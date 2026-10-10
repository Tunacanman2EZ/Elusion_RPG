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
the next band's set. `generalstore.tres` stocks the nine potions, the fishing
worm and the iron to amethyst rods, and every weapon and armour piece from iron
(tier 1) to amethyst (tier 4), bonus amulets included, at its value
(`price_multiplier` 1.0). Ember, the ember rod and the boss trophies stay
drop-only.

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
invented number from reaching anybody's health.

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
point `DEFAULT_BASE_URL` at the real address before exporting.

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
which reports exactly what the editor shows. `testrunner.gd` still carries
some of its own; they appear only when the suite is run from the editor.

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
their own attack animation". Tier 6 (Mythic), level 22, one per class; the
healer's (a heal) is a later commission.

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
  worth the wait" below. A meteor's hit is 22 px
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
  players land. Five alcoves (`elitealcoves/band1..5`) are markers for the
  elite spawns, which are not built.
- **Painted in the Field's own crypt tiles**: the same `underground.png`
  atlas block, walls with the same collision, 196 x 128 cells, and a
  navigation polygon cut from the floor. Generated by a script from the
  blueprint, so it has no props, candles or decals yet; those are the
  owner's to place in the editor like any other scene.
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
128 enemies, the safe landing, every enemy on open floor, the bands in
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
   why it waits for the droplet's numbers. The owner panel's **Go to** lands
   beside somebody since 0.7.4 without it: the presence link draws everyone in
   your area where they stand, so the position is your own game's, not the
   server's (`Presence.meet()`).
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
