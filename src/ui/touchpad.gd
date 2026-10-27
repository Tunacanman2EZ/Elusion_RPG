# touchpad.gd - the thumbs' half of a touch screen (0.53.0), drawn on the HUD.
#
# TouchControls (touchcontrols.gd) puts one on every HUD as its first child, so
# every bar, button and window on the HUD is over it and takes a touch first.
# It is shown while TouchControls is on - from the first finger on the screen
# until a key - and holds:
#
#   the stick    anywhere in the left part of the screen: it comes to where the
#                thumb lands and follows it, and is the move keys, eight ways;
#                drawn only while a thumb is on it (0.91.0), round (0.91.1)
#   Attack       a thumb anywhere on the middle right (ATTACK_ZONE_LEFT): drawn
#                where it lands, only while down (0.91.2); a press is an attack;
#                held, it keeps attacking; dragged, it aims (TouchControls, THE AIM)
#   Use          the interact key: the shop, the bank, the fire, the fishing
#                spot, a loot bag, a lever
#   Run          no button since 0.91.1: the stick pushed to its edge runs
#                (TouchControls.RUN_EDGE); the button is kept, hidden, for
#                anything still calling toggle_sprint()
#   Aura         the healer's: a tap drops it at the healer's feet, a drag
#                where it is dragged to; only for a class that has one
#                (player.gd, touch_skill_name())
#
# THUMB-SIZED ON ANY SCREEN. The game is drawn at 1280x720 and scaled to the
# screen, so a button 46 units wide is 46 CSS pixels on a laptop and 25 on a
# phone held sideways. The pad is sized in CSS pixels instead (thumb_scale()):
# the sizes below are what a thumb gets on every screen.
#
# ONLY THE GAME'S OWN ART (0.54.0). The owner, of the first pad's flat
# circles: "i do not like the circles" - and of icons drawn for it in code: "we
# need to use my art only there is no shortcuts we can look at potential stuff
# from clockwork". Nothing here is drawn by this script:
#   the sockets   the hotbar's own slot, art/images/hotbarslot.png (Elusion
#                 Studios'), nine-sliced as rpg_ui_theme.tres slices it and
#                 tinted with that theme's own pressed and hover colours
#   the icons     the Clockwork Raven pack's stat icons (art/pack/icons):
#                 Attack's sword, Run's boot (agility), Aura's heart (health),
#                 and Use's chest (the bag's gold)
#   the stick     the same slot, as big as the stick, with the pack's gold
#                 coin (art/pack/currency/goldcoin.png) for the knob
# THE PACK IS PRIVATE, so a clone of the repository has none of it: every pack
# picture is loaded when it is there and nothing breaks when it is not - a
# button shows its word, the knob is a small slot (ICON_PATHS, KNOB_PATH). Not
# preloaded: a preload of a missing file stops the script compiling at all.
#
# WHOLE SCREEN PIXELS. A socket's pixel and an icon's are each drawn a whole
# number of screen pixels wide (art_pixel(), Art.texel_size()), so their edges
# stay as crisp as the hotbar's.
extends Control

# In CSS pixels: what a thumb gets, whatever the screen.
#
# A QUARTER SMALLER (0.91.0). The owner, on a phone: "attack and stuff takes
# up a majority of the screen on mobile". Measured at 844x390, the pad, the
# hotbar and the menu bar covered most of the lower half. Attack is 72 CSS
# pixels now (was 92), about 19 mm on a phone - still past the 9 mm a thumb
# needs - and the small ones 46 (was 60).
#
# SMALLER STILL, AND ONLY WHEN TOUCHED (0.91.1). The owner: "we do not need a
# attack button really we could make it much smaller and only appear when
# player touches screen ... we could also make them more transparent". A tap
# or a hold on the world attacks there already, so Attack is a spare: 52 CSS
# pixels, Use and the Aura 40 (about 11 mm). They fade in at any touch and
# out SHOW_SECONDS after the last, and answer a press while faded out.
const STICK_RADIUS := 50.0
const KNOB_RADIUS := 21.0
# The round sockets: Attack, and the small ones beside and above it.
const ATTACK_SIDE := 52.0
const SMALL_SIDE := 40.0
const EDGE := 14.0
const GAP := 8.0
# Room under a small socket for its word.
const CAPTION := 13.0
const LABEL_SIZE := 11.0
# Never smaller than the game's own units, and on the smallest phone no bigger
# than this - past it the pad would cover the game.
const MOST_SCALE := 2.4
# The stick takes the left share of the screen, from this far down.
const STICK_ZONE_WIDTH := 0.42
const STICK_ZONE_TOP := 0.2
# ATTACK UNDER THE RIGHT THUMB (0.91.2). The owner: "attack button only needs
# to appear when player taps screen should not be visable and anywhere on the
# middle right screen it can appear", and "left side of screen is joystick" (0.91.2).
# From this share of the screen's width to its right edge, from the stick's
# top down to the hotbar: a thumb down there is Attack, drawn where it lands,
# gone when it lifts. A tap on the world outside it still strikes there.
const ATTACK_ZONE_LEFT := 0.5
# A button answers a touch a little outside its socket.
const REACH := 1.1

