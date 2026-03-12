# Chapter 14: Plugin Architecture

*Extending without coupling*

---

I want to tell you about the first plugin that broke everything. But first, let me tell you about all the plugin systems that broke everything before it.

I've been living through plugin architecture failures since the early 90s. DLL hell on Windows — where installing one application's DLL would silently overwrite another application's version of the same DLL, and suddenly your spreadsheet program couldn't print. COM and ActiveX — where "just register the component" was a phrase spoken with a confidence that the registry would never betray you, which it always did. OSGi bundles in the Java world — a dependency resolution system so complex that debugging a bundle loading failure required a PhD in graph theory and a strong stomach. Eclipse plugins — where a misbehaving extension could freeze the entire IDE, and you'd spend an hour in `eclipse.ini` trying to figure out which one. WordPress plugins — where any of ten thousand community extensions could inject arbitrary PHP into your process space, and the phrase "works on my machine" took on theological significance.

Every generation of plugin system fails in one of two ways. Either the plugins aren't isolated enough (a bad plugin takes down the host), or the coupling surface is too wide (a host upgrade breaks every plugin). Usually both. A plugin system is an invitation for strangers to run code in your living room. The question isn't whether they'll break something — it's how creatively. I've watched this cycle repeat for thirty-five years.

So when our first Hecate plugin — a simple monitoring dashboard — broke everything, the failure was almost nostalgic. A few routes, a small event store, a handful of projections. It loaded fine. It ran fine. Then the platform upgraded Cowboy, and the plugin's route handlers — which had been importing an internal Cowboy module that we hadn't documented as part of the contract — exploded on startup. Every request to the plugin returned a 500. And because the plugin loaded in the same supervision tree as the platform's core services, the crash cascaded into the platform itself. The monitoring dashboard took down the thing it was supposed to monitor.

That was the week we redesigned the plugin architecture from scratch. Not because we'd never seen this before — quite the opposite. Because I'd seen it so many times that I knew exactly what we'd gotten wrong, and exactly what the fix had to look like.

The worst thing you can do to a platform is make it monolithic. The second worst thing is make it extensible in theory but coupled in practice — the kind of plugin system where writing a plugin means importing half the platform's internals, where a version bump in the host breaks every extension, where "extensible" really means "we exposed some internal APIs and wished people luck." That's COM. That's early Eclipse. That's what we'd built, and the monitoring dashboard proved it.

Hecate's plugin architecture — the one we have now, the one that works — avoids both failure modes. Plugins are genuinely isolated: separate OTP applications, separate event stores, separate static assets. They declare a behavior contract, the platform loads them, and the two communicate through well-defined channels. When a plugin misbehaves, it crashes in its own supervision tree. When the platform upgrades, the plugin contract stays stable.

The design philosophy is stolen from old-fashioned office architecture: a plugin is a tenant in a building. The building provides electricity, plumbing, and a mail slot. The tenant furnishes the space however they want. The building manager doesn't need to know what happens inside. (And critically, a fire in one office doesn't burn down the building.)

---

![Plugin Architecture](assets/plugin-architecture.svg)

## The Behaviour Contract

Every Hecate plugin implements the `hecate_plugin` behaviour. Five required callbacks, one optional:

```erlang
-callback init(Config :: map()) -> {ok, State :: term()} | {error, Reason :: term()}.
-callback routes() -> [cowboy_router:route_match()].
-callback store_config() -> #hecate_store_config{} | none.
-callback static_dir() -> file:filename_all() | none.
-callback manifest() -> map().

%% Optional
-callback flag_maps() -> #{atom() => [{integer(), binary()}]}.
```

That's the entire surface area. Five functions. We agonized over this number. Early versions of the contract had twelve callbacks — `on_startup`, `on_shutdown`, `health_check`, `dependencies`, `migrations`, `permissions`... The contract was comprehensive and nobody wanted to implement it. Every new callback was a reason not to write a plugin.

