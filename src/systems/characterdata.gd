# autoload system for managing character save slots and persistent data.
# this script knows about characters, stats, and slots. storage (where the
# data lives) is delegated to a backend object — currently LocalStorage
# (file-based), swappable for ServerStorage later.
#
# data architecture (v2):
# - account_data: shared across ALL characters on this save file. includes
#   lusions (premium currency, soulbound), bank_gold, bank_inventory.
# - character_slots: array of 4 characters. each has per-character stats,
#   carry inventory, and carry gold (vulnerable to death loss).
#
# migration: _migrate_save() upgrades older save formats to current version
# automatically on load, so players don't lose progress when the schema evolves.
#
# ANTI-TAMPER / SANITY VALIDATION (NEW):
# runs on every load_data() call — for tampered saves AND honest bugs alike.
# does NOT reject or wipe corrupted saves; clamps/corrects individual fields
# and logs what changed via push_warning, so a beta tester who trips this
# from a real bug (not cheating) doesn't lose progress outright.
#
# IMPORTANT — what this does and doesn't cover:
# hp/max_hp/mana/max_mana/stamina/max_stamina are already effectively
# tamper-proof today as a side effect of existing design: player.gd's
# _ready() calls _recompute_max_stats() + _fill_all_resources() right after
# load_character_state(), unconditionally overwriting all six from `level`
# + the class's own stat-curve constants. editing them in the save file
# currently has zero live effect. this file still clamps them defensively
# (MAX_STAT_POOL below) in case something later reads the raw save dict
# without going through that pipeline (e.g. a character-select stat
# preview) — but it CANNOT validate "is max_hp correct for this class at
# this level," since per-class curves (hp_base/hp_per_lvl etc.) live in
# each player script's _set_stat_curve(), not here. that would require
# either exposing those curves as static data this script can read, or
# doing the check player-side instead.
#
# level/skill caps (MAX_LEVEL, MIN/MAX_SKILL_LEVEL) below are placeholders —
# confirm against your actual design before relying on them.
#
# WHERE SAVES LIVE NOW:
# not in user://. storage is a SaveStorage — ServerStorage in practice — and a
# character is rows in the server's database, reached with a bearer token. The
# save signing this class used to do is gone with the file it protected; see
# SAVE SIGNING (REMOVED) further down.
#
# The sanity clamps below stayed. They are no longer an anti-tamper measure —
# the server validates what it stores — but they still do the other half of
# their job, which is recomputing values that are fully derived from others
# (xp_next from level, each skill's xp_next from its skill level) so that no
# caller has to.
extends Node
 
 
# =============================================================================
# CONSTANTS
# =============================================================================
 
# version of the save file format — increment when format changes incompatibly
const SAVE_VERSION := 2
 
# bank holds up to this many item slots, fixed-size for stable indices
const BANK_MAX_SLOTS := 50
 
# how long to wait after the last change before actually writing to disk.
# see save_data() below for why this exists.
const SAVE_DEBOUNCE_SECONDS := 2.0

# How long to wait before trying again after the backend REFUSED a save, as
# opposed to after a change. Shorter than the debounce because nothing new has
# happened — this is a retry, not a coalescing window, and the thing it is
# waiting on (a push finishing, a session returning) usually clears in well
# under a second.
const SAVE_RETRY_SECONDS: float = 0.5
 
# central definition of all stats that get saved per character.
# LUSIONS REMOVED — now stored in account_data (account-shared).
const SAVEABLE_STATS := {
	"level":        1,
	"xp":           0,
	"xp_next":      100,
	"gold":         0,            # per-character carry gold (lost on death without revive)
	"hp":           100,
	"max_hp":       100,
	"stamina":      100,
	"max_stamina":  100,
	"mana":         100,
	"max_mana":     100,
	"attack":       1,
	"defense":      1,
	"agility":      1,
	"magic":        1,
	"fishing":      1,
	"cooking":      1,
	# NEW: skill XP progress toward each skill's NEXT level. these were
	# missing entirely — only the skill LEVEL itself (attack/defense/etc.
	# above) was ever saved, so progress within the current skill level
	# silently reset to player.gd's class defaults (0/100) on every reload,
	# regardless of how much had actually been earned. defaults here match
	# player.gd's own class-level defaults for a fresh character.
	"attack_xp":       0,   "attack_xp_next":  100,
	"defense_xp":      0,   "defense_xp_next": 100,
	"agility_xp":      0,   "agility_xp_next": 100,
	"magic_xp":        0,   "magic_xp_next":   100,
	"fishing_xp":      0,   "fishing_xp_next": 100,
	"cooking_xp":      0,   "cooking_xp_next": 100,
}
 
# default account_data structure — used for fresh installs and migrations
const DEFAULT_ACCOUNT_DATA := {
	"lusions":         0,    # account-shared, soulbound premium currency
	"bank_gold":       0,    # account-shared, safe from death
	"bank_inventory":  [],   # account-shared item array (50 slots)
}
 
# --- anti-tamper sanity ranges — PLACEHOLDERS, confirm against your design ---
const MAX_LEVEL := 99
const MIN_SKILL_LEVEL := 1
const MAX_SKILL_LEVEL := 99
const MAX_GOLD := 999999999
# blunt ceiling for hp/mana/stamina + their maxes — see class comment above
# for why this can't be a precise per-class check.
const MAX_STAT_POOL := 999999
 
# NEW: growth factors for each skill's XP-to-next-level curve, used to
# cross-check skill_xp/skill_xp_next the same way character-level xp/xp_next
# is already cross-checked. MUST exactly match the factor argument each
# gain_X_xp() function passes to xp_needed_for_skill(level, 100, factor)
# in player.gd — if that ever gets rebalanced there, update it here too, or
# this will start "correcting" perfectly legitimate skill XP against a
# stale formula.
const SKILL_GROWTH_FACTORS := {
	"attack":  1.25,
	"defense": 1.20,
	"agility": 1.15,
	"magic":   1.25,
	"fishing": 1.12,
	"cooking": 1.10,
}
 
