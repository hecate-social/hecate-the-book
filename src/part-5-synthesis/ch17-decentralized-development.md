# Chapter 17: Decentralized Development

*When your build system has no master*

---

I started my career on centralized systems. Not by choice -- by necessity. In 1990, the mainframe in the machine room cost more than the building it sat in, and every terminal in the office was a dumb pipe to that single point of truth. You logged in, you did your work, you logged out. The mainframe was God and the sysadmin was the priesthood.

Then PCs happened, and suddenly compute was everywhere. Desktops ran their own software. Local drives held local data. We decentralized -- not because of some grand vision, but because PCs were cheap and mainframe time wasn't. It felt like freedom.

Then client-server pulled it back. Then the web centralized it into data centers. Then cloud concentrated it further -- millions of developers worldwide, dependent on a handful of regions operated by three companies. Pull one plug in `us-east-1` and a thousand teams stop shipping. I've lived through that outage day more than once. The first time, in the mid-2010s, it was a surprise. By the third time, it was predictable. We'd rebuilt the mainframe. We just called it AWS. We added a load balancer and called it innovation.

When we started building Hecate, we thought we were building a deployment tool. Something to automate the tedious parts of shipping software. CI/CD with better ergonomics, maybe some AI sprinkled on top. We were spectacularly wrong.

What we actually built was a development environment with no center. And we didn't plan it that way -- it emerged, inevitably, from the decisions we'd been making for sixteen chapters. If your communication is peer-to-peer, and your storage is event-sourced, and your intelligence is distributed across nodes... why would your development process have a central server?

Every software team today has one. GitHub holds the code. Jenkins runs the builds. Jira tracks the work. Slack carries the conversation. The developers are distributed, but the infrastructure is centralized to an almost comical degree. We've centralized again, and this time not because we can't afford the alternative -- compute is practically free now, four mini-PCs cost less than a month of cloud bill -- but out of habit. Out of inertia. Because that's how the industry learned to do it in the 2010s, and nobody has seriously questioned it since.

We've spent the last sixteen chapters building something different. A masterless mesh for communication. An event-sourced store for truth. A CQRS framework for process. Neural networks that evolve their own topology. LLM agents that generate code through gated pipelines. Now it's time to put them together and ask the question this book has been building toward:

**What happens when the development process itself runs on the autonomous stack?**

---

## The Developer Node

Every participant in a Hecate development environment runs a daemon. Not connects to a server -- *runs a daemon.* This distinction matters more than it might seem. The `hecate-daemon` is an Erlang/OTP application packaged as an OCI container, managed by systemd, deployed via podman. It contains everything: a ReckonDB event store, the evoq CQRS framework, a cowboy HTTP API, and a macula mesh peer.

```
Developer Laptop                    Beam Cluster Node
┌──────────────────────┐           ┌──────────────────────┐
│  hecate-daemon       │           │  hecate-daemon       │
│  ├── ReckonDB        │◄─mesh──►  │  ├── ReckonDB        │
│  ├── Evoq            │           │  ├── Evoq            │
│  ├── Macula Peer     │           │  ├── Macula Peer     │
│  ├── Cowboy API      │           │  ├── Cowboy API      │
│  └── Plugins         │           │  └── Plugins         │
└──────────────────────┘           └──────────────────────┘
```

The laptop and the cluster node are peers. Neither is the server. Neither is the client. They discover each other via mDNS on the local network or through DHT bootstrap nodes on the internet. They exchange integration facts over the mesh. They each maintain their own event streams. When one goes offline, the other continues working.

I remember the first time this actually worked -- two machines finding each other, exchanging events, neither one in charge. After thirty-five years of building systems where something is always the server, it felt wrong at first, the way the metric system feels wrong to an American. Where's the authority? Who's the source of truth? The answer, once you internalize it, is both liberating and slightly unnerving: everyone is. The project state isn't in a central repository. The project state is the event stream -- and event streams exist on every participating node.

I've seen this pattern before, in a cruder form. In the early 90s, I worked on a system where each branch office had its own database and they synced overnight via modem. It was a nightmare -- conflicts, lost data, fingers pointed at the phone company. What's different now isn't the idea of distributed state. What's different is that we have the primitives to do it right: content-addressed data, CRDTs, immutable event streams. The idea is thirty years old. The tools finally caught up.

