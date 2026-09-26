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

454 checks, exits non-zero on any failure. It uses a throwaway database in your
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
failure. 636 checks at the time of writing; if that number and the one the suite
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

- `.size()` is the number of cells, never an item count.
- An empty array is a legitimate state, not a corrupt one. `gameover.gd`
  assigns `[]` outright when you decline a revive, and a fresh character starts
  the same way.

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

The second instance was found while fixing the first: `art/thirdparty/` holds
tilesets `split_art.ps1` itself calls "of unconfirmed origin", and the catch-all
in `assetlicense.md` — everything under `/art` except the item art — was
claiming them. One of those files, `houses read to use.png`, is drawn by
`scene/walls/shop.tscn`, so it ships. `assetlicense.md` now has a third section
claiming it for nobody and asking whoever recognises it to get in touch.

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
| present | 636 passed, 0 failed | 0 |
| absent | 604 passed, 0 failed, 12 skipped | **0** |

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
- **Eight signals are emitted with nothing connected, and that is the
  convention, not an oversight.** `took_damage` and `xp_gained_signal`
  (player.gd), `damaged` (baseenemy.gd), `wave_started` (bossgauntlet.gd),
  `cook_requested` (firepit.gd), `cast_failed` (fishingspot.gd),
  `raised_changed` (spikedoor.gd), `unauthorized_seen` (api.gd).

  Each sits **alongside** a direct call that already does the work — the
  "signal as well as the direct call" shape `fishingspot.gd` documents at
  `_notify()`. The signal is an extension point so a quest or a tutorial can
  hear an event without the emitting script knowing about it; it is never the
  only thing that happens, which is the failure that made `cast_failed` worth
  writing about in the first place.

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
src/world/          levels (elusion, field), interactables, lootbag, roofswap
src/shared/         pure helpers used across characters, enemies and pets
src/tools/          the gamedata exporter, the test runner and the atlas
                    audit — none of them ship
scene/tests/        tests.tscn, the headless entry point for the test runner
data/items/         ItemData      data/enemies/  EnemyData
data/classes/       ClassData     data/gamedata.json  the exported contract
docs/apicontract.md   what the client and server promise each other
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
