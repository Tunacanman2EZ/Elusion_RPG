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


func _test_levers_have_arrows() -> void:
	section("AN ARROW OVER EVERY LEVER WHILE ITS DOORS ARE SHUT (0.97.0)")
	# The owner: "we also need to put arrows above levers in the game so players
	# can see".
	var door_script := GDScript.new()
	door_script.source_code = "extends Node2D\nvar raised: bool = false\nfunc set_raised(r: bool) -> void:\n\traised = r\n"
	door_script.reload()
	var world := Node2D.new()
	add_child(world)
	var door := Node2D.new()
	door.name = "door"
	door.set_script(door_script)
	world.add_child(door)
	var packed: PackedScene = load("res://scene/interactables/lever.tscn") as PackedScene
	var outside: Node = packed.instantiate()
	outside.set("targets", [NodePath("../door")] as Array[NodePath])
	world.add_child(outside)
	var inside: Node = packed.instantiate()
	inside.set("targets", [NodePath("../door")] as Array[NodePath])
	inside.set("inverted", false)
	world.add_child(inside)
	var once: Node = packed.instantiate()
	once.set("one_shot", true)
	world.add_child(once)
	await get_tree().process_frame
	var a_out: Node2D = outside.get("arrow")
	var a_in: Node2D = inside.get("arrow")
	check("every lever has an arrow, its tip just over the handle, and unshaded (the Field's dark)",
		a_out != null and a_in != null and once.get("arrow") != null and a_out.position.y < -3.0
		and (a_out.material as CanvasItemMaterial) != null
		and (a_out.material as CanvasItemMaterial).light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED, a_out)
	check("  shown while the doors it drives are shut", a_out.visible and a_in.visible and bool(door.get("raised")))
	outside.call("throw")
	await get_tree().create_timer(0.45).timeout
	check("pulled: the doors open and both levers' arrows go (the partner follows)",
		not bool(door.get("raised")) and not a_out.visible and not a_in.visible, [door.get("raised"), a_out.visible, a_in.visible])
	inside.call("throw")
	await get_tree().create_timer(0.45).timeout
	check("  pulled shut again from the other side: both arrows are back",
		bool(door.get("raised")) and a_out.visible and a_in.visible)
	var a_once: Node2D = once.get("arrow")
	check("a one-shot lever with no doors points until it is pulled", a_once.visible)
	once.call("throw")
	await get_tree().create_timer(0.45).timeout
	check("  and not once it is spent", not a_once.visible)
	var y0: float = a_out.position.y
	var moved: bool = false
	for i in 20:
		await get_tree().process_frame
		if not is_equal_approx(a_out.position.y, y0):
			moved = true
	check("  it bobs, a whole pixel at a time", moved and is_equal_approx(a_out.position.y, roundf(a_out.position.y)))
	world.queue_free()
	await get_tree().process_frame
	print("  levers: an arrow over each, while there is something to open")


func _test_the_swell() -> void:
	section("THE SWELL: A STIRRING LAND'S MONSTERS, MORE OF THEM, REAL ONES (0.97.1)")
	# The owner: "lets make the tests into a real feature that changes with the
	# land we can customize it more in hud".
	const SwellScript := preload("res://src/world/swell.gd")
	const SyncScript := preload("res://src/world/monstersync.gd")
	# ---- what the server says ----
	var stir := {"element": Element.Type.WATER, "tick": 40, "started_at": 0, "ends_at": int(Time.get_unix_time_from_system()) + 3600,
		"hit": 0.25, "health": 0.5, "speed": 0.15, "resist": 1.5, "bags": 1.5, "xp": 0.0, "swell": 3,
		"now": int(Time.get_unix_time_from_system())}
	Lands.apply(stir)
	check("the poll's world says how many of each: 3", Lands.swell_size() == 3, Lands.swell_size())
	check("  and the HUD's line says where the land is", Lands.line().begins_with("The Water lands stir in the Chasm, north - "),
		Lands.line())
	var older: Dictionary = stir.duplicate()
	older.erase("swell")
	older["tick"] = 41
	Lands.apply(older)
	check("  a server from before it: 1, none added", Lands.swell_size() == 1)
	var junk: Dictionary = stir.duplicate()
	junk["swell"] = 99
	junk["tick"] = 42
	Lands.apply(junk)
	check("  more than four: held to four", Lands.swell_size() == 4)
	Lands.clear()
	check("  nothing stirring: 1", Lands.swell_size() == 1 and Lands.line() == "")
	# ---- each land's wing is where the plan put it ----
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/maps/bigfield_build.json"))
	var astray: Array = []
	if plan is Dictionary:
		var tile: float = float(plan.get("tile", 16))
		var names := {Element.Type.LIGHT: "light", Element.Type.WIND: "wind", Element.Type.WATER: "water",
			Element.Type.ICE: "ice", Element.Type.EARTH: "earth", Element.Type.FIRE: "fire", Element.Type.DARK: "dark"}
		for land in names:
			var wing: String = str(Lands.WINGS[land][0]).trim_prefix("the ").to_lower()
			var box: Array = plan["wings"].get(wing, {}).get("box", [])
			for m in plan["monsters"]:
				if str(m.get("land", "")) != names[land]:
					continue
				var inside: bool = box.size() == 4 and float(m["x"]) >= float(box[0]) * tile and float(m["x"]) <= float(box[2]) * tile \
					and float(m["y"]) >= float(box[1]) * tile and float(m["y"]) <= float(box[3]) * tile
				if not inside:
					astray.append([names[land], wing, m["x"], m["y"]])
	check("every land's Big Field monsters stand in the wing the line names (bigfield_build.json)",
		plan is Dictionary and astray.is_empty(), astray.slice(0, 4))
	# ---- the swell in an area ----
	var area := Node2D.new()
	area.scene_file_path = SwellScript.AREA
	add_child(area)
	# Floor under all of it: the swell stands its monsters on the navigation.
	var floor_region := NavigationRegion2D.new()
	var floor_shape := NavigationPolygon.new()
	floor_shape.vertices = PackedVector2Array([Vector2(0, 0), Vector2(1400, 0), Vector2(1400, 900), Vector2(0, 900)])
	floor_shape.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	floor_region.navigation_polygon = floor_shape
	area.add_child(floor_region)
	var holder := Node2D.new()
	holder.name = "enemies"
	area.add_child(holder)
	var water: Node2D = (load("res://scene/enemy/watersprite.tscn") as PackedScene).instantiate() as Node2D
	water.position = Vector2(400, 400)
	water.set_meta(&"net_origin", "ysortworld/enemies/water_001_watersprite")
	holder.add_child(water)
	var fire: Node2D = (load("res://scene/enemy/firesprite.tscn") as PackedScene).instantiate() as Node2D
	fire.position = Vector2(900, 400)
	fire.set_meta(&"net_origin", "ysortworld/enemies/fire_001_firesprite")
	holder.add_child(fire)
	var size: Array = [3]
	var land: Array = [Element.Type.WATER]
	var mine: Array = [true]
	var swell: Node = SwellScript.add_to(area)
	swell.set("land_now", func() -> int: return land[0])
	swell.set("size_now", func() -> int: return size[0])
	swell.set("authority_now", func() -> bool: return mine[0])
	swell.set("wait_override", 0.2)
	(swell.get("_timer") as Timer).stop()  # the test does the checking, one at a time
	# The navigation takes its floor in a few frames of its own (as the Big
	# Field's does when it loads; the swell's next check catches up then).
	var nav_map: RID = area.get_world_2d().navigation_map
	for i in 120:
		if NavigationServer2D.map_get_closest_point(nav_map, Vector2(430, 400)).distance_to(Vector2(430, 400)) < 1.0:
			break
		await get_tree().physics_frame
	await swell.call("check")
	await get_tree().process_frame
	var swelled: Array = []
	for e in holder.get_children():
		if SwellScript.is_swell(e) and not e.is_queued_for_deletion():
			swelled.append(e)
	var origins: Array = []
	for e in swelled:
		origins.append(str(e.get_meta(&"net_origin", "")))
	origins.sort()
	check("water stirring at 3x: two more of the water monster, none of the fire one, each at a place of its own",
		swelled.size() == 2 and origins == ["ysortworld/enemies/water_001_watersprite#swell1",
			"ysortworld/enemies/water_001_watersprite#swell2"], [origins, swell.call("source_count"), swell.call("copy_count"),
			water.call("current_element"), fire.call("current_element")])
	var pays: bool = true
	var near: bool = true
	for e in swelled:
		pays = pays and str(e.call("get_enemy_id")) != "" and not e.has_meta(&"stress_copy")
		near = near and (e as Node2D).global_position.distance_to(water.global_position) <= SwellScript.SPREAD_MAX + 0.5
	check("  real ones: a kill of one is reported and paid (get_enemy_id), beside the monster they swell",
		pays and near)
	if swelled.size() != 2:
		area.queue_free()
		await get_tree().process_frame
		return
	var first: Node2D = null
	for e in swelled:
		if str(e.get_meta(&"net_origin")).ends_with("#swell1"):
			first = e
	first.emit_signal("died")
	first.queue_free()
	await swell.call("check")
	check("  one killed is not back at once", int(swell.call("copy_count")) == 1, swell.call("copy_count"))
	await get_tree().create_timer(0.35).timeout
	await swell.call("check")
	check("  and is back after its wait, at the same place's number", int(swell.call("copy_count")) == 2
		and _swell_origins(holder, SwellScript).has("ysortworld/enemies/water_001_watersprite#swell1"),
		_swell_origins(holder, SwellScript))
	mine[0] = false
	size[0] = 4
	await swell.call("check")
	check("a game that does not run the area builds none", int(swell.call("copy_count")) == 2)
	mine[0] = true
	await swell.call("check")
	check("  the one that does: 4x is three", int(swell.call("copy_count")) == 3)
	var fighting: Node2D = null
	for e in holder.get_children():
		if str(e.get_meta(&"net_origin", "")).ends_with("#swell1") and not e.is_queued_for_deletion():
			fighting = e
	fighting.set("engaged", true)
	land[0] = Element.Type.FIRE
	await swell.call("check")
	await get_tree().process_frame
	check("the stir moves on: the water ones go - but not one in a fight - and the fire one swells",
		_swell_origins(holder, SwellScript) == ["ysortworld/enemies/fire_001_firesprite#swell1",
			"ysortworld/enemies/fire_001_firesprite#swell2", "ysortworld/enemies/fire_001_firesprite#swell3",
			"ysortworld/enemies/water_001_watersprite#swell1"], _swell_origins(holder, SwellScript))
	fighting.set("engaged", false)
	land[0] = 0
	await swell.call("check")
	await get_tree().process_frame
	check("  out of its fight, it goes too; nothing stirring, none at all", _swell_origins(holder, SwellScript).is_empty(),
		_swell_origins(holder, SwellScript))
	# ---- a game taking the area over carries on with the ones standing ----
	land[0] = Element.Type.WATER
	size[0] = 2
	await swell.call("check")
	swell.queue_free()
	await get_tree().process_frame
	var heir: Node = SwellScript.add_to(area)
	heir.set("land_now", func() -> int: return land[0])
	heir.set("size_now", func() -> int: return size[0])
	heir.set("authority_now", func() -> bool: return true)
	(heir.get("_timer") as Timer).stop()
	await heir.call("check")
	await get_tree().process_frame
	check("a game that takes the area over adopts the swell standing, and builds no second one",
		int(heir.call("copy_count")) == 1 and _swell_origins(holder, SwellScript).size() == 1,
		_swell_origins(holder, SwellScript))
	area.queue_free()
	await get_tree().process_frame
	# ---- the rest of the game makes room for them ----
	check("a follower draws up to %d monsters: dark's 66 at 4x is 480 in the Big Field" % SyncScript.MAX_MONSTERS,
		SyncScript.MAX_MONSTERS >= 282 + 66 * 3)
	var respawner_code: String = _code_src("res://src/world/enemyrespawner.gd")
	check("  the respawner and the stress test leave swell monsters out of what they count",
		respawner_code.contains("&\"swell_copy\"") and _code_src("res://src/world/stresscrowd.gd").contains("&\"swell_copy\""))
	check("  and every area gets a Swell (arearegistry.gd), which acts in the Big Field alone",
		_code_src("res://src/systems/arearegistry.gd").contains("Swell.add_to(scene)") and SwellScript.AREA == "res://scene/bigfield.tscn")
	print("  the swell: real monsters, more of the stirring land's, gone once the stir is over")


func _swell_origins(holder: Node, swell_script: GDScript) -> Array:
	var out: Array = []
	for e in holder.get_children():
		if swell_script.call("is_swell", e) and not e.is_queued_for_deletion():
			out.append(str(e.get_meta(&"net_origin", "")))
	out.sort()
	return out