---

## Venture State Is the Event Stream

In Chapter 1, we established the dossier principle: every process is a folder of event slips, not a mutable record. In Chapter 13, we applied this to software development itself -- a venture passes through discovery, planning, design, generation, testing, and deployment. Each phase is a dossier. Each dossier accumulates events.

Now extend this to multiple nodes. When a developer on their laptop initiates a venture, the daemon creates a local event stream:

```
venture-7f3a9b2e
  [slip] venture_initiated_v1    — name, description, owner
  [slip] vision_submitted_v1     — the architectural vision
  [slip] discovery_opened_v1     — begin finding bounded contexts
```

These are domain events -- internal to the bounded context. But the venture lifecycle also publishes integration facts to the mesh. A process manager watches for significant events and translates them into public contracts:

```
Domain Event (local ReckonDB)     →  Integration Fact (macula mesh)
──────────────────────────────       ──────────────────────────────
venture_initiated_v1              →  venture.announced
vision_submitted_v1               →  venture.vision_available
division_identified_v1            →  venture.division_discovered
```

Other nodes on the mesh receive these facts. They don't get the raw domain events -- they get curated, stable integration contracts. A developer on a different machine sees that a new venture exists, what its vision is, and which divisions have been identified. They can choose to participate.

The critical insight: **there is no "venture database" to query.** The venture's state is the sum of its events. Any node that has subscribed to the relevant mesh topics has a local projection of the venture's current status. Delete the projection, replay the facts, get the same result.

This is the part that trips up people coming from conventional architectures. "But where's the database?" they ask. Everywhere and nowhere. Your machine has a projection. My machine has a projection. They agree because they're derived from the same facts. There's nothing to sync because there's no single source to sync against.

I spent the better part of the 90s and 2000s wrestling with database replication -- master-slave, multi-master, conflict resolution strategies that filled whiteboards and produced ulcers. The solution was always "pick a source of truth and replicate from it." The insight that took me decades to internalize: if your source of truth is an immutable append-only log, the replication problem largely dissolves. You don't need conflict resolution when operations can't conflict.

---

## Parallel Agents on Parallel Nodes

In a conventional setup, CI/CD is a pipeline. One agent runs. It finishes. The next agent runs. If you want parallelism, you add more workers -- but they're all connected to a central orchestrator that assigns work. Somebody, somewhere, is maintaining a queue.

In the Hecate model, multiple agents on different physical nodes can work on the same venture simultaneously, without a central orchestrator. Here's how:

Each division within a venture is independent. Division A (the user authentication context) and Division B (the payment context) have separate event streams. An agent on beam01 can generate code for Division A while an agent on beam02 generates code for Division B. They don't interfere because they're operating on different dossiers.

Coordination happens through events, not locks. When the agent on beam01 finishes generating Division A, it emits `division_generated_v1` into its local event store. The process manager translates this into a mesh fact. The agent on beam02 receives it. If Division B depends on types from Division A, the generated artifacts are available via content-addressed transfer.

```
beam01 (Division A)                    beam02 (Division B)
────────────────────                   ────────────────────
crafting_opened_v1                     crafting_opened_v1
module_generated_v1 (user.erl)         module_generated_v1 (payment.erl)
module_generated_v1 (auth.erl)         ... waiting for Division A types ...
test_generated_v1
test_result_recorded_v1 (pass)
division_generated_v1  ──mesh──►       ... receives Division A artifacts
                                       module_generated_v1 (payment_auth.erl)
                                       test_generated_v1
                                       test_result_recorded_v1 (pass)
                                       division_generated_v1
```

No central build server decided this scheduling. No orchestrator assigned divisions to nodes. Each node advertised its capabilities (LLM models available, CPU capacity, storage), and the venture lifecycle distributed work based on those advertisements. The "market model" -- nodes offer what they have, nodes consume what they need.

