# panelwindow.gd — makes a panel behave like a window: drag it, resize it, and
# find it where you left it.
#
# ONE COMPONENT, SIXTEEN PANELS. statsscreen.gd had a drag of its own and no
# other panel had anything, and the instinct — copy that thirty lines into the
# other fifteen — is the exact mistake electricsprite.gd already cost this
# project: "a helper that copies part of a shared function stops inheriting its
# fixes". The three defects in that original are a good argument for one copy,
# because all three would have been copied fifteen times:
#
#   1. NOTHING CLAMPED IT. Drag the stats screen off the bottom of the screen
#      and the header goes with it. The header is the only thing you can grab,
#      so the panel is gone until the scene is rebuilt, and nothing on screen
#      says why.
#   2. THE POSITION WAS A MEMBER VARIABLE. `_last_position` lived and died with
#      the scene, so "where you left it" meant "since this screen was built",
#      not since yesterday.
#   3. IT POLLED THE MOUSE IN _process(). Every frame, forever, whether or not
#      anything was being dragged — and while dragging it saved the position
#      sixty times a second. Mouse MOTION events are the thing that actually
#      carries movement; reading the cursor once a frame is the laggy version
#      of the same question.
#
# All three are fixed here, once.
#
# HOW A PANEL OPTS IN — two lines, and the second is the only one that does
# anything:
#
#     var _window: PanelWindow
#
#     func _ready() -> void:
#         _window = PanelWindow.attach(self, "guild")
#
# `attach` finds the header itself from a SHORT LIST OF KNOWN PATHS and pushes
# an error naming the panel if none of them resolves. That is deliberately not a
# recursive search for a node called "headerpanel": a lenient lookup would hide
# a renamed node, and the panel would simply stop being draggable with nothing
# to read. Same argument as pet.gd::_find_muzzle_marker().

class_name PanelWindow
extends RefCounted


# WHERE THE HEADER LIVES, and there are only three shapes across every panel in
# the project. Written out rather than searched for, so a new panel that does
# not match fails loudly at attach instead of quietly not dragging.
const HEADER_PATHS: Array[String] = [
	"mainpanel/margincontainer/vboxcontainer/headerpanel",
	"frame/margin/rows/headerpanel",
	"mainpanel/margin/rows/headerpanel",
]

# How thick the invisible resize grips are, in pixels.
#
# FIVE, AND THE PANEL MARGINS ARE WHY. Every panel puts its content inside a
# MarginContainer with 8 to 10 pixels of padding, so a five-pixel grip sits on
# the frame's border and touches nothing — including the vertical scrollbar a
# ScrollContainer parks at the right edge, which is the one piece of content
# that would otherwise fight the right grip for the same few pixels.
const GRIP := 5.0

# A corner grip is square and bigger than the edges, because hitting an exact
# five-pixel corner with a mouse is a test of patience rather than of skill.
const CORNER := 12.0

# Nothing may be shrunk below this. A panel crushed to nothing is a panel with
# no header, which is a panel you cannot grab — the same way out as dragging one
# off screen, so it gets the same kind of floor.
const MIN_SIZE := Vector2(220.0, 140.0)

# HOW MUCH OF THE HEADER MUST STAY ON SCREEN. This is the whole answer to the
# lost-panel bug: you can put a panel almost entirely off the edge, but never so
# far that there is nothing left to take hold of.
const KEEP_VISIBLE := Vector2(80.0, 24.0)

# Panel geometry lives in its OWN FILE, and that is not a preference.
# Settings.save_settings() builds a fresh ConfigFile from its own section and
# writes it, so anything else stored in options.cfg is erased the next time any
# setting changes. A second file cannot be caught by that.
const LAYOUT_PATH := "user://panels.cfg"

# Which edges a grip drags. Combined for corners.
const EDGE_LEFT := 1
const EDGE_RIGHT := 2
const EDGE_TOP := 4
const EDGE_BOTTOM := 8


var window: Control = null
var header: Control = null
var key: String = ""

var _dragging: bool = false
var _drag_offset := Vector2.ZERO

var _resizing: int = 0
var _resize_from := Rect2()
var _resize_mouse := Vector2.ZERO


# =============================================================================
# ATTACHING
# =============================================================================

