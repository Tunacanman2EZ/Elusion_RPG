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
#
#
# AND, ON THE SECOND TAB, THE MEALS (0.74.0). See THE RECIPES VIEW near the
# bottom: the same fire, the same run, the same one request a meal, against
# /api/cooking/recipe.
extends Control


# What the fire is showing, as it shows it - for the suite, which has no other
# way to see a run's beats from outside.
signal fish_started(item_id: String)
signal fish_done(item_id: String, burnt: bool)
signal run_ended


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

# How long a BURNT fish stays on the fire, charred, before the next goes on
# (0.25.2). The owner: "burned fish vanished to quickly". A burnt fish
# used to get cook_interval like any other - 0.35 s - and the last one of a
# stack not even that: the fire was cleared the moment the run ended. A burn is
# the one result worth a look, so it gets a beat of its own.
@export var burnt_hold: float = 1.2

# The fire's last fish fades out over this long when a run ends, rather than
# being wiped in one frame.
const END_FADE := 0.45

# Divider colour between segments, drawn over the fill.
const SEGMENT_LINE := Color(0.05, 0.04, 0.03, 0.85)

# THE BAR MEANS ONE THING: how far along the fish on the fire is (0.25.2).
#
# It used to mean two. At rest it was the chance the fish burns; while cooking,
# how far along it was - and a run flipped between them every fish: the gold
# fill to the end, then for the 0.35 s between fish an orange bar as long as
# the burn chance, then back to nothing. The owner: "cooking meter was not
# matching up". The burn chance is now words under the fish ("5% burn"),
# which never move while it cooks, and the bar is the cook alone - gold while
# it fills, and ash when the fish it filled for burnt.
const COOK_FILL := Color(0.98, 0.82, 0.35, 1.0)
const BURNT_FILL := Color(0.36, 0.31, 0.28, 1.0)

# A burnt fish on the fire: the raw fish's own picture, charred.
const BURNT_TINT := Color(0.32, 0.26, 0.22, 1.0)
const BURNT_WORD := Color(1.0, 0.55, 0.42, 1.0)

# ONE ROW OF SIX, one cell per kind of fish (day 1: twelve empty boxes under
# the fire, for at most eight kinds of fish in the game). A second row appears
# only when somebody carries more than six kinds, so nothing is ever hidden.
const GRID_COLUMNS := 6

# The width the fire's contents were laid out for in cookingscreen.tscn. A
# wider window moves them across by half the difference, so the fire stays in
# the middle of its box.
const FIREBOX_AUTHORED_WIDTH := 324.0

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

# The two routes a cook can go to: a raw fish, or a meal from its recipe
# (0.74.0). Each request names one of them and nothing else.
const COOK_PATH := "/api/cooking/cook"
const RECIPE_PATH := "/api/cooking/recipe"

# A meal on the fire before it is done: its own picture, faded (_show_fish).
const MEAL_COOKING_TINT := Color(1.0, 1.0, 1.0, 0.65)

# HAVE AND NEED, in the tooltip's comparison colours: green for an ingredient
# the bag holds enough of, red for one it is short of - the same two colours
# that already mean "better" and "worse" over a piece of gear.
const HAVE_ENOUGH := Color(0.55, 0.85, 0.5)
const HAVE_SHORT := Color(0.9, 0.45, 0.4)

# The cooking level a meal needs, in the header badge's gold - and greyed, the
# theme's disabled grey, while yours is below it.
const LEVEL_OPEN := Color(0.95, 0.85, 0.6)
const LEVEL_LOCKED := Color(0.5, 0.45, 0.4)

# A meal you cannot cook yet is drawn this much dimmer, so the rows you can
# cook stand out of a list of nineteen without anything being hidden.
const LOCKED_ROW := Color(0.62, 0.62, 0.62, 1.0)

# How many meals the list shows before it scrolls. Nineteen rows laid out in
# full would make a window taller than the screen; four whole ones keep it
# inside a 720-high one with the fire above them. COUNTED IN ROWS, not pixels,
# so a bigger text size (Options) shows four bigger rows rather than three and
# a half - and never more than PanelWindow.scroll_height() lets it.
const RECIPE_ROWS_SHOWN := 4


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
# how far along it is, and the words under that what it risks (0.25.2 - the
# bar was the risk until then; COOK_FILL says why it is not). A refusal floats
# up and fades, because a refusal is an event and not a field.
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
# THE COOK BAR. Still named riskbar in the scene, from when it showed the burn
# chance (until 0.25.2); renaming a unique node is a second file to keep in step
# for nothing a player sees.
@onready var risk_bar: ProgressBar = %riskbar
@onready var flash_label: Label = %flash
@onready var catch_label: Label = %catchlabel
@onready var glow: TextureRect = %glow

# THE TWO TABS AND THE MEALS (0.74.0). The tabs are the kill record's: two
# toggle buttons in a row under the header, the one showing held down.
@onready var fish_tab: Button = %fishtab
@onready var recipes_tab: Button = %recipestab
@onready var recipe_scroll: ScrollContainer = %recipescroll
@onready var recipe_list: VBoxContainer = %recipelist


# =============================================================================
# STATE
# =============================================================================

var _firepit: Node = null
var _player: Node = null

# The raw fish item_id currently selected, or "" for none. Or a meal's: see
# _selected_recipe.
var _selected: String = ""

# TRUE WHEN _selected IS A MEAL (0.74.0), cooked from its recipe rather than a
# fish off its stack. The run reads both before every cook, so a click on a
# fish while a meal is on the fire is a switch like any other.
var _selected_recipe: bool = false

