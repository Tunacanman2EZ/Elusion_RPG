# Elusion API contract

The agreement between the Godot client (`Elusion_RPG`) and the Flask service
(`game/api/app.py`). Two repositories, one shape. Change this file first, then
change both sides to match.

Base URL is `http://127.0.0.1:5000`, set in `src/systems/api.gd:32`.

---

## A warning that has already cost a day

**Godot parses every JSON number as a `float`.** There is no integer type in
JSON and Godot does not guess one. So `88` on the wire arrives as `88.0`, and
because Godot's comparisons are type-strict, `88.0 != 88` and a Dictionary
keyed on one will not match the other.

This exact thing caused a save-rewrite loop earlier in this project: the
sanitizer cast to `int`, compared against the parsed `float`, decided all 112
fields had changed, and rewrote the save on every single load.

Every integer this contract describes must go through a coercion on the way in.
`ServerStorage._int()` and `Combat._int()` are that coercion. Nothing else is
safe.

---

## Who owns what

This is the part to read first. It is what the rest of the contract is shaped
around, and it changed after the endpoints below were first written.

**The server owns these, and ignores the client if it sends them.**

| Field | Why |
|---|---|
| `level`, `xp`, `xp_to_next` | Granted by `POST /api/combat/kill` and nowhere else. |
| `max_hp`, `max_mana`, `max_stamina` | *Derived*, not merely owned — recomputed from class and level on every status write, using the curve in `data/classes/*.tres`. |
| Loot rolls | `random.SystemRandom`, server-side. A Mersenne Twister is reconstructible from 624 observed outputs; a loot table is a very long game. |
| Loot bag contents | Rows in `loot_bags` / `loot_bag_items`. The client renders a copy. |

Those fields are **ignored, not refused**. A 400 would break every honest save,
because the client pushes its whole status block and has no way to know which
fields the server has taken ownership of since. Dropping them silently and
naming them in an `ignored` array lets an honest client carry on and gives a
dishonest one nothing.

**The client still asserts these.** `hp`, `mana`, `stamina`, `gold`, the
backpack, the bank and the skill table are all written from whatever it sends.
The backpack is the remaining gap: `POST /api/loot/take` closed where items
*come from*, but the ledger they land in is still client-declared.

---

## Authentication

Every endpoint below requires a bearer token except `POST /api/auth/register`,
`POST /api/auth/login` and `GET /api/status`:

```
Authorization: Bearer <token>
```

Obtained from `POST /api/auth/login`, handled already by `Api.login()`
(`src/systems/api.gd:235`). A missing, invalid or expired token returns `401`
with `{"error": "Unauthorized", "message": "..."}`.

---

## Accounts

### `POST /api/auth/register`

`{ "username": "...", "password": "...", "install": "<64 hex>" }` → **`201`**
with a token. **`400`** on a short password or illegal username characters.
**`409`** if the username is taken. **`403`** "New accounts cannot be created
from this connection." or "...from this computer." when the address, or the
computer, has been used by an account under a live ban.

`install` is this copy of the game's id (`Api.install_id()`, kept in
`user://install.cfg`), sent with register, login and resume. Optional: a
missing or malformed one is ignored, never refused. The server keeps only its
hash, and uses it for that 403 and for the staff view's "same computer" links.

Only the login screen's **Create an account** form calls this. Signing in never
does: it used to fall back to registering the name on a 401, so a typo in your
own name made a new, empty account.

### `POST /api/auth/login`

Same body, `install` included → **`200`** with a token. **`401`** on failure.

A wrong password and an unknown username return an **identical** 401. That is
deliberate: a distinguishable answer turns this route into a username
enumerator. The game says "Wrong name or password" for it.

The miss that locks an account (`LOGIN_MAX_ATTEMPTS` in a row) is **`429`**
"Too many failed attempts. Try again in 15 minutes." - as is every attempt
until the lock runs out, the right password included. Waits are in minutes.

**One login at a time.** A `200` ends every other session the account holds.
The game left behind is refused on its next request with:

