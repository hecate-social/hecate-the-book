# Chapter 3: Vertical Slicing

*The death of horizontal layers*

---

I want to tell you about the worst codebase I ever worked on. And I've worked on a lot of them — COBOL systems on mainframes, C++ on VAX/VMS, Java EE monstrosities, Ruby on Rails monoliths, microservice constellations. This one compiled. The tests passed. The CI pipeline was green. The architecture was terrible.

It was a web application with about forty features. User registration, order management, payment processing, the usual suspects. It was organized the way every textbook, every tutorial, and every Stack Overflow answer told us to organize it: by technical concern. Controllers in one folder. Services in another. Repositories in a third. Clean, layered, "professional." It had more layers than a wedding cake and roughly the same shelf life.

Six months in, nobody could find anything. "Where's the code for payment retry logic?" "Check the payment service. No wait, some of it's in the payment controller. Actually, the retry part might be in the order service because it triggers from there. Oh, and there's a helper in `utils/` that does the actual calculation."

Software architecture has a default mode, and it's horizontal. Decades of frameworks, textbooks, and best-practice guides have trained developers to organize code by technical concern. It's so pervasive that most developers have never questioned it. I know I didn't, for the first fifteen years of my career. It was just how things were done — like storing dates as strings was just how things were done, until it wasn't.

This chapter makes the case that horizontal layering is an anti-pattern — one that makes code harder to find, harder to change, and harder to delete. The alternative is vertical slicing: organizing code by business capability, so that everything related to one feature lives together.

---

## The Problem with Layers

Consider a web application with four features: user registration, order placement, payment processing, and shipment tracking. In a horizontally layered architecture:

```
src/
├── controllers/
│   ├── user_controller.erl
│   ├── order_controller.erl
│   ├── payment_controller.erl
│   └── shipment_controller.erl
├── services/
│   ├── user_service.erl
│   ├── order_service.erl
│   ├── payment_service.erl
│   └── shipment_service.erl
├── repositories/
│   ├── user_repo.erl
│   ├── order_repo.erl
│   ├── payment_repo.erl
│   └── shipment_repo.erl
└── models/
    ├── user.erl
    ├── order.erl
    ├── payment.erl
    └── shipment.erl
```

Question: how does user registration work?

To answer, you need to read four files across four directories. Four context switches. One feature. And that's a trivially simple example. In a real system, you'd also check the validation layer, the event layer, the notification layer, and whatever `utils/shared_validators.erl` is doing. I've counted as many as eight files across six directories for a single feature — and that was on a system considered "well-architected" by the standards of its time. It felt like a scavenger hunt, except nobody was having fun.

Now imagine the system has grown to 50 features. Each directory has 50 files. Finding the right file means scanning a list of 50. Understanding a feature means cross-referencing files across 4 directories.

The problem compounds with time. New developers join the team, and the first thing they ask is: "Where is the code for X?" The answer is always: "spread across four directories." They spend their first week building a mental map of which files belong together. I once watched a senior engineer — someone with twenty years of experience — spend three days building a spreadsheet that mapped features to their files across layers. Three days. A spreadsheet. To navigate a codebase. We had built a system so complex that understanding it required its own software project. Something had gone deeply wrong. And the bitter irony was that the same pattern was repeated on the next project, and the one after that. The industry kept prescribing the disease as the cure.

The second problem is change coupling. When you modify user registration — say, adding email verification — you touch files in all four directories. Your pull request spans four directories. The reviewer needs to mentally connect changes across four locations to understand the full picture.

The third problem is deletability. Want to remove the payment feature? You need to find and delete the relevant file from each layer. Miss one, and you have orphaned code that nobody notices for months. We once found a repository class for a feature that had been "removed" two years earlier. The controller and service were gone. The repository just sat there, imported but never called, a ghost of decisions past. This is not unusual. I've found dead code from discontinued features on nearly every layered codebase I've worked on. It's a natural consequence of the architecture — when a feature is spread across five directories, deleting it is an archaeological expedition.

---

## The Vertical Alternative

Now organize the same four features vertically:

```
src/
├── register_user/
│   ├── register_user_v1.erl          ← command
│   ├── user_registered_v1.erl        ← event
│   ├── maybe_register_user.erl       ← handler
│   └── user_registered_to_users.erl  ← projection
├── place_order/
│   ├── place_order_v1.erl
│   ├── order_placed_v1.erl
│   ├── maybe_place_order.erl
│   └── order_placed_to_orders.erl
├── process_payment/
│   └── ...
└── track_shipment/
    └── ...
```

