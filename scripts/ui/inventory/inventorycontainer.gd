## A grid-based inventory container that manages InventorySlot nodes.[br]
## Handles item storage, stacking, and provides signals for UI interactions.
extends GridContainer
class_name InventoryContainer

## Emitted when a slot is clicked
signal slot_clicked(slot: InventorySlot)
## Emitted when a slot is right-clicked
signal slot_right_clicked(slot: InventorySlot)
## Emitted when hovering a slot (for tooltips)
signal slot_hovered(slot: InventorySlot)
## Emitted when no longer hovering a slot
signal slot_unhovered(slot: InventorySlot)
## Emitted when inventory contents change
signal inventory_changed()

## The container's number of columns
@export var grid_width: int = 5
## The container's number of rows
@export var grid_height: int = 4

@export_category("Scene Connections")
## The scene to instantiate for each inventory slot
@export var inventory_slot_scene: PackedScene = preload("res://scripts/ui/inventory/inventoryslot.gd")

## Array of InventorySlot nodes in this container
var slots: Array[InventorySlot] = []

## Total capacity of the inventory (grid_width * grid_height)
var capacity: int:
	get: return grid_width * grid_height


func _ready() -> void:
	columns = grid_width
	_create_slots()


## Creates the inventory slot grid based on grid_width and grid_height.[br]
## Clears any existing slots before creating new ones.
func _create_slots() -> void:
	# Clear existing slots
	for child in get_children():
		child.queue_free()
	slots.clear()
	
	# Create new slots
	for i in range(capacity):
		var slot_instance = inventory_slot_scene.instantiate() as InventorySlot
		slot_instance.slot_index = i
		slot_instance.slot_clicked.connect(_on_slot_clicked)
		slot_instance.slot_right_clicked.connect(_on_slot_right_clicked)
		slot_instance.slot_hovered.connect(_on_slot_hovered)
		slot_instance.slot_unhovered.connect(_on_slot_unhovered)
		add_child(slot_instance)
		slots.append(slot_instance)


## Resizes the inventory grid to new dimensions.[br]
## When shrinking, items are compacted into available slots.[br]
## Returns an array of overflow items that could not fit (empty if all items fit).
func resize(w: int, h: int) -> Array[Item]:
	# Collect all existing items (non-null only)
	var existing_items: Array[Item] = []
	for slot in slots:
		if not slot.is_empty():
			existing_items.append(slot.item.duplicate_item())
	
	# Resize the grid
	grid_width = w
	grid_height = h
	columns = grid_width
	_create_slots()
	
	# Re-add items to the new slots (compacting them)
	var overflow: Array[Item] = []
	for item in existing_items:
		if not add_item(item):
			overflow.append(item)
	
	inventory_changed.emit()
	return overflow

#region Add Item Methods

## Adds an item to the first available slot (handles stacking).[br]
## Returns true if the item was successfully added.
func add_item(item: Item) -> bool:
	if item == null:
		return false
	
	# If stackable, try to find existing stack first
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
	
	# Find first empty slot
	for slot in slots:
		if slot.is_empty():
			slot.set_item(item.duplicate_item())
			inventory_changed.emit()
			return true
	
	# No room
	return false


## Adds an item to a specific slot index.[br]
## Returns true if successful, false if slot is occupied or index is invalid.
func add_item_at(index: int, item: Item) -> bool:
	if item == null:
		return false
	if index < 0 or index >= slots.size():
		return false
	
	var slot = slots[index]
	
	# If slot is empty, place item directly
	if slot.is_empty():
		slot.set_item(item.duplicate_item())
		inventory_changed.emit()
		return true
	
	# If slot has stackable item, try to stack
	if item.stackable and slot.item.can_stack_with(item):
		var leftover = slot.item.add_to_stack(item.quantity)
		slot.refresh_display()
		inventory_changed.emit()
		return leftover == 0
	
	# Slot is occupied with non-stackable item
	return false

#endregion


#region Remove Item Methods

## Removes an item at the specified slot index.[br]
## Returns the removed item or null if slot was empty/invalid.
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


## Removes the first occurrence of an item matching the given item.[br]
## Matches by item name and tier. Returns the removed item or null if not found.
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