We stumbled onto this pattern almost by accident. We had two beam nodes sitting idle while a third was grinding through code generation, and we thought: why can't they help? The answer was that they could -- the architecture already supported it. We just hadn't thought to try, because years of working with centralized CI had trained us to think in terms of queues and workers, not markets and peers. Old habits from old architectures. I've been unlearning them for thirty-five years, and they still surprise me.

---

## The Infrastructure Layer

Let's talk about what actually runs where -- because I think this is the part that makes the whole thing feel real instead of theoretical.

The beam cluster is four Intel Celeron J4105 mini PCs sitting on a shelf in a home lab. beam00 has 16GB of RAM; beam01 through beam03 have 32GB each. Each has NVMe storage mounted at `/fast` and one or two HDDs mounted at `/bulk0` and `/bulk1`. They run Ubuntu Server 20.04 with podman 3.x, managed by systemd user units.

There is no Kubernetes. There is no Docker Swarm. There is no cloud provider.

I can hear the skepticism. "You're running a distributed development platform on mini PCs?" Yes. And it works. Four mini-PCs on a shelf, drawing less power than the mainframe's cooling system drew in 1992. More compute power than the mainframe I started on in 1990 -- more than the entire data center I worked in through most of the 90s, if I'm honest. The total cost was less than three months of a modest AWS bill, and they don't send me an invoice when I breathe wrong. Running a mesh network that would have been a research project when I was debugging COBOL batch jobs. The architecture doesn't require impressive hardware. Each node is self-sufficient. It doesn't need low-latency connections to a central database. It doesn't need shared storage. It just needs to run the daemon and reach the mesh.

Deployment is almost absurdly simple: CI/CD in GitHub Actions builds an OCI image, pushes it to ghcr.io with both a semver tag and `:latest`. Each beam node runs podman with `AutoUpdate=registry`, which periodically checks for new `:latest` images and restarts the container if one is found. Zero-touch deploys.

```
Developer pushes to main
  → GitHub Actions builds OCI image
    → pushes ghcr.io/hecate-social/hecate-daemon:latest
      → beam00-03 each run podman auto-update
        → new image detected, container restarts
          → daemon reconnects to mesh
            → resumes event subscriptions
              → continues where it left off
```

Per-node configuration lives in `~/.hecate/gitops/`, a local directory that serves as the node's source of truth. A reconciler watches this directory and symlinks Quadlet `.container` files into systemd's unit path. Add a file, the service starts. Remove it, the service stops. The filesystem IS the desired state.

Rollback is equally simple: pin the `.container` file to a specific semver tag instead of `:latest`. The next auto-update cycle pulls the pinned version. Fix the bug, push a new `:latest`, revert the pin.

I've watched deployment go from "copy the binary and restart the service" (90s) to "write a 500-line XML deployment descriptor" (early 2000s, J2EE era) to "learn an entire container orchestration platform" (2010s, Kubernetes) and back to something that feels a lot like "copy the binary and restart the service" -- except the binary is an OCI image and the restart is automatic. The industry has a gift for overcomplicating things and then rediscovering simplicity two decades later. We just need the intermediate step of making it someone's full-time job first, so that we can later automate them out of it and call it DevOps.

This infrastructure model extends beyond the beam cluster. A developer laptop runs the same daemon, the same container, the same mesh peer. An edge device -- a laptop running MaculaOS -- is another node. They're all equal participants. The only difference is hardware resources, which the mesh advertises honestly.

---

## Content-Addressed Distribution

When an agent generates a module, that module needs to be available to other nodes. In a centralized system, you'd push to a package registry. In a decentralized system, you use content-addressed storage.

Every artifact in the mesh has an MCID -- a Macula Content Identifier. It's the hash of the content. If two nodes generate the same file, they produce the same MCID. Content is immutable by definition: if the content changes, the MCID changes.

The transfer protocol is Want/Have/Block:

```
Node A: "I have MCID abc123 (user_auth.beam)"
  → publishes to mesh topic: content.available

Node B: "I want MCID abc123"
  → sends WANT message to Node A

Node A: "Here's block 1 of 3, block 2 of 3, block 3 of 3"
  → streams BLOCK messages

Node B: verifies hash, stores locally
  → now also advertises: "I have MCID abc123"
```