# How many art pixels across each part is drawn: the socket's 24 (the hotbar
# slot's visible frame) for a small one, more for Attack, so all of them share
# one pixel size.
const SMALL_ART := 26
const ATTACK_ART := 34
# Shown this long after the last touch, faded in and out over FADE_SECONDS.
const SHOW_SECONDS := 3.0
const FADE_SECONDS := 0.25
# How much of a socket's inside its icon fills, at most: a square icon whose
# corners stay inside the round frame (0.91.1) - half its diagonal is no more
# than the frame's inner radius, 0.707 of the inside's width.
const ICON_FILL := 0.7

const SOCKET := preload("res://art/images/hotbarslot.png")
# The slot's frame is 3 pixels inside 4 of clear rim: nine-sliced at 7, as
# rpg_ui_theme.tres slices it, and drawn 4 past the box so the frame is the box.
const SOCKET_SLICE := 7
const SOCKET_RIM := 4
# The frame's width, in the slot's pixels: an icon goes inside it.
const SOCKET_FRAME := 3

# THE PACK'S PICTURES (Clockwork Raven, art/pack/ - see assetlicense.md).
const ICON_PATHS := {
	"attack": "res://art/pack/icons/attackiconcharacterstats.png",
	"use": "res://art/pack/icons/inventorygold.png",
	"run": "res://art/pack/icons/agilityiconcharacterstats.png",
	"skill": "res://art/pack/icons/hpiconcharacterstats.png",
}
const KNOB_PATH := "res://art/pack/currency/goldcoin.png"

# ROUND SOCKETS (0.91.1). The owner: "we can use the same gold ring just bend
# the shape so its round thats not ai art thats customization". The hotbar
# slot is drawn through this shader, which bends it: every point of the circle
# takes its colour from one of the slot's own pixels (texelFetch, no
# blending), found by stretching its ray from the middle onto the square - so
# each square ring of the slot becomes a circle, and the gold frame stays
# SOCKET_FRAME pixels thick all the way round. It is nine-sliced first, as the
# square one was, so the frame is that thick at every size. No pixel here is
# made; each is one of the slot's.
const ROUND_SHADER := """
shader_type canvas_item;
uniform float art = 22.0;
uniform float rim = 4.0;
uniform float slice = 7.0;
varying vec4 tint;
void vertex() {
	tint = COLOR;
}
float sliced(float a, float length, float width) {
	if (a < slice) {
		return a;
	}
	if (a > length - slice) {
		return width - (length - a);
	}
	return slice + (a - slice) * (width - 2.0 * slice) / (length - 2.0 * slice);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float most = max(abs(p.x), abs(p.y));
	if (r > 1.0 || most <= 0.0) {
		COLOR = vec4(0.0);
	} else {
		vec2 square = p * (r / most);
		float length = art + 2.0 * rim;
		vec2 a = (square + 1.0) * 0.5 * length;
		vec2 size = vec2(textureSize(TEXTURE, 0));
		vec2 t = vec2(sliced(a.x, length, size.x), sliced(a.y, length, size.y));
		ivec2 at = clamp(ivec2(floor(t)), ivec2(0), ivec2(size) - 1);
		COLOR = texelFetch(TEXTURE, at, 0) * tint;
	}
}
"""

