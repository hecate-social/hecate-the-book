# Chapter 12: The Human Gate

*When machines must stop and ask*

---

There's a seductive idea in AI-assisted development: let the machine do everything. Give it a product description, let it design the architecture, generate the code, write the tests, deploy it. Full autonomy. Zero human involvement. The ultimate developer experience is no developer at all.

I've been hearing this promise since expert systems in the late eighties. "Encode the knowledge, let the system reason, humans become optional." Then it was CASE tools in the nineties — draw the diagram, generate the code, ship the product. Then model-driven development. Then low-code platforms. Now LLMs. The technology changes. The promise doesn't. And the outcome has been the same every time: the tools get more capable, the developers adapt to use them, and the need for human judgment at critical decision points never goes away. Full autonomy for AI is like self-driving cars — always five years away, and for similar reasons. The last 5% of edge cases contains 95% of the difficulty.

I believed the LLM version of this promise for about six weeks. Then I watched an agent pipeline design a perfectly coherent, beautifully structured, completely wrong system. The vision was clear. The bounded contexts were crisp. The event model was elegant. The code compiled on the first try. And the whole thing solved a problem the user hadn't actually asked for, because the visionary had misinterpreted the initial brief and every subsequent agent had diligently built on that misinterpretation.

Nobody caught it because nobody was watching.

This idea — full autonomy — is wrong. Not because the technology isn't capable enough — though it isn't, not yet — but because it misunderstands what "autonomous" means. And I say this not from theoretical conviction but from thirty-five years of watching automated systems interact with the real world.

An autonomous car doesn't drive without rules. It follows lanes, obeys traffic lights, yields to pedestrians. Its autonomy is bounded by a framework of constraints designed by humans. The constraints aren't limitations on the car's capabilities — they're the reason you trust the car at all.

Manufacturing figured this out decades ago. Quality gates on production lines. Aviation figured it out with pre-flight checklists and crew resource management. Nuclear power figured it out with defense in depth and human-in-the-loop protocols for critical operations. The lesson is always the same: the more capable and autonomous the system, the more important the checkpoints where humans verify that the system's model of reality still matches actual reality.

Hecate's agent pipeline works the same way. Agents have genuine autonomy within their roles. The visionary autonomously produces a product vision. The explorer autonomously identifies bounded contexts. The stormer autonomously designs aggregates and events. But between certain roles — at critical decision points where the consequences of being wrong are high — the pipeline stops. A gate opens. A human must look at the output, consider it, and decide: pass or reject.

These gates are the most important feature in the entire system — and the one that runs most directly counter to the industry's obsession with removing humans from every loop. I don't say that lightly. More important than the LLM orchestration. More important than the event sourcing. More important than the twelve specialized roles. Because without gates, you have a very sophisticated way of producing output you can't trust.

---

## Four Gates, Four Decisions

Martha's pipeline has four gates, each placed after a role whose output shapes everything that follows:

| Gate | After Role | What's Reviewed | Why It Matters |
|------|-----------|-----------------|----------------|
| **vision_gate** | visionary | Product vision and goals | Everything downstream builds on this. A wrong vision means a well-built wrong product. |
| **boundary_gate** | explorer | Bounded context boundaries | Wrong boundaries create wrong microservices. This is the hardest thing to fix later. |
| **design_gate** | stormer | Aggregate and event designs | The event model IS the system. Wrong events are wrong forever (event stores are append-only). |
| **review_gate** | reviewer | Design critique and feedback | The last chance to catch design issues before code generation begins. |

Notice where the gates are. They're all in the early phases — discovery and design. There's no gate after code generation. No gate after testing. Why?

Because the cost of being wrong decreases as you move through the pipeline. A wrong product vision wastes months. Wrong bounded contexts create structural debt that never goes away. Wrong events poison the event store permanently. But wrong code? You delete it and regenerate. Wrong tests? Same. The damage from a bad code generation step is minutes of wasted compute. The damage from a bad vision is a failed product.

Gates are placed where human judgment has the highest leverage. This wasn't obvious to us at first. Our early prototype had gates after every single role — including code generation and testing. The pipeline ground to a halt. Humans were rubber-stamping gates they didn't really need to review, which meant they were also rubber-stamping gates they DID need to review. Gate fatigue is real, and it is the silent killer of every approval process ever designed. I've seen the same phenomenon in every gated process I've encountered over thirty-five years — security review boards that approve everything because they review too many things, code review processes where the fifth PR of the day gets a rubber stamp, change advisory boards that wave through changes at 4 PM on Friday. If you ask a human to approve twelve things, they'll carefully review the first three and click "pass" on the rest. By gate number seven, they'd approve a plan to rewrite the billing system in Brainfuck if it meant they could go to lunch. So we did the hard work of figuring out which four decisions actually matter.

