# Working on Elusion RPG

Read this before changing anything. Everything in it cost real hours to learn,
most of it twice.

Elusion RPG is a top-down 2.5D action RPG in Godot 4.6 / GDScript, backed by a
Flask service that lives in a separate repository (`game/api`). The server owns
level, XP, the derived stat maxima, every loot roll and the loot bags
themselves. The client owns HP, mana, stamina, gold, the backpack, the bank and
the skill table — see `docs/apicontract.md` for exactly which is which.

## How to work in here

**Re-read a file immediately before you edit it.** Not at the start of the
session — immediately before. Working from a copy read twenty minutes ago has
silently reverted finished work in this project more than once, and two of those
three reverts produced no error at all, just quietly missing fixes.

**If you are an agent working through a copy of this repo, re-fetch before you
write to a file — and before you conclude anything about one.** This is the same
rule and it is the single most expensive mistake available in this project, so it
gets its own paragraph.

**Reading counts.** The write half of this rule is easy to follow because a
write feels consequential. The read half is where it actually goes wrong: you
grep a copy pulled forty minutes ago, find something alarming, and report a bug
that was fixed before you looked. That has now happened twice in one session —
a licence file claiming ownership it had not claimed for weeks, and four scripts
"stranded" on a vocabulary they had already been migrated off. Both were
confident, both were specific, both were wrong, and a wrong bug report costs the
same attention as a real one.

A stale read is more dangerous than a stale write, because a stale write gets
caught by the modification-time guard and a stale read gets caught by nothing.
If you are about to tell someone their code is broken, re-fetch the file first
and read the current bytes. Every time.

Diff the *content*, not the byte count. A size comparison catches most drift and
quietly misses the rest: moving a `scale` line from one node to another and
editing a radius from `1.0` to `0.8` changed four scene files without changing
their length at all. Sizes are a cheap smoke test, not the check.

A copy pulled at the start of a session is a photograph, not a window. It goes
stale the moment anything is written — including by you, earlier in the same
session. Three separate near-misses in one afternoon: a 19,957-byte copy of
`fishingspot.gd` that would have deleted `_notify()` and four call sites, and
twice a copy from before an edit that had already landed. Every one was caught
by comparing byte counts, and byte counts are cheap.

The rule, in order:

0. Re-fetch before you draw a conclusion from a file, not only before you edit
   it. "I already read this" is not a reason to skip it; it is the reason to do
   it.
1. Re-fetch the file right before you edit it.
2. Diff it against whatever you were about to write. Every difference should be
   a change you recognise as yours. One you do not recognise is the user's work
   and you are about to destroy it.
3. Write back with the modification time you just fetched, so the write is
   refused rather than silently winning if the file moved underneath you.
4. If a write is refused for that reason, re-fetch and redo the edit. Never
   force it.

The failure mode is not an error message. It is a file that looks fine and is
quietly missing an afternoon's work.

**The API has a test suite. Run it before and after.** The API is a separate
repository — run this from *its* folder, not from this one:

```
.\venv\Scripts\python.exe test_api.py
```

506 checks at the time of writing, exits non-zero on any failure. It uses a throwaway database in your
temp folder and never touches `elusion.db`.

No relative path is given on purpose. The two repositories are separate
checkouts and where they sit next to each other is up to whoever cloned them —
the first draft of this file guessed at `..\game\api` and sent the first person
who read it to a folder that does not exist.

**The game has a test suite too. Run it from this folder:**

```
.\run_tests.ps1
```

It finds the Godot binary itself, waits for it to actually exit, and writes the
full transcript to `test_results.txt` as well as printing it - because on
Windows neither the editor's Output panel nor the terminal could be relied on to
show the results, for three different reasons in one afternoon.

Same shape as `test_api.py` on purpose — a line per check, non-zero exit on any
failure. 826 checks at the time of writing; if that number and the one the suite
prints disagree, this file is the stale one — trust the suite. It covers what can
be checked without playing: that every script under `src/` compiles, the XP
curve, the shared constants and class stat curves, `ItemStack`'s save round trip,
and the rank ordering.

**Most of it checks agreement, not correctness.** `.tres` files,
`GameConstants` and `baseenemy.gd`'s drop constants are the source of truth;
`data/gamedata.json` is the copy Flask reads — and Flask is what actually rolls
the loot, so a pet rate edited without re-running the exporter means the server
pays out the old odds on a 1-in-1296 event nobody could notice by playing. Edit one, forget to re-run `src/tools/exportgamedata.gd`, and the two
sides quietly disagree about your max HP or the price of a revive — the suite
exists to make that loud. Add a check here whenever you add a number both sides
need.

**It covers one thing that needs the scene tree**, and only one:
`PetController.despawn_all()`, which needs a tree and nothing else. The suite
builds a fake pet and a fake container, both in the `pets` group, and asserts
the pet is freed and the container is not.

**It deliberately does not cover** anything needing a player in a world, a
physics frame or a rendered scene — movement, collision, the enemy shove, the
loot bag UI. Those are still verified by booting the game and reading the log.
The boot prints are tagged `[BOOT]`, `[CHAR]`, `[HUD]`, `[WORLD]`, `[KILL]`,
`[LOOT]`, `[PET]`, `[PLR]`, `[DEATH]` so the console is greppable. Start Flask
first or the login screen will tell you it cannot reach the server.

**Kill the old Flask process before starting a new one.** Windows will let a
second process bind port 5000 without complaining. The symptom is a 404 on a
route that plainly exists in the file you are looking at, because the process
actually answering is running last week's code.

## Before you trust a check

Every check in `testrunner.gd` is here because something went wrong once. But
several of the checks *themselves* were wrong first, in ways that all looked like
passing. This is the short version; each has its own section below.

**A check you have not watched go red is not a check.** Sabotage it, see it fail
by name, put it back. Every check added in this project has been through that,
and it caught three that would otherwise have shipped green and blind.

Five ways one of these looked right and was not:

1. **`load(path) != null` does not prove a script compiles.** Godot returns a
   non-null `Script` for a file that will not parse, even with
   `CACHE_MODE_IGNORE`. The first compile check passed on a project that did not
   build. `can_instantiate()` is the probe that moves.
2. **An empty directory exists for you and for nobody who clones.** Git cannot
   represent one, so a check that counts directories fails locally and passes in
   CI on the same commit — the failure mode that teaches people to ignore a
   suite.
3. **A filename is not a file.** Two folders can hold the same name, so a text
   search finds the copy that is used and clears the copy that is not. Found
   exactly that: two byte-identical pairs.
4. **Definitions are not usages.** Tile *definitions* in an atlas say which
   rectangles are carved into tiles, not whether any is placed. Counting them
   overstated a texture's use and nearly cost a file that 112 cells depend on.
5. **A true measurement under the wrong heading is bad advice.** A reachability
   report listed ~200 files of purchased art as "safe to delete". Every line was
   true. The heading made it wrong, and nothing in the output would have made you
   doubt it.

The common thread: the measurement was almost always right and the *frame* around
it was wrong. When a check tells you something surprising about your own project,
your knowledge of the project is evidence too — twice here it was right and the
tool was not.

## Traps

### JSON has no integer type

Godot parses every JSON number as a float. `88` on the wire arrives as `88.0`,
Godot's comparisons are type-strict, so `88.0 != 88` and a Dictionary keyed on
one will not match the other.

This caused a save-rewrite loop that cost a full day: the sanitiser cast to
`int`, compared against the parsed float, decided all 112 fields had changed and
rewrote the save on every single load. Every integer crossing the wire goes
through a coercion — `ServerStorage._int()`, `Combat._int()`. There is no safe
shortcut.

### A freed object fails before your guard runs

GDScript checks argument types at the **call boundary**, not inside the
function. So this does not work:

```gdscript
func _notify(who: Node) -> void:
    if is_instance_valid(who):   # never reached
        ...
```

A freed object passed to a typed `Node` parameter errors before the body starts.
`null` is legal for a typed `Node`; a freed object is not. Collapse the
reference at the caller, once, after every `await`:

```gdscript
var target: Node = killer if is_instance_valid(killer) else null
```

This bites hardest after a network call, because a failed request waits out the
full timeout and several seconds is long enough to die, teleport, or return to
character select.

### Never await on something about to be freed

Godot silently drops a coroutine whose object has been freed. An `await` in
`_die()` — with `queue_free()` two lines below — resolves only if the node
happens to survive long enough, which is a coin flip that looks like a bug.

This is why `combat.gd` is an autoload rather than code inside `BaseEnemy`. An
autoload is always in the tree and can wait as long as the network takes. The
same trap ate every small poison slime's loot bag once already, because smalls
await their death animation and larges do not.

Measured on 4.6.1 rather than assumed, for a node suspended on
`await get_tree().create_timer(...).timeout`:

| what happens during the await | resumes? | `is_instance_valid(self)` | `is_inside_tree()` |
|---|---|---|---|
| `queue_free()`, or `change_scene_*` replaces its scene | **no — dropped silently** | not reached | not reached |
| `remove_child()`, not freed | yes | `true` | **`false`** |
| reparented, still in the tree | yes | `true` | `true` |

Two things follow, and the second one is the trap inside the trap:

- There is no error message. A dropped coroutine and a successful one look
  identical in the log, which is why the slime bug lived for months.
- In the standard guard `if not is_instance_valid(self) or not is_inside_tree()`
  the **validity half can never fire** — if `self` were freed, the line would
  not be running. The `is_inside_tree()` half is the whole guard. Keep both
  (the check is free and states the intent) but do not let the first one talk
  you out of the second.

Five files used to explain this the other way round — that the coroutine resumes
and errors on a freed node. `combat.gd` now carries the canonical version and
they point at it.

### reset_physics_interpolation() goes after the position

The project runs with physics interpolation on, so the renderer blends every
node between its previous and current transforms. A node that is placed rather
than moved has to be told, or it is drawn once at the origin and streaks across
the map over one frame. Call it **after** setting `global_position`, and after
anything that sets rotation.

### Object.get() takes one argument

Unlike `Dictionary.get()`, it has no default parameter and returns `null` for a
missing property. `node.get("hp", 100)` is a parse error, not a fallback.

### The editor runs a placeholder, not your script

For a script without `@tool`, the Godot editor builds a
`PlaceholderScriptInstance`. Exported properties hold their real values, but
**method calls fail** with "Attempt to call a method on a placeholder
instance." Editor tooling (`src/tools/exportgamedata.gd`) must read exported
values directly and never call methods on the scenes it inspects.

### to_save_array() is fixed-length, and an empty one is normal

`InventoryContainer.to_save_array()` appends `null` for every empty cell so
positions stay stable across a save and load. Two consequences:

- `.size()` is the number of cells, never an item count. For the backpack that
  is **30**, not 20 — see the next entry.
- An empty array is a legitimate state, not a corrupt one. `gameover.gd`
  assigns `[]` outright when you decline a revive, and a fresh character starts
  the same way.

### The hotbar's keys are the backpack's cells 20-29

The keys hold items. Dragging a potion onto key 1 moves it out of the bag, the
way equipping moves a piece onto the character, and the server stores it as a
`carry_items` row at position 20. It used to be an item id pointing *into* the
bag, so the same potion was drawn twice; the gold "linked" tint, the "Linked
from inventory" tooltip, the drag that cleared a reference and the trash that
refused a key all existed to explain that, and all went with it.

The backpack's `InventoryContainer` owns the keys, which is what makes every
endpoint's answer land on them for free — but it means three things are not
what they look like:

- **`slots` is every cell, `capacity` is only the grid.** `slots` is the twenty
  grid cells then the ten keys, and `slots[i].slot_index == i` for all thirty.
  Anything meaning "the bag" — a drop in a gap, `set_slot_type()` — loops to
  `capacity`, not `slots.size()`.
- **A key's parent is not its container.** It is a child of the hotbar's row.
  Ask `slot.home_container` for "the container that saves this cell"; the trash
  does, and falling back to `get_parent()` there deletes the item from the
  screen without telling the save.
- **The keys can arrive before the hotbar does.** The HUD loads the bag, then
  attaches the hotbar. Cells past the grid wait in `_unattached_tail`, go out
  again on a save, and are handed over on `attach_remote_slots()` — which is
  all or nothing, because a missing key would shift every later one a cell left.

The server's half is two rules, both in `write_inventory()` and
`_add_to_backpack()`: an array replaces the bag always and a key only if it
reaches it, and nothing is ever *placed* on a key. `consume`, `equip` and
`bank/items` take the cell used as `position`, because with the keys in the
same rows "the highest cell holding it" is usually a key.

### Things that look uncalled and are not

Before deleting a function because nothing seems to call it, check all three:

- **String call sites.** `call_deferred("_change_to_game_over")` and
  `connect("pressed", Callable(self, "_on_x_pressed"))` are real calls. A search
  that ignores string literals will report both as dead. This produced 19 false
  positives out of 52 in one sweep.
- **Scene connections.** `.tscn` files carry `method="_on_body_entered"`
  entries with no corresponding code.
- **Engine virtuals.** `_ready`, `_process`, `_drop_data`,
  `_get_drag_data`, and EditorScript's `_run` are called by Godot.

### The four-direction rule lives in one place now

`Facing` (in `src/shared/`) owns the rule that turns a Vector2 into "up",
"down", "left" or "right". This section used to say seven copies were still out
there, in `player.gd`, `warrior.gd`, `mage.gd`, `tank.gd`, `healer.gd` and
`pet.gd`. **They are all converted.** Those six now carry zero copies between
them and call `Facing`.

The drift that motivated it is worth keeping, because it is why `Facing` has
two entry points rather than one winner. The enemy version returned `""` for
`Vector2.ZERO`; the player and class versions fell through to their `else` and
returned `"up"`. A still enemy faced nowhere, a still character faced up, and
nobody chose that.

- `from_vec()` — `NONE` when there is no direction. Navigation needs "no
  heading" to be a real answer rather than a coerced `"down"`.
- `from_vec_total()` — always a direction, `UP` on an exactly zero vector.
  There is no "no animation" to play, so a still sprite has to idle facing
  somewhere. The `UP` default is not a preference: every old copy resolved zero
  to up because they all ended `else "up"` and `0 > 0` is false.

**Two literal copies remain and both are correct.** `slashwave.gd` was the last
straggler and now delegates. What is left:

- `testrunner.gd::_legacy_walk_animation()` — deliberately the old body,
  character for character, as an independent oracle. It checks `Facing` against
  what `Facing` replaced on a grid of vectors, and the moment it delegates to
  the thing it is testing it tests nothing. Its own comment says so. Leave it.
- Nothing else. If a grep turns up a third, it is new and it is a mistake.

### Teleport: the server spaces the group, the client keeps it out of the walls

`POST /api/staff/teleport` existed and `characterhud.gd` had always known how to
*receive* one. **Nothing ever issued one** — the feature was built from both ends
and never joined in the middle. The owner panel has the three buttons now:
**Bring here**, **Go to them**, **Bring everyone**.

Two separate rules, and mixing them up is how somebody ends up in the scenery.

**Nobody stacks — and the server already handles that.** `teleport_offset()`
packs a group into hexagonal rings at `TELEPORT_SPACING` (48px) and hands each
client its own final coordinates, with a comment saying the client must not
repeat the arithmetic. Correct, and untouched. The one gap: `teleport_offset(0)`
is `(0, 0)`, dead on the destination — and the destination is wherever the person
who pressed the button is standing. So the panel asks `SafeSpot.find(..., 1)` for
a spot **beside** itself, never its own.

**Nobody lands in a wall — and the server cannot help.** It has no collision
data. Fifty people in the town square puts the outer ring 192px out, which in a
tight room is inside the scenery. The client holds the shapes, so the nudge lives
in the **receive** path, where *every* teleported player goes through it rather
than only the one issued from this panel.

`SafeSpot` tests **both**, because neither is enough alone:

- **Navigation** answers *"off the map"* — a point past the edge of the world is
  clear of every collider precisely because there is nothing there. But only
  `field.tscn` and `bossarena.tscn` carry a `NavigationRegion2D`; `elusion.tscn`
  does not, so a navigation-only test silently passes everything in town.
  `map_get_closest_point()` always returns *something*, so the **distance back**
  is the answer, not the call succeeding.
- **Physics** answers *"in a wall"*, works everywhere, uses the body's own
  `collision_mask` rather than a number typed in the helper, and excludes the
  body's own RID — a character collides with its own position, so without that
  exclusion nowhere ever reads as clear.

**It refuses rather than inventing.** Nothing clear within three rings returns
`Vector2.INF` and the caller says so. Landing a player outside the map is worse
than not moving them: *"it did nothing and told me"* is a bug report, *"it put me
in the void"* is a lost character. The one exception is an **arriving** teleport,
which goes anyway to the spot it was given — refusing would strand somebody being
moved *out* of a bad place, and that is the single case where the server knows
something the client does not.

**"Go to them" sends no request.** Position is client-written, so moving yourself
is a local act; `AreaRegistry.go_to()` does it. Asking permission would be
theatre — and `/api/staff/teleport` runs through `can_act_on()`, which is
strictly-greater and so refuses acting on yourself anyway.

**"Bring everyone" is armed-then-confirmed**, like a ban. It moves every account
on the server and posts a broadcast; it is the widest button on the panel.
`_button_for()` has an `"everyone"` entry so `_disarm()` can put the label back —
without it the button reads `Confirm?` for ever after a timeout, which is the
trap `ARM_SECONDS` exists to prevent.

`/api/staff/user/<username>` now returns `x` and `y` beside the `area` it already
returned, which is what "go to them" needs to land beside rather than at an
area's default spawn. Position is where a character is standing in a game, not
personal data about a person — unlike the addresses on that route, which is why
those are gated by `can_act_on()` and this is not.

