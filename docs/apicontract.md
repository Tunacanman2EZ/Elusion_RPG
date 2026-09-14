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

`{ "username": "...", "password": "..." }` → **`201`** with a token.
**`400`** on a short password or illegal username characters.
**`409`** if the username is taken.

### `POST /api/auth/login`

Same body → **`200`** with a token. **`401`** on failure.

A wrong password and an unknown username return an **identical** 401. That is
deliberate: a distinguishable answer turns this route into a username
enumerator.

### `GET /api/auth/session`

**`200`** if the token is still good, **`401`** if not. The client calls this
on boot to decide whether it can skip the login screen.

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

`level` is **not** writable here — see *Who owns what*. A new character starts
at 1 and only a kill moves it.

**`active_pet_id` is left alone when the key is absent.** Omitting it does not
unequip the pet. That distinction matters more than it looks: a pet is a
1-in-216 drop, so "which pet is out" is the single most expensive field in the
table to lose, and the obvious implementation — treat a missing key as empty —
would silently unequip it on the next save from any caller that did not send it.

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

### `PUT /api/character/inventory`

```json
{ "slot": 0, "inventory": [ { "item_id": "ironsword", "quantity": 1 }, null ] }
```

**Positional.** The array is `INVENTORY_CAPACITY` (20) cells long with `null`
in every empty one, and the index *is* the grid cell. Returning a packed list
would make the client responsible for rebuilding the gaps; it would get that
right the first time and wrong the first time someone changed the capacity.

`item_id` matches an `ItemData` id from `data/items/`. The server stores the id
and the quantity and nothing else — item definition stays client-side, and the
server never needs to know what an iron sword *is*.

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
whole point of the feature: carry gold and carry items are lost when you die,
so the bank is where you put what you do not want to lose, and it is shared so
a second character can use what the first one banked.

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

### `PUT /api/account/bank`

`{ "bank_inventory": [ ... ] }` → **`200`** with the account as stored.
**`400`** on an oversized array or a malformed entry.

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
  "attack_xp_gained": 5,
  "levels_gained": 1,
  "level": 8, "xp": 40, "xp_to_next": 240,
  "pet_won": false,
  "contents": [ { "position": 0, "item_id": "smallamountofgold", "quantity": 19 } ]
}
```

An empty `bag_id` means nothing dropped and the client spawns no bag. **Every
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
`Api._describe_api_error()` (`src/systems/api.gd:385`) already reads both forms.

---

## Write timing

Stats change constantly — hp on every hit, xp on every kill — so the client
does not push per change. `CharacterData.save_data()` marks state dirty and a
`SAVE_DEBOUNCE_SECONDS` (2.0) countdown collapses the burst into one write.
Logging out flushes any pending save first, because the countdown would
otherwise never fire.

On top of that, `ServerStorage._put_if_changed()` fingerprints each body and
skips the request entirely when nothing in that section changed. One save
therefore costs between zero and six requests rather than always six — which is
why a normal play session shows `PUT /api/player/status` constantly and
`PUT /api/character/inventory` only when the bag actually moved.
