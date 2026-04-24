extends GridContainer
class_name InventoryContainer

signal slot_clicked(slot: InventorySlot)
signal slot_right_clicked(slot: InventorySlot)
signal slot_hovered(slot: InventorySlot)
signal slot_unhovered(slot: InventorySlot)
signal inventory_changed()

@export var grid_width: int = 5
@export var grid_height: int = 4
@export var inventory_slot_scene: PackedScene = preload("res://scene/ui/inventory/inventoryslot.tscn")

var slots: Array[InventorySlot] = []

var capacity: int:
	get: return grid_width * grid_height

func _ready() -> void:
	columns = grid_width
	_create_slots()

func _create_slots() -> void:
	for child in get_children():
		child.queue_free()
	slots.clear()
	for i in range(capacity):
		var slot_instance = inventory_slot_scene.instantiate() as InventorySlot
		slot_instance.slot_index = i
		slot_instance.slot_clicked.connect(_on_slot_clicked)
		slot_instance.slot_right_clicked.connect(_on_slot_right_clicked)
		slot_instance.slot_hovered.connect(_on_slot_hovered)
		slot_instance.slot_unhovered.connect(_on_slot_unhovered)
		add_child(slot_instance)
		slots.append(slot_instance)

func resize(w: int, h: int) -> Array[Item]:
	var existing_items: Array[Item] = []
	for slot in slots:
		if not slot.is_empty():
			existing_items.append(slot.item.duplicate_item())
	grid_width = w
	grid_height = h
	columns = grid_width
	_create_slots()
	var overflow: Array[Item] = []
	for item in existing_items:
		if not add_item(item):
			overflow.append(item)
	inventory_changed.emit()
	return overflow

func add_item(item: Item) -> bool:
	if item == null:
		return false
	if item.stackable:
		for slot in slots:
			if not slot.is_empty() and slot.item.can_stack_with(item):
				var leftover = slot.item.add_to_stack(item.quantity)
				if leftover == 0:
					slot.refresh_display()
					inventory_changed.emit()
					return true
				else:
					item.quantity = leftover
					slot.refresh_display()
	for slot in slots:
		if slot.is_empty():
			slot.set_item(item.duplicate_item())
			inventory_changed.emit()
			return true
	return false

func add_item_at(index: int, item: Item) -> bool:
	if item == null:
		return false
	if index < 0 or index >= slots.size():
		return false
	var slot = slots[index]
	if slot.is_empty():
		slot.set_item(item.duplicate_item())
		inventory_changed.emit()
		return true
	if item.stackable and slot.item.can_stack_with(item):
		var leftover = slot.item.add_to_stack(item.quantity)
		slot.refresh_display()
		inventory_changed.emit()
		return leftover == 0
	return false

func remove_item_at(index: int) -> Item:
	if index < 0 or index >= slots.size():
		return null
	var slot = slots[index]
	if slot.is_empty():
		return null
	var removed_item = slot.item
	slot.clear_item()
	inventory_changed.emit()
	return removed_item

func remove_item(item: Item) -> Item:
	if item == null:
		return null
	for slot in slots:
		if not slot.is_empty() and slot.item.name == item.name and slot.item.tier == item.tier:
			var removed_item = slot.item
			slot.clear_item()
			inventory_changed.emit()
			return removed_item
	return null

func remove_quantity_at(index: int, amount: int) -> int:
	if index < 0 or index >= slots.size():
		return 0
	var slot = slots[index]
	if slot.is_empty():
		return 0
	var removed = min(amount, slot.item.quantity)
	slot.item.quantity -= removed
	if slot.item.quantity <= 0:
		slot.clear_item()
	else:
		slot.refresh_display()
	inventory_changed.emit()
	return removed

func remove_quantity(item: Item, amount: int) -> int:
	if item == null or amount <= 0:
		return 0
	var remaining = amount
	for slot in slots:
		if remaining <= 0:
			break
		if slot.is_empty():
			continue
		if slot.item.name != item.name or slot.item.tier != item.tier:
			continue
		var to_remove = min(remaining, slot.item.quantity)
		slot.item.quantity -= to_remove
		remaining -= to_remove
		if slot.item.quantity <= 0:
			slot.clear_item()
		else:
			slot.refresh_display()
	if remaining < amount:
		inventory_changed.emit()
	return amount - remaining

func get_item_at(index: int) -> Item:
	if index < 0 or index >= slots.size():
		return null
	return slots[index].item

func get_slot_at(index: int) -> InventorySlot:
	if index < 0 or index >= slots.size():
		return null
	return slots[index]

func get_all_items() -> Array[Item]:
	var items: Array[Item] = []
	for slot in slots:
		if not slot.is_empty():
			items.append(slot.item)
	return items

func has_space() -> bool:
	for slot in slots:
		if slot.is_empty():
			return true
	return false

func can_add_item(item: Item) -> bool:
	if item == null:
		return false
	if item.stackable:
		var remaining = item.quantity
		for slot in slots:
			if not slot.is_empty() and slot.item.can_stack_with(item):
				remaining -= (slot.item.max_stack - slot.item.quantity)
				if remaining <= 0:
					return true
	return has_space()

func get_item_count(item: Item) -> int:
	if item == null:
		return 0
	var count = 0
	for slot in slots:
		if not slot.is_empty() and slot.item.name == item.name and slot.item.tier == item.tier:
			count += slot.item.quantity
	return count

func find_item(item: Item) -> int:
	if item == null:
		return -1
	for i in range(slots.size()):
		if not slots[i].is_empty() and slots[i].item.name == item.name and slots[i].item.tier == item.tier:
			return i
	return -1

func clear_inventory() -> void:
	for slot in slots:
		slot.clear_item()
	inventory_changed.emit()

func load_items(item_array: Array) -> void:
	clear_inventory()
	for i in range(min(item_array.size(), slots.size())):
		if item_array[i] != null and item_array[i] is Item:
			slots[i].set_item(item_array[i])
	inventory_changed.emit()

func sort_by_name() -> void:
	var items: Array[Item] = []
	for slot in slots:
		if not slot.is_empty():
			items.append(slot.item.duplicate_item())
	items.sort_custom(func(a: Item, b: Item) -> bool:
		return a.name.to_lower() < b.name.to_lower()
	)
	for slot in slots:
		slot.clear_item()
	for i in range(items.size()):
		if i < slots.size():
			slots[i].set_item(items[i])
	inventory_changed.emit()

func _on_slot_clicked(slot: InventorySlot) -> void:
	slot_clicked.emit(slot)

func _on_slot_right_clicked(slot: InventorySlot) -> void:
	slot_right_clicked.emit(slot)

func _on_slot_hovered(slot: InventorySlot) -> void:
	slot_hovered.emit(slot)

func _on_slot_unhovered(slot: InventorySlot) -> void:
	slot_unhovered.emit(slot)
