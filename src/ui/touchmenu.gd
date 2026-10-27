# touchmenu.gd - the menu bar under a thumb (0.91.0): one Menu button, and
# everything the bar holds in one grid above it.
#
# The owner, on a phone: "attack and stuff takes up a majority of the screen
# on mobile". The bar's eight buttons ran 938 of the game's 1280 units along
# the floor, at a 14-unit text that a phone shows at about 7 CSS pixels. While
# the touch screen is in use (TouchControls.active) the HUD keeps only Menu on
# the bar, drawn at the pad's scale (touchpad.gd's thumb_scale()), and Menu
# opens THIS instead of its dropdown: every window the bar opens - Social's
# and Menu's included - as one grid of buttons a thumb can hit.
#
# NOTHING IS MOVED. Each button here presses the bar's own button (its
# `pressed` signal), so what it opens, the dropdowns' wiring and the dots
# (" •" on a button with something waiting) stay the bar's: a button here
# copies its words from the bar's button each time the grid opens. With a
# keyboard the bar is back as it was.
#
# Built by the HUD (characterhud.gd's TouchMenu.attach()), no class_name, so a
# fresh checkout needs no editor rescan.
extends PanelContainer

const PadScript := preload("res://src/ui/touchpad.gd")

# The bar's buttons, in the order the grid shows them: the bar's own, then
# Social's, then Menu's.
const ITEMS := [
	"inventorybutton", "equipmentbutton", "statsbutton", "shopbutton", "mapbutton", "chatbutton",
	"friendsbutton", "playersbutton", "partybutton", "guildbutton", "tradebutton", "kingdombutton", "killsbutton",
	"controlsbutton", "optionsbutton", "switchcharacterbutton", "logoutbutton",
]
const COLUMNS := 3
const ITEM_SIZE := Vector2(132, 30)
const FONT_SIZE := 14
# How wide the bar is with only Menu on it, in game units before the scale.
const MENU_WIDTH := 96.0
# The bar's right offset in the scene, put back with a keyboard.
const BAR_RIGHT := -334.0
# The bar's left offset in the scene, and folded (0.91.3): further in from the
# edge, where a phone's rounded corner is. The owner, of his phone: "move over
# the menu more it is cut off on my phone because of gm panel" - the owner's
# Staff, Owner and Powers row is wider than Menu, and the bar grew both ways,
# so it started off the left of the screen. Folded, it grows to the right only.
const BAR_LEFT := 8.0
const FOLDED_LEFT := 24.0
const GAP := 6.0

# The suite's stand-in for a phone's pixels to a CSS pixel; 0 asks the screen.
static var pixel_ratio_for_test: float = 0.0

var hud: Node = null
var grid: GridContainer = null
var _buttons: Dictionary = {}
var _folded: bool = false
var _hidden_by_us: Array[Control] = []


static func attach(on_hud: Node) -> Control:
	var menu: Control = (load("res://src/ui/touchmenu.gd") as GDScript).new()
	menu.name = "touchmenu"
	menu.set("hud", on_hud)
	on_hud.add_child(menu)
	return menu


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	grid = GridContainer.new()
	grid.name = "items"
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	add_child(grid)


func _ready() -> void:
	var nav: Control = hud.get_node_or_null("%navframe") as Control if hud != null else null
	if nav != null:
		theme = nav.theme
		var style: StyleBox = nav.get_theme_stylebox("panel")
		if style != null:
			add_theme_stylebox_override("panel", style)
	for id in ITEMS:
		var real: Button = _real(id)
		if real == null:
			continue
		var button := Button.new()
		button.name = id
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = ITEM_SIZE
		button.add_theme_font_size_override("font_size", FONT_SIZE)
		button.pressed.connect(_press.bind(id))
		grid.add_child(button)
		_buttons[id] = button
	TouchControls.changed.connect(_on_touch_changed)
	get_viewport().size_changed.connect(_refold)
	fold(TouchControls.active)


