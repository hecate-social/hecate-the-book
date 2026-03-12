# Chapter 6: The Event Store

*Raft consensus on the BEAM, streams as truth*

---

Chapter 1 introduced the dossier — a folder of event slips that accumulates history as a process unfolds. That metaphor is clean and powerful. But metaphors don't survive contact with production. Somewhere, those slips have to be stored. Somewhere, the filing cabinet has to live. And in a distributed system where multiple nodes might try to add a slip to the same dossier simultaneously, that filing cabinet needs to handle concurrency without losing data.

This is the event store's job. And like everything else in this stack, we built our own. (I can already hear you groaning. "You built your own database?" Yes. And I'd do it again. Let me explain why before you close the book.)

---

## Why Not Use an Existing One?

EventStoreDB exists. It's mature, well-documented, and purpose-built for event sourcing. We used it for a while. I genuinely liked it. Then we hit the wall that every BEAM developer hits with external dependencies: operational coupling.

I've been managing external database dependencies since the early '90s — Oracle on Solaris, DB2 on AS/400, Sybase on HP-UX, SQL Server on Windows NT, PostgreSQL on Linux. The technology changes. The operational pain doesn't. You always end up with two systems that need to be healthy for one application to function. You always end up on call for a process you didn't write and don't fully control. You always end up debugging the gap between "the application is fine" and "the database isn't responding."

Running EventStoreDB means running a JVM process alongside your BEAM node. Running an external database alongside your BEAM node is like bringing a diesel generator to a house that already has solar panels — technically more power, practically more problems. It means a TCP connection between them. It means monitoring, health checks, restart coordination, and the inevitable 3 AM page when the JVM runs out of heap space and your BEAM application — which was fine, which was *happily processing messages* — can't write events. I remember the exact incident that broke us: a Saturday morning, the BEAM node had been running flawlessly for weeks, and EventStoreDB decided it needed a full GC that took 11 seconds. The JVM paused for garbage collection. Our event store paused for sympathy. Eleven seconds of write timeouts in an event-sourced system. Every aggregate that tried to process a command during that window failed. Users saw errors. The BEAM was healthy. The event store was not. And there was nothing our code could do about it. I'd lived this exact scenario with Oracle RAC in 2003, with Cassandra in 2015, and here it was again in 2025 wearing a different hat.

ReckonDB is a BEAM-native event store. It runs inside the BEAM VM, as an OTP application, supervised by the same supervision tree as the rest of your system. When your BEAM node starts, the event store starts. When your BEAM node stops, the event store stops. No external processes. No network connections. No impedance mismatch. No more "the database is fine but the connection pool is exhausted" incidents.

The storage layer is Khepri, which is built on Ra — an Erlang implementation of the Raft consensus protocol. Ra handles leader election, log replication, and snapshotting. Khepri provides a tree-structured key-value store on top of Ra. ReckonDB provides the event sourcing semantics on top of Khepri.

The result is an event store that speaks Erlang natively, clusters with other BEAM nodes using standard Erlang distribution, and participates in your application's supervision tree like any other OTP application. When it crashes, the supervisor restarts it. When it recovers, it's already there — no reconnection, no handshake, no "waiting for the database to come back." It's just another process in the tree.

---

## Streams: The Core Abstraction

Everything in ReckonDB is a stream. A stream is an ordered, append-only sequence of events identified by a string:

```
order-4821
capability-mri:capability:io.macula/weather
division-planning-7f3a9b2e
```

Each stream has a version — a monotonically increasing integer that starts at 0 and increments with every appended event. The version is the optimistic concurrency control mechanism, and it's the thing that makes event sourcing safe in concurrent systems. (I'll spend a whole section on this, because it's the single most important concept in the event store. If you only remember one thing from this chapter, make it this.)

If you've spent time with database internals, none of this is conceptually new. The write-ahead log in PostgreSQL is an append-only stream. The redo log in Oracle is an append-only stream. Transaction journals on AS/400 were append-only streams. Bank ledgers have been append-only for centuries — you never erase an entry, you add a correcting entry. Greg Young formalized "event sourcing" around 2005, but the pattern existed in banking systems and mainframe transaction processing for decades before that. What's new here isn't the append-only log. What's new is making it the primary data model instead of hiding it as an implementation detail behind a mutable table.

The streams API is small. Deliberately so:

```erlang
%% Append events to a stream (with optimistic concurrency)
esdb_gater_api:append(StoreName, StreamId, ExpectedVersion, Events).

%% Read events from a stream
esdb_gater_api:read(StoreName, StreamId, StartVersion, Count).

%% Read all events across all streams (for projections)
esdb_gater_api:read_all(StoreName, StartPosition, Count).

%% Get the current version of a stream
esdb_gater_api:get_version(StoreName, StreamId).

%% Check if a stream exists
esdb_gater_api:exists(StoreName, StreamId).

%% List all streams
esdb_gater_api:list_streams(StoreName).

%% Delete a stream
esdb_gater_api:delete(StoreName, StreamId).
```

