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

# Mirrors the client's own SAVE_VERSION. Stamped onto loaded payloads so
# CharacterData's migration path sees a current save rather than a versionless
# one it would try to upgrade.
const PAYLOAD_VERSION := 3


# What was last successfully pushed, per endpoint, as JSON text.
#
# WHY: save() runs on a two-second debounce during play, and a full push is three
# requests per character plus two for the account. With four characters that is
# fourteen requests every two seconds, almost all of them re-sending bytes the
# server already has. Comparing against the last push turns a quiet minute into
# zero requests instead of four hundred and twenty.
var _last_pushed: Dictionary = {}

# True while a push is in flight, so a debounce tick landing mid-push does not
# start a second overlapping one and interleave its writes.
var _pushing: bool = false

# The one save held back while _pushing is true. See save() for why holding it
# beats dropping it, and _push() for how it is drained.
var _queued_payload: Dictionary = {}
var _has_queued: bool = false

# Sections whose last push was refused or never answered, by the same key as
# _last_pushed. See has_unpushed().
var _failed_keys: Dictionary = {}

# Sections already handed to a closing page, by key, with the fingerprint that
# went. See requests_before_leaving().
var _sent_leaving: Dictionary = {}


# What load() answers when any part of it did not arrive.
const LOAD_FAILED := {"load_failed": true}


func _init() -> void:
	# The server is the authority — see SaveStorage.is_authoritative.
	is_authoritative = true


# =============================================================================
# LOAD
# =============================================================================

func load() -> Dictionary:
	# Rebuilds the blob CharacterData expects out of however many calls it
	# takes.
	#
	# A FAILED LOAD IS NOT AN EMPTY ACCOUNT. This used to return {} for both,
	# and CharacterData read {} as a fresh install: a server slow to answer at
	# login showed four empty slots, and pressing Create in one of them pushed
	# a brand new character's EMPTY backpack over the real one. Reproduced
	# live - the bag was gone. Now any part that does not load - the list, a
	# character on it, the account - is LOAD_FAILED, and nothing is shown or
	# saved from a view that never arrived. See CharacterData.load_failed.
	if not Api.is_logged_in():
		push_warning("ServerStorage: load() with no session — nothing loaded.")
		return LOAD_FAILED.duplicate()

	var listing: Dictionary = await Api.get_json("/api/save")
	if not listing.get("ok", false):
		push_warning("ServerStorage: could not list characters — %s" % listing.get("error", ""))
		return LOAD_FAILED.duplicate()

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
			# NOT SKIPPED. A character that did not load would be shown as an
			# empty slot, which is the same trap one slot at a time.
			push_warning("ServerStorage: slot %d failed to load — %s" % [index, res.get("error", "")])
			return LOAD_FAILED.duplicate()

		slots[index] = _slot_from_server(_dict(res.get("data", {})))

	var account: Dictionary = await Api.get_json("/api/account")
	if not account.get("ok", false):
		# AND NOT THE ACCOUNT EITHER. It holds the shared bank, and the bank
		# save replaces the whole bank: shown empty, one deposit would have
		# written "this and nothing else" over everything in it.
		push_warning("ServerStorage: could not load account data — %s" % account.get("error", ""))
		return LOAD_FAILED.duplicate()

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
		# No "skills:%d" seed, because nothing pushes skills any more. See
		# _push_slot().

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

		# GEAR, read back under the name CharacterData uses.
		#
		# The hotbar used to come back beside it as a list of item ids, one per
		# key. The keys hold items now, and arrive as cells 20-29 of "inventory"
		# below - there is no separate hotbar on the wire in either direction.
		"equipment":          _dict(data.get("equipment", {})),

		# The map you have uncovered. Opaque here on purpose — WorldMap knows
		# what the bytes mean and this layer does not need to.
		"explored":           _dict(data.get("explored", {})),

		# Alongside explored rather than in `status`: save_row_to_dict() returns
		# it at the top level of the character, not in the status block.
		"area":               str(data.get("area", "elusion")),

		"level":       _int(status.get("level", 1), 1),
		"xp":          _int(status.get("xp", 0)),
		# The server's xp_to_next is the client's xp_next. Different name for
		# the same number; the sanitizer recomputes it from level anyway.
		"xp_next":     _int(status.get("xp_to_next", int(GameConstants.XP_BASE)), int(GameConstants.XP_BASE)),
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
	# convenience here. /api/save keeps whatever the row holds for either of
	# these keys when the body does not mention it — so a slot that has never had gear
	# must not send `{}`, which is the explicit "take everything off".
	#
	# The distinction is only load-bearing for one case, and it is the case
	# that would hurt: a save file written before equipment existed has no such
	# key, and the first save after upgrading would otherwise undress a
	# character the server had already dressed.
	if slot.has("equipment"):
		body["equipment"] = _dict(slot["equipment"])
	if slot.has("explored"):
		body["explored"] = _dict(slot["explored"])

	# SAME "OMITTED MEANS LEAVE IT ALONE" RULE as the two above. A save from
	# before this field existed has no area, and sending "" would move that
	# character to the server's default instead of leaving it where it was.
	#
	# It also lands in _save_fingerprint() for free, which is what makes
	# walking into a new area push a save at all - without that the server
	# would keep whichever area you happened to be in when something else
	# changed.
	if slot.has("area"):
		body["area"] = str(slot["area"])

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
		"xp_to_next":  _int(slot.get("xp_next", int(GameConstants.XP_BASE)), int(GameConstants.XP_BASE)),
	}


