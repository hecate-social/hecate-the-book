# Chapter 1: The Dossier Principle

*Why process-centric beats data-centric*

---

I've been building software since 1990. In that time, I've worked on mainframes, VAX/VMS clusters, AS/400 systems, client-server architectures, three-tier web apps, SOA, microservices, and whatever we're calling the current thing. Through all of it — every paradigm, every platform, every industry cycle — I kept building systems the way everyone told me to. You have a `User`. You have an `Order`. You have a `Capability`. Each is a row in a database, a struct in memory, a thing with a current state. You create it, read it, update it, delete it. CRUD. The verbs are generic because the model treats everything as a container of mutable data.

And for decades, it worked. Or at least, it seemed to work — in the same way that not going to the dentist "works" until it suddenly, catastrophically doesn't. Then one Thursday afternoon in the late 2000s, a customer called to say they'd been charged twice. I looked at the order. Status: "paid." Just... "paid." No record of how many times payment was attempted. No trace of the duplicate charge. The database knew what the order *was*, but had absolutely no memory of what had *happened* to it.

That bug reminded me of something I'd known since my mainframe days but had let the industry talk me out of: you never overwrite a ledger entry. You make a correcting entry. Accountants figured this out five hundred years ago with double-entry bookkeeping. The AS/400 transaction logs I'd worked with in the early nineties never overwrote anything — they appended. Database write-ahead logs don't overwrite anything — they append. The entire financial industry had been doing this since before computers existed. And here I was, in the twenty-first century, building systems that destroyed their own history on every UPDATE statement.

This book starts from a different premise: **software is process, not data.**

The central metaphor is borrowed from how actual offices work — not the kind with standing desks and Slack channels, but the old kind. The kind with physical folders, clerks, and rubber stamps. The kind where work gets done by passing a dossier from desk to desk, each clerk adding a slip of paper before sending it along.

That metaphor isn't decorative. It's the architecture.

---

## The Two Mental Models

![The Dossier Metaphor](assets/dossier-metaphor.svg)

Consider an order in a typical e-commerce system.

In the **data-centric** model, the order is a database record. It has a status column. When the customer pays, you UPDATE the status to "paid." When you ship it, you UPDATE it again. The order's identity is its primary key. Its history is whatever you remembered to log.

```
Order #4821
  status: shipped
  updated_at: 2026-03-01T14:32:00Z
```

That's the entire truth about this order. Two fields. No memory of how it got here. Asking this database about the order's history is like asking a goldfish about last Tuesday — it's not being evasive, it genuinely has no idea. Was the payment retried three times? Did the warehouse put it on hold before shipping? Did someone change the shipping address between payment and fulfillment? The database shrugs. It doesn't know. It wasn't paying attention.

In the **process-centric** model, the order is a dossier — a folder that accumulates slips of paper as it passes through your organization:

```
Dossier: order-4821
  [slip] order_placed_v1        — customer, items, total
  [slip] payment_received_v1    — amount, method, processor_ref
  [slip] inventory_reserved_v1  — warehouse, items, reservation_id
  [slip] order_shipped_v1       — carrier, tracking_number, shipped_at
```

The dossier **is** its history. There is no separate "current state" — there's only the complete sequence of what happened. To know the order's status, you read the slips. The last slip tells you it was shipped. The slip before that tells you inventory was reserved. The one before that tells you payment came in.

Nothing was overwritten. Nothing was lost. And when that customer calls about a double charge, you open the dossier and there it is: two `payment_received_v1` slips, twelve seconds apart. Mystery solved in under a minute.

---

## Why the Difference Matters

The data-centric model answers one question: "What IS this thing right now?" It's an order. It's shipped. That's what it is.

The process-centric model answers a different question: "What has HAPPENED to this dossier?" It was placed, paid, reserved, and shipped. Each step is a fact. Each fact carries its own data — who did it, when, with what parameters.

If you'd asked me in 1995 whether I needed this distinction, I would have said no. We had transaction logs on the mainframe. We had audit tables in Oracle. The idea that the application layer itself should think in terms of events rather than state? That felt like over-engineering. Then we had our first production incident where two services disagreed about whether an order had been fulfilled, and the only way to figure out what happened was to grep through application logs across three servers, correlating timestamps by hand at 2 AM. I'd had that exact same experience on a DCE/RPC system in 1997, and again on a SOAP-based SOA in 2004. By the third time, "just keep the current status" stopped being a convincing argument.

