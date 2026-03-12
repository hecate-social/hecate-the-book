# Chapter 19: What Comes Next

*Self-modifying codebases and evolutionary deployment*

---

If you've read this far, you're either convinced or morbidly curious. Either way, thank you. This has been a long book about a system that doesn't look like anything else, built on principles that most of the industry has chosen to ignore, running on hardware that most people would call inadequate. I'm aware of how that sounds. I've been making this pitch, in various forms, for three decades -- to skeptical managers, to pragmatic engineers, to venture capitalists who wanted hockey-stick growth charts instead of architecture diagrams. The pitch has gotten better. The skepticism hasn't changed much.

Everything we've built so far is concrete. Running code, real hardware, actual deployments. Four beam nodes in a home lab, connected by a mesh, storing events, running agents, generating code through gated pipelines. The autonomous stack isn't a whitepaper. It's a system you can SSH into.

This final chapter looks forward. Not to fantasies, but to extensions that the existing architecture naturally supports -- capabilities that emerge when you follow the design principles to their logical conclusions. Some of these are months away. Some are years. Some may never arrive. But they're all architecturally possible, and that matters more than timelines.

I want to be honest about something: some of these ideas might be wrong. I've been wrong before -- spectacularly, publicly, expensively wrong. I thought expert systems would transform business software in the late 80s. I thought CORBA would solve distributed computing in the mid-90s. I thought P2P file sharing would remake content distribution in the early 2000s. Predicting the future of technology is a fool's errand. I know because I've been doing it for thirty-five years. Each time, the idea was directionally right but the timing, the tools, or the economics were wrong. Some of the ideas in this chapter will suffer the same fate. But every one of them is a straight line from decisions we've already made, and that's what keeps me working on this when the sensible thing would be to ship what we have and call it done. The path didn't always make sense while we were on it. It's starting to.

---

## Self-Modifying Codebases

The agents in the current system generate code. They take a venture's architectural vision, decompose it into divisions, plan each division's aggregates and events, and generate Erlang modules that implement them. The code works. The tests pass. The human gate approves.

But the agents don't understand the code they've generated. Not really. They produce it through LLM inference -- pattern matching against training data, guided by prompts and architectural constraints. The generated code is correct, but the agents have no persistent model of it. Ask the same agent to refactor the code tomorrow and it starts from scratch, re-reading the files, re-inferring the structure.

This is the gap between generating code and understanding code, and it's a gap that everyone working with LLMs has bumped into. Generation is surprisingly easy. Understanding is surprisingly hard. Self-modifying codebases sound terrifying until you remember that most codebases already modify themselves -- they just use a slower, less reliable mechanism called "the development team."

The dream of self-modifying codebases is older than most people working in software today. Lisp had it in the 1960s -- code as data, programs that rewrote themselves. Smalltalk lived it in the 1970s -- the entire development environment was a running program modifying itself. Genetic programming formalized it in the 1990s -- I remember reading Koza's first book and thinking "this changes everything." It didn't. Not then. The programs were too small, the fitness functions too crude, the compute too expensive.

What's different now is specific, and after watching three waves of "self-modifying software" promises crash, I can articulate exactly what changed. First: LLMs can generate structurally correct code at the module level, something no previous approach could do reliably. Second: the event store makes every modification auditable and reversible, which removes the terrifying "what did it change and why" problem that killed every previous attempt. Third: the human gate means the system proposes modifications but doesn't apply them unsupervised, which is the safety valve that Lisp and genetic programming never had.

The next step is agents that maintain a living model of the codebase. Not just "I can read the files" but "I know the dependency graph, the event flow, the aggregate state machines, the projection update paths, and the process manager coordination patterns." An agent with this knowledge doesn't just generate -- it refactors. It notices that two projections are racing on the same ETS table and merges them. It spots a process manager that could be simplified. It identifies dead code from a deprecated event version and removes it.

