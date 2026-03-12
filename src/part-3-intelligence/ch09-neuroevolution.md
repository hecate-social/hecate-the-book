# Chapter 9: Neuroevolution

*Why topology matters more than weights*

---

I need to tell you about the moment I realized the entire deep learning industry was asking the wrong question. But to explain why it hit so hard, I need to give you some context about what came before.

I started in IT in 1990. That means I was there for the second AI winter — the long, cold years when neural networks were considered a dead end. I watched the field go from breathless optimism about perceptrons in the textbooks I was studying, to a kind of institutional embarrassment. By the mid-nineties, if you mentioned neural networks in a serious computing conversation, people looked at you the way they'd look at someone who still believed in cold fusion. SVMs were the respectable choice. Decision trees were practical. Neural networks were for dreamers who hadn't gotten the memo.

Then deep learning came roaring back in the 2010s, and suddenly everyone was a believer again. I'd watched the industry declare neural networks dead twice by that point — once after Minsky's perceptron critique rippled through the field, and again after the backprop revival of the eighties fizzled into the winter I'd lived through. So when the ResNet papers started making waves and GPUs made deep networks tractable, I was interested but cautious. I'd seen this movie before.

What I hadn't expected was that even the renaissance would carry a blind spot. By 2019, I was doing what everyone was doing: picking a number of layers, picking a width, connecting everything to everything, and then throwing GPU hours at gradient descent until the loss went down. The architecture was a ResNet variant — because of course it was, everyone was using ResNets. When performance stalled, I did what everyone does: fiddle with hyperparameters, add dropout, try a different optimizer, pray. When it still stalled, I did what everyone does next: redesign the architecture by hand, based on intuition and whatever paper was trending on arXiv that week.

Now, I'd been tracking Kenneth Stanley's work for years. When NEAT appeared in 2002, I was deep in the post-winter skepticism — anything that smelled like "neural networks will save us" got an automatic raised eyebrow from me. But Stanley's approach was different. He wasn't promising magic. He was asking a structural question that nobody else seemed to be asking. I filed it away, kept watching, and when I finally circled back to it seriously in 2019, I remember thinking: *wait, we've been hand-designing the one thing that determines what the network can learn, and then hoping gradient descent fills in the details?*

That's the lie of omission at the heart of deep learning. Not a malicious lie — more of a collective blind spot. We assume the architecture is given, and training is the hard part. Nobody asks the obvious question: **what if the architecture itself could evolve?**

That question is the foundation of neuroevolution. And it changes everything about how you think about neural networks.

---

![TWEANN Architecture](assets/tweann-architecture.svg)

## The Fixed Topology Trap

Traditional machine learning works like this: a human decides the network topology (how many layers, how many neurons, how they connect), then an algorithm trains the weights (the strengths of the connections). The topology is a design decision. The weights are learned.

This separation is so deeply embedded in ML practice that most practitioners don't even see it as a choice. Of course you design the architecture. That's your job. The network learns the rest. It's the neural network equivalent of "here's a violin, now play Paganini" — except you also decided how many strings the violin has, how long the bow is, and whether it's actually a tuba.

But think about what this means. You're constraining the space of possible solutions to architectures a human can imagine. You're betting that your intuition about the problem maps to the right computational structure. You're hand-designing the thing that determines what the network CAN learn — and then hoping gradient descent fills in the details.

Sometimes this works brilliantly. CNNs for images. Transformers for sequences. These were inspired insights that unlocked entire fields.

But most problems aren't images or text. Most problems don't have a known-good architecture waiting to be discovered by a brilliant researcher. Most problems are messy, domain-specific, weird. And for those problems, fixing the topology is fixing the answer before you've asked the question.

