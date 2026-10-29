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
# THE WHOLE MAP, AS BIG AS THE WINDOW (0.96.0)
# =============================================================================
# The owner, of the Big Field and the new Field: "i need players to be able to
# see the whole map". The window fills most of the screen (1160 x 640 as
# drawn, and it resizes), the picture fits it at ANY scale, and ground not yet
# walked is drawn too, darker (WorldMap.display_image(area, true)).
#
# IT WAS A WHOLE NUMBER, ALWAYS, and that is why it could not grow: the Big
# Field is 385 x 322 tiles, which fits a 600 px frame once and not twice, so
# it was drawn at 1x in any window. Drawn at a fraction with nearest
# filtering, a one-pixel tile lands on three screen pixels in some columns and
# four in others - the stutter the old rule was for. So the picture is first
# blown up by a whole number with nearest filtering (sharpen(), MAX_SHARPEN)
# and drawn from there, smoothly (with mipmaps) while it is smaller than that
# on screen and pixel for pixel past it: straight edges at any size.
#
# ZOOM AND DRAG (0.96.0). The owner: "i meant the map not the player ... i
# meant map in hud" - the map is what had to zoom out. It opens on the whole
# area; the mouse wheel over it zooms in and out where the pointer is, a drag
# moves it, and -, + and Whole map in its footer do the same for a finger.
# _zoom is a multiple of the whole-area fit (1 is all of it, at most a tile
# MAX_TILE_PX across); _centre is the map pixel at the middle of the view.
#
# THE PICTURE DOES NOT SIZE THE WINDOW. %mapview fills the frame and clips;
# %mapground draws the picture at _offset, _fit (_layout()), so a window made
# smaller by hand is not held open by its own map.
extends Control


# =============================================================================
# SIGNALS
# =============================================================================

signal closed


# =============================================================================
# CONSTANTS
# =============================================================================

# How far sharpen() blows the picture up, at most, and the largest side it
# may reach. Past MAX_SHARPEN screen pixels a tile it is drawn pixel for pixel
# (nearest), where a column one pixel wider than the next does not show.
const MAX_SHARPEN := 6
const MAX_TEXTURE := 4096

# ZOOM AND DRAG: a notch of the wheel, a press of - or +, and the closest it
# goes - a tile this many interface pixels across (48 is the game's own 3x).
const WHEEL_STEP := 1.25
const BUTTON_STEP := 1.6
const MAX_TILE_PX := 24.0

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
# EVERY PIN, WALKED OR NOT (0.96.0). They were drawn only on ground you had
# seen - "a pin in the dark is a spoiler with an icon" - and now the whole
# area is drawn, so the pins are too: where the ladder is, is what a big map
# is opened for. Monsters still show only on ground you have seen.
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
	"smith":    ["res://art/pack/smith/anvil.png",                     Color(0.78, 0.80, 0.86)],
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
@onready var ground:         Control     = get_node_or_null("%mapground")
@onready var zoom_out_button: Button     = get_node_or_null("%mapzoomout")
@onready var zoom_in_button:  Button     = get_node_or_null("%mapzoomin")
@onready var whole_button:    Button     = get_node_or_null("%mapwhole")


# =============================================================================
# STATE
# =============================================================================

var player: Node = null

var _area: String = ""
# Where the picture is drawn in the marker layer: map pixel p is at
# _offset + p * _fit (_layout()).
var _fit: float = 1.0
var _offset := Vector2.ZERO
# ZOOM AND DRAG: how far in (1 is the whole area), the map pixel at the middle
# of the view (negative: the map's own middle), and a drag under way.
var _zoom: float = 1.0
var _centre := Vector2(-1.0, -1.0)
var _dragging: bool = false
# The picture, blown up _sharp times (refresh()).
var _picture: Texture2D = null
var _sharp: int = 1

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

# Drag by the header, resize from any edge, and come back where it was left.
# One component for all sixteen panels - see src/shared/panelwindow.gd for why
# this is not thirty lines copied into each of them.
#
# HELD IN A MEMBER, not discarded. It is a RefCounted carrying the drag state
# and the signal connections; letting it go frees it and the panel quietly
# stops responding.
var _window: PanelWindow


