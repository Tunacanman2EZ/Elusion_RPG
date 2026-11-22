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
	# WHERE A PAD LANDS (exportgamedata.gd, "arrivals"): presence.py lets a
	# step land there free when it holds moves to a walk.
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/gamedata.json"))
	var areas: Dictionary = (data as Dictionary).get("areas", {}) if data is Dictionary else {}
	var with_pads: Array = []
	for area_id in areas.keys():
		var scene_text: String = FileAccess.get_file_as_string(str((areas[area_id] as Dictionary).get("scene", "")))
		if scene_text.contains("res://src/world/teleporter.gd"):
			with_pads.append(area_id)
	var all_written: bool = not with_pads.is_empty()
	for area_id in with_pads:
		var arrivals: Array = (areas[area_id] as Dictionary).get("arrivals", [])
		all_written = all_written and not arrivals.is_empty()
	check("gamedata.json writes where each area's teleport pads land, for the server's walk check (%s)" % ", ".join(
		PackedStringArray(with_pads)), all_written and with_pads.has("elusion"), with_pads)
	# THE WAYSTONES ARE PADS TOO (0.161.3): a trip lands in front of a stone,
	# inside the Big Field too, so each landing is one of its "arrivals".
	var stone_consts: Dictionary = (load("res://src/world/waystones.gd") as GDScript).get_script_constant_map()
	var stone_area: String = String(stone_consts.get("AREA", ""))
	var written: Array = ((areas.get(stone_area, {}) as Dictionary).get("arrivals", [])) if areas.has(stone_area) else []
	var landings: Array = []
	for stone in stone_consts.get("STONES", []):
		var at: Vector2 = (stone as Dictionary)["at"] + (stone_consts.get("ARRIVE", Vector2.ZERO) as Vector2)
		landings.append(at)
	var missing: Array = []
	for at in landings:
		var found: bool = false
		for point in written:
			if point is Array and (point as Array).size() == 2 \
					and Vector2(float(point[0]), float(point[1])).distance_to(at) < 0.5:
				found = true
		if not found:
			missing.append(at)
	var exported: Array = (load("res://src/tools/exportgamedata.gd") as GDScript).call("waystone_arrivals", stone_area)
	check("  and where each of the %d waystones lands, in %s - the export writes them (re-export when a stone moves)" % [
		landings.size(), stone_area], landings.size() >= 6 and missing.is_empty() and exported.size() == landings.size(),
		[missing, exported.size()])
	print("  the Leave's words, the chest's notice and the Save history's line, as the server answers")



# ALL SIX OPEN (0.158.0). The owner, of the site calling four of the games
# "coming soon": "they are not coming soon they are already out" - and chose
# to open them for everyone. A player's card (not the owner's) shows every
# game, no tile says TESTING, and the Testing Ground stays the owner's.
func _test_every_minigame_is_open() -> void:
	section("ALL SIX OPEN (0.158.0): every minigame on a player's card, none marked TESTING")
	var was_owner: bool = Api.is_owner
	Api.is_owner = false
	var card_hud := Control.new()
	add_child(card_hud)
	var card = (load("res://src/ui/minigames/minigamescard.gd") as GDScript).call("attach", card_hud)
	card.set("area_now", func() -> String: return "elusion")
	card.set("class_now", func() -> String: return "warrior")
	card.set("list_request", func(_p: String, _t: float = 0.0) -> Dictionary: return {"ok": false})
	card.call("open")
	await get_tree().process_frame
	var tiles: Dictionary = {
		"the Endless": card.endless_box, "the Healer's Run": card.healer_box,
		"the Mage's Stand": card.stand_box, "the Descent": card.descent_box,
		"the Forge": card.forge_box, "Cut the Cloth": card.cloth_box,
	}
	var hidden: Array = []
	for game in tiles:
		if not (tiles[game] as Control).visible:
			hidden.append(game)
	check("a player's Minigames card shows all six games (%d of 6)" % (6 - hidden.size()), hidden.is_empty(), hidden)
	var marked: Array = []
	for tag in card.find_children("tag", "Label", true, false):
		# A game still being built (Crownfall, 0.162.0) wears TESTING on a
		# tile only its owner sees.
		if (tag as Label).text == "TESTING" and (tag as Label).is_visible_in_tree():
			marked.append(tag.get_parent().get_parent().get_parent().get_parent().name)
	check("  and no tile a player sees says TESTING", marked.is_empty(), marked)
	check("  Crownfall stays the owner's while it is built", not card.crown_box.visible)
	check("  the Testing Ground stays the owner's", not card.testing_box.visible)
	Api.is_owner = was_owner
	card_hud.queue_free()
	await get_tree().process_frame
	print("  all six open: done")


# LEVERS ONLY FROM NEAR (0.158.0). presence.py takes a pull only from a
# player near that lever, by gamedata.json's "levers" - written by the
# exporter, name (the path a pull goes by) -> spot. A lever renamed or moved
# without a re-export would have every honest pull refused, so each area's
# scene is built and its levers held to what the file says.
func _test_levers_written_where_they_stand() -> void:
	section("LEVERS ONLY FROM NEAR (0.158.0): gamedata.json says where every lever stands, by the name a pull goes by")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/gamedata.json"))
	var areas: Dictionary = (data as Dictionary).get("areas", {}) if data is Dictionary else {}
	var wrong: Array = []
	var seen: int = 0
	for area_id in areas.keys():
		var area: Dictionary = areas[area_id]
		var packed: PackedScene = load(str(area.get("scene", ""))) as PackedScene
		if packed == null:
			continue
		var root: Node = packed.instantiate()
		var found: Dictionary = {}
		_levers_in(root, root, found)
		root.free()
		seen += found.size()
		var written: Dictionary = area.get("levers", {}) if area.get("levers") is Dictionary else {}
		if not area.has("levers"):
			wrong.append("%s has no \"levers\"" % area_id)
			continue
		for lever_name in found:
			var spot: Array = written.get(lever_name, [])
			var at: Vector2 = found[lever_name]
			if spot.size() != 2 or absf(float(spot[0]) - at.x) > 0.5 or absf(float(spot[1]) - at.y) > 0.5:
				wrong.append("%s: %s" % [area_id, lever_name])
		for lever_name in written:
			if not found.has(lever_name):
				wrong.append("%s: %s is in the file and not the scene" % [area_id, lever_name])
	check("every area's levers are written by name and spot (%d lever(s); re-export when one moves)" % seen,
		wrong.is_empty() and seen > 0, wrong)
	var presence_script: String = FileAccess.get_file_as_string("res://src/systems/presence.gd")
	check("  by the name a pull goes by: the lever's path in its area's scene",
		presence_script.contains("String(scene.get_path_to(lever))"))
	print("  levers written where they stand: done")


func _levers_in(root: Node, node: Node, found: Dictionary) -> void:
	for child in node.get_children():
		var script: Script = child.get_script() as Script
		if script != null and script.resource_path == "res://src/world/lever.gd":
			var xform := Transform2D.IDENTITY
			var chain: Array = []
			var at: Node = child
			while at != null:
				chain.push_front(at)
				if at == root:
					break
				at = at.get_parent()
			for piece in chain:
				if piece is Node2D:
					xform = xform * (piece as Node2D).transform
			found[String(root.get_path_to(child))] = xform.origin
		if not child.scene_file_path.begins_with("res://scene/enemy/"):
			_levers_in(root, child, found)


# THE ENDLESS'S RECEIPTS (0.159.0). The server books the Endless now, and with
# its ELUSION_ENDLESS_RECEIPTS on a chest kill is paid only against its own
# count: a 202 is "not yet", asked again as an ordinary kill's is, and given
# up on in time, said once. The server's half is test_receipts.py R-9.
func _test_the_chest_waits_for_its_receipt() -> void:
	section("THE ENDLESS'S RECEIPTS (0.159.0): a chest kill waits for the server's count, as a kill does")
	check("the game is build 8, the first whose chest kill waits (Combat.ENDLESS_RECEIPT_BUILD)",
		Api.BUILD >= 8 and Combat.ENDLESS_RECEIPT_BUILD == 8, [Api.BUILD, Combat.ENDLESS_RECEIPT_BUILD])
	var stand_script := GDScript.new()
	stand_script.source_code = "extends Node2D\nvar notices: Array = []\n" \
		+ "func show_notice(message: String) -> void:\n\tnotices.append(message)\n"
	stand_script.reload()
	var killer: Node2D = Node2D.new()
	killer.set_script(stand_script)
	killer.add_to_group("player")
	add_child(killer)
	var chest_script := GDScript.new()
	chest_script.source_code = "extends Node\nvar wins: Array = []\nfunc note_win(data: Dictionary) -> void:\n\twins.append(data)\n"
	chest_script.reload()
	var chest: Node = Node.new()
	chest.set_script(chest_script)
	chest.add_to_group(&"endless_chest")
	add_child(chest)
	var kept_post: Callable = Combat.kill_post
	var kept_wait: float = Combat.receipt_wait_seconds
	var kept_token: String = Api.token
	var kept_known: bool = Api.reachability_known
	var kept_online: bool = Api.server_online
	Api.token = "test-not-a-real-token"
	var posts: Array = []
	var answers: Array = []
	Combat.kill_post = func(path: String, body: Dictionary, _timeout: float) -> Dictionary:
		posts.append([path, body.duplicate()])
		await get_tree().process_frame
		return answers.pop_front() if answers.size() > 1 else answers[0]
	var pending := {"ok": true, "status": 202, "data": {"pending": true, "retry_after_ms": 100}}
	var paid := {"ok": true, "status": 200, "data": {"enemy_id": "bushmage", "added": [], "used": 1, "cut": []}}
	answers.append_array([pending, pending, paid])
	Api.reachability_known = true
	Api.server_online = true
	await Combat.report_endless_kill("bushmage", killer)
	var alike: bool = posts.size() == 3
	for entry in posts:
		alike = alike and entry[0] == "/api/minigames/kill" and entry[1] == posts[0][1]
	check("pending twice and then paid: three posts of the same chest kill, into the chest once",
		alike and (chest.get("wins") as Array).size() == 1 and (killer.get("notices") as Array).is_empty(),
		[posts, chest.get("wins"), killer.get("notices")])
	posts.clear()
	answers.clear()
	answers.append(pending)
	Combat.receipt_wait_seconds = 0.35
	Combat._chest_unseen_said_at = -Combat.CHEST_UNSEEN_SAY_MSEC
	Api.reachability_known = true
	Api.server_online = true
	await Combat.report_endless_kill("bushmage", killer)
	check("never counted: it gives up in time, nothing in the chest, and says why once",
		posts.size() >= 2 and posts.size() <= 6 and (chest.get("wins") as Array).size() == 1
		and (killer.get("notices") as Array).size() == 1, [posts.size(), killer.get("notices")])
	Api.reachability_known = true
	Api.server_online = true
	await Combat.report_endless_kill("bushmage", killer)
	check("  and a second one given up on inside a minute is not said again - elites fall by the dozen",
		(killer.get("notices") as Array).size() == 1, killer.get("notices"))
	Combat.kill_post = kept_post
	Combat.receipt_wait_seconds = kept_wait
	Api.token = kept_token
	Api.reachability_known = kept_known
	Api.server_online = kept_online
	killer.queue_free()
	chest.queue_free()
	await get_tree().process_frame
	print("  the chest waits for its receipt: done")


# THE FORGE TOGETHER (0.160.0, step 3 of FORGE_PLAN.txt). Two islands in one
# tree, each on a stand-in link that passes "en" as the server does (JSON and
# back): the leader runs the heat, the floods, the essence and the sprites,
# the other follows its line; a fall is down, not out, until everybody is.
# The server's half is the API's test_presence.py P-22 and test_combatbook
# CB-17.
func _forge_party_link_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = _party_link_script().source_code + "\nfunc forge_rooms() -> bool:\n\treturn open\n"
	script.reload()
	return script


func _forge_island_for_test(body_script: GDScript, class_id: String, asks_ready: bool = false) -> Array:
	"""[island, run, body]: a stand-in island with the run and its player by
	the anvil."""
	const Run := preload("res://src/world/forge/forgerun.gd")
	var island := Node2D.new()
	add_child(island)
	var world := Node2D.new()
	world.name = "ysortworld"
	island.add_child(world)
	for holder in ["props", "enemies", "interactables"]:
		var n := Node2D.new()
		n.name = holder
		world.add_child(n)
	var body := Node2D.new()
	body.set_script(body_script)
	island.add_child(body)
	body.global_position = Run.CENTRE + Vector2(0, 150)
	var run: Node = Run.new()
	run.name = "forgerun"
	run.set("player_override", body)
	run.set("class_override", class_id)
	# The anvil as before 0.161.0, unless asked: the Ready panel has its own
	# test (_test_ready_first()).
	run.set("asks_ready", asks_ready)
	island.add_child(run)
	return [island, run, body]


func _test_the_forge_together() -> void:
	section("THE FORGE TOGETHER (0.160.0): one run for the party - the leader's heat, floods, essence and sprites, a fall down until everybody is")
	const Run := preload("res://src/world/forge/forgerun.gd")
	var body_script := GDScript.new()
	body_script.source_code = _forge_body_script().source_code + "var down_in_run: bool = false\n"
	body_script.reload()
	var picture_script := GDScript.new()
	picture_script.source_code = "extends Node2D\nvar class_id: String = \"\"\nvar effects: Array = []\n"
	picture_script.reload()
	var made_a: Array = _forge_island_for_test(body_script, "mage")
	var made_b: Array = _forge_island_for_test(body_script, "tank")
	var run_a: Node = made_a[1]
	var run_b: Node = made_b[1]
	var body_a: Node2D = made_a[2]
	var body_b: Node2D = made_b[2]
	await get_tree().process_frame
	await get_tree().process_frame
	var picture_a := Node2D.new()
	picture_a.set_script(picture_script)
	picture_a.set("class_id", "mage")
	var picture_b := Node2D.new()
	picture_b.set_script(picture_script)
	picture_b.set("class_id", "tank")
	add_child(picture_a)
	add_child(picture_b)
	var Link: GDScript = _forge_party_link_script()
	var la: Node = Link.new()
	var lb: Node = Link.new()
	add_child(la)
	add_child(lb)
	la.set("me", 1)
	lb.set("me", 2)
	la.set("peers", [lb])
	lb.set("peers", [la])
	la.set("bodies", {2: picture_b})
	lb.set("bodies", {1: picture_a})
	for pair in [[run_a, la], [run_b, lb]]:
		var party: Node = (pair[0] as Node).get("party")
		party.set("link", pair[1])
		(pair[1] as Node).run_received.connect(Callable(party, "_on_run"))
		(pair[1] as Node).lead_changed.connect(Callable(party, "_on_lead"))
	var party_a: Node = run_a.get("party")
	var party_b: Node = run_b.get("party")
	for r in [run_a, run_b]:
		r.set("_spawn_clock", 9999.0)
		r.set("_essence_clock", 9999.0)
	var roles: bool = bool(run_a.call("party_on")) and not bool(run_a.call("following")) and bool(run_b.call("following"))
	var says: bool = _code_src("res://src/systems/presence.gd").contains("\"fp\": FORGE_PARTY") \
		and _code_src("res://src/systems/presence.gd").contains("message.get(\"fr\", 0)")
	check("the game says it plays a party's Forge as one run ('fp'), and only shares one with a server that seats it ('fr'); the first in leads",
		roles and says and bool(party_b.call("shares")), [roles, says])

	# ---- the countdown, lit by the follower ----
	body_b.global_position = Run.CENTRE
	run_b.call("_process", Run.START_HOLD + 0.05)
	var asked: bool = int(run_a.get("state")) == Run.State.COUNTDOWN and int(run_a.get("run_key")) > 0
	party_a.call("flush")
	var both: bool = int(run_b.get("state")) == Run.State.COUNTDOWN and int(run_b.get("run_key")) == int(run_a.get("run_key"))
	run_b.call("_process", Run.COUNTDOWN_SECONDS + 0.1)
	var waits: bool = int(run_b.get("state")) == Run.State.COUNTDOWN
	check("  the other lights the forge: the countdown on both screens, and the follower waits for the leader to start",
		asked and both and waits, [asked, both, waits])

	# ---- the run, scaled for two, the tank's light for the party ----
	run_a.call("_process", Run.COUNTDOWN_SECONDS + 0.1)
	party_a.call("flush")
	var same_key: bool = int(run_b.get("run_key")) == int(run_a.get("run_key"))
	check("  the countdown over, both run it, scaled for two - %d alive, %d at once, x%.2f health - in a tank's light though the leader is a mage"
		% [int(run_a.call("alive_cap")), int(run_a.call("spawn_count")), float(run_a.call("health_scale"))],
		bool(run_a.call("running")) and bool(run_b.call("running")) and same_key
		and int(run_a.get("players")) == 2 and int(run_b.get("players")) == 2
		and int(run_a.call("alive_cap")) == 15 and int(run_a.call("spawn_count")) == 2
		and is_equal_approx(float(run_a.call("health_scale")), 1.2)
		and is_equal_approx(float(run_a.get("safe")), Run.SAFE_TANK) and is_equal_approx(float(run_b.get("safe")), Run.SAFE_TANK),
		[run_a.get("players"), run_b.get("players"), run_a.get("safe"), run_b.get("safe")])
	run_b.set("_spawn_clock", 0.0)
	run_b.call("_process", 0.05)
	check("  the follower brings no sprites of its own - the leader's are the party's",
		(run_b.get("monsters") as Array).is_empty() and int(run_b.get("_spawns_owed")) == 0, run_b.get("monsters"))

	# ---- the island sinks on both ----
	run_a.set("heat", 0.999)
	run_a.call("_process", Run.FLOOD_SECONDS + 0.5)
	party_a.call("flush")
	var first: int = int(Run.ORDER[0])
	check("  the leader's flood is the other's: the same slice gone, the heat back to nought",
		int(run_a.get("floods")) == 1 and int(run_b.get("floods")) == 1 and (run_b.get("flooded") as Dictionary).has(first)
		and int(run_b.get("flooding")) == -1 and float(run_b.get("heat")) < 0.05,
		[run_a.get("floods"), run_b.get("floods"), run_b.get("flooded"), run_b.get("heat")])

	# ---- the essence, walked over by the other ----
	run_a.call("_lay_essence")
	var essence_a: Node2D = run_a.get("_essence")
	party_a.call("flush")
	var essence_b: Node2D = run_b.get("_essence")
	var mirrored: bool = essence_a != null and essence_b != null and essence_b.position.distance_to(essence_a.position) < 1.0
	run_a.set("heat", 0.5)
	body_b.global_position = essence_b.global_position if essence_b != null else Vector2.ZERO
	run_b.call("_process", 0.016)
	var told: bool = int(run_b.get("took")) == 1 and run_b.get("_essence") == null
	party_b.call("flush")
	var cooled: bool = is_equal_approx(float(run_a.get("heat")), 0.5 - Run.ESSENCE_COOL) and run_a.get("_essence") == null
	party_a.call("flush")
	check("  the leader's ice essence lies on both islands; the other walks over it and the leader's forge cools - once",
		mirrored and told and cooled and run_b.get("_essence") == null, [mirrored, told, cooled])

	# ---- every tank's walkway ----
	picture_b.global_position = Run.CENTRE + Vector2(Run.RADIUS + 60.0, 0.0)
	picture_b.set("effects", ["ring"])
	run_a.call("_step_walkways", 1.0)
	check("  the party's tank, ring lit in the lava, lays a walkway on the mage's island too (%d cells)" % int(run_a.call("walkway_cells")),
		int(run_a.call("walkway_cells")) > 0, run_a.call("walkway_cells"))
	picture_b.set("effects", [])

	# ---- a mirrored sprite fills the Forge's chest, not the Endless's ----
	var sprite: Node = run_a.call("_bring", Run.SPRITE, Run.CENTRE + Vector2(400, 0), 1.0)
	await get_tree().process_frame
	var props: Dictionary = sprite.call("net_props") if sprite != null else {}
	var mirror: Node = (load("res://scene/enemy/%s.tscn" % Run.SPRITE) as PackedScene).instantiate()
	mirror.call("net_apply_props", props)
	var stranger: Node = (load("res://scene/enemy/%s.tscn" % Run.SPRITE) as PackedScene).instantiate()
	stranger.call("net_apply_props", {"rx": 1, "cg": "somewhere"})
	check("  a sprite's copy on a party's screen carries the Forge's chest ('cg'), so a follower's kill pays the Forge - and no other name is taken",
		str(props.get("cg", "")) == "forge" and str(mirror.get_meta(&"chest_game", "")) == "forge"
		and mirror.has_meta(&"run_extra") and not stranger.has_meta(&"chest_game"), props)
	mirror.free()
	stranger.free()

	# ---- down, not out, until everybody is ----
	var downed: bool = bool(run_a.call("knock_out", body_a))
	var down_not_out: bool = downed and bool(run_a.get("down")) and bool(run_a.call("running")) \
		and is_equal_approx(body_a.modulate.a, Run.OUT_ALPHA) and body_a.get("down_in_run") == true
	var player_src: String = _code_src("res://src/characters/player.gd")
	var nothing_lands: bool = _func_body(player_src, "func take_damage(").contains("if DescentBoons.out or down_in_run:") \
		and _func_body(player_src, "func effects_let_attack(").contains("if down_in_run:")
	var pays_nothing: bool = _func_body(_code_src("res://src/enemies/baseenemy.gd"), "func _die(").contains("killer.get(\"down_in_run\") != true")
	party_a.call("flush")
	run_a.call("_process", 0.016)
	var still_on: bool = bool(run_a.call("running"))
	run_b.call("knock_out", body_b)
	party_b.call("flush")
	run_a.call("_process", 0.016)
	party_a.call("flush")
	check("  down in a party is not the end: a ghost by the anvil, nothing lands and its blows pay nothing, while anybody stands - and with the other down too, it is over on both",
		down_not_out and nothing_lands and pays_nothing and still_on and not bool(run_a.call("running"))
		and not bool(run_b.call("running")) and is_equal_approx(body_a.modulate.a, 1.0) and body_b.get("down_in_run") == false,
		[down_not_out, nothing_lands, pays_nothing, still_on, run_a.get("state"), run_b.get("state")])

	# ---- the leader leaves: the other takes the run over ----
	run_a.call("begin_countdown")
	party_a.call("flush")
	run_a.call("_process", Run.COUNTDOWN_SECONDS + 0.1)
	party_a.call("flush")
	var left_behind := Node2D.new()
	left_behind.set_script(body_script)
	left_behind.set_meta(Run.MARK, true)
	(made_b[0] as Node).get_node("ysortworld/enemies").add_child(left_behind)
	lb.set("leader", 2)
	lb.lead_changed.emit("forge", 2, 1)
	check("  the leader gone, the other runs on from its own island: the old leader's sprites, mirrored there, are its own now - the Forge's chest's",
		bool(run_b.call("running")) and not bool(run_b.call("following")) and (run_b.get("monsters") as Array).has(left_behind)
		and str(left_behind.get_meta(Run.CHEST_META, "")) == Run.CHEST_GAME, [run_b.get("monsters"), run_b.call("following")])

	for n in [made_a[0], made_b[0], picture_a, picture_b, la, lb]:
		(n as Node).queue_free()
	await get_tree().process_frame
	print("  the forge together: done")


# =============================================================================
# THE MAGE'S STAND TOGETHER (0.161.0)
# =============================================================================
# The owner: "the forge should be 4 player mages stand also but the cloth 1
# player". Two games' Stands in one tree, each with a stand-in presence link
# that passes "en" as the server does (JSON and back): the leader's waves,
# gate, wall and star; the same monsters on both screens from the leader's
# seed; every hit and meteor on both; the picks waited for; Repair, the
# star's claim and its call done by the leader for the other. The server's
# half is the API's test_presence.py P-29.
func _stand_party_link_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = _party_link_script().source_code + "\nfunc stand_rooms() -> bool:\n\treturn open\n"
	script.reload()
	return script


func _stand_for_test(Stand: GDScript, PartyScript: GDScript, link: Node, seed_value: int) -> Array:
	"""[run, party]: a Stand with its party on `link`, driven by hand."""
	var run: Node2D = Stand.new()
	run.set("seed_value", seed_value)
	var party: Node = PartyScript.new()
	party.set("link", link)
	party.set("run", run)
	run.set("party", party)
	run.add_child(party)
	add_child(run)
	run.set_process(false)
	party.set_process(false)
	party.start_now.connect(Callable(run, "begin_run"))
	return [run, party]


func _stand_monsters(run: Node) -> Dictionary:
	"""Every living monster by its slot: [kind, spot, health]."""
	var out: Dictionary = {}
	for m in (run.get("monsters") as Node).get_children():
		if float(m.get("dying")) < 0.0:
			out[int(m.get("slot"))] = [str(m.get("kind")), (m as Node2D).position.round(), snappedf(float(m.get("health")), 0.001)]
	return out


func _stand_monster(run: Node, slot: int) -> Node:
	for m in (run.get("monsters") as Node).get_children():
		if int(m.get("slot")) == slot:
			return m
	return null


func _test_the_stand_together() -> void:
	section("THE MAGE'S STAND TOGETHER (0.161.0): up to four mages, two each side - the leader's waves, gate and star, every hit on every screen")
	const Stand := preload("res://src/world/magestand/magestand.gd")
	const PartyScript := preload("res://src/world/magestand/magestandparty.gd")
	var picture_script := GDScript.new()
	picture_script.source_code = "extends Node2D\nvar display_name: String = \"\"\n"
	picture_script.reload()
	var picture_a := Node2D.new()
	picture_a.set_script(picture_script)
	picture_a.set("display_name", "ann")
	var picture_b := Node2D.new()
	picture_b.set_script(picture_script)
	picture_b.set("display_name", "bob")
	add_child(picture_a)
	add_child(picture_b)
	var Link: GDScript = _stand_party_link_script()
	var la: Node = Link.new()
	var lb: Node = Link.new()
	add_child(la)
	add_child(lb)
	la.set("me", 1)
	lb.set("me", 2)
	la.set("peers", [lb])
	lb.set("peers", [la])
	la.set("bodies", {2: picture_b})
	lb.set("bodies", {1: picture_a})
	# Different seeds: what makes the monsters alike is the leader's group.
	var made_a: Array = _stand_for_test(Stand, PartyScript, la, 11)
	var made_b: Array = _stand_for_test(Stand, PartyScript, lb, 9922)
	var run_a: Node2D = made_a[0]
	var run_b: Node2D = made_b[0]
	var party_a: Node = made_a[1]
	var party_b: Node = made_b[1]
	await get_tree().process_frame
	var says: bool = _code_src("res://src/systems/presence.gd").contains("message.get(\"ms\", 0)") \
		and _code_src("res://src/systems/presence.gd").contains("entry[\"cls\"] = class_override") \
		and _code_src("res://src/world/magestand/magestandscreen.gd").contains("Presence.stand_rooms() and Party.members.size() > 1")
	var spot: Dictionary = run_b.call("presence_state")
	check("the Stand is shared with a server that seats it a room per party ('ms'), every mage drawn as the mage; the first in leads; her steps are her mage's",
		says and bool(run_a.call("party_on")) and not bool(run_a.call("following")) and bool(run_b.call("following"))
		and str(spot.get("a", "")) == "magestand" and int(spot.get("aim", 0)) == -1
		and is_equal_approx(float(Stand.body_lift()), 19.0)
		and ((spot["at"] as Vector2) - (run_b.get("mage") as Node2D).global_position).is_equal_approx(Vector2(0, 19)),
		[says, spot, Stand.body_lift()])

	# ---- Ready, the countdown, two each side ----
	party_a.call("_timed_process", 0.05)
	party_a.call("flush")
	party_b.call("_timed_process", 0.05)
	var sides: bool = is_equal_approx(float(run_a.get("her_side")), -1.0) and is_equal_approx(float(run_b.get("her_side")), 1.0) \
		and (run_b.get("mage") as Node2D).position.x > 0.0 and int(party_b.get("key")) == int(party_a.get("key")) and int(party_a.get("key")) > 0
	party_b.call("set_ready", true)
	party_b.call("flush")
	party_a.call("set_ready", true)
	party_a.call("_timed_process", 0.05)
	party_a.call("flush")
	var counting: bool = float(party_a.get("counting")) > 0.0 and float(party_b.get("counting")) > 0.0
	for i in 70:
		party_a.call("_timed_process", 0.05)
		party_b.call("_timed_process", 0.05)
	check("  the leader's key heard; everyone Ready, a count of three on both; then both begin, for two - the leader left of the gate, the other right",
		sides and counting and bool(run_a.get("begun")) and bool(run_b.get("begun")) and int(run_a.get("players")) == 2
		and int(run_b.get("players")) == 2, [sides, counting, run_a.get("begun"), run_b.get("begun"), run_b.get("players")])

	# ---- the leader's group, the same on both screens ----
	run_a.call("step", Stand.READY_SECONDS + 0.05)
	run_a.call("step", 0.01)
	party_a.call("flush")
	var mine: Dictionary = _stand_monsters(run_a)
	var theirs: Dictionary = _stand_monsters(run_b)
	check("  the leader's first wave, scaled for two (%d monsters, %d at once, x%.1f health): its group comes in on both screens alike - kind, spot and health, by its seed"
		% [int(run_a.call("wave_count", 1)), int(run_a.call("group_size")), float(run_a.call("party_health"))],
		int(run_a.call("wave_count", 1)) == 38 and int(run_a.call("group_size")) == 14 and is_equal_approx(float(run_a.call("party_health")), 1.1)
		and mine.size() == 14 and mine == theirs and int(run_b.get("wave")) == 1 and int(run_b.get("_to_spawn")) == 24
		and int(run_b.get("state")) == Stand.State.WAVE, [mine.size(), theirs.size(), run_b.get("wave"), run_b.get("_to_spawn")])

	# ---- every hit on every screen; a meteor's picture ----
	var hit_b: Node = _stand_monster(run_b, 3)
	run_b.call("hurt", hit_b, 5.0)
	run_b.call("hurt", _stand_monster(run_b, 4), 1000.0)
	party_b.call("flush")
	var hit_a: Node = _stand_monster(run_a, 3)
	var same_health: bool = is_equal_approx(float(hit_a.get("health")), float(hit_b.get("health")))
	var died: bool = float(_stand_monster(run_a, 4).get("dying")) >= 0.0
	party_b.call("flush")
	var kills_told: bool = int(run_b.get("my_kills")) == 1 and int(run_a.get("my_kills")) == 0 and int(run_a.get("slain")) == 1
	var board: Array = party_a.call("roster")
	var board_b: bool = board.size() == 2 and str(board[1]["name"]) == "bob" and int(board[1]["kills"]) == 1
	var total_before: float = 0.0
	for m in (run_a.get("monsters") as Node).get_children():
		total_before += float(m.get("health"))
	run_b.call("drop_meteor", Vector2(10, -50))
	party_b.call("flush")
	var pictured: bool = false
	for fall in run_a.get("falling"):
		pictured = pictured or (bool(fall.get("cosmetic", false)) and (fall["at"] as Vector2).is_equal_approx(Vector2(10, -50)))
	run_a.call("_falls", Stand.FALL_SECONDS + 0.01)
	var total_after: float = 0.0
	for m in (run_a.get("monsters") as Node).get_children():
		total_after += float(m.get("health"))
	var crater_cold: bool = not (run_a.get("craters") as Array).is_empty() and not bool((run_a.get("craters") as Array).back().get("burns", true))
	check("  the other's hit lands on the leader's copy too, and its kill is its own on the board; its meteor falls on the leader's screen, hurting nothing there",
		same_health and died and kills_told and board_b and pictured and crater_cold and is_equal_approx(total_before, total_after),
		[same_health, died, kills_told, board_b, pictured, crater_cold, total_before, total_after])

	# ---- the gate and the wall are the leader's ----
	run_a.set("door", 120.0)
	run_a.call("_breach", 2)
	party_a.call("flush")
	var broke: bool = is_equal_approx(float(run_b.get("door")), 120.0) and bool((run_b.get("stretches") as Array)[2]["broken"])
	run_a.call("_rebuild", 2, 0.5)
	party_a.call("flush")
	var mended: bool = not bool((run_b.get("stretches") as Array)[2]["broken"]) and is_equal_approx(float((run_b.get("stretches") as Array)[2]["health"]), 150.0)
	run_b.set("door", 400.0)
	run_b.call("_move_monsters", 0.01)
	check("  the leader's gate and wall are the other's: struck to 120, a stretch breached and built again - and the other's own monsters strike nothing",
		broke and mended and is_equal_approx(float(run_b.get("door")), 400.0), [broke, mended, run_b.get("door")])
	run_b.set("door", 120.0)

	# ---- the pick waits for the party; the other's Repair mends the leader's wall ----
	run_a.set("wave", 3)
	run_b.set("wave", 3)
	run_a.call("_end_wave")
	party_a.call("flush")
	var both_pick: bool = int(run_a.get("state")) == Stand.State.PICK and int(run_b.get("state")) == Stand.State.PICK \
		and not (run_b.get("offers") as Array).is_empty()
	party_b.call("flush")
	var says_picking: bool = int(party_a.call("flags_of", 2)) & PartyScript.PICKING != 0
	run_a.set("offers", ["cast"])
	run_a.call("pick", 0)
	var held: bool = bool(run_a.call("_held_for_picks", 0.1)) and bool(run_a.get("waiting_on_party"))
	run_b.set("offers", ["patch"])
	run_b.call("pick", 0)
	party_b.call("flush")
	check("  three waves held: both pick; the leader's next wave waits for the other's; its Repair mends the leader's gate (120 -> %d), and the wave goes on"
		% roundi(float(run_a.get("door"))),
		both_pick and says_picking and held and int(party_b.get("picked_through")) == 3 and is_equal_approx(float(run_a.get("door")), 240.0)
		and not bool(run_a.call("_held_for_picks", 0.1)) and int(run_b.get("state")) != Stand.State.PICK,
		[both_pick, says_picking, held, party_b.get("picked_through"), run_a.get("door"), run_b.get("state")])

	# ---- one star for the party: dropped, claimed together, called by the other ----
	run_a.set("state", Stand.State.WAVE)
	run_b.set("state", Stand.State.WAVE)
	party_a.call("flush")
	run_a.call("_drop_star")
	party_a.call("flush")
	var same_spot: bool = str(run_b.get("star_state")) == "dropping" and (run_b.get("star_at") as Vector2).is_equal_approx(run_a.get("star_at"))
	run_a.call("_star", Stand.STAR_DROP_SECONDS + 0.01)
	run_b.call("_star", Stand.STAR_DROP_SECONDS + 0.01)
	run_b.call("_strike_star")
	party_b.call("flush")
	var counted: bool = int(run_a.get("star_hits")) == 1 and int(run_b.get("star_hits")) == 0
	for i in 4:
		run_a.call("_strike_star")
	party_a.call("flush")
	var claimed: bool = str(run_a.get("star_state")) == "held" and str(run_b.get("star_state")) == "held" and Stand.claim_hits(2) == 5
	run_b.call("call_star")
	party_b.call("flush")
	party_a.call("flush")
	check("  the leader's star lies at the same spot on both; the other's meteor counts toward the claim (5 for two); claimed, the other calls it - and it falls on the same monsters on both",
		same_spot and counted and claimed and str(run_a.get("star_state")) == "falling" and str(run_b.get("star_state")) == "falling"
		and (run_a.get("star_marked") as Array).size() == (run_b.get("star_marked") as Array).size()
		and (run_a.get("star_marked") as Array).size() > 0,
		[same_spot, counted, claimed, run_a.get("star_state"), run_b.get("star_state")])

	# ---- the portal falls on both ----
	run_a.set("state", Stand.State.LOST)
	party_a.call("flush")
	check("  the leader's portal falls: the run is over on the other's screen too",
		int(run_b.get("state")) == Stand.State.LOST, run_b.get("state"))

	# ---- a game come late plays its own; the last run's end is no new run ----
	var lc: Node = Link.new()
	add_child(lc)
	lc.set("me", 3)
	var made_c: Array = _stand_for_test(Stand, PartyScript, lc, 5)
	var party_c: Node = made_c[1]
	await get_tree().process_frame
	party_c.call("_on_run", 1, {"r": run_a.call("line")})
	var waits: bool = int(party_c.get("key")) == 0
	run_a.set("state", Stand.State.WAVE)
	party_c.call("_on_run", 1, {"r": run_a.call("line")})
	check("  a game come late hears a run begun and plays its own; one that hears the last run's end waits for the next",
		waits and int(party_c.get("key")) == PartyScript.ALONE and not bool(party_c.call("active")), [waits, party_c.get("key")])

	# ---- the leader leaves: the other runs on ----
	run_a.set("state", Stand.State.WAVE)
	run_b.set("state", Stand.State.WAVE)
	lb.set("leader", 2)
	party_b.call("_timed_process", 0.05)
	check("  the leader gone, the other runs the waves from where it stands",
		not bool(run_b.call("following")) and bool(party_b.call("leads")), run_b.call("following"))

	# ---- alone, the Stand as it always was ----
	var alone: Node2D = Stand.new()
	add_child(alone)
	await get_tree().process_frame
	alone.set("wave", 1)
	check("  alone: no party - 24 a first wave, 9 at once, no more health, no hit told",
		int(alone.call("wave_count", 1)) == 24 and int(alone.call("group_size")) == 9 and is_equal_approx(float(alone.call("party_health")), 1.0)
		and not bool(alone.call("party_on")), [alone.call("wave_count", 1), alone.call("group_size")])

	# ---- the screen: Ready, the lobby, her side ----
	const Screen := preload("res://src/world/magestand/magestandscreen.gd")
	var lx: Node = Link.new()
	add_child(lx)
	lx.set("me", 5)
	lx.set("leader", 5)
	lx.set("bodies", {6: picture_b})
	var screen: CanvasLayer = Screen.new()
	screen.set("party_rooms", func() -> bool: return true)
	screen.set("party_link", lx)
	add_child(screen)
	await get_tree().process_frame
	screen.call("paint")
	var ready_word: bool = str((screen.get("start_button") as Button).text).begins_with("Ready")
	screen.call("begin")
	screen.call("paint")
	var party_s: Node = screen.call("_party")
	var lobby: String = str((screen.get("party_line") as Label).text)
	var seat_said: Array = []
	for card in screen.get("_seat_cards"):
		seat_said.append("%s: %s" % [(card as Node).find_child("who", true, false).text, (card as Node).find_child("said", true, false).text])
	check("  the screen with the party here: Start is Ready, pressed it is Not ready; the seats along the wall (%s), what it waits for and her side"
		% ", ".join(seat_said),
		ready_word and bool(party_s.get("said_ready")) and str((screen.get("start_button") as Button).text).begins_with("Not ready")
		and lobby == "Waiting for bob to arrive." and str((screen.get("side_line") as Label).text) == "You hold the left of the gate."
		and seat_said == ["Open: for the party", "You: READY", "bob: on the way...", "Open: for the party"]
		and str((screen.get("party_count") as Label).text) == "1 of 2 ready" and (load("res://src/ui/minigames/startpanel.gd") as GDScript).call("names_said", ["a", "b", "c"]) == "a, b and c",
		[ready_word, lobby, seat_said])
	screen.call("close")

	for n in [run_a, run_b, made_c[0], alone, picture_a, picture_b, la, lb, lc, lx]:
		(n as Node).queue_free()
	await get_tree().process_frame
	print("  the stand together: done")


