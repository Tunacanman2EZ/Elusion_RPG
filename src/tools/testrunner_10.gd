# testrunner_10.gd - part 10 of the suite (testrunner.gd says how it is
# split; part 9 passed 250 KB): _test_the_double_axe_in_the_descent and
# _test_the_descent_reroll.
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
