# descenthud.gd - what the Descent says on screen (0.112.0): a plate at the
# top with the floor, the room and the run's gold, a dot a room (done, here,
# to come, the keeper last), the upgrades taken under it, a banner as each
# room begins, the pick of three when a room promised an upgrade (a card
# chosen, then Take it - CONFIRMED, below), the fade
# between rooms, and how the run went. (The keeper's health is its own bar,
# over it, as every boss's.) Built by
# descentrun.gd, in a CanvasLayer of its own over the world and under the
# HUD's windows (as the Endless's is).
#
# CONFIRMED (0.112.1). The owner: "we need a confirm button for upgrades cause
# when round ends i click the upgrade on accident" - the pick comes up under
# the cursor while the last monster is still being swung at. A click on a card
# only chooses it (ringed in gold, `chosen`); Take it, under the cards, takes
# it, and stays dimmed until a card is chosen.
extends CanvasLayer

const Boons := preload("res://src/world/descent/descentboons.gd")
const RUN_TOP := 52.0
const BANNER_SECONDS := 2.4
const TOAST_SECONDS := 1.6
const GOLD := Color(1.0, 0.86, 0.5)
const HINT := Color(0.82, 0.78, 0.7)
const CARD_SIZE := Vector2(210, 150)
const CHOSEN := Color(1.0, 0.82, 0.3)
const PIP_GAP := 26.0
# THE WARD (0.115.0): its bar on the plate, under the rooms.
const WARD_BAR := Vector2(200, 10)
const WARD_GOLD := Color(1.0, 0.8, 0.3)
# AXE FURY's bar (0.115.0), under the ward's, while the Double Axe is on.
const FURY_ORANGE := Color(1.0, 0.55, 0.2)

var run: Node = null
var plate: PanelContainer = null
var title: Label = null
var detail: Label = null
var pips: Control = null
var boon_line: Label = null
var ward_row: HBoxContainer = null
var ward_bar: Control = null
var ward_text: Label = null
var fury_row: HBoxContainer = null
var fury_bar: Control = null
var fury_text: Label = null
var banner: Label = null
var banner_line: Label = null
var toast_label: Label = null
var pick_panel: PanelContainer = null
var cards: Array = []
var take_button: Button = null
# The card chosen, -1 for none yet (CONFIRMED).
var chosen: int = -1
var _offered: Array = []
var black: ColorRect = null
var result: Label = null
var _banner_left: float = 0.0
var _toast_left: float = 0.0


func _init() -> void:
	layer = 4
	name = "descenthud"


