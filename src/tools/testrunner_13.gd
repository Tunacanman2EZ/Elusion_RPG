# testrunner_13.gd - part 13 of the suite (testrunner.gd says how it is
# split; part 12 passed 234 KB): _test_the_beholders_table.
extends "res://src/tools/testrunner_12.gd"


func _test_the_beholders_table() -> void:
	section("The Beholder's Table: the pinball table in the game (0.167.0)")
	var Run = require_script("res://src/world/pinball/pinballrun.gd", "pinballrun.gd")
	var Screen = require_script("res://src/world/pinball/pinballscreen.gd", "pinballscreen.gd")
	if Run == null or Screen == null:
		return
	# ---- the plunger: held it pulls, let go it launches as hard as pulled
	var run = Run.new()
	run.set("headless", true)
	run.set("seed_now", 5)
	add_child(run)
	var ball: Dictionary = run.balls[0]
	check("a game starts with a ball waiting on the plunger", bool(ball["held"]))
	check("  and nothing is blended by physics interpolation",
		run.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF)
	run.step_frames(90)
	check("  it waits for the player, however long", bool(ball["held"]))
	run.plunge(true)
	run.step_frames(int(Run.FPS * Run.PULL_SECONDS) + 4)
	check("  held, the plunger pulls all the way", float(run.pull) > 0.99, run.pull)
	run.plunge(false)
	run.step_frames(1)
	var full: float = -float((ball["v"] as Vector2).y)
	check("  let go, the ball goes", not bool(ball["held"]) and full > Run.LAUNCH_MOST * 0.8, full)
	run.queue_free()
	var soft = Run.new()
	soft.set("headless", true)
	soft.set("seed_now", 5)
	add_child(soft)
	soft.plunge(true)
	soft.step_frames(int(Run.FPS * Run.PULL_SECONDS * 0.2))
	soft.plunge(false)
	soft.step_frames(1)
	var gentle: float = -float(((soft.balls[0] as Dictionary)["v"] as Vector2).y)
	check("  a short pull launches softer", gentle > 0.0 and gentle < full * 0.75, [gentle, full])
	# ---- the flippers: every flipper of a side answers its button
	soft.press(-1, true)
	soft.step_frames(8)
	var left_up: bool = true
	var right_rest: bool = true
	for f in soft.flippers:
		if float(f["side"]) > 0.0:
			left_up = left_up and is_equal_approx(float(f["a"]), Run.UP)
		else:
			right_rest = right_rest and is_equal_approx(float(f["a"]), Run.REST)
	check("the left button lifts every left flipper, on every floor and the wire's", left_up)
	check("  and leaves the right ones down", right_rest)
	soft.press(-1, false)
	soft.step_frames(20)
	check("  let go, they fall back", soft.flippers.all(func(f: Dictionary) -> bool: return is_equal_approx(float(f["a"]), Run.REST)))
	# ---- the levers: a flip moves the lit top lanes along
	soft.lanes[0] = [true, false, false]
	soft.press(-1, true)
	check("a flip moves the lit lane (the levers)", soft.lanes[0] == [false, false, true], soft.lanes[0])
	soft.press(-1, false)
	soft.press(-1, true)
	check("  once a press, not every step it is held", soft.lanes[0] == [false, true, false], soft.lanes[0])
	soft.press(-1, false)
	# ---- three balls, then the game is over
	var over: Array = [0]
	soft.game_over.connect(func() -> void: over[0] += 1)
	for i in 3:
		soft.save_until = -1.0
		for b in soft.balls:
			(b as Dictionary)["held"] = false
			(b as Dictionary)["p"] = Vector2(600, Run.H + 60.0)
		soft.step_frames(1)
	check("the third ball lost ends the game", bool(soft.over) and over[0] == 1, [soft.over, soft.ball_no])
	var more = Run.new()
	more.set("headless", true)
	add_child(more)
	more.extra_balls = 1
	for i in 3:
		more.save_until = -1.0
		for b in more.balls:
			(b as Dictionary)["held"] = false
			(b as Dictionary)["p"] = Vector2(600, Run.H + 60.0)
		more.step_frames(1)
	check("  an extra ball won plays on", not bool(more.over) and more.balls.size() == 1)
	more.queue_free()
	soft.queue_free()
	# ---- the camera: up and down the table only, with slack
	var drawn = Run.new()
	drawn.set("seed_now", 7)
	add_child(drawn)
	var b0: Dictionary = drawn.balls[0]
	b0["held"] = false
	b0["p"] = Vector2(300, 3000)
	drawn._follow(true)
	var x0: float = drawn.cam3.position.x
	var y0: float = drawn.cam_y
	b0["p"] = Vector2(1000, 3060)
	for i in 30:
		drawn._follow(false)
	check("the camera never slides sideways after the ball", is_equal_approx(drawn.cam3.position.x, x0), [x0, drawn.cam3.position.x])
	check("  a ball inside its slack does not move it", is_equal_approx(drawn.cam_y, y0), [y0, drawn.cam_y])
	b0["p"] = Vector2(600, 2500)
	for i in 120:
		drawn._follow(false)
	check("  past the slack it follows up the table", drawn.cam_y < y0 - 300.0, [y0, drawn.cam_y])
	drawn.queue_free()
	# ---- the screen: keys, mouse, fingers, Leave
	var screen = Screen.new()
	screen.set("headless_run", true)
	screen.set("on_touch", func() -> bool: return false)
	add_child(screen)
	var r = screen.run
	check("the screen opens a game in its own world", r != null and screen.viewport.own_world_3d and r.get_parent() == screen.viewport)
	screen._input(_pin_key(KEY_Z, true))
	check("  Z holds the left flippers", bool(r._pressed.get("left", false)))
	screen._input(_pin_key(KEY_Z, false))
	screen._input(_pin_key(KEY_RIGHT, true))
	check("  the right arrow the right ones", bool(r._pressed.get("right", false)) and not bool(r._pressed.get("left", false)))
	screen._input(_pin_key(KEY_RIGHT, false))
	screen._input(_pin_key(KEY_SPACE, true))
	check("  Space pulls the plunger", bool(r._plunging))
	screen._input(_pin_key(KEY_SPACE, false))
	check("  and letting go launches", not bool(r._plunging))
	var box: Rect2 = screen.picture.get_global_rect()
	r.balls[0]["held"] = false
	screen._input(_pin_touch(0, box.position + Vector2(box.size.x * 0.8, box.size.y * 0.5), true))
	check("a finger on the right half holds the right flippers", bool(r._pressed.get("right", false)))
	screen._input(_pin_touch(1, box.position + Vector2(box.size.x * 0.2, box.size.y * 0.5), true))
	check("  a second on the left the left ones, both at once", bool(r._pressed.get("left", false)) and bool(r._pressed.get("right", false)))
	screen._input(_pin_touch(0, box.position + Vector2(box.size.x * 0.8, box.size.y * 0.5), false))
	check("  lifting one lets only its side go", not bool(r._pressed.get("right", false)) and bool(r._pressed.get("left", false)))
	screen._input(_pin_touch(1, box.position + Vector2(box.size.x * 0.2, box.size.y * 0.5), false))
	r.balls[0]["held"] = true
	screen._input(_pin_touch(2, box.position + Vector2(box.size.x * 0.2, box.size.y * 0.5), true))
	check("  while a ball waits, a finger anywhere pulls the plunger", bool(r._plunging) and not bool(r._pressed.get("left", false)))
	screen._input(_pin_touch(2, box.position + Vector2(box.size.x * 0.2, box.size.y * 0.5), false))
	check("  and lifting it launches", not bool(r._plunging))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = box.get_center()
	click.device = 0
	screen._touch_ms = -100000
	r.balls[0]["held"] = false
	screen._input(click)
	check("the left mouse button holds the left flippers", bool(r._pressed.get("left", false)))
	screen._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check("  losing focus lets every flipper go", not bool(r._pressed.get("left", false)) and not bool(r._plunging))
	screen.ask_to_leave()
	check("Leave during a game asks twice", is_instance_valid(screen) and not screen.is_queued_for_deletion())
	screen.ask_to_leave()
	check("  the second press leaves", screen.is_queued_for_deletion())
	print("  the Beholder's Table: plunger, flippers, levers, balls, camera, controls checked")


func _pin_key(code: Key, down: bool) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = code
	key.pressed = down
	return key


func _pin_touch(index: int, at: Vector2, down: bool) -> InputEventScreenTouch:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.position = at
	touch.pressed = down
	return touch
