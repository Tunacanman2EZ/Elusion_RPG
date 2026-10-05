# inventory grid container — manages a grid of inventory slots.
# inherited by any UI that needs a grid-based inventory display (player
# inventory, bank, loot bag, future shop UI, etc.).
#
# architecture:
# - one InventorySlot scene per grid cell, instanced in _ready
# - slot signals (click, right-click, double-click) relay up to
#   whoever owns this container
# - save format is item_id + quantity per slot — small + MMO-ready
# - the player's backpack also owns the hotbar's ten keys, as cells past the
#   grid; see "CELLS PAST THE GRID" below
#
# THIS CONTAINER NO LONGER DECIDES WHERE AN ITEM GOES. It had a full local
# placement API — add_stack, add_stack_partial, add_stack_at, can_add_stack,
# has_space, remove_quantity_by_id, sort_by_name, resize — and every one of
# them is gone, because the server owns the layout now. load_server_array()
# applies the array an endpoint hands back; see its own comment for the bug
# that made this the rule. If you need a bag to change, ask an endpoint.
#
# common usage flow:
# 1. parent scene places InventoryContainer in its tree
# 2. _ready instantiates slots based on grid_width × grid_height
# 3. an endpoint answers, and the parent calls load_server_array()
# 4. inventory_changed signal fires on every mutation for save sync
# 5. the hotbar hands over its slots with attach_remote_slots()
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

# THE PLAYER'S OWN CARRY, as opposed to the bank's grid, which is the same kind
# of container. Set by InventoryScreen.
var is_carry: bool = false

# THE ACCOUNT'S BANK. Set by BankInventory. Between them these two say which
# server route a drag or the bin in this grid becomes - see THE SERVER DOES IT.
var is_bank: bool = false

var capacity: int:
	get: return grid_width * grid_height


# =============================================================================
# CELLS PAST THE GRID
# =============================================================================
# THE HOTBAR'S KEYS ARE THIS BACKPACK'S CELLS capacity .. capacity + 9. The
# server stores them as carry_items rows after the bag and hands them back in
# the same array, so the one container that applies that array has to own them
# - otherwise every endpoint answer would update the bag and leave a key
# showing an item the server had just moved. They are drawn by the hotbar,
# which is why they are not children of this grid.
#
# `slots` is therefore EVERY cell, in position order: the grid, then the keys.
# slots[i].slot_index == i holds for all of them, which is what lets
# remove_quantity_at(), remove_stack_at() and a trash drop work on a key with
# no code that knows it is one. `capacity` is still only the grid.
#
# UNTIL THE HOTBAR ATTACHES, THE KEYS ARE KEPT AS DATA. The HUD loads the bag
# before it wires the hotbar, and a container with nowhere to put cells 20-29
# must not simply drop them - the next save would then send twenty cells, and
# although the server leaves keys alone for a short array (see
# write_inventory() in app.py), the player would still see an empty hotbar.
# So they wait in _unattached_tail, go out again on a save, and are handed to
# the hotbar's slots the moment they exist.

var _remote_slots: Array[InventorySlot] = []
var _unattached_tail: Array = []


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
		slot_instance.home_container = self

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
		slot_instance.slot_changed.connect(_on_slot_changed)

		add_child(slot_instance)
		slots.append(slot_instance)


func resize_grid(width: int, height: int) -> void:
	"""A different number of cells: the cooking screen shows one row of fish
	and grows a second only when there are more kinds than fit. The cells are
	built again, empty - the caller loads them after."""
	width = maxi(1, width)
	height = maxi(1, height)
	if width == grid_width and height == grid_height and slots.size() == capacity:
		return
	grid_width = width
	grid_height = height
	columns = grid_width
	_create_slots()


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


func clear_inventory() -> void:
	for slot in slots:
		slot.clear_stack()
	_unattached_tail.clear()
	inventory_changed.emit()


func set_slot_type(type_name: String) -> void:
	# Stamps every slot in this grid with a context name. Only "lootbag" changes
	# behaviour: InventorySlot refuses to start a drag from one or accept a drop
	# onto one, because a loot bag belongs to the server and a drag is not a
	# request. See lootbaginventory.gd's header.
	#
	# Applied here rather than in the scene because the slots are instantiated
	# by _create_slots() at runtime, so there is nothing in the .tscn to set.
	#
	# THE GRID ONLY. A hotbar key keeps its own "hotbar" type whatever this
	# container is being used as.
	for i in range(mini(capacity, slots.size())):
		slots[i].slot_type = type_name


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
# CELLS PAST THE GRID — ATTACHING THE HOTBAR
# =============================================================================

