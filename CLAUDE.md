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

**The API has a test suite. Run it before and after.** The API is a separate
repository — run this from *its* folder, not from this one:

```
.\venv\Scripts\python.exe test_api.py
```

365 checks, exits non-zero on any failure. It uses a throwaway database in your
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
failure. 177 checks at the time of writing; if that number and the one in this
file disagree, this file is the stale one. It covers what can be checked without playing: the XP curve, the shared
constants and class stat curves, `ItemStack`'s save round trip, and the rank
ordering.

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

### Seven copies of the four-direction rule are still out there

`Facing` (in `src/shared/`) owns the rule that turns a Vector2 into "up",
"down", "left" or "right". `baseenemy.gd` uses it. **`player.gd`, `warrior.gd`,
`mage.gd`, `tank.gd`, `healer.gd` and `pet.gd` still have their own copies** —
seven in total, all spelled `if abs(dir.x) > abs(dir.y)`.

They have already drifted, and it is worth knowing which way. The enemy version
returns `""` for `Vector2.ZERO`; the player and class versions fall through to
their `else` and return `"up"`. A still enemy faces nowhere, a still character
faces up, and nobody chose that.

Both behaviours are right for their caller, which is why `Facing` has two
entry points rather than one winner:

- `from_vec()` — `NONE` when there is no direction. Navigation needs "no
  heading" to be a real answer rather than a coerced `"down"`.
- `from_vec_total()` — always a direction. There is no "no animation" to play,
  so a still sprite has to idle facing somewhere.

The remaining seven are animation-name mapping (`"walk" + direction`), so
converting them is an eight-file change through code that has no tests. Worth
doing; not worth doing by accident.

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

Which files are which is not guessable, so grep before you move anything:

```
rg -o 'type="Script"[^]]*' --glob '*.tscn' --glob '*.tres' | rg -v 'uid='
```

At the time of writing that returns three groups, all path-only:

- `data/enemies/*.tres` → `enemydata.gd` (6)
- `data/classes/*.tres` → `classdata.gd` (4)
- the crypt light scenes → `world/lightflicker.gd` (6), and one to
  `projectiles/acidpuddle.gd`

`data/items/*.tres` are editor-saved and carry uids, which is exactly why this
cannot be reasoned about from the folder name.

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

- **`SOUNDS` in `audio.gd` is 27 empty strings.** An unassigned id is a silent
  no-op by design. That is what lets the call sites exist now and the audio
  arrive later, one file at a time.
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
- **`cook()`, `gain_cooking_xp()`, `gain_fishing_xp()`, `set_bus_volume()`,
  `get_bus_volume()` and `play_music()` are uncalled on purpose.** They are the
  cooking system and the Options screen, built ahead of their consumers.
- **The owner panel is bound to backquote, not a function key.** F1-F7 and
  F9-F12 are `player.gd`'s debug keys and F8 is Godot's own stop-the-project
  shortcut, which closed the game. It was Shift+A before that, which collided
  with normal play - `interact` is Shift and `move_left` is A, so interacting
  while walking left toggled it.
- **`Api.is_admin` is a compatibility alias, not a rank.** There is no admin
  rank; the ranks are owner > dev > mod > player. The server still sends that
  key, meaning "dev or above", because existing client code reads it. New code
  should read `Api.role` and call `Api.role_at_least()`.

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
src/tools/          the gamedata exporter and the test runner — neither ships
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
- `has_active_revive` in `player.gd` is never set true. The branch it guards
  cannot be reached; the real revive is `GameState.reviving`, set by
  `gameover.gd` after death.
- `gamestate.gd` declares eleven signals that are never emitted or connected.
- The boss scene has no script.
- 27 sound ids, 20 wired to call sites, 0 audio files.
- `ItemRegistry.FALLBACK_ITEM_ID` is `"error_item"` and no `error_item.tres`
  exists, so an unknown id returns `null` rather than a visible placeholder.
  Not a bug — but adding that resource changes what `ItemStack.from_dict()`
  returns for a bad id, so the test that covers it asserts "never that item"
  rather than "null" on purpose.
- The test suite covers agreement and arithmetic, nothing that moves.
  `player.gd`, `baseenemy.gd` and the whole UI layer are still boot-and-read.
  `player.gd` is 60KB, `characterdata.gd` 52KB and `baseenemy.gd` 48KB. The
  pure stat maths came out into `PlayerStats` and the pet mechanics into
  `PetController`; the floating-label feedback is the next seam. `player.gd`
  still owns `active_pet_id`, because CharacterData persists it per slot and
  ServerStorage puts it on the wire — moving it would mean changing the save
  format to tidy a file.
- **`ObjectDB instances leaked at exit` on every test run is expected** and has
  not been chased. The suite quits a whole project from a bare scene while the
  autoloads are mid-flight. It is noise, not a failure — but it is noise on a
  green run, which is exactly the kind of thing that trains you to skim.
