extends Node

## Character Slots Manager Singleton
## Manages up to 4 character save slots

## Four character slots for up to 4 characters
var character_slots: Array = [null, null, null, null]
## Index of the currently active character
var active_character_index: int = 0


## Ensures slot array is always valid
func _ensure_slot_array():
	if character_slots == null \
			or typeof(character_slots) != TYPE_ARRAY \
			or character_slots.size() != 4:
		character_slots = [null, null, null, null]


## Save current slots and active index to disk
func save_data():
	_ensure_slot_array()
	var save_dict = {
		"character_slots": character_slots,
		"active_character_index": active_character_index
	}
	var file = FileAccess.open("user://character.save", FileAccess.WRITE)
	file.store_line(JSON.stringify(save_dict))
	file.close()


## Load slots and active from disk if present
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

