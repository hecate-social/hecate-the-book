# Chapter 8: Bit Flags and Status Machines

*Compact state for event-sourced systems*

---

I want to tell you about the worst aggregate I ever wrote. It had a `status` field that was an atom. Started simple: `placed`, `paid`, `shipped`. Three states, three atoms, clean pattern matching. Then the product team asked: "Can an order be paid but partially shipped?" And: "Can we put an order on hold while it's being shipped?" And: "Can an order be disputed even after delivery?"

Within two months, the status field was a list of atoms: `[paid, partially_shipped, on_hold, under_dispute]`. The pattern matching was a nightmare. Every `execute/2` function started with a paragraph of list membership checks. The serialization was a JSON array of strings. The ETS queries were full table scans because you can't index into a list. The code compiled. The tests passed (barely). And every time someone asked "what are the possible states of an order?" I had to stare at the code for ten minutes before answering.

The solution had been in my muscle memory since the early '90s. I'd just forgotten to use it. While the rest of the industry was reaching forward for newer abstractions, the answer was behind us the whole time.

C programmers have been using bit flags since before most of today's developers were born. I was using them in 1992, writing system utilities on Unix. Every C programmer of that era knew `O_RDONLY | O_CREAT | O_TRUNC` by heart. Unix file permissions are bit flags — `rwxr-xr-x` is just a visual representation of the integer 755, which is `111 101 101` in binary. TCP flags — SYN, ACK, FIN, RST — are bits in a byte. The Win32 API was riddled with them: `WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU` for window styles, `FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_READONLY` for file attributes. This was not esoteric knowledge. It was Tuesday.

Then the industry moved to high-level languages — Java, Python, Ruby, JavaScript — and bit manipulation fell out of the collective vocabulary. Not because it stopped being useful, but because nobody was teaching it anymore. An entire generation of programmers learned to model state with enums, strings, and boolean maps, never knowing there was a technique that was faster, more compact, and more expressive sitting right there at the hardware level. It's as if the entire industry collectively forgot how to drive a manual transmission — the automatic is fine for most people, but when you need to downshift on a mountain pass, you really wish someone had taught you.

A bit flag is an integer pretending to be a committee. Each bit has an opinion. The integer summarizes. Democracy in binary. Bit flags solve the aggregate status problem with one integer.

---

## The Idea

A bit flag assigns each possible status to a unique bit position — a power of 2:

```erlang
-define(INITIATED,   1).   %% 2^0 = bit 0
-define(ARCHIVED,    2).   %% 2^1 = bit 1
-define(OPEN,        4).   %% 2^2 = bit 2
-define(SHELVED,     8).   %% 2^3 = bit 3
-define(CONCLUDED,  16).   %% 2^4 = bit 4
```

The aggregate's status field is a single integer. To mark a venture as both INITIATED and OPEN, you set both bits:

```
INITIATED (1) = 00001
OPEN      (4) = 00100
Combined  (5) = 00101
```

The integer `5` means "initiated and open." The integer `3` means "initiated and archived." The integer `0` means "no status set." One number encodes an arbitrary combination of flags.

This is not a novel technique. It is one of the oldest patterns in computing because it maps directly to how hardware works. CPUs have used flag registers since the beginning. If you've ever read an Intel architecture manual, the FLAGS register is a tour of bit-flag design. What I'm doing here isn't inventing anything — it's bringing back a technique that the industry forgot when it moved away from systems programming. Applying it systematically to event-sourced aggregates, where status changes are driven by events and business rules are expressed as flag combinations, turns out to be a remarkably good fit. The moment we started using bit flags in our aggregates, the code got simpler, the queries got faster, and that nagging feeling of "there must be a better way" finally went away.

---

## The evoq_bit_flags Module

Evoq provides a complete bit flag library. The API is small and unsurprising — which is exactly what you want from something you'll call hundreds of times:

```erlang
%% Setting and clearing flags
Status1 = evoq_bit_flags:set(0, ?INITIATED),           %% 1
Status2 = evoq_bit_flags:set(Status1, ?OPEN),           %% 5
Status3 = evoq_bit_flags:unset(Status2, ?OPEN),         %% 1

%% Bulk operations
Status4 = evoq_bit_flags:set_all(0, [?INITIATED, ?OPEN]),  %% 5
Status5 = evoq_bit_flags:unset_all(Status4, [?INITIATED, ?OPEN]),  %% 0

%% Querying
true  = evoq_bit_flags:has(5, ?INITIATED),
true  = evoq_bit_flags:has(5, ?OPEN),
false = evoq_bit_flags:has(5, ?ARCHIVED),
true  = evoq_bit_flags:has_not(5, ?ARCHIVED),

%% Combination queries
true  = evoq_bit_flags:has_all(5, [?INITIATED, ?OPEN]),
false = evoq_bit_flags:has_all(5, [?INITIATED, ?ARCHIVED]),
true  = evoq_bit_flags:has_any(5, [?OPEN, ?SHELVED]),
```