### God mode is dev-and-owner, and the ordering is the whole feature

`Ctrl+G`, or the switch on the owner panel, turns damage off so the people who
have to test the game can do it without dying a hundred times.
`GameState.god_mode` holds it — transient, survives a scene change, cannot
survive a restart, which is exactly the contract that file states.

**The risk in it is one ordering decision.** `take_damage()` ends by calling
`gain_defense_xp()`, which reports the **raw** amount to `/api/skill/train`, and
the server *grants and stores* that XP. So the obvious implementation — let the
hit land, then heal back to full — would train defense continuously at no risk,
and **E-2's rate cap would not catch it**: that cap bounds XP per second, and an
invincible character parked in a pile of enemies sits at the honest ceiling all
day. It would be a god mode that farms.

So the guard returns **before** the hp change, before the floating number, before
the death and before the XP. The hit never happened; it was not healed.
`_test_god_mode_earns_nothing()` checks that by **position** — guard index before
the `hp = clamp(...)` index and before the `gain_defense_xp(` index — because
position is the only thing that actually matters here. Sabotage-tested with the
heal version, which fails both.

**Dev and owner — one rung above the debug keys beside it.** The threshold is
`Api.GOD_MODE_MIN_ROLE`, next to `DEBUG_KEYS_MIN_ROLE` and for the same reason:
one statement of the policy, which the suite asserts instead of a second copy.
Handing out an item a player should earn is a fairness question; turning off
whether the game can be lost is a different kind of decision, so it stops at the
two ranks trusted with the server rather than with the community.

**Ctrl+G is handled *before* `_staff_debug_allowed()`, so it works in a release
build.** Everything past that gate also needs `OS.is_debug_build()`, because those
keys hand out gear, currency and pets — things a player is supposed to earn, which
have no business existing in a shipped build. God mode hands out nothing, and it
is for the people who have to **test the real build against the real server**;
requiring a debug export would leave a dev with no way in on the thing they were
asked to check. Safe to lift on the same reasoning the whole feature rests on: it
earns nothing, and `hp` is client-written anyway. It calls `_typing_in_ui()`
because it now runs where chat is open.

**Two ways in, one flag.** `Ctrl+G` is the path a dev has; the panel switch is the
owner's convenience, because **the owner panel opens for `Api.is_owner` only** and
must stay that way — it also holds the maintenance switch and the gold grant.
Widening it to reach devs would hand them things god mode has nothing to do with.
Both paths move `GameState.god_mode`, and the switch re-reads it on every open
with `set_pressed_no_signal()`, so the keyboard and the panel cannot disagree.
The panel re-checks the rank in its handler too: a disabled button is a look, not
a permission.

`/api/staff/powers` lists it under `dev`, marked client-side. That route exists so
a rank never surprises the person granting it, and "comes with the ability to stop
dying" is exactly the kind of thing an owner should read before typing a name into
the rank box.

**It gives an attacker nothing.** `hp` is client-written and only clamped
server-side (E-9), so a modified client could always refuse to die. The gate
keeps an *honest* build honest, which is the same thing the debug keys below buy.

### A text check here is searching a haystack made of needles

Five times in one day a text check in this project matched **prose instead of
code**, or missed code because of how prose was laid out:

- a search for `"already taken"` went red on the comment explaining why that
  phrase must never be used
- a search for `"backpack ledger is still client-declared"` failed on a page that
  says exactly that, because markdown had wrapped the line between the two words
- `src.contains("const SKILL_IDS")` matched inside `const SKILL_IDS_UNUSED`
- a search for the first `gain_defense_xp(` after `func take_damage(` found it in
  the god-mode guard's own comment, three lines above the guard
- and the API's source scan reported five false alarms because Python
  concatenates adjacent string literals and it read them one at a time

**This is structural, not bad luck.** The house style is to explain a rule at
length beside the code implementing it, so *the comment explaining a rule
reliably contains the rule's own text*. Three rules follow, and all three are now
in the suite:

1. **Strip comments before searching for code.** `_first_code_index()` blanks
   comments in place — keeping line lengths, so indices still point into the
   original — the same job `code_only()` does in the API's `test_ownership.py`.
2. **Collapse whitespace before searching prose.** Markdown wraps wherever the
   column ran out; `"backpack\nledger"` does not contain `"backpack ledger"`.
3. **Match whole words, or match behaviour instead of names.** A consistent
   rename breaks nothing, so failing on one is noise — ask what the code *does*,
   not what it is called.
4. **A count is not evidence about a place.** `hud.count("_note_server_contact()") >= 2`
   was wrong twice in one line: `func _note_server_contact() -> void:` contains
   the string, so the *definition* counted as a call — and removing one of the
   two real calls still left the total at two. Assert each call site by the name
   of the function it must be in.
5. **Bound the search to the function you meant.** `_first_code_index()` answers
   *"in code rather than in a comment"*; it does not answer *"inside which
   function"*. Searching for something common — `save_character_state`,
   `if visible:`, `/api/staff/teleport` — finds it in a later function and reads
   as a pass. `_within(index, limit)` is the companion, and this was needed three
   separate times before it got a name — and twice more since, on
   `set_world_status("connection", "")`, which appears in the recovery path and
   in the give-up path and in the not-logged-in branch.

**And the check itself can be the thing that is wrong.**
`_test_no_unused_parameters()` split a signature on every comma, so
`colour: Color = Color(0.95, 0.45, 0.35)` became three parameters, the last of
them named `0.35)`, reported as unused. It would have fired on any `Vector2(x, y)`
default. `_split_params()` counts bracket depth now. A false alarm is how a check
gets switched off, and this file says so twice already.

The general form: **a check that has never been watched go red on the exact
mistake it is meant to catch is not a check.** Every one of those five was found
by sabotaging it, and four of them were wrong in a direction that *passed*.

### The debug keys are staff-only, and that is a rule, not a defence

F1-F7, F9-F12, M and the P O I U Y T pet row hand out gear, currency, pets and
skill XP. They are gated on `_staff_debug_allowed()` in `player.gd`:
`OS.is_debug_build()` **and** `Api.role_at_least(Api.DEBUG_KEYS_MIN_ROLE)`.

`is_debug_build()` alone was not enough, because a **Debug-template export
reports it as true** and choosing the wrong template in the Export dialog is one
mis-click. The rank check is what stops an ordinary player holding such a build
from pressing P and owning a pet. Pets are loot.

**It stops an honest player and nothing else.** `Api.role` is client memory set
from a login response, so a patched build sets it to `owner`. It would not even
need to: these keys add items to the LOCAL inventory and the client pushes that
to the server on save, and the backpack ledger is still client-asserted. Anyone
able to edit the client can grant themselves items with or without this gate.

The threshold lives in `api.gd` as `DEBUG_KEYS_MIN_ROLE` so the test suite
asserts the policy itself rather than a second copy of it.

### Some resources point at their script by path, with no uid

A `.tscn` or `.tres` saved by the Godot editor references its script twice —
`uid="uid://..."` and `path="res://..."` — and Godot resolves the uid first, so
moving the script (together with its `.gd.uid`) is safe.

A **hand-authored** one has only the path. Move the script and it breaks with no
error at all: the resource loads, the script is simply absent, and the object
falls back to its base class. Every class quietly running on Player's 20 hp
default is what that looks like from the outside.

**The suite now checks this, so it is no longer something to remember.**
`_test_script_references()` walks every `.tscn` and `.tres`, finds the
references carrying no uid, and asserts the file each one names still exists.
Move a path-only script and the run goes red naming every scene affected,
instead of the game quietly running on base-class defaults.

Which files are which is still not guessable, so to see the list yourself:

```
rg -o 'type="Script"[^]]*' --glob '*.tscn' --glob '*.tres' | rg -v 'uid='
```

At the time of writing: **339 script references, 301 with a uid, 38 path-only
across 22 distinct scripts.** The two clusters are `projectiles/acidpuddle.gd`
(11 files) and `world/lightflicker.gd` (7); the rest are one apiece, mostly UI
scenes.

This section used to name `data/enemies/*.tres` and `data/classes/*.tres` as
two of three path-only groups. **Both carry uids now** — they were re-saved by
the editor at some point, which is exactly how this set drifts and why a check
beats a written list. `data/items/*.tres` were always editor-saved, which is
why this cannot be reasoned about from the folder name.

### GDScript paths in string literals break silently too

`preload("res://src/...")` is a string. Nothing checks it until it runs. There
are three in the project, all in `src/tools/exportgamedata.gd`, pointing at
`baseenemy.gd`, `gameconstants.gd` and `characterdata.gd`. Move any of those
three files and the exporter dies, and a dead exporter means the server keeps
serving yesterday's numbers — which the test suite will catch and nothing else
will.

Scenes are worse: there are 25 `preload("res://scene/...")` paths. That is the
reason `src/` was reorganised to mirror `scene/` and not the other way round.

### A brand-new `class_name` is invisible until the editor rescans

Same cache as the next entry, different direction, and it costs the same
afternoon. `src/shared/safespot.gd` was added with `class_name SafeSpot` and the
next headless run reported **`characterhud.gd will not compile`** — because
`.godot/global_script_class_cache.cfg` had never heard of `SafeSpot`, and a
headless run only *reads* that file.

So after adding any file with a new `class_name`, **open the project in the Godot
editor once before running the suite.** That is the whole fix — the editor's
filesystem scan writes the cache.

**Not `godot --headless --editor --quit`.** That command is correct and it is
what CI would run, and on this machine `godot` is not on the PATH — the engine is
a loose `.exe` on the Desktop, which is the entire reason `run_tests.ps1` hunts
for the binary itself and why `atlasaudit.ps1` exists rather than a documented
`godot` command. This file said to run it anyway for about twenty minutes, which
is the same mistake the atlas audit already taught once. If you want it from a
shell, give it the path `run_tests.ps1` would find, or set `$env:GODOT` first.

Confirmed on 4.6.1: `SafeSpot NOT in the class cache` → rescan → 740 passed.

The compile check catches it immediately and names the file, which is the whole
reason that check runs first — the failure otherwise arrives as "every teleport
test failed" and sends you looking at teleports.

### Moving a script leaves Godot's caches lying about where it is

`.godot/global_script_class_cache.cfg` maps every `class_name` to the path it
was last seen at, and `.godot/uid_cache.bin` maps every uid to a path. **Neither
is updated when a file moves**, whether you moved it with `git mv` or anything
else outside the editor.

What you get is a wall of errors that looks like the move destroyed the project:

```
Parse Error: Could not parse global class "ItemData" from "res://src/systems/itemdata.gd"
Failed to instantiate an autoload, script ... does not inherit from 'Node'
Attempt to open script 'res://src/core/scenetransition.gd' ... 'File not found'
```

Every one of those paths is the OLD path. The files are fine. Delete the two
cache files and reopen:

```
Remove-Item ".godot\global_script_class_cache.cfg", ".godot\uid_cache.bin"
```

They are rebuilt by the **editor's** filesystem scan, so open the editor before
running anything headless -- a headless run only reads them, and starting one
with them missing is no better than starting one with them stale. Deleting all
of `.godot/` works too and costs a full reimport of every texture.

### Keep helper .ps1 files pure ASCII

Windows PowerShell 5.1 reads a `.ps1` with no BOM as CP1252, not UTF-8. A UTF-8
em dash is `E2 80 94`, and CP1252 decodes `0x94` as a right double quotation
mark, which PowerShell accepts as a string delimiter. One em dash inside a
double-quoted string closes it early, the rest of the line reparses as code, and
the error you get is `Missing closing '}'` pointing at a brace forty lines away
that is perfectly fine.

Nothing warns you, and the file looks correct in every editor. Write helper
scripts in ASCII, or save them as UTF-8 **with** a BOM.

### Shadowing a base class property

`Control` and `Node2D` both have `position`. Naming a local variable or
parameter `position` shadows it and Godot warns at parse time. In a grid, the
word you want is `cell` — it is also more accurate.

### A Label that shares a row gives way

A guild called "the first" was drawn as **"the"** in its own panel. The name
and a status line ("[THE FIRST] · Just you, so far. · founded …") shared one
`HBoxContainer`; the name could be trimmed and the status could not, so the
name was the thing cut to make room for a sentence about it. Nothing errors —
it just looks like the guild has a different name.

Two rules came out of it, both checked in `_test_the_guild_panel_reads_well()`
by measuring the text against the width it was given rather than by reading
the scene:

- **The thing a panel is about gets a row of its own.** The guild's name is on
  one line and everything said about it is on the line below.
- **A Label that clips or trims asks for almost no width.** Measured on 4.6:
  a twenty-character name wants 161px plain and **1px** with `clip_text` or an
  ellipsis overrun. That is how the name lost: it could trim, so its claim on
  the row was one pixel. Beside an expanding spacer such a Label is given
  nothing and vanishes. Clip or trim only a Label that is itself set to expand
  and has the row to itself.

### An invalid property assignment aborts the whole function

GDScript does not skip a bad assignment and carry on. It raises, and everything
below that line in the function never runs.

`bossenemy._spawn_one_eruption()` set `leaves_puddle` on a script that did not
have it. The error appeared on every pillar of every cast, and the three
statements *below* it — the radius scale, the per-spike telegraph, and the
interpolation reset — silently never executed. For months every spike used the
default 0.9s telegraph, the staggered patterns never rolled outward, and each
one slid in from the corner of the map on its first frame. None of that looked
like a missing property.

Guard an assignment onto anything whose script you do not control:

```gdscript
if "leaves_puddle" in eruption:
    eruption.leaves_puddle = true
```

### add_child() runs _ready(), so configure the node before you add it

Anything a node computes in `_ready()` from its own exported values is computed
at `add_child()`. Set those values afterwards and `_ready()` has already run on
the defaults — typically multiplying a profile against numbers that were not
there yet.

Both `bossenemy._spawn_one_eruption()` and `poisonslime._spawn_slime()` set
every property first and add last, on purpose. Keep that order.

**The suite checks this now, and it found a live one.**
`_test_spawn_ordering()` reads every `add_child()` in `enemies`, `projectiles`
and `pets` and fails if `element`, `element_override`, `damage`,
`telegraph_seconds` or `is_small` is assigned afterwards.

`bossstalker._drop_pillar()` was doing exactly that. `_apply_element_profile()`
**multiplies** — `telegraph_seconds *= p`, `damage *= p`, `scale *= size` — so
running it before the caller's values were set meant it scaled the scene
defaults, and the assignments below then flattened the result. Every pillar in
a stalker's trail telegraphed in 0.50s and hit for 22 whether it was lightning
or earth, while the boss's own cast pillars varied 0.25s–0.68s and 19–28. Fixed;
the trail is elemental now, and the plain pillar is unchanged at 22 / 0.50 / 0.80.

`bushmage.gd` set `vine.damage` after the call too. That one was genuinely
harmless — `vine.gd::_ready()` only connects signals — but it was moved up
anyway. A rule with one documented exception is a rule nobody can apply without
reading the exception first, and the comment justifying it said "today" twice.

It is a text check on the source rather than a runtime assertion, deliberately:
the failure has no symptom to assert against, which is why it survived. That
paid off in a way worth knowing: while a compile error was deliberately planted
in `baseenemy.gd`, this check and its sibling below still reported correctly,
because a text check does not need the project to build.

### `load()` does NOT return null for a script that will not compile

This is the trap that made a first attempt at the compile check below report a
clean pass on a project that did not build. Measured on 4.6.1, breaking one file
three different ways (wrong-arity call, syntax error, type mismatch):

| probe | valid script | all three broken |
|---|---|---|
| `load(path) as Script` | object | **object** — never null |
| `load(..., CACHE_MODE_IGNORE)` | object | **object** — also never null |
| `can_instantiate()` | `true` | `false` |
| `reload()` | `0` (OK) | `43` (`ERR_PARSE_ERROR`) |
| `get_script_constant_map().size()` | 1 | 0 |
| `get_script_method_list().size()` | 1 | 0 |

So a null check proves the file exists, nothing more. `reload()` is accurate but
recompiles in place, which is not something to do to a live project from inside
its own test suite. `can_instantiate()` is the read-only probe that moves.

`_test_every_script_compiles()` uses it with two corroborating conditions —
no methods and no constants either — because `can_instantiate()` is also false
for a legitimately abstract script, and a false alarm is how a check gets
switched off.

### A compile error is diagnosed by the first check, not the eighth

`_test_every_script_compiles()` runs **first** in the suite, loads every `.gd`
under `src/` (112 of them) and names any that will not parse.

It exists because of what the alternative looked like. A one-argument call to
`Combat.report_kill()` — which takes three — was planted in `baseenemy.gd`. The
report came back with **eight failures, every one of them named `gold_*`**, and
not a single line mentioning `baseenemy.gd`: the class had stopped compiling, so
every check reading `BaseEnemy.GOLD_*` had nothing to read. The true state was
"one file does not build"; the report said "the gold constants disagree with the
contract". Now the first line names the file, and it names the subclasses that
went down with it, so the blast radius is visible too.

`require_script()` already solved this for sections that do an explicit
`load()`. Sections that reach a global class name directly (`BaseEnemy.X`) have
no `load()` call to guard, which is the gap this closes.

It also moves a fact inside the suite that used to live outside it: "all scripts
compile" was previously only provable by launching a separate scene by hand, so
`run_tests.ps1` — the thing a person who clones this repo actually runs, and the
thing CI runs — did not prove it.

### But the suite cannot report that the suite is broken

The section above is only true of the files the suite *reads*. It is not true of
the suite itself, and the difference shows up as a **hang with no output at
all**.