func attach_remote_slots(remote: Array) -> void:
	# The hotbar's slots become cells capacity, capacity + 1, ... of this
	# container, in the order given.
	#
	# ALL OR NOTHING. A key missing from the middle would shift every key after
	# it one cell to the left, so potions saved on key 4 would load onto key 3.
	# A partial set is refused outright and the keys stay kept as data, which
	# loses nothing - the next save still sends them.
	for entry in remote:
		if not (entry is InventorySlot) or not is_instance_valid(entry):
			push_error("InventoryContainer: attach_remote_slots() given a missing or non-slot entry - hotbar not attached")
			return

	# Carried over rather than lost if the hotbar is re-attached: whatever the
	# old keys held is what the new ones must show.
	var carried: Array = _remote_cells()

	for old in _remote_slots:
		if is_instance_valid(old):
			_disconnect_slot(old)
	_remote_slots.clear()
	slots.resize(capacity)

	for i in range(remote.size()):
		var slot: InventorySlot = remote[i] as InventorySlot
		slot.slot_index = capacity + i
		slot.home_container = self
		# NOT slot_clicked OR slot_right_clicked. The hotbar answers a
		# right-click on a key itself, and relaying it too would use the item
		# twice. What the backpack needs from a key is to hear that it changed
		# (so the carry saves), and the two gestures the bank listens for.
		slot.slot_changed.connect(_on_slot_changed)
		slot.transfer_requested.connect(_on_slot_transfer_requested)
		slot.slot_double_clicked.connect(_on_slot_double_clicked)
		slots.append(slot)
		_remote_slots.append(slot)

	for i in range(_remote_slots.size()):
		var entry = carried[i] if i < carried.size() else null
		var stack: ItemStack = _stack_from_entry(entry)
		if stack == null:
			_remote_slots[i].clear_stack()
		else:
			_remote_slots[i].set_stack(stack)
	_unattached_tail.clear()


func _remote_cells() -> Array:
	# What cells past the grid hold right now, as save entries - from the
	# attached keys, or from the tail while nothing is attached.
	if _remote_slots.is_empty():
		return _unattached_tail.duplicate()
	var out: Array = []
	for slot in _remote_slots:
		if not is_instance_valid(slot) or slot.is_empty():
			out.append(null)
		else:
			out.append(slot.stack.to_dict())
	return out


func _disconnect_slot(slot: InventorySlot) -> void:
	if slot.slot_changed.is_connected(_on_slot_changed):
		slot.slot_changed.disconnect(_on_slot_changed)
	if slot.transfer_requested.is_connected(_on_slot_transfer_requested):
		slot.transfer_requested.disconnect(_on_slot_transfer_requested)
	if slot.slot_double_clicked.is_connected(_on_slot_double_clicked):
		slot.slot_double_clicked.disconnect(_on_slot_double_clicked)


# =============================================================================
# SAVE / LOAD
# =============================================================================

func to_save_array() -> Array:
	# Every cell, the hotbar's keys included - attached or still waiting as data.
	var result: Array = []
	for slot in slots:
		if slot.is_empty():
			result.append(null)
		else:
			result.append(slot.stack.to_dict())
	if _remote_slots.is_empty():
		result.append_array(_unattached_tail)
	return result


func load_server_array(cells: Array) -> void:
	# THE SERVER'S LAYOUT, APPLIED AS-IS.
	#
	# Endpoints that change the backpack - /api/loot/take, /api/staff/grant -
	# return the WHOLE array, built the way this container would build it: an
	# existing stack topped up before a new cell is opened. Applying that rather
	# than placing the item locally is what stops the two laying the same pickup
	# out differently, which is what happened the first time a potion landed on
	# a part-used stack. add_stack() was the local version; it is why it is gone.
	#
	# The coercion is the reason this is a method rather than a line at each call
	# site. JSON HAS NO INTEGER TYPE, so every quantity arrives as a float, and
	# ItemStack.from_dict() building a stack of 5.0 is not a stack of 5. There
	# were two places doing this the moment /api/staff/grant existed; now there
	# is one.
	#
	# AN EMPTY ARRAY IS NOT AN EMPTY BACKPACK, and applying one would be data
	# loss. inventory_payload() always returns CARRY_CAPACITY cells with null in
	# the gaps - the bag's twenty and then the hotbar's ten - so a genuinely
	# empty carry arrives as [null, null, ...] of length 30.
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
		var stack: ItemStack = _stack_from_entry(save_array[i])
		if stack != null:
			slots[i].set_stack(stack)

	# Cells past everything this container can draw yet - the hotbar's keys,
	# before the hotbar has attached. Kept, not dropped; see CELLS PAST THE GRID.
	if _remote_slots.is_empty() and save_array.size() > slots.size():
		_unattached_tail = save_array.slice(slots.size())

	inventory_changed.emit()


