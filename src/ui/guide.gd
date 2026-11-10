# guide.gd - the way to the first fight, pointed at (0.92.0).
#
# The owner's first five minutes, walked: a new character stands in town with
# the welcome's directions read once and gone, and nothing on screen to say
# which way the portal is. Until the character's first kill (level 1 and no
# XP - nothing new is stored: the first kill gives XP) a gold » from the
# game's own font circles the character, turned toward the next step, with
# its name under it:
#
#   town, the spawn side   the portal to the town square, south of the spawn
#   town, the square side  the portal to the Big Field, at the square's north
#   a field                the nearest monster ("Your first enemy")
#
# THE TOWN IS ONE AREA WITH A WALL ACROSS IT. Both portals stand on one
# north-south line, the square's portal (teleportnextarea) south of the
# spawn and the Big Field's (leavetown) south of that again, but the wall
# between them means the nearer one is not the next one. The side of the
# line halfway between the two portals says which half the character is in
# (town_step()). The portals are found by name, so moving one in the editor
# moves the pointer with it.
#
# STEADY (0.112.1). The owner: "the arrow pointing to the first enemy
# jitters". It was placed from get_global_transform_with_canvas(): the camera
# as the last frame DREW it - part way between two ticks, physics
# interpolation - times where the character and the monster stood at the last
# TICK. The two are apart by a share of a step that changes every frame (60
# frames to 80 ticks), so the » shook while either walked. Now both ends are
# where they are drawn: each tick keeps the last two places of the character
# and the target (_physics_process(), after everything has moved), each frame
# blends them by the engine's own fraction, and the screen is worked out from
# the camera at the character's drawn place, held to its limits as Godot holds
# it (player.gd camera_centre()). And it holds on: the target is kept unless
# another is STICKY times nearer, and a » standing over a near target stays
# over it out to NEAR_OUT times NEAR - it flicked between two monsters, and
# between circling and standing over, at the edge.
#
# NO ART MADE: the » is a letter of the theme font, outlined like a name.
# Built by the HUD under its windows (characterhud.gd, _ready()); no
# class_name, so a fresh checkout needs no editor rescan.
extends Control

const TownPortalSquare := "teleportnextarea"
const TownPortalField := "leavetown"
# The visible portal is the Area2D's "teleporter" sprite, well below its root.
const PORTAL_PICTURE := "teleporter"

const WORDS_SQUARE := "Portal to the town square"
const WORDS_FIELD := "Portal to the Big Field"
const WORDS_ENEMY := "Your first enemy"

# How far from the character the » circles, and from how near a target it
# stands over the target instead, pointing down at it.
const RING := 84.0
const NEAR := 130.0
# A character's origin is its feet; the » circles its middle, so pointing up
# it clears the head and the name over it.
const BODY_MIDDLE := 26.0
const OVER := 40.0
const ARROW_SIZE := 30
const WORDS_SIZE := 14
const COLOUR := Color(1.0, 0.86, 0.5, 0.95)
const OUTLINE := Color(0.1, 0.07, 0.07, 0.95)
# How often the target is looked for again; the » moves every frame.
const LOOK_SECONDS := 0.5
# Another monster takes over only when this many times nearer; standing over a
# target, the » keeps standing over it out to this many times NEAR.
const STICKY := 1.3
const NEAR_OUT := 1.15

var arrow: Label = null
var words: Label = null
var target: Node2D = null
var target_words: String = ""
var _look_left: float = 0.0
# Where the character and the target stood at the last two ticks, and which
# nodes those were (a new one starts where it stands).
var _body_seen: Node2D = null
var _body_was: Vector2 = Vector2.ZERO
var _body_now: Vector2 = Vector2.ZERO
var _target_seen: Node2D = null
var _target_was: Vector2 = Vector2.ZERO
var _target_now: Vector2 = Vector2.ZERO
var _over: bool = false


