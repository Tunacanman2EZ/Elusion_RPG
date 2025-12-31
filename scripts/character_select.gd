extends Control

func _ready():
	CharacterData.load_data()
	if CharacterData.character_slots == null or typeof(CharacterData.character_slots) != TYPE_ARRAY or CharacterData.character_slots.size() != 4:
		CharacterData.character_slots = [null, null, null, null]
	update_slot_labels()

func update_slot_labels():
	var char1 = CharacterData.character_slots[0]
	if char1 == null or typeof(char1) != TYPE_DICTIONARY or not char1.has("class") or not char1.has("level"):
		$CenterContainer/VBoxContainer/Warrior/Label_1.text = "Empty Slot"
		$CenterContainer/VBoxContainer/Warrior/CreateButton_1.disabled = false
		$CenterContainer/VBoxContainer/Warrior/SelectButton_1.disabled = true
	else:
		$CenterContainer/VBoxContainer/Warrior/Label_1.text = "Class: %s\nLevel: %s" % [char1["class"], str(char1["level"])]
		$CenterContainer/VBoxContainer/Warrior/CreateButton_1.disabled = true
		$CenterContainer/VBoxContainer/Warrior/SelectButton_1.disabled = false

	var char2 = CharacterData.character_slots[1]
	if char2 == null or typeof(char2) != TYPE_DICTIONARY or not char2.has("class") or not char2.has("level"):
		$CenterContainer/VBoxContainer/Mage/Label_2.text = "Empty Slot"
		$CenterContainer/VBoxContainer/Mage/CreateButton_2.disabled = false
		$CenterContainer/VBoxContainer/Mage/SelectButton_2.disabled = true
	else:
		$CenterContainer/VBoxContainer/Mage/Label_2.text = "Class: %s\nLevel: %s" % [char2["class"], str(char2["level"])]
		$CenterContainer/VBoxContainer/Mage/CreateButton_2.disabled = true
		$CenterContainer/VBoxContainer/Mage/SelectButton_2.disabled = false

	var char3 = CharacterData.character_slots[2]
	if char3 == null or typeof(char3) != TYPE_DICTIONARY or not char3.has("class") or not char3.has("level"):
		$CenterContainer/VBoxContainer/Tank/Label_3.text = "Empty Slot"
		$CenterContainer/VBoxContainer/Tank/CreateButton_3.disabled = false
		$CenterContainer/VBoxContainer/Tank/SelectButton_3.disabled = true
	else:
		$CenterContainer/VBoxContainer/Tank/Label_3.text = "Class: %s\nLevel: %s" % [char3["class"], str(char3["level"])]
		$CenterContainer/VBoxContainer/Tank/CreateButton_3.disabled = true
		$CenterContainer/VBoxContainer/Tank/SelectButton_3.disabled = false

	var char4 = CharacterData.character_slots[3]
	if char4 == null or typeof(char4) != TYPE_DICTIONARY or not char4.has("class") or not char4.has("level"):
		$CenterContainer/VBoxContainer/Healer/Label_4.text = "Empty Slot"
		$CenterContainer/VBoxContainer/Healer/CreateButton_4.disabled = false
		$CenterContainer/VBoxContainer/Healer/SelectButton_4.disabled = true
	else:
		$CenterContainer/VBoxContainer/Healer/Label_4.text = "Class: %s\nLevel: %s" % [char4["class"], str(char4["level"])]
		$CenterContainer/VBoxContainer/Healer/CreateButton_4.disabled = true
		$CenterContainer/VBoxContainer/Healer/SelectButton_4.disabled = false

func _on_CreateButton_1_pressed():
	CharacterData.character_slots[0] = {"class": "Warrior", "level": 1}
	CharacterData.save_data()
	update_slot_labels()

func _on_CreateButton_2_pressed():
	CharacterData.character_slots[1] = {"class": "Mage", "level": 1}
	CharacterData.save_data()
	update_slot_labels()

func _on_CreateButton_3_pressed():
	CharacterData.character_slots[2] = {"class": "Tank", "level": 1}
	CharacterData.save_data()
	update_slot_labels()

func _on_CreateButton_4_pressed():
	CharacterData.character_slots[3] = {"class": "Healer", "level": 1}
	CharacterData.save_data()
	update_slot_labels()

func _on_SelectButton_1_pressed():
	_select_character(0, "Warrior")

func _on_SelectButton_2_pressed():
	_select_character(1, "Mage")

func _on_SelectButton_3_pressed():
	_select_character(2, "Tank")

func _on_SelectButton_4_pressed():
	_select_character(3, "Healer")

func _select_character(idx: int, char_class: String) -> void:
	var char = CharacterData.character_slots[idx]
	if char == null or typeof(char) != TYPE_DICTIONARY or not char.has("class") or not char.has("level"):
		print("No character in slot %d to select!" % [idx + 1])
		return
	print("Selected %s in slot %d" % [char_class, idx + 1])
	CharacterData.active_character_index = idx
	CharacterData.save_data()
	get_tree().change_scene_to_file("res://Elusion.tscn")