---

## The Gate Mechanism

A gate is not a separate system. It's part of the aggregate's state machine, implemented with the same event-sourcing machinery as everything else.

When an agent completes a gated phase, the aggregate transitions to `GATE_PENDING`:

```erlang
%% In the orchestration aggregate
apply(State, #{event_type := <<"VisionaryCompleted.v1">>, data := Data}) ->
    State#{
        status => ?GATE_PENDING,
        pending_gate => vision_gate,
        gate_output => maps:get(<<"output">>, Data),
        completed_phases => [visionary | maps:get(completed_phases, State, [])]
    }.
```

The pipeline stops. No process manager fires. No next role initiates. The dossier sits on the human's desk, waiting for a stamp. The human gate is the architectural equivalent of "let me see that before you send it." Every parent, every editor, and every code reviewer knows why this exists. The machine has opinions. You have judgment. Those are different things.

There's something I find deeply satisfying about this. The entire event-sourced, process-managed, LLM-orchestrated pipeline — all that machinery — comes to a complete stop and waits for a human to think. The machine has done its work. Now it's your turn. Take your time. It reminds me of the old mainframe batch processing days, where the operator had to mount the next tape. Except now the "tape" is a product vision document and the "operator" is making a judgment call that will shape everything that follows.

Two commands can advance it:

```erlang
%% pass_gate_v1: human approves the output
-module(pass_gate_v1).

new(#{venture_id := VentureId, gate := Gate}) ->
    #{command_type => <<"PassGate.v1">>,
      stream_id => <<"venture-", VentureId/binary>>,
      data => #{
          <<"gate">> => Gate
      }}.

%% reject_gate_v1: human rejects the output
-module(reject_gate_v1).

new(#{venture_id := VentureId, gate := Gate, reject_reason := Reason}) ->
    #{command_type => <<"RejectGate.v1">>,
      stream_id => <<"venture-", VentureId/binary>>,
      data => #{
          <<"gate">> => Gate,
          <<"reject_reason">> => Reason
      }}.
```

The aggregate validates the gate command against its current state:

```erlang
execute(#{status := ?GATE_PENDING, pending_gate := Gate} = State,
        #{command_type := <<"PassGate.v1">>, data := Data}) ->
    case maps:get(<<"gate">>, Data) =:= Gate of
        true  -> {ok, [gate_passed_v1:new(State, Data)]};
        false -> {error, wrong_gate}
    end;

execute(#{status := ?GATE_PENDING, pending_gate := Gate} = State,
        #{command_type := <<"RejectGate.v1">>, data := Data}) ->
    case maps:get(<<"gate">>, Data) =:= Gate of
        true  -> {ok, [gate_rejected_v1:new(State, Data)]};
        false -> {error, wrong_gate}
    end;

execute(#{status := Status}, #{command_type := <<"PassGate.v1">>})
        when Status =/= ?GATE_PENDING ->
    {error, no_pending_gate}.
```

On pass, a process manager initiates the next role in the pipeline:

```erlang
-module(on_vision_gate_passed_initiate_explorer).
-behaviour(evoq_process_manager).

interested_in() -> [<<"GatePassed.v1">>].

handle(#{event_type := <<"GatePassed.v1">>, data := Data}) ->
    case maps:get(<<"gate">>, Data) of
        <<"vision_gate">> ->
            VentureId = maps:get(<<"venture_id">>, Data),
            evoq:dispatch(initiate_explorer_v1:new(#{
                venture_id => VentureId
            }));
        _ ->
            ok  %% Not our gate
    end.
```

On reject, the aggregate records the rejection reason and can either re-run the role with feedback or halt the pipeline entirely:

```erlang
apply(State, #{event_type := <<"GateRejected.v1">>, data := Data}) ->
    State#{
        status => ?GATE_REJECTED,
        pending_gate => undefined,
        reject_reason => maps:get(<<"reject_reason">>, Data),
        rejection_count => maps:get(rejection_count, State, 0) + 1
    }.
```