A parse error was planted in `testrunner.gd` — one call with two arguments where
the helper takes three. `_run_tests.tscn` loaded, the script failed to attach,
`_ready()` therefore never ran, and nothing ever called `get_tree().quit()`. So
`godot --headless` sat there with an empty main loop until it was killed. Not one
line of test output, no parse error on screen (the engine prints it, but the boot
log is hundreds of lines of `.tres` UID warnings and it scrolls past), and an
exit code that only ever says "timed out".

**A silent hang is what a broken test suite looks like from the outside.** Every
other failure mode in here announces itself; this one is indistinguishable from a
slow machine, and the first guess is always that the last test added is slow.

So when `run_tests.ps1` produces nothing and does not return:

```
godot --headless --path . --script-check src/tools/testrunner.gd
```

or load it from any other scene and print the result — `load()` returns a
GDScript whose `can_instantiate()` is **false** and whose method list is
**empty**, which is exactly what `_test_every_script_compiles()` looks for and
exactly what it cannot look for in itself. Two seconds, and it names the line.

### A runtime error inside a section aborts it and still reports 0 failed

The sibling of the one above, and the one that nearly shipped a section doing
half its job. A new check called `board._build_row()`; the real function is
`_make_row()`. GDScript raised, **unwound the rest of that test function**, and
the suite finished:

```
SCRIPT ERROR: Invalid call. Nonexistent function '_build_row' ...
...
  824 passed, 0 failed, 1 skipped
```

Five checks in that section had already run and passed. The two after the bad
line never existed, and nothing anywhere said so. **The count cannot see a check
that was never reached**, so a section that dies halfway is indistinguishable
from a section that is shorter than you thought.

`require_script()` covers the version of this where a whole section's dependency
is missing. It does not cover a typo in the middle of one, and nothing can:
GDScript has no exception to catch.

So the defence is a convention, and it is worth keeping deliberately:

- **Every section ends with a `print()` line summarising it.** That line is not
  decoration. It is the marker that says the function reached its end, and a
  section header in the output with no closing line under it is a section that
  died.
- **Read the output when you add a check, not just the total.** The total went
  *up* on the run that lost two checks, because the section before it had
  gained some.
- **`SCRIPT ERROR` in a green run is a failure**, whatever the last line says.

### Work that vanishes past an await is checked now too

`_test_await_does_not_lose_work()` reads every `await` in `enemies`,
`projectiles` and `pets` and fails if anything below it reaches **outside** the
node — `Combat.`, `Api.`, `CharacterData.`, a signal emit, an `add_child()`.

Losing a write to your own member when your node is freed is harmless; the node
took the member with it. Losing a kill report is the small-poison-slime loot bug.
See the measured table under "Never await on something about to be freed" for
why nothing appears in the log when it happens.

### Adding an art folder is a licensing decision, and the suite treats it as one

`_test_art_folders_are_licensed()` holds a hardcoded map of every top-level
folder under `art/` and `assets/` to an owner — `elusion`, `clockwork-raven`, or
`unconfirmed` — and fails when a folder exists that nobody has classified, or
when a classified folder has disappeared. `art/pack` is exempt from the second
half, because it is the private submodule and legitimately absent from any clone
without access to it.

**It exists because this has gone wrong twice, both times the same way.**

`LICENSE` used to claim that "all original artwork, music, and paid/commissioned
assets in this repository are the exclusive property of Robert Ashley Clear."
That was **true when it was written** — one artist, commissioned, rights
assigned. It became false the day the Clockwork Raven pack arrived, and nothing
went back to reread it. Adding art does not feel like touching licensing, so
nobody does, and the sentence quietly grew to cover another artist's copyright.

The second instance was found while fixing the first: `art/thirdparty/` held
tilesets `split_art.ps1` itself calls "of unconfirmed origin", and the catch-all
in `assetlicense.md` — everything under `/art` except the item art — was
claiming them.

**That folder is gone now, and this paragraph spent a while saying otherwise.**
It read: *"One of those files, `houses read to use.png`, **is drawn by**
`scene/walls/shop.tscn`, **so it ships**"* — present tense, and by then neither
file existed. The picture was reachable only from `shop.tscn`, and `shop.tscn`
was the OLD shop, which nothing instanced by path or by uid. The shop the game
actually builds is `scene/walls/shophouse.tscn`, on `art/shophouses/`. So it was
a file kept alive by a scene that nothing could reach, and both were deleted.

Which is the whole lesson in miniature, twice over. Art gets replaced by editing
the scenes that use it; a scene that stops being used stops being edited, so it
keeps its old references for ever and keeps the files behind them alive with it.
And then the note explaining that is written in the present tense and outlives
the thing it describes. **A comment cannot fail** — and this one was a licensing
claim, which is the most expensive kind in this repository to leave wrong.

A licence file is a claim about a *set of files*, and the set changes without the
claim changing. Pinning it to names means the next new source of art fails a test
run instead of being noticed by a stranger reading the repo.

Deliberately a hardcoded list rather than parsed out of `assetlicense.md`: a
parser would keep passing while the prose rotted around it. Somebody has to type
the folder name in two places and think once.

**A folder with no art in it does not count, and that is a correctness rule
rather than a convenience.** Git cannot represent an empty directory, so a folder
left behind on one machine after its files moved elsewhere exists for that
developer and for nobody who clones — and counting it would make the check FAIL
locally and PASS in CI on the same commit. That is the one kind of failure that
teaches people to ignore a suite.

It was found the honest way: the check's first version went red on the author's
machine and green in a clean clone. `split_art.ps1` had moved the purchased art
into `art/pack/` and left seven empty folders behind — `amulets`, `armour`,
`consumables`, `currency`, `icons`, `lootbag`, `weapons`. They are safe to delete
and git will never notice either way. An empty folder is also not a licensing
risk, which is the check's actual subject: nobody can misattribute art that is
not there.

### A public clone has no art/pack, and the suite says so instead of failing

`art/pack/` is a private submodule of purchased Clockwork Raven art. A clone of
the **public** repo cannot have it — by design and by licence. Measured with the
pack removed, the suite used to report **16 failures**, and every one was the
licence boundary working correctly.

Two different problems were hiding in that number, and they needed opposite fixes.

**One was a real defect.** `kingdomboard.gd` did

```gdscript
const GOLD_ICON := preload("res://art/pack/currency/goldpile.png")
```

`preload()` resolves at **compile time**, so without the pack that script did not
compile. Not "the board lost its coin icons" — `KingdomBoard` did not exist. One
missing decoration took out a whole screen. Now the paths are constants and the
textures `load()` lazily at the call site, with `_header_icon()` returning a
full-width empty box on null so the columns still line up under their headings.
The reasons the original comment gave for `preload` were all correct; the
compile-time coupling was the part nobody had priced.

**The rest genuinely cannot be known without the art**, so they skip.
`check_needs_pack()` reports those as skips and lists them with a reason. Crucially
it stays a real check on any machine that *has* the pack, so a renamed icon still
fails loudly for the people who can see it — a skip that could hide a defect from
the author would be worse than a confusing report.

| pack | result | exit |
|---|---|---|
| present | 826 passed, 0 failed, 1 skipped | 0 |
| absent | 794 passed, 0 failed, 13 skipped | **0** |

The exit code is the point: `run_tests.ps1` gates a commit on it, and CI gates a
merge on it, so a public clone now passes rather than looking abandoned.

**Still open.** 20 checks do not *generate* without the pack — no section aborts,
but `_test_itemstack()` bails once it has no registry item to test with, and the
coin-ordering loop iterates over coins that never registered. `ItemStack` is pure
logic and should not need purchased art to be tested; building its cases from a
synthetic `ItemData` instead of the registry would let those run everywhere.

### Deleting art a TileSet still uses degrades the scene instead of erroring

`.godot/` is gitignored, so anything inside it exists on the machine that built
it and in no clone, ever. `_test_no_import_cache_references()` fails on any
`.tscn` or `.tres` naming a path under `res://.godot/`.

**Nobody types such a path — Godot writes it for you.** Delete a texture a
TileSet is still painted with and Godot does not refuse and does not warn. It
*degrades* the reference. This:

```
[ext_resource type="Texture2D" uid="uid://cee7dyl4prmn0" path="res://art/tiles/c92.png" id="4_e1pj8"]
```

becomes, on the next save:

```
[sub_resource type="CompressedTexture2D" id="CompressedTexture2D_8xafn"]
load_path = "res://.godot/imported/c92.png-1dc1c53689dab26c05060ecf286a8bcc.ctex"
```

which keeps drawing from the baked copy until the cache is cleaned, then stops.
That is exactly what happened when `c92.png` was deleted: **112 cells in the
`ground` layer of `elusion.tscn` lost their texture**, and the only trace was one
line ninety lines into an 85KB scene file. The `.ctex` was already cleaned by the
time it was found; only the `.md5` remained.

**How to count usage properly, because it was got wrong twice here.**

One texture can back MORE THAN ONE atlas source, in DIFFERENT TileSets, at
DIFFERENT source ids. `c92.png` backs two:

| atlas source | TileSet | source id | painted cells |
|---|---|---|---|
| `TileSetAtlasSource_hv532` | `TileSet_xyqp5` (water) | 2 | 0 |
| `TileSetAtlasSource_urc6g` | `TileSet_mtdc6` (ground) | 15 | **112** |

Checking only the first one says the file is unused. It is not.

Two separate traps, both hit:

- The `N:M/0 = 0` lines in an atlas block are tile **definitions** — which
  regions of the sheet are carved into tiles. They are not placements. Painted
  cells live in `tile_map_data`, a base64 `PackedByteArray` of 12-byte records
  (`int16` x, y, source_id, atlas x, y, alt) after a 2-byte header. Decode the
  bytes.
- Source ids are **per TileSet**. `ground`'s source 2 and `water`'s source 2 are
  unrelated atlases. Resolve each layer's `tile_set` first, then map its ids.

So the honest procedure before deleting any texture: find every
`TileSetAtlasSource` whose `texture` resolves to it, note which TileSet holds
each and at which id, then decode every layer's `tile_map_data` and count cells
against those ids. Anything less answers a different question.

This is also why a plain orphan sweep cannot settle it: searching scene text for
`c92.png` finds the `ext_resource` and calls the file used, which is true but
says nothing about whether a single tile is placed.

A text check on purpose. A runtime check passes on the machine whose cache still
holds the file — which is the one machine where the bug is invisible.

**The general lesson, since this came out of a batch of renames and deletions:**
renaming inside Godot is safe, because Godot rewrites every reference. Deleting
is safe only for a file nothing uses, and Godot will not tell you which is which.
Check first — an unreferenced file is free to delete, a referenced one takes the
scene with it, quietly.

### "Is this tile art used?" is a command, not a judgement call

```
.\atlasaudit.ps1
```

`src/tools/atlasaudit.gd` prints painted cell counts per texture across every
scene. It reads and prints; it writes nothing.

**It exists because that question was answered wrong three times about one file.**
`c92.png` looked unused and was deleted. Then: "13 tiles are painted from it" —
wrong, those were tile *definitions* in the atlas. Then "nothing is painted from
it, deleting was correct" — also wrong, from finding its atlas in the water
TileSet, counting zero and stopping. The truth was **112 cells in the ground
layer**, through a *second* atlas source in a different TileSet.

Three traps, and a filename grep walks into all of them:

- Tile **definitions** (`N:M/0 = 0` lines) are which rectangles of the sheet are
  carved into tiles. They are not placements.
- One texture can back **several atlas sources**, in different TileSets.
- Source ids are **per TileSet** — `ground`'s source 2 and `water`'s source 2 are
  unrelated atlases.

So the tool asks Godot rather than parsing text. `PackedScene.get_state()` reads
node types and properties **without instantiating** (reading `elusion.tscn`
should not build the world), and `TileSet.get_source(id)` returns the real
`TileSetAtlasSource` and its real texture, so the id-to-texture mapping is the
engine's own. Only `tile_map_data` is hand-decoded, because there is no API for
it: a 2-byte header then 12 bytes per cell, with the source id at offset 4.

That choice paid immediately — a text-parsing version of the same audit reported
zero painted cells for `barrels.png`, `redflower.png` and `bush.png`. All three
have four.

**Its output has one honest limit, printed at the bottom of every run.** "Not
painted anywhere" means no tile is placed from that texture in any TileSet. It
does *not* mean the file is unused — the same texture can be a `Sprite2D`, an
animation frame, a button icon or a shader parameter. The tool answers one
question well. Deleting on it alone is how art disappears.

Which is why it prints a **second** report: reachability. That one walks
`ResourceLoader.get_dependencies()` transitively from every scene and resource,
plus literal `res://art...` strings in scripts, and lists art nothing reaches at
all. *That* is the list you can delete from.

**A filename is not a file, and this is the case that proves it.** Two folders
can hold the same name, so searching scene text for `bushmagevines.png` finds
the copy that is used and clears the copy that is not:

| file | uid | used by |
|---|---|---|
| `art/enemy/bushmagevines.png` | `dxgqyacytahx1` | 8 vine scenes |
| `art/tiles/bushmagevines.png` | `1tkm12y77aw4` | **nothing** |
| `art/maincharacter/smalltankring.png` | `cl86sjmxy2fsc` | `tank.tscn` |
| `art/tiles/smalltankring.png` | `d34clhu42p5x4` | **nothing** |

Byte-identical pairs, left behind when the art folders were reorganised. A
filename sweep called all four used; the dependency graph separates them by
path. Both `art/tiles/` copies are safe to delete.

Its own blind spot, also printed: a path assembled at runtime,
`load("res://art/images/hotbar%d.png" % i)`. Nothing in this project does that —
checked — but if that changes, the files behind it will look deletable here and
will not be.

**The reachability report splits `art/pack/` out, and that split is the whole
difference between a useful report and a harmful one.**

`art/pack/` is a purchased library, not project art. 646 files came in the
Clockwork Raven pack and the game places 134. The other ~512 being unreferenced
is not a finding — it is what buying an asset pack looks like, and they sit in a
private submodule where keeping them costs nothing.

The first version of this report did not distinguish them. It printed one list of
218 files under the heading *"safe to delete"*, and roughly 200 of those were art
that had been paid for. Every individual line was true — Godot genuinely does not
reach them — and the report was still wrong, because **a true statement filed
under the wrong heading is advice.** There would have been no reason to doubt it.

So the rule for anything in this project that reports findings: the categories
carry as much weight as the measurements, and they need checking just as hard. A
number that is correct and a heading that is wrong reads exactly like a number
that is correct.

### A colour that cannot change is a state that cannot be told apart

`%errorlabel` on the login screen carries everything this game says about an
account — progress, validation, a wrong password, a ban — and its colour was a
`theme_override` in `loginmenu.tscn`. One red, for all of it. So
`"Connecting..."` and `"Loading characters..."`, the two messages that mean it is
**working**, arrived in the same red as `"Incorrect password"`.

The tell that this was an oversight rather than a decision: the recovery form,
the email prompt and the connection banner **on the same screen** each already
take a colour per state — `_recover_say()`, `_email_say()`, `_set_status()`, all
three the same `(message, color)` shape. The main line was the only one that
could not change, because it was the only one whose colour lived in the scene
file instead of at the call site.

`_say(message, color)` is the fourth of those now, and there are four colours
because the server gives four kinds of answer, not because four is tidy.
Measured against `app.py`: `/login` answers 200/400/401/403/429 and `/register`
answers 201/400/403/409/429.

| colour | means | reached by |
|---|---|---|
| grey | a request is in flight | "Connecting…" |
| green | you are in | 200 login, 201 register → "Welcome, *name*" |
| red | what you typed is wrong | 401, 400, client-side validation, status 0 |
| amber | the door is shut anyway | 403 ban or blocked connection, 429, 503 |

**The last two are the split that earns its keep.** "What you typed is wrong"
asks the player to try again; a ban does not, and a ban in the typo colour asks
somebody to retype a password that was never the problem. `Api.signout_notice`
— the line a kicked or banned player reads on their way back to this screen —
was rendering in the typo red to exactly the one person who must not misread it.

**Status 0 is red, not amber, on purpose.** That is `api.gd`'s "no answer at
all", and the connection banner is already amber and already saying the server is
unreachable. Two amber lines saying the same thing is one of them repeating
itself.

**The 409 is the part most likely to be "fixed" by mistake.** A 409 means
"username already taken" everywhere else, and this screen must never say that.
`register()` is only ever called one line after a 401, so a 409 cannot mean a
free name was refused — it can only mean the account exists and the password was
wrong. Printing the server's own 409 message would send a player off to invent a
second username for an account that is already theirs. `_test_login_states_are_distinct()`
pins that reading, because it looks like a bug to anyone handling the status code
rather than the flow.

Worth knowing about the server side of it: `/login` is careful never to say
whether a username exists — one message for both failures and the same scrypt
cost on both paths — and `/register` answers that same question outright, because
a signup form has to say when a name is taken. `REGISTER_MAX_CONFLICTS` is what
stops the 409/201 split being an unlimited oracle. The client reconstructing
"wrong password" from 401-then-409 is not a leak; it is reading something the
server already publishes on purpose.

**The distinctness half of the check is not a text check.**
`get_script_constant_map()` hands back the real `Color` values, so "four
different colours" is measured. Two names pointing at one colour is this exact
bug wearing a new hat, and four different *spellings* would not catch it.

**And one of these checks caught its own explanation first.** A whole-file
search for `"already taken"` went red on the comment three lines above the
branch explaining why the phrase must not be used. What is forbidden is *saying*
it, so the check now reads only lines containing `_say(`. Same family as the
five entries under "Before you trust a check" — the measurement was right and
the frame around it was wrong.

