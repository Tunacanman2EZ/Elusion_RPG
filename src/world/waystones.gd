# waystones.gd - the Big Field's waystones (0.118.0): seven stones, one in the
# Crossroads and one where each wing begins. Walk past one once and it is lit;
# from the map, a lit one is a three-second stand-still away, from anywhere in
# the Big Field, the Field or town.
#
# WHY. The owner: "we need to speed up the game even more look into what we
# can advance"; measured, the far lands were 15 to 28 seconds' walk from the
# arrival, every trip, and he approved "waystones" with the rest of the plan,
# then the design and its picture ("yes looks good"): the teleport portal's own
# art (art/teleport, his), lit when found, a pin on the map, three seconds
# standing still, from town too.
#
# LIT IS THE MAP'S, NOT A NEW SAVE. A stone is lit when the map tile it stands
# on has been explored (WorldMap.is_seen) - walking within the map's reveal
# (seven tiles round you) of it. The explored map is already saved with the
# character on the server, so a lit stone stays lit on any computer, and
# nothing new is stored or sent.
#
# TRAVEL IS A PLACEMENT, AS EVERY TELEPORT IS. Position is the game's (the
# server knows only the area), so the stand-still and the landing are here:
# AreaRegistry.go_to() - in the Big Field it places you (and snaps the camera),
# from elsewhere it travels there and lands you on the spot. Not from the
# minigames, the boss rooms or anywhere else not in FROM.
#
# THE STAND-STILL (Travel, an inner class, a child of the player): a bar over
# your head for CHANNEL_SECONDS; moving more than MOVE_SLACK, being hit
# (Player.took_damage) or falling stops it and says why.
#
# Added to every area by AreaRegistry, like the sleeper; only the Big Field
# gets stones. The map (mapscreen.gd) draws their pins, a row of them, and
# starts travel from either.
extends Node

const NODE_NAME := "waystones"
const GROUP := &"waystones"
const TRAVEL_GROUP := &"waystone_travel"
# Where the stones stand, and the areas they can be reached from.
const AREA := "bigfield"
const FROM := ["elusion", "field", "bigfield"]
# Each where its wing begins: the furthest point along the walk from the
# Crossroads into the wing that is clear of walls and at least 250 px from
# any monster the plan places (worked out from tools/maps/bigfield_build.json).
# The Crossroads' stands within the map's reveal (WorldMap.SEEN_RADIUS) of the
# arrival, so it is lit the moment you arrive.
const STONES := [
	{"id": "crossroads", "place": "The Crossroads", "at": Vector2(1776, 2448)},
	{"id": "courts", "place": "The Courts", "at": Vector2(1336, 2280)},
	{"id": "chasm", "place": "The Chasm", "at": Vector2(2152, 1432)},
	{"id": "caverns", "place": "The Caverns", "at": Vector2(4296, 2104)},
	{"id": "fortress", "place": "The Fortress", "at": Vector2(2504, 3528)},
	{"id": "descent", "place": "The Descent", "at": Vector2(4760, 2552)},
	{"id": "crypt", "place": "The Crypt", "at": Vector2(1544, 3896)},
]
const CHANNEL_SECONDS := 3.0
const MOVE_SLACK := 6.0
# Where you land: just in front of the stone.
const ARRIVE := Vector2(0, 30)
const FRAMES := "res://art/teleport/teleportframes.tres"
const ART_SCALE := 1.5
const LIT_COLOUR := Color(0.42, 0.95, 1.0)
const UNLIT_COLOUR := Color(0.62, 0.62, 0.66)
const UNLIT_TINT := Color(0.26, 0.26, 0.3)

# THE SUITE'S SEAM: when valid, a finished stand-still calls this with the
# stone instead of jumping (the jump changes scenes).
static var jump_with: Callable = Callable()


static func add_to(scene: Node) -> Node:
	"""The stones for `scene`, or null when it is not the Big Field."""
	if scene == null or scene.scene_file_path.get_file().get_basename() != AREA:
		return null
	var helper := (load("res://src/world/waystones.gd") as GDScript).new() as Node
	helper.name = NODE_NAME
	scene.add_child(helper)
	var holder: Node = scene.get_node_or_null("ysortworld/props")
	if holder == null:
		holder = scene
	for stone in STONES:
		var made := Stone.new()
		made.name = "waystone_%s" % stone["id"]
		made.position = stone["at"]
		made.stone = stone
		holder.add_child(made)
	return helper


static func stone_for(stone_id: String) -> Dictionary:
	for stone in STONES:
		if stone["id"] == stone_id:
			return stone
	return {}


static func is_lit(stone: Dictionary) -> bool:
	"""Found: the map tile it stands on has been explored (Stone.found(), the
	one rule - an inner class sees this script's constants, not its static
	functions, so the rule lives where both can reach it)."""
	return Stone.found(stone)


static func reachable_from(area: String) -> bool:
	return FROM.has(area)


static func travel_to(tree: SceneTree, stone_id: String, area: String = "") -> String:
	"""Starts the stand-still to `stone_id`: "" when it started, otherwise
	why not, in words for the player. `area` is where you stand (the map
	passes the one it shows; empty, AreaRegistry's)."""
	var stone: Dictionary = stone_for(stone_id)
	if stone.is_empty():
		return "There is no such waystone."
	if not is_lit(stone):
		return "You have not found that waystone yet - walk past it once."
	if not reachable_from(area if area != "" else AreaRegistry.current_area_id()):
		return "Waystones cannot be reached from here."
	var player := tree.get_first_node_in_group("player") as Node2D
	if player == null or player.get("is_dying") == true:
		return "You cannot travel right now."
	for old in tree.get_nodes_in_group(TRAVEL_GROUP):
		old.queue_free()
	var trip := Travel.new()
	trip.stone = stone
	trip.jumper = jump_with
	trip.position = Vector2(0, -52)
	player.add_child(trip)
	return ""


