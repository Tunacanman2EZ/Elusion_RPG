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
# walked is drawn too, darker (the fog over it, WorldMap.fog_image(area, true)).
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
#
# WALKING WITH IT OPEN (0.112.1). The owner: "map is lagging when walking and
# open". Each step that uncovered ground rebuilt the whole picture - 54 ms in
# the Big Field, several times a second. The terrain is built once an area now
# (_built_for, kept while the panel lives), and the fog is a layer of its own
# over it ("fog", a child of %mapground): one map pixel a tile, drawn crisp by
# FOG_SHADER, and a step repaints only what it uncovered (_on_explored(),
# WorldMap.paint_fog() on WorldMap.last_reveal) - a few hundred pixels and a
# 460 KB texture, where it was 4 million and a 22 MB one. The "explored" line
# is counted again at most every EXPLORED_LINE_SECONDS.
#
# THE WAYSTONES (0.118.0). The Big Field's waystones (src/world/waystones.gd)
# are pins of their own, "waystone" - cyan when found, grey when not - and a
# click on a found one (a press and release that did not drag,
# CLICK_SLACK) starts the stand-still to it and shuts the map. A row under the
# map, "waystonerow" (_build_waystone_row()), lists all seven wherever they
# can be reached from (Waystones.FROM: town, the Field, the Big Field), so
# they are a click away from town too, where their pins are not on the map.
extends Control

const Waystones := preload("res://src/world/waystones.gd")


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
# A tile's edge drawn sharp at any size: the texel's own colour except within
# a screen pixel of its edge, where it blends - so the fog's edges line up with
# the terrain's, blown up and drawn down, without blowing the fog up too.
const FOG_SHADER := """shader_type canvas_item;
void fragment() {
	vec2 size = vec2(textureSize(TEXTURE, 0));
	vec2 texel = UV * size;
	vec2 seam = floor(texel + 0.5);
	vec2 width = max(fwidth(texel), vec2(0.0001));
	texel = seam + clamp((texel - seam) / width, -0.5, 0.5);
	COLOR = texture(TEXTURE, texel / size);
}
"""
# How often, at most, the "% explored" line is counted again while walking.
const EXPLORED_LINE_SECONDS := 0.5

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
	"waystone": ["", Color(0.42, 0.95, 1.0)],
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
# The picture, blown up _sharp times (refresh()) - the terrain alone, built
# for the area and size in _built_for and not again.
var _picture: Texture2D = null
var _sharp: int = 1
var _built_for: Array = []
# The fog over it, one pixel a tile, and its layer (WALKING WITH IT OPEN).
var _fog: Image = null
var _fog_picture: ImageTexture = null
var fog_layer: Control = null
var _explored_stale: bool = false
var _explored_left: float = 0.0

# Collected on refresh(), not per frame: a landmark does not move, and the
# group walk plus a fog lookup each is not work to redo sixty times a second
# for a picture that has not changed. Each entry: kind, label, colour, at
# (marker-layer pixels, rounded - see _collect_landmarks).
var _landmarks: Array = []
var _hover: int = -1
var _icon_cache: Dictionary = {}
# THE WAYSTONES: how far a press has dragged (a click is under CLICK_SLACK),
# and the row of them under the map.
const CLICK_SLACK := 5.0
var _press_travel: float = 0.0
var waystone_row: HFlowContainer = null
# How to use them, under the row (PLAYERS DID NOT KNOW, waystones.gd).
var waystone_hint: Label = null
const WAYSTONE_HINT := "Click a lit waystone, then stand still for 3 seconds to travel there. Grey ones: walk past them in the Big Field to light them."
var _waystone_buttons: Dictionary = {}


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
		# The monsters' own layer, under the pins and the arrow (see
		# MONSTER_PASS_MS).
		monster_layer = Control.new()
		monster_layer.name = "mapmonsters"
		monster_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		monster_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		for r in MONSTER_REGIONS * MONSTER_REGIONS:
			var region := Control.new()
			region.name = "region%d" % r
			region.mouse_filter = Control.MOUSE_FILTER_IGNORE
			region.set_anchors_preset(Control.PRESET_FULL_RECT)
			region.draw.connect(_draw_monsters.bind(region, r))
			monster_layer.add_child(region)
		markers.add_sibling(monster_layer)
		markers.get_parent().move_child(monster_layer, markers.get_index())
	# A window resized by hand fits the picture again.
	if view != null:
		view.resized.connect(_on_view_resized)
		view.gui_input.connect(_on_view_input)
	if ground != null:
		ground.draw.connect(_draw_ground)
		fog_layer = Control.new()
		fog_layer.name = "fog"
		fog_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fog_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		fog_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var crisp := ShaderMaterial.new()
		crisp.shader = Shader.new()
		crisp.shader.code = FOG_SHADER
		fog_layer.material = crisp
		fog_layer.draw.connect(_draw_fog)
		ground.add_child(fog_layer)
	if zoom_out_button != null:
		zoom_out_button.pressed.connect(zoom_by.bind(1.0 / BUTTON_STEP))
	if zoom_in_button != null:
		zoom_in_button.pressed.connect(zoom_by.bind(BUTTON_STEP))
	if whole_button != null:
		whole_button.pressed.connect(show_whole)
	_build_waystone_row()
	_build_key()

	visible = false


