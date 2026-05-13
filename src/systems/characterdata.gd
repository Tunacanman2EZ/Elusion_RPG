# autoload system for managing character save slots and persistent data.
# this script knows about characters, stats, and slots.
# storage (where the data lives) is delegated to a backend object —
# currently LocalStorage (file-based), swappable for ServerStorage later.
extends Node

# version of the save file format — increment when the format changes incompatibly
# old saves are upgraded through _migrate_save() on load
const SAVE_VERSION := 1

# central definition of all stats that get saved per character.
# adding a new stat means adding ONE entry here — save, load, and create
# all read from this list automatically.
const SAVEABLE_STATS := {
	"level":        1,
	"xp":           0,
	"xp_next":      100,
	"gold":         0,
	"lusions":      0,
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

# storage backend — handles the actual persistence of data.
# swap LocalStorage for ServerStorage when going networked.
var storage: LocalStorage = LocalStorage.new()

# array of 4 save slots — each slot is a dictionary or null if empty
var character_slots: Array = [null, null, null, null]

# index of the currently selected character slot (0-3)
var active_character_index: int = 0

func _ready():
	print("=== CHARACTERDATA READY ===")
	load_data()

func _ensure_slot_array():
	if character_slots == null \
			or typeof(character_slots) != TYPE_ARRAY \
			or character_slots.size() != 4:
		character_slots = [null, null, null, null]

func save_data() -> bool:
	_ensure_slot_array()

	var payload := {
		"version": SAVE_VERSION,
		"character_slots": character_slots,
		"active_character_index": active_character_index,
	}

	return storage.save(payload)

func load_data() -> bool:
	var data := storage.load()

	if data.is_empty():
		_ensure_slot_array()
		return false

	data = _migrate_save(data)
	character_slots = data.get("character_slots", [null, null, null, null])
	active_character_index = data.get("active_character_index", 0)
	_ensure_slot_array()
	return true

func _migrate_save(data: Dictionary) -> Dictionary:
	var version: int = data.get("version", 0)

	if version < SAVE_VERSION:
		print("migrating save from version %d to %d" % [version, SAVE_VERSION])

	# example template for future migrations:
	# if version < 2:
	#     ...

	data["version"] = SAVE_VERSION
	return data

func create_character(slot_idx: int, character_name: String) -> void:
	_ensure_slot_array()

	var new_char := {"character": character_name}
	for stat in SAVEABLE_STATS:
		new_char[stat] = SAVEABLE_STATS[stat]

	# new characters start with empty inventory
	new_char["inventory"] = []

	character_slots[slot_idx] = new_char
	save_data()

func save_character_state(player: Node) -> void:
	# saves player stats AND inventory to the active slot.
	# called on logout, periodic auto-save, etc.

	_ensure_slot_array()

	var slot: int = active_character_index

	if character_slots[slot] == null:
		return

	# loop through every saveable stat and copy it from the player.
	# wrap in int() to force-cast against any drift to float during play —
	# protects against floats accumulating across save/load cycles.
	for stat in SAVEABLE_STATS:
		if stat in player:
			character_slots[slot][stat] = int(player.get(stat))

	# save the inventory — read from the live inventory container if available,
	# otherwise fall back to the player's last-known inventory_data
	character_slots[slot]["inventory"] = _capture_inventory(player)

	save_data()

func load_character_state(player: Node) -> void:
	# loads player stats AND inventory data from the active slot.
	# the player should call apply_inventory_to_screen() once the inventory
	# UI is available — at scene load, this just stores the data on the player.

	_ensure_slot_array()

	var slot: Dictionary = character_slots[active_character_index]
	if slot == null:
		return

	# loop through every saveable stat and assign it to the player.
	# wrap in int() to protect against legacy floats in old save files.
	# falls back to the default from SAVEABLE_STATS if the key is missing.
	for stat in SAVEABLE_STATS:
		if stat in player:
			var default_value: int = SAVEABLE_STATS[stat]
			var saved_value = slot.get(stat, default_value)
			player.set(stat, int(saved_value))

	# load inventory data onto the player — the player applies it to the UI
	# when the inventory_screen exists (lazy init handles this)
	if "inventory_data" in player:
		var saved_inventory = slot.get("inventory", [])
		if typeof(saved_inventory) == TYPE_ARRAY:
			player.inventory_data = saved_inventory
		else:
			player.inventory_data = []

func _capture_inventory(player: Node) -> Array:
	# tries to get the live inventory from the open inventory screen.
	# falls back to the player's stored inventory_data if no screen exists.
	# this handles the case where the player logs out without ever opening
	# the inventory — we still save their last-known inventory state.

	# look up the HUD by group
	var hud: Node = player.get_tree().get_first_node_in_group("hud")
	if hud == null:
		# no HUD — use whatever the player has stored
		if "inventory_data" in player:
			return player.inventory_data
		return []

	# inventory screen exists — pull live data from it
	if hud.inventory_screen != null:
		var container: Node = hud.inventory_screen.get_node_or_null("%inventorycontainer")
		if container != null and container.has_method("to_save_array"):
			return container.to_save_array()

	# inventory screen doesn't exist (player never opened it this session) —
	# return the inventory_data we loaded at session start, unchanged
	if "inventory_data" in player:
		return player.inventory_data
	return []
	
	# --- public helpers used by the death/revive system ---
# these let other systems (like gameover.gd) read/write a character's slot
# by name rather than by index. handy when the player is between scenes
# and we need to update saved state without an active player node.

func get_character_by_name(char_name: String) -> Dictionary:
	# look up a character slot by character_name field.
	# returns the slot dict, or an empty dict if no slot matches.
	_ensure_slot_array()
	for slot in character_slots:
		if slot != null and slot.get("character", "") == char_name:
			return slot
	return {}

func save_character_slot(char_name: String, slot_data: Dictionary) -> bool:
	# overwrite the named character slot with new data and persist to disk.
	# this is the bridge that lets non-player scripts (like gameover.gd)
	# write back to the save file without needing a player node reference.
	_ensure_slot_array()
	for i in range(character_slots.size()):
		var slot = character_slots[i]
		if slot != null and slot.get("character", "") == char_name:
			character_slots[i] = slot_data
			return save_data()
	push_warning("CharacterData: no slot found for character '%s'" % char_name)
	return false
