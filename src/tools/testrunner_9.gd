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
	# The run puts its swarm and its floor wash beside itself, not under it
	# (2 Nov): left here, the swarm's 256 stand-ins stayed in "enemies" for
	# the rest of the run, and FAR ENEMIES SLEEP counted 257 where it put 1.
	for left_beside in [run.get("swarm"), run.get("floor_wash")]:
		if left_beside != null and is_instance_valid(left_beside):
			(left_beside as Node).queue_free()
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
	# Quarter steps as asked: Sharp pixels (0.114.0) has its own section.
	var was_sharp: bool = bool(Settings.get_value("sharp_pixels"))
	Settings.set_value("sharp_pixels", false)
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
	Settings.set_value("sharp_pixels", was_sharp)
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
		and _func_body(map_src, "func refresh(").contains("WorldMap.fog_image(_area, true)"))

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
	var started_with: int = run.meteors
	run.meteors = 0
	check("no meteor held, Space does nothing", not run.fire_meteor())
	for i in RunScript.METEORS_MOST + 1:
		run.gain_meteor()
	var tough: Node2D = run.meteor_target()
	check("  a run starts with three; a meteor picked up is one more (up to five); it locks on the toughest monster standing",
		started_with == RunScript.METEORS_BASE and RunScript.METEORS_BASE == 3 and run.meteors == RunScript.METEORS_MOST
		and RunScript.METEORS_MOST == 5 and tough != null, [started_with, run.meteors])
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
	# No probe and no resume (2 Nov): on the owner's PC the real server was
	# being asked when the button was pressed, and every check below failed.
	menu.set("talks_to_server", false)
	add_child(menu)
	await get_tree().process_frame
	var button: Button = menu.get("google_button")
	var login: Button = menu.get_node("%loginbutton")
	check("the login screen has \"Sign in with Google\" just under the sign-in button, \"or\" between (0.119.1)",
		button != null and button.text == "Sign in with Google" and button.get_parent() == login.get_parent()
		and button.get_index() == login.get_index() + 2
		and login.get_parent().get_child(login.get_index() + 1).name == "ordivider")
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
	# THE TOWN IT ASKED FOR (loginmenu.gd prefetches it), settled before the
	# next section loads the areas itself: a plain load() of a scene still
	# loading in the background is Godot's deadlock (arearegistry.gd) - the
	# whole suite hung here on 2 Nov, silent, once this section stopped
	# waiting on the real server (0.110.2) and so ended mid-load.
	var settle_until: int = Time.get_ticks_msec() + 20000
	while (not AreaRegistry._prefetching.is_empty() or not AreaRegistry._prefetch_queue.is_empty()) \
			and Time.get_ticks_msec() < settle_until:
		await get_tree().process_frame
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
	# "we need that shield to actually be around the character make it 5 meteors".
	run.shield = true
	run.ghost = false
	var shield_rocks: Array = []
	var behind: int = 0
	var in_front: int = 0
	for i in 30:
		run.call("_shield_step", 1.0 / 30.0)
		for rock in orbit.get_children():
			behind += 1 if int(rock.z_index) == 0 else 0
			in_front += 1 if int(rock.z_index) > 0 else 0
	for rock in orbit.get_children():
		shield_rocks.append((rock as Node2D).position)
	var lowest: float = -INF
	var highest: float = INF
	for at in shield_rocks:
		lowest = maxf(lowest, (at as Vector2).y)
		highest = minf(highest, (at as Vector2).y)
	var middle: Vector2 = orbit.position - run.healer.position
	check("  the shield is round her whole body: five meteors about her middle, behind her at the back and over her at the front",
		orbit.get_child_count() == 5 and middle.is_equal_approx(RunScript.SHIELD_AT)
		and RunScript.SHIELD_REACH * RunScript.SHIELD_SQUASH >= 19.0 and RunScript.SHIELD_AT.y > RunScript.HITBOX_AT.y
		and behind > 0 and in_front > 0, [middle, behind, in_front])
	# "i need that circle perfectly symetrical to the char": a true circle, its
	# middle the middle of her picture - read from her own frame: the halo's
	# columns (even about her) and her top and bottom.
	var frame: Image = (run.healer_sprite.sprite_frames as SpriteFrames).get_frame_texture("idleup", 0).get_image()
	var used: Rect2i = frame.get_used_rect()
	var halo_left: int = frame.get_width()
	var halo_right: int = -1
	for x in frame.get_width():
		if frame.get_pixel(x, used.position.y).a > 0.0:
			halo_left = mini(halo_left, x)
			halo_right = maxi(halo_right, x)
	var corner: Vector2 = run.healer_sprite.offset - Vector2(frame.get_size()) / 2.0
	var her_middle := Vector2(corner.x + (halo_left + halo_right + 1) / 2.0,
		corner.y + used.position.y + used.size.y / 2.0)
	var on_ring: bool = true
	for at in shield_rocks:
		on_ring = on_ring and absf((at as Vector2).length() - RunScript.SHIELD_REACH) < 0.01
	check("  a true circle about the middle of her picture (%s), every meteor on it, wide enough for all of her"
		% str(her_middle), RunScript.SHIELD_SQUASH == 1.0 and her_middle.is_equal_approx(RunScript.SHIELD_AT)
		and on_ring and RunScript.SHIELD_REACH >= used.size.y / 2.0 + 2.0, [her_middle, RunScript.SHIELD_AT])
	# THE METEORS ON HAND: "show 3 meteors at the bottom right meteor can
	# increase if looted but it should have a recharge".
	run.shield = false
	run.state = RunScript.State.RUNNING
	run.meteors = 0
	run.meteor_charge = 0.0
	for i in int(RunScript.METEOR_RECHARGE * 10.0) + 2:
		run.call("_recharge_meteors", 0.1)
	var one_back: int = run.meteors
	for i in int(RunScript.METEOR_RECHARGE * 10.0 * 3.0) + 5:
		run.call("_recharge_meteors", 0.1)
	var at_base: int = run.meteors
	run.gain_meteor()
	for i in int(RunScript.METEOR_RECHARGE * 10.0) + 2:
		run.call("_recharge_meteors", 0.1)
	check("meteors spent come back, one every %d s, up to three; one looted is a fourth, and the recharge waits"
		% int(RunScript.METEOR_RECHARGE), one_back == 1 and at_base == RunScript.METEORS_BASE
		and run.meteors == RunScript.METEORS_BASE + 1 and is_equal_approx(float(run.meteor_charge), 0.0),
		[one_back, at_base, run.meteors])
	# With the party, a player's meteor takes its share of the boss over the players.
	run.players = 2
	run.call("_start_boss")
	var boss_most: float = float(run.boss.get("most"))
	var boss_was: float = float(run.boss.get("health"))
	run.call("_land_meteor", run.boss.position, run.boss)
	var took: float = boss_was - float(run.boss.get("health"))
	check("  with a party of two, each one's meteor takes half its share of the keeper (the party's together, one player's)",
		absf(took - maxf(RunScript.METEOR_HIT, boss_most * RunScript.METEOR_BOSS_SHARE / 2.0)) < 0.01, [took, boss_most])
	# The bottom right.
	const ScreenScript := preload("res://src/world/healerrun/healerrunscreen.gd")
	var screen: CanvasLayer = ScreenScript.new()
	screen.set("may_be_god", func() -> bool: return false)
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	var srun: Node = screen.get("run")
	srun.set("meteors", 1)
	srun.set("meteor_charge", 0.5)
	screen.call("paint_meteors")
	var slots: Array = screen.get("meteor_slots")
	var shown: Array = []
	for slot in slots:
		shown.append([slot.visible, snappedf(float(slot.value), 0.01)])
	srun.set("meteors", 5)
	screen.call("paint_meteors")
	var five_shown: int = 0
	for slot in slots:
		five_shown += 1 if slot.visible and is_equal_approx(float(slot.value), 1.0) else 0
	var box: Control = screen.get("meteor_box")
	check("  bottom right: three meteors, held full, the next filling as it recharges, the rest dark; five when looted",
		shown == [[true, 1.0], [true, 0.5], [true, 0.0], [false, 0.0], [false, 0.0]] and five_shown == 5
		and box.anchor_left == 1.0 and box.anchor_top == 1.0 and str(screen.get("meteor_line").text) == "", shown)
	screen.call("close")
	run.queue_free()
	await get_tree().process_frame
	print("  (the critical beam and the shield: done)")


