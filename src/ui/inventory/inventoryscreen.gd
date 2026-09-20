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

# How long to wait on /api/character/consume. Short on purpose: this is between
# the player pressing a key and their health bar moving, and a potion that takes
# six seconds to answer has already failed even if it eventually says yes.
const CONSUME_TIMEOUT := 4.0

# reference to the player whose currency we display and inventory we modify
var player: Node = null

# cached reference to the inventory container — set once when found
var _container: Node = null

# One consume request at a time. See _use_consumable() for why a repeating
# hotbar key makes this necessary rather than tidy.
var _consuming: bool = false


func _notify(message: String) -> void:
	# one funnel for every player-facing refusal in this screen. has_method()
	# rather than a direct call because `player` is typed Node and is null
	# until set_player() runs — an unopened or detached screen must not crash
	# on a refusal it can't display.
	if player != null and player.has_method("show_notice"):
		player.show_notice(message)


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

	# ONE GATE, AND IT HAS TO BE HERE rather than inside _use_consumable().
	# The hotbar has no use path of its own: hotbar.gd::_use_slot() emits
	# item_used, characterhud.gd::_on_hotbar_item_used() finds the slot and
	# calls straight back into this function. A check further down would be one
	# a hotbar key walks past, which is the difference between a gate and a
	# gate-shaped decoration.
	if not _meets_requirements(data):
		return

	match data.type:
		ItemData.Type.CONSUMABLE:
			# AWAITED, because this one asks the server first now. Callers that
			# do not await still work - they simply do not block - and neither
			# of the two callers needs the answer: the inventory click and
			# hotbar.gd both fire and forget.
			await _use_consumable(slot)
		ItemData.Type.CURRENCY:
			_use_currency_pile(slot)
		ItemData.Type.PET:
			_use_pet(slot)
		ItemData.Type.WEAPON, ItemData.Type.ARMOR:
			_equip_item(data)
		_:
			# push_warning, not print, and not debug-gated: reaching this
			# branch means an item exists that the game has no idea how to
			# use. The player meets that as a click that does nothing.
			push_warning("InventoryScreen: '%s' has no use behavior for its item type" % data.item_id)


# =============================================================================
# ITEM USE — EQUIPMENT
# =============================================================================

func _equip_item(data: ItemData) -> void:
	# RIGHT-CLICK PUTS IT ON, which is what every other item type in this match
	# already does with a right-click and what gear did not do at all — a sword
	# in the backpack was the one thing you could click and have nothing
	# happen. It also means a full eight-piece kit is eight clicks rather than
	# eight drags across the screen.
	#
	# NOTHING MOVES. The item stays in the cell it was clicked in; equipping
	# writes an item_id into player.equipped and no more. See player.gd's note
	# on `equipped` for why, and expect the cell to keep its icon — that is
	# correct, not a failed click.
	#
	# THE RULE IS CharacterData's, not this panel's. The same call the paper
	# doll makes when something is dropped on a square, so the two gestures
	# cannot drift into two behaviours.
	if player == null:
		return

	# WHY THIS ASKS BEFORE IT TELLS, when equip_item() would return false
	# anyway: the refusal carries a reason, and the player deserves it. The
	# character-level and skill gates have already been checked above by
	# _meets_requirements(); this is the third gate, the one only gear has.
	if player.has_method("equip_check"):
		var verdict: Dictionary = player.equip_check(data.item_id)
		if not verdict.get("ok", false):
			match str(verdict.get("reason", "")):
				"class":
					var allowed: Array = verdict.get("allowed", [])
					var names: PackedStringArray = PackedStringArray()
					for class_id in allowed:
						names.append(String(class_id).capitalize())
					_notify("Only %s can wear that." % ", ".join(names))
				"level":
					_notify("Requires level %d." % int(verdict.get("needs", 1)))
				_:
					_notify("That cannot be equipped.")
			return

	if not CharacterData.equip_item(player, data.item_id):
		_notify("That cannot be equipped.")
		return

	# The doll is a view of player.equipped and has just gone stale. Found by
	# group rather than reached through the HUD, the same way the tooltip is —
	# and skipped without complaint when it is not open, because equipping is
	# a game action and should not need a panel to be on screen.
	for panel in get_tree().get_nodes_in_group("equipmentpanel"):
		if panel.has_method("refresh"):
			panel.refresh()


# =============================================================================
# ITEM USE — REQUIREMENTS
# =============================================================================

