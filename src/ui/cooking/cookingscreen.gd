# cookingscreen.gd — the panel a lit firepit opens. Shows the raw fish you are
# carrying, you pick one, and it cooks through the stack a fish at a time.
#
# BUILT ON lootbaginventory.gd's SHAPE ON PURPOSE, down to the guard names: one
# request in flight at a time, everything captured before the await, the server's
# arrays applied rather than local deltas, and exactly one close path. That file
# is the only other panel in the game that mutates items through the server, and
# two divergent shapes for the same job is how one of them ends up with the bug
# the other already fixed.
#
#
# THE FISH NEVER MOVE INTO THIS PANEL, AND THAT IS THE WHOLE SAFETY ARGUMENT.
#
# The obvious build is a drop zone you drag raw fish into. It is also a
# duplication bug waiting to happen, and lootbaginventory.gd's header spells out
# why: a drag moves a stack between containers synchronously with no request, so
# a player could drag five fish in, cook them, and still have the originals if
# anything went wrong on the way back. This grid is a VIEW of the backpack, not
# a second place items can be. Clicking selects; nothing is held here.
#
# So the slots are stamped "lootbag" — InventorySlot refuses to start a drag
# from one, which is exactly the behaviour wanted and already written. The name
# is wrong for this panel and the behaviour is right; adding a "cooking" string
# would be a silent no-op, because only "lootbag" and "bank" are branched on.
#
#
# THE SERVER DECIDES WHAT COMES OUT, INCLUDING WHETHER IT BURNED.
#
# docs/inventoryauthority.md names this endpoint:
#
#     POST /api/cooking/cook consumes the inputs and produces the output in one
#     transaction. Both halves server side, or a client can cook from nothing.
#
# So the request says which fish, and nothing else. Not the result, not the
# burn roll, not the cooking level. The burn roll in particular has to be the
# server's: a client that rolled its own would simply never burn anything.
#
# ONE FISH PER REQUEST, even when cooking a stack of ninety-nine. The loop lives
# here and each iteration is its own transaction, so a disconnect halfway
# through leaves the fish that were cooked cooked and the rest raw — rather than
# one request that mints ninety-nine items and has to be all-or-nothing about
# a thing the player watched happen one at a time.
extends Control


# =============================================================================
# CONSTANTS
# =============================================================================

# Matches lootbaginventory.gd's TAKE_TIMEOUT and for the same reason: this is a
# request the player made and is watching, so it earns more patience than a
# background probe — but not so much that a stalled cook reads as a hung game.
const COOK_TIMEOUT := 4.0

# Seconds between one fish finishing and the next starting. Long enough to read
# the result and hit stop, short enough that a big stack is not a chore.
const COOK_INTERVAL := 0.45

# Grid holding the raw fish view. Must match grid_width x grid_height in the
# .tscn — nothing asserts it, exactly as LOOT_SIZE does not in the loot panel.
const GRID_SIZE := 12


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var close_button: Button = %closebutton
@onready var fish_grid: Node = %fishgrid
@onready var cook_button: Button = %cookbutton
@onready var status_label: Label = %statuslabel
@onready var skill_label: Label = %skilllabel


# =============================================================================
# STATE
# =============================================================================

var _firepit: Node = null
var _player: Node = null

# The raw fish item_id currently selected, or "" for none.
var _selected: String = ""

# One request at a time, same guard as the loot panel's _taking. A second cook
# starting while the first is out would be two claims against a backpack neither
# has seen the state of.
var _cooking: bool = false

# Set false to stop a run partway through a stack.
var _running: bool = false


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	if close_button != null and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)

	if cook_button != null and not cook_button.pressed.is_connected(_on_cook_pressed):
		cook_button.pressed.connect(_on_cook_pressed)

	if fish_grid.has_signal("slot_clicked"):
		if not fish_grid.slot_clicked.is_connected(_on_slot_clicked):
			fish_grid.slot_clicked.connect(_on_slot_clicked)

	visible = false