# =============================================================================
# READY FIRST (0.161.0)
# =============================================================================
# The owner, of the Stand's new start panel: "lets fix the other minigames
# with the same idea" - "we need healers run tanks and warriors and arena" -
# and for the three that start in the world, the full Ready panel: "the door
# or anvil opens only once all are ready".
func _test_ready_first() -> void:
	section("READY FIRST (0.161.0): the Endless, the Forge and the Descent ask Ready - the door shut and the anvil cold until everyone says it")
	const Panel := preload("res://src/ui/minigames/readypanel.gd")
	const EndlessRun := preload("res://src/world/endless/endlessrun.gd")
	const EndlessParty := preload("res://src/world/endless/endlessparty.gd")
	# ---- the panel on its own ----
	var away := Node.new()
	away.set_script(_ready_party_stand_in(false))
	var near := Node.new()
	near.set_script(_ready_party_stand_in(true))
	add_child(away)
	add_child(near)
	var heard: Dictionary = {2: 1, 3: -1}
	var who := GDScript.new()
	who.source_code = "extends Node\nvar bodies: Dictionary = {}\nfunc remotes() -> Dictionary:\n\treturn bodies\n"
	who.reload()
	var link: Node = who.new()
	add_child(link)
	var pic := GDScript.new()
	pic.source_code = "extends Node2D\nvar display_name: String = \"\"\n"
	pic.reload()
	var bob := Node2D.new()
	bob.set_script(pic)
	bob.set("display_name", "bob")
	var cat := Node2D.new()
	cat.set_script(pic)
	cat.set("display_name", "cat")
	add_child(bob)
	add_child(cat)
	link.set("bodies", {2: bob, 3: cat})
	var panel: CanvasLayer = Panel.new()
	panel.set("title", "Test")
	panel.set("keys", ["One"])
	panel.set("lines", ["A line."])
	panel.set("party", away)
	panel.set("link", link)
	panel.set("ready_of", func(id: int) -> int: return int(heard.get(id, -1)))
	panel.set("own_name", func() -> String: return "ann")
	var went: Array = []
	panel.connect("go_pressed", func() -> void: went.append(1))
	add_child(panel)
	panel.call("paint")
	var alone_word: String = str((panel.get("start_button") as Button).text)
	var alone_party: bool = (panel.get("party_box") as Control).visible
	panel.call("press")
	check("the panel alone: Start, no party part; pressed, it goes (and says Ready for anybody who comes)",
		alone_word.begins_with("Start") and not alone_party and went.size() == 1 and bool(panel.get("said_ready")),
		[alone_word, alone_party, went])
	panel.set("said_ready", false)
	panel.set("party", near)
	panel.call("paint")
	var ready_word: String = str((panel.get("start_button") as Button).text)
	panel.call("press")
	panel.call("paint")
	var waits_for_cat: String = str((panel.get("party_line") as Label).text)
	var held: bool = not bool(panel.call("all_ready"))
	heard[3] = 0
	panel.call("paint")
	var waits_ready: String = str((panel.get("party_line") as Label).text)
	heard[3] = 1
	check("  with the party: Ready, then what it waits for (\"%s\", \"%s\"); all ready only when everyone here has said it"
		% [waits_for_cat, waits_ready],
		ready_word.begins_with("Ready") and waits_for_cat == "Waiting for cat to arrive."
		and waits_ready == "Waiting for cat to press Ready." and held and bool(panel.call("all_ready"))
		and str((panel.get("party_count") as Label).text) == "2 of 3 ready" and went.size() == 1,
		[ready_word, waits_for_cat, waits_ready, held])
	panel.queue_free()
	# ---- a game from before says no Ready: it holds nobody up ----
	var holder := Node.new()
	var old_party: Node = EndlessParty.new()
	old_party.set("run", holder)
	old_party.call("_on_run", 9, {"me": [0, 0, 0, 0]})
	var said_new: Node = EndlessParty.new()
	said_new.set("run", holder)
	said_new.call("_on_run", 9, {"me": [0, 0, 0, 0, 0]})
	check("  a game from before 0.161.0 (four numbers in its line) counts as ready; one that says 0 is not; one unheard is -1",
		int(old_party.call("ready_of", 9)) == 1 and int(said_new.call("ready_of", 9)) == 0 and int(said_new.call("ready_of", 4)) == -1)
	old_party.free()
	said_new.free()
	holder.free()

	# ---- THE ENDLESS: two games, the door shut until both say Ready ----
	var Link: GDScript = _party_link_script()
	var la: Node = Link.new()
	var lb: Node = Link.new()
	add_child(la)
	add_child(lb)
	la.set("me", 1)
	lb.set("me", 2)
	la.set("peers", [lb])
	lb.set("peers", [la])
	var body_a := Node2D.new()
	var body_b := Node2D.new()
	add_child(body_a)
	add_child(body_b)
	la.set("bodies", {2: body_b})
	lb.set("bodies", {1: body_a})
	var at_door := Vector2(768, 1000)
	var games: Array = [_party_game(EndlessRun, la, at_door, true), _party_game(EndlessRun, lb, Vector2(768, 1200), true)]
	var run_a: Node = games[0][1]
	var run_b: Node = games[1][1]
	await get_tree().process_frame
	_party_frames(games, 0.4)
	var door_a: Node = (games[0][0] as Node).get_node("ysortworld/props/rundoor")
	var shut: bool = bool(door_a.get("locked")) and bool((run_a.get("ready_panel") as CanvasLayer).visible) \
		and int(run_a.get("state")) == EndlessRun.State.WAITING and int(run_b.get("state")) == EndlessRun.State.WAITING
	(games[0][3] as Node2D).global_position = Vector2(768, 1200)
	(run_a.get("ready_panel") as Node).call("press")
	_party_frames(games, 0.6)
	var one_ready: bool = int((run_b.get("party") as Node).call("ready_of", 1)) == 1 and not bool(run_a.get("gate_open"))
	(run_b.get("ready_panel") as Node).call("press")
	_party_frames(games, 0.6)
	var opened: bool = bool(run_a.get("gate_open")) and bool(run_b.get("gate_open")) and not bool(door_a.get("locked")) \
		and not bool((run_a.get("ready_panel") as CanvasLayer).visible) and int(run_a.get("state")) == EndlessRun.State.WAITING
	(games[0][3] as Node2D).global_position = at_door
	_party_frames(games, 0.3)
	check("the Endless: the panel up and the door shut while it waits - a player in the doorway starts nothing; one Ready is not enough; both, and the door opens on both, and stepping through starts the count",
		shut and one_ready and opened and int(run_a.get("state")) == EndlessRun.State.COUNTDOWN
		and int(run_b.get("state")) == EndlessRun.State.COUNTDOWN, [shut, one_ready, opened, run_a.get("state"), run_b.get("state")])
	run_a.set("state", EndlessRun.State.OVER)
	run_a.call("_clear_arena")
	_party_frames([games[0]], 0.1)
	check("  back in the corridor after a run, it asks again", not bool(run_a.get("gate_open"))
		and bool((run_a.get("ready_panel") as CanvasLayer).visible) and not bool((run_a.get("ready_panel") as Node).get("said_ready"))
		and bool(door_a.get("locked")))
	for g in games:
		(g[0] as Node).queue_free()

	# ---- THE FORGE: the anvil cold until Start ----
	const ForgeRun := preload("res://src/world/forge/forgerun.gd")
	var forge_body := GDScript.new()
	forge_body.source_code = _forge_body_script().source_code + "var down_in_run: bool = false\n"
	forge_body.reload()
	var made: Array = _forge_island_for_test(forge_body, "tank", true)
	var forge_asks: Node = made[1]
	(made[2] as Node2D).global_position = ForgeRun.CENTRE
	await get_tree().process_frame
	forge_asks.call("_timed_process", ForgeRun.START_HOLD + 0.2)
	var cold: bool = int(forge_asks.get("state")) == ForgeRun.State.WAITING and bool((forge_asks.get("ready_panel") as CanvasLayer).visible)
	(forge_asks.get("ready_panel") as Node).call("press")
	forge_asks.call("_timed_process", ForgeRun.START_HOLD + 0.2)
	check("the Forge: standing at the anvil lights nothing while the panel is up; Start, and it lights - and its line says Ready",
		cold and int(forge_asks.get("state")) == ForgeRun.State.COUNTDOWN and int((forge_asks.call("my_line") as Array)[3]) == 1
		and int((forge_asks.call("my_line") as Array).size()) == 4, [cold, forge_asks.get("state")])
	(made[0] as Node).queue_free()

	# ---- THE DESCENT: both doors shut until Start ----
	const DescentRun := preload("res://src/world/descent/descentrun.gd")
	var room_made: Array = _descent_room_for_test(_endless_body_script(), true)
	var room: Node2D = room_made[0]
	var descent: Node = room_made[1]
	await get_tree().process_frame
	descent.call("_timed_process", 0.05)
	var doors: Array = descent.get("doors")
	var both_shut: bool = doors.size() == 2 and not bool(descent.call("_doors_open"))
	(doors[0] as Node).emit_signal("walked_in", doors[0])
	var still: bool = int(descent.get("state")) == DescentRun.State.WAITING
	(descent.get("ready_panel") as Node).call("press")
	descent.call("_timed_process", 0.05)
	var both_open: bool = bool(descent.call("_doors_open"))
	(doors[0] as Node).emit_signal("walked_in", doors[0])
	check("the Descent: both doors shut while the panel is up, walking at one starts nothing; Start, and they open, and a door begins the run - its line says Ready",
		both_shut and still and both_open and int(descent.get("state")) != DescentRun.State.WAITING
		and (descent.call("my_line") as Array).size() == 5, [both_shut, still, both_open, descent.get("state")])
	room.queue_free()
	for n in [away, near, link, bob, cat, la, lb, body_a, body_b]:
		(n as Node).queue_free()
	await get_tree().process_frame
	print("  ready first: done")


func _ready_party_stand_in(here: bool) -> GDScript:
	var script := GDScript.new()
	script.source_code = "extends Node\nfunc active() -> bool:\n\treturn %s\n" % ("true" if here else "false")
	script.reload()
	return script


# =============================================================================
# CUT THE CLOTH TOGETHER (0.161.0)
# =============================================================================
# The owner: "i was thinking of making cut the cloth 4 player and if players
# lines crash into each other they also die" - "only the player that crashed
# into it". Two games' cloths in one tree, each on a stand-in link that
# passes "en" as the server does (JSON and back): the same cloth from the
# leader's seed; each cut on the other's cloth; a crash costing the crasher
# alone; a piece kept while another's cut runs through it, then cut away; a
# pickup given through the leader; the slimes where the leader has them; a
# round cleared and the next from its seed; out, and the run over when both
# are. The server's half is the API's test_presence.py P-30.
func _cloth_party_link_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = _party_link_script().source_code + "\nfunc cloth_rooms() -> bool:\n\treturn open\n"
	script.reload()
	return script


func _cloth_for_test(Run: GDScript, PartyScript: GDScript, link: Node, seed_value: int) -> Array:
	"""[run, party]: a cloth with its party on `link`, driven by hand."""
	var run: Node2D = Run.new()
	run.set("seed_value", seed_value)
	var party: Node = PartyScript.new()
	party.set("link", link)
	party.set("run", run)
	run.set("party", party)
	run.add_child(party)
	add_child(run)
	run.set_physics_process(false)
	party.set_process(false)
	party.start_now.connect(Callable(run, "begin_party"))
	return [run, party]


func _cloth_cut(run: Node, cells: Array) -> void:
	"""Steps the shot through `cells`, one at a time, as its frames would."""
	for c in cells:
		run.call("_step_to", c)


func _test_the_cloth_together() -> void:
	section("CUT THE CLOTH TOGETHER (0.161.0): one cloth for up to four - every cut on every screen, a crash the crasher's alone")
	const Run := preload("res://src/world/cloth/clothrun.gd")
	const PartyScript := preload("res://src/world/cloth/clothparty.gd")
	const Screen := preload("res://src/world/cloth/clothscreen.gd")
	var picture_script := GDScript.new()
	picture_script.source_code = "extends Node2D\nvar display_name: String = \"\"\n"
	picture_script.reload()
	var picture_a := Node2D.new()
	picture_a.set_script(picture_script)
	picture_a.set("display_name", "ann")
	var picture_b := Node2D.new()
	picture_b.set_script(picture_script)
	picture_b.set("display_name", "bob")
	add_child(picture_a)
	add_child(picture_b)
	var Link: GDScript = _cloth_party_link_script()
	var la: Node = Link.new()
	var lb: Node = Link.new()
	add_child(la)
	add_child(lb)
	la.set("me", 1)
	lb.set("me", 2)
	la.set("peers", [lb])
	lb.set("peers", [la])
	la.set("bodies", {2: picture_b})
	lb.set("bodies", {1: picture_a})
	# Different seeds: what makes the cloths alike is the leader's round.
	var made_a: Array = _cloth_for_test(Run, PartyScript, la, 31)
	var made_b: Array = _cloth_for_test(Run, PartyScript, lb, 7777)
	var run_a: Node2D = made_a[0]
	var run_b: Node2D = made_b[0]
	var party_a: Node = made_a[1]
	var party_b: Node = made_b[1]
	await get_tree().process_frame
	var says: bool = _code_src("res://src/systems/presence.gd").contains("message.get(\"cc\", 0)") \
		and _code_src("res://src/world/cloth/clothscreen.gd").contains("Presence.cloth_rooms() and Party.members.size() > 1")

	# ---- Ready, the countdown, one cloth from the leader's seed ----
	party_a.call("_timed_process", 0.05)
	party_a.call("flush")
	party_b.call("_timed_process", 0.05)
	party_b.call("set_ready", true)
	party_b.call("flush")
	party_a.call("set_ready", true)
	party_a.call("_timed_process", 0.05)
	party_a.call("flush")
	var counting: bool = float(party_a.get("counting")) > 0.0 and float(party_b.get("counting")) > 0.0
	for i in 70:
		party_a.call("_timed_process", 0.05)
		party_b.call("_timed_process", 0.05)
	var foes_alike: bool = (run_a.get("foes") as Array).size() == (run_b.get("foes") as Array).size()
	for k in (run_a.get("foes") as Array).size() if foes_alike else 0:
		var fa: Dictionary = (run_a.get("foes") as Array)[k]
		var fb: Dictionary = (run_b.get("foes") as Array)[k]
		foes_alike = foes_alike and int(fa["id"]) == int(fb["id"]) and (fa["p"] as Vector2).distance_to(fb["p"]) < 0.5 \
			and str(fa["kind"]) == str(fb["kind"])
	var saws_alike: bool = str((run_a.get("saws") as Array).map(func(s: Dictionary) -> Vector2i: return s["c"])) \
		== str((run_b.get("saws") as Array).map(func(s: Dictionary) -> Vector2i: return s["c"]))
	var spot: Dictionary = run_b.call("presence_state")
	check("the cloth is shared with a server that seats it a room per party ('cc'); its steps are its shot's; everyone Ready, a count of three, then one cloth on both screens from the leader's seed - its slimes, its saws - each on a side of its own",
		says and str(spot.get("a", "")) == "cloth" and (spot["at"] as Vector2).is_equal_approx(run_b.get("cutter_px"))
		and counting and bool(run_a.call("party_on")) and not bool(run_a.call("following")) and bool(run_b.call("following"))
		and not bool(run_b.get("awaiting_round")) and int(run_a.get("players")) == 2 and int(run_b.get("players")) == 2
		and run_a.get("grid") == run_b.get("grid") and foes_alike and saws_alike and int(run_a.get("seat")) == 0
		and int(run_b.get("seat")) == 1 and (run_a.get("cutter") as Vector2i).y > 70 and (run_b.get("cutter") as Vector2i).y < 10,
		[says, spot, counting, run_b.get("awaiting_round"), foes_alike, saws_alike, run_a.get("cutter"), run_b.get("cutter"),
		run_a.get("grid") == run_b.get("grid"), run_a.get("players"), run_b.get("players"), run_a.get("seat"), run_b.get("seat")])

	# ---- bob's cut on ann's cloth; ann runs into it ----
	var grid_a: PackedByteArray
	var corner: Array = []
	for x in range(2, 11):
		corner.append(Vector2i(x, 10))
	for y in range(9, 1, -1):
		corner.append(Vector2i(10, y))
	run_b.set("cutter", Vector2i(1, 10))
	_cloth_cut(run_b, corner)
	party_b.call("flush")
	grid_a = run_a.get("grid")
	var marked: bool = int(grid_a[10 * Run.COLS + 5]) == Run.OTHER and int(grid_a[5 * Run.COLS + 10]) == Run.OTHER \
		and ((run_a.get("others_lines") as Dictionary).get(2, []) as Array).size() == corner.size()
	run_a.set("cutter", Vector2i(5, 1))
	var down: Array = []
	for y in range(2, 11):
		down.append(Vector2i(5, y))
	_cloth_cut(run_a, down)
	grid_a = run_a.get("grid")
	var crashed: bool = int(run_a.get("lives")) == Run.LIVES - 1 and int(run_b.get("lives")) == Run.LIVES \
		and not bool(run_a.get("cutting")) and int(grid_a[10 * Run.COLS + 5]) == Run.OTHER and int(grid_a[5 * Run.COLS + 5]) == Run.OPEN
	party_a.call("flush")
	var grid_b: PackedByteArray = run_b.get("grid")
	var dropped: bool = int(grid_b[5 * Run.COLS + 5]) == Run.OPEN and not (run_b.get("others_lines") as Dictionary).has(1) \
		and bool(run_b.get("cutting")) and int(grid_b[10 * Run.COLS + 5]) == Run.LINE
	check("  a cut is on the other's cloth as it goes; running into it costs the crasher a life, its own cut gone on both screens - and the other's cut stands",
		marked and crashed and dropped, [marked, crashed, dropped, run_a.get("lives"), run_b.get("lives")])

	# ---- a piece kept while ann's cut runs through it, then cut away ----
	run_a.set("grace_left", 0.0)
	_cloth_cut(run_a, [Vector2i(5, 2), Vector2i(5, 3)])
	party_a.call("flush")
	_cloth_cut(run_b, [Vector2i(10, 1)])
	party_b.call("flush")
	party_a.call("flush")
	grid_a = run_a.get("grid")
	grid_b = run_b.get("grid")
	var kept: bool = int(grid_a[3 * Run.COLS + 3]) == Run.OPEN and int(grid_b[3 * Run.COLS + 3]) == Run.OPEN \
		and int(grid_a[10 * Run.COLS + 7]) == Run.OWN and int(grid_b[10 * Run.COLS + 7]) == Run.OWN \
		and not bool(run_b.get("cutting")) and bool(run_a.get("cutting"))
	var rest: Array = []
	for y in range(4, 11):
		rest.append(Vector2i(5, y))
	_cloth_cut(run_a, rest)
	party_a.call("flush")
	grid_a = run_a.get("grid")
	grid_b = run_b.get("grid")
	var cut_both: bool = int(grid_a[3 * Run.COLS + 3]) == Run.OWN and int(grid_a[8 * Run.COLS + 8]) == Run.OWN \
		and grid_a == grid_b and is_equal_approx(float(run_a.get("taken")), float(run_b.get("taken"))) \
		and not bool(run_a.get("cutting"))
	check("  bob's cut closes round a corner ann is cutting into: the piece is kept for her; her cut closes, and it is cut away - on both screens alike (%d%% cut)"
		% roundi(float(run_a.get("taken")) * 100.0), kept and cut_both, [kept, cut_both, run_a.get("taken"), run_b.get("taken")])

	# ---- a pickup through the leader ----
	var swift_id: int = int(run_a.get("_next_pickup"))
	(run_a.get("pickups") as Array).append({"kind": "swift", "c": Vector2i(60, 40), "left": 15.0, "id": swift_id})
	run_a.call("_announce", [PartyScript.EV_PICKUP, swift_id, Run.PICKUPS.find("swift"), 60, 40])
	run_a.set("_next_pickup", swift_id + 1)
	party_a.call("flush")
	var out_there: bool = (run_b.get("pickups") as Array).size() == 1
	run_b.call("_take_pickup_at", Vector2i(60, 40))
	party_b.call("flush")
	party_a.call("flush")
	var swift_b: bool = float(run_b.get("swift_left")) > 0.0 and float(run_a.get("swift_left")) <= 0.0 \
		and (run_a.get("pickups") as Array).is_empty() and (run_b.get("pickups") as Array).is_empty()
	var slow_id: int = int(run_a.get("_next_pickup"))
	(run_a.get("pickups") as Array).append({"kind": "slow", "c": Vector2i(80, 30), "left": 15.0, "id": slow_id})
	run_a.call("_announce", [PartyScript.EV_PICKUP, slow_id, Run.PICKUPS.find("slow"), 80, 30])
	party_a.call("flush")
	run_a.call("_take_pickup_at", Vector2i(80, 30))
	party_a.call("flush")
	var slow_both: bool = float(run_a.get("slow_left")) > 0.0 and float(run_b.get("slow_left")) > 0.0
	check("  a pickup the leader puts out is on both cloths; crossed by bob it is his - Swift his alone - and gone on both; Slow, ann's, slows the slimes on both",
		out_there and swift_b and slow_both, [out_there, swift_b, slow_both])

	# ---- the slimes where the leader has them ----
	var foe_a: Dictionary = (run_a.get("foes") as Array)[0]
	foe_a["p"] = (foe_a["p"] as Vector2) + Vector2(40, 0)
	var gone_a: Dictionary = (run_a.get("foes") as Array)[1]
	gone_a["dead"] = 0.0
	party_a.call("flush")
	var foe_b: Dictionary = (run_b.get("foes") as Array)[0]
	var gone_b: Dictionary = (run_b.get("foes") as Array)[1]
	check("  a slime moved on the leader's cloth is moved on bob's; one gone there dissolves on his",
		(foe_b["p"] as Vector2).distance_to(foe_a["p"]) < 0.5 and float(gone_b["dead"]) >= 0.0,
		[foe_a["p"], foe_b["p"], gone_b["dead"]])

	# ---- a round cleared, the next from the leader's seed; an old round's cut lands nowhere ----
	run_a.call("_clear_round")
	party_a.call("flush")
	var cleared: bool = int(run_b.get("state")) == Run.State.CLEARED and int(run_b.get("best")) == 1 and int(run_a.get("best")) == 1
	var old_stamp: int = int(party_b.call("stamp"))
	run_a.set("cleared_left", 0.0)
	run_a.call("_timed_physics_process", 0.01)
	party_a.call("flush")
	var next_alike: bool = int(run_a.get("round_now")) == 2 and int(run_b.get("round_now")) == 2 \
		and int(run_b.get("state")) == Run.State.PLAYING and run_a.get("grid") == run_b.get("grid") \
		and (run_a.get("saws") as Array).size() == (run_b.get("saws") as Array).size()
	party_b.set("_cuts", [[20, old_stamp * PartyScript.KIND_SPAN + PartyScript.ADD, 21]])
	party_b.call("flush")
	grid_a = run_a.get("grid")
	check("  the leader clears the round on both screens (each cleared it, still in); its next round comes from its seed, alike; a cut stamped with the old round lands nowhere",
		cleared and next_alike and int(grid_a[20 * Run.COLS + 20]) == Run.OPEN, [cleared, next_alike, run_b.get("round_now")])

	# ---- out, and the run over when everybody is ----
	for i in 3:
		run_a.set("grace_left", 0.0)
		run_a.call("lose_life")
	party_a.call("flush")
	var a_out: bool = bool(run_a.get("out")) and int(run_a.get("state")) == Run.State.PLAYING \
		and int(party_b.call("flags_of", 1)) & PartyScript.OUT != 0 and (run_b.call("others_shots") as Array).is_empty()
	run_a.call("_clear_round")
	party_a.call("flush")
	var best_held: bool = int(run_a.get("best")) == 1 and int(run_b.get("best")) == 2
	run_a.set("cleared_left", 0.0)
	run_a.call("_timed_physics_process", 0.01)
	party_a.call("flush")
	for i in 3:
		run_b.set("grace_left", 0.0)
		run_b.call("lose_life")
	party_b.call("flush")
	run_a.call("_timed_physics_process", 0.01)
	party_a.call("flush")
	check("  out of lives, ann watches: the run goes on for bob, and the rounds he clears are his alone; both out, the run is over on both screens",
		a_out and best_held and int(run_a.get("state")) == Run.State.OVER and int(run_b.get("state")) == Run.State.OVER,
		[a_out, best_held, run_a.get("state"), run_b.get("state"), run_a.get("best"), run_b.get("best")])

	# ---- a dropped link: alone for good; the others forget it ----
	lb.set("open", false)
	party_b.call("_timed_process", 0.05)
	lb.set("open", true)
	party_b.call("_timed_process", 0.05)
	la.set("bodies", {})
	party_a.call("_timed_process", 0.2)
	check("  bob's link drops mid-run: his game finishes the run alone and stays alone when it comes back; ann's game forgets him",
		int(party_b.get("key")) == PartyScript.ALONE and not bool(party_b.call("active")) and not bool(run_b.call("party_on"))
		and not bool(party_a.call("in_run", 2)) and (party_a.get("_members") as Dictionary).is_empty(),
		[party_b.get("key"), party_b.call("active"), party_a.call("in_run", 2), party_a.get("_members")])

	# ---- the start panel: four seats, Ready ----
	var lc: Node = Link.new()
	add_child(lc)
	lc.set("me", 5)
	lc.set("leader", 5)
	lc.set("bodies", {6: picture_b})
	var screen: CanvasLayer = Screen.new()
	screen.set("party_rooms", func() -> bool: return true)
	screen.set("party_link", lc)
	add_child(screen)
	await get_tree().process_frame
	screen.call("_word_for_touch")
	screen.call("paint")
	var how: Array = (screen.get("_how_to_lines") as Array).map(func(l: Label) -> String: return l.text)
	var lobby: bool = (screen.get("party_box") as Control).visible and (screen.get("_seat_cards") as Array).size() == 4 \
		and str((screen.get("start_button") as Button).text).begins_with("Ready") \
		and str(how[2]).contains("no open cut") and str(how[3]).contains("teammate's cut") and str(how[0]) == str(Screen.HOW_TO[0])
	screen.call("begin")
	screen.call("paint")
	var readied: bool = bool(((screen.get("run") as Node).get("party") as Node).get("said_ready")) \
		and str((screen.get("start_button") as Button).text).begins_with("Not ready") \
		and (screen.get("start_panel") as Control).visible
	check("  the start panel: the party as four seats, HOW TO PLAY telling of open cuts kept and the crash, and Start is Ready - then Not ready, the panel staying up for the count",
		lobby and readied, [lobby, readied, (screen.get("start_button") as Button).text, how])
	screen.queue_free()
	for n in [run_a, run_b, la, lb, lc, picture_a, picture_b]:
		(n as Node).queue_free()
	await get_tree().process_frame
	print("  the cloth together: done")


