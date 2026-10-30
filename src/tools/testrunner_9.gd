# testrunner_9.gd - part 9 of the suite (testrunner.gd says how it is
# split): 9 tests, _test_far_attacks_hit_the_swarm,
# _test_a_fall_wakes_you_by_the_chest, _test_the_horde_reaches_the_back_wall,
# _test_the_field_is_dressed, _test_the_field, _test_the_camera_zooms_out,
# _test_the_whole_map, _test_the_swarm_keeps_off_the_walls and
# _test_slimes_speed_up.
extends "res://src/tools/testrunner_8.gd"


# =============================================================================
# FAR ATTACKS HIT THE SWARM (0.94.1)
# =============================================================================
# The owner: "i tossed down my mythic weapon as warrior would hit enemies then
# later it stopped hitting enemies". The swarm's PROXIES stand-ins stood on
# the slimes nearest the player, so once a stage's crowd was past them an axe
# spinning 170 px out hit nothing. Attacks out on the floor are FOCUS_GROUP
# now, and a second pool stands on the slimes round them.

func _test_far_attacks_hit_the_swarm() -> void:
	section("FAR ATTACKS HIT THE SWARM - stand-ins where the axe, a blast or a crater lands (0.94.1)")
	var SwarmScript: GDScript = load("res://src/world/endless/swarm.gd") as GDScript
	check("the swarm loads", SwarmScript != null and SwarmScript.can_instantiate())
	if SwarmScript == null:
		return
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
	# 150 round the player - more than its PROXIES - and a pack of 20 where an
	# axe landed, 170 px off.
	var records := PackedInt32Array()
	var slot: int = 0
	for k in 150:
		var turn: float = TAU * float(k) / 150.0
		var spot: Vector2 = me.global_position + Vector2(cos(turn), sin(turn)) * (30.0 + float(k % 5) * 14.0)
		records.append_array(PackedInt32Array([slot, 1, 50, roundi(spot.x), roundi(spot.y), Element.Type.LIGHT]))
		slot += 1
	var axe_at: Vector2 = me.global_position + Vector2(170, 0)
	var pack: Array = []
	for k in 20:
		var spot: Vector2 = axe_at + Vector2(float(k % 5) * 10.0 - 20.0, floorf(float(k) / 5.0) * 10.0 - 15.0)
		records.append_array(PackedInt32Array([slot, 1, 50, roundi(spot.x), roundi(spot.y), Element.Type.LIGHT]))
		pack.append(slot)
		slot += 1
	swarm.call("import_alive", records)
	var held := func() -> Array:
		var out: Array = []
		for proxy in swarm.get("_proxies"):
			out.append(int(proxy.get("slot")))
		return out
	var on_pack := func(slots: Array) -> int:
		var n: int = 0
		for s in slots:
			if pack.has(s):
				n += 1
		return n
	var twice := func(slots: Array) -> bool:
		var seen := {}
		for s in slots:
			if s >= 0 and seen.has(s):
				return true
			seen[s] = true
		return false

	swarm.call("_place_proxies")
	var before: Array = held.call()
	check("with no attack out, the far pack has no stand-in (the bug, as it was)",
		on_pack.call(before) == 0, on_pack.call(before))

	var focus := Node2D.new()
	focus.add_to_group(&"swarm_focus")
	add_child(focus)
	focus.global_position = axe_at
	swarm.call("_place_proxies")
	var with_axe: Array = held.call()
	check("an attack out on the floor puts a stand-in on every slime round it",
		on_pack.call(with_axe) == pack.size(), on_pack.call(with_axe))
	var player_pool: int = 0
	for p in SwarmScript.PROXIES:
		if int(with_axe[p]) >= 0:
			player_pool += 1
	check("  and the player keeps all of theirs", player_pool == SwarmScript.PROXIES, player_pool)
	check("  no slime has two stand-ins (a blow would land twice)", not twice.call(with_axe))
	check("  a stand-in for the attack sits in the second pool",
		with_axe.slice(SwarmScript.PROXIES).any(func(s): return pack.has(s)))
	var first: Node = swarm.get("_proxies")[SwarmScript.PROXIES]
	swarm.call("_move_proxies")
	var key_a: int = int(first.call("pass_key"))
	check("  a stand-in is remembered by its slime, not by itself (pass_key)",
		key_a < 0 and key_a != first.get_instance_id())

	# Another player's attack, drawn here, hits nothing here.
	focus.set_script(_cosmetic_focus_script())
	focus.set("cosmetic", true)
	check("another player's attack drawn here is no focus",
		(swarm.call("focus_points") as Array).is_empty())
	focus.remove_from_group(&"swarm_focus")
	swarm.call("_place_proxies")
	var after: Array = held.call()
	check("the attack gone, its stand-ins let go", on_pack.call(after) == 0, on_pack.call(after))

	# Every attack that lands away from the player is a focus, with its reach.
	for path in ["res://src/projectiles/spinningaxe.gd", "res://src/projectiles/dynamite.gd",
			"res://src/projectiles/meteor.gd", "res://src/projectiles/burningcrater.gd",
			"res://src/projectiles/spelltargetcircle.gd"]:
		var src: String = _code_src(path)
		check("  %s joins swarm_focus and says its swarm_reach()" % path.get_file(),
			_first_code_index(src, "add_to_group(&\"swarm_focus\")", 0) != -1
			and _first_code_index(src, "func swarm_reach() -> float:", 0) != -1)
	var cut: String = _func_body(_code_src("res://src/projectiles/spinningaxe.gd"), "func _cut_what_it_passes(")
	check("  the axe remembers what it passed by pass_key()", cut.find("pass_key") != -1)

	focus.queue_free()
	me.queue_free()
	swarm.queue_free()
	await get_tree().process_frame
	print("  far attacks: done")


func _fallen_body_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = "extends Node2D\nvar hp: int = 0\nvar notices: Array = []\nfunc show_notice(message: String) -> void:\n\tnotices.append(message)\n"
	script.reload()
	return script


func _cosmetic_focus_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = "extends Node2D\nvar cosmetic: bool = false\n"
	script.reload()
	return script


# =============================================================================
# A FALL WAKES YOU BY THE CHEST (0.94.1)
# =============================================================================
# The owner: "i died wen back into the minigame to find no loot need to make
# sure it pots player by chest after death and has an arrow saying grab loot
# from chest". A fall left a burn on, and once the run was over its tick was a
# death; the corridor's ladder took you to town at a step. Now nothing in the
# Endless kills, a fall clears every effect and wakes you in the chest's
# reach, an arrow over the chest says to grab it, and the ladder asks once.

