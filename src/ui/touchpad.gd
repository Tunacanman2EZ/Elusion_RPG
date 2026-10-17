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
#
# DRAWN IN THE GAME'S OWN ART (0.54.0). The owner, of the first pad's flat
# circles: "i do not like the circles". The buttons are the hotbar's own
# socket (art/images/hotbarslot.png, nine-sliced as the theme slices it), each
# with a pixel icon drawn here (ICONS: a sword, a hand, a boot, a heart); the
# stick is a pixel ring in the socket's gold with a gold knob. Every one is
# drawn at whole screen pixels to an art pixel (art_pixel()), so the edges
# stay as crisp as the hotbar's.
extends Control

# In CSS pixels: what a thumb gets, whatever the screen.
const STICK_RADIUS := 62.0
const KNOB_RADIUS := 26.0
# The square sockets: Attack, and the small ones beside and above it.
const ATTACK_SIDE := 92.0
const SMALL_SIDE := 60.0
const EDGE := 18.0
const GAP := 10.0
# Room under a small socket for its word.
const CAPTION := 15.0
const LABEL_SIZE := 12.0
# Never smaller than the game's own units, and on the smallest phone no bigger
# than this - past it the pad would cover the game.
const MOST_SCALE := 2.4
# The stick takes the left share of the screen, from this far down.
const STICK_ZONE_WIDTH := 0.42
const STICK_ZONE_TOP := 0.2
# A button answers a touch a little outside its socket.
const REACH := 1.1

# How many art pixels across each part is drawn: the socket's 24 (the hotbar
# slot's visible frame) for a small one, more for Attack, so all of them share
# one pixel size.
const SMALL_ART := 22
const ATTACK_ART := 34
const STICK_ART := 44
const KNOB_ART := 18

const SOCKET := preload("res://art/images/hotbarslot.png")
# The slot's frame is 3 pixels inside 4 of clear rim: nine-sliced at 7, as
# rpg_ui_theme.tres slices it, and drawn 4 past the box so the frame is the box.
const SOCKET_SLICE := 7
const SOCKET_RIM := 4

# The theme's own tints for a socket button (ButtonSocket): pressed is its
# pressed, lit is its hover.
const TINT_IDLE := Color(1.0, 1.0, 1.0, 0.86)
const TINT_PRESSED := Color(0.75, 0.7, 0.62, 1.0)
const TINT_LIT := Color(1.35, 1.25, 1.05, 1.0)
const LIT_GLOW := Color(0.95, 0.62, 0.16, 0.42)
const WORDS := Color(0.99, 0.93, 0.74, 1.0)
const WORDS_LIT := Color(1.0, 0.82, 0.3, 1.0)
const WORDS_OUTLINE := Color(0.1, 0.07, 0.07, 0.95)

# The socket's own colours, for the stick drawn to match it.
const INK := Color(37 / 255.0, 28 / 255.0, 35 / 255.0)
const CREAM := Color(253 / 255.0, 228 / 255.0, 143 / 255.0)
const GOLD := Color(244 / 255.0, 193 / 255.0, 21 / 255.0)
const GOLD_DARK := Color(176 / 255.0, 120 / 255.0, 20 / 255.0)
const SHINE := Color(255 / 255.0, 254 / 255.0, 253 / 255.0)
const HOLLOW := Color(27 / 255.0, 22 / 255.0, 18 / 255.0, 150 / 255.0)

