# touchpad.gd - the thumbs' half of a touch screen (0.53.0), drawn on the HUD.
#
# TouchControls (touchcontrols.gd) puts one on every HUD as its first child, so
# every bar, button and window on the HUD is over it and takes a touch first.
# It is shown while TouchControls is on - from the first finger on the screen
# until a key - and holds:
#
#   the stick    anywhere in the left part of the screen: it comes to where the
#                thumb lands and follows it, and is the move keys, eight ways
#   Attack       bottom right, above the hotbar: a press is an attack; held, it
#                keeps attacking; dragged, it aims (TouchControls, THE AIM)
#   Use          the interact key: the shop, the bank, the fire, the fishing
#                spot, a loot bag, a lever
#   Run          on for this run: sprints until the thumb leaves the stick
#   Aura         the healer's: a tap drops it at the healer's feet, a drag
#                where it is dragged to; only for a class that has one
#                (player.gd, touch_skill_name())
#
# THUMB-SIZED ON ANY SCREEN. The game is drawn at 1280x720 and scaled to the
# screen, so a button 46 units wide is 46 CSS pixels on a laptop and 25 on a
# phone held sideways. The pad is sized in CSS pixels instead (thumb_scale()):
# the sizes below are what a thumb gets on every screen.
extends Control

# In CSS pixels: what a thumb gets, whatever the screen.
const STICK_RADIUS := 62.0
const KNOB_RADIUS := 26.0
const ATTACK_RADIUS := 46.0
const SMALL_RADIUS := 31.0
const EDGE := 18.0
const GAP := 12.0
const LABEL_SIZE := 13.0
# Never smaller than the game's own units, and on the smallest phone no bigger
# than this - past it the pad would cover the game.
const MOST_SCALE := 2.4
# Where the small buttons sit round Attack: degrees, 0 to the right, 90 up.
const USE_ANGLE := 180.0
const RUN_ANGLE := 128.0
const SKILL_ANGLE := 80.0
# The stick takes the left share of the screen, from this far down.
const STICK_ZONE_WIDTH := 0.42
const STICK_ZONE_TOP := 0.2
# A button answers a touch a little outside its circle.
const REACH := 1.15

const FILL := Color(0.06, 0.05, 0.04, 0.42)
const FILL_DOWN := Color(0.85, 0.7, 0.4, 0.38)
const FILL_LIT := Color(0.88, 0.58, 0.22, 0.5)
const RIM := Color(0.85, 0.72, 0.42, 0.78)
const RIM_RESTING := Color(0.85, 0.72, 0.42, 0.32)
const WORDS := Color(0.95, 0.9, 0.8, 0.95)

var stick: Stick = null
var attack: PadButton = null
var use: PadButton = null
var run: PadButton = null
var skill: PadButton = null

var scale_now: float = 1.0
var _skill_name: String = ""
var _look_left: float = 0.0
var _laid_for: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	stick = Stick.new()
	stick.name = "stick"
	add_child(stick)
	attack = _button("attack", "Attack")
	use = _button("use", "Use")
	run = _button("run", "Run")
	skill = _button("skill", "")
	attack.went_down.connect(TouchControls.press_attack)
	attack.went_up.connect(TouchControls.release_attack)
	attack.dragged.connect(func(drag: Vector2): TouchControls.attack_drag = drag)
	use.went_down.connect(TouchControls.press_use)
	use.went_up.connect(TouchControls.release_use)
	run.went_down.connect(TouchControls.toggle_sprint)
	skill.went_down.connect(TouchControls.press_skill)
	skill.went_up.connect(TouchControls.release_skill)
	skill.dragged.connect(func(drag: Vector2): TouchControls.skill_drag = drag)


func _button(id: String, words: String) -> PadButton:
	var button := PadButton.new()
	button.name = id
	button.words = words
	add_child(button)
	return button


func _ready() -> void:
	visible = TouchControls.active
	get_viewport().size_changed.connect(lay_out)
	lay_out()


func _exit_tree() -> void:
	# The HUD goes with its area: every thumb is up as far as the game knows.
	TouchControls.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		for part in [stick, attack, use, run, skill]:
			if part != null:
				part.call("let_go")


