# Chapter 13: The Venture Lifecycle

*From vision to deployment in 10 processes*

---

After thirty-five years of watching development tools model the wrong things, I thought I'd seen every way to get "process" wrong. Waterfall gave us phases that lasted so long nobody remembered why the decisions in phase one mattered by phase three. RUP gave us artifacts — mountains of them — produced by people who'd never run the resulting software. Agile gave us ceremonies that replaced documentation with tribal knowledge, and when the tribe turned over, the knowledge evaporated. SAFe gave us... well, let's not talk about SAFe. I've lived through MS Project Gantt charts that nobody updated, Jira boards with ten thousand tickets and no coherent story, and enough retrospectives to fill a lifetime.

The one thing every methodology got right was the instinct that development is a *process* — a series of decisions made over time, building on each other. The thing they all got wrong was where to put the process boundary. Waterfall made the phases too big. Agile made them too small and too ephemeral. Every project management tool I've used since 1990 has either captured too much (RUP's artifact zoo) or too little (a Slack thread that disappears in two weeks).

Every project management tool is a monument to the belief that if you just track the work correctly, the work will get done. After thirty-five years, I can confirm: it will not. But I keep trying.

When we started building AI-assisted development tooling, the first model was the same one everyone reaches for: the human describes what they want, the AI plans it, and then it writes the code. Vision, planning, coding. Three phases. It lasted about two weeks before we realized that "planning" was doing the work of five separate concerns. Discovery was tangled with architecture. Architecture was tangled with task breakdown. The AI would jump from "I think you need three bounded contexts" straight to generating Erlang modules, skipping every design decision in between. The code compiled. It even ran. But it was untraceable — you couldn't explain *why* any particular module existed, because the decisions that led to it were buried in a single LLM conversation that had been thrown away.

I've seen this movie before. In the 90s, CASE tools promised to generate code from diagrams. They generated code, all right. Nobody could explain why the code was shaped the way it was, because the diagrams that produced it were on a whiteboard that got erased. Same failure mode, thirty years later: invisible decisions producing untraceable outputs.

That's when we stopped thinking about AI tooling and started thinking about process. Not "software development process" in the Agile-ceremony sense. Process in the business-operations sense: a series of desks, each with a specific job, each passing a dossier to the next. The same model we'd been building the rest of Hecate around (Chapter 1). After decades of BPM tools, workflow engines, and state machines in enterprise software, I knew one thing: if you model development as a business process, the process itself becomes the documentation. Every decision is a slip in a dossier. Every transition is an event. The history writes itself.

We modeled software development as a business process — not because no alternatives existed, but because the alternatives all modeled the wrong thing. There were task trackers, sprint boards, kanban tools by the dozen. We went somewhere less traveled. The irony of using event sourcing to track the development of an event-sourcing framework was not lost on us. We leaned into it.

The result is 10 processes that take a venture from a one-sentence idea to deployed, tested code. Each process is an event-sourced dossier. Each dossier passes through desks. Each desk adds slips. The slips accumulate into a complete, replayable record of every decision that was made along the way. We didn't arrive at 10 by planning it on a whiteboard. We arrived at 10 by splitting things apart every time a process tried to do two jobs at once.

---

![Venture Lifecycle](assets/venture-lifecycle.svg)

## The Hierarchy

A venture is the top of the tree — the overall software endeavor. It's the thing a founder describes in an elevator pitch. "We're building a decentralized marketplace for AI capabilities."

That venture contains divisions. Each division is a bounded context — a cohesive piece of software that handles one area of the business. The marketplace might have divisions for capability management, reputation tracking, and billing.

Each division has three departments — the same three from CQRS (Chapter 7): CMD (commands and business logic), PRJ (projections that build read models), and QRY (queries that serve read models). These aren't separate applications yet. They're a structural guarantee that each division will have a clean separation of concerns.

Inside each department sit desks — individual capabilities. The `register_user` desk. The `ship_order` desk. Each desk is a vertical slice containing its command, event, handler, and any side effects.

