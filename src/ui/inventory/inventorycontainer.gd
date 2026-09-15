# inventory grid container — manages a grid of inventory slots.
# inherited by any UI that needs a grid-based inventory display (player
# inventory, bank, loot bag, future shop UI, etc.).
#
# architecture:
# - one InventorySlot scene per grid cell, instanced in _ready
# - slot signals (click, right-click, double-click, hover) relay up to
#   whoever owns this container
# - save format is item_id + quantity per slot — small + MMO-ready
# - add_stack handles stackable consolidation + max_stack overflow splitting
# - linked_item_ids tracks which items are referenced by hotbar slots so
#   matching inventory items can be tinted gold to show the connection
#
# common usage flow:
# 1. parent scene places InventoryContainer in its tree
# 2. _ready instantiates slots based on grid_width × grid_height
# 3. parent calls add_stack / remove_quantity_at as items move
# 4. inventory_changed signal fires on every mutation for save sync
# 5. hotbar calls set_linked_item_ids to keep inventory tinting in sync
extends GridContainer
class_name InventoryContainer


# =============================================================================
# SIGNALS
# =============================================================================

# emitted when a slot is left clicked — passes the slot reference
signal slot_clicked(slot: InventorySlot)

# emitted when a slot is right clicked — passes the slot reference
signal slot_right_clicked(slot: InventorySlot)

# emitted when a slot is double-clicked (LMB double-click) — used for
# quick-transfer flows like "double-click loot to send to inventory"
signal slot_double_clicked(slot: InventorySlot)

# emitted when the mouse enters a slot — used for tooltip display
signal slot_hovered(slot: InventorySlot)

# emitted when the mouse leaves a slot — used to hide tooltip
signal slot_unhovered(slot: InventorySlot)

# emitted whenever the inventory contents change — used to sync with save system
signal inventory_changed()

# relayed from a slot that refused to perform a drop itself because the drag
# crossed between the bank and the backpack. bankinventory.gd answers it with a
# single POST /api/bank/items. See InventorySlot._drop_data(), CASE T.
signal transfer_requested(source_slot: InventorySlot, target_slot: InventorySlot)


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

@export var grid_width:  int = 5
@export var grid_height: int = 4

@export var inventory_slot_scene: PackedScene = preload("res://scene/ui/inventory/inventoryslot.tscn")


# =============================================================================
# STATE
# =============================================================================

var slots: Array[InventorySlot] = []

var capacity: int:
	get: return grid_width * grid_height


# =============================================================================
# LINKED ITEM TRACKING
# =============================================================================

var linked_item_ids: Dictionary = {}


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	columns = grid_width
	_create_slots()


# =============================================================================
# SLOT CREATION AND RESIZING
# =============================================================================

func _create_slots() -> void:
	for child in get_children():
		remove_child(child)
		child.free()

	slots.clear()

	for i in range(capacity):
		var slot_instance: InventorySlot = inventory_slot_scene.instantiate()
		if slot_instance == null:
			push_error("InventoryContainer: failed to instantiate inventory_slot_scene")
			return

		slot_instance.slot_index = i

		# connect each slot's signals to this container's relay handlers.
		#
		# slot_changed was missing from this list, and it is the one that
		# matters for persistence. InventorySlot._drop_data() announces every
		# drag-and-drop by emitting slot_changed on both the source and target
		# slot and nothing else — it never touches the container. with no
		# listener, that announcement went nowhere, so a drag was the one kind
		# of inventory change in the game that never reached a save.
		#
		# see _on_slot_changed() below for what that cost.
		slot_instance.slot_clicked.connect(_on_slot_clicked)
		slot_instance.slot_right_clicked.connect(_on_slot_right_clicked)
		slot_instance.slot_double_clicked.connect(_on_slot_double_clicked)
		slot_instance.transfer_requested.connect(_on_slot_transfer_requested)
		slot_instance.slot_hovered.connect(_on_slot_hovered)
		slot_instance.slot_unhovered.connect(_on_slot_unhovered)
		slot_instance.slot_changed.connect(_on_slot_changed)

		add_child(slot_instance)
		slots.append(slot_instance)


func resize(w: int, h: int) -> Array[ItemStack]:
	var existing_stacks: Array[ItemStack] = []
	for slot in slots:
		if not slot.is_empty():
			existing_stacks.append(slot.stack.duplicate_stack())

	grid_width = w
	grid_height = h
	columns = grid_width
	_create_slots()

	var overflow: Array[ItemStack] = []
	for stack in existing_stacks:
		if not add_stack(stack):
			overflow.append(stack)

	inventory_changed.emit()
	return overflow


