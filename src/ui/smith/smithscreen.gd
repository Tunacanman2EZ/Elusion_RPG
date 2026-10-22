# smithscreen.gd - the window the town's anvil opens. Two things happen here:
# a piece of gear is TEMPERED - its rolled stats raised a few points, for
# materials and gold - and the ROYAL CERTIFICATION is earned, rank by rank,
# which is what lets the hammer reach the higher tiers.
#
# The owner: "a new smith spends materials plus gold to upgrade gear", and
# "Upgrades that cost materials instead of only gold, plus a 'Royal
# Certification' step to reach higher tiers ... the certification fits the
# kingdom theme".
#
# BUILT ON cookingscreen.gd's SHAPE, which is built on lootbaginventory.gd's,
# down to the guard names: one request in flight at a time, everything captured
# before the await, the server's arrays applied rather than local deltas, and
# exactly one close path. Those are the other panels that change items through
# the server, and a third shape for the same job is how one of them ends up
# with the bug the other two already fixed.
#
#
# THE SERVER DECIDES EVERY NUMBER ON THIS SCREEN.
#
# What a temper would do and what it costs come from POST /api/smith/quote -
# the percent of each stat now and after, the gold, each material with how
# many you carry, and the certification the tier needs - and the temper itself
# is POST /api/smith/temper. The ranks, what each costs and which you hold come
# from GET /api/smith/status, and earning one is POST /api/smith/certify. Gold
# and items are the server's (docs/inventoryauthority.md), and the economy
# rules can scale the smith's prices on the server without a build, so a cost
# this client worked out for itself would be a second answer that is wrong the
# day the owner changes a number.
#
# TWO REFUSALS ARE SEEN HERE BEFORE ANY REQUEST. A Perfect piece - every stat
# already at QUALITY_PERFECT - and a piece whose every stat is at the temper
# cap have nothing for the hammer to add. The server refuses both too; this
# window says so the moment one is picked, rather than asking for a quote whose
# only content would be "no".
#
#
# THE GEAR NEVER MOVES INTO THIS PANEL. The grid is a VIEW of the backpack, its
# slots stamped "lootbag" so InventorySlot refuses to start a drag from one -
# the same trick, for the same reason, as the cooking screen. A temper names
# the bag cell it means AND the item it expects in it, so a bag that changed
# underneath (a trade, a loot take) is refused by the server rather than
# tempering whatever has moved into that cell.
extends Control


# =============================================================================
# CONSTANTS
# =============================================================================

# The drawn arrow between a stat as it is and as it will be. A mark rather than
# a letter, because the game's font has no arrow and a browser draws a missing
# letter as a box (see marks.gd).
const Marks := preload("res://src/shared/marks.gd")

# A request the player made and is watching, like a cook or a loot take: more
# patience than a background poll, not so much that a stall reads as a hang.
const REQUEST_TIMEOUT := 6.0

# One row of six, like the cooking screen; a second row appears only when the
# bag holds more pieces than fit, so nothing is ever hidden.
const GRID_COLUMNS := 6

# THE HOUSE COLOURS, copied rather than chosen again: muted text and a gold
# figure are written this way in every panel (see kingdomboard.gd's note on
# RANK_COLOUR), and the better / worse pair is the tooltip's own comparison.
const MUTED := Color(0.7, 0.66, 0.6)
const GOLD := Color(1, 0.9, 0.5)
const TITLE := Color(0.95, 0.85, 0.6)
const ENOUGH := ItemTooltip.COMPARE_BETTER
const SHORT := ItemTooltip.COMPARE_WORSE
const SAME := ItemTooltip.COMPARE_SAME

# The chosen piece wears a bright frame just outside its socket. InventorySlot
# has no selected look of its own (_update_style() says why one was removed),
# and the socket is art that must not be repainted - so the frame is drawn
# round it, a few pixels out, clear of the rarity frame drawn inside it.
const CHOSEN_FRAME := Color(1.0, 0.95, 0.78)

# A piece the hammer cannot help - Perfect, or tempered all the way - is still
# shown, so the player can see why it is not offered, but dimmed.
const REFUSED_TINT := Color(0.55, 0.55, 0.55)

# The anvil, in the header badge. A PATH AND A LAZY load(), not a preload(), for
# the reason kingdomboard.gd gives at GOLD_ICON_PATH: the art lives in the
# private pack, and a preload of a file a public clone does not have stops the
# whole script compiling. A missing badge is what a missing picture should cost.
const ANVIL_ICON_PATH := "res://art/pack/smith/anvil.png"

# Words for the server's refusals that arrive without a message of their own.
# The server's message always wins when there is one.
const REFUSAL_WORDS := {
	0: "No connection - try again.",
	403: "The smith will not do that for you yet.",
	404: "That piece is not where it was in your bag.",
	409: "Your bag changed. Pick the piece again.",
	429: "Slow down.",
}


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var close_button: Button = %closebutton
@onready var rank_badge: Control = %rankbadge
@onready var rank_icon: TextureRect = %rankicon
@onready var temper_tab: Button = %tempertab
@onready var certify_tab: Button = %certifytab
@onready var temper_view: Control = %temperview
@onready var certify_view: Control = %certifyview
@onready var gear_grid: Node = %geargrid
@onready var piece_icon: TextureRect = %pieceicon
@onready var piece_name: Label = %piecename
@onready var piece_quality: Label = %piecequality
@onready var stat_grid: GridContainer = %statgrid
@onready var cost_separator: Control = %costseparator
@onready var cost_grid: GridContainer = %costgrid
@onready var cert_line: Label = %certline
@onready var temper_notice: Label = %tempernotice
@onready var temper_button: Button = %temperbutton
@onready var rank_label: Label = %ranklabel
@onready var rank_rows: VBoxContainer = %rankrows
@onready var notice_label: Label = %noticelabel


# =============================================================================
# STATE
# =============================================================================

var _anvil: Node = null
var _player: Node = null

# The last answer from /api/smith/status: the rank held, the four ranks and what
# each costs, and the per-tier temper costs. Empty until it arrives.
var _status: Dictionary = {}

