# lootbaginventory.gd — the draggable loot-bag panel.
#
# THIS PANEL ASKS. IT NO LONGER TELLS.
# ------------------------------------
# It used to move items itself: double-click took the stack out of the loot
# container and put it in the player's inventory, right there on the player's
# machine, and the next save simply told the server what was now being carried.
# The server had rolled the loot and then had no idea what happened to it.
#
# Now the bag's real contents are rows on the server (loot_bags /
# loot_bag_items), this panel renders a copy, and taking something is
#
#     POST /api/loot/take {bag_id, position}
#
# which checks the bag is yours, that it still holds that cell, and moves the
# item into your backpack or your balance. What comes back is what happened, and
# that is what gets applied here — including the gold and lusion TOTALS rather
# than the amounts, so a response this client misses is corrected by the next
# one it gets instead of being lost on the following save.
#
# POSITION IS THE GRID CELL, ON BOTH SIDES
# ----------------------------------------
# InventoryContainer.load_save_array() writes index i into slot i and reads a
# null entry as an empty cell, so handing it a position-aligned array makes
# slot_index the server's position with no map to keep in sync. That is why
# _load_contents() below pads to LOOT_SIZE and assigns by index instead of
# appending: the old version skipped entries it could not resolve, which
# silently shifted everything after them one cell to the left.
#
# DRAGGING OUT IS BLOCKED, AND THAT IS THE POINT
# ----------------------------------------------
# A drag moves a stack between containers synchronously, with no request. Left
# enabled it would be a duplication bug the moment the server owned the bag:
# drag the potion into your backpack, then double-click the same cell and be
# handed it again, because the server was never told about the drag. So this
# panel's slots are marked "lootbag" in open_for_bag() and InventorySlot refuses
# to start a drag from one. Double-click is how items leave a bag.
#
# AUTO-CLOSE ON DISTANCE:
# lootbag.gd emits player_left_range when the player who has this panel open
# walks out of its Area2D. we connect to that signal in open_for_bag() and route
# it straight into _on_close_pressed() — the exact same close path the X button
# uses — so there's only ever one way this panel actually closes, not two
# divergent ones. the connection is torn down in _disconnect_world_bag_signal(),
# called both when closing normally and before wiring a new bag, so a stale
# connection to a previous (possibly despawned) bag can never fire against
# whatever bag the panel is currently pointed at.
extends Control


const LOOT_SIZE := 6
const LUSION_ITEM_ID := "lusions"

# Matches Combat.KILL_TIMEOUT's reasoning. A take is a request the player made
# and is watching for, so it earns more patience than a background probe — but
# not the full ten seconds, because ten seconds of a frozen loot panel reads as
# a broken game rather than a slow one.
const TAKE_TIMEOUT := 4.0


@onready var loot_container: Node = %lootcontainer
@onready var close_button: Button = %closebutton


var _world_bag: Node = null
var _player: Node = null
var _loading: bool = false

# The server's id for the bag this panel is currently pointed at.
var _bag_id: String = ""

# One take at a time. A double-click on a second cell while the first request is
# still out would be two claims against a bag neither of them has seen the state
# of — and the second would be applied to a grid that is about to be redrawn.
var _taking: bool = false


func _notify(message: String) -> void:
	# mirrors inventoryscreen.gd's funnel. _player is whoever opened this bag
	# (set by open_for_bag), and it is null whenever the panel is closed.
	if is_instance_valid(_player) and _player.has_method("show_notice"):
		_player.show_notice(message)


func _notify_player(player: Node, message: String) -> void:
	# Same thing against a CAPTURED reference rather than _player — used after
	# an await, where the panel may already have moved to another bag or closed.
	# The caller must have collapsed a freed reference to null first: GDScript
	# checks argument types at the CALL boundary, so a freed object fails before
	# this function's body gets a turn. Same trap as combat.gd's _notify().
	if is_instance_valid(player) and player.has_method("show_notice"):
		player.show_notice(message)


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
	_taking = false

	_bag_id = str(world_bag.get_bag_id()) if world_bag.has_method("get_bag_id") else ""
	if _bag_id == "":
		# Nothing here works without it, and the failure is worth naming: a bag
		# the server never registered refuses every take, and the player
		# deserves better than clicking at it and wondering.
		push_warning("LootBagInventory: bag has no server id — every take will be refused")

	_loading = true
	_load_contents(world_bag.get_contents())
	_loading = false

	# EVERY SLOT IN THIS PANEL IS A LOOT SLOT, and InventorySlot refuses to start
	# a drag from one — see the header. Done here rather than in the scene
	# because the slots are instantiated at runtime by InventoryContainer.
	if loot_container.has_method("set_slot_type"):
		loot_container.set_slot_type("lootbag")

	visible = true

	# snap the panel's size to its real content (header + 6-slot grid) instead
	# of whatever fixed size was last set in the editor. only works correctly
	# now that lootscroll (a ScrollContainer) has been removed from the
	# hierarchy — ScrollContainers don't propagate their child's actual size
	# upward, which is what caused the dead space below the grid. called after
	# visible = true since Godot needs the control to be visible to compute an
	# accurate combined minimum size.
	reset_size()

	# listen for the bag telling us the player walked out of range.
	if _world_bag != null and _world_bag.has_signal("player_left_range"):
		if not _world_bag.player_left_range.is_connected(_on_close_pressed):
			_world_bag.player_left_range.connect(_on_close_pressed)