This is BitTorrent for code artifacts. The more nodes that have a file, the more sources are available for download. Popular artifacts distribute themselves. Test results, generated modules, compiled releases -- they all flow through the same mechanism.

No central package registry. No single point of failure for artifact distribution. A node goes offline and its artifacts are still available from any other node that fetched them. If you've ever waited for a corporate Artifactory instance to come back online while your CI pipeline is burning money -- or, in my case, waited for the FTP server to come back up in 1997 while a production deploy sat half-finished -- you understand why this matters. The specific technology changes. The pain of centralized artifact distribution is eternal.

---

## Trust Through History

In a centralized system, trust is administrative. You're in the GitHub organization. You have write access. Your role says you can approve PRs. Trust is a flag in a database, granted by an administrator.

In a decentralized system, trust is historical. Every decision is an event. Every event is in a stream. Every stream is an immutable audit trail.

When Agent X on beam02 generates a module that fails three out of five tests, that fact is recorded:

```
agent-session-x-4f2a
  [slip] crafting_opened_v1
  [slip] module_generated_v1
  [slip] test_result_recorded_v1  — 3 of 5 failed
  [slip] module_regenerated_v1    — second attempt
  [slip] test_result_recorded_v1  — 5 of 5 passed
  [slip] gate_review_passed_v1   — human approved
```

The complete history of Agent X's work is right there. Its success rate, its failure patterns, its typical number of regeneration cycles -- all derivable from the event stream. Trust isn't a flag; it's a projection built from observed behavior.

This is how trust actually works between humans, too. You don't trust a colleague because their manager said they're competent. You trust them because you've watched them work, seen them handle failures, and observed their judgment over time. I've managed enough teams over three decades to know: the org chart says who has authority, but the team knows who has credibility. They're often different people. We just applied the same principle to machines and made it auditable.

This extends to the human gate. Chapter 12 introduced the concept of gates -- checkpoints where machines must stop and ask for human judgment. In a decentralized system, gate decisions are events too. `gate_review_passed_v1` carries the reviewer's identity, the timestamp, and (optionally) their rationale. The audit trail for "who approved this code for production" is a first-class part of the event stream, not a side effect captured in a PR comment.

---

## Island Evolution Across Physical Nodes

Chapter 9 introduced neuroevolution -- neural networks that evolve their own topology through mutation and selection. Chapter 10 showed how TWEANN runs on the BEAM, with each neural network as a set of Erlang processes.

Now imagine this running across the mesh. Each beam node is an "island" in the evolutionary sense. A population of neural networks evolves on beam01, another population evolves on beam02. Periodically, they exchange migrants -- high-fitness individuals that cross from one island to another, injecting genetic diversity.

```
beam01 (Island A)              beam02 (Island B)
─────────────────              ─────────────────
Population: 50 agents          Population: 50 agents
Generation: 142                Generation: 138
Best fitness: 0.87             Best fitness: 0.91

  ──── migration event ────►
  agent genome (0.87)          receives migrant
                               injects into population
                               genetic diversity increases
```

The mesh handles migration naturally. A `migration_offered_v1` fact is published to a topic. Interested islands subscribe. The genome travels as content-addressed data. The receiving island decides whether to accept based on its own fitness landscape.

This isn't theoretical. It's the architecture. The same mesh that carries venture lifecycle events and code artifacts carries neural network genomes. The same event store that records venture decisions records evolutionary history. The same content-addressed distribution that shares compiled modules shares trained network weights.

There's something beautiful about this convergence -- not beautiful in the aesthetic sense, but in the mathematical sense. When you design a system with genuinely general primitives (events, content-addressed data, peer-to-peer transport), you discover that wildly different use cases collapse into the same patterns. Code distribution and genome migration aren't similar problems. But they use the same infrastructure because the infrastructure doesn't care what it carries.

I've been designing systems long enough to know that this kind of convergence is rare and precious. Most systems I've built over thirty-five years have been special-purpose from the ground up -- each new requirement bolted on as a special case, like adding a sunroof to a submarine. When your primitives are genuinely general, the system teaches you things about itself that you didn't know when you designed it.

---

## The Market Model

