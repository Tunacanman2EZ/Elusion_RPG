# lootbaginventory.gd — the draggable loot-bag panel. mirrors bankinventory
# but points at a specific WORLD loot bag instead of persistent account storage.
#
# double-click quick-transfer:
# double-clicking a loot slot moves that stack to the player's inventory.
# if the inventory can't fit the whole stack, the fit portion goes and the
# leftover stays in the loot bag. if inventory is completely full for that
# item type, nothing moves and a message logs to console.
#
# AUTO-CLOSE ON DISTANCE (NEW):
# lootbag.gd emits player_left_range when the player who has this panel open
# walks out of its Area2D. we connect to that signal in open_for_bag() and
# route it straight into _on_close_pressed() — the exact same close path the
# X button uses (sync remaining contents back to the bag, hide, clear ref) —
# so there's only ever one way this panel actually closes, not two divergent
# ones. the connection is torn down in _disconnect_world_bag_signal(),
# called both when closing normally and before wiring a new bag, so a stale
# connection to a previous (possibly despawned) bag can never fire against
# whatever bag the panel is currently pointed at.
extends Control


const LOOT_SIZE := 6
const LUSION_ITEM_ID := "lusions"


@onready var loot_container: Node = %lootcontainer
@onready var close_button: Button = %closebutton


var _world_bag: Node = null
var _player: Node = null
var _loading: bool = false


func _notify(message: String) -> void:
	# mirrors inventoryscreen.gd's funnel. _player is whoever opened this bag
	# (set by open_for_bag), and it is null whenever the panel is closed.
	if _player != null and _player.has_method("show_notice"):
		_player.show_notice(message)


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	if close_button != null and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)

	if loot_container.has_signal("inventory_changed"):
		if not loot_container.inventory_changed.is_connected(_on_container_changed):
			loot_container.inventory_changed.connect(_on_container_changed)

	if loot_container.has_signal("slot_double_clicked"):
		if not loot_container.slot_double_clicked.is_connected(_on_slot_double_clicked):
			loot_container.slot_double_clicked.connect(_on_slot_double_clicked)

	visible = false


# =============================================================================
# OPEN / CLOSE
# =============================================================================

func open_for_bag(world_bag: Node, player: Node) -> void:
	# tear down any leftover connection to a PREVIOUS bag before pointing
	# this panel at a new one — prevents a stale signal from an old bag
	# ever reaching _on_close_pressed() once we've moved on.
	_disconnect_world_bag_signal()

	_world_bag = world_bag
	_player = player
	_loading = true
	_load_contents(world_bag.get_contents())
	_loading = false
	visible = true

	# NEW: snap the panel's size to its real content (header + 6-slot grid)
	# instead of whatever fixed size was last set in the editor. only works
	# correctly now that lootscroll (a ScrollContainer) has been removed from
	# the hierarchy — ScrollContainers don't propagate their child's actual
	# size upward, which is what caused the dead space below the grid.
	# called after visible = true since Godot needs the control to be
	# visible to compute an accurate combined minimum size.
	reset_size()

	# NEW: listen for the bag telling us the player walked out of range.
	if _world_bag != null and _world_bag.has_signal("player_left_range"):
		if not _world_bag.player_left_range.is_connected(_on_close_pressed):
			_world_bag.player_left_range.connect(_on_close_pressed)


func _on_close_pressed() -> void:
	_sync_back_to_bag()

	# NEW: tell the bag we're closed, regardless of why (X button, walked
	# away, etc.) — is_instance_valid guards against the bag already being
	# freed (e.g. this fires as part of the empty-inventory despawn path
	# too, where the bag is gone or about to be). see notify_panel_closed()
	# in lootbag.gd for why this matters beyond just the despawn-pause: it's
	# also the only thing that resets _is_open when closing via X while
	# still standing in range, since that path never triggers body_exited.
	if is_instance_valid(_world_bag) and _world_bag.has_method("notify_panel_closed"):
		_world_bag.notify_panel_closed()

	_disconnect_world_bag_signal()
	visible = false
	_world_bag = null


func _disconnect_world_bag_signal() -> void:
	# NEW: shared cleanup so the player_left_range connection never outlives
	# its usefulness — called before wiring a new bag AND when closing.
	if _world_bag != null and _world_bag.has_signal("player_left_range"):
		if _world_bag.player_left_range.is_connected(_on_close_pressed):
			_world_bag.player_left_range.disconnect(_on_close_pressed)


# =============================================================================
# CONTENT LOAD
# =============================================================================