func _test_a_fall_wakes_you_by_the_chest() -> void:
	section("A FALL WAKES YOU BY THE CHEST - no death in the Endless, an arrow, a ladder that asks (0.94.1)")
	var Run: GDScript = load("res://src/world/endless/endlessrun.gd") as GDScript
	var Chest: GDScript = load("res://src/world/endless/endlesschest.gd") as GDScript
	var Ladder: GDScript = load("res://src/world/ladder.gd") as GDScript
	var Effects: GDScript = load("res://src/characters/statuseffects.gd") as GDScript
	if Run == null or Chest == null or Ladder == null or Effects == null:
		check("the run, chest, ladder and effects load", false)
		return

	# ---- no death in the Endless ----
	var run: Node = Run.new()
	add_child(run)
	await get_tree().process_frame
	var body := Node2D.new()
	body.set_script(_fallen_body_script())
	add_child(body)
	body.global_position = Vector2(800, 400)
	var fx: Node = Effects.attach(body)
	fx.set("burn_left", 2.0)
	fx.set("burn_damage", 5)
	check("with no run, a fall in the Endless is caught: 1 health, by the chest, nothing started",
		bool(run.call("knock_out", body)) and int(body.get("hp")) == 1
		and body.global_position == run.get("wake_spot") and int(run.get("state")) == 0)
	check("  and its burn is out", float(fx.get("burn_left")) == 0.0 and (fx.call("active") as Array).is_empty())
	run.set("state", 2)
	body.global_position = Vector2(800, 400)
	check("  the run over, a fall is caught too (the burn's tick that killed)",
		bool(run.call("knock_out", body)) and int(body.get("hp")) == 1 and int(run.get("state")) == 2)
	body.global_position = Vector2(5000, 5000)
	check("  off the Endless's floor it is an ordinary death", run.call("knock_out", body) == false)

	# ---- you wake in the chest's reach ----
	var area: Node = (load("res://scene/endless.tscn") as PackedScene).instantiate()
	var scene_run: Node = area.get_node_or_null("endlessrun")
	var wake: Vector2 = scene_run.get("wake_spot") if scene_run != null else Vector2.INF
	var chest_at: Vector2 = scene_run.get("chest_spot") if scene_run != null else Vector2.INF
	var corridor: Rect2 = scene_run.get("corridor_rect") if scene_run != null else Rect2()
	var arrival: Node2D = area.get_node_or_null("ysortworld/interactables/endlessarrival") as Node2D
	# The chest's reach is a 42 px circle at (1, 3); a player's feet a 7 px one
	# at (0, 13); its body 17 x 10 at (0.5, 3).
	var reach_mid: Vector2 = chest_at + Vector2(1, 3)
	var chest_box := Rect2(chest_at + Vector2(0.5, 3) - Vector2(8.5, 5), Vector2(17, 10))
	var spots: Array = []
	for step in Run.WAKE_SPOTS:
		spots.append(wake + (step as Vector2))
	var fits: bool = true
	var why: Array = []
	for spot in spots:
		var feet: Vector2 = (spot as Vector2) + Vector2(0, 13)
		var in_reach: bool = feet.distance_to(reach_mid) < 42.0 + 7.0
		var off_chest: bool = not chest_box.grow(7.0).has_point(feet)
		var in_corridor: bool = corridor.has_point(spot)
		if not (in_reach and off_chest and in_corridor):
			fits = false
			why.append([spot, in_reach, off_chest, in_corridor])
	for a in spots.size():
		for b in range(a + 1, spots.size()):
			if (spots[a] as Vector2).distance_to(spots[b]) < 14.0:
				fits = false
				why.append(["close", spots[a], spots[b]])
	check("a fall wakes you in the chest's reach, clear of it - alone and each of a party", fits, why)
	check("  alone, where Go brings you", arrival != null and arrival.position == wake,
		[wake, arrival.position if arrival != null else null])
	var builder: String = _code_src("res://src/tools/buildendless.gd")
	check("  the map's builder sets the same spot", builder.find("run.set(\"wake_spot\", Vector2(%d, %d))" % [roundi(wake.x), roundi(wake.y)]) != -1)
	area.free()

	# ---- the arrow over the chest ----
	var chest: Node2D = Chest.new()
	chest.set("chest_request", func(_game: String, _slot: int) -> Dictionary: return {"ok": false})
	chest.set("slot_now", func() -> int: return 0)
	var standing := Node2D.new()
	add_child(standing)
	chest.set("player_now", func() -> Node: return standing)
	chest.set("corridor", Rect2(-62000, -62000, 160, 420))
	add_child(chest)
	chest.global_position = Vector2(-61920, -61700)
	standing.global_position = Vector2(-61930, -61740)
	await get_tree().process_frame
	var beckon: Node2D = chest.get("beckon")
	var tick := func() -> bool:
		chest.call("_tick_beckon", 0.1)
		return beckon.visible
	check("an empty chest points at nothing", beckon != null and not tick.call())
	chest.call("note_used", 3)
	check("with loot in it and you in the corridor, an arrow says to grab it",
		tick.call() and (chest.get("beckon_label") as Label).text == "Grab your loot")
	chest.set("is_open", true)
	check("  not while it is open", not tick.call())
	chest.set("is_open", false)
	standing.global_position = Vector2(-61930, -62100)
	check("  not to somebody out in the arena", not tick.call())
	standing.global_position = Vector2(-61930, -61740)
	var heights := {}
	for i in 20:
		tick.call()
		heights[beckon.position.y] = true
	var near_it: bool = true
	for y in heights.keys():
		near_it = near_it and absf(float(y) - Chest.BECKON_Y) <= Chest.BECKON_BOB
	check("  it bobs, a pixel or two over the chest", heights.size() > 1 and near_it, heights.keys())
	var run_src: String = _code_src("res://src/world/endless/endlessrun.gd")
	check("  the run tells its chest the corridor",
		_first_code_index(run_src, "chest.set(\"corridor\", corridor_rect)", 0) != -1)

	# ---- the ladder asks once ----
	var ladder: Area2D = Area2D.new()
	ladder.set_script(Ladder)
	add_child(ladder)
	# This chest alone asks: one an earlier section left would answer too.
	var others: Array = []
	for guard in get_tree().get_nodes_in_group(&"ladder_guard"):
		if guard != chest:
			others.append(guard)
			guard.remove_from_group(&"ladder_guard")
	check("with loot in the chest, the ladder holds you the first time and says so",
		bool(ladder.call("held_back", body)) and (body.get("notices") as Array).size() == 1
		and str((body.get("notices") as Array)[0]).find("chest holds 3") != -1, body.get("notices"))
	check("  and lets you go the next", not bool(ladder.call("held_back", body)))
	chest.call("note_used", 4)
	check("  more loot, and it asks again", bool(ladder.call("held_back", body)))
	chest.call("note_used", 0)
	check("  an empty chest never holds it", not bool(ladder.call("held_back", body)))
	var enter: String = _func_body(_code_src("res://src/world/ladder.gd"), "func _on_body_entered(")
	check("  the ladder asks before it starts the trip",
		enter.find("held_back(body)") != -1 and enter.find("held_back(body)") < enter.find("can_teleport = false"))

	for guard in others:
		if is_instance_valid(guard):
			guard.add_to_group(&"ladder_guard")
	ladder.queue_free()
	chest.queue_free()
	standing.queue_free()
	body.queue_free()
	run.queue_free()
	await get_tree().process_frame
	print("  the fall and the chest: done")


