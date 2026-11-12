extends Node
# testingground.gd - the Testing Ground (0.151.1): the Endless's map with no
# run, for measuring what each monster costs.
#
# The owner: "maybe we should make a new minigame called testing ground since
# minigame is designed to spawn slimes not test", "i want monsters to be
# counted on the field so if i spawn 10 at a time i know where the limit is",
# and "the goal is to make a spread sheet with all enemies then figure out the
# mathmatical solutions".
#
# Made by endlessrun.gd when GameState.testing_ground is set (the Minigames
# card's owner-only Go): the run never starts, nothing comes on its own, and
# this brings only what is asked for - the slime horde at a size (HORDES,
# kept topped up) and anything the GM panel's Spawn brings (gmspawner.gd, test
# copies worth nothing). A fall wakes you by the chest, as in the Endless.
#
# THE PANEL AT THE TOP: what is alive, by kind, and the game's own work a frame
# (PerfOverlay.work_stats(): physics + scripts + drawing, the median and the
# 95th percentile of the last COUNT_FRAMES - not the frame, which V-Sync holds
# to the screen's refresh) against the budget, green under AMBER_AT of it,
# amber to it, red past it. The readout is switched on here: it is what counts
# the work.

const GmSpawner := preload("res://src/world/gmspawner.gd")
const HORDES := [0, 1000, 3000, 5000]
# Slimes made a frame while the horde fills (the swarm's own fill is a rate).
const FILL_A_FRAME := 250
# The slimes' strength: a mid run's (endlessrun.gd stage 10).
const SLIME_STAGE := 10
const REPAINT_EVERY := 0.25
const COUNT_FRAMES := 60
const AMBER_AT := 0.8
const COLOUR := Color(1.0, 0.86, 0.5)
const COLOUR_TEXT := Color(0.92, 0.88, 0.8)
const GREEN := Color(0.55, 0.9, 0.5)
const AMBER := Color(1.0, 0.72, 0.35)
const RED := Color(1.0, 0.42, 0.38)
const WIDTH := 460.0

var run: Node = null
var horde: int = 0
var _layer: CanvasLayer = null
var _work_label: Label = null
var _count_label: Label = null
var _horde_buttons: Array = []
var _repaint_left: float = 0.0


func _ready() -> void:
	PerfOverlay.set_shown(true)
	_set_slimes()
	_build()
	paint()


func _set_slimes() -> void:
	var swarm: Node = run.get("swarm") if run != null else null
	if swarm == null:
		return
	var land: int = int(run.call("land_of", SLIME_STAGE))
	swarm.set("element", land)
	swarm.set("max_hp", float(run.call("stage_health", SLIME_STAGE)))
	swarm.set("speed", float(run.call("stage_speed", SLIME_STAGE)))
	swarm.set("touch_damage", int(run.call("stage_touch", SLIME_STAGE)))


func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "testinglayer"
	_layer.layer = 5
	add_child(_layer)
	# TOP RIGHT: the readout is top left, and the run's plate is not shown.
	var panel := PanelContainer.new()
	panel.name = "testingpanel"
	panel.custom_minimum_size = Vector2(WIDTH, 0.0)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -WIDTH - 8.0
	panel.offset_right = -8.0
	panel.offset_top = 8.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var look := StyleBoxFlat.new()
	look.bg_color = Color(0.08, 0.06, 0.05, 0.88)
	look.border_color = Color(COLOUR, 0.6)
	look.set_border_width_all(1)
	look.set_corner_radius_all(4)
	look.set_content_margin_all(8.0)
	panel.add_theme_stylebox_override("panel", look)
	_layer.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	panel.add_child(rows)
	var top := HBoxContainer.new()
	rows.add_child(top)
	var title := Label.new()
	title.name = "title"
	title.text = "TESTING GROUND"
	title.add_theme_color_override("font_color", COLOUR)
	title.add_theme_font_size_override("font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_work_label = Label.new()
	_work_label.name = "work"
	_work_label.add_theme_font_size_override("font_size", 13)
	_work_label.tooltip_text = "The game's own work a frame - physics, scripts and drawing - over the last %d frames:\nthe median, and the 95th percentile (the slow ones). Green under %d%% of the budget, amber to it, red past it." \
		% [COUNT_FRAMES, roundi(AMBER_AT * 100.0)]
	_work_label.mouse_filter = Control.MOUSE_FILTER_PASS
	top.add_child(_work_label)
	_count_label = Label.new()
	_count_label.name = "counts"
	_count_label.add_theme_color_override("font_color", COLOUR_TEXT)
	_count_label.add_theme_font_size_override("font_size", 12)
	_count_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_count_label.custom_minimum_size = Vector2(WIDTH - 16.0, 0.0)
	rows.add_child(_count_label)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 4)
	rows.add_child(controls)
	var said := Label.new()
	said.text = "Slime horde"
	said.add_theme_color_override("font_color", COLOUR_TEXT)
	said.add_theme_font_size_override("font_size", 12)
	controls.add_child(said)
	var group := ButtonGroup.new()
	for size in HORDES:
		var button := Button.new()
		button.name = "horde%d" % int(size)
		button.text = "Off" if int(size) == 0 else GameConstants.commas(int(size))
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(set_horde.bind(int(size)))
		controls.add_child(button)
		_horde_buttons.append(button)
	(_horde_buttons[0] as Button).set_pressed_no_signal(true)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(gap)
	var clear := Button.new()
	clear.name = "clearall"
	clear.text = "Clear all"
	clear.tooltip_text = "The horde off and every spawned monster gone."
	clear.focus_mode = Control.FOCUS_NONE
	clear.add_theme_font_size_override("font_size", 12)
	clear.pressed.connect(clear_all)
	controls.add_child(clear)


