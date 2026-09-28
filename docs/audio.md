# Sound: what the game asks for, and what it has

The game is **silent**. Every id in `Audio.SOUNDS` is an empty string, and the
boot log has been saying so at every launch since the system was written:

```
[BOOT] Audio: 0 of 31 sounds assigned
```

That is a deliberate state, not a bug. The hooks went into the game first so the
audio could arrive one line at a time without a flag day — an empty entry is a
no-op, so a call site with no file behind it returns quietly instead of
erroring. **Fill an entry in and that sound is live everywhere it is already
called from.** No other file changes.

This page exists so that can be done without reading the code.

---

## How to add one

1. Put the file at `res://audio/sfx/<id>.ogg` (or `res://audio/music/<id>.ogg`).
2. Paste that path into the matching entry in `SOUNDS` in
   `src/systems/audio.gd`.
3. Run `run_tests.ps1`. It will tell you what is still empty.

Nothing else. Callers use the id, never a path, so re-pointing a sound later is
one edit in that table rather than a search across fifty scripts.

### Format

| | |
|---|---|
| **Short one-shots** (swings, hits, coins, clicks) | `.wav`, 44.1kHz, mono |
| **Anything over a second** (music, ambience, the death sting) | `.ogg` |
| **Music** | `.ogg`, stereo, loop points set in the import dock |

Mono for positional sounds is not a preference: `play_at()` pans them, and a
stereo file arrives already panned and fights the engine for it.

### Loudness

Normalise so nothing clips, then mix **quiet**. The pools are twelve deep and
eight deep, so twelve swings can overlap; a sample mastered to sit comfortably
on its own is deafening when three enemies die in the same frame. Leave
headroom and let `volume_db` at the call site bring individual sounds up.

**Do not bake variation into the file.** `DEFAULT_PITCH_VARIATION` is 0.08, so
every play is already pitched a few percent either side of 1.0 — twenty sword
swings are never bit-for-bit identical. A sample with its own wobble recorded in
gets that twice.

### Licensing

Audio is a licensing decision, exactly like art, and this repository is careful
about art: `art/pack/` is a private submodule, the licence boundary is in the
README, and `_test_art_folders_are_licensed()` fails the suite when a new art
folder appears with nothing saying where it came from.

**Nothing equivalent exists for audio yet, because there is no audio yet.**
Whatever arrives here should be recorded the same way — where it came from, what
the licence allows, whether credit is required — and the licensing check should
learn about `audio/` at the same time. Do that on the first file, not the
thirtieth.

---

## The 31 ids, and where each one fires

Line numbers drift; the file names do not. Comments are excluded, so every site
below is real code.

### Combat

| id | played from |
|---|---|
| `attack_swing` | `characters/player.gd:1275`, `characters/warrior.gd:416` |
| `attack_hit` | `enemies/baseenemy.gd:2468` |
| `player_hurt` | `characters/player.gd:1361` |
| `enemy_hurt` | `enemies/baseenemy.gd:2478` |
| `enemy_death` | `enemies/baseenemy.gd:2515` |
| `player_death` | `characters/player.gd:1463` |

`player_death` is the one sound in the game that must not be cut off, and the
whole reason `Audio` is an autoload rather than players parented into scenes: an
enemy that played its own death sound got `queue_free()`d mid-playback. It fires
from `_start_death_sequence()`, before the death animation, and the comment
there is explicit that it must not fire for a revive that did not happen.

`attack_hit` and `enemy_hurt` both fire on a connecting blow, a few frames
apart. They need to be distinguishable or the hit reads as one muddy noise —
give the weapon the transient and the enemy the voice.

### Magic

| id | played from |
|---|---|
| `spell_cast` | `characters/healer.gd:208`, `characters/mage.gd:203` |
| `projectile` | **nothing plays it yet** |
| `aura_on` | `characters/tank.gd:343` |
| `refused` | `ui/lootbag/lootbaginventory.gd:448`, `ui/bank/bankinventory.gd:414`, `ui/cooking/cookingscreen.gd:776`, `ui/cooking/cookingscreen.gd:785`, `characters/mage.gd:184`, `characters/tank.gd:333` |

`refused` is the most-played id in the game — six call sites — and it is the one
most worth getting right. It is the sound of "you can't do that": a full bag, a
burnt fish, a spell on cooldown. Short, dull, unmusical, and **not annoying at
the twentieth repeat**, because it will be heard twenty times in a row.

`projectile` is registered and nothing plays it. The hook belongs where an
arrow, orb or poison ball leaves a muzzle — see `muzzle_marker_prefix` and the
release-frame notes in the art pipeline. Adding it is a one-line call in the
projectile spawn, not a new system.

### Items and loot

