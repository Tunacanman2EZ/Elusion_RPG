# inventoryscreen.gd — controls the inventory panel UI.
# attached to the root of inventory.tscn at res://scene/ui/inventory/.
#
# responsibilities:
# - emits the `closed` signal when the X button is pressed
# - keeps gold and lusions labels in sync with the active player
# - dispatches right-click → "use item" by ItemData.Type
#
# item-use architecture (type-dispatch):
# use_item() dispatches by ItemData.Type, not item_id. consumables route to
# the stat named by restore_target; currency piles convert to their pool.
# adding a new potion or currency needs NO code change here — just set the
# item's Type (+ restore_target for consumables) in the inspector.
extends Control
class_name InventoryScreen


# =============================================================================
# SIGNALS
# =============================================================================

signal closed


# =============================================================================
# STATE
# =============================================================================

# reference to the player whose currency we display and inventory we modify
var player: Node = null

# cached reference to the inventory container — set once when found
var _container: Node = null


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_wire_close_button()
	_wire_inventory_container()


# =============================================================================
# INITIALIZATION HELPERS
# =============================================================================

func _wire_close_button() -> void:
	var close_btn: Button = _find_close_button()
	if close_btn != null:
		close_btn.pressed.connect(_on_close_pressed)
	else:
		push_warning("InventoryScreen: closebutton not found — close button won't work")


func _wire_inventory_container() -> void:
	if has_node("%inventorycontainer"):
		_container = get_node("%inventorycontainer")
		_container.slot_right_clicked.connect(_on_slot_right_clicked)
	else:
		push_warning("InventoryScreen: inventorycontainer not found")


func _find_close_button() -> Button:
	if has_node("%closebutton"):
		return get_node("%closebutton") as Button
	return _find_node_by_name(self, "closebutton") as Button


func _find_node_by_name(start: Node, target_name: String) -> Node:
	if start.name == target_name:
		return start
	for child in start.get_children():
		var found: Node = _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null


# =============================================================================
# PUBLIC API
# =============================================================================

func set_player(p: Node) -> void:
	_disconnect_player_signals()
	player = p
	_connect_player_signals()
	_update_currency_labels()


func show_inventory() -> void:
	_update_currency_labels()
	visible = true


func hide_inventory() -> void:
	visible = false


# =============================================================================
# SIGNAL WIRING (PLAYER)
# =============================================================================

func _connect_player_signals() -> void:
	if player == null:
		return
	if player.has_signal("gold_changed_signal"):
		player.gold_changed_signal.connect(_on_gold_changed)
	if player.has_signal("lusions_changed_signal"):
		player.lusions_changed_signal.connect(_on_lusions_changed)


func _disconnect_player_signals() -> void:
	if player == null:
		return
	if player.has_signal("gold_changed_signal") and player.gold_changed_signal.is_connected(_on_gold_changed):
		player.gold_changed_signal.disconnect(_on_gold_changed)
	if player.has_signal("lusions_changed_signal") and player.lusions_changed_signal.is_connected(_on_lusions_changed):
		player.lusions_changed_signal.disconnect(_on_lusions_changed)


# =============================================================================
# CURRENCY DISPLAY
# =============================================================================

func _update_currency_labels() -> void:
	if player == null:
		return

	var gold_label: Label = _get_label("%goldlabel")
	if gold_label != null and "gold" in player:
		gold_label.text = "Gold: %d" % int(player.gold)

	var lusions_label: Label = _get_label("%lusionslabel")
	if lusions_label != null and "lusions" in player:
		lusions_label.text = "Lusions: %d" % int(player.lusions)


func _get_label(unique_path: String) -> Label:
	if has_node(unique_path):
		return get_node(unique_path) as Label
	return null


func _on_gold_changed(_amount: int) -> void:
	_update_currency_labels()


func _on_lusions_changed(_amount: int) -> void:
	_update_currency_labels()


func _on_close_pressed() -> void:
	closed.emit()


# =============================================================================
# ITEM USE — DISPATCH (by Type)
# =============================================================================

func _on_slot_right_clicked(slot: InventorySlot) -> void:
	# right-click triggers "use" on the slot's stack. no-op if slot is empty
	# or no player is set.
	if slot == null or slot.is_empty():
		return
	if player == null:
		push_warning("InventoryScreen: cannot use item — no player set")
		return
	use_item(slot)


func use_item(slot: InventorySlot) -> void:
	# dispatch by ItemData.Type so new items work without an item_id case.
	# consumables route by restore_target; currency piles convert to a pool.
	if slot == null or slot.is_empty():
		return

	var data: ItemData = slot.stack.data

	match data.type:
		ItemData.Type.CONSUMABLE:
			_use_consumable(slot)
		ItemData.Type.CURRENCY:
			_use_currency_pile(slot)
		_:
			print("InventoryScreen: no use behavior for type of '%s'" % data.item_id)


func _use_consumable(slot: InventorySlot) -> void:
	# route a consumable's restore_amount to the stat named by restore_target.
	# a new potion just needs Type=CONSUMABLE + the right restore_target set.
	var data: ItemData = slot.stack.data
	match data.restore_target:
		ItemData.RestoreTarget.HP:
			_use_health_potion(slot)
		ItemData.RestoreTarget.MANA:
			_use_mana_potion(slot)
		ItemData.RestoreTarget.STAMINA:
			_use_stamina_potion(slot)
		_:
			print("InventoryScreen: consumable '%s' has no restore_target set" % data.item_id)