The distinction cascades through every design decision:

**Validation changes meaning.** In the data-centric world, validation means "is this data well-formed?" In the process-centric world, validation means "given the slips in this dossier, can this new slip be added?" You can't ship an order that hasn't been paid. The dossier tells you whether payment happened — not by checking a status flag, but by looking for a payment slip.

**Undo becomes natural.** Data-centric systems need elaborate undo mechanisms because updating is destructive. Process-centric systems never update — they append. To cancel a shipment, you add a `shipment_cancelled_v1` slip. The original shipment slip remains as historical fact. I once watched a team spend three sprints building an "undo" feature for a CRUD app — and I'd seen the same struggle on a CORBA-based system in the late nineties. In an event-sourced system, it would have been an afternoon.

**Debugging becomes archaeology.** When something goes wrong in a data-centric system, you're left reading logs and guessing at sequences. In a process-centric system, the dossier IS the log. Every decision that was made, every state transition that occurred, is right there in order. After thirty-five years of 3 AM production incidents, I can tell you that the single greatest gift a system can give its operators is a complete, ordered record of what happened. No guessing. No reconstruction. Just facts.

**Projections replace queries.** Instead of querying a single source of truth, you build read-optimized views (projections) from the event stream. Need orders by customer? Build a projection. Need orders by status? Build another one. Each view is disposable — delete it, replay the events, get the same result.

---

## The Office Metaphor

Imagine a physical office. Not an open-plan tech office — a government office. The kind with departments.

A dossier arrives at the front desk. The clerk checks whether it should be here. If it's a new dossier, they assign it an ID and stamp the first slip: "Received." Then they route it to the right department.

At each desk, the process repeats:

1. The dossier arrives
2. The clerk reviews the slips inside
3. The clerk decides whether to add a new slip
4. The dossier moves on

Some desks are mandatory. Some are conditional — the dossier only goes to the auditing desk if the amount exceeds a threshold. Some desks generate side effects — the notification desk sends a letter to the customer. But the dossier itself just accumulates slips.

I know what you're thinking: "This is just a metaphor. Real software is more complicated." And you're right — it is more complicated. But here's what three decades of building distributed systems taught me: the complication lives in the business rules at each desk, not in the flow of the dossier. The *pattern* is exactly this simple. Every time the industry has invented a new architecture — CORBA services, EJB session beans, SOA orchestrations, microservice choreographies — the underlying pattern was always "a thing moves through stations where decisions are made." The only question was how much accidental complexity we buried it under.

This maps directly to code:

- **Dossier** = Aggregate (the event stream for one entity)
- **Slip** = Event (an immutable fact about what happened)
- **Desk** = Command handler (a station where decisions are made)
- **Clerk** = Business logic (the rules that decide whether a slip can be added)
- **Filing cabinet** = Event store (where all dossiers live)
- **Index card** = Projection (a read-optimized view derived from dossier contents)

The metaphor isn't forced. It's how event-sourced systems actually work. We just usually describe them in technical jargon — "aggregates," "event handlers," "read models" — that obscures the simplicity of the underlying pattern. When I started explaining the architecture to new team members using the office metaphor instead of the DDD vocabulary, onboarding time dropped from weeks to days. Not because the concepts changed, but because the words finally matched something people could picture.

---

## The Hierarchy: Venture, Division, Department, Desk

A single dossier passing through desks is the atomic unit. But real systems have hundreds of dossiers, dozens of desks, and multiple bounded contexts. How do you organize them?

I've been through this cycle more times than I'd like to admit. Every decade brings a new answer. In the nineties it was CORBA naming services and DCE cells. In the 2000s it was SOA registries and ESBs (in retrospect, naming it "Enterprise Service Bus" should have been our first warning — anything with "Enterprise" in the name is one vendor presentation away from becoming a religion). In the 2010s it was microservice catalogs and Kubernetes namespaces. The first attempt was always flat — everything in one namespace. That lasted about three weeks before we couldn't find anything. The second was always layered — technical concerns grouped together. That was worse (Chapter 3 will explain why in painful detail). The third attempt is what finally stuck: the office metaphor, extended upward.