# THE ICONS, a character a pixel ("." is clear). Drawn for this pad; nothing
# here is from the purchased pack.
const PALETTE := {
	"o": Color(37 / 255.0, 28 / 255.0, 35 / 255.0), "w": Color(255 / 255.0, 254 / 255.0, 253 / 255.0), "c": Color(253 / 255.0, 228 / 255.0, 143 / 255.0),
	"g": Color(244 / 255.0, 193 / 255.0, 21 / 255.0), "G": Color(176 / 255.0, 120 / 255.0, 20 / 255.0), "s": Color(214 / 255.0, 222 / 255.0, 232 / 255.0),
	"S": Color(128 / 255.0, 140 / 255.0, 160 / 255.0), "b": Color(122 / 255.0, 74 / 255.0, 42 / 255.0), "B": Color(84 / 255.0, 48 / 255.0, 28 / 255.0),
	"r": Color(226 / 255.0, 72 / 255.0, 72 / 255.0), "R": Color(150 / 255.0, 36 / 255.0, 48 / 255.0), "p": Color(255 / 255.0, 160 / 255.0, 160 / 255.0),
	"k": Color(200 / 255.0, 150 / 255.0, 110 / 255.0), "K": Color(150 / 255.0, 100 / 255.0, 70 / 255.0),
}
const ICONS := {
	"sword": [
		"........................o.",
		".......................owo",
		"......................owso",
		".....................owsSo",
		"....................owsSo.",
		"...................owsSo..",
		"..................owsSo...",
		".................owsSo....",
		"................owsSo.....",
		"...............owsSo......",
		".....oo.......owsSo.......",
		"....oGgo.....owsSo........",
		".....oggo...owsSo.........",
		"......oggo.owsSo..........",
		".......oggowsSo...........",
		"........ogGsSo............",
		"........oogGo.............",
		".......oboogGo............",
		"......obBo.ogGo...........",
		".....obBo...oGGo..........",
		"...oobBo.....oo...........",
		"..ocgBo...................",
		"..ogGo....................",
		"...oo.....................",
	],
	"hand": [
		".....oo.......",
		"....okko.oo...",
		"..oookkookko..",
		".okkokkookko..",
		".okkokkokkko..",
		".okkokkokkooo.",
		".okkokkokkokko",
		".okkkkkkkkkkko",
		".okkkkkkkkkko.",
		".okkkkkkkkkko.",
		"..okkkkkkkko..",
		"..okkkkkkkko..",
		"...okkkkkKo...",
		"...oKKKKKKo...",
		"....oooooo....",
	],
	"boot": [
		"................",
		".....oooooo.....",
		".....occcco.....",
		".....obbbbo.....",
		".cc..obbbbo.....",
		".....obbbbo.....",
		"cccc.obbbbo.....",
		".....obbbbboo...",
		".cc..obbbbbbbo..",
		".....obbbbbbbbo.",
		"....obbbbbbbbbo.",
		"....oBBBBBBBBBo.",
		"....ooooooooooo.",
		"................",
	],
	"heart": [
		"..............",
		"..ooo...ooo...",
		".orrro.orrro..",
		"orpprrorrrrro.",
		"orpwrrrrrrrro.",
		"orprrrwwrrrro.",
		"orrrrrwwrrrRo.",
		".orrwwwwwwrRo.",
		".orrwwwwwwRo..",
		"..orrrwwrRo...",
		"...orrwwRo....",
		"....orrRo.....",
		".....oRo......",
		"......o.......",
	],
}

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
	attack = _button("attack", "sword", "")
	use = _button("use", "hand", "Use")
	run = _button("run", "boot", "Run")
	skill = _button("skill", "heart", "")
	attack.went_down.connect(TouchControls.press_attack)
	attack.went_up.connect(TouchControls.release_attack)
	attack.dragged.connect(func(drag: Vector2): TouchControls.attack_drag = drag)
	use.went_down.connect(TouchControls.press_use)
	use.went_up.connect(TouchControls.release_use)
	run.went_down.connect(TouchControls.toggle_sprint)
	skill.went_down.connect(TouchControls.press_skill)
	skill.went_up.connect(TouchControls.release_skill)
	skill.dragged.connect(func(drag: Vector2): TouchControls.skill_drag = drag)