func set_horde(size: int) -> void:
	"""The slime horde kept at `size` (0 is none); a smaller size than is out
	clears it first, so it fills back to exactly that."""
	horde = clampi(size, 0, int(HORDES.back()))
	var swarm: Node = run.get("swarm") if run != null else null
	if swarm != null and int(swarm.get("alive")) > horde:
		swarm.call("clear")
	for button in _horde_buttons:
		(button as Button).set_pressed_no_signal(str((button as Button).name) == "horde%d" % horde)
	PerfOverlay.forget_work()
	paint()


func clear_all() -> void:
	set_horde(0)
	GmSpawner.clear(get_tree())
	paint()


func _process(delta: float) -> void:
	var swarm: Node = run.get("swarm") if run != null else null
	if swarm != null and horde > 0:
		var short: int = horde - int(swarm.get("alive"))
		if short > 0:
			var me: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
			swarm.call("spawn", mini(short, FILL_A_FRAME),
				me.global_position if me != null else Vector2(run.get("arena_rect").get_center()))
	_repaint_left -= delta
	if _repaint_left <= 0.0:
		_repaint_left = REPAINT_EVERY
		paint()


func counts() -> Dictionary:
	"""What is alive here, by name: the horde's slimes and every spawned
	monster (gmspawner.gd's group), most first in counts_text()."""
	var out: Dictionary = {}
	var swarm: Node = run.get("swarm") if run != null else null
	if swarm != null and int(swarm.get("alive")) > 0:
		out["Horde slimes"] = int(swarm.get("alive"))
	if is_inside_tree():
		for monster in get_tree().get_nodes_in_group(GmSpawner.GROUP):
			if monster.is_queued_for_deletion():
				continue
			var named: String = str(GmSpawner.label_of(str(monster.scene_file_path).get_file().get_basename())[0])
			out[named] = int(out.get(named, 0)) + 1
	return out


static func counts_text(alive: Dictionary) -> String:
	if alive.is_empty():
		return "Nothing here yet - the slime horde below, or Spawn on the GM panel's Testing tab."
	var names: Array = alive.keys()
	names.sort_custom(func(a, b): return int(alive[a]) > int(alive[b]))
	var bits: PackedStringArray = []
	var total: int = 0
	for named in names:
		bits.append("%s %s" % [named, GameConstants.commas(int(alive[named]))])
		total += int(alive[named])
	return "%s   ·   %s in all" % ["  ·  ".join(bits), GameConstants.commas(total)]


static func work_colour(median: float, p95: float, budget: float) -> Color:
	var worst: float = maxf(median, p95)
	if worst > budget:
		return RED
	if worst > budget * AMBER_AT:
		return AMBER
	return GREEN


func paint() -> void:
	if _work_label == null:
		return
	var stats: Dictionary = PerfOverlay.work_stats(COUNT_FRAMES)
	var budget: float = PerfOverlay.budget_ms()
	if int(stats["frames"]) == 0:
		_work_label.text = "work: measuring..."
		_work_label.add_theme_color_override("font_color", COLOUR_TEXT)
	else:
		_work_label.text = "work %.1f ms · slow %.1f ms · of %.1f" % [float(stats["median"]), float(stats["p95"]), budget]
		_work_label.add_theme_color_override("font_color",
			work_colour(float(stats["median"]), float(stats["p95"]), budget))
	_count_label.text = counts_text(counts())