func _ready() -> void:
	black = ColorRect.new()
	black.name = "fade"
	black.color = Color(0, 0, 0, 0)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	plate = PanelContainer.new()
	plate.name = "plate"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.03, 0.05, 0.8)
	style.border_color = Color(GOLD, 0.45)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	plate.add_theme_stylebox_override("panel", style)
	add_child(plate)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(column)
	title = _label("title", 18, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	detail = _label("detail", 13, HINT)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(detail)
	pips = Control.new()
	pips.name = "pips"
	pips.custom_minimum_size = Vector2(PIP_GAP * (run_rooms() + 1), 22)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.draw.connect(_draw_pips)
	column.add_child(pips)
	ward_row = HBoxContainer.new()
	ward_row.name = "ward"
	ward_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ward_row.add_theme_constant_override("separation", 8)
	ward_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(ward_row)
	var ward_name: Label = _label("wardname", 13, WARD_GOLD)
	ward_name.text = "Ward"
	ward_row.add_child(ward_name)
	ward_bar = Control.new()
	ward_bar.name = "wardbar"
	ward_bar.custom_minimum_size = WARD_BAR
	ward_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ward_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ward_bar.draw.connect(_draw_ward)
	ward_row.add_child(ward_bar)
	ward_text = _label("wardtext", 13, WARD_GOLD)
	ward_row.add_child(ward_text)
	fury_row = HBoxContainer.new()
	fury_row.name = "fury"
	fury_row.alignment = BoxContainer.ALIGNMENT_CENTER
	fury_row.add_theme_constant_override("separation", 8)
	fury_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(fury_row)
	var fury_name: Label = _label("furyname", 13, FURY_ORANGE)
	fury_name.text = "Fury"
	fury_row.add_child(fury_name)
	fury_bar = Control.new()
	fury_bar.name = "furybar"
	fury_bar.custom_minimum_size = WARD_BAR
	fury_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fury_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fury_bar.draw.connect(_draw_fury)
	fury_row.add_child(fury_bar)
	fury_text = _label("furytext", 13, FURY_ORANGE)
	fury_row.add_child(fury_text)
	boon_line = _label("boons", 12, GOLD)
	boon_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(boon_line)
	banner = _label("banner", 30, GOLD)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(banner)
	banner_line = _label("bannerline", 16, HINT)
	banner_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(banner_line)
	toast_label = _label("toast", 20, GOLD)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(toast_label)
	result = _label("result", 18, GOLD)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(result)
	_build_pick()
	paint()


func _label(id: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.name = id
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_pick() -> void:
	pick_panel = PanelContainer.new()
	pick_panel.name = "pick"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.05, 0.92)
	style.border_color = Color(0.85, 0.65, 0.25)
	style.set_border_width_all(3)
	style.set_content_margin_all(16)
	pick_panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	pick_panel.add_child(column)
	var heading := _label("heading", 24, GOLD)
	heading.text = "Room clear!  Choose one, then Take it"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)
	for i in 3:
		var card := Button.new()
		card.name = "card%d" % i
		card.focus_mode = Control.FOCUS_NONE
		card.custom_minimum_size = CARD_SIZE
		card.pressed.connect(_on_card.bind(i))
		var words := VBoxContainer.new()
		words.name = "words"
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.alignment = BoxContainer.ALIGNMENT_CENTER
		words.set_anchors_preset(Control.PRESET_FULL_RECT)
		words.add_theme_constant_override("separation", 8)
		card.add_child(words)
		for part in [["name", 20, GOLD], ["does", 15, HINT], ["level", 13, Color(0.75, 0.9, 0.6)]]:
			var l := _label(str(part[0]), int(part[1]), part[2])
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(CARD_SIZE.x - 20.0, 0)
			words.add_child(l)
		row.add_child(card)
		cards.append(card)
	take_button = Button.new()
	take_button.name = "take"
	take_button.focus_mode = Control.FOCUS_NONE
	take_button.custom_minimum_size = Vector2(220, 40)
	take_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	take_button.add_theme_font_size_override("font_size", 18)
	take_button.pressed.connect(_on_take)
	column.add_child(take_button)
	pick_panel.visible = false
	add_child(pick_panel)


func run_rooms() -> int:
	return int(run.get("ROOMS")) if run != null and "ROOMS" in run else 6


func _process(delta: float) -> void:
	_banner_left = maxf(0.0, _banner_left - delta)
	_toast_left = maxf(0.0, _toast_left - delta)
	paint()