| id | played from |
|---|---|
| `item_pickup` | `ui/lootbag/lootbaginventory.gd:370`, `world/fishingspot.gd:734` |
| `coin` | `ui/lootbag/lootbaginventory.gd:352`, `:361`, `ui/inventory/inventoryscreen.gd:549`, `ui/trade/tradepanel.gd:576`, `ui/shop/shopinventory.gd:337` |
| `potion` | `ui/inventory/inventoryscreen.gd:678` |
| `bag_drop` | `systems/combat.gd:256` |
| `bag_open` | `world/lootbag.gd:287`, `world/firepit.gd:290` |
| `inventory_move` | **nothing plays it yet** |

`coin` fires on five paths — loot, selling, buying, trading — and gold now has
real denominations, from a copper coin to a platinum one worth a hundred
thousand. One sample for all of them is fine; if it ever scales with value, that
is a `volume_db` argument at the call site, not five ids.

`inventory_move` is registered and unplayed: the hook is dropping an item into a
slot, in `inventoryscreen.gd`. It will be the most frequently heard sound in the
game after `refused`, so it wants to be very short and very quiet.

### Gathering and cooking

| id | played from |
|---|---|
| `cook` | `ui/cooking/cookingscreen.gd:785` |
| `fire_light` | `world/firepit.gd:485` |

`cook` is the id this project learned a lesson on. It was being played before it
was registered, so every fish finishing on the fire produced a `push_warning`
instead of a sound — and a warning in a running game is a line nobody sees. The
suite now fails if any played id is missing from the table.

It is also the awkward one to find: the call is

```gdscript
Audio.play("refused" if burnt else "cook")
```

so a check that matched `Audio.play("<id>")` would see `refused` and never learn
that `cook` is played at all. The suite reads every string literal between the
parentheses for exactly this reason.

### Progression

| id | played from |
|---|---|
| `level_up` | `characters/player.gd:1494` |
| `skill_up` | `characters/player.gd:1163`, `world/fishingspot.gd:734` |
| `pet_summon` | `characters/player.gd:2364` |

`level_up` and `skill_up` will sometimes land in the same frame — killing
something can raise both — so they must not be two takes of the same fanfare.
Make the character level the bigger event; skills go up constantly.

### World and UI

| id | played from |
|---|---|
| `ui_click` | `ui/menus/optionsscreen.gd:560` |
| `bank_open` | `world/bankchest.gd:113` |
| `teleport` | `world/teleporter.gd:34`, `world/victoryteleporter.gd:175`, `:208` |
| `door` | `world/ladder.gd:64` |
| `lever` | `world/lever.gd:140` |
| `spikes` | `world/spikedoor.gd:121` |

`ui_click` has exactly one call site — the options screen — which is almost
certainly wrong for a game with this many buttons. Either it belongs on a shared
button helper, or the id should be retired rather than left looking wired.

### Music

| id | played from |
|---|---|
| `music_menu` | **nothing plays it yet** |
| `music_town` | **nothing plays it yet** |
| `music_field` | **nothing plays it yet** |
| `music_crypt` | **nothing plays it yet** |

**No music is started anywhere in the game.** All four ids are registered, the
`Music` bus exists, `play_music()` is written and works — and nothing has ever
called it. That is four sound files *and* four call sites, which makes music the
largest single piece of work on this page, not the smallest.

Where each would go: `music_menu` on the login and character-select screens,
`music_town` and `music_field` from the area transition (`AreaRegistry` knows
which area is being entered, so one call in the world scene's `_ready()` covers
both), and `music_crypt` in the boss arena. `play_music()` already ignores a
request for the track that is playing unless `restart_if_same` is set, so
calling it on every scene load is safe and is the simplest wiring.

---

## What the suite does about all this

`_test_audio_paths()` in `src/tools/testrunner.gd`:

- **Every id anything plays must be in `SOUNDS`.** This is the `cook` failure,
  caught for good. It reads every string literal inside an `Audio.play*(...)`
  call, from comment-stripped source, so both branches of a ternary count. It
  cannot see an id held in a variable; there is no such call today.
- **Every filled slot must point at a file that exists.** A path typed wrong is
  silent until the sound is triggered in a running game, and then it is a
  `push_warning` nobody reads.
- **Zero assigned is a skip. All assigned is a pass. Anything in between
  fails**, and names what is still empty.

That middle case is the one worth having. Nobody ships a game and fails to
notice it makes no noise at all; what ships unnoticed is twenty-six sounds
assigned and five forgotten, because the boot line still prints a number and
nothing reads it.

- **Registered and never played is printed, not failed.** Six ids are in that
  state today. They are hooks not yet written rather than mistakes, and a check
  that went red on day one for all six would be switched off within a week.