func _process(delta: float) -> void:
	visible = TouchControls.active
	if not visible:
		return
	run.lit = TouchControls.sprint_on
	_look_left -= delta
	if _look_left <= 0.0:
		_look_left = 0.5
		var body: Node = TouchControls.player()
		var named: String = str(body.call("touch_skill_name")) if body != null and body.has_method("touch_skill_name") else ""
		if named != _skill_name:
			_skill_name = named
			skill.words = named
			lay_out()
		elif _laid_for != _what_lays_out():
			lay_out()


# =============================================================================
# SIZE AND PLACE
# =============================================================================

static func thumb_scale(window_pixels: Vector2, drawn_at: Vector2, pixel_ratio: float) -> float:
	"""Game units to a CSS pixel: a window of `window_pixels` real pixels
	(`pixel_ratio` to a CSS pixel) showing the game's `drawn_at` units. One on
	a laptop, near two on a phone held sideways, never past MOST_SCALE."""
	if drawn_at.x <= 0.0 or drawn_at.y <= 0.0 or window_pixels.x <= 0.0 or window_pixels.y <= 0.0:
		return 1.0
	var stretch: float = minf(window_pixels.x / drawn_at.x, window_pixels.y / drawn_at.y)
	return clampf(maxf(pixel_ratio, 1.0) / stretch, 1.0, MOST_SCALE)


static func layout(view: Vector2, f: float, hotbar_top: float, nav_top: float, has_skill: bool) -> Dictionary:
	"""Where everything goes on a `view`-sized HUD at `f` units to a CSS pixel,
	with the hotbar's top at `hotbar_top` and the menu bar's at `nav_top`.
	Circles are [centre, radius]."""
	var edge: float = EDGE * f
	var big: float = ATTACK_RADIUS * f
	var small: float = SMALL_RADIUS * f
	var stick_r: float = STICK_RADIUS * f
	var attack_at := Vector2(view.x - edge - big, hotbar_top - edge * 0.6 - big)
	var ring: float = big + small + GAP * f
	var around := func(degrees: float) -> Vector2:
		var a: float = deg_to_rad(degrees)
		return attack_at + Vector2(cos(a), -sin(a)) * ring
	var zone_top: float = view.y * STICK_ZONE_TOP
	var zone := Rect2(0.0, zone_top, view.x * STICK_ZONE_WIDTH, maxf(nav_top - zone_top, stick_r * 2.0))
	var out := {
		"zone": zone,
		"stick_rest": Vector2(edge + stick_r + 10.0 * f, nav_top - edge - stick_r),
		"stick_radius": stick_r,
		"knob_radius": KNOB_RADIUS * f,
		"attack": [attack_at, big],
		"use": [around.call(USE_ANGLE), small],
		"run": [around.call(RUN_ANGLE), small],
	}
	if has_skill:
		out["skill"] = [around.call(SKILL_ANGLE), small]
	return out


func _what_lays_out() -> Array:
	var hud: Node = get_parent()
	var hotbar: Control = hud.get_node_or_null(^"hotbar") as Control if hud != null else null
	var nav: Control = hud.get_node_or_null(^"navframe") as Control if hud != null else null
	var view: Vector2 = get_viewport_rect().size
	var window: Window = get_window()
	return [view,
		window.size if window != null else Vector2i.ZERO,
		hotbar.get_global_rect().position.y if hotbar != null and hotbar.visible else view.y - 163.0,
		nav.get_global_rect().position.y if nav != null and nav.visible else view.y - 48.0]


func lay_out() -> void:
	if not is_inside_tree():
		return
	_laid_for = _what_lays_out()
	var view: Vector2 = _laid_for[0]
	var window: Window = get_window()
	scale_now = thumb_scale(Vector2(window.size), Vector2(window.content_scale_size) if window.content_scale_size != Vector2i.ZERO else view,
		DisplayServer.screen_get_scale())
	var at: Dictionary = layout(view, scale_now, float(_laid_for[2]), float(_laid_for[3]), _skill_name != "")
	stick.place(at["zone"], at["stick_rest"] - (at["zone"] as Rect2).position, at["stick_radius"], at["knob_radius"])
	for id in ["attack", "use", "run", "skill"]:
		var button: PadButton = get(id)
		button.visible = at.has(id)
		if at.has(id):
			button.place(at[id][0], at[id][1], LABEL_SIZE * scale_now)


# =============================================================================
# THE PARTS
# =============================================================================

