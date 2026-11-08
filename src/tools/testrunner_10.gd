# testrunner_10.gd - part 10 of the suite (testrunner.gd says how it is
# split; part 9 passed 250 KB): _test_the_double_axe_in_the_descent,
# _test_the_descent_reroll, _test_a_quicker_pace,
# _test_the_big_field_draws_only_near_the_view and
# _test_the_swarm_steps_the_same_for_less.
extends "res://src/tools/testrunner_9.gd"


# =============================================================================
# THE DOUBLE AXE IN THE DESCENT (0.115.0)
# =============================================================================
# The owner: "we can also use mythic weapon here some how". Step 2's second
# half of DESCENT_PLAN_2.txt: mythic upgrades for a warrior wearing the Double
# Axe - Twin Axes, Storm, Harvester, Magnet, Ricochet - a keeper always
# offering one, and Axe Fury: kills fill a bar, Q throws a giant axe.
func _test_the_double_axe_in_the_descent() -> void:
	section("THE DOUBLE AXE IN THE DESCENT - mythic upgrades and Axe Fury (0.115.0)")
	const Boons := preload("res://src/world/descent/descentboons.gd")
	const RunScript := preload("res://src/world/descent/descentrun.gd")
	const AxeScene := preload("res://scene/projectiles/spinningaxe.tscn")
	Boons.clear()
	# ---- who is offered them ----
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var mythic_without: int = 0
	var mythic_with: int = 0
	var keeper_always: bool = true
	for i in 300:
		for id in Boons.offers(rng):
			if Boons.rarity(str(id)) == "mythic":
				mythic_without += 1
		for id in Boons.offers(rng, 3, "", true):
			if Boons.rarity(str(id)) == "mythic":
				mythic_with += 1
		var keeper: Array = Boons.offers(rng, 3, "rare", true, true)
		var has_mythic: bool = false
		for id in keeper:
			has_mythic = has_mythic or Boons.rarity(str(id)) == "mythic"
		keeper_always = keeper_always and keeper.size() == 3 and has_mythic
	check("mythic upgrades are offered only with the Double Axe on (%d of 900 cards with it), and a keeper always offers one"
		% mythic_with, mythic_without == 0 and mythic_with > 30 and keeper_always, [mythic_without, mythic_with])
	# ---- Storm and Harvester ----
	var axe: SpinningAxe = AxeScene.instantiate()
	var plain: float = axe.base_reach()
	Boons.active = true
	Boons.levels = {"storm": 2, "harvester": 2}
	check("Storm: the axe's reach a quarter wider a level (two: %.0f -> %.0f)" % [plain, axe.base_reach()],
		is_equal_approx(axe.base_reach(), plain * 1.5))
	var axe_code: String = _code_src("res://src/projectiles/spinningaxe.gd")
	var passes: String = _func_body(axe_code, "func _cut_what_it_passes(")
	check("Harvester: half again harder a level coming home, and only coming home",
		is_equal_approx(Boons.harvester_scale(), 2.0) and passes.contains("if state == State.RETURNING:")
		and passes.contains("DescentBoons.harvester_scale()"))
	axe.free()
	# ---- Ricochet and Magnet, in a little arena ----
	var arena := Node2D.new()
	add_child(arena)
	var holder_script := GDScript.new()
	holder_script.source_code = "extends Node2D\nvar is_dying: bool = false\n"
	holder_script.reload()
	var caster := Node2D.new()
	caster.set_script(holder_script)
	arena.add_child(caster)
	caster.global_position = Vector2(0, 0)
	var pulled_script := GDScript.new()
	pulled_script.source_code = "extends Node2D\nvar pulled: float = 0.0\nfunc pull_toward(point: Vector2, step: float) -> void:\n\tpulled += step\nfunc can_be_aimed_at() -> bool:\n\treturn true\n"
	pulled_script.reload()
	var next_one := Node2D.new()
	next_one.set_script(pulled_script)
	next_one.add_to_group("enemies")
	arena.add_child(next_one)
	next_one.global_position = Vector2(-90, 100)
	Boons.levels = {"ricochet": 1}
	var thrown: SpinningAxe = AxeScene.instantiate()
	thrown.caster = caster
	arena.add_child(thrown)
	thrown.throw_to(Vector2(0, 0), Vector2(0, 100))
	var landed_at: Vector2 = thrown.target
	for i in 40:
		thrown.advance(0.02)
		if not thrown.target.is_equal_approx(landed_at):
			break
	var flew_on: bool = thrown.target.is_equal_approx(next_one.global_position) and thrown.state == SpinningAxe.State.OUT \
		and thrown.global_position.distance_to(landed_at) < 1.0
	for i in 40:
		thrown.advance(0.02)
	check("Ricochet: landed, it flies on to the next monster - once - and spins there",
		flew_on and thrown.state == SpinningAxe.State.SPINNING and thrown.global_position.distance_to(next_one.global_position) < 1.0,
		[thrown.target, thrown.state])
	thrown.queue_free()
	Boons.levels = {"magnet": 1}
	var spinning: SpinningAxe = AxeScene.instantiate()
	spinning.caster = caster
	arena.add_child(spinning)
	spinning.throw_to(Vector2(0, 0), Vector2(0, 0))
	spinning.advance(0.02)
	var near := Node2D.new()
	near.set_script(pulled_script)
	near.add_to_group("enemies")
	arena.add_child(near)
	near.global_position = Vector2(40, 0)
	var far := Node2D.new()
	far.set_script(pulled_script)
	far.add_to_group("enemies")
	arena.add_child(far)
	far.global_position = Vector2(200, 0)
	next_one.global_position = Vector2(600, 600)
	spinning.advance(0.1)
	check("Magnet: the spinning axe pulls in what is near it, not what is far",
		spinning.state == SpinningAxe.State.SPINNING and float(near.get("pulled")) > 0.0 and float(far.get("pulled")) == 0.0,
		[near.get("pulled"), far.get("pulled")])
	spinning.queue_free()
	# ---- Twin Axes ----
	Boons.levels = {"twinaxes": 1}
	var warrior: Node = (load("res://src/characters/warrior.gd") as GDScript).new()
	warrior._set_stat_curve()
	warrior.spawn_parent_override = arena
	warrior.equipped = {"weapon": "doubleaxe"}
	warrior.position = Vector2(0, 300)
	var first: SpinningAxe = warrior.throw_axe(warrior.position + Vector2(100, 0))
	var second: SpinningAxe = warrior.get("_twin")
	check("Twin Axes: the throw has a twin beside it, turned off the aim",
		first != null and second != null and second.twin and not first.twin
		and absf((second.target - warrior.position).angle() - (first.target - warrior.position).angle() - warrior.TWIN_TURN) < 0.01)
	warrior.call("_on_twin_caught")
	var twin_freed: bool = warrior.get("_twin") == null
	var catch_code: String = _func_body(axe_code, "func advance(")
	check("  and its catch is its own, so the axe in hand is not forgotten",
		twin_freed and catch_code.contains("\"_on_twin_caught\" if twin else \"_on_axe_caught\""))
	# IN HAND AGAIN (0.123.0) - the owner: "axe stays there every round no
	# respawn lol". A new room of the run puts the axe and its twin away.
	warrior.call("put_axes_away")
	var put_first: bool = first.is_queued_for_deletion() and not bool(warrior.call("axe_is_out"))
	var again: SpinningAxe = warrior.throw_axe(warrior.position + Vector2(100, 0))
	var again_twin: SpinningAxe = warrior.get("_twin")
	warrior.call("put_axes_away")
	var arrive_code: String = _func_body(_code_src("res://src/world/descent/descentrun.gd"), "func _arrive(")
	check("  a new room of the run puts the axe and its twin away at once, so the next throw is yours (0.123.0)",
		put_first and again != null and again != first and again.is_queued_for_deletion() and again_twin != null
		and again_twin.is_queued_for_deletion() and warrior.get("_axe") == null and warrior.get("_twin") == null
		and arrive_code.contains("player.call(\"put_axes_away\")"), [put_first, again_twin])
	first.queue_free()
	second.queue_free()
	warrior.free()
	Boons.levels = {}
	Boons.active = false
	check("  and none of it off a run", not Boons.twin_axes() and not Boons.magnet() and not Boons.ricochet()
		and Boons.axe_reach_scale() == 1.0 and Boons.harvester_scale() == 1.0)
	# ---- Axe Fury ----
	var body_script := GDScript.new()
	body_script.source_code = "extends Node2D\nvar hp: int = 400\nvar max_hp: int = 400\nvar weapon_attack: int = %d\nfunc equipped_weapon_attack() -> int:\n\treturn weapon_attack\nfunc _calculate_melee_damage() -> int:\n\treturn 40\n" % ItemData.WeaponAttack.SPINNING_AXE
	body_script.reload()
	var made: Array = _descent_room_for_test(body_script)
	var room: Node2D = made[0]
	var run: Node = made[1]
	var body: Node2D = made[2]
	await get_tree().process_frame
	var doors: Array = run.get("doors")
	(doors[0] as Node).emit_signal("walked_in", doors[0])
	for i in 3:
		run.call("_process", RunScript.FADE_SECONDS)
	var hud: Node = run.get("hud")
	hud.call("paint")
	var bar_shown: bool = bool((hud.get("fury_row") as Control).visible)
	check("Axe Fury: its bar on the plate while the Double Axe is on", bar_shown and Boons.fury == 0)
	for i in 14:
		Boons.note_kill()
	var early: Node2D = run.call("unleash_fury")
	Boons.note_kill()
	Boons.note_kill()
	hud.call("paint")
	check("  every kill fills it; at %d it is full, the bar says Q" % Boons.FURY_NEEDS,
		early == null and Boons.fury_full() and (hud.get("fury_text") as Label).text == "Q!")
	run.set("room_kind", "gold")
	var target := Node2D.new()
	target.set_script(_hit_counter_script())
	target.add_to_group("enemies")
	room.add_child(target)
	var q := InputEventKey.new()
	q.keycode = KEY_Q
	q.pressed = true
	run.call("_unhandled_input", q)
	var giant: Node2D = room.get_node_or_null("giantaxe") as Node2D
	check("  Q in a fight throws the giant axe and empties the bar", giant != null and Boons.fury == 0
		and giant.get_node_or_null("spin") != null)
	if giant != null:
		target.global_position = giant.global_position
		giant.call("step", 0.0)
		var first_cut: int = int(target.get("took"))
		giant.call("step", 0.1)
		target.global_position = giant.global_position
		giant.call("step", 0.0)
		var held: int = int(target.get("took"))
		giant.call("step", RunScript.FURY_HIT_GAP)
		target.global_position = giant.global_position
		giant.call("step", 0.0)
		check("  it cuts what it meets for %d swings, each monster at most every %.1f s"
			% [RunScript.FURY_SWINGS, RunScript.FURY_HIT_GAP],
			first_cut == 40 * RunScript.FURY_SWINGS and held == first_cut and int(target.get("took")) == first_cut * 2,
			[first_cut, held, target.get("took")])
		var start_far: float = giant.global_position.distance_to(room.get_node("descentrun").get("room_rect").get_center())
		giant.call("step", RunScript.FURY_SECONDS * 0.5)
		var later_far: float = giant.global_position.distance_to(run.get("room_rect").get_center())
		giant.call("step", RunScript.FURY_SECONDS)
		check("  it spirals in round the room, and is gone after %.1f s" % RunScript.FURY_SECONDS,
			later_far < start_far and giant.is_queued_for_deletion(), [start_far, later_far])
	body.set("weapon_attack", ItemData.WeaponAttack.NONE)
	for i in RunScript.FURY_SWINGS * 5:
		Boons.note_kill()
	hud.call("paint")
	check("  with a sword: no bar, and Q does nothing", run.call("unleash_fury") == null
		and not bool((hud.get("fury_row") as Control).visible))
	room.queue_free()
	Boons.clear()
	await get_tree().process_frame
	print("  (the Double Axe in the Descent: done)")


func _hit_counter_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = "extends Node2D\nvar took: int = 0\nfunc take_damage(amount: int, _e: int = 0) -> void:\n\ttook += amount\n"
	script.reload()
	return script


# =============================================================================
# THE DESCENT'S REROLL (0.116.0)
# =============================================================================
# The owner: "we still need the reroll option also we can add gold to if
# needed". One free a floor, then the run's gold - 20, 40, 60...
func _test_the_descent_reroll() -> void:
	section("THE DESCENT'S REROLL - one free a floor, then gold (0.116.0)")
	const Boons := preload("res://src/world/descent/descentboons.gd")
	const RunScript := preload("res://src/world/descent/descentrun.gd")
	Boons.clear()
	var body_script := GDScript.new()
	body_script.source_code = "extends Node2D\nvar hp: int = 400\nvar max_hp: int = 400\nvar weapon_attack: int = %d\nfunc equipped_weapon_attack() -> int:\n\treturn weapon_attack\n" % ItemData.WeaponAttack.SPINNING_AXE
	body_script.reload()
	var made: Array = _descent_room_for_test(body_script)
	var room: Node2D = made[0]
	var run: Node = made[1]
	await get_tree().process_frame
	var doors: Array = run.get("doors")
	(doors[0] as Node).emit_signal("walked_in", doors[0])
	for i in 3:
		run.call("_process", RunScript.FADE_SECONDS)
	run.call("_process", RunScript.FIGHT_DELAY + 0.1)
	run.call("_process", RunScript.MARK_SECONDS + 0.05)
	_descent_kill_all(run)
	run.call("_process", 0.016)
	var hud: Node = run.get("hud")
	var button: Button = hud.get("reroll_button")
	var first: Array = (run.get("offers") as Array).duplicate()
	var free_said: bool = button != null and button.visible and button.text == "Reroll (free)" and not button.disabled
	button.pressed.emit()
	var second: Array = run.get("offers")
	var fresh: bool = second.size() == 3
	for id in second:
		fresh = fresh and not first.has(id)
	check("a pick has a Reroll beside Take: one free a floor - three new cards, none of the ones it replaced",
		free_said and fresh and int(run.get("gold")) == 0 and int(run.get("rerolls_free")) == 0, [first, second])
	hud.call("show_pick", second)
	check("  then it costs gold, and with none the button is grey", button.text == "Reroll - %d gold" % RunScript.REROLL_GOLD
		and button.disabled and not bool(run.call("reroll")))
	run.set("gold", 100)
	hud.call("show_pick", run.get("offers"))
	var paid_once: bool = bool(run.call("reroll")) and int(run.get("gold")) == 80
	var paid_twice: bool = bool(run.call("reroll")) and int(run.get("gold")) == 40
	check("  paid from the run's gold, more each time: %d, then %d" % [RunScript.REROLL_GOLD, RunScript.REROLL_GOLD * 2],
		paid_once and paid_twice, run.get("gold"))
	run.call("pick", 0)
	check("  only while a pick is on the table", not bool(run.call("can_reroll")))
	# A keeper's reroll keeps its mythic; down a floor, a free one again.
	run.set("gold", 1000)
	_descent_enter(run, "keeper", RunScript.ROOMS + 1)
	run.call("_process", RunScript.FIGHT_DELAY + 0.1)
	_descent_kill_all(run)
	run.call("_process", 0.016)
	var kept_mythic: bool = true
	for i in 4:
		run.call("reroll")
		var has: bool = false
		for id in (run.get("offers") as Array):
			has = has or Boons.rarity(str(id)) == "mythic"
		kept_mythic = kept_mythic and has
	check("a keeper's reroll still offers a mythic (Double Axe on)", kept_mythic, run.get("offers"))
	run.call("pick", 0)
	_descent_enter(run, "down")
	check("  and each floor brings a free one again, the price back to %d" % RunScript.REROLL_GOLD,
		int(run.get("rerolls_free")) == RunScript.REROLL_FREE and int(run.call("reroll_cost")) == 0
		and int(run.get("rerolls_paid")) == 0)
	room.queue_free()
	Boons.clear()
	await get_tree().process_frame
	print("  (the Descent's reroll: done)")


# =============================================================================
# A QUICKER PACE (0.117.0)
# =============================================================================
# The owner: "we need to speed up the game even more look into what we can
# advance", then "they all sound good to me lets do it". Regeneration while
# walking, a slower sprint drain, attack held on a mouse and keyboard, coins
# taken by walking over them, and a monster's bar only while it matters. (The
# story once a character is in testrunner_2's welcome section.)
func _test_a_quicker_pace() -> void:
	section("A QUICKER PACE - regen while walking, sprint, attack held, coins, bars (0.117.0)")
	var player_src: String = _code_src("res://src/characters/player.gd")
	var move_body: String = _func_body(player_src, "func _physics_process(")
	var dir_at: int = move_body.find("var direction: Vector2 = _read_move_direction()")
	var sprint_at: int = move_body.find("var wants_sprint", dir_at)
	check("walking no longer stops regeneration: nothing between reading the direction and the sprint calls _set_active()",
		dir_at > 0 and sprint_at > dir_at and not move_body.substr(dir_at, sprint_at - dir_at).contains("_set_active()"))
	var regen_body: String = _func_body(player_src, "func _tick_regen(")
	check("  sprinting is what spends stamina: none comes back while sprinting",
		regen_body.contains("if stamina < max_stamina and not _is_sprinting:"))
	var warrior: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	var mage: Node = (load("res://scene/characters/mage.tscn") as PackedScene).instantiate()
	check("the sprint drains 8 stamina a second (it was 15): a warrior's bar is 10 seconds",
		is_equal_approx(float(warrior.get("sprint_stamina_drain_per_sec")), 8.0)
		and is_equal_approx(float(mage.get("sprint_stamina_drain_per_sec")), 8.0))
	warrior.free()
	mage.free()
	var poll: String = _func_body(player_src, "func _poll_attack_pressed(")
	check("attack held keeps going with a mouse and keyboard too, where the touch pad's does",
		poll.contains("touch_attack_repeats() and touch_attack_ready()")
		and poll.contains("or left_edge or held_on) and effects_let_attack()"))
	# Coins walked over.
	const Bag := preload("res://src/world/lootbag.gd")
	var stood_in: Array = _stand_ins_for(["coppercoin", "ironsword"])
	check("a bag of coins and nothing else is taken by walking over it; gear, a pet or nothing is not",
		Bag.only_coins([{"item_id": "coppercoin", "count": 5}, {}], false)
		and not Bag.only_coins([{"item_id": "coppercoin", "count": 5}, {"item_id": "ironsword"}], false)
		and not Bag.only_coins([{"item_id": "coppercoin", "count": 5}], true)
		and not Bag.only_coins([{}, {}], false))
	_drop_stand_ins(stood_in)
	var bag_src: String = _code_src("res://src/world/lootbag.gd")
	var bag_process: String = _func_body(bag_src, "func _process(")
	var walk_over: String = _func_body(bag_src, "func _take_coins_walked_over(")
	check("  after the spawn grace, the nearest first, one at a time, once a bag, through the killer's own gate (_try_open())",
		bag_process.find("_in_spawn_grace()") < bag_process.find("_take_coins_walked_over()")
		and bag_process.find("_take_coins_walked_over()") < bag_process.find("Input.is_action_just_pressed(\"interact\")")
		and walk_over.contains("_is_nearest_candidate()") and walk_over.contains("_auto_tried = true")
		and walk_over.find("_try_open()", walk_over.find("_auto_tried = true")) != -1
		and walk_over.contains("bool(panel.get(\"visible\"))"))
	# A monster's bar only while it matters.
	var slime: Node = (load("res://scene/enemy/skeleton.tscn") as PackedScene).instantiate()
	add_child(slime)
	await get_tree().process_frame
	var bar: CanvasItem = slime.get_node_or_null("healthbar") as CanvasItem
	if bar == null:
		check("a monster to test the bar on", false)
		slime.queue_free()
		return
	var hidden_full: bool = not bar.visible
	slime.set("engaged", true)
	var shown_fighting: bool = bar.visible
	slime.set("engaged", false)
	var hidden_again: bool = not bar.visible
	slime.set("hp", int(slime.get("max_hp")) - 1)
	slime.call("_refresh_health_display")
	var shown_hurt: bool = bar.visible
	check("a monster's bar shows only while it is hurt or fighting",
		hidden_full and shown_fighting and hidden_again and shown_hurt,
		[hidden_full, shown_fighting, hidden_again, shown_hurt])
	slime.queue_free()
	await get_tree().process_frame
	print("  (a quicker pace: done)")


# =============================================================================
# THE BIG FIELD'S PROPS IN CHUNKS
# =============================================================================
# 12,000 off-screen sprites under a y-sorted parent cost 6.6-7.1 ms a frame in
# the container, and the Big Field's walls and decor are 11,948 drawn items,
# nearly all off screen. buildbigfield.gd puts each wall and prop in a chunk
# of its group for the 1,024 px square its foot stands in, and propchunks.gd
# shows only the chunks whose reach - every picture, every light at its
# brightest swell - is near the view. These hold that nothing is seen to
# change: what is in a chunk, its reach, the draw order on a tie, the
# backdrop worked out when the map was built, a jump and a zoom looked at
# at once, and a hidden wall still solid.
func _test_the_big_field_draws_only_near_the_view() -> void:
	section("THE BIG FIELD'S PROPS IN CHUNKS - drawn only near the view, sorted and solid as before")
	const Chunks := preload("res://src/world/propchunks.gd")
	const Backdrop := preload("res://src/world/mapbackdrop.gd")
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BIG_FIELD_BUILD))
	var area: Node = (load(BIG_FIELD) as PackedScene).instantiate()
	var crypt: Node = area.get_node("ysortworld/props/crypt")

	# ---- what is in a chunk --------------------------------------------------------
	var chunks: Array = []
	var loose: Array = []
	var wrong_square: Array = []
	var unsorted: Array = []
	for group_name in ["walls", "decor"]:
		for child in crypt.get_node(group_name).get_children():
			if not child.is_in_group(Chunks.GROUP) or not child.has_meta(Chunks.REACH):
				loose.append("%s/%s" % [group_name, child.name])
				continue
			chunks.append(child)
			var holder: Node2D = child as Node2D
			if not holder.y_sort_enabled or holder.position != Vector2.ZERO:
				unsorted.append("%s/%s" % [group_name, child.name])
			for piece in child.get_children():
				var at: Vector2 = (piece as Node2D).position
				var square: String = "c%d_%d" % [floori(at.x / Chunks.CHUNK), floori(at.y / Chunks.CHUNK)]
				if square != str(child.name):
					wrong_square.append("%s in %s" % [piece.name, child.name])
	var walls: Array = _crypt_pieces(crypt.get_node("walls"))
	var decor: Array = _crypt_pieces(crypt.get_node("decor"))
	check("the Big Field's %d walls and %d props are in %d chunks of %d px, each in its own square's"
		% [walls.size(), decor.size(), chunks.size(), Chunks.CHUNK],
		loose.is_empty() and wrong_square.is_empty() and chunks.size() >= 20
		and walls.size() == (plan["walls"] as Array).size() and decor.size() == (plan["props"] as Array).size(),
		[loose.slice(0, 3), wrong_square.slice(0, 3), chunks.size(), walls.size(), decor.size()])
	check("  each chunk y-sorted, at the origin: its pieces sort with the player and the monsters as before",
		unsorted.is_empty(), unsorted.slice(0, 4))
	var doors: Array = crypt.get_node("doors").get_children()
	check("  the doors are not in chunks: a door's path is its name on the wire",
		doors.size() == BIG_FIELD_DOORS and doors.all(func(d): return str(d.scene_file_path) == "res://scene/crypt/door.tscn"),
		doors.map(func(d): return d.name))

	# ---- its reach: everything it can draw ---------------------------------------
	# Worked out here on its own, not with reach_of(): each picture from its
	# texture, and each light at the most its flicker can swell it.
	var outside: Array = []
	var unknown: Array = []
	var stale: Array = []
	var lights: int = 0
	for chunk in chunks:
		var reach: Rect2 = chunk.get_meta(Chunks.REACH)
		if not reach.is_equal_approx(_reach_now(chunk)):
			stale.append(chunk.name)
		for piece in chunk.get_children():
			for node in [piece] + piece.find_children("*", "", true, false):
				var item := node as CanvasItem
				if item == null:
					continue
				var xf: Transform2D = _area_xform(item, area)
				var drawn := Rect2()
				if item is Sprite2D:
					var sprite := item as Sprite2D
					var size: Vector2 = sprite.texture.get_size()
					if sprite.region_enabled:
						size = sprite.region_rect.size
					size /= Vector2(sprite.hframes, sprite.vframes)
					var corner: Vector2 = sprite.offset - (size / 2.0 if sprite.centered else Vector2.ZERO)
					drawn = xf * Rect2(corner, size)
				elif item is PointLight2D:
					var light := item as PointLight2D
					lights += 1
					var most: float = 1.0
					if "reach_response" in light:
						most += (float(light.get("swell_amount")) + float(light.get("flicker_amount"))) * float(light.get("reach_response"))
					var across: Vector2 = light.texture.get_size() * light.texture_scale * most
					drawn = xf * Rect2(light.offset - across / 2.0, across)
				elif Chunks.draws_nothing(item):
					continue
				else:
					unknown.append("%s/%s" % [chunk.name, item.name])
					continue
				if not reach.grow(0.01).encloses(drawn):
					outside.append("%s/%s" % [chunk.name, item.name])
	check("every picture and every light (%d, at its brightest swell) is inside its chunk's reach" % lights,
		outside.is_empty() and lights > 30, outside.slice(0, 4))
	check("  nothing in a chunk draws what the reach does not measure (only pictures and lights)",
		unknown.is_empty(), unknown.slice(0, 4))
	check("  each chunk's reach is what PropChunks.reach_of() works out today - a piece changed size, rebuild the map",
		stale.is_empty(), stale.slice(0, 4))

	# ---- the order on a tie --------------------------------------------------------
	# Pieces of a group at the same y, drawn over each other, are drawn in the
	# order of the group's children: the plan's order, as before the chunks.
	var flipped: Array = []
	var ties: int = 0
	for pair in [[walls, plan["walls"]], [decor, plan["props"]]]:
		var plan_at: Dictionary = {}
		var rows: Array = pair[1]
		for i in rows.size():
			plan_at["%s@%s" % [rows[i][0], Vector2(float(rows[i][1]), float(rows[i][2]))]] = i
		var by_y: Dictionary = {}
		var pieces: Array = pair[0]
		for k in pieces.size():
			var at: Vector2 = (pieces[k] as Node2D).position
			if not by_y.has(at.y):
				by_y[at.y] = []
			(by_y[at.y] as Array).append(k)
		for y in by_y:
			var same: Array = by_y[y]
			for m in same.size():
				for n in range(m + 1, same.size()):
					var p: Node2D = pieces[same[m]]
					var q: Node2D = pieces[same[n]]
					if not Chunks.reach_of(p).intersects(Chunks.reach_of(q)):
						continue
					ties += 1
					var pk: String = "%s@%s" % [str(p.scene_file_path).get_file().get_basename(), p.position]
					var qk: String = "%s@%s" % [str(q.scene_file_path).get_file().get_basename(), q.position]
					if int(plan_at.get(pk, -1)) > int(plan_at.get(qk, -1)):
						flipped.append("%s / %s" % [pk, qk])
	check("pieces at one y drawn over each other (%d pairs) keep the plan's order: a tie draws as before" % ties,
		flipped.is_empty(), flipped.slice(0, 4))

	# ---- the backdrop, worked out when the map was built ---------------------------
	var kept: Array = area.get_meta(Backdrop.BUILT_COVER, [])
	var now: Array[Rect2] = Backdrop.cover(area)
	var same_cover: bool = kept.size() == now.size() and not kept.is_empty()
	for i in mini(kept.size(), now.size()):
		same_cover = same_cover and (kept[i] as Rect2).is_equal_approx(now[i])
	check("the backdrop's %d rectangles were worked out when the map was built, and are what cover() works out now"
		% kept.size(), same_cover, [kept.size(), now.size()])

	# ---- in the tree: shown near the view, a jump and a zoom at once ---------------
	# The props alone, in a y-sorted world of the suite's own, with a camera.
	var world := Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	var props: Node = area.get_node("ysortworld/props")
	props.get_parent().remove_child(props)
	props.owner = null
	world.add_child(props)
	area.free()
	var bare := Node2D.new()
	add_child(bare)
	check("an area with no chunks gets no helper", Chunks.add_to(bare) == null)
	bare.free()
	var kept_canvas: Transform2D = get_viewport().canvas_transform
	# The zoom is the Camera view setting's, as in the game: 3x to start.
	var zoom_was: Variant = Settings.get_value("camera_zoom")
	Settings.set_value("camera_zoom", 3.0)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	var arrival := Vector2(float(plan["arrival"][0]), float(plan["arrival"][1]))
	var ladder := Vector2(float(plan["ladder"][0]), float(plan["ladder"][1]))
	_aim(camera, arrival)
	var helper: Node = Chunks.add_to(world)
	check("a scene with chunks gets the helper, every chunk in its care", helper != null
		and int(helper.call("chunk_count")) == chunks.size(), helper.call("chunk_count") if helper else null)
	if helper == null:
		camera.free()
		world.free()
		get_viewport().canvas_transform = kept_canvas
		Settings.set_value("camera_zoom", zoom_was)
		return
	check("  and it looks again just before every frame is drawn, after every timer, tween and deferred call",
		RenderingServer.frame_pre_draw.is_connected(Callable(helper, "_on_pre_draw")))
	var in_view_first: Array = _chunks_wrong(helper, false)
	var first_hides: int = chunks.size() - int(helper.call("shown"))
	var frames: int = await _settle(helper)
	var near_arrival: Array = _chunks_wrong(helper, true)
	var shown_arrival: int = int(helper.call("shown"))
	check("at the arrival (zoom 3): every chunk whose reach touches the view is shown, every far one hidden - %d of %d shown"
		% [shown_arrival, chunks.size()], in_view_first.is_empty() and near_arrival.is_empty() and shown_arrival * 4 < chunks.size(),
		[in_view_first.slice(0, 2), near_arrival.slice(0, 4)])
	check("  the far ones hidden %d a look, over %d frames - never the whole map's toggles in one" % [Chunks.HIDES_PER_LOOK, frames],
		first_hides <= Chunks.HIDES_PER_LOOK and frames >= 2 and frames < 40, [first_hides, frames])

	# A jump across the map: the next look sees it, without waiting its turn.
	_aim(camera, ladder)
	var looked: bool = bool(helper.call("refresh"))
	var wrong_after_jump: Array = _chunks_wrong(helper, false)
	await _settle(helper)
	var wrong_settled: Array = _chunks_wrong(helper, true)
	check("a jump to the ladder is looked at the next time it asks - its chunks shown in that look, the arrival's hidden after",
		looked and wrong_after_jump.is_empty() and wrong_settled.is_empty(), [wrong_after_jump.slice(0, 4), wrong_settled.slice(0, 2)])
	_aim(camera, arrival)
	await get_tree().process_frame
	var wrong_after_frame: Array = _chunks_wrong(helper, false)
	check("  and in one frame of its own, back at the arrival", wrong_after_frame.is_empty(), wrong_after_frame.slice(0, 4))
	await _settle(helper)
	_aim(camera, arrival + Vector2(40, 0))
	check("  a step of 40 px is not looked at - four comparisons a frame", not bool(helper.call("refresh")))

	# The Camera view setting all the way out (1x, the widest view): more
	# chunks, in the frame.
	# (The camera is on the physics clock - physics interpolation - so its
	# view moves over its next ticks, each frame's look after it.)
	Settings.set_value("camera_zoom", 1.0)
	for i in 3:
		await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var wrong_wide: Array = _chunks_wrong(helper, false)
	await _settle(helper)
	wrong_wide.append_array(_chunks_wrong(helper, true))
	var shown_wide: int = int(helper.call("shown"))
	check("zoomed all the way out (1x, %s): the wider view's chunks are shown in the frame - %d of %d"
		% [helper.call("view_rect").size, shown_wide, chunks.size()],
		wrong_wide.is_empty() and (helper.call("view_rect") as Rect2).size.x > 1000.0
		and shown_wide >= shown_arrival and shown_wide < chunks.size(), wrong_wide.slice(0, 4))

	# ---- a hidden wall is still a wall -------------------------------------------
	var hidden_wall: Node2D = null
	for chunk in chunks:
		if is_instance_valid(chunk) and not (chunk as CanvasItem).visible and chunk.get_parent().name == &"walls":
			hidden_wall = chunk.get_child(0) as Node2D
			break
	var blocked: bool = false
	if hidden_wall != null:
		await get_tree().physics_frame
		await get_tree().physics_frame
		var body: StaticBody2D = hidden_wall.get_node_or_null("body") as StaticBody2D
		var shape: CollisionShape2D = body.get_child(0) as CollisionShape2D if body != null else null
		if shape != null:
			var query := PhysicsPointQueryParameters2D.new()
			query.position = shape.global_position
			query.collision_mask = 1
			for hit in get_viewport().world_2d.direct_space_state.intersect_point(query, 8):
				blocked = blocked or hit.get("collider") == body
	check("a wall in a hidden chunk still blocks: its body is in the physics world where it stands",
		hidden_wall != null and not hidden_wall.is_visible_in_tree() and blocked, [hidden_wall, blocked])

	# ---- off shows everything ------------------------------------------------------
	helper.set("enabled", false)
	var all_shown: int = int(helper.call("shown"))
	helper.set("enabled", true)
	check("switched off it shows every chunk; on, it hides the far ones again",
		all_shown == chunks.size() and int(helper.call("shown")) < chunks.size(), [all_shown, helper.call("shown")])
	check("AreaRegistry gives every area one, as it does the sleeper",
		_code_src("res://src/systems/arearegistry.gd").contains("PropChunks.add_to(scene)"))

	camera.free()
	world.free()
	get_viewport().canvas_transform = kept_canvas
	Settings.set_value("camera_zoom", zoom_was)
	await get_tree().process_frame
	print("  (the Big Field's props in chunks: done)")


func _reach_now(chunk: Node) -> Rect2:
	const Chunks := preload("res://src/world/propchunks.gd")
	var out := Rect2()
	var first: bool = true
	for piece in chunk.get_children():
		var drawn: Rect2 = Chunks.reach_of(piece as Node2D)
		out = drawn if first else out.merge(drawn)
		first = false
	return out


func _aim(camera: Camera2D, at: Vector2) -> void:
	"""Puts the camera on `at` now, as AreaRegistry.place_player() and
	Player.snap_camera() put a player's."""
	camera.global_position = at
	camera.reset_physics_interpolation()
	camera.reset_smoothing()
	camera.force_update_scroll()


func _settle(helper: Node) -> int:
	"""Frames until a helper has no far chunks waiting to be hidden."""
	var frames: int = 0
	while bool(helper.get("_hides_waiting")) and frames < 60:
		await get_tree().process_frame
		frames += 1
	return frames


func _chunks_wrong(helper: Node, settled: bool) -> Array:
	"""The chunks a helper has wrong for the view: hidden with the reach
	touching the view itself - and, once `settled`, shown with it past
	HIDE_MARGIN."""
	const Chunks := preload("res://src/world/propchunks.gd")
	var view: Rect2 = helper.call("view_rect")
	var wrong: Array = []
	var chunks: Array = helper.get("_chunks")
	var reaches: Array = helper.get("_reaches")
	for i in chunks.size():
		var chunk: CanvasItem = chunks[i]
		var reach: Rect2 = reaches[i]
		if reach.intersects(view, true) and not chunk.visible:
			wrong.append("%s hidden in view" % chunk.name)
		elif settled and not reach.intersects(view.grow(Chunks.HIDE_MARGIN), true) and chunk.visible:
			wrong.append("%s shown far off" % chunk.name)
	return wrong


# =============================================================================
# THE SWARM'S STEP: CHEAPER, AND THE SAME TO THE BIT (0.117.0)
# =============================================================================
# The owner approved making the Endless's swarm cheaper "with no visible change
# and no change to how the slimes behave". A step of 3,000 was 8.3 ms in the
# container: the sort, arrays and dictionaries made and thrown away each step,
# the corridor's rect grown for every slime, the clock read for every slime.
# The step, the buffer and the stand-ins as they were are kept here as text
# (_SWARM_WAS, only their docstrings left out and the clock read through
# _sway_msec()), built on the new script with the clock stopped, and both are
# stepped side by side on one seeded crowd - a pack against the back wall, the
# rest from the edges, a corridor, a party member, deaths, births between a step
# and a write, attacks out on the floor - and every number compared to the bit.
const _SWARM_CLOCK := "extends \"res://src/world/endless/swarm.gd\"\n\nvar clock_msec: int = 0\n\n\nfunc _sway_msec() -> int:\n\treturn clock_msec\n\n\n"


