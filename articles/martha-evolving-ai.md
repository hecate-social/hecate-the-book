# What If Your AI Coding Tool Actually Learned From You?

I've been using AI coding tools daily for over a year now. They were impressive on day one. They are exactly as impressive on day 365.

They still suggest horizontal service layers when I've corrected them hundreds of times. They still generate CRUD event names after I've explained business verbs in every session. They still reach for wrapper modules when I want direct Erlang calls. Every single morning, I start from zero.

I've been building software since 1990. I've watched four waves of "AI will replace programmers." The tools get better. The tools never learn.

## The Question Nobody's Asking

The entire industry is locked in an arms race over the same variables: bigger models, longer context windows, more training data, faster inference. Billions of dollars chasing marginal improvements on benchmarks that don't map to real engineering work.

Here's the question nobody seems to be asking: **what if the tool adapted to you?**

Not fine-tuning. Fine-tuning is expensive, requires ML infrastructure most teams don't have, and means your proprietary code leaves your machine to become someone else's training data. Not RAG either. Retrieval-augmented generation can look things up, but it doesn't learn. It doesn't get better over time. It's a search engine with a language model stapled to it.

I mean actual adaptation. The tool measurably improves at working with your specific codebase, your architectural patterns, your naming conventions, your taste. Not because someone trained a bigger foundation model. Because it watched you work and adjusted.

## Your Decisions Are Fitness Signals

Here's what we noticed when we stopped thinking about AI tools as chat interfaces and started thinking about them as evolving systems.

Every interaction between an engineer and an AI coding tool produces a signal. You approve a suggestion — that's a positive signal. You reject it and rewrite — negative. The generated code compiles — positive. It fails the type checker — negative. You accept the first draft — strong positive. You go through four revision cycles — the tool picked the wrong approach.

**These signals are everywhere. Nobody is using them.**

If you event-source your AI tool's interactions — every prompt, every model choice, every human review decision, every compile result, every test outcome — you end up with a rich stream of labeled data. Not labeled by mechanical turkers in a data center. Labeled by you, the engineer, doing your actual work.

The insight is simple: your engineering judgment, expressed through thousands of approve/reject decisions over months of work, is a training signal. A very good one. And it's unique to you.

## Five Things That Could Evolve

Once you have that signal stream, the question becomes: what do you point the optimization at? We found five layers where small neural networks, trained through evolutionary optimization, produce compounding returns.

**Model selection.** Most AI coding tools use the same model for everything. That's like hiring a senior architect to write boilerplate getters. A small network can learn which tasks in your workflow need the expensive model and which ones a cheaper, faster model handles just fine. Stop paying for Opus when Haiku would do. We expect significant cost reduction with no quality loss — because the selector learns your specific task distribution, not a generic benchmark.

**Gate prediction.** Current tools either auto-apply everything (dangerous) or interrupt you for approval on everything (exhausting). A network that has watched you approve and reject thousands of suggestions can predict your decision with increasing accuracy. High confidence? Apply automatically. Low confidence? Ask. The interruption rate drops over time as the predictor gets better at modeling your preferences. The human stays in the loop — but only where the human is actually needed.

**Prompt strategy.** The way you frame a request to a language model matters enormously, and what works depends on the codebase. A prompt that produces clean vertical slices for an event-sourced Erlang system is different from one that works for a React frontend. Evolution can explore the space of prompt construction strategies and select for the ones that produce code you accept. Not generic "prompt engineering." Prompt engineering that's been optimized against your specific rejection patterns.

**Pipeline composition.** Complex coding tasks often run through multi-step pipelines: analyze, plan, generate, review, test. But not every task needs every step. Some are simple enough to skip planning. Some need extra review. A network can learn which pipeline configurations work for which task types in your workflow, cutting latency on straightforward work while adding rigor where your history says it's needed.

**Overall strategy.** This is the meta-layer. Across weeks and months, a higher-level optimization watches the other four layers and adjusts the balance. Maybe your codebase went through a refactoring phase where accuracy mattered more than speed. Maybe you're in a prototyping sprint where the opposite is true. The strategy layer adapts to your current mode of work, not just your long-term preferences.

None of these require massive compute. We're talking about small networks — a few hundred parameters — evolving through selection pressure from your real decisions. It runs on the kind of hardware you already have.

## Privacy by Architecture, Not Privacy by Policy

This is where things get interesting from a trust perspective.

When you use Copilot, your code goes to Microsoft's servers. When you use Cursor, your code goes to their infrastructure. They have privacy policies. They promise not to train on your data. Maybe they keep that promise. Maybe they don't. You're trusting a policy document.

**What if the architecture made the question irrelevant?**

When the evolutionary optimization runs on your hardware, using your local event store, producing networks that live on your machines — there's nothing to leak. Your rejection patterns, your architectural preferences, the evolved networks that encode your engineering judgment — none of it ever leaves your cluster.

Not because we promised it wouldn't. Because there's no mechanism for it to.

Privacy by architecture is a fundamentally different proposition than privacy by policy. One requires trust in a corporation. The other requires trust in physics.

## The Compounding Moat

This brings us to the part that keeps me up at night — in a good way.

On day one, an evolving AI tool is exactly like every other AI tool. Same foundation models. Same capabilities. Same limitations. Nothing special.

On day 100, it's noticeably better. The model selector is saving you money. The gate predictor is interrupting you less. The prompt strategies are producing code that matches your style more often than not.

**On day 1000, it's irreplaceable.** The evolved networks encode a year of your accumulated engineering judgment. Your architectural taste. Your naming instincts. Your quality threshold. The thousand subtle preferences that make your code yours.

You can't copy that. You can't download someone else's evolved networks and get the same benefit — their engineering judgment isn't yours. You can't fast-track it by throwing more compute at it, because the bottleneck isn't processing power, it's the slow accumulation of real decisions made during real work.

This is earned, not installed.

Every day you use the tool, the moat gets deeper. Not for the vendor. For you. Your evolved AI assistant is your competitive advantage, not theirs.

## The Human Gate Isn't Overhead

Every AI coding tool treats the human review step as friction to be minimized. "How do we get to full automation?" is the question driving the industry.

We asked a different question: what if the human review step is the most valuable part?

Every time you approve or reject a suggestion, you're not just doing quality control. You're generating a fitness signal. You're training your system. You're making it more yours. The review isn't overhead to be eliminated. **It's the mechanism by which the tool becomes valuable.**

The engineer isn't a bottleneck in this architecture. The engineer is the selection pressure that makes the whole thing work.

I've spent 35 years watching our industry oscillate between "automate everything" and "humans are essential." The answer, as usual, is more nuanced than either extreme. The human and the machine are better as a co-evolutionary system than either is alone.

We're not building a better AI coding tool. We're building one that builds itself — with you as the selection pressure.

---

This is the core thesis behind Martha, an open-source project built on the BEAM (Erlang/OTP). The architecture, the philosophy, and the evolutionary mechanisms are documented in a free book: *The Autonomous Stack: An Exploration into Another Path*.

The book is free. The code is open. The path is different.
