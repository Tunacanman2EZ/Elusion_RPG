# touchcontrols.gd - the game on a touch screen (0.53.0). Autoload: TouchControls.
#
# The owner: "make the game mobile", and of the ways to, "Phone browsers
# (Recommended)". Everything in the game is played through input ACTIONS -
# move_*, sprint, attack, interact - so a phone plays it the same way. The pad
# on the HUD (touchpad.gd) writes here what the thumbs are doing, and once a
# physics frame, before any other node's (process_physics_priority), this turns
# it into the actions the keys would press. The player, the shops, the bank,
# the fire and the fishing spot read those, and cannot tell a thumb from a key.
#
# ON AT THE FIRST TOUCH, OFF AT A KEY. A phone has no keyboard, and a laptop
# with a touch screen has both: a finger on the screen turns the pad on, and a
# key pressed - or a click from a real mouse - turns it off. NOT a key typed
# into a text box: a phone's own keyboard sends keys too, and typing a chat
# line must not take the pad away.
#
# THE FIRST FINGER IS A MOUSE AS WELL. Godot copies the first finger on the
# screen into mouse events (emulate_mouse_from_touch), which is what lets a
# finger press the HUD's buttons and open its windows. Copied, those clicks
# would also attack from wherever the finger is - on the stick, say - so the
# player takes no click that was copied from a finger (player.gd,
# _unhandled_input); a finger on the world is an attack here instead, whichever
# finger it is.
#
# THE AIM. A mouse aims at the cursor and a keyboard where the character faces
# (player.gd, THE CURSOR, WHEN THERE IS ONE). A thumb on a button has no
# cursor, so on a touch screen aim_point() asks here first (aim_for()):
#   1. a finger on the world - not on the pad or a window - aims where it is,
#      as a click does, and is an attack;
#   2. the Aura button dragged, the way it is dragged, and as far;
#   3. the Attack button dragged, the way it is dragged;
#   4. otherwise the nearest monster within AUTO_AIM_RANGE;
#   5. otherwise nothing here, and the player aims where it faces.
#
# HELD, THE ATTACK BUTTON KEEPS ATTACKING where a class means the same thing by
# a second press (touch_attack_repeats(): the warrior's swing, the mage's
# cast), pressed again each time the class is ready (touch_attack_ready()), so
# a held thumb is a click a swing and never costs a frame of walking more than
# clicking would. Where a second press means something else - the tank's aura
# goes off, the Double Axe comes home - it is held like a key, and the healer,
# who fires for as long as attack is down, streams.
extends Node

signal changed(on: bool)

# Loaded when a HUD asks, not preloaded: the pad's script names this autoload,
# and a preload each way is a cycle for the compiler.
const PAD_PATH := "res://src/ui/touchpad.gd"

# How far from the character the auto-aim looks for a monster, in world pixels.
const AUTO_AIM_RANGE := 260.0
# A button dragged less than this share of its reach has not been dragged.
const DRAG_DEAD := 0.25
# The Attack button dragged all the way aims this far ahead (a spell, a stick of
# dynamite); a small drag, KEYBOARD_AIM_REACH ahead as a keyboard would.
const DRAG_REACH := 200.0
const KEYBOARD_AIM_REACH := 64.0
# A skill dragged a little lands this close; all the way, at the class's reach.
const SKILL_NEAREST := 24.0
# The stick: under this share of its reach is no direction; past it, 8 ways,
# each a 45-degree slice (sin 22.5 degrees is where one slice meets the next).
const STICK_DEAD := 0.22
const EIGHTH := 0.3827

const MOVES: Array[StringName] = [&"move_right", &"move_left", &"move_down", &"move_up"]

var active: bool = false

# WHAT THE PAD HOLDS, written by touchpad.gd. stick and the drags are shares of
# their reach, each no longer than 1.
var stick: Vector2 = Vector2.ZERO
var stick_held: bool = false
var attack_held: bool = false
var attack_drag: Vector2 = Vector2.ZERO
var skill_held: bool = false
var skill_drag: Vector2 = Vector2.ZERO
var sprint_on: bool = false
var use_held: bool = false

# THIS PHYSICS FRAME'S: the skill was let go (it drops where it was dragged to,
# skill_point()) - true for the one frame.
var skill_fired: bool = false
var skill_fired_drag: Vector2 = Vector2.ZERO

# A finger on the world: which, and where on the screen.
var _world_finger: int = -1
var _world_screen: Vector2 = Vector2.ZERO
# The world point stays the aim for the frame the tap's press lands on and the
# next, so a tap quicker than a frame still aims where it touched.
var _world_aim_ticks: int = 0