# How many more of the selected meal this run makes. A fish run counts nothing -
# it cooks until the stack is gone - so this is read only when the selection is
# a meal: one for Cook, as many as the bag holds the ingredients for, for Cook
# all.
var _recipe_left: int = 0

# One request at a time, same guard as the loot panel's _taking. A second cook
# starting while the first is out would be two claims against a backpack neither
# has seen the state of.
var _cooking: bool = false

# Set false to stop a run partway through a stack.
var _running: bool = false

# True while a _cook_run() loop is alive, including the beat after its last
# fish. A click that restarts a run while the old loop is still finishing its
# fish hands the fish to that loop rather than starting a second one beside it.
var _looping: bool = false

# Which run is the current one. Closing or reopening the panel moves it on, so a
# loop still waiting on its last fish from before wakes up, sees it is not the
# current run, and leaves without touching the fire or the new run's flags.
var _run_id: int = 0

# The bar's two fills, built once in _ready() and swapped between.
#
# CACHED RATHER THAN REBUILT, because get_theme_stylebox("fill") returns the
# OVERRIDE once one has been applied. Rebuilding from it each cook would make
# every later box a copy of the last colour set. See _cache_fill_styles().
var _fill_cook: StyleBox = null
var _fill_burnt: StyleBox = null

# The end-of-run fade, so a new fish going on can stop it.
var _fade: Tween = null

# WHICH TAB IS SHOWING (0.74.0). Kept across closes on purpose: the panel is
# built once and re-pointed at every fire, so this is "the tab you left it on".
enum View { FISH, RECIPES }
var _view: int = View.FISH

# recipe id -> that row's moving parts, for _refresh_recipes(); and the ids in
# the order the rows were built, so a catalogue whose meals have changed - the
# suite adding its own - is noticed and the list built again.
var _recipe_rows: Dictionary = {}
var _recipe_order: Array = []


# =============================================================================
# LIFECYCLE
# =============================================================================

# Drag by the header, resize from any edge, and come back where it was left.
# One component for all sixteen panels - see src/shared/panelwindow.gd for why
# this is not thirty lines copied into each of them.
#
# HELD IN A MEMBER, not discarded. It is a RefCounted carrying the drag state
# and the signal connections; letting it go frees it and the panel quietly
# stops responding.
var _window: PanelWindow


func _ready() -> void:
	_window = PanelWindow.attach(self, "cooking")
	# THE MEALS' LIST FOLLOWS ITS ROWS (0.75.0): set back from Largest to
	# Normal, the list kept the height of five Largest rows and the window
	# stood 92 px taller than it opens. Whenever the rows change size - the
	# text, a row built or gone - the list is measured again, and the window
	# follows it (PanelWindow's natural size).
	if recipe_list != null and not recipe_list.minimum_size_changed.is_connected(_fit_recipe_scroll):
		recipe_list.minimum_size_changed.connect(_fit_recipe_scroll, CONNECT_DEFERRED)
	if close_button != null and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)

	if fish_grid.has_signal("slot_clicked"):
		if not fish_grid.slot_clicked.is_connected(_on_slot_clicked):
			fish_grid.slot_clicked.connect(_on_slot_clicked)

	if fish_tab != null and not fish_tab.pressed.is_connected(_set_view):
		fish_tab.pressed.connect(_set_view.bind(View.FISH))
	if recipes_tab != null and not recipes_tab.pressed.is_connected(_set_view):
		recipes_tab.pressed.connect(_set_view.bind(View.RECIPES))

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
	_remember_fire_layout()

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
	_selected_recipe = false
	_recipe_left = 0
	_running = false
	_cooking = false
	_run_id += 1
	_looping = false

	# EVERY SLOT HERE IS A VIEW, NOT A HOLDING PLACE. See the header: stamping
	# them "lootbag" is what stops a drag moving a stack out of the backpack
	# with no request behind it. Done here rather than in the scene because the
	# slots are created at runtime by InventoryContainer.
	if fish_grid.has_method("set_slot_type"):
		fish_grid.set_slot_type("lootbag")

	# The meals, and the tab that was showing when the window last closed: a
	# player cooking stews goes on cooking stews at the next fire.
	_build_recipe_rows()
	_show_view(_view)

	_refresh()

	visible = true

	# visible BEFORE sizing: Godot cannot compute an accurate combined minimum
	# size for a hidden control. There is no ScrollContainer in this scene
	# precisely so this works — a ScrollContainer does not propagate its
	# child's real size upward, which is the dead-space bug the loot panel
	# still has.
	_fit_and_centre()

	if _firepit != null and _firepit.has_signal("player_left_range"):
		if not _firepit.player_left_range.is_connected(_on_close_pressed):
			_firepit.player_left_range.connect(_on_close_pressed)


func _fit_and_centre() -> void:
	"""The window as big as what is in it, in the middle of the screen.

	THE ROOT IS A PLAIN Control, and reset_size() on one does nothing: it
	stayed 0x0 at the screen's centre with the panel spilling out round it.
	Everything that measures the window - a drag, a resize, a window that
	no longer fits - then worked from a rectangle of nothing, and a saved
	position put the panel's corner where its middle had been. So the size
	is set from the content, here.

	CENTRED ON EVERY OPEN (day 1: it opened in the top left corner, where a
	position saved from the old zero-size window put it). A cooking window
	belongs to the fire you are standing at, so it opens in front of you; it
	can still be dragged anywhere while it is open."""
	# The meals' list measured now it is showing, before the window is
	# (0.74.0): a list sized while hidden would size the window with it.
	_fit_recipe_scroll()
	size = PanelWindow.content_minimum(self)
	var screen: Vector2 = get_viewport_rect().size
	position = ((screen - size) * 0.5).floor()