func _test_the_healers_run() -> void:
	section("THE HEALER'S RUN: A SHOOTER WITH THE HEALER AS THE SHIP, STEP 1 (0.98.0)")
	# The owner: "healer is constantly walking forward in a loop basically add
	# some upgrades drop some enemies", "first power up 2 bullets then 4 then 6
	# the 8", "make the path wider".
	const RunScript := preload("res://src/world/healerrun/healerrun.gd")
	const ScreenScript := preload("res://src/world/healerrun/healerrunscreen.gd")
	# ---- her shots ----
	var counts: Array = []
	var even: bool = true
	for n in RunScript.SHOT_STEPS:
		var volley: Array = RunScript.shot_offsets(int(n))
		counts.append(volley.size())
		var sum := Vector2.ZERO
		for shot in volley:
			sum += Vector2(float(shot[0]), float(shot[1]))
		even = even and sum.is_zero_approx()
	check("her shots: 1, then 2, 4, 6 and 8, each volley even either side",
		RunScript.SHOT_STEPS == [1, 2, 4, 6, 8] and counts == [1, 2, 4, 6, 8] and even, counts)
	check("  two side by side and straight up, then a pair fanning wider each step",
		RunScript.shot_offsets(2) == [[-4.0, 0.0], [4.0, 0.0]]
		and absf(float(RunScript.shot_offsets(8)[7][1])) > absf(float(RunScript.shot_offsets(6)[5][1])))
	# ---- the hidden rank ----
	check("harder with rank: tougher, faster bullets, quicker to shoot, bigger waves, waves sooner (never under 6 s)",
		RunScript.foe_health(3.0, 5) > RunScript.foe_health(3.0, 0) and RunScript.bullet_speed(6) > RunScript.bullet_speed(0)
		and RunScript.fire_gap(2.0, 6) < RunScript.fire_gap(2.0, 0) and RunScript.fire_gap(2.0, 99) >= 1.0
		and RunScript.group_extra(9) > RunScript.group_extra(0) and RunScript.wave_time(4) < RunScript.wave_time(0)
		and RunScript.wave_time(99) >= 6.0)
	# ---- every land has its monsters ----
	var missing: Array = []
	for land in RunScript.LANDS:
		for table in [RunScript.SPRITES, RunScript.MAGES, RunScript.SNIPERS, RunScript.BOSSES, RunScript.SLIMES]:
			var id: String = str(table.get(land, ""))
			if id != "" and not ResourceLoader.exists("res://scene/enemy/%s.tscn" % id):
				missing.append(id)
			elif id == "" and table != RunScript.SLIMES:
				missing.append("%s: none" % land)
	check("every land has a sprite, a mage, a sniper and a boss of its own in the game (and a slime, or a sprite instead)",
		missing.is_empty(), missing)
	var look: Dictionary = RunScript.look_of_scene("res://scene/enemy/windsprite.tscn")
	var her: Dictionary = RunScript.look_of_scene(RunScript.HEALER_SCENE, false)
	check("  each drawn as the world draws it - the game's own frames and its land's colour; the healer read, never made",
		look.get("frames") is SpriteFrames and look.get("material") is ShaderMaterial and her.get("frames") is SpriteFrames
		and (her["frames"] as SpriteFrames).has_animation("walkup"))
	# ---- a run ----
	var run = RunScript.new()
	run.set("seed_value", 77)
	run.set("steer", func() -> Vector2: return Vector2.ZERO)
	add_child(run)
	run.set_process(false)
	check("a run starts ready: 3 lives, one shot, nothing yet, and says so",
		run.state == RunScript.State.READY and run.lives == 3 and run.power == 0 and run.foes.get_child_count() == 0
		and run.banner == "Get ready")
	# The owner: "we want the healer to be standing on a platform not walking
	# in from the black".
	var under_her: Vector2i = Vector2i(0, floori((RunScript.HALF.y - 4.0) / RunScript.TILE))
	var walls_behind: int = 0
	for piece in run.props.get_children():
		if str(piece.scene_file_path).contains("wallrun") and (piece as Node2D).position.y > RunScript.HALF.y - 10.0:
			walls_behind += 1
	check("  standing on a landing: floor to the screen's bottom, the crypt's wall behind her, and she stands still",
		run.floor_layer.get_cell_source_id(under_her) != -1 and walls_behind == 5
		and run.healer_sprite.animation == &"idleup", [walls_behind, run.healer_sprite.animation])
	var standing_at: float = run.scrolled
	for i in 60:
		run.step(1.0 / 60.0)
	check("  and the path does not move while she gets ready", run.scrolled == standing_at, run.scrolled)
	for i in 60:
		run.step(1.0 / 60.0)
	var first: Array = []
	for f in run.foes.get_children():
		first.append(f.kind)
	check("  then she walks, and the first wave comes: a V of seven sprites of the first land, the land named",
		run.state == RunScript.State.RUNNING and first.size() == 7 and first.count("sprite") == 7
		and run.banner.begins_with("Tier 1 - the ") and run.healer_sprite.animation == &"walkup", [first, run.banner])
	var slow: float = run.scroll_speed()
	run.run_seconds += 120.0
	var later: float = run.scroll_speed()
	run.run_seconds -= 120.0
	check("THE GROUND SPEEDS UP A LITTLE AT A TIME: two minutes on, %.0f px/s faster, never past %d" % [later - slow,
		RunScript.SCROLL_MOST], later - slow > 10.0 and later - slow < 14.0 and RunScript.SCROLL_MOST < 100.0)
	check("THE PATH IS WIDER: 480 of the view's 640, walled both sides", RunScript.PATH_HALF * 2.0 == 480.0)
	var cells_then: int = run.floor_layer.get_used_cells().size()
	for i in 60 * 40:
		run.lives = 3
		run.untouchable = 1.0
		run.step(1.0 / 60.0)
	var cells_now: int = run.floor_layer.get_used_cells().size()
	check("the scene moves, not her: the floor laid ahead and taken up behind, never more than a screen and a bit",
		run.scrolled > 1000.0 and cells_now <= 40 * 30 and cells_then > 0, [run.scrolled, cells_then, cells_now])
	var before: int = run.shots_flying()
	run.power = 2
	run.call("_fire", RunScript.SHOT_GAP)
	check("at four shots, a volley is four", run.shots_flying() - before == 4, run.shots_flying() - before)
	run.gain_power()
	run.gain_power()
	run.gain_power()
	check("  and power-ups stop at eight", run.power == 4 and int(RunScript.SHOT_STEPS[run.power]) == 8)
	run.laser_level = 0
	run.laser = 0.0
	run.gain_power()
	check("  past it, a power-up is the laser for a while (the owner: \"lets add a laser\")",
		run.power == 4 and run.laser == RunScript.LASER_SECONDS and run.laser_level == 1 and run.banner == "Laser 1")
	var in_line: Node2D = run.call("_foe", "mage", run.healer.position + Vector2(0.0, -120.0))
	in_line.set("velocity", Vector2.ZERO)
	in_line.set("stop_y", -999.0)
	var was_health: float = in_line.get("health")
	run.call("_shine", 0.5)
	check("  a beam straight up from her, through what stands in it", run.beam.visible
		and float(in_line.get("health")) < was_health - RunScript.LASER_DPS * 0.4, [was_health, in_line.get("health")])
	# "add layers to the lasers add some color more upgrades should make you stronger".
	var rank_at_one: int = run.rank()
	for i in 6:
		run.gain_power()
	check("each power-up after is a laser level, to seven: wider, harder, longer, side beams, and the rank with it",
		run.laser_level == RunScript.LASER_LEVELS and RunScript.LASER_LEVELS == 7 and run.laser == RunScript.laser_seconds(7)
		and is_equal_approx(RunScript.laser_dps(5), RunScript.LASER_DPS * (1.0 + 4.0 * RunScript.LASER_PER_LEVEL))
		and RunScript.laser_half(5) > RunScript.laser_half(1)
		and RunScript.side_beams(2).is_empty() and RunScript.side_beams(3).size() == 2 and RunScript.side_beams(5).size() == 4
		and run.rank() >= mini(RunScript.RANK_MOST, rank_at_one + 4) and run.banner == "Laser 7",
		[run.laser_level, run.rank(), rank_at_one])
	check("  a layer of colour for each level, and red in the middle of the best one",
		RunScript.LASER_COLOURS.size() == RunScript.LASER_LEVELS and RunScript.LASER_HEART.r > 0.9
		and RunScript.LASER_HEART.g < 0.3)
	check("  her shots and the monsters' bullets are drawn over the laser, never hidden in it",
		run.beam.z_index < run.get_node("shots").z_index and run.beam.z_index < run.field.z_index)
	# "bullets need to be an addition to laser the do not overlap".
	var apart: bool = true
	for level in [1, 3, 5, 6, 7]:
		run.laser_level = level
		run.laser = 5.0
		var first_shot: int = run.shots_flying()
		run.call("_fire", RunScript.SHOT_GAP)
		var edge: float = run.laser_edge()
		for k in range(first_shot, run.shots_flying()):
			apart = apart and absf(run._shot_pos[k].x - run.healer.position.x) > edge
		apart = apart and run.shots_flying() - first_shot == 8
	check("  with the laser on, all eight shots start beside it, past its outer edge - at every level", apart)
	run.laser_level = 5
	run.laser = 5.0
	run.untouchable = 0.0
	var lives_then: int = run.lives
	run.hurt()
	check("  a hit takes a laser level before a shot step", run.laser_level == 4 and run.power == 4
		and run.lives == lives_then - 1)
	run.lives = lives_then
	run.laser_level = 0
	run.laser = 0.0
	run.call("_shine", 0.0)
	# THE METEOR: "we can loot a meteor for a special weapon for the bosses",
	# "just press space to fire meteor will auto lock".
	check("no meteor held, Space does nothing", not run.fire_meteor())
	run.gain_meteor()
	run.gain_meteor()
	run.gain_meteor()
	run.gain_meteor()
	var tough: Node2D = run.meteor_target()
	check("  a meteor picked up is held (up to three); it locks on the toughest monster standing",
		run.meteors == RunScript.METEORS_MOST and tough != null, tough)
	var tough_health: float = tough.get("health")
	check("  and Space calls it down", run.fire_meteor() and run.meteors == RunScript.METEORS_MOST - 1)
	for i in 40:
		run.untouchable = 1.0
		run.step(1.0 / 60.0)
	check("  where it lands it strikes", not is_instance_valid(tough) or float(tough.get("health")) < tough_health
		or float(tough.get("dying")) >= 0.0)
	# ARCS SWING DEEP: "the enemies on the left and right do not sway far enough into the map".
	var arc: Node2D = run.call("_foe", "sprite", Vector2(RunScript.PATH_HALF + 16.0, -150.0))
	arc.set("side", 1.0)
	arc.set("path", "arc")
	arc.set("velocity", Vector2(-RunScript.ARC_IN, 70.0))
	arc.set("shoot_in", 99.0)
	var deepest: float = 999.0
	for i in 180:
		run.untouchable = 1.0
		run.call("_move_foes", 1.0 / 60.0)
		if is_instance_valid(arc) and arc.get_parent() != null:
			deepest = minf(deepest, absf(arc.position.x))
	check("an arc swings deep into the path - %d px in from the wall" % int(RunScript.PATH_HALF - deepest),
		RunScript.PATH_HALF - deepest >= 150.0, deepest)
	var kinds_made: Dictionary = {}
	for kind in ["snake", "pincer", "ring", "wall"]:
		kinds_made[kind] = run.spawn_wave(kind).size()
	check("more formations: a snake, a pincer, a ring and a wall of slimes with a way through",
		RunScript.WAVE_KINDS.size() == 10 and kinds_made["snake"] >= 8 and kinds_made["pincer"] >= 10
		and kinds_made["ring"] >= 8 and kinds_made["wall"] >= 8, kinds_made)
	# GOLD: "gold should be rewarded on the screen then moved to char when hitting leave".
	var waves_were: int = run.waves_done
	run.waves_done = 7
	var seven: int = run.gold_now()
	run.waves_done = 10
	run.bosses_beaten = 1
	var ten_and_one: int = run.gold_now()
	run.bosses_beaten = 0
	run.waves_done = waves_were
	check("the gold on screen, by tier: seven waves are 70; ten waves and the first boss 80 + 50 + 120 (up to 20,000)",
		seven == 70 and ten_and_one == 80 + 50 + 120 and RunScript.DEFAULT_PAYS["most"] == 20000, [seven, ten_and_one])
	check("more power-ups: a mage drops one nearly half the time, and never more than 12 kills without one",
		float(RunScript.KINDS["mage"]["power"]) >= 0.4 and RunScript.POWER_PITY <= 12)
	var waves_then: int = run.foes.get_child_count()
	var tier_was: int = run.tier
	var wave_was: int = run.wave_in_tier
	run.tier = 0
	run.wave_in_tier = 0
	var cool: int = run.heat()
	run.wave_in_tier = 4
	var half_way: int = run.heat()
	run.tier = 1
	run.wave_in_tier = 0
	var next_tier: int = run.heat()
	run.wave_in_tier = 4
	var full_size: int = mini(13, 7 + run.crowd())
	var both: Array = run.spawn_wave("vee", 0.5)
	run.tier = tier_was
	run.wave_in_tier = wave_was
	check("THE NEXT TIER STARTS HOTTER: heat 0, 1 half way through the first, 2 at the second's start",
		cool == 0 and half_way == 1 and next_tier == 2, [cool, half_way, next_tier])
	check("  more monsters: a V is seven, and one more each heat; one alongside another comes at half its size",
		full_size >= 7 and both.size() == roundi(full_size * 0.5) and run.foes.get_child_count() == waves_then + both.size()
		and RunScript._sized(3, 0.5) == 2, [full_size, both.size()])
	var slain_then: int = run.slain
	var target: Node2D = run.call("_foe", "sprite", run.healer.position + Vector2(0.0, -90.0))
	target.set("health", 1.0)
	target.set("velocity", Vector2.ZERO)
	for i in 20:
		run.untouchable = 1.0
		run.step(1.0 / 60.0)
	check("a monster in front of her is shot down and counted", run.slain > slain_then, [slain_then, run.slain])
	# ---- lives ----
	run.untouchable = 0.0
	run.lives = 3
	run.power = 3
	run.laser_level = 0
	run.field.spawn(Vector2(0, -100), PI / 2.0, 10.0, Color.WHITE)
	run.hurt()
	check("one hit is one life: she blinks, a shot step goes, and the screen's bullets with it",
		run.lives == 2 and run.power == 2 and run.untouchable > 0.0 and run.field.count == 0)
	run.hurt()
	check("  and while she blinks nothing more is taken", run.lives == 2)
	for i in 4:
		run.gain_life()
	check("a potion is a life more, held to five", run.lives == RunScript.LIVES_MOST)
	run.lives = 2
	# Nothing else about that might drop a potion of its own as it is shot.
	for f in run.foes.get_children():
		run.foes.remove_child(f)
		f.queue_free()
	for d in run.drops.get_children():
		run.drops.remove_child(d)
		d.queue_free()
	run.call("_drop", "potion", run.healer.position + RunScript.HITBOX_AT)
	run.step(1.0 / 60.0)
	check("  and one she walks into is picked up", run.lives == 3, run.lives)
	# "when moving backwerds could not pick up the drop".
	run.call("_drop", "potion", run.healer.position + Vector2(0.0, 30.0))
	for i in 20:
		run.step(1.0 / 60.0)
	check("  one just behind her is drawn to her and picked up too", run.lives == 4, run.lives)
	run.lives = 3
	# "we need to balance out the lasers now".
	var full_laser: float = RunScript.laser_dps(5) * (1.0 + 4.0 * RunScript.SIDE_BEAM_SHARE)
	check("the laser balanced: a full laser and its side beams do %d a second (it was about 300)" % int(full_laser),
		full_laser < 150.0 and RunScript.laser_dps(1) < 30.0 and RunScript.laser_seconds(5) <= 10.0, full_laser)
	# THE FIRE BEHIND HER (the owner: "maybe a fire from behind"; then "the
	# fire at the bottom gets a bit taller and upgrades push it back down").
	var lives_before: int = run.lives
	run.untouchable = 0.0
	var then_seconds: float = run.run_seconds
	var tier_then: int = run.tier
	run.tier = 0
	run.fire_height = 0.0
	run.set("_fire_push", 0.0)
	run.run_seconds = RunScript.FIRE_AFTER - 1.0
	run.call("_burn", 10.0)
	var none_yet: bool = run.fire_height == 0.0 and not run.fire_glow.visible
	run.run_seconds = RunScript.FIRE_AFTER + 1.0
	run.healer.position.y = RunScript.HALF.y - 12.0
	run.call("_burn", 60.0)
	check("from %d s a fire rises behind her - %.0f px a minute in the first tier - and standing in it costs a life"
		% [RunScript.FIRE_AFTER, run.fire_height],
		none_yet and is_equal_approx(run.fire_height, 60.0 * RunScript.FIRE_RISE) and run.fire_glow.visible
		and run.lives == lives_before - 1 and run.healer.position.y < run.fire_top(), [run.fire_height, run.lives])
	run.healer.position.y = 0.0
	run.call("_burn", 9999.0)
	var tallest: float = run.fire_height
	# The second tier (the last climbs higher: _test_the_healers_run_gets_wilder).
	run.tier = 1
	run.fire_height = 0.0
	run.call("_burn", 60.0)
	var faster: float = run.fire_height
	run.call("_burn", 9999.0)
	var power_then: int = run.power
	run.gain_power()
	for i in 60:
		run.call("_burn", 1.0 / 60.0)
	var pushed_to: float = run.fire_height
	check("  taller now - held to %d (it was 64), climbing faster each tier - and a power-up pushes it back %d"
		% [int(RunScript.FIRE_MOST), int(RunScript.FIRE_PUSH)],
		RunScript.FIRE_MOST > 64.0 and tallest == RunScript.FIRE_MOST and faster > 60.0 * RunScript.FIRE_RISE
		and pushed_to < RunScript.FIRE_MOST - RunScript.FIRE_PUSH + 1.0 and pushed_to > RunScript.FIRE_MOST - RunScript.FIRE_PUSH - 2.0,
		[tallest, faster, pushed_to])
	run.power = power_then
	run.tier = tier_then
	run.run_seconds = then_seconds
	run.fire_height = 0.0
	run.set("_fire_push", 0.0)
	run.lives = 2
	var pushed: Vector2 = RunScript._pushed_out(Vector2(5, 5), 2.0, Rect2(0, 0, 20, 8))
	check("a pillar's foot stops her: put out the shortest way", pushed == Vector2(5, 10), pushed)
	# ---- a boss each tier ("lets progress tiers after round 8 to the next difficulty diff boss") ----
	for left in run.foes.get_children():
		left.queue_free()
	for drop in run.drops.get_children():
		drop.queue_free()
	await get_tree().process_frame
	run.state = RunScript.State.RUNNING
	run.tier = 0
	run.wave_in_tier = RunScript.WAVES_PER_TIER - 1
	run.waves_done = RunScript.WAVES_PER_TIER - 1
	run.bosses_beaten = 0
	run.call("_next_wave")
	var first_keeper: Node2D = run.boss
	var first_land: int = run.land()
	check("the eighth wave passed, the first land's keeper: its boss, its name, %d health before rank (the last %d)"
		% [int(RunScript.BOSS_HEALTH[0]), int(RunScript.BOSS_HEALTH[2])],
		run.state == RunScript.State.BOSS and first_keeper != null and run.waves_done == RunScript.WAVES_PER_TIER
		and run.banner == "The %s keeper" % run.land_name(first_land)
		and is_equal_approx(float(first_keeper.get("most")), RunScript.foe_health(RunScript.BOSS_HEALTH[0], run.rank()))
		and RunScript.BOSS_HEALTH[0] < RunScript.BOSS_HEALTH[1] and RunScript.BOSS_HEALTH[1] < RunScript.BOSS_HEALTH[2]
		and run.adds_gap() > RunScript.BOSS_ADDS_SECONDS, [run.banner, first_keeper.get("most")])
	var hangers_on: Array = run.spawn_wave("vee", 0.5)
	var slain_at_boss: int = run.slain
	run.call("_strike", first_keeper, float(first_keeper.get("most")) + 1.0)
	var spoils: Array = []
	for drop in run.drops.get_children():
		spoils.append(str(drop.get_meta(&"drop", "")))
	var all_burst: bool = true
	for f in hangers_on:
		all_burst = all_burst and float(f.get("dying")) >= 0.0
	check("  beaten: its crowd bursts with it, it leaves a power-up and a potion, and the next tier starts in the next land",
		run.state == RunScript.State.RUNNING and run.bosses_beaten == 1 and run.tier == 1 and run.wave_in_tier == 0
		and run.boss == null and all_burst and run.slain == slain_at_boss + 1 + hangers_on.size()
		and spoils.has("power") and spoils.has("potion") and run.land() != first_land
		and run.banner == "Tier 2 - the %s lands" % run.land_name(run.land()) and run.heat() == 2
		and run.shake > 0.0, [run.state, run.tier, spoils, run.banner])
	# ---- the gate and the goal ----
	var won: Array = []
	run.finished.connect(func(did_win: bool) -> void: won.append(did_win))
	for left in run.foes.get_children():
		left.queue_free()
	for drop in run.drops.get_children():
		drop.queue_free()
	await get_tree().process_frame
	run.tier = RunScript.TIERS - 1
	run.waves_done = RunScript.TIERS * RunScript.WAVES_PER_TIER
	run.bosses_beaten = RunScript.TIERS - 1
	run.call("_start_boss")
	var gate_meteor: bool = false
	for drop in run.drops.get_children():
		gate_meteor = gate_meteor or str(drop.get_meta(&"drop", "")) == "meteor"
	check("after the last tier, the gate: its keeper is the third land's boss, at full health, and a meteor falls ahead",
		run.state == RunScript.State.BOSS and run.boss != null and is_equal_approx(run.boss_share(), 1.0) and gate_meteor
		and run.banner == "The gate - and its keeper" and run.adds_gap() == RunScript.BOSS_ADDS_SECONDS)
	run.meteors = 1
	check("  Space locks on the boss", run.meteor_target() == run.boss and run.fire_meteor())
	for i in 40:
		run.untouchable = 1.0
		run.call("_meteors_fall", 1.0 / 60.0)
	check("  and takes a sixth of its health or so", run.boss_share() <= 1.0 - RunScript.METEOR_BOSS_SHARE + 0.001,
		run.boss_share())
	# "we need more enemies finishing should be pretty challenging".
	check("the finish is hard: the keeper has %d health before rank, waves come within %d s at most, a third wave late on"
		% [int(RunScript.BOSS_HEALTH[2]), int(RunScript.wave_time(0))],
		float(RunScript.BOSS_HEALTH[2]) >= 2400.0 and RunScript.wave_time(0) <= 12.0
		and RunScript.wave_time(99) == 6.0 and RunScript.THIRD_CHANCE > 0.0)
	var before_adds: int = run.foes.get_child_count()
	for i in int((RunScript.BOSS_ADDS_SECONDS + 0.5) * 60.0):
		run.untouchable = 1.0
		run.call("_boss_step", 1.0 / 60.0)
	check("  every few seconds it calls a wave to its side", run.foes.get_child_count() > before_adds,
		[before_adds, run.foes.get_child_count()])
	run.boss.health = run.boss.most * 0.4
	run.set("_boss_casting", 1)
	run.set("_boss_shots", 5.0)
	run.call("_boss_step", 1.0 / 60.0)
	check("  and under half its health it is enraged", run.enraged and run.banner == "The keeper is enraged")
	run.call("_strike", run.boss, run.boss.most + 1.0)
	check("  killed, the way is open and the goal marker laid ahead", run.state == RunScript.State.GOAL and run.goal != null
		and run.goal.get_child_count() >= 3)
	for i in 60 * 30:
		if run.state != RunScript.State.GOAL:
			break
		run.untouchable = 1.0
		run.step(1.0 / 60.0)
	check("  and walking to it wins the run - in the time it took - and the whole 20,000",
		run.state == RunScript.State.WON and won == [true] and run.result_text().begins_with("Cleared in ")
		and run.gold_now() == 20000 and run.bosses_beaten == 3, [run.state, won, run.result_text(), run.gold_now()])
	run.queue_free()
	var lost = RunScript.new()
	lost.set("seed_value", 3)
	add_child(lost)
	lost.set_process(false)
	for i in 120:
		lost.step(1.0 / 60.0)
	lost.lives = 1
	lost.untouchable = 0.0
	lost.hurt()
	check("the last life gone: the run is over, and says how far it got",
		lost.state == RunScript.State.LOST and lost.result_text().begins_with("Fell in tier 1, wave 1"), lost.result_text())
	lost.queue_free()
	var at_keeper = RunScript.new()
	at_keeper.set("seed_value", 5)
	add_child(at_keeper)
	at_keeper.set_process(false)
	at_keeper.tier = 1
	at_keeper.call("_start_boss")
	at_keeper.lives = 1
	at_keeper.untouchable = 0.0
	at_keeper.state = RunScript.State.BOSS
	at_keeper.hurt()
	check("  fallen to a keeper, it says which", at_keeper.result_text().begins_with("Fell to the %s keeper in tier 2"
		% at_keeper.land_name(at_keeper.land())), at_keeper.result_text())
	at_keeper.queue_free()
	# ---- on screen ----
	var stand_in := Node2D.new()
	stand_in.add_to_group("player")
	add_child(stand_in)
	var screen = ScreenScript.open(get_tree(), 9)
	await get_tree().process_frame
	check("the screen opens over everything with the run in a world of its own, and the character waits, still",
		screen.layer == ScreenScript.LAYER and screen.run != null and screen.viewport.world_2d != get_viewport().world_2d
		and stand_in.process_mode == Node.PROCESS_MODE_DISABLED)
	check("  the first run opens on the tutorial (\"a tutorial screen also before char walks\"), the run held behind it",
		screen.tutorial.visible and not screen.run.is_processing())
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	screen._input(space)
	check("  Space starts it", not screen.tutorial.visible and screen.run.is_processing())
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	screen._input(escape)
	check("  Escape asks first while a run is on", is_instance_valid(screen) and not screen.is_queued_for_deletion()
		and screen.leave_button.text == "Sure?")
	screen.ask_to_leave()
	await get_tree().process_frame
	check("  and the second time leaves - the character let go", not is_instance_valid(screen)
		and stand_in.process_mode == Node.PROCESS_MODE_INHERIT)
	# LEAVE PAYS: a run the server knows is finished there, its gold paid.
	var paid: Array = []
	var paying = ScreenScript.open(get_tree(), 4, 77, {"wave_gold": [10, 16, 24, 30, 40], "waves_per_stretch": 5,
		"boss_gold": 150, "goal_gold": 250, "most": 1000, "tiers": {"wave_gold": [10, 25, 100], "waves_per_tier": 8,
		"boss_gold": [120, 300, 1500], "goal_gold": 2000, "most": 5000}})
	paying.finish_request = func(path: String, body: Dictionary, _wait: float) -> Dictionary:
		paid.append([path, body])
		return {"ok": true, "status": 200, "data": {"gold": 26, "status": {"gold": 1026}}}
	await get_tree().process_frame
	var counted_by: Dictionary = paying.run.pays.duplicate()
	paying.run.waves_done = 9
	paying.run.bosses_beaten = 1
	paying.leave()
	await get_tree().process_frame
	check("Leave finishes the run on the server - how far it got, the bosses down - and goes; counted by the server's tiers",
		paid.size() == 1 and paid[0][0] == "/api/minigames/finish" and paid[0][1] == {"run": 77, "waves": 9,
		"bosses": 1, "goal": false} and not is_instance_valid(paying) and counted_by.get("most") == 5000
		and RunScript.pays_from({"most": 1000}) == RunScript.DEFAULT_PAYS, [paid, counted_by])
	var refused = ScreenScript.open(get_tree(), 5, 78)
	refused.finish_request = func(_path: String, _body: Dictionary, _wait: float) -> Dictionary:
		return {"ok": false, "status": 0}
	await get_tree().process_frame
	refused.leave()
	await get_tree().process_frame
	check("  not reached, it stays and says the gold is waiting", is_instance_valid(refused)
		and refused.result_line.text.contains("gold is waiting"))
	refused.close()
	stand_in.queue_free()
	# ---- the Minigames card ----
	var Card: GDScript = load("res://src/ui/minigames/minigamescard.gd") as GDScript
	var hud := Control.new()
	add_child(hud)
	var card = Card.call("attach", hud)
	var opened: Array = []
	card.set("open_run", func(run_id: int, what_it_pays: Dictionary) -> void: opened.append([run_id, what_it_pays]))
	card.set("enter_request", func(_path: String, body: Dictionary, _wait: float) -> Dictionary:
		return {"ok": true, "status": 200, "data": {"run": 42, "plays_left": 2, "pays": {"most": 1000}, "game": body["game"]}})
	card.set("area_now", func() -> String: return "field")
	card.call("paint")
	check("the Minigames card has the Healer's Run under the Endless, for everyone: away from town, \"Play it from town.\"",
		card.healer_box.visible and card.healer_status.text == "Play it from town." and card.healer_go.disabled)
	card.set("area_now", func() -> String: return "elusion")
	card.call("take_listing", {"ok": true, "data": {"games": [{"id": "healerrun", "plays_left": 2, "ready_in": 0}]}})
	check("  in town it says the runs left today (\"3 times a day\")", not card.healer_go.disabled
		and card.healer_status.text == "Ready - 2 of 3 runs left today", card.healer_status.text)
	card.healer_go.pressed.emit()
	await get_tree().process_frame
	check("  Go asks the server, and opens the run it gives", opened == [[42, {"most": 1000}]], opened)
	card.call("take_listing", {"ok": true, "data": {"games": [{"id": "healerrun", "plays_left": 0, "ready_in": 7200}]}})
	check("  none left: when the next one is, and no Go", card.healer_go.disabled
		and card.healer_status.text == "Back in 2h", card.healer_status.text)
	hud.queue_free()
	await get_tree().process_frame
	print("  the healer's run: a shooter of her own, in a world of its own, from town")


