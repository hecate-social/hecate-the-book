# Chapter 7: CQRS Without the Ceremony

*Aggregates, projections, process managers*

---

I didn't discover CQRS. I recognized it.

For years, every serious database deployment I'd worked on separated reads from writes at the infrastructure level. Read replicas in Oracle. Standby databases in DB2. Reporting servers that got nightly ETL loads from the OLTP system. The pattern was as old as relational databases themselves: the system that handles transactions is not the system that serves reports. Different workloads, different optimization strategies, different hardware sometimes. Every DBA I knew in the '90s understood this intuitively.

What Greg Young did around 2005 was take that infrastructure pattern and apply it at the application level. Separate the code that changes state from the code that reads state. Use one model for writes, a different model for reads. Let each side optimize independently. When I first read his writings, I didn't think "what a novel idea." I thought "of course — why weren't we doing this in our application code all along?"

Then I built a system with 50 concurrent users modifying shared state while a reporting dashboard queried that same state. The writes were locked waiting for reads. The reads were stale because writes were queued. Adding an index for the dashboard slowed down the writes. Optimizing the writes broke the dashboard query. Every improvement to one side was a regression on the other. The code compiled. The tests passed. The architecture was still terrible. The same problem I'd seen DBAs solve with read replicas, but at the application layer where nobody had thought to apply the same solution.

In practice, most CQRS implementations then proceed to drown in ceremony. You end up with a command bus, a command handler factory, a command validator, a command serializer, a command deserializer, an aggregate repository, an aggregate factory, a unit of work, and seventeen interfaces — all to change one field on one entity. It's like building a cathedral to store a Post-it note. If you lived through the Enterprise JavaBeans era, or suffered through SOAP/WSDL envelope ceremony, or maintained a J2EE application with its XML deployment descriptors and home/remote interface pairs, you'll recognize the disease immediately. The pattern disappears under the weight of its own infrastructure. I've seen Java CQRS codebases where you need to create six files to add a boolean field. I've also seen J2EE codebases where adding a method to an EJB required editing seven XML files. Different decade, same pathology.

The industry's answer was more abstraction. Ours was less. Evoq is our attempt to keep the pattern without the tax. It's an Erlang CQRS/Event Sourcing framework with 14 behaviours. That sounds like a lot. It isn't — because most of them are optional, and the ones you use daily are minimal: implement three callbacks, and you have a working aggregate. Implement two callbacks, and you have a projection. The framework handles the rest. No factories. No repositories. No "unit of work." Just behaviours and callbacks. After thirty-five years of watching frameworks oscillate between "too little" and "too much," evoq feels like we've finally landed on the right amount.

---

![CQRS Flow: Command to Query](assets/cqrs-flow.svg)

## The Aggregate: Your Dossier Reader

The aggregate is the central concept from Chapter 1, made concrete. It's the clerk who reads a dossier's slips and decides whether a new slip can be added.

In evoq, an aggregate implements three callbacks:

```erlang
-module(venture_aggregate).
-behaviour(evoq_aggregate).

%% What's the initial state of an empty dossier?
init(AggregateId) ->
    #{
        venture_id => AggregateId,
        status => 0,          %% bit flags — Chapter 8
        name => undefined,
        vision => undefined
    }.

%% Given the current state and a command, what events should happen?
%% State comes FIRST. This is not negotiable.
execute(#{status := Status} = State, #{command_type := <<"InitiateVenture.v1">>} = Cmd) ->
    case evoq_bit_flags:has(Status, ?INITIATED) of
        true  -> {error, already_initiated};
        false -> {ok, [venture_initiated_v1:new(Cmd)]}
    end;

execute(#{status := Status} = State, #{command_type := <<"SubmitVision.v1">>} = Cmd) ->
    case evoq_bit_flags:has(Status, ?INITIATED) of
        false -> {error, not_initiated};
        true  -> {ok, [vision_submitted_v1:new(State, Cmd)]}
    end.

%% Given the current state and an event, what's the new state?
%% This is a pure function. No side effects. No I/O. Just data in, data out.
apply(State, #{event_type := <<"VentureInitiated.v1">>, data := Data}) ->
    State#{
        status => evoq_bit_flags:set(maps:get(status, State), ?INITIATED),
        name => maps:get(<<"name">>, Data),
        initiated_at => maps:get(<<"initiated_at">>, Data)
    };

apply(State, #{event_type := <<"VisionSubmitted.v1">>, data := Data}) ->
    State#{
        status => evoq_bit_flags:set(maps:get(status, State), ?VISION_SUBMITTED),
        vision => maps:get(<<"vision">>, Data)
    }.
```