Under the hood, these are bitwise operations. `set` is `bor` (bitwise OR). `unset` is `band` with `bnot` (bitwise AND with complement). `has` is `band` followed by a comparison. They compile to single CPU instructions. There is no data structure faster than this. I'm not exaggerating — you literally cannot beat a CPU instruction. I've known this since writing bit-twiddling routines in C in the early '90s. When someone on the team suggested we use a map of booleans instead "for readability," I benchmarked both. The bit flags version was 47x faster. Forty-seven times. For something called on every command and every event in every aggregate. "But it's more readable!" Yes, and a horse-drawn carriage is more scenic than a car. Some lessons from systems programming are worth carrying forward, even into high-level languages.

---

## Flags in Aggregates

Here's where bit flags become powerful: applying events to update status. Watch how clean this is compared to the list-of-atoms horror show:

```erlang
-module(venture_aggregate).

-define(INITIATED,   1).
-define(ARCHIVED,    2).
-define(OPEN,        4).
-define(SHELVED,     8).
-define(CONCLUDED,  16).

init(_Id) ->
    #{status => 0, name => undefined}.

%% Initiating sets the INITIATED flag
apply(#{status := S} = State, #{event_type := <<"VentureInitiated.v1">>, data := D}) ->
    State#{
        status => evoq_bit_flags:set(S, ?INITIATED),
        name => maps:get(<<"name">>, D)
    };

%% Opening sets OPEN, clears SHELVED
apply(#{status := S} = State, #{event_type := <<"VentureOpened.v1">>}) ->
    State#{
        status => evoq_bit_flags:set(
            evoq_bit_flags:unset(S, ?SHELVED),
            ?OPEN
        )
    };

%% Shelving sets SHELVED, clears OPEN
apply(#{status := S} = State, #{event_type := <<"VentureShelved.v1">>}) ->
    State#{
        status => evoq_bit_flags:set(
            evoq_bit_flags:unset(S, ?OPEN),
            ?SHELVED
        )
    };

%% Archiving sets ARCHIVED
apply(#{status := S} = State, #{event_type := <<"VentureArchived.v1">>}) ->
    State#{status => evoq_bit_flags:set(S, ?ARCHIVED)}.
```

Each event modifies specific bits. Opening a venture doesn't need to know or care about the INITIATED or ARCHIVED bits — it only touches OPEN and SHELVED. This is composition. Flags are independent dimensions of state that can be manipulated independently. Each event handler is responsible for exactly its own bits and nothing else. No "and also update the status to reflect the new combined state" logic. Just flip the relevant bits and move on. It's the same principle that made Unix permissions elegant forty years ago — each bit is orthogonal, each operation is local.

---

## Business Rules as Flag Checks

The `execute/2` function uses flags to enforce business rules, and this is where the payoff really hits:

```erlang
%% Can only open a venture that's been initiated and isn't archived
execute(#{status := S}, #{command_type := <<"OpenVenture.v1">>}) ->
    case evoq_bit_flags:has(S, ?INITIATED) andalso
         evoq_bit_flags:has_not(S, ?ARCHIVED) of
        true  -> {ok, [venture_opened_v1:new()]};
        false -> {error, cannot_open}
    end;

%% Can only shelve an open venture
execute(#{status := S}, #{command_type := <<"ShelveVenture.v1">>} = Cmd) ->
    case evoq_bit_flags:has(S, ?OPEN) of
        true  -> {ok, [venture_shelved_v1:new(Cmd)]};
        false -> {error, not_open}
    end;

%% Can only archive if not already archived
execute(#{status := S}, #{command_type := <<"ArchiveVenture.v1">>}) ->
    case evoq_bit_flags:has_not(S, ?ARCHIVED) of
        true  -> {ok, [venture_archived_v1:new()]};
        false -> {error, already_archived}
    end.
```

The business rules read like English: "has INITIATED and has not ARCHIVED." There's no state machine transition table to maintain, no enum comparisons, no list membership checks. Just bit queries. When I show this to developers who've been maintaining state machine libraries with 200-line transition tables, I can see the moment it clicks. Their eyes go wide. "Wait, that's it?" The same reaction I had the first time I saw `chmod` explained in binary, back in 1991.

