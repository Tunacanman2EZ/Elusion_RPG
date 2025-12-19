# CharacterData.gd
extends Node

var character_slots = []
var active_character_index = 0

func save_data():
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
			character_slots = data.get("character_slots", [])
			active_character_index = data.get("active_character_index", 0)
