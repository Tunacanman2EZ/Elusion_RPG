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
# THE PANEL MARGINS DECIDE BOTH OF THESE NUMBERS, and they are a measurement
# rather than a preference. Every panel puts its content inside a
# MarginContainer, and a grip is invisible, so a grip THICKER THAN THAT PADDING
# does not look like anything — it just silently takes the clicks meant for
# whatever is underneath it.
#
# MEASURED ACROSS ALL SIXTEEN PANELS, on the outer MarginContainer that each
# header sits inside:
#
#     margin_left / margin_right    8 to 16
#     margin_top / margin_bottom    6 to 15     <- chatpanel and equipmentpanel
#
# So SIX is the ceiling, and it is set by two panels rather than by the typical
# one. _test_panels_are_windows() reads those numbers out of the scenes and
# fails if either constant outgrows the thinnest of them, because this is
# exactly the kind of number that gets nudged up by someone who remembers the
# typical panel and not the thin one.
#
# Five for an edge also keeps it clear of the vertical scrollbar a
# ScrollContainer parks at the right edge, which is the one piece of content
# that would otherwise fight the right grip for the same few pixels.
const GRIP := 5.0

# A corner grip is a square, and bigger than an edge is thick, because hitting
# an exact five-pixel corner with a mouse is a test of patience rather than of
# skill. Six is as big as that can get — see the measurement above.
#
# IT WAS TWELVE, and the overhang landed on the corners of the HEADER. The
# header is the only thing you can drag a panel by, so the result was a window
# that could not be moved, reported as "i cannot grab the header". Eight was the
# first fix and it was still wrong by two pixels on chat and equipment, which is
# how this stopped being a remembered number and became a checked one.
const CORNER := 6.0

# Nothing may be shrunk below this. A panel crushed to nothing is a panel with
# no header, which is a panel you cannot grab — the same way out as dragging one
# off screen, so it gets the same kind of floor.
const MIN_SIZE := Vector2(220.0, 140.0)

# THE SCREEN EDGES ARE WALLS, AND THAT REPLACES AN EARLIER, WORSE RULE.
#
# The first version let a panel hang off an edge and only guaranteed that a
# corner of the header stayed reachable. It is a defensible rule and it was the
# wrong one, for a reason that only shows up in play: a panel half off the
# bottom cannot be resized from the bottom, because the edge you need to grab is
# past the glass. "i cant strech down" is what that feels like.
#
# So: a panel is ALWAYS ENTIRELY ON SCREEN. Push it into an edge and it stops
# like furniture against a wall; push it into a corner when it is bigger than
# the space left and it COMPRESSES rather than going through. Every edge is
# therefore always reachable, and the header is always grabbable - not because
# something guards it, but because there is nowhere for it to go.

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

	# AND WHEN WHAT IT HOLDS GROWS (0.8.0): a bigger text size or a wider font
	# makes the content need more room than the window has, and a full-rect
	# panel cannot be smaller than its contents - it would draw past the grips.
	# Grown to fit, once a frame at most; never shrunk by this.
	for child in window.get_children():
		var part: Control = child as Control
		if part != null and not part.minimum_size_changed.is_connected(_on_content_resized):
			part.minimum_size_changed.connect(_on_content_resized)


var _fit_queued: bool = false


func _on_content_resized() -> void:
	if _fit_queued:
		return
	_fit_queued = true
	_fit_soon.call_deferred()


func _fit_soon() -> void:
	_fit_queued = false
	# A HIDDEN WINDOW IS NOT LAID OUT, so what it says it needs is nonsense -
	# a wrapping label never given a width asks for two thousand pixels - and
	# growing on it would open Options at the full height of the screen. It
	# is measured once it is showing (_on_shown()).
	if not is_instance_valid(window) or not window.is_visible_in_tree():
		return
	refit_scrolls()
	var need: Vector2 = _minimum()
	if window.size.x < need.x or window.size.y < need.y:
		_fit()