func _inventory_body(index: int, slot: Dictionary) -> Dictionary:
	return {
		"slot": index,
		"inventory": _items_to_server(_array(slot.get("inventory", []))),
	}


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

	for section in _slot_sections(index, slot):
		await _put_if_changed(section[0], section[1], section[2], section[3])

	# SKILLS ARE NOT PUSHED, and this is the last piece of E-2.
	#
	# All six are server-granted now - attack at the kill, fishing and cooking
	# against items the server consumed, defense/agility/magic through
	# /api/skill/train. PUT /api/character/skills drops every skill name it
	# accepts, so the call could not write anything: VALID_SKILLS and
	# SERVER_OWNED_SKILLS are the same six on the server, and test_gathering.py
	# holds that ("every skill the route accepts is a skill it drops").
	#
	# WHICH MADE THIS THE MOST EXPENSIVE NO-OP IN THE CLIENT. _put_if_changed
	# only sends when the body changes - and the body is the six skill levels,
	# which the SERVER moves on almost every kill. So the fingerprint changed
	# constantly, and each change bought a round trip whose entire effect was to
	# be validated and thrown away. A quiet request per kill, for nothing.
	#
	# THE ROUTE STAYS ON THE SERVER and still answers 200. That is deliberate and
	# not about this client: an un-updated build still sends all six every save,
	# and a 400 over a field it may no longer set would break saving for it
	# entirely. This is the client catching up with the server, not the server
	# changing.
	#
	# TO PUT IT BACK, if a seventh skill is ever the client's to grant: rebuild
	# the body from SKILL_IDS and add one _put_if_changed line here. SKILL_IDS
	# stays either way - the READ side still needs it to unpack what the server
	# sends down.


func _push_account(account: Dictionary) -> void:
	for section in _account_sections(account):
		await _put_if_changed(section[0], section[1], section[2], section[3])
	# bank_gold is NOT pushed. It only ever moves through /api/bank/gold, which
	# is the one endpoint that can verify anything here — it holds both balances
	# and conserves the total. Letting a blanket save overwrite it would throw
	# that away and make the bank as forgeable as everything else.


# THE SECTIONS, ONE LIST EACH: [key, path, body, compare]. A push walks them,
# and so does a page that is closing, so the two cannot disagree about what a
# save is. `compare` is what the fingerprint is taken of when it is not the body
# itself - see _put_if_changed().

func _slot_sections(index: int, slot: Dictionary) -> Array:
	var keys: Array = _slot_keys(index)
	return [
		[keys[0], "/api/save", _save_body(index, slot), _save_fingerprint(index, slot)],
		[keys[1], "/api/player/status", _status_body(index, slot), {}],
		[keys[2], "/api/character/inventory", _inventory_body(index, slot), {}],
	]


# What a slot's sections are called, in _slot_sections()'s order. One list, so
# forget_slot() cannot miss a section added there.
static func _slot_keys(index: int) -> Array:
	return ["save:%d" % index, "status:%d" % index, "inventory:%d" % index]


func _account_sections(account: Dictionary) -> Array:
	return [
		["lusions", "/api/account/lusions", _lusions_body(account), {}],
		["bank", "/api/account/bank", _bank_body(account), {}],
	]