---

## Progressive Refinement

Rejection isn't failure. It's feedback.

This is the part that surprised me the most about how the system works in practice. I expected rejections to feel punitive — "the AI got it wrong, try again." Instead, they feel collaborative. The human isn't correcting the machine. They're having a conversation with it, mediated by the event stream.

I've seen this dynamic before, actually. In the early days of expert systems, the knowledge engineers had a similar relationship with the domain experts — iterative refinement through structured dialogue. The tool is different. The pattern is the same. Humans are good at recognizing quality and articulating what's wrong. Machines are good at generating options and incorporating feedback. The combination is more powerful than either alone.

When a human rejects a gate, they provide a reason: "The vision is too broad — focus on the core workflow, not the entire platform." This reason is recorded in the event stream. The role can be re-initiated with the rejection reason as additional context:

```erlang
-module(on_gate_rejected_retry_role).
-behaviour(evoq_process_manager).

interested_in() -> [<<"GateRejected.v1">>].

handle(#{event_type := <<"GateRejected.v1">>, data := Data}) ->
    Gate = maps:get(<<"gate">>, Data),
    VentureId = maps:get(<<"venture_id">>, Data),
    Reason = maps:get(<<"reject_reason">>, Data),

    %% Re-initiate the role with rejection context
    Role = gate_to_role(Gate),
    evoq:dispatch(reinitiate_role_v1:new(#{
        venture_id => VentureId,
        role => Role,
        previous_rejection => Reason
    })).
```

The LLM runner for the re-initiated role includes the previous output AND the rejection reason in its context:

```erlang
build_context_with_feedback(VentureId, Role, RejectionReason) ->
    PreviousOutput = get_previous_output(VentureId, Role),
    SystemPrompt = load_agent_role:load(Role),
    [
        #{role => system, content => SystemPrompt},
        #{role => assistant, content => PreviousOutput},
        #{role => user, content => iolist_to_binary([
            <<"Your previous output was reviewed and rejected. ">>,
            <<"Reason: ">>, RejectionReason, <<"\n\n">>,
            <<"Please revise your output addressing this feedback.">>
        ])}
    ].
```

This creates a refinement loop: generate, review, reject with feedback, regenerate, review again. Each cycle is recorded as events. You can see the progression — the first vision attempt, the rejection reason, the second attempt, the pass. The dossier tells the story of how the decision was made, including the false starts.

In practice, most gates pass on the first or second attempt. The visionary usually gets the vision right. The explorer might miss a bounded context, gets rejected, and finds it on the second pass. Rarely does a gate take more than three cycles. But when it does, every cycle is recorded, and the final output is demonstrably better than the first.

I've started thinking of the gate-and-reject cycle as a form of dialogue. The human can't write the vision themselves — that's why they're using the AI. But they can recognize a good one when they see it, and they can articulate what's wrong with a bad one. The gate gives them a vocabulary for that articulation. "Too broad." "Missing the real-time requirement." "Wrong emphasis." The AI takes that feedback and tries again. Usually, it gets there. The result is better than either the human or the AI would have produced alone. That's the pattern I keep seeing across thirty-five years of human-computer collaboration: the best results come not from full automation or full manual control, but from structured interaction between human judgment and machine capability.

---

## The Gate Inbox

Gates need a UI. Not a notification buried in a chat stream — a dedicated workspace where pending gates demand attention.

Martha's Gate Inbox shows all pending gates across all ventures:

```
┌─────────────────────────────────────────────────────────┐
│  Gate Inbox                                       3 pending │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ▼ Vision Gate — "E-Commerce Platform"                  │
│    Visionary output: 2,340 words                        │
│    Waiting since: 14 minutes ago                        │
│    ┌─────────────────────────────────────────┐          │
│    │ ## Product Vision                       │          │
│    │                                         │          │
│    │ An event-sourced e-commerce platform    │          │
│    │ focused on order fulfillment...         │          │
│    │                                         │          │
│    │ ### Core Goals                          │          │
│    │ 1. Sub-second order placement           │          │
│    │ 2. Real-time inventory tracking         │          │
│    │ ...                                     │          │
│    └─────────────────────────────────────────┘          │
│                                                         │
│    [  Pass  ]    [ Reject with feedback ]               │
│                                                         │
│  ► Boundary Gate — "Trading Platform"                   │
│    Explorer output: 4,120 words — waiting 2 hours       │
│                                                         │
│  ► Design Gate — "Chat Application"                     │
│    Stormer output: 6,890 words — waiting 1 day          │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

Each gate card is expandable. The full output is shown inline — no navigating to a separate page. The human reads the output, thinks about it, and either clicks Pass or clicks Reject and types a reason.

The UI is backed by the same event bridge described in Chapter 11. When a gate enters PENDING, an event fires, and the inbox updates in real time. When the human passes or rejects, a command is dispatched, and the inbox updates again. No polling. No refresh. Events drive everything.

There's a design philosophy embedded in the inbox: pending gates should feel slightly urgent. Not panic-inducing, but present. The "waiting since" timer is intentional. It's a gentle reminder that the pipeline is paused and a machine is waiting for you. Not to rush you — you should think carefully — but to make the pause visible. A gate that sits unreviewed for a day is a signal that either the human is overwhelmed or the pipeline is producing output nobody cares about. Both are worth knowing.

---

## The Audit Trail

Here's what the event stream looks like for a venture that went through two vision gate rejections before passing:

```
venture-abc123:
  [1] venture_initiated_v1         — 2026-03-12T09:00:00Z
  [2] visionary_initiated_v1       — 2026-03-12T09:00:01Z
  [3] visionary_completed_v1       — 2026-03-12T09:02:14Z (output: 2,340 words)
  [4] gate_rejected_v1             — 2026-03-12T09:15:00Z
        gate: vision_gate
        reason: "Too broad. Focus on order management, not the whole platform."
  [5] visionary_initiated_v1       — 2026-03-12T09:15:01Z (retry with feedback)
  [6] visionary_completed_v1       — 2026-03-12T09:17:22Z (output: 1,890 words)
  [7] gate_rejected_v1             — 2026-03-12T09:25:00Z
        gate: vision_gate
        reason: "Better, but missing the real-time inventory requirement."
  [8] visionary_initiated_v1       — 2026-03-12T09:25:01Z (retry with feedback)
  [9] visionary_completed_v1       — 2026-03-12T09:27:45Z (output: 2,100 words)
  [10] gate_passed_v1              — 2026-03-12T09:30:00Z
        gate: vision_gate
  [11] explorer_initiated_v1       — 2026-03-12T09:30:01Z
  ...