This is feasible because the codebase follows screaming architecture. The directory structure IS the domain model. An agent that reads the file tree learns the bounded contexts, the commands, the events, and the relationships between them -- not from comments or documentation, but from the structure itself. `apps/design_division/src/open_design/` tells the agent everything it needs to know about that desk's responsibility.

We made that architectural choice years ago for human reasons -- we wanted developers to navigate the codebase by intuition. It turns out we were also making the codebase legible to machines. I've been building systems that try to explain themselves since my first mainframe debugging session in 1991, when I spent three days tracing a batch job failure through code that had been modified by six different people over eight years and documented by none of them. Every architectural decision since then has been, in some way, an attempt to make sure that never happens again. Screaming architecture is the latest and most successful attempt. That it also makes the code legible to AI agents was genuinely unintentional -- but it's the kind of consequence that only appears when you wander far enough from the familiar to find something you weren't looking for.

The event store makes this safer. Every refactoring decision is a command. Every outcome is an event. If a refactoring breaks something, the event stream shows exactly what happened, and the code can be regenerated from the last known good state. Refactoring becomes an event-sourced process with its own dossier: `refactoring_proposed_v1`, `refactoring_approved_v1` (human gate), `modules_modified_v1`, `tests_executed_v1`, `refactoring_completed_v1`.

The human gate remains. An agent proposes a refactoring. The gate reviews. The agent applies or discards. Self-modifying doesn't mean unsupervised. It means the system can propose improvements to itself -- and a human decides whether those improvements are actually improvements.

---

## Evolutionary Deployment

Deployment in the current system is simple: CI builds an image, pushes to ghcr.io, podman pulls and restarts. It works. It's also static -- every node runs the same image, the same configuration, the same resource allocation.

Neuroevolution can make deployment adaptive. Consider the parameters that a deployment strategy must choose:

- How many instances of each service?
- Which nodes host which services?
- How much memory allocated to each?
- What's the rolling update strategy?
- When should a canary deployment proceed or roll back?

These are optimization problems with complex, multi-dimensional fitness landscapes. The "right" answer depends on current load, node capabilities, network topology, and failure history. It changes over time. It's not something you configure once and forget -- though that's exactly what most of us do, because the alternative is exhausting.

An evolutionary approach would maintain a population of deployment strategies, each encoded as a genome. Fitness is measured by real metrics: request latency, error rate, resource utilization, recovery time from failures. High-fitness strategies survive and reproduce. Low-fitness strategies are culled. Over time, the population converges on deployment patterns that work well for the actual workload.

The mesh makes this tractable. Each node reports its metrics to the mesh. The evolutionary controller (running on whichever node has capacity) aggregates metrics, evaluates fitness, and produces new strategy candidates. The strategies propagate as integration facts. Each node adapts independently.

This isn't as radical as it sounds. The beam cluster already does something similar in a manual way: we observe which nodes handle which workloads well, and we adjust `.container` files accordingly. Evolution just automates the observation and adjustment loop. We're not replacing human judgment -- we're replacing human busywork. The judgment stays; the toil goes.

I've been doing this manually for thirty-five years -- watching dashboards, adjusting parameters, reacting to incidents, tuning configurations. Every ops engineer I've ever worked with has been doing the same. I started my career debugging COBOL on a green screen. I'm ending it debugging neural networks on a mesh of mini-PCs. The screens got better. The bugs didn't. The knowledge of "beam02 handles this workload better" lives in somebody's head, gets lost when they change jobs, and has to be rediscovered by the next person. Encoding that knowledge as a fitness function and letting evolution maintain it isn't just more efficient -- it's more durable. The knowledge survives personnel changes because it's in the event stream, not in somebody's memory.

---

## Agents That Learn from Their Mistakes

The current gate system is binary: an agent's output passes or fails human review. The agent doesn't learn from the failure. It doesn't adjust its behavior. Next time, it generates code using the same approach, and possibly makes the same mistake.

This is the part that bothers me most about the current system. We have this beautiful event store full of detailed records -- what was generated, what was rejected, why -- and we're not using any of it to improve the agents themselves. It's like keeping a journal and never reading it.

