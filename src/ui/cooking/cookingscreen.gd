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
#
# EXPORTED RATHER THAN CONST because this is a feel number, and a feel number
# belongs where you can drag it while watching the thing it controls. Open
# cookingscreen.tscn and it is in the inspector on the root.
#
# IT WENT 0.45 -> 0.9 -> 1.5 AND BACK DOWN TO 0.35, which is worth recording
# because the climb was chasing the wrong number.
#
# Each raise made the panel slower without making anything look like it was
# cooking, because there was no cook duration at all — a fish took as long as
# the server took to answer, and this only widened the silence afterwards. Past
# about two seconds that silence stopped reading as "the fish is cooking" and
# started reading as a stall.
#
# cook_duration below is the number that was actually missing. With the bar
# filling across it, this goes back to being what its name says: a short beat
# between one result and the next request, long enough to read what happened.
@export var cook_interval: float = 0.35

# How long one fish visibly takes to cook, in seconds.
#
# THIS IS THE NUMBER THAT WAS MISSING, and it is why raising cook_interval kept
# not being the fix. There was never a cook duration — a fish took exactly as
# long as /api/cooking/cook took to answer, which on localhost is a few
# milliseconds. All cook_interval could do was widen the silence BETWEEN fish,
# so the panel got slower without anything ever looking like it was cooking.
#
# Now the request goes out immediately and the bar fills across this duration.
# Whichever finishes last decides when the result appears, so the server's
# latency hides inside the animation rather than being the animation. A slow
# reply makes the bar wait at full; a fast one is invisible.
#
# cook_interval is back down to 0.35 because it no longer has to carry the
# pacing on its own — 1.6s of a bar filling reads as cooking, where 1.5s of a
# still panel read as a stall.
@export var cook_duration: float = 1.6

# How many chunks the bar fills in. Discrete steps rather than a smooth slide,
# because a bar that creeps reads as a loading spinner and a bar that clunks
# reads as something being done in stages. Six is enough to feel like progress
# and few enough that each step is a visible event.
@export var cook_segments: int = 6

# Divider colour between segments, drawn over the fill.
const SEGMENT_LINE := Color(0.05, 0.04, 0.03, 0.85)

# Fill colour while cooking, as distinct from the burn-risk fill.
#
# THE BAR MEANS TWO THINGS AND MUST NEVER LOOK LIKE IT MEANS ONE. At rest it is
# the chance this fish burns; while cooking it is how far along the fish is.
# They never show at the same time, but a player who sees the same orange in
# both will read the second as the first. Risk stays the hot orange it was;
# progress is a cooler gold.
const COOK_FILL := Color(0.98, 0.82, 0.35, 1.0)

# Grid holding the raw fish view. Must match grid_width x grid_height in the
# .tscn — nothing asserts it, exactly as LOOT_SIZE does not in the loot panel.
const GRID_SIZE := 12

# The fire's resting animation speed, and what it climbs to while something is
# actually cooking. A fire that visibly works harder when you put food on it is
# the whole reason the sprite is in the panel.
const FIRE_SPEED_IDLE := 1.0
const FIRE_SPEED_COOKING := 1.7

# How long a floating message stays fully readable before it fades.
const FLASH_HOLD := 1.3
const FLASH_FADE := 0.6

# The stone-warming shader, shared with the world firepit. The panel's fire is
# always lit, so its ring is always hot — there is no cold state to animate to
# here, only the extra glow while something is actually on the fire.
const HEARTH_SHADER := preload("res://src/shared/hearth_warm.gdshader")

# How much light the stone throws while idle, and while a fish is cooking. The
# second number is what makes putting food on the fire visible in the rock as
# well as in the flame.
const HEARTH_LIFT_IDLE := 0.30
const HEARTH_LIFT_COOKING := 0.44


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var close_button: Button = %closebutton
@onready var fish_grid: Node = %fishgrid
@onready var skill_label: Label = %skilllabel