```json
{ "error": "Unauthorized", "signed_in_elsewhere": true,
  "message": "This account signed in somewhere else, so this game was signed out." }
```

and goes back to the login screen saying so (`Api.signout_notice_for()`). Two
games on one account used to lose items: each held its own picture of the bag,
and the bag write replaced the whole bag. (It no longer does - the bag is
changed one cell at a time - but one login at a time stays.)

**Staff accounts take a second step.** For a mod, dev or the owner with a
confirmed recovery address, on a server that can send mail, a correct password
answers **`202`** with no token:

```json
{ "code_required": true, "sent_to": "t****n@example.com", "expires_in": 900,
  "message": "Staff login: we emailed a code to t****n@example.com." }
```

The same body sent again with `"code": "183774"` gets the ordinary **`200`**.
A wrong, spent or expired code is **`400`** with `"code_required": true` -
never 401, because the game reads a 401 as "wrong name or password".
Sending no code asks for a new one (at most one a minute). A 200 carries
`"staff_unprotected": true` when a staff account got in on the password alone.
`Api.login(user, password, code)` and `Api.needs_login_code()` handle it.

**Once per computer.** The `200` for a login that got in with a code also
carries `"device_token"`. Sent back as `"device"` with a later login from the
same computer, it lets a staff login through with no code: for 30 days, at
the rank the account had when the code was typed, and until a password
change, a recovery reset or `logout-all`. Only its hash is stored, and it is
checked after the password and the ban. The game keeps it per account in
`user://devices.cfg`.

### `GET /api/auth/session`

**`200`** if the token is still good, **`401`** if not. This is the heartbeat,
every 15 seconds in the world; a 401 there is how a kick, a ban or a login
somewhere else reaches the game.

### `POST /api/auth/resume`

What the game calls on boot when it has a remembered login, with
`{ "install": "..." }` as its body. **`200`** with the
same fields as `/api/auth/session` plus a **new `token`**, which ends when the
old one would have (resuming never renews a login). Every other session on the
account ends - including the one it came in on - so a second copy of the game
that found the same remembered token is signed out, with `signed_in_elsewhere`.
A server without this route answers 404 and the game falls back to
`GET /api/auth/session`.

"Remember me" decides whether the token is written to `user://session.cfg` at
all (`Api.keep_signed_in`). With it off, closing the game signs you out.

### `POST /api/auth/logout`

**`204`**. Invalidates the presented token.

---

## Character slots

### `GET /api/save`

Every character slot on the account. Backs the character-select screen.

```json
{
  "username": "Tunacan",
  "slots": [
    {
      "slot": 0,
      "class_id": "warrior",
      "name": "Tunacan",
      "level": 12,
      "area": "elusion",
      "active_pet_id": "petpoisonslimesmall",
      "updated_at": 1788900000
    }
  ]
}
```

`slots` contains **occupied slots only**. An account with nothing saved returns
`"slots": []`. The client renders four buttons regardless and marks the missing
ones empty — the server does not pad the list.

`slot` is `0..3`. `class_id` is one of `warrior`, `mage`, `tank`, `healer`.

### `PUT /api/save`

Write one slot. Upsert: writing an occupied slot overwrites it.

```json
{ "slot": 0, "class_id": "warrior", "name": "Tunacan", "area": "elusion" }
```

**`200`** — `{ "slot": 0, "updated_at": 1788900000 }`.
**`400`** on a bad slot, unknown class, empty name, or a malformed
`active_pet_id`.

`name` is shown to other players, so it goes through the same
`clean_player_text()` as chat (see *Chat* below): line breaks and tabs become
spaces, invisible format characters are dropped. A name that is nothing once
cleaned is an empty name, and a `400`.

`level` is **not** writable here — see *Who owns what*. A new character starts
at 1 and only a kill moves it.

**`active_pet_id` is left alone when the key is absent.** Omitting it does not
unequip the pet. That distinction matters more than it looks: a pet is a
1-in-216 drop, so "which pet is out" is the single most expensive field in the
table to lose, and the obvious implementation — treat a missing key as empty —
would silently unequip it on the next save from any caller that did not send it.