func paint() -> void:
	if run == null:
		return
	var screen: Vector2 = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	var running: bool = bool(run.call("running"))
	title.text = "The Descent"
	if running:
		var info: Dictionary = run.call("floor_info")
		detail.text = "Floor %d  -  %s  -  %s  -  Gold %d" % [int(run.get("floor_index")) + 1, str(info["name"]),
			"the keeper" if str(run.get("room_kind")) == "keeper" else "room %d of %d" % [maxi(1, int(run.get("room"))), run_rooms()],
			int(run.get("gold"))]
		# A CHALLENGE'S CLOCK (0.115.0), while it is fought.
		if str(run.get("room_kind")) == "challenge" and float(run.get("challenge_left")) > 0.0 \
				and int(run.get("state")) == 1:
			detail.text += "  -  Clear it: %d s" % ceili(float(run.get("challenge_left")))
	else:
		detail.text = "Walk through a door to begin"
	pips.visible = running
	pips.queue_redraw()
	ward_row.visible = running and Boons.ward_most > 0
	ward_text.text = "%d" % Boons.ward
	ward_bar.queue_redraw()
	fury_row.visible = running and run.has_method("wears_axe") and bool(run.call("wears_axe"))
	fury_text.text = "Q!" if Boons.fury_full() else "%d/%d" % [Boons.fury, Boons.FURY_NEEDS]
	fury_bar.queue_redraw()
	var taken: Array = []
	for id in Boons.ORDER:
		if Boons.level(id) > 0:
			taken.append("%s %d" % [str(Boons.BOONS[id]["name"]), Boons.level(id)])
	boon_line.text = "  ".join(taken)
	boon_line.visible = not taken.is_empty()
	plate.reset_size()
	plate.position = Vector2(floorf((screen.x - plate.size.x) / 2.0), RUN_TOP)
	banner.visible = _banner_left > 0.0
	banner_line.visible = banner.visible
	banner.modulate.a = minf(1.0, _banner_left / 0.4)
	banner_line.modulate.a = banner.modulate.a
	banner.reset_size()
	banner.position = Vector2(floorf((screen.x - banner.size.x) / 2.0), floorf(screen.y * 0.3))
	banner_line.reset_size()
	banner_line.position = Vector2(floorf((screen.x - banner_line.size.x) / 2.0), banner.position.y + 42.0)
	toast_label.visible = _toast_left > 0.0
	toast_label.modulate.a = minf(1.0, _toast_left / 0.4)
	toast_label.reset_size()
	toast_label.position = Vector2(floorf((screen.x - toast_label.size.x) / 2.0), floorf(screen.y * 0.42))
	result.visible = not running and result.text != ""
	result.reset_size()
	result.position = Vector2(floorf((screen.x - result.size.x) / 2.0), floorf(screen.y * 0.22))
	if pick_panel.visible:
		pick_panel.reset_size()
		pick_panel.position = ((screen - pick_panel.size) / 2.0).floor()


func _draw_ward() -> void:
	"""The ward's bar: gold for what is left, dark for what is gone."""
	var full: float = float(Boons.ward) / float(Boons.ward_most) if Boons.ward_most > 0 else 0.0
	ward_bar.draw_rect(Rect2(Vector2.ZERO, WARD_BAR), Color(0.1, 0.08, 0.05, 0.9))
	ward_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(WARD_BAR.x * full, WARD_BAR.y)), WARD_GOLD)
	ward_bar.draw_rect(Rect2(Vector2.ZERO, WARD_BAR), Color(WARD_GOLD, 0.6), false, 1.0)


func _draw_fury() -> void:
	"""Axe Fury's bar: orange as it fills, bright when Q is ready."""
	var full: float = float(Boons.fury) / float(Boons.FURY_NEEDS)
	fury_bar.draw_rect(Rect2(Vector2.ZERO, WARD_BAR), Color(0.1, 0.06, 0.04, 0.9))
	fury_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(WARD_BAR.x * full, WARD_BAR.y)),
		Color(1.6, 0.9, 0.35) if Boons.fury_full() else FURY_ORANGE)
	fury_bar.draw_rect(Rect2(Vector2.ZERO, WARD_BAR), Color(FURY_ORANGE, 0.6), false, 1.0)


