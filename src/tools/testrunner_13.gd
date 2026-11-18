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
	b0["p"] = Vector2(1200, 3571)
	drawn._follow(true)
	check("  a ball on the plunger: it stops at the floor's foot, the view on the table (0.168.0)",
		drawn.cam_y <= 3600.0 - Run.CAM_FOOT + 0.5, drawn.cam_y)
	# 0.168.2: "when the ball is falling fast ... it flies past my flippers
	# before i can see" - it went off the foot of the screen, flippers too
	drawn.paused = true
	b0["p"] = Vector2(560, 2980)
	b0["v"] = Vector2(0, 2000)
	drawn.focus_ball = b0
	drawn._follow(true)
	var tall: float = drawn.get_viewport().get_visible_rect().size.y
	var lowest := 0.0
	for i in 40:
		drawn.step_frames(1)
		drawn._follow(false, 1.0 / 60.0)
		lowest = maxf(lowest, drawn.cam3.unproject_position(drawn._w(b0["p"], drawn._ball_height(b0))).y)
		if (b0["p"] as Vector2).y > 3440.0:
			break
	var flips: float = drawn.cam3.unproject_position(drawn._w(Vector2(600, 3460), 0.0)).y
	check("  a ball falling at full speed stays on the screen, and the flippers are in view as it reaches them",
		lowest < tall * 0.92 and flips < tall * 0.92, [lowest, flips, tall])
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


func _test_every_minigame_has_a_picture() -> void:
	section("Every minigame tile has a picture (0.168.0)")
	# Crownfall's and the Testing Ground's tiles stood empty: their monsters
	# are inherited scenes, and the portrait never looked in the scene they
	# inherit. Every tile's portrait must draw something.
	var Card = require_script("res://src/ui/minigames/minigamescard.gd", "minigamescard.gd")
	var Crown = require_script("res://src/world/crownfall/crownfallrun.gd", "crownfallrun.gd")
	if Card == null or Crown == null:
		return
	var consts: Dictionary = Card.get_script_constant_map()
	var portraits: Dictionary = consts["PORTRAITS"]
	var blank: Array = []
	for id in portraits:
		var picture: Texture2D = Card.portrait_of(str(portraits[id][0]))
		var image: Image = picture.get_image() if picture != null else null
		if image == null or image.is_empty() or image.get_used_rect().size == Vector2i.ZERO:
			blank.append(id)
	check("every tile's portrait draws something", blank.is_empty(), blank)
	var bricks: Image = Card.bricks_picture()
	var side: int = int(consts["PORTRAIT_SIZE"]) - 4
	check("Crownfall's is the drawn bricks, the portrait's own size",
		str(portraits["crownfall"][0]) == str(consts["BRICKS"]) and bricks.get_size() == Vector2i(side, side), bricks.get_size())
	var land_colours: Dictionary = consts["LAND_COLOURS"]
	var game_colours: Dictionary = Crown.get_script_constant_map()["COLOURS"]
	var differ: Array = []
	for land in game_colours:
		if not land_colours.has(land) or not (land_colours[land] as Color).is_equal_approx(game_colours[land]):
			differ.append(land)
	check("its bricks are Crownfall's own seven colours", differ.is_empty() and land_colours.size() == game_colours.size(), differ)
	# a picture keeps 8 bits a channel, so within one step of 255
	var top: Color = bricks.get_pixel(3, 2)
	var foot: Color = bricks.get_pixel(3, 26)
	var near := func(a: Color, b: Color) -> bool: return absf(a.r - b.r) < 0.006 and absf(a.g - b.g) < 0.006 and absf(a.b - b.b) < 0.006
	check("  light at the top, dark at the foot", near.call(top, land_colours["light"])
		and near.call(foot, land_colours["dark"]), [top, foot])
	print("  every minigame tile has a picture")