# THE FIRE IS THE INTERFACE. There is no Cook button and no status line, and
# both were removed on purpose rather than restyled.
#
# A status line is what a screen uses when its visuals carry no state: the panel
# said "Select a fish." because nothing on it could show that no fish was
# selected. Here the fish sits on the fire or it does not. The bar under it is
# the burn risk. A refusal floats up and fades, because a refusal is an event
# and not a field.
#
# The Cook button went for the same reason: clicking a fish is already the
# instruction, so a second click on a different control to confirm it was
# ceremony. Click a fish to put it on the fire, click again to take it off.
@onready var firebox: Panel = %firebox
# NAMED fire_sprite, NOT firepit. open_for_firepit() takes a `firepit`
# parameter and _cook_one() keeps a local `firepit` across its await — a member
# by that name would shadow both, and GDScript would let it, quietly.
@onready var fire_sprite: AnimatedSprite2D = %firepit
@onready var sparks: CPUParticles2D = %sparks
@onready var cook_icon: TextureRect = %cookicon
@onready var risk_bar: ProgressBar = %riskbar
@onready var flash_label: Label = %flash
@onready var catch_label: Label = %catchlabel
@onready var glow: TextureRect = %glow


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

# The bar's two fills, built once in _ready() and swapped between.
#
# CACHED RATHER THAN REBUILT, because get_theme_stylebox("fill") returns the
# OVERRIDE once one has been applied. Rebuilding from it each cook would make
# the second cook a copy of the cook colour and the risk fill would never come
# back. See _cache_fill_styles().
var _fill_risk: StyleBox = null
var _fill_cook: StyleBox = null


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	if close_button != null and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)

	if fish_grid.has_signal("slot_clicked"):
		if not fish_grid.slot_clicked.is_connected(_on_slot_clicked):
			fish_grid.slot_clicked.connect(_on_slot_clicked)

	# THE FIRE IS A DROP TARGET, forwarded rather than scripted. firebox is a
	# plain Panel, and giving it its own script only to answer two callbacks
	# would be a second file that exists to hold eight lines. set_drag_forwarding
	# points those callbacks back at this node instead.
	#
	# Dropping a raw fish on the fire is the same instruction as clicking one in
	# the strip below — it just reads as the thing it is. Nothing is moved by the
	# drop: it starts a cook request, exactly as a click does, so the rule that
	# the client never relocates an item on its own still holds.
	firebox.set_drag_forwarding(Callable(), _fire_can_drop, _fire_drop)

	_cache_fill_styles()
	_build_segment_dividers()

	fire_sprite.play("lit")
	fire_sprite.speed_scale = FIRE_SPEED_IDLE

	# A FRESH MATERIAL, not a shared one. Same rule as everywhere else a
	# ShaderMaterial gets built in this project: a Material is a Resource, and
	# one held as a const would be handed to every scene that preloaded it.
	var hearth := ShaderMaterial.new()
	hearth.shader = HEARTH_SHADER
	hearth.set_shader_parameter("warmth", 1.0)
	hearth.set_shader_parameter("lift", HEARTH_LIFT_IDLE)
	fire_sprite.material = hearth
	cook_icon.texture = null
	risk_bar.visible = false
	flash_label.text = ""
	catch_label.text = ""

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

func close_panel() -> void:
	# The public name for "shut this". _on_close_pressed() is the close button's
	# handler and the firepit's walk-away handler, and calling a private handler
	# from another script is how a rename turns into a silent no-op. The HUD's
	# Escape key comes through here.
	_on_close_pressed()


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
	# ONE CLICK IS THE WHOLE INSTRUCTION. Clicking a fish puts it on the fire and
	# starts cooking; clicking the same fish again takes it off. Clicking a
	# different fish while one is cooking switches to it once the fish already
	# with the server comes back.
	if slot == null or slot.is_empty():
		return

	var item_id: String = str(slot.stack.data.item_id)

	if _running and item_id == _selected:
		_stop_run()
		return

	_start_run(item_id)


