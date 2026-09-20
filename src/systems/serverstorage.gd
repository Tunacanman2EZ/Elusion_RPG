# serverstorage.gd — CharacterData's save backend, talking to the Flask API.
#
# Implements the same two methods LocalStorage does, so swapping it in is one
# line in CharacterData.load_for_user(). Everything else in that file, and all
# 29 of its save_data() callers, are untouched.
#
# THE SHAPE MISMATCH THIS EXISTS TO BRIDGE
# ----------------------------------------
# CharacterData thinks in one blob: four character slots, an account_data dict,
# a version and a signature. The server thinks relationally — a row per
# character, a row per bank cell, a row per skill — because that is what lets
# it validate anything at all. A server that stored the blob could not tell you
# whether your gold was plausible.
#
# So this file is the translation, and it is the only place in the game that
# knows both shapes.
#
# INTEGERS
# --------
# Godot's JSON.parse_string() returns EVERY number as a float — there is no
# integer type in JSON and Godot does not infer one. The server's 88 arrives as
# 88.0, and Godot compares type-strictly, so 88.0 != 88.
#
# This already cost this project a day once: CharacterData's sanitizer cast to
# int, compared against the parsed float, concluded all 112 fields had changed,
# and rewrote the save on every load. Every integer crossing this boundary goes
# through _int(). No exceptions. netclient.gd learned this the hard way first.
class_name ServerStorage
extends SaveStorage


# The skills the server knows, matching VALID_SKILLS in app.py and
# SKILL_GROWTH_FACTORS in characterdata.gd. All three spell it "defense".
const SKILL_IDS := ["attack", "defense", "agility", "magic", "fishing", "cooking"]

# The hotbar is nine keys, because the HUD draws nine. The server pads and
# trims to the same number rather than refusing a body of the wrong length —
# an older client sending seven is not lying about anything, it just predates
# two of the keys, and 400-ing an otherwise honest save over the shape of a
# convenience feature would stop that client saving at all.
const HOTBAR_SIZE := 9

# Mirrors the client's own SAVE_VERSION. Stamped onto loaded payloads so
# CharacterData's migration path sees a current save rather than a versionless
# one it would try to upgrade.
const PAYLOAD_VERSION := 3


# What was last successfully pushed, per endpoint, as JSON text.
#
# WHY: save() runs on a two-second debounce during play, and a full push is four
# requests per character plus two for the account. With four characters that is
# eighteen requests every two seconds, almost all of them re-sending bytes the
# server already has. Comparing against the last push turns a quiet minute into
# zero requests instead of five hundred and forty.
var _last_pushed: Dictionary = {}

# True while a push is in flight, so a debounce tick landing mid-push does not
# start a second overlapping one and interleave its writes.
var _pushing: bool = false

# The one save held back while _pushing is true. See save() for why holding it
# beats dropping it, and _push() for how it is drained.
var _queued_payload: Dictionary = {}
var _has_queued: bool = false


func _init() -> void:
	# The server is the authority — see SaveStorage.is_authoritative.
	is_authoritative = true


# =============================================================================
# LOAD
# =============================================================================