### `POST /api/character/delete`

Delete one of your own characters, for good.

```json
{ "slot": 1, "confirm": "mage" }
```

`confirm` is the character's name as the player typed it, in any case. The
game asks for it before sending, and the server checks it again.

**`200`** — `{ "slot": 1, "deleted": true, "gold_lost": 345, "items_lost": 3 }`.
The save, the bag, the skills, the loot bags and the heal grants go. The
carried gold is burned through the ledger (reason `character-deleted`). The
bank, the lusions and everything else on the account stay.
**`400`** on a bad slot, or a `confirm` that is not the character's name.
**`404`** when the slot is empty. There is no way to name another account's
character: the slot is always yours.
**`409`** while an open trade names this character, from either side.

The server keeps a copy of what was deleted in `character_deletions` (the
newest ten per account), for putting a character back by hand. Nothing reads
it automatically.

---

## Live stats

### `GET /api/player/status?slot=0`

Deliberately separate from `/api/save`: the save is what you are, this is how
you are doing right now, and the two change at completely different rates.

```json
{
  "slot": 0,
  "level": 12,
  "hp": 88,          "max_hp": 120,
  "mana": 30,        "max_mana": 60,
  "stamina": 45,     "max_stamina": 50,
  "gold": 1450,
  "xp": 15320,       "xp_to_next": 2100
}
```

**`404`** if that slot is empty. The client treats this as "no character
there", not as an error.

### `PUT /api/player/status`

**Partial**: only the fields present are written, so a caller that knows
nothing about stamina can push `hp` without zeroing it.

```json
{ "slot": 0, "hp": 88, "gold": 1450 }
```

Writable: `hp`, `mana`, `stamina`, `gold`.
Ignored and echoed back in `ignored`: `level`, `xp`, `xp_to_next`, `max_hp`,
`max_mana`, `max_stamina`.

**`200`** — the full status, same shape as the `GET`, plus `"ignored": [...]`
when anything was dropped.

**`400`** if a writable value is not a non-negative integer no greater than
1,000,000,000, if no writable field was supplied at all, or if `hp` would
exceed `max_hp` (same for mana and stamina).

That last check runs against the **merged** state, not against the request
alone — and against the maximum the *server* computed, not one the client sent.
The maxima are recomputed from the class curve before any validation happens,
specifically so that a client declaring `max_hp = 999999` alongside
`hp = 999999` cannot pass the paired check on its own say-so.

Values are **refused, not clamped**. A clamp silently absorbs the bug that
produced the bad number; a 400 tells you it happened.

---

## One character, in full

### `GET /api/character?slot=0`

Identity, vitals, backpack and skills in a single call.

```json
{
  "slot": 0,
  "class_id": "warrior",
  "name": "Tunacan",
  "area": "elusion",
  "active_pet_id": "",
  "status":    { "...": "as GET /api/player/status" },
  "inventory": [ { "item_id": "ironsword", "quantity": 1 }, null, "..." ],
  "skills":    { "attack": { "level": 3, "xp": 40 }, "...": "..." }
}
```

One call, not four. Loading a character used to mean status, then inventory,
then skills, then bank — four round trips on a screen the player is staring at.
They are all keyed on the same `(user_id, slot)` and none of them is useful
without the others.

### The backpack is the server's: one cell at a time

The carry is a **positional** array, `CARRY_CAPACITY` (30) cells long with
`null` in every empty one, and the index *is* the cell: the bag's
`INVENTORY_CAPACITY` (20), then the hotbar's ten keys, 1-9 then 0. Every route
that changes it answers with the whole array, and the game draws that.

**Nothing is placed on a key.** Loot, the shop, withdrawals, trades, catches
and grants only top up or open cells below 20. "Your backpack is full" means
the twenty. A key holds what the player put there.

**Every change the player makes is its own request**, carried out on the
server's cells. Each names the item the game saw in the cell; when the cell
holds anything else - a trade or a loot take landed - nothing changes and the
answer is **`409`** with `resync`: `{"slot", "gold", "inventory", "trade":
null, "reason": "stale_save"}`, which the game adopts without a message.

