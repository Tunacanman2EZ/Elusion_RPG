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
	if markers == null or player == null or _area == "":
		return
	if not WorldMap.has_map(_area):
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
