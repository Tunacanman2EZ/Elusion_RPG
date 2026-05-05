# inventory grid container — manages a grid of inventory slots
# inherited by any UI that needs a grid-based inventory display
extends GridContainer
class_name InventoryContainer

# --- signals ---
# emitted when a slot is left clicked — passes the slot reference
signal slot_clicked(slot: InventorySlot)

# emitted when a slot is right clicked — passes the slot reference
signal slot_right_clicked(slot: InventorySlot)

# emitted when the mouse enters a slot — used for tooltip display
signal slot_hovered(slot: InventorySlot)

# emitted when the mouse leaves a slot — used to hide tooltip
signal slot_unhovered(slot: InventorySlot)

# emitted whenever the inventory contents change — used to sync with save system
signal inventory_changed()

# --- exported settings ---
# number of columns in the inventory grid
@export var grid_width: int = 5

# number of rows in the inventory grid
@export var grid_height: int = 4

# the inventory slot scene to instantiate for each grid cell
@export var inventory_slot_scene: PackedScene = preload("res://scene/ui/inventory/inventoryslot.tscn")

# --- state ---
# array of all slot instances in this inventory
var slots: Array[InventorySlot] = []

# calculated total capacity based on grid dimensions — read only
var capacity: int:
	get: return grid_width * grid_height

func _ready() -> void:
	# set the GridContainer column count to match grid width
	columns = grid_width

	# create all slot instances and add them to the grid
	_create_slots()

func _create_slots() -> void:
	# remove any existing slot children before recreating
	for child in get_children():
		child.queue_free()

	# clear the slots array
	slots.clear()

	# create one slot instance for each cell in the grid
	for i in range(capacity):
		# instantiate the slot scene
		var slot_instance = inventory_slot_scene.instantiate() as InventorySlot

		# assign the slot its index position in the grid
		slot_instance.slot_index = i

		# connect slot signals to this container's handler functions
		slot_instance.slot_clicked.connect(_on_slot_clicked)
		slot_instance.slot_right_clicked.connect(_on_slot_right_clicked)
		slot_instance.slot_hovered.connect(_on_slot_hovered)
		slot_instance.slot_unhovered.connect(_on_slot_unhovered)

		# add the slot to the scene tree
		add_child(slot_instance)

		# add to our tracking array
		slots.append(slot_instance)

func resize(w: int, h: int) -> Array[Item]:
	# collect all existing items before resizing
	var existing_items: Array[Item] = []
	for slot in slots:
		if not slot.is_empty():
			existing_items.append(slot.item.duplicate_item())

	# update grid dimensions
	grid_width = w
	grid_height = h
	columns = grid_width

	# recreate slots with new dimensions
	_create_slots()

	# try to re-add all existing items to the resized grid
	var overflow: Array[Item] = []
	for item in existing_items:
		if not add_item(item):
			# item didn't fit — add to overflow list
			overflow.append(item)

	# notify listeners that inventory changed
	inventory_changed.emit()

	# return any items that didn't fit after resize
	return overflow

func add_item(item: Item) -> bool:
	# do nothing if item is null
	if item == null:
		return false

	# if item is stackable try to add to an existing stack first
	if item.stackable:
		for slot in slots:
			if not slot.is_empty() and slot.item.can_stack_with(item):
				# try to add quantity to this stack
				var leftover = slot.item.add_to_stack(item.quantity)
				if leftover == 0:
					# entire quantity fit into existing stack
					slot.refresh_display()
					inventory_changed.emit()
					return true
				else:
					# partial stack — update remaining quantity and continue
					item.quantity = leftover
					slot.refresh_display()

	# find the first empty slot and place the item there
	for slot in slots:
		if slot.is_empty():
			slot.set_item(item.duplicate_item())
			inventory_changed.emit()
			return true

	# no empty slot found — inventory is full
	return false

func add_item_at(index: int, item: Item) -> bool:
	# do nothing if item is null
	if item == null:
		return false

	# validate index is within bounds
	if index < 0 or index >= slots.size():
		return false

	var slot = slots[index]

	# if slot is empty place item directly
	if slot.is_empty():
		slot.set_item(item.duplicate_item())
		inventory_changed.emit()
		return true

	# if stackable and compatible try to stack
	if item.stackable and slot.item.can_stack_with(item):
		var leftover = slot.item.add_to_stack(item.quantity)
		slot.refresh_display()
		inventory_changed.emit()
		# return true only if all quantity fit
		return leftover == 0

	# slot is occupied and not stackable
	return false

func remove_item_at(index: int) -> Item:
	# validate index is within bounds
	if index < 0 or index >= slots.size():
		return null

	var slot = slots[index]

	# return null if slot is already empty
	if slot.is_empty():
		return null

	# store reference to item before clearing
	var removed_item = slot.item

	# clear the slot
	slot.clear_item()
	inventory_changed.emit()

	# return the removed item
	return removed_item

func remove_item(item: Item) -> Item:
	# do nothing if item is null
	if item == null:
		return null

	# search for the first slot containing a matching item
	for slot in slots:
		if not slot.is_empty() and slot.item.name == item.name and slot.item.tier == item.tier:
			var removed_item = slot.item
			slot.clear_item()
			inventory_changed.emit()
			return removed_item

	# item not found
	return null