func _test_the_mages_stand() -> void:
	section("THE MAGE'S STAND (0.108.0 step 2; 0.109.0 the pick; 0.110.0 the wall)")
	# The owner: "mage would use mythic weapon stand on a wall and protect the
	# portal from enemies going in", "we can use the door as the gate enemies
	# break it then run through to the portal", "no limit on meteors", "make
	# field of view longer", "the door need to be slightly transparent".
	const StandScript := preload("res://src/world/magestand/magestand.gd")
	const RunScript := preload("res://src/world/healerrun/healerrun.gd")
	const ScreenScript := preload("res://src/world/magestand/magestandscreen.gd")
	var stand = StandScript.new()
	stand.set("seed_value", 4)
	stand.set("steer", func() -> float: return 0.0)
	add_child(stand)
	stand.set_process(false)
	# THE PLACE.
	var gate: Node2D = stand.world.get_node("gate")
	var faces: int = 0
	var left_end: float = INF
	var right_end: float = -INF
	for child in stand.world.get_children():
		if child is Node2D and str((child as Node2D).scene_file_path).contains("wallrun"):
			faces += 1
			left_end = minf(left_end, (child as Node2D).position.x)
			right_end = maxf(right_end, (child as Node2D).position.x)
	var caps: int = 0
	var cap_reach: Array = [0.0, 0.0]
	# 0.109.0, "fix the missing squares by the gate": the caps start at the
	# gate's posts, over the pillars' tops - not from the pillars out.
	var cap_from: Array = [INF, INF]
	for child in stand.get_children():
		if child is Sprite2D and is_equal_approx((child as Sprite2D).rotation, PI / 2.0):
			caps += 1
			var cap_x: float = (child as Sprite2D).position.x
			var cap_side: int = 0 if cap_x < 0.0 else 1
			cap_reach[cap_side] = maxf(float(cap_reach[cap_side]), absf(cap_x) + StandScript.CAP_REGION.size.y / 2.0)
			cap_from[cap_side] = minf(float(cap_from[cap_side]), absf(cap_x) - StandScript.CAP_REGION.size.y / 2.0)
	# "there is a gap on the right side of the wall": each side's face, end to
	# end from the gate, reaches the side wall.
	var widths := {"wallrun4": 101.0, "wallrun2": 51.0, "wallrun1": 26.0}
	var spans: Array = [[], []]
	for child in stand.world.get_children():
		var path: String = str((child as Node).scene_file_path) if child is Node2D else ""
		for key in widths:
			if path.contains(str(key)):
				var x: float = (child as Node2D).position.x
				var w: float = float(widths[key])
				(spans[0 if x < 0.0 else 1] as Array).append([absf(x) - w / 2.0, absf(x) + w / 2.0])
	var whole: bool = true
	for side_spans in spans:
		(side_spans as Array).sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		var edge: float = StandScript.GATE_HALF
		for one in side_spans:
			whole = whole and absf(float(one[0]) - edge) < 0.01
			edge = float(one[1])
		whole = whole and edge >= StandScript.PATH_HALF + 4.0
	var see_through: bool = true
	for part in stand.get("door_parts"):
		see_through = see_through and is_equal_approx((part as Sprite2D).modulate.a, StandScript.DOOR_SEE)
	check("the place: a wall across with the crypt door as its gate, no gap from the gate to either side wall, caps on top, the portal behind",
		faces >= 6 and left_end < -200.0 and right_end > 200.0 and caps > 10 and gate.position.y == StandScript.FOOT
		and whole and float(cap_reach[0]) >= StandScript.PATH_HALF and float(cap_reach[1]) >= StandScript.PATH_HALF
		and stand.portal_sprite.position == StandScript.PORTAL_AT and stand.portal_sprite.sprite_frames != null,
		[faces, caps, left_end, right_end])
	check("  the caps run right up to the gate's posts on both sides, over the pillars - no notch by the gate",
		absf(float(cap_from[0]) - StandScript.GATE_HALF) < 0.01 and absf(float(cap_from[1]) - StandScript.GATE_HALF) < 0.01,
		cap_from)
	check("  further out than the Healer's Run (half as far again each way); the gate see-through, monsters drawn behind it",
		StandScript.VIEW == RunScript.VIEW * 1.5 and see_through and StandScript.DOOR_SEE < 0.8
		and stand.world.y_sort_enabled and stand.monsters.y_sort_enabled and gate.get_parent() == stand.world
		and stand.monsters.get_parent() == stand.world)
	# HER.
	var mage: AnimatedSprite2D = stand.mage
	var from_x: float = mage.position.x
	stand.set("steer", func() -> float: return -1.0)
	stand.state = StandScript.State.BETWEEN
	stand.set("_left", 999.0)
	for i in 30:
		stand.step(1.0 / 30.0)
	var walked: float = from_x - mage.position.x
	for i in 300:
		stand.step(1.0 / 30.0)
	var at_end: float = mage.position.x
	check("she walks the wall's top, held to its ends, drawn over its caps",
		absf(walked - StandScript.WALK_SPEED) < 1.0 and is_equal_approx(at_end, -StandScript.WALK_HALF)
		and is_equal_approx(mage.position.y, StandScript.WALK_Y) and mage.z_index > 1, [walked, mage.position])
	# HER SIDE (0.110.2, "make sure mage cannot walk across the bridge 2 people
	# on left 2 on the right"): walking for the gate, she stops at its pillar.
	stand.set("steer", func() -> float: return 1.0)
	for i in 300:
		stand.step(1.0 / 30.0)
	var by_gate_left: float = mage.position.x
	stand.set("her_side", 1.0)
	mage.position.x = 100.0
	stand.set("steer", func() -> float: return -1.0)
	for i in 300:
		stand.step(1.0 / 30.0)
	var by_gate_right: float = mage.position.x
	stand.set("her_side", -1.0)
	mage.position.x = -150.0
	var seats: Array = []
	for seat in 4:
		seats.append(StandScript.side_for(seat))
	check("  and never crosses the gate: on the left she stops at %.0f, on the right at %.0f; a party's four seats sit %s"
		% [by_gate_left, by_gate_right, str(seats)],
		is_equal_approx(by_gate_left, -StandScript.SIDE_INNER) and is_equal_approx(by_gate_right, StandScript.SIDE_INNER)
		and StandScript.SIDE_INNER > StandScript.GATE_HALF and seats == [-1.0, 1.0, -1.0, 1.0])
	stand.set("steer", func() -> float: return 0.0)
	# THE METEORS: "no limit on meteors".
	var target: Node2D = stand.spawn("slime", Vector2(0.0, -60.0))
	target.set("speed", 0.0)
	target.set("most", 1000.0)
	target.set("health", 1000.0)
	var far: Node2D = stand.spawn("slime", Vector2(200.0, -200.0))
	far.set("speed", 0.0)
	far.set("health", 1000.0)
	stand.aim = Vector2(0.0, -60.0)
	stand.casting = true
	var casts_before: int = stand.casts
	for i in 30:
		stand.step(1.0 / 30.0)
	var in_a_second: int = stand.casts - casts_before
	for i in 270:
		stand.step(1.0 / 30.0)
	var in_ten: int = stand.casts - casts_before
	stand.casting = false
	for i in 30:
		stand.step(1.0 / 30.0)
	var took: float = 1000.0 - float(target.get("health"))
	check("hold the button and meteors rain where she aims - %d in a second, %d in ten, no limit but the gap"
		% [in_a_second, in_ten], in_a_second >= 3 and in_ten >= int(10.0 / StandScript.CAST_GAP) - 1
		and took >= StandScript.BLAST_DAMAGE * in_ten and is_equal_approx(float(far.get("health")), 1000.0),
		[in_a_second, in_ten, took])
	var crit_was: int = stand.crits
	var casts_was: int = stand.casts
	for i in 1000:
		stand.drop_meteor(Vector2(-250.0, -250.0))
	var share: float = float(stand.crits - crit_was) / float(stand.casts - casts_was)
	for fall in stand.falling:
		(fall["rock"] as Node).queue_free()
	stand.falling.clear()
	check("  one in five critical (%d%% of a thousand)" % roundi(share * 100.0), absf(share - StandScript.CRIT_CHANCE) < 0.04)
	for m in stand.monsters.get_children():
		stand.monsters.remove_child(m)
		m.queue_free()
	stand.craters.clear()
	var burnt: Node2D = stand.spawn("sprite", Vector2(100.0, 0.0))
	burnt.set("speed", 0.0)
	burnt.set("health", 100.0)
	stand.craters.append({"at": Vector2(100.0, 0.0), "left": StandScript.BURN_SECONDS, "seed": 1.0})
	for i in 60:
		stand.step(1.0 / 60.0)
	check("  each leaves the ground burning: a crater hurts what stands in it",
		absf((100.0 - float(burnt.get("health"))) - StandScript.BURN_DPS) < 0.2, burnt.get("health"))
	# 0.110.0: craters do not stack - five on one spot burn as one.
	burnt.set("health", 100.0)
	stand.craters.clear()
	for i in 5:
		stand.craters.append({"at": Vector2(100.0, 0.0), "left": StandScript.BURN_SECONDS, "seed": 1.0})
	for i in 60:
		stand.step(1.0 / 60.0)
	check("  and craters do not stack: five on one spot burn as one",
		absf((100.0 - float(burnt.get("health"))) - StandScript.BURN_DPS) < 0.2, burnt.get("health"))
	for m in stand.monsters.get_children():
		stand.monsters.remove_child(m)
		m.queue_free()
	stand.craters.clear()
	# THE WALL IN STRETCHES (0.110.0): "enemies just run in a line when door
	# is broken focus fire at gate easy".
	var stretch_count: int = stand.stretches.size()
	var all_faced: bool = stretch_count == 6
	for one in stand.stretches:
		all_faced = all_faced and not (one["pieces"] as Array).is_empty() and is_equal_approx(float(one["health"]), StandScript.WALL_MOST)
	var aims := {"gate": 0, "left": 0, "right": 0}
	for i in 90:
		var came_x: float = -300.0 + 600.0 * float(i) / 89.0
		var where: int = stand.choose_target("sprite", came_x)
		if where < 0:
			aims["gate"] += 1
		elif float(stand.stretches[where]["side"]) < 0.0:
			aims["left"] += 1
		else:
			aims["right"] += 1
	var bomber_aims: bool = true
	for i in 30:
		bomber_aims = bomber_aims and stand.choose_target("bomber", -200.0 + 13.0 * i) >= 0
	check("the wall is six stretches either side of the gate; the horde goes for the gate and for both sides (%s), a bomber never the gate" % str(aims),
		all_faced and int(aims["gate"]) > 10 and int(aims["left"]) > 10 and int(aims["right"]) > 10 and bomber_aims, aims)
	stand.wave = 1
	stand.state = StandScript.State.WAVE
	stand.set("_to_spawn", 0)
	var breakers: Array = []
	for i in 8:
		var m: Node2D = stand.spawn("slime", Vector2.ZERO)
		stand.send_to(m, 1)
		m.position = Vector2(float(m.get("stop_x")), StandScript.FOOT - 26.0 - float(m.get("stop_y")))
		m.set("health", 1000.0)
		breakers.append(m)
	stand.stretches[1]["health"] = 10.0
	for i in 30:
		stand.step(1.0 / 30.0)
	var breached: bool = bool(stand.stretches[1]["broken"]) and stand.breaches() == 1
	var faces_down: bool = true
	for face in stand.stretches[1]["pieces"]:
		faces_down = faces_down and not (face as Node2D).visible
	var rubble_laid: bool = (stand.stretches[1]["rubble"] as Array).size() > 0
	for i in 240:
		stand.step(1.0 / 30.0)
	var went_through: int = 0
	for m in breakers:
		if not is_instance_valid(m) or bool(m.get("through")):
			went_through += 1
	check("  a stretch hit to nought is breached - its face down, rubble in the gap - and its attackers run through for the portal",
		breached and faces_down and rubble_laid and went_through == breakers.size() and stand.portal < StandScript.PORTAL_MOST
		and stand.door == stand.door_most, [breached, faces_down, rubble_laid, went_through])
	stand.portal = StandScript.PORTAL_MOST
	var weakest_was: int = stand.weakest()
	var patch_sure: bool = stand.roll_offers().has("patch")
	var said: String = stand.offer_level_text("patch")
	stand.state = StandScript.State.PICK
	stand.picks_left = 1
	stand.offers = ["patch"]
	stand.pick(0)
	var rebuilt: bool = not bool(stand.stretches[1]["broken"]) and is_equal_approx(float(stand.stretches[1]["health"]), StandScript.WALL_MOST * StandScript.PATCH_SHARE)
	for face in stand.stretches[1]["pieces"]:
		rebuilt = rebuilt and (face as Node2D).visible
	await get_tree().process_frame
	for rubble in stand.stretches[1]["rubble"]:
		rebuilt = false
	check("  a breach always brings the Repair card (\"%s\"), which mends the weakest - rebuilding the breach" % said,
		weakest_was == 1 and patch_sure and said == "A breach to mend" and rebuilt, [weakest_was, patch_sure, said])
	# BOMBERS.
	for m in stand.monsters.get_children():
		stand.monsters.remove_child(m)
		m.queue_free()
	stand.state = StandScript.State.WAVE
	var slain_was: int = stand.slain
	var bomber: Node2D = stand.spawn("bomber", Vector2.ZERO)
	stand.send_to(bomber, 4)
	bomber.position = Vector2(float(bomber.get("stop_x")), StandScript.FOOT - 24.0)
	stand.step(1.0 / 30.0)
	var bombed: bool = is_equal_approx(float(stand.stretches[4]["health"]), StandScript.WALL_MOST - StandScript.BOMB_HIT) \
		and not is_instance_valid(bomber) or (is_instance_valid(bomber) and bomber.get_parent() == null)
	bombed = bombed and is_equal_approx(float(stand.stretches[4]["health"]), StandScript.WALL_MOST - StandScript.BOMB_HIT) and stand.slain == slain_was
	var lit: Node2D = stand.spawn("bomber", Vector2(0.0, -100.0))
	var near: Node2D = stand.spawn("slime", Vector2(12.0, -100.0))
	near.set("health", StandScript.BOMB_DAMAGE - 1.0)
	stand.hurt(lit, 9999.0)
	check("  a bomber at the wall blows %d off its stretch and is gone, no kill; one slain on its way blows up its neighbours; from wave %d"
		% [int(StandScript.BOMB_HIT), StandScript.BOMBERS_FROM], bombed and float(near.get("dying")) >= 0.0
		and StandScript.bomber_chance(StandScript.BOMBERS_FROM - 1) == 0.0 and StandScript.bomber_chance(StandScript.BOMBERS_FROM) > 0.0
		and is_equal_approx(StandScript.bomber_chance(60), StandScript.BOMBER_MOST) and lit.get("fuse") != null,
		[stand.stretches[4]["health"], stand.slain - slain_was, near.get("health")])
	for m in stand.monsters.get_children():
		stand.monsters.remove_child(m)
		m.queue_free()
	stand.state = StandScript.State.BETWEEN
	# THE GATE AND THE PORTAL: "enemies break it then run through to the portal".
	stand.wave = 1
	stand.state = StandScript.State.WAVE
	stand.set("_to_spawn", 0)
	var crowd: Array = []
	for i in 14:
		var m: Node2D = stand.spawn("sprite" if i % 2 == 0 else "slime", Vector2.ZERO)
		stand.send_to(m, -1)
		m.position = Vector2(float(m.get("stop_x")), StandScript.FOOT - 26.0 - float(m.get("stop_y")))
		m.set("health", 1000.0)
		crowd.append(m)
	stand.door = 20.0
	var door_was: float = stand.door
	stand.step(0.1)
	var one_tick: float = door_was - stand.door
	for i in 60:
		stand.step(1.0 / 30.0)
	var broke: bool = stand.gate_broken() and absf(stand.door_planks.rotation) > 1.0
	var portal_was: int = stand.portal
	for i in 300:
		stand.step(1.0 / 30.0)
	check("monsters at the gate hit it (at most %d at once); at nought it breaks and they run through, draining the portal"
		% StandScript.GATE_HITTERS, absf(one_tick - StandScript.DOOR_HIT * StandScript.GATE_HITTERS * 0.1) < 0.01
		and broke and stand.portal < portal_was, [one_tick, broke, portal_was, stand.portal])
	var fell: Array = []
	stand.finished.connect(func() -> void: fell.append(1))
	stand.portal = 1
	var last: Node2D = stand.spawn("slime", StandScript.PORTAL_AT + Vector2(0.0, -30.0))
	last.set("through", true)
	for i in 60:
		stand.step(1.0 / 30.0)
	check("  the portal at nought: the run is over, and says how far it got",
		stand.state == StandScript.State.LOST and fell.size() == 1 and str(stand.result_text()).contains("held"),
		stand.result_text())
	# THE WAVES: "progressivly getting harder".
	check("each wave more, faster and tougher: %d, %d, %d monsters; wave 10 %.0f%% the speed and %.0f%% the health of the first"
		% [stand.wave_count(1), stand.wave_count(2), stand.wave_count(10), StandScript.wave_speed(10) * 100.0,
		StandScript.wave_health(10) * 100.0], stand.wave_count(2) > stand.wave_count(1)
		and stand.wave_count(10) > stand.wave_count(2) and StandScript.wave_speed(10) > StandScript.wave_speed(1)
		and StandScript.wave_health(10) > StandScript.wave_health(1) and StandScript.wave_hit(10) > 1.0)
	stand.queue_free()
	var fresh = StandScript.new()
	fresh.set("seed_value", 6)
	fresh.set("steer", func() -> float: return 0.0)
	add_child(fresh)
	fresh.set_process(false)
	for i in int(StandScript.READY_SECONDS * 30.0) + 4:
		fresh.step(1.0 / 30.0)
	var started: bool = fresh.state == StandScript.State.WAVE and fresh.wave == 1
	var spawned: int = 0
	for i in 600:
		fresh.step(1.0 / 30.0)
		for m in fresh.monsters.get_children():
			if float(m.get("dying")) < 0.0:
				fresh.hurt(m, 9999.0)
				spawned += 1
		if fresh.state == StandScript.State.BETWEEN:
			break
	# "every 3 levels passed should pull up upgrade menu": wave 1 held, no
	# pick - the next comes on its own.
	var first_held: int = fresh.waves_held
	var no_pick_yet: bool = fresh.state == StandScript.State.BETWEEN and (fresh.offers as Array).is_empty()
	var said_when: String = str(fresh.banner)
	# Waves 2 and 3, held: the third brings the pick.
	fresh.waves_held = 2
	fresh.wave = 3
	for m in fresh.monsters.get_children():
		fresh.call("_gone", m)
	fresh.set("_to_spawn", 0)
	fresh.state = StandScript.State.WAVE
	fresh.step(1.0 / 30.0)
	var held_then_pick: bool = fresh.state == StandScript.State.PICK and fresh.waves_held == 3
	check("  a pick every %d waves: wave 1 held brings none (\"%s\"), wave 3 does" % [StandScript.PICK_EVERY, said_when],
		first_held == 1 and no_pick_yet and said_when.contains("after wave 3") and held_then_pick
		and StandScript.picks_due(2, 3) == 1 and StandScript.picks_due(3, 5) == 0 and StandScript.picks_due(2, 7) == 2)
	# THE PICK (0.109.0): the next wave waits, and the clock, until she picks.
	var offered: Array = (fresh.offers as Array).duplicate()
	var clock: float = fresh.run_seconds
	fresh.set("casting", true)
	for i in 90:
		fresh.step(1.0 / 30.0)
	var waited: bool = fresh.state == StandScript.State.PICK and fresh.wave == 3 and is_equal_approx(fresh.run_seconds, clock)
	var distinct: bool = offered.size() == StandScript.PICK_COUNT
	for id in offered:
		distinct = distinct and offered.count(id) == 1 and StandScript.UPGRADES.has(id)
	fresh.set("casting", false)
	var first: String = str(offered[0]) if not offered.is_empty() else ""
	var level_before: int = fresh.level(first)
	var door_before: float = fresh.door
	var picked: bool = fresh.pick(0)
	var it_took: bool = (fresh.door > door_before) if first == "patch" else fresh.level(first) == level_before + 1
	check("the pick waits for %d different upgrades (%s); the clock stops; one taken, the next wave follows"
		% [StandScript.PICK_COUNT, ", ".join(offered)], held_then_pick and waited and distinct and picked and it_took
		and fresh.state == StandScript.State.BETWEEN and not fresh.pick(1), [offered, fresh.state, fresh.wave])
	for i in int(StandScript.AFTER_PICK_SECONDS * 30.0) + 4:
		fresh.step(1.0 / 30.0)
	var next_came: bool = fresh.state == StandScript.State.WAVE and fresh.wave == 4
	# "gate should not auto recharge every round": a wave held leaves it as
	# it is; only the patch mends it, and rebuilds a broken one - which is
	# then always one of the cards.
	for m in fresh.monsters.get_children():
		fresh.call("_gone", m)
	fresh.set("_to_spawn", 0)
	fresh.door = 120.0
	fresh.call("_end_wave")
	var left_alone: bool = is_equal_approx(fresh.door, 120.0) and fresh.state == StandScript.State.BETWEEN
	fresh.state = StandScript.State.PICK
	fresh.door = 0.0
	fresh.call("_break_gate")
	var offered_patch: bool = fresh.roll_offers().has("patch")
	fresh.offers = ["patch", "cast", "blast"]
	fresh.pick(0)
	check("  then wave 4; a wave held leaves the gate as it is; a broken one always brings the patch, which rebuilds it",
		started and spawned == fresh.wave_count(1) and next_came and left_alone
		and offered_patch and is_equal_approx(fresh.door, StandScript.DOOR_MOST * StandScript.PATCH_SHARE)
		and is_equal_approx(fresh.door_planks.rotation, 0.0), [started, spawned, fresh.waves_held, fresh.door])
	# Struck, the gate shakes and flashes; low, it says so.
	fresh.door = fresh.door_most * 0.2
	fresh.state = StandScript.State.WAVE
	var striker: Node2D = fresh.spawn("slime", Vector2(0.0, StandScript.FOOT - 30.0))
	fresh.send_to(striker, -1)
	striker.set("stop_x", 0.0)
	striker.set("stop_y", 4.0)
	for i in 20:
		fresh.call("_move_monsters", 1.0 / 30.0)
		fresh.run_seconds += 1.0 / 30.0
	var gate_node: Node2D = fresh.world.get_node("gate")
	var shook: bool = bool(fresh.gate_struck) and absf(gate_node.position.x) > 0.0 or bool(fresh.gate_struck)
	check("  struck, the gate shakes and flashes; under a quarter it is low",
		shook and fresh.gate_low(), [fresh.gate_struck, gate_node.position, fresh.door])
	fresh.queue_free()
	# Each upgrade does what its card says, and stacks to its most.
	var up = StandScript.new()
	up.set("seed_value", 9)
	up.set("steer", func() -> float: return 0.0)
	add_child(up)
	up.set_process(false)
	var plain: Array = [up.cast_gap(), up.blast_reach(), up.blast_damage(), up.burn_seconds(), up.crit_chance()]
	up.levels = {"cast": 1, "blast": 1, "power": 1, "burn": 1, "crit": 1}
	check("  each card's numbers: casting 15% faster, blasts 20% wider and 25% harder, burns 40% longer, 8% more criticals",
		is_equal_approx(up.cast_gap(), float(plain[0]) / 1.15) and is_equal_approx(up.blast_reach(), float(plain[1]) * 1.2)
		and is_equal_approx(up.blast_damage(), float(plain[2]) * 1.25) and is_equal_approx(up.burn_seconds(), float(plain[3]) * 1.4)
		and is_equal_approx(up.crit_chance(), float(plain[4]) + 0.08), [plain, up.cast_gap(), up.blast_reach()])
	for id in StandScript.UPGRADE_ORDER:
		if id != "patch":
			up.levels[id] = StandScript.UPGRADE_MOST
	for id in StandScript.EVOLUTIONS:
		up.levels[id] = 1
	up.door = up.door_most
	var none_left: bool = up.roll_offers().is_empty()
	up.levels["pull"] = 0
	up.door = up.door_most * 0.5
	var only: Array = up.roll_offers()
	only.sort()
	check("  nothing past its most is offered, and the patch only while the gate is short",
		none_left and only == ["patch", "pull"], only)
	up.levels = {"double": StandScript.UPGRADE_MOST}
	up.state = StandScript.State.WAVE
	up.set("_to_spawn", 0)
	up.spawn("slime", Vector2(0.0, -200.0)).set("health", 99999.0)
	up.set("aim", Vector2(0.0, -60.0))
	up.set("casting", true)
	var up_casts_from: int = up.casts
	for i in 300:
		up.step(1.0 / 30.0)
	var per_cast: float = float(up.casts - up_casts_from) / (10.0 / up.cast_gap())
	up.set("casting", false)
	up.levels = {"pull": StandScript.UPGRADE_MOST}
	var packed: Node2D = up.spawn("sprite", Vector2(60.0, -60.0))
	packed.set("health", 99999.0)
	var pulled_from: float = packed.position.distance_to(Vector2(0.0, -60.0))
	for i in 40:
		up.call("_land", {"at": Vector2(0.0, -60.0), "rock": null, "crit": false})
	var pulled: bool = packed.position.distance_to(Vector2(0.0, -60.0)) < pulled_from * 0.5
	check("  double cast at its most: %.2f meteors a cast; the pull drags a pack in" % per_cast,
		per_cast > 1.3 and per_cast < 2.0 and pulled, [per_cast, packed.position])
	# EVOLUTIONS: two upgrades at their most bring a card of their own.
	up.levels = {"blast": StandScript.UPGRADE_MOST, "burn": StandScript.UPGRADE_MOST - 1}
	up.door = up.door_most
	var not_yet: bool = not up.roll_offers().has("firestorm")
	up.levels["burn"] = StandScript.UPGRADE_MOST
	var storm_offered: bool = up.roll_offers().has("firestorm")
	var plain_burn: Array = [up.burn_reach(), up.burn_dps()]
	up.offers = ["firestorm", "cast", "power"]
	up.state = StandScript.State.PICK
	up.picks_left = 1
	up.pick(0)
	check("  an evolution comes only with both its upgrades at their most, always offered; Firestorm doubles the burn",
		not_yet and storm_offered and is_equal_approx(up.burn_reach(), float(plain_burn[0]) * 2.0)
		and is_equal_approx(up.burn_dps(), float(plain_burn[1]) * 2.0) and not up.roll_offers().has("firestorm")
		and str(up.offer_level_text("shower")) == "Evolution", [not_yet, storm_offered, up.levels])
	up.levels = {"shower": 1, "crit": StandScript.UPGRADE_MOST}
	up.falling = []
	up.call("_land", {"at": Vector2(0.0, -60.0), "rock": null, "crit": true})
	var pieces: int = up.falling.size()
	up.falling = []
	up.levels = {"comet": 1}
	for i in StandScript.COMET_EVERY:
		up.drop_meteor(Vector2(0.0, -60.0))
	var comets: int = 0
	for fall in up.falling:
		comets += 1 if bool(fall.get("comet", false)) else 0
	check("  a critical splits into %d small meteors with Meteor shower; every %dth meteor is a comet"
		% [pieces, StandScript.COMET_EVERY], pieces == StandScript.SHOWER_PIECES and comets == 1)
	for fall in up.falling:
		if is_instance_valid(fall["rock"]):
			(fall["rock"] as Node).queue_free()
	up.falling = []
	# A REROLL, and CALLING EARLY: a reroll for it, and its pick still comes.
	up.levels = {}
	up.offers = ["cast", "blast", "power"]
	up.state = StandScript.State.PICK
	var had: int = up.rerolls
	var rerolled: bool = up.reroll()
	var spent: bool = up.rerolls == had - 1 and not up.reroll() and up.offers.size() == StandScript.PICK_COUNT
	up.state = StandScript.State.WAVE
	up.waves_held = 2
	up.wave = 3
	up.set("_to_spawn", 0)
	var early_on: bool = up.can_call_early()
	var called: bool = up.call_early()
	for i in 2:
		up.set("_to_spawn", 0)
		up.call_early()
	var early_wave: int = up.wave
	for m in up.monsters.get_children():
		up.call("_gone", m)
	up.set("_to_spawn", 0)
	up.call("_end_wave")
	var owed: int = up.picks_left
	up.pick(0)
	var still_picking: bool = up.state == StandScript.State.PICK
	up.pick(0)
	check("  one reroll a run draws three new cards; calling early starts the next wave and brings a reroll; waves 3 to 6 held together bring two picks",
		rerolled and spent and early_on and called and early_wave == 6 and up.rerolls == 3 and owed == 2 and still_picking
		and up.state == StandScript.State.BETWEEN, [owed, up.rerolls, up.state])
	up.state = StandScript.State.BETWEEN
	var arrow_before: bool = up.arrow_showing()
	var marked: float = up.next_x
	up.state = StandScript.State.WAVE
	up.set("_to_spawn", 30)
	var before_count: int = up.monsters.get_child_count()
	up.call("_spawn_group")
	var near_mark: bool = true
	var new_ones: Array = up.monsters.get_children().slice(before_count)
	for m in new_ones:
		near_mark = near_mark and absf((m as Node2D).position.x - marked) <= 71.0 \
			or absf((m as Node2D).position.x) >= StandScript.PATH_HALF - 13.0
	check("  an arrow shows where the next group comes in, and it comes in there",
		arrow_before and near_mark and not new_ones.is_empty() and up.arrow_showing(), [marked, new_ones.size()])
	up.queue_free()
	var bare = StandScript.new()
	check("  and no god mode in the Stand", not ("god" in bare))
	bare.free()
	# THE SCREEN.
	var screen: CanvasLayer = ScreenScript.new()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	var pic: TextureRect = screen.get("picture")
	var box: Rect2 = pic.get_global_rect()
	var middle: Vector2 = screen.world_from_screen(box.get_center())
	var fit: float = minf(box.size.x / StandScript.VIEW.x, box.size.y / StandScript.VIEW.y)
	var corner: Vector2 = box.get_center() - StandScript.HALF * fit
	var top_left: Vector2 = screen.world_from_screen(corner)
	screen.set("mouse_at", func() -> Vector2: return box.get_center() + Vector2(10.0, 20.0) * fit)
	screen.set("mouse_held", func() -> bool: return true)
	var panel_first: bool = screen.get("start_panel").visible
	screen.call("_process", 0.0)
	var held_on_panel: bool = bool(screen.get("run").get("casting"))
	screen.begin()
	screen.call("_process", 0.0)
	var srun: Node = screen.get("run")
	check("the screen: the start panel first; the mouse is turned into the stand's own space and casts once begun",
		panel_first and middle.length() < 0.6 and top_left.distance_to(-StandScript.HALF) < 0.6 and not held_on_panel
		and srun.get("aim").distance_to(Vector2(10.0, 20.0)) < 0.6 and bool(srun.get("casting"))
		and not screen.get("start_panel").visible, [middle, top_left, srun.get("aim")])
	# THE WORDS ON THE PICTURE (0.109.0, "clean up ui"): the strip and Leave
	# sit inside the drawn picture, whatever the window's shape.
	var drawn: Rect2 = screen.drawn_rect()
	var strip_box: Rect2 = (screen.get("strip") as Control).get_global_rect()
	var leave_box: Rect2 = (screen.get("leave_button") as Control).get_global_rect()
	var slain_box: Rect2 = (screen.get("slain_line") as Control).get_global_rect()
	check("  the words sit on the picture: the strip across its top, the slain and Leave inside it, no god switch",
		drawn.size.x > 0.0 and strip_box.position.distance_to(drawn.position) < 1.0
		and absf(strip_box.size.x - drawn.size.x) < 1.0 and drawn.grow(1.0).encloses(leave_box)
		and drawn.grow(1.0).encloses(slain_box) and screen.get_node_or_null("god") == null,
		[drawn, strip_box, leave_box, slain_box])
	# ON A PHONE (0.110.1, "no joystick on mobil believe we only need left
	# joystick"): a stick of its own in the dark left of the field; a finger
	# on the field aims and casts, one on the stick does not; the stick walks.
	TouchControls.set_active(true)
	screen.call("_process", 0.0)
	var phone_stick: Control = screen.get("stick")
	var zone: Rect2 = screen.stick_zone()
	var stick_up: bool = phone_stick.visible and zone.size.x > 0.0 and zone.size.y > 0.0
	var field_point: Vector2 = drawn.get_center() + Vector2(0.0, -drawn.size.y * 0.2)
	var finger := InputEventScreenTouch.new()
	finger.index = 1
	finger.position = field_point
	finger.pressed = true
	screen.call("_input", finger)
	screen.call("_process", 0.0)
	var aims_there: bool = bool(srun.get("casting")) \
		and (srun.get("aim") as Vector2).distance_to(screen.world_from_screen(field_point)) < 1.0
	var lifted := InputEventScreenTouch.new()
	lifted.index = 1
	lifted.position = field_point
	lifted.pressed = false
	screen.call("_input", lifted)
	var thumb := InputEventScreenTouch.new()
	thumb.index = 0
	thumb.position = zone.get_center()
	thumb.pressed = true
	screen.call("_input", thumb)
	screen.call("_process", 0.0)
	var thumb_no_cast: bool = not bool(srun.get("casting")) and int(screen.get("_aim_finger")) == -1
	var on_stick := InputEventScreenTouch.new()
	on_stick.index = 0
	on_stick.position = Vector2(40.0, 60.0)
	on_stick.pressed = true
	phone_stick.call("_gui_input", on_stick)
	var slide := InputEventScreenDrag.new()
	slide.index = 0
	slide.position = Vector2(140.0, 60.0)
	phone_stick.call("_gui_input", slide)
	TouchControls.call("_physics_process", 1.0 / 60.0)
	var walks: bool = Input.is_action_pressed("move_right") and float(srun.call("_read_steer")) > 0.0
	# MOUNTED, AND READ AS IT LIES (0.110.2): the thumb dragged far past the
	# rim leaves the stick where it stands, the knob at its rim, and the
	# Stand walks full; a little push walks slowly.
	var stand_rest: Vector2 = phone_stick.get("rest")
	var stand_r: float = float(phone_stick.get("radius"))
	var stand_box: Rect2 = phone_stick.get_global_rect()
	var past_rim := InputEventScreenDrag.new()
	past_rim.index = 0
	past_rim.position = stand_rest + Vector2(stand_r * 4.0, stand_r * 0.1)
	phone_stick.call("_gui_input", past_rim)
	var stays: bool = (phone_stick.get("base") as Vector2) == stand_rest \
		and (phone_stick.get("knob") as Vector2).length() <= stand_r + 0.01 \
		and phone_stick.get_global_rect() == stand_box and zone.encloses(stand_box)
	var full_walk: float = float(srun.call("_read_steer"))
	var gentle := InputEventScreenDrag.new()
	gentle.index = 0
	gentle.position = stand_rest + Vector2(stand_r * 0.5, 0.0)
	phone_stick.call("_gui_input", gentle)
	var slow_walk: float = float(srun.call("_read_steer"))
	check("  the Stand's stick is mounted (a thumb far past its rim moves only the knob) and read as it lies: full %.2f, a little push %.2f"
		% [full_walk, slow_walk], stays and full_walk > 0.99 and slow_walk > 0.05 and slow_walk < 0.6,
		[stand_rest, phone_stick.get("base"), phone_stick.get("knob"), stand_box, zone])
	phone_stick.call("let_go")
	var words_touch: String = str((screen.get("_how_to_lines")[0] as Label).text)
	var go_touch: String = str((screen.get("start_button") as Button).text)
	var hint_touch: String = str((screen.get("pick_hint") as Label).text)
	TouchControls.set_active(false)
	screen.call("_process", 0.0)
	check("  on a phone: a stick of its own left of the field walks her; a finger on the field aims and casts, a thumb on the stick does not",
		stick_up and aims_there and thumb_no_cast and walks and not phone_stick.visible and not Input.is_action_pressed("move_right"),
		[stick_up, aims_there, thumb_no_cast, walks, zone])
	check("  and the Stand's words are a phone's on one (\"%s\", \"%s\", \"%s\"), the keys' off it" % [words_touch, go_touch, hint_touch],
		words_touch == "Walk the wall with the stick." and go_touch == "Start" and hint_touch == "Tap one"
		and str((screen.get("_how_to_lines")[0] as Label).text) == ScreenScript.HOW_TO[0]
		and str((screen.get("start_button") as Button).text) == "Start  (Space)" and str((screen.get("pick_hint") as Label).text) == "Click one")
	# The pick on screen: the cards show what is offered; 2 takes the second.
	srun.set("offers", ["blast", "patch", "crit"])
	srun.set("door", float(srun.get("door_most")) * 0.5)
	srun.set("state", StandScript.State.PICK)
	screen.call("_process", 0.0)
	var pick_panel: Control = screen.get("pick_panel")
	var card_two: Button = (screen.get("cards") as Array)[1]
	var card_name: String = str((card_two.get_node("words/name") as Label).text)
	srun.set("levels", {"blast": 2})
	var card_one: Button = (screen.get("cards") as Array)[0]
	screen.get("pick_panel").visible = false
	screen.call("paint")
	var times: String = str((card_one.get_node("words/level") as Label).text)
	var no_cast: bool = not bool(srun.get("casting"))
	var cards_up: bool = pick_panel.visible
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.pressed = true
	screen.call("_input", key)
	var reroll_shown: String = str((screen.get("reroll_button") as Button).text)
	check("  a pick shows its cards (\"%s\", \"%s\") and \"%s\", no numbers on them, holds her meteors, and 2 takes the second"
		% [card_name, times, reroll_shown], cards_up and card_name == "Repair" and times == "Upgraded 2 of 5"
		and reroll_shown == "Reroll (1 left)"
		and card_one.get_node("words").get_node_or_null("key") == null and no_cast and srun.get("state") == StandScript.State.BETWEEN
		and float(srun.get("door")) > float(srun.get("door_most")) * 0.5 and not pick_panel.visible)
	screen.ask_to_leave()
	var asked_once: bool = is_instance_valid(screen) and str(screen.get("leave_button").text) == "Sure?"
	srun.set("portal", 0)
	srun.set("state", StandScript.State.LOST)
	screen.call("paint")
	var told: bool = screen.get("results").visible and str(screen.get("result_line").text).contains("portal fell")
	screen.again()
	var again_fresh: bool = screen.get("start_panel").visible and screen.get("run") != srun
	screen.ask_to_leave()
	await get_tree().process_frame
	check("  Leave asks twice while it is on, once before; the portal fallen says so, and Again starts afresh",
		asked_once and told and again_fresh and not is_instance_valid(screen))
	# THE CARD: the owner's alone while it is built.
	var card_hud := Control.new()
	add_child(card_hud)
	var card = (load("res://src/ui/minigames/minigamescard.gd") as GDScript).call("attach", card_hud)
	var opened: Array = []
	card.set("open_stand", func() -> void: opened.append(1))
	card.set("area_now", func() -> String: return "elusion")
	card.set("shows_mage_stand", func() -> bool: return false)
	card.call("paint")
	var hidden: bool = not card.stand_box.visible
	card.set("shows_mage_stand", func() -> bool: return true)
	card.call("open")
	card.call("paint")
	var shown: bool = card.stand_box.visible and not card.stand_go.disabled
	card.call("_on_stand_go")
	var went: bool = opened.size() == 1 and not card.visible
	card.set("area_now", func() -> String: return "field")
	card.call("paint")
	check("on the Minigames card for the owner alone; Go from town opens it, and asks the server nothing",
		hidden and shown and went and card.stand_go.disabled and str(card.stand_status.text) == "Play it from town.")
	card_hud.queue_free()
	await get_tree().process_frame
	# THE HEALER'S RUN ON A PHONE too (0.110.1): its stick, and the meteors tapped.
	var rock_art: Texture2D = load("res://art/maincharacter/meteor.png") as Texture2D
	var rock_was: Vector2i = rock_art.get_image().get_size() if rock_art != null else Vector2i.ZERO
	var hr_screen: CanvasLayer = (load("res://src/world/healerrun/healerrunscreen.gd") as GDScript).new()
	hr_screen.set("party_rooms", func() -> bool: return false)
	hr_screen.set("may_be_god", func() -> bool: return false)
	get_tree().root.add_child(hr_screen)
	await get_tree().process_frame
	TouchControls.set_active(true)
	hr_screen.call("_process", 0.0)
	var hr_stick: Control = hr_screen.get("stick")
	var hr_box: Control = hr_screen.get("meteor_box")
	var hr_key: Label = hr_box.get_node("meteorkey")
	var tapped_words: String = hr_key.text
	var hr_stick_up: bool = hr_stick != null and hr_stick.visible and hr_stick.get_global_rect().size.x > 0.0
	# 0.110.2, the owner: "having rough time moving left and right with healer
	# on mobil". The stick's edge pressed sprint, and here sprint is focus -
	# the harder the push, the slower she went. Mounted in the dark left of
	# the run now, off the field, and read as it lies.
	var hr_run: Node2D = hr_screen.get("run")
	var hr_zone: Rect2 = hr_screen.call("stick_zone")
	var hr_rest: Vector2 = hr_stick.get("rest")
	var hr_r: float = float(hr_stick.get("radius"))
	var hr_stick_box: Rect2 = hr_stick.get_global_rect()
	var drawn_at_rest: bool = (hr_stick.get("ring") as Control).visible and int(hr_stick.get("finger")) == -1
	var hr_down := InputEventScreenTouch.new()
	hr_down.index = 0
	hr_down.position = hr_rest
	hr_down.pressed = true
	hr_stick.call("_gui_input", hr_down)
	var hr_push := InputEventScreenDrag.new()
	hr_push.index = 0
	hr_push.position = hr_rest + Vector2(-hr_r * 3.0, 0.0)
	hr_stick.call("_gui_input", hr_push)
	TouchControls.call("_physics_process", 1.0 / 60.0)
	var edge_steer: Vector2 = hr_run.call("_read_steer")
	var edge_focus: bool = bool(hr_run.call("_read_focus"))
	var sprint_pressed: bool = Input.is_action_pressed("sprint")
	var hr_from: float = float((hr_run.get("healer") as Node2D).position.x)
	hr_run.set("frozen", 0.0)
	hr_run.set("gust", 0.0)
	hr_run.call("_move_healer", 0.1)
	var hr_went: float = hr_from - float((hr_run.get("healer") as Node2D).position.x)
	var hr_stays: bool = (hr_stick.get("base") as Vector2) == hr_rest and hr_stick.get_global_rect() == hr_stick_box
	hr_push.position = hr_rest + Vector2(-hr_r * 0.45, 0.0)
	hr_stick.call("_gui_input", hr_push)
	var gentle_steer: Vector2 = hr_run.call("_read_steer")
	hr_stick.call("let_go")
	TouchControls.call("_physics_process", 1.0 / 60.0)
	var path_wall: float = hr_zone.end.x
	check("  the Healer's Run's stick: drawn at rest, mounted left of the path (%s), never moved by a thumb past its rim, read as it lies (all the way %s, a little %s)"
		% [str(hr_stick_box), str(edge_steer), str(gentle_steer)],
		drawn_at_rest and hr_stays and hr_zone.encloses(hr_stick_box) and hr_stick_box.end.x <= path_wall + 0.01 and hr_zone.size.x > 0.0
		and edge_steer.distance_to(Vector2(-1.0, 0.0)) < 0.01 and gentle_steer.x < -0.05 and gentle_steer.x > -0.6,
		[hr_zone, hr_stick_box, hr_rest, hr_stick.get("base")])
	check("  and pushed all the way she goes her full speed: the stick's edge never focuses her (sprint %s, focus %s, %.1f px in 0.1 s)"
		% [str(sprint_pressed), str(edge_focus), hr_went],
		sprint_pressed and not edge_focus and absf(hr_went - RunScript.MOVE_SPEED * 0.1) < 0.5)
	var hr_words_touch: String = str((hr_screen.get("_tutorial_lines")[0] as Label).text)
	var hr_go_touch: String = str((hr_screen.get("start_button") as Button).text)
	TouchControls.set_active(false)
	hr_screen.call("_process", 0.0)
	check("  and its tutorial is a phone's on one (\"%s\", \"%s\"), the keys' off it" % [hr_words_touch, hr_go_touch],
		hr_words_touch == "Move with the stick - she shoots by herself." and hr_go_touch == "Start"
		and str((hr_screen.get("_tutorial_lines")[0] as Label).text) == "Move with your move keys - she shoots by herself."
		and str((hr_screen.get("start_button") as Button).text) == "Start  (Space)")
	check("  and the Healer's Run: a stick of its own on a phone, and its meteors tapped (\"%s\")" % tapped_words,
		hr_stick_up and not hr_stick.visible and tapped_words == "Meteors - tap" and hr_key.text == "Meteors - Space"
		and hr_box.mouse_filter == Control.MOUSE_FILTER_STOP and hr_box.gui_input.is_connected(Callable(hr_screen, "_on_meteors_touched")))
	# TAP THE SCREEN TO DROP A METEOR (0.110.3, "tap the screen to drop
	# meteor"): a finger on the field calls one down; one in the stick's dark
	# left does not; and a tap on the meteors is one meteor, not two (Godot
	# makes a first finger's tap a click as well).
	const HRScreen := preload("res://src/world/healerrun/healerrunscreen.gd")
	var seen_was: bool = HRScreen._tutorial_seen
	TouchControls.set_active(true)
	hr_screen.call("_process", 0.0)
	hr_run.set("lives", 99)
	hr_screen.call("begin")
	for i in 600:
		if hr_run.call("meteor_target") != null:
			break
		hr_run.call("step", 1.0 / 60.0)
	var rocks_at_start: int = int(hr_run.get("meteors"))
	var field_tap := InputEventScreenTouch.new()
	field_tap.index = 1
	field_tap.pressed = true
	field_tap.position = (hr_screen.get("picture") as Control).get_global_rect().get_center()
	hr_screen.call("_on_field_touched", field_tap)
	var rocks_after_tap: int = int(hr_run.get("meteors"))
	field_tap.position = (hr_screen.call("stick_zone") as Rect2).get_center()
	hr_screen.call("_on_field_touched", field_tap)
	field_tap.position = (hr_screen.get("picture") as Control).get_global_rect().get_center()
	field_tap.pressed = false
	hr_screen.call("_on_field_touched", field_tap)
	var rocks_after_misses: int = int(hr_run.get("meteors"))
	var box_tap := InputEventScreenTouch.new()
	box_tap.index = 0
	box_tap.pressed = true
	hr_screen.call("_on_meteors_touched", box_tap)
	var echo := InputEventMouseButton.new()
	echo.button_index = MOUSE_BUTTON_LEFT
	echo.pressed = true
	echo.device = InputEvent.DEVICE_ID_EMULATION
	hr_screen.call("_on_meteors_touched", echo)
	var rocks_after_box: int = int(hr_run.get("meteors"))
	var back_hears: bool = (hr_screen.get_node("back") as Control).gui_input.is_connected(Callable(hr_screen, "_on_field_touched"))
	TouchControls.set_active(false)
	HRScreen._tutorial_seen = seen_was
	check("  a tap on the field drops a meteor (%d -> %d); none in the stick's dark left or on a lift (%d); a tap on the meteors is one (%d)"
		% [rocks_at_start, rocks_after_tap, rocks_after_misses, rocks_after_box],
		back_hears and rocks_at_start >= 2 and rocks_after_tap == rocks_at_start - 1
		and rocks_after_misses == rocks_after_tap and rocks_after_box == rocks_after_tap - 1)
	hr_screen.call("close")
	await get_tree().process_frame
	# 2 Nov, on the owner's PC: "Too many pixels for image" building the
	# meteors - each screen made doubled the meteor art's own image, and in a
	# headless run that image is the texture's, so it grew every time.
	var again: CanvasLayer = (load("res://src/world/healerrun/healerrunscreen.gd") as GDScript).new()
	again.set("party_rooms", func() -> bool: return false)
	again.set("may_be_god", func() -> bool: return false)
	get_tree().root.add_child(again)
	await get_tree().process_frame
	again.call("close")
	await get_tree().process_frame
	var rock_now: Vector2i = rock_art.get_image().get_size() if rock_art != null else Vector2i.ZERO
	check("  and making its screen twice leaves the meteor's own picture as it was (%s)" % str(rock_now),
		rock_now == rock_was, [rock_was, rock_now])
	print("  (the mage's stand: done)")


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