func _init() -> void:
	name = "guide"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	arrow = _label("»", ARROW_SIZE)
	words = _label("", WORDS_SIZE)
	visible = false
	# After everything that moves this tick, so the place kept is this tick's.
	process_physics_priority = 1000


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", COLOUR)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	@warning_ignore("integer_division")
	label.add_theme_constant_override("outline_size", maxi(4, font_size / 4))
	add_child(label)
	return label


# =============================================================================
# THE RULES, pure, for the suite
# =============================================================================

static func wanted(level: int, xp: int) -> bool:
	"""Shown until the first kill: a new character is level 1 with no XP."""
	return level <= 1 and xp <= 0


static func town_step(player: Vector2, square_portal: Vector2, field_portal: Vector2) -> int:
	"""0: the square's portal is next; 1: the Big Field's. The side of the line
	halfway between them (both stand on one north-south road, a wall between)."""
	var middle: Vector2 = (square_portal + field_portal) / 2.0
	var along: Vector2 = field_portal - square_portal
	return 1 if (player - middle).dot(along) > 0.0 else 0


static func place(from: Vector2, to: Vector2, scale_by: float = 1.0, was_over: bool = false) -> Dictionary:
	"""Where the » goes on screen and which way it turns: round the character
	toward the target, or over a target that is near, pointing down at it - and
	still over it out to NEAR_OUT times as far when it already was."""
	var way: Vector2 = to - from
	if way.length() <= NEAR * scale_by * (NEAR_OUT if was_over else 1.0):
		return {"at": to - Vector2(0.0, OVER * scale_by), "angle": PI / 2.0, "over": true}
	return {"at": from + way.normalized() * RING * scale_by, "angle": way.angle(), "over": false}


static func words_at(at: Dictionary, arrow_size: Vector2, words_size: Vector2) -> Vector2:
	"""The words' corner: on the far side of the » from the character, so they
	never sit on it - above a » that points up, below one that points down or
	stands over a target (then above it), under one pointing sideways."""
	var centre: Vector2 = at["at"]
	var angle: float = float(at["angle"])
	var up: bool = sin(angle) < -0.5
	if bool(at["over"]):
		return centre + Vector2(-words_size.x / 2.0, -arrow_size.y * 0.55 - words_size.y)
	if up:
		return centre + Vector2(-words_size.x / 2.0, -arrow_size.y * 0.55 - words_size.y)
	return centre + Vector2(-words_size.x / 2.0, arrow_size.y * 0.55)


# =============================================================================
# EACH FRAME
# =============================================================================

func _process(delta: float) -> void:
	var body: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	if body == null or not wanted(int(body.get("level")), int(body.get("xp"))):
		visible = false
		target = null
		return
	_look_left -= delta
	if _look_left <= 0.0 or target == null or not is_instance_valid(target) or not target.is_inside_tree():
		_look_left = LOOK_SECONDS
		_find_target(body)
	if target == null:
		visible = false
		return
	visible = true
	var grow: float = _scale()
	var body_at: Vector2 = _drawn(body, _body_seen, _body_was, _body_now)
	var from: Vector2 = _on_screen(body, body_at, body_at) - Vector2(0.0, BODY_MIDDLE * grow)
	var to: Vector2 = _on_screen(body, body_at, _drawn(target, _target_seen, _target_was, _target_now))
	var at: Dictionary = place(from, to, grow, _over)
	_over = bool(at["over"])
	arrow.add_theme_font_size_override("font_size", int(round(ARROW_SIZE * grow)))
	words.add_theme_font_size_override("font_size", int(round(WORDS_SIZE * grow)))
	words.text = target_words
	arrow.reset_size()
	words.reset_size()
	arrow.pivot_offset = arrow.size / 2.0
	arrow.position = (at["at"] as Vector2) - arrow.size / 2.0
	arrow.rotation = float(at["angle"])
	words.position = words_at(at, arrow.size, words.size)