static func land(stone: Dictionary) -> bool:
	"""The jump itself: in front of the stone, in the Big Field."""
	return Travel.jump(stone)


# =============================================================================
# A STONE
# =============================================================================

class Stone extends Node2D:
	var stone: Dictionary = {}
	var _art: AnimatedSprite2D = null
	var _label: Label = null
	var _lit: bool = false

	static func found(of: Dictionary) -> bool:
		if of.is_empty():
			return false
		return WorldMap.is_seen(AREA, WorldMap.tile_at(AREA, of["at"]))

	func _init() -> void:
		add_to_group("map_landmarks")
		add_to_group(GROUP)

	func _ready() -> void:
		_art = AnimatedSprite2D.new()
		_art.name = "art"
		_art.sprite_frames = load(FRAMES)
		_art.scale = Vector2(ART_SCALE, ART_SCALE)
		# Standing on its foot, so it sorts with whoever walks past it.
		_art.position = Vector2(0, -24)
		_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_art)
		_label = Label.new()
		_label.name = "label"
		_label.add_theme_font_size_override("font_size", 7)
		_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_label.add_theme_constant_override("outline_size", 3)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.size = Vector2(160, 14)
		_label.position = Vector2(-80, -66)
		_label.z_index = 5
		add_child(_label)
		reset_physics_interpolation()
		if not WorldMap.explored.is_connected(_on_explored):
			WorldMap.explored.connect(_on_explored)
		paint()

	func _exit_tree() -> void:
		if WorldMap.explored.is_connected(_on_explored):
			WorldMap.explored.disconnect(_on_explored)

	func _on_explored(_area: String) -> void:
		if not _lit:
			paint()

	func lit() -> bool:
		return _lit

	func paint() -> void:
		_lit = found(stone)
		if _art != null:
			if _lit:
				_art.modulate = Color.WHITE
				if not _art.is_playing():
					_art.play("default")
			else:
				_art.modulate = UNLIT_TINT
				_art.stop()
		if _label != null:
			_label.text = ("Waystone - %s" % str(stone.get("place", ""))) if _lit else "Waystone"
			_label.add_theme_color_override("font_color",
				LIT_COLOUR if _lit else UNLIT_COLOUR)

	func map_landmark() -> Dictionary:
		var lit_now: bool = found(stone)
		return {"kind": "waystone",
			"label": ("Waystone: %s - click to travel" % str(stone.get("place", ""))) if lit_now
				else "Waystone (not found yet)",
			"colour": LIT_COLOUR if lit_now else UNLIT_COLOUR,
			"waystone": str(stone.get("id", "")), "lit": lit_now}


# =============================================================================
# THE STAND-STILL
# =============================================================================

class Travel extends Node2D:
	var stone: Dictionary = {}
	var jumper: Callable = Callable()
	var left: float = 3.0
	var _player: Node2D = null
	var _from := Vector2.ZERO
	var _stopped: String = ""
	var _stopped_left: float = 0.0
	var _hit: bool = false

	static func jump(to: Dictionary) -> bool:
		Audio.play("teleport")
		return AreaRegistry.go_to(AREA, (to["at"] as Vector2) + ARRIVE)

	func _init() -> void:
		add_to_group(TRAVEL_GROUP)
		z_index = 50
		left = CHANNEL_SECONDS

	func _ready() -> void:
		_player = get_parent() as Node2D
		if _player != null:
			_from = _player.global_position
			if _player.has_signal("took_damage"):
				_player.connect("took_damage", _on_hit)
		queue_redraw()

	func _exit_tree() -> void:
		if _player != null and is_instance_valid(_player) and _player.has_signal("took_damage") \
				and _player.is_connected("took_damage", _on_hit):
			_player.disconnect("took_damage", _on_hit)

	func _on_hit(_amount: int, _type: String) -> void:
		_hit = true

	func stop(why: String) -> void:
		_stopped = why
		_stopped_left = 1.5
		queue_redraw()

	func _process(delta: float) -> void:
		if _stopped != "":
			_stopped_left -= delta
			if _stopped_left <= 0.0:
				queue_free()
			return
		if _player == null or not is_instance_valid(_player) or _player.get("is_dying") == true:
			queue_free()
			return
		if _hit:
			stop("Travel stopped - you were hit")
			return
		if _player.global_position.distance_to(_from) > MOVE_SLACK:
			stop("Travel stopped - you moved")
			return
		left -= delta
		queue_redraw()
		if left <= 0.0:
			var where: Dictionary = stone
			queue_free()
			if jumper.is_valid():
				jumper.call(where)
			else:
				jump(where)

	func share_done() -> float:
		return clampf(1.0 - left / CHANNEL_SECONDS, 0.0, 1.0)

	func _draw() -> void:
		var font: Font = ThemeDB.fallback_font
		var text: String = _stopped if _stopped != "" else "Travelling to %s" % str(stone.get("place", ""))
		var width: float = 64.0
		var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
		draw_string_outline(font, Vector2(-text_width * 0.5, -6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, 3,
			Color(0, 0, 0))
		draw_string(font, Vector2(-text_width * 0.5, -6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 7,
			Color(1.0, 0.75, 0.5) if _stopped != "" else LIT_COLOUR)
		if _stopped == "":
			draw_rect(Rect2(-width * 0.5 - 1, -3, width + 2, 6), Color(0, 0, 0, 0.8))
			draw_rect(Rect2(-width * 0.5, -2, width * share_done(), 4), LIT_COLOUR)

