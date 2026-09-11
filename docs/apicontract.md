# Elusion API contract

The agreement between the Godot client (`Elusion_RPG`) and the Flask service
(`game/api/app.py`). Two repositories, one shape. Change this file first, then
change both sides to match.

Base URL is `http://127.0.0.1:5000`, set in `src/systems/api.gd:32`.

---

## A warning that has already cost a day

**Godot's `JSON.parse_string()` returns every number as a `float`.** There is no
integer type in JSON and Godot does not guess one. So `88` on the wire arrives
as `88.0`, and because Godot's comparisons are type-strict, `88.0 != 88` and a
Dictionary keyed on one will not match the other.

This exact thing caused a save-rewrite loop earlier in this project: the
sanitizer cast to `int`, compared against the parsed `float`, decided all 112
fields had changed, and rewrote the save on every single load.

Every integer this contract describes must go through `NetClient._as_int()` on
the way in. Nothing else is safe.

---

## Authentication

All endpoints below require a bearer token:

```
Authorization: Bearer <token>
```

Obtained from `POST /api/auth/login`, handled already by `Api.login()`
(`src/systems/api.gd:132`). A missing, invalid or expired token returns `401`
with `{"error": "Unauthorized", "message": "..."}`.

---

## `GET /api/save`

Every character slot on the account. Backs the character-select screen.

**Response `200`**

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
      "updated_at": 1788900000
    }
  ]
}
```

`slots` contains **occupied slots only**. An account with nothing saved returns
`"slots": []`. The client renders four buttons regardless and marks the missing
ones empty — the server does not pad the list.

`slot` is `0..3`. `class_id` is one of `warrior`, `mage`, `tank`, `healer`.

## `PUT /api/save`

Write one slot. Not used by the Net-Test branch — the client only reads — but
the route exists so the read has something to read.

**Body**

```json
{ "slot": 0, "class_id": "warrior", "name": "Tunacan", "level": 12, "area": "elusion" }
```

**Response `200`** — `{ "slot": 0, "updated_at": 1788900000 }`

Upsert: writing an occupied slot overwrites it.

---

## `GET /api/player/status?slot=0`

Live values for the HUD. Deliberately separate from `/api/save`: the save is
what you are, this is how you are doing right now, and the two change at
completely different rates.

**Response `200`**

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

---

## `GET /api/bank?slot=0`

**Response `200`**

```json
{
  "slot": 0,
  "gold": 1450,
  "capacity": 40,
  "items": [
    { "item_id": "ironsword", "quantity": 1 },
    { "item_id": "healthpotion", "quantity": 12 }
  ]
}
```

`item_id` matches an `ItemData` id from `data/items/` — the server stores the
id and the quantity and nothing else, exactly as the local save does. Item
definition stays client-side; the server never needs to know what an iron sword
*is*.

## `POST /api/bank`

One path, one body, both directions.

**Body**

```json
{ "slot": 0, "op": "deposit", "item_id": "healthpotion", "quantity": 5 }
```

`op` is `deposit` or `withdraw`. `quantity` must be a positive integer.

**Response `200`** — the full bank, same shape as the `GET`. Returning the
whole thing rather than a delta means the client never has to guess what the
server did, which is how bank duplication bugs start.

**`400`** on withdrawing more than is stored, or a non-positive quantity.
**`409`** on depositing past `capacity`.

---

## Error shape

Every failure, everywhere:

```json
{ "error": "Bad Request", "message": "quantity must be a positive integer" }
```

`message` may also be an array of strings for multi-field validation.
`Api._describe_api_error()` (`src/systems/api.gd:225`) already reads both forms.

---

## Status

| Endpoint | Server | Client |
|---|---|---|
| `POST /api/auth/register` | done | done |
| `POST /api/auth/login` | done | done |
| `GET /api/auth/session` | done | done |
| `POST /api/auth/logout` | done | done |
| `GET /api/save` | done | done |
| `PUT /api/save` | done | not used |
| `GET /api/player/status` | done | done |
| `GET /api/bank` | done | done |
| `POST /api/bank` | done | done |