| Route | Body | Does |
|---|---|---|
| `POST /api/character/inventory/move` | `{slot, from, to, item_id}` | A drag: onto an empty cell it moves, onto the same stackable item it merges up to the stack limit (the rest stays), onto anything else it swaps. Keys are cells 20-29 like any other. |
| `POST /api/character/inventory/discard` | `{slot, position, item_id}` | The bin: the whole stack in that cell is destroyed. Answers `discarded`. |
| `POST /api/character/inventory/cash` | `{slot, position, item_id}` | A pile of gold coins, or of lusions: the cell is emptied and the balance credited through the ledger. Answers `gold`, `lusions` and `cashed`. `409` "That is not money." for anything else. |
| `POST /api/shop/sell` | `{slot, shop_id, position, item_id, quantity?}` | Sell to a vendor: `quantity` from that cell (the whole stack when left out) at the shop's price, which `GET /api/shop/<shop_id>` lists as `sell_prices` (item_id -> gold each; a rolled piece sells at its catalogue id's price). The gold is minted through the ledger (reason `shop_sell`). Answers `gold`, `inventory`, `unit_price` and `total_received`. `400` "The shop does not buy that." for money, pets and quest items; more than the cell holds is the same `409` with `resync`. |

`POST /api/character/consume`, `POST /api/character/equip` and
`POST /api/bank/items` take an optional `position`: the cell the player used,
spent first when it holds the item. Without it a take starts at the highest
cell holding the item, which with the keys in the same rows is usually a key.
`consume` answers with `inventory` too.

`item_id` matches an `ItemData` id from `data/items/`. The server stores the id
and the quantity and nothing else — item definition stays client-side, and the
server never needs to know what an iron sword *is*.

### `PUT /api/character/inventory` - kept for older games and staff

`{ "slot": 0, "inventory": [...], "based_on": "..." }`. **A player's array is
ignored**: **`200`** with the bag the server holds and `"ignored":
["inventory"]`. Build 1 of the game sends it on every save, so it is answered
rather than refused; build 2 does not send it. The `409`s a build-1 game relied
on still come first - `based_on` (sha1 of `position:item_id:quantity` per
filled cell, joined with `|`) naming a bag the server no longer holds, or a
trade it has not been told about. **Staff** (mod and up) still write the bag
whole, for tooling: a twenty-cell array replaces the bag and leaves the keys.
**`400`** on an oversized array or a malformed entry. **`404`** if the slot is
empty.

### `PUT /api/character/skills`

```json
{ "slot": 0, "skills": { "attack": { "level": 3, "xp": 40 } } }
```

Valid ids: `attack`, `magic`, `agility`, `defense`, `fishing`, `cooking`.
Note **`defense`**, not `defence` — the client spells it the American way and
the server must match, or every write 400s.

`xp_next` is deliberately **not** sent. It is a pure function of the skill
level, and shipping it would be a second copy of the growth curve to keep in
step with the client's. `CharacterData` recomputes it on load.

An unknown skill id is **refused**, not dropped. A silently ignored skill is a
level that quietly stops saving.

---

## Account-shared state

The bank and lusions belong to the **account**, not to a character. That is the
whole point of the feature: carry gold, carry items and everything worn are lost
when you accept death (`POST /api/character/respawn`, which answers `gold_lost`
and `gear_lost`; a paid revive keeps it all), so the bank is where you put what
you do not want to lose, and it is shared so a second character can use what the
first one banked.

### `GET /api/account`

```json
{
  "lusions": 120,
  "bank_gold": 4500,
  "bank_inventory": [ { "item_id": "ironsword", "quantity": 1 }, null, "..." ],
  "capacity": 50
}
```

`bank_inventory` is positional and `capacity` cells long, same rule as the
backpack — the player expects things to stay in the cell they dragged them to.

### The bank, one cell at a time