# CROWNFALL (0.162.0): a brick breaker through seven monster kingdoms - the
# maps as rows of letters (crownfallmaps.gd), the play (crownfallrun.gd), the
# screen (crownfallscreen.gd) and the Minigames card's tile, the owner's while
# it is built. The server's half is test_minigames.py MG-17.
func _test_crownfall_wind(run: Node2D, wind: Array) -> void:
	"""The Kingdom of Wind (0.163.0): gusts, whirls, kites, the kingdom map's
	crests, and its five bosses."""
	const Run := preload("res://src/world/crownfall/crownfallrun.gd")
	const Boss := preload("res://src/world/crownfall/crownfallboss.gd")
	# ---- gusts, whirls, kites ----
	_cf_bare(run)
	run.gusts = [{"y0": 300.0, "y1": 360.0, "way": 1.0}]
	var in_gust: Dictionary = run._ball(Vector2(640, 330), Vector2(0, -Run.SPEED))
	var under_gust: Dictionary = run._ball(Vector2(640, 420), Vector2(0, -Run.SPEED))
	run.balls = [in_gust, under_gust]
	run._gusts(0.1)
	var pushed: bool = (in_gust["v"] as Vector2).x > 20.0 and absf((in_gust["v"] as Vector2).length() - Run.SPEED) < 1.0 \
		and (under_gust["v"] as Vector2).x == 0.0
	var whirl: Dictionary = run._add(10, 6, "whirl", "wind", 0)
	var ways: Array = []
	for n in 6:
		var flung: Dictionary = run._ball((whirl["rect"] as Rect2).get_center() + Vector2(0, 30), Vector2(0, -Run.SPEED))
		for i in 12:
			run._move(flung, 1.0 / 60.0)
			if (flung["v"] as Vector2).y > -Run.SPEED + 1.0:
				break
		if absf((flung["v"] as Vector2).length() - Run.SPEED) < 1.0:
			ways.append((flung["v"] as Vector2).normalized())
	var spread: float = 0.0
	for a in ways:
		for b in ways:
			spread = maxf(spread, rad_to_deg(absf((a as Vector2).angle_to(b))))
	var whirled: bool = ways.size() == 6 and spread > 30.0 and run.cells.get(Vector2i(10, 6)) == whirl
	run.begin(int(wind[1]))
	var kite: Dictionary = {}
	for k in run.movers:
		if k.has("kite") and float(k["hi"]) - float(k["lo"]) > 0.0 and (kite.is_empty() or float(k["hi"]) - float(k["lo"]) > float(kite["hi"]) - float(kite["lo"])):
			kite = k
	var y_most: float = -INF
	var y_least: float = INF
	var x_was: float = (kite["rect"] as Rect2).position.x
	for i in 90:
		run.t += 1.0 / 30.0
		run._bricks_move(0.0)
		y_most = maxf(y_most, (kite["rect"] as Rect2).position.y)
		y_least = minf(y_least, (kite["rect"] as Rect2).position.y)
	var bobbed: bool = y_most - y_least > 8.0 and y_least >= float(kite["home"]) + float(kite["lo"]) - 0.01 \
		and y_most <= float(kite["home"]) + float(kite["hi"]) + 0.01 and (kite["rect"] as Rect2).position.x == x_was
	check("WIND: a gust pushes a ball in its band sideways, its speed kept, and no ball out of it; a whirl never breaks and throws the ball off its own way each time; a kite bobs up and down into the room beside it, no further",
		pushed and whirled and bobbed, [pushed, whirled, bobbed])
	# ---- the kingdom map's crests ----
	run.show_kingdoms(int(wind[5]))
	var crests: bool = run.kingdom_at(run.kingdom_spot(0)) == 0 and run.kingdom_at(run.kingdom_spot(1)) == 1 \
		and run.kingdom_at(run.kingdom_spot(6)) == 6 and run.kingdom_at(Vector2(4, 4)) == -1 and run.open_map_in(2) == -1 and run.open_map_in(3) == -1 \
		and run.open_map_in(0) == int(wind[0]) - 1 \
		and run.open_map_in(1) == int(wind[5]) and run.kingdom_index(int(wind[3])) == 1
	run.show_kingdoms(3)
	crests = crests and run.open_map_in(1) == -1 and run.open_map_in(0) == 3
	check("  the kingdom map: a click on a made kingdom's crest picks its next map to clear (its last once cleared); a kingdom not reached yet picks nothing",
		crests)
	# ---- the Gale King ----
	run.begin(int(wind[4]))
	var gale = run.boss
	run.state = Run.State.PLAY
	var knocked: Dictionary = run._ball(gale.p + Vector2(90, 160), Vector2(0, -Run.SPEED))
	var far_ball: Dictionary = run._ball(gale.p + Vector2(-50, Boss.GALE_REACH + 60.0), Vector2(0, -Run.SPEED))
	run.balls = [knocked, far_ball]
	gale.gale_t = 0.001
	gale.step(0.01, true)
	var gale_ok: bool = str(gale.kind) == "galeking" and gale.hp == run.boss_left() and (knocked["v"] as Vector2).x > 50.0 \
		and (far_ball["v"] as Vector2).x == 0.0 and gale.gales.size() == 1
	run._hit_boss(Boss.SPLIT_EVERY)
	gale_ok = gale_ok and gale.minions.size() == 1
	# ---- the Whirlwind ----
	run.begin(int(wind[9]))
	var whirlwind = run.boss
	run.state = Run.State.PLAY
	whirlwind.whirl_t = 0.001
	whirlwind.step(0.01, true)
	var spun: bool = whirlwind.vortices.size() == 1 and (whirlwind._field_box() as Rect2).grow(1.0).has_point(whirlwind.vortices[0]["p"])
	var caught: Dictionary = run._ball((whirlwind.vortices[0]["p"] as Vector2) + Vector2(10, 0), Vector2(0, -Run.SPEED))
	whirlwind.work_balls([caught], 0.01)
	spun = spun and caught.has("spin") and (caught["v"] as Vector2) == Vector2.ZERO
	for i in roundi(Boss.SPIN_SECONDS * 60.0) + 2:
		whirlwind.work_balls([caught], 1.0 / 60.0)
	spun = spun and not caught.has("spin") and absf((caught["v"] as Vector2).length() - Run.SPEED) < 1.0 and float(caught["free_t"]) > 0.0
	for i in roundi((Boss.WHIRL_LIFE + 0.2) * 10.0):
		whirlwind._step_winds(0.1, true)
	spun = spun and whirlwind.vortices.is_empty()
	# ---- the Gust Sniper ----
	run.begin(int(wind[14]))
	var fanner = run.boss
	fanner.fan_t = 0.001
	fanner._fan(0.01)
	var three: int = fanner.shots.size()
	fanner.shots.clear()
	@warning_ignore("integer_division")
	fanner.hp = fanner.most / 3
	fanner.fan_t = 0.001
	fanner._fan(0.01)
	var five: int = fanner.shots.size()
	# ---- the Storm Mage ----
	run.begin(int(wind[19]))
	var storm = run.boss
	storm.wall_t = 0.001
	storm._wall(0.01)
	var wall_up: bool = storm.wall_left > 0.0 and storm.wards.size() == Boss.WARDS
	var rising: Dictionary = run._ball((storm.wall_rect() as Rect2).get_center(), Vector2(0, -Run.SPEED))
	storm.work_balls([rising], 0.01)
	var blown_back: bool = (rising["v"] as Vector2).y > 0.0
	for i in roundi(Boss.WALL_ON * 10.0) + 2:
		storm._wall(0.1)
	var wall_down: bool = storm.wall_left <= 0.0
	# ---- the Tempest ----
	run.begin(int(wind[24]))
	var tempest = run.boss
	var storm_on: bool = tempest.crowned and str(tempest.title) == "The Tempest" and tempest.vortices.size() == 1 \
		and bool(tempest.vortices[0]["forever"])
	for i in roundi((Boss.WHIRL_LIFE + 1.0) * 10.0):
		tempest._step_winds(0.1, true)
	storm_on = storm_on and tempest.vortices.size() == 1
	@warning_ignore("integer_division")
	run._hit_boss(tempest.hp - tempest.most / 3 + 1)
	run.state = Run.State.PLAY
	tempest.step(0.01, true)
	storm_on = storm_on and tempest.vortices.size() == 2 and tempest.minions.size() > 0
	check("  WIND'S BOSSES: the Gale King's stamp knocks near balls aside and he splits; the Whirlwind's vortex catches a ball, spins it and throws it on, then fades; the Gust Sniper fires a fan of %d (%d hurt); the Storm Mage's wall blows a rising ball back down, then drops; the Tempest's tornado never fades, and a second comes under a third of his health" % [three, five],
		gale_ok and spun and three == 3 and five == 5 and wall_up and blown_back and wall_down and storm_on,
		[gale_ok, spun, three, five, wall_up, blown_back, wall_down, storm_on])
	print("  crownfall wind: done")


func _test_crownfall_water(run: Node2D, water: Array) -> void:
	"""The Kingdom of Water (0.164.0): the tide, buoys, bubbles, clams, the
	way on from the Tempest, and its five bosses."""
	const Run := preload("res://src/world/crownfall/crownfallrun.gd")
	const Boss := preload("res://src/world/crownfall/crownfallboss.gd")
	const Maps := preload("res://src/world/crownfall/crownfallmaps.gd")
	# ---- the tide ----
	_cf_bare(run)
	run.tide_mark = 10
	for c in 16:
		run.footprint[Vector2i(c, 12)] = true
		run.placed[Vector2i(c, 12)] = "land"
		run.gone_at[Vector2i(c, 12)] = -45.0 + c
	for spot in [[Vector2i(20, 11), "guard"], [Vector2i(21, 11), "key"], [Vector2i(22, 11), "heart"], [Vector2i(23, 11), "land"],
			[Vector2i(24, 9), "land"]]:
		run.footprint[spot[0]] = true
		run.placed[spot[0]] = spot[1]
		run.gone_at[spot[0]] = -60.0
	run.gone_at[Vector2i(23, 11)] = -5.0
	run.balls = [run._ball(run._cell(0, 12).get_center(), Vector2(0, -Run.SPEED))]
	var made: int = run.tide_rebuild()
	var back: Array = []
	for c in 16:
		if run.cells.has(Vector2i(c, 12)):
			back.append(c)
	# the ball over cell 0 keeps it and its neighbour clear (_ball_near's reach)
	var rebuilt: Variant = run.cells.get(Vector2i(2, 12))
	var tide_ok: bool = made == Run.TIDE_MOST and back == range(2, 2 + Run.TIDE_MOST) and rebuilt != null \
		and str(rebuilt["land"]) == "water" and int(rebuilt["hp"]) == 1 and rebuilt.has("tide") and run.breakable == Run.TIDE_MOST \
		and not run.cells.has(Vector2i(20, 11)) and not run.cells.has(Vector2i(21, 11)) and not run.cells.has(Vector2i(22, 11)) \
		and not run.cells.has(Vector2i(23, 11)) and not run.cells.has(Vector2i(24, 9))
	# a second tide takes the two old cells left, never the fresh one
	var made_again: int = run.tide_rebuild()
	tide_ok = tide_ok and made_again == 2 and run.cells.has(Vector2i(15, 12)) and not run.cells.has(Vector2i(23, 11))
	var low: float = Run.TIDE_EVERY - 2.0 * Run.TIDE_RISE - Run.TIDE_HIGH
	run.tide_t = 0.0
	var level_low: float = run.tide_level()
	run.tide_t = low + Run.TIDE_RISE + 0.1
	var level_high: float = run.tide_level()
	run.tide_t = 0.0
	run.tide_now()
	run.words.clear()
	run._tide(0.1)
	var came_in: bool = run.words.any(func(w: Dictionary) -> bool: return str(w["text"]) == "THE TIDE COMES IN")
	tide_ok = tide_ok and level_low == 0.0 and level_high == 1.0 and came_in
	check("WATER'S TIDE: as it stands it brings back the cells under its mark broken over %ds ago as one-hit water bricks - the oldest first, %d at most, none by a ball, none a core's, a Guard's or a key's, none over the mark; it comes in when called" % [int(Run.TIDE_WAIT), Run.TIDE_MOST],
		tide_ok, [made, back, level_low, level_high, came_in])
	# ---- buoys, bubbles, clams ----
	_cf_bare(run)
	for r in [6, 7, 8]:
		run.footprint[Vector2i(5, r)] = true
	var buoy: Dictionary = run._add(5, 8, "buoy", "water", 1)
	run.buoys.append(buoy)
	for i in 60:
		run._waters(1.0 / 60.0)
	var floated: bool = buoy["cell"] == Vector2i(5, 6) and run.cells.get(Vector2i(5, 6)) == buoy and not run.cells.has(Vector2i(5, 8)) \
		and (buoy["rect"] as Rect2).is_equal_approx(run._cell(5, 6)) and not buoy.has("rise")
	_cf_bare(run)
	var bubble: Dictionary = run._add(7, 10, "bubble", "water", 1)
	var near: Dictionary = run._add(7, 6, "land", "light", 1)
	var far: Dictionary = run._add(7, 4, "land", "light", 1)
	run._damage(bubble, 1, null)
	var rose: bool = run.bubbles.size() == 1
	for i in 60:
		run._waters(1.0 / 60.0)
	rose = rose and int(near["hp"]) == 0 and int(far["hp"]) == 1 and run.bubbles.is_empty()
	_cf_bare(run)
	var clam: Dictionary = run._add(9, 9, "clam", "water", 1)
	clam["phase"] = 0.0
	run.t = Run.CLAM_OPEN + 0.5
	run._damage(clam, 1, null)
	var shut_held: bool = int(clam["hp"]) == 1 and run.caps.is_empty()
	run.t = Run.CLAM_OPEN / 2.0
	run._damage(clam, 1, null)
	var pearl: bool = int(clam["hp"]) == 0 and run.caps.size() == 1
	check("  a buoy floats up into the holes above it, cell by cell, while the map held them; a bubble rises up its column and breaks the first brick it meets, no more; a clam shut takes no harm, open breaks at a hit and its pearl drops a bonus",
		floated and rose and shut_held and pearl, [floated, rose, shut_held, pearl])
	# ---- on from the Tempest ----
	run.begin(int(water[0]) - 1)
	run._hit_boss(run.boss.hp)
	run.step(1.0 / 60.0)
	for i in roundi(Run.CLEARED_SECONDS * 60.0) + 2:
		run.step(1.0 / 60.0)
	var on_to_water: bool = run.state == Run.State.AIM and run.map_index == int(water[0]) and str(Maps.kingdom_of(run.map_index)["id"]) == "water" \
		and run.tide_mark >= 0
	# ---- the Tide King ----
	run.begin(int(water[4]))
	var king = run.boss
	run.state = Run.State.PLAY
	var king_ok: bool = str(king.kind) == "tideking" and king.hp == run.boss_left()
	run._hit_boss(Boss.SPLIT_EVERY)
	king_ok = king_ok and king.minions.size() == 1
	var before_young: int = run.breakable
	for i in 60 * 30:
		king._step_minions(1.0 / 60.0, true)
		if king.minions.is_empty():
			break
	king_ok = king_ok and king.minions.is_empty() and run.breakable == before_young + 1
	run.tide_t = 0.0
	king.call_t = 0.001
	king.step(0.01, true)
	king_ok = king_ok and run.tide_t > Run.TIDE_EVERY - 2.0 * Run.TIDE_RISE - Run.TIDE_HIGH - 0.2
	# ---- the Undine ----
	run.begin(int(water[9]))
	var undine = run.boss
	run.state = Run.State.PLAY
	undine.dive_t = 0.001
	undine.step(0.01, true)
	var under: bool = undine.dive_left > 0.0 and not undine.hittable()
	var at_it: Dictionary = run._ball(undine.p, Vector2(0, -Run.SPEED))
	run.balls = [at_it]
	run._move(at_it, 1.0 / 60.0)
	under = under and undine.hp == undine.most
	undine.dest = undine.p
	undine.dive_left = 0.01
	var splashed: Dictionary = run._ball(undine.p + Vector2(0, 120), Vector2(0, -Run.SPEED))
	var dry: Dictionary = run._ball(undine.p + Vector2(0, Boss.SPLASH_REACH + 40.0), Vector2(0, -Run.SPEED))
	run.balls = [splashed, dry]
	undine.step(0.02, true)
	var splash_ok: bool = under and undine.dive_left == 0.0 and undine.hittable() and (splashed["v"] as Vector2).y > 0.0 \
		and (dry["v"] as Vector2) == Vector2(0, -Run.SPEED) and undine.splashes.size() == 1
	# ---- the Harpooner ----
	run.begin(int(water[14]))
	var harp = run.boss
	run.state = Run.State.PLAY
	run.paddle_x = 500.0
	run.target_x = 500.0
	harp.harpoon_t = 0.001
	harp._harpoon(0.01)
	var aimed: bool = harp.harpoon_aim > 0.0 and absf(harp.harpoon_to.x - 500.0) < 0.1
	for i in 120:
		harp._harpoon(1.0 / 60.0)
		if harp.rope_left > 0.0:
			break
	var hooked: bool = aimed and run.tugged > 0.0 and harp.rope_left > 0.0
	var mid: Vector2 = harp.harpoon_from.lerp(harp.harpoon_to, 0.5)
	var n: Vector2 = (harp.harpoon_to - harp.harpoon_from).orthogonal().normalized()
	var crossing: Dictionary = run._ball(mid - n * 5.0, n * Run.SPEED)
	harp.work_balls([crossing], 0.01)
	var roped: bool = (crossing["v"] as Vector2).dot(n) < 0.0
	run.tugged = 0.0
	harp.rope_left = 0.0
	harp.harpoon_t = 0.001
	harp._harpoon(0.01)
	run.paddle_x = 900.0
	for i in 120:
		harp._harpoon(1.0 / 60.0)
		if harp.rope_left > 0.0:
			break
	var missed: bool = run.tugged == 0.0 and harp.rope_left > 0.0
	# ---- the Tide Mage ----
	run.begin(int(water[19]))
	var tm = run.boss
	run.state = Run.State.PLAY
	var shielded: bool = tm.bubble_hits == Boss.BUBBLE_HITS and not tm.hittable()
	for i in Boss.BUBBLE_HITS:
		tm.ward_touch(tm.p + Vector2(Boss.BUBBLE_R, 0), 6.0)
	var popped: bool = tm.bubble_hits == 0 and tm.hittable() and tm.ward_touch(tm.p + Vector2(Boss.BUBBLE_R, 0), 6.0) == Vector2.INF
	tm._bubble_step(Boss.BUBBLE_DOWN + 0.1)
	var formed: bool = tm.bubble_hits == Boss.BUBBLE_HITS
	var gone: int = 0
	for k in run.bricks:
		if gone < Boss.REBUILD_COUNT and k.has("cell") and int(k["hp"]) > 0 and run._breaks(k) and not run._guarded(k) \
				and str(k["kind"]) == "land" and (k["rect"] as Rect2).position.y > tm.hall.end.y:
			run._damage(k, 99, null)
			gone += 1
	var bubbles_before: int = run.bricks.filter(func(k: Dictionary) -> bool: return str(k["kind"]) == "bubble" and int(k["hp"]) > 0).size()
	tm.rebuild_t = 0.001
	tm._bubble_step(0.01)
	var bubbles_after: int = run.bricks.filter(func(k: Dictionary) -> bool: return str(k["kind"]) == "bubble" and int(k["hp"]) > 0).size()
	var mage_ok: bool = shielded and popped and formed and bubbles_after == bubbles_before + Boss.REBUILD_COUNT
	# ---- the Leviathan ----
	run.begin(int(water[24]))
	var lev = run.boss
	run.state = Run.State.PLAY
	var lev_ok: bool = lev.crowned and str(lev.title) == "The Leviathan" and lev.hp == run.boss_left()
	for k in run.bricks:
		if k.has("cell") and int(k["hp"]) > 0 and run._breaks(k) and not run._guarded(k) and (k["rect"] as Rect2).position.y > lev.hall.end.y + 60.0:
			run._damage(k, 99, null)
	var before_wave: int = run.breakable
	lev.wave_t = 0.001
	lev._wave(0.01)
	var warned: bool = lev.wave != null and float(lev.wave["warn"]) > 0.0 and lev.wave_band().size == Vector2.ZERO
	lev._wave(Boss.WAVE_WARN + 0.01)
	lev._wave(0.3)
	var band: Rect2 = lev.wave_band()
	var swept: Dictionary = run._ball(band.get_center(), Vector2(0, -Run.SPEED))
	var way: float = float(lev.wave["way"])
	lev.work_balls([swept], 0.01)
	var carried: bool = signf((swept["v"] as Vector2).x) == way and absf((swept["v"] as Vector2).length() - Run.SPEED) < 1.0
	for i in 400:
		if lev.wave == null:
			break
		lev._wave(1.0 / 60.0)
	var wake: int = run.breakable - before_wave
	lev_ok = lev_ok and warned and carried and lev.wave == null and wake > 0 and wake <= Boss.WAVE_BRICKS
	# (the bricks broken for his wave took their share: under half already,
	# a hit still splits him)
	@warning_ignore("integer_division")
	run._hit_boss(maxi(Boss.RULER_SPLIT_EVERY, lev.hp - lev.most / 2 + 1))
	lev.step(0.01, true)
	lev_ok = lev_ok and lev.dived and lev.dive_left > 0.0 and not lev.hittable() and lev.minions.size() > 0
	lev.dive_left = 0.0
	run._hit_boss(lev.hp)
	run.step(1.0 / 60.0)
	for i in roundi(Run.CLEARED_SECONDS * 60.0) + 2:
		run.step(1.0 / 60.0)
	lev_ok = lev_ok and run.state == Run.State.AIM and str(Maps.kingdom_of(run.map_index)["id"]) == "ice"
	check("  WATER'S BOSSES: the Tempest's fall leads on into the Kingdom of Water; the Tide King's young turn to water where they land and he calls the tide; the Undine under the water cannot be hit and comes up in a splash that throws near balls away; the Harpooner marks the paddle, hooks it and his rope turns the ball (missing when it moved); the Tide Mage's bubble takes %d hits, forms again, and he raises bubble bricks; the Leviathan's wave warns, carries a ball its way and leaves at most %d bricks, he dives at half health, and his fall leads on into Ice" % [Boss.BUBBLE_HITS, Boss.WAVE_BRICKS],
		on_to_water and king_ok and splash_ok and hooked and roped and missed and mage_ok and lev_ok,
		[on_to_water, king_ok, splash_ok, hooked, roped, missed, mage_ok, lev_ok, wake])
	print("  crownfall water: done")


func _test_crownfall_ice(run: Node2D, ice: Array) -> void:
	"""The Kingdom of Ice (0.165.0): frost, packed ice, snowdrifts, icicles,
	slick ice, the frost rows, and its five bosses."""
	const Run := preload("res://src/world/crownfall/crownfallrun.gd")
	const Boss := preload("res://src/world/crownfall/crownfallboss.gd")
	const Maps := preload("res://src/world/crownfall/crownfallmaps.gd")
	# ---- frost, packed ice, snowdrifts ----
	_cf_bare(run)
	var coated: Dictionary = run._add(5, 5, "land", "ice", 1)
	coated["frost"] = true
	run._damage(coated, 1, null)
	var coat_first: bool = not coated.has("frost") and int(coated["hp"]) == 1
	run._damage(coated, 1, null)
	coat_first = coat_first and int(coated["hp"]) == 0
	var burnt: Dictionary = run._add(6, 5, "land", "ice", 1)
	burnt["frost"] = true
	run._damage(burnt, 99, null)
	var fire_through: bool = int(burnt["hp"]) == 0
	var packed: Dictionary = run._add(8, 5, "packed", "ice", 3)
	run._damage(packed, 1, null)
	run._damage(packed, 1, null)
	var three: bool = int(packed["hp"]) == 1
	run._damage(packed, 1, null)
	three = three and int(packed["hp"]) == 0
	var drift: Dictionary = run._add(10, 6, "drift", "ice", 2)
	var into: Dictionary = run._ball(run._cell(10, 6).get_center() + Vector2(0, 26), Vector2(0, -Run.SPEED))
	run.balls = [into]
	for i in 12:
		run._move(into, 1.0 / 60.0)
	var soaked: bool = int(drift["hp"]) == 1 and (into["v"] as Vector2).length() < Run.SPEED * 0.6
	# ---- icicles ----
	_cf_bare(run)
	var holder: Dictionary = run._add(12, 3, "land", "light", 1)
	var icicle: Dictionary = run._add(12, 4, "icicle", "ice", 1)
	var below: Dictionary = run._add(12, 9, "stone", "", 3)
	run._damage(holder, 1, null)
	var fell: bool = int(icicle["hp"]) == 0 and run.falling.size() == 1
	for i in 60:
		run._icicles(1.0 / 60.0)
	fell = fell and int(below["hp"]) == 3 - Run.ICICLE_HIT and run.falling.is_empty()
	_cf_bare(run)
	run.paddle_x = Run.FIELD_X + 20.5 * run.cw
	var high: Dictionary = run._add(20, 2, "land", "light", 1)
	run._add(20, 3, "icicle", "ice", 1)
	run._damage(high, 1, null)
	for i in 120:
		run._icicles(1.0 / 60.0)
	var stunned_by_it: bool = run.stunned > 0.0
	# ---- slick ice, and a map's frost rows ----
	_cf_bare(run)
	run.slicks = [{"y0": 280.0, "y1": 340.0}]
	var slid: Dictionary = run._ball(Vector2(640, 310), Vector2(0, -Run.SPEED))
	var dry: Dictionary = run._ball(Vector2(640, 420), Vector2(0, -Run.SPEED))
	run.balls = [slid, dry]
	for i in 30:
		run.step(1.0 / 60.0)
		slid["p"] = Vector2(640, 310)
		dry["p"] = Vector2(640, 420)
	var slick_ok: bool = (slid["v"] as Vector2).length() > Run.SPEED * 1.2 and absf((dry["v"] as Vector2).length() - Run.SPEED) < 1.0
	var frosted_map: int = -1
	for i in ice:
		if (Maps.MAPS[i] as Dictionary).has("frost"):
			frosted_map = i
			break
	run.begin(frosted_map)
	var band: Array = Maps.MAPS[frosted_map]["frost"][0]
	var in_band: int = 0
	var rows_frosted: bool = true
	for k in run.bricks:
		if k.has("cell") and run._breaks(k) and not ["heart", "guard", "key"].has(str(k["kind"])) \
				and (k["cell"] as Vector2i).y >= int(band[0]) and (k["cell"] as Vector2i).y <= int(band[1]):
			in_band += 1
			rows_frosted = rows_frosted and k.has("frost")
	rows_frosted = rows_frosted and in_band > 0
	check("ICE: a frost coat takes a hit of its own before the brick (fire goes through it); packed ice takes three; a snowdrift two, and it soaks up the ball's speed; an icicle falls when its brick goes and strikes the first brick below for %d - or stuns the paddle; slick ice runs the ball %sx faster; a map's frost rows coat every brick in them" % [Run.ICICLE_HIT, str(Run.SLICK_SPEED)],
		coat_first and fire_through and three and soaked and fell and stunned_by_it and slick_ok and rows_frosted,
		[coat_first, fire_through, three, soaked, fell, stunned_by_it, slick_ok, rows_frosted])
	# ---- the Frost King ----
	run.begin(int(ice[4]))
	var king = run.boss
	run.state = Run.State.PLAY
	var near: Dictionary = run._ball(king.p + Vector2(0, 150), Vector2(0, -Run.SPEED))
	var far: Dictionary = run._ball(king.p + Vector2(0, Boss.BREATH_REACH + 60.0), Vector2(0, -Run.SPEED))
	run.balls = [near, far]
	king.breath_t = 0.001
	king.step(0.01, true)
	var breathed: bool = str(king.kind) == "frostking" and (near["v"] as Vector2).length() < Run.SPEED * 0.6 \
		and absf((far["v"] as Vector2).length() - Run.SPEED) < 1.0 and king.breaths.size() == 1
	run._hit_boss(Boss.SPLIT_EVERY)
	var young: bool = king.minions.size() == 1
	var landed: Dictionary = {}
	for k in run.bricks:
		if k.has("cell") and int(k["hp"]) > 0 and run._breaks(k) and not k.has("frost") and not ["heart", "guard"].has(str(k["kind"])):
			landed = k
			break
	young = young and bool(run.frost_at((landed["rect"] as Rect2).get_center())) and landed.has("frost")
	# and his young do it where they land, as they hop
	run._hit_boss(Boss.SPLIT_EVERY * 2)
	var frosted_before: int = run.bricks.filter(func(k: Dictionary) -> bool: return k.has("frost") and int(k["hp"]) > 0).size()
	for i in 60 * 20:
		king._step_minions(1.0 / 60.0, true)
	young = young and run.bricks.filter(func(k: Dictionary) -> bool: return k.has("frost") and int(k["hp"]) > 0).size() > frosted_before
	# ---- the Snow Sprite ----
	run.begin(int(ice[9]))
	var sprite = run.boss
	run.state = Run.State.PLAY
	var before_hang: int = run.breakable
	sprite.icicle_t = 0.001
	sprite.step(0.01, true)
	var hung: bool = run.breakable == before_hang + 1 and run.hanging.size() == 1
	var made_icicle: Dictionary = run.hanging[0] if hung else {}
	for i in roundi((Run.ICICLE_HANG + 0.1) * 60.0):
		run._icicles(1.0 / 60.0)
	hung = hung and int(made_icicle["hp"]) == 0
	# ---- the Ice Sniper ----
	run.begin(int(ice[14]))
	var sniper = run.boss
	run.state = Run.State.PLAY
	run.paddle_x = 640.0
	run.target_x = 640.0
	sniper.snipe_t = 0.001
	for i in roundi((Boss.AIM_SECONDS + 0.2) * 60.0):
		sniper._snipe(1.0 / 60.0)
	var iced_ok: bool = run.iced > 0.0 and run.stunned == 0.0
	run.target_x = 900.0
	for i in 30:
		run.step(1.0 / 60.0)
	run.target_x = run.paddle_x
	var at_stop: float = run.paddle_x
	run.step(1.0 / 60.0)
	run.step(1.0 / 60.0)
	iced_ok = iced_ok and run.paddle_x > at_stop + 1.0
	# ---- the Frost Mage ----
	run.begin(int(ice[19]))
	var mage = run.boss
	run.state = Run.State.PLAY
	var walled_before: int = run.breakable
	mage._ice_wall()
	var walled: int = run.breakable - walled_before
	# a row wider than the cap: the wall stops at ICE_WALL_MOST
	var wide_row: int = int(run.rows_count) - 1
	for c in run.cols:
		var o: Variant = run.cells.get(Vector2i(c, wide_row))
		if o != null and int(o["hp"]) > 0 and run._breaks(o):
			run._damage(o, 99, null)
	walled = walled if run.ice_wall(wide_row, 0, run.cols - 1, Boss.ICE_WALL_MOST) == Boss.ICE_WALL_MOST else -1
	var gone: int = 0
	for k in run.bricks:
		if gone < Boss.REBUILD_COUNT and k.has("cell") and int(k["hp"]) > 0 and run._breaks(k) and not run._guarded(k) \
				and (k["rect"] as Rect2).position.y > mage.hall.end.y + 40.0:
			run._damage(k, 99, null)
			gone += 1
	var frost_before: int = run.bricks.filter(func(k: Dictionary) -> bool: return k.has("frost") and int(k["hp"]) > 0).size()
	mage.rebuild_t = 0.001
	mage._ward_step(0.01)
	var frost_after: int = run.bricks.filter(func(k: Dictionary) -> bool: return k.has("frost") and int(k["hp"]) > 0).size()
	var mage_ok: bool = walled > 0 and walled <= Boss.ICE_WALL_MOST and frost_after == frost_before + Boss.REBUILD_COUNT \
		and mage.wards.size() == Boss.WARDS
	# ---- the Glacier Lord ----
	run.begin(int(ice[24]))
	var lord = run.boss
	run.state = Run.State.PLAY
	for k in run.bricks:
		if k.has("cell") and int(k["hp"]) > 0 and run._breaks(k) and not run._guarded(k) and (k["rect"] as Rect2).position.y > lord.hall.end.y:
			run._damage(k, 99, null)
	var before_snow: int = run.breakable
	lord.avalanche_t = 0.001
	lord.step(0.01, true)
	var snowed: int = run.breakable - before_snow
	var lord_ok: bool = lord.crowned and str(lord.title) == "The Glacier Lord" and snowed > 0 and snowed <= Boss.AVALANCHE_MOST \
		and lord.slides.size() == 1
	# (the bricks broken for his avalanche took their share of his health)
	@warning_ignore("integer_division")
	run._hit_boss(maxi(Boss.RULER_SPLIT_EVERY, lord.hp - lord.most * 2 / 3 + Boss.RULER_SPLIT_EVERY + 1))
	lord_ok = lord_ok and lord.minions.size() > 0
	check("  ICE'S BOSSES: the Frost King's breath slows near balls and his young coat bricks in frost; the Snow Sprite hangs an icicle that falls in its time; the Ice Sniper's lance ices the paddle and it slides on; the Frost Mage raises a wall of ice (%d at most) and rebuilds in frost; the Glacier Lord's avalanche pours snowdrifts (%d at most) and he splits" % [Boss.ICE_WALL_MOST, Boss.AVALANCHE_MOST],
		breathed and young and hung and iced_ok and mage_ok and lord_ok,
		[breathed, young, hung, iced_ok, mage_ok, lord_ok, walled, snowed])
	print("  crownfall ice: done")


