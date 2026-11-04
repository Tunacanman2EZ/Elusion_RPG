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
	WorldMap.reveal_around(stone_chasm["at"] + Vector2(60, 60), "bigfield")
	var bright: Dictionary = chasm.call("map_landmark")
	check("  walking past it lights it, at once: the portal plays, its name shows, a cyan pin",
		chasm.call("lit") and bool(bright.get("lit")) and bright.get("colour") == Ways.LIT_COLOUR
		and (chasm.get_node("art") as AnimatedSprite2D).is_playing()
		and (chasm.get_node("label") as Label).text == "Waystone - The Chasm", bright)
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
	map.call("refresh", "endless")
	check("  and hidden in a minigame", row != null and not row.visible)
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
var taken: Array = []
func take_damage(amount: int, element: int) -> void:
	taken.append([amount, element])
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
	var tank_spared: bool = (body.get("taken") as Array).size() == 1 and float(run.call("redness")) > 0.4 \
		and sprite.modulate != Color.WHITE
	check("in the lava a warrior catches fire (%s a tick, flames on them); the tank does not - his gear turns red" % [hits],
		burnt and tank_spared)
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
	# The volcano: everyone burns, the tank too, harder each tick.
	body.global_position = c + Vector2(0, 30)
	run.set("floods", Run.SLICES)
	var before: int = (body.get("taken") as Array).size()
	run.call("_process", Run.BURN_TICK + 0.01)
	run.call("_process", Run.BURN_TICK + 0.01)
	var late: Array = (body.get("taken") as Array).slice(before)
	check("once every slice is gone the volcano burns everyone, the tank too, harder each tick %s" % [late],
		bool(run.call("volcano")) and late.size() == 2 and int(late[1][0]) > int(late[0][0]))
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
	card.set("travel", func(area_id: String, spawn_id: String) -> void: went.append([area_id, spawn_id]))
	card.set("area_now", func() -> String: return "elusion")
	card.set("shows_forge", func() -> bool: return false)
	card.call("paint")
	var hidden: bool = not card.forge_box.visible
	card.set("shows_forge", func() -> bool: return true)
	card.set("class_now", func() -> String: return "mage")
	card.call("open")
	card.call("paint")
	var shown: bool = card.forge_box.visible and card.forge_go.text == "Go" and not card.forge_go.disabled
	card.call("_on_forge_go")
	card.set("area_now", func() -> String: return "forge")
	card.call("paint")
	var leave_text: String = card.forge_go.text
	card.call("_on_forge_go")
	check("on the Minigames card for the owner alone, any class: Go goes down (%s), and inside it is Leave, to town" % str(went),
		hidden and shown and leave_text == "Leave" and went.size() == 2 and went[0] == ["forge", "forge_entrance"]
		and went[1] == ["elusion", ""])
	card_hud.queue_free()
	await get_tree().process_frame
	print("  (the forge: done)")