Items go in and out through `POST /api/bank/items` (`op` deposit or withdraw).
Inside the bank, the same two as the backpack, with no `slot` - the bank is the
account's:

| Route | Body | Does |
|---|---|---|
| `POST /api/bank/move` | `{from, to, item_id}` | Move, merge up to the stack limit, or swap. |
| `POST /api/bank/discard` | `{position, item_id}` | Destroy the whole stack in that cell. |

Both answer with the account, `bank_inventory` included; a cell that does not
hold `item_id` is **`409`** with the account under `account`, and nothing
changes.

### `PUT /api/account/bank`

`{ "bank_inventory": [ ... ] }` → **`200`** with the account. **A player's
array is ignored** (`"ignored": ["bank_inventory"]`), for the backpack's
reasons; staff still write it whole. **`400`** on an oversized array or a
malformed entry.

### `PUT /api/account/lusions`

`{ "lusions": 120 }` → **`200`**. **`400`** if not a non-negative integer.

### `POST /api/bank/gold`

Gold is a **separate endpoint from items**, and the reason is the interesting
part of this whole contract.

Storing an item is a one-sided write. The server never sees your inventory, so
it can only record what it was handed; it cannot tell a real deposit from an
invented one. Gold is a **transfer**, and the server holds *both* balances —
`saves.gold` and `accounts.bank_gold` — so it can verify the move is possible
and that the total is conserved. Folding gold into the bank write would throw
that check away for the sake of one fewer route.

```json
{ "slot": 0, "op": "deposit", "amount": 500 }
```

`op` is `deposit` or `withdraw`. **`200`** returns the carried gold and the
account afterwards. **`400`** on depositing more than is carried, withdrawing
more than is banked, a non-positive amount, or a bad `op`. **`404`** if the
slot is empty.

Both sides move in a single `UPDATE`, so there is no instant where the gold
exists in neither place.

**The game calls it** - `CharacterData.deposit_gold_to_bank()` and
`withdraw_gold_from_bank()`, from the bank panel - and copies `carried_gold`
and `bank_gold` from the answer. Until day 1 nothing did: the panel moved the
two numbers on the client, which the server never heard about, so banked gold
went back to the purse at the next login.

---

## Item ids, and the roll a dropped piece carries

An item id is a catalogue id (`ironsword`) - or, for a piece of gear that
**dropped**, that id with its quality roll after a `~`:

    jadechest~a104h96          armour 104%, max health 96%
    ironsword~d107             damage 107%
    jadeamulet~a120h120m120p120   Perfect: every stat at 120%

One letter per stat the piece has above zero, in this order and only those:
`d` damage, `a` armor_value, `h` bonus_max_hp, `m` bonus_max_mana,
`p` bonus_damage_percent; each percent 85-115, or every one at 120 (Perfect).
The letters, the range and the odds are `GameConstants.QUALITY_*`, exported as
`quality_*` in gamedata.json. Anything else after a `~` is not an item.

- **The server rolls; nothing else names a roll.** Drops roll (bags and the
  mythic), and so does a purchase: the shelf lists the plain id, and
  `/api/shop/buy` answers `item_id` with the roll that arrived and `stock_id`
  with the shelf's id, at the shelf's price. A staff grant takes
  `"quality": "plain" | "roll" | "perfect"` (`"store"` is read as plain).
- **Every route that takes an item takes the id as seen**, roll and all: a
  move, the bin, the bank, equip, a trade offer, a sale. A rolled piece is
  never stacked (its stack is one), and naming the plain id for a rolled cell
  is the same `409` as any stale cell.
- **A stat is the catalogue number at its percent, halves up, in whole
  numbers**: `(number * percent + 50) // 100`. Both sides do exactly this sum,
  because the server derives `max_hp` / `max_mana` from what is worn.
- **A roll changes what a piece does, not its price.** `value` is the
  catalogue's; `sell_prices` and the trade tax use it, keyed by the catalogue
  id.
- **Client build 3** reads rolled ids; a build-2 game shows one as the error
  item.

---

## Combat

### `POST /api/combat/kill`