I've watched this pattern repeat across three decades of ML trends. The field fixates on one architecture — MLPs, then CNNs, then LSTMs, then Transformers — and treats it as the answer to everything until the next breakthrough comes along. Each time, the fixation produces tremendous results on the problems the architecture was designed for, and mediocre results on everything else. And each time, the practitioners who spent years tuning architectures by hand were convinced they were doing "science" when they were really doing trial-and-error with extra steps. Deep learning, as practiced by most of us, was "throw data at matrices until they confess." We called it "empirical research." We wrote papers about it. We got citations. I was one of them. The breakthrough wasn't a better optimizer or a clever regularization trick. It was realizing the architecture itself should be a variable, not a constant.

Neuroevolution takes a different approach: **evolve both the topology AND the weights.** Let the structure of the network emerge from evolutionary pressure, the same way biological neural architectures emerged over millions of years. Don't tell the network what shape to be. Let it figure that out.

---

## NEAT: Starting Small, Growing Smart

The breakthrough algorithm in neuroevolution is NEAT — NeuroEvolution of Augmenting Topologies, developed by Kenneth Stanley in 2002. I remember reading the original paper the year it came out and having one of those rare moments of recognition — like when I first encountered Erlang's "let it crash" philosophy, or the first time event sourcing clicked. The core idea is almost embarrassingly elegant: start with the simplest possible network and incrementally add complexity through mutation.

A NEAT network begins life as a direct connection from every input to every output. No hidden layers. No hidden neurons. Just wires from sensors to actuators, each with a weight. This is the simplest network that could possibly work.

Then evolution happens.

**Topological mutations** change the structure:

- **add_neuron**: Pick an existing connection. Disable it. Insert a new neuron in the middle. Create two new connections — one from the original source to the new neuron (weight 1.0), one from the new neuron to the original target (original weight). The network's behavior is preserved while new computational capacity is added.
- **add_outlink**: Pick a neuron. Connect it to a neuron in a later layer that it isn't already connected to.
- **add_inlink**: Pick a neuron. Connect it to a neuron in an earlier layer.
- **outsplice**: Like add_neuron, but specifically splits an output connection.
- **add_sensor**: Attach a new input to the network.
- **add_actuator**: Attach a new output.
- **add_bias**: Give a neuron a bias connection.

**Parametric mutations** adjust the parameters:

- **mutate_weights**: Perturb connection weights. Uses simulated annealing — large changes early, small refinements later.
- **mutate_af**: Change a neuron's activation function. The network might discover that a ReLU works better than a tanh in a particular position.
- **mutate_aggr_f**: Change how a neuron aggregates its inputs (sum, product, max).

The genius of NEAT is the starting point. By beginning minimal and complexifying, every network structure that appears during evolution is the simplest structure that earned its complexity. Every hidden neuron exists because evolution tried adding it and the resulting network performed better. There's no bloat. No vestigial layers. No neurons doing nothing.