func load() -> Dictionary:
	# Rebuilds the blob CharacterData expects out of however many calls it
	# takes. Returns {} on failure, which CharacterData already treats as
	# "fresh install" — and that is the correct reading here too, because a
	# player who cannot reach the server has no characters to show.
	if not Api.is_logged_in():
		push_warning("ServerStorage: load() with no session — returning empty.")
		return {}

	var listing: Dictionary = await Api.get_json("/api/save")
	if not listing.get("ok", false):
		push_warning("ServerStorage: could not list characters — %s" % listing.get("error", ""))
		return {}

	var slots: Array = [null, null, null, null]
	var listed: Array = _array(_dict(listing.get("data", {})).get("slots", []))

	for entry in listed:
		if not (entry is Dictionary):
			continue
		var index: int = _int(entry.get("slot", -1), -1)
		if index < 0 or index >= slots.size():
			continue

		# One call per character rather than four — /api/character returns
		# identity, vitals, backpack and skills together, because they are all
		# keyed on the same (user, slot) and none is useful without the others.
		var res: Dictionary = await Api.get_json("/api/character?slot=%d" % index)
		if not res.get("ok", false):
			push_warning("ServerStorage: slot %d failed to load — %s" % [index, res.get("error", "")])
			continue

		slots[index] = _slot_from_server(_dict(res.get("data", {})))

	var account: Dictionary = await Api.get_json("/api/account")
	if not account.get("ok", false):
		push_warning("ServerStorage: could not load account data — %s" % account.get("error", ""))

	var account_data: Dictionary = _account_from_server(_dict(account.get("data", {})))

	# WHAT WE JUST READ IS, BY DEFINITION, WHAT THE SERVER HOLDS.
	#
	# Without this the first save after every login re-sent all of it: fourteen
	# requests echoing back data fetched three seconds earlier, because
	# _last_pushed started empty and so everything looked changed.
	#
	# A later push still fires the moment anything genuinely moves — the
	# fingerprints are of the same bodies a push would send, built by the same
	# functions, so a real change produces a different hash and goes out.
	_seed_fingerprints(slots, account_data)

	return {
		"version": PAYLOAD_VERSION,
		"character_slots": slots,
		"active_character_index": 0,
		"account_data": account_data,
		"saved_at": int(Time.get_unix_time_from_system()),
		# NO SIGNATURE, deliberately. Signing exists to detect a locally edited
		# file; there is nothing to detect when the bytes came from the server.
		# CharacterData skips verification when storage.is_authoritative.
	}


func _seed_fingerprints(slots: Array, account: Dictionary) -> void:
	# Records what a push WOULD have sent for the state just loaded, without
	# sending any of it.
	#
	# NOTE it runs before CharacterData's sanitizer does. That is correct: the
	# sanitizer only recomputes derived fields, none of which appear in these
	# bodies. If it ever does clamp something real — a value the server holds
	# that the client considers impossible — the fingerprint will not match and
	# the correction gets pushed, which is exactly what should happen.
	for index in slots.size():
		var slot = slots[index]
		if not (slot is Dictionary):
			continue
		# _save_fingerprint, NOT _save_body — the seed has to hash the same
		# shape the push compares against, or the very first save of the
		# session would always look changed and always push.
		_last_pushed["save:%d" % index] = JSON.stringify(_save_fingerprint(index, slot))
		_last_pushed["status:%d" % index] = JSON.stringify(_status_body(index, slot))
		_last_pushed["inventory:%d" % index] = JSON.stringify(_inventory_body(index, slot))
		_last_pushed["skills:%d" % index] = JSON.stringify(_skills_body(index, slot))

	_last_pushed["lusions"] = JSON.stringify(_lusions_body(account))
	_last_pushed["bank"] = JSON.stringify(_bank_body(account))


func _slot_from_server(data: Dictionary) -> Dictionary:
	var status: Dictionary = _dict(data.get("status", {}))

	var slot: Dictionary = {
		# The client identifies a character by its CLASS — slot["character"] is
		# "warrior", and get_character_by_name() searches on it. The server
		# calls the same thing class_id.
		"character":     str(data.get("class_id", "")),
		"active_pet_id": str(data.get("active_pet_id", "")),

		# GEAR AND THE HOTBAR, read back under the names CharacterData uses.
		#
		# The hotbar is the reason this pair exists at all. It lived only in the
		# local slot dictionary, so it survived a scene change and did not
		# survive a re-login — the pet came back, because active_pet_id has a
		# column, and the hotbar did not, because it had none. Nobody decided
		# that; it was simply never wired, and equipment would have inherited
		# the same hole on its first day.
		#
		# "hotbar" on the wire, "hotbar_assignments" in the slot. The client's
		# name predates the column, and renaming a saved key would cost a
		# migration to fix a spelling.
		"equipment":          _dict(data.get("equipment", {})),
		"hotbar_assignments": _string_array(data.get("hotbar", []), HOTBAR_SIZE),

		# The map you have uncovered. Opaque here on purpose — WorldMap knows
		# what the bytes mean and this layer does not need to.
		"explored":           _dict(data.get("explored", {})),

		"level":       _int(status.get("level", 1), 1),
		"xp":          _int(status.get("xp", 0)),
		# The server's xp_to_next is the client's xp_next. Different name for
		# the same number; the sanitizer recomputes it from level anyway.
		"xp_next":     _int(status.get("xp_to_next", 100), 100),
		"gold":        _int(status.get("gold", 0)),

		"hp":          _int(status.get("hp", 0)),
		"max_hp":      _int(status.get("max_hp", 0)),
		"mana":        _int(status.get("mana", 0)),
		"max_mana":    _int(status.get("max_mana", 0)),
		"stamina":     _int(status.get("stamina", 0)),
		"max_stamina": _int(status.get("max_stamina", 0)),

		"inventory":   _items_from_server(_array(data.get("inventory", []))),
	}

	# Skills arrive as {"attack": {"level": 12, "xp": 340}} and live on the slot
	# as three flat keys each. xp_next is not sent: it is fully derived from the
	# level, and the sanitizer recomputes it. Sending a derived value would just
	# be a second copy of the growth curve to keep in step.
	var skills: Dictionary = _dict(data.get("skills", {}))
	for skill_id in SKILL_IDS:
		var entry: Dictionary = _dict(skills.get(skill_id, {}))
		slot[skill_id] = _int(entry.get("level", 1), 1)
		slot[skill_id + "_xp"] = _int(entry.get("xp", 0))

	return slot


