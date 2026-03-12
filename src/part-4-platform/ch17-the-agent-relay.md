# Chapter 16: The Agent Relay

*Watching machines collaborate in real-time*

---

Martha went through four architectures before we landed on the relay pattern. The first three taught us what NOT to do. But looking back, I realize they also taught us something else: every failed architecture was a pattern I'd seen before in a different context, and the relay itself draws on patterns that are decades old.

Version one was a single mega-prompt. You'd describe your venture and the AI would generate everything — bounded contexts, aggregates, events, code — in one massive response. The output was impressive-looking and almost always wrong in subtle ways. The AI would design an aggregate, forget about it three paragraphs later, and design a contradictory one. There was no memory between sections because there were no sections — just one continuous stream of text pretending to be architecture. I'd seen this pattern before in a different medium: the monolithic stored procedure from the 2000s, where a thousand lines of T-SQL tried to handle an entire business process in a single transaction. Same problem — no separation of concerns means no ability to reason about any single concern.

Version two was a chain of prompts in a script. Better — each prompt focused on one concern, and the output of each became the input of the next. But the chain was rigid. If the human wanted to reject the aggregate design and redo it, they'd have to restart from that point, losing everything downstream. And there was no visibility. The script ran in a terminal. You watched a spinner. You hoped. This was essentially a batch pipeline, and anyone who's worked with ETL tools or CI/CD pipelines knows the limitation: linear, fragile, no human intervention points. It was Jenkins for AI — and I mean that in the most unflattering way possible. (If your architecture can be accurately described as "Jenkins for anything," you have made a wrong turn somewhere.)

Version three was close to right. We had separate agents with separate prompts, connected by event-sourced commands. But the agents called each other directly — the visionary would dispatch a command to the stormer, the stormer would dispatch to the reviewer. It worked until we needed to add a gate between the visionary and stormer. Suddenly every agent needed to know about gates. The coupling was back. I recognized this immediately — it was the same problem that killed tightly-coupled ESB integrations in the enterprise world. When service A calls service B directly, adding cross-cutting concerns like monitoring, security, or in our case human approval gates, requires changing every service. The SOA crowd spent a decade learning this lesson the hard way.

The fourth architecture — the relay — solved it by applying the same pattern we'd been using for everything else in this book: events, process managers, and human gates. No agent knows about any other agent. They don't call each other. They produce output, which becomes an event, which triggers a process manager, which dispatches a command to the next agent. The relay emerges from the composition. And because it's all event-sourced, you can watch it happen in real time.

If you've worked with message queues, event brokers, or enterprise integration patterns, you'll recognize the bones of this architecture. It's a pipes-and-filters pattern with event sourcing for the pipes and human gates at the filter boundaries. The difference is that some of the filters are 100-billion-parameter neural networks. The architecture doesn't care. Of course the agent pipeline is event-sourced. What else would it be?

---

## Two Aggregates, Two Concerns

The agent relay is implemented by `orchestrate_agents`, an OTP application with two aggregates that manage different aspects of the relay:

**`agent_orchestration_aggregate`** manages individual agent sessions. Each time an AI agent is invoked — the visionary analyzing a vision statement, the stormer designing aggregates for a division — a new session dossier is created. The stream ID is `agent-session-{session_id}`.

**`division_team_aggregate`** manages the team of agents assigned to a division. When a division enters planning, a team is formed. When planning concludes and crafting begins, the team may be reformed with different roles. The team aggregate tracks which agents are active, which have completed, and which are waiting.