func _stack_from_entry(entry: Variant) -> ItemStack:
	if entry == null or typeof(entry) != TYPE_DICTIONARY:
		return null

	var stack: ItemStack = ItemStack.from_dict(entry)
	if stack == null:
		return null

	if stack.data.stackable and stack.quantity > stack.data.max_stack:
		push_warning("InventoryContainer: clamped %s quantity %d -> %d on load" % [
			stack.data.item_id, stack.quantity, stack.data.max_stack
		])
		stack.quantity = stack.data.max_stack
	return stack


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

	# THE BANK RULE HAS TO BE REPEATED HERE, exactly like the loot-bag one in
	# _can_drop_data() above, and for exactly the same reason: the gaps between
	# slots are this container, not a slot, so a drop that lands in one never
	# reaches InventorySlot._drop_data() and never meets its CASE T.
	#
	# WITHOUT THIS, RELEASING A BANK STACK OVER THE 4px GAP BETWEEN TWO CARRY
	# SLOTS MOVED IT LOCALLY. No POST /api/bank/items was ever sent; both
	# containers then wrote their whole arrays, so the item existed in the
	# backpack save and not in the bank one — two independent writes the server
	# cannot tell are two halves of one transfer. Aiming at a slot behaved
	# correctly, which made it read as intermittent duplication rather than as
	# a rule with a hole in it.
	#
	# XOR, matching CASE T: bank-to-bank is a rearrange and moves no items.
	var source_type: String = str(data.get("source_type", ""))
	var here_is_bank: bool = not slots.is_empty() \
		and slots[0].slot_type == InventorySlot.BANK_SLOT_TYPE
	if (source_type == InventorySlot.BANK_SLOT_TYPE) != here_is_bank:
		# target_slot is ignored by the handler — the endpoint takes an item and
		# a quantity, not a position — so there is nothing to name here.
		transfer_requested.emit(source_slot, null)
		return

	var target: InventorySlot = _first_empty_slot()

	# nowhere to put it. leave the item exactly where it was rather than
	# consuming the drop — a full bank must not eat what you dragged into it.
	if target == null or target == source_slot:
		return

	target.set_stack(incoming)
	source_slot.clear_stack()

	# announce both halves, so anything drawn from this grid redraws.
	target.slot_changed.emit(target)
	source_slot.slot_changed.emit(source_slot)

	# AND ASK THE SERVER, which owns the grid - see THE SERVER DOES IT. A gap
	# drop is a move onto the first empty cell, the same request as a drop
	# aimed at that cell.
	if source_slot.home_container == self:
		request_move(source_slot.slot_index, target.slot_index, incoming.data.item_id)


# =============================================================================
# THE SERVER DOES IT
# =============================================================================
# THE BAG AND THE BANK ARE THE SERVER'S (ONE CELL AT A TIME in app.py). A drag
# inside one grid, and the bin, used to happen only here and reach the server
# as the whole array on the next save, which it trimmed to what it had granted.
# Now each is a request the server carries out on its own cells, and the grid
# is redrawn from its answer.
#
# THE CHANGE IS STILL DRAWN AT ONCE. InventorySlot moves the stacks the moment
# the drop lands, because a round trip under the cursor would make every drag
# feel sticky. The answer then agrees, and nothing on screen changes, or it
# puts back what the server holds - the 409 a move gets when this grid was out
# of date carries exactly that.
#
# ONE AT A TIME, IN THE ORDER MADE, AND ONLY THE LAST ANSWER IS DRAWN. Two
# quick drags are two requests and the second is built on the first. Drawing
# the first answer while the second is on its way would flick the second drag
# back for a moment.

const CARRY_MOVE_PATH := "/api/character/inventory/move"
const CARRY_DISCARD_PATH := "/api/character/inventory/discard"
const BANK_MOVE_PATH := "/api/bank/move"
const BANK_DISCARD_PATH := "/api/bank/discard"

# Waiting requests, [path, body] each, and whether one is on its way.
var _queue: Array = []
var _sending: bool = false

# THE SUITE'S WAY IN. When valid, called as (path, body) instead of Api.post,
# and must return what Api.post would. Never set by the game.
var send_override: Callable = Callable()


func is_server_grid() -> bool:
	return is_carry or is_bank


func is_busy() -> bool:
	"""True while a move or a bin is on its way to the server."""
	return _sending or not _queue.is_empty()