LTC meta-controllers change this. A Liquid Time-Constant network with a slow time constant can track gate pass/reject ratios over time and adjust agent parameters accordingly:

```
L0 (fast tau):   Individual agent actions
                 Generate module, run tests, submit for review

L1 (medium tau): Meta-controller per agent
                 Tracks pass/reject ratio per generation
                 Adjusts prompt templates, model selection, context length
                 Time constant: ~1 sprint (days to weeks)

L2 (slow tau):   Strategic controller
                 Tracks meta-controller effectiveness across projects
                 Learns which adjustment strategies work
                 Time constant: ~1 quarter (weeks to months)
```

The L0 layer is what we have now: agents executing tasks. The L1 layer would sit alongside, observing outcomes. When a particular agent consistently gets gate rejections for test quality, L1 adjusts: perhaps a different LLM model for test generation, or a more explicit prompt template, or additional context from the venture's testing guidelines.

The L2 layer learns from L1's learning. If L1 consistently finds that switching to a larger model improves gate pass rates, L2 encodes this as a meta-strategy: "when pass rates drop, try a larger model before trying prompt changes." L2 operates across projects, building strategic knowledge that transfers.

This is the "Liquid Conglomerate" model from neuroevolution research, applied to the development pipeline. Multiple timescales of adaptation, each one informing the next, all grounded in observable metrics (gate pass/reject events in the event store).

The beauty of this is that it doesn't require the agents to be "smarter." It requires the system to have a memory of what worked and a mechanism for adjusting parameters. Both of those already exist. We just haven't connected them yet.

---

## The Mesh as a Marketplace

Chapter 17 introduced the market model: nodes advertise capabilities, other nodes consume them. This is currently simple -- capability advertisements are mesh facts, consumption is direct.

The natural extension is a full marketplace with reputation, pricing, and specialization.

**Reputation scores** emerge naturally from event history. A node that consistently provides fast, accurate LLM inference builds a reputation through observable behavior -- response times, generation quality (measured by gate pass rates downstream), and availability. The reputation isn't assigned; it's projected from the event stream, the same way any read model is projected.

**Pricing** doesn't have to mean money. It can mean reciprocity: I consumed 10 GPU-hours from your node, so I owe you 10 GPU-hours of compute. Or it can mean priority: nodes that contribute more get faster access during peak demand. The mesh already has the accounting infrastructure -- every interaction is an event, every event has a timestamp and a participant.

**Specialization** means nodes that focus. A node with a powerful GPU becomes the neuroevolution specialist. A node with a large LLM becomes the code generation specialist. A node with abundant storage becomes the event store archive. Specialization emerges from the market: nodes naturally gravitate toward workloads where their hardware gives them an advantage.

The mesh carries all of this without modification. Capability advertisements are pub/sub messages. Reputation is a CRDT that converges across nodes. Task assignment is an RPC call. Content delivery is the Want/Have/Block protocol. The infrastructure is already there; the marketplace is a pattern on top.

What excites me about this isn't the economics -- it's the emergence. Nobody designs the specialization. Nobody assigns roles. Nodes find their niche because the system rewards doing what you're good at. That's not a feature we built. It's a property that appears when you combine a market with evolutionary pressure. I've seen this pattern in organizations over thirty-five years -- the formal org chart says one thing, but the actual flow of work follows competence, not hierarchy. We're just encoding that natural tendency into the infrastructure.

---

## Content-Addressed Code Distribution

Today, Erlang packages come from hex.pm. You declare a dependency in `rebar.config`, run `rebar3 deps`, and hex.pm serves the tarball. It works. It's also centralized, and it doesn't know about your mesh.

MCID-based distribution offers an alternative. When an agent generates a module, the compiled BEAM file gets an MCID -- a hash of its content. When a test suite is generated, each test module gets an MCID. When a release is assembled, the entire release tarball gets an MCID.

These MCIDs propagate through the mesh. A node that needs a specific module version doesn't ask a central registry. It asks the mesh: "Who has MCID abc123?" Any node that has it responds. The requesting node downloads from the closest or fastest respondent.

