# CharacterData.gd
extends Node

var character_slots = [null, null, null, null]
var active_character_index = 0

func _ensure_slot_array():
	if character_slots == null or typeof(character_slots) != TYPE_ARRAY or character_slots.size() != 4:
		character_slots = [null, null, null, null]

func save_data():
	_ensure_slot_array()
	var save_dict = {
		"character_slots": character_slots,
		"active_character_index": active_character_index
	}
	var file = FileAccess.open("user://character.save", FileAccess.WRITE)
	file.store_line(JSON.stringify(save_dict))
	file.close()

func load_data():
	if FileAccess.file_exists("user://character.save"):
		var file = FileAccess.open("user://character.save", FileAccess.READ)
		var line = file.get_line()
		file.close()
		var data = JSON.parse_string(line)
		if typeof(data) == TYPE_DICTIONARY:
			character_slots = data.get("character_slots", [null, null, null, null])
			active_character_index = data.get("active_character_index", 0)
	_ensure_slot_array() # Always ensure correct type and length, even if load fails
