# testrunner_12.gd - part 12 of the suite (testrunner.gd says how it is
# split; part 11 passed 245 KB): _test_every_look_is_warmed,
# _test_the_stand_ins_cost_less, _test_the_readout_counts_the_screen,
# _test_a_days_minigame_gold_and_a_rollback_held_back.
extends "res://src/tools/testrunner_11.gd"


# =============================================================================
# EVERY LOOK DRAWN ONCE, OUT OF SIGHT (0.156.0)
# =============================================================================
# The owner's phone: a 3,243 ms frame of "waiting" in a boss fight, then "WE
# NEED TO LOOK INTO EVERY CRACK". Godot builds a program the first time each
# look is drawn; in the container (zz/firstdraw2.gd with Mesa's capture) 4 to
# 7 were built in the middle of every fight - the hit flash, the death
# crumble, a strike's sparks, an arena's fog and snow - and none after
# shaderwarm.gd. These hold that every look the game draws with is warmed,
# that the warming draws, hides and goes, and that the readout marks a look
# that was not.

func _test_every_look_is_warmed() -> void:
	section("Every look drawn once, out of sight, as the first area arrives (0.156.0)")
	const Warm := preload("res://src/systems/shaderwarm.gd")

	# ---- every look is in the lists -------------------------------------------
	var files_missing: Array = []
	for path in _all_files_under("res://src", ".gdshader"):
		if not Warm.SHADER_FILES.has(path):
			files_missing.append(path)
	for path in Warm.SHADER_FILES:
		if not ResourceLoader.exists(path):
			files_missing.append(path + " (listed, not there)")
	check("every shader file in src/ is warmed, and every one listed is there",
		files_missing.is_empty() and Warm.SHADER_FILES.size() >= 10, files_missing)

	var code_missing: Array = []
	var code_sites: int = 0
	var code_re := RegEx.create_from_string("\\.code\\s*=\\s*([A-Za-z_][\\w.]*)")
	for path in _all_gd_under("res://src"):
		if _is_suite_script(path) or path == Warm.PATH or Warm.NOT_WARMED.has(path):
			continue
		var src: String = _code_src(path)
		if not src.contains("Shader.new()"):
			continue
		for found in code_re.search_all(src):
			var named: String = found.get_string(1)
			code_sites += 1
			var listed := false
			for entry in Warm.SHADER_CODE:
				if (str(entry[0]) == path and str(entry[1]) == named) \
						or (named.contains(".") and named.get_slice(".", 1) == str(entry[1])
							and FileAccess.get_file_as_string(str(entry[0])).contains("const %s" % entry[1])):
					listed = true
			if not listed:
				code_missing.append("%s: %s" % [path.get_file(), named])
	var bad_entries: Array = []
	for entry in Warm.SHADER_CODE:
		var script: Script = load(str(entry[0])) as Script
		if script == null or not script.get_script_constant_map().get(str(entry[1])) is String:
			bad_entries.append(entry[1])
	check("  every shader written in code is warmed (SHADER_CODE), and each one listed is a script's constant",
		code_missing.is_empty() and bad_entries.is_empty() and code_sites >= 8, [code_missing, bad_entries, code_sites])

	var combos_missing: Array = []
	var made_re := RegEx.create_from_string("(?:var\\s+)?([\\w.]+)\\s*:?=\\s*CanvasItemMaterial\\.new\\(\\)")
	var plain_sites: int = 0
	for path in _all_gd_under("res://src"):
		if _is_suite_script(path) or path == Warm.PATH:
			continue
		var src: String = _code_src(path)
		if not src.contains("CanvasItemMaterial.new()"):
			continue
		for body in src.split("\nfunc "):
			for found in made_re.search_all(body):
				var v: String = found.get_string(1)
				plain_sites += 1
				var blend: int = CanvasItemMaterial.BLEND_MODE_MIX
				var light: int = CanvasItemMaterial.LIGHT_MODE_NORMAL
				var b := RegEx.create_from_string(v.replace(".", "\\.") + "\\.blend_mode\\s*=\\s*CanvasItemMaterial\\.(BLEND_MODE_\\w+)").search(body)
				var l := RegEx.create_from_string(v.replace(".", "\\.") + "\\.light_mode\\s*=\\s*CanvasItemMaterial\\.(LIGHT_MODE_\\w+)").search(body)
				if b != null:
					blend = int(ClassDB.class_get_integer_constant("CanvasItemMaterial", b.get_string(1)))
				if l != null:
					light = int(ClassDB.class_get_integer_constant("CanvasItemMaterial", l.get_string(1)))
				if body.contains(v + ".particles_animation = true"):
					combos_missing.append("%s: particles_animation" % path.get_file())
				if not Warm.PLAIN_LOOKS.has([blend, light]):
					combos_missing.append("%s: %s blend %d light %d" % [path.get_file(), v, blend, light])
	check("  every CanvasItemMaterial the game makes has its blend and light in PLAIN_LOOKS",
		combos_missing.is_empty() and plain_sites >= 20, [combos_missing, plain_sites])

	# ---- the warming draws, out of sight, and goes ------------------------------
	var was_done: bool = Warm._done
	var was_warmed: Dictionary = Warm.warmed.duplicate()
	Warm._done = false
	var area := Node2D.new()
	area.name = "warmarea"
	get_tree().root.add_child(area)
	var warm: Node = Warm.add_to(area)
	check("the first area of a session gets the warming, the next none",
		warm != null and warm.get_parent() == area and Warm.add_to(area) == null and Warm._done)
	var expected: int = 0
	for look in Warm.looks():
		expected += (look[1] as Array).size()
	var lit: bool = str(Settings.get_value("lighting")) == "full"
	for k in Warm.START_AFTER:
		await get_tree().process_frame
	var items: Array = (warm.get("_items") as Array).duplicate() if is_instance_valid(warm) else []
	check("  every look drawn each way it is drawn (%d), %s" % [expected, "and again lit" if lit else "unlit"],
		is_instance_valid(warm) and int(warm.get("drawn")) == expected * (2 if lit else 1) and items.size() == int(warm.get("drawn")),
		[warm.get("drawn") if is_instance_valid(warm) else null, expected])
	check("  under everything and too faint to see",
		Warm.WARM_ALPHA <= 0.03 and _code_src(Warm.PATH).contains("canvas_item_set_z_index(item, RenderingServer.CANVAS_ITEM_Z_MIN)")
		and _code_src(Warm.PATH).contains("Color(1.0, 1.0, 1.0, WARM_ALPHA)"))
	var hit_flash := ShaderMaterial.new()
	hit_flash.shader = load("res://src/shared/hitflash.gdshader") as Shader
	var flash_sprite := Sprite2D.new()
	flash_sprite.material = hit_flash
	var dust := CPUParticles2D.new()
	var dust_look := CanvasItemMaterial.new()
	dust_look.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	dust.material = dust_look
	var rain := MultiMeshInstance2D.new()
	var rain_look := ShaderMaterial.new()
	rain_look.shader = Shader.new()
	rain_look.shader.code = (load("res://src/enemies/waterarena.gd") as Script).get_script_constant_map()["RAIN_SHADER"]
	rain.material = rain_look
	check("  what was measured building mid-fight is warm: the hit flash, unshaded dust, the rain (a copy of its code)",
		Warm.warmed.has(Warm.look_key(flash_sprite)) and Warm.warmed.has(Warm.look_key(dust))
		and Warm.warmed.has(Warm.look_key(rain)) and Warm.mode_of(dust) == Warm.Mode.COPIES)
	var odd := Sprite2D.new()
	var odd_look := ShaderMaterial.new()
	odd_look.shader = Shader.new()
	odd_look.shader.code = "shader_type canvas_item;\nvoid fragment() { COLOR.rgb *= 0.937; }\n"
	odd.material = odd_look
	check("  a look nobody listed is not", not Warm.warmed.has(Warm.look_key(odd)))
	for k in Warm.WARM_FRAMES + 1:
		await get_tree().process_frame
	check("  for WARM_FRAMES frames, then the ghosts and the node are gone",
		not is_instance_valid(warm) or warm.is_queued_for_deletion() or (warm.get("_items") as Array).is_empty())

	# ---- the readout marks a first draw -----------------------------------------
	var was_shown: bool = PerfOverlay.is_shown()
	PerfOverlay.set_shown(true)
	area.add_child(flash_sprite)
	area.add_child(odd)
	# As the frame is handed to the renderer (_on_pre_draw()), here at once.
	PerfOverlay.call("_look_at_new_items")
	var seen: Dictionary = PerfOverlay.get("_seen_looks") as Dictionary
	var firsts: int = int((PerfOverlay.get("_marks_now") as Dictionary).get(&"first draws", 0))
	check("the readout marks \"first draws\" for a look that was not warmed, and not for one that was",
		firsts == 1 and seen.has(Warm.look_key(odd)) and not seen.has(Warm.look_key(flash_sprite))
		and PerfOverlay.MARK_LETTERS.has(&"first draws"), [firsts, seen.size()])
	var again := Sprite2D.new()
	again.material = odd_look
	area.add_child(again)
	PerfOverlay.call("_look_at_new_items")
	check("  once a look a session",
		int((PerfOverlay.get("_marks_now") as Dictionary).get(&"first draws", 0)) == firsts)
	PerfOverlay.set_shown(false)
	check("  and only while the readout is up (it stops listening)",
		not get_tree().node_added.is_connected(Callable(PerfOverlay, "_on_node_added")))
	if was_shown:
		PerfOverlay.set_shown(true)
	area.queue_free()
	dust.free()
	rain.free()
	Warm._done = was_done
	Warm.warmed = was_warmed

	# ---- where it is made -------------------------------------------------------
	check("AreaRegistry gives the warming to the first area to arrive, and the spikes keep no warming of their own",
		_func_body(_code_src("res://src/systems/arearegistry.gd"), "func _on_scene_changed(").contains("ShaderWarm.add_to(scene)")
		and not _code_src("res://src/projectiles/spikefx.gd").contains("func warm("))
	print("  every look warmed: %d shader files, %d in code, %d plain looks" %
		[Warm.SHADER_FILES.size(), Warm.SHADER_CODE.size(), Warm.PLAIN_LOOKS.size()])