# Grid index -> {"cell": bag cell, "item_id": the piece in it}. The grid packs
# the gear into its first cells, so the bag cell a temper names is read from
# here and never from the grid's own index.
var _gear: Array = []

# The bag cell on the anvil and the piece expected in it, or -1 / "".
var _chosen_cell: int = -1
var _chosen_id: String = ""

# The quote for the piece on the anvil, or {} while there is none.
var _quote: Dictionary = {}

# ONE REQUEST AT A TIME, the cooking screen's _cooking and the loot panel's
# _taking. A second temper sent while the first is out would be two claims on a
# bag and a purse neither had seen the state of.
var _busy: bool = false

# Which opening of the window this is. Closing or reopening moves it on, so an
# answer still on its way from before lands quietly instead of drawing itself
# over whatever the window shows now - the cooking screen's _run_id.
var _view: int = 0

# Which quote is the newest. Clicking through three pieces quickly sends three
# quotes, and only the last one asked for may draw.
var _quote_ticket: int = 0


# Drag by the header, resize from any edge - the one component every window
# uses. HELD IN A MEMBER: it is a RefCounted carrying the drag state and the
# connections, and letting it go frees it.
var _window: PanelWindow


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_window = PanelWindow.attach(self, "smith")
	close_button.pressed.connect(close_panel)
	temper_tab.toggled.connect(_on_tab_toggled)
	certify_tab.toggled.connect(_on_tab_toggled)
	temper_button.pressed.connect(_on_temper_pressed)

	if gear_grid.has_signal("slot_clicked"):
		gear_grid.slot_clicked.connect(_on_gear_clicked)
	# A double-click is a click here. The grid is a view; there is nothing in it
	# to equip or deposit, so the second click must not fall through to nothing.
	if gear_grid.has_signal("slot_double_clicked"):
		gear_grid.slot_double_clicked.connect(_on_gear_clicked)

	if ResourceLoader.exists(ANVIL_ICON_PATH):
		rank_icon.texture = load(ANVIL_ICON_PATH) as Texture2D

	_show_nothing_chosen()
	visible = false


func open_for_anvil(anvil: Node, player: Node) -> void:
	"""Point the window at an anvil and show it. Awaitable: it returns once the
	smith's status has been read, which is what the suite waits on."""
	_disconnect_anvil()
	_anvil = anvil
	_player = player
	_view += 1
	_busy = false
	_chosen_cell = -1
	_chosen_id = ""
	_quote = {}
	_set_notice("", false)

	temper_tab.button_pressed = true
	_show_tab(true)
	_refresh_gear()
	_show_nothing_chosen()
	_render_ranks()

	visible = true
	# VISIBLE BEFORE SIZING: a hidden control cannot report its real minimum.
	_fit_and_centre()
	_settle(_view, true)

	if _anvil != null and _anvil.has_signal("player_left_range") \
			and not _anvil.player_left_range.is_connected(close_panel):
		_anvil.player_left_range.connect(close_panel)

	await _load_status()


func _fit_and_centre() -> void:
	"""As big as what is in it, in the middle of the screen - the cooking
	window's rule and its reason: the root is a plain Control, and reset_size()
	on one does nothing. A smith window belongs to the anvil you are standing
	at, so it opens in front of you, and can still be dragged anywhere."""
	size = PanelWindow.content_minimum(self)
	var screen: Vector2 = get_viewport_rect().size
	position = ((screen - size) * 0.5).floor()


func _settle(view: int, centre: bool) -> void:
	"""The same fit again, a frame later, once the containers have laid the
	window out. A wrapping label measured before its first layout has no width
	yet and asks for a word to a line - measured in the suite, the window
	opened 800 px tall and was 455 a frame later. PanelWindow grows a window to
	what it asks for and never shrinks one, so without this the first, wrong
	answer is the one that stays."""
	await get_tree().process_frame
	if not is_instance_valid(self) or not is_inside_tree() or view != _view or not visible:
		return
	if centre:
		_fit_and_centre()
	else:
		_fit_to_content()


func _fit_to_content() -> void:
	# The window follows its content where it stands - a tab with more in it,
	# a second row of gear - in both directions. PanelWindow only ever grows a
	# window, so a tab with less in it would otherwise leave dead space.
	if is_instance_valid(self) and visible:
		size = PanelWindow.content_minimum(self)


# =============================================================================
# CLOSING - ONE PATH, whatever the reason
# =============================================================================

func close_panel() -> void:
	# The X, Escape (through the HUD's one list), walking away from the anvil -
	# all of them arrive here, so the anvil is always told.
	_view += 1
	_busy = false
	if is_instance_valid(_anvil) and _anvil.has_method("notify_panel_closed"):
		_anvil.notify_panel_closed()
	_disconnect_anvil()
	visible = false
	_anvil = null
	_player = null
	_chosen_cell = -1
	_chosen_id = ""
	_quote = {}


func _disconnect_anvil() -> void:
	# This window is built once and re-pointed at whichever anvil opens it, so
	# every connect needs a disconnect at close AND at the top of the next open.
	if is_instance_valid(_anvil) and _anvil.has_signal("player_left_range") \
			and _anvil.player_left_range.is_connected(close_panel):
		_anvil.player_left_range.disconnect(close_panel)


# =============================================================================
# TABS
# =============================================================================

func _on_tab_toggled(_pressed: bool) -> void:
	# Both buttons are in one ButtonGroup, so this fires twice per switch - once
	# for the button let go and once for the one pressed. Reading the pressed
	# one rather than the argument makes the two calls agree.
	_show_tab(temper_tab.button_pressed)


func show_certification() -> void:
	certify_tab.button_pressed = true
	_show_tab(false)


func show_temper() -> void:
	temper_tab.button_pressed = true
	_show_tab(true)


func _show_tab(tempering: bool) -> void:
	temper_view.visible = tempering
	certify_view.visible = not tempering
	_settle(_view, false)


# =============================================================================
# THE GEAR IN THE BAG
# =============================================================================