func _test_crownfall_earth(run: Node2D, earth: Array) -> void:
	"""The Kingdom of Earth (the same 0.165.0): pillars that topple, boulders,
	ore, sand that settles, tremors, the heavy paddle, the way on from the
	Glacier Lord, and its five bosses."""
	const Run := preload("res://src/world/crownfall/crownfallrun.gd")
	const Boss := preload("res://src/world/crownfall/crownfallboss.gd")
	const Maps := preload("res://src/world/crownfall/crownfallmaps.gd")
	var count_of := func(kind: String) -> int:
		return run.bricks.filter(func(k: Dictionary) -> bool: return str(k["kind"]) == kind and int(k["hp"]) > 0).size()
	# ---- a pillar topples ----
	_cf_bare(run)
	var foot: Dictionary = run._add(5, 10, "foot", "earth", 2)
	var stack: Array = [run._add(5, 9, "column", "earth", 2), run._add(5, 8, "column", "earth", 2), run._add(5, 7, "land", "earth", 2)]
	var apart: Dictionary = run._add(5, 5, "land", "light", 1)
	var under: Dictionary = run._add(5, 13, "stone", "", 3)
	run._damage(foot, 1, null)
	var cracked: bool = int(foot["hp"]) == 1 and run.rubble.is_empty() and stack.all(func(k: Dictionary) -> bool: return int(k["hp"]) > 0)
	var score_was: int = run.score
	run._damage(foot, 1, null)
	var toppled: bool = int(foot["hp"]) == 0 and run.rubble.size() == 3 and stack.all(func(k: Dictionary) -> bool: return int(k["hp"]) == 0) \
		and int(apart["hp"]) == 1 and run.score >= score_was + Run.TOPPLE_SCORE * 3 and not run.cells.has(Vector2i(5, 8))
	for i in 60:
		run._earth(1.0 / 60.0)
	toppled = toppled and int(under["hp"]) == 0 and run.rubble.is_empty()
	# the topple pays TOPPLE_SCORE a block on top of the blocks' own score
	_cf_bare(run)
	var foot3: Dictionary = run._add(9, 10, "foot", "earth", 2)
	run._add(9, 9, "column", "earth", 2)
	run._add(9, 8, "column", "earth", 2)
	var rate: float = run._multiplier()
	score_was = run.score
	toppled = toppled and run.topple(foot3) == 2 \
		and run.score - score_was == int(round(int(Run.SCORE["column"]) * rate)) * 2 + int(round(Run.TOPPLE_SCORE * 2 * rate))
	# a key in the way stops it
	_cf_bare(run)
	var foot2: Dictionary = run._add(8, 10, "foot", "earth", 2)
	var low: Dictionary = run._add(8, 9, "column", "earth", 2)
	var key: Dictionary = run._add(8, 8, "key", "light", 1)
	var high: Dictionary = run._add(8, 7, "column", "earth", 2)
	run._damage(foot2, 99, null)
	var held: bool = int(low["hp"]) == 0 and int(key["hp"]) == 1 and int(high["hp"]) == 2 and run.rubble.size() == 1
	# ---- ore and sand ----
	_cf_bare(run)
	var ore: Dictionary = run._add(12, 4, "ore", "earth", 3)
	score_was = run.score
	run._damage(ore, 1, null)
	run._damage(ore, 1, null)
	var three: bool = int(ore["hp"]) == 1
	run._damage(ore, 1, null)
	three = three and int(ore["hp"]) == 0 and run.score >= score_was + int(Run.SCORE["ore"])
	var sand: Dictionary = run._add(14, 3, "sand", "earth", 1)
	var prop: Dictionary = run._add(14, 4, "land", "light", 1)
	run._add(14, 9, "stone", "", 3)
	run._earth(Run.SAND_STEP + 0.01)
	var stayed: bool = sand["cell"] == Vector2i(14, 3)
	run._damage(prop, 1, null)
	for i in 30:
		run._earth(Run.SAND_STEP + 0.01)
	var settled: bool = stayed and sand["cell"] == Vector2i(14, 8) and run.cells.get(Vector2i(14, 8)) == sand \
		and not run.cells.has(Vector2i(14, 3)) and int(sand["hp"]) == 1
	# a ball in the hole under it holds it up
	var held_up: Dictionary = run._add(18, 3, "sand", "earth", 1)
	run.balls = [run._ball(run._cell(18, 4).get_center(), Vector2.ZERO)]
	run._earth(Run.SAND_STEP + 0.01)
	settled = settled and held_up["cell"] == Vector2i(18, 3)
	run.balls.clear()
	# ---- the tremor ----
	_cf_bare(run)
	run.tremors = true
	var shaky: Dictionary = run._add(3, 10, "foot", "earth", 1)
	shaky["most"] = 2
	var shaky_top: Dictionary = run._add(3, 9, "column", "earth", 2)
	var sound: Dictionary = run._add(20, 10, "foot", "earth", 2)
	var sound_top: Dictionary = run._add(20, 9, "column", "earth", 2)
	var rolling: Dictionary = run._ball(Vector2(640, 500), Vector2(0, -Run.SPEED))
	run.balls = [rolling]
	run.tremor_t = Run.TREMOR_EVERY - Run.TREMOR_WARN + 0.01
	run._earth(0.01)
	var warned: bool = run.words.any(func(w: Dictionary) -> bool: return str(w["text"]).begins_with("THE GROUND RUMBLES")) \
		and int(shaky["hp"]) == 1
	run._earth(Run.TREMOR_WARN)
	var shook: bool = warned and int(shaky["hp"]) == 0 and int(shaky_top["hp"]) == 0 and int(sound["hp"]) == 2 \
		and int(sound_top["hp"]) == 2 and absf((rolling["v"] as Vector2).length() - Run.SPEED) < 1.0 \
		and not (rolling["v"] as Vector2).is_equal_approx(Vector2(0, -Run.SPEED)) and run.tremor_t < 1.0
	shook = shook and run.tremor_now(true) == 1 and int(sound_top["hp"]) == 0
	# ---- the heavy paddle ----
	_cf_bare(run)
	run.lives = Run.LIVES
	run.balls = [run._ball(Vector2(640, 300), Vector2(0, -Run.SPEED))]
	run.paddle_x = 640.0
	run.target_x = 900.0
	run.step(1.0 / 60.0)
	var free_step: float = run.paddle_x - 640.0
	run.paddle_x = 640.0
	run.weigh_paddle(2.0, Vector2(640, Run.PADDLE_Y))
	run.step(1.0 / 60.0)
	var heavy_ok: bool = run.heavy > 0.0 and absf(run.paddle_x - 640.0 - free_step * Run.HEAVY_SHARE) < 0.5 and free_step > 10.0
	# ---- a map's letters ----
	var lettered: bool = true
	var boulder_ok: bool = false
	for i in earth:
		run.begin(i)
		var want: Dictionary = {"A": 0, "E": 0, "g": 0, "n": 0, "b": 0}
		for r in (Maps.MAPS[i]["rows"] as Array):
			for ch in str(r):
				if want.has(ch):
					want[ch] = int(want[ch]) + 1
		var rock_cells: int = 0
		for k in run.bricks:
			if str(k["kind"]) == "boulder":
				rock_cells += (k["cells"] as Array).size()
				if (k["cells"] as Array).size() == 2 and not boulder_ok:
					var c0: Vector2i = k["cells"][0]
					var c1: Vector2i = k["cells"][1]
					boulder_ok = int(k["hp"]) == 4 and c1 == c0 + Vector2i(1, 0) and run.cells.get(c0) == k and run.cells.get(c1) == k \
						and is_equal_approx((k["rect"] as Rect2).size.x, run.cw * 2.0 - 2.0)
					if boulder_ok:
						for n in 3:
							run._damage(k, 1, null)
						boulder_ok = int(k["hp"]) == 1 and run.cells.get(c1) == k
						run._damage(k, 1, null)
						boulder_ok = boulder_ok and int(k["hp"]) == 0 and not run.cells.has(c0) and not run.cells.has(c1)
		var hits: Dictionary = {"foot": 2, "column": 2, "ore": 3, "sand": 1}
		for k in run.bricks:
			if hits.has(str(k["kind"])):
				lettered = lettered and int(k["hp"]) == int(hits[str(k["kind"])]) and int(k["most"]) == int(hits[str(k["kind"])])
		lettered = lettered and run.tremors and count_of.call("foot") == int(want["A"]) and count_of.call("column") == int(want["E"]) \
			and count_of.call("ore") == int(want["g"]) and count_of.call("sand") == int(want["n"]) and rock_cells == int(want["b"])
	check("EARTH: a pillar's foot cracks at the first hit and at the second the pillar falls - every brick on it up to the first gap (a key stops it), %d score a block - and its rubble smashes what is below; a boulder is two cells, four hits; ore three; sand settles into the hole under it; the tremor rumbles first, then brings down every pillar on a cracked foot and jolts the ball (a quake, every pillar); the Rock Sniper's weight slows the paddle to %s; every earth map's letters become its bricks, and it shakes" % [Run.TOPPLE_SCORE, str(Run.HEAVY_SHARE)],
		cracked and toppled and held and three and settled and shook and heavy_ok and lettered and boulder_ok,
		[cracked, toppled, held, three, settled, shook, heavy_ok, lettered, boulder_ok])
	# ---- on from Ice ----
	run.begin(int(earth[0]) - 1)
	run.state = Run.State.PLAY
	run._hit_boss(run.boss.hp)
	run.step(1.0 / 60.0)
	for i in roundi(Run.CLEARED_SECONDS * 60.0) + 2:
		run.step(1.0 / 60.0)
	var on_to_earth: bool = run.state == Run.State.AIM and run.map_index == int(earth[0]) and str(Maps.kingdom_of(run.map_index)["id"]) == "earth"
	# ---- the Stone King ----
	run.begin(int(earth[4]))
	var king = run.boss
	run.state = Run.State.PLAY
	var feet: Array = run.bricks.filter(func(k: Dictionary) -> bool: return str(k["kind"]) == "foot" and int(k["hp"]) > 0 and not run._guarded(k))
	(feet[0] as Dictionary)["hp"] = 1
	king.stomp_t = 0.001
	king.step(0.01, true)
	var stomped: bool = str(king.kind) == "stoneking" and int((feet[0] as Dictionary)["hp"]) == 0 and king.gales.size() == 1 \
		and feet.slice(1).all(func(k: Dictionary) -> bool: return int(k["hp"]) == 2)
	run._hit_boss(Boss.SPLIT_EVERY)
	var young: bool = king.minions.size() == 1
	var spot := Vector2i(-1, -1)
	for row in run.rows_count:
		for c in run.cols:
			var r: Rect2 = run._cell(c, row)
			if spot.x < 0 and not run.cells.has(Vector2i(c, row)) and not king.hall.grow(2.0).intersects(r):
				spot = Vector2i(c, row)
	var sand_before: int = count_of.call("sand")
	young = young and bool(run.pile_sand(run._cell(spot.x, spot.y).get_center())) and count_of.call("sand") == sand_before + 1 \
		and str(run.cells[spot]["kind"]) == "sand"
	run._hit_boss(Boss.SPLIT_EVERY * 2)
	sand_before = count_of.call("sand")
	for i in 60 * 20:
		king._step_minions(1.0 / 60.0, true)
	young = young and count_of.call("sand") > sand_before
	# ---- the Dust Sprite ----
	run.begin(int(earth[9]))
	var sprite = run.boss
	run.state = Run.State.PLAY
	var gone: int = 0
	for k in run.bricks:
		if gone < Boss.DUST_MOST + 2 and k.has("cell") and int(k["hp"]) > 0 and run._breaks(k) and not run._guarded(k) \
				and str(k["kind"]) == "land" and (k["rect"] as Rect2).position.y > sprite.hall.end.y:
			run._damage(k, 99, null)
			gone += 1
	sand_before = count_of.call("sand")
	sprite.dust_t = 0.001
	sprite.step(0.01, true)
	var dusted: bool = str(sprite.kind) == "dustsprite" and count_of.call("sand") == sand_before + Boss.DUST_MOST
	# ---- the Rock Sniper ----
	run.begin(int(earth[14]))
	var sniper = run.boss
	run.state = Run.State.PLAY
	run.paddle_x = 640.0
	run.target_x = 640.0
	sniper.snipe_t = 0.001
	for i in roundi((Boss.AIM_SECONDS + 0.2) * 60.0):
		sniper._snipe(1.0 / 60.0)
	var weighed: bool = run.heavy > 0.0 and run.stunned == 0.0 and run.iced == 0.0
	# ---- the Earth Mage ----
	run.begin(int(earth[19]))
	var mage = run.boss
	run.state = Run.State.PLAY
	var col: int = -1
	for c in range(run.cell_at(Vector2(mage.hall.position.x + 2.0, 0)).x, run.cell_at(Vector2(mage.hall.end.x - 2.0, 0)).x):
		if col < 0 and not run.cells.has(Vector2i(c, run.rows_count - 6)) and not run.cells.has(Vector2i(c, run.rows_count - 5)):
			col = c
	var feet_before: int = count_of.call("foot")
	var before_pillar: int = run.breakable
	var raised: int = run.raise_pillar(run._cell(col, 0).get_center().x, Boss.PILLAR_TALL)
	var made_ok: bool = raised >= 2 and raised <= Boss.PILLAR_TALL and run.breakable == before_pillar + raised \
		and count_of.call("foot") == feet_before + 1
	var base_row: int = -1
	for row in run.rows_count:
		var o: Variant = run.cells.get(Vector2i(col, row))
		if o != null and str(o["kind"]) == "foot" and o.has("flash") and float(o["flash"]) > 0.0:
			base_row = row
	made_ok = made_ok and base_row >= 0 and str(run.cells[Vector2i(col, base_row - 1)]["kind"]) == "column"
	before_pillar = run.breakable
	mage.pillar_t = 0.001
	mage.step(0.01, true)
	made_ok = made_ok and run.breakable >= before_pillar and mage.wards.size() == Boss.WARDS
	gone = 0
	for k in run.bricks:
		if gone < Boss.REBUILD_COUNT and k.has("cell") and int(k["hp"]) > 0 and run._breaks(k) and not run._guarded(k) \
				and str(k["kind"]) == "land" and (k["rect"] as Rect2).position.y > mage.hall.end.y + 40.0:
			run._damage(k, 99, null)
			gone += 1
	var stone_before: int = count_of.call("stone")
	mage.rebuild_t = 0.001
	mage._ward_step(0.01)
	made_ok = made_ok and count_of.call("stone") == stone_before + Boss.REBUILD_COUNT
	# ---- the Mountain Lord ----
	run.begin(int(earth[24]))
	var lord = run.boss
	run.state = Run.State.PLAY
	for k in run.bricks:
		if k.has("cell") and int(k["hp"]) > 0 and run._breaks(k) and not ["foot", "column", "guard"].has(str(k["kind"])) \
				and (k["rect"] as Rect2).position.y > lord.hall.end.y:
			run._damage(k, 99, null)
	var standing: Array = run.bricks.filter(func(k: Dictionary) -> bool: return str(k["kind"]) == "foot" and int(k["hp"]) > 0 and not run._guarded(k))
	var rocks_before: int = count_of.call("boulder")
	lord.quake_t = 0.001
	lord.step(0.01, true)
	var rocks: int = count_of.call("boulder") - rocks_before
	var lord_ok: bool = lord.crowned and str(lord.title) == "The Mountain Lord" and standing.size() >= 2 \
		and standing.all(func(k: Dictionary) -> bool: return int(k["hp"]) == 0) and rocks > 0 and rocks <= Boss.ROCKFALL_MOST \
		and lord.slides.size() == 1 and bool(lord.slides[0].get("rock", false))
	# (the bricks broken for his quake took their share of his health)
	@warning_ignore("integer_division")
	run._hit_boss(maxi(Boss.RULER_SPLIT_EVERY, lord.hp - lord.most * 2 / 3 + Boss.RULER_SPLIT_EVERY + 1))
	lord_ok = lord_ok and lord.minions.size() > 0
	check("  EARTH'S BOSSES: the Glacier Lord's fall leads on into the Kingdom of Earth; the Stone King's stomp brings down a pillar on a cracked foot and his young pile sand; the Dust Sprite kicks up %d sand; the Rock Sniper's shot weighs the paddle down; the Earth Mage raises a pillar (%d at most) on its foot and rebuilds in stone; the Mountain Lord's quake brings every pillar down and drops boulders (%d at most), and he splits" % [Boss.DUST_MOST, Boss.PILLAR_TALL, Boss.ROCKFALL_MOST],
		on_to_earth and stomped and young and dusted and weighed and made_ok and lord_ok,
		[on_to_earth, stomped, young, dusted, weighed, made_ok, lord_ok, raised, rocks, standing.size()])
	print("  crownfall earth: done")


func _test_crownfall_fire(run: Node2D, fire: Array) -> void:
	"""The Kingdom of Fire (the same 0.165.0): wood that catches and spreads a
	link at a time, fuses, powder kegs, obsidian, lava that cools, eruptions,
	fire on the floor, the scorched paddle, the way on from the Mountain Lord,
	and its five bosses."""
	const Run := preload("res://src/world/crownfall/crownfallrun.gd")
	const Boss := preload("res://src/world/crownfall/crownfallboss.gd")
	const Maps := preload("res://src/world/crownfall/crownfallmaps.gd")
	var count_of := func(kind: String) -> int:
		return run.bricks.filter(func(k: Dictionary) -> bool: return str(k["kind"]) == kind and int(k["hp"]) > 0).size()
	# ---- wood ----
	_cf_bare(run)
	var plain: Dictionary = run._add(3, 3, "wood", "fire", 2)
	var striker: Dictionary = run._ball(Vector2(640, 500), Vector2(0, -Run.SPEED))
	run._damage(plain, 1, striker)
	var two_hits: bool = int(plain["hp"]) == 1 and float(plain["burn"]) < 0.0
	run._damage(plain, 1, striker)
	two_hits = two_hits and int(plain["hp"]) == 0
	var logs: Array = [run._add(10, 5, "wood", "fire", 2), run._add(11, 5, "wood", "fire", 2), run._add(12, 5, "wood", "fire", 2)]
	var stone: Dictionary = run._add(10, 6, "land", "light", 1)
	run.active["fire"] = 6.0
	run._damage(logs[0], 99, striker)
	run.active.erase("fire")
	var caught: bool = int(logs[0]["hp"]) == 2 and float(logs[0]["burn"]) >= 0.0
	run._burns(Run.WOOD_BURN + 0.01)
	var link_one: bool = int(logs[0]["hp"]) == 0 and float(logs[1]["burn"]) >= 0.0 and float(logs[2]["burn"]) < 0.0 \
		and int(stone["hp"]) == 1 and float(stone["burn"]) < 0.0
	run._burns(Run.WOOD_BURN + 0.01)
	var link_two: bool = int(logs[1]["hp"]) == 0 and float(logs[2]["burn"]) >= 0.0 and int(logs[2]["hp"]) == 2
	run._burns(Run.WOOD_BURN + 0.01)
	var wood_ok: bool = two_hits and caught and link_one and link_two and int(logs[2]["hp"]) == 0
	# ---- a fuse runs to its bomb ----
	_cf_bare(run)
	var fuses: Array = [run._add(4, 8, "fuse", "fire", 1), run._add(5, 8, "fuse", "fire", 1), run._add(6, 8, "fuse", "fire", 1)]
	var bomb: Dictionary = run._add(7, 8, "tnt", "fire", 1)
	var by_bomb: Dictionary = run._add(7, 9, "stone", "", 3)
	run._damage(fuses[0], 1, striker)
	var lit: bool = int(fuses[0]["hp"]) == 1 and float(fuses[0]["burn"]) >= 0.0 and float(fuses[1]["burn"]) < 0.0
	for i in 12:
		run._burns(Run.FUSE_STEP + 0.01)
	var fuse_ok: bool = lit and fuses.all(func(k: Dictionary) -> bool: return int(k["hp"]) == 0) and int(bomb["hp"]) == 0 \
		and int(by_bomb["hp"]) == 1
	# ---- a powder keg ----
	_cf_bare(run)
	var keg: Dictionary = run._add(10, 5, "keg", "fire", 2)
	var far_tnt: Dictionary = run._add(14, 5, "tnt", "fire", 1)
	var near_land: Dictionary = run._add(10, 12, "land", "light", 1)
	var out_land: Dictionary = run._add(17, 5, "land", "light", 1)
	var near_wood: Dictionary = run._add(10, 3, "wood", "fire", 2)
	var next_keg: Dictionary = run._add(7, 5, "keg", "fire", 2)
	run._damage(keg, 1, striker)
	var keg_ok: bool = int(keg["hp"]) == 1 and float(far_tnt["burn"]) < 0.0
	run._damage(keg, 1, striker)
	keg_ok = keg_ok and int(keg["hp"]) == 0 and float(far_tnt["burn"]) >= 0.0 and int(near_land["hp"]) == 0 \
		and int(out_land["hp"]) == 1 and float(near_wood["burn"]) >= 0.0 and int(near_wood["hp"]) == 2 \
		and float(next_keg["burn"]) >= 0.0 and int(next_keg["hp"]) == 2
	# ---- obsidian, lava ----
	_cf_bare(run)
	var glass: Dictionary = run._add(3, 3, "obsidian", "fire", 4)
	for i in 3:
		run._damage(glass, 1, striker)
	var four: bool = int(glass["hp"]) == 1
	run._damage(glass, 1, striker)
	four = four and int(glass["hp"]) == 0
	var lava: Dictionary = run._add(8, 3, "lava", "fire", 1)
	lava["cool"] = Run.LAVA_COOL
	run.state = Run.State.AIM
	run._fire(Run.LAVA_COOL + 1.0)
	var waits: bool = str(lava["kind"]) == "lava"
	run.state = Run.State.PLAY
	run._fire(Run.LAVA_COOL + 1.0)
	var cooled: bool = waits and str(lava["kind"]) == "basalt" and int(lava["hp"]) == 3 and int(lava["most"]) == 3
	var hot: Dictionary = run._add(14, 3, "lava", "fire", 1)
	hot["cool"] = Run.LAVA_COOL
	var kindling: Dictionary = run._add(15, 3, "wood", "fire", 2)
	run._damage(hot, 1, striker)
	cooled = cooled and int(hot["hp"]) == 0 and float(kindling["burn"]) >= 0.0
	# ---- eruptions and lava bombs ----
	_cf_bare(run)
	run.eruptions = true
	run.erupt_t = Run.ERUPT_EVERY - Run.ERUPT_WARN + 0.01
	run._fire(0.01)
	var rumbled: bool = run.words.any(func(w: Dictionary) -> bool: return str(w["text"]).begins_with("THE VOLCANO RUMBLES")) and run.bombs.is_empty()
	run._fire(Run.ERUPT_WARN)
	var erupted: bool = rumbled and run.bombs.size() == Run.ERUPT_BOMBS and run.erupt_t < 1.0
	_cf_bare(run)
	var floor_stone: Dictionary = run._add(10, 8, "stone", "", 3)
	run.lava_bomb(run._cell(10, 0).get_center().x, Run.ARENA.position.y + 4.0)
	run.paddle_x = run._cell(20, 0).get_center().x
	run.lava_bomb(run.paddle_x, Run.ARENA.position.y + 4.0)
	for i in 120:
		run._fire(1.0 / 60.0)
	var landed: Variant = run.cells.get(Vector2i(10, 7))
	var bombs_ok: bool = erupted and landed != null and str(landed["kind"]) == "lava" and int(floor_stone["hp"]) == 3 \
		and run.stunned > 0.0 and run.bombs.is_empty()
	# ---- fire on the floor; the scorched paddle ----
	_cf_bare(run)
	run.paddle_x = 640.0
	run.fire_patch(640.0)
	run._fire(Run.PATCH_WARN * 0.5)
	var patch_ok: bool = run.stunned == 0.0
	run._fire(Run.PATCH_WARN)
	run._fire(0.01)
	patch_ok = patch_ok and run.stunned > 0.0
	run.stunned = 0.0
	run._fire(0.5)
	patch_ok = patch_ok and run.stunned == 0.0
	run._fire(Run.PATCH_LIFE)
	patch_ok = patch_ok and run.patches.is_empty()
	run.fire_patch(200.0)
	run.paddle_x = 900.0
	run._fire(Run.PATCH_WARN + 0.5)
	patch_ok = patch_ok and run.stunned == 0.0
	_cf_bare(run)
	run.lives = Run.LIVES
	run.balls = [run._ball(Vector2(640, 300), Vector2(0, -Run.SPEED))]
	run.scorch_paddle(3.0, Vector2(640, Run.PADDLE_Y))
	for i in 30:
		run.step(1.0 / 60.0)
		run.balls[0]["p"] = Vector2(640, 300)
	var scorched: bool = run.scorched > 0.0 and absf(run.paddle_w - Run.PADDLE_W * Run.SCORCH_SHARE) < 1.0
	# ---- a map's letters ----
	var lettered: bool = true
	for i in fire:
		run.begin(i)
		var want: Dictionary = {"h": 0, "z": 0, "J": 0, "q": 0, "r": 0}
		for r in (Maps.MAPS[i]["rows"] as Array):
			for ch in str(r):
				if want.has(ch):
					want[ch] = int(want[ch]) + 1
		var hits: Dictionary = {"wood": 2, "fuse": 1, "keg": 2, "obsidian": 4, "lava": 1}
		for k in run.bricks:
			if hits.has(str(k["kind"])):
				lettered = lettered and int(k["hp"]) == int(hits[str(k["kind"])])
		lettered = lettered and run.eruptions and not run.tremors and count_of.call("wood") == int(want["h"]) \
			and count_of.call("fuse") == int(want["z"]) and count_of.call("keg") == int(want["J"]) \
			and count_of.call("obsidian") == int(want["q"]) and count_of.call("lava") == int(want["r"])
	check("FIRE: wood takes two hits from a ball, but a Fireball sets it alight and it spreads to the wood touching it a link at a time; a blow lights a fuse and the spark runs to its TNT; a powder keg blows %d wide, setting off TNT and kegs and lighting wood; obsidian takes four hits; lava cools into basalt after %d s of play (not before) and lights wood beside it when broken; the volcano rumbles, then %d lava bombs fall - setting as lava on what stands, stunning the paddle under one; fire on the floor warns, then stuns the paddle once; the scorched paddle is %s of its width; every fire map's letters become its bricks, and it erupts" % [Run.KEG_BLAST, Run.LAVA_COOL, Run.ERUPT_BOMBS, str(Run.SCORCH_SHARE)],
		wood_ok and fuse_ok and keg_ok and four and cooled and bombs_ok and patch_ok and scorched and lettered,
		[wood_ok, fuse_ok, keg_ok, four, cooled, bombs_ok, patch_ok, scorched, lettered])
	# ---- on from Earth ----
	run.begin(int(fire[0]) - 1)
	run.state = Run.State.PLAY
	run._hit_boss(run.boss.hp)
	run.step(1.0 / 60.0)
	for i in roundi(Run.CLEARED_SECONDS * 60.0) + 2:
		run.step(1.0 / 60.0)
	var on_to_fire: bool = run.state == Run.State.AIM and run.map_index == int(fire[0]) and str(Maps.kingdom_of(run.map_index)["id"]) == "fire"
	# ---- the Fire King ----
	run.begin(int(fire[4]))
	var king = run.boss
	run.state = Run.State.PLAY
	var tinted: bool = str(king.kind) == "fireking" and king.tint == Element.Type.FIRE
	if king.sprite != null:
		var mat: ShaderMaterial = king.sprite.material as ShaderMaterial
		tinted = tinted and mat != null and is_equal_approx(float(mat.get_shader_parameter("element_hue")), Element.hue_for(Element.Type.FIRE))
	var bombs_before: int = run.bombs.size()
	king.erupt_call_t = 0.001
	king.step(0.01, true)
	var called: bool = run.bombs.size() == bombs_before + Boss.ERUPT_CALL_BOMBS
	run._hit_boss(Boss.SPLIT_EVERY)
	var young: bool = king.minions.size() == 1
	var spot := Vector2i(-1, -1)
	for row in run.rows_count:
		for c in run.cols:
			var r: Rect2 = run._cell(c, row)
			if spot.x < 0 and not run.cells.has(Vector2i(c, row)) and not king.hall.grow(2.0).intersects(r) and not run._ball_near(r):
				spot = Vector2i(c, row)
	var lava_before: int = count_of.call("lava")
	young = young and bool(run.lava_at(run._cell(spot.x, spot.y).get_center())) and count_of.call("lava") == lava_before + 1
	var a_log: Dictionary = run.bricks.filter(func(k: Dictionary) -> bool: return str(k["kind"]) == "wood" and int(k["hp"]) > 0)[0]
	young = young and not bool(run.lava_at((a_log["rect"] as Rect2).get_center())) and float(a_log["burn"]) >= 0.0
	run._hit_boss(Boss.SPLIT_EVERY * 2)
	lava_before = count_of.call("lava")
	for i in 60 * 20:
		king._step_minions(1.0 / 60.0, true)
	young = young and count_of.call("lava") > lava_before
	# ---- the Flame Sprite ----
	run.begin(int(fire[9]))
	var sprite = run.boss
	run.state = Run.State.PLAY
	run.paddle_x = 500.0
	sprite.patch_t = 0.001
	sprite.step(0.01, true)
	var patched: bool = str(sprite.kind) == "flamesprite" and run.patches.size() == 1 and is_equal_approx(float(run.patches[0]["x"]), 500.0)
	# ---- the Fire Sniper ----
	run.begin(int(fire[14]))
	var sniper = run.boss
	run.state = Run.State.PLAY
	run.paddle_x = 640.0
	run.target_x = 640.0
	sniper.snipe_t = 0.001
	for i in roundi((Boss.AIM_SECONDS + 0.2) * 60.0):
		sniper._snipe(1.0 / 60.0)
	var scorch_ok: bool = run.scorched > 0.0 and run.stunned == 0.0 and run.heavy == 0.0 and sniper.tint == Element.Type.FIRE
	# ---- the Fire Mage ----
	run.begin(int(fire[19]))
	var mage = run.boss
	run.state = Run.State.PLAY
	bombs_before = run.bombs.size()
	mage.meteor_t = 0.001
	mage.step(0.01, true)
	var mage_ok: bool = run.bombs.size() == bombs_before + Boss.METEORS and mage.wards.size() == Boss.WARDS
	for f in run.bombs:
		mage_ok = mage_ok and absf((f["p"] as Vector2).y - (mage.hall.end.y + 4.0)) < 1.0
	var gone: int = 0
	for k in run.bricks:
		if gone < Boss.REBUILD_COUNT and k.has("cell") and int(k["hp"]) > 0 and run._breaks(k) and not run._guarded(k) \
				and str(k["kind"]) == "land" and (k["rect"] as Rect2).position.y > mage.hall.end.y + 40.0:
			run._damage(k, 99, null)
			gone += 1
	var glass_before: int = count_of.call("obsidian")
	mage.rebuild_t = 0.001
	mage._ward_step(0.01)
	mage_ok = mage_ok and count_of.call("obsidian") == glass_before + Boss.REBUILD_COUNT
	# ---- the Inferno ----
	run.begin(int(fire[24]))
	var lord = run.boss
	run.state = Run.State.PLAY
	bombs_before = run.bombs.size()
	lord.inferno_t = 0.001
	lord.step(0.01, true)
	var lord_ok: bool = lord.crowned and str(lord.title) == "The Inferno" and run.bombs.size() == bombs_before + Boss.INFERNO_BOMBS
	@warning_ignore("integer_division")
	run._hit_boss(lord.hp - lord.most * 2 / 3 + Boss.RULER_SPLIT_EVERY + 1)
	lord_ok = lord_ok and lord.minions.size() > 0
	check("  FIRE'S BOSSES: the Mountain Lord's fall leads on into the Kingdom of Fire; the Fire King wears the slime's art in fire's colour, calls an eruption (%d bombs), and his young leave lava or set wood alight; the Flame Sprite sets fire on the floor where the paddle is; the Fire Sniper's shot scorches the paddle; the Fire Mage throws %d meteors and rebuilds in obsidian; the Inferno's eruption is %d bombs, and he splits" % [Boss.ERUPT_CALL_BOMBS, Boss.METEORS, Boss.INFERNO_BOMBS],
		on_to_fire and tinted and called and young and patched and scorch_ok and mage_ok and lord_ok,
		[on_to_fire, tinted, called, young, patched, scorch_ok, mage_ok, lord_ok])
	print("  crownfall fire: done")


