# Chapter 11: LLM Orchestration

*Agents, roles, tiers, and the relay pattern*

---

I need to say something that will be unpopular in certain circles: Large Language Models are the most overhyped and underarchitected technology of the decade. Everyone is building with them. Almost nobody is building well.

I say this as someone who has lived through every AI hype cycle since expert systems. This is the fourth time in my career I've been told that AI will replace programmers. CASE tools in the nineties were going to generate all our code from diagrams. Model-driven development in the 2000s was going to make hand-coding obsolete. Low-code platforms in the 2010s were going to let "citizen developers" replace us. LLMs now. Each time, the prediction was wrong. Each time, the tools DID change what developers do. And each time, the people who built well with the new tools thrived, while the people who believed the hype without architecting for reality produced expensive messes.

LLMs are different from the previous waves in important ways — they're genuinely more capable, more general, more surprising. I don't deny that. After thirty-five years of watching AI promises, I'm genuinely impressed by what these models can do. But being impressed and being uncritical are different things, and the gap between "impressive demo" and "reliable production system" is exactly where good architecture lives.

The standard approach — the one I started with, the one most tutorials teach, the one that dominates the ecosystem — is to wrap an API call in a function, stuff a system prompt into it, and call it an "agent." Maybe you add some tool use. Maybe you chain a few calls together. Congratulations: you've built a function approximator with a marketing department. The result is brittle, opaque, and impossible to debug. When something goes wrong — and it always goes wrong — you're staring at a chat log trying to figure out which prompt in which chain produced the hallucination that corrupted everything downstream.

I spent a genuinely miserable weekend once tracking down a bug where our "architecture agent" had hallucinated a database table that didn't exist, the "code generation agent" had written perfectly valid code against this phantom table, and the "test agent" had written passing tests by mocking the non-existent table. Three agents, all confidently wrong, each one reinforcing the others' delusion. The architecture was surprisingly clean. The system was working perfectly. The output was garbage. LLMs are the most confident interns you'll ever hire — they'll rewrite your entire codebase at 3 AM with complete certainty, and half of it will compile. It reminded me of expert systems in the late eighties — beautiful chains of inference that produced nonsense because one axiom was wrong and nothing in the system could notice.

That's when we decided — against the grain of every LLM framework on the market — that LLM orchestration has to be event-sourced. Every agent interaction is a command dispatched to an aggregate. Every response is an event recorded permanently. Every state transition follows the same dossier model described in Chapter 1. The LLM is powerful, but it's not special. It's just another clerk at a desk, processing dossiers according to rules.

This wasn't a radical insight. It was the obvious conclusion for anyone who'd spent decades building audit-critical systems. In banking, in telecom, in healthcare — anywhere the consequences of getting it wrong are serious — you record everything. Every transaction, every decision, every state change. Of course you'd do the same thing with an AI pipeline that's making architectural decisions about your software. The only people who find this surprising are the ones who've never had to explain to a regulator what happened and why.

This chapter describes Martha — Hecate's AI-assisted software development plugin — as the concrete example. But the patterns apply to any LLM orchestration system.

---

## Twelve Roles, Not One God-Prompt

The first mistake everyone makes with LLMs is overloading a single agent. "You are a helpful AI assistant that can write code, review architecture, plan projects, and also be creative." This is the god-object antipattern applied to prompts. It works for demos. It fails for production.

I resisted the twelve-role design for a while. Not because it felt like over-engineering — I've been in this industry long enough to know that what looks like over-engineering at the start often looks like the minimum viable design six months later. I resisted because I kept thinking a sufficiently good prompt could do everything. "Can't one good prompt handle all of this?" I kept asking. I'd watched the industry go through this exact cycle before — with expert systems in the eighties, people started with one big knowledge base and eventually learned to decompose it into specialized modules. It took me longer than it should have to recognize the same pattern.

Then I watched a single-prompt agent try to simultaneously be creative about product vision AND rigorous about event schema design. It was like asking someone to write poetry and debug a race condition at the same time. The outputs were mediocre at everything and excellent at nothing.

Martha defines twelve distinct agent roles:

| Role | Purpose | Phase |
|------|---------|-------|
| **visionary** | Define the product vision and goals | Discovery |
| **explorer** | Identify bounded contexts and boundaries | Discovery |
| **stormer** | Design aggregates, events, and commands | Design |
| **reviewer** | Review and critique designs | Design |
| **architect** | Produce architectural decisions and structure | Architecture |
| **erlang_coder** | Write Erlang/OTP code | Implementation |
| **svelte_coder** | Write Svelte/TypeScript frontend code | Implementation |
| **sql_coder** | Write SQL schemas and migrations | Implementation |
| **tester** | Write and run tests | Testing |
| **delivery_manager** | Coordinate delivery and release | Delivery |
| **coordinator** | Orchestrate multi-agent workflows | Meta |
| **mentor** | Guide and teach the human operator | Meta |

Each role has a dedicated system prompt. Each prompt is loaded from a file, not embedded in code:

```erlang
load_agent_role(visionary) ->
    {ok, Prompt} = file:read_file("priv/prompts/visionary.md"),
    Prompt;
load_agent_role(explorer) ->
    {ok, Prompt} = file:read_file("priv/prompts/explorer.md"),
    Prompt.
```

The prompts are long, detailed, and opinionated. The visionary prompt doesn't just say "define a product vision." It specifies the output format, the questions to ask, the structure of a good vision document, and the antipatterns to avoid. Each prompt encodes the expertise of a specific role — not generic helpfulness, but domain mastery.

Writing these prompts was one of the most interesting challenges in the whole project. Prompt engineering is the art of talking to a very fast, very confident, very drunk genius. You can't just say "design an event model." You have to say "design an event model, but don't use CRUD verbs, and don't forget the aggregate invariants, and please for the love of all that is holy don't invent entities we didn't ask for." You're essentially writing a job description for an intelligence that has read everything but experienced nothing. The good prompts aren't the ones that tell the LLM what to do — they're the ones that tell it what NOT to do, what to prioritize, and what "good" looks like in this specific context. That last part is the hard-won knowledge. It took me decades of building systems to know what "good" looks like for event schema design. Encoding that into a prompt that a language model can act on is a strange and fascinating form of knowledge transfer.

---

## Each Role Is a Vertical Slice

Here's where the architecture from Part I pays off. Each agent role is implemented as a vertical slice — a desk in the dossier model:

```
apps/guide_venture/src/
├── initiate_visionary/
│   ├── initiate_visionary_v1.erl          ← command
│   ├── visionary_initiated_v1.erl         ← event
│   └── maybe_initiate_visionary.erl       ← handler
├── complete_visionary/
│   ├── complete_visionary_v1.erl          ← command
│   ├── visionary_completed_v1.erl         ← event
│   └── maybe_complete_visionary.erl       ← handler
├── on_visionary_initiated_run_visionary_llm/
│   └── on_visionary_initiated_run_visionary_llm.erl  ← process manager
```

The pattern repeats for every role. `initiate_{role}` dispatches a command. The aggregate records the initiation event. A process manager — `on_{role}_initiated_run_{role}_llm` — subscribes to that event type and kicks off the actual LLM call.