This separation matters. Session-level concerns (did the LLM call succeed? what was the output? did the human approve it?) are different from team-level concerns (which agents have been assigned? what's the pipeline order? is the team disbanded?). We tried putting them in one aggregate first — of course we did. Every developer's first instinct is to put related things in the same place. The aggregate grew to 15 event types and the `execute` function was a maze of pattern matches that took five minutes to read. Splitting into two aggregates wasn't elegant design thinking. It was survival. The God object is the software equivalent of the junk drawer in your kitchen — everything goes in, nothing comes out organized, and eventually you can't find the scissors. The same survival instinct that taught me, sometime around 2003, to stop building God objects and start separating concerns. Some lessons you learn once and apply forever.

---

## The Session State Machine

Each agent session follows a state machine:

```
fresh → INITIATED → [running LLM call]
                        │
              ┌─────────┼─────────┐
              ▼         ▼         ▼
          COMPLETED  AWAITING   FAILED
                     _INPUT
              │         │         │
              └────┬────┘         │
                   ▼              │
              GATE_PENDING        │
                   │              │
              ┌────┴────┐        │
              ▼         ▼        │
         GATE_PASSED  GATE_      │
                      REJECTED   │
              │         │        │
              └────┬────┴────────┘
                   ▼
              ARCHIVED
```

The session starts as INITIATED. An LLM call runs. If it succeeds, the session moves to COMPLETED. If it needs human input (a clarification, a missing detail), it moves to AWAITING_INPUT. If the LLM call fails, it moves to FAILED.

Completed sessions that require human approval enter GATE_PENDING. The human reviews the output and either passes or rejects. Passed sessions continue the relay — the next agent is triggered. Rejected sessions get a reason, which is fed back to the agent for revision. (The rejection loop is important. When you reject an aggregate design and say "this should be two aggregates, not one," that feedback becomes part of the context for the retry. The agent doesn't start from scratch — it starts from your critique.)

All transitions are events:

```erlang
%% Session events
-define(SESSION_EVENTS, [
    agent_session_initiated_v1,
    agent_session_completed_v1,
    agent_session_failed_v1,
    agent_input_requested_v1,
    agent_gate_pending_v1,
    agent_gate_passed_v1,
    agent_gate_rejected_v1,
    agent_session_archived_v1
]).
```

Status tracking uses bit flags, naturally:

```erlang
-define(SESSION_INITIATED,     1).
-define(SESSION_COMPLETED,     2).
-define(SESSION_FAILED,        4).
-define(SESSION_AWAITING,      8).
-define(SESSION_GATE_PENDING, 16).
-define(SESSION_GATE_PASSED,  32).
-define(SESSION_GATE_REJECTED,64).
-define(SESSION_ARCHIVED,    128).
```

---

## Per-Role LLM Runners

Each agent role — visionary, explorer, stormer, reviewer, architect, coder — has a dedicated process manager that handles LLM invocation. These PMs subscribe to their role's initiation event and orchestrate the entire call cycle:

```erlang
-module(on_visionary_initiated_run_llm).
-behaviour(evoq_process_manager).

handle(State, #{event_type := <<"VisionaryInitiated.v1">>, data := Data}) ->
    SessionId = maps:get(<<"session_id">>, Data),
    VentureId = maps:get(<<"venture_id">>, Data),
    Context   = maps:get(<<"context">>, Data),

    %% Spawn a linked process for the LLM call
    Self = self(),
    spawn_link(fun() ->
        %% Load the role's system prompt
        Prompt = load_system_prompt(<<"visionary">>),

        %% Build the messages
        Messages = [
            #{role => <<"system">>, content => Prompt},
            #{role => <<"user">>,   content => Context}
        ],

        %% Call the LLM
        case serve_llm:chat(Messages, #{model => maps:get(<<"model">>, Data)}) of
            {ok, Response} ->
                %% Parse structured output
                Parsed = martha_notation:parse(Response),
                Cmd = complete_agent_session_v1:new(#{
                    session_id => SessionId,
                    output     => Parsed,
                    raw        => Response
                }),
                Self ! {dispatch, Cmd};
            {error, Reason} ->
                Cmd = fail_agent_session_v1:new(#{
                    session_id => SessionId,
                    reason     => Reason
                }),
                Self ! {dispatch, Cmd}
        end
    end),

    {ok, [], State}.
```

The LLM call happens in a linked process, not in the process manager itself. This is deliberate — LLM calls can take seconds or minutes. Blocking the PM would prevent it from handling other events. The linked process does the slow work and sends the result back as a command to dispatch.

This pattern was another hard-won lesson. The first implementation made the LLM call inside the PM's `handle` callback. It worked fine with fast models. Then someone selected Claude Opus for a complex architecture task, and the PM was blocked for 45 seconds. During those 45 seconds, three other events queued up. When the LLM call finally returned, the PM processed the backlog and dispatched three commands simultaneously, two of which were now stale because the state had changed. Anyone who's built integrations with slow external services — SOAP calls in the 2000s, third-party APIs over unreliable networks — knows this pattern. You never block the event loop with I/O. The linked-process pattern eliminates this entirely — the PM returns immediately, stays responsive, and processes the result when it arrives.

Each role has its own system prompt, loaded from disk:

```
priv/prompts/
├── visionary.md        ← "You are a domain analyst..."
├── explorer.md         ← "You are a boundary mapper..."
├── stormer.md          ← "You are a DDD aggregate designer..."
├── reviewer.md         ← "You are a critical design reviewer..."
├── architect.md        ← "You are a systems architect..."
└── coder.md            ← "You are an Erlang/OTP developer..."
```

The prompts are carefully crafted. "Carefully crafted" is a euphemism for "rewritten dozens of times after the agent produced output that looked perfect, compiled cleanly, and did absolutely nothing useful." Prompt engineering is the new template engineering, and it inherits all the same frustrations — except the compiler error messages are replaced by polite apologies from a machine that is very sorry it designed your billing system as a linked list. If you remember the 90s code generators — the ones where you'd spend more time tuning the templates than writing code by hand — this will feel familiar, except the templates are natural language and the failure modes are more creative. The visionary prompt explains the dossier principle and asks the agent to identify bounded contexts. The stormer prompt explains aggregate design patterns and asks the agent to design aggregates, events, and desks. The coder prompt includes Hecate's naming conventions and code generation templates. Each prompt represents weeks of iteration — every edge case the AI mishandled became a new paragraph in the prompt.

The context passed to each role includes the accumulated output of all previous roles. The stormer sees the visionary's identified divisions. The reviewer sees the stormer's aggregate designs. The architect sees the reviewer's critique. Each agent builds on what came before — the dossier grows.

---

## The Pipeline Chain

The relay works through a chain of process managers, each watching for a specific event and triggering the next agent:

```
venture_initiated_v1
    │
    ▼
visionary_initiated_v1 ──→ [LLM: identify divisions]
    │
    ▼
visionary_completed_v1 ──→ vision_gate_pending_v1
    │                            │
    │                      [Human: pass/reject]
    │                            │
    ▼                            ▼
vision_gate_passed_v1
    │
    ▼
explorer_initiated_v1 ──→ [LLM: map boundaries]
    │
    ▼
explorer_completed_v1 ──→ boundary_gate_pending_v1
    │                            │
    │                      [Human: pass/reject]
    │                            │
    ▼                            ▼
boundary_gate_passed_v1
    │
    ▼
stormer_initiated_v1 ──→ [LLM: design aggregates]
    │
    ▼
... and so on through reviewer → architect → coder
```

Each arrow is a process manager. Each PM watches for exactly one event and dispatches exactly one command. The chain is explicit, auditable, and extensible — adding a new role means adding a new PM between two existing ones. No workflow engine to configure, no DAG to maintain, no YAML file describing the pipeline. The pipeline IS the set of process managers. Add a PM, the chain extends. Remove one, the chain shortens. The architecture is the configuration.

If you've ever worked with BPM tools — TIBCO, Pega, Camunda — you know the alternative: a visual workflow designer where the pipeline is defined in an XML dialect and executed by a runtime engine that nobody fully understands. Those tools work. They also introduce a layer of indirection that makes debugging feel like archaeology. Our pipeline has no runtime engine. There's no workflow definition language. The PMs *are* the pipeline. The code is the configuration. You can read it, debug it, and version control it with the same tools you use for everything else.

```erlang
-module(on_vision_gate_passed_initiate_explorer).
-behaviour(evoq_process_manager).

interested_in(#{event_type := <<"VisionGatePassed.v1">>}) -> true;
interested_in(_) -> false.

handle(State, #{event_type := <<"VisionGatePassed.v1">>, data := Data}) ->
    Cmd = initiate_explorer_v1:new(#{
        venture_id => maps:get(<<"venture_id">>, Data),
        session_id => generate_session_id(),
        context    => maps:get(<<"vision_output">>, Data),
        model      => maps:get(<<"recommended_model">>, Data)
    }),
    {ok, [Cmd], State}.
```

Notice how the PM passes the vision output as context to the explorer. Each PM is a translation point — it takes the output of one agent and packages it as input for the next. The PMs own the integration logic. The agents themselves are pure: prompt in, structured output out.

---

## Martha Notation

LLM output is unstructured by default — natural language text that's hard to parse programmatically. Martha solves this with a lightweight markup format called Martha notation. Each agent is prompted to produce output in this format, and a parser extracts structured data:

```
## Division: Authentication
### Description
Handles user identity, session management, and access control.
### Aggregates
- UserIdentity: manages registration, login, password changes
- Session: manages session lifecycle
### Events
- user_registered_v1: identity, email, hashed_password
- session_started_v1: session_id, user_id, expires_at
```

We tried JSON first. "Just ask the AI to output JSON." It works about 80% of the time. The other 20%, the AI produces JSON with trailing commas, or unescaped quotes in string values, or (my favorite) markdown-formatted JSON where the opening brace is inside a code fence and the closing brace is outside it. The AI will also occasionally decide that what you really wanted was YAML, because apparently even neural networks can't resist the siren call of significant whitespace. JSON parsing failures at the boundary between "AI output" and "structured data" were responsible for more failed sessions than actual bad architecture decisions.

I've been dealing with format negotiation at system boundaries for my entire career — from EDI in the 90s to XML schema validation in the 2000s to JSON Schema today. The lesson is always the same: the simpler the format, the more reliable the parsing. Martha notation is deliberately simple. It doesn't try to handle arbitrary markdown. It looks for specific heading patterns and bullet-list structures that the prompts instruct the agents to produce. When an agent's output doesn't conform, the session fails and the agent is re-invoked with a correction prompt.

```erlang
-module(martha_notation).

parse(Text) ->
    Lines = binary:split(Text, <<"\n">>, [global]),
    parse_lines(Lines, #{}, undefined).

parse_lines([], Acc, _CurrentSection) ->
    Acc;
parse_lines([<<"## Division: ", Name/binary>> | Rest], Acc, _) ->
    parse_lines(Rest, Acc#{current_division => string:trim(Name)}, division);
parse_lines([<<"### ", Section/binary>> | Rest], Acc, _) ->
    parse_lines(Rest, Acc, string:trim(Section));
parse_lines([<<"- ", Item/binary>> | Rest], Acc, Section) ->
    Items = maps:get(Section, Acc, []),
    parse_lines(Rest, Acc#{Section => Items ++ [parse_item(Item)]}, Section);
parse_lines([_ | Rest], Acc, Section) ->
    parse_lines(Rest, Acc, Section).
```

The parsed output becomes the `output` field of the `agent_session_completed_v1` event. Downstream agents receive structured maps, not raw text. The visionary's output is a list of divisions with names and descriptions. The stormer's output is a list of aggregates with fields and events. The coder's output is a list of module definitions with source code.

---

## The Event Bridge and Real-Time Visibility

The agent relay produces a dense stream of events. Sessions initiate, LLM calls start, responses arrive, gates open, humans decide, next agents trigger. All of these are events in Martha's ReckonDB store.

The event bridge (Chapter 15) picks up every one of these events and broadcasts them to connected Martha Studio clients. The NerveCenter shows which agents are currently running, which are waiting at gates, which have completed. The ActivityRail scrolls with live events:

```
14:32:01  visionary_initiated_v1      — Starting vision analysis
14:32:15  visionary_completed_v1      — 3 divisions identified
14:32:15  vision_gate_pending_v1      — Awaiting approval
14:33:42  vision_gate_passed_v1       — Approved by user
14:33:42  explorer_initiated_v1       — Starting boundary mapping
14:34:08  explorer_completed_v1       — Boundaries confirmed
...
```

There's something genuinely compelling about watching this unfold. Each line in the ActivityRail represents a real decision — an AI thinking, a human approving, the next step triggering automatically. The first time we ran a complete relay from vision to generated code, the whole team gathered around a screen and watched the events scroll by. It felt like watching a relay race, except the runners were language models and the baton was a dossier. After thirty-five years of staring at build logs, deployment scripts, and monitoring dashboards, I can tell you that watching an AI relay is a different kind of satisfying. The events aren't just status updates — they're decisions being made, each one traceable, each one reversible.

The user watches the relay unfold. When a gate appears, they review the agent's output in the GateInbox (Chapter 15), check the reasoning, and pass or reject. If they reject, the rejection reason flows back through the system — the PM dispatches a new session initiation with the rejection context appended, and the agent tries again with the feedback.

This is the critical difference between the agent relay and a batch pipeline. A batch pipeline runs start-to-finish and presents the final output for review. The relay pauses at gates. The human is in the loop at every significant decision point. The machine proposes, the human disposes.

---

## Team Formation

The `division_team_aggregate` manages which agents are assigned to a division and in what order. When a division enters planning, a team is formed:

```erlang
%% Team lifecycle
team_formed_v1          — roles assigned, pipeline defined
team_activated_v1       — agents can be initiated
team_member_completed_v1 — one role finished
team_disbanded_v1       — all roles done, team dissolved
```

The team aggregate tracks status:

```erlang
-record(team_state, {
    division_id :: binary(),
    status      :: non_neg_integer(),   %% FORMED=1, ACTIVE=2, DISBANDED=4
    roles       :: [#{role := binary(), status := atom()}],
    pipeline    :: [binary()],          %% ordered list of role names
    current     :: binary() | undefined %% currently active role
}).
```

Team formation is itself a command:

```erlang
execute(#team_state{status = 0} = State, #{command_type := <<"form_team">>} = Cmd) ->
    Roles = maps:get(<<"roles">>, Cmd),
    Pipeline = maps:get(<<"pipeline">>, Cmd),
    {ok, [team_formed_v1:new(State, #{roles => Roles, pipeline => Pipeline})]}.
```

The default pipeline for a division is: visionary, explorer, stormer, reviewer, architect, coder. But the pipeline is configurable per division. A simple utility library might skip the reviewer and architect. A critical infrastructure division might add additional review stages. The pipeline is data, not code — changing it doesn't require a deployment.

---

## The Relay Pattern

Step back and look at the whole thing.

Events flow through the system. Each process manager watches for exactly one trigger and dispatches exactly one command. Each command produces exactly one event (or fails). Each event is stored, projected, and broadcast. Humans intervene at gates. AI agents do the heavy lifting between gates.

This is the relay pattern:

1. An event occurs.
2. A process manager reacts.
3. A command is dispatched.
4. An agent session is initiated.
5. An LLM call executes.
6. The output is parsed and stored as an event.
7. A gate pauses for human approval.
8. The human passes or rejects.
9. The next process manager reacts.
10. Go to step 3.

No orchestrator. No central controller. No workflow engine. Every AI framework in 2025 was building elaborate orchestration layers — LangChain, CrewAI, AutoGen. We went without one. Just events, process managers, and agents. The relay emerges from the interaction of independent, event-driven components.

If that sounds familiar, it should. This is the same architecture we've been building throughout this book. Order processing, capability management, plugin lifecycle — they all work this way. The only difference is that some of the "desks" in this relay are staffed by language models instead of deterministic code. The architecture doesn't care. An event is an event. A command is a command. Whether the handler is a function or a 100-billion-parameter neural network, the process manager dispatches the same way.

I've been building message-driven systems since MQSeries on AS/400s in the mid-90s. The pattern is always the same: decouple producers from consumers, make the routing explicit, and make the messages durable. What changes is the technology — from MQ to JMS to AMQP to Kafka to event sourcing. What doesn't change is the principle. The relay is just the latest incarnation of a pattern that's been working for thirty years. The fact that some of the consumers are now language models is interesting, but architecturally, it's irrelevant. A message is a message.

The beauty is in the auditability. Every agent call is an event. Every gate decision is an event. Every output is an event. You can replay the entire relay from scratch — load the venture's event stream, walk through every session, see every decision. If an agent made a bad recommendation and the human missed it at the gate, you can find exactly when it happened and why.

You can also experiment. Change a system prompt, replay the relay from a specific point, and see how the output differs. The event stream gives you a rewind button for AI-assisted development. Try a different model for the stormer role. Try a different pipeline order. Each experiment produces its own event stream, its own audit trail, its own history. This is what we meant in Chapter 4 when we talked about event sourcing enabling "what-if" analysis. Here, "what if" means "what if we'd used a different AI model for this decision?"

The agents aren't magic. They're prompted language models with structured output requirements. The relay isn't magic either. It's process managers reacting to events and dispatching commands — the same pattern used throughout this book for order processing, capability management, and every other business process.

The magic, if there is any, is in the composition. A single agent is a tool. A relay of agents, connected by process managers, pausing at human gates, accumulating decisions in a dossier — that's a development team. A strange, tireless, occasionally wrong development team that writes everything down and never argues about tabs versus spaces. It makes mistakes. (They all do. Every tool I've used in thirty-five years makes mistakes. The good ones make their mistakes visible.) But it makes them transparently, in a format you can audit, replay, and learn from.

Watch the relay run. See each agent hand off to the next. Approve the decisions that matter. Reject the ones that don't. At the end, you have not just code — you have a complete, replayable record of how that code came to be.

The machines collaborate. You watch. When they need you, they stop and ask.

That's the relay. We tried three other architectures first — a monolith, a batch pipeline, and a tightly-coupled service mesh. Each one recapitulated a failure mode I'd seen before in thirty-five years of building systems. The relay works because it applies the patterns that have always worked: loose coupling, explicit routing, durable messages, and human checkpoints. It's not the road most traveled. This is the one that stuck.