func _account_from_server(data: Dictionary) -> Dictionary:
	return {
		"lusions":        _int(data.get("lusions", 0)),
		"bank_gold":      _int(data.get("bank_gold", 0)),
		# WHAT DYING HAS COST THIS ACCOUNT, read-only on this side. The server
		# is the only thing that ever adds to it - /api/character/revive, in
		# the same transaction as the payment - so there is no matching PUT
		# and nothing here should ever write it.
		"score":          _int(data.get("score", 0)),
		"bank_inventory": _items_from_server(_array(data.get("bank_inventory", []))),
	}


func _items_from_server(cells: Array) -> Array:
	# Positional in, positional out. A null cell stays null; the server already
	# returns a full-length array with gaps, so the shape matches what the
	# inventory UI expects without any repacking.
	var out: Array = []
	for cell in cells:
		if cell is Dictionary and str(cell.get("item_id", "")) != "":
			out.append({
				"item_id":  str(cell.get("item_id", "")),
				"quantity": _int(cell.get("quantity", 1), 1),
			})
		else:
			out.append(null)
	return out


# =============================================================================
# SAVE
# =============================================================================

func save(payload: Dictionary) -> bool:
	# Starts the push and returns. Nothing waits on a save during play, and
	# blocking a physics frame on HTTP would be far worse than a save landing a
	# few hundred milliseconds later.
	if not Api.is_logged_in():
		push_warning("ServerStorage: save() with no session — dropped.")
		return false
	if _pushing:
		# A debounce tick arriving mid-push. It is HELD, not dropped.
		#
		# THIS USED TO RETURN true AND THROW THE PAYLOAD AWAY, on the reasoning
		# that "CharacterData will mark itself dirty again on the next change".
		# That is true only if there IS a next change. Picking up 500 gold while
		# a slow push is in flight, then standing still and logging out, lost the
		# gold outright: _write_save_now() had already cleared _save_pending, this
		# returned true, and flush_save() on the way out saw nothing pending and
		# did nothing. Silent, and exactly as large as whatever happened during
		# the push.
		#
		# One slot is enough. A newer payload is a strict superset of an older
		# one — it is the whole save, not a delta — so a second arrival simply
		# replaces the first and _push() drains whatever is there when it
		# finishes. The interleaving the old comment worried about is what the
		# queue prevents, not what it causes.
		_queued_payload = payload
		_has_queued = true
		return true

	_push(payload)          # coroutine, deliberately not awaited
	return true


func _push(payload: Dictionary) -> void:
	# Drains the queue in a LOOP rather than by calling itself. A save arriving
	# during the final await of one push would otherwise start a nested coroutine
	# frame, and a steady stream of them would nest without bound.
	_pushing = true
	var current: Dictionary = payload

	while true:
		var slots: Array = _array(current.get("character_slots", []))
		for index in slots.size():
			var slot = slots[index]
			if slot is Dictionary:
				await _push_slot(index, slot)

		await _push_account(_dict(current.get("account_data", {})))

		if not _has_queued:
			break

		# Taken and cleared BEFORE the next round, so a save arriving during
		# THAT round queues cleanly behind it rather than being overwritten by
		# the one already in hand.
		current = _queued_payload
		_queued_payload = {}
		_has_queued = false

	_pushing = false