func _test_crownfall_dark(run: Node2D, dark_maps: Array) -> void:
	"""The Kingdom of Dark (the same 0.165.0), the last: the light, lanterns,
	shadow bricks that heal, void wells, nightfall, the hex, the way on from
	the Inferno, its five bosses, and the end of Crownfall."""
	const Run := preload("res://src/world/crownfall/crownfallrun.gd")
	const Boss := preload("res://src/world/crownfall/crownfallboss.gd")
	const Maps := preload("res://src/world/crownfall/crownfallmaps.gd")
	var count_of := func(kind: String) -> int:
		return run.bricks.filter(func(k: Dictionary) -> bool: return str(k["kind"]) == kind and int(k["hp"]) > 0).size()
	# ---- the light ----
	_cf_bare(run)
	run.dark = true
	run.paddle_x = 640.0
	var seen_far: Dictionary = run._add(3, 2, "land", "dark", 1)
	var seen_near: Dictionary = run._add(16, 4, "land", "dark", 1)
	var near_at: Vector2 = (seen_near["rect"] as Rect2).get_center()
	run.balls = [run._ball(near_at + Vector2(0, 100), Vector2.ZERO)]
	run._dark(0.2)
	var light_ok: bool = float(seen_near["seen"]) == 1.0 and float(seen_far["seen"]) == 0.0
	run.balls[0]["p"] = near_at + Vector2(0, 400)
	run._dark(0.5)
	light_ok = light_ok and float(seen_near["seen"]) < 1.0 and float(seen_near["seen"]) > 0.0
	run._dark(Run.SEEN_FADE)
	light_ok = light_ok and float(seen_near["seen"]) == 0.0
	run.balls[0]["p"] = near_at + Vector2(0, 100)
	run.night_left = 1.0
	run._dark(0.2)
	light_ok = light_ok and float(seen_near["seen"]) == 0.0
	run.night_left = 0.0
	run.light_stolen = 1.0
	run._dark(0.2)
	light_ok = light_ok and float(seen_near["seen"]) == 0.0
	run.light_stolen = 0.0
	light_ok = light_ok and run.light_sources().size() == run.balls.size() + 1
	run.blackout = 1.0
	light_ok = light_ok and run.light_sources().size() == run.balls.size()
	run.blackout = 0.0
	run.active["element"] = 12.0
	run.ball_land = "light"
	light_ok = light_ok and is_equal_approx(float(run.light_sources()[0][1]), Run.LIGHT_BALL * 1.6)
	run.active.erase("element")
	run.ball_land = ""
	# ---- lanterns ----
	_cf_bare(run)
	run.dark = true
	run.paddle_x = 640.0
	var lamp: Dictionary = run._add(10, 3, "lantern", "light", 1)
	var by_lamp: Dictionary = run._add(12, 4, "land", "dark", 1)
	var off_lamp: Dictionary = run._add(28, 4, "land", "dark", 1)
	run._damage(lamp, 1, null)
	run._dark(0.2)
	var lamp_ok: bool = run.lanterns.size() == 1 and float(by_lamp["seen"]) == 1.0 and float(off_lamp["seen"]) == 0.0
	run.blackout = 5.0
	run._dark(Run.SEEN_FADE + 0.1)
	lamp_ok = lamp_ok and float(by_lamp["seen"]) == 0.0
	run.blackout = 0.0
	# ---- shadow bricks, void wells ----
	_cf_bare(run)
	run.dark = true
	run.paddle_x = 640.0
	var shade: Dictionary = run._add(6, 3, "shadow", "dark", 2)
	run._damage(shade, 1, null)
	run._dark(Run.SHADOW_HEAL + 0.1)
	var healed: bool = int(shade["hp"]) == 2
	run._damage(shade, 1, null)
	run.balls = [run._ball((shade["rect"] as Rect2).get_center() + Vector2(0, 60), Vector2.ZERO)]
	run._dark(Run.SHADOW_HEAL + 0.1)
	healed = healed and int(shade["hp"]) == 1
	var well: Dictionary = run._add(20, 6, "void", "dark", 3)
	run.voids = [well]
	var well_at: Vector2 = (well["rect"] as Rect2).get_center()
	var drawn: Dictionary = run._ball(well_at + Vector2(60, 40), Vector2(0, -Run.SPEED))
	var free: Dictionary = run._ball(well_at + Vector2(300, 40), Vector2(0, -Run.SPEED))
	run.balls = [drawn, free]
	run._voids(0.1)
	var pulled: bool = (drawn["v"] as Vector2).x < -1.0 and (free["v"] as Vector2).is_equal_approx(Vector2(0, -Run.SPEED)) \
		and absf((drawn["v"] as Vector2).length() - Run.SPEED) < 1.0
	for i in 2:
		run._damage(well, 1, null)
	pulled = pulled and int(well["hp"]) == 1
	run._damage(well, 1, null)
	run._voids(0.1)
	pulled = pulled and int(well["hp"]) == 0 and run.voids.is_empty()
	# ---- nightfall; the hex ----
	_cf_bare(run)
	run.dark = true
	run.night_t = Run.NIGHT_EVERY - Run.NIGHT_WARN + 0.01
	run._dark(0.01)
	var night_ok: bool = run.words.any(func(w: Dictionary) -> bool: return str(w["text"]).begins_with("THE DARK DEEPENS")) and run.night_left == 0.0
	run._dark(Run.NIGHT_WARN)
	night_ok = night_ok and is_equal_approx(run.night_left, Run.NIGHT_SECONDS) and run.night_t < 1.0
	run.balls = [run._ball(Vector2(640, 300), Vector2.ZERO)]
	night_ok = night_ok and is_equal_approx(float(run.light_sources()[0][1]), Run.LIGHT_BALL * Run.NIGHT_SHARE)
	_cf_bare(run)
	run.lives = Run.LIVES
	run.balls = [run._ball(Vector2(640, 300), Vector2(0, -Run.SPEED))]
	run.paddle_x = 640.0
	run.target_x = 900.0
	run.hex_paddle(1.0, Vector2(640, Run.PADDLE_Y))
	run.step(1.0 / 60.0)
	var hex_ok: bool = run.paddle_x < 640.0
	for i in 70:
		run.step(1.0 / 60.0)
		run.balls[0]["p"] = Vector2(640, 300)
	var at_end: float = run.paddle_x
	run.step(1.0 / 60.0)
	hex_ok = hex_ok and run.hexed == 0.0 and run.paddle_x > at_end
	# ---- a map's letters ----
	var lettered: bool = true
	for i in dark_maps:
		run.begin(i)
		var want: Dictionary = {"t": 0, "m": 0, "v": 0}
		for r in (Maps.MAPS[i]["rows"] as Array):
			for ch in str(r):
				if want.has(ch):
					want[ch] = int(want[ch]) + 1
		var hits: Dictionary = {"lantern": 1, "shadow": 2, "void": 3}
		for k in run.bricks:
			if hits.has(str(k["kind"])):
				lettered = lettered and int(k["hp"]) == int(hits[str(k["kind"])])
		lettered = lettered and run.dark and not run.eruptions and count_of.call("lantern") == int(want["t"]) \
			and count_of.call("shadow") == int(want["m"]) and count_of.call("void") == int(want["v"]) and run.voids.size() == int(want["v"])
	run.begin(int(dark_maps[0]) - 1)
	lettered = lettered and not run.dark
	check("DARK: a brick shows only in the light - a ball's (less at nightfall, less while the Wisp has it, more for a light ball) - and fades back over %s s; a lantern broken lights its corner for good (not in the eclipse); a shadow brick heals in the dark, not in the light; a void well draws a near ball in, its speed kept, and takes three hits; the dark deepens before nightfall halves every light; the hex swaps left and right, and wears off; every dark map's letters become its bricks, and it is dark" % str(Run.SEEN_FADE),
		light_ok and lamp_ok and healed and pulled and night_ok and hex_ok and lettered,
		[light_ok, lamp_ok, healed, pulled, night_ok, hex_ok, lettered])
	# ---- on from Fire ----
	run.begin(int(dark_maps[0]) - 1)
	run.state = Run.State.PLAY
	run._hit_boss(run.boss.hp)
	run.step(1.0 / 60.0)
	for i in roundi(Run.CLEARED_SECONDS * 60.0) + 2:
		run.step(1.0 / 60.0)
	var on_to_dark: bool = run.state == Run.State.AIM and run.map_index == int(dark_maps[0]) and str(Maps.kingdom_of(run.map_index)["id"]) == "dark"
	# ---- the Shadow King ----
	run.begin(int(dark_maps[4]))
	var king = run.boss
	run.state = Run.State.PLAY
	run.light_lantern(Vector2(400, 200))
	king.snuff_t = 0.001
	king.step(0.01, true)
	var snuffed: bool = str(king.kind) == "shadowking" and run.lanterns.is_empty()
	run._hit_boss(Boss.SPLIT_EVERY)
	var young: bool = king.minions.size() == 1
	var plain: Dictionary = run.bricks.filter(func(k: Dictionary) -> bool: return str(k["kind"]) == "land" and int(k["hp"]) > 0 and k.has("cell"))[0]
	var lamp_brick: Dictionary = run.bricks.filter(func(k: Dictionary) -> bool: return str(k["kind"]) == "lantern" and int(k["hp"]) > 0)[0]
	young = young and bool(run.shade_at((plain["rect"] as Rect2).get_center())) and str(plain["kind"]) == "shadow" and int(plain["hp"]) == 2 \
		and not bool(run.shade_at((lamp_brick["rect"] as Rect2).get_center())) and str(lamp_brick["kind"]) == "lantern"
	run._hit_boss(Boss.SPLIT_EVERY * 2)
	var shades_before: int = count_of.call("shadow")
	for i in 60 * 20:
		king._step_minions(1.0 / 60.0, true)
	young = young and count_of.call("shadow") > shades_before
	# ---- the Wisp ----
	run.begin(int(dark_maps[9]))
	var wisp = run.boss
	run.state = Run.State.PLAY
	wisp.dim_t = 0.001
	wisp.step(0.01, true)
	var stolen: bool = str(wisp.kind) == "wisp" and run.light_stolen > 0.0
	# ---- the Shade Sniper ----
	run.begin(int(dark_maps[14]))
	var sniper = run.boss
	run.state = Run.State.PLAY
	run.paddle_x = 640.0
	run.target_x = 640.0
	sniper.snipe_t = 0.001
	for i in roundi((Boss.AIM_SECONDS + 0.2) * 60.0):
		sniper._snipe(1.0 / 60.0)
	var hexed_ok: bool = run.hexed > 0.0 and run.stunned == 0.0 and run.scorched == 0.0
	# ---- the Void Mage ----
	run.begin(int(dark_maps[19]))
	var mage = run.boss
	run.state = Run.State.PLAY
	var gone: int = 0
	for k in run.bricks:
		if gone < Boss.REBUILD_COUNT and k.has("cell") and int(k["hp"]) > 0 and run._breaks(k) and not run._guarded(k) \
				and str(k["kind"]) == "land" and (k["rect"] as Rect2).position.y > mage.hall.end.y + 40.0:
			run._damage(k, 99, null)
			gone += 1
	var shade_count: int = count_of.call("shadow")
	mage.rebuild_t = 0.001
	mage._ward_step(0.01)
	var mage_ok: bool = count_of.call("shadow") == shade_count + Boss.REBUILD_COUNT and mage.wards.size() == Boss.WARDS
	for k in run.bricks:
		if k.has("cell") and int(k["hp"]) > 0 and run._breaks(k) and not run._guarded(k) and str(k["kind"]) == "land" \
				and (k["rect"] as Rect2).position.y > mage.hall.end.y + 40.0:
			run._damage(k, 99, null)
			break
	var wells: int = run.voids.size()
	mage.void_t = 0.001
	mage.step(0.01, true)
	mage_ok = mage_ok and run.voids.size() == wells + 1 and (run.voids[-1]["rect"] as Rect2).position.y > mage.hall.end.y
	# ---- the Crowned Beholder, and the end ----
	run.begin(int(dark_maps[24]))
	var lord = run.boss
	run.state = Run.State.PLAY
	var last_ok: bool = lord.crowned and str(lord.title) == "The Crowned Beholder" and run.final_map()
	run.paddle_x = lord.p.x - 380.0
	run.target_x = run.paddle_x
	lord.gaze_t = 0.001
	lord._gaze(0.01)
	var gazing: bool = lord.gaze_warn > 0.0 and lord.gaze_left == 0.0
	lord._gaze(Boss.GAZE_WARN + 0.01)
	gazing = gazing and lord.gaze_left > 0.0 and run.stunned == 0.0
	var from_x: float = lord.gaze_x
	lord._gaze(0.5)
	gazing = gazing and absf(absf(lord.gaze_x - from_x) - Boss.GAZE_SPEED * 0.5) < 1.0 and run.stunned == 0.0
	for i in 60:
		lord._gaze(1.0 / 60.0)
	gazing = gazing and run.stunned > 0.0
	run.stunned = 0.0
	for i in 30:
		lord._gaze(1.0 / 60.0)
	gazing = gazing and run.stunned == 0.0
	@warning_ignore("integer_division")
	run._hit_boss(lord.hp - lord.most / 3 + 1)
	lord.eclipse_t = 0.001
	lord.step(0.01, true)
	last_ok = last_ok and run.blackout > 0.0 and lord.minions.size() > 0
	run._hit_boss(lord.hp)
	run.step(1.0 / 60.0)
	last_ok = last_ok and run.words.any(func(w: Dictionary) -> bool: return str(w["text"]) == "THE LAST CROWN FALLS!") \
		and run.words.any(func(w: Dictionary) -> bool: return str(w["text"]) == "Every land is healed.")
	for i in roundi(Run.CLEARED_SECONDS * 60.0) + 2:
		run.step(1.0 / 60.0)
	last_ok = last_ok and run.state == Run.State.OVER
	run.begin(int(dark_maps[0]) - 1)
	last_ok = last_ok and not run.final_map()
	# the screen says so at the end
	const Screen := preload("res://src/world/crownfall/crownfallscreen.gd")
	var screen: CanvasLayer = Screen.new()
	screen.set("pays", {"maps": []})
	screen.set("progress", Maps.made_count() - 1)
	screen.set("run_id", 0)
	screen.set("on_touch", func() -> bool: return false)
	add_child(screen)
	var srun: Node2D = screen.get("run")
	var finale: String = ""
	if srun != null:
		srun.set("running_by_clock", false)
		srun.begin(int(dark_maps[24]))
		srun.state = Run.State.PLAY
		srun._hit_boss(srun.boss.hp)
		for i in roundi(Run.CLEARED_SECONDS * 60.0) + 3:
			srun.step(1.0 / 60.0)
		screen.call("paint")
		finale = (screen.get("result_line") as Label).text
	screen.queue_free()
	last_ok = last_ok and finale == "The seventh crown is yours - every land is healed"
	check("  DARK'S BOSSES: the Inferno's fall leads on into the Kingdom of Dark; the Shadow King snuffs the last lantern and his young turn bricks to shadow (never a lantern); the Wisp steals the light; the Shade Sniper's shot hexes the paddle; the Void Mage rebuilds in shadow and opens a void well; the Crowned Beholder's gaze warns, then follows the paddle at %d px a second and stuns it once, his eclipse leaves only the balls' light, he splits - and his fall is THE LAST CROWN, every land healed, the end of the run, and the screen says the seventh crown is yours" % int(Boss.GAZE_SPEED),
		on_to_dark and snuffed and young and stolen and hexed_ok and mage_ok and gazing and last_ok,
		[on_to_dark, snuffed, young, stolen, hexed_ok, mage_ok, gazing, last_ok])
	print("  crownfall dark: done")


func _test_crownfall_powerups(run: Node2D) -> void:
	"""The five bonuses of 0.165.0: Magnet, Split, Big Ball, Extra Life and
	the Elemental Ball in each of its lands."""
	const Run := preload("res://src/world/crownfall/crownfallrun.gd")
	# ---- the Magnet ----
	_cf_bare(run)
	run.paddle_x = 640.0
	run.target_x = 640.0
	run.active = {"magnet": Run.BONUS["magnet"]["secs"]}
	var held: Dictionary = run._ball(Vector2(670, Run.PADDLE_Y - 30.0), Vector2(0, Run.SPEED))
	run.balls = [held]
	for i in 6:
		run._move(held, 1.0 / 60.0)
	var stuck: bool = held.has("stuck") and (held["v"] as Vector2) == Vector2.ZERO
	run.target_x = 600.0
	for i in 20:
		run.step(1.0 / 60.0)
	var rode: bool = stuck and absf((held["p"] as Vector2).x - (run.paddle_x + float(held["stuck"]))) < 0.5
	run.launch()
	var let_go: bool = not held.has("stuck") and (held["v"] as Vector2).y < 0.0 and (held["v"] as Vector2).x > 0.0
	held["stuck"] = 0.0
	held["stick_t"] = Run.MAGNET_HOLD
	held["v"] = Vector2.ZERO
	for i in roundi((Run.MAGNET_HOLD + 0.1) * 60.0):
		run.step(1.0 / 60.0)
	var by_itself: bool = not held.has("stuck") and (held["v"] as Vector2).length() > 0.0
	# ---- Split ----
	_cf_bare(run)
	run.active = {"split": 10.0}
	var splitter: Dictionary = run._ball(Vector2(640, 400), Vector2(0, -Run.SPEED))
	run.balls = [splitter]
	run._damage(run._add(10, 6, "land", "light", 1), 1, splitter)
	var split_ok: bool = run._new_balls.size() == 1
	run.balls = []
	for i in Run.MOST_BALLS:
		run.balls.append(run._ball(Vector2(640, 400), Vector2(0, -Run.SPEED)))
	run._new_balls.clear()
	run._damage(run._add(12, 6, "land", "light", 1), 1, run.balls[0])
	split_ok = split_ok and run._new_balls.is_empty()
	# ---- the Big Ball ----
	_cf_bare(run)
	run.active = {"big": 8.0}
	var round_it: Array = []
	for r in [5, 6, 7]:
		for c in [9, 10, 11]:
			round_it.append(run._add(c, r, "land", "light", 1))
	var big_ball: Dictionary = run._ball(run._cell(10, 7).get_center() + Vector2(0, 30), Vector2(0, -Run.SPEED))
	run.balls = [big_ball]
	for i in 12:
		run._move(big_ball, 1.0 / 60.0)
	var big_ok: bool = run.ball_r() == Run.BALL_R * Run.BIG_SIZE \
		and round_it.filter(func(k: Dictionary) -> bool: return int(k["hp"]) == 0).size() >= 6
	# ---- the Extra Life ----
	_cf_bare(run)
	run.lives = 3
	run._next_bonus = Run.LIFE_EVERY - 1
	run._drop(Vector2(640, 300))
	var life_ok: bool = str(run.caps[-1]["kind"]) == "life"
	run._take("life")
	life_ok = life_ok and run.lives == 4
	run.lives = Run.LIVES_MOST
	run._take("life")
	life_ok = life_ok and run.lives == Run.LIVES_MOST
	check("CROWNFALL'S NEW BONUSES: the Magnet holds a ball where it lands, carries it with the paddle and lets it go at a launch - or by itself after %ss; Split breaks a ball in two at each brick, %d balls at most; the Big Ball strikes the bricks round what it hits; every %dth bonus is an Extra Life, %d lives at most" % [str(Run.MAGNET_HOLD), Run.MOST_BALLS, Run.LIFE_EVERY, Run.LIVES_MOST],
		stuck and rode and let_go and by_itself and split_ok and big_ok and life_ok,
		[stuck, rode, let_go, by_itself, split_ok, big_ok, life_ok])
	# ---- the Elemental Ball ----
	_cf_bare(run)
	run._next_bonus = 2
	run._drop(Vector2(640, 300))
	var cap: Dictionary = run.caps[-1]
	var dropped: bool = str(cap["kind"]) == "element" and Run.ELEMENTS.has(str(cap.get("land", "")))
	var orb: Dictionary = run._ball(Vector2(640, 400), Vector2(0, -Run.SPEED))
	run.balls = [orb]
	cap["p"] = Vector2(run.paddle_x, Run.PADDLE_Y)
	run._capsules(0.0)
	var took: bool = run.element() == str(cap["land"]) and str(orb["el"]) == str(cap["land"])
	var by_land := func(land: String) -> Dictionary:
		_cf_bare(run)
		run.active = {"element": 12.0}
		run.ball_land = land
		var ball: Dictionary = run._ball(Vector2(640, 400), Vector2(0, -Run.SPEED))
		ball["el"] = land
		run.balls = [ball]
		return ball
	# a ball fresh from x3 Balls carries nothing: the land is still the Orb's
	var b: Dictionary = by_land.call("fire")
	b["el"] = ""
	var ice_brick: Dictionary = run._add(10, 6, "land", "ice", 1)
	run.words.clear()
	run._react_said = -1.0
	run._damage(ice_brick, 1, b)
	var kept: bool = str(b["el"]) == "fire" and run.words.any(func(w: Dictionary) -> bool: return str(w["text"]) == "STEAM!")
	b = by_land.call("fire")
	var beside: Dictionary = run._add(11, 6, "land", "light", 1)
	run._damage(run._add(10, 6, "land", "fire", 1), 1, b)
	var burnt: bool = float(beside["burn"]) >= 0.0
	b = by_land.call("water")
	var splashed: Dictionary = run._add(11, 6, "land", "light", 1)
	run._damage(run._add(10, 6, "land", "water", 1), 1, b)
	var wet: bool = int(splashed["hp"]) == 0
	b = by_land.call("ice")
	var cold: Dictionary = run._add(10, 6, "stone", "", 3)
	run._damage(cold, 1, b)
	var froze: bool = bool(cold.get("frozen", false)) and int(cold["hp"]) == 2
	b = by_land.call("earth")
	var rock: Dictionary = run._add(10, 6, "stone", "", 3)
	b["p"] = run._cell(10, 6).get_center() + Vector2(0, 26)
	for i in 12:
		run._move(b, 1.0 / 60.0)
	var heavy: bool = int(rock["hp"]) == 1
	b = by_land.call("light")
	run._add(10, 5, "guard", "light", 2)
	var guarded: Dictionary = run._add(11, 5, "land", "light", 1)
	var clam: Dictionary = run._add(14, 5, "clam", "water", 1)
	clam["phase"] = 0.0
	run.t = Run.CLAM_OPEN + 0.5
	run._damage(guarded, 1, b)
	run._damage(clam, 1, b)
	var bright: bool = int(guarded["hp"]) == 0 and int(clam["hp"]) == 0
	b = by_land.call("dark")
	run.combo = 0
	var doubled: bool = run._multiplier() == 2.0
	b = by_land.call("wind")
	run._add(20, 6, "land", "light", 1)
	b["p"] = Vector2(Run.FIELD_X + 10.0 * run.cw, 420.0)
	for i in 30:
		run._wind_ball(1.0 / 60.0)
	var curved: bool = (b["v"] as Vector2).x > 20.0
	check("  the Elemental Ball falls in a land of its own and the ball takes it; it keeps it, so each other land sets off their reaction; fire sets what is beside burning, water splashes it, ice freezes what it hits, earth hits twice as hard, light goes through a Guard's shield and finds a clam open, dark doubles the score, wind curves toward a brick",
		dropped and took and kept and burnt and wet and froze and heavy and bright and doubled and curved,
		[dropped, took, kept, burnt, wet, froze, heavy, bright, doubled, curved])
	run.active.clear()
	run.ball_land = ""
	print("  crownfall bonuses: done")


func _cf_bare(run: Node2D) -> void:
	"""Crownfall's checks: an empty 32-wide grid to set bricks on by hand -
	the map, its ball and boss gone, nothing in the footprint, the clock at
	nought, playing."""
	const Run := preload("res://src/world/crownfall/crownfallrun.gd")
	run._clear_map()
	run.cols = 32
	run.cw = Run.ARENA.size.x / 32.0
	run.ch = Run.CH
	run.gap = Run.ROW_GAP
	run.rows_count = 18
	run.t = 0.0
	run.state = Run.State.PLAY