func open_for_firepit(firepit: Node, player: Node) -> void:
	# Tear down the previous firepit's connection before pointing at a new one.
	# This panel is instantiated once and re-pointed forever, so every connect()
	# needs a disconnect() that runs at close AND at the top of the next open —
	# see lootbaginventory.gd, which learned this the same way.
	_disconnect_firepit_signal()

	_firepit = firepit
	_player = player
	_selected = ""
	_running = false
	_cooking = false

	# EVERY SLOT HERE IS A VIEW, NOT A HOLDING PLACE. See the header: stamping
	# them "lootbag" is what stops a drag moving a stack out of the backpack
	# with no request behind it. Done here rather than in the scene because the
	# slots are created at runtime by InventoryContainer.
	if fish_grid.has_method("set_slot_type"):
		fish_grid.set_slot_type("lootbag")

	_refresh()

	visible = true

	# visible BEFORE reset_size(): Godot cannot compute an accurate combined
	# minimum size for a hidden control. Same ordering, same reason, as the loot
	# panel. There is no ScrollContainer in this scene precisely so this works —
	# a ScrollContainer does not propagate its child's real size upward, which
	# is the dead-space bug the loot panel still has.
	reset_size()

	if _firepit != null and _firepit.has_signal("player_left_range"):
		if not _firepit.player_left_range.is_connected(_on_close_pressed):
			_firepit.player_left_range.connect(_on_close_pressed)


# =============================================================================
# CLOSING — ONE PATH, whatever the reason
# =============================================================================

func _on_close_pressed() -> void:
	_running = false

	if is_instance_valid(_firepit) and _firepit.has_method("notify_panel_closed"):
		_firepit.notify_panel_closed()

	_disconnect_firepit_signal()
	visible = false
	_firepit = null
	_player = null
	_selected = ""


func _disconnect_firepit_signal() -> void:
	if _firepit != null and _firepit.has_signal("player_left_range"):
		if _firepit.player_left_range.is_connected(_on_close_pressed):
			_firepit.player_left_range.disconnect(_on_close_pressed)


# =============================================================================
# THE FISH VIEW
# =============================================================================

func _refresh() -> void:
	var stacks: Array = _raw_fish_stacks()

	# INDEX IN, INDEX OUT is NOT needed here, and this is the one place this
	# panel deliberately differs from the loot panel. A loot bag's cell number
	# is what gets sent to the server, so compacting it would mean clicking one
	# item and being handed another. Nothing here sends a position — the request
	# carries an item_id — so packing the fish into the first cells is safe and
	# reads far better than a grid with holes where the potions were.
	var cells: Array = []
	cells.resize(GRID_SIZE)
	for i in range(mini(stacks.size(), GRID_SIZE)):
		cells[i] = stacks[i]

	if fish_grid.has_method("load_save_array"):
		fish_grid.load_save_array(cells)

	# set_slot_type has to be re-applied after anything that rebuilds slots.
	if fish_grid.has_method("set_slot_type"):
		fish_grid.set_slot_type("lootbag")

	_update_controls()


func _raw_fish_stacks() -> Array:
	# Everything cookable in the backpack, as {item_id, quantity} dictionaries.
	#
	# BY cooks_into, NOT BY TYPE OR BY NAME. Type.FISH would work today and
	# break the first time something cookable is not a fish; matching "raw" as a
	# prefix would break the first time a fish is called something else. An item
	# is cookable when it says what it cooks into, which is the same test the
	# server makes.
	var out: Array = []
	var backpack: Node = _player_backpack()
	if backpack == null or not backpack.has_method("get_all_stacks"):
		return out

	for stack in backpack.get_all_stacks():
		if stack == null or stack.data == null:
			continue
		if str(stack.data.cooks_into) == "":
			continue
		out.append({"item_id": stack.data.item_id, "quantity": stack.quantity})
	return out