```
Venture (1)
  └── Division (N)          — one per bounded context
       └── Department (3)   — CMD, PRJ, QRY
            └── Desk (N)    — individual capability
```

This is not an org chart. It's an architecture decision tree. Each level constrains the next: the venture's vision determines which divisions exist, each division's design determines which desks it needs, and each desk's behavior determines the events that flow through the system.

I'll be honest — we debated this hierarchy for longer than I'd like to admit. The early versions had five levels. Then two. We kept asking the same question: "If I'm new to this venture, can I understand what it does by reading the tree?" Five levels was too much noise — it reminded me of the deeply nested work breakdown structures from my Waterfall days, where you needed a project management degree to navigate the hierarchy. Two levels lost the department structure that makes CQRS work. Three was right, with desks as the leaf nodes. Sometimes the obvious answer takes a while to find, even when you've been doing this for three decades.

---

## Three Types of Lifecycle

Not all processes in the venture lifecycle work the same way. We learned this the hard way when we tried to force a single lifecycle model on everything and ended up with monitoring processes that could be "shelved." (Shelved monitoring. Think about that for a second. I've seen enterprise BPM tools make this exact mistake — one workflow definition to rule them all, regardless of whether the process is a one-shot approval or a never-ending health check.)

There are three distinct patterns, each modeled as its own kind of aggregate:

**Short-lived processes** run once and finish. `setup_venture` creates the venture dossier, records the initial vision, and completes. There's no pausing, no resuming. It happens and it's done.

**Long-lived processes** follow a lifecycle protocol. Discovery, planning, crafting — these can take days or weeks. They need to be opened, shelved when priorities shift, resumed when attention returns, and concluded when the work is done. Each state transition is a first-class event.

**Continuous processes** run forever. `guide_node_lifecycle` monitors the health of deployment nodes. There are no phases. It's always on, always reacting.

The lifecycle protocol for long-lived processes is a state machine driven by bit flags:

```
initiate → open → shelve/resume → conclude → archive
```

And in code, the status flags are:

```erlang
-define(INITIATED,  1).   %% 2^0 — dossier exists
-define(ARCHIVED,   2).   %% 2^1 — permanently closed
-define(OPEN,       4).   %% 2^2 — actively being worked
-define(SHELVED,    8).   %% 2^3 — paused, will resume
-define(CONCLUDED, 16).   %% 2^4 — finished successfully
```

These are bit flags, not enum values (Chapter 8). A dossier can be both INITIATED and OPEN simultaneously — flag `5` means "this process has been initiated and is currently open." This matters because the aggregate needs to check preconditions:

```erlang
execute(#planning_state{status = S} = State, #{command_type := <<"open_planning">>} = Cmd) ->
    case evoq_bit_flags:has(S, ?INITIATED) andalso
         not evoq_bit_flags:has_any(S, [?OPEN, ?CONCLUDED, ?ARCHIVED]) of
        true  -> {ok, [planning_opened_v1:new(State, Cmd)]};
        false -> {error, invalid_lifecycle_transition}
    end.
```

You can only open a planning dossier if it has been initiated and is not already open, concluded, or archived. The bit flags make this a single integer comparison, not a string pattern match. We considered using atoms for states — `:open`, `:shelved`, `:concluded` — and the code was prettier, in the way that a sports car is prettier than an ambulance. But atoms can't compose. You can't express "initiated AND open" with a single atom. The moment we needed compound states, bit flags became the only sane choice. I'd seen the same realization hit teams working with C# Flags enums back in the .NET days. Some patterns keep coming back because they're right.

---

## The 10 Processes

Here they are. Ten processes, covering the full venture lifecycle:

| Process | Phase | Duration |
|---------|-------|----------|
| `setup_venture` | Inception | Short |
| `discover_divisions` | Discovery | Long-lived |
| `design_division` | Architecture | Long-lived |
| `plan_division` | Planning | Long-lived |
| `generate_division` | Generation | Long-lived |
| `test_division` | Testing | Long-lived |
| `deploy_division` | Deployment | Long-lived |
| `monitor_division` | Monitoring | Long-lived |
| `rescue_division` | Rescue | Long-lived |
| `guide_venture` | Orchestration | Continuous |

The first two operate at the venture level. The next seven operate per-division — when you have three divisions, you get three independent instances of each process. The last one is the orchestrator that watches everything.

Why 10? Not 5, not 20? Because we kept splitting processes that tried to do two things, and kept merging processes that were too granular to justify separate dossiers. At one point we had 14 — "validate_division" and "review_division" were separate from "test_division." In practice, they were always opened and concluded together. Nobody ever wanted to validate without reviewing. So they merged. At another point, we tried combining "design" and "plan" into a single "architect_division." That lasted until we realized design decisions (what aggregates exist) and planning decisions (what desks to build, in what order) had different lifecycles. You might redesign an aggregate without replanning the desks. They needed separate dossiers.

If you've ever gone through the RUP discipline-splitting exercise, this will feel familiar — except we did it empirically instead of from a process template. Ten felt arbitrary at first. Now it feels inevitable. I give it six months before someone on the team argues for eleven.

But Hecate doesn't implement all 10 as separate aggregates. That would be over-engineering for processes that share lifecycle mechanics. Instead, it groups them into three aggregate types:

**The Venture Lifecycle aggregate** (`guide_venture_lifecycle`) handles `setup_venture` and `discover_divisions`. One dossier per venture. The stream ID is `venture-{venture_id}`. Its desks include `initiate_venture`, `submit_vision`, `open_discovery`, `identify_division`, `shelve_discovery`, `resume_discovery`, and `conclude_discovery`.

**The Division ALC** splits into two aggregates — Planning and Crafting — each with its own event stream. `guide_division_planning` manages design and planning decisions. `guide_division_crafting` manages code generation, testing, and delivery. Two separate dossiers, two separate lifecycles, connected by a process manager.

**The Node Lifecycle aggregate** (`guide_node_lifecycle`) runs continuously, managing deployment nodes. No phases, no shelving. Always on.

---

## The Process Manager Chain

Here's where it gets interesting. When discovery identifies a division, that event needs to kick off planning. When planning concludes, that needs to kick off crafting. But these are separate aggregates with separate event streams. They can't call each other.

We tried making them call each other, early on. Division A's aggregate would dispatch a command directly to Division B's aggregate. It worked for about a week, and then we added a third aggregate and ended up with a circular dependency that took two days to untangle. Anyone who survived the Enterprise Service Bus era of the mid-2000s will recognize this pattern: direct coupling between services that starts simple and turns into a dependency graph that nobody can draw on a single whiteboard. Never again.

Enter process managers — the automated clerks that watch for events and dispatch commands in response:

```
Venture Dossier                    Planning Dossier                   Crafting Dossier
────────────────                   ────────────────                   ────────────────
division_identified_v1             planning_initiated_v1
        │                          planning_opened_v1
        │                          aggregate_designed_v1
        ▼                          event_designed_v1
  ┌───────────────┐                desk_planned_v1
  │ PM: on_       │                planning_concluded_v1
  │ division_     │                        │
  │ identified_   │──initiate──────────▶   │
  │ initiate_     │  planning_v1           ▼
  │ planning      │                  ┌───────────────┐
  └───────────────┘                  │ PM: on_       │
                                     │ planning_     │
                                     │ concluded_    │──initiate──────▶ crafting_initiated_v1
                                     │ initiate_     │  crafting_v1     crafting_opened_v1
                                     │ crafting      │                  module_generated_v1
                                     └───────────────┘                  test_generated_v1
                                                                        release_delivered_v1
```

Each process manager lives with its target domain. The PM that initiates planning lives in the planning domain because it needs to know how to construct the `initiate_planning_v1` command. It subscribes to venture events and reacts to `division_identified_v1`.

```erlang
-module(on_division_identified_initiate_planning).
-behaviour(evoq_process_manager).

interested_in(_Event = #{event_type := <<"DivisionIdentified.v1">>}) -> true;
interested_in(_) -> false.

handle(State, #{event_type := <<"DivisionIdentified.v1">>, data := Data}) ->
    DivisionId = maps:get(<<"division_id">>, Data),
    VentureId = maps:get(<<"venture_id">>, Data),
    Cmd = initiate_planning_v1:new(#{
        division_id => DivisionId,
        venture_id  => VentureId,
        name        => maps:get(<<"name">>, Data),
        description => maps:get(<<"description">>, Data)
    }),
    {ok, [Cmd], State}.
```

This is the pattern from Chapter 1 in action: processes never call each other directly. Events flow through process managers, which dispatch commands. The dossiers are decoupled. The PMs are the integration points. It's more code than a direct function call. It's also the only approach that didn't eventually collapse into spaghetti as the system grew. I've watched message-driven architectures come and go — from MQSeries to Tibco to RabbitMQ — and the ones that survived were always the ones where the routing was explicit, not magical.

---

## The Planning Dossier

Let's look at the planning dossier in detail, because it's where the most interesting decisions happen — and frankly, it's the one that went through the most rewrites.

The planning aggregate manages the architectural design of a division. Its desks include:

```
apps/guide_division_planning/src/
├── initiate_planning/
│   ├── initiate_planning_v1.erl
│   ├── planning_initiated_v1.erl
│   └── maybe_initiate_planning.erl
├── open_planning/
├── shelve_planning/
├── resume_planning/
├── conclude_planning/
├── archive_planning/
├── design_aggregate/
│   ├── design_aggregate_v1.erl
│   ├── aggregate_designed_v1.erl
│   └── maybe_design_aggregate.erl
├── design_event/
│   ├── design_event_v1.erl
│   ├── event_designed_v1.erl
│   └── maybe_design_event.erl
├── plan_desk/
│   ├── plan_desk_v1.erl
│   ├── desk_planned_v1.erl
│   └── maybe_plan_desk.erl
└── plan_dependency/
    ├── plan_dependency_v1.erl
    ├── dependency_planned_v1.erl
    └── maybe_plan_dependency.erl
```

Each desk is a vertical slice. `design_aggregate` contains the command (`design_aggregate_v1`), the event it produces (`aggregate_designed_v1`), and the handler that decides whether the command is valid (`maybe_design_aggregate`). Everything needed to understand aggregate design is in one directory. No hunting through separate `commands/`, `events/`, and `handlers/` folders. It's all right there.

The planning aggregate accumulates architectural decisions:

```erlang
-record(planning_state, {
    division_id   :: binary(),
    venture_id    :: binary(),
    status        :: non_neg_integer(),    %% bit flags
    aggregates    :: [map()],              %% designed aggregates
    events        :: [map()],              %% designed events
    desks         :: [map()],              %% planned desks
    dependencies  :: [map()]               %% planned dependencies
}).
```

When the AI agent designs an aggregate, the `aggregate_designed_v1` event carries the name, the fields, the invariants, and the rationale. The aggregate state accumulates these designs. When it designs events, those reference the aggregates. When it plans desks, those reference the events. Each decision constrains the next.

There's something satisfying about watching this unfold in real time. The planning dossier starts empty — just an ID and a status flag. Then the aggregates appear, one by one. Then events that reference those aggregates. Then desks that tie events to capabilities. The dossier fills up like a blueprint being drawn, each new element connecting to the ones already there. It's the opposite of a code dump. It's architecture emerging through recorded decisions. After decades of watching architecture documents go stale the moment someone commits code, seeing the architecture and the decision trail be the same thing — that felt like progress.

---

## The Decision Cascade

This is the most important property of the venture lifecycle: **each phase's output constrains the next phase's decisions.**

The vision constrains discovery — you only look for divisions that serve the stated vision. Discovery constrains planning — you can only plan divisions that were identified. Planning constrains crafting — you can only generate code for desks that were planned, with events that were designed, for aggregates that were specified.

We debated whether this was too restrictive. What if the AI discovers something during crafting that should change the plan? What if the user has an insight mid-generation? The temptation was to allow backward jumps — let crafting modify the plan, let planning add new divisions. We resisted. Not because change is bad, but because untracked change is bad. If you need to change the plan, shelve crafting, reopen planning, make the change (which produces events), conclude planning again, and resume crafting. More steps, yes. But now the change is recorded. You can see that the plan was revised at 3:47 PM because the aggregate design didn't support the concurrency requirements. That's provenance. That's audit trail.

I've been on projects where someone changed the database schema in production at 2 AM and nobody found out until the morning standup. I've seen architecture decisions made in hallway conversations that never got written down, and six months later the team was maintaining code that contradicted its own design document because the document was never updated. The cascade is the antidote to all of that. You can always change the plan. You just have to do it through the process, so the change is recorded.

This cascade is enforced mechanically. The crafting aggregate's `generate_module` handler checks that the module being generated corresponds to a planned desk. The planning aggregate's `design_event` handler checks that the event references a designed aggregate. You can't skip steps.

```erlang
execute(#crafting_state{planned_desks = Desks} = State,
        #{command_type := <<"generate_module">>, data := Data} = Cmd) ->
    DeskId = maps:get(<<"desk_id">>, Data),
    case lists:keyfind(DeskId, 1, Desks) of
        {DeskId, DeskSpec} ->
            {ok, [module_generated_v1:new(State, Cmd, DeskSpec)]};
        false ->
            {error, {desk_not_planned, DeskId}}
    end.
```

This is not arbitrary restriction. It's quality control. The cascade ensures that generated code is traceable to a design decision, which is traceable to a discovered division, which is traceable to the original vision. Every line of generated code has provenance.

---

## The Guided Conversation Method

The lifecycle processes don't operate in silence. They're designed to support a guided conversation between a human and AI agents:

1. **Frame the decision.** "We need to identify the bounded contexts in your venture."
2. **Present options.** "Based on your vision, I see three potential divisions: capability management, reputation tracking, and billing."
3. **User decides.** "Yes, those three. But billing should include subscription management too."
4. **Record the decision.** `division_identified_v1` events emitted for each.
5. **Build forward.** The next phase uses these decisions as input.
6. **Produce artifacts.** Planning produces architectural specs. Crafting produces code.

Every step in this conversation is an event. The dossier records not just what was decided, but what options were presented, what the user's reasoning was, and what constraints were applied. You can replay the entire decision-making process.

This feels different from the way most AI tools work. Usually you get a conversation — ephemeral, unstructured, lost when you close the tab. Here, the conversation IS the architecture. Each exchange produces events. The events become the system's memory. Six months later, when someone asks "why does this division exist?", you don't grep through Slack. You read the dossier.

I've spent a non-trivial fraction of my career grepping through Slack, email archives, and Confluence pages trying to reconstruct why a particular architectural decision was made. The answer is usually "Dave thought it was a good idea," and Dave left the company in 2019. The dossier approach is something I wish I'd had twenty years ago.

---

## Fact Transport

The venture lifecycle uses two transport mechanisms for its events:

**pg (OTP process groups)** for internal communication. When a planning event occurs, the process manager that initiates crafting receives it through pg. Same BEAM VM, same daemon. This is fast, synchronous within the node, and requires no network overhead.

**Mesh (Macula)** for external communication. When Martha Studio needs to display the venture's progress, events flow through the mesh to connected frontends. The SSE bridge subscribes to the event store and broadcasts to all connected clients.

The processes themselves never make direct calls. They don't import each other's modules. They don't share databases. They communicate exclusively through events — emitted to pg groups, picked up by process managers, transformed into commands for other domains.

This is the dossier principle (Chapter 1) applied recursively. The venture is a dossier. Each division's planning phase is a dossier. Each division's crafting phase is a dossier. The process managers are the clerks passing folders between desks.

The result is a system that can explain, at any point, exactly how it got where it is. Not through logs. Not through database snapshots. Through a complete, ordered, immutable record of every decision that was ever made.

Ten processes. One venture. Every decision recorded, every phase traceable, every artifact accounted for. We arrived here after decades of watching project management tools capture either too much ceremony or too little history — and after deciding, deliberately, to stop waiting for the industry to fix the problem and build something ourselves. This captures exactly the decisions that matter, and nothing else. I wouldn't go back.
