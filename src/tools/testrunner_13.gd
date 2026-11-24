# testrunner_13.gd - part 13 of the suite (testrunner.gd says how it is
# split; part 12 passed 234 KB): _test_the_beholders_table.
extends "res://src/tools/testrunner_12.gd"

const MeshRingScript := preload("res://src/shared/meshring.gd")


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


func _test_crownfall_no_smoothing() -> void:
	section("CROWNFALL NO SMOOTHING (0.168.11): a brick never drawn out of its place")
	const Run := preload("res://src/world/crownfall/crownfallrun.gd")
	var plain := Node2D.new()
	add_child(plain)
	var smoothed: bool = plain.is_physics_interpolated()
	plain.queue_free()
	var run = Run.new()
	add_child(run)
	await get_tree().process_frame
	var twin := Node2D.new()
	run.brick_live.add_child(twin)
	check("Crownfall moves everything in _process, so the game's smoothing between physics ticks is off for the run and all under it - a brick's twin made for its first blow is drawn where it is placed, never part way from (0, 0) (\"when i hit a brick with the ball random brick flicker for a split second\")",
		smoothed and not run.is_physics_interpolated() and not run.brick_live.is_physics_interpolated()
		and not run.brick_pic.is_physics_interpolated() and not twin.is_physics_interpolated(),
		[smoothed, run.is_physics_interpolated(), twin.is_physics_interpolated()])
	run.queue_free()
	await get_tree().process_frame


func _test_a_wide_screen_fills() -> void:
	section("A WIDE SCREEN FILLS (0.168.12): a computer keeps the height, a menu stays 16:9 in the middle, pinball's words stay on its table")
	check("a computer keeps the game's height as a phone does - a 21:9 screen shows more world, no black bars (\"start that test\", the owner's 3440 x 1440)",
		Settings.aspect_for(false) == Window.CONTENT_SCALE_ASPECT_KEEP_HEIGHT)
	const WideFit := preload("res://src/ui/menus/widefit.gd")
	const PinScreen := preload("res://src/world/pinball/pinballscreen.gd")
	var seen: Array = []
	for w in [1720, 1280]:
		var view := SubViewport.new()
		view.size = Vector2i(w, 720)
		add_child(view)
		var menu := Control.new()
		menu.set_anchors_preset(Control.PRESET_FULL_RECT)
		view.add_child(menu)
		var art := ColorRect.new()
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		menu.add_child(art)
		var back = WideFit.new()
		menu.add_child(back)
		var holder := Control.new()
		holder.set_anchors_preset(Control.PRESET_FULL_RECT)
		view.add_child(holder)
		var pin = PinScreen.new()
		var frame: Control = pin._framed(holder)
		await get_tree().process_frame
		await get_tree().process_frame
		seen.append([menu.get_global_rect(), (back as Control).get_global_rect(), back.get_index(), frame.get_global_rect()])
		pin.free()
		view.queue_free()
	await get_tree().process_frame
	var wide: Array = seen[0]
	var plain: Array = seen[1]
	check("  a menu with art (the login, the character choice, game over) is laid out at 1280 x 720 in the middle of a wider screen, a dark backdrop behind it to the edges - at 16:9 it fills the screen as always",
		wide[0] == Rect2(220, 0, 1280, 720) and wide[1] == Rect2(0, 0, 1720, 720) and int(wide[2]) == 0
		and plain[0] == Rect2(0, 0, 1280, 720) and plain[1] == Rect2(0, 0, 1280, 720), [wide, plain])
	var src_login: String = _code_src("res://src/ui/menus/loginmenu.gd")
	var all_three: bool = true
	for f in ["loginmenu", "characterselect", "gameover"]:
		all_three = all_three and _func_body(_code_src("res://src/ui/menus/%s.gd" % f), "func _ready(").contains("add_child(WideFit.new())")
	check("  the login, the character choice and game over each add it", all_three and src_login.contains('preload("res://src/ui/menus/widefit.gd")'))
	var pin_src: String = _code_src("res://src/world/pinball/pinballscreen.gd")
	check("  pinball's frame is its table's picture, 16:9 in the middle (220 to 1500 on 1720) - Leave, the hints and the 3-2-1 placed in it, the cover's words in their own",
		wide[3] == Rect2(220, 0, 1280, 720) and plain[3] == Rect2(0, 0, 1280, 720)
		and pin_src.contains("frame.add_child(leave_button)") and pin_src.contains("frame.add_child(count_label)")
		and _func_body(pin_src, "func _hint(").contains("frame.add_child(label)") and pin_src.contains("on_cover.add_child(title)"),
		[wide[3], plain[3]])


func _test_on_the_way_in() -> void:
	section("ON THE WAY IN (0.168.13): a card while the characters load, the game in front, the door's fade")
	var menu: Control = (load("res://scene/ui/menus/loginmenu.tscn") as PackedScene).instantiate() as Control
	menu.set("talks_to_server", false)
	add_child(menu)
	await get_tree().process_frame
	menu.call("_show_entering", "Tunacan")
	var card: Control = menu.get("entering_form")
	var login: Control = menu.get("login_form")
	var title: Label = menu.get("_entering_title")
	var shown: bool = card != null and card.visible and login != null and not login.visible \
		and title != null and title.text == "Welcome, Tunacan"
	menu.call("_show_load_failed")
	var back: bool = not card.visible and login.visible
	check("signed in, the form gives way to a card - \"Welcome, NAME\", \"Loading your heroes...\", a moving bar - and a load that fails brings the form back (\"a small loading screen or something to take you directly there would be nice\")",
		shown and back, [shown, back])
	var src: String = _code_src("res://src/ui/menus/loginmenu.gd")
	var complete: String = _func_body(src, "func _complete_login(")
	check("  the card shows before the characters are asked for, and character select comes through the door's fade (SceneTransition)",
		complete.find("_show_entering(") != -1 and complete.find("_show_entering(") < complete.find("await CharacterData.load_for_user(")
		and _func_body(src, "func _go_to_character_select(").contains("SceneTransition.change_scene(char_select_scene)")
		and not _func_body(src, "func _go_to_character_select(").contains("change_scene_to_packed("))
	check("  Google finished in the browser: the game comes to the front first (a computer's window; the browser build is the tab already)",
		_func_body(src, "func _google_signed_in(").find("come_forward()") != -1
		and _func_body(src, "func _google_signed_in(").find("come_forward()") < _func_body(src, "func _google_signed_in(").find("Api.adopt_login(")
		and _func_body(src, "static func come_forward(").contains("window_move_to_foreground()")
		and _func_body(src, "static func come_forward(").contains("OS.has_feature(\"web\")"))
	menu.queue_free()
	# the town the login prefetches, settled (see _test_google_sign_in)
	var settle_until: int = Time.get_ticks_msec() + 20000
	while (not AreaRegistry._prefetching.is_empty() or not AreaRegistry._prefetch_queue.is_empty()) \
			and Time.get_ticks_msec() < settle_until:
		await get_tree().process_frame


func _test_the_bag_matches_the_hud() -> void:
	section("THE BAG MATCHES THE HUD (0.168.13): as wide as the hotbar, its grid centred, no empty band")
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	var hotbar: Control = hud.get_node("%hotbar") as Control
	var bag: Control = (load("res://scene/ui/inventory/inventory.tscn") as PackedScene).instantiate() as Control
	var gear: Control = (load("res://scene/ui/equipment/equipmentpanel.tscn") as PackedScene).instantiate() as Control
	check("the bag is as wide as the hotbar and lines up with its right edge (\"the inventory is smaller then the hudscreen\")",
		is_equal_approx(bag.anchor_left, 1.0) and is_equal_approx(bag.anchor_right, 1.0)
		and is_equal_approx(bag.offset_left, hotbar.offset_left) and is_equal_approx(bag.offset_right, hotbar.offset_right),
		[bag.offset_left, bag.offset_right, hotbar.offset_left, hotbar.offset_right])
	check("  the Gear window still sits beside it, not over it",
		is_equal_approx(gear.anchor_right, 1.0) and gear.offset_right <= bag.offset_left - 4.0, [gear.offset_right, bag.offset_left])
	check("  the bag ends above the hotbar", bag.offset_bottom < 720.0 + hotbar.offset_top, [bag.offset_bottom, hotbar.offset_top])
	var view := SubViewport.new()
	view.size = Vector2i(1280, 720)
	add_child(view)
	view.add_child(bag)
	await get_tree().process_frame
	await get_tree().process_frame
	var grid: Control = bag.get_node("%inventorycontainer") as Control
	var column: Control = bag.get_node("mainpanel/margincontainer/vboxcontainer") as Control
	var left: float = grid.get_global_rect().position.x - column.get_global_rect().position.x
	var right: float = column.get_global_rect().end.x - grid.get_global_rect().end.x
	var slot: Control = grid.get_child(0) as Control
	var icon: Control = slot.get_node("centercontainer/icon") as Control
	check("  the grid is centred (as much room each side), its slots 72 with the art at 3x (48), the one slot scene",
		absf(left - right) <= 1.0 and slot.custom_minimum_size == Vector2(72, 72) and icon.custom_minimum_size == Vector2(48, 48)
		and not FileAccess.get_file_as_string("res://scene/ui/inventory/inventory.tscn").contains("inventory_slot_scene"),
		[left, right, slot.custom_minimum_size])
	var header_spacer: Control = bag.find_child("headerspacer", true, false) as Control
	var close: Control = bag.get_node("%closebutton") as Control
	var panel: Control = bag.get_node("mainpanel") as Control
	check("  the title is centred on the window (a spacer as wide as the close button), and the window is no taller than what it holds",
		header_spacer != null and header_spacer.get_index() == 0 and header_spacer.custom_minimum_size.x == close.custom_minimum_size.x
		and absf(bag.size.y - panel.get_combined_minimum_size().y) <= 1.0, [bag.size.y, panel.get_combined_minimum_size().y])
	var label: Label = bag.get_node("%baglabel") as Label
	bag.call("_update_bag_count")
	check("  under the grid, how full the bag is", label != null and label.text.begins_with("Bag: ") and label.text.ends_with(" / 20"),
		label.text if label != null else "no label")
	view.queue_free()
	hud.free()
	gear.free()
	await get_tree().process_frame


# THE HIGHSCORES (0.169.0). The owner: "i want a global highscore option here
# for all minigames top 10 on each", and "this will help me see if anyone
# plays my minigames". Stats > Highscores: a button a minigame, its top ten
# from GET /api/minigames/top, your place under it when you are off the ten;
# and the Endless sends its run's time, as the Forge does.
func _test_the_highscores() -> void:
	section("HIGHSCORES (0.169.0): every minigame's top ten, under Kingdom")
	const Scores := preload("res://src/ui/highscores/highscores.gd")
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	var in_stats: Array[String] = []
	for b in hud.get_node("%statsmenu").find_children("*", "Button", true, false):
		in_stats.append(str(b.name))
	var hud_code: String = _code_src("res://src/ui/characterhud.gd")
	check("Stats holds Highscores under Kingdom, wired to its window, lit while it is open, on a phone's grid too",
		in_stats == ["characterbutton", "killsbutton", "kingdombutton", "highscoresbutton"]
		and hud_code.contains("\"highscoresbutton\":        \"_on_highscores_pressed\"")
		and str(hud.get("NAV_LIT_BY").get("highscoresbutton", "")) == "highscores_panel"
		and Array(preload("res://src/ui/touchmenu.gd").ITEMS).has("highscoresbutton"), in_stats)
	hud.free()
	var window: Control = (load("res://scene/ui/highscores/highscores.tscn") as PackedScene).instantiate() as Control
	add_child(window)
	await get_tree().process_frame
	var asked: Array = []
	var now: int = int(Time.get_unix_time_from_system())
	var top: Array = []
	for i in 10:
		top.append({"place": i + 1, "name": "p%02d" % i, "value": 9000 - i * 100, "at": now - 60, "you": false})
	var answer: Dictionary = {"now": now, "boards": [
		{"id": "endless", "name": "The Endless", "counts": "seconds", "players": 0, "top": [], "you": null},
		{"id": "healerrun", "name": "The Healer's Run", "counts": "waves", "players": 2,
			"top": [{"place": 1, "name": "ann", "value": 24, "bosses": 3, "at": now, "you": false},
				{"place": 2, "name": "kt_me", "value": 20, "bosses": 1, "at": now, "you": true}],
			"you": {"place": 2, "value": 20, "bosses": 1}},
		{"id": "forge", "name": "The Forge", "counts": "seconds", "players": 1,
			"top": [{"place": 1, "name": "ann", "value": 3725, "at": now, "you": false}], "you": null},
		{"id": "cloth", "name": "Cut the Cloth", "counts": "rounds", "players": 0, "top": [], "you": null},
		{"id": "crownfall", "name": "Crownfall", "counts": "maps", "players": 1,
			"top": [{"place": 1, "name": "bob", "value": 1, "at": now, "you": false}], "you": null},
		{"id": "pinball", "name": "The Beholder's Table", "counts": "score", "players": 23, "top": top,
			"you": {"place": 23, "value": 1234567}}]}
	window.set("fetch", func(path: String) -> Dictionary:
		asked.append(path)
		return {"ok": true, "status": 200, "data": JSON.parse_string(JSON.stringify(answer))})
	var was_name: String = Api.username
	Api.username = "kt_me"
	await window.call("open")
	var buttons: Dictionary = window.get("game_buttons")
	var words: Array[String] = []
	for id in window.get("order"):
		words.append((buttons[id] as Button).text)
	check("opened, it reads every board at once, and has a button a minigame in the server's order",
		asked == ["/api/minigames/top"] and window.visible
		and words == ["The Endless", "Healer's Run", "The Forge", "Cut the Cloth", "Crownfall", "Beholder's Table"]
		and (buttons["pinball"] as Button).tooltip_text == "The Beholder's Table - 23 players", words)
	var list: VBoxContainer = window.get("list")
	var summary: Label = window.get("summary_label")
	check("  the Endless first: nobody yet, said plainly", (buttons["endless"] as Button).button_pressed
		and summary.text == "Longest run - nobody yet." and list.get_node_or_null("empty") != null, summary.text)
	window.call("show_board", "pinball")
	var first: Node = list.get_node_or_null("row_1")
	var rows: int = list.get_children().filter(func(n: Node) -> bool: return str(n.name).begins_with("row_")).size()
	var mine: Node = list.get_node_or_null("row_23")
	check("the Beholder's Table: ten rows, the first in gold, scores with commas, and how many play it (\"see if anyone plays\")",
		summary.text == "Best score - 23 players." and rows == 11 and first != null
		and (first.get_node("place") as Label).text == "1st" and (first.get_node("value") as Label).text == "9,000"
		and (first.get_node("place") as Label).get_theme_color("font_color") == Scores.PLACE_COLOURS[0], [summary.text, rows])
	check("  you, off the ten: under it, after a gap, in green, your place and score",
		list.get_node_or_null("gap") != null and mine != null and (mine.get_node("place") as Label).text == "23rd"
		and (mine.get_node("name") as Label).text == "kt_me  (you)" and (mine.get_node("value") as Label).text == "1,234,567"
		and (mine.get_node("name") as Label).get_theme_color("font_color") == Scores.YOU_COLOUR,
		(mine.get_node("name") as Label).text if mine != null else "no row")
	(buttons["healerrun"] as Button).pressed.emit()
	var you_row: Node = list.get_node_or_null("row_2")
	check("  the Healer's Run: waves and bosses; you on the ten are green there, with nothing under it",
		window.get("board_id") == "healerrun" and (list.get_node("row_1").get_node("value") as Label).text == "24 waves, 3 bosses"
		and you_row != null and (you_row.get_node("name") as Label).get_theme_color("font_color") == Scores.YOU_COLOUR
		and list.get_node_or_null("gap") == null)
	check("each board in its own words: times, waves, rounds, maps, places",
		Scores.value_text("seconds", 272) == "4:32" and Scores.value_text("seconds", 3725) == "1:02:05"
		and Scores.value_text("waves", 1) == "1 wave" and Scores.value_text("waves", 20, 1) == "20 waves, 1 boss"
		and Scores.value_text("rounds", 12) == "12 rounds" and Scores.value_text("maps", 1) == "1 map"
		and Scores.place_text(1) == "1st" and Scores.place_text(2) == "2nd" and Scores.place_text(3) == "3rd"
		and Scores.place_text(11) == "11th" and Scores.place_text(12) == "12th" and Scores.place_text(13) == "13th"
		and Scores.place_text(21) == "21st" and Scores.place_text(102) == "102nd")
	window.call("close")
	await window.call("open")
	check("  shut and opened again: read again, on the board it was on", asked.size() == 2 and window.get("board_id") == "healerrun")
	window.set("fetch", func(_path: String) -> Dictionary: return {"ok": false, "status": 404, "error": "Not Found"})
	await window.call("refresh")
	var notice: Label = window.get("notice_label")
	check("a server from before it says so", notice.visible and notice.text == "This server does not keep highscores yet.", notice.text)
	Api.username = was_name
	window.queue_free()
	# THE ENDLESS SENDS ITS TIME, as the Forge does - each run, from _end_run().
	var RunScript: GDScript = load("res://src/world/endless/endlessrun.gd") as GDScript
	var run: Node = RunScript.new()
	var posted: Array = []
	run.set("best_post", func(path: String, body: Dictionary) -> Dictionary:
		posted.append([path, body])
		return {"ok": true, "data": {"best": 272, "new_best": true}})
	await run.call("_send_time", 272.6)
	await run.call("_send_time", 0.4)
	check("the Endless sends a run's time to the server, which keeps the best; under a second, nothing",
		posted == [["/api/minigames/best", {"game": "endless", "seconds": 272}]]
		and _func_body(_code_src("res://src/world/endless/endlessrun.gd"), "func _end_run(").contains("_send_time(elapsed)"), posted)
	run.free()
	await get_tree().process_frame
	print("  a button a minigame, its top ten and your place - and the Endless's time kept")


# STAFF SAYS WHY (0.169.0). The owner: "when rolling back a account i want it
# to let the player know by counting down on their screen or a loading screen
# that says your account was rolled back", and "same with being kicked staff
# kicked you". The server's 401 says kicked or rolled_back (the API's
# _remember_ended()); the HUD puts a card over the game, counting down, then
# the sign-in screen says it again.
func _test_staff_says_why_you_were_signed_out() -> void:
	section("A KICK, A BAN AND A ROLLBACK SAY SO (0.169.0): a card, counting down, then sign in")
	var kicked := {"ok": false, "status": 401, "data": {"error": "Unauthorized", "kicked": true}}
	var rolled := {"ok": false, "status": 401, "data": {"error": "Unauthorized", "rolled_back": true}}
	var elsewhere := {"ok": false, "status": 401, "data": {"error": "Unauthorized", "signed_in_elsewhere": true}}
	check("the server's reason is the sign-in screen's line: staff signed you out, staff rolled you back",
		ApiForTests.signout_notice_for(kicked) == Api.KICKED_NOTICE
		and ApiForTests.signout_notice_for(rolled) == Api.ROLLED_BACK_NOTICE
		and ApiForTests.signout_notice_for(elsewhere) == Api.SIGNED_IN_ELSEWHERE_NOTICE
		and ApiForTests.signout_notice_for({}) == Api.SIGNED_OUT_NOTICE)
	check("  and only those two put up a card first; every other sign-out goes straight to sign in",
		str(ApiForTests.signout_card_for(rolled).get("title", "")) == "Your character was rolled back"
		and str(ApiForTests.signout_card_for(kicked).get("title", "")) == "Staff signed you out"
		and ApiForTests.signout_card_for(elsewhere).is_empty() and ApiForTests.signout_card_for({}).is_empty())
	# AND A BAN (the owner: "add one for ban and perm ban"): how long and why.
	var now: int = int(Time.get_unix_time_from_system())
	var banned := {"ok": false, "status": 401, "data": {"error": "Unauthorized", "banned": true,
		"ban": {"permanent": false, "expires_at": now + 86400 + 4 * 3600 + 30, "reason": "griefing"}}}
	var forever := {"ok": false, "status": 401, "data": {"error": "Unauthorized", "banned": true,
		"ban": {"permanent": true, "expires_at": null, "reason": "cheating"}}}
	var ban_card: Dictionary = ApiForTests.signout_card_for(banned)
	var forever_card: Dictionary = ApiForTests.signout_card_for(forever)
	check("a ban is a card too - until when, how long, and why; a permanent one says so",
		str(ban_card.get("title")) == "You were banned"
		and str(ban_card.get("line")) == "Staff banned this account for 1 day, 4 hours, until %s.\nReason: griefing" % LocalTime.stamp(now + 86400 + 4 * 3600 + 30, now)
		and ApiForTests.signout_notice_for(banned).contains("(1 day, 4 hours left).")
		and str(forever_card.get("title")) == "You were banned permanently"
		and str(forever_card.get("line")) == "Staff banned this account permanently.\nReason: cheating"
		and ApiForTests.signout_notice_for(forever) == "This account is banned permanently.\nReason: cheating"
		and ApiForTests.signout_notice_for(banned).begins_with("This account is banned until"), [ban_card, forever_card])
	check("  how long, in the largest two units that say something",
		ApiForTests.ban_left_words(3 * 86400) == "3 days" and ApiForTests.ban_left_words(86400 + 3600) == "1 day, 1 hour"
		and ApiForTests.ban_left_words(2 * 3600 + 20 * 60) == "2 hours, 20 minutes" and ApiForTests.ban_left_words(3600) == "1 hour"
		and ApiForTests.ban_left_words(40) == "1 minute" and ApiForTests.ban_left_words(0) == "")
	const Card := preload("res://src/ui/signoutcard.gd")
	var card: CanvasLayer = Card.new()
	add_child(card)
	card.call("show_card", ApiForTests.signout_card_for(rolled))
	var clock: Label = card.get("clock_label")
	var first: String = clock.text
	card.set("step_seconds", 0.0)
	await card.call("count_down")
	check("the card: what happened in a sentence, \"Back to sign in in 5...\" down to 1, over everything, running while the game is paused",
		(card.get("title_label") as Label).text == "Your character was rolled back"
		and (card.get("line_label") as Label).text.begins_with("Staff put your character back to an earlier save")
		and first == "Back to sign in in 5..." and clock.text == "Back to sign in in 1..."
		and card.layer >= 100 and card.process_mode == Node.PROCESS_MODE_ALWAYS
		and (card.get_node("dim") as Control).mouse_filter == Control.MOUSE_FILTER_STOP, [first, clock.text])
	get_tree().paused = true
	remove_child(card)
	var unpaused: bool = not get_tree().paused
	get_tree().paused = false
	card.free()
	check("  gone, it never leaves the game paused", unpaused)
	var hud_src: String = _code_src("res://src/ui/characterhud.gd")
	var signout: String = _func_body(hud_src, "func _forced_signout(")
	check("the HUD's sign-out puts the card up for a kick or a rollback, pauses under it, counts down, then signs in - once",
		signout.contains("signout_card_for(said)") and signout.contains("SignoutCard.new()")
		and signout.contains("get_tree().paused = true") and signout.find("count_down") < signout.find("change_scene_to_file")
		and signout.contains("if _signing_out:") and signout.contains("Api.forget_session(notice)"))
	print("  kicked, banned and rolled back: said by the server, shown on a card, said again at sign in")


# A BROWSER STARTS IN ITS PAGE (0.169.0). The owner: "i have to flip from
# borderless to windowed back to borderless", "it should be defaulted
# windowed". A browser goes fullscreen only from a click or a key, so a game
# saved as Borderless opened in the page while Options said Borderless.
func _test_a_browser_starts_windowed() -> void:
	section("A BROWSER STARTS WINDOWED (0.169.0): Options says what the window is")
	const S := preload("res://src/systems/settings.gd")
	check("in a browser every launch is windowed, whatever was saved; a desktop game starts as it was left",
		S.launch_window_mode("borderless", true) == "windowed" and S.launch_window_mode("exclusive", true) == "windowed"
		and S.launch_window_mode("borderless", false) == "borderless" and S.launch_window_mode(true, false) == "borderless"
		and S.launch_window_mode("windowed", false) == "windowed")
	var full: int = DisplayServer.WINDOW_MODE_FULLSCREEN
	var win: int = DisplayServer.WINDOW_MODE_WINDOWED
	check("  Esc out of the browser's fullscreen says Windowed again; into it, Borderless; nothing changed, nothing said",
		S.browser_window_mode("borderless", full, win) == "windowed"
		and S.browser_window_mode("windowed", win, full) == "borderless"
		and S.browser_window_mode("borderless", win, win) == "borderless"
		and S.browser_window_mode("windowed", full, full) == "windowed")
	var code: String = _code_src("res://src/systems/settings.gd")
	check("  the file is read through it, and a browser's watch keeps Options truthful once a second",
		_func_body(code, "func load_settings(").contains("launch_window_mode(stored, OS.has_feature(\"web\"))")
		and _func_body(code, "func _start_window_watch(").contains("_watch_browser_window")
		and _func_body(code, "func _watch_browser_window(").contains("browser_window_mode("))
	print("  a browser starts windowed; picking Borderless is the click that goes fullscreen")