func _fit_to_content() -> void:
	if is_instance_valid(self) and visible:
		size = PanelWindow.content_minimum(self)


func _centre_fire_contents() -> void:
	"""Keep the fire, its glow and sparks, the icon, the bar and the two lines
	in the middle of the box however wide the window is made."""
	if firebox == null:
		return
	var shift: float = floorf((firebox.size.x - FIREBOX_AUTHORED_WIDTH) * 0.5)
	for node in _fire_contents:
		var start: Variant = node.get_meta("authored_x")
		if node is Node2D:
			(node as Node2D).position.x = float(start) + shift
		elif node is Control:
			var c: Control = node
			var width: float = c.offset_right - c.offset_left
			c.offset_left = float(start) + shift
			c.offset_right = c.offset_left + width


var _fire_contents: Array = []


func _remember_fire_layout() -> void:
	for node in [fire_sprite, sparks, glow, cook_icon, risk_bar, flash_label, catch_label]:
		if node == null:
			continue
		node.set_meta("authored_x", (node as Node2D).position.x if node is Node2D else (node as Control).offset_left)
		_fire_contents.append(node)
	if not firebox.resized.is_connected(_centre_fire_contents):
		firebox.resized.connect(_centre_fire_contents)


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
	_run_id += 1
	_looping = false

	if is_instance_valid(_firepit) and _firepit.has_method("notify_panel_closed"):
		_firepit.notify_panel_closed()

	_disconnect_firepit_signal()
	visible = false
	_firepit = null
	_player = null
	_selected = ""
	_selected_recipe = false
	_recipe_left = 0


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
	var rows: int = rows_for(stacks.size())
	if fish_grid.has_method("resize_grid") and fish_grid.grid_height != rows:
		fish_grid.resize_grid(GRID_COLUMNS, rows)
		# A ROW CAME OR WENT WHILE THE WINDOW IS OPEN - the last of a kind was
		# cooked. The window follows, where it stands, once the grid has
		# measured itself.
		if visible:
			_fit_to_content.call_deferred()
	var cells: Array = []
	cells.resize(GRID_COLUMNS * rows)
	for i in range(mini(stacks.size(), cells.size())):
		cells[i] = stacks[i]

	if fish_grid.has_method("load_save_array"):
		fish_grid.load_save_array(cells)

	# set_slot_type has to be re-applied after anything that rebuilds slots.
	if fish_grid.has_method("set_slot_type"):
		fish_grid.set_slot_type("lootbag")

	# THE MEALS' COUNTS TOO, from the same backpack: a fish cooked can be the
	# fish a Fish Skewer was short of, and a Bone Broth cooked is half a
	# Shadowcap Soup.
	_refresh_recipes()

	_update_controls()


func _raw_fish_stacks() -> Array:
	# Everything cookable in the backpack, as {item_id, quantity} dictionaries.
	#
	# BY cooks_into, NOT BY TYPE OR BY NAME. Type.FISH would work today and
	# break the first time something cookable is not a fish; matching "raw" as a
	# prefix would break the first time a fish is called something else. An item
	# is cookable when it says what it cooks into, which is the same test the
	# server makes.
	var backpack: Node = _player_backpack()
	if backpack == null or not backpack.has_method("get_all_stacks"):
		return []

	var held: Array = []
	for stack in backpack.get_all_stacks():
		if stack == null or stack.data == null:
			continue
		if str(stack.data.cooks_into) == "":
			continue
		held.append({"item_id": stack.data.item_id, "quantity": stack.quantity})
	return one_cell_per_kind(held)


static func one_cell_per_kind(held: Array) -> Array:
	"""Stacks of the same fish added together, in the order first seen. Two
	cells of mudfish in the bag are one mudfish cell here: a cook asks for an
	item_id, never a cell, so nothing is lost by joining them."""
	var out: Array = []
	var at: Dictionary = {}
	for entry in held:
		var id: String = str(entry.get("item_id", ""))
		if id == "":
			continue
		if at.has(id):
			out[at[id]]["quantity"] = int(out[at[id]]["quantity"]) + int(entry.get("quantity", 0))
		else:
			at[id] = out.size()
			out.append({"item_id": id, "quantity": int(entry.get("quantity", 0))})
	return out


static func rows_for(kinds: int) -> int:
	@warning_ignore("integer_division")
	return maxi(1, (kinds + GRID_COLUMNS - 1) / GRID_COLUMNS)


func _player_backpack() -> Node:
	# The group-lookup idiom, copied from lootbaginventory.gd and the owner
	# panel's _open_inventory_container() rather than reinvented.
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
	_update_badge()

	# THE FIRE IS THE RUN'S TO DRAW, NOT THIS FUNCTION'S (0.25.2). _show_fish()
	# puts each fish on as its bar starts, _show_result() shows how it came out,
	# and _end_fire() takes the last one off. This used to redraw the fire from
	# _selected whenever it ran - after every cook, and on a click - so the fire
	# showed whatever was selected rather than the fish actually cooking. Only
	# with no run on the fire at all is there nothing to show.
	if not _looping:
		_clear_fire()