func _test_each_keeper_fights_its_own_way() -> void:
	section("THE HEALER'S RUN: EACH LAND'S BOSS FIGHTS ITS OWN WAY, AND HITS ARE FELT (0.100.0)")
	# The owner: "lets progress tiers after round 8 to the next difficulty diff
	# boss and effects when hit".
	const RunScript := preload("res://src/world/healerrun/healerrun.gd")
	var run = RunScript.new()
	run.set("seed_value", 21)
	run.set("steer", func() -> Vector2: return Vector2.ZERO)
	add_child(run)
	run.set_process(false)
	for i in 120:
		run.step(1.0 / 60.0)
	for left in run.foes.get_children():
		left.queue_free()
	await get_tree().process_frame
	# Held between waves, with no boss: everything runs but the waves.
	run.state = RunScript.State.BOSS
	run.boss = null
	run.field.clear()
	var named: bool = RunScript.SIGNATURES.size() == RunScript.LANDS.size()
	for land in RunScript.LANDS:
		named = named and str(RunScript.SIGNATURES.get(land, "")) != "" and int(RunScript.SIGNATURE_VOLLEYS.get(land, 0)) > 0
	check("every land's boss has a cast of its own, by name", named)
	var from := Vector2(0.0, -110.0)
	var her: Vector2 = run.healer.position + RunScript.HITBOX_AT
	# FIRE
	run.lands[0] = Element.Type.FIRE
	run.set("_boss_fired", 0)
	run.call("_signature", from, 0, Color.RED)
	var settling: int = 0
	var from_above: int = 0
	for i in run.field.count:
		settling += 1 if run.field.brake_of(i) > 0.0 else 0
		from_above += 1 if run.field.position_of(i).y < -RunScript.HALF.y else 0
	check("fire: Fire rain - fireballs from above, and an ember that will lie burning",
		run.field.count == 4 and from_above == 4 and settling == 1, [run.field.count, from_above, settling])
	# ICE
	run.field.clear()
	run.lands[0] = Element.Type.ICE
	run.call("_signature", from, 0, Color.CYAN)
	var freezing: int = 0
	for i in run.field.count:
		freezing += 1 if run.field.damage_of(i) == RunScript.FREEZE_MARK else 0
	check("ice: Frost volley - a fan of freezing shots at her", freezing == 5 and run.field.count == 5, freezing)
	run.field.clear()
	run.untouchable = 0.0
	run.lives = 3
	run.field.spawn(her + Vector2(0.0, -2.0), PI / 2.0, 10.0, Color.CYAN, true, 0.0, 0.0, 14.0, RunScript.FREEZE_MARK)
	run.step(1.0 / 60.0)
	var frozen_then: bool = run.frozen > 0.0 and run.lives == 3
	var still_at: Vector2 = run.healer.position
	run.set("steer", func() -> Vector2: return Vector2.RIGHT)
	var flying: int = run.shots_flying()
	for i in 20:
		run.step(1.0 / 60.0)
	check("  a freezing shot freezes her instead of taking a life: she cannot move or shoot, and is tinted ice",
		frozen_then and run.healer.position == still_at and run.shots_flying() <= flying
		and run.healer_sprite.modulate == RunScript.ICE_TINT and not run.beam.visible, [frozen_then, run.healer.position])
	for i in int(RunScript.FREEZE_SECONDS * 60.0):
		run.step(1.0 / 60.0)
	run.field.spawn(run.healer.position + RunScript.HITBOX_AT + Vector2(0.0, -2.0), PI / 2.0, 10.0, Color.CYAN, true,
		0.0, 0.0, 14.0, RunScript.FREEZE_MARK)
	run.step(1.0 / 60.0)
	check("  thawed, she moves again, and a moment no freezing shot takes her (\"frozen\" never chains)",
		run.frozen == 0.0 and run.healer.position.x > still_at.x and run.lives == 3
		and run.healer_sprite.modulate != RunScript.ICE_TINT, [run.frozen, run.healer.position])
	run.set("steer", func() -> Vector2: return Vector2.ZERO)
	run.healer.position.x = 0.0
	# WIND
	run.field.clear()
	run.lands[0] = Element.Type.WIND
	run.set("_boss_fired", 0)
	run.call("_signature", from, 0, Color.GREEN)
	var side: float = run.gust_side
	var x0: float = run.healer.position.x
	var crosswinds: int = run.field.count
	for i in 30:
		run.untouchable = 1.0
		run.step(1.0 / 60.0)
	check("wind: Gale - a gust shoves her sideways while crosswinds blow from the wall",
		run.gust > 0.0 and absf((run.healer.position.x - x0) - side * RunScript.GUST_PUSH * 0.5) < 3.0
		and crosswinds == 3, [run.healer.position.x - x0, crosswinds])
	run.gust = 0.0
	run.healer.position.x = 0.0
	# WATER
	run.field.clear()
	run.lands[0] = Element.Type.WATER
	run.call("_signature", from, 0, Color.BLUE)
	var xs: Array = []
	for i in run.field.count:
		xs.append(run.field.position_of(i).x)
	xs.sort()
	var widest: float = 0.0
	for i in range(1, xs.size()):
		widest = maxf(widest, float(xs[i]) - float(xs[i - 1]))
	check("water: Tide - a row of weaving drops across the path, with a way through", xs.size() >= 14 and widest >= 60.0,
		[xs.size(), widest])
	# EARTH
	run.field.clear()
	run.untouchable = 0.0
	run.lives = 3
	run.shake = 0.0
	run.lands[0] = Element.Type.EARTH
	run.call("_signature", from, 0, Color.BROWN)
	var marked: Array = run.get("_rocks").duplicate()
	var drawn_marks: int = run.hazards.rocks.size()
	for i in int((RunScript.ROCK_WARN + 0.05) * 60.0):
		run.step(1.0 / 60.0)
	check("earth: Rockfall - rocks marked on the floor, one where she stands; staying there costs a life, and it lands with a shake",
		marked.size() == 2 and (marked[0]["at"] as Vector2).distance_to(her) < 1.0 and run.lives == 2 and run.shake > 0.0
		and run.field.count >= 10, [marked.size(), run.lives, run.field.count])
	for i in 150:
		run.step(1.0 / 60.0)
	run.get("_rocks").clear()
	run.hazards.rocks = []
	check("  and the marks are drawn first", drawn_marks == 2)
	# LIGHT
	run.field.clear()
	run.untouchable = 0.0
	run.lives = 3
	run.lands[0] = Element.Type.LIGHT
	run.call("_signature", from, 0, Color.YELLOW)
	var pillars: Array = run.get("_pillars").duplicate()
	for i in int((RunScript.PILLAR_WARN + 0.1) * 60.0):
		run.step(1.0 / 60.0)
	check("light: Pillars of light - columns marked, then burning; one on her, and standing in it costs a life",
		pillars.size() == 2 and absf(float(pillars[0]["x"]) - run.healer.position.x) < 1.0 and run.lives == 2,
		[pillars.size(), run.lives])
	for i in 150:
		run.step(1.0 / 60.0)
	# DARK
	run.field.clear()
	run.lands[0] = Element.Type.DARK
	run.call("_signature", from, 0, Color.PURPLE)
	var leaving: Vector2 = run.field.velocity_of(0)
	run.field.step(0.5, Vector2(9999.0, 9999.0), 0.0, 0.0, true)
	check("dark: Dark coils - six orbs curling as they fly", run.field.count == 6
		and absf(leaving.angle_to(run.field.velocity_of(0))) > 0.3, run.field.count)
	run.field.clear()
	# THE KEEPER'S CASTS: every other one its own, the first first.
	run.state = RunScript.State.RUNNING
	run.tier = 0
	run.lands[0] = Element.Type.FIRE
	run.call("_start_boss")
	var casts: Array = []
	for i in 60 * 12:
		run.untouchable = 1.0
		run.lives = 3
		var was: int = run.get("_boss_casting")
		run.step(1.0 / 60.0)
		var now: int = run.get("_boss_casting")
		if now >= 0 and now != was:
			casts.append(now)
			if casts.size() == 1:
				casts.append(run.banner)
		if casts.size() >= 3:
			break
	check("a keeper's first cast is its land's own, said in the banner, and the next is one of the shared four",
		casts.size() >= 3 and casts[0] == RunScript.SIGNATURE and casts[1] == "Fire rain" and int(casts[2]) < RunScript.SIGNATURE,
		casts)
	# ---- hits felt ----
	var bursts := func() -> int:
		var n: int = 0
		for child in run.get_children():
			n += 1 if child is RunScript.Burst else 0
		return n
	run.shake = 0.0
	run.set("_boss_shook", 0.0)
	var before: int = bursts.call()
	run.call("_strike", run.boss, 1.0)
	check("a boss struck sparks, and the screen shakes a little", run.shake == RunScript.BOSS_SHAKE
		and bursts.call() == before + 1)
	var mob: Node2D = run.call("_foe", "sprite", Vector2(0.0, -60.0))
	before = bursts.call()
	run.call("_strike", mob, 999.0)
	var burst: Node2D = run.get_children()[run.get_child_count() - 1]
	check("every kill bursts in its land's colour, drawn under the bullets", bursts.call() == before + 1
		and burst is RunScript.Burst and burst.z_index < run.field.z_index and burst.z_index < run.get_node("shots").z_index)
	burst.call("_process", 1.0)
	check("  and is gone when spent", burst.is_queued_for_deletion())
	before = bursts.call()
	run.power = 0
	run.gain_power()
	check("a power-up rings out from her and she shines", bursts.call() == before + 1
		and float(run.get("_shine_left")) > 0.0)
	run.shake = 0.0
	run.untouchable = 0.0
	run.hurt()
	check("a hit on her shakes the screen hard", run.shake == RunScript.HURT_SHAKE)
	run.step(1.0 / 60.0)
	var off: Vector2 = run.position - run.get("_home")
	for i in 30:
		run.step(1.0 / 60.0)
	check("  about where the run was put, and settles back to it", off.length() > 0.0
		and off.length() <= RunScript.HURT_SHAKE * 1.5 and run.shake == 0.0 and run.position == run.get("_home"), off)
	check("the marks and the bursts are drawn as light the crypt's dark does not dim, under her shots",
		run.hazards.z_index < run.get_node("shots").z_index and run.hazards.material is CanvasItemMaterial
		and (run.hazards.material as CanvasItemMaterial).light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED)
	run.queue_free()
	# ---- god mode: "i need a godmode switch that only i can see on the screen for this mini game so i can test" ----
	const ScreenScript := preload("res://src/world/healerrun/healerrunscreen.gd")
	var godly = RunScript.new()
	godly.set("seed_value", 8)
	add_child(godly)
	godly.set_process(false)
	for i in 120:
		godly.step(1.0 / 60.0)
	godly.god = true
	godly.untouchable = 0.0
	godly.lives = 3
	godly.power = 2
	godly.hurt()
	godly.healer.position.y = RunScript.HALF.y + 10.0
	godly.step(1.0 / 60.0)
	check("god mode: nothing takes a life or a shot step - a hit, or the scroll pushing her off - and the run remembers it was on",
		godly.lives == 3 and godly.power == 2 and godly.untouchable == 0.0 and godly.god_used
		and godly.healer.position.y < RunScript.HALF.y, [godly.lives, godly.power, godly.god_used])
	godly.queue_free()
	var god_was: bool = GameState.god_mode
	GameState.god_mode = false
	var screen = ScreenScript.open(get_tree(), 6, 91)
	await get_tree().process_frame
	check("  its switch is not on the screen for a player", not screen.god_switch.visible)
	screen.may_be_god = func() -> bool: return true
	screen.start()
	var shown: bool = screen.god_switch.visible and not screen.god_switch.button_pressed and not screen.run.god
	screen.god_switch.button_pressed = true
	check("  for the owner it is, off at first; on, it is the world's god mode too, and the run's",
		shown and GameState.god_mode and screen.run.god, [shown, GameState.god_mode])
	var sent: Array = []
	screen.finish_request = func(_path: String, body: Dictionary, _wait: float) -> Dictionary:
		sent.append(body)
		return {"ok": true, "status": 200, "data": {"gold": 0, "status": {}}}
	screen.run.waves_done = 9
	screen.run.bosses_beaten = 1
	screen.run.god_used = true
	screen.paint()
	var said: String = screen.gold_line.text
	screen.leave()
	await get_tree().process_frame
	check("  a run with it on says it pays nothing, and Leave closes it on the server with nothing reached",
		said.contains("pays nothing") and sent == [{"run": 91, "waves": 0, "bosses": 0, "goal": false}], [said, sent])
	var again = ScreenScript.open(get_tree(), 7)
	await get_tree().process_frame
	again.may_be_god = func() -> bool: return false
	again.god_switch.visible = true
	again.god_switch.button_pressed = true
	check("  and pressed by anyone else it does nothing and hides", not again.god_switch.visible
		and not again.god_switch.button_pressed and not again.run.god, again.god_switch.visible)
	again.close()
	GameState.god_mode = god_was
	print("  (each keeper's own way, and hits felt: done)")