static func is_gear(data: ItemData) -> bool:
	"""What the anvil takes: a weapon or a piece of armour. The server's own
	test is the same (a WEAPON or ARMOR with quality rolls); a piece that never
	rolled is shown and refused, with the reason."""
	return data != null and (int(data.type) == int(ItemData.Type.WEAPON)
		or int(data.type) == int(ItemData.Type.ARMOR))


static func refusal_for(data: ItemData, cap: int) -> String:
	"""Why the hammer can do nothing for this piece, or "" when it can.

	These are the server's own two refusals of a piece ("already perfect",
	"fully tempered") and the plain piece it refuses for having no rolls,
	worded for the player and decided from the piece itself, so they show the
	moment it is picked."""
	if data == null:
		return "Pick a piece from your bag."
	if not data.is_rolled():
		return "This piece never rolled its stats, so there is nothing for the hammer to raise."
	if data.is_perfect():
		return "Perfect: every stat is already at %d%%. The hammer has nothing to add." \
			% GameConstants.QUALITY_PERFECT
	var below_cap: bool = false
	for percent in data.rolls.values():
		if int(percent) < cap:
			below_cap = true
	if not below_cap:
		return "Fully tempered: every stat is at %d%%, as far as the hammer goes." % cap
	return ""


func _refresh_gear() -> void:
	"""The bag's weapons and armour, packed into the grid in bag order."""
	_gear = gear_in(_player_backpack())
	var rows: int = rows_for(_gear.size())
	if gear_grid.has_method("resize_grid") and int(gear_grid.get("grid_height")) != rows:
		gear_grid.resize_grid(GRID_COLUMNS, rows)
		if visible:
			_fit_to_content.call_deferred()
	var cells: Array = []
	cells.resize(GRID_COLUMNS * rows)
	for i in range(mini(_gear.size(), cells.size())):
		cells[i] = {"item_id": _gear[i]["item_id"], "quantity": 1}
	if gear_grid.has_method("load_save_array"):
		gear_grid.load_save_array(cells)
	# Re-stamped after every load, because a resize builds the slots again.
	if gear_grid.has_method("set_slot_type"):
		gear_grid.set_slot_type("lootbag")
	_paint_grid()


static func gear_in(backpack: Node) -> Array:
	"""[{"cell", "item_id"}] for every weapon and piece of armour in the bag,
	the hotbar's keys included (they are the bag's cells 20-29, and the server
	counts them as the bag)."""
	var out: Array = []
	if backpack == null or not backpack.has_method("get_stack_at"):
		return out
	var count: int = 0
	if "slots" in backpack:
		count = (backpack.get("slots") as Array).size()
	for i in range(count):
		var stack: ItemStack = backpack.get_stack_at(i)
		if stack == null or stack.data == null or not is_gear(stack.data):
			continue
		out.append({"cell": i, "item_id": str(stack.data.item_id)})
	return out


static func rows_for(pieces: int) -> int:
	@warning_ignore("integer_division")
	return maxi(1, (pieces + GRID_COLUMNS - 1) / GRID_COLUMNS)


func _paint_grid() -> void:
	# The chosen piece warmed, the ones the hammer cannot help dimmed. Set both
	# ways round on every slot, because a slot that was the chosen one a moment
	# ago keeps its tint until something takes it off.
	if not ("slots" in gear_grid):
		return
	var slots: Array = gear_grid.get("slots")
	for i in range(slots.size()):
		var slot: InventorySlot = slots[i]
		var chosen: bool = i < _gear.size() and int(_gear[i]["cell"]) == _chosen_cell
		_chosen_frame(slot).visible = chosen
		if slot.icon_rect == null or slot.is_empty():
			continue
		var refused: bool = refusal_for(slot.stack.data, _temper_cap()) != ""
		slot.icon_rect.modulate = slot.stack.data.icon_tint * (REFUSED_TINT if refused else Color.WHITE)


static func _chosen_frame(slot: InventorySlot) -> Panel:
	"""The frame round a chosen slot, made the first time it is asked for. A
	child of the slot, so it is freed with it when the grid is rebuilt."""
	var frame: Panel = slot.get_node_or_null("chosenframe") as Panel
	if frame != null:
		return frame
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.set_expand_margin_all(3)
	box.border_color = CHOSEN_FRAME
	frame = Panel.new()
	frame.name = "chosenframe"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.visible = false
	frame.add_theme_stylebox_override("panel", box)
	slot.add_child(frame)
	return frame


func _player_backpack() -> Node:
	# The group-lookup idiom the cooking screen and the loot panel use.
	if not is_inside_tree():
		return null
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return null
	var inv_screen: Node = hud.get("inventory_screen") if "inventory_screen" in hud else null
	if inv_screen == null:
		return null
	return inv_screen.get_node_or_null("%inventorycontainer")


func _on_gear_clicked(slot: Object) -> void:
	if slot == null or not (slot is InventorySlot) or (slot as InventorySlot).is_empty():
		return
	var index: int = (slot as InventorySlot).slot_index
	if index < 0 or index >= _gear.size():
		return
	await choose_cell(int(_gear[index]["cell"]))


# =============================================================================
# THE PIECE ON THE ANVIL
# =============================================================================

func choose_cell(cell: int) -> void:
	"""Put the piece in this bag cell on the anvil and ask what tempering it
	would do. Awaitable: it returns once the quote has drawn (or been refused)."""
	var backpack: Node = _player_backpack()
	var stack: ItemStack = backpack.get_stack_at(cell) if backpack != null else null
	if stack == null or stack.data == null or not is_gear(stack.data):
		_chosen_cell = -1
		_chosen_id = ""
		_quote = {}
		_show_nothing_chosen()
		_paint_grid()
		return

	_chosen_cell = cell
	_chosen_id = str(stack.data.item_id)
	_quote = {}
	_quote_ticket += 1
	_paint_grid()
	_show_piece(stack.data)

	var refusal: String = refusal_for(stack.data, _temper_cap())
	if refusal != "":
		# REFUSED HERE, AND NO QUOTE IS ASKED FOR. See the header.
		_show_refusal(refusal)
		return

	_set_temper_notice("Asking the smith...", false)
	await _ask_quote()