func _show_fish(item_id: String) -> void:
	"""The fish whose bar is about to fill, as it goes on the fire: its own
	picture in its own colours, and what it risks in words under it."""
	var data: ItemData = ItemRegistry.get_item(item_id)
	if data == null:
		return
	if _fade != null and _fade.is_valid():
		_fade.kill()
	cook_icon.texture = data.icon
	cook_icon.modulate = data.icon_tint
	# A MEAL GOES ON AS ITSELF, FADED (0.74.0). A fish has a raw picture and a
	# cooked one, and the change between them is the result; a meal has one
	# picture, so it cooks as a ghost of itself and comes off solid.
	if data.is_meal():
		cook_icon.modulate = data.icon_tint * MEAL_COOKING_TINT
	cook_icon.scale = Vector2.ONE
	cook_icon.visible = true
	risk_bar.modulate.a = 1.0
	catch_label.text = risk_text(data.display_name, _burn_chance(data, _cooking_level()))
	catch_label.modulate = Color.WHITE
	fire_sprite.speed_scale = FIRE_SPEED_COOKING
	sparks.amount = 40
	_set_hearth_lift(HEARTH_LIFT_COOKING)
	fish_started.emit(item_id)


static func risk_text(fish_name: String, burn: float) -> String:
	"""The fish's name, and its chance of burning when there is one: "Raw Marsh
	Carp  ·  5% burn". Never "0%" for a chance that is not nothing."""
	if burn <= 0.0:
		return fish_name
	return "%s  ·  %d%% burn" % [fish_name, maxi(1, roundi(burn * 100.0))]


func _show_result(item_id: String, burnt: bool) -> void:
	"""How the fish on the fire came out, held there for a beat: the cooked
	fish itself, or the raw one charred with "Burnt!" under it. The bar stays
	full - gold for cooked, ash for burnt."""
	var raw: ItemData = ItemRegistry.get_item(item_id)
	if burnt:
		cook_icon.modulate = BURNT_TINT
		catch_label.text = "Burnt!"
		catch_label.modulate = BURNT_WORD
		if _fill_burnt != null:
			risk_bar.add_theme_stylebox_override("fill", _fill_burnt)
		sparks.amount = 22
	else:
		var cooked: ItemData = ItemRegistry.get_item(str(raw.cooks_into)) if raw != null else null
		# A meal comes off the fire as the meal it already was (0.74.0).
		if raw != null and raw.is_meal():
			cooked = raw
		if cooked != null:
			cook_icon.texture = cooked.icon
			cook_icon.modulate = cooked.icon_tint
			catch_label.text = cooked.display_name
		sparks.amount = 64
	risk_bar.value = 100.0
	_pulse_fire(burnt)
	fish_done.emit(item_id, burnt)


func _end_fire() -> void:
	"""The run is over: the last fish fades off the fire, then it is cleared."""
	if not cook_icon.visible:
		_clear_fire()
		return
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween().set_parallel(true)
	_fade.tween_property(cook_icon, "modulate:a", 0.0, END_FADE)
	_fade.tween_property(risk_bar, "modulate:a", 0.0, END_FADE)
	_fade.tween_property(catch_label, "modulate:a", 0.0, END_FADE)
	_fade.chain().tween_callback(func() -> void:
		if is_instance_valid(self) and not _looping:
			_clear_fire())


func _clear_fire() -> void:
	cook_icon.texture = null
	cook_icon.visible = false
	cook_icon.scale = Vector2.ONE
	cook_icon.modulate = Color.WHITE
	risk_bar.visible = false
	risk_bar.modulate.a = 1.0
	catch_label.text = ""
	catch_label.modulate = Color.WHITE
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

	var switching: bool = _looping and item_id != _selected
	_selected = item_id
	_selected_recipe = false
	_running = true
	if _looping:
		# A RUN IS ALREADY ON THE FIRE. The fish on it finishes as it is, and the
		# next one off the stack is this one - the loop reads _selected before
		# every fish (0.25.2: it used to keep cooking the fish it started with
		# while the fire showed this one). Said, so the click is seen to land.
		if switching:
			_flash("Next: %s" % data.display_name)
		return

	await _cook_run()


func _stop_run() -> void:
	# The fish already in flight finishes, and is shown; nothing after it starts.
	_running = false


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
	# BOTH BOXES BUILT ONCE, FROM THE SCENE'S, AND STORED.
	#
	# Building a box on demand meant reading get_theme_stylebox("fill") after an
	# override had already been applied — so each would be a copy of the last
	# colour set. Reading a value you have already overwritten is the same bug
	# shape as the stale copies elsewhere in this project.
	#
	# The duplicate() also matters on its own: a StyleBox is a Resource and the
	# one in the theme is shared with anything else using it. Recolouring in
	# place would repaint every bar in the game — the Material trap in another
	# costume.
	if risk_bar == null:
		return
	var authored: StyleBox = risk_bar.get_theme_stylebox("fill")
	var box: StyleBoxFlat = authored as StyleBoxFlat
	if box == null:
		_fill_cook = authored
		_fill_burnt = authored
		return
	var gold: StyleBoxFlat = box.duplicate()
	gold.bg_color = COOK_FILL
	_fill_cook = gold
	var ash: StyleBoxFlat = box.duplicate()
	ash.bg_color = BURNT_FILL
	_fill_burnt = ash


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
	#
	# A MEAL BURNS ON THE SAME CURVE (0.74.0), from its recipe's level and
	# mastery: /api/cooking/recipe rolls it "exactly as burn_chance() does for
	# fish", so this is the same arithmetic with the meal's two numbers.
	var from: int = data.recipe_level if data.is_meal() else data.cook_level
	var mastered: int = data.recipe_mastery_level if data.is_meal() else data.cook_mastery_level
	if mastered <= from:
		return 0.0
	if level >= mastered:
		return 0.0
	var span: float = float(mastered - from)
	var into: float = float(level - from)
	var worst: float = GameConstants.COOK_BURN_MAX
	return clampf(worst * (1.0 - into / span), 0.0, worst)


