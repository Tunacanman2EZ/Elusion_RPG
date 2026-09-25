# mapscreen.gd — the full map of the area you are standing in, as much of it
# as you have walked.
# attached to res://scene/ui/menus/mapscreen.tscn.
#
# Opened by the HUD's map button, which until now was wired to a handler whose
# whole body was print("map pressed (not yet implemented)").
#
# =============================================================================
# THE PANEL DRAWS; WorldMap DECIDES
# =============================================================================
# Everything here is presentation. WorldMap owns the terrain, the fog, what has
# been explored and how that is stored; this scales the picture to fit, puts an
# arrow on it, and gets out of the way. There is no map state in this file at
# all — reopening the panel asks WorldMap again rather than trusting anything
# it kept from last time.
#
# =============================================================================
# THE SCALE IS A WHOLE NUMBER, ALWAYS
# =============================================================================
# The field is 126 x 108 pixels and the frame it goes in is around 500 x 380,
# so the honest fit is 3.5x. Drawn at 3.5x, a one-pixel tile lands on three
# screen pixels in some columns and four in others, and a map made of straight
# coastlines comes out with a stutter in it.
#
# So it is floored to 3x and centred. Losing a little of the frame is invisible;
# a shimmering grid is not. The same reasoning the HUD readouts use for their
# font sizes, and why the TextureRect is texture_filter = nearest.
extends Control


# =============================================================================
# SIGNALS
# =============================================================================

signal closed


# =============================================================================
# CONSTANTS
# =============================================================================

const MIN_SCALE := 1
const MAX_SCALE := 8

# What _fit_scale() returns on the one frame before the frame has been laid
# out and has no size to measure against. See the note at its use.
const FALLBACK_SCALE := 4

# The arrow. Drawn rather than authored, because it is four points and an
# artist should not be asked for a triangle.
const MARKER_COLOUR := Color(1.0, 0.86, 0.3)
const MARKER_EDGE := Color(0.15, 0.12, 0.05)
const MARKER_SIZE := 7.0

# WHICH WAY THE ARROW POINTS, and the mistake this replaces.
#
# There was a table here mapping "up"/"down"/"left"/"right" to vectors, looked
# up with str(player.last_direction). last_direction is a Vector2 —
# `var last_direction := Vector2.DOWN` — so that produced "(0, 1)", which
# matched no key, and the arrow pointed down no matter which way you walked.
#
# It is a vector already. Facing.gd converts it to one of the four cardinal
# names and back, which is worth the round trip rather than using the raw
# vector: last_direction can be diagonal while the SPRITE shows a cardinal
# pose, and an arrow that points somewhere the character visibly is not
# looking is worse than one that is a few degrees coarse.
#
# Facing.from_vec_total()'s own comment explains why its fallback matters:
# nobody chose UP for a zero vector, it fell out of an else. DOWN is passed
# here explicitly, because a character standing still faces the camera.


# =============================================================================
# LANDMARKS
# =============================================================================
# EVERY PIN COMES FROM THE THING IT MARKS. Anything in the "map_landmarks"
# group answers map_landmark() with its kind and a name, and this panel draws
# it where it actually stands. Nothing here lists where the bank is - so a
# bank chest moved in the editor moves on the map, and a second one placed
# anywhere gets a pin without a line of code. The group is joined in each
# landmark's _init(); see bankchest.gd for the pattern.
#
# FOG APPLIES. A landmark whose tile has not been seen is not drawn, for the
# same reason the terrain under it is not: the map is what you have walked,
# and a pin in the dark is a spoiler with an icon.
const LANDMARK_GROUP := "map_landmarks"