func request_move(from_index: int, to_index: int, item_id: String) -> void:
	"""Ask the server to do the drag the grid has just drawn."""
	if not is_server_grid() or from_index == to_index or item_id == "":
		return
	if is_carry:
		_enqueue(CARRY_MOVE_PATH, {"slot": CharacterData.active_character_index,
			"from": from_index, "to": to_index, "item_id": item_id})
	else:
		_enqueue(BANK_MOVE_PATH, {"from": from_index, "to": to_index, "item_id": item_id})


func request_discard(index: int, expected_item_id: String = "") -> void:
	"""The bin: take the stack off the grid now, and have the server destroy it.
	With `expected_item_id`, a cell that holds anything else is left alone."""
	if index < 0 or index >= slots.size() or slots[index].is_empty():
		return
	var item_id: String = slots[index].stack.data.item_id
	if expected_item_id != "" and item_id != expected_item_id:
		push_warning("InventoryContainer: cell %d holds %s now, not %s - not destroyed"
			% [index, item_id, expected_item_id])
		return
	remove_stack_at(index)
	if not is_server_grid():
		return
	if is_carry:
		_enqueue(CARRY_DISCARD_PATH, {"slot": CharacterData.active_character_index,
			"position": index, "item_id": item_id})
	else:
		_enqueue(BANK_DISCARD_PATH, {"position": index, "item_id": item_id})


func _enqueue(path: String, body: Dictionary) -> void:
	_queue.append([path, body])
	if not _sending:
		_drain()


func _drain() -> void:
	_sending = true
	var last: Dictionary = {}
	while not _queue.is_empty():
		var next: Array = _queue.pop_front()
		last = await _post(next[0], next[1])
		if not is_instance_valid(self):
			return
		if not last.get("ok", false) and int(last.get("status", 0)) != 409:
			push_warning("InventoryContainer: %s refused - HTTP %d %s" % [
				next[0], int(last.get("status", 0)), str(last.get("error", ""))])
	_sending = false
	await _adopt_answer(last)


func _post(path: String, body: Dictionary) -> Dictionary:
	if send_override.is_valid():
		return await send_override.call(path, body)
	return await Api.post(path, body)


func _adopt_answer(res: Dictionary) -> void:
	"""Draw the grid the server's last answer holds. A carry that was out of
	date goes through CharacterData.apply_server_carry(), the way a stale save
	and a trade's result always have; an answer with no grid in it - no
	connection, a 500 - asks for the grid instead, because what is drawn now is
	only a guess."""
	var data: Variant = res.get("data", {})
	if not (data is Dictionary):
		data = {}
	if res.get("ok", false):
		var cells: Variant = data.get("inventory" if is_carry else "bank_inventory")
		if cells is Array and not (cells as Array).is_empty():
			load_server_array(cells)
			return
	elif int(res.get("status", 0)) == 409:
		# THE CARRY'S RESYNC GOES THROUGH CharacterData TOO, which keeps the
		# character's copy and purse in step and says nothing for a stale_save.
		# It redraws the HUD's grid - this one, in the game - and the load here
		# makes sure of it for any other grid.
		var resync: Variant = data.get("resync")
		if is_carry and resync is Dictionary and resync.get("inventory") is Array \
				and not (resync["inventory"] as Array).is_empty():
			CharacterData.apply_server_carry(resync)
			load_server_array(resync["inventory"])
			return
		var account: Variant = data.get("account")
		if is_bank and account is Dictionary and account.get("bank_inventory") is Array:
			load_server_array(account["bank_inventory"])
			return
	await _refetch()


func _refetch() -> void:
	if send_override.is_valid():
		return
	var res: Dictionary
	if is_carry:
		res = await Api.get_json("/api/character?slot=%d" % CharacterData.active_character_index)
	else:
		res = await Api.get_json("/api/account")
	if not is_instance_valid(self):
		return
	var data: Variant = res.get("data", {})
	var cells: Variant = data.get("inventory" if is_carry else "bank_inventory") \
		if res.get("ok", false) and data is Dictionary else null
	if cells is Array and not (cells as Array).is_empty():
		load_server_array(cells)
	else:
		push_warning("InventoryContainer: the server could not be asked for the %s - "
			% ("backpack" if is_carry else "bank") + "it will be redrawn from the next answer")


func _first_empty_slot() -> InventorySlot:
	# THE GRID ONLY. A stack dropped in the gap between two bag cells belongs in
	# the bag, not on whichever hotbar key happens to be the first empty cell.
	for i in range(mini(capacity, slots.size())):
		if slots[i].is_empty():
			return slots[i]
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
