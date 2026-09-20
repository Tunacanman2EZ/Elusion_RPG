# Elusion RPG

A top-down 2.5D action RPG built in Godot 4.6 with GDScript, backed by a Flask account service. Four playable classes, six enemy families in forty-three elemental variants, collectable combat pets, fishing and cooking, player-to-player trading over a taxed economy, and a complete run from town to final boss.

![The final boss: two independent attack tracks telegraphing and erupting](docs/boss.gif)

*The boss telegraphs in red, then erupts. Two attack tracks run on separate timers and never sync, so the pattern you are dodging is emergent rather than authored — and each spike leads you by its own telegraph time, which means a volley deforms in flight instead of landing where you were.*

## The run

Register or log in → pick one of four class slots → town → leave town for the field → take the ladder down to the boss floor → defeat the boss → easter egg → game over → restart at town.

It is short on purpose. It has a beginning, an escalation, an ending, and a loop back to the start.

## What's interesting in here

The parts I'd point a reviewer at first.

### The client does not own the save — `src/systems/savestorage.gd`, `src/systems/serverstorage.gd`

`CharacterData` holds a `SaveStorage` and never asks which implementation it has. That seam is what let the game move from a local file to the Flask service without touching the twenty-nine places that call `save_data()`. The server is the authority now — it owns level, XP, the derived stat maxima and every loot roll — so the anti-tamper passes that existed to defend a local file against a text editor are skipped rather than run against data they can no longer say anything useful about. Writes are still debounced: saving on every stat change was firing about twenty times a second in normal play.

### Enemies that form up instead of stacking — `src/enemies/baseenemy.gd`

Pathfinding runs on `NavigationRegion2D`, but the interesting part is slot claiming: each enemy reserves a specific tile in the ring around the player and paths to that, so a group arranges itself around you rather than piling into one spot. Movement stays strictly 4-directional despite using real pathfinding underneath.

### One entity, two forms — `src/enemies/poisonslime.gd`

The poison slime duplicates once when you get close, then each copy converts into four smaller slimes at half health. Large and small are the same scene and the same script — a single `is_small` flag selects the animation set, the projectile, the stat block, and whether the duplicate and split paths are available at all. Its acid leaves ground hazards that stack, so the fight is about position rather than damage.

### One sheet, seven creatures — `src/shared/element.gd`, `src/shared/puddles.gd`

Six enemy families exist as forty-three variants, and none of the extra art was drawn. A shader rotates the hue of a sprite's chromatic pixels and leaves its near-greys alone, so a green slime becomes a blue one without the black outline turning blue with it. There is a second, opposite shader for the boss: its spike is 84% grey rock, so hue rotation repaints sixteen highlight pixels and leaves the stone unchanged — that one tints the pixels *below* a saturation threshold instead. Which shader an asset takes was decided by measuring the sheet, not by eye, and both files carry the measurement.

What keeps that from reading as seven coats of paint is that the colour is the least of it. Three separate layers decide what an element *is*, and they are deliberately orthogonal:

```
data/enemies/icebushsniper.tres     how hard it hits, how much HP   — a difficulty tier
scene/projectiles/icearrow.tscn     speed 320, scale 1.25           — how the shot moves
scene/projectiles/icepuddle.tscn    5.0s, 2 damage a tick           — what it leaves behind
ELEMENT_PROFILE in bossprojectile.gd   1.35 telegraph, 1.25 size    — how the boss's spike reads
```

Damage and HP rank identically in every family, because that axis is the tier ladder. Element character is the *other* axis: ice is slow, large and reaches furthest; wind is fast, small and brief; light is the quickest thing in the game and dark is the one you struggle to track. An ice arrow, an ice vine and an ice boss pillar all say the same thing about ice, which is what makes it learnable rather than decorative.

