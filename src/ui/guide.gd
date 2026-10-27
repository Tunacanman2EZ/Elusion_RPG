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

var arrow: Label = null
var words: Label = null
var target: Node2D = null
var target_words: String = ""
var _look_left: float = 0.0


func _init() -> void:
	name = "guide"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	arrow = _label("»", ARROW_SIZE)
	words = _label("", WORDS_SIZE)
	visible = false


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", COLOUR)
	label.add_theme_color_override("font_outline_color", OUTLINE)
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


static func place(from: Vector2, to: Vector2, scale_by: float = 1.0) -> Dictionary:
	"""Where the » goes on screen and which way it turns: round the character
	toward the target, or over a target that is near, pointing down at it."""
	var way: Vector2 = to - from
	if way.length() <= NEAR * scale_by:
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
	var from: Vector2 = body.get_global_transform_with_canvas().origin - Vector2(0.0, BODY_MIDDLE * grow)
	var to: Vector2 = target.get_global_transform_with_canvas().origin
	var at: Dictionary = place(from, to, grow)
	arrow.add_theme_font_size_override("font_size", int(round(ARROW_SIZE * grow)))
	words.add_theme_font_size_override("font_size", int(round(WORDS_SIZE * grow)))
	words.text = target_words
	arrow.reset_size()
	words.reset_size()
	arrow.pivot_offset = arrow.size / 2.0
	arrow.position = (at["at"] as Vector2) - arrow.size / 2.0
	arrow.rotation = float(at["angle"])
	words.position = words_at(at, arrow.size, words.size)


func _scale() -> float:
	"""Bigger under a thumb, as the pad is (touchpad.gd's thumb_scale())."""
	if not TouchControls.active:
		return 1.0
	var menu: GDScript = load("res://src/ui/touchmenu.gd") as GDScript
	return clampf(float(menu.call("thumb_scale_of", self)), 1.0, 1.6)


func _find_target(body: Node2D) -> void:
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
		for node in get_tree().get_nodes_in_group(&"enemies"):
			var enemy := node as Node2D
			if enemy == null or not enemy.is_inside_tree() or not enemy.is_visible_in_tree():
				continue
			if "hp" in enemy and float(enemy.get("hp")) <= 0.0:
				continue
			var d: float = enemy.global_position.distance_squared_to(body.global_position)
			if d < best_d:
				best_d = d
				best = enemy
		target = best
		target_words = WORDS_ENEMY


static func _portal(scene: Node, portal_name: String) -> Node2D:
	"""The portal you see: its sprite, or the area itself where it has none."""
	var area: Node2D = scene.find_child(portal_name, true, false) as Node2D
	if area == null:
		return null
	var picture: Node2D = area.get_node_or_null(PORTAL_PICTURE) as Node2D
	return picture if picture != null else area