I've seen this exact mistake in every plugin system I've worked with. Eclipse's extension point schema required XML manifests so verbose that writing the manifest was harder than writing the plugin. COM required implementing `IUnknown` plus whatever interfaces your component needed, and getting the reference counting wrong meant memory leaks or crashes. The lesson, which took the industry decades to learn and which we nearly forgot, is that the contract should be as small as possible. We kept cutting until we hit the minimum viable contract: tell us who you are, what routes you want, where your files are, whether you need a store, and how to start you up. Everything else is your problem.

Let's look at each:

**`manifest/0`** returns a map describing the plugin — name, version, description, author, capabilities. This is metadata, not configuration. It tells the platform what it loaded:

```erlang
manifest() ->
    #{
        name        => <<"martha">>,
        version     => <<"0.3.1">>,
        description => <<"AI-assisted software development studio">>,
        author      => <<"Hecate Social">>,
        category    => <<"development">>,
        icon        => <<"brain">>
    }.
```

**`store_config/0`** tells the platform whether the plugin needs its own event store. Most plugins do — they have their own bounded contexts, their own aggregates, their own event streams. The plugin returns a store configuration record, and the platform creates a ReckonDB store on its behalf:

```erlang
store_config() ->
    #hecate_store_config{
        store_id    = martha_store,
        dir_name    = "martha",
        description = "Martha Studio event store",
        options     = #{
            snapshot_interval => 100
        }
    }.
```

Return `none` if your plugin is stateless or manages its own storage.

**`routes/0`** returns Cowboy route specifications. The platform mounts these under the plugin's namespace automatically — `/plugin/{name}/api/...` for API endpoints and `/plugin/{name}/ui/[...]` for the frontend:

```erlang
routes() ->
    [
        {"/api/ventures", app_marthad_ventures_handler, []},
        {"/api/ventures/:venture_id", app_marthad_venture_handler, []},
        {"/api/ventures/:venture_id/divisions", app_marthad_divisions_handler, []},
        {"/api/events/sse", app_marthad_sse_handler, []}
    ].
```

**`static_dir/0`** points to a directory containing the plugin's frontend assets. The platform serves these as static files. For Martha, this is a compiled SvelteKit application:

```erlang
static_dir() ->
    code:priv_dir(app_marthad) ++ "/static".
```

**`init/1`** is called after the store is created and routes are registered. The plugin receives a config map containing its name, store ID, and data directory. This is where the plugin starts its domain supervisors, boots its processes, and prepares for work:

```erlang
init(#{plugin_name := Name, store_id := StoreId, data_dir := DataDir}) ->
    ok = app_marthad_sup:start_link(StoreId),
    ok = app_marthad_event_bridge:start(StoreId),
    {ok, #{name => Name, store_id => StoreId}}.
```

The optional **`flag_maps/0`** callback exposes bit-flag definitions to the frontend. When Martha's UI needs to decode a status integer into human-readable labels, it calls the plugin's flag-maps endpoint rather than hardcoding the bit positions:

```erlang
flag_maps() ->
    #{
        venture_status => [
            {1,  <<"initiated">>},
            {2,  <<"archived">>},
            {4,  <<"open">>},
            {8,  <<"shelved">>},
            {16, <<"concluded">>}
        ],
        planning_status => [
            {1,  <<"initiated">>},
            {4,  <<"open">>},
            {16, <<"concluded">>}
        ]
    }.
```

---

## The 11-Step Loading Sequence

When Hecate starts, the plugin loader — a gen_server called `hecate_plugin_loader` — walks through a precise 11-step sequence for each plugin. The ordering matters. Each step depends on the previous one succeeding.

We didn't start with 11 steps. We started with 3: load code, call init, register routes. You can probably guess what happened. Plugins crashed during init because their store didn't exist yet. Routes registered before the handler modules were loaded. Static directories were missing because nobody created them. Each bug added a step. Eleven is the number you reach when you've run out of new categories of failure. (So far. I've been in this business long enough to know that "so far" is doing a lot of work in that sentence.)

If that sounds familiar, it should. Anyone who's deployed Java applications into an OSGi container knows the dance: every step you skip becomes a failure mode in production at 3 AM. Anyone who's written a WordPress plugin loader knows that the ordering between `plugins_loaded`, `init`, and `wp_loaded` matters more than the documentation suggests. The 11 steps aren't clever engineering — they're the scar tissue from every deployment failure, distilled into a sequence that doesn't fail anymore.

