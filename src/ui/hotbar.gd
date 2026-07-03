# hotbar.gd — manages 9 quickslot HotbarSlots for the player's combat hotbar.
# parent script for the hotbar container node in characterhud.tscn.
#
# responsibilities:
# - holds 9 HotbarSlot child references (assigned in inspector OR found by name)
# - listens to player.inventory_changed and refreshes all slots
# - handles number key 1-9 input → use item in that slot
# - handles right-click on slot → use that slot's item
# - enforces "one item_id per hotbar" uniqueness rule
# - syncs to/from CharacterData for per-character save persistence
# - tells the inventory container which item_ids are linked so matching
#   inventory items get a gold border to visually show the connection
#
# usage:
# - parent HUD calls set_player(player) when active character changes
# - parent calls set_inventory_container(container) so we can look up stacks
# - hotbar listens to container.inventory_changed for auto-refresh
#
# input model:
# - number keys 1-9 use the assigned item
# - right-click on a slot uses the assigned item
# - both routes dispatch to the same use_item flow
extends Control
class_name Hotbar


# =============================================================================
# SIGNALS
# =============================================================================

# emitted when the player triggers a hotbar item use (key or right-click).
# parent HUD listens and routes to the actual use_item logic.
signal item_used(item_id: String)


# =============================================================================
# CONSTANTS
# =============================================================================

# expected number of hotbar slots
const SLOT_COUNT := 9


# =============================================================================
# STATE
# =============================================================================

# the 9 hotbar slot child references — resolved in _ready by name lookup
# (slot1 through slot9 children).
var slots: Array[HotbarSlot] = []

# the player whose inventory we read from. set via set_player.
var player: Node = null

# the inventory container we sync hotbar display with.
var inventory_container: Node = null


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_resolve_slot_children()
	_wire_slot_signals()


func _unhandled_input(event: InputEvent) -> void:
	# number keys 1-9 trigger the corresponding hotbar slot.
	# KEY_1 through KEY_9 map directly to slot indices 0-8.
	if not (event is InputEventKey) or not event.pressed:
		return

	var key_to_slot_index: int = -1
	match event.keycode:
		KEY_1: key_to_slot_index = 0
		KEY_2: key_to_slot_index = 1
		KEY_3: key_to_slot_index = 2
		KEY_4: key_to_slot_index = 3
		KEY_5: key_to_slot_index = 4
		KEY_6: key_to_slot_index = 5
		KEY_7: key_to_slot_index = 6
		KEY_8: key_to_slot_index = 7
		KEY_9: key_to_slot_index = 8

	if key_to_slot_index >= 0:
		_use_slot(key_to_slot_index)


# =============================================================================
# INITIALIZATION HELPERS
# =============================================================================

func _resolve_slot_children() -> void:
	# look up slot1 through slot9 children by name. fills the `slots` array.
	# null entries warn but don't crash so partial hotbars still function.
	slots.clear()
	for i in range(SLOT_COUNT):
		var slot_name: String = "slot%d" % (i + 1)
		if has_node(slot_name):
			var slot: HotbarSlot = get_node(slot_name) as HotbarSlot
			if slot == null:
				push_warning("Hotbar: %s is not a HotbarSlot" % slot_name)
			slots.append(slot)
		else:
			push_warning("Hotbar: missing child %s" % slot_name)
			slots.append(null)


func _wire_slot_signals() -> void:
	# subscribe to each slot's signals for right-click use, drag completion,
	# and assignment uniqueness enforcement.
	for slot in slots:
		if slot == null:
			continue
		if not slot.slot_right_clicked.is_connected(_on_slot_right_clicked):
			slot.slot_right_clicked.connect(_on_slot_right_clicked)
		if not slot.slot_changed.is_connected(_on_slot_changed):
			slot.slot_changed.connect(_on_slot_changed)


# =============================================================================
# PUBLIC API
# =============================================================================

func set_player(p: Node) -> void:
	# called by the HUD when the active character changes.
	# loads the saved hotbar assignments for this character.
	player = p
	if player != null:
		_load_assignments_from_player()


func set_inventory_container(container: Node) -> void:
	# called by the HUD after the inventory screen exists. subscribes to
	# inventory_changed so the hotbar auto-refreshes on every mutation.
	# also pushes initial linked ids so existing assignments highlight
	# their inventory counterparts.
	inventory_container = container

	if inventory_container == null:
		return

	if inventory_container.has_signal("inventory_changed"):
		if not inventory_container.inventory_changed.is_connected(_on_inventory_changed):
			inventory_container.inventory_changed.connect(_on_inventory_changed)

	refresh_all_slots()
	_push_linked_ids_to_inventory()