func _real(id: String) -> Button:
	return hud.get_node_or_null("%" + id) as Button if hud != null else null


static func thumb_scale_of(node: Control) -> float:
	"""The pad's scale for this window: game units to a CSS pixel."""
	var window: Window = node.get_window() if node.is_inside_tree() else null
	if window == null:
		return 1.0
	var view: Vector2 = node.get_viewport_rect().size
	var drawn_at: Vector2 = Vector2(window.content_scale_size) if window.content_scale_size != Vector2i.ZERO else view
	var ratio: float = pixel_ratio_for_test if pixel_ratio_for_test > 0.0 else DisplayServer.screen_get_scale()
	return PadScript.thumb_scale(Vector2(window.size), drawn_at, ratio)


func _on_touch_changed(on: bool) -> void:
	fold(on)


func _refold() -> void:
	fold(_folded)


func is_folded() -> bool:
	return _folded


func fold(touch: bool) -> void:
	"""Only Menu on the bar, at the thumbs' scale - or the bar as the scene
	made it."""
	var nav: Control = hud.get_node_or_null("%navframe") as Control if hud != null else null
	var row: Control = hud.get_node_or_null("%navbuttons") as Control if hud != null else null
	if nav == null or row == null:
		return
	if touch:
		for child in row.get_children():
			var c := child as Control
			if c != null and c.name != "menubutton" and c.visible:
				c.visible = false
				if not _hidden_by_us.has(c):
					_hidden_by_us.append(c)
	else:
		for c in _hidden_by_us:
			if is_instance_valid(c):
				c.visible = true
		_hidden_by_us.clear()
		close()
	_folded = touch
	var f: float = thumb_scale_of(nav) if touch else 1.0
	nav.anchor_right = 0.0 if touch else 1.0
	nav.grow_horizontal = Control.GROW_DIRECTION_END if touch else Control.GROW_DIRECTION_BOTH
	nav.offset_left = FOLDED_LEFT if touch else BAR_LEFT
	nav.offset_right = nav.offset_left + MENU_WIDTH if touch else BAR_RIGHT
	nav.scale = Vector2(f, f)
	# Grown from its bottom left corner, where it is pinned.
	nav.pivot_offset = Vector2(0.0, nav.size.y)
	scale = Vector2(f, f)
	# Menu's dot: its own with the bar out, the whole bar's folded.
	if hud.has_method("_paint_group_dots"):
		hud.call("_paint_group_dots")


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	for id in _buttons:
		var real: Button = _real(id)
		var mine: Button = _buttons[id]
		mine.visible = real != null and _shown_on_its_bar(real)
		if real != null:
			mine.text = real.text
			if real.has_theme_color_override("font_color"):
				mine.add_theme_color_override("font_color", real.get_theme_color("font_color"))
			else:
				mine.remove_theme_color_override("font_color")
	visible = true
	move_to_front()
	reset_size()
	var nav: Control = hud.get_node_or_null("%navframe") as Control
	var f: float = scale.x
	var screen: Vector2 = get_viewport_rect().size
	var drawn: Vector2 = size * f
	var above: float = nav.get_global_rect().position.y if nav != null else screen.y
	position = Vector2(clampf(FOLDED_LEFT, 0.0, maxf(0.0, screen.x - drawn.x)),
		maxf(0.0, above - drawn.y - GAP * f)).floor()


func _shown_on_its_bar(real: Button) -> bool:
	"""A button the bar itself hides (the staff ones aside, none today) is not
	offered here either. The bar's own are hidden by fold(), so they count."""
	return real.visible or _hidden_by_us.has(real) or not real.get_parent() is HBoxContainer


func close() -> bool:
	var was: bool = visible
	visible = false
	return was


func _press(id: String) -> void:
	close()
	var real: Button = _real(id)
	if real != null:
		real.pressed.emit()


func covers(point: Vector2) -> bool:
	return visible and get_global_rect().has_point(point)