**Step 1: Create directories.** `hecate_plugin_paths:ensure_layout/1` creates the plugin's file structure under `~/.hecate/hecate-daemon/plugins/{name}/`:

```
plugins/martha/
├── ebin/              ← compiled BEAM files
├── priv/static/       ← frontend assets
├── manifest.json      ← plugin metadata
├── sqlite/            ← SQLite databases (if needed)
├── reckon-db/         ← ReckonDB event store data
└── run/               ← runtime files (sockets, PIDs)
```

**Step 2: Load code.** The loader adds the plugin's `ebin/` directory to the code path and loads each `.beam` file using `code:load_abs/1`. This is hot code loading — no restart required.

**Step 3: Verify callback module.** The loader confirms that the module named in the plugin manifest actually implements `hecate_plugin`. If it doesn't, loading fails immediately. No partial loads. (This step was added after a particularly creative bug where a plugin's manifest named a module that existed but implemented the wrong behaviour. The loader happily called `init/1` on a gen_server callback module. The error message was... memorable. It reminded me of a COM registration bug I chased in 1998, where a CLSID pointed to a DLL that exported the right function name but with the wrong calling convention.)

**Step 4: Read manifest.** Call `manifest/0` and store the result. This gives the platform the plugin's metadata for display in the UI and for API responses.

**Step 5: Create ReckonDB store.** If `store_config/0` returns a configuration (not `none`), the platform creates a new ReckonDB store. This is the plugin's own event store — completely separate from the daemon's built-in stores.

**Step 6: Call init/1.** Pass the plugin its configuration map. The plugin starts its supervisors, event bridges, and anything else it needs.

**Step 7: Collect API routes.** Call `routes/0` and prefix each route with `/plugin/{name}`.

**Step 8: Resolve static directory.** Call `static_dir/0` to find where the plugin's frontend assets live.

**Step 9: Start store subscription.** If the plugin has a store, start an `evoq_store_subscription` so projections and process managers can receive events.

**Step 10: Register in ETS.** Insert the plugin's metadata, routes, and status into the `hecate_loaded_plugins` ETS table. This is the platform's registry of running plugins.

**Step 11: Hot-swap Cowboy dispatch.** Rebuild the Cowboy router dispatch table to include the new plugin's routes and static file serving. This is a live update — existing connections are unaffected, new requests see the new routes.

The whole sequence is atomic in intent: if any step fails, previous steps are rolled back where possible, and the plugin is marked as failed. A broken plugin never takes down the platform. That was the whole point, remember? The monitoring dashboard incident. I'd been through DLL hell, COM registration nightmares, and OSGi classloader conflicts. I wasn't going to build another plugin system that could be brought down by a tenant. Never again.

---

## Route Auto-Mounting

One of the neatest tricks in the plugin architecture is how routes work. A plugin declares its routes relative to itself:

```erlang
routes() ->
    [{"/api/ventures", handler_module, []}].
```

The platform mounts this at `/plugin/martha/api/ventures`. The plugin author never thinks about path prefixes. The platform never needs to know what routes the plugin wants. Each side owns its own concern.

This seems obvious in retrospect, but our first version had plugins declaring their full paths: `/plugin/martha/api/ventures`. Plugin authors kept getting the prefix wrong, or forgetting it, or — my personal favorite — using `/api/ventures` and accidentally shadowing the platform's built-in routes. I'd seen this exact problem in Apache httpd with mod_rewrite rules, in IIS with virtual directories, in every web framework that lets extensions register arbitrary URL paths. Auto-mounting eliminated an entire class of bugs by making the right thing the only thing.

But there's more. Every plugin automatically gets two built-in routes, injected by the platform:

```
GET /plugin/{name}/api/manifest     ← returns manifest/0
GET /plugin/{name}/api/flag-maps    ← returns flag_maps/0
```

These are free. The plugin doesn't declare them. The platform adds them because the frontend needs them — the UI reads the manifest to display the plugin's name and icon, and reads flag-maps to decode status integers.