class PadButton extends Control:
	"""A round button for a thumb, answering touches by finger - two thumbs on
	two buttons are two presses - and the first finger's copied mouse clicks,
	which it keeps from the world."""
	signal went_down
	signal went_up
	signal dragged(share: Vector2)

	var words: String = "":
		set(value):
			words = value
			queue_redraw()
	var radius: float = 30.0
	var label_size: float = 13.0
	var lit: bool = false:
		set(value):
			if value != lit:
				lit = value
				queue_redraw()
	var finger: int = -1
	var _from: Vector2 = Vector2.ZERO

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE

	func place(at: Vector2, r: float, words_size: float) -> void:
		radius = r
		label_size = words_size
		var half: float = r * REACH
		position = at - Vector2(half, half)
		size = Vector2(half, half) * 2.0
		queue_redraw()

	func centre() -> Vector2:
		return size / 2.0

	func _has_point(point: Vector2) -> bool:
		return point.distance_to(centre()) <= radius * REACH

	func _gui_input(event: InputEvent) -> void:
		var touch := event as InputEventScreenTouch
		if touch != null:
			if touch.pressed and finger < 0:
				finger = touch.index
				_from = touch.position
				went_down.emit()
				queue_redraw()
			elif not touch.pressed and touch.index == finger:
				let_go()
			accept_event()
			return
		var drag := event as InputEventScreenDrag
		if drag != null:
			if drag.index == finger:
				dragged.emit(((drag.position - _from) / (radius * 1.2)).limit_length(1.0))
			accept_event()
			return
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			accept_event()

	func let_go() -> void:
		if finger < 0:
			return
		finger = -1
		went_up.emit()
		queue_redraw()

	func _draw() -> void:
		var c: Vector2 = centre()
		var fill: Color = FILL_DOWN if finger >= 0 else (FILL_LIT if lit else FILL)
		draw_circle(c, radius, fill)
		draw_arc(c, radius, 0.0, TAU, 48, RIM, maxf(2.0, radius * 0.05), true)
		if words != "":
			var font: Font = get_theme_default_font()
			var px: int = int(round(label_size))
			var line: float = font.get_height(px)
			draw_string(font, Vector2(c.x - radius, c.y - line / 2.0 + font.get_ascent(px)), words,
				HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, px, WORDS)


class Stick extends Control:
	"""The move stick: wherever the thumb lands in its zone, following the
	thumb past its rim, at rest in the corner when nothing holds it."""
	var radius: float = 62.0
	var knob_radius: float = 26.0
	var rest: Vector2 = Vector2.ZERO
	var base: Vector2 = Vector2.ZERO
	var knob: Vector2 = Vector2.ZERO
	var finger: int = -1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE

	func place(zone: Rect2, resting: Vector2, r: float, knob_r: float) -> void:
		position = zone.position
		size = zone.size
		radius = r
		knob_radius = knob_r
		rest = resting
		if finger < 0:
			base = rest
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var touch := event as InputEventScreenTouch
		if touch != null:
			if touch.pressed and finger < 0:
				# WHERE THE THUMB LANDS, exactly: a touch alone is no way at
				# all, and only a slide from it walks.
				finger = touch.index
				base = touch.position
				knob = Vector2.ZERO
				_say()
			elif not touch.pressed and touch.index == finger:
				let_go()
			accept_event()
			return
		var drag := event as InputEventScreenDrag
		if drag != null:
			if drag.index == finger:
				var off: Vector2 = drag.position - base
				if off.length() > radius:
					# FOLLOWS THE THUMB: past the rim, the base comes along.
					base += off - off.normalized() * radius
					off = drag.position - base
				knob = off
				_say()
			accept_event()
			return
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			accept_event()

	func let_go() -> void:
		if finger < 0:
			return
		finger = -1
		base = rest
		knob = Vector2.ZERO
		_say()

	func _say() -> void:
		TouchControls.stick = (knob / radius).limit_length(1.0) if radius > 0.0 else Vector2.ZERO
		TouchControls.stick_held = finger >= 0
		queue_redraw()

	func _draw() -> void:
		var held: bool = finger >= 0
		draw_circle(base, radius, FILL if held else Color(FILL, FILL.a * 0.6))
		draw_arc(base, radius, 0.0, TAU, 64, RIM if held else RIM_RESTING, maxf(2.0, radius * 0.035), true)
		draw_circle(base + knob.limit_length(radius), knob_radius, FILL_DOWN if held else Color(RIM_RESTING, 0.22))