func _process(delta: float) -> void:
	# THE ARROW MOVES, THE MAP DOES NOT. Only the marker layer is asked to
	# repaint, and only while the panel is open — the terrain underneath is a
	# texture that has not changed.
	if visible and markers != null:
		_update_hover()
		markers.queue_redraw()
		_gather_monsters(MONSTER_PASS_MS, delta)
	_explored_left -= delta
	if visible and _explored_stale and _explored_left <= 0.0:
		_say_explored()


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


func refresh(area: String = "") -> void:
	"""The area you stand in (or `area`, for the suite), drawn afresh."""
	_area = area if area != "" else WorldMap.area_id()
	_paint_waystone_row()

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

	var image: Image = WorldMap.terrain_image(_area)
	if image == null:
		return

	if view != null:
		# THE TERRAIN ONCE AN AREA: it is the same picture every time.
		var key: Array = [_area, WorldMap.map_size(_area)]
		if _picture == null or _built_for != key:
			var big: Image = sharpen(image, MAX_SHARPEN)
			@warning_ignore("integer_division")
			_sharp = maxi(1, big.get_width() / maxi(1, image.get_width()))
			# Mipmaps, for drawing it smaller than it is without dropping rows.
			big.generate_mipmaps()
			_picture = ImageTexture.create_from_image(big)
			_built_for = key
		_fog = WorldMap.fog_image(_area, true)
		_fog_picture = ImageTexture.create_from_image(_fog) if _fog != null else null
		view.texture = null
		view.custom_minimum_size = Vector2.ZERO
		_layout()

	if header_label != null:
		header_label.text = AreaRegistry.display_name(_area) if _area != "" else "Map"

	_fill_key()
	_say_explored()
	_collect_landmarks()
	# Every monster at once as the map opens; a slice a frame after.
	_pass_list = []
	_pass_at = 0
	_pass_wait = 0.0
	_gather_monsters(GATHER_ALL_MS)


func _say_explored() -> void:
	"""The "% explored" line, counted now."""
	_explored_stale = false
	_explored_left = EXPLORED_LINE_SECONDS
	if explored_label != null:
		explored_label.text = "%d%% explored - the darker ground is still to explore" % roundi(
			WorldMap.explored_fraction(_area) * 100.0)


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
	if fog_layer != null:
		fog_layer.queue_redraw()
	view.mouse_default_cursor_shape = Control.CURSOR_MOVE if _zoom > 1.001 else Control.CURSOR_ARROW
	if markers != null:
		markers.queue_redraw()
	_redraw_regions(true)


func _draw_ground() -> void:
	if _picture == null or _area == "":
		return
	ground.draw_texture_rect(_picture, Rect2(_offset, Vector2(WorldMap.map_size(_area)) * _fit), false)