Three callbacks. That's it. `init` creates the blank dossier. `execute` is the business decision — can this command produce events given the current state? `apply` reads a slip and updates the clerk's understanding.

The distinction between `execute` and `apply` is the heart of event sourcing, and it's worth dwelling on because it represents a genuinely different way of thinking about state. `execute` runs only when processing new commands — it's where you say "no, you can't ship an unpaid order." `apply` runs during both command processing AND replay — it's how the aggregate rebuilds its state from history. Because `apply` runs during replay, it must be a pure function. No database calls. No API requests. No side effects. Just state transformation. The first time I accidentally put a logging call in `apply` and watched it fire 10,000 times during a replay, I understood this distinction viscerally. The same lesson every CQRS practitioner learns once, and only once.

---

## The Aggregate Lifecycle

Aggregates don't live forever. In a system with millions of dossiers, keeping them all in memory would be absurd. Evoq manages aggregate lifecycles automatically — and frankly, this is the part of the framework that saved us the most headaches:

**Activation.** When a command arrives for aggregate `venture-abc123`, evoq checks if that aggregate is already in memory. If not, it spawns a new process, loads all events from the event store, and replays them through `apply/2` to rebuild the current state.

**Passivation.** After 30 minutes of inactivity (no commands), the aggregate hibernates. After another period, it shuts down entirely. The state is gone from memory — but it's never gone from the event store. The next command will reactivate it. Aggregates are like cats: they sleep most of the time, wake up instantly when something interesting happens, and you shouldn't disturb them without good reason. If you've ever managed cache eviction policies or object pool lifecycles — and after thirty-five years I've managed more than I care to remember — you'll appreciate how clean this is compared to traditional ORM systems where "loading an entity" means a database query every time.

**Snapshotting.** Replaying 10,000 events to rebuild state is wasteful. Evoq takes snapshots every 100 events (configurable). On activation, it loads the latest snapshot and replays only the events after it. This is the difference between "activation takes 500ms" and "activation takes 2ms."

**Memory pressure.** When BEAM memory usage exceeds 70%, aggregate TTLs shrink to half. Above 85%, they shrink to a tenth. Aggregates passivate aggressively under pressure, freeing memory for the processes that are actually doing work.

```
Memory < 70%:   TTL = 30 minutes (normal)
Memory 70-85%:  TTL = 15 minutes (elevated)
Memory > 85%:   TTL =  3 minutes (critical)
```

**Partitioned supervision.** Aggregates are distributed across 4 supervisor partitions using consistent hashing on the aggregate ID. This prevents a single supervisor from becoming a bottleneck when thousands of aggregates activate simultaneously.

All of this is invisible to your code. You write `execute` and `apply`. Evoq handles the lifecycle. I find this deeply satisfying — the framework does the boring operational stuff so your code can focus entirely on business logic.

---

## Commands: The Desk's Inbox

A command is a request to do something. It's not a guarantee — the aggregate might reject it. Commands are maps with a required `command_type` field:

```erlang
-module(submit_vision_v1).

new(VentureId, Vision, SubmittedBy) ->
    #{
        command_type => <<"SubmitVision.v1">>,
        aggregate_type => venture_aggregate,
        aggregate_id => VentureId,
        data => #{
            <<"vision">> => Vision,
            <<"submitted_by">> => SubmittedBy
        }
    }.
```

Commands flow through a pipeline before reaching the aggregate. The pipeline is an ordered list of middleware — modules that can inspect, enrich, validate, or reject a command before it reaches `execute/2`:

```erlang
-module(validate_vision_length).
-behaviour(evoq_middleware).

before_dispatch(#{data := Data} = Pipeline) ->
    Vision = maps:get(<<"vision">>, Data, <<>>),
    case byte_size(Vision) > 50 of
        true  -> Pipeline;
        false -> evoq_pipeline:halt(Pipeline, {error, vision_too_short})
    end.

after_dispatch(Pipeline) -> Pipeline.
```

The pipeline record carries the command, a context map, an assigns map (for middleware to pass data to each other), a halted flag, and the eventual response. If any middleware halts the pipeline, the command never reaches the aggregate. This is where you do authorization checks, input validation, and request enrichment. (If you've used Plug in Elixir or Ring middleware in Clojure, this will feel familiar. It's the same idea: a chain of transforms with the ability to short-circuit. The pattern goes back to servlet filters in J2EE and even further to Unix pipes — every generation reinvents the middleware chain because it's a genuinely good idea.)

---

## Events: The Slip of Paper

Events are the immutable facts produced by successful commands. They have the same map structure as the event store's records, because they ARE the event store's records:

```erlang
-module(vision_submitted_v1).

new(State, Cmd) ->
    #{
        event_type => <<"VisionSubmitted.v1">>,
        data => #{
            <<"venture_id">> => maps:get(venture_id, State),
            <<"vision">> => maps:get(<<"vision">>, maps:get(data, Cmd)),
            <<"submitted_by">> => maps:get(<<"submitted_by">>, maps:get(data, Cmd)),
            <<"name">> => maps:get(name, State)  %% echoed from aggregate state
        }
    }.
```

Notice that the event carries both new data (the vision text, submitted_by) and echoed state (venture_id, name). This is the "default read model" principle from Chapter 1: events should carry enough data that downstream consumers don't need to look anything up. The process manager that reacts to this event will have everything it needs right in the payload. No joins. No lookups. No "go ask the database what the venture's name is." The event IS the answer.

---

## Event Handlers: Side Effects

Event handlers react to events by producing side effects. They publish messages to OTP process groups, send notifications to the mesh, trigger external API calls. They do NOT modify the aggregate's state — only `apply/2` does that.

```erlang
-module(vision_submitted_to_pg).
-behaviour(evoq_event_handler).

interested_in() ->
    [<<"VisionSubmitted.v1">>].

handle_event(EventType, EventData, Metadata, _State) ->
    pg:send(venture_events, {vision_submitted, EventData}),
    :ok.
```

The `interested_in/0` callback returns a list of event types this handler cares about. Evoq uses this to wire up subscriptions — one subscription per event type, not per aggregate. This is the constant-N subscription model from Chapter 6.

Error handling in event handlers is explicit. When `handle_event` fails, the handler can return `{retry, Delay}` to try again later, or `{dead_letter, Reason}` to park the event for manual investigation. Failed side effects don't block the event store or the aggregate — they're handled independently. This is important: a flaky email service doesn't stop your aggregate from processing commands. The two concerns are completely decoupled.

---

## Process Managers: The Automated Clerk

A process manager is a clerk that watches for events in one dossier and dispatches commands to another. It's the cross-domain integration point — the only sanctioned way for two bounded contexts to interact. If you're tempted to have Domain A directly call into Domain B, stop. Write a process manager. Your future self will thank you. I've been cleaning up tight coupling between domains for decades — CORBA's IDL-generated stubs that welded services together, EJB remote references that turned distributed calls into invisible landmines, microservices that were really a distributed monolith. The process manager is the circuit breaker.

```erlang
-module(on_planning_concluded_initiate_crafting).
-behaviour(evoq_process_manager).

interested_in() ->
    [<<"PlanningConcluded.v1">>].

%% Which aggregate instance should handle this?
correlate(<<"PlanningConcluded.v1">>, EventData) ->
    DivisionId = maps:get(<<"division_id">>, EventData),
    {start, <<"crafting-", DivisionId/binary>>}.

%% What command should we dispatch?
handle(<<"PlanningConcluded.v1">>, EventData, State) ->
    DivisionId = maps:get(<<"division_id">>, EventData),
    Cmd = initiate_crafting_v1:new(DivisionId, EventData),
    {dispatch, Cmd, State}.

%% Track our own state (optional)
apply(State, Event) ->
    State#{last_event => Event}.

%% What to do if things go wrong
compensate(FailedCommand, State) ->
    %% Log, alert, or dispatch a compensating command
    {skip, State}.
```

The `correlate/2` callback is the routing decision. It returns one of four values:

- `{start, Id}` — start a new process manager instance with this ID
- `{continue, Id}` — route to an existing instance
- `{stop, Id}` — stop the instance (process complete)
- `false` — ignore this event

This is how the process manager tracks long-running sagas. A multi-step process (order placement, payment, fulfillment) creates a PM instance on the first event, continues routing subsequent events to it, and stops when the process completes.

The name convention is critical: `on_planning_concluded_initiate_crafting`. Source event, action, target. You can read the module name and understand the integration point without opening the file. We went through three naming conventions before landing on this one. The first was verb_noun (`craft_division_after_planning`). The second was target_first (`crafting_triggered_by_planning`). Both were ambiguous about cause and effect. The `on_X_do_Y` pattern is unambiguous: when X happens, do Y. This is screaming architecture (Chapter 2) applied to cross-domain coordination.

---

## Projections: Building Read Models

Projections transform events into read-optimized data structures. They're the "index cards" from the dossier metaphor — derived views that let you find information without replaying entire streams.

```erlang
-module(plugin_lifecycle_to_plugins).
-behaviour(evoq_projection).

interested_in() ->
    [<<"PluginInstalled.v1">>, <<"PluginUninstalled.v1">>,
     <<"PluginEnabled.v1">>,  <<"PluginDisabled.v1">>].

project(<<"PluginInstalled.v1">>, EventData, _Metadata, _State) ->
    PluginId = maps:get(<<"plugin_id">>, EventData),
    ets:insert(plugins, {PluginId, #{
        plugin_id => PluginId,
        name => maps:get(<<"name">>, EventData),
        version => maps:get(<<"version">>, EventData),
        status => installed,
        installed_at => maps:get(<<"installed_at">>, EventData)
    }}),
    :ok;

project(<<"PluginUninstalled.v1">>, EventData, _Metadata, _State) ->
    PluginId = maps:get(<<"plugin_id">>, EventData),
    ets:delete(plugins, PluginId),
    :ok.
```

One critical lesson we learned the hard way — and I mean "spent an entire Friday tracking down phantom data" hard way: **one ETS table, one projection module.** If you split `PluginInstalled.v1` and `PluginUninstalled.v1` into separate projection modules, they each get their own `gen_server` process. Two processes writing to the same ETS table means race conditions. An install and immediate uninstall might process out of order, leaving a phantom plugin in the table. The plugin shows up in the UI even though it was uninstalled. Users see it, click it, and get an error. The data is a lie.

The fix is the merged projection: one module handles ALL event types for one read model. The single `gen_server`'s mailbox guarantees sequential processing. Events arrive in order. The table stays consistent.

Projections support checkpointing and rebuild. The checkpoint records the last processed event position. On restart, the projection resumes from where it left off. If the checkpoint is corrupted or you change the projection logic, you trigger a rebuild: delete the read model, reset the checkpoint, replay all events from the beginning. The read model is disposable. The events are truth. This is one of the most liberating things about event sourcing: you can change your mind about how to display data without changing the data itself. New report format? Rebuild the projection. Added a field? Rebuild. Realized the whole schema was wrong? Rebuild. The events don't care. After decades of writing painful ALTER TABLE migrations and ETL scripts to reshape data, the ability to just replay events through new logic feels almost miraculous.

---

## The 14 Behaviours

Evoq has 14 behaviours. Here's the map:

**Core 5 — you'll use these constantly:**
- `evoq_aggregate` — the dossier reader (init, execute, apply)
- `evoq_command` — command definition and routing
- `evoq_event_handler` — side effects (pg, mesh, notifications)
- `evoq_projection` — read model builder
- `evoq_process_manager` — cross-domain coordinator

**Adapters 5 — you'll configure these once:**
- `evoq_adapter` — connects evoq to an event store (ReckonDB via reckon_evoq)
- `evoq_subscription_adapter` — subscription mechanism
- `evoq_snapshot_adapter` — snapshot storage
- `evoq_read_model` — read model storage backend
- `evoq_checkpoint_store` — projection checkpoint persistence

**Lifecycle 4 — you'll use these when needed:**
- `evoq_aggregate_lifespan` — custom TTL and passivation rules
- `evoq_middleware` — command pipeline stages
- `evoq_event_upcaster` — transform old event versions during replay
- `evoq_error_handler` — global error handling policy

The adapter layer is what makes evoq storage-agnostic. The `reckon_evoq` library implements the adapter behaviours against ReckonDB's gateway API (`esdb_gater_api`). Swap the adapter, and evoq talks to a different event store. In practice, we always use ReckonDB, but the separation means evoq can be tested with an in-memory adapter and deployed with a persistent one. This sounds like a small thing until you've experienced the joy of running your entire test suite in milliseconds because events live in memory instead of hitting disk.

---

## The Event Envelope

Every event flowing through evoq is wrapped in an envelope:

```erlang
#evoq_event{
    event_id    = <<"evt-uuid-here">>,
    event_type  = <<"VisionSubmitted.v1">>,
    stream_id   = <<"venture-abc123">>,
    version     = 2,
    data        = #{...},
    metadata    = #{
        <<"correlation_id">> => <<"corr-789">>,
        <<"causation_id">> => <<"cmd-456">>
    },
    tags        = [<<"venture">>, <<"lifecycle">>]
}
```

The envelope adds identity (`event_id`), position (`version`), and lineage (`correlation_id`, `causation_id`) to the raw event data. This metadata is invisible to your aggregate — `apply/2` just sees the event map. But it's available to projections, event handlers, and process managers through the metadata parameter. Think of it as the stamps and routing labels on the outside of a sealed envelope — the recipient doesn't need to see them, but the mail system depends on them.

---

## Putting It Together

A command's journey through evoq:

1. API handler receives HTTP request, builds command map
2. Command enters the middleware pipeline
3. Middleware validates, enriches, authorizes
4. Evoq locates (or activates) the target aggregate
5. Aggregate's `execute/2` produces events (or rejects the command)
6. Events are appended to the event store (with optimistic concurrency)
7. Events pass through `apply/2` to update aggregate state
8. Event handlers fire (side effects: pg, mesh)
9. Projections update read models
10. Process managers evaluate and potentially dispatch new commands

Steps 1-7 are synchronous. The command either succeeds or fails, and the caller knows immediately. Steps 8-10 are asynchronous — they happen eventually, driven by event store subscriptions.

This separation is the CQRS payoff. The write side (steps 1-7) is optimized for consistency: one aggregate, one stream, one decision. The read side (steps 8-10) is optimized for flexibility: multiple projections, multiple views, eventual consistency. Neither side compromises for the other. That's the whole point — the same insight that every DBA has known about read replicas for decades, finally applied at the right level of the stack.

---

## A Complete Walk-Through

The numbered steps above are abstract. Let's make them concrete. I want to show you, from byte one to the final pixel, what actually happens. We'll follow a single command — submitting a vision for a venture in the Martha plugin — from the moment it hits the HTTP endpoint to the moment it's queryable.

**Step 1: The HTTP request arrives.**

```
POST /plugin/hecate-app-martha/api/ventures/ven-abc123/submit-vision
Content-Type: application/json

{"vision": "A marketplace for artisan coffee beans", "submitted_by": "user-42"}
```

Cowboy routes this to Martha's API handler.

**Step 2: The handler builds a command.**

```erlang
handle_post(Req, State) ->
    VentureId = cowboy_req:binding(venture_id, Req),
    {ok, Body, Req1} = cowboy_req:read_body(Req),
    Params = json:decode(Body),
    Cmd = #{
        command_type  => <<"SubmitVision.v1">>,
        aggregate_type => venture_aggregate,
        aggregate_id  => VentureId,
        data => #{
            <<"vision">>       => maps:get(<<"vision">>, Params),
            <<"submitted_by">> => maps:get(<<"submitted_by">>, Params)
        }
    },
    case evoq:dispatch(Cmd) of
        {ok, Version, _Events} ->
            {json:encode(#{ok => true, version => Version}), Req1, State};
        {error, Reason} ->
            {json:encode(#{error => Reason}), Req1, State}
    end.
```

No service layer. No repository. The handler builds a map and calls `evoq:dispatch/1`. That's it. The command map carries everything evoq needs: what type of command, which aggregate type handles it, which specific aggregate instance (by ID), and the payload. If you're used to Spring Boot or similar frameworks, this might look suspiciously simple. It is. And it stays simple. After decades of wiring up service layers, DAO layers, transaction managers, and dependency injection containers, the absence of all that machinery is not a gap — it's a relief.

**Step 3: Middleware runs.**

The command enters the pipeline. A middleware module checks that the vision isn't absurdly short:

```erlang
before_dispatch(#{data := Data} = Pipeline) ->
    Vision = maps:get(<<"vision">>, Data, <<>>),
    case byte_size(Vision) > 50 of
        true  -> Pipeline;
        false -> evoq_pipeline:halt(Pipeline, {error, vision_too_short})
    end.
```

If the vision is 12 characters, the pipeline halts. The aggregate never sees the command. The HTTP handler gets `{error, vision_too_short}` back from `evoq:dispatch/1`. No event is created. No state changes. The system protected itself before the business logic even got involved.

**Step 4: Evoq locates the aggregate.**

The command passed middleware. Now evoq needs to find `venture_aggregate` for ID `ven-abc123`. It checks whether a process for that aggregate is already alive. If not, it activates one: spawns a new `gen_server`, loads the latest snapshot from ReckonDB (say, at version 15), then replays events 16 through the current version through `apply/2`. The aggregate is now in memory with current state. This whole activation process — snapshot load plus replay — typically takes single-digit milliseconds.

**Step 5: `execute/2` makes the business decision.**

```erlang
execute(#{status := Status} = State, #{command_type := <<"SubmitVision.v1">>} = Cmd) ->
    case evoq_bit_flags:has(Status, ?INITIATED) of
        false ->
            {error, not_initiated};
        true ->
            case evoq_bit_flags:has(Status, ?VISION_SUBMITTED) of
                true  -> {error, vision_already_submitted};
                false -> {ok, [vision_submitted_v1:new(State, Cmd)]}
            end
    end.
```

Two checks, both using bit flags. Has this venture been initiated? If not, reject — you can't submit a vision for something that doesn't exist. Has a vision already been submitted? If so, reject — one vision per venture. Both pass? Return `{ok, [Event]}`. The aggregate never writes to a database. It returns data. The decision is pure logic. I love this part of the architecture — the business rules are just pattern matching and conditionals. No framework magic. No annotations. Just code.

**Step 6: Evoq appends to the event store.**

Evoq takes the event list from `execute/2`, wraps each in an envelope (adding event_id, correlation_id, causation_id), and appends them to ReckonDB stream `"venture-ven-abc123"` with optimistic concurrency. If the expected version doesn't match — because another command snuck in between — the append fails and evoq retries with fresh state.

**Step 7: `apply/2` updates in-memory state.**

```erlang
apply(State, #{event_type := <<"VisionSubmitted.v1">>, data := Data}) ->
    State#{
        status => evoq_bit_flags:set(maps:get(status, State), ?VISION_SUBMITTED),
        vision => maps:get(<<"vision">>, Data)
    }.
```

Pure function. No I/O. The aggregate's in-memory state now reflects the vision. The `?VISION_SUBMITTED` flag is set. Any subsequent `SubmitVision.v1` command will be rejected at step 5.

**The synchronous part is done.** `evoq:dispatch/1` returns `{ok, 2, [Event]}` to the HTTP handler. The handler sends a 200 response. The client knows the vision was accepted.

**Step 8-10: The asynchronous cascade.**

Now the event store subscription kicks in. `VisionSubmitted.v1` is delivered to every registered subscriber:

The **emitter** broadcasts to OTP process groups:
```erlang
handle_event(<<"VisionSubmitted.v1">>, EventData, _Meta, _State) ->
    pg:send(venture_events, {vision_submitted, EventData}),
    :ok.
```

The **projection** updates the ETS read model:
```erlang
project(<<"VisionSubmitted.v1">>, EventData, _Metadata, _State) ->
    VentureId = maps:get(<<"venture_id">>, EventData),
    case ets:lookup(ventures, VentureId) of
        [{VentureId, Existing}] ->
            ets:insert(ventures, {VentureId, Existing#{
                vision => maps:get(<<"vision">>, EventData),
                status => vision_submitted
            }});
        [] ->
            :ok  %% venture not in read model yet — initiation event hasn't projected
    end,
    :ok.
```

The **process manager** dispatches a follow-up command:
```erlang
handle(<<"VisionSubmitted.v1">>, EventData, State) ->
    VentureId = maps:get(<<"venture_id">>, EventData),
    Cmd = initiate_visionary_v1:new(VentureId, EventData),
    {dispatch, Cmd, State}.
```

That follow-up command enters the same pipeline — middleware, aggregate, events, projections — and the cycle continues. One event can trigger zero, one, or many downstream commands. Each runs independently. Each succeeds or fails on its own terms. It's turtles all the way down, but each turtle knows exactly what it's doing and files its own paperwork.

**Step 10: The query.**

```
GET /plugin/hecate-app-martha/api/ventures/ven-abc123
```

The query handler reads directly from ETS:

```erlang
handle_get(Req, State) ->
    VentureId = cowboy_req:binding(venture_id, Req),
    case ets:lookup(ventures, VentureId) of
        [{VentureId, Venture}] ->
            {json:encode(Venture), Req, State};
        [] ->
            {404, Req, State}
    end.
```

No aggregate activation. No event replay. No joins. A single ETS lookup returns a pre-computed map with everything the client needs. This is the read side — optimized for speed, fed by projections, disposable and rebuildable.

![CQRS Flow](assets/cqrs-flow.svg)

---

## Eventual Consistency: The Trade-Off You Accept

Yes, this is more moving parts than a CRUD app. Yes, your team will push back. "Why can't we just read from the database?" Here's why it's worth the fight.

Steps 1-7 are synchronous. When `evoq:dispatch/1` returns `{ok, Version, Events}`, those events are in the event store. The aggregate's in-memory state reflects them. The write side is strongly consistent within one aggregate — no ambiguity, no races, no stale reads.

Steps 8-10 are asynchronous. The projection, the emitter, the process manager — they all run on separate subscriptions, in separate processes, at their own pace. This means there's a window, however brief, where the event store has the truth but the read model doesn't yet.

**What this looks like in practice:** A client submits a vision (POST) and gets back `{ok: true}`. It immediately fetches the venture (GET). If the projection hasn't processed the event yet, the GET returns the venture without the vision. The client sees stale data.

**Why this is acceptable:** The event store is the source of truth. Projections are convenience views — cached, denormalized, disposable. They exist to make queries fast, not to be authoritative. The POST response already confirmed success. The client knows the vision was accepted. The read model will catch up.

**How fast is "eventually"?** On a single-node Hecate deployment — which is most deployments — "eventually" means "within milliseconds." The event store subscription delivers events to projections via BEAM message passing. There's no network hop, no queue, no polling interval. The event leaves the store and arrives at the projection's mailbox in microseconds. By the time the HTTP response crosses the network back to the client, the projection has almost certainly processed the event. In practice, we've never had a user notice the gap. Not once.

**What happens during replay?** Projections can be deleted and rebuilt from scratch. Delete the ETS table, reset the checkpoint to zero, replay all events from the beginning. The projection will reconstruct the exact same read model. This is deterministic — same events in, same state out. You can change projection logic, deploy a new version, trigger a rebuild, and your read model reflects the new logic applied to all historical events. The event store doesn't change. Only the view does. This is the superpower of event sourcing that takes the longest to fully appreciate.

**The idempotency requirement.** Projections must handle receiving the same event twice. This happens during restarts — the checkpoint records the last processed event version, but if the process crashes between processing an event and saving the checkpoint, it will reprocess that event on restart. ETS inserts are naturally idempotent (inserting the same key-value pair twice produces the same result), but if your projection has side effects beyond ETS writes, you need to check the event version against the checkpoint explicitly.

**When eventual isn't good enough.** Sometimes — rarely, but sometimes — you need a guarantee that a specific handler has processed the event before the command returns. Evoq supports this with the `consistency` option:

```erlang
Cmd = #{
    command_type => <<"SubmitVision.v1">>,
    aggregate_type => venture_aggregate,
    aggregate_id => VentureId,
    consistency => strong,
    data => #{...}
}.
```

With `consistency => strong`, `evoq:dispatch/1` blocks until all handlers marked as `strong` have processed the resulting events. The HTTP handler won't return until the projection has updated the read model. The client's subsequent GET is guaranteed to see the new data.

This is a sharp tool. Use it sparingly. Strong consistency turns your asynchronous read side into a synchronous bottleneck. Every slow projection, every flaky event handler, every overloaded process manager now sits in the critical path of every command. The whole point of CQRS is to decouple these concerns. Strong consistency re-couples them. Use it only when the user experience demands it — when showing stale data for even a millisecond would be confusing or harmful.

**The practical reality:** In eighteen months of running Hecate, we've never needed `consistency => strong` in production. The BEAM is fast enough that eventual consistency is indistinguishable from immediate consistency for human-facing interfaces. The gap exists in theory and in benchmarks. Users don't notice it. I keep the option in the framework because someday someone will need it. But I've come to see it as a fire extinguisher: essential to have, concerning if you're using it regularly. If your codebase has more than two `consistency => strong` calls, something has gone architecturally sideways and you should sit down and have a serious conversation with your domain model.

---

No command bus. No repository pattern. No unit of work. No AbstractCommandHandlerFactoryBeanProvider. Just behaviours, callbacks, and supervision trees. CQRS without the ceremony — arrived at not by following the crowd further down the complexity curve, but by stepping off it entirely. After thirty-five years of watching the industry oscillate between "no framework" and "framework that weighs more than the application," this is the balance I've been looking for. It's the difference between dreading Monday morning because you have to add a field to the write-and-read-model-that-are-actually-the-same-thing, and being excited to open your editor because you know exactly which file to touch and exactly what will happen when you do.
