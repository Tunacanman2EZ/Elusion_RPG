# Elusion RPG

A top-down 2.5D action RPG built in **Godot 4.6** with GDScript, backed by a
Flask account service. Four playable classes, six enemy types, collectable
combat pets, and a complete run from town to final boss.

<!-- TODO: put a screenshot here. This is the single highest-impact line in
	 the file — most people decide whether to keep reading from the image.
	 Something mid-combat with the HUD visible beats a title screen.
	 ![Elusion RPG](docs/screenshot.png)                                   -->

---

## The run

Register or log in → pick one of four class slots → **town** → leave town for
the **field** → take the ladder down to the **boss floor** → defeat the boss →
easter egg → game over → restart at town.

It is short on purpose. It has a beginning, an escalation, an ending, and a
loop back to the start.

---

## What's interesting in here

The parts I'd point a reviewer at first.

**Save system that assumes it will be interrupted** — `src/systems/localstorage.gd`

Writes go to a `.tmp` file, the live save is copied to `.bak`, and only then is
the temp file renamed into place. A crash at any point leaves either the old
save intact or the new one complete, never a half-written file. Loads fall back
to the backup automatically. On top of that, `src/systems/characterdata.gd`
adds SHA-256 signing, sanity clamps on every numeric field, schema versioning
with a migration path, and debounced writes (saving on every stat change was
hitting the disk ~20 times a second in normal play).

**Enemies that form up instead of stacking** — `src/enemies/baseenemy.gd`

Pathfinding runs on `NavigationRegion2D`, but the interesting part is slot
claiming: each enemy reserves a specific tile in the ring around the player and
paths to *that*, so a group arranges itself around you rather than piling into
one spot. Movement stays strictly 4-directional despite using real pathfinding
underneath.

**One entity, two forms** — `src/enemies/poisonslime.gd`

The poison slime duplicates once when you get close, then each copy converts
into four smaller slimes at half health. Large and small are the same scene and
the same script — a single `is_small` flag selects the animation set, the
projectile, the stat block, and whether the duplicate and split paths are
available at all. Its acid leaves ground hazards that stack, so the fight is
about position rather than damage.

**Real accounts, not a local profile gate** — `src/systems/api.gd`

Passwords are salted and hashed server-side; the client holds a bearer token
and never sees a hash. Login and "no such user" return an identical 401 so the
endpoint can't be used to enumerate usernames. Admin is a database column, not
a username comparison running on the player's own machine.

**Composition where inheritance would have been wrong** — `src/pets/pet.gd`

A pet is a shrunk, ally-flipped enemy, so inheriting `BaseEnemy` looks obvious.
It isn't: a pet follows an owner and picks targets, an enemy chases and leashes
home. `Pet` is its own `CharacterBody2D` with every combat value exported, and
the two share nothing but a shape.

**Frame-accurate combat** — `src/enemies/bushsniper.gd`, `poisonslime.gd`

Projectiles are released on a specific animation frame rather than at the start
of the swing, so the shot leaves the sprite at the moment the art throws it.

**Data-driven items** — `src/systems/itemregistry.gd`, `itemdata.gd`

`ItemData` resources are scanned from `data/items/` at startup and indexed by
id. Item definition (`ItemData`) is deliberately split from instance state
(`ItemStack`), so saves store only `{item_id, quantity}` and rehydrate against
the registry on load. Drop a new `.tres` in the folder and it exists.

---

## Layout

```
src/
  characters/    player base + the four classes (warrior, mage, tank, healer)
  enemies/       BaseEnemy and its six subclasses
  pets/          the companion system
  projectiles/   arrows, acid, vines, slash waves, ground hazards
  systems/       save/load, item registry, API client, game state
  ui/            HUD, inventory, bank, character select, login
  world/         ladders, portals, shops, interactables
  core/          scene transition, area controllers, loot bags
scene/           the .tscn side of all of the above
data/items/      ItemData resources — the item database
docs/            design notes
```

Two files carry most of the complexity and are the best places to start
reading: `src/enemies/baseenemy.gd` and `src/systems/characterdata.gd`.

---

## Running it

**The game:** open the project in Godot 4.6 and press F5.

**The account service** is a companion Flask app in its own repository. The
game expects it at `http://127.0.0.1:5000` (set in `src/systems/api.gd`):

```bash
python app.py
```

Without it the login screen will tell you it can't reach the server — the game
does not fall back to local accounts by design.

---

## Status

The single-player build is complete and playable start to finish. Active work
is on the multiplayer port toward a persistent online world, with a headless
Godot instance as the authoritative server and Flask continuing to own accounts
and persistence. `devlog.md` records the architecture decisions and the
reasoning behind them, including the ones that turned out to be wrong.

---

## License

Code is MIT licensed — see `license`.

Art, graphics and audio are **not** covered by that license. See
`assetlicense.md`. If you'd like to contribute assets, read
`docs/ASSET_CONTRIBUTOR_AGREEMENT.md` first.
