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
	# free() is immediate, unlike queue_free() which is deferred —
	# avoids one-frame window where old + new slots both exist
	for child in get_children():
		remove_child(child)
		child.free()

	# clear the slots array
	slots.clear()

	# create one slot instance for each cell in the grid
	for i in range(capacity):
		var slot_instance: InventorySlot = inventory_slot_scene.instantiate()
		if slot_instance == null:
			push_error("InventoryContainer: failed to instantiate inventory_slot_scene")
			return

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

func resize(w: int, h: int) -> Array[ItemStack]:
	# collect all existing stacks before resizing
	var existing_stacks: Array[ItemStack] = []
	for slot in slots:
		if not slot.is_empty():
			existing_stacks.append(slot.stack.duplicate_stack())

	# update grid dimensions
	grid_width = w
	grid_height = h
	columns = grid_width

	# recreate slots with new dimensions
	_create_slots()

	# try to re-add all existing stacks to the resized grid
	var overflow: Array[ItemStack] = []
	for stack in existing_stacks:
		if not add_stack(stack):
			overflow.append(stack)

	inventory_changed.emit()
	return overflow

# --- core inventory operations ---

func add_stack(stack: ItemStack) -> bool:
	# add an ItemStack to the inventory.
	# returns true if the entire quantity fit, false if some/all couldn't fit.
	# if stackable, tries to top up existing stacks first, then places remainder
	# in empty slots — splitting across multiple slots if needed.

	if stack == null or not stack.is_valid():
		return false

	# work on a copy so we don't mutate the caller's stack
	var working: ItemStack = stack.duplicate_stack()

	# step 1: if stackable, try to top up existing stacks of the same item
	if working.data.stackable:
		for slot in slots:
			if working.quantity <= 0:
				break  # everything fit, done
			if slot.is_empty():
				continue
			if slot.stack.can_stack_with(working):
				var leftover: int = slot.stack.add_to_stack(working.quantity)
				working.quantity = leftover
				slot.refresh_display()

	# step 2: place remainder in empty slots, splitting if needed
	# handles "adding 250 arrows when max_stack is 100" correctly:
	# fills first empty slot to 100, then next to 100, then next to 50.
	while working.quantity > 0:
		var found_empty: bool = false
		for slot in slots:
			if slot.is_empty():
				# place up to max_stack worth in this slot
				var to_place: int = min(working.quantity, working.data.max_stack)
				var new_stack: ItemStack = working.duplicate_stack()
				new_stack.quantity = to_place
				slot.set_stack(new_stack)
				working.quantity -= to_place
				found_empty = true
				break
		if not found_empty:
			break  # no more empty slots — inventory is full

	inventory_changed.emit()
	# true if the entire quantity fit, false if there's leftover
	return working.quantity == 0

func add_stack_at(index: int, stack: ItemStack) -> bool:
	# place a stack at a specific slot index.
	# returns true if it fit (or stacked), false otherwise.

	if stack == null or not stack.is_valid():
		return false
	if index < 0 or index >= slots.size():
		return false

	var slot: InventorySlot = slots[index]

	# if slot is empty, place the stack directly (clamped to max_stack)
	if slot.is_empty():
		var to_place: int = min(stack.quantity, stack.data.max_stack)
		var new_stack: ItemStack = stack.duplicate_stack()
		new_stack.quantity = to_place
		slot.set_stack(new_stack)
		inventory_changed.emit()
		# if the original quantity exceeded max_stack, return false to
		# signal the caller has overflow they need to handle
		return to_place == stack.quantity

	# if slot is occupied with a compatible stack, try to merge
	if slot.stack.can_stack_with(stack):
		var leftover: int = slot.stack.add_to_stack(stack.quantity)
		slot.refresh_display()
		inventory_changed.emit()
		# true only if all quantity fit
		return leftover == 0

	# slot is occupied with an incompatible stack
	return false

func remove_stack_at(index: int) -> ItemStack:
	# remove and return the entire stack at a given slot index.
	# returns null if slot is empty or index is invalid.

	if index < 0 or index >= slots.size():
		return null

	var slot: InventorySlot = slots[index]
	if slot.is_empty():
		return null

	var removed: ItemStack = slot.stack
	slot.clear_stack()
	inventory_changed.emit()
	return removed

func remove_quantity_at(index: int, amount: int) -> int:
	# remove a specific quantity from the stack at a slot index.
	# clears the slot if quantity drops to zero.
	# returns how much was actually removed.

	if index < 0 or index >= slots.size() or amount <= 0:
		return 0

	var slot: InventorySlot = slots[index]
	if slot.is_empty():
		return 0

	var removed: int = slot.stack.remove_quantity(amount)

	if slot.stack.quantity <= 0:
		slot.clear_stack()
	else:
		slot.refresh_display()

	if removed > 0:
		inventory_changed.emit()
	return removed

func remove_quantity_by_id(item_id: String, amount: int) -> int:
	# remove a quantity of an item across all slots that contain it.
	# useful for "consume 5 arrows" — pulls from any slot containing arrows.
	# returns how much was actually removed (may be less than requested).

	if item_id == "" or amount <= 0:
		return 0

	var remaining: int = amount
	var any_removed: bool = false

	for slot in slots:
		if remaining <= 0:
			break
		if slot.is_empty():
			continue
		if slot.stack.data.item_id != item_id:
			continue

		var to_remove: int = min(remaining, slot.stack.quantity)
		slot.stack.remove_quantity(to_remove)
		remaining -= to_remove
		any_removed = true

		if slot.stack.quantity <= 0:
			slot.clear_stack()
		else:
			slot.refresh_display()

	if any_removed:
		inventory_changed.emit()
	return amount - remaining