func _test_the_table_never_traps_a_ball() -> void:
	section("The Beholder's Table never keeps a ball for ever (0.168.0)")
	# The table's own bot found balls held for good: in the Field's right
	# orbit (its guide ended 22 px from its gate), and on the dead-flat top of
	# the XL2 ramp; and the old nudge, which read speed, never fired on a
	# ball rattling in a corner, and fired on one cradled on a flipper.
	var Run = require_script("res://src/world/pinball/pinballrun.gd", "pinballrun.gd")
	if Run == null:
		return
	var run = Run.new()
	run.headless = true
	run.seed_now = 7
	add_child(run)
	var ball: Dictionary = run.balls[0]
	ball["held"] = false
	ball["p"] = Vector2(1140, 1560)
	ball["v"] = Vector2.ZERO
	var lane := Rect2(1100, 1420, 80, 250)
	run.step_frames(240)
	check("a ball dropped down the Field's right orbit rolls off its gate onto the field",
		not lane.has_point(ball["p"]) and not ball.has("ride"), ball["p"])
	var nudges: int = int(run.stats["nudges"])
	for i in 100:
		ball["p"] = Vector2(600, 2900)
		ball["v"] = Vector2.ZERO
		run.step_frames(1)
	check("a ball held to one spot for %.1f s is nudged" % Run.STILL_SECONDS, int(run.stats["nudges"]) > nudges,
		[nudges, run.stats["nudges"]])
	var flipper: Dictionary = {}
	for f in run.flippers:
		if float(f["side"]) > 0.0 and int(f["floor"]) == 0 and not f.has("mini"):
			flipper = f
	run.press(-1, true)
	nudges = int(run.stats["nudges"])
	var on_it: Vector2 = (flipper["pivot"] as Vector2) + Vector2(60, -14)
	for i in 180:
		ball["p"] = on_it
		ball["v"] = Vector2.ZERO
		run.step_frames(1)
	check("  never one cradled on a flipper held up", int(run.stats["nudges"]) == nudges, [nudges, run.stats["nudges"]])
	run.press(-1, false)
	ball["ride"] = "XL2"
	ball["s"] = 520.0
	ball["rv"] = 0.0
	run.step_frames(360)
	check("a ball stopped on the level top of a ramp crawls on, off its end",
		str(ball.get("ride", "")) != "XL2" or float(ball.get("s", 0.0)) > 880.0, [ball.get("ride", ""), ball.get("s", 0.0)])
	run.queue_free()
	print("  no ball kept for ever")