```

Ten events, and you can reconstruct the entire decision-making process. The initial vision was too broad. The human narrowed it. The second attempt missed a requirement. The human added it. The third attempt was right. The human approved. The explorer started.

Try getting that level of auditability from a chat log.

This audit trail is permanent. It's in the event store. It can be queried, projected, analyzed. You can build a dashboard showing average gate pass rates by role. You can track which roles need the most refinement. You can identify patterns — maybe the visionary consistently misses non-functional requirements, and the prompt needs updating.

The gate events aren't metadata about the pipeline. They ARE the pipeline. The system's history of decisions is its own documentation.

I've had conversations with users where they pulled up the event stream for a venture built six months ago and walked a new team member through every decision. "Here's why we chose these bounded contexts. See event 7? That's where we realized we needed to separate billing from ordering. And here — event 12 — that's where we caught the missing real-time constraint." The event stream is an institutional memory that doesn't fade, doesn't get misremembered, and doesn't require the original decision-makers to still be around to explain it. In thirty-five years of building software, I've never seen a better solution to the "why was it built this way?" problem.

---

## The Guided Conversation

Gates are binary — pass or reject. But the process of deciding is not binary. The human needs context. They need to understand what the agent produced, why it produced it, and what the implications are for downstream steps.

Martha frames each gate as a **guided conversation**:

1. **Frame the decision.** "The visionary has produced a product vision for your venture. This vision will determine what the explorer looks for and what the stormer designs. Review it carefully."

2. **Present the output.** The full agent output, formatted for readability. Not a summary — the actual text.

3. **Highlight key choices.** "The vision identifies three core goals. The explorer will use these to identify bounded contexts. Are these the right goals?"

4. **Accept the decision.** Pass or reject, with a reason if rejecting.

5. **Record and proceed.** The decision becomes an event. The pipeline moves forward (or loops back for refinement).

This is fundamentally different from "click approve to continue." The human isn't rubber-stamping. They're making an informed decision based on presented evidence, with full understanding of the consequences. The gate framework ensures they have the context to decide well.

We learned this the hard way. Our first gate UI was literally a "Pass / Reject" button pair with the raw output above it. Users clicked Pass without reading. When we added the framing — "this decision will affect X, Y, and Z downstream" — the reject rate went up, the final output quality went up, and users reported feeling more confident about the results. They weren't approving more carefully because we nagged them. They were approving more carefully because we gave them the context to care.

---

## Why Gates Make the System Trustworthy

Without gates, an LLM pipeline is a black box that takes a product description and produces code. It's the AI equivalent of "I woke up and this tattoo was here." Even if the code works, you don't know why it works. You don't know what assumptions were made. You don't know what alternatives were considered and rejected. You can't explain the architecture to a new team member because you didn't make the architectural decisions — the machine did, opaquely, in a chain of API calls you can't reconstruct.

With gates, the pipeline is transparent. You made the decisions. The machine did the work, but at every critical juncture, a human evaluated the output and said "yes, this is right" or "no, fix this." The resulting system is explainable because the decision trail is recorded. The architecture choices are defensible because a human reviewed and approved them.

This matters more than most people think. I've been in meetings where someone asked "why is the system designed this way?" and the answer was "because the AI generated it." That's not an answer. It's an abdication. With gates, the answer is: "Because the visionary proposed this vision, we reviewed it and narrowed the scope (see gate event 4), the explorer identified these contexts, we validated them (see gate event 10), and the stormer designed these events, which we approved after adding the missing real-time constraint (see gate event 15)." That's an answer you can defend. That's an answer you can learn from. That's an answer that gives the next person enough context to decide whether to change it.

This is what "autonomous" actually means in practice. Not unsupervised. Not unaccountable. Autonomous like a skilled professional who does excellent work and checks in with stakeholders at key milestones. The professional doesn't ask permission for every line of code. But they do present the architecture for review before building on it. They do confirm the product vision before designing for it.

Gates encode this workflow into the system's architecture. They're not a safety net bolted on after the fact. They're a first-class concept in the aggregate's state machine, with their own events, their own commands, their own process managers. They're as fundamental to the system as the LLM calls themselves.

---

## The Philosophical Argument

There's a deeper principle at work, and I want to take a moment to articulate it because I think it matters beyond software.

In any system that makes consequential decisions, there's a spectrum of trust:

```
Full manual control ←────────────────────→ Full autonomy
   (human does everything)          (machine does everything)
```

Neither extreme is right. Full manual control doesn't scale. Full autonomy isn't trustworthy. The interesting design space is in between: **bounded autonomy** with human checkpoints at high-leverage decision points.

The key insight is that not all decisions have equal consequences. Choosing a variable name is low-consequence — let the machine decide. Choosing the bounded context boundaries for a distributed system is high-consequence — a human should review. The gate pattern formalizes this distinction. It asks: where in this pipeline does being wrong cost the most? Put a gate there.

This isn't a temporary measure. It's not "we'll remove the gates when the AI gets good enough." I've heard "we'll remove the human from the loop when the technology matures" in every decade of my career. The expert systems people said it in the eighties. The CASE tools people said it in the nineties. The model-driven people said it in the 2000s. At this point, "remove the human from the loop" is the "this year is the year of Linux on the desktop" of AI. The gates are permanent because the value of human judgment at critical decision points is permanent. Even if an LLM produces perfect bounded context boundaries 99% of the time, the cost of the 1% failure is so high that a human review is worth it. The gate takes 30 seconds to pass. The wrong boundary takes months to untangle.

After thirty-five years, I've learned that the question isn't whether to trust the machine. It's which decisions need human judgment and which ones don't. Every technology generation promises to move that line further toward full autonomy. And every generation does move it — a little. CASE tools automated boilerplate code. Model-driven development automated schema generation. Low-code platforms automated CRUD interfaces. LLMs automate design exploration and code generation. Each wave automated something real. None of them eliminated the need for human judgment at the critical junctures. The line moves, but it never reaches the end.

The gate pattern is our answer to that permanent reality. Not "how do we make AI fully autonomous?" but "how do we make human judgment at critical decision points as informed and efficient as possible?" While the industry chased full autonomy, we chased trustworthy collaboration. That's the question that has a good answer. The first question, I suspect, never will.

Autonomy isn't the absence of oversight. It's the presence of trust — and trust is built by showing your work, accepting feedback, and recording every decision for posterity.

The dossier accumulates its slips. The gate adds one more. Pass the dossier. Move on.