# =============================================================================
# CORE INVENTORY OPERATIONS — ADD
# =============================================================================

func add_stack(stack: ItemStack) -> bool:
	if stack == null or not stack.is_valid():
		return false

	var working: ItemStack = stack.duplicate_stack()

	if working.data.stackable:
		for slot in slots:
			if working.quantity <= 0:
				break
			if slot.is_empty():
				continue
			if slot.stack.can_stack_with(working):
				var leftover: int = slot.stack.add_to_stack(working.quantity)
				working.quantity = leftover
				slot.refresh_display()

	while working.quantity > 0:
		var found_empty: bool = false
		for slot in slots:
			if slot.is_empty():
				var to_place: int = min(working.quantity, working.data.max_stack)
				var new_stack: ItemStack = working.duplicate_stack()
				new_stack.quantity = to_place
				slot.set_stack(new_stack)
				working.quantity -= to_place
				found_empty = true
				break
		if not found_empty:
			break

	inventory_changed.emit()
	return working.quantity == 0


func add_stack_partial(stack: ItemStack) -> int:
	# add as much of `stack` as fits, return how many units DID NOT fit.
	# same logic as add_stack, but returns the leftover count so callers can
	# put the remainder back where it came from (loot bag partial-take flow).
	if stack == null or not stack.is_valid():
		return 0

	var working: ItemStack = stack.duplicate_stack()

	if working.data.stackable:
		for slot in slots:
			if working.quantity <= 0:
				break
			if slot.is_empty():
				continue
			if slot.stack.can_stack_with(working):
				var leftover: int = slot.stack.add_to_stack(working.quantity)
				working.quantity = leftover
				slot.refresh_display()

	while working.quantity > 0:
		var found_empty: bool = false
		for slot in slots:
			if slot.is_empty():
				var to_place: int = min(working.quantity, working.data.max_stack)
				var new_stack: ItemStack = working.duplicate_stack()
				new_stack.quantity = to_place
				slot.set_stack(new_stack)
				working.quantity -= to_place
				found_empty = true
				break
		if not found_empty:
			break

	inventory_changed.emit()
	return working.quantity


func add_stack_at(index: int, stack: ItemStack) -> bool:
	if stack == null or not stack.is_valid():
		return false
	if index < 0 or index >= slots.size():
		return false

	var slot: InventorySlot = slots[index]

	if slot.is_empty():
		var to_place: int = min(stack.quantity, stack.data.max_stack)
		var new_stack: ItemStack = stack.duplicate_stack()
		new_stack.quantity = to_place
		slot.set_stack(new_stack)
		inventory_changed.emit()
		return to_place == stack.quantity

	if slot.stack.can_stack_with(stack):
		var leftover: int = slot.stack.add_to_stack(stack.quantity)
		slot.refresh_display()
		inventory_changed.emit()
		return leftover == 0

	return false


# =============================================================================
# CORE INVENTORY OPERATIONS — REMOVE
# =============================================================================

func remove_stack_at(index: int) -> ItemStack:
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


func clear_inventory() -> void:
	for slot in slots:
		slot.clear_stack()
	inventory_changed.emit()


func set_slot_type(type_name: String) -> void:
	# Stamps every slot in this grid with a context name. Only "lootbag" changes
	# behaviour: InventorySlot refuses to start a drag from one or accept a drop
	# onto one, because a loot bag belongs to the server and a drag is not a
	# request. See lootbaginventory.gd's header.
	#
	# Applied here rather than in the scene because the slots are instantiated
	# by _create_slots() at runtime, so there is nothing in the .tscn to set.
	for slot in slots:
		slot.slot_type = type_name


# =============================================================================
# QUERIES
# =============================================================================

func get_stack_at(index: int) -> ItemStack:
	if index < 0 or index >= slots.size():
		return null
	return slots[index].stack


func get_slot_at(index: int) -> InventorySlot:
	if index < 0 or index >= slots.size():
		return null
	return slots[index]


func get_all_stacks() -> Array[ItemStack]:
	var result: Array[ItemStack] = []
	for slot in slots:
		if not slot.is_empty():
			result.append(slot.stack)
	return result