func _test_the_swarm_steps_the_same_for_less() -> void:
	section("THE SWARM'S STEP - cheaper, and the same to the bit as before (0.117.0)")
	var was_script := GDScript.new()
	was_script.source_code = _SWARM_CLOCK + _SWARM_WAS
	var was_ok: bool = was_script.reload() == OK and was_script.can_instantiate()
	var now_script := GDScript.new()
	now_script.source_code = _SWARM_CLOCK
	var now_ok: bool = now_script.reload() == OK and now_script.can_instantiate()
	check("the swarm as it was and as it is, each on a stopped clock", was_ok and now_ok, [was_ok, now_ok])
	if not (was_ok and now_ok):
		return
	var proxies_near: int = int((load("res://src/world/endless/swarm.gd") as GDScript).PROXIES)
	var o := Vector2(-64000, -64000)
	var arena := Rect2(o + Vector2(24, 34), Vector2(1488, 1334))
	var corridor := Rect2(o + Vector2(690, 1030), Vector2(160, 380))
	var me := Node2D.new()
	me.add_to_group(&"player")
	add_child(me)
	var pair: Array = []
	for script in [was_script, now_script]:
		var swarm: Node2D = script.new()
		swarm.set("arena", arena)
		(swarm.get("keep_out") as Array).append(corridor)
		swarm.call("draw_in_front_of", arena.position.y - 6.0)
		add_child(swarm)
		swarm.set_process(false)
		swarm.set_physics_process(false)
		pair.append(swarm)
	await get_tree().process_frame
	var was: Node2D = pair[0]
	var start := o + Vector2(760, 140)
	me.global_position = start
	# 600 round the player against the back wall, 1,800 more from the edges.
	var records := PackedInt32Array()
	for k in 600:
		var turn: float = TAU * float(k) / 600.0
		var spot: Vector2 = start + Vector2(cos(turn), sin(turn)) * (20.0 + float(k % 9) * 13.0)
		records.append_array(PackedInt32Array([k, 1, 40, roundi(spot.x), roundi(spot.y), k % 7]))
	for swarm in pair:
		swarm.call("import_alive", records)
		var slots: PackedInt32Array = swarm.call("take_slots", 1800)
		swarm.call("spawn_batch", 2, 777, slots, PackedVector2Array([start]), 30.0, 1)
	var steps: int = 100
	var spent := PackedInt64Array([0, 0, 0, 0, 0, 0])
	var differ: Array = []
	var differing: int = 0
	var most_near: int = 0
	var most_front: int = 0
	var saw_dying: bool = false
	var saw_twice: bool = false
	var saw_focus: bool = false
	var focus: Array = []
	for k in steps:
		var at: Vector2 = o + Vector2(760.0 + 520.0 * sin(float(k) * 0.045), 140.0 + 1000.0 * (0.5 - 0.5 * cos(float(k) * 0.03)))
		me.global_position = at
		var chasing: bool = k % 23 != 5
		if k == 35:
			for f in 3:
				var attack := Node2D.new()
				attack.add_to_group(&"swarm_focus")
				add_child(attack)
				focus.append(attack)
		if k >= 35 and k < 70:
			for f in focus.size():
				(focus[f] as Node2D).global_position = at + Vector2(120.0 + 40.0 * f, -60.0 + float(k - 35) * 4.0)
		if k == 70:
			for attack in focus:
				(attack as Node).queue_free()
			focus.clear()
		for which in 2:
			var swarm: Node2D = pair[which]
			swarm.set("clock_msec", 1000 + 50 * k)
			if k >= 20 and k < 50:
				swarm.set("_others_now", PackedVector2Array([swarm.call("floor_point", o + Vector2(400, 700))]))
			else:
				swarm.set("_others_now", PackedVector2Array())
			if k == 10 or k == 60:
				for i in range(0, mini(800, int(swarm.get("_high"))), 3):
					swarm.call("hurt", i, 10000.0)
			if k % 7 == 3:
				for i in range(1, mini(900, int(swarm.get("_high"))), 11):
					swarm.call("hurt", i, 3.0)
			var target: Vector2 = swarm.call("floor_point", at)
			var t0: int = Time.get_ticks_usec()
			swarm.call("_step", target, chasing)
			var t1: int = Time.get_ticks_usec()
			# Born again between a step and a write: twice in the order.
			if (k >= 15 and k < 30) or (k >= 65 and k < 80):
				var slots: PackedInt32Array = swarm.call("take_slots", 25)
				swarm.call("spawn_batch", 100 + k, 31 * k, slots, PackedVector2Array([at]), 30.0, k % 7)
			if which == 0:
				var listed := {}
				for i in (swarm.get("_order") as PackedInt32Array):
					saw_twice = saw_twice or listed.has(i)
					listed[i] = true
			var t2: int = Time.get_ticks_usec()
			swarm.call("_write_buffer")
			var t3: int = Time.get_ticks_usec()
			swarm.call("_place_proxies")
			var t4: int = Time.get_ticks_usec()
			spent[which * 3] += t1 - t0
			spent[which * 3 + 1] += t3 - t2
			spent[which * 3 + 2] += t4 - t3
		var apart: Array = _swarm_twins_differ(pair[0], pair[1])
		if not apart.is_empty():
			differing += 1
			if differ.is_empty():
				differ = [k, apart]
		most_near = maxi(most_near, (was.get("_near") as PackedInt32Array).size())
		most_front = maxi(most_front, (was.get("_front") as MultiMeshInstance2D).multimesh.visible_instance_count)
		saw_dying = saw_dying or (was.get("state") as PackedByteArray).has(2)
		var held: PackedInt32Array = was.get("_held")
		for p in range(proxies_near, held.size()):
			saw_focus = saw_focus or held[p] >= 0
		await get_tree().process_frame
	var per: Callable = func(us: int) -> float: return float(us) / 1000.0 / float(steps)
	check("%d steps of %d slimes, side by side: every position, heading, facing, health, the draw order, both buffers and every stand-in the same to the bit (%d steps differed)"
		% [steps, int(was.get("alive")), differing], differing == 0, differ)
	check("  through every way a step goes: the crowd round you (%d near), the front layer (%d), dying, born again between a step and a write, attacks out on the floor"
		% [most_near, most_front], most_near > 100 and most_front > 0 and saw_dying and saw_twice and saw_focus,
		[most_near, most_front, saw_dying, saw_twice, saw_focus])
	print("  the swarm a step, was -> now: _step %.2f -> %.2f ms, _write_buffer %.2f -> %.2f ms, _place_proxies %.2f -> %.2f ms" % [
		per.call(spent[0]), per.call(spent[3]), per.call(spent[1]), per.call(spent[4]), per.call(spent[2]), per.call(spent[5])])
	# NOTHING MADE IN A STEP: no array or dictionary built in the functions a
	# step runs (the engine's list of attacks, asked only with one out, aside).
	var src: String = _code_src("res://src/world/endless/swarm.gd")
	var makes := RegEx.new()
	makes.compile("Packed[A-Za-z0-9]+Array\\(|\\{\\s*\\}|\\[\\s*\\]|\\bDictionary\\(|\\bArray\\(|\\.duplicate\\(|\\.slice\\(")
	var making: Array = []
	for header in ["func _process(", "func _step(", "func _make_room(", "func _write_buffer(", "func _sort_order(",
			"func _place_proxies(", "func _focus_find(", "func _gather_foci(", "func _near_focus(", "func _move_proxies("]:
		var fn_body: String = _func_body(src, header)
		if fn_body == "" or makes.search(fn_body) != null:
			making.append(header)
	check("  and a step makes no array or dictionary to throw away", making.is_empty(), making)
	for swarm in pair:
		(swarm as Node).queue_free()
	me.queue_free()
	await get_tree().process_frame
	print("  the swarm's step: the same, for less")


func _swarm_twins_differ(a: Node, b: Node) -> Array:
	"""Where two swarms differ, to the bit (to_byte_array(), so even -0 and 0
	are told apart): every slime's numbers, the order, the stand-ins'
	choice, what each buffer draws and where each stand-in stands."""
	var out: Array = []
	for field in ["px", "py", "bx", "by", "vx", "vy", "hp", "timer", "flash", "phase", "hue", "_rx", "_ry", "_sum_x", "_sum_y"]:
		if (a.get(field) as PackedFloat32Array).to_byte_array() != (b.get(field) as PackedFloat32Array).to_byte_array():
			out.append(field)
	for field in ["facing", "state", "elem"]:
		if (a.get(field) as PackedByteArray) != (b.get(field) as PackedByteArray):
			out.append(field)
	for field in ["gen", "_free", "_order", "_held", "_grid"]:
		if (a.get(field) as PackedInt32Array) != (b.get(field) as PackedInt32Array):
			out.append(field)
	for field in ["alive", "slain", "my_slain", "batch", "_high", "_touching"]:
		if int(a.get(field)) != int(b.get(field)):
			out.append(field)
	for mesh in ["_mesh", "_front"]:
		var drawn: int = (a.get(mesh) as MultiMeshInstance2D).multimesh.visible_instance_count
		if drawn != (b.get(mesh) as MultiMeshInstance2D).multimesh.visible_instance_count:
			out.append(mesh)
		var buffer: String = "_buffer" if mesh == "_mesh" else "_front_buffer"
		if (a.get(buffer) as PackedFloat32Array).slice(0, drawn * 16).to_byte_array() \
				!= (b.get(buffer) as PackedFloat32Array).slice(0, drawn * 16).to_byte_array():
			out.append(buffer)
	var stand_a: Array = a.get("_proxies")
	var stand_b: Array = b.get("_proxies")
	for p in stand_a.size():
		var one: Node2D = stand_a[p]
		var two: Node2D = stand_b[p]
		if int(one.get("slot")) != int(two.get("slot")) or one.global_position != two.global_position or one.visible != two.visible:
			out.append("stand-in %d" % p)
			break
	return out


# The swarm's step, buffer and stand-ins before 0.117.0, word for word but for
# their docstrings, the clock (_sway_msec(), once a slime as it was) and the
# names of the helpers (_was_...), so nothing here overrides the new ones.
const _SWARM_WAS := """
func _step(target: Vector2, chasing: bool) -> void:
	_grid.fill(0)
	_sum_x.fill(0.0)
	_sum_y.fill(0.0)
	var ox: float = arena.position.x
	var oy: float = arena.position.y
	var gw: int = _gw
	var gh: int = _gh
	# The near ones' hash: ROOM-sized cells over the square round the player.
	for i in _near:
		_rx[i] = 0.0
		_ry[i] = 0.0
	var near := PackedInt32Array()
	var side: int = int(ceil(2.0 * ROOM_REACH / ROOM)) + 1
	_room_head.resize(side * side)
	_room_head.fill(-1)
	var hx: float = target.x - ROOM_REACH
	var hy: float = target.y - ROOM_REACH
	var reach2: float = ROOM_REACH * ROOM_REACH
	for i in _high:
		if state[i] == 1:
			var gx: int = clampi(int((px[i] - ox) / CELL), 0, gw - 1)
			var gy: int = clampi(int((py[i] - oy) / CELL), 0, gh - 1)
			var cell_at: int = gy * gw + gx
			_grid[cell_at] += 1
			_sum_x[cell_at] += px[i]
			_sum_y[cell_at] += py[i]
			var nx0: float = px[i] - target.x
			var ny0: float = py[i] - target.y
			if nx0 * nx0 + ny0 * ny0 <= reach2:
				var room_at: int = clampi(int((py[i] - hy) / ROOM), 0, side - 1) * side + clampi(int((px[i] - hx) / ROOM), 0, side - 1)
				_room_next[i] = _room_head[room_at]
				_room_head[room_at] = i
				near.append(i)
	_near = near
	_was_make_room(hx, hy, side)
	var left: float = arena.position.x + SIDE_EDGE
	var right: float = arena.end.x - SIDE_EDGE
	var top: float = arena.position.y + EDGE
	var bottom: float = arena.end.y - EDGE
	var stride: float = speed * STEP
	var push: float = PUSH * STEP
	var spread: float = SPREAD * STEP
	var touching: int = 0
	var tx: float = target.x
	var ty: float = target.y
	var others_now: PackedVector2Array = _others_now
	var n_others: int = others_now.size()
	for i in _high:
		var s: int = state[i]
		if s == 0:
			continue
		if flash[i] > 0.0:
			flash[i] = maxf(0.0, flash[i] - STEP)
		if s == 2:
			timer[i] += STEP
			bx[i] = px[i]
			by[i] = py[i]
			if timer[i] >= DYING_SECONDS:
				state[i] = 0
				_free.append(i)
			continue
		var x: float = px[i]
		var y: float = py[i]
		bx[i] = x
		by[i] = y
		# THE NEAREST PLAYER: this game's, or one of the party's others.
		var dx: float = tx - x
		var dy: float = ty - y
		var best: float = dx * dx + dy * dy if chasing else INF
		var mine: bool = chasing
		if n_others > 0:
			for o in n_others:
				var odx: float = others_now[o].x - x
				var ody: float = others_now[o].y - y
				var od2: float = odx * odx + ody * ody
				if od2 < best:
					best = od2
					dx = odx
					dy = ody
					mine = false
		var d: float = sqrt(best) if best < INF else 0.0
		var mx: float = 0.0
		var my: float = 0.0
		var gx2: int = clampi(int((x - ox) / CELL), 0, gw - 1)
		var gy2: int = clampi(int((y - oy) / CELL), 0, gh - 1)
		var here: int = _grid[gy2 * gw + gx2]
		var against: bool = false
		if best < INF:
			# Only this game's player is hurt here (each by their own copy):
			# by every slime within BITE of them, the second rank too.
			if mine and d <= BITE:
				touching += 1
			if d <= TOUCH:
				against = true
			elif d > 0.001:
				# A little sideways wander, its own and slow, so a crowd does
				# not march in ruled lines.
				var wobble: float = sin(phase[i] * 40.0 + float(_sway_msec()) * WANDER_RATE) * WANDER
				var nx: float = dx / d
				var ny: float = dy / d
				# IN A CROWD IT WAITS: past CROWD_ROOM in its cell it presses
				# on less, and not at all from CROWD_ROOM + 2 - so a horde
				# stands in ranks round the player instead of all of it
				# squeezing onto the same few px.
				var press: float = clampf(float(CROWD_ROOM + 2 - here) / 2.0, 0.0, 1.0)
				mx = (nx - ny * wobble) * stride * press
				my = (ny + nx * wobble) * stride * press
		if here > 1:
			var l: int = _grid[gy2 * gw + gx2 - 1] if gx2 > 0 else here
			var r: int = _grid[gy2 * gw + gx2 + 1] if gx2 < gw - 1 else here
			var u: int = _grid[(gy2 - 1) * gw + gx2] if gy2 > 0 else here
			var dn: int = _grid[(gy2 + 1) * gw + gx2] if gy2 < gh - 1 else here
			# Against the player it is shoved half as hard: the ring round
			# them settles instead of churning.
			var shove: float = push * (0.5 if against else 1.0)
			mx += float(l - r) * shove
			my += float(u - dn) * shove
			# Away from the middle of the others in its cell; one standing on
			# that very spot goes its own way, the same way every step.
			var cell_here: int = gy2 * gw + gx2
			var ax: float = x - _sum_x[cell_here] / float(here)
			var ay: float = y - _sum_y[cell_here] / float(here)
			var apart: float = sqrt(ax * ax + ay * ay)
			if apart < 0.05:
				ax = cos(phase[i] * TAU)
				ay = sin(phase[i] * TAU)
				apart = 1.0
			mx += ax / apart * spread * float(here - 1)
			my += ay / apart * spread * float(here - 1)
		# Its own room, if it is near (_was_make_room()).
		mx += _rx[i] * ROOM_PUSH * STEP
		my += _ry[i] * ROOM_PUSH * STEP
		# Carried from the last step, never a full turn at once - but at the
		# player it stops: carried on at a late stage's stride (up to 8.75 px a
		# step, endlessrun.gd stage_speed()) it slid through them and back.
		var steer: float = 1.0 if against else STEER
		mx = lerpf(vx[i], mx, steer)
		my = lerpf(vy[i], my, steer)
		vx[i] = mx
		vy[i] = my
		x = clampf(x + mx, left, right)
		y = clampf(y + my, top, bottom)
		for kept in keep_out:
			# Its walls' width further out at the sides (HELD_OUT_SIDES).
			var rect: Rect2 = kept.grow_individual(HELD_OUT_SIDES, 0.0, HELD_OUT_SIDES, 0.0)
			if rect.has_point(Vector2(x, y)):
				# Out the nearest side.
				# Never out a side that leaves the floor: a corridor walled
				# into the arena's foot has only three.
				var to_left: float = x - rect.position.x if rect.position.x - 0.5 >= left else INF
				var to_right: float = rect.end.x - x if rect.end.x + 0.5 <= right else INF
				var to_top: float = y - rect.position.y if rect.position.y - 0.5 >= top else INF
				var to_bottom: float = rect.end.y - y if rect.end.y + 0.5 <= bottom else INF
				var least: float = minf(minf(to_left, to_right), minf(to_top, to_bottom))
				if least == to_top:
					y = rect.position.y - 0.5
				elif least == to_left:
					x = rect.position.x - 0.5
				elif least == to_right:
					x = rect.end.x + 0.5
				else:
					y = rect.end.y + 0.5
		if absf(mx) > 0.2 or absf(my) > 0.2:
			var sideways: bool = facing[i] <= 1
			if sideways and absf(my) > absf(mx) * FACE_LEAD:
				sideways = false
			elif not sideways and absf(mx) > absf(my) * FACE_LEAD:
				sideways = true
			if sideways:
				facing[i] = 0 if mx > 0.0 else 1
			else:
				facing[i] = 2 if my > 0.0 else 3
		px[i] = x
		py[i] = y
	_touching = touching


func _was_make_room(hx: float, hy: float, side: int) -> void:
	var room2: float = ROOM * ROOM
	for i in _near:
		var x: float = px[i]
		var y: float = py[i]
		var cx: int = clampi(int((x - hx) / ROOM), 0, side - 1)
		var cy: int = clampi(int((y - hy) / ROOM), 0, side - 1)
		var sx: float = 0.0
		var sy: float = 0.0
		for row in range(maxi(0, cy - 1), mini(side, cy + 2)):
			for col in range(maxi(0, cx - 1), mini(side, cx + 2)):
				var j: int = _room_head[row * side + col]
				while j >= 0:
					if j != i:
						var dx: float = x - px[j]
						var dy: float = y - py[j]
						var d2: float = dx * dx + dy * dy
						if d2 < room2:
							var d: float = sqrt(d2)
							if d < 0.01:
								var way: float = (phase[i] - phase[j]) * TAU
								dx = cos(way)
								dy = sin(way)
								d = 1.0
							var inside: float = (ROOM - minf(d, ROOM)) / ROOM
							sx += dx / d * inside
							sy += dy / d * inside
					j = _room_next[j]
		_rx[i] = clampf(sx, -1.5, 1.5)
		_ry[i] = clampf(sy, -1.5, 1.5)


func _write_buffer() -> void:
	_was_sort_order()
	# Back to front, so the ones in front of the back wall (above front_line)
	# are the first of the order: those go to _front, a pixel past the wall's
	# foot, and the rest to _mesh.
	var back: PackedFloat32Array = _buffer
	var front: PackedFloat32Array = _front_buffer
	var in_front: int = 0
	var k: int = 0
	for i in _order:
		var s: int = state[i]
		var to_front: bool = _front != null and py[i] < front_line
		var buf: PackedFloat32Array = front if to_front else back
		var at: int = (in_front if to_front else k) * 16
		buf[at] = 1.0
		buf[at + 1] = 0.0
		buf[at + 2] = 0.0
		buf[at + 3] = px[i]
		buf[at + 4] = 0.0
		buf[at + 5] = 1.0
		buf[at + 6] = 0.0
		buf[at + 7] = py[i] - _front_y if to_front else py[i]
		buf[at + 8] = flash[i] / FLASH_SECONDS if s == 1 else 0.0
		buf[at + 9] = clampf(timer[i] / DYING_SECONDS, 0.01, 1.0) if s == 2 else 0.0
		buf[at + 10] = 0.0
		buf[at + 11] = 1.0
		buf[at + 12] = bx[i] - px[i]
		buf[at + 13] = by[i] - py[i]
		buf[at + 14] = float(facing[i]) + phase[i] * 0.99
		buf[at + 15] = hue[i]
		if to_front:
			in_front += 1
		else:
			k += 1
	var multi: MultiMesh = _mesh.multimesh
	# The whole buffer, always: MultiMesh takes one of exactly its size. Past
	# the order's end it holds old cells, and visible_instance_count draws
	# none of them.
	multi.buffer = back
	multi.visible_instance_count = k
	if _front != null:
		_front.multimesh.buffer = front
		_front.multimesh.visible_instance_count = in_front


func _was_sort_order() -> void:
	var order: PackedInt32Array = _order
	_order = PackedInt32Array()
	# Once each: a slot freed and born again between two writes is in the
	# order twice.
	var seen := PackedByteArray()
	seen.resize(_high)
	var kept: int = 0
	for i in order:
		if state[i] != 0 and seen[i] == 0:
			seen[i] = 1
			order[kept] = i
			kept += 1
	order.resize(kept)
	for k in range(1, kept):
		var i: int = order[k]
		var at: float = py[i]
		var j: int = k - 1
		while j >= 0 and py[order[j]] > at:
			order[j + 1] = order[j]
			j -= 1
		order[j + 1] = i
	_order = order


func _place_proxies() -> void:
	var player: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null or alive == 0:
		_was_park_proxies()
		return
	var at: Vector2 = player.global_position
	var reach2: float = PROXY_REACH * PROXY_REACH
	if _held.size() != _proxies.size():
		_held.resize(_proxies.size())
		_held.fill(-1)
	var foci: Array = _was_focus_points()
	var taken := {}
	var empty: int = 0
	var empty_focus: int = 0
	for p in _held.size():
		var i: int = _held[p]
		if i >= 0 and state[i] == 1 and not taken.has(i):
			if p < PROXIES:
				var hx: float = px[i] - at.x
				var hy: float = py[i] - at.y
				if hx * hx + hy * hy <= reach2:
					taken[i] = true
					continue
			elif _was_near_focus(i, foci) <= 1.0:
				taken[i] = true
				continue
		_held[p] = -1
		if p < PROXIES:
			empty += 1
		else:
			empty_focus += 1
	if empty > 0:
		var bands: Array = [[], [], [], [], [], []]
		var band_size: float = PROXY_REACH / float(bands.size())
		for i in _high:
			if state[i] != 1 or taken.has(i):
				continue
			var dx: float = px[i] - at.x
			var dy: float = py[i] - at.y
			var d2: float = dx * dx + dy * dy
			if d2 > reach2:
				continue
			(bands[mini(bands.size() - 1, int(sqrt(d2) / band_size))] as Array).append(i)
		var p: int = 0
		for band in bands:
			for i in band:
				while p < PROXIES and _held[p] >= 0:
					p += 1
				if p >= PROXIES:
					break
				_held[p] = i
				taken[i] = true
	if empty_focus > 0 and not foci.is_empty():
		# Nearest the middle of an attack first, by thirds of its reach - found
		# through the cells round each attack (_was_focus_shares()), not by asking
		# every slime about every attack: a warrior's waves and orbs are
		# dozens of attacks at once (0.96.0).
		var shares: Dictionary = _was_focus_shares(foci, taken)
		var near: Array = [[], [], []]
		for i in shares:
			(near[mini(2, int(float(shares[i]) * 3.0))] as Array).append(i)
		var q: int = PROXIES
		for band in near:
			for i in band:
				while q < _held.size() and _held[q] >= 0:
					q += 1
				if q >= _held.size():
					break
				_held[q] = i
	_was_move_proxies()


func _was_focus_shares(foci: Array, taken: Dictionary) -> Dictionary:
	var cells: int = _gw * _gh
	if _focus_head.size() != cells:
		_focus_head.resize(cells)
	_focus_head.fill(-1)
	if _focus_next.size() != MOST:
		_focus_next.resize(MOST)
	var ox: float = arena.position.x
	var oy: float = arena.position.y
	for i in _high:
		if state[i] != 1 or taken.has(i):
			continue
		var c: int = clampi(int((py[i] - oy) / CELL), 0, _gh - 1) * _gw + clampi(int((px[i] - ox) / CELL), 0, _gw - 1)
		_focus_next[i] = _focus_head[c]
		_focus_head[c] = i
	var best: Dictionary = {}
	for focus in foci:
		var fx: float = focus[0]
		var fy: float = focus[1]
		var reach: float = maxf(1.0, focus[2])
		var x0: int = clampi(int(floorf((fx - reach - ox) / CELL)), 0, _gw - 1)
		var x1: int = clampi(int(floorf((fx + reach - ox) / CELL)), 0, _gw - 1)
		var y0: int = clampi(int(floorf((fy - reach - oy) / CELL)), 0, _gh - 1)
		var y1: int = clampi(int(floorf((fy + reach - oy) / CELL)), 0, _gh - 1)
		for cy in range(y0, y1 + 1):
			for cx in range(x0, x1 + 1):
				var i: int = _focus_head[cy * _gw + cx]
				while i >= 0:
					var dx: float = px[i] - fx
					var dy: float = py[i] - fy
					var d2: float = dx * dx + dy * dy
					if d2 <= reach * reach:
						var share: float = sqrt(d2) / reach
						if share < float(best.get(i, INF)):
							best[i] = share
					i = _focus_next[i]
	return best


func _was_focus_points() -> Array:
	var out: Array = []
	if not is_inside_tree():
		return out
	for node in get_tree().get_nodes_in_group(FOCUS_GROUP):
		if not (node is Node2D) or not (node as Node2D).is_inside_tree() or (node as Node).is_queued_for_deletion():
			continue
		# Another player's attack drawn here hits nothing here (remoteattacks.gd).
		if node.get("cosmetic") == true:
			continue
		var reach: float = float(node.call("swarm_reach")) if node.has_method("swarm_reach") else FOCUS_REACH
		var spot: Vector2 = (node as Node2D).global_position
		out.append(PackedFloat32Array([spot.x, spot.y, reach + FOCUS_MARGIN]))
	return out


func _was_near_focus(i: int, foci: Array) -> float:
	var best: float = INF
	for focus in foci:
		var dx: float = px[i] - focus[0]
		var dy: float = py[i] - focus[1]
		var reach: float = maxf(1.0, focus[2])
		var d2: float = dx * dx + dy * dy
		if d2 <= reach * reach:
			best = minf(best, sqrt(d2) / reach)
	return best


func _was_move_proxies() -> void:
	var blend: float = clampf(1.0 - _step_left / STEP, 0.0, 1.0)
	for p in _proxies.size():
		var proxy: Node2D = _proxies[p]
		var i: int = _held[p] if p < _held.size() else -1
		if i >= 0 and state[i] == 1:
			proxy.call("stand_on", i, Vector2(lerpf(bx[i], px[i], blend), lerpf(by[i], py[i], blend)))
		else:
			proxy.call("stand_on", -1, Vector2.ZERO)


func _was_park_proxies() -> void:
	_held.resize(_proxies.size())
	_held.fill(-1)
	for proxy in _proxies:
		(proxy as Node2D).call("stand_on", -1, Vector2.ZERO)
"""


# =============================================================================
# THE WAYSTONES (0.118.0)
# =============================================================================
# The owner approved waystones with the speed plan, then their picture: "yes
# looks good". Seven in the Big Field, lit once explored, a pin and a row on
# the map, three seconds standing still, from town too. See waystones.gd.
func _test_the_waystones() -> void:
	section("THE WAYSTONES - seven in the Big Field, lit once found, three seconds still to travel, from town too (0.118.0)")
	const Ways := preload("res://src/world/waystones.gd")
	# ---- where they stand ---------------------------------------------------------------------
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/maps/bigfield_build.json"))
	var spawns: Array = ((JSON.parse_string(FileAccess.get_file_as_string("res://data/gamedata.json")) as Dictionary)
		["areas"]["bigfield"]["spawns"]) as Array
	var bad: Array = []
	var ids: Array = []
	for stone in Ways.STONES:
		ids.append(stone["id"])
		var at: Vector2 = stone["at"]
		var cell := Vector2i(floori(at.x / 16.0), floori(at.y / 16.0))
		var floor_ok: bool = true
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var row: String = str((plan["floor"] as Array)[cell.y + dy])
				floor_ok = floor_ok and row[cell.x + dx] == "1"
		var nearest: float = INF
		for spawn in spawns:
			nearest = minf(nearest, at.distance_to(Vector2(float(spawn["x"]), float(spawn["y"]))))
		if not floor_ok or nearest < 250.0:
			bad.append([stone["id"], floor_ok, roundi(nearest)])
	check("seven waystones, each on open floor and 250 px or more from every monster the Big Field places",
		Ways.STONES.size() == 7 and bad.is_empty() and ids.has("crossroads"), bad)
	var arrival := Vector2(1832, 2384)
	check("  the Crossroads' is lit as you arrive: within the map's reveal of the arrival",
		(Ways.stone_for("crossroads")["at"] as Vector2).distance_to(arrival) < 16.0 * WorldMap.SEEN_RADIUS - 8.0,
		(Ways.stone_for("crossroads")["at"] as Vector2).distance_to(arrival))
	check("  reached from town, the Field and the Big Field - never a minigame or a boss room",
		Ways.reachable_from("elusion") and Ways.reachable_from("field") and Ways.reachable_from("bigfield")
		and not Ways.reachable_from("endless") and not Ways.reachable_from("descent")
		and not Ways.reachable_from("bossarena"))

	# ---- placed only in the Big Field, and lit by the map --------------------------------------
	var kept_terrain: Variant = WorldMap._terrain.get("bigfield")
	var kept_seen: Variant = WorldMap._seen.get("bigfield")
	var kept_dirty: bool = WorldMap._save_dirty
	var kept_pending: bool = WorldMap._revision_pending
	var kept_cache: Dictionary = WorldMap._save_cache
	var kept_reveal: Rect2i = WorldMap.last_reveal
	WorldMap._terrain["bigfield"] = {"image": null, "origin": Vector2i.ZERO, "size": Vector2i(385, 322), "tile": Vector2i(16, 16)}
	WorldMap._seen.erase("bigfield")
	WorldMap._ensure_seen("bigfield", Vector2i(385, 322))
	var field := Node2D.new()
	field.scene_file_path = "res://scene/bigfield.tscn"
	add_child(field)
	var town := Node2D.new()
	town.scene_file_path = "res://scene/elusion.tscn"
	add_child(town)
	Ways.add_to(field)
	Ways.add_to(town)
	var stone_group: StringName = Ways.GROUP
	var stones: Array = field.get_children().filter(func(n: Node) -> bool: return n.is_in_group(stone_group))
	var chasm: Node = field.get_node_or_null("waystone_chasm")
	check("the Big Field gets its seven stones, landmarks on the map; town gets none",
		stones.size() == 7 and chasm != null and chasm.is_in_group("map_landmarks")
		and town.get_children().all(func(n: Node) -> bool: return not n.is_in_group(stone_group)),
		[stones.size(), town.get_child_count()])
	var dark: Dictionary = chasm.call("map_landmark")
	var stone_chasm: Dictionary = Ways.stone_for("chasm")
	check("  unlit until found: dark art, standing still, a grey pin that says not found",
		not chasm.call("lit") and dark.get("kind") == "waystone" and not bool(dark.get("lit"))
		and dark.get("waystone") == "chasm" and not (chasm.get_node("art") as AnimatedSprite2D).is_playing()
		and (chasm.get_node("art") as CanvasItem).modulate == Ways.UNLIT_TINT, dark)
	var listener_script := GDScript.new()
	listener_script.source_code = "extends Node2D\nvar heard: Array = []\nfunc show_notice(message: String) -> void:\n\theard.append(message)\n"
	listener_script.reload()
	var listener := Node2D.new()
	listener.set_script(listener_script)
	var others: Array = get_tree().get_nodes_in_group(&"player")
	for other in others:
		(other as Node).remove_from_group(&"player")
	listener.add_to_group(&"player")
	add_child(listener)
	WorldMap.reveal_around(stone_chasm["at"] + Vector2(60, 60), "bigfield")
	var heard: Array = (listener.get("heard") as Array).duplicate()
	listener.remove_from_group(&"player")
	listener.free()
	for other in others:
		(other as Node).add_to_group(&"player")
	check("  finding it tells the player, and how to use it (0.134.3)",
		heard.size() == 1 and str(heard[0]) == Ways.FOUND_NOTICE % "The Chasm", heard)
	var bright: Dictionary = chasm.call("map_landmark")
	check("  walking past it lights it, at once: the portal plays, its name shows, a cyan pin",
		chasm.call("lit") and bool(bright.get("lit")) and bright.get("colour") == Ways.LIT_COLOUR
		and (chasm.get_node("art") as AnimatedSprite2D).is_playing()
		and (chasm.get_node("label") as Label).text == "Waystone - The Chasm\n" + Ways.TRAVEL_LINE, bright)
	check("  and the others are still dark", not Ways.is_lit(Ways.stone_for("crypt")))

	# ---- the stand-still ------------------------------------------------------------------------
	var player := Node2D.new()
	player.add_user_signal("took_damage", [{"name": "amount", "type": TYPE_INT}, {"name": "type", "type": TYPE_STRING}])
	player.add_to_group("player")
	player.position = Vector2(300, 300)
	add_child(player)
	var landed: Array = []
	Ways.jump_with = landed.append
	var refused: Array = [Ways.travel_to(get_tree(), "nowhere", "elusion"),
		Ways.travel_to(get_tree(), "crypt", "elusion"), Ways.travel_to(get_tree(), "chasm", "endless")]
	check("travel is refused, in words, to no stone, to one not found, and from a minigame",
		refused[0] != "" and refused[1].contains("not found") and refused[2].contains("cannot be reached")
		and get_tree().get_nodes_in_group(Ways.TRAVEL_GROUP).is_empty(), refused)
	var said: String = Ways.travel_to(get_tree(), "chasm", "elusion")
	var trip: Node = get_tree().get_first_node_in_group(Ways.TRAVEL_GROUP)
	trip._process(1.0)
	check("from town a found stone starts the stand-still over your head",
		said == "" and trip != null and trip.get_parent() == player and landed.is_empty(), said)
	player.position += Vector2(10, 0)
	trip._process(0.1)
	check("  moving stops it, and says so", String(trip.get("_stopped")).contains("moved") and landed.is_empty(),
		trip.get("_stopped"))
	trip.free()
	Ways.travel_to(get_tree(), "chasm", "elusion")
	trip = get_tree().get_first_node_in_group(Ways.TRAVEL_GROUP)
	player.emit_signal("took_damage", 5, "physical")
	trip._process(0.1)
	check("  a hit stops it, and says so", String(trip.get("_stopped")).contains("hit") and landed.is_empty(),
		trip.get("_stopped"))
	trip.free()
	Ways.travel_to(get_tree(), "chasm", "bigfield")
	trip = get_tree().get_first_node_in_group(Ways.TRAVEL_GROUP)
	trip._process(Ways.CHANNEL_SECONDS - 0.5)
	var early: bool = landed.is_empty()
	trip._process(0.6)
	check("  three seconds still and you go: to that stone",
		early and landed.size() == 1 and (landed[0] as Dictionary).get("id") == "chasm", landed)
	var code: String = _code_src("res://src/world/waystones.gd")
	var jump_body: String = _func_body(code, "static func jump(")
	check("  the jump lands in front of the stone, in the Big Field, with the portal's sound",
		jump_body.contains("AreaRegistry.go_to(AREA") and jump_body.contains("+ ARRIVE")
		and jump_body.contains("Audio.play(\"teleport\")"))

	# ---- the map ----------------------------------------------------------------------------------
	var map: Control = (load("res://scene/ui/menus/mapscreen.tscn") as PackedScene).instantiate() as Control
	add_child(map)
	await get_tree().process_frame
	var row: HFlowContainer = map.get("waystone_row")
	map.call("refresh", "elusion")
	var chasm_button: Button = row.get_node_or_null("chasm") as Button if row != null else null
	var crypt_button: Button = row.get_node_or_null("crypt") as Button if row != null else null
	check("the map has a row of the seven, shown in town; found ones pressable, the rest greyed",
		row != null and row.visible and row.get_child_count() == 8 and chasm_button != null
		and not chasm_button.disabled and crypt_button.disabled and chasm_button.text == "Chasm",
		[row != null and row.visible, row.get_child_count() if row != null else 0])
	var hint: Label = map.get("waystone_hint")
	check("  the row says how to use it (0.134.3: \"players have no idea how to teleport\") - found ones are cyan buttons",
		hint != null and hint.visible and hint.text.contains("stand still") and hint.text.contains("Click")
		and chasm_button.get_theme_stylebox("normal") is StyleBoxFlat
		and (chasm_button.get_theme_stylebox("normal") as StyleBoxFlat).border_color.a > 0.5)
	map.call("refresh", "endless")
	check("  and hidden in a minigame", row != null and not row.visible and not hint.visible)
	map.call("refresh", "elusion")
	map.visible = true
	chasm_button.pressed.emit()
	trip = get_tree().get_first_node_in_group(Ways.TRAVEL_GROUP)
	check("  pressing one starts the stand-still and shuts the map", trip != null and not map.visible)
	if trip != null:
		trip.free()
	var why: String = map.call("travel_to_waystone", "crypt")
	check("  one not found says why on the map's footer",
		why.contains("not found") and (map.get("explored_label") as Label).text == why, why)
	var map_code: String = _code_src("res://src/ui/menus/mapscreen.gd")
	var input_body: String = _func_body(map_code, "func _on_view_input(")
	check("  and a click on a pin - a press that did not drag - travels to a waystone under it",
		input_body.contains("_press_travel <= CLICK_SLACK") and input_body.contains("_click_pin()")
		and _func_body(map_code, "func _click_pin(").contains("travel_to_waystone("))

	# ---- and the registry adds them -----------------------------------------------------------
	check("every area is given its waystones as it loads (only the Big Field has any)",
		_func_body(_code_src("res://src/systems/arearegistry.gd"), "func _on_scene_changed(").contains("Waystones.add_to(scene)"))

	Ways.jump_with = Callable()
	map.queue_free()
	player.queue_free()
	field.queue_free()
	town.queue_free()
	if kept_terrain == null:
		WorldMap._terrain.erase("bigfield")
	else:
		WorldMap._terrain["bigfield"] = kept_terrain
	if kept_seen == null:
		WorldMap._seen.erase("bigfield")
	else:
		WorldMap._seen["bigfield"] = kept_seen
	WorldMap._save_dirty = kept_dirty
	WorldMap._revision_pending = kept_pending
	WorldMap._save_cache = kept_cache
	WorldMap.last_reveal = kept_reveal
	await get_tree().process_frame
	print("  (the waystones: done)")