func _test_google_sign_in() -> void:
	section("SIGNING IN WITH GOOGLE (0.101.0)")
	# A player: "Google account to play or I am not registering". The server's
	# half is the API's test_googlesignin.py; this is the game's.
	const GoogleScript := preload("res://src/systems/googlesignin.gd")
	var google = GoogleScript.new()
	add_child(google)
	var sent: Array = []
	var opened: Array = []
	var answers: Array = [
		{"ok": true, "status": 200, "data": {"code": "c0de" + "x".repeat(28), "check": "K7Q-4MX",
			"url": "https://api.example/api/auth/google/page?c=c0de", "expires_in": 600, "poll_every": 2}},
		{"ok": true, "status": 202, "data": {"waiting": true}},
		{"ok": false, "status": 0, "data": {}},
		{"ok": true, "status": 202, "data": {"waiting": true}},
		{"ok": true, "status": 200, "data": {"needs_name": true}},
		{"ok": true, "status": 201, "data": {"token": "t", "username": "newbie", "role": "player"}},
	]
	google.post_request = func(path: String, body: Dictionary, _wait: float) -> Dictionary:
		sent.append([path, body])
		return answers.pop_front() if not answers.is_empty() else {"ok": false, "status": 0}
	google.opener = func(url: String) -> void: opened.append(url)
	google.wait_between = func(_seconds: float) -> void: pass
	google.device_tokens = func() -> Array: return ["this-computer"]
	var began: Dictionary = await google.begin()
	check("Sign in with Google asks the server for a code and opens its page in the web browser",
		began.get("ok", false) and sent[0][0] == GoogleScript.START_PATH and opened == [began["data"]["url"]]
		and google.check == "K7Q-4MX" and google.waiting(), [sent, opened])
	var done: Dictionary = await google.wait_for_page()
	check("  it asks until the page is done - through a moment with no answer - and hears \"pick a name\"",
		done.get("data", {}).get("needs_name", false) and sent.size() == 5
		and sent[1] == [GoogleScript.POLL_PATH, {"code": google.code, "devices": ["this-computer"]}], sent.size())
	var made: Dictionary = await google.register("newbie")
	check("  the name goes with the code, and the account comes back signed in",
		sent[5] == [GoogleScript.REGISTER_PATH, {"code": google.code, "username": "newbie"}]
		and made.get("data", {}).get("token", "") == "t", sent[5])
	answers.append({"ok": true, "status": 200, "data": {"token": "t2", "username": "oldhand"}})
	var claimed: Dictionary = await google.claim("oldhand")
	check("  an account found by the email is claimed with the code and its name (0.102.0)",
		sent[6] == [GoogleScript.CLAIM_PATH, {"code": google.code, "username": "oldhand"}]
		and claimed.get("data", {}).get("username", "") == "oldhand", sent[6])
	check("  the names found are read as names, four at most",
		GoogleScript.found_in({"data": {"needs_name": true, "found": ["a", 3, "", "b", "c", "d", "e"]}})
		== ["a", "b", "c", "d"] and GoogleScript.found_in({"data": {"needs_name": true}}).is_empty())
	google.open_page()
	check("  and the page can be opened again", opened.size() == 2)
	answers = [{"ok": true, "status": 200, "data": {"code": "y".repeat(32), "check": "AAA-BBB", "url": "u"}}]
	await google.begin()
	var waiting_on: Array = []
	google.wait_between = func(_seconds: float) -> void:
		waiting_on.append(1)
		google.cancel()
	var stopped: Dictionary = await google.wait_for_page()
	check("Cancel stops it asking", stopped.get("cancelled", false) and not google.waiting())
	check("refusals say the server's own words, or that it could not be reached",
		GoogleScript.refusal_text({"status": 403, "data": {"message": "Staff accounts sign in with their password and code, not Google."}})
		.begins_with("Staff accounts") and GoogleScript.refusal_text({"status": 0}).contains("reach"))
	google.queue_free()
	# ---- on the login screen ----
	var menu: Control = (load("res://scene/ui/menus/loginmenu.tscn") as PackedScene).instantiate() as Control
	add_child(menu)
	await get_tree().process_frame
	var button: Button = menu.get("google_button")
	var login: Button = menu.get_node("%loginbutton")
	check("the login screen has \"Sign in with Google\" just under the sign-in button",
		button != null and button.text == "Sign in with Google" and button.get_parent() == login.get_parent()
		and button.get_index() == login.get_index() + 1)
	var g = menu.get("google")
	sent.clear()
	opened.clear()
	answers = [
		{"ok": true, "status": 200, "data": {"code": "z".repeat(32), "check": "QQQ-777", "url": "https://x/page"}},
		{"ok": true, "status": 200, "data": {"needs_name": true}},
	]
	g.post_request = google_stand_in.bind(sent, answers)
	g.opener = func(url: String) -> void: opened.append(url)
	g.wait_between = func(_seconds: float) -> void: pass
	menu.call("_on_google_pressed")
	for i in 4:
		await get_tree().process_frame
	var form: Control = menu.get("google_form")
	check("  pressed: the page opens, the screen shows the same check code, then asks for a name",
		opened == ["https://x/page"] and form.visible and not menu.get_node("%loginform").visible
		and menu.get("google_name").visible and menu.get("google_go").text == "Start playing", [opened, form.visible])
	check("  and it tells a player who already has an account what to do instead (0.102.1)",
		str(menu.get("google_intro").text).contains("sign in with your password, then link Google in Options"))
	menu.get("google_name").text = "no spaces"
	menu.call("_on_google_go")
	await get_tree().process_frame
	check("  a name the rules do not take is caught before it is sent", sent.size() == 2
		and str(menu.get("google_status").text).contains("Letters"))
	answers.append({"ok": false, "status": 409, "data": {"message": "That name is taken. Pick another."}})
	menu.get("google_name").text = "taken_name"
	menu.call("_on_google_go")
	for i in 3:
		await get_tree().process_frame
	check("  a name taken says so and stays on the name", sent.size() == 3 and form.visible
		and str(menu.get("google_status").text) == "That name is taken. Pick another.")
	menu.call("_on_google_back")
	check("  Cancel goes back to the sign-in form", not form.visible and menu.get_node("%loginform").visible
		and not g.waiting())
	answers.append({"ok": false, "status": 503, "data": {"message": "Google sign-in is not set up on this server yet."}})
	menu.call("_on_google_pressed")
	for i in 3:
		await get_tree().process_frame
	check("  a server without it set up says so on the form", not form.visible
		and str(menu.get_node("%errorlabel").text) == "Google sign-in is not set up on this server yet.")
	answers.append({"ok": true, "status": 200, "data": {"code": "w".repeat(32), "check": "BAN-NED", "url": "u"}})
	answers.append({"ok": false, "status": 403, "data": {"message": "This account is banned.",
		"ban": {"permanent": true, "reason": "cheating"}}})
	menu.call("_on_google_pressed")
	for i in 4:
		await get_tree().process_frame
	check("  a banned account hears its ban, as at the password login",
		str(menu.get_node("%errorlabel").text).begins_with("This account is banned permanently"),
		menu.get_node("%errorlabel").text)
	# AN ACCOUNT ALREADY THERE (0.102.0): the owner, "also need to look for
	# existing accounts".
	answers.append({"ok": true, "status": 200, "data": {"code": "v".repeat(32), "check": "OLD-ONE", "url": "u"}})
	answers.append({"ok": true, "status": 200, "data": {"needs_name": true, "found": ["oldhand"]}})
	menu.call("_on_google_pressed")
	for i in 4:
		await get_tree().process_frame
	var found: Control = menu.get("google_found")
	var as_them: Button = found.get_child(0) as Button if found.get_child_count() > 0 else null
	check("an account on the same email is offered first: \"Sign in as\" it, \"Make a new account\" under it",
		form.visible and found.visible and found.get_child_count() == 1 and as_them.text == "Sign in as oldhand"
		and not menu.get("google_name").visible and menu.get("google_go").text == "Make a new account",
		[found.visible, found.get_child_count()])
	var before: int = sent.size()
	answers.append({"ok": false, "status": 404, "data": {"message": "That account cannot be signed into with this Google account."}})
	as_them.emit_signal("pressed")
	for i in 3:
		await get_tree().process_frame
	check("  pressed, it claims that name; a refusal says so and stays on the offer",
		sent.size() == before + 1 and sent[before] == [GoogleScript.CLAIM_PATH, {"code": "v".repeat(32),
		"username": "oldhand"}] and found.visible and str(menu.get("google_status").text).begins_with("That account"),
		sent.slice(before))
	menu.call("_on_google_go")
	check("  \"Make a new account\" goes to the name box", menu.get("google_name").visible and not found.visible
		and menu.get("google_go").text == "Start playing" and sent.size() == before + 1)
	menu.call("_on_google_back")
	check("  and Cancel takes the offer down", not form.visible and found.get_child_count() == 0)
	menu.queue_free()
	# ---- Options ----
	var options: Control = (load("res://scene/ui/menus/optionsscreen.tscn") as PackedScene).instantiate() as Control
	add_child(options)
	await get_tree().process_frame
	var row: Control = options.get("account_google_row")
	check("Options has a Google row under the recovery email, hidden until the server says it may be linked",
		row != null and row.get_parent() == options.get("account_email_value").get_parent().get_parent()
		and row.get_index() == options.get("account_email_value").get_parent().get_index() + 1 and not row.visible)
	var shown: Callable = Callable(options, "google_row_shown")
	check("  staff see it too, on a server that says they may link Google (0.103.0); an older server hides it",
		shown.call({"ok": true, "data": {"available": true, "staff": true, "staff_may_link": true}})
		and not shown.call({"ok": true, "data": {"available": true, "staff": true}})
		and shown.call({"ok": true, "data": {"available": true, "staff": false}})
		and not shown.call({"ok": true, "data": {"available": false, "staff": false}}))
	options.queue_free()
	print("  (signing in with Google: done)")