# =============================================================================
# THE HORDE REACHES THE BACK WALL (0.94.2)
# =============================================================================
# The owner: "enemies stop moving on top side of map in minigame". A player's
# origin is 13 px over its feet, so against the back wall it stands at y 22,
# over the swarm's floor (y 34): the crowd chased nobody, stood still and
# touched nobody, and the run did not count the player in.

func _test_the_horde_reaches_the_back_wall() -> void:
	section("THE HORDE REACHES THE BACK WALL - a player against it is on the floor (0.94.2)")
	var SwarmScript: GDScript = load("res://src/world/endless/swarm.gd") as GDScript
	var Run: GDScript = load("res://src/world/endless/endlessrun.gd") as GDScript
	if SwarmScript == null or Run == null:
		check("the swarm and the run load", false)
		return
	# The arena as the map has it (endless.tscn), far from everything.
	var o := Vector2(-58000, -58000)
	var floor_rect := Rect2(o + Vector2(9, 34), Vector2(1518, 1344))
	var swarm: Node2D = SwarmScript.new()
	swarm.set("arena", floor_rect)
	add_child(swarm)
	swarm.set_process(false)
	swarm.set_physics_process(false)
	var me := Node2D.new()
	me.add_to_group(&"player")
	add_child(me)
	# Where a warrior stands against the back wall: 12 px over the floor.
	me.global_position = o + Vector2(700, 22)
	check("a player against the back wall is on the crowd's floor",
		bool(swarm.call("on_floor", me.global_position)) and not floor_rect.has_point(me.global_position))
	var aim: Vector2 = swarm.call("floor_point", me.global_position)
	check("  and the crowd goes for the nearest point of the floor to them",
		aim == Vector2(me.global_position.x, floor_rect.position.y + SwarmScript.EDGE), aim)
	var records := PackedInt32Array()
	for k in 12:
		var spot: Vector2 = me.global_position + Vector2(float(k % 4) * 20.0 - 30.0, 90.0 + floorf(float(k) / 4.0) * 20.0)
		records.append_array(PackedInt32Array([k, 1, 50, roundi(spot.x), roundi(spot.y), Element.Type.LIGHT]))
	swarm.call("import_alive", records)
	var start: float = 0.0
	for k in 12:
		start += (swarm.get("py") as PackedFloat32Array)[k]
	for i in 120:
		swarm.call("_process", 1.0 / 30.0)
	var end: float = 0.0
	for k in 12:
		end += (swarm.get("py") as PackedFloat32Array)[k]
	check("  it comes for them", end < start - 12.0 * 40.0, [start / 12.0, end / 12.0])
	check("  and touches them", int(swarm.get("_touching")) > 0, swarm.get("_touching"))
	me.global_position = o + Vector2(700, -40)
	check("off the map's floor nobody is chased", not bool(swarm.call("on_floor", me.global_position)))

	var run: Node = Run.new()
	var against: Vector2 = Vector2(700, 22)
	check("the run counts a player against the back wall in",
		bool(run.call("on_floor", against)) and not bool(run.call("in_arena", against)))
	check("  but not one in the corridor", not bool(run.call("on_floor", Vector2(768, 1200))))
	run.free()
	me.queue_free()
	swarm.queue_free()
	await get_tree().process_frame
	print("  the back wall: done")


# =============================================================================
# THE FIELD, BUILT FROM A PLAN (0.94.2)
# =============================================================================
# The owner: "work on the next map field". tools/maps/field.py (seed 38) and
# src/tools/buildfield.gd, as the Big Field: you arrive top left from the Big
# Field's ladder; the fire route over the top and down the right, the dark
# route down the left and along the bottom, round a solid middle; the exit
# hall's guard by the outer lever, the boss gate, the ladder below.
const FIELD := "res://scene/field.tscn"
const FIELD_PLAN := "res://tools/maps/field_build.json"
const FIELD_MONSTERS := 27
const FIELD_DOORS := 3
const FIELD_LANDS := {"fire": 12, "dark": 12, "plain": 3}


func _test_the_field_is_dressed() -> void:
	_check_dressed_map(FIELD,
		"THE FIELD, DRESSED - every edge walled in the crypt's own pieces, its doors and the boss gate in place (0.94.2)",
		{"pieces": 300, "edges": 1000, "doors": FIELD_DOORS, "levers": 2, "spikes": 3,
		"gates_words": "%d levers, one either side of the boss gate, each driving its three spikes",
		"lands": {}, "behind": ["dark", "plain"],
		"behind_words": "  and with the doors shut, the dark route and the exit hall are closed off behind them"})


