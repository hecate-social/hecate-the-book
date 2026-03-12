# The Autonomous Stack

**Building Self-Evolving Software Systems**

---

> The next generation of software isn't built by humans writing code — it's *grown* by autonomous agents operating on decentralized infrastructure, guided by human judgment at critical gates, and evolved through topology-aware neural networks.

---

## What This Book Is About

This book documents the architecture, philosophy, and implementation of a vertically integrated open-source stack designed for autonomous software development:

- **A masterless peer-to-peer mesh network** — QUIC transport, Kademlia DHT, CRDT consistency, NAT traversal. No central server, no single point of failure.
- **A BEAM-native distributed event store** — Raft consensus via Khepri/Ra, event sourcing as the default, CQRS without ceremony.
- **Neuroevolution libraries** — Topology and Weight Evolving Artificial Neural Networks (TWEANN) running on the BEAM. Neural architectures that evolve, not just train.
- **An LLM-orchestrated development platform** — Multiple AI agents (visionary, explorer, stormer, architect, coders, reviewer, mentor) collaborating through a human-gated pipeline to build software from vision to deployment.

Every layer — from transport to storage to intelligence to UI — is designed for autonomy.

## Structure

### Part I — The Philosophy
The mental models that shape every technical decision.

| Chapter | Title |
|---------|-------|
| 1 | The Dossier Principle — why process-centric beats data-centric |
| 2 | Screaming Architecture — when code tells you what it does |
| 3 | Vertical Slicing — the death of horizontal layers |
| 4 | Events as Facts — why immutable history changes everything |

### Part II — The Infrastructure
The foundation: networking, storage, and the patterns that make them work together.

| Chapter | Title |
|---------|-------|
| 5 | A Masterless Mesh — QUIC, DHT, CRDTs, and the end of central servers |
| 6 | The Event Store — Raft consensus on the BEAM, streams as truth |
| 7 | CQRS Without the Ceremony — aggregates, projections, process managers |
| 8 | Bit Flags and Status Machines — compact state for event-sourced systems |

### Part III — The Intelligence
Where classical AI meets large language models.

| Chapter | Title |
|---------|-------|
| 9 | Neuroevolution — why topology matters more than weights |
| 10 | TWEANN on the BEAM — evolving neural architectures in Erlang |
| 11 | LLM Orchestration — agents, roles, tiers, and the relay pattern |
| 12 | The Human Gate — when machines must stop and ask |

### Part IV — The Platform
The product: a decentralized development environment that brings it all together.

| Chapter | Title |
|---------|-------|
| 13 | The Venture Lifecycle — from vision to deployment in 10 processes |
| 14 | Plugin Architecture — extending without coupling |
| 15 | Martha Studio — building the command center for AI-assisted development |
| 16 | The Agent Relay — watching machines collaborate in real-time |

### Part V — The Synthesis
What happens when every layer reinforces every other layer.

| Chapter | Title |
|---------|-------|
| 17 | Decentralized Development — when your build system has no master |
| 18 | The Autonomous Stack — how every layer reinforces the others |
| 19 | What Comes Next — self-modifying codebases and evolutionary deployment |

## Target Audience

Senior engineers and architects who feel the current AI-assisted dev tooling is shallow — autocomplete, not architecture. People who want to understand what a *real* autonomous development platform looks like, built from first principles.

## What Makes It Different

It's not theory. Every chapter has running code. The mesh exists. The event store ships. The agents run. The neuroevolution library is on hex.pm. This is a book that says "here's what we built and why" — not "imagine if."

## Source Ecosystem

| Repository | What It Is |
|------------|-----------|
| `macula-io/macula` | Masterless mesh network (QUIC, DHT, CRDTs) |
| `reckon-db-org/reckon-db` | BEAM-native distributed event store |
| `reckon-db-org/evoq` | CQRS/Event Sourcing framework |
| `reckon-db-org/reckon-evoq` | Adapter connecting evoq to reckon-db |
| `rgfaber/faber-tweann` | TWEANN neuroevolution on the BEAM |
| `rgfaber/faber-neuroevolution` | Neuroevolution algorithms and experiments |
| `hecate-social/hecate-daemon` | The platform runtime (Erlang/OTP) |
| `hecate-social/hecate-web` | The desktop client (Tauri + SvelteKit) |
| `hecate-social/hecate-agents` | Philosophy, skills, and agent templates |
| `hecate-apps/hecate-app-martha` | Martha — AI-assisted software development plugin |

## License

Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)
