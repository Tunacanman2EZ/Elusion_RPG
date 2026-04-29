extends Control

var elusion_scene: PackedScene = preload("res://scene/elusion.tscn")

func _ready() -> void:
	CharacterData.load_data()
	if CharacterData.character_slots == null or typeof(CharacterData.character_slots) != TYPE_ARRAY or CharacterData.character_slots.size() != 4:
		CharacterData.character_slots = [null, null, null, null]
	update_slot_labels()

func update_slot_labels() -> void:
	var labels = [%Label_1, %Label_2, %Label_3, %Label_4]
	var create_btns = [%CreateButton_1, %CreateButton_2, %CreateButton_3, %CreateButton_4]
	var select_btns = [%SelectButton_1, %SelectButton_2, %SelectButton_3, %SelectButton_4]

	for i in range(4):
		var slot = CharacterData.character_slots[i]
		var is_valid = slot != null and typeof(slot) == TYPE_DICTIONARY \
			and slot.has("character") and slot.has("level")
		if is_valid:
			labels[i].text = "%s  |  level: %d" % [slot["character"], slot["level"]]
			create_btns[i].disabled = true
			select_btns[i].disabled = false
		else:
			labels[i].text = "empty slot"
			create_btns[i].disabled = false
			select_btns[i].disabled = true

func _on_CreateButton_1_pressed() -> void:
	CharacterData.create_character(0, "warrior")
	update_slot_labels()

func _on_CreateButton_2_pressed() -> void:
	CharacterData.create_character(1, "mage")
	update_slot_labels()

func _on_CreateButton_3_pressed() -> void:
	CharacterData.create_character(2, "tank")
	update_slot_labels()

func _on_CreateButton_4_pressed() -> void:
	CharacterData.create_character(3, "healer")
	update_slot_labels()

func _on_SelectButton_1_pressed() -> void:
	_select_character(0, "warrior")

func _on_SelectButton_2_pressed() -> void:
	_select_character(1, "mage")

func _on_SelectButton_3_pressed() -> void:
	_select_character(2, "tank")

func _on_SelectButton_4_pressed() -> void:
	_select_character(3, "healer")

func _select_character(idx: int, _name: String) -> void:
	var slot = CharacterData.character_slots[idx]
	if slot == null or typeof(slot) != TYPE_DICTIONARY or not slot.has("character") or not slot.has("level"):
		print("no character in slot %d to select!" % [idx + 1])
		return
	print("selected %s in slot %d" % [_name, idx + 1])
	CharacterData.active_character_index = idx
	CharacterData.save_data()
	get_tree().change_scene_to_packed(elusion_scene)