# =============================================================================
# THE FORGE (step 1)
# =============================================================================
# The owner: "lets build it then decide more" - the tank's world, an island in
# a lake of lava that floods slice by slice ("enemies spawn close and closer",
# "players catch on fire and tanks gear just turns a little red", "everyone
# dies but time can be added"). Open to every class.

func _forge_body_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """extends Node2D
var hp: int = 200
var max_hp: int = 200
var is_dying: bool = false
var aura_active: bool = false
var velocity: Vector2 = Vector2.ZERO
var taken: Array = []
var shakes: Array = []
func take_damage(amount: int, element: int) -> void:
	taken.append([amount, element])
func shake_camera(strength: float, seconds: float) -> void:
	shakes.append([strength, seconds])
"""
	script.reload()
	return script


func _test_the_forge() -> void:
	section("THE FORGE (step 1): the tank's world - an island in a lake of lava that floods slice by slice")
	const Run := preload("res://src/world/forge/forgerun.gd")
	const BuildForge := preload("res://src/tools/buildforge.gd")
	var c: Vector2 = Run.CENTRE
	# ---- THE AREA ----------------------------------------------------------------
	var packed: PackedScene = load(str(AreaRegistry.AREAS.get("forge", ""))) as PackedScene
	var area: Node = packed.instantiate() if packed != null else null
	check("the Forge is an area, named for players, with a map in gamedata.json, and its island loads",
		AreaRegistry.has_area("forge") and AreaRegistry.display_name("forge") == "The Forge"
		and (_load_gamedata().get("areas", {}) as Dictionary).has("forge") and area != null)
	if area == null:
		return
	var run_node: Node = area.get_node_or_null("forgerun")
	var lava: TileMapLayer = area.get_node_or_null("lava") as TileMapLayer
	var anvil: Node2D = area.get_node_or_null("ysortworld/props/anvil") as Node2D
	var falls: Array = area.get_node("ysortworld/props").get_children().filter(
		func(n: Node) -> bool: return n is AnimatedSprite2D and n.is_in_group(&"forge_falls"))
	var arrivals: Array = []
	_collect_by_script(area, "res://src/world/fieldportal.gd", arrivals)
	var arrival: Node2D = null
	for a in arrivals:
		if str(a.get("portal_id")) == "forge_entrance":
			arrival = a
	var north_falls: bool = falls.size() == BuildForge.FALLS_AT.size() and falls.all(
		func(f: Node) -> bool: return (f as Node2D).position.y < c.y - Run.RADIUS and str((f as AnimatedSprite2D).autoplay) == "default")
	check("  its run, the anvil in the middle, the arrival beside it in the light, %d falls along the north, the bullet zone and no story" % falls.size(),
		run_node != null and run_node.get_script() == Run and anvil != null and anvil.position == c
		and arrival != null and arrival.position.distance_to(c) < Run.SAFE_OTHER and north_falls
		and area.get("tells_story") == false and area.get("bullet_zone") == true and lava != null)
	# THE LAKE (the owner: "animated lava should only be here the rest stale").
	var wrong: int = 0
	var bubbling: int = 0
	var still: int = 0
	for cell in lava.get_used_cells():
		var want: int = Run.BUBBLING if Run.bubbles(cell, {}, Run.SAFE_OTHER) else Run.STILL
		if lava.get_cell_source_id(cell) != want:
			wrong += 1
		if want == Run.BUBBLING:
			bubbling += 1
		else:
			still += 1
	var moving := lava.tile_set.get_source(Run.BUBBLING) as TileSetAtlasSource
	var resting := lava.tile_set.get_source(Run.STILL) as TileSetAtlasSource
	var deep := Vector2i(floori(c.x / Run.LAVA_TILE), floori((c.y - Run.RADIUS - 150.0) / Run.LAVA_TILE))
	check("the lake bubbles only where it meets the shore (%d cells) and lies still everywhere else (%d) - the town's lava tile, nine frames at three a second, each cell its own start" % [bubbling, still],
		wrong == 0 and bubbling > 100 and still > bubbling * 5 and lava.get_cell_source_id(deep) == Run.STILL
		and moving.texture.resource_path == "res://art/tiles/propsandterrain.png"
		and moving.get_tile_animation_frames_count(Run.LAVA_CELL) == 9
		and is_equal_approx(moving.get_tile_animation_speed(Run.LAVA_CELL), 3.0)
		and moving.get_tile_animation_mode(Run.LAVA_CELL) == TileSetAtlasSource.TILE_ANIMATION_MODE_RANDOM_START_TIMES
		and resting.texture == moving.texture and resting.get_tile_animation_frames_count(Run.LAVA_CELL) == 1,
		[wrong, bubbling, still])
	area.free()
	# ---- THE PIE -------------------------------------------------------------------
	var gone := {0: true}
	check("slice 0 is north, 2 east, 4 south, 6 west, and opposite slices flood in turn",
		Run.slice_of(c + Vector2(0, -500)) == 0 and Run.slice_of(c + Vector2(500, 0)) == 2
		and Run.slice_of(c + Vector2(0, 500)) == 4 and Run.slice_of(c + Vector2(-500, 0)) == 6
		and Run.ORDER == [0, 4, 2, 6, 1, 5, 3, 7])
	check("  a gone slice is floor inside the light and lava past it; the rest of the island is floor; past the shore is lava",
		Run.floor_at(c + Vector2(0, -250), gone, Run.SAFE_TANK) and not Run.floor_at(c + Vector2(0, -400), gone, Run.SAFE_TANK)
		and Run.floor_at(c + Vector2(0, 400), gone, Run.SAFE_TANK) and not Run.floor_at(c + Vector2(0, 980), {}, Run.SAFE_TANK)
		and absf(Run.SAFE_TANK - 256.0 / 2.0 * 2.3) < 1.0)
	# ---- THE RUN, on a stand-in island ----------------------------------------------
	var island := Node2D.new()
	add_child(island)
	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.tile_set = load("res://scene/world/underground.tres") as TileSet
	island.add_child(ground)
	var stand_lava := TileMapLayer.new()
	stand_lava.name = "lava"
	stand_lava.tile_set = BuildForge.lava_tiles()
	island.add_child(stand_lava)
	# A strip of floor north to south through the anvil, lava under the north.
	for y in range(int((c.y - 900.0) / Run.TILE), int((c.y + 900.0) / Run.TILE)):
		ground.set_cell(Vector2i(int(c.x / Run.TILE), y), 1, Vector2i(1, 1))
	for y in range(int((c.y - 960.0) / Run.LAVA_TILE), int((c.y - 100.0) / Run.LAVA_TILE)):
		stand_lava.set_cell(Vector2i(int(c.x / Run.LAVA_TILE), y), Run.STILL, Run.LAVA_CELL)
	var floor_cells: int = ground.get_used_cells().size()
	var world := Node2D.new()
	world.name = "ysortworld"
	island.add_child(world)
	for holder in ["props", "enemies"]:
		var n := Node2D.new()
		n.name = holder
		world.add_child(n)
	var glow := PointLight2D.new()
	glow.name = "forgeglow"
	island.add_child(glow)
	var body := Node2D.new()
	body.set_script(_forge_body_script())
	var sprite := Sprite2D.new()
	sprite.name = "animatedsprite2d"
	body.add_child(sprite)
	island.add_child(body)
	body.global_position = c + Vector2(0, 20)
	var run: Node = Run.new()
	run.name = "forgerun"
	run.set("player_override", body)
	run.set("class_override", "warrior")
	island.add_child(run)
	await get_tree().process_frame
	# Lighting it.
	run.call("_process", Run.START_HOLD + 0.01)
	var counting: bool = int(run.get("state")) == Run.State.COUNTDOWN
	run.call("_process", Run.COUNTDOWN_SECONDS + 0.01)
	run.set("_spawn_clock", 9999.0)
	run.set("_essence_clock", 9999.0)
	check("standing at the anvil lights it, the clock runs after the countdown, and a warrior's light is the anvil's own (%s px)" % run.get("safe"),
		counting and bool(run.call("running")) and is_equal_approx(float(run.get("safe")), Run.SAFE_OTHER)
		and is_equal_approx(glow.texture_scale, Run.SAFE_OTHER / 128.0))
	# The heat, the warning, the flood.
	var fill: float = float(run.call("fill_seconds"))
	run.call("_process", fill * Run.WARN_AT + 0.01)
	var warned: bool = bool(run.call("warning")) and int(run.get("flooding")) == -1 and int(run.call("next_slice")) == 0
	run.set("heat", 0.999)
	run.call("_process", 0.05)
	var started: bool = int(run.get("flooding")) == 0
	run.call("_process", Run.FLOOD_SECONDS + 0.1)
	var north_floor: int = 0
	var light_floor: int = 0
	for cell in ground.get_used_cells():
		var mid: Vector2 = Run.floor_cell_mid(cell)
		if mid.y < c.y and mid.distance_to(c) > Run.SAFE_OTHER:
			north_floor += 1
		elif mid.y < c.y:
			light_floor += 1
	check("heat warns from %d%%, then floods the north slice from the rim to the light: its floor goes, the light's and the south's stay" % int(Run.WARN_AT * 100),
		warned and started and int(run.get("floods")) == 1 and (run.get("flooded") as Dictionary).has(0)
		and north_floor == 0 and light_floor > 0 and ground.get_used_cells().size() < floor_cells
		and is_equal_approx(float(run.get("heat")), 0.0) and float(run.call("fill_seconds")) < fill,
		[warned, started, north_floor, light_floor])
	# Closer and closer: the spots' mean distance from the anvil, one slice
	# gone and then six.
	var all_lava: bool = true
	var one_gone: float = 0.0
	var six_gone: float = 0.0
	for i in 300:
		var spot: Vector2 = run.call("edge_spot")
		all_lava = all_lava and bool(run.call("in_lava", spot))
		one_gone += spot.distance_to(c) / 300.0
	var kept_flooded: Dictionary = run.get("flooded")
	run.set("flooded", {0: true, 4: true, 2: true, 6: true, 1: true, 5: true})
	for i in 300:
		var spot: Vector2 = run.call("edge_spot")
		all_lava = all_lava and bool(run.call("in_lava", spot))
		six_gone += spot.distance_to(c) / 300.0
	run.set("flooded", kept_flooded)
	check("the fire sprites step out of the lava's edges, closer and closer: %d px from the anvil on average with one slice gone, %d with six; more and more often" % [roundi(one_gone), roundi(six_gone)],
		all_lava and six_gone < one_gone - 150.0 and float(run.call("spawn_gap")) < Run.SPAWN_EVERY
		and int(run.call("alive_cap")) > Run.ALIVE_FIRST)
	# Fire.
	body.global_position = c + Vector2(0, -420)
	run.call("_process", Run.BURN_TICK + 0.01)
	var hits: Array = body.get("taken")
	var burnt: bool = hits.size() == 1 and int(hits[0][0]) == roundi(200 * Run.LAVA_BURN) \
		and int(hits[0][1]) == Element.Type.FIRE and body.get_node_or_null("forgeflames") != null
	run.set("class_override", "tank")
	run.call("_process", Run.BURN_TICK + 0.01)
	var tank_burns: bool = (body.get("taken") as Array).size() == 2 and float(run.call("redness")) > 0.4 \
		and sprite.modulate != Color.WHITE
	check("in the lava with no armour a warrior catches fire (%s a tick, flames on them) - and since 0.121.0 the tank too, his gear red" % [hits],
		burnt and tank_burns)
	# The tank's walkways (the owner: "what if the tanks aura can push back lava
	# only where he is standing to create safe walkways for the team").
	var under: Vector2 = body.global_position + Run.AURA_OFFSET
	var under_cell := Vector2i(floori(under.x / Run.TILE), floori(under.y / Run.TILE))
	var lava_before: bool = bool(run.call("in_lava", under))
	run.call("_process", Run.WALK_REPAINT + 0.01)
	var no_aura: bool = int(run.call("walkway_cells")) == 0
	body.set("aura_active", true)
	run.call("_process", Run.WALK_REPAINT + 0.01)
	var paved_cells: int = int(run.call("walkway_cells"))
	var paved: bool = not bool(run.call("in_lava", under)) and ground.get_cell_source_id(under_cell) != -1 \
		and bool(run.call("in_lava", body.global_position + Vector2(0, -150))) and paved_cells > 10
	body.set("aura_active", false)
	run.call("_process", Run.WALK_REPAINT + 0.01)
	var lingers: bool = not bool(run.call("in_lava", under))
	run.call("_process", Run.WALK_LINGER)
	var melted: bool = bool(run.call("in_lava", under)) and int(run.call("walkway_cells")) == 0 \
		and ground.get_cell_source_id(under_cell) == -1
	check("the tank's aura pushes the lava back where he stands - island under his ring (%d cells), lingering %s s after he moves on, then melting; nothing without the aura" % [paved_cells, Run.WALK_LINGER],
		lava_before and no_aura and paved and lingers and melted)
	# Time added.
	body.global_position = c + Vector2(0, 30)
	run.set("heat", 0.5)
	run.call("_lay_essence")
	var essence: Node2D = run.get("_essence")
	var placed: bool = essence != null and essence.global_position.distance_to(c) >= Run.RADIUS * Run.ESSENCE_NEAR \
		and Run.slice_of(essence.global_position) != 0 and Run.slice_of(essence.global_position) != int(run.call("next_slice"))
	if essence != null:
		body.global_position = essence.global_position
	run.call("_process", 0.01)
	check("ice essence lies out in an open slice, never the one about to flood; walked over, it cools the heat",
		placed and int(run.get("essences")) == 1 and float(run.get("heat")) < 0.5 - Run.ESSENCE_COOL + 0.05)
	# The volcano (0.121.0): it erupts - nobody in the light burns; its rocks
	# are _test_the_forge_gear_and_eruption()'s.
	body.global_position = c + Vector2(0, 30)
	run.set("floods", Run.SLICES)
	var before: int = (body.get("taken") as Array).size()
	run.call("_process", Run.BURN_TICK + 0.01)
	run.call("_process", Run.BURN_TICK + 0.01)
	var late: Array = (body.get("taken") as Array).slice(before)
	check("once every slice is gone the volcano erupts: no burn on anyone in the light, and its first rocks are in the air",
		bool(run.call("volcano")) and late.is_empty() and not (run.get("rocks") as Array).is_empty(), [late, (run.get("rocks") as Array).size()])
	# A fall.
	body.global_position = Vector2(-5000, -5000)
	var elsewhere: bool = not bool(run.call("knock_out", body))
	body.global_position = c + Vector2(0, 30)
	var caught: bool = bool(run.call("knock_out", body))
	check("a fall off the island is an ordinary death; on it you wake by the anvil on 1 health, the run is over, and the island is whole again",
		elsewhere and caught and int(body.get("hp")) == 1 and body.global_position == run.get("entry_spot")
		and int(run.get("state")) == Run.State.WAITING and str(run.get("last_result")).begins_with("The forge held")
		and ground.get_used_cells().size() == floor_cells and (run.get("flooded") as Dictionary).is_empty()
		and sprite.modulate == Color.WHITE)
	check("  the player's fall is caught by the Forge's run, as the Endless's and the Descent's are",
		_func_body(_code_src("res://src/characters/player.gd"), "func _endless_catches_fall(").contains("&\"forge_run\""))
	island.queue_free()
	await get_tree().process_frame
	# ---- THE CARD -------------------------------------------------------------------
	var card_hud := Control.new()
	add_child(card_hud)
	var card = (load("res://src/ui/minigames/minigamescard.gd") as GDScript).call("attach", card_hud)
	var went: Array = []
	var entered: Array = []
	card.set("travel", func(area_id: String, spawn_id: String) -> void: went.append([area_id, spawn_id]))
	card.set("area_now", func() -> String: return "elusion")
	# Go asks the server first since 0.120.0 (_test_the_forge_pays() has the day).
	card.set("list_request", func(_p: String, _t: float = 0.0) -> Dictionary: return {"ok": false})
	# No chest left in the tree by an earlier section holds Leave back.
	card.set("chest_count", func() -> int: return 0)
	card.set("enter_request", func(path: String, body: Dictionary, _t: float = 0.0) -> Dictionary:
		entered.append([path, body])
		return {"ok": true, "status": 200, "data": {"ok": true, "game": "forge"}})
	card.set("shows_forge", func() -> bool: return false)
	card.call("paint")
	var hidden: bool = not card.forge_box.visible
	card.set("shows_forge", func() -> bool: return true)
	card.set("class_now", func() -> String: return "mage")
	card.call("open")
	card.call("paint")
	var shown: bool = card.forge_box.visible and card.forge_go.text == "Go" and not card.forge_go.disabled
	await card.call("_on_forge_go")
	card.set("area_now", func() -> String: return "forge")
	card.call("paint")
	var leave_text: String = card.forge_go.text
	card.call("_on_forge_go")
	check("on the Minigames card for the owner alone, any class: Go goes down (%s), and inside it is Leave, to town" % str(went),
		hidden and shown and leave_text == "Leave" and went.size() == 2 and went[0] == ["forge", "forge_entrance"]
		and went[1] == ["elusion", ""] and entered == [["/api/minigames/enter", {"game": "forge"}]], [went, entered])
	card_hud.queue_free()
	await get_tree().process_frame
	print("  (the forge: done)")


# =============================================================================
# TEXT BOXES HAVE NO RIGHT-CLICK MENU (0.119.1)
# =============================================================================
# The owner, of the login screen's right-click menu: "this douse nothing".

func _test_text_boxes_have_no_right_click_menu() -> void:
	section("TEXT BOXES (0.119.1): no right-click menu on any - their shortcut keys still work")
	var login: Node = (load("res://scene/ui/menus/loginmenu.tscn") as PackedScene).instantiate()
	var login_boxes: int = login.find_children("*", "LineEdit", true, false).size()
	login.free()
	var holder := Control.new()
	var box := LineEdit.new()
	var area := TextEdit.new()
	var rich := RichTextLabel.new()
	rich.context_menu_enabled = true
	holder.add_child(box)
	holder.add_child(area)
	holder.add_child(rich)
	add_child(holder)
	await get_tree().process_frame
	check("a text box entering the game has no right-click menu (the login screen's %d among them), its Ctrl keys still on; a RichTextLabel keeps its Copy" % login_boxes,
		login_boxes >= 2 and not box.context_menu_enabled and not area.context_menu_enabled
		and box.shortcut_keys_enabled and area.shortcut_keys_enabled and rich.context_menu_enabled)
	holder.queue_free()
	await get_tree().process_frame


# =============================================================================
# THE LOGIN SCREEN AND THE MINIGAMES CARD, UPDATED (0.119.1)
# =============================================================================
# The owner: "need image 1 upgraded" (the Minigames card), "we need to update
# this" (the login screen), "i meant my sytle boxs from hitbar", and of the
# mock-ups, "looks great".

func _test_the_login_and_minigames_look() -> void:
	section("THE LOOK (0.119.1): the login screen in the hotbar's frames, Google green or red, the Minigames card in tiles")
	const Google := preload("res://src/systems/googlesignin.gd")
	var login: Node = _login_screen_for_test()
	login._build_create_account()
	login._build_google()
	login._build_notice()
	login._dress_in_sockets()
	var form: Node = login.get_node("%loginform")
	var button: Button = login.get_node("%loginbutton")
	var name_box: LineEdit = login.get_node("%usernamelineedit")
	var remember: CheckBox = login.get_node("%rememberme")
	var framed := func(c: Control) -> bool:
		var style := c.get_theme_stylebox(&"normal") as StyleBoxTexture
		return style != null and style.texture != null and style.texture.resource_path == "res://art/images/hotbarslot.png"
	check("the boxes and solid buttons wear the hotbar's key frame - Enter Elusion's green; the tick box and the flat links do not",
		framed.call(button) and (button.get_theme_stylebox(&"hover") as StyleBoxTexture).modulate_color == login.ENTER_TINT
		and framed.call(name_box) and framed.call(login.get_node("%passwordlineedit"))
		and not remember.has_theme_stylebox_override(&"normal") and not login.create_link.has_theme_stylebox_override(&"normal"))
	var divider: Node = form.get_node_or_null("ordivider")
	check("  \"or\" between Enter Elusion and Sign in with Google, the link line under Google",
		divider != null and button.get_index() < divider.get_index() and divider.get_index() < login.google_button.get_index()
		and login.google_link_line.get_index() == login.google_button.get_index() + 1)
	var forgot: Node = login.get_node("%recoverlinkbutton")
	check("  \"Forgot password?\" and \"Create an account\" side by side",
		forgot.get_parent().name == "linksrow" and login.create_link.get_parent() == forgot.get_parent()
		and login.create_link.get_index() == forgot.get_index() + 1)
	# Green, red, plain.
	Google.remember_link("suitesmith", true)
	Google.remember_link("suitenolink", false)
	var tint := func() -> Color:
		return (login.google_button.get_theme_stylebox(&"hover") as StyleBoxTexture).modulate_color
	name_box.text = "SuiteSmith"
	login._paint_google_link()
	var green: bool = login.google_link_line.visible and login.google_link_line.text.contains("is linked") \
		and tint.call() == login.GOOGLE_LINKED
	name_box.text = "suitenolink"
	login._paint_google_link()
	var red: bool = login.google_link_line.visible and login.google_link_line.text.contains("isn't linked") \
		and tint.call() == login.GOOGLE_UNLINKED
	name_box.text = "suitenever"
	login._paint_google_link()
	var plain: bool = not login.google_link_line.visible and tint.call() == Color.WHITE
	check("Google's button is green for a name this computer heard is linked, red for one it heard is not, plain for one it never heard",
		green and red and plain and Google.remembered_link("SUITESMITH") == 1 and Google.remembered_link("") == -1)
	var learned: bool = _func_body(_code_src("res://src/ui/menus/loginmenu.gd"), "func _complete_login(").contains("GoogleScript.learn_link(") \
		and _func_body(_code_src("res://src/ui/menus/loginmenu.gd"), "func _google_signed_in(").contains("GoogleScript.remember_link(Api.username, true)") \
		and _func_body(_code_src("res://src/ui/menus/optionsscreen.gd"), "func _refresh_google(").contains("GoogleScript.remember_link(")
	check("  heard at a Google sign-in, at every sign-in (asked, never awaited) and in Options' Google row", learned)
	# The status, and the notice under it.
	var status: Label = login.get_node("%statuslabel")
	login._set_status("Connected to the Elusion server.", login.STATUS_ONLINE)
	var pill: bool = status.size_flags_horizontal == Control.SIZE_SHRINK_CENTER and status.get_theme_stylebox(&"normal") is StyleBoxFlat \
		and (status.get_theme_stylebox(&"normal") as StyleBoxFlat).border_color.g > 0.5
	login._set_status("Password updated - sign in with your new password, then pick your character.", login.STATUS_GOOD)
	var wraps: bool = status.size_flags_horizontal == Control.SIZE_FILL and status.autowrap_mode != TextServer.AUTOWRAP_OFF
	login._show_notice("You were signed out - the connection to the server was lost.")
	check("the server's status is a pill in its colour (a long one wraps); a sign-out notice has its own amber box under it",
		pill and wraps and login.notice_box.visible and login.notice_box.get_index() == status.get_index() + 1
		and login.notice_label.get_theme_color(&"font_color") == login.SAY_BLOCKED)
	login.free()
	# The Minigames card in tiles.
	var card_hud := Control.new()
	add_child(card_hud)
	var card = (load("res://src/ui/minigames/minigamescard.gd") as GDScript).call("attach", card_hud)
	for seam in ["shows_healer_run", "shows_mage_stand", "shows_descent", "shows_forge"]:
		card.set(seam, func() -> bool: return true)
	card.set("area_now", func() -> String: return "elusion")
	card.set("class_now", func() -> String: return "tank")
	card.set("list_request", func(_p: String, _t: float = 0.0) -> Dictionary: return {"ok": false})
	card.call("open")
	await get_tree().process_frame
	await get_tree().process_frame
	var tiles: Array = [card.endless_box, card.healer_box, card.stand_box, card.descent_box, card.forge_box]
	var pictured: bool = tiles.all(func(t: Control) -> bool:
		var pics: Array = t.find_children("*", "TextureRect", true, false)
		return t is PanelContainer and t.visible and pics.size() == 1 and (pics[0] as TextureRect).texture != null)
	var tagged: bool = card.forge_box.find_children("tag", "Label", true, false).size() == 4 \
		and card.endless_box.find_children("tag", "Label", true, false).size() == 1
	check("the Minigames card is a tile a game - each its portrait from the game's own art and its tags - and %d px tall (it was 640)" % roundi(card.size.y),
		pictured and tagged and card.size.y < 480.0 and card.forge_go.get_parent().get_parent() == card.forge_box)
	card_hud.queue_free()
	await get_tree().process_frame


# 0.119.2. The owner: "when minigame ends bullets fly randomly". A run's end
# freed its monsters at once and left every orb, lob and shot they had in the
# air flying on from nobody - measured in the Forge, 20 orbs and 5 shots at
# the end, still there a quarter second later.
func _test_a_runs_end_takes_its_shots() -> void:
	section("A RUN'S END - what the monsters fired goes with them")
	const Source := preload("res://src/shared/hitsource.gd")
	var area := Node2D.new()
	add_child(area)
	var shots := Node2D.new()
	shots.add_to_group(&"projectiles")
	area.add_child(shots)
	var floor_fx := Node2D.new()
	floor_fx.add_to_group(&"groundeffects")
	area.add_child(floor_fx)
	var zone: BulletZone = BulletZone.new()
	area.add_child(zone)
	await get_tree().process_frame
	zone.fire_ring(Vector2(100, 100), 0.0, 12, 120.0, 5, 6)
	var lob := BulletLob.new()
	zone.add_child(lob)
	var arrow := Node2D.new()
	arrow.set_meta(Source.HIT_META, "firesprite:fireprojectile")
	shots.add_child(arrow)
	var pool := Node2D.new()
	pool.set_meta(Source.HIT_META, "boss:burn")
	floor_fx.add_child(pool)
	var mine := Node2D.new()
	shots.add_child(mine)
	var orbs_before: int = zone.field.count
	var taken: int = BulletZone.clear_enemy_shots(zone)
	check("clear_enemy_shots() takes the zone's %d orbs and its lob, and a monster's shot and burning pool" % orbs_before,
		orbs_before == 12 and zone.field.count == 0 and taken == 15
		and arrow.is_queued_for_deletion() and pool.is_queued_for_deletion() and lob.get_parent() == null, taken)
	check("  and leaves a player's shot (no monster's tag)", is_instance_valid(mine) and not mine.is_queued_for_deletion())
	check("  and with no zone and no shots it takes nothing", BulletZone.clear_enemy_shots(null) == 0)
	area.queue_free()
	# Every minigame's end calls it, beside freeing its monsters.
	var forge: String = _code_src("res://src/world/forge/forgerun.gd")
	var endless: String = _code_src("res://src/world/endless/endlessrun.gd")
	var descent: String = _code_src("res://src/world/descent/descentrun.gd")
	check("the Forge's end, the Endless's end and its emptying, and the Descent's clearing all take the shots",
		_func_body(forge, "func end_run(").contains("BulletZone.clear_enemy_shots(self)")
		and _func_body(endless, "func _end_run(").contains("BulletZone.clear_enemy_shots(self)")
		and _func_body(endless, "func _end_run(").contains("_free_extras()")
		and _func_body(endless, "func _clear_arena(").contains("BulletZone.clear_enemy_shots(self)")
		and _func_body(descent, "func _clear_monsters(").contains("BulletZone.clear_enemy_shots(self)"))
	await get_tree().process_frame
	print("  a run's end: the orbs, lobs and shots go with the monsters")


# 0.119.2. The owner, of the Forge: "need major reduction on dynamite cost on
# mp and click to hold i think limiting the attack was a bad idea click to hold
# spam fire would be nice for this mini game".
func _test_the_dynamite_held_and_cheap_in_the_forge() -> void:
	section("THE DYNAMITE - held, it keeps throwing; in the Forge, a tenth of the mana")
	var arena := Node2D.new()
	add_child(arena)
	var tank: Node = (load("res://src/characters/tank.gd") as GDScript).new()
	tank._set_stat_curve()
	tank.level = 22
	tank.spawn_parent_override = arena
	tank.equipped = {"weapon": "dynamite"}
	tank.refresh_gear_stats()
	tank.dynamite_bundle_chance = 0.0
	tank.dynamite_barrage_chance = 0.0
	arena.add_child(tank)
	tank.set_process(false)
	tank.set_physics_process(false)
	tank.global_position = Vector2(-61000, -61000)
	var usual: int = tank.dynamite_mana_cost
	check("held, the Dynamite repeats: ready when the cooldown is over and the bar can pay",
		tank.touch_attack_repeats() == true and usual == 82, usual)
	tank.mana = 500
	var ready_before: bool = tank.touch_attack_ready()
	tank.throw_dynamite(tank.global_position + Vector2(60, 0))
	var waits: bool = not tank.touch_attack_ready()
	tank.set("_dynamite_cooldown_left", 0.0)
	tank.mana = usual - 1
	check("  not mid-cooldown, and not with too little mana - so a held button on an empty bar is quiet",
		ready_before and waits and not tank.touch_attack_ready())
	tank.equipped = {}
	tank.refresh_gear_stats()
	check("  and without the Dynamite, attack is the aura's switch and never repeats", tank.touch_attack_repeats() == false)
	tank.equipped = {"weapon": "dynamite"}
	tank.refresh_gear_stats()
	var forge := Node.new()
	forge.add_to_group(&"forge_run")
	arena.add_child(forge)
	var in_forge: int = tank.dynamite_mana_cost
	check("in the Forge a throw costs a tenth - %d mana where it is %d - less than the bar refills between throws" % [in_forge, usual],
		in_forge == ceili(usual * tank.FORGE_DYNAMITE_SHARE) and in_forge == 9 and tank.in_the_forge(), [in_forge, usual])
	arena.remove_child(forge)
	forge.free()
	check("  and out of it, the usual price again", tank.dynamite_mana_cost == usual and not tank.in_the_forge())
	arena.queue_free()
	await get_tree().process_frame
	print("  dynamite: held, it throws on; in the Forge a tenth of the mana")