# Kind -> [16px icon, or "" for a drawn glyph; pin colour].
#
# 16PX ART ONLY, drawn at exactly 1x. The pack's 32px art would have to be
# halved to fit a pin, and nearest filtering halves pixel art by throwing
# every other row away. Where the pack has no 16px icon that fits, the glyph
# is drawn instead - four or five shapes, crisp at any size, and no second
# artist to ask.
const LANDMARK_STYLE := {
	"shop":     ["res://art/pack/currency/goldpile.png",           Color(1.0, 0.84, 0.35)],
	"cooking":  ["res://art/pack/icons/cookingiconcharacterselection.png",   Color(1.0, 0.56, 0.26)],
	"fishing":  ["res://art/pack/icons/fishingiconcharacterstats.png",       Color(0.45, 0.76, 1.0)],
	"bank":     ["", Color(0.95, 0.78, 0.38)],
	"teleport": ["", Color(0.42, 0.95, 1.0)],
	"exit":     ["", Color(0.92, 0.90, 0.84)],
	"ladder":   ["", Color(0.82, 0.64, 0.42)],
	"boss":     ["", Color(1.0, 0.32, 0.32)],   # each gate overrides with its element
}

const PIN_RADIUS := 9.0
const PIN_BACK := Color(0.08, 0.06, 0.04, 0.88)
const ICON_PX := 16.0
const HOVER_RADIUS := 11.0
const LABEL_FONT_SIZE := 11


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var close_button:   Button      = get_node_or_null("%mapclosebutton")
@onready var header_label:   Label       = get_node_or_null("%mapheaderlabel")
@onready var explored_label: Label       = get_node_or_null("%mapexploredlabel")
@onready var frame:          Control     = get_node_or_null("%mapframe")
@onready var view:           TextureRect = get_node_or_null("%mapview")
@onready var markers:        Control     = get_node_or_null("%mapmarkers")


# =============================================================================
# STATE
# =============================================================================

var player: Node = null

var _area: String = ""
var _scale: int = 1

# Collected on refresh(), not per frame: a landmark does not move, and the
# group walk plus a fog lookup each is not work to redo sixty times a second
# for a picture that has not changed. Each entry: kind, label, colour, at
# (marker-layer pixels, rounded - see _collect_landmarks).
var _landmarks: Array = []
var _hover: int = -1
var _icon_cache: Dictionary = {}


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	if close_button != null:
		close_button.pressed.connect(close)

	# REDRAWN WHILE OPEN, when something is actually uncovered. WorldMap only
	# emits this on a step that reveals a tile that was dark, which is a small
	# fraction of steps — so this is not a per-frame rebuild wearing a signal.
	if not WorldMap.explored.is_connected(_on_explored):
		WorldMap.explored.connect(_on_explored)

	if markers != null:
		markers.draw.connect(_draw_markers)

	visible = false


func _process(_delta: float) -> void:
	# THE ARROW MOVES, THE MAP DOES NOT. Only the marker layer is asked to
	# repaint, and only while the panel is open — the terrain underneath is a
	# texture that has not changed.
	if visible and markers != null:
		_update_hover()
		markers.queue_redraw()


# =============================================================================
# OPENING AND CLOSING
# =============================================================================

func set_player(p: Node) -> void:
	player = p


func open() -> void:
	visible = true
	refresh()


func close() -> void:
	visible = false
	closed.emit()


func refresh() -> void:
	_area = WorldMap.area_id()

	if not WorldMap.ensure_built(_area):
		# AN AREA WITH NO TILEMAP IS A REAL STATE, not a failure — the boss
		# arena is one room and some scenes are built from instanced pieces.
		# Saying so is better than an empty panel that looks broken.
		if view != null:
			view.texture = null
		if header_label != null:
			header_label.text = "Map"
		if explored_label != null:
			explored_label.text = "Nothing here can be mapped."
		_landmarks.clear()
		_hover = -1
		return

	var image: Image = WorldMap.display_image(_area)
	if image == null:
		return

	if view != null:
		view.texture = ImageTexture.create_from_image(image)
		_scale = _fit_scale(image.get_size())
		# custom_minimum_size, not scale: scaling a Control scales its children
		# and its input rect too, and the marker layer is a child. Sizing the
		# TextureRect and letting stretch_mode fill it keeps the arrow's
		# coordinate space the same as the panel's.
		view.custom_minimum_size = Vector2(image.get_size()) * float(_scale)

	if header_label != null:
		header_label.text = _area.capitalize() if _area != "" else "Map"

	if explored_label != null:
		explored_label.text = "%d%% explored" % roundi(
			WorldMap.explored_fraction(_area) * 100.0)

	_collect_landmarks()