func _button(id: String, icon: String, words: String) -> PadButton:
	var button := PadButton.new()
	button.name = id
	button.icon = icon
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
	Each button is its socket's box; a small one has its word under it.

	SQUARES IN A BLOCK, not round buttons on an arc: Attack bottom right over
	the hotbar, Use to its left, Run over Use and the skill over Attack - each
	small one's word in the gap under it."""
	var edge: float = EDGE * f
	var gap: float = GAP * f
	var words: float = CAPTION * f
	var big: float = ATTACK_SIDE * f
	var small: float = SMALL_SIDE * f
	var stick_r: float = STICK_RADIUS * f
	var floor_y: float = hotbar_top - gap
	var attack_box := Rect2(view.x - edge - big, floor_y - big, big, big)
	var use_box := Rect2(attack_box.position.x - gap - small, floor_y - words - small, small, small)
	var run_box := Rect2(use_box.position.x, use_box.position.y - gap - words - small, small, small)
	var zone_top: float = view.y * STICK_ZONE_TOP
	var zone := Rect2(0.0, zone_top, view.x * STICK_ZONE_WIDTH, maxf(nav_top - zone_top, stick_r * 2.0))
	var out := {
		"zone": zone,
		"stick_rest": Vector2(edge + stick_r + 10.0 * f, nav_top - edge - stick_r),
		"stick_radius": stick_r,
		"knob_radius": KNOB_RADIUS * f,
		"attack": attack_box,
		"use": use_box,
		"run": run_box,
		"words": words,
	}
	if has_skill:
		out["skill"] = Rect2(attack_box.end.x - small, attack_box.position.y - gap - words - small, small, small)
	return out


static func caption_box(box: Rect2, words: float) -> Rect2:
	"""Where a small socket's word goes: the strip under it, as wide as it."""
	return Rect2(box.position.x, box.end.y, box.size.x, words)


static func art_pixel(side: float, art: int, screen_per_unit: float) -> float:
	"""The game units to one art pixel, for a part `side` units across drawn
	`art` pixels across, held to WHOLE SCREEN PIXELS - a pixel art edge that
	falls between two screen pixels draws one wide and the next narrow."""
	var want: float = side / float(maxi(art, 1))
	if screen_per_unit <= 0.0:
		return want
	return maxf(1.0, round(want * screen_per_unit)) / screen_per_unit


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
	# Screen pixels to a game unit, for whole-pixel art.
	var per_unit: float = minf(float(window.size.x) / view.x, float(window.size.y) / view.y) if view.x > 0.0 and view.y > 0.0 else 1.0
	var at: Dictionary = layout(view, scale_now, float(_laid_for[2]), float(_laid_for[3]), _skill_name != "")
	var px: float = art_pixel((at["attack"] as Rect2).size.x, ATTACK_ART, per_unit)
	# ONE PIXEL SIZE FOR THE WHOLE PAD, Attack's: the stick and the sockets
	# read as one set.
	stick.place(at["zone"], at["stick_rest"] - (at["zone"] as Rect2).position, at["stick_radius"], at["knob_radius"], px)
	for id in ["attack", "use", "run", "skill"]:
		var button: PadButton = get(id)
		button.visible = at.has(id)
		if at.has(id):
			button.place(at[id], ATTACK_ART if id == "attack" else SMALL_ART, px, LABEL_SIZE * scale_now, float(at["words"]))


# =============================================================================
# THE ART
# =============================================================================
# An inner class, so the parts below can ask for it: an inner class reaches
# the script's constants but not its functions.

