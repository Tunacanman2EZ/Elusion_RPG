# netclient.gd — the ONE place the Net-Test branch talks to the backend.
#
# WHY THIS EXISTS instead of calling Api directly from each screen:
#
# 1. FALLBACK. This branch is built endpoint-by-endpoint. Every call here
#    answers even when the route doesn't exist yet or the server is down, by
#    returning local placeholder data and flagging it. Screens never have to
#    know whether an endpoint has landed — they render the same either way,
#    and the "LIVE" / "LOCAL" badge tells you which you're looking at. That
#    badge is the whole point of the harness: you watch the screens go live
#    one at a time as the Flask side catches up.
#
# 2. INTEGER COERCION. Godot's JSON.parse_string() returns EVERY number as a
#    float — there is no integer type in JSON and Godot does not infer one. So
#    the server's 88 arrives as 88.0, and because Godot compares type-strictly,
#    88.0 != 88. This already cost this project a day: CharacterData's
#    sanitizer cast to int, compared against the parsed float, concluded all
#    112 fields had changed, and rewrote the save on every load. Every integer
#    crossing this boundary goes through _as_int(). No exceptions.
#
# RESULT SHAPE — every method resolves to:
#   ok     bool       — we have usable data (true even when it came from local)
#   live   bool       — true if it came from the server, false if it's local
#   data   Dictionary — the payload, integers already coerced
#   error  String     — why we fell back, "" when live
extends RefCounted
class_name NetClient


# =============================================================================
# CROSS-SCENE STATE
# =============================================================================

# The slot picked on the select screen, read by the test area after the scene
# change. A static var rather than a field on GameState so this branch never
# touches an autoload that `main` also uses — the entire Net-Test surface stays
# inside src/nettest/ and scene/nettest/, which is what makes it safe to throw
# away or merge wholesale later.
static var selected_slot: int = 0


# =============================================================================
# TYPE COERCION
# =============================================================================

func _as_int(value: Variant, fallback: int = 0) -> int:
	# The single most important function in this file. See the header.
	# Handles float (the normal case), int, and numeric strings, because a
	# hand-written JSON fixture or a sloppy endpoint can produce any of them.
	match typeof(value):
		TYPE_INT:
			return value
		TYPE_FLOAT:
			return int(round(value))
		TYPE_STRING:
			return int(value) if (value as String).is_valid_int() else fallback
		_:
			return fallback


func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _array(value: Variant) -> Array:
	return value if value is Array else []


# =============================================================================
# RESULT HELPERS
# =============================================================================

func _live(data: Dictionary) -> Dictionary:
	return {"ok": true, "live": true, "data": data, "error": ""}


func _local(data: Dictionary, reason: String) -> Dictionary:
	return {"ok": true, "live": false, "data": data, "error": reason}


func _dead(reason: String) -> Dictionary:
	return {"ok": false, "live": false, "data": {}, "error": reason}


# =============================================================================
# GET /api/save — character slots
# =============================================================================

func fetch_save() -> Dictionary:
	if not Api.is_logged_in():
		return _dead("Not logged in.")

	var res: Dictionary = await Api.get_json("/api/save")
	if not res.ok:
		return _local(_placeholder_save(), res.error)

	var body: Dictionary = _dict(res.data)
	var slots: Array = []

	for raw in _array(body.get("slots")):
		var row: Dictionary = _dict(raw)
		slots.append({
			"slot":       _as_int(row.get("slot"), -1),
			"class_id":   str(row.get("class_id", "")),
			"name":       str(row.get("name", "")),
			"level":      _as_int(row.get("level"), 1),
			"area":       str(row.get("area", "elusion")),
			"updated_at": _as_int(row.get("updated_at"), 0),
		})

	return _live({
		"username": str(body.get("username", Api.username)),
		"slots": slots,
	})