# 0.120.0. The owner, 4 Nov: "Rewards + daily wait" - the Forge's step 1 of
# four (FORGE_PLAN.txt). The server's half is the API's test_minigames.py MG-14.
func _test_the_forge_pays() -> void:
	section("THE FORGE PAYS - once a day, every fire sprite into a chest by the arrival, the best time kept (0.120.0)")
	const Run := preload("res://src/world/forge/forgerun.gd")
	# ---- the schedule the server holds a kill to ----
	var made: Dictionary = Run.schedule()
	var file := FileAccess.open("res://data/gamedata.json", FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	var exported: Dictionary = (parsed as Dictionary).get("forge", {}) if parsed is Dictionary else {}
	var phases: Array = made["phases"]
	var written: Array = exported.get("phases", [])
	var same: bool = written.size() == phases.size() and phases.size() == Run.SLICES
	for i in mini(written.size(), phases.size()):
		same = same and is_equal_approx(float(written[i].get("seconds", -1)), float(phases[i]["seconds"])) \
			and is_equal_approx(float(written[i].get("gap", -1)), float(phases[i]["gap"])) \
			and int(written[i].get("count", -1)) == int(phases[i]["count"])
	var volcano: Dictionary = exported.get("volcano", {})
	check("gamedata.json carries the Forge's schedule as forgerun.gd makes it (change the spawns or the heat: re-export, copy to the API)",
		same and Array(exported.get("sprites", [])) == ["firesprite"] and made["sprite_scenes"] == [Run.SPRITE]
		and int(exported.get("alive_most", -1)) == int(made["alive_most"])
		and int(exported.get("volcano_believed", -1)) == Run.VOLCANO_BELIEVED
		and is_equal_approx(float(volcano.get("gap", -1)), float(made["volcano"]["gap"]))
		and int(volcano.get("count", -1)) == int(made["volcano"]["count"]), [written.size(), exported.get("sprites")])
	check("  at its fastest: the first flood 40 s at a sprite each 3 s, the last 19.13 s at three each 0.629 s, 50 alive",
		is_equal_approx(float(phases[0]["seconds"]), 40.0) and is_equal_approx(float(phases[0]["gap"]), 3.0)
		and int(phases[0]["count"]) == 1 and is_equal_approx(float(phases[7]["seconds"]), 19.13)
		and is_equal_approx(float(phases[7]["gap"]), 0.629) and int(phases[7]["count"]) == 3
		and int(made["alive_most"]) == 50, [phases[0], phases[7]])

	# ---- a fire sprite pays the chest ----
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
	body.set_script(_forge_body_script())
	island.add_child(body)
	body.global_position = Vector2(-90000, -90000)
	var run: Node = Run.new()
	run.name = "forgerun"
	run.set("player_override", body)
	run.set("class_override", "tank")
	island.add_child(run)
	await get_tree().process_frame
	await get_tree().process_frame
	var chest: Node2D = world.get_node_or_null("interactables/forgechest") as Node2D
	run.call("_process", 0.01)
	check("the Forge has its chest beside the arrival, the Forge's, its arrow for the light round the anvil between runs",
		chest != null and chest == run.get("chest") and chest.position == Run.CHEST_SPOT
		and str(chest.get("game")) == "forge" and chest.get("corridor") == Run.CHEST_BECKON
		and Run.CHEST_SPOT.distance_to(Run.CENTRE) > Run.START_REACH
		and str(chest.get("empty_words")).contains("fire sprite"), chest)
	run.set("_spawn_clock", 9999.0)
	run.set("_essence_clock", 9999.0)
	run.set("state", Run.State.RUNNING)
	run.call("_process", 0.0)
	check("  and no arrow while a run is on", chest != null and chest.get("corridor") == Rect2())
	run.set("state", Run.State.WAITING)

	var kept_post: Callable = Combat.kill_post
	var kept_token: String = Api.token
	var kept_known: bool = Api.reachability_known
	var kept_online: bool = Api.server_online
	Api.token = "test-not-a-real-token"
	var posts: Array = []
	Combat.kill_post = func(path: String, sent: Dictionary, _timeout: float) -> Dictionary:
		posts.append([path, sent.duplicate()])
		await get_tree().process_frame
		return {"ok": true, "status": 200, "data": {"used": 2, "added": [{"item_id": "coppercoin", "quantity": 9}],
			"cut": [], "mythic": "", "pet_won": false, "chest_id": "chest:forge:0"}}
	var sprite: Node = run.call("_bring", Run.SPRITE, Run.CENTRE + Vector2(400, 0), 1.0)
	await get_tree().process_frame
	check("a fire sprite the Forge brings carries the chest's mark and the stress test's: no ordinary kill",
		sprite != null and str(sprite.get_meta(Run.CHEST_META, "")) == "forge" and sprite.has_meta(Run.MARK)
		and sprite.call("get_enemy_id") == "", sprite)
	Api.reachability_known = true
	Api.server_online = true
	if sprite != null:
		sprite.call("_die")
	for i in 6:
		await get_tree().process_frame
	check("  slain, it reports to /api/minigames/kill for the Forge, never /api/combat/kill, and the chest's count follows",
		posts.size() == 1 and str(posts[0][0]) == "/api/minigames/kill" and posts[0][1].get("game") == "forge"
		and posts[0][1].get("enemy_id") == "firesprite" and chest != null and int(chest.get("used")) == 2, posts)
	Combat.kill_post = kept_post

	# ---- the run's time ----
	var times: Array = []
	run.set("best_post", func(path: String, sent: Dictionary) -> Dictionary:
		times.append([path, sent.duplicate()])
		await get_tree().process_frame
		return {"ok": true, "status": 200, "data": {"seconds": 270, "best": 270, "new_best": true}})
	run.set("state", Run.State.RUNNING)
	run.set("elapsed", 270.4)
	run.call("end_run")
	for i in 3:
		await get_tree().process_frame
	check("a run's end sends its time, and the server's best is kept",
		times == [["/api/minigames/best", {"game": "forge", "seconds": 270}]] and int(run.get("server_best")) == 270
		and float(run.get("best")) >= 270.0, [times, run.get("server_best")])
	times.clear()
	run.set("state", Run.State.RUNNING)
	run.set("elapsed", 0.4)
	run.call("end_run")
	await get_tree().process_frame
	check("  a run of no time at all sends nothing", times.is_empty(), times)
	Api.token = kept_token
	Api.reachability_known = kept_known
	Api.server_online = kept_online
	island.queue_free()
	await get_tree().process_frame

	# ---- the card: Go asks, the day, the best ----
	var card_hud := Control.new()
	add_child(card_hud)
	var card = (load("res://src/ui/minigames/minigamescard.gd") as GDScript).call("attach", card_hud)
	var area: Array = ["elusion"]
	var entering: Array = [{"ok": false, "status": 409, "data": {"ready_in": 48000}}]
	var held: Array = [0]
	var went: Array = []
	card.set("shows_forge", func() -> bool: return true)
	card.set("area_now", func() -> String: return area[0])
	card.set("travel", func(area_id: String, spawn_id: String) -> void: went.append([area_id, spawn_id]))
	card.set("chest_count", func() -> int: return held[0])
	card.set("list_request", func(_p: String, _t: float = 0.0) -> Dictionary:
		return {"ok": true, "status": 200, "data": {"games": [{"id": "forge", "ready_in": 0, "best": 270}]}})
	card.set("enter_request", func(_p: String, _b: Dictionary, _t: float = 0.0) -> Dictionary: return entering[0])
	await card.call("open")
	var ready_line: String = card.forge_status.text
	await card.call("_on_forge_go")
	check("the card says your best beside Ready (%s); inside the day Go says how long is left and waits" % ready_line,
		ready_line == "Ready  ·  best 4:30" and card.forge_status.text == "Back in 13h 20m  ·  best 4:30"
		and card.forge_go.disabled and went.is_empty(), [card.forge_status.text, went])
	area[0] = "forge"
	held[0] = 3
	card.call("paint")
	var holds: String = card.forge_status.text
	card.call("_on_forge_go")
	var armed: String = card.forge_go.text
	card.call("_on_forge_go")
	check("  inside with loot in the chest, Leave asks twice, saying the next Go empties it",
		holds == "Your chest holds 3. Leave it and your next Go empties it." and armed == "Leave anyway"
		and went == [["elusion", ""]], [holds, armed, went])
	check("the Forge is DAILY on the card", card.forge_box.find_children("tag", "Label", true, false).any(
		func(t: Label) -> bool: return t.text == "DAILY"))
	card_hud.queue_free()
	await get_tree().process_frame
	print("  the forge pays: its schedule, the chest, the time, the card")


# 0.120.0. The owner, of the hero screen: "add the styles and maybe a picture
# of the characters on the top left of the boxs ... get rid of the dull brown
# and just make everything look pretty and well conformed", and "keep going
# gotta update everything".
func _test_one_look_for_the_game() -> void:
	section("ONE LOOK - every button and box the hotbar's frame, the browns gone, the heroes pictured (0.120.0)")
	const SOCKET_ART := "res://art/images/hotbarslot.png"
	var theme: Theme = load("res://assets/themes/rpg_ui_theme.tres") as Theme
	var framed := func(box: StyleBox) -> bool:
		return box is StyleBoxTexture and (box as StyleBoxTexture).texture != null \
			and (box as StyleBoxTexture).texture.resource_path == SOCKET_ART
	var cropped := func(box: StyleBox) -> bool:
		return box is StyleBoxTexture and (box as StyleBoxTexture).region_rect == Rect2(4, 4, 24, 24) \
			and is_equal_approx((box as StyleBoxTexture).texture_margin_left, 3.0)
	var parts: Array = [["normal", "Button"], ["hover", "Button"], ["pressed", "Button"], ["disabled", "Button"],
		["normal", "OptionButton"], ["normal", "LineEdit"], ["focus", "LineEdit"], ["tab_selected", "TabContainer"],
		["tab_unselected", "TabContainer"], ["panel", "PanelHeader"], ["panel", "PanelSlot"]]
	var plain: Array = []
	for part in parts:
		var box: StyleBox = theme.get_stylebox(part[0], part[1])
		if not (framed.call(box) and cropped.call(box)):
			plain.append("%s/%s" % [part[1], part[0]])
	check("every button, dropdown, field, tab, header and card in the game's theme is the hotbar's frame, its empty edge cropped",
		plain.is_empty(), plain)
	var window: StyleBoxFlat = theme.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	var inner: StyleBoxFlat = theme.get_stylebox("panel", "PanelSub") as StyleBoxFlat
	check("  windows near-black in a bright gold edge; an inner box a dark box with a thin gold line",
		window != null and window.bg_color.v < 0.1 and window.border_color.r > 0.7 and window.border_width_left >= 3
		and inner != null and inner.bg_color.v < 0.12 and inner.border_color.r > 0.8 and inner.border_width_top == 1)
	var source: String = FileAccess.get_file_as_string("res://assets/themes/rpg_ui_theme.tres")
	check("  and none of the old browns is left in it",
		not source.contains("Color(0.18, 0.15, 0.12") and not source.contains("Color(0.12, 0.1, 0.08")
		and not source.contains("StyleBoxFlat_button_normal"))
	var nav: StyleBoxFlat = _node_prop_in_scene("res://scene/ui/characterhud.tscn", "navframe",
		"theme_override_styles/panel") as StyleBoxFlat
	check("the bar at the bottom wears the windows' colours", nav != null and nav.bg_color.v < 0.1
		and nav.border_color.r > 0.7, nav)
	var over: PackedScene = load("res://scene/ui/menus/gameover.tscn") as PackedScene
	var death: Control = over.instantiate() as Control
	check("the death screen has the game's theme, not Godot's grey", death.theme != null
		and death.theme.resource_path == "res://assets/themes/rpg_ui_theme.tres")
	death.free()

	# ---- the hero screen ----
	var kept: Array = []
	for i in 4:
		kept.append(CharacterData.character_slots[i])
	CharacterData.character_slots[0] = {"character": "warrior", "level": 99}
	CharacterData.character_slots[1] = null
	var select: Control = (load("res://scene/ui/menus/characterselect.tscn") as PackedScene).instantiate() as Control
	select.call("_build_slot_extras")
	select.call("_dress_cards")
	select.call("update_slot_labels")
	var grid: Node = select.get_node(select.GRID_PATH)
	var pictured: Array = []
	for hero in ["warrior", "mage", "tank", "healer"]:
		var top: Node = grid.get_node_or_null("%s/vbox/top" % hero)
		var frame: Node = top.get_node_or_null("portraitframe") if top != null else null
		var words: Node = top.get_node_or_null("words") if top != null else null
		if frame != null and frame.get_node_or_null("portrait") is TextureRect and words != null \
				and words.get_node_or_null("classname") != null and top.get_index() == 0:
			pictured.append(hero)
	var level: Label = select.get_node("%label1")
	var picked: Button = select.get_node("%selectbutton1")
	var made: Button = select.get_node("%createbutton2")
	check("each hero card has its picture in the top left, framed, its name and level beside it",
		pictured == ["warrior", "mage", "tank", "healer"] and level.get_parent().name == "words"
		and level.text == "Level 99", [pictured, level.get_parent().name, level.text])
	var tint := func(button: Button) -> Color:
		var box: StyleBoxTexture = button.get_theme_stylebox("hover") as StyleBoxTexture
		return box.modulate_color if box != null else Color.BLACK
	var delete_one: Button = select.get("delete_buttons")[0]
	check("  Select green, Create gold, Delete red - and the buttons at the card's foot",
		tint.call(picked).g > tint.call(picked).r and tint.call(made).r > tint.call(made).b
		and tint.call(delete_one).r > tint.call(delete_one).g
		and grid.get_node("warrior/vbox/push").get_index() == grid.get_node("warrior/vbox/buttons").get_index() - 1,
		[tint.call(picked), tint.call(made), tint.call(delete_one)])
	check("  the pictures are asked of a thread, never loaded on the spot (the world may be loading ahead)",
		_func_body(_code_src("res://src/ui/menus/characterselect.gd"), "func _ask_portrait(").contains("load_threaded_request")
		and not _func_body(_code_src("res://src/ui/menus/characterselect.gd"), "func _dress_cards(").contains("portrait_of("))
	select.free()
	for i in 4:
		CharacterData.character_slots[i] = kept[i]
	print("  one look: the themes, the bar, the death screen, the hero cards")


# =============================================================================
# THE FORGE'S GEAR AND ITS ERUPTION (0.121.0)
# =============================================================================
# The owner's rules: "He wades lava longest. Every class burns in lava, but
# each forged piece buys the tank about twice as much wading time as anyone
# else", "He forges fastest. Anyone can work the anvil, but the tank's swings
# count fully", "Fire bites him less", then "lets add the gear to make the
# minigame funner no point in the fire damage at the end we need the screen to
# start shaking and we can use the giant meteor impact to simulate the volcano
# erupting".

func _test_the_forge_gear_and_eruption() -> void:
	section("THE FORGE'S GEAR AND ERUPTION (0.121.0): armour hammered at the anvil buys time in the lava, the tank's fire bites less, the volcano throws rocks")
	const Run := preload("res://src/world/forge/forgerun.gd")
	var c: Vector2 = Run.CENTRE
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
	body.set_script(_forge_body_script())
	island.add_child(body)
	body.global_position = c + Vector2(0, 20)
	var run: Node = Run.new()
	run.name = "forgerun"
	run.set("player_override", body)
	run.set("class_override", "warrior")
	island.add_child(run)
	await get_tree().process_frame
	await get_tree().process_frame
	run.call("start_run")
	run.set("_spawn_clock", 9999.0)
	run.set("_essence_clock", 9999.0)
	var hud: Node = run.get("hud")
	var hint: String = str(hud.call("gear_text"))
	# ---- THE HAMMER ----------------------------------------------------------------
	run.set("hammer_override", 1)
	run.call("_process", 0.5)
	var swinging: bool = bool(run.call("hammering")) and float(run.call("forging_share")) > 0.0 \
		and str(hud.call("gear_text")).begins_with("Forging the helm")
	for i in 22:
		run.call("_process", 0.5)
	var not_yet: bool = int(run.get("pieces")) == 0
	run.call("_process", 0.51)
	check("standing still at the anvil holding the interact key the hammer swings (a ring fills, \"Forging the helm\"); a warrior's piece takes %d s" % int(Run.PIECE_OTHER),
		swinging and not_yet and int(run.get("pieces")) == 1 and is_equal_approx(float(run.get("wade_left")), Run.WADE_OTHER)
		and str(hud.call("gear_text")).begins_with("Forging the chestplate"), [run.get("pieces"), run.get("forging"), hud.call("gear_text")])
	run.set("hammer_override", 0)
	run.call("_process", 1.0)
	var no_hand: bool = not bool(run.call("hammering")) and is_equal_approx(float(run.get("forging")), 0.0) \
		and str(hud.call("gear_text")).begins_with("Armour 1 of %d  -  4.0 s in the lava" % Run.PIECES.size())
	run.set("hammer_override", 1)
	body.set("velocity", Vector2(120, 0))
	run.call("_process", 1.0)
	var walking: bool = not bool(run.call("hammering"))
	body.set("velocity", Vector2.ZERO)
	body.global_position = c + Vector2(0, Run.FORGE_REACH + 20.0)
	run.call("_process", 1.0)
	var away: bool = not bool(run.call("hammering"))
	check("  nothing without the key held, while walking, or away from the anvil", no_hand and walking and away)
	body.global_position = c + Vector2(0, 20)
	run.set("class_override", "tank")
	run.set("forging", 0.0)
	for i in 12:
		run.call("_process", 0.5)
	run.call("_process", 0.01)
	check("  the tank's swings count fully: his piece takes %d s, and buys %d s in the lava a piece to anyone else's %d" % [int(Run.PIECE_TANK), int(Run.WADE_TANK), int(Run.WADE_OTHER)],
		int(run.get("pieces")) == 2 and is_equal_approx(float(run.call("wade_most")), 2.0 * Run.WADE_TANK)
		and Run.WADE_TANK >= 2.0 * Run.WADE_OTHER and Run.PIECE_OTHER >= 2.0 * Run.PIECE_TANK, [run.get("pieces"), run.call("wade_most")])
	run.set("hammer_override", 0)
	# ---- WADING ----------------------------------------------------------------------
	run.set("class_override", "warrior")
	run.set("pieces", 1)
	run.set("wade_left", Run.WADE_OTHER)
	var lava_spot: Vector2 = c + Vector2(0, -(Run.RADIUS + 60.0))
	body.global_position = lava_spot
	(body.get("taken") as Array).clear()
	for i in 7:
		run.call("_process", 0.5)
	var dry: bool = (body.get("taken") as Array).is_empty() and bool(run.call("in_lava", lava_spot))
	for i in 3:
		run.call("_process", 0.5)
	var burnt: bool = not (body.get("taken") as Array).is_empty() and is_equal_approx(float(run.get("wade_left")), 0.0)
	body.global_position = c + Vector2(0, 20)
	run.call("_process", 1.0)
	var refilled: float = float(run.get("wade_left"))
	check("a piece is %d s in the lava before the fire starts - every class burns once it is spent - and the time comes back on the floor (%s a second)" % [int(Run.WADE_OTHER), Run.WADE_REFILL],
		dry and burnt and is_equal_approx(refilled, minf(Run.WADE_OTHER, Run.WADE_REFILL)), [dry, burnt, refilled])
	# ---- FIRE BITES HIM LESS -------------------------------------------------------
	run.set("class_override", "tank")
	var tank_fire: float = float(run.call("hit_scale", body, Element.Type.FIRE))
	var tank_plain: float = float(run.call("hit_scale", body, Element.Type.NONE))
	body.global_position = Vector2(-90000, -90000)
	var tank_away: float = float(run.call("hit_scale", body, Element.Type.FIRE))
	body.global_position = c + Vector2(0, 20)
	run.set("class_override", "warrior")
	var warrior_fire: float = float(run.call("hit_scale", body, Element.Type.FIRE))
	check("the tank's fire hits on the island land at %d%% - sprites, lava, rocks; not off the island, not other hits, not other classes; Player.damage_taken() asks it" % roundi(Run.TANK_FIRE * 100.0),
		is_equal_approx(tank_fire, Run.TANK_FIRE) and tank_plain == 1.0 and tank_away == 1.0 and warrior_fire == 1.0
		and _func_body(_code_src("res://src/characters/player.gd"), "func damage_taken(").contains("minigame_hit_scale(element)"),
		[tank_fire, tank_plain, tank_away, warrior_fire])
	# ---- THE VOLCANO ERUPTS --------------------------------------------------------
	run.set("pieces", 0)
	run.set("wade_left", 0.0)
	run.set("floods", Run.SLICES)
	(body.get("taken") as Array).clear()
	(body.get("shakes") as Array).clear()
	run.call("_process", Run.ERUPT_FIRST + 0.01)
	var thrown: Array = run.get("rocks")
	var meteor: Node2D = thrown[0]["meteor"] as Node2D if not thrown.is_empty() else null
	check("with every slice gone the volcano throws its first rock: a glowing circle, and the mage's meteor %s times as big falling onto it - a picture that hits nothing itself" % Run.ERUPT_SCALE,
		bool(run.call("volcano")) and thrown.size() == 1 and meteor != null and meteor.get_parent() == island
		and meteor.get("cosmetic") == true and meteor.scale.is_equal_approx(Vector2.ONE * Run.ERUPT_SCALE)
		and absf(Meteor.HIT_RADIUS * Run.ERUPT_SCALE - Run.ERUPT_RADIUS) < 1.0
		and absf(float(meteor.get("delay")) + Meteor.FALL_SECONDS - Run.ERUPT_WARN) < 0.001
		and (body.get("taken") as Array).is_empty(), [thrown.size(), meteor])
	run.set("rocks", [])
	run.set("_erupt_clock", 9999.0)
	(body.get("shakes") as Array).clear()
	run.call("throw_rock", body.global_position + Vector2(Run.ERUPT_RADIUS - 10.0, 0))
	run.call("throw_rock", body.global_position + Vector2(Run.ERUPT_RADIUS + 20.0, 0))
	run.call("_process", Run.ERUPT_WARN + 0.01)
	var hits: Array = body.get("taken")
	var first_hit: int = int(hits[0][0]) if hits.size() == 1 else -1
	check("  a rock landing within %d px hits for %d%% of your health as fire (one did, of two) and jolts the screen; one past it does not hit" % [int(Run.ERUPT_RADIUS), roundi(Run.ERUPT_HIT * 100.0)],
		hits.size() == 1 and int(hits[0][1]) == Element.Type.FIRE and first_hit == roundi(200 * Run.ERUPT_HIT + 200 * Run.ERUPT_HIT_STEP)
		and int(run.get("rocks_fallen")) == 2 and not (body.get("shakes") as Array).is_empty()
		and float((body.get("shakes") as Array)[0][0]) > Run.RUMBLE_MOST, [hits, body.get("shakes")])
	run.set("volcano_seconds", Run.ERUPT_MORE_EVERY * 2.0 + 1.0)
	run.set("rocks_fallen", 200)
	check("  faster and more: the gap shrinks to %s s, a volley grows a rock every %d s, each rock hits harder, and the screen rumbles harder (to %d px)" % [Run.ERUPT_FASTEST, int(Run.ERUPT_MORE_EVERY), int(Run.RUMBLE_MOST)],
		is_equal_approx(float(run.call("erupt_gap")), Run.ERUPT_FASTEST) and int(run.call("volley_size")) == 3
		and float(run.call("erupt_hit")) > Run.ERUPT_HIT and bool(run.call("rumbling"))
		and float(run.call("rumble_px")) > Run.RUMBLE_PX)
	(body.get("shakes") as Array).clear()
	run.set("_jolt_left", 0.0)
	run.call("_process", Run.RUMBLE_EVERY + 0.01)
	var rumbled: bool = not (body.get("shakes") as Array).is_empty()
	run.set("floods", Run.SLICES - 1)
	run.set("flooding", -1)
	check("  the ground rumbles while the volcano throws (and from the last flood), not before",
		rumbled and not bool(run.call("rumbling")))
	run.set("floods", Run.SLICES)
	run.call("throw_rock", c)
	var flying: Node = (run.get("rocks") as Array)[0]["meteor"]
	var caught: bool = bool(run.call("knock_out", body))
	check("  a fall ends it: no rock left in the air, the armour gone for the next run, the result counts it",
		caught and (run.get("rocks") as Array).is_empty() and int(run.get("pieces")) == 0
		and is_instance_valid(flying) and flying.is_queued_for_deletion())
	# ---- THE ISLAND IS WIPED (0.122.0): the owner, "we need the giant impact
	# to wipe the field at the end", "you know the field wipe on mages minigame".
	run.call("start_run")
	run.set("_spawn_clock", 9999.0)
	run.set("_essence_clock", 9999.0)
	run.set("floods", Run.SLICES)
	var stand_in := Node2D.new()
	stand_in.name = "standinsprite"
	island.add_child(stand_in)
	stand_in.global_position = c + Vector2(150, 0)
	stand_in.reset_physics_interpolation()
	stand_in.tree_exiting.connect(Callable(run, "_on_monster_gone").bind(stand_in))
	(run.get("monsters") as Array).append(stand_in)
	run.set("volcano_seconds", Run.FINALE_AT - Run.FINALE_FALL - 0.01)
	run.set("_erupt_clock", 9999.0)
	run.call("_process", 0.05)
	var first_shadow: float = float(run.call("finale_shadow"))
	var high: Vector2 = hud.call("heart_at", 0.0)
	var low: Vector2 = hud.call("heart_at", 1.0)
	run.set("volcano_seconds", Run.FINALE_AT - Run.FINALE_FALL * 0.3)
	var later_shadow: float = float(run.call("finale_shadow"))
	check("%d s into the volcano it throws its heart: \"The volcano throws its heart!\", a giant rock falling on the screen from over its top edge onto the anvil, its shadow growing out from the anvil, the ground shaking harder" % int(Run.FINALE_AT - Run.FINALE_FALL),
		str(run.get("finale")) == "falling" and str(hud.get("banner").text) == "The volcano throws its heart!"
		and bool(hud.call("heart_falling")) and hud.get("heart") is Control and high.y < 0.0 and high.y < low.y - 200.0
		and first_shadow < 120.0 and later_shadow > first_shadow * 3.0 and float(run.call("rumble_px")) >= Run.RUMBLE_MOST
		and (run.get("_sky") as Node2D).z_index == Run.SKY_Z, [run.get("finale"), first_shadow, later_shadow, high, low])
	run.set("_spawn_clock", 0.0)
	var alive_before: int = (run.get("monsters") as Array).size()
	run.call("_process", 0.01)
	check("  no fire sprite steps out once the heart is thrown", (run.get("monsters") as Array).size() == alive_before)
	run.set("volcano_seconds", Run.FINALE_AT - 0.5)
	run.set("_erupt_clock", 0.0)
	run.call("_process", 0.01)
	var no_rain: bool = (run.get("rocks") as Array).is_empty()
	(body.get("shakes") as Array).clear()
	run.call("_process", 0.6)
	var jolts: Array = body.get("shakes")
	check("  the rain stops %s s before; the heart lands on the anvil - every fire sprite gone in a blast, a white flash, the hardest jolt (%d px)" % [Run.RAIN_STOPS, int(Run.FINALE_SHAKE.x)],
		no_rain and str(run.get("finale")) == "landed" and (run.get("monsters") as Array).is_empty()
		and stand_in.is_queued_for_deletion() and float(hud.get("_flash_left")) > 0.0
		and str(hud.get("banner").text) == "The island is wiped!"
		and not jolts.is_empty() and is_equal_approx(float(jolts[0][0]), Run.FINALE_SHAKE.x)
		and float(run.get("finale_afterglow")) > 0.0, [run.get("finale"), jolts])
	body.set("hp", 150)
	run.call("_process", Run.FINALE_HOLD + 0.01)
	check("  %s s later the run is over for everyone still standing: \"The volcano took the island at ...\"" % Run.FINALE_HOLD,
		int(run.get("state")) == Run.State.WAITING and str(run.get("last_result")).begins_with("The volcano took the island at")
		and int(body.get("hp")) == 1 and str(run.get("finale")) == "" and not bool(run.get("_wiped")), run.get("last_result"))
	check("the HUD's gear line: the key to hold before the first piece, nothing between runs; \"The volcano erupts\" over the heat bar",
		hint.begins_with("Hold ") and hint.ends_with("at the anvil to forge armour") and str(hud.call("gear_text")) == ""
		and _func_body(_code_src("res://src/world/forge/forgehud.gd"), "func paint(").contains("The volcano erupts"), hint)
	island.queue_free()
	await get_tree().process_frame
	print("  the Forge's gear: the hammer, wading, the tank's fire, the eruption")


# =============================================================================
# THE STORIES (0.123.0)
# =============================================================================
# The owner, of the Stand: "after the mages minigame there is a story where
# the mages were trying to stop a volcano from erupting by sealing it with
# meteors ..."; and of the Forge, "did you already get the tanks lore?" - "the
# tank lived generations making armor but eventually fate decided the lava
# would rise ...".

func _test_the_stories_of_the_stand_and_the_forge() -> void:
	section("THE STORIES (0.123.0): the mages' sealing when the Stand's portal falls, the smith's when you first reach the Forge, the warrior's when you first enter the Descent")
	const Descent := preload("res://src/world/descent/descentrun.gd")
	const StandScreen := preload("res://src/world/magestand/magestandscreen.gd")
	const Run := preload("res://src/world/forge/forgerun.gd")
	const FieldScript := preload("res://src/world/field.gd")
	var key: String = FieldScript.story_key()
	var cfg := ConfigFile.new()
	cfg.load(ControlsPanel.seen_path)
	for k in [StandScreen.STORY_KEY, Run.STORY_KEY, Descent.STORY_KEY]:
		if cfg.has_section_key("story", (key + k).replace("/", "|")):
			cfg.erase_section_key("story", (key + k).replace("/", "|"))
	cfg.save(ControlsPanel.seen_path)
	# ---- THE SEALING -------------------------------------------------------------
	var screen: CanvasLayer = StandScreen.open(get_tree())
	await get_tree().process_frame
	var stand: Node = screen.get("run")
	var wired: bool = stand != null and stand.is_connected("finished", Callable(screen, "_on_stand_over"))
	screen.call("tell_story")
	var told: Node = screen.get("story")
	check("when the Stand's portal falls the mages' story plays over it, in the game's story screen - five lines, the owner's",
		wired and told is StoryScreen and told.get_parent() == screen and (told.get("_blocks") as Array) == StandScreen.STORY
		and StandScreen.STORY.size() == 5 and str(StandScreen.STORY[2]).contains("the volcano erupted")
		and str(StandScreen.STORY[4]).contains("parallel dimensions"), [wired, told])
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	screen.call("_input", esc)
	check("  while it plays every key is the story's (any key skips it) - Escape does not leave the Stand under it; remembered for the character",
		is_instance_valid(screen) and not screen.is_queued_for_deletion() and FieldScript.story_seen(key + StandScreen.STORY_KEY))
	told.call("_finish")
	await get_tree().process_frame
	screen.call("_on_stand_over")
	await get_tree().process_frame
	check("  once a character: the next fall tells it no more",
		screen.get("story") == null or not is_instance_valid(screen.get("story")))
	screen.call("close")
	await get_tree().process_frame
	# ---- THE SMITH -------------------------------------------------------------------
	var kept_scene: Node = get_tree().current_scene
	var island := Node2D.new()
	island.name = "forgestoryisland"
	get_tree().root.add_child(island)
	get_tree().current_scene = island
	var run: Node = Run.new()
	run.name = "forgerun"
	island.add_child(run)
	await get_tree().process_frame
	await get_tree().process_frame
	var smith: Node = null
	for child in island.get_children():
		if child is StoryScreen:
			smith = child
	check("the first time a character reaches the Forge the smith's story is told - four lines, the owner's, and remembered",
		smith != null and (smith.get("_blocks") as Array) == Run.STORY and Run.STORY.size() == 4
		and str(Run.STORY[1]).contains("lava would rise") and FieldScript.story_seen(key + Run.STORY_KEY), smith)
	island.queue_free()
	await get_tree().process_frame
	var island2 := Node2D.new()
	get_tree().root.add_child(island2)
	get_tree().current_scene = island2
	var run2: Node = Run.new()
	island2.add_child(run2)
	await get_tree().process_frame
	await get_tree().process_frame
	var again: bool = island2.get_children().any(func(n: Node) -> bool: return n is StoryScreen)
	var stand_in: Node = Run.new()
	stand_in.set("player_override", Node2D.new())
	check("  once a character; and never on a suite's stand-in island (a player handed in, or not the scene being played)",
		not again and not bool(stand_in.call("tells_story")))
	(stand_in.get("player_override") as Node).free()
	stand_in.free()
	island2.queue_free()
	await get_tree().process_frame
	# ---- THE WARRIOR -----------------------------------------------------------------
	var crypt := Node2D.new()
	crypt.name = "descentstorycrypt"
	get_tree().root.add_child(crypt)
	get_tree().current_scene = crypt
	var descent: Node = Descent.new()
	descent.name = "descentrun"
	crypt.add_child(descent)
	await get_tree().process_frame
	await get_tree().process_frame
	var warrior: Node = null
	for child in crypt.get_children():
		if child is StoryScreen:
			warrior = child
	var stand_in_descent: Node = Descent.new()
	stand_in_descent.set("player_override", Node2D.new())
	check("the first time a character enters the Descent the warrior's story is told - five lines, the owner's, remembered; never on a stand-in",
		warrior != null and (warrior.get("_blocks") as Array) == Descent.STORY and Descent.STORY.size() == 5
		and str(Descent.STORY[3]).contains("It was a trap") and str(Descent.STORY[4]).contains("unlimited stamina or magic")
		and FieldScript.story_seen(key + Descent.STORY_KEY) and not bool(stand_in_descent.call("tells_story")), warrior)
	(stand_in_descent.get("player_override") as Node).free()
	stand_in_descent.free()
	crypt.queue_free()
	get_tree().current_scene = kept_scene
	await get_tree().process_frame
	print("  the stories: the sealing, the smith, the warrior")


# =============================================================================
# THE GUARDIAN (0.132.0)
# =============================================================================
# The owner, of the healer: "a guardian of light; in search of her mythic
# weapon ... she only cares to carve a path with her laser".

func _test_the_guardians_story() -> void:
	section("THE GUARDIAN (0.132.0): the healer's story the first time a character opens the Healer's Run")
	const HRScreen := preload("res://src/world/healerrun/healerrunscreen.gd")
	const FieldScript := preload("res://src/world/field.gd")
	var key: String = FieldScript.story_key() + HRScreen.STORY_KEY
	var cfg := ConfigFile.new()
	cfg.load(ControlsPanel.seen_path)
	if cfg.has_section_key("story", key.replace("/", "|")):
		cfg.erase_section_key("story", key.replace("/", "|"))
	cfg.save(ControlsPanel.seen_path)
	var bare: CanvasLayer = HRScreen.open(get_tree(), 3)
	await get_tree().process_frame
	check("a suite's bare screen (no HUD) tells no story",
		not bool(bare.call("story_playing")) and not FieldScript.story_seen(key))
	bare.call("close")
	await get_tree().process_frame
	var stand_hud := Node.new()
	stand_hud.name = "guardianstoryhud"
	get_tree().root.add_child(stand_hud)
	var screen: CanvasLayer = HRScreen.open(get_tree(), 3, 0, {}, stand_hud)
	await get_tree().process_frame
	var told: Node = screen.get("story")
	var run: Node = screen.get("run")
	check("opened from the card the healer's story plays over the run - five lines, the owner's, in the story screen; the run waits on its tutorial; remembered",
		told is StoryScreen and told.get_parent() == screen and (told.get("_blocks") as Array) == HRScreen.STORY
		and HRScreen.STORY.size() == 5 and str(HRScreen.STORY[0]).contains("guardian of light")
		and str(HRScreen.STORY[1]).contains("not supposed to exist in this dimension")
		and str(HRScreen.STORY[4]).contains("carve a path with her laser")
		and (screen.get("tutorial") as Control).visible and run != null and not run.is_processing()
		and FieldScript.story_seen(key), told)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	screen.call("_input", esc)
	await get_tree().process_frame
	check("  any key skips it - Escape too, which does not leave the run under it; the tutorial waits",
		not bool(screen.call("story_playing")) and is_instance_valid(screen) and not screen.is_queued_for_deletion()
		and (screen.get("tutorial") as Control).visible)
	screen.call("close")
	await get_tree().process_frame
	var again: CanvasLayer = HRScreen.open(get_tree(), 3, 0, {}, stand_hud)
	await get_tree().process_frame
	check("  once a character: the next open tells it no more", not bool(again.call("story_playing")))
	again.call("close")
	stand_hud.queue_free()
	await get_tree().process_frame
	print("  the guardian's story")


# =============================================================================
# THE SHOPKEEPER TALKS (0.132.0)
# =============================================================================
# The owner: "lets make one for the shop saying 'are you lost? I make a living
# buying and selling gear; Welcome to Elusionrpg! its rare travelers have
# money but I make do.'", then "we can make multiple chat bubbles for when a
# player walks in again".

func _test_the_shopkeeper_talks() -> void:
	section("THE SHOPKEEPER TALKS (0.132.0): a speech bubble a line at a time; the first meeting's greeting, then the rest in turn")
	const Bubble := preload("res://src/shared/speechbubble.gd")
	const Keeper := preload("res://src/world/shopkeeperanim.gd")
	var greetings: Array = Keeper.GREETINGS
	var n: int = greetings.size()
	check("the first meeting is the owner's four lines; then each greeting in turn, round again after the last",
		(greetings[0] as Array).size() == 4 and str(greetings[0][0]) == "Are you lost?"
		and str(greetings[0][3]).contains("but I make do")
		and Keeper.greeting_for(0) == greetings[0] and Keeper.greeting_for(1) == greetings[1]
		and Keeper.greeting_for(n - 1) == greetings[n - 1] and Keeper.greeting_for(n) == greetings[1], n)
	# ---- the bubble -----------------------------------------------------------------
	var holder := Node2D.new()
	add_child(holder)
	var said: Array = []
	var bubble: Node2D = Bubble.say(holder, ["Hello there.", "A second, longer line that has to wrap round onto another row."], Vector2(0, -27))
	bubble.connect("finished", func() -> void: said.append(true))
	var words: Label = bubble.get("label")
	check("a bubble sits on who says it, its tail's tip where it was asked, over the room, typing its first line",
		bubble.get_parent() == holder and bubble.position == Vector2(0, -27) and bubble.z_index == Bubble.Z
		and not bubble.z_as_relative and words.text == "Hello there." and words.visible_characters == 0)
	bubble.call("_process", 0.1)
	var typing: int = words.visible_characters
	bubble.call("_process", 5.0)
	bubble.call("_process", 5.0)
	var second: String = words.text
	bubble.call("_process", 5.0)
	var wrapped: bool = words.get_line_count() >= 2
	var paper: Rect2 = bubble.call("box")
	check("  it types, holds, then says the next line; the paper fits a wrapped line's rows",
		typing > 0 and typing < 12 and second.begins_with("A second") and wrapped
		and paper.size.y >= (bubble.get("words_size") as Vector2).y * Bubble.SCALE
		and paper.end.y <= 0.0, [typing, second, paper])
	bubble.call("_process", 5.0)
	bubble.call("_process", 1.0)
	check("  after the last line it fades, says it is finished, and goes",
		said.size() == 1 and bubble.is_queued_for_deletion())
	holder.queue_free()
	# ---- the shopkeeper -------------------------------------------------------------
	var key: String = Keeper.talk_key()
	var cfg := ConfigFile.new()
	cfg.load(ControlsPanel.seen_path)
	if cfg.has_section_key("talk", key.replace("/", "|")):
		cfg.erase_section_key("talk", key.replace("/", "|"))
	cfg.save(ControlsPanel.seen_path)
	var area := Area2D.new()
	var keeper := AnimatedSprite2D.new()
	var frames := SpriteFrames.new()
	frames.add_animation(Keeper.IDLE_ANIM)
	frames.add_animation(Keeper.WAVE_ANIM)
	keeper.sprite_frames = frames
	area.add_child(keeper)
	keeper.set_script(Keeper)
	add_child(area)
	await get_tree().process_frame
	var visitor := CharacterBody2D.new()
	visitor.add_to_group("player")
	keeper.call("_on_body_entered", visitor)
	var first: Node2D = keeper.get("bubble")
	check("walking up to him: the first meeting's greeting over his head, counted for the character",
		first != null and first.get_parent() == keeper and first.position == Keeper.BUBBLE_AT
		and first.get("lines") == greetings[0] and Bubble.times_said(key) == 1)
	keeper.call("_on_body_entered", visitor)
	var same: bool = keeper.get("bubble") == first and Bubble.times_said(key) == 1
	first.free()
	keeper.call("greet")
	var none_soon: bool = keeper.get("bubble") == null or not is_instance_valid(keeper.get("bubble"))
	keeper.set("_last_greeting", -1000.0)
	keeper.call("greet")
	var next: Node2D = keeper.get("bubble")
	check("  not again while he is talking, nor soon after; the next arrival is the next greeting",
		same and none_soon and next != null and next.get("lines") == greetings[1] and Bubble.times_said(key) == 2)
	var rock := Node2D.new()
	next.free()
	keeper.set("_last_greeting", -1000.0)
	keeper.call("_on_body_entered", rock)
	check("  a monster crossing the shop is not talked to",
		keeper.get("bubble") == null or not is_instance_valid(keeper.get("bubble")))
	rock.free()
	visitor.free()
	area.queue_free()
	await get_tree().process_frame
	print("  the shopkeeper talks")


# =============================================================================
# IMMUNE TO EFFECTS (0.133.0)
# =============================================================================
# The owner: "i need a immune to effects option in gm panel".

func _test_immune_to_effects() -> void:
	section("IMMUNE TO EFFECTS (0.133.0): the GM panel's switch beside God mode - no effect starts, no element stacks; damage still lands")
	const FX := preload("res://src/characters/statuseffects.gd")
	const Boons := preload("res://src/world/descent/descentboons.gd")
	var was_role: String = Api.role
	var was_immune: bool = GameState.immune_effects
	var host := Node2D.new()
	add_child(host)
	var fx: Node = FX.attach(host)
	await get_tree().process_frame
	Api.role = "owner"
	GameState.immune_effects = false
	var chilled: bool = FX.apply_to(host, FX.CHILL)
	fx.call("clear_all")
	GameState.immune_effects = true
	var kinds_refused: bool = true
	for kind in [FX.CHILL, FX.BURN, FX.SOAKED, FX.SHOVE, FX.ROOT, FX.DAZZLE, FX.WITHER]:
		if FX.apply_to(host, kind, 10, Vector2(5, 5)):
			kinds_refused = false
	fx.call("pull", Vector2(50, 0), 1.0, 40.0)
	check("off, an effect starts; on, none does - chill, burn, soaked, shove, root, dazzle, wither, and no pull",
		chilled and kinds_refused and (fx.call("active") as Array).is_empty(), fx.call("active"))
	Api.role = "player"
	var player_chilled: bool = FX.apply_to(host, FX.CHILL)
	check("  the owner's alone: the rank is asked with every effect, not only at the switch",
		player_chilled and not FX.immune())
	fx.call("clear_all")
	Api.role = "owner"
	var stacks_before: Dictionary = (Boons.stacks as Dictionary).duplicate()
	var player_src: String = _code_src("res://src/characters/player.gd")
	check("  and no element stacks in the Descent: player.gd counts a hit's element only when not immune",
		_func_body(player_src, "func take_damage(").contains("if not StatusEffects.immune():\n\t\tDescentBoons.note_element(element)"))
	Boons.stacks = stacks_before
	# ---- the switch -----------------------------------------------------------------
	GameState.immune_effects = false
	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var god: Node = gm.get_node_or_null("%godmodebutton")
	var immune: CheckButton = gm.get_node_or_null("%immunebutton") as CheckButton
	check("the switch sits beside God mode on the Testing tab",
		immune != null and god != null and immune.get_parent().get_parent() == god.get_parent().get_parent()
		and str(immune.get_parent().get_parent().name) == "switchgrid"
		and immune.get_parent().get_index() == god.get_parent().get_index() + 1)
	if immune != null:
		gm.call("_sync_god_mode_button")
		host.add_to_group("player")
		FX.apply_to(host, FX.BURN, 10)
		Api.role = "owner"
		immune.button_pressed = true
		var on_clears: bool = GameState.immune_effects and (fx.call("active") as Array).is_empty()
		immune.button_pressed = false
		var off_again: bool = not GameState.immune_effects
		Api.role = "player"
		gm.call("_on_immune_toggled", true)
		check("  on, it clears what is on you; off again; and pressed by anybody below the owner it does nothing",
			on_clears and off_again and not GameState.immune_effects and not immune.button_pressed)
	gm.queue_free()
	host.queue_free()
	Api.role = was_role
	GameState.immune_effects = was_immune
	await get_tree().process_frame
	print("  immune to effects")


# =============================================================================
# THE SWARM RUNS LIGHTER (0.133.0)
# =============================================================================
# The owner's phone, stage 14 of the Endless, 2,930 slimes: 6-7 fps. With a
# camera (the game) only the slimes on screen are written and drawn, and a
# slime past FAR_REACH from every player moves one step in FAR_EVERY, that
# many strides at once.

func _test_the_swarm_runs_lighter() -> void:
	section("THE SWARM RUNS LIGHTER (0.133.0): only what is on screen is drawn; far ones move in turns")
	const SwarmScript := preload("res://src/world/endless/swarm.gd")
	var world := Node2D.new()
	add_child(world)
	var swarm: Node2D = SwarmScript.new()
	swarm.set("arena", Rect2(0, 0, 3000, 1400))
	world.add_child(swarm)
	await get_tree().process_frame
	swarm.set_process(false)
	swarm.set_physics_process(false)
	swarm.call("spawn", 2, Vector2(-9999, -9999))
	var px: PackedFloat32Array = swarm.get("px")
	var py: PackedFloat32Array = swarm.get("py")
	px[0] = 300.0
	py[0] = 300.0
	px[1] = 2600.0
	py[1] = 300.0
	swarm.set("px", px)
	swarm.set("py", py)
	swarm.call("_write_buffer")
	var bare: int = int(swarm.get("drawn"))
	var cam := Camera2D.new()
	cam.position = Vector2(300, 300)
	world.add_child(cam)
	cam.make_current()
	await get_tree().process_frame
	swarm.call("_write_buffer")
	var with_cam: int = int(swarm.get("drawn"))
	var shown: int = (swarm.get("_mesh") as MultiMeshInstance2D).multimesh.visible_instance_count
	check("with no camera every slime is drawn; with one, only those on screen",
		bare == 2 and with_cam == 1 and shown == 1, [bare, with_cam, shown])
	var near_moves: int = 0
	var far_moves: int = 0
	var far_most: float = 0.0
	for k in SwarmScript.FAR_EVERY * 2:
		var was_near: Vector2 = Vector2((swarm.get("px") as PackedFloat32Array)[0], (swarm.get("py") as PackedFloat32Array)[0])
		var was_far: Vector2 = Vector2((swarm.get("px") as PackedFloat32Array)[1], (swarm.get("py") as PackedFloat32Array)[1])
		swarm.call("_step", Vector2(500, 300), true)
		var now_near: Vector2 = Vector2((swarm.get("px") as PackedFloat32Array)[0], (swarm.get("py") as PackedFloat32Array)[0])
		var now_far: Vector2 = Vector2((swarm.get("px") as PackedFloat32Array)[1], (swarm.get("py") as PackedFloat32Array)[1])
		if now_near.distance_to(was_near) > 0.01:
			near_moves += 1
		if now_far.distance_to(was_far) > 0.01:
			far_moves += 1
			far_most = maxf(far_most, now_far.distance_to(was_far))
	var stride: float = float(swarm.get("speed")) * SwarmScript.STEP
	check("  a near slime moves every step; a far one one step in FAR_EVERY, that many strides at once",
		near_moves == SwarmScript.FAR_EVERY * 2 and far_moves == 2 and far_most > stride * 1.2,
		[near_moves, far_moves, far_most, stride])
	cam.queue_free()
	world.queue_free()
	await get_tree().process_frame
	# PHONES HOLD THE CROWD: a phone, or a party with one, fills to 1,000.
	const RunScript := preload("res://src/world/endless/endlessrun.gd")
	const PartyScript := preload("res://src/world/endless/endlessparty.gd")
	var run: Node = RunScript.new()
	run.set("stage", 30)
	run.set("players", 1)
	var was_phone: bool = RunScript.pretend_phone
	RunScript.pretend_phone = false
	var full: int = int(run.call("crowd_now"))
	RunScript.pretend_phone = true
	var held: int = int(run.call("crowd_now"))
	RunScript.pretend_phone = false
	var party: Node = PartyScript.new()
	var link := Node.new()
	var stub := GDScript.new()
	stub.source_code = "extends Node\nfunc runs() -> bool:\n\treturn true\nfunc sharers() -> int:\n\treturn 1\nfunc leader_for(_a) -> int:\n\treturn 1\nfunc my_id() -> int:\n\treturn 1\nfunc remotes() -> Dictionary:\n\treturn {7: true}\n"
	stub.reload()
	link.set_script(stub)
	party.set("link", link)
	run.set("party", party)
	party.set("_members", {7: [1, 0, 0]})
	var party_pc: int = int(run.call("crowd_now"))
	party.set("_members", {7: [1, 0, 1]})
	var party_phone: int = int(run.call("crowd_now"))
	party.set("_members", {7: [1, 0]})
	var old_game: bool = bool(party.call("any_phone"))
	check("a phone fills the Endless to 1,000; so does a party with one in it; a computer alone, the whole crowd",
		full > RunScript.PHONE_CROWD and held == RunScript.PHONE_CROWD
		and party_pc == RunScript.crowd_for(30, 1) and party_phone == RunScript.PHONE_CROWD and not old_game,
		[full, held, party_pc, party_phone])
	RunScript.pretend_phone = was_phone
	run.free()
	party.free()
	link.free()
	print("  the swarm runs lighter")


# =============================================================================
# THE CROWNED, REMADE (0.134.0) - step 1 of CROWNED_PLAN.txt
# =============================================================================
# The owner: "we remake the last boss and the area in the final boss room",
# "a beholder is a master of illusions", "lets try it out and see what happens".

func _test_the_crowned_remade() -> void:
	section("THE CROWNED, REMADE (0.134.0): the room rebuilt, the Seven Crowns, the decoy eyes")
	const Fight := preload("res://src/world/crowned/crownedfight.gd")
	const Decoy := preload("res://src/world/crowned/crowneddecoy.gd")
	const Builder := preload("res://src/tools/buildcrowned.gd")
	# ---- the room -----------------------------------------------------------------
	var packed: PackedScene = load("res://scene/boss.tscn") as PackedScene
	var room: Node = packed.instantiate()
	var fight_node: Node = room.get_node_or_null("crownedfight")
	var boss_node: Node2D = room.get_node_or_null("ysortworld/enemies/bossenemy") as Node2D
	var walls: int = 0
	for piece in room.get_node("ysortworld/props").get_children():
		if str(piece.scene_file_path).begins_with("res://scene/crypt/wall") or str(piece.scene_file_path).ends_with("pillar.tscn"):
			walls += 1
	var floor_rect: Rect2 = fight_node.get("room_rect") if fight_node != null else Rect2()
	check("the Crowned's room is built by buildcrowned.gd: walled all round, the fight's node with its floor and seven lights, the Crowned where the server has it",
		fight_node != null and fight_node.get_script() == Fight and walls == 59
		and (fight_node.get("light_spots") as PackedVector2Array).size() == 7
		and floor_rect.size.x > 1000.0 and floor_rect.size.y > 700.0
		and boss_node != null and boss_node.position == Vector2(-400, 100)
		and floor_rect.has_point(boss_node.position), [walls, floor_rect])
	room.free()
	var widths_back: int = 0
	for w in Builder.wall_widths(Builder.BACK_MIDDLE):
		widths_back += int(w)
	var widths_front: int = 0
	for w in Builder.wall_widths(Builder.FRONT_MIDDLE):
		widths_front += int(w)
	check("  its walls end to end: the back 997 between its corners, the front 996, each the same read either way",
		widths_back == 997 and widths_front == 996
		and Builder.wall_widths(Builder.BACK_MIDDLE) == _reversed(Builder.wall_widths(Builder.BACK_MIDDLE))
		and Builder.wall_widths(Builder.FRONT_MIDDLE) == _reversed(Builder.wall_widths(Builder.FRONT_MIDDLE)))
	check("  the crowns in the bands' order, CROWN_SECONDS each, round again",
		Fight.CROWN_ORDER.size() == 7 and int(Fight.CROWN_ORDER[0]) == Element.Type.LIGHT
		and int(Fight.CROWN_ORDER[6]) == Element.Type.DARK and Fight.crown_at(0.0) == 0
		and Fight.crown_at(Fight.CROWN_SECONDS + 0.1) == 1 and Fight.crown_at(Fight.CROWN_SECONDS * 7.0 + 0.1) == 0)
	# ---- the fight ----------------------------------------------------------------
	var world := Node2D.new()
	add_child(world)
	var enemies := Node2D.new()
	enemies.name = "enemies"
	world.add_child(enemies)
	var boss: Node2D = (load("res://scene/enemy/bossenemy.tscn") as PackedScene).instantiate() as Node2D
	boss.position = Vector2(500, 400)
	enemies.add_child(boss)
	boss.reset_physics_interpolation()
	boss.process_mode = Node.PROCESS_MODE_DISABLED
	var sprite: CanvasItem = boss.get_node("animatedsprite2d") as CanvasItem
	var worn: Material = sprite.material
	var fight: Node2D = Fight.new()
	fight.set("room_rect", Rect2(0, 0, 1000, 800))
	var spots := PackedVector2Array()
	for k in 7:
		spots.append(Vector2(60 + 120 * k, 60))
	fight.set("light_spots", spots)
	var me := Node2D.new()
	me.position = Vector2(300, 600)
	world.add_child(me)
	world.add_child(fight)
	fight.set("player_override", me)
	await get_tree().process_frame
	var quiet: bool = not bool(fight.get("fighting"))
	boss.set("engaged", true)
	fight.call("_process", 0.016)
	var lands: Node = fight.get("lands")
	check("turned on somebody, the fight begins in the Crown of Light: its kit, its colours, its light, its floor and weather, a banner",
		quiet and bool(fight.get("fighting")) and int(fight.get("crown")) == 0
		and int(boss.get("crown_land")) == Element.Type.LIGHT and int(boss.call("crown_or_element")) == Element.Type.LIGHT
		and boss.call("kit") == BossEnemy.KITS[Element.Type.LIGHT] and sprite.material != worn
		and float((fight.get("_light_want") as Array)[0]) == Fight.LIGHT_LIT
		and float((fight.get("_light_want") as Array)[1]) == Fight.LIGHT_DIM
		and (lands.get("env_lands") as Array) == [Element.Type.LIGHT]
		and str((fight.get("_banner") as Label).text) == "The Crown of Light", [fight.get("crown"), boss.get("crown_land")])
	fight.set("fight_clock", Fight.CROWN_SECONDS + 0.05)
	fight.call("_process", 0.016)
	check("  twelve seconds on, the Crown of Wind - and the last land lingers on the floor, so the two react",
		int(fight.get("crown")) == 1 and int(boss.get("crown_land")) == Element.Type.WIND
		and (lands.get("env_lands") as Array).has(Element.Type.WIND) and (lands.get("env_lands") as Array).has(Element.Type.LIGHT))
	var edge: Vector2 = fight.call("_edge_spot")
	check("  it hosts the lands' hazards: their player is this game's, an edge spot is in the room and clear of it",
		fight.call("_player") == me and Rect2(0, 0, 1000, 800).has_point(edge) and edge.distance_to(me.position) >= Fight.EDGE_CLEAR - 0.01)
	# ---- the illusions ------------------------------------------------------------
	var made: Array = fight.call("make_decoys", 2)
	var all_in: bool = made.size() == 2
	for decoy in made:
		all_in = all_in and (decoy as Node).is_in_group(&"enemies") and (decoy as Node).has_meta(Decoy.STRESS_MARK) \
			and (decoy as Node).get_parent() == enemies and Rect2(0, 0, 1000, 800).has_point((decoy as Node2D).global_position) \
			and bool((decoy as Node).call("can_be_aimed_at")) and (decoy as Node).get_node_or_null("healthbar") != null
	(made[0] as Node).call("take_damage", 40.0, 0)
	check("decoy eyes stand round it, among the monsters but never counted, wearing its health bar; a blow breaks one",
		all_in and bool((made[0] as Node).get("broken")) and not (made[0] as Node).is_in_group(&"enemies")
		and not bool((made[1] as Node).get("broken")))
	# ---- the crowns shed, and the fall ----------------------------------------------
	boss.set("hp", int(float(int(boss.get("max_hp"))) * 0.7))
	fight.call("_process", 0.016)
	# (Since 0.134.1 the Sealing follows at once - _test_the_crowned_falls_apart().)
	check("  under three quarters the crowns come off and the Sealing begins: the boss in fire, the floor's random hazards stopped",
		int(fight.get("crown")) == -1 and int(boss.get("crown_land")) == Element.Type.FIRE and sprite.material != worn
		and int((fight.get("phases") as Node).get("phase")) == 2 and (lands.get("env_lands") as Array).is_empty())
	boss.set("hp", 0)
	fight.call("_process", 0.016)
	var lit: bool = true
	for want in fight.get("_light_want"):
		lit = lit and float(want) == Fight.LIGHT_DONE
	check("  and when it falls every light burns, the decoys break, the fight is over",
		not bool(fight.get("fighting")) and bool(fight.get("won")) and lit and (fight.get("decoys") as Array).is_empty())
	world.queue_free()
	await get_tree().process_frame
	print("  the Crowned, remade")


func _reversed(list: Array) -> Array:
	var copy: Array = list.duplicate()
	copy.reverse()
	return copy



# =============================================================================
# THE DESCENT GOES DEEPER (0.123.0)
# =============================================================================
# The owner: "we need more enemies in the descent and we need more then 3
# levels we also make sure all bosses are hitting", then "we need more elites
# this needs to be super hard".
func _test_the_descent_goes_deeper() -> void:
	section("THE DESCENT GOES DEEPER (0.123.0): seven floors, one a land, more monsters and elites, keepers that call their floor")
	const RunScript := preload("res://src/world/descent/descentrun.gd")
	const Boons := preload("res://src/world/descent/descentboons.gd")
	# ---- the floors ----
	var keepers: Dictionary = {}
	var lands: Dictionary = {}
	var missing: Array = []
	for f in RunScript.FLOORS:
		keepers[str(f["keeper"])] = true
		lands[int(f["land"])] = true
		for id in (f["monsters"] as Array) + (f["elites"] as Array) + [f["keeper"]]:
			if not ResourceLoader.exists("res://scene/enemy/%s.tscn" % str(id)):
				missing.append(id)
	check("seven floors of %d rooms and a keeper, each keeper a different one of the seven bosses, the Fire Keeper first and the Dark last, every monster a scene the game has"
		% RunScript.ROOMS, RunScript.FLOORS.size() == 7 and RunScript.ROOMS == 4 and keepers.size() == 7 and missing.is_empty()
		and str(RunScript.FLOORS[0]["keeper"]) == "fireboss" and str(RunScript.FLOORS[6]["keeper"]) == "bossenemy",
		[keepers.keys(), missing])
	check("  every floor a land of its own, the Crypt none",
		lands.size() == 7 and int(RunScript.FLOORS[0]["land"]) == Element.Type.NONE)
	# ---- elites ----
	var probe: Node = RunScript.new()
	var by_floor: Array = []
	var calls: Array = []
	for f in RunScript.FLOORS.size():
		probe.set("floor_index", f)
		by_floor.append(int(probe.call("elites_for", "upgrade")))
		calls.append(int(probe.call("keeper_call_elites")))
	probe.set("floor_index", 0)
	var elite_room: int = int(probe.call("elites_for", "elite"))
	var none: bool = int(probe.call("elites_for", "treasure")) == 0 and int(probe.call("elites_for", "keeper")) == 0 \
		and int(probe.call("elites_for", "rest")) == 0
	probe.free()
	check("elites in every fight: %s down the floors, an elite room two more (%d), a Treasure, a Rest and the keeper's room none" % [by_floor, elite_room],
		by_floor == [1, 1, 2, 2, 3, 3, 4] and elite_room == 3 and none, by_floor)
	# ---- the keeper calls its floor ----
	var body_script := GDScript.new()
	body_script.source_code = "extends Node2D\nvar hp: int = 400\nvar max_hp: int = 400\n"
	body_script.reload()
	var made: Array = _descent_room_for_test(body_script)
	var room: Node2D = made[0]
	var run: Node = made[1]
	await get_tree().process_frame
	var doors: Array = run.get("doors")
	(doors[0] as Node).emit_signal("walked_in", doors[0])
	for i in 3:
		run.call("_process", RunScript.FADE_SECONDS)
	run.call("_clear_monsters")
	run.set("floor_index", 1)
	run.set("room", RunScript.ROOMS)
	run.call("_go", "keeper")
	for i in 3:
		run.call("_process", RunScript.FADE_SECONDS)
	run.call("_process", RunScript.FIGHT_DELAY + 0.1)
	var keeper: Node = run.get("_keeper")
	var alone: bool = (run.get("monsters") as Array).size() == 1 and keeper != null \
		and str(keeper.scene_file_path).ends_with("iceboss.tscn") and (run.get("_coming") as Array).is_empty()
	var wash: ColorRect = room.get_node_or_null("floorwash") as ColorRect
	var ice: Color = Element.colour_for(Element.Type.ICE)
	var washed: bool = wash != null and wash.color.is_equal_approx(Color(ice.r, ice.g, ice.b, RunScript.FLOOR_WASH)) \
		and is_equal_approx(Boons.floor_taken, float(RunScript.FLOORS[1]["keeper_taken"]) * RunScript.KEEPER_HARDER)
	run.call("_process", RunScript.KEEPER_CALL_FIRST)
	var called: Array = run.get("_coming")
	var called_elites: int = called.filter(func(e: Array) -> bool: return bool(e[3])).size()
	var told: String = str((run.get("hud").get("toast_label") as Label).text)
	check("the Ice Keeper comes alone on a floor washed blue, hitting at its floor's keeper_taken; %d seconds in it calls %d of its floor, an elite with them (%s)"
		% [int(RunScript.KEEPER_CALL_FIRST), called.size(), told],
		alone and washed and called.size() == RunScript.KEEPER_CALL_SIZE + 1 + 1 and called_elites == 1
		and told.contains("calls for help"), [alone, washed, called.size(), called_elites])
	run.call("_process", RunScript.MARK_SECONDS + 0.05)
	var with_help: int = (run.get("monsters") as Array).size()
	keeper.call("take_damage", 99999999)
	run.call("_process", 0.016)
	await get_tree().process_frame
	run.call("_process", 0.016)
	check("  they step out, and when the keeper falls they fall with it and the room is clear (%d were standing)" % with_help,
		with_help == 5 and int(run.call("living")) == 0 and int(run.get("state")) == RunScript.State.PICK,
		[with_help, run.call("living"), run.get("state")])
	run.set("floor_index", 0)
	run.call("_wash_floor")
	check("  and the Crypt is not washed", wash != null and is_instance_valid(wash) and is_zero_approx(wash.color.a))
	room.queue_free()
	Boons.clear()
	await get_tree().process_frame
	print("  the Descent goes deeper: done")


# =============================================================================
# THE LANDS SHINE: HAZARDS, DOUBLE KEEPERS, IMPOSSIBLE ROOMS, THE DEEP (0.124.0)
# =============================================================================
# Step 1 of DESCENT_PLAN_3.txt. The owner: "double bosses impossible rooms we
# need effects added also lets make those elements shine", "everyone has to
# die at some point", "fields should use the bosses elemental hazards in this
# minigame so the wind pushing the player tunnel vision etc".
func _test_the_lands_shine_in_the_descent() -> void:
	section("THE LANDS SHINE (0.124.0): each floor's keeper's hazards in its rooms, weather, double keepers, Impossible rooms, the Deep")
	const RunScript := preload("res://src/world/descent/descentrun.gd")
	const LandsScript := preload("res://src/world/descent/descentlands.gd")
	const Boons := preload("res://src/world/descent/descentboons.gd")
	const FieldScript := preload("res://src/world/field.gd")
	# ---- the numbers ----
	var gaps: Array = []
	var phases: Array = []
	for f in 8:
		gaps.append(LandsScript.gap(f))
		phases.append(LandsScript.phase_for(f))
	var weathers: int = 0
	for f in RunScript.FLOORS:
		var land: int = int(f["land"])
		weathers += 0 if LandsScript.weather_for(land if land != Element.Type.NONE else Element.Type.FIRE).is_empty() else 1
	check("a hazard every %s seconds down the floors, the kits' phases %s, the orbs' effects from %.2f to %.2f, every floor its weather"
		% [gaps, phases, LandsScript.effect_for(0), LandsScript.effect_for(7)],
		is_equal_approx(float(gaps[0]), LandsScript.GAP_FIRST) and float(gaps[7]) >= LandsScript.GAP_LEAST
		and float(gaps[6]) < float(gaps[0]) and phases == [0, 0, 0, 1, 1, 1, 2, 2]
		and LandsScript.effect_for(0) > FieldScript.FIELD_EFFECTS and is_equal_approx(LandsScript.effect_for(7), 1.0)
		and weathers == RunScript.FLOORS.size(), [gaps, phases])
	# ---- a room of stand-ins ----
	var body_script := GDScript.new()
	body_script.source_code = "extends Node2D\nvar hp: int = 400\nvar max_hp: int = 400\n"
	body_script.reload()
	var made: Array = _descent_room_for_test(body_script)
	var room: Node2D = made[0]
	var run: Node = made[1]
	await get_tree().process_frame
	var doors: Array = run.get("doors")
	(doors[0] as Node).emit_signal("walked_in", doors[0])
	for i in 3:
		run.call("_process", RunScript.FADE_SECONDS)
	run.call("_process", RunScript.FIGHT_DELAY + 0.1)
	var lands: Node2D = run.get("_lands")
	var weather: Node = lands.get_node_or_null("weather") if lands != null else null
	var first_calm: bool = lands != null and not bool(lands.call("active")) and weather is CPUParticles2D
	var felt: String = str(run.call("_room_line"))
	# Room 2 of the Frozen Halls: the Ice Keeper's hazards.
	run.call("_clear_monsters")
	run.set("floor_index", 1)
	run.set("room", 1)
	run.call("_go", "gold")
	for i in 3:
		run.call("_process", RunScript.FADE_SECONDS)
	run.call("_process", RunScript.FIGHT_DELAY + 0.1)
	var casters: Array = lands.get("_casters")
	var caster: Node2D = casters[0] if casters.size() == 1 else null
	var hidden: bool = caster != null and str(caster.scene_file_path).ends_with("iceboss.tscn") and not caster.visible \
		and not caster.is_in_group(&"enemies") and not caster.is_in_group(&"bosses") and not caster.is_physics_processing() \
		and caster.has_meta(&"stress_copy") and not (run.get("monsters") as Array).has(caster)
	check("the first room of a floor is calm, with the floor's weather and its line (%s); from the second, the floor's keeper throws its hazards - hidden, never a target, never counted"
		% felt, first_calm and felt.begins_with("The fire burns you") and hidden, [first_calm, caster])
	await get_tree().process_frame
	var skies: Array = lands.find_children("*", "CPUParticles2D", false, false)
	var snow: Color = LandsScript.weather_for(Element.Type.ICE)["colour"]
	check("  one floor's weather at a time: down in the Frozen Halls, its snow and not the Crypt's embers still (0.126.0)",
		skies.size() == 1 and (skies[0] as CPUParticles2D).color == snow and str(skies[0].name) == "weather",
		[skies.size(), skies.map(func(n: Node) -> Color: return (n as CPUParticles2D).color)])
	run.call("_process", LandsScript.FIRST)
	var warned: Array = lands.get("_warns")
	var marked: bool = warned.size() == 1 and str(warned[0][3]).begins_with("frost0") or warned.size() == 1 and str(warned[0][3]).begins_with("frost")
	var before: int = int(lands.get("thrown"))
	run.call("_process", LandsScript.WARN + 0.05)
	check("  %.1f seconds in, its volley is marked where it starts (%s), and %.1f seconds later it is thrown"
		% [LandsScript.FIRST, str(warned[0][3]) if not warned.is_empty() else "-", LandsScript.WARN],
		marked and int(lands.get("thrown")) == before + 1 and (lands.get("_warns") as Array).is_empty(), warned)
	_descent_kill_all(run)
	run.call("_process", 0.016)
	await get_tree().process_frame
	check("  and the hazards stop when the room is clear", not bool(lands.call("active")) and not is_instance_valid(caster))
	# ---- double keepers ----
	var probe: Node = RunScript.new()
	var counts: Array = []
	for f in 8:
		probe.set("floor_index", f)
		counts.append((probe.call("keepers_for") as Array).size())
	probe.set("floor_index", 3)
	var fourth: Array = probe.call("keepers_for")
	probe.set("floor_index", 6)
	var seventh: Array = probe.call("keepers_for")
	probe.free()
	check("double keepers from floor 4 (%s): the Wind Keeper and an echo of the Water Keeper, its hits held to its own floor; the Dark Keeper and another"
		% [counts], counts == [1, 1, 1, 2, 2, 2, 2, 2] and str(fourth[0][0]) == "windboss" and str(fourth[1][0]) == "waterboss"
		and is_equal_approx(float(fourth[1][2]), float(RunScript.FLOORS[2]["keeper_taken"]) / float(RunScript.FLOORS[3]["keeper_taken"]) * RunScript.ECHO_HIT)
		and str(seventh[0][0]) == "bossenemy" and str(seventh[1][0]) != "bossenemy", [fourth, seventh])
	run.call("_clear_monsters")
	run.set("floor_index", 3)
	run.set("room", RunScript.ROOMS)
	run.call("_go", "keeper")
	for i in 3:
		run.call("_process", RunScript.FADE_SECONDS)
	run.call("_process", RunScript.FIGHT_DELAY + 0.1)
	var keepers: Array = run.get("_keepers")
	var echo: Node = keepers[1] if keepers.size() == 2 else null
	var shared: EnemyData = (load("res://scene/enemy/waterboss.tscn") as PackedScene).instantiate().get("enemy_data") as EnemyData
	var echo_data: EnemyData = echo.get("enemy_data") as EnemyData if echo != null else null
	var own_copy: bool = echo_data != null and shared != null and echo_data != shared \
		and echo_data.projectile_damage == maxi(1, roundi(shared.projectile_damage * float(fourth[1][2])))
	(keepers[0] as Node).call("take_damage", 99999999)
	run.call("_process", 0.016)
	var still_fight: bool = int(run.get("state")) == RunScript.State.FIGHT and bool(run.call("keepers_standing"))
	(keepers[1] as Node).call("take_damage", 99999999)
	run.call("_process", 0.016)
	await get_tree().process_frame
	run.call("_process", 0.016)
	check("  in the room: both come, the echo with its own copy of its numbers (%d, the Water Keeper's own %d untouched); the room is theirs until the last falls"
		% [echo_data.projectile_damage if echo_data != null else -1, shared.projectile_damage if shared != null else -1],
		keepers.size() == 2 and own_copy and still_fight and int(run.get("state")) == RunScript.State.PICK,
		[keepers.size(), own_copy, still_fight, run.get("state")])
	run.call("pick", 0)
	# ---- an Impossible room ----
	run.set("floor_index", 1)
	run.set("_impossible_floor", -1)
	var early: int = 0
	for i in 40:
		run.set("room", 1)
		run.set("room_kind", "gold")
		run.call("_open_doors")
		early += 1 if str(doors[1].get("reward")) == "impossible" else 0
	run.set("floor_index", 2)
	var offered: int = 0
	for i in 60:
		run.set("room", 1)
		run.set("room_kind", "gold")
		run.call("_open_doors")
		offered += 1 if str(doors[1].get("reward")) == "impossible" else 0
	check("an Impossible door: never before floor 3, then once a floor (%d of 60 pairs of doors)" % offered,
		early == 0 and offered == 1, [early, offered])
	run.call("_clear_monsters")
	run.set("room", 1)
	run.call("_go", "impossible")
	for i in 3:
		run.call("_process", RunScript.FADE_SECONDS)
	var size: int = int(run.call("pack_size"))
	var waves: int = int(run.call("waves_in", size))
	run.call("_process", RunScript.FIGHT_DELAY + 0.1)
	var bosses: int = 0
	for m in (run.get("monsters") as Array):
		bosses += 1 if is_instance_valid(m) and (m as Node).is_in_group(&"bosses") else 0
	var fast: bool = is_equal_approx(float(lands.get("every")), LandsScript.gap(2) * 0.5) and int(lands.get("phase")) == 2
	var gold_was: int = int(run.get("gold"))
	_descent_kill_all(run)
	run.call("_process", 0.016)
	var epic: bool = not (run.get("offers") as Array).is_empty()
	for id in (run.get("offers") as Array):
		epic = epic and Boons.RARITIES.find(Boons.rarity(str(id))) >= Boons.RARITIES.find("epic")
	check("  inside: %d monsters (three packs) in %d waves, an elite in every one, a keeper of another land, hazards twice as often; lived, an epic pick and five rooms' gold"
		% [size, waves], size == 3 * (RunScript.PACK_FIRST + 2 + RunScript.PACK_FLOOR * 2) and waves == ceili(size / 5.0)
		and int(run.call("elites_for", "impossible")) >= waves and bosses == 1 and fast and epic
		and int(run.get("gold")) - gold_was == RunScript.GOLD_BASE * 3 * RunScript.IMPOSSIBLE_GOLD,
		[size, waves, bosses, fast, epic, int(run.get("gold")) - gold_was])
	# ---- the Deep ----
	var deep: Node = RunScript.new()
	deep.set("floor_index", 6)
	deep.set("room", 2)
	var last_health: float = float(deep.call("health_scale"))
	var last_taken: float = float(deep.call("taken_for", "gold"))
	deep.set("floor_index", RunScript.FLOORS.size() + 6)
	var name_now: String = str(deep.call("floor_info")["name"])
	var round_health: float = float(deep.call("health_scale"))
	var round_taken: float = float(deep.call("taken_for", "gold"))
	var round_elites: int = int(deep.call("elites_for", "gold"))
	var hazards: Array = deep.call("hazard_keepers")
	deep.free()
	check("the Deep: the Dark Below again as %s - health x%.1f, hits x%.2f, %d elites a room, two lands' hazards (%s)"
		% [name_now, round_health / last_health, round_taken / last_taken, round_elites, hazards],
		name_now == "the Deep 1: the Dark Below" and is_equal_approx(round_health / last_health, 1.0 + RunScript.DEEP_HEALTH_STEP)
		and is_equal_approx(round_taken / last_taken, 1.0 + RunScript.DEEP_TAKEN_STEP) and round_elites == 4 + RunScript.DEEP_ELITES
		and hazards.size() == 2 and str(hazards[0]) == "bossenemy")
	room.queue_free()
	Boons.clear()
	await get_tree().process_frame
	print("  the lands shine: done")


# =============================================================================
# EVERY CLASS ITS OWN UPGRADES (0.124.0)
# =============================================================================
# Step 2 of DESCENT_PLAN_3.txt, its first half. The owner: "any class can join
# but we have to set up bonuses for all 4 chars".
func _test_every_class_has_its_own_upgrades() -> void:
	section("EVERY CLASS ITS OWN UPGRADES (0.124.0): any class in the Descent, each offered its own and its mythic weapon's")
	const Boons := preload("res://src/world/descent/descentboons.gd")
	const RunScript := preload("res://src/world/descent/descentrun.gd")
	Boons.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 124
	var seen: Dictionary = {}
	var wrong: Array = []
	for who in [["warrior", "axe"], ["mage", "meteor"], ["tank", "dynamite"], ["healer", ""]]:
		Boons.class_now = str(who[0])
		Boons.weapon_now = str(who[1])
		var got: Dictionary = {}
		for i in 300:
			for id in Boons.offers(rng, 3, "", str(who[1]) != "", i % 3 == 0):
				got[id] = true
				var boon: Dictionary = Boons.BOONS[id]
				if boon.has("class") and str(boon["class"]) != str(who[0]):
					wrong.append([who[0], id])
				if str(boon.get("rarity", "")) == "mythic" and str(boon.get("weapon", "")) != str(who[1]):
					wrong.append([who[0], id])
		seen[who[0]] = got
	var own: Dictionary = {}
	for id in Boons.ORDER:
		var cls: String = str(Boons.BOONS[id].get("class", ""))
		if cls != "":
			own[cls] = int(own.get(cls, 0)) + 1
	var all_offered: bool = true
	for id in Boons.ORDER:
		var cls: String = str(Boons.BOONS[id].get("class", ""))
		var whose: Array = ["warrior", "mage", "tank", "healer"] if cls == "" else [cls]
		for c in whose:
			all_offered = all_offered and (seen[c] as Dictionary).has(id)
	check("each class is offered anyone's upgrades and its own alone - a mythic only with its weapon on (own: %s)" % own,
		wrong.is_empty() and all_offered and int(own.get("mage", 0)) == 6 and int(own.get("tank", 0)) == 5
		and int(own.get("healer", 0)) == 3 and int(own.get("warrior", 0)) == 9, wrong)
	# ---- what they do ----
	Boons.active = true
	Boons.levels = {"arcaneedge": 3, "spikestorm": 2, "deepcrits": 1, "comet": 1, "longburn": 2, "searing": 3,
		"bastion": 1, "cluster": 1, "barrage": 1, "shortfuse": 1, "quickhands": 3, "twinorbs": 2, "wardinglight": 1}
	Boons.ward_most = 100
	Boons.ward = 50
	Boons.warding_light(30)
	var warded: int = Boons.ward
	Boons.warding_light(500)
	var meteor: Node = (load("res://scene/projectiles/meteor.tscn") as PackedScene).instantiate()
	var stick: Node = (load("res://scene/projectiles/dynamite.tscn") as PackedScene).instantiate()
	var fell: float = float(meteor.get("fall_seconds"))
	var fused: float = float(stick.get("fuse"))
	meteor.free()
	stick.free()
	check("Arcane Edge %.1f more crit, Spike Storm every cast triple, Deep Crits x3, Comet falls in %.2f s, Long Burn x%.1f, Searing x%.2f, Bastion x%.1f, Cluster %.1f, Barrage %.2f, Short Fuse %.1f s, Quick Hands x%.2f, Twin Orbs every %d, Warding Light %d then full"
		% [Boons.crit_more(), fell, Boons.crater_scale(), Boons.aura_scale(), Boons.bastion_scale(true),
			Boons.bundle_chance(0.1), Boons.barrage_chance(0.01), fused, Boons.shot_rate(), Boons.fan_every(5), warded],
		is_equal_approx(Boons.crit_more(), 0.3) and Boons.triple_every(3) == 1 and is_equal_approx(Boons.crit_mult(2.0), 3.0)
		and is_equal_approx(fell, 0.55 * 0.5) and is_equal_approx(Boons.crater_scale(), 2.0) and is_equal_approx(Boons.aura_scale(), 1.75)
		and is_equal_approx(Boons.bastion_scale(true), 0.8) and is_equal_approx(Boons.bastion_scale(false), 1.0)
		and is_equal_approx(Boons.bundle_chance(0.1), 0.5) and Boons.barrage_chance(0.01) > 0.14
		and is_equal_approx(fused, 0.6) and is_equal_approx(Boons.shot_rate(), 1.36) and Boons.fan_every(5) == 3
		and warded == 80 and Boons.ward == 100)
	Boons.clear()
	var calm: Node = (load("res://scene/projectiles/meteor.tscn") as PackedScene).instantiate()
	var off_run: bool = is_equal_approx(float(calm.get("fall_seconds")), 0.55) and Boons.triple_every(3) == 3 \
		and Boons.fan_every(5) == 5 and is_equal_approx(Boons.shot_rate(), 1.0) and Boons.class_now == "warrior"
	calm.free()
	check("  and none of it off a run (a cleared run is the warrior's, with the axe)", off_run)
	# ---- wired into each class ----
	var hooks: Array = [["res://src/characters/mage.gd", "func rolls_critical(", "DescentBoons.crit_more()"],
		["res://src/characters/mage.gd", "func _spawn_stalagmite(", "DescentBoons.triple_every(TRIPLE_EVERY)"],
		["res://src/characters/mage.gd", "func _spawn_stalagmite(", "DescentBoons.crit_mult(CRIT_MULT)"],
		["res://src/characters/mage.gd", "func call_meteor(", "DescentBoons.meteor_shower()"],
		["res://src/projectiles/burningcrater.gd", "func _build(", "DescentBoons.crater_scale()"],
		["res://src/characters/tank.gd", "func _deal_aura_damage(", "DescentBoons.aura_scale()"],
		["res://src/characters/tank.gd", "func take_damage(", "DescentBoons.bastion_scale(true)"],
		["res://src/characters/tank.gd", "func throw_dynamite(", "DescentBoons.bundle_chance("],
		["res://src/characters/healer.gd", "func attack_period(", "DescentBoons.shot_rate()"],
		["res://src/characters/healer.gd", "func rolls_double_hit(", "DescentBoons.fan_every(FAN_EVERY)"],
		["res://src/projectiles/healaura.gd", "func tick(", "DescentBoons.warding_light(amount)"]]
	var unwired: Array = []
	for hook in hooks:
		if not _func_body(_code_src(str(hook[0])), str(hook[1])).contains(str(hook[2])):
			unwired.append(hook[2])
	check("  each wired into its class's own attack (%d places)" % hooks.size(), unwired.is_empty(), unwired)
	# ---- who is playing ----
	var run: Node = RunScript.new()
	var mage: Node = (load("res://src/characters/mage.gd") as GDScript).new()
	run.set("player_override", mage)
	var mythic: bool = bool(run.call("_note_class"))
	var as_mage: bool = Boons.class_now == "mage" and Boons.weapon_now == "" and not mythic
	run.free()
	mage.free()
	Boons.clear()
	check("the run tells the upgrades who is playing - the class from its own script, the mythic weapon from what it wears",
		as_mage, [Boons.class_now])
	print("  every class its own: done")


# =============================================================================
# THE DESCENT TOGETHER (0.126.0)
# =============================================================================
# Step 2 of DESCENT_PLAN_3.txt, its second half. The owner: "lets set up
# party", "everyone has to die at some point even with a party of 4".
# Two games in one tree, each on a stand-in link that passes "en" as the
# server does (JSON and back). DescentBoons is one set of statics for both,
# so what is the player's own (picks, the ward, down) is shared here - the
# checks are on what crosses between the runs.
func _descent_link_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = _party_link_script().source_code + "\nfunc descent_rooms() -> bool:\n\treturn open\n"
	script.reload()
	return script


func _test_the_descent_together() -> void:
	section("THE DESCENT TOGETHER (0.126.0): the leader runs it, the party follows - a countdown, the same rooms, picks awaited, the door anyone takes, down until the room is clear")
	const RunScript := preload("res://src/world/descent/descentrun.gd")
	const Boons := preload("res://src/world/descent/descentboons.gd")
	Boons.clear()
	var body_script := GDScript.new()
	body_script.source_code = "extends Node2D\nvar hp: int = 400\nvar max_hp: int = 400\n"
	body_script.reload()
	var made_a: Array = _descent_room_for_test(body_script)
	var made_b: Array = _descent_room_for_test(body_script)
	var run_a: Node = made_a[1]
	var run_b: Node = made_b[1]
	var body_a: Node2D = made_a[2]
	var body_b: Node2D = made_b[2]
	await get_tree().process_frame
	var Link: GDScript = _descent_link_script()
	var la: Node = Link.new()
	var lb: Node = Link.new()
	add_child(la)
	add_child(lb)
	la.set("me", 1)
	lb.set("me", 2)
	la.set("peers", [lb])
	lb.set("peers", [la])
	la.set("bodies", {2: body_b})
	lb.set("bodies", {1: body_a})
	for pair in [[run_a, la], [run_b, lb]]:
		var party: Node = (pair[0] as Node).get("party")
		party.set("link", pair[1])
		(pair[1] as Node).run_received.connect(Callable(party, "_on_run"))
	var party_a: Node = run_a.get("party")
	var party_b: Node = run_b.get("party")
	var roles: bool = bool(run_a.call("party_on")) and not bool(run_a.call("following")) and bool(run_b.call("following"))
	# ---- the countdown, from the follower's door ----
	var doors_b: Array = run_b.get("doors")
	(doors_b[0] as Node).emit_signal("walked_in", doors_b[0])
	var counting: bool = int(run_a.get("state")) == RunScript.State.COUNTDOWN and int(run_a.get("run_key")) > 0
	party_a.call("flush")
	var both_counting: bool = int(run_b.get("state")) == RunScript.State.COUNTDOWN and int(run_b.get("run_key")) == int(run_a.get("run_key"))
	check("in a party's Descent the first in leads; the other walking through a door starts the countdown on both screens",
		roles and counting and both_counting, [roles, counting, both_counting])
	# ---- together into room 1 ----
	run_a.call("_process", RunScript.COUNTDOWN_SECONDS + 0.1)
	party_a.call("flush")
	for i in 3:
		run_a.call("_process", RunScript.FADE_SECONDS)
		run_b.call("_process", RunScript.FADE_SECONDS)
	run_a.call("_process", RunScript.FIGHT_DELAY + 0.1)
	run_b.call("_process", RunScript.FIGHT_DELAY + 0.1)
	run_a.call("_process", RunScript.MARK_SECONDS + 0.05)
	var pack_a: Array = run_a.get("monsters")
	var shared: bool = not pack_a.is_empty()
	for m in pack_a:
		shared = shared and (m as Node).has_meta(RunScript.PARTY_MARK) and (m as Node).has_meta(&"stress_copy")
	check("  the countdown over, both come into floor 1, room 1 - the leader's pack scaled for two (%d and %d elites), shared with the party; the other runs none of its own"
		% [int(run_a.call("pack_size")), int(run_a.call("elites_for", "upgrade"))],
		int(run_a.get("players")) == 2 and int(run_a.get("room")) == 1 and int(run_b.get("room")) == 1
		and int(run_b.get("floor_index")) == 0 and int(run_b.get("state")) == RunScript.State.FIGHT
		and int(run_a.call("pack_size")) == 8 and int(run_a.call("elites_for", "upgrade")) == 2 and shared
		and (run_b.get("monsters") as Array).is_empty() and (run_b.get("_coming") as Array).is_empty()
		and (run_b.get("_waves") as Array).is_empty(), [run_a.get("players"), run_b.get("room"), pack_a.size()])
	var first: Dictionary = RunScript.FLOORS[0]
	check("  and both are hit harder for two - x%.2f (PARTY_HIT; x%.2f for four, x1 alone), the keeper too, the follower's the same"
		% [RunScript.PARTY_HIT[2], RunScript.PARTY_HIT[4]],
		RunScript.PARTY_HIT[1] == 1.0 and RunScript.PARTY_HIT[4] > RunScript.PARTY_HIT[2]
		and is_equal_approx(float(run_a.call("taken_for", "upgrade")), float(first["taken"]) * RunScript.FLOOR_HARDER * RunScript.PARTY_HIT[2])
		and is_equal_approx(float(run_b.call("taken_for", "upgrade")), float(first["taken"]) * RunScript.FLOOR_HARDER * RunScript.PARTY_HIT[2])
		and is_equal_approx(float(run_a.call("taken_for", "keeper")), float(first["keeper_taken"]) * RunScript.KEEPER_HARDER * RunScript.PARTY_HIT[2]),
		[run_a.call("taken_for", "upgrade"), run_b.call("taken_for", "upgrade"), run_b.get("players")])
	# ---- the room clear; the doors wait for everybody's pick ----
	_descent_kill_all(run_a)
	run_a.call("_process", 0.016)
	var leader_picking: bool = int(run_a.get("state")) == RunScript.State.PICK
	party_a.call("flush")
	var other_picking: bool = int(run_b.get("state")) == RunScript.State.PICK and not (run_b.get("offers") as Array).is_empty()
	party_b.call("flush")
	run_a.call("pick", 0)
	party_a.call("flush")
	var held: bool = int(run_a.get("state")) == RunScript.State.CLEAR and not bool(run_a.call("_doors_open"))
	run_b.call("pick", 0)
	party_b.call("flush")
	run_a.call("_process", 0.016)
	party_a.call("flush")
	var doors_a: Array = run_a.get("doors")
	var open_both: bool = bool(run_a.call("_doors_open")) and bool(run_b.call("_doors_open")) \
		and str(doors_b[1].get("reward")) == str(doors_a[1].get("reward"))
	check("  the leader's room clear is the other's too, each with their own pick; the doors stay shut until both have picked, then open alike",
		leader_picking and other_picking and held and open_both, [leader_picking, other_picking, held, open_both])
	# ---- the door anyone takes ----
	if str(doors_a[1].get("reward")) == "rest":
		doors_a[1].call("set_reward", "gold")
		party_a.call("flush")
	var promised: String = str(doors_a[1].get("reward"))
	(doors_b[1] as Node).emit_signal("walked_in", doors_b[1])
	party_b.call("flush")
	party_a.call("flush")
	for i in 3:
		run_a.call("_process", RunScript.FADE_SECONDS)
		run_b.call("_process", RunScript.FADE_SECONDS)
	check("  the other walks through the right-hand door: everybody goes through it, into room 2 (%s)" % promised,
		int(run_a.get("room")) == 2 and int(run_b.get("room")) == 2 and str(run_a.get("room_kind")) == promised
		and str(run_b.get("room_kind")) == promised, [run_a.get("room"), run_b.get("room"), run_b.get("room_kind")])
	# ---- down, until everybody is ----
	run_a.call("_process", RunScript.FIGHT_DELAY + 0.1)
	# Whatever the two picks were, no Second Wind to keep the fallen standing.
	Boons.levels.erase("secondwind")
	var downed: bool = bool(run_a.call("knock_out", body_a))
	var down_not_out: bool = downed and Boons.out and bool(run_a.call("running")) and is_equal_approx(body_a.modulate.a, RunScript.OUT_ALPHA)
	var nothing_lands: bool = _func_body(_code_src("res://src/characters/player.gd"), "func take_damage(").contains("if DescentBoons.out:")
	run_a.call("_process", 0.016)
	var still_on: bool = bool(run_a.call("running"))
	party_b.call("flush")
	run_a.call("_process", 0.016)
	party_a.call("flush")
	check("  down in a party is not the end: a ghost at the front whom nothing hits, while anybody stands - and when the other is down too, the run is over on both",
		down_not_out and nothing_lands and still_on and not bool(run_a.call("running")) and not bool(run_b.call("running"))
		and is_equal_approx(body_a.modulate.a, 1.0), [down_not_out, nothing_lands, still_on, run_a.get("state"), run_b.get("state")])
	# ---- standing again ----
	Boons.clear()
	Boons.active = true
	Boons.out = true
	run_a.set("state", RunScript.State.FIGHT)
	run_a.set("room_kind", "gold")
	run_a.call("fill_ward")
	run_a.call("_room_cleared")
	check("  a fallen player stands when the room is clear, on half a ward", not Boons.out and Boons.ward == Boons.ward_most / 2
		and Boons.ward_most > 0, [Boons.out, Boons.ward, Boons.ward_most])
	(made_a[0] as Node).queue_free()
	(made_b[0] as Node).queue_free()
	la.queue_free()
	lb.queue_free()
	Boons.clear()
	await get_tree().process_frame
	print("  the Descent together: done")


# =============================================================================
# THE FLOOR ITSELF FIGHTS (0.127.0)
# =============================================================================
# The owner: "when i think of enviromental damage i mean bubbles or sparks
# that can catch a player on fire poison gas etc", "start building them".
func _test_the_floor_itself_fights() -> void:
	section("THE FLOOR ITSELF FIGHTS (0.127.0): sparks, hail, bubbles, gusts, flares, rocks, wisps and poison gas - and a second land's weather mixed in")
	const RunScript := preload("res://src/world/descent/descentrun.gd")
	const LandsScript := preload("res://src/world/descent/descentlands.gd")
	const Boons := preload("res://src/world/descent/descentboons.gd")
	Boons.clear()
	var counts: Array = []
	for f in 7:
		counts.append(LandsScript.env_count(f))
	var every_land: bool = true
	for land in RunScript.ALL_LANDS:
		every_land = every_land and LandsScript.KIND_FOR.has(land) and not LandsScript.weather_for(land).is_empty()
	check("every land its own hazard (%s), one every %.1f s on floor 1 down to %.1f, hitting for %.0f%% of your health up to %.0f%%, %s at a time"
		% [LandsScript.KIND_FOR.values(), LandsScript.env_gap(0), LandsScript.env_gap(7), 100.0 * LandsScript.env_share(0),
		100.0 * LandsScript.env_share(6), counts],
		every_land and is_equal_approx(LandsScript.env_gap(0), LandsScript.ENV_GAP_FIRST) and LandsScript.env_gap(10) >= LandsScript.ENV_GAP_LEAST
		and LandsScript.env_share(6) > LandsScript.env_share(0) and counts == [1, 1, 2, 2, 3, 3, 4]
		and LandsScript.env_amount(0, 500) == roundi(500.0 * LandsScript.ENV_SHARE_FIRST))
	# ---- a room of stand-ins, its player keeping what hit it ----
	var body_script := GDScript.new()
	body_script.source_code = "extends Node2D\nvar hp: int = 400\nvar max_hp: int = 400\nvar hits: Array = []\nfunc take_damage(amount: int, element: int = 0) -> void:\n\thits.append([amount, element])\n"
	body_script.reload()
	var made: Array = _descent_room_for_test(body_script)
	var room: Node2D = made[0]
	var run: Node = made[1]
	var body: Node2D = made[2]
	await get_tree().process_frame
	# ---- mixing ----
	var mixed_early: int = 0
	var mixed_deep: int = 0
	var mixed_seventh: int = 0
	for i in 60:
		run.set("floor_index", 1)
		mixed_early += 1 if (run.call("lands_for_room") as Array).size() > 1 else 0
		run.set("floor_index", 6)
		mixed_seventh += 1 if (run.call("lands_for_room") as Array).size() > 1 else 0
		run.set("floor_index", 8)
		mixed_deep += 1 if (run.call("lands_for_room") as Array).size() > 1 else 0
	run.set("floor_index", 0)
	check("a second land mixes in from floor 3, more often deeper, always in the Deep (%d, %d, %d of 60)" % [mixed_early, mixed_seventh, mixed_deep],
		mixed_early == 0 and mixed_seventh > 0 and mixed_seventh < 60 and mixed_deep == 60)
	# ---- each hazard, touched ----
	var lands: Node2D = run.call("_lands_node")
	lands.call("begin_env", RunScript.ALL_LANDS, 2)
	var got: Array = []
	var expected: Array = []
	for one in [["spark", Element.Type.FIRE, 0.016], ["bubble", Element.Type.WATER, 0.016], ["wisp", Element.Type.DARK, 0.016],
			["hail", Element.Type.ICE, 0.95], ["rock", Element.Type.EARTH, 1.15], ["flare", Element.Type.LIGHT, 1.05],
			["gust", Element.Type.WIND, 1.05], ["gas", Element.Type.POISON, 1.25]]:
		lands.set("hazards", [])
		lands.set("_touch_left", 0.0)
		lands.set("_env_left", 999.0)
		var before: int = (body.get("hits") as Array).size()
		var hz: Dictionary = lands.call("spawn_env", str(one[0]), body)
		hz["p"] = body.global_position
		if str(one[0]) == "gust":
			hz["p"] = Vector2(320, body.global_position.y)
		lands.call("step", float(one[2]))
		var hits: Array = body.get("hits")
		got.append(int(hits[hits.size() - 1][1]) if hits.size() > before else -1)
		expected.append(int(one[1]))
	check("  each, touched or stood in, hits as its land: spark fire, bubble water, wisp dark, hail ice, rock earth, flare light, gust wind, gas poison",
		got == expected, [got, expected])
	lands.set("hazards", [])
	lands.set("_touch_left", 0.0)
	var count_was: int = (body.get("hits") as Array).size()
	var far: Dictionary = lands.call("spawn_env", "spark", body)
	far["p"] = body.global_position + Vector2(200, 0)
	var near_a: Dictionary = lands.call("spawn_env", "spark", body)
	near_a["p"] = body.global_position
	var near_b: Dictionary = lands.call("spawn_env", "spark", body)
	near_b["p"] = body.global_position
	lands.call("step", 0.016)
	check("  one far away does nothing, and two at once hit once (TOUCH_GAP)", (body.get("hits") as Array).size() == count_was + 1)
	lands.call("end")
	# ---- in a room ----
	(made[3][0] as Node).emit_signal("walked_in", made[3][0])
	for i in 3:
		run.call("_process", RunScript.FADE_SECONDS)
	run.call("_clear_monsters")
	run.set("floor_index", 2)
	run.set("room", 1)
	run.call("_go", "gold")
	for i in 3:
		run.call("_process", RunScript.FADE_SECONDS)
	run.call("_process", RunScript.FIGHT_DELAY + 0.1)
	var room_lands: Array = run.get("room_lands")
	var skies: int = lands.find_children("*", "CPUParticles2D", false, false).size()
	var made_before: int = int(lands.get("env_made"))
	run.call("_process", LandsScript.ENV_FIRST + 0.05)
	# Each in turn since 0.134.2 (ENV_STAGGER): give the wave time to arrive.
	for k in 6:
		run.call("_process", LandsScript.ENV_STAGGER)
	var line: Array = run.call("line")
	check("  room 2 of the Drowned Halls: its lands %s each with weather (%d), and %.1f s in, the floor's first hazards; the party's line carries the mix"
		% [room_lands, skies, LandsScript.ENV_FIRST],
		room_lands.size() >= 1 and int(room_lands[0]) == Element.Type.WATER and skies == room_lands.size()
		and int(lands.get("env_made")) - made_before >= LandsScript.env_count(2) and line.size() == 13
		and int(line[12]) == (int(room_lands[1]) if room_lands.size() > 1 else -1), [room_lands, skies, lands.get("env_made")])
	room.queue_free()
	Boons.clear()
	await get_tree().process_frame
	print("  the floor itself fights: done")


func _mix_kinds(lands: Node) -> Array:
	"""The hazards still going, by kind, sorted."""
	var kinds: Array = []
	for hz in lands.get("hazards"):
		if not bool(hz["done"]):
			kinds.append(str(hz["k"]))
	kinds.sort()
	return kinds


func _mix_fresh(lands: Node) -> void:
	lands.set("hazards", [])
	lands.set("_touch_left", 0.0)
	lands.set("_env_left", 999.0)


func _mix_last(body: Node) -> Array:
	var hits: Array = body.get("hits")
	return hits[hits.size() - 1] if not hits.is_empty() else []


func _test_the_mixes_react() -> void:
	section("THE MIXES REACT (0.128.0): puddles, explosions, melting, steam, shocks, ice and the wind blowing it all")
	const RunScript := preload("res://src/world/descent/descentrun.gd")
	const LandsScript := preload("res://src/world/descent/descentlands.gd")
	const Boons := preload("res://src/world/descent/descentboons.gd")
	Boons.clear()
	var body_script := GDScript.new()
	body_script.source_code = "extends Node2D\nvar hp: int = 400\nvar max_hp: int = 400\nvar hits: Array = []\nfunc take_damage(amount: int, element: int = 0) -> void:\n\thits.append([amount, element])\n"
	body_script.reload()
	var made: Array = _descent_room_for_test(body_script)
	var room: Node2D = made[0]
	var run: Node = made[1]
	var body: Node2D = made[2]
	await get_tree().process_frame
	var lands: Node2D = run.call("_lands_node")
	lands.call("begin_env", RunScript.ALL_LANDS, 2)
	var hit: int = LandsScript.env_amount(2, 400)
	var at: Vector2 = body.global_position
	# ---- a bubble popped leaves a puddle, and standing in it soaks ----
	_mix_fresh(lands)
	var bubble: Dictionary = lands.call("spawn_env", "bubble", body)
	bubble["p"] = at
	lands.call("step", 0.016)
	var after_pop: Array = _mix_kinds(lands)
	var pop_hit: Array = _mix_last(body)
	lands.set("_touch_left", 0.0)
	lands.call("step", LandsScript.PUDDLE_WARN + 0.05)
	check("a bubble popped on you leaves a puddle (%s), and standing in it soaks you for half (%s)" % [after_pop, _mix_last(body)],
		after_pop == ["puddle"] and pop_hit == [hit, Element.Type.WATER] and _mix_last(body) == [LandsScript.env_amount(2, 400, 0.5), Element.Type.WATER])
	# ---- a spark in a gas cloud: it explodes ----
	_mix_fresh(lands)
	var gas: Dictionary = lands.call("spawn_env", "gas", body)
	gas["p"] = at + Vector2(0, -40)
	gas["t"] = 2.0
	var spark: Dictionary = lands.call("spawn_env", "spark", body)
	spark["p"] = at + Vector2(0, -40)
	lands.call("step", 0.016)
	check("  a spark in a gas cloud blows it up (%s): fire for twice the hit on you beside it (%s)" % [_mix_kinds(lands), _mix_last(body)],
		_mix_kinds(lands) == ["blast"] and _mix_last(body) == [LandsScript.env_amount(2, 400, 2.0), Element.Type.FIRE])
	# ---- a spark through falling hail: melted to a puddle ----
	_mix_fresh(lands)
	var hits_before: int = (body.get("hits") as Array).size()
	var hail: Dictionary = lands.call("spawn_env", "hail", body)
	hail["p"] = Vector2(150, 150)
	var spark_b: Dictionary = lands.call("spawn_env", "spark", body)
	spark_b["p"] = Vector2(150, 150)
	lands.call("step", 0.016)
	var melted: Array = _mix_kinds(lands)
	# ---- a spark into a puddle: put out ----
	_mix_fresh(lands)
	var puddle: Dictionary = lands.call("_patch", "puddle", Vector2(480, 150))
	(lands.get("hazards") as Array).append(puddle)
	var spark_c: Dictionary = lands.call("spawn_env", "spark", body)
	spark_c["p"] = Vector2(480, 150)
	lands.call("step", 0.016)
	check("  fire meets ice and water far from you: hail melts before it lands (%s), a spark goes out in steam (%s), nobody hit"
		% [melted, _mix_kinds(lands)], melted == ["puddle"] and _mix_kinds(lands) == ["puddle", "steam"]
		and (body.get("hits") as Array).size() == hits_before)
	# ---- a flare over puddles: the light runs through them ----
	_mix_fresh(lands)
	var under: Dictionary = lands.call("_patch", "puddle", at)
	under["t"] = 1.0
	(lands.get("hazards") as Array).append(under)
	var flare: Dictionary = lands.call("spawn_env", "flare", body)
	flare["p"] = at + Vector2(100, 0)
	flare["t"] = float(flare["w"]) - 0.01
	lands.call("step", 0.016)
	check("  a flare flashing 100 px off shocks the puddle you stand in (%s): light, half again the hit" % [_mix_last(body)],
		_mix_last(body) == [LandsScript.env_amount(2, 400, 1.5), Element.Type.LIGHT] and under.has("shock"))
	# ---- hail on a puddle: ice ----
	_mix_fresh(lands)
	var pool: Dictionary = lands.call("_patch", "puddle", Vector2(480, 150))
	pool["t"] = 1.0
	(lands.get("hazards") as Array).append(pool)
	var hail_b: Dictionary = lands.call("spawn_env", "hail", body)
	hail_b["p"] = Vector2(495, 150)
	hail_b["t"] = float(hail_b["w"]) - 0.01
	lands.call("step", 0.016)
	var frozen: Array = _mix_kinds(lands)
	for hz in lands.get("hazards"):
		if str(hz["k"]) == "ice":
			hz["p"] = at
	lands.set("_touch_left", 0.0)
	lands.call("step", 0.016)
	check("  hail landing on a puddle freezes it (%s), and the ice chills you on it (%s)" % [frozen, _mix_last(body)],
		frozen == ["hail", "ice"] and _mix_last(body) == [LandsScript.env_amount(2, 400, 0.5), Element.Type.ICE])
	# ---- a gust blows what floats along its lane ----
	_mix_fresh(lands)
	var gust: Dictionary = lands.call("spawn_env", "gust", body)
	gust["p"] = Vector2(320, 200)
	gust["dir"] = 1.0
	gust["t"] = float(gust["w"]) - 0.01
	var cloud: Dictionary = lands.call("spawn_env", "gas", body)
	cloud["p"] = Vector2(300, 200)
	cloud["v"] = Vector2.ZERO
	var edge: Dictionary = lands.call("spawn_env", "bubble", body)
	edge["p"] = Vector2(600, 190)
	edge["v"] = Vector2.ZERO
	var outside: Dictionary = lands.call("spawn_env", "gas", body)
	outside["p"] = Vector2(300, 260)
	outside["v"] = Vector2.ZERO
	lands.call("step", 0.016)
	var cloud_x: float = (cloud["p"] as Vector2).x
	var edge_x: float = (edge["p"] as Vector2).x
	check("  a gust blows the gas in its lane %.0f px (%.0f -> %.0f), a bubble only to the wall (%.0f), not what is out of its lane"
		% [LandsScript.GUST_PUSH, 300.0, cloud_x, edge_x],
		is_equal_approx(cloud_x, 300.0 + LandsScript.GUST_PUSH) and edge_x <= (run.get("room_rect") as Rect2).end.x - 11.0
		and is_equal_approx((outside["p"] as Vector2).x, 300.0))
	lands.call("end")
	room.queue_free()
	Boons.clear()
	await get_tree().process_frame
	print("  the mixes react: done")


func _test_the_descent_bites() -> void:
	section("THE DESCENT BITES (0.129.0): hits pierce the ward, elements stack and burst, lasers cross the rooms, the floors hit harder")
	const RunScript := preload("res://src/world/descent/descentrun.gd")
	const LandsScript := preload("res://src/world/descent/descentlands.gd")
	const Boons := preload("res://src/world/descent/descentboons.gd")
	const Source := preload("res://src/shared/hitsource.gd")
	Boons.clear()
	Boons.active = true
	# ---- piercing ----
	Boons.pierce_base = 0.3
	Boons.ward = 100
	var plain: int = Boons.absorb(100, "skeleton:arrow")
	var ward_left: int = Boons.ward
	var elite: int = Boons.absorb(40, "skeletonelite:arrow")
	var keeper: int = Boons.absorb(40, "fireboss:orb")
	var floors: int = Boons.absorb(40, "", true)
	check("a hit pierces the ward by the room's share (70 of 100 soaked); an elite's, a keeper's and the floor's own skip it all",
		plain == 70 and ward_left == 30 and elite == 0 and keeper == 0 and floors == 0 and Boons.ward == 30,
		[plain, ward_left, elite, keeper, floors])
	var marked := Node2D.new()
	marked.set_meta(&"descent_elite", true)
	marked.name = "icefiresprite"
	check("  a Descent elite's hits say so (%s), so they pierce" % Source.of(marked, "shot"),
		Source.of(marked, "shot").get_slice(":", 0).contains("elite") and Boons.pierce_share(Source.of(marked, "shot")) == 1.0)
	marked.free()
	var run: Node = RunScript.new()
	var shares: Array = []
	for f in [0, 6, 20]:
		run.set("floor_index", f)
		shares.append(snappedf(float(run.call("pierce_for", "upgrade")), 0.01))
	check("  the share: %s on floors 1, 7 and deep in the Deep, and all of it in the keeper's room" % [shares],
		shares == [RunScript.PIERCE_FIRST, snappedf(RunScript.PIERCE_FIRST + 6.0 * RunScript.PIERCE_STEP, 0.01), RunScript.PIERCE_MOST]
		and float(run.call("pierce_for", "keeper")) == 1.0)
	# ---- harder ----
	run.set("floor_index", 0)
	check("every floor hits x%.2f its old \"taken\" and its keeper x%.2f (floor 1: %.2f, the Fire Keeper %.2f)"
		% [RunScript.FLOOR_HARDER, RunScript.KEEPER_HARDER, float(run.call("taken_for", "upgrade")), float(run.call("taken_for", "keeper"))],
		is_equal_approx(float(run.call("taken_for", "upgrade")), float(RunScript.FLOORS[0]["taken"]) * RunScript.FLOOR_HARDER)
		and is_equal_approx(float(run.call("taken_for", "keeper")), float(RunScript.FLOORS[0]["keeper_taken"]) * RunScript.KEEPER_HARDER)
		and RunScript.FLOOR_HARDER > 1.0 and RunScript.KEEPER_HARDER > 1.0)
	run.free()
	# ---- stacks ----
	Boons.clear_stacks()
	Boons.note_element(Element.Type.FIRE)
	Boons.note_element(Element.Type.FIRE)
	var one_a_gap: bool = int(Boons.stacks.get(Element.Type.FIRE, 0)) == 1
	for i in Boons.STACK_MOST - 2:
		Boons._stack_at.clear()
		Boons.note_element(Element.Type.FIRE)
	var four: float = Boons.stack_scale(Element.Type.FIRE)
	Boons._stack_at.clear()
	Boons.note_element(Element.Type.FIRE)
	var burst: Array = Boons.take_bursts()
	Boons.note_element(Element.Type.POISON)
	Boons.note_element(Element.Type.NONE)
	Boons.note_element(Element.Type.ICE)
	Boons._stack_at.clear()
	Boons.note_element(Element.Type.ICE)
	Boons.fade_stacks(Boons.STACK_FADE + 0.05)
	check("elements stack, one an element every %.2f s: four fire hits make fire hit x%.1f, the fifth bursts and spends them; poison and a plain hit never stack; one goes every %.0f s"
		% [Boons.STACK_GAP, four, Boons.STACK_FADE],
		one_a_gap and
		is_equal_approx(four, 1.0 + 4.0 * Boons.STACK_STEP) and burst == [Element.Type.FIRE] and not Boons.stacks.has(Element.Type.FIRE)
		and not Boons.stacks.has(Element.Type.POISON) and not Boons.stacks.has(Element.Type.NONE)
		and int(Boons.stacks.get(Element.Type.ICE, 0)) == 1, Boons.stacks)
	var warrior: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	warrior.call("_set_stat_curve")
	warrior.set("level", 10)
	warrior.set("equipped", {})
	Boons.clear_stacks()
	var bare: int = int(warrior.call("damage_taken", 1000, Element.Type.FIRE))
	for i in 3:
		Boons._stack_at.clear()
		Boons.note_element(Element.Type.FIRE)
	var stacked: int = int(warrior.call("damage_taken", 1000, Element.Type.FIRE))
	var other: int = int(warrior.call("damage_taken", 1000, Element.Type.ICE))
	check("  a player with three fire stacks takes %d of a fire hit for %d bare - and an ice hit as ever (%d)" % [stacked, bare, other],
		absf(float(stacked) - float(bare) * 1.3) <= 1.0 and other == bare)
	warrior.free()
	var src: String = _code_src("res://src/characters/player.gd")
	var hit: String = _func_body(src, "func take_damage(")
	check("  take_damage(): the floor's own hit exact, the ward pierced by the hit's source, then the stack - before the health moves",
		hit.find("DescentBoons.take_exact()") != -1 and hit.find("DescentBoons.take_exact()") < hit.find("DescentBoons.absorb(reduced_amount, source, exact)")
		and hit.find("DescentBoons.absorb(reduced_amount, source, exact)") < hit.find("DescentBoons.note_element(element)")
		and hit.find("DescentBoons.note_element(element)") < hit.find("hp = clamp(hp - reduced_amount"))
	# ---- a burst, on a room's stand-in ----
	Boons.clear()
	var body_script := GDScript.new()
	body_script.source_code = "extends Node2D\nvar hp: int = 400\nvar max_hp: int = 400\nvar hits: Array = []\nvar said: Array = []\nfunc take_damage(amount: int, element: int = 0) -> void:\n\thits.append([amount, element])\nfunc show_notice(text: String) -> void:\n\tsaid.append(text)\n"
	body_script.reload()
	var made: Array = _descent_room_for_test(body_script)
	var room: Node2D = made[0]
	var desc: Node = made[1]
	var body: Node2D = made[2]
	await get_tree().process_frame
	Boons.active = true
	desc.call("_burst", Element.Type.FIRE)
	var lands: Node2D = desc.call("_lands_node")
	var flashed: bool = false
	for hz in lands.get("hazards"):
		flashed = flashed or str(hz["k"]) == "burst"
	check("a fire burst: %s of your health as fire, past everything, \"Ignited!\" over you and a flash" % [_mix_last(body)],
		_mix_last(body) == [roundi(400.0 * float(RunScript.BURSTS[Element.Type.FIRE][0])), Element.Type.FIRE]
		and (body.get("said") as Array).has("Ignited!") and flashed and not Boons.exact_once and int(desc.get("bursts_seen")) == 1)
	# ---- lasers ----
	lands.call("begin_env", RunScript.ALL_LANDS, 4)
	lands.set("_env_left", 999.0)
	lands.set("hazards", [])
	lands.set("_touch_left", 0.0)
	var beam: Dictionary = lands.call("spawn_env", "laser", body)
	beam["p"] = body.global_position
	beam["a"] = 0.0
	beam["spin"] = 0.0
	beam["e"] = Element.Type.LIGHT
	# Unbent, for the wall-to-wall check (they bend since 0.134.1 -
	# _test_the_lasers_bend()).
	beam["bend"] = 0.0
	var ends: Array = lands.call("beam_ends", beam)
	var rect: Rect2 = desc.get("room_rect")
	var count_was: int = (body.get("hits") as Array).size()
	lands.call("step", 0.5)
	var warned_only: bool = (body.get("hits") as Array).size() == count_was
	beam["t"] = float(beam["w"])
	lands.call("step", 0.016)
	check("a laser runs wall to wall (%.0f to %.0f), warns first, then burns you on its line for %s of your health as its land"
		% [(ends[0] as Vector2).x, (ends[1] as Vector2).x, str(_mix_last(body))],
		absf((ends[0] as Vector2).x - rect.position.x) < 6.0 and absf((ends[1] as Vector2).x - rect.end.x) < 6.0
		and warned_only and _mix_last(body) == [LandsScript.env_amount(4, 400, LandsScript.LASER_HIT), Element.Type.LIGHT]
		and not Boons.exact_once)
	lands.set("hazards", [])
	lands.set("_touch_left", 0.0)
	var miss: Dictionary = lands.call("spawn_env", "laser", body)
	miss["p"] = body.global_position + Vector2(0, -60)
	miss["a"] = 0.0
	miss["spin"] = 0.0
	miss["t"] = float(miss["w"])
	count_was = (body.get("hits") as Array).size()
	lands.call("step", 0.016)
	var turning: Dictionary = lands.call("spawn_env", "laser", body)
	turning["p"] = body.global_position + Vector2(0, -80)
	turning["a"] = 0.0
	var spins: bool = absf(float(turning["spin"])) > 0.0
	var a0: float = float(turning["a"])
	turning["t"] = float(turning["w"])
	lands.call("step", 0.2)
	check("  60 px off its line, nothing; from floor %d it turns as it burns, and comes at %.0f%% a gap on floor 1, every gap by floor %d"
		% [LandsScript.LASER_SPIN_FROM + 1, 100.0 * LandsScript.laser_chance(0), 8],
		(body.get("hits") as Array).size() == count_was and spins and absf(float(turning["a"]) - a0) > 0.05
		and LandsScript.laser_chance(7) == 1.0 and LandsScript.laser_chance(0) < 1.0)
	lands.call("end")
	room.queue_free()
	Boons.clear()
	await get_tree().process_frame
	print("  the descent bites: done")


func _test_cut_the_cloth() -> void:
	section("CUT THE CLOTH (0.130.0): cut the old map away from the slimes, a round at a time")
	const ClothRun := preload("res://src/world/cloth/clothrun.gd")
	const ClothScreen := preload("res://src/world/cloth/clothscreen.gd")
	check("the rounds: clear at 75%%, a point more each round, never over 85%% (%s); 3 slimes, more as it goes, never over 7 (%s); 5%% faster a round to round 10, then 4%%, never over 2x" % [
		[ClothRun.target_for(1), ClothRun.target_for(2), ClothRun.target_for(11), ClothRun.target_for(30)],
		[ClothRun.slimes_for(1), ClothRun.slimes_for(3), ClothRun.slimes_for(8), ClothRun.slimes_for(41)]],
		is_equal_approx(ClothRun.target_for(1), 0.75) and is_equal_approx(ClothRun.target_for(2), 0.76)
		and is_equal_approx(ClothRun.target_for(11), 0.85) and is_equal_approx(ClothRun.target_for(30), 0.85)
		and ClothRun.slimes_for(1) == 3 and ClothRun.slimes_for(3) == 4 and ClothRun.slimes_for(8) == 7
		and ClothRun.slimes_for(41) == 7 and is_equal_approx(ClothRun.speed_for(1), 1.0)
		and is_equal_approx(ClothRun.speed_for(10), 1.45) and is_equal_approx(ClothRun.speed_for(11), 1.49)
		and is_equal_approx(ClothRun.speed_for(60), 2.0))
	var run: Node2D = ClothRun.new()
	run.set("seed_value", 7)
	add_child(run)
	run.set_physics_process(false)
	var cols: int = ClothRun.COLS
	var rows: int = ClothRun.ROWS
	var border_own: bool = true
	var inside_open: bool = true
	for y in rows:
		for x in cols:
			var s: int = run.grid[y * cols + x]
			var rim: bool = x < ClothRun.BORDER or y < ClothRun.BORDER or x >= cols - ClothRun.BORDER or y >= rows - ClothRun.BORDER
			border_own = border_own and (not rim or s == ClothRun.OWN)
			inside_open = inside_open and (rim or s == ClothRun.OPEN)
	check("a fresh cloth: its border cut away, the rest whole, nothing taken, the shot on the edge, 3 slimes, 3 lives",
		border_own and inside_open and run.taken == 0.0 and run.is_edge(run.cutter) and run.slimes_left() == 3
		and run.lives == 3 and run.state == ClothRun.State.PLAYING, [run.cutter, run.slimes_left()])
	var told: Dictionary = {"hurt": 0, "cleared": [], "over": []}
	run.hurt.connect(func() -> void: told["hurt"] = int(told["hurt"]) + 1)
	run.round_cleared.connect(func(w: int) -> void: (told["cleared"] as Array).append(w))
	run.run_over.connect(func(w: int) -> void: (told["over"] as Array).append(w))
	# ---- a cut up the middle, every slime on the right: the left is cut away ----
	var mid: int = 78
	for f in run.foes:
		f["p"] = run.px(Vector2i(120, 20 + run.foes.find(f) * 15))
		f["v"] = Vector2.ZERO
	run.cutter = Vector2i(mid, rows - 1 - ClothRun.BORDER + 1)
	run.cutter_px = run.px(run.cutter)
	run.aim = null
	run.steer = Vector2.UP
	run.cut_held = true
	var t0: int = Time.get_ticks_usec()
	var steps: int = 0
	var was_cutting: bool = false
	while steps < 400:
		steps += 1
		run.call("_move_shot", 0.05)
		was_cutting = was_cutting or run.cutting
		if was_cutting and not run.cutting:
			break
	var close_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	var left_gone: bool = true
	var right_whole: bool = true
	for y in range(ClothRun.BORDER, rows - ClothRun.BORDER):
		for x in range(ClothRun.BORDER, cols - ClothRun.BORDER):
			var s: int = run.grid[y * cols + x]
			if x <= mid:
				left_gone = left_gone and s == ClothRun.OWN
			else:
				right_whole = right_whole and s == ClothRun.OPEN
	var share: float = float((mid - 1) * (rows - 4)) / float((cols - 4) * (rows - 4))
	check("held cut, the shot burns a line up through the cloth; back on the edge it closes, and the half with no slime on it is cut away (%d%% taken, the line and the close in %.1f ms)" % [
		roundi(run.taken * 100.0), close_ms],
		was_cutting and not run.cutting and run.line.is_empty() and left_gone and right_whole
		and absf(run.taken - share) < 0.01 and run.is_edge(run.cutter) and run.slimes_left() == 3 and run.dissolving.size() > 0,
		[run.taken, share, run.cutter])
	# ---- a slime on each side: only the line goes ----
	run.begin(1)
	run.set_physics_process(false)
	for f in run.foes:
		f["v"] = Vector2.ZERO
	run.foes[0]["p"] = run.px(Vector2i(20, 40))
	run.foes[1]["p"] = run.px(Vector2i(130, 40))
	run.foes[2]["p"] = run.px(Vector2i(140, 60))
	run.cutter = Vector2i(mid, rows - 2)
	run.cutter_px = run.px(run.cutter)
	steps = 0
	was_cutting = false
	while steps < 400:
		steps += 1
		run.call("_move_shot", 0.05)
		was_cutting = was_cutting or run.cutting
		if was_cutting and not run.cutting:
			break
	var line_share: float = float(rows - 4) / float((cols - 4) * (rows - 4))
	check("  a slime on each side: nothing but the line itself is cut away (%.1f%%)" % (run.taken * 100.0),
		was_cutting and absf(run.taken - line_share) < 0.002, [run.taken, line_share])
	# ---- let go mid-cut: the shot waits on its line ----
	run.begin(1)
	run.set_physics_process(false)
	for f in run.foes:
		f["v"] = Vector2.ZERO
		f["p"] = run.px(Vector2i(130, 20))
	run.cutter = Vector2i(40, rows - 2)
	run.cutter_px = run.px(run.cutter)
	for k in 12:
		run.call("_move_shot", 0.05)
	var cut_so_far: int = run.line.size()
	var stood: Vector2i = run.cutter
	run.cut_held = false
	for k in 12:
		run.call("_move_shot", 0.05)
	check("  let go mid-cut and the shot waits on its line (%d cells cut)" % cut_so_far,
		cut_so_far >= 6 and run.cutting and run.cutter == stood and run.line.size() == cut_so_far)
	# ---- a slime on the open line costs a life ----
	var from: Vector2i = run.cut_from
	run.foes[0]["p"] = run.px(run.line[2])
	run.call("_move_slimes", 0.0)
	var reverted: bool = true
	for y in rows:
		for x in cols:
			reverted = reverted and run.grid[y * cols + x] != ClothRun.LINE
	check("a slime touching the open cut costs a life: the line is gone (back to cloth), the shot back where it began, and the screen is told",
		run.lives == 2 and int(told["hurt"]) == 1 and not run.cutting and run.line.is_empty() and reverted
		and run.cutter == from and run.state == ClothRun.State.PLAYING, [run.lives, told["hurt"]])
	# ---- a slime touching the shot while it cuts, too; none left is the end ----
	for k in 2:
		run.grace_left = 0.0
		run.cut_held = true
		run.steer = Vector2.UP
		run.foes[0]["p"] = run.px(Vector2i(130, 20))
		for n in 4:
			run.call("_move_shot", 0.05)
		run.foes[0]["p"] = run.cutter_px
		run.call("_move_slimes", 0.0)
	check("  a slime on the shot while it cuts costs one too; the last life lost ends the run on its round (%s)" % [told["over"]],
		run.lives == 0 and run.state == ClothRun.State.OVER and told["over"] == [1] and int(told["hurt"]) == 3)
	# ---- the mouse: the shot rides the edge to the edge cell nearest it ----
	run.begin(1)
	run.set_physics_process(false)
	run.cut_held = false
	run.steer = Vector2.ZERO
	run.aim = ClothRun.ORIGIN + Vector2(4.5, 40.5) * ClothRun.CELL
	for k in 60:
		run.call("_move_shot", 0.05)
	var lined: bool = false
	for i in run.grid.size():
		lined = lined or run.grid[i] == ClothRun.LINE
	check("with the mouse and no cut held the shot rides the edge to the edge cell nearest it, cutting nothing (at %s)" % [run.cutter],
		run.cutter == Vector2i(1, 40) and not lined and not run.cutting)
	# the button held: it heads into the cloth for the mouse
	run.aim = ClothRun.ORIGIN + Vector2(30.5, 40.5) * ClothRun.CELL
	run.cut_held = true
	for k in 20:
		run.call("_move_shot", 0.05)
	check("  the button held, it cuts into the cloth toward the mouse (%d cells, at %s)" % [run.line.size(), run.cutter],
		run.cutting and run.line.size() >= 8 and run.cutter.y == 40 and run.cutter.x > 2)
	# ---- a round cleared: the next has its own cloth and slimes ----
	run.begin(1)
	run.set_physics_process(false)
	for f in run.foes:
		f["v"] = Vector2.ZERO
		f["p"] = run.px(Vector2i(10, 30))
	for y in range(ClothRun.BORDER, rows - ClothRun.BORDER):
		run.grid[y * cols + 30] = ClothRun.OWN
	run.line = []
	run.cutting = false
	run.call("_close")
	var cleared_at: float = run.taken
	var at_cleared: int = run.state
	run.call("_physics_process", ClothRun.CLEARED_SECONDS + 0.1)
	check("cut past the mark (%d%%) the round is cleared and said; after a moment round 2 begins on a fresh cloth, faster, and the best is kept" % roundi(cleared_at * 100.0),
		at_cleared == ClothRun.State.CLEARED and told["cleared"] == [1] and run.round_now == 2
		and run.state == ClothRun.State.PLAYING and run.taken == 0.0 and run.slimes_left() == ClothRun.slimes_for(2)
		and run.best == 1 and ClothRun.best_ever >= 1
		and is_equal_approx((run.foes[0]["v"] as Vector2).length(), ClothRun.FOE_SPEED * ClothRun.speed_for(2)))
	# a slime on cut-away cloth dissolves
	run.foes[0]["p"] = run.px(Vector2i(0, 0))
	run.call("_move_slimes", 0.0)
	check("  a slime that finds itself on cut-away cloth dissolves", run.slimes_left() == ClothRun.slimes_for(2) - 1)
	run.queue_free()
	await get_tree().process_frame
	# ---- the screen ----
	var screen: CanvasLayer = ClothScreen.open(get_tree())
	await get_tree().process_frame
	var srun: Node2D = screen.get("run")
	var drawn: Rect2 = screen.call("drawn_rect")
	var middle: Vector2 = screen.call("world_from_screen", drawn.get_center())
	check("the screen opens on its start panel, the run still behind it; a point on the picture is that point on the board (%s)" % [middle.round()],
		(screen.get("start_panel") as Control).visible and not srun.is_physics_processing()
		and middle.distance_to(ClothRun.VIEW / 2.0) < 1.0 and screen.layer == ClothScreen.LAYER)
	var way: Array = [Vector2.ZERO]
	var space: Array = [false]
	var held: Array = [false]
	var at: Array = [drawn.get_center()]
	screen.set("keys_way", func() -> Vector2: return way[0])
	screen.set("space_held", func() -> bool: return space[0])
	screen.set("mouse_held", func() -> bool: return held[0])
	screen.set("mouse_at", func() -> Vector2: return at[0])
	space[0] = true
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	screen.call("_input", key)
	await get_tree().process_frame
	var started: bool = not (screen.get("start_panel") as Control).visible and srun.is_physics_processing()
	var no_cut_yet: bool = not bool(srun.cut_held)
	space[0] = false
	await get_tree().process_frame
	space[0] = true
	way[0] = Vector2.UP
	await get_tree().process_frame
	check("Space starts it - and the Space that started it is not a cut; pressed again it cuts, the keys steering",
		started and no_cut_yet and bool(srun.cut_held) and srun.steer == Vector2.UP and srun.aim == null)
	space[0] = false
	way[0] = Vector2.ZERO
	var moved := InputEventMouseMotion.new()
	moved.relative = Vector2(12, 0)
	screen.call("_input", moved)
	held[0] = true
	at[0] = drawn.position + drawn.size * Vector2(0.25, 0.5)
	await get_tree().process_frame
	var aimed: Variant = srun.aim
	check("  the mouse moved, it takes over: the shot follows it, its button cuts",
		aimed != null and (aimed as Vector2).distance_to(ClothRun.VIEW * Vector2(0.25, 0.5)) < 1.0 and bool(srun.cut_held))
	srun.call("lose_life")
	await get_tree().process_frame
	var held_through: bool = bool(srun.cut_held)
	held[0] = false
	await get_tree().process_frame
	held[0] = true
	await get_tree().process_frame
	check("  a life lost, the button held through it does not cut again until it is let go and pressed",
		not held_through and bool(srun.cut_held))
	held[0] = false
	srun.call("lose_life")
	srun.call("lose_life")
	await get_tree().process_frame
	var results: Control = screen.get("results")
	check("the last life lost: how far you got (\"%s\"), with Again and Leave" % (screen.get("result_line") as Label).text,
		results.visible and (screen.get("result_line") as Label).text.contains("round 1")
		and results.find_child("again", true, false) != null and results.find_child("out", true, false) != null)
	screen.call("again")
	await get_tree().process_frame
	screen.call("begin")
	await get_tree().process_frame
	screen.call("ask_to_leave")
	await get_tree().process_frame
	var still: bool = is_instance_valid(screen) and screen.is_inside_tree()
	screen.call("ask_to_leave")
	await get_tree().process_frame
	check("  Again starts a fresh run; Leave asks twice while it is on, then it is gone",
		still and not is_instance_valid(screen))
	# ---- the card ----
	var card_hud := Control.new()
	add_child(card_hud)
	var card = (load("res://src/ui/minigames/minigamescard.gd") as GDScript).call("attach", card_hud)
	for seam in ["shows_healer_run", "shows_mage_stand", "shows_descent", "shows_forge", "shows_cloth"]:
		card.set(seam, func() -> bool: return true)
	var area: Array = ["elusion"]
	var opened: Array = []
	card.set("area_now", func() -> String: return area[0])
	card.set("class_now", func() -> String: return "healer")
	card.set("list_request", func(_p: String, _t: float = 0.0) -> Dictionary: return {"ok": false})
	var asked: Array = []
	card.set("enter_request", func(path: String, body: Dictionary, _t: float = 0.0) -> Dictionary:
		asked.append([path, body])
		return {"ok": true, "status": 200, "data": {"run": 77, "plays_left": 2, "pays": {"rounds": [5, 6]}}})
	card.set("open_cloth", func(run_on_server: int, what: Dictionary) -> void: opened.append([run_on_server, what]))
	card.call("open")
	await get_tree().process_frame
	await get_tree().process_frame
	var portraits: Array = card.cloth_box.find_children("*", "TextureRect", true, false)
	var town_ready: bool = card.cloth_box.visible and not card.cloth_go.disabled and portraits.size() == 1 \
		and (portraits[0] as TextureRect).texture != null
	var tall: float = card.size.y
	await card.call("_on_cloth_go")
	var went: bool = opened.size() == 1 and int(opened[0][0]) == 77 and (opened[0][1] as Dictionary).has("rounds") \
		and asked.size() == 1 and str(asked[0][0]) == "/api/minigames/enter" and str((asked[0][1] as Dictionary).get("game")) == "cloth" \
		and not card.visible
	area[0] = "field"
	card.call("paint")
	check("the Minigames card has its tile (the owner's while it is built), the healer's shot its portrait: Go in town asks the server for a run of the day and opens it on that run; elsewhere \"%s\"; all six tiles %d px tall" % [card.cloth_status.text, roundi(tall)],
		town_ready and went and card.cloth_go.disabled and card.cloth_status.text == "Play it from town." and tall < 560.0)
	card.set("shows_cloth", func() -> bool: return false)
	card.call("paint")
	check("  and it is nobody else's yet", not card.cloth_box.visible)
	card_hud.queue_free()
	await get_tree().process_frame
	print("  cut the cloth: done")


func _cloth_cut_left_half(run: Node2D) -> void:
	"""For the suite: every slime to the right, then a cut straight up at
	column 78 - the left half goes."""
	for f in run.foes:
		if float(f["dead"]) < 0.0:
			f["p"] = run.px(Vector2i(120, 20 + (run.foes.find(f) % 5) * 12))
			f["v"] = Vector2.ZERO
	run.saws = []
	run.cutter = Vector2i(78, run.ROWS - 2)
	run.cutter_px = run.px(run.cutter)
	run.aim = null
	run.steer = Vector2.UP
	run.cut_held = true
	var was_cutting: bool = false
	for k in 400:
		run.call("_move_shot", 0.05)
		was_cutting = was_cutting or run.cutting
		if was_cutting and not run.cutting:
			break


func _test_cut_the_cloth_rounds() -> void:
	section("CUT THE CLOTH, STEP 2 (0.131.0): lands, slime moves, saws, elites, the Plague Mother, pickups, gold")
	const ClothRun := preload("res://src/world/cloth/clothrun.gd")
	const ClothScreen := preload("res://src/world/cloth/clothscreen.gd")
	var lands: Array = []
	for w in range(1, 9):
		lands.append(ClothRun.land_of(w))
	var saw_counts: Array = [ClothRun.saws_for(1), ClothRun.saws_for(2), ClothRun.saws_for(4), ClothRun.saws_for(5),
		ClothRun.saws_for(8), ClothRun.saws_for(14)]
	var elite_counts: Array = [ClothRun.elites_for(2), ClothRun.elites_for(3), ClothRun.elites_for(6),
		ClothRun.elites_for(9), ClothRun.elites_for(16), ClothRun.elites_for(10)]
	check("a land a round in the bands' order, round again (%s); saws %s; elites %s; a boss every 5th round, with 2 slimes and no elites" % [
		lands, saw_counts, elite_counts],
		lands == ["light", "wind", "water", "ice", "earth", "fire", "dark", "light"]
		and saw_counts == [0, 1, 1, 2, 3, 4] and elite_counts == [0, 1, 2, 3, 4, 0]
		and ClothRun.is_boss_round(5) and ClothRun.is_boss_round(10) and not ClothRun.is_boss_round(4)
		and ClothRun.slimes_for(5) == ClothRun.BOSS_SLIMES and ClothRun.elites_for(5) == 0)
	check("  gold a round: its own from the table (100 for the first, 1,500 for the tenth), Endless rounds 800 and its bosses 1,600 - and the server's table when it gave one",
		ClothRun.gold_for_round(1) == 100 and ClothRun.gold_for_round(10) == 1500
		and ClothRun.gold_for_round(11) == ClothRun.ENDLESS_GOLD and ClothRun.gold_for_round(15) == ClothRun.ENDLESS_BOSS_GOLD
		and ClothRun.gold_for_round(2, {"rounds": [7, 8]}) == 8 and ClothRun.gold_for_round(3, {"rounds": [7, 8], "endless": 9}) == 9)
	var run: Node2D = ClothRun.new()
	run.set("seed_value", 3)
	add_child(run)
	run.set_physics_process(false)
	var heard: Array = []
	run.said.connect(func(text: String) -> void: heard.append(text))
	run.best = 3
	var three: int = int(run.call("gold_now"))
	run.pays = {"rounds": [1, 2, 3]}
	var paid_three: int = int(run.call("gold_now"))
	run.pays = {}
	run.round_now = 11
	var endless_title: String = str(run.call("round_title"))
	check("  a run's gold is its rounds cleared (%d, %d by the server's table); past round 10 it is \"%s\"" % [three, paid_three, endless_title],
		three == 450 and paid_three == 6 and endless_title == "Endless 1")
	# ---- the saws ----
	run.begin(2)
	run.set_physics_process(false)
	var saw: Dictionary = run.saws[0] if not run.saws.is_empty() else {}
	var rides: bool = not saw.is_empty() and run.is_edge(saw["c"])
	for k in 60:
		run.call("_saw_step", saw)
		rides = rides and run.is_edge(saw["c"])
	run.lives = 3
	run.grace_left = 0.0
	run.cutting = false
	saw["px"] = run.cutter_px
	run.call("_move_saws", 0.0)
	var cut_on_edge: int = run.lives
	run.grace_left = 0.0
	run.cutting = true
	saw["px"] = run.cutter_px
	run.call("_move_saws", 0.0)
	var while_cutting: int = run.lives
	run.cutting = false
	check("round 2 has an edge saw: it rides the cut edge (60 steps, every one on it); on the shot while it rides the edge it costs a life, while it cuts it cannot reach it",
		run.saws.size() == 1 and rides and cut_on_edge == 2 and while_cutting == 2)
	# ---- elites ----
	run.begin(3)
	run.set_physics_process(false)
	var hunter: Dictionary = {}
	for f in run.foes:
		if str(f["size"]) == "elite":
			hunter = f
	var first_y: float = 0.0
	if not hunter.is_empty():
		hunter["p"] = run.px(Vector2i(78, 30))
		hunter["v"] = Vector2.RIGHT * 40.0
		run.cutter_px = run.px(Vector2i(78, 79))
		for k in 10:
			run.call("_move_slimes", 0.1)
		first_y = (hunter["v"] as Vector2).normalized().y
	check("round 3 has an elite, bigger, a hunter: it turns toward the shot (heading %.2f down)" % first_y,
		not hunter.is_empty() and str(hunter["trick"]) == "hunter" and float(hunter["r"]) == ClothRun.ELITE_R and first_y > 0.3)
	run.begin(4)
	run.set_physics_process(false)
	var splitter: Dictionary = {}
	for f in run.foes:
		if str(f["trick"]) == "splitter":
			splitter = f
	var before_split: int = run.slimes_left()
	_cloth_cut_left_half(run)
	var smalls_of_kind: int = 0
	for f in run.foes:
		if float(f["dead"]) < 0.0 and str(f["size"]) == "small" and not splitter.is_empty() and str(f["kind"]) == str(splitter["kind"]):
			smalls_of_kind += 1
	check("  round 4's elite is a splitter: a cut that takes enough of the cloth splits it in two (%d slimes, then %d)" % [before_split, run.slimes_left()],
		not splitter.is_empty() and float(splitter["dead"]) >= 0.0 and run.slimes_left() == before_split + 1
		and smalls_of_kind >= 2 and heard.has("The splitter split in two!"))
	run.begin(8)
	run.set_physics_process(false)
	var gnawer: Dictionary = {}
	for f in run.foes:
		if str(f["trick"]) == "gnawer":
			gnawer = f
	for y in range(36, 47):
		for x in range(36, 47):
			run.grid[y * run.COLS + x] = run.OWN
	run.call("_mark_edges")
	run.call("_count")
	var had: float = run.taken
	run.cutting = false
	run.cutter = Vector2i(120, run.ROWS - 2)
	if not gnawer.is_empty():
		gnawer["gnaw"] = 0.0
		run.call("_gnaw", gnawer, Vector2i(36, 41))
		gnawer["gnaw"] = 0.0
		run.call("_gnaw", gnawer, Vector2i(1, 41))
	var chewed_open: bool = run.grid[41 * run.COLS + 36] == run.OPEN and run.grid[41 * run.COLS + 1] == run.OWN
	check("  round 8's second elite is a gnawer: it chews cut-away cloth back (%.2f%% then %.2f%%) - never the border" % [had * 100.0, run.taken * 100.0],
		not gnawer.is_empty() and chewed_open and run.taken < had)
	# ---- the Plague Mother ----
	run.begin(5)
	run.set_physics_process(false)
	var mother: Dictionary = run.call("_mother")
	var smalls_before: int = run.slimes_left()
	if not mother.is_empty():
		mother["brood"] = 0.0
		run.call("_brood", mother, 0.01)
	var spat: bool = run.slimes_left() == smalls_before + 1
	for f in run.foes:
		f["p"] = run.px(Vector2i(10, 20 + (run.foes.find(f) % 6) * 8))
		f["v"] = Vector2.ZERO
	for y in range(run.BORDER, run.ROWS - run.BORDER):
		run.grid[y * run.COLS + 30] = run.OWN
	run.line = []
	run.cutting = false
	run.call("_close")
	check("round 5 is the Plague Mother's: huge, she spits slimes; sealed into %d%% of the cloth (no more than %d%%) the round is cleared" % [
		roundi(run.boss_share * 100.0), roundi(ClothRun.SEAL_SHARE * 100.0)],
		not mother.is_empty() and float(mother["r"]) == ClothRun.BOSS_R and spat and run.boss_share <= ClothRun.SEAL_SHARE
		and run.state == ClothRun.State.CLEARED and heard.has("The Plague Mother is sealed!") and float(mother["dead"]) >= 0.0)
	# ---- the lands ----
	run.begin(4)
	run.set_physics_process(false)
	for f in run.foes:
		f["p"] = run.px(Vector2i(130, 20))
		f["v"] = Vector2.ZERO
	run.saws = []
	run.cutter = Vector2i(40, run.ROWS - 2)
	run.cutter_px = run.px(run.cutter)
	run.aim = null
	run.steer = Vector2.UP
	run.cut_held = true
	for k in 6:
		run.call("_move_shot", 0.05)
	var cut_so_far: int = run.line.size()
	run.cut_held = false
	run.steer = Vector2.ZERO
	for k in 6:
		run.call("_move_shot", 0.05)
	check("ice: let go mid-cut and the shot slides on (%d cells, then %d)" % [cut_so_far, run.line.size()],
		run.land == "ice" and cut_so_far > 0 and run.line.size() > cut_so_far and run.cutting)
	run.begin(6)
	run.set_physics_process(false)
	for f in run.foes:
		f["p"] = run.px(Vector2i(130, 20))
		f["v"] = Vector2.ZERO
	run.saws = []
	run.lives = 3
	run.grace_left = 0.0
	run.cutter = Vector2i(40, run.ROWS - 2)
	run.cutter_px = run.px(run.cutter)
	run.steer = Vector2.UP
	run.cut_held = true
	for k in 10:
		run.call("_move_shot", 0.05)
	run.cut_held = false
	var fuse_seen: bool = false
	for k in 40:
		run.call("_move_shot", 0.1)
		run.call("_land_effects", 0.1)
		fuse_seen = fuse_seen or run.fuse >= 0.0
		if run.lives < 3:
			break
	check("fire: a cut left standing still lights a fuse that burns back along it - when it reaches the shot, a life",
		run.land == "fire" and fuse_seen and run.lives == 2 and heard.has("The fuse caught you!"))
	run.begin(3)
	run.set_physics_process(false)
	var wet_cell := Vector2i(-1, -1)
	for i in run.wet.size():
		if run.wet[i] == 1:
			wet_cell = Vector2i(i % run.COLS, floori(float(i) / float(run.COLS)))
			break
	var dry_speed: float = 0.0
	var wet_speed: float = 0.0
	if wet_cell.x >= 0:
		run.cutting = true
		run.cut_held = true
		run.cutter = wet_cell
		wet_speed = float(run.call("_shot_speed"))
		run.cutter = Vector2i(1, 1)
		dry_speed = float(run.call("_shot_speed"))
		run.cutting = false
		run.cut_held = false
	check("water: wet patches on the cloth, where the cut goes at half speed (%.0f against %.0f)" % [wet_speed, dry_speed],
		run.land == "water" and wet_cell.x >= 0 and is_equal_approx(wet_speed, ClothRun.CUT_SPEED * ClothRun.WET_SLOW)
		and is_equal_approx(dry_speed, ClothRun.CUT_SPEED))
	run.begin(2)
	run.set_physics_process(false)
	var blown: Dictionary = run.foes[0]
	blown["p"] = run.px(Vector2i(60, 40))
	blown["v"] = Vector2.ZERO
	run.gust_dir = Vector2.RIGHT
	run.gust_on = 1.0
	run.call("_move_slimes", 0.5)
	var pushed: float = (blown["p"] as Vector2).x - run.px(Vector2i(60, 40)).x
	run.gust_on = 0.0
	check("wind: a gust shoves the slimes along it (%.0f px in half a second)" % pushed,
		run.land == "wind" and absf(pushed - ClothRun.GUST_PUSH * 0.5) < 1.0)
	run.begin(1)
	run.set_physics_process(false)
	var dazzled: Dictionary = run.foes[0]
	dazzled["p"] = run.px(Vector2i(60, 40))
	dazzled["v"] = Vector2.RIGHT * 50.0
	run.flares = [{"at": run.px(Vector2i(62, 40)), "warn": 0.01, "flash": 0.0}]
	run.call("_land_effects", 0.05)
	var at_daze: Vector2 = dazzled["p"]
	run.call("_move_slimes", 0.3)
	check("light: a flare dazzles the slimes in it still for a moment",
		run.land == "light" and float(dazzled["dazed"]) > 0.0 and (dazzled["p"] as Vector2) == at_daze)
	run.begin(12)
	run.set_physics_process(false)
	var rock_cells: int = 0
	var rock_own: bool = true
	for i in run.rock.size():
		if run.rock[i] == 1:
			rock_cells += 1
			rock_own = rock_own and run.grid[i] == run.OWN
	check("earth: rocks on the map (%d cells), already cut - the round starts %.1f%% taken" % [rock_cells, run.taken * 100.0],
		run.land == "earth" and rock_cells > 40 and rock_own and run.taken > 0.0)
	run.begin(7)
	run.set_physics_process(false)
	var dark_on: bool = (run.get("_dark") as Node2D).visible
	run.begin(1)
	run.set_physics_process(false)
	check("  dark: only the shot's light to see by (and every other land in the light)",
		dark_on and not (run.get("_dark") as Node2D).visible)
	# ---- the slimes' moves ----
	var hopper: Dictionary = run.call("_add_slime", "earth", run.px(Vector2i(60, 40)), Vector2.RIGHT, "small", "")
	hopper["t"] = 0.05
	var hop_from: Vector2 = hopper["p"]
	run.call("_move_slimes", 0.05)
	var still_while_crouched: bool = (hopper["p"] as Vector2) == hop_from
	hopper["t"] = 0.6
	run.call("_move_slimes", 0.05)
	check("each colour moves its own way (%s): an earth slime crouches still, then hops on" % [ClothRun.MOVES],
		ClothRun.MOVES["water"] == "bounce" and ClothRun.MOVES["wind"] == "zigzag" and ClothRun.MOVES["earth"] == "hop"
		and ClothRun.MOVES["fire"] == "hunt" and still_while_crouched and (hopper["p"] as Vector2).x > hop_from.x)
	# ---- pickups ----
	run.begin(1)
	run.set_physics_process(false)
	run.ward = false
	run.pickups = [{"kind": "ward", "c": Vector2i(20, 40), "left": 10.0}]
	_cloth_cut_left_half(run)
	var cut_free: bool = run.ward and run.pickups.is_empty()
	run.lives = 3
	run.grace_left = 0.0
	run.call("_hit", null)
	var warded: bool = run.lives == 3 and not run.ward and heard.has("The Ward held!")
	run.call("_hit", null)
	var graced: bool = run.lives == 3
	run.grace_left = 0.0
	run.call("_hit", null)
	check("pickups: a Ward cut free is had; it takes the next hit, a moment's grace after, then a hit is a life again",
		cut_free and warded and graced and run.lives == 2)
	run.call("_take", {"kind": "slow", "c": Vector2i(30, 30), "left": 5.0})
	var slow_speed: float = float(run.call("_slime_speed", run.foes[0]))
	run.slow_left = 0.0
	var full_speed: float = float(run.call("_slime_speed", run.foes[0]))
	run.call("_take", {"kind": "swift", "c": Vector2i(30, 30), "left": 5.0})
	run.cut_held = true
	run.cutting = false
	var swift_speed: float = float(run.call("_shot_speed"))
	run.cut_held = false
	run.lives = ClothRun.LIVES_MOST - 1
	run.call("_take", {"kind": "life", "c": Vector2i(30, 30), "left": 5.0})
	run.call("_take", {"kind": "life", "c": Vector2i(30, 30), "left": 5.0})
	check("  Slow halves the slimes (%.0f of %.0f), Swift quickens the cut (%.0f), a Life is a life - never past %d" % [
		slow_speed, full_speed, swift_speed, ClothRun.LIVES_MOST],
		is_equal_approx(slow_speed, full_speed * ClothRun.SLOW_SPEED) and is_equal_approx(swift_speed, ClothRun.CUT_SPEED * ClothRun.SWIFT_SPEED)
		and run.lives == ClothRun.LIVES_MOST)
	run.swift_left = 0.0
	run.begin(1)
	run.set_physics_process(false)
	for f in run.foes:
		f["p"] = run.px(Vector2i(130, 20))
		f["v"] = Vector2.ZERO
	run.pickups = [{"kind": "swift", "c": Vector2i(40, run.ROWS - 6), "left": 10.0}]
	run.cutter = Vector2i(40, run.ROWS - 2)
	run.cutter_px = run.px(run.cutter)
	run.steer = Vector2.UP
	run.cut_held = true
	for k in 8:
		run.call("_move_shot", 0.05)
	check("  and a pickup the cut runs over is had too", run.swift_left > 0.0 and run.pickups.is_empty())
	# ---- what it costs ----
	run.begin(9)
	run.set_physics_process(false)
	var t0: int = Time.get_ticks_usec()
	_cloth_cut_left_half(run)
	var close_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	run.aim = run.px(Vector2i(5, 5))
	run.cut_held = false
	t0 = Time.get_ticks_usec()
	for k in 30:
		run.aim = run.px(Vector2i(5 + k, 5 + (k % 7)))
		run.call("_move_shot", 0.016)
	var ride_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0 / 30.0
	print("  [CLOTH] a cut and its close %.1f ms; a frame of riding with the mouse moving %.2f ms" % [close_ms, ride_ms])
	run.queue_free()
	await get_tree().process_frame
	# ---- the screen, paying ----
	var screen: CanvasLayer = ClothScreen.open(get_tree(), null, 41, {"rounds": [10, 20]})
	var sent: Array = []
	screen.set("finish_request", func(path: String, body: Dictionary, _t: float = 0.0) -> Dictionary:
		sent.append([path, body])
		return {"ok": true, "status": 200, "data": {"gold": 10, "status": {"gold": 999}}})
	await get_tree().process_frame
	screen.call("begin")
	var srun: Node2D = screen.get("run")
	srun.best = 1
	await get_tree().process_frame
	var counted: int = int(srun.call("gold_now"))
	screen.call("ask_to_leave")
	screen.call("ask_to_leave")
	await get_tree().process_frame
	await get_tree().process_frame
	check("a run on the server counts its gold on screen (%d by its table) and Leave finishes it there with the rounds cleared (%s)" % [
		counted, str(sent[0][1]) if not sent.is_empty() else "nothing sent"],
		counted == 10 and sent.size() == 1 and str(sent[0][0]) == "/api/minigames/finish"
		and int((sent[0][1] as Dictionary).get("run", 0)) == 41 and int((sent[0][1] as Dictionary).get("rounds", -1)) == 1
		and not is_instance_valid(screen))
	var screen2: CanvasLayer = ClothScreen.open(get_tree(), null, 42, {})
	screen2.set("finish_request", func(_p: String, _b: Dictionary, _t: float = 0.0) -> Dictionary:
		return {"ok": true, "status": 200, "data": {"gold": 0}})
	screen2.set("enter_request", func(_p: String, _b: Dictionary, _t: float = 0.0) -> Dictionary:
		return {"ok": false, "status": 409, "data": {"message": "You have run Cut the Cloth 3 times today."}})
	await get_tree().process_frame
	screen2.call("begin")
	(screen2.get("run") as Node2D).call("lose_life")
	(screen2.get("run") as Node2D).call("lose_life")
	(screen2.get("run") as Node2D).call("lose_life")
	await get_tree().process_frame
	await screen2.call("again")
	check("  Again with no runs left today says so in the server's words, and Again goes grey",
		(screen2.get("result_line") as Label).text.contains("3 times today") and (screen2.get("again_button") as Button).disabled)
	screen2.call("close")
	await get_tree().process_frame
	print("  cut the cloth, step 2: done")


func _test_spikes_read_the_player_late() -> void:
	# The owner, of the remade Crowned (0.134.1): "those spikes from the
	# ground are deadly accurate and they predict the player well i think we
	# need to improve the logic on that". bossenemy.gd, AIM_LEAD: the boss
	# leads by the heading it has SEEN (eased over AIM_REACTION), by less
	# (0.75), with a little doubt (AIM_SCATTER).
	section("Spikes read the player late")
	var world := Node2D.new()
	add_child(world)
	var boss: Node2D = (load("res://scene/enemy/bossenemy.tscn") as PackedScene).instantiate() as Node2D
	boss.position = Vector2(500, 400)
	world.add_child(boss)
	boss.reset_physics_interpolation()
	boss.process_mode = Node.PROCESS_MODE_DISABLED
	var runner := CharacterBody2D.new()
	runner.position = Vector2(560, 420)
	world.add_child(runner)
	runner.reset_physics_interpolation()
	runner.add_to_group(&"player")
	boss.set("_aim_target", runner)
	var tick: float = 1.0 / 80.0
	var shift_for := func(telegraph: float) -> Vector2:
		var pattern: Array[Dictionary] = [{"pos": Vector2(1000, 1000), "telegraph": telegraph}]
		var led: Array[Dictionary] = boss.call("_lead_pattern", pattern, &"lines")
		return (led[0]["pos"] as Vector2) - Vector2(1000, 1000)
	runner.velocity = Vector2(200, 0)
	for k in 160:
		boss.call("watch_runners", tick)
	var want: float = 200.0 * 0.5 * BossEnemy.AIM_LEAD
	var worst := 0.0
	var all_near := true
	for k in 40:
		var shift: Vector2 = shift_for.call(0.5)
		worst = maxf(worst, shift.distance_to(Vector2(want, 0)))
		all_near = all_near and shift.distance_to(Vector2(want, 0)) <= BossEnemy.AIM_SCATTER + 0.01
	check("a runner in a straight line is led by 0.75 of their heading, give or take the doubt (16 px)",
		is_equal_approx(BossEnemy.AIM_LEAD, 0.75) and all_near and worst > 1.0, [want, worst])
	runner.velocity = Vector2(0, -200)
	for k in 8:
		boss.call("watch_runners", tick)
	var seen: Vector2 = boss.call("seen_velocity", runner)
	check("  a tenth of a second after they turn, it still reads them going the old way",
		seen.x > 120.0 and seen.y > -80.0 and (boss.call("_player_velocity") as Vector2) == seen, seen)
	for k in 96:
		boss.call("watch_runners", tick)
	seen = boss.call("seen_velocity", runner)
	check("  about a second on, it has caught up with the turn",
		seen.y < -180.0 and absf(seen.x) < 20.0, seen)
	runner.velocity = Vector2.ZERO
	for k in 240:
		boss.call("watch_runners", tick)
	var still: Vector2 = shift_for.call(0.5)
	check("  a player who has stood still a moment gets no lead and no doubt: it lands on them",
		still == Vector2.ZERO, still)
	runner.remove_from_group(&"player")
	boss.call("watch_runners", tick)
	check("  somebody out of the fight is forgotten",
		(boss.get("_seen_heading") as Dictionary).is_empty())
	var src: String = FileAccess.get_file_as_string("res://src/enemies/bossenemy.gd")
	var at: int = _first_code_index(src, "func _physics_process(delta: float) -> void:", 0)
	var watch: int = _first_code_index(src, "watch_runners(delta)", at)
	check("  every tick the boss watches who is in the fight (not a picture of another game's boss)",
		at != -1 and _within(watch, src.find("\nfunc ", at + 10)) != -1
		and _first_code_index(src, "if not net_mirror:", at) != -1
		and _first_code_index(src, "if not net_mirror:", at) < watch)
	world.queue_free()
	await get_tree().process_frame
	print("  spikes read the player late: done")


func _laser_on_edge(at: Vector2, rect: Rect2) -> bool:
	return minf(minf(absf(at.x - rect.position.x), absf(at.x - rect.end.x)),
		minf(absf(at.y - rect.position.y), absf(at.y - rect.end.y))) < 2.0


func _test_the_lasers_bend() -> void:
	# The owner, of the crossing lasers: "the x lasers are cool but i need
	# them to bend and carry effects with them" - and "curve and whip"
	# (0.134.1, descentlands.gd THEY BEND AND CARRY THEIR LAND).
	section("The lasers bend, whip, and carry their land")
	const RunScript := preload("res://src/world/descent/descentrun.gd")
	const LandsScript := preload("res://src/world/descent/descentlands.gd")
	const Boons := preload("res://src/world/descent/descentboons.gd")
	Boons.clear()
	var body_script := GDScript.new()
	body_script.source_code = "extends Node2D\nvar hp: int = 400\nvar max_hp: int = 400\nvar hits: Array = []\nfunc take_damage(amount: int, element: int = 0) -> void:\n\thits.append([amount, element])\n"
	body_script.reload()
	var made: Array = _descent_room_for_test(body_script)
	var room: Node2D = made[0]
	var run: Node = made[1]
	var body: Node2D = made[2]
	await get_tree().process_frame
	var lands: Node2D = run.call("_lands_node")
	lands.call("begin_env", RunScript.ALL_LANDS, 4)
	_mix_fresh(lands)
	body.global_position = (run.get("room_rect") as Rect2).get_center()
	var at: Vector2 = body.global_position
	var walls: Rect2 = (run.get("room_rect") as Rect2).grow(-4.0)
	var far: Vector2 = (run.get("room_rect") as Rect2).position + Vector2(14, 14)
	# ---- an arc through its spot, wall to wall, swaying ----
	var beam: Dictionary = lands.call("spawn_env", "laser", body)
	beam["p"] = at
	beam["a"] = 0.0
	beam["spin"] = 0.0
	beam["ph"] = PI / 2.0
	var line: PackedVector2Array = lands.call("beam_points", beam)
	var bent := 0.0
	for q in line:
		bent = maxf(bent, q.y - at.y)
	var ends: Array = lands.call("beam_ends", beam)
	check("a laser is an arc: through its spot, %.0f px off its straight line at the most, meeting the walls at both ends" % bent,
		line.has(at) and bent > 40.0 and _laser_on_edge(ends[0], walls) and _laser_on_edge(ends[1], walls)
		and is_equal_approx(float(beam["bend"]), LandsScript.LASER_BEND), [ends, bent])
	beam["t"] = LandsScript.LASER_WHIP_SECONDS / 2.0
	var other_way := 0.0
	for q in lands.call("beam_points", beam):
		other_way = minf(other_way, (q as Vector2).y - at.y)
	check("  half a sway (%.1f s) later it bends the other way (%.0f px)" % [LandsScript.LASER_WHIP_SECONDS / 2.0, other_way],
		other_way < -40.0)
	# ---- it burns you on its curve, not on its straight line ----
	_mix_fresh(lands)
	var spot: Vector2 = at + Vector2(-200, 0)
	var arc: Dictionary = lands.call("spawn_env", "laser", body)
	arc["p"] = spot
	arc["a"] = 0.0
	arc["spin"] = 0.0
	arc["e"] = Element.Type.FIRE
	arc["t"] = float(arc["w"])
	arc["ph"] = PI / 2.0 - TAU * float(arc["w"]) / LandsScript.LASER_WHIP_SECONDS
	arc["t"] = float(arc["w"]) + 0.016
	var curve_then: float = lands.call("beam_curve", arc)
	arc["t"] = float(arc["w"])
	body.global_position = lands.call("_arc_point", spot, 0.0, curve_then, 200.0)
	var off_line: float = body.global_position.y - at.y
	lands.call("step", 0.016)
	var on_curve: Array = _mix_last(body)
	_mix_fresh(lands)
	var count_was: int = (body.get("hits") as Array).size()
	var straight: Dictionary = arc.duplicate()
	straight["landed"] = false
	straight["fired"] = false
	straight["t"] = float(arc["w"])
	straight.erase("pts")
	lands.set("hazards", [straight])
	body.global_position = at
	lands.call("step", 0.016)
	check("  it burns you where it bends (%.0f px off the straight line): %s as its land - and not on the straight line"
		% [off_line, str(on_curve)],
		off_line > 25.0 and on_curve == [LandsScript.env_amount(4, 400, LandsScript.LASER_HIT), Element.Type.FIRE]
		and (body.get("hits") as Array).size() == count_was)
	# ---- its land rides along it ----
	var riding: PackedVector2Array = lands.call("motes", straight)
	var on_it: bool = riding.size() == LandsScript.LASER_MOTES
	for q in riding:
		on_it = on_it and q.distance_to(lands.call("closest_on_beam", straight, q)) <= LandsScript.LASER_MOTE_SWAY + 1.0
	check("  %d pieces of its land ride along it, swirling round it (none more than %.0f px off it)"
		% [riding.size(), LandsScript.LASER_MOTE_SWAY], on_it)
	# ---- it leaves its land where it burned ----
	body.global_position = far
	var left: Dictionary = {}
	var all_near: bool = true
	for land in [Element.Type.FIRE, Element.Type.ICE, Element.Type.WATER, Element.Type.WIND,
			Element.Type.LIGHT, Element.Type.EARTH, Element.Type.DARK]:
		_mix_fresh(lands)
		var fading: Dictionary = lands.call("spawn_env", "laser", body)
		fading["p"] = at
		fading["a"] = 0.0
		fading["spin"] = 0.0
		fading["e"] = land
		fading["fired"] = true
		fading["landed"] = true
		fading["t"] = float(fading["life"]) - LandsScript.LASER_TRAIL_BEFORE - 0.001
		lands.call("step", 0.016)
		var pieces: Array = []
		for hz in lands.get("hazards"):
			if bool(hz.get("trail", false)):
				pieces.append(str(hz["k"]))
				all_near = all_near and (hz["p"] as Vector2).distance_to(lands.call("closest_on_beam", fading, hz["p"])) < 3.0 \
					and (hz["p"] as Vector2).distance_to(at) <= LandsScript.LASER_TRAIL_REACH + 1.0
		left[land] = pieces
	check("  as it fades it leaves its land along it, near its spot: fire scorches, ice ice, water puddles, light flares, earth rubble, dark shade; wind nothing",
		left[Element.Type.FIRE] == ["scorch", "scorch", "scorch", "scorch", "scorch", "scorch", "scorch"]
		and (left[Element.Type.ICE] as Array).count("ice") == 7 and (left[Element.Type.WATER] as Array).count("puddle") == 7
		and left[Element.Type.LIGHT] == ["flare", "flare", "flare"] and (left[Element.Type.EARTH] as Array).count("rubble") == 7
		and (left[Element.Type.DARK] as Array).count("shade") == 7 and (left[Element.Type.WIND] as Array).is_empty() and all_near,
		left)
	# ---- standing on it ----
	_mix_fresh(lands)
	body.global_position = at
	var scorch: Dictionary = lands.call("trail_patch", "scorch", at)
	lands.set("hazards", [scorch])
	lands.call("step", 0.016)
	var too_soon: bool = (body.get("hits") as Array).size() == count_was
	scorch["t"] = LandsScript.LASER_TRAIL_WARN
	lands.call("step", 0.016)
	var burned: Array = _mix_last(body)
	_mix_fresh(lands)
	var rubble: Dictionary = lands.call("trail_patch", "rubble", at)
	rubble["t"] = LandsScript.LASER_TRAIL_WARN
	lands.set("hazards", [rubble])
	var before_rubble: int = (body.get("hits") as Array).size()
	lands.call("step", 0.016)
	lands.set("_touch_left", 0.0)
	lands.call("step", 0.016)
	check("  a piece grows in first (no hit), then a scorch burns you for half a hazard (%s); rubble roots you once" % [burned],
		too_soon and burned == [LandsScript.env_amount(4, 400, 0.5), Element.Type.FIRE]
		and (body.get("hits") as Array).size() == before_rubble + 1 and _mix_last(body)[1] == Element.Type.EARTH)
	# ---- wind blows what floats along it ----
	_mix_fresh(lands)
	body.global_position = far
	var gale: Dictionary = lands.call("spawn_env", "laser", body)
	gale["p"] = at
	gale["a"] = 0.0
	gale["spin"] = 0.0
	gale["bend"] = 0.0
	gale["e"] = Element.Type.WIND
	gale["t"] = float(gale["w"])
	var floating: Dictionary = lands.call("spawn_env", "bubble", body)
	floating["p"] = at + Vector2(60, 10)
	floating["v"] = Vector2.ZERO
	lands.call("step", 0.016)
	check("  a wind laser blows what floats near it along it (a bubble from x %.0f to %.0f)" % [at.x + 60.0, (floating["p"] as Vector2).x],
		(floating["p"] as Vector2).x > at.x + 60.0 + LandsScript.GUST_PUSH * 0.9)
	# ---- the X ----
	_mix_fresh(lands)
	lands.call("begin_env", [Element.Type.FIRE, Element.Type.WATER], 7)
	lands.set("_env_left", 0.0)
	body.global_position = at
	lands.call("step", 0.016)
	# The wave's laser comes LASER_LATER of the gap after it (0.134.2).
	lands.call("step", float(lands.get("env_every")) * LandsScript.LASER_LATER + 0.01)
	var lasers: Array = []
	for hz in lands.get("hazards"):
		if str(hz["k"]) == "laser":
			lasers.append(hz)
	var pair: bool = lasers.size() == 2 and lasers[1]["p"] == lasers[0]["p"] \
		and is_equal_approx(float(lasers[1]["ph"]), float(lasers[0]["ph"]) + PI) and lasers[1].has("x_with")
	var flashes: Array = []
	var crossing: Vector2 = lasers[0]["p"] if lasers.size() == 2 else at
	if lasers.size() == 2:
		lasers[0]["e"] = Element.Type.FIRE
		lasers[1]["e"] = Element.Type.WATER
		lasers[1]["x_with"] = Element.Type.FIRE
		for hz in lasers:
			hz["t"] = float(hz["w"])
			hz["landed"] = true
		lands.set("hazards", lasers.duplicate())
		lands.set("_env_left", 999.0)
		body.global_position = far
		lands.call("step", 0.016)
		for hz in lands.get("hazards"):
			if str(hz["k"]) == "burst" and (hz["p"] as Vector2) == crossing:
				flashes.append(int(hz["e"]))
		flashes.sort()
		for hz in lasers:
			hz["t"] = float(hz["life"]) - LandsScript.LASER_TRAIL_BEFORE - 0.001
		lands.call("step", 0.016)
		lands.call("step", LandsScript.LASER_TRAIL_WARN + 0.05)
	var steam_there: bool = false
	for hz in lands.get("hazards"):
		steam_there = steam_there or (str(hz["k"]) == "steam" and (hz["p"] as Vector2).distance_to(crossing) < 20.0)
	var want_flashes: Array = [Element.Type.FIRE, Element.Type.WATER]
	want_flashes.sort()
	check("  an X: two beams through one spot, swaying opposite ways; as they fire it flashes in both lands (%s), and fire over water leaves steam where they cross"
		% [flashes], pair and flashes == want_flashes and steam_there, [lasers.size(), _mix_kinds(lands)])
	# ---- new shapes (0.134.2) ----
	_mix_fresh(lands)
	lands.call("begin_env", [Element.Type.LIGHT], 4)
	lands.set("_env_left", 999.0)
	lands.set("hazards", [])
	body.global_position = at
	var wheel: Array = lands.call("pinwheel", body, at, Element.Type.FIRE)
	var wheel_ok: bool = wheel.size() == LandsScript.PINWHEEL_ARMS
	for arm in wheel:
		wheel_ok = wheel_ok and arm["p"] == at and float(arm["spin"]) == float(wheel[0]["spin"]) and float(arm["spin"]) != 0.0
	var ghosts: int = (lands.call("ghost_lines", wheel[0]) as Array).size()
	lands.set("hazards", [])
	var swept: Dictionary = lands.call("sweep", body, Element.Type.WATER)
	var swept_from: Vector2 = swept["p"]
	swept["t"] = float(swept["w"])
	lands.set("_touch_left", 99.0)
	lands.call("step", 1.0)
	var swept_by: float = (swept["p"] as Vector2).distance_to(swept_from)
	check("  a pinwheel of %d turning beams through one spot (its path ghosted %d times while it warns); a sweep crossing the room (%.0f px in a second)"
		% [wheel.size(), ghosts, swept_by],
		wheel_ok and ghosts == LandsScript.GHOSTS and absf(swept_by - LandsScript.SWEEP_SPEED) < 2.0 and float(swept["bend"]) == 0.0)
	lands.set("hazards", [])
	var bars: Array = lands.call("cage", body, Element.Type.ICE)
	for bar in bars:
		bar["t"] = float(bar["w"])
	lands.set("_touch_left", 99.0)
	for k in 18:
		lands.call("step", 0.1)
	var closest: float = INF
	var farthest: float = 0.0
	for bar in bars:
		var gap: float = body.global_position.distance_to(lands.call("closest_on_beam", bar, body.global_position))
		closest = minf(closest, gap)
		farthest = maxf(farthest, gap)
	check("  a cage of 4 beams closes round you and stops %.0f px short (%.0f to %.0f now)" % [LandsScript.CAGE_STOP, closest, farthest],
		bars.size() == 4 and absf(closest - LandsScript.CAGE_STOP) < 3.0 and absf(farthest - LandsScript.CAGE_STOP) < 3.0)
	lands.set("hazards", [])
	var beat: Dictionary = lands.call("pulse_beam", body, Element.Type.DARK)
	beat["p"] = at
	var beats: Array = []
	for at_t in [0.1, 0.5, 0.75]:
		beat["t"] = float(beat["w"]) + at_t
		beats.append(bool(lands.call("beam_on", beat)))
	var hits_were_pulse: int = (body.get("hits") as Array).size()
	beat["t"] = float(beat["w"]) + LandsScript.PULSE_ON + 0.05
	lands.set("_touch_left", 0.0)
	lands.call("step", 0.016)
	var off_hit: bool = (body.get("hits") as Array).size() > hits_were_pulse
	check("  a pulse beam burns to a beat - on, off, on - and not between beats",
		beats == [true, false, true] and not off_hit)
	_mix_fresh(lands)
	lands.set("hazards", [])
	var pair_x: Array = lands.call("cross_lasers", body, Element.Type.FIRE, Element.Type.ICE)
	for half in pair_x:
		half["p"] = body.global_position
		half["t"] = float(half["w"])
		half["landed"] = true
	var hits_were_x: int = (body.get("hits") as Array).size()
	lands.set("_touch_left", 0.0)
	lands.call("step", 0.016)
	check("  where an X crosses it bursts as it fires: standing on the crossing hurts",
		(body.get("hits") as Array).size() > hits_were_x)
	# ---- a wave comes in turn, and wind pushes harder (0.134.2) ----
	_mix_fresh(lands)
	lands.call("begin_env", [Element.Type.WIND], 4)
	lands.set("_env_left", 0.0)
	lands.set("hazards", [])
	var made_was: int = int(lands.get("env_made"))
	lands.call("step", 0.016)
	var first: int = int(lands.get("env_made")) - made_was
	var waiting: int = (lands.get("_queue") as Array).size()
	lands.call("step", LandsScript.ENV_STAGGER)
	var second: int = int(lands.get("env_made")) - made_was
	check("  a wave of the floor's hazards comes in turn, %.1f s apart (%d, then %d), not all at once" % [LandsScript.ENV_STAGGER, first, second],
		first == 1 and second == 2 and waiting >= LandsScript.env_count(4) - 1)
	const Effects := preload("res://src/characters/statuseffects.gd")
	var pushed := Node2D.new()
	add_child(pushed)
	var fx: Node = Effects.attach(pushed)
	Effects.apply_to(pushed, Effects.SHOVE, 10, pushed.global_position - Vector2(30, 0))
	var plain: float = (fx.get("shove_velocity") as Vector2).length()
	Effects.push_harder(pushed, 2.0)
	check("  push_harder() still makes a shove that many times as hard",
		plain > 0.0 and is_equal_approx((fx.get("shove_velocity") as Vector2).length(), plain * 2.0))
	# ---- wind SLIDES you (0.134.3): "wind is still not sliding a player when hit" ----
	fx.call("clear_all")
	lands.call("_wind_slide", pushed, pushed.global_position - Vector2(30, 0))
	var carried := Vector2.ZERO
	var lasted: float = 0.0
	for i in 200:
		var v: Vector2 = fx.call("push_velocity")
		if v == Vector2.ZERO:
			break
		carried += v * 0.0125
		lasted += 0.0125
		fx.call("_physics_process", 0.0125)
	check("  a wind hit slides you along: %.0f px over %.2f s (a shove is 40 px in 0.2 s)" % [carried.x, lasted],
		carried.x >= 150.0 and absf(carried.y) < 1.0 and lasted >= 0.5 and lasted <= 0.8, [carried, lasted])
	fx.call("clear_all")
	Effects.apply_to(pushed, Effects.SHOVE, 10, pushed.global_position - Vector2(30, 0))
	carried = Vector2.ZERO
	for i in 200:
		var v2: Vector2 = fx.call("push_velocity")
		if v2 == Vector2.ZERO:
			break
		carried += v2 * 0.0125
		fx.call("_physics_process", 0.0125)
	check("  and any other shove is the 40 px it was (%.1f px)" % carried.x, absf(carried.x - 40.0) < 3.0, carried)
	# A gust inside the touch gap cannot hurt you yet - and still blows you.
	fx.call("clear_all")
	lands.set("hazards", [])
	lands.set("_queue", [])
	lands.set("_touch_left", 5.0)
	body.global_position = at
	var gfx: Node = Effects.attach(body)
	gfx.call("clear_all")
	var gust: Dictionary = lands.call("spawn_env", "gust", body)
	gust["p"] = at
	gust["dir"] = 1.0
	gust["w"] = 0.0
	lands.set("hazards", [gust])
	var hurt_was: int = (body.get("hits") as Array).size()
	lands.call("step", 0.016)
	check("  a gust crossing you inside the touch gap: no hurt, and it still slides you along",
		(body.get("hits") as Array).size() == hurt_was and float(gfx.get("shove_left")) > 0.4
		and (gfx.call("push_velocity") as Vector2).x > 0.0, [gfx.get("shove_left"), gfx.call("push_velocity")])
	lands.set("hazards", [])
	lands.set("_touch_left", 0.0)
	gfx.call("clear_all")
	# Stood still to attack (the mage's cast, the tank's, the healer's), a
	# shove still carries you.
	var player_src: String = FileAccess.get_file_as_string("res://src/characters/player.gd")
	var tank_src: String = FileAccess.get_file_as_string("res://src/characters/tank.gd")
	var lock_at: int = player_src.find("if is_attacking and attack_locks_movement:")
	var tank_at: int = tank_src.find("\tif is_attacking:\n")
	check("  stood still for an attack, a shove still carries you (player.gd and tank.gd)",
		lock_at > 0 and player_src.substr(lock_at, 90).contains("move_by_push_only()")
		and tank_at > 0 and tank_src.substr(tank_at, 60).contains("move_by_push_only()"), [lock_at, tank_at])
	pushed.queue_free()
	lands.call("end")
	room.queue_free()
	Boons.clear()
	await get_tree().process_frame
	print("  the lasers bend: done")


func _test_the_crowned_falls_apart() -> void:
	# The Crowned, step 2 (0.134.1): its last three phases, the lying room and
	# the rift (crownedphases.gd, crownedrift.gd). The owner, of the plan:
	# "sounds good".
	section("THE CROWNED, step 2 (0.134.1): the Sealing, the Trap, the Tear, the lying room, the rift")
	const Phases := preload("res://src/world/crowned/crownedphases.gd")
	const LandsScript := preload("res://src/world/descent/descentlands.gd")
	const Boons := preload("res://src/world/descent/descentboons.gd")
	const RunScript := preload("res://src/world/endless/endlessrun.gd")
	const Fight := preload("res://src/world/crowned/crownedfight.gd")
	Boons.clear()
	check("the phases by health: the crowns over three quarters, the Sealing to a half, the Trap to a quarter, then the Tear",
		Phases.phase_for(0.9) == 1 and Phases.phase_for(0.7) == 2 and Phases.phase_for(0.4) == 3 and Phases.phase_for(0.1) == 4)
	var rise: float = Phases.LAVA_RISE * Phases.LAVA_MOST
	check("  the lava rises a ring every %.1f s to %d rings, holds, falls back faster, rests, and again" % [Phases.LAVA_RISE, Phases.LAVA_MOST],
		Phases.lava_depth_at(0.0) == 0 and Phases.lava_depth_at(Phases.LAVA_RISE * 2.0 + 0.1) == 2
		and Phases.lava_depth_at(rise + 1.0) == Phases.LAVA_MOST
		and Phases.lava_depth_at(rise + Phases.LAVA_HOLD + Phases.LAVA_FALL * 0.5) == Phases.LAVA_MOST - 1
		and Phases.lava_depth_at(rise + Phases.LAVA_HOLD + Phases.LAVA_FALL * Phases.LAVA_MOST + 0.5) == 0)
	# ---- the room ------------------------------------------------------------------
	var room: Node2D = (load("res://scene/boss.tscn") as PackedScene).instantiate() as Node2D
	room.set_script(null)
	room.get_node("hudcontrol").free()
	room.get_node("enemyrespawner").free()
	var boss: Node2D = room.get_node("ysortworld/enemies/bossenemy") as Node2D
	boss.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	await get_tree().process_frame
	var fight: Node2D = room.get_node("crownedfight") as Node2D
	var phases: Node2D = fight.get("phases")
	var lands: Node2D = fight.get("lands")
	var ground: TileMapLayer = room.get_node("ground") as TileMapLayer
	var floor_rect: Rect2 = fight.get("room_rect")
	var body_script := GDScript.new()
	body_script.source_code = "extends Node2D\nvar hp: int = 400\nvar max_hp: int = 400\nvar hits: Array = []\nfunc take_damage(amount: int, element: int = 0) -> void:\n\thits.append([amount, element])\n"
	body_script.reload()
	var body: Node2D = Node2D.new()
	body.set_script(body_script)
	body.position = floor_rect.get_center() + Vector2(0, 150)
	room.add_child(body)
	body.reset_physics_interpolation()
	fight.set("player_override", body)
	fight.set("boss", boss)
	var cells_whole: int = ground.get_used_cells().size()
	# ---- the rift --------------------------------------------------------------------
	var rift: Node2D = fight.get("rift")
	var layer: CanvasLayer = rift.get_parent() as CanvasLayer if rift != null else null
	var clipped: int = 0
	for glimpse in (rift.get("glimpses") as Array if rift != null else []):
		var holder: Polygon2D = glimpse[0]
		if holder.clip_children == CanvasItem.CLIP_CHILDREN_ONLY and holder.get_child_count() > 0 \
				and not floor_rect.grow(40.0).has_point(holder.position):
			clipped += 1
	check("the rift: behind the whole world (layer -1, with the camera), out of the room's darkness, %d glimpses of the heroes' worlds past the walls" % clipped,
		layer != null and layer.layer == -1 and layer.follow_viewport_enabled and clipped == 4)
	var zip: Dictionary = rift.call("make_zip")
	var zip_along: PackedFloat32Array = zip["along"]
	var zips_were: int = int(rift.get("zips_made"))
	rift.set("_zip_left", 0.0)
	rift.call("_step_zips", 0.016)
	check("  the realm breaking: cracks race across the void (%.0f px, forking %d ways), one after another" % [zip_along[zip_along.size() - 1], (zip["forks"] as Array).size()],
		zip_along[zip_along.size() - 1] >= 700.0 and (zip["forks"] as Array).size() >= 2 and int(rift.get("zips_made")) == zips_were + 1
		and not (rift.get("zips") as Array).is_empty())
	# ---- the Sealing -------------------------------------------------------------------
	phases.call("step", 0.016, 0.7)
	check("  under three quarters: the Sealing - the boss in fire, a share of the warnings illusions, the realm cracking faster",
		int(phases.get("phase")) == 2 and int(boss.get("crown_land")) == Element.Type.FIRE and float(rift.get("intensity")) > 1.0
		and is_equal_approx(float(lands.get("false_share")), Phases.LIE_SHARE))
	lands.set("false_share", 0.0)
	lands.set("hazards", [])
	phases.set("_meteor_left", 0.0)
	phases.call("step", 0.016, 0.7)
	var meteors: int = 0
	for hz in lands.get("hazards"):
		if str(hz["k"]) == "meteor" and (hz["p"] as Vector2).distance_to(body.global_position) < 60.0:
			meteors += 1
	var meteor: Dictionary = lands.call("spawn_env", "meteor", body)
	meteor["p"] = body.global_position
	meteor["t"] = float(meteor["w"])
	lands.set("_touch_left", 0.0)
	lands.call("step", 0.016)
	var struck: Array = (body.get("hits") as Array).back() if not (body.get("hits") as Array).is_empty() else []
	var scorched: bool = false
	for hz in lands.get("hazards"):
		scorched = scorched or (str(hz["k"]) == "scorch" and (hz["p"] as Vector2) == body.global_position)
	check("  meteors fall where you stand (%d near you) and strike as fire, leaving a scorch: %s" % [meteors, str(struck)],
		meteors >= 1 and struck == [LandsScript.env_amount(4, 400, LandsScript.METEOR_TIMES), Element.Type.FIRE] and scorched)
	lands.set("hazards", [])
	lands.set("false_share", 1.0)
	var hits_were: int = (body.get("hits") as Array).size()
	var illusions_were: int = int((lands.get("reactions") as Dictionary).get("illusion", 0))
	var lie: Dictionary = lands.call("spawn_env", "hail", body)
	lie["p"] = body.global_position
	lie["t"] = float(lie["w"])
	lands.set("_touch_left", 0.0)
	lands.call("step", 0.016)
	check("  a false warning (its circle shimmers) lands on you and does nothing but break",
		bool(lie.get("fake", false)) and (body.get("hits") as Array).size() == hits_were
		and int((lands.get("reactions") as Dictionary).get("illusion", 0)) == illusions_were + 1 and not bool(lie.get("just", false)))
	lands.set("false_share", Phases.LIE_SHARE)
	lands.set("hazards", [])
	phases.set("_meteor_left", 99.0)
	phases.set("phase_clock", Phases.LAVA_RISE * 3.0 + 0.05)
	body.global_position = Vector2(floor_rect.position.x + 20.0, floor_rect.get_center().y)
	lands.set("_touch_left", 0.0)
	phases.call("step", 0.016, 0.7)
	var taken_floor: int = cells_whole - ground.get_used_cells().size()
	var lava_cells: int = (phases.get("lava") as TileMapLayer).get_used_cells().size()
	var burned: Array = (body.get("hits") as Array).back()
	var volcano: Array = []
	for glimpse in rift.get("glimpses"):
		if str(glimpse[3]) == "volcano":
			volcano = glimpse
	rift.call("_process", 10.0)
	var shows_while_flooding: bool = float(rift.get("flood")) > 0.0 and (volcano[0] as Node2D).modulate.a > 0.0 \
		and (volcano[0] as Node2D).position.distance_to(floor_rect.get_center()) < (volcano[4] as Vector2).distance_to(floor_rect.get_center())
	check("  the volcano's windows in the rift come in toward the walls only while the lava floods",
		shows_while_flooding)
	phases.call("set_lava_depth", Phases.LAVA_MOST)
	var dry: Rect2 = phases.call("dry_rect", Phases.LAVA_MOST)
	check("  at its height the lava boxes you in: a %.0f x %.0f px square of floor round the middle, nothing else dry"
		% [dry.size.x, dry.size.y],
		absf(dry.size.x - dry.size.y) < 1.0 and is_equal_approx(dry.size.x, float(Phases.BOX_CELLS * Phases.LAVA_TILE))
		and dry.has_point(floor_rect.get_center() + Vector2(0, 20)) and not bool(phases.call("in_lava", dry.get_center()))
		and bool(phases.call("in_lava", dry.position + Vector2(-20, dry.size.y / 2.0)))
		and bool(phases.call("in_lava", dry.position + Vector2(dry.size.x / 2.0, -20))))
	phases.call("set_lava_depth", 3)
	check("  the lava takes the floor ring by ring from the walls (3 rings: %d lava cells, %d floor cells gone) and burns whoever stands in it"
		% [lava_cells, taken_floor],
		int(phases.get("lava_depth")) == 3 and taken_floor == lava_cells * 4 and lava_cells > 100
		and bool(phases.call("in_lava", body.global_position + Vector2(0, 10)))
		and not bool(phases.call("in_lava", floor_rect.get_center())) and int(burned[1]) == Element.Type.FIRE)
	# ---- the Trap --------------------------------------------------------------------
	body.global_position = floor_rect.get_center() + Vector2(0, 150)
	phases.call("step", 0.016, 0.4)
	var floor_back: bool = ground.get_used_cells().size() == cells_whole
	rift.call("_process", 10.0)
	floor_back = floor_back and float(rift.get("flood")) == 0.0 and (volcano[0] as Node2D).modulate.a == 0.0
	for k in 20:
		phases.call("step", 0.1, 0.4)
	var horde: Node2D = phases.get("swarm")
	var alive: int = int(horde.get("alive")) if horde != null else 0
	RunScript.pretend_phone = true
	var on_phone: int = phases.call("horde_size")
	RunScript.pretend_phone = false
	lands.set("hazards", [])
	phases.set("_laser_left", 0.0)
	phases.set("lasers_cast", 0)
	phases.call("step", 0.016, 0.4)
	var beams: Array = []
	for hz in lands.get("hazards"):
		if str(hz["k"]) == "laser":
			beams.append(hz)
	check("  under a half: the Trap - the floor whole again, a horde from the Endless filling (%d of %d; %d on a phone) and an X of lasers"
		% [alive, Phases.HORDE_CROWD, on_phone],
		int(phases.get("phase")) == 3 and floor_back and horde != null and horde.get_parent() == room.get_node("ysortworld/groundeffects")
		and alive > 50 and alive <= Phases.HORDE_CROWD and on_phone == Phases.HORDE_PHONE
		and beams.size() == 2 and (beams[1] as Dictionary).has("x_with") and beams[1]["p"] == beams[0]["p"])
	# ---- the Tear --------------------------------------------------------------------
	lands.set("hazards", [])
	phases.call("step", 0.016, 0.2)
	var horde_gone: bool = phases.get("swarm") == null
	phases.set("_tear_left", 0.0)
	var feet: Vector2 = body.global_position + Vector2(0, 10)
	phases.call("step", 0.016, 0.2)
	var tears: Dictionary = phases.get("tears")
	var under: Vector2i = phases.call("piece_at", feet)
	var lo := Vector2i(999, 999)
	var hi := Vector2i(-999, -999)
	for piece in tears.keys():
		lo = Vector2i(mini(lo.x, piece.x), mini(lo.y, piece.y))
		hi = Vector2i(maxi(hi.x, piece.x), maxi(hi.y, piece.y))
	var spread: int = maxi(hi.x - lo.x, hi.y - lo.y)
	check("  under a quarter: the Tear - the horde gone, a pattern of %d pieces cracking across the map (%d apart at the most), one under you"
		% [tears.size(), spread],
		int(phases.get("phase")) == 4 and horde_gone and tears.size() >= 4 and spread >= 3 and tears.has(under)
		and ground.get_used_cells().size() == cells_whole)
	var shapes_ok: bool = true
	for shape in Phases.PATTERNS:
		phases.call("knit_all")
		shapes_ok = shapes_ok and int(phases.call("cut_pattern", shape)) >= 3
	phases.call("knit_all")
	phases.call("cut", under)
	phases.call("cut_pattern", "row")
	check("  each pattern cuts across the floor: a row, a column, a ring, a scatter", shapes_ok)
	var land_was: int = int(boss.get("crown_land"))
	phases.set("_flicker_left", 0.0)
	lands.set("_touch_left", 0.0)
	phases.call("step", Phases.TEAR_WARN + 0.05, 0.2)
	var torn_now: int = (phases.get("tears") as Dictionary).size()
	var holes: int = cells_whole - ground.get_used_cells().size()
	var fell: Array = (body.get("hits") as Array).back()
	check("  they fall into the rift (%d floor cells open); you fall through, are hurt as dark, and climb out on solid floor; it flickers to another land"
		% holes,
		holes == torn_now * (Phases.TEAR_PER * Phases.FLOOR_PER) * (Phases.TEAR_PER * Phases.FLOOR_PER) and int(phases.get("falls")) == 1 and int(fell[1]) == Element.Type.DARK
		and not bool(phases.call("fell_in", body.global_position + Vector2(0, 10)))
		and floor_rect.has_point(body.global_position) and int(boss.get("crown_land")) != land_was)
	# ---- the lying room ------------------------------------------------------------------
	var lies_were: int = int(phases.get("lies"))
	for k in 6:
		phases.set("_lie_left", 0.0)
		phases.call("_step_lies", 0.016)
	fight.call("flash_wash", Element.Type.WATER)
	var wash: ColorRect = fight.get("_wash")
	check("  the room lies: %d walls to shimmer, a lie every few seconds, the floor washed in the wrong land a moment" % (phases.call("_walls") as Array).size(),
		(phases.call("_walls") as Array).size() == 59 and int(phases.get("lies")) == lies_were + 6
		and wash.color.a > Fight.WASH * 1.5)
	# ---- the eyes shuffle -------------------------------------------------------------------
	lands.set("hazards", [])
	var eyes: Array = fight.call("make_decoys", 3)
	var before: Array = [boss.global_position]
	for eye in eyes:
		before.append((eye as Node2D).global_position)
	fight.call("shuffle")
	var after: Array = [boss.global_position]
	for eye in eyes:
		after.append((eye as Node2D).global_position)
	var same_spots: bool = true
	for at in before:
		var found: bool = false
		for q in after:
			found = found or (q as Vector2).distance_to(at) < 0.5
		same_spots = same_spots and found
	var flashes: int = 0
	for hz in lands.get("hazards"):
		if str(hz["k"]) == "burst":
			flashes += 1
	check("  the eyes shuffle: all %d blink out in a flash of dark and come back in each other's places, the Crowned among them"
		% flashes, eyes.size() == 3 and same_spots and after != before and flashes == 4 and int(fight.get("shuffles")) >= 1)
	for eye in eyes:
		(eye as Node).call("shatter")
	# ---- the end -------------------------------------------------------------------------
	phases.call("end")
	check("  when the fight ends the room is put back: the floor whole, no lava, no tears, no horde, no illusions",
		ground.get_used_cells().size() == cells_whole and (phases.get("tears") as Dictionary).is_empty()
		and int(phases.get("lava_depth")) == 0 and phases.get("swarm") == null
		and float(lands.get("false_share")) == 0.0 and int(phases.get("phase")) == 0)
	room.queue_free()
	Boons.clear()
	await get_tree().process_frame
	print("  the Crowned falls apart: done")


func _test_the_readout_finds_its_spikes() -> void:
	# The owner's screenshot after a fight (0.134.3): process worst 241 ms,
	# physics worst 22.5, frame worst 31.25 - and nothing to say whether that
	# was the fight or the walk into the area (perfoverlay.gd LOADS ARE NOT
	# HITCHES, AND A HITCH SAYS WHERE IT WAS).
	section("The readout tells a load from a spike, and says where each spike was (0.134.3)")
	var shown_before: bool = PerfOverlay.is_shown()
	PerfOverlay.set_shown(false)
	PerfOverlay.set_shown(true)
	var now: int = Time.get_ticks_msec()
	var plain := {"ms": 10.0, "held": false, "fps": 100.0, "process": 3.0, "physics": 0.5,
		"ticks": 1, "nodes": 0, "area": "field", "at": now}
	for i in 6:
		PerfOverlay.push_sample(plain.duplicate())
	var hitch := plain.duplicate()
	hitch["ms"] = 40.0
	PerfOverlay.push_sample(hitch)
	check("a frame is held back %d frames before it counts, so a load found late still takes it" % PerfOverlay.LOAD_BEFORE,
		PerfOverlay._hitches == 0 and PerfOverlay._pending.size() == PerfOverlay.LOAD_BEFORE, PerfOverlay._pending.size())
	# A load: a 241 ms frame, then the scene changes.
	var heavy := plain.duplicate()
	heavy["ms"] = 241.0
	heavy["process"] = 230.0
	heavy["area"] = "descent"
	PerfOverlay.push_sample(heavy)
	PerfOverlay.mark_load()
	for i in PerfOverlay.LOAD_AFTER:
		var arrived := plain.duplicate()
		arrived["area"] = "descent"
		PerfOverlay.push_sample(arrived)
	# A spike in the fight: two physics ticks, forty nodes made.
	var spike := plain.duplicate()
	spike["ms"] = 48.0
	spike["physics"] = 22.5
	spike["ticks"] = 2
	spike["process"] = 2.0
	spike["nodes"] = 40
	spike["at"] = now - 12000
	PerfOverlay.push_sample(spike)
	var scripts := plain.duplicate()
	scripts["ms"] = 60.0
	scripts["process"] = 50.0
	PerfOverlay.push_sample(scripts)
	var outside := plain.duplicate()
	outside["ms"] = 90.0
	outside["nodes"] = -300
	PerfOverlay.push_sample(outside)
	PerfOverlay.flush_samples()
	check("a 241 ms frame as the scene changed is a load: counted once, into the area it loaded",
		PerfOverlay._loads == 1 and is_equal_approx(PerfOverlay._last_load_ms, 241.0)
		and PerfOverlay.loads_text().contains("241 ms") and PerfOverlay.loads_text().contains(AreaRegistry.display_name("descent")),
		PerfOverlay.loads_text())
	check("  and in no worst and no hitch - the 40 ms frame it swallowed with it neither",
		PerfOverlay._worst_process_ms < 100.0 and PerfOverlay._worst_frame_ms < 100.0 and PerfOverlay._hitches == 3,
		[PerfOverlay._worst_process_ms, PerfOverlay._worst_frame_ms, PerfOverlay._hitches])
	check("the frame row's worst is the longest real frame (90 ms), not the worst fps turned back into ms",
		is_equal_approx(PerfOverlay._worst_frame_ms, 90.0), PerfOverlay._worst_frame_ms)
	var said: String = PerfOverlay.spike_text(PerfOverlay._spikes[2], now)
	check("a spike says how long, when, where, that physics took it, and what was made: \"%s\"" % said,
		said.begins_with("48 ms") and said.contains("12 s ago") and said.contains(" in " + AreaRegistry.display_name("field"))
		and said.contains("physics, 2 ticks, the last 22.5 ms") and said.contains("+40 nodes"), said)
	said = PerfOverlay.spike_text(PerfOverlay._spikes[1], now)
	check("  scripts and drawing when they took it: \"%s\"" % said, said.contains("scripts + drawing 50.0 ms"), said)
	said = PerfOverlay.spike_text(PerfOverlay._spikes[0], now)
	check("  and neither, newest first: \"%s\"" % said,
		said.begins_with("90 ms") and said.contains("outside the scripts") and said.contains("-300 nodes"), said)
	PerfOverlay._accum = PerfOverlay.SAMPLE_INTERVAL
	await get_tree().process_frame
	await get_tree().process_frame
	var text: String = PerfOverlay.readout()
	check("drawn: the loads row, the spikes rows, the frame's real worst",
		text.contains("loads") and text.contains("spikes") and text.contains("(worst 90.00)") and text.contains("48 ms   12 s ago"), text)
	check("every label has a space after it - \"after you\" ran into its value (\"after younobody\")",
		PerfOverlay._row("after you", "nobody") == "after you nobody" and "after you".length() < PerfOverlay.LABEL_WIDTH)
	check("memory never reads 0.0 MB: Godot counts it in a debug build only, so an exported game says so",
		not PerfOverlay.memory_text().contains("0.0 MB") and PerfOverlay.memory_text() != "", PerfOverlay.memory_text())
	PerfOverlay.set_shown(false)
	PerfOverlay.set_shown(shown_before)
	print("  the readout finds its spikes: done")