# THE REQUEST BODIES LIVE IN ONE PLACE EACH.
#
# They are built by two callers: _push_slot() below, which sends them, and
# _seed_fingerprints() after a load, which only hashes them. If those two ever
# constructed the bodies separately the seed would compare against something the
# push never sends, and the optimisation would silently do nothing — or worse,
# suppress a push that was genuinely needed.

func _save_body(index: int, slot: Dictionary) -> Dictionary:
	var body: Dictionary = {
		"slot": index,
		"class_id": str(slot.get("character", "")),
		# The client has no separate display name; a character IS its class.
		"name": str(slot.get("character", "")),
		"level": _int(slot.get("level", 1), 1),
		"active_pet_id": str(slot.get("active_pet_id", "")),
	}

	# OMITTED MEANS "LEAVE IT ALONE", and that is the server's rule, not a
	# convenience here. /api/save keeps whatever the row holds for any of these
	# three keys the body does not mention — so a slot that has never had gear
	# must not send `{}`, which is the explicit "take everything off".
	#
	# The distinction is only load-bearing for one case, and it is the case
	# that would hurt: a save file written before equipment existed has no such
	# key, and the first save after upgrading would otherwise undress a
	# character the server had already dressed.
	if slot.has("equipment"):
		body["equipment"] = _dict(slot["equipment"])
	if slot.has("hotbar_assignments"):
		body["hotbar"] = _string_array(slot["hotbar_assignments"], HOTBAR_SIZE)
	if slot.has("explored"):
		body["explored"] = _dict(slot["explored"])

	return body


func _save_fingerprint(index: int, slot: Dictionary) -> Dictionary:
	# WHAT IS COMPARED, WHICH IS NOT WHAT IS SENT — and this is the one place
	# in this file where those differ, so it is worth being explicit about why.
	#
	# The explored map changes every few steps. Comparing it directly meant a
	# player walking in a straight line pushed /api/save every three or four
	# seconds, forever, to record fog:
	#
	#     16:51:21 "PUT /api/save HTTP/1.1" 200
	#     16:51:26 "PUT /api/save HTTP/1.1" 200
	#     16:51:30 "PUT /api/save HTTP/1.1" 200
	#
	# So the map is replaced here by WorldMap's revision counter, which moves
	# at most once every forty-five seconds and only when something has
	# actually been uncovered. The BODY still carries the real map, so a push
	# triggered by anything else — a level, a pet, a piece of gear — takes the
	# current map with it for free.
	#
	# The net effect is that the map costs at most one request a minute while
	# walking and none at all while standing still.
	var body: Dictionary = _save_body(index, slot)
	if body.has("explored"):
		body.erase("explored")
		body["explored_rev"] = _int(slot.get("explored_rev", 0))
	return body


func _status_body(index: int, slot: Dictionary) -> Dictionary:
	return {
		"slot": index,
		"level":       _int(slot.get("level", 1), 1),
		"hp":          _int(slot.get("hp", 0)),
		"max_hp":      _int(slot.get("max_hp", 0)),
		"mana":        _int(slot.get("mana", 0)),
		"max_mana":    _int(slot.get("max_mana", 0)),
		"stamina":     _int(slot.get("stamina", 0)),
		"max_stamina": _int(slot.get("max_stamina", 0)),
		"gold":        _int(slot.get("gold", 0)),
		"xp":          _int(slot.get("xp", 0)),
		"xp_to_next":  _int(slot.get("xp_next", 100), 100),
	}


func _inventory_body(index: int, slot: Dictionary) -> Dictionary:
	return {
		"slot": index,
		"inventory": _items_to_server(_array(slot.get("inventory", []))),
	}


func _skills_body(index: int, slot: Dictionary) -> Dictionary:
	var skills: Dictionary = {}
	for skill_id in SKILL_IDS:
		skills[skill_id] = {
			"level": _int(slot.get(skill_id, 1), 1),
			"xp":    _int(slot.get(skill_id + "_xp", 0)),
		}
	return {"slot": index, "skills": skills}


func _lusions_body(account: Dictionary) -> Dictionary:
	return {"lusions": _int(account.get("lusions", 0))}


