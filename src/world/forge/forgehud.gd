# forgehud.gd - what the Forge says on screen (step 1): a plate at the top
# with the clock, the slices gone and the fire sprites slain, the heat bar
# under it (orange, red while the next slice glows, "The volcano" once every
# slice is gone), a banner for each beat of the run, a toast for the ice
# essence, and how long the forge held - and since 0.121.0 the gear line
# (gear_text(): the hammer's progress at the anvil, the armour forged and the
# wading time left, its bar pale blue). Built by forgerun.gd, in a
# CanvasLayer of its own over the world and under the HUD's windows (as the
# Endless's and the Descent's are).
extends CanvasLayer

const Run := preload("res://src/world/forge/forgerun.gd")

const RUN_TOP := 52.0
const BANNER_SECONDS := 2.6
const TOAST_SECONDS := 1.8
const GOLD := Color(1.0, 0.86, 0.5)
const HINT := Color(0.82, 0.78, 0.7)
const HEAT_BAR := Vector2(220, 12)
const HEAT := Color(1.0, 0.55, 0.15)
const HEAT_WARNING := Color(1.0, 0.25, 0.1)
const COLD := Color(0.55, 0.9, 1.0)
const FLASH_SECONDS := 0.9
# THE VOLCANO'S HEART (0.122.0), drawn on the screen so it is seen at any
# zoom: the meteor's stone HEART_SCALE times over, falling from the top of
# the screen to the right (HEART_FROM, a share of its width and px over its
# top edge) onto the anvil as the camera sees it.
const HEART_ART := "res://art/maincharacter/meteor.png"
const HEART_SCALE := 7.0
const HEART_FROM := Vector2(0.84, -70.0)

var run: Node = null
var plate: PanelContainer = null
var title: Label = null
var detail: Label = null
var heat_row: HBoxContainer = null
var heat_name: Label = null
var heat_bar: Control = null
var gear: Label = null
# THE ISLAND IS WIPED (0.122.0): a white flash over the screen, fading.
var white: ColorRect = null
var _flash_left: float = 0.0
var heart: Control = null
var _heart_art: Texture2D = null
var banner: Label = null
var banner_line: Label = null
var toast_label: Label = null
var result: Label = null
var _banner_left: float = 0.0
var _toast_left: float = 0.0


func _init() -> void:
	layer = 4
	name = "forgehud"