Static assets follow the same pattern. If `static_dir/0` returns a path, everything under that directory is served at `/plugin/{name}/ui/[...]`. A plugin's frontend is always available at a predictable URL.

---

## Plugin Lifecycle as Event Sourcing

Plugins themselves are event-sourced. Installing, activating, upgrading, and removing a plugin — these are all commands that produce events. The plugin's lifecycle is a dossier:

```
Plugin Dossier: plugin-martha
  [slip] plugin_installed_v1       — version, source, checksum
  [slip] plugin_activated_v1       — enabled for use
  [slip] plugin_loaded_confirmed_v1 — running in VM
  [slip] plugin_upgraded_v1        — new version, migration status
  [slip] plugin_deactivated_v1     — disabled, still installed
  [slip] plugin_removed_v1         — uninstalled
```

The in-VM lifecycle commands include: `install`, `upgrade`, `remove`, `extract`, `activate`, `deactivate`, `confirm_loaded`, and `confirm_unloaded`. Each produces a corresponding event. The aggregate tracks the plugin's status using bit flags:

```erlang
-define(PLG_INSTALLED,   1).
-define(PLG_REMOVED,     2).
-define(PLG_RUNNING,     4).
-define(PLG_STOPPED,     8).
-define(PLG_ACTIVATED,  16).
-define(PLG_DEACTIVATED,32).
```

This means the platform knows the complete history of every plugin. When did Martha get installed? What version was it before the upgrade? Was it ever deactivated? The event stream answers all of these. No more spelunking through log files trying to reconstruct what happened at 2 AM when someone upgraded a plugin and everything went sideways. I've spent more nights than I'd like to remember doing exactly that — grepping through `/var/log` trying to figure out which deployment step changed what, in what order. The event stream makes that archaeology unnecessary.