This doesn't replace hex.pm for external dependencies. It extends the distribution model for internal artifacts -- the code your agents generate, the releases your CI builds, the test results your pipelines produce. These artifacts move through the same mesh that carries events and capability advertisements. No separate artifact storage system. No separate CDN. No separate package registry.

Version management becomes content management. Instead of "give me version 1.2.3 of module X," you say "give me MCID abc123." If the content is the same, the MCID is the same, regardless of version numbering. If the content differs by one byte, the MCID is different, regardless of whether anyone bumped the version.

---

## Multi-Venture Collaboration

The current system models one venture at a time. A venture has divisions, divisions have departments, departments have desks. Clean hierarchy.

But real organizations work on multiple ventures simultaneously. And ventures share infrastructure -- a user authentication division might serve three different product ventures. A payment processing division might be consumed by every venture in the organization.

Multi-venture collaboration means divisions can be shared. A shared division has its own event stream, its own aggregate, its own lifecycle. Multiple ventures reference it. When the shared division evolves (a new event version, a refactored aggregate), the change propagates to all consuming ventures through integration facts.

Process managers handle the coordination. When Venture A's user authentication division publishes `authentication_scheme_updated_v1` as a mesh fact, Venture B's process manager receives it and dispatches `update_auth_dependency_v1` to its own integration division. Each venture reacts independently. No central dependency manager. No monorepo coordination tool.

This is organizational event sourcing. The same principle that coordinates desks within a division now coordinates divisions across ventures. Events are facts. Facts propagate. Recipients decide what to do.

---

## Neuroevolution of Agent Prompts

Here's an idea that the current architecture makes surprisingly feasible -- and one that I find genuinely exciting, even knowing it might not work as well as the theory suggests.

Evolving prompt templates through natural selection.

The system already has the ingredients:

**Variation** -- prompt templates can be modified: different system instructions, different few-shot examples, different output format specifications. Each variation is a candidate in a population.

**Selection pressure** -- gate pass rates provide fitness. A prompt template that consistently produces code the human gate approves has high fitness. A template that produces code the gate rejects has low fitness.

**Reproduction** -- high-fitness templates are combined. Take the system instruction from Template A and the few-shot examples from Template B. Mutate a parameter. Run the offspring.

**Islands** -- different nodes can evolve different prompt populations. beam01 evolves prompts for test generation. beam02 evolves prompts for aggregate design. Periodic migration exchanges the best templates.

The event store tracks everything: which template was used, what code was generated, whether the gate approved. Fitness is a projection -- a read model built from the event stream. Template genomes are content-addressed and distributed via the mesh.

This is not prompt engineering. It's prompt evolution. The difference: a human engineer tries variations and keeps what seems to work, limited by their own experimental bandwidth. Evolution tries thousands of variations, keeps what actually works (measured by gate pass rate), and explores regions of the prompt space that a human would never think to visit.

The human gate still decides. Evolution just ensures the gate sees better candidates over time.

I've watched optimization techniques cycle through the industry for decades -- operations research in the 70s and 80s, simulated annealing in the 90s, genetic algorithms in the 2000s, gradient descent everywhere now. Each one was a hammer looking for nails. What makes evolutionary prompt optimization different is that we already have the fitness function (gate pass rates), the variation mechanism (prompt templates are just text), and the infrastructure to run thousands of experiments across distributed nodes. We're not looking for a nail. The nail found us.

---

## Agent Specialization Through Evolution

A fresh LLM agent is a generalist. It can generate any kind of code, write any kind of test, produce any kind of documentation. It does all of these adequately and none of them exceptionally.

Evolutionary pressure changes this. An agent that consistently generates excellent aggregate implementations but mediocre test suites will, over time, be assigned more aggregate work and less test work. Not because a manager decided, but because the market model matches capabilities to demand, and the agent's track record (projected from the event stream) shows where it excels.