# SAVE_SIGNING_KEY removed — see SAVE SIGNING (REMOVED) further down. It signed
# a local file that no longer exists.
 
 
# =============================================================================
# STATE
# =============================================================================
 
# Storage backend. Typed as the INTERFACE, not either implementation — see
# savestorage.gd. Starts null; a distinct instance is constructed per user in
# load_for_user() below, rather than one shared instance at autoload boot.
var storage: SaveStorage = null
 
# NEW: which user is currently loaded, if any. empty string means no user
# is logged in (fresh boot, or after clear_current_user()).
var current_username: String = ""
 
# 4 character slots, each a dictionary (or null if empty)
var character_slots: Array = [null, null, null, null]
 
# which slot the player picked at character select — read by elusion.gd
var active_character_index: int = 0
 
# account-wide shared data — initialized in _ready, refilled on load
var account_data: Dictionary = DEFAULT_ACCOUNT_DATA.duplicate(true)
 
 
# =============================================================================
# LIFECYCLE
# =============================================================================
 
func _ready() -> void:
	# every startup print in this project is gated on OS.is_debug_build() and
	# tagged [BOOT]/[CHAR]/[HUD]/[WORLD]/[PET], so the boot log is greppable
	# and an exported Release build stays silent. is_debug_build() is true in
	# the editor and in a Debug export, false in a Release export.
	if OS.is_debug_build():
		print("[BOOT] CharacterData ready")
	# CHANGED: no longer loads a save at boot — this autoload's _ready()
	# fires before the login screen even exists, so there's no "current
	# user" yet to load for. state stays at defaults until load_for_user()
	# is called after a successful login (see loginmenu.gd).
	_initialize_account_data()
 
 
# =============================================================================
# PER-USER SESSION  (NEW)
# =============================================================================
# CharacterData used to load ONE global save at boot, before any login
# system existed — every user, new or old, ended up sharing the exact same
# character data regardless of who logged in. this section makes save data
# genuinely scoped per username: a distinct LocalStorage instance (and
# therefore a distinct file on disk) per user, constructed on demand here
# rather than once at autoload _ready().
 
# COROUTINE — callers must await. See the storage swap inside.
func load_for_user(username: String) -> bool:
	# call this right after a successful login, BEFORE transitioning to
	# character select — see loginmenu.gd's _on_login_button_pressed().
	# resets in-memory state first (via clear_current_user()) so a second
	# user logging in during the same session can't briefly see whatever
	# the previous user's data was.
	clear_current_user()
 
	current_username = username

	# THE CUTOVER. This was LocalStorage.new(_save_path_for_user(username)) — a
	# file in user:// that the player could open in a text editor.
	#
	# Everything else in this file is unchanged by that swap, which is the whole
	# reason savestorage.gd exists: 29 save_data() callers, the debounce, the
	# atomic-write guarantees at the call sites, none of them know or care which
	# backend is underneath.
	#
	# await, because ServerStorage.load() has to wait for HTTP. Awaiting a
	# function that is not a coroutine just returns its value, so this line is
	# correct for a file read too.
	storage = ServerStorage.new()
	return await load_data()
 
 
func clear_current_user() -> void:
	# called on logout (see characterhud.gd's _on_logout_pressed()), AND
	# internally by load_for_user() before switching to a new user. resets
	# everything to fresh in-memory defaults — does NOT touch disk, this
	# only clears state so nothing from the outgoing user can leak into
	# whatever comes next (a different user logging in, or a fresh boot).
	#
	# NEW: flushes any pending debounced save FIRST. Without this, logging
	# out within SAVE_DEBOUNCE_SECONDS of your last gold pickup silently
	# threw it away — storage gets nulled two lines below, and the queued
	# write would then have nowhere to go.
	flush_save()
 
	current_username = ""
	storage = null
	character_slots = [null, null, null, null]
	active_character_index = 0
	account_data = DEFAULT_ACCOUNT_DATA.duplicate(true)
 
 
func _save_path_for_user(username: String) -> String:
	# usernames are already restricted to [a-zA-Z0-9_] at registration
	# (see loginmenu.gd's is_valid_input()), so they're already safe to
	# use directly in a filename — no path-traversal risk from characters
	# like '/' or '..'. this strip is defensive in case load_for_user()
	# ever gets called from somewhere that skipped that validation.
	var regex := RegEx.new()
	regex.compile("[^a-zA-Z0-9_]")
	var safe_username: String = regex.sub(username, "", true)
	return "user://character_%s.save" % safe_username
 
 
# =============================================================================
# DEFENSIVE INITIALIZATION
# =============================================================================
 
func _ensure_slot_array() -> void:
	# guarantees character_slots is an Array of exactly 4 entries.
	# protects against corrupted saves or malformed legacy data.
	if character_slots == null \
			or typeof(character_slots) != TYPE_ARRAY \
			or character_slots.size() != 4:
		character_slots = [null, null, null, null]
 
 
func _ensure_account_data() -> void:
	# defensively initialize account_data if missing or malformed.
	# handles fresh installs, corrupted saves, and migration edge cases.
	if account_data == null or typeof(account_data) != TYPE_DICTIONARY:
		account_data = DEFAULT_ACCOUNT_DATA.duplicate(true)
 
	# fill in any missing keys with defaults — graceful upgrade if a new
	# account field is added later
	for key in DEFAULT_ACCOUNT_DATA:
		if not account_data.has(key):
			account_data[key] = DEFAULT_ACCOUNT_DATA[key]

	# Leftover from the removed admin flag. Nothing reads it, but a key left in
	# the payload is a key that outlives everyone who knows what it meant.
	# Ranks live on the server now — Api.role, owner > dev > mod > player.
	account_data.erase("is_admin")
 
	# ensure bank_inventory is exactly BANK_MAX_SLOTS long with nulls for empty
	var bank: Array = account_data.get("bank_inventory", [])
	if typeof(bank) != TYPE_ARRAY:
		bank = []
	while bank.size() < BANK_MAX_SLOTS:
		bank.append(null)
	if bank.size() > BANK_MAX_SLOTS:
		bank.resize(BANK_MAX_SLOTS)
	account_data["bank_inventory"] = bank
 
 
