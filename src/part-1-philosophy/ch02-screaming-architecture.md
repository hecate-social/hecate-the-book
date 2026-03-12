# Chapter 2: Screaming Architecture

*When code tells you what it does*

---

In the mid-2000s, I joined a project mid-flight. By that point I'd been in the industry for fifteen years, so I'd seen my share of codebases. Day one, I cloned the repo, opened the `src/` directory, and saw this:

```
src/
├── controllers/
├── services/
├── repositories/
├── models/
└── utils/
```

I stared at it for a while. Then I asked my new colleague: "What does this application do?" He laughed. "Good luck figuring that out from the folder structure."

He wasn't wrong. That directory told me exactly one thing: the developer used an MVC framework. It told me nothing about what the application does. Is it a banking system? A social network? A spaceship navigation computer? Impossible to tell. The directory structure screams "I'm a web app built with Rails/Spring/Django" — the implementation detail, not the purpose. It's the architectural equivalent of answering "What do you do?" with "I use a keyboard."

I'd seen this same layout in a different skin on every project for fifteen years. In the nineties it was `ejb/`, `dao/`, `dto/`. In the early 2000s it was `managers/`, `facades/`, `delegates/`. The framework du jour changed; the organizational disease didn't. We kept telling new developers what technology we used instead of what problem we solved.

Now open Hecate's source directory for one of its domain apps:

```
src/
├── announce_capability/
├── revoke_capability/
├── track_rpc_call/
├── flag_dispute/
└── resolve_dispute/
```

Without reading a single line of code, you know: this system manages capabilities (announcing and revoking them) and handles disputes (flagging and resolving them). The architecture screams its intent.