The most subtle aspect of decentralized development is resource allocation. Who decides which node generates code? Who decides which node runs tests? Who decides which node trains neural networks?

Nobody decides. The market decides.

Each node advertises its capabilities to the mesh:

```
beam01 advertises:
  - LLM: ollama/codellama:34b (GPU: none, CPU inference)
  - CPU: 4 cores, 1.5GHz
  - Storage: 900GB HDD, 224GB NVMe
  - RAM: 32GB

beam03 advertises:
  - LLM: ollama/deepseek-coder:33b
  - CPU: 4 cores, 1.5GHz
  - Storage: 900GB HDD x2, 932GB NVMe
  - RAM: 32GB

developer-laptop advertises:
  - LLM: claude-api (remote, rate-limited)
  - CPU: 16 cores, 3.2GHz
  - GPU: RTX 4090
  - Storage: 2TB NVMe
  - RAM: 64GB
```

When a venture needs code generation, it doesn't assign the task to a specific node. It publishes a capability request: "Need LLM inference for Erlang code generation." Nodes that can fulfill the request respond. The requesting node picks based on whatever criteria matter -- model quality, latency, cost, availability.

This is how real markets work. Buyers don't call a central office to be assigned a seller. They broadcast a need. Sellers respond. Transactions happen bilaterally.

The same mechanism works for CPU-intensive tasks (compilation, testing), storage-intensive tasks (hosting event stores with long histories), and GPU-intensive tasks (neuroevolution training). Each node contributes what it has. No node is required to contribute anything. The system works with whatever resources are available.

I'll be honest: we were skeptical of the market model at first. It sounded like the kind of elegant abstraction that falls apart the moment real workloads hit it. I've been burned by elegant abstractions before -- CORBA was supposed to solve distributed computing, EJBs were supposed to solve component architecture, SOA was supposed to solve enterprise integration. They were all beautiful on the whiteboard and brutal in production.

But it turns out that markets are robust precisely because they're decentralized. A node goes offline? The market adjusts. A new node with a better GPU shows up? The market adjusts. No rebalancing algorithm. No capacity planner. Just nodes offering what they have and consuming what they need. The market model works not because it's elegant but because it's simple -- and after thirty-five years, I've learned that simple and ugly beats elegant and complex every single time.

---

## What Changes

Decentralized development isn't just distributed development with the server removed. It's a different model with different properties. And after living with it for a while, I can tell you that the changes are more profound than they appear on paper.

**Resilience is structural, not operational.** When a centralized CI server goes down, development stops. When a mesh node goes down, the other nodes continue. They might lose access to that node's specific capabilities (its LLM model, its GPU), but the venture's event stream exists on every participating node. Development slows; it doesn't stop.

**Scaling is additive, not managed.** Adding capacity means plugging in another node and starting the daemon. No cluster reconfiguration. No load balancer update. No Kubernetes node pool scaling. The new node joins the mesh, advertises its capabilities, and starts picking up work.

**Audit is intrinsic, not bolted on.** There's no separate audit log, compliance tool, or activity tracker. The event stream IS the audit trail. Every command, every decision, every gate review, every test result -- they're all events in streams that never get modified.

**Collaboration is asynchronous by default.** Nodes don't need to be online simultaneously. A developer works on their laptop during a flight, generating events into their local store. When they land and reconnect, integration facts propagate to the mesh. Other nodes react. The venture advances. Nobody waited for anyone.

This is what decentralized development looks like: not a grand vision of cloud infrastructure without a cloud, but a pragmatic arrangement of small machines, each running the full stack, each contributing what it can, each maintaining its own truth, and all converging through events on a masterless mesh.

No central server. No single point of failure. No single point of control.

Just dossiers, flowing from desk to desk, across machines that find each other in the dark.

The centralization-decentralization cycle has come around again. Mainframes to PCs to client-server to cloud, and now to this: peer-to-peer mesh networks on commodity hardware. But this time we're not decentralizing because we can't afford the mainframe. We're decentralizing because centralization itself became the problem -- the outages, the vendor lock-in, the single points of failure, the surveillance, the rent-seeking. The reasons are different. The tools are better. And after watching this cycle play out three times over three decades, I think this iteration might actually stick.