### Events scroll away, states must not

The HUD had one surface for everything the world said, and it treated the two
kinds identically — four *"Tunacan has gone hostile"* lines sitting in the corner
for ever with no timestamps. `app.py` makes the same distinction about deaths and
gets it right: *"A death is a TRANSITION, NOT A STATE, and counting it as a state
is the bug worth not writing."*

- **The message box holds events.** They happened, they are history, chat keeps
  them. A hostile announcement, a level-up, loot.
- **The status strip holds states.** True right now, must not scroll away, and
  must vanish the moment they stop being true. Connection lost, server closing,
  PvP on.

Mixing them is not a tidiness problem: a connection warning arriving beside four
old announcements looks exactly like more old news.

**The one that mattered was already answered and thrown away.**
`heartbeat_verdict()` has returned three values all along — `ok`, `revoked`,
`offline` — and the broadcast poll ended with a bare `if verdict != "ok": return`.
So a client that could not reach the server went on playing with **nothing on
screen to say so**, and everything since the last successful save was lost
without a word. The fourth time that exact shape has turned up here: an answer
that existed and nothing acting on it.

Three numbers, each with a reason rather than a guess:

- `OFFLINE_GRACE_SECONDS` **25** — the broadcast poll is every 10s and the
  heartbeat every 15s, so one missed request is ordinary and announcing it would
  make the strip flicker. Two missed polls is not ordinary.
- `OFFLINE_SIGNOUT_SECONDS` **90** — a lid, a lift, a router reboot all fit
  inside it, and the countdown is visible for the last 65 so nobody is surprised.
  Past it the client stops pretending and sends the player back with the reason,
  because playing on into a dead session loses everything after the last save.
- Priority **connection > maintenance > pvp** — if the server cannot be reached,
  nothing else on the strip can be trusted to still be true.

**Recovery is as automatic as the warning.** `_note_server_contact()` runs on
every `ok` from *both* polls and clears the alarm; a strip that keeps its last
message is a strip that lies.

**The ban countdown deliberately does not tick.** A ticking clock earns its keep
at 90 seconds, where every one counts. A ban is measured in days, nobody watches
it, and redrawing the login screen each second would be work spent on a number
that changes meaningfully once an hour. `describe_ban_remaining()` is static and
pure, so the suite asks it directly: 0 and negatives say nothing (a ban the next
login will simply ignore), "1 day" is not "1 days", and forty seconds left never
reads as "0 minutes".

### The death screen has two exits and only one was migrated

`_pay_and_revive()` in `gameover.gd` carries a long comment beginning **"THE
SERVER DOES ALL THREE THINGS THAT USED TO HAPPEN HERE"**. The button beside it —
*return to character select*, the one that pays nothing — went on doing all of
them locally:

```gdscript
slot_data["hp"] = int(slot_data.get("max_hp", 100))   # in two places
slot_data["gold"] = 0
```

Both lines were wrong, in opposite directions, which is why neither was noticed.

**The heal was a client decision.** The next status push reached the server as a
rise from hp 0 to hp 504 with nothing authorising it, and `_reconcile_heals()`
clamped it to what a few seconds of regeneration could produce:

```
unexplained heal: hp +504 vs regen 53 + granted 0
heal clamped: hp 504 -> 52
```

Full bars on this screen, a corpse on 52 hp after a relog. **The reconciler was
not the bug** — it was the only part of the system telling the truth, and
`granted 0` in that line named the missing piece exactly: no route had
authorised anything.

**The penalty was also a client decision, and it did nothing.** `gold` is in the
server's `SERVER_OWNED_STATS`, so the zero never arrived — the carry gold came
back in full on the next login. The empty inventory *did* stick, because losing
items is a loss and only gains are reconciled. True death took the items,
refunded the gold, and left the character unplayable.

`POST /api/character/respawn` is the other half now, and
`_clear_carry_on_death()` writes no hp at all. What is left in it is a **mirror**
of decisions the server has already committed, so the UI does not show stale
numbers for a frame.

**A failed request must not fall back to the local restore**, and the suite
checks that specifically — falling back puts the character back exactly where
the clamp will find it. Better to leave the player on the death screen with a
reason on it.

**The general lesson is about forks.** When a decision moves to the server, the
thing to search for is not the function that moved — it is every other branch
that reached the same state. Two buttons on one screen both ended with a
character alive at full health.

### A timestamp made on receipt measures when the reader turned up

The sibling of the rule above, and the same mistake one step further on. Events
were finally scrolling and states were finally staying put — and every server
notice on screen was still lying about **when**.

`GET /api/server/broadcasts` has returned an `at` per message since the table was
created. `characterhud.gd` read `body` and `kind` out of each entry and dropped
the rest. So a notice was stamped, once system lines were stamped at all, with
the moment *this client happened to receive it*.

That is correct for exactly one player: the one who was already logged in when it
went out. **And the first poll after login asks `since=0`, which the server
answers with the tail of the table — up to a week of notices, delivered in one
second.** So the player who most needs the time is handed a week of history with
every line claiming to be now. It does not fail to inform. It misinforms.

Three things came out of fixing it, all worth keeping:

- **`push_system_line()` takes the server's `at`**, and 0 — meaning "now" — is
  right for exactly one kind of caller: a notice this client invented about
  itself ("Lost connection."), which has no server row behind it because the
  server was never involved.
- **A bare clock is only unambiguous for today.** `LocalTime.stamp()` grows the
  date only as far as it has to: `14:32` today, `Sat 14:32` inside six days,
  `Sep 21 14:32` beyond. Six and not seven, because at seven "Sat" means either
  of two Saturdays, which is the exact ambiguity the date is there to remove. The
  full date on every line would spend a third of a chat row repeating the same
  eight characters down the whole log.
- **The record is written whether or not anybody is looking.** `_push_message()`
  used to send a notice to the chat log *or* the fading message box, never both —
  so a player with chat closed got a few seconds of "Tunacan has gone hostile."
  and no trace of it afterwards. The box is an announcement and should fade; the
  log is a record and should not. They are different things and the old code
  treated them as two outputs for one message.
- **"Should fade" was a sentence, not a feature.** Nothing faded the box: a line
  left only when a newer one pushed it off the top, so the last five notices sat
  above the menu bar all session. `_age_messages()` fades each line on its own
  clock now (`MESSAGE_SHOW_SECONDS`, then `MESSAGE_FADE_SECONDS`). And the first
  poll's catch-up — the week-long tail — is written to the log without popping
  the box; only what arrives after it is news. "The log always gets it" had a
  hole too: chat is built on first open, so before that there was no log at all.
  Notices wait in `_unlogged_lines` until it exists.

**And one conversion, in one place.** `unix seconds + system bias, then
decompose` was written four times in this project — `chatpanel.gd`,
`loginmenu.gd`, `staffpanel.gd`, `ownerpanel.gd` — and the fourth copy had lost
the bias, so every date in the owner panel was UTC under no label: seven hours
out in Denver, thirteen in Sydney, and wrong in the way that looks like right.
It is `src/shared/localtime.gd` now, and the suite fails if any of those four
files grows its own `Time.get_time_zone_from_system()` again.

The honest limit, stated rather than hidden: that call reports the offset in
force **today**, DST included, so a stamp from the other side of a DST change is
an hour out. For chat, which is minutes old, never. For a week-old broadcast,
twice a year. Fixing it properly needs a timezone database, which is not worth
shipping to make an old server notice an hour righter.

### The fatal hit is the one that never saved

Deaths on the kingdom board were never going up, and the server was not the
problem. `PUT /api/player/status` counts a death on the **transition** — stored
`hp` above zero, arriving `hp` at or below it — and `test_economy.py` covers it
three ways: *"a death is counted"*, *"staying dead is not five more deaths"*,
*"healing up does not count as anything"*. All correct, all passing.

**The zero never arrived.** `take_damage()` ends by calling `gain_defense_xp()`,
which is the only call on that path that reaches
`CharacterData.save_character_state()` — and on the fatal hit it returns two
lines earlier, at `if hp <= 0`. So the one hit that mattered was the one hit that
never saved. By the time anything else did, the player had either revived (hp
restored) or gone back to character select, and the server saw a healthy number
both times.

`_start_death_sequence()` now saves, and three details are load-bearing:

- **Flushed, not queued.** `save_data()` marks the save pending and `_process()`
  writes it on a later frame — and there is no later frame, because
  `_change_to_game_over()` replaces the scene. A queued save here is a save that
  never happens.
- **Not awaited.** This node is about to be freed, and Godot silently **drops** a
  coroutine whose object is gone (see the measured table under *"Never await on
  something about to be freed"*). `flush_save()` is called on `CharacterData`, an
  autoload, so the waiting is done by something that survives the scene change —
  the same reason `combat.gd` is an autoload rather than code inside `BaseEnemy`.
- **Before the scene change**, which the check verifies by index rather than by
  reading it.

**The general shape, which is most of this project's bugs:** a server half that
was right *and tested*, and a client half nobody had wired to it. `unauthorized_seen`,
the chat deletions, the teleport route with nothing issuing one, and this.

### A feed that can only grow cannot be moderated

`chatpanel.gd` was append-only, and nobody noticed because appending is all a chat
log ever looks like it needs to do. `_poll()` asks `/api/chat?since=<cursor>` and
calls `_add_line()`; the only way a line ever left was `pop_front()` at
`LINES_KEPT`. So when a mod deleted a message the server row went, the line stopped
reaching anybody who had not read it yet — and **stayed on every screen that
already had it** until a hundred more lines pushed it off or the player closed the
game. That is exactly the set of players the deletion was for.

Pictures were worse. The server now drops the image row when the last message
showing it goes, so the bytes 404 — but a client that already decoded one holds the
frames in `_pictures`, and again that is the people who saw it.

`_remove_lines(channel, ids)` closes it, off the `removed` list the poll now
carries. Three things in it are the actual lesson:

- **The open viewer is the case that makes it worth doing properly.**
  `_sweep_pictures()` deliberately *spares* `_viewing` — correctly, for its own job
  — so sweeping first keeps the picture alive and leaves the overlay up in front of
  the one player most needing it gone. `close_viewer()` runs **before** the sweep.
  After that the existing sweep needs no changes at all: it rebuilds the live set
  from whatever the feeds still hold, so it drops the picture without knowing
  anything about deletions.
- **Removals run after additions.** A line posted and deleted inside one
  three-second poll arrives in the same response as its own removal. Process the
  removal first and the line survives for ever.
- **An id of `0` must match nothing.** A system notice — a maintenance banner, a
  kick message — is a line this client invented and has no server id, so
  `line.get("id", 0)` returns `0` for it. A removal list that treats `0` as an id
  quietly deletes every one of them.

All three sabotage-tested, and `_test_chat_deletions_reach_the_client()` is a
**behavioural** check rather than a text one: `_remove_lines()` is pure logic over
`_feeds`, so the suite instantiates the script bare, fills `_feeds` itself (which is
all `_ready()` would have done that the function reads), and asks. Only the two
wiring facts — that the poll reads `removed`, and that it does so after the
additions — are checked as text, because no bare instance can prove them.

### The staff desk had no door

The Staff panel was built, drawn, tested — and **nothing opened it.**
`characterhud.tscn` carried a hidden Staff button, `_add_owner_button()` hid the
whole row from everybody except the owner, and no line anywhere instanced
`staffpanel.tscn`. A mod had no way in. Found while adding the moderation log,
which would have been a second room behind the same missing door.

`_add_owner_button()` now shows the row to `is_staff()` — mod and up — with the
Staff button on it; Owner and Powers stay owner-only. `_test_the_staff_desk()`
builds the real HUD and asks the row who it is for and what the button is
connected to. **Every check before that one was about the panel in isolation,
and every one of them passed.** Same shape as `unauthorized_seen` and the
teleport route: a finished half with nothing joined to it.

What the desk is now, and the rules in it that are not obvious:

- **Players** is a page from the server, not the server. `GET /api/staff/users`
  searches, filters and orders; the panel holds what it was sent and asks for
  more after the server's cursor (`next_after`). It used to fetch every account
  every ten seconds and search them locally — fine at forty players, the heaviest
  request in the game at forty thousand, sent by exactly the people trying to keep
  order while it is busy.
- **Generations, not a busy flag.** A search typed while the last one is in
  flight must win, so each request takes a number and an answer holding an old
  one is dropped. A flag that refused the second request would show results for
  what was typed a keystroke ago.
- **A null cursor is not a string.** The last page's `next_after` arrives as
  `null`, and `str(null)` is `"<null>"` — a name to page after. `read_page()`
  turns every page into what it must be, and "no cursor" also means "no more",
  whatever `more` said.
- **The picked player survives a page that does not carry them.** A new search
  can leave them off the list; the buttons stay aimed at them rather than quietly
  unpicking.
- **Record** is `GET /api/staff/actions?player=` — every sanction, note and
  warning about them, with a tally over the whole record on the tab. A note or a
  warning is **staff-only in the strict sense**: the server reads them under
  `can_act_on()`, so a mod never sees what a dev wrote about another mod, and the
  panel never has them to hide. "Log a warning" records that one was given; the
  game sends the player nothing, and the confirmation line says so.
- **Log** is the whole moderation log, filterable by player, staff and kind. The
  kinds come from the server's `kinds`, not a list typed here. A line about an
  account opens that account.

The suite hands the real panel answers in the server's shape through the same
function a real answer lands in — `_apply_list_page()`, `_apply_record_page()`,
`_apply_log_page()` — and reads what it drew and what it would ask next
(`_list_params()` and its siblings). The three `Api.get_json` lines are the only
part checked as text, bounded to the function they belong in.

### Colour is yours, rank is a badge

Names used to be painted by rank — owner gold, dev blue, mod green, everyone
else parchment — and the colour a player picked in Options was drawn over their
own head and nowhere else. For staff the slider did nothing at all, because a
staff name was locked to its rank colour. It was reported as "name colours did
not update", which was exactly right.

The rule now:

- **The colour is the player's.** The server stores the hue (`users.name_hue`,
  `PUT /api/account/name-colour`) and sends it with every name: chat lines,
  friends, the players menu, the guild roster. Chat keeps it as a snapshot per
  line, like the guild tag. `null` means "never chose" and draws Settings'
  default — the default lives in one place, `settings.gd`.
- **Rank is a badge a player cannot choose.** The owner's crown, and `MOD` /
  `DEV` in the rank colour (`Api.RANK_COLOURS` colour the badge now, not the
  name). Once colours are free a colour proves nothing — a player can pick the
  owner's gold — so the badge, drawn from the server's `role`, is the part that
  has to be true.
- **One function draws a name in every list:** `src/shared/nametag.gd`,
  preloaded (no `class_name`, so a fresh checkout does not need an editor
  rescan). Chat, friends, players and guild all go through it; the suite fails
  if any of them paints a name with `colour_for_role()` again.