func _initialize_account_data() -> void:
	_ensure_account_data()
 
 
# =============================================================================
# ANTI-TAMPER / SANITY VALIDATION  (NEW)
# =============================================================================
 
func _sanitize_character_slot(slot) -> bool:
	# clamps/corrects one character slot in place (Dictionaries are
	# reference types in GDScript, so mutating `slot` here mutates the
	# actual entry inside character_slots — no reassignment needed).
	# returns true if anything was actually changed, via a before/after
	# snapshot comparison — Godot 4 Dictionaries do deep content comparison
	# with !=, so this is simpler and less error-prone than tracking each
	# field's change individually.
	if slot == null or typeof(slot) != TYPE_DICTIONARY:
		return false
 
	var before: Dictionary = slot.duplicate(true)
 
	# --- level ---
	var level: int = clamp(int(slot.get("level", 1)), 1, MAX_LEVEL)
	slot["level"] = level
 
	# --- xp / xp_next cross-check ---
	# xp_next is fully deterministic from level, so the sanitizer recomputes it
	# rather than trust a saved value that may have been edited.
	#
	# IT MUST USE THE SAME FUNCTION REAL PLAY USES. This block previously had
	# its own copy of the formula, expecting the doubling curve. When gain_xp()
	# moved to the 1.15 curve, this did not - so it treated every honest save as
	# tampered and overwrote xp_next with a value the game never produces. At
	# level 10 the player suddenly needed 51,200 XP instead of 351, and since the
	# value genuinely changed, the save was marked dirty and rewritten on every
	# load. Two copies of one rule is how that happens; there is now one.
	var expected_xp_next: int = GameConstants.xp_needed_for_level(level)

	var saved_xp_next: int = int(slot.get("xp_next", expected_xp_next))
	if saved_xp_next != expected_xp_next:
		push_warning("CharacterData: xp_next mismatch for level %d (had %d, expected %d) — correcting" % [
			level, saved_xp_next, expected_xp_next
		])
	slot["xp_next"] = expected_xp_next
	slot["xp"] = clamp(int(slot.get("xp", 0)), 0, max(expected_xp_next - 1, 0))
 
	# --- gold (carry) ---
	slot["gold"] = clamp(int(slot.get("gold", 0)), 0, MAX_GOLD)
 
	# --- skills + skill XP progress ---
	# clamps each skill's LEVEL first, then uses that clamped level to
	# recompute the expected xp_next for that skill's specific growth curve
	# (see SKILL_GROWTH_FACTORS above) — same cross-check pattern as
	# character-level xp/xp_next, just per-skill. clamps skill_xp below
	# that threshold for the same reason: gain_X_xp()'s while-loop
	# guarantees xp never legitimately reaches xp_next without triggering
	# a skill level-up first.
	for skill in SKILL_GROWTH_FACTORS:
		var skill_level: int = clamp(int(slot.get(skill, MIN_SKILL_LEVEL)), MIN_SKILL_LEVEL, MAX_SKILL_LEVEL)
		slot[skill] = skill_level
 
		var factor: float = SKILL_GROWTH_FACTORS[skill]
		var expected_skill_xp_next: int = int(100 * pow(factor, skill_level - 1))
		var xp_key: String = skill + "_xp"
		var xp_next_key: String = skill + "_xp_next"
 
		var saved_skill_xp_next: int = int(slot.get(xp_next_key, expected_skill_xp_next))
		if saved_skill_xp_next != expected_skill_xp_next:
			push_warning("CharacterData: %s mismatch for %s level %d (had %d, expected %d) — correcting" % [
				xp_next_key, skill, skill_level, saved_skill_xp_next, expected_skill_xp_next
			])
		slot[xp_next_key] = expected_skill_xp_next
		slot[xp_key] = clamp(int(slot.get(xp_key, 0)), 0, max(expected_skill_xp_next - 1, 0))
 
	# --- hp/mana/stamina + maxes — blunt defensive ceiling only, see notes above ---
	for stat in ["hp", "max_hp", "mana", "max_mana", "stamina", "max_stamina"]:
		slot[stat] = clamp(int(slot.get(stat, 0)), 0, MAX_STAT_POOL)
	slot["hp"] = min(int(slot["hp"]), int(slot["max_hp"]))
	slot["mana"] = min(int(slot["mana"]), int(slot["max_mana"]))
	slot["stamina"] = min(int(slot["stamina"]), int(slot["max_stamina"]))
 
	# --- inventory item validation ---
	if slot.has("inventory") and typeof(slot["inventory"]) == TYPE_ARRAY:
		slot["inventory"] = _validate_item_array(slot["inventory"], "character inventory")

	# NEW: say WHAT changed. This used to return a bare bool, so load_data()
	# could only report "correction(s) applied" with no way to tell which
	# field — and that warning fires on EVERY login, meaning some correction
	# never sticks and the save is rewritten every single time. That is not
	# diagnosable from a boolean.
	_report_sanitizer_diff(before, slot, "character slot %s" % str(slot.get("character", "?")))

	# CHANGED: was `slot != before`, which compared TYPE as well as value and
	# so reported a correction on every single load. See _values_differ().
	return _values_differ(before, slot)
 
 
func _sanitize_account_data() -> bool:
	# lusions/bank_gold already clamp >= 0 in their setters (below), but
	# that doesn't help against a save file edited directly on disk and
	# loaded straight in — clamp again here at load time to close that gap.
	var before: Dictionary = account_data.duplicate(true)
 
	account_data["lusions"] = max(int(account_data.get("lusions", 0)), 0)
	account_data["bank_gold"] = max(int(account_data.get("bank_gold", 0)), 0)
 
	if account_data.has("bank_inventory") and typeof(account_data["bank_inventory"]) == TYPE_ARRAY:
		account_data["bank_inventory"] = _validate_item_array(account_data["bank_inventory"], "bank inventory")

	_report_sanitizer_diff(before, account_data, "account data")

	# CHANGED: see _sanitize_character_slot() and _values_differ().
	return _values_differ(before, account_data)


