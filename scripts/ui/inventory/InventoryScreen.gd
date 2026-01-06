extends Control
# InventoryScreen.gd (used at MenuScreen/InventoryUI/PanelContainer/InventoryScreen)

func setup_for_player(player, _slot_idx):
	_clear_grid()
	for slot in get_inventory_slots(player.inventory):
		var btn = Button.new()
		if slot is Dictionary and "name" in slot:
			btn.text = slot.name + (" x" + str(slot.count) if "count" in slot and slot.count > 1 else "")
			btn.connect("pressed", Callable(self, "_on_inventory_slot_used").bind(slot, player))
		elif slot:  # single item string (not dict)
			btn.text = str(slot)
			btn.connect("pressed", Callable(self, "_on_inventory_slot_used").bind(slot, player))
		else:  # empty slot (null/empty)
			btn.text = ""
			btn.disabled = true
		$GridContainer.add_child(btn)
	# In the future: right-click menu, drag-drop, tooltips

func _clear_grid():
	for child in $GridContainer.get_children():
		child.queue_free()

func get_inventory_slots(inventory_obj, slot_count := 20):
	var slots = []
	var arr = _extract_inventory_array(inventory_obj)
	for item in arr:
		slots.append(item)
	while slots.size() < slot_count:
		slots.append(null)
	return slots

func _extract_inventory_array(inventory_obj):
	# Returns array for any inventory layout (array/resource/object/custom)
	if typeof(inventory_obj) == TYPE_ARRAY:
		return inventory_obj
	elif typeof(inventory_obj) == TYPE_OBJECT:
		if inventory_obj.has_method("get_all_items"):
			return inventory_obj.get_all_items()
		if "items" in inventory_obj:
			return inventory_obj.items
	return []

func _on_inventory_slot_used(item, player):
	_use_item(item, player)

func _use_item(item, player):
	var item_name = ""
	var is_stack := false
	var _item_count := 1
	if typeof(item) == TYPE_DICTIONARY and "name" in item:
		item_name = item.name
		is_stack = "count" in item
		_item_count = item.count if is_stack else 1
	elif typeof(item) == TYPE_STRING:
		item_name = item
	else:
		print("Invalid item format!")
		return

	if item_name == "Test Potion":
		if player.has_method("heal"):
			player.heal(20)
			print("Test Potion used! Player healed for 20 HP.")
		_erase_from_inventory(player, item)
		update_for_player(player, CharacterData.active_character_index)
	else:
		print("%s is not usable." % str(item_name))

func _erase_from_inventory(player, item):
	var arr = _extract_inventory_array(player.inventory)
	if typeof(item) == TYPE_DICTIONARY and "count" in item and item.count > 1:
		item.count -= 1
	else:
		arr.erase(item)

func update_for_player(player, slot_idx):
	_clear_grid()
	setup_for_player(player, slot_idx)

func loot_item(player, item_name):
	var arr = _extract_inventory_array(player.inventory)
	for item in arr:
		if typeof(item) == TYPE_DICTIONARY and item.name == item_name:
			item.count += 1
			return
		elif typeof(item) == TYPE_STRING and item == item_name:
			# Convert to stackable dictionary for further loots
			var dict_item = { "name": item_name, "count": 2 }
			arr[arr.find(item)] = dict_item
			return
	arr.append({ "name": item_name, "count": 1 })