- **`Api` keeps the setting and the server in step.** The login's hue is written
  into Settings (a second machine draws the first one's choice); moving the
  slider pushes the new hue once it stops (`NAME_HUE_PUSH_DELAY`); a colour
  picked before the server kept one is uploaded rather than lost.

**The first live run found the trap `_line_from_server()` warns about.** Every
name in chat came out in the default gold while the friends list beside it had
the real colours: the server sent `name_hue`, and chat's line copy did not carry
it. The suite now hands that function a real server message and reads the line
it draws, instead of checking for the key by text.

### A trade changes two bags and only one of them asked

Found by driving a trade between two real accounts, with the game client as one
of them. Four defects, each invisible from the side that was doing the testing:

- **Whoever accepts FIRST was told nothing.** The second accept's request runs
  the trade and gets the result; the first player's window just emptied, their
  bag went on showing what it had, and their next ordinary save - a whole-bag
  `PUT /api/character/inventory` - **deleted the item they had just received.**
  Now the server flags both characters and refuses that stale save with the bag
  it holds (409); the trade poll and the HUD's broadcast poll deliver the same
  result. All three routes hand it to `CharacterData.apply_server_carry()`,
  which adopts it (the live character AND the cached slot, so switching back
  cannot resurrect the old copy) and emits `carry_adopted`; the HUD announces
  it once, in the same sentence the history uses (`TradePanel.result_line`).
- **The person asked was never told.** The window polled the trade only while
  open, and nothing made them open it. The broadcast poll now carries a one-line
  `trade` summary; `_read_trade()` lights the strip and the Trade button (a
  dot) and toasts once per trade.
- **A typed name went to the other player's first character.** The window sent
  `to_slot` 0. It now sends no slot, the poll tells the server which character
  this is (`_broadcast_path()`, and one poll on arrival rather than ten seconds
  later), and the server decides.
- **Accept agreed to whatever was standing when it landed.** It now sends the
  revision the window drew; a 409 redraws the offer and says it changed, and a
  change the poll brings in is pointed out and flashed, never slipped in.

**Guild chat was the same bug, reported the same week.** The server had guild
chat from the day guilds landed - send, read, the "are you in one" check - and
the chat window refused it in four places without asking: opening the tab, the
poll, Say and the picture button, all saying "Guilds are not in the game yet."
Now `_local_refusal()` is the one gate (only a whisper to nobody is refused
locally), `_poll_path()` asks for guild chat like any other room, and
`_apply_read()` shows the server's own `notice` when `available` is false and
takes exactly that notice down when the room opens. The server words "no guild"
once (`GUILD_CHAT_NO_GUILD`) for both reading and writing.

**Staff can read a trade now.** The desk's third tab under a player, Trades,
pages `GET /api/staff/trades` by its pair cursor (`trade_cursor()`), says each
trade in the player's own words (`TradePanel.exchange_text`), carries the trade
id the ledger names in the tooltip, and opens the other person on a click.
Loaded when the tab is opened and when a new pick is made with it open.

**The Friends header is the guild header's shape** - a title over a line in
words ("2 of 4 friends online", "nobody on your list yet") and requests
waiting called out beside it, one flat ×, and no R: the list re-reads itself.

**The HUD's poll handler is `_apply_broadcast(data)`, split from the request.**
Every reader is called from there, so a reader written and tested but never
called from the poll - this project's most repeated bug - fails a check that
drives `_apply_broadcast()` with a server-shaped answer. The two old checks on
the cursor, which read the source, became checks on what it does.

### Deleting inert code is how you find out what it was for

E-2 closed by making all six skills server-granted, which left machinery behind
that *looks* dead and is not the same kind of dead:

- **`PUT /api/character/skills` writes nothing.** `VALID_SKILLS` and
  `SERVER_OWNED_SKILLS` are the same six, so the drop filter empties the parsed
  rows every time. The route validates a body thoroughly and discards it.
- The route's **skill-level clamp**, its **DELETE** and its **INSERT** therefore
  all run on rows that never land.

The instinct is to delete all of it. **Don't.** There are two different things
here and only one is rot:

**Rot is a comment that is false.** That block said *"skills have no server-side
grant path yet"* and *"fine for the four skills the client still grants"* — there
are none, and there has been a grant path since E-2 closed. A false comment is
worse than no comment because it is trusted. Those are corrected.

**Inert is generic code with nothing to do today.** The clamp is the thing
standing between a modified client and a level of 2³¹ *the day a seventh skill is
the client's to grant* — which is exactly when the drop filter stops catching
everything. It is not wrong, not a duplicate, not stale. It has no work right
now. Deleting a guardrail because it currently has nothing to guard is how you
find out what it was for.

The distinction that decides it: **does this code state something false, or is it
simply not on today's path?** The first gets fixed, the second gets a comment
saying why it stays.

The ceiling that *is* load-bearing today is in `_grant_skill_xp()`, which caps
every server grant — the path everything actually takes.

**What was genuinely worth removing is on the client.** `serverstorage.gd` pushed
all six skills through `_put_if_changed()` on every save. Since the SERVER moves
those levels on almost every kill, the fingerprint changed constantly — so nearly
every save bought a round trip whose entire effect was to be validated and thrown
away. The push and `_skills_body()` are gone; `SKILL_IDS` stays, because the read
side still unpacks what the server sends down.

That asymmetry is the shape of the whole thing: **the useless work was the
request, not the code that received it.**

### Godot's warnings don't reach the headless suite, so one is checked by text

GDScript warns on a parameter that is never read and asks for a leading
underscore — `_source_slot` means "deliberately unused". That warning comes from
the **editor** parsing the script. It does **not** surface through
`ResourceLoader.load()` in a headless run; that was proven by planting an unused
variable and unreachable code and watching the suite stay silent.

Which makes it the one regression class this suite is structurally blind to, and
precisely the class an editing pass creates: delete the last line that read a
parameter and it is now dead, with nothing headless to say so.

It happened here. Removing a write-only `_current_slot` tracker from
`itemtooltip.gd` left `source_slot` with no reader. The suite was green; the
warning appeared only when the project was next opened in the editor. The
docstring above it also still promised a guarantee the file no longer made.

`_test_no_unused_parameters()` closes it by matching Godot's own rule rather
than inventing one — a parameter not starting with `_` that never appears in its
body — so anything it flags is something the editor already complains about, and
underscoring satisfies both.

Two details that make it a real check rather than a decorative one:

- **Whole-word matching.** Without it a parameter named `slot` counts itself as
  used because the body says `slot_index`, and the check quietly stops checking.
  Sabotage-tested with exactly that case.
- **Known limit:** it reads single-line `func` declarations, so a signature
  wrapped across lines is skipped rather than guessed at. 1,631 signatures parse
  this way. A missed one still shows in the editor, as it always did.

### The .ps1 entry points are held to pure ASCII

`_test_helper_scripts_ascii()` reads `run_tests.ps1` and `split_art.ps1` byte by
byte and fails on any byte above 127.

Windows PowerShell 5.1 — the shell on a stock Windows install — reads a `.ps1`
with no BOM as CP1252, one byte per character, so a UTF-8 em-dash becomes three
garbage characters. Harmless in a comment; not harmless in a string, a path or a
regex. Every `.md` file here uses em-dashes and these headers get copy-edited
alongside the docs, so that is the realistic way one gets in. Held as ASCII
rather than fixed with a BOM, because a BOM makes 5.1 read the file correctly and
makes some other tooling read the BOM itself as content.

The two files are named explicitly rather than discovered by scanning, so
renaming a documented entry point fails the check instead of quietly leaving it
with nothing to look at.

### A Material is a Resource, so one instance is shared by everybody

`sprite.material = mat` does not copy anything. Hand the same `ShaderMaterial`
to two nodes and the second one to set a parameter decides the colour of both —
so the last slime to spawn repaints every slime already on screen.

The two correct answers, and which one applies is the whole design decision:

- **Authored in a scene.** Every instance of `icearrow.tscn` shares one
  material, and that is right, because every ice arrow is the same colour. Zero
  allocation per shot. This is what the 48 elemental scenes are for.
- **Built at runtime.** Only when instances of the *same* scene must differ.
  Costs a Resource per node, which in a bullet-hell is a cost in the wrong place.

The runtime path is still in `BaseEnemy._recolour_projectile()` and
`AcidPuddle._apply_element_recolour()` as a fallback, and both now return early
if the sprite already carries a material, so an authored scene always wins.

### CPUParticles2D and ParticleProcessMaterial take different resource types

Same-named properties, incompatible types, and the error only appears when the
scene is opened:

| node | colour ramp | scale curve |
|---|---|---|
| `CPUParticles2D` | `Gradient` | `Curve` |
| `ParticleProcessMaterial` (GPU) | `GradientTexture1D` | `CurveTexture` |

Handing a `GradientTexture1D` to a `CPUParticles2D` is a parse error, not a
warning. It shipped twice in `cookingscreen.tscn` and would have failed the
moment anyone opened a firepit.

### A helper that copies part of a shared function stops inheriting its fixes

`electricsprite.gd` had a private `_parent_to_projectiles_container()`. It
looked like a local copy of `BaseEnemy.spawn_projectile_node()`. It was a copy
of about a quarter of it, and the missing three quarters were the element stamp,
`EnemyData.projectile_damage`, and the interpolation reset. So that one family
fired orbs with the wrong damage type, ignored its own tier's damage, and still
streaked in from the world origin — a bug whose fix carries a long comment
saying it was applied "in the one place every enemy projectile passes through."
That family did not pass through it.

Nothing errored. Nothing logged. It was invisible for as long as nobody compared
two enemies side by side.

**If a shot, a spawn or a hazard needs to reach the world, route it through the
shared function.** If the shared function does not fit, change it — do not grow
a second one beside it. Check `bushmage.gd` and `bossstalker.gd` first when
something elemental behaves oddly; both reach the world by a different door for
real reasons, and both needed their element stamped by hand because of it.

### Scale the sprite, size the shape — never scale a collision node

Two separate pieces of documented guidance, and between them they rule out both
of the obvious approaches:

> Be careful to never scale your collision shapes in the editor. The "Scale"
> property in the Inspector should remain `(1, 1)`. [...] Scaling a shape can
> result in unexpected collision behavior.

> [...] avoid translating, rotating, or scaling CollisionShapes to benefit from
> the physics engine's internal optimizations.

A `CollisionShape2D` inherits its parent's transform, so scaling the `Area2D`
root is scaling the shape — the warning applies to both. The second quote is the
one that matters at bullet-hell volumes: an untransformed shape lets the broad
phase discard cheaply, and a scaled one gives that up on every projectile in
flight.

**The obvious fix is the other trap.** Resizing `CircleShape2D.radius` on an
instance looks right and is worse: a shape declared as a sub-resource is shared
by every instance of that scene, so resizing one pool resizes every pool on the
floor. Same shape as the Material trap above. `bossenemy.gd`'s "SCALED, NOT
RESIZED" comment is about exactly this and was correct for the case it was
written for.

**What actually works, when the scene is its own file:**

1. Put the visual scale on the **sprite** — a `CanvasItem`, no physics involved.
2. Put the size in the **shape resource**, in that scene's own copy of it.
3. Leave `scale` at `(1, 1)` on the `Area2D` and on the `CollisionShape2D`.

That is what all 48 elemental projectiles and all 9 puddles do. It only works
because each is a full copy owning its own sub-resources — nothing is shared
with the base scene, so writing `radius = 11.25` into `icepuddle.tscn` affects
ice and nothing else.

**Still outstanding, at runtime:** `bossenemy._spawn_one_eruption()` and
`bossstalker._drop_pillar()` both set `eruption.scale` at runtime, because the
per-pattern spike radius is not known until the pattern is chosen. Fixing those
properly means `resource_local_to_scene = true` on the spike's shape, or a
`duplicate()` per spike, and both change how a load-bearing fight behaves. It is
written down here rather than done.

**Still outstanding, authored into scenes: 15 physics nodes carry a non-unit
scale.** Counted, rather than estimated:

- all seven pets — six at `0.666667`, `petboss` at `1.333333`
- `turretprojectile` at 2.0, `petbossprojectile` at 0.35, `petvine` at 0.5
- `fieldteleport` at 1.5, and `teleports.tscn`, which has a non-uniform
  `0.93, 0.14` on the Area2D and a **negative** `0.53, -2.54` on the shape
  itself — that one is an editor drag, not a decision
- two `collisionshape2d` in `elusion.tscn` at `1, 0.99999994`, which is float
  noise rather than intent

`petpoisonpuddle.tscn` used to be a sixteenth. It was fixed because it was the
odd one out among eleven sibling puddles that all follow the rule, and because
the fix was provably geometry-neutral: radius 9.0 → 4.5, shape offset
`(1,1)` → `(0.5,0.5)`, the 0.5 moved onto the sprite. Same picture, same
hitbox, `Area2D` and `CollisionShape2D` both back at `(1,1)`.

The other fifteen are the same one-line-each change, but they are pets and
projectiles whose feel is tuned, so each wants verifying in play rather than
in arithmetic. Written down here rather than done, same as above.

### Two .tscn facts that changed in Godot 4.6

- **`load_steps` is deprecated.** "This attribute is now deprecated and should be
  ignored if present." Do not add it to a generated scene.
- **`unique_id` on a `[node]` is optional.** It is "only present in scenes saved
  with Godot 4.6 or later [...] not guaranteed to be present", it is per-scene-file,
  and the engine regenerates it on save. A scene written from outside the editor
  can leave it out. Copying a scene, do **strip** it rather than duplicating the
  original's — names stay primary and the ids are only a refactoring fallback,
  but two files claiming the same id is a question nobody should have to answer.

### Enum values are written into .tres as bare integers

`element = 3` in a resource file is ICE only because ICE is fourth in
`Element.Type`. Insert a value anywhere but the end and every `.tres`, every
`.tscn` and every saved game silently means something else.

`Element.Type` is **append only**. `LIGHTNING` and `POISON` are at the bottom
for exactly this reason, even though the tidy place for them was in the middle.

**The suite enforces this now.** `_test_element_enum_order()` pins all ten
names to the integers already baked into the data — written out by hand rather
than derived from the enum, because deriving it would make the check agree with
whatever the enum currently says, which is the thing under test.

Appending stays green; inserting goes red and names every element that moved
and what it now contradicts (*"EARTH is now 6, but every .tres that says 5
means EARTH"*). 102 files carry an element integer and every value 0-9 is in
use, so an insertion silently rewrites the meaning of 101 of them.

### The login screen does not wait for the world

`characterselect.gd` used to `preload("res://scene/elusion.tscn")`, and
`loginmenu.tscn` exports `characterselect.tscn` — so the login screen's first
frame waited on the town, the field it exports, the HUD, every panel and about
sixty scripts compiling. Measured cold in the sandbox: a login box at **2.6 s**,
1.8 s of it the world. `gameover.tscn`, which pulls none of it, loads in 25 ms.

Now `loginmenu.gd` calls `AreaRegistry.prefetch("elusion")` as it opens, the town
loads on a worker thread while the player types, and character select takes it
with `AreaRegistry.scene_for()` — waiting by the frame, with "Loading the
world..." on the slot, only if the player beat the loader. The login box is up
at **0.95 s**; picking a character after three seconds of typing reaches the town
in the same ~150 ms it always did. Once in the world, `prefetch_all()` loads the
other areas one at a time (0.3–0.4 s in all), which halved the hop down the
ladder to the boss (210 ms to 95 ms).

**Never `preload()` an area scene.** A preload is invisible to
`ResourceLoader.get_dependencies()`, which is how this chain went unnoticed:
nothing in any scene file named the town. `_test_the_world_loads_in_the_background()`
walks the login screen's whole load, script preloads included, and fails naming
the chain if any area turns up in it.

### A load() of an area loading in the background never returns

Godot 4.6.1, reproduced in the sandbox: `load_threaded_request()` an area, then
`load()` the same path on the main thread, and the main thread waits forever.
It happens with `boss.tscn` and `bossarena.tscn`, not with a small scene and not
with any of their dependencies. It was found because a sabotage of `scene_for()`
made the suite **hang** instead of fail — and then reproduced in the running game:
the old `ladder.gd`, walked into while the arena was still loading, froze the
game with no error.

So **an area's path is only ever resolved through `AreaRegistry`**:
`scene_for(area_id)`, or `scene_at(path)` for the doors that name their
destination by file (`ladder.gd`, `victoryteleporter.gd`, `gameover.gd`).
Both collect a background load with `load_threaded_get()`, the one call that is
safe while it runs. `change_scene_to_file()` on an area path is a `load()` too.
The suite scans `src/` for any `load(`, `preload(`, `change_scene_to_file(` or
`load_threaded_request(` given an area's path or one of the two exported path
variables — a hang cannot be a FAIL line, so the rule is held by reading the code.

### Rarity is a tier's name and colour, and it is drawn everywhere

`GameConstants.RARITY_NAMES` and `RARITY_COLOURS` give every item tier a word
and a colour: Common (iron grey), Uncommon (jade), Rare (cobalt), Epic
(amethyst), Legendary (ember), Mythic past that. The colours are the gear
materials, so an ember piece, its name and its bag's glow are one orange.

- **Every slot** that inherits `InventorySlot` - backpack, bank, loot bag,
  shop, hotbar, equipment - frames uncommon and up in that colour. The frame
  is built in code (`_build_rarity_frame`) and sits under the stack count.
  Common draws no frame: outlining most of what a player owns marks nothing.
- **The tooltip** colours the name from uncommon up and adds a rarity line.
- **A loot bag on the ground glows** for epic or better, in the colour of its
  rarest item (`lootbag.gd`'s `rare_tier_of`; a pet counts as legendary, coins
  never count). It replaced `petbeam`, a flat Line2D that lit only for pets.
  **Ordinary blending, not additive**: added light went pale cyan over water.

The loot bag panel fits its items (`rows_needed`, no 200-pixel scroll area),
packs its cells like the inventory's, shows stack counts at a readable size and
has **Take all**, which walks the cells in order, skips a cell that will not
fit (409) or is already gone (404), and stops on anything else.
`take_request` is the suite's door into a take.

**Nine cells, and the server's `LOOT_BAG_CAPACITY` must match.** It was six,
coins came first, and a boss bag's coins, gear, potion and pet ran past it -
the server cut the tail, which was the pet. See the API's CLAUDE.md, "Loot".

### Amulets add to the character, and the server has to count it

Fifteen amulets in `data/items/amulets/`, four families, and **the family is
the colour**: green is Vitality (`bonus_max_hp`), blue is Arcana
(`bonus_max_mana`), crimson is Fury (`bonus_damage_percent`), purple is Ward
(plain `armor_value`). Lesser / plain / Greater / Exalted are tiers 2-5 at
levels 5/10/16/22 (Vitality starts at 3). The plainest pack icon of a colour
is the lowest tier. The five plain tier amulets (iron..ember) are unchanged.

- `ItemData` carries the three `bonus_*` fields; 0 means none, so they are
  absent from every other .tres. The exporter refuses a negative bonus, a bonus
  on something with no equip_slot, and a damage percent over 100.
- **`Player._recompute_max_stats()` adds worn health and mana; the server's
  `gamedata.max_stats_for()` adds the same.** They must agree: the status route
  clamps hp to the server's maximum, so a bonus the server could not see would
  be taken away on every save. That is why the bonuses are in gamedata.json.
- **`refresh_gear_stats()` is the only place a gear change clamps hp and
  mana**, and it never raises them: putting an amulet on lifts the ceiling, not
  the health. `_recompute_max_stats()` must never clamp, because it runs
  through the `level` setter in the middle of `load_character_state()`, before
  hp has been read. `equip()`, `unequip()` and `CharacterData._apply_equip_result()`
  call it.
- **Fury multiplies** the skill multiplier in `get_damage_multiplier()`, which
  every class's hit and the pet's shot go through. `PlayerStats.gear_damage_factor()`
  floors a negative percent so a hit can never heal.

`_test_amulets_carry_their_bonus` holds the fifteen files against gamedata.json
(re-run the exporter after changing one) and the maths on a warrior built
outside the tree; the API's `test_gearbonus.py` holds the server half.

### The pace: element bands, the level curve, slimes and the finale

**Eight hours to level 22** at about five kills a minute in the band that
matches your level. `GameConstants.XP_BASE` 1,250 and `XP_GROWTH` 1.27 (was
100 x 1.15); no level cap by design. `_test_the_game_has_a_pace` recomputes
the hours from the .tres files and fails if they drift.

| Band | Levels | Elements | Drops up to | Normal health | Normal hit |
|---|---|---|---|---|---|
| 1 | 1-4 | light, wind | iron | ~270 | ~14 |
| 2 | 5-9 | water, ice | jade | ~400 | ~20 |
| 3 | 10-15 | earth | cobalt | ~600 | ~28 |
| 4 | 16-21 | fire | amethyst | ~925 | ~40 |
| 5 | 22+ | dark | ember | ~1,400 | ~55 |

- Each element's normals were scaled together, so the families keep their
  spread and health still climbs light < wind < water < ice < earth < fire <
  dark. XP and attack XP scaled with health (about 0.37 XP a point), so skill
  XP per second of fighting did not change. The plain bush mage is earth and
  the plain fire sprite is fire; the bush sniper and electric sprite are
  specials outside the bands.
- **Normals' pet odds are held at 1 in 216 at best** (`pet_odds_override`) so
  a band-5 mob does not drop pets like a boss.
- **`bushmage.gd` now uses `projectile_damage`**; every mage used to hit for
  `attack_power` 8. So do the bosses now - see "Bosses hit for their band".
- **Slimes are placed as larges** (`<element>slimelarge.tscn`). A large
  copies itself once and each large bursts into four smalls at half health: two
  larges, then eight archers. `EnemyData.split_into` names the small, and
  `_spawn_slime()` gives a twin the large's data and a small the split_into
  data (it used to be poisonslimesmall for every element). Large = 2x the
  band's normal health, small = a third, arrow = three quarters of a hit. The
  large grants nothing; the exporter credits the small with 8 placements per
  placed large, which is its kill ceiling on the server.
- **A splitting large emits `died` before its hitflash await**, so the
  respawner brings it back (it never did) and the signal cannot be lost.
- **The Crowned is the finale**: 13,800 health, tier 6, and the arena's
  victory door now leads to its room (`boss_entrance`); that room's ladder goes
  up to the field. Fire boss 9,200.

### Every tier from jade up carries a bonus, and legendary is rare

Loot is rewarding past its armour or damage number. Iron is Common and plain;
from jade up every piece adds a bonus that grows with the tier (the
`bonus_*` fields from the amulets):

| Gear | Bonus | Jade | Cobalt | Amethyst | Ember |
|---|---|---|---|---|---|
| Plate set (helm, chest, legs, boots, shield) | health | +20 | +40 | +65 | +100 |
| Cloth set (hood, robe, trousers, slippers) | mana | +24 | +48 | +78 | +120 |
| Each weapon | damage | +2% | +3% | +5% | +8% |

Plain amulets and rings (iron to ember) add a little of all three plus their
armour, the all-rounders; a ring never gives more than the amulet of its tier,
and **each bonus family must still beat the plain amulet of its tier at its own
stat**, or the specialist becomes the vendor loot.

**Legendary (ember) is rare**, through `tier_odds`, which may carry zeros:
dark-band normals put ember on 3% of their item slots (about one an hour at
five kills a minute); the fire boss and the Crowned are `(0, 0.25, 0.75)` from
tier 6, so legendary 1 in 4; the other five bosses never drop ember (amethyst
35%, cobalt otherwise). Zeros keep `max_loot_tier` - and with it gold and pet
odds - where it was. `_test_better_loot_carries_more` and the API's
`test_rewards.py` hold both halves.

### Bosses hit for their band

All seven bosses run `bossenemy.gd`, and all seven used to hit for its
`attack_power` 34, `melee_power` 45 and the stalker's 22, whatever their .tres
said. The six elemental ones had a `projectile_damage` nothing read (the spike
is placed by `_spawn_one_eruption()`, not `spawn_projectile_node()`), so once
the normals were banded the Crowned's spike (37 after dark's profile) hit softer
than a dark bush mage (55) and the light boss nearly three times its band.

- **The spike is the .tres's `projectile_damage`**, 1.5x its band's normal hit:
  light and wind 21, water and ice 30, earth 42, fire 60, the Crowned 83.
- **The swing and the trail are shares of it** (`MELEE_SHARE` 45/34,
  `TRAIL_SHARE` 22/34, the ratios the fight was tuned at), through
  `spike_damage()`, `melee_damage()` and `trail_damage()`. The stalker is
  handed its number in `setup()`. The exports are only the fallback now.
- **The element profile still scales the spike and the trail**, so a real
  spike lands for 24 / 19 / 26 / 27 / 53 / 60 / 91 (light to the Crowned) and
  a trail pillar for 16 / 13 / 16 / 17 / 34 / 39 / 59.
  Relative to the class health pools, the Crowned at level 22 is about as
  dangerous as the original 34/45 fight was at level 1; the early bosses are
  gentler than that, as their bands are.
- **The stalker stamps the boss's element on its pillars** (`setup()`'s last
  argument). The variant scene alone was not enough: there is no dark pillar
  scene, so the Crowned's trail used to be plain - 54 and a full-strength
  ring - while its spikes were dark. It is dark now: 59, ring alpha 0.22.