func _values_differ(a: Variant, b: Variant) -> bool:
	# Deep comparison that treats a number as a number regardless of whether
	# it is stored as an int or a float.
	#
	# THIS FUNCTION EXISTS BECAUSE OF A PERMANENT RESAVE LOOP. JSON has no
	# integer type, so Godot's JSON.parse_string() returns EVERY number as a
	# float. The sanitizer then casts each one with int(). Godot's built-in
	# Dictionary comparison is type-strict, so `slot != before` was true on
	# every load, for every numeric field, on a save that was completely
	# correct — level 4.0 became level 4, and that counted as a "correction".
	#
	# The consequence was not cosmetic. load_data() responds to a correction
	# by immediately writing the save back to disk. So every login rewrote
	# the entire save file, forever, over a difference that did not exist.
	# With two game instances running (which the editor's multiple-instances
	# setting quietly enabled) that is two processes racing to rewrite the
	# same three files on startup.
	#
	# Genuine corrections — a clamped level, a recomputed xp_next, a dropped
	# item — still register, because those change the VALUE.
	var type_a: int = typeof(a)
	var type_b: int = typeof(b)

	var a_numeric: bool = type_a == TYPE_INT or type_a == TYPE_FLOAT
	var b_numeric: bool = type_b == TYPE_INT or type_b == TYPE_FLOAT
	if a_numeric and b_numeric:
		return not is_equal_approx(float(a), float(b))

	if type_a != type_b:
		return true

	if type_a == TYPE_DICTIONARY:
		var dict_a: Dictionary = a
		var dict_b: Dictionary = b
		if dict_a.size() != dict_b.size():
			return true
		for key in dict_a:
			if not dict_b.has(key):
				return true
			if _values_differ(dict_a[key], dict_b[key]):
				return true
		return false

	if type_a == TYPE_ARRAY:
		var array_a: Array = a
		var array_b: Array = b
		if array_a.size() != array_b.size():
			return true
		for i in range(array_a.size()):
			if _values_differ(array_a[i], array_b[i]):
				return true
		return false

	return a != b


func _is_derived_key(key: String) -> bool:
	# Keys the sanitizer COMPUTES rather than loads, so their absence from a
	# loaded slot is normal rather than a missing field.
	#
	# Derived from SKILL_GROWTH_FACTORS rather than listed literally, so adding
	# a seventh skill cannot leave a stale hardcoded list behind — the whole
	# reason these are computed in the first place is to have one copy of the
	# curve, and a hand-written list here would quietly become a second one.
	if not key.ends_with("_xp_next"):
		return false
	return SKILL_GROWTH_FACTORS.has(key.trim_suffix("_xp_next"))


func _report_sanitizer_diff(before: Dictionary, after: Dictionary, context: String) -> void:
	# Logs the specific keys the sanitizer altered.
	#
	# CHANGED: this used to flag a type change on its own, which is what
	# exposed the resave loop — every numeric field reported
	# "4.0 (float) -> 4 (int)" on every load. Now that _values_differ()
	# treats those as equal, this reports the same way, so the warning only
	# fires for corrections that actually changed something.
	var changed: Array[String] = []

	for key in after:
		if not before.has(key):
			# A KEY THAT WAS NEVER STORED IS NOT A CORRECTION.
			#
			# This fired on every boot, for every slot, listing all six skill
			# xp_next values as additions — because serverstorage.gd
			# deliberately does not send them. Its comment is right that it
			# should not: they are a pure function of the skill level, and
			# shipping a derived number would be a second copy of the growth
			# curve to keep in step with this one.
			#
			# So the sanitizer filling them in IS the mechanism working, and
			# announcing it as "sanitizer changed character slot warrior" every
			# login taught you to ignore a warning that is supposed to mean
			# something is wrong with a save.
			#
			# A stored value that DISAGREES with the curve is still reported —
			# louder and more precisely — by the per-skill mismatch warning in
			# _sanitize_character_slot().
			if _is_derived_key(key):
				continue
			changed.append("+%s = %s" % [key, str(after[key])])
			continue
		if _values_differ(before[key], after[key]):
			changed.append("%s: %s -> %s" % [key, str(before[key]), str(after[key])])

	for key in before:
		if not after.has(key):
			changed.append("-%s" % key)

	if changed.is_empty():
		return

	push_warning("CharacterData: sanitizer changed %s — %s" % [context, ", ".join(changed)])
 
 
func _is_item_registry_ready() -> bool:
	# defensive check: if ItemRegistry reports zero total items, it almost
	# certainly hasn't finished loading its item table yet (autoload order
	# issue, or some other startup timing gap) — NOT that the game genuinely
	# has zero items defined. treating "not ready" as "doesn't exist" is
	# exactly what caused real, legitimate items (ironsword, bushamulet,
	# etc.) to get silently dropped from real saves. this check exists so
	# that failure mode can't happen again regardless of autoload order.
	return ItemRegistry.get_all_items().size() > 0
 
 
func _validate_item_array(items: Array, context: String) -> Array:
	# drops entries referencing an item_id that doesn't exist in
	# ItemRegistry (e.g. a fabricated ID from a modified/fake registry)
	# instead of silently trusting whatever's in the save. logs what got
	# dropped so it's visible in testing/support, rather than a silent skip.
	if not _is_item_registry_ready():
		push_warning("CharacterData: ItemRegistry not populated yet — skipping item validation for %s this load (nothing dropped)" % context)
		return items
 
	var validated: Array = []
	for entry in items:
		if entry == null:
			validated.append(null)
			continue
		if typeof(entry) != TYPE_DICTIONARY or not entry.has("item_id"):
			validated.append(null)
			continue
		var item_id: String = str(entry.get("item_id", ""))
		if item_id == "" or ItemRegistry.get_item(item_id) == null:
			push_warning("CharacterData: %s references unknown item_id '%s' — dropping" % [context, item_id])
			validated.append(null)
			continue
		validated.append(entry)
	return validated
 
 