func _test_the_table_pays() -> void:
	section("The Beholder's Table pays: three games a day through the server (0.168.0)")
	var Screen = require_script("res://src/world/pinball/pinballscreen.gd", "pinballscreen.gd")
	var Card = require_script("res://src/ui/minigames/minigamescard.gd", "minigamescard.gd")
	if Screen == null or Card == null:
		return
	var sent: Array = []
	var finish_ok := func(path: String, body: Dictionary, _t: float = 0.0) -> Dictionary:
		sent.append([path, body.duplicate()])
		return {"ok": true, "status": 200, "data": {"gold": 617, "score": body["score"], "best": 1234567,
			"new_best": true, "held_back": 0}}
	var screen = Screen.new()
	screen.set("headless_run", true)
	screen.set("on_touch", func() -> bool: return false)
	screen.run_id = 41
	screen.pays = {"points_per_gold": 2000, "most": 3000}
	screen.server_best = 500
	screen.finish_request = finish_ok
	add_child(screen)
	var r = screen.run
	screen._process(0.0)
	var at_start: String = str(r.purse_text)
	r.score = 1234567
	screen._process(0.0)
	var counted: String = str(r.purse_text)
	r.score = 7000000
	screen._process(0.0)
	check("the gold counts up on the table's panel by the server's table, to its most",
		at_start == "0 GOLD" and counted == "617 GOLD" and str(r.purse_text) == "3,000 GOLD  ·  MOST",
		[at_start, counted, r.purse_text])
	r.over = true
	await screen._on_game_over()
	check("Game Over finishes the run on the server with the score, and says what was paid and the best",
		sent.size() == 1 and sent[0][0] == "/api/minigames/finish" and sent[0][1] == {"run": 41, "score": 7000000}
		and screen.results.visible and str(screen.gold_line.text).begins_with("617 gold into your purse")
		and str(screen.best_line.text) == "A new best!  1,234,567", [sent, screen.gold_line.text, screen.best_line.text])
	await screen._pay()
	check("  once: it is not sent again", sent.size() == 1)
	screen.enter_request = func(_p: String, body: Dictionary, _t: float = 0.0) -> Dictionary:
		return {"ok": true, "status": 200, "data": {"run": 42, "plays_left": 1, "pays": {"points_per_gold": 2000, "most": 3000},
			"best_score": 1234567, "game": body.get("game")}}
	await screen.again()
	var r2 = screen.run
	check("Again asks for the day's next game and plays it", screen.run_id == 42 and r2 != r and not screen.results.visible,
		[screen.run_id])
	screen.enter_request = func(_p: String, _b: Dictionary, _t: float = 0.0) -> Dictionary:
		return {"ok": false, "status": 409, "data": {"ready_in": 3600, "plays_left": 0}}
	await screen.again()
	screen._process(0.0)
	var r3 = screen.run
	check("  with none left, Again pays the last and the next is practice: PRACTICE on the panel",
		sent.size() == 2 and int(sent[1][1]["run"]) == 42 and screen.run_id == 0 and r3 != r2
		and str(r3.purse_text) == "PRACTICE", [sent.size(), screen.run_id])
	r3.over = true
	await screen._on_game_over()
	check("  a practice game sends nothing and says it pays nothing", sent.size() == 2
		and str(screen.pay_line.text).contains("pays nothing"))
	screen.run_id = 43
	screen.start()
	screen.finish_request = func(_p: String, _b: Dictionary, _t: float = 0.0) -> Dictionary:
		return {"ok": false, "status": 0}
	screen.ask_to_leave()
	screen.ask_to_leave()
	check("Leave during a paid game, the server not reached: the screen stays and says so",
		is_instance_valid(screen) and not screen.is_queued_for_deletion()
		and str(screen.result_line.text) == "Could not reach the server", screen.result_line.text)
	screen.finish_request = finish_ok
	screen.leave()
	check("  Leave again pays it, then goes", sent.size() == 3 and int(sent[2][1]["run"]) == 43
		and screen.is_queued_for_deletion(), sent.size())
	# ---- the card ----
	var was_owner: bool = Api.is_owner
	Api.is_owner = true
	var card_hud := Control.new()
	add_child(card_hud)
	var card = (load("res://src/ui/minigames/minigamescard.gd") as GDScript).call("attach", card_hud)
	card.set("area_now", func() -> String: return "elusion")
	card.set("class_now", func() -> String: return "warrior")
	card.set("list_request", func(_p: String, _t: float = 0.0) -> Dictionary:
		return {"ok": true, "data": {"games": [{"id": "pinball", "plays_left": 2, "ready_in": 0, "best_score": 1234567}]}})
	var asked: Array = []
	card.set("enter_request", func(path: String, body: Dictionary, _t: float = 0.0) -> Dictionary:
		asked.append([path, body])
		return {"ok": true, "status": 200, "data": {"run": 41, "plays_left": 1, "ready_in": 0,
			"pays": {"points_per_gold": 2000, "most": 3000}, "best_score": 1234567}})
	var opened: Array = []
	card.set("open_pinball", func(run_on_server: int, what: Dictionary, best_known: int) -> void:
		opened.append([run_on_server, what, best_known]))
	card.call("open")
	await get_tree().process_frame
	await get_tree().process_frame
	var said: String = card.pinball_status.text
	await card.call("_on_pinball_go")
	check("the tile says \"%s\"; Go asks the server for a game and opens the table on it with its gold and the best" % said,
		said.contains("2 of 3 games") and said.contains("best 1,234,567") and asked.size() == 1
		and asked[0][1].get("game") == "pinball" and opened.size() == 1 and int(opened[0][0]) == 41
		and (opened[0][1] as Dictionary).get("most") == 3000 and int(opened[0][2]) == 1234567, [said, asked, opened])
	card.set("enter_request", func(path: String, body: Dictionary, _t: float = 0.0) -> Dictionary:
		asked.append([path, body])
		return {"ok": false, "status": 409, "data": {"ready_in": 3600, "plays_left": 0}})
	await card.call("_on_pinball_go")
	card.call("paint")
	var none_said: String = card.pinball_status.text
	await card.call("_on_pinball_go")
	check("  none left (409): it opens as practice, the tile says when the next paid game is (\"%s\"), and the next Go asks nothing" % none_said,
		asked.size() == 2 and opened.size() == 3 and int(opened[1][0]) == 0 and int(opened[2][0]) == 0
		and none_said.begins_with("Practice - paid games back in"), [asked.size(), opened, none_said])
	Api.is_owner = was_owner
	card_hud.queue_free()
	await get_tree().process_frame
	print("  the table pays: done")