func _fire_can_drop(_at: Vector2, data: Variant) -> bool:
	# Accepts a drag carrying a cookable item. The check is cooks_into, the same
	# test _raw_fish_stacks() and the server both make — not the item type and
	# not the name, so the first cookable thing that is not a fish works without
	# anyone remembering this line exists.
	var item_id: String = _dragged_item_id(data)
	if item_id == "":
		return false
	var item: ItemData = ItemRegistry.get_item(item_id)
	return item != null and str(item.cooks_into) != ""


func _fire_drop(_at: Vector2, data: Variant) -> void:
	var item_id: String = _dragged_item_id(data)
	if item_id == "":
		return
	_start_run(item_id)


func _dragged_item_id(data: Variant) -> String:
	# InventorySlot builds the drag payload; read it defensively because a drag
	# can also arrive from somewhere that is not a slot at all.
	if not (data is Dictionary):
		return ""
	var dict: Dictionary = data as Dictionary
	var stack: Variant = dict.get("stack")
	if stack == null or stack.data == null:
		return ""
	return str(stack.data.item_id)


func _update_controls() -> void:
	# Kept under its old name because every existing caller uses it, and renaming
	# a function to describe a redesign is how a diff stops being readable.
	var level: int = _cooking_level()
	skill_label.text = "Cooking %d" % level

	if _selected == "" or not _running:
		_clear_fire()
		return

	var data: ItemData = ItemRegistry.get_item(_selected)
	if data == null:
		_clear_fire()
		return

	cook_icon.texture = data.icon
	cook_icon.modulate = data.icon_tint
	cook_icon.visible = true
	catch_label.text = data.display_name

	# THE BAR IS THE SENTENCE THAT USED TO BE HERE. "about 30% will burn" became
	# a bar that is 30% full: same number, read at a glance, and it sits under
	# the fish it is talking about instead of in a line of prose below the panel.
	var burn: float = _burn_chance(data, level)
	risk_bar.visible = burn > 0.0
	risk_bar.value = burn * 100.0

	fire_sprite.speed_scale = FIRE_SPEED_COOKING
	sparks.amount = 40
	_set_hearth_lift(HEARTH_LIFT_COOKING)


func _clear_fire() -> void:
	cook_icon.texture = null
	cook_icon.visible = false
	cook_icon.scale = Vector2.ONE
	risk_bar.visible = false
	catch_label.text = ""
	fire_sprite.speed_scale = FIRE_SPEED_IDLE
	sparks.amount = 22
	_set_hearth_lift(HEARTH_LIFT_IDLE)


func _set_hearth_lift(value: float) -> void:
	var mat: ShaderMaterial = fire_sprite.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("lift", value)


# =============================================================================
# STARTING AND STOPPING
# =============================================================================

func _start_run(item_id: String) -> void:
	var data: ItemData = ItemRegistry.get_item(item_id)
	if data == null or str(data.cooks_into) == "":
		return

	# CHECKED HERE ONLY TO EXPLAIN THE REFUSAL. The server checks it again
	# against its own skills row and its answer is the one that counts; this
	# exists so the player reads "needs cooking level 30" rather than putting a
	# fish on the fire and watching nothing happen.
	var level: int = _cooking_level()
	if level < data.cook_level:
		_flash("Needs cooking level %d." % data.cook_level)
		return

	_selected = item_id
	if _running:
		# Already cooking something else. Point at the new fish and let the run
		# pick it up — the fish currently with the server still finishes.
		_update_controls()
		return

	_running = true
	_update_controls()
	await _cook_run(_selected)


func _stop_run() -> void:
	# The fish already in flight finishes; nothing after it starts.
	_running = false
	_update_controls()


# =============================================================================
# FLOATING MESSAGES
# =============================================================================