# =============================================================================
# SAVE SIGNING  (REMOVED)
# =============================================================================
# _compute_signature(), _canonicalize_for_signing() and _verify_signature() are
# gone, along with SAVE_SIGNING_KEY.
#
# They existed to detect a save file edited in a text editor: sign the payload
# with a key baked into the build, check it on load, and revoke any elevated
# permission on a mismatch. Honest obfuscation for a LOCAL file, and the class comment always
# said so — anyone who decompiled the game could extract the key.
#
# There is no local file any more. Characters live in the server's database,
# reached with a bearer token, and the bytes that arrive at load_data() came off
# the wire rather than off the player's disk. Signing them would be signing our
# own request and checking our own signature.
#
# Rank was the one thing that mattered most here, and it is better protected now
# than signing ever made it: the server decides it, returns it with the login
# response, and the client holds it in memory only. There is nothing to edit.

# =============================================================================
# SAVE / LOAD
# =============================================================================
 
func _write_save_now() -> bool:
	# does the ACTUAL disk write. Only ever called by flush_save() — every
	# gameplay caller goes through save_data(), which queues instead.
	# the storage backend handles the file I/O.
	# NEW: storage can legitimately be null if no user is currently loaded
	# (before login, or after clear_current_user()) — guard rather than
	# crash, since this function has many callsites throughout this file.
	if storage == null:
		push_warning("CharacterData: save attempted with no user loaded — ignoring")
		return false
 
	_ensure_slot_array()
	_ensure_account_data()
	var payload := {
		"version":                 SAVE_VERSION,
		"character_slots":         character_slots,
		"active_character_index":  active_character_index,
		"account_data":            account_data,
		# CHANGED: truncated to whole seconds (int) instead of the raw
		# microsecond-precision float. floats with many decimal digits
		# aren't guaranteed to round-trip losslessly through JSON text —
		# integers are. this was a real candidate for the persistent
		# signature mismatch, since saved_at was the one genuinely
		# non-whole-number float in the whole signed payload.
		"saved_at":                int(Time.get_unix_time_from_system()),
	}
	# THE FLAG IS CLEARED ONLY IF THE BACKEND TOOK IT.
	#
	# It used to be cleared on the line before the call, unconditionally, and
	# the return value was thrown away. So a save the backend refused — no
	# session, or a push already in flight — left the game believing it was
	# clean. Nothing retried, flush_save() on logout saw nothing pending, and
	# whatever had changed was gone with no error anywhere.
	#
	# Staying dirty costs one more attempt. Clearing it wrongly costs the
	# player's progress.
	var accepted: bool = storage.save(payload)
	if accepted:
		_save_pending = false
		_save_countdown = 0.0
	else:
		_save_countdown = SAVE_RETRY_SECONDS
	return accepted
 
 
# =============================================================================
# DEBOUNCED SAVING
# =============================================================================
# WHY: save_data() is called from 13 places in this file, and those are
# reached from ~16 more in player.gd — every gain_*_xp(), every gold
# pickup, every bank operation. Each one used to run a FULL atomic write:
# serialize all four character slots plus inventories and account data,
# write .tmp, copy .bak, delete, rename. Four file operations.
#
# The healer fires ten shots a second and every landed hit grants both
# attack XP and magic XP, so that peaked at roughly twenty complete
# rewrites of the save file per second — all of them writing nearly
# identical data.
#
# Now save_data() marks state dirty and returns. SAVE_DEBOUNCE_SECONDS
# after the last change, _process() writes once. Twenty writes a second
# becomes one every two seconds, and the atomicity guarantee in
# LocalStorage is completely untouched — it just isn't invoked twenty
# times for the same data.
#
# ANYTHING THAT MUST NOT BE LOST calls flush_save() directly: logout,
# quitting, and switching user. Those are the moments where waiting two
# seconds could mean waiting forever.
 
var _save_pending: bool = false
var _save_countdown: float = 0.0
 
 
func save_data() -> bool:
	# Queues a save rather than performing one. Returns true when the save
	# was accepted — NOT when it has hit the disk. No caller has ever used
	# this return value to mean "the bytes are safely written", so this is
	# a safe change, but it is a change in meaning worth knowing about.
	if storage == null:
		push_warning("CharacterData: save_data() called with no user loaded — ignoring")
		return false
 
	_save_pending = true
	_save_countdown = SAVE_DEBOUNCE_SECONDS
	return true
 
 
func flush_save() -> bool:
	# Writes immediately if anything is pending. Safe to call when nothing
	# is dirty — it just does nothing and reports success.
	if not _save_pending:
		return true
	if storage == null:
		_save_pending = false
		return false
	return _write_save_now()
 
 
func _process(delta: float) -> void:
	if not _save_pending:
		return
 
	# defensive: if storage vanished while a save was queued, drop the
	# queue rather than letting _write_save_now() warn on every frame.
	if storage == null:
		_save_pending = false
		return
 
	_save_countdown -= delta
	if _save_countdown <= 0.0:
		_write_save_now()
 
 
func _notification(what: int) -> void:
	# NOTIFICATION_WM_CLOSE_REQUEST fires when the window's X is clicked.
	# NOTIFICATION_EXIT_TREE covers get_tree().quit() paths, like the login
	# screen's Exit button — an autoload stays in the tree across scene
	# changes and only leaves it at shutdown, so this doesn't fire spuriously.
	# Between them, a pending save survives the player closing the game two
	# seconds after picking up gold.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		flush_save()
 
 