func _test_the_table_on_a_phone() -> void:
	section("The Beholder's Table on a phone (0.168.0)")
	var Run = require_script("res://src/world/pinball/pinballrun.gd", "pinballrun.gd")
	var Screen = require_script("res://src/world/pinball/pinballscreen.gd", "pinballscreen.gd")
	if Run == null or Screen == null:
		return
	Run.pretend_phone = true
	var holder := SubViewport.new()
	holder.size = Vector2i(1280, 720)
	add_child(holder)
	var run = Run.new()
	run.seed_now = 7
	holder.add_child(run)
	Run.pretend_phone = false
	var fills_out: bool = run.fills.all(func(l: OmniLight3D) -> bool: return not l.visible)
	check("a phone's table draws lighter: no shadows, no glow, the fill lights out, the 3D at %d%%, each floor's moving layer and each eye at half"
		% int(Run.PHONE_3D_SCALE * 100.0),
		run.light and not run.sun_light.shadow_enabled and not run.world_env.glow_enabled and fills_out
		and is_equal_approx(holder.scaling_3d_scale, Run.PHONE_3D_SCALE)
		and (run.moving_vps[0] as SubViewport).size == Vector2i(620, 600)
		and (run.eye_vps as Array).all(func(v: SubViewport) -> bool: return v.size == Vector2i(128, 128)),
		[run.light, run.sun_light.shadow_enabled, run.world_env.glow_enabled, fills_out, holder.scaling_3d_scale,
		(run.moving_vps[0] as SubViewport).size])
	holder.queue_free()
	var screen = Screen.new()
	screen.set("headless_run", true)
	screen.set("on_touch", func() -> bool: return true)
	add_child(screen)
	screen._process(0.1)
	var wide: float = screen.leave_button.anchor_right - screen.leave_button.anchor_left
	check("on a touch screen a new game says which half holds which flippers, how to launch, and Leave is bigger",
		screen.left_hint.visible and screen.right_hint.visible and screen.plunger_hint.visible
		and wide > Screen.LEAVE_BOX.size.x / float(Screen.VIEW.x) * 1.3, [screen.left_hint.visible, screen.plunger_hint.visible, wide])
	screen._process(Screen.HINT_SECONDS)
	screen.run.balls[0]["held"] = false
	screen._process(0.0)
	check("  the halves' words go after a few seconds, the launch's once the ball is away",
		not screen.left_hint.visible and not screen.right_hint.visible and not screen.plunger_hint.visible)
	screen.on_touch = func() -> bool: return false
	screen.start()
	screen._process(0.1)
	check("  with keys none of it shows, and Leave is its own size",
		not screen.left_hint.visible and not screen.plunger_hint.visible
		and is_equal_approx(screen.leave_button.anchor_right - screen.leave_button.anchor_left, Screen.LEAVE_BOX.size.x / float(Screen.VIEW.x)))
	screen.queue_free()
	print("  the table on a phone: done")


func _test_the_gale_is_fair() -> void:
	section("The gale bends a shot, it never drains one (0.168.0)")
	# The owner: "when wind is blowing its a instant loss" - the gale pushed at
	# 620 px/s a second everywhere, flippers and outlanes too.
	var Run = require_script("res://src/world/pinball/pinballrun.gd", "pinballrun.gd")
	if Run == null:
		return
	var run = Run.new()
	run.headless = true
	run.seed_now = 7
	add_child(run)
	run.wind_dir = -1.0
	run.effect = {"land": "wind", "warn": run.t - 3.0, "from": run.t - 2.0, "to": run.t + 6.0, "begun": true}
	var ball: Dictionary = run.balls[0]
	ball["held"] = false
	var pushed := func(at: Vector2) -> float:
		ball["p"] = at
		ball["v"] = Vector2.ZERO
		ball.erase("ride")
		run.step_frames(6)
		return (ball["v"] as Vector2).x
	var high: float = pushed.call(Vector2(600, 2980))
	var low: float = pushed.call(Vector2(600, 3330))
	check("up the table the gale pushes the ball its way, at %d px/s a second (it was 620)" % int(Run.GALE_PUSH),
		high < -10.0 and Run.GALE_PUSH <= 320.0, high)
	check("  over the flippers and their lanes the air is still", absf(low) < 1.0, low)
	run.queue_free()
	print("  the gale is fair")