func _test_the_healers_run_gets_wilder() -> void:
	section("THE HEALER'S RUN: THE LAST TIER'S FIRE, ELITES, RANDOM EVENTS (0.104.0)")
	# The owner: "fire needs to rise faster on part 3 of mini game and it keeps
	# getting higher if no upgrades are taken", "we need more randomness in the
	# game also i want elites to pop in also with their hit effects", "t3 needs
	# to reward up to 20,000 gold".
	const RunScript := preload("res://src/world/healerrun/healerrun.gd")
	var run = RunScript.new()
	run.set("seed_value", 33)
	run.set("steer", func() -> Vector2: return Vector2.ZERO)
	add_child(run)
	run.set_process(false)
	for i in 120:
		run.step(1.0 / 60.0)
	run.lives = 99
	# THE FIRE.
	run.tier = 0
	var first_rise: float = run.fire_rise()
	var first_ceiling: float = run.fire_ceiling()
	run.tier = RunScript.TIERS - 1
	run.set("_starved", 0.0)
	var last_rise: float = run.fire_rise()
	run.set("_starved", 30.0)
	var starved_rise: float = run.fire_rise()
	var starved_ceiling: float = run.fire_ceiling()
	run.set("_starved", 9999.0)
	var highest: float = run.fire_ceiling()
	check("the last tier's fire rises at least twice as fast, and faster and higher the longer no power-up is taken",
		first_ceiling == RunScript.FIRE_MOST and last_rise >= 2.0 * (RunScript.FIRE_RISE + RunScript.FIRE_RISE_PER_TIER * 2) - 0.001
		and last_rise > first_rise * 2.0 and starved_rise > last_rise and starved_ceiling > RunScript.FIRE_MOST
		and highest == RunScript.FIRE_HIGHEST and highest >= RunScript.HALF.y - 1.0,
		[first_rise, last_rise, starved_rise, starved_ceiling, highest])
	run.run_seconds = 999.0
	run.fire_height = 150.0
	run.set("_starved", 40.0)
	run.untouchable = 99.0
	run.gain_power()
	for i in 60:
		run.call("_burn", 1.0 / 60.0)
	check("  a power-up pushes it down further in the last tier and starts the climb again; it does not rise past its new ceiling",
		float(run.get("_starved")) < 1.5 and run.fire_height < 150.0 - RunScript.FIRE_PUSH
		and run.fire_height > run.fire_ceiling(), [run.fire_height, run.fire_ceiling()])
	# ELITES.
	for left in run.foes.get_children():
		left.queue_free()
	await get_tree().process_frame
	run.field.clear()
	run.state = RunScript.State.RUNNING
	run.tier = 0
	run.set("_elite_in", 0.01)
	for i in 30:
		run.call("_elites_step", 1.0 / 60.0)
	check("no elites in the first tier", (run.get("_elite_marks") as Array).is_empty() and run.elites_seen == 0)
	run.tier = 1
	run.lands[1] = Element.Type.ICE
	run.set("_elite_in", 0.01)
	run.call("_elites_step", 1.0 / 60.0)
	var marked: int = (run.get("_elite_marks") as Array).size()
	var foes_before: int = run.foes.get_child_count()
	var bursts_before: int = _bursts_in(run)
	for i in int(RunScript.ELITE_WARN * 60.0) + 2:
		run.call("_elites_step", 1.0 / 60.0)
	var elite: Node2D = null
	for f in run.foes.get_children():
		if bool(f.get("elite")):
			elite = f
	check("from the second tier an elite is marked, then pops in with a flash: bigger, %d times as tough, holding no wave"
		% int(RunScript.ELITE_HEALTH),
		marked == 1 and elite != null and run.foes.get_child_count() == foes_before + 1 and run.elites_seen == 1
		and _bursts_in(run) > bursts_before and int(elite.get("wave")) == -1
		and is_equal_approx(float(elite.get("most")), RunScript.foe_health(float(RunScript.KINDS[str(elite.get("kind"))]["health"]),
			run.rank()) * RunScript.ELITE_HEALTH) and float(elite.get("radius")) > float(RunScript.KINDS[str(elite.get("kind"))]["radius"]),
		[marked, run.elites_seen])
	elite.set("casts", 1)
	elite.set("shoot_in", 0.0)
	run.field.clear()
	run.call("_elite_move", elite, 1.0 / 60.0, 0)
	var freezing: int = 0
	for i in run.field.count:
		freezing += 1 if run.field.damage_of(i) == RunScript.FREEZE_MARK else 0
	check("  every other cast is a volley of its land's keeper cast - an ice elite's shots freeze",
		freezing >= 5 and int(elite.get("casts")) == 2, [run.field.count, freezing])
	var sparks_before: int = _bursts_in(run)
	run.set("_spark_in", 0.0)
	run.call("_strike", elite, 1.0)
	check("  struck, it sparks (its hit effect)", _bursts_in(run) > sparks_before)
	var drops_before: Array = []
	for d in run.drops.get_children():
		drops_before.append(d)
	run.call("_strike", elite, float(elite.get("health")) + 1.0)
	var powers: int = 0
	for d in run.drops.get_children():
		if not drops_before.has(d) and str(d.get_meta(&"drop", "")) == "power":
			powers += 1
	check("  down, it bursts and always drops a power-up", float(elite.get("dying")) >= 0.0 and powers == 1
		and run.shake > 0.0, powers)
	# EVENTS.
	check("five random events, each with a name", RunScript.EVENTS.size() == 5 and RunScript.EVENT_NAMES.size() == 5)
	var drops_then: int = run.drops.get_child_count()
	run.start_event("power rain")
	check("  power-up rain: power-ups and a potion fall from the top", run.drops.get_child_count() == drops_then + 4
		and run.banner == RunScript.EVENT_NAMES["power rain"])
	var foes_then: int = run.foes.get_child_count()
	run.start_event("swarm")
	check("  a swarm: a crowd of sprites diving fast", run.foes.get_child_count() >= foes_then + 12)
	run.start_event("treasure")
	var treasure: Node2D = null
	for f in run.foes.get_children():
		if str(f.get("kind")) == "treasure":
			treasure = f
	var lives_then: int = run.lives
	run.untouchable = 0.0
	treasure.position = run.healer.position + RunScript.HITBOX_AT
	run.call("_move_foes", 0.0)
	var harmless: bool = run.lives == lives_then
	run.untouchable = 99.0
	var power_drops: int = 0
	for d in run.drops.get_children():
		power_drops += 1 if str(d.get_meta(&"drop", "")) == "power" else 0
	run.call("_strike", treasure, float(treasure.get("health")) + 1.0)
	var power_after: int = 0
	for d in run.drops.get_children():
		power_after += 1 if str(d.get_meta(&"drop", "")) == "power" else 0
	check("  a treasure runs past, harmless; caught, it spills %d power-ups" % RunScript.TREASURE_DROPS,
		harmless and power_after == power_drops + RunScript.TREASURE_DROPS, [harmless, power_drops, power_after])
	run.start_event("meteors")
	run.set("_rocks", [])
	for i in 90:
		run.call("_events_step", 1.0 / 60.0)
	check("  a meteor shower: rocks marked on the path, one after another",
		(run.get("_rocks") as Array).size() >= 2, (run.get("_rocks") as Array).size())
	run.start_event("darkness")
	for i in 60:
		run.call("_events_step", 1.0 / 60.0)
	check("  darkness: only the ground round her is lit, under every bullet",
		run.darkness.visible and float(run.get("_dark")) >= 0.99 and run.darkness.z_index < RunScript.BULLETS_Z
		and run.darkness.z_index < RunScript.HAZARD_Z)
	run.event_left = 0.0
	for i in 70:
		run.call("_events_step", 1.0 / 60.0)
	check("  and it lifts when it ends", not run.darkness.visible and run.event == "")
	# MIXED UP.
	run.set("_last_kind", "vee")
	run.waves_done = 5
	var repeats: int = 0
	for i in 60:
		var k: String = run.call("_pick_kind")
		repeats += 1 if k == str(run.get("_last_kind")) else 0
		run.set("_last_kind", k)
	# An arcs wave's first always came in from the left; flipped, from the right.
	var sides: Dictionary = {}
	var paces: Dictionary = {}
	for i in 12:
		var wave: Array = run.spawn_wave("arcs")
		var one: Node2D = wave[0]
		sides[signf(one.position.x)] = true
		paces[snappedf(absf(float(one.get("velocity").y)), 1.0)] = true
	check("waves are mixed up: never the same twice running, some flipped, at different speeds",
		repeats == 0 and sides.size() == 2 and paces.size() >= 4, [repeats, sides.keys(), paces.size()])
	run.queue_free()
	await get_tree().process_frame
	print("  (the healer's run gets wilder: done)")