func load_data() -> bool:
	# COROUTINE — callers must await. storage.load() reaches the network now.
	# reads from the backend and reconstructs character + account state.
	# empty data means fresh install — initialize defaults and return false.
	# NEW: same null-storage guard as save_data() — load_for_user() always
	# sets storage before calling this, but defensive here too.
	if storage == null:
		push_warning("CharacterData: load_data() called with no user loaded — ignoring")
		_ensure_slot_array()
		_ensure_account_data()
		return false
 
	# @warning_ignore because the analyser types `storage` as SaveStorage, whose
	# load() is not a coroutine — so it reports this await as redundant. It is
	# not: ServerStorage.load() waits on HTTP. await resolves dynamically at
	# runtime and is correct for either backend; only the static check cannot
	# see which one is in the variable.
	@warning_ignore("redundant_await")
	var data: Dictionary = await storage.load()
	if data.is_empty():
		_ensure_slot_array()
		_ensure_account_data()
		return false
 
	data = _migrate_save(data)
 
	# The signature check that used to live here is gone entirely — see SAVE
	# SIGNING (REMOVED) below. Nothing verifies the payload because nothing
	# signs it: it came from the server.
	var needs_resave: bool = false
 
	character_slots = data.get("character_slots", [null, null, null, null])
	active_character_index = data.get("active_character_index", 0)
	account_data = data.get("account_data", DEFAULT_ACCOUNT_DATA.duplicate(true))
 
	_ensure_slot_array()
	_ensure_account_data()
 
	# Sanity pass — runs on every load regardless of whether the save was
	# actually tampered with. See the class comment for scope and limitations.
	var corrected: bool = false
	for slot in character_slots:
		if _sanitize_character_slot(slot):
			corrected = true
	if _sanitize_account_data():
		corrected = true

	# A CORRECTION ON AUTHORITATIVE DATA IS NOT A REASON TO WRITE BACK.
	#
	# The sanitizer has two jobs tangled together: it CLAMPS values that may
	# have been edited, and it FILLS IN fields fully derived from other fields.
	# Only the first is evidence of tampering, and only the first is a reason to
	# persist anything.
	#
	# ServerStorage deliberately does not send the per-skill xp_next values.
	# They are entirely determined by the skill level, and sending them would be
	# a third copy of the growth curve to keep in step with player.gd and the
	# block above. So every login arrived, the sanitizer added six derived keys,
	# and this marked the save dirty — producing exactly the "corrections
	# applied, persisting immediately" warning on every single load that this
	# project has already chased down twice.
	#
	# The values are still filled in; that is what they are for. What stops is
	# treating a recomputation as a change worth writing back to the server.
	if corrected and not storage.is_authoritative:
		needs_resave = true
 
	# NEW: if anything above actually changed the data (a sanity-clamp
	# correction, or a signature/timestamp anomaly), persist the corrected
	# version immediately rather than waiting for the next natural save
	# trigger. otherwise the fix only exists in memory — if the game
	# crashes or gets force-quit before anything else triggers a save, the
	# uncorrected version is still what's on disk next launch, and this
	# whole process just repeats without ever actually landing the fix.
	if needs_resave:
		push_warning("CharacterData: correction(s) applied on load — persisting corrected save immediately.")
		save_data()
 
	return true
 
 
# =============================================================================
# SAVE MIGRATION
# =============================================================================
 
func _migrate_save(data: Dictionary) -> Dictionary:
	# converts old save format to current SAVE_VERSION. runs on every load.
	# safe to call on already-current saves (no-op if version is up to date).
	var version: int = data.get("version", 0)
	if version < SAVE_VERSION:
		# push_warning rather than a gated print, deliberately: a migration
		# rewrites the player's save. It is expected and not an error, but if
		# a save ever comes out wrong, the one thing you want in the log is
		# evidence of which version it was migrated from — and a debug-gated
		# print would not be there in the build that broke it.
		push_warning("CharacterData: migrating save from version %d to %d" % [version, SAVE_VERSION])
 
	# version 0 -> 1: legacy saves without version field. no field changes.
 
	# version 1 -> 2:
	# - extract per-character lusions into account_data.lusions (max value)
	# - migrate old top-level bank fields (account_bank_gold,
	#   account_bank_inventory) into the new account_data dict
	# - convert old bank items from {name, icon_path, quantity} to
	#   {item_id, quantity}
	if version < 2:
		var migrated_account: Dictionary = DEFAULT_ACCOUNT_DATA.duplicate(true)
 
		# legacy bank gold field
		if data.has("account_bank_gold"):
			migrated_account["bank_gold"] = int(data.get("account_bank_gold", 0))
			data.erase("account_bank_gold")
 
		# consolidate per-character lusions into account-shared pool (take max)
		var consolidated_lusions := 0
		for slot in data.get("character_slots", []):
			if slot != null and slot.has("lusions"):
				consolidated_lusions = max(consolidated_lusions, int(slot["lusions"]))
				slot.erase("lusions")
		migrated_account["lusions"] = consolidated_lusions
 
		# convert legacy bank inventory format if present
		# old format: array of {name, icon_path, quantity} dicts
		# new format: array of {item_id, quantity} or null
		var legacy_bank: Array = data.get("account_bank_inventory", [])
		if typeof(legacy_bank) == TYPE_ARRAY:
			var converted: Array = []
			for entry in legacy_bank:
				if entry == null or (typeof(entry) == TYPE_DICTIONARY and entry.is_empty()):
					converted.append(null)
					continue
				if typeof(entry) == TYPE_DICTIONARY:
					# already in new format?
					if entry.has("item_id"):
						converted.append(entry)
						continue
					# old format — look up item_id by display name
					var item_name: String = entry.get("name", "")
					var found_id: String = _find_item_id_by_display_name(item_name)
					if found_id != "":
						converted.append({
							"item_id":  found_id,
							"quantity": int(entry.get("quantity", 1)),
						})
					else:
						# unknown item — leave empty rather than dropping data silently
						push_warning("CharacterData: legacy bank item '%s' not found in registry, skipping" % item_name)
						converted.append(null)
			migrated_account["bank_inventory"] = converted
			data.erase("account_bank_inventory")
 
		data["account_data"] = migrated_account
 
	# future migration template:
	# if version < 3:
	#     # field rename, new account field, etc.
	#     pass
 
	data["version"] = SAVE_VERSION
	return data
 
 