func _use_currency_pile(slot: InventorySlot) -> void:
	# route currency to the correct pool. item_id containing "lusion" feeds the
	# lusion pool; everything else feeds gold. (a dedicated currency_type field
	# on ItemData would be cleaner if you add more currencies later.)
	var data: ItemData = slot.stack.data
	if "lusion" in data.item_id.to_lower():
		_use_lusions_pile(slot)
	else:
		_use_gold_pile(slot)


# =============================================================================
# ITEM USE — CURRENCY PILES
# =============================================================================

func _use_gold_pile(slot: InventorySlot) -> void:
	# convert a gold pile stack into player gold currency.
	# value field is the gold-per-pile rate, so a stack of 5 at value=10 = 50.
	if slot == null or slot.is_empty() or player == null:
		return

	var stack: ItemStack = slot.stack
	var total: int = stack.quantity * int(stack.data.value)

	if player.has_method("add_gold"):
		player.add_gold(total)

	slot.clear_stack()
	_emit_container_changed()


func _use_lusions_pile(slot: InventorySlot) -> void:
	# convert a lusions pile stack into player lusions currency.
	# mirrors _use_gold_pile — value field is the lusions-per-pile rate.
	if slot == null or slot.is_empty() or player == null:
		return

	var stack: ItemStack = slot.stack
	var total: int = stack.quantity * int(stack.data.value)

	if player.has_method("add_lusions"):
		player.add_lusions(total)
	elif "lusions" in player:
		player.lusions += total
		_update_currency_labels()

	slot.clear_stack()
	_emit_container_changed()

	print("Used lusions pile: +%d lusions (now %d total)" % [total, player.lusions])


# =============================================================================
# ITEM USE — POTIONS
# =============================================================================

func _use_health_potion(slot: InventorySlot) -> void:
	# heal the player by the potion's restore_amount.
	# refuses ONLY if HP is at exactly max. consumes one on use.
	if slot == null or slot.is_empty() or player == null:
		return

	if "hp" in player and "max_hp" in player:
		if player.hp >= player.max_hp:
			print("Cannot use potion: HP is already full")
			return

	var stack: ItemStack = slot.stack
	var base_restore: int = int(stack.data.restore_amount)
	if base_restore <= 0:
		push_warning("InventoryScreen: %s has no restore_amount set" % stack.data.item_id)
		return

	var actual_restore: int = _calculate_potion_restore(base_restore)

	if player.has_method("heal"):
		player.heal(actual_restore)
	else:
		push_error("InventoryScreen: player has no heal() method")
		return

	_consume_one_from_stack(slot, stack)


func _use_mana_potion(slot: InventorySlot) -> void:
	# restore the player's mana by the potion's restore_amount.
	# refuses ONLY if mana is at exactly max. consumes one on use.
	if slot == null or slot.is_empty() or player == null:
		return

	if "mana" in player and "max_mana" in player:
		if player.mana >= player.max_mana:
			print("Cannot use potion: mana is already full")
			return

	var stack: ItemStack = slot.stack
	var base_restore: int = int(stack.data.restore_amount)
	if base_restore <= 0:
		push_warning("InventoryScreen: %s has no restore_amount set" % stack.data.item_id)
		return

	var actual_restore: int = _calculate_potion_restore(base_restore)

	if player.has_method("restore_mana"):
		player.restore_mana(actual_restore)
	elif "mana" in player and "max_mana" in player:
		player.mana = clamp(player.mana + actual_restore, 0, player.max_mana)
	else:
		push_error("InventoryScreen: player has no mana fields")
		return

	_consume_one_from_stack(slot, stack)


func _use_stamina_potion(slot: InventorySlot) -> void:
	# restore the player's stamina by the potion's restore_amount.
	# refuses ONLY if stamina is at exactly max. consumes one on use.
	if slot == null or slot.is_empty() or player == null:
		return

	if "stamina" in player and "max_stamina" in player:
		if player.stamina >= player.max_stamina:
			print("Cannot use potion: stamina is already full")
			return

	var stack: ItemStack = slot.stack
	var base_restore: int = int(stack.data.restore_amount)
	if base_restore <= 0:
		push_warning("InventoryScreen: %s has no restore_amount set" % stack.data.item_id)
		return

	var actual_restore: int = _calculate_potion_restore(base_restore)

	if "stamina" in player and "max_stamina" in player:
		player.stamina = clamp(player.stamina + actual_restore, 0, player.max_stamina)
	else:
		push_error("InventoryScreen: player has no stamina fields")
		return

	_consume_one_from_stack(slot, stack)


# =============================================================================
# ITEM USE — SHARED HELPERS
# =============================================================================

func _consume_one_from_stack(slot: InventorySlot, stack: ItemStack) -> void:
	if _container != null and _container.has_method("remove_quantity_at"):
		_container.remove_quantity_at(slot.slot_index, 1)
		return

	stack.quantity -= 1
	if stack.quantity <= 0:
		slot.clear_stack()
	else:
		slot.refresh_display()


func _emit_container_changed() -> void:
	if _container != null and _container.has_signal("inventory_changed"):
		_container.inventory_changed.emit()


func _calculate_potion_restore(base: int) -> int:
	# generic restore calculation — currently returns base unchanged.
	# swap-point for future modifiers (tier multipliers, skill scaling, buffs).
	return base
