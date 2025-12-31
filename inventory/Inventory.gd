extends Resource
class_name Inventory

## A simple slot inventory (rows/columns) storing ItemStacks, with restriction masks and
## operations needed for Wyvernbox-style drag/drop (merge/swap/transfer).

signal resized(old_rows: int, old_columns: int, new_rows: int, new_columns: int)
signal slot_changed(index: int)
signal changed_all()

@export var display_name: String = ""

var _rows: int = 4
var _columns: int = 5

@export_range(1, 50) var rows: int = 4:
	get:
		return _rows
	set(value):
		_apply_size(value, _columns)

@export_range(1, 50) var columns: int = 5:
	get:
		return _columns
	set(value):
		_apply_size(_rows, value)

## If 0, accept all. Otherwise, item_type.slot_flags must match (bitwise AND != 0).
@export var accepted_flags_mask: int = 0

@export var slots: Array[ItemStack] = []

func _init():
	_apply_size(_rows, _columns)
	_ensure_slots_size()

func get_capacity() -> int:
	return int(max(1, _rows) * max(1, _columns))

func _ensure_slots_size():
	var cap := get_capacity()
	if slots.size() == cap:
		return
	slots.resize(cap)
	for i in range(cap):
		if slots[i] != null and not slots[i].is_valid():
			slots[i] = null
	emit_signal("changed_all")
	emit_changed()

func resize(new_rows: int, new_columns: int) -> Array[ItemStack]:
	return _apply_size(new_rows, new_columns)

func _apply_size(new_rows: int, new_columns: int) -> Array[ItemStack]:
	new_rows = max(1, new_rows)
	new_columns = max(1, new_columns)
	var old_rows := _rows
	var old_cols := _columns
	var old_slots := slots.duplicate(false)

	_rows = new_rows
	_columns = new_columns

	var new_cap := get_capacity()
	slots.resize(new_cap)
	for i in range(new_cap):
		slots[i] = old_slots[i] if i < old_slots.size() else null

	var overflow: Array[ItemStack] = []
	if old_slots.size() > new_cap:
		for i in range(new_cap, old_slots.size()):
			if old_slots[i] != null:
				overflow.append(old_slots[i])

	emit_signal("resized", old_rows, old_cols, _rows, _columns)
	emit_signal("changed_all")
	emit_changed()
	return overflow

func is_index_valid(index: int) -> bool:
	return index >= 0 and index < slots.size()

func get_stack(index: int) -> ItemStack:
	return slots[index] if is_index_valid(index) else null

func set_stack(index: int, stack: ItemStack) -> void:
	if not is_index_valid(index):
		return
	slots[index] = stack if stack != null and stack.is_valid() else null
	emit_signal("slot_changed", index)
	emit_changed()

func can_accept_item_type(it: ItemType) -> bool:
	if it == null:
		return false
	if accepted_flags_mask == 0:
		return true
	return (it.slot_flags & accepted_flags_mask) != 0

func can_accept_stack(stack: ItemStack) -> bool:
	return stack != null and stack.is_valid() and can_accept_item_type(stack.item_type)

func find_first_empty_slot() -> int:
	for i in range(slots.size()):
		if slots[i] == null:
			return i
	return -1

func find_first_stackable_slot(stack: ItemStack) -> int:
	if stack == null:
		return -1
	for i in range(slots.size()):
		var s := slots[i]
		if s != null and s.can_stack_with(stack, true) and s.quantity < s.item_type.max_stack_size:
			return i
	return -1

## Returns leftover quantity that couldn't be inserted (0 if all inserted).
func try_add(item_type: ItemType, quantity: int, extras: Dictionary = {}) -> int:
	if item_type == null:
		return quantity
	if quantity <= 0:
		return 0
	if not can_accept_item_type(item_type):
		return quantity

	var remaining := quantity
	# Fill existing stacks first.
	for i in range(slots.size()):
		var s := slots[i]
		if s == null:
			continue
		if s.item_type != item_type:
			continue
		if not (s.extra_properties == extras or extras.is_empty()):
			# If extras differ, don't merge.
			continue
		var space: int = max(0, item_type.max_stack_size - s.quantity)
		if space <= 0:
			continue
		var add: int = min(space, remaining)
		s.quantity += add
		remaining -= add
		emit_signal("slot_changed", i)
		if remaining <= 0:
			emit_changed()
			return 0

	# Fill empty slots.
	while remaining > 0:
		var idx := find_first_empty_slot()
		if idx == -1:
			break
		var add2: int = min(item_type.max_stack_size, remaining)
		slots[idx] = ItemStack.new(item_type, add2, extras)
		remaining -= add2
		emit_signal("slot_changed", idx)

	emit_changed()
	return remaining

## Move inside the same inventory: merge if possible, otherwise swap.
func move_within(from_idx: int, to_idx: int) -> bool:
	if not is_index_valid(from_idx) or not is_index_valid(to_idx):
		return false
	if from_idx == to_idx:
		return true

	var from_stack := slots[from_idx]
	if from_stack == null:
		return false

	var to_stack := slots[to_idx]
	if to_stack == null:
		slots[to_idx] = from_stack
		slots[from_idx] = null
		emit_signal("slot_changed", from_idx)
		emit_signal("slot_changed", to_idx)
		emit_changed()
		return true

	# Merge if compatible.
	if to_stack.can_stack_with(from_stack, true):
		var space: int = max(0, to_stack.item_type.max_stack_size - to_stack.quantity)
		if space > 0:
			var moved: int = min(space, from_stack.quantity)
			to_stack.quantity += moved
			from_stack.quantity -= moved
			if from_stack.quantity <= 0:
				slots[from_idx] = null
			emit_signal("slot_changed", from_idx)
			emit_signal("slot_changed", to_idx)
			emit_changed()
			return true

	# Otherwise swap.
	slots[from_idx] = to_stack
	slots[to_idx] = from_stack
	emit_signal("slot_changed", from_idx)
	emit_signal("slot_changed", to_idx)
	emit_changed()
	return true

## Transfer between inventories using the same merge/swap rules, but respecting restrictions.
func try_transfer_to(other: Inventory, from_idx: int, to_idx: int) -> bool:
	if other == null:
		return false
	if not is_index_valid(from_idx) or not other.is_index_valid(to_idx):
		return false

	var from_stack := slots[from_idx]
	if from_stack == null:
		return false
	if not other.can_accept_stack(from_stack):
		return false

	var to_stack := other.slots[to_idx]
	if to_stack == null:
		other.slots[to_idx] = from_stack
		slots[from_idx] = null
		emit_signal("slot_changed", from_idx)
		other.emit_signal("slot_changed", to_idx)
		emit_changed()
		other.emit_changed()
		return true

	# Merge if possible.
	if to_stack.can_stack_with(from_stack, true):
		var space: int = max(0, to_stack.item_type.max_stack_size - to_stack.quantity)
		if space > 0:
			var moved: int = min(space, from_stack.quantity)
			to_stack.quantity += moved
			from_stack.quantity -= moved
			if from_stack.quantity <= 0:
				slots[from_idx] = null
			emit_signal("slot_changed", from_idx)
			other.emit_signal("slot_changed", to_idx)
			emit_changed()
			other.emit_changed()
			return true

	# Swap only if this inventory can accept the other stack.
	if not can_accept_stack(to_stack):
		return false

	slots[from_idx] = to_stack
	other.slots[to_idx] = from_stack
	emit_signal("slot_changed", from_idx)
	other.emit_signal("slot_changed", to_idx)
	emit_changed()
	other.emit_changed()
	return true