static func attach(panel: Control, layout_key: String,
		explicit_header: Control = null) -> PanelWindow:
	"""Make `panel` draggable and resizable. Returns null if it cannot be.

	KEEP THE RETURNED OBJECT. It is a RefCounted holding the drag state and the
	signal connections; dropping it on the floor frees it and the panel stops
	responding, which looks exactly like the feature not working."""
	if panel == null:
		push_error("PanelWindow: asked to attach to nothing.")
		return null

	var grip_header: Control = explicit_header
	if grip_header == null:
		for path in HEADER_PATHS:
			var found: Node = panel.get_node_or_null(path)
			if found is Control:
				grip_header = found
				break

	if grip_header == null:
		# NAMED, AND LOUD. The alternative is a panel that silently stops being
		# draggable because a node was renamed, which nobody reports as a bug
		# because nobody knew it was a feature.
		push_error("PanelWindow: no header found on '%s'. Tried: %s"
			% [panel.name, ", ".join(HEADER_PATHS)])
		return null

	var made := PanelWindow.new()
	made.window = panel
	made.header = grip_header
	made.key = layout_key
	made._take_control()
	made._build_grips()
	made._wire()
	made._restore()
	return made


func _take_control() -> void:
	"""Convert the panel from anchored-to-centre into a free-floating rectangle.

	EVERY PANEL IS AUTHORED CENTRED — anchors at 0.5 with offsets either side.
	That is right for something the game positions and wrong for something the
	PLAYER positions: with a centre anchor, `position` is measured from a point
	that moves when the window is resized, so a panel parked in the top-left
	slides inward the moment somebody drags the game window wider.

	So the anchors are flattened to the top left. Nothing moves on screen; what
	changes is that from here on a position means what it says.

	MEASURED, NOT ASSUMED: set_anchors_preset(PRESET_TOP_LEFT, false) REWRITES
	THE OFFSETS so the rectangle does not move. On 4.6.1, a control anchored at
	0.5 inside an 800x600 parent with offsets (-200, -150, 200, 150):

	    before   rect (200, 150) 400x300   offsets (-200, -150, 200, 150)
	    after    rect (200, 150) 400x300   offsets ( 200,  150, 600,  450)

	So putting the rectangle back afterwards is redundant, and it was in here
	until a sabotage run proved it: deleting those two lines changed nothing,
	because the engine had already done the work. What they WOULD have hidden
	is the real mistake available here - passing `true`, which keeps the offsets
	and therefore moves every panel to a new place the first time it opens. The
	suite checks the rectangle instead, so that mistake goes red rather than
	being quietly corrected by a line nobody could justify."""
	if window == null:
		return
	window.set_anchors_preset(Control.PRESET_TOP_LEFT, false)


func _wire() -> void:
	if not header.gui_input.is_connected(_on_header_input):
		header.gui_input.connect(_on_header_input)
	# A HEADER YOU CANNOT PRESS IS NOT A HANDLE. A PanelContainer defaults to
	# MOUSE_FILTER_STOP, but a header built from a plain Control or left on
	# IGNORE would swallow nothing and receive nothing.
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.mouse_default_cursor_shape = Control.CURSOR_MOVE

	# RE-CLAMPED WHEN THE GAME WINDOW CHANGES SIZE, because a panel parked
	# against the right edge of a 1920-wide window is off screen entirely in a
	# 1280-wide one. Without this the panel is lost by resizing rather than by
	# dragging, which is the same bug through a different door.
	var view: Viewport = window.get_viewport()
	if view != null and not view.size_changed.is_connected(_on_viewport_resized):
		view.size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	if is_instance_valid(window):
		_clamp()


# =============================================================================
# THE GRIPS
# =============================================================================