func _find_item_id_by_display_name(item_name: String) -> String:
	# helper used by migration to map old "name"-based bank entries to item_ids.
	# only called during save migration, not at runtime.
	if item_name == "":
		return ""
	for data in ItemRegistry.get_all_items():
		if data.display_name == item_name:
			return data.item_id
	return ""
 
 
# =============================================================================
# CHARACTER CREATION
# =============================================================================
 
func create_character(slot_idx: int, character_name: String) -> void:
	# creates a fresh character at the given slot with default stats.
	# overwrites any existing character in that slot — caller is responsible
	# for confirming that's intended.
	_ensure_slot_array()
	var new_char := {"character": character_name}
	for stat in SAVEABLE_STATS:
		new_char[stat] = SAVEABLE_STATS[stat]
	new_char["inventory"] = []
	new_char["active_pet_id"] = ""  # NEW — fresh characters start with no pet
	character_slots[slot_idx] = new_char
	save_data()
 
 
# =============================================================================
# CHARACTER STATE (PLAYER ↔ SAVE)
# =============================================================================
 
func save_character_state(player: Node) -> void:
	# saves player stats AND inventory to the active slot.
	# called on logout, periodic auto-save, XP gain, gold pickup, etc.
	# lusions are NOT saved per-character — they're in account_data via the
	# player.lusions property proxy.
	_ensure_slot_array()
	var slot: int = active_character_index
	if character_slots[slot] == null:
		return
 
	for stat in SAVEABLE_STATS:
		if stat in player:
			character_slots[slot][stat] = int(player.get(stat))
 
	character_slots[slot]["inventory"] = _capture_inventory(player)
 
	# save hotbar assignments alongside the int stats.
	# must happen BEFORE save_data() or the assignments wait one save cycle
	# to actually hit disk.
	if "hotbar_assignments" in player:
		character_slots[slot]["hotbar_assignments"] = player.hotbar_assignments
 
	# NEW: same reasoning as hotbar_assignments above — active_pet_id is a
	# String (an item_id), not part of the int-only SAVEABLE_STATS loop,
	# so it's handled here explicitly. this is what actually makes a pet
	# survive a scene transition: the pet NODE gets freed with the old
	# scene, but this string persists and player.gd re-spawns from it on
	# the next _ready().
	if "active_pet_id" in player:
		character_slots[slot]["active_pet_id"] = player.active_pet_id
 
	save_data()
 
 
func load_character_state(player: Node) -> void:
	# loads player stats AND inventory data from the active slot.
	# called from player.gd._ready() when the world scene first spawns.
	_ensure_slot_array()
	_ensure_account_data()
 
	var slot: Dictionary = character_slots[active_character_index]
	if slot == null:
		return
 
	for stat in SAVEABLE_STATS:
		if stat in player:
			var default_value: int = SAVEABLE_STATS[stat]
			var saved_value = slot.get(stat, default_value)
			player.set(stat, int(saved_value))
 
	if "inventory_data" in player:
		var saved_inventory = slot.get("inventory", [])
		if typeof(saved_inventory) == TYPE_ARRAY:
			player.inventory_data = saved_inventory
		else:
			player.inventory_data = []
 
	# load hotbar assignments — defaults to 9 empty strings if not in save
	# (covers fresh characters and pre-hotbar save files)
	if "hotbar_assignments" in player:
		var saved_hotbar = slot.get("hotbar_assignments", [])
		if typeof(saved_hotbar) == TYPE_ARRAY:
			player.hotbar_assignments = saved_hotbar
		else:
			player.hotbar_assignments = ["", "", "", "", "", "", "", "", ""]
 
	# NEW: load active_pet_id — defaults to "" (no pet) if not in save,
	# which covers both fresh characters and saves that predate this
	# feature. player.gd's _ready() calls _restore_active_pet() right
	# after this, which is what actually re-spawns the pet node.
	if "active_pet_id" in player:
		player.active_pet_id = str(slot.get("active_pet_id", ""))
			
func _capture_inventory(player: Node) -> Array:
	# pulls the live inventory contents from the open inventory container if
	# available, otherwise falls back to the player's cached inventory_data.
	#
	# NEW: the fallback paths are normalised now. ItemStack.to_dict() writes
	# `"quantity": int(quantity)`, so anything going through the container is
	# clean — but player.inventory_data is assigned STRAIGHT from the parsed
	# save (see load_character_state), so whatever type came out of JSON goes
	# back in untouched. A quantity that ever became a float stays a float
	# for the life of that save, because it never passes through to_dict()
	# again. That is how this save ended up with a lone
	# {"item_id": "tinyhealthpotion", "quantity": 16.0} among otherwise
	# integer values.
	var hud: Node = player.get_tree().get_first_node_in_group("hud")
	if hud == null:
		if "inventory_data" in player:
			return _normalise_item_array(player.inventory_data)
		return []

	if hud.inventory_screen != null:
		var container: Node = hud.inventory_screen.get_node_or_null("%inventorycontainer")
		if container != null and container.has_method("to_save_array"):
			return container.to_save_array()
 
	if "inventory_data" in player:
		return _normalise_item_array(player.inventory_data)
	return []


func _normalise_item_array(items: Array) -> Array:
	# NEW: forces quantity back to int on entries that never went through
	# ItemStack.to_dict(). See _capture_inventory() for how a float gets in
	# and why it then survives forever.
	#
	# Returns a NEW array and NEW entry dictionaries rather than mutating in
	# place — player.inventory_data may be the same Array instance the save
	# was loaded from, and rewriting it underneath its owner is the kind of
	# aliasing bug that only shows up much later.
	var normalised: Array = []

	for entry in items:
		if entry == null or typeof(entry) != TYPE_DICTIONARY:
			normalised.append(null)
			continue

		var copy: Dictionary = (entry as Dictionary).duplicate()
		if copy.has("quantity"):
			copy["quantity"] = int(copy["quantity"])
		normalised.append(copy)

	return normalised


