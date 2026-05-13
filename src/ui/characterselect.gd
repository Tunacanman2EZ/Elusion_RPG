# character select screen — allows players to create and select characters
extends Control

# preloaded reference to the main game scene
const ELUSION_SCENE := preload("res://scene/elusion.tscn")

# class assigned to each slot — slot index maps to class name
const SLOT_CLASSES := ["warrior", "mage", "tank", "healer"]

func _ready() -> void:
	# refresh save data from disk
	# CharacterData also loads on autoload init, but we reload here
	# in case the player just logged out and saved progress
	CharacterData.load_data()

	# refresh the UI to show current slot data
	update_slot_labels()

func update_slot_labels() -> void:
	# get references to slot UI nodes via unique name % syntax
	var labels = [%label1, %label2, %label3, %label4]
	var create_btns = [%createbutton1, %createbutton2, %createbutton3, %createbutton4]
	var select_btns = [%selectbutton1, %selectbutton2, %selectbutton3, %selectbutton4]

	# loop through all 4 slots and update the UI for each
	for i in range(4):
		var slot = CharacterData.character_slots[i]

		# check if this slot has valid character data
		var is_valid: bool = slot != null \
			and typeof(slot) == TYPE_DICTIONARY \
			and slot.has("character") \
			and slot.has("level")

		if is_valid:
			# slot has a character — show their name and level
			labels[i].text = "%s  |  level: %d" % [slot["character"], slot["level"]]
			create_btns[i].disabled = true   # slot taken — can't create
			select_btns[i].disabled = false  # character exists — can select
		else:
			# slot is empty — show placeholder
			labels[i].text = "empty slot"
			create_btns[i].disabled = false  # empty — can create
			select_btns[i].disabled = true   # no character — can't select

# --- create button handlers — one per slot ---
# these are connected via the editor signals panel.
# function names must match the connections in the .tscn file.

func _on_createbutton1_pressed() -> void:
	CharacterData.create_character(0, SLOT_CLASSES[0])
	update_slot_labels()

func _on_createbutton2_pressed() -> void:
	CharacterData.create_character(1, SLOT_CLASSES[1])
	update_slot_labels()

func _on_createbutton3_pressed() -> void:
	CharacterData.create_character(2, SLOT_CLASSES[2])
	update_slot_labels()

func _on_createbutton4_pressed() -> void:
	CharacterData.create_character(3, SLOT_CLASSES[3])
	update_slot_labels()

# --- select button handlers — one per slot ---

func _on_selectbutton1_pressed() -> void:
	_select_character(0)

func _on_selectbutton2_pressed() -> void:
	_select_character(1)

func _on_selectbutton3_pressed() -> void:
	_select_character(2)

func _on_selectbutton4_pressed() -> void:
	_select_character(3)

func _select_character(idx: int) -> void:
	# get the save data for the selected slot
	var slot = CharacterData.character_slots[idx]

	# validate the slot has a real character before proceeding
	if slot == null \
			or typeof(slot) != TYPE_DICTIONARY \
			or not slot.has("character") \
			or not slot.has("level"):
		print("no character in slot %d to select!" % [idx + 1])
		return

	# confirm selection in the output panel
	print("selected %s in slot %d" % [slot["character"], idx + 1])

	# set this slot as the active character
	CharacterData.active_character_index = idx

	# save the active selection to disk
	CharacterData.save_data()

	# switch to the main game scene
	# the player's _ready() should call CharacterData.load_character_state(self)
	# to pull stats from the slot into the player instance
	get_tree().change_scene_to_packed(ELUSION_SCENE)