func refresh_all_slots() -> void:
	# update every slot's display from the current inventory state.
	# called after set_inventory_container and on every inventory_changed.
	for slot in slots:
		if slot != null:
			slot.refresh_from_inventory(inventory_container)


func clear_all() -> void:
	# wipe all 9 slot assignments. called on death cleanup.
	for slot in slots:
		if slot != null:
			slot.clear()
	_save_assignments_to_player()
	_push_linked_ids_to_inventory()


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_inventory_changed() -> void:
	# inventory contents changed — refresh display to pick up new quantities
	# and auto-clear hotbar slots whose items are now at 0.
	refresh_all_slots()


func _on_slot_right_clicked(slot: HotbarSlot) -> void:
	# right-clicking a hotbar slot uses the assigned item, same as a number key.
	if slot == null or not slot.is_assigned():
		return
	item_used.emit(slot.get_item_id())


func _on_slot_changed(_slot: HotbarSlot) -> void:
	# a drag-drop modified a slot's assignment — enforce uniqueness,
	# persist atomically, and update inventory tinting.
	_enforce_unique_assignments()
	_save_assignments_to_player()
	refresh_all_slots()
	_push_linked_ids_to_inventory()

	# atomic save — hotbar changes persist immediately so a crash mid-session
	# can't lose drag/drop work
	if player != null:
		CharacterData.save_character_state(player)


# =============================================================================
# USE DISPATCH
# =============================================================================

func _use_slot(slot_index: int) -> void:
	# fire the item_used signal for the slot at this index, if assigned.
	# parent HUD subscribes and routes to inventoryscreen's use_item logic.
	if slot_index < 0 or slot_index >= slots.size():
		return

	var slot: HotbarSlot = slots[slot_index]
	if slot == null or not slot.is_assigned():
		return

	item_used.emit(slot.get_item_id())


# =============================================================================
# UNIQUENESS ENFORCEMENT
# =============================================================================

func _enforce_unique_assignments() -> void:
	# walk the slots and ensure each item_id appears at most once.
	# if a duplicate is found, the EARLIER slot is cleared so the most
	# recent assignment wins (matches drag-drop user intent).
	var seen_ids: Dictionary = {}

	# walk in reverse so the LATEST slot keeps the assignment
	for i in range(slots.size() - 1, -1, -1):
		var slot: HotbarSlot = slots[i]
		if slot == null or not slot.is_assigned():
			continue

		var item_id: String = slot.get_item_id()
		if seen_ids.has(item_id):
			# duplicate — clear this older slot
			slot.set_item_id("")
		else:
			seen_ids[item_id] = true


# =============================================================================
# INVENTORY LINK TINTING
# =============================================================================

func _push_linked_ids_to_inventory() -> void:
	# tell the inventory container which item_ids are currently assigned to
	# hotbar slots. the container uses this to apply gold borders to matching
	# inventory items, visually showing the inventory-to-hotbar link.
	if inventory_container == null:
		return
	if not inventory_container.has_method("set_linked_item_ids"):
		return

	var ids: Array = []
	for slot in slots:
		if slot != null and slot.is_assigned():
			ids.append(slot.get_item_id())

	inventory_container.set_linked_item_ids(ids)


# =============================================================================
# SAVE PERSISTENCE
# =============================================================================

func _load_assignments_from_player() -> void:
	# read hotbar_assignments from the player and apply to slots.
	# fresh characters / death-cleared hotbars start with all empty strings.
	if player == null or not "hotbar_assignments" in player:
		return

	var assignments: Array = player.hotbar_assignments
	for i in range(min(slots.size(), assignments.size())):
		if slots[i] == null:
			continue
		slots[i].set_item_id(str(assignments[i]))

	# refresh display in case inventory_container is already set
	refresh_all_slots()


func _save_assignments_to_player() -> void:
	# persist the current 9 slot assignments to the player as an array of
	# item_id strings. CharacterData.save_character_state will pick this up
	# on the next atomic save event (item pickup, XP gain, etc.).
	if player == null:
		return
	if not "hotbar_assignments" in player:
		return

	var assignments: Array = []
	for slot in slots:
		if slot == null:
			assignments.append("")
		else:
			assignments.append(slot.get_item_id())

	player.hotbar_assignments = assignments