func _meets_requirements(data: ItemData) -> bool:
	# NO LONGER THE ONLY GATE, and this comment used to say what it was waiting
	# for: "it becomes load-bearing the day trade exists". Trade exists, and the
	# rule moved — POST /api/character/consume checks these same two fields
	# against the character the SERVER owns, and destroys the item itself.
	#
	# SO WHY IS THIS STILL HERE. Because it is the fast answer. The server's
	# refusal costs a round trip; this one is instant, and a player who is four
	# levels short of a potion should be told so the moment they click rather
	# than a fifth of a second later. A patched client skipping it gains
	# nothing now — it just reaches a 403 the long way round.
	#
	# The order is the point: the client refusing is a courtesy, the server
	# refusing is the rule.
	if data == null:
		return true
	if player == null:
		# Nothing to measure against. Refusing here would break every context
		# that opens this screen before set_player() runs; the handlers below
		# all null-check `player` again before touching it.
		return true

	# BOTH CHECKED, character level first, because an item may carry either or
	# both and the player should be told about the one that is actually in the
	# way. Order only decides which message shows when both fail.
	if not _meets_character_level(data):
		return false
	return _meets_skill_level(data)


func _meets_character_level(data: ItemData) -> bool:
	var needed: int = int(data.required_level)
	if needed <= 1:
		return true

	var have: int = int(player.level) if "level" in player else 1
	if have >= needed:
		return true

	_notify("Requires level %d." % needed)
	return false


func _meets_skill_level(data: ItemData) -> bool:
	var skill: String = String(data.required_skill).strip_edges()
	if skill == "":
		return true

	var needed: int = int(data.required_skill_level)
	if needed <= 1:
		return true

	# A skill name the player has no property for is a typo in the .tres. LOUD
	# AND PERMISSIVE: the item stays usable, because refusing would take a
	# working item away from every player over an editor slip, but the log says
	# exactly which item and which name. Silently passing with no error is the
	# one outcome to avoid — that is a gate that has quietly stopped gating.
	if not (skill in player):
		push_error("InventoryScreen: '%s' requires unknown skill '%s' — check its .tres" % [
			data.item_id, skill,
		])
		return true

	if int(player.get(skill)) >= needed:
		return true

	_notify("Requires %s level %d." % [skill.capitalize(), needed])
	return false


# =============================================================================
# ITEM USE — CONSUMABLES
# =============================================================================

func _use_consumable(slot: InventorySlot) -> void:
	# THE SERVER DESTROYS THE POTION; THIS APPLIES WHAT IT DID.
	#
	# Everything below the await used to be the whole function, and that was the
	# finding: a potion was drunk entirely on this machine, and the server met
	# it as an inventory sync one item shorter - which is indistinguishable from
	# an honest use, so it was accepted. The requirement check above was a
	# courtesy a patched client skipped.
	#
	# ORDER MATTERS AND IS THE FIDDLY PART. Every local reason not to drink has
	# to be settled BEFORE the request, because past it the item is gone from
	# the server's rows: bailing after a 200 would destroy a potion and heal
	# nobody. That is what _consumable_blocked_reason() is for.
	var data: ItemData = slot.stack.data

	var blocked: String = _consumable_blocked_reason(data)
	if blocked != "":
		_notify(blocked)
		return

	# ONE AT A TIME. Holding a hotbar key repeats, and without this each repeat
	# is another request against a stack the earlier ones are still spending -
	# the client would ask to drink four potions it has one of, and the server
	# would answer 404 three times having destroyed one.
	if _consuming:
		return
	_consuming = true
	var res: Dictionary = await Api.post("/api/character/consume", {
		"slot": CharacterData.active_character_index,
		"item_id": data.item_id,
	}, CONSUME_TIMEOUT)
	_consuming = false

	# PAST AN AWAIT. Logout frees this panel and a ladder changes the scene,
	# either of which can happen while the request is in flight. Same guard and
	# same reason as shopinventory.gd's catalogue load.
	if not is_instance_valid(self) or not is_inside_tree():
		return

	if not res.get("ok", false):
		# api.gd has already turned the response into a sentence, and the
		# server's own refusals ("You need level 22.") are worth showing
		# verbatim - they say the thing the player needs to hear.
		_notify(str(res.get("error", "That cannot be used.")))
		return

	# The slot can have changed under us across the await - a drag, a sync, a
	# different item in that cell. Re-read rather than trusting the capture.
	if slot == null or slot.is_empty() or slot.stack.data != data:
		return

	# route a consumable's restore_amount to the stat named by restore_target.
	# a new potion just needs Type=CONSUMABLE + the right restore_target set.
	match data.restore_target:
		ItemData.RestoreTarget.HP:
			_use_health_potion(slot)
		ItemData.RestoreTarget.MANA:
			_use_mana_potion(slot)
		ItemData.RestoreTarget.STAMINA:
			_use_stamina_potion(slot)
		_:
			# same reasoning: a consumable with no restore_target is a .tres
			# that was filled in incompletely, and it fails silently at the
			# moment the player tries to drink it.
			push_warning("InventoryScreen: consumable '%s' has no restore_target set" % data.item_id)