func _test_the_field() -> void:
	section("THE FIELD - two routes round a solid middle, fire and dark, the guard at the levers (0.94.2)")
	var area: Node = (load(FIELD) as PackedScene).instantiate()
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIELD_PLAN))
	check("the scene and its plan load", area != null and plan is Dictionary)
	if area == null or not (plan is Dictionary):
		if area != null:
			area.free()
		return
	var enemies: Array = area.get_node("ysortworld/enemies").get_children()
	var by_land: Dictionary = {}
	for enemy in enemies:
		var land: String = str(enemy.name).get_slice("_", 0)
		by_land[land] = int(by_land.get(land, 0)) + 1
	check("%d monsters, as the plan says: twelve of fire, twelve of the dark, three skeletons" % enemies.size(),
		enemies.size() == FIELD_MONSTERS and (plan["monsters"] as Array).size() == FIELD_MONSTERS
		and by_land == FIELD_LANDS, by_land)
	var arrive: Vector2 = _area_xform(area.get_node("ysortworld/interactables/fieldteleport/arrivalmarker"), area).origin
	var nearest: float = INF
	for enemy in enemies:
		nearest = minf(nearest, (enemy as Node2D).position.distance_to(arrive))
	check("  none within 400 px of where you arrive", nearest >= 400.0, nearest)
	var outside: Node2D = area.get_node_or_null("ysortworld/interactables/levergatesout") as Node2D
	var guard: Node2D = null
	for enemy in enemies:
		if str(enemy.scene_file_path).ends_with("skeletonelite.tscn") and str(enemy.name).begins_with("plain"):
			guard = enemy
	var guarded: bool = outside != null and guard != null
	if guarded:
		for enemy in enemies:
			if not str(enemy.name).begins_with("plain") \
					and (enemy as Node2D).position.distance_to(outside.position) < guard.position.distance_to(outside.position):
				guarded = false
	check("the guard - a skeleton elite and two soldiers - stands nearer the outer lever than anything else", guarded)
	var authored := true
	for enemy in enemies:
		var own: Node = (load(str(enemy.scene_file_path)) as PackedScene).instantiate()
		authored = authored and is_equal_approx(float(enemy.get("leash_range")), float(own.get("leash_range")))
		own.free()
	check("  every monster keeps its own leash, as the old Field's did (a bush mage's 1,500)", authored)
	# The export: the server's books know every monster where it stands.
	var exported: Array = []
	var areas: Variant = _load_gamedata().get("areas", {})
	if areas is Dictionary and (areas as Dictionary).has("field"):
		exported = (areas["field"] as Dictionary).get("spawns", [])
	var missing: Array = []
	for spawn in exported:
		if not area.has_node(str(spawn.get("o", ""))):
			missing.append(spawn.get("o"))
	check("gamedata.json holds the Field's %d monsters where they stand (re-export and copy to the API if not)" % exported.size(),
		exported.size() == enemies.size() and missing.is_empty(), missing.slice(0, 4))
	# The road: the Big Field's ladder lands here, this ladder goes to the boss.
	var down: Node = area.get_node_or_null("ysortworld/interactables/ladderdown")
	var back: Node = area.get_node_or_null("ysortworld/interactables/ladderarrival")
	check("the ladder down goes to the boss arena, and a climb back up lands beside it",
		down != null and str(down.get("destination_scene_path")) == "res://scene/bossarena.tscn"
		and str(down.get("target_spawn_id")) == "boss_entrance" and back != null and str(back.get("portal_id")) == "boss_ladder")
	var builder: String = _code_src("res://src/tools/buildfield.gd")
	check("  built by buildfield.gd, the Big Field's builder with the Field's own ladder, gate and leashes",
		builder.contains("extends \"res://src/tools/buildbigfield.gd\"") and builder.contains("func _gates(")
		and builder.contains("func _ladder(") and builder.contains("func _monsters("))
	area.free()
	print("  the Field: %d monsters %s, the guard at the levers" % [enemies.size(), by_land])


# =============================================================================
# THE CAMERA ZOOMS OUT TO 1x, FROM THE WORLD (0.95.0)
# =============================================================================
# The owner, of the Big Field and the new Field: "map is soo big we need to be
# able to zoom out", "all the way out". Options' Camera view goes to 1x (it
# stopped at 2x), and the mouse wheel over the world and two zoom keys move it.
const _HudCode := preload("res://src/ui/characterhud.gd")
const _OptionsScene := preload("res://scene/ui/menus/optionsscreen.tscn")


func _wheel(up: bool, factor: float = 1.0, down: bool = true) -> InputEventMouseButton:
	var turn := InputEventMouseButton.new()
	turn.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	turn.factor = factor
	turn.pressed = down
	return turn


func _test_the_camera_zooms_out() -> void:
	section("THE CAMERA ZOOMS OUT TO 1x - the wheel over the world, the zoom keys, the Options slider (0.95.0)")
	var was: float = float(Settings.get_value("camera_zoom"))
	check("the camera goes out to 1x and in to 3x, in quarters",
		is_equal_approx(Settings.CAMERA_ZOOM_MIN, 1.0) and is_equal_approx(Settings.CAMERA_ZOOM_MAX, 3.0)
		and is_equal_approx(Settings.CAMERA_ZOOM_STEP, 0.25))
	# A camera in the tree follows, as the slider's does.
	var camera := Camera2D.new()
	add_child(camera)
	Settings.set_value("camera_zoom", 3.0)
	var out_one: float = Settings.step_camera_zoom(-1)
	check("a step out from 3x is 2.75x, and the camera is there", is_equal_approx(out_one, 2.75)
		and is_equal_approx(camera.zoom.x, 2.75) and is_equal_approx(camera.zoom.y, 2.75), camera.zoom)
	for i in 20:
		Settings.step_camera_zoom(-1)
	check("  stepping on stops at 1x", is_equal_approx(float(Settings.get_value("camera_zoom")), 1.0)
		and is_equal_approx(camera.zoom.x, 1.0), camera.zoom)
	Settings.step_camera_zoom(3)
	check("  and back in, a quarter a step", is_equal_approx(float(Settings.get_value("camera_zoom")), 1.75))
	for i in 20:
		Settings.step_camera_zoom(1)
	check("  stopping at 3x", is_equal_approx(float(Settings.get_value("camera_zoom")), 3.0))
	Settings.set_value("camera_zoom", 2.6)
	check("  a value off the grid (an edited file) steps onto it",
		is_equal_approx(Settings.step_camera_zoom(-1), 2.25), Settings.get_value("camera_zoom"))
	camera.queue_free()

	# The wheel and the keys, as the HUD reads them.
	var hud: Node = _HudCode.new()
	check("a notch of the wheel up is a step in, down a step out",
		hud.zoom_steps_for(_wheel(true)) == 1 and hud.zoom_steps_for(_wheel(false)) == -1)
	check("  its letting go is nothing", hud.zoom_steps_for(_wheel(true, 1.0, false)) == 0)
	var small: Array = [hud.zoom_steps_for(_wheel(false, 0.4)), hud.zoom_steps_for(_wheel(false, 0.4)),
		hud.zoom_steps_for(_wheel(false, 0.4))]
	check("  a trackpad's small turns add up to whole steps", small == [0, 0, -1], small)
	var minus := Keybinds.key_press(KEY_MINUS)
	minus.pressed = true
	var equal := Keybinds.key_press(KEY_EQUAL)
	equal.pressed = true
	var held := Keybinds.key_press(KEY_MINUS)
	held.pressed = true
	held.echo = true
	check("the zoom keys: minus out, equals in, and held it keeps going",
		hud.zoom_steps_for(minus) == -1 and hud.zoom_steps_for(equal) == 1 and hud.zoom_steps_for(held) == -1)
	var a_key := Keybinds.key_press(KEY_A)
	a_key.pressed = true
	check("  any other key is nothing", hud.zoom_steps_for(a_key) == 0)
	hud.free()
	check("  both can be changed like every other key, and the Controls card lists them",
		Keybinds.all_actions().has("zoom_in") and Keybinds.all_actions().has("zoom_out")
		and InputMap.has_action("zoom_in") and InputMap.has_action("zoom_out")
		and ControlsPanel.ROWS.any(func(row: Array) -> bool: return row[1] == "zoom_out")
		and ControlsPanel.ROWS.any(func(row: Array) -> bool: return row[1] == "zoom_in"))
	var hud_code: String = _code_src("res://src/ui/characterhud.gd")
	var handler: String = _func_body(hud_code, "func _unhandled_input(")
	check("  the HUD zooms from what no window took (its _unhandled_input), through the setting",
		handler.contains("zoom_steps_for(event)") and handler.contains("Settings.step_camera_zoom("))

	# Options: the slider's range, and it follows a zoom from the world.
	var opts: Node = _OptionsScene.instantiate()
	var slider: Range = opts.get_node_or_null("%camerazoom") as Range
	check("the Options slider goes from 1x to 3x as authored",
		slider != null and is_equal_approx(slider.min_value, 1.0) and is_equal_approx(slider.max_value, 3.0))
	opts.set("camera_zoom", slider)
	opts.set("camera_zoom_value", opts.get_node_or_null("%camerazoomvalue"))
	opts.call("_on_zoom_from_the_world", "camera_zoom", 1.5)
	var number: Label = opts.get_node_or_null("%camerazoomvalue") as Label
	check("  and follows a zoom from the world, its number with it",
		is_equal_approx(slider.value, 1.5) and number != null and number.text == "1.50x",
		[slider.value, number.text if number else "?"])
	opts.free()

	Settings.set_value("camera_zoom", was)
	print("  the camera: 1x to 3x, the wheel and the keys a quarter a step")


