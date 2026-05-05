# autoload system for managing character save slots and persistent data
extends Node

# array of 4 save slots — each slot is a dictionary or null if empty
var character_slots: Array = [null, null, null, null]

# index of the currently selected character slot (0-3)
var active_character_index: int = 0

func _ready():
	# confirm characterdata autoload is running
	print("=== CHARACTERDATA READY ===")
	# load saved data from disk on startup
	load_data()

func _ensure_slot_array():
	# safety check — if character_slots is invalid reset it to 4 empty slots
	# this prevents crashes if the save file corrupts the array
	if character_slots == null \
			or typeof(character_slots) != TYPE_ARRAY \
			or character_slots.size() != 4:
		character_slots = [null, null, null, null]

func save_data():
	# make sure slot array is valid before saving
	_ensure_slot_array()

	# open the save file for writing — creates it if it doesn't exist
	var file = FileAccess.open("user://character.save", FileAccess.WRITE)

	# if file failed to open show an error and stop
	if file == null:
		push_error("failed to open save file for writing!")
		return

	# convert the save data to JSON and write it as a single line
	file.store_line(JSON.stringify({
		"character_slots": character_slots,
		"active_character_index": active_character_index
	}))

	# close the file after writing
	file.close()

func load_data() -> bool:
	# tracks whether loading succeeded
	var loaded_ok := false

	# check if a save file exists before trying to open it
	if FileAccess.file_exists("user://character.save"):
		# open the save file for reading
		var file = FileAccess.open("user://character.save", FileAccess.READ)

		# read the first line of the file
		var line = file.get_line()

		# close the file after reading
		file.close()

		# parse the JSON string back into a dictionary
		var data = JSON.parse_string(line)

		# check that the parsed data is a valid dictionary
		if typeof(data) == TYPE_DICTIONARY:
			# restore character slots from save data
			character_slots = data.get("character_slots", [null, null, null, null])

			# restore which character slot was last selected
			active_character_index = data.get("active_character_index", 0)

			# mark loading as successful
			loaded_ok = true
		else:
			# save file exists but data is invalid — use defaults
			print("save file corrupted, using defaults")
	else:
		# no save file found — first time playing
		print("no save file found, using defaults")

	# ensure slot array is valid after loading
	_ensure_slot_array()

	# return whether loading succeeded
	return loaded_ok

func create_character(slot_idx: int, character_name: String) -> void:
	# make sure slot array is valid before creating
	_ensure_slot_array()

	# create a new character dictionary with default starting stats
	character_slots[slot_idx] = {
		"character": character_name, # the character class name e.g. "warrior"
		"level": 1,                  # starting level
		"xp": 0,                     # starting xp
		"xp_next": 100,              # xp needed for next level
		"gold": 0,                   # starting gold
		"lusions": 0,                # starting lusions (premium currency)
		"hp": 100,                   # starting current hp
		"max_hp": 100,               # starting max hp
		"stamina": 100,              # starting current stamina
		"max_stamina": 100,          # starting max stamina
		"mana": 100,                 # starting current mana
		"max_mana": 100,             # starting max mana
		"attack": 1,                 # starting attack skill level
		"defense": 1,                # starting defense skill level
		"agility": 1,                # starting agility skill level
		"magic": 1,                  # starting magic skill level
		"fishing": 1,                # starting fishing skill level
		"cooking": 1                 # starting cooking skill level
	}

	# save immediately after creating character
	save_data()

func save_character_state(player: Node) -> void:
	# make sure slot array is valid before saving
	_ensure_slot_array()

	# get the current active slot index
	var slot = active_character_index

	# if the slot is empty there is nothing to save
	if character_slots[slot] == null:
		return

	# copy all current player stats into the save slot dictionary
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

	# write the updated data to disk
	save_data()

func load_character_state(player: Node) -> void:
	# make sure slot array is valid before loading
	_ensure_slot_array()

	# get the save data dictionary for the active slot
	var slot = character_slots[active_character_index]

	# if the slot is empty there is nothing to load
	if slot == null:
		return

	# restore all player stats from the save slot
	# second argument is the default value if the key doesn't exist
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