func _ask_quote() -> void:
	var ticket: int = _quote_ticket
	var view: int = _view
	var cell: int = _chosen_cell
	var item_id: String = _chosen_id
	var res: Dictionary = await Api.post("/api/smith/quote", {
		"slot": CharacterData.active_character_index,
		"position": cell,
		"item_id": item_id,
	}, REQUEST_TIMEOUT)

	# PAST AN AWAIT. The window may have closed, reopened, or moved on to
	# another piece while this was out; only the newest quote may draw.
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if view != _view or ticket != _quote_ticket:
		return

	if not res.get("ok", false):
		_quote = {}
		# THE CELL DID NOT HOLD WHAT THIS WINDOW SAW IN IT - a trade or a loot
		# take moved the bag - and the refusal carries the bag the server holds.
		# Taken, so the grid and the next pick are right.
		var refused: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
		if refused.get("resync") is Dictionary:
			_adopt_resync(refused, _player if is_instance_valid(_player) else null)
			_refresh_gear()
		_show_refusal(_refusal_text(res))
		return
	var data: Variant = res.get("data", {})
	_quote = data if data is Dictionary else {}
	_show_quote()


func _show_nothing_chosen() -> void:
	piece_icon.texture = null
	piece_name.text = "Nothing on the anvil"
	piece_name.add_theme_color_override("font_color", TITLE)
	piece_quality.text = "Pick a weapon or a piece of armour above." if not _gear.is_empty() \
		else "Bring a weapon or a piece of armour in your bag."
	_clear(stat_grid)
	_clear(cost_grid)
	cost_separator.visible = false
	cert_line.text = ""
	temper_button.disabled = true
	_set_temper_notice("", false)


func _show_piece(data: ItemData) -> void:
	"""The piece's picture, name and roll - drawn at once from the piece itself,
	before the quote arrives, so a click never looks like it did nothing."""
	piece_icon.texture = data.icon
	piece_icon.modulate = data.icon_tint
	piece_name.text = data.display_name
	var colour: Color = TITLE
	if int(data.tier) >= GameConstants.RARITY_FRAME_MIN_TIER:
		colour = GameConstants.rarity_colour(int(data.tier))
	if data.is_perfect():
		colour = GameConstants.QUALITY_PERFECT_COLOUR
	piece_name.add_theme_color_override("font_color", colour)
	var line: String = ItemTooltip.rarity_text(data)
	if data.resistance_text() != "":
		line += "  -  " + data.resistance_text()
	piece_quality.text = line

	# THE STATS AS THEY ARE, with no "after" yet. The quote fills in the rest.
	var now: Dictionary = data.rolls.duplicate()
	_fill_stats(stat_rows(data, now, now), false)
	_clear(cost_grid)
	cost_separator.visible = false
	cert_line.text = ""
	temper_button.disabled = true


func _show_refusal(reason: String) -> void:
	temper_button.disabled = true
	_set_temper_notice(reason, true)


func _show_quote() -> void:
	var backpack: Node = _player_backpack()
	var stack: ItemStack = backpack.get_stack_at(_chosen_cell) if backpack != null else null
	var data: ItemData = stack.data if stack != null else ItemRegistry.get_item(_chosen_id)
	if data == null:
		_show_nothing_chosen()
		return

	var before: Dictionary = _percents(_quote.get("before", {}))
	var after: Dictionary = _percents(_quote.get("after", {}))
	_fill_stats(stat_rows(data, before, after), true)

	# THE COST, have against need on every line. Gold reads the same way as a
	# material does - what you carry, then what it takes - so one glance down
	# the right-hand column says whether this temper is affordable.
	_clear(cost_grid)
	cost_separator.visible = true
	_cost_header()
	var gold: int = int(_quote.get("gold", 0))
	_cost_row(_gold_icon(gold), "Gold", _purse(), gold, "")
	var materials: Variant = _quote.get("materials", [])
	if materials is Array:
		for entry in materials:
			if not (entry is Dictionary):
				continue
			var id: String = str(entry.get("item_id", ""))
			var item: ItemData = ItemRegistry.get_item(id) if id != "" else null
			_cost_row(item.icon if item != null else null,
				item.display_name if item != null else id,
				int(entry.get("have", 0)), int(entry.get("quantity", 0)),
				item.description if item != null else "")

	# THE CERTIFICATION THIS TIER NEEDS, and whether you hold it.
	var needs: int = int(_quote.get("certification", 0))
	if needs <= 0:
		cert_line.text = "Any smith may temper this tier."
		cert_line.add_theme_color_override("font_color", MUTED)
	elif _rank() >= needs:
		cert_line.text = "Needs a %s - you are one." % _rank_name(needs)
		cert_line.add_theme_color_override("font_color", ENOUGH)
	else:
		cert_line.text = "Needs a %s. Earn it under Royal Certification." % _rank_name(needs)
		cert_line.add_theme_color_override("font_color", SHORT)

	var can: bool = bool(_quote.get("can", false))
	temper_button.disabled = not can or _busy
	if can:
		_set_temper_notice("", false)
	else:
		_set_temper_notice(_sentence(str(_quote.get("reason", ""))), true)


static func stat_rows(data: ItemData, before: Dictionary, after: Dictionary) -> Array:
	"""One row per rolled stat, in the order the tooltip lists them:
	{"label", "now", "now_percent", "then", "then_percent", "raised"}.

	"now" and "then" are the stat itself at each percent - what the piece
	actually does - worked out the way ItemRegistry turns a roll into a number,
	from the catalogue piece under the roll. The percents are the server's."""
	var rows: Array = []
	if data == null:
		return rows
	var base: ItemData = data
	if data.base_id != "" and ItemRegistry.has_item(data.base_id):
		base = ItemRegistry.get_item(data.base_id)
	for spec in ItemTooltip.COMPARED_STATS:
		var field: String = spec[0]
		if not before.has(field):
			continue
		var was: int = int(before[field])
		var will: int = int(after.get(field, was))
		var number: int = int(base.get(field)) if field in base else 0
		rows.append({
			"label": spec[1],
			"suffix": spec[2],
			"now": ItemRegistry.scale_stat(number, was),
			"now_percent": was,
			"then": ItemRegistry.scale_stat(number, will),
			"then_percent": will,
			"raised": will > was,
		})
	return rows