# --- queries ---

func get_stack_at(index: int) -> ItemStack:
	# returns the ItemStack at a slot index, or null if empty/invalid
	if index < 0 or index >= slots.size():
		return null
	return slots[index].stack

func get_slot_at(index: int) -> InventorySlot:
	# returns the slot node at a given index
	if index < 0 or index >= slots.size():
		return null
	return slots[index]

func get_all_stacks() -> Array[ItemStack]:
	# collect and return all non-empty stacks in the inventory
	var result: Array[ItemStack] = []
	for slot in slots:
		if not slot.is_empty():
			result.append(slot.stack)
	return result

func has_space() -> bool:
	# returns true if any slot is empty
	for slot in slots:
		if slot.is_empty():
			return true
	return false

func can_add_stack(stack: ItemStack) -> bool:
	# returns true if the given stack can fit in the inventory,
	# accounting for both empty slots and existing stack space.

	if stack == null or not stack.is_valid():
		return false

	# count available space across existing matching stacks
	if stack.data.stackable:
		var remaining: int = stack.quantity
		for slot in slots:
			if not slot.is_empty() and slot.stack.can_stack_with(stack):
				remaining -= (slot.stack.data.max_stack - slot.stack.quantity)
				if remaining <= 0:
					return true

		# also account for empty slots — each can hold one full stack
		for slot in slots:
			if slot.is_empty():
				remaining -= stack.data.max_stack
				if remaining <= 0:
					return true
		return false

	# non-stackable: just need an empty slot
	return has_space()

func get_quantity_of(item_id: String) -> int:
	# count total quantity of an item across all slots
	if item_id == "":
		return 0

	var total: int = 0
	for slot in slots:
		if not slot.is_empty() and slot.stack.data.item_id == item_id:
			total += slot.stack.quantity
	return total

func find_first_index_of(item_id: String) -> int:
	# return the slot index of the first stack matching item_id, or -1
	if item_id == "":
		return -1

	for i in range(slots.size()):
		if not slots[i].is_empty() and slots[i].stack.data.item_id == item_id:
			return i
	return -1

func clear_inventory() -> void:
	# clear all slots in the inventory
	for slot in slots:
		slot.clear_stack()
	inventory_changed.emit()

# --- save / load helpers ---
# these methods serialize the inventory contents for the save system.
# only item_id and quantity are saved per slot — the data is hydrated
# from ItemRegistry on load. this is what makes saves small and MMO-ready.

func to_save_array() -> Array:
	# serialize the inventory to an array of dictionaries.
	# null entries represent empty slots.
	# preserves slot order so layout is restored on load.
	var result: Array = []
	for slot in slots:
		if slot.is_empty():
			result.append(null)
		else:
			result.append(slot.stack.to_dict())
	return result

func load_save_array(save_array: Array) -> void:
	# restore inventory from a saved array. clears existing contents first.
	# unknown item_ids are skipped (with a registry warning) — slot stays empty.

	clear_inventory()

	for i in range(min(save_array.size(), slots.size())):
		var entry = save_array[i]
		if entry == null or typeof(entry) != TYPE_DICTIONARY:
			continue

		var stack: ItemStack = ItemStack.from_dict(entry)
		if stack == null:
			continue

		# clamp quantity to max_stack on load — protects against legacy
		# save files where stacks exceeded their data's current max_stack
		if stack.data.stackable and stack.quantity > stack.data.max_stack:
			push_warning("InventoryContainer: clamped %s quantity %d -> %d on load" % [
				stack.data.item_id, stack.quantity, stack.data.max_stack
			])
			stack.quantity = stack.data.max_stack

		slots[i].set_stack(stack)

	inventory_changed.emit()

func sort_by_name() -> void:
	# sort all stacks alphabetically by display_name, consolidating
	# matching stackable items into single stacks where possible.

	# collect all current stacks
	var stacks: Array[ItemStack] = []
	for slot in slots:
		if not slot.is_empty():
			stacks.append(slot.stack.duplicate_stack())

	# clear all slots
	for slot in slots:
		slot.clear_stack()

	# sort by display name (case-insensitive)
	stacks.sort_custom(func(a: ItemStack, b: ItemStack) -> bool:
		return a.data.display_name.to_lower() < b.data.display_name.to_lower()
	)

	# re-add — add_stack handles consolidation of stackables automatically
	for stack in stacks:
		add_stack(stack)

# --- signal relay functions ---
# forward slot signals up to the parent UI (the InventoryScreen)

func _on_slot_clicked(slot: InventorySlot) -> void:
	slot_clicked.emit(slot)

func _on_slot_right_clicked(slot: InventorySlot) -> void:
	slot_right_clicked.emit(slot)

func _on_slot_hovered(slot: InventorySlot) -> void:
	slot_hovered.emit(slot)

func _on_slot_unhovered(slot: InventorySlot) -> void:
	slot_unhovered.emit(slot)
