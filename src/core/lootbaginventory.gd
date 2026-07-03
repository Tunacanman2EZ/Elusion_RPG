# lootbaginventory.gd — the draggable loot-bag panel. mirrors bankinventory
# but points at a specific WORLD loot bag instead of persistent account storage.
#
# double-click quick-transfer:
# double-clicking a loot slot moves that stack to the player's inventory.
# if the inventory can't fit the whole stack, the fit portion goes and the
# leftover stays in the loot bag. if inventory is completely full for that
# item type, nothing moves and a message logs to console.
extends Control


const LOOT_SIZE := 6
const LUSION_ITEM_ID := "lusions"


@onready var loot_container: Node = %lootcontainer
@onready var close_button: Button = %closebutton


var _world_bag: Node = null
var _player: Node = null
var _loading: bool = false


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
	# === DIAGNOSTIC — remove after fixing ===
	print("LOOTBAG_INV.open_for_bag: world_bag=%s player=%s contents_from_bag=%s" % [
		world_bag, player, world_bag.get_contents() if world_bag != null else "null"
	])
	# === END DIAGNOSTIC ===

	_world_bag = world_bag
	_player = player
	_loading = true
	_load_contents(world_bag.get_contents())
	_loading = false
	visible = true

	# === DIAGNOSTIC — remove after fixing ===
	print("LOOTBAG_INV.open_for_bag DONE: visible=true, container_empty=%s" % _is_container_empty())
	# === END DIAGNOSTIC ===


func _on_close_pressed() -> void:
	# === DIAGNOSTIC — remove after fixing ===
	print("LOOTBAG_INV._on_close_pressed CALLED")
	# === END DIAGNOSTIC ===
	_sync_back_to_bag()
	visible = false
	_world_bag = null


# =============================================================================
# CONTENT LOAD
# =============================================================================

func _load_contents(contents: Array) -> void:
	# === DIAGNOSTIC — remove after fixing ===
	print("LOOTBAG_INV._load_contents: received %d entries" % contents.size())
	# === END DIAGNOSTIC ===

	var resolved: Array = []
	for entry in contents:
		var item_id: String = entry.get("item_id", "")
		var qty: int = entry.get("quantity", 1)
		if item_id == "":
			continue
		var data: ItemData = ItemRegistry.get_item(item_id)
		if data == null:
			# === DIAGNOSTIC ===
			print("  ... skipping '%s' — not in ItemRegistry" % item_id)
			# === END ===
			continue
		if data.type == ItemData.Type.PET and _player_owns_pet(item_id):
			resolved.append({
				"item_id": LUSION_ITEM_ID,
				"quantity": GameConstants.DUPE_PET_LUSIONS,
			})
		else:
			resolved.append({ "item_id": item_id, "quantity": qty })

	# === DIAGNOSTIC ===
	print("LOOTBAG_INV._load_contents: resolved %d entries, calling load_save_array" % resolved.size())
	# === END ===
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
			print("LootBagInventory: inventory full — nothing moved")
			return

		loot_container.remove_quantity_at(slot.slot_index, moved)
	else:
		if not inv_container.can_add_stack(full_stack):
			print("LootBagInventory: inventory full — nothing moved")
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
	# === DIAGNOSTIC — remove after fixing ===
	print("LOOTBAG_INV._on_container_changed: _loading=%s _player=%s _world_bag=%s" % [
		_loading, _player, _world_bag
	])
	# === END DIAGNOSTIC ===

	if _loading:
		# === DIAGNOSTIC ===
		print("  ... _loading flag is true, returning early (safe)")
		# === END ===
		return
	if _player != null:
		CharacterData.save_character_state(_player)
	_sync_back_to_bag()

	var empty: bool = _is_container_empty()
	# === DIAGNOSTIC ===
	print("  ... container_empty=%s _world_bag=%s" % [empty, _world_bag])
	# === END ===

	if empty:
		# === DIAGNOSTIC ===
		print("  ... DESPAWNING — calling _world_bag.despawn_now()")
		# === END ===
		if _world_bag != null and _world_bag.has_method("despawn_now"):
			_world_bag.despawn_now()
		_world_bag = null
		visible = false


func _sync_back_to_bag() -> void:
	if _world_bag == null:
		return
	if _world_bag.has_method("set_contents"):
		_world_bag.set_contents(loot_container.to_save_array())


func _is_container_empty() -> bool:
	var arr: Array = loot_container.to_save_array()
	return arr.is_empty()


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
	var bank: Array = CharacterData.get_bank_inventory()
	if bank != null:
		for entry in bank:
			if entry.get("item_id", "") == pet_id:
				return true
	return false