`{ "slot": 0, "enemy_id": "bushmage" }`

The server rolls the reward, grants the XP, applies any level-ups, and stores
whatever dropped as a bag it owns.

```json
{
  "bag_id": "k3Jx9_QpZ2mNvRt1",
  "enemy_id": "bushmage",
  "xp_gained": 20,
  "attack_xp_gained": 7,
  "attack_level": 4, "attack_xp": 61, "attack_xp_to_next": 164,
  "attack_levelled_up": false,
  "levels_gained": 1,
  "level": 8, "xp": 40, "xp_to_next": 240,
  "pet_won": false,
  "contents": [ { "position": 0, "item_id": "smallamountofgold", "quantity": 19 } ]
}
```

**Attack is banked here, with the class specialty** (`SKILL_PROFICIENCY`: a
warrior 1.5x), and nowhere else - nothing a client does between kills trains
it. `attack_xp_gained` is what was banked; the three `attack_*` fields are where
the skill now stands, and the client sets its attack bar to them rather than
adding up its own.

A piece of gear in `contents`, and the `mythic` named beside them, carries its
quality roll in its id (see "Item ids" above). An empty `bag_id` means nothing
dropped and the client spawns no bag. **Every
entry carries its `position`** — that number is the only thing
`/api/loot/take` accepts, and inferring it from array order on each side
separately is how a client ends up asking for a different item than the one the
player clicked.

A level-up moves the maxima with it, in the same `UPDATE`. Two statements would
leave a window where a crash could bank the XP and lose the level.

**`400`** on a bad slot, an unknown `enemy_id`, or an enemy that awards nothing
(the large poison slime, which splits rather than dying — its worth walks away
as four smalls). **`404`** if the slot is empty.

**`429`** when kills arrive faster than the bucket allows. It is a **token
bucket** — 50 capacity, refilling at 5/second — not a minimum gap between
kills. Real combat is bursty: an AoE or a splitting slime produces several
simultaneous kills, and a minimum gap can never allow a burst no matter how it
is tuned. A player should essentially never see this; if they do, the bucket is
mis-sized, not the player.

---

## Loot

A bag exists on the **server**. The client renders a copy of it, and taking
something out is a request rather than an announcement.

### `POST /api/loot/take`

`{ "bag_id": "...", "position": 0 }`

```json
{
  "bag_id": "...", "position": 0,
  "item_id": "smallamountofgold", "quantity": 19,
  "credited": "gold",
  "granted_item_id": "smallamountofgold", "granted_quantity": 19,
  "bag_empty": true,
  "status":    { "...": "the full status" },
  "inventory": [ "...": "the full backpack" ],
  "lusions": 120
}
```

`credited` is `gold`, `lusions` or `inventory`. When it is `inventory`,
`carry_positions` lists the cells written.

`item_id` is what was **in the bag**; `granted_*` is what the player actually
received. They differ in one case: a pet you already own pays
`dupe_pet_lusions` instead, flagged with `"duplicate_pet": true`. That decision
used to live in `lootbaginventory.gd`, which checked the local inventory and
the local bank — both copies of rows this process owns.

**Balances come back as totals, not deltas.** The client still pushes `gold` on
save, so a client keeping its own running figure that got it wrong once would
overwrite the server's row on the very next write, and the loss would look like
nothing at all.

**`404`** if there is no such bag, it is not yours, or that cell is already
empty — all three are the same answer, which is what makes a duplicate request
harmless: the second one finds nothing and changes nothing.
**`409`** if the backpack is full; the item **stays in the bag** rather than
being dropped on the floor.
**`410`** if the bag has expired.
**`400`** on a bad `bag_id` or a position outside the bag's six cells.

### `GET /api/loot/bag?bag_id=...`

The bag's remaining contents, so a client that reconnects — or one unsure
whether a take landed — can ask rather than guess.

**`404`** if there is no such bag or it is not yours. A bag the server has
already emptied is also a 404, which is the right answer: in both cases there
is nothing to collect.