func _fit_scale(image_size: Vector2i) -> int:
	# NOT `size`. This script extends Control, which already has a `size`
	# property, and a parameter by that name shadows it — so `frame.size`
	# below still means the frame but a bare `size` would mean the argument.
	# Godot warns about it; the warning is right.
	if frame == null or image_size.x <= 0 or image_size.y <= 0:
		return 1
	var room: Vector2 = frame.size
	if room.x <= 0.0 or room.y <= 0.0:
		# Before the first layout pass the frame has no size yet. Guessing at
		# 1x here would be a map the size of a postage stamp for one frame;
		# the next refresh() corrects it, and opening the panel calls one.
		#
		# A constant rather than MAX_SCALE / 2, which Godot flagged as an
		# integer division. It was not a rounding bug — 8 / 2 is exact — but
		# the expression implied a relationship that isn't real: this number
		# is "a sensible guess for one frame", not "half the maximum", and
		# raising MAX_SCALE should not quietly change it.
		return FALLBACK_SCALE
	var fit: int = int(min(room.x / float(image_size.x), room.y / float(image_size.y)))
	return clampi(fit, MIN_SCALE, MAX_SCALE)


func _on_explored(area: String) -> void:
	if visible and area == _area:
		refresh()


# =============================================================================
# THE ARROW
# =============================================================================

func _draw_markers() -> void:
	# UNDER THE ARROW, then the arrow, then the hover label over both. The
	# arrow has early returns of its own - off the edge of the map, no player
	# yet - and those must not take the landmarks down with them, which they
	# would if the three were one function.
	if markers == null or _area == "" or not WorldMap.has_map(_area):
		return
	_draw_landmarks()
	_draw_arrow()
	_draw_hover_label()


func _draw_arrow() -> void:
	if player == null:
		return

	var pixel: Vector2 = WorldMap.pixel_for(player.global_position, _area)
	var at: Vector2 = pixel * float(_scale)

	# `bounds`, not `size` — same shadowing as _fit_scale(); this one reads
	# the marker layer's size, and a local called `size` would hide this
	# Control's own property from everything below it.
	var bounds: Vector2 = markers.size
	if at.x < 0.0 or at.y < 0.0 or at.x > bounds.x or at.y > bounds.y:
		# Off the edge of what is mapped — which happens legitimately at the
		# boundary of an area, and drawing the arrow clamped to the rim would
		# say "you are here" about somewhere you are not.
		return

	var facing: Vector2 = Vector2.DOWN
	if "last_direction" in player:
		facing = Facing.to_vec(Facing.from_vec_total(player.last_direction, Facing.DOWN))
	if facing == Vector2.ZERO:
		facing = Vector2.DOWN

	# A TRIANGLE POINTING THE WAY YOU FACE, because a dot answers "where am I"
	# and half the reason to open a map is "which way am I pointing".
	var side: Vector2 = Vector2(-facing.y, facing.x)
	var points := PackedVector2Array([
		at + facing * MARKER_SIZE,
		at - facing * MARKER_SIZE * 0.6 + side * MARKER_SIZE * 0.6,
		at - facing * MARKER_SIZE * 0.6 - side * MARKER_SIZE * 0.6,
	])

	# Outlined, because a yellow arrow on pale ground and a yellow arrow on
	# water have to both be findable at a glance.
	markers.draw_colored_polygon(points, MARKER_COLOUR)
	markers.draw_polyline(points + PackedVector2Array([points[0]]),
		MARKER_EDGE, 1.0, true)


# =============================================================================
# LANDMARKS - COLLECTING
# =============================================================================