# =============================================================================
# THE STAND-INS COST LESS A TICK (0.156.0)
# =============================================================================
# The owner's phone: physics 9.1 ms a tick in a boss fight with the horde.
# Timed piece by piece in the container (zz/fightbench.gd, a phone's 40
# ticks): the empty arena 0.62 ms a tick, of it 0.3 the swarm moving 256
# stand-ins - every one called by name, the parked ones too. Now a parked one
# is never touched (the swarm's own `_shown`), and on a phone one on the slime
# it stood on waits until the slime is drawn PHONE_STAND_SLACK px off.

func _test_the_stand_ins_cost_less() -> void:
	section("The stand-ins cost less a tick: the parked ones left alone, a phone's still crowd too (0.156.0)")
	var SwarmScript: GDScript = load("res://src/world/endless/swarm.gd") as GDScript
	var o := Vector2(-64000, -64000)
	var swarm: Node2D = SwarmScript.new()
	swarm.set("arena", Rect2(o, Vector2(2000, 2000)))
	add_child(swarm)
	swarm.set_process(false)
	swarm.set_physics_process(false)
	var me := Node2D.new()
	me.add_to_group(&"player")
	add_child(me)
	me.global_position = o + Vector2(1000, 1000)
	var proxies: Array = swarm.get("_proxies")
	var shown: PackedInt32Array = swarm.get("_shown")
	check("the swarm notes each stand-in's slime, all parked to begin with",
		shown.size() == proxies.size() and not shown.has(0) and Array(shown).all(func(v): return v == -1))
	# A parked stand-in is not touched: one moved by hand stays where it was.
	var parked: Node2D = proxies[proxies.size() - 1]
	parked.global_position = o + Vector2(5, 5)
	swarm.call("_move_proxies")
	check("  a parked stand-in is not touched by the tick", parked.global_position == o + Vector2(5, 5)
		and _func_body(_code_src("res://src/world/endless/swarm.gd"), "func _move_proxies(").contains("elif _shown[p] != -1:"))
	parked.global_position = Vector2(-100000, -100000)
	var records := PackedInt32Array()
	for k in 20:
		var spot: Vector2 = me.global_position + Vector2(20.0 + 4.0 * k, 0.0)
		records.append_array(PackedInt32Array([k, 1, 50, roundi(spot.x), roundi(spot.y), Element.Type.LIGHT]))
	swarm.call("import_alive", records)
	swarm.set("_since_write", float(SwarmScript.STEP))
	swarm.call("_place_proxies")
	var first: Node2D = proxies[0]
	var slime: int = int(first.get("slot"))
	var px: PackedFloat32Array = swarm.get("px")
	var py: PackedFloat32Array = swarm.get("py")
	check("  a stand-in is put on its slime, and the note says so",
		slime >= 0 and int((swarm.get("_shown") as PackedInt32Array)[0]) == slime
		and first.global_position == Vector2(px[slime], py[slime]), [slime, first.global_position])
	# A computer moves it with its slime every tick.
	px[slime] += 1.0
	swarm.set("px", px)
	var bx: PackedFloat32Array = swarm.get("bx")
	bx[slime] = px[slime]
	swarm.set("bx", bx)
	swarm.call("_move_proxies")
	check("  on a computer it follows its slime to the pixel, every tick",
		is_equal_approx(float(swarm.get("stand_slack")), 0.0) and first.global_position.x == px[slime])
	# A phone leaves it until its slime is PHONE_STAND_SLACK off.
	swarm.set("stand_slack", SwarmScript.PHONE_STAND_SLACK)
	var was: Vector2 = first.global_position
	px[slime] += 2.0
	bx[slime] = px[slime]
	swarm.set("px", px)
	swarm.set("bx", bx)
	swarm.call("_move_proxies")
	var stayed: bool = first.global_position == was
	px[slime] += 2.0
	bx[slime] = px[slime]
	swarm.set("px", px)
	swarm.set("bx", bx)
	swarm.call("_move_proxies")
	check("  on a phone it stays for 2 px, and goes once its slime is past %.0f px" % SwarmScript.PHONE_STAND_SLACK,
		stayed and first.global_position.x == px[slime], [stayed, first.global_position.x, px[slime]])
	# Killed under a blow it parks itself; the slot born again, it is put back.
	first.call("take_damage", 100000.0)
	var gone: bool = int(first.get("slot")) == -1 and not first.visible
	var alive_again := PackedInt32Array([slime, 2, 50, roundi(px[slime]), roundi(py[slime]), Element.Type.LIGHT])
	swarm.call("import_alive", alive_again)
	var held: PackedInt32Array = swarm.get("_held")
	held[0] = slime
	swarm.set("_held", held)
	swarm.call("_move_proxies")
	check("  killed under a blow it parks itself, and a slime born in that slot gets it back",
		gone and int(first.get("slot")) == slime and first.visible, [gone, first.get("slot")])
	var made: String = _func_body(_code_src("res://src/world/endless/endlessrun.gd"), "func _ready(")
	check("the run gives a phone's crowd the slack (on_phone(), as its steps)",
		made.find("PHONE_STAND_SLACK") > made.find("if on_phone():") and made.find("if on_phone():") != -1)
	swarm.queue_free()
	me.queue_free()
	await get_tree().process_frame
	print("  the stand-ins: %d, the parked ones untouched, a phone's slack %.0f px" % [proxies.size(), SwarmScript.PHONE_STAND_SLACK])