This is not a cosmetic preference. This is not "bike-shedding over folder names" (though if you've ever attended a naming discussion that lasted longer than the feature implementation, raise your hand — I see all of you). This is a design principle with concrete consequences for maintainability, onboarding, and the ability to reason about a system at scale. I've watched teams waste entire sprints because someone couldn't find the code that handled a critical business operation — in the nineties on CORBA codebases, in the 2000s on J2EE projects, in the 2010s on microservice repos. That doesn't happen when the architecture screams.

---

## The Stranger Test

The principle has a simple litmus test: **imagine a stranger opens your codebase for the first time. Can they tell what the system does just by reading directory and file names?**

If the answer is "they can tell it's a web app" — you've failed. If the answer is "they can tell it manages orders, handles payments, and coordinates shipments" — you've passed.

We used this test constantly during development. Whenever someone proposed a new module name, we'd ask: "If you'd never seen this codebase, would this name tell you what's inside?" It felt pedantic at first. Then a new team member joined and navigated to the exact piece of code they needed within thirty seconds of cloning the repo. After decades of watching new hires spend their first week just learning where things live, that moment felt like vindication.

This test applies at every level:

**Directory names** should be verb phrases that describe business actions:

```
announce_capability/          ← PASSES
track_rpc_call/               ← PASSES
flag_dispute/                 ← PASSES
detect_llm_models/            ← PASSES

capability/                   ← FAILS
rpc/                          ← FAILS
dispute/                      ← FAILS
llm_handler/                  ← FAILS
```

**File names** should describe the file's role in the business operation:

```
announce_capability_v1.erl             ← PASSES
capability_announced_v1.erl            ← PASSES
maybe_announce_capability.erl          ← PASSES
capability_announced_to_mesh.erl       ← PASSES

capability_command.erl                 ← FAILS
capability_event.erl                   ← FAILS
capability_handler.erl                 ← FAILS
capability_publisher.erl               ← FAILS
```

**Module names** should read like English sentences:

```
"maybe announce capability"            ← reads naturally
"capability announced to mesh"         ← reads naturally
"on user registered send email"        ← reads naturally

"capability handler"                   ← reads like code gibberish
"capability publisher"                 ← reads like code gibberish
"user notification manager"            ← reads like code gibberish
```

That last one — `user_notification_manager` — is a real module name I encountered in a Java EE codebase around 2008. What does it manage? All user notifications? Just one type? Does it send them, queue them, template them? Nobody could tell from the name. The developer who wrote it had left the company six months earlier — the code equivalent of a crop circle, clearly made by intelligent life but impossible to interpret. `on_user_registered_send_welcome_email` would have saved us an hour. I could fill a book with module names like this — `TransactionProcessor`, `DataManager`, `ServiceHelper` — names that sound important but communicate nothing.

---

## Technical Names vs. Business Names

The fundamental tension is between naming things for what they ARE (technical) versus naming things for what they DO (business):

| Technical Name | Business Name |
|----------------|---------------|
| `handler` | `announce_capability` |
| `service` | `track_rpc_call` |
| `manager` | `resolve_dispute` |
| `processor` | `detect_llm_models` |
| `worker` | `listen_for_llm_request` |
| `controller` | `grant_capability` |

Technical names are generic containers. They tell you the pattern but not the content. Business names are specific — they tell you exactly what happens in this code.

This matters because developers spend most of their time reading code, not writing it. When you need to find where capability announcements are handled, `grep -r "announce_capability"` gives you an immediate, unambiguous result. When you search for `handler` or `service`, you get every handler and service in the system. I've done that search on codebases of every size, from a ten-person startup to a Fortune 500 enterprise. The result is always the same: dozens or hundreds of matches, none of them what you're looking for, and an afternoon lost to reading through them.

---

## The CRUD Taboo

One consequence of screaming architecture is that CRUD verbs are banned from event names and desk names. `create`, `read`, `update`, `delete` — these are generic database operations, not business actions.

This was the hardest habit to break. The industry has been teaching CRUD since the 1980s — since before I started. It's the first thing every tutorial teaches you. "Let's build a CRUD app!" And CRUD is fine for what it is — when your domain truly is "store and retrieve data." But most interesting domains aren't that. They have *processes*, and those processes deserve names that describe what's actually happening.

| CRUD Verb | Problem | Business Alternative |
|-----------|---------|---------------------|
| `create_user` | What kind of creation? | `register_user`, `invite_user`, `import_user` |
| `update_order` | What's being updated? | `confirm_order`, `ship_order`, `amend_order` |
| `delete_item` | Why? | `archive_item`, `remove_item`, `expire_item` |
| `user_created` | Meaningless | `user_registered`, `user_invited`, `user_imported` |
| `order_updated` | Tells you nothing | `order_confirmed`, `order_shipped`, `order_amended` |

The test: can you distinguish the business intent from the verb alone? "User created" tells you a user now exists. "User registered" tells you someone signed up. "User invited" tells you someone else brought them in. "User imported" tells you they came from a bulk migration. Same outcome (a user exists), entirely different business contexts.

Here's the moment this became visceral for me: we had an `order_updated` event in production. A bug report came in about incorrect order totals. I opened the event stream and saw seventeen `order_updated` events. Some changed the shipping address. Some changed the quantity. Some applied coupons. Some corrected pricing errors. They were all called `order_updated`. I had to read the payload of each one to figure out what actually happened. I'd seen this exact pattern twenty years earlier on a mainframe system that logged every record change as `RECORD_MODIFIED` with a blob of before-and-after data. Same mistake, thirty years apart. If they'd been named `shipping_address_changed`, `quantity_adjusted`, `coupon_applied`, `pricing_corrected` — the debugging session would have taken five minutes instead of an hour.

Events are historical facts. They should describe what happened in the language of the domain, not in the language of database operations.

---

## Naming Patterns That Scream

Hecate uses consistent naming patterns across all domain apps. Each pattern encodes both the business role and the technical function:

**Commands** are imperative, present-tense verb phrases with a version:

```
announce_capability_v1
revoke_capability_v1
register_user_v1
ship_order_v1
```

The version suffix enables evolution. When the command's payload changes, you create `v2` alongside `v1`. No breaking changes.

**Events** are past-tense, describing what happened:

```
capability_announced_v1
capability_revoked_v1
user_registered_v1
order_shipped_v1
```

Note the inversion: commands are `verb_noun_version`, events are `noun_verbed_version`. Commands tell you what to do; events tell you what was done. We went through three naming conventions before landing on this one. The first used the same order for both (confusing). The second used full sentences (too long). This inversion — imperative for commands, declarative for events — is the one that stuck, because it mirrors natural language. If that sounds like a small thing, try maintaining a system with five hundred events and see whether consistent naming matters.

**Handlers** use the "maybe" prefix:

```
maybe_announce_capability
maybe_register_user
maybe_ship_order
```

This name tells you: this module contains business rules. It might produce an event, or it might reject the command. The "maybe" is honest in a way that most code isn't — a small defiance of the convention that every function name should promise certainty. It doesn't promise success. It says: "I'll look at the dossier and decide."

**Process managers** describe their trigger and action:

```
on_user_registered_send_welcome_email
on_division_identified_initiate_planning
on_planning_concluded_initiate_crafting
```

This is perhaps the most powerful naming pattern. A process manager named `on_user_registered_send_welcome_email` tells you everything: when a user registers, a welcome email is sent. The trigger (source event), the action (side effect), and the target — all in the name. I've worked on systems where understanding the integration flow required reading a 40-page wiki, or reverse-engineering a CORBA IDL file, or tracing SOAP message flows through an ESB. Here, you read the file names.

**Emitters** describe the event and destination:

```
capability_announced_to_mesh
capability_announced_to_pg
order_shipped_to_pg
```

The suffix tells you where the event goes: `_to_mesh` publishes to the peer-to-peer mesh network, `_to_pg` publishes to OTP process groups (internal pub/sub within the BEAM VM).

**Projections** describe the source event and target table:

```
user_registered_v1_to_users
order_shipped_v1_to_order_status
plugin_installed_v1_to_plugins
```

Source event, target read model. No ambiguity about what this projection does.

---

## Process Managers Scream Integration Points

One of the strongest arguments for screaming architecture comes from process managers. In a typical codebase, cross-domain integration points are buried inside handler code, invisible unless you read every file. In a screaming codebase, they're impossible to miss:

```
apps/guide_division_lifecycle/src/
├── initiate_division/                          ← desk (internal)
├── archive_division/                           ← desk (internal)
├── design_aggregate/                           ← desk (internal)
├── on_division_identified_initiate_division/   ← SCREAMS: reacts to external event!
```

That `on_` directory stands out. It's a process manager — it subscribes to an event from another domain (`division_identified_v1` from the venture lifecycle) and dispatches a command in this domain (`initiate_division_v1`). The directory name alone tells you exactly what crosses domain boundaries.

This pattern extends throughout Hecate's Martha plugin:

```
apps/orchestrate_agents/src/
├── initiate_visionary/
├── complete_visionary/
├── on_venture_initiated_initiate_visionary/     ← when venture starts, spawn visionary
├── on_vision_gate_passed_initiate_explorer/     ← when vision approved, spawn explorer
├── on_boundary_gate_passed_initiate_stormer/    ← when boundaries approved, spawn stormer
```

Reading these directory names, you can reconstruct the entire agent pipeline without opening a single file. Venture initiates, visionary runs, vision gate, explorer runs, boundary gate, stormer runs. The architecture IS the documentation.

I showed this to a product manager once. She read the folder names, paused, and said: "Oh, so when the vision gate passes, it automatically starts the explorer?" Yes. Exactly. In thirty-five years, that was the first time I'd seen a non-engineer read a source code directory listing and immediately understand the system's behavior. On every previous project — from COBOL JCL decks to Java EE deployment descriptors to Kubernetes manifests — the code structure was opaque to anyone who wasn't a developer. That moment was the proof that screaming architecture isn't just a developer convenience. It's a communication tool.

---

## The Forbidden Suffixes

Certain technical suffixes are banned because they carry no meaning:

```
*_handler     — "handles" what?
*_manager     — "manages" what?
*_processor   — "processes" what?
*_worker      — "works" on what?
*_service     — "serves" what?
*_helper      — "helps" with what?
*_util        — "utilizes" what?
*_impl        — implementation of what?
```

These suffixes are symptoms of thinking in technical layers. A "UserHandler" tells you there's a handler related to users. A "UserManager" tells you there's a manager related to users. Neither tells you what the code actually does. They're the naming equivalent of shrugging. (The average enterprise Java codebase has more `Manager` classes than actual managers, and roughly the same ratio of useful decision-making.)

Allowed suffixes are specific and meaningful:

```
*_v1              — version (commands, events)
*_desk_sup        — desk supervisor (process management)
*_to_mesh         — emitter to mesh network
*_to_pg           — emitter to process groups
*_to_{table}      — projection to specific table
*_store           — storage accessor
*_aggregate       — the dossier reader
```

Each of these tells you something concrete about the module's role in the system.

---

## The Architecture as Documentation

When names scream intent, several expensive activities become free:

**READMEs become optional.** A new developer can navigate the system by reading folder names. They don't need a prose description of what the system does — the structure tells them.

**Onboarding accelerates.** Instead of "read the wiki, then ask Sarah about the payment flow," it's "open the `receive_payment/` directory." We timed this once. Old system: average 3 days before a new hire could find and modify business logic confidently. New system: 2 hours. Same complexity, different organization. I've onboarded developers onto many systems over the decades. Nothing has ever come close to this.

**Code reviews gain context.** A pull request that changes files in `flag_dispute/` is clearly about the dispute-flagging process. The reviewer knows what to look for without reading the PR description.

**Refactoring becomes safer.** When everything related to capability announcement lives in `announce_capability/`, you can reason about the blast radius of any change. Nothing outside this directory should be affected.

**Deletability becomes trivial.** Want to remove the dispute system? `rm -rf flag_dispute/ resolve_dispute/`. Done. No orphaned code in a `services/` directory. No dangling references in a `handlers/` folder. The feature is the folder. I cannot overstate how liberating this is. Deleting code in most systems is terrifying because you can never be sure you've found all the pieces. I've been on teams that were afraid to delete dead code for years because nobody was confident they'd found all the tendrils. Here, the pieces are in one place. Delete the folder. Done.

---

## The Real Challenge

The hard part of screaming architecture isn't the naming conventions — those are mechanical. The hard part is resisting the gravitational pull of horizontal organization.

Every framework, every tutorial, every Stack Overflow answer teaches you to organize by technical concern. Controllers go in `controllers/`. Services go in `services/`. Models go in `models/`. It's the path of least resistance, and it's what your IDE scaffolds for you. Your tools are, with the best of intentions, actively helping you build an unmaintainable codebase. It's like a GPS that always routes you through the scenic overlook — pleasant at first, catastrophic when you're late for a deployment. This has been true since the first MVC frameworks in the nineties. The entire industry has been reinforcing this muscle memory for thirty-plus years.

The industry went one way. We went the other. Breaking out of this pattern requires constant vigilance — not for a week, but for months, until the new pattern becomes the default. After thirty-five years of building software, I can tell you that unlearning a deeply ingrained practice is harder than learning a new one. Every time I created a new file, my fingers wanted to type `handlers/`. The mental muscle memory of decades of layered architecture doesn't go away overnight. It took about three months of conscious effort before the new patterns became automatic. But they did become automatic, and now the old way feels as wrong as it should.

The reward is a codebase that explains itself. One where you can show a product manager the directory listing and they'll recognize their domain. Where six months from now, you won't need to grep through the codebase to find where disputes are handled — the answer will be screaming at you from the folder structure.

Let the code scream. Let the structure speak. Let the names tell the story.
