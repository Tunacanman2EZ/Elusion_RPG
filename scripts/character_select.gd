extends Control

func _ready():
	CharacterData.load_data()
	while CharacterData.character_slots.size() < 4:
		CharacterData.character_slots.append(null)
	update_slot_labels()

func update_slot_labels():
	# Warrior slot
	if CharacterData.character_slots[0] == null:
		$CenterContainer/VBoxContainer/Warrior/Label_1.text = "Empty Slot"
		$CenterContainer/VBoxContainer/Warrior/CreateButton_1.disabled = false
		$CenterContainer/VBoxContainer/Warrior/SelectButton_1.disabled = true
	else:
		var char1 = CharacterData.character_slots[0]
		$CenterContainer/VBoxContainer/Warrior/Label_1.text = "Class: %s\nLevel: %s" % [char1["class"], str(char1["level"])]
		$CenterContainer/VBoxContainer/Warrior/CreateButton_1.disabled = true
		$CenterContainer/VBoxContainer/Warrior/SelectButton_1.disabled = false

	# Mage slot
	if CharacterData.character_slots[1] == null:
		$CenterContainer/VBoxContainer/Mage/Label_2.text = "Empty Slot"
		$CenterContainer/VBoxContainer/Mage/CreateButton_2.disabled = false
		$CenterContainer/VBoxContainer/Mage/SelectButton_2.disabled = true
	else:
		var char2 = CharacterData.character_slots[1]
		$CenterContainer/VBoxContainer/Mage/Label_2.text = "Class: %s\nLevel: %s" % [char2["class"], str(char2["level"])]
		$CenterContainer/VBoxContainer/Mage/CreateButton_2.disabled = true
		$CenterContainer/VBoxContainer/Mage/SelectButton_2.disabled = false

	# Tank slot
	if CharacterData.character_slots[2] == null:
		$CenterContainer/VBoxContainer/Tank/Label_3.text = "Empty Slot"
		$CenterContainer/VBoxContainer/Tank/CreateButton_3.disabled = false
		$CenterContainer/VBoxContainer/Tank/SelectButton_3.disabled = true
	else:
		var char3 = CharacterData.character_slots[2]
		$CenterContainer/VBoxContainer/Tank/Label_3.text = "Class: %s\nLevel: %s" % [char3["class"], str(char3["level"])]
		$CenterContainer/VBoxContainer/Tank/CreateButton_3.disabled = true
		$CenterContainer/VBoxContainer/Tank/SelectButton_3.disabled = false

	# Healer slot
	if CharacterData.character_slots[3] == null:
		$CenterContainer/VBoxContainer/Healer/Label_4.text = "Empty Slot"
		$CenterContainer/VBoxContainer/Healer/CreateButton_4.disabled = false
		$CenterContainer/VBoxContainer/Healer/SelectButton_4.disabled = true
	else:
		var char4 = CharacterData.character_slots[3]
		$CenterContainer/VBoxContainer/Healer/Label_4.text = "Class: %s\nLevel: %s" % [char4["class"], str(char4["level"])]
		$CenterContainer/VBoxContainer/Healer/CreateButton_4.disabled = true
		$CenterContainer/VBoxContainer/Healer/SelectButton_4.disabled = false

func _on_SelectButton_1_pressed():
	_select_character(0, "Warrior")

func _on_SelectButton_2_pressed():
	_select_character(1, "Mage")

func _on_SelectButton_3_pressed():
	_select_character(2, "Tank")

func _on_SelectButton_4_pressed():
	_select_character(3, "Healer")