func _bank_body(account: Dictionary) -> Dictionary:
	return {"bank_inventory": _items_to_server(_array(account.get("bank_inventory", [])))}


func _push_slot(index: int, slot: Dictionary) -> void:
	if str(slot.get("character", "")) == "":
		# A slot with no class is one the server would reject anyway — it
		# validates class_id against the four it knows.
		push_warning("ServerStorage: slot %d has no character class — not pushed." % index)
		return

	await _put_if_changed("save:%d" % index, "/api/save", _save_body(index, slot),
		_save_fingerprint(index, slot))
	await _put_if_changed("status:%d" % index, "/api/player/status", _status_body(index, slot))
	await _put_if_changed("inventory:%d" % index, "/api/character/inventory", _inventory_body(index, slot))
	await _put_if_changed("skills:%d" % index, "/api/character/skills", _skills_body(index, slot))


func _push_account(account: Dictionary) -> void:
	await _put_if_changed("lusions", "/api/account/lusions", _lusions_body(account))
	await _put_if_changed("bank", "/api/account/bank", _bank_body(account))
	# bank_gold is NOT pushed. It only ever moves through /api/bank/gold, which
	# is the one endpoint that can verify anything here — it holds both balances
	# and conserves the total. Letting a blanket save overwrite it would throw
	# that away and make the bank as forgeable as everything else.


func _items_to_server(cells: Array) -> Array:
	# Positional, nulls preserved. The server keys these on their index, so
	# packing out the gaps here would silently move every item left.
	var out: Array = []
	for cell in cells:
		if cell is Dictionary and str(cell.get("item_id", "")) != "":
			out.append({
				"item_id":  str(cell.get("item_id", "")),
				"quantity": maxi(_int(cell.get("quantity", 1), 1), 1),
			})
		else:
			out.append(null)
	return out


# =============================================================================
# CHANGE DETECTION
# =============================================================================

func _put_if_changed(key: String, path: String, body: Dictionary,
		compare: Dictionary = {}) -> void:
	# Takes the PATH and the BODY, not a started request — so an unchanged
	# section costs nothing at all rather than costing a round trip whose reply
	# we then ignore.
	#
	# JSON.stringify is the comparison because it is stable for the dictionaries
	# built above: every one is assembled in the same literal order, from the
	# same keys, every time. It would not be safe against dictionaries built by
	# arbitrary code in arbitrary order, and this is the only place it is used.
	# `compare` is the body for everything but the save, where a field that
	# changes constantly is swapped for one that does not — see
	# _save_fingerprint(). Empty means "compare the body itself", which is what
	# every other section wants.
	var fingerprint: String = JSON.stringify(body if compare.is_empty() else compare)
	if _last_pushed.get(key, "") == fingerprint:
		return

	var res: Dictionary = await Api.put(path, body)
	if not res.get("ok", false):
		# NOT recorded as pushed. A rejected section stays dirty, so the next
		# save retries it rather than deciding it is already up to date — which
		# is exactly how a failed write becomes silent data loss.
		push_warning("ServerStorage: %s rejected — %s" % [key, res.get("error", "")])
		return

	_last_pushed[key] = fingerprint


func _int(value: Variant, fallback: int = 0) -> int:
	# THE ONE PLACE INTEGERS CROSS THE BOUNDARY. See the header: JSON has no
	# integer type, so every number Godot parses is a float, and 88.0 != 88
	# under strict comparison.
	match typeof(value):
		TYPE_INT:
			return value
		TYPE_FLOAT:
			return int(value)
		TYPE_STRING:
			return int(value) if value.is_valid_int() else fallback
		_:
			return fallback


func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _array(value: Variant) -> Array:
	return value if value is Array else []


func _string_array(value: Variant, size: int) -> Array:
	# A fixed-length array of plain Strings, padded with "" and trimmed to fit.
	#
	# BOTH DIRECTIONS USE THIS, which is the point: the hotbar arrives from the
	# server and leaves for it in the same shape, so one function is all that
	# is needed and there is no pair of half-matching converters to drift. The
	# length is forced because the HUD indexes the array directly — a short one
	# is an out-of-range read on the eighth key, and a long one silently drops
	# whatever is past the end.
	var out: Array = []
	var source: Array = _array(value)
	for index in size:
		out.append(str(source[index]) if index < source.size() else "")
	return out