# =============================================================================
# COOKING
# =============================================================================

func _cook_run() -> void:
	var cooked: int = 0
	var burnt: int = 0
	_run_id += 1
	var mine: int = _run_id
	_looping = true

	while _running:
		# THE FISH IS READ AGAIN BEFORE EVERY COOK, from _selected (0.25.2). A
		# click on another fish mid-run changes _selected; this loop used to hold
		# the item_id it started with and cook that to the end of its stack, while
		# the fire showed the new one - the bar filling for a fish the server
		# never saw.
		var item_id: String = _selected
		var recipe: bool = _selected_recipe
		# RE-READ FROM THE BACKPACK EVERY ITERATION rather than counting down a
		# number captured at the start. The backpack is the server's answer to
		# the last cook, so it already knows how many are left — and a local
		# counter would drift the moment anything else touched the bag.
		var backpack: Node = _player_backpack()
		if item_id == "" or backpack == null or not backpack.has_method("get_quantity_of"):
			break
		# A MEAL STOPS WHEN IT HAS MADE AS MANY AS IT WAS ASKED FOR, or when the
		# bag can no longer make one - read off the bag again, like the fish,
		# so the count is never a number this panel kept for itself.
		if recipe:
			if _recipe_left <= 0 or makeable(ItemRegistry.get_item(item_id), _bag_counts()) <= 0:
				break
		elif backpack.get_quantity_of(item_id) <= 0:
			break

		_show_fish(item_id)
		var result: String = await _cook_one(item_id, recipe)

		# PAST AN AWAIT. Four seconds is long enough to close the panel, walk
		# away, or die - and closing or reopening it makes this a past run.
		if not is_instance_valid(self) or not is_inside_tree() or mine != _run_id:
			return

		match result:
			"cooked":
				cooked += 1
			"burnt":
				burnt += 1
			_:
				# Anything else is a refusal that already told the player why.
				break

		# ONE OFF THE COUNT - unless a click put something else on the fire
		# while this meal cooked, in which case the count is the new one's.
		if recipe and _selected_recipe and _selected == item_id:
			_recipe_left -= 1

		_refresh()
		_show_result(item_id, result == "burnt")

		# THE BEAT AFTER EVERY FISH, the last one's too: long enough to see how
		# it came out before the next goes on or the fire is cleared. A burn gets
		# longer (burnt_hold) - "burned fish vanished to quickly".
		await get_tree().create_timer(burnt_hold if result == "burnt" else cook_interval).timeout
		if not is_instance_valid(self) or not is_inside_tree() or mine != _run_id:
			return

	_running = false
	_looping = false

	# THE TALLY IS THE ONE SENTENCE WORTH SAYING, because it is the only thing
	# on this screen the art cannot show: what happened across a whole stack,
	# after the stack is gone. It floats and fades like any other event.
	if cooked > 0 or burnt > 0:
		if burnt > 0:
			_flash("Cooked %d, burnt %d." % [cooked, burnt])
		else:
			_flash("Cooked %d." % cooked)
	_selected = ""
	_selected_recipe = false
	_recipe_left = 0
	_update_badge()
	# The Stop on a meal's row goes back to Cook all.
	_refresh_recipes()
	_end_fire()
	run_ended.emit()


func _update_badge() -> void:
	# A BADGE ON THE LEFT OF THE TITLE, as wide as the × on the right, so
	# "COOKING" sits in the middle like every other window's title (day 1: the
	# header read "Cooking  Cooking 1  ×").
	var level: int = _cooking_level()
	skill_label.text = "Lv %d" % level
	skill_label.tooltip_text = "Your cooking level is %d" % level


func _cook_one(item_id: String, recipe: bool = false) -> String:
	# A MEAL TAKES THIS SAME PATH (0.74.0), to its own route: the request names
	# the recipe and nothing else, and the answer is /api/cooking/cook's - the
	# bag, the skill, burnt or not - so everything below it is the fish's.
	# One function rather than a copy beside it, because a copy is the one that
	# misses the next fix (the 0.56.0 bag-and-skill one below, for instance).
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

	var path: String = RECIPE_PATH if recipe else COOK_PATH
	var body: Dictionary = {"slot": CharacterData.active_character_index}
	body["recipe_id" if recipe else "item_id"] = item_id
	var res: Dictionary = await Api.post(path, body, COOK_TIMEOUT)

	# PAST AN AWAIT, and the tween may be dead because the node was freed.
	if bar != null and is_instance_valid(bar) and bar.is_running():
		await bar.finished

	_cooking = false

	if not is_instance_valid(self) or not is_inside_tree():
		return "refused"

	# Re-collapse: valid a moment ago is not valid now.
	player = player if is_instance_valid(player) else null

	# The panel may have been re-pointed at a different firepit, or shut, while
	# this was in flight. The fish is cooked on the server either way, and this
	# screen must not narrate it over whatever it is showing now - BUT THE BAG
	# AND THE SKILL STILL TAKE THE ANSWER (0.56.0). Thrown away, the bag went on
	# showing the raw fish and no cooked one until something else redrew it.
	if _firepit != firepit:
		if res.get("ok", false) and res.get("data", {}) is Dictionary:
			var quiet: Dictionary = res["data"]
			if _apply_inventory(quiet) and player != null:
				CharacterData.save_character_state(player)
			_apply_skill(quiet)
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