func _load_contents(contents: Array) -> void:
	var resolved: Array = []
	for entry in contents:
		# NEW: skip empty-slot placeholders. %lootcontainer's save-array
		# format represents empty slots as null (or possibly an empty dict)
		# in a fixed-length array rather than omitting them — without this
		# guard, entry.get(...) below crashes with "Nonexistent function
		# 'get' in base 'Nil'" the moment any slot is empty.
		if not (entry is Dictionary):
			continue

		var item_id: String = entry.get("item_id", "")
		var qty: int = entry.get("quantity", 1)
		if item_id == "":
			continue
		var data: ItemData = ItemRegistry.get_item(item_id)
		if data == null:
			continue
		if data.type == ItemData.Type.PET and _player_owns_pet(item_id):
			resolved.append({
				"item_id": LUSION_ITEM_ID,
				"quantity": GameConstants.DUPE_PET_LUSIONS,
			})
		else:
			resolved.append({ "item_id": item_id, "quantity": qty })

	loot_container.load_save_array(resolved)


# =============================================================================
# DOUBLE-CLICK → SEND TO INVENTORY
# =============================================================================

func _on_slot_double_clicked(slot: InventorySlot) -> void:
	if _player == null or slot == null or slot.is_empty():
		return

	var inv_container: Node = _get_player_inventory_container()
	if inv_container == null:
		push_warning("LootBagInventory: player inventory not found — can't transfer")
		return

	var full_stack: ItemStack = slot.stack.duplicate_stack()

	if inv_container.has_method("add_stack_partial"):
		var leftover: int = inv_container.add_stack_partial(full_stack)
		var moved: int = slot.stack.quantity - leftover

		if moved <= 0:
			# "your inventory is full" is the single most useful thing this
			# panel can tell a player, and it used to tell the console.
			_notify("Inventory full")
			return

		loot_container.remove_quantity_at(slot.slot_index, moved)
	else:
		if not inv_container.can_add_stack(full_stack):
			_notify("Inventory full")
			return
		if inv_container.add_stack(full_stack):
			loot_container.remove_quantity_at(slot.slot_index, full_stack.quantity)


func _get_player_inventory_container() -> Node:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return null
	var inv_screen: Node = hud.get("inventory_screen") if "inventory_screen" in hud else null
	if inv_screen == null:
		return null
	return inv_screen.get_node_or_null("%inventorycontainer")


# =============================================================================
# CHANGE / SYNC / DESPAWN
# =============================================================================

func _on_container_changed() -> void:
	if _loading:
		return
	if _player != null:
		CharacterData.save_character_state(_player)
	_sync_back_to_bag()

	var empty: bool = _is_container_empty()

	if empty:
		if _world_bag != null and _world_bag.has_method("despawn_now"):
			_world_bag.despawn_now()
		_disconnect_world_bag_signal()
		_world_bag = null
		visible = false


func _sync_back_to_bag() -> void:
	if _world_bag == null:
		return
	if _world_bag.has_method("set_contents"):
		_world_bag.set_contents(loot_container.to_save_array())


func _is_container_empty() -> bool:
	# THIS COULD NEVER RETURN TRUE.
	#
	# to_save_array() is fixed-length: it appends null for every empty slot
	# rather than omitting it, so the array is always exactly as long as the
	# grid and is_empty() was always false. The bag therefore never despawned
	# when the player took the last item, and the panel never auto-closed —
	# you had to close it by hand and the empty bag sat on the ground until
	# its despawn timer ran out.
	#
	# "Empty" means no slot holds anything, not "the array has no entries".
	var arr: Array = loot_container.to_save_array()
	for entry in arr:
		if entry is Dictionary and entry.get("item_id", "") != "":
			return false
	return true


# =============================================================================
# PET OWNERSHIP CHECK
# =============================================================================

func _player_owns_pet(pet_id: String) -> bool:
	if _player == null:
		return false
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud != null and hud.get("inventory_screen") != null:
		var inv: Node = hud.inventory_screen.get_node_or_null("%inventorycontainer")
		if inv != null and inv.has_method("find_first_index_of"):
			if inv.find_first_index_of(pet_id) != -1:
				return true
	# THE null GUARD HERE IS THE WHOLE BUG.
	#
	# get_bank_inventory() returns a FIXED-LENGTH array padded to
	# BANK_MAX_SLOTS, with null standing in for every empty slot — so
	# entry.get(...) hit "Nonexistent function 'get' in base 'Nil'" on the
	# first empty bank slot. This only runs when a PET drops, which is why it
	# looked like pets specifically broke the loot panel.
	#
	# _load_contents() above already guards the identical case, with a comment
	# describing this exact crash. This copy of the loop never got it.
	#
	# The damage went past the one bag: this is called from _load_contents(),
	# which runs between `_loading = true` and `_loading = false` in
	# open_for_bag(). A crash there aborts before the flag is lowered, and
	# _on_container_changed() returns early while _loading is true — so loot
	# taken after that point silently stopped saving until a bag opened
	# cleanly again.
	var bank: Array = CharacterData.get_bank_inventory()
	if bank != null:
		for entry in bank:
			if not (entry is Dictionary):
				continue
			if entry.get("item_id", "") == pet_id:
				return true
	return false