Take this further. If agents carry parameters that influence their behavior -- model selection, temperature, context window size, prompt template, reference material -- then evolution can tune these parameters independently for each agent role. The aggregate specialist gets a low-temperature, detailed prompt. The test generator gets a higher temperature and broader context. The documentation writer gets different few-shot examples.

Over generations, the agent population differentiates. Not through explicit configuration, but through selection pressure on observable outcomes. The agents that pass gates survive. The parameters that produce gate-passing agents propagate.

This mirrors biological specialization. Cells in an organism start identical and differentiate based on environmental signals. Agents in the mesh start identical and specialize based on evolutionary signals -- fitness measured by gate outcomes, propagated through the event stream, applied through parameter adjustment.

There's a philosophical question lurking here that I don't have an answer to: at what point does an evolved agent configuration stop being a "tool with tuned parameters" and start being something with its own character? I don't know. But I think the question is worth asking, and the system we've built is the kind of system where the question becomes practical rather than theoretical. After thirty-five years in this industry, the questions that interest me most are the ones that start as theoretical and become practical. This might be one of them.

---

## The Philosophical Endpoint

Follow the thread all the way out and you arrive at a system that doesn't look like software development as we know it.

Conventional software is built. Engineers write code. They decide the architecture. They choose the algorithms. They deploy the result. The software is an artifact -- a thing made by humans, for humans, reflecting human decisions at every level.

The autonomous stack points toward software that is grown. Agents generate the code. Neuroevolution optimizes the parameters. The mesh distributes the artifacts. The event store remembers everything. The system adapts, improves, and specializes over time.

Grown, not built. Cultivated, not constructed.

I want to be careful here, because this is where technical books usually veer into hype, and I have no interest in hype. I've read too many books that ended with breathless predictions about the future -- the AI books of the 80s, the object-oriented manifestos of the 90s, the agile proclamations of the 2000s, the blockchain gospels of the 2010s. Each one was going to transform everything. Each one transformed something, just not what the authors predicted, and not on the timeline they promised. I have no reason to believe my predictions will be more accurate. This is not a prediction that all software will be built this way. It's an observation that some software *can* be built this way, and the implications are worth sitting with.

This is not the same as "autonomous." The system doesn't make its own decisions about what to build. It doesn't set its own goals. It doesn't define its own fitness functions. Those remain human responsibilities. And frankly, I think they should stay human responsibilities. The autonomous stack isn't about replacing developers. It's about amplifying them -- giving them a system that handles the mechanical parts of software development so they can focus on the parts that require actual thought: what to build, for whom, and why.

What the system does is execute. Given a vision (human), decompose it into bounded contexts (agent, human-approved). Given a bounded context, design its aggregates and events (agent, human-approved). Given a design, generate the implementation (agent, human-approved). Given an implementation, test it (agent, human-approved). Given a passing test suite, deploy it (automated, human-initiated).

At every stage, the human gate stands. Hecate, the goddess of crossroads, stands at every decision point. The agents propose. The humans dispose. The event store records. The system learns.

---

## What Remains Human

It would be dishonest to end this book without naming what the autonomous stack cannot automate. And I mean *cannot*, not *should not* -- though both apply.

**Vision.** The system can decompose a vision into divisions and implement them. It cannot decide what should be built. "Build a marketplace for neural network models" is a human decision. The system doesn't want things. It doesn't need things. It doesn't imagine things. I've spent enough time working with LLMs to know that the appearance of imagination is not imagination. The gap between generating plausible text and having genuine intent is not a gap that more compute will close. I've heard "computers will do everything" since the first AI hype cycle I lived through in the late 80s. They won't. They'll do more and more of the mechanical work, and the boundary of what counts as "mechanical" will keep shifting, but the direction -- the why -- stays human.

**Judgment.** The human gate exists because judgment cannot be automated. Not "shouldn't be" -- cannot be. Judgment requires values, context, intuition, and accountability. An LLM can estimate quality. It cannot take responsibility for the consequences of a decision.