The fifty-seven variant scenes each author their own material rather than building one at spawn. A `Material` is a `Resource`, so one authored in a scene is shared by every instance of it — which means a boss cast that erupts sixty-five spikes now allocates nothing, where it used to allocate sixty-five. Two small registries map a base scene to its elemental variant, keyed on the base's `resource_path` so an `@export` pointed at something custom passes through untouched, and an element with no scene of its own falls back to the original and is recoloured at runtime. A missing file degrades; it does not break.

Ground hazards are the part that needed arithmetic rather than taste. A sixty-five-pillar cast every 2.16 seconds would cover 44% of the arena in standing acid if every pillar left one, so the roll is held at a third of that. Area goes as the square of scale, and two of the multipliers in that table exist purely to pay for a scene's size or spread rather than to express anything — water leaves three pools per roll, ice's pool is 1.56× the area — which is written down beside both of them, because a number that looks like character and is actually compensation is the kind that gets "tidied" back to 54% floor coverage a year later.

### An economy that has to balance — `gold_ledger` (API repo), `src/ui/trade/tradepanel.gd`, `src/ui/kingdom/kingdomboard.gd`

Players can trade with each other, which is the point at which "the server owns the items" stops being enough. Two clients can now cooperate, and a duplication bug between them mints currency rather than moving it.

So gold is double-entry. Every creation and every destruction writes a row to `gold_ledger`, and one equation has to hold at all times:

```
SUM(gold_ledger.delta)  ==  SUM(saves.gold) + SUM(accounts.bank_gold)
```

The subtle part is what does **not** write a row. A player-to-player transfer creates nothing and destroys nothing — both purses are already inside the right-hand sum — so routing it through the ledger would net to zero and still pass. That makes the invariant alone a weak test, and `test_economy.py` asserts row *counts* and the minted total alongside it for exactly that reason. The suite mutates the ledger deliberately to confirm the check fails when it should.

It is also the kind of guarantee that can be true and useless at the same time, and I found that out the hard way. The invariant held across 268 tests while one endpoint let any player write their own balance directly — because every one of those tests reached the economy through a server path and then checked the books, and none of them tried the balance itself. The suite now attacks it head-on. An invariant only tells you about the paths somebody walked.

Trades are taxed, and the tax is the one place gold genuinely leaves the world. You are charged on what you **receive**, valued from the item table, gold included, and it is taken after the swap so gold you just received can pay for it. It rounds up with a floor of 1, which means splitting one trade into five is strictly more expensive than doing it once — the rounding is the anti-avoidance rule, not an accident of integer maths.

A sink nobody can see is a tax; a sink with a scoreboard is a contribution. `GET /api/economy/kingdom` sums those rows into a leaderboard, and the board recomputes on request rather than counting into a running total — a second place the truth lives is a first disagreement nobody can resolve.

Both sides confirm before anything moves, and a trade that fails validation at execution is refused through one path that marks it dead for *both* players. That one came out of a test I wrote speculatively: `db.rollback()` undoes the confirmation made in the current request and not the one the other player committed minutes ago, which left trades stuck half-confirmed until `_trade_refuse()` existed.

### Real accounts, not a local profile gate — `src/systems/api.gd`

Passwords are salted and hashed server-side; the client holds a bearer token and never sees a hash. Login and "no such user" return an identical 401 so the endpoint can't be used to enumerate usernames. Admin is a database column, not a username comparison running on the player's own machine.

### Composition where inheritance would have been wrong — `src/pets/pet.gd`

A pet is a shrunk, ally-flipped enemy, so inheriting `BaseEnemy` looks obvious. It isn't: a pet follows an owner and picks targets, an enemy chases and leashes home. `Pet` is its own `CharacterBody2D` with every combat value exported, and the two share nothing but a shape.

### Frame-accurate combat — `src/enemies/bushsniper.gd`, `src/enemies/poisonslime.gd`

Projectiles are released on a specific animation frame rather than at the start of the swing, so the shot leaves the sprite at the moment the art throws it.