func _on_viewport_resized() -> void:
	# THE WINDOW SHRINKING IS THE SAME EVENT AS A PANEL BEING PUSHED INTO A
	# WALL, so it gets the same answer: compress to fit, do not hang off.
	if is_instance_valid(window):
		refit_scrolls()
		_fit()


# =============================================================================
# A WINDOW TALLER THAN THE SCREEN SCROLLS (0.8.0)
# =============================================================================
# Every window was laid out for 1280x720 at one text size. At the largest text
# size two of them - Options and the GM panel - need more than 720, and "the
# screen beats the minimum" (fit_to()) would cut their bottoms off with
# nothing to reach them by. So each wraps its body in a ScrollContainer and
# hands it here: the scroll is exactly as tall as what it holds while the
# window fits on the screen - the window grows, nothing scrolls - and no
# taller than the room left once that is no longer true, when it scrolls.
# Measured on 4.6.1 with every font: nothing else passes 720.

const SCROLL_LEAST := 120.0

var _scrolls: Array[ScrollContainer] = []


func keep_scroll_fitted(scroll: ScrollContainer) -> void:
	if scroll == null or _scrolls.has(scroll):
		return
	_scrolls.append(scroll)
	if not window.visibility_changed.is_connected(_on_shown):
		window.visibility_changed.connect(_on_shown)
	var content: Control = scroll_content(scroll)
	# What the scroll holds is below the window's own children, and a
	# ScrollContainer's minimum does not move with it - so it is watched itself.
	if content != null and not content.minimum_size_changed.is_connected(_on_content_resized):
		content.minimum_size_changed.connect(_on_content_resized)
	# DEFERRED, not now: this runs from a panel's _ready(), which goes on to
	# hide it, and nothing in it has been laid out yet.
	_on_content_resized()


static func scroll_content(scroll: ScrollContainer) -> Control:
	# The first child that is not one of its own scrollbars.
	for child in scroll.get_children():
		if child is Control:
			return child
	return null


static func scroll_height(want: float, rest: float, screen_height: float) -> float:
	"""How tall a scroll may be: all it wants, unless the rest of the window
	plus that is taller than the screen - then what is left, and never less
	than SCROLL_LEAST. Static and pure, so the suite can ask it directly."""
	if not is_finite(screen_height):
		return want
	return minf(want, maxf(screen_height - rest, SCROLL_LEAST))


func _on_shown() -> void:
	# A FRAME AFTER IT APPEARS, when its containers have laid it out.
	if not is_instance_valid(window) or not window.is_visible_in_tree():
		return
	await window.get_tree().process_frame
	_fit_soon()


func refit_scrolls() -> void:
	if _scrolls.is_empty() or not is_instance_valid(window) or not window.is_visible_in_tree():
		return
	var screen: Vector2 = _screen()
	for scroll in _scrolls:
		if not is_instance_valid(scroll):
			continue
		var content: Control = scroll_content(scroll)
		if content == null:
			continue
		# THE REST OF THE WINDOW is what it needs less what the scroll adds,
		# which is plain subtraction because each of these windows stacks its
		# parts in one column. Measured, never by setting the scroll to zero
		# first: that would fire this again, every frame.
		var rest: float = content_minimum(window).y - scroll.get_combined_minimum_size().y
		var height: float = scroll_height(content.get_combined_minimum_size().y, rest, screen.y)
		if absf(scroll.custom_minimum_size.y - height) > 0.5:
			scroll.custom_minimum_size.y = height


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