func _test_the_giant_meteor() -> void:
	section("THE GIANT METEOR (0.111.0): a star a wave drops, claimed by meteors, called down on the field")
	# The owner: "we need 1 giant meteor to wipe the whole field but i need
	# to think carefully about how it can be used because with 4 people
	# might be too op", "i did not see giant meteor pop up", "lets build it".
	# The plan's section 13.
	const StandScript := preload("res://src/world/magestand/magestand.gd")
	const ScreenScript := preload("res://src/world/magestand/magestandscreen.gd")
	# THE ODDS: none before wave 4; one in four; sure after three without.
	var odds_hold: bool = not StandScript.star_comes(3, 9, 0.0) and StandScript.star_comes(4, 0, 0.2) \
		and not StandScript.star_comes(4, 0, 0.3) and StandScript.star_comes(9, 3, 0.99) \
		and not StandScript.star_comes(9, 2, 0.99)
	var stand = StandScript.new()
	stand.set("seed_value", 4)
	stand.set("steer", func() -> float: return 0.0)
	add_child(stand)
	stand.set_process(false)
	var dropped: int = 0
	var longest: int = 0
	var run_without: int = 0
	for k in 400:
		stand.wave = StandScript.STAR_FROM + k
		stand.call("_roll_star")
		if float(stand.get("star_drop_in")) >= 0.0:
			dropped += 1
			run_without = 0
			stand.set("star_drop_in", -1.0)
		else:
			run_without += 1
			longest = maxi(longest, run_without)
	var share: float = float(dropped) / 400.0
	stand.wave = 2
	stand.call("_roll_star")
	var none_early: bool = float(stand.get("star_drop_in")) < 0.0
	stand.wave = 20
	stand.set("star_state", "held")
	var without_before: int = int(stand.get("star_waves_without"))
	stand.set("star_waves_without", 3)
	stand.call("_roll_star")
	var one_at_a_time: bool = float(stand.get("star_drop_in")) < 0.0 and int(stand.get("star_waves_without")) == 3
	stand.set("star_state", "")
	stand.set("star_waves_without", without_before)
	check("from wave 4 a wave may drop a star (one in four), surely after three without (%d of 400 waves, at most %d in a row without); never one while one is about"
		% [dropped, longest], odds_hold and longest <= StandScript.STAR_SURE - 1 and share > 0.28 and share < 0.46
		and none_early and one_at_a_time)
	# CLAIMED BY METEORS: 3 alone, 8 for four - landed on it, not beside it.
	var needs: Array = []
	for n in [1, 2, 3, 4]:
		needs.append(StandScript.claim_hits(n))
	stand.state = StandScript.State.WAVE
	stand.wave = 5
	stand.set("_to_spawn", 0)
	# One far off keeps the wave on (an empty field ends it, and its pick holds all).
	stand.spawn("slime", Vector2(StandScript.PATH_HALF - 20.0, -StandScript.HALF.y + 10.0))
	stand.call("_drop_star")
	for i in 60:
		stand.step(1.0 / 60.0)
	var lying: bool = str(stand.get("star_state")) == "lying"
	var star_at: Vector2 = stand.get("star_at")
	var rock_shown: bool = stand.get_node_or_null("star") != null
	stand.call("_land", {"at": star_at + Vector2(120.0, 0.0), "rock": null, "crit": false})
	var beside_counts: int = int(stand.get("star_hits"))
	stand.call("_land", {"at": star_at, "rock": null, "crit": false})
	stand.call("_land", {"at": star_at + Vector2(10.0, 5.0), "rock": null, "crit": false})
	var after_two: String = str(stand.get("star_state"))
	stand.call("_land", {"at": star_at, "rock": null, "crit": false})
	await get_tree().process_frame
	check("  claimed by meteors landed on it (%s for 1 to 4 players): one beside it is no hit, two leave it lying, the third makes it held"
		% str(needs), needs == [3, 5, 6, 8] and lying and rock_shown and beside_counts == 0 and after_two == "lying"
		and str(stand.get("star_state")) == "held" and stand.get_node_or_null("star") == null)
	# CALLED: refused between waves; in a wave, its shadow STAR_FALL, then
	# everything on the field at the call is hit - what walked in after lives.
	stand.state = StandScript.State.BETWEEN
	var refused_between: bool = not bool(stand.call("call_star"))
	stand.state = StandScript.State.WAVE
	for node in stand.monsters.get_children():
		node.free()
	var marked: Array = []
	for i in 5:
		marked.append(stand.spawn("sprite", Vector2(-200.0 + i * 90.0, -150.0)))
	(marked[4] as Node2D).position = Vector2(-StandScript.PATH_HALF + 30.0, StandScript.FOOT + 12.0)
	marked[4].set("through", true)
	var elite = stand.spawn("slime", Vector2(100.0, -60.0))
	elite.set("rank", "elite")
	elite.set("most", 100.0)
	elite.set("health", 100.0)
	var keeper = stand.spawn("slime", Vector2(-100.0, -60.0))
	keeper.set("rank", "keeper")
	keeper.set("most", 500.0)
	keeper.set("health", 500.0)
	var slain_before: int = stand.slain
	var called: bool = bool(stand.call("call_star"))
	var falling: bool = str(stand.get("star_state")) == "falling"
	var late = stand.spawn("sprite", Vector2(0.0, -StandScript.HALF.y - 10.0))
	for i in int(StandScript.STAR_FALL * 60.0) - 6:
		stand.step(1.0 / 60.0)
	var still_falling: bool = str(stand.get("star_state")) == "falling" and float(marked[0].get("dying")) < 0.0
	for i in 12:
		stand.step(1.0 / 60.0)
	var all_hit: bool = true
	for m in marked:
		all_hit = all_hit and (not is_instance_valid(m) or float(m.get("dying")) >= 0.0)
	var late_lives: bool = is_instance_valid(late) and float(late.get("dying")) < 0.0
	check("  called down in a wave (refused between them): its shadow %.0f s, then the field at the call is slain, the one inside the gate too (%d) - and one that came after lives"
		% [StandScript.STAR_FALL, stand.slain - slain_before], refused_between and called and falling and still_falling
		and all_hit and late_lives and stand.slain - slain_before == 5 and str(stand.get("star_state")) == ""
		and int(stand.get("stars_called")) == 1 and str(stand.get("banner")) == "The field is wiped!")
	check("  elites lose half their health to it (%.0f of 100), keepers a fifth (%.0f of 500)"
		% [float(elite.get("health")), float(keeper.get("health"))],
		is_equal_approx(float(elite.get("health")), 50.0) and is_equal_approx(float(keeper.get("health")), 400.0)
		and not bool(stand.call("call_star")))
	# NOT CLAIMED IN TIME: it fades, its hits gone.
	stand.call("_drop_star")
	for i in 60:
		stand.step(1.0 / 60.0)
	stand.call("_land", {"at": stand.get("star_at"), "rock": null, "crit": false})
	var one_hit: int = int(stand.get("star_hits"))
	for i in int(StandScript.STAR_LIFE * 60.0) + 6:
		stand.step(1.0 / 60.0)
	await get_tree().process_frame
	check("  left lying %.0f s unclaimed it fades (one hit on it, then none)" % StandScript.STAR_LIFE,
		one_hit == 1 and str(stand.get("star_state")) == "" and int(stand.get("star_hits")) == 0
		and stand.get_node_or_null("star") == null)
	stand.queue_free()
	# THE SCREEN: a Giant meteor button while one is held, Q or a press calls
	# it; on a phone it is tapped.
	var screen: CanvasLayer = ScreenScript.new()
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	screen.set("mouse_held", func() -> bool: return false)
	screen.begin()
	screen.call("_process", 0.0)
	var srun: Node = screen.get("run")
	srun.set_process(false)
	var button: Button = screen.get("star_button")
	var hidden_without: bool = not button.visible
	srun.set("state", StandScript.State.WAVE)
	srun.call("spawn", "sprite", Vector2(0.0, -100.0))
	srun.set("star_state", "held")
	screen.call("_process", 0.0)
	var shown: bool = button.visible and not button.disabled and button.text == "Giant meteor\n(Q)"
	var q := InputEventKey.new()
	q.keycode = KEY_Q
	q.pressed = true
	screen.call("_input", q)
	var q_called: bool = str(srun.get("star_state")) == "falling"
	srun.set("star_state", "held")
	TouchControls.set_active(true)
	screen.call("_process", 0.0)
	var phone_words: String = button.text
	var on_controls: bool = bool(screen.call("_on_controls", button.get_global_rect().get_center()))
	var over_field: bool = (screen.call("drawn_rect") as Rect2).encloses(button.get_global_rect())
	button.pressed.emit()
	var pressed_called: bool = str(srun.get("star_state")) == "falling"
	TouchControls.set_active(false)
	screen.call("_word_for_touch")
	var how_to: Array = screen.get("_how_to_lines")
	var told: String = str((how_to[how_to.size() - 1] as Label).text)
	check("  the screen: a Giant meteor button while one is held (\"%s\" on a phone), on the picture, not an aim; Q or a press calls it; the start panel tells of it"
		% phone_words, hidden_without and shown and q_called and phone_words == "Giant meteor" and pressed_called
		and on_controls and over_field and told.contains("star"))
	screen.queue_free()
	await get_tree().process_frame
	print("  (the giant meteor: done)")