func _on_close_pressed() -> void:
	_mirror_to_bag()

	# tell the bag we're closed, regardless of why (X button, walked away,
	# etc.) — is_instance_valid guards against the bag already being freed
	# (e.g. this fires as part of the empty-bag despawn path too, where the bag
	# is gone or about to be). see notify_panel_closed() in lootbag.gd for why
	# this matters beyond the despawn-pause: it's also the only thing that
	# resets _is_open when closing via X while still standing in range, since
	# that path never triggers body_exited.
	if is_instance_valid(_world_bag) and _world_bag.has_method("notify_panel_closed"):
		_world_bag.notify_panel_closed()

	_disconnect_world_bag_signal()
	visible = false
	_world_bag = null
	_bag_id = ""


func _disconnect_world_bag_signal() -> void:
	# shared cleanup so the player_left_range connection never outlives its
	# usefulness — called before wiring a new bag AND when closing.
	if _world_bag != null and _world_bag.has_signal("player_left_range"):
		if _world_bag.player_left_range.is_connected(_on_close_pressed):
			_world_bag.player_left_range.disconnect(_on_close_pressed)


# =============================================================================
# CONTENT LOAD
# =============================================================================

func _load_contents(contents: Array) -> void:
	# INDEX IN, INDEX OUT. resize() fills with null and load_save_array() reads
	# a null as an empty cell, so every entry lands in the slot whose index is
	# the server's position for it.
	#
	# The previous version appended to a list and skipped anything it could not
	# resolve, which moved every later item one cell to the left. That was
	# harmless while the client owned the bag. Now the cell number is what gets
	# sent, so it would be the player clicking one item and being handed a
	# different one.
	var resolved: Array = []
	resolved.resize(LOOT_SIZE)

	for i in range(mini(contents.size(), LOOT_SIZE)):
		var entry = contents[i]
		if not (entry is Dictionary):
			continue

		var item_id: String = str(entry.get("item_id", ""))
		if item_id == "":
			continue

		var data: ItemData = ItemRegistry.get_item(item_id)
		if data == null:
			# An item the server knows about and this build does not. Leaving
			# the cell empty is the safe read: the player cannot click what they
			# cannot see, so they cannot ask for something this client would
			# have no way to render once it arrived.
			push_warning("LootBagInventory: no ItemData for '%s' — cell %d left empty" % [item_id, i])
			continue

		if data.type == ItemData.Type.PET and _player_owns_pet(item_id):
			# COSMETIC ONLY. The server makes this same call for real, in
			# /api/loot/take, against rows it owns rather than a local copy.
			# This just means the player sees lusions sitting in the bag instead
			# of a pet that turns into lusions when clicked.
			#
			# If the two ever disagree — the pet was banked or sold between
			# opening the bag and taking from it — the server's answer is what
			# happens, and the notice says what was actually granted.
			resolved[i] = {
				"item_id": LUSION_ITEM_ID,
				"quantity": GameConstants.DUPE_PET_LUSIONS,
			}
		else:
			resolved[i] = {
				"item_id": item_id,
				"quantity": maxi(int(entry.get("quantity", 1)), 1),
			}

	if contents.size() > LOOT_SIZE:
		# The server caps a bag at LOOT_BAG_CAPACITY for exactly this reason. If
		# this ever fires, the two capacities have drifted apart and there is
		# loot sitting behind a cell the player has no way to reach.
		push_warning("LootBagInventory: bag has %d cells, the panel shows %d" % [
			contents.size(), LOOT_SIZE
		])

	loot_container.load_save_array(resolved)