func _test_crownfall() -> void:
	section("CROWNFALL (0.162.0): the kingdoms' maps, the play, the screen and the card")
	const Maps := preload("res://src/world/crownfall/crownfallmaps.gd")
	const Run := preload("res://src/world/crownfall/crownfallrun.gd")
	const Screen := preload("res://src/world/crownfall/crownfallscreen.gd")
	const Boss := preload("res://src/world/crownfall/crownfallboss.gd")
	const LETTERS := ".lawiefdSIMT?BHR1234567CUOKLGNZXYp<DWkuoQFPsVAEbgnhzJqrtmv"
	var bad_rows: Array = []
	for m in Maps.MAPS:
		var rows: Array = m["rows"]
		var wide: int = str(rows[0]).length()
		var odd: bool = not [Maps.COLS, Maps.BIG_COLS].has(wide) \
			or rows.size() > (Maps.ROWS_MOST if wide == Maps.COLS else Maps.BIG_ROWS_MOST)
		for r in rows:
			var row: String = r
			odd = odd or row.length() != wide
			for ch in row:
				odd = odd or not LETTERS.contains(ch)
		if odd:
			bad_rows.append(m["name"])
	var light: Array = Maps.maps_of("light")
	var bosses: Array = []
	var boss_kinds: bool = true
	for i in Maps.made_count():
		var info: Variant = Maps.MAPS[i].get("boss")
		if info is Dictionary:
			bosses.append(i)
			@warning_ignore("integer_division")
			var stretch: int = Maps.in_kingdom(i) / Maps.BOSS_EVERY
			boss_kinds = boss_kinds and str(info["kind"]) == str(Boss.KINDS_OF[str(Maps.MAPS[i]["kingdom"])][stretch]) \
				and bool(info.get("crown", false)) == (Maps.in_kingdom(i) == Maps.MAPS_A_KINGDOM - 1) \
				and "".join(Maps.MAPS[i]["rows"]).contains("R")
	var made: Array = Maps.KINGDOMS.filter(func(k: Dictionary) -> bool: return bool(k["made"]))
	var wind_maps: Array = Maps.maps_of("wind")
	var water_maps: Array = Maps.maps_of("water")
	var big_of := func(of: Array) -> int:
		return of.filter(func(i: int) -> bool: return str(Maps.MAPS[i]["rows"][0]).length() == Maps.BIG_COLS).size()
	var ice_maps: Array = Maps.maps_of("ice")
	var earth_maps: Array = Maps.maps_of("earth")
	var fire_maps: Array = Maps.maps_of("fire")
	var dark_maps: Array = Maps.maps_of("dark")
	var big_wind: int = big_of.call(wind_maps)
	var big_water: int = big_of.call(water_maps)
	var big_ice: int = big_of.call(ice_maps)
	var big_earth: int = big_of.call(earth_maps)
	var big_fire: int = big_of.call(fire_maps)
	var big_dark: int = big_of.call(dark_maps)
	check("the maps: Light's %d, Wind's %d (%d of them big), Water's %d (%d big), Ice's %d (%d big, every one), Earth's %d (%d big, every one), Fire's %d (%d big, every one) and Dark's %d (%d big, every one), every row %d letters of the legend (%d on a big map), at most %d rows (%d); seven kingdoms, all seven made; a boss on every %dth map (%s) in each kingdom's own order, the last crowned, each with a hall; the story told in %d lines" % [
		light.size(), wind_maps.size(), big_wind, water_maps.size(), big_water, ice_maps.size(), big_ice, earth_maps.size(), big_earth,
		fire_maps.size(), big_fire, dark_maps.size(), big_dark,
		Maps.COLS, Maps.BIG_COLS, Maps.ROWS_MOST, Maps.BIG_ROWS_MOST, Maps.BOSS_EVERY, bosses, Maps.STORY.size()],
		bad_rows.is_empty() and Maps.KINGDOMS.size() == 7 and made.size() == 7 and str(made[0]["id"]) == "light"
		and str(made[1]["id"]) == "wind" and str(made[2]["id"]) == "water" and str(made[3]["id"]) == "ice" and str(made[4]["id"]) == "earth"
		and str(made[5]["id"]) == "fire" and fire_maps.size() == Maps.MAPS_A_KINGDOM and big_fire == Maps.MAPS_A_KINGDOM
		and int(fire_maps[0]) == int(earth_maps[0]) + earth_maps.size()
		and str(made[6]["id"]) == "dark" and dark_maps.size() == Maps.MAPS_A_KINGDOM and big_dark == Maps.MAPS_A_KINGDOM
		and int(dark_maps[0]) == int(fire_maps[0]) + fire_maps.size() and Maps.made_count() == Maps.MAPS.size()
		and light.size() == Maps.MAPS_A_KINGDOM and wind_maps.size() == Maps.MAPS_A_KINGDOM and water_maps.size() == Maps.MAPS_A_KINGDOM
		and ice_maps.size() == Maps.MAPS_A_KINGDOM and earth_maps.size() == Maps.MAPS_A_KINGDOM
		and light.size() + wind_maps.size() + water_maps.size() + ice_maps.size() + earth_maps.size() + fire_maps.size() + dark_maps.size() == Maps.made_count()
		and big_wind >= 10 and big_water >= 10 and big_ice == Maps.MAPS_A_KINGDOM and big_earth == Maps.MAPS_A_KINGDOM
		and int(wind_maps[0]) == light.size() and int(water_maps[0]) == light.size() + wind_maps.size()
		and int(ice_maps[0]) == int(water_maps[0]) + water_maps.size() and int(earth_maps[0]) == int(ice_maps[0]) + ice_maps.size()
		and Maps.MAPS_A_KINGDOM == Maps.BOSS_EVERY * Maps.STRETCHES
		and bosses.size() == 7 * Maps.STRETCHES and bosses.all(func(i: int) -> bool: return (i + 1) % Maps.BOSS_EVERY == 0)
		and boss_kinds and Maps.STORY.size() == 5 and Maps.BOSS_SLOTS.size() == Maps.STRETCHES,
		[bad_rows, bosses, boss_kinds])
	var run: Node2D = Run.new()
	run.set("running_by_clock", false)
	add_child(run)
	run.rng.seed = 3
	run.pays = {"maps": [600, 600, 700, 800, 2000]}
	var told: Dictionary = {"cleared": [], "lost": 0, "over": 0}
	run.map_cleared.connect(func(i: int) -> void: (told["cleared"] as Array).append(i))
	run.life_lost.connect(func() -> void: told["lost"] = int(told["lost"]) + 1)
	run.run_over.connect(func() -> void: told["over"] = int(told["over"]) + 1)
	# ---- every map built ----
	var problems: Array = []
	var big: Array = []
	for i in Maps.made_count():
		run.begin(i)
		var m: Dictionary = Maps.MAPS[i]
		if run.cols == Maps.BIG_COLS:
			big.append(i)
		var outside: int = 0
		for k in run.bricks:
			var r: Rect2 = k["rect"]
			if k.has("rail"):
				outside += 0 if Run.ARENA.encloses(r) else 1
			elif r.position.x < Run.FIELD_X or r.end.x > Run.FIELD_X + Run.FIELD_W or r.position.y < Run.MAP_TOP:
				outside += 1
		var lanes_ok: bool = run.rails.size() >= 4 and run.gates().size() == 2
		for gate in run.gates():
			lanes_ok = lanes_ok and (gate as Vector2).y - (gate as Vector2).x >= Run.GATE_H - 0.5
		var portals: Array = run.bricks.filter(func(k: Dictionary) -> bool: return k["kind"] == "portal")
		var paired: int = portals.filter(func(k: Dictionary) -> bool: return k.has("to")).size()
		var wants_boss: bool = m.get("boss") is Dictionary
		var boss_ok: bool = not wants_boss or (run.boss != null and str(run.boss.kind) == str(m["boss"]["kind"])
			and run.hall.size.x >= 200.0 and Run.ARENA.encloses(run.hall))
		if run.breakable < 40 or outside > 0 or paired != portals.size() or not boss_ok or not lanes_ok \
				or run.field_bottom() > Run.PADDLE_Y - 200.0 or run.state != Run.State.AIM:
			problems.append([m["name"], run.breakable, outside, paired, portals.size(), boss_ok, lanes_ok, run.field_bottom()])
	run.begin(big[0] if not big.is_empty() else 0)
	var small_bricks: bool = run.cols == Maps.BIG_COLS and is_equal_approx(run.cw, Run.FIELD_W / Maps.BIG_COLS) \
		and run.ch < Run.CH
	var some: Dictionary = run.bricks.filter(func(k: Dictionary) -> bool: return k.has("cell") and run._breaks(k))[0]
	var at_some: Vector2 = (some["rect"] as Rect2).get_center()
	check("every map builds: its bricks inside the field and well over the paddle, a lane down each side railed in iron with two gates, its portals in pairs, its boss and hall; the %d big maps (%s) %d across, their smaller bricks found by the ball as any other" % [
		big.size(), big, Maps.BIG_COLS],
		problems.is_empty() and big.size() >= 1 and small_bricks and run._bricks_near(at_some).has(some)
		and run.cell_at(at_some) == some["cell"], problems)
	# ---- the kingdom map ----
	run.show_kingdoms(2)
	var row_two: Vector2 = run.map_spot(1)
	check("the kingdom map opens on the next map to clear: any map up to it may be started, none past it; a click on a map's node picks it",
		run.state == Run.State.KINGDOMS and run.selected == 2 and run.can_start_at(0) and run.can_start_at(2)
		and not run.can_start_at(3) and run.pick_at(row_two) == 1 and run.pick_at(Vector2(60, 60)) == -1)
	# ---- a map loaded from its letters ----
	run.begin(0)
	var want: int = 0
	var fixed: int = 0
	for r in (Maps.MAPS[0]["rows"] as Array):
		for ch in str(r):
			want += 1 if "lawiefdST?BD".contains(ch) else 0
			fixed += 1 if "IM".contains(ch) else 0
	var irons: int = run.bricks.filter(func(k: Dictionary) -> bool: return (k["kind"] == "mirror" or k["kind"] == "iron") and not k.has("rail")).size()
	check("a map is built from its rows: %d bricks to break (its %d iron and mirrors never count), the ball waiting on the paddle, three lives" % [run.breakable, irons],
		run.breakable == want and irons == fixed and fixed > 0 and run.state == Run.State.AIM and run.balls.size() == 1
		and run.lives == Run.LIVES and run.map_index == 0, [run.breakable, want, irons, fixed])
	# ---- a mirror bends the ball ----
	run.bricks.clear()
	run.cells.clear()
	var mirror: Dictionary = run._add(8, 4, "mirror", "light", 0)
	var under: Vector2 = (mirror["rect"] as Rect2).get_center() + Vector2(0, 40)
	run.balls = [run._ball(under, Vector2(0, -Run.SPEED))]
	run.state = Run.State.PLAY
	for i in 30:
		run.step(1.0 / 60.0)
		if (run.balls[0]["v"] as Vector2).y > 0.0:
			break
	var v: Vector2 = run.balls[0]["v"]
	var bend: float = rad_to_deg(absf(atan2(v.x, v.y)))
	check("  a mirror throws the ball back bent %d degrees (a plain bounce would be straight back), and never breaks" % roundi(bend),
		v.y > 0.0 and absf(bend - Run.MIRROR_BEND) < 1.0 and mirror["hp"] == 0 and run.bricks.has(mirror))
	var flat: Vector2 = Run.steady(Vector2(500, 3))
	check("  no ball runs flat along a row: at least %d%% of its speed goes up or down" % roundi(Run.STEEPEST_FLAT * 100.0),
		absf(flat.normalized().y) >= Run.STEEPEST_FLAT - 0.001 and is_equal_approx(flat.length(), Vector2(500, 3).length()))
	# ---- bricks: stone, earth, TNT ----
	run.bricks.clear()
	run.cells.clear()
	var stone: Dictionary = run._add(2, 2, "stone", "", 3)
	var earth: Dictionary = run._add(10, 2, "land", "earth", 2)
	var tnt: Dictionary = run._add(15, 2, "tnt", "fire", 1)
	var beside: Dictionary = run._add(16, 2, "land", "light", 1)
	run._damage(stone, 1, null)
	run._damage(stone, 1, null)
	var stone_stands: bool = stone["hp"] == 1
	run._damage(stone, 1, null)
	run._damage(earth, 1, null)
	var earth_stands: bool = earth["hp"] == 1
	run._damage(tnt, 1, null)
	check("  stone takes three hits, earth two; TNT goes off and takes what is beside it",
		stone_stands and stone["hp"] == 0 and earth_stands and tnt["hp"] == 0 and beside["hp"] == 0)
	# ---- the blight grows back ----
	run.begin(1)
	var blight: Dictionary = {}
	for k in run.bricks:
		if k["kind"] == "blight":
			blight = k
			break
	var spot: Vector2i = blight["cell"] + Vector2i(1, 0)
	var next_to: Dictionary = run.cells.get(spot, {})
	if not next_to.is_empty():
		run._damage(next_to, 99, null)
	var count_before: int = run.breakable
	run.balls.clear()
	run._blight(Run.BLIGHT_EVERY + 0.01)
	var regrown: Dictionary = run.cells.get(spot, {})
	var outside: bool = true
	for k in run.bricks:
		if k["kind"] == "blight" and k.has("cell"):
			outside = outside and run.footprint.has(k["cell"])
	check("the blight grows back into an empty cell beside it the map once held - never past the map's own shape - and must be broken too",
		not regrown.is_empty() and regrown["kind"] == "blight" and run.breakable > count_before and outside)
	run.begin(2)
	var heart: Dictionary = {}
	for k in run.bricks:
		if k["kind"] == "heart":
			heart = k
	var core_mid: Vector2 = (heart["rect"] as Rect2).get_center()
	var held: int = heart["hp"]
	run._damage(heart, 1, null)
	var core_guarded: bool = heart["hp"] == held and heart.has("warded")
	var guards_near: Array = run.bricks.filter(func(k: Dictionary) -> bool: return k["kind"] == "guard" and (k["rect"] as Rect2).get_center().distance_to(core_mid) < 60.0)
	for k in guards_near:
		run._damage(k, 2, null)
	var round_core: Array = []
	var hp_before: Array = []
	var far_brick: Dictionary = {}
	for k in run.bricks:
		if k["hp"] <= 0 or not run._breaks(k) or k["kind"] == "heart":
			continue
		var off: float = (k["rect"] as Rect2).get_center().distance_to(core_mid)
		if off < Run.CORE_BLAST:
			round_core.append(k)
			hp_before.append(int(k["hp"]))
		elif off > Run.CORE_BLAST + 60.0 and far_brick.is_empty():
			far_brick = k
	var far_hp: int = far_brick["hp"]
	var caps_before: int = run.caps.size()
	var four_cells: bool = not heart.is_empty() and (heart["cells"] as Array).size() == 4 \
		and run.cells.get(heart["cells"][0]) == heart and heart["hp"] == 6
	run._damage(heart, 6, null)
	var all_hit: bool = round_core.size() > 4
	for i in round_core.size():
		all_hit = all_hit and int(round_core[i]["hp"]) < int(hp_before[i])
	check("  the core is one brick over its four cells, each cell naming it, so the blight cannot grow into it; its four Guards keep it whole until they fall; shattered, its shockwave hits every brick within %d px (%d) and a bonus falls" % [
		roundi(Run.CORE_BLAST), round_core.size()],
		four_cells and heart["hp"] == 0 and all_hit and far_brick["hp"] == far_hp and run.caps.size() > caps_before
		and core_guarded and guards_near.size() == 4,
		[four_cells, all_hit, round_core.size(), far_brick["hp"], far_hp, core_guarded, guards_near.size()])
	# ---- the elements mixed ----
	var pairs_ok: bool = Run.reaction_of("ice", "fire") == "steam" and Run.reaction_of("wind", "fire") == "firestorm" \
		and Run.reaction_of("water", "ice") == "glacier" and Run.reaction_of("wind", "water") == "storm" \
		and Run.reaction_of("fire", "earth") == "magma" and Run.reaction_of("wind", "ice") == "blizzard" \
		and Run.reaction_of("dark", "light") == "eclipse" and Run.reaction_of("light", "fire") == "clash"
	_cf_bare(run)
	var fire_brick: Dictionary = run._add(2, 2, "land", "fire", 1)
	var ice_brick: Dictionary = run._add(10, 2, "land", "ice", 1)
	var by_ice: Dictionary = run._add(11, 2, "stone", "", 3)
	var carried: Dictionary = run._ball(Vector2(640, 400), Vector2(0, -Run.SPEED))
	run._damage(fire_brick, 1, carried)
	var took_fire: bool = str(carried.get("el", "")) == "fire"
	run._damage(ice_brick, 1, carried)
	check("the ball carries the land it breaks (fire); breaking another (ice) sets the two off - steam, two hits round it - and it carries the new one; seven pairs react, any other two clash",
		pairs_ok and took_fire and by_ice["hp"] == 1 and str(carried.get("el", "")) == "ice",
		[pairs_ok, took_fire, by_ice["hp"], carried.get("el")])
	var signs: Dictionary = {}
	_cf_bare(run)
	var spark: Dictionary = run._add(5, 4, "land", "light", 1)
	var in_row: Dictionary = run._add(5 + Run.FIRESTORM_REACH, 4, "land", "water", 1)
	var past_reach: Dictionary = run._add(6 + Run.FIRESTORM_REACH, 4, "land", "water", 1)
	var next_row: Dictionary = run._add(6, 6, "land", "water", 1)
	run._react("firestorm", spark, (spark["rect"] as Rect2).get_center())
	signs["firestorm"] = in_row["burn"] >= 0.0 and past_reach["burn"] < 0.0 and next_row["burn"] < 0.0
	_cf_bare(run)
	var pool: Dictionary = run._add(10, 5, "land", "water", 1)
	var cold: Array = [run._add(12, 5, "stone", "", 3), run._add(11, 6, "stone", "", 3), run._add(13, 5, "stone", "", 3)]
	run._react("glacier", pool, (pool["rect"] as Rect2).get_center())
	var froze: bool = bool(cold[0].get("frozen", false)) and bool(cold[1].get("frozen", false)) \
		and not bool(cold[2].get("frozen", false))
	run._damage(cold[0], 1, null)
	var at_a_touch: bool = cold[0]["hp"] == 0 and cold[1].has("shatter")
	run._bricks_move(Run.SHATTER_STEP + 0.01)
	signs["glacier"] = froze and at_a_touch and cold[1]["hp"] == 0 and cold[2]["hp"] == 3
	_cf_bare(run)
	var cloud: Dictionary = run._add(10, 5, "land", "wind", 1)
	var charged: Array = []
	for c in 4:
		charged.append(run._add(12 + c, 5, "stone", "", 3))
	var far_off: Dictionary = run._add(31, 17, "stone", "", 3)
	run._react("storm", cloud, (cloud["rect"] as Rect2).get_center())
	var jolted: int = charged.filter(func(k: Dictionary) -> bool: return k["hp"] < 3).size() + (1 if cloud["hp"] < 1 else 0)
	signs["storm"] = jolted == Run.STORM_JUMPS and run.zaps.size() == Run.STORM_JUMPS and far_off["hp"] == 3
	_cf_bare(run)
	var vent: Dictionary = run._add(10, 2, "land", "earth", 2)
	var under_vent: Array = [run._add(10, 4, "stone", "", 3), run._add(10, 6, "stone", "", 3)]
	var by_vent: Dictionary = run._add(11, 4, "stone", "", 3)
	run._react("magma", vent, (vent["rect"] as Rect2).get_center())
	for i in 60:
		run._bricks_move(1.0 / 60.0)
	signs["magma"] = under_vent[0]["hp"] == 2 and under_vent[1]["hp"] == 2 and by_vent["hp"] == 3 and run.drips.is_empty()
	_cf_bare(run)
	var frost: Dictionary = run._add(10, 8, "land", "ice", 1)
	var over_frost: Array = [run._add(10, 6, "stone", "", 3), run._add(10, 2, "stone", "", 3)]
	var under_frost: Dictionary = run._add(10, 10, "stone", "", 3)
	run._react("blizzard", frost, (frost["rect"] as Rect2).get_center())
	signs["blizzard"] = over_frost[0]["hp"] == 2 and over_frost[1]["hp"] == 2 and under_frost["hp"] == 3
	_cf_bare(run)
	var dusk: Dictionary = run._add(1, 1, "land", "dark", 1)
	var most_land: Array = []
	for c in Run.ECLIPSE_MOST + 4:
		most_land.append(run._add(2 + c, 3, "land", "water", 1))
	var fewer: Array = [run._add(2, 5, "land", "fire", 1), run._add(3, 5, "land", "fire", 1)]
	run._react("eclipse", dusk, (dusk["rect"] as Rect2).get_center())
	var dimmed: Array = most_land.filter(func(k: Dictionary) -> bool: return k["hp"] == 0)
	signs["eclipse"] = dimmed.size() == Run.ECLIPSE_MOST and dimmed == most_land.slice(0, Run.ECLIPSE_MOST) \
		and fewer.all(func(k: Dictionary) -> bool: return k["hp"] == 1)
	_cf_bare(run)
	var mixed: Dictionary = run._add(10, 5, "mix", "fire", 1)
	mixed["mix"] = "steam"
	var by_mix: Dictionary = run._add(11, 5, "stone", "", 3)
	run._damage(mixed, 1, run._ball(Vector2(640, 500), Vector2(0, -Run.SPEED)))
	var burnt_mix: Dictionary = run._add(20, 5, "mix", "fire", 1)
	burnt_mix["mix"] = "steam"
	var by_burnt: Dictionary = run._add(21, 5, "stone", "", 3)
	burnt_mix["burn"] = 0.01
	run._burns(0.02)
	signs["a mixed brick"] = by_mix["hp"] == 1 and burnt_mix["hp"] == 0 and by_burnt["hp"] == 3
	_cf_bare(run)
	var band: Array = []
	for c in 12:
		band.append(run._add(c, 8, "land", "fire", 1))
	run._damage(band[0], 1, null)
	for i in 40:
		run._burns(0.05)
	var burnt: int = band.filter(func(k: Dictionary) -> bool: return k["hp"] == 0).size()
	check("  each reaction does its own thing: a firestorm burns %d cells each way along its row, a glacier freezes round it (a frozen brick breaks at a touch, its frozen neighbours shatter after), a storm jumps to %d bricks, magma drips down its column, a blizzard shoots up it, an eclipse hits the %d nearest bricks of the land most left; a mixed brick goes off when the ball or a reaction breaks it, never a burn" % [
		Run.FIRESTORM_REACH, Run.STORM_JUMPS, Run.ECLIPSE_MOST],
		signs.size() == 7 and signs.values().all(func(v: bool) -> bool: return v), signs)
	check("  fire spreads to the fire touching it %d steps from where it caught, no further (a 48-wide band burnt down whole)" % Run.FIRE_SPREAD,
		burnt == Run.FIRE_SPREAD + 1, burnt)
	# ---- the new bricks ----
	_cf_bare(run)
	var gem: Dictionary = run._add(8, 3, "crystal", "ice", 1)
	var splitter: Dictionary = run._ball(Vector2(400, 300), Vector2(0, -Run.SPEED))
	run.balls = [splitter]
	run._damage(gem, 1, splitter)
	var twins: int = run._new_balls.size()
	var shell: Dictionary = run._add(3, 3, "shell", "", 1)
	run._damage(shell, 1, null)
	var hardened: bool = shell["kind"] == "stone" and shell["hp"] == 2
	var rune: Dictionary = run._add(5, 5, "rune", "light", 1)
	rune["phase"] = 0.0
	run.t = Run.RUNE_LIT + 0.5
	run._damage(rune, 1, null)
	var dark_held: bool = rune["hp"] == 1
	run.t = 0.1
	run._damage(rune, 1, null)
	var lit_broke: bool = rune["hp"] == 0
	var prism: Dictionary = run._add(7, 7, "prism", "light", 1)
	prism["phase"] = 0.0
	run.prisms.append(prism)
	run.t = 0.01
	run._bricks_move(0.0)
	var first_land: String = prism["land"]
	run.t = Run.PRISM_EVERY + 0.01
	run._bricks_move(0.0)
	var turned: bool = first_land == str(Run.ELEMENTS[0]) and prism["land"] == str(Run.ELEMENTS[1])
	var mimic: Dictionary = run._add(13, 9, "mimic", "", 1)
	var model: Dictionary = run._add(14, 9, "gold", "light", 2)
	run._damage(model, 2, null)
	var copied: bool = mimic["kind"] == "gold" and mimic["hp"] == 2
	check("a crystal splits the ball that breaks it; a shell hardens into stone; a rune breaks only while lit; a prism turns through the lands; a mimic becomes what broke beside it",
		twins == 1 and hardened and dark_held and lit_broke and turned and copied, [twins, hardened, dark_held, lit_broke, turned, copied])
	_cf_bare(run)
	var keys: Array = [run._add(2, 2, "key", "light", 1), run._add(20, 2, "key", "light", 1)]
	var lock: Dictionary = run._add(10, 4, "lock", "", 0)
	run.keys_left = 2
	run._damage(lock, 1, null)
	var lock_held: bool = lock["kind"] == "lock" and run.cells.has(Vector2i(10, 4))
	run._damage(keys[0], 1, null)
	var one_key_left: bool = lock["kind"] == "lock" and run.keys_left == 1
	run._damage(keys[1], 1, null)
	check("  a lock stands until every key is broken, then every lock opens",
		lock_held and one_key_left and lock["kind"] == "opened" and not run.cells.has(Vector2i(10, 4)))
	_cf_bare(run)
	var bumper: Dictionary = run._add(10, 6, "bumper", "light", 0)
	var kicked: Dictionary = run._ball((bumper["rect"] as Rect2).get_center() + Vector2(4, 30), Vector2(0, -Run.SPEED))
	for i in 20:
		run._move(kicked, 1.0 / 60.0)
		if (kicked["v"] as Vector2).y > 0.0:
			break
	var kick: float = (kicked["v"] as Vector2).length()
	var portal_a: Dictionary = run._add(5, 10, "portal", "dark", 0)
	var portal_b: Dictionary = run._add(25, 3, "portal", "dark", 0)
	portal_a["to"] = portal_b
	portal_b["to"] = portal_a
	var traveller: Dictionary = run._ball((portal_a["rect"] as Rect2).get_center() + Vector2(0, 30), Vector2(0, -Run.SPEED))
	var went: bool = false
	for i in 20:
		run._move(traveller, 1.0 / 60.0)
		if float(traveller.get("portal_t", 0.0)) > 0.0:
			went = true
			break
	var came_out: float = (traveller["p"] as Vector2).distance_to((portal_b["rect"] as Rect2).get_center())
	check("  a bumper kicks the ball off its middle, %d%% the speed, and never breaks; a portal sends it out of its pair the way it was going" % roundi(Run.BUMPER_KICK * 100.0),
		(kicked["v"] as Vector2).y > 0.0 and absf(kick - Run.SPEED * Run.BUMPER_KICK) < 1.0 and run.cells.get(Vector2i(10, 6)) == bumper
		and went and came_out < 40.0 and (traveller["v"] as Vector2).y < 0.0, [kick, went, came_out])
	_cf_bare(run)
	var sick: Dictionary = run._add(5, 5, "blight", "", 1)
	var healthy: Dictionary = run._add(6, 5, "land", "light", 1)
	var tries: int = 0
	while healthy["kind"] == "land" and tries < 30:
		run._blight(Run.BLIGHT_EVERY + 0.01)
		tries += 1
	check("  with no room to grow, the blight corrupts a land brick beside it into plague-stone, two hits",
		healthy["kind"] == "plague" and healthy["hp"] == 2 and sick["hp"] == 1 and run.cells.size() == 2, [healthy["kind"], tries])
	run.begin(15)
	var drifter: Dictionary = run.movers[0]
	for k in run.movers:
		if float(k["hi"]) - float(k["lo"]) > float(drifter["hi"]) - float(drifter["lo"]):
			drifter = k
	var x_was: float = (drifter["rect"] as Rect2).position.x
	var x_most: float = x_was
	var x_least: float = x_was
	for i in 120:
		run.t += 1.0 / 30.0
		run._bricks_move(0.0)
		x_most = maxf(x_most, (drifter["rect"] as Rect2).position.x)
		x_least = minf(x_least, (drifter["rect"] as Rect2).position.x)
	var home: float = float(drifter["home"])
	check("  drifters slide along their row into the room beside them and no further, off the grid, and the ball still finds them",
		x_most - x_least > 20.0 and x_least >= home + float(drifter["lo"]) - 0.01 and x_most <= home + float(drifter["hi"]) + 0.01
		and not run.cells.values().has(drifter) and run._bricks_near((drifter["rect"] as Rect2).get_center()).has(drifter),
		[x_least, x_most, home, drifter["lo"], drifter["hi"]])
	_cf_bare(run)
	run._add(2, 2, "land", "light", 1)
	run.breakable = 1
	var chaser: Dictionary = run._ball(Vector2(640, 500), Vector2(0, -Run.SPEED))
	run.balls = [chaser]
	run._pull(0.1)
	var turned_by: float = rad_to_deg(Vector2(0, -1).angle_to(chaser["v"]))
	check("  the last %d bricks call the ball: a rising ball turns toward the nearest, %d degrees a second" % [Run.PULL_BELOW, roundi(Run.PULL_TURN)],
		run.pulling and absf(turned_by + Run.PULL_TURN * 0.1) < 0.1, turned_by)
	# ---- the side lanes ----
	_cf_bare(run)
	run._make_rails(0)
	var lane_gates: Array = run.gates()
	var lane_x: float = Run.ARENA.position.x + (Run.SIDE_GAP - Run.RAIL_W) / 2.0
	var walled: Dictionary = run._ball(Vector2(lane_x, (lane_gates[1] as Vector2).x - 14.0), Vector2(0.5, -0.87) * Run.SPEED)
	var turned_back: bool = false
	for i in 5:
		run._move(walled, 1.0 / 60.0)
		turned_back = turned_back or (walled["v"] as Vector2).x < 0.0
	var kept_in: bool = turned_back and (walled["p"] as Vector2).x < Run.FIELD_X - Run.RAIL_W
	var gate_mid: float = ((lane_gates[0] as Vector2).x + (lane_gates[0] as Vector2).y) / 2.0
	var through: Dictionary = run._ball(Vector2(lane_x, gate_mid), Vector2(0.96, -0.28) * Run.SPEED)
	for i in 6:
		run._move(through, 1.0 / 60.0)
	check("  a lane down each side, railed in iron: a ball in it comes back off the rail, and one aimed through a gate gets in",
		lane_gates.size() == 2 and kept_in and (through["p"] as Vector2).x > Run.FIELD_X + 5.0 and (through["v"] as Vector2).x > 0.0,
		[lane_gates, kept_in, through["p"]])
	# ---- the Guard ----
	_cf_bare(run)
	var warden: Dictionary = run._add(10, 5, "guard", "light", 2)
	var shielded: Dictionary = run._add(11, 6, "stone", "", 3)
	var open_brick: Dictionary = run._add(13, 5, "stone", "", 3)
	var second_guard: Dictionary = run._add(9, 5, "guard", "light", 2)
	run._damage(shielded, 1, null)
	run._damage(open_brick, 1, null)
	var glanced: bool = shielded["hp"] == 3 and shielded.has("warded") and open_brick["hp"] == 2
	run._damage(second_guard, 2, null)
	var guard_breaks: bool = second_guard["hp"] == 0
	run._damage(warden, 1, null)
	run._damage(shielded, 1, null)
	var still_held: bool = warden["hp"] == 1 and shielded["hp"] == 3
	run._damage(warden, 1, null)
	run._damage(shielded, 1, null)
	_cf_bare(run)
	var ring_guard: Dictionary = run._add(10, 5, "guard", "light", 2)
	# a ring open below, so a ball can get to the Guard (one shut in on every
	# side takes the blows instead - _test_crownfall_never_locked())
	for d in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0)]:
		run._add(10 + d.x, 5 + d.y, "land", "light", 1)
	run._add(25, 3, "land", "light", 1)
	run.breakable = run.bricks.size()
	run.balls = [run._ball(Vector2(640, 500), Vector2(0, -Run.SPEED))]
	run._pull(0.1)
	var calls_open: bool = run.pulling
	check("  a Guard takes two hits, and while it stands the bricks touching it take none (the blow glances off); a Guard beside a Guard still breaks; the last bricks' pull counts only what can be hurt (%d standing, 2 open)" % run.breakable,
		glanced and guard_breaks and still_held and warden["hp"] == 0 and shielded["hp"] == 2 and calls_open and ring_guard["hp"] == 2,
		[glanced, guard_breaks, still_held, warden["hp"], shielded["hp"], calls_open])
	# ---- a life lost, a map cleared, the next map ----
	run.show_kingdoms(0)
	run.begin(0)
	run.state = Run.State.PLAY
	run.balls.clear()
	run.step(1.0 / 60.0)
	var after_one: bool = run.lives == Run.LIVES - 1 and run.state == Run.State.AIM and run.balls.size() == 1 \
		and int(told["lost"]) == 1
	for first in [true, false]:
		for k in run.bricks:
			if run._breaks(k) and k["hp"] > 0 and (k["kind"] == "guard") == first:
				run._damage(k, 99, null)
	run.state = Run.State.PLAY
	run.step(1.0 / 60.0)
	var cleared_now: bool = run.state == Run.State.CLEARED and run.cleared == 1 and run.gold_now() == 600 \
		and told["cleared"] == [0]
	for i in roundi(Run.CLEARED_SECONDS * 60.0) + 2:
		run.step(1.0 / 60.0)
	check("a ball lost is a life, the ball back on the paddle; every brick broken clears the map and pays its gold; then the next map",
		after_one and cleared_now and run.state == Run.State.AIM and run.map_index == 1 and run.furthest == 1,
		[after_one, cleared_now, run.state, run.map_index, run.furthest])
	run.lives = 1
	run.state = Run.State.PLAY
	run.balls.clear()
	run.step(1.0 / 60.0)
	check("  the last life lost, the run is over", run.state == Run.State.OVER and int(told["over"]) == 1)
	# ---- the Slime King ----
	run.begin(4)
	var king = run.boss
	var has_boss: bool = king != null and king.hp == run.breakable - run.broken and king.most == king.hp and run.hall.size.x > 300.0 \
		and str(king.title) == "The Slime King" and not king.crowned
	var king_art: bool = king.sprite != null and king.sprite.sprite_frames != null
	var hall_cells: Dictionary = run.cells.duplicate()
	run.cells.clear()
	var struck_ball: Dictionary = run._ball(king.p + Vector2(0, (king.body_rect() as Rect2).size.y / 2.0 + Run.BALL_R + 2.0), Vector2(0, -Run.SPEED))
	run._move(struck_ball, 1.0 / 60.0)
	var ball_took: int = king.most - king.hp
	run.bolts = [{"p": king.p + Vector2(0, 30), "from": king.p + Vector2(0, 30)}]
	run._lasers(1.0 / 60.0)
	var laser_took: int = king.most - king.hp - ball_took
	var pressed: Dictionary = run._ball(king.p, Vector2(0, -Run.SPEED))
	var before_press: int = king.hp
	run._move(pressed, 1.0 / 60.0)
	var press_took: int = before_press - king.hp
	run.cells = hall_cells
	check("a boss's health is its field - the Slime King's %d bricks - and a ball strikes it for %d, a laser for 1, and a ball pressed into it counts once" % [
		int(king.most), Run.BALL_HIT],
		ball_took == Run.BALL_HIT and laser_took == 1 and press_took == Run.BALL_HIT
		and (struck_ball["v"] as Vector2).y > 0.0 and king.most == run.boss_base,
		[ball_took, laser_took, press_took])
	king.hits_since_split = 0
	run.state = Run.State.PLAY
	for i in roundi(Boss.THROW_EVERY * 60.0) + 5:
		run.step(1.0 / 60.0)
	var threw: bool = king.shots.size() >= 1
	king.shots = [{"p": Vector2(run.paddle_x, Run.PADDLE_Y), "v": Vector2(0, 10)}]
	run.step(1.0 / 60.0)
	var stunned: bool = run.stunned > 0.0
	var before_split: int = king.hp
	run._hit_boss(Boss.SPLIT_EVERY)
	var split: bool = king.minions.size() == 1 and king.hp == before_split - Boss.SPLIT_EVERY
	var empty_spot: Vector2 = Vector2.INF
	for row in range(int(run.rows_count) - 1, 0, -1):
		for col in run.cols:
			if empty_spot == Vector2.INF and not run.cells.has(Vector2i(col, row)) \
					and not run.hall.grow(2.0).intersects(run._cell(col, row)):
				empty_spot = run._cell(col, row).get_center()
	var was: int = run.breakable
	run.plant_blight(empty_spot)
	run.plant_blight(run.hall.get_center())
	var planted: bool = run.breakable == was + 1 and run.cells.get(run.cell_at(empty_spot), {}).get("kind") == "blight"
	var slain: int = king.ball_touch((king.minions[0] as Dictionary)["p"], Run.BALL_R)
	run._hit_boss(king.hp)
	var crumbling: int = run.bricks.filter(func(k: Dictionary) -> bool: return k.has("crumble")).size()
	run.step(1.0 / 60.0)
	var won: bool = run.state == Run.State.CLEARED
	for i in roundi(Run.CLEARED_SECONDS * 60.0) - 3:
		run.step(1.0 / 60.0)
	var left_standing: int = run.bricks.filter(func(k: Dictionary) -> bool: return run._breaks(k) and k["hp"] > 0).size()
	for i in 5:
		run.step(1.0 / 60.0)
	check("the Slime King walks his hall and throws at the paddle, a hit stunning it; every %d damage (five ball hits) he splits, and his young plant blight where they land (never in his hall) - the ball kills one; brought down, his walls crumble (%d), and on to the next map" % [
		Boss.SPLIT_EVERY, crumbling],
		has_boss and threw and stunned and split and planted and slain == 1 and won and crumbling > 50 and left_standing == 0
		and run.state == Run.State.AIM and run.map_index == 5 and run.boss == null and king.sprite == null,
		[has_boss, threw, stunned, split, planted, slain, won, crumbling, left_standing, run.map_index])
	check_needs_pack("  the Slime King is his own art, recoloured light", king_art)
	# ---- the Sprite ----
	run.begin(9)
	var sprite_boss = run.boss
	run.state = Run.State.PLAY
	run.target_x = run.paddle_x
	var from_spot: Vector2 = sprite_boss.p
	var in_hall: bool = true
	var sparks: int = 0
	var blinked: bool = false
	var last_blink: float = sprite_boss.blink_t
	var quiet: bool = true
	var never_stunned: bool = true
	for i in roundi((Boss.BLINK_EVERY * 3.0 + 0.1) * 60.0):
		run.step(1.0 / 60.0)
		in_hall = in_hall and run.hall.grow(2.0).has_point(sprite_boss.p)
		sparks = maxi(sparks, sprite_boss.shots.size())
		if sprite_boss.blink_t > last_blink:
			blinked = true
			quiet = quiet and sprite_boss.throw_t >= Boss.BLINK_QUIET - 0.02
		last_blink = sprite_boss.blink_t
		never_stunned = never_stunned and run.stunned <= 0.0
	check("the Sprite darts about its hall and never leaves it, blinks to a new spot every %.1f s and then throws nothing for %.1f s, and throws its sparks in a fan of %d (0.168.9: \"this boss is firing shots to fast\") - a paddle standing still in the middle lane is never hit" % [Boss.BLINK_EVERY, Boss.BLINK_QUIET, Boss.SPARK_FAN.size()],
		str(sprite_boss.kind) == "sprite" and sprite_boss.hp == run.boss_left() and in_hall and blinked and quiet
		and sparks >= 4 and Boss.SPARK_FAN.size() == 4 and never_stunned
		and sprite_boss.p != from_spot, [in_hall, blinked, quiet, sparks, never_stunned])
	# ---- the Sniper ----
	run.begin(14)
	var sniper = run.boss
	run.state = Run.State.PLAY
	run.target_x = run.paddle_x
	var aimed_at: float = -1.0
	var beamed: bool = false
	var stun_seen: bool = false
	for i in roundi((Boss.SNIPE_EVERY + Boss.AIM_SECONDS + 0.2) * 60.0):
		run.step(1.0 / 60.0)
		if sniper.aim_left > 0.0 and aimed_at < 0.0:
			aimed_at = sniper.beam_x
		beamed = beamed or sniper.beam_left > 0.0
		stun_seen = stun_seen or run.stunned > 0.0
	var stood_under: bool = absf(aimed_at - run.paddle_x) < 1.0 and beamed and stun_seen
	for i in 30:
		run.step(1.0 / 60.0)
	run.stunned = 0.0
	var dodged_aim: bool = false
	var stun_after: bool = false
	for i in roundi((Boss.SNIPE_EVERY + Boss.AIM_SECONDS + Boss.BEAM_SECONDS + 0.2) * 60.0):
		if sniper.aim_left > 0.0 and not dodged_aim:
			dodged_aim = true
			run.target_x = Run.ARENA.position.x + 80.0 if sniper.beam_x > 640.0 else Run.ARENA.end.x - 80.0
		run.step(1.0 / 60.0)
		stun_after = stun_after or run.stunned > 0.0
	check("the Sniper marks the paddle's column, waits %.1f s, then fires down it: the paddle left under it is stunned, the paddle moved out of it is not" % Boss.AIM_SECONDS,
		str(sniper.kind) == "sniper" and stood_under and dodged_aim and not stun_after, [aimed_at, beamed, stun_seen, dodged_aim, stun_after])
	# ---- the Bush Mage ----
	run.begin(19)
	var mage = run.boss
	var lowest: int = 0
	for i in mage.wards.size():
		if mage.ward_at(i).y > mage.ward_at(lowest).y:
			lowest = i
	var ward_spot: Vector2 = mage.ward_at(lowest)
	var broke_ward: bool = mage.ward_touch(ward_spot, Run.BALL_R) == ward_spot and float(mage.wards[lowest]["back"]) == Boss.WARD_BACK
	var gone_now: bool = mage.ward_touch(ward_spot, Run.BALL_R) == Vector2.INF
	mage.wards[lowest]["back"] = 0.0
	var kept_cells: Dictionary = run.cells.duplicate()
	run.cells.clear()
	var met: Dictionary = run._ball(ward_spot + Vector2(0, 12), Vector2(0, -Run.SPEED))
	run._move(met, 1.0 / 60.0)
	var bounced: bool = (met["v"] as Vector2).y > 0.0 and float(mage.wards[lowest]["back"]) > 0.0
	run.cells = kept_cells
	var foot: Vector2 = Vector2(run.hall.get_center().x, run.hall.end.y)
	var by_hall: Array = run.bricks.filter(func(k: Dictionary) -> bool: return k.has("cell") and run._breaks(k) and k["hp"] > 0 and not run._guarded(k))
	by_hall.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["rect"] as Rect2).get_center().distance_to(foot) < (b["rect"] as Rect2).get_center().distance_to(foot))
	for k in by_hall.slice(0, 5):
		run._damage(k, 99, null)
	var before_rebuild: int = run.breakable
	mage._ward_step(Boss.REBUILD_EVERY + 0.01)
	check("the Bush Mage's %d wards throw the ball back and break, growing back in %d s; every %d s he rebuilds the %d broken cells nearest his hall, in stone" % [
		Boss.WARDS, roundi(Boss.WARD_BACK), roundi(Boss.REBUILD_EVERY), Boss.REBUILD_COUNT],
		str(mage.kind) == "mage" and mage.wards.size() == Boss.WARDS and broke_ward and gone_now and bounced
		and run.breakable == before_rebuild + Boss.REBUILD_COUNT, [broke_ward, gone_now, bounced, run.breakable - before_rebuild])
	# ---- the Dawn Warden ----
	run.begin(int(light[-1]))
	var ruler = run.boss
	var crowned_now: bool = ruler.crowned and str(ruler.title) == "The Dawn Warden" and ruler.hp == run.boss_left()
	@warning_ignore("integer_division")
	run._hit_boss(ruler.most / 3 - 1)
	var none_yet: bool = ruler.minions.is_empty() and ruler.hp * 3 > ruler.most * 2
	run._hit_boss(Boss.RULER_SPLIT_EVERY)
	var one_split: bool = ruler.minions.size() == 1
	run._hit_boss(2 * Boss.RULER_SPLIT_EVERY)
	var three_split: bool = ruler.minions.size() == 3
	@warning_ignore("integer_division")
	run._hit_boss(ruler.hp - ruler.most / 3 + 1)
	three_split = three_split and ruler.hp * 3 < ruler.most
	run.state = Run.State.PLAY
	run.target_x = run.paddle_x
	var ruler_aimed: bool = false
	for i in roundi((Boss.SNIPE_EVERY + 0.1) * 60.0):
		run.step(1.0 / 60.0)
		ruler_aimed = ruler_aimed or ruler.aim_left > 0.0
	run._hit_boss(ruler.hp)
	var crown_words: bool = run.words.any(func(w: Dictionary) -> bool: return str(w["text"]) == "THE CROWN FALLS!")
	run.step(1.0 / 60.0)
	var crown_won: bool = run.state == Run.State.CLEARED and ruler.minions.is_empty()
	for i in roundi(Run.CLEARED_SECONDS * 60.0) + 2:
		run.step(1.0 / 60.0)
	check("the Dawn Warden wears the crown: past a third of his health gone he splits every %d damage, past two thirds he snipes too; brought down, THE CROWN FALLS and the run goes on into the Kingdom of Wind" % Boss.RULER_SPLIT_EVERY,
		crowned_now and none_yet and one_split and three_split and ruler_aimed and crown_words and crown_won
		and run.state == Run.State.AIM and run.map_index == int(wind_maps[0]) and str(Maps.kingdom_of(run.map_index)["id"]) == "wind",
		[crowned_now, none_yet, one_split, three_split, ruler_aimed, crown_words, crown_won, run.state, run.map_index])
	await _test_crownfall_wind(run, wind_maps)
	await _test_crownfall_water(run, water_maps)
	_test_crownfall_ice(run, ice_maps)
	_test_crownfall_earth(run, earth_maps)
	_test_crownfall_fire(run, fire_maps)
	_test_crownfall_dark(run, dark_maps)
	_test_crownfall_powerups(run)
	# ---- words never land on words ----
	run.begin(0)
	run.words.clear()
	run.paddle_x = Run.ARENA.end.x - 60.0
	for kind in ["shield", "multi", "laser"]:
		run._take(kind)
	var rects: Array = []
	for w in run.words:
		rects.append(Run._word_rect(w["p"], run._word_width(w["text"], int(w["size"])), int(w["size"])))
	var apart: bool = rects.size() >= 3
	for i in rects.size():
		var r: Rect2 = rects[i]
		apart = apart and r.position.x >= Run.ARENA.position.x and r.end.x <= Run.ARENA.end.x
		for j in range(i + 1, rects.size()):
			apart = apart and not r.intersects(rects[j])
	check("three bonuses caught at once by the right wall say so in three words, none on another and all inside the arena (the owner: \"SHIELD and 3 BALLS! stack right on top of each other\")",
		apart, rects)
	run.queue_free()
	# ---- the screen ----
	var finished: Array = []
	var screen: CanvasLayer = Screen.new()
	screen.set("pays", {"maps": [600, 600, 700, 800, 2000]})
	screen.set("progress", 1)
	screen.set("run_id", 9)
	screen.set("on_touch", func() -> bool: return false)
	screen.set("finish_request", func(path: String, body: Dictionary, _t: float = 0.0) -> Dictionary:
		finished.append([path, body])
		return {"ok": true, "status": 200, "data": {"gold": 0, "cleared": 0, "progress": 1, "held_back": 0, "status": {}}})
	add_child(screen)
	await get_tree().process_frame
	var srun: Node2D = screen.get("run")
	srun.set("running_by_clock", false)
	var opened_on_map: bool = srun.state == Run.State.KINGDOMS and srun.selected == 1 \
		and (screen.get("start_button") as Button).visible and not screen.call("tells_story") \
		and str(srun.get("map_hint")).contains("Enter / Space")
	screen.call("step_pick", 1)
	var held_at_open: bool = srun.selected == 1
	screen.call("step_pick", -1)
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	screen.call("_key", key)
	var begun: bool = srun.state == Run.State.AIM and srun.start_index == 0
	screen.call("paint")
	var start_gone: bool = not (screen.get("start_button") as Button).visible
	screen.call("_key", key)
	var launched: bool = srun.state == Run.State.PLAY
	screen.call("ask_to_leave")
	await get_tree().process_frame
	var still: bool = is_instance_valid(screen) and screen.is_inside_tree() and finished.is_empty()
	screen.call("ask_to_leave")
	for i in 3:
		await get_tree().process_frame
	check("the screen opens on the kingdom map at the next map to clear (no story without a HUD), the keys' prompt under it; up and down pick only open maps, Space starts and launches; Leave asks twice in a run, then finishes it on the server from the map it began on and goes",
		opened_on_map and held_at_open and begun and start_gone and launched and still and finished.size() == 1
		and str(finished[0][0]) == "/api/minigames/finish" and finished[0][1] == {"run": 9, "from": 0, "cleared": 0}
		and not is_instance_valid(screen), [opened_on_map, held_at_open, begun, start_gone, launched, still, finished])
	# ---- the card ----
	var was_owner: bool = Api.is_owner
	Api.is_owner = true
	var card_hud := Control.new()
	add_child(card_hud)
	var card = (load("res://src/ui/minigames/minigamescard.gd") as GDScript).call("attach", card_hud)
	card.set("area_now", func() -> String: return "elusion")
	card.set("class_now", func() -> String: return "warrior")
	card.set("list_request", func(_p: String, _t: float = 0.0) -> Dictionary:
		return {"ok": true, "data": {"games": [{"id": "crownfall", "plays_left": 2, "ready_in": 0, "progress": 3}]}})
	var asked: Array = []
	card.set("enter_request", func(path: String, body: Dictionary, _t: float = 0.0) -> Dictionary:
		asked.append([path, body])
		return {"ok": true, "status": 200, "data": {"run": 41, "plays_left": 1, "pays": {"maps": [6, 7]}, "progress": 3}})
	var opened: Array = []
	card.set("open_crownfall", func(run_on_server: int, what: Dictionary, how_far: int) -> void:
		opened.append([run_on_server, what, how_far]))
	card.call("open")
	await get_tree().process_frame
	await get_tree().process_frame
	var tagged: bool = card.crown_box.find_children("tag", "Label", true, false).any(
		func(l: Label) -> bool: return l.text == "TESTING")
	var said: String = card.crown_status.text
	var portrait: Array = card.crown_box.find_children("*", "TextureRect", true, false)
	await card.call("_on_crown_go")
	check("the owner's Minigames card has Crownfall's tile, marked TESTING, the Slime King its portrait, saying \"%s\"; Go asks the server for a run and opens it with what each map pays and how far you got" % said,
		card.crown_box.visible and tagged and portrait.size() == 1 and said.contains("2 of 3 runs") and said.contains("3 of %d maps" % Maps.made_count())
		and asked.size() == 1 and asked[0][1].get("game") == "crownfall" and opened.size() == 1
		and int(opened[0][0]) == 41 and (opened[0][1] as Dictionary).has("maps") and int(opened[0][2]) == 3,
		[said, asked, opened])
	Api.is_owner = was_owner
	card_hud.queue_free()
	await get_tree().process_frame
	print("  crownfall: done")