# Presses that have not had a physics frame yet: a tap quicker than a frame is
# still seen once.
var _attack_tap: bool = false
var _tap_on_world: bool = false
var _use_tap: bool = false
var _skill_release: bool = false
var _skill_release_drag: Vector2 = Vector2.ZERO
var _stick_was_held: bool = false

# The actions this has pressed, so it lets go of exactly those.
var _pressed: Dictionary = {}

# aim_for() is asked several times a frame (the ring, the attack): the monster
# search is made once a frame.
var _aim_frame: int = -1
var _aim_target: Node2D = null


func _ready() -> void:
	process_physics_priority = -1000


# =============================================================================
# ON AND OFF
# =============================================================================

func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	if not on:
		clear()
	changed.emit(on)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		set_active(true)
		return
	if not active:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and not typing():
		set_active(false)
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.device != InputEvent.DEVICE_ID_EMULATION:
		set_active(false)


func typing() -> bool:
	"""A text box that can be typed in has the keyboard - a phone's own keyboard
	sends keys while a chat line is written."""
	var viewport: Viewport = get_viewport()
	var focused: Control = viewport.gui_get_focus_owner() if viewport != null else null
	if focused == null or not focused.is_visible_in_tree():
		return false
	if focused is LineEdit:
		return (focused as LineEdit).editable
	if focused is TextEdit:
		return (focused as TextEdit).editable
	return false


func clear() -> void:
	"""Every thumb up: the pad gone with its HUD, or the pad switched off."""
	stick = Vector2.ZERO
	stick_held = false
	attack_held = false
	attack_drag = Vector2.ZERO
	skill_held = false
	skill_drag = Vector2.ZERO
	sprint_on = false
	use_held = false
	_world_finger = -1
	_world_aim_ticks = 0
	_attack_tap = false
	_tap_on_world = false
	_use_tap = false
	_skill_release = false
	_stick_was_held = false
	release_all()


func release_all() -> void:
	for action in _pressed.keys():
		Input.action_release(action)
	_pressed.clear()


# =============================================================================
# THE PAD SAYS
# =============================================================================

func attach(hud: Node) -> Control:
	"""The pad on a HUD, as its FIRST child: drawn under every window and bar on
	it, and every one of those takes a touch before the pad does."""
	var pad: Control = (load(PAD_PATH) as GDScript).new()
	pad.name = "touchpad"
	hud.add_child(pad)
	hud.move_child(pad, 0)
	return pad


func press_attack() -> void:
	attack_held = true
	attack_drag = Vector2.ZERO
	_attack_tap = true
	_tap_on_world = false


func release_attack() -> void:
	attack_held = false
	attack_drag = Vector2.ZERO


func press_use() -> void:
	use_held = true
	_use_tap = true


func release_use() -> void:
	use_held = false


func press_skill() -> void:
	skill_held = true
	skill_drag = Vector2.ZERO


func release_skill() -> void:
	if skill_held:
		_skill_release = true
		_skill_release_drag = skill_drag
	skill_held = false
	skill_drag = Vector2.ZERO


func toggle_sprint() -> void:
	sprint_on = not sprint_on


# =============================================================================
# A FINGER ON THE WORLD
# =============================================================================
# Reaches _unhandled_input only when no window, bar or pad button took it.

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			if _world_finger < 0 and player() != null:
				_world_finger = touch.index
				_world_screen = touch.position
				_attack_tap = true
				_tap_on_world = true
				get_viewport().set_input_as_handled()
		elif touch.index == _world_finger:
			_world_finger = -1
		return
	var drag := event as InputEventScreenDrag
	if drag != null and drag.index == _world_finger:
		_world_screen = drag.position


func world_finger() -> int:
	return _world_finger


# =============================================================================
# EACH PHYSICS FRAME, BEFORE ANYONE READS THE ACTIONS
# =============================================================================

func _physics_process(_delta: float) -> void:
	skill_fired = false
	if _world_aim_ticks > 0:
		_world_aim_ticks -= 1
	if not active:
		if not _pressed.is_empty():
			release_all()
		return
	var body: Node2D = player()
	_latch_move()
	_latch_attack(body)
	_latch_use()
	if _skill_release:
		_skill_release = false
		skill_fired = true
		skill_fired_drag = _skill_release_drag


func _latch_move() -> void:
	# RUN IS FOR THIS RUN: lifting the thumb off the stick ends it.
	if _stick_was_held and not stick_held:
		sprint_on = false
	_stick_was_held = stick_held
	var way: Vector2 = move_way(stick)
	_set_action(&"move_right", way.x > 0.0)
	_set_action(&"move_left", way.x < 0.0)
	_set_action(&"move_down", way.y > 0.0)
	_set_action(&"move_up", way.y < 0.0)
	_set_action(&"sprint", sprint_on and way != Vector2.ZERO)


