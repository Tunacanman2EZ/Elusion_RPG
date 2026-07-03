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
extends Node


# =============================================================================
# CONSTANTS
# =============================================================================

# version of the save file format — increment when format changes incompatibly
const SAVE_VERSION := 2

# bank holds up to this many item slots, fixed-size for stable indices
const BANK_MAX_SLOTS := 50

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
}

# default account_data structure — used for fresh installs and migrations
const DEFAULT_ACCOUNT_DATA := {
	"lusions":         0,    # account-shared, soulbound premium currency
	"bank_gold":       0,    # account-shared, safe from death
	"bank_inventory":  [],   # account-shared item array (50 slots)
}


# =============================================================================
# STATE
# =============================================================================

# storage backend — LocalStorage (file) for now, ServerStorage later
var storage: LocalStorage = LocalStorage.new()

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
	print("=== CHARACTERDATA READY ===")
	_initialize_account_data()
	load_data()


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
# SAVE / LOAD
# =============================================================================

func save_data() -> bool:
	# writes everything to disk via the storage backend. called from many
	# places: any atomic write (gold pickup, XP gain, bank deposit, lusions
	# change). the storage backend handles the actual file I/O.
	_ensure_slot_array()
	_ensure_account_data()
	var payload := {
		"version":                 SAVE_VERSION,
		"character_slots":         character_slots,
		"active_character_index":  active_character_index,
		"account_data":            account_data,
	}
	return storage.save(payload)


func load_data() -> bool:
	# reads from disk and reconstructs character + account state.
	# empty data means fresh install — initialize defaults and return false.
	var data := storage.load()
	if data.is_empty():
		_ensure_slot_array()
		_ensure_account_data()
		return false

	data = _migrate_save(data)
	character_slots = data.get("character_slots", [null, null, null, null])
	active_character_index = data.get("active_character_index", 0)
	account_data = data.get("account_data", DEFAULT_ACCOUNT_DATA.duplicate(true))

	_ensure_slot_array()
	_ensure_account_data()
	return true


# =============================================================================
# SAVE MIGRATION
# =============================================================================

func _migrate_save(data: Dictionary) -> Dictionary:
	# converts old save format to current SAVE_VERSION. runs on every load.
	# safe to call on already-current saves (no-op if version is up to date).
	var version: int = data.get("version", 0)
	if version < SAVE_VERSION:
		print("migrating save from version %d to %d" % [version, SAVE_VERSION])

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
			
func _capture_inventory(player: Node) -> Array:
	# pulls the live inventory contents from the open inventory container if
	# available, otherwise falls back to the player's cached inventory_data.
	var hud: Node = player.get_tree().get_first_node_in_group("hud")
	if hud == null:
		if "inventory_data" in player:
			return player.inventory_data
		return []

	if hud.inventory_screen != null:
		var container: Node = hud.inventory_screen.get_node_or_null("%inventorycontainer")
		if container != null and container.has_method("to_save_array"):
			return container.to_save_array()

	if "inventory_data" in player:
		return player.inventory_data
	return []


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
