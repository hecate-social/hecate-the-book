# Chapter 15: Martha Studio

*Building the command center for AI-assisted development*

---

I've been using development tools since vi on a VT220 terminal in 1990. I've watched every generation of IDE promise to make programming effortless. Turbo Pascal gave us integrated compilation and a debugger in the same window — revolutionary at the time. Visual Studio gave us IntelliSense and made us believe the IDE could understand our code. Eclipse gave us refactoring tools and a plugin ecosystem that could do almost anything, if you could figure out which of the three thousand plugins you needed. IntelliJ gave us "intelligent" code assistance that actually worked most of the time. VS Code gave us speed and a marketplace that made Eclipse's ecosystem look quaint.

Each generation got something right. Each generation also overpromised on the "effortless" part. I've used every IDE from vi to VS Code. Each one promised to make me 10x more productive. I'm now theoretically 10^7x productive. My actual output has not changed proportionally.

And now we're in the AI generation, where the promise is even bigger: the tool doesn't just assist you — it writes the code for you. I've been here before. In the 90s, CASE tools — Computer-Aided Software Engineering — promised that you'd draw diagrams and the tool would generate the code. Rational Rose, Together, PowerDesigner. They generated code, all right. The code was usually a skeleton that you had to fill in by hand, and the round-trip between diagram and code was so fragile that after the first manual edit, the diagram and the code were permanently divorced. The tools died not because the idea was wrong, but because the generated output was opaque. You couldn't see *why* the tool made the choices it made, and you couldn't steer it when it went wrong.

The first version of Martha was embarrassing in exactly the same way. It was a text area, a "Generate" button, and a scrollable div that showed the LLM's response. You typed your vision, hit the button, waited 30 seconds, and got back a wall of text describing your architecture. Martha v1 could generate code. It could also generate code that looked perfect, compiled cleanly, and did absolutely nothing useful — like a very expensive screensaver. It felt like a slightly fancier ChatGPT wrapper. Which, to be fair, is exactly what it was.

The problem wasn't the AI's output — it was actually decent. The problem was that you couldn't *see* anything happening. You'd press the button and stare at a spinner. Then a massive block of text would appear all at once. Did the AI consider three bounded contexts and reject one? You'd never know. Did it design the aggregate before or after identifying the events? No idea. The process was invisible. The result was a monolith of text that you had to read top-to-bottom, hoping you'd catch the parts that mattered.

Same failure as CASE tools, thirty years later. Opaque generation. Invisible decisions. No steering.

That's when we realized Martha needed to be a command center, not a chat window. Every other AI tool was building a better chatbot. We stepped sideways. You can't watch a machine think. But you can watch it *decide* — if you model its decisions as events, and you build a UI that renders those events in real time.

Martha Studio is that window. It's a real-time command center for AI-assisted software development, showing you every decision being made, every gate waiting for approval, every agent currently running. It turns the venture lifecycle (Chapter 13) from an abstract process model into something you can see, steer, and trust.

This time the "tool that writes code" might actually work. Not because the AI is smarter than Rational Rose's code generator — though it is, by a wide margin. Because we learned from thirty-five years of tool failures that the tool's intelligence doesn't matter if the human can't see what it's doing and can't intervene when it goes wrong. Martha is built on that lesson.

Martha is also a case study in how to build a modern frontend for an event-sourced backend. The challenges are specific: the data is temporal, not static. State arrives as a stream of events, not a response to a query. The UI needs to react in real time without polling. And the whole thing ships as a plugin (Chapter 14), which means it has to work as a web component embedded in a host application.

---

## The Three-Zone Layout