This is not over-engineering. (I know it looks like it. I've been building systems long enough to know that the developers who call things "over-engineering" on day one are often the same ones calling them "critical infrastructure" on day ninety. "All this ceremony for an API call?" But keep reading.)

It's the same structure used for every other business process in the system. The LLM call is a side effect triggered by a process manager, just like sending an email or publishing to the mesh. The aggregate tracks the lifecycle:

```
fresh → INITIATED → COMPLETED | AWAITING_INPUT | FAILED
                          ↓
                   GATE_PENDING (for gated roles)
                          ↓
              GATE_PASSED | GATE_REJECTED
                          ↓
                      ARCHIVED
```

Every state transition is an event. Every event is persisted. The entire history of an agent's work on a venture — every prompt sent, every response received, every gate decision — is permanently recorded in the event store.

The first time something went wrong in production and I was able to replay the exact sequence of LLM calls, see the exact context each agent received, and pinpoint exactly where the hallucination started — that's when the ceremony earned its keep. I've been debugging production systems since the early nineties. The ones that recorded everything were always easier to fix than the ones that didn't. This is the same principle, applied to a new kind of system.

---

## The Per-Role LLM Runner

The process manager for each role follows the same pattern:

```erlang
-module(on_visionary_initiated_run_visionary_llm).
-behaviour(evoq_process_manager).

interested_in() -> [<<"VisionaryInitiated.v1">>].

handle(#{event_type := <<"VisionaryInitiated.v1">>, data := Data}) ->
    VentureId = maps:get(<<"venture_id">>, Data),
    SessionId = maps:get(<<"session_id">>, Data),

    %% Load the role's system prompt
    SystemPrompt = load_agent_role:load(visionary),

    %% Build the conversation context
    Messages = build_context(VentureId, SessionId, SystemPrompt),

    %% Select the right model for this task
    Model = select_model(creative, flagship),

    %% Call the LLM
    case chat_to_llm:chat(Model, Messages, #{stream => false}) of
        {ok, Response} ->
            %% Parse the structured output
            Parsed = martha_notation:parse(Response),
            %% Dispatch the completion command
            evoq:dispatch(complete_visionary_v1:new(#{
                venture_id => VentureId,
                session_id => SessionId,
                output => Parsed
            }));
        {error, Reason} ->
            evoq:dispatch(fail_visionary_v1:new(#{
                venture_id => VentureId,
                session_id => SessionId,
                reason => Reason
            }))
    end.
```

The LLM call itself — `chat_to_llm:chat/3` — is deliberately simple. It takes a model identifier, a list of messages, and options. It returns `{ok, Response}` or `{error, Reason}`. No streaming abstractions, no callback chains, no middleware stacks. Just a function call.

The intelligence is in what surrounds the call: the prompt selection, the context building, the output parsing, and most importantly, the event-sourced lifecycle that makes every step auditable.

I want to emphasize that last point because it's the thing I didn't appreciate until I needed it. When your LLM pipeline produces weird output — and it will, regularly — the question is never "what happened?" It's "where in the chain did it go wrong?" With function-call chaining, you add logging after the fact and hope you captured enough. With event sourcing, the entire chain is already recorded. You query the event store, walk through the sequence, and find the exact moment the LLM zigged when it should have zagged.

---

## Smart Model Selection

Not every task needs GPT-4. Not every task can survive GPT-3.5. This was another lesson learned the expensive way — our first prototype used the most capable model for everything. The API bills were... educational. We were using a flagship model to format JSON. That's like hiring a Michelin-star chef to make toast. The toast was excellent, but the invoice was not. Then again, I've been paying for computing education since 1990. At least this time the tuition receipt was itemized.

Martha implements a tiered model selection system that matches tasks to models:

```erlang
%% Model tiers
-define(FLAGSHIP,  flagship).   %% Best quality, highest cost
-define(BALANCED,  balanced).   %% Good quality, moderate cost
-define(FAST,      fast).       %% Quick responses, lower quality
-define(LOCAL,     local).      %% On-device models, zero cost

%% Task affinities
-define(CODE,      code).       %% Code generation/review
-define(CREATIVE,  creative).   %% Vision, design, writing
-define(GENERAL,   general).    %% Coordination, management
```

Model selection considers three dimensions:

**Tier classification**: How capable does the model need to be? Visionary work needs flagship. Code formatting needs fast. The tier is determined by the role.

**Task affinity**: What kind of work is it? Code generation benefits from models trained on code. Creative work benefits from models with better language capabilities. The affinity is determined by the specific task within a role.

**Context window scoring**: How much context does this call need? A code review that needs to see 50 files requires a large context window. A simple completion needs minimal context. The score determines which models are eligible.

```erlang
select_model(TaskAffinity, Tier) ->
    Available = get_available_models(),
    Filtered = lists:filter(fun(M) ->
        model_tier(M) =:= Tier andalso
        model_affinity(M) =:= TaskAffinity
    end, Available),
    %% Score by context window, latency, cost
    Scored = [{score(M), M} || M <- Filtered],
    {_, Best} = lists:max(Scored),
    Best.
```

Model metadata is stored as plain data:

```erlang
model_metadata(<<"claude-opus-4">>) ->
    #{name => <<"claude-opus-4">>,
      context_length => 200000,
      family => anthropic,
      tier => flagship,
      affinity => [code, creative, general],
      parameter_size => undefined,
      format => api,
      provider => anthropic};

model_metadata(<<"llama3.1:8b">>) ->
    #{name => <<"llama3.1:8b">>,
      context_length => 128000,
      family => llama,
      tier => local,
      affinity => [general],
      parameter_size => <<"8B">>,
      format => gguf,
      provider => ollama}.
```

The system supports both cloud APIs and local models (via Ollama). A venture might use Claude for visionary work and a local Llama for routine code formatting. The model selection is transparent — every LLM call event records which model was used and why. No surprises. No hidden costs. When the bill comes, you can trace every dollar to a specific agent, a specific role, a specific task.

---

## The Venture Pipeline

Individual agent roles are useful. The pipeline that connects them is where the real value emerges.

Martha's venture pipeline chains roles through process managers. Each process manager subscribes to the completion event of one phase and initiates the next:

```
venture_initiated_v1
    → PM: on_venture_initiated_initiate_visionary
        → visionary_initiated_v1
            → PM: on_visionary_initiated_run_visionary_llm
                → visionary_completed_v1
                    → GATE: vision_gate (human review)
                        → gate_passed_v1
                            → PM: on_vision_gate_passed_initiate_explorer
                                → explorer_initiated_v1
                                    → PM: on_explorer_initiated_run_explorer_llm
                                        → explorer_completed_v1
                                            → GATE: boundary_gate (human review)
                                                → gate_passed_v1
                                                    → ... stormer → design_gate → reviewer → ...
```

The pipeline is not hardcoded as a sequential workflow. It's a chain of independent process managers, each reacting to events. This means:

**Parallelism is natural.** If two roles can run simultaneously (they share no dependencies), their process managers both fire on the same trigger event. No coordination code needed.

**Failure is contained.** If the stormer's LLM call fails, only `stormer_failed_v1` is recorded. The pipeline stops at that point. The visionary and explorer outputs are safe. Retry the stormer — the aggregate knows exactly where it left off. I can't overstate how important this is. LLM APIs fail. They time out. They rate limit you. They occasionally return gibberish. Having a pipeline that gracefully handles all of this without losing work is the difference between a toy and a tool. I've been building production systems long enough to know that the interesting engineering isn't the happy path — it's what happens when things go wrong at three in the morning.

**New roles plug in.** Adding a new agent role is adding a new vertical slice and a new process manager. No changes to existing code. The pipeline extends by composition.

**The pipeline is visible.** Query the event store for a venture's stream and you see every step: which roles ran, what they produced, which gates they passed through, how long each step took. The pipeline is its own audit log.

---

## Martha Notation and Output Parsing

LLM output is unstructured text. The venture pipeline needs structured data — lists of bounded contexts, aggregate definitions, code modules. The bridge is **Martha notation**: a lightweight markup format that LLMs produce reliably and parsers consume efficiently.

```erlang
martha_notation:parse(<<"
## Bounded Contexts

### OrderManagement
- Aggregates: Order, LineItem
- Events: OrderPlaced, OrderShipped, OrderCancelled
- Commands: PlaceOrder, ShipOrder, CancelOrder

### Inventory
- Aggregates: StockItem, Warehouse
- Events: StockReserved, StockReleased
- Commands: ReserveStock, ReleaseStock
">>) ->
    #{contexts => [
        #{name => <<"OrderManagement">>,
          aggregates => [<<"Order">>, <<"LineItem">>],
          events => [<<"OrderPlaced">>, <<"OrderShipped">>, <<"OrderCancelled">>],
          commands => [<<"PlaceOrder">>, <<"ShipOrder">>, <<"CancelOrder">>]},
        #{name => <<"Inventory">>,
          aggregates => [<<"StockItem">>, <<"Warehouse">>],
          events => [<<"StockReserved">>, <<"StockReleased">>],
          commands => [<<"ReserveStock">>, <<"ReleaseStock">>]}
    ]}.
```

The notation is designed for LLM reliability, and this is a design decision born of pain. We tried JSON first. LLMs frequently produce invalid JSON — missing commas, trailing commas, unescaped characters, truncated output. We tried YAML. Indentation-sensitive formats and LLMs don't mix — it turns out an intelligence trained on the entire internet still can't reliably count spaces, which honestly makes me feel better about my own YAML struggles. We tried XML. I don't want to talk about it.

Martha notation uses markdown headers (which every LLM produces consistently), bullet points (which rarely get mangled), and simple key-value patterns. Just headers and bullets that a simple parser can extract. It's not elegant. It's robust. Those are different things, and in production, you want the second one. I've been choosing "robust over elegant" for thirty-five years and I've never regretted it once.

Each role's prompt specifies the expected output format in Martha notation. The corresponding parser knows what to extract. When the LLM deviates from the format — and it will — the parser either recovers gracefully or the process manager dispatches a failure event with the raw output, allowing retry with corrective feedback.

---

## The Event Bridge: Real-Time Visibility

When a venture pipeline runs, humans want to watch. There's something almost hypnotic about seeing the agent roles fire in sequence — like watching a relay race where each runner is an AI.

Martha's event bridge subscribes to the orchestration store's `$all` stream and forwards events to connected SSE (Server-Sent Events) clients:

```erlang
%% Event bridge process
event_bridge_loop(Clients) ->
    receive
        {event, #{event_type := Type, data := Data} = Event} ->
            Payload = json:encode(#{
                type => Type,
                data => Data,
                timestamp => maps:get(timestamp, Event)
            }),
            %% Forward to all connected SSE clients
            [Client ! {sse, Payload} || Client <- Clients],
            event_bridge_loop(Clients);

        {subscribe, ClientPid} ->
            event_bridge_loop([ClientPid | Clients]);

        {unsubscribe, ClientPid} ->
            event_bridge_loop(lists:delete(ClientPid, Clients))
    end.
```

The frontend displays a live feed: "Visionary initiated... Calling Claude Opus... Response received... Parsing output... Visionary completed... Awaiting vision gate approval..."

Every event in the pipeline is visible in real time. No polling. No log tailing. The event stream IS the UI data source, just as the event stream IS the audit log and the event stream IS the persistence layer. One stream, many consumers. This is the payoff of event sourcing that's hard to appreciate until you experience it: you build the persistence layer once, and the real-time UI, the audit log, the debugging tools, and the analytics dashboard all fall out of it for free.

---

## Why Event-Sourced LLM Orchestration

You might wonder: is event sourcing overkill for LLM calls? After all, most frameworks just chain function calls together. Why the ceremony?

I wondered too. For about two months, I thought we were over-engineering. Then three things happened in the same week that changed my mind permanently.

**Auditability.** A venture produced bad code. The bounded contexts were wrong. I needed to know why. Was the vision off? Did the explorer miss a context? Did the stormer design the wrong aggregates? I queried the event store and walked through the entire pipeline in fifteen minutes. I found the exact moment the explorer made a wrong assumption — it was visible in the event payload. In a function-call chain, I would have been adding print statements and re-running the entire pipeline to reproduce the issue. I've debugged production systems for decades. The ones you can replay are the ones you can fix.

**Resumability.** We hit a rate limit during the stormer phase. The API returned a 429 and the LLM call failed. In a regular pipeline, everything would have been lost — re-run from the top. With event sourcing, the visionary and explorer outputs were already persisted. We waited thirty seconds, retried the stormer, and it picked up exactly where it left off. No re-running successful steps. No lost work. No re-spending on API calls that had already succeeded.

**Composability.** We needed a new role — `sql_coder` — that we hadn't anticipated. Adding it was a new vertical slice and a new process manager. Zero changes to existing code. The pipeline grew by composition, not modification. The whole thing took an afternoon. While everyone else was building LLM wrappers that optimized for the demo, we'd built infrastructure that optimized for the sixth month.

This is the open-closed principle enforced by architecture, not discipline. And that matters, because discipline fails at 2 AM when you're debugging a production issue. I've been there enough times to know.

The next chapter addresses the most important piece of the pipeline — the points where machines must stop and ask a human for judgment. Gates aren't a limitation. They're the feature that makes the whole system trustworthy.