# =============================================================================
# DOUBLE-CLICK → ASK THE SERVER FOR IT
# =============================================================================

func _on_slot_double_clicked(slot: InventorySlot) -> void:
	if slot == null or slot.is_empty():
		return

	if _taking:
		# Silent. The player double-clicked twice inside the time one request
		# takes, which is not a mistake worth a message — and the request
		# already out is about to redraw the grid underneath them anyway.
		return

	if _bag_id == "":
		# NO LOCAL FALLBACK, deliberately. Handing the item over because the
		# server could not be asked is the whole exploit: a client that can
		# produce loot by making a request fail does not need permission for
		# anything.
		_notify("This bag isn't registered with the server.")
		return

	if not Api.is_logged_in():
		_notify("Not connected — can't take that.")
		return

	# CAPTURED BEFORE THE AWAIT, ALL OF IT.
	#
	# Four seconds is long enough to close the panel, walk away, open a
	# different bag, or die. _bag_id, _world_bag and _player can all be
	# something else by the time the response lands — and the item has already
	# moved on the server by then, so the grant has to be applied to the player
	# who asked for it rather than to whoever _player happens to be now.
	var bag_id: String = _bag_id
	var cell: int = slot.slot_index
	var player: Node = _player if is_instance_valid(_player) else null

	_taking = true
	var res: Dictionary = await Api.post("/api/loot/take", {
		"bag_id": bag_id,
		"position": cell,
	}, TAKE_TIMEOUT)
	_taking = false

	# Re-collapse: valid a moment ago is not valid now.
	player = player if is_instance_valid(player) else null

	if not res.get("ok", false):
		_handle_refusal(res, player, bag_id, cell)
		return

	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}

	_apply_grant(player, data)
	_clear_cell(bag_id, cell)

	if bool(data.get("bag_empty", false)):
		_close_emptied_bag(bag_id)

	if OS.is_debug_build():
		print("[LOOT] took cell %d — %d x %s → %s" % [
			cell,
			int(data.get("granted_quantity", 0)),
			str(data.get("granted_item_id", "")),
			str(data.get("credited", "")),
		])


func _apply_grant(player: Node, data: Dictionary) -> void:
	# player must already be valid-or-null. See the capture in the caller.
	if player == null:
		# The item is on the server and this client is no longer in a position
		# to show it. The next load reads the server's rows, so nothing is
		# lost — it just does not appear until then.
		return

	var granted_id: String = str(data.get("granted_item_id", ""))
	var granted_qty: int = maxi(int(data.get("granted_quantity", 0)), 0)
	var credited: String = str(data.get("credited", ""))

	match credited:
		"gold":
			# THE TOTAL, NOT THE DELTA. This client still pushes `gold` on every
			# save, so a figure it worked out for itself and got wrong once
			# would overwrite the server's row with the wrong number on the very
			# next save — and the loss would look like nothing at all.
			var status: Dictionary = data.get("status", {}) if data.get("status", {}) is Dictionary else {}
			if status.has("gold") and player.has_method("set_gold"):
				player.set_gold(int(status["gold"]))
			elif player.has_method("add_gold"):
				player.add_gold(granted_qty)
			Audio.play("coin")
			_notify_player(player, "+%d gold" % granted_qty)

		"lusions":
			if data.has("lusions") and player.has_method("set_lusions"):
				player.set_lusions(int(data["lusions"]))
			elif player.has_method("add_lusions"):
				player.add_lusions(granted_qty)

			Audio.play("coin")

			if bool(data.get("duplicate_pet", false)):
				_notify_player(player, "Already owned — +%d lusions" % granted_qty)
			else:
				_notify_player(player, "+%d lusions" % granted_qty)

		"inventory":
			var applied: bool = _apply_inventory(data)
			Audio.play("item_pickup")
			var item: ItemData = ItemRegistry.get_item(granted_id)
			var label: String = item.display_name if item != null else granted_id
			_notify_player(player, ("+%d %s" % [granted_qty, label]) if granted_qty > 1 else label)

			# ONLY SAVE IF THE GRID ACTUALLY TOOK THE SERVER'S ANSWER.
			#
			# save_character_state() captures the backpack from that same
			# container, so saving after a failed apply would push the grid as
			# it was BEFORE the pickup straight over the server's carry_items —
			# turning "this screen could not show it" into "this item no longer
			# exists". Skipping the save leaves the server's rows alone, and the
			# next load reads them.
			if applied:
				CharacterData.save_character_state(player)

		_:
			push_warning("LootBagInventory: server credited '%s', which this build does not handle" % credited)