func has_space() -> bool:
	for slot in slots:
		if slot.is_empty():
			return true
	return false


func can_add_stack(stack: ItemStack) -> bool:
	if stack == null or not stack.is_valid():
		return false

	if stack.data.stackable:
		var remaining: int = stack.quantity
		for slot in slots:
			if not slot.is_empty() and slot.stack.can_stack_with(stack):
				remaining -= (slot.stack.data.max_stack - slot.stack.quantity)
				if remaining <= 0:
					return true

		for slot in slots:
			if slot.is_empty():
				remaining -= stack.data.max_stack
				if remaining <= 0:
					return true
		return false

	return has_space()


func get_quantity_of(item_id: String) -> int:
	if item_id == "":
		return 0

	var total: int = 0
	for slot in slots:
		if not slot.is_empty() and slot.stack.data.item_id == item_id:
			total += slot.stack.quantity
	return total


func find_first_index_of(item_id: String) -> int:
	if item_id == "":
		return -1

	for i in range(slots.size()):
		if not slots[i].is_empty() and slots[i].stack.data.item_id == item_id:
			return i
	return -1


# =============================================================================
# LINKED ITEM TINTING
# =============================================================================

func set_linked_item_ids(item_ids: Array) -> void:
	linked_item_ids.clear()
	for item_id in item_ids:
		var s: String = str(item_id)
		if s != "":
			linked_item_ids[s] = true

	_refresh_all_slot_styles()


func is_item_linked(item_id: String) -> bool:
	return linked_item_ids.has(item_id)


func _refresh_all_slot_styles() -> void:
	for slot in slots:
		if slot != null:
			slot.refresh_display()


# =============================================================================
# SAVE / LOAD
# =============================================================================

func to_save_array() -> Array:
	var result: Array = []
	for slot in slots:
		if slot.is_empty():
			result.append(null)
		else:
			result.append(slot.stack.to_dict())
	return result


func load_server_array(cells: Array) -> void:
	# THE SERVER'S LAYOUT, APPLIED AS-IS.
	#
	# Endpoints that change the backpack - /api/loot/take, /api/staff/grant -
	# return the WHOLE array, built the way this container would build it: an
	# existing stack topped up before a new cell is opened. Applying that rather
	# than calling add_stack() locally is what stops the two laying the same
	# pickup out differently, which is what happened the first time a potion
	# landed on a part-used stack.
	#
	# The coercion is the reason this is a method rather than a line at each call
	# site. JSON HAS NO INTEGER TYPE, so every quantity arrives as a float, and
	# ItemStack.from_dict() building a stack of 5.0 is not a stack of 5. There
	# were two places doing this the moment /api/staff/grant existed; now there
	# is one.
	#
	# AN EMPTY ARRAY IS NOT AN EMPTY BACKPACK, and applying one would be data
	# loss. inventory_payload() always returns CARRY_CAPACITY cells with null in
	# the gaps, so a genuinely empty bag arrives as [null, null, ...] of length 20.
	# A ZERO-LENGTH array means the key was missing - a malformed reply, a 500
	# body, a renamed field - and load_save_array() opens with clear_inventory().
	# Doing nothing is the only safe reading of "the server told me nothing".
	if cells.is_empty():
		push_warning("InventoryContainer: server sent no inventory array - leaving the bag alone")
		return

	var cleaned: Array = []
	cleaned.resize(cells.size())
	for i in range(cells.size()):
		var cell = cells[i]
		if not (cell is Dictionary):
			continue
		var item_id: String = str(cell.get("item_id", ""))
		if item_id == "":
			continue
		cleaned[i] = {
			"item_id": item_id,
			"quantity": maxi(int(cell.get("quantity", 1)), 1),
		}

	load_save_array(cleaned)


func load_save_array(save_array: Array) -> void:
	clear_inventory()

	for i in range(min(save_array.size(), slots.size())):
		var entry = save_array[i]
		if entry == null or typeof(entry) != TYPE_DICTIONARY:
			continue

		var stack: ItemStack = ItemStack.from_dict(entry)
		if stack == null:
			continue

		if stack.data.stackable and stack.quantity > stack.data.max_stack:
			push_warning("InventoryContainer: clamped %s quantity %d -> %d on load" % [
				stack.data.item_id, stack.quantity, stack.data.max_stack
			])
			stack.quantity = stack.data.max_stack

		slots[i].set_stack(stack)

	inventory_changed.emit()