(Well, almost no neurons doing nothing. If you've never watched a neural network evolve to game a fitness function in ways you didn't anticipate, you haven't lived. I once had a population that discovered it could maximize its fitness score by evolving a single neuron that always output zero. Technically correct. Completely useless. Thirty-five years in this industry and the machines still find new ways to remind me that I'm not as clever as I think I am. That's when I learned that designing fitness functions is an art form.)

---

## Innovation Numbers: The Alignment Problem

Crossover — combining two parent networks to produce offspring — is trivial when both parents have the same topology. Just pick each weight from one parent or the other.

But in neuroevolution, parents have different topologies. Parent A might have 7 neurons and 12 connections. Parent B might have 5 neurons and 9 connections. How do you align them? How do you know that connection #3 in Parent A corresponds to connection #5 in Parent B?

NEAT solves this with **innovation numbers**. Every time a new structural mutation occurs — a new connection, a new neuron — it gets a globally unique innovation number. If two separate lineages independently evolve a connection between the same two neurons, they get the same innovation number (checked against a global registry). If they evolve different connections, they get different numbers.

During crossover, you align the parent genomes by innovation number:

```
Parent A:  [1, 2, 3, -, 5, 6, -, 8]
Parent B:  [1, 2, -, 4, 5, -, 7, 8]
                      ↑           ↑
                  disjoint     matching
```

Matching genes (same innovation number) are inherited from one parent or the other randomly. Disjoint and excess genes (present in one parent but not the other) are inherited from the more fit parent. This preserves innovations from both lineages while maintaining structural coherence.

Without innovation numbers, crossover in variable-topology networks is a disaster. You'd be splicing random connections together and hoping the result works. Innovation numbers make it principled. It's one of those ideas where once you see it, you can't imagine the alternative — but somebody had to invent it.

---

## Speciation: Protecting the Weird Ones

Here's a problem with evolving topology that cost me about a month of wasted experiments before I understood it: a new structural mutation almost always makes the network worse, at least initially. Adding a neuron disrupts the existing computation. The new neuron needs time — generations of weight optimization — before it starts contributing. But in a flat evolutionary population, it'll be outcompeted by simpler, already-optimized networks before it gets the chance.

I watched this happen over and over. The population would converge to some mediocre but stable topology and stay there forever. Every interesting mutation would get crushed by the incumbent. It was like watching a company kill every innovative project because the quarterly numbers looked bad. I'd seen that pattern in corporate IT for decades — the promising new technology that never gets past the pilot because the existing system is "good enough." Same dynamic, different domain.

NEAT solves this with **speciation**. Similar networks are grouped into species. Competition happens primarily within species, not across them. A novel topology competes against other novel topologies, not against established architectures that have had hundreds of generations to optimize.

The compatibility between two networks is measured as a function of their structural difference (disjoint and excess genes) and their weight differences on matching genes. Networks within a compatibility threshold are in the same species.

This means evolution explores multiple architectural niches simultaneously. One species might be evolving deep narrow networks. Another might be evolving wide shallow ones. A third might be experimenting with recurrent connections. Each niche gets protected exploration time. If a niche proves valuable, it grows. If it doesn't, it shrinks. But it doesn't get killed on day one by an incumbent.

Speciation is one of those ideas that seems obvious in hindsight but is crucial in practice. Without it, neuroevolution converges prematurely to whatever simple architecture happens to do okay on the current problem. With it, the population maintains genuine diversity, and radical innovations have room to breathe. It's the difference between a monoculture and an ecosystem.

---

## Beyond Static: Liquid Neurons

Standard artificial neurons are stateless. They receive inputs, apply weights, run an activation function, and produce an output. Between evaluations, they remember nothing. Every forward pass starts from scratch.

Biological neurons are nothing like this. Real neurons have temporal dynamics. They integrate inputs over time. Their responses depend on their recent history. They have time constants that determine how quickly they respond to changes.

This has bugged me since the early nineties, when I first read about recurrent networks and immediately thought: this is still a crude approximation of what biological neurons actually do. We were trying to build systems that could react to temporal patterns — time-series data, sequential decisions — and our computational elements had the memory of a goldfish. (No offense to goldfish. Recent research suggests they actually have decent memories. Our neurons didn't.)

**Liquid Time-Constant (LTC) neurons** bring this temporal awareness to artificial networks. An LTC neuron maintains internal state `x(t)` that evolves according to a differential equation:

```
dx/dt = -(1/tau) * (x - target)
```

where `tau` is the time constant (how quickly the neuron responds) and `target` is determined by the current inputs. A large tau means the neuron changes slowly — it acts as a memory, smoothing over rapid input fluctuations. A small tau means it tracks inputs closely, responding to every change.

The time constant itself is evolvable. Evolution can decide that a particular neuron should be fast-responding (small tau, reactive) or slow-integrating (large tau, memory). Different neurons in the same network can have different temporal scales, creating a rich hierarchy of temporal processing.

**Closed-form Continuous-time (CfC)** neurons take this further by solving the ODE analytically:

```
x(t+dt) = sigma(-f) * x(t) + (1 - sigma(-f)) * h
```

where `sigma` is the sigmoid function, `f` controls the interpolation, and `h` is determined by the current inputs. This is 100x faster than numerical ODE integration because there's no Euler step, no Runge-Kutta — just a direct computation of the next state. The network gets temporal dynamics without the computational cost.

Our implementation supports three neuron types — `standard`, `ltc`, and `cfc` — and evolution can mutate between them via `mutate_neuron_type`. A network might discover that its input-processing neurons work best as standard (fast, stateless), while its decision-making neurons need to be CfC (temporal memory, state persistence). The architecture evolves not just its topology but the nature of its computational elements.

I'll be honest — when I first read about LTC neurons, my AI winter instincts kicked in. "Another clever idea that won't survive contact with real problems," I thought. I'd been burned too many times by elegant theories that fell apart in practice. Then I ran the same temporal pattern recognition task with and without them. The standard-neuron network plateaued at 72% accuracy. The network with evolved LTC neurons hit 94%. After thirty-five years, I've learned to let the numbers overrule my skepticism. That's when I stopped doubting.

---

## Process-Per-Neuron: Where BEAM Changes Everything

Here's where neuroevolution meets the BEAM virtual machine, and something remarkable happens.

In a traditional neural network framework (PyTorch, TensorFlow), neurons are matrix elements. The entire network is a sequence of matrix multiplications. This is great for GPU acceleration but terrible for variable topology: every structural change means reallocating matrices, reshaping tensors, rebuilding the computational graph.

Everyone told us to use Python. "Real ML happens in Python," they said. "You're going to rewrite PyTorch in Erlang?" they said. I've been told to use the fashionable language many times over thirty-five years. Use C++, they said in the nineties. Use Java, they said in 2000. Use Ruby, they said in 2008. Use Go, use Rust, use Python. Each time, the advice was well-intentioned. Each time, the question wasn't "which language is popular?" but "which platform's fundamental model matches the problem?" For neuroevolution — where every neuron is an independent computational entity with its own state and lifecycle — the answer has been obvious since I first understood the BEAM's process model.

On the BEAM, each neuron is an Erlang process. Not a metaphorical process — an actual lightweight process with its own mailbox, its own state, its own lifecycle. A network with 50 neurons is 50 processes, communicating via message passing.

```erlang
%% A neuron process receives inputs, aggregates, activates, and forwards
neuron_loop(State) ->
    receive
        {forward, FromPid, Value} ->
            NewState = accumulate_input(State, FromPid, Value),
            case all_inputs_received(NewState) of
                true ->
                    Output = activate(NewState),
                    [Pid ! {forward, self(), Output * W}
                     || {Pid, W} <- NewState#neuron.output_links],
                    neuron_loop(reset_inputs(NewState));
                false ->
                    neuron_loop(NewState)
            end
    end.
```

This matters for neuroevolution in ways that aren't immediately obvious:

**Adding a neuron is spawning a process.** No matrix reallocation. No computational graph rebuild. Just `spawn_link` a new process and update the connection topology. Adding connections is sending a message to the new neuron with its updated link list.

**Fault isolation is free.** If a neuron's activation function produces a NaN (it happens during evolution when weights go extreme), that process crashes. Its supervisor restarts it. The rest of the network keeps running. In a matrix-based framework, one NaN poisons the entire computation. If a neuron in PyTorch crashes, you restart your entire training run, check your CUDA drivers, sacrifice a small animal to the GPU gods, and rethink your career choices. I once lost an entire sixteen-hour training run to a single divergent weight. On the BEAM, that neuron would have crashed, restarted, and life would have gone on. Erlang was built for telephone switches that handled millions of concurrent calls and couldn't afford to let one bad call take down the exchange. Turns out that's not so different from a neural network where one bad neuron shouldn't take down the population.

**True parallelism is natural.** Neurons in the same layer can execute simultaneously on different CPU cores. The BEAM scheduler handles this automatically. No explicit parallelism primitives needed. A network naturally uses as many cores as it has independent neurons.

**Hot code loading works.** You can update a neuron's activation function in a running network without stopping the evaluation. This enables on-the-fly mutation during training, not just between generations.

The weight format reflects this process-oriented design:

```erlang
%% {Weight, DeltaWeight, LearningRate, ParameterList}
{0.3421, 0.0, 0.1, []}
```

Each weight carries its own learning rate and parameter history, enabling per-connection learning dynamics. This is trivial when weights are local state in a process. It would be an engineering nightmare in a flat weight matrix.

So were the Python people wrong? Mostly yes. They were almost right three times, though: when we needed GPU-accelerated matrix ops (we wrote Rust NIFs), when we needed a pre-trained language model (we use APIs for that now), and when we needed the ecosystem of pre-built datasets and benchmarks (we wrote adapters). But for neuroevolution specifically — where the topology changes constantly and fault tolerance isn't optional — the BEAM is not just viable, it's the natural choice. I've been in this industry long enough to know that "everyone uses X" is never a technical argument. It's a social one. And social arguments don't survive contact with the wrong abstraction at two in the morning.

---

## Lamarckian vs. Darwinian Evolution

Classical Darwinian evolution is blind to what an individual learns during its lifetime. A cheetah that learns to hunt more efficiently doesn't pass that learned skill to its offspring through genetics. The offspring inherits the cheetah's DNA — its innate capabilities — not its acquired skills.

Lamarckian evolution allows acquired traits to be inherited. If a network optimizes its weights during evaluation (lifetime learning), those optimized weights are written back into the genotype and inherited by offspring.

In neuroevolution, this choice is practical, not philosophical:

**Darwinian mode**: The network's weights after evaluation are discarded. Only the original genotype weights (plus structural mutations) pass to the next generation. Lifetime learning helps the individual but doesn't contribute to the gene pool.

**Lamarckian mode**: The network's optimized weights replace the genotype weights. Offspring start with the parent's learned weights. Evolution doesn't just find good topologies — it accumulates weight knowledge across generations.

Lamarckian evolution converges faster but risks getting trapped in local optima (the population becomes too similar). Darwinian evolution maintains diversity but converges slowly. The choice depends on the problem, and in our system, it's a configuration option — not a religious commitment.

We flipped between the two constantly during development. Lamarckian for problems where we needed fast convergence and could tolerate less diversity. Darwinian when we kept getting stuck in local minima. Eventually we settled on a hybrid: Lamarckian within species, with periodic Darwinian resets when diversity drops below a threshold. It's not elegant, but it works. Sometimes engineering is about finding the pragmatic compromise between two beautiful theories. It's the computational equivalent of "diet on weekdays, pizza on weekends." Biologists would be appalled. The fitness scores don't care. After thirty-five years, I've made my peace with that.

---

## Why Topology Matters More Than Weights

Back to the title of this chapter. Here's the argument in its starkest form:

**The topology of a network determines what it CAN learn. The weights determine how well it learns it.** A network without recurrent connections cannot learn temporal patterns, no matter how good its weights are. A network without enough hidden neurons cannot represent complex decision boundaries. A network with the wrong activation functions will plateau at mediocre performance.

Getting the weights right on the wrong architecture produces a mediocre solution, optimally. Getting the architecture right with random weights produces a terrible solution, temporarily — but one that can be trained to excellence.

Traditional ML gets the architecture right through human expertise. This works when humans have good intuitions about the problem space. Neuroevolution gets the architecture right through evolution. This works when humans don't — which, for most real-world problems, is most of the time.

The BEAM makes neuroevolution practical in ways that matrix-based frameworks cannot. The process model maps naturally to variable-topology networks. The fault tolerance survives the chaos of evolutionary mutation. The concurrency exploits the inherent parallelism of neural computation.

In the next chapter, we'll see exactly how this plays out — how an Erlang/OTP system evolves neural architectures from scratch, using records for genotypes, processes for phenotypes, and populations of agents competing and reproducing across generations.

Every generation of AI promises to replace programmers. So far, programmers have survived expert systems, CASE tools, UML code generation, model-driven development, low-code platforms, and blockchain smart contracts. We're like cockroaches, but with worse posture. Neuroevolution won't replace us either. But it will change what "designing" means — from drawing the blueprint to setting the constraints and letting evolution do what evolution has always done, given enough time and enough pressure: surprise you.

The architecture of intelligence isn't designed. It's evolved.
