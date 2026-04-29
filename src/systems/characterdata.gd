extends Node

var character_slots: Array = [null, null, null, null]
var active_character_index: int = 0

func _ready():
	print("=== CHARACTERDATA READY ===")
	load_data()

func _ensure_slot_array():
	if character_slots == null \
			or typeof(character_slots) != TYPE_ARRAY \
			or character_slots.size() != 4:
		character_slots = [null, null, null, null]

func save_data():
	_ensure_slot_array()
	var file = FileAccess.open("user://character.save", FileAccess.WRITE)
	if file == null:
		push_error("failed to open save file for writing!")
		return
	file.store_line(JSON.stringify({
		"character_slots": character_slots,
		"active_character_index": active_character_index
	}))
	file.close()

func load_data() -> bool:
	var loaded_ok := false
	if FileAccess.file_exists("user://character.save"):
		var file = FileAccess.open("user://character.save", FileAccess.READ)
		var line = file.get_line()
		file.close()
		var data = JSON.parse_string(line)
		if typeof(data) == TYPE_DICTIONARY:
			character_slots = data.get("character_slots", [null, null, null, null])
			active_character_index = data.get("active_character_index", 0)
			loaded_ok = true
		else:
			print("save file corrupted, using defaults")
	else:
		print("no save file found, using defaults")
	_ensure_slot_array()
	return loaded_ok

func create_character(slot_idx: int, character_name: String) -> void:
	_ensure_slot_array()
	character_slots[slot_idx] = {
		"character": character_name,
		"level": 1,
		"xp": 0,
		"xp_next": 100,
		"gold": 0,
		"lusions": 0,
		"hp": 100,
		"max_hp": 100,
		"stamina": 100,
		"max_stamina": 100,
		"mana": 100,
		"max_mana": 100,
		"attack": 1,
		"defense": 1,
		"agility": 1,
		"magic": 1,
		"fishing": 1,
		"cooking": 1
	}
	save_data()

func save_character_state(player: Node) -> void:
	_ensure_slot_array()
	var slot = active_character_index
	if character_slots[slot] == null:
		return
	character_slots[slot]["level"]       = player.level
	character_slots[slot]["xp"]          = player.xp
	character_slots[slot]["xp_next"]     = player.xp_next
	character_slots[slot]["gold"]        = player.gold
	character_slots[slot]["lusions"]     = player.lusions
	character_slots[slot]["hp"]          = player.hp
	character_slots[slot]["max_hp"]      = player.max_hp
	character_slots[slot]["stamina"]     = player.stamina
	character_slots[slot]["max_stamina"] = player.max_stamina
	character_slots[slot]["mana"]        = player.mana
	character_slots[slot]["max_mana"]    = player.max_mana
	character_slots[slot]["attack"]      = player.attack
	character_slots[slot]["defense"]     = player.defense
	character_slots[slot]["agility"]     = player.agility
	character_slots[slot]["magic"]       = player.magic
	character_slots[slot]["fishing"]     = player.fishing
	character_slots[slot]["cooking"]     = player.cooking
	save_data()

func load_character_state(player: Node) -> void:
	_ensure_slot_array()
	var slot = character_slots[active_character_index]
	if slot == null:
		return
	player.level       = slot.get("level", 1)
	player.xp          = slot.get("xp", 0)
	player.xp_next     = slot.get("xp_next", 100)
	player.gold        = slot.get("gold", 0)
	player.lusions     = slot.get("lusions", 0)
	player.hp          = slot.get("hp", 100)
	player.max_hp      = slot.get("max_hp", 100)
	player.stamina     = slot.get("stamina", 100)
	player.max_stamina = slot.get("max_stamina", 100)
	player.mana        = slot.get("mana", 100)
	player.max_mana    = slot.get("max_mana", 100)
	player.attack      = slot.get("attack", 1)
	player.defense     = slot.get("defense", 1)
	player.agility     = slot.get("agility", 1)
	player.magic       = slot.get("magic", 1)
	player.fishing     = slot.get("fishing", 1)
	player.cooking     = slot.get("cooking", 1)