func _draw_fog() -> void:
	"""The fog over the terrain, in the same rect (WALKING WITH IT OPEN)."""
	if _fog_picture == null or _area == "":
		return
	fog_layer.draw_texture_rect(_fog_picture, Rect2(_offset, Vector2(WorldMap.map_size(_area)) * _fit), false)


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
			if button.pressed:
				_press_travel = 0.0
			elif _dragging and _press_travel <= CLICK_SLACK:
				# A CLICK, NOT A DRAG: a found waystone under it is a trip.
				_dragging = false
				_click_pin()
			_dragging = button.pressed
			view.accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		if not (motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_dragging = false
			return
		_press_travel += motion.relative.length()
		pan_by(motion.relative)
		view.accept_event()
		return
	var pinch := event as InputEventMagnifyGesture
	if pinch != null:
		zoom_by(pinch.factor, pinch.position)
		view.accept_event()


func _click_pin() -> void:
	"""The pin under a click: a waystone is a trip there (or why not)."""
	_update_hover()
	if _hover < 0 or _hover >= _landmarks.size():
		return
	var stone_id: String = str(_landmarks[_hover].get("waystone", ""))
	if stone_id != "":
		travel_to_waystone(stone_id)


func travel_to_waystone(stone_id: String) -> String:
	"""Starts the stand-still and shuts the map, or says on the footer why
	not. Answers what Waystones.travel_to() did."""
	var why: String = Waystones.travel_to(get_tree(), stone_id, _area)
	if why == "":
		close()
	elif explored_label != null:
		explored_label.text = why
	return why


func _build_waystone_row() -> void:
	"""Every waystone, a button each, above the footer - so they can be
	reached from town, where their pins are not on the map."""
	var footer: Node = explored_label.get_parent() if explored_label != null else null
	if footer == null or footer.get_parent() == null:
		return
	waystone_row = HFlowContainer.new()
	waystone_row.name = "waystonerow"
	waystone_row.add_theme_constant_override("h_separation", 6)
	waystone_row.add_theme_constant_override("v_separation", 4)
	var title := Label.new()
	title.text = "Travel by waystone:"
	title.add_theme_color_override("font_color", Waystones.LIT_COLOUR)
	waystone_row.add_child(title)
	for stone in Waystones.STONES:
		var button := Button.new()
		button.name = str(stone["id"])
		button.text = str(stone["place"]).trim_prefix("The ")
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(travel_to_waystone.bind(str(stone["id"])))
		# PLAYERS DID NOT KNOW (waystones.gd): a found stone is a cyan button,
		# plainly one; one not found is a dim outline.
		for look in ["normal", "hover", "pressed", "disabled"]:
			button.add_theme_stylebox_override(look, _waystone_look(look))
		button.add_theme_color_override("font_color", Waystones.LIT_COLOUR)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_color_override("font_disabled_color", Color(Waystones.UNLIT_COLOUR, 0.7))
		waystone_row.add_child(button)
		_waystone_buttons[str(stone["id"])] = button
	waystone_hint = Label.new()
	waystone_hint.name = "waystonehint"
	waystone_hint.text = WAYSTONE_HINT
	waystone_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	waystone_hint.add_theme_font_size_override("font_size", 12)
	waystone_hint.add_theme_color_override("font_color", Color(0.78, 0.82, 0.86))
	var column: Node = footer.get_parent()
	column.add_child(waystone_row)
	column.move_child(waystone_row, footer.get_index())
	column.add_child(waystone_hint)
	column.move_child(waystone_hint, footer.get_index())


func _waystone_look(look: String) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	var cyan: Color = Waystones.LIT_COLOUR
	match look:
		"hover":
			box.bg_color = Color(cyan, 0.32)
			box.border_color = cyan
		"pressed":
			box.bg_color = Color(cyan, 0.45)
			box.border_color = Color.WHITE
		"disabled":
			box.bg_color = Color(0.2, 0.2, 0.22, 0.25)
			box.border_color = Color(Waystones.UNLIT_COLOUR, 0.35)
		_:
			box.bg_color = Color(cyan, 0.16)
			box.border_color = Color(cyan, 0.75)
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.content_margin_left = 8.0
	box.content_margin_right = 8.0
	box.content_margin_top = 2.0
	box.content_margin_bottom = 2.0
	return box


func _paint_waystone_row() -> void:
	"""Shown where they can be reached from; a stone not found is greyed."""
	if waystone_row == null:
		return
	waystone_row.visible = Waystones.reachable_from(_area)
	if waystone_hint != null:
		waystone_hint.visible = waystone_row.visible
	for stone in Waystones.STONES:
		var button: Button = _waystone_buttons.get(str(stone["id"]))
		if button == null:
			continue
		var found: bool = Waystones.is_lit(stone)
		button.disabled = not found
		button.tooltip_text = ("Travel to %s - stand still for %d seconds" % [stone["place"], int(Waystones.CHANNEL_SECONDS)]) \
			if found else "Not found yet - walk past it once in the Big Field"


func _on_view_resized() -> void:
	if not visible:
		return
	_layout()


func _on_explored(area: String) -> void:
	"""A step uncovered ground: repaint that much of the fog, not the map."""
	if not visible or area != _area:
		return
	if _fog == null or _fog_picture == null or _fog.get_size() != WorldMap.map_size(_area):
		refresh()
		return
	WorldMap.paint_fog(_area, WorldMap.last_reveal, true, _fog)
	_fog_picture.update(_fog)
	_explored_stale = true


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


func _draw_monsters(region: Control, r: int) -> void:
	"""One region's dots from the last pass - drawn again only when they
	changed or the view moved."""
	if _area == "" or not WorldMap.has_map(_area) or r >= _dot_px.size():
		return
	var spots: Array = _dot_px[r]
	var colours: Array = _dot_colours[r]
	var bosses: Array = _dot_boss[r]
	for i in spots.size():
		var at: Vector2 = _offset + (spots[i] as Vector2) * _fit
		var radius: float = BOSS_RADIUS if bosses[i] else MONSTER_RADIUS
		region.draw_circle(at, radius + 1.0, MONSTER_EDGE)
		region.draw_circle(at, radius, colours[i])


# DRAWN WHEN THEY MOVE, GATHERED A SLICE A FRAME (0.135.8). The owner's
# readout with the map open over the Big Field at 16x: 17 fps, scripts
# 52-57 ms every frame - each of 8,611 monsters looked up and drawn twice,
# every frame the map was open. Now they are gathered a slice a frame until
# MONSTER_PASS_MS is spent, a pass every MONSTER_PASS_GAP (in one frame at
# 1x; about a quarter of a second at 16x); each pass's dots, the same dots
# as before, go to monster_layer, a grid of MONSTER_REGIONS x
# MONSTER_REGIONS layers, and only a region whose dots changed is drawn
# again: the sleeping crowd's stand still. Moving or zooming the map draws
# them all. The arrow, the pins and your party still move every frame, and
# opening the map gathers every monster at once (GATHER_ALL_MS).
const MONSTER_PASS_MS := 1.5
const MONSTER_PASS_GAP := 0.1
const MONSTER_REGIONS := 4
const GATHER_ALL_MS := 1.0e6
var monster_layer: Control = null
var _pass_list: Array = []
var _pass_at: int = 0
var _pass_wait: float = 0.0
var _pass_px: Array = []
var _pass_colours: Array = []
var _pass_boss: Array = []
var _pass_counts: Dictionary = {}
var _pass_bosses: int = 0
# The last finished pass, a region at a time: what monster_layer draws.
var _dot_px: Array = []
var _dot_colours: Array = []
var _dot_boss: Array = []
# Regions drawn again as the last pass ended, for the suite.
var regions_redrawn: int = 0


func _gather_monsters(budget_ms: float, delta: float = 0.0) -> bool:
	"""Gathers monsters until `budget_ms` is spent. True when a pass ended."""
	if not is_inside_tree() or _area == "":
		return false
	if _pass_at == 0 and _pass_list.is_empty():
		_pass_wait -= delta
		if _pass_wait > 0.0:
			return false
		_start_pass()
	var started: int = Time.get_ticks_usec()
	var limit: int = int(budget_ms * 1000.0)
	var bounds := Vector2(WorldMap.map_size(_area))
	while _pass_at < _pass_list.size():
		var enemy: Variant = _pass_list[_pass_at]
		_pass_at += 1
		if is_instance_valid(enemy) and shows_monster(enemy):
			_gather_one(enemy, bounds)
		if (_pass_at & 31) == 0 and Time.get_ticks_usec() - started >= limit:
			return false
	_finish_pass()
	return true


func _start_pass() -> void:
	_pass_list = get_tree().get_nodes_in_group(&"enemies")
	_pass_at = 0
	_pass_px = []
	_pass_colours = []
	_pass_boss = []
	for r in MONSTER_REGIONS * MONSTER_REGIONS:
		# Plain Arrays: a Packed one inside an Array is handed out as a copy,
		# and an append to it is lost.
		_pass_px.append([])
		_pass_colours.append([])
		_pass_boss.append([])
	_pass_counts = {}
	_pass_bosses = 0


func _gather_one(enemy: Node, bounds: Vector2) -> void:
	# NOT THROUGH THE FOG: a monster on ground you have not explored would
	# draw the map you have not found yet, one cluster at a time.
	var where: Vector2 = (enemy as Node2D).global_position
	if not WorldMap.is_seen(_area, WorldMap.tile_at(_area, where)):
		return
	var pixel: Vector2 = WorldMap.pixel_for(where, _area)
	if pixel.x < 0.0 or pixel.y < 0.0 or pixel.x > bounds.x or pixel.y > bounds.y:
		return
	var element: int = int(enemy.call("current_element")) if enemy.has_method("current_element") else Element.Type.NONE
	var boss: bool = enemy is BossEnemy
	_pass_counts[element] = int(_pass_counts.get(element, 0)) + 1
	if boss:
		_pass_bosses += 1
	var r: int = mini(int(pixel.x / maxf(bounds.x, 1.0) * MONSTER_REGIONS), MONSTER_REGIONS - 1) \
		+ MONSTER_REGIONS * mini(int(pixel.y / maxf(bounds.y, 1.0) * MONSTER_REGIONS), MONSTER_REGIONS - 1)
	(_pass_px[r] as Array).append(pixel)
	(_pass_colours[r] as Array).append(Element.colour_for(element))
	(_pass_boss[r] as Array).append(boss)


func _finish_pass() -> void:
	"""The pass's dots to the regions - each drawn again only if it changed."""
	regions_redrawn = 0
	var everything: bool = _dot_px.size() != _pass_px.size()
	for r in _pass_px.size():
		var changed: bool = everything or _dot_px[r] != _pass_px[r] or _dot_colours[r] != _pass_colours[r] \
			or _dot_boss[r] != _pass_boss[r]
		if changed and monster_layer != null and r < monster_layer.get_child_count():
			(monster_layer.get_child(r) as CanvasItem).queue_redraw()
			regions_redrawn += 1
	_dot_px = _pass_px
	_dot_colours = _pass_colours
	_dot_boss = _pass_boss
	_count_key(_pass_counts, _pass_bosses)
	_pass_list = []
	_pass_at = 0
	_pass_wait = MONSTER_PASS_GAP


func _redraw_regions(_all: bool) -> void:
	if monster_layer == null:
		return
	for region in monster_layer.get_children():
		(region as CanvasItem).queue_redraw()


func dots_drawn() -> int:
	var n: int = 0
	for spots in _dot_px:
		n += (spots as Array).size()
	return n


# =============================================================================
# THE KEY (0.135.0)
# =============================================================================
# The owner, of the map: "time to improve map colored grid on right side
# explaining monsters". A column right of the map: each element's dot as the
# map draws it (bigger, to be read), its name, and how many of them you can see
# on the map now - alive, on ground you have explored, so the key gives away
# no more than the dots do. A row with none is dimmed, not hidden: the key
# reads the same in every area. In the Big Field each says where its land is
# (Lands.WINGS), and the stirring land's says so. Then the boss's dot, your
# party's ring and your arrow. Shown only where monsters are.

const KEY_WIDTH := 172.0
# Between the counts and the key's scroll bar, while it shows.
const KEY_BAR_GAP := 8
# By where they stand in the Big Field, first wing to last; physical last.
const KEY_ORDER := [Element.Type.LIGHT, Element.Type.WIND, Element.Type.WATER, Element.Type.ICE,
	Element.Type.LIGHTNING, Element.Type.POISON, Element.Type.EARTH, Element.Type.FIRE,
	Element.Type.DARK, Element.Type.NONE]
# Where the lands that never stir stand (the rest from Lands.WINGS).
const KEY_WHERE := {Element.Type.LIGHTNING: "the Chasm", Element.Type.POISON: "the Chasm",
	Element.Type.NONE: "the Crypt"}
const KEY_DOT := 4.5
const KEY_BOSS_DOT := 6.5
const KEY_DIM := 0.38
const KEY_TEXT := Color(0.92, 0.90, 0.86)
const KEY_SOFT := Color(0.66, 0.68, 0.74)
const KEY_STIR := Color(1.0, 0.78, 0.35)

var key_panel: PanelContainer = null
var key_total: Label = null
# element (or "boss") -> {"row": the row, "count": its number, "where": its line}
var _key_rows: Dictionary = {}
var _key_counts: Dictionary = {}


func _build_key() -> void:
	"""The map and the key side by side: the frame moves into a row with the
	key to its right."""
	if frame == null or frame.get_parent() == null:
		return
	var column: Node = frame.get_parent()
	var row := HBoxContainer.new()
	row.name = "maprow"
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	column.move_child(row, frame.get_index())
	frame.reparent(row, false)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_panel = PanelContainer.new()
	key_panel.name = "mapkey"
	key_panel.custom_minimum_size = Vector2(KEY_WIDTH, 0)
	key_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var look := StyleBoxFlat.new()
	look.bg_color = Color(0.06, 0.05, 0.08, 0.86)
	look.border_color = Color(0.30, 0.26, 0.36)
	look.set_border_width_all(1)
	look.set_corner_radius_all(4)
	look.set_content_margin_all(8)
	key_panel.add_theme_stylebox_override("panel", look)
	row.add_child(key_panel)
	# THE KEY SCROLLS RATHER THAN STRETCH THE WINDOW (0.135.6). At Largest
	# text in the tallest fonts its rows stood 754 px tall, past a 1280 x 720
	# screen. In here it is as tall as the map beside it, and scrolls only
	# when its text is too big for that.
	var scroller := ScrollContainer.new()
	scroller.name = "keyscroll"
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.mouse_filter = Control.MOUSE_FILTER_PASS
	key_panel.add_child(scroller)
	# A gap before the bar, only while there is one: the counts stood
	# against it.
	var rows := MarginContainer.new()
	rows.name = "keyrows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(rows)
	var bar: VScrollBar = scroller.get_v_scroll_bar()
	bar.visibility_changed.connect(_key_bar_shown.bind(rows, bar))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_child(list)
	var head := HBoxContainer.new()
	head.add_child(_key_label("Monsters", 14, KEY_TEXT))
	key_total = _key_label("0", 14, KEY_TEXT)
	key_total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key_total.tooltip_text = "Monsters you can see on the map"
	head.add_child(key_total)
	list.add_child(head)
	list.add_child(HSeparator.new())
	for element in KEY_ORDER:
		list.add_child(_key_row(element, "dot", Element.colour_for(element),
			Element.name_for(element).capitalize()))
	list.add_child(HSeparator.new())
	list.add_child(_key_row("boss", "boss", Color(0.55, 0.55, 0.6), "Boss"))
	var boss_line: Label = _key_rows["boss"]["where"]
	boss_line.text = "a bigger dot, in its colour"
	boss_line.visible = true
	list.add_child(_key_row("party", "ring", Party.COLOUR, "Your party"))
	list.add_child(_key_row("you", "arrow", MARKER_COLOUR, "You"))
	var note := _key_label("Seen on ground you have explored.", 10, KEY_SOFT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(note)


func _key_bar_shown(rows: MarginContainer, bar: VScrollBar) -> void:
	rows.add_theme_constant_override("margin_right", KEY_BAR_GAP if bar.visible else 0)


func _key_label(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label


func _key_row(id: Variant, kind: String, colour: Color, title: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "key_%s" % [Element.name_for(id) if id is int else str(id)]
	row.add_theme_constant_override("separation", 6)
	var swatch := Control.new()
	swatch.custom_minimum_size = Vector2(16, 16)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.draw.connect(_draw_swatch.bind(swatch, kind, colour))
	row.add_child(swatch)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", -3)
	words.add_child(_key_label(title, 12, KEY_TEXT))
	var where := _key_label("", 10, KEY_SOFT)
	where.visible = false
	words.add_child(where)
	row.add_child(words)
	var count := _key_label("", 12, KEY_TEXT)
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(count)
	_key_rows[id] = {"row": row, "count": count, "where": where}
	return row


func _draw_swatch(swatch: Control, kind: String, colour: Color) -> void:
	"""A row's mark, drawn as the map draws it."""
	var c: Vector2 = swatch.size * 0.5
	match kind:
		"dot", "boss":
			var radius: float = KEY_BOSS_DOT if kind == "boss" else KEY_DOT
			swatch.draw_circle(c, radius + 1.0, MONSTER_EDGE)
			swatch.draw_circle(c, radius, colour)
		"ring":
			swatch.draw_circle(c, PARTY_RADIUS + 1.5, MONSTER_EDGE)
			swatch.draw_arc(c, PARTY_RADIUS, 0.0, TAU, 20, colour, 2.0, true)
		"arrow":
			var points := PackedVector2Array([c + Vector2(0, MARKER_SIZE),
				c + Vector2(-MARKER_SIZE * 0.6, -MARKER_SIZE * 0.6), c + Vector2(MARKER_SIZE * 0.6, -MARKER_SIZE * 0.6)])
			swatch.draw_colored_polygon(points, colour)
			swatch.draw_polyline(points + PackedVector2Array([points[0]]), MARKER_EDGE, 1.0, true)


func key_where(element: int) -> String:
	"""Where an element's monsters stand in the Big Field, or ''."""
	if Lands.WINGS.has(element):
		return str(Lands.WINGS[element][0])
	return str(KEY_WHERE.get(element, ""))


func _fill_key() -> void:
	"""On refresh: shown where monsters are, and in the Big Field where each
	land is and which one stirs."""
	if key_panel == null:
		return
	key_panel.visible = is_inside_tree() and not get_tree().get_nodes_in_group(&"enemies").is_empty()
	var big: bool = _area == "bigfield"
	for element in KEY_ORDER:
		var where: Label = _key_rows[element]["where"]
		var stirs: bool = big and element != Element.Type.NONE and Lands.stirring() == element
		where.text = (key_where(element) + (" - stirring" if stirs else "")) if big else ""
		where.add_theme_color_override("font_color", KEY_STIR if stirs else KEY_SOFT)
		where.visible = where.text != ""
	_key_counts.clear()
	_count_key({}, 0)


func _count_key(counts: Dictionary, bosses: int) -> void:
	"""Each row's number, as the dots were just drawn - changed only when it
	changes."""
	if key_panel == null or not key_panel.visible:
		return
	var total: int = 0
	for element in KEY_ORDER:
		var n: int = int(counts.get(element, 0))
		total += n
		_key_number(element, n)
	_key_number("boss", bosses)
	_key_number("party", -1)
	_key_number("you", -1)
	if key_total != null:
		key_total.text = str(total)


func _key_number(id: Variant, n: int) -> void:
	if _key_counts.get(id, -2) == n:
		return
	_key_counts[id] = n
	var entry: Dictionary = _key_rows[id]
	(entry["count"] as Label).text = str(n) if n >= 0 else ""
	(entry["row"] as Control).modulate.a = KEY_DIM if n == 0 else 1.0


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
			# A waystone's id, and whether it is found (a click travels).
			"waystone": str(info.get("waystone", "")),
			"lit": bool(info.get("lit", false)),
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
		"teleport", "waystone":
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