# The theme's own tints for a socket button (ButtonSocket): pressed is its
# pressed, lit is its hover.
const TINT_IDLE := Color(1.0, 1.0, 1.0, 0.6)
const TINT_PRESSED := Color(0.75, 0.7, 0.62, 1.0)
const TINT_LIT := Color(1.35, 1.25, 1.05, 1.0)
# THE STICK DIMMED (0.91.1): the owner, "dim the joystick also". Its ring and
# coin are this see-through under a thumb; running lights them, still dimmed.
const STICK_RING := Color(1, 1, 1, 0.4)
const STICK_COIN := Color(1, 1, 1, 0.6)
const STICK_RUNNING := Color(1.35, 1.25, 1.05, 0.7)
const WORDS := Color(0.99, 0.93, 0.74, 0.8)
const WORDS_LIT := Color(1.0, 0.82, 0.3, 1.0)
const WORDS_OUTLINE := Color(0.1, 0.07, 0.07, 0.95)

var stick: Stick = null
var attack: PadButton = null
var use: PadButton = null
var run: PadButton = null
var skill: PadButton = null

var scale_now: float = 1.0
var _skill_name: String = ""
var _look_left: float = 0.0
var _laid_for: Array = []
# How long the buttons stay up, and how far faded in they are now (0 to 1).
var show_left: float = 0.0
var shown: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	stick = Stick.new()
	stick.name = "stick"
	add_child(stick)
	attack = _button("attack", "Attack", false)
	use = _button("use", "Use", true)
	run = _button("run", "Run", true)
	skill = _button("skill", "", true)
	attack.went_down.connect(TouchControls.press_attack)
	attack.went_up.connect(TouchControls.release_attack)
	attack.dragged.connect(func(drag: Vector2): TouchControls.attack_drag = drag)
	use.went_down.connect(TouchControls.press_use)
	use.went_up.connect(TouchControls.release_use)
	run.went_down.connect(TouchControls.toggle_sprint)
	skill.went_down.connect(TouchControls.press_skill)
	skill.went_up.connect(TouchControls.release_skill)
	skill.dragged.connect(func(drag: Vector2): TouchControls.skill_drag = drag)


func _button(id: String, words: String, captioned: bool) -> PadButton:
	var button := PadButton.new()
	button.name = id
	button.picture = Art.picture(ICON_PATHS.get(id, ""))
	button.words = words
	button.captioned = captioned
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
	var was_shown: bool = visible
	visible = TouchControls.active
	if not visible:
		return
	# Looked at at once on the frame it appears: the hotbar has just grown
	# for the thumbs (hotbar.gd, 0.55.0), and Attack sits on its top.
	if not was_shown:
		_look_left = 0.0
	_fade(delta)
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


func _input(event: InputEvent) -> void:
	# ANY FINGER ON THE SCREEN brings the buttons up; nothing is taken from it.
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		show_left = SHOW_SECONDS


func _fade(delta: float) -> void:
	"""Up while a finger is down and SHOW_SECONDS after, faded in and out."""
	for part in [stick, attack, use, skill]:
		if part != null and int(part.get("finger")) >= 0:
			show_left = SHOW_SECONDS
	show_left = maxf(0.0, show_left - delta)
	shown = move_toward(shown, 1.0 if show_left > 0.0 else 0.0, delta / FADE_SECONDS)
	# Attack is not faded: it is drawn only under its thumb. Nor is Use
	# (0.91.3): the owner, "do not make the use button invisable" - it is
	# always there, at its see-through rest.
	for button in [skill]:
		if button != null:
			button.modulate.a = shown


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