# THE COFFERS AS ROWS (0.170.0). The owner: "i want us to upgrade this", and
# "im also not sure what patron douse". Where the gold came from, a row a
# source biggest first with its share behind it; your standing as rows; a line
# saying what a title is; the gifts as buttons, with no box.
func _test_the_coffers_as_rows() -> void:
	section("THE KINGDOM'S COFFERS AS ROWS (0.170.0): where it came from, and you")
	const Board := preload("res://src/ui/kingdom/kingdomboard.gd")
	var rows: Array = Board.source_rows({"kingdom_tax": 25, "death": 33097, "shop_buy": 13995, "revive": 21666})
	check("the sources, biggest first, each in the player's words",
		rows == [["Lost by the dead", 33097], ["Paid to cheat death", 21666], ["Spent with merchants", 13995], ["Trade tax", 25]], rows)
	var mine: Array = Board.you_rows({"contributed": 70021, "lusions": 40, "lost": 29021, "deaths": 85, "rank": 1}, 7,
		"THE CAN: 75,141 from 5")
	var said: Array = mine.map(func(row: Array) -> String: return "%s=%s" % [row[0], row[1]])
	check("  you: your place first, the gold, how much of it was lost, lusions, deaths, your guild - each once",
		said == ["Your place=1st of 7", "Gold you gave the realm=70,021", "  of it lost when you died=29,021", "Lusions=40",
			"Deaths=85", "Guild=THE CAN: 75,141 from 5"], said)
	var fresh: Array = Board.you_rows({"contributed": 0, "lusions": 0, "rank": null}, 7, "")
	check("  somebody who has given nothing has no place, no losses, no deaths and no guild row",
		fresh.map(func(row: Array) -> String: return str(row[0])) == ["Gold you gave the realm", "Lusions"], fresh)
	check("  a guild in words, ranked only against others; places in words",
		Board.guild_words({"tag": "THE CAN", "contributed": 75141, "members": 5, "rank": 2}, [{}, {}, {}]) == "THE CAN: 75,141 from 5 (2nd of 3)"
		and Board.guild_words({"tag": "SOLO", "contributed": 10, "members": 1, "rank": 1}, [{}]) == "SOLO: 10"
		and Board.guild_words(null, []) == "" and Board.place_words(1) == "1st" and Board.place_words(12) == "12th"
		and Board.place_words(22) == "22nd")
	var board: Control = (load("res://scene/ui/kingdom/kingdomboard.tscn") as PackedScene).instantiate() as Control
	add_child(board)
	await get_tree().process_frame
	board.call("_render", {"total": 1000, "total_deaths": 2, "contributors": 3, "by_reason": {"death": 600, "shop_buy": 400},
		"lusions_by_reason": {"revive": 5}, "total_lusions": 5,
		"you": {"username": "kt_me", "contributed": 900, "lusions": 5, "lost": 500, "deaths": 2, "rank": 1,
			"donated": 0, "next_title": "Patron", "next_at": 10000}, "top": []})
	var sources: GridContainer = board.get("sources_box")
	var first: Node = sources.get_child(0)
	var share: Control = first.get_node("share") as Control
	var you: VBoxContainer = board.get("you_grid")
	check("on the board: the sources two to a row with their share behind them, the old sentence their hover; you as rows",
		sources.columns == 2 and sources.get_child_count() == 3
		and (first.find_child("words", true, false) as Label).text.strip_edges() == "Lost by the dead"
		and is_equal_approx(float(share.get("share")), 0.6) and sources.tooltip_text.contains("lost by the dead")
		and not (board.get("breakdown_label") as Label).visible and not (board.get("you_label") as Label).visible
		and (you.get_child(0).find_child("value", true, false) as Label).text == "1st of 3" and you.tooltip_text.begins_with("You have given 900 gold")
		and (board.get("headline_label") as Label).text == "2 deaths  ·  3 subjects",
		[(board.get("headline_label") as Label).text])
	# ROOM ROUND IT (0.170.1, "screen is off upgrade it"): the panel holds its rows
	# YOU_INSET in, the rows are banded every other line, and the loss is a
	# smaller line set in under the gold.
	var frame: StyleBox = (you.get_parent().get_parent() as Control).get_theme_stylebox("panel")
	var bands: Array = you.get_children().map(func(row: Node) -> float: return ((row as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a)
	var lost_row: Node = you.get_child(2)
	check("  your panel has room inside it, its rows a ledger: a band every other line, the loss set in under the gold and smaller",
		is_equal_approx(frame.content_margin_left, Board.YOU_INSET) and is_equal_approx(frame.content_margin_right, Board.YOU_INSET)
		and bands[0] > 0.0 and bands[1] == 0.0 and bands[2] == 0.0 and bands[3] > 0.0
		and (lost_row.find_child("words", true, false) as Label).text == "of it lost when you died"
		and (lost_row.find_child("words", true, false) as Label).get_theme_font_size("font_size") < (you.get_child(1).find_child("words", true, false) as Label).get_theme_font_size("font_size")
		and ((lost_row as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left > ((you.get_child(1) as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left,
		bands)
	var hint: Label = board.get("patron_hint")
	var gifts: HBoxContainer = board.get("quick_row")
	check("  what a title is, said under the bar, every title on its hover; under it the gifts, buttons, and no box",
		hint.visible and hint.text == "Gifts earn a title under your name in the ranking."
		and hint.tooltip_text.contains("Patron - 10,000 gold given") and hint.tooltip_text.contains("Royal Patron - 10,000,000")
		and gifts.get_index() == hint.get_index() + 1 and gifts.get_child_count() == 3
		and (gifts.get_child(2) as Button).theme_type_variation == &"ButtonSocket"
		and (gifts.get_child(2) as Button).tooltip_text.contains("asks twice")
		and not (gifts.get_child(1) as Button).tooltip_text.contains("asks twice")
		and board.get("donate_input") == null and not board.has_method("_on_donate_pressed"))
	board.queue_free()
	await get_tree().process_frame
	print("  the coffers: sources and you as rows, what a title is, gifts as buttons")


# CHARACTERS TALK IN TURN (0.171.0). The owner: "we need to make a story
# scene", "i was thinking about adding the chat bubbles above characters",
# "there are 4 heros that means 4 separate chats for each char", and "the
# chat bubbles start in town then work our way out". talk.gd plays a script
# - data/story/<scene>/<class>.txt, "speaker: words" a line - in speech
# bubbles over each speaker in turn; the first is the shopkeeper's first
# meeting, a script a hero.
func _test_characters_talk_in_turn() -> void:
	section("CHARACTERS TALK IN TURN (0.171.0): a scene is a script a hero, said in bubbles over each speaker")
	const Talk := preload("res://src/shared/talk.gd")
	const Bubble := preload("res://src/shared/speechbubble.gd")
	const Keeper := preload("res://src/world/shopkeeperanim.gd")
	const HEROES := ["warrior", "mage", "tank", "healer"]
	var read: Array = Talk.read_script("# a note\n\nShopkeeper: Hello: there\r\nhero:   Hi  \nno speaker here\n: nobody\nhero:\n")
	check("a script: a line a speaker, the speaker in lower case, notes, blanks and empty lines skipped, words may hold a colon",
		read == [["shopkeeper", "Hello: there"], ["hero", "Hi"]], read)
	var parts: Array = Talk.read_parts("a: one\n---\n# only a note\n  ---  \nb: two\nb: three\n---\n")
	check("  in parts, \"---\" between them; a part with nothing said is dropped",
		parts == [[["a", "one"]], [["b", "two"], ["b", "three"]]], parts)
	# ---- the first meeting's scripts ---------------------------------------
	var scripts_ok := true
	var said_by: Array = []
	var missing: Array = []
	for hero in HEROES:
		var path: String = Talk.script_path(Keeper.MEETING, hero)
		var lines: Array = Talk.lines_for(Keeper.MEETING, hero)
		var speakers: Array = []
		for line in lines:
			if not ["?", "[", ">"].has(str(line[0])) and not speakers.has(line[0]):
				speakers.append(line[0])
		said_by.append(speakers)
		if path != "%s%s/%s.txt" % [Talk.STORY_DIR, Keeper.MEETING, hero] or lines.size() < 2 \
				or str(lines[0][0]) != "shopkeeper" or not speakers.has("hero") or speakers.size() != 2:
			scripts_ok = false
	check("each of the four heroes has its own first meeting with the shopkeeper: he speaks first, then the two of them",
		scripts_ok, said_by)
	# EVERY SCRIPT THERE IS, so one the owner writes is held too: a line it
	# cannot read, a choice to a branch that is not there or an @ it does not
	# know (talk.gd problems(), 0.172.0) would be dropped or end the
	# conversation without a word, and a letter the font lacks is a box on
	# the web.
	var dropped: Array = []
	var scripts: int = 0
	for scene in DirAccess.get_directories_at(Talk.STORY_DIR):
		for file in DirAccess.get_files_at(Talk.STORY_DIR + scene):
			if not file.ends_with(".txt"):
				continue
			scripts += 1
			var text: String = FileAccess.get_file_as_string(Talk.STORY_DIR + scene + "/" + file)
			for problem in Talk.problems(text):
				dropped.append("%s/%s: %s" % [scene, file, problem])
			for one_part in Talk.read_parts(text):
				for step in one_part:
					var words: Array = []
					if str(step[0]) == "?":
						for choice in step[1]:
							words.append(str(choice[0]))
					elif not ["[", ">"].has(str(step[0])):
						words.append(str(step[1]))
					for said in words:
						for i in said.length():
							if not ThemeDB.fallback_font.has_char(said.unicode_at(i)):
								missing.append("%s/%s: %s" % [scene, file, said[i]])
	check("  every script in data/story can be played (talk.gd problems()), and every letter is in the game's font",
		scripts >= 6 and dropped.is_empty() and missing.is_empty(), [scripts, dropped, missing])
	check("  a hero with no script, and no all.txt, has none", Talk.script_path(Keeper.MEETING, "nobody") == ""
		and Talk.lines_for(Keeper.MEETING, "nobody").is_empty())
	var presets := ConfigFile.new()
	var filters: Array = []
	if presets.load("res://export_presets.cfg") == OK:
		for preset in presets.get_sections():
			if preset.begins_with("preset.") and not preset.ends_with(".options"):
				filters.append(str(presets.get_value(preset, "include_filter", "")))
	check("  every export carries the scripts (.txt is left out unless the filter names it)",
		filters.size() >= 2 and filters.all(func(f: String) -> bool: return f.contains(Talk.STORY_FILTER)), filters)
	# ---- a conversation ----------------------------------------------------
	var holder := Node2D.new()
	add_child(holder)
	var first := Node2D.new()
	var second := Node2D.new()
	holder.add_child(first)
	holder.add_child(second)
	# Side by side: each speaks over its own head.
	second.position = Vector2(120, 0)
	var ended: Array = []
	var talk: Node = Talk.play(holder, [["a", "One."], ["ghost", "Nobody says this."], ["b", "Two, a little longer."]],
		{"a": first, "b": second})
	talk.connect("finished", func() -> void: ended.append(true))
	await get_tree().process_frame
	var bubble: Node2D = talk.get("bubble")
	check("it says the first line over its speaker, where the speaker says (or over the head by default)",
		bubble != null and bubble.get_parent() == first and bubble.get("lines") == ["One."] and bubble.position == Talk.DEFAULT_AT)
	var press := InputEventAction.new()
	press.action = "interact"
	press.pressed = true
	talk.call("_unhandled_input", press)
	var whole: bool = (bubble.get("label") as Label).visible_characters == -1
	talk.call("_unhandled_input", press)
	bubble.call("_process", 1.0)
	var next: Node2D = talk.get("bubble")
	check("  Interact hurries it: the line shows whole, then gives way; the next speaker in the cast says the next line",
		whole and next != null and next != bubble and next.get_parent() == second and next.get("lines") == ["Two, a little longer."],
		next.get("lines") if next != null else null)
	for step in 40:
		if not is_instance_valid(next):
			break
		next.call("_process", 0.5)
	check("  after the last line the conversation says it is finished and goes", ended.size() == 1 and talk.is_queued_for_deletion())
	var gone: Node = Talk.play(holder, [["a", "First."], ["b", "Second."]], {"a": first, "b": second})
	await get_tree().process_frame
	first.free()
	gone.call("_process", 0.0)
	var after: Node2D = gone.get("bubble")
	check("  a speaker who goes mid-line takes the line, and the next is said",
		after != null and is_instance_valid(after) and after.get_parent() == second and after.get("lines") == ["Second."])
	gone.free()
	if is_instance_valid(after):
		after.free()
	# ONE UNDER ANOTHER speaks from below its feet, or its bubble covers them.
	var upper := Node2D.new()
	holder.add_child(upper)
	second.position = Vector2(-4, 40)
	var stacked: Node = Talk.play(holder, [["up", "Above."], ["down", "Below."]], {"up": upper, "down": second})
	await get_tree().process_frame
	var top_bubble: Node2D = stacked.get("bubble")
	top_bubble.call("hurry")
	top_bubble.call("hurry")
	top_bubble.call("_process", 1.0)
	var low_bubble: Node2D = stacked.get("bubble")
	var paper: Rect2 = low_bubble.call("box") if low_bubble != null else Rect2()
	check("  one standing just under another speaks from below its feet, the paper hanging down; the one above, over its head",
		not bool(top_bubble.get("below")) and low_bubble != null and bool(low_bubble.get("below"))
		and low_bubble.position == Talk.FEET_AT and paper.position.y > 0.0, [paper])
	stacked.free()
	check("  nothing to say is no conversation", Talk.play(holder, [], {}) == null)
	holder.queue_free()
	# ---- the hero's bubble sits over its name --------------------------------
	var hero_body: CharacterBody2D = (load("res://src/characters/player.gd") as GDScript).new()
	hero_body.set("character_name", "tank")
	var bare: Vector2 = hero_body.call("talk_at")
	var plate := Label.new()
	plate.position = Vector2(-10, -70)
	hero_body.set("_nameplate", plate)
	var over_name: Vector2 = hero_body.call("talk_at")
	check("a hero's bubble points just over its name (over its head with no name yet)",
		is_equal_approx(bare.y, -58.0 - 3.0 - 1.0) and is_equal_approx(over_name.y, -71.0) and over_name.x == 0.0, [bare, over_name])
	plate.free()
	hero_body.free()
	# ---- the shopkeeper's first meeting --------------------------------------
	var key: String = Keeper.talk_key()
	var met_key: String = Talk.seen_key(Keeper.MEETING)
	var cfg := ConfigFile.new()
	cfg.load(ControlsPanel.seen_path)
	for each in [key, met_key]:
		if cfg.has_section_key("talk", each.replace("/", "|")):
			cfg.erase_section_key("talk", each.replace("/", "|"))
	# MET HIM BEFORE THERE WERE CONVERSATIONS (0.171.1, the owner: "also
	# warrior did not talk to shop keeper"): three greetings already heard.
	cfg.set_value("talk", key.replace("/", "|"), 3)
	cfg.save(ControlsPanel.seen_path)
	var area := Area2D.new()
	var keeper := AnimatedSprite2D.new()
	var frames := SpriteFrames.new()
	frames.add_animation(Keeper.IDLE_ANIM)
	frames.add_animation(Keeper.WAVE_ANIM)
	keeper.sprite_frames = frames
	area.add_child(keeper)
	keeper.set_script(Keeper)
	keeper.set("class_override", "warrior")
	add_child(area)
	var visitor := CharacterBody2D.new()
	visitor.add_to_group("player")
	add_child(visitor)
	await get_tree().process_frame
	var others: Array = get_tree().get_nodes_in_group("player").filter(func(n: Node) -> bool: return n != visitor)
	for other in others:
		other.remove_from_group("player")
	keeper.call("_on_body_entered", visitor)
	var meeting: Node = keeper.get("bubble")
	await get_tree().process_frame
	var opening: Node2D = meeting.get("bubble") if meeting != null else null
	var warrior_lines: Array = Talk.lines_for(Keeper.MEETING, "warrior")
	check("a warrior who met him before there were conversations: one now, his first line over his head, counted for the character",
		meeting != null and meeting.get("lines") == warrior_lines and opening != null and opening.get_parent() == keeper
		and opening.position == Keeper.BUBBLE_AT and opening.get("lines") == [warrior_lines[0][1]]
		and Bubble.times_said(met_key) == 1 and Bubble.times_said(key) == 4)
	opening.call("hurry")
	opening.call("hurry")
	opening.call("_process", 1.0)
	# THE HERO ANSWERS BY CHOOSING (0.172.0): four answers under the hero,
	# the last Trade.
	var offered: Node2D = visitor.get_node_or_null("choicebox") as Node2D
	var rows: Array = []
	if offered != null:
		for row in offered.get("labels"):
			rows.append((row as Label).text)
	check("  then the hero picks an answer, offered under the hero: the fourth is Trade",
		offered != null and offered.position == Talk.FEET_AT and rows.size() == 4
		and rows[0] == "1  Lost? I was dead." and rows[3] == "4  Trade", rows)
	if offered != null:
		offered.call("choose", 0)
	var reply: Node2D = meeting.get("bubble")
	check("  picking the first, the hero says its branch", reply != null and reply.get_parent() == visitor
		and reply.get("lines") == [Talk.lines_for(Keeper.MEETING, "warrior")[Talk.branch_where(warrior_lines, "dead") + 1][1]]
		and Talk.choice_made(Keeper.MEETING) == "dead", reply.get("lines") if reply != null else null)
	keeper.call("greet")
	check("  he does not start again while they talk", keeper.get("bubble") == meeting and Bubble.times_said(key) == 4)
	meeting.free()
	if is_instance_valid(reply):
		reply.free()
	keeper.set("_last_greeting", -1000.0)
	keeper.call("greet")
	var later: Node = keeper.get("bubble")
	check("  the next visit is the next greeting in turn, and the conversation is not had twice",
		later is Node2D and later.get("lines") == Keeper.greeting_for(4) and Bubble.times_said(met_key) == 1)
	for other in others:
		if is_instance_valid(other):
			other.add_to_group("player")
	visitor.queue_free()
	area.queue_free()
	await get_tree().process_frame
	print("  characters talk: scripts a hero, in turn, hurried, the shopkeeper's first meeting")


# A HERO SPEAKS ON ARRIVING (0.171.0). The owner: "when warrior dies he could
# arrive and say, This is not the crypt where am I how did I get here my head
# is screaming", "I think I have been here before", "My entire body hurts like
# I was slashed into pieces?", and "warrior goes through portal and another
# chat come up saying I am so hungry". talk.gd arrival(): the scene
# "arrive_<the area's scene>", once a character, after the area's story.
func _test_a_hero_speaks_on_arriving() -> void:
	section("A HERO SPEAKS ON ARRIVING (0.171.0): the warrior's first town and first Big Field, in his words")
	const Talk := preload("res://src/shared/talk.gd")
	const Bubble := preload("res://src/shared/speechbubble.gd")
	var town: Array = Talk.lines_for("arrive_elusion", "warrior")
	var field: Array = Talk.lines_for("arrive_bigfield", "warrior")
	check("the warrior's first time in town is three lines, his own; the Big Field one",
		town.size() == 3 and town.all(func(line: Array) -> bool: return line[0] == "hero")
		and str(town[0][1]).begins_with("This is not the crypt") and str(town[2][1]).contains("slashed into pieces")
		and field.size() == 1 and str(field[0][1]).begins_with("I am so hungry"), [town, field])
	var wired: Array = []
	for wiring in [["res://src/world/elusion.gd", "Talk.arrive(self, Talk.came_back_from_death(), \"\", Talk.just_signed_in())", "func _ready"],
			["res://src/world/field.gd", "Talk.arrive(self, Talk.came_back_from_death())", "func _ready"],
			["res://src/ui/menus/gameover.gd", "Talk.note_death()", "func _ready"],
			["res://src/ui/menus/characterselect.gd", "GameState.just_signed_in = true", "func _enter_world"]]:
		var src: String = FileAccess.get_file_as_string(str(wiring[0]))
		var ready: int = _first_code_index(src, str(wiring[2]), 0)
		var call: int = _first_code_index(src, str(wiring[1]), ready)
		var after: int = src.find("\nfunc ", ready + 4)
		wired.append(ready >= 0 and call > ready and (after < 0 or call < after))
	var named := Node.new()
	named.scene_file_path = "res://scene/bigfield.tscn"
	check("  the town and every area on field.gd ask for it as they start, the game over screen notes a death, character select a sign-in; the Big Field's is arrive_bigfield",
		wired == [true, true, true, true] and Talk.arrival_scene(named) == "arrive_bigfield", wired)
	named.free()
	# ---- once, after the story, a line at a time ------------------------------
	var area := Node2D.new()
	area.scene_file_path = "res://scene/elusion.tscn"
	add_child(area)
	var key: String = Talk.seen_key("arrive_elusion")
	var cfg := ConfigFile.new()
	cfg.load(ControlsPanel.seen_path)
	if cfg.has_section_key("talk", key.replace("/", "|")):
		cfg.erase_section_key("talk", key.replace("/", "|"))
	cfg.save(ControlsPanel.seen_path)
	var others: Array = get_tree().get_nodes_in_group("player")
	for other in others:
		other.remove_from_group("player")
	var hero := Node2D.new()
	hero.add_to_group("player")
	area.add_child(hero)
	var story := StoryScreen.new()
	area.add_child(story)
	var talk: Node = Talk.arrival(area, "warrior")
	await get_tree().process_frame
	talk.call("_process", Talk.ARRIVE_DELAY + 1.0)
	var quiet: bool = talk.get("bubble") == null and Bubble.times_said(key) == 0
	story.free()
	talk.call("_process", 0.1)
	var first: Node2D = talk.get("bubble")
	check("arriving in town: nothing while the story screen is up; then the warrior's first line over his head, counted",
		talk != null and talk.name == "arrivaltalk" and quiet and first != null and first.get_parent() == hero
		and first.get("lines") == [town[0][1]] and not bool(first.get("below")) and Bubble.times_said(key) == 1,
		[quiet, Bubble.times_said(key)])
	first.call("hurry")
	first.call("hurry")
	first.call("_process", 1.0)
	var waiting: bool = talk.get("held") == true
	await get_tree().process_frame
	talk.call("_process", 0.0)
	var second: Node2D = talk.get("bubble")
	check("  his next line waits for the last bubble to go, then is said over him",
		waiting and second != null and second != first and second.get_parent() == hero and second.get("lines") == [town[1][1]])
	check("  a part each time: with its one part said, arriving again says nothing; a hero with no lines here says nothing",
		Talk.arrival(area, "warrior") == null and Talk.arrival(area, "nobody") == null)
	# ---- after a death -----------------------------------------------------------
	Talk.note_death()
	var back: bool = Talk.came_back_from_death()
	var once: bool = not Talk.came_back_from_death()
	GameState.back_from_death = "somebody/else#talk:"
	var not_them: bool = not Talk.came_back_from_death() and GameState.back_from_death == ""
	check("after a death: the hero who died comes back from it, once; another hero picked after it did not",
		back and once and not_them)
	cfg.load(ControlsPanel.seen_path)
	cfg.erase_section_key("talk", key.replace("/", "|"))
	cfg.save(ControlsPanel.seen_path)
	var fallback: Node = Talk.arrive(area, true, "warrior")
	check("  with no after-death lines left, the arrival's own are said",
		fallback != null and fallback.get("waiting_scene") == "arrive_elusion" and int(fallback.get("part")) == 0)
	if fallback != null:
		fallback.free()
	# ---- signing in says the first part at most --------------------------------
	GameState.just_signed_in = true
	var signed: bool = Talk.just_signed_in()
	var signed_once: bool = not Talk.just_signed_in()
	var mage_key: String = Talk.seen_key("arrive_elusion")
	cfg.load(ControlsPanel.seen_path)
	cfg.set_value("talk", mage_key.replace("/", "|"), 1)
	cfg.save(ControlsPanel.seen_path)
	var on_sign_in: Node = Talk.arrive(area, false, "mage", true)
	var by_portal: Node = Talk.arrive(area, false, "mage", false)
	var mage_two: Array = Talk.lines_for("arrive_elusion", "mage", 1)
	check("signing in says only a hero's first part; the next waits for a trip into town (\"in the first portal to town\")",
		signed and signed_once and on_sign_in == null and by_portal != null and int(by_portal.get("part")) == 1
		and mage_two.size() == 1 and str(mage_two[0][1]).contains("learn new magic"),
		[signed, signed_once, on_sign_in, mage_two])
	if by_portal != null:
		by_portal.free()
	cfg.load(ControlsPanel.seen_path)
	cfg.erase_section_key("talk", mage_key.replace("/", "|"))
	cfg.save(ControlsPanel.seen_path)
	var first_on_sign_in: Node = Talk.arrive(area, false, "mage", true)
	check("  and a hero's very first arrival is said on signing in, as before",
		first_on_sign_in != null and int(first_on_sign_in.get("part")) == 0)
	if first_on_sign_in != null:
		first_on_sign_in.free()
	area.queue_free()
	for other in others:
		if is_instance_valid(other):
			other.add_to_group("player")
	await get_tree().process_frame
	print("  a hero speaks on arriving: once, after the story, a line at a time")


# HEROES CHOOSE WHAT TO SAY (0.172.0). The owner: "a is a convo b is a convo
# and so is c thats what makes chat branching amazing", "lets add another
# number that says trade" - "the issue was people did not know you could
# trade the shop keep". A script's "?" lines are answers the player picks
# (choicebox.gd); [branch], > and @shop / @end; the Replay story button.
func _test_heroes_choose_what_to_say() -> void:
	section("HEROES CHOOSE WHAT TO SAY (0.172.0): answers to pick, branches, Trade, Replay story")
	const Talk := preload("res://src/shared/talk.gd")
	const Bubble := preload("res://src/shared/speechbubble.gd")
	var text := "a: Are you lost?\n? First = one\n? Second = two\n\n? Trade = @shop\n[one]\nhero: One.\n[two]\nhero: Two.\n> three\n[three]\na: And on.\n"
	var steps: Array = Talk.read_script(text)
	check("a script's answers: \"? words = branch\" lines in a row are one choice; [branch] and > read",
		steps.size() == 9 and steps[1] == ["?", [["First", "one"], ["Second", "two"], ["Trade", "@shop"]]]
		and steps[2] == ["[", "one"] and steps[6] == [">", "three"], steps)
	var bad: Array = Talk.problems("a: hi\n? Go = nowhere\n? Do = @dance\nthis line has no speaker\n> lost\n")
	check("  problems() names what cannot be played: a line it cannot read, a branch not there, an action it does not know",
		bad.size() == 4 and str(bad[0]).begins_with("cannot read") and bad.has("no [nowhere] for it to go to")
		and bad.has("no such action: @dance") and bad.has("no [lost] for it to go to"), bad)
	var trades: Array = []
	for hero in ["warrior", "mage", "tank", "healer"]:
		var meeting: Array = Talk.lines_for("meet_shopkeeper", hero)
		var first_choice: Array = []
		for step in meeting:
			if str(step[0]) == "?":
				first_choice = step[1]
				break
		var menu: Array = Talk.lines_for("visit_shopkeeper", hero)
		var menu_first: Array = menu[0][1] if not menu.is_empty() and str(menu[0][0]) == "?" else []
		trades.append(first_choice.size() == 4 and first_choice[3] == ["Trade", "@shop"]
			and Talk.script_path("visit_shopkeeper", hero).ends_with("/%s.txt" % hero)
			and not menu_first.is_empty() and menu_first[0] == ["Trade", "@shop"])
	check("  every hero has its own meeting with the shopkeeper (four answers, the fourth Trade) and its own menu each visit (Trade first)",
		trades == [true, true, true, true], trades)
	# ---- a conversation with a choice -----------------------------------------
	var holder := Node2D.new()
	add_child(holder)
	var asker := Node2D.new()
	var hero := Node2D.new()
	holder.add_child(asker)
	holder.add_child(hero)
	hero.position = Vector2(200, 0)
	var talk: Node = Talk.play(holder, steps, {"a": asker, "hero": hero}, "choicetest")
	await get_tree().process_frame
	var first: Node2D = talk.get("bubble")
	first.call("hurry")
	first.call("hurry")
	first.call("_process", 1.0)
	var box: Node2D = hero.get_node_or_null("choicebox") as Node2D
	var row_words: Array = []
	if box != null:
		for row in box.get("labels"):
			row_words.append((row as Label).text)
	check("after the question, the answers under the hero, numbered; nothing said while they wait",
		box != null and box.position == Talk.FEET_AT and row_words == ["1  First", "2  Second", "3  Trade"]
		and talk.get("bubble") == null, row_words)
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.physical_keycode = KEY_2
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().process_frame
	await get_tree().process_frame
	var said: Node2D = talk.get("bubble")
	check("  the 2 key picks the second: its branch is said, the pick kept for the character, the box gone",
		said != null and said.get_parent() == hero and said.get("lines") == ["Two."]
		and Talk.choice_made("choicetest") == "two" and not is_instance_valid(box), said.get("lines") if said != null else null)
	said.call("hurry")
	said.call("hurry")
	said.call("_process", 1.0)
	var jumped: Node2D = talk.get("bubble")
	check("  > goes on in another branch", jumped != null and jumped.get_parent() == asker and jumped.get("lines") == ["And on."])
	talk.free()
	if is_instance_valid(jumped):
		jumped.free()
	# a branch ends where the next begins
	var ended: Array = []
	var short: Node = Talk.play(holder, steps, {"a": asker, "hero": hero}, "choicetest")
	short.connect("finished", func() -> void: ended.append(true))
	await get_tree().process_frame
	var ask: Node2D = short.get("bubble")
	ask.call("hurry")
	ask.call("hurry")
	ask.call("_process", 1.0)
	(hero.get_node("choicebox") as Node2D).call("choose", 0)
	var one: Node2D = short.get("bubble")
	one.call("hurry")
	one.call("hurry")
	one.call("_process", 1.0)
	check("  a branch ends where the next begins: \"One.\", then the conversation is over",
		ended.size() == 1 and short.is_queued_for_deletion())
	await get_tree().process_frame
	# Trade, by a click on its row
	var vendor_shape := GDScript.new()
	vendor_shape.source_code = "extends Node\nvar opened: int = 0\nfunc player_at_counter() -> bool:\n\treturn true\nfunc open_for_player() -> void:\n\topened += 1\n"
	vendor_shape.reload()
	var vendor := Node.new()
	vendor.set_script(vendor_shape)
	vendor.add_to_group(&"vendors")
	add_child(vendor)
	var shop_talk: Node = Talk.play(holder, steps, {"a": asker, "hero": hero}, "choicetest")
	await get_tree().process_frame
	var asked: Node2D = shop_talk.get("bubble")
	asked.call("hurry")
	asked.call("hurry")
	asked.call("_process", 1.0)
	var trade_box: Node2D = hero.get_node_or_null("choicebox") as Node2D
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	# The window's pixels: the event goes in where a real click does.
	click.position = trade_box.get_viewport().get_screen_transform() \
		* (trade_box.get_global_transform_with_canvas() * (trade_box.call("row_rect", 2) as Rect2).get_center())
	Input.parse_input_event(click)
	await get_tree().process_frame
	await get_tree().process_frame
	check("  a click on Trade opens the shop for a hero at its counter (@shop), and the conversation ends",
		vendor.get("opened") == 1 and not is_instance_valid(shop_talk) or (shop_talk != null and shop_talk.is_queued_for_deletion()),
		vendor.get("opened"))
	vendor.queue_free()
	if is_instance_valid(shop_talk):
		shop_talk.free()
	if is_instance_valid(trade_box):
		trade_box.free()
	# walking off
	var walked: Node = Talk.play(holder, steps, {"a": asker, "hero": hero}, "choicetest")
	await get_tree().process_frame
	var q: Node2D = walked.get("bubble")
	q.call("hurry")
	q.call("hurry")
	q.call("_process", 1.0)
	var left_box: Node2D = hero.get_node_or_null("choicebox") as Node2D
	hero.position += Vector2(Talk.CHOICE_REACH + 20.0, 0)
	walked.call("_process", 0.0)
	check("  walking off ends it, the answers with it", walked.is_queued_for_deletion()
		and (left_box == null or left_box.is_queued_for_deletion()))
	await get_tree().process_frame
	holder.queue_free()
	# ---- the menu every visit -----------------------------------------------------
	const Keeper := preload("res://src/world/shopkeeperanim.gd")
	var cfg := ConfigFile.new()
	cfg.load(ControlsPanel.seen_path)
	cfg.set_value("talk", Talk.seen_key(Keeper.MEETING).replace("/", "|"), 1)
	cfg.set_value("talk", Keeper.talk_key().replace("/", "|"), 2)
	if cfg.has_section_key("talk", Talk.seen_key(Keeper.VISIT).replace("/", "|")):
		cfg.erase_section_key("talk", Talk.seen_key(Keeper.VISIT).replace("/", "|"))
	cfg.save(ControlsPanel.seen_path)
	var area := Area2D.new()
	var keeper := AnimatedSprite2D.new()
	var frames := SpriteFrames.new()
	frames.add_animation(Keeper.IDLE_ANIM)
	frames.add_animation(Keeper.WAVE_ANIM)
	keeper.sprite_frames = frames
	area.add_child(keeper)
	keeper.set_script(Keeper)
	keeper.set("class_override", "warrior")
	add_child(area)
	var others: Array = get_tree().get_nodes_in_group("player")
	for other in others:
		other.remove_from_group("player")
	var visitor := Node2D.new()
	visitor.add_to_group("player")
	visitor.position = Vector2(0, 40)
	add_child(visitor)
	await get_tree().process_frame
	keeper.call("greet")
	var greeting: Node2D = keeper.get("bubble") as Node2D
	var greeted: bool = greeting != null and greeting.get("lines") == Keeper.greeting_for(2)
	for step in 40:
		if not is_instance_valid(greeting):
			break
		greeting.call("_process", 0.5)
	var menu: Node = keeper.get("bubble")
	await get_tree().process_frame
	var menu_box: Node2D = visitor.get_node_or_null("choicebox") as Node2D
	var menu_rows: Array = []
	if menu_box != null:
		for row in menu_box.get("labels"):
			menu_rows.append((row as Label).text)
	check("a later visit: his greeting, then the menu under the hero - Trade, Talk, Goodbye (\"story once, menu every visit\")",
		greeted and menu != null and menu.get("scene_name") == Keeper.VISIT and menu_rows == ["1  Trade", "2  Talk", "3  Goodbye"],
		[greeted, menu_rows])
	var shop_open := Node.new()
	shop_open.add_to_group(&"openvendor")
	add_child(shop_open)
	menu.call("_process", 0.0)
	check("  the shop opened another way (Interact at the counter) takes the menu away",
		menu.is_queued_for_deletion())
	shop_open.free()
	await get_tree().process_frame
	keeper.call("greet")
	var again: Node = keeper.get("bubble")
	await get_tree().process_frame
	var again_steps: Array = again.get("lines") if again != null else []
	var again_talk: Array = again_steps[Talk.branch_where(again_steps, "talk") + 1] if not again_steps.is_empty() else []
	check("  back in the shop straight after: no second greeting, the menu again at once (0.172.1, \"i want that box to pop up again\"), Talk with something new",
		again != null and again.get("scene_name") == Keeper.VISIT and visitor.get_node_or_null("choicebox") != null
		and not again_talk.is_empty() and str(again_talk[1]).contains("fire pit"), again_talk)
	if is_instance_valid(again):
		again.free()
	for child in visitor.get_children():
		child.free()
	var next_visit: Node = Talk.visit(self, Keeper.VISIT, "warrior", {"hero": visitor})
	var talk_line: Array = []
	if next_visit != null:
		var steps_now: Array = next_visit.get("lines")
		talk_line = steps_now[Talk.branch_where(steps_now, "talk") + 1]
	check("  each visit the next part, round again: after the last, the first",
		next_visit != null and str(talk_line[1]).contains("waystone"), talk_line)
	if next_visit != null:
		next_visit.free()
	for child in visitor.get_children():
		child.free()
	visitor.queue_free()
	area.queue_free()
	for other in others:
		if is_instance_valid(other):
			other.add_to_group("player")
	await get_tree().process_frame
	# ---- Replay story ------------------------------------------------------------
	Bubble.note_said(Talk.seen_key("arrive_elusion"))
	Bubble.note_said(Talk.seen_key("meet_shopkeeper"))
	var forgot: int = Talk.forget_story()
	check("Replay story: this character forgets every scene heard and every pick made",
		forgot >= 3 and Bubble.times_said(Talk.seen_key("arrive_elusion")) == 0
		and Bubble.times_said(Talk.seen_key("meet_shopkeeper")) == 0 and Talk.choice_made("choicetest") == "", forgot)
	var panel: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(panel)
	await get_tree().process_frame
	var replay: Button = panel.find_child("replaystorybutton", true, false) as Button
	var catalogue: Button = panel.get_node_or_null("%cataloguebutton") as Button
	Bubble.note_said(Talk.seen_key("arrive_elusion"))
	if replay != null:
		replay.pressed.emit()
	check("  the GM panel's Testing tab has it, beside Item catalogue... (no taller), and it forgets",
		replay != null and catalogue != null and replay.get_parent() == catalogue.get_parent()
		and str(replay.get_parent().name) == "cataloguerow" and Bubble.times_said(Talk.seen_key("arrive_elusion")) == 0)
	panel.queue_free()
	await get_tree().process_frame
	print("  heroes choose: answers, branches, >, @shop, walking off, Replay story")


# A NEWER VERSION IS SAID (0.173.0). The owner: "the update game is not
# popping up for pc", "pc is on browser also no need for anyone to download
# anything really". The web deploy writes version.txt; versioncheck.gd asks
# for it and the HUD's strip says "Refresh the page to update".
func _test_a_newer_version_is_said() -> void:
	section("A NEWER VERSION IS SAID (0.173.0): version.txt, asked every five minutes, on the strip")
	const Check := preload("res://src/systems/versioncheck.gd")
	const ApiScript := preload("res://src/systems/api.gd")
	check("versions compare as numbers, three of them: 0.172.10 is after 0.172.9, 1.0.0 after 0.999.0; anything else is never newer",
		Check.is_newer("0.172.10", "0.172.9") and Check.is_newer("1.0.0", "0.999.0") and not Check.is_newer("0.172.1", "0.172.1")
		and not Check.is_newer("0.99.0", "0.172.1") and not Check.is_newer("<html>", "0.1.0") and not Check.is_newer("1.2", "0.1.0"))
	var was: String = ApiScript.newer_web_version
	ApiScript.newer_web_version = ""
	var checker: Node = Check.new()
	add_child(checker)
	var heard: Array = []
	checker.connect("newer_version", func(version: String) -> void: heard.append(version))
	check("  off the web it asks nowhere (a game run from the editor has no page)", str(checker.get("url")) == "")
	checker.call("note", ApiScript.DISPLAY_VERSION)
	checker.call("note", "0.0.1")
	checker.call("note", "99.0.0\n")
	checker.call("note", "99.0.0")
	check("  this version or an older one says nothing; a newer one is kept and said once",
		heard == ["99.0.0"] and ApiScript.newer_web_version == "99.0.0", heard)
	check("  the line, the owner's words: \"An update has been made. Refresh your browser.\" - and the login screen says it too",
		Check.line("99.0.0") == "An update has been made. Refresh your browser."
		and ApiScript.build_notice() == Check.line("99.0.0"), ApiScript.build_notice())
	var fresh: Node = Check.new()
	add_child(fresh)
	fresh.set("url", "https://example.invalid/version.txt")
	var asked: Array = []
	fresh.set("fetch", func(where: String) -> String:
		asked.append(where)
		return "99.1.0")
	fresh.set("_left", 0.0)
	fresh.call("_process", 0.016)
	await get_tree().process_frame
	check("  it asks when its time comes, and again EVERY_SECONDS later", asked == ["https://example.invalid/version.txt"]
		and str(fresh.get("newest")) == "99.1.0" and float(fresh.get("_left")) > Check.EVERY_SECONDS - 1.0, [asked, fresh.get("newest"), fresh.get("_left")])
	fresh.call("_notification", Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check("  and soon after the game is looked at again", float(fresh.get("_left")) <= Check.BACK_SECONDS)
	fresh.queue_free()
	checker.queue_free()
	var hud: Node = (load("res://src/ui/characterhud.gd") as GDScript).new()
	hud.call("_on_newer_version", "99.0.0")
	var states: Dictionary = hud.get("_status_states")
	var order: Array = hud.get("STATUS_PRIORITY")
	check("the HUD's strip says it, under a trade, over PvP",
		states.has("update") and str(states["update"]["text"]) == Check.line("99.0.0")
		and order.find("update") > order.find("trade") and order.find("update") < order.find("pvp"), states)
	hud.free()
	var src: String = FileAccess.get_file_as_string("res://src/ui/characterhud.gd")
	var ready: int = _first_code_index(src, "func _ready", 0)
	var watch: int = _first_code_index(src, "_watch_for_a_newer_version()", ready)
	var deploy: String = FileAccess.get_file_as_string("res://tools/deploy_web.ps1")
	check("  the HUD watches from its start; Api has the check; the web deploy writes version.txt into the build",
		watch > ready and watch < src.find("\nfunc ", ready + 4) and Api.version_check != null
		and deploy.contains("[IO.File]::WriteAllText((Join-Path $web \"version.txt\"), \"$version`n\")"))
	ApiScript.newer_web_version = was
	print("  a newer version: version.txt, compared, said once, on the strip and at sign-in")


# SPAWNED MONSTERS STAY ON THE TOWN'S GROUND (0.173.1). The owner: "if i
# spawn monsters in town they go outside the map". The town has no
# navigation, so the GM panel's Spawn put them anywhere in the ring round
# him - off the ground, on the water. gmspawner.gd on_floor().
func _test_spawns_stay_on_the_town_ground() -> void:
	section("SPAWNED MONSTERS STAY ON THE TOWN'S GROUND (0.173.1)")
	const Spawner := preload("res://src/world/gmspawner.gd")
	var town: Node = (load("res://scene/elusion.tscn") as PackedScene).instantiate()
	var tiles: Array = Spawner.floor_layers(town)
	check("the town has a ground layer (and a water one) to place them on",
		tiles.size() == 2 and tiles[0] is TileMapLayer and tiles[1] is TileMapLayer)
	if tiles.size() != 2:
		town.free()
		return
	var ground: TileMapLayer = tiles[0]
	var used: Rect2i = ground.get_used_rect()
	# A corner of the town: most of the ring round it is off the ground.
	var corner: Vector2 = ground.to_global(ground.map_to_local(used.position + Vector2i(2, 2)))
	var placed: int = 0
	var wrong: Array = []
	for n in 60:
		var spot: Variant = Spawner._spot(corner, RID(), false, null, tiles, null)
		if spot == null:
			continue
		placed += 1
		if not Spawner.on_floor(spot, tiles, null):
			wrong.append(spot)
	var outside: Vector2 = ground.to_global(ground.map_to_local(used.position - Vector2i(10, 10)))
	check("by a corner of the town, every spot it gives is on the ground and off the water; far outside is not floor",
		placed > 5 and wrong.is_empty() and not Spawner.on_floor(outside, tiles, null), [placed, wrong])
	check("  an area with no ground layer places as before", Spawner.floor_layers(Node.new()).is_empty())
	town.free()
	print("  spawns stay on the town's ground")


# MULTIMESHES SENT WITHOUT WAITING (0.173.2). The owner's limit sweep in his
# browser: 20 archers took drawing from 1.3 to 17.1 ms a frame, and every kind
# that writes a MultiMesh (the bullets, the horde, the spikes' rings) stopped
# on slow frames of 20-25 ms. Each write went whole (12,000 bullet slots, 5,000
# slimes) into the MultiMesh being drawn. meshring.gd: the next one round,
# only the slots used.
func _test_multimeshes_never_wait() -> void:
	section("MULTIMESHES SENT WITHOUT WAITING (0.173.2)")
	check("a mesh's slots: a power of two (64 at least), kept while it fits and is not four times too big, never past the buffer",
		MeshRingScript.slots_for(300, 0, 12000) == 512 and MeshRingScript.slots_for(300, 512, 12000) == 512
		and MeshRingScript.slots_for(100, 512, 12000) == 128 and MeshRingScript.slots_for(130, 128, 12000) == 256
		and MeshRingScript.slots_for(5, 0, 12000) == MeshRingScript.LEAST and MeshRingScript.slots_for(4999, 0, 5000) == 5000
		and MeshRingScript.slots_for(20, 64, 12000) == 64,
		[MeshRingScript.slots_for(300, 0, 12000), MeshRingScript.slots_for(100, 512, 12000), MeshRingScript.slots_for(4999, 0, 5000)])
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_2D
	multi.use_colors = true
	multi.mesh = QuadMesh.new()
	multi.instance_count = 0
	var drawer := MultiMeshInstance2D.new()
	drawer.multimesh = multi
	add_child(drawer)
	var ring: MeshRingScript = MeshRingScript.new()
	ring.wear(drawer, 12)
	ring.set_bounds(AABB(Vector3(-50, -50, -1), Vector3(100, 100, 2)))
	var buffer := PackedFloat32Array()
	buffer.resize(12000 * 12)
	for k in 300:
		var o: int = k * 12
		buffer[o] = 1.0
		buffer[o + 5] = 1.0
		buffer[o + 3] = float(k)
		buffer[o + 7] = float(-k)
		buffer[o + 11] = 1.0
	var drawn: Array = []
	for n in 4:
		ring.send(buffer, 300)
		drawn.append(drawer.multimesh)
	var turned: bool = drawn[0] != drawn[1] and drawn[1] != drawn[2] and drawn[2] != drawn[3] and drawn[3] == drawn[0]
	check("each send goes to the next MultiMesh of three, never the one on screen; the drawer is turned to it",
		turned and ring.meshes.size() == MeshRingScript.RING and drawn[0] != multi, drawn.map(func(m: MultiMesh) -> int: return m.get_rid().get_id()))
	var now: MultiMesh = drawer.multimesh
	check("  it holds only the slots used, in a step (512 for 300 of 12,000), and draws the 300 (every slot since 0.174.2, the rest blank)",
		now.instance_count == 512 and now.visible_instance_count == -1 and ring.shown == 300 and _drawn(drawer) == 300,
		[now.instance_count, now.visible_instance_count, _drawn(drawer)])
	# What each holds can be read back only from a real renderer (the suite
	# runs headless), so this asks it there.
	var as_written: bool = DisplayServer.get_name() == "headless" \
		or (now.get_instance_transform_2d(0).origin == Vector2(0, 0)
			and now.get_instance_transform_2d(299).origin == Vector2(299, -299))
	check("  every instance as written, and every one round has the bounds",
		as_written and ring.meshes.all(func(m: MultiMesh) -> bool: return m.custom_aabb.size.x == 100.0),
		ring.meshes.map(func(m: MultiMesh) -> Vector3: return m.custom_aabb.size))
	var sent: int = ring.sends
	ring.send(buffer, 0)
	ring.send(buffer, 0)
	ring.send(buffer, 0)
	check("nothing to draw: the one on screen draws none, and nothing is sent while there is nothing",
		drawer.multimesh.visible_instance_count == 0 and _drawn(drawer) == 0 and ring.sends == sent and ring.shown == 0)
	var resized: int = ring.resizes
	for n in 6:
		ring.send(buffer, 280 + n * 4)
	check("  a crowd that changes a little keeps its sizes (no reallocation)", ring.resizes == resized, ring.resizes - resized)
	drawer.queue_free()
	# The bullet field: none in flight sends nothing; 300 send 512, not 12,000.
	var field := BulletField.new()
	field.bounds = Rect2(-2000, -2000, 4000, 4000)
	add_child(field)
	await get_tree().process_frame
	var field_ring: MeshRingScript = field.get("_ring")
	for n in 3:
		field.step(1.0 / 60.0, Vector2(1.0e6, 1.0e6), 0.0, 0.0, true)
	check("the bullet field wears a ring, and with no bullets it sends nothing, frame after frame",
		field_ring != null and field_ring.sends == 0)
	for k in 300:
		field.spawn(Vector2(k % 40, floori(k / 40.0)) * 10.0, 0.0, 5.0, Color.WHITE, false, 0.0, 0.0, 5.0, 1, 0)
	field.step(1.0 / 60.0, Vector2(1.0e6, 1.0e6), 0.0, 0.0, true)
	var bullets: MultiMeshInstance2D = field.get_node_or_null(^"bullets") as MultiMeshInstance2D
	check("  300 bullets in flight: 512 slots sent and 300 drawn, not 12,000",
		bullets != null and bullets.multimesh.instance_count == 512 and _drawn(bullets) == 300
		and field_ring.sends == 1, [bullets.multimesh.instance_count if bullets != null else -1, _drawn(bullets)])
	field.clear()
	check("  cleared, none drawn", _drawn(bullets) == 0 and bullets.multimesh.visible_instance_count == 0)
	field.queue_free()
	# Every MultiMesh the game rewrites goes through the ring.
	var direct: Array = []
	for script_path in _all_gd_under("res://src"):
		if _is_suite_script(script_path) or script_path.ends_with("/meshring.gd"):
			continue
		var code: String = _code_src(script_path)
		if code.contains(".buffer = ") or code.contains("multimesh_set_buffer("):
			direct.append(script_path.get_file())
	check("every MultiMesh the game rewrites is sent through meshring.gd (the bullets, the horde, the spikes, the healer run's shots)",
		direct.is_empty() and _code_src("res://src/world/endless/swarm.gd").contains("_mesh_ring.send(")
		and _code_src("res://src/projectiles/spikefx.gd").contains("_ring_send.send(")
		and _code_src("res://src/world/healerrun/healerrun.gd").contains("_shot_send.send("), direct)
	print("  multimeshes sent without waiting: a ring of three, only the slots used")


# THE COUNT DRAWN HOLDS (0.174.2). The owner's card: 1,000 slimes filling the
# Testing Ground gave 50 to 85 frames over 14 ms, each with about 20 ms of
# drawing, while the horde walked on - none once it stood. The browser's
# renderer steps an instanced draw by the number drawn
# (glVertexAttribDivisor(..., instance_count)), and builds its drawing anew
# for each new number; walking on, the number changed 20 times a second.
# meshring.gd draws every slot of a MultiMesh, the ones past the count blank.
func _test_the_count_drawn_holds() -> void:
	section("THE COUNT DRAWN HOLDS (0.174.2)")
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_2D
	multi.use_colors = true
	multi.use_custom_data = true
	multi.mesh = QuadMesh.new()
	multi.instance_count = 0
	var drawer := MultiMeshInstance2D.new()
	drawer.multimesh = multi
	add_child(drawer)
	var ring: MeshRingScript = MeshRingScript.new()
	ring.wear(drawer, 16)
	var buffer := PackedFloat32Array()
	buffer.resize(3000 * 16)
	for k in 3000:
		var o: int = k * 16
		buffer[o] = 1.0
		buffer[o + 5] = 1.0
		buffer[o + 3] = float(k)
		buffer[o + 7] = 2.0
		buffer[o + 11] = 1.0
		buffer[o + 15] = 0.5
	# A horde walking on: ten more a send, 10 to 1,000 - a hundred numbers the
	# old way, each one new to the browser.
	var numbers: Dictionary = {}
	var every_slot: bool = true
	var says: bool = true
	for n in 100:
		var count: int = 10 + n * 10
		ring.send(buffer, count)
		var now: MultiMesh = drawer.multimesh
		numbers[now.instance_count] = true
		every_slot = every_slot and now.visible_instance_count == -1
		says = says and ring.shown == count and _drawn(drawer) == count
	check("a horde walking on, 10 to 1,000 ten more a send: every send draws every slot of its MultiMesh, so the browser sees five numbers (the powers of two), not a hundred",
		every_slot and numbers.size() == 5 and numbers.has(64) and numbers.has(1024), numbers.keys())
	check("  and the ring says how many it really draws (shown, shown_on())", says)
	var blanked: PackedFloat32Array = ring._with_blanks(buffer, 300, 512, 3000)
	var tail: PackedFloat32Array = blanked.slice(300 * 16)
	check("  the slots past the count are sent blank - all zeros, a transform of no size, so nothing of them is drawn - and the count as written",
		blanked.size() == 512 * 16 and blanked.slice(0, 300 * 16) == buffer.slice(0, 300 * 16)
		and tail.size() == 212 * 16 and tail.count(0.0) == tail.size(), [blanked.size(), tail.count(0.0)])
	var narrow: PackedFloat32Array = ring._with_blanks(buffer, 500, 512, 3000)
	var whole: PackedFloat32Array = ring._with_blanks(buffer, 3000, 3000, 3000)
	check("  a narrower gap after a wide one is blank too; a full one is the buffer as it is",
		narrow.size() == 512 * 16 and narrow.slice(500 * 16).count(0.0) == 12 * 16
		and narrow.slice(0, 500 * 16) == buffer.slice(0, 500 * 16) and whole == buffer)
	# Read back only from a real renderer (the suite runs headless).
	ring.send(buffer, 300)
	var on_screen: MultiMesh = drawer.multimesh
	var as_drawn: bool = DisplayServer.get_name() == "headless" \
		or (on_screen.get_instance_transform_2d(299).origin == Vector2(299, 2)
			and on_screen.get_instance_transform_2d(400).x == Vector2.ZERO
			and on_screen.get_instance_transform_2d(400).y == Vector2.ZERO)
	check("  on the card: the last slime where it was written, the slot after the count of no size", as_drawn)
	drawer.queue_free()
	# Nobody beside the ring says how many are drawn.
	var counting: Array = []
	for script_path in ["res://src/shared/bulletfield.gd", "res://src/world/endless/swarm.gd",
			"res://src/projectiles/spikefx.gd", "res://src/world/healerrun/healerrun.gd"]:
		var code: String = _code_src(script_path)
		if code.count("visible_instance_count = ") != code.count("visible_instance_count = 0"):
			counting.append(script_path.get_file())
	check("  the bullets, the horde, the spikes and the healer run's shots leave the count drawn to the ring",
		counting.is_empty(), counting)
	print("  the count drawn holds: every slot drawn, the unused blank")


# THE SWEEP'S AXES COME AWAY (0.174.3). The owner's Every effect sweep: from
# the party axe on, every effect started at 19 ms with nothing out and none
# was measured. The sweep fires party pictures on the player itself, whose
# axe is warrior.gd's `_axe`: the old picture was looked for as `axe`, never
# found, and twenty a second stayed out spinning.
func _test_the_sweeps_axes_come_away() -> void:
	section("THE SWEEP'S AXES COME AWAY (0.174.3)")
	const Kinds := preload("res://src/world/endless/stresskinds.gd")
	var was_shown: Variant = Settings.get_value("others_attacks")
	Settings.set_value("others_attacks", true)
	var body := Node2D.new()
	add_child(body)
	body.global_position = Vector2(-52000, -52000)
	var fired: Array = []
	for n in 3:
		fired.append_array(RemoteAttacks.fire(body, ["axe", 0, -52000.0, -52000.0, -51900.0, -52000.0, 0, 0]))
	var out: Array = fired.filter(func(a): return is_instance_valid(a) and not (a as Node).is_queued_for_deletion())
	check("on a body with no axe of its own, a new party axe takes the old one's place: one out of three thrown",
		fired.size() == 3 and out.size() == 1 and out[0] == fired[2] and RemoteAttacks.axe_of(body) == fired[2],
		[fired.size(), out.size()])
	var kinds: Node = Kinds.new()
	add_child(kinds)
	kinds.call("begin", {"label": "Effect: party warrior axe", "rate": "axe", "kind": -3}, body)
	kinds.call("end")
	check("  and the sweep takes the last one away when the effect ends - the next starts with nothing out",
		(fired[2] as Node).is_queued_for_deletion() and not body.has_meta(RemoteAttacks.PICTURE_AXE))
	kinds.queue_free()
	body.queue_free()
	Settings.set_value("others_attacks", was_shown)
	await get_tree().process_frame
	print("  the sweep's axes come away")


# A PARTY TANK'S AURA, SWEPT (0.174.4). The owner, of the Every effect sweep:
# "i didnt see tanks aura". It stays lit, so it is counted like a shot: how
# many party tanks round you have theirs lit.
func _test_the_tank_aura_is_swept() -> void:
	section("A PARTY TANK'S AURA, SWEPT (0.174.4)")
	const Kinds := preload("res://src/world/endless/stresskinds.gd")
	const Sweep := preload("res://src/world/endless/limitsweep.gd")
	var was_shown: Variant = Settings.get_value("others_attacks")
	Settings.set_value("others_attacks", true)
	var auras: Array = []
	for e in Kinds.effects():
		if Kinds.is_aura(e):
			auras.append(e)
	var swept: Dictionary = auras[0] if not auras.is_empty() else {}
	check("Every effect sweeps a party tank's aura, counted lit like a shot, one more a step",
		auras.size() == 1 and str(swept.get("label", "")) == "Effect: party tank aura" and Kinds.is_shot(swept)
		and not Kinds.is_rate(swept) and Sweep.counted_as(swept) == "lit" and Sweep.most_for(swept) == Kinds.AURA_MOST
		and Sweep.targets_for(Sweep.EVERY_EFFECT, 10).has(swept), [auras.size(), Sweep.counted_as(swept)])
	var me := Node2D.new()
	me.add_to_group(&"player")
	add_child(me)
	me.global_position = Vector2(-53000, -53000)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var made: int = Kinds.make_shots(get_tree(), swept, 3, me.global_position, rng)
	var tanks: Array = get_tree().get_nodes_in_group(Kinds.GROUP).filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	var lit: int = 0
	var burning: int = 0
	for tank in tanks:
		var fire: CanvasItem = (tank as Node).get_node_or_null(^"firering") as CanvasItem
		if str(tank.get("class_id")) == "tank" and fire != null and fire.visible:
			lit += 1
		if (tank as Node).get_node_or_null(^"auraburn") != null:
			burning += 1
	var near: bool = tanks.all(func(t: Node) -> bool: return (t as Node2D).global_position.distance_to(me.global_position) <= 400.0)
	check("  three more: three party tanks round you, each with its aura lit and burning the ground, counted by the sweep",
		made == 3 and tanks.size() == 3 and lit == 3 and burning == 3 and near
		and Kinds.count_shots(get_tree(), swept) == 3, [made, tanks.size(), lit, burning, near])
	var cleared: int = Kinds.clear(get_tree())
	check("  and the ground's Clear all takes them away", cleared == 3
		and Kinds.count_shots(get_tree(), swept) == 0)
	me.queue_free()
	Settings.set_value("others_attacks", was_shown)
	await get_tree().process_frame
	print("  a party tank's aura, swept")


# EVERY MONSTER DRAWN ONCE, FOR REAL, OUT OF SIGHT (0.174.0). The owner's
# browser: 23 to 38 frames of about 25 ms - all drawing - the first time a
# kind appeared after a new build. examplewarm.gd draws one real copy of each
# kind an area may bring as it arrives: a picture only, under everything,
# faint, lit then unlit, with its shots, then gone.
func _test_monsters_warm_by_example() -> void:
	section("EVERY MONSTER DRAWN ONCE, FOR REAL, OUT OF SIGHT (0.174.0)")
	const Warm := preload("res://src/systems/examplewarm.gd")
	var was_warmed: Dictionary = Warm.warmed.duplicate()
	Warm.forget()
	var skeleton: String = "res://scene/enemy/skeleton.tscn"
	var archer: String = "res://scene/enemy/bushsniper.tscn"
	var boss: String = "res://scene/enemy/bossenemy.tscn"
	var provider_script := GDScript.new()
	provider_script.source_code = "extends Node\nvar paths := PackedStringArray()\nfunc warm_examples() -> PackedStringArray:\n\treturn paths\n"
	provider_script.reload()
	var provider: Node = provider_script.new()
	provider.set("paths", PackedStringArray([skeleton, archer, boss, skeleton]))
	provider.add_to_group(Warm.PROVIDERS)
	var area := Node2D.new()
	area.add_child(provider)
	add_child(area)
	var wanted: Array[String] = Warm.scenes_wanted(get_tree())
	check("what an area may bring: each scene once, from the area and what its run says",
		wanted.has(skeleton) and wanted.has(archer) and wanted.has(boss) and wanted.count(skeleton) == 1, wanted)
	var enemies_before: int = get_tree().get_nodes_in_group(&"enemies").size()
	var warm: Node = Warm.add_to(area)
	var seen_ghost: Node = null
	var ghost_ok: bool = false
	var frames: int = 0
	while is_instance_valid(warm) and frames < 120:
		await get_tree().process_frame
		frames += 1
		var holder: Node = warm.get_node_or_null(^"ghosts") if is_instance_valid(warm) else null
		if holder != null and seen_ghost == null:
			for child in holder.get_children():
				if child is BaseEnemy:
					seen_ghost = child
					var bar: CanvasItem = child.get_node_or_null(^"healthbar") as CanvasItem
					ghost_ok = (child as BaseEnemy).is_warm_ghost() and child.process_mode == Node.PROCESS_MODE_DISABLED \
						and not child.is_in_group(&"enemies") and (child as CanvasItem).z_index == RenderingServer.CANVAS_ITEM_Z_MIN \
						and is_equal_approx((holder as CanvasItem).modulate.a, Warm.WARM_ALPHA) \
						and bar != null and bar.visible and bar.z_index == RenderingServer.CANVAS_ITEM_Z_MIN \
						and bar.get_node_or_null(^"healthvalue") != null
					break
	check("a ghost is a picture only: never processing, in no group, under everything, faint, its bar and number shown",
		ghost_ok, [seen_ghost != null])
	check("  all of them gone after a few frames, the warming with them; nothing counted as a monster",
		not is_instance_valid(warm) and frames < 60 and get_tree().get_nodes_in_group(&"enemies").size() == enemies_before, frames)
	check("  the skeleton and the archer drawn, the boss left out, and all three known this session",
		Warm.warmed.has(skeleton) and Warm.warmed.has(archer) and Warm.warmed.has(boss), Warm.warmed.keys())
	var again: Node = Warm.add_to(area)
	var drew_again: int = -1
	for n in 12:
		await get_tree().process_frame
		if is_instance_valid(again):
			drew_again = int(again.get("kinds_drawn"))
	check("  the next arrival brings nothing new: nothing drawn", not is_instance_valid(again) and drew_again <= 0)
	area.queue_free()
	# A shot's picture has no scripts; the archer's arrow is one.
	var archer_ghost: Node = (load(archer) as PackedScene).instantiate()
	var shots: Array[PackedScene] = Warm.shot_scenes(archer_ghost)
	var picture: Node = Warm._picture_of(shots[0]) if not shots.is_empty() else null
	check("the shots: what the monster's script holds from scene/projectiles, as pictures with no scripts",
		not shots.is_empty() and shots.any(func(p: PackedScene) -> bool: return p.resource_path.ends_with("arrow.tscn"))
		and picture != null and picture.get_script() == null and picture.process_mode == Node.PROCESS_MODE_DISABLED)
	archer_ghost.free()
	if picture != null:
		picture.free()
	# Who says what may come.
	var run_script: GDScript = load("res://src/world/endless/endlessrun.gd") as GDScript
	var elites: Dictionary = run_script.get_script_constant_map()["ELITES"]
	var listed: Dictionary = {}
	for land in elites:
		for scene_name in elites[land]:
			listed["res://scene/enemy/%s.tscn" % scene_name] = true
	var run_src: String = _code_src("res://src/world/endless/endlessrun.gd")
	var ground_src: String = _code_src("res://src/world/endless/testingground.gd")
	var registry_src: String = _code_src("res://src/systems/arearegistry.gd")
	check("the Endless names every land's elites, the Testing Ground every kind but the bosses; every arrival warms",
		run_src.contains("add_to_group(&\"warm_examples\")") and run_src.contains("func warm_examples(")
		and ground_src.contains("add_to_group(&\"warm_examples\")") and ground_src.contains("func warm_examples(")
		and registry_src.find("ExampleWarm.add_to(scene)") > registry_src.find("ShaderWarm.add_to(scene)")
		and registry_src.find("ShaderWarm.add_to(scene)") >= 0 and listed.size() > 20, listed.size())
	Warm.warmed = was_warmed
	print("  monsters warm by example: one real copy a kind, drawn as an area arrives")


# CLEARED IN PARTS (0.174.1). The owner's worst spike: "scripts 38.1 ms,
# -12,664 nodes", 600 skeletons freed in one frame. gmspawner.gd clear()
# takes every copy out of the game at once and frees CLEAR_EACH_FRAME a frame.
func _test_the_testing_ground_clears_in_parts() -> void:
	section("CLEARED IN PARTS (0.174.1)")
	const Spawner := preload("res://src/world/gmspawner.gd")
	var script := GDScript.new()
	script.source_code = "extends Node2D\nvar gated: bool = false\n"
	script.reload()
	var holder := Node2D.new()
	add_child(holder)
	var copies: Array = []
	for n in 90:
		var copy: Node2D = script.new()
		copy.add_to_group(Spawner.GROUP)
		copy.add_to_group(&"enemies")
		holder.add_child(copy)
		copies.append(copy)
	var gone: int = Spawner.clear(get_tree())
	var out_now: bool = gone == 90 and Spawner.alive(get_tree()) == 0 and Spawner.clearing() == 90
	for copy in copies:
		out_now = out_now and not (copy as Node).is_in_group(&"enemies") and not (copy as Node2D).visible \
			and bool(copy.get("gated")) and not (copy as Node).is_queued_for_deletion()
	check("Clear takes every copy out at once - out of the groups, hidden, gated - and frees none yet", out_now, [gone, Spawner.clearing()])
	await get_tree().process_frame
	var after_one: int = copies.filter(func(c: Variant) -> bool: return is_instance_valid(c) and not (c as Node).is_queued_for_deletion()).size()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var after_four: int = copies.filter(func(c: Variant) -> bool: return is_instance_valid(c)).size()
	check("  then CLEAR_EACH_FRAME a frame are freed, and soon all", after_one == 90 - Spawner.CLEAR_EACH_FRAME
		and after_four == 0 and Spawner.clearing() == 0, [after_one, after_four, Spawner.clearing()])
	holder.queue_free()
	print("  the Testing Ground clears in parts")


# PARTICLE CLOUDS DRAWN TOGETHER, ON THE CARD (0.174.4). The owner, of his
# card's Every effect sweep: "we need to majorly refine mages meteor and
# mages spike and dynamite". A meteor, a blast and a burning crater each had
# CPUParticles2D of their own, worked out by the processor and drawn one by
# one; fxparticles.gd draws every cloud of a layer in one draw and works out
# each particle on the card (fxparticles.gdshader).
func _test_particles_are_drawn_together() -> void:
	section("PARTICLE CLOUDS DRAWN TOGETHER, ON THE CARD (0.174.4)")
	const Fx := preload("res://src/shared/fxparticles.gd")
	var room := Node2D.new()
	add_child(room)
	var far := Vector2(-41000, -41000)
	var blast: Blast = Blast.spawn(room, far, &"dynamite", 40.0, false)
	var clouds: Array = blast.get_children().filter(func(n: Node) -> bool: return n is _FxEmitterCode)
	var smoke: _FxEmitterCode = clouds[0] if clouds.size() == 3 else null
	var fire: _FxEmitterCode = clouds[1] if clouds.size() == 3 else null
	var sparks: _FxEmitterCode = clouds[2] if clouds.size() == 3 else null
	check("a stick's blast is three clouds, and the smoke, told to wait its beat, has let nothing out yet",
		smoke != null and not smoke.emitting and smoke.fx_t1 < smoke.fx_t0, clouds.size())
	await get_tree().process_frame
	await get_tree().process_frame
	var drawer: Node = Fx.of(room)
	var groups: Dictionary = drawer.get("_groups") if drawer != null else {}
	check("  all three drawn by the one drawer: the smoke and fire's puffs in one layer, the smoke first (behind the fire, as before), the sparks in another",
		drawer != null and fire != null and smoke.fx_drawer == drawer and fire.fx_group == smoke.fx_group
		and smoke.fx_slot >= 0 and smoke.fx_slot < fire.fx_slot and sparks.fx_group != fire.fx_group
		and groups.has(fire.fx_group) and (groups[fire.fx_group]["mmi"] as MultiMeshInstance2D).texture == fire.texture,
		[smoke.fx_slot if smoke else -1, fire.fx_slot if fire else -1])
	var rows: int = (drawer.get("_params_rows") as Dictionary).size() if drawer != null else -1
	var again: Blast = Blast.spawn(room, far + Vector2(200, 0), &"dynamite", 40.0, false)
	await get_tree().process_frame
	check("  a second blast like it shares their rows of numbers: nothing new is sent to the card",
		drawer != null and (drawer.get("_params_rows") as Dictionary).size() == rows, rows)

	var crater: BurningCrater = BurningCrater.spawn(room, far + Vector2(0, 300), 10, 40.0, null)
	crater.set_physics_process(false)
	await get_tree().process_frame
	var flames: _FxEmitterCode = crater.get_node_or_null(^"flames") as _FxEmitterCode
	check("a crater's flames, given their puff once they had joined, are drawn as puffs - in the puff's layer",
		flames != null and flames.texture != null and groups.has(flames.fx_group)
		and (groups[flames.fx_group]["mmi"] as MultiMeshInstance2D).texture == flames.texture
		and (groups[flames.fx_group]["mat"] as ShaderMaterial).get_shader_parameter(&"textured") == true)

	var meteor: Meteor = (load("res://scene/projectiles/meteor.tscn") as PackedScene).instantiate()
	meteor.cosmetic = true
	room.add_child(meteor)
	meteor.global_position = far + Vector2(300, 300)
	meteor.set_physics_process(false)
	await get_tree().process_frame
	meteor.advance(Meteor.FALL_SECONDS * 0.25)
	await get_tree().process_frame
	for i in 3:
		meteor.advance(Meteor.FALL_SECONDS * 0.05)
		await get_tree().process_frame
	var moving: Dictionary = drawer.get("_moving")
	check("a falling meteor's trails and sparks glide down with the stone on the card: none of them moves or is written as it falls",
		meteor.trail.gliding() and meteor.trail.position == Vector2.ZERO and not moving.has(meteor.trail)
		and not moving.has(meteor.smoke_trail) and not moving.has(meteor.get_node(^"whirl")),
		[meteor.trail.position, moving.size()])
	check("  its ring of fire narrows in steps, every meteor's the same, so its rows are shared",
		Meteor.SWIRL_STEPS <= 16.0
		and _func_body(_code_src("res://src/projectiles/meteor.gd"), "func _fall(").contains("floorf(t * SWIRL_STEPS) / SWIRL_STEPS"))

	var frost: Blast = Blast.spawn(room, far + Vector2(0, 600), &"stalagmite", 30.0, false)
	await get_tree().process_frame
	var marks: Array = room.get_children().filter(func(n: Node) -> bool: return n.get_node_or_null(^"twinkles") != null)
	var glints: _FxEmitterCode = (marks[0] as Node).get_node(^"twinkles") as _FxEmitterCode if not marks.is_empty() else null
	if glints != null:
		(marks[0] as CanvasItem).modulate.a = 0.5
	for i in Fx.FADE_TURNS:
		await get_tree().process_frame
	check("a frost mark's glints fade with the mark, drawn unshaded as before",
		glints != null and glints.follow_fades and is_equal_approx(glints.fx_alpha, 0.5)
		and (groups[glints.fx_group]["mat"] as ShaderMaterial).shader == Fx.UNSHADED_SHADER, glints.fx_alpha if glints else -1.0)

	# A layer of its own (a z index nothing else uses), forty clouds, every
	# other one gone: it closes up, in the order they were made.
	var made: Array = []
	for i in 40:
		var e := _FxEmitterCode.new()
		e.z_as_relative = false
		e.z_index = 37
		e.set_meta(&"made", i)
		room.add_child(e)
		made.append(e)
	await get_tree().process_frame
	var layer: String = (made[0] as _FxEmitterCode).fx_group
	for i in range(0, 40, 2):
		(made[i] as Node).free()
	var kept: Array = []
	var held: Array = groups[layer]["emitters"] if groups.has(layer) else []
	for slot in int(groups[layer]["high"]) if groups.has(layer) else 0:
		kept.append(int((held[slot] as Node).get_meta(&"made")))
	check("leaving frees a cloud's slot, and a layer more than half empty closes up, in the order its clouds were made",
		groups.has(layer) and int(groups[layer]["high"]) == 20 and kept == range(1, 40, 2), kept)
	var lone: _FxEmitterCode = made[1]
	var started: int = int(drawer.get("rows_started_again"))
	for i in Fx.MOST_ROWS + 1:
		lone.spread = 1.0 + float(i) * 0.01
		drawer.call("_write", lone, Vector2.ZERO)
	await get_tree().process_frame
	check("a cloud whose numbers keep changing takes a row each time, and past MOST_ROWS every row is let go and written again",
		int(drawer.get("rows_started_again")) == started + 1
		and (drawer.get("_params_rows") as Dictionary).size() < 64, (drawer.get("_params_rows") as Dictionary).size())

	var no_cpu: Array = []
	for path in ["res://src/projectiles/meteor.gd", "res://src/projectiles/blast.gd", "res://src/projectiles/burningcrater.gd"]:
		if _code_src(path).contains("CPUParticles2D.new()"):
			no_cpu.append(path.get_file())
	if FileAccess.get_file_as_string("res://scene/projectiles/meteor.tscn").contains("type=\"CPUParticles2D\""):
		no_cpu.append("meteor.tscn")
	check("the meteor, its blast and its crater make no CPUParticles2D now", no_cpu.is_empty(), no_cpu)
	room.queue_free()
	blast.queue_free()
	again.queue_free()
	frost.queue_free()
	await get_tree().process_frame
	print("  particle clouds drawn together")


# ROOM FOR 10,000, AND SHOTS HELD FOR THE WHOLE SWEEP (0.175.0). The owner,
# in the Testing Ground: "we were able to spawn 5k slimes no frame loss lets
# try 10,000", and of Every shot, "arrows vanishing faster then they spawn".
func _test_ten_thousand_in_the_testing_ground() -> void:
	section("ROOM FOR 10,000 IN THE TESTING GROUND; SHOTS HELD FOR THE WHOLE SWEEP (0.175.0)")
	const SwarmScript := preload("res://src/world/endless/swarm.gd")
	const RunScript := preload("res://src/world/endless/endlessrun.gd")
	const Ground := preload("res://src/world/endless/testingground.gd")
	const Sweep := preload("res://src/world/endless/limitsweep.gd")
	const Kinds := preload("res://src/world/endless/stresskinds.gd")
	check("the swarm holds 10,000, the Testing Ground has a 10,000 horde and its sweep goes that far",
		SwarmScript.MOST == 10000 and int(Ground.HORDES.back()) == 10000
		and Sweep.most_for({"horde": true}) == 10000)
	check("  an Endless run still brings 5,000 at most, a party and a phone as before",
		SwarmScript.RUN_MOST == 5000 and RunScript.stage_crowd(60) == 5000 and RunScript.crowd_for(60, 4) == 5000
		and RunScript.PHONE_CROWD == 1000)
	var o := Vector2(-61000, -61000)
	var swarm: Node2D = SwarmScript.new()
	swarm.set("arena", Rect2(o, Vector2(1488, 1334)))
	add_child(swarm)
	swarm.set_process(false)
	swarm.set_physics_process(false)
	await get_tree().process_frame
	var made: int = 0
	for i in 12:
		made += int(swarm.call("spawn", 1000, o - Vector2(500, 500)))
	check("  10,000 slimes fit in the swarm, and no more", made == 10000 and int(swarm.get("alive")) == 10000,
		[made, int(swarm.get("alive"))])
	swarm.queue_free()
	# The longest a shot sweep can run: every step's settling and its
	# measuring, at a slow 20 frames a second.
	var steps: int = ceili(float(Kinds.SHOT_MOST) / float(Kinds.SHOT_STEP))
	var longest: float = float(steps) * (Sweep.SETTLE_SECONDS + float(Sweep.MEASURE_FRAMES) / 20.0)
	check("a swept shot outlasts the longest shot sweep and drifts under 200 px in it, so none goes before it is counted",
		Kinds.HELD_LIFE > longest and Kinds.HELD_SPEED > 0.0 and Kinds.HELD_SPEED * Kinds.HELD_LIFE <= 200.0,
		[Kinds.HELD_LIFE, longest, Kinds.HELD_SPEED * Kinds.HELD_LIFE])
	var me := Node2D.new()
	add_child(me)
	me.global_position = o + Vector2(3000, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var swept: Dictionary = Kinds.shots()[1]
	Kinds.make_shots(get_tree(), swept, 5, me.global_position, rng)
	var held: Array = get_tree().get_nodes_in_group(Kinds.GROUP).filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	var right: int = 0
	for shot in held:
		if is_equal_approx(float(shot.get("lifetime")), Kinds.HELD_LIFE) and is_equal_approx(float(shot.get("speed")), Kinds.HELD_SPEED):
			right += 1
	check("  an ice arrow swept is made to last HELD_LIFE at HELD_SPEED", held.size() == 5 and right == 5, [held.size(), right])
	Kinds.clear(get_tree())
	me.queue_free()
	await get_tree().process_frame
	print("  room for 10,000; shots held for the whole sweep")


# THE TESTING GROUND AT A GLANCE (0.175.1). The owner, of its panel: "upgrade
# this ui". The work a bar, the horde chosen lit, Find the limit green and
# Stop red, a card while it sweeps, every result in a table.
func _test_the_testing_ground_at_a_glance() -> void:
	section("THE TESTING GROUND AT A GLANCE (0.175.1)")
	const Sweep := preload("res://src/world/endless/limitsweep.gd")
	const Bar := preload("res://src/world/endless/workbar.gd")
	var box := VBoxContainer.new()
	add_child(box)
	var sweep: Node = Sweep.new()
	sweep.set("save_path", "")
	add_child(sweep)
	sweep.call("build", box, 460.0)
	var results: Dictionary = {}
	var order: Array = []
	for k in 12:
		var named: String = "Monster %d" % k
		results[named] = {"label": named, "each": 0.01 * float(k + 1), "fits": 40 + 60 * k, "why": "limit" if k % 3 else "most",
			"grows": k == 5, "per": "out", "stopped": 100, "base": 1.0, "budget": 16.7, "when": "t%d" % k}
		order.append(named)
	sweep.set("results", results)
	sweep.set("order", order)
	sweep.call("paint")
	var rows_box: Node = box.find_child("sweepresults", true, false)
	var first: Control = box.find_child("result0", true, false) as Control
	var newest: String = str((first.find_child("name", true, false) as Label).text) if first != null else ""
	var scroll: ScrollContainer = box.find_child("sweepscroll", true, false) as ScrollContainer
	check("every result is a row of the table, newest first - all twelve, not five and \"... and 7 more\" - and eight show before the scroll",
		rows_box != null and rows_box.get_child_count() == 12 and newest == "Monster 11"
		and is_equal_approx(scroll.custom_minimum_size.y, Sweep.ROW_HEIGHT * float(Sweep.ROWS_SHOWN)),
		[rows_box.get_child_count() if rows_box else -1, newest])
	var row5: Control = box.find_child("result6", true, false) as Control
	check("  a row: its name, ms each, a fits bar and number, what stopped it in a word; the whole sentence on a hover; a rising cost marked",
		row5 != null and (row5.find_child("each", true, false) as Label).text == Sweep.ms_text(0.06)
		and (row5.find_child("fits", true, false) as Label).text == "340" and (row5.find_child("why", true, false) as Label).text == "80%"
		and row5.tooltip_text == Sweep.summary_line(results["Monster 5"])
		and (row5.find_child("grows", true, false) as Control).visible
		and not ((box.find_child("result0", true, false) as Control).find_child("grows", true, false) as Control).visible,
		row5.tooltip_text if row5 else "")
	check("  fits on a log scale with a colour - few red, some amber, many green; what stopped it said short",
		is_equal_approx(Sweep.fits_fraction(5000, 5000), 1.0) and Sweep.fits_fraction(80, 5000) > 0.4
		and Sweep.fits_fraction(80, 5000) < 0.6 and Sweep.fits_colour(79) == Bar.RED and Sweep.fits_colour(127) == Bar.AMBER
		and Sweep.fits_colour(2500) == Bar.GREEN and Sweep.short_why("slow") == "slow" and Sweep.short_why("base") == "too busy")
	var go: Button = box.find_child("sweepgo", true, false) as Button
	var card: Control = box.find_child("sweepcard", true, false) as Control
	var idle_green: bool = (go.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.g > (go.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.r
	var idle_card: bool = card.visible
	sweep.set("target", {"label": "Skeleton elite", "path": "x", "kind": 2})
	sweep.set("queue", [{}, {}, {}, {}])
	sweep.set("queue_size", 11)
	sweep.set("phase", Sweep.Phase.MEASURING)
	sweep.set("rows", [[0, 2.0, 2.2, 100, 0.5, 0.8, 0.7], [70, 7.9, 8.7, 100, 3.0, 2.9, 2.0]])
	sweep.call("_say", "measuring 120 frames")
	var work_bar: Control = box.find_child("sweepworkbar", true, false) as Control
	var budget: float = PerfOverlay.budget_ms()
	check("while it sweeps: Stop in red, and a card - what, 7 of 11, its work against the 80% line, what it is doing",
		not idle_card and idle_green and go.text == "Stop"
		and (go.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.r > (go.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.g
		and card.visible and (box.find_child("sweepname", true, false) as Label).text == "Skeleton elite"
		and (box.find_child("sweepof", true, false) as Label).text == "7 of 11"
		and is_equal_approx(float(work_bar.get("fraction")), 7.9 / budget) and is_equal_approx(float(work_bar.get("tick")), Sweep.LIMIT_AT)
		and (box.find_child("sweepdoing", true, false) as Label).text == "measuring 120 frames",
		[go.text, card.visible])
	sweep.set("phase", Sweep.Phase.IDLE)
	sweep.call("paint")
	var chosen := Button.new()
	chosen.toggle_mode = true
	Bar.dress_choice(chosen)
	check("  the horde's chosen size lit gold, and the work a bar in green, amber or red as before",
		(chosen.get_theme_stylebox("pressed") as StyleBoxFlat).bg_color.is_equal_approx(Color(Bar.GOLD, 0.9))
		and Bar.work_colour(10.0, 12.0, 16.67) == Bar.GREEN and Bar.work_colour(10.0, 14.0, 16.67) == Bar.AMBER
		and Bar.work_colour(10.0, 17.0, 16.67) == Bar.RED and not card.visible)
	chosen.free()
	sweep.queue_free()
	box.queue_free()
	await get_tree().process_frame
	print("  the testing ground at a glance")


# THE SMITH'S HOUSE (0.175.1). The owner, with Ahvassa's round house, its
# inside and its forge: "blacksmiths house". The general store's rules: walk
# in and the walls and roof give way to the room; its trigger is the round
# floor (shop.gd covers() reads a polygon too).
func _test_the_smith_has_a_house() -> void:
	section("THE SMITH'S HOUSE (0.175.1)")
	const ShopScript := preload("res://src/world/shop.gd")
	var packed: PackedScene = load("res://scene/walls/smithhouse.tscn") as PackedScene
	check("smithhouse.tscn loads", packed != null and packed.can_instantiate())
	if packed == null:
		return
	var house: Node2D = packed.instantiate() as Node2D
	var first_strip: Sprite2D = house.get_node("smithexterior/house").get_child(0) as Sprite2D
	var sheet: Texture2D = first_strip.texture if first_strip != null else null
	check("  drawn from Ahvassa's sheet, art/shophouses/smithhouse.png, nearest-neighbour",
		sheet != null and sheet.resource_path == "res://art/shophouses/smithhouse.png"
		and first_strip.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
	var anvils: Array = []
	_collect_by_script(house, "res://src/world/anvil.gd", anvils)
	check("  its anvil is the smith's, beside the forge, drawn by its own picture - Ahvassa's anvil on its stump",
		anvils.size() == 1 and ((anvils[0] as Node).get_node("animatedsprite2d") as CanvasItem).visible
		and house.get_node_or_null("interiorfurniture/forge") is Sprite2D
		and house.get_node_or_null("interiorfurniture/stump") == null)
	house.position = Vector2(-63000, -63000)
	add_child(house)
	await get_tree().process_frame
	var trigger: Area2D = house.get_node("trigger") as Area2D
	var outside: bool = (house.get_node("smithexterior") as CanvasItem).visible \
		and not (house.get_node("smithinterior") as CanvasItem).visible and not (house.get_node("interiorfurniture") as CanvasItem).visible
	var walker := Node2D.new()
	walker.add_to_group(&"player")
	trigger.call("_on_body_entered", walker)
	var inside: bool = not (house.get_node("smithexterior") as CanvasItem).visible \
		and (house.get_node("smithinterior") as CanvasItem).visible and (house.get_node("interiorfurniture") as CanvasItem).visible
	trigger.call("_on_body_exited", walker)
	var out_again: bool = (house.get_node("smithexterior") as CanvasItem).visible
	walker.free()
	check("outside, the house; walk in and the room with its forge; walk out and the house again",
		outside and inside and out_again, [outside, inside, out_again])
	var floor_box: Node2D = trigger.get_node("collisionshape2d") as Node2D
	var o: Vector2 = house.global_position
	check("  its trigger is the round floor: the middle and by the walls are in, the doorstep and past the walls are not",
		ShopScript.covers(floor_box, o + Vector2(0, -43)) and ShopScript.covers(floor_box, o + Vector2(-60, -43))
		and not ShopScript.covers(floor_box, o + Vector2(0, -2)) and not ShopScript.covers(floor_box, o + Vector2(-75, -10))
		and not ShopScript.covers(floor_box, o + Vector2(0, -95)))
	var store_box := CollisionShape2D.new()
	var square := RectangleShape2D.new()
	square.size = Vector2(20, 10)
	store_box.shape = square
	add_child(store_box)
	store_box.global_position = Vector2(500, 500)
	check("  and the general store's rectangle reads as before",
		ShopScript.covers(store_box, Vector2(509, 504)) and not ShopScript.covers(store_box, Vector2(511, 500)))
	store_box.queue_free()
	var ring: CollisionPolygon2D = house.get_node("walls/ring") as CollisionPolygon2D
	var gap_open: bool = not Geometry2D.is_point_in_polygon(Vector2(0, -3), ring.polygon)
	var wall_solid: bool = Geometry2D.is_point_in_polygon(Vector2(-40, -10), ring.polygon) \
		and Geometry2D.is_point_in_polygon(Vector2(0, -83), ring.polygon) and Geometry2D.is_point_in_polygon(Vector2(74, -43), ring.polygon)
	check("  its round wall is solid but for the door", gap_open and wall_solid, [gap_open, wall_solid])
	var town: Node = (load("res://scene/elusion.tscn") as PackedScene).instantiate()
	var in_town: Node = town.get_node_or_null("ysortworld/interactables/smithhouse")
	check("  it stands in town, beside the general store", in_town is Node2D and town.get_node_or_null("ysortworld/interactables/shophouse") != null)
	town.free()
	house.queue_free()
	await get_tree().process_frame
	print("  the smith's house")
	_test_bodies_sort_round_the_smith()


# EVERY BODY IS DRAWN IN FRONT OF WHAT IT STANDS IN FRONT OF (0.175.1). The
# owner, of the smith's house and the Forge's new anvil: "fix the layering
# also make sure everything is perfect". The house is round: drawn as one
# picture sorted at its lowest point, anybody standing in front of its sides
# - where the wall curves back up to y -40 - sorted north of y 0 and the whole
# house was drawn over them; inside, its two front walls did the same. Each is
# upright strips now, every strip sorted at the foot of the wall in it. And
# the tank sorted 5 px above his soles (his picture at -23, his soles at -18),
# so walked up to a short prop from the south he could still be drawn under
# it; his picture is placed at his soles now and drawn where it was.
# Worked out from the scenes, for every class: touching each piece from the
# south it sorts after it, from the north (or from inside the wall) before.
func _test_bodies_sort_round_the_smith() -> void:
	section("LAYERING (0.175.1): every class in front of the smith's round wall, its furniture and the anvil when it stands in front, behind when behind")
	var house: Node2D = (load("res://scene/walls/smithhouse.tscn") as PackedScene).instantiate() as Node2D
	var sheet: Image = (load("res://art/shophouses/smithhouse.png") as Texture2D).get_image()
	var wrong: Array = []
	# ---- every strip sorted at the foot of the wall in it ----
	var strips: Array = []
	for group in ["smithexterior/house", "smithinterior"]:
		for strip in house.get_node(group).get_children():
			var cut := strip as Sprite2D
			if cut == null or cut.z_index < 0:
				continue
			strips.append(cut)
			var region: Rect2i = Rect2i(cut.region_rect)
			for c in region.size.x:
				var foot: float = INF
				for r in range(region.size.y - 1, -1, -1):
					if sheet.get_pixel(region.position.x + c, region.position.y + r).a > 0.0:
						foot = cut.position.y + cut.offset.y + r + 1
						break
				# The sign and the eave hang off the wall at its widest (y -43).
				var x: float = cut.position.x + c
				if absf(x) > 77.0:
					foot = -43.0
				if foot < cut.position.y - 0.01:
					wrong.append("%s sorts at %.0f, south of the wall's foot at x %.0f (%.0f)" % [cut.name, cut.position.y, x, foot])
	check("the house and its two front walls are upright strips, each sorted at the foot of the wall in it (none south of it)",
		strips.size() > 20 and house.get_node("smithexterior").y_sort_enabled and house.get_node("smithexterior/house").y_sort_enabled
		and house.get_node("smithinterior").y_sort_enabled and wrong.is_empty(), wrong.slice(0, 4))
	# ---- each class's height it sorts at, and the top and bottom of its feet ----
	var classes: Dictionary = {}
	for cls in ["warrior", "mage", "healer", "tank"]:
		var hero: Node2D = (load("res://scene/characters/%s.tscn" % cls) as PackedScene).instantiate() as Node2D
		var body: CollisionShape2D = hero.get_node(^"bodyshape") as CollisionShape2D
		var picture: Node2D = hero.get_node(^"animatedsprite2d") as Node2D
		var half: float = 0.0
		if body.shape is CircleShape2D:
			half = (body.shape as CircleShape2D).radius
		elif body.shape is CapsuleShape2D:
			half = (body.shape as CapsuleShape2D).height * 0.5
		classes[cls] = {"sort": picture.position.y if hero.y_sort_enabled else 0.0,
			"top": body.position.y - half, "bottom": body.position.y + half}
		hero.free()
	# ---- the round wall: in front of it from the street, behind it from inside ----
	var ring: PackedVector2Array = (house.get_node("walls/ring") as CollisionPolygon2D).polygon
	wrong = []
	for x in range(-76, 77):
		var crossings: Array = []
		for i in ring.size():
			var p: Vector2 = ring[i]
			var q: Vector2 = ring[(i + 1) % ring.size()]
			if (p.x - x) * (q.x - x) < 0.0 or (is_equal_approx(p.x, x) and q.x != p.x):
				crossings.append(lerpf(p.y, q.y, (x - p.x) / (q.x - p.x)))
		if crossings.size() < 4:
			continue
		crossings.sort()
		var outer_front: float = crossings[crossings.size() - 1]
		var inner_front: float = crossings[crossings.size() - 2]
		for cut in strips:
			var c: Sprite2D = cut as Sprite2D
			if float(x) < c.position.x or float(x) >= c.position.x + c.region_rect.size.x:
				continue
			for cls in classes:
				var k: Dictionary = classes[cls]
				var in_front: float = outer_front + float(k["sort"]) - float(k["top"])
				var inside: float = inner_front + float(k["sort"]) - float(k["bottom"])
				if in_front <= c.position.y:
					wrong.append("%s in front of the wall at x %d sorts at %.1f, under %s (%.0f)" % [cls, x, in_front, c.name, c.position.y])
				if inside >= c.position.y:
					wrong.append("%s inside at x %d sorts at %.1f, over %s (%.0f)" % [cls, x, inside, c.name, c.position.y])
	check("  every class walked up to the round wall from the street is drawn in front of it, and from inside behind its front walls",
		wrong.is_empty(), wrong.slice(0, 4))
	# ---- the furniture and the anvil: in front from the south, behind from the north ----
	var props: Array = []
	for piece in ["forge", "workbench", "barrel", "crate"]:
		props.append([piece, (house.get_node("interiorfurniture/" + piece) as Node2D).position.y,
			house.get_node("walls/" + piece) as CollisionShape2D, 0.0])
	var anvil: Node2D = house.get_node("interiorfurniture/anvil") as Node2D
	props.append(["anvil", anvil.position.y, anvil.get_node("body/collision") as CollisionShape2D, anvil.position.y])
	wrong = []
	for prop in props:
		var shape: CollisionShape2D = prop[2]
		var half: float = 0.0
		if shape.shape is RectangleShape2D:
			half = (shape.shape as RectangleShape2D).size.y * 0.5
		elif shape.shape is CircleShape2D:
			half = (shape.shape as CircleShape2D).radius
		var centre: float = shape.position.y + float(prop[3])
		for cls in classes:
			var k: Dictionary = classes[cls]
			var south: float = centre + half + float(k["sort"]) - float(k["top"])
			var north: float = centre - half + float(k["sort"]) - float(k["bottom"])
			if south <= float(prop[1]) or north >= float(prop[1]):
				wrong.append("%s by the %s: %.1f / %.1f against %.1f" % [cls, prop[0], south, north, prop[1]])
	check("  every class is drawn in front of the forge, bench, barrel, crate and anvil from the south, behind them from the north",
		wrong.is_empty(), wrong)
	var tank: Node2D = (load("res://scene/characters/tank.tscn") as PackedScene).instantiate() as Node2D
	var tank_picture: AnimatedSprite2D = tank.get_node(^"animatedsprite2d") as AnimatedSprite2D
	check("  the tank's picture sorts at his soles (y -18), drawn where it was (-39)",
		is_equal_approx(float(classes["tank"]["sort"]), -18.0)
		and is_equal_approx(tank_picture.position.y + tank_picture.offset.y, -39.0), tank_picture.position)
	tank.free()
	house.free()


func _shares_material(beam: Node2D) -> bool:
	var other: Node2D = (load("res://src/characters/healerlaser.gd") as GDScript).call("make") as Node2D
	var same: bool = other.material == beam.material
	other.free()
	return same


# THE GOLD STAFF (0.175.1). The owner, of Ahvassa's three staffs: "the gold one
# is mythic it will use the red crit laser from healers run", then "we need to
# optimize the laser and put the other 2 weapons on standby". The beam alone
# in a world (a healer's _ready() is the camera, the pets and the save), the
# healer's half by its own functions, and the picture others see.
func _test_the_gold_staff_shines() -> void:
	section("THE GOLD STAFF (0.175.1): the healer's mythic shines the Healer's Run's red laser - everything in it struck once a tick, the red heart double")
	const HealerScript := preload("res://src/characters/healer.gd")
	const Laser := preload("res://src/characters/healerlaser.gd")
	const RunScript := preload("res://src/world/healerrun/healerrun.gd")
	var staff: ItemData = ItemRegistry.get_item("goldstaff")
	check("the Gold Staff: the healer's tier 6 weapon, whose attack is the LASER (appended: 4)",
		staff != null and staff.tier == 6 and staff.required_classes == ["healer"]
		and int(staff.weapon_attack) == ItemData.WeaponAttack.LASER and ItemData.WeaponAttack.LASER == 4,
		[staff.tier, staff.weapon_attack] if staff != null else null)
	var arena := Node2D.new()
	arena.name = "lasertest"
	add_child(arena)
	var o := Vector2(-81000, -81000)
	var foes: Array = []
	var make_foe := func(at: Vector2, named_shape: bool = true, aimable: bool = true) -> Node2D:
		var script := GDScript.new()
		script.source_code = "extends Node2D\nvar taken: Array = []\nvar aimable: bool = true\n" \
			+ "func take_damage(amount: int, _element: int = 0) -> void:\n\ttaken.append(amount)\n" \
			+ "func can_be_aimed_at() -> bool:\n\treturn aimable\n"
		script.reload()
		var foe := Node2D.new()
		foe.set_script(script)
		foe.set("aimable", aimable)
		foe.add_to_group(&"enemies")
		var box := Area2D.new()
		box.name = "hurtbox"
		box.collision_layer = 8
		box.collision_mask = 0
		box.monitoring = false
		var shape := CollisionShape2D.new()
		if named_shape:
			shape.name = "collisionshape2d"
		var circle := CircleShape2D.new()
		circle.radius = 8.0
		shape.shape = circle
		box.add_child(shape)
		foe.add_child(box)
		arena.add_child(foe)
		foe.global_position = o + at
		foes.append(foe)
		return foe
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var wall_shape := CollisionShape2D.new()
	var block := RectangleShape2D.new()
	block.size = Vector2(10, 200)
	wall_shape.shape = block
	wall.add_child(wall_shape)
	arena.add_child(wall)
	wall.global_position = o + Vector2(160, 0)
	var on_line: Node2D = make_foe.call(Vector2(40, 0))
	var in_red: Node2D = make_foe.call(Vector2(70, 9))
	var beside: Node2D = make_foe.call(Vector2(100, 12.5))
	var stand_in: Node2D = make_foe.call(Vector2(130, -2), false)
	var wide: Node2D = make_foe.call(Vector2(60, 30))
	var behind: Node2D = make_foe.call(Vector2(-40, 0))
	var past_wall: Node2D = make_foe.call(Vector2(200, 0))
	var caged: Node2D = make_foe.call(Vector2(50, -3), true, false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var beam: Node2D = Laser.make()
	arena.add_child(beam)
	beam.call("shine", true)
	beam.call("aim", o, Vector2.RIGHT)
	check("it shines to the first wall, short of it, not through it",
		float(beam.get("length")) > 140.0 and float(beam.get("length")) < 155.0, beam.get("length"))
	var struck: int = int(beam.call("strike", 10, 20))
	check("  one tick strikes everything standing in it once: the red heart double, the rest the orb's damage",
		struck == 4 and on_line.get("taken") == [20] and in_red.get("taken") == [20] and beside.get("taken") == [10]
		and stand_in.get("taken") == [20], [struck, on_line.get("taken"), in_red.get("taken"), beside.get("taken"), stand_in.get("taken")])
	check("  nothing beside it, behind her, past the wall, or that may not be aimed at",
		(wide.get("taken") as Array).is_empty() and (behind.get("taken") as Array).is_empty()
		and (past_wall.get("taken") as Array).is_empty() and (caged.get("taken") as Array).is_empty())
	check("  a swarm's stand-in, whose shape has no name, is read by its first shape",
		stand_in.get("taken") == [20])
	beam.call("strike", 10, 20, true)
	check("  and the owner's Always roll makes every one in it double",
		beside.get("taken") == [10, 20], beside.get("taken"))
	var focus: Array = get_tree().get_nodes_in_group(&"swarm_focus").filter(func(n: Node) -> bool: return beam.is_ancestor_of(n))
	var covered: bool = focus.size() == Laser.FOCUS_POINTS
	for f in focus:
		var spot: Vector2 = (f as Node2D).global_position - o
		covered = covered and absf(spot.y) < 0.01 and spot.x > 0.0 and spot.x < float(beam.get("length")) \
			and float(f.call("swarm_reach")) * 2.0 * Laser.FOCUS_POINTS >= float(beam.get("length"))
	check("  the Endless's swarm is asked for stand-ins all along it while it shines",
		covered, focus.size())
	beam.call("shine", false)
	var after: Array = get_tree().get_nodes_in_group(&"swarm_focus").filter(func(n: Node) -> bool: return beam.is_ancestor_of(n))
	check("  and for none once it is let go", after.is_empty() and not beam.visible and int(beam.call("strike", 10, 20)) == 0)
	check("its look is the run's: its five colours, its red heart and the fade, one unshaded material shared by every beam",
		Laser.LAYERS == 5 and RunScript.LASER_COLOURS.size() >= 5 and is_equal_approx(Laser.RED_SHARE, RunScript.CRIT_HEART[1])
		and beam.material is CanvasItemMaterial and (beam.material as CanvasItemMaterial).light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED
		and _shares_material(beam) and beam.z_index == Laser.Z and not beam.z_as_relative)
	var laser_src: String = _code_src("res://src/characters/healerlaser.gd")
	check("  cheap: redrawn only when its length moves, its shimmer is its own scale, one shape query a tick",
		_func_body(laser_src, "func _process(").contains("scale = ") and not _func_body(laser_src, "func _process(").contains("queue_redraw")
		and _func_body(laser_src, "func _set_length(").contains("queue_redraw()")
		and _func_body(laser_src, "func strike(").count("intersect_shape(") == 1
		and not _func_body(laser_src, "func strike(").contains(".new("))

	# ---- the healer's half ----
	var healer: Node2D = (load("res://scene/characters/healer.tscn") as PackedScene).instantiate() as Node2D
	healer.set("equipped", {"weapon": "goldstaff"})
	var wields: bool = healer.call("wields_laser")
	healer.set("equipped", {"weapon": "emberscepter"})
	var ember: bool = healer.call("wields_laser")
	healer.set("equipped", {"weapon": "goldstaff"})
	healer.set("max_mana", 50)
	healer.set("mana", 50)
	healer.call("_laser_tick", Vector2.RIGHT)
	check("a healer with the Gold Staff shines it, with anything else throws orbs; a tick costs the orb's mana and makes the beam once, hers",
		wields and not ember and int(healer.get("mana")) == 50 - int(healer.get("mana_cost_per_shot"))
		and healer.get_node_or_null(^"laser") != null and healer.call("laser") == healer.get_node(^"laser"),
		[wields, ember, healer.get("mana")])
	healer.free()
	var healer_src: String = _code_src("res://src/characters/healer.gd")
	var physics_body: String = _func_body(healer_src, "func _physics_process(")
	var tick_body: String = _func_body(healer_src, "func _laser_tick(")
	check("  on the orbs' own clock in place of them, an orb's damage and the double in the red - the server's books unchanged",
		physics_body.find("_hold_laser()") >= 0 and physics_body.find("_hold_laser()") < physics_body.find("_fire_projectile()")
		and _func_body(healer_src, "func _hold_laser(").contains("_shot_timer = hasten(shot_cooldown)")
		and tick_body.contains("\"strike\", hit, hit * DOUBLE_HIT") and tick_body.count("mana -=") == 1
		and tick_body.contains("Presence.tell_attack(\"laser\""))

	# ---- the picture everyone else sees ----
	var body := Node2D.new()
	arena.add_child(body)
	body.global_position = o + Vector2(0, 300)
	var made: Array = RemoteAttacks.fire(body, ["laser", 0, o.x, o.y + 300.0, o.x + 120.0, o.y + 300.0, 0, 0])
	var picture: Node2D = body.get_node_or_null(^"laser") as Node2D
	if RemoteAttacks.shown():
		var again: Array = RemoteAttacks.fire(body, ["laser", 0, o.x, o.y + 300.0, o.x + 90.0, o.y + 300.0, 0, 0])
		check("another healer's beam is drawn here: one picture, from where theirs started to where it ended, each tick they tell",
			made.size() == 1 and picture != null and again.size() == 1 and again[0] == picture and picture.visible
			and bool(picture.get("cosmetic")) and is_equal_approx(float(picture.get("length")), 90.0), [made, picture])
		check("  it strikes nothing here and asks the swarm for nothing",
			int(picture.call("strike", 10, 20)) == 0
			and get_tree().get_nodes_in_group(&"swarm_focus").filter(func(n: Node) -> bool: return picture.is_ancestor_of(n)).is_empty())
		picture.call("_process", Laser.SHOW_SECONDS + 0.01)
		check("  and goes when they stop telling", not picture.visible)
	else:
		check("another healer's beam: attack pictures are switched off here", made.is_empty())
	arena.queue_free()
	await get_tree().process_frame
	print("  the gold staff")


func _test_the_crowned_costs_less() -> void:
	section("THE CROWNED, MEASURED AND CHEAPER (0.176.0): the Trap's stand-ins a few a tick, the Tear in one draw on the floor's turn, the eyes made ahead")
	const SwarmScript := preload("res://src/world/endless/swarm.gd")
	const Phases := preload("res://src/world/crowned/crownedphases.gd")
	const Fight := preload("res://src/world/crowned/crownedfight.gd")
	const QuadBatch := preload("res://src/enemies/quadbatch.gd")
	# ---- the swarm's stand-ins ----------------------------------------------------
	var by_loop := PackedFloat32Array()
	by_loop.resize(3 * 16)
	for at in range(0, by_loop.size(), 16):
		by_loop[at] = 1.0
		by_loop[at + 5] = 1.0
		by_loop[at + 11] = 1.0
	check("the swarm's still parts, made by doubling one instance, are the old loop's number for number - and a whole swarm's worth",
		SwarmScript.still_parts(3) == by_loop and SwarmScript.still_parts(SwarmScript.MOST).size() == SwarmScript.MOST * 16)
	var full: int = SwarmScript.PROXIES + SwarmScript.FOCUS_PROXIES
	var at_once: Node2D = SwarmScript.new()
	at_once.set("arena", Rect2(-90000, -90000, 800, 800))
	add_child(at_once)
	var gradual: Node2D = SwarmScript.new()
	gradual.set("arena", Rect2(-90000, -90000, 800, 800))
	gradual.set("proxies_a_tick", 24)
	add_child(gradual)
	gradual.set_physics_process(false)
	var first: int = (gradual.get("_proxies") as Array).size()
	gradual.call("_physics_process", 0.0125)
	var second: int = (gradual.get("_proxies") as Array).size()
	for _k in 20:
		gradual.call("_physics_process", 0.0125)
	check("  stand-ins: all %d as the swarm comes, or with proxies_a_tick 24 at first and 24 more a tick until all are made" % full,
		(at_once.get("_proxies") as Array).size() == full and first == 24 and second == 48
		and (gradual.get("_proxies") as Array).size() == full and (gradual.get("_shown") as Array).size() == full,
		[first, second, (gradual.get("_proxies") as Array).size()])
	at_once.queue_free()
	gradual.queue_free()
	var phases_alone: Node2D = Phases.new()
	phases_alone.set("room", Rect2(-90000, -90000, 800, 800))
	add_child(phases_alone)
	phases_alone.call("_make_horde")
	var horde: Node = phases_alone.get("swarm")
	check("  the Trap's horde makes them %d a tick (its slimes come in at %d a second)" % [Phases.HORDE_STAND_INS_A_TICK, int(Phases.HORDE_RATE)],
		horde != null and int(horde.get("proxies_a_tick")) == Phases.HORDE_STAND_INS_A_TICK and Phases.HORDE_STAND_INS_A_TICK > 0)
	phases_alone.call("_clear_horde")
	phases_alone.queue_free()
	# ---- the Tear ---------------------------------------------------------------------
	var batch := QuadBatch.new()
	batch.begin()
	var area := Rect2(10, 20, 128, 128)
	Phases._outline(batch, area, Color.WHITE, 3.0)
	var covered: float = 0.0
	var points: PackedVector2Array = batch.points
	for q in int(batch.size() / 2.0):
		var a: Vector2 = points[q * 4]
		var c: Vector2 = points[q * 4 + 2]
		covered += absf((c.x - a.x) * (c.y - a.y))
	var outer: Rect2 = area.grow(1.5)
	var inner: Rect2 = area.grow(-1.5)
	check("the Tear's outline in the batch is four bands, the corners once - the same ground a 3 px draw_rect outline covers",
		batch.size() == 8 and is_equal_approx(covered, outer.get_area() - inner.get_area()), [batch.size(), covered])
	var draw_body: String = _func_body(_code_src("res://src/world/crowned/crownedphases.gd"), "func _draw(")
	var tear_from: int = draw_body.find("tears.is_empty()")
	var tear_to: int = draw_body.find("batch.end(self)")
	var tear_part: String = draw_body.substr(tear_from, tear_to - tear_from) if tear_from != -1 and tear_to > tear_from else ""
	check("  every piece drawn into one triangle list (no draw call of its own), handed over once at the end",
		tear_part.contains("batch.begin()") and draw_body.count("batch.end(") == 1 and not tear_part.contains("batch.end(")
		and not tear_part.contains("draw_rect(") and not tear_part.contains("draw_circle(") and not tear_part.contains("draw_polyline("),
		[tear_from, tear_to])
	var step_body: String = _func_body(_code_src("res://src/world/crowned/crownedphases.gd"), "func step(")
	var redraw_body: String = _func_body(_code_src("res://src/world/crowned/crownedphases.gd"), "func redraw_floor(")
	check("  and drawn on the floor's turn while the Tear is open (every %d frames, as the arenas' floors), every frame otherwise" % QuadBatch.FLOOR_EVERY,
		step_body.contains("redraw_floor()") and not step_body.contains("queue_redraw()")
		and redraw_body.contains("phase != 4 or tears.is_empty() or QuadBatch.turn(self, QuadBatch.FLOOR_EVERY)"))
	# ---- the eyes, made ahead ----------------------------------------------------------
	var made: Dictionary = _crowned_test_room()
	var room: Node2D = made["room"]
	var floor_rect: Rect2 = made["floor"]
	var fight: Node2D = Fight.new()
	fight.set("room_rect", floor_rect)
	fight.set("player_override", made["body"])
	room.add_child(fight)
	var boss: Node2D = (load("res://scene/enemy/bossenemy.tscn") as PackedScene).instantiate() as Node2D
	boss.position = floor_rect.get_center()
	room.get_node("ysortworld/enemies").add_child(boss)
	boss.process_mode = Node.PROCESS_MODE_DISABLED
	fight.set_process(false)
	fight.set("boss", boss)
	fight.set("_decoy_left", Fight.DECOY_AHEAD + 0.2)
	fight.call("_step_decoys", 0.15)
	var before_due: int = (fight.get("decoys_ahead") as Array).size()
	for _k in 3:
		fight.call("_step_decoys", 0.2)
	var held: Array = (fight.get("decoys_ahead") as Array).duplicate()
	var hidden: bool = held.size() == Fight.DECOY_COUNT
	for decoy in held:
		hidden = hidden and not (decoy as Node2D).visible and not (decoy as Node).is_in_group(&"enemies") \
			and (decoy as Node).process_mode == Node.PROCESS_MODE_DISABLED and bool((decoy as Node).get("held"))
	check("the eyes: made in the second before they come, one a frame, each held - unseen, out of \"enemies\", nothing of it running",
		before_due == 0 and hidden, [before_due, held.size()])
	fight.call("_step_decoys", 1.0)
	var out: Array = fight.get("decoys")
	var woken: bool = out.size() == Fight.DECOY_COUNT
	for decoy in out:
		woken = woken and held.has(decoy) and (decoy as Node2D).visible and (decoy as Node).is_in_group(&"enemies") \
			and (decoy as Node).process_mode == Node.PROCESS_MODE_INHERIT and is_equal_approx(float((decoy as Node).get("life")), Fight.DECOY_SECONDS)
	check("  when they come they are those ones woken - seen, in \"enemies\", for %d s - and none made in that frame" % int(Fight.DECOY_SECONDS),
		woken and (fight.get("decoys_ahead") as Array).is_empty(), out.size())
	fight.set("_decoy_left", Fight.DECOY_AHEAD - 0.1)
	fight.call("_step_decoys", 0.01)
	var spare: Node = (fight.get("decoys_ahead") as Array)[0] if not (fight.get("decoys_ahead") as Array).is_empty() else null
	var had_spare: bool = spare != null and bool(spare.get("held"))
	fight.call("finish", false)
	await get_tree().process_frame
	check("  and one held when the fight ends goes with it", had_spare and not is_instance_valid(spare)
		and (fight.get("decoys_ahead") as Array).is_empty(), [had_spare, is_instance_valid(spare)])
	room.queue_free()
	await get_tree().process_frame
	# ---- a shape by its name ---------------------------------------------------------
	var boss_src: String = _code_src("res://src/enemies/bossenemy.gd")
	check("a boss's cast raises its shape through cast_shape(), which Find the limit asks by name",
		_func_body(boss_src, "func _cast_stalagmites_from_cast(").contains("cast_shape(pool[randi() % pool.size()])")
		and _func_body(boss_src, "func cast_shape(").contains("_pattern_by_name(choice, _aim_point())"))
	print("  the Crowned costs less")


func _test_every_boss_attack() -> void:
	section("EVERY BOSS ATTACK (0.176.0): Find the limit sweeps the Crowned's attacks one by one, and its fight part by part, made by its own fight's code")
	const Bench := preload("res://src/world/endless/bossbench.gd")
	const Sweep := preload("res://src/world/endless/limitsweep.gd")
	const Phases := preload("res://src/world/crowned/crownedphases.gd")
	const Fight := preload("res://src/world/crowned/crownedfight.gd")
	const Spawner := preload("res://src/world/gmspawner.gd")
	var attacks: Array = Bench.attacks()
	var parts: Array = Bench.phases()
	var labels: Dictionary = {}
	var by_what: Dictionary = {}
	for entry in attacks + parts:
		labels[str(entry["label"])] = true
		by_what[str(entry["boss"])] = int(by_what.get(str(entry["boss"]), 0)) + 1
	var kit_shapes: Dictionary = {}
	for land in BossEnemy.KITS:
		for shape in BossEnemy.KITS[land]["shapes"]:
			kit_shapes[shape] = true
	var shapes_known: bool = Bench.SHAPES.size() == kit_shapes.size()
	for shape in Bench.SHAPES:
		shapes_known = shapes_known and kit_shapes.has(shape) \
			and (BossEnemy.KITS[Bench.shape_land(shape)]["shapes"] as Array).has(shape)
	var volleys_known: bool = Bench.VOLLEY_LAND.size() == BossEnemy.VOLLEYS.size()
	for volley in BossEnemy.VOLLEYS:
		volleys_known = volleys_known and Bench.VOLLEY_LAND.has(volley) \
			and (BossEnemy.KITS[int(Bench.VOLLEY_LAND[volley])]["volleys"] as Array).any(func(pool: Array) -> bool: return pool.has(volley))
	check("the attacks: every volley (each in a land whose kit throws it), every shape any kit raises, the floor's hazards, three lasers and the wheel, decoy eyes, the seven weathers, the lava, the holes, the rift and the horde - each named once",
		labels.size() == attacks.size() + parts.size() and volleys_known and shapes_known
		and int(by_what.get("volley", 0)) == 7 and int(by_what.get("shape", 0)) == 14 and int(by_what.get("hazard", 0)) == 9
		and int(by_what.get("laser", 0)) == 3 and int(by_what.get("weather", 0)) == 7 and int(by_what.get("wheel", 0)) == 1
		and int(by_what.get("decoys", 0)) == 1 and int(by_what.get("lava", 0)) == 1 and int(by_what.get("holes", 0)) == 1
		and int(by_what.get("rift", 0)) == 1 and int(by_what.get("horde", 0)) == 1, by_what)
	var party_of: Array = parts.map(func(entry: Dictionary) -> int: return int(entry["party"]))
	check("  and the fight's four parts - the crowns, the Sealing, the Trap, the Tear - alone and with three more players",
		parts.size() == 8 and party_of.count(0) == 4 and party_of.count(Bench.PARTY) == 4 and Bench.PARTY == 3
		and parts.all(func(entry: Dictionary) -> bool: return int(entry["most"]) == 1)
		and Phases.phase_for(float(parts[2]["share"])) == 2 and Phases.phase_for(float(parts[4]["share"])) == 3
		and Phases.phase_for(float(parts[6]["share"])) == 4 and float(parts[0]["share"]) > Fight.CROWNS_UNTIL)
	var lava_entry: Dictionary = attacks.filter(func(entry: Dictionary) -> bool: return str(entry["boss"]) == "lava")[0]
	check("  Find the limit offers both, each counted in its own words (a second, rings, on...)",
		Sweep.targets_for(Sweep.EVERY_BOSS, 10) == attacks and Sweep.targets_for(Sweep.BOSS_PHASES, 10) == parts
		and Sweep.counted_as(attacks[0]) == "a second" and Sweep.counted_as(lava_entry) == "rings"
		and Sweep.counted_as(parts[0]) == "on" and Bench.is_rate(attacks[0]) and not Bench.is_rate(lava_entry))
	var box := VBoxContainer.new()
	add_child(box)
	var picking: Node = Sweep.new()
	picking.set("save_path", "")
	add_child(picking)
	picking.call("build", box, 460.0)
	var picker: OptionButton = box.find_child("sweeppick", true, false) as OptionButton
	var names: Array = []
	for k in picker.item_count:
		names.append(picker.get_item_text(k))
	check("  on its picker: Every boss attack (%d) and The Crowned's phases (%d)" % [attacks.size(), parts.size()],
		names.has("Every boss attack (%d)" % attacks.size()) and names.has("The Crowned's phases (%d)" % parts.size())
		and attacks.size() == 46, names.slice(0, 8))
	picking.queue_free()
	box.queue_free()
	# ---- a sweep of them on the Testing Ground ------------------------------------------
	const Run := preload("res://src/world/endless/endlessrun.gd")
	var was_god: bool = GameState.god_mode
	var was_shown: bool = PerfOverlay.is_shown()
	GameState.testing_ground = true
	var run: Node = Run.new()
	add_child(run)
	await get_tree().process_frame
	var sweep: Node = run.get_node("testingground").get("sweep")
	sweep.set("save_path", "")
	sweep.set("places_path", "user://test_limitplaces_none.json")
	var standing := Node2D.new()
	add_child(standing)
	run.set("player_override", standing)
	sweep.call("begin", Sweep.EVERY_BOSS, 10)
	var bench_node: Node = sweep.get("_bench")
	var hosted: Node = bench_node.get("host") if bench_node != null else null
	var hosted_here: bool = hosted != null and hosted.get_parent() == self
	var first_up: String = str((sweep.get("target") as Dictionary).get("label", ""))
	sweep.call("_process", Sweep.CLEAR_SECONDS + 0.1)
	sweep.call("_process", Sweep.SETTLE_SECONDS + 0.1)
	_feed_work(Sweep.MEASURE_FRAMES, 2.0)
	sweep.call("_process", 0.016)
	var a_second: int = int(sweep.call("count_now"))
	var rate_now: float = float(bench_node.get("rate")) if bench_node != null else 0.0
	sweep.call("stop")
	await get_tree().process_frame
	check("  a sweep of them: each made by the bench on the Testing Ground's floor, the first volley swept +2 a second; Stop takes it all away",
		hosted_here and first_up == "Boss: prism volley" and a_second == 2
		and is_equal_approx(rate_now, 2.0) and not is_instance_valid(hosted) and bench_node.get("host") == null,
		[first_up, a_second, rate_now])
	# The run puts its swarm and floor wash beside itself (testrunner_9's
	# fall and chest): left, its 256 stand-ins stayed in "enemies" for the
	# rest of the run - FAR ENEMIES SLEEP counted 257, and the stress
	# crowd's Off never found the world empty of copies.
	for left_beside in [run.get("swarm"), run.get("floor_wash")]:
		if left_beside != null and is_instance_valid(left_beside):
			(left_beside as Node).queue_free()
	run.queue_free()
	standing.queue_free()
	await get_tree().process_frame
	GameState.god_mode = was_god
	PerfOverlay.forget_work()
	PerfOverlay.set_shown(was_shown)
	# ---- on the Crowned's own floor -----------------------------------------------------
	var made: Dictionary = _crowned_test_room()
	var room: Node2D = made["room"]
	var floor_rect: Rect2 = made["floor"]
	var zone: BulletZone = made["zone"]
	var body: Node2D = made["body"]
	var ground: TileMapLayer = room.get_node("ground") as TileMapLayer
	var cells_whole: int = ground.get_used_cells().size()
	var middle: Vector2 = floor_rect.get_center()
	var bench: Node = Bench.new()
	add_child(bench)
	var entry_of := func(label: String) -> Dictionary:
		for entry in attacks + parts:
			if str(entry["label"]) == label:
				return entry
		return {}
	bench.call("begin", entry_of.call("Boss: gale volley"), body, room, middle)
	var host: Node2D = bench.get("host")
	var caster: Node2D = bench.get("caster")
	var lights: int = 0
	for child in host.get_children():
		if str(child.name).begins_with("crownlight"):
			lights += 1
	var rift_layer: CanvasLayer = host.get_node_or_null("riftlayer") as CanvasLayer
	check("the host: the Crowned's own fight, its floor the room's size round the middle, its seven lights, the rift hidden, no minigame of its own",
		host != null and host.get_parent() == room and (host.get("room_rect") as Rect2).size == Bench.ROOM_SIZE
		and (host.get("room_rect") as Rect2).get_center().is_equal_approx(middle) and lights == 7
		and rift_layer != null and not rift_layer.visible and not host.is_in_group(&"minigame_run"))
	check("  and the volleys' and shapes' caster: the Crowned hidden, in the volley's land, out of \"enemies\", aimed at you",
		caster != null and not caster.visible and int(caster.get("crown_land")) == Element.Type.WIND
		and not caster.is_in_group(&"enemies") and caster.get("player") == body)
	var orbs_before: int = zone.field.count
	bench.call("_one")
	check("  a volley: the Crowned's own, its orbs in the bullet zone", zone.field.count > orbs_before, [orbs_before, zone.field.count])
	bench.call("begin", entry_of.call("Boss: ring shape"), body, room, middle)
	var spikes_before: int = _ground_effects_count()
	bench.call("_one")
	check("  a shape: its spikes rise round you", _ground_effects_count() > spikes_before + 5,
		[spikes_before, _ground_effects_count()])
	bench.call("begin", entry_of.call("Boss: floor meteor"), body, room, middle)
	var lands: Node2D = bench.get("host").get("lands")
	bench.call("set_rate", 4.0)
	bench.call("_physics_process", 0.5)
	var meteors: int = (lands.get("hazards") as Array).filter(func(hz: Dictionary) -> bool: return str(hz["k"]) == "meteor").size()
	check("  a hazard so many a second: 4 a second for half a second is two meteors on the floor", meteors == 2, meteors)
	bench.call("begin", entry_of.call("Boss: cage laser"), body, room, middle)
	lands = bench.get("host").get("lands")
	bench.call("_one")
	var beams: int = (lands.get("hazards") as Array).filter(func(hz: Dictionary) -> bool: return str(hz["k"]) == "laser").size()
	check("  a laser: the cage's four beams", beams == 4, beams)
	body.global_position = floor_rect.position - Vector2(200, 200)
	bench.call("_physics_process", 0.0)
	check("  and you are kept on its floor, as its walls would keep you", floor_rect.grow(-Bench.HOLD_IN + 1.0).has_point(body.global_position),
		body.global_position)
	body.global_position = middle + Vector2(0, 150)
	# ---- held out -------------------------------------------------------------------
	var held: Dictionary = {}
	for pair in [["Boss: the Trap's wheel", 1], ["Boss: decoy eyes", 3], ["Boss: fire weather", 1], ["Boss: the Sealing's lava", 2],
			["Boss: the Tear's holes", 2], ["Boss: the rift", 1], ["Boss: the Trap's horde", 50]]:
		bench.call("begin", entry_of.call(str(pair[0])), body, room, middle)
		var got: int = int(bench.call("make", int(pair[1])))
		var cells: int = ground.get_used_cells().size()
		bench.call("_process", 0.016)
		held[str(pair[0])] = [got, int(bench.call("count")), cells < cells_whole]
	check("held out: the wheel lit, three eyes, the weather falling, two rings of lava, two holes open and the rift under them, fifty of the horde - each counted",
		held["Boss: the Trap's wheel"] == [1, 1, false] and held["Boss: decoy eyes"] == [3, 3, false]
		and held["Boss: fire weather"] == [1, 1, false] and held["Boss: the Sealing's lava"] == [2, 2, true]
		and held["Boss: the Tear's holes"] == [2, 2, true] and held["Boss: the rift"] == [1, 1, false]
		and held["Boss: the Trap's horde"] == [50, 50, false], held)
	bench.call("begin", entry_of.call("Boss: decoy eyes"), body, room, middle)
	bench.call("make", 3)
	var eye: Node = (bench.get("host").get("decoys") as Array)[0]
	eye.call("shatter")
	bench.call("_process", 0.016)
	check("  an eye broken (or gone with its time) is made again", int(bench.call("count")) == 3)
	bench.call("begin", entry_of.call("Boss: the Trap's wheel"), body, room, middle)
	bench.call("make", 1)
	var wheel_phases: Node2D = bench.get("host").get("phases")
	bench.call("_process", Phases.WHEEL_WARN + Phases.WHEEL_SECONDS + 0.1)
	check("  the wheel lit again as one burns out", int(bench.call("count")) == 1 and int(wheel_phases.get("wheels")) == 2)
	bench.call("end")
	await get_tree().process_frame
	check("  and after: the host, its caster and all it made gone, the floor whole again",
		bench.get("host") == null and room.find_child("benchcrowned", true, false) == null
		and room.find_child("crownlava", true, false) == null and room.find_child("crownhorde", true, false) == null
		and ground.get_used_cells().size() == cells_whole, [ground.get_used_cells().size(), cells_whole])
	# ---- a part of the fight -----------------------------------------------------------
	body.add_to_group(&"player")
	await get_tree().physics_frame
	await get_tree().physics_frame
	bench.call("begin", entry_of.call("Crowned: the Sealing, 4 players"), body, room, middle)
	var on: int = int(bench.call("make", 1))
	var crowned: Node2D = bench.get("boss")
	var fight_host: Node2D = bench.get("host")
	if crowned != null:
		crowned.process_mode = Node.PROCESS_MODE_DISABLED
	for _k in 3:
		bench.call("_process", 0.016)
		fight_host.call("_timed_process", 0.016)
	var targets: Array = crowned.call("fight_targets") if crowned != null else []
	var fighters: int = targets.size()
	var counted: bool = targets.has(body)
	for picture in bench.get("party"):
		counted = counted and targets.has(picture)
	var share: float = float(crowned.get("hp")) / float(maxi(1, int(crowned.get("max_hp")))) if crowned != null else 0.0
	check("a part: the Crowned (a test copy) fights you at its share - the Sealing - with three more players it counts as fighters",
		on == 1 and crowned != null and crowned.has_meta(&"stress_copy") and bool(fight_host.get("fighting"))
		and int(fight_host.get("phases").get("phase")) == 2 and absf(share - 0.7) < 0.01 and counted and fighters >= 4
		and (bench.get("party") as Array).size() == 3, [on, fighters, share])
	bench.call("end")
	body.remove_from_group(&"player")
	Spawner.clear(get_tree())
	await get_tree().process_frame
	check("  and after: the Crowned and the party gone", not is_instance_valid(crowned) and (bench.get("party") as Array).is_empty())
	bench.queue_free()
	room.queue_free()
	await get_tree().process_frame
	# ---- and what Every shot and Every effect lacked ------------------------------------
	const Stress := preload("res://src/world/endless/stresskinds.gd")
	var pet_shots: Array = Stress.shots().filter(func(swept: Dictionary) -> bool: return str(swept.get("shot", "")).contains("/pets/"))
	var pet_scenes: Dictionary = {}
	for path in ["res://scene/pets/petsniper.tscn", "res://scene/pets/petfiresprite.tscn", "res://scene/pets/petelectricsprite.tscn",
			"res://scene/pets/petpoisonslimelarge.tscn"]:
		var pet_scene: PackedScene = (load(path) as PackedScene).instantiate().get("projectile_scene")
		pet_scenes[pet_scene.resource_path if pet_scene != null else path] = true
	var listed: bool = pet_shots.size() == 4
	for swept in pet_shots:
		listed = listed and pet_scenes.has(str(swept["shot"]))
	check("Every shot has the pets' shots too - the archer's arrow, the sprites' orbs, the slimes' acid ball - each the pet's own scene",
		listed, pet_shots.map(func(swept: Dictionary) -> String: return str(swept["shot"])))
	var beam_entry: Array = []
	for swept in Stress.effects():
		if Stress.is_beam(swept):
			beam_entry.append(swept)
	var beams_at := Node2D.new()
	add_child(beams_at)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var lit: int = Stress.make_beams(get_tree(), 2, Vector2(-70000, -70000), rng)
	var shining: bool = true
	for healer in get_tree().get_nodes_in_group(Stress.GROUP):
		var beam: Node2D = (healer as Node).get_node_or_null(^"laser") as Node2D
		shining = shining and beam != null and beam.visible and float(beam.get("_show_left")) > 60.0
	if RemoteAttacks.shown():
		check("  and Every effect a party healer's Gold Staff beam, counted lit: each shining for the whole sweep",
			beam_entry.size() == 1 and Sweep.counted_as(beam_entry[0]) == "lit" and lit == 2 and shining
			and Stress.count_shots(get_tree(), beam_entry[0]) == 2, [lit, shining])
	else:
		check("  a party healer's beam: attack pictures are switched off here", lit == 0)
	Stress.clear(get_tree())
	beams_at.queue_free()
	await get_tree().process_frame
	print("  every boss attack")


# =============================================================================
# A FLOOR THE GAME EDITS (0.176.0)
# =============================================================================
# The owner: "we need to reduce that forge time". The Forge's island (21 ms)
# and lava (6.5 ms) were built whole in its arrival frame and its _ready()
# copied the island (9 ms); its slices' last sort was a 25 ms frame. Now both
# come in chunks (groundchunks.gd), the run edits them through put() and
# erase(), the scan keeps the copy, and Godot sorts the slices itself.
func _test_a_floor_the_game_edits() -> void:
	section("A FLOOR THE GAME EDITS - the Forge in chunks, its edits on them (0.176.0)")
	const Ground := preload("res://src/world/groundchunks.gd")
	const ForgeRun := preload("res://src/world/forge/forgerun.gd")

	# ---- a small floor in chunks, live ------------------------------------------------
	var world := Node2D.new()
	var layer := TileMapLayer.new()
	layer.name = "ground"
	layer.tile_set = load("res://scene/world/underground.tres")
	for x in 64:
		for y in 16:
			layer.set_cell(Vector2i(x, y), 1, Vector2i(1 + (x + y) % 4, 1 + x % 3))
	Ground.order_by_chunks(layer, 16)
	world.add_child(layer)
	var kept_canvas: Transform2D = get_viewport().canvas_transform
	var zoom_was: Variant = Settings.get_value("camera_zoom")
	Settings.set_value("camera_zoom", 3.0)
	var camera := Camera2D.new()
	world.add_child(camera)
	add_child(world)
	camera.make_current()
	var tile: float = float(layer.tile_set.tile_size.x)
	_aim(camera, Vector2(tile * 8.0, tile * 8.0))
	var helper: Node = Ground.add_to(world)
	if helper == null:
		check("a small floor in chunks gets its helper", false)
		world.free()
		get_viewport().canvas_transform = kept_canvas
		Settings.set_value("camera_zoom", zoom_was)
		return
	var far := Vector2i(3, 0)
	var made_at_arrival: int = int(helper.call("made_count"))
	check("as it arrives only what is seen is made (%d of %d chunks), the far end waiting"
		% [made_at_arrival, helper.call("chunk_count")],
		_chunk_made(helper, Vector2i(0, 0)) and not _chunk_made(helper, far) and Ground.SEEN_MARGIN < Ground.VIEW_MARGIN
		and layer.get_meta(Ground.HELPER_META, null) == helper, made_at_arrival)
	# A made chunk's cell erased, and one set to another tile.
	Ground.erase(layer, Vector2i(2, 2))
	Ground.put(layer, Vector2i(3, 3), 1, Vector2i(4, 3))
	var first_chunk: TileMapLayer = _chunk_layer(helper, Vector2i(0, 0))
	check("an edit to a made chunk's cell is on the chunk at once, and on the ground",
		first_chunk != null and first_chunk.get_cell_source_id(Vector2i(2, 2)) == -1
		and first_chunk.get_cell_atlas_coords(Vector2i(3, 3)) == Vector2i(4, 3)
		and layer.get_cell_source_id(Vector2i(2, 2)) == -1 and layer.get_cell_atlas_coords(Vector2i(3, 3)) == Vector2i(4, 3))
	# The far chunk, not made yet: a cell set and one erased.
	Ground.put(layer, Vector2i(60, 5), 1, Vector2i(4, 3))
	Ground.erase(layer, Vector2i(61, 6))
	# Where the ground had no cells at all.
	var lonely := Vector2i(5, 40)
	Ground.put(layer, lonely, 1, Vector2i(2, 2))
	var waiting: bool = not _chunk_made(helper, far)
	_aim(camera, Vector2(tile * 56.0, tile * 8.0))
	helper.call("_on_pre_draw")
	var far_chunk: TileMapLayer = _chunk_layer(helper, far)
	check("  one to a chunk not made yet is on it as it is made - a cell set, a cell gone",
		waiting and far_chunk != null and far_chunk.get_cell_atlas_coords(Vector2i(60, 5)) == Vector2i(4, 3)
		and far_chunk.get_cell_source_id(Vector2i(61, 6)) == -1 and far_chunk.get_cell_source_id(Vector2i(62, 6)) != -1,
		[waiting, far_chunk != null])
	var frames: int = 0
	while int(helper.call("made_count")) < int(helper.call("chunk_count")) and frames < 200:
		await get_tree().process_frame
		frames += 1
	await get_tree().process_frame
	var lonely_chunk: TileMapLayer = _chunk_layer(helper, Ground.chunk_of(lonely, 16))
	check("  a cell where the ground had none gets a chunk of its own, made with the rest",
		lonely_chunk != null and lonely_chunk.get_cell_atlas_coords(lonely) == Vector2i(2, 2)
		and lonely_chunk.get_used_cells().size() == 1)
	# Every chunk made: an edit where there is none makes one now.
	var later := Vector2i(100, 100)
	Ground.put(layer, later, 1, Vector2i(1, 1))
	var later_chunk: TileMapLayer = _chunk_layer(helper, Ground.chunk_of(later, 16))
	var drawn: int = 0
	var differ: int = 0
	for chunk: TileMapLayer in helper.call("chunk_layers"):
		for cell in chunk.get_used_cells():
			drawn += 1
			if chunk.get_cell_atlas_coords(cell) != layer.get_cell_atlas_coords(cell):
				differ += 1
	check("  and once all are made, at once - the chunks then draw the ground's %d cells exactly" % layer.get_used_cells().size(),
		later_chunk != null and later_chunk.get_cell_source_id(later) == 1 and drawn == layer.get_used_cells().size()
		and differ == 0, [later_chunk != null, drawn, differ])
	camera.free()
	world.free()
	get_viewport().canvas_transform = kept_canvas
	Settings.set_value("camera_zoom", zoom_was)
	var plain := TileMapLayer.new()
	plain.tile_set = load("res://scene/world/underground.tres")
	Ground.put(plain, Vector2i(1, 1), 1, Vector2i(2, 2))
	Ground.erase(plain, Vector2i(1, 1))
	Ground.put(plain, Vector2i(2, 2), 1, Vector2i(3, 3))
	check("  a layer with no chunks is simply edited", plain.get_cell_source_id(Vector2i(1, 1)) == -1
		and plain.get_cell_atlas_coords(Vector2i(2, 2)) == Vector2i(3, 3))
	plain.free()

	# ---- the Forge ---------------------------------------------------------------------
	var area: Node = (load(str(AreaRegistry.AREAS.get("forge", ""))) as PackedScene).instantiate()
	var fits: bool = true
	for name_of in ["ground", "lava"]:
		var each: TileMapLayer = area.get_node(name_of)
		var ranges: PackedInt32Array = each.get_meta(Ground.RANGES_META, PackedInt32Array())
		fits = fits and int(each.get_meta(Ground.SIZE_META, 0)) == Ground.CHUNK_CELLS_SMALL \
			and Ground.ranges_fit(ranges, each.tile_map_data.size()) and _strays(each.tile_map_data, ranges, Ground.CHUNK_CELLS_SMALL) == 0
	check("the Forge's island and lava come in chunks of %d, every cell in its own" % Ground.CHUNK_CELLS_SMALL, fits)
	var build: String = _func_body(_code_src("res://src/tools/buildforge.gd"), "func build(")
	var run_src: String = _code_src("res://src/world/forge/forgerun.gd")
	check("  buildforge.gd lays them out so once they are painted, and the run edits them only through put() and erase()",
		build.find("GroundChunks.order_by_chunks(ground") > build.find("ground.set_cell(")
		and build.contains("GroundChunks.order_by_chunks(lava")
		and run_src.contains("GroundChunks.erase(_ground") and run_src.contains("GroundChunks.put(_lava")
		and not run_src.contains("_ground.erase_cell(") and not run_src.contains("_ground.set_cell(")
		and not run_src.contains("_lava.set_cell(") and not run_src.contains("_lava.erase_cell("))
	var ground: TileMapLayer = area.get_node("ground")
	var lava: TileMapLayer = area.get_node("lava")
	var island := Node2D.new()
	area.remove_child(ground)
	area.remove_child(lava)
	island.add_child(ground)
	island.add_child(lava)
	area.free()
	var body := Node2D.new()
	body.set_script(_forge_body_script())
	island.add_child(body)
	body.global_position = Vector2(-90000, -90000)
	add_child(island)
	var run: Node = ForgeRun.new()
	run.name = "forgerun"
	run.set("player_override", body)
	run.set("class_override", "tank")
	island.add_child(run)
	run.set_process(false)
	var copied_at_ready: int = (run.get("_ground_saved") as Dictionary).size()
	run.call("_finish_scan")
	var saved: Dictionary = run.get("_ground_saved")
	var saved_right: bool = saved.size() == ground.get_used_cells().size()
	for cell in ground.get_used_cells():
		var kept: Array = saved.get(cell, [])
		saved_right = saved_right and kept.size() == 2 and int(kept[0]) == ground.get_cell_source_id(cell) \
			and kept[1] == ground.get_cell_atlas_coords(cell)
	check("  the island as built is kept by the scan, not copied in _ready() (%d cells)" % saved.size(),
		copied_at_ready == 0 and saved_right, [copied_at_ready, saved.size()])
	island.queue_free()
	# Godot's own sort, the same order as a sort by distance.
	var rng := RandomNumberGenerator.new()
	rng.seed = 176
	var entries: Array = []
	for i in 3000:
		entries.append([snappedf(rng.randf_range(0.0, 1400.0), 0.25), Vector2i(i, -i)])
	var quick: Array = ForgeRun.furthest_first(entries)
	var slow: Array = entries.duplicate()
	slow.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var same_order: bool = quick.size() == slow.size()
	var seen: Dictionary = {}
	for i in quick.size():
		same_order = same_order and is_equal_approx(float(quick[i][0]), float(slow[i][0]))
		seen[quick[i][1]] = true
	var scan: String = _func_body(run_src, "func _step_scan(")
	if scan.find("\nstatic func ") != -1:
		scan = scan.substr(0, scan.find("\nstatic func "))
	check("  its slices furthest first by Godot's own sort: the order a sort by distance gives, every entry once",
		same_order and seen.size() == entries.size() and ForgeRun.furthest_first([]).is_empty()
		and scan.contains("furthest_first(") and not scan.contains("sort_custom("), [same_order, seen.size()])
	await get_tree().process_frame
	print("  (a floor the game edits: done)")


func _chunk_layer(helper: Node, key: Vector2i) -> TileMapLayer:
	"""The chunk layer `helper` made for `key`, or null."""
	for chunk: TileMapLayer in helper.call("chunk_layers"):
		if chunk.get_meta(&"ground_chunk", Vector2i(-99999, -99999)) == key:
			return chunk
	return null


# =============================================================================
# CROWNFALL DRAWS ONLY WHAT CHANGED (0.176.0)
# =============================================================================
# The owner, of every minigame measured: "lets fix". A struck or broken brick
# drew Crownfall's whole brick picture again - about 1,050 draws in that
# frame on a map of 460 bricks. Now only the box round what changed is
# cleared and drawn again, by the bricks that reach into it. (Drawn by xvfb in
# the sandbox, zz/cfpatch: the picture so kept is the same, pixel for pixel,
# as the whole picture drawn again, on maps of 450, 665 and 1,339 bricks.)
func _test_crownfall_draws_only_what_changed() -> void:
	section("Crownfall draws only what changed - a brick broken draws a box of the picture again, not all of it (0.176.0)")
	const Run := preload("res://src/world/crownfall/crownfallrun.gd")
	var run: Node2D = Run.new()
	run.set("running_by_clock", false)
	add_child(run)
	run.begin(0)
	var frames: int = 0
	while (not run._unpainted.is_empty() or run._map_painting) and frames < 60:
		run.sync_bricks()
		frames += 1
	run.sync_bricks()
	var whole_first: int = int(run.patched_last)
	var bricks_in: int = run.brick_layer.get_child_count()
	check("a map's picture is drawn whole once its bricks are in (%d), kept between draws, its eraser ahead of the bricks"
		% whole_first, whole_first == bricks_in and bricks_in > 100
		and run.brick_cache.render_target_clear_mode == SubViewport.CLEAR_MODE_NEVER
		and run.brick_eraser.get_parent() == run.brick_cache and run.brick_eraser.get_index() < run.brick_layer.get_index()
		and (run.brick_eraser.visibility_layer & Run.PATCH_LAYER) != 0 and (run.brick_layer.visibility_layer & Run.PATCH_LAYER) != 0,
		[whole_first, bricks_in])
	# One plain brick in the middle of the others, broken.
	var target: Dictionary = {}
	var best: float = INF
	var middle: Vector2 = Vector2.ZERO
	for k in run.bricks:
		if k.has("node") and (k["node"] as Node2D).visible:
			middle += (k["rect"] as Rect2).get_center()
	middle /= maxf(1.0, float(bricks_in))
	for k in run.bricks:
		if k.has("node") and (k["node"] as Node2D).visible and run._breaks(k) and Run.STILL_KINDS.has(k["kind"]):
			var d: float = (k["rect"] as Rect2).get_center().distance_to(middle)
			if d < best:
				best = d
				target = k
	if target.is_empty():
		check("a plain brick to break", false)
		run.queue_free()
		return
	var rect: Rect2 = target["rect"]
	run.brick_cache.render_target_update_mode = SubViewport.UPDATE_DISABLED
	target["hp"] = 0
	run.sync_bricks()
	var box: Rect2 = run._erase_box
	var near: int = 0
	var far_marked: int = 0
	for k in run.bricks:
		if not k.has("node"):
			continue
		var node: Node2D = k["node"]
		var reaches: bool = Rect2(node.position, (k["rect"] as Rect2).size).grow(Run.DIRTY_MARGIN).intersects(box)
		var marked: bool = (node.visibility_layer & Run.PATCH_LAYER) != 0
		if reaches and node.visible and marked:
			near += 1
		elif marked and not reaches:
			far_marked += 1
	var target_marked: bool = ((target["node"] as Node2D).visibility_layer & Run.PATCH_LAYER) != 0
	check("  a brick broken draws again only the box round it (%s), with the %d bricks that reach into it - not all %d"
		% [str(box), int(run.patched_last), bricks_in],
		run.brick_cache.render_target_update_mode == SubViewport.UPDATE_ONCE and box.encloses(rect)
		and box.size.x <= rect.size.x + 2.0 * Run.DIRTY_MARGIN + 2.0 and box.size.y <= rect.size.y + 2.0 * Run.DIRTY_MARGIN + 2.0
		and int(run.patched_last) == near and near >= 1 and int(run.patched_last) < bricks_in / 10 and far_marked == 0
		and not target_marked and not (target["node"] as Node2D).visible
		and run.brick_cache.canvas_cull_mask == Run.PATCH_LAYER and box.position == box.position.floor()
		and box.end == box.end.floor(), [run.patched_last, near, far_marked, target_marked, run.brick_cache.canvas_cull_mask])
	# Next time, last time's bricks are back to drawing with the rest.
	var marked_before: Array = (run._patched as Array).duplicate()
	var second: Dictionary = {}
	for k in run.bricks:
		if k != target and k.has("node") and (k["node"] as Node2D).visible and run._breaks(k) \
				and (k["rect"] as Rect2).get_center().distance_to(rect.get_center()) > 200.0:
			second = k
			break
	if not second.is_empty():
		second["hp"] = 0
		run.sync_bricks()
		var back: bool = true
		for node in marked_before:
			if is_instance_valid(node) and not (run._patched as Array).has(node):
				back = back and (node as Node2D).visibility_layer == 1
		check("  and the next one: last time's bricks back with the rest, only the new box drawn",
			back and (run._erase_box as Rect2).encloses(second["rect"]) and not (run._erase_box as Rect2).intersects(rect.grow(Run.DIRTY_MARGIN)))
	# A new map is drawn whole again.
	run.begin(1)
	frames = 0
	while (not run._unpainted.is_empty() or run._map_painting) and frames < 60:
		run.sync_bricks()
		frames += 1
	run.sync_bricks()
	check("  a new map's picture is drawn whole, every layer (%d bricks)" % run.brick_layer.get_child_count(),
		int(run.patched_last) == run.brick_layer.get_child_count() and run.brick_cache.canvas_cull_mask == 0xFFFFFFFF
		and run._erase_box == Rect2(Vector2.ZERO, Run.VIEW))
	run.queue_free()
	await get_tree().process_frame
	print("  (crownfall draws only what changed: done)")


# =============================================================================
# THE STAND'S MARKS IN ONE CALL (0.176.0)
# =============================================================================
# The owner, of every minigame measured: "lets fix". The Mage's Stand drew
# each crater, fall, trail and arrow as a call of its own - 78 of its 150
# draws a frame in a wave. Now the ground's marks and the sky's trails are a
# triangle list each (quadbatch.gd). (Drawn by xvfb in the sandbox,
# zz/marksshot: 8 craters and 5 falls, 133 draws -> 3, the same marks.)
func _test_the_stands_marks_in_one_call() -> void:
	section("The Mage's Stand's marks in one call each - the craters, falls, trails and arrow (0.176.0)")
	const Stand := preload("res://src/world/magestand/magestand.gd")
	const Batch := preload("res://src/enemies/quadbatch.gd")
	var fake := Node2D.new()
	fake.set_script(_fake_stand_script())
	for i in 4:
		(fake.get("craters") as Array).append({"at": Vector2(i * 70, 20), "left": 1.0 + i * 0.3, "seed": float(i)})
		(fake.get("falling") as Array).append({"at": Vector2(i * 70, 90), "left": 0.1 + i * 0.05})
	add_child(fake)
	var ground: Node2D = Stand.Marks.new()
	ground.set("run", fake)
	var sky: Node2D = Stand.Marks.new()
	sky.set("run", fake)
	sky.set("sky", true)
	add_child(ground)
	add_child(sky)
	await get_tree().process_frame
	var before: int = Batch.handed
	ground.queue_redraw()
	await get_tree().process_frame
	var ground_triangles: int = Batch.handed - before
	before = Batch.handed
	sky.queue_redraw()
	await get_tree().process_frame
	var sky_triangles: int = Batch.handed - before
	# Each crater: its three ovals and seven flames; each fall: its shadow and ring.
	var small: int = Batch.SEGMENTS / 2
	var want_ground: int = 4 * (Batch.SEGMENTS * 2 + small + 7 * 2) + 4 * (Batch.SEGMENTS + Batch.SEGMENTS * 2)
	var src: String = _code_src("res://src/world/magestand/magestand.gd")
	var marks: String = src.substr(src.find("class Marks extends Node2D:"))
	marks = marks.substr(0, marks.find("func _draw_star_ground()"))
	# What each list covers: the sky's up to the star's own shapes, the
	# ground's from its begin() to the star's.
	var sky_part: String = marks.substr(marks.find("if sky:"))
	sky_part = sky_part.substr(0, sky_part.find("_draw_star_sky()"))
	var ground_part: String = marks.substr(marks.rfind("_batch.begin()"))
	var drawn_alone: int = 0
	for part in [sky_part, ground_part]:
		for call in ["draw_circle(", "draw_colored_polygon(", "draw_arc(", "draw_set_transform(", "draw_line("]:
			drawn_alone += (part as String).count(call)
	check("the ground's craters and falls are one triangle list (%d triangles, %d wanted), the sky's trails and arrow another (%d)"
		% [ground_triangles, want_ground, sky_triangles],
		ground_triangles == want_ground and sky_triangles > 0 and marks.count("_batch.end(self)") == 2
		and drawn_alone == 0 and sky_part.contains("_batch.end(self)") and ground_part.contains("_batch.end(self)"),
		[ground_triangles, want_ground, sky_triangles, drawn_alone])
	ground.queue_free()
	sky.queue_free()
	fake.queue_free()
	await get_tree().process_frame
	print("  (the stand's marks in one call: done)")


func _fake_stand_script() -> GDScript:
	"""What the Stand's Marks read of a run, and nothing else."""
	var script := GDScript.new()
	script.source_code = """extends Node2D
var craters: Array = []
var falling: Array = []
var star_state: String = ""
var star_afterglow: float = 0.0
var star_left: float = 1.0
var next_x: float = 60.0
var run_seconds: float = 1.3
var showing_aim: bool = false
var aim: Vector2 = Vector2.ZERO
var players: int = 1
var star_hits: int = 0
var star_at: Vector2 = Vector2.ZERO
func burn_reach() -> float:
	return 30.0
func blast_reach() -> float:
	return 36.0
func arrow_showing() -> bool:
	return true
"""
	script.reload()
	return script


# =============================================================================
# EVERY ARENA EFFECT (0.176.1)
# =============================================================================
# The owner: "we need to add every effect into testing area from cown and all
# minigames and measure and optimize them all and the effects outside of
# final boss also", and of the Earth boss's box: "faults crack had a hitch
# drop". Find the limit sweeps each elemental boss's arena whole, and each of
# its effects alone, made through the arena's own hear() - the way a
# follower's game makes it (arenabench.gd).
func _test_every_arena_effect() -> void:
	section("EVERY ARENA EFFECT (0.176.1): Find the limit sweeps each elemental boss's arena, whole and effect by effect")
	const Bench := preload("res://src/world/endless/arenabench.gd")
	const Sweep := preload("res://src/world/endless/limitsweep.gd")
	const Light := preload("res://src/enemies/lightarena.gd")
	var entries: Array = Bench.arenas()
	var labels: Dictionary = {}
	var wholes: int = 0
	var heard: bool = true
	for entry in entries:
		labels[str(entry["label"])] = true
		if str(entry["boss"]) == "arena":
			wholes += 1
		else:
			var land: String = str(entry["what"]).get_slice(":", 0)
			var kind: String = str(entry["what"]).get_slice(":", 1)
			var hear: String = _func_body(_code_src("res://src/enemies/%sarena.gd" % land), "func hear(")
			heard = heard and hear.contains("\"%s\"" % kind)
	var all_arena: bool = true
	for entry in entries:
		all_arena = all_arena and Bench.is_arena(entry)
	var lands_known: bool = Bench.LANDS.size() == BossEnemy.ARENAS.size()
	for land in Bench.LANDS:
		lands_known = lands_known and BossEnemy.ARENAS.has(StringName(land)) \
			and ResourceLoader.exists("res://scene/enemy/%sboss.tscn" % land)
	check("every arena whole (6) and each of its effects alone (%d), each named once, each an event its arena hears"
		% (entries.size() - wholes), labels.size() == entries.size() and wholes == 6 and entries.size() == 17
		and lands_known and heard and all_arena,
		[entries.size(), wholes, heard, lands_known])
	var box := VBoxContainer.new()
	add_child(box)
	var picking: Node = Sweep.new()
	picking.set("save_path", "")
	add_child(picking)
	picking.call("build", box, 460.0)
	var picker: OptionButton = box.find_child("sweeppick", true, false) as OptionButton
	var names: Array = []
	for k in picker.item_count:
		names.append(picker.get_item_text(k))
	check("  Find the limit offers them (Every arena effect (17)), counted on or a second, swept as the boss's attacks are",
		names.has("Every arena effect (17)") and Sweep.targets_for(Sweep.EVERY_ARENA, 10) == entries
		and Sweep.counted_as(entries[0]) == "on" and Sweep.counted_as(entries[6]) == "a second"
		and Sweep.BossBench.is_boss(entries[0]) and Sweep.BossBench.is_rate(entries[6]) and not Sweep.BossBench.is_rate(entries[0]))
	picking.queue_free()
	box.queue_free()
	# ---- each land's boss, its arena made and fed ------------------------------------------
	var origin := Vector2(-60000, -40000)
	var world := Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	var ground := Node2D.new()
	ground.y_sort_enabled = true
	ground.add_to_group(&"groundeffects")
	world.add_child(ground)
	var zone := BulletZone.new()
	world.add_child(zone)
	zone.set_process(false)
	zone.field.bounds = Rect2(origin - Vector2(400, 300), Vector2(800, 600))
	var me: CharacterBody2D = ArenaDummy.new()
	world.add_child(me)
	me.global_position = origin
	Light.everywhere = true
	var whole_ok: Dictionary = {}
	var fed: Dictionary = {}
	var list_of := {"box": "faults", "rock": "rocks", "pit": "pits", "frost": "frost", "wall": "walls",
		"hail": "hail", "flare": "flares", "gust": "gusts", "ember": "embers", "sweep": "turns"}
	for entry in entries:
		var bench: Node = Bench.new()
		add_child(bench)
		bench.set("target", entry)
		bench.set("me", me)
		var land: String = str(entry["what"]).get_slice(":", 0)
		var boss: Node2D = (load("res://scene/enemy/%sboss.tscn" % land) as PackedScene).instantiate()
		boss.position = origin + Vector2(0, -Bench.BOSS_ABOVE)
		boss.set("net_mirror", str(entry["boss"]) == "arena_event")
		world.add_child(boss)
		# Held where it stands (with no floor to keep to, a boss walks home):
		# its arena is made by the bench, as in the sweep.
		boss.process_mode = Node.PROCESS_MODE_DISABLED
		bench.set("boss", boss)
		await get_tree().process_frame
		var made: int = int(bench.call("make", 1))
		var arena: Node2D = boss.call("arena")
		var right_one: bool = arena != null and arena.get_script() == BossEnemy.ARENAS[StringName(land)]
		if str(entry["boss"]) == "arena":
			whole_ok[land] = right_one and made == 1 and int(bench.call("count")) == 1 \
				and not boss.is_physics_processing() and not bool(boss.get("net_mirror"))
		else:
			var kind: String = str(entry["what"]).get_slice(":", 1)
			bench.call("set_rate", 4.0)
			var before: Variant = arena.get(list_of.get(kind, "rain_left")) if right_one else null
			var size_before: int = (before as Array).size() if before is Array else 0
			bench.call("_physics_process", 1.0)
			var after: Variant = arena.get(list_of.get(kind, "rain_left")) if right_one else null
			var grew: bool = (after as Array).size() > size_before if after is Array else float(after) > 0.0
			fed[str(entry["label"])] = right_one and grew and int(bench.call("count")) == 4
		bench.call("end")
		bench.queue_free()
		await get_tree().process_frame
	var all_whole: bool = whole_ok.size() == 6 and whole_ok.values().all(func(v: bool) -> bool: return v)
	check("  each arena whole: its land's boss makes it at once, then stands, its brain stopped, while the arena leads",
		all_whole, whole_ok)
	var all_fed: bool = fed.size() == 11 and fed.values().all(func(v: bool) -> bool: return v)
	check("  each effect alone: the boss a follower's copy, its arena fed the leader's event so many a second, and it comes",
		all_fed, fed)
	Light.everywhere = false
	world.queue_free()
	await get_tree().process_frame
	print("  (every arena effect: done)")


func _test_the_readout_not_while_away() -> void:
	section("THE READOUT NOT WHILE AWAY - a frame the browser never drew is no spike (0.176.1)")
	# The owner's readout: "547872 ms 10 s - waiting 547868.5 ms", and "i was
	# on a separate screen". A browser draws nothing for a page out of sight.
	var shown_before: bool = PerfOverlay.is_shown()
	PerfOverlay.set_shown(false)
	PerfOverlay.set_shown(true)
	var clock: Array = [100000]
	for k in 120:
		_readout_frame(clock, 16.0, 2.0, 60.0)
	# Away nine minutes: one frame, nearly all of it waiting.
	_readout_frame(clock, 547872.0, 3.5, 60.0)
	for k in 150:
		_readout_frame(clock, 16.0, 2.0, 0.1 if k < 60 else 60.0)
	PerfOverlay.flush_samples()
	check("the frame you come back in is no spike, no worst frame, no worst fps",
		PerfOverlay._hitches == 0 and PerfOverlay._worst_frame_ms < 25.0
		and is_equal_approx(PerfOverlay._worst_fps, 60.0),
		[PerfOverlay._hitches, PerfOverlay._worst_frame_ms, PerfOverlay._worst_fps])
	# A long frame the game spent working is a spike, however long.
	_readout_frame(clock, 2500.0, 2400.0, 50.0)
	# And a slow frame that is waiting, under the stop's length, still counts.
	_readout_frame(clock, 900.0, 3.0, 50.0)
	for k in 6:
		_readout_frame(clock, 16.0, 2.0, 60.0)
	PerfOverlay.flush_samples()
	check("  but a long frame of work, and a slow frame of waiting, still count",
		PerfOverlay._hitches == 2 and PerfOverlay._worst_frame_ms > 2000.0,
		[PerfOverlay._hitches, PerfOverlay._worst_frame_ms])
	check("  judged before the frame is counted",
		_func_body(_code_src("res://src/systems/perfoverlay.gd"), "func _count_sample(").contains("was_stopped(sample)"))
	PerfOverlay.set_shown(false)
	if shown_before:
		PerfOverlay.set_shown(true)
	print("  (the readout not while away: done)")


func _readout_frame(clock: Array, ms: float, scripts: float, fps: float) -> void:
	clock[0] += int(ms)
	var at: int = int(clock[0])
	PerfOverlay.push_sample({"ms": ms, "held": PerfOverlay.held_for_frame(false, at), "fps": fps,
		"physics": 0.5, "worst_tick": 0.5, "ticks": 1, "scripts": scripts, "drawing": 0.5,
		"nodes": 0, "area": "elusion", "at": at})


func _test_every_arena_sorts_with_the_world() -> void:
	section("EVERY ARENA SORTS WITH THE WORLD - its floor under you, wherever you stand (0.176.1)")
	# The owner: "the lava area spawns above player on boss". The Fire boss's
	# arena was the one of six without it, so it sorted as one at y 0, and in
	# the Boss Arena's top half its lava was drawn over everybody.
	var missing: Array = []
	for land in ["light", "wind", "water", "ice", "earth", "fire"]:
		var path: String = "res://src/enemies/%sarena.gd" % land
		if not _func_body(_code_src(path), "func _ready(").contains("y_sort_enabled = true"):
			missing.append(land)
	check("each of the six arenas sorts its floor and what stands with the world", missing.is_empty(), missing)
	print("  (every arena sorts with the world: done)")


func _test_the_shop_menu_only_at_the_counter() -> void:
	section("THE SHOP'S MENU ONLY AT THE COUNTER - not out in the street (0.176.1)")
	# The owner: "the menu is not supposed to pop up outside of shop". It
	# waited for the greeting, and a hero who walked out meanwhile was asked
	# where they stood.
	const Talk := preload("res://src/shared/talk.gd")
	const Bubble := preload("res://src/shared/speechbubble.gd")
	var others: Array = get_tree().get_nodes_in_group("player")
	for other in others:
		other.remove_from_group("player")
	var holder := Node2D.new()
	holder.position = Vector2(60000, 60000)
	add_child(holder)
	var house: Node2D = (load("res://scene/walls/shophouse.tscn") as PackedScene).instantiate()
	holder.add_child(house)
	var counter: Area2D = house.get_node("interiorfurniture/shopvendor") as Area2D
	var keeper: Node = counter.get_node("animatedsprite2d")
	keeper.set("class_override", "healer")
	var hero := CharacterBody2D.new()
	hero.name = "Player"
	hero.collision_layer = 4
	hero.collision_mask = 0
	var body_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 6.0
	body_shape.shape = circle
	hero.add_child(body_shape)
	hero.add_to_group("player")
	var at_counter: Vector2 = (counter.get_node("collisionshape2d") as Node2D).global_position
	holder.add_child(hero)
	hero.global_position = at_counter
	hero.reset_physics_interpolation()
	# Met before, so a visit is a greeting and then the menu.
	Bubble.note_said(Talk.seen_key("meet_shopkeeper"))
	keeper.set("_last_greeting", -1000.0)
	for i in 3:
		await get_tree().physics_frame
	var greeting: Node = keeper.get("bubble")
	check("walking up to the counter, the shopkeeper greets the hero",
		greeting != null and greeting.get_script() == Bubble and counter.overlaps_body(hero))
	# Out of the shop while he is still talking.
	hero.global_position = at_counter + Vector2(0, 400)
	hero.reset_physics_interpolation()
	for i in 3:
		await get_tree().physics_frame
	_end_bubble(greeting)
	await get_tree().process_frame
	check("  the hero walked out before he finished: no menu out there",
		hero.get_node_or_null("choicebox") == null and keeper.get("bubble") == null)
	# Back again soon: the menu at once.
	hero.global_position = at_counter
	hero.reset_physics_interpolation()
	for i in 3:
		await get_tree().physics_frame
	var menu: Node = keeper.get("bubble")
	var asked: Node2D = menu.get("bubble") as Node2D if menu != null else null
	if asked != null:
		_end_bubble(asked)
	await get_tree().process_frame
	check("  back at the counter soon after, the menu at once, under the hero",
		menu != null and menu.get_script() == Talk and hero.get_node_or_null("choicebox") != null)
	if menu != null and is_instance_valid(menu):
		menu.queue_free()
	var box: Node = hero.get_node_or_null("choicebox")
	if box != null:
		box.queue_free()
	await get_tree().process_frame
	# Staying for the whole greeting: the menu after it, as before.
	keeper.set("bubble", null)
	keeper.set("_last_greeting", -1000.0)
	keeper.call("greet")
	var again: Node = keeper.get("bubble")
	_end_bubble(again)
	await get_tree().process_frame
	check("  and a hero who stays for the greeting is offered the menu after it, as before",
		keeper.get("bubble") != null and (keeper.get("bubble") as Node).get_script() == Talk)
	# OUT OF THE SHOP, THE TALK ENDS: "after pressing talk on shop keeper and
	# walking out of building chat pops up".
	var chat: Node = keeper.get("bubble")
	if chat != null and is_instance_valid(chat):
		chat.free()
	await get_tree().process_frame
	var lines: Array = Talk.read_script("hero: What do you sell?\nshopkeeper: Gear, mostly.\nhero: And?\n")
	var talking: Node = Talk.play(keeper, lines, {"shopkeeper": keeper, "hero": hero}, "")
	keeper.set("bubble", talking)
	await get_tree().process_frame
	var said_before: bool = false
	for c in hero.get_children():
		said_before = said_before or c.get_script() == Bubble
	hero.global_position = at_counter + Vector2(0, 400)
	hero.reset_physics_interpolation()
	for i in 3:
		await get_tree().physics_frame
	await get_tree().process_frame
	var still_said: bool = false
	for c in hero.get_children():
		still_said = still_said or (c.get_script() == Bubble and not c.is_queued_for_deletion())
	check("  talking, the hero walks out of the shop: the talk ends there, nothing more said in the street",
		said_before and not still_said and keeper.get("bubble") == null
		and (not is_instance_valid(talking) or talking.is_queued_for_deletion()), [said_before, still_said])
	holder.queue_free()
	await get_tree().process_frame
	for other in others:
		if is_instance_valid(other):
			other.add_to_group("player")
	print("  (the shop's menu only at the counter: done)")


func _end_bubble(said: Variant) -> void:
	"""A speech bubble said to its end: every line shown, then faded. A
	Variant: one already gone (walked out of the shop) is passed too."""
	if not is_instance_valid(said):
		return
	for i in 24:
		said.call("hurry")
	said.call("_process", 1.0)


func _test_the_shop_keeps_its_lists() -> void:
	section("THE SHOP KEEPS ITS LISTS - Buy not built again, a sale makes one row (0.176.1)")
	# The owner: "shop spikes when i trade also". Buy built all its rows on
	# every switch (40-58 ms in town) and a sale redrew the Sell list twice.
	const T := ItemData.Type
	var potion: ItemData = _menu_item("zz_keep_potion", T.CONSUMABLE, 0, 20)
	var sword: ItemData = _menu_item("zz_keep_sword", T.WEAPON, ItemData.EquipSlot.WEAPON)
	for item in [potion, sword]:
		item.tier = 1
		ItemRegistry._items[item.item_id] = item
	var panel: Node = (load("res://scene/ui/shop/shopinventory.tscn") as PackedScene).instantiate()
	add_child(panel)
	panel.visible = true
	var bag := InventoryContainer.new()
	bag.is_carry = true
	add_child(bag)
	bag.load_save_array([{"item_id": "zz_keep_potion", "quantity": 5}, {"item_id": "zz_keep_sword", "quantity": 1},
		null, {"item_id": "zz_keep_potion", "quantity": 2}])
	panel.inventory_override = bag
	var stock: Array = [
		{"item_id": "zz_keep_potion", "display_name": "Potion", "price": 40, "tier": 1, "type_name": "CONSUMABLE"},
		{"item_id": "zz_keep_sword", "display_name": "Sword", "price": 400, "tier": 1, "type_name": "WEAPON"}]
	var answer: Dictionary = {"shop_id": "generalstore", "display_name": "Kingdom Supplies", "stock": stock,
		"sell_multiplier": 0.05, "sell_prices": {"zz_keep_potion": 2, "zz_keep_sword": 20}}
	panel.show_catalogue(answer)
	var shelf: Array = panel.stock_list.get_children()
	panel.set_mode("sell")
	var selling: Array = panel.stock_list.get_children()
	var sell_names: Array = selling.map(func(r: Node) -> String: return str(r.name))
	check("Sell shows its own list, the shelf kept out of sight; Buy the same shelf again, nothing made",
		sell_names == ["sell_0", "sell_1", "sell_3"] and not shelf.is_empty()
		and shelf.all(func(r: Node) -> bool: return is_instance_valid(r) and not r.is_visible_in_tree()), sell_names)
	panel.set_mode("buy")
	check("  back on Buy, the very same rows",
		panel.stock_list.get_children() == shelf and shelf.all(func(r: Node) -> bool: return r.is_visible_in_tree()))
	# A sale: the sword's cell empties, the rest are the rows they were.
	panel.set_mode("sell")
	var potion_row: Node = panel.stock_list.get_node("sell_0")
	var arm: Button = panel.stock_list.get_node("sell_3").find_child("sellall", true, false)
	arm.text = "Sure?"
	bag.load_save_array([{"item_id": "zz_keep_potion", "quantity": 5}, null, null, {"item_id": "zz_keep_potion", "quantity": 2}])
	panel.show_sell_list()
	await get_tree().process_frame
	var after: Array = panel.stock_list.get_children().map(func(r: Node) -> String: return str(r.name))
	check("  a sale: the sold cell's row gone, the others the same rows, an armed one disarmed",
		after == ["sell_0", "sell_3"] and panel.stock_list.get_node("sell_0") == potion_row
		and is_instance_valid(arm) and arm.text == "Sell all", after)
	bag.load_save_array([{"item_id": "zz_keep_potion", "quantity": 4}, null, {"item_id": "zz_keep_sword", "quantity": 1},
		{"item_id": "zz_keep_potion", "quantity": 2}])
	panel.show_sell_list()
	await get_tree().process_frame
	var redrawn: Array = panel.stock_list.get_children().map(func(r: Node) -> String: return str(r.name))
	var count_label: Label = panel.stock_list.get_node("sell_0").find_child("itemname", true, false)
	check("  one fewer in a stack is a new row for that cell, a new cell takes its place in order",
		redrawn == ["sell_0", "sell_2", "sell_3"] and panel.stock_list.get_node("sell_0") != potion_row
		and count_label.text.ends_with("×4"), [redrawn, count_label.text])
	# Shut and opened again on the same answer: the shelf as it was.
	panel.set_mode("buy")
	panel.close_shop()
	panel.visible = true
	panel.show_catalogue(answer)
	check("  shut and opened on the same catalogue, the shelf is not made again",
		panel.stock_list.get_children() == shelf)
	var dearer: Dictionary = answer.duplicate(true)
	dearer["stock"][0]["price"] = 60
	panel.show_catalogue(dearer)
	check("  a new price is a new shelf", panel.stock_list.get_child_count() == shelf.size()
		and not is_instance_valid(shelf[0]) or (shelf[0] as Node).is_queued_for_deletion())
	panel.queue_free()
	bag.queue_free()
	ItemRegistry._items.erase("zz_keep_potion")
	ItemRegistry._items.erase("zz_keep_sword")
	await get_tree().process_frame
	print("  (the shop keeps its lists: done)")


func _test_an_old_copy_refreshes_itself() -> void:
	section("AN OLD COPY REFRESHES ITSELF - at the sign-in screen, once a version (0.176.1)")
	# The owner's game pane ran 0.175.0 for a day after 0.176.0 went live:
	# put back from the browser's cache, and nothing reloaded it.
	const Check := preload("res://src/systems/versioncheck.gd")
	const ApiScript := preload("res://src/systems/api.gd")
	var was: String = ApiScript.newer_web_version
	var reloads: Array = []
	var door: Array = [true]
	# A local const is not seen inside a lambda; a local var is.
	var check_script: GDScript = Check
	var make := func(said: String) -> Node:
		var checker: Node = check_script.new()
		checker.set("url", "https://example.invalid/version.txt")
		checker.set("fetch", func(_where: String) -> String: return said)
		checker.set("reload", func(version: String) -> bool:
			reloads.append(version)
			return true)
		checker.set("at_door", func() -> bool: return door[0])
		add_child(checker)
		return checker
	check("the first ask is at once, not a while into the game", Check.FIRST_SECONDS <= 1.0, Check.FIRST_SECONDS)
	var at_door: Node = make.call("99.5.0")
	await at_door.call("check")
	check("  a newer version on the first ask, at the sign-in screen: the page reloads for it",
		reloads == ["99.5.0"], reloads)
	at_door.set("fetch", func(_where: String) -> String: return "99.6.0")
	await at_door.call("check")
	check("  a later ask only says it (someone may be typing their password)", reloads == ["99.5.0"]
		and str(at_door.get("newest")) == "99.6.0", reloads)
	door[0] = false
	var in_world: Node = make.call("99.7.0")
	await in_world.call("check")
	check("  in the world, nothing reloads: the strip says it, as before",
		reloads == ["99.5.0"] and str(in_world.get("newest")) == "99.7.0", reloads)
	door[0] = true
	var same: Node = make.call(ApiScript.DISPLAY_VERSION)
	await same.call("check")
	check("  this version itself: no reload", reloads == ["99.5.0"], reloads)
	var src: String = _code_src("res://src/systems/versioncheck.gd")
	var body: String = _func_body(src, "func refresh_at_the_door(")
	check("  in a browser, once a version a tab (sessionStorage), and never when it cannot be kept",
		body.contains("sessionStorage.getItem") and body.contains("sessionStorage.setItem")
		and body.contains("catch (e) { return false; }") and body.contains("window.location.reload()")
		and Check.AT_THE_DOOR == ProjectSettings.get_setting("application/run/main_scene"))
	for node in [at_door, in_world, same]:
		node.queue_free()
	ApiScript.newer_web_version = was
	print("  (an old copy refreshes itself: done)")


func _test_the_crownfall_bars_in_one_call() -> void:
	section("CROWNFALL'S BARS IN ONE CALL - their shapes as the engine makes them, handed over together (0.176.1)")
	# The owner: "work on this", of the bars' 214 draws a repaint: every
	# circle, polygon, arc and outline was a draw call of its own.
	const Batch := preload("res://src/shared/canvasbatch.gd")
	var batch = Batch.new()
	batch.begin()
	batch.draw_circle(Vector2(10, 10), 5.0, Color.RED)
	batch.draw_arc(Vector2(10, 10), 8.0, 0.0, TAU, 20, Color.WHITE, 1.5)
	batch.draw_rect(Rect2(0, 0, 10, 10), Color.GREEN, false, 2.0)
	batch.draw_polyline(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)]), Color.WHITE, 1.0)
	batch.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(5, 10)]), Color.BLUE)
	batch.draw_line(Vector2(0, 0), Vector2(10, 10), Color.WHITE, 2.0)
	batch.draw_rect(Rect2(0, 0, 4, 4), Color.GREEN)
	var holder := Node2D.new()
	add_child(holder)
	batch.end(holder)
	# The engine's own counts (zz/primprobe): a circle 64, a 20-point arc 38,
	# an outline 8, a two-segment polyline 4, a triangle 1, a line 2, a rect 2.
	check("each shape the triangles the engine would make: 64 + 38 + 8 + 4 + 1 + 2 + 2",
		int(batch.last_triangles) == 119, batch.last_triangles)
	holder.queue_free()
	var Run: GDScript = load("res://src/world/crownfall/crownfallrun.gd") as GDScript
	var src: String = _code_src("res://src/world/crownfall/crownfallrun.gd")
	var paint: String = _func_body(src, "func _paint_panels(")
	var shapes_at: int = paint.find("_cv = _panel_batch")
	var ended_at: int = paint.find("_panel_batch.end(panel_node)")
	var words_at: int = paint.find("_write_held_words()")
	check("  the bars are drawn into the batch, handed to their picture, then their words written on it",
		shapes_at >= 0 and shapes_at < paint.find("_draw_hud()") and ended_at > paint.find("_draw_right_panel()")
		and words_at > ended_at and paint.find("_cv = panel_node") > ended_at and paint.find("_cv = panel_node") < words_at
		and Run.get_script_constant_map().has("CanvasBatch"))
	print("  (crownfall's bars in one call: done)")


func _test_the_big_field_walls_flattened() -> void:
	section("THE BIG FIELD'S WALLS FLATTENED - a picture each, a body a chunk (0.176.1)")
	# The owner's "yes" to the plan: 4,555 wall pieces were 18,846 nodes, 55
	# ms of the arrival and 96 of leaving (zz/bfbranches).
	const WallChunk := preload("res://src/world/wallchunk.gd")
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/maps/bigfield_build.json"))
	var area: Node = (load("res://scene/bigfield.tscn") as PackedScene).instantiate()
	var walls: Node = area.get_node("ysortworld/props/crypt/walls")
	var nodes: int = 0
	var pictures: Array = []
	var boxes: int = 0
	var not_chunks: Array = []
	for chunk in walls.get_children():
		if chunk.get_script() != WallChunk:
			not_chunks.append(chunk.name)
			continue
		boxes += (chunk.get("boxes") as PackedFloat32Array).size() / 4
		for piece in chunk.get_children():
			nodes += 1 + piece.get_child_count()
			pictures.append(piece)
	# What each piece was, from its own crypt scene.
	var wanted_boxes: int = 0
	var models: Dictionary = {}
	var wrong: Array = []
	var at_plan: Dictionary = {}
	for row in plan["walls"]:
		var kind: String = str(row[0])
		if not models.has(kind):
			models[kind] = (load("res://scene/crypt/%s.tscn" % kind) as PackedScene).instantiate()
		wanted_boxes += (models[kind] as Node).get_node("body").get_child_count()
		at_plan["%s@%s" % [kind, Vector2(float(row[1]), float(row[2]))]] = true
	for piece in pictures:
		var kind: String = str(piece.get_meta(&"piece", ""))
		var model: Node = models.get(kind)
		var art: Sprite2D = model.get_node("sprite") as Sprite2D if model != null else null
		var sprite := piece as Sprite2D
		# The scene keeps its own copy of each piece's AtlasTexture: the same
		# sheet and region.
		var mine := sprite.texture as AtlasTexture if sprite != null else null
		var theirs := art.texture as AtlasTexture if art != null else null
		if mine == null or theirs == null or mine.region != theirs.region or mine.atlas != theirs.atlas \
				or sprite.offset != art.offset \
				or not at_plan.has("%s@%s" % [kind, sprite.position]) or piece.get_child_count() != 0:
			wrong.append(piece.name)
	check("every wall chunk a WallChunk; every piece its crypt piece's picture alone, at the plan's spot (%d in %d nodes)"
		% [pictures.size(), nodes], not_chunks.is_empty() and wrong.is_empty() and pictures.size() == (plan["walls"] as Array).size()
		and nodes == pictures.size(), [not_chunks.slice(0, 3), wrong.slice(0, 3)])
	check("  and every one of the pieces' %d boxes kept on its chunk" % wanted_boxes, boxes == wanted_boxes, [boxes, wanted_boxes])
	for model in models.values():
		(model as Node).free()
	# In the world: one body, on the pieces' layer, a shape a box, out of the
	# way of its pictures.
	var chunk: Node2D = null
	for c in walls.get_children():
		if (c.get("boxes") as PackedFloat32Array).size() >= 8:
			chunk = c
			break
	var holder := Node2D.new()
	add_child(holder)
	chunk.get_parent().remove_child(chunk)
	chunk.owner = null
	holder.add_child(chunk)
	var body: StaticBody2D = chunk.get_node_or_null("body") as StaticBody2D
	var piece_body := StaticBody2D.new()
	var shapes: int = 0
	if body != null:
		for id in body.get_shape_owners():
			shapes += body.shape_owner_get_shape_count(id)
	check("  in the world a chunk is one StaticBody2D on the pieces' own layer and mask, a shape a box, not among its pictures",
		body != null and body.collision_layer == piece_body.collision_layer and body.collision_mask == piece_body.collision_mask
		and shapes * 4 == (chunk.get("boxes") as PackedFloat32Array).size() and not chunk.get_children().has(body), shapes)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var first: Rect2 = (chunk.call("box_rects") as Array)[0]
	var query := PhysicsPointQueryParameters2D.new()
	query.position = chunk.global_position + first.get_center()
	query.collision_mask = 1
	var hit: bool = false
	for h in get_viewport().world_2d.direct_space_state.intersect_point(query, 8):
		hit = hit or h.get("collider") == body
	check("  and it blocks where the piece's box was", hit)
	piece_body.free()
	holder.queue_free()
	area.free()
	var src: String = _code_src("res://src/tools/buildbigfield.gd")
	check("  the builder flattens only walls in chunks (the Field's builder, chunk_size 0, places its pieces as before)",
		_func_body(src, "func build(").contains("if chunk_size > 0:\n\t\t\t_flat_wall("))
	print("  (the big field's walls flattened: done)")
