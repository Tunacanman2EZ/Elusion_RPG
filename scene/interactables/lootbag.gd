# lootbaginventory.gd — the draggable loot-bag panel. mirrors bankinventory
# but points at a specific WORLD loot bag instead of persistent account storage.
#
# grid size:
# loot bags are 6 slots (3 columns × 2 rows) — enforced in _ready via
# loot_container.resize() so the .tscn can't drift out of sync. change the
# numbers in the resize() call if you want a different shape.
#
# double-click quick-transfer:
# double-clicking a loot slot moves that stack to the player's inventory.
# if the inventory can't fit the whole stack, the fit portion goes and the
# leftover stays in the loot bag. if inventory is completely full for that
# item type, nothing moves and a message logs to console.
extends Control


# =============================================================================
# CONSTANTS
# =============================================================================

# grid dimensions for the loot container (3 × 2 = 6 slots)
const LOOT_GRID_WIDTH: int = 3
const LOOT_GRID_HEIGHT: int = 2

# item_id used when a pet drop is converted to lusions because the player
# already owns the pet (duplicate-pet compensation).
const LUSION_ITEM_ID := "lusions"


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var loot_container: Node = %lootcontainer
@onready var close_button: Button = %closebutton


# =============================================================================
# STATE
# =============================================================================

# the WORLD loot bag we're currently displaying. null when panel is closed.
var _world_bag: Node = null

# the player who opened this panel (the killer). used for ownership checks
# and to route items to the correct inventory.
var _player: Node = null

# suppresses _on_container_changed side effects (save + sync + despawn)
# during the initial content load — otherwise we'd try to save + sync
# before the bag is fully populated.
var _loading: bool = false


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# force the loot container to the intended grid size. calling resize
	# AFTER the container's own _ready lets us override whatever the .tscn
	# had — keeps grid size defined in ONE place (this script's constants).
	if loot_container != null and loot_container.has_method("resize"):
		loot_container.resize(LOOT_GRID_WIDTH, LOOT_GRID_HEIGHT)

	if close_button != null and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)

	if loot_container.has_signal("inventory_changed"):
		if not loot_container.inventory_changed.is_connected(_on_container_changed):
			loot_container.inventory_changed.connect(_on_container_changed)

	# double-click any loot slot → send stack to player inventory
	if loot_container.has_signal("slot_double_clicked"):
		if not loot_container.slot_double_clicked.is_connected(_on_slot_double_clicked):
			loot_container.slot_double_clicked.connect(_on_slot_double_clicked)

	visible = false


# =============================================================================
# OPEN / CLOSE
# =============================================================================

func open_for_bag(world_bag: Node, player: Node) -> void:
	# called by the HUD when the killer interacts with a bag on the ground.
	# stores refs, loads contents (with pet-dupe resolution), then shows panel.
	_world_bag = world_bag
	_player = player
	_loading = true
	_load_contents(world_bag.get_contents())
	_loading = false
	visible = true


func _on_close_pressed() -> void:
	# manual close via X button. sync remaining contents back to the world
	# bag first so leftovers persist until the bag despawns naturally.
	_sync_back_to_bag()
	visible = false
	_world_bag = null


# =============================================================================
# CONTENT LOAD
# =============================================================================

func _load_contents(contents: Array) -> void:
	# hydrate bag contents into the loot container.
	# pet-owner check: if the player already owns this pet, swap it out for
	# a lusions pile (dupe compensation) so pets never become tradable clutter.
	var resolved: Array = []
	for entry in contents:
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
	# transfer the stack from this loot bag slot to the player's inventory.
	# partial fit is honored — if the inventory can only hold part of the
	# stack, the rest stays in the loot bag.
	if _player == null or slot == null or slot.is_empty():
		return

	var inv_container: Node = _get_player_inventory_container()
	if inv_container == null:
		push_warning("LootBagInventory: player inventory not found — can't transfer")
		return

	var full_stack: ItemStack = slot.stack.duplicate_stack()

	# try partial fit — returns how many units DID NOT fit
	if inv_container.has_method("add_stack_partial"):
		var leftover: int = inv_container.add_stack_partial(full_stack)
		var moved: int = slot.stack.quantity - leftover

		if moved <= 0:
			print("LootBagInventory: inventory full — nothing moved")
			return

		# remove the moved quantity from the loot slot.
		# _on_container_changed handles save + sync + empty-check.
		loot_container.remove_quantity_at(slot.slot_index, moved)
	else:
		# fallback if add_stack_partial isn't available — all-or-nothing
		if not inv_container.can_add_stack(full_stack):
			print("LootBagInventory: inventory full — nothing moved")
			return
		if inv_container.add_stack(full_stack):
			loot_container.remove_quantity_at(slot.slot_index, full_stack.quantity)


func _get_player_inventory_container() -> Node:
	# resolve the player's inventory container via the HUD's inventory screen.
	# null-safe walk in case any link in the chain is missing.
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
	# fired on every mutation to the loot container. skip during initial
	# load to avoid saving/syncing before the bag is populated. otherwise:
	# save player state atomically, sync leftovers back to the world bag,
	# and despawn the bag + close the panel if it's now empty.
	if _loading:
		return
	if _player != null:
		CharacterData.save_character_state(_player)
	_sync_back_to_bag()
	if _is_container_empty():
		if _world_bag != null and _world_bag.has_method("despawn_now"):
			_world_bag.despawn_now()
		_world_bag = null
		visible = false


func _sync_back_to_bag() -> void:
	# push the panel's current contents back to the world bag so leftovers
	# persist there until the bag despawns (from timer or emptying).
	if _world_bag == null:
		return
	if _world_bag.has_method("set_contents"):
		_world_bag.set_contents(loot_container.to_save_array())


func _is_container_empty() -> bool:
	# empty test — checks the serialized array which is smaller and cheaper
	# to walk than the slot array itself.
	var arr: Array = loot_container.to_save_array()
	return arr.is_empty()


# =============================================================================
# PET OWNERSHIP CHECK
# =============================================================================

func _player_owns_pet(pet_id: String) -> bool:
	# check whether the player already owns this pet (in inventory OR bank).
	# used to swap duplicate pet drops for lusions instead — pets shouldn't
	# accumulate as tradeable items once collected.
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