func requests_before_leaving(payload: Dictionary) -> Array:
	"""What a closing page must send now: every section of `payload` the
	server does not hold, as {"method", "path", "body"}.

	A PAGE THAT IS HIDDEN OR CLOSING HAS NO NEXT FRAME, and _push() needs one
	per request - so a save queued then is sent when the player comes back, or
	never. The caller sends these at once instead (Api.send_before_leaving()).

	What is returned is remembered as sent, so a tab closed from the strip -
	hidden first, then unloaded - does not send each section twice. The mark
	goes when the server confirms a push of that section (_record_push).

	THE BROWSER HOLDS AT MOST 64 KB OF THESE IN FLIGHT, and a save carries the
	explored map, which the server allows up to 64 KB per area. So the save goes
	LAST and WITHOUT the map - omitted means "leave it alone" to /api/save, and
	the next ordinary push brings the map - and the bag, the vitals and the
	purse go first, whatever the save weighs."""
	var out: Array = []
	var sections: Array = []
	var slots: Array = _array(payload.get("character_slots", []))
	for index in slots.size():
		var slot = slots[index]
		if slot is Dictionary and str(slot.get("character", "")) != "":
			sections.append_array(_slot_sections(index, slot))
	sections.append_array(_account_sections(_dict(payload.get("account_data", {}))))
	var saves: Array = []
	for section in sections:
		var key: String = section[0]
		var body: Dictionary = section[2]
		var compare: Dictionary = section[3]
		var fingerprint: String = JSON.stringify(body if compare.is_empty() else compare)
		if _last_pushed.get(key, "") == fingerprint or _sent_leaving.get(key, "") == fingerprint:
			continue
		_sent_leaving[key] = fingerprint
		if section[1] == "/api/save":
			var light: Dictionary = body.duplicate()
			light.erase("explored")
			saves.append({"method": "PUT", "path": section[1], "body": light})
		else:
			out.append({"method": "PUT", "path": section[1], "body": body})
	out.append_array(saves)
	return out


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
		# The server already holds exactly this, so a failure recorded for a
		# later version of it no longer matters.
		_failed_keys.erase(key)
		return

	var res: Dictionary = await Api.put(path, body)
	_record_push(key, res.get("ok", false), fingerprint)
	if not res.get("ok", false):
		# A BAG THE SERVER HAS MOVED ON FROM. PUT /api/character/inventory
		# refuses with 409 when a trade changed this character's bag after the
		# client last saw it, and hands back what the server holds - because
		# this write is a whole-bag replace, and letting it through deleted
		# whatever the trade had just given. Adopting that answer is the only
		# correct response; retrying the same body would be refused again.
		_adopt_refusal(res)
		# NOT recorded as pushed. A rejected section stays dirty, so the next
		# save retries it rather than deciding it is already up to date — which
		# is exactly how a failed write becomes silent data loss.
		push_warning("ServerStorage: %s rejected — %s" % [key, res.get("error", "")])
		return


func forget_slot(index: int) -> void:
	"""A deleted character's sections are no longer anything the server holds.

	_last_pushed is how an unchanged section is skipped, and it is keyed by
	slot. Left alone, a new character made in the slot the old one left could
	match what was last pushed for the OLD one - a level 1 warrior deleted and
	made again sends exactly the same save body - and that push would be
	skipped as already stored, when the server holds nothing for the slot at
	all. The new character would never exist on the server."""
	for key in _slot_keys(index):
		_last_pushed.erase(key)
		_failed_keys.erase(key)
		_sent_leaving.erase(key)


func is_pushing() -> bool:
	"""True while a push is on its way to the server, or one is queued behind it."""
	return _pushing or _has_queued


func has_unpushed() -> bool:
	"""True while any section's last push failed. See SaveStorage.has_unpushed().

	THIS OVERRIDE WAS MISSING, and so was every caller. The base class said the
	gap existed and returned false; nothing asked. A push refused or timed out
	after save() had already returned true stayed dirty in _last_pushed - but
	only the NEXT save would retry it, and a player who changed nothing more
	before quitting never made one. CharacterData asks this now."""
	return not _failed_keys.is_empty()


func _record_push(key: String, ok: bool, fingerprint: String) -> void:
	# NAMED so the bookkeeping can be driven without a server. A success is
	# remembered as pushed and clears the section's failure; a failure is
	# remembered as a failure and NOT as pushed, so the retry sends it again.
	if ok:
		_last_pushed[key] = fingerprint
		_failed_keys.erase(key)
		_sent_leaving.erase(key)
	else:
		_failed_keys[key] = true


func _adopt_refusal(res: Dictionary) -> bool:
	"""A refused save that carries the server's bag: adopt it. True if it did.

	NAMED, so it can be called with a made-up refusal and checked - the rest of
	_put_if_changed() needs a live server to reach. The next save after this is
	built from the adopted bag, so it goes through."""
	if int(res.get("status", 0)) != 409:
		return false
	var data: Dictionary = _dict(res.get("data", {}))
	if not (data.get("resync") is Dictionary):
		return false
	return CharacterData.apply_server_carry(data["resync"])


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