How does user registration work? Read the `register_user/` directory. Everything is there. One directory. One feature. No archaeology.

Want to delete the payment feature? `rm -rf process_payment/`. Done.

Need to add email verification? Your changes are confined to `register_user/`. The PR is focused. The reviewer sees exactly what changed.

New developer joins? They scan the top-level directory and immediately know: this system registers users, places orders, processes payments, and tracks shipments. No mental map needed. No spreadsheet required.

The first time I reorganized a project this way — after fifteen years of layered architecture — the reaction from the team was disbelief. "Wait, that's it? Everything for registration is just... in there?" Yes. That's it. The relief was palpable. It was the same feeling I'd had in the early 2000s when I first used version control after years of manual file copying — an immediate sense of "why didn't we always do this?"

---

## The Core Principle

> **Add a feature, add a folder. Delete a feature, delete a folder. No archaeology required.**

Features are the unit of organization. Each feature contains everything it needs: its command definition, its event definition, its business logic, its side effects, its projections.

The rule has a corollary: **if you're touching files in more than one directory to add a feature, your architecture is horizontal.**

Simple as that. Not always easy. But simple.

---

## What Lives in a Slice

In Hecate's architecture, each vertical slice (called a "desk") contains:

| Component | Purpose | Example |
|-----------|---------|---------|
| Command | The request structure | `announce_capability_v1.erl` |
| Event | What happened | `capability_announced_v1.erl` |
| Handler | Business logic | `maybe_announce_capability.erl` |
| Emitter | Side effects | `capability_announced_to_mesh.erl` |
| API handler | HTTP endpoint | `announce_capability_api.erl` |

Not every desk needs every component. A desk that doesn't have HTTP exposure won't have an API handler. A desk that doesn't publish events externally won't have a mesh emitter. But whatever it needs, it contains.

The desk is the unit of deployment, the unit of testing, and the unit of change. When you're working on a feature, you have one directory open. When you're reviewing a feature, you're looking at one directory. When you're deleting a feature, you delete one directory. The cognitive overhead stays constant regardless of how large the system grows.

---

## The Forbidden Directories

Certain directory names are banned from Hecate codebases. Not because they're inherently evil, but because they're the first symptom of horizontal thinking creeping back in. After thirty-five years in this industry, I've learned to recognize the early warning signs:

| Directory | Why It's Banned |
|-----------|----------------|
| `services/` | Where business logic goes to be orphaned from its context |
| `utils/` | A junk drawer of unrelated functions |
| `helpers/` | Same as `utils/` with a friendlier name |
| `common/` | If it's truly common, it should be a library |
| `shared/` | Shared by whom? For what purpose? |
| `handlers/` | Handlers belong with their commands |
| `listeners/` | Listeners belong with their domains |
| `managers/` | God modules wearing a mask — a `Manager` is an architecture's cry for help, dressed up as a design pattern |

If you feel the urge to create one of these, stop. Ask: "Which feature owns this code?" Put it in that feature's directory.

