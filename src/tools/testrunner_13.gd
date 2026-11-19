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
	b0["p"] = Vector2(400, 3000)
	drawn._follow(true)
	var x0: float = drawn.cam3.position.x
	var y0: float = drawn.cam_y
	b0["p"] = Vector2(800, 3060)
	for i in 30:
		drawn._follow(false)
	# since 0.168.5 it leans a little toward a ball near a wall (its own test)
	check("the camera does not slide sideways after a ball about the middle", is_equal_approx(drawn.cam3.position.x, x0), [x0, drawn.cam3.position.x])
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
	screen.run.score = 50000
	screen.finish_request = func(_p: String, _b: Dictionary, _t: float = 0.0) -> Dictionary:
		return {"ok": false, "status": 0}
	screen.ask_to_leave()
	screen.ask_to_leave()
	check("Leave during a paid game, the server not reached: the screen stays and says so (0.168.8's words)",
		is_instance_valid(screen) and not screen.is_queued_for_deletion()
		and str(screen.result_line.text) == "No answer from the server.", screen.result_line.text)
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
	section("The Beholder's Table on a phone (0.168.0, cooler 0.168.4), fewer draws (0.168.7)")
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
	# COOLER ON A PHONE (0.168.4): "phone started to overheat on minigame"
	var lit_count := func(r: Node) -> int:
		return (r.world.find_children("*", "OmniLight3D", true, false) as Array).filter(
			func(l: Node) -> bool: return (l as Light3D).visible).size()
	var cadence := func(r: Node) -> Array:
		var modes: Array = []
		var vp: SubViewport = r.moving_vps[(r.floor_seen as Array).find(true)]
		for i in 4:
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			r._sync_world()
			modes.append(vp.render_target_update_mode)
		return modes
	var phone_lights: int = lit_count.call(run)
	var phone_modes: Array = cadence.call(run)
	check("  cooler (0.168.4): none of the table's own lights on, the moving layer painted and drawn every other frame, once, the panel painted on its own",
		phone_lights == 0 and phone_modes.count(SubViewport.UPDATE_ONCE) == 2 and phone_modes.count(SubViewport.UPDATE_DISABLED) == 2
		and run.panel_node.draw.is_connected(run._paint_panel_layer), [phone_lights, phone_modes])
	var world_joins := func(r: Node) -> Array:
		return (r.joined_meshes as Array).filter(func(m: Node) -> bool: return m.get_parent() == r.world)
	var phone_joins: int = world_joins.call(run).size()
	var phone_shadow_meshes: int = run.shadow_meshes.size()
	holder.queue_free()
	var desk_holder := SubViewport.new()
	desk_holder.size = Vector2i(1280, 720)
	add_child(desk_holder)
	var desk = Run.new()
	desk.seed_now = 7
	desk_holder.add_child(desk)
	var desk_lights: int = lit_count.call(desk)
	desk._layers_at = -100.0
	var desk_modes: Array = cadence.call(desk)
	desk._layers_at -= 1.0
	var desk_vp: SubViewport = desk.moving_vps[(desk.floor_seen as Array).find(true)]
	desk_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	desk._sync_world()
	var later: int = desk_vp.render_target_update_mode
	check("  a PC's table keeps its lights; its layers are painted at most %d times a second (0.168.7), each drawn once then"
		% int(Run.PAINT_HZ), desk_lights > 10 and desk_modes == [SubViewport.UPDATE_ONCE, SubViewport.UPDATE_DISABLED,
		SubViewport.UPDATE_DISABLED, SubViewport.UPDATE_DISABLED] and later == SubViewport.UPDATE_ONCE, [desk_lights, desk_modes, later])
	# the panel is a picture of its own, shown as one sprite, drawn when painted
	var shown: Sprite2D = desk.panel_vp.get_parent().find_child("panel", true, false) as Sprite2D
	desk._panel_at = -100.0
	desk.panel_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	desk._sync_world()
	var painted: int = desk.panel_vp.render_target_update_mode
	desk.panel_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	desk._sync_world()
	check("  the side panel is a picture of its own (one sprite over the table), painted and drawn at most %d times a second" % int(Run.PANEL_HZ),
		shown != null and shown.texture == desk.panel_vp.get_texture() and desk.panel_node.get_parent() == desk.panel_vp
		and painted == SubViewport.UPDATE_ONCE and desk.panel_vp.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		[shown, painted])
	# round meshes as fine as the camera shows
	var finest: int = 0
	for mi in desk.world.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh is SphereMesh:
			finest = maxi(finest, (mesh as SphereMesh).radial_segments)
		elif mesh is CylinderMesh:
			finest = maxi(finest, (mesh as CylinderMesh).radial_segments)
	check("  no sphere or post finer than 32 round (Godot's default is 64)", finest > 0 and finest <= 32, finest)
	# THE STILL PIECES (0.168.7, more): joined by look, no mesh lit by more
	# lamps than a renderer keeps, the plain ones' shadows apart
	var lamps: Array = []
	for l in desk.world.find_children("*", "OmniLight3D", true, false):
		if (l as Node3D).visible:
			lamps.append([(l as Node3D).position, (l as OmniLight3D).omni_range])
	var joins: Array = world_joins.call(desk)
	var most_lamps: int = 0
	var casting: int = 0
	for mi in joins:
		var mat: Material = (mi as MeshInstance3D).material_override
		if not (mat is BaseMaterial3D and (mat as BaseMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED):
			most_lamps = maxi(most_lamps, Run._lamps_on((mi as MeshInstance3D).transform * (mi as MeshInstance3D).mesh.get_aabb(), lamps))
		if (mi as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and Run._plain_shadow(mat):
			casting += 1
	var only_shadow: bool = true
	for m in desk.shadow_meshes:
		only_shadow = only_shadow and (m as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY \
			and (m as Node).get_parent() == desk.world
	check("  the still pieces: %d joined into %d meshes by look, none lit by more than %d lamps (a renderer drops the rest), on a phone (lamps out) %d"
		% [desk.still_joined, joins.size(), Run.LIGHTS_EACH, phone_joins],
		desk.still_joined > 600 and joins.size() > 20 and joins.size() < 120 and most_lamps <= Run.LIGHTS_EACH
		and phone_joins > 0 and phone_joins < joins.size(), [desk.still_joined, joins.size(), most_lamps, phone_joins])
	check("  the plain pieces' shadows are %d meshes of their own, drawn only as shadow; the pieces cast none; a phone (no shadows) makes none"
		% desk.shadow_meshes.size(), desk.shadow_meshes.size() > 0 and desk.shadow_meshes.size() <= 12 and only_shadow
		and casting == 0 and phone_shadow_meshes == 0, [desk.shadow_meshes.size(), only_shadow, casting, phone_shadow_meshes])
	# a picture's words wait for its end and are written alike together
	var f1: Font = desk._bold
	var kinds: Dictionary = Run._word_kinds([[f1, 16, 3, Vector2.ZERO, "RAMP", Color.WHITE, 1.0],
		[f1, 20, 0, Vector2.ZERO, "W", Color.WHITE, 1.0], [f1, 16, 3, Vector2.ZERO, "ORBIT", Color.WHITE, 1.0]])
	desk._hold_words = true
	desk._text(Vector2(10, 10), "HELD", 14, Color.WHITE)
	var waiting: int = desk._held_words.size()
	desk._hold_words = false
	desk._held_words = []
	check("  a picture's words wait for its end, then are written alike together, each kind in the order its first was asked for",
		waiting == 1 and kinds.keys() == [[f1, 16, 3], [f1, 20, 0]] and (kinds[[f1, 16, 3]] as Array).size() == 2,
		[waiting, kinds.keys()])
	desk_holder.queue_free()
	var under := CanvasLayer.new()
	under.layer = 3
	add_child(under)
	var above := CanvasLayer.new()
	above.layer = 120
	add_child(above)
	var screen = Screen.new()
	screen.set("headless_run", true)
	screen.set("on_touch", func() -> bool: return true)
	add_child(screen)
	check("the layers under the screen (the HUD) are not drawn while it is up; those over it are",
		not under.visible and above.visible, [under.visible, above.visible])
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
	screen.close()
	check("  closed, they are drawn again", under.visible and above.visible)
	under.queue_free()
	above.queue_free()
	print("  the table on a phone: done")


func _test_the_wind_is_an_updraft() -> void:
	section("The wind land is an updraft: the ball hangs, never pushed sideways (0.168.3)")
	# The owner: "the wind i think need to change it keep blowing the ball
	# into the gutter" - the gale (0.168.0, halved and stilled over the
	# flippers) still sent 22 of 150 balls down the outlane on its side. He
	# chose an updraft.
	var Run = require_script("res://src/world/pinball/pinballrun.gd", "pinballrun.gd")
	if Run == null:
		return
	var fall := func(windy: bool, from_v: Vector2, frames: int) -> Vector2:
		var run = Run.new()
		run.headless = true
		run.seed_now = 7
		add_child(run)
		run.next_effect = 1e9
		if windy:
			run.effect = {"land": "wind", "warn": run.t - 3.0, "from": run.t - 2.0, "to": run.t + 60.0, "begun": true}
		var ball: Dictionary = run.balls[0]
		ball["held"] = false
		ball["p"] = Vector2(600, 2700)
		ball["v"] = from_v
		run.step_frames(frames)
		var v: Vector2 = ball["v"]
		run.queue_free()
		return v
	var still: Vector2 = fall.call(false, Vector2.ZERO, 20)
	var up: Vector2 = fall.call(true, Vector2.ZERO, 20)
	check("in the updraft a ball from rest falls slower than in still air (%.0f px/s against %.0f)" % [up.y, still.y],
		up.y > 0.0 and up.y < still.y * (1.0 - Run.UPDRAFT_LIFT) + 20.0, [up, still])
	check("  and is pushed no way sideways", absf(up.x) < 0.5, up)
	var fast: Vector2 = fall.call(true, Vector2(0, 1800), 30)
	var fast_still: Vector2 = fall.call(false, Vector2(0, 1800), 30)
	check("  a fast fall is eased toward %d px/s" % int(Run.UPDRAFT_FALL),
		fast.y < 1300.0 and fast.y < fast_still.y - 400.0, [fast, fast_still])
	check("  its banner says UPDRAFT, and there is no gale left to push",
		str(Run.EFFECT["wind"]) == "UPDRAFT" and str(Run.EFFECT_SUB["wind"]).ends_with("THE BALL HANGS")
		and not (Run as GDScript).get_script_property_list().any(func(prop: Dictionary) -> bool: return prop["name"] == "wind_dir"))
	print("  the wind is an updraft")


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
	section("The table opens quicker, and its kickbacks moved up the side walls (0.168.2, higher 0.168.3)")
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
	# up while that side's KICK is lit, spending it; dark, it rolls in. Since
	# 0.168.3 the catcher is the wall's whole lower part, so it is caught
	# above the outlane's mouth (y 3215), and a gentle roll down it counts too
	for lit in [true, false]:
		var run = Run.new()
		run.headless = true
		run.seed_now = 7
		add_child(run)
		run.save_until = -100.0
		run.next_effect = 1e9
		run.kickbacks = [false, lit]
		var ball: Dictionary = run.balls[0]
		ball["held"] = false
		ball["p"] = Vector2(1140, 3010)
		ball["v"] = Vector2(-380, 300)
		var kicked_at := -1
		var top_after := 99999.0
		var lowest := 0.0
		for i in 150:
			run.step_frames(1)
			var y: float = (ball["p"] as Vector2).y
			lowest = maxf(lowest, y)
			if kicked_at < 0 and not bool(run.kickbacks[1]) and lit:
				kicked_at = i
			if kicked_at >= 0:
				top_after = minf(top_after, y)
		if lit:
			check("  lit, a ball down the right side wall is caught above the outlane, thrown back up the table, the KICK spent",
				run.ball_no == 1 and kicked_at >= 0 and lowest < 3215.0 and top_after < 2950.0
				and run.kickbacks == [false, false] and int(run.stats["kickbacks"]) == 1,
				[ball["p"], lowest, top_after, run.ball_no, run.kickbacks])
		else:
			check("  dark, the same ball rolls on into the outlane", lowest > 3300.0 and int(run.stats["kickbacks"]) == 0,
				[ball["p"], lowest, run.ball_no])
		run.queue_free()
	var roll = Run.new()
	roll.headless = true
	roll.seed_now = 7
	add_child(roll)
	roll.save_until = -100.0
	roll.next_effect = 1e9
	roll.kickbacks = [false, true]
	var catcher: Dictionary = {}
	for sg in roll.segs:
		if sg.get("bounce", false) and int(sg.get("kb", -1)) == 1:
			catcher = sg
	var along: Vector2 = ((catcher["b"] as Vector2) - (catcher["a"] as Vector2)).normalized()
	if along.y < 0.0:
		along = -along
	var up: Vector2 = along.orthogonal()
	if up.y > 0.0:
		up = -up
	var rolling: Dictionary = roll.balls[0]
	rolling["held"] = false
	rolling["p"] = ((catcher["a"] as Vector2) + (catcher["b"] as Vector2)) / 2.0 + up * (Run.BALL_R + float(catcher["r"]) - 0.5)
	rolling["v"] = along * 60.0
	var roll_top := 99999.0
	for i in 90:
		roll.step_frames(1)
		roll_top = minf(roll_top, (rolling["p"] as Vector2).y)
	check("  lit, a ball rolling gently down it is thrown back too (a slingshot needs a 110 px/s hit)",
		roll.kickbacks == [false, false] and roll_top < 2950.0, [roll.kickbacks, roll_top, catcher.get("a"), catcher.get("b")])
	# THE PRONGS (0.168.4): "we need to add prongs on both of these corners
	# its to easy for the ball to fall down" - from each catcher's foot over
	# the outlane's mouth, leaving one ball and a half beside the inlane post
	var gaps: Array = []
	var yb: float = 3600.0
	for side in [1.0, -1.0]:
		var at := func(x: float) -> float: return x if side > 0.0 else roll._mx(x)
		var corner := Vector2(at.call(270.0), yb - Run.BOUNCE_TO_Y)
		var tip := Vector2(at.call(Run.PRONG_TIP.x), yb - Run.PRONG_TIP.y)
		var found := false
		for sg in roll.segs:
			if (sg["a"] as Vector2).is_equal_approx(corner) and (sg["b"] as Vector2).is_equal_approx(tip):
				found = true
		var post := Vector2(at.call(330.0), yb - 360.0)
		gaps.append((tip.distance_to(post) - 6.0) / (Run.BALL_R * 2.0) if found else -1.0)
	check("  a prong over each outlane's mouth, leaving %.2f and %.2f balls' width beside the inlane post (it was 3)" % gaps,
		gaps.all(func(g: float) -> bool: return g > 1.1 and g < 2.0), gaps)
	roll.queue_free()
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


func _test_the_table_loads_behind_a_cover() -> void:
	section("The table opens on a loading cover, then 3, 2, 1, GO (0.168.3)")
	# The owner, on his phone: "it still takes to long to start the game up
	# if needed we can improvise with a loading screen or a countdown".
	var Screen = require_script("res://src/world/pinball/pinballscreen.gd", "pinballscreen.gd")
	if Screen == null:
		return
	var src: String = FileAccess.get_file_as_string("res://src/world/pinball/pinballscreen.gd")
	check("the screen does not preload the table's script: the cover loads it",
		not src.contains("preload(\"res://src/world/pinball/pinballrun.gd\")"))
	var screen = Screen.new()
	screen.set("on_touch", func() -> bool: return false)
	add_child(screen)
	var at_once: Array = [screen.loading.visible, screen.loading_now(), screen.run == null, screen.leave_button.visible,
		screen.load_words.text]
	screen._input(_pin_key(KEY_SPACE, true))
	screen._input(_pin_key(KEY_ESCAPE, true))
	check("Go opens the cover at once, before the table is built; keys wait (no Again, no Leave)",
		at_once == [true, true, true, false, "Opening the table..."] and not screen.results.visible
		and not screen.is_queued_for_deletion(), at_once)
	var said: Array = []
	for i in 40:
		if screen.loading_now() and not said.has(str(screen.load_words.text)):
			said.append(str(screen.load_words.text))
		if not screen.loading_now():
			break
		await get_tree().process_frame
	var r = screen.run
	check("  a step a frame, each said, then the table built behind it and held",
		said == ["Opening the table...", "Setting the table...", "Building the board...", "Lighting it..."]
		and r != null and r.world != null and bool(r.paused) and screen.counting() and screen.leave_button.visible, said)
	var three: String = screen.count_label.text
	screen._process(Screen.COUNT_STEP * 3.0 + 0.01)
	var go: String = screen.count_label.text
	var moving: bool = not bool(r.paused)
	screen._process(Screen.GO_SECONDS)
	check("  then 3, 2, 1 over the table, GO!, and the ball is the player's",
		three == "3" and go == "GO!" and moving and not screen.count_label.visible and not screen.counting()
		and not screen.loading.visible, [three, go, moving])
	await screen.again()
	check("Again: a new table behind the cover the same way", screen.loading_now() and screen.load_words.text == "A new table..."
		and screen.run == null, [screen.loading_now(), screen.load_words.text])
	screen.close()
	await get_tree().process_frame
	print("  the table loads behind a cover: done")


func _test_the_ball_floats_on_the_tide() -> void:
	section("High tide: the ball is lighter than water (0.168.4)")
	# The owner: "with the water i want to pretend the ball is lighter then
	# water". It was lifted by 0.55 of gravity, and sank slowly.
	var Run = require_script("res://src/world/pinball/pinballrun.gd", "pinballrun.gd")
	if Run == null:
		return
	var tide := func(from: Vector2, v: Vector2) -> Node:
		var run = Run.new()
		run.headless = true
		run.seed_now = 7
		add_child(run)
		run.save_until = -100.0
		run.next_effect = 1e9
		run.effect = {"land": "water", "warn": run.t - 3.0, "from": run.t - 2.0, "to": run.t + 30.0, "begun": true}
		var ball: Dictionary = run.balls[0]
		ball["held"] = false
		ball["p"] = from
		ball["v"] = v
		return run
	var run = tide.call(Vector2(500, 3250), Vector2.ZERO)
	var ball: Dictionary = run.balls[0]
	var surface: float = run._tide_y(0)
	run.step_frames(150)
	var off: float = (ball["p"] as Vector2).y - run._surface_at((ball["p"] as Vector2).x, 0)
	check("a ball under the tide rises to its surface and rides it (%.0f px off it, the surface at %.0f)" % [off, surface],
		surface < 3200.0 and absf(off) < 12.0, [ball["p"], off])
	var low := -99999.0
	var high := 99999.0
	for i in 90:
		run.step_frames(1)
		low = maxf(low, (ball["p"] as Vector2).y)
		high = minf(high, (ball["p"] as Vector2).y)
	check("  it bobs on the waves, and is never nudged as stuck", low - high > 2.0 and int(run.stats["nudges"]) == 0,
		[low - high, run.stats["nudges"]])
	run.effect["to"] = run.t + 0.1
	run.step_frames(80)
	check("  and comes down as the tide goes out", (ball["p"] as Vector2).y > surface + 120.0, ball["p"])
	run.queue_free()
	var dive = tide.call(Vector2(500, 2950), Vector2(0, 1500))
	var dball: Dictionary = dive.balls[0]
	var deepest := 0.0
	for i in 240:
		dive.step_frames(1)
		deepest = maxf(deepest, (dball["p"] as Vector2).y)
	var doff: float = (dball["p"] as Vector2).y - dive._surface_at((dball["p"] as Vector2).x, 0)
	check("a ball falling in at 1,500 px/s dives (to %.0f), is slowed, and comes back up to float" % deepest,
		dive.ball_no == 1 and absf(doff) < 12.0 and deepest > surface, [dball["p"], doff, deepest, dive.ball_no])
	dive.queue_free()
	print("  the ball floats on the tide")


func _test_the_camera_leans_toward_a_wall() -> void:
	section("The camera eases a little sideways toward a ball near a wall (0.168.5)")
	# The owner: "viewpoint still needs to be a little wider i need to see the
	# ball on the right side" - a ball on the plunger was drawn at x 1,080,
	# under the panel.
	var Run = require_script("res://src/world/pinball/pinballrun.gd", "pinballrun.gd")
	if Run == null:
		return
	var holder := SubViewport.new()
	holder.size = Vector2i(1280, 720)
	add_child(holder)
	var run = Run.new()
	run.seed_now = 7
	holder.add_child(run)
	var ball: Dictionary = run.balls[0]
	var screen_x := func(p: Vector2, held: bool) -> float:
		ball["p"] = p
		ball["held"] = held
		ball["v"] = Vector2.ZERO
		run._follow(true)
		return run.cam3.unproject_position(run._w(p, run._ball_height(ball))).x
	var plunger: float = screen_x.call(Vector2(1200, 3571), true)
	var right_wall: float = run.cam3.unproject_position(run._w(Vector2(1240, 3400))).x
	var middle_pan: float = 0.0
	screen_x.call(Vector2(700, 3300), false)
	middle_pan = run.cam_x - Run.CX
	var left: float = screen_x.call(Vector2(60, 3300), false)
	check("a ball on the plunger is in view, clear of the LAUNCH bar (x %d, the right wall %d, the bar at %d), at %d degrees"
		% [int(plunger), int(right_wall), int(Run.LAUNCH_BOX.position.x), int(Run.CAM_FOV)],
		plunger < Run.LAUNCH_BOX.position.x - 60.0 and right_wall < Run.LAUNCH_BOX.position.x and Run.CAM_FOV > 56.0,
		[plunger, right_wall])
	check("  one by the left wall too (x %d); a ball near the middle moves it not at all" % int(left),
		left > 40.0 and is_zero_approx(middle_pan), [left, middle_pan])
	ball["p"] = Vector2(1200, 3300)
	ball["held"] = false
	run.cam_x = Run.CX
	run._follow(false, 1.0 / 60.0)
	var one_frame: float = run.cam_x - Run.CX
	check("  and it eases there (%.1f px of %d in a frame), never jumps - a camera chasing every move was \"a little wobbly\""
		% [one_frame, int(Run.PAN_RIGHT)], one_frame > 0.0 and one_frame < Run.PAN_RIGHT * 0.1, one_frame)
	holder.queue_free()
	print("  the camera leans toward a wall")


func _test_the_crownfall_map_is_neater() -> void:
	section("Crownfall's map screen: a card for the map, locks and progress, quicker to open (0.168.6)")
	# The owner: "we need to improve this screen".
	var Run = require_script("res://src/world/crownfall/crownfallrun.gd", "crownfallrun.gd")
	var Screen = require_script("res://src/world/crownfall/crownfallscreen.gd", "crownfallscreen.gd")
	var Healer = require_script("res://src/world/healerrun/healerrunscreen.gd", "healerrunscreen.gd")
	if Run == null or Screen == null or Healer == null:
		return
	var view := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var slots_in: bool = true
	var run = Run.new()
	add_child(run)
	run.call("show_kingdoms", 8)
	for slot in 25:
		var p: Vector2 = run.slot_spot(slot)
		var boss: bool = (slot + 1) % 5 == 0
		var half: Vector2 = Run.TILE / 2.0
		var up: float = half.y + 9.0 if boss else half.y
		if not Rect2(Run.MAP_PANEL.position + Vector2(0, 40), Run.MAP_PANEL.size - Vector2(0, 40)).grow(-1.0).encloses(
				Rect2(p - Vector2(half.x, up), Vector2(half.x * 2.0, up + half.y + 8.0))):
			slots_in = false
	var labels_clear: bool = true
	for i in 7:
		if run.kingdom_spot(i).y + 84.0 > Run.MAP_PANEL.position.y:
			labels_clear = false
	check("the map's panel and its card side by side on the screen, Start inside the card, every map's dot inside the panel, the kingdoms' words above it",
		view.encloses(Run.MAP_PANEL) and view.encloses(Run.MAP_CARD) and not Run.MAP_PANEL.intersects(Run.MAP_CARD)
		and Run.MAP_CARD.encloses(Screen.START_BOX) and slots_in and labels_clear)
	check("  eight cleared: the Light says 8 of 25 and is open, the Wind is locked",
		run.kingdom_cleared(0) == 8 and not run.kingdom_locked(0) and run.kingdom_locked(1), [run.kingdom_cleared(0), run.kingdom_locked(1)])
	# THE MAPS' PICTURES: every letter any map uses is known to the tiles
	var unknown: Array = []
	for m in Run.Maps.MAPS:
		for line in m["rows"]:
			for letter in str(line):
				if letter != "." and letter != "R" and not Run.LAND_OF.has(letter) and not Run.MIXED.has(letter) \
						and not Run.THUMB_KIND.has(letter) and not unknown.has(letter):
					unknown.append(letter)
	var pic: ImageTexture = run.map_picture(8)
	var rows: Array = Run.Maps.MAPS[8]["rows"]
	check("  each map's tile is a picture of it, a pixel a brick (map 9 is %dx%d), knowing every letter the maps use" % [pic.get_width(), pic.get_height()],
		unknown.is_empty() and pic.get_height() == rows.size() and pic.get_width() == str(rows[0]).length()
		and run.map_picture(8) == pic, unknown)
	var corner: Vector2 = run.map_spot(8) + Run.TILE / 2.0 - Vector2(3, 3)
	check("  a tap anywhere on a tile picks its map", run.pick_at(corner) == 8 and run.pick_at(run.map_spot(8)) == 8, run.pick_at(corner))
	# THE RULERS ON THE CRESTS: one looked up a frame, then each shaded
	for i in 9:
		run._process(1.0 / 60.0)
	var rulers: Array = []
	for i in 7:
		rulers.append(str(run.ruler_of(i).get("enemy", "")))
	var light_art: Sprite2D = run._crest_sprites[0]
	var wind_art: Sprite2D = run._crest_sprites[1]
	check_needs_pack("  each crest shows its crowned ruler from its own art (%s): the Light's in its colours, the Wind's a shadow without its recolour"
		% ", ".join(rulers),
		not rulers.has("") and run._crest_sprites.all(func(a: Variant) -> bool: return a != null)
		and light_art.position.distance_to(run.kingdom_spot(0)) < 4.0 and light_art.modulate.v > 0.5
		and wind_art.material == null and wind_art.modulate.v < 0.1, [rulers, run._crest_sprites])
	run.queue_free()
	var src: String = FileAccess.get_file_as_string("res://src/world/crownfall/crownfallscreen.gd")
	var same: bool = true
	for c in [[1200, 0], [0, 500], [700, 300], [0, 0]]:
		if Screen.paid_line("Crownfall", c[0], c[1]) != Healer.paid_line("Crownfall", c[0], c[1]):
			same = false
	check("it opens without loading the Healer's Run, saying the same paid line",
		not src.contains("healerrunscreen.gd\")") and same)
	print("  Crownfall's map screen: done")


# =============================================================================
# LEAVING NEVER TRAPS (0.168.8)
# =============================================================================
# The owner, on Crownfall's results: "issue trying to leave the game". Every
# paying screen called any answer but a payment "Could not reach the server",
# and Leave only asked again - a no that would always be no kept the screen up
# for good. payanswer.gd words the answer and says when to go without.

func _test_leaving_never_traps() -> void:
	section("Leaving a minigame never traps you (0.168.8): the server's answer in words, and a way out")
	const Pay := preload("res://src/ui/minigames/payanswer.gd")
	var Screen = require_script("res://src/world/crownfall/crownfallscreen.gd", "crownfallscreen.gd")
	var Table = require_script("res://src/world/pinball/pinballscreen.gd", "pinballscreen.gd")
	if Screen == null or Table == null:
		return
	check("the answer in words - no answer, signed out, busy, broken, the server's reason - and only a 4xx (not 408 or 429) is a no for good",
		Pay.why_not({"ok": false, "status": 0}) == "No answer from the server."
		and Pay.why_not({"ok": false, "status": 401}).contains("signed out")
		and Pay.why_not({"ok": false, "status": 429}).contains("busy")
		and Pay.why_not({"ok": false, "status": 502}).contains("problem")
		and Pay.why_not({"ok": false, "status": 400, "data": {"message": "that map is not open to you yet"}})
			== "The server would not pay this run: that map is not open to you yet"
		and Pay.refused({"status": 404}) and Pay.refused({"status": 401}) and not Pay.refused({"status": 0})
		and not Pay.refused({"status": 429}) and not Pay.refused({"status": 503}))
	var hud_script := GDScript.new()
	hud_script.source_code = "extends Node\nvar said: Array = []\nfunc _push_message(text, _colour = null, _at = 0, _log = false) -> void:\n\tsaid.append(str(text))\n"
	hud_script.reload()
	var hud := Node.new()
	hud.set_script(hud_script)
	add_child(hud)
	# a refusal, on Crownfall: said in the server's words; Leave again goes
	var asked: Array = []
	var screen: CanvasLayer = Screen.new()
	screen.set("hud", hud)
	screen.set("pays", {"maps": [600, 600, 700, 800, 2000]})
	screen.set("progress", 1)
	screen.set("run_id", 9)
	screen.set("on_touch", func() -> bool: return false)
	screen.set("finish_request", func(_p: String, _b: Dictionary, _t: float = 0.0) -> Dictionary:
		asked.append(1)
		return {"ok": false, "status": 404, "data": {"message": "No such run."}})
	add_child(screen)
	await get_tree().process_frame
	var srun: Node2D = screen.get("run")
	srun.set("running_by_clock", false)
	srun.call("begin", 0)
	srun.set("cleared", 1)
	await screen.call("leave")
	var stayed: bool = is_instance_valid(screen) and not screen.is_queued_for_deletion()
	var said: String = str((screen.get("result_line") as Label).text)
	var next: String = str((screen.get("gold_line") as Label).text)
	await screen.call("leave")
	check("a run the server will not pay (Crownfall, 600 gold reached): the screen says why in its words; Leave again goes without it, asked once, the HUD told",
		stayed and said == "The server would not pay this run: No such run." and next == "Leave again to go without its gold."
		and screen.is_queued_for_deletion() and asked.size() == 1
		and (hud.get("said") as Array).has("Crownfall: this run's gold was not paid. The server would not pay this run: No such run."),
		[stayed, said, next, asked.size(), hud.get("said")])
	# no answer, on the Beholder's Table: once more, then go without
	var tries: Array = []
	var table: CanvasLayer = Table.new()
	table.set("headless_run", true)
	table.set("on_touch", func() -> bool: return false)
	table.set("hud", hud)
	table.run_id = 50
	table.pays = {"points_per_gold": 2000, "most": 3000}
	table.finish_request = func(_p: String, _b: Dictionary, _t: float = 0.0) -> Dictionary:
		tries.append(1)
		return {"ok": false, "status": 0}
	add_child(table)
	table.run.score = 40000
	await table.leave()
	var first: String = str(table.gold_line.text)
	await table.leave()
	var second: String = str(table.gold_line.text)
	var still: bool = not table.is_queued_for_deletion()
	await table.leave()
	check("no answer (the Beholder's Table, 20 gold reached): Leave tries once more; after the second it says Leave goes without it, and the third goes - asked twice",
		first == "Your gold is waiting: Leave again to try once more." and second == "Leave again to go without its gold."
		and still and table.is_queued_for_deletion() and tries.size() == 2, [first, second, still, tries.size()])
	# worth nothing: out at once
	var empty: CanvasLayer = Table.new()
	empty.set("headless_run", true)
	empty.set("on_touch", func() -> bool: return false)
	empty.run_id = 51
	empty.pays = {"points_per_gold": 2000, "most": 3000}
	empty.finish_request = func(_p: String, _b: Dictionary, _t: float = 0.0) -> Dictionary:
		return {"ok": false, "status": 0}
	add_child(empty)
	await empty.leave()
	check("  a run worth nothing leaves at once when the server cannot be reached - nothing to lose",
		empty.is_queued_for_deletion())
	var four: bool = true
	for path in ["res://src/world/healerrun/healerrunscreen.gd", "res://src/world/cloth/clothscreen.gd",
			"res://src/world/crownfall/crownfallscreen.gd", "res://src/world/pinball/pinballscreen.gd"]:
		var src: String = _code_src(path)
		four = four and src.contains("PayAnswer.refused(res) or _pay_fails >= 2") and src.contains("_go_without")
	check("  all four paying screens work the same way (the Healer's Run, Cut the Cloth, Crownfall, the Beholder's Table)", four)
	hud.queue_free()
	await get_tree().process_frame
	print("  leaving never traps: done")


# =============================================================================
# CROWNFALL LIGHTER STILL (0.168.8)
# =============================================================================
# The owner: "my pc is running hard here too". Keys of the Keep drew 523
# draws a frame, 254 of them the bars; a map's bricks were all painted in
# its first frame; a popping word was drawn at a new font size each frame.

func _test_crownfall_lighter_still() -> void:
	section("Crownfall lighter still (0.168.8): the bars and the stars pictures, a map painted a few bricks at a time, words pop by scale")
	const Run := preload("res://src/world/crownfall/crownfallrun.gd")
	var run: Node2D = Run.new()
	run.set("running_by_clock", false)
	add_child(run)
	run.begin(0)
	var src: String = _code_src("res://src/world/crownfall/crownfallrun.gd")
	var own: String = _func_body(src, "func _draw() -> void:")
	var floor_src: String = _func_body(src, "func _paint_floor() -> void:")
	var premult: bool = run.panel_pic.material is CanvasItemMaterial \
		and (run.panel_pic.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	check("the bars are a picture over the run's own drawing (where they were drawn, last), the stars one behind the floor",
		run.panel_pic.texture == run.panel_cache.get_texture() and not run.panel_pic.show_behind_parent and premult
		and run.panel_node.get_parent() == run.panel_cache and run.panel_pic.get_index() > run.brick_live.get_index()
		and run.stars_pic.show_behind_parent and run.stars_pic.get_index() < run.floor_layer.get_index()
		and run.stars_pic.texture == run.stars_cache.get_texture()
		and not own.contains("_draw_hud()") and not own.contains("_draw_left_panel()") and not floor_src.contains("_draw_backdrop"),
		[premult, run.panel_pic.get_index(), run.stars_pic.get_index()])
	var now: float = Time.get_ticks_msec() / 1000.0
	run._panels_at = now
	run._stars_at = now
	run.panel_cache.render_target_update_mode = SubViewport.UPDATE_DISABLED
	run.stars_cache.render_target_update_mode = SubViewport.UPDATE_DISABLED
	run._paint_pictures()
	var quiet: bool = run.panel_cache.render_target_update_mode == SubViewport.UPDATE_DISABLED \
		and run.stars_cache.render_target_update_mode == SubViewport.UPDATE_DISABLED
	run._panels_at = now - 1.0 / Run.PANEL_HZ
	run._paint_pictures()
	var bars_due: bool = run.panel_cache.render_target_update_mode == SubViewport.UPDATE_ONCE \
		and run.stars_cache.render_target_update_mode == SubViewport.UPDATE_DISABLED
	check("  painted again when due - the bars at most %d times a second, the stars %d - and left as they are between"
		% [int(Run.PANEL_HZ), int(Run.STARS_HZ)], quiet and bars_due, [quiet, bars_due])
	# a map a few bricks at a time: the one with the most bricks
	var most: int = 0
	var most_at: int = 0
	for i in Run.Maps.made_count():
		run.begin(i)
		var n: int = run.bricks.filter(func(k: Dictionary) -> bool: return not k.has("rail")).size()
		if n > most:
			most = n
			most_at = i
	run.begin(most_at)
	run.sync_bricks()
	var painted: int = 0
	for n in run.brick_layer.get_children():
		if (n as Node2D).draw.get_connections().size() > 0:
			painted += 1
	var hidden_first: bool = not run.brick_pic.visible
	var frames: int = 1
	var rendered_early: bool = false
	while not run._unpainted.is_empty() and frames < 100:
		run.brick_cache.render_target_update_mode = SubViewport.UPDATE_DISABLED
		run.sync_bricks()
		frames += 1
		if not run._unpainted.is_empty() and run.brick_cache.render_target_update_mode == SubViewport.UPDATE_ONCE:
			rendered_early = true
	var shown: bool = run.brick_pic.visible and run.brick_cache.render_target_update_mode == SubViewport.UPDATE_ONCE
	check("a map's bricks are painted %d a frame (%d bricks, %d frames), its picture shown whole once all are in and drawn then, not before"
		% [Run.FIRST_PAINTS, most, frames], painted == mini(most, Run.FIRST_PAINTS) and hidden_first == (most > Run.FIRST_PAINTS)
		and shown and not rendered_early and frames == ceili(float(most) / Run.FIRST_PAINTS),
		[painted, hidden_first, shown, rendered_early, frames])
	run.begin(0)
	for i in 30:
		run.sync_bricks()
	var added: Dictionary = run._add(1, 0, "land", "light", 1)
	run.sync_bricks()
	var node: Node2D = added.get("node")
	check("  a brick added in play is painted at once, the picture kept on screen",
		node != null and node.draw.get_connections().size() > 0 and run.brick_pic.visible and run._unpainted.is_empty())
	var words_src: String = _func_body(src, "func _draw() -> void:")
	check("a popping word is drawn at its own size and scaled - not at a new font size each frame of its pop",
		words_src.contains("draw_set_transform(_jolt + (w[\"p\"] as Vector2), 0.0, Vector2(pop, pop))")
		and not words_src.contains("int(w[\"size\"] * pop)"))
	# the readout names a teleport, a portal and a map opening beside a spike
	var was_on: bool = PerfOverlay.visible
	PerfOverlay.visible = true
	PerfOverlay._marks_now = {}
	run._clear_map()
	var marked: bool = PerfOverlay._marks_now.has(&"map opens")
	PerfOverlay._marks_now = {}
	PerfOverlay.visible = was_on
	var letters: Array = (PerfOverlay.MARK_LETTERS as Dictionary).values()
	var unique: bool = true
	for l in letters:
		unique = unique and letters.count(l) == 1
	check("the readout names a teleport, a portal and a map opening beside a spike (\"i think the spikes were going through the teleportar\"), each its own letter",
		marked and unique and _code_src("res://src/world/teleporter.gd").contains("PerfOverlay.mark(&\"teleport\")")
		and src.contains("PerfOverlay.mark(&\"portal\")")
		and (PerfOverlay.MARK_LETTERS as Dictionary).has(&"teleport") and (PerfOverlay.MARK_LETTERS as Dictionary).has(&"portal"),
		[marked, unique])
	run.queue_free()
	await get_tree().process_frame
	print("  Crownfall lighter still: done")


func _test_cut_the_cloth_a_picture() -> void:
	section("CUT THE CLOTH A PICTURE (0.168.10): the cloth drawn once a change, shown as one picture")
	const ClothRun := preload("res://src/world/cloth/clothrun.gd")
	var run: Node2D = ClothRun.new()
	run.set("seed_value", 7)
	add_child(run)
	run.set_physics_process(false)
	await get_tree().process_frame
	var cache: SubViewport = run.board_cache
	var pic: Sprite2D = run.board_pic
	var board: Node2D = run._board
	var placed: bool = cache != null and pic != null and board.get_parent() == cache and cache.get_parent() == run \
		and pic.get_parent() == run and pic.texture == cache.get_texture() and cache.size == Vector2i(ClothRun.VIEW) \
		and not cache.transparent_bg and cache.world_2d != null and not pic.centered and pic.position == Vector2.ZERO \
		and pic.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and pic.get_index() < run._under.get_index()
	cache.render_target_update_mode = SubViewport.UPDATE_DISABLED
	run.call("_redraw_board")
	var painted: bool = cache.render_target_update_mode == SubViewport.UPDATE_ONCE
	var src: String = _code_src("res://src/world/cloth/clothrun.gd")
	var only_helper: bool = src.count("_board.queue_redraw()") == 1 and src.count("_redraw_board()") >= 9
	check("Cut the Cloth's cloth (about 1,100 draws, sent again every frame) is drawn into a picture the view's size, opaque, nearest, under the rest, painted once each time the board changes - every redraw goes through _redraw_board() (\"if any new features we added needs it feel free to measure\")",
		placed and painted and only_helper, [placed, painted, only_helper, src.count("_redraw_board()")])
	run.queue_free()
	await get_tree().process_frame