```
Venture (1)
  └── Division (N)         — one per bounded context
       └── Department (3)  — CMD, PRJ, QRY
            └── Desk (N)   — individual capability
```

**A Venture** is the entire endeavor — the thing described in an elevator pitch. "We're building a decentralized marketplace for AI capabilities." There's one venture. Everything below serves it.

**A Division** is a bounded context — a cohesive piece of the business that owns its own language, its own data, its own processes. The marketplace venture might have divisions for capability management, reputation tracking, billing, and plugin distribution. Each division is autonomous. It has its own event store, its own aggregates, its own terminology. A division doesn't need to know how other divisions work.

**A Department** is where the CQRS structure appears. Every division has exactly three departments, always the same three:

| Department | Role | Office Analogy |
|------------|------|----------------|
| **CMD** (Command) | Makes decisions. Receives commands, enforces business rules, produces events. | The decision-making floor — where clerks read dossiers and stamp slips |
| **PRJ** (Projection) | Maintains records. Subscribes to events, builds and updates read-optimized views. | The records office — clerks who maintain index cards and filing summaries |
| **QRY** (Query) | Answers questions. Serves read models to the outside world via API endpoints. | The information desk — where visitors come to ask questions |

This isn't an arbitrary division. It's the minimum structure that keeps writes and reads separate. The CMD department never reads from projections (it reads from its dossiers). The QRY department never writes events (it reads from projections). The PRJ department bridges the two — it consumes events from CMD and produces the read models that QRY serves.

If the three-department split seems like overkill, consider: this is exactly what database architects have been doing since the eighties with read replicas. Separate the write path from the read path. What CQRS does — what Greg Young articulated in the mid-2000s — is apply that same separation at the application level, not just the infrastructure level. We tried combining PRJ and QRY into one department. Within a month we had projection code tangled with query code, and nobody could change one without risking the other. Three departments is the minimum that actually holds up under pressure.

```
             ┌─────────────────────────────────────────────┐
             │              Division                       │
             │                                             │
  Command ──►│  CMD ──events──► PRJ ──read models──► QRY  │──► Response
             │   │                                         │
             │   └──► Event Store (source of truth)        │
             │                                             │
             └─────────────────────────────────────────────┘
```

In code, each department is a set of OTP applications under the umbrella:

```
apps/
├── guide_order_lifecycle/      ← CMD department (the process verb)
│   ├── place_order/            ← desk
│   ├── ship_order/             ← desk
│   └── cancel_order/           ← desk
├── project_orders/             ← PRJ department (projections + store)
│   ├── order_placed/           ← projection desk
│   └── order_shipped/          ← projection desk
└── query_orders/               ← QRY department (HTTP endpoints)
    ├── get_order_by_id/        ← desk
    └── get_orders_page/        ← desk
```

Notice the naming. The CMD app is named after the process: `guide_order_lifecycle`. It screams what it does. The PRJ app is named after what it projects: `project_orders`. The QRY app is named after what it queries: `query_orders`. Every name reveals purpose (Chapter 2).

**A Desk** is the smallest unit — one capability. The `place_order` desk contains the command definition, the event it produces, the handler that enforces business rules, and any side effects (emitters that announce the event via process groups or the mesh). A desk is a vertical slice. Everything needed to understand one operation lives in one directory.

The hierarchy is fractal. A venture contains divisions. Each division contains three departments. Each department contains desks. And each desk processes dossiers. The dossier principle operates at every level — ventures have dossiers, divisions have dossiers, and the desks within each division's CMD department are where those dossiers are processed.

This structure is not optional. It's not a suggestion. It's the organizing principle that makes a 50-app Erlang umbrella navigable. When you join the team and open the `apps/` directory, the structure screams: "Here are the divisions. Each has CMD, PRJ, QRY. Each desk inside does one thing." You can find any piece of business logic in seconds. After thirty-five years of navigating codebases organized every which way — from monolithic COBOL copybooks to Java EE packages with fourteen directory levels — I can tell you that finding code in seconds never gets old. It still feels like a superpower.

---

## Stream ID = Dossier Identity

Every dossier needs a unique identifier — something that ties all its slips together:

```
order-4821
capability-mri:capability:io.macula/weather
reputation-agent-abc123
division-planning-7f3a9b2e
```

The stream ID is the dossier's name on the folder tab. All events (slips) for this dossier share this identifier. When you need to make a decision about this dossier, you load its stream and read the slips.

In Hecate, the event store (ReckonDB) stores dossiers as event streams. Each stream is identified by a string. The CQRS framework (evoq) manages the lifecycle: loading the stream, applying events to rebuild state, executing commands, appending new events.

```erlang
%% The aggregate is the dossier reader.
%% execute/2: "Given what's happened so far, can this command produce new events?"
execute(#order_state{} = State, #{command_type := <<"ship_order">>} = Cmd) ->
    case evoq_bit_flags:has(State#order_state.status, ?PAYMENT_RECEIVED) of
        true  -> {ok, [order_shipped_v1:new(State, Cmd)]};
        false -> {error, payment_not_received}
    end.

%% apply/2: "Read this slip and update my understanding of the dossier."
apply(State, #{event_type := <<"OrderShipped.v1">>, data := Data}) ->
    State#order_state{
        status = evoq_bit_flags:set(State#order_state.status, ?SHIPPED),
        tracking_number = maps:get(<<"tracking_number">>, Data)
    }.
```

The aggregate's `execute` function is the clerk checking whether a new slip can be added. The `apply` function is the clerk reading an existing slip to understand the dossier's history. The distinction is crucial: `execute` makes decisions, `apply` only reads.

---

## Desks Are Verbs, Not Nouns

In the data-centric world, you organize code around entities: `OrderService`, `OrderRepository`, `OrderController`. The noun is the organizing principle.

I've watched this pattern play out across four decades of programming paradigms. In the nineties it was `OrderBean` and `OrderDAO`. In the 2000s it was `OrderService` and `OrderRepository`. In the 2010s it was `OrderController` and `OrderModel`. The nouns change their suffixes, but the gravitational pull is always the same: everything related to "Order" collapses into one place, and that place grows until it becomes unmanageable. We had a beautiful `OrderService` with twelve methods in it. Then it grew to thirty. Then we needed to add a feature and three people had merge conflicts on the same file. The noun attracted everything order-related like a gravity well, and eventually it collapsed under its own weight. I'd seen the same implosion on a CORBA system in 1998 — different language, same disease.

In the process-centric world, you organize around actions:

```
src/
├── place_order/
│   ├── place_order_v1.erl          ← command record
│   ├── order_placed_v1.erl         ← event record
│   ├── maybe_place_order.erl       ← handler (business logic)
│   └── order_placed_to_mesh.erl    ← emitter (side effect)
├── ship_order/
│   ├── ship_order_v1.erl
│   ├── order_shipped_v1.erl
│   ├── maybe_ship_order.erl
│   └── order_shipped_to_pg.erl
└── cancel_order/
    ├── cancel_order_v1.erl
    ├── order_cancelled_v1.erl
    └── maybe_cancel_order.erl
```

Each directory is a desk. Each desk handles one action. The desk contains everything needed: the command definition, the event it produces, the business logic, and any side effects.

This is vertical slicing (Chapter 3) applied to the dossier model. A stranger looking at this directory tree immediately knows: this system places orders, ships them, and cancels them. The structure screams its intent (Chapter 2). And nobody will ever have a merge conflict because they were both editing `OrderService`.

---

## The Default Read Model

Here's a principle that catches people off guard: **the aggregate state IS the default read model.**

When Greg Young started talking about CQRS, one of the things that took longest to sink in — even for people like me who'd been separating read replicas from write masters for years — was that the aggregate itself was already the most complete view of any entity. We spent weeks building elaborate query mechanisms before realizing we already had the most complete view right there in the aggregate. When you replay all events in a dossier's stream, the resulting aggregate state is the complete truth about that process instance. It contains everything that has ever happened, collapsed into a current understanding. It's what the clerk knows after reading every slip in the folder.

This means event payloads don't need to carry the entire world. They carry a **subset of the aggregate state** plus any new data from the command:

```
Event Payload = subset(Aggregate State) + new data from Command
```