func _test_the_descent() -> void:
	section("THE DESCENT (0.112.0): a roguelike run down a crypt, room by room, as your own character")
	# The owner, of roguelike_mockup.png: "that looks so cool incredible
	# simply the best lets try it out". Step 1, his alone.
	const Boons := preload("res://src/world/descent/descentboons.gd")
	const RunScript := preload("res://src/world/descent/descentrun.gd")
	const DoorScript := preload("res://src/world/descent/descentdoor.gd")
	const Build := preload("res://src/tools/builddescent.gd")
	# THE AREA.
	var packed: PackedScene = load(str(AreaRegistry.AREAS.get("descent", ""))) as PackedScene
	var area: Node = packed.instantiate() if packed != null else null
	check("the Descent is an area, named for players, with a map in gamedata.json, and its room loads",
		AreaRegistry.has_area("descent") and AreaRegistry.display_name("descent") == "The Descent"
		and (_load_gamedata().get("areas", {}) as Dictionary).has("descent") and area != null)
	if area == null:
		return
	var run_node: Node = area.get_node_or_null("descentrun")
	var left: Node = area.get_node_or_null("ysortworld/props/doorleft")
	var right: Node = area.get_node_or_null("ysortworld/props/doorright")
	var front: Node = area.get_node_or_null("ysortworld/props/doorfront")
	var arrivals: Array = []
	_collect_by_script(area, "res://src/world/fieldportal.gd", arrivals)
	var arrives: bool = arrivals.any(func(a: Node) -> bool: return str(a.get("portal_id")) == "descent_entrance")
	var inside: Rect2 = Rect2(Build.SIDE_LEFT, Build.WALL_BACK, Build.SIDE_RIGHT - Build.SIDE_LEFT, Build.WALL_FRONT - Build.WALL_BACK)
	check("  its run, two doors on in the back wall where its gaps are, the shut one you come in by, and the arrival from the card",
		run_node != null and run_node.get_script() == RunScript and left != null and left.get_script() == DoorScript
		and right != null and right.get_script() == DoorScript and front != null and bool(front.get("entrance"))
		and not bool(left.get("entrance")) and is_equal_approx((left as Node2D).position.x, 217.0)
		and is_equal_approx((right as Node2D).position.x, 424.0) and is_equal_approx((front as Node2D).position.x, 320.0)
		and arrives and inside.encloses(run_node.get("room_rect")) and inside.has_point(run_node.get("entry_spot")))
	check("  it tells no opening story and fights in the bullet zone", area.get("tells_story") == false
		and area.get("bullet_zone") == true)
	area.free()
	# THE UPGRADES: nothing off a run; each its own share on one.
	Boons.clear()
	Boons.levels = {"might": 3, "iron": 2, "swift": 1, "fortune": 2}
	var off_run: bool = Boons.damage_factor() == 1.0 and Boons.taken_factor() == 1.0 and Boons.speed_factor() == 1.0 \
		and Boons.gold_factor() == 1.0
	Boons.active = true
	var on_run: bool = is_equal_approx(Boons.damage_factor(), 1.45) and is_equal_approx(Boons.taken_factor(), 0.84) \
		and is_equal_approx(Boons.speed_factor(), 1.08) and is_equal_approx(Boons.gold_factor(), 1.5)
	Boons.take("berserk")
	var berserk_once: bool = not Boons.take("berserk") and is_equal_approx(Boons.damage_factor(), 1.45 * 1.4) \
		and is_equal_approx(Boons.taken_factor(), 0.84 * 1.2)
	Boons.levels["might"] = Boons.MOST
	var stops: bool = not Boons.take("might") and Boons.level("might") == Boons.MOST
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var drawn: Array = Boons.offers(rng)
	var fair: bool = drawn.size() == 3 and not drawn.has("might") and not drawn.has("berserk") \
		and drawn[0] != drawn[1] and drawn[1] != drawn[2] and drawn[0] != drawn[2]
	Boons.clear()
	check("an upgrade does nothing off a run; on one Might, Iron Skin, Swift and Fortune each take their share; Berserk once; none past its most, none offered twice",
		off_run and on_run and berserk_once and stops and fair and not Boons.active and Boons.levels.is_empty(), drawn)
	# THE WARRIOR'S OWN ("this will be the warriors decent"): Whirlwind,
	# Bloodletter, Quick Finisher, Long Wave - nothing off a run.
	const WarriorScript := preload("res://src/characters/warrior.gd")
	Boons.levels = {"whirlwind": 1, "bloodletter": 2, "quickfinish": 1, "longwave": 2}
	var warrior_off: bool = not Boons.whirlwind() and Boons.bleed_swings() == 0.0 \
		and Boons.wave_scale() == 1.0 and not WarriorScript.finisher_on(2) and WarriorScript.finisher_on(3)
	Boons.active = true
	var warrior_on: bool = Boons.whirlwind() and is_equal_approx(Boons.bleed_swings(), 1.0) \
		and is_equal_approx(Boons.wave_scale(), 1.5) and WarriorScript.finisher_on(2) and WarriorScript.finisher_on(4) \
		and not WarriorScript.finisher_on(3)
	Boons.clear()
	var warrior_code: String = _code_src("res://src/characters/warrior.gd")
	var wave_code: String = _code_src("res://src/projectiles/slashwave.gd")
	var wired: bool = _func_body(warrior_code, "func _deal_melee_damage(").contains("DescentBoons.whirlwind()") \
		and _func_body(warrior_code, "func _deal_melee_damage(").contains("CARDINAL_DIRECTIONS") \
		and _func_body(warrior_code, "func _try_damage(").contains("Bleed.open(target") \
		and _func_body(warrior_code, "func _spawn_slashwave(").contains("wave.size_scale = grown") \
		and _func_body(wave_code, "func _dress(").contains("_base_scale * size_scale")
	check("the warrior's own: Whirlwind cuts every way, Bloodletter bleeds, Quick Finisher every 2nd swing, Long Wave a quarter bigger a level - none of it off a run",
		warrior_off and warrior_on and wired and Boons.BOONS.size() == Boons.ORDER.size())
	# ON YOUR OWN CHARACTER: the three numbers every class asks.
	var warrior: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	var dealt: float = float(warrior.call("get_damage_multiplier"))
	var walks: float = float(warrior.call("effects_speed_scale"))
	var takes: float = float(warrior.call("effects_damage_scale"))
	Boons.active = true
	Boons.levels = {"might": 2, "swift": 1, "iron": 1}
	var dealt_on: float = float(warrior.call("get_damage_multiplier"))
	var walks_on: float = float(warrior.call("effects_speed_scale"))
	var takes_on: float = float(warrior.call("effects_damage_scale"))
	Boons.clear()
	var back: bool = is_equal_approx(float(warrior.call("get_damage_multiplier")), dealt)
	warrior.free()
	var fall_code: String = _code_src("res://src/characters/player.gd")
	var catch_at: int = fall_code.find("func _endless_catches_fall(")
	var catch_body: String = fall_code.substr(catch_at, fall_code.find("\nfunc ", catch_at + 1) - catch_at)
	check("  on your character: its hits, its walk and the hits it takes carry them (%.2f -> %.2f), and a fall in the Descent is caught as the Endless's is"
		% [dealt, dealt_on], is_equal_approx(dealt_on, dealt * 1.3) and is_equal_approx(walks_on, walks * 1.08)
		and is_equal_approx(takes_on, takes * 0.92) and back and catch_body.contains("&\"descent_run\""))
	# THE RUN, in a room of stand-ins.
	var room := Node2D.new()
	add_child(room)
	var world := Node2D.new()
	world.name = "ysortworld"
	room.add_child(world)
	var props := Node2D.new()
	props.name = "props"
	world.add_child(props)
	var enemies := Node2D.new()
	enemies.name = "enemies"
	world.add_child(enemies)
	for one in [["doorleft", 217.0], ["doorright", 424.0]]:
		var door := Node2D.new()
		door.set_script(DoorScript)
		door.name = str(one[0])
		door.position = Vector2(float(one[1]), Build.WALL_BACK)
		props.add_child(door)
	var body := Node2D.new()
	body.set_script(_endless_body_script())
	room.add_child(body)
	body.global_position = Vector2(320, 200)
	body.set("hp", 100)
	var run: Node = RunScript.new()
	run.name = "descentrun"
	run.set("player_override", body)
	room.add_child(run)
	await get_tree().process_frame
	var doors: Array = run.get("doors")
	var waiting: bool = int(run.get("state")) == RunScript.State.WAITING and doors.size() == 2 \
		and bool(doors[0].get("open")) and str(doors[0].get("reward")) == "begin" and str(doors[1].get("reward")) == "begin"
	(doors[0] as Node).emit_signal("walked_in", doors[0])
	var travelling: bool = int(run.get("state")) == RunScript.State.TRAVEL and Boons.active and not bool(doors[0].get("open"))
	for i in 3:
		run.call("_process", RunScript.FADE_SECONDS)
	var arrived: bool = int(run.get("state")) == RunScript.State.FIGHT and int(run.get("room")) == 1 \
		and body.global_position == run.get("entry_spot")
	body.global_position = Vector2(320, 200)
	run.call("_process", RunScript.FIGHT_DELAY + 0.1)
	# Marked on the floor first, then out (0.115.0).
	run.call("_process", RunScript.MARK_SECONDS + 0.05)
	var pack: Array = run.get("monsters")
	var marked: bool = not pack.is_empty()
	for m in pack:
		marked = marked and (m as Node).has_meta(&"stress_copy") and (m as Node).get_parent() == enemies \
			and (m as Node2D).global_position.distance_to(body.global_position) >= RunScript.SPAWN_CLEAR - 0.01
	var first_elites: int = pack.filter(func(m: Node) -> bool: return m.has_meta(&"descent_elite")).size()
	check("a run: through a door the screen fades, you come in at the room's front, the doors shut, and a pack of %d comes, an elite among them - marked as the owner's copies (no kill reported, never shared)"
		% pack.size(), waiting and travelling and arrived and pack.size() == int(run.call("pack_size")) + int(run.call("elites_for", "upgrade"))
		and pack.size() == 6 and first_elites == 1 and marked, [pack.size(), first_elites])
	for m in pack:
		(m as Node).call("take_damage", 999999)
	run.call("_process", 0.016)
	var offered: Array = (run.get("offers") as Array).duplicate()
	var picking: bool = int(run.get("state")) == RunScript.State.PICK and offered.size() == 3 \
		and bool((run.get("hud").get("pick_panel") as Control).visible) and not bool(doors[0].get("open"))
	# CONFIRMED (0.112.1): a click on a card chooses it; Take it takes it.
	var pick_hud: Node = run.get("hud")
	var pick_cards: Array = pick_hud.get("cards")
	var take: Button = pick_hud.get("take_button")
	var dimmed: bool = take != null and take.disabled
	(pick_cards[1] as Button).pressed.emit()
	var chose_one: bool = int(pick_hud.get("chosen")) == 1 and int(run.get("state")) == RunScript.State.PICK \
		and Boons.level(str(offered[1])) == 0 and not take.disabled \
		and take.text == "Take %s" % str(Boons.BOONS[str(offered[1])]["name"])
	(pick_cards[0] as Button).pressed.emit()
	var chose_other: bool = int(pick_hud.get("chosen")) == 0 and Boons.level(str(offered[0])) == 0
	check("  a card clicked is only chosen - Take it (dimmed until then) takes it - so a stray swing's click takes nothing (0.112.1)",
		dimmed and chose_one and chose_other, [dimmed, chose_one, chose_other])
	take.pressed.emit()
	var took: bool = int(run.get("state")) != RunScript.State.PICK and Boons.level(str(offered[0])) == 1 \
		and Boons.level(str(offered[1])) == 0 and int(pick_hud.get("chosen")) == -1
	var promise_a: String = str(doors[0].get("reward"))
	var promise_b: String = str(doors[1].get("reward"))
	check("  the last one down and the room is clear: three upgrades offered (%s), one taken, then the doors open, each promising a room (%s, %s)"
		% [", ".join(offered), promise_a, promise_b], picking and took and bool(doors[0].get("open"))
		and RunScript.KINDS.has(promise_a) and RunScript.KINDS.has(promise_b) and promise_a != promise_b
		and int(run.get("state")) == RunScript.State.CLEAR)
	# Through the door that does not promise an upgrade (they differ, so one
	# does not): an upgrade room is what a run would give anyway.
	var taken: Node = doors[0] if promise_a != "upgrade" else doors[1]
	# A Rest has no fight (0.115.0): this walks into one that has.
	if str(taken.get("reward")) == "rest":
		taken.call("set_reward", "gold")
	var promised: String = str(taken.get("reward"))
	taken.emit_signal("walked_in", taken)
	for i in 3:
		run.call("_process", RunScript.FADE_SECONDS)
	var kept: bool = int(run.get("room")) == 2 and str(run.get("room_kind")) == promised and promised != "upgrade"
	run.set("room_kind", "elite")
	run.call("_process", RunScript.FIGHT_DELAY + 0.1)
	run.call("_process", RunScript.MARK_SECONDS + 0.05)
	var elites: Array = (run.get("monsters") as Array).filter(func(m: Node) -> bool: return m.has_meta(&"descent_elite"))
	var queued: int = 0
	var queued_elites: int = 0
	for wave in (run.get("_waves") as Array):
		for entry in (wave as Array):
			queued += 1
			queued_elites += 1 if bool(entry[2]) else 0
	check("  the door you take is the room you get (%s); an elite room brings three elites, bigger and tougher (0.123.0: every fight one, an elite room two more)"
		% promised, kept and elites.size() >= 1 and elites.size() + queued_elites == 3
		and (run.get("monsters") as Array).size() + queued == int(run.call("pack_size")) + 3
		and is_equal_approx((elites[0] as Node2D).scale.x, RunScript.ELITE_SIZE), [elites.size(), queued_elites, queued])
	Boons.levels["fortune"] = 2
	var gold_before: int = int(run.get("gold"))
	run.call("_pay", 100)
	check("  gold for the run, Fortune's share on it (100 -> %d)" % (int(run.get("gold")) - gold_before),
		int(run.get("gold")) - gold_before == 150)
	# THE KEEPER, then down.
	run.call("_clear_monsters")
	run.set("room", RunScript.ROOMS)
	run.call("_go", "keeper")
	for i in 3:
		run.call("_process", RunScript.FADE_SECONDS)
	run.call("_process", RunScript.FIGHT_DELAY + 0.1)
	var keepers: Array = run.get("monsters")
	var the_keeper: bool = str(run.get("room_kind")) == "keeper" and keepers.size() == 1 \
		and str((keepers[0] as Node).scene_file_path).ends_with("fireboss.tscn")
	(keepers[0] as Node).call("take_damage", 99999999)
	run.call("_process", 0.016)
	run.call("pick", 0)
	var down: bool = str(doors[0].get("reward")) == "down" and str(doors[1].get("reward")) == "down"
	(doors[0] as Node).emit_signal("walked_in", doors[0])
	for i in 3:
		run.call("_process", RunScript.FADE_SECONDS)
	check("  after the last room (%d) both doors lead to the keeper; the Fire Keeper beaten, a pick, then both doors go down to floor 2, room 1" % RunScript.ROOMS,
		the_keeper and down and int(run.get("floor_index")) == 1 and int(run.get("room")) == 1)
	# NO BOTTOM (0.124.0): the seventh keeper beaten, the run goes on into the
	# Deep; a run ends only in a fall, and the deepest is the best.
	run.call("_clear_monsters")
	run.set("floor_index", RunScript.FLOORS.size() - 1)
	run.set("room_kind", "keeper")
	run.call("_room_cleared")
	var picking_on: bool = int(run.get("state")) == RunScript.State.PICK and Boons.active
	run.call("pick", 0)
	var down_deep: bool = str(doors[0].get("reward")) == "down"
	(doors[0] as Node).emit_signal("walked_in", doors[0])
	for i in 3:
		run.call("_process", RunScript.FADE_SECONDS)
	check("  the seventh keeper beaten is not the bottom: a pick, then down into the Deep - %s" % str(run.call("floor_info")["name"]),
		picking_on and down_deep and int(run.get("floor_index")) == RunScript.FLOORS.size() and int(run.call("deep_round")) == 1
		and str(run.call("floor_info")["name"]) == "the Deep 1: the Crypt" and str(run.call("floor_info")["keeper"]) == "fireboss")
	# A FALL.
	(doors[0] as Node).emit_signal("walked_in", doors[0])
	for i in 3:
		run.call("_process", RunScript.FADE_SECONDS)
	body.global_position = Vector2(5000, 5000)
	var elsewhere: bool = not bool(run.call("knock_out", body))
	body.global_position = Vector2(300, 200)
	var caught: bool = bool(run.call("knock_out", body))
	check("  a fall off the Descent is an ordinary death; in it, you wake at the front on 1 health and the run is over",
		elsewhere and caught and int(body.get("hp")) == 1 and body.global_position == run.get("entry_spot")
		and int(run.get("state")) == RunScript.State.WAITING and str(run.get("last_result")).begins_with("You fell")
		and (run.get("monsters") as Array).is_empty() and not Boons.active)
	room.queue_free()
	await get_tree().process_frame
	# THE CARD: the owner's alone; Go travels there; inside, Leave.
	var card_hud := Control.new()
	add_child(card_hud)
	var card = (load("res://src/ui/minigames/minigamescard.gd") as GDScript).call("attach", card_hud)
	var went: Array = []
	card.set("travel", func(area_id: String, spawn_id: String) -> void: went.append([area_id, spawn_id]))
	card.set("area_now", func() -> String: return "elusion")
	card.set("shows_descent", func() -> bool: return false)
	card.call("paint")
	var hidden: bool = not card.descent_box.visible
	card.set("shows_descent", func() -> bool: return true)
	# EVERY CLASS (0.124.0; it was "the warriors decent"): a mage goes too.
	card.set("class_now", func() -> String: return "mage")
	card.call("open")
	card.call("paint")
	var mage_held: bool = not card.descent_go.disabled
	card.call("_on_descent_go")
	mage_held = mage_held and went.size() == 1 and went[0] == ["descent", "descent_entrance"]
	went.clear()
	card.call("open")
	card.set("class_now", func() -> String: return "warrior")
	card.call("paint")
	var shown: bool = card.descent_box.visible and card.descent_go.text == "Go" and not card.descent_go.disabled
	card.call("_on_descent_go")
	card.set("area_now", func() -> String: return "descent")
	card.call("paint")
	var leave_text: String = card.descent_go.text
	card.call("_on_descent_go")
	check("on the Minigames card for the owner alone, any class (0.124.0): a mage's Go goes down, a warrior's too (%s), and inside it is Leave, to town" % str(went),
		hidden and mage_held and shown and leave_text == "Leave" and went.size() == 2 and went[0] == ["descent", "descent_entrance"]
		and went[1] == ["elusion", ""])
	card_hud.queue_free()
	await get_tree().process_frame
	print("  (the descent: done)")