func _test_the_minigames_grid() -> void:
	section("The Minigames card is a grid that fits the screen (0.168.1)")
	# The owner: "we have to remake the minigames hud because I cannot see
	# the new minigame" - nine tiles in one column stood 680 of 720 high.
	var was_owner: bool = Api.is_owner
	Api.is_owner = true
	var card_hud := Control.new()
	card_hud.size = Vector2(1280, 720)
	add_child(card_hud)
	var bar := Button.new()
	bar.name = "minigamesbutton"
	bar.unique_name_in_owner = true
	card_hud.add_child(bar)
	bar.owner = card_hud
	bar.position = Vector2(734, 676)
	bar.size = Vector2(99, 30)
	var card = (load("res://src/ui/minigames/minigamescard.gd") as GDScript).call("attach", card_hud)
	card.set("area_now", func() -> String: return "elusion")
	card.set("class_now", func() -> String: return "warrior")
	card.set("list_request", func(_p: String, _t: float = 0.0) -> Dictionary: return {"ok": true, "data": {"games": []}})
	var asked: Array = []
	card.set("enter_request", func(path: String, body: Dictionary, _t: float = 0.0) -> Dictionary:
		asked.append(body.get("game", ""))
		return {"ok": false, "status": 0})
	card.call("open")
	await get_tree().process_frame
	await get_tree().process_frame
	var endless: Control = card.endless_box
	var healer: Control = card.healer_box
	var drawn: Rect2 = (card as Control).get_global_rect()
	var shown: Array = card.grid.get_children().filter(func(t: Control) -> bool: return t.visible)
	var in_view: bool = shown.all(func(t: Control) -> bool: return drawn.encloses(t.get_global_rect()))
	check("two columns: the Endless and the Healer's Run side by side",
		card.grid.columns == 2 and is_equal_approx(endless.position.y, healer.position.y) and healer.position.x > endless.position.x,
		[endless.position, healer.position])
	check("  every game shown (%d) is on the card, the card on the screen above the bar, no scroll needed" % shown.size(),
		shown.size() >= 9 and in_view and drawn.position.y >= 0.0 and drawn.end.y <= bar.position.y
		and is_equal_approx(card.scroller.custom_minimum_size.y, card.grid.get_combined_minimum_size().y), [drawn, shown.size()])
	bar.position = Vector2(734, 300)
	card.call("_place")
	await get_tree().process_frame
	drawn = (card as Control).get_global_rect()
	check("  with the bar high up, the card keeps above it and its list scrolls",
		drawn.position.y >= 0.0 and drawn.end.y <= 300.0 and card.scroller.custom_minimum_size.y < card.grid.get_combined_minimum_size().y,
		[drawn, card.scroller.custom_minimum_size.y])
	var tile: Control = card.pinball_box
	var go: Button = card.pinball_go
	var tap := func(from: Vector2, to: Vector2) -> void:
		var down := InputEventMouseButton.new()
		down.button_index = MOUSE_BUTTON_LEFT
		down.pressed = true
		down.global_position = from
		card._on_tile_input(down, tile, go)
		var up := InputEventMouseButton.new()
		up.button_index = MOUSE_BUTTON_LEFT
		up.pressed = false
		up.global_position = to
		card._on_tile_input(up, tile, go)
	tap.call(Vector2(500, 200), Vector2(503, 202))
	await get_tree().process_frame
	var after_tap: Array = asked.duplicate()
	tap.call(Vector2(500, 200), Vector2(500, 260))
	await get_tree().process_frame
	check("a tap on a game's card is its Go; a drag (the scroll) is not",
		after_tap == ["pinball"] and asked == ["pinball"], [after_tap, asked])
	Api.is_owner = was_owner
	card_hud.queue_free()
	await get_tree().process_frame
	print("  the grid: done")


