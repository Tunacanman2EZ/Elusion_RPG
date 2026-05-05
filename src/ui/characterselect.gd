# character select screen — allows players to create and select characters
extends Control

# preload the main game scene so we can switch to it after selecting a character
var elusion_scene: PackedScene = preload("res://scene/elusion.tscn")

func _ready() -> void:
	# load saved character data from disk when screen opens
	CharacterData.load_data()

	# safety check — ensure character slots array is valid
	# resets to 4 empty slots if data is missing or corrupted
	if CharacterData.character_slots == null \
			or typeof(CharacterData.character_slots) != TYPE_ARRAY \
			or CharacterData.character_slots.size() != 4:
		CharacterData.character_slots = [null, null, null, null]

	# refresh the UI to show current slot data
	update_slot_labels()

func update_slot_labels() -> void:
	# get references to all 4 slot labels using unique name % syntax
	var labels = [%Label_1, %Label_2, %Label_3, %Label_4]

	# get references to all 4 create buttons
	var create_btns = [%CreateButton_1, %CreateButton_2, %CreateButton_3, %CreateButton_4]

	# get references to all 4 select buttons
	var select_btns = [%SelectButton_1, %SelectButton_2, %SelectButton_3, %SelectButton_4]

	# loop through all 4 slots and update the UI for each
	for i in range(4):
		# get the save data for this slot
		var slot = CharacterData.character_slots[i]

		# check if this slot has valid character data
		var is_valid = slot != null \
			and typeof(slot) == TYPE_DICTIONARY \
			and slot.has("character") \
			and slot.has("level")

		if is_valid:
			# slot has a character — show their name and level
			labels[i].text = "%s  |  level: %d" % [slot["character"], slot["level"]]

			# disable create button — slot is already taken
			create_btns[i].disabled = true

			# enable select button — player can enter this character
			select_btns[i].disabled = false
		else:
			# slot is empty — show placeholder text
			labels[i].text = "empty slot"

			# enable create button — player can create a character here
			create_btns[i].disabled = false

			# disable select button — no character to select
			select_btns[i].disabled = true

# --- create button handlers — one per slot ---

func _on_CreateButton_1_pressed() -> void:
	# create a warrior in slot 1 (index 0)
	CharacterData.create_character(0, "warrior")
	update_slot_labels()

func _on_CreateButton_2_pressed() -> void:
	# create a mage in slot 2 (index 1)
	CharacterData.create_character(1, "mage")
	update_slot_labels()

func _on_CreateButton_3_pressed() -> void:
	# create a tank in slot 3 (index 2)
	CharacterData.create_character(2, "tank")
	update_slot_labels()

func _on_CreateButton_4_pressed() -> void:
	# create a healer in slot 4 (index 3)
	CharacterData.create_character(3, "healer")
	update_slot_labels()

# --- select button handlers — one per slot ---

func _on_SelectButton_1_pressed() -> void:
	# select the character in slot 1
	_select_character(0, "warrior")

func _on_SelectButton_2_pressed() -> void:
	# select the character in slot 2
	_select_character(1, "mage")

func _on_SelectButton_3_pressed() -> void:
	# select the character in slot 3
	_select_character(2, "tank")

func _on_SelectButton_4_pressed() -> void:
	# select the character in slot 4
	_select_character(3, "healer")

func _select_character(idx: int, _name: String) -> void:
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
	print("selected %s in slot %d" % [_name, idx + 1])

	# store the selected slot index in characterdata autoload
	CharacterData.active_character_index = idx

	# save the active character selection to disk
	CharacterData.save_data()

	# switch to the main game scene
	get_tree().change_scene_to_packed(elusion_scene)