func _ready() -> void:
	_window = PanelWindow.attach(self, "map")
	if close_button != null:
		close_button.pressed.connect(close)

	# REDRAWN WHILE OPEN, when something is actually uncovered. WorldMap only
	# emits this on a step that reveals a tile that was dark, which is a small
	# fraction of steps — so this is not a per-frame rebuild wearing a signal.
	if not WorldMap.explored.is_connected(_on_explored):
		WorldMap.explored.connect(_on_explored)

	if markers != null:
		markers.draw.connect(_draw_markers)
	# A window resized by hand fits the picture again.
	if view != null:
		view.resized.connect(_on_view_resized)
		view.gui_input.connect(_on_view_input)
	if ground != null:
		ground.draw.connect(_draw_ground)
	if zoom_out_button != null:
		zoom_out_button.pressed.connect(zoom_by.bind(1.0 / BUTTON_STEP))
	if zoom_in_button != null:
		zoom_in_button.pressed.connect(zoom_by.bind(BUTTON_STEP))
	if whole_button != null:
		whole_button.pressed.connect(show_whole)

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
	# OPENS ON THE WHOLE AREA, every time: that is what it is opened for.
	_zoom = 1.0
	_centre = Vector2(-1.0, -1.0)
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

	var image: Image = WorldMap.display_image(_area, true)
	if image == null:
		return

	if view != null:
		var big: Image = sharpen(image, MAX_SHARPEN)
		_sharp = maxi(1, big.get_width() / maxi(1, image.get_width()))
		# Mipmaps, for drawing it smaller than it is without dropping rows.
		big.generate_mipmaps()
		_picture = ImageTexture.create_from_image(big)
		view.texture = null
		view.custom_minimum_size = Vector2.ZERO
		_layout()

	if header_label != null:
		header_label.text = AreaRegistry.display_name(_area) if _area != "" else "Map"

	if explored_label != null:
		explored_label.text = "%d%% explored - the darker ground is still to explore" % roundi(
			WorldMap.explored_fraction(_area) * 100.0)

	_collect_landmarks()


static func fit_for(room: Vector2, map_px: Vector2) -> float:
	"""How big a map of `map_px` pixels is drawn to fill `room`: the largest
	scale at which all of it fits, a fraction or not. 1 for nothing."""
	if map_px.x <= 0.0 or map_px.y <= 0.0 or room.x <= 0.0 or room.y <= 0.0:
		return 1.0
	return minf(room.x / map_px.x, room.y / map_px.y)


static func sharpen(image: Image, on_screen: float) -> Image:
	"""The picture blown up by the whole number that makes it at least as big
	as it is drawn (`on_screen` screen pixels a map pixel), nearest filtered -
	so drawn down from there with linear filtering, every tile's edge is
	straight (THE WHOLE MAP, AS BIG AS THE WINDOW)."""
	var times: int = clampi(ceili(on_screen), 1, MAX_SHARPEN)
	var longest: int = maxi(image.get_width(), image.get_height())
	while times > 1 and longest * times > MAX_TEXTURE:
		times -= 1
	if times == 1:
		return image
	var big: Image = image.duplicate() as Image
	big.resize(image.get_width() * times, image.get_height() * times, Image.INTERPOLATE_NEAREST)
	return big


func _stretch() -> float:
	"""Screen pixels an interface pixel takes - the window's own stretch."""
	if not is_inside_tree():
		return 1.0
	return maxf(get_viewport().get_final_transform().x.length(), 0.01)


func max_zoom() -> float:
	"""As far in as the map goes: a tile MAX_TILE_PX interface pixels across,
	and never less than the whole area."""
	if view == null or _area == "":
		return 1.0
	var whole: float = fit_for(view.size, Vector2(WorldMap.map_size(_area)))
	return maxf(1.0, MAX_TILE_PX / maxf(whole, 0.01))


func _layout() -> void:
	"""Where the picture is drawn in the view - _fit and _offset from _zoom and
	_centre, which is kept so the map never leaves more of the view empty than
	it must - and everything on it with it."""
	if view == null or _area == "":
		return
	var map_px: Vector2 = Vector2(WorldMap.map_size(_area))
	_zoom = clampf(_zoom, 1.0, max_zoom())
	_fit = fit_for(view.size, map_px) * _zoom
	var half: Vector2 = view.size * 0.5 / maxf(_fit, 0.0001)
	var centre: Vector2 = _centre if _centre.x >= 0.0 else map_px * 0.5
	for axis in 2:
		if map_px[axis] <= half[axis] * 2.0:
			centre[axis] = map_px[axis] * 0.5
		else:
			centre[axis] = clampf(centre[axis], half[axis], map_px[axis] - half[axis])
	_centre = centre
	_offset = (view.size * 0.5 - centre * _fit).round()
	if ground != null:
		# Smooth while the picture is drawn smaller than it was blown up;
		# pixel for pixel past that.
		ground.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS \
			if _fit * _stretch() < float(_sharp) else CanvasItem.TEXTURE_FILTER_NEAREST
		ground.queue_redraw()
	view.mouse_default_cursor_shape = Control.CURSOR_MOVE if _zoom > 1.001 else Control.CURSOR_ARROW
	if markers != null:
		markers.queue_redraw()