Seven operations. That's the entire write and read surface for stored events. That's fewer API operations than most REST endpoints have for a single entity. We considered adding an eighth, but that felt decadent. No query language. No indexes. No secondary lookups. Streams go in, streams come out. Everything else — querying, filtering, aggregating — happens in projections (Chapter 7), where it belongs.

We went through three iterations of this API before landing on "seven operations." The first version had fourteen. The second had twenty-two (don't ask). Every time we added a "convenience" operation, it turned into a leaky abstraction that encouraged people to use the event store as a general-purpose database. It isn't one. It's a filing cabinet. Filing cabinets don't have query languages. I learned this lesson the hard way with CQRS implementations earlier in my career — the moment your event store grows a query API, someone will use it as a read model, and then you've lost the entire architectural benefit.

---

## Optimistic Concurrency: The Expected Version

The `ExpectedVersion` parameter on `append` is the most important concept in the event store. It's how you prevent two concurrent processes from corrupting a stream. It's also, in my experience, the concept that takes the longest to truly click for developers coming from CRUD systems.

Consider two users trying to ship the same order simultaneously. Without concurrency control:

```
Process A: reads order stream (version 3)
Process B: reads order stream (version 3)
Process A: appends order_shipped_v1 (version 4)
Process B: appends order_shipped_v1 (version 5)  ← WRONG! Shipped twice!
```

With expected version:

```
Process A: reads order stream (version 3)
Process B: reads order stream (version 3)
Process A: appends order_shipped_v1, expected_version=3 → SUCCESS (now version 4)
Process B: appends order_shipped_v1, expected_version=3 → FAILS! Version is now 4!
```

Process B's append fails because the stream's version has moved past what B expected. B must re-read the stream, re-evaluate its business rules against the new state (which now includes the shipping event), and decide whether to retry. This is the beauty of it: B doesn't just get a generic "conflict" error. It's forced to reconsider whether its intended action still makes sense given what happened in the meantime. In the order shipping example, B would re-read the stream, discover the order is already shipped, and correctly decide to do nothing. Optimistic concurrency is the technical term for "hope for the best, plan for the worst." Which, come to think of it, is also my career motto.

If this reminds you of HTTP ETags or CAS (Compare-And-Swap) operations, it should. It's the same fundamental idea — test-and-set — applied at the stream level. I first encountered this pattern in the early '90s with multi-version concurrency control in database systems. The mechanism is timeless.

The expected version has three special values:

```
-1  NO_STREAM    — The stream must NOT exist. Used for "birth"
                   events: initiate_venture, register_user.
                   If the stream already exists, the append fails.

-2  ANY_VERSION  — Skip the concurrency check. Append regardless
                   of current version. Used for event types where
                   duplicates are harmless or handled downstream.

N >= 0           — Exact match. The stream's current version must
                   be exactly N. This is the normal case.
```

`NO_STREAM` is particularly elegant — it's the solution to a problem that has plagued distributed systems since I first started building them. When you initiate a new venture, the command handler appends `venture_initiated_v1` with expected version -1. If two nodes try to initiate the same venture simultaneously, exactly one succeeds and the other gets a version conflict. The dossier is created exactly once. No distributed lock. No external coordination. Just a version check. Simple, deterministic, and it scales to a million concurrent creates without breaking a sweat.

This is strong consistency for a single stream. It's important to understand the scope: ReckonDB guarantees ordering and uniqueness within a stream. Across streams, events are independent. There's no distributed transaction that spans multiple streams, and there shouldn't be — each dossier is autonomous.

---

## The Event Record

Events are maps with a fixed structure:

```erlang
#{
    event_type  => <<"VentureInitiated.v1">>,
    stream_id   => <<"venture-abc123">>,
    version     => 0,
    data        => #{
        <<"venture_id">> => <<"abc123">>,
        <<"name">> => <<"Weather Station">>,
        <<"initiated_by">> => <<"agent-jane">>
    },
    metadata    => #{
        <<"correlation_id">> => <<"corr-789">>,
        <<"causation_id">> => <<"cmd-456">>,
        <<"source">> => <<"guide_venture_lifecycle">>
    },
    tags        => [<<"venture">>, <<"lifecycle">>],
    timestamp   => <<"2026-03-12T10:30:00Z">>,
    epoch_us    => 1741772400000000
}
```

The `data` field is the business payload — what happened. The `metadata` field is the operational context — who caused it, what correlated with it, where it came from. Tags enable filtering without parsing. The microsecond epoch enables precise temporal ordering.

The `correlation_id` chains related events together. When a user submits a command that triggers a process manager that dispatches another command that produces another event, all of these share the same correlation ID. You can trace a complete causal chain — from the user's click to the final side effect — by filtering on one string. I cannot tell you how many hours of debugging this has saved us. When something goes wrong in an event-sourced system, the first question is always "what caused this?" The correlation ID answers that question instantly. After thirty-five years of debugging distributed systems — from mainframe hex dumps to Wireshark traces — having a single string that threads the entire causal chain is the kind of tooling I dreamed about in 1995.

The `causation_id` is more specific: it points to the immediate cause. The event was caused by this command. That command was caused by this process manager. The process manager was triggered by this event. It's a linked list of cause and effect. Together, correlation and causation IDs give you a full genealogy of every event in your system. When I'm debugging a weird state, I follow the causation chain backward until I find the originating command. It's like forensic accounting, and it's oddly satisfying.

---

## Subscriptions: Reacting to Events

Storing events is half the job. The other half is notifying interested parties when new events appear. ReckonDB supports four subscription types, each matching a different use case:

**Stream subscriptions** follow a single stream. When a new event is appended to `venture-abc123`, all stream subscribers for that stream receive it. This is what an aggregate uses to stay up to date.

**Event type subscriptions** follow a specific event type across ALL streams. When ANY stream gets a `VentureInitiated.v1` event, subscribers for that type receive it. This is what projections and process managers use — they care about what happened, not where it happened.

**Event pattern subscriptions** use wildcards on event types. Subscribe to `Venture*.v1` and you'll get `VentureInitiated.v1`, `VisionSubmitted.v1`, and every other v1 event in the venture domain. Useful for domain-level logging and auditing.

**Event payload subscriptions** filter on the content of the event data. Subscribe to events where `data.amount > 10000` for fraud detection. This is the most specific — and most expensive — subscription type.

The critical design choice here: **per-event-type subscriptions, not per-stream.** This took us a while to get right. Our first implementation used per-stream subscriptions for everything. It worked fine with 100 aggregates. At 10,000 it was sluggish. We did some napkin math for a million and realized we'd need a million subscriptions for a single projection. That's not scaling — that's a memory leak with aspirations.

With per-event-type subscriptions, the number of subscriptions is proportional to the number of event types (tens to hundreds), not the number of aggregates (potentially millions). You want ONE subscription for the `OrderShipped.v1` event type, and you'll receive that event regardless of which stream it appears in. This is what makes event-sourced systems scale.

```erlang
%% Emitter groups — named groups that receive events
%% Multiple consumers can share a group for load balancing
esdb_gater_api:subscribe(StoreName, #{
    subscription_type => event_type,
    event_type => <<"PluginInstalled.v1">>,
    group => <<"plugin_projection">>
}).
```

---

## Writer and Reader Pools

ReckonDB uses pooled workers for both reads and writes — 10 of each by default. This isn't arbitrary. (Well, okay, 10 is somewhat arbitrary. It's the software engineer's favorite round number — small enough to seem disciplined, large enough to seem serious. But the principle isn't.)