func _physics_process(_delta: float) -> void:
	"""The last two ticks' places, kept after everything has moved."""
	if not visible and target == null:
		_body_seen = null
		_target_seen = null
		return
	var body: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	if body != null:
		_body_was = _body_now if body == _body_seen else body.global_position
		_body_now = body.global_position
	_body_seen = body
	var aim: Node2D = target if target != null and is_instance_valid(target) and target.is_inside_tree() else null
	if aim != null:
		_target_was = _target_now if aim == _target_seen else aim.global_position
		_target_now = aim.global_position
	_target_seen = aim


static func _drawn(node: Node2D, seen: Node2D, was: Vector2, now: Vector2) -> Vector2:
	"""Where `node` is drawn this frame: between its last two ticks by the
	engine's fraction, as physics interpolation draws it."""
	if node != seen:
		return node.global_position
	if not node.is_physics_interpolated_and_enabled():
		return now
	return was.lerp(now, Engine.get_physics_interpolation_fraction())


func _on_screen(body: Node2D, body_at: Vector2, point: Vector2) -> Vector2:
	"""`point` on the screen, with the camera where it is drawn this frame: on
	the character drawn at `body_at`, held to its limits."""
	var camera: Camera2D = body.get_node_or_null("camera2d") as Camera2D
	if camera == null or not camera.is_inside_tree() or not camera.is_current() or not body.has_method("camera_centre"):
		return body.get_canvas_transform() * point
	var view: Vector2 = get_viewport().get_visible_rect().size
	var wanted_at: Vector2 = body_at + (camera.global_position - body.global_position) + camera.offset
	var centre: Vector2 = body.call("camera_centre", camera, wanted_at, view)
	return (point - centre) * camera.zoom + view / 2.0


func _scale() -> float:
	"""Bigger under a thumb, as the pad is (touchpad.gd's thumb_scale())."""
	if not TouchControls.active:
		return 1.0
	var menu: GDScript = load("res://src/ui/touchmenu.gd") as GDScript
	return clampf(float(menu.call("thumb_scale_of", self)), 1.0, 1.6)


func _find_target(body: Node2D) -> void:
	var was: Node2D = target if target != null and is_instance_valid(target) and target_words == WORDS_ENEMY else null
	target = null
	var area: String = AreaRegistry.current_area_id()
	var scene: Node = get_tree().current_scene
	if area == "elusion" and scene != null:
		var square: Node2D = _portal(scene, TownPortalSquare)
		var field: Node2D = _portal(scene, TownPortalField)
		if square == null or field == null:
			return
		if town_step(body.global_position, square.global_position, field.global_position) == 0:
			target = square
			target_words = WORDS_SQUARE
		else:
			target = field
			target_words = WORDS_FIELD
		return
	if area == "bigfield" or area == "field":
		var best: Node2D = null
		var best_d: float = INF
		var held: Node2D = was
		var held_d: float = INF
		for node in get_tree().get_nodes_in_group(&"enemies"):
			var enemy := node as Node2D
			if enemy == null or not enemy.is_inside_tree() or not enemy.is_visible_in_tree():
				continue
			if "hp" in enemy and float(enemy.get("hp")) <= 0.0:
				continue
			var d: float = enemy.global_position.distance_squared_to(body.global_position)
			if enemy == held:
				held_d = d
			if d < best_d:
				best_d = d
				best = enemy
		# The one it points at already, unless another is a good deal nearer.
		if held != null and held_d < INF and best_d * STICKY * STICKY > held_d:
			best = held
		target = best
		target_words = WORDS_ENEMY


static func _portal(scene: Node, portal_name: String) -> Node2D:
	"""The portal you see: its sprite, or the area itself where it has none."""
	var area: Node2D = scene.find_child(portal_name, true, false) as Node2D
	if area == null:
		return null
	var picture: Node2D = area.get_node_or_null(PORTAL_PICTURE) as Node2D
	return picture if picture != null else area