func _fill_stats(rows: Array, with_after: bool) -> void:
	_clear(stat_grid)
	if rows.is_empty():
		return
	# A HEADER ROW, because "52 (104%)" beside "54 (107%)" is two numbers until
	# something says which one is the piece as it is.
	_stat_cell("", MUTED, 11)
	_stat_cell("now", MUTED, 11, HORIZONTAL_ALIGNMENT_RIGHT)
	_stat_cell("", MUTED, 11)
	_stat_cell("tempered" if with_after else "", MUTED, 11, HORIZONTAL_ALIGNMENT_RIGHT)
	for row in rows:
		_stat_cell(str(row["label"]), Color(0.9, 0.85, 0.75), 12)
		_stat_cell(_stat_text(int(row["now"]), int(row["now_percent"]), str(row["suffix"])),
			Color(0.9, 0.85, 0.75), 12, HORIZONTAL_ALIGNMENT_RIGHT)
		if not with_after:
			_stat_cell("", MUTED, 12)
			_stat_cell("", MUTED, 12)
			continue
		var raised: bool = bool(row["raised"])
		stat_grid.add_child(Marks.make("closed", ENOUGH if raised else MUTED, "", 12))
		var then_text: String = _stat_text(int(row["then"]), int(row["then_percent"]), str(row["suffix"])) \
			if raised else "at the cap"
		_stat_cell(then_text, ENOUGH if raised else SAME, 12, HORIZONTAL_ALIGNMENT_RIGHT)


static func _stat_text(number: int, percent: int, suffix: String) -> String:
	return "%s%s (%d%%)" % [GameConstants.commas(number), suffix, percent]


func _stat_cell(text: String, colour: Color, font_size: int,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if align == HORIZONTAL_ALIGNMENT_LEFT \
		else Control.SIZE_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	stat_grid.add_child(label)


func _cost_header() -> void:
	cost_grid.add_child(Control.new())
	var what := Label.new()
	what.text = "Cost"
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	what.add_theme_font_size_override("font_size", 11)
	what.add_theme_color_override("font_color", MUTED)
	cost_grid.add_child(what)
	var head := Label.new()
	head.text = "have / need"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_theme_font_size_override("font_size", 11)
	head.add_theme_color_override("font_color", MUTED)
	cost_grid.add_child(head)


func _cost_row(icon: Texture2D, what: String, have: int, need: int, tip: String) -> void:
	cost_grid.add_child(_icon_rect(icon, 16, tip))
	var name_label := Label.new()
	name_label.text = what
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 12)
	cost_grid.add_child(name_label)
	cost_grid.add_child(_have_need_label(have, need))


static func have_need_text(have: int, need: int) -> String:
	return "%s / %s" % [GameConstants.commas(have), GameConstants.commas(need)]


func _have_need_label(have: int, need: int) -> Label:
	var label := Label.new()
	label.text = have_need_text(have, need)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", ENOUGH if have >= need else SHORT)
	label.tooltip_text = "You have enough." if have >= need \
		else "%s short." % GameConstants.commas(need - have)
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	return label


static func _icon_rect(icon: Texture2D, side: int, tip: String = "") -> TextureRect:
	# EXPAND_IGNORE_SIZE, like every small icon in this project: without it a
	# TextureRect demands its texture's size as a minimum and widens its column.
	var rect := TextureRect.new()
	rect.texture = icon
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.custom_minimum_size = Vector2(side, side)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rect.tooltip_text = tip
	rect.mouse_filter = Control.MOUSE_FILTER_STOP if tip != "" else Control.MOUSE_FILTER_IGNORE
	return rect


static func _gold_icon(amount: int) -> Texture2D:
	return GameConstants.gold_icon_for(maxi(amount, 1))


# =============================================================================
# TEMPERING
# =============================================================================

func _on_temper_pressed() -> void:
	await temper()


func temper() -> void:
	"""Temper the piece on the anvil. Awaitable."""
	if _busy or _chosen_cell < 0 or _quote.is_empty() or not bool(_quote.get("can", false)):
		return
	if not Api.is_logged_in():
		# NO LOCAL FALLBACK - the rule every item-changing panel states. A
		# temper done here because the server could not be asked is a client
		# minting stats by making a request fail.
		_show_refusal("Not connected - the smith cannot work.")
		return

	# Captured before the await, all of it.
	var view: int = _view
	var ticket: int = _quote_ticket
	var cell: int = _chosen_cell
	var was_id: String = _chosen_id
	var was: ItemData = ItemRegistry.get_item(was_id)
	var player: Node = _player if is_instance_valid(_player) else null

	_busy = true
	temper_button.disabled = true
	_set_temper_notice("The hammer rings...", false)

	var res: Dictionary = await Api.post("/api/smith/temper", {
		"slot": CharacterData.active_character_index,
		"position": cell,
		"item_id": was_id,
	}, REQUEST_TIMEOUT)

	if not is_instance_valid(self) or not is_inside_tree():
		return
	_busy = false
	player = player if is_instance_valid(player) else null

	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}

	# THE WINDOW MOVED ON WHILE THE HAMMER WAS DOWN - closed, or reopened at
	# another anvil. The piece is tempered on the server either way, so the bag
	# and the purse still take the answer; only the narration is dropped. The
	# cooking screen learned this the hard way (0.56.0): an answer thrown away
	# left the bag showing the piece as it was until something else redrew it.
	if view != _view:
		if res.get("ok", false):
			_apply_carry(data, player)
		return

	if not res.get("ok", false):
		Audio.play("refused")
		_adopt_resync(data, player)
		_refresh_gear()
		_show_refusal(_refusal_text(res))
		return

	_apply_carry(data, player)
	_adopt_status(data.get("status"))
	Audio.play("coin")

	var now_id: String = str(data.get("item_id", was_id))
	var now: ItemData = ItemRegistry.get_item(now_id)
	_refresh_gear()
	_render_ranks()
	# THE SAME PIECE GOES BACK ON THE ANVIL, quoted afresh, so a second temper
	# is one more press - unless the player picked another while the hammer was
	# down, in which case that one is quoted again against the bag as it is now.
	var again: int = int(data.get("position", cell)) if _quote_ticket == ticket else _chosen_cell
	await choose_cell(again)
	if not is_instance_valid(self) or view != _view:
		return
	if now != null and was != null:
		_set_notice("Tempered: %s, quality %d%% to %d%%." % [
			now.display_name, was.quality_percent(), now.quality_percent()], false)