func _flash(text: String) -> void:
	# A REFUSAL IS AN EVENT, NOT A FIELD. The old panel had a Label that always
	# held a sentence, so the screen was always explaining itself. This shows a
	# line over the fire, holds it long enough to read, and takes it away.
	if flash_label == null:
		return
	flash_label.text = text
	flash_label.modulate = Color(1, 1, 1, 1)

	var tween: Tween = create_tween()
	tween.tween_interval(FLASH_HOLD)
	tween.tween_property(flash_label, "modulate:a", 0.0, FLASH_FADE)


func _pulse_fire(burnt: bool) -> void:
	# The result of one fish, said in the art. A cooked fish flares the fire and
	# throws sparks; a burnt one drops the icon to charcoal for a beat. Neither
	# needs a word, which is the point.
	if not is_instance_valid(cook_icon):
		return

	if burnt:
		cook_icon.modulate = Color(0.32, 0.26, 0.22, 1)
	else:
		sparks.amount = 64

	var tween: Tween = create_tween()
	tween.tween_property(cook_icon, "scale", Vector2(1.22, 1.22), 0.09)
	tween.tween_property(cook_icon, "scale", Vector2.ONE, 0.16)

	# PUT THE EMITTER BACK. Without this the flare was permanent: the first
	# cooked fish raised the spark count and nothing ever lowered it, so a long
	# run ended with a bonfire.
	tween.tween_callback(func() -> void:
		if is_instance_valid(sparks):
			sparks.amount = 40 if _running else 22)


func _build_segment_dividers() -> void:
	# Thin lines across the bar so the segments are visible as segments rather
	# than as a fill that happens to move in jumps.
	#
	# PARENTED TO THE BAR AND ANCHORED, not positioned in pixels. The bar is
	# absolutely placed in cookingscreen.tscn and has already been resized once
	# this week; anchors mean the dividers follow whatever width it ends up
	# with instead of being a second set of numbers to keep in sync with it.
	#
	# Children of a ProgressBar draw over its fill, which is what puts the lines
	# on top rather than behind.
	if risk_bar == null or cook_segments <= 1:
		return

	for i in range(1, cook_segments):
		var frac: float = float(i) / float(cook_segments)
		var line := ColorRect.new()
		line.color = SEGMENT_LINE
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.anchor_left = frac
		line.anchor_right = frac
		line.anchor_top = 0.0
		line.anchor_bottom = 1.0
		line.offset_left = -1.0
		line.offset_right = 1.0
		line.offset_top = 0.0
		line.offset_bottom = 0.0
		risk_bar.add_child(line)


func _cache_fill_styles() -> void:
	# BOTH BOXES BUILT ONCE, FROM THE ORIGINAL, AND STORED.
	#
	# Building the cook box on demand meant reading get_theme_stylebox("fill")
	# after an override had already been applied — so the second cook would
	# duplicate the cook colour, the third would duplicate that, and the risk
	# fill would never come back. Reading a value you have already overwritten
	# is the same bug shape as the stale copies elsewhere in this project.
	#
	# The duplicate() also matters on its own: a StyleBox is a Resource and the
	# one in the theme is shared with anything else using it. Recolouring in
	# place would repaint every bar in the game — the Material trap in another
	# costume.
	if risk_bar == null:
		return
	_fill_risk = risk_bar.get_theme_stylebox("fill")

	var box: StyleBoxFlat = (_fill_risk as StyleBoxFlat)
	if box == null:
		_fill_cook = _fill_risk
		return
	var copy: StyleBoxFlat = box.duplicate()
	copy.bg_color = COOK_FILL
	_fill_cook = copy