# =============================================================================
# AFTER THE FIRST DESCENT (0.112.1)
# =============================================================================
# The owner, playing 0.112.0: "having directional errors in the minigame",
# "map is lagging when walking and open", "the arrow pointing to the first
# enemy jitters", "we need a confirm button for upgrades" (held in
# _test_the_descent()), and "when a player goes into a house i can see them
# still they are standing on the house on my screen".
func _test_after_the_first_descent() -> void:
	section("AFTER THE FIRST DESCENT - the aim in a room smaller than the view, a steady arrow, a map that walks, players in houses (0.112.1)")
	const PlayerCode := preload("res://src/characters/player.gd")
	# THE AIM. A camera held to a room no wider than the view is put in the
	# middle of it, as Godot puts it; a wider room still holds it at the edge.
	var held := Camera2D.new()
	held.zoom = Vector2(2, 2)
	held.limit_left = 0
	held.limit_top = 0
	held.limit_right = 640
	held.limit_bottom = 408
	var mid: Vector2 = PlayerCode.camera_centre(held, Vector2(60, 120), Vector2(1280, 720))
	held.zoom = Vector2(3, 3)
	var edge: Vector2 = PlayerCode.camera_centre(held, Vector2(60, 120), Vector2(1280, 720))
	held.free()
	check("a room no wider than the view is centred, as Godot centres it; a wider one holds the camera at its edge",
		mid.is_equal_approx(Vector2(320, 180)) and edge.is_equal_approx(Vector2(213.33333, 120)), [mid, edge])
	var o := Vector2(-64000, -64000)
	var room := Node2D.new()
	add_child(room)
	var warrior: Node2D = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate() as Node2D
	room.add_child(warrior)
	var cam: Camera2D = warrior.get_node("camera2d") as Camera2D
	cam.make_current()
	cam.limit_left = int(o.x)
	cam.limit_top = int(o.y)
	cam.limit_right = int(o.x) + 640
	cam.limit_bottom = int(o.y) + 408
	var worst := 0.0
	for zoom in [3.0, 2.0, 1.0]:
		cam.zoom = Vector2(zoom, zoom)
		for spot in [Vector2(60, 120), Vector2(590, 300)]:
			warrior.global_position = o + spot
			warrior.reset_physics_interpolation()
			for i in 3:
				await get_tree().physics_frame
			await get_tree().process_frame
			var screen := Vector2(900, 200)
			var truth: Vector2 = warrior.get_canvas_transform().affine_inverse() * screen
			worst = maxf(worst, ((warrior.call("world_point_at", screen) as Vector2) - truth).length())
			worst = maxf(worst, ((warrior.call("screen_point_of", truth) as Vector2) - screen).length())
	check("  in the Descent's room at 3x, 2x and 1x the cursor's world point is where the cursor is (it was up to 287 px off zoomed out), and back again",
		worst < 0.5, worst)
	room.queue_free()
	await get_tree().process_frame

	# THE ARROW: placed from where things are drawn, and holding on.
	var GuideCode := preload("res://src/ui/guide.gd")
	var guide_code: String = _code_src("res://src/ui/guide.gd")
	check("the » is placed from where the character and the target are drawn - their last two ticks blended - not the drawn camera times the tick",
		_func_body(guide_code, "func _process(").contains("_on_screen(")
		and not _func_body(guide_code, "func _process(").contains("get_global_transform_with_canvas")
		and _func_body(guide_code, "func _drawn(").contains("get_physics_interpolation_fraction()"))
	var near_edge: Vector2 = Vector2(100, 100) + Vector2(GuideCode.NEAR * 1.1, 0)
	check("  over a near target it stays over it a little further out, so it does not flick at the edge",
		not bool(GuideCode.place(Vector2(100, 100), near_edge)["over"])
		and bool(GuideCode.place(Vector2(100, 100), near_edge, 1.0, true)["over"]))
	check("  and it keeps pointing at its monster unless another is a good deal nearer",
		_func_body(guide_code, "func _find_target(").contains("STICKY") and GuideCode.STICKY > 1.0)

	# THE MAP: the fog over the terrain is the old picture, and a step
	# repaints the fog where it uncovered, never the picture.
	var area_id := "zz_suite_fog"
	var ground := Color(0.33, 0.45, 0.26)
	var terrain := Image.create_empty(4, 2, false, Image.FORMAT_RGBA8)
	terrain.fill(Color(0, 0, 0, 0))
	for x in 4:
		terrain.set_pixel(x, 0, ground)
	for x in 3:
		terrain.set_pixel(x, 1, ground)
	WorldMap._terrain[area_id] = {"image": terrain, "origin": Vector2i.ZERO, "size": Vector2i(4, 2), "tile": Vector2i(16, 16)}
	WorldMap._seen[area_id] = PackedByteArray([0b11])
	var same := true
	for whole in [true, false]:
		var baked: Image = WorldMap.display_image(area_id, whole)
		var fog: Image = WorldMap.fog_image(area_id, whole)
		for y in 2:
			for x in 4:
				var under: Color = terrain.get_pixel(x, y)
				var over: Color = fog.get_pixel(x, y)
				var laid: Color = under.blend(over) if under.a > 0.0 else over
				var want: Color = baked.get_pixel(x, y)
				if absf(laid.r - want.r) > 0.01 or absf(laid.g - want.g) > 0.01 or absf(laid.b - want.b) > 0.01 or absf(laid.a - want.a) > 0.01:
					same = false
	check("the map's fog laid over its terrain is the picture it was, seen and unseen, either way", same)
	var map: Control = _MapScene.instantiate() as Control
	add_child(map)
	map.set("_area", area_id)
	map.visible = true
	map.call("refresh", area_id)
	var picture: Variant = map.get("_picture")
	var before: Color = (map.get("_fog") as Image).get_pixel(2, 0)
	WorldMap._seen[area_id] = PackedByteArray([0b111])
	WorldMap.last_reveal = Rect2i(2, 0, 1, 1)
	map.call("_on_explored", area_id)
	var after: Color = (map.get("_fog") as Image).get_pixel(2, 0)
	check("  a step that uncovers ground clears that much of the fog and builds no new picture (it was 56 ms a step in the Big Field, now under 1)",
		map.get("_picture") == picture and before.a > 0.5 and after.a < 0.01
		and not _func_body(_code_src("res://src/ui/menus/mapscreen.gd"), "func _on_explored(").contains("refresh()\n\tWorldMap"),
		[before, after])
	map.queue_free()
	WorldMap._terrain.erase(area_id)
	WorldMap._seen.erase(area_id)

	# PLAYERS IN HOUSES.
	var house: Node2D = (load("res://scene/walls/shophouse.tscn") as PackedScene).instantiate() as Node2D
	house.global_position = o + Vector2(2000, 2000)
	add_child(house)
	var trigger: Area2D = house.get_node("trigger") as Area2D
	var box: CollisionShape2D = trigger.get_node("collisionshape2d") as CollisionShape2D
	var stand := GDScript.new()
	stand.source_code = "extends Node2D\nfunc set_hidden_indoors(hidden: bool) -> void:\n\tvisible = not hidden\n"
	stand.reload()
	var them := Node2D.new()
	them.set_script(stand)
	them.add_to_group(&"remoteplayers")
	add_child(them)
	them.global_position = box.global_position
	trigger.call("hide_those_inside")
	var hidden_out: bool = not them.visible
	trigger.set("me_inside", true)
	trigger.call("hide_those_inside")
	var shown_in: bool = them.visible
	trigger.set("me_inside", false)
	trigger.call("hide_those_inside")
	them.global_position = box.global_position + Vector2(0, 400)
	trigger.call("hide_those_inside")
	var shown_out: bool = them.visible
	check("another player inside the shop is hidden from you outside it, shown when you are in, and again when they come out",
		hidden_out and shown_in and shown_out and trigger.call("covers", box, box.global_position)
		and not trigger.call("covers", box, box.global_position + Vector2(0, 400)), [hidden_out, shown_in, shown_out])
	them.global_position = box.global_position
	trigger.call("hide_those_inside")
	house.free()
	check("  and a house that goes shows whoever it hid", them.visible)
	var RemoteCode: GDScript = load("res://src/characters/remoteplayer.gd") as GDScript
	var picture_node: Node2D = RemoteCode.new() as Node2D
	var pet := AnimatedSprite2D.new()
	picture_node.set("_pet", pet)
	picture_node.call("set_hidden_indoors", true)
	var both_hidden: bool = not picture_node.visible and not pet.visible
	picture_node.call("set_hidden_indoors", false)
	check("  a player's picture hides its pet with it", both_hidden and picture_node.visible and pet.visible)
	pet.free()
	picture_node.free()
	them.queue_free()
	await get_tree().process_frame
	print("  (after the first descent: done)")