# =============================================================================
# THE SCREEN'S DRAWS, NOT THE PICTURES' (0.156.0)
# =============================================================================
# The owner's readout: "draws 209", and a spike line's "draws +243" in a boss
# cast. Measured in the container with the pictures left out (zz/spikedraws
# .gd, the world view's own count): a risen spike costs 0.2-0.4 draws - they
# were drawn together already - and the 243 was the readout's own picture,
# redrawn as its text changed. The readout counts the screen now, and says
# apart when a frame redrew a picture.

func _test_the_readout_counts_the_screen() -> void:
	section("The readout counts the screen's draws, and a picture's redraw apart (0.156.0)")
	var src: String = _code_src("res://src/systems/perfoverlay.gd")
	var noted: String = _func_body(src, "func _note_drawn(")
	check("a frame's draws are the screen's own (the root view's canvas), the pictures' redraw kept apart",
		noted.contains("screen_draws()") and noted.contains("parts[\"pictures\"]")
		and _func_body(src, "func screen_draws(").contains("VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME"))
	check("  both draws rows read the screen (draws_text()), not the renderer's total",
		src.count("draws_text()") >= 2 and not src.contains("Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME"))
	var line: String = PerfOverlay.marks_text({"marks": {&"spikes go": 3}, "draws": 5, "pictures": 214})
	check("  a spike line says a picture was redrawn, beside the screen's change",
		line == "spikes go ×3 · draws +5 · a picture redrawn (214 draws)", line)
	check("  and says nothing of pictures when none was",
		PerfOverlay.marks_text({"marks": {&"boss casts": 1}, "draws": 4}) == "boss casts ×1 · draws +4")
	check("  the screen's count is a number here too", PerfOverlay.screen_draws() >= 0)
	print("  the readout's draws: the screen's own, %d now" % PerfOverlay.screen_draws())