# =============================================================================
# THE RECIPES VIEW (0.74.0)
# =============================================================================
# The owner: cooking should grow past fish, with "meals that combine 2-3
# ingredients, heal more and give a short buff", and "i want to make recipes
# people can make with the food also". The second tab lists every meal the
# catalogue has, by the cooking level it needs: what it takes, with how many of
# each the bag holds against how many it needs, the level, what it heals and
# what it adds while it lasts - and Cook, and Cook all.
#
# THE FIRE IS STILL THE INTERFACE. A meal goes on as a fish does (_show_fish),
# comes off cooked or burnt the same way (_show_result), and is cooked by the
# same loop (_cook_run), one request a meal. Two things differ: the route,
# /api/cooking/recipe, and that a meal run counts down how many it was asked
# for (_recipe_left) where a fish run cooks to the end of the stack.
#
# THE ROWS ARE A VIEW OF THE BAG, like the fish grid. Nothing moves into this
# panel: the request names the meal, and the server takes the ingredients and
# rolls the burn. The have/need counts are read off the backpack the server's
# last answer drew, again after every meal - so a Bone Broth just cooked is
# counted at once on the Shadowcap Soup that takes it.

static func meals() -> Array[ItemData]:
	"""Every meal in the catalogue - an item with a recipe (ItemData.is_meal())
	- by the cooking level it needs, then by name."""
	var out: Array[ItemData] = []
	for data in ItemRegistry.get_all_items():
		if data != null and data.is_meal():
			out.append(data)
	out.sort_custom(func(a: ItemData, b: ItemData) -> bool:
		if a.recipe_level != b.recipe_level:
			return a.recipe_level < b.recipe_level
		return a.display_name < b.display_name)
	return out


static func makeable(meal: ItemData, held: Dictionary) -> int:
	"""How many of this meal the bag holds the ingredients for: the fewest of any
	one ingredient's have over need. 0 for a meal that lists none."""
	if meal == null or meal.recipe_ingredients.is_empty():
		return 0
	var most: int = -1
	for id in meal.recipe_ingredients:
		var need: int = maxi(int(meal.recipe_ingredients[id]), 1)
		@warning_ignore("integer_division")
		var times: int = int(held.get(str(id), 0)) / need
		most = times if most < 0 else mini(most, times)
	return maxi(most, 0)


static func first_short(meal: ItemData, held: Dictionary) -> String:
	"""The first ingredient the bag holds too few of, or "" when none is."""
	if meal == null:
		return ""
	for id in meal.recipe_ingredients:
		if int(held.get(str(id), 0)) < maxi(int(meal.recipe_ingredients[id]), 1):
			return str(id)
	return ""


static func heal_text(meal: ItemData) -> String:
	"""What it restores, short: "Heals 45", or "" for a meal that restores
	nothing."""
	if meal == null or int(meal.restore_amount) <= 0:
		return ""
	match int(meal.restore_target):
		ItemData.RestoreTarget.HP:
			return "Heals %d" % int(meal.restore_amount)
		ItemData.RestoreTarget.MANA:
			return "Restores %d mana" % int(meal.restore_amount)
		ItemData.RestoreTarget.STAMINA:
			return "Restores %d stamina" % int(meal.restore_amount)
	return ""


static func item_name(item_id: String) -> String:
	"""An ingredient's name, or its id for one this catalogue does not know -
	asked with has_item(), because get_item() warns and hands back a stand-in."""
	if ItemRegistry.has_item(item_id):
		return ItemRegistry.get_item(item_id).display_name
	return item_id


func _bag_counts() -> Dictionary:
	"""item_id -> how many the backpack holds, every cell of it added up - the
	same count the server's carry check makes (keys included)."""
	var out: Dictionary = {}
	var backpack: Node = _player_backpack()
	if backpack == null or not backpack.has_method("get_all_stacks"):
		return out
	for stack in backpack.get_all_stacks():
		if stack == null or stack.data == null:
			continue
		var id: String = str(stack.data.item_id)
		out[id] = int(out.get(id, 0)) + int(stack.quantity)
	return out


# ---- the tabs ----------------------------------------------------------------

func _set_view(which: int) -> void:
	"""A tab pressed: show it, and fit the window to it where it stands.

	WHERE IT STANDS IS READ NOW, before anything moves. The list appearing makes
	the window's content bigger, and PanelWindow grows a window to its content
	from its left edge, a frame later - read after that, the middle would
	already have slid right by half the new width."""
	var middle: float = position.x + size.x * 0.5
	var top: float = position.y
	_show_view(which)
	if visible:
		_refit_in_place.call_deferred(middle, top)


func _show_view(which: int) -> void:
	_view = which
	# BOTH SET EVERY TIME, because a toggle button pressed while already down
	# would otherwise come up, and a row of tabs with none down says nothing.
	if fish_tab != null:
		fish_tab.set_pressed_no_signal(which == View.FISH)
	if recipes_tab != null:
		recipes_tab.set_pressed_no_signal(which == View.RECIPES)
	(fish_grid as Control).visible = which == View.FISH
	if recipe_scroll != null:
		recipe_scroll.visible = which == View.RECIPES
	if which == View.RECIPES:
		_refresh_recipes()