- `_damage_data()` answers with `ENEMY_DATA` while `enemy_data` is still null,
  as `_ready()` does, so a bare `bossenemy.tscn` reports the Crowned's numbers.

`_test_bosses_hit_for_their_band` spawns a real spike and a real stalker
pillar for each of the seven.

### Gear bonuses are shown

- **The Gear window sums them**: Health / Mana / Damage from gear, from the
  character's own `equipped_bonus()` - the sums its maxima and hits use - as
  "+150" in green, or a dash for none (not "+0").
- **A tooltip over gear compares it with what is worn in that slot**: a
  heading ("Compared with your Cobalt Cuirass:" or "Nothing worn there yet:")
  and one row per stat that would change, gains green and losses red, in the
  tooltip's `statscontainer` rows the scene always had and nothing filled.
  Not shown for the piece on the doll itself, for gear this class can never
  wear, or with nobody playing; a level requirement does not hide it.
- **The tooltip fits itself** (`reset_size()`) each time it is shown. It used
  to keep the size of the largest thing it had held and end every tooltip in
  a rule with an empty band under it.

`_test_gear_bonuses_are_shown` holds the panel, the arithmetic and each case.
Gear over an **empty** slot gets the heading alone ("Nothing is worn there yet -
all of it is a gain."): against nothing, every row is the stat line again.

### Attack XP is the server's, and the bar copies it

Attack trains **only at the kill**, on the server. The client used to add its
own on top: 5 per enemy per warrior swing, 2 per enemy per tank aura tick, 5
per stalagmite and turret hit - and it scaled the kill's amount by its own
`skill_proficiency` as well. None of that was ever reported, so the attack bar
climbed on screen, and the level and the damage it carries fell back at the
next login.

- **`Player.apply_server_attack(level, xp, xp_next)`** copies the kill's answer
  (`attack_level`, `attack_xp`, `attack_xp_to_next`) onto the bar;
  `combat._apply_xp()` calls it. `gain_attack_xp()` is only the fallback for an
  answer without those fields, and adds what it is given, unscaled.
- **The warrior's 1.5 is applied by the server now** (`proficient_amount()` in
  app.py, the same rule `/api/skill/train` uses). It sat in `SKILL_PROFICIENCY`
  and nothing honoured it for attack.
- No swing, tick, spell or shot calls `gain_attack_xp()`; the suite fails if
  one does. Defense and magic still show an optimistic copy and report the raw
  amount (`SkillTrainer`), because those do train per hit. What they show is
  rounded the way the server rounds it; see "Shown skill XP rounds like the
  server".

### A push that failed after it was accepted is retried

`save()` returns "taken", not "stored". `ServerStorage` pushes after it has
returned true, and a refused or unanswered section stayed dirty - but only the
**next** save retried it, so a player who changed nothing more before quitting
lost it. `has_unpushed()` existed on `SaveStorage`, said exactly this, returned
false, and nothing called it.

- `ServerStorage._record_push()` keeps `_failed_keys`; `has_unpushed()` reports
  them. A section whose current body the server already holds clears its mark.
- `CharacterData.flush_save()` writes when anything is unpushed, not only when
  a save is queued, and `_process()` retries every `UNPUSHED_RETRY_SECONDS`
  (10) with nobody changing anything.

### Small wires, joined (the sweep)

Each of these existed, looked finished, and was connected to nothing:

- **Gate spikes hit at full height.** `bossprojectile.gd` had `const
  IMPACT_FRAME := 1`; `secondbossprojectile.tscn` and its six copies set
  `impact_frame = 2`, which Godot dropped without a word. It is an export now.
- **Bosses are not shoved.** `player.gd` skips the `"unpushable"` group; the
  boss joins it in `_ready()`.
- **M opens the map** (`minimap_toggle`), beside I, C and G in the HUD.
- **The electric orb animates.** `magicprojectile.gd` looked for
  `animatedsprite2d` and played `projectile`; the scenes say `AnimatedSprite2D`
  and `default`.