Write operations (appending events) involve Raft consensus, which means leader coordination and log replication. These are inherently slower than reads. Read operations (loading streams) hit the local Khepri store directly.

Separate pools prevent a burst of reads from starving writes, and vice versa. If your system is projection-heavy (lots of read_all scans), the readers stay busy while writers continue appending events unimpeded. If you're command-heavy (lots of appends), the writers queue up while readers continue serving queries.

We learned the importance of separate pools the embarrassing way: an early version used a single shared pool, and a projection rebuild (which hammered read_all in a tight loop) blocked command processing for forty-five seconds. Every user action during that window got a timeout. The same lesson every DBA learns with database connection pools — separate your workloads — applied at a different level of the stack. Separate pools, separate problems.

The pool sizes are configurable per store. A system that's read-heavy might run 5 writers and 20 readers. A system that's write-heavy might invert that ratio.

---

## Multi-Store Configuration

ReckonDB supports multiple independent event stores in a single BEAM node. Each store has its own data directory, its own Raft cluster, its own reader/writer pools:

```erlang
%% In sys.config or application env
{reckon_db, [
    {stores, [
        #{name => settings_store,
          data_dir => "/bulk0/hecate/stores/settings"},
        #{name => llm_store,
          data_dir => "/bulk0/hecate/stores/llm"},
        #{name => plugins_store,
          data_dir => "/bulk0/hecate/stores/plugins"},
        #{name => licenses_store,
          data_dir => "/bulk0/hecate/stores/licenses"}
    ]},
    {mode, single}  %% or 'cluster' for multi-node
]}
```