# =============================================================================
# THE WHOLE MAP, AS BIG AS THE WINDOW (0.96.0)
# =============================================================================
# The owner: "i need players to be able to see the whole map". The map window
# fills most of the screen and fits the picture at any scale (blown up by a
# whole number, nearest, then drawn down, linear), ground not walked yet is
# drawn darker, and every landmark has its pin.
const _MapCode := preload("res://src/ui/menus/mapscreen.gd")
const _MapScene := preload("res://scene/ui/menus/mapscreen.tscn")
const _MAP_AREA := "zz_suite_map"
const _MAP_BIG := "zz_suite_map_big"


func _test_the_whole_map() -> void:
	section("THE WHOLE MAP - the window fills the screen, the picture fits it, it zooms and drags, the unwalked ground is drawn darker (0.96.0)")
	# A 4 x 2 area: the top row painted, the bottom row's last cell bare; the
	# first two cells seen.
	var ground := Color(0.33, 0.45, 0.26)
	var terrain := Image.create_empty(4, 2, false, Image.FORMAT_RGBA8)
	terrain.fill(Color(0, 0, 0, 0))
	for x in 4:
		terrain.set_pixel(x, 0, ground)
	for x in 3:
		terrain.set_pixel(x, 1, ground)
	WorldMap._terrain[_MAP_AREA] = {"image": terrain, "origin": Vector2i.ZERO, "size": Vector2i(4, 2),
		"tile": Vector2i(16, 16)}
	WorldMap._seen[_MAP_AREA] = PackedByteArray([0b11])
	var fogged: Image = WorldMap.display_image(_MAP_AREA)
	var whole: Image = WorldMap.display_image(_MAP_AREA, true)
	# Eight bits a channel: a colour comes back within half a step of 1/255.
	var near := func(a: Color, b: Color) -> bool:
		return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01 and absf(a.a - b.a) < 0.01
	check("seen ground is drawn as it is, either way",
		near.call(whole.get_pixel(0, 0), ground) and near.call(fogged.get_pixel(1, 0), ground),
		[whole.get_pixel(0, 0), fogged.get_pixel(1, 0)])
	check("  the fog still hides the rest where the whole map is not asked for",
		near.call(fogged.get_pixel(2, 0), WorldMap.COLOUR_FOG), fogged.get_pixel(2, 0))
	var dim: Color = whole.get_pixel(2, 0)
	check("  the whole map draws ground not walked yet, darker than what was seen",
		dim.a > 0.99 and dim.v < ground.v and dim.v > WorldMap.COLOUR_FOG.v, dim)
	check("  and leaves bare what nothing is painted on", whole.get_pixel(3, 1).a < 0.01, whole.get_pixel(3, 1))

	# The fit: any scale, the largest at which all of it fits.
	check("the Big Field's 385 x 322 fills the frame at 1.74x - not floored to 1x",
		is_equal_approx(snappedf(_MapCode.fit_for(Vector2(1120, 560), Vector2(385, 322)), 0.01), 1.74),
		_MapCode.fit_for(Vector2(1120, 560), Vector2(385, 322)))
	check("  a frame with no size yet draws at 1x", is_equal_approx(_MapCode.fit_for(Vector2.ZERO, Vector2(10, 10)), 1.0))
	var small := Image.create_empty(10, 5, false, Image.FORMAT_RGBA8)
	var sharp: Image = _MapCode.sharpen(small, 2.6)
	check("the picture is blown up by the whole number past what it is drawn at (2.6 -> 3x)",
		sharp.get_size() == Vector2i(30, 15), sharp.get_size())
	check("  not at all when it is drawn smaller than it is", _MapCode.sharpen(small, 0.7).get_size() == Vector2i(10, 5))
	var wide := Image.create_empty(600, 10, false, Image.FORMAT_RGBA8)
	check("  and never past the largest texture side",
		_MapCode.sharpen(wide, 8.0).get_width() <= _MapCode.MAX_TEXTURE, _MapCode.sharpen(wide, 8.0).get_width())

	# The window as drawn, and the picture in it.
	var map: Control = _MapScene.instantiate() as Control
	check("the map window is drawn 1160 x 640 - most of the screen",
		map.size.is_equal_approx(Vector2(1160, 640)) or Vector2(map.offset_right - map.offset_left,
			map.offset_bottom - map.offset_top).is_equal_approx(Vector2(1160, 640)))
	var picture: TextureRect = map.get_node_or_null("%mapview") as TextureRect
	var under: Control = map.get_node_or_null("%mapground") as Control
	check("  the map fills its frame and clips; the picture is drawn on a layer under the pins",
		picture != null and picture.get_parent() == map.get_node_or_null("%mapframe")
		and picture.expand_mode == TextureRect.EXPAND_IGNORE_SIZE and picture.clip_contents
		and under != null and under.get_parent() == picture and under.get_index() < map.get_node("%mapmarkers").get_index())
	check("  and its footer has -, + and Whole map",
		map.get_node_or_null("%mapzoomout") is Button and map.get_node_or_null("%mapzoomin") is Button
		and map.get_node_or_null("%mapwhole") is Button)
	add_child(map)
	map.set("_area", _MAP_AREA)
	picture.size = Vector2(400, 300)
	map.call("_layout")
	var at: Variant = map.call("_on_map", Vector2(24, 24))
	check("  a place in the world lands where the picture drew it (fit 100, 50 px down to centre it)",
		is_equal_approx(float(map.get("_fit")), 100.0) and at is Vector2 and (at as Vector2).is_equal_approx(Vector2(150, 200)), at)
	check("  and off the map is nowhere", map.call("_on_map", Vector2(-40, 8)) == null)

	# ZOOM AND DRAG, on a 40 x 20 area in a 400 x 300 view: the whole of it at
	# 10 a tile, and in as far as 24 a tile.
	WorldMap._terrain[_MAP_BIG] = {"image": Image.create_empty(40, 20, false, Image.FORMAT_RGBA8),
		"origin": Vector2i.ZERO, "size": Vector2i(40, 20), "tile": Vector2i(16, 16)}
	map.set("_area", _MAP_BIG)
	map.call("show_whole")
	check("the map opens on the whole area: 10 a tile, centred",
		is_equal_approx(float(map.get("_fit")), 10.0) and (map.get("_offset") as Vector2).is_equal_approx(Vector2(0, 50)),
		[map.get("_fit"), map.get("_offset")])
	map.call("zoom_by", 2.0, Vector2(100, 100))
	var kept: Vector2 = (map.get("_offset") as Vector2) + Vector2(10, 5) * float(map.get("_fit"))
	check("  zoomed in about the pointer, the map under it stays under it",
		is_equal_approx(float(map.get("_fit")), 20.0) and kept.is_equal_approx(Vector2(100, 100)), [map.get("_fit"), kept])
	map.call("zoom_by", 100.0)
	check("  no further in than a tile 24 across", is_equal_approx(float(map.get("_fit")), 24.0), map.get("_fit"))
	map.call("pan_by", Vector2(-5000, 0))
	var right_edge: float = (map.get("_offset") as Vector2).x + 40.0 * float(map.get("_fit"))
	check("  dragged as far as it goes, its edge stops at the view's",
		is_equal_approx(right_edge, 400.0), right_edge)
	map.call("zoom_by", 0.01)
	check("  and zoomed out, no further than the whole area", is_equal_approx(float(map.get("_fit")), 10.0), map.get("_fit"))
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(200, 150)
	map.call("_on_view_input", wheel)
	check("the wheel over the map zooms it", is_equal_approx(float(map.get("_fit")), 12.5), map.get("_fit"))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	map.call("_on_view_input", press)
	var was_centre: Vector2 = map.get("_centre")
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	drag.relative = Vector2(25, 0)
	map.call("_on_view_input", drag)
	check("  a drag moves it", is_equal_approx((map.get("_centre") as Vector2).x, was_centre.x - 2.0),
		[was_centre, map.get("_centre")])
	(map.get_node("%mapwhole") as Button).pressed.emit()
	check("  and Whole map shows all of it again", is_equal_approx(float(map.get("_fit")), 10.0))
	(map.get_node("%mapzoomin") as Button).pressed.emit()
	var stepped_in: float = float(map.get("_fit"))
	(map.get_node("%mapzoomout") as Button).pressed.emit()
	check("  + zooms in a step, - back out",
		is_equal_approx(stepped_in, 16.0) and is_equal_approx(float(map.get("_fit")), 10.0), [stepped_in, map.get("_fit")])
	var hud_code: String = _code_src("res://src/ui/menus/mapscreen.gd")
	check("  the map takes the wheel and the drag itself, so the camera does not zoom under it",
		_func_body(hud_code, "func _on_view_input(").contains("view.accept_event()"))
	WorldMap._terrain.erase(_MAP_BIG)
	map.queue_free()
	var map_src: String = _code_src("res://src/ui/menus/mapscreen.gd")
	check("every landmark has its pin, walked or not; monsters only on ground seen",
		not _func_body(map_src, "func _collect_landmarks(").contains("is_seen")
		and _func_body(map_src, "func _draw_monsters(").contains("WorldMap.is_seen(")
		and _func_body(map_src, "func refresh(").contains("WorldMap.display_image(_area, true)"))

	WorldMap._terrain.erase(_MAP_AREA)
	WorldMap._seen.erase(_MAP_AREA)
	await get_tree().process_frame
	print("  the map: the whole area, at any size, the unwalked ground darker")