class Art:
	# Built once, the first time each is asked for.
	static var _icon_cache: Dictionary = {}
	static var _ring_cache: Dictionary = {}
	static var _socket_box: StyleBoxTexture = null


	static func socket_box() -> StyleBoxTexture:
		"""The hotbar slot, nine-sliced as the theme slices it."""
		if _socket_box == null:
			_socket_box = StyleBoxTexture.new()
			_socket_box.texture = SOCKET
			_socket_box.texture_margin_left = SOCKET_SLICE
			_socket_box.texture_margin_top = SOCKET_SLICE
			_socket_box.texture_margin_right = SOCKET_SLICE
			_socket_box.texture_margin_bottom = SOCKET_SLICE
		return _socket_box


	static func icon_texture(name: String) -> Texture2D:
		"""ICONS[name] as a texture, one texel an art pixel."""
		if _icon_cache.has(name):
			return _icon_cache[name]
		var rows: Array = ICONS.get(name, [])
		var w: int = 0
		for row in rows:
			w = maxi(w, String(row).length())
		var image := Image.create(maxi(w, 1), maxi(rows.size(), 1), false, Image.FORMAT_RGBA8)
		for y in rows.size():
			var row: String = rows[y]
			for x in row.length():
				var key: String = row[x]
				if PALETTE.has(key):
					image.set_pixel(x, y, PALETTE[key])
		var texture := ImageTexture.create_from_image(image)
		_icon_cache[name] = texture
		return texture


	static func ring_texture(art: int) -> Texture2D:
		"""The stick's ring, `art` pixels across: the socket's ink outline, its
		cream lit from the top left and gold below, a dark hollow the world shows
		through, and an arrow at each of the four ways."""
		var key: String = "ring%d" % art
		if _ring_cache.has(key):
			return _ring_cache[key]
		var image := Image.create(art, art, false, Image.FORMAT_RGBA8)
		var r: float = art / 2.0
		for y in art:
			for x in art:
				var dx: float = x + 0.5 - r
				var dy: float = y + 0.5 - r
				var d: float = sqrt(dx * dx + dy * dy)
				if d > r:
					continue
				if d > r - 1.0 or (d > r - 4.0 and d <= r - 3.0):
					image.set_pixel(x, y, INK)
				elif d > r - 3.0:
					image.set_pixel(x, y, CREAM if dx + dy < 0.0 else GOLD)
				else:
					image.set_pixel(x, y, HOLLOW)
		var mid: int = int(art / 2.0)
		var out: int = int(r) - 7
		for i in 3:
			for j in range(-i, i + 1):
				image.set_pixel(mid + j, mid - out + i, CREAM)
				image.set_pixel(mid + j, mid + out - 1 - i, CREAM)
				image.set_pixel(mid - out + i, mid + j, CREAM)
				image.set_pixel(mid + out - 1 - i, mid + j, CREAM)
		var texture := ImageTexture.create_from_image(image)
		_ring_cache[key] = texture
		return texture


	static func knob_texture(art: int) -> Texture2D:
		"""The stick's knob: a gold orb, cream where the light catches it."""
		var key: String = "knob%d" % art
		if _ring_cache.has(key):
			return _ring_cache[key]
		var image := Image.create(art, art, false, Image.FORMAT_RGBA8)
		var r: float = art / 2.0
		for y in art:
			for x in art:
				var dx: float = x + 0.5 - r
				var dy: float = y + 0.5 - r
				var d: float = sqrt(dx * dx + dy * dy)
				if d > r:
					continue
				var t: float = (dx + dy) / (2.0 * r)
				var colour: Color = INK if d > r - 1.0 else (CREAM if t < -0.25 else (GOLD if t < 0.3 else GOLD_DARK))
				image.set_pixel(x, y, colour)
		var shine := Vector2i(int(r * 0.6), int(r * 0.5))
		for spot in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)]:
			image.set_pixelv(shine + spot, SHINE)
		var texture := ImageTexture.create_from_image(image)
		_ring_cache[key] = texture
		return texture


# =============================================================================
# THE PARTS
# =============================================================================

