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
	if CharacterData.character_slots[0] == null:
		print("No character in slot 1 to select!")
		return
	print("Selected Warrior in slot 1")
	CharacterData.active_character_index = 0
	CharacterData.save_data()
	get_tree().change_scene_to_file("res://scenes/GameScene.tscn")

func _on_SelectButton_2_pressed():
	if CharacterData.character_slots[1] == null:
		print("No character in slot 2 to select!")
		return
	print("Selected Mage in slot 2")
	CharacterData.active_character_index = 1
	CharacterData.save_data()
	get_tree().change_scene_to_file("res://scenes/GameScene.tscn")

func _on_SelectButton_3_pressed():
	if CharacterData.character_slots[2] == null:
		print("No character in slot 3 to select!")
		return
	print("Selected Tank in slot 3")
	CharacterData.active_character_index = 2
	CharacterData.save_data()
	get_tree().change_scene_to_file("res://scenes/GameScene.tscn")

func _on_SelectButton_4_pressed():
	if CharacterData.character_slots[3] == null:
		print("No character in slot 4 to select!")
		return
	print("Selected Healer in slot 4")
	CharacterData.active_character_index = 3
	CharacterData.save_data()
	get_tree().change_scene_to_file("res://scenes/GameScene.tscn")


func _on_create_button_1_pressed() -> void:
	if CharacterData.character_slots[0] != null:
		print("Slot 1 already filled! Cannot create another character here.")
		return
	CharacterData.character_slots[0] = {"class": "Warrior", "level": 1}
	CharacterData.save_data()
	update_slot_labels()

func _on_select_button_1_pressed() -> void:
	if CharacterData.character_slots[0] == null:
		print("No character in slot 1 to select!")
		return
	print("Selected Warrior in slot 1")
	CharacterData.active_character_index = 0
	CharacterData.save_data()
	get_tree().change_scene_to_file("res://scenes/GameScene.tscn")


func _on_create_button_2_pressed() -> void:
	if CharacterData.character_slots[1] != null:
		print("Slot 2 already filled! Cannot create another character here.")
		return
	CharacterData.character_slots[1] = {"class": "Mage", "level": 1}
	CharacterData.save_data()
	update_slot_labels()

func _on_select_button_2_pressed() -> void:
	if CharacterData.character_slots[1] == null:
		print("No character in slot 2 to select!")
		return
	print("Selected Mage in slot 2")
	CharacterData.active_character_index = 1
	CharacterData.save_data()
	get_tree().change_scene_to_file("res://scenes/GameScene.tscn")


func _on_create_button_3_pressed() -> void:
	if CharacterData.character_slots[2] != null:
		print("Slot 3 already filled! Cannot create another character here.")
		return
	CharacterData.character_slots[2] = {"class": "Tank", "level": 1}
	CharacterData.save_data()
	update_slot_labels()

func _on_select_button_3_pressed() -> void:
	if CharacterData.character_slots[2] == null:
		print("No character in slot 3 to select!")
		return
	print("Selected Tank in slot 3")
	CharacterData.active_character_index = 2
	CharacterData.save_data()
	get_tree().change_scene_to_file("res://scenes/GameScene.tscn")


func _on_create_button_4_pressed() -> void:
	if CharacterData.character_slots[3] != null:
		print("Slot 4 already filled! Cannot create another character here.")
		return
	CharacterData.character_slots[3] = {"class": "Healer", "level": 1}
	CharacterData.save_data()
	update_slot_labels()

func _on_select_button_4_pressed() -> void:
	if CharacterData.character_slots[3] == null:
		print("No character in slot 4 to select!")
		return
	print("Selected Healer in slot 4")
	CharacterData.active_character_index = 3
	CharacterData.save_data()
	get_tree().change_scene_to_file("res://scenes/GameScene.tscn")
