# testrunner_9.gd - part 9 of the suite (testrunner.gd says how it is
# split): 5 tests, _test_far_attacks_hit_the_swarm,
# _test_a_fall_wakes_you_by_the_chest, _test_the_horde_reaches_the_back_wall,
# _test_the_field_is_dressed and _test_the_field.
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