func _player_backpack() -> Node:
	# The group-lookup idiom, copied from lootbaginventory.gd and
	# player.gd::_debug_inventory_container() rather than reinvented.
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return null
	var inv_screen: Node = hud.get("inventory_screen") if "inventory_screen" in hud else null
	if inv_screen == null:
		return null
	return inv_screen.get_node_or_null("%inventorycontainer")


func _on_slot_clicked(slot: Object) -> void:
	if slot == null or slot.is_empty():
		_selected = ""
	else:
		_selected = str(slot.stack.data.item_id)
	_update_controls()


func _update_controls() -> void:
	var level: int = _cooking_level()
	skill_label.text = "Cooking %d" % level

	if _running:
		cook_button.text = "Stop"
		cook_button.disabled = false
		return

	cook_button.text = "Cook"

	if _selected == "":
		cook_button.disabled = true
		status_label.text = "Select a fish."
		return

	var data: ItemData = ItemRegistry.get_item(_selected)
	if data == null:
		cook_button.disabled = true
		status_label.text = ""
		return

	if level < data.cook_level:
		# SAID HERE ONLY TO EXPLAIN THE REFUSAL. The server checks it again
		# against its own skills row and its answer is the one that counts —
		# this exists so the player reads "you need level 30" instead of
		# watching a button do nothing.
		cook_button.disabled = true
		status_label.text = "Needs cooking level %d." % data.cook_level
		return

	cook_button.disabled = false
	var burn: int = int(round(_burn_chance(data, level) * 100.0))
	if burn > 0:
		status_label.text = "%s — about %d%% will burn." % [data.display_name, burn]
	else:
		status_label.text = "%s — you have this one mastered." % data.display_name


func _cooking_level() -> int:
	if is_instance_valid(_player) and "cooking" in _player:
		return int(_player.cooking)
	return 1


func _burn_chance(data: ItemData, level: int) -> float:
	# SHOWN HERE, DECIDED ON THE SERVER, FROM ONE NUMBER. The panel tells the
	# player what they are risking before they commit; /api/cooking/cook does the
	# rolling. Both read GameConstants.COOK_BURN_MAX, which exportgamedata.gd
	# ships to the server - so the label and the roll cannot drift, and editing
	# the curve is one edit in one file.
	if data.cook_mastery_level <= data.cook_level:
		return 0.0
	if level >= data.cook_mastery_level:
		return 0.0
	var span: float = float(data.cook_mastery_level - data.cook_level)
	var into: float = float(level - data.cook_level)
	var worst: float = GameConstants.COOK_BURN_MAX
	return clampf(worst * (1.0 - into / span), 0.0, worst)


# =============================================================================
# COOKING
# =============================================================================

func _on_cook_pressed() -> void:
	if _running:
		# The button is "Stop" while a run is going. The fish already in flight
		# finishes — it is with the server — and nothing after it starts.
		_running = false
		_update_controls()
		return

	if _selected == "":
		return

	_running = true
	_update_controls()
	await _cook_run(_selected)


func _cook_run(item_id: String) -> void:
	var cooked: int = 0
	var burnt: int = 0

	while _running:
		# RE-READ FROM THE BACKPACK EVERY ITERATION rather than counting down a
		# number captured at the start. The backpack is the server's answer to
		# the last cook, so it already knows how many are left — and a local
		# counter would drift the moment anything else touched the bag.
		var backpack: Node = _player_backpack()
		if backpack == null or not backpack.has_method("get_quantity_of"):
			break
		if backpack.get_quantity_of(item_id) <= 0:
			break

		var result: String = await _cook_one(item_id)

		# PAST AN AWAIT. Four seconds is long enough to close the panel, walk
		# away, or die.
		if not is_instance_valid(self) or not is_inside_tree():
			return
		if not visible:
			return

		match result:
			"cooked":
				cooked += 1
			"burnt":
				burnt += 1
			_:
				# Anything else is a refusal that already told the player why.
				break

		_refresh()

		if not _running:
			break
		await get_tree().create_timer(COOK_INTERVAL).timeout
		if not is_instance_valid(self) or not is_inside_tree() or not visible:
			return

	_running = false

	if cooked > 0 or burnt > 0:
		if burnt > 0:
			status_label.text = "Cooked %d, burnt %d." % [cooked, burnt]
		else:
			status_label.text = "Cooked %d." % cooked
	_update_controls()


