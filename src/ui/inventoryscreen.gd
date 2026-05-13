# inventoryscreen.gd — controls the inventory panel UI
# attached to the root of inventory.tscn at res://scene/ui/inventory/
# emits closed signal when the close button is pressed,
# updates gold and lusions labels from the active player,
# handles right-click to use items.
extends Control
class_name InventoryScreen

signal closed

# reference to the player whose currency we display and inventory we modify
var player: Node = null

# cached reference to the inventory container — set once when found
var _container: Node = null

func _ready() -> void:
	# wire up the close button
	var close_btn := _find_close_button()
	if close_btn != null:
		close_btn.pressed.connect(_on_close_pressed)
	else:
		push_warning("InventoryScreen: closebutton not found — close button won't work")

	# cache the container reference
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
		var found := _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null

func _on_close_pressed() -> void:
	closed.emit()

# --- public API for the HUD ---

func set_player(p: Node) -> void:
	# disconnect from previous player if any — covers both currency signals
	# to keep the listener list clean when switching players (e.g. char swap)
	if player != null:
		if player.has_signal("gold_changed_signal") and player.gold_changed_signal.is_connected(_on_gold_changed):
			player.gold_changed_signal.disconnect(_on_gold_changed)
		if player.has_signal("lusions_changed_signal") and player.lusions_changed_signal.is_connected(_on_lusions_changed):
			player.lusions_changed_signal.disconnect(_on_lusions_changed)

	player = p

	# listen for live currency changes so labels update immediately
	if player != null:
		if player.has_signal("gold_changed_signal"):
			player.gold_changed_signal.connect(_on_gold_changed)
		if player.has_signal("lusions_changed_signal"):
			player.lusions_changed_signal.connect(_on_lusions_changed)

	_update_currency_labels()

func show_inventory() -> void:
	_update_currency_labels()
	visible = true

func hide_inventory() -> void:
	visible = false

# --- currency display ---

func _update_currency_labels() -> void:
	if player == null:
		return

	var gold_label := _get_label("%goldlabel")
	if gold_label != null and "gold" in player:
		gold_label.text = "Gold: %d" % int(player.gold)

	var lusions_label := _get_label("%lusionslabel")
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

# --- item use (right-click) ---

func _on_slot_right_clicked(slot: InventorySlot) -> void:
	# right-click triggers "use" on the slot's stack
	# different items have different use behaviors — dispatched by item_id
	if slot == null or slot.is_empty():
		return
	if player == null:
		push_warning("InventoryScreen: cannot use item — no player set")
		return

	use_item(slot)

func use_item(slot: InventorySlot) -> void:
	# called when the player wants to use an item.
	# dispatches to specific use behavior based on item_id.
	# add new cases here as you implement more item behaviors.
	# future improvement: dispatch by ItemData.Type instead of item_id
	# so adding a new potion doesn't require a new match case.

	if slot == null or slot.is_empty():
		return

	var stack: ItemStack = slot.stack
	var item_id: String = stack.data.item_id

	match item_id:
		"smallamountofgold":
			_use_gold_pile(slot)
		"smalllusions":
			_use_lusions_pile(slot)
		"healthpotion":
			_use_health_potion(slot)
		"manapotion":
			_use_mana_potion(slot)
		_:
			# no use behavior defined for this item
			print("InventoryScreen: no use behavior for '%s'" % item_id)

func _use_gold_pile(slot: InventorySlot) -> void:
	# convert a gold pile stack into player gold currency.
	# the value field on ItemData is the gold-per-pile rate.

	if slot == null or slot.is_empty() or player == null:
		return

	var stack: ItemStack = slot.stack
	var quantity: int = stack.quantity
	var per_pile: int = int(stack.data.value)
	var total: int = quantity * per_pile

	if player.has_method("add_gold"):
		player.add_gold(total)

	slot.clear_stack()

	if _container != null and _container.has_signal("inventory_changed"):
		_container.inventory_changed.emit()

func _use_lusions_pile(slot: InventorySlot) -> void:
	# convert a lusions pile stack into player lusions currency.
	# mirrors _use_gold_pile — value field is the lusions-per-pile rate.

	if slot == null or slot.is_empty() or player == null:
		return

	var stack: ItemStack = slot.stack
	var quantity: int = stack.quantity
	var per_pile: int = int(stack.data.value)
	var total: int = quantity * per_pile

	# add via the method so lusions_changed_signal fires and label refreshes
	if player.has_method("add_lusions"):
		player.add_lusions(total)
	elif "lusions" in player:
		# fallback for legacy player without add_lusions
		player.lusions += total
		_update_currency_labels()

	slot.clear_stack()

	if _container != null and _container.has_signal("inventory_changed"):
		_container.inventory_changed.emit()

	print("Used lusions pile: +%d lusions (now %d total)" % [total, player.lusions])

func _use_health_potion(slot: InventorySlot) -> void:
	# heal the player by the potion's restore_amount.
	# refuses ONLY if player is at exactly max hp — even 1 missing hp allows use.
	# always consumes the full potion regardless of how much was actually healed.
	# uses restore_amount on ItemData as the generic restore field that all
	# potions share — health/mana/stamina all read the same field, but the
	# use function decides which stat receives the restore.

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
	# refuses ONLY if mana is at exactly max — even 1 missing mp allows use.
	# mirrors _use_health_potion but applied to the mana stat.
	# always consumes the full potion regardless of how much was restored.

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

	# apply mana restore — prefer the dedicated method, fall back to direct
	# field assignment with clamp for backwards compatibility
	if player.has_method("restore_mana"):
		player.restore_mana(actual_restore)
	elif "mana" in player and "max_mana" in player:
		player.mana = clamp(player.mana + actual_restore, 0, player.max_mana)
	else:
		push_error("InventoryScreen: player has no mana fields")
		return

	_consume_one_from_stack(slot, stack)

func _consume_one_from_stack(slot: InventorySlot, stack: ItemStack) -> void:
	# decrements the stack by one, clearing the slot if it reaches zero.
	# extracted so all potion use functions share consistent consume behavior.
	if _container != null and _container.has_method("remove_quantity_at"):
		_container.remove_quantity_at(slot.slot_index, 1)
	else:
		# fallback if container method is missing
		stack.quantity -= 1
		if stack.quantity <= 0:
			slot.clear_stack()
		else:
			slot.refresh_display()

func _calculate_potion_restore(base: int) -> int:
	# generic restore calculation — currently returns base unchanged.
	# swap point for future modifiers:
	#   - tier multipliers (random crit-style)
	#   - skill scaling (magic skill boosts mana potions, etc.)
	#   - buff effects (alchemist's blessing)
	#   - gear bonuses (charm of greater restoration)
	# applies to all potion types since they all use the same architecture.
	# keep this signature stable so callers never change.
	return base