# =============================================================================
# THE SWARM KEEPS OFF THE WALLS, AND THE WAVE CUTS IT ALL (0.96.0)
# =============================================================================
# The owner: "in minigame slimes are going behind walls and warriors
# projectile is not slicing through all enemies". A slime's picture is wider
# than its feet, so held EDGE from a side wall half of it was under the wall;
# the top row was under the back wall. And the slash wave flew past the crowd
# round the player, where the slimes had no stand-ins, and remembered a
# stand-in, not its slime.
func _test_the_swarm_keeps_off_the_walls() -> void:
	section("THE SWARM KEEPS OFF THE WALLS, AND THE WAVE CUTS IT ALL - bodies clear of the sides, the top row over the back wall, every slime the wave meets cut once (0.96.0)")
	var SwarmScript: GDScript = load("res://src/world/endless/swarm.gd") as GDScript
	var o := Vector2(-64000, -64000)
	var swarm: Node2D = SwarmScript.new()
	var arena := Rect2(o + Vector2(9, 34), Vector2(800, 600))
	var corridor := Rect2(o + Vector2(350, 450), Vector2(100, 184))
	swarm.set("arena", arena)
	(swarm.get("keep_out") as Array).append(corridor)
	swarm.call("draw_in_front_of", o.y + 28.0)
	add_child(swarm)
	swarm.set_process(false)
	swarm.set_physics_process(false)
	await get_tree().process_frame
	swarm.call("spawn", 400, o + Vector2(400, 300))
	# Chased to the left wall, then to beside the corridor.
	for k in 80:
		swarm.call("_step", o + Vector2(0, 300), true)
	var px: PackedFloat32Array = swarm.get("px")
	var py: PackedFloat32Array = swarm.get("py")
	var leftmost: float = INF
	for i in int(swarm.get("_high")):
		if int(swarm.get("state")[i]) == 1:
			leftmost = minf(leftmost, px[i])
	check("against a side wall a slime's feet stay %d px off it - its picture clear of the wall" % int(SwarmScript.SIDE_EDGE),
		leftmost >= arena.position.x + SwarmScript.SIDE_EDGE - 0.01, leftmost - arena.position.x)
	for k in 80:
		swarm.call("_step", o + Vector2(340, 600), true)
	px = swarm.get("px")
	py = swarm.get("py")
	var too_near: int = 0
	for i in int(swarm.get("_high")):
		if int(swarm.get("state")[i]) == 1 and py[i] > corridor.position.y + 1.0 \
				and px[i] > corridor.position.x - SwarmScript.HELD_OUT_SIDES + 0.5 and px[i] < corridor.end.x + SwarmScript.HELD_OUT_SIDES - 0.5:
			too_near += 1
	check("  beside the corridor, %d px further out than its feet were held" % int(SwarmScript.HELD_OUT_SIDES), too_near == 0, too_near)
	var target: Vector2 = swarm.call("floor_point", o + Vector2(12, 300))
	check("  and a player against the wall is still the crowd's to reach (floor_point)",
		is_equal_approx(target.x, arena.position.x + SwarmScript.SIDE_EDGE))
	# The top row, over the back wall.
	swarm.call("clear")
	var records := PackedInt32Array()
	var ys: Array = [40, 50, 69, 71, 200]
	for k in ys.size():
		records.append_array(PackedInt32Array([k, 1, 50, roundi(o.x + 100.0 + k * 40.0), roundi(o.y + float(ys[k])), 0]))
	swarm.call("import_alive", records)
	swarm.call("_write_buffer")
	var front: MultiMeshInstance2D = swarm.get("_front") as MultiMeshInstance2D
	var back: MultiMeshInstance2D = swarm.get("_mesh") as MultiMeshInstance2D
	check("the slimes whose pictures reach over the back wall are drawn by the front layer, the rest as before",
		front != null and front.multimesh.visible_instance_count == 3 and back.multimesh.visible_instance_count == 2,
		[front.multimesh.visible_instance_count if front else -1, back.multimesh.visible_instance_count])
	var first_y: float = (swarm.get("_front_buffer") as PackedFloat32Array)[7]
	check("  sorted a pixel past the wall's foot, with the world, over the wall and under anybody south of it",
		swarm.y_sort_enabled and is_equal_approx(front.position.y, o.y + 29.0) and front.z_index == 0
		and back.z_index == SwarmScript.DRAW_Z and is_equal_approx(first_y + front.position.y, o.y + 40.0), first_y)
	check("  drawn as written, never blended by the engine",
		front.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF)

	# The wave, flown through a line of slimes past the crowd round the player.
	swarm.call("clear")
	var me := Node2D.new()
	me.add_to_group(&"player")
	add_child(me)
	me.global_position = o + Vector2(200, 300)
	records = PackedInt32Array()
	var slot: int = 0
	for k in 150:
		var turn: float = TAU * float(k) / 150.0
		var spot: Vector2 = me.global_position + Vector2(cos(turn), sin(turn)) * (24.0 + float(k % 5) * 10.0)
		if spot.x > me.global_position.x + 10.0 and absf(spot.y - me.global_position.y - 8.0) < 30.0:
			spot.y += 80.0
		records.append_array(PackedInt32Array([slot, 1, 50, roundi(spot.x), roundi(spot.y), 0]))
		slot += 1
	var line: Array = []
	for k in 30:
		var spot: Vector2 = me.global_position + Vector2(110.0 + float(k) * 12.0, 8.0 + float(k % 3) * 6.0 - 6.0)
		records.append_array(PackedInt32Array([slot, 1, 50, roundi(spot.x), roundi(spot.y), 0]))
		line.append(slot)
		slot += 1
	swarm.call("import_alive", records)
	var wave: Area2D = (load("res://scene/projectiles/slashwave.tscn") as PackedScene).instantiate()
	var notice: Node = wave.get_node_or_null("VisibleOnScreenNotifier2D")
	if notice != null:
		wave.remove_child(notice)
		notice.free()
	wave.set("damage", 10)
	add_child(wave)
	wave.global_position = me.global_position
	wave.call("shoot_vector", Vector2.RIGHT)
	check("the slash wave puts stand-ins where it flies (swarm_focus, its reach)",
		wave.is_in_group(&"swarm_focus") and float(wave.call("swarm_reach")) > 30.0)
	for t in 140:
		swarm.call("_place_proxies")
		await get_tree().physics_frame
	var hp: PackedFloat32Array = swarm.get("hp")
	var cut: int = 0
	var twice: int = 0
	for s in line:
		if hp[s] <= 40.5:
			cut += 1
		if hp[s] < 39.5:
			twice += 1
	check("  it cuts every slime in its way, past the crowd round you: %d of %d" % [cut, line.size()],
		cut == line.size(), cut)
	check("  each once, though stand-ins move from slime to slime under it (Targets.hit_key)", twice == 0, twice)
	var orb_src: String = _code_src("res://src/projectiles/bladeorb.gd")
	check("  and the warrior's orbs: stand-ins where they fly, a slime remembered by itself",
		_first_code_index(orb_src, "add_to_group(&\"swarm_focus\")", 0) != -1
		and _func_body(orb_src, "func _try_hit(").contains("Targets.hit_key(target)"))
	if is_instance_valid(wave):
		wave.queue_free()
	me.queue_free()
	swarm.queue_free()
	await get_tree().process_frame
	print("  the swarm: off the walls, over the back wall, cut by the wave")


