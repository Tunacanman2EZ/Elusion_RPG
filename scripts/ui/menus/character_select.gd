"""
Character Slot Selection UI (Godot 4.5)

WHY: Lets players view, create, or select one of four character slots (Warrior, Mage, Tank, Healer).
HOW: Syncs slot data from CharacterData, updates labels/buttons, and transitions to game scene on selection.
WHAT: Handles empty slot prompts, prevents selecting uninitialized characters, and manages slot state UI.
TODO:
 - Genericize for more/fewer slots (array-driven).
 - Add delete/rename functionality per slot.
 - Show avatar/previews beside levels.
 - Animate selection and creation for richer feedback.
"""
extends Control

# Preloads the main game scene for quick selection transition.
var elusion_scene: PackedScene = preload("res://scenes/Elusion.tscn")

"""
Initializes slot data, loads character info from disk, and redraws UI.
WHY: Ensures all slots are valid arrays; guards against corrupted data.
TODO: Support loading icons/skins for each slot.
"""
func _ready() -> void:
	CharacterData.load_data()
	if CharacterData.character_slots == null or typeof(CharacterData.character_slots) != TYPE_ARRAY or CharacterData.character_slots.size() != 4:
		CharacterData.character_slots = [null, null, null, null]
	update_slot_labels()

"""
Update all labels and buttons to match current character_slots array.

WHY: Dynamically reflects slot state in UI (empty vs. taken, correct level/classes).
HOW: For each slot:
 - If slot is empty/malformed, show "Empty Slot" and enable Create.
 - If slot has class/level, show info and enable Select.
TODO: Extract loop for larger slot counts.
"""
func update_slot_labels() -> void:
	# Slot 1: Warrior
	var char1 = CharacterData.character_slots[0]
	if char1 == null or typeof(char1) != TYPE_DICTIONARY or not char1.has("class") or not char1.has("level"):
		%Label_1.text = "Empty Slot"
		%CreateButton_1.disabled = false
		%SelectButton_1.disabled = true
	else:
		%Label_1.text = "Level: %s" % str(char1["level"])
		%CreateButton_1.disabled = true
		%SelectButton_1.disabled = false

	# Slot 2: Mage
	var char2 = CharacterData.character_slots[1]
	if char2 == null or typeof(char2) != TYPE_DICTIONARY or not char2.has("class") or not char2.has("level"):
		%Label_2.text = "Empty Slot"
		%CreateButton_2.disabled = false
		%SelectButton_2.disabled = true
	else:
		%Label_2.text = "Level: %s" % str(char2["level"])
		%CreateButton_2.disabled = true
		%SelectButton_2.disabled = false

	# Slot 3: Tank
	var char3 = CharacterData.character_slots[2]
	if char3 == null or typeof(char3) != TYPE_DICTIONARY or not char3.has("class") or not char3.has("level"):
		%Label_3.text = "Empty Slot"
		%CreateButton_3.disabled = false
		%SelectButton_3.disabled = true
	else:
		%Label_3.text = "Level: %s" % str(char3["level"])
		%CreateButton_3.disabled = true
		%SelectButton_3.disabled = false

	# Slot 4: Healer
	var char4 = CharacterData.character_slots[3]
	if char4 == null or typeof(char4) != TYPE_DICTIONARY or not char4.has("class") or not char4.has("level"):
		%Label_4.text = "Empty Slot"
		%CreateButton_4.disabled = false
		%SelectButton_4.disabled = true
	else:
		%Label_4.text = "Level: %s" % str(char4["level"])
		%CreateButton_4.disabled = true
		%SelectButton_4.disabled = false

# Slot creation handlers—set new character with level 1
"""
On Create pressed, assigns a new character with starting level to relevant slot, then refreshes display.

WHY: Initializes character info for selected class/slot.
TODO: Ask for name/customization before creation.
"""
func _on_CreateButton_1_pressed() -> void:
	CharacterData.character_slots[0] = {"class": "Warrior", "level": 1}
	CharacterData.save_data()
	update_slot_labels()

func _on_CreateButton_2_pressed() -> void:
	CharacterData.character_slots[1] = {"class": "Mage", "level": 1}
	CharacterData.save_data()
	update_slot_labels()

func _on_CreateButton_3_pressed() -> void:
	CharacterData.character_slots[2] = {"class": "Tank", "level": 1}
	CharacterData.save_data()
	update_slot_labels()

func _on_CreateButton_4_pressed() -> void:
	CharacterData.character_slots[3] = {"class": "Healer", "level": 1}
	CharacterData.save_data()
	update_slot_labels()

# Slot select handlers—move to main game scene with chosen character/class
"""
Select handlers set the current active character index, 
then save and jump to the main game.

WHY: Only lets players select initialized slots; avoids index errors.
TODO: Fade screen or animate transition.
"""
func _on_SelectButton_1_pressed() -> void:
	_select_character(0, "Warrior")

func _on_SelectButton_2_pressed() -> void:
	_select_character(1, "Mage")

func _on_SelectButton_3_pressed() -> void:
	_select_character(2, "Tank")

func _on_SelectButton_4_pressed() -> void:
	_select_character(3, "Healer")

"""
Selects a character in the given slot, validates slot, and launches the game.

WHY: Prevents broken selection (like picking an empty slot).
TODO: Support per-character loadouts, achievements, stat recall.
"""
func _select_character(idx: int, _name: String) -> void:
	var slot = CharacterData.character_slots[idx]
	if slot == null or typeof(slot) != TYPE_DICTIONARY or not slot.has("class") or not slot.has("level"):
		print("No character in slot %d to select!" % [idx + 1])
		return
	print("Selected %s in slot %d" % [_name, idx + 1])
	CharacterData.active_character_index = idx
	CharacterData.save_data()
	get_tree().change_scene_to_packed(elusion_scene)
