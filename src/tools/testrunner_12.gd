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
		if (tag as Label).text == "TESTING":
			marked.append(tag.get_parent().get_parent().get_parent().get_parent().name)
	check("  and no tile says TESTING", marked.is_empty(), marked)
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