For container-model plugins — plugins that run as separate OCI containers rather than in the BEAM VM — the lifecycle includes additional commands: `start_execution`, `stop_execution`, `confirm_up`, `confirm_down`, `start_oci_pull`, `cancel_oci_pull`, `complete_oci_pull`. The container lifecycle is richer because container operations are asynchronous and can fail in more ways. (Pulling a container image over a flaky network connection is, let's say, a character-building experience. Though not as character-building as pulling a 200MB WAR file over a VPN to a remote data center in 2005.)

---

## Store Bootstrapping

There's a subtle ordering problem in the platform that consumed more whiteboard space than I care to admit. The daemon has 10 built-in stores — for settings, LLM models, licenses, plugins, launcher, realm memberships, and more. Plugins create additional stores. Domain supervisors depend on stores existing. Store subscriptions depend on domain supervisors running.

If you wire this up wrong, you get race conditions. A projection tries to subscribe to a store that hasn't started yet. A domain supervisor tries to query a read model that no projection has built yet. Everything starts concurrently, and everything fails concurrently.

Anyone who's managed Spring application contexts with circular bean dependencies, or debugged OSGi service tracker timeouts, or wrestled with systemd unit ordering, knows this problem intimately. The answer is always the same: explicit phases.

Hecate solves this with a three-phase boot:

**Phase 1: Start all built-in stores in parallel.** The 10 built-in ReckonDB stores are started concurrently. They have no dependencies on each other. Each store opens its data directory, loads its event streams, and becomes ready.

**Phase 2: Start domain supervisors.** Once stores are available, each domain supervisor starts. These supervisors manage the aggregates, projections, and process managers for their bounded context.

**Phase 3: Start store subscriptions.** Finally, the store subscriptions are started. These connect projections and process managers to the event streams, replaying existing events and then switching to live processing.

Plugin stores are created during the plugin loading sequence (Step 5), which happens after Phase 3. This means plugins start after the platform is fully booted. Their stores are "on-demand" — they exist only when the plugin is loaded.

```erlang
%% hecate_app.erl — Phase 1
Stores = [
    settings_store, llm_store, licenses_store, plugins_store,
    launcher_store, realm_memberships_store, %% ... and more
],
ok = lists:foreach(fun(S) -> hecate_stores:start(S) end, Stores),

%% Phase 2
ok = hecate_domain_sup:start_link(),

%% Phase 3
ok = hecate_subscriptions:start_all(),

%% Later — plugin loading creates plugin stores on demand
ok = hecate_plugin_loader:load_all().
```

Three phases. Sequential where it matters, parallel where it's safe. It's not clever. It's just correct. And "correct" took us three iterations to reach — the first two had race conditions that only manifested under load, which is exactly as fun to debug as it sounds. Race conditions are nature's way of reminding you that concurrency is not parallelism, and you understand neither. (The third time, I drew the dependency graph on paper before writing code. Sometimes the old ways are the best ways.)

---

## The Frontend Contract

Hecate's web frontend (a Tauri application running SvelteKit) hosts plugins through custom elements. Each plugin's frontend is compiled as a web component and loaded into the host application:

```html
<martha-studio shadow="none"></martha-studio>
```

The `shadow="none"` is deliberate — plugins render in the host's DOM, sharing styles and inheriting the theme. Shadow DOM would isolate them visually, breaking the unified look and feel. We tried Shadow DOM first. The plugin looked like it was wearing a different outfit to the same party. Colors didn't match, fonts were wrong, spacing was off. It reminded me of the early days of Java applets embedded in web pages — technically present, visually alien. Turning off the shadow and letting plugins inherit the host's CSS was the right call — it means plugin authors get theming for free, and users get a consistent experience.

The plugin's frontend communicates with its backend through its auto-mounted API routes. Martha's SvelteKit app makes requests to `/plugin/martha/api/ventures`, which the platform routes to `app_marthad_ventures_handler`. The frontend never talks to the platform directly — only to its own plugin backend.

This creates a clean separation:

```
hecate-web (Tauri + SvelteKit)
    │
    ├── Built-in routes: /appstore, /llm, /settings
    │
    └── Plugin host: /plugin/:name
         │
         └── <martha-studio> custom element
              │
              └── Calls /plugin/martha/api/*
                   │
                   └── Handled by app_marthad (Erlang plugin)
```

The platform is the landlord. The plugin is the tenant. The building provides the infrastructure. The tenant provides the experience.

---

## Martha as Case Study

Martha — the AI-assisted development studio — is the reference plugin. It's also the plugin that stress-tested every assumption we had about plugin isolation. (Building your flagship product as a plugin is a great way to discover the holes in your plugin system. Painful, but great. It's the "eat your own dog food" principle, and in thirty-five years of building software, I've never seen a team regret doing it.)

Martha consists of two repositories:

**`hecate-app-marthad`** is the Erlang backend. It's an OTP umbrella application with its own CMD, PRJ, and QRY departments. It implements `hecate_plugin`, defines its own aggregates (venture lifecycle, division planning, division crafting), runs its own projections, and manages its own event bridge for real-time updates.

**`hecate-app-marthaw`** is the SvelteKit frontend. It compiles to a web component that gets copied into the daemon's static directory. It communicates exclusively through the plugin's API routes.

Martha's `init/1` starts three things: its domain supervisor (which manages the venture lifecycle aggregates), its event bridge (which subscribes to the plugin's event store and broadcasts to connected SSE clients), and its projection system (which builds read models from events).

The platform knows nothing about ventures, divisions, or AI agents. It knows that a plugin called "martha" is installed, running, and serving routes at `/plugin/martha/`. Everything else is Martha's business.

This is the plugin architecture's core promise: **the platform provides isolation and infrastructure; the plugin provides the domain.** The two never need to know about each other's internals. The behavior contract is the only coupling point. Change the plugin's implementation freely — as long as the five callbacks still work, the platform doesn't care.

Extend without coupling. Furnish your space however you want. The building stays standing. Even when the monitoring dashboard catches fire. After thirty-five years of watching plugin systems fail — from DLLs to COM to OSGi to Eclipse to VS Code extensions — I can tell you that the plugin systems that survive are the ones with the smallest contract and the strongest isolation. Everything else is a variation on DLL hell with better marketing. DLL hell wasn't hell because of the DLLs. It was hell because of the humans who shipped them. The technology changes; the humans don't.
