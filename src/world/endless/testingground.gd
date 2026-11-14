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
#
# FIND THE LIMIT, under it (0.152.0, limitsweep.gd): one monster, more and more of it,
# until the work reaches 80% of the budget - what one costs and how many fit,
# kept and copied for the spreadsheet. While it sweeps it has the horde and
# Clear all (hold_controls()), and the panel repaints every SWEEP_REPAINT.

const GmSpawner := preload("res://src/world/gmspawner.gd")
const LimitSweep := preload("res://src/world/endless/limitsweep.gd")
const StressKinds := preload("res://src/world/endless/stresskinds.gd")
const LayerPicture := preload("res://src/ui/hudpicture.gd")
const HORDES := [0, 1000, 3000, 5000]
# Slimes made a frame while the horde fills (the swarm's own fill is a rate).
const FILL_A_FRAME := 250
# The slimes' strength: a mid run's (endlessrun.gd stage 10).
const SLIME_STAGE := 10
const REPAINT_EVERY := 0.25
# Slower while a sweep measures: counting hundreds of monsters is work too.
const SWEEP_REPAINT := 1.0
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
var _clear_button: Button = null
var _repaint_left: float = 0.0
var sweep: Node = null
# OUT OF THE WAY (0.153.0): the owner, "the testing ground menues are
# blocking my viewpoint". Less folds the panel to its title line - the name,
# the work and More - until More; kept while the game runs (static), so a
# second visit opens it as it was.
static var folded: bool = false
var _panel: PanelContainer = null
# The panel as one picture (hudpicture.gd), or null.
var _picture: Node = null
# Hidden by a drag (_notification()), shown again when it ends.
var _hidden_for_drag: bool = false
var _top: HBoxContainer = null
var _fold_button: Button = null
# A spawned monster's name a person reads, by its scene (label_of() once each).
var _label_by_path: Dictionary = {}


func _ready() -> void:
	PerfOverlay.set_shown(true)
	_set_slimes()
	sweep = LimitSweep.new()
	sweep.name = "limitsweep"
	sweep.set("ground", self)
	add_child(sweep)
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
	_panel = panel
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
	_top = top
	_fold_button = Button.new()
	_fold_button.name = "fold"
	_fold_button.focus_mode = Control.FOCUS_NONE
	_fold_button.add_theme_font_size_override("font_size", 12)
	_fold_button.tooltip_text = "Fold the panel to this line, so more of the arena shows; More opens it again."
	_fold_button.pressed.connect(toggle_folded)
	top.add_child(_fold_button)
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
	_clear_button = clear
	sweep.call("build", rows, WIDTH)
	_show_folded()
	# DRAWN AS ONE PICTURE (0.155.1, hudpicture.gd picture_parts()), as the
	# readout is: about 30 draw calls a frame for a panel that changes a few
	# times a second.
	_picture = LayerPicture.picture_parts(_layer, [_panel], "testingpicture", "testingpanellayer")


func toggle_folded() -> void:
	folded = not folded
	_show_folded()


func _show_folded() -> void:
	"""Folded: the title line alone, as narrow as it is; open: everything."""
	if _panel == null or _top == null:
		return
	for child in _top.get_parent().get_children():
		if child != _top:
			(child as CanvasItem).visible = not folded
	_fold_button.text = "More" if folded else "Less"
	_panel.custom_minimum_size = Vector2(0.0 if folded else WIDTH, 0.0)
	# Shrunk from the left, held to the right edge.
	_panel.offset_right = -8.0
	_panel.offset_left = -8.0 - _panel.get_combined_minimum_size().x
	_panel.reset_size()


func hold_controls(held: bool) -> void:
	"""The horde's buttons and Clear all are the sweep's while it runs."""
	for button in _horde_buttons:
		(button as Button).disabled = held
	if _clear_button != null:
		_clear_button.disabled = held


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


func _notification(what: int) -> void:
	# OUT OF THE WAY OF A DRAG (0.155.1). The panel is on its own layer (5),
	# over the HUD's windows, and the bag opens under it: an item dragged to
	# the bag was dropped on the panel and went nowhere. The owner: "dragging
	# item from hotbar to inventory dousnt work because the item goes behind
	# the panel". Godot tells every node when a drag begins and ends.
	if what == NOTIFICATION_DRAG_BEGIN:
		if _panel != null and _panel.visible:
			_panel.visible = false
			_hidden_for_drag = true
	elif what == NOTIFICATION_DRAG_END:
		if _hidden_for_drag and _panel != null:
			_panel.visible = true
		_hidden_for_drag = false


func clear_all() -> void:
	set_horde(0)
	GmSpawner.clear(get_tree())
	# AND WHAT THEY LEFT (0.153.0): their shots in the air and their pools on
	# the floor - 115 slime pools outlived a 300-slime sweep, 0.8 ms a frame
	# under the next one's empty field.
	BulletZone.clear_enemy_shots(self)
	# And Find the limit's own shots (0.154.0, stresskinds.gd).
	StressKinds.clear(get_tree())
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
		_repaint_left = SWEEP_REPAINT if sweep != null and bool(sweep.call("running")) else REPAINT_EVERY
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
			var path: String = str(monster.scene_file_path)
			if not _label_by_path.has(path):
				_label_by_path[path] = str(GmSpawner.label_of(path.get_file().get_basename())[0])
			var named: String = str(_label_by_path[path])
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