func _cook_one(item_id: String) -> String:
	if _cooking:
		return "busy"
	if not Api.is_logged_in():
		# NO LOCAL FALLBACK, deliberately — the same rule lootbaginventory.gd
		# states. Cooking a fish because the server could not be asked is a
		# client minting items by making a request fail.
		status_label.text = "Not connected — can't cook."
		return "refused"

	# Captured before the await, all of it.
	var firepit: Node = _firepit
	var player: Node = _player if is_instance_valid(_player) else null

	_cooking = true
	var res: Dictionary = await Api.post("/api/cooking/cook", {
		"slot": CharacterData.active_character_index,
		"item_id": item_id,
	}, COOK_TIMEOUT)
	_cooking = false

	if not is_instance_valid(self) or not is_inside_tree():
		return "refused"

	# Re-collapse: valid a moment ago is not valid now.
	player = player if is_instance_valid(player) else null

	# The panel may have been re-pointed at a different firepit while this was
	# in flight. The fish is cooked on the server either way, but this screen
	# must not narrate it over whatever it is showing now.
	if _firepit != firepit:
		return "refused"

	if not res.get("ok", false):
		status_label.text = _refusal_text(res)
		Audio.play("refused")
		return "refused"

	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}

	var applied: bool = _apply_inventory(data)
	_apply_skill(data)

	var burnt: bool = bool(data.get("burnt", false))
	Audio.play("refused" if burnt else "cook")

	if bool(data.get("levelled_up", false)) and player != null and player.has_method("show_notice"):
		player.show_notice("Cooking level %d" % int(data.get("cooking_level", 0)))

	# ONLY SAVE IF THE GRID ACTUALLY TOOK THE SERVER'S ANSWER. Saving after a
	# failed apply pushes the backpack as it was BEFORE the cook over the
	# server's carry_items, turning "this screen could not show it" into "this
	# item no longer exists". Straight from lootbaginventory.gd.
	if applied and player != null:
		CharacterData.save_character_state(player)

	return "burnt" if burnt else "cooked"


func _apply_inventory(data: Dictionary) -> bool:
	var cells: Array = data.get("inventory", []) if data.get("inventory", []) is Array else []
	if cells.is_empty():
		return false
	var backpack: Node = _player_backpack()
	if backpack == null or not backpack.has_method("load_server_array"):
		push_warning("CookingScreen: player inventory not found — the server cooked it, this screen did not show it")
		return false
	backpack.load_server_array(cells)
	return true


func _apply_skill(data: Dictionary) -> void:
	# THE TOTAL, NOT THE DELTA, for the reason written all over the loot panel:
	# this client still syncs skills, so a level it worked out for itself and
	# got wrong once would overwrite the server's row on the next push.
	if not is_instance_valid(_player):
		return
	var skills: Dictionary = data.get("skills", {}) if data.get("skills", {}) is Dictionary else {}
	var cooking: Dictionary = skills.get("cooking", {}) if skills.get("cooking", {}) is Dictionary else {}
	if cooking.is_empty():
		return
	if "cooking" in _player:
		_player.cooking = int(cooking.get("level", _player.cooking))
	if "cooking_xp" in _player:
		_player.cooking_xp = int(cooking.get("xp", _player.cooking_xp))


func _refusal_text(res: Dictionary) -> String:
	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	var message: String = str(data.get("message", ""))
	if message != "":
		return message

	match int(res.get("status", 0)):
		0:   return "No connection — try again."
		403: return "Your cooking level isn't high enough."
		404: return "You aren't carrying that."
		409: return "Your backpack is full."
		429: return "Slow down."
		_:   return "That didn't cook."