When the `ship_order` desk adds a shipping slip, the slip carries the tracking number (new data from the command) and echoes the order ID and customer ID (from the existing aggregate state). Downstream consumers — process managers, projections — receive everything they need IN the event.

This principle has a hard consequence: **data from outside the bounded context enters ONLY through commands.** If a process manager needs data it doesn't have, the fix is never to reach outside and read from a database. The fix is to trace the chain backward:

```
PM needs field X
  → Event doesn't carry X
    → Handler didn't echo X from aggregate state
      → Aggregate state doesn't have X
        → Command didn't bring X in
          → API handler didn't enrich the command with X
```

Fix it at the source. Usually the API handler (at the boundary) needs to read from a projection and stuff the data into the command before dispatching it.

We learned this the hard way. We had a process manager that reached into a SQLite read model during event replay to look up a user's email address. It worked perfectly in production. Then we needed to rebuild projections from scratch, and the process manager tried to read from an empty table. The behavior diverged from the original run. It took us two days to track down why the rebuild produced different results. This was the same class of bug I'd seen on mainframe batch systems in the early nineties — a job that depended on the output of another job that hadn't run yet. Different technology, identical mistake. The lesson hasn't changed in thirty-five years: never let a process depend on state that might not exist when you replay it.

The practical test: **"Can I delete all read models, replay all events, and get the same result?"** If the answer is yes, the system is correctly designed. If a process manager reads from a projection during replay, the answer is no — because the projection might be empty during replay, producing different behavior than the first run.

That test has saved us more times than I can count. Every time someone proposes a shortcut that involves reading from a projection in the command path, we ask the question. The answer is always no. The shortcut always loses.

---

## Designing with Dossiers

