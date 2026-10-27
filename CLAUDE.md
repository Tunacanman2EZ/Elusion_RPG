# Working on Elusion RPG

Read this before changing anything. Everything in it cost real hours to learn,
most of it twice.

Elusion RPG is a top-down 2.5D action RPG in Godot 4.7 / GDScript, backed by a
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

**The suite is a chain of scripts (0.85.0).** `src/tools/testrunner.gd` holds
only `_ready()` and `_run_all()`; it extends `testrunner_8.gd`, which extends
`testrunner_7.gd`, and so on down to `testrunner_base.gd` (the counters,
`check()`, `section()`, every shared helper and constant). All of it is one
node, so every test sees every helper. A new test goes in the last part (or a
new `testrunner_9.gd` that `testrunner.gd` extends once a part passes about
250 KB); a test may call only a test in its own part or an earlier one, and a
helper goes in the base. A scan of the game's code leaves the suite out with
`_is_suite_script()`. It was one 2 MB file - slow to copy and costly to edit,
and running a few tests meant editing that file.

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

**`_test_placed_nodes_are_not_drawn_from_the_origin()` holds every script to
it (0.72.2):** a node given to `add_child()` and then a `global_position` or
`global_transform` in the same function must be reset after the last of them.
It was written after the owner's video of a Big Field fight showed white discs
out in the black past the walls, one frame each, somewhere new each time - what
he had been reporting as "white bullet projectiles from warrior fling in the
black of the map ... spraying across the map" and "projectiles are still flying
through walls". They were the sword's strike flash (`strikefx.gd`): placed at
the blow and never reset, so its one bright frame was drawn part way along the
line from the area's origin, which in the Big Field is up and left of every
fight. The healer orb's splash, a blast's scorch, crater or frost mark and the
boss's stalker did the same. A test cannot see a drawn frame; the scan is what
keeps the next one out.

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
**Bring here**, **Go to**, **Bring everyone** - and since 0.7.4 a list of who is
online under them (see "Move Players" below).

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

**"Go to" sends no request, and lands beside them.** Position is
client-written, so moving yourself is a local act; asking permission would be
theatre - and `/api/staff/teleport` runs through `can_act_on()`, which is
strictly-greater and so refuses acting on yourself anyway. The server knows
only the AREA a character is in (`/api/players/online`), so the panel travels
there with `AreaRegistry.go_to()` - but it asks `Presence.meet(name)` FIRST,
because the change of area frees the panel. The presence link draws everyone in
your area where they stand; once their picture appears, `meet()` puts you beside
it with `SafeSpot.find(me, them, 1)`, and gives up after `MEET_SECONDS` (10)
with a notice over your head rather than moving you later. No presence server,
or they are not drawn: you arrive at the area's entrance, as before 0.7.4.

**"Bring everyone" is armed-then-confirmed**, like a ban. It moves every account
on the server and posts a broadcast; it is the widest button on the panel.
`_button_for()` has an `"everyone"` entry so `_disarm()` can put the label back —
without it the button reads `Confirm?` for ever after a timeout, which is the
trap `ARM_SECONDS` exists to prevent.

### Move Players: a name box, the list of who is online, and Go to beside them

The owner, 6 Oct (0.7.4): "pick who from a list", "go to lands next to them",
"its own name box", and Bring everyone stays the whole game. The row read the
name box at the top of the Account tab ("MOVE PLAYERS - USES THE NAME ABOVE")
and "Go to area" left you at the room's entrance.

- **Its own name box** (`%movenameinput`), Enter brings them, beside **Bring
  here** and **Go to**. The head row says how many are online and holds
  **Refresh** and **Bring everyone**.
- **The list** (`%onlinelist`): `GET /api/players/online` - account,
  character, level and area, you left out - each row with its own Bring and Go
  to; clicking a name puts it in both name boxes. Asked on every open and on
  Refresh, never polled, so it does not reorder under the mouse. It is the only
  thing in the panel that scrolls (the window test allows exactly that one), and
  the tabs now grow with the window, so a taller panel shows more of it.
- **Go to lands beside them** through `Presence.meet()` - section above.
- **And the server hears your area when you arrive** (`CharacterData.note_area()`,
  from `AreaRegistry._on_scene_changed()`). It used to ride along with the next
  save, so somebody who arrived and stood still stayed, on the server, in the
  area they had left: the Players list showed the wrong room and Go to went
  there and found nobody. Found playing two games. The arrival save sends
  `WorldMap.to_save()`, not the slot's own copy of the map: that came back from
  the server as JSON, every number a float, and the save route refuses sizes
  that are not whole numbers - the first version of this saved 400 on every
  retry.

`_test_move_players_from_the_list()` drives the list, the name box, Enter,
Bring everyone's confirm, Go to's refusals, `meet()` (beside, not on top; waits;
gives up) and `note_area()`.

### Give item and Save history: a player's bag, and their character as it was

The owner, 6 Oct (0.7.5), after asking for a "secure game control panel":
"we can skip read me but roll back and give player item might be useful". So
no exploit-demo scene; these two, both owner only, both on the server
(`require_owner`, a bare 404 to everyone else - the API's CLAUDE.md, "Save
history, rollback, and giving a player an item", and `test_rollback.py`).

- **Two buttons beside View account** on the Account tab (`%givebutton`,
  `%historybutton`, in View account's row, so the tab is no taller), both about
  the name in `%usernameinput`. They open windows the HUD owns, through
  `open_window` (a Callable the suite swaps): `open_item_spawner_for(name)` and
  `open_save_history(name)` on the HUD, owner-gated there as a courtesy.
- **Give item is the item catalogue with a Give to box** (`%givetoinput`).
  Empty, or your own name in any case, is your own bag exactly as before. A
  name sends `username` and no slot - the server puts it in the character they
  are PLAYING, which only it knows - and nothing is adopted or put on here:
  "put gear on" is about your own character. The line says who got what and
  whether their game is told now or at their next sign-in (`gift_line()`).
- **Their game is told by the server**, on the broadcast poll it already runs:
  the bag arrives as a trade's does (`trade_resync`), with `gifts` - who gave
  what - and the HUD says one line per gift, "boss gave you 2 × Large Health
  Potion." (`characterhud.gd::gift_line()`, in `_on_carry_adopted()`). A game
  from before 0.7.5 says its old "Your backpack was updated by the server".
- **Save history** (`src/ui/owner/savehistory.gd`, the twentieth window - in the
  HUD's `_escape_windows()` and `WINDOW_PANELS`): the name, which of their
  characters (starting on the one they are playing), the character as it is
  now, and its snapshots newest first - when, level, gold, cells carried, and
  "before a gift" or "before a rollback" when it was not an ordinary save. The
  server keeps the last 20, taken when the game saves (at most every ten
  minutes, and only if something changed), before a gift and before a
  rollback.
- **Restore asks twice**: the first press makes that row's button "Sure?" for
  `ARM_SECONDS` (4), the second sends `POST /api/staff/rollback`. Another row,
  a reload, the x or Escape disarms. A timer, not `_process`.
- **What a rollback does to them**: level, XP, gold (through the ledger), gear,
  the pet if still held, the whole bag and every skill go back; the bank,
  lusions, area and map do not; hp and mana only come down. Every session of
  theirs ends, so their game goes to the login screen ("You were signed out by
  the server.") and loads the restored character at sign-in - nothing less
  replaces the game's own copy of level, gold and gear. Rolling back your own
  character signs you out too, and the line says so. The window's answer says
  what changed, and the list's new top line ("before a rollback") undoes it.
- **The honest limit** is written under the buttons: an item they have traded
  away since comes back as a second copy.

`_test_give_and_save_history()` holds the catalogue's Give to, the GM panel's
buttons, the window (rows, characters, arming, the request, the reload, the
refusals) and the HUD's gift lines. Played with two games against the local
server: the owner gave caster's mage two Large Health Potions, caster's game
said "boss gave you 2 × Large Health Potion." within a poll, the owner restored
the "before a gift" snapshot, caster's game went to the login screen, and
signing back in showed the bag without them.

### God mode is the owner's switch, and the ordering is the whole feature

The God mode switch on the owner panel's Testing tab turns damage off so the
game can be tested without dying a hundred times.
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

**The owner's, since 0.7.1.** The threshold is `Api.GOD_MODE_MIN_ROLE`: one
statement of the policy, which the suite asserts instead of a second copy. It
was `"dev"` while Ctrl+G was a dev's way in; the debug keys went in 0.7.1 (see
"There are no debug keys" below), and the switch is the only way in now, so the rank says what
is true. **The owner panel opens for `Api.is_owner` only** and must stay that
way - it also holds the maintenance switch and the gold grant. The switch
re-reads `GameState.god_mode` on every open with `set_pressed_no_signal()`, and
re-checks the rank in its handler too: a disabled button is a look, not a
permission. `take_damage()` re-reads the rank on every hit as well, so the flag
alone is never the authority.

`/api/staff/powers` lists it under the owner, marked client-side (it was under
`dev` until 0.7.1).

**It gives an attacker nothing.** `hp` is client-written and only clamped
server-side (E-9), so a modified client could always refuse to die. The gate
keeps an *honest* build honest, which is all a client-side gate can buy.

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

### There are no debug keys; the owner panel does their work

The owner, 6 Oct (0.7.1): "remove debug keys i have a full menu to debug".
F1-F7 and Ctrl+P O I U Y T B R K M granted items, pets, lusions, a fishing kit
and cooked fish, and drained mana, in a debug build; Ctrl+G switched god mode;
backslash showed the performance readout ("add to menu instead and remove
backslash"). All of it is on the owner panel (backquote) now:

- **Items, pets, the fishing kit, cooked fish:** Give item, or the Item
  catalogue. The same `POST /api/staff/grant` the keys called, which the
  server answers for the owner alone.
- **Level and skills:** Set level, Set skill.
- **God mode:** the switch on the Testing tab (section above).
- **The performance readout:** the Performance readout switch, through
  `PerfOverlay.set_shown()`. It works in an exported build too now - the panel
  is the gate, so it no longer needs a debug build to keep it from players.
  **Since 0.63.0 it reads a crowd too** (the owner, stress testing the Big
  Field: "i need to upgrade the performance read out"): `hitches` - frames
  over 25 ms since it was switched on, out of how many; `physics` - the tick
  against its 12.5 ms budget (80 ticks a second), and its worst; `process` -
  the rest of the frame, **scripts and drawing** (Godot's TIME_PROCESS is
  measured round the whole idle step, the draw included - 0.63.0 called it
  the scripts alone, which was wrong), and its worst; `monsters` - how many are in the
  area, awake and asleep (enemysleeper.gd). Switching it on starts every
  worst and count again. `_test_the_readout_counts_a_crowd()` holds it.
  **Since 0.69.2 it says when the game is held** (the owner's 8x screenshot:
  fps 15, frame 66.67 ms, 64% of frames hitching - and physics 0.75 ms a tick,
  process 9.5 ms; the window was in the background or the screen resting, so
  `Settings.BACKGROUND_FPS` held it). The fps row reads "held at 15: the game
  is in the background - click it" or "the screen is resting - press a key"
  (`Settings.held_reason()`); held frames count in no worst and no hitch;
  `busy` is the frame's own work (process plus the physics ticks it ran)
  and `gpu` the graphics card's (the viewport's measured render time, "not
  measured" where the renderer cannot say), both true while held. And the
  screen does not rest while the readout is up: it is for watching hands off.
- **The stress test (0.65.0):** "Stress test: Big Field monsters" on the
  Testing tab - Off, 2x, 3x, 4x, and since 0.65.1 6x and 8x (the owner, 21
  Oct: "first we need to stress test the game with 2x the enemies in big
  field"; he chose this over putting them in the scene for everybody; after
  4x, "we can add even more i think"). `src/world/stresscrowd.gd`,
  added to every area by AreaRegistry like the sleeper, acts only in the
  Big Field: beside each authored monster, (n - 1) copies of its own scene
  and leash, on the floor 20 to 56 px away, none within 400 px of the
  arrival. **Built by the clock** (0.65.1): each frame builds or frees
  copies until `BUILD_MS` (3 ms) is spent - it was 24 a frame, and the
  owner's 4x run opened with 111 hitches and a 66 ms frame from the building
  alone. 8x takes several seconds to fill in. **Born asleep** when further
  than the sleeper's SLEEP_DISTANCE from every player, so a thousand new
  monsters are not all awake for the sleeper's first quarter second.
  **A copy is this game's alone and worth nothing**: `get_enemy_id()` is
  "" for it (no kill report - no XP, no bag, nothing for the kill ceilings
  or killwatch.py), monstersync.gd never numbers it (no other game and not
  the server's books hear of it), the respawner's census skips it (it
  brings its own back after its monster's wait), and a big slime's copy
  splits into copies. Survives walking between areas; off after a restart.
  `_test_the_owner_stress_crowd()` holds it.
- **What the stress test found, and what was done (0.66.0)** - the owner,
  after a 4x run: "incredible lets refine so it runs smooth as butter".
  Measured in the container on a bench (the Big Field at 4x, 1,470 monsters,
  about 790 awake round one god-mode warrior holding attack):
  - **Threat rings worked themselves out every frame**: 5.7 of 9 ms of
    scripts. Now `ThreatRing.REFRESH_SECONDS` (0.05) while the monster is
    after somebody and `IDLE_REFRESH_SECONDS` (0.25) while not, each ring at
    its own moment, and at once when `BaseEnemy.engaged` changes (its setter
    calls `look_now()`). Scripts went to about 5.8 ms.
  - **Nothing could be drawn together**: every ring, aim ring and recoloured
    monster had a material of its own (863 draw calls at 4x). Now one
    unshaded material for every ring (`RangeRing.unshaded()`), one recolour
    per profile and element (`BaseEnemy.element_material()` caches them -
    nothing writes to them after), aim rings drawn as `draw_multiline` like
    range rings, and a monster's rings on the floor at `ThreatRing.FLOOR_Z`
    (-1), its ball still at z 1. **A boss's rings stay at z 0** - the crypt
    arena's dais is on `grounddecals` at z 0 and would cover them. 605 draws.
  - **A parked monster slid every frame.** Every monster move goes through
    `BaseEnemy._slide()`: with no velocity it slides every
    `STILL_SLIDE_SECONDS` (0.2) instead - still enough to ease out of an
    overlap. Physics about 12 ms -> 9.6.
  - **Sleepers are hidden too** (enemysleeper.gd `put_to_sleep()`): at
    1,100 px they are never on screen (the widest view is 640 x 360), and the
    renderer stopped sorting 1,100 of them. Woken, shown as they were. When
    the player jumps more than `JUMP_DISTANCE` (150 px) in a frame the
    sleeper checks at once, so nobody walks out of a door into hidden
    monsters.
  - **Awake is not busy: the near ones doze.** Of 790 awake monsters at 4x,
    about 700 stood at home with nobody in reach, and their brains were 2.7
    ms of the 9 ms tick (measured by switching them off). Each sleeper pass
    sets `BaseEnemy.dozing` on a monster at home, not after anybody, with
    nobody within `notice_reach() + DOZE_MARGIN` (150 px - more than a
    player covers between passes), and `_dozes()`, first thing in its brain
    (BushMage's own too), skips the tick. Being hit, walking home or moving
    at all rouses it that tick. Physics at 4x about 8.3 -> 6.9 ms.
  - **What is left is the fight itself.** With every monster's brain
    switched off, physics at 4x is 1.4 to 2.3 ms - the 5,600 collision
    pairs are cheap. The rest is the brains of the monsters fighting:
    steering, separation and sight queries (about 1 ms each; changing them
    changes how a pack moves) and slides through a crowd. Left alone, as are
    health bars (about 300 draws; batching them means drawing them over
    walls, or showing fewer - the owner's call).
  - **8x is still over budget** in the container: 2,944 monsters, 1,580
    awake, physics 21 to 24 ms a tick against 12.5, so Godot runs several
    ticks a frame to catch up. 4x is comfortably inside it.
  `_test_a_big_fight_is_cheap()` holds all of it.
- **A crowd thinks in turns (0.67.0)** - the owner: "we can make it even
  faster but i need ideas it can almost handle x8", choosing the changes
  nobody can see, and "All of these try to keep the feel first, before
  changing fight rules". Timed piece by piece at 8x, the ~200 monsters
  fighting were 13 ms of the tick: slides 4.7, crowd work 3.5, sight 2.4.
  - **Sight remembered** (`_has_line_of_sight()`): one query object, moved,
    and the last two answers kept for `SIGHT_REUSE_TICKS` (8, 0.1 s) while
    both ends stay within `SIGHT_REUSE_PX` (4). 2.4 -> 0.7 ms.
  - **Crowd work on a stride, in distance bands** (`think_stride()`,
    `_due()`): who is near (`_find_neighbours()`, the shape query) and a
    slot's correction off the walls are redone every tick within
    `NEAR_BAND` (80 px) of the target, every 2nd tick within `MID_BAND`
    (200), every 4th further out, each monster on its own `_phase`. In
    between it reads the same neighbours where they stand now. Movement,
    decisions and timers still run every tick. At 8x most fighters stand
    120 to 200 px out. `clamp_to_navigation()` asks the map for its regions
    once a tick (`_map_has_regions()`), not once a call.
  - **Two slides a tick** (`MAX_SLIDES`), not Godot's four: slides 4.7 ->
    3.4 ms at 8x. The player keeps four.
  - **A dozer off screen stops** (enemysleeper.gd `view_rect()`): outside
    this game's view plus `VIEW_MARGIN` (96 px) it is `PROCESS_MODE_DISABLED`
    but still drawn, so nothing of it runs. Anything that rouses it (a hit
    through the `engaged` setter, somebody in reach, the sleeper switched
    off) restores it at once; never a shared monster another game runs.
  - **A disabled monster has no body in the physics world** - Godot's
    `disable_mode` default is `DISABLE_MODE_REMOVE`. The sleeper's notes said
    a sleeper kept its collision; measured in 0.67.0, it never did. Stopped
    dozers are the same, which took the 8x collision pairs from 20,000 to
    4,000.
  - **Measured** (container, 3 runs each, holding attack, noisy +-3 ms):
    8x physics 29.7 -> 21.1 ms a tick, frames 184 -> 125 ms, worst 254 ->
    178 ms; 4x physics 11-13 -> 7-10 ms, worst 41-52 -> 18-29 ms, hitches
    2-9 -> 0-1. **Thinking at 40 Hz** (fighters deciding every other tick,
    sliding every tick), tried on the bench only: 21.1 -> 19.4 ms more.
    **Attack turns are the next step only if 8x still needs it on the
    owner's PC** - his numbers first.
  `_test_a_crowd_thinks_in_turns()` holds it.
- **The crypt crowd (0.68.0)** - the owner's 8x video of 0.67.0: 60 fps in
  the open, 8 fps among the crypt's skeletons. Physics 13 to 18 ms a tick
  on his PC against 12.5, and once a tick runs over Godot runs extra ticks
  to catch up (up to 8 a frame), so frames reached 125 ms. On the bench at
  the hall door (1000, 180) the tick was 71 ms, and most of it was not the
  crowd:
  - **The place search** (`_ensure_slot_claimed()`): 160 skeletons without
    a place in the 40-place ring searched every tick (18.6 ms). A monster
    with no place now looks every `SLOT_RETRY_SECONDS` (0.1, jittered);
    giving one up (`_release_slot()`) means looking again at once.
  - **Places inside walls** - round a player in a corridor that is half the
    ring, and those places never fill, so every searcher asked the navmesh
    about them. `_slot_in_wall()` asks once a tick per place, per player
    position (to the pixel) and navigation map, for everybody.
  - **Routes** (`_heading_vector_to()`): `NavigationAgent2D` plans a whole
    new path every time `target_position` is SET, even to the same point.
    Behind walls every skeleton did that every tick (9 ms). Now only when
    the target has moved more than `REROUTE_PX` (8, the agent's own arrival
    distance).
  - **Measured** (container, 3 runs each): the hall at 8x 63 -> 34 ms a
    tick, frames 385 -> 210 ms; the open field unchanged (about 23 ms -
    there the cost is the fighting itself). Tried and not worth it: hurtbox
    monitoring off, monsters' physics interpolation off.
  `_test_the_crypt_crowd_is_cheap()` holds it.
- **A crowd waits its turn (0.73.0)** - the owner, of the 8x stress test:
  "my pc fires up a bit and some lag is going on ... you would think on
  regular absolutely nothing would lag", and "im open to real solutions".
  Timed function by function at the hall door (1000, 180), 8x: of the
  monsters' 14 ms a tick, 10 was the ~150 with no place in the ring, and
  most with a place stood more than 48 px from it - a jam in the doorway,
  every one still steering round its neighbours and sliding into their backs
  every tick (about 80 us each) to move nowhere. Measured and not worth it:
  hurtbox monitoring off, navigation agents off, dozers' brains off,
  physics interpolation off - all inside the bench's noise.
  - **In a jam, it waits** (`baseenemy.gd`, IN A JAM, IT WAITS ITS TURN):
    `_note_headway()` adds up how far each chase step went *toward* where
    the monster is going; under a quarter of what its speed would cover
    over `QUEUE_AFTER_SECONDS` (0.25), with another monster pressed round it
    (`_crowded()`, the neighbours it last looked for), it stands still facing
    that way for `QUEUE_SECONDS` (0.45, jittered), about 5 us a tick instead
    of 80. Shoved sideways round a crowd counts as no headway; chasing a
    player who runs counts in full; a wall with nobody near is left to the
    old escalation in `_record_nav_movement_result()`. Every `QUEUE_TRIES`-th
    (3rd) wait in a row it also gives its place up (`_release_slot()`), so
    a jam still breaks. Attacks come first in the brain, so a monster in
    reach never waits.
  - **A place in one pass** (`_ensure_slot_claimed()`): no dictionary per
    free place and no sort - the lowest score that clears the margin, the
    wall asked only for a place that would win. `Formation.ring_list()` and
    `bearing_list()` hold every place's ring and bearing. The same answer as
    the sort, held by a 60-crowd comparison in the test.
  - **Seven rings were tried and were slower** (181 places for the 8x crowd's
    200): the outer places lay behind the jam and in the crypt's walls, and
    their holders walked at them. `RING_COUNT` stays 3.
  - **Measured** (container, headless, holding attack, 2 runs each): the
    hall at 8x, frames 145 and 132 ms -> 7.5 and 7.4, hitches every frame ->
    6 of 1,334 and 3 of 1,347, physics 25 to 35 ms a tick -> 11 to 13; the
    open field at 8x, frames 18 and 14 ms -> 9.0 and 9.5, hitches 137 of 558
    and 109 of 741 -> 32 of 1,108 and 42 of 1,055; the hall at 4x, physics
    8.1 -> 5.1 ms; 1x unchanged (frames held at 6.9 ms either way).
  `_test_a_crowd_waits_its_turn()` holds it.

`player.gd` reads no keys of its own any more (it has no `_unhandled_input()`),
and `perfoverlay.gd` none either. **A new testing power goes on the panel, not
on a key** - `_test_no_debug_keys_the_panel_does_it()` fails on a function key,
backslash or a debug-key helper in any script, and on a key handler back in
`player.gd`.

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

**The suite reaches a new class by path, so it does not wait on the rescan.**
On day 2 the owner's checkout had last been scanned before `itemspawner.gd`
arrived, and `testrunner.gd` naming `ItemSpawner` made the whole suite fail to
compile: a hang with no output, the trap described further down. The game ran
fine, because nothing else names the class. `_test_the_item_menu` now does
`const Spawner := preload("res://src/ui/owner/itemspawner.gd")`, which resolves
by path whatever the cache says. Do the same in the suite for any class newer
than the last editor scan.

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

### Shadowing a member of the same script (0.64.0)

The same warning one step closer: a local, `for` or parameter with the name
of a `var`, `static var` or `const` the script itself declares. The owner's
editor showed four at once - "The local function parameter "path" is
shadowing an already-declared variable at line 55" - settings.gd's own
`static var path` (where the options file is kept) hidden by locals called
`path` in four functions. Renamed (`file_path`, `script_path`,
`override_file`); the scan that found them found two more, a parameter in
optionsscreen.gd hiding its `frame_cap` picker and a `var skipped` in the
suite hiding its own count. Editor warnings never reach a headless run, so
`_test_nothing_shadows_its_own_members()` scans for them.

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
is missing. It does not cover a typo in the middle of one: GDScript has no
exception to catch, so the section cannot carry on past the bad line.

**But the run can count it, and now it does.** Godot 4.5's `Logger`
hears every error the engine reports. `_watch_script_errors()` adds a
`ScriptErrorCounter` before the first section, and `_report()` turns any SCRIPT
ERROR in the run into the failed check "the run raised no SCRIPT ERROR", with
the first few `file:line` locations. A `push_error()` that a check provokes on
purpose is not a script error and does not count. It took a second miss to
build: on 4 Oct a trade test still called `_adopt_refusal()` after that
function was deleted, the summary read green, and the state it left behind put
five more SCRIPT ERRORs into later sections. That batch's "0 failed" was not
true, and nothing said so.

The convention below still stands, because the counter says THAT a section
died and the convention says WHICH checks went with it:

- **Every section ends with a `print()` line summarising it.** That line is not
  decoration. It is the marker that says the function reached its end, and a
  section header in the output with no closing line under it is a section that
  died.
- **Read the output when you add a check, not just the total.** The total went
  *up* on the run that lost two checks, because the section before it had
  gained some.
- **`SCRIPT ERROR` in a green run is a failure**, whatever the last line says.

### A font with no glyphs of its own draws on Windows and not in a browser

The town sign said "Goal: slay the Crowned" in the desktop game and showed a
row of boxes with hex numbers in them on play.elusionrpg.com - 47 6F 61 6C, the
letters' own codes. Its label pointed at a `FontFile` embedded in `sign.tscn`
with no font data at all (the inspector's "New FontFile", never loaded). On a
desktop Godot borrows a system font for every glyph a font lacks, so nobody
saw it; a browser has no system fonts to borrow. The label now inherits the
theme's font. `_test_every_font_draws_without_the_os()` fails on any empty
`FontFile` in a scene or resource, and checks every letter on the sign is in
the font it resolves to. A `SystemFont` (the chat's) is fine: Godot documents
that it falls back to the default theme font where there are no system fonts.

**A letter the font does not have is the same bug, one character at a time.**
6 Oct: a box with a code in it before every name in the Staff window on the
web. The online dot was the letter ●, and the game's font - Godot's built-in
Open Sans, with no theme or project font set - has no ●, nor ○, ▸, ▾, ♛, ◆, ✓
or →. They were in the Staff, Friends, Guild and Trade windows. They are
drawn now, by `src/shared/marks.gd` (a few rows of pixels each, cached per
colour, `make()` for a TextureRect, `texture()` for a Button's icon), and
`_test_every_ui_character_is_in_the_font()` reads every double-quoted string
in `src/` and `scene/` - comments and docstrings left out, `src/tools/` too -
and fails on any character `ThemeDB.fallback_font` cannot draw. Before using a
symbol in a string, ask the font: `ThemeDB.fallback_font.has_char(ord)`. The
ones it has include • · — – … × » « › ‹ °.

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

**A full death takes what is worn too** (day 2, the owner: "gear is not
dropping on full death"). It never had: the respawn took the bag and the purse
and left every worn piece on. His call: worn gear goes with the bag, and
nothing is exempt, mythic weapons included. A paid revive keeps everything; the
bank is the one thing a full death cannot reach.

- The server empties `saves.equipment` in the same transaction, refills to the
  **bare** maxima (a Vitality amulet's ceiling goes with the amulet), and
  answers `gear_lost`. `/api/save` already ignored client equipment, so a save
  built before the death cannot dress the character again.
- `_clear_carry_on_death()` mirrors it: no equipment. (It also used to set the
  bag's `based_on` base, for the "inventory:0 rejected" warning the owner
  found; saves carry no bag now, so there is no base to set - see "The bag is
  the server's".)
- The return button's tooltip says what it costs.

`_test_death_reaches_the_server` holds the client half; the API's
`test_gearbonus.py` ("ACCEPTING DEATH TAKES EVERYTHING WORN") the server's.
Played: a level 22 warrior in five ember and mythic pieces died in the field,
accepted it, and came back in town wearing nothing, on 432 of 432 health, with
no warning in the log.

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
force **now**, DST included. **Since 0.11.2 a browser does better**: the web
build asks JavaScript for the offset in force *at each timestamp*
(`LocalTime.bias_minutes_at()`, kept by the quarter hour), so a notice from
before the clocks changed reads the hour it was. **A desktop still cannot** -
there is no timezone database to ask - so there a stamp from the other side of
a change is an hour out, a week-old broadcast twice a year. The system offset
is re-read once a minute (`BIAS_REREAD_MSEC`): it used to be read once and
kept, so a game left running across the change showed the old hour until it
was closed.

**Leap years and the calendar** (the owner, 7 Oct: "lets make sure my game
accounts for leap year etc"). Nothing in the game or the server counts days in
a month or in a year:

- **Every time is unix seconds**, stored and sent, and **every duration is
  seconds** - a ban of N days is N x 86400 seconds, a trade hold 48 hours, a
  trusted computer 30 days, "3 days ago" - which no leap year changes. SQLite
  is never asked a date question. The server writes a date into text in one
  place a player could see - a rollback's line in the staff log, labelled UTC -
  and its scripts (killwatch, deathwatch, the backup names) print the server's
  own clock, which on the droplet is UTC.
- **The calendar appears only where a time is shown, and that is LocalTime**,
  which takes every day, month and weekday from Godot's `Time`.
  `_test_the_calendar()` holds Godot's calendar against Howard Hinnant's
  days-to-civil for every day of 1970-2199, both directions and the weekday,
  then LocalTime on Feb 29 2028 (a Tuesday), the day after Feb 28 2100 (Mar 1:
  not a leap year), New Year's Eve, a stamp seven days after Feb 29, and both
  of Denver's changes of clocks with a stand-in for the browser.
- **The kill record's "counted since" is the player's date** now; it read the
  UTC date, so a record begun on the evening of the 6th in Denver said the 7th.
- The website's visitor counter keys its days by UTC (`toISOString()`), so it
  has neither problem.

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
- **Record** is `GET /api/staff/actions?player=&action=moderation` — every
  sanction, note and warning about them, with a tally over the whole record
  on the tab. Item grants and teleports are behind "Show everything" at the
  top of the tab. A note or a
  warning is **staff-only in the strict sense**: the server reads them under
  `can_act_on()`, so a mod never sees what a dev wrote about another mod, and the
  panel never has them to hide. "Log a warning" records that one was given; the
  game sends the player nothing, and the confirmation line says so.
- **Log** is the whole moderation log, filterable by player, staff and kind. The
  kinds come from the server's `kinds`, not a list typed here. A line about an
  account opens that account. **It opens on Moderation** (the server's
  `groups`), with Everything next to it, so the owner's testing - grants,
  teleports, the PvP and maintenance switches - is not what a mod scrolls
  through. **The same thing done again and again is one line**: `fold_runs()`
  folds entries in a row with the same person, action and target, each within
  `FOLD_GAP_SECONDS` of the next, into "boss granted themselves items ×12",
  opened with a click. A server that does not know `moderation` answers 400,
  and the panel asks for everything instead (`_group_refused()`).

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
  result. (Saves carry no bag now - "The bag is the server's" - so the two
  polls, and a move refused as stale, are what deliver it.) All of them hand it
  to `CharacterData.apply_server_carry()`,
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
  wrapped across lines is skipped rather than guessed at. 2,394 signatures parse
  this way (0.7.4). A missed one still shows in the editor, as it always did.

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

**The tank is the same lesson on the player side.** `tank.gd` replaces
`player.gd`'s `_physics_process()` with an eased walk of its own, and that copy
had fallen behind (day 1, "tank not getting stamina xp"). It never noted a key
press, so the tank went "away" three minutes after launch and earned no defence
or agility XP. It paid no agility for sprinting or for ground covered, never
uncovered the map, and walked and toggled its aura while chat was being typed.
Each step is now one `player.gd` function — `_stamp_input()`,
`_read_move_direction()`, `_sprint_tick()`, `_stop_sprint()`,
`_accrue_agility_from_travel()`, `_tick_regen()` — and both loops call every one.
`_test_the_tank_loop_takes_every_step` fails if either loop drops one, or if the
tank grows its own key poll or stamina drain again. A new step in the base loop
goes into that list too.

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

### The store sells iron to amethyst; ember is found

Decided by the owner on day 1, so a player farming one band can save up for
the next band's set. `generalstore.tres` stocks every potion, the fishing
worm and the iron to amethyst rods, and every weapon and armour piece from iron
(tier 1) to amethyst (tier 4), bonus amulets included, at its value
(`price_multiplier` 1.0). Ember, the ember rod and the boss trophies stay
drop-only.

- **Every potion since 0.25.4.** The store sold the tiny, small and medium
  ones (levels 1, 5, 10); the large (16) and greater (22) were drops only.
  The owner: "need to unlock all of the potions we set up". Asked the same
  day whether ember and the mythics should go on the shelf too, the owner
  kept them drops ("Only the potions"). The game's shop test and the API's
  `test_pacing.py` / `test_economy.py` hold all fifteen, at value.
- **The mythic weapons are free (0.69.0).** The owner: "add mythic weapons to
  the shop marked as free so new players can use free"; asked how, "Real ones,
  free, any level". `ShopData.free` lists the Meteorite, the Double Axe and
  Dynamite, and all three are worn from level 1 (`required_level` was 22).
  The server's rules (`/api/shop/buy`, `gamedata.is_free()`):
  - **One each per character**, counting what it carries and wears and what
    its account's bank holds. The panel shows them first under "Free", priced
    "Free", with Take instead of Buy.
  - **The plain catalogue piece, never rolled.** A dropped mythic always rolls
    (`meteorite~d104p96`), so the plain id is the free one: no vendor buys it,
    no trade takes it, and the Sell list leaves it out (`free_ids` in the
    catalogue answer). A drop still sells and trades as before. Throwing the
    free one away and taking it again re-rolls nothing. An owner grant of the
    plain id ("plain") is the free piece too.
  - **Lost on a full death like any worn gear**; the shop gives another.
  - The healer has no mythic, so there is none for it.
  The exporter refuses an id that is both free and in `stock`.
  `_test_the_shop_gives_the_mythics_away`; the API's `test_economy.py` holds
  the server half.

- **Anyone may buy any piece; it is worn at its level.** The row says "Lv 5"
  before you pay, and the server's equip check refuses it until then.
- **The next set is about six to eight hours away** (it was three to four
  until the 5 Oct price pass below). At five kills a minute in the band you
  are in, a jade plate set (9,168) is 7.5 hours of iron-band gold, cobalt
  (23,840) 6.5 hours of jade-band gold, amethyst (61,840) 6.1 hours of
  cobalt-band gold; each cloth set is within half an hour of its plate set.
  The API's `test_pacing.py` measures it through the real kill roll.
- **The 5 Oct price pass.** The owner: a few lucky kills or a good fishing
  trip made the old prices trivial, and a cooked fish cost about four times a
  potion for every point either healed. Every weapon, armour piece, amulet and
  rod doubled (`value` in its .tres); every potion quadrupled, which puts a
  potion within a fifth of the cooked fish of its tier per point healed, at
  every tier. Worms, fish, gold, lusions and pets did not change. Gold drops
  do not read item values (`GOLD_TIER_RATIO`), so prices are a pure sink, and
  the trade tax (5% of `value`) moved with them.
- **The shop buys** (5 Oct, the owner: "we should be able to sell items to
  the shop"). Every piece of a tier is the same piece, so a second jade sword
  was worth nothing to its finder. The panel has Buy and Sell under the purse;
  Sell lists the backpack cells the shop will take, at `sell_prices` from the
  catalogue answer, with Sell 1 and Sell all on a stack. A sale is
  `POST /api/shop/sell` with the cell and the item seen in it; the answer's
  purse and bag are drawn, and a `409` adopts the `resync` and redraws. Ember
  and mythic gear ask twice ("Sure?"). `ShopData.sell_multiplier` is 0.05:
  selling mints gold, gear drops are worth seven or eight times an hour's coin,
  and at 0.1 a player selling everything reached the next set in about four
  hours, undoing the price pass the same day. `_test_the_shop_buys`; the API's
  `test_economy.py` and `test_pacing.py` hold the server half.
- **A price edit is an export.** The store and the trade tax read
  gamedata.json, not the .tres, so an edited `value` that is not exported
  shows one price and charges another. `_test_the_export_carries_every_price`
  fails until the exporter runs, and holds the potion-to-fish rule.
- **One shelf per band.** `show_catalogue()` starts a heading whenever
  `shelf_of()` changes, so the stock is listed potions first, then fishing
  ("Fishing · rods and worms": a rod is any id ending `fishingrod` and the bait
  is `FISHING_BAIT_ID`, the same rules the pond uses), then tier by tier. A heading reads "Jade  ·  the Water and Ice lands  ·  level 5": the
  material (`GameConstants.TIER_MATERIALS`), the lands that drop it
  (`TIER_ELEMENTS`, through `tier_lands()`) and the level.
- **`TIER_ELEMENTS` must agree with the enemies.** If an element moves band,
  its normals' `max_loot_tier` and this table change together; the suite reads
  every normal enemy and fails on a mismatch.
- **A placed monster's leash is read through `BaseEnemy.authored_leash()`
  (0.69.2).** The exporter runs in the editor on placeholders that never ran
  `_init()`, and the bush mage's 1,500 is set there - so an editor export
  wrote the field mages as 400 and a running one 1,500. A class that sets its
  own leash names it `const CHASE_LEASH`; a placement's own number wins.
- **The server sells from `gamedata.json`, not from the .tres.** After
  changing the stock, re-export, copy the file to the API and restart Flask.
  Until then the suite fails "data/gamedata.json carries the same stock".

`_test_the_store_sells_the_next_set` holds the game side.

### Dropped gear rolls its stats, and the roll is in the id

The owner, 5 Oct: "random stats on all items because it gives loot a better
value if a rare max roll". Every stat a dropped piece of gear has - damage,
armour, max health, max mana, the damage bonus - rolls on its own when it
drops, 85 to 115% of the number in its .tres, most often near 100 (a
triangle peaked at 100: six stats in ten land within 5 of it, and 113% or
more is about one in seventy). One drop in a
hundred is **Perfect**: every stat at 120%, "Perfect" in front of its name.
Gear bought from the shop rolls the same way, at the till. The numbers are
`GameConstants.QUALITY_*`, exported; the server rolls (`gamedata.roll_quality`
at the bag, the mythic and `/api/shop/buy`).

- **The roll is part of the item id**: `jadechest~a104h96` is a Jade Cuirass
  with armour at 104% and health at 96%. `QUALITY_MARK`, then a letter from
  `QUALITY_FIELDS` and a percent for every stat the piece has, in that order.
  Every cell, bag entry, trade row, hotbar key and the equipment map already
  hold an id, so a rolled piece is moved, worn, banked, traded and sold by the
  paths that exist, and the server's "the item the game saw in that cell"
  check covers the roll too. **Never change a letter** once a piece has
  dropped: every stored roll is spelled with them.
- **`ItemRegistry.get_item()` reads it.** For a rolled id it hands back a COPY
  of the .tres (`rolled_item()`, cached, so one id is one object) with
  `item_id` the whole rolled id, every rolled stat already scaled, `base_id`
  and `rolls` filled in. So `player.gd`, the Gear window, the tooltip's
  comparison and everything else that reads `damage` or `bonus_max_hp` gets
  the rolled number without knowing a roll exists. `split_roll()` is as strict
  as the server's `split_variant()` - every stat once, in order, 85-115 or
  all 120 - and a malformed roll is an unknown id.
- **The rounding is integer and halves up, on both sides**
  (`ItemRegistry.scale_stat`, `gamedata.scale_stat`), because the server
  derives max health from the same rolled numbers; a float rounding one way
  here and another there is a point of health apart and a clamp on every save.
  Both suites hold one table of pairs; change one side and both go red.
- **Ask `catalogue_id()` for anything keyed by the catalogue.** A rolled
  piece's `item_id` is not a key of the shop's `sell_prices` or of anything
  else built from the .tres files; the Sell list reads the price by
  `catalogue_id()`. A roll changes what a piece does, not what it is worth:
  `value` is the .tres's, so the shop pays the same for any roll and the trade
  tax is the same.
- **Where a roll shows**: the tooltip puts each rolled stat's percent after it
  ("21 Damage (107%)") and the rarity line says "Quality 104%" (the rolls
  averaged); the trade window says the quality on the row and the stats in its
  tooltip. A Perfect piece is gold: its name, a frame a pixel wider on its slot
  at any tier, and the glow of the bag it drops in (unless that bag holds a
  mythic, whose red is the bigger news). Selling one asks twice.
- **On the shelf, "?"** (the owner, 5 Oct: "item stats say ? and are revealed
  upon buying in shop only"). The shop lists the catalogue piece at its
  price; `/api/shop/buy` hands over a roll of it, at that price whatever it
  rolls, so an average purchase is still the catalogue piece. Hovering a
  shelf row shows "? Damage" and the like and no comparison
  (`show_for_stack(..., on_the_shelf)`, `ItemTooltip.rolls_when_bought()`);
  the purchase line says what it rolled ("quality 104%", or a Perfect), in the
  shop and over the player. A Sell row is something you own, and shows its
  own numbers.
- **The owner's item menu** has "Gear stats": plain at 100% (the only way to
  have one now), rolled like a drop or a purchase, or Perfect (`quality` on
  `/api/staff/grant`: plain, roll or perfect; the server still reads the
  first build-3 game's "store" as plain).
- **Small numbers barely move.** 85% of a 1% damage bonus is still 1%, and an
  iron boot's 3 armour is 3 from 85 to 115; only a Perfect makes it 4. The
  roll matters from the middle tiers up, where the numbers are big enough.
- **Build 3.** A build-2 game reads a rolled id as the error item, so the
  wire build went up (`Api.BUILD`, the API's `CURRENT_CLIENT_BUILD`). Raise the
  server's minimum to 3 once the new game is out.

`_test_quality_rolls`; the API's `test_quality.py` holds the server half.

### Armour resists an element, and the roll is in the id too (0.11.0)

The owner, 7 Oct: "add resistance to armor with a ? random roll also in the
shop", "i want elements to do something". Every monster already deals its own
element; now every piece of **armour** - anything worn that is not a weapon,
helm to amulet - rolls one of the seven lands' elements and a percent, wherever
its stats roll (a drop, the till, the owner's "rolled" and "Perfect" grants).
The numbers are `GameConstants.RESIST_*`, exported; the server rolls.

- **Never a weapon, and nothing about a player's own damage.** The owner, the
  same day, on giving weapons an element: "the main goal should be to keep
  players damage consistent with attack level and gear". Elements defend; there
  is no matchup chart. Environmental hazards may come later, and would be one
  more source of elemental hits for this to cut.
- **The last part of the rolled id**: `jadechest~a104h96r605` resists fire
  (`Element.Type` 6) by 5%. `RESIST_LETTER`, one digit of element, two of
  percent, after every stat. **Never renumber `Element.Type`** or change the
  letter: every stored roll spells the element with that digit. A piece from
  before 0.11.0 has no `r` part and resists nothing; it is still read.
- **The ranges** are by tier (`RESIST_RANGES`): iron 2-5, jade 3-7, cobalt
  4-9, amethyst 5-11, ember 6-13, past the table its last row. Evenly across
  the range, the element evenly from `RESIST_ELEMENTS` (the seven lands; not
  lightning or poison). A Perfect piece resists at the top of its range.
- **Matching pieces add up, to `RESIST_CAP` (50%)**, and take that share off
  a hit of that element only. `Player.damage_taken()` is the arithmetic, and
  `take_damage()` lands what it says: the defense tier, the armour, then the
  resistance, each multiplied with what the one before left, `maxi(1, ...)`
  under all three. A physical hit is armour's alone. Seven ember pieces of one
  element at 13% are 91%, held to 50%, so a hit is at most halved by it.
- **`ItemRegistry.split_roll()` reads it** (`read_resist()`), as strictly as
  the server's `gamedata._parse_variant()`: armour only, an element from the
  list, inside the tier's range, two digits of percent, last, once, and the top
  of the range on a Perfect. Anything else is a malformed roll, the unknown id.
  `rolled_item()` sets `resist_element` and `resist_percent` on the copy;
  `resistance_text()` says "Resists fire 5%".
- **Where it shows**: its own line in the tooltip; on the shelf "Resists ? -
  one element, 3-7%", since the till rolls it with the stats; the purchase line
  ("quality 104%, resists fire 5%"); and the Gear window's **Resists** row,
  strongest first (`Player.resistances()`): the top two and a count, "Fire
  18%, Ice 5% +1", with the whole list as the row's hover text
  (`RESISTS_SHOWN`). Three ember elements at 13% made the window 6 pixels
  wider than the column it sits in.
- **The server only carries it.** Damage a player takes never reaches the
  server, so nothing there reads a resistance but the parser and the roll; a
  resistance changes no price, no maximum and no combat bound.
- **Build 4.** A build-3 game reads a resisting id as a malformed roll, the
  error item, exactly as build 2 read a quality roll - so `Api.BUILD` and the
  API's `CURRENT_CLIENT_BUILD` are 4. Raise the server's minimum to 4 once
  0.11.0 is out.
- **Found while here, 7 Oct**: `_roll_suffix` ended in `$`, which in PCRE also
  matches before a final newline, so `"ironsword~d107\n"` read as the 107 roll
  - a second spelling of one piece. It is `\z` now. The server had the same
  hole and Unicode digits through `\d`; both sides' malformed lists hold them.
  And `spikedoor.gd` passed `&"physical"` to `take_damage()`'s int element, a
  type error the first time a door is given contact damage (none is yet).

`_test_armour_resistance`; the API's `test_quality.py` Q-8 holds the server
half, and both name the same malformed spellings.

### The boss gates in the Field: a lever on each side

The Field's three spike gates (`spikedoor`, `spikedoor2`, `spikedoor3`, at
the scene's root) stand between the field and the ladder down to the bosses,
and climbing back up lands you inside them. The owner, 5 Oct: "set up that
lever to release the 3 gates by boss exit". So there are two levers under
`ysortworld/interactables`: `levergatesout` on the field side, and
`levergatesin` beside the ladder, where you come back up. Both drive all
three gates and toggle them; the Field loads with the gates up.

- **On means open.** `lever.gd`'s settings always said so ("a lever that
  starts thrown holds its door OPEN"), but the sum said the opposite - and no
  scene had wired a lever to anything until these, so nothing caught it. Wired,
  the gates fell as the Field loaded and the first pull closed them.
  `doors_raised()` is the one place it is decided now.
- **Levers on the same doors move together.** A throw tells every other lever
  that drives any of the same doors where they went (`follow_doors()`), so the
  lever by the ladder never reads "off" over gates the outside one opened.
  Linked by the doors themselves - nothing to name or keep in step.
- **The inner lever stays out of the ladder's reach.** The ladder is a
  walk-in (`ladder.gd` fires on `body_entered`), so a lever whose zone touched
  it could drop a player into the boss arena on the way to pulling it.
- **Each player's own.** A lever and its gates are the client's, like the
  rest of the Field: another player does not see your gates open, and leaving
  the Field closes them again.

`_test_the_boss_gates_lever`.

### The version: MAJOR.MINOR.PATCH, and who moves it

6 Oct, the owner on numbering releases. The game's version is
`Api.DISPLAY_VERSION` in `src/systems/api.gd` and nowhere else - it was there
from the first build as "0.1.0" and never shown. `GameConstants.game_version()`
and `version_text()` read it, the login screen shows it in its bottom-right
corner and the Menu dropdown at its foot, and the Windows export's file and
product versions are it with `.0` after (Windows wants four numbers).
`_test_the_game_says_its_version` fails when they disagree.

- **0.x until launch; 1.0.0 is launch.** MINOR for a new chunk of the game,
  PATCH for fixes and balance. Counted from what had shipped: 0.1 the
  single-player run, 0.2 accounts and the server owning saves, 0.3 trading,
  guilds and chat, 0.4 the browser (4 Oct), 0.5 seeing each other (6 Oct).
  0.5.1 is the dots drawn instead of letters, 0.6.0 the trade switch and
  the hold on fresh finds, 0.6.1 the owner-only item grant and the wider
  loot bag reach, 0.7.0 shared monsters, 0.7.1 no debug keys (the owner panel
  does their work, the performance readout included), 0.7.2 enemies see and
  shoot a player pressed against a wall, 0.7.3 Escape closes every window, 0.7.4
  Move Players: a list of who is online, its own name box, Go to beside them,
  0.7.5 Give item to a player and the Save history (rollback), 0.7.6 window
  mode (exclusive fullscreen), the monitor picker, where the window was, and
  Match screen, 0.8.0 text size, five style fonts and keys you can change,
  0.9.0 the kill record (Social > Kills, or K), 0.10.0 the server's books on
  every fight (it watches; nothing in play changes), 0.11.0 armour resists an
  element, 0.11.1 the Credits window (Options > Credits), 0.11.2 each time shown
  at the offset in force when it happened (a browser), and the calendar tested,
  0.11.3 the Credits' Support tab sends a name through the PayPal note,
  0.11.4 and asks for nothing but the hot cocoa, 0.11.5 the Electric Sprite
  pet's orb reaches what it is aimed at, 0.11.6 the seven bosses are Crowned
  Beholders by name, 0.11.7 beating the Crowned opens a teleporter home to
  town, and a pet's tooltip says a right-click summons it, 0.11.8 the GM
  panel's Server tab can make old versions update, 0.11.9 the mythic weapons
  hit 1.4 times ember and the Double Axe spins up when left, 0.12.0 the
  Meteorite lands twice as wide and leaves a burning crater, and Dynamite
  chains, 0.13.0 a Dynamite blast leaves its scorch smouldering, 0.14.0
  Dynamite blasts as wide as a meteor, throws faster with the ring lit and
  bundles every fifth throw, the Double Axe whirls wider and its cuts bleed,
  and the Meteorite falls in a fire vortex, 0.15.0 the town's portal leads
  to the Big Field and its ladder down to the Field, 0.15.1 an arrival
  portal closes as you walk away from it, 0.16.0 a monster with no death of
  its own flashes white and breaks into pixels when it dies, 0.17.0 the
  Meteorite's fire vortex pulls monsters in before the stone lands, 0.17.1
  one meteor in ten does, 0.17.2 one in a hundred, 0.18.0 every mythic has a
  10% roll and a 1% one (the Double Axe wide or bloody, Dynamite three
  sticks or five), 0.18.1 the owner panel can make every one the 1%, 0.18.2
  and every one the 10%.
- **Raise it with every delivered change to the game**, in the same batch:
  the PATCH for a fix, the MINOR (PATCH back to 0) for a feature. Both
  `DISPLAY_VERSION` and export_presets.cfg - and read export_presets.cfg off
  the PC first: the editor rewrites it when it exports, so a copy from here is
  stale.
- **The website is not versioned with the game.** The owner, at 0.16.0: "do
  not update website with 0.16.0 we should have one for the game and one for
  the website". A game release is the game's commit; a website change is its
  own commit with its own message, and does not add the game's version to the
  site unless the owner asks for it.
- **And close Godot before export_presets.cfg is replaced.** The editor holds
  the presets in memory from when it opened and writes them back on every
  export. On 7 Oct the 0.10.0 web export wrote a copy from before 0.7.2:
  file version 0.7.1.0 and no `include_filter`, so that build went out
  without the fonts' OFL.txt. `_test_the_game_says_its_version` and "every
  licence text goes out in every export" both catch it - on the PC, where
  the file is.
- **Not `Api.BUILD`.** That counter tells the server which games are too old
  to talk to it, and moves only when the game and the API must change
  together. The version is for people and moves every release.

### Trading can be switched off, and a fresh find waits

6 Oct (E3_SCOPE.md, option B, with the owner's "allow trade to finish"). The
kill is still the game's word, so a cheated drop is real loot and a trade is
the only road between accounts; the gates are on the server (api/CLAUDE.md,
"Trade gates") and the game only says so.

- **The GM panel's Testing tab** has "Trading", a CheckButton beside the
  other world switch, PvP (on the Server tab it made that tab the tallest, and
  its wrapping status line then changed the window's height between tabs),
  showing `/api/status`'s `trade` and posting `/api/server/trade`
  (`_refresh_trade()`, `_on_trade_toggled()`, with `status_request` and
  `post_request` as the suite's seams). Off says how many open trades may
  still finish. Owner only, here and on the server.
- **The trade window asks when it opens on the start page**
  (`_check_trading_open()`): off, it says so and disables Open trade before
  anybody types a name. No answer leaves the button alone - the server's own
  503 says it anyway, in the same words (`TRADING_OFF_TEXT`).
- **A held piece** (a mythic or a Perfect found in the last 48 hours) is
  refused by the server when it is offered; the window shows the server's
  sentence, which says when it can go. Nothing here knows about holds.
- The staff log words it "changed trade switch", and names the owner's level
  and skill tools.

`_test_the_trade_switch_reaches_the_game`; the rules are `test_tradegates.py`.

### Other players are drawn from the presence socket

The owner, 5 Oct: "i want to make other players see each other" - their body
walking and idling the right way round, the name over the head, their attacks
and their pet following. The `Presence` autoload (`src/systems/presence.gd`)
keeps a WebSocket to the API's `presence.py` while a character is in the world
and the game is logged in, and draws everybody in the same area as a
`remoteplayer.gd` node in the local player's own parent (the y-sort world).

- **A ticket, never the login.** It asks `POST /api/presence/ticket` and hands
  the socket the ticket; the API's answer says where the socket is
  (`socket_url`), so the browser build reaches it on its own address. Renewed
  every minute, which is how a level-up or a new guild reaches other screens.
- **The game says where, never who.** `state_for()` sends the area, the
  position (global, to a tenth of a pixel, so standing still sends nothing),
  the body's animation, the lit aura and the pet out - at most ten times a
  second and only on a change. Name, rank, colour, guild, class and the pets
  allowed come from the server. Positions arrive as world positions and are
  turned into the world node's space (`_local()`).
- **A remote player is a picture, not a player**: no body to collide with, no
  hurtbox, and never in the "player" group - everything that asks for "the
  player" still means you. Its sprite, auras and nameplate are copied from the
  class scene and from player.gd's own constants (`class_parts()`,
  `plate_constant()`), so it cannot look different from the real thing. A
  class without an animation it was sent (a healer has no attack) stands
  facing the same way. An attack replays until the next state arrives,
  because the game sends "attacking" once.
- **The pet is a sibling** in the world, so it sorts by where it stands, and
  goes when its owner does.
- **A new scene is a new world.** A change of scene, even a revive in the same
  area, clears every remote and asks the server who is here (`sync`), sent
  after the new state so the answer is about the new area.
- **Nothing here is essential.** No server, a refused ticket or a dropped
  socket: the game plays as before, nobody is drawn, and it tries again after
  2, 5, 10, then 30 seconds. It never tells the player.
- **And, since 0.7.0, the monsters** - see "Shared monsters" below.
- **And, since 0.19.0, their attacks, the levers they pull, and a playback
  instead of a chase** - see "Seeing each other's attacks" below.

`_test_other_players_are_drawn`; the server's rules are `test_presence.py` in
the API repo.

### Shared monsters: one game runs them, everyone fights them

The owner, 6 Oct: "shared monsters separate loot bags". Until 0.7.0 two
friends in the Field saw each other but swung at different copies of every
monster. Now everyone in an area fights the same ones.

- **One game runs them: the area's LEADER.** The presence server names it -
  the game that has been in the area longest - and sends `lead`. Its monsters
  are THE monsters: they think, chase, cast and respawn exactly as a lone
  player's always have. `src/world/monstersync.gd` (added to every area by
  AreaRegistry, like the sleeper) says ten times a second what changed:
  `[id, x, y, animation, hp]` for each monster that moved, and an ordered list
  of what happened - a spawn, a death, a shot, a vine, a boss spike or swing,
  a stalker pillar - plus the gauntlet's wave. A game walking in is sent
  everything at once (`need` -> a full world, in parts of 60 records).
- **Everyone else FOLLOWS: their monsters are mirrors.** `BaseEnemy` has a
  SHARED MONSTERS section: `net_set_mirror()` turns a monster into one where it
  stands (no AI, every Timer child paused - the boss's spike and stalker
  clocks run beside the AI, not in it), `_net_follow()` eases it toward where
  the leader says, `net_apply_state()` plays what the leader says and shows the
  health it says. Every frame-triggered attack (the shooters' release frames,
  the vine, the boss's cast and swing frames) returns for a mirror, and so does
  `PoisonSlime._check_duplicate()` - a mirror never makes anything.
- **Your hits are decided on the leader.** `take_damage()` on a mirror shows
  your number, flash and sound at once and hands the hit to monstersync, which
  sends it (batched, `[[id, damage, element]]`) for the leader's game to apply
  with `net_take_remote_hit()`. Nothing on a follower changes a mirror's hp.
- **Separate loot bags.** A monster that dies is reported by every game whose
  player or pet hit it - each gets its own XP and its own bag from the server's
  own roll, and nobody sees anyone else's. The leader reports only if its own
  player helped (`_should_report_kill()`: hit locally, or hit by nobody else,
  which is every kill a lone player has ever made). A follower reports from
  the death event, if it ever sent a hit for that monster.
- **You are hurt only by what you see.** A monster's shot, vine, spike or swing
  happens on the leader and is replayed on each follower - shots through the
  mirror's own `spawn_projectile_node()` with the leader's aim, spikes through
  `_spawn_one_eruption()` with the same telegraph and a shared `puddle_seed`
  (so the acid lands in the same places), swings through `_land_swing()`
  around the mirror. Each copy can only touch its own game's player. Your
  health is still your game's, as it always was.
- **Monsters chase anybody sharing them.** `src/shared/targets.gd`: the local
  player and every RemotePlayer whose game shares monsters (presence "v" 2) and
  is not playing its death. `BaseEnemy._resolve_player()`, the sleeper, the
  respawner's distance check and the twin all ask it. A RemotePlayer carries a
  `bodyshape` marker at its class's body circle and a `velocity` worked out from
  its positions, so a boss aims at and leads it like the local player. A
  monster whose target is out of leash range looks for a nearer one every
  half second instead of walking home past someone. `player` on an enemy is a
  Node2D now, for that reason.
- **Handing over keeps the fight.** When the leader leaves, the server names
  the next in line and its mirrors turn back into monsters where they stand,
  at their health, keeping their numbers; a monster it hit as a follower is
  one it helped kill. Its respawner starts a fresh clock for every dead spawn
  point (`resume_authority()`). A dropped link does the same: the follower
  fights its own, as before 0.7.0.
- **Matched by where they were authored.** Every placed monster carries
  `net_origin` - its path from the scene root, the same string on every
  machine - and the respawner keys its census by it. A follower binds the
  leader's monsters to its own by number, then by origin (so the boss
  gauntlet's gates keep the bosses they hold), and only then builds one from
  the leader's record; anything left over goes silently (`net_remove()`, no
  `died`). The leader's world may only name scenes under `scene/enemy/` and
  `scene/projectiles/`, profiles under `data/enemies/`, and containers this
  scene already keeps monsters in.
- **A leader cannot make the floor hit harder.** Shots, swings and spikes are
  built from the follower's own copy of the monster, so their damage is the
  follower's own. The three numbers that are not - a spike's telegraph and
  size, a stalker pillar's damage, telegraph and size - are held to what the
  follower's own boss could do (`safe_spike()`, `safe_pillar_damage()`,
  bossstalker.gd `PILLAR_*`), and a follower draws at most `MAX_MONSTERS`
  (400; Big Field has 128). A cheating leader can still set the game's own
  monsters on you; it cannot invent a harder one.
- **Waiting, briefly.** A game that knows a presence server is there holds its
  monsters still until it hears who leads (at most 2 s, then it runs them
  itself). No server, an old one, or no other player: everything is exactly
  as it was.
- **The boss gauntlet agrees by itself**: every game advances it from its own
  bosses dying, and a mirror's death is the leader's. `net_jump_to()` catches
  a game that walked in mid-fight up to the leader's wave.
- **Small fixes on the way.** A respawned monster used to believe its home was
  the world origin (BaseEnemy._ready() records `spawn_position` before the
  respawner set the position) and walked off to the top-left when leashed; the
  respawner sets it again now. And presence's `_remove()` no longer raises a
  SCRIPT ERROR when the world was freed first (a death).

Tests: `_test_presence_carries_the_monsters`, `_test_shared_monsters_lead`,
`_follow`, `_handover`, `_targets`, `_pieces` (respawner, gauntlet, acid) and
`_hold_the_leaders_numbers`, against a stand-in link; `test_presence.py` P-7 for the server. Played with
two real games against the real API and presence server: both hitting one
monster each got the kill and a bag of their own, a follower was hurt by the
leader's shots, a boss arena advanced to wave 2 on both screens, and the
follower took the arena over when the leader left.

**Not shared, and said so:** loot (by design). Levers and spike gates were
each game's own until 0.19.0 - see "Seeing each other's attacks" below. The leader is trusted with the monsters exactly as every
game is trusted with its own kills (E-3): a cheating leader can do no more to
the monsters than a cheating game always could, and the caps above keep an
invented number from reaching anybody's health. **Since 0.87.0 it is not
trusted with their health either** - see "The server owns the monsters'
health" below.

### The server's books: it watches every fight (0.10.0)

The owner, 7 Oct: "Moving combat onto the server ... The first step only
watches: the server checks every hit against what that character could really
do, but changes nothing in play." E3_SCOPE.md (api repo), option C, step 1.
The presence server now keeps its own count of every monster's health
(api `combatbook.py`, api CLAUDE.md "The books on every monster"). The game's
part is small, and **nothing a player sees changes**:

- **A leader tells the server even alone.** A server whose welcome says
  `"books": true` (`Presence.books()`) hears the leader's world whether or not
  anybody else shares the area: monstersync's `_sending()` is `_sharing()` or
  `_books()`. Spawns, deaths and what moved go out; shots, vines and swings
  still only go to games that draw them.
- **With its own hits inside it.** `BaseEnemy.take_damage()` hands every hit
  this game's player or pet lands on a monster it runs to `own_hit()`, BEFORE
  the hp moves, and the next world carries them as `"hits"` - read by the
  server ahead of the deaths they caused. A remote hit was counted on its way
  through the server and is not sent again. At most `MAX_HITS_PER_MESSAGE` a
  world; the rest go in the next.
- **A scene loads before its socket does.** Every change of area opens a new
  presence link, so the monsters start running with nobody told. When the
  link opens and names this game leader of monsters it already runs,
  `_on_lead()` sends everything, as a new scene's (`_told_books`); again after
  the link drops and comes back. The server answers a world about monsters it
  never saw with `need` for game 0, which `_on_need()` answers like any other.
- **Dead is dead while it still stands.** A large slime says it died as its
  split begins and flashes a moment before its smalls appear; it used to be
  numbered again in that moment (`_register_all()`), a second monster at its
  spot on every follower's screen. `_on_died()` marks it `net_dead` now.
- **A fresh ticket after an equip** (`Presence.renew_soon()`, from
  `CharacterData._apply_equip_result()`): the server holds every hit to what
  the ticket says is in hand, and tickets are otherwise renewed once a minute.
- **The numbers the server bounds hits by are the game's**, exported:
  each class's base damage, cooldown, swing length and walking speed
  (`CLASS_SPEED`, a constant now so the exporter can read it), the pets', the
  skill and agility steps, which weapons bring their own attack - and every
  area's spawn points and respawn time (`areas`). Re-run the exporter and copy
  gamedata.json across when any of them changes; the suite says so if not.
- Hello says wire `3` (`SHARED_VERSION`); a server on 2 still shares
  (`SHARED_MINIMUM`). An area led by a game from before 0.10.0 is not judged by
  the server at all.

Tests: `_test_presence_carries_the_books`, `_test_shared_monsters_keep_the_books`,
`_test_combat_bounds_match_the_game`; the server's half is `test_combatbook.py`
and `test_presence.py` P-8. Played with two real games against the real API
and presence server: a warrior leading and a mage following killed monsters
together, each AGREED with their own damage and character, a warrior alone
split a large slime and its twin and smalls were all accounted for, and the
only flags were the test harness's own teleports.

### Enemies aim at the body, not the origin

The owner, 6 Oct (0.7.2): "walking up to the wall enemies dont attack". Every
enemy asked "can I see you" with a ray to the player's **node origin**, and
aimed its shots there too. The origin is not where the body is: the warrior's
`bodyshape` is 13 px below it, the tank's 16 px above, the mage's and healer's
a few px above. A warrior walked up into a north wall has its body touching the
wall and its origin 6 px *inside* it (a tank against a south wall, 8 px), so
the ray to it hit masonry, `_has_line_of_sight()` said no, and the whole pack
stood around holding fire.

**`BaseEnemy.target_point()`** is the body - `Targets.body_point()`, the
`bodyshape` node, or the origin for anything without one (a RemotePlayer
carries a `bodyshape` marker). Every sight check against the player and every
shot aimed at one uses it; the boss's `_aim_point()` and the stalker always
did. Distances, formation slots and facing still measure from the origin, as
they were tuned. `_test_enemies_see_a_player_against_a_wall()` builds a wall on
layer 1, presses each class's real body offset against it from both sides, and
fails if any enemy cannot see or will not shoot; it also fails on
`player.global_position` written into a sight line or a shot anywhere under
`src/enemies/`.

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
hold all of it. The owner's Powers window is built in code rather than a scene,
so that check could not see it, and it had no × until day 1
(`_close_powers_panel()`, `_test_the_powers_panel_closes`).

**The three staff windows wear one look** (day 1). Owner, Staff and Powers had
three (navy, brown, navy). All three now wear `assets/themes/staff_ui_theme.tres`:
navy, with the inventory's gold frame, a gold header box (`PanelHeader`), gold
boxes (`PanelSub`) and gold-boxed tabs. It is set on the Owner root, on the Staff
window's `mainpanel` (its root keeps `rpg_ui_theme.tres` as the fallback) and on
the Powers frame. Nothing inside keeps a style of its own except the red and
green action buttons (Ban, Unban, Close server): a per-node override beats the
theme, so one left behind keeps an old colour whatever the theme says. Both
themes also style `PopupMenu`, so dropdowns and right-click menus get the gold
frame instead of Godot's grey. `_test_the_staff_windows_share_one_look` holds it.

**The Powers window reads in words** (5 Oct, the owner: "update powers tab").
Every route arrives from `/api/staff/powers` with `what`, the first line of its
docstring, and the window printed only the method and path - a column of
`POST /api/staff/ban` that only someone who had read app.py could use.
`_render_powers()` shows the sentence and puts the route on the line's tooltip,
with `mouse_filter` set to PASS, because a Label ignores the mouse by default
and a control that ignores the mouse never shows a tooltip. `power_words()`
falls back to the route when there is no sentence, and drops "(owner only)" and
"(staff only)" under a heading that already says it. The notes under each rank
are the server's, so correcting one is a server update, not a game export.
`_test_the_powers_read_in_words`.

**The Character Stats window is two columns** (day 1): the level badge,
experience and the three pools on the left, the six skills on the right, with
no separator lines between boxes. Health, stamina and mana are red, gold and
blue bars with the numbers inside; under the XP bar, "1% · 998K to level 30".
Big numbers are short (`GameConstants.short_number()`: "9,391", "12K", "1M",
"1.2M", rounded down) with the exact figure in the tooltip. Its window key is
`charstats`, so a rectangle saved for the old narrow window is not reused.
The level sits in a hotbar slot (`levelbadge` wears the theme's `PanelSocket`,
the same socket as the hotbar and every grid cell). `_test_the_stats_window_reads_cleanly`
holds it.

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

**A proxy's 502 or 504 is the server not answering.** In a browser the game
reaches the API through the site, so with app.py down the page still gets an
HTTP answer from the proxy. `Api._read_answer()` took any HTTP status as proof
the server was up, so on day 1, with the API stopped, the login screen said
"Connected to the Elusion server." and a login showed serve.py's own text
("The API at http://127.0.0.1:5000 did not answer: <urlopen error ...>"). A 502
or 504 is now status 0 and offline, the same as no answer at all; app.py never
sends either, and its 503 (maintenance) is still an answer.
`_test_a_gateway_saying_no_answer_is_no_answer` hands `_read_answer()` each
status with no network.

**The login screen asks without a login.** Its five-second probe asked
`/api/auth/session`, which answers 401 to nobody signed in, and opening the
game with nothing remembered asked it once more. In a browser every 401 is a
red "Failed to load resource" line in the console, twelve a minute. Both ask
`/api/status` now (the opening reuses the answer `refresh_build_info()` already
has). `_test_the_login_screen_asks_without_a_login`.

**In a browser, Options hides window size, V-Sync, the renderer, the graphics
API and the monitor picker, and greys out exclusive fullscreen.** The browser owns the window and paces the frames, and Compatibility is
the only renderer there. The readout says "paced by the browser". The login
screen has no Exit, since a page cannot close its own tab.

**Measured** in headless Chromium through Caddy and nginx, with SwiftShader
software GL (a real GPU draws much faster):

- The export is 46.2 MB, or 15.7 MB with gzip, since the emoji font ships at
  chat size (see "Speed on day 1"); it was 51.8 MB and 21.4 MB, and on 40 Mbps
  the login screen was up at 7.3 s at that size.
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
- Audio in the browser is untested. The teleport is the only sound so far.

### The Windows build

**Export:** Project > Export > **Windows** (day 1: "we need that pc export"; the
project only had the Web preset). It writes one file,
`builds/windows/ElusionRPG.exe`, with the game packed inside it (`embed_pck`).
It is 64-bit, named Elusion RPG by Elusion Studios, and leaves `src/tools/` and
`scene/tests/` out like the Web preset. Its version, 0.1.0.0, follows
`Api.DISPLAY_VERSION`; bump both together, or `_test_the_windows_build` fails.
Godot's export templates must be installed once (Editor > Manage Export
Templates > Download). Godot 4.6 writes the name and version into the .exe
itself, without rcedit.

**Which server it talks to.** A desktop build has no page address, so
`Api._resolve_base_url()` tries `--server=`, then `ELUSION_SERVER`, then
`user://server.cfg`, then falls back to `http://127.0.0.1:5000`. Until the
server moves, the .exe only finds one on a PC running the API. When it moves,
point `DEFAULT_BASE_URL` at the real address before exporting. Since 0.44.0
an override must be `https://`, or `http://` to this computer only
(`is_this_computer()`); any other `http://` is ignored, with a `[BOOT]` line.

Measured in the sandbox: a 113 MB .exe, 104.6 MB of it the engine. Booted from
its own pack, it loaded every item (146 of 146) and every area, and nothing from
`src/tools/` or `scene/tests/` was stored.

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
  Press Enter Elusion to try again", which retries the LOAD (not the login -
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
  (`GameState.opening_story_told`, reset by `clear_current_user()`). Its last
  page carried the credits until 0.11.1; they are in Options > Credits now.
- `_test_every_area_can_be_walked` copies each area's tiles and static bodies
  into the tree and floods it with the warrior's own feet: every arrival must
  land clear of every door, nothing reachable may be off the map, and every
  door must be reachable from where players arrive. It found both boss room
  bugs, and it reads the doors, markers and walls off the scenes, so a new
  room is checked the day it is saved. A hole a single tile high can still hide
  between its steps; one two tiles high cannot.
- Not changed, noted: the field has no way back to town but dying or Switch.
  `leavetown.gd` says that is on purpose ("life is a gamble"). `easteregg` is
  in `AreaRegistry.AREAS` and is an empty scene with no script, so "Go to"
  to it arrives nowhere.

### Characters: a line about each class, and deleting one

Asked for on day 1: four fixed slots, one per class, and no way to start a
class again; and nothing on the screen said what a class is.
`_test_a_character_can_be_deleted` holds the client; the API's
`test_chardelete.py` holds the route.

- **A line under each class's name** comes from its ClassData's `description`
  (`data/classes/*.tres`). Not in gamedata.json: the server has no use for it.
  The label wraps inside the panel's width, so the four panels stay the size
  they were.
- **Delete takes Create's place** on an occupied slot. A third button would
  widen all four panels past the window.
- **It asks, and wants the name typed.** "Delete your Mage?", what goes (bag,
  gold, skills) and what stays (bank, lusions), and "Delete forever" only arms
  when the typed name matches. The server checks the same name again
  (`POST /api/character/delete`), so a stray call cannot take a character.
  It refuses while a trade names the character; the box shows the reason.
- **`CharacterData.delete_character()` saves first** (`finish_saving()`), so a
  push still on its way cannot land after the delete and write the character
  back, and it empties the slot only once the server says yes.
  `ServerStorage.forget_slot()` then forgets what was last pushed for the
  slot: a level 1 warrior deleted and made again sends the same save body, and
  without this the push would be skipped as already stored.
- **A new character starts on its class's full pools**
  (`CharacterData.new_character()`). It was pushed with SAVEABLE_STATS' flat
  100s, the server (which had given it full pools) took that as damage, and
  the full bars the game then drew were clamped as an unexplained heal: a new
  warrior came back from a relog on 107 of 180 hp, and every new character
  wrote the warning that is there to catch cheats. Found by deleting and
  making a warrior live.

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
- **Staff**: a Reports tab, mute buttons and the mute's state in a player's
  Actions tab, mutes on the record, and the Staff button counts open reports
  from the poll (`_mark_open_reports`).
- **The Reports tab is a card per reported player** (day 1: one spammer's
  twenty lines were twenty rows). A card says how many lines, how many
  people, why and when, shows their newest lines (each with a Delete while
  it is still in chat) and has one Open, Mute 1 hour and Dismiss all
  (`_make_player_card()`); a card about your own rank only opens the player.
  Mute is one request: the server closes the player's reports itself when
  they are muted, kicked or banned, from anywhere. The tab and the Staff
  button count players, not lines. A server from before the cards (no
  `players` in the answer) still gets the old per-line rows.
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

**Once per computer, not once per login.** A code on every staff login was the
owner's own complaint the first day he had it. A login that gets in with a
code is answered with a `device_token`; `Api.login()` keeps it per account in
`user://devices.cfg` (`_remember_device()`) and sends it as `device` with the
next login (`device_token_for()`), and the server lets a live one through with
no code. Its own file, not session.cfg: the session goes with Log out and
with "Remember me" off, and a mod who never ticks the box would otherwise be
asked every time. The server's rules - thirty days, a new code after any rank
change, forgotten on a password change, a reset or log-out-everywhere - are
TRUSTED DEVICES in app.py. Measured live: the first login asked and the
second went straight to character select; after a promotion it asked once
more. `_test_one_code_per_computer` holds the client side.

**One install id per computer, sent on every way in.** `Api.install_id()` makes
a random 64-hex id the first time the game runs, keeps it in
`user://install.cfg` and sends it as `install` with `login()`, `register()` and
the resume in `probe_and_resume()`. The server refuses a new account from a
computer a live-banned account has used, whatever the address (INSTALL IDS in
app.py) - the half of ban evasion a VPN does not change. Its own file for the
same reason as devices.cfg: Log out must not reset it. It is not a secret and
not a credential; the server keeps only its hash. The staff view's linked
accounts say "same computer" through `linked_how()` in ownerpanel.gd.
`_test_install_id_is_kept_and_sent` holds the client side.

### The editor's debugger lists GDScript warnings, and the game has none

The editor shows script warnings in the Debugger's Errors tab when the game
runs. There were 26 in game code on 1 October, found and cleared at once:

- **A static function called through an autoload** (`Api.clean_password()`,
  `Api.no_answer_text()`...) is `STATIC_CALLED_ON_INSTANCE`: `Api` is the
  autoload's instance. The UI calls them on the script instead -
  `const ApiScript := preload("res://src/systems/api.gd")`, the same shape as
  the `WebPage` preload - so a static helper stays static.
- A parameter or local named after something already there (`position` on a
  Control, `level` and `xp` on the player, `hidden`, `is_open`), a ternary
  mixing `null` with a typed value, and one integer division in a tool
  (`@warning_ignore("integer_division")`, because it is meant).

The headless suite cannot see these (see "Godot's warnings don't reach the
headless suite"), so the count was taken from Godot's own language server,
which reports exactly what the editor shows. `testrunner.gd` carried 73 of
its own, which showed only when the suite was run from the editor; they were
cleared in 0.66.0 the same ways (its static calls go through
`_SettingsCode`, `_CombatCode`, `_AreaRegistryCode` and `ApiForTests`).

**How to count them (container, 4.7):** copy the project, set every
`gdscript/warnings/<name>` the project leaves at 1 to 2 in the copy's
`project.godot` `[debug]` section (setting them from a script at run time
does not take), and load every `.gd` under `res://src` and `res://scene`
with `ResourceLoader.CACHE_MODE_IGNORE` from a `--script` SceneTree. Each
warning is then a `Parse Error ... (Warning treated as error.)` with its file
and line. 0 in game code and 0 in `testrunner.gd` as of 0.66.0.

### Escape closes every window, from one list

The owner, 6 Oct (0.7.3): "every window needs to close with escape also".
Escape closed fourteen of the HUD's nineteen windows, from three lists kept by
hand in characterhud.gd - `hide_panel()` (close it), `is_panel_open()` (is
there anything to close) and `_any_panel_visible()` (is the screen busy, the
guard on Escape opening Options) - and they had drifted. The doll opened alone
with G, and the GM panel alone, were closed by one and not counted by the
next, so Escape did nothing; the players list was in none of them, so Escape
opened Options on top of it; the shop, the loot bag, the kingdom board and the
trade window were left out on purpose.

- **One list, `_escape_windows()`**: every window and the way its **own x**
  closes it (a method name on the window, or a HUD Callable for the bag, the
  doll and the stats). `hide_panel()` and `is_panel_open()` both read it, and
  `_any_panel_visible()` is gone: nothing open means Escape opens Options.
- **Escape does what the x does, nothing more.** That is what makes the trade
  window safe - its x has never cancelled a trade, only hidden the window, and
  the trade waits on the server. The loot bag gained a public `close_panel()`,
  like the cooking screen's, so the HUD does not call a private handler.
- **A new window goes in the list.** `_test_escape_closes_every_window()`
  opens each of the nineteen alone, presses Escape and checks it closed, and
  fails on any script under `src/ui/` built on `PanelWindow` that is not one
  of them.

Dialogs and menus inside a window (the bin's confirmation, a row's right-click
menu) are Godot's own, and close on Escape by themselves.

### A window is never made bigger than the screen

Options offered 2560x1440 and 3840x2160 whatever the monitor, and on day 1
the owner picked one on a smaller screen: the window's title bar went off the
top, Options with it, and the way back was editing `options.cfg` by hand
(`%APPDATA%\Godot\app_userdata\ElusionRPG`). Now:

- **The picker greys out a size that does not fit** and says "too big for
  this screen", asked on every open because the window may be on another
  monitor by now (`_mark_window_sizes()` in optionsscreen.gd).
- **A size that arrives anyway is brought down as it is read.**
  `Settings._normalise()` puts `window_width` / `window_height` through
  `fit_window_side()`, so a file saved too big, or saved on a bigger monitor,
  fixes itself at the next launch and the file is rewritten.
- **"Fits" is the usable screen less the window's own frame** -
  `Settings.window_room()`: the taskbar is not usable, and a title bar is not
  part of the window's size. On a 1080p screen that is about 1904x1001, so the
  biggest window is 1600x900; fullscreen is the way to fill it. Headless and
  the browser have no screen to measure, and nothing is shrunk there.

`_test_a_window_never_outgrows_the_screen()` holds it, sabotage-checked.

### Three screens at three refresh rates: window mode, monitor, Match screen

The owner, 7 Oct (0.7.6): "the game runs really rough on my screen but only
this screen not my other 2". His desk is a 180 Hz LG UltraGear (FreeSync), a
100 Hz LG UltraWide and a 59.94 Hz Samsung, and the game was rough only on the
Samsung. MONITORS AND WINDOW MODES in settings.gd is the whole story; in short:

- **A window, or borderless fullscreen, is composited**, and with screens at
  different rates V-Sync can keep time with a screen other than the one the
  window is on - 100 frames a second shown on a 59.94 Hz screen is one frame on
  some refreshes and two on others. Godot's own stutter guide recommends
  exclusive fullscreen on Windows; a Godot forum report (4.5, 144 Hz and 60 Hz)
  found borderless running at the other screen's rate.
- **Window mode** replaced the Fullscreen switch: Windowed, Borderless
  fullscreen (what the switch was) and **Exclusive fullscreen**, which takes
  that one screen over. An old `fullscreen=true` is read as borderless
  (`Settings.stored_value()`), once, and the key is gone from the file. A
  browser has one fullscreen: exclusive is greyed out there.
- **Monitor** lists every screen by size and rate - "1920 x 1080, 60 Hz",
  "(main)" on the primary - never by number, because Godot's order is not
  Windows' Display 1/2/3. Picking one moves the window (out of fullscreen to
  move, back in there; a window too big for the new screen is brought down).
  One screen, or a browser, hides the row. `screen` is -1 by default: nothing
  moves a window nobody placed.
- **Where it was is remembered.** A once-a-second window watch (a Timer on the
  Settings autoload, `_watch_window()`) records the screen and the window's
  spot on it - counted from that screen's corner, never negative, because a
  screen left of the main one has negative desktop coordinates - once the
  window has held still for a look (`note_window_place()`).
- **The next launch STARTS there instead of jumping.** The exported game writes
  `display/window/size/mode`, `initial_screen` and `initial_position_type` /
  `initial_position` into override.cfg beside the exe - the file Godot reads
  before it makes the window - through `write_display_override_to()`, which
  touches only those keys and leaves the renderer's alone. Never in the
  editor, whose override.cfg is the project's own. Checked on a virtual
  display: an override.cfg position is where the window opens, with nothing
  moving it afterwards. A screen that has gone, or a spot no screen contains,
  opens centred on the main screen (`_place_window_at_launch()`,
  `_rescue_offscreen_window()`).
- **Frame cap: Match screen** (-1, `FRAME_CAP_MATCH`, second on the list): the
  window's screen's rate, rounded - 60 on the Samsung - and it follows the
  window to another screen through the watch. Not the default: with V-Sync
  working, no cap is still right (FRAME PACING).
- **The readout says which screen is timing the game.** `timed_by_screen()`:
  V-Sync on or adaptive, clearly more frames than this screen shows, nothing
  capping below that, and within a few frames of another screen's rate. Then
  the hint names both ("This screen is 60 Hz, but the game is drawing about
  100 frames a second - the pace of your 100 Hz screen") and both cures, and
  does not blame the driver; 2400 fps is still the driver-override hint.
- **A virtual X display reports NaN for a refresh rate**, which compares false
  with everything and slips past a `> 0` test. `_known_rate()` makes it -1.

`_test_monitors_and_window_modes()` holds all of it, including a real
override.cfg written to a file of the suite's own. A headless run has no
desktop, so the parts that move windows are read rather than run; they were
run on a virtual display (modes, the remembered spot, the rescue, an
override.cfg start). Xvfb cannot make a second monitor, so moving between
screens was first seen on the owner's desk.

### Text size and the style fonts

The owner, 7 Oct (0.8.0), picking from a list of improvements: "UI and text
size and font" - and then, of the fonts: "what we need is style fonts", "we
dont need the brail etc". So typefaces that suit the game, not accessibility
faces. TEXT SIZE AND FONT in settings.gd is the whole story; in short:

- **Text size scales every font size, not the boxes.** Nearly every label in
  the game names its own size in its .tscn or script, so a theme-wide size
  would have changed nothing. `_on_node_added()` scales each text control as
  it enters the tree; the size it was authored with is kept in a meta, the
  size drawn is that times `text_factor()`, and a size a script sets later is
  caught through `theme_changed` and scaled too. Normal (100%), Large, Larger,
  Largest (150%). **At Normal in the standard font nothing is touched** - not
  one override, not one meta.
- **The world's writing keeps its size** (`is_world_text()`: a Node2D before
  any CanvasLayer): names over heads, damage numbers, an enemy's readout are
  under the camera's zoom and inside boxes sized for them. It takes the
  font's own scale, so it looks the same size in any font.
- **The font is the default theme's `default_font`, swapped in place.**
  `ThemeDB.fallback_font` alone changes NOTHING on screen (measured on
  4.6.1); the default theme's `default_font` relayouts every existing control
  and is what new ones are born with. Bold and italic rich text are
  FontVariations in the default theme and follow. Each style falls back to
  the standard font for a character it lacks (none of them has an arrow).
  Chat keeps its own system font for its emoji.
- **Each font has a size scale** so 12 in it looks like 12 in Open Sans
  (Godot's own font), matched on the height of a small "x" - Pixelify, Fell
  and Grenze have about 0.46 of the size against Open Sans' 0.54 - and pulled
  back where that made one much wider or loud; checked by eye on Options.
- **The five are the families' own releases from google/fonts, UNMODIFIED**,
  in `assets/stylefonts/<family>/` each with its own `OFL.txt`. Two reserve
  their names (MedievalSharp, IM FELL English Roman), which binds a modified
  copy - the fontsource web subsets first tried ARE modified copies, so they
  were not used. Subset or convert one of these and those two must be renamed
  inside the font. assetlicense.md has the table.
- **Every licence text ships in the build now.** A .txt is not a resource,
  so an export left out every OFL.txt - the emoji font's too, since it
  arrived - until export_presets.cfg's `include_filter` named them.
  `_test_third_party_licences()` checks each preset names each licence.

**A window taller than the screen scrolls, and only then.** At Largest,
Options and the GM panel need more than 720 - and `fit_to()`'s "the screen
beats the minimum" would have cut their bottoms off. Each wraps its body in a
ScrollContainer handed to `PanelWindow.keep_scroll_fitted()`: the scroll is
as tall as what it holds while the window fits, and the room left when it
does not. Stats (whose header promises nothing scrolls) and the Controls card
use it too; every other window was measured at Largest in every font and
fits. Two traps found doing it:

- **A hidden window is not laid out**, so a wrapping label in it - never given
  a width - asks for two thousand pixels. Measured then, Options opened at the
  full height of the screen. So a hidden window is never measured; it is a
  frame after it appears (`_on_shown()`), and `keep_scroll_fitted()` defers
  its first look, because a panel's `_ready()` goes on to hide it.
- **A ScrollContainer's minimum does not move with what it holds**, so what
  the scroll holds is watched itself; otherwise the password form opening in
  Options would scroll instead of making room.

`_test_text_size_and_font()` holds it: every size scaled and put back, the
world's writing, the font swap and back, the licences, the Options rows, and
every window found by what it calls, at Largest in the two tallest fonts.

### Keys you can change

The owner, 7 Oct (0.8.0): "Rebindable keys. The Controls page shows the keys,
but Options has no way to change them." `src/systems/keybinds.gd` is the
whole story:

- **One object, `Settings.keys`**, set up in Settings' `_ready()` before any
  scene asks the InputMap for a key, kept in `user://keys.cfg` - not in
  DEFAULTS, because a binding is two keys per action and every DEFAULTS key
  is one control in Options. The file holds only what differs.
- **What can be changed**: the four walks, sprint, attack, use, the six window
  keys (Kills joined them in 0.9.0) and the ten hotbar keys, two keys each (a first and a second, the way
  W and Up both walk). The suite fails if project.godot gains an action that
  is not on the list. **What cannot**: Escape (closes windows, cancels a key
  being set - bound away, nothing could be got out of), the backquote (the GM
  panel) and Enter (chat); trying says what they are kept for.
- **The defaults are project.godot's own**, read at launch, and put back
  exactly at Reset - the Map's binding is the printed letter M, not a
  physical key, and stays so. New bindings are physical keys, like the rest.
- **The hotbar's keys are actions now**, `hotbar_1`..`hotbar_10`, made at
  launch from `Hotbar.SLOT_KEYS`; `slot_for_key()` asks them, and each slot's
  number is the key on it (`refresh_key_labels()`). **A new key is made the
  same way** (`Keybinds.MADE_HERE`, where `kills_toggle` on K lives), never by
  editing project.godot from outside the editor: the editor keeps its own copy
  of that file and writes it back over an action added behind its back.
- **A key on two actions is moved, not doubled**, and the card says whose it
  was: "Bag is on E now. It was Use the shop...'s, which has no key now." An
  action left with no key is red on the card.
- **Changed on the Controls card**: Change keys (on the card, or on Options'
  footer) turns the list into buttons; click one, press the key. The press is
  taken in `_input()` and marked handled, so pressing I to put the Bag on I
  does not also open the bag. A button is repainted in place, never rebuilt:
  rebuilding the grid from inside a button's own signal frees the button
  mid-signal. The welcome has no Change keys - it is a new player's first
  minute.
- **Everything that names a key reads it live**: the Controls card, the bar's
  tooltips (repainted on `keys.changed`), the hotbar's numbers.

`_test_rebindable_keys()` holds it, with a scratch keys file
(`Keybinds.path`), never the machine's own.

### The kill record: every monster, with its picture

The owner, 7 Oct (0.9.0): "lets make a button in game that records all players
kills with icons of the enemies". Social > Kills, or K - in the Social
dropdown beside Kingdom, not on the bar, because the bar was cut to eight
buttons on day 1 for being crowded.

- **Two tabs.** You: this character's kills of each monster, most first, and
  when the last fell; then every monster it has not killed yet, greyed - the
  record is also the list of what is left to find. Everyone: each monster's
  total across every account, how many players, who has killed the most (an
  account, its characters added together) and your own share.
- **The server counts** (api CLAUDE.md, "The kill record"): `kill_tally`,
  paid kills only, kept for good. **It has a birthday** - the first boot
  counted what `kill_reports` still held (two weeks) - and the summary line
  says "counted since" that day rather than letting a young record pass for a
  lifetime one.
- **The pictures are the monsters' own art** (`EnemyPortraits`): the first
  frame of the idle pose from each one's scene, instantiated and freed without
  entering the tree, dressed as in the world - the element recolour its
  EnemyData asks for (`BaseEnemy.element_material()`, shared with the live
  monster now) and its body tint - and **cut to the creature**
  (`Image.get_used_rect()`): a cell of the sheet is mostly empty, and drawn
  whole a fire sprite was a speck. Three scenes are not named for their
  enemy_id (`boss` is bossenemy.tscn; both poison slimes are poisonslime.tscn,
  the small drawn from its "small" animations), and the suite checks every
  monster that pays finds a picture.
- **The roster is data/enemies/**, read with `ResourceLoader.list_directory()`
  as ItemRegistry reads items - DirAccess finds nothing in an export.
- **A game newer than its server** gets a 404 and says "This server does not
  keep a kill record yet."

`_test_the_kill_record()` holds the window and the pictures; the server's half
is test_killrecord.py.

### Options explains itself: the help bubble (0.64.0)

The owner, 20 Oct: "what if a player changes settings unknowingly maybe we
need a hud explaining i really want to think about all playes some people
may not even know what vulkan is", then "maybe a tool tip or something".

- **A bubble beside the setting, not Godot's tooltip.** Point at a setting
  - its control or its name beside it - tap it, or reach it with the
  keyboard, and a bubble opens at once under its row (over it, near the
  bottom, so it never covers the footer's buttons) saying in plain words
  what it does, what most players want, and when to change it. A tooltip
  shows only to a mouse, after a wait, and Godot's runs on in one line -
  half the players are on a phone. The controls in Options carry no
  tooltip of their own any more.
- **It takes no room.** Options is laid out to fit a 720-high screen with
  nothing scrolling ("Options opens at the size it was drawn at", 702 px);
  a strip along the bottom, tried first, broke that, so the bubble floats
  (`top_level`, ignores the mouse) and the title bar's line is clipped.
- **The words are `HELP` in optionsscreen.gd**, keyed by each control's
  unique name; `help_for()` fills in Settings' own numbers (15 pictures a
  second in the background, 30 on Battery saver, 2 minutes to rest).
  **A new setting needs its words there** - the suite fails on a picker,
  slider or switch without them. Keep each under 240 characters.
- **What is set oddly is marked** (`help_warnings()`): the master volume at
  0%, V-Sync Off, a frame cap under the screen's rate (with V-Sync on),
  Brightness under 70%. Each shows as a line in the title bar ("Heads up:
  V-Sync is Off - the picture can tear.", or how many when there are more)
  and that setting's name in orange; its bubble says why first, and that
  "Reset to defaults" puts it back. Changing one updates the marks at once.
  A mark taken off puts back the colour the scene drew the name in.
- **Only those four settings move the marks**: the window watch writes the
  window's place to Settings whenever it moves, and that must not shut a
  bubble being read.
- **Renderer and Graphics API are explained, not hidden**, and "Reset to
  defaults" still leaves them alone (they need a restart) - the reset
  button's own words say so.
- `_test_options_explain_themselves()` holds all of it.

### The Credits: Options > Credits (0.11.1)

The owner, 7 Oct: "as for credits i think we should make it a button in
settings that says credits we can separate artists audio and support there".
`creditsscreen.gd`, a window like the rest (`credits`), opened by the Credits
button in the Options footer (`credits_requested` -> the HUD's
`open_credits()`, in front of Options). Four tabs, each built once and then
only shown or hidden:

- **Art**: Ahvassa and Caio Carlos / Clockwork Raven Studios, linked, each
  with what they made; then every font the game ships with its copyright line
  (`FONTS`) under the OFL. The suite holds `FONTS` to `Settings.FONT_STYLES`
  and the emoji font, and every owner in `LICENSED_ART_FOLDERS` to a name in
  the credits (`CREDITED_OWNERS`) - **art from a new source is a new credit**,
  and the suite says whose name is missing.
- **Audio**: who recorded the sounds, and on what (docs/audio.md).
- **Support**: `SUPPORTERS`, **the one list the owner edits** - everyone who
  bought a hot cocoa on the website and put their name in the PayPal note.
  The only list of them: the site's supporters wall went on 7 Oct ("remove
  wall keep ledger i will put their names directly into the game"). Empty, it
  says how to get on it; the link is the site's Support page.
- **Engine**: Godot's licence, and FreeType's, ENet's and Mbed TLS's, each in
  full and read from the engine (`Engine.get_license_text()`,
  `get_copyright_info()`, `get_license_info()`), then every other part of
  Godot with its licence. **Not decoration**: MIT asks for its notice in every
  copy, and Godot's guide to complying names a credits screen and those three.
  FreeType's sentence is in the words its licence asks for. The texts come
  broken at 80 columns; `reflow()` makes them paragraphs.

They were the last page of the field's welcome (`field.gd`) until now, read
once a login on the way through the portal. The owner is rewriting that
welcome as story; the credits no longer depend on it. `_test_the_credits()`.

### The Electric Sprite pet's orb flew 80 px (0.11.5)

Found measuring every pet against a boss for the website's Boss Sim: from
90 px the Electric Sprite pet put nothing into the Crowned, every other pet
put its full rate. `petmagicprojectile.tscn` set `speed = 20` where every
other pet's shot flies at 300 (the script's default), and the orb lives 4 s,
so it went about 80 px. The pet picks a target up to `aggro_range` (280) away
and keeps it to 322 (`TARGET_KEEP_SLACK`), so from anywhere but beside its
target the orb faded out on the way, for as long as the pet existed. Nothing
logged; the pet just seemed to keep missing - the fire pet's mask
(`_test_collision_contract`) again, one number over.

- **The scene no longer sets it**: 300, the same as the rest. Measured after:
  the pet lands its shot every 2 s from 90 px, as the fire pet does.
- **`_test_pet_shots_reach()`** asks every pet scene whose shot flies (it has
  a speed and a lifetime - five of the seven; the vine and the Crowned's
  rupture are put down on the target) whether `speed x lifetime` covers
  `aggro_range x TARGET_KEEP_SLACK`. With the 20 back it fails naming the
  scene and the numbers.

Also in 0.11.5: **writing override.cfg logged an engine error per key.**
`Settings.write_display_override_to()` asked `cfg.get_value("display", key,
null)`, and a default of null is the same call as no default - so every key
the file did not have yet (all of them, the first time a player picks a
screen) printed "Couldn't find the given section ... and no default was
given" before the write went ahead. It asks `has_section_key()` first now.
The suite's display section attaches an `EngineErrorCounter` (a `Logger`
that hears every engine error, not only script errors) around the write and
fails if it hears one.

### The Crowned Beholder, by name (0.11.6)

The owner, 8 Oct: "this is a crowned beholder". The seven bosses were "The
Crowned" and "Light The Crowned" to "Fire The Crowned"; they are "The Crowned
Beholder" and "Light The Crowned Beholder" and so on now
(`data/enemies/*boss*.tres` `display_name`), and the Crowned pet's
`pet_source_name` says the same. The names reach players in the Kills window
and the mythic banner, whose sentence the server writes from gamedata.json -
so it is re-exported, and **the API's copy has to follow** or a find off a
boss is still announced under the old name.

- **The town sign is the owner's**: he set it to the seven of them; 0.11.6
  only takes the apostrophe out of "Beholders".
- `_test_the_sweep_words()` (the sign check) used to keep "Beholder" OFF
  the sign, because no monster was called one; it holds the opposite now, and
  checks all seven bosses' names.
- Seven elements, seven bosses: the Crowned itself is Dark (`boss.tres`
  element 1), so there is one crown for every element.

**export_presets.cfg was written back as 0.11.0.0 on 8 Oct**, the trap under
"The version" again: the editor had been open since before 0.11.5 and saved
its old presets on export. 0.11.6 is set over the copy read off the PC.

### The finale ends in town, and a pet says how to summon it (0.11.7)

The owner, 8 Oct: "final teleport does not return to town". The way through
is field ladder -> arena (six bosses) -> the arena's victory teleporter ->
the Crowned's room (`boss.tscn`). That room's only exit was its ladder up to
the field, so beating the last boss in the game put you back in the Field.
The container's `finale` run walked it and said so.

- **The Crowned's room has a victory teleporter now**, at (-464, -8) in the
  north half of the room, clear of the corridor along its south side that
  leads to the ladder. Hidden and unsteppable until the Crowned dies, then
  it appears and goes to the town (its default destination), where the town
  puts you at `playerspawn` as a login does. The ladder stays, for leaving
  without the win. Move the node in the editor if you want it elsewhere; the
  walk test checks it can be reached.
- **`victoryteleporter.gd` has `boss_path`**. Set, it waits for that boss's
  `died` instead of the arena's `gauntlet_cleared`. It also watches every node
  of the same scene that enters the boss's container, because **the boss that
  dies may not be the node the scene placed**: the respawner brings a boss back
  as a new node, and with shared monsters a player who walks in after someone
  else's kill has their copy removed without a death (`net_remove`, no
  `died`) and fights a mirror built fresh. A second kill while it is open or
  opening does nothing (`_revealing`).
- **A pet's tooltip says "Right-click in your bag to summon it, and again to
  put it away"** (`ItemTooltip.use_line()`). Reported as "issues with pet
  spawning when clicked on from inventory"; walked in the container with real
  mouse events, a left click and a double click leave the pet in the bag (a
  left click selects the cell; a double click is the bank's transfer), and a
  right-click summons it - which only Options > Controls said.
- Tests: `_test_the_finale_sends_you_home` (the room's wiring, and the node
  with stand-in bosses: not fooled by another monster, opened by the boss,
  opened by a replacement boss) and `_test_a_pet_says_how_to_summon_it`.

**export_presets.cfg came back as 0.11.0.0 again** an hour after 0.11.6 set
it: the editor was still open from before 0.11.5 and exported. 0.11.7 is set
over the copy read off the PC. Close Godot and open it again after pulling a
version change, before exporting.

### Old versions must update, from the Server tab (0.11.8)

The owner, 8 Oct: "how to raise client build". The server has had the gate
since the build header went in - `POST /api/server/minbuild`, owner only,
`min_client_build` on `/api/status` - and nothing in the game could set it,
so the answer was a request carrying his token by hand.

- **GM panel > Server, under WHO MAY LOG IN: "Old versions must update"**
  (`ownerpanel.gd` `_on_minbuild_toggled`). On asks for `Api.BUILD`, the
  build of the game the owner is holding; off asks for 0. Never a typed
  number: the server already refuses a minimum newer than any game it knows,
  and this makes the switch unable to lock out the person throwing it.
- It shows the server's minimum when the panel opens (`_refresh_minbuild`,
  with PvP and trading), and a line under it says where it stands. A refusal
  puts it back. The server logs who set it (staff log, "minbuild").
- **When to throw it:** after a version with a new `Api.BUILD` is out on the
  web and the download. Build 4 is every 0.11.x game; anything before 0.11.0
  is build 3 and cannot read the resist ids the server now rolls.
- **A word-wrapped label in a hidden tab measures as a column of letters.**
  Adding the switch made the GM panel 22 px taller on Account and Testing than
  on Server ("the window is the same height on every tab" failed: 642, 642,
  620). The Server tab is the shortest when it shows (172 px) and measured 424
  while hidden: `maintenancestatus` wrapped with `AUTOWRAP_WORD_SMART`, which
  may break inside a word, and a tab never shown has width 0, so "Server is
  OPEN" stood fourteen lines tall in the hidden-tab minimum. It wraps at words
  now (`AUTOWRAP_WORD`): three lines while hidden, and the tabs measure 620 on
  all three. The new status line does not wrap at all.
- `_test_old_versions_must_update`.

### Mythic weapons worth the wait, and the axe spins up (0.11.9)

The owner, 8 Oct: "mythic weapons need a power buff they are pretty weak for a
super rare drop", and "double axe needs to speed up when left deployed".

- **Why they were weak.** A mythic rolls quality like any drop (85-115%, a
  Perfect 120%), and the Double Axe was 110 against the Ember Sword's 100,
  with 9% against 8%. An ember sword rolled 110% or better matched it, and a
  Perfect ember sword (120) beat it - for a drop of one in 20,000 from the
  dark band.
- **Now 1.4 times ember, and 15%.** `doubleaxe.tres` 140, `meteorite.tres` 53,
  `dynamite.tres` 23; `bonus_damage_percent` 15 on all three. The Meteorite
  and Dynamite are the axe's share of their class's dps, as the API's
  `test_equipment.py` requires (52.5 and 23.3). A warrior's hit with the axe
  ((24 + 140) x 1.15) is about 1.4 times an ember sword's ((24 + 100) x 1.08),
  and about 1.2 times a Perfect one's.
- **The axe spins up** (`spinningaxe.gd`, SPIN UP). Left spinning, its rate
  climbs evenly from 1x to `SPIN_MAX_RATE` (2) over `SPIN_RAMP_SECONDS` (4),
  and holds. Each tick is still a tick's share of a swing, so the cuts a
  second double, and `spin.speed_scale` follows so it looks faster. Recalling
  it puts the picture back to 1x; every throw starts at 1x. The first tick
  still lands `TICK_SECONDS` after it stops (the step's rate is the rate at
  its start), so the old tick check is unchanged.
- **The server's books allow for it.** The exporter writes `SPIN_MAX_RATE`
  as `combat.classes.warrior.axe_spin_max_rate`, and the API's
  `combat_bounds()` bounds a warrior with the axe at a pass plus
  `(1 + axe_spin_max_rate)` swings a second (it was 2 a swing). **The API's
  gamedata.json has to go out first**, or a warrior with the axe left
  spinning is written down as too fast. The books only watch, but it is a
  false line on an honest player.
- The Boss Sim on the site models it the same way (`AXE_SPIN_MAX`,
  `AXE_SPIN_RAMP`, a new target a new throw), and its test holds the numbers
  to this file.
- Tests: the mythic section's SPIN UP checks (lands at 1x, about four cuts in
  the first second, eight a second at the top, each still a tick's share, the
  picture's speed, a recall and a new throw back at 1x) and the books' check
  that the exported rate is the game's.

### The Meteorite burns and Dynamite chains (0.12.0)

The owner, 8 Oct: "dynamite douse not feel that special or meteor". Offered a
list: "i want the meteor to be bigger yes leave burning crator with fire damage
knock back is a bad idea chain reaction sounds cool", and "fire effects on the
ground where meteor hits". Nothing in this is knockback.

- **The meteor is twice as wide**: `Meteor.HIT_RADIUS` 44 (was 22, against
  the stalagmite's 18), and `meteor.tscn`'s shape with it. The crater mark,
  flash and ring are drawn from the radius, so they grew too.
- **The crater burns** (`src/projectiles/burningcrater.gd`, `BurningCrater`,
  built in code like Blast and spawned by `Meteor._impact()`): for
  `BURN_SECONDS` (2.5) flames rise out of it (Blast's puff, shrinking as it
  rises, and squares for sparks) over an additive orange glow on the floor;
  every `BURN_EVERY` (0.5) every enemy in it takes `BURN_SHARE` (a fifth) of
  the meteor's hit as `Element.Type.FIRE`. Five bites, so a meteor's hit
  again for whatever stays in the fire. The bites go by their own times
  (`_bites`), so a long step still bites as often as it should and never
  after the end.
- **One fire at a time per enemy.** Casts overlap at one spot; an enemy burns
  from the crater that burned it last (meta `&"burning_by"`, an instance id)
  until that one goes out. So the most fire any enemy takes is a fifth of a hit
  every half second, which is what the books allow.
- **Dynamite chains** (`dynamite.gd`, CHAIN REACTION). A blast sets off every
  LIT stick within `CHAIN_RADIUS` (42: the blast's reach and half again, so a
  double throw's two sticks, 40 apart, chain) `CHAIN_DELAY` (0.1) later - a
  ripple - and a stick set off that way hits `CHAIN_BONUS` (25%) harder with a
  bigger fireball; its blast sets off the next. Sticks in the air do not
  chain. **The fuse went from 0.9 to 1.2**, longer than the tank's
  `dynamite_cooldown` (1.0): at 0.9 a stick was gone before the next landed,
  and nothing could ever chain. Now every second stick thrown at one spot is
  set off by the first, and a quicker tank chains three.
- **The books allow for both**: the exporter writes `meteor_burn_share` and
  `meteor_burn_every` on the mage's combat row and `dynamite_chain_bonus` on
  the tank's; the API's `combat_bounds()` adds the burn to a Meteorite mage's
  rate and multiplies a Dynamite tank's biggest hit and rate by the bonus.
  **The API's gamedata.json goes out first.**
- Item descriptions say so; the Boss Sim on the site models the burn on the
  boss being hit and the chain as groups of `1 + floor(fuse / throw period)`.
- Tests: the meteor section (twice as wide and its shape matching, two
  enemies paid XP, the crater as wide as the hit, flames and glow, a fifth a
  bite as fire, nobody pushed, two craters biting once, five bites then out,
  the next crater taking over), the dynamite section (a blast sets off the lit
  stick beside it a beat later and 25% harder, not the far one, not one in
  the air, not one already gone; the fuse outlasts a throw; a double throw's
  sticks are in chain range) and the books' check of the exported numbers.

### Dynamite's scorch smoulders (0.13.0)

The owner, 8 Oct: "we need some sort of bonus damage for tnt like a field
effect".

- **Every blast leaves its scorch smouldering** for `Dynamite.FIELD_SECONDS`
  (1.5): smoke rolling up and white-hot sparks spitting out over a deep red
  glow, and every `FIELD_EVERY` (0.5) whatever stands in it takes
  `FIELD_SHARE` (15%) of the stick's plain hit (not a chained one's) as fire.
  Three bites, nearly half a stick again: about a quarter more damage a second
  on one target with the double throws and chains counted, and every enemy in
  the scorch takes it.
- **It is `BurningCrater`, configured**: `spawn_smoulder()` sets `bite_share`,
  `bite_every`, `lasts`, the look (`smoulder`, named "smoulder") and its own
  one-at-a-time mark, `&"smouldering_by"`, apart from the meteor's
  `&"burning_by"` - a mage's crater and a tank's scorch are two players'
  fires, and each is bounded on its own player. A chain's overlapping scorches
  do not stack. The meteor's crater keeps its constants as the defaults.
- **The books allow for it**: the tank's combat row carries
  `dynamite_field_share` and `dynamite_field_every`, and the API adds the
  smoulder to a Dynamite tank's rate. The API's gamedata.json goes out first.
- Tests: the scorch is left as wide as the blast, smoke and sparks, a bite of
  FIELD_SHARE, not outside it, its own mark, FIELD_SECONDS of bites then out;
  and the exported numbers.

### Bigger Dynamite, a bleeding axe and the meteor's vortex (0.14.0)

The owner, 8 Oct: "dynamite needs a bigger blast radios need to be able to
throw faster and use tank ring i feel like 1 by its self is not enough to be
impressive"; of all three, "each weapon is unique but i want them to be
powerful but balanced i mean the odds of getting one might aswell pay for";
"we need to add a effect to double axe also to give it that feel mind you
there will be much more difficult enemies later in the game so they may feel
over powered now but i expect them to prove their worth"; and "can you add a
fire vortex around the meteo when it falls to really draw out that final
fantasy effect".

- **Dynamite** (`tank.gd`, DYNAMITE SETTINGS, which has the before and after):
  the blast is the meteor's 44 (`Dynamite.HIT_RADIUS`, was 28, and
  `dynamite.tscn`'s shape), the chain reaches 66 (`CHAIN_RADIUS`, was 42) and
  the smoulder follows the blast. A throw every 0.75 s (`dynamite_cooldown`,
  was 1.0) for 3 mana (was 4): the ring's own 4 a second. **The ring burns
  while it throws**: a throw lights it (`_light_ring_by_dynamite()`,
  `ring_by_dynamite`), it drains no mana of its own, and it goes out
  `DYNAMITE_RING_LINGER` (3 s) after the last throw. Putting Dynamite on puts
  out a ring the aura key lit (attack cannot reach it to turn it off);
  taking Dynamite off puts out one its throws lit. A stick is
  `dynamite_stick_ticks` (1.5) ring ticks, where it was the cooldown's worth
  (4) - smaller, because there are more of them and the ring burns too.
  **Every fifth throw is a bundle**: `DYNAMITE_BUNDLE_STICKS` (3) sticks in a
  triangle `DYNAMITE_BUNDLE_SPREAD` (14) round the aim, each a beat behind the
  last; the first sets off the other two, so the middle takes all three, two
  chained. A bundle does not also roll a double. The double's spread went to
  28 for the bigger blast. (Both replaced at 0.18.0 by one roll a throw - see
  "The mythics' rolls".)
- **What it comes to**, one boss at level 22 in Ember gear by the Boss Sim's
  model: an Ember maul tank ~165 a second, Dynamite in 0.13.0 ~338, now ~440
  (2.7x), the ring about half of it and reaching every enemy round the tank.
- **The Double Axe** (`spinningaxe.gd`, WHIRLWIND AND BLEED): its reach grows
  with the spin, from `HIT_RADIUS` (20) to `REACH_AT_TOP` (1.6) times that at
  full speed, on **its own copy** of the scene's CircleShape2D (the scene's is
  shared by every axe); wind streaks are drawn round it (`_draw`) and dust is
  swept round the rim ("whirl", orbiting particles), both faster and brighter
  as it spins up, and gone when it is called back. **Every cut opens a wound**
  (`src/projectiles/bleed.gd`, `Bleed`, a child of the enemy): `BLEED_SHARE`
  (a quarter) of a swing every `BLEED_EVERY` (0.5) for `BLEED_SECONDS` (2)
  after the last cut, red drops falling, one wound per enemy (meta
  `&"bleed_wound"`; a fresh cut keeps it open at the new size, and it bites
  on its own clock). One boss at level 22: ~486 at 1x and ~829 at full spin
  against an Ember sword's ~428 (1.9x). `SpinningAxe.wounds` is the suite's
  switch for counting cuts alone.
- **The Meteorite** (`meteor.gd`, THE FIRE VORTEX): picture only. Two ribbons
  of fire corkscrew round the path behind the stone (`_sky`, a Node2D in the
  sky layer drawing through `_draw_sky()`), sparks orbit the stone ("whirl"),
  and on the ground a ring of fire swirls in from `SWIRL_FROM` to `SWIRL_TO`
  of the hit with flames twisting up off it ("swirl"), tighter and brighter as
  it falls; all of it goes out on impact. `vortex_burning()` is for the tests.
- **The books** (the API's `combat_bounds()`): the warrior's row carries
  `axe_bleed_share` / `axe_bleed_every`, added to the axe's rate; the tank's
  `dynamite_stick_ticks` and `dynamite_bundle_every` / `_sticks`, bounded at
  three sticks every throw on top of the ring. **The API's gamedata.json goes
  out first.** The Boss Sim models all of it and its test holds the numbers.
- Tests: the mythic section (the vortex up while it falls and out on impact;
  an axe's own circle, its reach at 1x and at the top, what stands past it
  cut only at the top, the wind, a recall; a wound a quarter of a swing, the
  drops, one wound however many cuts, its bites, closing, a new one after;
  the blast the meteor's size; the ring lit by a throw, no mana, kept lit,
  out after; the bundle round the aim, its delays and price, all three on
  the middle; the gear and the ring) and the books' checks.

### Inventory, bank and shop on day 1

A sweep of the backpack, the bank chest and the vendor, driven through the
real panels against the real server.

- **Banking gold did nothing on the server.** The panel's deposit and
  withdraw moved the purse and the bank on this machine, and nothing called
  `POST /api/bank/gold` - gold is server-owned, so the status push ignores the
  purse, and serverstorage.gd deliberately pushes no `bank_gold`. Banking 200
  of 257 showed 57 carried and 200 banked while the server held 257 and 0; a
  relog put it back in the purse, and a death would have burned it all.
  `CharacterData._move_bank_gold()` asks the server now and copies its two
  figures in; the panel sends one move at a time and says why a refusal was
  refused. `bank_gold_request` is the suite's door, so the test never moves
  real gold. `_test_banked_gold_goes_through_the_server` holds it.
- Worked as they should: moving, swapping and merging cells, a stack onto a
  hotbar key and drinking from the key, equip and unequip, items in and out
  of the bank, the bank shared by every character on the account, buying,
  "You cannot afford that", the server's own refusal, a full backpack (409,
  no gold taken), and all of it identical after a relog.
- Not changed, noted: vendors sell and never buy. The server says so on
  purpose ("the whole reason vendors sell rather than buy" - the shop is the
  gold sink), so loot a player does not wear is only worth a trade.
- **Deposit and Withdraw are drawn like hotbar slots** (day 1): the theme's
  `ButtonSocket` variation is a Button on the same `hotbarslot.png` socket the
  hotbar and every grid cell use, brighter under the pointer and darker when
  pressed. Any button can wear it with `theme_type_variation = &"ButtonSocket"`.
- **The gear squares are hotbar slots too** (day 1): `equipmentslot.tscn` wears
  `PanelSocket` itself, and the eight squares on the doll no longer override it
  with the flat `PanelSlot` (which friends, guild, chat and character select
  still use). `_test_slots_wear_the_hotbar_socket` names any square left flat.

### Friends, guilds and trades on day 1

A sweep with two real accounts: the game on one, a scripted second player on
the other, against the real server.

- **Founding a guild did not show what it cost.** The server took 5,000 (1,000
  carried, 4,000 from the bank) and the game went on showing 1,000 and 4,500
  until a relog, so the shop offered what the server then refused. The
  founding answer carries `carried_gold` and `bank_gold` now, and the guild
  panel's `_act()` hands any answer to `CharacterData.adopt_server_gold()`,
  which copies whichever of the two it finds. The owner's gold grant had the
  same half-copy (the purse, never the bank) and uses it too.
  `_test_founding_a_guild_shows_what_it_cost` holds it, through the panel's
  `post_request` door.
- **A friend request or a guild invitation reached nobody.** Both are answered
  from a panel, and nothing told the player to open it. The broadcast poll
  carries `asks` now: how many of each are waiting, and the newest. The HUD
  lights "Friends •" and "Guild •" while anything waits and says the newest
  once ("caster asked to be your friend. Open Friends to answer."). The state
  is static per login, like the chat dot, so a door neither repeats the toast
  nor darkens the button. `_test_a_request_waiting_on_you_lights_its_button`
  holds it; the asker's notice says so now instead of "They will see it next
  time they look".
- Worked as they should: asking, refusing yourself, a name that does not exist,
  accepting, online and "1 min ago" presence, removing; founding (a bad name
  refused before anything is sent, the cost paid from both piles), inviting,
  joining, guild chat with the tag over the name, promoting, demoting,
  removing, the two-press disband; a trade of two potions for 100 gold, taxed,
  with both bags right on the server and on screen.

### The bag is the server's

Found cooking on day 1: a stack of twelve raw fish made five cooked ones where
the cooking XP said six. The bag was saved whole (`PUT /api/character/inventory`)
on a two-second debounce while the cook, the catch, the loot take, the purchase
and the equip changed it on the server too, so a save built after one cook and
landing after the next deleted the fish the next cook made. `based_on` (the
save naming the bag it was built on) fixed that on day 1.

Then the save stopped carrying the bag at all, on the owner's call: the
backpack ledger being "still client-declared" was an honest limit worth
closing. Every change is a request now, and the grid is drawn from the answer.

- **A drag inside one grid** (bag, keys, or the bank) is drawn at once by
  `InventorySlot._drop_data()` - B1 move, B2 merge, B3 swap, the same three
  rules `_grid_move()` applies on the server - and sent by the grid as one
  `request_move()` (THE SERVER DOES IT in inventorycontainer.gd). A drop in a
  gap is a move onto the first empty cell.
- **One at a time, in order, and only the last answer is drawn.** Two quick
  drags are two requests and the second is built on the first; drawing the
  first answer would flick the second drag back.
- **A 409 carries the grid** when the cell held something else (a trade landed):
  the carry's goes through `apply_server_carry()`, silently for
  `reason: "stale_save"`; the bank's reloads the bank grid. No answer at all
  keeps what is drawn, and the next answer puts it right.
- **The bin** is `request_discard(cell, item_id)`; a cell holding something
  else by the time Destroy is pressed is left alone.
- **A pile of coins or lusions** is `POST /api/character/inventory/cash`. It
  used to add gold here, which the server has ignored since E-8, so the pile
  was destroyed and the gold was gone at the next login.
- **A potion's answer carries the bag**, and `_adopt_carry()` draws it unless a
  drag is still on its way.
- **A save carries neither the bag nor the bank** (`_slot_sections()`,
  `_account_sections()`), and `bag_base`, `bag_sent()`, `bag_saved()` and
  `_adopt_refusal()` went with them. `is_carry` / `is_bank` on the grid say
  which routes it uses.

Played against the real server (the `bagserver` harness mode): four quick
drags, a key, the bin, a coin pile and the bank, each matching the server with
no save, and the same after a relog. `_test_the_bag_is_the_servers` holds the
client half, `test_bagmoves.py` the server's.

### Fishing and cooking on day 1

Driven at the town pond and firepit against the real server: a cast, a strike
too early ("Too early", no worm spent), a catch every time the float went
under (one worm each, fishing XP from the server), lighting the fire, the
cooking screen, single cooks and a whole stack, burns, and the skill bars.
Everything but the loss above worked. Two gaps, both closed by the store on
the owner's call:

- **Only the iron rod could be had.** Jade to ember rods are not droppable and
  were not sold, so the deeper fish were out of reach (`fish_ceiling()` is rod
  tier plus fishing level / 20). Iron to amethyst rods are sold now; ember is
  still found only.
- **Worms came one at a time from loot**, about 1.6 an hour in the first two
  bands and none past the third, and every catch spends one. They are 24 gold
  each in the store. Measured after: twenty worms and a jade rod bought by a
  fresh character, and a marsh carp (tier 2) on the third cast.

**The cooking window, day 1.** It opened in the top left corner. Its root is a
plain Control, and `reset_size()` on one does nothing, so it sat at 0x0 in the
middle of the screen with the panel spilling out round it. Every drag, resize
and fit then measured a rectangle of nothing, and the owner's `panels.cfg`
held `cooking` at (58, 40). Now `_fit_and_centre()` sizes the window from its
content (`PanelWindow.content_minimum()`) and centres it on every open, since
the window belongs to the fire you are standing at. The fish are one row of
six, one cell per kind (`one_cell_per_kind()`; a cook asks for an item_id,
never a cell). A second row appears only past six kinds
(`InventoryContainer.resize_grid()`), and the window follows when a row comes
or goes. The fire, glow, sparks, icon, bar and labels stay centred however wide
the window is made (`_centre_fire_contents()`). The header reads COOKING like
BANK and INVENTORY; the level is a "Lv 1" badge on the left as wide as the ×
on the right, so the title sits in the middle (it read "Cooking  Cooking 1  ×").
`_test_bank_buttons_and_the_cooking_window` holds all of it.

**The fire shows the fish it is cooking (0.25.2).** The owner: "cooking meter
was not matching up and burned fish vanished to quickly". Recorded against a
stand-in server before the fix, four faults:

- **A burnt fish stayed charred through the next fish's bar.** The result
  tinted the icon, and nothing put the next fish on the fire as its own: it
  went on still burnt, and turned back only when ITS result came in, one fish
  late. `_show_fish()` now puts every fish on, in its own colours, as its bar
  starts.
- **A click on another fish showed it, and cooked the first kind.** The loop
  held the item_id it started with and cooked that to the end of its stack;
  `_update_controls()` redrew the fire from `_selected`. The loop reads
  `_selected` before every fish now, and a switch says "Next: ..." while the
  fish on the fire finishes.
- **The bar meant two things.** The cook, gold, and then for the 0.35 s
  between fish the burn chance, orange, at another length. The bar is the cook
  alone now - gold, or ash when the fish burnt - and the chance is words under
  the fish ("Raw Marsh Carp  ·  5% burn", `risk_text()`).
- **A burnt fish was gone in 0.35 s, and the last one at once.** Every result
  is held before the next fish (`_show_result()`): the cooked fish itself for
  `cook_interval`, a burnt one charred with "Burnt!" for `burnt_hold` (1.2 s),
  and the last fish of a run too, which then fades off (`_end_fire()`).

The fire is drawn by the run alone (`_show_fish`, `_show_result`,
`_end_fire`); `_update_controls()` only clears it when no run is on it. A run
has a number (`_run_id`), moved on by closing or opening the panel, so a loop
still waiting on a fish from before leaves without touching the new one.
`_test_the_fire_shows_the_fish_it_cooks` runs the panel against a stand-in
server (`CookingServer`) and a stand-in backpack, and each of its checks was
watched failing with its fault put back.

### Pets, the map, the kingdom board, Options and the owner panel on day 1

Driven in the game against the real server.

- **The map was blank at every login.** Two faults, each enough on its own:
  - `ServerStorage.load()` built each character from `/api/character`, which
    carries no map; the listing (`/api/save`) does. Every login started with
    none, and the first save after a walk wrote that session's tiles over
    everything the character had uncovered. `with_listing()` takes the map from
    the listing now.
  - The map rides `/api/save` only when WorldMap's revision moves, at most
    every `SAVE_REVISION_SECONDS` (45). A walk then a logout inside that window
    left the walk behind. `finish_saving()` calls `WorldMap.flush_pending()`
    first, so leaving counts it; 45 s is now a cost only a crash pays.

  Measured after: 6% of the field walked, a logout at once, and 6% back on the
  next login. `_test_the_map_comes_back`.
- **One character's map is not another's world (0.68.1).** The owner's log:
  "the stored map for 'bigfield' would not decompress to the size it
  claims". `WorldMap._terrain` outlives a character: after another character
  walked the Big Field (or after dying and picking another), the area is built
  at today's size, and `from_save()` kept the new character's bits - saved
  before the crypt made the field bigger (0.63.0) - beside it. The next save
  wrote today's width and height round the old bits. Now `from_save()` starts
  a map again when it does not fit the area as built (the same rule as
  `_build_terrain()`), replaces a stub left by another character's save, and
  `to_save()` never writes bits that do not fit their size. A character
  already saved broken shows the warning once more, then the map is right.
  `_test_one_characters_map_is_not_anothers_world()`.
- **...and the broken copy is replaced, not only skipped (0.73.1).** The
  owner's log, 22 Oct, the same warning on a healer: "seems like a bug we ran
  into a couple times already". "Once more, then right" above was only true
  if a save went out after it: `from_save()` dropped the map from WorldMap,
  but the slot and the server still held it, and the map rides a push only
  when the revision moves (45 s of walking) or something else changes. Log
  in, stand in town, log out - and the next login read the same broken map
  and warned again. Now `from_save()` names what it left out
  (`WorldMap.dropped_on_load()`) and counts it as a change, and
  `load_character_state()` puts the map as it now is into the slot, moves
  the revision and calls `save_data()` - so the first push replaces the
  server's copy and the warning is seen once per character.
  `_test_a_broken_map_is_mended_once()`.
- **Pets worked:** summoned from the bag, through a door, through a relog, and
  put away with a second use; the sniper followed and took 84 health off a dark
  sprite in eight seconds. The server stored whatever `active_pet_id` a save
  named, owned or not, so a modified client could walk out a pet it never
  won; on the owner's call it now keeps only a pet the carry or the bank holds
  (API `test_api.py`). The game needs no change: a pet is summoned from the
  bag, so it is always held.
- **The kingdom board** opened with the coffers, the death count, the player's
  own line and the ranking.
- **A staff teleport** (a dev sending the player to the field) reached the
  game within one poll and landed on the field's arrival dais.
- **Options** worked: the name colour reached the server and came back after a
  relog, the toggles and the camera zoom stuck, a wrong current password was
  refused without signing anyone out, the right one changed it and the game
  kept its session, a recovery address was confirmed with the mailed code (a
  wrong code refused first), and Reset put everything back.
- **The owner panel** worked: gold to the bank and to the purse (both shown at
  once now), an item grant, PvP on and off on the strip, and closing the
  server with a message and reopening it before the countdown ran out.

### Saving and reconnecting on day 1

Measured against the real server, on the desktop build and in Chromium:

- **The server gone 15 s, a bag change made meanwhile.** The change reached the
  server once it was back, with no relog. The strip showed "Connection lost"
  for 12 s after the restart, because the next poll was up to ten seconds
  away. While the strip is up the poll now runs every `OFFLINE_POLL_SECONDS`
  (5) and goes back to ten on the first answer; a 30 s outage then cleared
  within 10 s of the restart. `_test_a_lost_server_is_asked_for_more_often`.
- **Gone 100 s.** The countdown ran from 1:05, and at 0:00 the game went to the
  login screen with "Lost connection to the server. Anything since your last
  save is not saved." Signing back in worked, and the change made while the
  server was down was gone, as the line says.
- **A kill with the server down** paid nothing on either side ("Server offline
  — no reward."). The next kill after it came back levelled the character, and
  the game and server agreed.
- **The game killed outright** 2.5 s after a bag change kept it; 0.3 s after,
  it lost it, inside the two-second save debounce. Gold, loot and trades are
  server routes and are never in that window.
- **Log out and back in** kept the bag, the gear, the level, the purse and the
  pools. It starts in town, not where you left (noted at the login sweep).
- **Browser:** a bag change with the tab closed 0.2 s later reached the server;
  the API down and back mid-game showed the countdown and cleared it.

Fixed: the two browser findings in "The browser build" above.

### Speed on day 1

Measured in the sandbox (two slow cores, software GL), with the frame rate held
at 60 and the server put 50 ms away by a delaying proxy:

- The login box is up 0.85 s after launch; picking a character to standing in
  town is 0.1 s; every other area is loaded within 0.1 s of arriving.
- Panels open in under 30 ms the first time and under 7 ms after; game scripts
  cost about 0.4 ms a frame; the server answers a request in about 2 ms.
- The field's physics is 3.6 ms a tick at 80 ticks a second. Fine on a desktop;
  60 ticks would save a quarter of it, and is a feel decision, so it is left.
  Since day 2 enemies out of sight sleep (see "The Big Field"), which takes
  most of that away wherever the player stands.

Four things changed:

- **The desktop game keeps its connections to the server open**
  (`src/systems/connectionpool.gd`, owned by `Api` as `_pool`). HTTPRequest
  opened a new connection for every request: on the real site a TCP and a TLS
  handshake before the request. Measured: 133 ms a request before, 67 ms after;
  the login's four requests 0.70 s before, 0.40 s after. Against Flask's own
  server at home, 83 ms became 17 ms. The rules, each held by
  `_test_connections_are_kept_open` against a small HTTP server inside the
  suite (`FakeHttpServer`) and each watched failing when broken:
  - up to six connections, one request at a time each, a queue past that;
  - a connection unused for 20 s is closed by the game, before nginx (75 s),
    waitress (120 s) or Caddy (5 min) would close it, and every connection is
    checked just before use, so a request almost never goes out on a dead one;
  - **a GET lost on a reused connection is asked again once; nothing else ever
    is.** A purchase, a loot take or a kill report sent twice is the expensive
    mistake; one that fails says "no answer", as it always could;
  - "Connection: close" is obeyed (Flask's own server says it to everything,
    and HTTPClient still reads CONNECTED for a moment after the last byte);
  - an answer is complete when all its bytes are in, whatever the connection's
    state says: HTTPClient reports a connection error the moment a server that
    closes after answering has been read to the end;
  - gzip is unpacked, as HTTPRequest did.
  Pictures (`post_bytes`, `get_bytes`) and the whole browser build still use
  HTTPRequest: a browser keeps its own connections open. The site's proxy keeps
  connections to players open by default (Caddy and nginx both do); nothing in
  DEPLOY.md needs to change for it.
- **Doors fade 0.15 s each way** (`SceneTransition.fade_duration`, was 0.3).
  The fade was 0.6 s of every 0.65 s trip. The area is built while the screen
  is black either way. `_test_a_door_is_quick`.
- **The emoji font ships at chat size.** Google's Noto Color Emoji is 10.8 MB
  of 136x128 pictures, three quarters of the browser's game file, for emoji
  drawn at 10-16 px. `tools/shrink_emoji_font.py` scales the pictures to 32 ppem
  (every emoji kept, 4.6 MB); the browser download went from 21.4 MB to 15.7 MB
  compressed, and the game file from 14.2 MB to 8.2 MB, which is the part every
  player downloads again after every update. Checked side by side at 11, 16,
  24 and 32 px, and in the browser's chat. **Rebuild it from Google's release,
  never from this copy** (the script refuses a strike already that small). The
  licence notes are in assetlicense.md. `_test_the_emoji_font_is_chat_sized`
  fails if Google's full file is dropped back in.
- **Enemies keep their place on the ring.** Found while timing the field: each
  0.4 s review that found no better slot forgot the slot it held without
  releasing it, so within a second 37 of the 40 slots were owned by enemies not
  standing on them and none of 12 chasers held one. Every enemy ran at the
  player's own position and rescanned all forty slots every physics tick. Now
  9 to 12 of 12 hold a slot, and the lookup is 7 us instead of 24. **This
  changes how a fight looks**: enemies spread round the player as the formation
  was built to, instead of piling onto one spot.
  `_test_enemies_keep_their_place_in_the_ring`.

And one regression, found while testing the connections: **a bag changed while
the server was down was lost when it came back.** `bag_sent()` makes the bag on
its way the base for the next save (see "A bag save names the bag it was built
on"); when that save never landed, the retry claimed a base the server never
had, was refused as stale, and the server's older bag was adopted over the
change. `CharacterData.bag_unsent()` puts the old base back when a bag save
fails, unless a newer server bag has been noted since. Measured after: two cells
swapped during a 15 s outage reached the server, through Flask's own server and
through a kept-open one. `_test_a_bag_changed_offline_still_lands`.

Noted, not changed: during a fight the server logs "unexplained heal" for mana
(+13 against 9 of regeneration over two seconds) and clamps it, on the old
request code and the new alike. The game regenerates mana a little faster than
the server's model of it; worth a look on its own.

### The first five minutes, played as a new player

A fresh account, a new warrior, the town and the Field, the way a tester from
outside would meet them. What was rough, and what changed:

- **The bar was fourteen small buttons.** It is eight now: Inventory, Gear,
  Stats, Shop, Map, Chat, **Social** (Friends, Players, Guild, Trade, Kingdom)
  and **Menu** (Controls, Options, Switch character, Log out). The dropdowns are
  `%socialmenu` and `%systemmenu` in characterhud.tscn; they open above their
  button with the right edges lined up (`nav_menu_position()`, so Menu's stays
  off the health bars), and shut on a choice, on any bar button, on Escape
  (before any window) and on a click anywhere else. **Every bar button is found
  by its unique name** (`_nav_button("tradebutton")`), never through
  `%navbuttons`: nine of them are not on that row any more. The dots still
  light the button inside a dropdown, and `_paint_group_dots()` puts the same
  dot on Social, with "Waiting for you: Trade" as its hint. Each window's key is
  added to its button's hint from the input map.
- **Nothing said what any key did.** H, or Menu > Controls, opens the Controls
  card (`src/ui/controls/controlspanel.gd`), and **every key on it is read from
  the input map**: `help_toggle` is a new action for H. The suite fails if a key
  the game binds has no line on the card, or a line names an action that does
  not exist.
- **Nothing said where to go.** The first time a character stands in town on a
  computer, the card opens as a welcome: the way out of town (south to the
  portal into the square, then north up the road to the Field's portal, walked
  and checked), the keys, and "Got it". It is marked seen in `user://seen.cfg`
  the moment it shows, never in options.cfg (every key in Settings' DEFAULTS
  must have a control). `offer_welcome()` shows it in town only, which also
  keeps a suite run from marking it seen.
- **The login button said "Enter Elysium".** It says Enter Elusion.
- **Two windows were out of line.** The Gear window's title is EQUIPMENT,
  centred, at INVENTORY's size; Character Stats spreads its left column from
  top to bottom (three expanding gaps) instead of floating it in the middle.
- The login screen's server address is shown in debug builds only already
  (`Api.describe_online()`); a player's build says "Connected to the Elusion
  server."

`_test_the_first_five_minutes` holds all of it (35 checks). Sixteen deliberate
breaks, each caught. Left for the owner: the Field puts its strongest enemies
(the dark element, 1,155 to 2,800 health) within 250 px of the entrance and its
weakest farthest away, so a new level 1 character dies in about two seconds.

### Mythic weapons: a weapon that brings its own attack

Day 2. Ahvassa drew a meteor, a double axe and a lit stick of dynamite, and the
owner made them weapons - "an upgraded version of weapons because they have
their own attack animation". Tier 6 (Mythic), one per class, worn from level
1 since 0.69.0 (it was 22), when the general store started giving them away
("The mythic weapons are free", in the shop section); the healer's (a heal)
is a later commission.

| Item | Class | Attack while worn |
|---|---|---|
| Meteorite (`meteorite`) | mage | a meteor where you aim, in place of the stalagmite |
| Double Axe (`doubleaxe`) | warrior | thrown to a spot, spins there; attack again calls it back |
| Dynamite (`dynamite`) | tank | a lit stick where you aim, in place of the aura |

- **`ItemData.weapon_attack`** (`WeaponAttack`: NONE, METEOR, SPINNING_AXE,
  DYNAMITE - append only, the .tres files store the integer).
  `Player.equipped_weapon_attack()` answers it, and each class's attack branches
  on it: `mage._cast_stalagmite_drop()`, `warrior.attack_action()`,
  `tank.attack_action()`. Every weapon below mythic is NONE.
- **Double cast.** One meteor cast or dynamite throw in ten comes twice
  (`Player.rolls_double()`, `double_cast_chance`, 0.10), for one price, spread
  apart as the owner asked: the second meteor 30-40 px away in a random
  direction and 0.18 s later; the two sticks 20 px either side of the aim,
  across the line of the throw.
- **The axe** (`spinningaxe.gd`) cuts what it passes going out and coming back,
  once each, for a sword swing; spinning, it cuts everything within 20 px every
  0.25 s for a quarter of a swing, so it deals a swinging warrior's damage per
  second to everything near it. It comes home on its own past a 260 px leash or
  when the warrior is away (`is_afk()`, the three minutes that stop skill XP),
  and is gone if the warrior dies, leaves or takes it off (`_on_gear_changed()`,
  called from `refresh_gear_stats()`). Max throw 170 px.
- **Dynamite** (`dynamite.gd`) is priced against the aura it replaces: a throw a
  second for 4 mana, worth four aura ticks at once. Max throw 150 px, 0.9 s fuse
  with a ring that brightens. Putting it on puts the aura out.
- **The look** is built in code around Ahvassa's frames: the meteor comes in
  from up and to the left, speeding up, with a fire and smoke trail and a shadow
  that grows a pixel at a time; `blast.gd` is the impact for both (flash, ring of
  air, fireball and smoke puffs, thrown stones or sparks, a short camera shake,
  and a crater or scorch that fades). Particles are untextured squares or an
  8-px round puff, the textures small images drawn pixel by pixel, so it is the
  same size of dot as the art.
- **Balance.** Damage follows the ladder: the Double Axe is the tier's sword,
  and the Meteorite and Dynamite add the same share of their class's dps as it
  does - `test_equipment.py` holds it. Since 0.11.9 that sword is 140 (it was
  110, against ember's 100) and each adds 15% (was 9%): see "Mythic weapons
  worth the wait" below. Since 0.71.0 the Meteorite is 175, with every staff
  (25 / 40 / 60 / 88 / 125), for the mage's heavy spike (below). A meteor's hit is 22 px
  across (the stalagmite's is 18); a stick's is 28.
- **They drop from anything, on a roll of their own.** No `tier_odds` reaches
  tier 6. See "Mythic drops" below.
- **Sounds**: `meteor_impact`, `axe_throw`, `axe_catch`, `dynamite_throw`,
  `explosion` - registered, empty, live the moment a file is assigned.

Three traps, all found on the way:

- **A blast's ground mark landed at the world's origin.** `_ready()` runs inside
  `add_child()`, before the spawner moves the node, and the mark is placed by
  global position. Blast builds itself in `spawn()`, after the move.
- **An Area2D moved by hand never reported a wall.** The axe flew through a
  StaticBody2D in the suite. Walls are found with a ray along each frame's step
  (layers 1 and 2 - the field keeps its walls on 1), and the area only looks
  for enemies.
- **A fresh Area2D sees nothing for its first physics steps.** The first area in
  a new arena reported no bodies after two frames. Harmless in play (a meteor
  falls for 44 frames first), but the suite waits four.

`_test_the_mythic_weapons` holds it (71 checks), on stand-in enemies in an
arena; the three scenes join PLAYER_PROJECTILE_SCENES. Twenty deliberate
breaks, each caught. Played in the field with all three equipped through
`/api/character/equip`: the server paid the kills.

### Mythic drops: anything can drop one, the tougher the better

Day 2, the owner: regular mobs and bosses both drop the mythic weapons, "mixed
rarity but it should be super rewarding getting 1".

- **A roll of its own, on the server.** Every enemy that pays rewards carries
  "one in N" odds, `EnemyData.mythic_odds()`. That reads
  `GameConstants.MYTHIC_ODDS_BY_TIER` by `max_loot_tier`, or
  `MYTHIC_ODDS_BOSS_BY_TIER` for a boss (`slots_are_gear`), unless
  `mythic_odds_override` is set. The exporter writes it into gamedata.json as
  `mythic_odds`. `gamedata.roll_mythic()` rolls it at every kill, beside the
  bag.
- **What a win gives.** The killer's own class's piece. A healer, with none of
  their own yet, gets any of the three. A win makes a bag even when the bag
  roll said no, and comes first in it, after a pet.

| Who | One in | About |
|---|---|---|
| The Crowned (override) | 150 | 8 hours farming it, a kill every three minutes |
| Fire and Earth Crowned | 300 | |
| Ice, Water, Wind and Light Crowned | 600 | |
| Dark band | 20,000 | 65 hours at five kills a minute |
| Fire band | 50,000 | |
| Earth band | 100,000 | |
| Water and Ice band | 250,000 | |
| Light and Wind band | 500,000 | a lottery ticket |
| A small slime (override) | four times its band | one large releases eight |

- **The finder's moment.** The kill answer names the piece (`mythic`).
  `Combat.celebrate_mythic()` plays `mythic_drop`, shakes the camera harder
  than any weapon does, and the HUD's `show_mythic_banner()` says MYTHIC DROP!
  and the piece's name over a red flash. The bag (`lootbag.set_mythic()`)
  raises its pillar 2.4 times as high and brighter, throws a burst of sparks,
  and stays on the ground `MYTHIC_BAG_DESPAWN_SECONDS` (300) instead of 45. A
  boss fight can outlast 45 seconds, and the rarest drop in the game should
  not be lost to a timer. The show ends when the piece is taken out.
- **Everyone else online.** The server posts a broadcast of kind `mythic`,
  "Tunacan found the Meteorite on The Crowned!". The broadcast poll draws it
  as the same banner, without the flash, and writes it into chat in the mythic
  red. The finder's own game skips the banner, since it already celebrated, by
  matching `by` to `Api.username`. A first poll's backlog writes old finds into
  chat without a banner. The owner's announcement route takes only `system`
  and `shout`, so nobody can type a fake one.

`_test_mythic_drops` holds the game half (33 checks), and the API's
`test_loot.py` and `test_equipment.py` hold the roll, the rates, the kill and
the notice. Played end to end against a server with every rate at one in one:
a Light Slime killed in the field gave a mage the Meteorite. The bag, the
banner and the chat line all appeared, and the same broadcast, read as another
player, put up the red banner.

### The first sound: the teleport, and a tone nobody can hear

Day 2: the owner recorded the teleport himself, his Stylophone through the CPM
DS-2's AUX IN, and `teleport` is the first id in `Audio.SOUNDS` with a file
behind it (`audio/sfx/teleport.ogg`, 1.5 s, rising an octave). It plays at
both town portals (`teleporter.gd`, and `leavetown.gd` on the way to the
field), when the field's arrival portal closes behind you (`leavetown.gd`'s
`_vanish()`), and at both moments of the victory door. It carries across the
scene change because `Audio` is an autoload. docs/audio.md has how it was made.

- **His recordings carry a tone at about 21.6 kHz**, too high to hear and
  60% of the energy. Normalising to the peak normalises to that tone, so
  low-pass the next recording at 15 kHz before anything else.
- **`audio/sfx` is classified** in `LICENSED_ART_FOLDERS` as the owner's own,
  like `audio/ambience`. A new folder under `audio/` fails the suite until it
  is named there.
- **The registry check no longer fails a half-filled table.** It skips, counts,
  and prints every id still empty, because sounds now arrive one at a time and
  a suite red for weeks gets ignored. All filled is still a pass.
- **No sound effect may be imported looping** (`_test_audio_paths`). A one-shot
  with Loop ticked never stops; music is exempt.
- **Every portal makes a sound** (`_test_every_portal_makes_a_sound`). The
  owner found the town's way out and the field's arrival portal silent by
  walking through them. Every function under `src/world` that calls
  `SceneTransition.change_scene()` must call `Audio.play` first, and the
  arrival portal is driven for real: quiet when you land, one teleport sound
  when it closes. The sound goes after `leavetown.gd`'s arrival-only return,
  or every arrival in the field would play it a second time.
- **But not on top of the trip's own sound** (5 Oct, the owner: "a double
  sound going through second teleport"). The teleport sound is 1.5 s and the
  fade between areas about 0.3, so a player still holding the key stepped off
  the arrival portal while the departure sound rang, and the closing sound
  landed on it. `_vanish()` plays only when `Audio.is_playing("teleport")` is
  false: walk straight through and you hear one sound; stand on the portal
  first and you hear it close.
- **A closing portal fades its own picture, not what is parented to it.**
  `_vanish()` tweens the `visual` target's `self_modulate`, because `modulate`
  is inherited and field.tscn's portal sprite has 39 props under it (the
  ribcage, rubble, crates, pillars, lanterns, cages and the skeleton). They
  all faded away with the portal. With no `visual` set the trigger fades its
  own `modulate`, because there the art is its child.

### The owner's item catalogue, and the owner's level

Day 2: "i need these items as hot keys so i can test - can you create a menu in
hud that allows me to select and spawn items registered in the game that only
owner can use". It was an **Items** button on the HUD's staff row until 5 Oct,
when the owner asked for the testing tools in one place ("set level should be
in gm panel under testing", "the whole items tab should be in gm panel maybe").
The GM panel's **Testing** tab has an **Item catalogue...** button now, and the
catalogue stays a window of its own (`src/ui/owner/itemspawner.gd`), because a
grid of pictures needs more room than the panel has. The button calls the
HUD's `toggle_item_spawner()` through the `hud` group, so the HUD still owns
the window: it is in the HUD's `_escape_windows()` list, so Escape closes
it, and it is the nineteenth window. Since 0.7.5 it also gives to a player
(Give to; see "Give item and Save history").

- **Every item `ItemRegistry` loaded**, so a new .tres is in the menu at the
  next launch. Kinds come from `ItemSpawner.category_of()` - type and equip
  slot, never a list of ids - then tier, then name. The search reads the name
  and the id, any case, every word. Frames are the rarity colour.
- **A click is `/api/staff/grant`**, the same route as the GM panel's Give item,
  with the quantity clamped to the item's stack. How many is read
  through `typed_quantity()` (see the SpinBox trap below). The bag that comes
  back goes through `CharacterData.adopt_granted_bag()`: the same adoption as a
  trade's, without `carry_adopted`, which would announce "Your backpack was
  updated by the server" to the person who pressed the button.
- **"Put gear on"** equips a weapon or armour piece from the cell the grant
  wrote (`carry_positions`), through the ordinary `/api/character/equip`, so
  the class and level gates still refuse and say why.
- **Set level** is in the Testing tab, a `LineEdit` beside the gold and item
  rows: `POST /api/staff/level`, owner only, the caller's own character, XP
  from zero, the maxima the curve gives, full pools recorded as a level-up
  grant, and a `level` line in the staff log. The box takes two digits and the
  panel refuses anything but a whole number 1-99 before asking. The player
  copies the answer with `apply_server_level()` - the server's pools, not a
  refill, so `_fill_all_resources()` keeps its one caller.
- **Set skill** is the row under it (6 Oct, the owner: "full control of my
  stats"): a picker with All skills and the six skills, a two-digit box and the
  button. `POST /api/staff/skill`, owner only, the caller's own character, the
  level with no XP into it, a `skill` line in the staff log. The player copies
  the answer with `apply_server_skills()`, which sets only the six names in
  `GameConstants.SKILL_XP_GROWTH` and pops nothing - a set is not a level-up.
  Damage, the defense tier and attack speed read the skill vars live, so they
  change at once.

`_test_the_item_menu` holds the catalogue, `_test_the_gm_panel_sets_a_level`
the level and the button, and `_test_the_gm_panel_sets_skills` the skill row,
through the panels' own doors - `post_request`, `adopt_bag`, `equip_request`,
`apply_level` and `apply_skills` are Callables the suite swaps for stubs. The
API's `test_ownership.py` O-7 and O-8 hold the two routes. Played as
the owner: level 1 to 22, then a Double Axe spawned and worn in two clicks.

### A SpinBox's typed number is not its value until Enter

5 Oct, on play.elusionrpg.com: the owner typed 99 into the Items window's level
box, pressed Set level, and was told "Level 29, from 29". A `SpinBox` keeps
what is typed in its `LineEdit` and parses it into `value` only on Enter or
when the box loses focus, and the button had `focus_mode = 0` so a click would
not take focus from the game. Focus never moved, and `value` was still the 29
the box had been filled with. How many, beside it, had the same bug: type 7,
click a potion, get the 5 the box held before.

- **The level is a `LineEdit` now**, read as text when the button is pressed.
- **How many stays a SpinBox and is read through `typed_quantity()`**, which
  calls `SpinBox.apply()` first - the Enter the player did not press.
- **`apply()` reads the text, and the text catches up with a `value` set from
  code one frame late.** Set `value` and read in the same frame, and `apply()`
  puts the old number back. The suite awaits a frame after setting one; a
  player cannot click that fast.
- **A button that takes no focus and reads a SpinBox must apply it first.** The
  trade panel's SpinBoxes are fine: they are read through `value_changed` and
  its buttons take focus, so the click itself ends the typing.

### The Big Field, and enemies that sleep when nobody is near

Day 2, the owner: the Field is too small, "needs to be 2x the size more
corridors", with enemies in fields of one element "because if you group up
enemies they are easier to kill in groups". `scene/bigfield.tscn` is the
blueprint he approved, built beside the Field. **The Field itself is
untouched**, and its layout stays his to adjust.

- **One road from the arrival to the ladder**, ten fields off it, five each
  side, in band order: Light/Wind, Water/Ice, Earth and the oddities
  (electric, poison, the plain bush mage and sniper), Fire twice, Dark twice.
  12 to 14 enemies a field, 128 in all, with nothing within 400 px of where
  players land - doubled to 256 in 0.63.0, each monster given a twin of its
  own kind in its own field. The five alcoves that held a skeleton each in
  0.60.0 are gone: the crypt over the top fields took their place (0.63.0,
  below).
- **Painted in the Field's own crypt tiles**: the same `underground.png`
  atlas block, walls with the same collision, 196 x 128 cells, and a
  navigation polygon cut from the floor. Generated by a script from the
  blueprint; its walls and props came in 0.61.0 and 0.62.0 (below).
- **The first stop out of town since 0.15.0.** The owner: "keep both big
  field -> small field -> gauntlet -> main boss -> teleport back to town".
  The town's portal (`elusion.tscn` leavetown) lands players at the Big
  Field's `field_entrance`; the Big Field's ladder at the far end goes down to
  the Field's `field_entrance` (it went to the boss arena); the Field's
  ladder goes to the arena as before, the arena's victory door to the
  Crowned, and the Crowned's to town. The boss room's ladder up still leads to
  the Field, for leaving without the win. `_test_the_road_through_the_game`
  reads every door and looks for its landing spot in the scene it leads to.
- **Its doors were never connected.** bigfield.tscn was generated without the
  `[connection]` lines that hand an Area2D's `body_entered` / `body_exited`
  to the door's script, so its ladder did nothing and its arrival portal
  never faded - unnoticed while only `/goto` went there, found walking a
  character onto the ladder. The four lines are in, and the road test checks
  every door in every area is wired both ways.
- **The arrival portal closes by your steps (0.15.1).** The owner: "portal
  took way to long to vanish in big field". It waited for `body_exited`, but
  the player lands clear of its trigger (the marker is 12 px below the
  portal's middle, the feet circle 13 px below that, the trigger 25 px
  across), so it never saw them arrive and closed only when walked over -
  in both fields. `leavetown.gd` now has an arrival portal watch the player:
  first seen within `LANDED_WITHIN` (48) it landed there, and `LEAVE_DISTANCE`
  (20) from that spot it closes, fading in `FADE_SECONDS` (0.6, was 1.0).
  Measured: closed 0.13 s into the walk, gone at 0.73 s.
  `_test_the_arrival_portal_closes_behind_you`.

### The new-content performance sweep (0.15.1)

The owner: "we need to speed up the game again ... have not done in new
content sweep". Measured with the container driver (`_run.gd`, `newperf` and
`fieldprof`), headless for what the CPU spends and under xvfb for drawing.
The budget is the suite's: 30 fps, 33.3 ms a frame (`_test_frame_budget`).

- **What the CPU spends is small everywhere.** Process and physics a frame:
  town 0.5 + 0.2 ms; Field 0.4 + 1.6; Big Field standing 0.5 + 0.7 and its
  road end to end 0.6 + 0.9 (128 enemies, the sleeper on); a Meteorite
  barrage into a pack 0.9 + 1.4; Dynamite throwing 0.9 + 2.0; the Double Axe
  spinning 0.8 + 1.4. A browser runs the same work slower, still well inside
  33 ms.
- **Nothing leaks.** Eight seconds after each mythic stops, no meteor,
  crater, stick, blast, wound or axe is left, and the node count is back to
  where it was.
- **The heaviest thing on screen was the Field's `Black` layer**, and it is
  gone. 28,548 solid black tiles (`art/tiles/black tile.png`) in a
  rectangle under the whole Field at z -100, from before the screen past the
  map was made black (MapBackdrop): black drawn on black. The owner, shown
  it: "remove layer". The node, its TileSet and the texture's line in the
  scene went; the PNG stays, the town's ground uses it. In the container's
  renderer the Field's frame went from 74-76 ms to 37 (every frame over
  50 ms before, two in six seconds after), and field.tscn from 564 KB to
  107 KB, which is that much less to load. Screenshots before and after look
  the same at the arrival; anywhere a floor tile has see-through pixels now
  shows the grey mortar the town and the Big Field show.
  `_test_no_black_underlay` fails on any area with a layer of nothing but
  black tiles, and failed on the old Field.
  Before 0.15.0 no door led there and the owner used `/goto bigfield`
  (`chatpanel.gd`, owner only), which still works; `AreaRegistry.AREAS`
  holds it as `"bigfield"`, "Big Field".
- **Every enemy there chases from 250 px**, set on each instance, so a fight
  in one field does not pull the next (the default is 400, the fields sit 230
  to 300 px apart). Two things had to change for a per-placement leash to
  hold:
  - `enemyrespawner.gd` rebuilt an enemy from its scene file and lost
    anything set on the instance. `KEPT_PROPERTIES` names what a census keeps
    and a respawn puts back, before `add_child()`.
  - `bushmage.gd` set its 1,500 in `_ready()`, after the scene's values, so
    every mage ignored its placement. It is set in `_init()` now, the class's
    default, and `bushmage.tscn` stores no `leash_range` (a stored value would
    replace it). The Field's mages still chase from 1,500.

**Enemies far from the player sleep** (`src/world/enemysleeper.gd`). Every
enemy ran its whole brain every physics tick wherever the player was, and 128
of them would have cost more than the rest of the game together. Four times a
second, an enemy beyond `SLEEP_DISTANCE` (1,100 px) is set to
`PROCESS_MODE_DISABLED` and one inside `WAKE_DISTANCE` (900) is put back; the
gap stops an enemy at the edge flickering. `AreaRegistry` adds one to every
area as it opens, beside `MapBackdrop`.

- **The process mode, not `set_physics_process()`.** `field.gd` freezes
  enemies with that switch while the welcome story plays; sharing it would let
  the story's unfreeze wake the map and a wake undo the freeze.
- **A boss never sleeps** (`"unpushable"`): one frozen mid-pattern because
  the player stepped back is not worth finding out about later.
- Measured in the Big Field: 88 of 128 asleep where players arrive, and the
  physics time roughly halved with it on (0.5 ms a frame against 1.1). In the
  Field, 25 of 36 sleep at the arrival.

**The kill ceiling counts every scene.** The exporter's `placed_count` sums
the instances in every scene under `scene/`, so the Big Field raised most
ceilings: five light sprites where there was one. gamedata.json is re-exported
with it, and the API's copy must match or kills in the Big Field are refused
past the old ceiling. The API's `test_killwatch.py` read "15 kills breach a
ceiling of 11" and now works the burst out from gamedata.json.

`_test_the_big_field` holds the scene: the atlas, the arrival, the ladder,
366 enemies since 0.63.0 (the fields' 256, 80 Skeleton Soldiers, 30 Skeleton Elites), the safe landing, every enemy on open floor, the bands in
order, and the 250 both in the file and once each kind is in the world (the
check that found the mages). `_test_far_enemies_sleep` drives the sleeper and
a real respawn; the walk test walks the Big Field with every other area;
`_test_chat_safety_menu` holds `/goto`. Fifteen deliberate breaks, each
caught. Played as the owner through `/goto`: the sleeper attached, all 128
enemies chase from 250, and three light enemies killed paid through the
server.

### Monsters with no death of their own break into pixels (0.16.0)

Only the Crowned (and the element bosses, which are instances of
`bossenemy.tscn`) has `death*` frames, and only the small poison slime has
`smalldeath*`. Every sprite, bush mage and bush sniper - 28 of the 48 enemy
scenes - was simply freed on the frame it died. The owner wanted the
website's arena to show each creature's death, facing down, and a creature
with no death cannot be shown dying; so the game got one first, and the
website plays it, recorded from the game.

- **`DeathBurst` (`src/enemies/deathburst.gd`)** is a picture, not the
  monster. `BaseEnemy._die()` and `net_vanish()` spawn it in the `elif` after
  the death-animation branch, then `queue_free()` exactly as before - the kill
  report, the respawner's clock, a gauntlet wave and the slot release do not
  wait on it. It copies the frame the sprite was showing (texture, offset,
  flip, the sprite's own material so an element's recolour is kept, the
  enemy's `body_tint`) into the enemy's parent at the enemy's transform, so it
  y-sorts where the monster stood. No group, no collision. `net_remove()`
  (taken away, not killed) leaves none.
- **What it shows:** `FLASH_SECONDS` of the frame overexposed by
  `BaseEnemy.HIT_FLASH_COLOR` (the killing hit's flash, which the old instant
  free never let anyone see), `WHITE_SECONDS` of a pure white shape, then
  `CRUMBLE_SECONDS` of that shape breaking into 2x2 squares of its own pixels,
  top first, lifting `LIFT` px, while single pixels are thrown up out of the
  hurtbox, white cooling to `Element.colour_for()` the monster's element. It
  frees itself when the last pixel lands: `DeathBurst.seconds()`, about
  0.95 s.
- **The white shape is a shader (`src/shared/death_crumble.gdshader`) on the
  copy, never on a monster's sprite.** baseenemy.gd's hit-flash note is why: a
  shader left on an enemy, with a state that can stick, was a mistake once.
  The copy is gone in a second.
- **`_bursts_on_death()`** says whether a monster bursts; `poisonslime.gd`
  says no for both forms (the small shows `smalldeath*` before handing to
  `BaseEnemy._die()`, the large splits).
- **Cost:** forty made at once 1.5-2.5 ms of CPU, a frame of forty running
  about 0.2 ms (measured with the container driver's `burstcost`;
  `_test_monsters_go_out_in_a_burst` holds them to a quarter and a tenth of
  the 33.3 ms frame). The test also kills a fire sprite and walks the
  burst through its timeline, checks the slime and the Crowned keep their own
  deaths, a mirror bursts on `net_vanish()` and not on `net_remove()`, and
  every bursting scene has a sprite and a hurtbox.

### The Meteorite pulls monsters in before it lands (0.17.0; one in a hundred since 0.17.2)

The owner: "on the spin up of meteor can we pull enemies closer to the
center?", then "like before the meteor falls". Then, at 0.17.1: "meteor has
10% chance to pull enemies i think sounds better", and at 0.17.2: "1% chance
instead of 10".

- **One meteor in a hundred pulls** (`Meteor.PULL_CHANCE`, 0.01; 0.10 at
  0.17.1). `mage.gd`'s
  `_drop_meteor()` rolls it for each meteor (`Meteor.rolls_pull(randf())`), so
  a double cast's two roll apart, and sets `pulls` BEFORE `add_child()`: the
  meteor builds its ring of fire at a size that says which kind it is. A
  meteor made anywhere else (a test, a tool) does not pull unless told to.

- **While the stone falls (`Meteor.FALL_SECONDS`, 0.55 s)** every monster
  within `PULL_RADIUS` (88, twice the hit) of the landing spot is drawn toward
  it at `PULL_SPEED` (150 px/s at the landing, `PULL_START` 0.4 of that at the
  top), and stops `PULL_STOP` (14) from the middle. A monster standing still
  moves about 60 px: one at the edge of the pull ends up inside the hit. Its
  own walking is not cancelled, only added to, so one running away can still
  get out. Nothing before the fall starts (a double cast's second meteor
  waits), nothing after the impact.
- **The ring of fire is the pull.** A pulling meteor's ring starts at
  `PULL_SWIRL_FROM` (2.0, so at `PULL_RADIUS`) and swirls in with the monsters,
  with 64 flames for the wider ring; an ordinary meteor's starts at
  `SWIRL_FROM` (1.25) with 48, as in 0.14.0. A player sees the wide ring and
  knows this one will gather the pack.
- **Through the physics engine.** `BaseEnemy.pull_toward()` moves with
  `move_and_collide()` and slides along what it meets: walls stop it the way
  they stop a monster walking, and a pack bunches rather than stacks. Found by
  a shape query on the hit's own mask, bodies only (a bush mage's attack boxes
  are areas on the enemies layer).
- **Who is not pulled** (`can_be_pulled()`): a boss (`BossEnemy` overrides it,
  so its rings and spikes stay placed from where it stands), a monster behind
  a boss gate, one already dying, and a mirror - a monster another game runs
  stands where that game says, so in a shared area only the leader's meteors
  pull, and the leader's world carries the result to everyone. Making a
  follower's meteor pull would need a new message through the presence server.
- **Sixty times a second, not every physics tick** (`PULL_EVERY`). Moving a
  packed crowd through the physics engine is about 25 us a monster; forty
  monsters in the pull cost about 1 ms a frame for the 0.55 s of the fall
  (container driver, `pullcost`). The impact itself, forty hit at once, is
  5-7 ms in that frame, as it was before the pull.
- **The server's books do not change**: the meteor hits each monster for what
  it always did, it just reaches more of them.
- `_test_the_meteor_pulls`.

### The mythics' rolls: one in ten, one in a hundred (0.18.0)

The owner set one rule for the three mythic weapons - a common roll and a rare
one - and named them:

| Weapon | 1 in 10 | 1 in 100 |
|---|---|---|
| Meteorite (mage) | a second meteor beside the first (`Player.WEAPON_DOUBLE_CHANCE`, since 0.11) | the pull (`Meteor.PULL_CHANCE`, 0.17.2) |
| Double Axe (warrior) | WIDE: reaches `WIDE_REACH` (1.5) times as far, flying, spinning and home | BLOODY: flings blood as it spins and spatters the ground; picture only |
| Dynamite (tank) | a bundle of `DYNAMITE_BUNDLE_STICKS` (3) in a triangle | a barrage of `DYNAMITE_BARRAGE_STICKS` (5) in a wider ring (`DYNAMITE_BARRAGE_SPREAD` 24) |

- **Each roll is made by the character as the attack is made**, and set on
  the projectile before `add_child()` so it builds itself to match: `mage.gd`
  `_drop_meteor()` (`Meteor.rolls_pull()`), `warrior.gd` `throw_axe()`
  (`SpinningAxe.rolls()`, the two apart, so a throw can be both), `tank.gd`
  `throw_dynamite()` (`sticks_for()`: one roll, the lowest
  `DYNAMITE_BARRAGE_CHANCE` five, the next `DYNAMITE_BUNDLE_CHANCE` three).
  The chances are vars on the characters (`axe_wide_chance`,
  `axe_blood_chance`, `dynamite_bundle_chance`, `dynamite_barrage_chance`) so
  the suite can make a roll certain, as `double_cast_chance` always was.
- **Dynamite lost the every-fifth-throw bundle and the one-in-ten double.**
  The owner: "dynamite is already getting a bonus from aoe of ring hmm". A
  throw is 1.24 sticks on average where it was 1.48: by the Boss Sim's model
  (level 22, Ember, skills 30) about 523 a second to about 486, 7%.
  `_dynamite_throws` and `is_bundle_next()` are gone with the count.
- **The books.** The exporter writes the tank's `dynamite_bundle_chance` /
  `_sticks` and `dynamite_barrage_chance` / `_sticks` (`dynamite_bundle_every`
  is gone), and the API's `combat_bounds()` allows a throw the most of them,
  five; a catalogue without the barrage keeps three. The axe's wide throw cuts
  more monsters, none harder, and the bloody one is a picture, so the
  warrior's bound is unchanged. **The API's gamedata.json goes out first.**
  The Boss Sim models the dynamite's average throw; neither axe roll moves
  one boss's numbers.
- **What a player sees.** A wide axe's dust and streaks ride its wider rim; a
  bloody axe's wind runs red and its blood stays where it fell, the spatter on
  the floor (z -1) for a couple of seconds. A barrage is five sticks in the
  air. Each weapon's tooltip names its rolls.
- **Always roll the 1% (0.18.1).** A switch on the owner panel's Testing
  tab (`%rarebutton`) sets `GameState.force_rare_rolls`, and
  `Player.rare_forced()` - the flag AND `Api.GOD_MODE_MIN_ROLE`, read on every
  roll - makes every meteor pull, every axe throw bloody and every Dynamite
  throw the barrage. The owner, who had seen the pull but neither of the
  others: "yes that sounds amazing". Off after every restart (GameState), and
  nothing it does is outside the books: they already take every throw as five.
  **And the 10% (0.18.2)**, the owner: "do another switch for 10% casts" -
  `%commonbutton`, `GameState.force_common_rolls`, `Player.common_forced()`:
  every Meteorite cast is two (`rolls_double()` asks it), every axe throw wide,
  every Dynamite throw three sticks. Both on: two meteors that both pull, a
  wide bloody axe, and Dynamite's five (one throw is one count; the rare one
  wins, as the dice take it first). `_test_the_rare_roll_switch` covers both.
- Tests: `_test_the_axe_rolls` (the wide reach cutting past a plain one's and
  no harder, home still wide; the blood while spinning and not after, none on
  a plain axe, the red wind, the cuts never reading it; the dice; the
  warrior's roll before the build) and the mythic section's roll checks (the
  odds, the dice over 100,000 throws, no double, the bundle's triangle and its
  chain, the barrage's ring and its spacing), and the books' check on the
  exported fields.

### Walk and talk: Enter opens chat, and chat stays up while you walk (0.18.3)

The owner, after his first game with somebody else: "i cant see chat while i
walk stopping to chat is a hassle i was thinking enter would open chat and we
could keep it a transparent box on hudscreen", and, pointing at the HUD's
floating notice box, "maybe we could see chat here or something like this".

Two things made chat a place you stopped at. Opening it put the keyboard in
the box and nothing ever gave it back - a send called `entry.grab_focus()`
again - so `player.gd`'s `_typing_in_ui()` held the character still until the
box was clicked away from. And a solid window that size, over the world, is a
window you close.

- **Enter opens chat with the keyboard in the box** (`characterhud.gd`
  `_chat_key()`, `is_chat_key()`, `open_chat_to_type()`): shut, it opens
  (`open()` focuses the box); open, `ChatPanel.focus_entry()`. Read in the
  HUD's `_input`, first, before the GUI, so a button a click left holding the
  focus cannot take the press. A text box that has the keyboard keeps Enter -
  it is that box's (the chat box sends). `keybinds.gd` had reserved Enter and
  the keypad's Enter for chat all along, and nothing listened for them.
- **Enter sends and hands the keyboard back** (`hand_back_keyboard()`, in
  `_send()`'s success where the `grab_focus()` was). Enter on an empty box
  just hands it back - unless a picture is waiting, when the empty line is its
  caption and it sends. Walking and attacking work the moment the line is
  said; Enter again to say the next.
- **Up and not typing, the window is see-through** (`_refresh_look()`): the
  frame (`IDLE_FRAME_ALPHA`), the title bar, the tabs and the entry row
  (`IDLE_CHROME_ALPHA`) go, and the lines stay on the log's backing at
  `IDLE_LOG_ALPHA` - `self_modulate`, so the backing fades and the lines do
  not. Typing in either box (the message box or the whisper name box), or the
  mouse over the window, draws it whole again. The mouse is read from motion
  events in `_input` (`mouse_at()`), taken into the frame's own coordinates;
  nothing polls it, as the window rule in `_test_panels_are_windows`
  asks. Shut, the window forgets the mouse, so it never opens awake.
- **Nothing new is fetched.** It is the same window, polling every
  `POLL_SECONDS` while open as it always did; a player who never opens chat
  still never starts the timer. The floating notice box still stands down
  while chat is up.
- Tests: `_test_chat_walk_and_talk` (Enter and the keypad's from the game and
  from a clicked button, not from a text box, only the press; the HUD wiring;
  open to type, Enter on an empty box out, the see-through look and the whole
  one, the whisper box, the mouse over and off by real motion events, a window
  shut under the mouse; a send hands back).

### Seeing each other's attacks, one gate for everyone, and an even walk (0.19.0)

The owner, after his first game with somebody else (a student): "i could not
see their attacks but they could see mine the had to lower the gate to boss
even though i did some" and "as i was running past them i noticed some lag
wobble". Three gaps in the presence link, each found in the code before
anything was changed:

- **Their attacks were never sent.** A remote player was its body, its auras
  and its pet. A sword swing is the body's own animation, so his warrior's
  swings were seen; a meteor, a thrown axe, a stick of dynamite, a slash wave
  or a healer's orb is a thing in the world, and nothing carried those.
- **Levers were each game's own** ("Not shared, and said so", above).
- **The walk was chased, not played.** remoteplayer.gd eased toward the newest
  step - fast just after one arrived, slowing as it closed in - and steps come
  unevenly (the game's ten a second, the server's ten ticks and the network
  are three clocks). Measured between two games against the local server, on
  a steady walk of 120 a second, the old picture moved at anything from 4 to
  198 a second, surging and stalling from one frame to the next.

What changed:

- **Attack pictures.** The class scripts call `Presence.tell_attack(kind,
  from, to, delay, flags)` where they spawn an attack: warrior.gd `throw_axe()`
  ("axe", the rolls as flags) and `_spawn_slashwave()` ("slash"), mage.gd
  `_spawn_stalagmite()` ("stalag") and `_drop_meteor()` ("meteor", the pull as
  a flag, a double cast's second with its delay), tank.gd `_throw_stick()`
  ("dyn", one per stick), healer.gd `_spawn_projectile()` ("orb"), and
  spinningaxe.gd `recall()` ("recall", for a real axe called home for any
  reason). Presence sends them after the next state (`send_tick()`), each with
  the game's clock, at most `MAX_ATTACKS_PER_SEND`, and only to a server whose
  welcome says `"x"`. Another game hands them to that player's picture
  (`hear_attacks()`), which spawns each (`RemoteAttacks.fire()`,
  `src/characters/remoteattacks.gd`) when its playback reaches the moment it
  was made - so the meteor falls as their body finishes the cast.
- **A picture touches nothing.** It is the class's own scene with `cosmetic`
  set: spinningaxe, meteor, burningcrater, slashwave, dynamite,
  spelltargetcircle and turretprojectile each say under "A PICTURE OF SOMEBODY
  ELSE'S" what that leaves out - no hit, no XP, no wound, no pull, no camera
  shake (`Blast.spawn(..., shake)`), and a picture's stick sets off only other
  pictures. The monsters are the leader's and the attacker's real hits still go
  as hits; a picture that hit too would hit twice. `RemoteAttacks.go_quiet()`
  turns a picture's Area2D off; the slash wave keeps looking (walls stop it, a
  monster makes it swell) and is never seen. A thrown axe's picture flies home
  to the remote body (`axe`, `_on_axe_caught()`); spinningaxe.gd asks a caster
  `is_dying()` as a method when it has one, because `get("is_dying")` on a
  picture is a Callable and comparing that with true is a SCRIPT ERROR.
- **Levers.** A pull at the lever (`_process()`, not `throw()`, which a
  cutscene may call) goes out as `Presence.tell_lever()`, named by its path in
  the scene (`lever_name()`, which every game that loaded the scene has the
  same; the Field's are `ysortworld/interactables/levergatesout` and `...in`).
  Another game pulls its own (`follow_pull()`: the doors, the partner levers,
  the sound at the lever, told to nobody). The server remembers each area's
  pulls in order and tells a game that walks in (`levers`), and forgets them
  when the area empties, as a fresh scene has every lever as built.
- **Played back, not chased.** Every state carries the game's clock (`ts`,
  `clock_ms()`, kept out of the "did it change" comparison so standing still
  still sends nothing), and the send beat no longer drifts late
  (`_send_clock` keeps its remainder). remoteplayer.gd keeps every step with
  its time on their clock and draws the body `PLAYBACK_DELAY` (0.2 s) behind
  the newest, between the steps either side of that moment; the animation,
  aura and pet change when the playback reaches the step that says so. The
  link between their clock and ours is the quickest any reading took to
  arrive over `CLOCK_WINDOW`, followed at `CLOCK_SLEW` only when it moves by
  more than `CLOCK_DEADBAND` (following every few-millisecond wander made the
  walk surge by a tenth), and taken at once past `CLOCK_SNAP` (a join from
  somebody who stood still for a minute carries a clock a minute old). A
  pause longer than `PAUSE_SECONDS` was a stop: the walk starts a step before
  the next step, not across the pause. A clock going back a second is their
  game restarting. A game from before sends no clock and is played back by
  when its steps arrived. The same two games, the same walk: drawn at 118 to
  122 a second.
- **The server** (api `presence.py`, "ATTACKS AND LEVERS") checks every
  attack's shape and passes it to the rest of the area, never back; relays
  every step of a tick, not only the newest (`moves` entries carry `ts`); and
  allows 40 messages a second, burst 80, where it was 30 and 60 - a follower
  healer's ten orbs a second go out as ten more messages. **The API goes out
  first**: this game sends `x` and `l` only to a server that says it takes
  them, so a game ahead of its server plays exactly as 0.18.
- Not drawn yet: pets' shots (a remote pet follows its owner, as before).
  PvP is still "Decided, not built" below - the switch is real and nothing in
  the game can hurt another player.
- Tests: `_test_other_players_move_evenly` (uneven arrivals walked evenly, the
  delay, a stop, a start after a pause, a restart, a quicker road caught up
  without a skip, a wandering one ignored, a stale join, a game with no
  clock), `_test_other_players_attacks_are_pictures` (the class scenes, each
  kind against real monsters touching nothing, the axe home, when, routing),
  `_test_presence_sends_attacks` (only to a server that takes them, the shape,
  the cap, the beat and its clock, a new world, every class's call),
  `_test_levers_are_shared` (the name, telling, following, partners, the
  order, the wiring), and `_test_other_players_are_drawn` played back on a
  hand clock (`RemotePlayer.clock_override`).

### A held direction is let go when the keyboard goes elsewhere (0.19.1)

The owner, passing on what the first other player found: "you need to disable
the ability to shift rightclick to bring up the native context menu, it causes
the character to get locked in the direction of whatever movement state its in
at the time". He died like that, walking south.

- **Why.** Shift is sprint and right-click is attack, so a running attack is a
  Shift+right-click. Firefox opens its own right-click menu on one whatever
  the page says - the export's shell cancels the menu, which Chrome, Edge and
  Safari obey and Firefox, with Shift held, does not; no page can switch that
  off. The menu takes the keyboard, the key-up of the direction being held goes
  to the menu, and Godot's Input goes on holding that key: the character walks
  that way until it is pressed again. The same happens to any key held while
  the keyboard leaves - another window, a tab, a browser prompt.
- **What the game does: lets go.** `Keybinds.let_go()` sends the key-up of
  every key bound to `HELD_ACTIONS` (walking, sprint, attack) that is held, as
  if it had arrived, and releases the action at once; with `mouse_too`, the
  mouse buttons. The Settings autoload calls it (settings.gd, THE KEYBOARD
  GOES ELSEWHERE) when the app or the window loses focus, when an editable
  text box takes the keyboard (nobody walks while typing, and on a touch-screen
  browser the box is a page element of its own), and on a Shift+right-click in
  a browser that opens its own menu (`native_menu_on_shift_click`, from
  `Keybinds.opens_its_own_menu(navigator.userAgent)`: Firefox and its forks).
  There the keys go at once and the mouse button two physics frames later, so
  the click still attacks. In Chrome, Edge and Safari a sprinting attack lets
  go of nothing.
- What a player sees in Firefox: Shift+right-click still opens the browser's
  menu, and the character stops instead of walking off. The Windows build has
  no browser menu.
- Tests: `_test_held_keys_are_let_go` (the stuck key reproduced, letting go and
  of what, Firefox's menu and the click still attacking, a right-click without
  Shift, other browsers, the user agents, the window and the app losing focus,
  a text box and a button).

### Every gift the owner makes is counted, and what it came to (0.20.0)

The owner, 10 Oct, after giving the first other player 10,990 Piles of Gold
(274,750,000 gold) by accident, and keeping it: "do not roll back but make a
ledger for anthing i give to players so its accounted for if i ever ask how
much did i inflate my server".

- **The server keeps the ledger** (THE GIFTS LEDGER in the API's app.py,
  `owner_gifts`): every give to a player, every grant to yourself, every gold
  put in from the Testing tab, with what it was worth that day. The gifts
  from before were read back out of the staff log and the gold ledger the
  first time the server started with it, so the 274,750,000 is in it.
- **A gift says what it came to.** `/api/staff/grant` answers `worth`, and
  `ItemSpawner.money_text()` says the money in it: the catalogue's lines are
  "Gave 999 × Pile of Gold (24,975,000 gold) to allmind's tank." and "Added 3 ×
  Gold Coin to your bag (3,000 gold).", and the Testing tab's Give item the
  same. A sword is not money: its line is as it was, and its price is in the
  ledger. A server from before sends no `worth`, and the lines are as before.
- **"What I've given"**, in the GM panel's Testing tab under the item
  catalogue, asks `GET /api/staff/gifts` and prints it into the results box
  (`gift_report_lines()`, a static so the suite can read it): since when it
  counts, everything, to players and to yourself apart, the gold in purses and
  banks now and what share of it the gifts are, by player, and the newest ten
  by the item's name. Piles given and not used yet count as given and are in
  nobody's purse, so when the gifts are more than all the gold there is, it
  says that instead of a percentage in the thousands. A 404 is a server from
  before the ledger: update the API.
- **On the server, without the game:** `giftwatch.py` in the API folder prints
  the same, read only: `sudo -u elusion python3 giftwatch.py --db
  /var/lib/elusion/elusion.db` (add `--player <name>` for one account).
- Tests: `_test_gifts_are_counted` here (the lines with and without `worth`,
  the button, the report in words, more than all of it, nothing yet, an old
  server, anyone but the owner); `test_gifts.py` in the API.

### A co-owner, let in by the owner's switch, and a player's level (0.21.0)

The owner, 10 Oct: "i would promote allmind to owner but there can only be 1
however thats why i want to build another gate that allows him to enter", then
"maybe a switch in my gm panel that gives him access as long as i leave it on
... people want to try the new weapons and i dont mind for first time players
so i also need the ability to set a players level so they can try out the
game".

- **Two keys, both the owner's.** The server's `.env` names who may be a
  co-owner (`ELUSION_CO_OWNERS=AllMind`, beside `ELUSION_OWNER`; no request can
  write it), and the **Co-owners in** switch on the GM panel's Server tab says
  whether they are in now. Only THE owner moves it (`Api.is_the_owner()`); a
  co-owner sees it on, disabled. The line under it is one short sentence on
  purpose - an autowrapped label in a hidden tab measures as a column of single
  words and stretched the panel past the menu bar.
- **On, a co-owner has everything the owner has, except over the owner.** The
  server answers his login and heartbeat `role: "coowner"`, `is_owner: true`:
  `Api.is_owner` means "has the owner's powers" now, so every door on it - the
  Owner and Powers buttons, the GM panel, the catalogue - opens for him, and
  `Api.own_rank()` says which of the two he is. He wears **CO-OWNER** in the
  owner's gold (`Nametag.BADGES`); the crown is the owner's alone. God mode and
  the always-roll switches are his (`GOD_MODE_MIN_ROLE` is `"coowner"`). The
  rank lists - chat, the staff desk, the GM panel - read `Api.RANK_ORDER`, and
  the rank picker offers only `Api.GRANTABLE_RANKS`. The desk offers the owner
  a kick on him, not a demotion that would not move him.
- **The doors follow the switch while he plays.** The HUD listens to
  `Api.identity_changed`: switched on, the Owner and Powers buttons appear on
  his next heartbeat; off, they go, with the GM panel and the catalogue if open
  (`_on_rank_changed`). The server refused him the moment it moved.
- **Set level beside Give to**, in the item catalogue: a name, a level, Set
  level, then the weapon. `POST /api/staff/level {username, level}` sets the
  character they are playing, takes a snapshot first (Save history can put it
  back - "before a level change"), puts a line on their record, and signs their
  game out so it loads the level. Not on the GM panel's Account tab: one more
  row there pushed the panel past the menu bar. Your own level is still the
  Testing tab's.
- **The gifts ledger** button is "Gifts ledger" now (it was "What I've given"),
  because it is a co-owner's gifts too: with more than one giver it says who
  gave what, and "(by AllMind)" on each of the newest lines.
- Tests: `_test_coowners_and_their_levels` (the rank, the badge, the switch for
  the owner and for him, nobody named, an old server, the rank picker, the
  doors following the switch, Set level, the ledger by giver);
  `test_coowner.py` in the API.
- **0.21.1: the Credits byline is "a game by Robert and AllMind".** The owner,
  of AllMind: "he built my inventory and helped me with ui a bit" - there when
  the game began, and back as co-owner. The website's About page says the
  same (the team chapter and a credits card).

### A monster born since the leader's last tick is numbered by its first hit (0.21.2)

The server's books' first live week (8 to 11 Oct, 1,182 deaths): 1,141
AGREED, 41 SHORT - and every SHORT was a small slime, alive about half a
second, in the Field or the Big Field. No hit too big, too fast or too far for
anyone, so the bounds were right; the books were missing hits.

- **Why.** A monster gets its number (`net_id`) and its `_net_sync` from
  `_register_all()`, on the leader's tick, every `TICK_SECONDS` (0.1). A small
  slime out of a split, or a respawn, born into a fire ring, a burning crater
  or a smoulder field is hit inside that tenth of a second - and
  `take_damage()` only reported a hit through `_net_sync`, which was still
  null. The game took the health; the server never heard; the death read
  SHORT.
- **Now.** `take_damage()` asks the area's sync when the monster has none
  (`_unbound_sync()`: the sync whose parent holds this monster), and
  `own_hit()` numbers a monster it has not numbered yet on the spot
  (`_number()`, the body `_register_all()` uses), so its "spawn" and the hit go
  in the same world. Not a mirror, not dead, in the tree - the same rules as
  the tick.
- **The server's half** (API, combatbook.py `world()`): a hit on a monster the
  books do not know yet waits for that monster's spawn in the same message,
  and lands as it is read - before a "die" for it later on. Spawns are not
  simply read first: a split's "die" has to come before its smalls' "spawn",
  or the books do not owe them.
- **Deploy the API first.** A 0.21.2 game against an older server sends the
  hit ahead of the spawn and loses it, as before; nothing worse.
- Tests: `_test_shared_monsters_keep_the_books` ("a monster hit before the
  leader's tick reached it is numbered by the hit, and the hit is sent", its
  spawn in the same world, numbered once); the API's `test_combatbook.py`
  CB-14.

### The Field is the bullet-hell zone (0.22.0)

The owner, 11 Oct: the goal is "top down bullet hell hardcore survival", and
"set up field monsters to fire more projectiles small patterns and leave
large field as it is ... keeping rpg and bullet hell both well tuned" - the
existing Field, not a copy. Step 1 is the Bush Snipers.

- **The pieces.** `src/shared/bulletfield.gd` (BulletField): enemy bullets as
  packed arrays and ONE MultiMesh draw, no physics - an enemy bullet only has
  to hit this game's player. `src/world/bulletzone.gd` (BulletZone): one per
  area, the field plus the area's walls plus the player it hurts.
  `field.gd`'s `@export var bullet_zone` turns it on: true in field.tscn,
  false (absent) in bigfield.tscn, which shares the script.
- **A monster supports both with one branch.** `BulletZone.find(self)` is
  null everywhere but the Field, so the monster fires its ordinary projectile
  there. `BushSniper.fire_projectile()`: in the zone, `fire_volley()` - three
  orbs over 0.5 rad at 150 px/s, each 60% of the arrow (`FAN_SHARE`, the
  owner's "lower dps on projectiles") - and otherwise the arrow, untouched.
- **Shared as where and which way, never how hard.** The leader's sniper
  adds `{k: "b", id, x, y, a}` to its world (`MonsterSync.leader_bullets`);
  a follower's copy of that monster fires its own volley (`fire_volley`) with
  its own damage and element. Anything else in the message is ignored, like
  `safe_spike()`. The books (combatbook.py) read only spawn/die/gone, so the
  API needs nothing.
- **Unshaded, or invisible.** The Field sits under a CanvasModulate of
  (0.28, 0.3, 0.4). An orb drawn like everything else measured (71, 77, 102)
  at its white core; `render_mode unshaded` measured (255, 255, 255).
- **Not physics-interpolated (0.23.1).** The project interpolates physics,
  and on the desktop renderer an interpolated MultiMesh blends between
  buffers set on physics ticks; the orbs' buffer is set every frame from
  `_process`, which logged "MultiMesh interpolation is being triggered from
  outside physics process" in the editor. Off on the drawing node and on the
  MultiMesh (`RenderingServer.multimesh_set_physics_interpolated`). The
  browser build's renderer never showed it, nor did the suite.
- **And told where it is.** A MultiMeshInstance2D is culled by its mesh's
  box, which left alone sat around the world origin: the preview (an arena
  centred on 0) drew every orb and the real Field, 900 px from 0, drew none.
  `bounds` sets `custom_aabb`. Both of these only showed up by looking at a
  frame of the real Field - the suite passed either way until it checked.
- **The hitbox is the body**, `Targets.body_point()` with a 6 px radius (3
  until 0.25.3, when an orb could cross the middle of a sprite and miss),
  where every monster aims and what the walls stop - not the hurtbox, which
  the warrior carries 10 px higher. Damage goes through `take_damage()`, so
  armour, resistance, numbers and defense XP are what any hit gets.
- **Every orb that reaches you lands (0.25.3).** Until then, after one
  landed the rest passed through for `CHIP_MERCY` (0.2 s, then 0.1 s at
  0.23.1), and of several touching in one frame only the strongest landed.
  The owner, the third time: "i still want more projectiles to hit
  player". `CHIP_MERCY` is 0 and kept as the knob; above 0 it only passes
  through the frames after a hit. Each orb is its own `take_damage()`, so
  each is armoured, resisted and numbered. A dying player is not hit.
  Measured in the Field, a warrior among two snipers, a fire sprite, an
  electric sprite, a large slime and a mage for 25 s: standing still, 148
  hits became 294 (3,998 damage to 7,555); walking up and down, 43 became
  80.
- **Walls** are 8 px cells, solid where a point query on layer 1 finds a
  body (what the game's arrows stop on), built 12 rows a frame after loading
  (the whole Field is 200 x 164 cells, about 20 ms if done at once), and
  rescanned around a spike door when it rises or lowers.
- **The preview stays a preview.** `scene/prototype/bullethellpreview.tscn`
  (F6) uses the same BulletField and the pattern library in
  `src/prototype/bulletpattern.gd`; nothing in the game loads either.
- Tests: `_test_the_bullet_zone` (the Field is the zone and the Big Field is
  not, unshaded, the culling box, the element colour, flight, hits, mercy,
  catch-up along a curve, walls and a door, the sniper's fan in and out of
  a zone) and `_test_the_bullet_zone_is_shared` (the leader's "b", a
  follower's own damage, "r" and "v", nothing from an id it does not have).

**0.23.0: every monster in the Field fires its own shape.** The owner: "lets
do it", to the list of the other four.

| monster | in the Field | each orb |
|---|---|---|
| Bush Sniper | a fan of 3 | 60% of the arrow |
| Bush Mage | its vine as before, and a ring of 10 at 70 px/s with a GAP toward the player | 35% of the vine |
| Fire Sprite | a pincer: 4 orbs leave 0.45 and 0.9 rad wide and curve back to meet where the player stood | 50% of the fire orb |
| Electric Sprite | a chain: 5 down one line at 110 to 170 px/s, leaving together and stringing out | 50% of the electric orb |
| Poison Slime | small: a twin; large: a spray of 5 big orbs; and a ring of 12 as it splits | 60% / 45% / 35% |

- **One contract.** Every one has `fire_volley(zone, origin, aim, volley,
  reach)`, and `BulletZone` has the shapes (`fire_fan`, `fire_ring`,
  `fire_chain`, `fire_pincer`) and `base_damage()` / `share_of()`:
  `projectile_damage` when the .tres has one, else the shot scene's own
  `damage`, read once.
- **The wire grew two optional keys.** `"v"`, which volley (the slime's
  `"split"`; anything a monster does not have fires nothing), and `"r"`, how
  far (the pincer's meeting point, held on every screen to the sprite's own
  `PINCER_REACH_MIN..MAX`). Capped at `MAX_VOLLEY_NAME` / `MAX_VOLLEY_REACH`.
- **The pincer closes together.** The first version flew all four at one
  speed, and the wide ones, with the longer arcs, arrived later - a stream,
  not a pincer, and the test that waited for all four in one place never saw
  it. The widest flies at `PINCER_SPEED` and the others are slowed to take as
  long (`fire_pincer`'s docstring has the arc).
- **The split ring goes out before the large's death.** `_begin_split()`
  fires it ahead of `died.emit()`: the leader's "die" is what takes the large
  out of every follower's list, and a "b" behind it found no slime to fire.
- **The mage's ring has its gap toward you.** The vine already punishes
  standing where you are; the ring punishes the panicked sidestep.
- **Recorded in the real Field**, the player among the five dark monsters:
  about 190 orbs on screen at once, every element its own colour.
- Tests: `_test_the_field_volleys` (each monster's shape, count, share and
  element; the mage's vine still raised; the pincer leaving wide and all four
  meeting; the chain's speeds on one line; the slime's three; the leader's
  "r", and its "b:split" ahead of "die").

**0.24.0: the artist's shots fly again, and the orbs ride with them.** The
owner, watching the sprites and slimes fire only orbs: "for slime and sprites
i want the projectiles to be their art we are not taking away from my artists
art but adding to it". And of the sniper: "i want the orbs to spin in a circle
around the arrows", then, of the helix that came of it, "if only the arrow
hits its pointless howabout the vortex stays but it sprays bullet like a < if
the arrow fired left".

| monster | the artist's shot | and the orbs |
|---|---|---|
| Bush Sniper | its arrow, slowed to 160 px/s | a helix of 2 winding 12 px either side (35%), and a wake: a pair every 0.08 s flying back and out, a < behind an arrow going left (20%) |
| Fire Sprite | its fire orb, down the middle at reach / the pincer's time | the pincer, closing round it as it lands |
| Electric Sprite | its electric orb at 170 px/s | the chain behind it |
| Poison Slime | small: its arrow at 140; large: its acid ball at 90 (150 since 0.25.0) | between the twin; in the middle of the spray |

- **The shot hits for its full damage, as it always did;** the orbs are the
  shares above. The mage's vine and the slime's split were already the art.
- **Sent once.** The shot is part of the volley, so
  `spawn_projectile_node(shot, at, false)` does not also send it as a "p":
  each game's own `fire_volley` fires it, from the one "b".
- **The sway** (`BulletField.spawn_swaying`, `_sway_side` / `_sway_along`):
  a bullet drawn weaving about the point it is flying, a function of age so
  every screen agrees. Side alone is the helix; side and along equal would
  be an orbit. `position_of()` is where it is drawn and hits;
  `anchor_of()` the point it weaves about.
- **The wake** (`src/world/bulletwake.gd`) is a child of the arrow, so it
  sheds only while that arrow flies and stops where it stops - a wall, a
  body, its lifetime. Each game's own arrow sheds its own.
- Tests: the sniper's arrow, helix and wake and its plain arrow outside a
  zone; the leader's arrow not sent as a "p"; the follower's arrow and helix;
  each sprite's and slime's own shot with its volley.

**0.25.0: the large slime controls the floor.** The owner: "slimes are not
dangerous enough ideas?", and of the list, "2 and 3" - the mortar and the
settling acid. Every slime shot had been aimed where you were, so a sidestep
beat all of them.

| the large slime's | what it does | each orb |
|---|---|---|
| spray (turn 1) | its acid ball at 150 px/s, and 5 big orbs leaving at 150 that slow evenly to a stop where you stood (`SPRAY_REACH_MIN..MAX`) and lie there 3 s as mines | 45% |
| mortar (turn 2) | its acid ball LOBBED over everything onto your spot, marked on the floor as it flies; 1 s later: the full acid ball on the spot, a ring of 8 settling 40 px out, and the acid puddle | 100% on the spot, 35% the ring |

- **Settling** (`BulletField.spawn_settling`, `_brake`): a bullet slows evenly
  from v to rest over d px - a brake of v²/2d, taking 2d/v - and lies there
  until its life is up, fading over the last `FADE_SECONDS` (0.75, the
  puddle's own fade). The step is exact however the frames fall: the frame's
  average speed times its length, or v²/2·brake in the frame it stops.
  `fire_fan` and `fire_ring` take `stop_at` for it; `SETTLE_LINGER` is 3 s.
- **The lob** (`src/world/bulletlob.gd`, `BulletZone.fire_mortar`) carries the
  artist's acid ball sprite - taken off the element's ball scene by
  `poisonslime.gd`'s `_lob_art`, tinted and recoloured as a shot of that
  slime's is - along a parabola, drawn up to twice its size at the top, with a
  shadow under it. Nothing touches it in the air. The crater's edge is drawn on
  the floor from the moment it leaves and fills in as it falls.
- **The puddle is the one the ball always left** on a hit
  (`Puddles.scene_for`), so a mortar leaves the same acid, in the same
  element, that the straight ball does.
- **The two shots take turns** (`_mortar_next`, the leader's), the spray first.
  The mortar is `"v": "mortar"` on the wire, and both carry `"r"`, held on
  every screen to `MORTAR_REACH_MAX` / `SPRAY_REACH_MIN..MAX`.
- **The ring leaves from 12 px out** (`BulletLob.RING_STARTS_OUT`), past the
  impact's reach on a player at the spot. Since 0.25.3 every orb that
  reaches you lands, and a ring born on the spot added eight hits to the
  acid ball (watched: 55 and eight 19s). The spot is the ball's; the
  crater is for whoever was near it.
- **Recorded in the real Field** with two large slimes: the sprays settle in a
  wall across the player's spot, and each mortar leaves a ring of mines round
  a puddle.
- Tests: settling exact under uneven frames, three quarters of the way at
  half its time, lying 3 s and fading, spent on contact; the spray settling
  where the player stood; the mortar's art, its spot, its arc, its landing
  (impact + 8), the crater at 40 px, the puddle in its element, the hit on a
  player who stayed, the turns; the leader's "r" and "v": "mortar"; the
  follower's lob and its range, and its spray settling at the leader's "r".

### How fast a character moves (0.25.1)

A walk is `speed + (agility - 1) * PlayerStats.AGILITY_SPEED_PER_LEVEL`
(player.gd, and tank.gd's own copy), where `speed` is the class's
`CLASS_SPEED` (warrior 200, mage 165, tank 160, healer 140); sprinting
multiplies it by `sprint_speed_multiplier`.

- **1 a level and 1.5x since 0.25.1; 10 and 2x before.** The owner: "at level
  99 max speed chars are way too fast especially with the option to run". A
  level-99 warrior walked 1,180 px/s and sprinted 2,360, past every orb in the
  Field; now 298 and 447. Every class at 99 is about half again its agility-1
  speed.
- **Both numbers are the server's too.** `"agility_speed"` and `"sprint"` in
  gamedata.json are what the presence server's combat book judges a walk
  against (gamedata.py `combat_bounds()`), so a change goes through the
  exporter and the API's copy of gamedata.json. A server still holding the old
  numbers only judges more loosely, never wrongly.
- Agility XP for ground covered is per 1,000 px, so a slower walk trains it a
  little slower at high levels; the sprint's per-second XP is unchanged.
- Tests: the export agrees with the code in both places a walk is worked out,
  and a level-99 warrior walks 298 and runs 447.

### The healer aims from the middle of its body, and shows it (0.26.0)

The owner: auto fire "is broken between flipping from left auto fire to top
left and right to top right where as bottom directionals are fine", and the
fix the owner proposed: "a small circle under the character with a ball in
it ... the ball would move when player clicks on the screen to show the
accuracy of aim" - "the same thing as games that show directional movement
with the circle around the character".

- **The stream left from the feet.** healer.gd aimed and spawned from the
  node's origin, which is the healer's feet; the picture is drawn 15 px above
  them. A cursor level with the chest was 10 to 20 degrees up from the feet,
  and a stream aimed up and across left the feet and crossed the healer's own
  body on its way out - the upper diagonals - while one aimed down left from
  below the body and looked right. `AIM_FROM` (0, -16), the hurtbox's height,
  is now where a shot is aimed from (`aim_origin()`, `aim_direction_to()`),
  where the orb is placed, and where the others' picture of it starts.
- **The aim ring** (`src/characters/aimring.gd`, `AimRing`): an ellipse on the
  floor round the feet (18 x 8 px), the healer's first child so it draws under
  the sprite, with a ball at the aim's angle that reads the same
  `aim_direction_to()` the shot does. The ball is drawn on a child at
  z_index 1, because aiming up puts it on the far side, behind the legs. Both
  are unshaded (the Field's CanvasModulate turned the first one grey), and
  brighten for a moment as each shot leaves. Hidden when the healer dies.
- Not in the tree in the suite (player.gd's _ready() is the camera, the pets
  and the save): `_test_the_healer_aims_from_its_middle` positions a healer
  instance, calls `_add_aim_ring()`, and reads the spawn from the source. With
  `AIM_FROM` back at the feet, two of its checks fail.
- **The warrior has one too (0.27.0)** - the owner: "add to warrior also".
  The ring's helpers moved to player.gd (`_add_aim_ring()`, `aim_ring_feet()`,
  `_point_aim_ring()`, `_aim_ring_fired()`), and a class that aims at the
  cursor calls them. The warrior's origin is already the middle of its
  picture (sprite 3 px above it, feet 13 below), so it aims from there as it
  always did - now through `aim_direction_to()`, which the swing and the ring
  both read; its ring sits at (0, 12.5), a hair above the sprite in its
  y-sorted body so the ring draws first. It brightens on every swing. Mage and
  tank had none until 0.33.0 (below).
- **The mage and the tank (0.33.0)** - the owner: "meant mage and tank just aim
  ring". Both attack a POINT (the spell at the cursor; the stick where it
  lands, `tank.dynamite_landing()`, up to 150 px toward the cursor), so they
  point it with `_point_aim_ring_at(point)`: the ball on the line from the
  middle of the ring to that point. The tank's body is y-sorted with the
  picture placed well above the feet, so a ring at the feet would draw over
  it: `aim_ring_placed_at()` puts it a hair above the picture (drawn first)
  and `AimRing.drawn_at` draws it down at the feet. **The mage's body is not
  y-sorted since 0.68.1** - its picture sat 19 px above its feet, and a
  y-sorted body sorts every picture by the picture's own height against the
  whole world, so a mage walked up to a wall sorted 9 px behind the wall's
  foot and the bricks were drawn over it (the owner's screenshot: "big error
  on walls"). Unsorted, the mage sorts at its origin (its feet), and its ring
  at (0, -1) is simply its first child, drawn under the robe by tree order.
  `_test_every_class_stands_in_front_of_a_wall()` works out every class's
  sort height walked up to a wall from its own scene. The tank already wears an orange ring at its feet (tank.tscn's
  `ring`, smalltankring.png - not the aura's fire ring), so its ball rides
  that one: `aim_ring_radii()` is its size, measured off the art
  (`OWN_RING_HALF` 31.5 x 16.5 frame px round `OWN_RING_FROM_FRAME_MIDDLE`,
  times the node's 0.9), and `aim_ring_has_line()` is false. It flashes on a
  cast, a throw and the aura switched on. `_test_the_mage_and_tank_aim_rings`
  measures the orange ellipse off the PNG, so redrawn art fails a check.

### Every monster shows who it is after: a red ring and dot (0.28.0)

The owner: "i want the same ring for enemies but with a red dot and we will us
detection to make the dot aim to the player".

- **`ThreatRing`** (`src/enemies/threatring.gd`) extends `AimRing`, whose size
  and colours became instance vars (`radii`, `ring_colour`, `ball_colour`) for
  it. `BaseEnemy._ready()` puts one on every monster, bosses included
  (`ThreatRing.on(self)`, first child so it draws under the monster), and
  `_trigger_attack()` makes it flash. Sized from the monster's own shapes:
  centred 4 px below `bodyshape`, as wide as the larger of that and the
  hurtbox (1.8 x / 0.8 x the radius, at least 8).
- **The detection is the monster's own.** The ball points at `player`, the
  body BaseEnemy chases and shoots at (its `bodyshape`, `Targets.body_point`),
  so in a group it shows which of you it picked. It shows only while that
  target is within `leash_range`, measured as BaseEnemy measures it (origin to
  origin) - past it the monster walks home - and not while gated, frozen
  (`is_physics_processing()`, the welcome story) or dead. Dim (45%) while it
  only chases; full red once you are inside its `attack_range`. A bush mage's
  leash is 1,500, so its ring is up from far off: that is how far it chases.
- **A follower's copy** (`net_mirror`) has no target of its own; its ring
  points at the nearest player (`Targets.nearest`).
- `_test_monsters_show_who_they_are_after` runs a darkbushsniper out of the
  tree with a ZoneDummy target **in** the tree - out of it the dummy's body
  position is cached after the first read and never moves. The sniper's `hp`
  is set by hand, since its `_ready()` never ran. Dropping the ring from
  `_ready()`, the leash check, the frozen check or the dimming each fails a
  check.

### How far things reach: the warrior's reach, a monster's detection (0.29.0)

The owner: "now we need one for range on warrior like distance for attack and
enemies so i can see their detection range so a much bigger circle"; asked
when a monster's should show, "Always, faint".

- **`RangeRing`** (`src/shared/rangering.gd`): a dashed line on the floor at
  a distance. Dashed where the aim rings are solid - an aim ring says which
  way, a range ring how far. **Not squashed**: the game measures distance the
  same every way (`distance_to`), so the line is a world-space circle. It
  takes four reaches (left, right, up, down) and blends between them
  (cos^2 / sin^2), exact straight out each way; a circle is the four the
  same. Unshaded; `fired()` flashes it.
- **A monster's detection** (`ThreatRing.sense`, node "detectionring", the
  monster's second child after the red ring): a circle round its origin, where
  BaseEnemy measures from. Shown whenever it could notice anyone (not gated,
  frozen or dead). In 0.29.0 it was the `leash_range`, faint, brighter once
  the monster was after someone - 400 to 500 px, wider than the screen at the
  default zoom (427 x 240 world px), and the owner's next word was "now fix
  monster leash and radius". Since 0.30.0 it is two lines - see below.
- **The warrior's reach** (`warrior.gd`, node "reachring", round its origin):
  **a mythic's only (0.29.1).** With the Double Axe, `mythic_reach()` gives
  `SpinningAxe.MAX_THROW + HIT_RADIUS` (190); with anything else it is 0 and
  the ring is hidden. 0.29.0 also drew the sword's reach, read off its four
  hitboxes (31 left, 32 right, 25 up, 28 down - about the warrior's own
  width), and the owner: "that small circle for warrir for range with that
  weapon is not needed". Refitted in `_on_gear_changed()` (through
  `_show_reach_for()`, which the suite calls without equipping), flashed by
  every throw, hidden while dying. **The slash wave has no line**: it flies
  until it hits a wall or leaves the screen (slashwave.gd's
  VisibleOnScreenNotifier2D), so its range is the camera's.
- `_test_how_far_they_reach`. Taking out the warrior's ring, showing it for
  the sword, squashing the circle, dropping the detection circle, its
  brightening or its hiding each fails a check.

### Monsters notice you close and chase you far (0.30.0)

The owner: "now fix monster leash and radius"; asked, "Notice close, chase
far". Until now one number, `leash_range`, was both how close you could come
before a monster came for you and how far it followed - so it noticed you from
off the screen (400 to 500 in the Field, 1,500 for a bush mage).

- **`notice_range`** (BaseEnemy, 250 by default): it comes after you once you
  are this close, origin to origin. **`leash_range`** is unchanged: once after
  you it keeps on until you are further than that, then walks home and has to
  notice you again. **Being hit** notices too (`take_damage()` sets it), so a
  shot from outside 250 is answered. `notice_reach()` is the smaller of the
  two, so the Big Field's 250 leashes keep their 250.
- **`engaged`** holds it; `keep_after(dist)` is the one rule (notice inside
  `notice_reach()`, let go past `leash_range`). BaseEnemy's
  `_physics_process()` calls it and, while not after its target, looks for a
  nearer one on the retarget clock - so with several players it notices
  whoever walks up first. bushmage.gd (its own AI) calls it the same way.
- **Bosses notice as far as they chase** - `BossEnemy.notice_reach()` returns
  the leash, as before.
- **A slime's twin and its smalls** inherit `engaged` (`_spawn_slime()`): a
  large splits because it was hit, and four smalls that had to notice the
  shooter afresh would stand about.
- **Followers' copies** run no AI; threatring.gd applies `keep_after()` to the
  player nearest a copy, and a hit on it sets `engaged`, so its ring and
  circle follow the same rule. Nothing new is sent between games:
  `notice_range` is the class's own, the same in every game.
- **The circle** (threatring.gd `_sense()`): not after anyone, `notice_reach()`
  and faint - cross it and it comes for you; after someone, `leash_range` and
  brighter - get past it and it lets you go.
- `_test_monsters_notice_close_and_chase_far` runs a real darkbushsniper's AI
  in the tree with a stand-in player at 320 (not noticed), 240 (noticed), 470
  (still after you), 700 (let go) and 380 then hit (noticed).
  `_test_how_far_they_reach` checks the circle's two lines. Putting the notice
  back to the leash, dropping the hit, never letting go, or drawing the circle
  at the leash each fails a check.

### Monsters walk in between attacks, and the rings have switches (0.31.0)

The owner: "i want enemies to actually chase the player closer while attacking
and add the option in options to enable veiw of the circles or disable".

- **Pressing in** (BaseEnemy `_handle_combat()`, `press_reach()`): a monster
  used to stop the moment you were inside `attack_range` (200 to 280 px) and
  shoot from there for the whole fight. Now, between attacks
  (`attack_ready` false), out past `press_reach()` it keeps walking toward its
  slot (`_chase_slot()`, the chase it always had); inside it, it holds as
  before. It still attacks the moment it is ready, from wherever it stands.
  `press_reach()` is `PRESS_SHARE` (0.5) of the attack range, but never inside
  where it would turn and flee - `flee_range * FLEE_RELEASE_FACTOR +
  PRESS_CLEAR` - or a kiting archer would walk in, flee, and walk in again:
  sniper 110, sprite 140, fire sprite and large slime 120. **Bosses hold their
  spacing** (`BossEnemy.press_reach()` is the attack range; melee_range
  decides swing or cast). The bush mage runs its own AI from a 36 px ring and
  was already close.
- **Two switches in Options, under RINGS** in the right-hand column (the left
  was already the taller, and the panel is drawn at 600 px - the suite checks
  it still opens at that): `aim_rings` (your aim ring, player.gd
  `_point_aim_ring()`, and each monster's red ring, threatring.gd) and
  `range_circles` (each monster's detection circle, threatring.gd `_sense()`,
  and the warrior's mythic reach, warrior.gd `_reach_ring_shown()`). Both on
  by default; read where each ring decides whether to show, every frame, so a
  change shows at once. What each covers is in the rows' tooltips.
- `_test_monsters_walk_in_between_attacks` runs a darkbushsniper's AI in the
  tree: between attacks at 190 of its 200 it walks in, and inside its 110 it
  holds. `_test_the_rings_have_switches` turns each off and on. No pressing,
  or a ring that ignores its switch, each fails a check.

### The mage's off hand: tomes, wands and grimoires (0.32.0)

The owner: "i noticed mage hass no offhand can we check clockworks art for
something of the sort", then, shown what the pack held, "tombs grimoires and
off hand wands i can make them special later but give them some stats".

- **The art is Caio's** (Clockwork Raven), from the owner's copy of
  **Premium - Raven Fantasy Icons** on his desktop - the pack every item icon
  already came from. Its full 16 px sheet (`Full Spritesheet/16x16.png`, 16
  across, 516 rows) is where each icon was cut: tomes from the magic set
  (row, column) iron (105,2), jade (108,12), cobalt (105,3), amethyst (109,5),
  ember (108,3); wands from each tier's own weapon block, the short wand beside
  the staff - (281,1), (301,1), (291,1), (296,1), (286,1); the grimoires from
  `New updates/Epic Weapons 3` (row 1, columns 6-8). In `art/pack/armour/`,
  the private submodule, like every other item icon.
- **Thirteen items in the shield square, mage and healer** (`data/items/armour/`):
  `<tier>tome` (armour + mana), `<tier>wand` (damage % + mana), each on its
  tier's shield rung - same tier, level and price - and `arcanegrimoire`
  (damage), `verdantgrimoire` (health) and `sapphiregrimoire` (mana), tier 5,
  level 22, 22,800 gold, a little past the ember pair. Tomes 2/4/6/9/13 armour
  and 5/10/16/24/34 mana; wands 1/2/3/4/6 % and 3/6/10/14/20 mana.
- **The store** sells iron to amethyst, beside each shield; the ember pair and
  the grimoires drop, like all ember gear. Drops need nothing new: the server
  picks a tier's gear evenly from gamedata.json, so these join their tiers'
  pools once the API has the new catalogue.
- **The server must have the new gamedata.json before anyone can be given
  one** - equip, shop and loot all read it. The API's `test_equipment.py` and
  `test_economy.py` check the mage wears them and nobody else does, the
  grimoire's level, the shelf and the drop pools.
- **The healer wears them too (0.32.1)** - the owner: "and the healer?". It
  had no off hand either, and cloth (robes, hoods) was already shared by the
  two, so `required_classes` is `["mage", "healer"]` on all thirteen rather
  than a second set. Warrior and tank keep their shields.
- `_test_the_mage_has_an_off_hand` reads the .tres as text (so a clone checks
  the numbers too), the store, gamedata.json, and with the pack the icons
  (16 px) and the registry. A flat wand tier or a tome a third class can wear
  each fails a check.

### The tank's aura burns on the ground (0.34.0)

The owner, with a picture of the lit aura: "i want us to elavate the animation
by adding effects and born on the ground", and, asked how the ground should
burn, "Both" - the floor inside the ring glowing with small flames while it is
lit, and the ground it passes over left scorched, with dying embers, for a few
seconds.

- **`AuraBurn`** (`src/characters/auraburn.gd`), put on by `tank._ready()`
  (`AuraBurn.on(self)`), follows the `firering` sprite's visibility - no new
  calls in tank.gd's aura code. Lit, it fades in over 0.3 s and out over 0.6:
  the ring made unshaded (fire in the dark) with a small pulse; a pixel-banded
  additive glow on the floor inside it (brightest by the flames, spilling a
  little past); a flickering `PointLight2D` in a dark area only (an area with
  a CanvasModulate), switched with `enabled` so Settings' "simple" lighting
  still hides it by `visible`; flames (a 3 x 7 spark like the ring's own) off
  the floor inside, and embers off the ring's line (`CPUParticles2D`, unshaded).
- **Placed above the fire ring's own sort point** (its frame is placed by the
  top-left corner, 131 px up) so the y-sorted tank draws it first: the glow
  under the ring's line (added on top, it turned the line white in the first
  recording) and under any monster standing inside the ring.
- **Measured off the art**: the fire ring's line runs 51 x 30 frame px round
  (64, 83) of its 128 px frames, times the node's scale - about 75 x 43 round
  (-0.9, -12), which is the aura's own capsule within 2 px.
- **`ScorchMarks`** (`src/world/scorchmarks.gd`): one per area, a child of the
  area's `ground` layer, so it draws with the floor in every scene (field,
  bigfield and elusion have the ground at z -10, boss and bossarena at 0 in
  tree order). Patches are 8 seeded pixel blots, 16 to 30 px, dark for 1.4 s
  and gone by 4.5, each with 2 to 4 embers that cool within 2.6 s; at most 140.
  The burn lays 4 a second standing and one per 7 px the ring moves (a jump
  past 64 px is not a walk), anywhere on the floor inside the ring, and none
  where the ground has no tile - water showed through there in town.
- **Remote tanks too**: `remoteplayer.gd`'s `_build_body()` puts one on the
  copy's `firering` and rebuilds it with the body.
- `_test_the_tank_aura_burns` uses the real tank scene with its script taken
  off (no player _ready()), measures the ring off the PNG, and checks the
  glow, light, particles, scorch rates, fade, cap and the no-floor rule. Each
  was broken on purpose to see it fail.

### The boss rooms' floor was over everything that lies on it (0.34.1)

Found while the tank's scorch went in. Whatever lies on the floor pins an
absolute z under the entities' 0: blast marks -2 (blast.gd); a crater's glow,
a lit stick of Dynamite, a meteor's shadow, the mage's target circle and the
Double Axe's spatter -1; the boss gate's far pane -5. The field, the big field
and the town put `ground` at z -10 and `water` at -20, but boss.tscn and
bossarena.tscn left both at 0 - so in the boss room and the gauntlet all of
those were drawn under the floor tiles and never seen (a red square at -2 was
hidden there and plain in the field). Both scenes now match the others. The
gates in the arena show their back pane for the first time, as bossgate.gd
always meant ("far" behind the boss, "near" in front).
`_test_every_area_floor_is_under_its_floor_effects` reads every area's .tscn
and fails on a ground at -5 or above, or water not below the ground.

### The mage's spell, with effects (0.35.0)

The owner: "time to give the mages attack some effects", and of the four
offered for the ice stalagmite, all four.

- **Motes off the staff** (`src/characters/castsparkle.gd`, `CastSparkle`):
  a one-shot burst round the staff's gem and a streak toward where the spell
  goes, whole-pixel and unshaded, frost for the stalagmite and embers for the
  Meteorite's meteor. The gem's place per facing (`CastSparkle.GEM`, from the
  middle of the picture) was measured off the first frame of each attack
  animation in mage.png - the suite measures it again. mage.gd's
  `_cast_stalagmite_drop()` throws one on every cast; remoteattacks.gd throws
  one for a picture of somebody else's mage (`facing_of()` reads the facing
  off the picture's animation; a double meteor's second throws none).
- **The frost ring and the shadow** (spelltargetcircle.gd): the red
  antialiased 2 px circle became a 1 px ice-blue ring with a faint band inside
  and six glints, frosting in as the spike falls, and the meteor's pixel shadow
  (`Blast.shadow_texture()`) growing under it - both timed off the animation
  (`fall_progress()`, `after_progress()`), fading after the impact. Still
  exactly the hit (`circle_radius` 18, the collision shape's).
- **The shatter and the frost** (blast.gd, a third kind, `&"stalagmite"`):
  spawned on IMPACT_FRAME beside the spell, a cold flash, a ring of air, mist,
  ice shards and glints, the smallest camera shake (0.6 px, 0.1 s - a mage
  casts every half second; none for a picture), and `frost_texture()` left at
  z -2 that glints (unshaded twinkles) and melts - it fades and draws in to 70%
  over the last 40% of MARK_SECONDS.
- **`Blast.disc_texture()` caches by colour too.** The key was the size alone,
  so two discs of one size in different colours were whichever was made first
  - a smoulder's glow could come out a crater's, and the cold flash a hot one.
- `_test_the_mage_spell_effects` measures the gem off the art and checks the
  burst, the palettes, both casters, the ring's timing, the shatter's parts,
  the cold flash, the shake, the frost and its melt, and the cache key. Each
  was broken on purpose to see it fail.

### The mage's spike finds its mark, and the third cast drops three (0.70.0)

The owner: "mage is the weakest of all my chars ... a single ice spike is
kinda lame". The spike lands a third of a second after the cast
(`IMPACT_FRAME` 4 at 12 frames a second) on an 18 px circle, so a monster
walking at 60 px/s was 20 px on by then and most casts at anything moving
missed - the class's designed dps (20/s against the warrior's 24/s) was a
ceiling it rarely reached.

- **The spike finds its mark.** `Mage.spike_marks()`: the nearest monster
  within `SPIKE_SEEK_RADIUS` (48 px) of the aim that the mage can see
  (`can_hit()`) and that can be aimed at. The spike starts on its feet and
  follows them down (`spelltargetcircle.gd` `target`, `follow()`), letting
  go at the strike, or when the mark dies, sleeps or goes behind a wall.
  Nothing near the aim: it lands where it was aimed, as before.
- **The third cast drops three** (`TRIPLE_EVERY` 3, `TRIPLE_SPIKES` 3): the
  mark first, then the next nearest monsters within `TRIPLE_REACH` (110 px)
  of it, or round it `TRIPLE_SPREAD` (44 px) out when there are none.
- **One spike a monster a cast.** The spikes of a cast share `struck`, so a
  monster under two of them takes one. One monster takes no more than it did,
  and the server's bound on a mage (`gamedata.combat_bounds()`, a hit a cast)
  still holds with no server change. The damage is rolled once a cast.
- `_test_the_mage_spike_finds_its_mark()`.

### The mage's kit: a heavy spike, a critical one, and ice shards (0.71.0)

The owner: "mage needs to be strong enough to kill enemies at level 1", and of
how: "consumes more mana deals more damage i was thinking more projectiles
maybe a critical projectile also maybe some ice bullets that spin in a circle
around the ring". A level 1 mage's whole bar of 250 was 144 damage (15 mana
for 9), short of one Wind Sprite (233); the healer got five times as much out
of a point of mana.

- **The heavy spike.** `spell_mana_cost` 20, `damage_per_magic` 30,
  `spell_cooldown` 1.0 (it was 15, 9 and 0.45): a bar is 360 damage, a sprite
  about eight casts. 30/s is a quarter above the warrior's swing alone and
  under its swing and wave. Every staff and the Meteorite scale with it
  (THE LADDER in the API's `test_equipment.py`: a staff adds what the sword
  adds, times 30/24): 25 / 40 / 60 / 88 / 125, Meteorite 175.
- **The critical spike** (`CRIT_CHANCE` 0.2, `CRIT_MULT` 2): one cast in five
  hits twice as hard, drops the third cast's three spikes too and shatters
  `CRIT_SHATTER` (1.6x) wider. Rolled once a cast (`rolls_critical()`); the
  owner panel's "Always roll the 10%" makes every cast one. `crit_chance` on
  the mage is the roll a test pins. Others see it too
  (`RemoteAttacks.FLAG_CRITICAL`, 128).
- **Gold, as every class's big roll is.** The owner: "we need that critical to
  be gold like the other chars" - "well the spike gold". The spike's art is
  turned gold by `element_recolour.gdshader` (hue `CRIT_HUE`, its shades
  lifted by the shader's `value_lift`, 0 for every monster, so it is not
  brown); its ring and glints are gold, its shatter tinted `CRIT_TINT`, its
  shards the warrior's gold orbs (`BladeOrb.GOLD`), and its numbers big and
  gold (`BaseEnemy.take_critical_damage()`, `FloatingLabel.Type.CRITICAL`,
  appended, in the healer's double's gold, at 0.85 scale).
- **The ice shards** (`src/projectiles/frostring.gd`, preloaded, no
  class_name): as a spike strikes, `SHARDS` (6) ice blade orbs appear
  `ORBIT_PAD` (6 px) outside its frost ring, spin round it for
  `ORBIT_SECONDS` (0.5), then fly out `SHARD_REACH` (70 px) at
  `SHARD_SPEED`, each for `SHARD_SHARE` (0.2 since 0.71.1; 0.4 before) of
  the spike's hit. They break on walls, none starts past one, a picture of
  somebody else's cuts nothing, and the ring is gone by `MAX_SECONDS` (3).
- **Every shard hits what it touches, and is spent on it (0.71.1).** The
  owner: "the spinning balls are not hitting the enemies, really we need to
  increase the amount of times a enemy can be damaged and make sure bullets
  are absorbed by impacts". In 0.71.0 the shards shared the spike's "one hit
  a monster a cast", so they spun through the spike's own mark untouched. Now
  a shard hits any monster it touches and pops there; a monster takes
  `SHARD_HITS_EACH` (2) shards a cast after the spike, counted across the
  cast (`BladeOrb.cast_hits` / `cast_hits_each`, the spike's `shard_hits`),
  and one past that is still absorbed, for nothing. A monster takes up to
  three hits a cast, 1.4 spikes' worth.
- **One caster's count.** `struck` and `shard_hits` are one mage's cast:
  four players on one monster each land every hit (the owner: "if 4 people
  are attacking 1 monster i do not want only 1 persons attack to register";
  monstersync.gd sends each follower's hits to the leader, and each helper
  reports their own kill).
- **The server's bound** (`gamedata.combat_bounds()`) takes every cast
  critical and every monster two shards: `crit_chance`, `crit_mult`,
  `shard_hits_each` and `shard_share` are exported with the class. **Deploy
  the API with the game**, or the bound is short.
- `_test_the_mage_kit()`.

### Bullets that fly true (0.72.0)

The owner: "we need to upgrade bullets to be way more refined darza managed
this ability nicely" (Darza's Dominion, a co-op bullet hell), and of what was
offered: shape and flight, hitboxes and rules, and the monsters' bullets too.
His own art only - nothing new is drawn; what flies is turned and drawn
longer.

- **They face where they fly.** The healer's orb streams its flame behind it,
  the art's tip back along its path, turning with the weave and the homing
  (`turretprojectile.gd` `_face_flight()`; it never turned before). Blade
  orbs - the warrior's fans and burst, the mage's ice shards - are drawn
  `BladeOrb.STRETCH` (1.25 x 0.85) along their flight and round when still
  (`face()`; a carried shard along its ring, `stretched_still`). The Field's
  bullets are drawn `STRETCH_LONG` x `STRETCH_SHORT` along their velocity,
  curving ones turning with it (`BulletField._shape()`, `shape_of()`); one
  slower than `STRETCH_SPEED` is round and square, because a round orb turned
  a little is only its pixels made ragged. Arrows and the fire, electric and
  acid orbs already turned to their heading.
- **Hitboxes match the art.** Electric orbs (all seven and the pet's): the
  circle was 60% of the 13-15 px orb, now its size (6.5 for the plain one,
  every variant by its own scale). Arrows: the capsule is the 3 px shaft (it
  was 2). The healer's orb: `hit_pad` 6, half its flame's drawn width (it was
  14 - an orb passing 20 px from a slime hit it). The Field's bullets keep
  `SMALL_RADIUS` / `BIG_RADIUS`, their bright body, as the blade orbs keep
  `RADIUS`.
- **Rules.** Every bullet is used up on what it hits (the survey found them
  all so, the warrior's burst passing over the monster it bursts from on
  purpose). The electric orb ends at `RANGE` (360 px) on every screen - it
  ended where it left THIS player's camera, so one shot flew a different
  distance on each. A pet's arrow born inside a bush and a monster at once
  looked at the bush only and flew through the monster; it looks at all.
- `_test_bullets_fly_true()`.

### The healer's orbs, mixed with the crypt's (0.36.0)

The owner, of the healer's attack: he paid for its orb, so keep it, "mixing
with the bullets from crypt and adding a effect also" - and, offered how,
"Patterns too". (The healing animation he showed is an AoE effect still to
come; nothing here heals.)

- **The paid orb, dressed** (turretprojectile.gd, THE ORB, DRESSED): a 2 x 2
  white-hot core on its ball and a faint green glow behind (added, unshaded) -
  the crypt bullet's look; green wisps behind it that outlive it by their own
  0.35 s (`_let_go_of_trail()` hands them to the parent); and where it hits,
  `splash()` - eight green sparks and a small `Blast.BlastRing`, z 5. The root
  is drawn at 2x, so what is added in world pixels is scaled by half. The
  first glow (radius 5, alpha 0.35) made every orb a blob twice its size; it
  is 4 and 0.25.
- **THE FAN** (healer.gd): every `FAN_EVERY` (5th) shot also throws
  `FAN_ORBS` (2) orbs `FAN_SPREAD_DEGREES` (16) either side, each for
  `FAN_SHARE` (half) of the shot's damage, no mana of its own. A fan orb is
  turretprojectile with `fan` set BEFORE add_child (its _ready() reads it):
  the paid sprite hidden, the crypt bullet's 8 x 8 orb (bulletfield.gd's,
  coloured: white core, `ORB_GREEN` body, darker rim) in its place, straight -
  no homing, no weave. Smaller and greener than a monster's bullet, and
  trailing wisps, so it does not read as one.
- **At most a fifth more on one monster** (all three hitting it). The exporter
  writes `fan_every`, `fan_orbs` and `fan_share` into gamedata.json, and the
  API's `gamedata.combat_bounds()` multiplies the healer's rate by
  `1 + fan_orbs * fan_share / fan_every`. Inside `SLACK` (1.5) even on a
  server not yet updated. The stats window's dps stays the single stream.
- **Motes off each shot**: `CastSparkle.muzzle()`, five green motes at
  `AIM_FROM`, no streak (ten a second).
- **Others see it**: the "orb" attack carries `RemoteAttacks.FLAG_FAN` (8) on a
  shot that fanned - presence.py passes any flags up to 255 - and the picture
  throws the fan too (`fan_ways()` asks healer.gd), with the motes.
- `_test_the_healer_orbs` checks the rhythm, the angles, the share, the order
  `fan` is set in, the dressing, the splash, the wisps left behind, the fan
  orb's look and flight, the picture's fan and the export. Each was broken on
  purpose to see it fail.

### Longer glowing trails and the golden double (0.37.0)

The owner: "make the glowing trails longer and add a 20% chance to deal dbl
damage on 1 main projectile" - and "can make a diff color if needed".

- **The trails** (turretprojectile.gd): `TRAIL_SECONDS` 0.8 (was 0.35),
  `TRAIL_WISPS` 24 / `FAN_TRAIL_WISPS` 16 (were 10 / 8), added (they glow),
  drifting up less (-5, was -14) so each orb draws a line behind it.
- **THE DOUBLE** (healer.gd): every main orb rolls `DOUBLE_HIT_CHANCE` (0.2)
  - `rolls_double_hit()`, `double_hit_chance` a var for the tests, forced by
  the owner panel's "Always roll the 10%" like every class's common roll - to
  hit `DOUBLE_HIT` (2) times as hard. Rolled before add_child() (`doubled`
  dresses the orb in _ready()); the fan is figured from the shot before it
  doubles, so a fan orb never does.
- **Gold**, the healer's halo's colour: the flame `self_modulate`d by
  `DOUBLE_TINT` (2.0, 0.95, 0.5 - over 1, so the green flame comes out gold; the
  first try, 1.9 / 1.15 / 0.45, came out lemon), a gold glow and core, gold
  wisps (`gold_colours()`), and `splash(..., big)`: 16 gold sparks and a 15 px
  ring. Others see it: `RemoteAttacks.FLAG_DOUBLE` (16) on the "orb" attack.
- **The server's books**: the exporter writes `double_chance` and `double_hit`,
  and the API's healer bound takes the worst, as it does for every roll: its
  biggest hit is a doubled orb and its rate every orb doubled plus the fan
  (`unit * (double_hit + fan) / cooldown`). The server has to be updated
  before players get 0.37.0 - a doubled hit is past the old biggest hit
  times SLACK, and would be capped and flagged `hit_too_big`.
- `_test_the_healer_orbs` adds the roll, the order (the roll before the add,
  the fan before the double), the gold, the bigger splash, the longer glowing
  trail, the picture's gold and the export. Each was broken on purpose.

### The warrior's blows, seen and felt (0.38.0)

The owner: "the final character warrioe how can we make him better also" -
and of the four offered, all four: "Swing arc + sparks", "Dressed slash
wave", "Heavier hits", "Third-swing finisher". The arc and the dressing of a
plain wave did not last: see 0.39.0 below.

- **src/shared/strikefx.gd**, preloaded as `Strike` by warrior.gd and
  slashwave.gd (no class_name). `sparks()`: a small flash and 8 steel sparks
  at z 5 where the sword or the wave lands (`hit_point()`, the middle of the
  hurtbox), and where a wave breaks on a wall. (Its `arc()` - a white Line2D
  swept round every swing - went in 0.39.0.)
- **THE HIT-STOP** (warrior.gd): the first time a swing connects, the
  monster's picture and the warrior's hold still `HITSTOP_SECONDS` (0.06) and
  the camera shakes a little - pictures only, the fight is not paused. The
  swing lock ends on the attack animation's `animation_finished`
  (player.gd), so a held picture would have made every next swing that much
  later - about 13% fewer swings for a warrior that hits with every one. So
  the warrior's picture plays the rest of the swing faster after the hold
  (`swing_time_left()`) and the swing ends when it would have; so near the
  end that the rest would have to rush, it is not held at all.
- **THE FINISHER**: every `FINISHER_EVERY` (3rd) sword swing - not the Double
  Axe's, whose swing is the throw - throws a gold wave `FINISHER_SCALE`
  (1.35) as big, its hitbox too, for `FINISHER_MULT` (1.5x) the wave's
  damage: unshaded, with a gold glow behind it (a larger copy, added), gold
  sparks and a longer stop (0.09). Set before `shoot_vector()`, which dresses
  the wave. Others see it: `RemoteAttacks.FLAG_FINISHER` (32) on the "slash"
  attack.
- **The server's books**: the exporter writes `finisher_every` and
  `finisher_mult`, and the API's warrior bound takes the worst - every wave a
  finisher's - for its biggest hit and its rate.

### The warrior's crypt orbs, and no trails (0.39.0)

The owner, of 0.38.0: "its horrible not the kind of effects i was thinking of
and i have a projectile faintly spawning across screen like huh? the trails
are bad i would say maybe the gold one is cool but no trails we can use
projectiles from crypt to elavate". The faint thing across the screen was the
wave, now unshaded and glowing, flying off with its afterimages. Offered four
ways to use the crypt's orbs, he took all four.

- **Out**: the swing arc (strikefx.gd's `arc()`), the afterimages, and a plain
  wave's glow and unshading - it looks as it did in 0.37.0. The gold finisher
  keeps its gold, size and glow, with no trail.
- **BladeOrb** (src/projectiles/bladeorb.gd, class_name): the Field's bullet
  for the player's side. An enemy bullet only has to find one player, so it is
  a packed-array slot (bulletfield.gd); these have to find monsters, so each is
  a small Area2D on the slash wave's layers (32, mask 11). The crypt orb's
  8 x 8 pixels - white core, steel (0.62, 0.82, 1.0) or the crypt's gold body,
  darker rim - unshaded, no trail, no glow. Hits the first monster it touches
  (`take_damage()`), pops on a wall or at `reach`, passes the player and the
  monster `ignore_id` names; a `cosmetic` one touches nothing. No magic XP.
  `fan_ways()` and `ring_ways()` are the shapes.
- **THE SWORD FAN** (warrior.gd): on the first contact frame of every sword
  swing (where the arc was cut), `fling_sword_fan()`: `SWORD_FAN_ORBS` (3)
  steel orbs 18 degrees apart off the blade, 70 px out, each for
  `SWORD_FAN_SHARE` (0.1) of a swing - gold on the finisher.
- **THE FINISHER'S FAN**: `FINISHER_FAN_ORBS` (4) gold orbs 12 and 24 degrees
  either side of the finisher's wave - none down it - as fast, 300 px out,
  each for `FINISHER_ORB_SHARE` (0.15) of the wave (`wave.burst_damage`).
- **THE BURST** (slashwave.gd): a finisher bursts once into `BURST_ORBS` (8)
  gold orbs, 80 px out, each for `burst_damage`: from the first monster it
  cuts (passing over it), or else where it breaks on a wall - not off the
  edge of the screen. The orbs are added at the end of the frame
  (`call_deferred`): the cut is a physics callback, where a new Area2D may not
  join.
- **THE WEAVE** (slashwave.gd): two orbs crossing over every wave,
  `WEAVE_ACROSS` (7) either side of its line and `WEAVE_ALONG` (3) along it,
  half a turn apart at `WEAVE_RATE` (16 rad/s), over the crescent on the near
  half of the turn and under it on the far (`weave_point()`, `weave_near()`).
  Steel, gold on a finisher. A picture: no damage.
- **Others see them**: `RemoteAttacks.FLAG_SWORD_FAN` (64) on the "slash"
  attack draws their sword's fan from where the wave left; a finisher's fan
  comes with `FLAG_FINISHER`; their wave weaves and bursts by itself. All
  cosmetic. A game from before sends no `FLAG_SWORD_FAN`, so its swings fling
  nothing here. The orb numbers are read off warrior.gd by path
  (`WARRIOR_PATH`), as the healer's fan is.
- **The server's books**: the exporter writes `sword_fan_orbs`,
  `sword_fan_share`, `finisher_fan_orbs`, `finisher_burst_orbs` (slashwave.gd)
  and `finisher_orb_share`, and the API's warrior rate adds every orb on one
  monster - the sword's every swing, the finisher's twelve once in three, as
  the healer's fan is counted. A swing's worth goes from 2.125 to 3.1 (every
  orb landing on one monster), past `SLACK` of the 0.37.0 bound, so the
  server is updated before players get 0.39.0. No orb is bigger than a swing:
  the biggest hit is unchanged.
- `_test_the_warrior_blows` adds: no arc and no trails, the orb's pixels, its
  flight, hit, pass-over, picture and reach, the fans' shapes, the sword's fan,
  the plain wave's look, the weave and its turn, the burst (once, not into
  its own monster, deferred, on a wall, not off-screen), the finisher's fan,
  the pictures and the export. Each was broken on purpose to see it fail; a
  material check that threw on a missing material, and one that indexed a
  filtered list, were made to fail instead of ending the section.

### The healer's aura, and every attack on left-click (0.40.0)

The owner sent the art for the healer's heal (his "healer ff": 25 frames of
64 x 64 at 70 ms - a green pillar slamming down, a ring on the ground with
sparks rising, white motes as it fades) - "the character will not be there but
will turn into an aoe" - chose "Heal players + hurt monsters", and: "energy
beam crashes down around the circle green orbs spawn around the circle and
each blob travels to players outside of the circle giving them hp". Then,
trying it: "i can tell the image was streched keep it original size" (it had
been drawn at 2x, the pillar's top row carried on up the screen), and "i right
click and hold takes like 5 seconds should just be right click if we are using
that approach and change all attacks to left click".

- **The art**: art/maincharacter/healaura.png, the 25 frames in one strip
  (1600 x 64), beside the paid orb, and drawn at its own size - every pixel
  his, nothing stretched, nothing tinted. Its .import is the orb's settings.
- **Every class attacks on left-click** (and Space). player.gd's ATTACK INPUT
  catches the click in `_unhandled_input` - only a click no window took - and
  holds it until the button comes up (`left_click_attack_held()`);
  `_poll_attack_pressed()` edge-detects it for warrior, mage and tank, and the
  healer streams orbs while it is held. The right button is the healer's aura
  and nothing for the others; `right_click_held()` also needs a click no
  window took. The Controls card, the README and the healer's line on
  character select (64 characters at most) say so.
- **The HUD took every click.** characterhud.tscn laid its bars out in a
  `barcontainer` over the whole screen, a Control left at the default STOP:
  harmless while attacks read the mouse button straight off the hardware, but
  with the click caught where no window took it, the first recording of a
  right-click dropped nothing. It is `mouse_filter = 2` (ignore) now, and the
  suite holds that nothing the HUD lays over the whole screen takes the mouse.
- **player.gd has an input handler again** - the mouse buttons' - and the
  security check that it "reads no keys of its own" (SECURITY.md, "There are
  no debug keys") now reads its body: no key, no keycode, no action.
- **THE AURA** (healer.gd): a right-click drops it at once, at the cursor, no
  further than `AURA_RANGE` (160): `AURA_MANA_COST` (25) mana, `AURA_COOLDOWN`
  (8 s), one a click - holding it on does nothing more. A click before it is
  ready drops nothing and says why over the healer (`aura_refusal()`: "Aura
  ready in Ns", "Not enough mana"). It was first a hold of 0.3 s, which waited
  out the cooldown or the mana while held and then dropped it with nothing to
  say why - the owner's "takes like 5 seconds". Told to the area as "heal".
- **HealAura** (src/projectiles/healaura.gd, class_name): the ring's middle on
  the node (`RING_FROM_MIDDLE`, measured off the art, to the whole pixel; the
  ring 45 x 19, `RADII` 22 x 9), unshaded. While the pillar falls (frames 0-3)
  it is over everyone (z 5); from `LANDS_ON` (frame 4) it is on the floor
  (z -1).
- **The beam, dressed.** The owner: "is there any way we can make the beam
  look better?" - and of four ways offered, "Fade the top", "Glow + light" and
  "Falling sparkles". Each is its own node beside his frames (`_dress_up()`,
  `_dress(frame)`); his frames are untouched. **The shaft**: `SHAFT_HEIGHT`
  (96) px standing on the frame's top edge while the pillar falls, its own
  texture (`shaft_texture()`): each column the colour of the pillar's top row
  there, its foot exactly that row (no seam), fading to nothing going up in
  whole quarters of his alpha with a 4 x 4 dither - so the beam comes out of
  the sky instead of ending in a lid. **The glow**: a halo added round the
  shaft and pillar, `GLOW_SPREAD` past each side, fading in at the top as the
  shaft does, shown down to where his pillar's sides end in each frame
  (`PILLAR_FOOT`, measured off the art) through `region_rect` - never scaled;
  then a glow round the ring once it lands, fading over `RING_GLOW_FRAMES`.
  **The light**: in a dark area only (`AuraBurn.scene_is_dark()`, read as it
  is made), a green PointLight2D rising as the beam falls and out by
  `LIGHT_OUT_ON` (`light_energy()`), switched with `enabled` - Settings'
  simple lighting hides lights with `visible`. **The sparkles**: white-to-lime
  pixels streaming down the shaft and pillar while it falls, gone with it as
  it lands.
- **Who is healed**, decided as it lands: a player inside the ring gets
  `heal_each()` on each of `TICK_FRAMES` (4, 6, 8, 10) while still in it -
  `HEAL_SHARE` (a quarter) of their own maximum in all. `BLOBS` (8) green
  crypt orbs lift off the ring (healblob.gd, `BladeOrb.HEAL`) and fly to the
  players outside it within `SEEK_RANGE` (200), shared out in turn, the ones a
  player gets healing `HEAL_SHARE` between them; with nobody out there they
  lift and fade. Nobody dying is healed.
- **Every game heals its own player, and draws everyone else's.** A picture of
  somebody else's aura (remoteattacks.gd, "heal") heals you if you are in it,
  or sends you blobs, as your own does, and sends blobs to the pictures of the
  others for you to see. The presence server writes each heal down for the
  API's healing check (presence.py, THE AURA'S HEALS): a `__spellheal__`
  consume grant of the share for every player in the area within the reach
  (with slack), from a healer, at most once a cooldown. **The server has to be
  updated first**: an older one refuses a batch with "heal" in it whole, the
  healer's orb pictures with it.
- **The burn**: each tick, every monster in the ring takes `AURA_DAMAGE_SHARE`
  (2) orbs of damage - the healer's own aura only - through take_damage(), so a
  monster another game runs is hit where it is run. The exporter writes the
  aura's numbers (`aura_*` on the healer's row), and the API's healer bound
  adds the burn (`unit * ticks * share / cooldown`, one orb a second).
- `_test_the_healer_aura` checks the art and where the ring sits in it, that
  it is drawn as he drew it with the dressing as its own nodes, the dressing
  (the shaft's seam and fade, the pillar measured off the art, the halo's foot
  frame by frame and never scaled, the light only in the dark and only by
  `enabled`, the sparkles, all gone as it lands, the ring's glow fading), the
  landing, the ring's ticks and its edge, the
  blobs (on the ring, to whom, how much, arriving, not twice, not past the
  reach, shared between two), nobody dying, the burn and a picture's, the
  click (the range, at once, one a click, why not), every class on the left
  button, the right button needing a click no window took, the HUD letting
  clicks through, a picture of somebody else's, and the export. Each was
  broken on purpose to see it fail; one blob check compared ring_point() with
  itself and was made to measure the ellipse instead, and the dressing was
  broken twelve ways in three runs, every one caught.

### A scene on its way out hears nothing (0.40.1)

The owner's log: "Cannot call method 'create_timer' on a null value" at
enemyrespawner.gd `_respawn_after()`, from `resume_authority()`, from
monstersync.gd `_respawner_resume()` / `_become()` / `_on_lead()`, from
presence.gd `_lose_lead()` / `stop()` / `_process()`.

- **What happened.** Changing area takes the old scene out of the tree a
  moment before it is freed, and its player with it. Presence's `_process()`,
  finding no player, calls `stop()`, which says nobody leads any more
  (`lead_changed` with -1). The old scene's MonsterSync was still connected,
  heard it, took its monsters back (`_become(LEAD)`), and asked its
  respawners to start a clock for every dead spawn point - with no tree to
  time them.
- **The fix, twice.** MonsterSync is on the link only while it is in the
  tree: `_listen(true)` in `_enter_tree()` and `_ready()`, `_listen(false)` in
  `_exit_tree()` - each of the four signals connected once, whichever way. And
  EnemyRespawner starts no clock out of the tree: `resume_authority()` and
  `_respawn_after()` return first.
- `_test_shared_monsters_pieces` takes a follower's area out of the tree,
  tells it nobody leads, and checks the sync stayed a follower and off the
  link, the respawner started nothing even when asked, and that back in the
  tree it is on the link once and takes the area over. Each half was broken
  on purpose to see it fail; the code as it was gave the owner's error word
  for word ("Parameter \"data.tree\" is null", then the create_timer one).

### The healer lost its own attack in 0.40.0 (0.40.1)

The owner's log after 0.40.0: "player.gd:1545 @ attack_action(): Player:
missing animation 'attackright' - attack canceled ... like 16 errors for
that", from healer.gd's `_physics_process()`.

- **The aura's second rewrite of healer.gd took the ATTACK ACTION OVERRIDE
  block with it**: `base_attack_damage()`, `attack_period()` and the no-op
  `attack_action()`. So every left-click and Space ran player.gd's base swing
  - a sword's swoosh and that warning - and the equipment panel read a healer
  with no attack (damage 0, no dps). The orbs themselves were never touched,
  and the exporter reads the healer's numbers off its properties, so
  gamedata.json and the server's bounds were right all along (re-exported to
  check: the same).
- The block is back, word for word. `_test_every_class_answers_its_own_attack`
  holds all four classes to their own three, and a bare healer's
  `attack_action()` to starting nothing.
- **Every 0.40.0 script was compared with its last earlier copy for any
  function that went missing**: only `right_click_attack_held`, renamed on
  purpose to `right_click_held`.

### Other players: sorted as their own scene, and a switch for their attacks (0.40.1)

The owner: "on my screen garys ring is over the character and i cannot see
his attacks we need a switch to allow the sight of player attacks that are not
their own".

- **The ring.** The tank's scene y-sorts its pictures: its fire ring (its
  top-left corner 131 px up) and its small ring draw under the tank and under
  everyone standing in the fire. remoteplayer.gd built its picture from the
  same parts but never sorted, so both rings were drawn last - over the tank,
  and over every player south of it, hiding them and what they did. It sorts
  as the class scene does now (`class_sorted()`, read from the scene's root:
  warrior, mage and tank yes, healer no).
- **The switch**: Options, under the rings (the heading is ON SCREEN now),
  "Other players' attacks" - `others_attacks`, on by default. Off,
  `RemoteAttacks.fire()` draws nothing but a heal, and remoteplayer.gd lights
  no aura (it re-lights them at once on `Settings.changed`). **A healer's aura
  still heals you**: its picture is spawned `unseen` - HealAura hidden, its
  blobs too - and ticks and flies as ever.
- **Seeing his attacks.** Recorded with a picture of a warrior swinging and a
  tank burning: every wave, finisher and crypt orb was drawn; what hid things
  was the tank's ring over everyone. The server passes every attack on the
  same way in every direction (presence.py `clean_attacks()`: an origin within
  400 px of the player's last state, a target within 1000 of it); all 51 API
  suites pass (4,977).
- **Gary's "only attack left".** A real warrior, clicked and Spaced at the
  cursor in all eight directions in the Field, swung that way with that side's
  hitbox and hit a monster placed there every time. The swing follows the
  cursor - by Space too - so a cursor resting to one side swings that way.
- `_test_other_players_attacks_switch`: the tank's picture sorting with its
  rings above its body; every class's sorting; the switch in Options, on by
  default; on, a wave and the rings; off, no slash, axe, stalagmite, meteor,
  stick or orb, the rings out at once and staying out; an unseen aura healing
  inside and by unseen blobs outside; on again, the rings back at once. The
  older picture test sets the switch on for itself and puts it back. Each was
  broken on purpose to see it fail.

### An attack with no cursor aims where you face (0.41.0)

Gary, playing in Chrome: "he can only attack left also with warrior", and the
owner: "he was using chrome so we need to think to the max to solve the
problem".

- **Reproduced in Chromium.** Every attack aims at the cursor - Space too - and
  a game that has never seen the mouse over it has the cursor at (0, 0), the
  screen's top-left corner. Playing from the keyboard with the mouse off the
  page, every swing went up and left, and the warrior's swing favours left and
  right on a diagonal (`swing_horizontal_bias`): `attackleft`, every time,
  whichever way he walked. The browser's own mapping was fine: a web export
  driven in Chromium at 100%, 125%, 150% and 200% scaling and windows from
  900x1000 to 2560x1305 aimed every click and Space exactly at the mouse.
- **The fix** (player.gd, THE CURSOR, WHEN THERE IS ONE): an attack aims at the
  cursor only while there is one on the game - it moved over the window or
  clicked it since it last left (`get_window().mouse_exited`) - and otherwise
  `KEYBOARD_AIM_REACH` (64 px) ahead the way the character faces. `aim_point()`
  is what every class asks: the warrior's swing, axe and ring, the mage's
  stalagmite, meteor, sparkle and ring, the tank's sticks and ring, the
  healer's orbs, aura and ring. `pointer_on_game` is static, so a new area's
  character does not forget a mouse still over the game. A still cursor is not
  news (`_watch_pointer()` compares frames); a click always is. Measured after,
  in Chromium: walk right, down, left, up, Space - `attackright`, `attackdown`,
  `attackleft`, `attackup`; the mouse on the game wins; the mouse leaving the
  page hands it back to the keyboard.
- **The web build on the site was 0.21.2** (`builds\web`, exported 11 Oct), so
  a browser player was nineteen releases behind everyone else. Hence build 5
  (below): set the minimum once 0.41.0 is uploaded.
- `_test_attacks_aim_with_no_cursor`.

### The finisher, uncluttered (0.41.0)

The owner: "warriors critical attack is overlapped it looks bad". On the third
swing the gold wave, its fan riding over it from its middle, the sword's fan
off the blade, the weave and the burst all landed in one place.

- The finisher flings **no sword fan** (`_on_frame_changed()`: its fan is its
  wave's), its wave **weaves nothing** (slashwave.gd), its **fan leaves from
  the crescent's tips** - `finisher_fan()`: each orb `FINISHER_FAN_TIP` (28 px,
  past the crescent's half-width) out on the side it flies to - and **the burst
  starts at the monster's edge** (`SlashWave.BURST_FROM`, 10 px), not its
  middle. Somebody else's finisher is drawn the same, whatever an older game
  flags. The numbers are unchanged; the server's bound counted a sword fan on
  the finisher and still does, which only leaves it higher than it needs.
- **One crescent, no glow behind it (0.45.1).** The owner, after all that:
  "still double layerd". The glow behind the gold wave was a copy of it 1.15
  times as big, added, grown from the middle of its 64-pixel picture - and the
  crescent sits 15 to 24 pixels off that middle, so the copy landed about 6
  pixels ahead of it as a second, paler crescent. It is gone (slashwave.gd,
  `_dress()`): gold, 1.35 times as big, unshaded, and nothing else is drawn
  with it. The suite asks for exactly one picture on a finisher's wave. **A
  glow made by scaling a copy only works on art centred in its picture.**

### Other players: their aim ring and their health (0.41.0)

The owner: "i need to be able to see other players directional bar etc ... i
want players to see everything i see and everything i see players also see".

- **The state carries** `aim` (where the aim ring's ball points, whole
  degrees, stepped to `Presence.AIM_STEP_DEGREES`, 8, so a drifting mouse is
  not a new state ten times a second) and `hp` (health, whole percent). The
  presence server checks both and passes them on in every step and join
  (presence.py, THEIR AIM AND THEIR HEALTH) - **update the server first**; an
  older one simply drops them.
- **remoteplayer.gd draws** their aim ring - placed by asking their class's own
  scene (`class_ring()`: the same feet, size and line their game uses), under
  their body, under the same Aim rings switch, hidden while they die - with the
  ball swinging round to each new aim (`AIM_FOLLOW_RATE`) and brightening as
  they attack; and their health as a bar in the gap under their name, green,
  amber under half, red under a quarter. Taken as they arrive, not played back.
- **Build 5** (`Api.BUILD`, app.py `CURRENT_CLIENT_BUILD`): a build-4 game
  plays on but draws none of it. The owner panel's minimum makes everyone in an
  area draw the same.
- `_test_other_players_aim_and_health`.

### Parties: a Party window, party chat, and the map (0.42.0)

The owner: "we need to be able to start parties so we need a tab for parties",
and of what a party should do, "Party tab + members", "Party chat", "Party on
the map" - and "monsters on map also by element color". (Shared XP was offered
and not chosen.)

- **The server keeps the party** (app.py, PARTIES; test_parties.py). Two to
  `MAX_PARTY_MEMBERS` (4). Anybody with no party may ask somebody; the party
  is made when they accept, the one who asked leading it. The leader asks,
  removes and hands it on; anybody leaves; a leader leaving hands it to the
  longest there; down to one, it is gone. An invitation waits
  `PARTY_INVITE_SECONDS` (120) and is asked, never imposed. Routes:
  `GET /api/party`, `POST /api/party/invite`, `respond`, `leave`, `kick`,
  `lead` - each answers with the whole party again.
- **Party** (src/systems/party.gd, class_name): the party you are in - id,
  leader, members - from the broadcast poll's `party` (`_own_party()`) and from
  every Party window answer. Static and per login (`kept_for`): a new login
  never sees the last account's party. `revision` moves on each change, so a
  name drawn from it knows to repaint.
- **The Party window** (Social > Party; partypanel.gd, a PanelWindow): each
  member's class, level and area (or "away"), a LEADER mark, and a health bar -
  yours from your own character, a member in your area from their picture
  (0.41.0's health in the state), anybody else from their last save - read
  again every `REFRESH_SECONDS` (3) while open. Join and No for an invitation;
  Lead and Remove for the leader; an invite box while there is room and you
  may ask; Leave. **Invite to party** is on the players list's right-click
  too. An invitation lights Social > Party with "pamy invited you to their
  party. Open Party to answer." (`_read_asks`, kind "party").
- **Party chat**: the chat window's Party tab. The server's `party` channel is
  stamped with the party's id like guild chat, so a line said in one party
  never shows in another, nor to somebody who left; the poll's `chat_news`
  lights the Chat button for it.
- **Their names in the party's colour** (`Party.COLOUR`), over their heads
  (remoteplayer.gd `_paint_plate()`, repainted on `Party.revision`).
- **The map** (mapscreen.gd, MONSTERS AND YOUR PARTY): every monster still
  alive on ground you have explored, as a dot in its element's colour
  (`Element.colour_for`; a boss bigger) - not through the fog, which would
  draw the map you have not found - and everyone in your party standing in
  this area as a ring in the party's colour with their name. Only this area:
  the presence server tells a game about its own area, and the Party window
  says where the rest are.
- `_test_parties`, and the window lists that hold every window, the Social
  dropdown, the players menu and the chat channels.

### Party voice, and a name clicked anywhere (0.43.0)

The owner: "I really really want the option for voice chat in game for
parties ... could even be a flappable switch", and "clicking over a person
should have add friend inv to guild or party and report button that syncs to
our mod/dev/owner same thing in chat if i hover over some ones name". Asked
how voice should be built, he chose "Browser voice + Cloudflare TURN".

- **Why the browser.** Godot's WebRTC carries data, not sound, and has no echo
  cancellation. The browser's calling has the microphone, Opus, a jitter
  buffer, echo cancellation, noise suppression and gain. So on the web the
  game hands the call to it: `VoiceBridge.SOURCE` (src/systems/voicebridge.gd)
  is JavaScript put into the page once as `window.elusionVoice`; the bridge
  calls it. **No backslash in that JavaScript** - it sits in a GDScript string
  (the suite checks), and **no method named like an Object method** (`call`,
  `connect`, `set`, `get`): `dial`, `hear`, `status`. Off the web there is no
  bridge, and the switch says voice is in the browser version.
- **A mesh through a relay.** One call per other member (a party is at most
  four), every one through the TURN relay the server names, with
  `iceTransportPolicy: "relay"` - nobody sees anybody's address. The server
  hands out short-lived relay credentials (`GET /api/party/voice`, only to a
  party member) made from its own TURN key; only `ELUSION_VOICE_DIRECT=on`, for
  a test on one computer, says "all".
- **Who calls whom** (presence.py, PARTY VOICE): a game in voice says so
  (`{"t": "vs", "on": true}`); it is told who is already in (`"in"`) and calls
  each (`dial`); they are told it came (`"join"`) and wait for its call. So of
  any two, exactly one calls. A call's setup goes over the presence socket
  (`"vc"`), which passes it only between two in voice in the same party.
  **Every meeting is a new call**: somebody already known saying they joined
  again (their link dropped) is hung up first and calls anew.
- **Voice** (src/systems/voice.gd, an autoload after Presence): the switch,
  the relay, the microphone (`MODE_OPEN`, or `MODE_PUSH` on **Push to talk**,
  V), **Mute my microphone** (B) - both rebindable on the Controls card - each
  other voice's volume, who is speaking (`speaking()`, the page's loudness
  over `SPEAKING_LEVEL`). Mode, mute and volumes are kept in
  `user://voice.cfg` (`Voice.path`). Off by itself when the party goes, when
  the server says so (`"off"`), or the browser refuses the microphone; the
  window losing focus lets go of push-to-talk.
- **The Party window**: Voice switch, Open mic / Push to talk (with its key),
  Mute, a line saying why voice is off or how to talk, and Voice settings
  (below); for each member in voice a speaker that lights while they talk.
  **Over their heads**, a lit speaker beside the name while they talk
  (remoteplayer.gd `TalkMark`).
- **A name, clicked** (src/ui/players/playermenu.gd, `PlayerMenu`): the name
  over a player in the world is a button now (the plate takes the click, so it
  never swings) and opens the HUD's player menu (group `player_menu_host`,
  `open_player_menu()`); the Players window and a chat name show the same
  items - Whisper, Add friend, Trade, Invite to party (not for somebody in
  yours), Invite to guild, and Report with a reason. Chat keeps "Report this
  message" for a line; a hovered chat name is underlined under a pointing hand.
  Each item goes where it already went (`CharacterHUD.player_action()`).
- **Report a player** (`POST /api/report/player`): a `chat_reports` row with
  channel `player` and a negative `message_id`, so it sits on that player's
  card on the staff Reports tab, counts in the badge and closes with the same
  buttons; the staff card says "the player" and does not quote it.
- `_test_names_open_the_player_menu`, `_test_party_voice`. The browser side was
  run for real: two exported game clients in Chromium with fake microphones,
  logged in, in one party - both in voice, the call connected, sound both
  ways, the mute key silencing one, and the party ending turning voice off.

### Voice settings (0.45.0)

The owner, on the Party window: "add a settings for it in that menu so players
can adjust voice volume". He chose all four: voice volume, microphone volume
with a level bar, open-mic sensitivity, and the noise and echo switches.

- **Where.** Voice settings, under the switch, swaps the member list for the
  settings (`show_settings()`, `settingsscroll`) and Back to the party swaps it
  back; out of a party it goes back by itself. Everything can be set with voice
  off. Each member's volume moved here from their row, so a member's volume can
  be set before they join voice (`volume_<name>` sliders under EACH PLAYER).
- **Voice's numbers** (voice.gd, all in `voice.cfg`): `voices_volume` and each
  `volume_of()` to `MOST_VOLUME` (200%); a call plays at `heard_volume()`, the
  two multiplied and held to 200%. `mic_volume` to 200%. `sensitivity` 0..1 of
  `GATE_TOP` (0.3 loudness), which is also the level bar's width, so the line
  on the bar IS the slider; `gate_level()` is 0 for push to talk. `echo_cancel`
  and `noise_suppress`, on unless the file says false. A file with junk in it
  reads as the defaults (`_number()`, `_switched_on()`).
- **Given to the page before `start()`**, so the first word is already at the
  right volume, through the right gate, with the right cleaning.
- **The page** (VoiceBridge.SOURCE, version "2"): the microphone goes through
  the page's own audio - its gain, then the gate - into a track every call
  sends (`buildMic()`); the noise and echo switches open a new microphone and
  put it in at the start of that chain, so no call is renegotiated. A voice at
  or under 100% is the call itself, at that volume; **over 100% it is made
  louder in the page, through a limiter, and played through a call to itself**
  (`loopback()`), because Chrome's echo cancellation only hears audio a call
  plays (issue 687574) - boosted straight to the speakers, a voice would come
  back to its owner as an echo. Each call also plays into a muted element
  (`sink`): Chrome gives the page's audio nothing from a call no element is
  playing, and the speaking light and the boost read it. The gate looks every
  20 ms, stays open 350 ms after the last loud moment, and opens fully while
  the page is hidden (timers slow down there). `levels()` adds `mic` (the
  level whether or not it goes out), `gate`, and what the browser actually
  gave for `ec` and `ns`.
- **Run for real in Chromium**: two pages, a speech-like test tone as the
  microphone, the code taken straight from voicebridge.gd: the call connects
  through the chain; mic at 0 is silence and at 200% louder; a sensitivity
  over the voice sends nothing and under it everything; 50% plays the call at
  half, 150% through the call to itself and louder (limited), and back under
  100% the call to itself is closed; noise and echo off gives a microphone
  without them and the call carries on; mute still mutes; a boosted call hung
  up leaves no element behind. 19 of 19, and again under the normal autoplay
  rules (after a click, as the Voice switch is).
- `_test_voice_settings` (28 checks), and `_test_party_voice` updated.

### Token lifecycle: which copy of the game, the password again (0.44.0)

Students reviewing the project named one missing defence: "token-lifecycle
hardening through rotation, short lifetime, binding, revocation, and secure
storage". The server does the work (TOKEN LIFECYCLE in app.py, the API's
CLAUDE.md and `test_tokens.py`); this is the game's half, held by
`_test_token_lifecycle()`.

- **Build 6 sends `X-Elusion-Install`** - `install_id()`, the random id in
  `user://install.cfg` - on every request, from all four header builders
  (`_request_once`, `post_bytes`, `get_bytes`, `send_before_leaving`). A login
  from build 6 is bound to it: the same token without it, or with another
  copy's, is theft, and the server ends every session on the account. **A new
  header builder stamps both headers**, or every request through it signs the
  player out as stolen. The suite counts them.
- **Step-up.** `_request()` wraps `_request_once()`: a 403 with
  `confirm_password` calls `Api.confirm_handler` with the server's words,
  sends what was typed to `POST /api/auth/confirm`, and sends the request again
  once. Cancel ("") sends nothing more and the 403 is the answer; a wrong
  password is the confirm's own 403 ("That is not your password."), and the
  request is not resent. Never for the confirm itself, and never for a 403
  without the flag. `post_bytes` and `get_bytes` do not step up - no step-up
  route is reached through them.
- **The HUD is the handler** (`characterhud.gd` `_ready()`:
  `Api.confirm_handler = Callable(self, "ask_password")`). `ask_password()`
  puts a `PasswordPrompt` (src/ui/passwordprompt.gd) up as the HUD's last
  child, one at a time, and returns what was typed. At the login screen there
  is no HUD, the Callable is invalid, and the 403 is the answer.
- **What an ended session says** (`signout_notice_for()`): `token_stolen` -
  sign in again, change the password if it was not you; `staff_session_ended`
  - 12 hours, half an hour away; `old_login` - the game was updated. A
  remembered login refused on reopening says the first and last of those on
  the login screen too (`probe_and_resume()`'s `notice`).
- **Plain `http://` only to this computer.** `_clean_base_url()` ignores an
  `http://` override that is not `is_this_computer()` - exactly `localhost`,
  `127.x.x.x` or `[::1]`, never a name that begins like one, a login part
  (`localhost:80@evil.example`) or `name.localhost` (a desktop game asks DNS).
  A browser page keeps its own origin, http or not (`web_base_url()`): it came
  over that connection.
- **It switches on with the minimum build.** Until the owner sets it to 6 on
  the Server tab, a build-5 game plays as before. At 6, every login made
  before is ended once (everyone types the password again).

### The stirring lands (0.46.0)

The owner: "lets build it in my game if you think it will elavate it" - a
world that changes on its own - and of its effects, "just make those switches
in my gm panel under a new tab that can be adjusted". Every 3 hours (the
owner's setting) one of the seven lands, an element from DARK to WATER, stirs.
The server's side is in the API's CLAUDE.md, "The stirring lands".

- **Who does what.** The server picks the land, announces it (broadcast kind
  `world`) and pays the more-loot and more-XP itself at the kill. The game
  applies the rest: a hit of the stirring land lands harder, and resistance
  to it counts for more - in `Player.damage_taken()`, still held to
  `RESIST_CAP`; its monsters have more health and move faster (BaseEnemy).
  Defense XP is still trained on the hit as sent. Players' own damage never
  changes.
- **It has to be felt.** The owner's first try: "i did not notice dps change
  on enemies or anything" - only one land's monsters in seven change, and
  +25% on a hit of 12 is 15. So the stirring land's monsters stand in a
  pulsing glow of its colour (`StirGlow`, src/enemies/stirglow.gd, the
  monster's first child), have +50% health and move +15% faster, a hit they
  made harder is drawn 1.4x bigger (`Player.STIRRED_NUMBER_SCALE`), and
  switching the lands off gets its own banner ("THE LANDS GROW STILL").
- **Health: raised once, never lowered.** A monster born while its land
  stirs is born with it (`BaseEnemy._ready()`, `Lands.raised_max_hp()`); one
  already standing when the stir begins gets the extra added to its maximum
  and to what it has left (`raise_for_stir()`, on `Lands.changed`). Never
  taken back: the combat books count a death at the health the leader's game
  sent, and a monster lowered under that would die before they agreed. A
  follower's copy told of more health than it knew takes the leader's word
  (`net_apply_state()`).
- **Speed** is `stir_speed()`, multiplied into every velocity BaseEnemy and
  BushMage set from `get_move_speed()` or `get_flee_speed()` - the overrides
  stay what each monster is.
- **`Lands`** (src/systems/lands.gd, an autoload) holds what the broadcast
  poll's `"world"` said (`characterhud.gd`, `_read_world()`), every number held
  to its range, and answers `hit_scale()` and `resist_scale()` - 1.0 for every
  other element, and for everything when nothing stirs. **A stir 60 seconds
  past its end is over** (`STALE_SECONDS`), whatever was last heard: a server
  that cannot be reached never makes the game harder. The countdown runs on
  the server's clock (`now` in the payload).
- **On the HUD**: a line under the top of the screen ("The Fire lands stir -
  2h 14m left") in the land's colour, under the status strip when that is up;
  a new stir while playing gets the mythic banner in that colour, saying what
  it does - but not on the first poll, which is history. The world is read
  before the poll's messages so its announcement is coloured too.
- **The GM panel's World tab** (`WorldTab`, src/ui/owner/worldtab.gd; owner
  only, after Server): the master switch, hours per stir, each of the six
  effects' switch and amount (one to a row: two to a row needed amount boxes
  too narrow to show "1.75 x"), Save, a land and "Stir it now", what stirs now, the last stirs
  (and who stirred one by hand), and each land's hunting. Saving and stirring
  ask for the password again (step-up). **What each button did goes in the
  panel's Results box too** (`report`, set to `OwnerPanel._say`; 0.46.1, the
  owner: "i want refresh to say it in the results"): Refresh writes what
  stirs now and every setting (`settings_text()`), Save the settings the
  server now holds, and every refusal; "Saving..." stays on the tab
  (`_say_here()`), and opening the panel reads quietly. **Save and Stir it now wait until
  the server has been read**, and again after a read fails: unread, the
  controls hold their lowest values, and Save would send those. A 404 there
  means the server is from before 0.46.0, and it says so. Built narrow: the GM panel draws 370
  wide, and a wrapping label with no width set measures one word per line,
  which once made the panel 720 tall.
- `_test_stirring_lands` (54 checks); `test_world.py` (67) on the server.

### The aim held still while walking (0.46.1)

The owner: "when moving left and right that ball wobbles ... if my mouse is
not moving and the ball is wobbling means there is a tiny issue". It was:

- **Two clocks.** `get_global_mouse_position()` maps the cursor through the
  canvas transform of the last DRAWN frame - with physics interpolation on,
  the camera part-way between two ticks - and every aim is worked out on a
  tick, from this tick's `global_position`. 60 frames to 80 ticks is a
  four-tick beat: walking right with the cursor still, the ball's angle went
  -135.58, -135.47, -135.36, -135.69 and round again.
- **`Player.steady_mouse_position()`** keeps the cursor's place on the screen
  and puts the screen where the camera is THIS tick: the camera node's own
  `global_position` (it rides the player), held to its limits. Measured
  after: -135.0 every tick. `aim_point()` reads it, so every class's attack,
  aim ring and aura agree with it.
- **Not `Camera2D.get_screen_center_position()`**: on 4.6.1 it answers with
  the drawn, in-between centre too. Measured, not guessed.
- `_test_aim_holds_still_while_walking` makes the drawn frame lag on purpose
  and checks the cursor still lands on one point.

### Player stats on the GM panel (0.47.0)

The owner, after "they log in noone is here it is pretty discouraging": "build
this and add it in my gm menu as a button somewhere". The question it answers
is why new players leave, from rows the server already keeps (the API's
`playerstats/` package and its CLAUDE.md, "Player stats").

- **The way in**: a **Player stats** button at the top of the GM panel's
  Server tab (`OwnerPanel.stats_button`, made in `_ready()` like the World
  tab), which asks the HUD (`open_player_stats()`) - the save history's
  route. Out of the game it says so in Results.
- **The window** (`StatsWindow`, src/ui/owner/statswindow.gd and
  scene/ui/owner/statswindow.tscn): read on opening and by Refresh, with a
  picker for how far back a player signed up to count as new (7, 30, 90
  days). It sends `offset` from `LocalTime.bias_minutes_at()`, so the owner's
  days start at their midnight.
- **In words** (`report_lines()`, static, what the suite reads): the
  players, the new players' road (signed up, made a character, killed a
  monster, level 5, level 10, came back, still around a week later, minutes
  to the first kill), **the biggest drop** worked out here - the step that
  lost the most new players, the one to look at first - where the ones who
  stopped stopped (how long, how far, which area), day by day, the monsters
  most and least hunted, and the classes. add_text only: an area's name is
  the server's word.
- **A window the HUD owns**, so it is on `_escape_windows()` and freed with
  the rest; the suite's window lists have it (twenty-four windows then).
- `_test_player_stats_window`; `test_stats.py` on the server.

### World events (0.48.0)

The owner: "Treat events (double XP, double loot, forced stir, etc.) as their
own feature area with a clean public contract, not just 'some extra flags in
config.'" The server holds and pays them (the API's `events/` package and its
CLAUDE.md, "The world's events"); the game shows them and lets the owner set
them, with no build.

- **WorldEvents** (src/systems/worldevents.gd, an autoload beside Lands):
  the poll's `"events"` - `{events: on now, next: coming, now}` - read
  through `read_event()`, which drops anything that is not an event and
  holds what is to what the server allows (3x at most, a name of 40, a land
  of 7). `apply()` hands back the events that began since the last poll;
  `lines()` is the HUD's: "Double XP - 2h 14m left", "Next: Double Loot in
  1d 2h", by the server's clock, so an event is off the screen at its end
  before the next poll says so. **The multipliers are words**: XP and loot
  are paid by the server at `/api/combat/kill`, whatever this game believes.
- **The HUD** (`_read_events()`, called from `_apply_broadcast()` right
  after `_read_world()`): an `eventchip` under the stirring land's line (or
  where it would be), in `EVENT_COLOUR`; a banner for an xp or loot event
  that begins - not on the first poll, and not for a stir event, whose
  banner is its land's; broadcast kind `"event"` in chat in the same green.
- **The GM panel's Events tab** (`EventsTab`, src/ui/owner/eventstab.gd,
  added in `_ready()` like the World tab, read on every open): what (more
  XP, more loot, a land stirs), how much, whose monsters, when (Now, or a
  day and an hour and minute on this computer's clock - `start_time()`),
  how many hours, a name; the list of what is on and coming and the last
  that ended; Call off. Reports to Results with `[EVENTS]`. **Picker values
  are item metadata, not ids**: an OptionButton reads an id of -1 as "use
  the index", so the stirring land's -1 came back as 1, the dark lands. The
  day picker is one width all year (`DAY_WIDTH`, every weekday and month
  measured by the suite) and the hour and minute boxes hold two digits, so
  the tab fits the panel's 370. A calendar beside them since 0.51.0 (below).
- **Staff log**: kind `event`, the server's detail as the sentence.
- `_test_world_events`; `test_events.py` on the server.

### Events measured, and guarded (0.49.0)

The owner's two asks on top of world events: "dashboards that show, for each
event: XP/hour and gold/hour before/during/after; player count online vs time;
which events actually move the needle on 'empty world'", and "guardrails on
your event DSL ... or a dry-run page". The server holds all of it (the API's
CLAUDE.md, "Guardrails, the dry run and the event report"); the game asks and
shows.

- **The guardrails are the server's.** No kill is paid past 3x XP, 3x loot or
  6x the two together, events and the stirring land's own counted in, and an
  event that could pass them is refused when set - a 409 whose message the
  Events tab shows as it is. Nothing here works it out.
- **Dry run** (Events tab, beside Schedule; `EventsTab.dry_run()`): what the
  controls hold, plus `players` 20, to POST /api/world/events/preview. The
  tab says "Dry run: allowed - see Results"; Results gets the sentences
  (`dry_run_lines()`, static): allowed or why not, the most at once
  (`worst_text()` - "for every monster" when every land is the same, else the
  worst land's), warnings, and what 20 players might earn as usual and with
  it, from how many player-hours, and the most online at once in two weeks.
  Numbers short (`GameConstants.short_number()`). A schedule's `warnings` go
  to Results too.
- **Report** (beside the tab's status line): opens the **Event report**
  window through the HUD (`open_event_report()`, owner only; on
  `_escape_windows()` and freed with the rest - twenty-five windows now):
  `EventReportWindow`, src/ui/owner/eventreport.gd and
  scene/ui/owner/eventreport.tscn, read on opening and by Refresh.
  `report_lines()` (static) is the words: what moves the needle (each kind's
  average lift, finished events only), then each event - its verdict, and
  online, XP and gold an hour, who played and who signed up before, during
  and after. "-" is not known (before the counting began, or past the
  14-day kill log), never 0; "not yet after" for one still on.
- **The chart** (`OnlineChart`, src/ui/owner/onlinechart.gd, drawn in
  `_draw()`): players and everyone over the last 7 days from the report's
  `online` rows (`fill()`: a five minutes with no row is 0), events as pale
  bands, whole-number ticks (`ticks()`), the days at this computer's
  midnights, a legend, an end dot and number per line (`value_at()` - the
  number the line ends at), and a hover that snaps to the bucket the line is
  drawn at (`bucket_under()`) and says the time, both counts and the events on.
  Drawn the data-viz skill's way: one axis, hairline grid, 2px lines, text in
  text colours; blue #3987e5 and orange #d95926 checked for colour-blind
  separation and contrast on the #12161d surface.
- `_test_event_report`; `test_events.py` E-5 to E-7 on the server.

### The Lands window, and the next stir offered (0.50.0)

From a "Behavior Insights" idea the owner brought: per land, players, kills,
time since its last event, whether it is overfarmed, ignored or healthy; a
suggested next stir with a reason, weighing new players against veterans and
when lands are busy; accept or override on the GM panel. The server holds it
(the API's insights/ package and its CLAUDE.md, "The land insights").

- **The world's own pick changed on the server**: still the least hunted
  land, never the one that just stirred - but never one where a player under
  level 10 has a kill in the last two hours, while another will do. Nothing
  in the game decides it.
- **The World tab** says the next stir and why where the land's kills were
  (`WorldTab.next_text()`, from the world answer's `next`), and selects that
  land in "Stir it now": pressing it is accepting now, picking another is
  overriding. From a server before 0.50.0, the kills line as before.
  A **Lands** button beside Refresh opens the Lands window
  (`open_lands`, set by the panel, through the HUD).
- **The Lands window** (`LandReportWindow`, src/ui/owner/landreport.gd and
  scene/ui/owner/landreport.tscn; owner only, on `_escape_windows()` -
  twenty-six windows now): reads GET /api/server/insights on opening and by
  Refresh. NEXT TO STIR (`next_lines()`); EVERY LAND, THIS WEEK as a
  RichTextLabel table (`row_cells()`: today, week, players, new now, stirred,
  event - `ago()` - busiest hour in this computer's clock, status - busy,
  healthy, quiet, ignored); the notes (`note_lines()`, a rough read under 30
  kills); and the hours.
- **The hours** (`HoursChart`, src/ui/owner/hourschart.gd): players online by
  hour of the day, turned from UTC to this computer's hours (`to_local()`,
  `local_hour()` - half-hour zones too), as 24 bars with a hover, the axis
  topped at a whole player (`top_of()`), the busiest three said
  (`busiest()`, `LandReportWindow.hours_text()`), and "still counting" under
  three days. The data-viz way, like the online chart.
- `_test_land_report`; `test_insights.py` on the server.

### One event line for what pays, and an open tab told of a new build (0.50.1)

The owner's screenshot: "Double XP - 2h 59m left" twice on the HUD, two
events set in the same minute - "only 1 should display otherwise breaks the
logic". And after a web deploy: "can we build something to avoid the ctrl
f5".

- **The HUD shows the event that pays** (`WorldEvents.shown()`, which
  `lines()` and `apply()` use). The server pays the bigger of each kind, never
  the product (`kill_scales()`), so an event another of its kind outdoes is
  not shown (`outdoes()`): the other covers every monster it does (every
  monster, or the same land) and pays more; or the same and covers more; or
  the same of both and ends later; or ends together and was set first. Two
  stir events: the one that began last, as `forced_stir()` stirs it. One it
  hid comes up if it outlasts the one that hid it. A new event that only
  matches one already on (`pays_as_much()`) is no news - no banner for an
  event made to run on. The GM panel's Events tab still lists every one, to
  call off.
- **The server says so when one is set** (`warnings()`, on the 201 and in
  the dry run): "It overlaps Double XP: while both are on, a kill gets the
  bigger XP, never both, and the game shows only that one." Said, not
  refused - a second, longer one is how an event is run on.
- **Ctrl+F5 was never needed**: Caddy sends every file of the web build with
  `Cache-Control: no-cache` (checked on the live site, 16 Oct), so a refresh
  or a new visit asks about each file and gets the new build. What a deploy
  did not reach is a tab left open. **web/shell.html now tells it**
  (`watchForNewBuild()`): it notes the Last-Modified of index.pck and
  index.wasm as the engine starts fetching them, asks again (HEAD,
  `cache: 'no-store'`) every five minutes and when the tab comes back into
  view or back from the browser's back-forward cache, and when they differ
  shows `#update` - "A new version of Elusion is out." - with Reload and
  Later (quiet for half an hour). The date, not the ETag: Caddy puts the
  encoding in the ETag. A reload unloads the page, which is the leave-save's
  cue (`WebPage.watch_leaving()`), so it is as safe as closing the tab.
  `window.elusionCheckForUpdate()` asks at once. Nothing in GDScript is
  involved, and a build from before 0.50.1 has no watcher: its tab needs
  the one refresh.
- `_test_world_events` and the loader checks in the export suite;
  `test_events.py` on the server. Tried in Chromium against a real export
  served the way Caddy serves it.

### The Events tab's calendar (0.51.0)

The owner: "i want to set a calendar in schedule that i can use to set
events for specific days". Nothing changed on the server: it already took
an event up to 60 days ahead (`FURTHEST`, `limits.days_ahead`), and the
day picker offered three weeks.

- **The day picker runs as far as the server takes one**
  (`EventsTab.days_ahead()`: the answer's `limits.days_ahead`,
  `DAYS_AHEAD` = 60 until it is read), and each day is counted from today's
  date (`EventCalendar.date_of()`), not in 86400s from now - a clock change
  in the weeks ahead used to be able to move a name onto the wrong day.
- **The calendar button** sits after the minute: a picture, because the word
  would have made the GM panel wider than 370 - that row is the tab's widest.
  Since 0.54.2 the picture is the Clockwork pack's book with the red bookmark
  (`EventCalendar.ICON_PATH`, the Magic stat icon) - it was a calendar drawn
  in code, and the owner wants his art only. Loaded, never preloaded; a clone
  with no pack shows "Cal" (`ICON_WORD`), which still fits. It opens a
  **PopupPanel** under itself (so the panel keeps its size, and Escape or a
  click outside closes it) holding `EventCalendar`
  (src/ui/owner/eventcalendar.gd): one month, Sunday first (`month_cells()`,
  `days_in_month()` - 2000 and 2028 leap, 2100 not), < and > from this
  month to the one with the last day offered; days before today or past
  the last disabled; **today a warm fill, a day with an event a green edge
  and green letters**, its tooltip each event with its hours that day
  (`marks()`: "Double XP 14:00-17:00", 00:00 and 24:00 across midnight,
  "all day"). Pressing a day picks it in the day picker
  (`_on_calendar_picked()`), closes, and says "Day picked: ..."; the hour
  and minute are still the owner's. Reopened, it shows the picked day's
  month with that day pressed in.
- **Style a cell once it is in the grid** (`_edge()`): before that,
  `get_theme_stylebox()` answers with the engine's default button - no
  border - not the GM panel's, and the copy drew a cell with no edge at all.
- In `_test_world_events`, the Events tab part.

### The whole calendar, a year ahead, days in hotbar boxes (0.52.0)

The owner, of the first one: "can we make it a real calendar that updates
with the years etc?" - it went from this month to the one holding the
sixtieth day, and never reached a new year - and "also i want to use
hotbar boxs for the outline on those days".

- **Any month of any year** (`EventCalendar.month_after()`, held to 1970 and
  2199): << and >> a year, < and > a month, **Today** back to this month
  (disabled on it). The month and year come from the date, so December
  2026 is followed by January 2027. Past months are there to read, none of
  their days offered.
- **A year ahead, on the server** (`FURTHEST` = 366 days, so the same date
  next year is always in; `limits.days_ahead` says so and the game follows
  it, `DAYS_AHEAD` = 366 until it is read). `MOST_WAITING` is still 20 on
  or coming at once.
- **The day picker still lists sixty days** (`DAYS_LISTED`); a day pressed
  on the calendar past them joins it as one more item with its year,
  "Nov 11 2027" (`far_name()`, `far_day`, kept through every refill) -
  measured, like the weekday names, to fit the picker's one width.
- **Events marked are the schedule answer's** (`EventsTab.on_calendar()`):
  on, coming, and over in the last 30 days - "(over)" in the tooltip, the
  box dimmed on a past day - never one called off.
- **Hotbar boxes**: a day with an event is drawn in the theme's
  `ButtonSocket` (the hotbar's art/images/hotbarslot.png, nine-sliced at
  7 px, lit on hover, darker pressed, dim disabled; `socket_style()`), its
  content margins brought in for a number and drawn 4 px past the cell at
  the sides and 2 at the top and bottom - the art's clear rim, which the
  hotbar hides by overlapping its slots - so the box is the cell's size.
  The GM panel's theme (staff_ui_theme) has no ButtonSocket, so the styles
  are taken from rpg_ui_theme.tres itself. Event days have green numbers;
  **today's number is gold** whatever is on, on a warm fill when nothing is.

### On a phone: the touch pad (0.53.0)

The owner: "make the game mobile", and of the ways to, "Phone browsers
(Recommended)". Phase 1 is "playable on a phone"; the windows by touch and
text sized for a phone are the next two.

- **Everything is played through input actions** (move_*, sprint, attack,
  interact), so a phone presses the same ones. **TouchControls**
  (src/systems/touchcontrols.gd, an autoload) holds what the thumbs are doing
  and, once a physics frame and before any other node's
  (`process_physics_priority` -1000), turns it into `Input.action_press()` /
  `action_release()`. The player, the shops, the bank, the fire, the fishing
  spot, loot bags and levers read the actions and cannot tell.
- **On at the first finger, off at a key** (`_input`): a key typed into a
  text box does not count (a phone's own keyboard sends keys), nor does the
  first finger's copied click (`InputEvent.DEVICE_ID_EMULATION`); a click
  from a real mouse does. Off lets go of every action it pressed.
- **The pad** (src/ui/touchpad.gd) goes on every HUD as its **first child**
  (`TouchControls.attach()` from `characterhud._ready()`), so every bar,
  button and window there is over it and takes a touch first. A floating
  move stick in the left 42% of the screen (it lands exactly where the
  thumb does and follows it past its rim; eight ways, `move_way()`), and
  round Attack above the hotbar: Use, Run (on for this run - ends as the
  thumb leaves the stick) and the healer's Aura (`touch_skill_name()`).
  Buttons answer by finger, so two thumbs are two presses. **Thumb-sized**:
  the sizes are CSS pixels (`thumb_scale()`: devicePixelRatio over the
  stretch, 1 on a laptop, about 1.85 on a phone held sideways, at most 2.4).
- **The first finger is a mouse too** (Godot's emulate_mouse_from_touch):
  that is what presses the HUD's buttons. The player takes no copied click
  (`_unhandled_input`), so a thumb on the stick is not a swing; **a finger on
  the world** - on nothing else - is an attack in TouchControls instead,
  whichever finger, aimed where it touched (`world_point_at()`, the cursor's
  rule), and a tap quicker than a frame still lands once and aims there.
- **The aim** (`aim_for()`, asked first by `aim_point()` while the pad is
  on): a finger on the world; the Aura or Attack button dragged; the nearest
  monster within AUTO_AIM_RANGE that can be hit (`BaseEnemy.can_be_aimed_at()`,
  its "bodyshape"); else the facing. The aim ring shows it.
- **Held, Attack keeps attacking** only where a second press is another of
  the same (`touch_attack_repeats()`: the warrior, but not with the Double
  Axe out; the mage), pressed again when the class is ready
  (`touch_attack_ready()`), so a held thumb walks no slower than clicking.
  The tank's (its aura's switch) is held like a key, and the healer streams.
- **Aura** drops as the thumb lets go: a tap at the healer's feet, a drag
  the way and as far as it went (`skill_point()`, `touch_skill_reach()`);
  the healer takes `skill_fired` as a right-click for that one frame.
- **A tap on a hotbar key uses it** (hotbar.gd, `_on_slot_touched()`: down
  and up on the key without the slide that drags it). **The Controls card**
  says what the thumbs do while the pad is on (`TOUCH_ROWS`).
- **The page** (web/shell.html): `#turn` asks for the phone sideways while
  it is upright (CSS, `(orientation: portrait) and (pointer: coarse)`), with
  "Play this way" for a tablet and, on an iPhone, Add to Home Screen;
  `#fullscreen` where the browser has a full screen to give, locking it
  sideways there; pull-to-refresh and the long-press menu kept off the game.
  `html/experimental_virtual_keyboard=true`: the phone's keyboard comes up
  for the login and the chat.
- `_test_a_touch_screen_plays_the_game()`, and the hotbar's and the
  healer's sections. Tried in Chromium as a phone (844x390 at 3x, touch)
  against a real export: login typed on the phone's keyboard, the stick,
  Run, Attack held, a finger on the world, Aura, the Controls card.

### The pad in the game's own art; a phone's battery (0.54.0, 0.54.1)

The owner, of the first pad: "i do not like the circles how can we elavte
those controls to be visually appealing", and "i also need to add a
brightness setting in options to reduce charge on battery also need to make
sure the game runs smooth on any phone".

- **The pad is the game's own art and the Clockwork pack's, nothing drawn in
  code** (touchpad.gd, 0.54.1). 0.54.0 shipped pixel icons and a stick ring
  drawn in code here; the owner: "i would prefer we do not use your art
  specifically we need to use my art only there is no shortcuts we can look
  at potential stuff from clockwork". So: each button is the hotbar's socket
  - art/images/hotbarslot.png nine-sliced at 7, as rpg_ui_theme.tres slices
  it, drawn 4 past the box for its clear rim - tinted with the theme's own
  ButtonSocket pressed and hover colours; the icons are the pack's stat icons
  (`ICON_PATHS`: attackiconcharacterstats, agility for Run, hp for Aura,
  inventorygold for Use); the stick is the same socket, as big as the stick,
  with the pack's gold coin for the knob (`KNOB_PATH`). **No art is made in
  this file** - the suite looks for Image.create, set_pixel and the draw_*
  shapes in it. **The pack is loaded, never preloaded** (`Art.picture()`): a
  clone has none, and a button there says its word in its socket. Squares in
  a block: Attack over the hotbar, Use to its left, Run over Use, the skill
  over Attack (`layout()`). **Whole screen pixels**: a socket's pixel
  (`art_pixel()`) and an icon's (`Art.texel_size()`) are each a whole number
  of screen pixels, so the edges stay as crisp as the hotbar's.
- **Brightness** (Options, `brightness`, 40-100%): a web page cannot turn a
  phone's backlight down, so Settings lays a black veil over everything
  (`_apply_brightness()`, layer 120: over the scene fades, under the owner's
  performance readout; it never takes a touch). On an OLED screen darker
  pixels draw less power. Gone at 100%.
- **Battery saver** (`battery_saver`): at most `SAVER_FPS` (30) a second -
  half the work. And **on a phone, no cap is `PHONE_FPS` (60)** - a 90 or
  120 Hz phone does not draw every frame twice. Both are `fps_cap_for()`'s
  (`saver`, `phone`). `Engine.max_fps` was measured working in a web build:
  60 holds 59.7-59.9 on a 60 Hz browser, 30 and 20 hold.
- **A phone's own defaults, once** (`PHONE_DEFAULTS`, `phone_changes()`): the
  first launch of this build on a phone sets Render resolution to 1280x720
  and Lighting to Simple - the two the PERFORMANCE section measured - and
  writes `[device] phone_tuned` beside the settings so it never does again;
  a player who sets either back keeps it. A phone is Godot's `web_android`
  or `web_ios` (`on_phone()`).
- **web/shell.html draws a phone at most two pixels to a CSS pixel**: before
  the engine loads, on a touch-first device, `devicePixelRatio` reads at most
  2 (`window.elusionPixels` says both). A phone's is 3 or more. Measured in
  Chromium as a phone (844x390 at 3x), in town, on software graphics: 3.1
  frames a second drawn as a laptop draws it, 6.6 at 1280x720 with the cap.
  Software graphics are far slower than a phone's; the ratio is the point.
- **Options grew to 681 tall**: Brightness and the Battery saver sit in the
  right column, which is the taller one on a computer.
- `_test_a_phone_saves_its_battery()`, the pad's own-art checks in
  `_test_a_touch_screen_plays_the_game()`.

### A finger held is the right-click; a phone kept cool (0.55.0)

The owner, on a phone: "looted a mage pet but is not deploying", "hotbar
icons are a bit small", and "major things i want to avoid phone over heating
and a image burned on the screen we need a slider for bullet projectile
brightness and make the game super user friendly on the tutorial screen i
think we should mention to players it would be a good idea to adjust
options".

- **Everything in a bag was used by a right-click, which a phone cannot
  make.** A pet, a potion, a sword, a piece taken off the doll - none of it
  worked on a touch screen. Now **a finger held still on a cell for
  `HOLD_SEC` (0.45) is that click** (inventoryslot.gd `_watch_hold()`): a
  tap is still the tooltip, a finger that slides past `HOLD_SLIDE` is still
  the drag, and a drag that began anyway (`gui_is_dragging()`) wins. In a
  loot bag or the bank, where the mouse takes an item with a double-click,
  the hold is the double-click. **Not on a hotbar key** - a tap uses one
  already (`holds_to_use = false` in hotbarslot.gd), and held it would be
  used twice. The pet's tooltip says "Hold it in your bag" on a touch screen
  (`ItemTooltip.use_line(data, touch)`), and the Controls card's touch rows
  say hold for the bag, Gear and a loot bag.
- **The hotbar is drawn at the pad's scale while the touch screen is in
  use** (hotbar.gd `fit_to_thumbs()`, `touch_scale()`): a key is the size it
  is on a laptop, grown up and left from its pinned bottom-right corner,
  never past `TOUCH_MOST_SCALE` (1.85 - its left end then still clears the
  stick's 42% of the screen). The pad lays out against the grown top the
  frame it appears (touchpad.gd `_process()`).
- **Projectile brightness** (Options, `projectile_brightness`, 30-100%).
  Every projectile is drawn unshaded, so in the dark they are the brightest
  things on the screen. A projectile is anything a script in
  `res://src/projectiles/` drives, and the large slime's lob
  (`Settings.is_projectile()`). Settings dims one **after its `_ready()`**
  (`_dim_projectile()`, deferred from `_on_node_added()` by the shot's id,
  so a remote player's orb is tinted first): its own modulate, which plain
  sprites under it take. **element_recolour and hearth_warm write COLOR
  without the modulate** - measured, a 0.3 modulate drew them at full - so
  each has a `brightness` uniform, set on the materials under a projectile
  and 1.0 for everything else drawn with them. The bullet field sets its own
  (bulletfield.gd `_shading`). Moving the slider redraws everything in the
  air (`_apply_projectile_brightness()`). At 100% and never moved, nothing is
  touched at all.
- **Screen rest** (`screen_rest`, on by default): after `REST_AFTER` (120 s)
  with no key, click, touch, mouse movement or stick, the veil drops to
  `REST_DIM` (0.82) and the game draws `BACKGROUND_FPS`; the next input wakes
  it at once (`Settings._input()` -> `note_input()`). The game goes on
  underneath - it dims, never pauses. The words on it move every
  `REST_WORDS_MOVE` seconds so they cannot burn in. A gap of more than 5 s
  between two of the one-second checks is the browser stopping the game, not
  a person idle. **The suite stops the rest watch** in its `_ready()`.
  Measured on the phone build: the water read 72 awake and 13 resting.
- **A phone's defaults come in steps** (`PHONE_STEPS`): 0.54.0's drawing,
  then 0.55.0's **Battery saver on**. `[device] phone_tuned` counts the steps
  taken (0.54.0's `true` is one), so a phone from 0.54 gets only the saver.
- **The welcome says to visit Options first**, with an **Open Options**
  button beside Got it (controlspanel.gd `options_requested`, the HUD's
  `open_options()`). Its lines are broken by hand like the directions: the
  card is as wide as its longest line.
- **Options is 713 tall**: Rest the screen in the right column, Projectile
  brightness in the left. With the password form open the left column is 614
  of the 616 a 720-high window leaves it - there is no room left in either
  column at this width. (Measured without Windows' Graphics API row: 702
  since 0.56.1, below.)
- **The page's Full screen button is a square** (web/shell.html): with its
  words it reached over the Bag's close button.
- `_test_a_finger_held_uses_an_item()`, `_test_the_hotbar_grows_for_thumbs()`,
  `_test_a_phone_stays_cool_and_unburnt()`.

### What you did is saved, a phone can do what a mouse can (0.56.0)

A bug hunt through saves, the touch screen, items and fights. The owner's
"looted a mage pet but is not deploying" was the start of it: 0.55.0 let a
finger summon the pet, and the summon was never saved.

- **A summon or a dismiss saves at once** (player.gd `summon_pet()` and
  `dismiss_pet()`). Before this, the pet was only saved along with the next XP
  gain, hit or step, so a pet summoned and then a door, or a closed tab, came
  back without it.
- **Every door saves the player as they stand** (scenetransition.gd
  `_capture_player()`, before the fade). The next area loads its player from
  the save slot, so HP regenerated, fog walked or a pet summoned since the
  last save was undone on the far side. **A closed tab does the same**
  (characterdata.gd `_on_page_leaving()` captures the live player first, as
  the desktop's close already did).
- **A pet the server refuses is put away** (serverstorage.gd `heard_save()`,
  `pet_refused()`, then `CharacterData.pet_not_held()`). The server clears a
  pet whose item is gone (sold, binned, traded, or lost with the bag) and
  names it in `ignored`. That answer used to be thrown away, so the pet stayed
  out until the next login. **A true death takes the pet with the bag** unless
  the bank holds its item (gameover.gd, `CharacterData.bank_holds()`).
- **A save belongs to the account that made it** (serverstorage.gd
  `_push_token`, `session_moved()`). A slow push still going when the next
  account signed in wrote the old character into the new account's slot.
- **Skill XP goes to the slot it was earned on** (skilltrainer.gd
  `_pending_user`, `_pending_slot`, `_set_aside`, `_claim()`). It was sent
  with whichever slot was playing at flush time, so the last twenty seconds of
  a warrior's defense went to the mage picked after Switch character. A batch
  that failed before a logout was sent by whoever signed in next; now another
  account's XP is forgotten.
- **No answer is not a refusal** (`CharacterData.got_no_answer()`,
  `resync_carry()`). A request that timed out may have gone through all the
  same: a purchase charged, gold banked, an item moved. The client showed the
  state from before it, so the player pressed again and bought twice. The bag,
  the shop, the bank and the bank's gold now ask the server again when a
  request gets no answer.
- **Items:**
  - Gear goes on from the bag only (equipmentslot.gd `is_carried()`). A sword
    dragged straight from the bank sent the bank's cell number.
  - The trash asks again when a stack grew while its dialog was up
    (trashslot.gd `changed_since_asked()`). A catch landing on the stack
    turned "Destroy x3" into four binned.
  - A trade box edited while a poll was out is sent when the window is free
    (tradepanel.gd `_offer_dirty`). Before, the box said 1, the server had 9,
    and Accept traded 9.
  - Cooking at a firepit you walked away from still updates the bag and the
    skill.
  - A potion dragged off its key while it was being drunk still heals.
- **A phone:**
  - **A thumb on the game gives the keyboard back** (touchcontrols.gd `played`
    and `played_now()`). The pad, the stick and a tap on the world end typing,
    so the phone's keyboard goes away.
  - **A quick tap on a player's name opens their menu** (`tap_name_at()`, from
    the stick's touchpad.gd as well). The Players list opens a row's menu with
    a tap on a touch screen.
  - **A finger held still and lifted shows the tooltip** of what is under it
    (`show_tip_at()`) in a box of its own, until the next touch or
    `TIP_SECONDS`. Godot's tooltips need a mouse resting on a control. A mouse
    move made in code is not enough: measured in the web build, the tooltip
    never came.
  - **Chat on a phone opens without the keyboard.** It stays awake until a
    thumb goes back to the game, then goes quiet. **Quiet, it passes touches
    through** (chatpanel.gd `_pass_touches()`), so the stick under it works.
    Chat on the bar wakes a quiet window, and a swipe scrolls the log (lines
    are PASS with selection off, `_suit_touch()`). The Friends and Players
    rows are PASS too, so a swipe scrolls those lists.
  - **Push to talk needs a key**, so a touch screen uses open mic
    (partypanel.gd `PUSH_ON_TOUCH`).
  - The Controls card's touch rows gained "See what something is: Hold it,
    then let go".
- **Fights:**
  - **A click down and up inside one frame is still a click** (player.gd
    `_left_click_came`). Every tap of a trackpad was missed, and so was any
    quick click at the battery saver's 30 frames a second.
  - **Pets and the healer's orbs skip what cannot be hit** (pet.gd
    `can_shoot_at()`, turretprojectile.gd `_enemy_in_reach()`): a boss still
    behind its gate, a slime splitting or dying (poisonslime.gd
    `can_be_aimed_at()`). A pet shot a caged boss for the whole fight.
  - **The healer's orb looks for its target on its first frame**
    (turretprojectile.gd `_seek_pending`). `_ready()` runs before the spawner
    sets the position, so the search started from the world's origin.
  - **The tank's aura charges a tick's mana when it goes on** (tank.gd
    `_activate_aura()`) and refuses with less. Toggling it every 0.45 s burned
    enemies for nothing.
  - **Pet orbs hit what they are already touching** when they start hitting
    (petelectricprojectile.gd, petfireprojectile.gd
    `_enable_hitting_after()`).
  - **The mage's shot has a lifetime** (magicprojectile.gd `lifetime`, 10 s).
    A shot aimed off screen flew until a wall stopped it.
  - **A loot bag from a kill answered in another area drops at your feet**
    (combat.gd `killed_in`), not at the old area's coordinates inside a wall.
  - A warrior killed mid-swing died at normal speed.
- `_test_what_you_do_is_saved_before_you_leave()`,
  `_test_a_phone_can_do_what_a_mouse_can()`,
  `_test_items_agree_with_the_server()`,
  `_test_fights_hit_what_they_aim_at()`, and the SkillTrainer and Players menu
  tests.
- **Not fixed yet:** holding a bag cell at the bank uses the item rather than
  depositing it (a drag deposits). Close buttons and window grips are small
  under a thumb. The server does not clear `active_pet_id` on a respawn (the
  client does). (All three fixed in 0.56.2, below.)

### The suite passes on the PC as it does here (0.56.1)

19 Oct: the owner's run on Windows failed four checks that a Linux run
passed. Each was the PC being measured differently, and each hid a real
fault.

- **Options fits a 720-high window on Windows.** The Graphics API row is
  Windows' alone (`rows_hidden_on()`), so the 713 measured on Linux was 746
  on the PC - past the 720, and Options scrolled at Normal. Both columns
  are 4 apart now, not 6, and Options is drawn 702 tall: the right column
  598 of the 616, the password form beside it, and the email form growing
  the window to 709. **The suite measures it with the API row shown**,
  whatever system runs it. A desk with more than one screen adds the
  Monitor row (628, a 12-pixel scroll at 720 high); a driver hint adds
  more. Both are past what two columns at this width can hold.
- **A presence socket that never opens is given up on** after
  `CONNECT_SECONDS` (presence.gd, 10 s), then tried again after
  `RETRY_SECONDS` like any failure. Nothing gave up before: Linux refuses a
  closed port at once, Windows knocks again for about two seconds, and a
  server that takes the knock and never speaks kept the game "connecting"
  for ever. The check uses exactly that - a `TCPServer` that listens and is
  never read - so it waits the same on every system.
- **A shot freed before its dimming came logs nothing** (settings.gd
  `_dim_projectile_by_id()`). The dimming is deferred, and a shot that hit on
  the frame it was made was handed over freed: "Cannot convert argument 1
  from Object to Object", 19 times in a Linux run. The id is looked up when
  the call comes, and `instance_from_id()` is null for one already gone.
- `_test_text_size_and_font()`, `_test_other_players_are_drawn()`,
  `_test_a_phone_stays_cool_and_unburnt()`.
- **The other lines in a run's log are the suite's own.** The unknown items
  (`nosuchthing`), the refused server overrides, `save_data()` with no user,
  the bank's "HTTP 0 no answer" and `attach_remote_slots()`'s missing entry
  are each a check provoking it on purpose and reading the answer. The
  leaked RIDs at exit are the ObjectDB line below.

### The three left over from 0.56.0 (0.56.2)

The "not fixed yet" list above, fixed.

- **A finger held on the bag deposits while the bank is open**
  (`InventoryContainer.held_is_double_click`, set by bankinventory.gd
  `_wire_carry_container()` for exactly as long as the bank's own
  double-click is wired). A double-click there is the deposit, a phone cannot
  make one, and the hold was the right-click - the potion was drunk on its way
  into the bank. With the bank shut a hold is the right-click again.
- **A window's × and edges answer a thumb** while the touch screen is in use
  (panelwindow.gd, UNDER A THUMB). A × was 14 CSS pixels on a phone held
  sideways and a grip 3. The × answers an invisible `THUMB_CLOSE` (40) CSS
  pixel square over it (`close_pad_rect()`): never below the header, never over
  another header button, reaching above and right of the window for what it
  cannot have there. The left, right and bottom grips and the bottom corners
  reach `THUMB_GRIP` (16) CSS pixels out past the edge and no further in; the
  top keeps a mouse's, and the right edge starts below the header. A mouse's
  sizes come back at the first key or real click. The × is found by name
  (`find_close_in()`: a button in the header whose name says close), and every
  window in `WINDOW_PANELS` is checked to have one. A window whose root clips
  (the chat's) keeps only the inside half of each.
- **The server's respawn puts the pet away** unless the bank holds one
  (death/routes.py, with carry/'s `owns_item()` handed in), in the same
  transaction as the bag, and answers `pet_lost` and the `active_pet_id` left.
  gameover.gd takes that answer; a server from before says nothing, and the
  game's own rule is kept for it. Before, a game closed before its next save
  came back with the pet out and no item to put it away with.
- `_test_a_finger_held_uses_an_item()`, `_test_windows_fit_a_thumb()`,
  `_test_what_you_do_is_saved_before_you_leave()`; on the API, test_packages
  and test_economy.

### A kill waits for the server's receipt (0.57.0)

SECURITY_NOTES E-3, step 2 (E3_SCOPE.md option C). The server has counted
every fight itself since 0.10.0 - its books (presence.py, combatbook.py) -
and still paid every kill on the game's word. With the owner's new switch on,
it pays a kill only when its own count agrees the monster died.

- **A 202 is "not yet", not "no"** (combat.gd `report_kill()`). The books
  hold a death a second for late hits and write it a quarter of a second
  later, about 1.3 s, and the game reports the kill the instant the monster
  falls. So `/api/combat/kill` answers 202 `{"pending": true,
  "retry_after_ms": 400}` until the receipt is there, and the game posts the
  same body again after that pause (`receipt_pause_ms()`, held to 100..2000
  ms) until a real answer or `RECEIPT_WAIT_SECONDS` (8) have gone. Then the
  player is told: "No live link to the server" when Presence is not open,
  otherwise "The server did not see that fight" (`receipt_gave_up_text()`).
  With the switch off the server never answers 202 and nothing changed.
- **Build 7** (`Api.BUILD`, `Combat.RECEIPT_BUILD`). A build-6 game reads a
  202 as a kill that paid nothing, so the server refuses it a kill the count
  has not backed (409) instead. Switch the receipts on together with Old
  versions must update at 7.
- **The switch is on the GM panel's Testing tab**, "Kills need the server's
  count" (ownerpanel.gd `_refresh_receipts()`, `_on_receipts_toggled()`):
  POST /api/server/receipts, owner only, the password asked again, not
  announced; `/api/status` says `kill_receipts`. Switching it on says to raise
  the minimum build while it is below 7.
- **Read the numbers first.** killwatch.py's receipts line says how many of
  the paid kills of the last days the books backed. If honest play is not
  nearly all of them, the switch stays off.
- **Seams**: `Combat.kill_post` (Api.post in the game) and
  `Combat.receipt_wait_seconds`. `_test_a_kill_waits_for_the_servers_receipt()`.

### The suite plays in a world of its own (0.57.1)

19 Oct, from the owner's lesson on test configuration: tests run in their
own world. The suite ran in the game's own user:// folder, so on the owner's
PC it read his options - with the text size at 1.3 and the Pixelify font in
options.cfg, nine of the GM panel's layout checks failed for nothing in the
code. And it wrote to those files; every value came back, but nothing proved
it would.

- **Before the first section the suite moves every file of the player's it
  could touch to one of its own** (testrunner.gd
  `_play_in_a_world_of_its_own()`): `Settings.path`, `Voice.path`,
  `Keybinds.path`, `PanelWindow.layout_path`, `ControlsPanel.seen_path`, and
  the login files `Api.SESSION_PATH`, `Api.DEVICES_PATH`,
  `Api.INSTALL_PATH` and the login screen's `remembered_path` (loginmenu.gd
  has no class_name, so it is set through the script). Each becomes
  `user://_suite_*.cfg`, is removed, and starts from the defaults. They
  were fixed names; they are `static var`s now, and nothing in the game
  changes them. The install id matters most: every login on the PC is
  bound to it, and a run that lost it would end them all.
- **What the game read at boot is put back too.** The autoloads start
  before the suite does, so a remembered login was already in memory - the
  owner's real token, which the login screen resumes when its checks open
  it - and a `server.cfg` could already have moved the address. The suite
  starts signed out (`Api.token`, `keep_signed_in`, the identity) at
  `DEFAULT_BASE_URL`, as on a machine that never ran the game.
- **And it is checked, not trusted** (`_check_the_players_files_untouched()`,
  the last section). The MD5 of every file in user:// that is not the
  suite's own (`_suite*`, `suite_*`, `test_*`; the logs folder left out) is
  taken at the start and compared at the end, and a file changed, removed
  or made fails the run by name. Its first run caught `install.cfg made` -
  the login files were not moved yet.
- **A new file in user://** needs a path the suite can move (a `static
  var`) and a line in `_play_in_a_world_of_its_own()`; the last section
  names it otherwise.
- The same rule as the API's suites and `ELUSION_DB` (test_isolation.py
  there checks every suite sets it first).

### Every hit flashes the artist's white (0.58.0)

The owner: "every enemy and player has hitflash made for the animations why
did we not use them?" - and of the fix, "im hoping will not cause issue with
the frames". The four classes, the boss and the poison slime were drawn with a
hitflash: the pose, the same pose as a solid white shape (93-99% the pose's
own outline for the classes, measured), the pose again. Played as an
animation it REPLACED whatever was running - the boss's cast cut off and the
boss frozen for good - so since then the game doubled the sprite's colour
instead, which leaves the outline and every dark pixel dark. Only the tank
still played its frames, cutting short whatever it was showing.

- **`src/shared/hitflash.gd` draws the artist's white on top of the frame on
  screen**: a Sprite2D child of the AnimatedSprite2D, its texture the
  sprite's current frame, drawn by `hitflash.gdshader` (every opaque pixel
  white; the alpha the frame's times the sprite's fade). It follows the
  sprite's `frame_changed`, `animation_changed` and every frame's
  `_process`, so mid-swing it is the swing, white. `HitFlash.flash(sprite,
  seconds)` starts or restarts it - one per sprite - and it frees itself,
  renamed out of the way first.
- **It never writes the sprite**: not its animation, frame, speed, modulate
  or material. So nothing keyed to a frame or to `animation_finished` moves,
  a placed tint is never lost, and nothing can be left half white.
- **Who flashes**: every monster (`BaseEnemy.play_hit_flash()`,
  `hit_flash_duration` 0.08), every class (`player.gd _play_hit_flash()`,
  0.15 scaled down by defence as before), and other players seen here when
  their health drops (`remoteplayer.gd set_bearing()`, 0.15) - every class,
  where only the tank's ever showed, as a body animation. The tank no longer
  plays its frames. The large poison slime's hitflash is its split, not a
  hit, and stays. `HIT_FLASH_COLOR` stays as the first beat of a death
  (DeathBurst).
- **The sheets**: only the classes, the boss and the poison slime have
  hitflash rows in the project. The bush archer, bush mage, fire sprite and
  electric sprite sheets have none (every row is idle, walk, attack or a
  projectile); they flash the same white, drawn from their own frames.
- `_test_a_hit_flashes_the_artists_white()`: the sprite untouched through a
  hit, the white following frame, animation and turn, one flash per sprite,
  gone after; the boss hit on every frame of its cast still casts to its end;
  all four classes; nothing plays a hitflash animation over a body; and
  others seen here. Rendered once under a real renderer: standing, the white
  matches the artist's own white frame.

### Dynamite costs a fifth of the tank's bar (0.59.0)

The owner: "not enough mana burn we need to account for level on equipping
and what stats are manageable at that level ... if players wanna spam they
can waste magic potions", and of the throws a full bar should give, "much
less then 10 ... if even 3 people have these weps could break the game if it
is too easy". At 3 mana a throw a level-22 tank (410 mana) had 137 throws in
a full bar, about a hundred seconds of throwing without a pause.

- **A throw costs the level's bar over `DYNAMITE_THROWS_PER_BAR` (5)**,
  rounded up (tank.gd `dynamite_mana_cost`, a getter over
  `dynamite_mana_cost_at()`): `PlayerStats.max_for()` of the class's mana at
  its level, before gear. 82 at level 22 (the Dynamite's own), 102 at 32, 132
  at 47; five throws a full bar at every level. Mana gear is not charged for:
  what it adds is spare, toward one more throw.
- **Then a potion.** Potions restore a fixed amount, so a Greater (260) is
  three throws at level 22 and two at 32. That is the trade the owner asked
  for, and it means a level up makes each potion worth fewer throws; the
  website's Boss Sim test holds it as its one known exception.
- **The ring a throw lights still burns nothing of its own**, and still goes
  out `DYNAMITE_RING_LINGER` (3 s) after the last throw. The aura key's ring
  without Dynamite is unchanged (2 every 0.5 s).
- The website's Boss Sim prices it the same way (`bosssim.js`
  `dynamiteCost()`), and its test reads `DYNAMITE_THROWS_PER_BAR` and the
  formula off tank.gd - ship the site with the game.
- `_test_the_mythic_weapons()`: 82 at level 22, five throws a bar at levels
  1, 22, 32, 47 and 99, the price climbing with the level, not with gear.

### The alcove skeletons (0.60.0)

**0.63.0 replaced the five profiles and the alcoves** with two kinds in the
crypt - the Skeleton Soldier and the Skeleton Elite (see "The crypt over the
Big Field" below). The sheet, the swing, the reach, no pet and the respawn
here all still hold; the Guard..Lord profiles and their numbers do not.

The owner, 19 Oct: "lets add skeletons" - Ahvassa's sheet - in "the 5 elite
alcoves", fighting by "chase and sword swing". One body
(`scene/enemy/skeleton.tscn`, `src/enemies/skeleton.gd`) and five profiles,
one per alcove: Guard, Warden, Knight, Champion, Lord, bands 1 to 5. Each
variant scene carries its profile, because a respawn rebuilds from the scene
file. `_test_the_crypt_skeletons()` (it was
`_test_the_skeletons_guard_the_alcoves()`) holds all of it.

- **The sheet** (`art/enemy/skeleton.png`, 64 px): groups of four rows -
  idle 8, walk 6, attack 8, one blank - facing right, left, down, up, top to
  bottom. Read off the skull (its eyes are on the side it faces); a sheet's
  order is the artist's, and the firesprite's is down, right, left, up. No death and no
  hitflash rows: it breaks up in a DeathBurst and flashes with hitflash.gd
  like any monster without them.
- **The swing lands on frame 6** (`SWING_FRAME`), the frame the sword is
  drawn widest in every direction, 0.6 s into the swing, against wherever the
  player is then - stepping back during the wind-up works. One blow a swing,
  `projectile_damage` of the profile. Shared monsters: the leader's blow goes
  out as "m", and a mirror's swing is only a picture.
- **Reach is measured to the player's BODY** (`Targets.body_point()`), not
  the origin: the tank's body is 8 to 46 px above its origin, and a skeleton
  south of a tank swung at nothing. It stands at `fighting_distance()` (reach
  less 8) of the body, keeping its formation slot's bearing - an outer-ring
  slot (44 or 64 px) is past a sword, so it is brought in.
- **Only a player's hurtbox counts among its Area2Ds.** The tank's `aura` is
  an Area2D on the players' layer, about 150 px wide, there whether lit or
  not. **The boss's `_land_swing()` still counts it**, so a boss swing hits a
  tank from about 100 px off to its side - not fixed here.
- **The bag is a find, not a jackpot**: always one, its one slot always
  filled (gear about 85% of the time), a potion half the time - and the slot
  rolls its tier exactly as the band's own monsters do (`tier_odds`), never a
  tier up. The first cut (60% its own tier, a 35% tier-up) made the Lord a
  legendary every other kill, every three minutes, where a dark-band player
  finds about one an hour, and gave the fire band legendaries; the API's
  `test_rewards.py` caught it. Now the Lord is a legendary about one kill in
  40, at most about half one more an hour for a player camping it.
- **Not `slots_are_gear`**: the server tells a boss by a gear-only bag
  (killwatch.py `is_boss()`, the API's "seven bosses"), and a skeleton must
  not be one to the books.
- **No pet**: `EnemyData.drops_no_pet` (new) exports `pet_odds` 0. Without it
  the tier table gave them pet odds with nothing to drop, which the suite
  fails on. The exporter refuses `drops_no_pet` with a pet named.
- **Back after three minutes**: `EnemyData.respawn_seconds` (new, 0 = the
  area's), read by the respawner's census (`respawn_time_for()`), never
  sooner than the area's. Ship the API's gamedata.json with it and update the
  server: the books only pay for monsters in the export.

### The Big Field, dressed and walled all round (0.61.0, 0.62.0)

The owner, 20 Oct: "go ahead and place because i cannot get the right sizes
for them to do it" - the walls and props of `art/floordecoration/floorwalls.png`,
in "the alcoves and edges", the walls and big pieces solid - and then "i
need walls around the whole map".

- **The sheet is not a grid.** Its pieces are every size (a wall run 101 x
  28, a pillar 17 x 30, a cage 27 x 49), so a TileSet source cuts them into
  16 px squares that match nothing - which is what the owner hit, and the
  half-made source (`sources/0`) is gone from the Big Field's tileset.
  **`scene/crypt/` already has every piece at its size**, its origin at its
  feet and its collision at its base; the Field and the boss arena use them.
- **To place more: drag a `scene/crypt/*.tscn` into
  `ysortworld/props/crypt/<group>`** (or any y-sorted node). Nothing to size.
- **Walls round the whole map (0.62.0), 502 pieces**, in the `walls_*`
  groups, laid from the ground layer's own edges: a cell with the void above
  is a north edge, the void beside it a west or east edge, a ledge row (atlas
  y 4) a south edge. North: wall runs, their foot on the floor's first open
  row - exactly where the navigation polygon starts, so monsters do not path
  into them - rising over the void behind. South: runs over the ledge,
  replacing its brown face. West and east: the 9 px side strips, inside the
  edge column (outside the navigation). Outside corners take the four corner
  pieces (`wallcornerback*` at the top, `wallcornerfront*` at the bottom);
  inside corners are closed by running the strip on to meet the run. Long
  north runs have a pillar every two, and each top alcove's doorway a pillar
  either side.
- **The furniture** (181 pieces): each alcove two candelabras, two cages, a
  skull pile, bones, skull poles outside its door; every field's corners
  stores, pots, graves, rocks or bones; the road lanterns in front of its
  walls and candelabras by the ladder.
- **It is dark like the Field**: `cryptambience` under `ground`, so the 35
  candles and lanterns light it and the player's own light comes on
  (player.gd turns it on in any scene with a CanvasModulate). Delete that one
  node to have the Big Field lit again.
- **Kept out of the fights**: solid pieces at least 14 px from every
  monster's spawn (18 from a skeleton's), never across an alcove's doorway.
  The furniture's solids sit in corners and against walls, inside the
  navigation, so a monster walks round one by its usual detour.
- `_test_the_big_field_is_dressed()` holds all of it: every edge tile has its
  wall, a walk over the floor from the arrival to every monster round every
  blocker, a light budget of 40 for a browser's frame.
- **0.63.0 laid it again for the crypt**: 1126 props - 866 wall pieces, 15
  doors, 245 pieces of furniture, 35 lights. The alcoves' furniture moved
  into the halls and chambers; the rules above are the same.

### The crypt over the Big Field (0.63.0)

The owner, 20 Oct: "skeleton rooms need to be much bigger lets double the
enemies in big field skeletons need a solid tier ... normal skeletons and
elite skeletons ... make the door bigger", the skeletons "on north" and the
south "for a new enemy i have not added yet". He chose Option B, "make sure
it is mathmatically measured out", saw the pictures before it was committed,
and asked for the elites' rooms bigger and more elites in them (3, then 6 a
chamber), and for a door to "close after player leaves proximity".

- **Measured on the 16 px grid, square over the fields.** Rows below are
  tile rows (row 0 is the old top edge; the crypt goes up to row -28 - there
  are no camera limits, so negative rows are fine):
  - **Five crypt halls**, each exactly over its top field's columns (14-41,
    48-75, 82-109, 116-143, 150-181): 28 x 19 tiles (hall 5 is 32 x 19,
    as field 5 is wider), rows -8 to 10 - top edge, 16 open, a 2-row ledge -
    with one void row between a hall and its field.
  - **Five elite chambers**, one over each hall's middle: 20 x 19 tiles (18
    x 16 open), rows -28 to -10.
  - **Four archways** join the halls across the 6-column gaps: 6 x 7, rows
    -3 to 3. No doors - the door art is front view only.
  - **The south wing**, under the bottom fields, the whole width: 168 x 17
    tiles, rows 117 to 133. **Empty on purpose**: the owner's next enemy
    goes there.
  - A 5-column passage through every wall that has a door, on the field's
    centre line.
- **15 doors** (`scene/crypt/door.tscn`, `src/world/cryptdoor.gd`, the
  owner's `art/floordecoration/cryptdoor.png` at 2x, 78 x 56 px): field to
  hall, hall to chamber, field to wing, in `ysortworld/props/crypt/doors`.
  **Press interact beside one** (its `reach`, 110 x 120 px) and the planks
  lift away and the gap opens; press again and it shuts. **It shuts itself
  half a second (`CLOSE_AFTER`) after the player walks out of its reach** -
  not if they step back in first, and never on a body: while a player or a
  monster stands in the gap (`gap_taken()`, layers 3 and 4) neither the key
  nor the timer shuts it, and it looks again every 0.25 s. Each is a lever to
  presence.gd (`levers` group, `Presence.tell_lever()`, `follow_pull()`), so
  everyone in the area sees the same door; the server already relays and
  remembers levers. All start shut, and monsters never open one.
- **Two skeleton kinds, one tier each**, on the 0.60.0 body:
  - **Skeleton Soldier** (`skeletonsoldier`): tier 3, 700 HP, 30 a blow,
    260 XP; an ordinary monster's bag. 16 in each hall, 80 in all.
  - **Skeleton Elite** (`skeletonelite`): tier 4, 1.25x the size (and its
    reach with it, `melee_range` 45), 3460 HP, 60 a blow, 1284 XP; always a
    bag, its slot always filled, a potion half the time, back after three
    minutes. 6 in each chamber, two rows of three, 30 in all.
  - Both roll loot exactly as the tier's own monsters do, no pet, and
    neither is a boss to the server. **The old five profiles' files are
    deleted** (`data/enemies/` and `scene/enemy/` `skeleton{guard,warden,
    knight,champion,lord}`).
- **Navigation**: the Big Field's polygon was baked again from every open
  floor cell, rooms and passages included. The doors are props, not holes
  in it: a monster follows a player through an open door (as far as its
  250 leash) and pushes against a shut one.
- **How it was made**: generated outside the repo from the ground layer's
  own tiles (the same tile rule the map was painted with), then checked by a
  walk over the floor. **To change it by hand**, paint the floor in the
  editor and move walls from `ysortworld/props/crypt/walls_*` - then ask
  for the navigation polygon to be generated again. **Do not press Bake
  NavigationPolygon** on `ground/navigationregion2d`: the polygon keeps no
  outline of its own to bake from, and it would come out empty.
- **Tests**: `_test_the_big_field` (366 monsters, the field bands),
  `_test_the_big_field_is_dressed` (with the doors shut the crypt cannot be
  walked into and the fields can; open, everything can; 15 doors; each hall
  and chamber furnished), `_test_the_crypt_doors` (the 2x size, the key in
  reach and out of it, the lever, a body stopped shut and through open, the
  shut behind a player who leaves, a step back in, a monster in the gap) and
  `_test_the_crypt_skeletons` (the two profiles and their tiers, where they
  stand, the fight, the Elite's respawn). The API's `test_rewards.py` holds
  the loot: a Soldier rolls as tier 3, an Elite as tier 4, neither a boss,
  an Elite never a legendary.
- **The owner's stress test, 20 Oct** (two videos, the warrior through field
  1, hall 1, chamber 1, hall 2 and chamber 2, 69 to 114 monsters awake):
  with V-Sync on, locked at 60 fps and not one hitch in 1,261 frames; with
  V-Sync off and no frame cap, 320 to 692 fps (its slowest second 3.13 ms a
  frame, a fifth of the 16.67 budget), not one hitch in 10,133 frames,
  physics at most 4.29 ms a tick of its 12.5, process at most 8.71 ms. The
  366 monsters fit with room to spare on his machine.
- **The crowd costs more than its size (measured 21 Oct, headless in the
  container, the stress switch, a stand-in player in hall 3):** 1x, 220
  awake, physics 1.3 to 1.5 ms a tick and 554 collision pairs; 2x, 435
  awake, 5.7 to 9.2 ms and about 2,000 pairs; 4x, 870 awake, 14 to 40 ms.
  Twice the monsters is four to six times the physics - something in a
  crowd is paid per pair, not per monster, and the pairs are the clue.
  First thing to look at when speeding the game up.
- **The owner's 4x run, 21 Oct** (1,464 monsters, about 340 to 430 awake,
  the warrior through field 3, hall 3 and chamber 3, killed by 24 elites):
  42 to 61 fps; in the biggest field fight 28 of about 150 frames hitched
  (25 ms or more); physics 4 to 10 ms a tick, worst 13.3 (over its 12.5);
  process (scripts + drawing) 8 to 20 ms, worst 20.3 - over the 16.67 frame
  on its own, so **at 4x the drawing and scripts run out first, not the
  physics**. Draw calls went from about 130 at rest to 1,118 in that
  fight, with the screen covered in the monsters' dashed range circles:
  every RangeRing (src/shared/rangering.gd) makes its own
  CanvasItemMaterial in `_init()`, so none of them batch - the lead for
  the speed-up. Nodes 30,900 (11,300 at 1x), memory 326 MB (199 at 1x).
  Container, headless, 8x (2,931 monsters, 1,780 awake in a hall):
  physics 17 to 36 ms a tick, process 23 to 32 ms.
- **Still open**: the boss's swing counts a tank's `aura` (see the 0.60.0
  note above), and the south wing waits for its enemy.

### Mixed tabs and spaces inside one indent is a parse error

Godot's parser rejects a line indented with tabs and then padded with spaces —
including alignment spaces inside a `const` table, which is where it is hardest
to see. This project is tabs only. Alignment *after* the first non-space
character is fine; leading whitespace must be tabs and nothing else.

## Traps on the server side

### Two requests sent together used to read the same old number

A warrior's slash wave that kills two enemies sends two kill reports at once.
The server read the character's XP for each before either wrote it back, so
one kill's XP was lost - six sent together banked 99 of 676. The game had
added up all 676 itself (combat.gd re-runs `gain_xp()` with each answer),
levelled up before the server did, refilled its mana, and the server's healing
check clamped that as a cheat. The same shape let a loot cell pay twice and a
purse be deposited twice. Every write route now takes the database's write
lock before its first read - THE WRITE LOCK in app.py, held by
`test_concurrency.py` - so nothing changes on this side: the game was right to
send them together.

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

- **`SOUNDS` in `audio.gd` is 36 empty strings and one path** (`teleport`).
  An unassigned id is a silent no-op by design. That is what lets the call
  sites exist now and the audio arrive later, one file at a time. The suite
  skips the registry until it is full and prints what is still empty.
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
- **The owner panel is bound to backquote, not a function key.** F1-F7 were
  `player.gd`'s debug keys when it was chosen (gone since 0.7.1) and F8 is
  Godot's own stop-the-project shortcut, which closed the game. It was Shift+A before that, which collided
  with normal play - `interact` is Shift and `move_left` is A, so interacting
  while walking left toggled it.
- **`Api.is_admin` is a compatibility alias, not a rank.** There is no admin
  rank; the ranks are owner > dev > mod > player. The server still sends that
  key, meaning "dev or above", because existing client code reads it. New code
  should read `Api.role` and call `Api.role_at_least()`.

## The larder, the smith and the crown's ledger (0.74.0)

The owner, 22 Oct: "we have a whole lot of materials and ways to expand cooking
in clockwork lets get those done use 5 agents sync back up into 1"; on what the
materials are for, "Cooking + a smith"; "i want to make recipes people can make
with the food also"; and of five ideas for the economy, "we need to do these
tasks also max power". One release, built by five agents in parallel against
one written contract and merged into one tree. Every icon is a whole 16 px cell
of the owner's Clockwork Raven sheet (`art/pack/materials/`, `art/pack/food/`,
`art/pack/smith/anvil.png`, the two baits in `art/pack/fishing/`) - nothing
drawn. `assetlicense.md` lists the new folders.

**What is new, in one place:**

| piece | where | what it does |
|---|---|---|
| 67 items | `data/items/materials/`, `data/items/food/`, `data/items/fishing/` | 22 smith materials (five ores, Royal Gold, seven essences, Old Bone, Cursed Skull, seven Beholder Eyes), 14 produce, 10 shop staples, 2 baits, 19 meals |
| item fields | `src/types/itemdata.gd` | `BuffKind` (MIGHT % damage, GUARD armour, VIGOUR max health, WISDOM max mana), `buff_*`, `recipe_ingredients` / `recipe_level` / `recipe_xp` / `recipe_mastery_level`, `bait_rolls`, `is_meal()`, `buff_text()` |
| drops | `EnemyData.material_drops` | per kill, rolled on the server beside the bag |
| numbers | `GameConstants.TEMPER_*`, `CERTIFICATIONS`, `PATRON_TITLES`, `DONATION_MINIMUM` | the smith, the four ranks, the patron titles |
| recipes | `src/ui/cooking/cookingscreen.gd` | the Fish / Recipes tabs |
| buffs | `src/systems/foodbuff.gd` (autoload `FoodBuff`) | the one meal in force, on player.gd's numbers and the HUD |
| the smith | `src/world/anvil.gd`, `scene/interactables/anvil.tscn`, `src/ui/smith/smithscreen.gd` | the anvil right of the shop; Temper and Royal Certification |
| patronage | `src/ui/kingdom/kingdomboard.gd` | Donate, titles on the board |
| live rules | `src/systems/economyrules.gd` (autoload `EconomyRules`) | the server's economy numbers, for the shop's prices |
| GM panel | `src/ui/owner/economytab.gd`, `goldflowchart.gd` | Gold flow, Rules, Canary |

**The server owns all of it.** The game shows; `/api/cooking/recipe`,
`/api/character/consume`, `/api/fishing/catch`, `/api/smith/*`,
`/api/kingdom/donate` and `/api/economy/rules` decide. See the API's CLAUDE.md
for the routes, the tables and the ledger reasons.

**Materials never enter the generic loot pool** (`droppable = false`). They
come only from `material_drops`, rolled per kill on the server; a kill whose
bag roll said no and whose materials said yes makes a bag of materials alone,
with no gold - a material must never be a reason for more gold to drop.
Plant monsters drop produce, slimes the ore of their land's tier, sprites
their land's essence, skeletons bones and ore, Beholders their eye and Royal
Gold.

**The large slimes drop nothing.** They never pay out a kill (they split into
the smalls, which do), so ore given to them could never roll. The plan gave
them 60% and it was found only as six warnings on every export; the exporter
now REFUSES material_drops on an enemy that grants no rewards.

**Meals.** A meal is a CONSUMABLE with no skill gate - anyone at its
character level may eat it, so a cook can sell them. One buff at a time; a new
meal replaces the last, a potion leaves it running. The buff is applied in
`player.gd`: `get_damage_multiplier()` (MIGHT, like a Fury amulet),
`_recompute_max_stats()` (VIGOUR, WISDOM), `armour_total()` (worn + GUARD,
what `damage_taken()` uses). Starting or ending a buff clamps health and mana
into the new maxima and never heals or kills (`refresh_food_stats()`, the rule
`refresh_gear_stats()` has). The consume answer's `food_buff` is adopted
BEFORE the heal, so a Vigour meal's heal fills the room it made. The buff is
read at login from the character payload, kept on the slot across Switch
Character, cleared on logout. **A new buff renews the presence ticket at
once** (`FoodBuff._take()` -> `Presence.renew_soon()`, as an equip does):
presence.py bounds every hit by the ticket, which otherwise renews once a
minute, and a Might meal eaten mid-fight would be read against the old one.

**Recipes.** The Recipes tab lists every `is_meal()` item by recipe level,
with have/need counted from the bag, a locked row below your cooking level,
Cook and Cook all (one request at a time, Stop to end a run). A meal may be an
ingredient of another (Shadowcap Soup takes Bone Broth; the Royal Banquet a
Sushi and a Tart). Burns follow the fish's curve from the recipe's level and
mastery; a burnt meal takes its ingredients anyway.

**Bait.** The server uses the best bait carried (most `bait_rolls`) and rolls
the catch that many times, keeping the best fish. `fishingspot.gd` counts every
bait before casting - it counted only worms, which would have refused a cast to
someone holding only a Lugworm.

**The smith.** Temper raises every rolled stat of a bag piece by
`TEMPER_STEP` (3) points up to `TEMPER_CAP` (115 = QUALITY_HIGH), never to a
Perfect; the resistance is unchanged; Perfect and fully tempered pieces are
refused. Tier 1-2 is anyone's; tier 3 needs a Journeyman, 4 an Artisan, 5 a
Master, 6 a Royal Smith. The ranks are earned in order, per character, with a
level, gold and materials; the Royal Smith asks for an eye from every one of
the seven Beholders. **Every essence is asked for somewhere** - the first rank
took only ice and water essence, so a Light or Wind Essence said "the smith's
certificates are paid in it" while none was; the first rank now takes the
first four lands' essences. The window's numbers are the server's quote.

**Patronage.** Gold given to the crown is burned (`donation`) and counts per
ACCOUNT over its lifetime toward Patron, Benefactor, Noble Patron and Royal
Patron, shown under the name on the board and with progress on the reader's
own line. Titles sit under the name, not beside it - the four figure columns
leave a name no room.

**The guild tag on the board finally shows.** It had `clip_text` and no width,
so it was given one pixel and every "[ABCD]" drew as a sliver - since the day it
was written. It takes its text's width now and the name clips first, which is
what its own comment always said.

**The economy's numbers live on the server** (`EconomyRules`, fetched after
login, falling back to the catalogue): the shop's buy and sell prices use them.
The owner changes them in the GM panel's Economy tab (co-owners read), beside
the gold flow (minted vs burned by reason, per UTC day) and the canary's last
hourly check with a Check now button.

**Tests**: `_test_the_larder_loads`, `_test_monsters_drop_what_fits_them`,
`_test_the_store_sells_the_larder`, `_test_the_export_carries_the_larder`
(data); `_test_the_cooking_window_cooks_meals`,
`_test_a_meal_buff_works_while_it_lasts`, `_test_the_catch_names_its_bait`,
`_test_a_tooltip_says_what_food_is_for` (cooking); `_test_the_anvil_stands_by_the_shop`,
`_test_the_anvil_opens_the_smith`, `_test_the_smith_tempers`,
`_test_the_smith_certifies`, `_test_the_board_takes_gifts` (smith);
`_test_economy_rules_on_the_client`, `_test_the_gm_panel_economy_tab`
(economy). Every check was watched failing with its fault put back. The
UI tests run against stand-in servers on a real socket, so they read JSON
floats where they sent ints, as from Flask.

**Things that bit while it was built:**

- `export472.sh` and `gfocus472.sh` copy g472's import cache, which has none of
  the new PNGs: every new item failed to load through them. A tree with new art
  must be `--import`ed and run on its own `.godot`.
- The standard warning scan misses scripts compiled before it raises the
  warning levels (ItemRegistry compiles ItemData at boot). A planted integer
  division in itemdata.gd passed it; setting the levels in a scratch copy's
  project.godot caught it.
- The wall-clock checks (the board's refresh inside a frame, the death
  bursts) failed under five agents' load on two CPUs and passed alone. Rerun
  before suspecting the code.
- **Play stuck on "Loading the world..." - a Godot deadlock (0.74.1, 0.74.2).**
  The owner's log stopped at the `[CHAR]` line: the town's background load
  (started at the login screen) never finished. 0.74.1 guessed at a stall
  that `load_threaded_get()` would clear, waited 3 s and took the town - and
  his next log said "still loading in the background after 3.0 s (19%) -
  taking it now", then nothing. That guess was wrong, and it is gone.
  **What it is:** Godot 4.7.2 deadlocks a background load when two worker
  threads load at once. Thread A compiles `elusion.gd` (the town's first
  file) holding the GDScript cache's lock; its
  `preload("res://scene/characters/warrior.tscn")` becomes a pool task; if
  thread B starts it first, A waits for B with the lock held while B waits
  for the lock to compile `warrior.gd`. 19% is inside the town's first file.
  Reproduced in the sandbox with one script preloading 300 small scenes: 4
  loading threads (Godot's default on 16) stuck 2 loads in 8, 14 threads 3 in
  6, ONE thread 0 in 28 and as fast; gdb on a stuck one showed one worker in
  the loader's sleep loop, one on a mutex, the rest idle. Nothing can finish
  such a load - every new script needs that lock.
  **The fix:** `project.godot` sets
  `threading/worker_pool/low_priority_thread_ratio=0.01`, so the game loads
  on one worker thread on any computer up to 100 threads (Godot gives loading
  the pool's size times that ratio, at least one). The editor's own pool is
  untouched (main.cpp gives it 0.75). `AreaRegistry.loads_in_background()`
  is false whenever more than one would load (`loader_threads()`), so if the
  setting is ever lost the game loads each area on the way in instead.
  Character select now waits by the frame while the load moves and, if it
  ever stops for `STUCK_SECONDS` (15), says "close the game and open it
  again" and logs it - never `load_threaded_get()` on a load that has
  stopped. A two-core sandbox always had one loading thread, so its suite
  never saw this; `_test_one_thread_loads_in_the_background` holds the rule
  as numbers. **Do not edit `[threading]` in the Project Settings.**
- `art/pack` is a submodule: `tools\ship.ps1` now ships it (`SHIP_pack.txt`)
  BEFORE the game, putting a detached pack back on main when that loses
  nothing, so the game's commit records a pack commit GitHub already has.

## Windows snap to their text (0.75.0)

The owner, 22 Oct, with a screenshot of the smith's Royal Certification tab
and a hand's breadth of nothing under its last row: "I need ui to snap into
correct sizing when someone adjusts font size, some people have a hard time
seeing. we need to adjust the sizes".

**A window grew and never shrank.** PanelWindow grew a window to fit what it
held and left it there, so whenever its content needed less - a smaller text
size, a shorter tab, a wrapping line that measured tall for one frame before
it had a width - the room stayed, empty. Measured on 0.74.2 with every
window opened at Largest and set back to Normal: 16 of 27 were left bigger
than they open at Normal (the smith 164 px, Controls 257 x 181, Equipment
79). And three opened taller than drawn for good - Players, Kills and Party
at the full 720 - from that one tall frame.

**Now a window is its natural size** (`PanelWindow.natural_size()`): as its
scene drew it (`_authored`, read at attach), or what it holds if that needs
more. It follows that both ways whenever what it holds changes, a frame
after it opens, and on `snap()`. The top left corner stays; `_fit()` keeps it
on the screen.

- **A window the player resized by hand keeps its size** (`hand_sized`, set
  when a grip is let go) and only grows. A text size or font change forgets
  it - that size was for the old text - and `panels.cfg` says so (`sized`).
- **A `panels.cfg` line from before 0.75.0 has no `sized`** and is taken as a
  place, not a size: those sizes were mostly the old rule's leftovers.
- **An empty Label keeps the height of its old text size** (Godot 4.7.2: at
  12, 18, then 12 it still asks for 26 px, not 17), so every window with an
  empty notice line stood a line too tall after the text shrank.
  `Settings._scale_text_of()` gives it a text and takes it away.
- **The smith widens with the text** (`VIEW_WIDTH` 372 times
  `text_factor()`): at 408 across, Largest wrapped every line and the
  Certification tab stood 947 tall on a 720 screen with its header and x off
  the top. Its ranks are in `rankscroll`, fitted by `keep_scroll_fitted()`:
  all shown while the window fits, scrolled when it cannot. `_fit_and_centre()`
  never puts the window above the top.
- **The cooking window's meals list** refits when its rows change size
  (`recipe_list.minimum_size_changed`): opened at Largest and set back, it
  kept five Largest rows of height, 92 px too tall.
- **The suite's every-window check was blind to content**: it opened each
  window bare, so the smith with no ranks loaded passed at Largest. The
  smith and the cooking window are now checked with their content.
- `_test_windows_snap_to_their_text` holds it: every window Largest and back
  is its natural size; the rule on a built window; hand sizes; the old
  `panels.cfg` lines; the smith at Largest on the screen and scrolling; the
  cooking window back to its size; an empty line. Seven sabotages, each
  caught.

Measured with a throwaway harness that opens all 27 windows under xvfb at
each text size, in the standard font and Grenze (the tallest), and prints
each one's rectangle against what it needs.

## A crowd sixteen times over, and other players' attacks in the tick (0.76.0)

The owner, 22 Oct, on a 16x stress test that runs smooth: "i need absolute
masterclass help to get my server to accomplish this" - the game first, then
the server (the API's swarm.py and its CLAUDE.md).

**The game at 16x was 5 frames a second.** The Big Field at 16x is 5,888
monsters; a warrior holding attack had 390 of them after him, every one
chasing, steering round its neighbours, sliding into their backs and firing,
for 40 places round him. The physics tick took 28 to 32 ms against its 12.5,
and Godot ran up to eight ticks a frame to catch up: 161 to 200 ms frames.
Measured headless in the container (the owner's PC is about 1.7 times
faster), `_bench.gd`, the warrior holding attack:

| | before | after |
|---|---|---|
| 16x, open field | 161-200 ms a frame, every frame a hitch | 10.4-11.3 ms, 10-12% hitches |
| 16x, physics tick | 28-32 ms | 9.8-11.3 ms |
| 16x, against a wall | - | 9.2 ms, 16 hitches in 868 frames |
| 12x | - | 7.9 ms, 14 in 1,011 |
| 8x, in the hall | 107 ms, every frame a hitch | about 7 ms, 0-1 hitches |

With every brain switched off the same field costs 3.2 ms - that is the
engine's floor for that many bodies, and the hitches left at 16x are frames
that ran two ticks at about 11 ms each.

- **SEATS: 64 fight at once** (`BaseEnemy.FIGHT_SEATS`; baseenemy.gd, SEATS,
  has the whole rule). A monster after somebody fights only while it holds
  one of that target's seats; one without WAITS ITS TURN where it stands,
  facing them, idle, asking again every `SEAT_RETRY_TICKS`. A seat frees when
  its holder dies, gives up, turns on somebody else or stops asking
  (`SEAT_STALE_TICKS`). One `SEAT_SWAP_MARGIN` nearer than the furthest seated
  one takes its seat, and **being hit takes a seat at once** - nothing stands
  and lets itself be killed. A boss never waits. A heavy pull at 1x is a few
  dozen, so play is as it was; only a stress crowd ever waits.
- **A waiter thinks one tick in `WAIT_STRIDE`** (4), each on its own phase
  (`waits_this_tick()`); a hit is answered on the next tick regardless. The
  bush mage takes the same seat (`bushmage.gd`), and a waiter's threat ring
  refreshes at the idle pace (`threatring.gd`).
- **The sleeper's pass is spread over its quarter second**
  (`EnemySleeper.round_share()`): it looked at every monster in one frame,
  four times a second - 19 ms of one frame at 16x. Now a round is the area's
  monsters as they were when it began, and each frame looks at its share, so
  each is still looked at once a quarter second. A jump looks at everybody at
  once (`check_now()`).
- **The readout says who is fighting**: "after you" in the F3 overlay,
  `PerfOverlay.fight_counts()` - fighting, waiting their turn, and the seats.
- **The owner panel's stress crowd** has 1, 2, 3, 4, 6, 8, 12 and 16x
  (`StressCrowd.MULTIPLIERS`).

**THEIR ATTACKS RIDE THE TICK** (presence.gd, the header). The presence server
sent every attack picture to every other game in the area in a frame of its
own, as it came: players x players frames a second, and at 128 bots in one
area that was 16,000 frames a second and most of the server's time. The hello
now says `"xt": 1` (`TICK_ATTACKS`), and the server puts the attacks made
since its last tick inside that tick's `moves` (`"x": [[who, attacks], ...]`);
`_hear_attacks()` hands them out exactly as an `x` of their own. Nothing plays
later: attacks are played back on the maker's clock, `PLAYBACK_DELAY` behind,
like the steps in the same frame. Our own come back in it and are passed over.
Either side may be older: a server from before ignores `"xt"` and sends `x` as
it did, and this game reads both.

`_test_the_crowd_takes_seats` holds the seats (the first 64 seated, the swap,
a hit, a boss, leaving and retaking, the stride, the stale seat, a freed one);
the sleeper's jump test and "a pass is spread over its quarter second" hold
the round; `_test_other_players_attacks_are_pictures` and
`_test_presence_carries_the_monsters` hold the attacks in the tick and the
hello.

## Seven bosses, seven fights (0.77.0)

The owner, 23 Oct: "bosses currently are stale do to only locking on 1 player
... the idea was cool but bosses are too complicated in a sense but also to
easy not that we have bullets we can customize each boss to do different
things instead of each boss being a repeat we can add real elements and
effects slow on ice etc i want to keep the stalagmites but each boss needs to
be a challenge but also clearable".

**What it was.** All seven bosses ran `bossenemy.gd` with one vocabulary:
three pillar shapes on the cast, eleven spike shapes on a second clock,
stalkers from phase two, the swing. The element changed timings, sizes and
puddles and nothing else, and every attack was a ring at the feet of whoever
was nearest when the gate opened, for the whole fight (`_resolve_player()`
never looks again while its target is valid).

**What it is** - `bossenemy.gd`, THE KITS, has the table and the reasons:

| Boss | Stalagmites | Signature volley | Effect |
|---|---|---|---|
| Light | lance, ring, arc | PRISM: spokes that turn as they leave | dazzle |
| Wind | arc, snare, sweep | GALE: fans that shove; VORTEX in phase three | shove, pull |
| Water | cage, snare, ladder | TIDE: walls of orbs, one moving gap each | soaked |
| Ice | ladder, cage, checker | FROST: shards that stop as mines across your spot | chill, frozen |
| Earth | gate, triwall, rake | BOULDER: its stalagmite thrown where you stood | root |
| Fire | cross, spiral, carpet | PINCER: orbs that shut on your spot and burn it | burn |
| Crowned | ring, cage, gate + stalkers | the other six's, more each phase | wither |

- **One stalagmite clock** (`_on_spike_timer` / `_cast_spike_pattern`) raises
  the kit's shapes: the first two from the start, the third from phase two
  (`stalagmite_pool()`). Ring, cage and gate wear the pillar art, the rest the
  spike art, as before (`PILLAR_SHAPES`). One clock means the pairings the two
  tracks were split to keep apart can never meet. `_build_pattern()` is gone.
- **The cast throws the volley** (`_cast_signature()`, on `cast_frame`) into
  the room's BulletZone - `boss.gd` gives both boss rooms one, with
  `element_effects` on. No zone (a test world) and it raises a stalagmite
  shape instead. Every game fires its own copy: `fire_volley(zone, origin,
  aim, volley, reach)` is monstersync's "b" contract; the name carries the
  phase and a number ("tide2:17"), and a name not in `VOLLEYS` fires nothing.
  Multi-beat volleys run on tweens of the boss's own (`_on_beat()`), so a
  freed boss takes its volley with it.
- **Nobody is locked on.** `next_target()`: whoever in the fight
  (`fight_targets()`, inside the leash, not dying) has gone longest without
  being attacked, never the one just attacked while anyone else is there. Each
  clock takes its own turns; after a cast the boss walks to the next one it
  can see; BOULDER and PINCER go at up to `SPLIT_MAX` players at once
  (`split_targets()`). `_aim_body()` is who a shape is laid out for.
- **Waves take turns**: `_pace()` slows a boss's clocks by `WAVE_PACE` for
  each partner `in_fight()` - x1.35 beside one, x1.7 beside two.
- **Each phase is harder**: `PHASE_TEMPO` on the stalagmite clock, more in
  every volley (the per-phase arrays), `VOLLEY_REST` shorter, and from phase
  two a run of `SWINGS_BEFORE_CAST` swings ends in a cast at point blank.
- **Only the Crowned keeps the stalkers** (`"stalkers"` in its kit).

**The effects** (`src/characters/statuseffects.gd`, no class_name - preload it
by path). One node per character, named `statuseffects`, made in player.gd's
`_ready()`; hazards reach it with `StatusEffects.apply_to()`, which does
nothing to a body without one. `FOR_ELEMENT` is the one table of which element
carries which effect; spikes get theirs in `_spawn_one_eruption()` (on every
game that draws them), orbs through `BulletZone.element_effects` and
`BulletField.hit_from` (a shove goes along the orb's flight, or away from a
mine), puddles through `AcidPuddle.status` - only the ones in `GROUND`, and a
puddle can chill but never freeze. Your own player only; nothing is sent.
The caps that keep a fight clearable: nothing slows more than 40%
(`SLOW_FLOOR`), after frozen or rooted neither can happen for `HOLD_IMMUNITY`,
nothing lasts more than 3 s, a pull is slower than walking, and you can always
attack. Shown with no new art: a tint on your sprite (`self_modulate`), a word
over your head (`show_status_word()`), and dazzle's darkening drawn by a
shader on a CanvasLayer.

player.gd asks `effects_speed_scale()`, `effects_let_sprint()`,
`effects_push()` (added for the move and taken off after it) and
`effects_heal_scale()` (in `heal()` and the regen); tank.gd's own loop asks the
same four - it replaces the base loop, so anything added there has to be
repeated in it.

**Measured** (the website's `tools/bossmeasure.gd`, which now has a dodging
stand-in as well as the two that stand, and carries the effects), raw damage
a second, before armour, 2026-10-23:

| Boss | In reach (phase 1 / 2 / 3) | At range | At range, dodging |
|---|---|---|---|
| Light | 33 / 33 / 41 | 18 / 24 / 33 | 10 / 12 / 17 |
| Wind | 32 / 29 / 32 | 15 / 22 / 25 | 9 / 8 / 10 |
| Water | 43 / 46 / 58 | 33 / 44 / 55 | 7 / 7 / 8 |
| Ice | 42 / 53 / 88 | 19 / 25 / 54 | 8 / 15 / 18 |
| Earth | 101 / 114 / 158 | 84 / 119 / 144 | 24 / 31 / 36 |
| Fire | 127 / 130 / 186 | 80 / 113 / 183 | 20 / 24 / 28 |
| Crowned | 122 / 201 / 284 | 78 / 164 / 238 | 46 / 40 / 57 |

Against the one shared set the bosses had before, measured the same way with the
same dodging stand-in: the first four are gentler on a player who stands still in
phases 2 and 3 and the last three harder by phase 3, and a player who dodges takes
about the same or less. **What makes the bosses easy is not their attacks but
their health**: the website's Boss Sim has a level-22 warrior in Ember, alone,
killing Light in under 10 s and the Crowned in about 25. That is the next lever,
not more attacks.

`_test_the_bosses_are_seven_fights` holds the kits, every effect and its cap,
the hazards carrying them, every volley's count on its beat, the turns, the
pace, and both movement loops asking.

## The Health tab: the live server on the GM panel (0.78.0)

The owner, 24 Oct, of four next steps after the swarm (send each game only
the players near it, watch the live server, test on the real machine, let the
server referee every kill): "work on this or if you have a even better idea
lets hear it". The better idea: measure first. The droplet's plan includes
1,000 GiB of outgoing data a month, and 128 in one area send about 13 MB/s -
some 32 TiB a month held - so the trigger for sending only what is near is
the bill, and nobody could see it. Now the GM panel can.

`src/ui/owner/healthtab.gd` (`HealthTab`), the seventh tab, after Economy;
built like the Economy tab - made in code, pages that take turns,
nothing scrolls, every page no taller than the other tabs. It reads
`GET /api/server/health` (the API's serverhealth/; its CLAUDE.md, "The
server's health") when the panel opens, on Refresh (the kill receipts read
fresh, `?fresh=1`, and what it read said in Results) and every
`REFRESH_SECONDS` (30) while it is on screen (`is_visible_in_tree()`).

- **Players**: online, in an area, the biggest crowd; the most today and this
  week; the tick (steady is ten a second with no late beat).
- **Data**: data going out a second - the machine's own network and the
  game's sockets' share; the month at this week's rate against the 1,000
  GiB, and what past it would cost (green, then amber at half, red past it);
  the data guard (0.79.0, below); whether one area needs sending only what is
  near yet (the server's verdict).
- **Machine**: the load, memory, disk and database size, the three slowest
  routes by p99 (one gunicorn worker's view, as /api/metrics).
- **Receipts**: "Kills need the server's count" - the week's kills put to
  the server's own count (killwatch.py's), a verdict in a sentence (ready,
  or what it waits for: a week of books, 200 kills, 98% backed, no monster
  the books never see), the monsters never seen by name, and the switch.
  **One switch, two places**: the Health tab's throws it through the
  Testing tab's own `_on_receipts_toggled()` (owner only, the password asked
  again), and `_show_receipts()` sets both from whatever the server says.
  While the oldest build allowed in is below `Combat.RECEIPT_BUILD` it says
  to raise Old versions must update first.

A server from before 0.78.0 answers 404 and the tab says to update it; a
server whose presence.py is still the old process says it has not written a
minute. `_test_the_gm_panel_health_tab`; the tab titles in
`_test_the_gm_panel_is_a_window`.

**THE DATA GUARD (0.79.0).** The owner: "i do not have that kind of budget i
need to keep under specifications because i will go bankrupt fast". The
server holds the month's data under the droplet's plan itself (the API's
CLAUDE.md, "The data guard"): full, then other players' steps at half rate,
then at most 16 players seeing each other in one area (the rest in a second
room of it, "field#2", with monsters of their own), then everyone alone.
Nothing changes in the game for it: a player moved between rooms is sent the
"leave"s, "join"s and "lead" a game already handles, and its game takes the
monsters over where they stand when it is alone. The tab now has four pages
- Players (and the tick), **Data** (data out, the month, the guard's level,
the month counted and what it can still send, nearby-only sending), Machine,
Receipts - with Refresh under the page buttons (`guard_text()`).

## Bosses that scale (0.80.0)

The owner, after a rating of the game: "we need to think outside the box ...
lets fix it up". Measured on 0.77.0, a level-22 warrior in ember killed the
Light boss in under ten seconds and the Crowned in about twenty-five. A boss's
health is now set by who is fighting it, on the game that runs it
(`bossenemy.gd`, BOSSES THAT SCALE): `scale_for()` - each fighter counts
`min(LEVEL_MOST 5, 1 + LEVEL_SHARE 0.2 x levels above BAND_TOP)` (the band
table under "The pace"), the mean of them, times `1 + PARTY_SHARE 0.6` per
extra fighter (`PARTY_MOST` 16, the highest levels), times `HEALTH_BASE` (the
Crowned 2.5). Looked at every `SCALE_SECONDS` while it fights: raised as
fighters join, the damage done kept (`raise_for_scale()`), never lowered in a
fight; back home, out of it and whole, itself again (`unscale()`). Every
screen and the server's books are told with a world event `"mh"`
(`net_rescale()` on a mirror; the API's combatbook.py `rescaled()`,
`BOSS_RAISED_MOST`). **Deploy the server first**: an older one flags a raised
boss "max_hp_differs". `_test_bosses_scale_to_their_fight`; the API's
test_combatbook.py CB-12.

## The damage meter (0.81.0)

GM panel > Testing > **Damage meter** (a CheckButton made in code under
Performance, `ownerpanel.gd` `_add_meter_button()`). It opens
`src/ui/owner/damagemeter.gd`: a CanvasLayer built in code, on the root so it
stays open across areas (`shared()`), preloaded rather than a class_name.

- **The server's count, not this game's**: `Presence.watch_damage(on)` sends
  `{"t": "dm", "on": ...}` (said again on every welcome); presence.py answers
  once a second with the room's hits the books counted and who dealt them
  (api/CLAUDE.md, "The damage meter"). `Presence.damage_meter` hands each report on.
- **Rows**: DPS over the last `RECENT_SECONDS` (5) and over the fight since
  Reset (first report to last, plus the second the first covered), total,
  biggest hit, and the server's allowed DPS for that character. A hit the books
  held down to the character's bounds counts as booked, and the rest shows as
  "held" in red. Filters: Everyone / Just me; All monsters / Bosses only.
- **0.81.1, the owner: "make this even better"**: solid (0.97 - at 0.88 the
  windows behind showed through in patches); a fight line (length, everyone's
  total, group DPS); a bar under each row as long as its share of the top
  total, in its class's colour (`CLASS_COLOURS`, drawn on the grid after it
  sorts); Share; Limit as the fight's DPS against what the server allows,
  green under 90%, yellow to 100%, red past it or "held"; a tooltip on every
  heading; **Copy** puts the table on the clipboard as text; the window
  remembers where it was dragged (`last_position`) while the game runs.
- **Static and tested**: `fresh_state()`, `add_hits()`, `rows()`, `summary()`,
  `limit_share()`, `clock()`, `as_text()`, `number()`; `_test_the_damage_meter()`.

## The fight log (0.82.0)

The owner, 25 Oct: "i need to document the progression of battles to fine tune
my system ... the main point is statistics that i can improve upon". The damage
meter's **Fights** page (`src/ui/owner/fightlog.gd`, pure statics plus the
`Chart` inner class; damagemeter.gd holds the state and the page).

- **A fight starts with the first hit the meter hears and ends after
  `QUIET_SECONDS` (10) with none**, or on Reset, or when the meter shuts (the
  server stops reporting to a shut meter, so only fights fought with it open
  are logged).
- **The record** (`finish()`): when, where, length; a row a player - total,
  DPS, best `PEAK_SECONDS` (5), hits, average and biggest hit, held, limit used;
  every kill timed from its first hit to its death (the server's "m" and "k",
  api/CLAUDE.md "The damage meter"), bosses first, at the health they died
  with (scaled); and each player's damage each second.
- **Kept**: the last `KEEP` (10) in `user://fights/log.json`, and each as a CSV
  beside it (`csv()`, `save_csv()`) - not on the web build, where Folder is
  hidden and Copy is the way out. The meter's `log_path` / `csv_folder` are
  settable so the test runner never writes into the owner's own log.
- **Compared**: tick up to `COMPARE_MOST` (3); a chart each (DPS over time,
  the top four players, smoothed over five seconds, in class colours), then
  `compare_rows()` side by side. The page scrolls past 70% of the screen.
- **How it looks** (the owner: "needs to visually appealing for me and more
  refined", then "its too big"): ONE VIEW AT A TIME under three buttons -
  **List**, **Chart**, **Table** (`show_view()`, `fights_view`) - under a status
  line (a red dot while recording) with Copy and Folder. Picked fights are
  shown OLDEST FIRST as **A, B, C**, each in its own colour (`SLOT_COLOURS`)
  wherever it appears. List: a row a fight, clicked to pick. Chart: one
  `FightLog.GroupChart`, the group's DPS through each picked fight
  (`group_line()`, smoothed over 5 s) on one clock, a dashed line in its colour
  where its boss fell, and a legend. Table: `compare_cells()` - every number
  after A with its change from A, green where better and red where worse
  (`BETTER`: group DPS, best 5 s, boss kill time, held), the best of a row on a
  green ground; `KEY_ROWS` until **More rows**.
- **What else a fight keeps** (the owner chose all three of: steadiness and
  uptime, damage by element, event markers): a player's **Uptime**
  (`uptime_of()`: the seconds it dealt damage over its own first-to-last hit -
  low is dodging, walking, waiting; a projectile in flight still counts) and
  **Steadiness** (`steadiness_of()`: 1 / (1 + spread / average) over the seconds
  it dealt any - low is burst or luck); its damage **by element** (the sixth of
  a hit, the element the game sent, after the target's resistance; -1 unknown);
  and the fight's **events** (`event_text()`: a boss grew or shrank as players
  joined or left it, a player joined, left or fell - presence.py METER_EVENTS).
  The table gains Uptime and Steadiness (group means); a fourth view,
  **Players**, shows one picked fight a row a player; **Events** on the Chart
  view marks each on the timeline (^ v + - x, in the fight's colour) and lists
  the first `EVENTS_LISTED`. CSV and Copy carry all of it.
- **One player on the Chart**: click a name in the Players view (`focus()`)
  and the Chart shows only that player's damage (`player_line()`) through each
  picked fight, matched by user id; the title reads "Damage meter: <name>",
  the legend gives their class, DPS, best 5 s and uptime in each fight (or
  "not in this fight"), and **x Group** beside Events brings the group back.
- **A fight's id is its start in milliseconds**, and close_fight() moves one
  that matches a kept fight on by one: Reset can end a fight and start the next
  inside a second, and two fights with one id were picked and drawn as one.
- Tested: `_test_the_fight_log()`.

## The enemy meter, phase 1: damage TAKEN (0.83.0)

The owner's agreed plan: what the monsters do to the players, beside what the
players do to them. The `"hp"` a state carried was a whole percent, for name
plates - too coarse - so each game sends **running totals**, and the server
turns them into each second's share (api/CLAUDE.md, "The damage meter").

- **Counted where the health moves**, into `Presence` (an autoload, so a
  revive's new player does not start the totals again): `take_damage()` counts
  `reduced_amount` (after armour and resistance) once `hp` has moved -
  `Presence.note_taken(amount, element)`, which also keeps the biggest hit since
  the last state and a total by element number; god mode returns first and
  counts nothing. `heal()` counts `actual_heal` (Withered applied, only what was
  missing) - potions, healblob, healaura all land there; `_tick_regen()` counts
  its own **regen**. NOT counted: the level-up refill, loading a save, max-health
  clamps, the owner level tool, a respawn.
- **Sent in every state** (`state_for()` / `send_tick()`): `dt` taken, `dh`
  healed, `dr` regen, `hpa`/`hpm` real health and most; and, off the
  comparison like the clock, `dx` the biggest hit since the last state (once)
  and `dte` the by-element totals only when they moved. A new link sends every
  element again (`_sent_by_element` cleared). A total past `METER_TOTAL_MOST`
  starts again; the server takes that as a new baseline.
- **The fight log** (`add()`, the report's `"tk"`): a player who took damage
  joins the fight (named from `"who"`); one in it has every second kept, so
  their health runs through it. Being hit starts and keeps a fight going like
  hitting does; a heal alone does neither (`took_any()`). A record's row gains
  `taken`, `taken_ps`, `biggest_taken`, `healed`, `regen`, `lowest` (-1 none
  heard), `danger` (seconds under `DANGER_SHARE`, 25%), `deaths` (its "fell"
  events) and `took` (by element); the record gains `taken_timeline`,
  `heal_timeline` and `health_timeline` (lowest health each second, 0-1,
  carried over quiet seconds - `health_line()`). CSV and Copy carry it; a
  fight from before 0.83.0 shows "-".
- **Players** gains a second table under the first (one row of fourteen ran
  off the screen): Taken/s, Biggest, Healed, Regen, Lowest, Danger, Deaths,
  Took (`TAKEN_COLUMNS`).
- **Chart: Taken** - the group's taken dashed in each fight's colour; with one
  player focused their taken dashed, their healing dotted (`taken_line()`,
  `heal_line()`, smoothed like the rest), and a strip of their health under the
  chart, a row a fight, red under 25% (`GroupChart.set_taken()`). Heal and
  damage are two lines, never netted.
- **Phase 2, with the element kits**: "what hit me" - which monster and which
  attack, for a per-attack breakdown.
- Tested: `_test_damage_taken()`.

## The Field's elements do something (0.86.0)

The boss rooms' orbs have carried their element's effect since 0.77.0 (ice
chills, fire burns, water soaks, wind shoves, earth roots, light dazzles, dark
withers - statuseffects.gd). Now the Field's do too, at `field.gd
FIELD_EFFECTS` (0.5) of their strength: `BulletZone.effect_strength`, passed
through `StatusEffects.apply_to(..., strength)` to `apply()`. Under 1 every
effect lasts that share as long, a burn bites and a shove pushes that share as
hard, and nothing takes the controls away: chill is one stack at most (a
fifth slower) and never freezes, earth never roots. At 1 (a boss room)
nothing changed. Only orbs carry effects; a monster's own shot does not.
Tested: `_test_field_effects()`.

## The enemy meter, phase 2: what hit me (0.85.0)

Every hit on a player says where it came from, "<monster>:<attack>"
(`src/shared/hitsource.gd`): the monster is its profile's file name (the
catalogue's id), the attack the volley's kind (frost, helix, ring, pincer...),
the shot's scene name without its element word (arrow, orb), "swing",
"spike", "pool", "burn". Without a new argument on `take_damage()`:

- **A shot** carries it as the meta `HitSource.HIT_META`, set by
  `BaseEnemy.spawn_projectile_node()` (and by hand for the vine, the boss's
  spikes and burning floor, a slime ball's pool), and calls `blame_node()`
  the line before `take_damage()`.
- **An orb** is stamped as it spawns (`BulletField._source`, from
  `HitSource.stamp`, which each `fire_volley()` and the kits set) and
  BulletZone blames it as it lands. Later beats keep their volley's stamp
  (`HitSource.later()`: the boss's `_on_beat()`, the kits' `_later()`); a lob
  and a wake carry theirs (`source`).
- **A swing, a gate, a burn** blame directly.
- `Player.take_damage()` takes the blame first (`take()`), so a hit that
  lands nothing leaves none for the next; nothing blamed is "unknown:hit".
- `Presence.note_taken(amount, element, source)` keeps [hits, damage] a source
  (at most `SOURCES_MOST`, then "other:other"), sent as `dts` only when it
  moved. The server's report row gains it eighth, and `"sn"` names the
  monsters. The fight log keeps `hit_by` a player ([source, hits, damage],
  most first) and `names`; the Players view gains a third table (each
  player's top `HIT_ROWS`), and CSV and Copy carry it all.
- Tested: `_test_what_hit_me()`.

## The element kits for monsters (0.84.0)

The 42 element variants only changed colour and health: in the Field's bullet
zone a water archer and an ice archer fired the same helix. Now each fires its
element's orbs (`src/enemies/elementkit.gd`, small versions of the bosses'
volleys - bossenemy.gd, THE KITS): light a prism ring and a second turned
half a step; wind two swept gale fans; water a slow tide wall with a door,
never on the middle orb where the shot flies (`tide_door()`); ice a frost
fan that settles as mines where you stood; earth the element's stalagmite
lobbed onto your spot, bursting into a crater (`boulder_art()`, the boss's
pillar art at 0.4; a large slime throws its own acid ball); fire the pincer;
dark one of the six per shot.

- **Each family keeps** how it moves and fights and the artist's own shot,
  which flies at the speed the kit gives (`BaseEnemy.fire_kit()`); a boulder
  carries it as the lob; the bush mage's vine is placed apart as before. The
  orbs keep the family's own share of the shot (`HELIX_SHARE`, `RING_SHARE`,
  `CHAIN_SHARE`, `PINCER_SHARE`, `SPRAY_SHARE`), so a band hits as it did.
- **Unchanged**: lightning, poison and physical (no kit); the fire sprite,
  whose pincer IS fire's (`kit_volley(&"pincer")` sends none); the small
  slime's twin and the split ring; and everywhere with no bullet zone - the
  Big Field, as the owner chose, and the crypt.
- **On the wire**: the leader sends the volley name `kit:<n>` (`kit_volley()`,
  n from 0 to `ROLL_MOST`), which picks dark's kind, the tide's door and the
  gale's swing, and the reach; every game fires the same pattern from it with
  its own damage and element (monstersync.gd "b", 16 characters at most). A
  game from before 0.84.0 fires its family volley for it (a slime, nothing).
- **Element effects stay off in the Field** (`BulletZone.element_effects`),
  so an ice orb there chills nobody; a switch for later if wanted.
- Tested: `_test_monsters_fire_their_element()`.

## The server owns the monsters' health (0.87.0)

The owner, of the leader still being trusted with the monsters: "fix this",
choosing the smaller of two sizes - the server owns every monster's health,
deaths and respawns; the leader's game still moves them. (The bigger, the
server running the monsters itself, is weeks and more CPU.) The server half is
the API's presence.py and combatbook.py; this half is `monstersync.gd`,
`BaseEnemy` and `presence.gd`.

- **The hello says `"sh": 1`** and a server whose welcome says the same sends
  `{"t": "hp", "p": [[id, health, maximum], ...], "d": [id, ...]}` each tick
  in a room of two or more: its own count of every monster it moved, and the
  ones it brought to zero (`Presence.health_received`, `server_health()`).
- **A mirror shows the server's count**, never the leader's: the snap's
  health is passed over and `BaseEnemy.net_server_health()` sets it, flashing
  for a drop it did not cause as before.
- **The leader's own monsters come DOWN to the count, never up**: a hit the
  server counted that never reached this game still lands, and the server
  never heals what this game has hurt.
- **A count at zero is dead on every screen.** A mirror dies as at a leader's
  "die" (`_mirror_died()`: the kill reported if this game helped); the
  leader's own dies as from a blow (`net_server_kill()` -> `_die()`, its
  respawner and the gauntlet hearing `died` as ever). Whichever of the
  server's word and the leader's "die" comes second finds nothing to do, so a
  kill is reported once. The server judges such a death AGREED at once.
- **A stir raising a monster while it stands is said** (`raise_for_stir()`
  sends "mh", which `leader_event()` now lets go even alone): the count rises
  with it instead of reaching zero a third early.
- **What stays the leader's**: where monsters stand, how they move, what they
  throw, and when they come back. A dodge is still decided on your screen.
- **A leader that lies loses the area** (presence.py, LEAD STRIKES): three
  deaths in ten minutes the count did not back, monsters back sooner than
  their respawn, or moving one the count killed, and the next game in line
  leads; the struck one may not lead there for ten minutes. Alone, it keeps
  it - there is nobody to hand it to, and it only affects its own screen.
- **Old on either side plays as before**: a game without `sh` is sent no
  `hp` and shows the leader's health; a server without it sends none.
  Deploy the server first.

Tested: `_test_the_server_owns_monster_health()` (a stand-in link,
`HealthLink`), and the API's test_presence.py P-19 and P-19b (a real socket:
a follower's hits bring the count to zero, both games hear it, and the death
is AGREED with no word from the leader).

## The way to the first fight (0.92.0)

The owner's first five minutes, walked: a new character stood in town with the
welcome read once and gone, no sign of which way the portal was, and nothing
to drink. Asked "what is next", he chose this ("yes absolutely improve as
needed"). Three parts:

- **A pointer, until the first kill** (src/ui/guide.gd, made by the HUD just
  after the pad, under every window). A gold » - a letter of the theme font,
  not a picture - circles the character's middle (`RING`, `BODY_MIDDLE`),
  turned toward the next step, with its name on the far side of it from the
  character (`words_at()`); near a target it stands over it pointing down.
  Shown while `wanted(level, xp)`: level 1 with no XP, which the first kill
  ends - nothing new is stored.
  - **The town is one area with a wall across it.** Both portals stand on one
    north-south road: the square's (`teleportnextarea`) south of the spawn,
    the Big Field's (`leavetown`) south of that, the wall between. So the
    nearer is not the next: `town_step()` takes the side of the line halfway
    between them. Found by name each look (every `LOOK_SECONDS`), as each
    one's `teleporter` sprite, so moving a portal in the editor moves it.
  - **A field**: the nearest living monster, "Your first enemy".
  - Bigger under a thumb, at the touch menu's scale, held to 1.6.
- **Starter potions** - the server's (the API's CLAUDE.md, "A new
  character's starter potions"): 5 Tiny Health Potions on key 1, and 5 Tiny
  Mana Potions on key 2 for the mage and the healer, for a slot's first
  character only. The save that made it is answered with its bag, which
  `ServerStorage.heard_save()` adopts (`CharacterData.adopt_granted_bag()`):
  the game made the character with an empty bag of its own, and the potions
  did not show until the next sign-in.
- **The welcome says so**: the potions on key 1, and the shop's free mythic
  weapon on its Free shelf ("for most classes": the healer has none yet).
  And it names the Big Field, where the square's portal has led since 0.15.0
  ("to the Field" was a release out of date).

`_test_the_way_to_the_first_fight()` (testrunner_8) reads both portals from
elusion.tscn and holds the side rule at the spawn, on the road, where the
portal lands and at the Big Field's portal; the placing and the words; the
font letter; the HUD's wiring; the bag adopted. Flipping the side failed two
checks by name. The welcome checks hold the new lines.

## The phone's screen is the game's (0.91.0)

The owner, on a phone: "attack and stuff takes up a majority of the screen on
mobile we are going to have to figure that out". Measured at 844x390 (a phone
held sideways): the stick's resting frame, Attack, Use and Run, ten hotbar
keys at the thumbs' scale (731 of 1280 units across) and an eight-button bar
covered most of the lower half, and the welcome card was fourteen rows at
about 7 CSS pixels. Five changes, all only while `TouchControls.active` - with
a keyboard and mouse nothing moved (pictured, and every older check passes):

- **The pad a quarter smaller** (touchpad.gd): Attack 72 CSS pixels (was 92),
  Use and Run 46 (60), the stick 50 (62), the gaps with them. Still past a
  thumb's 9 mm. Under 4.5% of the screen where it was 5.8%.
- **Round sockets (0.91.1)**: the owner, "we can use the same gold ring just bend the
  shape so its round thats not ai art thats customization". The hotbar slot
  is drawn through `ROUND_SHADER` (touchpad.gd) on a `RoundSocket` behind
  each button and under the stick: each point of the circle reads one of the
  slot's own pixels (`texelFetch`), found by stretching its ray onto the
  square after the same nine-slice, so each square ring of the slot is a
  circle and the gold frame stays 3 pixels thick. `ICON_FILL` is 0.7 so a
  square icon's corners stay inside. The suite checks the shader reads only
  TEXTURE.
- **Smaller, see-through, only when touched (0.91.1)**: the owner, "we do
  not need a attack button really we could make it much smaller and only
  appear when player touches screen ... we could also make them more
  transparent". A tap or a hold on the world already attacks there, so
  Attack is a spare: 52 CSS pixels, Use and the Aura 40. They fade in at any
  touch (`_input()`) and out `SHOW_SECONDS` (3) after the last (`_fade()`),
  and answer a press while faded. Sockets at 60%, icons at 75% at rest.
- **Attack under the right thumb (0.91.2)**: "attack button only needs to
  appear when player taps screen should not be visable and anywhere on the
  middle right screen it can appear", "left side of screen is joystick".
  Attack is a floating `PadButton` (`place_floating()`): the control is the
  whole of `layout()`'s `attack_zone` - from `ATTACK_ZONE_LEFT` (half) across
  to the right edge, the stick's top down to the hotbar - and its ring is
  drawn where the thumb lands (`_land()`), only while it is down. Held, it
  attacks the nearest; dragged, it aims, as the button did. A quick tap on a
  player's name there opens their menu instead (`tap_name_at()` at the
  press). A tap on the world outside the zone still strikes where it lands.
  Not faded with Use: it is never drawn without a thumb.
- **Use always there, and Menu in from the edge (0.91.3)**: "do not make
  the use button invisable next move over the menu more it is cut off on my
  phone because of gm panel". Use is not faded (only the Aura is). The
  owner's Staff, Owner and Powers row is wider than Menu, and the folded bar
  grew both ways (the scene's `grow_horizontal` 2), so it began 18 units off
  the left of the screen. Folded, it grows right only and sits at
  `FOLDED_LEFT` (24) from the edge; the grid opens there too. Unfolded, the
  scene's 8 and both ways are put back.
- **No Run button (0.91.1)**: "if player drags the coin all the way over run
  is initiated". The stick past `TouchControls.RUN_EDGE` (0.92 of its reach)
  sprints, eased back it walks, and its ring and coin light while it runs.
  The Run button is kept, hidden and out of `layout()`, for anything still
  calling `toggle_sprint()`.
- **Use beside the health and mana (0.91.1)**: "the use button we can put
  right next to hp and mana". `layout()` takes the bars' box (`bars`) and
  stands Use just left of it, its middle on theirs.
- **The stick only under a thumb**: `Stick._draw()` returns at rest. The zone
  still takes a touch anywhere on the left; the welcome says so.
- **Five hotbar keys** (hotbar.gd, `TOUCH_KEYS`): 1 to 5 shown, the bar
  narrowed from its pinned right edge (`_show_touch_keys()`, which keeps the
  ten-key width and puts it back). 6 to 0 keep what is on them.
- **One Menu button** (src/ui/touchmenu.gd, made by the HUD as `touch_menu`):
  the bar keeps only Menu, at the pad's scale from its bottom left corner, and
  Menu opens a grid of every button the bar has - its own, Social's and
  Menu's (`ITEMS`). **Nothing is moved**: a grid button presses the bar's own
  button, so the windows, the dropdowns' wiring and the dots stay the bar's,
  and the grid copies each button's words (dot included) as it opens. Menu
  wears Chat's and Social's dot while folded (`paint_touch_menu_dot()`).
  `toggle_nav_menu("menubutton")` opens the grid while folded;
  `close_nav_menus()` and a tap outside shut it.
- **A welcome for thumbs** (controlspanel.gd): three lines of directions
  (`TOUCH_WELCOME_LINES`), the six things a thumb does
  (`TOUCH_WELCOME_ROWS`), in text `TOUCH_TEXT` (1.5) times its size
  (`fit_text_to_thumbs()`, each label's own size kept in a meta, so it never
  grows twice). **Bigger text, not a scaled card**: PanelWindow sizes and
  places every window from what it holds, and a scaled one was measured at
  its unscaled size and ran off the bottom of the screen. The card redraws
  when the thumbs or the keys take over with it open. Menu, then Controls
  still shows the whole touch list.

Two fixes found on the way, both in touchpad.gd: an icon was snapped to whole
screen pixels on a window with fewer pixels than units (20-unit steps, so it
left its frame), and `Art.texel_size()` grew a picture past its room when the
room was under a screen pixel a texel. Both now only snap where there are
more pixels than units, as `art_pixel()` already did.

`_test_the_phone_screen_is_the_games()` (testrunner_8) holds the sizes, the
stick at rest, the fold and back, the grid's buttons and dots, and the
welcome; testrunner_3's hotbar check holds the five keys. Four sabotages
caught: the stick drawn at rest, the bar not folded, ten keys, the long
welcome list.

**Speed at 1x, measured for the same request ("making it even faster")**:
with every script's physics switched off, town's tick costs the same, so at
1x the scripts are not the cost; the sandbox's software drawing cannot say
what a phone's GPU does. Two levers left, both the owner's call: physics at
60 ticks instead of 80 (a quarter of the physics work; interpolated, so it
looks the same, but every count in ticks would change in seconds - "a feel
decision", Speed on day 1), and a smaller engine for the web (index.wasm is
39.5 MB of a 58 MB first visit, about 16 MB compressed; a Godot build without
3D is a custom export template, built from source).

## Deleting your own account (0.90.0)

The owner, of a database diagram that showed no way to remove an account:
"lets fix all of those". Options > Account > **Delete account...**, built in
code under the password form (`_build_delete_account()`, like character
select's delete), so `optionsscreen.tscn` is untouched:

- A red warning that says what goes and that it cannot be undone
  (`delete_warning_text()`), a box for the account's name ("Type <name>"), the
  password, and **Delete forever**, pressable only when `delete_ready()` (the
  name in any case, and a password).
- **The first press only arms it** ("Sure? Press again to delete") for
  `DELETE_ARM_MSEC` (4 s); typing, or shutting the form, disarms it.
- The second sends POST /api/account/delete (the API's accountdelete/); a 401
  says the password is wrong and changes nothing. Deleted:
  `Api.forget_session()` with "Your account is deleted. Thank you for playing
  Elusion.", `CharacterData.clear_current_user()`, and the login screen. The
  server already ended every session, so there is nobody to tell.
- Hidden when nobody is signed in. `delete_request` is the suite's door.

`_test_an_account_can_be_deleted()` (testrunner_8); one sabotage (no arming)
caught.

## Each game is sent only the players near it (0.89.0)

The owner, rating the server's cost 8 of 10 ("the weak spot is data, which
grows fast when players crowd one area"): "upgrade this". The work is the
API's (presence.py, ONLY WHAT IS NEAR; the API CLAUDE.md has the rules and
the measurements) - **the game needed no change to take it**: the server
draws a player on this game's screen with the "join" it always sent, and
takes it off with "leave", so every version since presence began gets it.

What that means here, if something looks wrong:

- **A player more than about half a screen off the edge is not drawn**
  (`presence.gd` `_remotes` holds only the near ones). They come back with a
  "join" as they walk up, placed where they stand. Nothing in the game may
  assume `_remotes` or the `remoteplayers` group is the whole area.
- **What still sees everyone, by the server's rule**: the area's leader (its
  game runs the monsters, which chase anybody - `targets.gd`), staff (Go to,
  `Presence.meet()`), and party members of each other (the party window's
  health, `partypanel.gd`, and the map's party rings, `mapscreen.gd`).
- **The healer's aura blobs** go to the remote players drawn; one too far off
  to be drawn is too far for a blob. The heal itself is the server's
  (THE AURA'S HEALS), by distance, as before.
- The Health tab's nearby line says "on" (`HealthTab.nearby_text()`, verdict
  `"on"` from the server); a server from before still sends the old verdicts.

## The game tells the server what broke (0.88.0)

The owner rated stability 8 of 10 - "rare live breakages, and fixes go out
fast" - and asked for the 9. A SCRIPT ERROR in a player's game printed to a
console nobody reads and the game played on half broken; he heard of it only
if the player said so.

- **`src/systems/errorreporter.gd`**, a child of the Api autoload
  (`Api.error_reporter`), adds a Godot `Logger` (`Catcher`) that keeps every
  `ERROR_TYPE_SCRIPT` error - not `push_error()`, not warnings, not engine
  errors - as where (`res://...gd:line`; a file off the game is only its name
  in angle brackets, never a path that could hold the player's name), what it
  said, and how many times. Once a minute (`REPORT_SECONDS`), signed in, the
  oldest `ERRORS_PER_REPORT` (20) go to `POST /api/client/errors` with
  `Api.DISPLAY_VERSION` and the area. Not heard (server down, signed out):
  kept for the next. Refused (400) or a server from before 0.88.0 (404):
  dropped. At most `ERRORS_HELD` (200) different errors wait; the rest are
  counted in `lost`. A Logger is called from any thread, so the counts sit
  behind a Mutex.
- **Not in the editor** (`wanted()`): the owner sees his own errors there, and
  the suite runs with the editor's binary - a test that provokes an error must
  never post it. The suite starts one by hand with a stand-in `send`.
- **The GM panel's Health tab has an Errors page**: `GET
  /api/server/client-errors` (the API's clienterrors/), read with the health,
  worst first - how many players, how many times, the script and line, the
  versions, the message. Never who. The page button turns amber, its hover
  counts them. Five page buttons at 13 points, 2 apart, fill the panel's 370.
- `_test_the_game_reports_its_errors()` (testrunner_8) feeds the catcher by
  hand (the suite fails any real SCRIPT ERROR) and drives the report, the
  give-back and the Errors page. Played: a real null call in a running game
  was caught, sent to a local server and listed on the page.

## The window sweep (0.88.0)

The owner, 26 Oct: the game "works and keeps improving, but its history is full
of 'found by playing' fixes: names cut off, wrong colours, windows nobody could
open". So every window in `WINDOW_PANELS` was opened in a real game, signed in
to a throwaway local server seeded with the longest names it allows (twenty
letters, W the widest; a twelve-letter guild tag), full friends, guild, party,
chat and a kingdom donation, a bag and a bank full of stacks up to 1,000, and
pictured at 1280 x 720. A layout check measured every Label against its text
and every button against its window's edges. What it found, and what changed:

- **The kingdom board drew only the guild tag.** The tag sat beside the name,
  took the width of its own text, and the name (set to clip) got one pixel:
  Tunacan's row read "[WWWWWWWWWWWW]". The tag now goes on the line under the
  name, with a patron's title (`names/sub/guild`, `names/sub/title`; the line
  shows only when it has something). A name wider than the name column itself
  (a twenty-W name; the four figure columns take most of the board) is still
  clipped, with the whole name on its hover.
- **The party lost what members play.** "Lv 27 Mage - away" shared the row
  with the name and the leader's buttons, set to clip: a long name cut it to
  "awa", a twenty-letter one to nothing. It is its own line under the name now.
- **Four-digit stacks covered the picture.** A cell's count is thousands from
  a thousand, rounded down so it never claims more than it holds
  (`InventorySlot.count_text()`: 1,999 is "1.9k", 12,345 is "12k"); the
  tooltip still says the exact count.
- **"Tunacan (Tunacan)".** Who is playing names the character only when it is
  called something else (`PlayersPanel.row_name()`).

**The owner's two rules from it (26 Oct):**

- **Windows stay 95% solid, on purpose.** The hotbar, the health bars and
  nameplates showing faintly through a window is a feature: "If a player opens
  their bank ... in a dangerous zone, they need to see if an aggressive mob
  wanders onto their screen." Do not make the brown panels opaque.
- **Brown is the player's, dark blue is the staff's.** "Brown is for the
  player experience; Dark Blue is exclusively for the admin cockpit." Options
  was the one player window in the dark blue; it takes `rpg_ui_theme.tres`
  now, with a small theme of its own on `margincontainer` that keeps its text
  at 12 (the brown theme sets no size, so it would be 16 and overflow), pads
  its drop-downs and draws its switches without a button's box. Its section
  headings, text, help bubble and name swatch are brown-palette colours. A
  new player window takes `rpg_ui_theme.tres`; a GM or staff window takes
  `staff_ui_theme.tres`.

`_test_long_names_fit_their_windows()` (testrunner_8) builds the party and the
board with those names, measures them with `_layout_cuts()`, and holds the two
small rules; it went red with the party's old row put back.

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
src/characters/     player.gd, playerstats.gd, and warrior/mage/tank/healer;
                    remoteplayer.gd draws another player
src/enemies/        BaseEnemy and its six subclasses
src/pets/           the companion system
src/projectiles/    arrows, acid, vines, slash waves, ground hazards
src/systems/        the autoloads — api, audio, characterdata, combat,
                    gameconstants, gamestate, itemregistry, presence,
                    scenetransition —
                    plus the save/load storage layer
src/types/          ClassData, EnemyData, ItemData, ItemStack. The Resource TYPE
                    definitions only; data/ at the project root holds the .tres
                    instances authored from them.
src/ui/             characterhud, hotbar, statsscreen, floatinglabel, storyscene
src/ui/bank/        src/ui/inventory/   src/ui/lootbag/   src/ui/menus/
src/ui/owner/       owner-only tooling, gated on Api.is_owner
src/world/          levels (elusion, field), interactables, lootbag, roofswap,
                    mapbackdrop (grey under the tiles, black past the map),
                    enemysleeper (far enemies stop thinking)
src/shared/         pure helpers used across characters, enemies and pets —
                    facing, formation, homing, safespot, marks (the dots and
                    arrows drawn as pixels), and localtime, which
                    is the ONLY place unix seconds become a wall clock
src/tools/          the gamedata exporter, the test runner and the atlas
                    audit — none of them ship
scene/tests/        tests.tscn, the headless entry point for the test runner
data/items/         ItemData      data/enemies/  EnemyData
data/classes/       ClassData     data/gamedata.json  the exported contract
docs/apicontract.md   what the client and server promise each other
docs/audio.md         the 37 sound ids, where each fires, what the suite
                      does about a registry that is half filled in, and
                      where every recorded file came from. One entry in
                      Audio.SOUNDS is filled (teleport); the rest are empty
                      on purpose, and the boot log counts them at every launch.
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

### Attacks stop at walls, and nothing flies out over the black (0.69.1)

The owner, in the Big Field: "players can attack enemies through doors/walls"
and "i saw a projectile floating in the black". Every way a player hurts a
monster found it by overlap or by distance, and nothing asked whether a wall
stood between. Monsters already asked (`_has_line_of_sight()`); now players'
attacks ask the same question.

- **The rule is `Targets.clear_between()`** (`src/shared/targets.gd`): a ray
  on `BLOCKERS`, layer 1 (every TileMap, wall piece, crypt door and solid
  prop, the layer monster sight masks) and layer 2 (boss-gate bars). Areas
  never block. `can_reach()` asks it of a target's body; `short_of_wall()`
  stops a point `WALL_MARGIN` this side of the first wall. On a player,
  `can_hit()` and `reach_short_of_wall()` ask from `Targets.body_point()`,
  never the origin.
- **Why from the body.** The warrior's origin is 13 px above its feet, so a
  warrior pressed against a crypt door has its origin inside the door, and
  against a Big Field north wall (collision strips about 2 px thick) already
  past it, over the black. A ray that starts inside or past a wall does not
  see it. That is how a Double Axe thrown from there flew out into the black
  and spun.
- **What asks.** The sword (`_try_damage()`), the wave and the fan (not
  thrown when their start is past a wall; a wave's box asks from its middle),
  blade orbs, the spinning axe's every cut (thrown from this side of the wall
  too), the stalagmite, the meteor and its crater, the tank's ring, dynamite
  (landing, blast and chain), the healer's orb (a ray along each step; it
  homes only on what it can see), its aura (dropped and ticking), pets
  (nearest visible target; their shots stop at walls) and the touch screen's
  auto-aim. A spell, throw or aura aimed past a wall lands this side of it.
  The meteor's pull does not ask: it hurts nothing, and a monster behind a
  wall slides along it as it would walking.
- **Small solid props count.** A pot, crate or pillar between you and a
  monster blocks a blow, as it already blocked the monster's shots at you.
- **The bush mage had four always-on 108 px boxes on the monsters' layer**
  (`attackbox*`, used by nothing). Any attack reading areas hit the mage
  anywhere in a 150 px square round it, through walls. They are gone.
- **A finisher's burst and fan start this side of a wall (0.70.0).** The
  owner: "warriors bullet projectile is spilling outside the map and is
  scattering in the black kind of like teleporting". The burst left from the
  middle of the monster's hurtbox, which stands taller than the wall its feet
  are behind - over a Big Field north wall, already in the black. It leaves
  from as far toward it as the wave can see, and an orb whose start is past a
  wall is not fired; so for the finisher's fan, and for another warrior's
  pictures, which a game from before 0.69.1 sent from its origin.
- **Nothing is left over the black.** A slash wave lives `MAX_SECONDS` (3) at
  most - one fired off this screen by another warrior never left it. An axe
  taken off while out tells everyone else's copy to come home, and a recall
  reaches a copy even with Options > "Other players' attacks" switched off.
- `_test_attacks_stop_at_walls()` builds a crypt door, a 2 px Big Field wall
  and boss-gate bars, and drives every class's attack on both sides; a code
  check fails any of the attacks above that stops asking.

### Every bullet vanishes over the black (0.72.1)

The owner: "white bullet projectiles from warrior fling in the black of the
map ... spraying across the map instead of vanishing". Walls stop bullets,
but the town, the Field and the boss arena have edges with no wall: water
or a cliff that stops a player's feet (a thick collision body, or none at
all past the last tile) while a bullet flies on over the unpainted black.
A probe walking a real warrior to every edge found 64 such leaks in the
town, 11 in the Field and 4 in the boss arena; the Big Field had none.

- **`MapBackdrop.black_at(node, world_pos)`** (`src/world/mapbackdrop.gd`)
  is the rule: true when the spot is not on any painted tile of the area the
  node is in. The backdrop builds a byte grid of 8 px cells (`BLACK_CELL`)
  from its `rects`, once per scene (cached in `_grids`, like `_covers`).
  A cell a painted rect touches is painted, so a bullet skimming the edge of
  the last tile is not cut early.
- **Only inside the area.** `black_at()` is false for anything outside the
  area the current backdrop belongs to, and false with no backdrop - a test
  arena, built without one, behaves as before.
- **Who asks, every tick.** Blade orbs (freed, no spark), slash waves and
  finishers (broken quietly: no burst out over the black), the monsters'
  arrows, fire, magic and poison shots, the healer's orb and every pet shot.
  The Double Axe takes the map's edge for a wall: it stops there and spins.
- `_test_bullets_vanish_over_the_black()` builds an area with a backdrop
  and checks each of those, the grid against `cover()` for the town, and
  that a node outside the area is never black.

## The players menu, and a switch for combat that does not exist

**Who is playing** is a nav-bar button anyone can press. It lists every online
player, their character, level and area, grouped into *"In Elusion with you"* and
*"Elsewhere"* — and the heading is built from the server's own `precision` field
rather than the word "area", so when real positions arrive the wording follows
instead of going on promising a distance nobody measured.

**Right-click a name for Whisper, Add friend or Trade** (day 1). There is no menu
on your own row. The panel only asks: it emits `whisper_asked`, `friend_asked`
or `trade_asked`, and the HUD (`_build_players_panel()`) sends each to the window
that already does it. Those are `chat_panel.start_whisper()` (the chat log's name
menu uses it too), `friends_panel.ask_from_elsewhere()` (the same `ask()` as the
Ask box, so the two cannot check a name differently) and `trade_panel.offer_to()`
(the typed-name offer, with no slot). Trade works with anyone online, not only
people in your area, because the server allows that. `_test_players_right_click_menu`
holds it. It was also checked live with real clicks against a second account:
the friend was asked and accepted, the whisper arrived, and the trade opened.

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

**Where this stands, 19 Oct.** This was written before presence, and two of
the four steps below are done since. Players see each other: presence (0.7.0)
draws every body, name, attack and pet in an area, and the area's monsters
are shared. And where everyone stands is recorded: presence.py writes a sample
of each character every 15 seconds it moved (`position_samples`, api/CLAUDE.md
"WHERE EVERYONE STANDS"), its own table, not a column on `saves`, and nothing
reads it yet. What is left is step 3, damage the server decides - server-owned
hp and server-run monsters, E3_SCOPE.md's step 3 - and then the switch. The
rest of this section is as it was written, for the reasoning.

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

1. **Positions on the server** *(done 19 Oct, as presence's samples - see the
   top of this section)*. When written: there were none at all. Not stale ones: none.
   `saves` holds `class_id`, `name`, `level`, `area` and the vitals, and **no
   coordinates**. This was got wrong here once already: a pass added `x, y` to
   the `SELECT` in `/api/staff/user` so the owner panel could stand beside
   somebody, and broke that route outright — `no such column: x`, caught by
   `test_security.py` on the next run. The `x`/`y` that do exist are on
   `pending_teleports`, which is where a teleport is **going**, not where a
   player **is**.

   So this step is a new column pair *and* a heartbeat carrying them — the first
   thing in this project that costs real requests per player per second, which is
   why it waits for the droplet's numbers. The owner panel's **Go to** lands
   beside somebody since 0.7.4 without it: the presence link draws everyone in
   your area where they stand, so the position is your own game's, not the
   server's (`Presence.meet()`).
2. **Remote players rendered** *(done: presence, 0.7.0)*. A body, a nameplate, interpolation between
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

- ~~The backpack ledger is still whatever the client pushes on save.~~ Closed:
  the bag and the bank are the server's, every drag, bin and pile a request of
  its own, and a save carries neither. See "The bag is the server's".
- ~~`has_active_revive` in `player.gd` is never set true.~~ Closed — the flag
  and its unreachable branch are gone. The real revive is `gameover.gd`'s,
  after the server has been paid. The ordering the dead branch needed is
  recorded where it was, in case a token-style revive is ever added.
- **A paid revive lands in town**, at its usual spawn, as every login does.
  Decided by the owner on day 1. `GameState.reviving` was set "so the world
  can put the player back at `death_position`" and nothing ever read it; it is
  gone, so nobody builds on the promise.
- ~~`gamestate.gd` declares eleven signals that are never emitted or connected.~~
  Closed. There were thirteen, not eleven, which is its own small lesson about
  counts written down by hand. All removed — `gamestate.gd` is now the four
  transient values something actually reads. The signals are in git if
  multiplayer wants a starting point, though one designed around a real
  listener will fit better than one designed around none.
- ~~The boss scene has no script.~~ Closed — `bossarena.tscn` runs `boss.gd`,
  and the arena's portal runs `fieldportal.gd`.
- 37 sound ids, 32 wired to call sites, 2 audio files (`audio/ambience/firepit.ogg`,
  and `audio/sfx/teleport.ogg`, the first id filled). The audio is authored
  in-house, so the slots exist and fill one at a time.
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