func _apply_carry(data: Dictionary, player: Node) -> void:
	"""The bag and purse the server sent, applied as they are. The cooking
	screen's _apply_inventory(), and the shop's _write_gold()."""
	var applied: bool = false
	var cells: Variant = data.get("inventory", [])
	if cells is Array and not (cells as Array).is_empty():
		var backpack: Node = _player_backpack()
		if backpack != null and backpack.has_method("load_server_array"):
			backpack.load_server_array(cells)
			applied = true
		else:
			push_warning("SmithScreen: player inventory not found - the server changed it, this screen did not show it")
	if data.has("gold"):
		# THE SERVER'S NUMBER, NOT A DELTA - see Player.set_gold().
		CharacterData.adopt_server_gold({"carried_gold": int(data["gold"])}, player)
	elif applied and player != null:
		# ONLY SAVED IF THE GRID TOOK THE SERVER'S ANSWER, straight from the
		# loot panel: saving after a failed apply would push the bag as it was
		# before over the server's. set_gold() above saves on its own.
		CharacterData.save_character_state(player)


func _adopt_resync(data: Dictionary, player: Node) -> void:
	# THE BAG MOVED UNDER US - a loot take, a trade - and the server sent the one
	# it holds with its refusal. Adopted, so the next click is right; the shop
	# does the same with the same key.
	var resync: Variant = data.get("resync")
	if resync is Dictionary and resync.get("inventory") is Array \
			and not (resync["inventory"] as Array).is_empty():
		CharacterData.apply_server_carry(resync, player)
		var backpack: Node = _player_backpack()
		if backpack != null and backpack.has_method("load_server_array"):
			backpack.load_server_array(resync["inventory"])


# =============================================================================
# THE ROYAL CERTIFICATION
# =============================================================================

func _load_status() -> void:
	var view: int = _view
	var res: Dictionary = await Api.get_json(
		"/api/smith/status?slot=%d" % CharacterData.active_character_index, REQUEST_TIMEOUT)
	if not is_instance_valid(self) or not is_inside_tree() or view != _view:
		return
	if not res.get("ok", false):
		_set_notice(_refusal_text(res), true)
		_render_ranks()
		return
	_adopt_status(res.get("data", {}))
	_render_ranks()
	_paint_grid()


func _adopt_status(status: Variant) -> void:
	# A status is recognised by its ranks, so a temper answer whose "status" is
	# something else entirely is left alone rather than wiping the ranks.
	if status is Dictionary and ((status as Dictionary).has("ranks") or (status as Dictionary).has("rank")):
		_status = status


func _rank() -> int:
	return int(_status.get("rank", 0))


func _ranks() -> Array:
	var out: Array = []
	var listed: Variant = _status.get("ranks", [])
	if listed is Array:
		for entry in listed:
			if entry is Dictionary:
				out.append(entry)
	return out


func _rank_name(rank: int) -> String:
	for entry in _ranks():
		if int(entry.get("rank", 0)) == rank:
			return str(entry.get("name", "rank %d" % rank))
	return "rank %d smith" % rank if rank > 0 else "nobody"


func _temper_cap() -> int:
	return int(_status.get("temper_cap", GameConstants.TEMPER_CAP))


static func tier_words(tier: int) -> String:
	# "Rare gear (tier 3)": the rarity's own name, which is what a player reads
	# on every slot frame and tooltip, with the number for the table above it.
	return "%s gear (tier %d)" % [GameConstants.rarity_name(tier), tier]


func _render_ranks() -> void:
	_clear(rank_rows)
	var ranks: Array = _ranks()
	_paint_badge()
	if ranks.is_empty():
		rank_label.text = "Reading the smith's ledger..." if notice_label.text == "" \
			else "The smith's ledger could not be read."
		rank_label.add_theme_color_override("font_color", MUTED)
		return

	var held: int = _rank()
	var reach: int = _reach(held)
	if held <= 0:
		rank_label.text = "You hold no certification yet. Any smith may temper up to %s." \
			% tier_words(reach)
	else:
		rank_label.text = "You are a %s, and may temper up to %s." % [_rank_name(held), tier_words(reach)]
	rank_label.add_theme_color_override("font_color", TITLE)

	for entry in ranks:
		rank_rows.add_child(_rank_row(entry, held))


func _reach(held: int) -> int:
	"""The highest tier this rank may temper: the top tier whose certification
	is at or below it, read from the server's per-tier costs."""
	var best: int = 0
	var costs: Variant = _status.get("temper_costs", [])
	if costs is Array:
		for entry in costs:
			if entry is Dictionary and int(entry.get("certification", 0)) <= held:
				best = maxi(best, int(entry.get("tier", 0)))
	return best