### Gathering that the server owns outright — `src/world/fishingspot.gd`, `src/ui/cooking/cookingscreen.gd`

Fishing and cooking are the first two skills the client cannot lie about. The rod and bait are checked, the catch is rolled and the XP granted by the server against items it consumed itself; `PUT /api/character/skills` then *drops* fishing and cooking from whatever the client sends, because a client's next routine sync would otherwise overwrite a grant the server just made. The fishing spot draws its own tell — ripples that fade in by proximity — in `_draw()` rather than using art.

### An audit I ran against my own API — `SECURITY_NOTES.md` (API repo)

I attacked my own server as a logged-in player with a modified client and wrote down what I got away with, then kept the file honest as the code moved. Ten findings now, each rated, each with a fix: six closed, one partly closed, two open and still listed because naming them is the point.

The one I'd actually point at is **E-8**, because I found it by accident. Every other finding came from attacking the API deliberately; that one turned up while wiring an unrelated endpoint. `gold` was a writable field on the status endpoint and had never been marked server-owned, so one request set any balance a player liked and the supply invariant broke on the spot. What makes it worth writing down is *why the tests missed it*: all 268 of them moved gold through a server path and then asserted the books balanced. None tried the front door of the balance itself.

It happened twice. **E-10** is the same mistake one endpoint over: lusions were client-written too, and since reviving after death is the only thing lusions are for, dying was free for anyone who skipped one line. After the second one the question stopped being "is this endpoint safe" and became "which fields can a client still write, and who decided that" — which is a list now rather than an assumption.

Player trading arrived after the audit and gets its own section there, because it is the first feature where two clients can cooperate against the server rather than one lying alone. The login endpoint that came out of it throttles per account *and* per source address — the second one because eight consecutive misses on one account does nothing about one host trying the same password against a thousand usernames.

### Data-driven items — `src/systems/itemregistry.gd`, `src/types/itemdata.gd`

`ItemData` resources are scanned from `data/items/` at startup and indexed by id. Item definition (`ItemData`) is deliberately split from instance state (`ItemStack`), so saves store only `{item_id, quantity}` and rehydrate against the registry on load. Drop a new `.tres` in the folder and it exists.

Items carry two independent requirements, and the split is the interesting part. `required_level` is character level, which is right for gear you **buy** — the ladder a shop sells against. `required_skill` / `required_skill_level` is a named skill, which is right for things you **made**: a cooked shark is gated on cooking, not on how many slimes you killed, because fishing and cooking grow on their own curves and a character level bound would clamp a dedicated cook. An unknown skill name is loud and permissive — it logs an error and lets the use through, because failing closed on a typo would silently delete an item's usefulness.

## Layout

```
src/
  characters/    player base + the four classes (warrior, mage, tank, healer)
  enemies/       BaseEnemy and its subclasses, including the multi-phase boss
  pets/          the companion system
  projectiles/   arrows, acid, vines, slash waves, ground hazards
  shared/        facing and formation helpers, the element table and its two
				 shaders, and the base-scene -> elemental-variant registries
  systems/       save/load, item registry, API client, game state, audio
  tools/         editor-only: the game-data exporter and the in-engine test runner
  types/         the Resource definitions — ItemData, EnemyData, ClassData, ItemStack
  ui/            HUD, inventory, bank, shop, cooking, trade, kingdom board,
				 loot bag, character select, login
  world/         ladders, portals, shops, fishing spots, firepits, loot bags
scene/           the .tscn side of all of the above
data/items/      ItemData resources — the item database (123 of them, in eight
				 categories: amulets, armour, consumables, fishing, gold,
				 lusions, pets, weapons)
data/enemies/    EnemyData resources — stats and drop tables, one per variant
data/classes/    ClassData resources — the per-class stat curves
data/gamedata.json  generated by src/tools/exportgamedata.gd; the server reads it
docs/            design notes
```