func _test_the_healers_run_with_a_party() -> void:
	section("THE HEALER'S RUN WITH THE PARTY (0.105.0)")
	# The owner: "make it to where you can join with your party", and of the
	# gold: "each player". Two games in one tree on stand-in links that pass
	# "en" as the server does (JSON and back).
	const RunScript := preload("res://src/world/healerrun/healerrun.gd")
	const PartyScript := preload("res://src/world/healerrun/healerparty.gd")
	var Link: GDScript = _party_link_script()
	var la: Node = Link.new()
	var lb: Node = Link.new()
	la.set("me", 1)
	lb.set("me", 2)
	for l in [la, lb]:
		l.set("leader", 1)
		l.set("others", 1)
		add_child(l)
	la.set("peers", [lb])
	lb.set("peers", [la])
	var body_a := Node2D.new()
	var body_b := Node2D.new()
	add_child(body_a)
	add_child(body_b)
	la.set("bodies", {2: body_b})
	lb.set("bodies", {1: body_a})
	var games: Array = []
	for pair in [[la, 31], [lb, 77]]:
		var run = RunScript.new()
		run.set("seed_value", int(pair[1]))
		run.set("steer", func() -> Vector2: return Vector2.ZERO)
		var party: Node = PartyScript.new()
		party.set("link", pair[0])
		party.set("run", run)
		run.set("party", party)
		run.add_child(party)
		add_child(run)
		run.set_process(false)
		party.set_process(false)
		games.append([run, party])
	var a = games[0][0]
	var b = games[1][0]
	var pa: Node = games[0][1]
	var pb: Node = games[1][1]
	var began_at: Array = [-1.0, -1.0]
	var clock: Array = [0.0]
	pa.connect("start_now", func() -> void:
		began_at[0] = clock[0]
		a.begin_run())
	pb.connect("start_now", func() -> void:
		began_at[1] = clock[0]
		b.begin_run())
	_hr_frames(games, 0.3)
	check("waiting together: the leader picks the run's key and its lands, and the other takes them",
		int(pa.get("key")) > 0 and int(pb.get("key")) == int(pa.get("key")) and pa.call("leads") and not pb.call("leads")
		and [b.lands[0], b.lands[1], b.lands[2]] == [a.lands[0], a.lands[1], a.lands[2]],
		[pa.get("key"), pb.get("key")])
	# READY, THEN THE COUNT ("we need a ready for all players then a countdown").
	pa.call("set_ready", true)
	_hr_frames(games, 0.6)
	var one_ready: bool = float(pa.get("counting")) < 0.0 and not bool(a.get("begun"))
	pb.call("set_ready", true)
	_hr_frames(games, 0.6)
	var counted: Array = [float(pa.get("counting")), float(pb.get("counting"))]
	check("Ready: the leader alone ready counts nothing; both ready, both count down together (%.1f s and %.1f s left)"
		% [counted[0], counted[1]], one_ready and counted[0] > 1.5 and counted[1] > 1.5
		and absf(counted[0] - counted[1]) <= PartyScript.COUNTDOWN_SLACK + 0.21 and not bool(a.get("begun")), counted)
	pb.call("set_ready", false)
	_hr_frames(games, 0.4)
	var stopped: bool = float(pa.get("counting")) < 0.0 and float(pb.get("counting")) < 0.0
	pb.call("set_ready", true)
	var t: float = 0.0
	while t < PartyScript.COUNTDOWN_SECONDS + 1.0:
		clock[0] = t
		_hr_frames(games, 1.0 / 30.0)
		t += 1.0 / 30.0
	check("  one not ready again stops the count on both; ready again, both begin within a frame or two of each other",
		stopped and began_at[0] >= PartyScript.COUNTDOWN_SECONDS - 0.2 and began_at[1] >= 0.0
		and absf(began_at[0] - began_at[1]) <= 0.21, began_at)
	_hr_frames(games, RunScript.READY_SECONDS + 0.3)
	check("  for two players, the run under way on both", bool(a.get("begun")) and bool(b.get("begun"))
		and int(a.get("players")) == 2 and int(b.get("players")) == 2 and int(b.get("state")) == RunScript.State.RUNNING,
		[a.get("players"), b.get("players"), b.get("state")])
	var fa: Array = _hr_foes(a)
	var fb: Array = _hr_foes(b)
	var same: bool = fa.size() == fb.size() and fa.size() > 0
	var far: float = 0.0
	for i in mini(fa.size(), fb.size()):
		same = (same and str(fa[i].get("kind")) == str(fb[i].get("kind")) and int(fa[i].get("batch")) == int(fb[i].get("batch"))
			and int(fa[i].get("slot")) == int(fb[i].get("slot")) and is_equal_approx(float(fa[i].get("most")), float(fb[i].get("most"))))
		far = maxf(far, (fa[i].position as Vector2).distance_to(fb[i].position))
	check("  the first wave is the same on both screens: the same monsters, health and places (%d, %.1f px apart)"
		% [fa.size(), far], same and far < 8.0, [fa.size(), fb.size(), far])
	var base_health: float = float(RunScript.KINDS[str(fa[0].get("kind"))]["health"])
	var ranked: float = (float(fa[0].get("most")) / (a.party_share() * base_health) - 1.0) / 0.18
	check("  and tougher for two, by less than before (\"lower the health increases\"): %d%% of its health alone"
		% roundi(a.party_share() * 100.0), is_equal_approx(a.party_share(), 1.0 + RunScript.PARTY_HEALTH)
		and RunScript.PARTY_HEALTH <= 0.15 and RunScript.PARTY_BOSS <= 0.4 and RunScript.PARTY_CROWD <= 1
		and absf(ranked - roundf(ranked)) < 0.01, ranked)
	var target_b: Node2D = fb[0]
	var target_a: Node2D = fa[0]
	var before: float = float(target_a.get("health"))
	b.call("_strike", target_b, 1.0)
	_hr_frames(games, 0.3)
	check("a hit on the other screen lands here too", is_equal_approx(float(target_a.get("health")), before - 1.0),
		[before, target_a.get("health")])
	a.call("_strike", target_a, float(target_a.get("health")) + 1.0)
	_hr_frames(games, 0.3)
	check("  and a monster killed there dies here", float(target_b.get("dying")) >= 0.0 or not is_instance_valid(target_b)
		or target_b.get_parent() == null)
	var push_was: float = float(a.get("_fire_push"))
	b.gain_power()
	pb.call("flush")
	check("a power-up taken by the other pushes the leader's fire back", float(a.get("_fire_push")) > push_was
		and int(pb.get("pushes")) == 1, [push_was, a.get("_fire_push"), pb.get("pushes")])
	a.waves_done = 5
	_hr_frames(games, 0.7)
	check("  the waves passed are the leader's count on both screens (the gold for each)", b.waves_done == 5, b.waves_done)
	for f in a.foes.get_children():
		f.queue_free()
	for f in b.foes.get_children():
		f.queue_free()
	await get_tree().process_frame
	a.call("_decide", RunScript.EVENT_BOSS, [])
	_hr_frames(games, 0.3)
	check("the leader's keeper comes to both, as tough for two",
		int(b.get("state")) == RunScript.State.BOSS and b.boss != null and a.boss != null
		and is_equal_approx(float(b.boss.get("most")), float(a.boss.get("most"))) and a.party_share(true) > 1.3,
		[b.get("state")])
	b.untouchable = 0.0
	b.lives = 1
	b.hurt()
	_hr_frames(games, 0.6)
	check("out of lives with the party still in: she watches, the run goes on",
		bool(b.get("ghost")) and int(b.get("state")) == RunScript.State.BOSS and int(a.get("state")) == RunScript.State.BOSS)
	# THE BOARD ("show players and total accumulation for the party and who is dead").
	pa.call("flush")
	pb.call("flush")
	var board_a: Array = pa.call("roster")
	var board_b: Array = pb.call("roster")
	var gold_a: int = int(a.call("gold_now"))
	var gold_b: int = int(b.call("gold_now"))
	check("the party's board on each screen: both players, who is out, their kills and gold, and the party's gold",
		board_a.size() == 2 and board_b.size() == 2 and bool(board_a[0]["me"]) and int(board_a[1]["flags"]) & PartyScript.OUT != 0
		and int(board_b[0]["flags"]) & PartyScript.OUT != 0 and int(board_b[1]["flags"]) & PartyScript.OUT == 0
		and int(board_b[1]["lives"]) == int(a.get("lives")) and int(board_a[0]["kills"]) >= 1
		and int(board_b[1]["kills"]) == int(board_a[0]["kills"]) and int(pa.call("party_gold")) == gold_a + gold_b,
		[board_a, board_b])
	a.untouchable = 0.0
	a.lives = 1
	a.hurt()
	_hr_frames(games, 0.6)
	check("  and when nobody is left in, it ends on both screens", int(a.get("state")) == RunScript.State.LOST
		and int(b.get("state")) == RunScript.State.LOST, [a.get("state"), b.get("state")])
	# A GAME COMING LATE plays alone.
	var lc: Node = Link.new()
	lc.set("me", 3)
	lc.set("leader", 1)
	lc.set("others", 2)
	add_child(lc)
	var c = RunScript.new()
	c.set("steer", func() -> Vector2: return Vector2.ZERO)
	var pc: Node = PartyScript.new()
	pc.set("link", lc)
	pc.set("run", c)
	c.set("party", pc)
	c.add_child(pc)
	add_child(c)
	c.set_process(false)
	pc.set_process(false)
	pc.call("_on_run", 1, {"r": [int(pa.get("key")), 1, 0, 3, 3, 0, 0, 2, 600, 1, 2, 3, 1]})
	check("a game coming once the party's run has begun plays its own (joining half way would pay for others' work)",
		int(pc.get("key")) == PartyScript.ALONE and not pc.call("active") and pc.call("leads"))
	# PRESENCE: where her healer runs, and the world's monsters not heard.
	var held_state: Callable = Presence.state_override
	var needs: Array = []
	var on_need: Callable = func(_id: int) -> void: needs.append(1)
	Presence.world_needed.connect(on_need)
	Presence.state_override = func() -> Dictionary: return {"a": "healerrun", "at": Vector2(5.0, 6.0), "m": "walkup"}
	var said: Dictionary = Presence.state_for(body_a)
	Presence.handle_message({"t": "need", "id": 9})
	Presence.state_override = held_state
	Presence.world_needed.disconnect(on_need)
	check("presence says where her healer runs while the party plays, and hears none of the world's monsters",
		said.get("a") == "healerrun" and is_equal_approx(float(said.get("x")), 5.0) and str(said.get("m")) == "walkup"
		and str(said.get("pet")) == "" and needs.is_empty(), said)
	# THE SCREEN: the start panel lists who is here, and Start is Ready.
	const ScreenScript := preload("res://src/world/healerrun/healerrunscreen.gd")
	var lf: Node = Link.new()
	lf.set("me", 2)
	lf.set("leader", 1)
	lf.set("others", 1)
	lf.set("bodies", {1: body_a})
	add_child(lf)
	var screen: CanvasLayer = ScreenScript.new()
	screen.set("party_rooms", func() -> bool: return true)
	screen.set("party_link", lf)
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	var sp: Node = screen.get("run").get("party")
	sp.set("own_name", func() -> String: return "mia")
	sp.set("key", 55)
	screen.call("paint")
	var waiting_said: String = str(screen.get("party_line").text)
	screen.call("begin")
	screen.call("paint")
	var ready_said: String = str(screen.get("party_line").text)
	var held: bool = screen.get("tutorial").visible and not bool(screen.get("run").get("begun")) and bool(sp.get("said_ready"))
	var button_said: String = str(screen.get("start_button").text)
	sp.emit_signal("start_now")
	check("the start panel with the party: who is here and who is ready, Start is Ready, and the count starts it",
		waiting_said.contains("mia (you) - not ready") and waiting_said.contains("a player - joining")
		and ready_said.contains("mia (you) - ready") and button_said.begins_with("Not ready") and held
		and not screen.get("tutorial").visible and bool(screen.get("run").get("begun")), [waiting_said, ready_said])
	screen.call("close")
	for g in games:
		(g[0] as Node).queue_free()
	for n in [c, la, lb, lc, lf, body_a, body_b]:
		n.queue_free()
	await get_tree().process_frame
	print("  (the healer's run with the party: done)")