func _rank_row(entry: Dictionary, held: int) -> Control:
	"""One rank as a card: its name and what it opens, the level it asks, the
	gold and each material with have / need, and - on the next rank only - the
	Earn button. A rank already held says so; a later one says what comes first."""
	var rank: int = int(entry.get("rank", 0))
	var earned: bool = bool(entry.get("earned", false)) or rank <= held
	var is_next: bool = rank == held + 1

	var card := PanelContainer.new()
	card.name = "rank%d" % rank
	card.theme_type_variation = &"PanelSub"
	# PanelSub draws a border and no padding, so the card brings its own - the
	# same 8 and 6 the piece panel on the Temper tab sits in.
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_theme_constant_override("margin_right", 8)
	pad.add_theme_constant_override("margin_top", 5)
	pad.add_theme_constant_override("margin_bottom", 5)
	card.add_child(pad)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	pad.add_child(rows)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	rows.add_child(top)
	var title := Label.new()
	title.name = "title"
	title.text = str(entry.get("name", "Rank %d" % rank))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color",
		GameConstants.QUALITY_PERFECT_COLOUR if earned else TITLE)
	top.add_child(title)

	if earned:
		var done := Label.new()
		done.name = "state"
		done.text = "Earned"
		done.add_theme_font_size_override("font_size", 12)
		done.add_theme_color_override("font_color", ENOUGH)
		done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(done)
	elif is_next:
		var earn_button := Button.new()
		earn_button.name = "earn"
		earn_button.text = "Earn"
		earn_button.theme_type_variation = &"ButtonSocket"
		earn_button.custom_minimum_size = Vector2(84, 28)
		earn_button.focus_mode = Control.FOCUS_NONE
		earn_button.add_theme_font_size_override("font_size", 13)
		var missing: String = shortfall_text(entry, _level(), _purse(), _carried_counts(entry))
		# OFFERED, BUT NOT PRESSABLE, WHILE SOMETHING IS VISIBLY SHORT. The
		# server is still the judge - this is the server's own list of what the
		# rank costs, read against the bag and purse it last sent - and a button
		# that can only be refused is a button that teaches nothing; the line
		# under the card says what is missing instead.
		earn_button.disabled = _busy or missing != ""
		earn_button.tooltip_text = missing if missing != "" else "Pay the Crown and take the rank."
		earn_button.pressed.connect(_on_earn_pressed.bind(rank))
		top.add_child(earn_button)
	else:
		var later := Label.new()
		later.name = "state"
		later.text = "after %s" % _rank_name(rank - 1)
		later.add_theme_font_size_override("font_size", 11)
		later.add_theme_color_override("font_color", MUTED)
		later.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(later)

	var level: int = int(entry.get("level", 0))
	var opens := Label.new()
	opens.name = "opens"
	opens.text = "Opens %s  -  needs character level %d" % [tier_words(int(entry.get("max_tier", 0))), level]
	opens.add_theme_font_size_override("font_size", 11)
	opens.add_theme_color_override("font_color",
		SHORT if not earned and _level() < level else MUTED)
	opens.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(opens)

	if earned:
		return card

	# WHAT IT COSTS, as a flow of coin and materials, so the Royal Smith's nine
	# lines wrap instead of pushing the window wider than the screen.
	var cost := HFlowContainer.new()
	cost.name = "cost"
	cost.add_theme_constant_override("h_separation", 10)
	cost.add_theme_constant_override("v_separation", 2)
	rows.add_child(cost)
	var gold: int = int(entry.get("gold", 0))
	cost.add_child(_cost_chip(_gold_icon(gold), "Gold", _purse(), gold))
	var materials: Variant = entry.get("materials", [])
	if materials is Array:
		for need in materials:
			if not (need is Dictionary):
				continue
			var id: String = str(need.get("item_id", ""))
			var item: ItemData = ItemRegistry.get_item(id) if id != "" else null
			var have: int = int(need.get("have", _carried(id)))
			cost.add_child(_cost_chip(item.icon if item != null else null,
				item.display_name if item != null else id, have, int(need.get("quantity", 0))))
	# THE NEXT RANK SAYS WHAT IS STILL MISSING, under its costs, in words: the
	# chips above say it in colour, and a red "0 / 6" beside an icon is a
	# riddle until the name is read off its hover.
	if is_next:
		var missing_line: String = shortfall_text(entry, _level(), _purse(), _carried_counts(entry))
		var still := Label.new()
		still.name = "missing"
		still.text = missing_line if missing_line != "" else "Everything the Crown asks is in your bag."
		still.add_theme_font_size_override("font_size", 11)
		still.add_theme_color_override("font_color", SHORT if missing_line != "" else ENOUGH)
		still.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(still)
	return card


static func shortfall_text(entry: Dictionary, level: int, purse: int, carried: Dictionary) -> String:
	"""What still stands between the player and this rank, as one line - "Still
	needed: level 10, 3 Water Essence" - or "" when nothing does. The rank's
	costs are the server's (GET /api/smith/status, its gold already scaled);
	the level, purse and bag are what the server last sent this client."""
	var parts := PackedStringArray()
	if level < int(entry.get("level", 0)):
		parts.append("level %d" % int(entry.get("level", 0)))
	var gold: int = int(entry.get("gold", 0))
	if purse < gold:
		parts.append("%s more gold" % GameConstants.commas(gold - purse))
	var materials: Variant = entry.get("materials", [])
	if materials is Array:
		for need in materials:
			if not (need is Dictionary):
				continue
			var id: String = str(need.get("item_id", ""))
			var short: int = int(need.get("quantity", 0)) - int(carried.get(id, 0))
			if short > 0:
				var item: ItemData = ItemRegistry.get_item(id) if ItemRegistry.has_item(id) else null
				parts.append("%d %s" % [short, item.display_name if item != null else id])
	if parts.is_empty():
		return ""
	return "Still needed: " + ", ".join(parts)


func _carried_counts(entry: Dictionary) -> Dictionary:
	# How many of each of the rank's materials the bag holds - or the count the
	# server put on the line, when it sent one.
	var out: Dictionary = {}
	var materials: Variant = entry.get("materials", [])
	if materials is Array:
		for need in materials:
			if need is Dictionary:
				var id: String = str(need.get("item_id", ""))
				out[id] = int(need.get("have", _carried(id)))
	return out