- **An update is announced.** `Api.build_notice()` reads the two build numbers
  `refresh_build_info()` always fetched; the login screen shows it ("Refresh
  the page to update" in a browser).
- **One password rule.** `Api.clean_password()` trims, everywhere: login,
  Options and recovery. Only the login screen used to, so a password set in
  Options with a trailing space could never be typed in again.
- **The revive price is read** from `GameConstants.REVIVE_COST`, not copied.
- `PlayerStats.attack_damage_bonus()` / `magic_damage_bonus()` are **not
  applied** and now say so; `damage_multiplier()` superseded them.

And the words: `LocalTime.ago()` is the one "5 min ago / 1 day ago",
`GameConstants.counted()` the one "1 day / 3 days", `AreaRegistry.display_name()`
the one area name (no "Bossarena"), `Api.no_answer_text()` the one "no answer"
(a player never reads "Is it running?"). The restore line on a potion is said
once, from the data; rods no longer claim level requirements they do not have;
every close button is ×. `_test_the_sweep_wiring` and `_test_the_sweep_words`
hold all of it.

### The browser build

**Export:** Project > Export > **Web** (`export_presets.cfg`). The preset builds
without threads, uses Elusion's own loader (`web/shell.html`), has no service
worker, leaves `src/tools/` and `scene/tests/` out, and writes to `builds/web/`.
`builds/` is gitignored and must stay that way: an export contains the private
art pack. The site serves those files to players; git must never hold them.

**Try it at home:** start Flask, then `python web/serve.py` and open
`http://localhost:8060`. It serves the export and passes `/api/` to the API, as
the real site does. The Caddy and nginx blocks for the real site, both tested
against this export in the sandbox, are in the API repo's `DEPLOY.md`.

**One address.** A browser build calls the address it was loaded from
(`WebPage.origin()`, step 0 of `Api._resolve_base_url()`). The API sends no
cross-site headers, so the browser refuses any other address. Measured: a page on
:8061 calling :5000 had every request blocked. So the site serves the game and
`/api/` from one host.

**No threads, so nothing loads ahead.** In a no-threads build,
`load_threaded_request()` does the whole load inside the call. Asking for the town
as the login screen opened held that screen 2.2 s longer: the box appeared at
4.35 s instead of 2.1-2.25 s. `AreaRegistry.loads_in_background()` is false when
the build has the `nothreads` feature, and then `prefetch()` asks for nothing.

The town loads when a character is picked, under "Loading the world...".
Character select waits **two** frames before that load, because the first one
resumes inside the click's own frame, before it is drawn. With one frame, the
label never reached the screen in Chromium. A thread-support export was tried and
dropped: it took 40 s from the pick to the town in the same browser, and it needs
isolation headers.

**A closing tab still saves.** A hidden page draws no frames, and
HTTPRequest starts its fetch on the next frame. So a save queued as a tab closed
was lost, as was a push that was still in flight. `CharacterData._on_page_leaving()`
runs on visibilitychange and pagehide (`WebPage.watch_leaving()`). It sends every
section the server has not confirmed as a keepalive fetch, which the browser
finishes after the page is gone (`Api.send_before_leaving()`,
`ServerStorage.requests_before_leaving()`).

- The browser holds at most 64 KB of keepalive in flight, and the explored map
  can fill that alone. So the save goes last and without the map. `/api/save`
  keeps a map the body does not mention.
- Measured: a potion moved, then the tab closed 0.2 s later, and the server had
  it. With the watch removed, the server kept the old bag.
- A hidden tab saved within 0.5 s, against a 2 s debounce.

**An export lists every `.tres` as `.tres.remap`.** `ItemRegistry` walked
`data/items/` with DirAccess looking for `.tres`, so **every exported build ran
with an empty registry**. That included a Windows export: no item could be named,
drawn or validated. It was found in the browser ("ItemRegistry not populated
yet" at every login). It now uses `ResourceLoader.list_directory()`, and the
suite fails if anything that ships walks `res://` with DirAccess.

**An arrival draws the right map from its first frame.** The class cameras run
on the physics clock, so an area's first frame was often drawn before the first
tick, with no camera: the map from its corner, unzoomed. This was measured on the
desktop too: canvas origin (0, 0) on the first frame of each arrival. Now
`Player.snap_camera()` runs:

- in `_ready()`
- in `AreaRegistry.place_player()`, after `reset_physics_interpolation()`
- at the field's arrival portal
- in the teleporter

A frame with no scene in it yet is black, not grey. The black is set at runtime by
`AreaRegistry`, not in project.godot; see "Grey in the gaps, black past the map".

**In a browser, Options hides window size, V-Sync, the renderer and the graphics
API.** The browser owns the window and paces the frames, and Compatibility is
the only renderer there. The readout says "paced by the browser". The login
screen has no Exit, since a page cannot close its own tab.

**Measured** in headless Chromium through Caddy and nginx, with SwiftShader
software GL (a real GPU draws much faster):

- The export is 51.8 MB, or 21.4 MB with gzip. On 40 Mbps the login screen is up
  at 7.3 s.
- From picking the warrior to standing in the town takes 3.2-3.5 s.
- A return visit gets 304s and downloads nothing.
- After an upload, the next visit runs the new build.

**Pictures in chat.** In a browser Godot's FileDialog shows the engine's virtual
disk, a folder of nothing. There, + asks the page's own file picker
(`WebPage.pick_file()`), writes the file to `/tmp` in the page's memory and
attaches it as a dropped one. Dropping a file on the game works as it is. A page
gets text from the clipboard, never a picture, so the chat box there says
"drop a picture" rather than "Ctrl+V".

Tested in Chromium:

- + opened the picker, and the chosen file arrived byte for byte.
- A dropped picture was attached, sent through `/api/`, and drawn in chat.
- **Remember me survives a reload**: `user://` lives in the browser's
  IndexedDB.
- **The tab keeps the game's name.** The engine renames it after the project
  ("ElusionRPG") as it starts, and the loader puts "Elusion RPG" back.

**A ticked box under the pointer** was found in the browser, and it is true on
the desktop too. The theme had no `hover_pressed` button style, so a toggled
button under the mouse fell back to the engine's own: no border, the text pushed
right, and "Remember me" read "Remember m". `Button/styles/hover_pressed` is the
pressed style now, with its font colour.

`_test_the_browser_build` holds every wire a desktop run can see.

**Still open:**

- The tab icon is Godot's, because the project sets no `config/icon`.
- There is no audio to test, since every sound id is empty.

### Leaving waits for the save

`flush_save()` only **starts** a push. On the desktop, the window's X ran it and
the engine quit in the same frame, before the first request left. Measured
against the real server: a bag changed and the window closed at once, and the
server kept the old bag.

The X now waits:

- `CharacterData` turns off the engine's own quit (`set_auto_accept_quit(false)`).
- `_quit_after_saving()` takes the live character's state and sends
  SkillTrainer's batch.
- `finish_saving()` then waits until the server has everything, for at most
  `QUIT_SAVE_SECONDS` (3), and quits.

Measured: the bag went, and the game closed 0.2 s after the X.

A logout now waits too, with `await CharacterData.finish_saving()` before
`clear_current_user()` and `Api.logout()`. Before, the revoke raced the push's
PUTs, which go one after another. On localhost the push won five times out of
five, but the order should be settled by the code, not by the network.
`_test_leaving_waits_for_the_save` covers both.

### Shown skill XP rounds like the server

The server grants `int(raw x specialty)` for each batch SkillTrainer sends
(`proficient_amount()`). Defence and magic rounded each hit instead, with a
floor of 1. A tank's 1-point hits showed 1 each against the server's 1.5, so the
bar ran a third behind and jumped at the next login. A hit worth nothing showed
1.

`SkillTrainer.report(skill, raw, factor)` now returns what to show: the batch's
`int(raw x factor)` less what the batch has already shown. It starts again at
each flush, as the server does. The bar and the record now agree to the point.
`_test_skill_xp_rounds_like_the_server` holds it.

### A game key takes the keyboard back from a clicked menu

`project.godot` binds WASD and the arrows to `ui_left`/`ui_right`/`ui_up`/`ui_down`
as well as the `move_` actions, and Space to `ui_accept` as well as `attack`. A
click gives a Button or a slider the keyboard focus, and the GUI then read every
step as menu navigation. Measured in Options:

- After one click on Damage numbers, walking moved the focus from button to
  button, and Space swung the sword and flipped the setting too.
- After a click on the master volume, walking right turned the volume up.

`CharacterHUD._input()` runs before the GUI does. When a move key or attack is
pressed, it takes the focus off whatever has it (`release_for_world_key()`), so
the GUI never sees the key as navigation. Movement is polled, so the character
walks either way. An editable text box keeps the keyboard, since those keys are
letters in it: the same test as `player.gd`'s `_typing_in_ui()`. Enter, Tab and
E are not game keys, so a menu keeps them.

The `ui_` bindings are left as they are, so the login screen and character
select can still be walked with WASD. `_test_game_keys_are_not_menu_keys` builds
the bug first, then shows the hand-back stops it.

### Grey in the gaps, black past the map

Many floor tiles have transparent gaps: the town's cobblestones are a third
transparent pixels. A gap shows whatever is behind the tiles, and the art was
painted over the engine's grey, so the gaps read as mortar. The browser round set
`default_clear_color` to black in project.godot. The editor draws a scene over
that colour too, so every gap in every scene turned black, in the editor and in
the game. It was reported as "my graphics trip out". The field's `Black` layer was
painted by hand to make its outside black before that.

The two jobs are separate now:

- **project.godot keeps the engine's grey** (no `default_clear_color` line), so the
  editor shows a scene the way the game does.
- **`AreaRegistry` makes the screen black at runtime**
  (`RenderingServer.set_default_clear_color`). Outside the map is black, and so
  is a frame with no scene in it yet.
- **Every area gets a `MapBackdrop`** (`src/world/mapbackdrop.gd`) when it opens,
  through `SceneTree.scene_changed`. It is grey (`GAPS`, the engine's colour)
  under every tile any visible `TileMapLayer` draws, and nothing past the edge.
  There is no layer to paint and nothing to keep in step. A new or repainted
  area is covered as soon as it is saved.

Three details that matter:

- **It covers the tile as drawn, not the cell.** The town's water is 32x32 tiles
  on a 16x16 grid, drawn centred on their cell. Covering cells left three
  quarters of each water tile bare, and rounding to whole cells put a grey band
  past the map's edge.
- **Runs, not tiles.** Tiles in a band that touch are merged, so the field is
  108 rectangles instead of about 18,000 draw commands a frame.
- **Once per area per session.** The cover is cached by scene path. The field's
  takes tens of milliseconds to work out.

`_test_black_past_the_map` holds all of it, and checks every real area.

### Chat, the way players will use it on day 1

A sweep of chat with the real game against the real server found these. Each is
held by a suite section.

**One message is one line** (`_test_chat_is_one_line_per_message`). The server
stored whatever was typed. Some real damage:

- One message of 150 newlines was 150 blank lines on every screen, which wiped
  the window.
- A newline let a player print "12:00 [SERVER] Server restarting" on a line of
  its own.
- A bidi override printed a message backwards.
- A message of nothing but zero-width spaces was a blank line under a name.

The server now cleans all of this (`clean_player_text()`, see the API's
CLAUDE.md). `ChatPanel.one_line()` does the same as a line is drawn, for lines
stored before the rule. ZWJ stays, since emoji are built with it.

**A new line is added, not the log rebuilt** (`_test_chat_keeps_your_place`).
Every arriving line used to call `_render()`, which destroyed and rebuilt the
whole log and scrolled to the end. Measured with fifty lines:

- A line cost 35 ms, so a busy world chat stuttered the game while it was open.
- A player who scrolled up to read was pulled back down whenever anybody spoke.

Now `_append_to_log()` adds the one line (about 1 ms) and drops the oldest past
`LINES_KEPT`.

- The log follows only a player already reading the newest lines, or one who just
  sent a line (`_stick_to_bottom`).
- A reader further up keeps their place, including when staff remove a line
  (`_render(true)`).
- A poll's lines decide once, as a batch, because the layout does not catch up
  between them.
- Two things keep a tab switch correct:
  - A feed reset moves `_feed_generation`, and a poll answer that left before the
    reset is dropped. Otherwise `/r` showed the reply and none of the
    conversation it answered.
  - The first read after a reset replaces the screen in one render
    (`_redraw_on_next_read`), instead of landing under the old lines.

**Whispers reach you** (`_test_whispers_reach_you`). The chat window reads only
its open tab, while it is open, and the Whisper tab shows only a conversation with
a name you already typed. So a whisper sent to a player reached nobody. That was
measured: two whispers, chat shut, then open on World, and nothing anywhere.

- The broadcast poll now carries `chat_news`: the newest whisper to you (who,
  what, when), and the newest guild and friends lines by somebody else.
- `_read_chat_news()` pops "X whispers: ..." and lights the Chat button with a
  dot.
- The chat window opens on that conversation.
- Open on another tab, the Whisper tab lights and the notice says
  "X whispered you. /r to answer."
- `/r` answers whoever whispered last.
- The first poll is where "new" starts. A whisper from within
  `WHISPER_CATCH_UP_SECONDS` before logging in is still said.
- This state is static on the HUD, per login. Every area has its own HUD, and
  kept per HUD, the same whisper was said again in every area walked into.

### Characters: a load that did not arrive, and a way out of character select

From the day-1 sweep of creating and picking a character.

- **A failed load is not an empty account** (`_test_a_failed_load_is_not_an_empty_account`).
  `ServerStorage.load()` returned `{}` when the character list, a character or
  the account did not arrive, and `{}` reads as a fresh install. Reproduced
  live: the list timed out after the login, character select showed four
  empty slots, and Create over the warrior pushed an empty backpack over the
  real one - the bag was gone. Now any part failing returns `LOAD_FAILED`,
  `CharacterData.load_failed` is set, `save_data()` and `_write_save_now()`
  refuse, and the login screen stays put: "Your characters did not load...
  Press Enter Elysium to try again", which retries the LOAD (not the login -
  that would send a staff member another code).
- **Character select has a Log out button** (`_test_character_select_has_a_way_out`).
  With Remember me on, reopening the game lands there, and the only way to the
  login screen was to enter the world first. It saves, clears, signs out and
  leaves, in the HUD's order.
- An occupied slot says "Level 12" rather than "warrior | level: 12" under a
  WARRIOR heading.
- Not changed, noted: logging in always starts in town (`WORLD_AREA`); the
  saved `area` is where other players see you, not where you appear.

### Moving between areas: arrive clear of the doors, on a floor with walls

From the day-1 sweep, walking the real game from the town gate to the Crowned
and back up the ladder.

- **The boss room could not be reached.** Its arrival marker (`boss_entrance`)
  had never been moved off (0, 0), which is where its ladder up stands, so the
  arena's victory door put the winner on the exit and the ladder sent them
  back to the field. The marker is at the room's own default spot now, the
  west end of the corridor.
- **The boss room had no walls.** Its TileSet uses `underground.png`, the same
  sheet as the arena, and the arena's copy carries the wall shapes; the boss
  room's copy had none, so a player walked off the corridor into the black.
  Its atlas now has the arena's 48 polygons, tile for tile. A TileSet is a
  sub-resource of each scene, so **the same sheet in two scenes is two sets of
  collision** - painting a room from a sheet another room already uses does
  not bring its walls along.
- **The field's welcome played on every arrival**: from the town gate, the
  boss room's ladder, a revive and a staff teleport. It plays once a login now
  (`GameState.opening_story_told`, reset by `clear_current_user()`). It carries
  the credits, so it must still play once.
- `_test_every_area_can_be_walked` copies each area's tiles and static bodies
  into the tree and floods it with the warrior's own feet: every arrival must
  land clear of every door, nothing reachable may be off the map, and every
  door must be reachable from where players arrive. It found both boss room
  bugs, and it reads the doors, markers and walls off the scenes, so a new
  room is checked the day it is saved. A hole a single tile high can still hide
  between its steps; one two tiles high cannot.
- Not changed, noted: the field has no way back to town but dying or Switch.
  `leavetown.gd` says that is on purpose ("life is a gamble"). `easteregg` is
  in `AreaRegistry.AREAS` and is an empty scene with no script, so "Go to area"
  to it arrives nowhere.

### Chat safety: ignore, report, mute, the filter, new messages below

Asked for after the chat sweep, for day 1. `_test_chat_filter`,
`_test_chat_safety_menu` and `_test_staff_reports_and_mutes` hold the client;
the server's rules are in the API's CLAUDE.md, "Chat: ignore, report, mute".

- **Click a name in chat** for a menu: Whisper, Ignore, Report (five reasons),
  and for staff above that player, Mute 10 minutes / 1 hour / 1 day and
  Unmute. Not on your own name; Ignore is greyed on staff, which the server
  refuses. The name is a `[url]` in the line's RichTextLabel
  (`_clickable_name`, `_wire_name_click`), and the menu is one PopupMenu built
  on first use.
- **Commands**: `/help`, `/ignore`, `/unignore`, `/ignored`, and for staff
  `/mute name minutes reason`, `/unmute`. Anything starting `/` and a letter
  is a command and is never sent - a typo'd command said out loud in world is
  worse than it not working.
- **Ignoring takes their lines off the screen at once** (`forget_author`),
  every tab, rather than waiting for the next poll to leave them out.
- **A muted player's box says so before they type** (`_set_muted`, from the
  read's `muted`), and a send refused for it says how long and why.
- **The language filter** (`src/ui/chat/chatfilter.gd`, the `chat_filter`
  setting, on by default, in Options). Whole words and their endings only -
  "class", "assess" and Scunthorpe are left alone - with look-alike symbols
  and stretched letters caught. Display only: the server keeps what was said.
  `ChatPanel.shown_text()` is the one door, used by the log, captions and the
  HUD's whisper pop-up. The list is ROT13 in the source.
- **"New messages below"** under the log when a line arrives while the player
  is reading further up. It goes when they reach the bottom or click it.
- **Staff**: a Reports tab (one row per reported line, with who, why and how
  many; Delete line, Mute 1 hour, Dismiss, or only "Open player" for a report
  about your own rank), mute buttons and the mute's state in a player's
  Actions tab, mutes on the record, and the Staff button counts open reports
  from the poll (`_mark_open_reports`).
- **Fixed while here**: a 429 in chat showed "one picture every few seconds"
  for every kind, so typing fast was reported as a picture problem.

### Signing in, the way players will on day 1

A sweep of the login screen with the real game against the real server found
these. Each is held by a suite section.

- **Signing in never makes an account** (`_test_signing_in_never_makes_an_account`).
  The button used to register the name on a 401, so a typo in your own name
  made a new, empty account, asked for its recovery email, and every
  character was "gone". A 401 now says "Wrong name or password", and
  "Create an account" (built in code, like the staff code box) turns the form
  into sign-up with the password asked twice. It is the one `Api.register()`
  call on the screen, so its 409 simply means the name is taken.
- **Remember me means it** (`_test_remember_me_means_it`). `Api.keep_signed_in`
  comes from the box. Off, the token is never written to `session.cfg`, and
  closing the game signs you out. It used to be written either way, so on a
  shared computer the next person walked into your account. A remembered login
  that still owes a recovery address now goes in; the prompt comes back at the
  next typed sign-in.
- **One game per account** (`_test_one_game_per_account`). The server ends an
  account's other sessions on every login, and a remembered login is reopened
  through `POST /api/auth/resume`, which swaps the token, so a second copy of
  the game cannot share one either. Two games on one account lost items. The
  game left behind reads `signed_in_elsewhere` off the 401 (heartbeat or
  broadcast poll; `Api.signout_notice_for()`) and says "This account signed in
  somewhere else" instead of "signed out by the server".
- **The recovery email can wait** (`_test_email_prompt_can_wait`). The prompt
  had only Exit if a code never came. "Not now" goes into the game, and the
  prompt returns at the next typed sign-in. A server with no mail set up does
  not ask at all.
- **Smaller things.** The attempt that locks an account says so, in minutes
  (it used to be one more "incorrect password"). "Can't reach the server"
  under the button clears when the banner turns green again.

### Staff logins take a code from the email

Staff names are public (the crown, the MOD and DEV badges), so theirs are the
passwords worth guessing. For a mod, dev or the owner with a confirmed recovery
address, the server answers a correct password with **202** and emails a
six-digit code. Only the same login sent again with the code gets a token. The
server's side is STAFF LOGIN CODES in app.py and the API's CLAUDE.md.

- **`Api.login(user, password, code)` never adopts a 202.** It is a 2xx with no
  token, and adopting it would save an empty session and walk into the game
  signed in as nobody. `Api.needs_login_code(res)` is the test, for the 202
  and for a wrong code (400).
- **The login screen checks for the code step before `res.ok` and before the
  401 branch.** A wrong code is a 400 on purpose: a 401 reads as "Wrong name
  or password", and the password was right.
- **The code box is built in `loginmenu.gd`, not the scene**, right under the
  password, hidden until a 202. The same button sends the login again with the
  code. Spaces are fine ("183 774", as copied from the mail). Changing the
  username puts the box away, since a code is for one account. An empty box
  asks for a new code (the server sends at most one a minute).
- **A staff login that needed no code is told once** (`staff_unprotected`,
  `Api.take_staff_unprotected_notice()`, `_warn_unprotected_staff()` in the HUD):
  the account has no confirmed address, or the server cannot send mail.

Measured live against the real server with its mail printed to the log: the
password alone showed the box and "we emailed a code to b\*\*s@example.test"
with one mail sent. A wrong code kept the box and said so in red. The right
code, typed with a space, reached character select. `_test_staff_logins_take_a_code`
holds the client side.

### Mixed tabs and spaces inside one indent is a parse error

Godot's parser rejects a line indented with tabs and then padded with spaces —
including alignment spaces inside a `const` table, which is where it is hardest
to see. This project is tabs only. Alignment *after* the first non-space
character is fine; leading whitespace must be tabs and nothing else.

## Traps on the server side

### CREATE TABLE IF NOT EXISTS does nothing to an existing table

Adding a column to the schema block changes nothing for a database that already
has that table. A real schema change needs a migration that rebuilds it — see
`_migrate_bank_to_account()`.

This is worse than it sounds because **151 tests passed while the live server
was broken**, since the suite builds a fresh database every run and the fresh
one got the new schema. If you change a table, add a migration test that starts
from the old shape.

### Routes below app.run() never register

`app.run()` blocks. Anything defined after it is parsed and then never reached.
The entry point lives at the very end of `app.py` with a comment saying so.

### init_db() runs at import time

Helpers defined further down the file do not exist yet when it runs. Table
creation belongs in the schema block, not in a function called from it.

### Use SystemRandom for anything a player benefits from predicting

Python's default RNG is a Mersenne Twister, and its internal state is
reconstructible from 624 observed outputs. Loot rolls use
`random.SystemRandom()` for that reason.

### One rule, two validators

A rule added to one of two duplicated validators applies to one of them. The
stack ceiling was added to `_parse_positional_items()` and the backpack route
kept accepting a billion potions, because that route had its own copy of the
same twenty lines. There is now one validator and a test asserting the bank and
the backpack are bound by the same rule.

## Things that look wrong but are deliberate

Do not "fix" these.

- **`SOUNDS` in `audio.gd` is 31 empty strings.** An unassigned id is a silent
  no-op by design. That is what lets the call sites exist now and the audio
  arrive later, one file at a time.
- **Seven signals are emitted with nothing connected, and that is the
  convention, not an oversight.** `took_damage` and `xp_gained_signal`
  (player.gd), `damaged` (baseenemy.gd), `wave_started` (bossgauntlet.gd),
  `cook_requested` (firepit.gd), `cast_failed` (fishingspot.gd),
  `raised_changed` (spikedoor.gd).

  Each sits **alongside** a direct call that already does the work — the
  "signal as well as the direct call" shape `fishingspot.gd` documents at
  `_notify()`. The signal is an extension point so a quest or a tutorial can
  hear an event without the emitting script knowing about it; it is never the
  only thing that happens, which is the failure that made `cast_failed` worth
  writing about in the first place.

  **`unauthorized_seen` (api.gd) was the eighth and is now connected**, because
  it was the one entry on this list that did *not* have a direct call doing the
  work. api.gd's comment on it said "characterhud.gd answers it with an
  immediate heartbeat()", and nothing did — the sentence described a wire nobody
  had run. The cost was measurable: `/api/staff/ban` deletes the account's
  session rows in the same transaction that sets the ban, so the server revokes
  instantly, while the client only noticed on the broadcast poll. A banned player
  kept playing for up to `BROADCAST_POLL_SECONDS` (10s).

  `characterhud.gd::_on_unauthorized_seen()` now answers it, and the shape is
  worth keeping: **a 401 is a prompt to ask, not a verdict.** Changing a password
  answers 401 for a mistyped *current* password, so a client that signs people
  out on any 401 signs them out for typos. The handler calls `Api.heartbeat()`,
  `heartbeat_verdict()` decides, and only `"revoked"` acts. It is debounced,
  because chat, friends and the guild list can each 401 in the same moment, and
  `_request()` excludes `/api/auth/session` from the signal so the probe's own
  401 cannot call it back. `_test_unauthorized_is_answered()` holds all of that.

  This is **not** the `gamestate.gd` case, and the difference is the whole
  rule. Those thirteen were the sole mechanism, heard by nothing, and
  `player_moved` cost 180 emissions a second. These fire when a cast fails or
  a wave starts. A rarely-emitted signal nobody hears costs nothing; a
  per-frame one costs CPU and reads as working code.
- **Server-owned stats are ignored, not refused.** `PUT /api/player/status`
  drops `level`, `xp` and the maxima and names them in an `ignored` array. A 400
  would break every honest client, because the client sends its whole status
  block and cannot know which fields the server has taken ownership of.
- **Item ids are not whitelisted on the server.** Validating them against a list
  would mean every new item needs a matching server deploy. Unknown ids are
  bounded by `QUANTITY_CEILING` instead.
- **`_set_stat_curve()` is `pass` in `player.gd`.** All four classes override it.
- **`savestorage.gd` has one implementation.** `is_authoritative` is read by
  `characterdata.gd` to skip the anti-tamper passes, so the base class is
  load-bearing even though `LocalStorage` is gone.
- **`set_bus_volume()`, `get_bus_volume()` and `play_music()` are uncalled on
  purpose.** They are the Options screen, built ahead of its consumer.
- **`firepit.cook()`, `player.gain_cooking_xp()` and `player.gain_fishing_xp()`
  are gone.** They were all client-side versions of something the server now
  owns: `POST /api/cooking/cook` and `POST /api/fishing/catch` decide what was
  cooked or caught and grant the XP, and `PUT /api/character/skills` drops the
  cooking and fishing rows from anything the client sends. A client-side grant
  could only ever be overwritten on the next sync, so there was nothing to wire
  them to. If a display needs either number, read it back from the server.
- **The owner panel is bound to backquote, not a function key.** F1-F7 and
  F9-F12 are `player.gd`'s debug keys and F8 is Godot's own stop-the-project
  shortcut, which closed the game. It was Shift+A before that, which collided
  with normal play - `interact` is Shift and `move_left` is A, so interacting
  while walking left toggled it.
- **`Api.is_admin` is a compatibility alias, not a rank.** There is no admin
  rank; the ranks are owner > dev > mod > player. The server still sends that
  key, meaning "dev or above", because existing client code reads it. New code
  should read `Api.role` and call `Api.role_at_least()`.

## The element system

One artist's sheet becomes seven creatures. What stops that reading as seven
coats of paint is that **an element changes how a thing behaves, not just what
colour it is** — and the numbers for that live in three separate places, on
purpose, because they answer three different questions.

### Which file owns which number

| question | lives in | example |
|---|---|---|
| How hard does it hit, how much HP? | `data/enemies/<el><family>.tres` | `icebushsniper.tres`: 14 damage, 208 hp |
| How does its shot move and look? | `scene/projectiles/<el><base>.tscn` | `icearrow.tscn`: speed 320, scale 1.25 |
| What does its ground hazard do? | `scene/projectiles/<el>puddle.tscn` | `icepuddle.tscn`: 5.0s, 2 tick, scale 1.25 |
| What does the boss's spike do? | `ELEMENT_PROFILE` in `bossprojectile.gd` | ice: 1.35 telegraph, 1.25 size |

**The `.tres` is a difficulty ladder, not a personality.** Dark is the hardest
tier and light the easiest, and damage and HP both rank the same way in every
family — that is tier, and it is deliberately orthogonal to element character.
Do not encode "ice feels slow" as lower damage; encode it as lower speed.

**Do not write `damage` into a variant scene.** `spawn_projectile_node()`
overwrites it with `EnemyData.projectile_damage` whenever that is above zero,
and every variant sets it. A `damage` line in `icearrow.tscn` is a knob that
lies.

### What each element means

Consistent across every family, which is what makes it learnable — ICE means
the same thing whether it is an arrow, a vine or a boss pillar.

| element | speed | scale | reach | reads as |
|---|---|---|---|---|
| light | 1.35 | 1.00 | 0.85 | fastest thing in the game, short |
| wind | 1.30 | 0.80 | 0.80 | fast, small, gone quickly |
| dark | 1.00 | 1.00 | 1.00 | normal, and hard to track |
| fire | 1.00 | 1.00 | 1.10 | normal, leaves the ground burning |
| water | 0.90 | 1.05 | 1.25 | slow-ish, long, spreads |
| ice | 0.80 | 1.25 | 1.30 | slow, big, reaches furthest |
| earth | 0.80 | 1.35 | 0.85 | slow, biggest, short |

`lifetime` is derived, not chosen: `reach / speed`. Reach is what a player
feels; a lifetime typed in directly will contradict the speed sitting above it.

Two levers are family-specific because the others are not real there:

- **The vine is stationary**, so its lever is `impact_frame` — which of six
  animation frames lands the hit. Light 2, wind 3, dark/fire/water 4, ice 5.
  Five is the last frame and is as late as it goes.
- **Arrows and orbs are screen-bounded.** Their `lifetime` is a failsafe, not a
  range. Leave it alone; tune speed and scale.

Dark's low-visibility signature is `self_modulate` alpha `0.78` on the sprite,
and it is deliberately **not** applied to puddles. A bullet you half-see is a
reaction test; a floor hazard you cannot see is just unfair, and dark is already
the hardest tier. If dark feels cheap in playtest, that alpha is the first knob
to back off — six files, one value.

### The floor coverage budget

Read `PUDDLE_CHANCE` in `bossenemy.gd` before changing any puddle number. A
65-pillar cast every 2.16s with a 2.5s pool would cover 44% of the room in
standing hazard; the constant exists to hold the real figure near 15%.

Every element currently lands between 0% and 23%. **Area goes as the square of
scale**, which is what makes this easy to get wrong — two multipliers in that
table are compensation rather than character, and both say so in their comment:

- **water 0.5**, because `extra: 2` means three pools per roll. At 1.4 it was 54%.
- **ice 0.8**, because scale 1.25 is 1.56x the area. At 1.2 it was 35%.

`bossprojectile.gd`'s `puddle_life_scale` (0.6) is what keeps a carpet from
turning ice's five seconds into a floor with no floor left.

### Adding to it

- **A new elemental variant of an existing family** — copy the `.tres`, the
  enemy `.tscn`, and the six-per-family projectile scenes, then add the scene to
  `Projectiles.BY_BASE` and to `ENEMY_PROJECTILE_SCENES` in `testrunner.gd`.
  Drag the enemy scene into the level; the respawner takes a census of what is
  already placed, so it repopulates on its own.
- **A new element** — append to `Element.Type`, add a hue to `HUES` and a colour
  to `COLOURS` (measure it off the art if the art exists first), add a row to
  `ELEMENT_PROFILE`, then build its scenes. An element with no scene falls back
  to the base and is recoloured at runtime, so it degrades rather than breaking.
- **Two registries map base scene to variant**: `src/shared/projectiles.gd` and
  `src/shared/puddles.gd`. Both key on the base scene's `resource_path`, so an
  `@export` pointed at something custom is not in the table and passes through
  untouched. Neither can preload a scene whose script it is attached to — that
  is why they are separate files and not constants on the projectile scripts.

## Conventions

**Comments explain why, or warn about a trap.** Anything the code already says
plainly gets no comment. Reserve the long treatment for the genuine landmines
above — when every comment is an essay with a capitalised headline, emphasis
stops meaning anything and the real warnings get scrolled past.

**Game data lives in `.tres` resources**, not in literals inside scripts.
`ItemData` in `data/items/`, `EnemyData` in `data/enemies/`, `ClassData` in
`data/classes/`. `src/tools/exportgamedata.gd` writes them to
`data/gamedata.json`, which the Flask service reads — that is what lets the
server know your class's HP curve without a second copy of it.

If you change a `.tres`, re-run the exporter or the server keeps the old values.

**The client asks, it does not tell.** Anything the player benefits from lying
about goes through an endpoint. Taking an item out of a loot bag is a request;
gold and lusion balances come back as totals rather than deltas so a missed
response is corrected by the next one instead of compounding.

**Rank and ownership come from the server, every time.** `Api.role` and
`Api.is_owner` are set from the login and session responses and held in memory
only - never written to `session.cfg`, unlike `Api.is_admin`, which
`CharacterData` mirrors into `account_data` and therefore into the save. A
permission that lives in a file is a permission that can be edited.

They are still only good for hiding buttons. `require_role()` and
`require_owner()` in `app.py` are what actually refuse. The owner panel reads
`Api.is_owner` directly for that reason.

**No local fallback when the server is unreachable.** A kill that could not be
reported is a kill that did not pay, and the player is told so. Rolling loot
locally when a request fails hands the whole exploit back — a client that can
produce its own loot only has to make the request fail.

## Layout

```
src/characters/     player.gd, playerstats.gd, and warrior/mage/tank/healer
src/enemies/        BaseEnemy and its six subclasses
src/pets/           the companion system
src/projectiles/    arrows, acid, vines, slash waves, ground hazards
src/systems/        the autoloads — api, audio, characterdata, combat,
                    gameconstants, gamestate, itemregistry, scenetransition —
                    plus the save/load storage layer
src/types/          ClassData, EnemyData, ItemData, ItemStack. The Resource TYPE
                    definitions only; data/ at the project root holds the .tres
                    instances authored from them.
src/ui/             characterhud, hotbar, statsscreen, floatinglabel, storyscene
src/ui/bank/        src/ui/inventory/   src/ui/lootbag/   src/ui/menus/
src/ui/owner/       owner-only tooling, gated on Api.is_owner
src/world/          levels (elusion, field), interactables, lootbag, roofswap,
                    mapbackdrop (grey under the tiles, black past the map)
src/shared/         pure helpers used across characters, enemies and pets —
                    facing, formation, homing, safespot, and localtime, which
                    is the ONLY place unix seconds become a wall clock
src/tools/          the gamedata exporter, the test runner and the atlas
                    audit — none of them ship
scene/tests/        tests.tscn, the headless entry point for the test runner
data/items/         ItemData      data/enemies/  EnemyData
data/classes/       ClassData     data/gamedata.json  the exported contract
docs/apicontract.md   what the client and server promise each other
docs/audio.md         the 31 sound ids, where each fires, and what the suite
                      does about a registry that is half filled in. The game
                      is silent: every entry in Audio.SOUNDS is empty, on
                      purpose, and the boot log says so at every launch.
web/shell.html        the browser build's loader page (export_presets.cfg)
web/serve.py          serves an export at localhost:8060, /api/ passed through
```

**`src/` mirrors `scene/` folder for folder.** A script lives beside where its
scene lives, so `scene/ui/menus/loginmenu.tscn` is driven by
`src/ui/menus/loginmenu.gd`. Keep it that way when you add things.

When the two disagreed, `src/` was the half that moved, and that was not a
preference: 25 `preload()` calls name a path under `scene/`, against 3 that name
one under `src/`. Reorganising the other direction would have meant editing
twenty-five string literals that nothing checks until they run.

`src/enemies/baseenemy.gd` and `src/systems/characterdata.gd` carry most of the
complexity and are the best places to start reading.

## The players menu, and a switch for combat that does not exist

**Who is playing** is a nav-bar button anyone can press. It lists every online
player, their character, level and area, grouped into *"In Elusion with you"* and
*"Elsewhere"* — and the heading is built from the server's own `precision` field
rather than the word "area", so when real positions arrive the wording follows
instead of going on promising a distance nobody measured.

**Online means the heartbeat, and the token.** Both. `last_seen_at` within
`ONLINE_WINDOW_SECONDS` says a client was there in the last 45 seconds;
`expires_at > now` says the session is still allowed to be. Either alone is wrong
in a different direction, and both mistakes were made here in one afternoon:

- `/api/players/nearby` had filtered on **`expires_at` only** — a token lasts
  thirty days and survives the game being closed, so the trade panel's *"in this
  area with you"* had been listing everyone who logged in since last month.
  `ONLINE_WINDOW_SECONDS` warns about exactly this, in these words: *"NOT 'has a
  live session'… a kick list sorted by it put last week's visitors at the top."*
- The fix then used **`last_seen_at` only**, which let a revoked or expired
  session stay listed for its last 45 seconds. `test_economy.py`'s *"an offline
  player is not listed as nearby"* caught it on the next run.

**The PvP switch is real and the combat is not, and every place it speaks says
so.** It is a row in `server_settings` like the maintenance switch, set by
`POST /api/server/pvp` (owner, 404 to anyone else), announced through the same
broadcast path the shutdown notice uses — *"Tunacan has gone hostile."* /
*"Tunacan has cooled off - no longer hostile."* — and carried on `/api/status`,
which needs no token, so even the login screen can read it.

It does **not** make anybody damageable, because nothing in this game can damage
another player. The button's tooltip, the panel's banner and the route's own
`damage_implemented: false` all say that, and `_test_players_menu_and_pvp_are_honest()`
holds them to it. **A switch labelled "PvP" that implied combat would be the
`unauthorized_seen` bug with a nicer font** — a control describing a wire nobody
ran — which is the one failure this project has spent the most time removing.

**Why build the switch before the combat, rather than with it.** Because of where
it lives. "May other players hurt me" has to be answered by the **server**; a flag
in a client is a flag an attacker sets. Putting the authority in the right place
first means the damage path has something to ask when it exists, instead of
growing an answer in a hurry beside the thing that needed one.

## Decided, not built: PvP and the world boss

**The goal:** the owner flips a switch, becomes a world boss, and players can hit
him. It is a good goal. It is also **not a switch**, and the reason is worth
writing down before anybody tries.

`/api/players/nearby` already says it, in its own words:

> *There is no position on the server and no heartbeat carrying one, so "nearby"
> here means "in the same area and online" — which is the honest maximum today
> and is genuinely what a trade panel needs, because **you cannot see another
> player at all yet**.*

That is the whole answer. Players are not rendered in each other's worlds; there
are no remote bodies, no hurtboxes, nothing for a sword to overlap. A PvP toggle
today would be a control wired to nothing — the `unauthorized_seen` bug with a
button on it.

**The ladder, in the order it has to happen:**

1. **Positions on the server — there are none at all.** Not stale ones: none.
   `saves` holds `class_id`, `name`, `level`, `area` and the vitals, and **no
   coordinates**. This was got wrong here once already: a pass added `x, y` to
   the `SELECT` in `/api/staff/user` so the owner panel could stand beside
   somebody, and broke that route outright — `no such column: x`, caught by
   `test_security.py` on the next run. The `x`/`y` that do exist are on
   `pending_teleports`, which is where a teleport is **going**, not where a
   player **is**.

   So this step is a new column pair *and* a heartbeat carrying them — the first
   thing in this project that costs real requests per player per second, which is
   why it waits for the droplet's numbers. It is also why the owner panel's
   button says **"Go to area"** and not "Go to them": it travels to the room they
   are in and tells you the server does not know where in it. `SafeSpot` is
   already written and already used by the other two buttons, so the day
   coordinates exist, landing beside somebody is one line.
2. **Remote players rendered.** A body, a nameplate, interpolation between
   updates, and a decision about how many are drawn before it stops being
   affordable. `/api/players/nearby` is the seam and its own comment says so:
   *"the query gains a distance test and the response gains a position, and the
   client does not change shape."*
3. **Damage that the server decides.** This is the one that matters. If an
   attacking client says *"I hit the boss for 40"*, that is E-3 with the stakes
   raised — one modified client deletes the world boss from across the map.
   A PvP hit has to be a server event like a kill: the server holds both
   characters' stats, checks the range against positions it owns, and applies
   the damage itself. Note this needs **server-owned hp**, which today is
   client-written and only clamped (E-9).
4. **Then the switch.** Owner-only, mutually exclusive with god mode, because one
   says "nothing may hurt me" and the other says "everyone may".

**Worth knowing before starting:** step 3 is the same work that would close E-9,
and step 1 is the same work that makes E-3 closable. A world boss is not a
feature bolted onto this architecture — it is what the architecture looks like
once the two oldest open findings are shut. That is an argument for doing it, not
against it, but it is a season rather than an afternoon.

**One thing to decide early, not late:** if players can hit the owner, the
owner's `take_damage()` runs, and that grants defense XP through
`/api/skill/train`. A world boss farming defense off fifty attackers would sit at
the rate cap all day. Whatever step 3 becomes has to answer it — the same
question god mode answered by returning before the XP.

## Known gaps

- The backpack ledger is still whatever the client pushes on save.
  `POST /api/loot/take` closed where items come from, not what you claim to hold.
- ~~`has_active_revive` in `player.gd` is never set true.~~ Closed — the flag
  and its unreachable branch are gone. The real revive is `GameState.reviving`,
  set by `gameover.gd` after death. The ordering the dead branch needed is
  recorded where it was, in case a token-style revive is ever added.
- ~~`gamestate.gd` declares eleven signals that are never emitted or connected.~~
  Closed. There were thirteen, not eleven, which is its own small lesson about
  counts written down by hand. All removed — `gamestate.gd` is now the four
  transient values something actually reads. The signals are in git if
  multiplayer wants a starting point, though one designed around a real
  listener will fit better than one designed around none.
- ~~The boss scene has no script.~~ Closed — `bossarena.tscn` runs `boss.gd`,
  and the arena's portal runs `fieldportal.gd`.
- 31 sound ids, 26 wired to call sites, 1 audio file (`audio/ambience/firepit.ogg`).
  The audio is authored in-house, so the slots exist and fill one at a time.
- `ItemRegistry.FALLBACK_ITEM_ID` is `"error_item"` and no `error_item.tres`
  exists, so an unknown id returns `null` rather than a visible placeholder.
  Not a bug — but adding that resource changes what `ItemStack.from_dict()`
  returns for a bad id, so the test that covers it asserts "never that item"
  rather than "null" on purpose.
- The test suite covers agreement and arithmetic, nothing that moves.
  `player.gd`, `baseenemy.gd` and the whole UI layer are still boot-and-read.
  `baseenemy.gd` is 116KB, `player.gd` 110KB and `characterdata.gd` 65KB —
  each roughly double what this line said when it was written, which is the
  argument for the seams below rather than against measuring. The
  pure stat maths came out into `PlayerStats` and the pet mechanics into
  `PetController`; the floating-label feedback is the next seam. `player.gd`
  still owns `active_pet_id`, because CharacterData persists it per slot and
  ServerStorage puts it on the wire — moving it would mean changing the save
  format to tidy a file.
- **`ObjectDB instances leaked at exit` on every test run is expected** and has
  not been chased. The suite quits a whole project from a bare scene while the
  autoloads are mid-flight. It is noise, not a failure — but it is noise on a
  green run, which is exactly the kind of thing that trains you to skim.