static func move_way(at: Vector2) -> Vector2:
	"""The stick as the keys it stands for: each of x and y -1, 0 or 1, eight
	ways and none."""
	if at.length() < STICK_DEAD:
		return Vector2.ZERO
	var n: Vector2 = at.normalized()
	return Vector2(signf(n.x) if absf(n.x) > EIGHTH else 0.0, signf(n.y) if absf(n.y) > EIGHTH else 0.0)


func _latch_attack(body: Node2D) -> void:
	var holding: bool = attack_held or _world_finger >= 0
	var want: bool
	if _attack_tap:
		if _is_pressed(&"attack"):
			# A NEW PRESS NEEDS AN UP FIRST: a frame up, and the tap's own press
			# on the next.
			want = false
		else:
			want = true
			_attack_tap = false
			if _tap_on_world:
				_tap_on_world = false
				_world_aim_ticks = 2
	elif not holding:
		want = false
	elif body != null and body.has_method("touch_attack_repeats") and body.call("touch_attack_repeats"):
		want = not _is_pressed(&"attack") and bool(body.call("touch_attack_ready"))
	else:
		want = true
	_set_action(&"attack", want)


func _latch_use() -> void:
	if _use_tap:
		_use_tap = false
		_set_action(&"interact", true)
		return
	_set_action(&"interact", use_held)


func _set_action(action: StringName, down: bool) -> void:
	if down == _is_pressed(action):
		return
	if down:
		Input.action_press(action)
		_pressed[action] = true
	else:
		Input.action_release(action)
		_pressed.erase(action)


func _is_pressed(action: StringName) -> bool:
	return _pressed.has(action)


# =============================================================================
# THE AIM
# =============================================================================

func player() -> Node2D:
	var tree: SceneTree = get_tree()
	return tree.get_first_node_in_group(&"player") as Node2D if tree != null else null


func aim_for(body: Node2D) -> Variant:
	"""Where `body`'s attack aims now, on a touch screen - or null, and it aims
	the way it faces (THE AIM, above)."""
	if _world_finger >= 0 or _world_aim_ticks > 0:
		return body.call("world_point_at", _world_screen)
	if skill_held and skill_drag.length() >= DRAG_DEAD:
		return skill_point(body, skill_drag)
	if attack_held and attack_drag.length() >= DRAG_DEAD:
		return body.global_position + attack_drag.normalized() * drag_reach(attack_drag.length())
	var target: Node2D = aim_target(body)
	if target != null:
		return target_point(target)
	return null


static func drag_reach(share: float) -> float:
	"""How far ahead a drag of `share` of the button's reach aims."""
	return lerpf(KEYBOARD_AIM_REACH, DRAG_REACH, clampf(inverse_lerp(DRAG_DEAD, 1.0, share), 0.0, 1.0))


func skill_point(body: Node2D, drag: Vector2) -> Vector2:
	"""Where a skill let go with `drag` lands: at the feet for a tap, and the way
	it was dragged, as far as it was, up to the class's reach."""
	if drag.length() < DRAG_DEAD:
		return body.global_position
	var reach: float = float(body.call("touch_skill_reach")) if body.has_method("touch_skill_reach") else DRAG_REACH
	var share: float = clampf(inverse_lerp(DRAG_DEAD, 1.0, drag.length()), 0.0, 1.0)
	return body.global_position + drag.normalized() * lerpf(SKILL_NEAREST, reach, share)


func aim_target(body: Node2D) -> Node2D:
	var frame: int = Engine.get_physics_frames()
	if frame != _aim_frame or not is_instance_valid(_aim_target):
		_aim_frame = frame
		_aim_target = nearest_monster(body.get_tree(), body.global_position, AUTO_AIM_RANGE)
	return _aim_target if is_instance_valid(_aim_target) else null


static func nearest_monster(tree: SceneTree, from: Vector2, reach: float) -> Node2D:
	"""The closest monster within `reach` that can still be hit, or null."""
	if tree == null:
		return null
	var best: Node2D = null
	var best_d: float = reach * reach
	for node in tree.get_nodes_in_group(&"enemies"):
		var monster := node as Node2D
		if monster == null or not is_instance_valid(monster) or not monster.is_visible_in_tree():
			continue
		if monster.has_method("can_be_aimed_at") and not monster.call("can_be_aimed_at"):
			continue
		var d: float = from.distance_squared_to(target_point(monster))
		if d <= best_d:
			best_d = d
			best = monster
	return best


static func target_point(monster: Node2D) -> Vector2:
	"""Where a monster's BODY is - its "bodyshape" - rather than its origin,
	which sits somewhere else in every scene (targets.gd, body_point())."""
	var shape: Node2D = monster.get_node_or_null(^"bodyshape") as Node2D
	return shape.global_position if shape != null else monster.global_position