# =============================================================================
# THE SLIMES SPEED UP AS THE RUN GOES ON (0.96.0)
# =============================================================================
# The owner: "slimes need a speed buff as things progress". It stopped at 95,
# slower than any class walks; now 6 a stage up to 175, and at the player a
# slime stops instead of sliding through them. And "make sure more then 3
# slimes are attacking the player when surrounded": every one within BITE.
func _test_slimes_speed_up() -> void:
	section("THE SLIMES SPEED UP AND A CROWD IS DEADLY - 6 a stage up to 175, they stop at you, every one within 26 px bites (0.96.0)")
	var Run: GDScript = load("res://src/world/endless/endlessrun.gd") as GDScript
	var rising: bool = true
	for s in range(1, 30):
		if Run.stage_speed(s + 1) < Run.stage_speed(s):
			rising = false
	check("faster every stage until the most: %d at 1, %d at 10, %d from 21" % [int(Run.stage_speed(1)), int(Run.stage_speed(10)),
		int(Run.stage_speed(21))],
		rising and Run.stage_speed(1) >= 53.0 and Run.stage_speed(10) > 80.0 and is_equal_approx(Run.stage_speed(21), Run.SPEED_MOST)
		and is_equal_approx(Run.stage_speed(40), Run.SPEED_MOST))
	var slowest_sprint: float = 140.0 * 1.5
	check("  past the slower classes' walk late on, never the warrior's walk (200) or a sprint (%d)" % int(slowest_sprint),
		Run.stage_speed(16) > 140.0 and Run.SPEED_MOST < 200.0 and Run.SPEED_MOST < slowest_sprint)
	# One slime at the most, walking straight at a still player: it stops at
	# them, never slides through.
	var SwarmScript: GDScript = load("res://src/world/endless/swarm.gd") as GDScript
	var o := Vector2(-64000, -64000)
	var swarm: Node2D = SwarmScript.new()
	swarm.set("arena", Rect2(o, Vector2(800, 600)))
	add_child(swarm)
	swarm.set_process(false)
	swarm.set_physics_process(false)
	await get_tree().process_frame
	swarm.set("speed", Run.SPEED_MOST)
	var player: Vector2 = o + Vector2(400, 300)
	swarm.call("import_alive", PackedInt32Array([0, 1, 50, roundi(player.x - 160.0), roundi(player.y), 0]))
	var nearest: float = INF
	var last: float = INF
	for k in 80:
		swarm.call("_step", player, true)
		last = Vector2(float(swarm.get("px")[0]), float(swarm.get("py")[0])).distance_to(player)
		nearest = minf(nearest, last)
	check("  at the most, one walking at a still player stops at them and stays (nearest %.1f px, last %.1f)" % [nearest, last],
		last <= SwarmScript.TOUCH + 0.5 and nearest >= 4.0 and float(swarm.get("px")[0]) <= player.x, [nearest, last])
	# SURROUNDED IS DEADLY: the owner, "make sure more then 3 slimes are
	# attacking the player when surrounded stopping in a crowd should be
	# deadly". 200 round a still player, then round one walking.
	swarm.call("clear")
	swarm.set("arena", Rect2(o, Vector2(1200, 1000)))
	swarm.set("speed", 110.0)
	player = o + Vector2(600, 500)
	swarm.call("spawn", 200, player)
	var biting: int = 0
	for k in 320:
		swarm.call("_step", player, true)
		if k >= 270:
			biting += int(swarm.get("_touching"))
	var still_bites: float = float(biting) / 50.0
	check("  stood still in a crowd, the two ranks round you bite - %.1f of them (4 or 5 did), at most %d" % [still_bites, SwarmScript.TOUCH_MOST],
		still_bites >= 10.0 and SwarmScript.TOUCH_MOST > 5 and SwarmScript.BITE > SwarmScript.TOUCH, still_bites)
	var centre: Vector2 = player
	biting = 0
	for k in 200:
		var turn: float = float(k) * SwarmScript.STEP * 150.0 / 200.0
		player = centre + Vector2(cos(turn), sin(turn)) * 200.0
		swarm.call("_step", player, true)
		if k >= 100:
			biting += int(swarm.get("_touching"))
	var moving_bites: float = float(biting) / 100.0
	check("  and one who keeps walking leaves most of them behind (%.1f biting)" % moving_bites, moving_bites < 5.0, moving_bites)
	swarm.queue_free()
	await get_tree().process_frame
	print("  the slimes: faster each stage, stopping at you, deadly round you")