Three files carry most of the complexity and are the best places to start reading: `src/enemies/baseenemy.gd` (the shared enemy brain), `src/enemies/bossenemy.gd` (two independent attack tracks that never sync, so what you dodge is emergent rather than authored) and `src/systems/characterdata.gd` (everything a character is, and the seam the server took over).

## Running it

The game: open the project in Godot 4.6 and press <kbd>F5</kbd>.

The account service is a companion Flask app in its own repository. Start it before launching the game — the game expects it at `http://127.0.0.1:5000` (set in `src/systems/api.gd`).

```bat
cd <your-path>\game\api
.\venv\Scripts\python.exe app.py
```

```bash
# macOS / Linux
cd <your-path>/game/api
./venv/bin/python app.py
```

Calling the virtualenv's interpreter directly is deliberate: it skips having to activate the environment and guarantees you're on the venv's Python rather than whatever `python` happens to resolve to on `PATH`.

That serves forty-two endpoints — accounts and sessions, character saves, the shared bank, combat kills, loot, the vendor, fishing and cooking, item use, reviving, player trading, the kingdom ledger and staff tools — plus interactive Swagger docs (via flasgger) at `http://127.0.0.1:5000/apidocs`, which is the quickest way to see the whole surface at once.

Thirty-nine of the forty-two require a bearer token. The three that do not are `register`, `login` and `status`, and that is the whole public surface.

The backend has five test suites, run individually and all green together:

```
test_api.py        422 checks    the endpoint surface
test_economy.py    279 checks    the gold ledger and the supply invariant
test_security.py   131 checks    the audit's findings, held closed
test_throttle.py    44 checks    login lockout, per-IP spray, token rotation
test_gathering.py   44 checks    fishing and cooking authority
				   ───
				   920 checks, 0 failures
```

Each suite points `ELUSION_DB` at a throwaway file before importing `app.py`, so running them never touches the real database.

Note this is Flask's development server (`app.run(debug=True)`), which is right for local play and wrong for anything public; a real deployment would sit behind a WSGI server.

Without the service running, the login screen will tell you it can't reach the server — the game does not fall back to local accounts by design.

## Status

The single-player build is complete and playable start to finish.

Authority has moved off the client. The server rolls every loot drop with entropy the client never sees, owns level and XP and the stat maxima they imply, holds loot bags as rows the game renders a copy of — taking an item out of one is a request, not an announcement — and now reconciles the backpack against what it actually granted, so a modified client's fabricated items are trimmed to nothing.

Gold is double-entry on top of that. Every coin that enters or leaves the world writes a ledger row, players can trade with each other, and the trade tax is the first deliberate sink — with a public board showing where the money went, because an invisible sink is just a tax.

Item use is server-authoritative too now — the server checks the level and skill requirement against the character it owns and destroys the item itself, so the gates stopped being advisory the day trading made them matter. So is reviving: the server refuses anyone who is not dead by its own reckoning, takes the cost in lusions itself, and restores the resources from the class curve, which is what puts a price back on dying.

Three gaps remain, all named and tracked in the API repo's `SECURITY_NOTES.md`: three of the six skills still have no server-side XP grant (fishing, cooking and attack do), current health is still written by the client, and the kill *event* is still asserted rather than verified. The last two are the same problem wearing different hats — the server does not watch the fight. Health is at least measured now: an unexplained rise is logged against what regeneration and an authorised potion could account for, which is the same shadow-mode staging the backpack fix used before it started refusing anything.

`devlog.md` records the architecture decisions and the reasoning behind them, including the ones that turned out to be wrong.

## License

Code is MIT licensed — see [LICENSE](LICENSE).

Art, graphics and audio are **not** covered by that license, and some of it belongs to someone else. See [assetlicense.md](assetlicense.md) before doing anything with the files under `art/` or `assets/`. If you'd like to contribute assets, read [docs/ASSET_CONTRIBUTOR_AGREEMENT.md](docs/ASSET_CONTRIBUTOR_AGREEMENT.md) first.