Each store is a bounded context's filing cabinet. The settings store doesn't know about the plugins store. The LLM store doesn't know about the licenses store. They share a BEAM node but nothing else.

This maps directly to the domain model: each division (bounded context) owns its events. There's no global event store that everyone writes to — that would create coupling. I've seen what happens with shared event stores. I've also seen what happens with shared Oracle schemas, shared DB2 tablespaces, and shared Sybase databases. The technology changes; the coupling disaster is always the same. A schema change in one domain breaks projections in three others. A migration in one context locks tables that another context needs. Never again. Each context has its own truth, its own history, its own replay capability. If the plugins store gets corrupted (it hasn't, but if it did), the settings store doesn't care. Isolation is the whole point.

---

## Clustering: Raft on the BEAM

In single-node mode, ReckonDB stores everything locally. In cluster mode, Ra kicks in. Multiple BEAM nodes form a Raft group, and each event append goes through the Raft consensus protocol:

1. The client sends an append to any node
2. If it's not the leader, it forwards to the leader
3. The leader writes the event to its log
4. The leader replicates the log entry to followers
5. When a majority acknowledges, the event is committed
6. The leader responds to the client

"Wait," I hear you saying, "didn't Chapter 5 just spend several pages arguing against leaders?" Yes. And here's the important distinction: the masterless mesh (Chapter 5) is for *inter-node* communication across the wide-area network, where availability matters more than consistency. The event store uses Raft for *intra-cluster* replication on a local network, where consistency matters more than availability. Different problems, different trade-offs. The mesh is AP. The event store is CP. They coexist because they serve different purposes.

This gives you strong consistency within a store — every node sees the same events in the same order — with automatic failover. If the leader crashes, the remaining nodes elect a new leader and continue. No manual intervention. No operator on-call. The BEAM's distribution mechanism handles the plumbing.

Cluster discovery uses the same mechanisms as any BEAM cluster: UDP multicast for local development, DNS for production, or Kubernetes headless services if you're in that world. Ra handles the Raft protocol once nodes find each other.

---

## Aggregation: fold as a Query

ReckonDB includes a fold-based aggregation mechanism for stream processing:

```erlang
%% Sum all amounts in a stream
esdb_gater_api:foldl(StoreName, StreamId,
    fun(Event, Acc) ->
        Amount = maps:get(<<"amount">>, maps:get(data, Event), 0),
        {sum, Amount}  %% Tagged value — sums accumulate
    end,
    {sum, 0}).

%% Get the latest value (last write wins)
esdb_gater_api:foldl(StoreName, StreamId,
    fun(Event, _Acc) ->
        {overwrite, maps:get(data, Event)}
    end,
    {overwrite, #{}}).
```

The tagged value system (`{sum, N}` and `{overwrite, V}`) tells the fold how to combine results. Sums accumulate. Overwrites replace. This is a simple but powerful mechanism for computing aggregate values without building a full projection. Think of it as a quick peek into a dossier's history — not a replacement for proper projections, but handy for debugging and one-off queries.

---

## The Filing Cabinet Contract

ReckonDB makes a small number of guarantees, and it's important to understand both what it promises and what it doesn't. This is the section I wish every event store's documentation led with, because the non-guarantees are just as important as the guarantees. I've been bitten by undocumented assumptions in database systems more times than I care to count — from Oracle's "read consistency" surprising people with ORA-01555, to Cassandra's "tunable consistency" silently losing writes.

**Guarantees:**
- Events in a stream are strictly ordered by version
- Optimistic concurrency prevents conflicting writes to the same stream
- Committed events are durable (replicated to a majority in cluster mode)
- Subscriptions deliver events at least once
- Stream versions are monotonically increasing with no gaps

**Non-guarantees:**
- No ordering across different streams
- No distributed transactions spanning multiple streams
- No exactly-once delivery (consumers must be idempotent)
- No global ordering of all events (read_all provides a local order, not a global one)

These non-guarantees aren't limitations — they're design choices. Cross-stream ordering would require a global sequence number, which would be a bottleneck. Exactly-once delivery is impossible in distributed systems (it's a theorem, not a shortcoming — if someone tells you their system has exactly-once delivery, they're either lying, redefining "exactly once," or selling you something. Possibly all three). Global ordering would serialize all writes through a single point.

The event store is a filing cabinet. Each drawer (stream) is perfectly ordered. The cabinet as a whole is not — and that's fine, because each dossier is an independent process with its own timeline.

What matters is that within a single dossier, every slip is in order, every slip is permanent, and no slip is ever lost. The filing cabinet keeps its promises. And after eighteen months of production use, I can say with confidence: it really does keep them.