func _placeholder_save() -> Dictionary:
	# Shown when /api/save isn't reachable. Deliberately obvious: a slot named
	# "(offline)" should never be mistaken for a real character.
	return {
		"username": Api.username if Api.username != "" else "(offline)",
		"slots": [{
			"slot": 0,
			"class_id": "warrior",
			"name": "(offline)",
			"level": 1,
			"area": "elusion",
			"updated_at": 0,
		}],
	}


# =============================================================================
# GET /api/player/status — live HUD values
# =============================================================================

func fetch_status(slot: int) -> Dictionary:
	if not Api.is_logged_in():
		return _dead("Not logged in.")

	var res: Dictionary = await Api.get_json("/api/player/status?slot=%d" % slot)

	# 404 is not a failure here — it means the slot is genuinely empty, which
	# is a real answer the caller needs to distinguish from "server is down".
	if res.status == 404:
		return _dead("No character in slot %d." % slot)

	if not res.ok:
		return _local(_placeholder_status(slot), res.error)

	var body: Dictionary = _dict(res.data)
	return _live({
		"slot":        _as_int(body.get("slot"), slot),
		"level":       _as_int(body.get("level"), 1),
		"hp":          _as_int(body.get("hp"), 0),
		"max_hp":      _as_int(body.get("max_hp"), 1),
		"mana":        _as_int(body.get("mana"), 0),
		"max_mana":    _as_int(body.get("max_mana"), 1),
		"stamina":     _as_int(body.get("stamina"), 0),
		"max_stamina": _as_int(body.get("max_stamina"), 1),
		"gold":        _as_int(body.get("gold"), 0),
		"xp":          _as_int(body.get("xp"), 0),
		"xp_to_next":  _as_int(body.get("xp_to_next"), 1),
	})


func _placeholder_status(slot: int) -> Dictionary:
	return {
		"slot": slot, "level": 1,
		"hp": 10, "max_hp": 10,
		"mana": 10, "max_mana": 10,
		"stamina": 10, "max_stamina": 10,
		"gold": 0, "xp": 0, "xp_to_next": 1,
	}


# =============================================================================
# GET /api/bank and POST /api/bank
# =============================================================================

func fetch_bank(slot: int) -> Dictionary:
	if not Api.is_logged_in():
		return _dead("Not logged in.")

	var res: Dictionary = await Api.get_json("/api/bank?slot=%d" % slot)
	if not res.ok:
		return _local(_placeholder_bank(slot), res.error)

	return _live(_normalise_bank(_dict(res.data), slot))


func bank_op(slot: int, op: String, item_id: String, quantity: int) -> Dictionary:
	# op is "deposit" or "withdraw". The server answers with the WHOLE bank,
	# not a delta, so the client never has to guess what happened — guessing
	# is how bank duplication bugs get written.
	if not Api.is_logged_in():
		return _dead("Not logged in.")

	var res: Dictionary = await Api.post("/api/bank", {
		"slot": slot,
		"op": op,
		"item_id": item_id,
		"quantity": quantity,
	})

	if not res.ok:
		# A rejected operation is NOT a fallback case. Falling back to
		# placeholder data here would show the player a bank that didn't
		# happen, which is worse than showing them the error.
		return _dead(res.error)

	return _live(_normalise_bank(_dict(res.data), slot))


func _normalise_bank(body: Dictionary, slot: int) -> Dictionary:
	var items: Array = []
	for raw in _array(body.get("items")):
		var row: Dictionary = _dict(raw)
		var id: String = str(row.get("item_id", ""))
		if id == "":
			continue
		items.append({
			"item_id": id,
			"quantity": _as_int(row.get("quantity"), 0),
		})

	return {
		"slot":     _as_int(body.get("slot"), slot),
		"gold":     _as_int(body.get("gold"), 0),
		"capacity": _as_int(body.get("capacity"), 40),
		"items":    items,
	}


func _placeholder_bank(slot: int) -> Dictionary:
	return {"slot": slot, "gold": 0, "capacity": 40, "items": []}