func _apply_inventory(data: Dictionary) -> bool:
	# THE SERVER'S LAYOUT, NOT A LOCAL add_stack().
	#
	# /api/loot/take returns the whole backpack, and it builds it the way
	# InventoryContainer would — topping up an existing stack before opening a
	# new cell. Applying that array rather than adding the item here is what
	# stops the two laying the same pickup out differently, which is what would
	# have happened the first time a potion landed on a part-used stack.
	#
	# Returns false when the grid could not be reached. The caller must not save
	# in that case; see the comment there.
	var cells: Array = data.get("inventory", []) if data.get("inventory", []) is Array else []
	if cells.is_empty():
		return false

	var inv_container: Node = _get_player_inventory_container()
	if inv_container == null:
		push_warning("LootBagInventory: player inventory not found — the server has the item, this screen does not")
		return false

	# The coercion and the load both live on the container now - /api/staff/grant
	# needed the identical thing, and two copies of "parse the server's array"
	# is how they stop agreeing.
	inv_container.load_server_array(cells)
	return true


func _clear_cell(bag_id: String, cell: int) -> void:
	# ONLY IF THE PANEL IS STILL ON THIS BAG. After the await it may be showing
	# a different one, and clearing cell 2 of the bag in front of the player
	# because cell 2 of a bag they walked away from was taken is exactly what
	# "my items vanished" looks like from the outside.
	if _bag_id != bag_id:
		return

	# _loading around it so _on_container_changed() does not also fire a mirror
	# mid-removal; the mirror below is the one that should happen.
	_loading = true
	loot_container.remove_stack_at(cell)
	_loading = false

	_mirror_to_bag()


func _handle_refusal(res: Dictionary, player: Node, bag_id: String, cell: int) -> void:
	var code: int = int(res.get("status", 0))

	match code:
		404:
			# Already taken, or never there — the same answer either way, and it
			# is the answer that makes a duplicate request harmless. Clear the
			# cell, because the grid was showing something the bag does not
			# have.
			_clear_cell(bag_id, cell)
			_notify_player(player, "That's already gone.")
		409:
			# The refusal has its own sound. A take that does nothing and says
			# nothing audible is indistinguishable from a click that missed.
			Audio.play("refused")
			_notify_player(player, "Inventory full")
		410:
			_notify_player(player, "That bag is gone.")
			_close_emptied_bag(bag_id)
		_:
			# Including a timeout, which is the common one. Nothing moved on
			# either side, so the cell stays exactly where it is and the player
			# can try again.
			_notify_player(player, "No connection — try again.")

	if OS.is_debug_build():
		print("[LOOT] take refused (%d) — %s" % [code, res.get("error", "")])


func _close_emptied_bag(bag_id: String) -> void:
	if _bag_id != bag_id:
		return
	if is_instance_valid(_world_bag) and _world_bag.has_method("despawn_now"):
		_world_bag.despawn_now()
	_disconnect_world_bag_signal()
	_world_bag = null
	_bag_id = ""
	visible = false


func _get_player_inventory_container() -> Node:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return null
	var inv_screen: Node = hud.get("inventory_screen") if "inventory_screen" in hud else null
	if inv_screen == null:
		return null
	return inv_screen.get_node_or_null("%inventorycontainer")


# =============================================================================
# THE DISPLAY MIRROR
# =============================================================================

func _on_container_changed() -> void:
	# The grid only changes now because this panel changed it — a drag out of a
	# loot slot is refused, and a take goes through _clear_cell(), which raises
	# _loading around the removal for exactly this reason. So reaching here
	# un-guarded means something moved that this file did not move, and keeping
	# the bag's copy honest is the safe response.
	if _loading:
		return
	_mirror_to_bag()


func _mirror_to_bag() -> void:
	# NOT A SAVE. This writes the panel's view back onto the world node so that
	# re-opening the bag shows what is left without another round trip. The
	# server's rows are the bag; this is the picture of them.
	#
	# to_save_array() is fixed-length with null in every empty cell, which is
	# what keeps index == the server's position across a close and a re-open.
	if not is_instance_valid(_world_bag):
		return
	if _world_bag.has_method("set_contents"):
		_world_bag.set_contents(loot_container.to_save_array())


# =============================================================================
# PET OWNERSHIP CHECK — FOR DISPLAY ONLY
# =============================================================================

func _player_owns_pet(pet_id: String) -> bool:
	# The real decision is the server's, in /api/loot/take. This only decides
	# whether the bag DRAWS a pet or a pile of lusions.
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