func _build_grips() -> void:
	"""Eight invisible Controls around the edge, anchored so they follow.

	ANCHORED RATHER THAN REPOSITIONED. A grip laid out by hand would need
	moving on every resize — by this same file, one frame late, which is how a
	grip ends up half a panel away from the edge it is supposed to be on.

	EDGES FIRST, CORNERS SECOND. A later sibling receives input in front of an
	earlier one, so the corners sit on top of the edges they overlap and a drag
	from the very corner resizes both axes rather than whichever edge happened
	to be added last."""
	_add_grip("gripleft", EDGE_LEFT, Control.CURSOR_HSIZE,
		Vector2(0, 0), Vector2(0, 1), Vector2(0, CORNER), Vector2(GRIP, -CORNER))
	_add_grip("gripright", EDGE_RIGHT, Control.CURSOR_HSIZE,
		Vector2(1, 0), Vector2(1, 1), Vector2(-GRIP, CORNER), Vector2(0, -CORNER))
	_add_grip("griptop", EDGE_TOP, Control.CURSOR_VSIZE,
		Vector2(0, 0), Vector2(1, 0), Vector2(CORNER, 0), Vector2(-CORNER, GRIP))
	_add_grip("gripbottom", EDGE_BOTTOM, Control.CURSOR_VSIZE,
		Vector2(0, 1), Vector2(1, 1), Vector2(CORNER, -GRIP), Vector2(-CORNER, 0))

	# FDIAGSIZE runs top-left to bottom-right; BDIAGSIZE runs the other way.
	_add_grip("griptopleft", EDGE_TOP | EDGE_LEFT, Control.CURSOR_FDIAGSIZE,
		Vector2(0, 0), Vector2(0, 0), Vector2(0, 0), Vector2(CORNER, CORNER))
	_add_grip("griptopright", EDGE_TOP | EDGE_RIGHT, Control.CURSOR_BDIAGSIZE,
		Vector2(1, 0), Vector2(1, 0), Vector2(-CORNER, 0), Vector2(0, CORNER))
	_add_grip("gripbottomleft", EDGE_BOTTOM | EDGE_LEFT, Control.CURSOR_BDIAGSIZE,
		Vector2(0, 1), Vector2(0, 1), Vector2(0, -CORNER), Vector2(CORNER, 0))
	_add_grip("gripbottomright", EDGE_BOTTOM | EDGE_RIGHT, Control.CURSOR_FDIAGSIZE,
		Vector2(1, 1), Vector2(1, 1), Vector2(-CORNER, -CORNER), Vector2(0, 0))


func _add_grip(grip_name: String, edges: int, cursor: int,
		anchor_begin: Vector2, anchor_end: Vector2,
		offset_begin: Vector2, offset_end: Vector2) -> void:
	if window.has_node(NodePath(grip_name)):
		return

	var grip := Control.new()
	grip.name = grip_name
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	grip.mouse_default_cursor_shape = cursor
	# THE GRIPS ARE THE LAST CHILDREN, so they sit in front of the frame and
	# its content. They draw nothing, so "in front" costs a hit test and no
	# pixels.
	window.add_child(grip)
	grip.anchor_left = anchor_begin.x
	grip.anchor_top = anchor_begin.y
	grip.anchor_right = anchor_end.x
	grip.anchor_bottom = anchor_end.y
	grip.offset_left = offset_begin.x
	grip.offset_top = offset_begin.y
	grip.offset_right = offset_end.x
	grip.offset_bottom = offset_end.y
	grip.gui_input.connect(_on_grip_input.bind(edges))


# =============================================================================
# DRAGGING
# =============================================================================

func _on_header_input(event: InputEvent) -> void:
	# MOTION, NOT A POLL. Godot routes mouse events to the control that received
	# the button press until the button comes up, so the drag keeps following
	# the cursor even once it has left the header — which is most of a drag.
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			_dragging = true
			_drag_offset = window.get_global_mouse_position() - window.global_position
		else:
			_dragging = false
			_clamp()
			_remember()
		return

	if event is InputEventMouseMotion and _dragging:
		window.global_position = window.get_global_mouse_position() - _drag_offset
		_clamp()


# =============================================================================
# RESIZING
# =============================================================================