func _test_the_healers_run_is_fair() -> void:
	section("THE HEALER'S RUN: INSIDE THE WALLS, TUNING, AND THE START PANEL (0.105.0)")
	const RunScript := preload("res://src/world/healerrun/healerrun.gd")
	const PartyScript := preload("res://src/world/healerrun/healerparty.gd")
	const ScreenScript := preload("res://src/world/healerrun/healerrunscreen.gd")
	# NOTHING BREAKS OUT OF THE WALLS ("make everything symetrical so nothing
	# breaks out of the walls").
	var run = RunScript.new()
	run.set("steer", func() -> Vector2: return Vector2.ZERO)
	add_child(run)
	run.set_process(false)
	var out_of_walls: Array = []
	var crossing_kinds: Dictionary = {}
	var uneven: Array = []
	for kind in RunScript.WAVE_KINDS + ["swarm"]:
		for heat_now in [0, 5]:
			run.tier = heat_now / 2
			run.wave_in_tier = 4 if heat_now % 2 == 1 else 0
			run.power = 4 if heat_now > 0 else 0
			for i in 8:
				var made: Array = run.spawn_wave(str(kind))
				var xs: Array = []
				for f in made:
					xs.append(float(f.position.x))
					if bool(f.get("crossing")):
						crossing_kinds[kind] = true
				if kind == "wall" or kind == "mages":
					xs.sort()
					if absf(float(xs[0]) + float(xs[xs.size() - 1])) > 0.01:
						uneven.append([kind, xs[0], xs[xs.size() - 1]])
				for k in 90:
					run.call("_move_foes", 1.0 / 30.0)
					for f in run.foes.get_children():
						if not bool(f.get("crossing")) and str(f.get("kind")) != "boss" and f.get_parent() != null \
								and absf(float(f.position.x)) > RunScript.PATH_HALF - float(f.get("radius")) + 0.01:
							out_of_walls.append([kind, snappedf(float(f.position.x), 0.1)])
				for f in run.foes.get_children():
					run.foes.remove_child(f)
					f.queue_free()
	check("every wave stays inside the walls, all the way down: only what crosses the path (%s) goes behind them"
		% ", ".join(crossing_kinds.keys()), out_of_walls.is_empty()
		and crossing_kinds.keys().all(func(k: String) -> bool: return k in ["sweep", "arcs", "pincer"])
		and crossing_kinds.size() == 3, out_of_walls.slice(0, 6))
	check("  and the wall of slimes and the mages are laid even about the middle", uneven.is_empty(), uneven)
	run.call("_lay_terrain")
	var wall_z: Array = []
	for piece in run.props.get_children():
		if piece.has_meta(&"wall"):
			wall_z.append(int(piece.z_index))
	check("  the side walls are drawn over the monsters, the party and the beam, under the dark and every shot",
		not wall_z.is_empty() and wall_z.all(func(z: int) -> bool: return z == RunScript.WALL_Z)
		and RunScript.WALL_Z > maxi(int(run.others.z_index), RunScript.BEAM_Z) and RunScript.WALL_Z > int(run.foes.z_index)
		and RunScript.WALL_Z < mini(RunScript.DARK_Z, RunScript.SHOTS_Z), wall_z.slice(0, 3))
	run.queue_free()
	# TUNING: the owner's, carried in each event so every screen agrees.
	check("the tuning is kept in the suite's own file, never the owner's",
		RunScript.tune_path.get_file().begins_with("_suite"), RunScript.tune_path)
	RunScript.tune = RunScript.TUNE_DEFAULTS.duplicate()
	RunScript.tune["party_health"] = 0.5
	RunScript.tune["health"] = 2.0
	RunScript.save_tune()
	RunScript.tune = RunScript.TUNE_DEFAULTS.duplicate()
	RunScript.load_tune()
	var loaded: bool = is_equal_approx(float(RunScript.tune["party_health"]), 0.5) and RunScript.tune_changed()
	var Link: GDScript = _party_link_script()
	var la: Node = Link.new()
	var lb: Node = Link.new()
	la.set("me", 1)
	lb.set("me", 2)
	for l in [la, lb]:
		l.set("leader", 1)
		l.set("others", 1)
		add_child(l)
	la.set("peers", [lb])
	lb.set("peers", [la])
	var games: Array = []
	for pair in [[la, 5], [lb, 6]]:
		var r = RunScript.new()
		r.set("seed_value", int(pair[1]))
		r.set("steer", func() -> Vector2: return Vector2.ZERO)
		var p: Node = PartyScript.new()
		p.set("link", pair[0])
		p.set("run", r)
		r.set("party", p)
		r.add_child(p)
		add_child(r)
		r.set_process(false)
		p.set_process(false)
		p.connect("start_now", r.begin_run)
		games.append([r, p])
	var a = games[0][0]
	var b = games[1][0]
	_hr_frames(games, 0.3)
	games[0][1].call("set_ready", true)
	games[1][1].call("set_ready", true)
	# The follower's own computer is untuned: only the leader's numbers count.
	_hr_frames(games, PartyScript.COUNTDOWN_SECONDS + RunScript.READY_SECONDS + 0.5)
	var fa: Array = _hr_foes(a)
	var fb: Array = _hr_foes(b)
	var same: bool = not fa.is_empty() and fa.size() == fb.size()
	for i in mini(fa.size(), fb.size()):
		same = same and is_equal_approx(float(fa[i].get("most")), float(fb[i].get("most")))
	var base: float = float(RunScript.KINDS[str(fa[0].get("kind"))]["health"]) if not fa.is_empty() else 1.0
	var at_rank: float = float(fa[0].get("most")) / (base * 1.5 * 2.0) if not fa.is_empty() else 0.0
	check("tuning is the leader's on every screen: the same monsters, %d%% health a player more, x2 health; kept and read back"
		% roundi(float(RunScript.tune["party_health"]) * 100.0), loaded and same
		and absf((at_rank - 1.0) / 0.18 - roundf((at_rank - 1.0) / 0.18)) < 0.01, [fa.size(), fb.size(), at_rank])
	check("  and a tuned run pays nothing, on the leader's screen and the others'",
		bool(a.get("tune_used")) and bool(b.get("tune_used")))
	RunScript.tune = RunScript.TUNE_DEFAULTS.duplicate()
	RunScript.save_tune()
	for g in games:
		(g[0] as Node).queue_free()
	la.queue_free()
	lb.queue_free()
	# THE START PANEL, opened from the card with the party: the run of the day
	# is asked for at the count, so Leave before it costs nothing.
	var asked: Array = []
	var answers: Array = []
	var stand_in: Callable = func(path: String, body: Dictionary, _wait: float) -> Dictionary:
		asked.append([path, body])
		return answers.pop_front() if not answers.is_empty() else {"ok": false, "status": 0}
	var screen: CanvasLayer = ScreenScript.new()
	screen.set("party_rooms", func() -> bool: return false)
	screen.set("enter_at_start", true)
	screen.set("enter_request", stand_in)
	screen.set("finish_request", stand_in)
	screen.set("slot_now", func() -> int: return 2)
	screen.set("may_be_god", func() -> bool: return false)
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	answers.append({"ok": false, "status": 409, "data": {"message": "You have run The Healer's Run 3 times today."}})
	await screen.call("begin")
	screen.call("paint")
	var refused: bool = screen.get("tutorial").visible and int(screen.get("run_id")) == 0 \
		and str(screen.get("party_line").text).contains("3 times today")
	answers.append({"ok": true, "status": 200, "data": {"run": 77, "pays": {}}})
	await screen.call("begin")
	check("Start alone asks for the run of the day then (the server's no said on the panel), and goes",
		refused and asked.size() == 2 and str(asked[1][0]) == "/api/minigames/enter"
		and str(asked[1][1].get("game")) == "healerrun" and int(asked[1][1].get("slot")) == 2
		and int(screen.get("run_id")) == 77 and not screen.get("tutorial").visible, asked)
	screen.get("run").set("state", RunScript.State.LOST)
	answers.append({"ok": true, "status": 200, "data": {"gold": 0}})
	await screen.call("again")
	check("  Again pays this run and goes back to the start panel, asking for nothing yet",
		asked.size() == 3 and str(asked[2][0]) == "/api/minigames/finish" and int(screen.get("run_id")) == 0
		and screen.get("tutorial").visible, asked.size())
	screen.call("ask_to_leave")
	await get_tree().process_frame
	check("  Leave from the start panel: out at once, nothing asked, no run spent",
		asked.size() == 3 and not is_instance_valid(screen))
	# With the party: Ready, then the count asks for the run; no run, not ready.
	var lf: Node = Link.new()
	lf.set("me", 2)
	lf.set("leader", 1)
	lf.set("others", 1)
	add_child(lf)
	screen = ScreenScript.new()
	screen.set("party_rooms", func() -> bool: return true)
	screen.set("party_link", lf)
	screen.set("enter_at_start", true)
	screen.set("enter_request", stand_in)
	screen.set("may_be_god", func() -> bool: return false)
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	asked.clear()
	var sp: Node = screen.get("run").get("party")
	sp.set("key", 9)
	screen.call("begin")
	var readied: bool = bool(sp.get("said_ready")) and asked.is_empty()
	answers.append({"ok": false, "status": 409, "data": {"message": "No runs left."}})
	sp.call("_on_run", 1, {"r": [9, 0, 0, 0, 0, 0, 0, 1, 0, 1, 2, 3, PartyScript.COUNTING, 30, 0]})
	await get_tree().process_frame
	await get_tree().process_frame
	screen.call("paint")
	check("with the party: Ready asks for nothing; the count asks for the run, and a no takes Ready back, said",
		readied and asked.size() == 1 and str(asked[0][0]) == "/api/minigames/enter" and not bool(sp.get("said_ready"))
		and str(screen.get("party_line").text).contains("No runs left."), [asked, screen.get("party_line").text])
	screen.call("close")
	lf.queue_free()
	# The board's numbers read well.
	check("  the board's gold reads with commas (20,000)", ScreenScript.thousands(20000) == "20,000"
		and ScreenScript.thousands(999) == "999" and ScreenScript.thousands(1234567) == "1,234,567")
	# THE OWNER'S SLIDERS, under the god switch.
	screen = ScreenScript.new()
	screen.set("may_be_god", func() -> bool: return true)
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	var tune_button: Button = screen.get("tune_button")
	tune_button.button_pressed = true
	var rows: Dictionary = screen.get("_tune_rows")
	var slider: HSlider = rows["party_health"][1]
	slider.value = 0.2
	var moved: bool = is_equal_approx(float(RunScript.tune["party_health"]), 0.2) \
		and str((rows["party_health"][0] as Label).text).contains("20%")
	screen.call("tune_defaults")
	check("Tuning under the god switch: a slider a number, said as it moves, kept; Defaults puts them back",
		tune_button.visible and screen.get("tune_panel").visible and rows.size() == RunScript.TUNE_ORDER.size()
		and moved and not RunScript.tune_changed() and slider.focus_mode == Control.FOCUS_NONE)
	screen.call("close")
	screen = ScreenScript.new()
	screen.set("may_be_god", func() -> bool: return false)
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	check("  and nobody else sees it", not screen.get("tune_button").visible and not screen.get("tune_panel").visible)
	screen.call("close")
	# THE CARD: with the party, Go opens the start panel and asks for nothing.
	var card_hud := Control.new()
	add_child(card_hud)
	var card = (load("res://src/ui/minigames/minigamescard.gd") as GDScript).call("attach", card_hud)
	var lobbies: Array = []
	var entered: Array = []
	card.set("area_now", func() -> String: return "elusion")
	card.set("healer_party", func() -> bool: return true)
	card.set("open_lobby", func() -> void: lobbies.append(1))
	card.set("enter_request", func(path: String, _b: Dictionary, _w: float) -> Dictionary:
		entered.append(path)
		return {"ok": false, "status": 0})
	card.call("_on_healer_go")
	check("the card's Go with the party opens the start panel, asking for no run yet",
		lobbies.size() == 1 and entered.is_empty(), [lobbies, entered])
	card_hud.queue_free()
	await get_tree().process_frame
	print("  (the healer's run is fair: done)")