Martha's interface is organized into three zones, each serving a distinct purpose. We went through at least six layout iterations before landing on this one. The first was a single-column timeline. The second was a two-pane split (tree on the left, detail on the right). The third was... let's just say "ambitious" and leave it there. (I've spent enough time with UI frameworks over the decades to know that "ambitious" in a layout meeting means "we'll be rewriting this in two weeks.") The three-zone layout survived because it answers the three questions you always have: "What's the state of the whole venture?" (NerveCenter), "What needs my attention?" (VentureBar), and "What am I looking at right now?" (Workspace).

**The VentureBar** spans the top of the screen. It shows the current venture name, lets you select which AI model to use, displays a gate badge (showing how many decisions are pending), and provides toggles for the agent pipeline and gate system. This is your dashboard strip — always visible, always telling you the current state of play.

**The NerveCenter** occupies the left sidebar. This is the structural view of your venture. Each division appears as a card with color-coded phase dots: blue for planning, green for crafting, amber for testing. Agent role statuses show which AI agents are currently active. Gate statuses show which decisions are pending. Think of it as the control tower — you see the whole airfield at a glance.

**The Workspace** fills the main area, with the ActivityRail running along the bottom. The workspace switches modes depending on what you're looking at: an overview of the whole venture, a gate inbox for pending decisions, the agent pipeline showing AI progress, or a detailed view of a specific division. The ActivityRail streams live events as they happen — a continuous scroll of what the system is doing right now. It's mesmerizing in the way that watching a build log is mesmerizing, except the events are business decisions, not compiler output.

```
┌─────────────────────────────────────────────────────────┐
│ VentureBar: [Venture Name] [Model: ▼] [🔔 3] [Agents] │
├────────────┬────────────────────────────────────────────┤
│            │                                            │
│ NerveCenter│           Workspace                        │
│            │                                            │
│ ○ Auth Div │   (VentureOverview | GateInbox |           │
│   ●● ○     │    AgentPipeline | DivisionDetail)         │
│            │                                            │
│ ○ Billing  │                                            │
│   ●○ ○     │                                            │
│            │                                            │
├────────────┴────────────────────────────────────────────┤
│ ActivityRail: [14:32:01 aggregate_designed_v1] [...]    │
└─────────────────────────────────────────────────────────┘
```

---

## Workspace Modes

The workspace isn't a single view — it's a mode switcher that adapts to what you're doing:

**VentureOverview** is the default. Division graph cards show each bounded context with its current phase and progress bars. Live agent activity pulses in real time. This is the "what's happening across the whole venture" view. When everything is running smoothly, it's genuinely beautiful — cards pulsing gently as agents work, progress bars advancing, phase dots lighting up one by one.

**GateInbox** shows pending decisions. Each gate is an expandable card with context — what the AI decided, why it chose that approach, and what alternatives it considered. You can pass or reject. If you reject, a form asks for the reason, which gets recorded as an event and fed back to the agent. The inbox splits into pending and decided sections so you can review past decisions. This is where the human-in-the-loop actually happens, and getting the UX right mattered enormously. Early versions showed the AI's raw output in a code block. Now each gate card is structured: here's what the agent proposes, here's its reasoning, here's what it considered and rejected. You're reviewing a recommendation, not parsing a text dump. After years of reading code review comments in tools from Crucible to Gerrit to GitHub PRs, I know that the format of the review matters as much as the content. Present a wall of text and people skim. Present structured reasoning and people engage.

**AgentPipeline** visualizes the chain of AI agents working on the current division. Each agent appears as a node in a pipeline, showing its status (waiting, running, completed, failed, gate-pending). You can see which agent is currently active, what it's working on, and what comes next.

**DivisionDetail** drills into a specific division and offers four sub-views:

- **Storm** — the discovery brainstorming view, showing identified concepts and relationships
- **Plan** — the architectural planning view, showing designed aggregates, events, and desks
- **Kanban** — a task board showing generation progress
- **Craft** — the code generation view, showing generated modules and test results

---

## The Event Bridge

Martha's frontend doesn't poll. It receives a real-time stream of events through Server-Sent Events (SSE). The plumbing that makes this work is the event bridge — and it's one of those components that sounds simple until you build it.

On the backend, `app_marthad_event_bridge` is a gen_server that subscribes to the `$all` stream on Martha's ReckonDB store. Every event that occurs in the venture lifecycle — every aggregate designed, every planning opened, every gate decision — flows through the bridge:

```erlang
-module(app_marthad_event_bridge).

init(StoreId) ->
    ok = reckon_db:subscribe(StoreId, <<"$all">>, self()),
    pg:join(martha_sse, self()),
    {ok, #{store_id => StoreId}}.

handle_info({event, Event}, State) ->
    %% Forward to all SSE handler processes
    lists:foreach(
        fun(Pid) -> Pid ! {sse_event, Event} end,
        pg:get_members(martha_sse) -- [self()]
    ),
    {noreply, State}.
```

On the frontend, a SvelteKit SSE handler connects to `/plugin/martha/api/events/sse` and receives these events as a text stream. Each event arrives as JSON, gets parsed, and updates the reactive state:

```typescript
function connectEventStream(ventureId: string) {
    const source = new EventSource(
        `/plugin/martha/api/events/sse?venture_id=${ventureId}`
    );

    source.onmessage = (event) => {
        const parsed = JSON.parse(event.data);
        handleEvent(parsed);
    };
}

function handleEvent(event: DomainEvent) {
    switch (event.event_type) {
        case 'AggregateDesigned.v1':
            aggregates = [...aggregates, event.data];
            break;
        case 'PlanningOpened.v1':
            planningStatus = 'open';
            break;
        case 'GatePending.v1':
            pendingGates = [...pendingGates, event.data];
            gateBadgeCount = pendingGates.length;
            break;
    }
}
```

The pg (OTP process groups) group `martha_sse` acts as a broadcast channel. Every connected SSE handler joins this group. When the bridge receives an event from the store, it fans it out to every handler. When a browser disconnects, its handler process terminates and is automatically removed from the group. No cleanup code, no connection tracking, no stale-connection bugs. OTP's process lifecycle does the work.

This is event-driven UI at its purest: the same events that drive the backend state drive the frontend display. There's no translation layer, no REST polling interval, no stale data. The UI is a live projection of the event stream. The first time we got this working end-to-end — an AI agent designing an aggregate and watching the card appear in Martha Studio two seconds later — it felt like the whole architecture finally made sense. The events weren't just a persistence mechanism. They were the nervous system connecting backend decisions to frontend pixels. After decades of building UIs that polled REST endpoints on timers and showed stale data more often than fresh, this felt like something genuinely new.

---

## Svelte 5 Runes and Reactive State

Martha's frontend is built with Svelte 5, which introduces runes — a new reactivity model that replaces Svelte 4's implicit reactivity with explicit declarations:

```svelte
<script>
    let { venture } = $props();

    let divisions = $state([]);
    let selectedDivision = $state(null);
    let pendingGates = $state([]);

    let gateBadgeCount = $derived(pendingGates.length);

    let activeDivisions = $derived(
        divisions.filter(d => (d.status & 4) === 4) // OPEN flag
    );

    $effect(() => {
        if (venture?.id) {
            connectEventStream(venture.id);
        }
    });
</script>
```

`$state` declares reactive variables. `$derived` creates computed values that update automatically. `$effect` runs side effects when dependencies change. `$props` receives component inputs. No stores, no subscriptions, no boilerplate. The reactive graph is explicit in the code.

This pairs naturally with event sourcing. Each incoming event mutates a `$state` variable. Derived values recalculate. The DOM updates. The flow is:

```
SSE event → handleEvent() → $state mutation → $derived recalc → DOM patch
```

One reactive pipeline from backend event to pixel on screen. Svelte 5's runes make this pipeline visible in the code — you can trace the path from SSE event to DOM update by reading the component top to bottom. No hidden magic, no implicit subscriptions, no "where does this value get updated?" mysteries. For an event-sourced UI, this explicitness is a gift.

---

## Smart Model Selection

Martha doesn't just let you pick an AI model from a dropdown. It scores models against the current task and recommends the best fit.

This feature was born from a frustration that anyone who's used AI coding tools will recognize: we kept accidentally using the most expensive model for boilerplate generation and the cheapest model for complex architecture decisions. The cost was silly and the quality was inconsistent. It's the same lesson I learned twenty years ago with build servers — you don't run your integration tests on the same machine as your linter. Match the tool to the task. So we automated the thing we should have been doing manually all along.

The scoring engine classifies available models into tiers:

```typescript
type ModelTier = 'flagship' | 'balanced' | 'fast' | 'local';
type TaskAffinity = 'code' | 'creative' | 'general';

interface LLMModel {
    name: string;
    context_length: number;
    family: string;
    parameter_size: string;
    format: string;
    provider: string;
}
```

Each tier has different strengths. Flagship models (Claude Opus, GPT-4) handle complex architectural decisions — designing aggregates, identifying bounded contexts. Balanced models (Claude Sonnet, GPT-4o) handle the bulk of code generation. Fast models (Claude Haiku, GPT-4o-mini) handle boilerplate and test scaffolding. Local models (Ollama) handle sensitive operations that shouldn't leave the machine.

When the venture lifecycle needs to design an aggregate, Martha's model selector evaluates: this is a code task with high complexity. It recommends a flagship model. When it needs to generate a boilerplate handler module, it recommends a fast model. The user can always override, but the default is intelligent.

```typescript
function scoreModel(model: LLMModel, task: TaskRequirement): number {
    let score = 0;

    // Context window must fit the task
    if (model.context_length >= task.estimatedTokens) score += 30;

    // Tier affinity
    if (task.complexity === 'high' && getTier(model) === 'flagship') score += 40;
    if (task.complexity === 'low' && getTier(model) === 'fast') score += 40;

    // Task type affinity
    if (task.type === 'code' && model.family === 'claude') score += 20;

    // Prefer local for sensitive operations
    if (task.sensitive && model.provider === 'ollama') score += 50;

    return score;
}
```

The scoring is deliberately simple. We could have built something more sophisticated — factoring in latency, cost per token, recent performance — but the 80/20 rule applies. The simple scorer eliminates the worst mismatches (Haiku designing your database schema, Opus writing boilerplate getters) and that's enough to make a real difference in both quality and cost. Left to its own devices, a developer will always select the model the way they select a restaurant: the most impressive one they can expense.

---

## Building as a Web Component

Martha's frontend must ship as a plugin. That means it can't be a standalone SvelteKit application served from its own origin. It needs to be a web component — a custom element that the host application drops into its DOM.

This was one of those decisions that sounded simple in a meeting and took three weeks to get right. Web components and SvelteKit have different ideas about routing, about lifecycle, about how the DOM works. Getting them to agree required some creative build configuration. It reminded me of embedding Java applets in the late 90s, or ActiveX controls in Internet Explorer — the host and the guest always have different opinions about who owns the page.

The build pipeline uses Vite in library mode:

```typescript
// vite.config.lib.ts
export default defineConfig({
    build: {
        lib: {
            entry: 'src/lib/component.ts',
            name: 'MarthaStudio',
            fileName: 'component',
            formats: ['es']
        },
        outDir: 'dist'
    },
    plugins: [svelte({
        compilerOptions: {
            customElement: true
        }
    })]
});
```

The entry point registers the custom element:

```typescript
// src/lib/component.ts
import MarthaStudio from './MarthaStudio.svelte';

customElements.define('martha-studio', MarthaStudio);
```

The compiled `dist/component.js` gets copied to the daemon's `priv/static/` directory. When hecate-web loads the plugin page, it injects a `<script>` tag pointing to `/plugin/martha/ui/component.js`, which registers the custom element. Then it renders `<martha-studio>` into the page.

The `shadow="none"` attribute is critical. Without it, the web component would use Shadow DOM, isolating its styles from the host. Martha needs to inherit the host's theme — dark mode, font choices, color palette. By opting out of Shadow DOM, Martha's components share the host's CSS context. The visual result is that Martha feels native — not like a plugin bolted onto the side, but like a natural part of the application.

---

## SvelteKit Routes as Business Capabilities

Martha's internal routing mirrors the venture lifecycle's business capabilities:

```
routes/
├── compose_vision/     ← venture inception
├── storm_division/     ← division discovery
├── plan_division/      ← architectural planning
├── kanban_division/    ← task tracking during generation
└── craft_division/     ← code generation and testing
```

These aren't technical route names. They're business capabilities. A developer looking at this directory tree knows exactly what Martha does: compose visions, storm divisions, plan them, track work on a kanban, and craft code. No `pages/`, no `views/`, no `components/` — the choices were unconventional, deliberately so, and the directory structure screams its intent.

Each route directory contains its Svelte components, its API client functions, and its local state management. No shared `stores/` directory. No centralized `api/` layer. Each capability owns everything it needs.

This is vertical slicing (Chapter 3) applied to a frontend. The same principle that organizes the backend — group by capability, not by technical layer — works just as well in a SvelteKit application. We were skeptical at first. Frontend frameworks push you hard toward shared component libraries and centralized state stores. But the same arguments that apply to backend code apply here: when you need to understand how vision composition works, you open one directory. Everything is there.

---

## Real-Time Confidence

The deepest value of Martha Studio isn't the layout or the model selection or the clever event bridge. It's confidence.

When you watch an AI agent design your system's aggregates in real time, seeing each decision appear as an event, seeing each gate pause for your approval, seeing each rejected decision get revised — you develop trust in the process. Not blind trust, but informed trust. You know what's happening because you're watching it happen.

The alternative — running a prompt, waiting for a wall of text, reading through thousands of lines of generated code hoping it's correct — is the current state of AI-assisted development. It's terrifying. You don't know what the machine decided or why. You review after the fact, looking for mistakes in code you didn't write and don't fully understand.

I've been here before, in a different form. In the late 90s, code generators promised to turn UML diagrams into running applications. They generated code that compiled. But when something went wrong, you were debugging generated code that didn't match any mental model you had. The code wasn't yours, and you couldn't explain it. Today's AI coding assistants have the same problem at a larger scale — they generate more code, faster, and the gap between "generated" and "understood" is wider than ever.

Martha inverts this. Every architectural decision is an event. Every event appears in the ActivityRail. Every significant decision pauses at a gate. You're not reviewing after the fact. You're steering in real time.

We debated whether the gate system was paternalistic. Why make the human approve every decision? Why not let the AI run autonomously? Then an early prototype confidently designed a system with a single aggregate called "MainEntity" that handled every operation in the entire domain. One table. One aggregate. The AI had essentially proposed a database schema with one table called "data" and one column called "json." I admired its commitment to minimalism. It compiled. It even had decent test coverage. It was also a masterclass in how to build an unmaintainable monolith. After that, the gates stayed. I've been writing software long enough to know that any tool powerful enough to be useful is powerful enough to be dangerous. The gates aren't paternalism. They're the same principle as code review, applied at the architectural level.

The command center doesn't replace the AI. It makes the AI legible. And legibility, it turns out, is the thing that was missing from AI-assisted development all along. Not better models. Not better prompts. A window into the process, with a hand on the brake. Every generation of development tools, from vi to VS Code to Copilot, has been a story about visibility — seeing more of what matters, faster. Martha is the next chapter in that story.