# =============================================================================
# ACCOUNT-LEVEL ACCESS
# =============================================================================
# lusions, bank gold, bank inventory all live in account_data (shared across
# all 4 characters). each setter writes to disk immediately for atomic save.
 
# --- lusions (premium currency, soulbound) ---
 
func get_account_lusions() -> int:
	_ensure_account_data()
	return int(account_data.get("lusions", 0))
 
 
func set_account_lusions(value: int) -> void:
	_ensure_account_data()
	account_data["lusions"] = max(int(value), 0)
	save_data()
 
 
func add_account_lusions(amount: int) -> void:
	_ensure_account_data()
	account_data["lusions"] = max(int(account_data.get("lusions", 0)) + int(amount), 0)
	save_data()
 
 
# --- bank gold (account-shared, safe from death) ---
 
func get_bank_gold() -> int:
	_ensure_account_data()
	return int(account_data.get("bank_gold", 0))
 
 
func set_bank_gold(value: int) -> void:
	_ensure_account_data()
	account_data["bank_gold"] = max(int(value), 0)
	save_data()
 
 
func add_bank_gold(amount: int) -> void:
	_ensure_account_data()
	account_data["bank_gold"] = max(int(account_data.get("bank_gold", 0)) + int(amount), 0)
	save_data()
 
 
# --- bank inventory (account-shared, fixed-size) ---
 
func get_bank_inventory() -> Array:
	# returns the bank inventory contents — array of {item_id, quantity} or null.
	# size is always BANK_MAX_SLOTS after _ensure_account_data() runs.
	_ensure_account_data()
	return account_data["bank_inventory"]
 
 
func set_bank_inventory(items: Array) -> void:
	# overwrites the bank inventory. used by the bank UI when items change.
	# normalizes to BANK_MAX_SLOTS length to keep indices stable.
	_ensure_account_data()
	while items.size() < BANK_MAX_SLOTS:
		items.append(null)
	if items.size() > BANK_MAX_SLOTS:
		items.resize(BANK_MAX_SLOTS)
	account_data["bank_inventory"] = items
	save_data()
 
 
# =============================================================================
# BANK TRANSFERS
# =============================================================================
# atomic gold transfers between player carry pool and account-shared bank.
# both sides of the transfer happen in one save_data() so a crash mid-transfer
# can't desync the totals.
 
func deposit_gold_to_bank(amount: int, player: Node) -> bool:
	# transfer gold from the player's carry pool to the account-shared bank.
	# returns false if amount invalid or player can't afford it.
	var player_gold: int = int(player.get("gold")) if player.get("gold") != null else 0
	if amount <= 0 or player_gold < amount:
		return false
 
	player.set("gold", player_gold - amount)
	_ensure_account_data()
	account_data["bank_gold"] = int(account_data.get("bank_gold", 0)) + amount
 
	save_character_state(player)  # includes save_data() at the end
	return true
 
 
func withdraw_gold_from_bank(amount: int, player: Node) -> bool:
	# transfer gold from the account-shared bank to player's carry pool.
	# returns false if amount invalid or bank can't cover it.
	var player_gold: int = int(player.get("gold")) if player.get("gold") != null else 0
	_ensure_account_data()
	var current_bank: int = int(account_data.get("bank_gold", 0))
	if amount <= 0 or current_bank < amount:
		return false
 
	account_data["bank_gold"] = current_bank - amount
	player.set("gold", player_gold + amount)
 
	save_character_state(player)
	return true
 
 
# =============================================================================
# DEATH CLEANUP
# =============================================================================
# called from player.gd when the player dies WITHOUT a revive.
# clears carry items + carry gold. bank gold + bank inventory + lusions persist.
 
func clear_carry_on_death(player: Node) -> void:
	# zero out carry gold
	if "gold" in player:
		player.set("gold", 0)
 
	# clear live inventory container if open
	var hud: Node = player.get_tree().get_first_node_in_group("hud")
	if hud != null and hud.inventory_screen != null:
		var container: Node = hud.inventory_screen.get_node_or_null("%inventorycontainer")
		if container != null and container.has_method("clear_inventory"):
			container.clear_inventory()
 
	# clear stored inventory_data (used when no inventory screen exists)
	if "inventory_data" in player:
		player.inventory_data = []
 
	# clear hotbar assignments on true death — matches the carry-loss design.
	# revive path does NOT call this function, so hotbar survives revive.
	if "hotbar_assignments" in player:
		player.hotbar_assignments = ["", "", "", "", "", "", "", "", ""]
 
	# also reset the live hotbar UI if it exists, so the visual matches the data.
	# null-guarded — hotbar may not exist yet during early scene setup.
	if hud != null and hud.hotbar != null:
		hud.hotbar.clear_all()
 
	# persist immediately — anti-cheat / anti-relog-restore
	save_character_state(player)
# =============================================================================
# CHARACTER LOOKUP (DEATH/REVIVE SYSTEM)
# =============================================================================
 
func get_character_by_name(char_name: String) -> Dictionary:
	# look up a character slot by its name. returns empty dict if not found.
	# used by the gameover/revive flow to find the dying character's data.
	_ensure_slot_array()
	for slot in character_slots:
		if slot != null and slot.get("character", "") == char_name:
			return slot
	return {}
 
 
func save_character_slot(char_name: String, slot_data: Dictionary) -> bool:
	# overwrite a character's slot data by name. used by the revive system
	# to apply post-revive state (full HP, return position, etc.).
	# returns false if no slot with that name exists.
	_ensure_slot_array()
	for i in range(character_slots.size()):
		var slot = character_slots[i]
		if slot != null and slot.get("character", "") == char_name:
			character_slots[i] = slot_data
			return save_data()
	push_warning("CharacterData: no slot found for character '%s'" % char_name)
	return false