# `cursor` IS TYPED AS THE ENUM, NOT AS int. Every call site already passes a
# Control.CURSOR_* constant, but an `int` parameter assigned to
# mouse_default_cursor_shape makes the editor warn INT_AS_ENUM_WITHOUT_CAST -
# and that warning never reaches the headless suite, so it only shows up when
# somebody next opens the project. Typing the parameter is the fix that needs
# no cast at the assignment and no `as` at any of the eight callers.
func _add_grip(grip_name: String, edges: int, cursor: Control.CursorShape,
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
			_fit()
			_remember()
		return

	if event is InputEventMouseMotion and _dragging:
		window.global_position = window.get_global_mouse_position() - _drag_offset
		_fit()


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
			_fit()
			_remember()
		return

	if event is InputEventMouseMotion and _resizing != 0:
		_resize_to(window.get_global_mouse_position())


func _resize_to(mouse: Vector2) -> void:
	var fitted: Rect2 = resize_rect(
		_resize_from, mouse - _resize_mouse, _resizing, _minimum(), _screen())
	window.global_position = fitted.position
	window.size = fitted.size


static func resize_rect(start: Rect2, moved: Vector2, edges: int,
		minimum: Vector2, screen: Vector2) -> Rect2:
	"""The rectangle an edge-drag produces: `start`, with `edges` moved by
	`moved`, held above `minimum` and inside `screen`.

	MEASURED FROM THE START OF THE DRAG, not from the previous frame. Applying
	a delta per event accumulates every rounding error and every clamp, so a
	panel dragged to its minimum size and back does not come back to the size it
	started at. This way the arithmetic is the same however many events arrive.

	THE WALL IS APPLIED HERE RATHER THAN LEFT TO fit_to(), and that is the whole
	difference between stopping and jumping. fit_to() is a rule about a finished
	rectangle: it settles the SIZE first, so a bottom edge dragged 300px past the
	floor of the screen becomes a panel too tall, which it shortens — and then it
	has to put that shortened panel somewhere inside the screen, which sends it
	to the TOP. The panel leaves the cursor entirely.

	Clamping the EDGE instead is what a wall does. The bottom edge stops at the
	floor, the top edge stays where it was, and the panel is simply as tall as
	the room left. Pull back and it follows the cursor again from there.

	THE WALL IS APPLIED AFTER THE FLOOR, in the same order fit_to() uses and for
	the same reason: a panel that cannot have its minimum size because the screen
	is smaller than that must still be on screen. It cannot bite in practice - a
	fitted panel's left edge is already at most `screen.x - minimum.x`, so the
	opposite edge can always reach the minimum without leaving the glass - but
	the order says what wins if it ever does."""
	var left: float = start.position.x
	var top: float = start.position.y
	var right: float = left + start.size.x
	var bottom: float = top + start.size.y

	if edges & EDGE_LEFT:
		# DRAGGING A LEFT EDGE MOVES THE PANEL AS WELL AS SIZING IT, and the
		# floor has to stop the left edge rather than the width — otherwise the
		# panel keeps sliding right once it has hit its minimum.
		left = minf(left + moved.x, right - minimum.x)
		left = maxf(left, 0.0)
	if edges & EDGE_RIGHT:
		right = maxf(right + moved.x, left + minimum.x)
		right = minf(right, screen.x)
	if edges & EDGE_TOP:
		top = minf(top + moved.y, bottom - minimum.y)
		top = maxf(top, 0.0)
	if edges & EDGE_BOTTOM:
		bottom = maxf(bottom + moved.y, top + minimum.y)
		bottom = minf(bottom, screen.y)

	return Rect2(left, top, right - left, bottom - top)


func _minimum() -> Vector2:
	"""The smallest this panel may be: the largest of its own declared minimum,
	what its CONTENT needs, and the floor.

	THE CONTENT TERM IS WHAT KEEPS THE GRIPS ON THE BORDER. The grips sit on
	`window`; what the player sees is the panel drawn inside it. A full-rect
	PanelContainer cannot be smaller than its own contents, so shrinking the
	window below what the header, separators and scroll need left the panel
	overflowing the window - drawn past the very edge the grips were on, which
	is the inventory bug arriving through a second door. Asking the children
	means the window cannot be dragged smaller than what it holds, so the drawn
	edge and the grab edge are the same line at every size.

	custom_minimum_size is still believed when a panel sets it: a panel that has
	said something about itself is taken at its word. MIN_SIZE is the floor under
	everything."""
	var declared: Vector2 = window.custom_minimum_size
	var content: Vector2 = content_minimum(window)
	return Vector2(maxf(maxf(declared.x, content.x), MIN_SIZE.x),
		maxf(maxf(declared.y, content.y), MIN_SIZE.y))


static func content_minimum(host: Control) -> Vector2:
	"""The largest combined minimum among `host`'s direct Control children.

	A plain Control's own get_combined_minimum_size() ignores its children -
	only CONTAINERS add theirs up - so the window cannot simply be asked. Static,
	so the suite can put a panel together and ask it in one line."""
	var out: Vector2 = Vector2.ZERO
	if host == null:
		return out
	for child in host.get_children():
		var c: Control = child as Control
		if c != null and c.visible:
			out = out.max(c.get_combined_minimum_size())
	return out


# =============================================================================
# STAYING REACHABLE
# =============================================================================

func _screen() -> Vector2:
	"""How much room there is, or a screen with no walls in it.

	INF RATHER THAN ZERO when there is no viewport. A panel not yet in the tree
	has no screen to be inside, and answering zero would clamp it to nothing —
	a wall at the origin is a worse lie than no wall at all."""
	if window == null or not is_instance_valid(window):
		return Vector2(INF, INF)
	var view: Viewport = window.get_viewport()
	if view == null:
		return Vector2(INF, INF)
	return view.get_visible_rect().size


func _fit() -> void:
	if window == null or not is_instance_valid(window):
		return
	var screen: Vector2 = _screen()
	if not is_finite(screen.x) or not is_finite(screen.y):
		return
	var fitted: Rect2 = fit_to(
		Rect2(window.global_position, window.size), screen, _minimum())
	window.global_position = fitted.position
	window.size = fitted.size


static func fit_to(rect: Rect2, screen: Vector2, minimum: Vector2) -> Rect2:
	"""`rect`, compressed and pushed until it sits entirely inside `screen`.

	STATIC AND PURE, so the suite can ask it directly rather than building a
	viewport to find out what it does. This is the whole rule, and it is worth
	being able to test in one line.

	SIZE IS SETTLED BEFORE POSITION, and the reason is narrower than it first
	looks - which is worth writing down, because the first version of this
	docstring gave a reason that sounded right and was not.

	It claimed the order is what makes an oversized panel COMPRESS rather than
	slide. It is not: an oversized panel compresses either way, because
	`screen - size` is already at or below zero whichever size the bound is
	computed from, so the position clamps to 0 in both orders. Sabotage proved
	it - swapping these two blocks left every check green.

	The order matters when the size GROWS, which is the other half of this
	function: a panel restored below the minimum is grown back up to it. Settle
	the position first and it is bounded by `screen - the small size`, which is a
	LOOSER bound than the panel is about to need. A 4x4 panel saved at x=1900
	stays at 1900 and is then grown to 220 wide, and 200 pixels of it are off the
	right of a 1920 screen - put there by the function whose job is to prevent
	exactly that.

	THE SCREEN BEATS THE MINIMUM. A panel may not be shrunk below `minimum` -
	except when the window itself is smaller than that, in which case the window
	wins. A panel larger than the window has an edge nobody can reach, and
	honouring a minimum size is worth less than being able to move the thing."""
	var size: Vector2 = rect.size

	size.x = minf(size.x, screen.x)
	size.y = minf(size.y, screen.y)
	size.x = maxf(size.x, minf(minimum.x, screen.x))
	size.y = maxf(size.y, minf(minimum.y, screen.y))

	var at: Vector2 = rect.position
	at.x = clampf(at.x, 0.0, maxf(screen.x - size.x, 0.0))
	at.y = clampf(at.y, 0.0, maxf(screen.y - size.y, 0.0))

	return Rect2(at, size)


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
	_fit()


static func forget_all() -> void:
	"""Throw every saved rectangle away. Panels return to where they were
	authored on the next open."""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LAYOUT_PATH))