## Removes a specific quantity from a slot at the given index.[br]
## Returns the actual amount removed (may be less if stack was smaller).
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


## Removes a specific quantity of an item matching the given item.[br]
## Searches all slots and removes from stacks until amount is fulfilled.[br]
## Returns the actual amount removed.
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

#endregion


#region Query Methods

## Gets the item at a specific slot index.[br]
## Returns null if index is invalid or slot is empty.
func get_item_at(index: int) -> Item:
	if index < 0 or index >= slots.size():
		return null
	return slots[index].item


## Gets the slot at a specific index.[br]
## Returns null if index is invalid.
func get_slot_at(index: int) -> InventorySlot:
	if index < 0 or index >= slots.size():
		return null
	return slots[index]


## Returns an array of all non-null items in the inventory.
func get_all_items() -> Array[Item]:
	var items: Array[Item] = []
	for slot in slots:
		if not slot.is_empty():
			items.append(slot.item)
	return items


## Returns true if at least one slot is empty.
func has_space() -> bool:
	for slot in slots:
		if slot.is_empty():
			return true
	return false


## Returns true if the inventory can accept the specified item.[br]
## Considers both empty slots and stacking potential.
func can_add_item(item: Item) -> bool:
	if item == null:
		return false
	
	# Check for stackable items with existing stacks
	if item.stackable:
		var remaining = item.quantity
		for slot in slots:
			if not slot.is_empty() and slot.item.can_stack_with(item):
				remaining -= (slot.item.max_stack - slot.item.quantity)
				if remaining <= 0:
					return true
	
	# Check for empty slot
	return has_space()


## Returns the total quantity of a specific item in the inventory.[br]
## Matches by item name and tier.
func get_item_count(item: Item) -> int:
	if item == null:
		return 0
	
	var count = 0
	for slot in slots:
		if not slot.is_empty() and slot.item.name == item.name and slot.item.tier == item.tier:
			count += slot.item.quantity
	return count


## Finds the first slot index containing the specified item.[br]
## Returns -1 if not found.
func find_item(item: Item) -> int:
	if item == null:
		return -1
	
	for i in range(slots.size()):
		if not slots[i].is_empty() and slots[i].item.name == item.name and slots[i].item.tier == item.tier:
			return i
	return -1

#endregion


#region Bulk Operations

## Clears all items from the inventory.
func clear_inventory() -> void:
	for slot in slots:
		slot.clear_item()
	inventory_changed.emit()


## Populates inventory from an array of items.[br]
## Used for loading saved inventory data.
func load_items(item_array: Array) -> void:
	clear_inventory()
	for i in range(min(item_array.size(), slots.size())):
		if item_array[i] != null and item_array[i] is Item:
			slots[i].set_item(item_array[i])
	inventory_changed.emit()


## Sorts all items alphabetically by name and compacts them to the beginning of the inventory.
func sort_by_name() -> void:
	# Collect all items
	var items: Array[Item] = []
	for slot in slots:
		if not slot.is_empty():
			items.append(slot.item.duplicate_item())
	
	# Sort alphabetically by name (case-insensitive)
	items.sort_custom(func(a: Item, b: Item) -> bool:
		return a.name.to_lower() < b.name.to_lower()
	)
	
	# Clear all slots
	for slot in slots:
		slot.clear_item()
	
	# Place sorted items at the beginning
	for i in range(items.size()):
		if i < slots.size():
			slots[i].set_item(items[i])
	
	inventory_changed.emit()

#endregion


#region Signal Handlers

## Forwards slot_clicked signal from child slots.
func _on_slot_clicked(slot: InventorySlot) -> void:
	slot_clicked.emit(slot)


## Forwards slot_right_clicked signal from child slots.
func _on_slot_right_clicked(slot: InventorySlot) -> void:
	slot_right_clicked.emit(slot)


## Forwards slot_hovered signal from child slots.
func _on_slot_hovered(slot: InventorySlot) -> void:
	slot_hovered.emit(slot)


## Forwards slot_unhovered signal from child slots.
func _on_slot_unhovered(slot: InventorySlot) -> void:
	slot_unhovered.emit(slot)

#endregion