func _run_cook_bar() -> Tween:
	# The bar filling, one segment at a time, across cook_duration.
	#
	# RETURNED RATHER THAN AWAITED so the caller can fire the request first and
	# then wait on whichever of the two finishes last. Awaiting it here would
	# serialise them and make every cook take duration PLUS latency.
	if risk_bar == null:
		return null

	if _fill_cook != null:
		risk_bar.add_theme_stylebox_override("fill", _fill_cook)
	risk_bar.visible = true
	risk_bar.value = 0.0

	var steps: int = maxi(cook_segments, 1)
	var step_time: float = maxf(cook_duration, 0.05) / float(steps)

	var tween: Tween = create_tween()
	for i in range(1, steps + 1):
		var to: float = 100.0 * float(i) / float(steps)
		tween.tween_interval(step_time)
		# GUARDED INSIDE THE LAMBDA. The tween is bound to this node so it dies
		# with the panel, but risk_bar is a child and the callback runs a frame
		# later than the check that queued it.
		tween.tween_callback(func() -> void:
			if is_instance_valid(risk_bar):
				risk_bar.value = to)
	return tween


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

		# REFRESH FIRST, THEN PULSE. _refresh() runs _update_controls(), which
		# rewrites cook_icon.modulate from the item's tint. Pulsing before it
		# set the burnt charcoal and then wiped it in the same frame.
		_refresh()
		_pulse_fire(result == "burnt")

		if not _running:
			break
		await get_tree().create_timer(cook_interval).timeout
		if not is_instance_valid(self) or not is_inside_tree() or not visible:
			return

	_running = false

	# THE TALLY IS THE ONE SENTENCE WORTH SAYING, because it is the only thing
	# on this screen the art cannot show: what happened across a whole stack,
	# after the stack is gone. It floats and fades like any other event.
	if cooked > 0 or burnt > 0:
		if burnt > 0:
			_flash("Cooked %d, burnt %d." % [cooked, burnt])
		else:
			_flash("Cooked %d." % cooked)
	_selected = ""
	_update_controls()


func _cook_one(item_id: String) -> String:
	if _cooking:
		return "busy"
	if not Api.is_logged_in():
		# NO LOCAL FALLBACK, deliberately — the same rule lootbaginventory.gd
		# states. Cooking a fish because the server could not be asked is a
		# client minting items by making a request fail.
		_flash("Not connected — can't cook.")
		return "refused"

	# Captured before the await, all of it.
	var firepit: Node = _firepit
	var player: Node = _player if is_instance_valid(_player) else null

	_cooking = true

	# THE BAR STARTS BEFORE THE REQUEST, AND BOTH HAVE TO FINISH.
	#
	# Started first so the fill covers the whole round trip rather than starting
	# after it. Then the request is awaited, then whatever is left of the bar —
	# so a fast server is hidden inside the animation and a slow one holds the
	# bar at full instead of the panel sitting blank.
	var bar: Tween = _run_cook_bar()

	var res: Dictionary = await Api.post("/api/cooking/cook", {
		"slot": CharacterData.active_character_index,
		"item_id": item_id,
	}, COOK_TIMEOUT)

	# PAST AN AWAIT, and the tween may be dead because the node was freed.
	if bar != null and is_instance_valid(bar) and bar.is_running():
		await bar.finished

	_cooking = false

	if not is_instance_valid(self) or not is_inside_tree():
		return "refused"

	# AFTER THE GUARD, not before it. This touches a child node, and this file's
	# own rule is that nothing past an await assumes the tree is as it was.
	#
	# Hands the bar back to the risk readout. _refresh() below rewrites the
	# value; this is the colour, which _refresh() has no reason to know about.
	if is_instance_valid(risk_bar) and _fill_risk != null:
		risk_bar.add_theme_stylebox_override("fill", _fill_risk)

	# Re-collapse: valid a moment ago is not valid now.
	player = player if is_instance_valid(player) else null

	# The panel may have been re-pointed at a different firepit while this was
	# in flight. The fish is cooked on the server either way, but this screen
	# must not narrate it over whatever it is showing now.
	if _firepit != firepit:
		return "refused"

	if not res.get("ok", false):
		_flash(_refusal_text(res))
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