func _collect_landmarks() -> void:
	_landmarks.clear()
	_hover = -1
	if markers == null or _area == "" or not WorldMap.has_map(_area):
		return

	# THE IMAGE'S SIZE, NOT THE MARKER LAYER'S. This runs inside refresh(),
	# on the frame the panel opens - before layout has sized the layer - so
	# markers.size would be zero and every pin would be thrown away as off
	# the edge. The first draft did exactly that. The image is known now.
	var bounds: Vector2 = Vector2(WorldMap.map_size(_area)) * float(_scale)
	for node in get_tree().get_nodes_in_group(LANDMARK_GROUP):
		# Node2D, not "anything": the pin goes where it stands, and a Control
		# or a plain Node has no world position to put one at.
		if not (node is Node2D) or not node.is_inside_tree():
			continue
		if not node.has_method("map_landmark"):
			continue

		var info: Dictionary = node.map_landmark()
		# EMPTY MEANS "NOT RIGHT NOW". The field's arrival portal answers
		# this way - it is one-way and vanishes after first use, so a pin
		# on it would advertise a way out that is not there.
		if info.is_empty():
			continue
		var kind: String = str(info.get("kind", ""))
		if not LANDMARK_STYLE.has(kind):
			# Loud, because the alternative is a landmark that silently has no
			# pin - which looks exactly like one that was never placed.
			push_warning("mapscreen: '%s' reports unknown landmark kind '%s'" % [node.name, kind])
			continue

		var world_pos: Vector2 = (node as Node2D).global_position
		if not WorldMap.is_seen(_area, WorldMap.tile_at(_area, world_pos)):
			continue

		# ROUNDED, because the icon is 16 art pixels drawn at 1x, and a
		# texture drawn at a fractional position is resampled - half a pixel
		# off is a blurred coin. The arrow is a polygon and can sit anywhere;
		# a sprite cannot.
		var at: Vector2 = (WorldMap.pixel_for(world_pos, _area) * float(_scale)).round()
		if at.x < 0.0 or at.y < 0.0 or at.x > bounds.x or at.y > bounds.y:
			continue

		var style: Array = LANDMARK_STYLE[kind]
		_landmarks.append({
			"kind": kind,
			"label": str(info.get("label", kind.capitalize())),
			"colour": info.get("colour", style[1]),
			"at": at,
		})


func _icon_for(kind: String) -> Texture2D:
	if _icon_cache.has(kind):
		return _icon_cache[kind]
	var path: String = LANDMARK_STYLE[kind][0]
	var tex: Texture2D = null
	if path != "" and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	# Cached even when null, so a missing file costs one failed lookup rather
	# than one per frame - and falls through to the drawn glyph, which is a
	# worse pin but a better one than a hole.
	_icon_cache[kind] = tex
	return tex


func _update_hover() -> void:
	_hover = -1
	if markers == null or _landmarks.is_empty():
		return
	var mouse: Vector2 = markers.get_local_mouse_position()
	var best: float = HOVER_RADIUS * HOVER_RADIUS
	for i in _landmarks.size():
		var d: float = mouse.distance_squared_to(_landmarks[i]["at"])
		if d <= best:
			best = d
			_hover = i


# =============================================================================
# LANDMARKS - DRAWING
# =============================================================================

func _draw_landmarks() -> void:
	for i in _landmarks.size():
		var lm: Dictionary = _landmarks[i]
		var c: Vector2 = lm["at"]
		var colour: Color = lm["colour"]
		var hovered: bool = i == _hover

		# THE PIN: a dark disc with a ring in the kind's colour. Same idea as
		# the arrow's outline - it has to read on pale grass and on water.
		markers.draw_circle(c, PIN_RADIUS + (1.0 if hovered else 0.0), PIN_BACK)
		markers.draw_arc(c, PIN_RADIUS + (1.0 if hovered else 0.0), 0.0, TAU, 24,
			colour.lightened(0.25) if hovered else colour, 1.0, true)

		var tex: Texture2D = _icon_for(lm["kind"])
		if tex != null:
			markers.draw_texture_rect(tex, Rect2(c - Vector2(ICON_PX, ICON_PX) * 0.5,
				Vector2(ICON_PX, ICON_PX)), false)
		else:
			_draw_glyph(lm["kind"], c, colour)