func _cost_chip(icon: Texture2D, what: String, have: int, need: int) -> Control:
	"""An icon and its have / need, with the item's name on the hover - nine of
	them must fit across one card."""
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 3)
	chip.tooltip_text = "%s: you have %s of %s" % [what, GameConstants.commas(have), GameConstants.commas(need)]
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.add_child(_icon_rect(icon, 16))
	var count: Label = _have_need_label(have, need)
	count.add_theme_font_size_override("font_size", 11)
	count.mouse_filter = Control.MOUSE_FILTER_PASS
	count.tooltip_text = ""
	chip.add_child(count)
	return chip


func _paint_badge() -> void:
	var held: int = _rank()
	rank_badge.tooltip_text = "No Royal Certification yet" if held <= 0 \
		else "Royal Certification: %s" % _rank_name(held)
	rank_icon.modulate = GameConstants.QUALITY_PERFECT_COLOUR if held >= _ranks().size() and held > 0 \
		else Color.WHITE


func _on_earn_pressed(rank: int) -> void:
	await earn(rank)


func earn(rank: int) -> void:
	"""Earn this rank. Only the next one is ever offered - the server takes the
	next rank only, and a button for any other would be a button that says no."""
	if _busy or rank != _rank() + 1:
		return
	var wanted: Dictionary = {}
	for entry in _ranks():
		if int(entry.get("rank", 0)) == rank:
			wanted = entry
	var missing: String = shortfall_text(wanted, _level(), _purse(), _carried_counts(wanted)) \
		if not wanted.is_empty() else "The smith's ledger has no such rank."
	if missing != "":
		# The button is not pressable while this is so; this is the same rule
		# for anything that calls earn() without the button.
		_set_notice(missing, true)
		return
	if not Api.is_logged_in():
		_set_notice("Not connected - the certification cannot be granted.", true)
		return
	var view: int = _view
	var player: Node = _player if is_instance_valid(_player) else null
	var title: String = _rank_name(rank)
	_busy = true
	_render_ranks()
	_set_notice("The Crown's assessor looks over your work...", false)

	var res: Dictionary = await Api.post("/api/smith/certify", {
		"slot": CharacterData.active_character_index,
		"rank": rank,
	}, REQUEST_TIMEOUT)

	if not is_instance_valid(self) or not is_inside_tree():
		return
	_busy = false
	player = player if is_instance_valid(player) else null
	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}

	if not res.get("ok", false):
		if view == _view:
			Audio.play("refused")
			_render_ranks()
			_set_notice(_refusal_text(res), true)
		return

	# THE STATUS IS THE ANSWER - flat, or under "status". The gold and the
	# materials the rank took come back as the purse and the bag when the
	# server sends them; when it does not, the bag is asked for, because
	# what is drawn now still holds materials the Crown has taken.
	_adopt_status(data.get("status", data))
	if data.has("inventory") or data.has("gold"):
		_apply_carry(data, player)
	else:
		var backpack: Node = _player_backpack()
		if backpack != null and backpack.has_method("refetch"):
			await backpack.refetch()
			if not is_instance_valid(self) or not is_inside_tree():
				return
	if view != _view:
		return
	Audio.play("coin")
	_refresh_gear()
	_render_ranks()
	_set_notice("You are now a %s. The Crown's seal is yours." % title, false)
	# A HIGHER RANK MAY LIFT THE GATE on the piece already on the anvil.
	if _chosen_cell >= 0:
		await choose_cell(_chosen_cell)


# =============================================================================
# SMALL THINGS
# =============================================================================

func _purse() -> int:
	var player: Node = _player if is_instance_valid(_player) else null
	if player != null and "gold" in player:
		return int(player.get("gold"))
	return 0


func _level() -> int:
	var player: Node = _player if is_instance_valid(_player) else null
	if player != null and "level" in player:
		return int(player.get("level"))
	return 0


func _carried(item_id: String) -> int:
	var backpack: Node = _player_backpack()
	if backpack == null or not backpack.has_method("get_quantity_of"):
		return 0
	return int(backpack.get_quantity_of(item_id))


static func _percents(raw: Variant) -> Dictionary:
	# JSON HAS NO INTEGER TYPE: every percent arrives as a float, and a
	# comparison of 104.0 with 104 is the kind of thing that works until it is
	# a key. Turned to ints once, here.
	var out: Dictionary = {}
	if raw is Dictionary:
		for field in raw:
			out[str(field)] = int(raw[field])
	return out


static func _sentence(text: String) -> String:
	# The server's reasons are short phrases ("already perfect"); a notice is
	# read as a sentence.
	var clean: String = text.strip_edges()
	if clean == "":
		return "The smith will not temper that."
	clean = clean.left(1).to_upper() + clean.substr(1)
	if not (clean.ends_with(".") or clean.ends_with("!") or clean.ends_with("?")):
		clean += "."
	return clean


func _refusal_text(res: Dictionary) -> String:
	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	var message: String = str(data.get("message", ""))
	if message != "":
		return _sentence(message)
	var status: int = int(res.get("status", 0))
	if status == 0 and str(res.get("error", "")) != "":
		return _sentence(str(res.get("error", "")))
	return str(REFUSAL_WORDS.get(status, "The smith could not do that (HTTP %d)." % status))


func _set_temper_notice(message: String, is_error: bool) -> void:
	temper_notice.text = message
	temper_notice.add_theme_color_override("font_color",
		Color(1, 0.6, 0.5) if is_error else Color(0.75, 0.72, 0.66))


func _set_notice(message: String, is_error: bool) -> void:
	notice_label.text = message
	notice_label.add_theme_color_override("font_color",
		Color(1, 0.6, 0.5) if is_error else Color(0.75, 0.72, 0.66))


static func _clear(box: Node) -> void:
	# TAKEN OUT AT ONCE, FREED AT THE END OF THE FRAME. Out of the tree now,
	# because these rows are rebuilt in the same frame and a row still in the
	# box counts for its layout. Not freed now, because the Earn button that
	# started a rebuild is one of them, and freeing a button from inside its
	# own pressed signal pulls it out from under the call still running.
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