func _consumable_blocked_reason(data: ItemData) -> String:
	"""Every local reason not to drink this, settled before the server is asked.
	Returns "" when nothing is in the way.

	THESE ARE THE SAME CHECKS the three _use_*_potion() handlers make, hoisted
	so they run on the near side of the request. They stay in the handlers too:
	this is not the only way in during a refactor, and a handler that trusts a
	caller to have checked is a handler one call site away from being wrong."""
	if data == null or player == null:
		return "Nothing to use that on."

	if int(data.restore_amount) <= 0:
		push_warning("InventoryScreen: %s has no restore_amount set" % data.item_id)
		return "That does nothing."

	# "Already full" is the common one, and it is worth answering here rather
	# than spending a round trip and a potion to be told no.
	match data.restore_target:
		ItemData.RestoreTarget.HP:
			if "hp" in player and "max_hp" in player and player.hp >= player.max_hp:
				return "Health already full"
		ItemData.RestoreTarget.MANA:
			if "mana" in player and "max_mana" in player and player.mana >= player.max_mana:
				return "Mana already full"
		ItemData.RestoreTarget.STAMINA:
			if "stamina" in player and "max_stamina" in player and player.stamina >= player.max_stamina:
				return "Stamina already full"
		_:
			push_warning("InventoryScreen: consumable '%s' has no restore_target set" % data.item_id)
			return "That does nothing."

	return ""


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
# ITEM USE — PETS
# =============================================================================

func _use_pet(slot: InventorySlot) -> void:
	# NEW: summon the companion this item represents — or put it away if it's
	# the one already out, so a single item is both the summon and the dismiss.
	#
	# DELIBERATELY DOES NOT CONSUME THE ITEM. a pet is a 1/216 drop, and
	# ItemData carries pet_source_name specifically for a future pet-collection
	# screen — both say a pet is a permanent collectible, not a single-use
	# scroll. consuming it would make swapping pets a one-way door: put the
	# sniper away to try the mage and the sniper is gone forever.
	#
	# if you'd rather they WERE consumable, add
	#     _consume_one_from_stack(slot, slot.stack)
	# after a successful summon below. nothing else has to change.
	if slot == null or slot.is_empty() or player == null:
		return

	var data: ItemData = slot.stack.data

	if not player.has_method("summon_pet"):
		push_error("InventoryScreen: player has no summon_pet() method")
		return

	# already out? this is the dismiss. checked against active_pet_id rather
	# than a node lookup because that string is the thing CharacterData
	# persists — the node is just its current visible form.
	if "active_pet_id" in player and player.active_pet_id == data.item_id:
		if player.has_method("dismiss_pet"):
			player.dismiss_pet()
			if OS.is_debug_build():
				print("[PET]  put away '%s'" % data.item_id)
		return

	player.summon_pet(data.item_id)


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

	Audio.play("coin")
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

	if OS.is_debug_build():
		print("[ITEM] lusions pile: +%d (now %d)" % [total, player.lusions])


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
			# routed to the player, not the console. These three refusals
			# used to print, which from the player's side is no feedback at
			# all — the click did nothing and said nothing. show_notice()
			# de-duplicates, so double-clicking a potion shows one label.
			_notify("Health already full")
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
			_notify("Mana already full")
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
			_notify("Stamina already full")
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
	# The shared funnel for all three potion types, which is why the sound
	# lives here rather than three times over. The pet path deliberately does
	# not consume and so never reaches this.
	Audio.play("potion")

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


# =============================================================================
# DRAG AND DROP — PANEL BACKGROUND
# =============================================================================
# Same reasoning as BankInventory's copy of this: accepting a drag anywhere on
# the window stops Godot flipping the pointer to the forbidden cursor over the
# parts of the panel that aren't slots.
#
# Accept and do nothing. The drag carries a duplicate of the stack and the
# source slot is only cleared by whoever actually takes the item, so a drop on
# panel furniture leaves everything exactly where it started.

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY \
		and data.has("stack") \
		and data.has("source_slot")


func _drop_data(_at_position: Vector2, _data: Variant) -> void:
	pass