**Ethics.** When the neuroevolution system optimizes for gate pass rates, it's optimizing for a metric. Metrics can be gamed. Ethics cannot be measured. The human who sets the fitness function and reviews the outcomes is responsible for ensuring the system optimizes for the right things, not just measurable things.

**The gates themselves.** The most important architectural decision in the entire stack is where to put the human gates. Too many gates and the system stalls -- every decision waits for human attention. Too few and the system runs unsupervised -- generating code, deploying artifacts, and evolving parameters without oversight. Placing the gates is a design decision that requires deep understanding of risk, trust, and consequence. And it's a decision that should be revisited as the system matures and trust is earned -- or lost.

These are not limitations to be overcome. They are the boundaries that make the system trustworthy. A fully autonomous system with no human gates would be powerful and irresponsible. A system where humans set direction, approve transitions, and maintain accountability -- that's a tool worth building.

---

## The Crossroads

Hecate stood at crossroads. Not to block the path, but to illuminate it. Travelers chose their own direction. The goddess held the torch.

The autonomous stack is a crossroads technology. It doesn't decide where software development goes. It illuminates possibilities. Decentralized collaboration without central servers. Event-sourced processes without mutable state. Evolutionary optimization without manual tuning. AI-generated code without unsupervised deployment.

Each of these paths is open. Which ones we walk -- and how far -- remains a human decision.

I started this project because I was tired. Not the tiredness of a beginner who doesn't know how hard things are, but the tiredness of someone who's spent thirty-five years knowing exactly how hard things are and watching the industry make them harder. Tired of centralized infrastructure that fails when a single company has a bad day. Tired of mutable state that lies about what happened. Tired of deployment processes that require more ceremony than the code they deploy. Tired of AI tools that generate code with no audit trail and no accountability. Tired of integration layers that exist only because the layers they connect were never designed to talk to each other. The autonomous stack isn't about replacing developers. It's about making sure I never have to manually configure a CORBA naming service again. After thirty-five years, I've earned the right to have machines do the parts I've already done a thousand times.

I've been building toward this for three decades, even when I didn't know it. Every event-sourced system I built was a step toward ReckonDB. Every time I argued for vertical slicing over horizontal layers was a step toward screaming architecture. Every painful integration between incompatible systems was a lesson that eventually became the autonomous stack. The vision didn't arrive fully formed. It accumulated, the way event streams do -- one slip at a time, each one making the pattern a little clearer.

I don't know if any of this will work at the scale the industry demands. Nobody does -- not yet. I've seen too many scale predictions be wrong, in both directions. Technologies that were supposed to scale to millions died at hundreds. Technologies that were never supposed to work ran the internet. Thirty-five years of watching predictions fail has made me humble about timelines and stubborn about principles. The principles are sound. The timeline is unknown. That's an honest position, and it's the only one I'm willing to defend.

What I know is that every piece of it works today, on four small machines in a home lab, connected by a mesh that nobody controls, storing events that nobody can alter, running agents that nobody trusts without verification.

And I know that the principles are sound. Event sourcing gives you truth. Peer-to-peer gives you resilience. Vertical slicing gives you clarity. Human gates give you accountability. Evolution gives you adaptation. Put them together and you get something that feels, for the first time in thirty-five years of building software, like infrastructure that respects both the humans who use it and the complexity of what it does.

I started on a mainframe terminal in 1990. I'm ending on a mesh of mini-PCs in 2026. The hardware changed. The networks changed. The languages changed. But the fundamental problem -- building systems that are truthful, resilient, and comprehensible -- hasn't changed at all. This whole book has been an exploration, not a manifesto -- an attempt to see what else was possible when you stopped assuming the obvious approach was the only one. I've just gotten better at recognizing what matters and what doesn't. What matters is immutable truth, loose coupling, human oversight, and the humility to let the system evolve beyond what you designed. What doesn't matter is everything else -- the frameworks, the cloud providers, the hype cycles, the conference talks. They come and go. The principles remain.

The dossier stays open. There are more slips to add.

Pass it to the next desk.