When you sit down to model a new domain, the dossier principle gives you a recipe. It's not glamorous. It's not going to win you any conference talk awards. (Though to be fair, the talks that win awards tend to describe systems that don't exist yet, while the talks about systems that actually work are scheduled for 4 PM on the last day.) But after thirty-five years, I've learned to prize the boring approaches that work every time over the exciting ones that work sometimes.

**1. What dossiers exist?**

What are the "things" that accumulate history? Not entities — processes. An order is processed. A capability is announced, endorsed, and potentially revoked. A division goes through planning and crafting phases.

**2. What's the stream ID pattern?**

How is each dossier uniquely identified? `order-{order_id}`. `capability-{mri}`. `division-planning-{division_id}`.

**3. What desks process each dossier?**

What actions can happen? List them as verbs:

```
Order dossier passes through:
├── place_order     (birth — creates the dossier)
├── receive_payment
├── reserve_inventory
├── ship_order
└── cancel_order    (may happen at various points)
```

**4. What slips can be added?**

Each desk produces a specific event type:

| Desk | Slip (Event) |
|------|-------------|
| `place_order` | `order_placed_v1` |
| `receive_payment` | `payment_received_v1` |
| `ship_order` | `order_shipped_v1` |
| `cancel_order` | `order_cancelled_v1` |

**5. What index cards do we need?**

Projections are index cards for the filing cabinet. They let you find dossiers without opening every folder:

- Orders by customer (for the "my orders" page)
- Orders by status (for the fulfillment dashboard)
- Revenue by day (for accounting)

Each projection is a separate, disposable read model built from the event stream.

---

## Minimal Ceremony

One consequence of thinking in processes: every desk should do real work. If a command exists only to change a flag so another command can run, it's ceremony — remove it.

The test: "Does this command produce a business-meaningful event, or does it just change a flag?"

I've seen this trap on every project I've worked on, going back to COBOL batch jobs that existed solely to set a flag for the next job in the sequence. The technology changes; the antipattern doesn't. We fell into it ourselves — we had a three-step workflow where one of the steps existed purely to "unlock" the next step. It felt right — it was modeling a "real" business process. But the middle step carried no data, triggered no side effects, and produced an event that nobody cared about. It was pure ceremony.

Bad (ceremony):

```
submit_vision → SUBMITTED (locked)
reopen_vision → SUBMITTED cleared (does nothing but unlock)
refine_vision → actually changes the vision
```

Good (minimal):

```
submit_vision → SUBMITTED (locked)
refine_vision → changes vision AND clears SUBMITTED
```

`refine_vision` IS the reopening. There's no separate unlock step. The action carries the transition.

The exception: a dedicated transition command is not ceremony when it carries its own business data (a `shelve_planning` command records a shelve reason), triggers meaningful side effects (a process manager reacts to the shelving event), or represents a distinct business decision that should be auditable in the event stream.

---

## The Dossier in Practice: Hecate's Venture Lifecycle

Hecate uses the dossier principle to model software development itself. A venture (a software project) is not a database record — it's a process that passes through phases:

```
Venture Dossier: venture-{venture_id}
  [slip] venture_initiated_v1
  [slip] vision_submitted_v1
  [slip] discovery_opened_v1
  [slip] division_identified_v1  (identifies a bounded context)
  [slip] division_identified_v1  (another one)
  [slip] discovery_concluded_v1
```

Each identified division gets its own dossier:

```
Division Planning Dossier: division-planning-{division_id}
  [slip] planning_initiated_v1
  [slip] planning_opened_v1
  [slip] aggregate_designed_v1
  [slip] event_designed_v1
  [slip] desk_planned_v1
  [slip] planning_concluded_v1
```

And when planning concludes, a process manager (an automated clerk) initiates crafting:

```
Division Crafting Dossier: division-crafting-{division_id}
  [slip] crafting_initiated_v1
  [slip] crafting_opened_v1
  [slip] module_generated_v1
  [slip] test_generated_v1
  [slip] test_result_recorded_v1
  [slip] release_delivered_v1
```

Each dossier is independent. Each has its own desks, its own slips, its own lifecycle. Process managers coordinate between them — when one dossier reaches a terminal event, the PM dispatches a command to initiate the next dossier. The processes never call each other directly.

This is process-centric architecture: not "managing data about software development," but "modeling software development as a set of business processes, each with its own dossier."

There's something deeply satisfying about this for someone who's spent thirty-five years watching the industry reinvent project tracking tools. We used to have a project management tool (several, actually — I've used every generation from Lotus Notes databases to Rational ClearQuest to Jira to Notion). When something went sideways, we'd dig through whatever the current tool was, trying to reconstruct what happened. Now the system itself tells the story. The dossier is the history. The history is the truth. It's the same principle as the AS/400 transaction logs I worked with in 1992, just applied at the application level instead of the infrastructure level.

---

## What This Changes

Adopting the dossier principle isn't just a modeling exercise. It changes how you think about your entire system:

**You stop building APIs around entities** and start building them around actions. Instead of `PUT /orders/:id`, you have `POST /orders/:id/ship`. Instead of a generic update endpoint, you have specific commands that correspond to business operations. Your API becomes a menu of things you can *do*, not a list of things you can *mutate*.

**You stop worrying about database schema migrations** because there is no schema — there are events. The event store is append-only. When your understanding of the domain changes, you version your events (`order_placed_v2`) and write upcasters to transform old events during replay.

**You gain auditability for free.** Every state change is an event. Every event has a timestamp, a correlation ID, and a causation chain. You never need to add logging — the event stream IS the log.

**You gain temporal queries for free.** "What was this order's status on March 1st?" Replay events up to that date. Done.

**You accept eventual consistency** as a feature, not a bug. Read models are derived from events. They might be milliseconds behind. That's fine — the event stream is the truth, and projections catch up.

The trade-off is complexity. Event-sourced systems have more moving parts than a CRUD application. CRUD is the junk food of software architecture — quick, satisfying, and slowly killing your ability to understand your own system. You need an event store, command handlers, projections, process managers. The conceptual overhead is higher. Yes, your team will push back. Yes, the first sprint will feel slower. Here's what I can tell you after three and a half decades: the systems I've seen survive and thrive long-term all shared one trait — they could explain what had happened. The CRUD systems could tell you where they were. The process-centric systems could tell you how they got there. When a bug report comes in at 2 AM, that difference is everything. By the third month, the team that adopted this approach stopped dreading bug reports. They started looking forward to them. "Let me just pull up the event stream" replaced "Let me try to reproduce this."

But the payoff is a system that remembers everything, explains itself, scales horizontally (events are partitioned by stream), and models the business domain in the language of the business.

The dossier principle says: **don't ask what a thing IS. Ask what has HAPPENED to it.**

Pass the dossier. Add the slip. Move on.
