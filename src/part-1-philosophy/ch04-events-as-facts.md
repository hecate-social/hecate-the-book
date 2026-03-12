# Chapter 4: Events as Facts

*Why immutable history changes everything*

---

Let me tell you about the database update that cost us a customer.

In a traditional database, when a customer changes their shipping address, you UPDATE the address column. The old address is gone. It never existed. The database reflects the current state — and only the current state. A shared mutable database is like a whiteboard in a busy office — everyone writes on it, nobody erases properly, and by Friday it's a crime scene.

We had a customer who changed their shipping address after placing an order but before it shipped. The warehouse used the address from the database — the new one. The customer expected the package at their old address (they'd changed it for a *future* order). We had no way to know what the address was at the time of the order. The database only knew "now." It had no concept of "then."

I'd seen this exact failure mode before — on a mainframe system in 1993. A batch job overwrote a customer's credit limit, and we couldn't figure out what the limit had been when the original transaction was authorized. The technology was completely different — VSAM files instead of PostgreSQL, COBOL instead of whatever we're using now — but the root cause was identical: mutable state destroys history. The fix on the mainframe was to add an audit trail. The fix in the 2000s was to add an audit table. The fix now — our fix — is to stop overwriting things in the first place.

In an event-sourced system, you append a new event: `shipping_address_changed_v1`. The old address is still there, in the `shipping_address_set_v1` event from three months ago. Both are facts. Both are true. One describes what happened in January; the other describes what happened in March. And critically, you can ask: "What was the shipping address when order #4821 was placed?" The event stream gives you an unambiguous answer.

This chapter is about what happens when you take this idea seriously. Spoiler: it changes more than you'd expect.

---

## The Nature of Events

An event is a fact about something that happened. Not something that should happen (that's a command). Not something that could happen (that's a speculation). Something that DID happen, past tense, recorded at the moment it occurred.

```
capability_announced_v1     — a capability was announced
payment_received_v1         — a payment was received
division_identified_v1      — a division was identified
order_shipped_v1            — an order was shipped
vision_submitted_v1         — a vision was submitted
```

Events are named in past tense because they describe the past. By the time you read an event, it has already happened. The decision was already made. The business logic already ran. The event is a record of the outcome.

This has a profound consequence: **events are immutable.** You cannot change what happened. You can append new events that represent new facts (a correction, a reversal, a modification), but you cannot alter the historical record.

The first time this principle truly sank in for me, it felt like remembering something I'd always known. A colleague asked, "But what if the event has a bug? What if we recorded the wrong amount?" And before I could think about it in software terms, the answer came from decades of working with financial systems: you don't fix the event. You append a correction event. `payment_amount_corrected_v1`. The original event stays, because it's a fact about what the system *did*, even if what it did was wrong. The correction is a new fact about what happened next. This is exactly how double-entry bookkeeping has worked since Luca Pacioli described it in 1494. It's how bank transaction logs worked on every mainframe I touched in the nineties. It's how database write-ahead logs work. The concept isn't new — it's ancient. Greg Young just gave it a name that software engineers recognized.

In code, this means events are created once and never modified:

```erlang
%% Event creation — happens once, in the handler
order_shipped_v1:new(State, Command) ->
    #{
        event_type => <<"OrderShipped.v1">>,
        order_id => State#order_state.order_id,
        customer_id => State#order_state.customer_id,
        carrier => maps:get(<<"carrier">>, Command#evoq_command.payload),
        tracking_number => maps:get(<<"tracking_number">>, Command#evoq_command.payload),
        shipped_at => erlang:system_time(millisecond)
    }.
```

Once this event is appended to the event store, it's permanent. The order was shipped by this carrier with this tracking number at this time. Future events may add new information (a delivery confirmation, a return initiation), but this event stands unchanged.

---

## The Event Envelope

Raw business events don't travel alone. In Hecate's stack, every event is wrapped in an envelope that carries metadata:

```erlang
#evoq_event{
    event_id       = <<"550e8400-e29b-41d4-a716-446655440000">>,
    event_type     = <<"OrderShipped.v1">>,
    stream_id      = <<"order-4821">>,
    version        = 3,
    data           = #{
        <<"order_id">>     => <<"4821">>,
        <<"carrier">>      => <<"fedex">>,
        <<"tracking">>     => <<"FX123456789">>
    },
    metadata       = #{
        <<"causation_id">>   => <<"cmd-abc-123">>,
        <<"correlation_id">> => <<"req-xyz-789">>,
        <<"user_id">>        => <<"user-42">>,
        <<"timestamp">>      => 1709312400000
    },
    tags           = [<<"tenant:acme">>, <<"priority:high">>],
    timestamp      = 1709312400000,
    epoch_us       = 1709312400000000
}
```

The envelope separates concerns. Business data (what happened) goes in `data`. Infrastructure metadata (who, when, why) goes in `metadata`. Cross-stream query hints go in `tags`. The event store (ReckonDB) manages the envelope; your domain code only produces the `data` and `event_type`.

The `causation_id` links each event to the command that caused it. This creates a causal chain: command A produced event B, which triggered process manager C, which dispatched command D, which produced event E. When something goes wrong at event E, you can trace backward through the causation chain to understand the full sequence.

If you've spent any time debugging distributed systems — and I've been doing it since CORBA and DCOM in the mid-nineties — you know that the hardest part is reconstructing the sequence of events across process boundaries. We used to correlate timestamps across log files on different servers, accounting for clock skew, hoping the log levels were consistent. The causation chain replaces all of that. It's like a breadcrumb trail that was laid down automatically, at write time, when nobody was thinking about debugging. The first time I used it to trace a production issue, I found the root cause in under five minutes. The same class of issue in our old SOAP-based system would have been a multi-hour investigation involving three teams and a shared spreadsheet.

The `correlation_id` is broader — it ties together all events and commands that originated from a single external request. A user clicks "place order" and a correlation ID is assigned. Every event produced as a result shares that correlation ID, across all bounded contexts, across all process managers. One ID, one complete story of what a single user action caused.

---

## Versioning Events

Events are immutable, but understanding evolves. Today's `order_shipped_v1` might not carry the warehouse ID, but tomorrow you realize you need it. You can't change existing events — they're facts about what happened when the system didn't know about warehouses.

I've been through this exact situation on every system that lasted more than a year. In the traditional world, the answer is always `ALTER TABLE` followed by a backfill script and a prayer. In the event-sourced world, the answer is versioning:

```erlang
%% v1: original event (still in the event store)
#{event_type => <<"OrderShipped.v1">>,
  order_id => <<"4821">>,
  carrier => <<"fedex">>,
  tracking_number => <<"FX123456789">>}

%% v2: new events get the warehouse field
#{event_type => <<"OrderShipped.v2">>,
  order_id => <<"4821">>,
  carrier => <<"fedex">>,
  tracking_number => <<"FX123456789">>,
  warehouse_id => <<"wh-east-1">>}
```

When replaying events to rebuild state, the aggregate handles both versions:

```erlang
apply(State, #{event_type := <<"OrderShipped.v1">>, data := Data}) ->
    State#order_state{
        status = evoq_bit_flags:set(State#order_state.status, ?SHIPPED),
        carrier = maps:get(<<"carrier">>, Data),
        tracking = maps:get(<<"tracking_number">>, Data),
        warehouse_id = undefined
    };

apply(State, #{event_type := <<"OrderShipped.v2">>, data := Data}) ->
    State#order_state{
        status = evoq_bit_flags:set(State#order_state.status, ?SHIPPED),
        carrier = maps:get(<<"carrier">>, Data),
        tracking = maps:get(<<"tracking_number">>, Data),
        warehouse_id = maps:get(<<"warehouse_id">>, Data)
    }.
```

For more complex transformations, evoq supports **event upcasters** — modules that transform old event versions into new ones during replay:

```erlang
-module(order_shipped_upcaster).
-behaviour(evoq_event_upcaster).

upcast(#{event_type := <<"OrderShipped.v1">>} = Event) ->
    Data = maps:get(data, Event),
    NewData = Data#{<<"warehouse_id">> => <<"unknown">>},
    Event#{event_type => <<"OrderShipped.v2">>, data => NewData}.
```

The upcaster runs during replay, transparently converting v1 events to v2. The aggregate only sees v2. The original v1 event remains unchanged in the store.

Compare this to the road most traveled: `ALTER TABLE orders ADD COLUMN warehouse_id;` followed by a backfill script that guesses at warehouse IDs for historical records. The migration runs once, prays it doesn't timeout on a table with millions of rows, and if something goes wrong... well, you'd better have a backup. (The number of production `ALTER TABLE` statements that have been preceded by the words "this should be fine" is a number I try not to think about.) I've been through enough failed migrations — on Oracle, on SQL Server, on PostgreSQL — to have a deep appreciation for how boring event versioning is by comparison. And boring is exactly what you want for data evolution.

---

## Events vs. Commands

The distinction between events and commands is fundamental, and worth being crystal clear about:

**Commands are requests.** They express intent. They may succeed or fail. They're named as imperatives: `place_order`, `ship_order`, `cancel_order`. A command says: "I want this to happen."

**Events are facts.** They describe outcomes. They cannot fail — they already happened. They're named in past tense: `order_placed`, `order_shipped`, `order_cancelled`. An event says: "This happened."

```
Command: place_order_v1
  ├── Validation passes → Event: order_placed_v1
  └── Validation fails  → Error: insufficient_stock

Event: order_placed_v1
  └── Always accepted. It happened. Deal with it.
```

Handlers receive commands and decide whether to produce events. Once an event is produced, it's final. There's no "event validation" — events represent historical facts, and facts aren't validated, they're recorded.

This distinction tripped us up early on. We had developers writing code that tried to "reject" events during projection. "This event doesn't look right, let's skip it." No. If the event is in the store, it happened. If it shouldn't have happened, that's a bug in the command handler, not the projection. Fix the handler. Append a correction event. But never, ever pretend an event didn't happen. This is the same principle that makes bank reconciliation work — you don't erase transactions that look wrong, you add adjusting entries. The financial industry learned this lesson centuries ago. We just keep rediscovering it in software.

This is why event naming matters. `order_updated` is a terrible event name because it doesn't tell you what happened. `shipping_address_changed_v1`, `quantity_adjusted_v1`, `coupon_applied_v1` — these are facts. Each carries specific data about a specific thing that happened.

---

## The Event Store as Source of Truth

![Event Sourcing vs CRUD](assets/event-sourcing-vs-crud.svg)

In a traditional system, the database is the source of truth. Tables hold current state. History is lost.

In an event-sourced system, the event store is the source of truth. Events hold the complete history. Current state is derived.

ReckonDB, the event store in the Hecate stack, implements this through event streams:

```erlang
%% Append events to a stream (with optimistic concurrency)
{ok, NewVersion} = reckon_db_streams:append(
    martha_store,
    <<"order-4821">>,
    2,                      %% expected version (optimistic concurrency)
    [OrderShippedEvent]
).

%% Read events from a stream
{ok, Events} = reckon_db_streams:read(
    martha_store,
    <<"order-4821">>,
    0,                      %% from version
    100,                    %% count
    forward
).
```

Optimistic concurrency prevents conflicts: if two processes try to append to the same stream simultaneously, only one succeeds. The other gets `{error, {wrong_expected_version, Expected, Actual}}` and must retry with the updated state. This is how event sourcing handles concurrent writes without locks.

If you've worked with database systems long enough, you recognize this as a variation of optimistic locking — the same pattern that's been used in database systems since the 1980s. The difference is that here, the "lock" is on a stream of facts rather than on a mutable row. In practice, conflicts are rare for the same stream, and when they do happen, the retry is fast. The aggregate reloads (a few events to replay), re-evaluates the command, and appends. We've had this in production for over a year with thousands of streams, and optimistic concurrency conflicts account for less than 0.1% of operations. The ones that do conflict are resolved in milliseconds.

ReckonDB uses Raft consensus (via Khepri/Ra) for durability and replication. Events, once appended, survive node failures. The Raft log IS the event log — consistency and durability are the same mechanism.

---

## Subscriptions: Reacting to Facts

Events aren't just stored — they're distributed. Multiple consumers need to react to the same events: projections update read models, process managers trigger follow-up commands, emitters publish to external systems.

ReckonDB supports four subscription types:

**Stream subscriptions** — watch events from a specific dossier.

**Event type subscriptions** — watch all events of a specific type across all dossiers. This is the critical one for scalability. In a system with a million orders, you don't want a million stream subscriptions. You want one event type subscription that catches every `OrderShipped.v1` regardless of which order produced it.

**Pattern subscriptions** — wildcards across stream IDs: `order-*` catches all order streams.

**Payload subscriptions** — match on event data: `#{total => {gt, 10000}}` catches high-value orders.

The subscription system is the distribution backbone. It's what makes the CQRS pattern work: commands go in, events come out, and multiple independent consumers react without knowing about each other. Each consumer sees the same events but does something completely different with them. The projection builds a read model. The process manager kicks off a new workflow. The emitter publishes to an external system. They're all independent. They can be added, removed, or rebuilt without affecting each other.

---

## Domain Events vs. Integration Facts

Not all events should leave your bounded context. This was a mistake we almost made — and having lived through the "publish everything to the ESB" era of SOA in the mid-2000s, I recognized the smell immediately.

The temptation is obvious: "We have all these beautiful events flowing through the system. Let's just publish them all to the mesh so other services can consume them!" It sounds efficient. It's the distributed systems equivalent of posting your diary online and being surprised when people quote it back to you in unexpected contexts. I watched this exact pattern bring an enterprise SOA to its knees around 2007 — internal domain changes cascaded through the service bus to dozens of consumers, each breaking in its own creative way. The industry then spent a decade slowly rediscovering the concept of "public API vs. internal implementation." We don't need to make that mistake again.

Domain events are internal — they're implementation details. Integration facts are external — they're public contracts.

| Aspect | Domain Events | Integration Facts |
|--------|--------------|-------------------|
| **Scope** | Internal to one bounded context | Cross-context, external |
| **Stability** | May change with implementation | Stable public contract |
| **Audience** | Projections, process managers | Other bounded contexts |
| **Storage** | Local event store (ReckonDB) | Mesh network |

The anti-pattern is bridging all domain events directly to the mesh. This leaks internal implementation details and couples external consumers to your aggregate's internal structure. When you refactor your aggregate (and you will), every external consumer breaks.

The correct pattern uses process managers as explicit translation points:

```
Domain Event (internal)          Integration Fact (external)
────────────────────────         ─────────────────────────
order_shipped_v1          ──PM──►  shipment_dispatched_v1
(internal structure)              (public contract, curated subset)
```

The process manager decides what to publish, how to shape it, and when to send it. In Hecate, internal events go via `_to_pg` emitters (OTP process groups). External facts go via `_to_mesh` emitters (the macula peer-to-peer network). The distinction is architectural: `pg` is internal, `mesh` is external.

The process manager is a firewall between your internal domain and the outside world. It gives you the freedom to refactor your internal events without breaking external consumers. That freedom is worth the extra indirection. After three decades of watching tight coupling destroy systems — from CORBA interface dependencies to SOAP schema changes to microservice API versioning nightmares — I can tell you that a little indirection at the boundary saves enormous pain downstream.

---

## Temporal Queries

One of the most powerful consequences of immutable history is temporal queries — the ability to ask "what was the state at time T?"

In a traditional system, this requires audit tables, change data capture, or a separate history mechanism that someone has to build and maintain. In an event-sourced system, it's built in:

```erlang
%% What was the order's state on March 1st?
{ok, Events} = reckon_db_streams:read(Store, <<"order-4821">>, 0, 1000, forward),
EventsBeforeMarch = [E || E <- Events, E#evoq_event.timestamp =< March1],
State = lists:foldl(fun apply_event/2, initial_state(), EventsBeforeMarch).
```

Replay events up to the desired timestamp. The resulting state is what the system knew at that moment.

This enables scenarios that would be expensive or impossible with mutable state:
- "What was the customer's shipping address when we shipped order #4821?"
- "How did the aggregate's status change over time?"
- "If we had applied this business rule three months ago, what would have happened?"

That last one is particularly powerful. We used it to evaluate a proposed pricing change by replaying three months of order events with the new pricing logic. The results told us exactly how revenue would have differed. No guessing, no spreadsheet models — just replay the history with different rules and see what happens. I'd spent years on traditional systems where this kind of analysis required a data warehouse team, an ETL pipeline, and three weeks. Here it was an afternoon of coding and a few minutes of replay. Our finance team thought it was magic. It's not magic. It's just immutable history — the same principle that lets a bank reconstruct any account balance at any point in time from its transaction log.

---

## The Projection Pattern

Events are optimized for writes: append-only, sequentially ordered, one stream per entity. They're terrible for reads: finding all orders by a specific customer requires scanning every order stream.

Projections bridge this gap. A projection subscribes to event types and builds a read-optimized view:

```erlang
-module(order_lifecycle_to_orders_by_customer).
-behaviour(evoq_projection).

interested_in() ->
    [<<"OrderPlaced.v1">>, <<"OrderShipped.v1">>, <<"OrderCancelled.v1">>].

project(#{event_type := <<"OrderPlaced.v1">>} = Event, _Meta, State, RM) ->
    Data = maps:get(data, Event),
    CustomerId = maps:get(<<"customer_id">>, Data),
    OrderId = maps:get(<<"order_id">>, Data),
    Order = #{id => OrderId, customer_id => CustomerId, status => <<"placed">>},
    {ok, NewRM} = evoq_read_model:put({CustomerId, OrderId}, Order, RM),
    {ok, State, NewRM}.
```

The projection is disposable. Delete the ETS table. Replay all events. Get the same result. The event store is the truth; the projection is a convenient view.

This disposability is one of those things that sounds nice in theory but really hits home when you need it. We had a projection bug that was silently corrupting a read model for two weeks. In a traditional system, that's a data recovery nightmare — I've been through enough of them to know the drill: restore from backups, run migration scripts, pray you don't lose data, spend a week reconciling. For us, we fixed the projection code, deleted the ETS table, and replayed events. The read model rebuilt itself perfectly from the source of truth. Total downtime: about ninety seconds. After thirty-five years of database recovery procedures, that felt like cheating.

Critical rule: **one ETS table = one projection module.** Multiple projection modules writing to the same table will race — each is a separate gen_server with no ordering guarantee between them. Merge them into a single module that handles all relevant event types. We learned this one the hard way, too. Two projections writing to the same table, events arriving in different orders, subtle data corruption that only manifested under load. If you've ever debugged a race condition in a concurrent system, you know the particular misery of bugs that only appear under load and disappear when you add logging. Merge the projections. One table, one writer.

---

## Bit Flags as Compact State

Events accumulate status. An order starts empty, gets placed, gets paid, gets shipped. Hecate represents aggregate status as bit flags — a single integer where each bit represents a boolean state:

```erlang
-define(PLACED,     1).   %% 2^0
-define(PAID,       2).   %% 2^1
-define(RESERVED,   4).   %% 2^2
-define(SHIPPED,    8).   %% 2^3
-define(DELIVERED, 16).   %% 2^4
-define(CANCELLED, 32).   %% 2^5
```

A shipped, paid order has status `11` (8 + 2 + 1 = SHIPPED + PAID + PLACED). Checking status is a bitwise operation:

```erlang
evoq_bit_flags:has(Status, ?SHIPPED) -> true | false

can_cancel(#order{status = S}) ->
    not evoq_bit_flags:has_any(S, [?SHIPPED, ?DELIVERED, ?CANCELLED]).
```

This is a design choice that aligns with event sourcing: each event potentially sets or clears bits, and the current status is the bitwise accumulation of all state changes. It's compact (one integer instead of a list of booleans), it's fast (CPU-native operations), and it's queryable (bitwise operators work in SQL). If you've worked with Unix file permissions or C-style flags enums, this will feel immediately familiar — it's one of the oldest patterns in computing, and it's still one of the most efficient. Chapter 8 explores this pattern in depth.

---

## What Events Change About Your System

Taking events seriously changes the character of your system in ways that accumulate over time. Some of these benefits we anticipated. Others surprised us — and after three decades, I'm not easily surprised.

**Debugging becomes reading, not guessing.** When a bug report comes in, you load the affected stream and read the events. The sequence of what happened is right there, in order, with timestamps and causation chains. No log correlation. No reproduction steps. The story is already written.

**Compliance becomes trivial.** Financial regulations require audit trails. Health regulations require change history. Event-sourced systems provide both for free — the event store IS the audit trail. We had an auditor ask for "a complete history of all changes to this account." We gave them the event stream. They'd never seen anything like it. Usually that request takes a team weeks to compile from scattered logs. I've been on the receiving end of those audit requests on traditional systems — it's never fun.

**Feature flagging becomes projection selection.** Want to show users a new dashboard? Build a new projection. Don't like it? Delete the projection. The event stream is unaffected. The old dashboard's projection is still there, still working. Zero risk.

**Schema migration becomes event versioning.** No ALTER TABLE. No migration scripts. No downtime. No 3 AM "maintenance window" that was supposed to take twenty minutes and is now entering hour four. New event versions carry new fields. Old events remain unchanged. Upcasters transform during replay.

**Testing becomes deterministic.** Given these events, does the aggregate produce the correct state? Given this state and this command, does the handler produce the correct events? No database setup. No mock services. Pure function composition. Our test suite runs in seconds, not minutes, because there's no I/O.

The trade-off is complexity. Event-sourced systems have more moving parts. You need to understand eventual consistency (which, in some systems, turns out to mean "eventually consistent, where 'eventually' is doing a suspicious amount of heavy lifting"). You need to design for idempotent consumers. You need to think about event versioning and upcasting. The learning curve is real, and it takes time for a team to internalize the patterns.

But the trade-off pays for itself the first time you need to understand why a system did what it did, and the answer is sitting right there in the event stream — complete, immutable, and unambiguous. No guessing. No "I think what happened was..." Just: here's what happened. Here's the order. Here's the causation chain. Here's where it went wrong. After thirty-five years of debugging systems that couldn't explain themselves, I can tell you: that clarity is worth every bit of the added complexity.

Events are sacred. They are the source of truth. They describe what happened, not what we wish had happened.

Append only. Never mutate. Never delete. That's the deal.