class PadButton extends Control:
	"""A hotbar socket for a thumb, with its icon and, for a small one, its
	word under it. It answers touches by finger - two thumbs on two buttons
	are two presses - and the first finger's copied mouse clicks, which it
	keeps from the world."""
	signal went_down
	signal went_up
	signal dragged(share: Vector2)

	var icon: String = "":
		set(value):
			icon = value
			queue_redraw()
	var words: String = "":
		set(value):
			words = value
			queue_redraw()
	var lit: bool = false:
		set(value):
			if value != lit:
				lit = value
				queue_redraw()
	# The socket in game units, inside this control (which reaches past it).
	var box: Rect2 = Rect2(0, 0, 60, 60)
	var art: int = 22
	var pixel: float = 2.0
	var label_size: float = 12.0
	var caption_height: float = 15.0
	var finger: int = -1
	var _from: Vector2 = Vector2.ZERO

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE

	func place(socket: Rect2, art_pixels: int, art_pixel_size: float, words_size: float, words_height: float) -> void:
		art = art_pixels
		pixel = art_pixel_size
		label_size = words_size
		caption_height = words_height
		var reach: float = socket.size.x * (REACH - 1.0) / 2.0
		position = (socket.position - Vector2(reach, reach)).round()
		size = (socket.size + Vector2(reach, reach) * 2.0).round()
		var drawn: float = pixel * art
		box = Rect2(((size - Vector2(drawn, drawn)) / 2.0).round(), Vector2(drawn, drawn))
		queue_redraw()

	func radius() -> float:
		return box.size.x / 2.0

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
				dragged.emit(((drag.position - _from) / (radius() * 1.2)).limit_length(1.0))
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
		var down: bool = finger >= 0
		# IN ART PIXELS from here: one unit is one pixel of the socket.
		draw_set_transform(box.position, 0.0, Vector2(pixel, pixel))
		var socket: StyleBoxTexture = Art.socket_box()
		socket.modulate_color = TINT_PRESSED if down else (TINT_LIT if lit else TINT_IDLE)
		draw_style_box(socket, Rect2(-SOCKET_RIM, -SOCKET_RIM, art + SOCKET_RIM * 2, art + SOCKET_RIM * 2))
		if lit:
			draw_rect(Rect2(3, 3, art - 6, art - 6), LIT_GLOW)
		var picture: Texture2D = Art.icon_texture(icon)
		var at: Vector2 = ((Vector2(art, art) - picture.get_size()) / 2.0).floor()
		if down:
			at.y += 1.0
		draw_texture(picture, at, Color(1, 1, 1, 1.0 if down or lit else 0.95))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if words != "":
			var font: Font = get_theme_default_font()
			var px: int = int(round(label_size))
			var strip := Rect2(box.position.x, box.end.y, box.size.x, caption_height)
			var base_y: float = strip.position.y + (strip.size.y - font.get_height(px)) / 2.0 + font.get_ascent(px) + pixel
			var colour: Color = WORDS_LIT if lit else WORDS
			draw_string_outline(font, Vector2(strip.position.x, base_y), words, HORIZONTAL_ALIGNMENT_CENTER,
				strip.size.x, px, maxi(2, int(round(px / 4.0))), WORDS_OUTLINE)
			draw_string(font, Vector2(strip.position.x, base_y), words, HORIZONTAL_ALIGNMENT_CENTER, strip.size.x, px, colour)


class Stick extends Control:
	"""The move stick: wherever the thumb lands in its zone, following the
	thumb past its rim, at rest in the corner when nothing holds it. A pixel
	ring in the socket's gold, with a gold knob."""
	var radius: float = 62.0
	var knob_radius: float = 26.0
	var pixel: float = 2.0
	var rest: Vector2 = Vector2.ZERO
	var base: Vector2 = Vector2.ZERO
	var knob: Vector2 = Vector2.ZERO
	var finger: int = -1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE

	func place(zone: Rect2, resting: Vector2, r: float, knob_r: float, art_pixel_size: float = 0.0) -> void:
		position = zone.position
		size = zone.size
		radius = r
		knob_radius = knob_r
		pixel = art_pixel_size if art_pixel_size > 0.0 else r * 2.0 / STICK_ART
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
		var fade := Color(1, 1, 1, 0.92 if held else 0.5)
		var ring: Texture2D = Art.ring_texture(STICK_ART)
		var ring_side: float = pixel * STICK_ART
		draw_texture_rect(ring, Rect2((base - Vector2(ring_side, ring_side) / 2.0).round(), Vector2(ring_side, ring_side)), false, fade)
		var gem: Texture2D = Art.knob_texture(KNOB_ART)
		var gem_side: float = pixel * KNOB_ART
		var at: Vector2 = base + knob.limit_length(radius)
		draw_texture_rect(gem, Rect2((at - Vector2(gem_side, gem_side) / 2.0).round(), Vector2(gem_side, gem_side)), false, fade)