func remove_quantity_at(index: int, amount: int) -> int:
	# validate index is within bounds
	if index < 0 or index >= slots.size():
		return 0

	var slot = slots[index]

	# return 0 if slot is empty
	if slot.is_empty():
		return 0

	# calculate how much we can actually remove
	var removed = min(amount, slot.item.quantity)

	# reduce the stack quantity
	slot.item.quantity -= removed

	# clear slot if quantity dropped to zero
	if slot.item.quantity <= 0:
		slot.clear_item()
	else:
		slot.refresh_display()

	inventory_changed.emit()

	# return how much was actually removed
	return removed

func remove_quantity(item: Item, amount: int) -> int:
	# do nothing if item is null or amount is invalid
	if item == null or amount <= 0:
		return 0

	var remaining = amount

	# search all slots for matching items and remove quantity
	for slot in slots:
		# stop if we have removed enough
		if remaining <= 0:
			break

		# skip empty slots
		if slot.is_empty():
			continue

		# skip slots with different items
		if slot.item.name != item.name or slot.item.tier != item.tier:
			continue

		# remove as much as possible from this slot
		var to_remove = min(remaining, slot.item.quantity)
		slot.item.quantity -= to_remove
		remaining -= to_remove

		# clear slot if empty or refresh display
		if slot.item.quantity <= 0:
			slot.clear_item()
		else:
			slot.refresh_display()

	# emit changed if anything was removed
	if remaining < amount:
		inventory_changed.emit()

	# return how much was actually removed
	return amount - remaining

func get_item_at(index: int) -> Item:
	# validate index is within bounds
	if index < 0 or index >= slots.size():
		return null

	# return the item in the slot — may be null if empty
	return slots[index].item

func get_slot_at(index: int) -> InventorySlot:
	# validate index is within bounds
	if index < 0 or index >= slots.size():
		return null

	# return the slot node at this index
	return slots[index]

func get_all_items() -> Array[Item]:
	# collect and return all non-empty items in the inventory
	var items: Array[Item] = []
	for slot in slots:
		if not slot.is_empty():
			items.append(slot.item)
	return items

func has_space() -> bool:
	# return true if any slot is empty
	for slot in slots:
		if slot.is_empty():
			return true
	return false

func can_add_item(item: Item) -> bool:
	# do nothing if item is null
	if item == null:
		return false

	# check if stackable item can fit into existing stacks
	if item.stackable:
		var remaining = item.quantity
		for slot in slots:
			if not slot.is_empty() and slot.item.can_stack_with(item):
				# calculate available stack space
				remaining -= (slot.item.max_stack - slot.item.quantity)
				if remaining <= 0:
					return true

	# fall back to checking for any empty slot
	return has_space()

func get_item_count(item: Item) -> int:
	# do nothing if item is null
	if item == null:
		return 0

	# count total quantity of matching items across all slots
	var count = 0
	for slot in slots:
		if not slot.is_empty() and slot.item.name == item.name and slot.item.tier == item.tier:
			count += slot.item.quantity
	return count

func find_item(item: Item) -> int:
	# do nothing if item is null
	if item == null:
		return -1

	# return the index of the first slot containing a matching item
	for i in range(slots.size()):
		if not slots[i].is_empty() and slots[i].item.name == item.name and slots[i].item.tier == item.tier:
			return i

	# item not found — return -1
	return -1

func clear_inventory() -> void:
	# clear all slots in the inventory
	for slot in slots:
		slot.clear_item()
	inventory_changed.emit()

func load_items(item_array: Array) -> void:
	# clear existing inventory before loading
	clear_inventory()

	# load items from array into slots — stops at capacity or array end
	for i in range(min(item_array.size(), slots.size())):
		if item_array[i] != null and item_array[i] is Item:
			slots[i].set_item(item_array[i])

	inventory_changed.emit()

func sort_by_name() -> void:
	# collect all existing items
	var items: Array[Item] = []
	for slot in slots:
		if not slot.is_empty():
			items.append(slot.item.duplicate_item())

	# sort items alphabetically by name — case insensitive
	items.sort_custom(func(a: Item, b: Item) -> bool:
		return a.name.to_lower() < b.name.to_lower()
	)

	# clear all slots
	for slot in slots:
		slot.clear_item()

	# re-populate slots with sorted items
	for i in range(items.size()):
		if i < slots.size():
			slots[i].set_item(items[i])

	inventory_changed.emit()

# --- signal relay functions ---
# these forward slot signals up to the parent UI

func _on_slot_clicked(slot: InventorySlot) -> void:
	# relay slot clicked signal to parent
	slot_clicked.emit(slot)

func _on_slot_right_clicked(slot: InventorySlot) -> void:
	# relay slot right clicked signal to parent
	slot_right_clicked.emit(slot)

func _on_slot_hovered(slot: InventorySlot) -> void:
	# relay slot hovered signal to parent
	slot_hovered.emit(slot)

func _on_slot_unhovered(slot: InventorySlot) -> void:
	# relay slot unhovered signal to parent
	slot_unhovered.emit(slot)