Bags are honoured for `LOOT_BAG_TTL_SECONDS` (600), deliberately far longer
than the client's 20-second despawn. The client despawning the node is a
display decision; if the two disagree, the player should lose the bag to the
*animation*, never to a 410 from a server that expired it a moment early.

---

## Chat

The chat routes are not listed here in full; `api/CLAUDE.md` is their home.
Two things the client depends on:

**Every line is one line, as typed.** The server cleans chat text before it is
stored (`clean_player_text()`): newlines, tabs and other control characters
become a space, runs of spaces become one, invisible format characters (bidi
overrides, zero-width spaces) are dropped except U+200D, which emoji are built
from, and at most three accents stack on one letter. What is stored is what
every reader gets. A message that is nothing once cleaned is a `400`, like an
empty one. The chat window also flattens what it draws
(`ChatPanel.one_line()`), so a line stored before this rule cannot break the
window either.

**`chat_news` rides the broadcast poll.** `GET /api/server/broadcasts`, which
the HUD polls anyway, carries:

```json
"chat_news": {
  "whisper": { "id": 812, "from": "amy", "body": "you there?", "at": 1788900000 },
  "guild": 811,
  "friends": 790
}
```

The same answer carries **`open_reports`**: the number of reported chat lines
waiting, and **`open_report_players`**: how many players those lines are
about, both for mod and up (`0` for everyone else). The HUD puts the players
on the Staff button (one card each on the Reports tab), and falls back to the
lines from a server without `open_report_players`.

`whisper` is the newest private line sent TO the caller by somebody else
(`null` if none; a picture alone reads `"(a picture)"`). `guild` and `friends`
are the newest line ids in the caller's guild and among their friends, said by
somebody else, `0` when none. The client keeps the last ids it has seen per
login and treats a larger one as news: a whisper pops a message and marks the
Chat button, and a room lights its tab. An older client ignores the key.

**`asks` rides it too**: the friend requests and guild invitations waiting on
the caller's answer, how many of each, and the newest.

```json
"asks": {
  "friends": { "count": 1, "newest": "caster", "at": 1790800000 },
  "guild":   { "count": 0, "newest": "", "at": 0 }
}
```

`newest` is the asker's account name for a friend request and the guild's name
for an invitation. The HUD lights "Friends •" or "Guild •" while a count is
above zero and says the newest once per login, keyed on `at`.

**`POST /api/guild/create` answers with both balances after paying**:
`carried_gold` and `bank_gold`, beside `paid`, `from_carried` and `from_bank`
(`gold` is the carried figure, kept for older clients). The game copies them in
through `CharacterData.adopt_server_gold()`.

**Ignore, report, mute.** Every chat read leaves out the players the caller
ignores, and carries `"muted": null` or `{"until", "seconds_left", "reason"}`
for the caller.