func _on_grip_input(event: InputEvent, edges: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			_resizing = edges
			_resize_from = Rect2(window.global_position, window.size)
			_resize_mouse = window.get_global_mouse_position()
		else:
			_resizing = 0
			_clamp()
			_remember()
		return

	if event is InputEventMouseMotion and _resizing != 0:
		_resize_to(window.get_global_mouse_position())


func _resize_to(mouse: Vector2) -> void:
	"""The new rectangle, from the one we started with and how far the mouse
	has moved.

	MEASURED FROM THE START OF THE DRAG, not from the previous frame. Applying
	a delta per event accumulates every rounding error and every clamp, so a
	panel dragged to its minimum size and back does not come back to the size it
	started at. This way the arithmetic is the same however many events arrive."""
	var moved: Vector2 = mouse - _resize_mouse
	var left: float = _resize_from.position.x
	var top: float = _resize_from.position.y
	var right: float = left + _resize_from.size.x
	var bottom: float = top + _resize_from.size.y

	var floor_size: Vector2 = _minimum()

	if _resizing & EDGE_LEFT:
		# DRAGGING A LEFT EDGE MOVES THE PANEL AS WELL AS SIZING IT, and the
		# floor has to stop the left edge rather than the width — otherwise the
		# panel keeps sliding right once it has hit its minimum.
		left = minf(left + moved.x, right - floor_size.x)
	if _resizing & EDGE_RIGHT:
		right = maxf(right + moved.x, left + floor_size.x)
	if _resizing & EDGE_TOP:
		top = minf(top + moved.y, bottom - floor_size.y)
	if _resizing & EDGE_BOTTOM:
		bottom = maxf(bottom + moved.y, top + floor_size.y)

	window.global_position = Vector2(left, top)
	window.size = Vector2(right - left, bottom - top)
	_clamp()


func _minimum() -> Vector2:
	"""The smallest this panel may be: its own declared minimum, or the floor.

	A panel that has set custom_minimum_size has said something about itself and
	is believed; MIN_SIZE is what everything else gets."""
	var declared: Vector2 = window.custom_minimum_size
	return Vector2(maxf(declared.x, MIN_SIZE.x), maxf(declared.y, MIN_SIZE.y))


# =============================================================================
# STAYING REACHABLE
# =============================================================================

func _clamp() -> void:
	if window == null or not is_instance_valid(window):
		return
	var view: Viewport = window.get_viewport()
	if view == null:
		return
	window.global_position = clamp_to(
		Rect2(window.global_position, window.size),
		view.get_visible_rect().size).position


static func clamp_to(rect: Rect2, screen: Vector2) -> Rect2:
	"""Push `rect` back until enough of its top edge is on screen to grab.

	STATIC AND PURE, so the suite can ask it directly rather than building a
	viewport to find out what it does. This is the whole lost-panel fix and it
	is worth being able to test in one line.

	THE TOP EDGE, NOT THE WHOLE PANEL. Letting a panel hang off the bottom or
	the right is useful — it is how you park something you want half out of the
	way. What must never happen is the HEADER leaving the screen, because the
	header is the only part you can take hold of. So the rule is expressed as a
	bound on the top-left corner:

	    x may run from -(width - KEEP_VISIBLE.x) to screen.x - KEEP_VISIBLE.x
	    y may run from 0 to screen.y - KEEP_VISIBLE.y

	y never goes negative: a panel pushed up loses its header off the top of the
	screen first, and there is nothing below it to grab."""
	var size: Vector2 = rect.size
	var out: Vector2 = rect.position

	var min_x: float = minf(-(size.x - KEEP_VISIBLE.x), 0.0)
	var max_x: float = maxf(screen.x - KEEP_VISIBLE.x, 0.0)
	out.x = clampf(out.x, min_x, max_x)

	var max_y: float = maxf(screen.y - KEEP_VISIBLE.y, 0.0)
	out.y = clampf(out.y, 0.0, max_y)

	return Rect2(out, size)


# =============================================================================
# REMEMBERING
# =============================================================================

func _remember() -> void:
	"""Write this panel's rectangle to disk.

	ON RELEASE, NOT ON MOTION. The original saved on every frame of a drag; this
	one writes when the mouse comes up, which is sixty times less often and is
	the only moment the number is worth keeping."""
	if key == "":
		return
	var cfg := ConfigFile.new()
	# READ THEN WRITE, because this file holds every panel and a fresh
	# ConfigFile written straight out would take the other fifteen with it.
	# That is the exact behaviour that keeps this out of options.cfg.
	cfg.load(LAYOUT_PATH)
	cfg.set_value(key, "x", window.position.x)
	cfg.set_value(key, "y", window.position.y)
	cfg.set_value(key, "w", window.size.x)
	cfg.set_value(key, "h", window.size.y)
	cfg.save(LAYOUT_PATH)


func _restore() -> void:
	if key == "":
		return
	var cfg := ConfigFile.new()
	if cfg.load(LAYOUT_PATH) != OK:
		return
	if not cfg.has_section(key):
		return

	var floor_size: Vector2 = _minimum()
	var wanted := Vector2(
		maxf(float(cfg.get_value(key, "w", window.size.x)), floor_size.x),
		maxf(float(cfg.get_value(key, "h", window.size.y)), floor_size.y))
	var at := Vector2(
		float(cfg.get_value(key, "x", window.position.x)),
		float(cfg.get_value(key, "y", window.position.y)))

	window.size = wanted
	window.position = at
	# CLAMPED ON THE WAY IN AS WELL AS ON THE WAY OUT. The screen may be smaller
	# than it was when this was written — a different monitor, a windowed launch
	# after a fullscreen one — and a position that was reachable then is not
	# necessarily reachable now.
	_clamp()


static func forget_all() -> void:
	"""Throw every saved rectangle away. Panels return to where they were
	authored on the next open."""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LAYOUT_PATH))