func _ready() -> void:
	# The heart first, so every word is drawn over it.
	heart = Control.new()
	heart.name = "heart"
	heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	heart.set_anchors_preset(Control.PRESET_FULL_RECT)
	heart.draw.connect(_draw_heart)
	add_child(heart)
	_heart_art = load(HEART_ART) as Texture2D
	plate = PanelContainer.new()
	plate.name = "plate"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.03, 0.02, 0.82)
	style.border_color = Color(HEAT, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	plate.add_theme_stylebox_override("panel", style)
	add_child(plate)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(column)
	title = _label("title", 18, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	detail = _label("detail", 13, HINT)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(detail)
	heat_row = HBoxContainer.new()
	heat_row.name = "heat"
	heat_row.alignment = BoxContainer.ALIGNMENT_CENTER
	heat_row.add_theme_constant_override("separation", 8)
	heat_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heat_row)
	heat_name = _label("heatname", 13, HEAT)
	heat_row.add_child(heat_name)
	heat_bar = Control.new()
	heat_bar.name = "heatbar"
	heat_bar.custom_minimum_size = HEAT_BAR
	heat_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heat_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heat_bar.draw.connect(_draw_heat)
	heat_row.add_child(heat_bar)
	gear = _label("gear", 13, COLD)
	gear.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(gear)
	banner = _label("banner", 30, GOLD)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(banner)
	banner_line = _label("bannerline", 16, HINT)
	banner_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(banner_line)
	toast_label = _label("toast", 20, COLD)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(toast_label)
	result = _label("result", 18, GOLD)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(result)
	white = ColorRect.new()
	white.name = "flash"
	white.color = Color(1.0, 0.97, 0.88, 0.0)
	white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	white.set_anchors_preset(Control.PRESET_FULL_RECT)
	white.visible = false
	add_child(white)
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


func flash() -> void:
	_flash_left = FLASH_SECONDS


func heart_falling() -> bool:
	return run != null and str(run.get("finale")) == "falling"


func heart_at(done: float) -> Vector2:
	"""Where the heart is on the screen, `done` of the way down: from high and
	to the right, onto the anvil where the camera has it - slow, then fast."""
	var land: Vector2 = Run.CENTRE + Run.FINALE_LAND
	var view := Vector2(1280, 720)
	if is_inside_tree():
		land = get_viewport().get_canvas_transform() * land
		view = get_viewport().get_visible_rect().size
	var from := Vector2(view.x * HEART_FROM.x, HEART_FROM.y)
	return from.lerp(land, pow(done, 1.4))


func _draw_heart() -> void:
	if not heart_falling():
		return
	var done: float = float(run.call("finale_done"))
	var at: Vector2 = heart_at(done)
	var back: Vector2 = (heart_at(0.0) - at).normalized()
	for k in 16:
		var u: float = float(k) / 16.0
		heart.draw_circle(at + back * (30.0 + 46.0 * k), 84.0 - k * 4.6, Color(1.0, 0.35 + u * 0.45, 0.08, 0.85 - u * 0.8))
	if _heart_art != null:
		heart.draw_set_transform(at, float(run.get("volcano_seconds")) * 2.0, Vector2.ONE * HEART_SCALE)
		heart.draw_texture(_heart_art, -_heart_art.get_size() / 2.0, Color(1.4, 1.1, 0.9))
		heart.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# WHO SPENT IT (0.152.0): this minigame's own frame, timed, so a slow
# frame on the readout names it (PerfOverlay.spend()).
func _process(delta: float) -> void:
	var spent_from: int = Time.get_ticks_usec()
	_timed_process(delta)
	PerfOverlay.spend(&"forge screen", Time.get_ticks_usec() - spent_from)


func _timed_process(delta: float) -> void:
	_flash_left = maxf(0.0, _flash_left - delta)
	if heart != null:
		heart.queue_redraw()
	if white != null:
		white.visible = _flash_left > 0.0
		white.color.a = 0.85 * pow(_flash_left / FLASH_SECONDS, 1.5)
	_banner_left = maxf(0.0, _banner_left - delta)
	_toast_left = maxf(0.0, _toast_left - delta)
	paint()


func detail_text() -> String:
	if run == null:
		return ""
	var clock: String = Run.clock_text(float(run.get("elapsed")))
	if bool(run.call("running")):
		return "%s  -  %d of %d slices flooded  -  %d slain" % [clock, int(run.get("floods")),
			Run.SLICES, int(run.get("slain"))]
	var left: float = float(run.call("countdown_left"))
	if left > 0.0:
		return "The lava rises in %d" % ceili(left)
	var line: String = "Stand at the anvil to light the forge"
	if float(run.get("best")) > 0.0:
		line += "  -  best %s" % Run.clock_text(float(run.get("best")))
	return line


func gear_text() -> String:
	"""The hammer, the armour and the wading time (0.121.0)."""
	if run == null or not bool(run.call("running")):
		return ""
	var pieces: int = int(run.get("pieces"))
	var most: int = Run.PIECES.size()
	if bool(run.call("hammering")):
		return "Forging the %s  -  %d%%" % [str(run.call("next_piece")), roundi(100.0 * float(run.call("forging_share")))]
	if pieces == 0:
		return "Hold %s at the anvil to forge armour" % ControlsPanel.action_key("interact")
	var line: String = "Armour %d of %d  -  %.1f s in the lava" % [pieces, most, float(run.get("wade_left"))]
	if pieces < most:
		line += "  -  forge more at the anvil"
	return line


func paint() -> void:
	if run == null or title == null:
		return
	var screen: Vector2 = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	var running: bool = bool(run.call("running"))
	title.text = "The Forge"
	detail.text = detail_text()
	heat_row.visible = running or float(run.call("hold_share")) > 0.0
	heat_name.text = "The volcano erupts" if bool(run.call("volcano")) else ("Heat" if running else "Lighting")
	gear.text = gear_text()
	gear.visible = gear.text != ""
	heat_name.add_theme_color_override("font_color", HEAT_WARNING if bool(run.call("warning")) else HEAT)
	heat_bar.queue_redraw()
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
	result.visible = not running and result.text != "" and float(run.call("countdown_left")) <= 0.0
	result.reset_size()
	result.position = Vector2(floorf((screen.x - result.size.x) / 2.0), floorf(screen.y * 0.22))


func heat_share() -> float:
	if run == null:
		return 0.0
	if bool(run.call("running")):
		return 1.0 if bool(run.call("volcano")) else float(run.get("heat"))
	return float(run.call("hold_share"))


func _draw_heat() -> void:
	var full: float = heat_share()
	var colour: Color = HEAT_WARNING if run != null and bool(run.call("warning")) else HEAT
	if run != null and not bool(run.call("running")):
		colour = GOLD
	heat_bar.draw_rect(Rect2(Vector2.ZERO, HEAT_BAR), Color(0.1, 0.05, 0.03, 0.9))
	heat_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(HEAT_BAR.x * full, HEAT_BAR.y)), colour)
	heat_bar.draw_rect(Rect2(Vector2.ZERO, HEAT_BAR), Color(colour, 0.6), false, 1.0)


func announce(words: String, line: String = "") -> void:
	banner.text = words
	banner_line.text = line
	_banner_left = BANNER_SECONDS
	result.text = ""


func toast(words: String) -> void:
	toast_label.text = words
	_toast_left = TOAST_SECONDS


func show_result(words: String) -> void:
	result.text = words
	announce("The smith falls", "Stand at the anvil to light the forge again")
	result.text = words