And because each check is independent, you can express complex preconditions without nested conditionals:

```erlang
%% Can submit discovery findings only if:
%% - venture is initiated
%% - venture is open
%% - not shelved
%% - not concluded
can_submit_discovery(#{status := S}) ->
    evoq_bit_flags:has_all(S, [?INITIATED, ?OPEN]) andalso
    evoq_bit_flags:has_not(S, ?SHELVED) andalso
    evoq_bit_flags:has_not(S, ?CONCLUDED).
```

Four conditions, one expression, no nesting. Compare that to the equivalent with atoms or lists. I'll wait. (Actually, don't — I've seen the equivalent, and it was a twelve-line `case` expression with three levels of nesting.)

---

## Multi-Level Status

Hecate's venture lifecycle has status at multiple levels. A venture has its own status. Each division within the venture has its own status. Each phase of a division (planning, crafting, testing) has its own status.

Each level gets its own integer:

```erlang
%% Venture-level status
#{
    venture_status => 5    %% INITIATED | OPEN
}

%% Division-level status (within the venture)
#{
    division_status => 7   %% INITIATED | OPEN | PLANNING
}

%% Phase-level status (within a division)
#{
    planning_status => 13  %% INITIATED | OPEN | IN_PROGRESS
}
```

The flags at each level are independent. A venture can be OPEN while one of its divisions is SHELVED. A division can be in PLANNING while another is in CRAFTING. The integers don't interfere because they're stored in separate fields.

This is a natural fit for the event-sourced model. Each level has its own aggregate, its own event stream, its own dossier. The venture aggregate tracks venture-level status. The planning aggregate tracks planning-level status. They don't share state — they share events through process managers. The bit flags at each level are their own little universe, oblivious to what's happening above or below. No "check the parent's status before updating the child's status" logic leaking between aggregates.

---

## Debugging: decompose and to_string

A raw integer like `37` is opaque. I'll admit that. After thirty-five years of reading hex dumps and binary flag registers, I can do the mental arithmetic faster than most — but I still don't want to at 11 PM. What flags does `37` represent? The `decompose` function breaks it down:

```erlang
evoq_bit_flags:decompose(37).
%% [1, 4, 32]
%% That's ?INITIATED, ?OPEN, and whatever flag 32 is
```

For human-readable output, `to_string` maps flags to names:

```erlang
FlagMap = #{
    1  => <<"INITIATED">>,
    2  => <<"ARCHIVED">>,
    4  => <<"OPEN">>,
    8  => <<"SHELVED">>,
    16 => <<"CONCLUDED">>
},

evoq_bit_flags:to_string(5, FlagMap).
%% <<"INITIATED|OPEN">>

evoq_bit_flags:to_string(10, FlagMap).
%% <<"ARCHIVED|SHELVED">>
```

This is invaluable in logs, API responses, and debugging sessions. The integer `5` is stored and transmitted — compact, fast, unambiguous. The string `"INITIATED|OPEN"` is displayed to humans. Both representations are derived from the same source of truth. We added `to_string` to every API response that includes a status field, and the support burden dropped noticeably. Instead of "the status is 37, what does that mean?" we get "the status is INITIATED|OPEN|CUSTOM_FLAG" and the conversation can move forward. It's the same principle behind C#'s `[Flags]` enum attribute and Java's `EnumSet` — the pipe-delimited string representation is a convention as old as the technique itself.

---

## Why Not Enums?

Erlang has atoms. They're interned strings. Why not use them? I hear this question a lot, usually from developers who haven't hit the wall yet. Let me save you the trip — I hit it in the '90s with C enums and again in the 2000s with Java enums, and the wall hasn't moved.

**Atoms can't compose.** An order that is `paid` and `shipped` needs to be `{paid, shipped}` or `[paid, shipped]` or a map `#{paid => true, shipped => true}`. Each representation requires its own matching logic. Bit flags compose with arithmetic — `paid bor shipped` — and decompose with arithmetic too.

**Atoms don't serialize efficiently.** Sending `[initiated, open, not_shelved, not_archived]` over the wire requires a list of variable-length strings. Sending `5` requires one integer. Over a mesh with thousands of status updates per second, this matters. We measured: the atom-list serialization was 23 bytes. The integer was 1 byte. Multiply by a few thousand messages per second and it adds up.

**Atoms can't be queried with math.** In a SQL or ETS read model, finding all ventures that are OPEN and not ARCHIVED requires one expression:

```sql
SELECT * FROM ventures WHERE status & 4 = 4 AND status & 2 = 0
```

```erlang
%% ETS match spec
ets:select(ventures, [
    {{'$1', '$2'},
     [{'andalso',
       {'=:=', {'band', '$2', 4}, 4},
       {'=:=', {'band', '$2', 2}, 0}}],
     ['$1']}
]).
```

Try doing that with a list of atoms. You'd need to iterate every record and check list membership. Bit flags push the filtering into the storage engine. The ETS match spec above runs at native speed inside the BEAM's ETS implementation. A list-membership check runs in your Erlang code, one record at a time. The performance difference is not subtle.

**Atoms can exhaust the atom table.** The BEAM has a finite atom table (1,048,576 atoms by default). Creating atoms dynamically from user input is a denial-of-service vector. Integers are infinite and harmless. Nobody has ever crashed a production system by having too many integers. (The atom table, on the other hand, has ended more careers than bad stock picks.)

---

## The Pattern

Bit flags follow a repeating pattern across every aggregate in the stack:

1. **Define flags as powers of 2** in header files or macros
2. **Start status at 0** in `init/1`
3. **Set and clear flags in `apply/2`** when events arrive
4. **Check flags in `execute/2`** before allowing commands
5. **Store as a plain integer** in the event store and read models
6. **Decompose for display** in API responses and logs

This pattern is mechanical. Once you've seen it in one aggregate, you can read every aggregate in the system. The business rules change. The flag names change. The pattern doesn't. There's something deeply comforting about that — the same comfort I get from well-established C conventions, from Unix's consistent use of file descriptors, from the BEAM's consistent use of supervision trees. A new team member can look at any aggregate in the system and immediately understand how status works, because it's always the same six steps. No surprises. No "this aggregate does status differently because historical reasons." Just the pattern.

---

## Flags Are Not a State Machine

It's tempting to think of bit flags as implementing a state machine. They don't — at least not in the formal sense. And this distinction matters more than you might think.

A state machine has explicit transitions: from state A, event X leads to state B. The set of valid transitions is defined, and anything outside that set is an error.

Bit flags are more flexible. A venture with `INITIATED | OPEN` (5) can receive an event that sets `SHELVED` and clears `OPEN`, producing `INITIATED | SHELVED` (9). But there's no transition table that says "5 + shelve = 9." The transitions are implicit in the `apply` and `execute` functions.

This flexibility is intentional. Real business processes don't follow clean state machines. I know — I tried. More than once, across multiple decades. We started with a formal state machine for the venture lifecycle. It had twelve states and forty-seven transitions, and it still couldn't express "the venture is open but one of its divisions is shelved while another is being archived." The same combinatorial explosion I'd seen in every state machine I'd built since the '90s — telecommunications call processing, order management workflows, insurance claim lifecycles. An order can be paid and disputed simultaneously. A division can be in planning and have one of its sub-phases shelved. A venture can be open, have three active divisions, and be in the process of archiving a fourth.

Bit flags let you model this naturally. Each flag is an independent fact about the aggregate. The combination of flags is the aggregate's status. Business rules query flags to decide what's allowed. Events modify flags to record what happened.

If you need a strict state machine — exactly one state at a time, explicit transitions, no combinations — bit flags are overkill. Use an atom. But in event-sourced systems with complex lifecycle processes, the "multiple simultaneous facts" model is almost always what you need. We haven't used a single atom for status in over a year. Every aggregate uses bit flags. Not because we mandated it, but because every time someone tried atoms, they hit the composition wall within a week and switched.

---

## The Compact Truth

Bit flags are a small idea with outsized impact. One integer replaces a collection of booleans, a list of atoms, or a nested state machine. It composes with bitwise operators, queries with arithmetic, serializes as a single number, and reads as a pipe-delimited string.

In an event-sourced system where status changes with every event, where business rules gate every command, and where aggregate state must be compact enough to snapshot and replay efficiently, bit flags are the natural representation.

They're not glamorous. They're not novel. They're the kind of technique that C programmers used routinely in the '80s and '90s, that Unix internals have relied on since the beginning, that TCP headers have carried since 1981 — applied to a domain where most practitioners reach for heavyweight alternatives because nobody taught them the old ways. Sometimes the road less taken is the one your predecessors already paved. The first time you refactor a twenty-line state management function into a single `has_all` check, you'll feel what I felt: relief, followed by mild irritation that the industry forgot this technique in the first place.

One integer. All the state you need.