# =============================================================================
# THE GM PANEL, TIDIED AND LIVE (0.112.1)
# =============================================================================
# The owner: "can you update all of my tabs in gm panel" - and chose all of
# tidy and dedupe, a new look, live data and what was missing. Steps 1 and 2:
# the look and the tidy, and live data.
func _test_the_gm_panel_tidied_and_live() -> void:
	section("THE GM PANEL, TIDIED AND LIVE - every tab a button away, one text size, each switch in one place, tabs read again while open (0.112.1)")
	var was_owner: bool = Api.is_owner
	Api.is_owner = true
	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var tabs: TabContainer = gm.get_node("%ownertabs") as TabContainer
	var buttons: Array = gm.get("tab_buttons")
	var grid: GridContainer = gm.find_child("tabbuttons", true, false) as GridContainer
	var titles: Array = buttons.map(func(b: Button) -> String: return b.text)
	check("every tab is a button, four to a row, where the strip that showed four of seven was",
		not tabs.tabs_visible and grid != null and grid.columns == 4 and titles == ["Account", "Testing", "Server", "World", "Events", "Economy", "Health", "Guilds"]
		and grid.get_index() == gm.get_node("%tabsscroll").get_index() - 1, titles)
	(buttons[5] as Button).pressed.emit()
	check("  a button picks its tab and is lit", tabs.current_tab == 5 and (buttons[5] as Button).button_pressed
		and not (buttons[0] as Button).button_pressed)
	tabs.current_tab = 0
	check("  and the tab picked another way lights its button", (buttons[0] as Button).button_pressed
		and not (buttons[5] as Button).button_pressed)
	check("one text size: the tabs made in code draw at the scene's 13",
		tabs.theme != null and tabs.theme.default_font_size == 13
		and (gm.get("world_tab").get("on_switch") as Control).get_theme_font_size("font_size") == 13)
	var testing: Node = tabs.get_node("testing")
	var server: Node = tabs.get_node("server")
	check("PvP and Trading are the Server tab's, under WHAT PLAYERS MAY DO - not Testing's (\"your own character only\")",
		server.is_ancestor_of(gm.get_node("%pvpbutton")) and server.is_ancestor_of(gm.get_node("%tradebutton"))
		and not testing.is_ancestor_of(gm.get_node("%pvpbutton"))
		and server.find_child("playlabel", true, false) is Label
		and (server.find_child("playlabel", true, false) as Label).text == "WHAT PLAYERS MAY DO")
	check("  each switch in one place: the kill receipts the Health tab's alone, the item-id row gone (the catalogue gives)",
		gm.get_node_or_null("%receiptsbutton") == null and gm.get("receipts_button") == gm.get("health_tab").get("receipts_switch")
		and gm.get_node_or_null("%iteminput") == null and gm.get_node_or_null("%itembutton") == null
		and gm.get_node_or_null("%cataloguebutton") != null)

	# LIVE.
	var world: Node = gm.get("world_tab")
	var asked: Array = []
	var now := int(Time.get_unix_time_from_system())
	var view := {"settings": {"on": true, "hours": 3, "hit_on": true, "hit_percent": 25}, "state": {"on": true, "element": 0, "now": now},
		"recent": [], "lands": [], "now": now}
	world.set("fetch", func(path: String) -> Dictionary:
		asked.append(path)
		return {"ok": true, "status": 200, "data": view.duplicate(true)})
	# THE OPEN'S READS FAIL AT ONCE (0.117.2). Opening the panel reads a dozen
	# things from the server, and the clock starts when they are done. At the
	# suite's address no server runs: on Linux each fails at once, on the
	# owner's Windows each waited out its 10 s - over a minute. An address the
	# game cannot use (no http://) is refused on the next frame everywhere;
	# the old one is put back once the clock is checked.
	var kept_url: String = ApiForTests.BASE_URL
	ApiForTests.BASE_URL = "suite-no-server"
	gm.visible = true
	await get_tree().process_frame
	gm.set("read_at", {})
	asked.clear()
	(buttons[3] as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var read_on_pick: bool = asked == ["/api/server/world"]
	(buttons[0] as Button).pressed.emit()
	(buttons[3] as Button).pressed.emit()
	await get_tree().process_frame
	check("a tab picked is read again when its last read is stale - and not again within %d s" % int(gm.get("STALE_SECONDS")),
		read_on_pick and asked.size() == 1, asked)
	var timer: Timer = gm.get("_live_timer")
	# The clock starts when the open's reads are done - a few frames now.
	await _larder_wait(func() -> bool: return timer != null and not timer.is_stopped(), 10.0)
	check("  and a clock reads the tab shown every %d s while the panel is open" % int(gm.get("LIVE_SECONDS")),
		timer != null and is_equal_approx(timer.wait_time, 30.0) and not timer.is_stopped())
	ApiForTests.BASE_URL = kept_url
	(world.get("hours_box") as SpinBox).value = 7.0
	view["settings"]["hours"] = 3
	await world.refresh()
	var kept: bool = is_equal_approx((world.get("hours_box") as SpinBox).value, 7.0) and bool(world.get("edited"))
	await world.refresh(true)
	check("  a World setting changed and not saved is kept through a read; Refresh by hand puts the server's back",
		kept and is_equal_approx((world.get("hours_box") as SpinBox).value, 3.0) and not bool(world.get("edited")))
	gm.visible = false
	await get_tree().process_frame
	check("  closed, the clock stops", timer.is_stopped())

	var events: Node = gm.get("events_tab")
	var two := {"events": [{"id": 4, "name": "Double XP", "state": "coming", "starts_at": now + 600, "ends_at": now + 4200},
		{"id": 9, "name": "1.5x Loot", "state": "coming", "starts_at": now + 900, "ends_at": now + 4500}], "now": now}
	events.call("show_answer", two)
	var pick: OptionButton = events.get("cancel_pick")
	pick.select(pick.get_item_index(9))
	events.call("show_answer", two)
	check("the Events tab keeps the event picked to call off through a read",
		pick.get_item_id(pick.selected) == 9)
	var economy: Node = gm.get("economy_tab")
	var economy_code: String = _code_src("res://src/ui/owner/economytab.gd")
	check("  and the Economy tab's clock reads the flow and the canary, never rebuilding the rules' boxes under a typed number",
		_func_body(economy_code, "func refresh_live(").contains("refresh_flow(") and _func_body(economy_code, "func refresh_live(").contains("refresh_canary(")
		and not _func_body(economy_code, "func refresh_live(").contains("refresh_rules(")
		and _func_body(_code_src("res://src/ui/owner/ownerpanel.gd"), "func refresh_tab(").contains("economy_tab.refresh_live()")
		and economy.has_method("refresh_live"))
	# THE GUILDS TAB (step 3): every guild, renamed or disbanded.
	var guilds: Node = gm.get("guilds_tab")
	var sent: Array = []
	var list := {"guilds": [{"name": "zeta", "founded_by": "bo", "created_at": now - 86400, "size": 1, "leader": "bo"},
		{"name": "Alpha Wolves", "founded_by": "cy", "created_at": now - 3600, "size": 5, "leader": "cy"}], "now": now, "may_disband": true}
	guilds.set("fetch", func(_path: String) -> Dictionary: return {"ok": true, "status": 200, "data": list.duplicate(true)})
	guilds.set("send", func(path: String, body: Dictionary) -> Dictionary:
		sent.append([path, body])
		return {"ok": true, "status": 200, "data": {"guild": str(body.get("name", body.get("guild"))), "was": str(body.get("guild")),
			"state": "renamed" if body.get("action") == "rename" else "disbanded", "members_removed": 5}})
	await guilds.refresh()
	var gpick: OptionButton = guilds.get("guild_pick")
	check("the Guilds tab lists every guild - name, members, leader - sorted, and says what the one picked is",
		guilds.get_parent() == tabs and gpick.item_count == 2 and gpick.get_item_text(0) == "Alpha Wolves - 5 members, led by cy"
		and gpick.get_item_text(1) == "zeta - 1 member, led by bo"
		and (guilds.get("about_label") as Label).text.contains("5 members, led by cy"), [gpick.get_item_text(0), (guilds.get("about_label") as Label).text])
	await guilds.rename()
	var asked_nothing: bool = sent.is_empty()
	(guilds.get("name_edit") as LineEdit).text = "Alpha Pack"
	(guilds.get("reason_edit") as LineEdit).text = "name was rude"
	await guilds.rename()
	check("  Rename needs a name and a reason, then asks the staff route",
		asked_nothing and sent == [["/api/staff/guild", {"guild": "Alpha Wolves", "action": "rename", "name": "Alpha Pack", "reason": "name was rude"}]], sent)
	sent.clear()
	await guilds.disband()
	var armed: bool = sent.is_empty() and (guilds.get("disband_button") as Button).text == "Sure? Disband"
	await guilds.disband()
	check("  Disband asks twice, then takes it down with the reason",
		armed and sent == [["/api/staff/guild", {"guild": "Alpha Wolves", "action": "disband", "reason": "name was rude"}]], sent)
	check("  and the tab is read with the others when picked and on the clock",
		_func_body(_code_src("res://src/ui/owner/ownerpanel.gd"), "func refresh_tab(").contains("guilds_tab.refresh()"))
	gm.queue_free()
	Api.is_owner = was_owner
	await get_tree().process_frame
	print("  (the GM panel, tidied and live: done)")


# =============================================================================
# THE HUD BAR: ITS KEYS, WHAT IS OPEN, THE SHOP, A RUN READY (0.113.0)
# =============================================================================
# The owner: "can you update my hudscreen buttons also". Each button with a key
# wears it, small, in its corner; a button is lit while what it opens is up;
# Shop is grey away from a counter; Minigames wears a dot when a run is ready
# again; and Kills and Kingdom moved from Social into a Stats dropdown - C
# still opens Stats at once.
func _test_the_hud_bar_says_keys_and_what_is_open() -> void:
	section("THE HUD BAR - keys on the buttons, lit while open, Shop at a counter, a run ready (0.113.0)")
	const Hud := preload("res://src/ui/characterhud.gd")
	var Card: GDScript = load("res://src/ui/minigames/minigamescard.gd") as GDScript
	Card.call("forget_news")
	var was_touch: bool = TouchControls.active
	TouchControls.set_active(false)
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame

	# ---- the keys ----
	var letter := func(btn: String) -> String:
		var l: Label = hud.get_node("%" + btn).get_node_or_null("keyletter") as Label
		return l.text if l != null and l.visible else ""
	var wanted := {"inventorybutton": "inventory_toggle", "equipmentbutton": "equipment_toggle",
		"statsbutton": "character_toggle", "mapbutton": "minimap_toggle",
		"characterbutton": "character_toggle", "killsbutton": "kills_toggle", "controlsbutton": "help_toggle"}
	var shown: Dictionary = {}
	var right: bool = true
	for b in wanted:
		shown[b] = letter.call(b)
		right = right and shown[b] != "" and shown[b] == ControlsPanel.action_key(wanted[b])
	check("every button with a key wears it - Inventory, Gear, Stats, Map on the bar; Stats, Kills, Controls in theirs",
		right, shown)
	var bare: Array = []
	for b in ["shopbutton", "chatbutton", "socialbutton", "minigamesbutton", "menubutton", "kingdombutton"]:
		if letter.call(b) != "":
			bare.append(b)
	check("  and a button with no key wears none", bare.is_empty(), bare)
	var inv: Button = hud.get_node("%inventorybutton")
	var tag: Label = inv.get_node("keyletter")
	check("  small and dim, and a click goes through it to the button",
		tag.get_theme_font_size("font_size") < inv.get_theme_font_size("font_size")
		and tag.get_theme_color("font_color").a < 1.0 and tag.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var crowded: Array = []
	for b in ["inventorybutton", "equipmentbutton", "statsbutton", "mapbutton"]:
		var button: Button = hud.get_node("%" + b)
		var font: Font = button.get_theme_font("font")
		var word: float = font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
		var mark: float = font.get_string_size(letter.call(b), HORIZONTAL_ALIGNMENT_LEFT, -1, Hud.KEY_LETTER_SIZE).x
		if (button.size.x - word) / 2.0 < mark + Hud.KEY_LETTER_INSET.x + 1.0:
			crowded.append([b, button.size.x, word, mark])
	check("  the letter sits clear of the button's word", crowded.is_empty(), crowded)
	InputMap.add_action(&"zz_long_key")
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	InputMap.action_add_event(&"zz_long_key", space)
	check("  a key whose name is too long for the corner is left to the tooltip",
		Hud.key_letter_for("zz_long_key") == "" and Hud.key_letter_for("no_such_action") == "",
		Hud.key_letter_for("zz_long_key"))
	InputMap.erase_action(&"zz_long_key")
	check("  the tooltip still says the key, and Stats' tooltip promises nothing C does not do",
		inv.tooltip_text.ends_with("(%s)" % ControlsPanel.action_key("inventory_toggle"))
		and not (hud.get_node("%statsbutton") as Button).tooltip_text.contains("("),
		[inv.tooltip_text, (hud.get_node("%statsbutton") as Button).tooltip_text])

	# ---- Stats is a dropdown ----
	var stats_bar: Button = hud.get_node("%statsbutton")
	var stats_menu: Control = hud.get_node("%statsmenu")
	stats_bar.pressed.emit()
	await get_tree().process_frame
	check("Stats on the bar opens its dropdown, above the button",
		stats_menu.visible and stats_menu.get_global_rect().end.y <= stats_bar.get_global_rect().position.y,
		[stats_menu.get_global_rect(), stats_bar.get_global_rect()])
	hud.call("paint_lit_buttons")
	check("  lit while it is open", bool(hud.call("is_lit", "statsbutton")))
	(hud.get_node("%characterbutton") as Button).pressed.emit()
	await get_tree().process_frame
	var stats_window: Control = hud.get("stats_screen")
	check("  Stats in it opens the stats window and shuts the dropdown",
		stats_window != null and stats_window.visible and not stats_menu.visible)
	hud.call("paint_lit_buttons")
	check("  Stats stays lit while the window is up, and Stats inside too",
		bool(hud.call("is_lit", "statsbutton")) and bool(hud.call("is_lit", "characterbutton")))
	check("  lit is the theme's pressed look, held",
		stats_bar.get_theme_stylebox("normal") == stats_bar.get_theme_stylebox("pressed")
		and stats_bar.get_theme_stylebox("hover") == stats_bar.get_theme_stylebox("pressed"))
	var c_key := InputEventKey.new()
	c_key.physical_keycode = KEY_C
	c_key.keycode = KEY_C
	c_key.pressed = true
	var c_says: bool = c_key.is_action_pressed("character_toggle")
	hud.call("_unhandled_input", c_key)
	check("C still shuts and opens the stats window at once, no dropdown",
		c_says and not stats_window.visible and not stats_menu.visible)
	hud.call("paint_lit_buttons")
	check("  and the bar's Stats goes dark with it, its own look back",
		not bool(hud.call("is_lit", "statsbutton")) and not stats_bar.has_theme_stylebox_override("normal"))
	var missing: Array = []
	for b in Hud.NAV_LIT_BY:
		if not (String(Hud.NAV_LIT_BY[b]) in hud) or hud.get_node_or_null("%" + b) == null:
			missing.append(b)
	check("  every lit button names a real button and a window the HUD keeps", missing.is_empty(), missing)
	(hud.get_node("%socialbutton") as Button).pressed.emit()
	hud.call("paint_lit_buttons")
	check("  an open dropdown lights its button", bool(hud.call("is_lit", "socialbutton"))
		and not bool(hud.call("is_lit", "menubutton")))
	hud.call("close_nav_menus")
	hud.call("paint_lit_buttons")
	check("  and shut, it goes dark", not bool(hud.call("is_lit", "socialbutton")))

	# ---- the shop ----
	var shop: Button = hud.get_node("%shopbutton")
	hud.call("paint_shop_button")
	check("Shop is grey away from a counter, and says why", shop.disabled and shop.tooltip_text == Hud.SHOP_AWAY_TIP,
		[shop.disabled, shop.tooltip_text])
	var counter_script := GDScript.new()
	counter_script.source_code = "extends Node\nvar here: bool = true\nfunc player_at_counter() -> bool:\n\treturn here\n"
	counter_script.reload()
	var counter := Node.new()
	counter.set_script(counter_script)
	counter.add_to_group("vendors")
	add_child(counter)
	hud.call("paint_shop_button")
	check("  at a counter it lights up to be pressed", not shop.disabled and shop.tooltip_text == Hud.SHOP_HERE_TIP)
	var panel_script := GDScript.new()
	panel_script.source_code = "extends PanelContainer\nfunc close_shop() -> void:\n\tvisible = false\n"
	panel_script.reload()
	var open_shop := PanelContainer.new()
	open_shop.set_script(panel_script)
	hud.add_child(open_shop)
	hud.set("shop_panel", open_shop)
	counter.set("here", false)
	hud.call("paint_shop_button")
	hud.call("paint_lit_buttons")
	check("  with the shop open it is lit and pressable even as the counter goes",
		not shop.disabled and bool(hud.call("is_lit", "shopbutton")))
	shop.pressed.emit()
	check("  and pressing it then shuts the shop", not open_shop.visible)
	hud.call("paint_shop_button")
	check("  grey again once it is shut and you have walked off", shop.disabled)
	hud.set("shop_panel", null)
	open_shop.queue_free()
	counter.queue_free()
	var vendor_src: String = _code_src("res://src/world/vendor.gd")
	check("  a vendor says whether you stand at it, open or not",
		_func_body(vendor_src, "func player_at_counter(").contains("_player_nearby != null")
		and not _func_body(vendor_src, "func player_at_counter(").contains("_is_open")
		and _func_body(vendor_src, "func can_open_for_player(").contains("player_at_counter() and not _is_open"))

	# ---- a run ready again ----
	var mg: Button = hud.get_node("%minigamesbutton")
	var card: Node = hud.get("minigames_card")
	card.set("area_now", func() -> String: return "elusion")
	var listing: Dictionary = {"ok": true, "status": 200, "data": {"games": [{"id": "endless", "ready_in": 0},
		{"id": "healerrun", "plays_left": 3, "ready_in": 0}]}}
	card.set("list_request", func(_p: String, _t: float) -> Dictionary: return listing)
	card.call("paint_news")
	check("Minigames wears no dot while nothing is known", mg.text == "Minigames", mg.text)
	Card.call("note_wait", "endless", 0)
	card.call("paint_news")
	check("  a run ready lights it, green, with a dot", mg.text == "Minigames •"
		and mg.get_theme_color("font_color") == Hud.MINIGAMES_READY_COLOUR, mg.text)
	var other: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	add_child(other)
	await get_tree().process_frame
	check("  a new area's bar keeps it", (other.get_node("%minigamesbutton") as Button).text == "Minigames •")
	other.queue_free()
	mg.pressed.emit()
	await get_tree().process_frame
	check("  opening the card leaves it lit - it is a run to play, not news to read (0.113.1)",
		mg.text == "Minigames •" and (card as Control).visible, mg.text)
	hud.call("close_nav_menus")
	Card.call("forget_news")
	Card.call("note_wait", "endless", 3600)
	Card.call("note_wait", "healerrun", 600)
	card.call("paint_news")
	check("  with every run used it is out", mg.text == "Minigames", mg.text)
	Card.call("note_wait", "endless", 0)
	card.call("paint_news")
	check("  the end of a wait lights it again", mg.text == "Minigames •", mg.text)
	Card.call("forget_wait", "endless")
	card.call("paint_news")
	check("  going in puts it out at once, and the next area's card asks again", mg.text == "Minigames"
		and not (Card.call("ready_games") as Array).has("endless"))
	var card_code: String = _code_src("res://src/ui/minigames/minigamescard.gd")
	check("  Go into the Endless goes in only after the server says yes, and forgets the day then",
		_func_body(card_code, "func _on_go(").find("forget_wait(GAME)") > _func_body(card_code, "func _on_go(").find("if res.get(\"ok\", false):"))
	Card.call("note_wait", "healerrun", 0)
	card.set("area_now", func() -> String: return "endless")
	card.call("paint_news")
	check("  inside the Endless there is no dot - Leave is the button there", mg.text == "Minigames")
	card.set("area_now", func() -> String: return "elusion")
	card.call("paint_news")
	check("  the Healer's Run counts too", mg.text == "Minigames •")
	var card_src: String = _code_src("res://src/ui/minigames/minigamescard.gd")
	check("  the card asks the server once a login, signed in, never inside the Endless",
		_func_body(card_src, "func _ready(").contains("Api.is_logged_in() and _asked_by != Api.username and not inside_endless()"))

	# ---- the touch grid ----
	TouchControls.set_active(true)
	await get_tree().process_frame
	hud.call("paint_shop_button")
	var grid_menu: Control = hud.get("touch_menu")
	grid_menu.call("open")
	var grid: Control = grid_menu.get("grid")
	check("the touch grid's Stats is the stats window, and its Shop is grey away from a counter",
		grid.get_node_or_null("characterbutton") != null and grid.get_node_or_null("statsbutton") == null
		and (grid.get_node("shopbutton") as Button).disabled)
	check("  folded, Menu wears the Minigames dot", (hud.get_node("%menubutton") as Button).text == "Menu •",
		(hud.get_node("%menubutton") as Button).text)
	hud.call("close_nav_menus")
	TouchControls.set_active(was_touch)
	Card.call("forget_news")
	hud.queue_free()
	await get_tree().process_frame
	print("  (the HUD bar: done)")



# =============================================================================
# SHARP PIXELS (0.114.0)
# =============================================================================
# The owner: "is there a way we can increase sharpness for a better picture?"
# At 1080p the canvas is drawn 1.5x, so zoom 3 made an art pixel 4.5 screen
# pixels - 4 and 5 wide by turns. On, the camera goes to the nearest zoom that
# makes it whole.
func _test_sharp_pixels() -> void:
	section("SHARP PIXELS - every art pixel a whole number of screen pixels (0.114.0)")
	var was_sharp: bool = bool(Settings.get_value("sharp_pixels"))
	var was_zoom: float = float(Settings.get_value("camera_zoom"))
	check("on by default", Settings.DEFAULTS["sharp_pixels"] == true)
	check("at 1080p zoom 3 goes to 5 screen pixels an art pixel (4.5 rounds closer)",
		is_equal_approx(Settings.sharp_zoom(3.0, 1.5) * 1.5, 5.0), Settings.sharp_zoom(3.0, 1.5))
	var uneven: Array = []
	for scale in [1.0, 1.25, 1.5, 2.0, 3.0]:
		var z: float = Settings.CAMERA_ZOOM_MIN
		while z <= Settings.CAMERA_ZOOM_MAX + 0.001:
			var drawn: float = Settings.sharp_zoom(z, scale) * scale
			var fewest: float = ceilf(Settings.CAMERA_ZOOM_MIN * scale - 0.0001)
			if absf(drawn - roundf(drawn)) > 0.0001 or Settings.sharp_zoom(z, scale) < Settings.CAMERA_ZOOM_MIN - 0.0001 \
					or (absf(drawn - z * scale) > 0.5001 and not is_equal_approx(drawn, fewest)):
				uneven.append([scale, z, drawn])
			z += Settings.CAMERA_ZOOM_STEP
	check("  every zoom the slider offers, at every window size offered, is whole, within half a pixel, never past 1x",
		uneven.is_empty(), uneven)
	check("  never further out than 1x: at a 1.25x window, 1x goes in to 2 pixels",
		is_equal_approx(Settings.sharp_zoom(1.0, 1.25) * 1.25, 2.0) and is_equal_approx(Settings.sharp_zoom(0.2, 1.0), 1.0),
		Settings.sharp_zoom(1.0, 1.25))
	check("  a whole zoom on a whole canvas is left alone", is_equal_approx(Settings.sharp_zoom(2.5, 2.0), 2.5)
		and is_equal_approx(Settings.sharp_zoom(3.0, 1.0), 3.0))

	var camera := Camera2D.new()
	add_child(camera)
	Settings.canvas_scale_for_test = 1.5
	Settings.set_value("sharp_pixels", true)
	Settings.set_value("camera_zoom", 3.0)
	Settings.reapply_camera_zoom()
	check("a camera in the tree goes there", is_equal_approx(camera.zoom.x * 1.5, 5.0)
		and is_equal_approx(camera.zoom.y, camera.zoom.x), camera.zoom)
	check("  and the setting keeps what was asked", is_equal_approx(float(Settings.get_value("camera_zoom")), 3.0))
	var told: Array = []
	var listen := func(key: String, _value: Variant) -> void: told.append(key)
	Settings.changed.connect(listen)
	Settings.set_value("sharp_pixels", false)
	check("off, the zoom is as asked again, and the name plate is told",
		is_equal_approx(camera.zoom.x, 3.0) and told.has("camera_zoom"), [camera.zoom, told])
	Settings.set_value("sharp_pixels", true)
	var seen: Array = []
	Settings.set_value("camera_zoom", 3.0)
	for i in 6:
		seen.append(roundi(camera.zoom.x * 1.5))
		Settings.step_camera_zoom(-1)
	check("  each notch of the wheel changes the picture while it can: 5, 4, 3, 2 pixels, then 1x",
		seen.slice(0, 4) == [5, 4, 3, 2] and is_equal_approx(float(Settings.get_value("camera_zoom")), 1.0), seen)
	Settings.set_value("camera_zoom", 3.0)
	told.clear()
	Settings.canvas_scale_for_test = 2.0
	Settings.reapply_camera_zoom()
	check("a new window size is a new canvas: at 1440p zoom 3 is 6 pixels, and the plate is told",
		is_equal_approx(camera.zoom.x, 3.0) and told.has("camera_zoom"), camera.zoom)
	Settings.changed.disconnect(listen)
	Settings.canvas_scale_for_test = 0.0
	var settings_src_early: String = _code_src("res://src/systems/settings.gd")
	var root: Window = get_tree().root
	var was_mode: Window.ContentScaleMode = root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	check("  Low render resolution draws the world at 1280 x 720: the camera's pixels are the canvas's",
		is_equal_approx(Settings.canvas_scale(), 1.0)
		and _func_body(settings_src_early, "func canvas_scale(").contains("CONTENT_SCALE_MODE_VIEWPORT:\n\t\treturn 1.0"))
	check("  and a run with no screen (the suite's) counts as 1x, not its token window",
		_func_body(settings_src_early, "func canvas_scale(").contains("DisplayServer.get_name() == \"headless\""))
	root.content_scale_mode = was_mode
	var settings_src: String = _code_src("res://src/systems/settings.gd")
	check("  and a resize asks again",
		_func_body(settings_src, "func _ready(").contains("root.size_changed.connect(_on_root_resized)")
		and _func_body(settings_src, "func _on_root_resized(").contains("reapply_camera_zoom"))
	camera.queue_free()
	var opts: Node = _OptionsScene.instantiate()
	var toggle: CheckButton = opts.get_node_or_null("%sharppixels") as CheckButton
	check("Options has the switch, under Camera view, saying what it does",
		toggle != null and toggle.get_parent().get_parent() == opts.get_node("%camerazoom").get_parent().get_parent()
		and toggle.tooltip_text.contains("same size"))
	opts.free()
	Settings.set_value("sharp_pixels", was_sharp)
	Settings.set_value("camera_zoom", was_zoom)
	print("  (sharp pixels: done)")


# =============================================================================
# THE DESCENT, KINDER (0.115.0)
# =============================================================================
# The owner: "time to improve the decent feels pretty boring and chars die
# fast". Step 1: a ward over your health, filled at every room cleared; the
# crypt hitting softer floor by floor; smaller rooms; the pack in waves from
# the edges, each spot marked first.
func _test_the_descent_is_kinder() -> void:
	section("THE DESCENT, KINDER - a ward, softer hits, smaller rooms, waves (0.115.0)")
	const Boons := preload("res://src/world/descent/descentboons.gd")
	const RunScript := preload("res://src/world/descent/descentrun.gd")
	const DoorScript := preload("res://src/world/descent/descentdoor.gd")
	const Build := preload("res://src/tools/builddescent.gd")
	# ---- the ward ----
	Boons.clear()
	Boons.fill_ward(400)
	var off_run: bool = Boons.ward == 0 and Boons.absorb(50) == 0
	Boons.active = true
	Boons.fill_ward(400)
	var full: bool = Boons.ward == 160 and Boons.ward_most == 160
	var first: int = Boons.absorb(50)
	var second: int = Boons.absorb(200)
	var third: int = Boons.absorb(30)
	check("the ward is 40% of your most health, takes a hit first, and once it is gone takes nothing; off a run there is none",
		off_run and full and first == 50 and second == 110 and third == 0 and Boons.ward == 0, [first, second, third])
	var hit_code: String = _code_src("res://src/characters/player.gd")
	var hit_at: int = hit_code.find("func take_damage(")
	var hit_body: String = hit_code.substr(hit_at, hit_code.find("\nfunc ", hit_at + 1) - hit_at)
	var absorb_at: int = hit_body.find("DescentBoons.absorb(reduced_amount")
	check("  in your hits: after armour and the land, before your health - and the number says the whole hit",
		absorb_at > hit_body.find("damage_taken(amount, element)") and absorb_at < hit_body.find("hp = clamp(hp - reduced_amount")
		and hit_body.contains("_spawn_floating_label(reduced_amount + warded"))
	# ---- softer floors ----
	var takens: Array = RunScript.FLOORS.map(func(f: Dictionary) -> float: return float(f.get("taken", 1.0)))
	Boons.floor_taken = 0.5
	var soft: bool = is_equal_approx(Boons.taken_factor(), 0.5)
	Boons.clear()
	check("the crypt hits for half on floor 1, then harder each floor down to 1.2 on the seventh (0.123.0) - and nothing of it off a run",
		takens == [0.5, 0.65, 0.8, 0.9, 1.0, 1.1, 1.2] and soft and is_equal_approx(Boons.taken_factor(), 1.0), takens)
	# ---- smaller rooms, in waves ----
	var sizes: Array = []
	var probe: Node = RunScript.new()
	for at in [[0, 1], [0, RunScript.ROOMS], [RunScript.FLOORS.size() - 1, RunScript.ROOMS]]:
		probe.set("floor_index", at[0])
		probe.set("room", at[1])
		sizes.append(int(probe.call("pack_size")))
	probe.free()
	check("a room begins at 5 and never holds more than %d (0.123.0; floor 1 room 1, floor 1 room 4, floor 7 room 4: %s)"
		% [RunScript.PACK_MOST, sizes], sizes == [5, 8, 20], sizes)
	check("  in waves of up to five, four at most",
		RunScript.waves_for(3) == 1 and RunScript.waves_for(5) == 1 and RunScript.waves_for(6) == 2
		and RunScript.waves_for(10) == 2 and RunScript.waves_for(11) == 3 and RunScript.waves_for(20) == 4
		and RunScript.waves_for(40) == 4)
	# ---- a run, in a room of stand-ins ----
	var room := Node2D.new()
	add_child(room)
	var world := Node2D.new()
	world.name = "ysortworld"
	room.add_child(world)
	var props := Node2D.new()
	props.name = "props"
	world.add_child(props)
	var enemies := Node2D.new()
	enemies.name = "enemies"
	world.add_child(enemies)
	for one in [["doorleft", 217.0], ["doorright", 424.0]]:
		var door := Node2D.new()
		door.set_script(DoorScript)
		door.name = str(one[0])
		door.position = Vector2(float(one[1]), Build.WALL_BACK)
		props.add_child(door)
	var body_script := GDScript.new()
	body_script.source_code = "extends Node2D\nvar hp: int = 400\nvar max_hp: int = 400\n"
	body_script.reload()
	var body := Node2D.new()
	body.set_script(body_script)
	room.add_child(body)
	var run: Node = RunScript.new()
	run.name = "descentrun"
	run.set("player_override", body)
	room.add_child(run)
	await get_tree().process_frame
	var doors: Array = run.get("doors")
	(doors[0] as Node).emit_signal("walked_in", doors[0])
	var ward_on: bool = Boons.active and Boons.ward == 160 and body.get_node_or_null("wardring") != null
	var hud: Node = run.get("hud")
	for i in 3:
		run.call("_process", RunScript.FADE_SECONDS)
	hud.call("paint")
	var shown: bool = bool((hud.get("ward_row") as Control).visible) and (hud.get("ward_text") as Label).text == "160"
	check("a run starts with the ward full, a gold ring at your feet and its bar on the plate",
		ward_on and shown, [Boons.ward, shown])
	# The bottom floor's last room (0.123.0): twenty and four elites, in four
	# waves of five and an elite.
	run.call("_clear_monsters")
	run.set("floor_index", RunScript.FLOORS.size() - 1)
	run.set("room", RunScript.ROOMS - 1)
	run.call("_go", "gold")
	for i in 3:
		run.call("_process", RunScript.FADE_SECONDS)
	body.global_position = Vector2(320, 300)
	run.call("_process", RunScript.FIGHT_DELAY + 0.1)
	var marked: Array = run.get("_coming")
	var marked_elites: int = marked.filter(func(e: Array) -> bool: return bool(e[3])).size()
	var marks: Node2D = room.get_node_or_null("wavemarks") as Node2D
	var before_out: int = (run.get("monsters") as Array).size()
	check("the bottom floor's last room: twenty and four elites in four waves; the first six, an elite with them, are marked on the floor before they step out, the floor's hits at 1.2",
		int(run.call("pack_size")) == 20 and int(run.call("elites_for", "gold")) == 4 and marked.size() == 6
		and marked_elites == 1 and before_out == 0 and marks != null
		and int(run.call("waves_left")) == 3 and is_equal_approx(Boons.floor_taken, 1.2 * RunScript.FLOOR_HARDER),
		[marked.size(), marked_elites, before_out, run.call("waves_left")])
	run.call("_process", RunScript.MARK_SECONDS + 0.05)
	var out: Array = run.get("monsters")
	var rect: Rect2 = run.get("room_rect")
	var at_edges: bool = out.size() == 6
	for m in out:
		var p: Vector2 = (m as Node2D).global_position
		at_edges = at_edges and (p.y <= rect.position.y + 30.5 or p.x <= rect.position.x + 34.5 or p.x >= rect.end.x - 34.5) \
			and p.distance_to(body.global_position) >= RunScript.SPAWN_CLEAR - 0.01
	check("  they step out at the room's edges, clear of you", at_edges)
	for k in 4:
		(out[k] as Node).call("take_damage", 999999)
	run.call("_process", 0.016)
	check("  two left of a wave, the next is marked", (run.get("_coming") as Array).size() == 6
		and int(run.call("waves_left")) == 2)
	run.call("_process", RunScript.MARK_SECONDS + 0.05)
	run.call("_process", RunScript.WAVE_SECONDS + 0.1)
	check("  and the next comes after %d seconds even if you have not cleared the one before" % int(RunScript.WAVE_SECONDS),
		(run.get("_coming") as Array).size() == 6 and int(run.call("waves_left")) == 1)
	run.call("_process", RunScript.MARK_SECONDS + 0.05)
	run.call("_process", RunScript.WAVE_SECONDS + 0.1)
	run.call("_process", RunScript.MARK_SECONDS + 0.05)
	# (0.129.0: a hit pierces some of the ward - none here, for the arithmetic.)
	Boons.pierce_base = 0.0
	Boons.absorb(100)
	var drained: int = Boons.ward
	var not_yet: bool = int(run.get("state")) == RunScript.State.FIGHT
	for m in (run.get("monsters") as Array):
		if is_instance_valid(m):
			(m as Node).call("take_damage", 999999)
	run.call("_process", 0.016)
	check("  the room is clear only when every wave is down - and clearing it fills the ward again (%d -> %d)" % [drained, Boons.ward],
		not_yet and int(run.get("state")) != RunScript.State.FIGHT and Boons.ward == 160 and drained == 60)
	# A KEEPER HITS AT FULL (0.123.0) - the owner: "fire boss in warriors run
	# was doing 0 damage to warrior". Every floor's keeper, and its room as
	# it is entered.
	var keeper_takens: Array = []
	var pack_takens: Array = []
	var taken_probe: Node = RunScript.new()
	for f in RunScript.FLOORS.size():
		taken_probe.set("floor_index", f)
		keeper_takens.append(float(taken_probe.call("taken_for", "keeper")))
		pack_takens.append(float(taken_probe.call("taken_for", "fight")))
	taken_probe.free()
	run.call("_clear_monsters")
	run.set("floor_index", 0)
	run.set("room", RunScript.ROOMS)
	run.call("_go", "keeper")
	for i in 3:
		run.call("_process", RunScript.FADE_SECONDS)
	var from_table: Array = RunScript.FLOORS.map(func(f: Dictionary) -> float: return float(f["keeper_taken"]) * RunScript.KEEPER_HARDER)
	takens = takens.map(func(x: float) -> float: return x * RunScript.FLOOR_HARDER)
	check("  but a keeper's room hits at its floor's keeper_taken, the Fire Keeper's at full or more, set as its room is entered (0.123.0: the Fire Keeper did 0 to a warrior) %s" % [keeper_takens],
		keeper_takens == from_table and float(keeper_takens[0]) >= 1.0 and pack_takens == takens
		and str(run.get("room_kind")) == "keeper" and is_equal_approx(Boons.floor_taken, float(keeper_takens[0])),
		[run.get("room_kind"), Boons.floor_taken, pack_takens])
	# A fall ends the run: the ward and its ring go.
	run.call("knock_out", body)
	check("a fall ends it all: no ward, no ring", Boons.ward == 0 and not Boons.active
		and (body.get_node_or_null("wardring") == null or (body.get_node("wardring") as Node).is_queued_for_deletion()))
	room.queue_free()
	Boons.clear()
	await get_tree().process_frame
	print("  (the Descent, kinder: done)")



# =============================================================================
# THE DESCENT, MORE TO CHOOSE (0.115.0)
# =============================================================================
# Step 2a of DESCENT_PLAN_2.txt: upgrades with rarities, five new ones, and
# four new doors.
func _descent_room_for_test(body_script: GDScript) -> Array:
	"""[room, run, body, doors]: a Descent room of stand-ins."""
	const RunScript := preload("res://src/world/descent/descentrun.gd")
	const DoorScript := preload("res://src/world/descent/descentdoor.gd")
	const Build := preload("res://src/tools/builddescent.gd")
	var room := Node2D.new()
	add_child(room)
	var world := Node2D.new()
	world.name = "ysortworld"
	room.add_child(world)
	var props := Node2D.new()
	props.name = "props"
	world.add_child(props)
	var enemies := Node2D.new()
	enemies.name = "enemies"
	world.add_child(enemies)
	for one in [["doorleft", 217.0], ["doorright", 424.0]]:
		var door := Node2D.new()
		door.set_script(DoorScript)
		door.name = str(one[0])
		door.position = Vector2(float(one[1]), Build.WALL_BACK)
		props.add_child(door)
	var body := Node2D.new()
	body.set_script(body_script)
	room.add_child(body)
	body.global_position = Vector2(320, 300)
	var run: Node = RunScript.new()
	run.name = "descentrun"
	run.set("player_override", body)
	room.add_child(run)
	return [room, run, body, run.get("doors")]


func _descent_enter(run: Node, kind: String, at_room: int = 2) -> void:
	const RunScript := preload("res://src/world/descent/descentrun.gd")
	run.set("room", at_room - 1)
	run.call("_clear_monsters")
	run.call("_go", kind)
	for i in 3:
		run.call("_process", RunScript.FADE_SECONDS)


func _descent_kill_all(run: Node) -> void:
	# Every wave still to come too (0.123.0: rooms come in more of them).
	run.set("_waves", [])
	run.set("_coming", [])
	for m in (run.get("monsters") as Array):
		if is_instance_valid(m):
			(m as Node).call("take_damage", 99999999)


func _test_the_descent_has_more_to_choose() -> void:
	section("THE DESCENT, MORE TO CHOOSE - rarities, five new upgrades, four new doors (0.115.0)")
	const Boons := preload("res://src/world/descent/descentboons.gd")
	const RunScript := preload("res://src/world/descent/descentrun.gd")
	const DoorScript := preload("res://src/world/descent/descentdoor.gd")
	const HudScript := preload("res://src/world/descent/descenthud.gd")
	Boons.clear()
	# ---- rarities ----
	var unrated: Array = []
	for id in Boons.ORDER:
		if not Boons.RARITIES.has(Boons.rarity(id)) or not (Boons.BOONS[id] as Dictionary).has("rarity"):
			unrated.append(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var seen: Dictionary = {"common": 0, "rare": 0, "epic": 0}
	var three_different: bool = true
	for i in 600:
		var drawn: Array = Boons.offers(rng)
		three_different = three_different and drawn.size() == 3 and drawn[0] != drawn[1] and drawn[1] != drawn[2] and drawn[0] != drawn[2]
		for id in drawn:
			seen[Boons.rarity(id)] += 1
	var only_rare: bool = true
	for i in 200:
		for id in Boons.offers(rng, 3, "rare"):
			only_rare = only_rare and Boons.rarity(id) != "common"
	check("every upgrade is common, rare or epic; a pick is three different, commons most, epics least (%s)" % [seen],
		unrated.is_empty() and Boons.BOONS.size() == Boons.ORDER.size() and three_different
		and int(seen["common"]) > int(seen["rare"]) and int(seen["rare"]) > int(seen["epic"]) and int(seen["epic"]) > 0, unrated)
	check("  a shrine, a challenge won and a keeper offer rare or better", only_rare)
	# ---- the new five ----
	Boons.active = true
	Boons.levels = {"bulwark": 2}
	Boons.fill_ward(400)
	check("Bulwark: the ward is 15% more of your health a level (two: 70%, 280 of 400)", Boons.ward == 280, Boons.ward)
	Boons.levels = {"execute": 1}
	check("Execute: a monster under 15% dies to any hit; above it, the hit as it was",
		Boons.executed(10, 100, 3) == 10 and Boons.executed(50, 100, 3) == 3 and Boons.executed(2, 100, 3) == 3)
	var enemy_code: String = _code_src("res://src/enemies/baseenemy.gd")
	var hit_at: int = enemy_code.find("func take_damage(")
	var hit_body: String = enemy_code.substr(hit_at, enemy_code.find("\nfunc ", hit_at + 1) - hit_at)
	var exec_at: int = hit_body.find("DescentBoons.executed(hp, max_hp, amount)")
	check("  in a monster's take_damage, before the shared monster hears the hit and before its health moves",
		exec_at > 0 and exec_at < hit_body.find("sync.own_hit(") and exec_at < hit_body.find("hp = max(hp - amount, 0)"))
	Boons.levels = {"momentum": 1, "might": 0}
	for i in 12:
		Boons.note_kill()
	check("Momentum: each kill in a room 4% more damage and speed, at most ten",
		is_equal_approx(Boons.damage_factor(), 1.4) and is_equal_approx(Boons.speed_factor(), 1.4))
	Boons.room_kills = 0
	Boons.levels = {"secondwind": 1}
	var once: bool = Boons.second_wind() and not Boons.second_wind()
	Boons.new_floor()
	check("Second Wind: once a floor", once and Boons.second_wind())
	Boons.levels = {"thorns": 2}
	check("Thorns: half a swing a level", Boons.thorns_cut(100.0) == 100)
	var span_script := GDScript.new()
	span_script.source_code = "extends Node2D\nfunc attack_damage_range() -> Vector2i:\n\treturn Vector2i(80, 120)\n"
	span_script.reload()
	var hit_script := GDScript.new()
	hit_script.source_code = "extends Node2D\nvar took: int = 0\nfunc take_damage(amount: int, _e: int = 0) -> void:\n\ttook += amount\n"
	hit_script.reload()
	var arena := Node2D.new()
	add_child(arena)
	var me := Node2D.new()
	me.set_script(span_script)
	arena.add_child(me)
	me.global_position = Vector2(100, 100)
	var near := Node2D.new()
	near.set_script(hit_script)
	near.add_to_group("enemies")
	arena.add_child(near)
	near.global_position = Vector2(130, 100)
	var far := Node2D.new()
	far.set_script(hit_script)
	far.add_to_group("enemies")
	arena.add_child(far)
	far.global_position = Vector2(300, 100)
	Boons._thorns_at = -100000
	var cut: int = Boons.thorns(me)
	var again: int = Boons.thorns(me)
	check("  it cuts every monster near you when you are hit - not one far off, and not twice in a moment",
		cut == 1 and int(near.get("took")) == 100 and int(far.get("took")) == 0 and again == 0, [cut, near.get("took"), far.get("took")])
	arena.queue_free()
	var player_code: String = _code_src("res://src/characters/player.gd")
	var take_at: int = player_code.find("func take_damage(")
	var take_body: String = player_code.substr(take_at, player_code.find("\nfunc ", take_at + 1) - take_at)
	check("  from your take_damage, after the hit lands", take_body.find("DescentBoons.thorns(self)") > take_body.find("hp = clamp(hp - reduced_amount"))
	Boons.clear()
	check("  and none of it off a run", Boons.executed(10, 100, 3) == 3 and Boons.momentum() == 1.0 and not Boons.second_wind()
		and Boons.thorns_cut(100.0) == 0)
	# ---- the doors, in a room of stand-ins ----
	var body_script := GDScript.new()
	body_script.source_code = "extends Node2D\nvar hp: int = 400\nvar max_hp: int = 400\n"
	body_script.reload()
	var made: Array = _descent_room_for_test(body_script)
	var room: Node2D = made[0]
	var run: Node = made[1]
	var body: Node2D = made[2]
	await get_tree().process_frame
	var doors: Array = run.get("doors")
	var missing_icon: Array = []
	for kind in RunScript.KINDS:
		if kind != "elite" and kind != "impossible" and not DoorScript.ICONS.has(kind):
			missing_icon.append(kind)
		elif DoorScript.ICONS.has(kind) and DirAccess.dir_exists_absolute("res://art/pack/icons") \
				and not ResourceLoader.exists(str(DoorScript.ICONS[kind])):
			missing_icon.append(kind)
	check("eight doors a room can promise (an Impossible room's with the elite's skull, 0.124.0), each with its picture from the pack", RunScript.KINDS.size() == 8
		and RunScript.KINDS.size() == RunScript.KIND_WEIGHTS.size() and missing_icon.is_empty(), missing_icon)
	(doors[0] as Node).emit_signal("walked_in", doors[0])
	for i in 3:
		run.call("_process", RunScript.FADE_SECONDS)
	# A Rest.
	_descent_enter(run, "rest")
	var fire: bool = room.find_children("restfire", "", true, false).size() == 1
	check("a Rest: no fight, the doors open as the fade ends, a fire in the middle, the ward full and half again (240 of 400)",
		int(run.get("state")) == RunScript.State.CLEAR and (run.get("monsters") as Array).is_empty() and fire
		and Boons.ward == 240 and bool(doors[0].get("open")), [run.get("state"), Boons.ward, fire])
	run.call("_process", RunScript.FIGHT_DELAY + 1.0)
	check("  and nothing comes after", (run.get("monsters") as Array).is_empty() and (run.get("_coming") as Array).is_empty())
	# A Treasure.
	_descent_enter(run, "treasure", 4)
	var whole: int = mini(RunScript.PACK_MOST, RunScript.PACK_FIRST + 4)
	check("a Treasure is lightly guarded: half the pack (%d of %d)" % [int(run.call("pack_size")), whole],
		int(run.call("pack_size")) == ceili(whole / 2.0))
	run.call("_process", RunScript.FIGHT_DELAY + 0.1)
	run.call("_process", RunScript.MARK_SECONDS + 0.05)
	var gold_was: int = int(run.get("gold"))
	_descent_kill_all(run)
	run.call("_process", 0.016)
	check("  and pays three rooms' gold, no pick", int(run.get("gold")) - gold_was == RunScript.GOLD_BASE * RunScript.TREASURE_GOLD
		and int(run.get("state")) == RunScript.State.CLEAR, int(run.get("gold")) - gold_was)
	# A Shrine.
	_descent_enter(run, "shrine")
	run.call("_process", RunScript.FIGHT_DELAY + 0.1)
	run.call("_process", RunScript.MARK_SECONDS + 0.05)
	_descent_kill_all(run)
	run.call("_process", 0.016)
	var shrine_offers: Array = run.get("offers")
	var all_rare: bool = not shrine_offers.is_empty()
	for id in shrine_offers:
		all_rare = all_rare and Boons.rarity(str(id)) != "common"
	check("a Shrine: a rare or better pick - and the floor's monsters hit 15% harder after",
		all_rare and is_equal_approx(Boons.shrine_taken, 1.15)
		and is_equal_approx(Boons.taken_factor(), float(RunScript.FLOORS[0]["taken"]) * RunScript.FLOOR_HARDER * 1.15), shrine_offers)
	run.call("pick", 0)
	# A Challenge, beaten.
	_descent_enter(run, "challenge")
	run.call("_process", RunScript.FIGHT_DELAY + 0.1)
	var given: float = float(run.get("challenge_left"))
	run.call("_process", RunScript.MARK_SECONDS + 0.05)
	_descent_kill_all(run)
	run.call("_process", 0.016)
	var won_offers: Array = run.get("offers")
	var rare_won: bool = not won_offers.is_empty()
	for id in won_offers:
		rare_won = rare_won and Boons.rarity(str(id)) != "common"
	check("a Challenge: %d seconds for this pack; beaten, a rare or better pick" % roundi(given),
		is_equal_approx(given, RunScript.CHALLENGE_BASE + RunScript.CHALLENGE_EACH * (int(run.call("pack_size")) + 2 * int(run.call("elites_for", "challenge"))))
		and rare_won and int(run.get("state")) == RunScript.State.PICK)
	run.call("pick", 0)
	# A Challenge, too slow.
	_descent_enter(run, "challenge")
	run.call("_process", RunScript.FIGHT_DELAY + 0.1)
	run.call("_process", RunScript.MARK_SECONDS + 0.05)
	run.call("_process", given + 1.0)
	run.call("_process", RunScript.MARK_SECONDS + 0.05)
	_descent_kill_all(run)
	run.call("_process", 0.016)
	check("  too slow: no pick, the doors open", int(run.get("state")) == RunScript.State.CLEAR
		and (run.get("offers") as Array).is_empty())
	# Momentum counts this room's kills; a new room starts again.
	check("Momentum's count is this room's kills, and a new room starts it again",
		Boons.room_kills > 0)
	_descent_enter(run, "gold")
	check("  ...here", Boons.room_kills == 0)
	# Down a floor lifts the shrine's price.
	_descent_kill_all(run)
	run.call("_process", RunScript.FIGHT_DELAY + 0.1)
	_descent_enter(run, "down")
	check("down a floor: the shrine's price lifted, Second Wind back", is_equal_approx(Boons.shrine_taken, 1.0)
		and not Boons.wind_used)
	# Second Wind catches a fall, once a floor.
	Boons.levels["secondwind"] = 1
	body.global_position = Vector2(300, 200)
	body.set("hp", 0)
	var caught: bool = bool(run.call("knock_out", body))
	var stood: bool = caught and run.call("running") and int(body.get("hp")) == 1 and body.global_position == Vector2(300, 200) \
		and Boons.ward == Boons.ward_most
	body.set("hp", 0)
	run.call("knock_out", body)
	check("Second Wind: a fall leaves you standing where you were on a full ward, the run going on - the next fall that floor ends it",
		stood and not bool(run.call("running")), [caught, body.get("hp")])
	# The HUD: a card in its rarity's colour.
	var hud: Node = run.get("hud")
	hud.call("show_pick", ["might", "thorns", "secondwind"])
	var names: Array = (hud.get("cards") as Array).map(func(c: Button) -> Color: return (c.get_node("words/name") as Label).get_theme_color("font_color"))
	var level_line: String = ((hud.get("cards") as Array)[1] as Button).get_node("words/level").text
	check("a card's name is in its rarity's colour, the rarity written under",
		names[0] == Boons.RARITY_COLOURS["common"] and names[1] == Boons.RARITY_COLOURS["rare"]
		and names[2] == Boons.RARITY_COLOURS["epic"] and level_line.begins_with("Rare"), level_line)
	hud.call("hide_pick")
	room.queue_free()
	Boons.clear()
	await get_tree().process_frame
	print("  (the Descent, more to choose: done)")