func _draw_ground() -> void:
	if _picture == null or _area == "":
		return
	ground.draw_texture_rect(_picture, Rect2(_offset, Vector2(WorldMap.map_size(_area)) * _fit), false)


func zoom_by(factor: float, at: Variant = null) -> void:
	"""Zoom by `factor` (over 1 is in) about `at` in the view - the map under
	it stays under it - or about the middle of the view."""
	if view == null or _area == "":
		return
	var point: Vector2 = at if at is Vector2 else view.size * 0.5
	var under: Vector2 = (point - _offset) / maxf(_fit, 0.0001)
	_zoom = clampf(_zoom * factor, 1.0, max_zoom())
	var new_fit: float = fit_for(view.size, Vector2(WorldMap.map_size(_area))) * _zoom
	_centre = under + (view.size * 0.5 - point) / maxf(new_fit, 0.0001)
	_layout()


func pan_by(screen_delta: Vector2) -> void:
	"""Move the map with a drag of `screen_delta` view pixels."""
	_centre -= screen_delta / maxf(_fit, 0.0001)
	_layout()


func show_whole() -> void:
	_zoom = 1.0
	_centre = Vector2(-1.0, -1.0)
	_layout()


func _on_view_input(event: InputEvent) -> void:
	"""The wheel zooms where the pointer is, a held button drags, a trackpad's
	pinch zooms - all of it taken here, so none of it reaches the camera."""
	var button := event as InputEventMouseButton
	if button != null:
		if button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var notches: float = button.factor if button.factor > 0.0 else 1.0
			var step: float = pow(WHEEL_STEP, notches)
			zoom_by(step if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / step, button.position)
			view.accept_event()
		elif button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
			view.accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		if not (motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_dragging = false
			return
		pan_by(motion.relative)
		view.accept_event()
		return
	var pinch := event as InputEventMagnifyGesture
	if pinch != null:
		zoom_by(pinch.factor, pinch.position)
		view.accept_event()


func _on_view_resized() -> void:
	if not visible:
		return
	_layout()


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
	_draw_monsters()
	_draw_landmarks()
	_draw_party()
	_draw_arrow()
	_draw_hover_label()


# =============================================================================
# MONSTERS AND YOUR PARTY (0.42.0)
# =============================================================================
# The owner, of what a party should do: "Party on the map", and "monsters on
# map also by element color". Both are read live from this area's scene each
# frame the map is open: every monster still alive on ground you have explored
# as a dot in its element's colour (Element.colour_for, the colour its own
# attacks are tinted), a boss a bigger one; and everyone in your party standing in this area as a ring in
# the party's colour (party.gd) with their name. Only this area: the presence
# server tells a game about the people in its own area, and the Party window
# says where the rest are.

const MONSTER_RADIUS := 2.5
const BOSS_RADIUS := 4.5
const MONSTER_EDGE := Color(0.05, 0.04, 0.06, 0.9)
const PARTY_RADIUS := 4.0


func _on_map(world: Vector2) -> Variant:
	"""Where `world` is drawn on the marker layer, or null off the map."""
	var pixel: Vector2 = WorldMap.pixel_for(world, _area)
	var bounds: Vector2 = Vector2(WorldMap.map_size(_area))
	if pixel.x < 0.0 or pixel.y < 0.0 or pixel.x > bounds.x or pixel.y > bounds.y:
		return null
	return _offset + pixel * _fit


static func monster_colour(enemy: Node) -> Color:
	"""A monster's dot: its element's colour - physical's steel for none."""
	var element: int = int(enemy.call("current_element")) if enemy.has_method("current_element") else Element.Type.NONE
	return Element.colour_for(element)


static func shows_monster(enemy: Node) -> bool:
	"""Alive and in the world - not a picture going away."""
	if not (enemy is BaseEnemy) or enemy.is_queued_for_deletion():
		return false
	return not (enemy as BaseEnemy)._death_resolved


func _draw_monsters() -> void:
	if not is_inside_tree():
		return
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		if not shows_monster(enemy):
			continue
		# NOT THROUGH THE FOG: a monster on ground you have not explored would
		# draw the map you have not found yet, one cluster at a time.
		var where: Vector2 = (enemy as Node2D).global_position
		if not WorldMap.is_seen(_area, WorldMap.tile_at(_area, where)):
			continue
		var at: Variant = _on_map(where)
		if at == null:
			continue
		var radius: float = BOSS_RADIUS if enemy is BossEnemy else MONSTER_RADIUS
		markers.draw_circle(at, radius + 1.0, MONSTER_EDGE)
		markers.draw_circle(at, radius, monster_colour(enemy))


func _draw_party() -> void:
	if not Party.in_one() or not is_inside_tree():
		return
	var font: Font = get_theme_default_font()
	for picture in get_tree().get_nodes_in_group(&"remoteplayers"):
		var who: String = str(picture.get("display_name"))
		if not Party.is_member(who) or not (picture is Node2D):
			continue
		var at: Variant = _on_map((picture as Node2D).global_position)
		if at == null:
			continue
		markers.draw_circle(at, PARTY_RADIUS + 1.5, MONSTER_EDGE)
		markers.draw_arc(at, PARTY_RADIUS, 0.0, TAU, 20, Party.COLOUR, 2.0, true)
		if font != null:
			var words: Vector2 = font.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
			var spot: Vector2 = (at as Vector2) + Vector2(-words.x / 2.0, -PARTY_RADIUS - 4.0)
			markers.draw_string_outline(font, spot, who, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, MONSTER_EDGE)
			markers.draw_string(font, spot, who, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Party.COLOUR)


func _draw_arrow() -> void:
	if player == null:
		return

	# Off the edge of what is mapped — which happens legitimately at the
	# boundary of an area, and drawing the arrow clamped to the rim would
	# say "you are here" about somewhere you are not.
	var spot: Variant = _on_map(player.global_position)
	if spot == null:
		return
	var at: Vector2 = spot

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

	# THE MAP'S SIZE, NOT THE MARKER LAYER'S. This runs inside refresh(),
	# on the frame the panel opens - before layout has sized the layer - so
	# markers.size would be zero and every pin would be thrown away as off
	# the edge. The first draft did exactly that. Each keeps its map pixel;
	# where it is drawn, zoomed and dragged, is _pin_at().
	var bounds: Vector2 = Vector2(WorldMap.map_size(_area))
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
		var pixel: Vector2 = WorldMap.pixel_for(world_pos, _area)
		if pixel.x < 0.0 or pixel.y < 0.0 or pixel.x > bounds.x or pixel.y > bounds.y:
			continue

		var style: Array = LANDMARK_STYLE[kind]
		_landmarks.append({
			"kind": kind,
			"label": str(info.get("label", kind.capitalize())),
			"colour": info.get("colour", style[1]),
			"pixel": pixel,
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


func _pin_at(landmark: Dictionary) -> Vector2:
	"""Where a pin is drawn now, zoomed and dragged. ROUNDED, because the
	icon is 16 art pixels drawn at 1x, and a texture drawn at a fractional
	position is resampled - half a pixel off is a blurred coin. The arrow is a
	polygon and can sit anywhere; a sprite cannot."""
	return (_offset + (landmark["pixel"] as Vector2) * _fit).round()


func _update_hover() -> void:
	_hover = -1
	if markers == null or _landmarks.is_empty() or _dragging:
		return
	var mouse: Vector2 = markers.get_local_mouse_position()
	var best: float = HOVER_RADIUS * HOVER_RADIUS
	for i in _landmarks.size():
		var d: float = mouse.distance_squared_to(_pin_at(_landmarks[i]))
		if d <= best:
			best = d
			_hover = i


# =============================================================================
# LANDMARKS - DRAWING
# =============================================================================

func _draw_landmarks() -> void:
	for i in _landmarks.size():
		var lm: Dictionary = _landmarks[i]
		var c: Vector2 = _pin_at(lm)
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
	var pin: Vector2 = _pin_at(lm)
	var origin: Vector2 = pin + Vector2(PIN_RADIUS + 4.0, -box.y * 0.5)
	if origin.x + box.x > markers.size.x:
		origin.x = pin.x - PIN_RADIUS - 4.0 - box.x
	origin = origin.round()

	markers.draw_rect(Rect2(origin, box), PIN_BACK)
	markers.draw_rect(Rect2(origin, box), lm["colour"], false, 1.0)
	markers.draw_string(font, origin + Vector2(pad.x, pad.y + float(LABEL_FONT_SIZE)),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, Color(0.98, 0.94, 0.86))