func _test_the_table_opens_and_bounces_back() -> void:
	section("The table opens quicker, and its kickbacks moved up the side walls (0.168.2)")
	# The owner: "it takes almost 6 seconds to launch the minigame", and
	# "ball hits bumpers on right then just falls down to the lose a ball area
	# the bounce backs are too low on the board".
	var Screen = require_script("res://src/world/pinball/pinballscreen.gd", "pinballscreen.gd")
	var Healer = require_script("res://src/world/healerrun/healerrunscreen.gd", "healerrunscreen.gd")
	var Run = require_script("res://src/world/pinball/pinballrun.gd", "pinballrun.gd")
	if Screen == null or Healer == null or Run == null:
		return
	var src: String = FileAccess.get_file_as_string("res://src/world/pinball/pinballscreen.gd")
	var same := true
	for c in [[617, 0], [617, 1383], [0, 250], [0, 0], [12345678, 9]]:
		same = same and Screen.paid_line("The Beholder's Table", c[0], c[1]) == Healer.paid_line("The Beholder's Table", c[0], c[1])
	check("the screen no longer loads the Healer's Run for its paid line, and says the same words",
		not src.contains("healerrunscreen.gd\")") and same)
	# the bounce-backs: a ball sliding down the right side wall is thrown back
	# up while that side's KICK is lit, spending it; dark, it rolls in
	for lit in [true, false]:
		var run = Run.new()
		run.headless = true
		run.seed_now = 7
		add_child(run)
		run.save_until = -100.0
		run.kickbacks = [false, lit]
		var ball: Dictionary = run.balls[0]
		ball["held"] = false
		ball["p"] = Vector2(1140, 3010)
		ball["v"] = Vector2(-380, 300)
		var highest_after := 99999.0
		var low_point := 0.0
		for i in 90:
			run.step_frames(1)
			var y: float = (ball["p"] as Vector2).y
			low_point = maxf(low_point, y)
			if low_point > 3150.0:
				highest_after = minf(highest_after, y)
		if lit:
			check("  lit, a ball down the right side wall meets its bounce-back, goes back up the table and spends the KICK",
				run.ball_no == 1 and highest_after < 3000.0 and run.kickbacks == [false, false] and int(run.stats["kickbacks"]) == 1,
				[ball["p"], highest_after, run.ball_no, run.kickbacks])
		else:
			check("  dark, the same ball rolls on into the outlane",
				highest_after > 3150.0 and int(run.stats["kickbacks"]) == 0, [ball["p"], highest_after, run.ball_no])
		run.queue_free()
	# the card says it is opening, drawn, before the table loads
	var was_owner: bool = Api.is_owner
	Api.is_owner = true
	var card_hud := Control.new()
	add_child(card_hud)
	var card = (load("res://src/ui/minigames/minigamescard.gd") as GDScript).call("attach", card_hud)
	card.set("area_now", func() -> String: return "elusion")
	card.set("class_now", func() -> String: return "warrior")
	card.set("list_request", func(_p: String, _t: float = 0.0) -> Dictionary: return {"ok": true, "data": {"games": []}})
	card.set("enter_request", func(_p: String, _b: Dictionary, _t: float = 0.0) -> Dictionary:
		return {"ok": true, "status": 200, "data": {"run": 5, "plays_left": 2, "pays": {}, "best_score": 0}})
	var opened: Array = []
	card.set("open_pinball", func(run_id: int, _w: Dictionary, _b: int) -> void: opened.append(run_id))
	card.call("open")
	await get_tree().process_frame
	card.call("_on_pinball_go")
	await get_tree().process_frame
	var said: String = card.pinball_status.text
	var before: int = opened.size()
	await get_tree().process_frame
	await get_tree().process_frame
	check("  Go says \"%s\" on the tile, drawn, before the table is opened" % said,
		said == card.OPENING and before == 0 and opened == [5], [said, before, opened])
	Api.is_owner = was_owner
	card_hud.queue_free()
	await get_tree().process_frame
	print("  opens and bounces back: done")