static func layout(view: Vector2, f: float, hotbar_top: float, nav_top: float, has_skill: bool,
		bars: Rect2 = Rect2()) -> Dictionary:
	"""Where everything goes on a `view`-sized HUD at `f` units to a CSS pixel,
	with the hotbar's top at `hotbar_top` and the menu bar's at `nav_top`.
	Each button is its socket's box; a small one has its word under it.

	IN A BLOCK, not on an arc: Attack bottom right over the hotbar, Use to
	its left and the skill over Attack - each small one's word in the gap
	under it. No Run since 0.91.1: the stick's edge runs.

	USE BESIDE THE HEALTH AND MANA (0.91.1): the owner, "the use button we
	can put right next to hp and mana". Given the bars' box, Use stands just
	left of it, its middle on theirs, its word under it."""
	var edge: float = EDGE * f
	var gap: float = GAP * f
	var words: float = CAPTION * f
	var big: float = ATTACK_SIDE * f
	var small: float = SMALL_SIDE * f
	var stick_r: float = STICK_RADIUS * f
	var floor_y: float = hotbar_top - gap
	var attack_box := Rect2(view.x - edge - big, floor_y - big, big, big)
	var use_box := Rect2(attack_box.position.x - gap - small, floor_y - words - small, small, small)
	if bars.has_area():
		use_box = Rect2(bars.position.x - gap - small, bars.get_center().y - small / 2.0, small, small)
	var zone_top: float = view.y * STICK_ZONE_TOP
	var zone := Rect2(0.0, zone_top, view.x * STICK_ZONE_WIDTH, maxf(nav_top - zone_top, stick_r * 2.0))
	var attack_zone := Rect2(view.x * ATTACK_ZONE_LEFT, zone_top,
		view.x * (1.0 - ATTACK_ZONE_LEFT) - edge, maxf(floor_y - zone_top, big))
	var out := {
		"zone": zone,
		"attack_zone": attack_zone,
		"stick_rest": Vector2(edge + stick_r + 10.0 * f, nav_top - edge - stick_r),
		"stick_radius": stick_r,
		"knob_radius": KNOB_RADIUS * f,
		"attack": attack_box,
		"use": use_box,
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
	# A window with fewer pixels than the game has units (a headless one) has
	# no whole pixel worth holding to.
	if screen_per_unit < 1.0:
		return want
	return maxf(1.0, round(want * screen_per_unit)) / screen_per_unit


func _what_lays_out() -> Array:
	var hud: Node = get_parent()
	var hotbar: Control = hud.get_node_or_null(^"hotbar") as Control if hud != null else null
	var nav: Control = hud.get_node_or_null(^"navframe") as Control if hud != null else null
	var health: Control = hud.get_node_or_null(^"barcontainer/healthbar") as Control if hud != null else null
	var mana: Control = hud.get_node_or_null(^"barcontainer/magicbar") as Control if hud != null else null
	var bars := Rect2()
	if health != null and mana != null and health.is_visible_in_tree():
		bars = health.get_global_rect().merge(mana.get_global_rect())
	var view: Vector2 = get_viewport_rect().size
	var window: Window = get_window()
	return [view,
		window.size if window != null else Vector2i.ZERO,
		hotbar.get_global_rect().position.y if hotbar != null and hotbar.visible else view.y - 163.0,
		nav.get_global_rect().position.y if nav != null and nav.visible else view.y - 48.0,
		bars]


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
	var at: Dictionary = layout(view, scale_now, float(_laid_for[2]), float(_laid_for[3]), _skill_name != "", _laid_for[4])
	var px: float = art_pixel((at["attack"] as Rect2).size.x, ATTACK_ART, per_unit)
	# ONE PIXEL SIZE FOR THE WHOLE PAD, Attack's: the stick and the sockets
	# read as one set.
	stick.place(at["zone"], at["stick_rest"] - (at["zone"] as Rect2).position, at["stick_radius"], at["knob_radius"], px, per_unit)
	for id in ["attack", "use", "run", "skill"]:
		var button: PadButton = get(id)
		button.visible = at.has(id)
		if id == "attack":
			button.place_floating(at["attack_zone"], at[id], ATTACK_ART, px, per_unit)
		elif at.has(id):
			button.place(at[id], SMALL_ART, px, LABEL_SIZE * scale_now, float(at["words"]), per_unit)


# =============================================================================
# THE ART
# =============================================================================
# An inner class, so the parts below can ask for it: an inner class reaches
# the script's constants but not its functions.

class Art:
	static var _socket_box: StyleBoxTexture = null
	static var _pictures: Dictionary = {}

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

	static func picture(path: String) -> Texture2D:
		"""A picture from the pack, or null where a clone has none."""
		if path == "":
			return null
		if not _pictures.has(path):
			_pictures[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
		return _pictures[path]

	static func texel_size(room: float, texels: int, screen_per_unit: float) -> float:
		"""Game units to one of a picture's pixels: as big as fits `room`
		units, held to whole screen pixels."""
		if texels <= 0:
			return 0.0
		# Less than a screen pixel to each of its pixels (a small socket
		# on a small window): drawn to fit, not grown past its room.
		if screen_per_unit < 1.0 or room * screen_per_unit < texels:
			return room / texels
		return floor(room * screen_per_unit / texels) / screen_per_unit

	static var _round: Shader = null

	static func round_shader() -> Shader:
		if _round == null:
			_round = Shader.new()
			_round.code = ROUND_SHADER
		return _round

	static func draw_socket(on: CanvasItem, box: Rect2, pixel: float, tint: Color) -> void:
		"""The slot drawn as `box`, its frame `pixel` units to one of its pixels."""
		var art := Vector2(box.size.x / pixel, box.size.y / pixel)
		on.draw_set_transform(box.position, 0.0, Vector2(pixel, pixel))
		var socket: StyleBoxTexture = socket_box()
		socket.modulate_color = tint
		on.draw_style_box(socket, Rect2(-Vector2(SOCKET_RIM, SOCKET_RIM), art + Vector2(SOCKET_RIM, SOCKET_RIM) * 2.0))
		on.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class RoundSocket extends Control:
	"""The hotbar slot bent round (ROUND_SHADER), drawn behind its button."""
	var tint: Color = TINT_IDLE:
		set(value):
			if value != tint:
				tint = value
				queue_redraw()

	func _init() -> void:
		name = "roundsocket"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		show_behind_parent = true
		var mat := ShaderMaterial.new()
		mat.shader = Art.round_shader()
		material = mat

	func place(box: Rect2, pixel: float) -> void:
		"""As `box`, its frame `pixel` units to one of the slot's pixels."""
		var reach := Vector2(SOCKET_RIM, SOCKET_RIM) * pixel
		position = box.position - reach
		size = box.size + reach * 2.0
		(material as ShaderMaterial).set_shader_parameter(&"art", box.size.x / pixel)
		(material as ShaderMaterial).set_shader_parameter(&"rim", float(SOCKET_RIM))
		(material as ShaderMaterial).set_shader_parameter(&"slice", float(SOCKET_SLICE))
		queue_redraw()

	func _draw() -> void:
		draw_texture_rect(SOCKET, Rect2(Vector2.ZERO, size), false, tint)


class PadButton extends Control:
	"""A hotbar socket for a thumb, with the pack's icon in it and, for a
	small one, its word under it - or, where a clone has no pack, its word in
	it. It answers touches by finger - two thumbs on two buttons are two
	presses - and the first finger's copied mouse clicks, which it keeps from
	the world."""
	signal went_down
	signal went_up
	signal dragged(share: Vector2)

	var picture: Texture2D = null:
		set(value):
			picture = value
			queue_redraw()
	var words: String = "":
		set(value):
			words = value
			queue_redraw()
	# A small socket's word goes under it; Attack's only where it has no icon.
	var captioned: bool = true
	var lit: bool = false:
		set(value):
			if value != lit:
				lit = value
				queue_redraw()
	# The socket in game units, inside this control (which reaches past it).
	var box: Rect2 = Rect2(0, 0, 60, 60)
	var art: int = 22
	var pixel: float = 2.0
	var per_unit: float = 1.0
	var label_size: float = 12.0
	var caption_height: float = 15.0
	var finger: int = -1
	var _from: Vector2 = Vector2.ZERO
	var ring: RoundSocket = null
	# FLOATING: this control is the whole zone, and the socket is drawn where
	# the thumb lands, only while it is down (Attack, 0.91.2).
	var floating: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		ring = RoundSocket.new()
		add_child(ring)

	func place(socket: Rect2, art_pixels: int, art_pixel_size: float, words_size: float, words_height: float,
			screen_per_unit: float = 1.0) -> void:
		art = art_pixels
		pixel = art_pixel_size
		per_unit = screen_per_unit
		label_size = words_size
		caption_height = words_height
		var reach: float = socket.size.x * (REACH - 1.0) / 2.0
		position = (socket.position - Vector2(reach, reach)).round()
		size = (socket.size + Vector2(reach, reach) * 2.0).round()
		var drawn: float = pixel * art
		box = Rect2(((size - Vector2(drawn, drawn)) / 2.0).round(), Vector2(drawn, drawn))
		ring.place(box, pixel)
		queue_redraw()

	func place_floating(zone: Rect2, socket: Rect2, art_pixels: int, art_pixel_size: float,
			screen_per_unit: float = 1.0) -> void:
		"""The whole of `zone` answers; a socket of `socket`'s size is drawn
		under the thumb."""
		floating = true
		art = art_pixels
		pixel = art_pixel_size
		per_unit = screen_per_unit
		position = zone.position.round()
		size = zone.size.round()
		var drawn: float = pixel * art
		if finger < 0:
			box = Rect2(((size - Vector2(drawn, drawn)) / 2.0).round(), Vector2(drawn, drawn))
		ring.place(box, pixel)
		ring.visible = finger >= 0
		queue_redraw()

	func _land(at: Vector2) -> void:
		"""The socket under the thumb, kept inside the zone."""
		var corner: Vector2 = (at - box.size / 2.0).clamp(Vector2.ZERO, (size - box.size).max(Vector2.ZERO))
		box = Rect2(corner.round(), box.size)
		ring.place(box, pixel)
		ring.visible = true

	func radius() -> float:
		return box.size.x / 2.0

	func icon_rect() -> Rect2:
		"""Where the icon is drawn: as big as fits inside the slot's frame, a
		whole number of screen pixels to each of its own."""
		if picture == null:
			return Rect2()
		var room: float = (art - SOCKET_FRAME * 2) * pixel * ICON_FILL
		var texels: int = maxi(picture.get_width(), picture.get_height())
		var side: float = Art.texel_size(room, texels, per_unit) * texels
		var at: Vector2 = box.position + (box.size - Vector2(side, side)) / 2.0
		if finger >= 0:
			at.y += pixel
		# Whole screen pixels only where there are more of them than units.
		if per_unit >= 1.0:
			at = (at * per_unit).round() / per_unit
		return Rect2(at, Vector2(side, side))

	func _gui_input(event: InputEvent) -> void:
		var touch := event as InputEventScreenTouch
		if touch != null:
			if touch.pressed and finger < 0:
				# A NAME UNDER THE THUMB opens that player's menu instead
				# (0.56.0's tap, kept on the side Attack now covers).
				if floating and TouchControls.tap_name_at(get_global_transform_with_canvas() * touch.position):
					accept_event()
					return
				finger = touch.index
				_from = touch.position
				if floating:
					_land(touch.position)
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
		if floating:
			ring.visible = false
		went_up.emit()
		queue_redraw()

	func _draw() -> void:
		var down: bool = finger >= 0
		if floating and not down:
			return
		ring.tint = TINT_PRESSED if down else (TINT_LIT if lit else TINT_IDLE)
		if picture != null:
			draw_texture_rect(picture, icon_rect(), false, Color(1, 1, 1, 1.0 if down or lit else 0.75))
		if words == "":
			return
		var font: Font = get_theme_default_font()
		var px: int = int(round(label_size))
		var colour: Color = WORDS_LIT if lit else WORDS
		# Under a small socket; inside one with no icon (a clone has no pack).
		var strip := Rect2(box.position.x, box.end.y, box.size.x, caption_height)
		if picture == null:
			strip = Rect2(box.position.x, box.position.y + (box.size.y - caption_height) / 2.0, box.size.x, caption_height)
		elif not captioned:
			return
		var base_y: float = strip.position.y + (strip.size.y - font.get_height(px)) / 2.0 + font.get_ascent(px) + (pixel if picture != null else 0.0)
		draw_string_outline(font, Vector2(strip.position.x, base_y), words, HORIZONTAL_ALIGNMENT_CENTER,
			strip.size.x, px, maxi(2, int(round(px / 4.0))), WORDS_OUTLINE)
		draw_string(font, Vector2(strip.position.x, base_y), words, HORIZONTAL_ALIGNMENT_CENTER, strip.size.x, px, colour)


class Stick extends Control:
	"""The move stick: wherever the thumb lands in its zone, following the
	thumb past its rim, and not drawn when nothing holds it. The
	hotbar's slot as big as the stick, with the pack's gold coin for a knob."""
	var radius: float = 62.0
	var knob_radius: float = 26.0
	var pixel: float = 2.0
	var per_unit: float = 1.0
	var rest: Vector2 = Vector2.ZERO
	var base: Vector2 = Vector2.ZERO
	var knob: Vector2 = Vector2.ZERO
	var finger: int = -1
	var coin: Texture2D = null

	# Where and when the thumb came down, for a tap on a name.
	var _landed_at: Vector2 = Vector2.ZERO
	var _landed_msec: int = 0

	var ring: RoundSocket = null

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		coin = Art.picture(KNOB_PATH)
		ring = RoundSocket.new()
		ring.visible = false
		add_child(ring)

	func place(zone: Rect2, resting: Vector2, r: float, knob_r: float, art_pixel_size: float = 0.0,
			screen_per_unit: float = 1.0) -> void:
		position = zone.position
		size = zone.size
		radius = r
		knob_radius = knob_r
		pixel = art_pixel_size if art_pixel_size > 0.0 else 2.0
		per_unit = screen_per_unit
		rest = resting
		if finger < 0:
			base = rest
		_place_base()
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var touch := event as InputEventScreenTouch
		if touch != null:
			if touch.pressed and finger < 0:
				# WHERE THE THUMB LANDS, exactly: a touch alone is no way at
				# all, and only a slide from it walks.
				TouchControls.played_now()
				finger = touch.index
				base = touch.position
				knob = Vector2.ZERO
				_landed_at = touch.position
				_landed_msec = Time.get_ticks_msec()
				_say()
			elif not touch.pressed and touch.index == finger:
				# A QUICK TAP THAT WENT NOWHERE may be on a name (0.56.0).
				if Time.get_ticks_msec() - _landed_msec <= TouchControls.NAME_TAP_MSEC \
						and touch.position.distance_to(_landed_at) <= TouchControls.NAME_TAP_SLIDE:
					TouchControls.tap_name_at(get_global_transform_with_canvas() * touch.position)
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
		_place_base()
		queue_redraw()

	func running() -> bool:
		return finger >= 0 and radius > 0.0 and knob.length() >= radius * TouchControls.RUN_EDGE

	func _place_base() -> void:
		"""The round slot under the thumb, as wide as the stick - and no slot
		at rest (0.91.0)."""
		ring.visible = finger >= 0
		if not ring.visible:
			return
		var side: float = float(int(radius * 2.0 / pixel)) * pixel
		var corner: Vector2 = base - Vector2(side, side) / 2.0
		if per_unit >= 1.0:
			corner = (corner * per_unit).round() / per_unit
		# AT THE EDGE IT RUNS (0.91.1), and the ring lights to say so.
		ring.tint = STICK_RUNNING if running() else STICK_RING
		ring.place(Rect2(corner, Vector2(side, side)), pixel)

	func knob_rect() -> Rect2:
		"""Where the knob is drawn: the coin, a whole number of screen pixels to
		each of its own - or a small slot where a clone has no pack."""
		var at: Vector2 = base + knob.limit_length(radius)
		var side: float = knob_radius * 2.0
		if coin != null:
			var texels: int = maxi(coin.get_width(), coin.get_height())
			side = Art.texel_size(knob_radius * 2.0, texels, per_unit) * texels
		var corner: Vector2 = at - Vector2(side, side) / 2.0
		if per_unit >= 1.0:
			corner = (corner * per_unit).round() / per_unit
		return Rect2(corner, Vector2(side, side))

	func _draw() -> void:
		var held: bool = finger >= 0
		# ONLY UNDER A THUMB (0.91.0): at rest the stick is not drawn at all,
		# so the lower left is the game's. It appears where the thumb lands.
		if not held:
			return
		var tint: Color = STICK_RUNNING if running() else STICK_COIN
		var spot: Rect2 = knob_rect()
		if coin != null:
			draw_texture_rect(coin, spot, false, tint)
		else:
			Art.draw_socket(self, spot, pixel, TINT_LIT if held else tint)