func _test_the_critical_beam_and_the_shield() -> void:
	section("THE HEALER'S RUN: THE CRITICAL BEAM AND THE METEOR SHIELD (0.106.0)")
	const RunScript := preload("res://src/world/healerrun/healerrun.gd")
	var run = RunScript.new()
	run.set("steer", func() -> Vector2: return Vector2.ZERO)
	add_child(run)
	run.set_process(false)
	run.power = 4
	run.healer.position = Vector2(0.0, 120.0)
	var from: Vector2 = run.healer.position + Vector2(0.0, -18.0)
	var hits: Callable = func(level: int, at: Vector2) -> float:
		for f in run.foes.get_children():
			run.foes.remove_child(f)
			f.queue_free()
		var f: Node2D = run.call("_foe", "mage", from + at)
		f.set("velocity", Vector2.ZERO)
		f.set("stop_y", -999.0)
		f.set("most", 9999.0)
		f.set("health", 9999.0)
		run.laser_level = level
		run.laser = 5.0
		run.call("_shine", 0.1)
		return 9999.0 - float(f.get("health"))
	# "the two outer beams slightly outward towards the corners".
	var five: Array = RunScript.side_beams(5)
	var leaning: bool = five.size() == 4
	for side in five:
		var outer: bool = absf(float(side[0])) > RunScript.SIDE_BEAM_GAP * 1.5
		leaning = leaning and (is_equal_approx(float(side[1]), signf(float(side[0])) * RunScript.OUTER_TILT) if outer
			else float(side[1]) == 0.0)
	var up: float = 150.0
	var lean_x: float = RunScript.SIDE_BEAM_GAP * 2.0 + up * tan(RunScript.OUTER_TILT)
	var on_lean: float = hits.call(5, Vector2(lean_x, -up))
	var straight_up: float = hits.call(5, Vector2(RunScript.SIDE_BEAM_GAP * 2.0, -up))
	var side_hit: float = RunScript.laser_dps(5) * RunScript.SIDE_BEAM_SHARE * 0.1
	check("the outer pair of side beams leans out toward the far corners: what stands on the lean is hit, straight above them not",
		leaning and RunScript.OUTER_TILT > 0.1 and RunScript.OUTER_TILT < 0.35 and absf(on_lean - side_hit) < 0.01
		and straight_up == 0.0, [on_lean, side_hit, straight_up])
	# "the red beam should be our critical beam".
	var red_five: float = hits.call(5, Vector2(0.0, -up))
	var red_seven: float = hits.call(7, Vector2(0.0, -up))
	var edge_seven: float = hits.call(7, Vector2(RunScript.laser_half(7) + 9.0, -up))
	check("in the red, a critical hit: %.1fx the beam at laser 5, %.1fx at 7; beside the red, the beam's own"
		% [RunScript.crit_mult(5), RunScript.crit_mult(7)],
		absf(red_five - RunScript.laser_dps(5) * RunScript.crit_mult(5) * 0.1) < 0.01
		and absf(red_seven - RunScript.laser_dps(7) * RunScript.crit_mult(7) * 0.1) < 0.01
		and absf(edge_seven - RunScript.laser_dps(7) * 0.1) < 0.01 and RunScript.crit_mult(4) == 1.0
		and RunScript.crit_heart(4) == 0.0, [red_five, red_seven, edge_seven])
	# "the next upgrade should increase the size of the red beam and get rid of some white beams".
	check("  each level past it: the red wider and harder, the white side beams fewer (4, then the leaning 2, then none)",
		RunScript.crit_heart(6) > RunScript.crit_heart(5) and RunScript.crit_heart(7) > RunScript.crit_heart(6)
		and RunScript.crit_mult(7) > RunScript.crit_mult(6) and RunScript.crit_mult(6) > RunScript.crit_mult(5)
		and RunScript.side_beams(6).size() == 2 and absf(float(RunScript.side_beams(6)[0][1])) > 0.0
		and RunScript.side_beams(7).is_empty()
		and RunScript.laser_dps(7) * RunScript.crit_mult(7) > RunScript.laser_dps(5) * RunScript.crit_mult(5),
		[RunScript.side_beams(6), RunScript.side_beams(7)])
	run.laser_level = 6
	run.laser = 5.0
	run.call("_shine", 0.0)
	check("  \"fade the white beams a tiny bit and keep red strong\": the white drawn faded, the red at full",
		RunScript.WHITE_FADE < 0.9 and RunScript.WHITE_FADE > 0.6 and RunScript.LASER_HEART.r > 0.9
		and is_equal_approx(float(run.beam.get("red")), RunScript.crit_heart(6)) and (run.beam.get("sides") as Array).size() == 2)
	# THE METEOR SHIELD.
	for f in run.foes.get_children():
		run.foes.remove_child(f)
		f.queue_free()
	run.laser_level = 6
	run.laser = 0.0
	run.state = RunScript.State.RUNNING
	run.lives = 3
	run.untouchable = 0.0
	run.call("_drop", "shield", run.healer.position + Vector2(0.0, -30.0))
	for i in 20:
		run.call("_move_drops", 1.0 / 60.0)
	run.call("_shield_step", 1.0 / 60.0)
	var orbit: Node2D = run.get("shield_orbit")
	var circling: bool = bool(run.get("shield")) and orbit.visible and orbit.get_child_count() == RunScript.SHIELD_METEORS
	run.banner_left = 0.0
	run.call("_drop", "shield", run.healer.position)
	run.call("_move_drops", 1.0 / 60.0)
	var already: String = str(run.banner)
	run.hurt()
	var held: bool = (run.lives == 3 and run.laser_level == 6 and run.power == 4 and not bool(run.get("shield"))
		and is_equal_approx(run.untouchable, RunScript.SHIELD_BLINK))
	run.call("_shield_step", 1.0 / 60.0)
	run.untouchable = 0.0
	run.hurt()
	check("a meteor shield picked up: meteors circling her; the next hit breaks it and takes nothing else, then hits count again",
		circling and already == "Shield up already" and held and not orbit.visible and run.lives == 2,
		[circling, already, held, run.lives])
	check("  shields drop now and then from mages and snipers, and from elites more often",
		RunScript.SHIELD_DROP > 0.0 and RunScript.SHIELD_DROP < 0.15 and RunScript.ELITE_SHIELD > RunScript.SHIELD_DROP)
	run.queue_free()
	await get_tree().process_frame
	print("  (the critical beam and the shield: done)")


func _hr_frames(games: Array, seconds: float, step: float = 1.0 / 30.0) -> void:
	var t: float = 0.0
	while t < seconds:
		for g in games:
			var run: Node = g[0]
			if run.get("begun"):
				run.call("step", step)
			(g[1] as Node).call("_process", step)
		t += step


func _hr_foes(run: Node) -> Array:
	var out: Array = []
	for f in run.get("foes").get_children():
		if int(f.get("batch")) >= 0:
			out.append(f)
	out.sort_custom(func(x: Node, y: Node) -> bool: return int(x.get("slot")) < int(y.get("slot")))
	return out


func _bursts_in(run: Node) -> int:
	const RunScript := preload("res://src/world/healerrun/healerrun.gd")
	var count: int = 0
	for child in run.get_children():
		count += 1 if child is RunScript.Burst else 0
	return count


func google_stand_in(path: String, body: Dictionary, _wait: float, sent: Array, answers: Array) -> Dictionary:
	sent.append([path, body])
	return answers.pop_front() if not answers.is_empty() else {"ok": false, "status": 0}