func _refit_in_place(middle: float, top: float) -> void:
	"""The window as big as what it now holds, its top and its middle where they
	were. A tab changes how wide the window is, and one that grew from its left
	edge would walk across the screen a click at a time; one that grew from its
	middle would move the tabs out from under the pointer that just clicked."""
	if not is_instance_valid(self) or not visible:
		return
	_fit_recipe_scroll()
	var want: Vector2 = PanelWindow.content_minimum(self)
	var screen: Vector2 = get_viewport_rect().size
	var fitted: Rect2 = PanelWindow.fit_to(Rect2(Vector2(floorf(middle - want.x * 0.5), top), want),
		screen, want)
	position = fitted.position
	size = fitted.size


func recipe_list_cap() -> float:
	"""How tall RECIPE_ROWS_SHOWN rows of the list are, as they are drawn now."""
	if recipe_list == null or recipe_list.get_child_count() == 0:
		return 0.0
	var row: float = (recipe_list.get_child(0) as Control).get_combined_minimum_size().y
	var gap: float = float(recipe_list.get_theme_constant("separation"))
	return row * RECIPE_ROWS_SHOWN + gap * (RECIPE_ROWS_SHOWN - 1)


func _fit_recipe_scroll() -> void:
	"""The list as tall as its rows, up to RECIPE_ROWS_SHOWN of them, past which
	it scrolls - and never so tall the window would leave the screen."""
	if recipe_scroll == null or recipe_list == null:
		return
	var height: float = minf(recipe_list.get_combined_minimum_size().y, recipe_list_cap())
	if is_inside_tree() and recipe_scroll.visible:
		# THE REST OF THE WINDOW, as PanelWindow.refit_scrolls() measures it:
		# what the window needs less what the list adds.
		var rest: float = PanelWindow.content_minimum(self).y - recipe_scroll.get_combined_minimum_size().y
		height = PanelWindow.scroll_height(height, rest, get_viewport_rect().size.y)
	if absf(recipe_scroll.custom_minimum_size.y - height) > 0.5:
		recipe_scroll.custom_minimum_size.y = height


# ---- the rows ----------------------------------------------------------------

func _build_recipe_rows() -> void:
	"""A row a meal, built again only when the catalogue's meals are not the
	ones the list already shows."""
	if recipe_list == null:
		return
	var list: Array[ItemData] = meals()
	var ids: Array = []
	for meal in list:
		ids.append(meal.item_id)
	if ids == _recipe_order:
		return
	for child in recipe_list.get_children():
		recipe_list.remove_child(child)
		child.queue_free()
	_recipe_rows.clear()
	_recipe_order = ids
	for meal in list:
		recipe_list.add_child(_make_recipe_row(meal))


func _label(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label


func _icon(texture: Texture2D, tint: Color, side: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.modulate = tint
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(side, side)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _make_recipe_row(meal: ItemData) -> Control:
	"""One meal: its picture, its name, what it heals and adds, what it takes
	with have/need under that, and on the right the level and the buttons.

	BUILT IN CODE, not a scene of its own, for the reason the tooltip's rarity
	line is: it is nineteen of one small shape, filled from data, and a scene
	would be a second file to keep in step with the dictionary below."""
	var row := PanelContainer.new()
	row.name = "recipe_" + meal.item_id
	row.theme_type_variation = &"PanelSub"
	# PASS, so the wheel over a row still scrolls the list it is in.
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 5)
	row.add_child(margin)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 10)
	margin.add_child(line)

	var picture: TextureRect = _icon(meal.icon, meal.icon_tint, 32.0)
	picture.name = "icon"
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(picture)

	var middle := VBoxContainer.new()
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 2)
	line.add_child(middle)
	var title: Label = _label(meal.display_name, 14, LEVEL_OPEN)
	title.name = "name"
	middle.add_child(title)

	# WHAT IT DOES: the heal, then the buff in its own colour - the colour the
	# HUD's chip wears while it lasts (FoodBuff.colour_for()).
	var effects := HBoxContainer.new()
	effects.name = "effects"
	effects.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effects.add_theme_constant_override("separation", 8)
	middle.add_child(effects)
	var heal: Label = _label(heal_text(meal), 12, Color(0.9, 0.85, 0.75))
	heal.name = "heal"
	effects.add_child(heal)
	var buff: Label = _label(meal.buff_text(), 12, FoodBuff.colour_for(int(meal.buff_kind)))
	buff.name = "buff"
	effects.add_child(buff)

	# WHAT IT TAKES, each ingredient's picture and have/need. A meal that is
	# itself an ingredient (a Bone Broth in a Shadowcap Soup) is one like any
	# other: its count is the bag's.
	var takes := HBoxContainer.new()
	takes.name = "ingredients"
	takes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	takes.add_theme_constant_override("separation", 10)
	middle.add_child(takes)
	var counts: Dictionary = {}
	var cells: Dictionary = {}
	for id in meal.recipe_ingredients:
		var key: String = str(id)
		var cell := HBoxContainer.new()
		cell.name = "ing_" + key
		# PASS, NOT IGNORE: the name of what it is is on hover.
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.add_theme_constant_override("separation", 3)
		var known: bool = ItemRegistry.has_item(key)
		var part: ItemData = ItemRegistry.get_item(key) if known else null
		var picture_of: TextureRect = _icon(part.icon if part != null else null,
			part.icon_tint if part != null else Color.WHITE, 16.0)
		picture_of.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(picture_of)
		var count: Label = _label("", 12, HAVE_SHORT)
		count.name = "count"
		cell.add_child(count)
		takes.add_child(cell)
		counts[key] = count
		cells[key] = cell

	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 4)
	line.add_child(right)
	var level: Label = _label("Lv %d" % meal.recipe_level, 12, LEVEL_OPEN)
	level.name = "level"
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Hover says it in words, so a grey "Lv 40" is never a riddle.
	level.mouse_filter = Control.MOUSE_FILTER_PASS
	level.tooltip_text = "Needs cooking level %d" % meal.recipe_level
	right.add_child(level)
	var buttons := HBoxContainer.new()
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.add_theme_constant_override("separation", 4)
	right.add_child(buttons)
	var one := Button.new()
	one.name = "cook"
	one.text = "Cook"
	one.focus_mode = Control.FOCUS_NONE
	one.custom_minimum_size = Vector2(52, 24)
	one.add_theme_font_size_override("font_size", 12)
	one.pressed.connect(_on_recipe_pressed.bind(meal.item_id, false))
	buttons.add_child(one)
	var every := Button.new()
	every.name = "cookall"
	every.text = "Cook all"
	every.focus_mode = Control.FOCUS_NONE
	every.custom_minimum_size = Vector2(92, 24)
	every.add_theme_font_size_override("font_size", 12)
	every.pressed.connect(_on_recipe_pressed.bind(meal.item_id, true))
	buttons.add_child(every)

	_recipe_rows[meal.item_id] = {
		"meal": meal, "row": row, "icon": picture, "name": title, "level": level,
		"counts": counts, "cells": cells, "cook": one, "cookall": every,
	}
	return row