# =============================================================================
# SORTING
# =============================================================================

func sort_by_name() -> void:
	var stacks: Array[ItemStack] = []
	for slot in slots:
		if not slot.is_empty():
			stacks.append(slot.stack.duplicate_stack())

	for slot in slots:
		slot.clear_stack()

	stacks.sort_custom(func(a: ItemStack, b: ItemStack) -> bool:
		return a.data.display_name.to_lower() < b.data.display_name.to_lower()
	)

	for stack in stacks:
		add_stack(stack)


# =============================================================================
# DRAG AND DROP — GRID BACKGROUND
# =============================================================================
# The slots accept drops; the grid they sit in did not. Godot shows the
# forbidden cursor (the circle with a slash) whenever the control under the
# pointer refuses the drag, and the gaps between slots, plus the padding
# around the grid, are all container — not slot. So the cursor flickered to
# "no" across most of the trip between two panels even though the drop was
# perfectly legal the moment it landed on a slot.
#
# Accepting here does two things: the cursor stays sane over the whole grid,
# and a drop that lands in a gap goes to the first free slot instead of
# silently snapping back.

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	# The gaps BETWEEN slots are this container, not a slot — which is the whole
	# reason this override exists (see the comment above). So the loot-bag
	# refusal has to be repeated here, or a drop that landed in a gap would slip
	# into a bag that InventorySlot had already refused.
	if not slots.is_empty() and slots[0].slot_type == InventorySlot.LOOT_SLOT_TYPE:
		return false

	return typeof(data) == TYPE_DICTIONARY \
		and data.has("stack") \
		and data.has("source_slot")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var incoming: ItemStack = data["stack"]
	var source_slot: InventorySlot = data["source_slot"]

	if source_slot == null or not is_instance_valid(source_slot):
		return

	# a hotbar slot only ever holds a reference to an item that really lives
	# in an inventory. dropping it on open space breaks the link and must not
	# move or copy anything — same rule as InventorySlot._drop_data()'s CASE A.
	if source_slot is HotbarSlot:
		source_slot.clear()
		source_slot.slot_changed.emit(source_slot)
		return

	var target: InventorySlot = _first_empty_slot()

	# nowhere to put it. leave the item exactly where it was rather than
	# consuming the drop — a full bank must not eat what you dragged into it.
	if target == null or target == source_slot:
		return

	target.set_stack(incoming)
	source_slot.clear_stack()

	# announce both halves. these reach _on_slot_changed() on each slot's own
	# container, so a cross-panel move saves both sides.
	target.slot_changed.emit(target)
	source_slot.slot_changed.emit(source_slot)


func _first_empty_slot() -> InventorySlot:
	for slot in slots:
		if slot.is_empty():
			return slot
	return null


# =============================================================================
# SIGNAL RELAY
# =============================================================================

func _on_slot_clicked(slot: InventorySlot) -> void:
	slot_clicked.emit(slot)


func _on_slot_right_clicked(slot: InventorySlot) -> void:
	slot_right_clicked.emit(slot)


func _on_slot_double_clicked(slot: InventorySlot) -> void:
	slot_double_clicked.emit(slot)


func _on_slot_transfer_requested(source_slot: InventorySlot, target_slot: InventorySlot) -> void:
	transfer_requested.emit(source_slot, target_slot)


func _on_slot_hovered(slot: InventorySlot) -> void:
	slot_hovered.emit(slot)


func _on_slot_unhovered(slot: InventorySlot) -> void:
	slot_unhovered.emit(slot)


func _on_slot_changed(_slot: InventorySlot) -> void:
	# a slot's contents were changed directly, which in practice means a
	# drag-and-drop. promote it to a container-level change so the save
	# listeners hear about it.
	#
	# THIS IS WHAT WAS DUPLICATING BANK ITEMS. dragging a sword from carry
	# into the bank moved it on screen and saved nothing. closing the bank
	# then wrote the bank out WITH the sword, while the carry inventory's
	# matching removal was still only in memory — so the copy on disk kept
	# it. reload that character and the sword was in both places.
	#
	# a cross-container drag emits this on both containers, one per side, so
	# both halves of the move are now persisted by their own owner: the bank
	# container's listener saves the bank, the carry container's saves the
	# character. a same-container move emits twice into one container, which
	# is a duplicate save rather than a wrong one, and CharacterData's
	# debounce collapses the pair before either reaches disk.
	inventory_changed.emit()