func _draw_pips() -> void:
	"""A dot a room: done gold, this one ringed, to come dim, the keeper red."""
	var count: int = run_rooms() + 1
	var here: int = int(run.get("room")) - 1
	var mid_y: float = pips.size.y / 2.0
	var start_x: float = pips.size.x / 2.0 - PIP_GAP * (count - 1) / 2.0
	for k in count:
		var p := Vector2(start_x + PIP_GAP * k, mid_y)
		if k < count - 1:
			pips.draw_line(p, p + Vector2(PIP_GAP, 0), Color(HINT, 0.35), 2.0)
		if k == count - 1:
			pips.draw_circle(p, 7.0, Color(0.6, 0.15, 0.1, 0.9))
			pips.draw_arc(p, 7.0, 0.0, TAU, 20, Color(1.0, 0.45, 0.3) if k == here else Color(1.0, 0.45, 0.3, 0.6), 2.0)
		elif k < here:
			pips.draw_circle(p, 4.5, Color(GOLD, 0.95))
		elif k == here:
			pips.draw_circle(p, 5.0, Color.WHITE)
			pips.draw_arc(p, 8.0, 0.0, TAU, 20, Color(GOLD, 0.8), 1.5)
		else:
			pips.draw_circle(p, 4.0, Color(HINT, 0.35))


# =============================================================================
# WHAT THE RUN SAYS
# =============================================================================

func announce(words: String, line: String = "") -> void:
	banner.text = words
	banner_line.text = line
	_banner_left = BANNER_SECONDS
	result.text = ""


func toast(words: String) -> void:
	toast_label.text = words
	_toast_left = TOAST_SECONDS


func fade(amount: float) -> void:
	black.color.a = clampf(amount, 0.0, 1.0)


func show_pick(offers: Array) -> void:
	for i in cards.size():
		var card: Button = cards[i]
		card.visible = i < offers.size()
		if not card.visible:
			continue
		var id: String = str(offers[i])
		var info: Dictionary = Boons.BOONS[id]
		var words: Node = card.get_node("words")
		(words.get_node("name") as Label).text = str(info["name"])
		# ITS RARITY (0.115.0): the name in the rarity's colour, the word under.
		(words.get_node("name") as Label).add_theme_color_override("font_color", rarity_colour(id))
		(words.get_node("does") as Label).text = str(info["does"])
		(words.get_node("level") as Label).text = "%s  -  %s" % [Boons.rarity(id).capitalize(), Boons.level_text(id)]
	_offered = offers.duplicate()
	_choose(-1)
	pick_panel.visible = true
	paint()


func hide_pick() -> void:
	pick_panel.visible = false
	_choose(-1)


func _on_card(index: int) -> void:
	"""A card clicked is chosen, not taken (CONFIRMED)."""
	_choose(index)


func _choose(index: int) -> void:
	chosen = index if index >= 0 and index < _offered.size() else -1
	for i in cards.size():
		var card: Button = cards[i]
		if i == chosen:
			var ring := StyleBoxFlat.new()
			ring.bg_color = Color(0.16, 0.12, 0.05, 0.95)
			ring.border_color = CHOSEN
			ring.set_border_width_all(3)
			ring.set_corner_radius_all(4)
			for look in ["normal", "hover", "pressed"]:
				card.add_theme_stylebox_override(look, ring)
		elif i < _offered.size():
			# Its rarity's rim (0.115.0).
			var rim := StyleBoxFlat.new()
			rim.bg_color = Color(0.1, 0.08, 0.07, 0.95)
			rim.border_color = Color(rarity_colour(str(_offered[i])), 0.8)
			rim.set_border_width_all(2)
			rim.set_corner_radius_all(4)
			for look in ["normal", "hover", "pressed"]:
				card.add_theme_stylebox_override(look, rim)
		else:
			for look in ["normal", "hover", "pressed"]:
				card.remove_theme_stylebox_override(look)
	if take_button != null:
		take_button.disabled = chosen < 0
		take_button.text = "Choose an upgrade" if chosen < 0 else \
			"Take %s" % str(Boons.BOONS[str(_offered[chosen])]["name"])


static func rarity_colour(id: String) -> Color:
	return Boons.RARITY_COLOURS.get(Boons.rarity(id), GOLD)


func _on_take() -> void:
	"""Take it: the chosen card goes to the run."""
	if chosen >= 0 and run != null:
		run.call("pick", chosen)


func show_result(words: String, won: bool) -> void:
	result.text = words
	announce("The bottom!" if won else "You fell", "Walk through a door to go again")