func _refresh_recipes() -> void:
	"""Every row's counts, colours and buttons, from the bag and the level as
	they are now."""
	if recipe_list == null or _recipe_rows.is_empty():
		_fit_recipe_scroll()
		return
	var held: Dictionary = _bag_counts()
	var level: int = _cooking_level()
	for id in _recipe_rows:
		var parts: Dictionary = _recipe_rows[id]
		var meal: ItemData = parts["meal"]
		var open: bool = level >= meal.recipe_level
		var can: int = makeable(meal, held)
		var mine: bool = _running and _selected_recipe and _selected == str(id)

		(parts["level"] as Label).add_theme_color_override("font_color", LEVEL_OPEN if open else LEVEL_LOCKED)
		(parts["name"] as Label).add_theme_color_override("font_color", LEVEL_OPEN if open else LEVEL_LOCKED)
		(parts["icon"] as TextureRect).modulate = meal.icon_tint if open else meal.icon_tint * LOCKED_ROW

		for key in parts["counts"]:
			var need: int = maxi(int(meal.recipe_ingredients[key]), 1)
			var have: int = int(held.get(key, 0))
			var count: Label = parts["counts"][key]
			count.text = "%d/%d" % [have, need]
			count.add_theme_color_override("font_color", HAVE_ENOUGH if have >= need else HAVE_SHORT)
			(parts["cells"][key] as Control).tooltip_text = "%s: you have %d, it takes %d" % [item_name(key), have, need]

		# WHY A BUTTON IS GREY, on the button: the level first, because no
		# amount of shopping gets you past it, then what the bag is short of.
		var why: String = ""
		if not open:
			why = "Needs cooking level %d" % meal.recipe_level
		elif can <= 0:
			why = "You are missing %s" % item_name(first_short(meal, held))
		var cook: Button = parts["cook"]
		var every: Button = parts["cookall"]
		cook.disabled = why != "" or mine
		cook.tooltip_text = why if why != "" else "Cook one %s" % meal.display_name
		# THE BUTTON THAT STARTED A RUN STOPS IT, the way a second click on the
		# fish on the fire takes it off.
		every.disabled = why != "" and not mine
		if mine:
			every.text = "Stop"
			every.tooltip_text = "Stop after the one on the fire"
		else:
			every.text = "Cook all (%d)" % can if can > 1 else "Cook all"
			every.tooltip_text = why if why != "" else "Cook %s %d times, one after another" % [meal.display_name, can]
	_fit_recipe_scroll()


func _on_recipe_pressed(recipe_id: String, every: bool) -> void:
	if every and _running and _selected_recipe and _selected == recipe_id:
		_stop_run()
		_refresh_recipes()
		return
	var meal: ItemData = ItemRegistry.get_item(recipe_id)
	var count: int = makeable(meal, _bag_counts()) if every else 1
	await _start_recipe(recipe_id, count)


func _start_recipe(recipe_id: String, count: int) -> void:
	"""Put a meal on the fire, `count` times over: _start_run() for a recipe."""
	if not ItemRegistry.has_item(recipe_id):
		return
	var meal: ItemData = ItemRegistry.get_item(recipe_id)
	if meal == null or not meal.is_meal():
		return

	# CHECKED HERE ONLY TO EXPLAIN THE REFUSAL, as the fish's level is: the
	# server checks both again, and its answer is the one that counts.
	if _cooking_level() < meal.recipe_level:
		_flash("Needs cooking level %d." % meal.recipe_level)
		return
	var short: String = first_short(meal, _bag_counts())
	if short != "":
		_flash("You are missing %s." % item_name(short))
		return

	var switching: bool = _looping and recipe_id != _selected
	_selected = recipe_id
	_selected_recipe = true
	_recipe_left = maxi(count, 1)
	_running = true
	if _looping:
		# A RUN IS ALREADY ON THE FIRE: what is on it finishes, and this is
		# next - the same as clicking another fish.
		if switching:
			_flash("Next: %s" % meal.display_name)
		_refresh_recipes()
		return

	_refresh_recipes()
	await _cook_run()