func _test_a_boss_keeps_its_health_when_the_lead_moves() -> void:
	section("A BOSS KEEPS ITS HEALTH WHEN ITS FIGHT CHANGES HANDS (0.96.1)")
	# The owner: "i was playing with a friend we both were killing the bosses
	# he died and boss recharged full hp". His friend's game ran the boss; it
	# fell, and the owner's copy took over at a scale of 1.0, so its first
	# raise_for_scale() raised the already-raised boss again and added the
	# difference as health.
	var Sync := preload("res://src/world/monstersync.gd")
	var world := Node2D.new()
	add_child(world)
	var me: Node2D = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate() as Node2D
	me.set_physics_process(false)
	world.add_child(me)
	var bosses: Array = []
	for i in 2:
		var b: Node2D = (load("res://scene/enemy/lightboss.tscn") as PackedScene).instantiate() as Node2D
		world.add_child(b)
		bosses.append(b)
	await get_tree().process_frame
	var base: int = int(bosses[0].max_hp)
	# Two level-22s on the Light boss: 4.6 x 1.6 = 7.36 times, 70% done.
	var two: float = BossEnemy.scale_for(Element.Type.LIGHT, [22, 22])
	var told_max: int = roundi(base * two)
	var told_hp: int = roundi(told_max * 0.3)
	var sync: Node = Sync.new()
	for b in bosses:
		b.set_physics_process(false)
		b.net_set_mirror(true)
	# One copy hears the leader raise it ("mh"); the other walked in late and
	# was sent everything (a record).
	bosses[0].net_rescale(told_max, told_hp)
	sync.call("_apply_record", bosses[1], {"x": bosses[1].global_position.x,
		"y": bosses[1].global_position.y, "a": "", "hp": told_hp, "mh": told_max}, true)
	sync.free()
	var ways: Array = ["told by the leader", "sent everything on arrival"]
	for k in 2:
		var b: Node2D = bosses[k]
		check("a copy %s knows how far the fight raised it (%.2f times)" % [ways[k], two],
			is_equal_approx(float(b.health_scale), float(told_max) / float(base)), [b.health_scale, two])
		# The leader falls: this game takes the fight over, one level-22 left.
		me.global_position = b.global_position + Vector2(0, 60)
		me.set("level", 22)
		b.net_set_mirror(false)
		b.set("player", me)
		b.set("engaged", true)
		b.set("gated", false)
		b.call("raise_for_scale")
		check("  taking it over with one fighter left: not healed (%d of %d)" % [int(b.hp), int(b.max_hp)],
			int(b.hp) == told_hp and int(b.max_hp) == told_max, [b.hp, b.max_hp, told_hp, told_max])
		b.set("engaged", false)
		b.hp = int(b.max_hp)
		b.call("unscale")
		check("  and home, whole, out of the fight: itself again",
			int(b.max_hp) == base and is_equal_approx(float(b.health_scale), 1.0), [b.max_hp, base])
	world.queue_free()
	await get_tree().process_frame
	print("  a boss: its health is the fight's, whoever's game runs it")