func _draw_glyph(kind: String, c: Vector2, colour: Color) -> void:
	# Five shapes, each chosen to be told apart at a glance at 16px rather than
	# to be pretty up close. Coordinates are offsets from the pin's centre.
	var dark := Color(0.12, 0.09, 0.06)
	match kind:
		"bank":
			# A chest: body, lid, clasp.
			markers.draw_rect(Rect2(c + Vector2(-5, -1), Vector2(10, 6)), colour.darkened(0.25))
			markers.draw_rect(Rect2(c + Vector2(-5, -5), Vector2(10, 4)), colour)
			markers.draw_rect(Rect2(c + Vector2(-5, -5), Vector2(10, 10)), dark, false, 1.0)
			markers.draw_rect(Rect2(c + Vector2(-1, -2), Vector2(2, 3)), dark)
		"teleport":
			# Two rings: a way through, not a way out.
			markers.draw_arc(c, 5.0, 0.0, TAU, 20, colour, 1.5, true)
			markers.draw_arc(c, 2.5, 0.0, TAU, 12, colour.lightened(0.3), 1.5, true)
		"exit":
			# A door ajar: frame, and an arrow leaving through it.
			markers.draw_rect(Rect2(c + Vector2(-5, -6), Vector2(6, 12)), colour, false, 1.5)
			var tip := c + Vector2(6, 0)
			markers.draw_line(c + Vector2(-1, 0), tip, colour, 1.5)
			markers.draw_colored_polygon(PackedVector2Array([
				tip + Vector2(0, 0), tip + Vector2(-3, -3), tip + Vector2(-3, 3)]), colour)
		"ladder":
			# Two rails, three rungs.
			markers.draw_line(c + Vector2(-3.5, -6), c + Vector2(-3.5, 6), colour, 1.5)
			markers.draw_line(c + Vector2(3.5, -6), c + Vector2(3.5, 6), colour, 1.5)
			for y in [-3.5, 0.0, 3.5]:
				markers.draw_line(c + Vector2(-3.5, y), c + Vector2(3.5, y), colour, 1.0)
		"boss":
			# A diamond in the gate's element colour, with a dark heart - the
			# one pin that should look like a warning.
			var d := PackedVector2Array([c + Vector2(0, -6), c + Vector2(6, 0),
				c + Vector2(0, 6), c + Vector2(-6, 0)])
			markers.draw_colored_polygon(d, colour)
			markers.draw_polyline(d + PackedVector2Array([d[0]]), dark, 1.0, true)
			markers.draw_circle(c, 1.6, dark)
		_:
			markers.draw_circle(c, 3.0, colour)


func _draw_hover_label() -> void:
	# THE NAME, ONLY ON HOVER. Nine pins with nine names always showing is a
	# map covered in words; a coin that says "Shop" when you point at it is a
	# map that explains itself when asked.
	if _hover < 0 or _hover >= _landmarks.size():
		return
	var lm: Dictionary = _landmarks[_hover]
	var text: String = lm["label"]
	var font: Font = ThemeDB.fallback_font
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
	var pad := Vector2(4, 2)
	var box := Vector2(text_size.x, float(LABEL_FONT_SIZE) + 2.0) + pad * 2.0

	# To the right of the pin, flipped left if that would run off the map.
	var origin: Vector2 = lm["at"] + Vector2(PIN_RADIUS + 4.0, -box.y * 0.5)
	if origin.x + box.x > markers.size.x:
		origin.x = lm["at"].x - PIN_RADIUS - 4.0 - box.x
	origin = origin.round()

	markers.draw_rect(Rect2(origin, box), PIN_BACK)
	markers.draw_rect(Rect2(origin, box), lm["colour"], false, 1.0)
	markers.draw_string(font, origin + Vector2(pad.x, pad.y + float(LABEL_FONT_SIZE)),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, Color(0.98, 0.94, 0.86))