# Where each of Crownfall's test fingers is on the window (index -> Vector2).
var _cf_at: Dictionary = {}


func _cf_finger(screen: CanvasLayer, index: int, at: Vector2, down: bool) -> void:
	"""Crownfall's phone checks: a finger put down or lifted at `at` on the
	window."""
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.position = at
	touch.pressed = down
	if down:
		_cf_at[index] = at
	else:
		_cf_at.erase(index)
	screen.call("_input", touch)


func _cf_slide(screen: CanvasLayer, index: int, by_x: float) -> void:
	"""A finger slid by `by_x` px on the window: its position and its
	relative both, as a phone sends them."""
	var from: Vector2 = _cf_at.get(index, Vector2.ZERO)
	var drag := InputEventScreenDrag.new()
	drag.index = index
	drag.position = from + Vector2(by_x, 0.0)
	drag.relative = Vector2(by_x, 0.0)
	_cf_at[index] = drag.position
	screen.call("_input", drag)


func _test_crownfall_on_a_phone() -> void:
	section("CROWNFALL ON A PHONE (0.166.0): the slider, a tap on the field, the slower aim and tracer")
	const Run := preload("res://src/world/crownfall/crownfallrun.gd")
	const Screen := preload("res://src/world/crownfall/crownfallscreen.gd")
	var screen: CanvasLayer = Screen.new()
	screen.set("pays", {"maps": []})
	screen.set("progress", 1)
	screen.set("run_id", 0)
	screen.set("on_touch", func() -> bool: return true)
	add_child(screen)
	await get_tree().process_frame
	var srun: Node2D = screen.get("run")
	srun.set("running_by_clock", false)
	var box: Rect2 = screen.call("drawn_rect")
	var fit: float = box.size.x / Run.VIEW.x
	# ---- the kingdom map: a tap still picks ----
	var spot: Vector2 = box.position + srun.map_spot(0) * fit
	_cf_finger(screen, 0, spot, true)
	_cf_finger(screen, 0, spot, false)
	var picked: bool = srun.selected == 0 and srun.state == Run.State.KINGDOMS
	screen.call("begin")
	screen.call("paint")
	var told: bool = srun.touch_slider and str(srun.launch_hint) == "Tap the field to launch"
	# ---- the slider: a thumb left of the field ----
	var thumb: Vector2 = box.position + Vector2(70, 610) * fit
	_cf_finger(screen, 0, thumb, true)
	var from: float = srun.target_x
	_cf_slide(screen, 0, 20.0 * fit)
	var slid: float = srun.target_x - from
	var slider_ok: bool = is_equal_approx(slid, 20.0 * Screen.SLIDER_GAIN) and srun.state == Run.State.AIM
	# a second thumb on the left takes the slider (0.166.3: the newest); the
	# first then moves nothing
	_cf_finger(screen, 7, box.position + Vector2(40, 300) * fit, true)
	var before_other: float = srun.target_x
	_cf_slide(screen, 7, 25.0 * fit)
	var newest: bool = is_equal_approx(srun.target_x, before_other + 25.0 * Screen.SLIDER_GAIN)
	var before_old: float = srun.target_x
	_cf_slide(screen, 0, 25.0 * fit)
	var old_still: bool = srun.target_x == before_old
	_cf_finger(screen, 7, box.position + Vector2(40, 300) * fit, false)
	_cf_finger(screen, 0, thumb, false)
	# while the ball waits a finger on the field slides the paddle and does
	# not launch; a tap launches on its lift
	var field: Vector2 = box.position + Vector2(640, 420) * fit
	_cf_finger(screen, 1, field, true)
	var not_on_press: bool = srun.state == Run.State.AIM
	var held: float = srun.target_x
	_cf_slide(screen, 1, 30.0 * fit)
	var field_slides: bool = is_equal_approx(srun.target_x, held + 30.0 * Screen.SLIDER_GAIN)
	_cf_finger(screen, 1, field, false)
	var slide_no_launch: bool = srun.state == Run.State.AIM
	_cf_finger(screen, 1, field, true)
	_cf_finger(screen, 1, field, false)
	var launched: bool = srun.state == Run.State.PLAY
	# in flight a thumb on the slider and a finger on the field both slide
	_cf_finger(screen, 0, thumb, true)
	_cf_finger(screen, 2, field, true)
	var both_from: float = srun.target_x
	_cf_slide(screen, 0, -10.0 * fit)
	_cf_slide(screen, 2, -5.0 * fit)
	var both: bool = is_equal_approx(srun.target_x, both_from - 15.0 * Screen.SLIDER_GAIN)
	_cf_finger(screen, 2, field, false)
	# far to the left in real steps (0.166.4: one leap past a quarter of the
	# field in a single drag moves nothing)
	for i in 40:
		_cf_slide(screen, 0, -60.0 * fit)
	var clamped: bool = srun.target_x == Run.ARENA.position.x
	_cf_finger(screen, 0, thumb, false)
	_cf_slide(screen, 0, 50.0 * fit)
	var let_go: bool = srun.target_x == Run.ARENA.position.x
	check("on a phone a thumb landing left of the field is the slider: it moves the paddle %dx as far as it slides (%.0f for 20), wherever it goes, held to the arena; the newest thumb there takes it from the last; while the ball waits a finger on the field slides the paddle and does not launch, and a tap launches on its lift; in flight a thumb and a finger both slide; lifted, the slider lets go; on the kingdom map a tap still picks; the waiting ball says \"Tap the field to launch\"" % [int(Screen.SLIDER_GAIN), slid],
		fit > 0.0 and picked and told and slider_ok and newest and old_still and not_on_press and field_slides and slide_no_launch and launched and both and clamped and let_go,
		[fit, picked, told, slid, newest, old_still, not_on_press, field_slides, slide_no_launch, launched, both, clamped, let_go])
	# ---- the Laser: a tap fires it ----
	srun.active = {"laser": 10.0}
	srun.bolts = []
	srun._laser_t = 0.0
	for i in 30:
		srun._lasers(1.0 / 60.0)
	var quiet: bool = srun.bolts.is_empty()
	_cf_finger(screen, 2, field, true)
	var volley: bool = srun.bolts.size() == 2
	_cf_finger(screen, 2, field, false)
	_cf_finger(screen, 3, field, true)
	var waits: bool = srun.bolts.size() == 2
	_cf_finger(screen, 3, field, false)
	for i in roundi(Run.LASER_EVERY * 60.0) + 1:
		srun._lasers(1.0 / 60.0)
	var n: int = srun.bolts.size()
	_cf_finger(screen, 4, field, true)
	var again: bool = srun.bolts.size() == n + 2
	_cf_finger(screen, 4, field, false)
	# the Magnet's ball let go by a tap
	var ball: Dictionary = srun.balls[0]
	ball["stuck"] = 0.0
	ball["v"] = Vector2.ZERO
	_cf_finger(screen, 5, field, true)
	var magnet_waits: bool = ball.has("stuck")
	_cf_finger(screen, 5, field, false)
	var magnet_let_go: bool = magnet_waits and not ball.has("stuck") and ball["v"] != Vector2.ZERO
	# a computer: by itself, as before
	srun.touch_slider = false
	srun.bolts = []
	srun._laser_t = 0.0
	srun._lasers(1.0 / 60.0)
	var pc_fires: bool = srun.bolts.size() == 2
	# the tap that launches only launches
	srun.begin(0)
	srun.touch_slider = true
	srun.active = {"laser": 10.0}
	srun.bolts = []
	srun._laser_t = 0.0
	_cf_finger(screen, 6, field, true)
	_cf_finger(screen, 6, field, false)
	var launch_only: bool = srun.state == Run.State.PLAY and srun.bolts.is_empty()
	check("on a phone the Laser never fires by itself: a tap on the field fires a volley, another within %.2f s nothing, one after it the next; the tap that launches only launches; a tap lets go of a ball the Magnet holds, on its lift; on a computer the Laser fires by itself as before" % Run.LASER_EVERY,
		quiet and volley and waits and again and launch_only and magnet_let_go and pc_fires,
		[quiet, volley, waits, again, launch_only, magnet_let_go, pc_fires])
	# ---- the aim and the tracer, slower ----
	srun.begin(0)
	srun.t = 0.0
	srun.step(0.5)
	var swayed_to: float = srun.aim
	var sway_ok: bool = srun.state == Run.State.AIM and is_equal_approx(swayed_to, deg_to_rad(-90.0 + Run.AIM_SWAY * sin(0.5 * 0.8)))
	var src: String = (load("res://src/world/crownfall/crownfallrun.gd") as GDScript).source_code
	var tracer_at: int = src.find("func _draw_tracer(")
	var tracer: String = src.substr(tracer_at, src.find("\nfunc ", tracer_at + 10) - tracer_at)
	var tracer_ok: bool = Run.TRACER_SPEED <= 500.0 and tracer.contains("fmod(t * TRACER_SPEED, spacing)")
	check("the waiting ball's aim sways half as fast as it did (the owner: \"it sways left and right to fast\"), and a tracer's streaks run at %d px a second, a third of what they did (\"the tracer is too fast also\")" % int(Run.TRACER_SPEED),
		sway_ok and tracer_ok, [rad_to_deg(swayed_to), tracer_ok])
	screen.queue_free()
	await get_tree().process_frame
	print("  crownfall on a phone: done")


# =============================================================================
# CROWNFALL DRAWS LESS (0.166.1)
# =============================================================================
# The owner: "fireball and multiball make the map lag", "the layer of effects
# made it lag", "the last few bricks are hard to destroy", "had a brick travel
# up all the steel wall". Every brick was drawn again every frame; now each is
# a picture of its own, drawn again when its look changes (crownfallrun.gd,
# THE BRICKS DRAW ONCE). Sparks are fewer, the last few glow and draw the
# ball, and a buoy floats two cells at most.

func _test_crownfall_draws_less() -> void:
	section("Crownfall draws less (0.166.1): the bricks once, fewer sparks, the last few, the buoy")
	const Run := preload("res://src/world/crownfall/crownfallrun.gd")
	var run: Node2D = Run.new()
	run.set("running_by_clock", false)
	add_child(run)
	# ---- the bricks draw once ----
	run.rng.seed = 7
	run.begin(54)
	run.sync_bricks()
	var first: int = run.redrawn
	var bricks_in: int = run.bricks.filter(func(k: Dictionary) -> bool: return not k.has("rail")).size()
	run.sync_bricks()
	var again: int = run.redrawn
	run.sync_bricks()
	again += run.redrawn
	var lively: int = run.bricks.filter(func(k: Dictionary) -> bool: return int(k["hp"]) > 0 and not k.has("rail") \
		and not Run.STILL_KINDS.has(k["kind"])).size()
	check("THE BRICKS DRAW ONCE: a picture each, all drawn at first; then only what moves is drawn again - over two frames each once",
		first == bricks_in and run.brick_layer.get_child_count() == bricks_in and again == lively,
		[first, bricks_in, run.brick_layer.get_child_count(), again, lively])
	var plain: Dictionary = {}
	for k in run.bricks:
		if k["kind"] == "land" and int(k["hp"]) > 0:
			plain = k
			break
	plain["flash"] = 1.0
	run.sync_bricks()
	var struck: bool = int(plain["look"]) == -1 and run.redrawn >= 1
	plain["flash"] = 0.0
	run.sync_bricks()
	run.sync_bricks()
	struck = struck and int(plain["look"]) >= 0
	plain["frozen"] = true
	run.sync_bricks()
	run.sync_bricks()
	var coat: int = int(plain["look"])
	plain.erase("frozen")
	run.sync_bricks()
	run.sync_bricks()
	var thawed: bool = coat != int(plain["look"])
	plain["hp"] = 0
	run.sync_bricks()
	var hidden: bool = not (plain["node"] as Node2D).visible
	check("  a brick struck is drawn again at once and goes back to still; frozen and thawed it is drawn again; broken, hidden",
		struck and thawed and hidden, [struck, thawed, hidden])
	var src: String = _code_src("res://src/world/crownfall/crownfallrun.gd")
	var own: String = _func_body(src, "func _draw() -> void:")
	check("  the floor, the stone they are set in, the floor over it, then the bricks (the still ones one picture, 0.166.2, the rest over it), all behind the run's own drawing - which draws no brick",
		run.floor_layer.show_behind_parent and run.building_layer.show_behind_parent and run.floor_top.show_behind_parent
		and run.brick_pic.show_behind_parent and run.brick_live.show_behind_parent
		and run.floor_layer.get_index() < run.building_layer.get_index() and run.building_layer.get_index() < run.floor_top.get_index()
		and run.floor_top.get_index() < run.brick_pic.get_index() and run.brick_pic.get_index() < run.brick_live.get_index()
		and run.brick_layer.get_parent() == run.brick_cache
		and not own.contains("_draw_brick_in") and not own.contains("for k in bricks"))
	run.begin(16)
	run.sync_bricks()
	await get_tree().process_frame
	var new_in: int = run.bricks.filter(func(k: Dictionary) -> bool: return not k.has("rail")).size()
	check("  a new map's bricks get pictures of their own and the old map's are let go",
		run.brick_layer.get_child_count() == new_in, [run.brick_layer.get_child_count(), new_in])
	# ---- sparks ----
	run.parts.clear()
	for i in 40:
		run._burst(Vector2(640, 300), Color.WHITE, 40, 200.0)
	var thrown: int = run.parts.size()
	run._effects(0.001)
	check("SPARKS: with the air half full a burst throws a third as many, and no more than %d stay" % Run.PARTS_MOST,
		thrown < 40 * 40 / 2 and run.parts.size() <= Run.PARTS_MOST, [thrown, run.parts.size()])
	# ---- the last few ----
	_cf_bare(run)
	run.breakable = 3
	run.broken = 0
	var far: Dictionary = run._add(28, 2, "land", "light", 1)
	run._add(28, 3, "land", "light", 1)
	run._add(28, 4, "land", "light", 1)
	run.balls.append(run._ball(Vector2(200, 500), Vector2(0, -560)))
	var was: float = (run.balls[0]["v"] as Vector2).angle()
	for i in 30:
		run._wind_ball(1.0 / 60.0)
	var turned: float = (run.balls[0]["v"] as Vector2).angle() - was
	check("THE LAST FEW: with %d or fewer left they glow and every ball bends toward the nearest" % Run.LAST_FEW,
		run.last_few() and turned > 0.2 and run._brick_look(far, true) == -1, [run.last_few(), turned])
	run.breakable = 50
	var own_way: bool = not run.last_few() and not run.seeking()
	run._since_break = Run.STUCK_SECONDS
	var stuck: bool = run.seeking()
	run._damage(far, 1, null)
	check("  with many left the balls go their own way - until none has broken for %ds; a break starts the count again" % int(Run.STUCK_SECONDS),
		own_way and stuck and not run.seeking(), [own_way, stuck, run.seeking()])
	# ---- the buoy ----
	_cf_bare(run)
	for r in range(2, 9):
		run.footprint[Vector2i(5, r)] = true
	var buoy: Dictionary = run._add(5, 8, "buoy", "water", 1)
	run.buoys.append(buoy)
	for i in 240:
		run._waters(1.0 / 60.0)
	check("A BUOY floats %d cells at most, however many holes are above it (it climbed a whole iron column)" % Run.BUOY_MOST,
		buoy["cell"] == Vector2i(5, 8 - Run.BUOY_MOST), buoy["cell"])
	run.queue_free()
	await get_tree().process_frame
	print("  crownfall draws less: done")


