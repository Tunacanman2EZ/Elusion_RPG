# endlesshud.gd - what the endless run says on screen (0.93.0): a plate at
# the top with the stage, its land and the clock, a banner as each stage
# begins, and how the run went when it ends. Built by endlessrun.gd, in a
# CanvasLayer of its own over the world and under the HUD's windows.
extends CanvasLayer

const RUN_TOP := 52.0
const BANNER_SECONDS := 2.2
const COLOUR_GOLD := Color(1.0, 0.86, 0.5)
const COLOUR_HINT := Color(0.82, 0.78, 0.7)

var run: Node = null
var plate: PanelContainer = null
var title: Label = null
var detail: Label = null
var banner: Label = null
# A smaller line under the banner: what the stage's land does to you (0.93.3).
var banner_line: Label = null
var _banner_left: float = 0.0
# The countdown's last number said (-1: none yet this countdown).
var _count_said: int = -1


func _init() -> void:
	layer = 4
	name = "endlesshud"


func _ready() -> void:
	var theme_from: Control = null
	var hud: Node = get_tree().get_first_node_in_group(&"hud")
	if hud != null:
		theme_from = hud.get_node_or_null("%navframe") as Control
	plate = PanelContainer.new()
	plate.name = "plate"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if theme_from != null:
		plate.theme = theme_from.theme
		var style: StyleBox = theme_from.get_theme_stylebox("panel")
		if style != null:
			plate.add_theme_stylebox_override("panel", style)
	add_child(plate)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(column)
	title = _label(16, COLOUR_GOLD)
	detail = _label(12, COLOUR_HINT)
	column.add_child(title)
	column.add_child(detail)
	banner = _label(30, COLOUR_GOLD)
	banner.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.05))
	banner.add_theme_constant_override("outline_size", 8)
	banner.visible = false
	add_child(banner)
	banner_line = _label(16, COLOUR_HINT)
	banner_line.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.05))
	banner_line.add_theme_constant_override("outline_size", 6)
	banner_line.visible = false
	add_child(banner_line)


func _label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label


func _process(delta: float) -> void:
	if run == null or plate == null:
		return
	var state: int = int(run.get("state"))
	if state != 3:
		_count_said = -1
	var slain: int = int(run.swarm.get("slain")) if run.swarm != null else 0
	var shared: bool = bool(run.call("shared"))
	if state == 1:
		var land: String = str(run.LAND_NAMES.get(run.land_of(int(run.get("stage"))), ""))
		title.text = "Stage %d  ·  %s  ·  %s" % [int(run.get("stage")), land,
			run.clock_text(float(run.get("elapsed")))]
		detail.text = "%s slain  ·  %s in the arena" % [GameConstants.commas(slain),
			GameConstants.commas(int(run.swarm.get("alive")))]
		if shared:
			detail.text += "  ·  " + party_text()
	elif state == 3:
		var count: int = ceili(float(run.get("countdown_left")))
		title.text = "The Endless  ·  party of %d" % int(run.party.call("members"))
		detail.text = "The run starts in %d - come through the door" % count
		# THE COUNT, ONCE A SECOND, in the middle of the screen.
		if count != _count_said and count > 0:
			_count_said = count
			announce("The run starts in %d" % count)
	elif state == 0:
		title.text = "The Endless" if not shared else "The Endless  ·  party of %d" % int(run.party.call("members"))
		detail.text = "Open the door and step through to begin." if str(run.call("result_line")) == "" \
			else str(run.call("result_line"))
	_place()
	if _banner_left > 0.0:
		_banner_left -= delta
		banner.modulate.a = clampf(_banner_left / 0.6, 0.0, 1.0)
		banner_line.modulate.a = banner.modulate.a
		if _banner_left <= 0.0:
			banner.visible = false
			banner_line.visible = false


func _place() -> void:
	var screen: Vector2 = plate.get_viewport_rect().size
	plate.reset_size()
	plate.position = Vector2(floorf((screen.x - plate.size.x) / 2.0), RUN_TOP)
	if banner.visible:
		banner.reset_size()
		banner.position = Vector2(floorf((screen.x - banner.size.x) / 2.0), floorf(screen.y * 0.3))
		if banner_line.visible:
			banner_line.reset_size()
			banner_line.position = Vector2(floorf((screen.x - banner_line.size.x) / 2.0),
				banner.position.y + banner.size.y)


func announce(text: String, line: String = "") -> void:
	banner.text = text
	banner.visible = true
	banner.modulate.a = 1.0
	banner_line.text = line
	banner_line.visible = line != ""
	banner_line.modulate.a = 1.0
	_banner_left = BANNER_SECONDS


func show_result(text: String, best_text: String) -> void:
	announce("The party fell" if text.begins_with("The party") else "You fell")
	detail.text = "%s  ·  best %s" % [text, best_text]


func party_text() -> String:
	"""A party run: how many are in - or, for one who fell or came late, that
	there is no way in until the run is over (0.97.1: the door stays shut)."""
	var members: int = int(run.party.call("members"))
	var in_now: int = int(run.call("line")[7]) if bool(run.call("leading")) else int(run.get("party_in"))
	if bool(run.get("my_in")):
		return "%d of %d in" % [clampi(in_now, 1, members), members]
	var still: int = maxi(in_now, 1)
	return "out - waiting by the chest while %d %s on" % [still, "fights" if still == 1 else "fight"]