This is harder than it sounds. Much harder. The urge is strong — it's muscle memory from every project you've ever worked on, reinforced by every framework, every tutorial, every book (possibly including other books on my own shelf from earlier in my career). You have a validation function that two features use. The instinct says: put it in `shared/`. The discipline says: either duplicate it (if it's small), put it in the feature that owns the concept, or extract it into a proper library with its own API, tests, and documentation.

I won't pretend the discipline always felt good. There were moments where duplicating eight lines of code across two desks made me physically uncomfortable. Thirty years of "Don't Repeat Yourself" will do that to you. But I'll take that discomfort over the alternative: a `shared/` directory that starts with one file and ends with sixty, half of which nobody can explain, most of which are used by exactly one consumer, and all of which are coupled to everything. I've seen that movie too many times. I know how it ends.

---

## What About Shared Code?

The question always comes: "But what about code that's genuinely shared across features?"

It comes up in every architecture discussion. Every single one. It came up in CORBA design reviews in the nineties. It came up in SOA governance meetings in the 2000s. It came up in microservice architecture discussions in the 2010s. It's a fair question, and it deserves a real answer.

The answer has three levels:

**Level 1: It's not actually shared.** Two features happen to need similar code, but the similarity is incidental. Duplicate it. Three lines of similar code is better than a premature abstraction that couples two unrelated features. I know this feels wrong. Every instinct screams "DRY! Don't Repeat Yourself!" But DRY is about knowledge duplication, not code duplication. If two features happen to validate email addresses the same way, that's not shared knowledge — it's coincidence. When one feature needs to change its validation rules, you'll be glad they're independent. I resisted this insight for years. It took watching several "shared" validation modules become unmaintainable — because every change risked breaking a consumer nobody remembered — before I accepted it.

**Level 2: It's domain-owned.** One feature defines a concept that another feature uses. The `user_registered_v1` event is defined in the `register_user/` desk. When the `send_welcome_email` process manager needs to react to this event, it reads the event — but the event definition belongs to its originating desk. Dependencies flow from consumer to producer, not to a shared directory.

**Level 3: It's a library.** Truly generic code — HTTP client utilities, date formatting, encryption helpers — belongs in a separate library. In Erlang/OTP, this means a separate OTP application. In the Hecate ecosystem, libraries like `evoq` (CQRS framework), `reckon_db` (event store), and `macula` (mesh network) are separate packages on hex.pm. They have their own APIs, their own tests, their own versioning. They're not `utils/` — they're proper software with clear boundaries.

The distinction: a library is generic, stable, and independently useful. A `utils/` folder is none of these things. If your "shared" code isn't worth giving its own name, its own tests, and its own README, it probably isn't shared — it's just similar.

---

## The Slow Creep

Horizontal organization doesn't arrive all at once. It creeps in through small, reasonable-seeming decisions. This is what makes it so dangerous — each individual step feels sensible. I've watched this exact sequence play out on at least a dozen projects across three decades:

1. "I'll just add a quick utility function to `utils/`." — Now `utils/` exists.
2. "This handler is used by two features, let me put it in `shared/`." — Now `shared/` exists.
3. "The validation logic should be centralized in `validators/`." — Now `validators/` exists.
4. "Let me create a `listeners/` directory for all event listeners." — Now the architecture is horizontal.

Each step seems reasonable in isolation. The result is a codebase where features are scattered across layers, dependencies are implicit, and the directory structure tells you nothing about the business domain.

The creep follows a predictable timeline. It starts with one `utils.erl` file. "Just this once." Then someone adds a second function. Then a third person adds a function that only one module uses but "might be useful later." Within six months, `utils/` has twenty-three functions, four of which are dead code, six of which are used by exactly one caller, and nobody wants to touch it because they're not sure what depends on what. A `utils/` directory is where code goes to die — it's the junk drawer of software, and like every junk drawer, it starts with a battery and a rubber band and ends as an archaeological site. I've seen this exact progression on projects in Perl, Java, C#, Python, Ruby, Elixir, and Erlang. The language is irrelevant. The pattern is universal.

Fighting the creep requires active resistance. Every time you create a file, ask: "Does this belong to a business feature, or am I creating a technical layer?" If it's the latter, rethink.

---

## Vertical Slicing in Practice: Hecate's Martha Plugin

Martha — Hecate's AI-assisted development plugin — demonstrates vertical slicing at scale. Its daemon side is an Erlang umbrella with domain apps, each containing desks:

```
apps/
├── guide_venture_lifecycle/          ← CMD: venture management
│   └── src/
│       ├── initiate_venture/         ← desk: creates ventures
│       ├── submit_vision/            ← desk: submits AI vision
│       ├── open_discovery/           ← desk: starts discovery phase
│       ├── identify_division/        ← desk: identifies bounded contexts
│       └── conclude_discovery/       ← desk: wraps up discovery
│
├── guide_division_lifecycle/         ← CMD: division management
│   └── src/
│       ├── initiate_division/
│       ├── design_aggregate/
│       ├── plan_desk/
│       ├── post_kanban_card/
│       └── generate_module/
│
├── orchestrate_agents/               ← CMD: agent sessions
│   └── src/
│       ├── initiate_visionary/
│       ├── complete_visionary/
│       ├── pass_gate/
│       ├── reject_gate/
│       └── on_venture_initiated_initiate_visionary/
│
├── project_ventures/                 ← PRJ: venture read models
├── project_divisions/                ← PRJ: division read models
├── project_agent_sessions/           ← PRJ: agent session read models
│
├── query_ventures/                   ← QRY: venture query endpoints
├── query_divisions/                  ← QRY: division query endpoints
└── query_agent_sessions/             ← QRY: agent session query endpoints
```

Every desk is a directory. Every directory contains everything that desk needs. There is no `services/` directory for venture management. There is no `handlers/` directory for agent orchestration. Each feature lives in one place.

What I find genuinely remarkable — and after thirty-five years in this industry, it takes a lot to earn that word — is that you can onboard someone to a specific feature without them understanding the entire system. "You're going to work on the vision submission flow. Everything you need is in `submit_vision/`. Read those four files and you'll understand the feature completely." Compare that to the onboarding experience on every layered codebase I've ever worked on: "You're going to work on vision submission. Start with the VisionController, then read VisionService, then check VisionRepository, also there's a VisionValidator in shared, and the event publishing is in EventPublisher. Oh, and Dave wrote a helper in utils that you'll need but isn't documented. Dave doesn't work here anymore." That second version isn't a straw man — it's Tuesday.

---

## The Supervision Tree Follows

In Erlang/OTP, the process supervision tree mirrors the vertical structure. Each domain app has its own supervisor:

```
app_martha_sup
├── guide_venture_lifecycle_sup
├── guide_division_lifecycle_sup
├── orchestrate_agents_sup
├── project_ventures_sup
├── project_divisions_sup
├── project_agent_sessions_sup
├── query_ventures_sup
├── query_divisions_sup
└── query_agent_sessions_sup
```

There is no `all_listeners_sup`. There is no `all_projections_sup`. Each domain owns its infrastructure. If the venture lifecycle needs a process manager, that PM is started by `guide_venture_lifecycle_sup`, not by some central coordinator.

We tried the central coordinator approach early on — and in fairness, it's the approach I'd used on every distributed system going back to CORBA's ORB. We had an `all_listeners_sup` that managed every event listener in the system. It was the single point of failure. When one listener crashed, the restart strategy affected all listeners. When we needed to redeploy one domain, we had to think about the impact on listeners from other domains. It was a mess. The same mess I'd seen with centralized service registries in SOA, with centralized ingress controllers in Kubernetes, with every centralized coordination point in the history of distributed computing. The day we split the supervision tree to match the domain boundaries was the day our deployment confidence went up by an order of magnitude.

This is vertical slicing applied to runtime architecture. The same principle that organizes files also organizes processes. The domain is the organizing unit, not the technical concern.

---

## The Benefits

**Discoverability.** "Where is capability announcement handled?" `ls src/` `announce_capability/`. Found in 3 seconds. Not 3 minutes. Not "ask Sarah." Three seconds.

**Isolation.** Changes to `announce_capability` don't touch `revoke_capability`. Each desk is independent. Merge conflicts between teams working on different features become rare. We went from multiple merge conflicts per week to essentially zero.

**Testability.** Test one feature: `rebar3 eunit --module=maybe_announce_capability`. No need to stand up the entire system. No database fixtures. No mocking half the application. The handler is a pure function: give it a state and a command, it gives you events or an error.

**Deletability.** Remove a feature: `rm -rf src/announce_capability/`. No orphaned code elsewhere. This might be my favorite benefit. In most codebases, removing a feature is terrifying — I've been on teams that maintained dead features for years because nobody was confident enough to delete them. Here, it's a single `rm -rf`.

**Onboarding.** "How does X work?" "Read the `X/` directory." That's the entire onboarding conversation for any single feature.

---

## The Trade-Offs

I won't pretend this is free. Nothing in software architecture is free — that's one of the few constants across thirty-five years. You're trading one set of problems for another. The difference is that I prefer these problems.

**Duplication increases.** Two desks might have similar validation logic. Without a `shared/` directory, you might duplicate it. This is acceptable — the cost of duplication is lower than the cost of coupling. I know this is heresy. I felt like a heretic writing it. But after living with both approaches for decades — on systems ranging from a few thousand lines to a few million — I'll take a few duplicated lines over an invisible dependency chain any day.

**File count increases.** Each desk has its own files, even when they're small. Three files in one directory that explains itself is better than three functions in a God module that explains nothing. Your IDE's file count goes up. Your cognitive load goes down. Reasonable trade.

**Conventions must be enforced.** Without clear conventions (desks, naming patterns, the "maybe" prefix), vertical slicing degenerates into ad-hoc folder organization. The mechanical strictness of the patterns is what makes the approach work. This isn't optional — it's load-bearing. The naming conventions from Chapter 2 are the glue that holds vertical slicing together.

These trade-offs are real. But the teams that adopt vertical slicing consistently report the same thing: the codebase is easier to navigate, easier to change, and easier to explain. And after a career spanning every organizational pattern the industry has tried — from COBOL copybook libraries to Java package hierarchies to Ruby gem conventions to Go's flat packages — I can tell you that vertical slicing is the first approach where I stopped dreading the question "where does this code live?"

---

## The Rule, Restated

Features live together. Code that changes together stays together.

Don't organize by what code IS (controller, service, repository). Organize by what code DOES (register user, process payment, announce capability).

Add a feature. Add a folder. Delete a feature. Delete a folder.

No archaeology required.