func _test_crownfall_never_locked() -> void:
	section("Crownfall is never locked (0.166.2): a Guard shut in, the shield cracks, the balls aim at what breaks, the walls crumble, drawn lighter")
	const Run := preload("res://src/world/crownfall/crownfallrun.gd")
	const Screen := preload("res://src/world/crownfall/crownfallscreen.gd")
	var run: Node2D = Run.new()
	run.set("running_by_clock", false)
	add_child(run)
	# ---- Gilded Gate, as the owner left it: a Guard in the middle of its own nine ----
	run.rng.seed = 7
	run.begin(0)
	var gate_guards: Array = run.bricks.filter(func(k: Dictionary) -> bool: return k["kind"] == "guard")
	var all_shut: bool = gate_guards.size() == 4 and gate_guards.all(func(k: Dictionary) -> bool: return not run._reachable(k))
	var keep: Dictionary = {}
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			keep[Vector2i(13 + dx, 5 + dy)] = true
	run._crumbling = true
	for k in run.bricks.duplicate():
		if k.has("cell") and not keep.has(k["cell"]) and int(k["hp"]) > 0 and run._breaks(k):
			run._damage(k, 99, null)
	run._crumbling = false
	var guard: Dictionary = run.cells[Vector2i(13, 5)]
	var below: Dictionary = run.cells[Vector2i(13, 6)]
	var nine: bool = run.breakable - run.broken == 9
	var shut_in: bool = not run._reachable(guard) and run._reachable(below) and run._shut_guard(below) == guard
	var below_hp: int = below["hp"]
	run._damage(below, 1, null)
	var through: bool = int(below["hp"]) == below_hp and int(guard["hp"]) == 1 and below.has("warded")
	run._damage(below, 1, null)
	var fell: bool = int(guard["hp"]) == 0
	run._damage(below, 1, null)
	var then_breaks: bool = int(below["hp"]) == 0
	check("A GUARD SHUT IN: Gilded Gate's four Guards have every side a brick they shield; a blow on one of those goes through to the Guard, which falls in two - then they break",
		all_shut and nine and shut_in and through and fell and then_breaks,
		[all_shut, gate_guards.size(), nine, run.breakable - run.broken, shut_in, through, fell, then_breaks])
	# ---- a Guard a ball can get to: the blow glances, and every third cracks the shield ----
	_cf_bare(run)
	var open_guard: Dictionary = run._add(10, 5, "guard", "light", 2)
	var beside: Dictionary = run._add(11, 5, "land", "light", 1)
	run._damage(beside, 1, null)
	run._damage(beside, 1, null)
	var two_glance: bool = int(beside["hp"]) == 1 and int(open_guard["hp"]) == 2 and run._reachable(open_guard) and run._guarded(beside)
	run._damage(beside, 1, null)
	var cracked: bool = int(open_guard["hp"]) == 1 and int(beside["hp"]) == 1
	for i in Run.GUARD_GLANCES:
		run._damage(beside, 1, null)
	var shield_gone: bool = int(open_guard["hp"]) == 0
	run._damage(beside, 1, null)
	check("THE SHIELD CRACKS: a Guard a ball can reach still turns the blow aside - but every %d glancing blows give it a hit of its own, so a shield never locks a map" % Run.GUARD_GLANCES,
		two_glance and cracked and shield_gone and int(beside["hp"]) == 0, [two_glance, cracked, shield_gone, beside["hp"]])
	# ---- what the seeking balls aim at ----
	_cf_bare(run)
	run.t = Run.RUNE_LIT + 0.1
	var aimed: Dictionary = run._add(10, 5, "guard", "light", 2)
	run._add(11, 5, "land", "light", 1)
	run._add(20, 5, "land", "light", 1)
	var rune: Dictionary = run._add(25, 5, "rune", "light", 1)
	run._add(5, 5, "iron", "", 1)
	var aims: Array = run._seek_targets()
	var guard_first: bool = aims.size() == 1 and aims[0] == aimed
	run._damage(aimed, 99, null)
	aims = run._seek_targets()
	var then_open: bool = aims.size() == 2 and not aims.has(rune) and aims.all(func(k: Dictionary) -> bool: return k["kind"] == "land")
	_cf_bare(run)
	var ringed: Dictionary = run._add(10, 5, "guard", "light", 2)
	for d in Run.DIRS4:
		run._add(10 + d.x, 5 + d.y, "land", "light", 1)
	run.breakable = 5
	run.broken = 0
	run.balls = [run._ball(Vector2(400, 600), Vector2(0, -560))]
	run._wind_ball(1.0 / 60.0)
	var seek: Vector2 = run.balls[0].get("seek", Vector2.INF)
	var not_shut: bool = run.last_few() and seek != Vector2.INF and seek != (ringed["rect"] as Rect2).get_center() \
		and run._brick_look(ringed, true) != -1
	check("THE BALLS AIM AT WHAT BREAKS: a Guard a ball can reach first, never a shielded brick, a dark rune or iron - and never a Guard shut in, nor does it glow",
		guard_first and then_open and not_shut, [guard_first, then_open, aims.size(), not_shut, seek])
	# ---- the way in, and the walls that crumble ----
	_cf_bare(run)
	var top: Dictionary = run._add(5, 0, "land", "light", 1)
	for c in [Vector2i(5, 1), Vector2i(4, 0), Vector2i(6, 0)]:
		run._add(c.x, c.y, "iron", "", 1)
	var over_top: bool = run._reachable(top)
	_cf_bare(run)
	var boxed: Dictionary = run._add(10, 5, "land", "light", 1)
	for d in Run.DIRS4:
		run._add(10 + d.x, 5 + d.y, "iron", "", 1)
	run.breakable = 1
	run.broken = 0
	run.balls = [run._ball(Vector2(640, 600), Vector2(0, -400))]
	var unreached: bool = not run._reachable(boxed) and run.seeking()
	for i in roundi(Run.CRUMBLE_AFTER / Run.CRUMBLE_LOOK) - 1:
		run._walls_crumble(Run.CRUMBLE_LOOK)
	var waited: bool = int(boxed["hp"]) == 1
	for i in 2:
		run._walls_crumble(Run.CRUMBLE_LOOK)
	var crumbled: bool = int(boxed["hp"]) == 0 and run.broken == run.breakable
	check("THE WAY IN: a brick under the arena's top is reached over the rows; one boxed in iron is not - and with nothing left a ball can reach and hurt, after %ds the walls crumble and the map can be cleared" % int(Run.CRUMBLE_AFTER),
		over_top and unreached and waited and crumbled, [over_top, unreached, waited, crumbled])
	# ---- drawn lighter: the stone once a map, the still bricks one picture ----
	run.begin(0)
	run._process(1.0 / 60.0)
	var stone_key: int = run._building_key
	run._process(1.0 / 60.0)
	var stone_kept: bool = run._building_key == stone_key
	run.begin(1)
	run._process(1.0 / 60.0)
	var stone_new: bool = run._building_key != stone_key
	var floor_src: String = _func_body(_code_src("res://src/world/crownfall/crownfallrun.gd"), "func _paint_floor() -> void:")
	var plain: Dictionary = {}
	for k in run.bricks:
		if k["kind"] == "land" and int(k["hp"]) > 0:
			plain = k
			break
	run.sync_bricks()
	run.sync_bricks()
	# a map's bricks are painted a few at a time since 0.168.8: all in first
	while not run._unpainted.is_empty():
		run.sync_bricks()
	run.brick_cache.render_target_update_mode = SubViewport.UPDATE_DISABLED
	run.sync_bricks()
	run.sync_bricks()
	var quiet: bool = run.brick_cache.render_target_update_mode == SubViewport.UPDATE_DISABLED
	plain["flash"] = 1.0
	run.sync_bricks()
	var twin: bool = plain.has("twin") and (plain["twin"] as Node2D).visible and (plain["node"] as Node2D).visible \
		and run.brick_cache.render_target_update_mode == SubViewport.UPDATE_DISABLED
	plain["flash"] = 0.0
	run.sync_bricks()
	run.sync_bricks()
	var back: bool = (plain["node"] as Node2D).visible and not (plain["twin"] as Node2D).visible \
		and run.brick_cache.render_target_update_mode == SubViewport.UPDATE_DISABLED
	plain["hp"] = 0
	run.sync_bricks()
	var gone: bool = not (plain["node"] as Node2D).visible and run.brick_cache.render_target_update_mode == SubViewport.UPDATE_ONCE
	var premult: bool = (run.brick_pic.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	check("DRAWN LIGHTER: the stone the bricks are set in is drawn once a map, not every frame; the still bricks are one picture, drawn again only when one changes - a struck brick's twin flashes over it without drawing the picture again, and a broken one leaves it",
		stone_kept and stone_new and not floor_src.contains("_draw_building") and quiet and twin and back and gone and premult,
		[stone_kept, stone_new, quiet, twin, back, gone, premult])
	run.queue_free()
	# ---- the town is not drawn under the screen ----
	var screen: CanvasLayer = Screen.new()
	var town := Node2D.new()
	add_child(town)
	screen.cover(town)
	var hidden: bool = not town.visible
	screen.uncover()
	var shown: bool = town.visible
	var a_node := Node.new()
	screen.cover(a_node)
	var left_alone: bool = screen.get("_covered") == null
	screen.free()
	town.queue_free()
	a_node.free()
	check("THE TOWN UNDER IT: while the screen is up the town is not drawn, and shown again when it goes; a scene that does not draw is left alone",
		hidden and shown and left_alone, [hidden, shown, left_alone])
	await get_tree().process_frame
	print("  crownfall never locked: done")


# =============================================================================
# CROWNFALL'S SLIDER NEVER STICKS (0.166.3)
# =============================================================================
# The owner: "the move slider is not working out on mobile ... it is working
# but it is easy for it to stop working". The slider let go of its thumb
# only on that thumb's own lift; a lift that never came (off the screen's
# edge, a notification, a system swipe) held it dead, and a new thumb took
# nothing. And only a thumb that landed left of the field moved the paddle.
# Now the newest thumb takes the slider, every finger is forgotten when a
# run starts or ends, the game loses focus or is paused, or the screen
# hides, and a finger anywhere on the field slides the paddle (its tap on
# its lift while a ball waits, at once while one flies).

func _test_crownfall_slider_never_sticks() -> void:
	section("CROWNFALL'S SLIDER NEVER STICKS (0.166.3, 0.166.4): the newest thumb, fingers forgotten, a drag anywhere, each finger by its own step")
	const Run := preload("res://src/world/crownfall/crownfallrun.gd")
	const Screen := preload("res://src/world/crownfall/crownfallscreen.gd")
	var screen: CanvasLayer = Screen.new()
	screen.set("pays", {"maps": []})
	screen.set("progress", 1)
	screen.set("run_id", 0)
	screen.set("on_touch", func() -> bool: return true)
	add_child(screen)
	await get_tree().process_frame
	var srun: Node2D = screen.get("run")
	srun.set("running_by_clock", false)
	var box: Rect2 = screen.call("drawn_rect")
	var fit: float = box.size.x / Run.VIEW.x
	var thumb: Vector2 = box.position + Vector2(70, 610) * fit
	var field: Vector2 = box.position + Vector2(640, 420) * fit
	srun.selected = 0
	screen.call("begin")
	# a thumb whose lift never comes, then another: the new one moves the paddle
	_cf_finger(screen, 0, thumb, true)
	_cf_finger(screen, 3, thumb, true)
	var from: float = srun.target_x
	_cf_slide(screen, 3, 20.0 * fit)
	var newest_moves: bool = is_equal_approx(srun.target_x, from + 20.0 * Screen.SLIDER_GAIN)
	_cf_finger(screen, 3, thumb, false)
	# losing focus, a window's focus, a pause: every finger forgotten
	var forgets: Array = []
	for what in [Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT,
			Node.NOTIFICATION_APPLICATION_PAUSED]:
		_cf_finger(screen, 0, thumb, true)
		_cf_finger(screen, 4, field, true)
		screen.notification(what)
		forgets.append(int(screen.get("_slider_finger")) == -1 and (screen.get("_field_fingers") as Dictionary).is_empty())
	var focus_ok: bool = forgets == [true, true, true]
	# the screen hidden: forgotten
	_cf_finger(screen, 0, thumb, true)
	screen.visible = false
	var hidden_ok: bool = int(screen.get("_slider_finger")) == -1
	screen.visible = true
	# a run ending under a thumb: forgotten
	_cf_finger(screen, 0, thumb, true)
	screen.call("_process", 1.0 / 60.0)
	srun.state = Run.State.OVER
	screen.call("_process", 1.0 / 60.0)
	var end_ok: bool = int(screen.get("_slider_finger")) == -1
	# a run starting under a finger: forgotten
	screen.call("start")
	srun = screen.get("run")
	srun.set("running_by_clock", false)
	srun.selected = 0
	_cf_finger(screen, 5, box.position + srun.map_spot(0) * fit, true)
	var held_before: bool = int(screen.get("_finger")) == 5
	screen.call("begin")
	var start_ok: bool = held_before and int(screen.get("_finger")) == -1 and srun.state == Run.State.AIM
	check("a thumb whose lift never came cannot hold the slider: the newest thumb left of the field takes it and moves the paddle; every finger is forgotten when the game loses focus, its window's focus or is paused, when the screen hides, when a run ends and when one starts",
		newest_moves and focus_ok and hidden_ok and end_ok and start_ok,
		[newest_moves, forgets, hidden_ok, end_ok, held_before, start_ok])
	# drag anywhere: a finger on the field slides the paddle, wherever it landed
	_cf_finger(screen, 1, field, true)
	var aim_press: bool = srun.state == Run.State.AIM
	var at: float = srun.target_x
	_cf_slide(screen, 1, 18.0 * fit)
	var drag_moves: bool = is_equal_approx(srun.target_x, at + 18.0 * Screen.SLIDER_GAIN)
	_cf_finger(screen, 1, field, false)
	var drag_no_launch: bool = srun.state == Run.State.AIM
	# a tap while aiming: nothing on the press, the launch on the lift
	_cf_finger(screen, 2, field, true)
	var still_aiming: bool = srun.state == Run.State.AIM
	_cf_finger(screen, 2, field, false)
	var launched_on_lift: bool = srun.state == Run.State.PLAY
	# in flight a press taps at once: the Laser's volley before any lift
	srun.active = {"laser": 10.0}
	srun.bolts = []
	srun._laser_t = 0.0
	_cf_finger(screen, 6, field, true)
	var volley_at_once: bool = srun.bolts.size() == 2
	var fly_from: float = srun.target_x
	_cf_slide(screen, 6, -12.0 * fit)
	var fly_slides: bool = is_equal_approx(srun.target_x, fly_from - 12.0 * Screen.SLIDER_GAIN)
	_cf_finger(screen, 6, field, false)
	var no_second: bool = srun.bolts.size() == 2
	check("a finger anywhere on the field slides the paddle %dx as far as it moves; while the ball waits its press launches nothing, a slide never launches, and a tap launches on its lift; while a ball flies a press taps at once (the Laser's volley) and the same finger slides the paddle, its lift taps no more" % int(Screen.SLIDER_GAIN),
		aim_press and drag_moves and drag_no_launch and still_aiming and launched_on_lift and volley_at_once and fly_slides and no_second,
		[aim_press, drag_moves, drag_no_launch, still_aiming, launched_on_lift, volley_at_once, fly_slides, no_second])
	# EACH FINGER BY ITS OWN STEP (0.166.4): the web build can hand the
	# thumb's drag a relative from another finger to it; the paddle goes by
	# the thumb's own positions, and a leap past a quarter of the field
	# moves nothing
	var left_x: float = Run.ARENA.position.x
	var right_x: float = Run.ARENA.end.x
	screen.call("_process", 1.0 / 60.0)
	srun.target_x = (left_x + right_x) / 2.0
	_cf_finger(screen, 7, thumb, true)
	_cf_finger(screen, 8, field, true)
	var before: float = srun.target_x
	var leap := InputEventScreenDrag.new()
	leap.index = 7
	leap.position = thumb + Vector2(6.0, 0.0)
	leap.relative = Vector2(-700.0, 0.0)
	_cf_at[7] = leap.position
	screen.call("_input", leap)
	var want: float = clampf(before + 6.0 / fit * Screen.SLIDER_GAIN, left_x, right_x)
	var own_step: bool = absf(srun.target_x - want) < 0.01 and srun.target_x > before
	var at_tap: float = srun.target_x
	var bogus := InputEventScreenDrag.new()
	bogus.index = 8
	bogus.position = field + Vector2(-4.0, 0.0)
	bogus.relative = Vector2(900.0, 0.0)
	_cf_at[8] = bogus.position
	screen.call("_input", bogus)
	var tap_own: bool = absf(srun.target_x - clampf(at_tap - 4.0 / fit * Screen.SLIDER_GAIN, left_x, right_x)) < 0.01
	var at_jump: float = srun.target_x
	var jump := InputEventScreenDrag.new()
	jump.index = 7
	jump.position = (_cf_at[7] as Vector2) + Vector2(Run.ARENA.size.x * 0.5 * fit, 0.0)
	jump.relative = Vector2(Run.ARENA.size.x * 0.5 * fit, 0.0)
	_cf_at[7] = jump.position
	screen.call("_input", jump)
	var leap_ignored: bool = is_equal_approx(srun.target_x, at_jump)
	_cf_slide(screen, 7, 5.0)
	var after_leap: bool = absf(srun.target_x - clampf(at_jump + 5.0 / fit * Screen.SLIDER_GAIN, left_x, right_x)) < 0.01
	check("each finger moves the paddle by its own step: a thumb's drag carrying another finger's leap as its relative moves by its own +6 px (not slammed to the left wall), a tap finger's drag the same, and a step past a quarter of the field moves nothing while the next real step does",
		own_step and tap_own and leap_ignored and after_leap,
		[before, srun.target_x, own_step, tap_own, leap_ignored, after_leap])
	# the browser's own mouse after a tap takes nothing from the thumbs
	screen.set("on_touch", func() -> bool: return false)
	screen.set("mouse_at", func() -> Vector2: return box.position)
	var held_at: float = srun.target_x
	var ghost := InputEventMouseMotion.new()
	ghost.position = box.position + Vector2(5, 300) * fit
	ghost.relative = Vector2(-40.0, 0.0)
	screen.call("_input", ghost)
	var ghost_click := InputEventMouseButton.new()
	ghost_click.button_index = MOUSE_BUTTON_LEFT
	ghost_click.pressed = true
	ghost_click.position = ghost.position
	screen.call("_input", ghost_click)
	var mouse_unbelieved: bool = not bool(screen.get("_by_mouse"))
	screen.call("_process", 1.0 / 60.0)
	var paddle_kept: bool = is_equal_approx(srun.target_x, held_at)
	_cf_slide(screen, 7, 5.0)
	var still_slides: bool = absf(srun.target_x - clampf(held_at + 5.0 / fit * Screen.SLIDER_GAIN, left_x, right_x)) < 0.01
	check("the mouse just after a finger is the browser's, not believed: its move and click take nothing, the frame does not put the paddle under it (even with the touch controls switched off), and the thumb still slides",
		mouse_unbelieved and paddle_kept and still_slides, [mouse_unbelieved, paddle_kept, still_slides])
	screen.set("on_touch", func() -> bool: return true)
	_cf_finger(screen, 7, thumb, false)
	_cf_finger(screen, 8, field, false)
	var head: String = (Screen as GDScript).source_code
	head = head.substr(0, head.find("extends CanvasLayer"))
	check("the screen's header says the phone's controls as they are now (the newest thumb, a drag anywhere, the tap on the lift while a ball waits, fingers forgotten, each finger by its own step)",
		head.contains("newest thumb") and head.contains("DRAG ANYWHERE") and head.contains("_forget_fingers()")
		and head.contains("EACH FINGER MOVES BY ITS OWN STEP"), [])
	var code: String = (Screen as GDScript).source_code
	check("the screen never moves the paddle by a drag's relative (the web build's is not the finger's)",
		not code.contains("drag.relative.x"), [])
	screen.queue_free()
	await get_tree().process_frame
	print("  crownfall's slider never sticks: done")


func _test_crownfall_final_fireball() -> void:
	section("Crownfall's final fireball (0.166.4): the last few go through everything and lock on")
	const Run := preload("res://src/world/crownfall/crownfallrun.gd")
	var run: Node2D = Run.new()
	run.set("running_by_clock", false)
	add_child(run)
	# ---- the owner's picture: the last brick boxed in mirrors and iron ----
	_cf_bare(run)
	var last: Dictionary = run._add(22, 6, "land", "light", 1)
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(0, -1),
			Vector2i(-1, -1), Vector2i(1, -1)]:
		run._add(22 + d.x, 6 + d.y, "mirror" if (d.x + d.y) % 2 == 0 else "iron", "light", 0)
	run.breakable = 1
	run.broken = 0
	run.lives = 99
	run.balls = [run._ball(Vector2(300, 640), Vector2(0, -Run.SPEED))]
	var broke_at: float = -1.0
	var lit: bool = false
	for i in 300:
		run.step(1.0 / 60.0)
		lit = lit or run.final_fire
		if int(last["hp"]) <= 0:
			broke_at = run.t
			break
	var walls_stand: bool = run.bricks.filter(func(k: Dictionary) -> bool: return k["kind"] == "mirror" or k["kind"] == "iron").size() == 8
	check("THE FINAL FIREBALL: the last brick, boxed in mirrors and iron off to one side, breaks inside %ds - the walls would wait %ds" % [int(Run.CRUMBLE_AFTER), int(Run.CRUMBLE_AFTER * Run.FINAL_WAITS)],
		lit and broke_at > 0.0 and broke_at < Run.CRUMBLE_AFTER and walls_stand, [lit, broke_at, walls_stand])
	# ---- straight through a mirror, up to the brick behind it ----
	_cf_bare(run)
	var mirror: Dictionary = run._add(10, 12, "mirror", "light", 0)
	run._add(10, 2, "land", "light", 1)
	run.breakable = 1
	run.broken = 0
	var mid_x: float = (mirror["rect"] as Rect2).get_center().x
	run.balls = [run._ball(Vector2(mid_x, 600), Vector2(0, -Run.SPEED))]
	var bounced: bool = false
	var past: bool = false
	for i in 60:
		run.step(1.0 / 60.0)
		if run.balls.is_empty():
			break
		var b: Dictionary = run.balls[0]
		bounced = bounced or (b["v"] as Vector2).y > 0.0
		past = past or (b["p"] as Vector2).y < (mirror["rect"] as Rect2).position.y - Run.BALL_R
		if past:
			break
	check("THE FINAL FIREBALL passes a mirror without bouncing", past and not bounced and int(mirror["hp"]) == 0, [past, bounced])
	# ---- a normal ball outside the last few still bounces off it ----
	_cf_bare(run)
	mirror = run._add(10, 12, "mirror", "light", 0)
	for c in 20:
		run._add(c, 1, "land", "light", 1)
	run.breakable = 20
	run.broken = 0
	run.balls = [run._ball(Vector2(mid_x, 600), Vector2(0, -Run.SPEED))]
	var back: bool = false
	var through: bool = false
	for i in 60:
		run.step(1.0 / 60.0)
		if run.balls.is_empty():
			break
		var b: Dictionary = run.balls[0]
		back = back or (b["v"] as Vector2).y > 0.0
		through = through or (b["p"] as Vector2).y < (mirror["rect"] as Rect2).position.y - Run.BALL_R
		if back:
			break
	check("Outside the last few a ball still bounces off a mirror (and is no fireball)", back and not through and not run.final_fire,
		[back, through, run.final_fire])
	# ---- on only in the last few, off on a new map ----
	_cf_bare(run)
	for c in 10:
		run._add(c + 3, 3, "land", "light", 1)
	run.breakable = 10
	run.broken = 0
	run.balls = [run._ball(Vector2(640, 600), Vector2(0, -Run.SPEED))]
	run.step(1.0 / 60.0)
	var off_many: bool = not run.final_fire
	run.broken = 6
	run.step(1.0 / 60.0)
	var on_few: bool = run.final_fire
	run.begin(1)
	var off_new: bool = not run.final_fire
	check("The final fireball is on only in the last %d, and off again on a new map" % Run.LAST_FEW, off_many and on_few and off_new,
		[off_many, on_few, off_new])
	# ---- it locks on: the turn is sharp, and sharper close by ----
	_cf_bare(run)
	var one: Dictionary = run._add(16, 4, "land", "light", 1)
	run.breakable = 1
	run.broken = 0
	var at: Vector2 = (one["rect"] as Rect2).get_center()
	run.balls = [run._ball(at + Vector2(-80, 40), Vector2.from_angle(deg_to_rad(-80.0)) * Run.SPEED)]
	run.final_fire = true
	var v0: Vector2 = run.balls[0]["v"]
	run._wind_ball(1.0 / 60.0)
	var turned: float = absf(v0.angle_to(run.balls[0]["v"]))
	check("It locks on: close to the last brick a ball turns more than %d degrees a second" % int(Run.LAST_TURN_ONE),
		turned > deg_to_rad(Run.LAST_TURN_ONE) / 60.0 + 0.001, [rad_to_deg(turned) * 60.0])
	run.queue_free()
	print("  crownfall final fireball: done")


func _test_crownfall_boss_is_the_field() -> void:
	section("Crownfall's boss is the field (0.166.5): its health is the bricks left to break, less what hits took")
	const Run := preload("res://src/world/crownfall/crownfallrun.gd")
	const Maps := preload("res://src/world/crownfall/crownfallmaps.gd")
	const Boss := preload("res://src/world/crownfall/crownfallboss.gd")
	var run: Node2D = Run.new()
	run.set("running_by_clock", false)
	add_child(run)
	run.rng.seed = 5
	# ---- every boss begins as its field ----
	var by_kind: Dictionary = {}
	var bosses: int = 0
	var wrong: Array = []
	for i in Maps.made_count():
		if not Maps.MAPS[i].get("boss") is Dictionary:
			continue
		run.begin(i)
		bosses += 1
		by_kind[str(run.boss.kind)] = i
		var left: int = run.breakable - run.broken
		if run.boss.hp != left or run.boss.most != left or left <= Run.LAST_FEW:
			wrong.append([i, run.boss.kind, run.boss.hp, left])
	check("Every boss's health begins as its field: the bricks there are to break, not iron, mirrors or locks (%d bosses)" % bosses,
		bosses >= 35 and wrong.is_empty(), wrong)
	# ---- a brick takes one, a ball's hit BALL_HIT, a laser's 1 ----
	run.begin(int(by_kind["slimeking"]))
	var king = run.boss
	var stones: Array = run.bricks.filter(func(k: Dictionary) -> bool: return str(k["kind"]) == "stone" and int(k["hp"]) > 0 and not run._guarded(k))
	var start: int = king.hp
	var broken_before: int = run.broken
	run._damage(stones[0], 99, null)
	var brick_took: int = start - king.hp
	var only_one: bool = run.broken == broken_before + 1
	run._hit_boss(Run.BALL_HIT)
	var hit_took: int = start - brick_took - king.hp
	run._hit_boss(1)
	var laser_took: int = start - brick_took - hit_took - king.hp
	check("A brick broken takes one off the boss, a ball's hit %d, a laser's 1 - and its health is the bricks left less what hits took" % Run.BALL_HIT,
		only_one and brick_took == 1 and hit_took == Run.BALL_HIT and laser_took == 1
		and king.hp == run.breakable - run.broken - Run.BALL_HIT - 1, [brick_took, hit_took, laser_took, king.hp])
	# ---- a brick it builds gives one back, up to BOSS_HEALS ----
	var before_build: int = king.hp
	run.rebuild_near(1, run.hall, "stone")
	var healed: int = king.hp - before_build
	var fill: int = run.boss_base + ceili(run.boss_base * Run.BOSS_HEALS)
	run.breakable += fill
	var capped: bool = king.hp == fill - run.broken - run.boss_struck and king.most == king.hp
	run.breakable -= fill
	var back_down: bool = king.hp == before_build + 1
	check("A brick the boss builds gives one back (healing); past %d%% of its start it heals no more, so a fight always ends" % roundi(Run.BOSS_HEALS * 100.0),
		healed == 1 and capped and back_down, [healed, capped, back_down])
	# ---- its splits come from hits alone ----
	run.begin(int(by_kind["slimeking"]))
	king = run.boss
	stones = run.bricks.filter(func(k: Dictionary) -> bool: return str(k["kind"]) == "stone" and int(k["hp"]) > 0 and not run._guarded(k))
	for k in stones.slice(0, Boss.SPLIT_EVERY + 5):
		run._damage(k, 99, null)
	var no_young: bool = king.minions.is_empty() and king.hits_since_split == 0 and king.hp == king.most - Boss.SPLIT_EVERY - 5
	run._hit_boss(Boss.SPLIT_EVERY)
	var young: bool = king.minions.size() == 1
	run.begin(int(by_kind["ruler"]))
	var ruler = run.boss
	for k in run.bricks.duplicate():
		if ruler.hp * 3 < ruler.most * 2:
			break
		if int(k["hp"]) > 0 and run._breaks(k) and str(k["kind"]) != "key":
			run._damage(k, 99, null)
	var past_two_thirds: bool = ruler.hp * 3 < ruler.most * 2 and ruler.alive() and ruler.minions.is_empty()
	run._hit_boss(Boss.RULER_SPLIT_EVERY)
	var ruler_young: bool = ruler.minions.size() == 1
	check("Its splits come from hits alone: the Slime King's %d bricks broken split him not, %d damage does; the Dawn Warden past two thirds by bricks alone splits at his next %d" % [
		Boss.SPLIT_EVERY + 5, Boss.SPLIT_EVERY, Boss.RULER_SPLIT_EVERY],
		no_young and young and past_two_thirds and ruler_young, [no_young, young, past_two_thirds, ruler_young])
	# ---- every brick broken, and the boss falls with the last ----
	run.begin(int(by_kind["slimeking"]))
	king = run.boss
	run.final_fire = true   # so a blow passes every shield and shut brick
	var fireball: Dictionary = run._ball(Vector2(640, 600), Vector2.ZERO)
	var standing_when: int = -1
	for round_n in 8:
		for k in run.bricks.duplicate():
			if king.alive() and int(k["hp"]) > 0 and run._breaks(k):
				run._damage(k, 99, fireball)
				if not king.alive() and standing_when < 0:
					standing_when = run.bricks.filter(func(o: Dictionary) -> bool: return int(o["hp"]) > 0 and run._breaks(o)).size()
	var defeated_words: bool = run.words.any(func(w: Dictionary) -> bool: return str(w["text"]) == "THE SLIME KING IS DEFEATED!")
	run.final_fire = false
	run.step(1.0 / 60.0)
	check("Every brick broken and the boss falls with the last of them - the defeat, its words and the map won",
		standing_when == 0 and run.boss_struck == 0 and defeated_words and run.state == Run.State.CLEARED,
		[standing_when, run.boss_struck, defeated_words, run.state])
	# ---- hits and bricks together, at exactly nought ----
	run.begin(int(by_kind["slimeking"]))
	king = run.boss
	stones = run.bricks.filter(func(k: Dictionary) -> bool: return str(k["kind"]) == "stone" and int(k["hp"]) > 0 and not run._guarded(k))
	run._hit_boss(king.hp - 2)
	run._damage(stones[0], 99, null)
	var one_to_go: bool = king.alive() and king.hp == 1
	run._damage(stones[1], 99, null)
	var by_brick: bool = not king.alive() and run.boss_left() == 0 and run.breakable - run.broken > 100
	run.begin(int(by_kind["slimeking"]))
	king = run.boss
	stones = run.bricks.filter(func(k: Dictionary) -> bool: return str(k["kind"]) == "stone" and int(k["hp"]) > 0 and not run._guarded(k))
	for k in stones.slice(0, 3):
		run._damage(k, 99, null)
	run._hit_boss(king.hp - 1)
	var one_more: bool = king.alive() and king.hp == 1
	run._hit_boss(1)
	var by_hit: bool = not king.alive() and run.boss_left() == 0 and run.words.any(func(w: Dictionary) -> bool: return str(w["text"]) == "THE SLIME KING IS DEFEATED!")
	check("Hits and bricks together bring it down at exactly nought, whichever takes the last - a brick or a hit",
		one_to_go and by_brick and one_more and by_hit, [one_to_go, by_brick, one_more, by_hit])
	# ---- the last few of a boss: final fireballs, and it is among their aims ----
	run.begin(int(by_kind["sprite"]))
	var sprite_boss = run.boss
	stones = run.bricks.filter(func(k: Dictionary) -> bool: return str(k["kind"]) == "stone" and int(k["hp"]) > 0 and not run._guarded(k))
	run.lives = 99
	run.state = Run.State.PLAY
	run.balls = [run._ball(Vector2(640, 650), Vector2(0, -Run.SPEED))]
	run._hit_boss(sprite_boss.hp - Run.LAST_FEW - 1)
	run.step(1.0 / 60.0)
	var not_yet: bool = not run.final_fire and not sprite_boss.cornered and sprite_boss.hp == Run.LAST_FEW + 1
	run._damage(stones[0], 99, null)
	run.step(1.0 / 60.0)
	var fire_on: bool = run.final_fire and sprite_boss.cornered and run.last_few() and run.to_win() == Run.LAST_FEW
	var foe: Vector2 = (sprite_boss.body_rect() as Rect2).get_center()
	var near: Dictionary = run._ball(foe, Vector2(0, -Run.SPEED))
	var brick_at: Vector2 = (stones[1]["rect"] as Rect2).get_center()
	var by_brick_ball: Dictionary = run._ball(brick_at + Vector2(0, 2), Vector2(0, -Run.SPEED))
	run.balls = [near, by_brick_ball]
	run._wind_ball(1.0 / 60.0)
	var aims_at_boss: bool = (near.get("seek", Vector2.INF) as Vector2).is_equal_approx(foe) \
		and (by_brick_ball.get("seek", Vector2.INF) as Vector2).is_equal_approx(brick_at)
	check("A boss's last %d: every ball is a final fireball, and the boss is what it locks on to when it is the nearest" % Run.LAST_FEW,
		not_yet and fire_on and aims_at_boss, [not_yet, fire_on, aims_at_boss])
	# ---- never out of reach then: no dive, no bubble ----
	run.begin(int(by_kind["undine"]))
	var undine = run.boss
	run.lives = 99
	run.state = Run.State.PLAY
	run.balls = [run._ball(Vector2(640, 650), Vector2(0, -Run.SPEED))]
	undine.dive_left = Boss.DIVE_SECONDS
	var under: bool = not undine.hittable()
	run._hit_boss(undine.hp - Run.BALL_HIT)
	run.step(1.0 / 60.0)
	var surfaced: bool = undine.dive_left <= 0.0 and undine.hittable()
	undine.dive_t = 0.001
	undine.step(0.05, true)
	surfaced = surfaced and undine.dive_left <= 0.0
	var strike: Dictionary = run._ball(undine.p + Vector2(0, (undine.body_rect() as Rect2).size.y / 2.0 + Run.BALL_R + 2.0), Vector2(0, -Run.SPEED))
	run._move(strike, 1.0 / 60.0)
	var struck_down: bool = not undine.alive()
	run.begin(int(by_kind["tidemage"]))
	var tide_mage = run.boss
	run.lives = 99
	run.state = Run.State.PLAY
	run.balls = [run._ball(Vector2(640, 650), Vector2(0, -Run.SPEED))]
	var bubbled: bool = tide_mage.bubble_hits > 0 and not tide_mage.hittable()
	run._hit_boss(tide_mage.hp - Run.BALL_HIT)
	run.step(1.0 / 60.0)
	tide_mage.bubble_down = 0.0
	tide_mage._bubble_step(0.1)
	var popped: bool = tide_mage.bubble_hits <= 0 and tide_mage.hittable()
	check("In a boss's last few it is never out of reach: the Undine comes up and dives no more (a fireball brings her down), the Tide Mage's bubble pops and stays down",
		under and surfaced and struck_down and bubbled and popped, [under, surfaced, struck_down, bubbled, popped])
	run.queue_free()
	print("  crownfall boss is the field: done")
