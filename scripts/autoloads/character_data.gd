"""
Character Slots Manager Singleton (Godot 4.5)

WHY: Centralized, always-available global for up to four playable character save slots.
HOW: Stores all slot data, tracks which slot is active, and handles save/load to disk.
WHAT: Designed for easy future expansion—currently supports four fixed slots and basic persistence.
TODO:
 - Allow for more than four slots (dynamic array).
 - Support slot renaming, deletion, or reordering.
 - Add timestamp/metadata per slot for UX.
 - Encrypt or protect save data for security.
"""
extends Node

# --- MAIN SLOT DATA ---
## Four character slots, one per possible toon. Each can be null or Dictionary.
var character_slots: Array = [null, null, null, null]

## Index of currently selected/active character (used for spawning, stat screen, etc).
var active_character_index: int = 0

"""
Ensures character_slots is always a valid 4-slot array.

WHY: Protects against corruption or version mismatches after game updates.
HOW: Fixes bad/null arrays after load, or if code accidentally reassigns/clears slots.
"""
func _ensure_slot_array():
	if character_slots == null \
			or typeof(character_slots) != TYPE_ARRAY \
			or character_slots.size() != 4:
		character_slots = [null, null, null, null]

"""
Serializes slot data and active index to local storage.

WHY: Stores progress and switches; always call before exiting, switching slots, or at key checkpoints.
TODO: Migrate to multi-file saves (one per slot), add slot-specific backups.
"""
func save_data():
	_ensure_slot_array()
	var save_dict = {
		"character_slots": character_slots,
		"active_character_index": active_character_index
	}
	var file = FileAccess.open("user://character.save", FileAccess.WRITE)
	file.store_line(JSON.stringify(save_dict))
	file.close()

"""
Restores slot data and active index from disk (if present).

WHY: Ensures persistent progress; creates empty slots if no save found or if corrupt.
TODO: Handle load failures more robustly and signal errors to UI.
"""
func load_data():
	if FileAccess.file_exists("user://character.save"):
		var file = FileAccess.open("user://character.save", FileAccess.READ)
		var line = file.get_line()
		file.close()
		var data = JSON.parse_string(line)
		if typeof(data) == TYPE_DICTIONARY:
			character_slots = data.get("character_slots", [null, null, null, null])
			active_character_index = data.get("active_character_index", 0)
	_ensure_slot_array()