| Route | Body | Answers |
|---|---|---|
| `GET /api/ignores` | | `{"ignored": [{"username", "since"}], "limit"}` |
| `POST /api/ignores` | `{"username"}` | `200`; `400` yourself; `403` staff; `404`; `409` list full |
| `POST /api/ignores/remove` | `{"username"}` | `200` with `was_ignored` |
| `POST /api/chat/report` | `{"id", "reason"}` - spam, harassment, hate, cheating, other | `200` (`already` on a repeat); `400` your own line; `404` a line you were not shown; `429` |
| `GET /api/staff/reports?state=open\|all` | mod | `players`: one card per reported player, worst first - `reported`, `reported_role`, `actionable`, `line_count`, `reports`, `people`, `reporters`, `reasons`, `first_at`, `last_at`, and `lines` (their newest, each in the per-line shape); `reports`: one entry per line - `reported`, `body`, `reports`, `reporters`, `reasons`, `actionable`, `line_exists`; `open` (lines), `open_players` |
| `POST /api/staff/reports/resolve` | mod; `{"message_id", "outcome": "dismissed"\|"actioned"}` or `{"username", "outcome"}` for every open report about a player | `200` (`closed`, or `lines` by player); `404` nothing open, or out of your reach |
| `POST /api/staff/mute` | mod; `{"username", "minutes", "reason"}` | `200` with `reports_closed` (a mute, kick or ban closes the player's open reports as actioned); `403` a mod over a day; `404` out of reach |
| `POST /api/staff/unmute` | mod; `{"username"}` | `200` |

A whisper, friend request or trade to somebody who ignores you is `403` with a
sentence saying so. A muted player's `POST /api/chat/send` is `403` with how
long is left and why.

---

## Seeing each other

Other players are drawn from a WebSocket, not from these routes: `presence.py`
in the API repo, a second process beside the API. `src/systems/presence.gd`
is the client; api/CLAUDE.md ("Seeing each other") and `presence.py`'s header
are the server's side.

### `POST /api/presence/ticket`

`{"slot": 0}` → `{"ticket", "expires_in": 120, "socket_url"}`. `404` with no
character in that slot. The ticket is good for two minutes, once, for this
login; the game asks for a fresh one every minute and sends it as `renew`.
`socket_url` is where to connect: `wss://<the host the API was reached on>/ws/presence`
behind the proxy, so the browser build stays on its own address.

### The socket

JSON text frames. The game sends:

| Message | When |
|---|---|
| `{"t": "hello", "ticket"}` | first, within 5 seconds |
| `{"t": "s", "a", "x", "y", "m", "fx", "pet"}` | where it stands, on a change, at most 10 a second: area id, world position, the body's animation (`idle\|walk\|attack\|death\|hitflash` + a facing), the lit auras (`ring`, `firering`) and the pet out |
| `{"t": "renew", "ticket"}` | every minute |
| `{"t": "sync"}` | after a new scene: tell me who is here again |

The server sends:

| Message | Meaning |
|---|---|
| `{"t": "welcome", "id"}` | in; `id` is your account id |
| `{"t": "join", "p": [{"id", "name", "cls", "lvl", "role", "hue", "guild", "x", "y", "m", "fx", "pet"}]}` | people now in your area (and anyone whose identity changed) |
| `{"t": "moves", "p": [[id, x, y, m, fx, pet]]}` | who moved this tick, ten a second; your own id is in it, skip it |
| `{"t": "leave", "ids": [...]}` | gone from your area |
| `{"t": "bye", "why"}` | then the socket closes: `ticket`, `replaced` (signed in elsewhere), `signed out`, `too fast` |

**Who somebody is comes only from `join`**, written by the API from its own
rows. A state naming a pet the character does not hold shows no pet; a
malformed state is ignored. A second connection on the same account replaces
the first.

---

## Server health

### `GET /api/status`

No auth, deliberately. The login screen needs to ask "are you there?" before
anyone has logged in, and a 401 is not an answer to that question. It is what
lets the client tell "your internet is down" apart from "the host's server is
down".

---

## Error shape

Every failure, everywhere:

```json
{ "error": "Bad Request", "message": "quantity must be a positive integer" }
```

`message` may also be an array of strings for multi-field validation.
`Api._describe_api_error()` (`src/systems/api.gd`) already reads both forms.

**A body holding a lone UTF-16 surrogate (`"\ud800"` with no partner) is not
JSON as far as any route is concerned** — it is legal JSON text, but it cannot
be stored, and it used to reach the database and come back a `500`. It is now
refused while parsing, so every route answers the `400` it gives any body that
is not JSON. No keyboard types one.

---

## Write timing

Stats change constantly — hp on every hit, xp on every kill — so the client
does not push per change. `CharacterData.save_data()` marks state dirty and a
`SAVE_DEBOUNCE_SECONDS` (2.0) countdown collapses the burst into one write.
Logging out flushes any pending save first, because the countdown would
otherwise never fire.

On top of that, `ServerStorage._put_if_changed()` fingerprints each body and
skips the request entirely when nothing in that section changed. One save
therefore costs between zero and three requests rather than always three —
which is why a normal play session shows `PUT /api/player/status` constantly
and `PUT /api/save` only when something in it moved. The bag and the bank are
not in a save at all: each change is its own request (see "The backpack is the
server's").