# =============================================================================
# A DAY'S MINIGAME GOLD, AND A ROLLBACK THAT HOLDS BACK (0.157.0)
# =============================================================================
# The owner, 14 Nov: "lets fix issues in security". The server now pays an
# account's minigames one allowance a day - every run's gold and every
# chest's coins together - and says what it held back; and a rollback puts
# back nothing that went to the bank, another character or another player
# since. The game says both: the Leave line (healerrunscreen.gd paid_line(),
# Cut the Cloth's too), the chest once in ten minutes (combat.gd
# DAY_FULL_WORDS), and the Save history's line after a restore.

func _test_a_days_minigame_gold_and_a_rollback_held_back() -> void:
	section("A day's minigame gold, and a rollback that holds back what went elsewhere (0.157.0)")
	const HealerScreen := preload("res://src/world/healerrun/healerrunscreen.gd")
	const ClothScreen := preload("res://src/world/cloth/clothscreen.gd")
	const History := preload("res://src/ui/owner/savehistory.gd")
	check("a Leave in words: the gold, and past the day's allowance what was held back; nothing either way, nothing said",
		HealerScreen.paid_line("The Healer's Run", 1000, 0) == "The Healer's Run: 1,000 gold, into your purse."
		and HealerScreen.paid_line("Cut the Cloth", 1000, 750)
			== "Cut the Cloth: 1,000 gold into your purse - 750 held back, today's minigame gold is full."
		and HealerScreen.paid_line("The Healer's Run", 0, 20000)
			== "The Healer's Run: today's minigame gold is full - 20,000 held back."
		and HealerScreen.paid_line("Cut the Cloth", 0, 0) == "")
	var hud_script := GDScript.new()
	hud_script.source_code = "extends Node\nvar said: Array = []\nfunc _push_message(text, _colour = null, _at = 0, _log = false) -> void:\n\tsaid.append(str(text))\n"
	hud_script.reload()
	var hud := Node.new()
	hud.set_script(hud_script)
	add_child(hud)
	var healer = HealerScreen.open(get_tree(), 4, 91, {"most": 1000}, hud)
	healer.finish_request = func(_path: String, _body: Dictionary, _wait: float) -> Dictionary:
		return {"ok": true, "status": 200, "data": {"gold": 250, "held_back": 750, "status": {"gold": 1250}}}
	await get_tree().process_frame
	healer.run.waves_done = 25
	healer.leave()
	for i in 3:
		await get_tree().process_frame
	check("the Healer's Run's Leave says what the server paid, and what it held back - not what the screen counted",
		(hud.get("said") as Array).has("The Healer's Run: 250 gold into your purse - 750 held back, today's minigame gold is full."),
		hud.get("said"))
	var cloth: CanvasLayer = ClothScreen.open(get_tree(), hud, 92, {"rounds": [10, 20]})
	cloth.set("finish_request", func(_p: String, _b: Dictionary, _t: float = 0.0) -> Dictionary:
		return {"ok": true, "status": 200, "data": {"gold": 0, "held_back": 10, "status": {"gold": 1250}}})
	await get_tree().process_frame
	cloth.call("begin")
	(cloth.get("run") as Node2D).set("best", 1)
	cloth.call("ask_to_leave")
	cloth.call("ask_to_leave")
	for i in 3:
		await get_tree().process_frame
	check("  and Cut the Cloth's the same way: the day full, its rounds' gold held back, said so",
		(hud.get("said") as Array).has("Cut the Cloth: today's minigame gold is full - 10 held back."), hud.get("said"))

	# THE CHEST: past the allowance it rolls gear and no coins, said once.
	var noticer_script := GDScript.new()
	noticer_script.source_code = "extends Node2D\nvar notices: Array = []\nfunc show_notice(text) -> void:\n\tnotices.append(str(text))\n"
	noticer_script.reload()
	var me := Node2D.new()
	me.set_script(noticer_script)
	me.add_to_group("player")
	add_child(me)
	var kept_post: Callable = Combat.kill_post
	var kept_token: String = Api.token
	var kept_known: bool = Api.reachability_known
	var kept_online: bool = Api.server_online
	var kept_said: int = int(Combat.get("_day_full_said_at"))
	Api.token = "test-not-a-real-token"
	Api.reachability_known = true
	Api.server_online = true
	Combat.set("_day_full_said_at", -Combat.DAY_FULL_SAY_MSEC)
	Combat.kill_post = func(_path: String, _sent: Dictionary, _timeout: float) -> Dictionary:
		return {"ok": true, "status": 200, "data": {"used": 1, "added": [{"item_id": "ironsword", "quantity": 1}],
			"cut": [], "mythic": "", "pet_won": false, "held_back": 2000, "chest_id": "chest:endless:0"}}
	await Combat.report_endless_kill("bushmage", me)
	await Combat.report_endless_kill("bushmage", me)
	check("a chest kill past the day's allowance says, once, that no more coins come today",
		(me.get("notices") as Array).count(Combat.DAY_FULL_WORDS) == 1, me.get("notices"))
	Combat.kill_post = func(_path: String, _sent: Dictionary, _timeout: float) -> Dictionary:
		return {"ok": true, "status": 200, "data": {"used": 2, "added": [{"item_id": "goldcoin", "quantity": 2}],
			"cut": [], "mythic": "", "pet_won": false, "held_back": 0, "chest_id": "chest:endless:0"}}
	Combat.set("_day_full_said_at", -Combat.DAY_FULL_SAY_MSEC)
	await Combat.report_endless_kill("bushmage", me)
	check("  and a kill with nothing held back says nothing of it",
		(me.get("notices") as Array).count(Combat.DAY_FULL_WORDS) == 1, me.get("notices"))
	Combat.kill_post = kept_post
	Api.token = kept_token
	Api.reachability_known = kept_known
	Api.server_online = kept_online
	Combat.set("_day_full_said_at", kept_said)
	me.queue_free()
	hud.queue_free()

	# THE ROLLBACK: the Save history says what was held back.
	var answer := {"username": "dave", "character": "Warrior", "taken_at": 0, "was": {"level": 3, "gold": 5, "items": 2},
		"now": {"level": 2, "gold": 9, "items": 4}, "sessions_ended": 1, "held_back_words": "2 x Iron Sword, Jade Helm",
		"knew_where": true}
	check("after a restore, the Save history names what went elsewhere and was not put back twice",
		History.restored_line(answer, "boss").contains("Held back, gone elsewhere since: 2 x Iron Sword, Jade Helm."))
	answer["held_back_words"] = ""
	answer["knew_where"] = false
	check("  and says when an older snapshot could not tell",
		History.restored_line(answer, "boss").contains("An older snapshot: anything given away since may now be twice."))
	answer.erase("knew_where")
	check("  and a server from before says nothing of either",
		not History.restored_line(answer, "boss").contains("Held back") and not History.restored_line(answer, "boss").contains("older snapshot"))
	var window: String = FileAccess.get_file_as_string("res://scene/ui/owner/savehistory.tscn")
	check("  the window's own words no longer say a restore makes a second copy",
		window.contains("is not put back twice") and not window.contains("second copy"))
	print("  the Leave's words, the chest's notice and the Save history's line, as the server answers")

