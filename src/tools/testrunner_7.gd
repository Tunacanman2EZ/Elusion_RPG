# testrunner_7.gd - part 7 of the suite (testrunner.gd says how it is
# split): 40 tests, _test_the_export_reads_a_mages_leash_in_the_editor to _test_character_select_has_a_way_out.
extends "res://src/tools/testrunner_6.gd"


# =============================================================================
# THE EXPORT READS A MAGE'S LEASH IN THE EDITOR TOO (0.69.2)
# =============================================================================
# The exporter runs in the editor, on placeholders that never ran _init() - and
# the bush mage's 1,500 leash is set in _init(), so an export from the editor
# wrote the field mages' leash as the base 400, and one run in the game 1,500.
# The server reads that number. BaseEnemy.authored_leash() asks the class.
func _test_the_export_reads_a_mages_leash_in_the_editor() -> void:
	section("THE EXPORT - a bush mage's leash is its class's, wherever the export runs (0.69.2)")
	var mage := CharacterBody2D.new()
	mage.set_script(load("res://src/enemies/bushmage.gd"))
	check("a bush mage chases from its class's CHASE_LEASH, 1,500",
		is_equal_approx(float(mage.get("leash_range")), 1500.0) and is_equal_approx(BushMage.CHASE_LEASH, 1500.0))
	mage.set("leash_range", 400.0)        # what the editor's placeholder reads
	check("  read as the editor reads it, the export still says 1,500",
		is_equal_approx(BaseEnemy.authored_leash(mage), BushMage.CHASE_LEASH), BaseEnemy.authored_leash(mage))
	mage.set("leash_range", 250.0)        # the Big Field's own mages
	check("  and a placement that chose its own keeps it", is_equal_approx(BaseEnemy.authored_leash(mage), 250.0))
	mage.free()
	var sprite: Node = (load("res://scene/enemy/firesprite.tscn") as PackedScene).instantiate()
	check("a monster with no CHASE_LEASH is what it says", is_equal_approx(BaseEnemy.authored_leash(sprite),
		float(sprite.get("leash_range"))))
	sprite.free()
	check("  and the exporter asks authored_leash()",
		_code_src("res://src/tools/exportgamedata.gd").contains("\"leash\": BaseEnemy.authored_leash(child)"))
	var field_mages: Array = []
	var areas: Variant = _load_gamedata().get("areas", {})
	if areas is Dictionary and (areas as Dictionary).has("field"):
		for spawn in (areas["field"] as Dictionary).get("spawns", []):
			if str(spawn.get("e", "")).ends_with("bushmage"):
				field_mages.append(float(spawn.get("leash", 0.0)))
	check("the Field's mages are exported at 1,500 (re-run the exporter if not)",
		not field_mages.is_empty() and field_mages.all(func(l: float) -> bool: return is_equal_approx(l, 1500.0)),
		field_mages)


# =============================================================================
# ATTACKS STOP AT WALLS (0.69.1)
# =============================================================================
# The owner, in the Big Field: "players can attack enemies through doors/
# walls", and "i saw a projectile floating in the black". Every way a player
# hurts a monster found it by overlap or by distance, with nothing asking
# whether a wall stood between - and a warrior pressed against one of the Big
# Field's 2 px north walls has its origin already past it, so a Double Axe
# thrown from there flew out over the black and spun. Built here in an arena:
# a 16 px wall (a crypt door's depth), a 2 px one (a Big Field north wall),
# boss-gate bars on layer 2, and every class's attack on each side.

func _test_attacks_stop_at_walls() -> void:
	section("WALLS - a player's attack stops at a wall, a closed door or a boss gate (0.69.1)")
	const Targets := preload("res://src/shared/targets.gd")
	var arena := Node2D.new()
	add_child(arena)
	var base := Vector2(-90000.0, 60000.0)
	var door_x: float = base.x
	var thin_x: float = base.x + 3000.0
	_attack_wall(arena, base, Vector2(600, 16), 1)                           # a crypt door: y -8..8
	_attack_wall(arena, Vector2(thin_x + 1000.0, base.y), Vector2(4000, 2), 1)  # a Big Field north wall: y -1..1
	_attack_wall(arena, base + Vector2(8000, 0), Vector2(600, 16), 2)           # boss-gate bars
	var sensor := Area2D.new()                                               # a trigger, not a wall
	sensor.collision_layer = 1
	var sensor_shape := CollisionShape2D.new()
	var sensor_rect := RectangleShape2D.new()
	sensor_rect.size = Vector2(600, 16)
	sensor_shape.shape = sensor_rect
	sensor.add_child(sensor_shape)
	arena.add_child(sensor)
	sensor.global_position = base + Vector2(11000, 0)
	for i in 3:
		await get_tree().physics_frame

	# ---- the rule ---------------------------------------------------------------
	var up := Vector2(0, -30)
	var down := Vector2(0, 30)
	check("a wall between two points blocks the line", not Targets.clear_between(arena, base + up, base + down))
	check("  so does a 2 px one", not Targets.clear_between(arena, Vector2(thin_x, base.y) + up, Vector2(thin_x, base.y) + down))
	check("  and a boss gate's bars, on layer 2",
		not Targets.clear_between(arena, base + Vector2(8000, 0) + up, base + Vector2(8000, 0) + down))
	check("  open ground does not, nor an Area2D on the walls' layer",
		Targets.clear_between(arena, base + Vector2(1500, 0) + up, base + Vector2(1500, 0) + down)
		and Targets.clear_between(arena, base + Vector2(11000, 0) + up, base + Vector2(11000, 0) + down))
	var short: Vector2 = Targets.short_of_wall(arena, base + Vector2(0, 40), base + Vector2(0, -60))
	check("short_of_wall() stops this side of the wall, a little short of it",
		short.y > base.y + 8.0 and short.y <= base.y + 8.0 + Targets.WALL_MARGIN + 0.01 and is_equal_approx(short.x, base.x), short)
	check("  and leaves a clear aim where it was",
		Targets.short_of_wall(arena, base + Vector2(1500, 40), base + Vector2(1500, -60)) == base + Vector2(1500, -60))

	# ---- the warrior: the swing, the wave, the fan and the axe ------------------
	var warrior: Node2D = _hero_against(arena, "warrior", base.y + 8.0, door_x)
	check("the case is real: a warrior pressed against the door has its origin inside it",
		warrior.global_position.y < base.y + 8.0 and warrior.global_position.y > base.y - 8.0, warrior.global_position)
	var past: CharacterBody2D = _weapon_dummy(arena, Vector2(door_x, base.y - 16.0))
	var here: CharacterBody2D = _weapon_dummy(arena, Vector2(door_x + 12.0, base.y + 30.0))
	await get_tree().physics_frame
	check("the sword does not cut a monster on the far side of the door",
		warrior.call("_try_damage", past) == 0 and past.get("taken").is_empty(), past.get("taken"))
	check("  and cuts one on this side", warrior.call("_try_damage", here) == 1 and not here.get("taken").is_empty())
	warrior.set("mana", 500)
	warrior.set("_swing_aim_direction", Vector2.UP)
	warrior.call("_spawn_slashwave")
	check("a wave swung into the door is not thrown from its far side, and costs nothing",
		int(warrior.get("mana")) == 500, warrior.get("mana"))
	check("  nor the sword fan", (warrior.call("fling_sword_fan", arena) as Array).is_empty())
	warrior.set("_swing_aim_direction", Vector2.DOWN)
	warrior.call("_spawn_slashwave")
	check("  swung away from it, the wave goes as ever", int(warrior.get("mana")) < 500, warrior.get("mana"))
	var fan: Array = warrior.call("fling_sword_fan", arena)
	check("  and the fan", not fan.is_empty())
	for orb in fan:
		(orb as Node).queue_free()

	var wave: SlashWave = (load("res://scene/projectiles/slashwave.tscn") as PackedScene).instantiate()
	arena.add_child(wave)
	wave.global_position = Vector2(door_x, base.y + 20.0)
	wave.damage = 10
	wave.shoot_vector(Vector2.UP)
	var near_past: CharacterBody2D = _weapon_dummy(arena, Vector2(door_x - 40.0, base.y - 12.0))
	var near_here: CharacterBody2D = _weapon_dummy(arena, Vector2(door_x - 40.0, base.y + 40.0))
	wave._try_hit(near_past)
	wave._try_hit(near_here)
	check("a wave at the door cuts the monster this side and not the one past it",
		near_past.get("taken").is_empty() and not near_here.get("taken").is_empty(),
		[near_past.get("taken"), near_here.get("taken")])
	check("  and a wave that never meets a wall or the screen is gone after a while",
		SlashWave.MAX_SECONDS > 0.0 and SlashWave.MAX_SECONDS * wave.speed < 1500.0, SlashWave.MAX_SECONDS)
	wave.queue_free()
	var orb_up: BladeOrb = BladeOrb.fire(arena, Vector2(door_x - 80.0, base.y + 20.0), Vector2.UP, 100.0, 80.0, 10, BladeOrb.STEEL)
	var orb_past: CharacterBody2D = _weapon_dummy(arena, Vector2(door_x - 80.0, base.y - 12.0))
	orb_up._try_hit(orb_past)
	check("a blade orb at the door breaks there, and the monster past it is not cut",
		orb_past.get("taken").is_empty() and orb_up._done, orb_past.get("taken"))

	var axe: SpinningAxe = (load("res://scene/projectiles/spinningaxe.tscn") as PackedScene).instantiate()
	axe.caster = warrior
	axe.wounds = false
	arena.add_child(axe)
	axe.global_position = Vector2(door_x + 60.0, base.y + 14.0)
	var axe_past: CharacterBody2D = _weapon_dummy(arena, Vector2(door_x + 60.0, base.y - 14.0))
	var axe_here: CharacterBody2D = _weapon_dummy(arena, Vector2(door_x + 70.0, base.y + 30.0))
	check("a spinning axe at the door does not cut through it",
		not axe._cut(axe_past, 10, 10) and axe_past.get("taken").is_empty())
	check("  and cuts what is this side", axe._cut(axe_here, 10, 10))
	axe.queue_free()
	var thrown: SpinningAxe = warrior.call("throw_axe", Vector2(door_x, base.y - 160.0))
	for i in 30:
		if thrown == null or not is_instance_valid(thrown):
			break
		thrown.advance(1.0 / 30.0)
	check("thrown at the door from inside it, the axe stops this side and spins there - not out past it",
		thrown != null and is_instance_valid(thrown) and thrown.state == SpinningAxe.State.SPINNING
		and thrown.global_position.y > base.y + 8.0,
		str(thrown.global_position) if thrown != null and is_instance_valid(thrown) else "no axe")
	if thrown != null and is_instance_valid(thrown):
		thrown.queue_free()
	warrior.set("_axe", null)
	warrior.queue_free()

	# ---- the mage: the spike, the meteor and its fire --------------------------
	var mage: Node2D = _hero_against(arena, "mage", base.y + 1.0, thin_x)
	var aimed: Vector2 = mage.call("reach_short_of_wall", Vector2(thin_x, base.y - 120.0))
	check("a spell aimed past a wall comes down this side of it", aimed.y > base.y + 1.0, aimed)
	var spike_past: CharacterBody2D = _weapon_dummy(arena, Vector2(thin_x, base.y - 8.0))
	var spike_here: CharacterBody2D = _weapon_dummy(arena, Vector2(thin_x + 8.0, base.y + 12.0))
	var spell: Area2D = (mage.get("target_circle_scene") as PackedScene).instantiate()
	spell.set("explosion_damage", 10)
	arena.add_child(spell)
	spell.global_position = Vector2(thin_x, base.y + 6.0)
	var meteor: Meteor = (load("res://scene/projectiles/meteor.tscn") as PackedScene).instantiate()
	meteor.explosion_damage = 10
	arena.add_child(meteor)
	meteor.global_position = Vector2(thin_x, base.y + 6.0)
	var crater: BurningCrater = BurningCrater.spawn(arena, Vector2(thin_x, base.y + 6.0), 100, 44.0, null)
	for i in 3:
		await get_tree().physics_frame
	check("the case is real: the spike's circle reaches the monster past the 2 px wall",
		spell.get_overlapping_bodies().has(spike_past))
	spell.call("_apply_area_damage")
	check("  and its impact hurts the one this side only",
		spike_past.get("taken").is_empty() and not spike_here.get("taken").is_empty(),
		[spike_past.get("taken"), spike_here.get("taken")])
	spike_here.get("taken").clear()
	check("the meteor's reaches past it too", meteor.get_overlapping_bodies().has(spike_past))
	meteor._apply_damage()
	check("  and hits only this side", spike_past.get("taken").is_empty() and not spike_here.get("taken").is_empty())
	spike_here.get("taken").clear()
	crater._burn()
	check("its crater burns only this side", spike_past.get("taken").is_empty() and not spike_here.get("taken").is_empty(),
		[spike_past.get("taken"), spike_here.get("taken")])
	spike_here.get("taken").clear()
	spell.queue_free()
	meteor.queue_free()
	crater.queue_free()

	# ---- auto-aim on a touch screen: the nearest monster it can see -------------
	# The nearer one, past the wall: placed to be passed over.
	var _aim_past: CharacterBody2D = _weapon_dummy(arena, Vector2(thin_x + 200.0, base.y - 6.0))
	var aim_here: CharacterBody2D = _weapon_dummy(arena, Vector2(thin_x + 200.0, base.y + 60.0))
	var looker: Node2D = _hero_against(arena, "mage", base.y + 1.0, thin_x + 200.0)
	const Touch := preload("res://src/systems/touchcontrols.gd")
	var aimed_at: Node2D = Touch.nearest_monster(get_tree(), looker.global_position, 260.0, looker)
	check("touch auto-aim takes the nearest monster it can see, not one nearer behind a wall",
		aimed_at == aim_here, aimed_at)
	looker.queue_free()
	mage.queue_free()

	# ---- the tank: the ring and the dynamite ------------------------------------
	var tank: Node2D = _hero_against(arena, "tank", base.y + 1.0, thin_x + 600.0)
	var ring_past: CharacterBody2D = _weapon_dummy(arena, Vector2(thin_x + 600.0, base.y - 6.0))
	var ring_here: CharacterBody2D = _weapon_dummy(arena, tank.global_position + Vector2(20.0, 0.0))
	for i in 3:
		await get_tree().physics_frame
	var ring: Area2D = tank.get("_aura")
	check("the case is real: the tank's ring reaches past the wall", ring != null and ring.get_overlapping_bodies().has(ring_past))
	tank.call("_deal_aura_damage")
	check("  and burns only this side", ring_past.get("taken").is_empty() and not ring_here.get("taken").is_empty(),
		[ring_past.get("taken"), ring_here.get("taken")])
	# THE RING READS HURTBOXES TOO (0.93.1): the Endless's swarm is hurtboxes
	# alone (swarmproxy.gd) - the owner: "tanks aura is doing no damage to
	# these mobs" - and a monster with a body AND a hurtbox burns once a tick.
	var both_box := Area2D.new()
	both_box.collision_layer = 8
	both_box.collision_mask = 0
	both_box.monitoring = false
	var both_shape := CollisionShape2D.new()
	var both_circle := CircleShape2D.new()
	both_circle.radius = 6.0
	both_shape.shape = both_circle
	both_box.add_child(both_shape)
	ring_here.add_child(both_box)
	var ring_swarm: Node2D = (load("res://src/world/endless/swarm.gd") as GDScript).new()
	ring_swarm.set("arena", Rect2(tank.global_position - Vector2(400, 400), Vector2(800, 800)))
	arena.add_child(ring_swarm)
	ring_swarm.process_mode = Node.PROCESS_MODE_DISABLED
	ring_swarm.set("max_hp", 500.0)
	ring_swarm.call("spawn", 1, tank.global_position)
	var ring_slime: int = int(ring_swarm.get("_high")) - 1
	var ring_proxy: Node = null
	for child in ring_swarm.get_children():
		if child.is_in_group(&"enemies"):
			ring_proxy = child
			break
	# The swarm is held still (no player to chase here), its stand-in not:
	# a disabled hurtbox leaves the physics world.
	ring_proxy.process_mode = Node.PROCESS_MODE_ALWAYS
	ring_proxy.call("stand_on", ring_slime, tank.global_position + Vector2(-20.0, 0.0))
	for i in 3:
		await get_tree().physics_frame
	ring_here.get("taken").clear()
	tank.call("_deal_aura_damage")
	var slime_hp: float = (ring_swarm.get("hp") as PackedFloat32Array)[ring_slime]
	check("the ring burns the Endless's swarm through its stand-ins, and a monster with a body and a hurtbox once a tick",
		slime_hp < 500.0 and ring_here.get("taken").size() == 1, [slime_hp, ring_here.get("taken")])
	ring_swarm.queue_free()
	both_box.queue_free()
	var body_only: Array = []
	for weapon in ["res://src/characters/tank.gd", "res://src/projectiles/dynamite.gd",
			"res://src/projectiles/meteor.gd", "res://src/projectiles/spelltargetcircle.gd",
			"res://src/projectiles/burningcrater.gd", "res://src/projectiles/petvine.gd",
			"res://src/projectiles/petbossprojectile.gd"]:
		var weapon_src: String = _code_src(weapon)
		if weapon_src.contains("get_overlapping_bodies()") or not weapon_src.contains("Targets.touching("):
			body_only.append(weapon.get_file())
	check("  and every blast, ring and spike of the players' reads both through Targets.touching()",
		body_only.is_empty(), body_only)
	var landing: Vector2 = tank.call("dynamite_landing", Vector2(thin_x + 600.0, base.y - 120.0))
	check("dynamite thrown at a wall comes down this side of it", landing.y > base.y + 1.0, landing)
	ring_here.get("taken").clear()
	var stick: Dynamite = (load("res://scene/projectiles/dynamite.tscn") as PackedScene).instantiate()
	stick.explosion_damage = 10
	stick.caster = tank
	arena.add_child(stick)
	stick.throw_from(Vector2(thin_x + 600.0, base.y + 6.0), Vector2(thin_x + 600.0, base.y + 6.0))
	for i in 3:
		await get_tree().physics_frame
	check("a stick's blast reaches past the wall", stick.get_overlapping_bodies().has(ring_past))
	stick.explode()
	check("  and hurts only this side", ring_past.get("taken").is_empty() and not ring_here.get("taken").is_empty(),
		[ring_past.get("taken"), ring_here.get("taken")])
	tank.queue_free()

	# ---- the healer's orb ---------------------------------------------------------
	var healer: Node2D = _hero_against(arena, "healer", base.y + 1.0, thin_x + 1200.0)
	var bolt: Area2D = (healer.get("projectile_scene") as PackedScene).instantiate()
	bolt.set("fan", true)
	bolt.set("direction", Vector2.UP)
	bolt.set("speed", 200.0)
	bolt.set("damage", 10)
	bolt.set("owner_group", "player")
	arena.add_child(bolt)
	bolt.global_position = Vector2(thin_x + 1200.0, base.y + 20.0)
	var bolt_past: CharacterBody2D = _weapon_dummy(arena, Vector2(thin_x + 1200.0, base.y - 40.0))
	for i in 30:
		await get_tree().physics_frame
		if not is_instance_valid(bolt):
			break
	check("the healer's orb bursts on the wall and never reaches the monster past it",
		not is_instance_valid(bolt) and bolt_past.get("taken").is_empty(), bolt_past.get("taken"))
	var _seek_past: CharacterBody2D = _weapon_dummy(arena, Vector2(thin_x + 1300.0, base.y - 10.0))
	var seek_here: CharacterBody2D = _weapon_dummy(arena, Vector2(thin_x + 1300.0, base.y + 80.0))
	var seeker: Area2D = (healer.get("projectile_scene") as PackedScene).instantiate()
	arena.add_child(seeker)
	seeker.global_position = Vector2(thin_x + 1300.0, base.y + 20.0)
	check("  and one homing picks the nearest monster it can see",
		seeker.call("_find_nearest_enemy") == seek_here, seeker.call("_find_nearest_enemy"))
	seeker.queue_free()
	var dropped: Vector2 = healer.call("aura_point", Vector2(thin_x + 1200.0, base.y - 100.0))
	check("  and its aura dropped past a wall lands this side", dropped.y > base.y + 1.0, dropped)
	healer.queue_free()

	# ---- a pet --------------------------------------------------------------------
	var pet: Node2D = (load("res://scene/pets/petsniper.tscn") as PackedScene).instantiate()
	arena.add_child(pet)
	pet.set_physics_process(false)
	pet.global_position = Vector2(thin_x + 1800.0, base.y + 20.0)
	var _pet_past: CharacterBody2D = _weapon_dummy(arena, Vector2(thin_x + 1800.0, base.y - 10.0))
	var pet_here: CharacterBody2D = _weapon_dummy(arena, Vector2(thin_x + 1800.0, base.y + 120.0))
	await get_tree().physics_frame
	check("a pet shoots the nearest monster it can see, not one nearer behind a wall",
		pet.call("_find_nearest_enemy") == pet_here, pet.call("_find_nearest_enemy"))
	pet.queue_free()

	# ---- the bush mage's stray boxes ----------------------------------------------
	var bush: Node = (load("res://scene/enemy/bushmage.tscn") as PackedScene).instantiate()
	var strays: Array = []
	for child in bush.get_children():
		if child is Area2D and str(child.name) != "hurtbox" and ((child as Area2D).collision_layer & 8) != 0:
			strays.append(str(child.name))
	check("the bush mage carries no Area2D on the monsters' layer but its hurtbox - four 108 px boxes made it hittable a box away, through walls",
		strays.is_empty(), strays)
	bush.free()

	# ---- another warrior's axe, called home with their attacks switched off -------
	var Remote := preload("res://src/characters/remoteplayer.gd")
	var kept: bool = bool(Settings.get_value("others_attacks"))
	var them: Node2D = Remote.new()
	them.user_id = 692
	arena.add_child(them)
	them.set_identity({"id": 692, "name": "Wes", "cls": "warrior", "lvl": 20, "v": 2})
	them.set_process(false)
	them.place(base + Vector2(0, 300))
	Settings.set_value("others_attacks", true)
	var copies: Array = RemoteAttacks.fire(them, ["axe", 0, base.x, base.y + 300.0, base.x + 60.0, base.y + 300.0, 0, 0])
	var copy: SpinningAxe = copies[0] if not copies.is_empty() else null
	if copy != null:
		copy.set_physics_process(false)
		for i in 30:
			copy.advance(1.0 / 30.0)
	Settings.set_value("others_attacks", false)
	RemoteAttacks.fire(them, ["recall", 0, base.x, base.y + 300.0, base.x, base.y + 300.0, 0, 0])
	check("their axe, thrown while their attacks were shown, still goes home once they are switched off",
		copy != null and copy.state == SpinningAxe.State.RETURNING, str(copy.state) if copy != null else "no copy")
	Settings.set_value("others_attacks", kept)
	if copy != null and is_instance_valid(copy):
		copy.queue_free()
	# Another warrior pressed against the door, on a game from before 0.69.1,
	# which throws its wave from its origin - inside the door (0.70.0).
	var pressed: Node2D = Remote.new()
	pressed.user_id = 693
	arena.add_child(pressed)
	pressed.set_identity({"id": 693, "name": "Ola", "cls": "warrior", "lvl": 20, "v": 2})
	pressed.set_process(false)
	var pressed_feet: Node2D = pressed.get_node_or_null(^"bodyshape") as Node2D
	var feet_y: float = pressed_feet.position.y if pressed_feet != null else 13.0
	pressed.place(Vector2(door_x - 150.0, base.y + 8.0 + 7.5 - feet_y))
	var o2: Vector2 = pressed.global_position
	Settings.set_value("others_attacks", true)
	var into: Array = RemoteAttacks.fire(pressed, ["slash", 0, o2.x, o2.y, o2.x, o2.y - 100.0, 0, 0])
	var away: Array = RemoteAttacks.fire(pressed, ["slash", 0, o2.x, o2.y, o2.x, o2.y + 100.0, 0, 0])
	Settings.set_value("others_attacks", kept)
	check("another warrior's wave thrown from inside a door is not drawn past it; thrown away from it, it is",
		into.is_empty() and away.size() == 1, [into.size(), away.size()])
	for made_wave in away:
		(made_wave as Node).queue_free()
	check("  and an axe taken off while it is out is called home on everyone else's screen too",
		_func_body(_code_src("res://src/characters/warrior.gd"), "func _on_gear_changed(").contains("tell_attack(\"recall\""))

	# ---- every way a player hurts a monster asks ----------------------------------
	var asks := {
		"res://src/characters/warrior.gd": [["func _try_damage(", "can_hit("], ["func _spawn_slashwave(", "clear_between("],
			["func fling_sword_fan(", "clear_between("], ["func throw_axe(", "reach_short_of_wall("]],
		"res://src/characters/mage.gd": [["func _spawn_stalagmite(", "reach_short_of_wall("], ["func _cast_stalagmite_drop(", "reach_short_of_wall("]],
		"res://src/characters/tank.gd": [["func _deal_aura_damage(", "can_hit("], ["func dynamite_landing(", "reach_short_of_wall("]],
		"res://src/characters/healer.gd": [["func aura_point(", "reach_short_of_wall("], ["func _spawn_projectile(", "reach_short_of_wall("]],
		"res://src/projectiles/slashwave.gd": [["func _try_hit(", "can_reach("]],
		"res://src/projectiles/bladeorb.gd": [["func _try_hit(", "can_reach("]],
		"res://src/projectiles/spinningaxe.gd": [["func _cut(", "can_reach("]],
		"res://src/projectiles/spelltargetcircle.gd": [["func _apply_area_damage(", "can_reach("]],
		"res://src/projectiles/meteor.gd": [["func _apply_damage(", "can_reach("]],
		"res://src/projectiles/burningcrater.gd": [["func _burn(", "can_reach("]],
		"res://src/projectiles/dynamite.gd": [["func explode(", "can_reach("]],
		"res://src/projectiles/healaura.gd": [["func tick(", "can_reach("]],
		"res://src/projectiles/turretprojectile.gd": [["func _physics_process(", "clear_between("], ["func _find_nearest_enemy(", "can_reach("]],
		"res://src/projectiles/petarrow.gd": [["func _physics_process(", "clear_between("]],
		"res://src/projectiles/petfireprojectile.gd": [["func _physics_process(", "clear_between("]],
		"res://src/projectiles/petelectricprojectile.gd": [["func _physics_process(", "clear_between("]],
		"res://src/pets/pet.gd": [["func _find_nearest_enemy(", "sees("]],
		"res://src/systems/touchcontrols.gd": [["func nearest_monster(", "can_reach("]],
	}
	var deaf: Array = []
	for path in asks:
		var code: String = _code_src(path)
		for pair in asks[path]:
			if not _func_body(code, pair[0]).contains(pair[1]):
				deaf.append("%s %s" % [path.get_file(), pair[0]])
	check("every way a player hurts a monster asks whether a wall stands between", deaf.is_empty(), deaf)
	arena.queue_free()
	await get_tree().process_frame


func _test_enemies_see_a_player_against_a_wall() -> void:
	section("ENEMIES - a player pressed against a wall is seen and shot at")
	const Targets := preload("res://src/shared/targets.gd")
	var arena := Node2D.new()
	add_child(arena)
	var base := Vector2(-70000, -70000)
	# Two walls on layer 1, the TileMaps' layer and the one the sight ray masks:
	# one with its bottom edge at north_y, one with its top edge at south_y.
	var north_y: float = base.y
	var south_y: float = base.y + 600.0
	for spec in [[north_y - 40.0], [south_y + 40.0]]:
		var wall := StaticBody2D.new()
		wall.collision_layer = 1
		wall.collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(2400, 80)
		shape.shape = rect
		wall.add_child(shape)
		arena.add_child(wall)
		wall.global_position = Vector2(base.x, float(spec[0]))
	var enemy: BaseEnemy = (load("res://scene/enemy/firesprite.tscn") as PackedScene).instantiate()
	arena.add_child(enemy)
	enemy.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var origin_in_a_wall: Array = []
	var blind: Array = []
	var held_fire: Array = []
	var x: float = base.x - 900.0
	for cls in ["warrior", "mage", "tank", "healer"]:
		var hero: Node = (load("res://scene/characters/%s.tscn" % cls) as PackedScene).instantiate()
		var body_node: CollisionShape2D = hero.get_node_or_null("bodyshape") as CollisionShape2D
		var offset: Vector2 = body_node.position if body_node != null else Vector2.ZERO
		var reach: float = 0.0
		if body_node != null and body_node.shape is CircleShape2D:
			reach = (body_node.shape as CircleShape2D).radius
		elif body_node != null and body_node.shape is CapsuleShape2D:
			reach = (body_node.shape as CapsuleShape2D).height * 0.5
		hero.free()
		for side in ["north", "south"]:
			# A stand-in carrying the class's own body offset, like a RemotePlayer,
			# its body touching the wall exactly as a walk into it leaves it.
			var target := Node2D.new()
			var marker := Node2D.new()
			marker.name = "bodyshape"
			marker.position = offset
			target.add_child(marker)
			arena.add_child(target)
			var body_y: float = north_y + reach + 0.5 if side == "north" else south_y - reach - 0.5
			target.global_position = Vector2(x, body_y - offset.y)
			if (side == "north" and target.global_position.y < north_y) \
					or (side == "south" and target.global_position.y > south_y):
				origin_in_a_wall.append("%s %s" % [cls, side])
			# The enemy stands off to one side and back from the wall, in range.
			var away: float = 70.0 if side == "north" else -70.0
			enemy.global_position = Vector2(x + 90.0, body_y + away)
			enemy.player = target
			if not enemy._has_line_of_sight(enemy.target_point()):
				blind.append("%s %s" % [cls, side])
			enemy.attack_ready = true
			enemy.is_attacking = false
			enemy._trigger_attack()
			if not enemy.is_attacking:
				held_fire.append("%s %s" % [cls, side])
			enemy.is_attacking = false
			target.free()
			x += 400.0
	check("the case is real: some class's origin is inside the wall it walked into",
		not origin_in_a_wall.is_empty(), origin_in_a_wall)
	check("an enemy sees every class, pressed against a wall either way",
		blind.is_empty(), blind)
	check("  and opens fire on every one of them", held_fire.is_empty(), held_fire)

	# The body, not the origin, for anything with a body; the origin otherwise.
	var probe := Node2D.new()
	var feet := Node2D.new()
	feet.name = "bodyshape"
	feet.position = Vector2(0, 13)
	probe.add_child(feet)
	arena.add_child(probe)
	probe.global_position = base + Vector2(0, 300)
	check("Targets.body_point() is the body", Targets.body_point(probe) == probe.global_position + Vector2(0, 13))
	feet.free()
	check("  or the node itself when there is no body", Targets.body_point(probe) == probe.global_position)

	# EVERY AIM AND EVERY SIGHT LINE goes through the one helper. A new enemy that
	# writes player.global_position into a ray or a shot brings this bug back.
	var leftovers: Array = []
	for path in _all_gd_under("res://src/enemies"):
		var code: String = _code_src(path)
		for bad in ["_has_line_of_sight(player.global_position)", "player.global_position - spawn_node",
				"shoot_vector(player.global_position"]:
			if code.contains(bad):
				leftovers.append("%s: %s" % [path.get_file(), bad])
	check("no enemy aims a sight line or a shot at the player's origin", leftovers.is_empty(), leftovers)
	arena.queue_free()
	await get_tree().process_frame

# 6 Oct, the owner: "wider pick up radius". The bag's circle had no radius line
# in lootbag.tscn, so it was Godot's default 10 px; it is 40 now. And it sat on
# the player layer, where enemy shots look for the player and burst on whatever
# they meet - a bag four times wider would have been a four-times-wider shield.
func _test_a_loot_bag_is_reached_from_further() -> void:
	section("LOOT BAG - reached from further away, and no shield")
	var bag := (load("res://scene/interactables/lootbag.tscn") as PackedScene).instantiate() as Area2D
	var shape_node := bag.get_node_or_null("collisionshape2d") as CollisionShape2D
	var circle := (shape_node.shape if shape_node != null else null) as CircleShape2D
	check("the bag's reach is a circle with a radius written down",
		circle != null, shape_node)
	check("  of 40 px, four times the default it used to fall back to",
		circle != null and is_equal_approx(circle.radius, 40.0), circle.radius if circle != null else -1.0)
	check("it is on the interactors layer, like the chest and the lever",
		bag.collision_layer == 16, bag.collision_layer)
	check("  and not the player layer any more", (bag.collision_layer & 4) == 0, bag.collision_layer)
	var hero := (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate() as CollisionObject2D
	check("it still sees the player's body walk in",
		hero != null and (bag.collision_mask & hero.collision_layer) != 0,
		[bag.collision_mask, hero.collision_layer if hero != null else -1])
	if hero != null:
		hero.free()
	# EVERY enemy shot and hazard that is an Area2D: none of them may see the bag.
	var shields: Array = []
	var dir := DirAccess.open("res://scene/projectiles")
	for file in dir.get_files():
		if not file.ends_with(".tscn"):
			continue
		var shot := (load("res://scene/projectiles/" + file) as PackedScene).instantiate()
		if shot is CollisionObject2D and ((shot as CollisionObject2D).collision_layer & 64) != 0 \
				and ((shot as CollisionObject2D).collision_mask & bag.collision_layer) != 0:
			shields.append(file)
		shot.free()
	check("no enemy projectile or puddle can meet a bag, so a bag is not a shield",
		shields.is_empty(), shields)
	bag.free()


func _test_rare_loot_reads_as_rare() -> void:
	section("RARE LOOT — rarity colours, the loot bag, and the glow")

	check("each tier has its name", GameConstants.rarity_name(1) == "Common"
		and GameConstants.rarity_name(2) == "Uncommon" and GameConstants.rarity_name(3) == "Rare"
		and GameConstants.rarity_name(4) == "Epic" and GameConstants.rarity_name(5) == "Legendary",
		[GameConstants.rarity_name(1), GameConstants.rarity_name(5)])
	check("past the end is Mythic, before the start is Common",
		GameConstants.rarity_name(8) == "Mythic" and GameConstants.rarity_name(0) == "Common")
	var seen_colours: Dictionary = {}
	for t in range(1, 7):
		seen_colours[GameConstants.rarity_colour(t).to_html()] = t
	check("the six rarities are six different colours", seen_colours.size() == 6, seen_colours)

	# Items the suite can build without the art pack: the ones a clone has
	# are pets, and the point here is the TIER, not the art.
	var legendary := _rarity_test_item("raritytest_legendary", 5)
	var epic := _rarity_test_item("raritytest_epic", 4)
	var common := _rarity_test_item("raritytest_common", 1)
	var coin := _rarity_test_item("raritytest_coin", 6, ItemData.Type.CURRENCY)
	for d in [legendary, epic, common, coin]:
		ItemRegistry._items[d.item_id] = d

	# ---- the slot -----------------------------------------------------------
	var slot_packed: PackedScene = load("res://scene/ui/inventory/inventoryslot.tscn")
	var slot: InventorySlot = slot_packed.instantiate()
	add_child(slot)
	await get_tree().process_frame
	slot.set_stack(ItemStack.new(legendary, 3))
	var frame: Panel = slot.get_node_or_null("rarityframe")
	check("a legendary item frames its slot in the legendary colour",
		frame != null and frame.visible
		and (frame.get_theme_stylebox("panel") as StyleBoxFlat).border_color == GameConstants.rarity_colour(5))
	check("and the frame sits under the stack count, so the number stays on top",
		frame != null and frame.get_index() < slot.quantity_label.get_index())
	slot.set_stack(ItemStack.new(common, 1))
	check("a common item draws no frame", frame != null and not frame.visible)
	slot.clear_stack()
	check("nor does an empty slot", frame != null and not frame.visible)
	check("the stack count is big enough to read (was font size 7)",
		slot.quantity_label.get_theme_font_size("font_size") >= 10,
		slot.quantity_label.get_theme_font_size("font_size"))
	slot.set_stack(ItemStack.new(epic, 5))
	check("and it shows the count", slot.quantity_label.text == "5", slot.quantity_label.text)
	slot.queue_free()

	# ---- the tooltip ----------------------------------------------------------
	var tip_packed: PackedScene = load("res://scene/ui/inventory/itemtooltip.tscn")
	var tip: Control = tip_packed.instantiate()
	add_child(tip)
	await get_tree().process_frame
	var plain_colour: Color = tip.name_label.get_theme_color("font_color")
	tip.show_for_stack(ItemStack.new(legendary, 1), null)
	check("the tooltip says how rare it is, in its colour",
		tip.rarity_label != null and tip.rarity_label.text == "Legendary"
		and tip.rarity_label.get_theme_color("font_color") == GameConstants.rarity_colour(5),
		tip.rarity_label.text if tip.rarity_label != null else "no label")
	check("and the name takes the colour too",
		tip.name_label.get_theme_color("font_color") == GameConstants.rarity_colour(5))
	tip.show_for_stack(ItemStack.new(common, 1), null)
	check("a common name keeps the tooltip's own gold",
		tip.name_label.get_theme_color("font_color") == plain_colour and tip.rarity_label.text == "Common")
	tip.queue_free()

	# ---- the loot bag panel ---------------------------------------------------
	var Bag: Script = load("res://src/ui/lootbag/lootbaginventory.gd")
	var one := {"item_id": "x", "quantity": 1}
	check("rows: an empty bag is still one row", Bag.rows_needed([], 3) == 1)
	check("rows: two items are one row", Bag.rows_needed([one, one], 3) == 1)
	check("rows: four items are two", Bag.rows_needed([one, one, one, one], 3) == 2)
	check("rows: a gap still counts - the last item decides",
		Bag.rows_needed([null, null, null, one], 3) == 2 and Bag.rows_needed([one, null, null, null], 3) == 1)

	var panel_packed: PackedScene = load("res://scene/ui/lootbag/lootbaginventory.tscn")
	var panel: Control = panel_packed.instantiate()
	add_child(panel)
	await get_tree().process_frame
	var cells: Array = [{"item_id": legendary.item_id, "quantity": 1}, {"item_id": epic.item_id, "quantity": 1}]
	panel._load_contents(cells)
	var shown: int = 0
	for s in panel.loot_container.get_children():
		if s is InventorySlot and s.visible:
			shown += 1
	check("a two-item bag shows one row of cells, not two", shown == 3, shown)
	panel._load_contents(cells + cells)
	shown = 0
	for s in panel.loot_container.get_children():
		if s is InventorySlot and s.visible:
			shown += 1
	check("a four-item bag shows both rows", shown == 6, shown)
	var scroll: Control = panel.get_node("mainpanel/margincontainer/vboxcontainer/lootscroll")
	check("no fixed 200-pixel area under the grid", scroll.custom_minimum_size.y == 0.0,
		scroll.custom_minimum_size)
	check("the cells pack like the inventory's (same -4 spacing)",
		panel.loot_container.get_theme_constant("h_separation") == -4
		and panel.loot_container.get_theme_constant("v_separation") == -4)
	var loot_size: int = int(Bag.get_script_constant_map().get("LOOT_SIZE", 0))
	check("a bag has nine cells, three rows of three (it was six, and boss bags ran past it)",
		loot_size == 9 and panel.loot_container.grid_width * panel.loot_container.grid_height == loot_size,
		[loot_size, panel.loot_container.grid_width, panel.loot_container.grid_height])
	check("there is a Take all button, and it is wired",
		panel.take_all_button != null and panel.take_all_button.pressed.is_connected(panel._on_take_all_pressed))

	# Take all against a pretend server: cell 1 will not fit, the rest do.
	var asked: Array = []
	var answers: Dictionary = {1: {"ok": false, "status": 409}}
	panel._bag_id = "raritytest-bag"
	panel.visible = true
	panel._load_contents(cells + cells)
	panel.take_request = func(_bag: String, cell: int) -> Dictionary:
		asked.append(cell)
		await get_tree().process_frame
		return answers.get(cell, {"ok": true, "data": {"credited": "inventory", "bag_empty": false}})
	var taken: int = await panel.take_all()
	check("Take all asks for every cell, in order", asked == [0, 1, 2, 3], asked)
	check("a cell that will not fit is skipped, not the end of it", taken == 3, taken)
	check("and the ones taken are gone from the grid",
		panel.loot_container.get_children()[0].is_empty() and not panel.loot_container.get_children()[1].is_empty())

	# MUTATED, NOT REASSIGNED: a GDScript lambda captures its locals by value
	# when it is made, so a new dictionary here would never reach it.
	asked.clear()
	answers.clear()
	answers[1] = {"ok": false, "status": 0}
	panel._load_contents(cells + cells)
	taken = await panel.take_all()
	check("a lost connection stops Take all where it failed", asked == [0, 1] and taken == 1, [asked, taken])
	check("and the button comes back", not panel.take_all_button.disabled)
	panel.take_request = Callable()
	panel.queue_free()

	# ---- the bag on the ground ------------------------------------------------
	var World: Script = load("res://src/world/lootbag.gd")
	check("the rarest item sets the bag's tier",
		World.rare_tier_of([{"item_id": common.item_id}, {"item_id": epic.item_id}], false) == 4)
	check("coins do not count, however big the heap",
		World.rare_tier_of([{"item_id": coin.item_id}], false) == 0)
	check("a pet counts as legendary", World.rare_tier_of([], true) == 5)

	var bag_packed: PackedScene = load("res://scene/interactables/lootbag.tscn")
	var bag: Node2D = bag_packed.instantiate()
	add_child(bag)
	await get_tree().process_frame
	check("the old flat beam is gone", bag.get_node_or_null("petbeam") == null)
	bag.set_contents([{"item_id": common.item_id, "quantity": 1}])
	check("a common bag does not glow", bag.glow_tier() == 0)
	bag.set_contents([{"item_id": epic.item_id, "quantity": 1}])
	check("an epic bag glows", bag.glow_tier() == 4)
	var pool: Sprite2D = bag.get_node_or_null("rareglow/pool")
	check("in the epic colour",
		pool != null and Color((pool.texture as GradientTexture2D).gradient.get_color(0), 1.0)
		== Color(GameConstants.rarity_colour(4), 1.0))
	bag.set_has_pet(true)
	check("a pet lights it legendary", bag.glow_tier() == 5)
	bag.set_has_pet(false)
	bag.set_contents([null])
	var glow_node: Node2D = bag.get_node_or_null("rareglow")
	check("and it goes out once the rare thing is taken - the light itself, not just the number",
		bag.glow_tier() == 0 and glow_node != null and not glow_node.visible)
	bag.queue_free()

	for d in [legendary, epic, common, coin]:
		ItemRegistry._items.erase(d.item_id)


# =============================================================================
# AMULETS: WHAT WEARING ONE ADDS
# =============================================================================
# Fifteen amulets in four families, and the family is the colour: green is
# health (Vitality), blue is mana (Arcana), crimson is damage (Fury), purple is
# armour (Ward). The plainest icon of a colour is its lowest tier.
#
# THE SERVER HAS TO AGREE, which is most of what can go wrong. max_hp is
# server-derived and the status route clamps hp to it, so a bonus only this
# client knew about would be taken away on every save. test_gearbonus.py holds
# the server half; this holds the client half and the file between them.

func _test_amulets_carry_their_bonus() -> void:
	section("AMULETS — what wearing one adds, and the server counting it")

	# ---- the fifteen, as authored, and as exported --------------------------
	var gd := _load_gamedata()
	var exported: Dictionary = {}
	for row in gd.get("items", []):
		if row is Dictionary:
			exported[str(row.get("item_id", ""))] = row
	var icons_seen: Dictionary = {}
	var authored: Array = []
	for family in _AMULET_FAMILIES:
		var field: String = _AMULET_FAMILIES[family][0]
		var icon_range: Array = _AMULET_FAMILIES[family][2]
		var amounts: Array = []
		for tier in _AMULET_FAMILIES[family][1]:
			var iid: String = "%s%samulet" % [_AMULET_PREFIX[tier], family]
			var f := _tres_fields("res://data/items/amulets/%s.tres" % iid)
			if f.is_empty():
				check("%s is authored" % iid, false, "no data/items/amulets/%s.tres" % iid)
				continue
			authored.append(iid)
			var amount := int(f.get(field, "0"))
			amounts.append(amount)
			check("%s: its id is its file name, it is an amulet, tier %d at level %d" % [iid, tier, _AMULET_LEVEL[tier]],
				f.get("item_id") == iid
				and int(f.get("equip_slot", "0")) == ItemData.EquipSlot.AMULET
				and int(f.get("type", "0")) == ItemData.Type.ARMOR
				and int(f.get("tier", "0")) == tier
				and int(f.get("required_level", "0")) == _AMULET_LEVEL[tier], f)
			var others: Array = []
			for other in ["bonus_max_hp", "bonus_max_mana", "bonus_damage_percent", "armor_value", "damage"]:
				if other != field and f.has(other):
					others.append(other)
			check("  carries %s and nothing else" % field, amount > 0 and others.is_empty(), [amount, others])
			var icon: String = str(f.get("_icon_path", ""))
			var number := int(icon.get_file().get_basename().trim_prefix("a"))
			check("  wears a %s-coloured pack icon nobody else wears" % family,
				icon.begins_with("res://art/pack/amulets/a")
				and number >= int(icon_range[0]) and number <= int(icon_range[1])
				and not icons_seen.has(icon), [icon, icons_seen.get(icon, "")])
			icons_seen[icon] = iid
			var row: Dictionary = exported.get(iid, {})
			check("  and gamedata.json says the same (re-run the exporter if not)",
				not row.is_empty() and int(row.get(field, -1)) == amount
				and int(row.get("tier", -1)) == tier
				and int(row.get("required_level", -1)) == _AMULET_LEVEL[tier], row)
		var climbing := true
		for i in range(1, amounts.size()):
			if int(amounts[i]) <= int(amounts[i - 1]):
				climbing = false
		check("the %s bonus climbs with tier" % family, climbing, amounts)
	check("all fifteen are authored", authored.size() == 15, authored)

	var missing_fields: Array = []
	for iid in exported:
		for field in ["bonus_max_hp", "bonus_max_mana", "bonus_damage_percent"]:
			if not (exported[iid] as Dictionary).has(field):
				missing_fields.append("%s.%s" % [iid, field])
	check("every exported item carries the three bonus fields, so the server can sum them",
		missing_fields.is_empty(), missing_fields.slice(0, 5))
	var exporter := FileAccess.get_file_as_string("res://src/tools/exportgamedata.gd")
	for field in ["bonus_max_hp", "bonus_max_mana", "bonus_damage_percent"]:
		check("the exporter writes %s" % field, exporter.contains("\"%s\": item.%s" % [field, field]))

	var loaded := 0
	for iid in authored:
		var real: ItemData = ItemRegistry.get_item(iid)
		if real != null and real.icon != null:
			loaded += 1
	check_needs_pack("every amulet loads in game with its icon", loaded == authored.size(),
		"%d of %d" % [loaded, authored.size()])

	# ---- the character, with amulets the suite can build without the art ----
	var vit := _amulet_test_item("amulettest_vitality", "bonus_max_hp", 50)
	var arc := _amulet_test_item("amulettest_arcana", "bonus_max_mana", 40)
	var fury := _amulet_test_item("amulettest_fury", "bonus_damage_percent", 10)
	for d in [vit, arc, fury]:
		ItemRegistry._items[d.item_id] = d

	# THE BODY WITHOUT THE WORLD. Adding a warrior to the tree runs all of
	# player.gd's _ready() - camera, pets, the save - for checks about sums.
	var body: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	body._set_stat_curve()
	body.equipped = {}
	body.level = 10
	var bare_hp: int = body.max_hp
	var bare_mana: int = body.max_mana
	check("with nothing worn, max_hp is the class curve",
		bare_hp == PlayerStats.max_for(body.hp_base, body.hp_per_lvl, 10), bare_hp)

	body.hp = bare_hp
	check("a Vitality amulet can be put on", body.equip(vit.item_id))
	check("  it raises max_hp by its bonus", body.max_hp == bare_hp + 50, [body.max_hp, bare_hp])
	check("  but not hp - the ceiling moves, not the health", body.hp == bare_hp, body.hp)
	body.hp = body.max_hp
	body.unequip("amulet")
	check("taking it off brings max_hp back to the curve", body.max_hp == bare_hp, body.max_hp)
	check("  and hp comes down with it rather than sitting over the ceiling", body.hp == bare_hp, body.hp)
	body.hp = 40
	body.equip(vit.item_id)
	body.unequip("amulet")
	check("a wounded character stays exactly as wounded through on and off", body.hp == 40, body.hp)

	body.mana = bare_mana
	body.equip(arc.item_id)
	check("an Arcana amulet raises max_mana and nothing else",
		body.max_mana == bare_mana + 40 and body.max_hp == bare_hp, [body.max_mana, body.max_hp])
	body.mana = body.max_mana
	body.equip(fury.item_id)
	check("swapping it for Fury takes the mana back off",
		body.max_mana == bare_mana and body.mana == bare_mana, [body.max_mana, body.mana])

	var skill_mult: float = PlayerStats.damage_multiplier(body.attack, body.magic)
	check("a Fury amulet multiplies every hit by its percent",
		is_equal_approx(body.get_damage_multiplier(), skill_mult * 1.10),
		[body.get_damage_multiplier(), skill_mult])
	var with_fury: Vector2i = body.attack_damage_range()
	body.unequip("amulet")
	var without: Vector2i = body.attack_damage_range()
	check("  and the equipment panel's damage band shows it",
		with_fury.y > without.y and with_fury.x >= without.x, [with_fury, without])
	check("a negative damage percent is floored - a hit can never heal",
		is_equal_approx(PlayerStats.gear_damage_factor(-50), 1.0))
	body.equipped = {"amulet": "amulettest_nosuchthing"}
	check("an id the registry does not know adds nothing",
		body.equipped_bonus("bonus_max_hp") == 0 and body.equipped_bonus("bonus_damage_percent") == 0)

	# THE RECOMPUTE ITSELF MUST NOT CLAMP. It runs through the level setter in
	# the middle of CharacterData.load_character_state(), before hp is read, so
	# a clamp there would cut a loading character's health to a stale ceiling.
	body.equipped = {}
	body.hp = 99999
	body._recompute_max_stats()
	check("_recompute_max_stats() never touches hp (it runs mid-load)", body.hp == 99999, body.hp)

	# THE SERVER'S ANSWER, RENDERED. /api/character/unequip has already clamped
	# its own copy; the client has to land in the same place.
	body.equipped = {"amulet": vit.item_id}
	body._recompute_max_stats()
	body.hp = body.max_hp
	CharacterData._apply_equip_result(body, {"equipment": {}})
	check("the equip endpoint's answer moves the maxima and the pool with it",
		body.max_hp == bare_hp and body.hp == bare_hp, [body.max_hp, body.hp])
	body.free()

	# ---- the tooltip says what it does --------------------------------------
	var tip := ItemTooltip.new()
	check("a Vitality tooltip says +50 max health",
		ItemTooltip._requirement_lines(vit).to_lower().contains("+50 max health"), ItemTooltip._requirement_lines(vit))
	check("an Arcana tooltip says +40 max mana",
		ItemTooltip._requirement_lines(arc).to_lower().contains("+40 max mana"), ItemTooltip._requirement_lines(arc))
	check("a Fury tooltip says +10% damage",
		ItemTooltip._requirement_lines(fury).to_lower().contains("+10% damage"), ItemTooltip._requirement_lines(fury))
	tip.free()

	for d in [vit, arc, fury]:
		ItemRegistry._items.erase(d.item_id)


# =============================================================================
# THE PACE: element bands, the eight-hour curve, dangerous slimes, the finale
# =============================================================================
# The plan in the Economy and Progression doc, held against the data. Every
# number below is read from the .tres files, so retuning one enemy is caught
# here as a band drifting, not discovered as "the game got fast again".

func _test_the_game_has_a_pace() -> void:
	section("PACE — element bands, the eight-hour curve, dangerous slimes, the Crowned's door")

	# ---- the curve ----------------------------------------------------------
	check("level 1 costs the curve's 1,250 XP", GameConstants.xp_needed_for_level(1) == 1250,
		GameConstants.xp_needed_for_level(1))
	check("a brand-new save starts on the same first level",
		int(CharacterData.SAVEABLE_STATS["xp_next"]) == GameConstants.xp_needed_for_level(1),
		CharacterData.SAVEABLE_STATS["xp_next"])
	var fresh: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	check("so does a freshly built player",
		int(fresh.get("xp_next")) == GameConstants.xp_needed_for_level(1), fresh.get("xp_next"))
	fresh.free()

	# ---- the bands ----------------------------------------------------------
	var element_hp: Dictionary = {}
	var element_hit: Dictionary = {}
	var band_xp: Dictionary = {}
	var off_band: Array = []
	var odd_ratio: Array = []
	for el in _LADDER:
		var band: int = _BAND_OF[el]
		var hps: Array = []
		var hits: Array = []
		for eid in _BAND_FAMILY[el]:
			var f := _enemy_fields(eid)
			var hp := int(f.get("max_hp", "0"))
			var xp := int(f.get("xp_reward", "0"))
			hps.append(hp)
			hits.append(int(f.get("projectile_damage", "0")))
			if not band_xp.has(band):
				band_xp[band] = []
			band_xp[band].append(xp)
			if int(f.get("max_loot_tier", "0")) != band:
				off_band.append("%s tier %s" % [eid, f.get("max_loot_tier")])
			# XP stays at today's ratio to health, about 0.37 a point.
			if hp <= 0 or float(xp) / hp < 0.30 or float(xp) / hp > 0.42:
				odd_ratio.append("%s %d/%d" % [eid, xp, hp])
		element_hp[el] = hps.reduce(func(a, b): return a + b, 0) / float(hps.size())
		element_hit[el] = hits.reduce(func(a, b): return a + b, 0) / float(hits.size())
	check("every normal drops up to its band's tier (light/wind iron ... dark ember)",
		off_band.is_empty(), off_band)
	check("every normal pays about 0.37 XP per point of health", odd_ratio.is_empty(), odd_ratio)
	for band in [1, 2, 3, 4, 5]:
		var hp_sum := 0.0
		var hit_sum := 0.0
		var n := 0
		for el in _LADDER:
			if _BAND_OF[el] == band:
				hp_sum += element_hp[el]
				hit_sum += element_hit[el]
				n += 1
		check("band %d: normal health averages about %d" % [band, _BAND_HP[band]],
			_near(hp_sum / n, _BAND_HP[band], 0.03), snappedf(hp_sum / n, 0.1))
		check("band %d: a normal hit averages about %d" % [band, _BAND_HIT[band]],
			_near(hit_sum / n, _BAND_HIT[band], 0.06), snappedf(hit_sum / n, 0.1))
	var climbing := true
	for i in range(1, _LADDER.size()):
		if element_hp[_LADDER[i]] <= element_hp[_LADDER[i - 1]]:
			climbing = false
	check("health climbs light, wind, water, ice, earth, fire, dark", climbing, element_hp)

	# ---- the eight hours ----------------------------------------------------
	# Five kills a minute in the band that matches your level. The plan's
	# checkpoints are level 5 in a quarter hour, 10 in about one, 16 in about
	# three and 22 in about eight.
	var avg_xp: Dictionary = {}
	for band in band_xp:
		avg_xp[band] = (band_xp[band] as Array).reduce(func(a, b): return a + b, 0) / float((band_xp[band] as Array).size())
	var minutes := 0.0
	var at: Dictionary = {}
	for level in range(1, 22):
		var band: int = 1 if level < 5 else 2 if level < 10 else 3 if level < 16 else 4
		minutes += GameConstants.xp_needed_for_level(level) / avg_xp[band] / 5.0
		at[level + 1] = minutes / 60.0
	check("level 5 in about a quarter of an hour", at[5] > 0.18 and at[5] < 0.35, snappedf(at[5], 0.01))
	check("level 10 in about an hour", at[10] > 0.7 and at[10] < 1.3, snappedf(at[10], 0.01))
	check("level 16 in about three hours", at[16] > 2.3 and at[16] < 3.5, snappedf(at[16], 0.01))
	check("level 22 in about eight hours", at[22] > 7.0 and at[22] < 9.0, snappedf(at[22], 0.01))

	# ---- the slimes, as data ------------------------------------------------
	var field_text := FileAccess.get_file_as_string("res://scene/field.tscn")
	for el in _SLIME_ELEMENTS:
		var large := _enemy_fields(el + "slimelarge")
		var small := _enemy_fields(el + "slime")
		var large_text := FileAccess.get_file_as_string("res://data/enemies/%sslimelarge.tres" % el)
		check("%s: the large splits into the %s small, same element, and pays nothing itself" % [el, el],
			large_text.contains('path="res://data/enemies/%sslime.tres"' % el)
			and large_text.contains("split_into = ExtResource(")
			and large.get("element") == small.get("element")
			and large.get("grants_rewards") == "false", [large, small])
		check("  large health about twice the band's normal, each small a third",
			_near(int(large.get("max_hp", "0")), 2.0 * element_hp[el], 0.02)
			and _near(int(small.get("max_hp", "0")), element_hp[el] / 3.0, 0.03),
			[large.get("max_hp"), small.get("max_hp"), element_hp[el]])
		check("  and a small's arrow hits for about three quarters of a normal hit",
			absf(int(small.get("projectile_damage", "0")) - 0.75 * element_hit[el]) <= 1.0,
			[small.get("projectile_damage"), element_hit[el]])
		check("  the field places the large, not the small",
			field_text.contains('path="res://scene/enemy/%sslimelarge.tscn"' % el)
			and not field_text.contains('path="res://scene/enemy/%sslime.tscn"' % el))

	# ---- the slimes, alive --------------------------------------------------
	var holder := Node2D.new()
	add_child(holder)
	var large_node: Node = (load("res://scene/enemy/windslimelarge.tscn") as PackedScene).instantiate()
	holder.add_child(large_node)
	await get_tree().process_frame
	check("a placed wind slime is the large, on the large's data",
		not large_node.is_small and large_node.enemy_data != null
		and large_node.enemy_data.enemy_id == "windslimelarge")
	var heard: Array = [false]
	large_node.died.connect(func(): heard[0] = true)
	var smalls_expected: int = int(large_node.small_count)
	var wait_for: float = float(large_node.hitflash_duration) + 0.3
	large_node._begin_split()
	check("splitting tells the respawner the placed large is gone (died, before the await)", heard[0])
	await get_tree().create_timer(wait_for).timeout
	await get_tree().process_frame
	var smalls: Array = []
	for c in holder.get_children():
		if c is PoisonSlime and is_instance_valid(c) and c.is_small:
			smalls.append(c)
	var wrong: Array = []
	for s in smalls:
		if s.enemy_data == null or s.enemy_data.enemy_id != "windslime" or s.current_element() != Element.Type.WIND:
			wrong.append(s.enemy_data.enemy_id if s.enemy_data != null else "null")
	check("it bursts into %d wind smalls on the windslime profile" % smalls_expected,
		smalls.size() == smalls_expected and wrong.is_empty(), [smalls.size(), wrong])

	var twin_parent: Node = (load("res://scene/enemy/windslimelarge.tscn") as PackedScene).instantiate()
	holder.add_child(twin_parent)
	await get_tree().process_frame
	var before: Array = holder.get_children()
	twin_parent._spawn_slime(false, Vector2(40, 0))
	await get_tree().process_frame
	var twin: Node = null
	for c in holder.get_children():
		if not before.has(c):
			twin = c
	check("its twin is another large wind slime, with its duplication spent",
		twin != null and not twin.is_small and twin.enemy_data.enemy_id == "windslimelarge"
		and twin._has_duplicated)

	var poison: Node = (load("res://scene/enemy/poisonslime.tscn") as PackedScene).instantiate()
	holder.add_child(poison)
	await get_tree().process_frame
	before = holder.get_children()
	poison._spawn_slime(true, Vector2(-40, 0))
	await get_tree().process_frame
	var poison_small: Node = null
	for c in holder.get_children():
		if not before.has(c):
			poison_small = c
	check("the original poison slime still bursts into poisonslimesmall",
		poison_small != null and poison_small.enemy_data != null
		and poison_small.enemy_data.enemy_id == "poisonslimesmall")

	# ---- a bush mage hits for its own profile -------------------------------
	var mage: Node = (load("res://scene/enemy/darkbushmage.tscn") as PackedScene).instantiate()
	holder.add_child(mage)
	await get_tree().process_frame
	var scene_root: Node = get_tree().current_scene
	var groundeffects: Node = get_tree().get_first_node_in_group("groundeffects")
	var vine_parent: Node = groundeffects if groundeffects != null else scene_root
	var had: Array = vine_parent.get_children()
	mage._spawn_vine()
	var vine: Node = null
	for c in vine_parent.get_children():
		if not had.has(c):
			vine = c
	check("a dark bush mage's vine hits for its .tres projectile_damage, not the script's 8",
		vine != null and int(vine.damage) == int(_enemy_fields("darkbushmage").get("projectile_damage", "0")),
		vine.damage if vine != null else "no vine")
	if vine != null:
		vine.queue_free()
	holder.queue_free()

	# ---- the finale ---------------------------------------------------------
	var arena := FileAccess.get_file_as_string("res://scene/bossarena.tscn")
	var room := FileAccess.get_file_as_string("res://scene/boss.tscn")
	check("the arena's victory door leads to the Crowned's room",
		arena.contains('destination_scene_path = "res://scene/boss.tscn"')
		and arena.contains('target_spawn_id = "boss_entrance"'))
	check("and that room has the marker it lands on, and a registered area",
		room.contains('portal_id = "boss_entrance"') and AreaRegistry.has_area("boss"))
	var crowned := _enemy_fields("boss")
	var fire := _enemy_fields("fireboss")
	check("the fire boss is about 9,200 health", int(fire.get("max_hp", "0")) == 9200, fire.get("max_hp"))
	check("the Crowned is the hardest fight in the game and drops the best tier",
		int(crowned.get("max_hp", "0")) > int(fire.get("max_hp", "0"))
		and int(crowned.get("max_loot_tier", "0")) == 6
		and int(crowned.get("xp_reward", "0")) > int(fire.get("xp_reward", "0")), crowned)


# =============================================================================
# BETTER LOOT CARRIES MORE, AND LEGENDARY IS RARE
# =============================================================================
# Every piece from jade up adds something beyond its armour or damage, and the
# something grows with the tier: plate adds health, cloth adds mana, weapons
# add damage, and the plain rings and amulets add a little of all three. Iron
# is Common and plain. Ember - Legendary - carries the most, and drops rarely:
# about one an hour in the dark band, 1 in 4 from the fire boss and the
# Crowned, never from the other five bosses.

func _test_better_loot_carries_more() -> void:
	section("LOOT — every tier from jade up carries a bonus, and legendary is rare")

	# ---- the gear ladder ----------------------------------------------------
	var exported: Dictionary = {}
	for row in _load_gamedata().get("items", []):
		if row is Dictionary:
			exported[str(row.get("item_id", ""))] = row
	var groups := {"bonus_max_hp": _PLATE, "bonus_max_mana": _CLOTH, "bonus_damage_percent": _WEAPONS}
	var set_totals: Dictionary = {}
	for field in groups:
		var folder: String = "weapons" if field == "bonus_damage_percent" else "armour"
		for piece in groups[field]:
			var last := 0
			var climbing := true
			var wrong: Array = []
			for mat in _MATERIALS:
				var iid: String = mat + piece
				var f := _item_fields(folder, iid)
				var amount := int(f.get(field, "0"))
				for other in _BONUS_FIELDS:
					if other != field and f.has(other):
						wrong.append("%s has %s" % [iid, other])
				if mat == "iron":
					if amount != 0:
						wrong.append("iron %s has %d - Common stays plain" % [piece, amount])
					continue
				if amount <= last:
					climbing = false
				last = amount
				set_totals["%s:%s" % [field, mat]] = int(set_totals.get("%s:%s" % [field, mat], 0)) + amount
				var row: Dictionary = exported.get(iid, {})
				if int(row.get(field, -1)) != amount:
					wrong.append("gamedata.json says %s for %s (re-export)" % [row.get(field), iid])
			check("%s: %s from jade up, climbing to ember, and nothing else" % [piece, field.trim_prefix("bonus_")],
				climbing and wrong.is_empty(), wrong)
	check("a full ember plate set is +100 health (jade +20, cobalt +40, amethyst +65)",
		set_totals.get("bonus_max_hp:ember") == 100 and set_totals.get("bonus_max_hp:jade") == 20
		and set_totals.get("bonus_max_hp:cobalt") == 40 and set_totals.get("bonus_max_hp:amethyst") == 65,
		set_totals)
	check("a full ember cloth set is +120 mana (jade +24, cobalt +48, amethyst +78)",
		set_totals.get("bonus_max_mana:ember") == 120 and set_totals.get("bonus_max_mana:jade") == 24
		and set_totals.get("bonus_max_mana:cobalt") == 48 and set_totals.get("bonus_max_mana:amethyst") == 78,
		set_totals)

	# ---- the plain jewellery ------------------------------------------------
	var specialist := {2: "lesser", 3: "", 4: "greater", 5: "exalted"}
	var tier_of := {"iron": 1, "jade": 2, "cobalt": 3, "amethyst": 4, "ember": 5}
	for kind in ["amulet", "ring"]:
		var prev := [-1, -1, -1, -1]
		var climbing := true
		var wrong: Array = []
		for mat in _MATERIALS:
			var f := _item_fields("armour", mat + kind)
			var now := [int(f.get("bonus_max_hp", "0")), int(f.get("bonus_max_mana", "0")),
				int(f.get("bonus_damage_percent", "0")), int(f.get("armor_value", "0"))]
			for i in range(4):
				if now[i] <= 0:
					wrong.append("%s%s has no %s" % [mat, kind, ["health", "mana", "damage", "armour"][i]])
				if now[i] < prev[i]:
					climbing = false
			prev = now
			var row: Dictionary = exported.get(mat + kind, {})
			for field in _BONUS_FIELDS:
				if int(row.get(field, -1)) != int(f.get(field, "0")):
					wrong.append("gamedata.json disagrees on %s%s.%s" % [mat, kind, field])
		check("every plain %s, iron to ember, adds health, mana, damage and armour, never shrinking" % kind,
			climbing and wrong.is_empty(), wrong)

	for mat in _MATERIALS:
		var amulet := _item_fields("armour", mat + "amulet")
		var ring := _item_fields("armour", mat + "ring")
		check("the %s ring gives no more than the %s amulet" % [mat, mat],
			int(ring.get("bonus_max_hp", "0")) <= int(amulet.get("bonus_max_hp", "0"))
			and int(ring.get("bonus_max_mana", "0")) <= int(amulet.get("bonus_max_mana", "0"))
			and int(ring.get("bonus_damage_percent", "0")) <= int(amulet.get("bonus_damage_percent", "0")))

	# THE SPECIALISTS STAY SPECIAL. The plain amulet is the all-rounder; at its
	# own tier each family must still win its own stat, or it is the one that
	# becomes vendor loot.
	var losers: Array = []
	for mat in ["jade", "cobalt", "amethyst", "ember"]:
		var tier: int = tier_of[mat]
		var plain := _item_fields("armour", mat + "amulet")
		for pair in [["vitality", "bonus_max_hp"], ["arcana", "bonus_max_mana"],
				["fury", "bonus_damage_percent"], ["ward", "armor_value"]]:
			var sid: String = "%s%samulet" % [specialist[tier], pair[0]]
			var s := _item_fields("amulets", sid)
			if s.is_empty():
				continue   # Vitality starts at tier 3
			if int(s.get(pair[1], "0")) <= int(plain.get(pair[1], "0")):
				losers.append("%s %s vs %s %s" % [sid, s.get(pair[1]), mat + "amulet", plain.get(pair[1])])
	check("each bonus family beats the plain amulet of its tier at its own stat", losers.is_empty(), losers)

	# ---- worn, with the real items (needs the art pack to load them) --------
	var body: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	body._set_stat_curve()
	body.equipped = {}
	body.level = 22
	var bare: int = body.max_hp
	body.equipped = {"chest": "emberchest", "legs": "emberlegs", "helm": "emberhelm",
		"boots": "emberboots", "shield": "embershield", "ring": "emberring",
		"amulet": "emberamulet", "weapon": "embersword"}
	body._recompute_max_stats()
	check_needs_pack("a level 22 warrior in full ember is +150 health (100 plate, 20 ring, 30 amulet)",
		body.max_hp == bare + 150, [body.max_hp, bare])
	check_needs_pack("and hits 15% harder (8 sword, 3 ring, 4 amulet)",
		body.equipped_bonus("bonus_damage_percent") == 15, body.equipped_bonus("bonus_damage_percent"))
	body.free()

	# ---- legendary is rare --------------------------------------------------
	for eid in ["darksprite", "darkfiresprite", "darkbushmage", "darkbushsniper", "darkslime"]:
		var odds := _odds_of(eid)
		check("%s: ember on 3%% of its item slots, not 15%%" % eid,
			int(_enemy_fields(eid).get("max_loot_tier", "0")) == 5 and odds.size() == 3
			and is_equal_approx(odds[0], 0.03), odds)
	for eid in ["fireboss", "boss"]:
		var odds := _odds_of(eid)
		check("%s: legendary 1 in 4, amethyst otherwise (tier 6 has no gear)" % eid,
			odds.size() == 3 and is_equal_approx(odds[0], 0.0) and is_equal_approx(odds[1], 0.25)
			and is_equal_approx(odds[2], 0.75), odds)
	for eid in ["lightboss", "windboss", "waterboss", "iceboss", "earthboss"]:
		var top: int = int(_enemy_fields(eid).get("max_loot_tier", "0"))
		var odds := _odds_of(eid)
		var ember_share := 0.0
		for i in range(odds.size()):
			if top - i >= 5:
				ember_share += odds[i]
		var amethyst_share: float = odds[top - 4] if top - 4 < odds.size() else 0.0
		check("%s: never legendary, amethyst about a third of the time" % eid,
			is_zero_approx(ember_share) and is_equal_approx(amethyst_share, 0.35), [top, odds])


# =============================================================================
# BOSSES HIT FOR THEIR BAND
# =============================================================================
# All seven bosses run bossenemy.gd, and all seven hit for its 34 / 45 / 22
# whatever their .tres said: the six elemental ones had a projectile_damage
# nothing read, and the Crowned had none. So when the normals moved into bands
# the Crowned's spike (37 after dark's profile) was softer than a dark bush
# mage's 55, and the light boss hit nearly three times its band. The spike is
# the .tres's projectile_damage now, 1.5x its band's normal hit; the swing and
# the stalker's trail keep the 45 : 34 and 22 : 34 they were tuned at.

func _test_bosses_hit_for_their_band() -> void:
	section("BOSSES HIT FOR THEIR BAND — spike, swing and trail from the boss's own data")

	var profile: Dictionary = (load("res://src/projectiles/bossprojectile.gd") as Script) \
		.get_script_constant_map().get("ELEMENT_PROFILE", {})
	var boss_src := FileAccess.get_file_as_string("res://src/enemies/bossenemy.gd")

	# ---- the data -----------------------------------------------------------
	var last_spike := 0
	var climbs := true
	for eid in _BOSS_BAND:
		var band: int = _BOSS_BAND[eid]
		var spike := int(_enemy_fields(eid).get("projectile_damage", "0"))
		check("%s: its spike is 1.5x a band-%d normal hit (%d)" % [eid, band, roundi(1.5 * _BAND_HIT[band])],
			spike == roundi(1.5 * _BAND_HIT[band]), spike)
		if spike < last_spike:
			climbs = false
		last_spike = spike
	check("and the spikes climb band by band, the Crowned's the biggest", climbs)

	# ---- the bosses themselves ----------------------------------------------
	var holder := Node2D.new()
	add_child(holder)
	var target := Node2D.new()
	holder.add_child(target)
	var container: Node = get_tree().get_first_node_in_group("groundeffects")
	if container == null:
		container = get_tree().current_scene
	var hits: Dictionary = {}
	for eid in _BOSS_BAND:
		var band: int = _BOSS_BAND[eid]
		var spike := int(_enemy_fields(eid).get("projectile_damage", "0"))
		var boss: Node = (load(_boss_scene_path(eid)) as PackedScene).instantiate()
		check("%s: spike %d, swing %d, trail %d - the shares the fight was tuned at" % [
				eid, spike, roundi(spike * 45.0 / 34.0), roundi(spike * 22.0 / 34.0)],
			boss.spike_damage() == spike
			and boss.melee_damage() == roundi(spike * 45.0 / 34.0)
			and boss.trail_damage() == roundi(spike * 22.0 / 34.0),
			[boss.spike_damage(), boss.melee_damage(), boss.trail_damage()])
		if boss.enemy_data == null:
			# What _ready() would do; the bare scene answered as the Crowned above.
			boss.enemy_data = boss.ENEMY_DATA

		# A real spike, through the one function both tracks go through.
		var p: Dictionary = profile.get(boss.current_element(), profile.get(Element.Type.NONE, {}))
		var scaled := maxi(1, int(round(spike * float(p.get("damage", 1.0)))))
		var had: Array = holder.get_children()
		boss._spawn_one_eruption(holder, Vector2.ZERO, 1.0, boss.SPIKE_BASE_RADIUS, boss.eruption_scene)
		var eruption: Node = null
		for c in holder.get_children():
			if not had.has(c):
				eruption = c
		check("  a real spike lands for %d (its element's x%s on top)" % [scaled, p.get("damage", 1.0)],
			eruption != null and int(eruption.damage) == scaled,
			eruption.damage if eruption != null else "no spike")
		check("  which is more than a band-%d normal hit and at most twice one" % band,
			eruption != null and int(eruption.damage) > int(_BAND_HIT[band])
			and int(eruption.damage) <= 2 * int(_BAND_HIT[band]),
			[eruption.damage if eruption != null else -1, _BAND_HIT[band]])
		hits[eid] = int(eruption.damage) if eruption != null else 0
		if eruption != null:
			eruption.free()

		# A real stalker, handed what _spawn_stalker() hands it, dropping a pillar.
		var stalker: Node2D = Node2D.new()
		stalker.set_script(boss.STALKER_SCRIPT)
		holder.add_child(stalker)
		stalker.setup(target, Projectiles.variant_of(boss.eruption_scene, boss.current_element()),
			boss.trail_damage(), boss.current_element())
		var before: Array = container.get_children()
		stalker._drop_pillar()
		var pillar: Node = null
		for c in container.get_children():
			if not before.has(c):
				pillar = c
		# The trail wears the BOSS's element, stamped by the stalker - there is
		# no dark pillar scene, so without the stamp the Crowned's trail was
		# plain (54, a full-strength ring) while its spikes were dark.
		var trail_scaled := maxi(1, int(round(boss.trail_damage() * float(p.get("damage", 1.0)))))
		check("  its stalker's trail drops %s pillars for %d" % [Element.name_for(boss.current_element()), trail_scaled],
			pillar != null and int(pillar.damage) == trail_scaled
			and int(pillar.element) == boss.current_element(),
			str([pillar.damage, pillar.element]) if pillar != null else "no pillar")
		if pillar != null:
			pillar.free()
		stalker.free()
		boss.free()
	holder.queue_free()
	check("the Crowned hits hardest of the seven",
		hits["boss"] == hits.values().max(), hits)

	# ---- the wiring the bosses above cannot show outside a fight -------------
	var swing_at := _first_code_index(boss_src, "func _land_swing(", 0)
	var swing_end := _first_code_index(boss_src, "\nfunc ", swing_at + 1)
	check("the swing lands for melee_damage(), not the bare melee_power",
		_within(_first_code_index(boss_src, "take_damage(melee_damage()", swing_at), swing_end) != -1
		and _within(_first_code_index(boss_src, "take_damage(melee_power", swing_at), swing_end) == -1)
	var stalk_at := _first_code_index(boss_src, "func _spawn_stalker(", 0)
	var stalk_end := _first_code_index(boss_src, "\nfunc ", stalk_at + 1)
	check("and _spawn_stalker() hands the stalker trail_damage() and the boss's element",
		_within(_first_code_index(boss_src, "trail_damage(),\n\t\tcurrent_element())", stalk_at), stalk_end) != -1)
	print("  bosses: spikes %s" % str(hits))


# =============================================================================
# SEVEN BOSSES, SEVEN FIGHTS (0.77.0) - kits, effects, whose turn it is
# =============================================================================
# The owner, 23 Oct: "bosses currently are stale do to only locking on 1 player
# ... we can add real elements and effects slow on ice etc i want to keep the
# stalagmites but each boss needs to be a challenge but also clearable".
# bossenemy.gd's THE KITS and statuseffects.gd have the design; this holds it:
# each boss its own shapes and volley, the effects capped so a fight stays
# clearable, the hazards carrying them, and every attack taking turns round the
# fight instead of locking on to one player.

func _test_the_damage_meter() -> void:
	section("DAMAGE METER - every player's damage here, as the server counts it (0.81.0)")
	var meter_script: GDScript = load("res://src/ui/owner/damagemeter.gd") as GDScript
	var counted: Dictionary = meter_script.fresh_state()
	meter_script.add_hits(counted, [[1, 100, 100, 0], [2, 50, 80, 1], [1, 30, 30, 1], "junk", [3]], 10.0)
	meter_script.add_hits(counted, [[1, 10, 10, 0]], 11.0)
	var names: Dictionary = {1: ["Ann", "mage", 5, 40, 20], 2: ["Bob", "warrior", 3, 30, 25]}
	var everyone: Array = meter_script.rows(counted, names, 11.0, 1, false, false)
	check("a row a player, biggest total first; junk in a report is passed over",
		everyone.size() == 2 and int(everyone[0]["id"]) == 1 and int(everyone[0]["total"]) == 140
		and int(everyone[1]["total"]) == 50, everyone)
	if everyone.size() == 2:
		check("  DPS over the fight: total over first report to last, plus the second the first covered",
			is_equal_approx(float(everyone[0]["dps"]), 70.0) and is_equal_approx(float(everyone[1]["dps"]), 50.0),
			[everyone[0]["dps"], everyone[1]["dps"]])
		check("  DPS over the last five seconds, the biggest hit, and what the server allows",
			is_equal_approx(float(everyone[0]["dps5"]), 28.0) and int(everyone[0]["biggest"]) == 100
			and int(everyone[0]["allowed"]) == 40 and str(everyone[0]["name"]) == "Ann")
		check("  a hit the books held down is counted as booked, and the rest shown as held",
			int(everyone[1]["held"]) == 30 and int(everyone[0]["held"]) == 0)
	var bosses: Array = meter_script.rows(counted, names, 11.0, 1, false, true)
	check("Bosses only: just the hits a boss took",
		bosses.size() == 2 and int(bosses[0]["id"]) == 2 and int(bosses[1]["total"]) == 30
		and is_equal_approx(float(bosses[1]["dps5"]), 6.0), bosses)
	var mine: Array = meter_script.rows(counted, names, 11.0, 1, true, false)
	check("Just me: only this game's own row", mine.size() == 1 and int(mine[0]["id"]) == 1, mine)
	var later: Array = meter_script.rows(counted, names, 16.5, 1, false, false)
	check("  five quiet seconds later the short window is empty and the fight's totals are kept",
		later.size() == 2 and is_equal_approx(float(later[0]["dps5"]), 0.0) and int(later[0]["total"]) == 140)
	meter_script.add_hits(counted, [[3, 1, 1, 0]], 17.0)
	var stranger: Array = meter_script.rows(counted, names, 17.0, 1, false, false)
	check("  a dealer the server never named is still a row", stranger.any(func(r: Dictionary) -> bool:
		return str(r["name"]) == "player 3"), stranger)
	var fight: Dictionary = meter_script.summary(counted, false)
	check("the fight line: its length, everyone's total and the group's DPS",
		is_equal_approx(float(fight["seconds"]), 8.0) and int(fight["total"]) == 191
		and is_equal_approx(float(fight["dps"]), 191.0 / 8.0) and meter_script.clock(75.0) == "1:15", fight)
	check("  bosses only counts only what bosses took, and an empty fight is zero",
		int(meter_script.summary(counted, true)["total"]) == 80
		and int(meter_script.summary(meter_script.fresh_state(), false)["total"]) == 0)
	check("Limit: the fight's DPS against what the server allows, unknown when it said nothing",
		is_equal_approx(meter_script.limit_share({"dps": 30.0, "allowed": 40}), 0.75)
		and meter_script.limit_share({"dps": 30.0, "allowed": 0}) < 0.0)
	var copied: String = meter_script.as_text(stranger, meter_script.summary(counted, false), "bigfield")
	check("Copy: a line a player under a header, held hits named",
		copied.begins_with("Damage meter - bigfield - fight 0:08") and copied.contains("Ann (mage 5)\t")
		and copied.contains("held 30") and copied.split("\n").size() == 2 + stranger.size(), copied)
	check("numbers short enough for a column",
		meter_script.number(999.0) == "999" and meter_script.number(1234.0) == "1.23k"
		and meter_script.number(12345.0) == "12.3k" and meter_script.number(1234567.0) == "1.2M")

	var kept: Dictionary = {"send": Presence.send_override, "phase": Presence._phase,
		"watching": Presence._watching_damage}
	var sent: Array = []
	Presence.send_override = func(message: Dictionary) -> void: sent.append(message)
	Presence._phase = "open"
	Presence.watch_damage(true)
	Presence._phase = "off"
	Presence.watch_damage(false)
	Presence._watching_damage = true
	Presence.handle_message({"t": "welcome", "id": Presence._my_id, "v": int(Presence._server_shares) * 99,
		"books": Presence._server_books, "x": int(Presence._server_relays)})
	check("Presence asks for the reports, remembers the ask, and asks again on every welcome",
		sent == [{"t": "dm", "on": true}, {"t": "dm", "on": true}], sent)
	var heard: Array = []
	var ear: Callable = func(report: Dictionary) -> void: heard.append(report)
	Presence.damage_meter.connect(ear)
	Presence.handle_message({"t": "dm", "a": "field", "h": [], "who": {}})
	Presence.damage_meter.disconnect(ear)
	check("  and hands each report to the meter (damage_meter)", heard.size() == 1 and str(heard[0]["a"]) == "field")
	Presence.send_override = kept["send"]
	Presence._phase = kept["phase"]
	Presence._watching_damage = kept["watching"]

	var meter: CanvasLayer = meter_script.new() as CanvasLayer
	# Never the owner's own fight log (0.82.0): a test's fight goes nowhere.
	meter.set("log_path", "user://test_fightlog/meter.json")
	meter.set("csv_folder", "user://test_fightlog")
	add_child(meter)
	meter.call("take_report", {"a": "bigfield", "h": [[Presence.my_id(), 12, 12, 0], [77, 8, 9, 1]],
		"who": {"77": ["Cy", "tank", 9, 15, 6]}}, 5.0)
	var grid: GridContainer = meter.get_node_or_null("panel").find_child("rows", true, false) as GridContainer
	var columns: int = meter_script.COLUMNS.size()
	check("the window draws a header and a row a dealer, biggest first, named by the server",
		grid != null and grid.get_child_count() == columns * 3
		and (grid.get_child(columns * 2) as Label).text.begins_with("Cy (tank 9)"))
	check("  its status says whether the server is counting",
		str(meter.call("status_text", 5.5)) == ("Live - bigfield, counted by the server." if Presence.books()
			else "The server is not counting hits right now."))
	await get_tree().process_frame
	check("  each row has its bar, as long as its share of the top total, in its class's colour",
		(meter.get("_bars") as Array).size() == 2 and is_equal_approx(float(meter.get("_bars")[1][1]), 8.0 / 12.0)
		and meter.get("_bars")[1][2] == meter_script.CLASS_COLOURS["tank"])
	var panel_box: StyleBoxFlat = (meter.get_node("panel") as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	check("  the window is solid, so nothing behind it shows through the numbers",
		panel_box != null and panel_box.bg_color.a >= 0.95)
	meter.set("fight", {})
	meter.call("reset")
	check("  Reset starts a fresh fight", (meter.get("state")["all"] as Dictionary).is_empty())
	meter.queue_free()

	var was_owner: bool = Api.is_owner
	var was_role: String = Api.role
	Api.is_owner = true
	Api.role = "owner"
	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var perf: Node = gm.get("perf_button")
	var switch: CheckButton = gm.get("meter_button") as CheckButton
	check("the GM panel's Testing tab has a Damage meter switch, under Performance",
		perf != null and switch != null and switch.get_parent() == perf.get_parent()
		and switch.get_index() == perf.get_index() + 1 and switch.text == "Damage meter")
	gm.queue_free()
	Api.is_owner = was_owner
	Api.role = was_role


func _test_the_fight_log() -> void:
	section("FIGHT LOG - every fight the meter hears, kept, timed and compared (0.82.0)")
	var log_script: GDScript = load("res://src/ui/owner/fightlog.gd") as GDScript
	var who: Dictionary = {"1": ["Ann", "mage", 5, 40, 20], "2": ["Bob", "warrior", 3, 30, 25]}
	var first: Dictionary = {"a": "bigfield", "h": [[1, 100, 100, 0, 5], [2, 40, 60, 1, 9]], "who": who,
		"m": {"5": ["slime", "Slime", 90], "9": ["fireboss", "Fire Boss", 50000]}, "k": []}
	var second: Dictionary = {"a": "bigfield", "h": [[1, 50, 50, 1, 9]], "who": {}, "m": {}, "k": [[5, 0]]}
	var third: Dictionary = {"a": "bigfield", "h": [[2, 30, 30, 1, 9]], "who": {},
		"m": {"9": ["fireboss", "Fire Boss", 60000]}, "k": [[9, 1], [404, 0]]}
	var fight: Dictionary = log_script.begin(100.0, 1793000000.0, "bigfield")
	log_script.add(fight, first, 100.0)
	log_script.add(fight, second, 101.0)
	log_script.add(fight, third, 104.0)
	check("a fight ends after QUIET_SECONDS (%d) with no hit, not before" % int(log_script.QUIET_SECONDS),
		not log_script.quiet(fight, 113.9) and log_script.quiet(fight, 114.0) and not log_script.quiet({}, 999.0))
	var record: Dictionary = log_script.finish(fight)
	check("the record: its length, everyone's total, the group's DPS and its best five seconds",
		int(record.get("seconds", 0)) == 5 and int(record.get("total", 0)) == 220
		and is_equal_approx(float(record.get("dps", 0.0)), 44.0) and is_equal_approx(float(record.get("peak", 0.0)), 44.0),
		record)
	var players: Array = record.get("players", [])
	check("  a row a player, biggest first: total, DPS, best 5 s, hits, average and biggest hit, held, limit",
		players.size() == 2 and str(players[0]["name"]) == "Ann" and int(players[0]["total"]) == 150
		and is_equal_approx(float(players[0]["dps"]), 30.0) and is_equal_approx(float(players[0]["peak"]), 30.0)
		and int(players[0]["hits"]) == 2 and is_equal_approx(float(players[0]["avg"]), 75.0)
		and int(players[0]["biggest"]) == 100 and is_equal_approx(float(players[0]["limit"]), 0.75)
		and int(players[1]["held"]) == 20, players)
	var kills: Array = record.get("kills", [])
	check("  every kill timed from its first hit to its death, bosses first, at the health it died with",
		kills.size() == 2 and str(kills[0]["name"]) == "Fire Boss" and bool(kills[0]["boss"])
		and is_equal_approx(float(kills[0]["seconds"]), 5.0) and int(kills[0]["max_hp"]) == 60000
		and int(kills[0]["damage"]) == 120 and str(kills[1]["name"]) == "Slime"
		and is_equal_approx(float(kills[1]["seconds"]), 2.0), kills)
	check("  and a second-by-second line a player", record.get("timeline", {}).get("1", []) == [100, 50, 0, 0, 0]
		and record.get("timeline", {}).get("2", []) == [40, 0, 0, 0, 30], record.get("timeline"))
	check("a fight nobody hit in is not kept", log_script.finish(log_script.begin(0.0, 0.0, "x")).is_empty())
	check("the best five seconds of a line", is_equal_approx(log_script.peak([10, 0, 0, 0, 0, 50]), 10.0)
		and is_equal_approx(log_script.peak([5]), 1.0))
	check("its one line in the list names the boss and how long it took",
		log_script.headline(record).contains("bigfield") and log_script.headline(record).ends_with("Fire Boss 0:05"),
		log_script.headline(record))
	var table: Array = log_script.compare_rows([record, record])
	var by_label: Dictionary = {}
	for row in table:
		by_label[str(row[0])] = row
	check("side by side: a row a number, a column a fight",
		table.size() == log_script.COMPARE_LABELS.size() and (table[0] as Array).size() == 3
		and by_label["Boss kill"][1] == "0:05" and by_label["Boss"][1] == "Fire Boss" and by_label["Boss health"][1] == "60.0k"
		and by_label["Players"][2] == "2" and by_label["Held"][1] == "20", by_label)
	var slow: Dictionary = record.duplicate(true)
	slow["id"] = 1792990000000
	slow["dps"] = 22.0
	(slow["kills"][0] as Dictionary)["seconds"] = 10.0
	var cells: Array = log_script.compare_cells([slow, record])
	var by_row: Dictionary = {}
	for row in cells:
		by_row[str(row[0])] = row[1]
	check("compared: each number after the first says how far it moved, and which way is better",
		by_row["Group DPS"][1]["delta"] == "+100%" and int(by_row["Group DPS"][1]["trend"]) == 1
		and by_row["Boss kill"][1]["delta"] == "-50%" and int(by_row["Boss kill"][1]["trend"]) == 1
		and by_row["Group DPS"][0]["delta"] == "" and by_row["Players"][1]["delta"] == "", by_row)
	check("  the best of a row is marked, and a tie marks none",
		bool(by_row["Group DPS"][1]["best"]) and not bool(by_row["Group DPS"][0]["best"])
		and not bool(by_row["Held"][0]["best"]) and not bool(by_row["Held"][1]["best"]))
	check("  a kill remembers when in the fight it fell, for the chart's marker",
		is_equal_approx(float(record["kills"][0]["at"]), 4.0) and is_equal_approx(float(record["kills"][1]["at"]), 1.0))
	check("Uptime: the share of a player's own time it dealt damage; Steadiness: how evenly",
		is_equal_approx(log_script.uptime_of([0, 5, 0, 5, 5, 0]), 0.75) and is_equal_approx(log_script.uptime_of([0, 0]), 0.0)
		and is_equal_approx(log_script.steadiness_of([10, 10, 10]), 1.0)
		and is_equal_approx(log_script.steadiness_of([10, 0, 30]), 1.0 / 1.5)
		and is_equal_approx(float(players[0]["uptime"]), 1.0) and is_equal_approx(float(players[1]["uptime"]), 0.4)
		and is_equal_approx(float(record["uptime"]), 0.7), [players[0].get("uptime"), players[1].get("uptime")])
	var mixed: Dictionary = log_script.begin(0.0, 1793000500.0, "field")
	log_script.add(mixed, {"a": "field", "h": [[1, 10, 10, 0, 5, Element.Type.FIRE], [1, 30, 30, 0, 5, Element.Type.ICE]],
		"who": who, "m": {"5": ["slime", "Slime", 90]},
		"e": [["joined", 1, "Ann"], ["grew", 5, [90, 200]], ["danced", 1, "Ann"], ["fell", 2, ""]]}, 3.0)
	var mixed_record: Dictionary = log_script.finish(mixed)
	check("damage by element, biggest first, as the server said each hit was",
		mixed_record["players"][0]["elements"] == [[Element.Type.ICE, 30], [Element.Type.FIRE, 10]]
		and log_script.elements_text(mixed_record["players"][0]["elements"], 40) == "ice 75% fire 25%",
		mixed_record["players"][0]["elements"])
	check("what changed the fight, when and in words - and nothing the server does not name",
		mixed_record["events"].map(func(e: Dictionary) -> String: return str(e["text"]))
			== ["Ann joined", "Slime grew to 200", "A player fell"]
		and is_equal_approx(float(mixed_record["events"][0]["at"]), 3.0), mixed_record["events"])
	var sheet: String = log_script.csv(record)
	check("a spreadsheet: summary, players, kills, then the damage each player did each second",
		sheet.contains("Player,Class,Level,Total") and sheet.contains("Ann,mage,5,150,30,30,2,75,100,0,40,75%,100%,")
		and sheet.contains("Fire Boss,yes,60000,120,5") and sheet.contains("Second,Ann,Bob\n0,100,40\n")
		and sheet.ends_with("4,0,30\n"), sheet)
	check("  a name with a comma is quoted", log_script._cell("Ann, the first") == "\"Ann, the first\"")
	var path: String = "user://test_fightlog/log.json"
	check("kept between runs: saved and read back the same",
		log_script.save_log([record], path) and int(log_script.load_log(path)[0]["id"]) == 1793000000000
		and int(log_script.load_log(path)[0]["kills"].size()) == 2)
	check("  a missing or broken file reads as no fights", log_script.load_log("user://test_fightlog/none.json").is_empty())
	check("  a spreadsheet named by when and where",
		log_script.csv_path(record, "user://x").begins_with("user://x/fight_2026") and log_script.csv_path(record, "user://x").ends_with("_bigfield.csv"))

	var meter_script: GDScript = load("res://src/ui/owner/damagemeter.gd") as GDScript
	var meter: CanvasLayer = meter_script.new() as CanvasLayer
	meter.set("log_path", path)
	meter.set("csv_folder", "user://test_fightlog")
	meter.set("fights", [])
	meter.set("picked", [])
	add_child(meter)
	meter.call("take_report", first, 100.0)
	meter.call("take_report", second, 101.0)
	check("the meter starts a fight with the first hit it hears", not (meter.get("fight") as Dictionary).is_empty())
	meter.call("take_report", {"a": "bigfield", "h": [[1, 7, 7, 0, 5]], "who": {}, "m": {}, "k": []}, 130.0)
	check("  and a hit after a quiet spell keeps the last fight and starts the next",
		(meter.get("fights") as Array).size() == 1 and int((meter.get("fights")[0] as Dictionary)["total"]) == 190
		and float((meter.get("fight") as Dictionary)["t0"]) == 130.0)
	var shut: Dictionary = meter.call("close_fight")
	check("  closing keeps it too, newest first, and picks it to compare - its id its own, even in the same second",
		(meter.get("fights") as Array).size() == 2 and int(shut.get("total", 0)) == 7
		and int(meter.get("fights")[0]["id"]) != int(meter.get("fights")[1]["id"])
		and (meter.get("picked") as Array).size() == 2 and log_script.load_log(path).size() == 2)
	meter.call("show_page", "fights")
	var list: Control = meter.find_child("list", true, false) as Control
	var compare: GridContainer = meter.find_child("compare", true, false) as GridContainer
	var chart: Control = meter.find_child("groupchart", true, false) as Control
	meter.call("show_view", "list")
	var chart_page: Control = chart.get_parent() as Control
	var table_page: Control = compare.get_parent() as Control
	check("the Fights page shows one view at a time: List is a line a fight",
		list != null and list.visible and list.get_child_count() == 2 and not chart_page.visible
		and not table_page.visible)
	meter.call("show_view", "chart")
	check("  Chart: one chart, a line a picked fight, the group's DPS through it",
		chart_page.visible and not list.visible and not table_page.visible and (chart.get("lines") as Array).size() == 2
		and (chart.get("lines")[0] as Array).size() == int((meter.get("fights")[1] as Dictionary)["seconds"]))
	meter.call("show_view", "table")
	var key_cells: int = compare.get_child_count()
	check("  Table: the picked side by side, the key rows until More",
		table_page.visible and not chart_page.visible and compare.columns == 3
		and key_cells == 3 * (1 + meter_script.KEY_ROWS.size()))
	meter.call("_on_more")
	check("  and every row after it", compare.get_child_count() == 3 * log_script.COMPARE_LABELS.size())
	meter.call("show_view", "players")
	var grid: GridContainer = meter.find_child("playergrid", true, false) as GridContainer
	check("  Players: the newest picked fight a row a player - DPS, best 5 s, uptime, steadiness, elements",
		(grid.get_parent() as Control).visible and grid.get_child_count() == 2 * meter_script.PLAYER_COLUMNS.size()
		and (meter.find_child("slots", true, false) as Node).get_child_count() == 2)
	meter.call("show_view", "chart")
	meter.call("_on_events_toggled", true)
	check("  Events on the chart: marked, and listed - or said there were none",
		bool(chart.get("show_events")) and (meter.find_child("eventlist", true, false) as Node).get_child_count() == 1)
	meter.call("_on_events_toggled", false)
	meter.call("focus", 2, "Bob")
	var group_button: Button = meter.find_child("group", true, false) as Button
	var title: Label = meter.find_child("title", true, false) as Label
	check("ONE PLAYER ON THE CHART: a name clicked shows only their damage, across the picked fights",
		str(meter.get("fights_view")) == "chart" and title.text == "Damage meter: Bob" and group_button.visible
		and chart.get("lines")[0] == log_script.player_line(meter.get("fights")[1], 2)
		and (chart.get("lines")[1] as Array).is_empty(), [title.text, chart.get("lines")])
	check("  the legend says when they were not in a fight",
		((meter.find_child("legend", true, false) as Node).get_child(1).get_child(1) as Label).text.ends_with("not in this fight"))
	group_button.pressed.emit()
	check("  and Group brings the whole group back, the title with it",
		title.text == "Damage meter" and not group_button.visible
		and chart.get("lines")[0] == log_script.group_line(meter.get("fights")[1]))
	check("a player's own line, and their row, from a saved fight",
		log_script.player_line(record, 1, 1) == [100.0, 50.0, 0.0, 0.0, 0.0] and log_script.player_line(record, 9).is_empty()
		and str(log_script.player_in(record, 2).get("name", "")) == "Bob" and log_script.player_in(record, 9).is_empty())
	meter.call("show_page", "now")
	var smooth: Array = log_script.group_line({"seconds": 3, "timeline": {"1": [10, 20, 30], "2": [0, 0, 30]}}, 2)
	check("the group's line: everyone's damage each second, averaged over the seconds before",
		smooth.size() == 3 and is_equal_approx(float(smooth[0]), 10.0) and is_equal_approx(float(smooth[1]), 15.0)
		and is_equal_approx(float(smooth[2]), 40.0), smooth)
	meter.queue_free()
	var left: DirAccess = DirAccess.open("user://test_fightlog")
	if left != null:
		for file in left.get_files():
			left.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_fightlog"))

func _test_damage_taken() -> void:
	section("ENEMY METER, PHASE 1 - damage TAKEN: counted where health moves, sent as totals, kept in the fight log (0.83.0)")
	var player_src: String = (load("res://src/characters/player.gd") as GDScript).source_code
	var hit: String = _func_body(player_src, "func take_damage(")
	check("a hit is counted after armour and resistance, once the health has moved - and god mode, returning first, counts nothing",
		hit.find("Presence.note_taken(reduced_amount, element") > hit.find("hp = clamp(hp - reduced_amount")
		and hit.find("hp = clamp(hp - reduced_amount") > 0
		and hit.find("GameState.god_mode") < hit.find("Presence.note_taken"))
	check("  a heal counts only what it gave back; regen is its own total",
		_func_body(player_src, "func heal(").contains("Presence.note_healed(actual_heal)")
		and _func_body(player_src, "func _tick_regen(").contains("Presence.note_regen(hp - before)"))
	var kept: Dictionary = {"send": Presence.send_override, "last": Presence._last_state, "taken": Presence.meter_taken,
		"healed": Presence.meter_healed, "regen": Presence.meter_regen, "big": Presence.meter_biggest,
		"els": Presence.meter_by_element, "sent_els": Presence._sent_by_element, "attacks": Presence._attacks,
		"sync": Presence._sync_pending}
	var sent: Array = []
	Presence.send_override = func(message: Dictionary) -> void: sent.append(message)
	Presence._attacks = []
	Presence._sync_pending = false
	Presence.meter_taken = 100
	Presence.meter_healed = 0
	Presence.meter_regen = 0
	Presence.meter_biggest = 0
	Presence.meter_by_element = {}
	Presence._sent_by_element = {}
	Presence._last_state = {}
	var body := Node2D.new()
	body.set_script(_stand_in_with_health())
	body.set("max_hp", 400)
	body.set("hp", 358)
	Presence.note_taken(30, Element.Type.FIRE)
	Presence.note_taken(12, Element.Type.NONE)
	Presence.note_taken(-5, Element.Type.FIRE)
	Presence.note_healed(0)
	Presence.send_tick(body)
	var first: Dictionary = sent[0] if sent.size() == 1 else {}
	check("the state carries the totals, the biggest hit since the last, by element, and real health",
		int(first.get("dt", -1)) == 142 and int(first.get("dh", -1)) == 0 and int(first.get("dr", -1)) == 0
		and int(first.get("dx", -1)) == 30 and first.get("dte", {}) == {Element.Type.FIRE: 30, Element.Type.NONE: 12}
		and int(first.get("hpa", -1)) == 358 and int(first.get("hpm", -1)) == 400, first)
	Presence.send_tick(body)
	check("  nothing new, nothing sent: the biggest hit and the elements go once", sent.size() == 1, sent)
	Presence.note_regen(3)
	Presence.note_healed(20)
	body.set("hp", 381)
	Presence.send_tick(body)
	var second: Dictionary = sent[1] if sent.size() == 2 else {}
	check("  a heal and regen: their totals, no biggest hit, no elements",
		int(second.get("dh", -1)) == 20 and int(second.get("dr", -1)) == 3 and not second.has("dx")
		and not second.has("dte") and int(second.get("hpa", -1)) == 381, second)
	Presence.meter_taken = Presence.METER_TOTAL_MOST - 1
	Presence.note_taken(5, Element.Type.NONE)
	check("  a total past METER_TOTAL_MOST starts again (the server takes it as a new baseline)",
		Presence.meter_taken == 5)
	body.free()
	Presence.send_override = kept["send"]
	Presence._last_state = kept["last"]
	Presence.meter_taken = kept["taken"]
	Presence.meter_healed = kept["healed"]
	Presence.meter_regen = kept["regen"]
	Presence.meter_biggest = kept["big"]
	Presence.meter_by_element = kept["els"]
	Presence._sent_by_element = kept["sent_els"]
	Presence._attacks = kept["attacks"]
	Presence._sync_pending = kept["sync"]

	var log_script: GDScript = load("res://src/ui/owner/fightlog.gd") as GDScript
	var who: Dictionary = {"1": ["Ann", "mage", 5, 40, 20], "2": ["Tom", "tank", 9, 30, 25]}
	var fight: Dictionary = log_script.begin(100.0, 1793001000.0, "bigfield")
	log_script.add(fight, {"a": "bigfield", "h": [[1, 50, 50, 0, 5]], "who": who, "m": {"5": ["slime", "Slime", 90]},
		"tk": {"1": [0, 0, 1, 0, 100, 100, {}], "2": [80, 0, 0, 50, 220, 400, {"6": 80}], "3": [0, 0, 5, 0, 10, 10, {}]}}, 100.0)
	log_script.add(fight, {"a": "bigfield", "h": [], "who": {}, "m": {},
		"tk": {"2": [60, 40, 2, 60, 80, 400, {"6": 20, "0": 40}]}, "e": [["fell", 2, "Tom"]]}, 101.0)
	log_script.add(fight, {"a": "bigfield", "h": [], "who": {}, "m": {},
		"tk": {"2": [0, 0, 0, 0, 380, 400, {}]}}, 103.0)
	var record: Dictionary = log_script.finish(fight)
	var tom: Dictionary = log_script.player_in(record, 2)
	check("a player hit but never hitting is in the fight: named, and the fight runs to their last hit",
		str(tom.get("name", "")) == "Tom" and int(tom.get("total", -1)) == 0 and int(record.get("seconds", 0)) == 2
		and log_script.player_in(record, 3).is_empty(), [tom, record.get("seconds")])
	check("  taken, a second, biggest, healed, regen, lowest health, danger seconds, deaths, by element",
		int(tom.get("taken", 0)) == 140 and is_equal_approx(float(tom.get("taken_ps", 0.0)), 70.0)
		and int(tom.get("biggest_taken", 0)) == 60 and int(tom.get("healed", 0)) == 40 and int(tom.get("regen", 0)) == 2
		and is_equal_approx(float(tom.get("lowest", -1.0)), 0.2) and int(tom.get("danger", -1)) == 1
		and int(tom.get("deaths", 0)) == 1 and tom.get("took", []) == [[6, 100], [0, 40]], tom)
	check("  a second-by-second line of each: taken, given back, health",
		record["taken_timeline"]["2"] == [80, 60] and record["heal_timeline"]["2"] == [0, 42]
		and record["health_timeline"]["2"] == [0.55, 0.2] and record["health_timeline"]["1"] == [1.0, 1.0], record["health_timeline"])
	check("health carried over the seconds nothing was heard, and back to the start; none heard, none drawn",
		log_script.health_line({2: 0.5, 4: 0.3}, 6) == [0.5, 0.5, 0.5, 0.5, 0.3, 0.3] and log_script.health_line({}, 3).is_empty())
	check("  smoothed for the chart: one player's taken and healing, or the whole group's taken",
		log_script.taken_line(record, 2, 1) == [80.0, 60.0] and log_script.heal_line(record, 2, 1) == [0.0, 42.0]
		and log_script.taken_line(record, -1, 2) == [80.0, 70.0] and log_script.taken_line({"seconds": 3}, 2).is_empty())
	var sheet: String = log_script.csv(record)
	check("the spreadsheet gains the columns and each second's taken, healed and health",
		sheet.contains(",Taken,Taken a second,Biggest taken,Healed,Regen,Lowest health,Danger seconds,Deaths,Took by element")
		and sheet.contains(",140,70,60,40,2,20%,1,1,") and sheet.contains("Second,Ann taken,Ann healed,Ann health,Tom taken")
		and sheet.ends_with("1,0,0,100%,60,42,20%\n"), sheet)
	check("  and Copy says it too", log_script.compare_text([record]).contains("\tTaken\tTaken/s\t"))

	var meter_script: GDScript = load("res://src/ui/owner/damagemeter.gd") as GDScript
	var meter: CanvasLayer = meter_script.new() as CanvasLayer
	var path: String = "user://test_fightlog_taken/log.json"
	meter.set("log_path", path)
	meter.set("csv_folder", "user://test_fightlog_taken")
	meter.set("fights", [])
	meter.set("picked", [])
	add_child(meter)
	meter.call("take_report", {"a": "bigfield", "h": [], "who": who, "tk": {"2": [0, 30, 4, 0, 300, 400, {}]}}, 50.0)
	check("on the meter, a heal alone starts no fight", (meter.get("fight") as Dictionary).is_empty())
	meter.call("take_report", {"a": "bigfield", "h": [], "who": who, "tk": {"2": [25, 0, 0, 25, 275, 400, {"6": 25}]}}, 51.0)
	check("  being hit does", not (meter.get("fight") as Dictionary).is_empty())
	meter.call("close_fight")
	meter.set("fights", [record] + (meter.get("fights") as Array))
	meter.set("picked", [int(record["id"])])
	meter.call("show_page", "fights")
	meter.call("show_view", "chart")
	var chart: Control = meter.find_child("groupchart", true, false) as Control
	meter.call("_on_taken_toggled", true)
	check("Taken on the chart: the group's taken alone, no healing and no health strip",
		bool(chart.get("show_taken")) and chart.get("taken_lines")[0] == log_script.taken_line(record, -1)
		and (chart.get("heal_lines")[0] as Array).is_empty() and int(chart.call("strip_height")) == 0)
	meter.call("focus", 2, "Tom")
	check("  one player: their taken, their healing, and their health under the chart",
		chart.get("taken_lines")[0] == log_script.taken_line(record, 2) and chart.get("heal_lines")[0] == log_script.heal_line(record, 2)
		and chart.get("health_lines")[0] == [0.55, 0.2] and int(chart.call("strip_height")) > 0
		and chart.custom_minimum_size.y > 150)
	meter.call("show_view", "players")
	var grid: GridContainer = meter.find_child("playergrid", true, false) as GridContainer
	var taken_grid: GridContainer = meter.find_child("takengrid", true, false) as GridContainer
	check("Players gains a second table: Taken/s, Biggest, Healed, Regen, Lowest, Danger, Deaths and Took",
		meter_script.TAKEN_COLUMNS == ["Player", "Taken/s", "Biggest", "Healed", "Regen", "Lowest", "Danger", "Deaths", "Took"]
		and meter_script.TAKEN_COLUMNS.size() == meter_script.TAKEN_TIPS.size()
		and meter_script.PLAYER_COLUMNS.size() == meter_script.PLAYER_TIPS.size()
		and grid.get_child_count() == 3 * meter_script.PLAYER_COLUMNS.size()
		and taken_grid != null and taken_grid.get_child_count() == 3 * meter_script.TAKEN_COLUMNS.size())
	meter.queue_free()
	var left: DirAccess = DirAccess.open("user://test_fightlog_taken")
	if left != null:
		for file in left.get_files():
			left.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_fightlog_taken"))


func _test_monsters_fire_their_element() -> void:
	section("ELEMENT KITS - in the Field a monster's orbs move like its element (0.84.0)")
	var Kit := preload("res://src/enemies/elementkit.gd")
	check("each land has its kit; lightning, poison and physical have none",
		Kit.kind_for(Element.Type.LIGHT) == &"prism" and Kit.kind_for(Element.Type.WIND) == &"gale"
		and Kit.kind_for(Element.Type.WATER) == &"tide" and Kit.kind_for(Element.Type.ICE) == &"frost"
		and Kit.kind_for(Element.Type.EARTH) == &"boulder" and Kit.kind_for(Element.Type.FIRE) == &"pincer"
		and Kit.kind_for(Element.Type.DARK) == &"dark" and Kit.kind_for(Element.Type.LIGHTNING) == &""
		and Kit.kind_for(Element.Type.POISON) == &"" and Kit.kind_for(Element.Type.NONE) == &"")
	check("  a leader's volley name is the mark and a roll; none for no kit, or a kit that is the family's own",
		Kit.volley_for(Element.Type.ICE).begins_with("kit:") and Kit.volley_for(Element.Type.POISON) == ""
		and Kit.volley_for(Element.Type.FIRE, &"pincer") == "" and Kit.volley_for(Element.Type.DARK, &"pincer") != "")
	check("  the roll read back, and junk read as 0, never as a kit it is not",
		Kit.roll_of("kit:17") == 17 and Kit.roll_of("kit:-5") == 5 and Kit.roll_of("kit:x") == 0
		and Kit.is_kit("kit:3") and not Kit.is_kit("mortar") and not Kit.is_kit(""))
	var kinds: Dictionary = {}
	var door_ok: bool = true
	for roll in Kit.ROLL_MOST:
		kinds[Kit.kind_of(Element.Type.DARK, roll)] = true
		var door: int = Kit.tide_door(roll)
		var middle: int = Kit.TIDE_ORBS >> 1
		if door < 0 or door + Kit.TIDE_DOOR > Kit.TIDE_ORBS or (middle >= door and middle < door + Kit.TIDE_DOOR):
			door_ok = false
	check("a dark monster's roll reaches all six kits", kinds.size() == 6, kinds.keys())
	check("  the tide's door is always in the wall and never on the middle, where the shot flies", door_ok)

	var arena := Node2D.new()
	arena.position = Vector2(-80000, -80000)
	add_child(arena)
	var cases: Array = [["lightbushsniper", "kit:1", 7, 14], ["windfiresprite", "kit:2", 4, 8],
		["waterslimelarge", "kit:3", Kit.TIDE_ORBS - Kit.TIDE_DOOR, Kit.TIDE_ORBS - Kit.TIDE_DOOR],
		["icesprite", "kit:4", Kit.FROST_ORBS, Kit.FROST_ORBS], ["earthsprite", "kit:5", 0, 1 + Kit.BOULDER_ROCKS],
		["darkbushmage", "kit:0", Kit.PRISM_ORBS, Kit.PRISM_ORBS * 2]]
	var monsters: Array = []
	var zones: Array = []
	for c in cases:
		var monster: Node = (load("res://scene/enemy/%s.tscn" % c[0]) as PackedScene).instantiate()
		monster.process_mode = Node.PROCESS_MODE_DISABLED
		arena.add_child(monster)
		monster.process_mode = Node.PROCESS_MODE_ALWAYS
		monster.set_physics_process(false)
		monster.set_process(false)
		var zone := BulletZone.new()
		arena.add_child(zone)
		zone.set_process(false)
		monsters.append(monster)
		zones.append(zone)
		monster.fire_volley(zone, arena.global_position, 0.0, str(c[1]), 120.0)
	var first: Array = []
	for z in zones:
		first.append((z as BulletZone).field.count)
	await get_tree().create_timer(1.2).timeout
	var later: Array = []
	for z in zones:
		later.append((z as BulletZone).field.count)
	var want_first: Array = cases.map(func(c: Array) -> int: return int(c[2]))
	var want_later: Array = cases.map(func(c: Array) -> int: return int(c[3]))
	check("light's prism, wind's gale, water's tide with its door, ice's frost, earth's boulder (nothing until it lands), dark's roll - as they leave",
		first == want_first, [first, want_first])
	check("  and on the beat: a second prism, a second gale fan, the boulder's impact and its crater",
		later == want_later, [later, want_later])
	var sniper: Node = monsters[0]
	var orb_damage: int = int((zones[0] as BulletZone).field._damage[0]) if (zones[0] as BulletZone).field.count > 0 else -1
	check("an orb keeps its family's share of the shot, so a band hits as hard as it did",
		orb_damage == int(sniper.orb_damage()), [orb_damage, sniper.orb_damage()])
	var small: Node = (load("res://scene/enemy/waterslime.tscn") as PackedScene).instantiate()
	small.set("is_small", true)
	small.process_mode = Node.PROCESS_MODE_DISABLED
	arena.add_child(small)
	var small_zone := BulletZone.new()
	arena.add_child(small_zone)
	small_zone.set_process(false)
	small.fire_volley(small_zone, arena.global_position, 0.0, "kit:3", 120.0)
	check("  a small slime keeps its twin: a kit name fires nothing from it", small_zone.field.count == 0)
	var plain: Node = (load("res://scene/enemy/firesprite.tscn") as PackedScene).instantiate()
	check("  the plain fire sprite's pincer IS fire's kit, so it sends none",
		plain.call("kit_volley", &"pincer") == "")
	plain.free()
	var sent: bool = true
	for script_path in ["bushsniper", "firesprite", "electricsprite", "poisonslime"]:
		var body: String = _func_body(FileAccess.get_file_as_string("res://src/enemies/%s.gd" % script_path),
			"func fire_projectile(")
		if not (body.contains("kit_volley(") and body.contains("leader_bullets(self,")):
			sent = false
	var mage_body: String = _func_body(FileAccess.get_file_as_string("res://src/enemies/bushmage.gd"), "func _spawn_vine(")
	check("every family's leader picks the kit and sends it to the other games (monstersync.gd \"b\")",
		sent and mage_body.contains("kit_volley(") and mage_body.contains("leader_bullets(self, global_position, aim, kit, reach)"))
	check("  and the name fits what a \"b\" may carry", ("kit:%d" % (Kit.ROLL_MOST - 1)).length() <= 16)
	for n in get_tree().get_nodes_in_group(&"enemy_projectiles"):
		if is_instance_valid(n) and n.get_parent() == get_tree().current_scene:
			n.queue_free()
	arena.queue_free()
	await get_tree().process_frame
	print("  element kits checked")


func _test_what_hit_me() -> void:
	section("WHAT HIT ME - every hit on a player says which monster and which attack (0.85.0)")
	var HS := preload("res://src/shared/hitsource.gd")
	var Kit := preload("res://src/enemies/elementkit.gd")
	var sprite: Node = (load("res://scene/enemy/icesprite.tscn") as PackedScene).instantiate()
	var arrow: Node = (load("res://scene/projectiles/icearrow.tscn") as PackedScene).instantiate() \
		if ResourceLoader.exists("res://scene/projectiles/icearrow.tscn") else null
	check("a source is '<monster>:<attack>': the monster's profile, the attack's kind",
		HS.of(sprite, "frost") == "icesprite:frost" and HS.clean("Ice Sprite!", "x") == "icesprite"
		and HS.clean("", "hit") == "hit", HS.of(sprite, "frost"))
	check("  a shot is named by its scene, the element word off the front",
		arrow == null or HS.shot_kind(arrow) == "arrow", HS.shot_kind(arrow) if arrow != null else "")
	HS.tag(arrow, sprite)
	check("  and a tagged shot carries it", arrow == null or str(arrow.get_meta(HS.HIT_META)) == "icesprite:arrow")
	HS.blame_node(arrow, "arrow")
	var first: String = HS.take()
	check("the hit takes the blame once: the next with none is unknown",
		(arrow == null or first == "icesprite:arrow") and HS.take() == HS.UNKNOWN, first)
	HS.stamp_for(sprite, "frost")
	var frost: int = HS.stamp
	var stamped: Callable = HS.later(func() -> void: HS.blame(HS.name_of(HS.stamp)))
	HS.stamp_for(sprite, "other")
	stamped.call()
	check("  an orb on a later beat keeps the stamp of the volley it belongs to",
		HS.take() == "icesprite:frost" and HS.name_of(HS.stamp) == "icesprite:other")
	var field := BulletField.new()
	add_child(field)
	HS.stamp = frost
	field.spawn(Vector2.ZERO, 0.0, 0.0, Color.WHITE, false, 0.0, 0.0, 2.0, 7, Element.Type.ICE)
	HS.stamp = 0
	field.step(0.01, Vector2.ZERO, 6.0, 0.0, false)
	check("an orb is stamped as it spawns and its hit names it (BulletField.hit_source)",
		field.hits.size() == 1 and field.hit_source.size() == 1 and HS.name_of(field.hit_source[0]) == "icesprite:frost",
		[field.hits, field.hit_source])
	field.queue_free()
	var zone := BulletZone.new()
	add_child(zone)
	zone.set_process(false)
	add_child(sprite)
	sprite.process_mode = Node.PROCESS_MODE_DISABLED
	Kit.fire(zone, sprite, Vector2(-90000, -90000), 0.0, "kit:4", 90.0, 3, 3)
	check("  a kit's orbs are its monster's kind", zone.field.count > 0
		and HS.name_of(zone.field._source[0]) == "icesprite:frost")
	zone.queue_free()
	sprite.queue_free()

	var player_src: String = (load("res://src/characters/player.gd") as GDScript).source_code
	var hit: String = _func_body(player_src, "func take_damage(")
	check("take_damage() takes the blame before anything can return, and counts it with the hit",
		hit.find("HitSource.take()") >= 0 and hit.find("HitSource.take()") < hit.find("if is_dying")
		and hit.contains("Presence.note_taken(reduced_amount, element, source)"))
	var blamed: Array = []
	for f in ["projectiles/arrow", "projectiles/fireprojectile", "projectiles/magicprojectile",
			"projectiles/poisonprojectile", "projectiles/vine", "projectiles/bossprojectile",
			"projectiles/acidpuddle", "enemies/skeleton", "enemies/bossenemy", "world/spikedoor",
			"world/bulletzone", "characters/statuseffects"]:
		if not FileAccess.get_file_as_string("res://src/%s.gd" % f).contains("HitSource.blame"):
			blamed.append(f)
	check("  every script that hurts a player says whose hit it is", blamed.is_empty(), blamed)

	var kept: Dictionary = {"by": Presence.meter_by_source, "sent": Presence._sent_by_source, "taken": Presence.meter_taken}
	Presence.meter_by_source = {}
	Presence.note_taken(12, Element.Type.ICE, "icesprite:frost")
	Presence.note_taken(8, Element.Type.ICE, "icesprite:frost")
	check("Presence keeps [hits, damage] by source", Presence.meter_by_source.get("icesprite:frost", []) == [2, 20])
	for n in Presence.SOURCES_MOST:
		Presence.note_taken(1, 0, "m%d:a" % n)
	check("  past SOURCES_MOST names the rest are counted as other",
		Presence.meter_by_source.has(Presence.OTHER_SOURCE) and Presence.meter_by_source.size() == Presence.SOURCES_MOST + 1)
	Presence.meter_by_source = kept["by"]
	Presence._sent_by_source = kept["sent"]
	Presence.meter_taken = kept["taken"]

	var log_script: GDScript = load("res://src/ui/owner/fightlog.gd") as GDScript
	var who: Dictionary = {"2": ["Tom", "tank", 9, 30, 25]}
	var fight: Dictionary = log_script.begin(0.0, 1793002000.0, "field")
	log_script.add(fight, {"a": "field", "h": [], "who": who, "sn": {"icesprite": "Ice Sprite"},
		"tk": {"2": [50, 0, 0, 30, 350, 400, {}, {"icesprite:frost": [3, 30], "lightbushsniper:arrow": [1, 20]}]}}, 0.0)
	log_script.add(fight, {"a": "field", "h": [], "who": {},
		"tk": {"2": [15, 0, 0, 15, 335, 400, {}, {"icesprite:frost": [1, 15]}]}}, 1.0)
	var record: Dictionary = log_script.finish(fight)
	var tom: Dictionary = log_script.player_in(record, 2)
	check("the fight keeps what hit each player, most damage first",
		tom.get("hit_by", []) == [["icesprite:frost", 4, 45], ["lightbushsniper:arrow", 1, 20]], tom.get("hit_by"))
	check("  named as the server's catalogue names them, else by its id",
		log_script.source_monster(record, "icesprite:frost") == "Ice Sprite"
		and log_script.source_monster(record, "lightbushsniper:arrow") == "Lightbushsniper"
		and log_script.source_attack("icesprite:frost") == "frost mines" and log_script.source_attack("x:big_bang") == "big bang")
	var rows: Array = log_script.hit_by_rows(record)
	check("  the table's rows: player, source, hits, damage, share of what they took",
		rows.size() == 2 and int(rows[0][3]) == 45 and is_equal_approx(float(rows[0][4]), 45.0 / 65.0), rows)
	check("  the spreadsheet and Copy carry it",
		log_script.csv(record).contains("Player,Hit by,Attack,Hits,Damage,Average,Share of taken\nTom,Ice Sprite,frost mines,4,45,11,69%")
		and log_script.compare_text([record]).contains("Tom hit by Ice Sprite, frost mines: 4 hits, 45"))

	var meter_script: GDScript = load("res://src/ui/owner/damagemeter.gd") as GDScript
	var meter: CanvasLayer = meter_script.new() as CanvasLayer
	meter.set("log_path", "user://test_fightlog_hit/log.json")
	meter.set("csv_folder", "user://test_fightlog_hit")
	meter.set("fights", [record])
	meter.set("picked", [int(record["id"])])
	add_child(meter)
	meter.call("show_page", "fights")
	meter.call("show_view", "players")
	var grid: GridContainer = meter.find_child("hitgrid", true, false) as GridContainer
	check("Players gains a third table: what hit each of them",
		grid != null and grid.visible and grid.get_child_count() == 3 * meter_script.HIT_COLUMNS.size()
		and meter_script.HIT_COLUMNS.size() == meter_script.HIT_TIPS.size())
	meter.queue_free()
	await get_tree().process_frame
	print("  what hit me checked")


func _test_bosses_scale_to_their_fight() -> void:
	section("BOSSES THAT SCALE - a boss's health set by who is fighting it")
	var B := preload("res://src/enemies/bossenemy.gd")
	check("at its own band, one player: the catalogue's health",
		is_equal_approx(B.scale_for(Element.Type.LIGHT, [4]), 1.0) and is_equal_approx(B.scale_for(Element.Type.FIRE, [21]), 1.0))
	check("  a level-22 on the Light boss (band top 4): 1 + 0.2 x 18 = 4.6 times",
		is_equal_approx(B.scale_for(Element.Type.LIGHT, [22]), 4.6), B.scale_for(Element.Type.LIGHT, [22]))
	check("  far over, held to LEVEL_MOST (5); the Crowned at 22 its own 2.5",
		is_equal_approx(B.scale_for(Element.Type.LIGHT, [60]), 5.0) and is_equal_approx(B.scale_for(Element.Type.DARK, [22]), 2.5))
	check("  four of its band: 1 + 0.6 x 3 = 2.8 times; nobody: its base",
		is_equal_approx(B.scale_for(Element.Type.LIGHT, [4, 4, 3, 2]), 2.8) and is_equal_approx(B.scale_for(Element.Type.DARK, []), 2.5))
	var crowd: Array = []
	for i in 20:
		crowd.append(99)
	check("  at most PARTY_MOST (16) counted, so the most is 2.5 x 5 x 10 = 125 - under the server's BOSS_RAISED_MOST (400)",
		is_equal_approx(B.scale_for(Element.Type.DARK, crowd), 125.0), B.scale_for(Element.Type.DARK, crowd))

	var world := Node2D.new()
	add_child(world)
	var boss: Node2D = (load("res://scene/enemy/lightboss.tscn") as PackedScene).instantiate() as Node2D
	world.add_child(boss)
	var me: Node2D = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate() as Node2D
	me.set_physics_process(false)
	world.add_child(me)
	await get_tree().process_frame
	boss.set_physics_process(false)
	me.global_position = boss.global_position + Vector2(0, 60)
	var base: int = int(boss.max_hp)
	boss.set("player", me)
	boss.set("engaged", true)
	boss.set("gated", false)
	me.set("level", 10)
	boss.call("raise_for_scale")
	var at_ten: int = int(boss.max_hp)
	check("in a fight: raised for who is in it (one level-10 on Light: 2.2 times), and full",
		at_ten == roundi(base * 2.2) and int(boss.hp) == at_ten and is_equal_approx(float(boss.health_scale), 2.2),
		[base, at_ten, boss.hp])
	boss.hp = at_ten - 500
	me.set("level", 22)
	boss.call("raise_for_scale")
	check("  stronger fighters raise it again, the damage already done kept",
		int(boss.max_hp) == roundi(base * 4.6) and int(boss.hp) == int(boss.max_hp) - 500, [boss.max_hp, boss.hp])
	var raised: int = int(boss.max_hp)
	me.set("level", 4)
	boss.call("raise_for_scale")
	check("  and never lowered in a fight", int(boss.max_hp) == raised)
	boss.set("engaged", false)
	boss.hp = int(boss.max_hp)
	boss.call("unscale")
	check("home, out of the fight and whole: itself again for whoever comes next",
		int(boss.max_hp) == base and int(boss.hp) == base and is_equal_approx(float(boss.health_scale), 1.0), boss.max_hp)
	boss.set("net_mirror", true)
	boss.set("engaged", true)
	boss.call("raise_for_scale")
	boss.call("net_rescale", 9999, 8000)
	check("a copy on another screen never raises it itself; it takes the leader's ('mh')",
		int(boss.max_hp) == 9999 and int(boss.hp) == 8000)
	check("  and the leader tells every screen and the server",
		_func_body(_code_src("res://src/enemies/bossenemy.gd"), "func _tell_scale(").contains("\"k\": \"mh\"")
		and _code_src("res://src/world/monstersync.gd").contains("mirror.call(\"net_rescale\""))
	world.queue_free()
	await get_tree().process_frame


func _test_the_bosses_are_seven_fights() -> void:
	section("SEVEN BOSSES, SEVEN FIGHTS (0.77.0) - each its own kit and effect, attacking everyone in turn")
	const FX := preload("res://src/characters/statuseffects.gd")
	const BossScript := preload("res://src/enemies/bossenemy.gd")
	const Targets := preload("res://src/shared/targets.gd")
	var boss_src := FileAccess.get_file_as_string("res://src/enemies/bossenemy.gd")
	var kits: Dictionary = BossScript.KITS

	# ---- the kits ------------------------------------------------------------
	var elements: Array = []
	var shape_sets: Array = []
	var first_volleys: Array = []
	var bad_kits: Array = []
	for eid in _KIT_BOSSES:
		var boss: Node = _kit_boss(eid)
		var element: int = boss.current_element()
		elements.append(element)
		var kit: Dictionary = kits.get(element, {})
		var shapes: Array = kit.get("shapes", [])
		var known: bool = shapes.size() == 3
		for shape in shapes:
			known = known and _KNOWN_SHAPES.has(shape)
		var phases_ok: bool = boss.stalagmite_pool(0).size() == 2 and boss.stalagmite_pool(1).size() == 3 \
			and boss.stalagmite_pool(2).size() == 3 and boss.stalagmite_pool(0) == [shapes[0], shapes[1]]
		var volleys: Array = kit.get("volleys", [])
		var volleys_ok: bool = volleys.size() == 3
		for list in volleys:
			for v in list:
				volleys_ok = volleys_ok and BossScript.VOLLEYS.has(v)
		if not (kits.has(element) and known and phases_ok and volleys_ok):
			bad_kits.append(eid)
		var sorted_shapes: Array = shapes.duplicate()
		sorted_shapes.sort()
		shape_sets.append(sorted_shapes)
		first_volleys.append(volleys[0] if volleys.size() > 0 else [])
		boss.free()
	check("every boss has a kit of its element's: three of the sixteen stalagmite shapes and a volley for each phase",
		bad_kits.is_empty(), bad_kits)
	check("  the first two shapes from the start and all three from phase two", bad_kits.is_empty())
	var distinct_shapes: Dictionary = {}
	var distinct_volleys: Dictionary = {}
	for k in shape_sets.size():
		distinct_shapes[str(shape_sets[k])] = true
		distinct_volleys[str(first_volleys[k])] = true
	check("no two bosses raise the same three shapes, or open with the same volley - seven fights, not one recoloured",
		distinct_shapes.size() == 7 and distinct_volleys.size() == 7, [shape_sets, first_volleys])
	var crowned_last: Array = kits[Element.Type.DARK]["volleys"][2]
	var all_six: bool = true
	for element in elements:
		if element == Element.Type.DARK:
			continue
		for v in kits[element]["volleys"][0]:
			all_six = all_six and crowned_last.has(v)
	check("the Crowned's last phase throws every one of the other six's volleys", all_six, crowned_last)
	var stalker_kits: Array = []
	for element in kits:
		if bool(kits[element].get("stalkers", false)):
			stalker_kits.append(element)
	check("only the Crowned keeps the stalkers", stalker_kits == [Element.Type.DARK], stalker_kits)
	check("one clock raises the stalagmites now, so shapes once kept on separate tracks can never meet",
		_first_code_index(boss_src, "func _build_pattern(", 0) == -1
		and _first_code_index(boss_src, "_pattern_by_name(choice, origin), choice)", 0) != -1)

	# ---- the effects, on their own -------------------------------------------
	var lab := Node2D.new()
	add_child(lab)
	var body := ZoneDummy.new()
	lab.add_child(body)
	var fx: Node = FX.attach(body)
	check("anything that takes damage can carry effects, found by name", FX.of(body) == fx and fx.host == body)
	fx.apply(FX.CHILL)
	var one: float = fx.speed_scale()
	fx.apply(FX.CHILL)
	var two: float = fx.speed_scale()
	fx.apply(FX.CHILL)
	check("chill: 20%% slower a hit, 40%% at two, and the third hit freezes (%.1f, %.1f, %.1f)" % [one, two, fx.speed_scale()],
		is_equal_approx(one, 0.8) and is_equal_approx(two, 0.6) and fx.speed_scale() == 0.0
		and fx.started.has(FX.FROZEN), [one, two, fx.speed_scale()])
	check("  held, you cannot sprint either", not fx.can_sprint())
	fx.advance(FX.FROZEN_SECONDS + 0.01)
	check("  for %.1f s, then free" % FX.FROZEN_SECONDS, is_equal_approx(fx.speed_scale(), 1.0), fx.speed_scale())
	for k in 4:
		fx.apply(FX.CHILL)
	check("  and nothing holds you again for %.0f s: chilled four times over, you are slowed, never frozen" % FX.HOLD_IMMUNITY,
		is_equal_approx(fx.speed_scale(), FX.SLOW_FLOOR) and not fx.is_held(), fx.speed_scale())
	check("  rooted neither", not fx.apply(FX.ROOT))
	check("nothing slows you more than 40%", is_equal_approx(FX.SLOW_FLOOR, 0.6) and FX.CHILL_STEP * (FX.CHILL_TO_FREEZE - 1) <= 0.4 + 0.0001)
	fx.advance(FX.HOLD_IMMUNITY + 0.1)
	check("  the chill wears off on its own (%.1f s since the last)" % FX.CHILL_SECONDS, is_equal_approx(fx.speed_scale(), 1.0))
	check("root: %.1f s where you stand" % FX.ROOT_SECONDS, fx.apply(FX.ROOT) and fx.speed_scale() == 0.0)
	fx.advance(FX.ROOT_SECONDS + 0.01)
	check("  then you walk, and cannot be rooted or frozen again at once",
		is_equal_approx(fx.speed_scale(), 1.0) and not fx.apply(FX.ROOT) and fx.hold_immune_left > 0.0)
	fx.clear_all()
	for k in 5:
		fx.apply(FX.CHILL, 4, Vector2.INF, true)
	check("a puddle chills but never freezes: standing on ice slows you, being hit by it is what freezes",
		is_equal_approx(fx.speed_scale(), FX.SLOW_FLOOR) and not fx.is_held())
	check("  and a puddle cannot shove, root or dazzle - only the ground effects ride on one",
		not fx.apply(FX.ROOT, 4, Vector2.INF, true) and not fx.apply(FX.SHOVE, 4, Vector2.ZERO, true)
		and not fx.apply(FX.DAZZLE, 4, Vector2.INF, true)
		and FX.GROUND == [FX.CHILL, FX.BURN, FX.SOAKED, FX.WITHER])
	fx.clear_all()
	body.taken.clear()
	fx.apply(FX.BURN, 100)
	for k in 20:
		fx.advance(0.1)
	fx.apply(FX.BURN, 100)
	for k in 20:
		fx.advance(0.1)
	var ticks: Array = []
	for t in body.taken:
		ticks.append(t[0])
	check("burn: %d%% of the hit every %.1f s, refreshed by another hit, never stacked (8 ticks of 8 over 4 s)" % [
			roundi(FX.BURN_SHARE * 100), FX.BURN_TICK],
		ticks.size() == 8 and ticks.max() == 8 and ticks.min() == 8 and body.taken[0][1] == Element.Type.FIRE, ticks)
	fx.advance(FX.BURN_SECONDS)
	check("  and out %.0f s after the last hit: ten ticks in all" % FX.BURN_SECONDS,
		body.taken.size() == 10 and fx.burn_left == 0.0, body.taken.size())
	fx.apply(FX.SOAKED)
	var soaked: bool = not fx.can_sprint()
	fx.advance(FX.SOAKED_SECONDS + 0.01)
	check("soaked: no sprint for %.0f s, and walking as ever" % FX.SOAKED_SECONDS,
		soaked and fx.can_sprint() and is_equal_approx(fx.speed_scale(), 1.0))
	fx.apply(FX.SHOVE, 1, Targets.body_point(body) + Vector2(-10, 0))
	var push: Vector2 = fx.push_velocity()
	var carried: float = 0.0
	for k in 40:
		carried += fx.push_velocity().x * 0.01
		fx.advance(0.01)
	check("shove: knocked along the hit, about 40 px, then still (%.1f px)" % carried,
		push.x > 0.0 and is_zero_approx(push.y) and absf(carried - 40.0) < 3.0 and fx.push_velocity() == Vector2.ZERO, [push, carried])
	fx.pull(Targets.body_point(body) + Vector2(300, 0), 2.0, 999.0)
	check("pull: toward the boss, never as fast as you walk (%.0f px/s at most)" % FX.PULL_SPEED_MAX,
		fx.push_velocity().x > 0.0 and fx.push_velocity().length() <= FX.PULL_SPEED_MAX + 0.01 and FX.PULL_SPEED_MAX < 90.0,
		fx.push_velocity())
	fx.clear_all()
	fx.apply(FX.DAZZLE)
	var flashed: float = fx._flash_left
	fx.advance(0.2)
	fx.apply(FX.DAZZLE)
	check("dazzle: %.0f s, one soft flash however many orbs land (at most one every %.0f s)" % [FX.DAZZLE_SECONDS, FX.DAZZLE_FLASH_GAP],
		flashed > 0.0 and fx._flash_left < flashed and FX.FLASH_ALPHA <= 0.5 and fx.started.count(FX.DAZZLE) == 1)
	fx.apply(FX.WITHER)
	check("wither: healing halved while it lasts", is_equal_approx(fx.heal_scale(), 0.5))
	fx.advance(FX.WITHER_SECONDS + 0.01)
	check("  for %.0f s" % FX.WITHER_SECONDS, is_equal_approx(fx.heal_scale(), 1.0))
	var longest: float = maxf(maxf(FX.CHILL_SECONDS, FX.BURN_SECONDS), maxf(FX.SOAKED_SECONDS, maxf(FX.DAZZLE_SECONDS, FX.WITHER_SECONDS)))
	check("nothing lasts longer than 3 s", longest <= 3.0 and FX.FROZEN_SECONDS < 1.0 and FX.ROOT_SECONDS < 1.0, longest)
	body.is_dying = true
	check("a dying body takes no effects", not fx.apply(FX.CHILL) and not fx.apply(FX.BURN, 50))
	body.is_dying = false
	var boss_effects: Dictionary = {}
	for element in elements:
		boss_effects[FX.for_element(element)] = true
	check("each of the seven bosses' elements carries an effect of its own", boss_effects.size() == 7 and not boss_effects.has(&""),
		boss_effects.keys())
	check("  and the others carry none: the Field's monsters are as they were", FX.for_element(Element.Type.POISON) == &""
		and FX.for_element(Element.Type.NONE) == &"")

	# ---- the hazards carry them ----------------------------------------------
	var holder := Node2D.new()
	lab.add_child(holder)
	var wrong: Array = []
	for eid in _KIT_BOSSES:
		var boss: Node = _kit_boss(eid)
		var had: Array = holder.get_children()
		boss._spawn_one_eruption(holder, Vector2.ZERO, 1.0, boss.SPIKE_BASE_RADIUS, boss.gate_scene)
		for c in holder.get_children():
			if not had.has(c):
				if StringName(c.get("status")) != FX.for_element(boss.current_element()):
					wrong.append(eid)
				c.free()
		boss.free()
	check("every boss's stalagmites carry its effect, on every game that draws them (set in _spawn_one_eruption)",
		wrong.is_empty(), wrong)
	var spike_src := FileAccess.get_file_as_string("res://src/projectiles/bossprojectile.gd")
	check("  a spike puts it on whoever it catches, and its pool carries the ground ones",
		spike_src.contains("StatusEffects.apply_to(target, status, damage, global_position)")
		and spike_src.contains("StatusEffects.GROUND.has(status)"))

	var others: Array = get_tree().get_nodes_in_group(&"player")
	for o in others:
		o.remove_from_group(&"player")
	body.add_to_group(&"player")
	body.position = Vector2(-52000, -52000)
	var zone := BulletZone.new()
	lab.add_child(zone)
	zone.set_process(false)
	fx.clear_all()
	var at: Vector2 = Targets.body_point(body)
	zone.field.spawn(at, 0.0, 1.0, Color.WHITE, false, 0.0, 0.0, 6.0, 9, Element.Type.ICE)
	zone._process(0.01)
	check("an orb in the Field chills nobody - the Field's monsters are as they were", fx.chill_stacks == 0)
	zone.element_effects = true
	zone.field.spawn(at, 0.0, 1.0, Color.WHITE, false, 0.0, 0.0, 6.0, 9, Element.Type.ICE)
	zone._process(0.01)
	check("an orb in a boss room carries its element's effect", fx.chill_stacks == 1, fx.chill_stacks)
	zone.field.spawn(at - Vector2(6, 0), 0.0, 100.0, Color.WHITE, false, 0.0, 0.0, 6.0, 5, Element.Type.WIND)
	zone._process(0.05)
	check("  a wind orb shoves you on along the line it flew", fx.push_velocity().x > 0.0 and absf(fx.push_velocity().y) < 1.0,
		fx.push_velocity())
	fx.clear_all()
	zone.field.spawn(at + Vector2(0, 5), 0.0, 0.0, Color.WHITE, true, 0.0, 0.0, 6.0, 5, Element.Type.WIND)
	zone._process(0.01)
	check("  and a mine lying still shoves you away from where it lay", fx.push_velocity().y < 0.0, fx.push_velocity())
	check("both boss rooms are bullet rooms whose orbs carry their effects (boss.gd)",
		FileAccess.get_file_as_string("res://src/enemies/boss.gd").contains("zone.element_effects = true"))
	fx.clear_all()
	var pool: Node = (load("res://scene/projectiles/icepuddle.tscn") as PackedScene).instantiate()
	pool.status = FX.CHILL
	pool.spawn_at = at
	lab.add_child(pool)
	pool._enter(body)
	for k in 6:
		pool._tick_players_inside(float(pool.tick_interval))
	check("a boss's ice slick chills you while you stand in it, and never freezes you",
		fx.chill_stacks == FX.CHILL_TO_FREEZE - 1 and not fx.is_held(), fx.chill_stacks)
	pool.queue_free()
	zone.queue_free()
	var slime_pool: Node = (load("res://scene/projectiles/icepuddle.tscn") as PackedScene).instantiate()
	check("  and every other pool in the game carries nothing", StringName(slime_pool.status) == &"")
	slime_pool.free()

	# ---- the volleys -----------------------------------------------------------
	var arena := Node2D.new()
	arena.position = Vector2(-60000, -60000)
	lab.add_child(arena)
	body.position = Vector2(-60000 + 90, -60000)
	fx.clear_all()
	var crowned: Node = _kit_boss("boss")
	crowned.set_physics_process(false)
	arena.add_child(crowned)
	# Caged: it thinks nothing and casts nothing of its own while the test
	# fires its volleys for it.
	crowned.gated = true
	crowned.global_position = Vector2(-60000, -60000)
	var zones: Dictionary = {}
	for kind in BossScript.VOLLEYS:
		var z := BulletZone.new()
		arena.add_child(z)
		z.set_process(false)
		zones[kind] = z
	var origin: Vector2 = crowned.global_position
	var aim: float = (Targets.body_point(body) - origin).angle()
	for kind in BossScript.VOLLEYS:
		crowned.fire_volley(zones[kind], origin, aim, "%s0" % kind, 90.0)
	var at_once: Dictionary = {}
	for kind in zones:
		at_once[kind] = zones[kind].field.count
	check("a prism's first spokes leave at once, a pincer's arms all together",
		at_once[&"prism"] == 6 and at_once[&"pincer"] == 4, at_once)
	check("  and the vortex draws you in, slower than you walk",
		fx.pull_left > 0.0 and fx.pull_speed <= FX.PULL_SPEED_MAX, [fx.pull_left, fx.pull_speed])
	await get_tree().create_timer(1.9).timeout
	var later: Dictionary = {}
	for kind in zones:
		later[kind] = zones[kind].field.count
	check("the rest on the beat: 10 prisms of 6, 3 gales of 5, 2 vortex rings of 28 with a door of 4, 3 tides of 23 with a gap of 3, 9 frost mines, a boulder's impact and 8 rocks",
		later[&"prism"] == 60 and later[&"gale"] == 15 and later[&"vortex"] == 48 and later[&"tide"] == 60
		and later[&"frost"] == 9 and later[&"boulder"] == 9, later)
	var burning: int = 0
	for p in get_tree().get_nodes_in_group(&"acidpuddles"):
		if StringName(p.get("status")) == FX.WITHER:
			burning += 1
	check("  where the pincer shut, the floor carries the boss's effect (the Crowned's: withered)", burning >= 1, burning)
	var nothing := BulletZone.new()
	arena.add_child(nothing)
	nothing.set_process(false)
	for name_sent in ["laser0", "prism", "", "0", "tide:4"]:
		crowned.fire_volley(nothing, origin, aim, name_sent, 90.0)
	check("a volley named nothing this boss throws fires nothing - what a follower is sent cannot make one up",
		nothing.field.count == 0, nothing.field.count)
	check("  and every boss answers a leader's volley (monstersync \"b\")", crowned.has_method(&"fire_volley"))
	for z in zones.values():
		z.queue_free()
	nothing.queue_free()
	crowned.queue_free()

	# ---- whose turn it is ------------------------------------------------------
	var ring_boss: Node = _kit_boss("lightboss")
	ring_boss.set_physics_process(false)
	arena.add_child(ring_boss)
	ring_boss.gated = true
	ring_boss.global_position = Vector2(-60000, -60000)
	var second := ZoneDummy.new()
	second.add_to_group(&"player")
	arena.add_child(second)
	body.global_position = Vector2(-60000 + 60, -60000)
	second.global_position = Vector2(-60000 - 100, -60000)
	check("with nobody attacked yet, the nearer goes first", ring_boss.next_target() == body)
	ring_boss._mark_aimed(body)
	check("  then the one left alone longest", ring_boss.next_target() == second)
	await get_tree().create_timer(0.02).timeout
	ring_boss._mark_aimed(second)
	check("  round and round", ring_boss.next_target() == body)
	check("  never the one just attacked while anyone else is there", ring_boss.next_target(body) == second)
	second.is_dying = true
	check("a dying player is not in the fight", ring_boss.fight_targets() == [body] and ring_boss.next_target(body) == body)
	second.is_dying = false
	second.global_position = Vector2(-60000 - 600, -60000)
	check("  nor one past the leash", ring_boss.fight_targets() == [body])
	second.global_position = Vector2(-60000 - 100, -60000)
	check("a boulder or a pincer goes at everyone in the fight, %d at most" % BossScript.SPLIT_MAX,
		ring_boss.split_targets(body).size() == 2 and ring_boss.split_targets(body)[0] == body)

	var cast_zone := BulletZone.new()
	arena.add_child(cast_zone)
	cast_zone.set_process(false)
	ring_boss.player = body
	ring_boss._cast_signature()
	check("a cast at one player turns the boss to the next", ring_boss.player == second, ring_boss.player)
	check("  and the prism went at the one it faced", cast_zone.field.count == 6, cast_zone.field.count)
	ring_boss._cast_signature()
	check("  and back", ring_boss.player == body)
	second.remove_from_group(&"player")
	ring_boss._cast_signature()
	check("alone in the room, it is all you", ring_boss.player == body)
	var timer: Timer = ring_boss.get_node(^"attacktimer")
	check("each cast waits for its volley and a rest before the next (prism %.1f s + %.1f s)" % [
			BossScript.VOLLEY_BUSY[&"prism"], BossScript.VOLLEY_REST[0]],
		is_equal_approx(timer.wait_time, BossScript.VOLLEY_BUSY[&"prism"] + BossScript.VOLLEY_REST[0]), timer.wait_time)

	var stub := GDScript.new()
	stub.source_code = "extends Node\nvar fighting: bool = true\nfunc in_fight() -> bool:\n\treturn fighting\n"
	stub.reload()
	var partners: Array = []
	for k in 3:
		var partner: Node = stub.new()
		partner.add_to_group(BossScript.BOSS_GROUP)
		lab.add_child(partner)
		partners.append(partner)
	partners[2].fighting = false
	check("two partners loose beside a boss slow it to x%.2f; a caged one does not count" % (1.0 + 2.0 * BossScript.WAVE_PACE),
		is_equal_approx(ring_boss._pace(), 1.0 + 2.0 * BossScript.WAVE_PACE), ring_boss._pace())
	for partner in partners:
		partner.queue_free()
	await get_tree().process_frame
	check("  and alone it is back to full speed", is_equal_approx(ring_boss._pace(), 1.0), ring_boss._pace())
	check("a caged boss is in no fight", not ring_boss.in_fight())

	var stalkers: Dictionary = {}
	for eid in ["lightboss", "boss"]:
		var b: Node = _kit_boss(eid)
		b.set_physics_process(false)
		arena.add_child(b)
		b.gated = true
		stalkers[eid] = b.get("_stalker_timer") != null
		b.queue_free()
	check("  and only the Crowned's room has a stalker clock running", stalkers == {"lightboss": false, "boss": true}, stalkers)

	# ---- you, carrying them ----------------------------------------------------
	var me: Node2D = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	me.set_physics_process(false)
	lab.add_child(me)
	var mine: Node = FX.of(me)
	check("your character carries effects from the moment it is made", mine != null and me.status_effects == mine)
	mine.apply(FX.CHILL)
	check("  chilled, it walks slower", is_equal_approx(me.effects_speed_scale(), 0.8), me.effects_speed_scale())
	mine.apply(FX.SOAKED)
	check("  soaked, it cannot sprint", not me.effects_let_sprint())
	me.set("max_hp", 400)
	me.set("hp", 100)
	mine.apply(FX.WITHER)
	me.heal(40)
	check("  withered, a heal of 40 is 20", int(me.get("hp")) == 120, me.get("hp"))
	var player_src := FileAccess.get_file_as_string("res://src/characters/player.gd")
	var tank_src := FileAccess.get_file_as_string("res://src/characters/tank.gd")
	check("both walks ask: the shared loop and the tank's own",
		player_src.contains("velocity = direction.normalized() * actual_speed * effects_speed_scale()")
		and player_src.contains("velocity += push") and tank_src.contains("actual_speed * effects_speed_scale()")
		and tank_src.contains("velocity += push") and tank_src.contains("effects_let_sprint()"))
	me.queue_free()

	lab.queue_free()
	for o in others:
		if is_instance_valid(o):
			o.add_to_group(&"player")
	await get_tree().process_frame


# =============================================================================
# GEAR BONUSES ARE SHOWN: THE DOLL'S TOTALS AND THE TOOLTIP'S COMPARISON
# =============================================================================
# Every tier from jade up adds health, mana or damage, and until this the only
# place to read one was a single tooltip - with nothing saying whether it beat
# what you were wearing. The Gear window sums them (from the same
# equipped_bonus() the character uses), and a tooltip over a piece of gear
# lists what would change, green or red, against the piece in that slot.

func _test_gear_bonuses_are_shown() -> void:
	section("GEAR BONUSES ARE SHOWN — the Gear window's totals, the tooltip's comparison")

	var chest := _gear_test_item("geartest_chest", ItemData.EquipSlot.CHEST,
		{"armor_value": 10, "bonus_max_hp": 40})
	var better := _gear_test_item("geartest_chest_b", ItemData.EquipSlot.CHEST,
		{"armor_value": 16, "bonus_max_hp": 30})
	var twin := _gear_test_item("geartest_chest_c", ItemData.EquipSlot.CHEST,
		{"armor_value": 10, "bonus_max_hp": 40})
	var ring := _gear_test_item("geartest_ring", ItemData.EquipSlot.RING,
		{"bonus_max_mana": 12, "bonus_damage_percent": 2})
	var boots := _gear_test_item("geartest_boots", ItemData.EquipSlot.BOOTS, {"armor_value": 4})
	var robe := _gear_test_item("geartest_robe", ItemData.EquipSlot.CHEST,
		{"armor_value": 3, "bonus_max_mana": 48})
	robe.required_classes.append("geartest_nobody")
	var stone := _gear_test_item("geartest_stone", ItemData.EquipSlot.NONE, {})
	for d in [chest, better, twin, ring, boots, robe, stone]:
		ItemRegistry._items[d.item_id] = d

	var body: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	body._set_stat_curve()
	body.level = 10
	body.equipped = {}

	# ---- the Gear window ----------------------------------------------------
	var panel: Node = (load("res://scene/ui/equipment/equipmentpanel.tscn") as PackedScene).instantiate()
	add_child(panel)
	await get_tree().process_frame
	panel.player = body
	panel._refresh_summary()
	check("wearing nothing, the three bonus rows read as a dash, not +0",
		panel.health_bonus_label.text == "-" and panel.mana_bonus_label.text == "-"
		and panel.damage_bonus_label.text == "-",
		[panel.health_bonus_label.text, panel.mana_bonus_label.text, panel.damage_bonus_label.text])
	body.equipped = {"chest": chest.item_id, "ring": ring.item_id}
	panel._refresh_summary()
	check("in a +40 health chest and a +12 mana, +2% ring: +40, +12, +2%",
		panel.health_bonus_label.text == "+40" and panel.mana_bonus_label.text == "+12"
		and panel.damage_bonus_label.text == "+2%",
		[panel.health_bonus_label.text, panel.mana_bonus_label.text, panel.damage_bonus_label.text])
	check("  in the good colour",
		panel.health_bonus_label.get_theme_color("font_color") == panel.COLOUR_GOOD)
	check("  and they are the character's own sums, the ones its maxima use",
		body.equipped_bonus("bonus_max_hp") == 40 and body.equipped_bonus("bonus_max_mana") == 12)
	panel.queue_free()

	# ---- compare_rows, the arithmetic ---------------------------------------
	var Tip: Script = load("res://src/ui/inventory/itemtooltip.gd")
	var rows: Array = Tip.compare_rows(better, chest)
	check("a chest with 6 more armour and 10 less health: two rows, in that order",
		rows.size() == 2 and rows[0]["label"] == "Armour" and int(rows[0]["delta"]) == 6
		and rows[1]["label"] == "Max health" and int(rows[1]["delta"]) == -10, rows)
	check("against an empty slot everything is a gain",
		Tip.compare_rows(ring, null).size() == 2
		and int(Tip.compare_rows(ring, null)[1]["delta"]) == 2
		and Tip.compare_rows(ring, null)[1]["suffix"] == "%", Tip.compare_rows(ring, null))
	check("and a piece identical to the worn one changes nothing",
		Tip.compare_rows(twin, chest).is_empty())

	# ---- the tooltip ---------------------------------------------------------
	var tip: Control = (load("res://scene/ui/inventory/itemtooltip.tscn") as PackedScene).instantiate()
	add_child(tip)
	await get_tree().process_frame
	check("a tooltip for a stone ends at its text: no rule, no empty band under it",
		_tip_comparing(tip, stone, null, body) == "hidden")
	check("a tooltip for gear compares it with what is worn in that slot",
		_tip_comparing(tip, better, null, body) == "shown"
		and tip.compare_heading.text == "Compared with your Geartest Chest:", tip.compare_heading.text)
	var got := _tip_rows(tip)
	check("  +6 armour in green, -10 max health in red",
		got.size() == 2 and got[0] == ["Armour", "+6", tip.COMPARE_BETTER]
		and got[1] == ["Max health", "-10", tip.COMPARE_WORSE], got)
	var bare := _tip_comparing(tip, boots, null, body)
	got = _tip_rows(tip)
	check("boots over bare feet: one line saying it is all a gain, not the stat line again as rows",
		bare == "shown" and tip.compare_heading.text.begins_with("Nothing is worn there yet")
		and got.is_empty(), [tip.compare_heading.text, got])
	_tip_comparing(tip, twin, null, body)
	got = _tip_rows(tip)
	check("the same stats as the worn piece say No change",
		got.size() == 1 and got[0][0] == "No change", got)
	var square: Node = (load("res://scene/ui/equipment/equipmentslot.tscn") as PackedScene).instantiate()
	check("the piece on the doll compares with nothing - it is what is worn",
		_tip_comparing(tip, chest, square, body) == "hidden")
	square.free()
	check("gear this class can never wear is not compared",
		_tip_comparing(tip, robe, null, body) == "hidden")
	check("nor is anything when nobody is playing",
		_tip_comparing(tip, better, null, null) == "hidden")
	tip.show_for_stack(ItemStack.new(better, 1), null)
	var show_src := FileAccess.get_file_as_string("res://src/ui/inventory/itemtooltip.gd")
	var show_at := _first_code_index(show_src, "func show_for_stack(", 0)
	var show_end := _first_code_index(show_src, "\nfunc ", show_at + 1)
	check("show_for_stack() asks for the comparison with the player who is playing",
		_within(_first_code_index(show_src, "populate_comparison(stack.data, source_slot, get_tree().get_first_node_in_group(\"player\"))", show_at), show_end) != -1)
	check("  and fits itself to what it holds, so a short tooltip is not a tall one",
		_within(_first_code_index(show_src, "reset_size()", show_at), show_end) != -1)
	tip.queue_free()

	body.free()
	for d in [chest, better, twin, ring, boots, robe, stone]:
		ItemRegistry._items.erase(d.item_id)
	print("  gear bonuses: the Gear window sums them, the tooltip compares them")


func _test_tooltips_say_it_once() -> void:
	section("A TOOLTIP SAYS A THING ONCE — the restore line comes from the data, not the description")

	var doubled: Array = []
	var restoring := 0
	for folder in ["consumables", "fishing"]:
		var dir := DirAccess.open("res://data/items/%s" % folder)
		if dir == null:
			continue
		for f in dir.get_files():
			if not f.ends_with(".tres"):
				continue
			var fields := _tres_fields("res://data/items/%s/%s" % [folder, f])
			if int(fields.get("restore_amount", "0")) <= 0:
				continue
			restoring += 1
			if str(fields.get("description", "")).to_lower().contains("restores"):
				doubled.append(f.get_basename())
	check("no restoring item's description repeats the restore line (%d items)" % restoring,
		restoring >= 20 and doubled.is_empty(), doubled)

	var tip: Control = (load("res://scene/ui/inventory/itemtooltip.tscn") as PackedScene).instantiate()
	add_child(tip)
	await get_tree().process_frame
	var potion := ItemData.new()
	potion.item_id = "saytest_potion"
	potion.restore_amount = 260
	potion.restore_target = ItemData.RestoreTarget.HP
	check("a health potion's line reads Restores 260 Health, not Hp",
		ItemTooltip._requirement_lines(potion) == "Restores 260 Health", ItemTooltip._requirement_lines(potion))
	potion.restore_target = ItemData.RestoreTarget.MANA
	check("and a mana potion's, Restores 260 Mana",
		ItemTooltip._requirement_lines(potion) == "Restores 260 Mana", ItemTooltip._requirement_lines(potion))
	tip.queue_free()
	print("  tooltips: the restore number is said once, from the data")


# =============================================================================
# THE SWEEP: FINISHED HALVES WITH NOTHING JOINED TO THEM
# =============================================================================
# One pass over the client for "a thing that exists and nothing reaches it",
# this project's most repeated bug. Each check below is one of those, joined.

func _test_the_sweep_wiring() -> void:
	section("THE SWEEP — attack from the server, failed pushes retried, and six small wires joined")

	# ---- attack XP is the server's, copied onto the bar ---------------------
	var callers: Array = []
	for path in _all_gd_under("res://src"):
		if _is_suite_script(path) or path.ends_with("combat.gd") or path.ends_with("player.gd"):
			continue
		if _code_src(path).contains("gain_attack_xp("):
			callers.append(path.get_file())
	check("no swing, aura tick, spell or turret shot adds attack XP of its own any more",
		callers.is_empty(), callers)

	var stub_script := GDScript.new()
	stub_script.source_code = "extends Node\nvar got: Array = []\nvar added: int = 0\n" \
		+ "func apply_server_attack(level: int, xp: int, xp_next: int) -> void:\n\tgot = [level, xp, xp_next]\n" \
		+ "func gain_attack_xp(amount: int) -> void:\n\tadded += amount\n" \
		+ "func gain_xp(_amount: int) -> void:\n\tpass\n"
	stub_script.reload()
	var killer: Node = stub_script.new()
	Combat._apply_xp(killer, {"xp_gained": 0, "attack_xp_gained": 25, "attack_level": 3,
		"attack_xp": 40, "attack_xp_to_next": 164})
	check("a kill's answer is copied onto the attack bar - level, XP and next - not added up",
		killer.got == [3, 40, 164] and killer.added == 0, [killer.got, killer.added])
	killer.got = []
	Combat._apply_xp(killer, {"xp_gained": 0, "attack_xp_gained": 25})
	check("an answer without those fields falls back to adding the amount, unscaled",
		killer.got.is_empty() and killer.added == 25, [killer.got, killer.added])
	killer.free()

	var body: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	body._set_stat_curve()
	var slots_before: Array = CharacterData.character_slots.duplicate(true)
	body.attack = 3
	body.attack_xp = 99
	body.apply_server_attack(3, 40, 164)
	check("a warrior's bar takes the server's numbers as they are (no 1.5 on top)",
		body.attack == 3 and body.attack_xp == 40 and body.attack_xp_next == 164,
		[body.attack, body.attack_xp, body.attack_xp_next])
	body.gain_attack_xp(10)
	check("and the fallback adds what it is given, no specialty, no AFK gate",
		body.attack_xp == 50, body.attack_xp)
	body.free()
	CharacterData.character_slots = slots_before

	# ---- a push that failed after it was accepted is retried -----------------
	var ss := ServerStorage.new()
	check("a fresh ServerStorage has nothing unpushed", not ss.has_unpushed())
	ss._record_push("status:0", false, "a")
	check("a refused push is remembered as unpushed", ss.has_unpushed())
	ss._record_push("status:0", true, "b")
	check("and cleared when that section goes through, with the new fingerprint",
		not ss.has_unpushed() and ss._last_pushed.get("status:0", "") == "b")
	ss._record_push("save:0", false, "c")
	check("  a failure is not recorded as pushed, so the retry sends it",
		not ss._last_pushed.has("save:0"))

	var store_script := GDScript.new()
	store_script.source_code = "extends SaveStorage\nvar saves: int = 0\nvar unpushed: bool = true\n" \
		+ "func save(_payload: Dictionary) -> bool:\n\tsaves += 1\n\tunpushed = false\n\treturn true\n" \
		+ "func has_unpushed() -> bool:\n\treturn unpushed\n"
	store_script.reload()
	var store = store_script.new()
	var was_storage = CharacterData.storage
	var was_pending: bool = CharacterData._save_pending
	var was_clock: float = CharacterData._unpushed_clock
	CharacterData.storage = store
	CharacterData._save_pending = false
	CharacterData.flush_save()
	var flushed: int = store.saves
	CharacterData.flush_save()
	var again: int = store.saves
	store.unpushed = true
	CharacterData._unpushed_clock = 0.0
	CharacterData._process(0.016)
	var retried: int = store.saves
	CharacterData.storage = was_storage
	CharacterData._save_pending = was_pending
	CharacterData._unpushed_clock = was_clock
	check("quitting with nothing queued but a failed push behind it writes the save",
		flushed == 1, flushed)
	check("  and once it is through, quitting again writes nothing", again == 1, again)
	check("  and a failed push is retried on its own clock, with nobody changing anything",
		retried == 2, retried)

	# ---- passwords: one rule ------------------------------------------------
	check("a password's surrounding spaces are not part of it",
		ApiForTests.clean_password("  hunter2hunter2 ") == "hunter2hunter2")
	var raw_fields: Array = []
	for path in ["res://src/ui/menus/loginmenu.gd", "res://src/ui/menus/optionsscreen.gd"]:
		for line in _code_src(path).split("\n"):
			if line.contains("password") and line.contains(".text") and line.contains("var ") \
					and not line.contains("clean_password("):
				raw_fields.append("%s: %s" % [path.get_file(), line.strip_edges()])
	check("every password field read goes through Api.clean_password - login, options, recovery",
		raw_fields.is_empty(), raw_fields)

	# ---- the gate spikes hit at full height -----------------------------------
	var frames_wrong: Array = []
	for el in ["", "earth", "fire", "ice", "light", "water", "wind"]:
		var node: Node = (load("res://scene/projectiles/%ssecondbossprojectile.tscn" % el) as PackedScene).instantiate()
		if int(node.get("impact_frame")) != 2:
			frames_wrong.append("%ssecondbossprojectile %s" % [el, node.get("impact_frame")])
		node.free()
	check("every gate spike lands on frame 2, the one its art holds at full height",
		frames_wrong.is_empty(), frames_wrong)
	var pillar: Node = (load("res://scene/projectiles/bossprojectile.tscn") as PackedScene).instantiate()
	check("and the pillar still on frame 1", int(pillar.get("impact_frame")) == 1, pillar.get("impact_frame"))
	pillar.free()
	check("  and the hit is timed by that setting, not a number typed in the script",
		_func_body(_code_src("res://src/projectiles/bossprojectile.gd"), "func _on_frame_changed(")
			.contains("anim.frame != impact_frame"))

	# ---- bosses are not shoved --------------------------------------------------
	check("a boss joins the group the wade query skips",
		_func_body(_code_src("res://src/enemies/bossenemy.gd"), "func _ready(").contains("add_to_group(&\"unpushable\")")
		and _code_src("res://src/characters/player.gd").contains("is_in_group(\"unpushable\")"))

	# ---- M opens the map ------------------------------------------------------
	var hud_input := _func_body(_code_src("res://src/ui/characterhud.gd"), "func _unhandled_input(")
	var m_at := hud_input.find("is_action_pressed(\"minimap_toggle\")")
	check("M (minimap_toggle) opens the map, like I, C and G open theirs",
		m_at != -1 and hud_input.find("toggle_map()", m_at) != -1
		and InputMap.has_action("minimap_toggle"))

	# ---- the electric orb animates ------------------------------------------------
	var holder := Node2D.new()
	add_child(holder)
	var still: Array = []
	for el in ["", "dark", "earth", "ice", "light", "water", "wind"]:
		var orb: Node = (load("res://scene/projectiles/%smagicprojectile.tscn" % el) as PackedScene).instantiate()
		holder.add_child(orb)
		var sprite: AnimatedSprite2D = orb.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if sprite == null or not sprite.is_playing():
			still.append("%smagicprojectile" % el)
	check("all seven electric orbs play their animation (they flew as a still frame)",
		still.is_empty(), still)
	holder.queue_free()

	# ---- an update is announced -------------------------------------------------
	var was_min: int = Api.server_min_build
	var was_current: int = Api.server_current_build
	Api.server_min_build = 0
	Api.server_current_build = Api.BUILD
	var current_note: String = ApiForTests.build_notice()
	Api.server_current_build = Api.BUILD + 1
	var newer_note: String = ApiForTests.build_notice()
	Api.server_min_build = Api.BUILD + 1
	var refused_note: String = ApiForTests.build_notice()
	Api.server_min_build = was_min
	Api.server_current_build = was_current
	check("a current build says nothing", current_note == "", current_note)
	check("a newer build on the server is announced", newer_note.contains("newer version"), newer_note)
	check("a refused build says it is too old", refused_note.contains("too old"), refused_note)
	check("and the login screen shows it once it has asked",
		_func_body(_code_src("res://src/ui/menus/loginmenu.gd"), "func _check_connection_and_resume(").contains("build_notice()"))

	# ---- the revive price is read, not copied ------------------------------------
	var go: Node = (load("res://src/ui/menus/gameover.gd") as Script).new()
	check("the game-over screen's lusion price is GameConstants.REVIVE_COST",
		int(go.get("revive_cost")) == GameConstants.REVIVE_COST, go.get("revive_cost"))
	go.free()
	print("  sweep: attack, pushes, passwords, spikes, bosses, M, orbs, updates, price - all joined")


func _test_the_sweep_words() -> void:
	section("THE SWEEP — the words a player reads")

	check("counted() says 1 day, 3 days, 1,204 lusions",
		GameConstants.counted(1, "day") == "1 day" and GameConstants.counted(3, "day") == "3 days"
		and GameConstants.counted(1204, "lusion") == "1,204 lusions"
		and GameConstants.counted(2, "address", "addresses") == "2 addresses")
	var now := 1_800_000_000
	check("LocalTime.ago: just now, 5 min, 2 h, 1 day, 3 days - never '1 days' or '0 min'",
		LocalTime.ago(now - 20, now) == "just now" and LocalTime.ago(now - 300, now) == "5 min ago"
		and LocalTime.ago(now - 7200, now) == "2 h ago" and LocalTime.ago(now - 86400, now) == "1 day ago"
		and LocalTime.ago(now - 3 * 86400, now) == "3 days ago")
	var own_ago: Array = []
	for path in ["res://src/ui/friends/friendspanel.gd", "res://src/ui/staff/staffpanel.gd",
			"res://src/ui/guild/guildpanel.gd"]:
		if _code_src(path).contains("\"%d days ago\""):
			own_ago.append(path.get_file())
	check("the friends list, staff desk and guild roster ask LocalTime, not their own copy",
		own_ago.is_empty(), own_ago)

	var raw_areas: Array = []
	for id in AreaRegistry.AREAS:
		var shown: String = AreaRegistry.display_name(id)
		if shown == "" or (id in ["bossarena", "easteregg", "boss"] and shown == String(id).capitalize()):
			raw_areas.append("%s -> %s" % [id, shown])
	check("every area has a name a player reads (no 'Bossarena', no 'Easteregg')",
		raw_areas.is_empty() and AreaRegistry.AREA_NAMES.size() == AreaRegistry.AREAS.size(), raw_areas)
	var capitalised: Array = []
	for path in ["res://src/ui/menus/mapscreen.gd", "res://src/world/ladder.gd", "res://src/world/leavetown.gd",
			"res://src/ui/players/playerspanel.gd", "res://src/ui/trade/tradepanel.gd", "res://src/ui/guild/guildpanel.gd"]:
		for line in _code_src(path).split("\n"):
			if line.contains(".capitalize()") and (line.contains("area") or line.contains("where")
					or line.contains("get_basename()") or line.contains("_area")):
				capitalised.append("%s: %s" % [path.get_file(), line.strip_edges()])
	check("and no screen capitalises an area id itself", capitalised.is_empty(), capitalised)

	var sign_text := FileAccess.get_file_as_string("res://scene/interactables/sign.tscn")
	# THE CROWNED BEHOLDER, by name (0.11.6). This check used to keep "Beholder"
	# OFF the sign, because no monster in the game was called one; the owner
	# named them on 8 Oct ("this is a crowned beholder"), so it holds the
	# opposite now: the sign and all seven bosses say Crowned Beholder.
	check("the town sign names the Crowned Beholders", sign_text.contains("Crowned Beholders"), sign_text)
	var unnamed: Array = []
	for boss_id in ["boss", "lightboss", "windboss", "waterboss", "iceboss", "earthboss", "fireboss"]:
		var boss_data := load("res://data/enemies/%s.tres" % boss_id) as EnemyData
		if boss_data == null or not boss_data.display_name.ends_with("The Crowned Beholder"):
			unnamed.append("%s: %s" % [boss_id, boss_data.display_name if boss_data else "missing"])
	check("  and every one of the seven bosses is a Crowned Beholder by name", unnamed.is_empty(), unnamed)
	var over := FileAccess.get_file_as_string("res://scene/ui/menus/gameover.tscn")
	check("the game-over screen reads GAME OVER and 'Return to character select'",
		over.contains("\"GAME OVER\"") and over.contains("\"Return to character select\""))

	var x_buttons: Array = []
	for path in _all_files_under("res://scene/ui", ".tscn"):
		if FileAccess.get_file_as_string(path).contains("text = \"x\"\n"):
			x_buttons.append(path.get_file())
	check("every close button is the same ×", x_buttons.is_empty(), x_buttons)

	var rods: Array = []
	for f in DirAccess.get_files_at("res://data/items/fishing"):
		if f.ends_with(".tres") and FileAccess.get_file_as_string("res://data/items/fishing/" + f).contains("Requires fishing level"):
			rods.append(f)
	check("no rod claims a fishing level it does not require (rods raise reach, they gate nothing)",
		rods.is_empty(), rods)

	var labels: Dictionary = (load("res://src/ui/kingdom/kingdomboard.gd") as Script).get_script_constant_map().get("REASON_LABELS", {})
	check("the kingdom board has words for founding a guild and gold taken back by staff",
		labels.has("guild_found") and labels.has("staff_gold"), labels.keys())

	var chat: Node = (load("res://scene/ui/chat/chatpanel.tscn") as PackedScene).instantiate()
	check("the guild tab no longer says it is waiting on guilds",
		not chat._tab_hint("guild").contains("Waiting"), chat._tab_hint("guild"))
	check("  and a one-second wait is '1 second'", chat._readable_wait(1) == "1 second", chat._readable_wait(1))
	chat.free()

	var stats_code := _code_src("res://src/ui/statsscreen.gd")
	check("the stats screen shows a skill's progress as a percentage, not 'n/100'",
		not stats_code.contains("/100") and stats_code.contains("%d%%")
		and not FileAccess.get_file_as_string("res://scene/ui/statsscreen.tscn").contains("0/100"))
	check("  and says Health and Defence like the rest of the game",
		FileAccess.get_file_as_string("res://scene/ui/statsscreen.tscn").contains("\"Health:\"")
		and FileAccess.get_file_as_string("res://scene/ui/statsscreen.tscn").contains("\"Defence:\""))

	var talking: Array = []
	for path in ["res://src/ui/chat/chatpanel.gd", "res://src/ui/friends/friendspanel.gd", "res://src/ui/guild/guildpanel.gd"]:
		var code := _code_src(path)
		if code.contains("Is it running?") or not code.contains("no_answer_text()"):
			talking.append(path.get_file())
	check("chat, friends and guilds say 'no answer' in a player's words, not 'Is it running?'",
		talking.is_empty(), talking)

	var tip: Control = (load("res://scene/ui/inventory/itemtooltip.tscn") as PackedScene).instantiate()
	var sword := ItemData.new()
	sword.item_id = "sweeptest_sword"
	sword.damage = 32
	sword.bonus_damage_percent = 2
	check("a sword reads '32 Damage, +2% Damage Bonus', not '32 Damage, +2% Damage'",
		ItemTooltip._requirement_lines(sword) == "32 Damage, +2% Damage Bonus", ItemTooltip._requirement_lines(sword))
	tip.free()

	var inv_code := _code_src("res://src/ui/inventory/inventoryscreen.gd")
	check("the class refusal joins with 'or', like the tooltip ('Only warriors or tanks')",
		inv_code.contains("\" or \".join(names)"))
	check("the trash asks in its own words, not Godot's 'Please Confirm...'",
		_code_src("res://src/ui/inventory/trashslot.gd").contains("confirm_dialog.title = "))
	check("a shop row says the rarity and 'Armour', like the tooltip",
		_code_src("res://src/ui/shop/shopinventory.gd").contains("GameConstants.rarity_name("))
	print("  sweep: plurals, areas, sign, game over, ×, rods, board, chat, stats, errors, tooltip, shop")


# =============================================================================
# THE BROWSER BUILD
# =============================================================================
# Most of what the browser build needs can only be watched in a browser: it was
# (headless Chromium, the 4.6.1 web templates, the real API behind web/serve.py)
# and CLAUDE.md has what was measured. What is held here is every wire that a
# desktop run can see - the preset, the loader, the address, the rows a browser
# cannot use, the save a closing tab sends, and the one bug an export had that
# the editor never shows.

func _test_the_windows_build() -> void:
	section("THE WINDOWS BUILD - one file to hand out, without the suite in it")

	# Day 1: "we need that pc export - this game is not playable on a phone".
	# The project had a Web preset and nothing else. Exported and booted from
	# the sandbox: one 113 MB .exe, the pack inside it, every item and area
	# loaded, and nothing from src/tools or scene/tests stored.
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	var win := ""
	for sec in presets.get_sections():
		if str(presets.get_value(sec, "platform", "")) == "Windows Desktop":
			win = sec
	check("there is a Windows preset", win != "", presets.get_sections())
	if win == "":
		return
	var opts := win + ".options"
	var excluded: String = str(presets.get_value(win, "exclude_filter", ""))
	check("  the suite and the tools do not ship", excluded.contains("src/tools/*")
		and excluded.contains("scene/tests/*"), excluded)
	var out_path: String = str(presets.get_value(win, "export_path", ""))
	check("  it exports under builds/, which git ignores - an export holds the private art pack",
		out_path.begins_with("builds/") and out_path.ends_with(".exe")
		and FileAccess.get_file_as_string("res://.gitignore").contains("\nbuilds/"), out_path)
	check("  one file to hand out: the pack is inside the .exe",
		presets.get_value(opts, "binary_format/embed_pck", false) == true)
	check("  64-bit", str(presets.get_value(opts, "binary_format/architecture", "")) == "x86_64")
	check("  named Elusion RPG, by Elusion Studios",
		str(presets.get_value(opts, "application/product_name", "")) == "Elusion RPG"
		and str(presets.get_value(opts, "application/company_name", "")) == "Elusion Studios")
	# THE VERSION WINDOWS SHOWS IS THE GAME'S OWN. Api.DISPLAY_VERSION is the
	# one players read; a release that bumps it and not this would show an old
	# number in the file's properties.
	var version: String = str(presets.get_value(opts, "application/file_version", ""))
	check("  and its version is the game's (Api.DISPLAY_VERSION)",
		version.begins_with(Api.DISPLAY_VERSION + ".") or version == Api.DISPLAY_VERSION,
		[version, Api.DISPLAY_VERSION])
	print("  windows: one .exe, the suite left out, the game's own name and version")


func _test_the_browser_build() -> void:
	section("THE BROWSER BUILD — one address, a loader, and a tab that can close")

	# ---- the preset ------------------------------------------------------------
	var presets := ConfigFile.new()
	var read_err: int = presets.load("res://export_presets.cfg")
	check("export_presets.cfg is in the project", read_err == OK, read_err)
	var web := ""
	for sec in presets.get_sections():
		if str(presets.get_value(sec, "platform", "")) == "Web":
			web = sec
	check("it has a Web preset", web != "", presets.get_sections())
	var opts := web + ".options"
	check("  built without threads: a threaded export needs isolation headers, and it took "
		+ "40 s to reach the town in Chromium against 4.4 s without",
		presets.get_value(opts, "variant/thread_support", true) == false)
	var shell: String = str(presets.get_value(opts, "html/custom_html_shell", ""))
	check("  with Elusion's own loader as its page", shell == "res://web/shell.html"
		and FileAccess.file_exists(shell), shell)
	check("  and no service worker: one would serve yesterday's build from its cache after a refresh",
		presets.get_value(opts, "progressive_web_app/enabled", true) == false)
	var excluded: String = str(presets.get_value(web, "exclude_filter", ""))
	check("  the suite and the tools do not ship", excluded.contains("src/tools/*")
		and excluded.contains("scene/tests/*"), excluded)
	var out_path: String = str(presets.get_value(web, "export_path", ""))
	check("  and it exports under builds/, which git ignores - an export holds the private art pack",
		out_path.begins_with("builds/") and FileAccess.get_file_as_string("res://.gitignore").contains("\nbuilds/"),
		out_path)

	# ---- the loader --------------------------------------------------------------
	var page: String = FileAccess.get_file_as_string("res://web/shell.html")
	var missing_names: Array = []
	for placeholder in ["$GODOT_URL", "$GODOT_CONFIG", "$GODOT_THREADS_ENABLED", "$GODOT_HEAD_INCLUDE"]:
		if not page.contains(placeholder):
			missing_names.append(placeholder)
	check("the loader carries every name the exporter fills in", missing_names.is_empty(), missing_names)
	check("  and steps aside when the game says it is drawing (window.elusionReady)",
		page.contains("window.elusionReady = "))
	check("  and gives the tab back its name then - the engine renames it after the project",
		page.contains("const pageTitle = document.title;") and page.contains("document.title = pageTitle;"))
	check("  and tells a tab left open that a new build is up (0.50.1): the game files' dates, noted as they load "
		+ "and asked again past the cache, and a Reload button",
		page.contains("function watchForNewBuild()") and page.contains("cache: 'no-store'")
		and page.contains("'Last-Modified'") and page.contains("<div id=\"update\" role=\"status\"")
		and page.contains("id=\"update-reload\"") and page.contains("window.elusionCheckForUpdate = ")
		and page.contains("\twatchForNewBuild();\n\tstatus.textContent = 'Downloading the game...';"))
	var art_at: int = page.find("data:image/png;base64,")
	var art_end: int = page.find("\"", art_at)
	var embedded: PackedByteArray = Marshalls.base64_to_raw(
		page.substr(art_at + 22, art_end - art_at - 22)) if art_at != -1 else PackedByteArray()
	check("  its picture is the login screen's own (art/menu/original size.png) - re-embed it if that changes",
		embedded == FileAccess.get_file_as_bytes("res://art/menu/original size.png"), embedded.size())
	var login_code := _code_src("res://src/ui/menus/loginmenu.gd")
	var login_ready := _func_body(login_code, "func _ready()")
	check("the login screen tells the loader once it has drawn, in a browser",
		login_ready.contains("WebPage.in_browser()") and login_ready.contains("WebPage.mark_ready()")
		and login_ready.contains("frame_post_draw"))

	# ---- one address -------------------------------------------------------------
	check("a page's origin is the API's address",
		ApiForTests.web_base_url("https://play.example.com") == "https://play.example.com"
		and ApiForTests.web_base_url("http://localhost:8060/") == "http://localhost:8060",
		ApiForTests.web_base_url("http://localhost:8060/"))
	check("  and a page from disk (origin \"null\") or no page at all is no address",
		ApiForTests.web_base_url("null") == "" and ApiForTests.web_base_url("") == ""
		and ApiForTests.web_base_url("file://") == "")
	var api_code := _code_src("res://src/systems/api.gd")
	var resolve := _func_body(api_code, "static func _resolve_base_url()")
	check("  asked for first in a browser, before any override that cannot work there",
		resolve.find("OS.has_feature(\"web\")") != -1
		and resolve.find("OS.has_feature(\"web\")") < resolve.find("get_cmdline_args()")
		and resolve.contains("WebPage.origin()"))

	# ---- off the web, nothing happens --------------------------------------------
	var WebPageScript: Script = load("res://src/systems/webpage.gd")
	check("the page helper does nothing on the desktop",
		not WebPageScript.in_browser() and WebPageScript.origin() == ""
		and WebPageScript.watch_leaving(func() -> void: pass).is_empty()
		and not WebPageScript.send_now("http://x", "PUT", PackedStringArray(), "{}"))
	check("  and neither does a send meant for a closing page",
		not Api.send_before_leaving("PUT", "/api/save", {}))

	# ---- rows a browser cannot use ---------------------------------------------
	var Options: Script = load("res://src/ui/menus/optionsscreen.gd")
	var on_web: Array = Options.rows_hidden_on("Web")
	check("in a browser, Options drops window size, V-Sync, the renderer and the graphics API",
		on_web.has("window") and on_web.has("vsync") and on_web.has("renderer") and on_web.has("api"),
		on_web)
	check("  on Windows it drops nothing, elsewhere only the graphics API",
		Options.rows_hidden_on("Windows").is_empty() and Options.rows_hidden_on("Linux") == ["api"],
		[Options.rows_hidden_on("Windows"), Options.rows_hidden_on("Linux")])
	var screen: Node = (load("res://scene/ui/menus/optionsscreen.tscn") as PackedScene).instantiate()
	screen.api_row = screen.get_node("%apirow")
	screen.screen_row = screen.get_node("%screenrow")
	screen.window_size = screen.get_node("%windowsize")
	screen.vsync_mode = screen.get_node("%vsyncmode")
	screen.renderer = screen.get_node("%renderer")
	screen.renderer_note = screen.get_node("%renderernote")
	screen._hide_rows_for("Web")
	var still_shown: Array = []
	for row in [screen.get_node("%windowsize").get_parent(), screen.get_node("%vsyncmode").get_parent(),
			screen.get_node("%renderer").get_parent(), screen.get_node("%renderernote"), screen.get_node("%apirow")]:
		if (row as CanvasItem).visible:
			still_shown.append(str(row.name))
	check("  and the screen really hides those rows", still_shown.is_empty(), still_shown)
	check("  but keeps the window mode and the frame cap, which a browser honours",
		(screen.get_node("%windowmode").get_parent() as CanvasItem).visible
		and (screen.get_node("%framecap").get_parent() as CanvasItem).visible)
	check("  and drops the monitor picker - a page is on whatever screen its browser is",
		on_web.has("screen") and not (screen.get_node("%screenrow") as CanvasItem).visible)
	screen.free()
	var report := {"refresh": -1.0, "fps": 59.6, "vsync": "on", "cap": 0, "overridden": false}
	check("  its readout says the browser paces the frames, not 'Screen ? Hz - V-Sync on'",
		Options.pacing_line(report, "Web") == "Drawing 60 fps  -  paced by the browser",
		Options.pacing_line(report, "Web"))
	check("  and on the desktop reads as it did",
		Options.pacing_line({"refresh": 60.0, "fps": 60.0, "vsync": "on", "cap": 144, "overridden": false}, "Windows")
			== "Screen 60 Hz  -  drawing 60 fps  -  V-Sync on, cap 144",
		Options.pacing_line({"refresh": 60.0, "fps": 60.0, "vsync": "on", "cap": 144, "overridden": false}, "Windows"))
	var login: Node = (load("res://scene/ui/menus/loginmenu.tscn") as PackedScene).instantiate()
	login._hide_exit_row()
	check("the login screen's Exit row and the rule above it go in a browser (a page cannot close its tab)",
		not (login.get_node("%exitbutton").get_parent() as CanvasItem).visible
		and not (login.get_node("centercontainer/mainpanel/margincontainer/vboxcontainer/hseparator2") as CanvasItem).visible
		and (login.get_node("%loginbutton") as CanvasItem).visible)
	login.free()
	check("  and only there", login_ready.find("_hide_exit_row()") > login_ready.find("if WebPage.in_browser():")
		and login_ready.find("if WebPage.in_browser():") != -1)

	# ---- a closing tab still saves ---------------------------------------------
	var ss := ServerStorage.new()
	var slot := {"character": "warrior", "level": 5, "hp": 40, "max_hp": 60,
		"inventory": [{"item_id": "healthpotion", "quantity": 2}, null],
		"explored": {"field": "abc"}, "area": "field"}
	var payload := {"character_slots": [slot, null, null, null],
		"account_data": {"lusions": 3, "bank_inventory": []}}
	var first: Array = ss.requests_before_leaving(payload)
	var paths: Array = first.map(func(r: Dictionary) -> String: return str(r["path"]))
	check("a closing page sends every section the server has not confirmed",
		paths.size() == 3 and paths.has("/api/player/status")
		and paths.has("/api/account/lusions") and paths.has("/api/save"),
		paths)
	check("  and neither the bag nor the bank - they are the server's",
		not paths.has("/api/character/inventory") and not paths.has("/api/account/bank"), paths)
	check("  the save last and without the explored map (64 KB of keepalive, and the map can fill it)",
		not paths.is_empty() and paths[-1] == "/api/save" and not (first[-1]["body"] as Dictionary).has("explored")
		and (first[-1]["body"] as Dictionary).get("area", "") == "field",
		first[-1]["body"] if not first.is_empty() else {})
	check("  as PUTs", first.all(func(r: Dictionary) -> bool: return r["method"] == "PUT"))
	check("  and not twice when the page hides and then unloads",
		ss.requests_before_leaving(payload).is_empty())
	var fp := JSON.stringify(ss._status_body(0, slot))
	ss._record_push("status:0", true, fp)
	slot["hp"] = 30
	var again: Array = ss.requests_before_leaving(payload)
	check("  vitals changed since go again, and only the vitals",
		again.size() == 1 and again[0]["path"] == "/api/player/status", again)
	var hurt := JSON.stringify(ss._status_body(0, slot))
	ss._record_push("status:0", true, hurt)
	ss._record_push("status:0", true, "the server moved on to other vitals")
	slot["hp"] = 40
	var back: Array = ss.requests_before_leaving(payload)
	check("  a confirmed push clears the mark, so vitals put back as they were are not taken for sent",
		back.size() == 1 and back[0]["path"] == "/api/player/status", back)
	slot["inventory"] = [null, {"item_id": "healthpotion", "quantity": 2}]
	check("  and a bag changed since sends nothing at all",
		ss.requests_before_leaving(payload).is_empty())
	var ss_code := _code_src("res://src/systems/serverstorage.gd")
	check("  it reads the same section lists a push walks, so the two cannot disagree",
		_func_body(ss_code, "func _push_slot(").contains("_slot_sections(index, slot)")
		and _func_body(ss_code, "func _push_account(").contains("_account_sections(account)")
		and _func_body(ss_code, "func requests_before_leaving(").contains("_slot_sections(index, slot)"))

	var leave_script := GDScript.new()
	leave_script.source_code = "extends SaveStorage\nvar asked: int = 0\nvar saves: int = 0\n" \
		+ "func requests_before_leaving(_payload: Dictionary) -> Array:\n\tasked += 1\n\treturn []\n" \
		+ "func save(_payload: Dictionary) -> bool:\n\tsaves += 1\n\treturn true\n"
	leave_script.reload()
	var store = leave_script.new()
	var was_storage = CharacterData.storage
	var was_pending: bool = CharacterData._save_pending
	CharacterData.storage = store
	CharacterData._save_pending = false
	CharacterData._on_page_leaving()
	var asked_idle: int = store.asked
	CharacterData._save_pending = true
	CharacterData._on_page_leaving()
	CharacterData.storage = was_storage
	CharacterData._save_pending = was_pending
	check("CharacterData asks for them on leaving even with nothing queued (a push in flight dies with the tab)",
		asked_idle == 1, asked_idle)
	check("  and flushes the queued save as well, for a page that comes back",
		store.asked == 2 and store.saves == 1, [store.asked, store.saves])
	var cd_code := _code_src("res://src/systems/characterdata.gd")
	check("  it is watching: _ready() hands _on_page_leaving to the page",
		_func_body(cd_code, "func _ready()").contains("WebPage.watch_leaving(_on_page_leaving)"))
	check("  and each request goes out through Api.send_before_leaving()",
		_func_body(cd_code, "func _on_page_leaving()").contains("Api.send_before_leaving("))

	# ---- nothing loads ahead where it would be the wait itself -------------------
	check("this build loads areas in the background (a desktop build has threads)",
		_AreaRegistryCode.loads_in_background())
	var ar_code := _code_src("res://src/systems/arearegistry.gd")
	var prefetch_body := _func_body(ar_code, "func prefetch(")
	check("  a build without threads asks for nothing ahead - there the request IS the load",
		ar_code.contains("not OS.has_feature(\"nothreads\")")
		and prefetch_body.find("if not loads_in_background():") != -1
		and prefetch_body.find("if not loads_in_background():") < prefetch_body.find("_start_prefetch("))
	var enter := _func_body(_code_src("res://src/ui/menus/characterselect.gd"), "func _enter_world(")
	var gate := "if not AreaRegistry.is_ready(WORLD_AREA):"
	var first_gate := enter.find(gate)
	var second_gate := enter.find(gate, first_gate + 1) if first_gate != -1 else -1
	var takes := enter.find("AreaRegistry.scene_for(WORLD_AREA)")
	var drawn := enter.find("await get_tree().process_frame", second_gate) if second_gate != -1 else -1
	check("  so character select says 'Loading the world...' whenever the town is not ready - not only while it loads",
		first_gate != -1 and enter.substr(first_gate, gate.length() + 24).contains("_show_loading(idx)"))
	check("  and lets that label draw before a load that holds the screen - two frames, the first is the click's own",
		second_gate != -1 and drawn != -1 and drawn < takes
		and enter.substr(second_gate, drawn - second_gate).contains("in 2:"), [first_gate, second_gate, drawn, takes])
	# A LOAD THAT STOPS IS NOT TAKEN (0.74.2). 0.74.1 waited three seconds and
	# then took the town with scene_for() - and the owner's take hung for good:
	# waiting in load_threaded_get() cannot finish a deadlocked load. The wait
	# goes by the frame for as long as the load moves; one that stops for
	# STUCK_SECONDS is said on the label and left, never taken.
	var poll := enter.find("while not AreaRegistry.is_ready(WORLD_AREA) and AreaRegistry.is_loading(WORLD_AREA):")
	var stuck := enter.find("STUCK_SECONDS * 1000.0", poll) if poll != -1 else -1
	var gives_up := enter.find("return", stuck) if stuck != -1 else -1
	var in_loop := enter.substr(poll, second_gate - poll) if poll != -1 and second_gate > poll else ""
	var Select: Script = load("res://src/ui/menus/characterselect.gd") as Script
	var stuck_for: float = float(Select.get_script_constant_map().get("STUCK_SECONDS", 0.0))
	check("  and waits by the frame while the load moves; one that stops is said, never taken",
		poll != -1 and stuck != -1 and gives_up != -1 and gives_up < second_gate and second_gate < takes
		and not in_loop.contains("break") and not in_loop.contains("scene_for(")
		and not enter.contains("load_threaded_get(") and stuck_for >= 5.0 and stuck_for <= 60.0,
		[poll, stuck, gives_up, second_gate, takes, stuck_for])
	check("  in words the player can act on, and a line in the log",
		in_loop.contains("close the game and open it again") and in_loop.contains("print(\"[WORLD]"))

	# ---- the bug an export had and the editor never showed ------------------------
	var walkers: Array = []
	for path in _all_gd_under("res://src"):
		if path.begins_with("res://src/tools/"):
			continue
		if _code_src(path).contains("list_dir_begin("):
			walkers.append(path.get_file())
	check("nothing that ships walks res:// with DirAccess - an export lists every .tres as .tres.remap",
		walkers.is_empty(), walkers)
	check("  the item registry lists with ResourceLoader.list_directory(), which gives the editor's names",
		_func_body(_code_src("res://src/systems/itemregistry.gd"), "func _scan_folder(").contains("ResourceLoader.list_directory("))

	# ---- an arrival draws the right map from its first frame -----------------
	var player_code := _code_src("res://src/characters/player.gd")
	check("the player puts its camera in place at once - it runs on the physics clock, and "
		+ "an area's first frame came before the first tick (the map from its corner, unzoomed)",
		_func_body(player_code, "func snap_camera(").contains("force_update_scroll()")
		and _func_body(player_code, "func _ready(").contains("snap_camera()"))
	var place := _func_body(ar_code, "func place_player(")
	check("  a placed player is told so after the position, then the camera follows",
		place.find("global_position = spawn_position") != -1
		and place.find("reset_physics_interpolation()") > place.find("global_position = spawn_position")
		and place.find("snap_camera()") > place.find("reset_physics_interpolation()"))
	var field_code := _func_body(_code_src("res://src/world/field.gd"), "func _position_player_at_spawn(")
	var tele_code := _func_body(_code_src("res://src/world/teleporter.gd"), "func _on_body_entered(")
	check("  and so do the field's arrival portal and an in-world teleporter",
		field_code.find("snap_camera()") > field_code.find("player.reset_physics_interpolation()")
		and field_code.find("player.reset_physics_interpolation()") != -1
		and tele_code.find("snap_camera()") > tele_code.find("body.reset_physics_interpolation()")
		and tele_code.find("body.reset_physics_interpolation()") != -1)
	# BLACK AT RUNTIME, NOT IN project.godot. Set there, the editor drew every
	# gap in every tile black as well; see the MAP BACKDROP section.
	check("  and a frame with no scene in it yet is black, not the engine's grey",
		RenderingServer.get_default_clear_color().is_equal_approx(Color(0, 0, 0, 1)),
		RenderingServer.get_default_clear_color())

	# ---- pictures in chat, the browser's way ------------------------------------
	var Chat: Script = load("res://src/ui/chat/chatpanel.gd")
	check("in a browser the chat box points at + and dropping a file, not Ctrl+V (a page gets no pictures from the clipboard)",
		Chat.entry_placeholder(true).contains("drop") and not Chat.entry_placeholder(true).contains("Ctrl+V")
		and Chat.entry_placeholder(false).contains("Ctrl+V"))
	var chat_code := _code_src("res://src/ui/chat/chatpanel.gd")
	var image_pressed := _func_body(chat_code, "func _on_image_pressed(")
	check("  + asks the browser's own picker there, before any FileDialog (which shows the engine's empty virtual disk)",
		image_pressed.find("if WebPage.in_browser():") != -1
		and image_pressed.find("WebPage.pick_file(") > image_pressed.find("if WebPage.in_browser():")
		and image_pressed.find("WebPage.pick_file(") < image_pressed.find("FileDialog.new()"))
	var picked := _func_body(chat_code, "func _on_web_file_picked(")
	check("  and a picked file is attached exactly as a dropped one is",
		picked.find("store_buffer(bytes)") != -1 and picked.find("_attach_file(path)") > picked.find("store_buffer(bytes)"))
	check("  the picker does nothing on the desktop",
		WebPageScript.pick_file(".png", func(_b: PackedByteArray, _n: String) -> void: pass).is_empty())

	# ---- a ticked box under the pointer ----------------------------------------
	# Seen in the browser first, true everywhere: the theme had no hover_pressed
	# style, so a toggled button under the mouse fell back to the engine's own -
	# no border, the text pushed right, and "Remember me" read "Remember m".
	var ui_theme: Theme = load("res://assets/themes/rpg_ui_theme.tres")
	check("a pressed button under the pointer keeps the game's pressed look (no engine fallback)",
		ui_theme.has_stylebox("hover_pressed", "Button")
		and ui_theme.get_stylebox("hover_pressed", "Button") == ui_theme.get_stylebox("pressed", "Button")
		and ui_theme.has_color("font_hover_pressed_color", "Button")
		and ui_theme.get_color("font_hover_pressed_color", "Button") == ui_theme.get_color("font_pressed_color", "Button"))
	print("  browser: preset, loader, one address, rows, a closing tab, no loading ahead, the registry, arrivals, chat pictures, theme")


# =============================================================================
# LEAVING WAITS FOR THE SAVE
# =============================================================================
# flush_save() STARTS a push. Closing the window quit in the same frame (a bag
# changed and closed at once kept its old bag on the real server), and a logout
# raced its revoke against the push. Both now wait, bounded, for the server.

func _test_leaving_waits_for_the_save() -> void:
	section("LEAVING — closing the window and logging out wait for the save")

	var store_script := GDScript.new()
	store_script.source_code = "extends SaveStorage\nvar saves: int = 0\nvar left: int = 0\n" \
		+ "func save(_payload: Dictionary) -> bool:\n\tsaves += 1\n\treturn true\n" \
		+ "func is_pushing() -> bool:\n\tleft -= 1\n\treturn left > 0\n"
	store_script.reload()
	var store = store_script.new()
	var was_storage = CharacterData.storage
	var was_pending: bool = CharacterData._save_pending
	CharacterData.storage = store
	CharacterData._save_pending = true
	store.left = 6
	var all_went: bool = await CharacterData.finish_saving(5.0)
	check("finish_saving() writes the queued save and waits until the push is through",
		store.saves == 1 and store.left <= 0 and all_went, [store.saves, store.left, all_went])

	store.left = 1_000_000
	var t0 := Time.get_ticks_msec()
	var stuck_went: bool = await CharacterData.finish_saving(0.2)
	var waited: int = Time.get_ticks_msec() - t0
	check("  and gives up on a server that never answers, at the limit it was given",
		not stuck_went and waited >= 180 and waited < 1500, [stuck_went, waited])

	store.left = 5
	CharacterData._save_pending = true
	var quit_state: Array = []
	var fake_quit := func() -> void: quit_state.append(store.left)
	CharacterData._quitting = false
	await CharacterData._quit_after_saving(fake_quit)
	check("closing the window quits only once the push is through",
		quit_state.size() == 1 and int(quit_state[0]) <= 0 and store.saves == 2, [quit_state, store.saves])
	await CharacterData._quit_after_saving(fake_quit)
	check("  and a second press of the X does not quit twice", quit_state.size() == 1, quit_state)
	CharacterData._quitting = false
	CharacterData.storage = was_storage
	CharacterData._save_pending = was_pending

	var cd_code := _code_src("res://src/systems/characterdata.gd")
	check("the engine no longer quits on the X by itself",
		_func_body(cd_code, "func _ready()").contains("set_auto_accept_quit(false)"))
	var notif := _func_body(cd_code, "func _notification(")
	check("  the X goes to _quit_after_saving()", notif.find("NOTIFICATION_WM_CLOSE_REQUEST") != -1
		and notif.find("_quit_after_saving()") > notif.find("NOTIFICATION_WM_CLOSE_REQUEST"))
	var quitting := _func_body(cd_code, "func _quit_after_saving(")
	check("  which takes the live character's state first, as a logout does",
		quitting.find("save_character_state(player)") != -1
		and quitting.find("save_character_state(player)") < quitting.find("finish_saving("))

	var logout := _func_body(_code_src("res://src/ui/characterhud.gd"), "func _on_logout_pressed(")
	var waits := logout.find("await CharacterData.finish_saving()")
	check("a logout waits for the save before it clears the session and revokes the token",
		waits != -1 and waits < logout.find("CharacterData.clear_current_user()")
		and waits < logout.find("await Api.logout()"))
	check("ServerStorage says when a push is still on its way",
		ServerStorage.new().is_pushing() == false
		and _func_body(_code_src("res://src/systems/serverstorage.gd"), "func is_pushing(").contains("_has_queued"))
	print("  leaving: finish_saving, the X, a second X, logout order")


# =============================================================================
# SHOWN SKILL XP ROUNDS LIKE THE SERVER
# =============================================================================
# The server grants int(raw x specialty) per batch SkillTrainer sends
# (proficient_amount() in app.py). The bar used to round each hit, with a floor
# of 1, so a tank's 1-point hits showed 1 against the server's 1.5.

func _test_skill_xp_rounds_like_the_server() -> void:
	section("SKILL XP — the bar rounds a batch the way the server grants it")

	var trainer: Node = (load("res://src/systems/skilltrainer.gd") as Script).new()
	# Earned on slot 0, whatever this run was left playing.
	var kept_slot: int = CharacterData.active_character_index
	CharacterData.active_character_index = 0
	var shown := 0
	var steps: Array = []
	for i in 10:
		var step: int = trainer.report("defense", 1, 1.5)
		steps.append(step)
		shown += step
	check("ten 1-point hits at a tank's 1.5 show 15, the server's int(10 x 1.5) - not 10",
		shown == 15 and steps.min() >= 1 and steps.max() <= 2, [shown, steps])
	var magic := 0
	for i in 7:
		magic += trainer.report("magic", 3, 1.5)
	check("  seven 3-point spells show 31, int(21 x 1.5) - not 28, rounding each",
		magic == 31, magic)
	check("  and a hit worth nothing shows nothing (it used to show 1)",
		trainer.report("defense", 0, 1.5) == 0)
	var plain := 0
	for i in 5:
		plain += trainer.report("agility", 7)
	check("  with no specialty, what is shown is what was earned", plain == 35, plain)
	check("  and the raw amounts are what waits for the server",
		int(trainer._pending["defense"]) == 10 and int(trainer._pending["magic"]) == 21
		and int(trainer._pending["agility"]) == 35, trainer._pending)
	# WHOSE IT IS (0.56.0): the slot it was earned on, and the account.
	var earned_on: int = int(trainer._pending_slot)
	CharacterData.active_character_index = earned_on + 1
	trainer.report("defense", 4)
	var aside: Array = trainer._set_aside
	check("XP earned before Switch character goes with the slot it was earned on, not the one picked next",
		aside.size() == 1 and int(aside[0][0]) == earned_on and int(aside[0][1]["defense"]) == 10
		and int(trainer._pending["defense"]) == 4 and int(trainer._pending_slot) == earned_on + 1, [aside, trainer._pending])
	CharacterData.active_character_index = kept_slot
	trainer._pending_user = "somebody_else_entirely"
	trainer.report("magic", 2)
	check("  and another account's XP is forgotten, never sent as the one signed in now",
		trainer._set_aside.is_empty() and int(trainer._pending["defense"]) == 0 and int(trainer._pending["magic"]) == 2,
		[trainer._set_aside, trainer._pending])
	trainer.free()

	var flush := _func_body(_code_src("res://src/systems/skilltrainer.gd"), "func flush(")
	var send := _func_body(_code_src("res://src/systems/skilltrainer.gd"), "func _send(")
	check("a flushed batch starts the rounding again, as the server does per batch - and each slot's goes as that slot",
		flush.find("_shown = _empty()") != -1 and flush.find("_shown = _empty()") < flush.find("await _send(")
		and send.contains("var body: Dictionary = {\"slot\": slot}") and send.contains("await Api.post("))
	var player_code := _code_src("res://src/characters/player.gd")
	var defense := _func_body(player_code, "func gain_defense_xp(")
	var magic_body := _func_body(player_code, "func gain_magic_xp(")
	check("defence and magic show what SkillTrainer answers, with the class specialty",
		defense.contains("SkillTrainer.report(\"defense\", amount,") and magic_body.contains("SkillTrainer.report(\"magic\", amount,")
		and not defense.contains("maxi(1, int(amount") and not magic_body.contains("maxi(1, int(amount"))
	print("  skill xp: batch rounding, zero, no specialty, raw pending, flush, callers")



func _test_game_keys_are_not_menu_keys() -> void:
	section("GAME KEYS — walking and attacking do not work a clicked menu")

	# project.godot binds WASD and the arrows to ui_left/right/up/down as well
	# as the move_ actions, and Space to ui_accept as well as attack. So a
	# control that kept the focus from a click took every step as menu
	# navigation. Built here the way a panel is: two buttons in a column, a
	# slider and a text box, on a layer of their own.
	var HUD: Script = load("res://src/ui/characterhud.gd") as Script
	var layer := CanvasLayer.new()
	var column := VBoxContainer.new()
	var first := Button.new()
	first.text = "first"
	var second := Button.new()
	second.text = "second"
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = 0.5
	slider.custom_minimum_size = Vector2(120, 16)
	var box := LineEdit.new()
	box.custom_minimum_size = Vector2(120, 24)
	for node in [first, second, slider, box]:
		column.add_child(node)
	layer.add_child(column)
	add_child(layer)
	# A frame, so the column has laid out: focus moves by position.
	await get_tree().process_frame
	await get_tree().process_frame
	var presses := [0]
	first.pressed.connect(func() -> void: presses[0] += 1)
	var viewport: Viewport = get_viewport()

	# A stand-in for the HUD's _input: the real HUD cannot join the tree here,
	# since its _ready() starts the server polls. Its _input is one call to the
	# static below, checked by text at the end.
	var hand_back := GDScript.new()
	hand_back.source_code = "extends Node\nvar hud: Script\n" \
		+ "func _input(event: InputEvent) -> void:\n\thud.release_for_world_key(event, get_viewport())\n"
	hand_back.reload()

	var press := func(code: Key, unicode: int = 0) -> void:
		for down in [true, false]:
			var key := InputEventKey.new()
			key.keycode = code
			key.physical_keycode = code
			key.unicode = unicode
			key.pressed = down
			viewport.push_input(key)

	# ---- WITHOUT IT: the bug, reproduced, so the checks below mean something ----
	first.grab_focus()
	press.call(KEY_S)
	var moved_to: Control = viewport.gui_get_focus_owner()
	first.grab_focus()
	press.call(KEY_SPACE, 32)
	slider.grab_focus()
	press.call(KEY_D)
	check("without it, S walks the focus down the column, Space presses the button, D turns the slider",
		moved_to == second and presses[0] == 1 and slider.value > 0.5,
		[str(moved_to.name) if moved_to else "nobody", presses[0], slider.value])

	# ---- WITH IT ----
	var watcher := Node.new()
	watcher.set_script(hand_back)
	watcher.hud = HUD
	add_child(watcher)
	presses[0] = 0
	slider.value = 0.5
	first.grab_focus()
	press.call(KEY_S)
	check("a step takes the focus off a clicked button instead of moving it",
		viewport.gui_get_focus_owner() == null, viewport.gui_get_focus_owner())
	first.grab_focus()
	press.call(KEY_DOWN)
	check("  the arrow keys as well", viewport.gui_get_focus_owner() == null)
	first.grab_focus()
	press.call(KEY_SPACE, 32)
	check("Space attacks and presses nothing", presses[0] == 0, presses[0])
	slider.grab_focus()
	press.call(KEY_D)
	press.call(KEY_RIGHT)
	check("walking right leaves a clicked slider where it was", is_equal_approx(slider.value, 0.5), slider.value)
	box.grab_focus()
	press.call(KEY_W, 119)
	press.call(KEY_SPACE, 32)
	press.call(KEY_D, 100)
	check("a text box keeps the keyboard: the keys are letters there",
		viewport.gui_get_focus_owner() == box and box.text == "w d", [box.text])
	box.editable = false
	box.grab_focus()
	press.call(KEY_A, 97)
	check("  but not one that cannot be typed in", viewport.gui_get_focus_owner() == null)
	first.grab_focus()
	press.call(KEY_ENTER)
	press.call(KEY_TAB)
	check("Enter and Tab are not game keys, so the menu keeps them",
		viewport.gui_get_focus_owner() != null)

	var sprint_up := InputEventKey.new()
	sprint_up.keycode = KEY_W
	sprint_up.physical_keycode = KEY_W
	sprint_up.shift_pressed = true
	sprint_up.pressed = true
	var interact := InputEventKey.new()
	interact.keycode = KEY_E
	interact.physical_keycode = KEY_E
	interact.pressed = true
	check("Shift+W, sprinting up, is still a step; E is not one of them",
		HUD.is_world_key(sprint_up) and not HUD.is_world_key(interact))

	watcher.queue_free()
	layer.queue_free()

	var input_body := _func_body(_code_src("res://src/ui/characterhud.gd"), "func _input(")
	check("the HUD's _input hands the keyboard back",
		input_body.contains("release_for_world_key(event, get_viewport())"), input_body.strip_edges())
	print("  game keys: the bug, buttons, arrows, space, slider, text boxes, other keys, the wiring")


func _test_staff_logins_take_a_code() -> void:
	section("STAFF LOGIN CODE — the password, then the code from the email")

	# ---- what counts as the code step ----
	var first_step := {"ok": true, "status": 202, "error": "",
		"data": {"code_required": true, "sent_to": "b***s@example.test", "expires_in": 900}}
	var wrong_code := {"ok": false, "status": 400, "error": "That code is not right.",
		"data": {"error": "Bad Code", "code_required": true, "sent_to": "b***s@example.test",
			"message": "That code is not right, or it has run out."}}
	var logged_in := {"ok": true, "status": 200, "error": "", "data": {"token": "t", "username": "boss"}}
	var wrong_password := {"ok": false, "status": 401, "error": "Incorrect username or password.", "data": {}}
	check("the first step (202) and a wrong code (400) are the code step; a login and a 401 are not",
		ApiForTests.needs_login_code(first_step) and ApiForTests.needs_login_code(wrong_code)
		and not ApiForTests.needs_login_code(logged_in) and not ApiForTests.needs_login_code(wrong_password))
	var api_login := _func_body(_code_src("res://src/systems/api.gd"), "func login(")
	check("Api.login sends the code, and never adopts a 202 - a 2xx with no token",
		api_login.contains("body[\"code\"] = code")
		and api_login.contains("if res.ok and not needs_login_code(res):"), api_login.left(400))

	# ---- the login screen ----
	var login: Node = (load("res://scene/ui/menus/loginmenu.tscn") as PackedScene).instantiate()
	login._build_code_box()
	var box: LineEdit = login.login_code_box
	var form: Node = login.get_node("%loginform")
	var password: Node = login.get_node("%passwordlineedit")
	check("the code box is built hidden, right under the password",
		box != null and not box.visible and box.get_parent() == form
		and box.get_index() == password.get_index() + 1)
	login._show_code_step("boss", first_step)
	var said: Label = login.get_node("%errorlabel")
	check("a 202 shows the box and says where the code went, in the working grey",
		box.visible and said.text.contains("b***s@example.test")
		and said.get_theme_color("font_color") == login.SAY_WORKING, said.text)
	box.text = "183 774"
	check("  the typed code goes with the login, spaces out", login._typed_login_code("boss") == "183774",
		login._typed_login_code("boss"))
	check("  but only for the account it was asked for", login._typed_login_code("someoneelse") == "")
	login._show_code_step("boss", wrong_code)
	check("a wrong code keeps the box and what was typed, and says so in red",
		box.visible and box.text == "183 774" and said.text.contains("not right")
		and said.get_theme_color("font_color") == login.SAY_REFUSED, said.text)
	login.get_node("%usernamelineedit").text_changed.emit("somebody")
	check("changing the username puts the box away", not box.visible and box.text == ""
		and login._typed_login_code("boss") == "")
	login.free()

	var pressed := _func_body(_code_src("res://src/ui/menus/loginmenu.gd"), "func _on_login_button_pressed(")
	var step_at := pressed.find("if ApiScript.needs_login_code(res):")
	check("the button sends the typed code, and checks for the code step before res.ok and the 401",
		pressed.contains("Api.login(username, password, _typed_login_code(username))")
		and step_at != -1 and step_at < pressed.find("if res.ok:")
		and step_at < pressed.find("if res.status == 401:"), step_at)

	# ---- a staff login that needed no code is told, once ----
	var was := [Api.staff_unprotected, Api._told_staff_unprotected, Api.role]
	Api.staff_unprotected = true
	Api._told_staff_unprotected = false
	Api.role = "mod"
	var first_time: bool = Api.take_staff_unprotected_notice()
	var second_time: bool = Api.take_staff_unprotected_notice()
	Api._told_staff_unprotected = false
	Api.role = "player"
	var as_player: bool = Api.take_staff_unprotected_notice()
	Api.staff_unprotected = was[0]
	Api._told_staff_unprotected = was[1]
	Api.role = was[2]
	check("a staff login without a code is told once per login, and a player never",
		first_time and not second_time and not as_player, [first_time, second_time, as_player])
	var adopt := _func_body(_code_src("res://src/systems/api.gd"), "func _adopt_session(")
	var hud_ready := _func_body(_code_src("res://src/ui/characterhud.gd"), "func _ready(")
	check("  the flag comes from the login, and the HUD asks on its way in",
		adopt.contains("staff_unprotected = bool(data.get(\"staff_unprotected\", false))")
		and hud_ready.contains("_warn_unprotected_staff()"))
	print("  staff code: the step, the adopt gate, the box, the order, the once-only notice")


func _test_chat_is_one_line_per_message() -> void:
	section("CHAT - one message is one line, with nothing invisible in it")

	var ChatPanel: Script = load("res://src/ui/chat/chatpanel.gd") as Script
	check("the chat panel script loads", ChatPanel != null and ChatPanel.can_instantiate())
	if ChatPanel == null or not ChatPanel.can_instantiate():
		return
	check("newlines are spaces: 150 of them used to be 150 blank lines on every screen",
		ChatPanel.one_line("top" + "\n".repeat(150) + "bottom") == "top bottom")
	check("  so a player cannot put a fake [SERVER] line on a line of its own",
		not ChatPanel.one_line("hi\n12:00 [SERVER] restarting").contains("\n"))
	check("a bidi override and zero-width characters are dropped",
		ChatPanel.one_line(String.chr(0x202E) + "evil" + String.chr(0x200B) + String.chr(0xFEFF)) == "evil")
	check("  and a message of nothing else comes out empty",
		ChatPanel.one_line(String.chr(0x200B) + String.chr(0x2060)) == "")
	var family: String = String.chr(0x1F468) + String.chr(0x200D) + String.chr(0x1F469)
	check("emoji joined with ZWJ keep the joiner", ChatPanel.one_line(family + " hi") == family + " hi")
	check("tabs and runs of spaces are one space", ChatPanel.one_line("a\t\t b   c") == "a b c")

	# THE REAL LINE, as the log builds it - not the helper alone.
	var chat: Node = ChatPanel.new()
	var label: RichTextLabel = chat._node_for({"kind": "chat", "by": "griefer", "role": "player",
		"body": "hi\n\n\n\n12:00 [SERVER] Server restarting", "at": 1700000000}) as RichTextLabel
	var drawn: String = label.get_parsed_text() if label != null else ""
	check("a chat line is drawn as one line, and the [ stays a literal bracket",
		label != null and not drawn.contains("\n") and drawn.contains("hi 12:00 [SERVER] Server restarting"), drawn)
	var picture: Control = chat._node_for({"kind": "image", "by": "griefer", "role": "player",
		"image": "", "body": "look\n\n\nhere", "at": 1700000000})
	var header: RichTextLabel = null
	if picture != null:
		for child in picture.get_children():
			if child is RichTextLabel:
				header = child
				break
	check("  and so is a picture's caption", header != null and header.get_parsed_text().contains("look here")
		and not header.get_parsed_text().contains("\n"), header.get_parsed_text() if header else "")
	if label != null:
		label.free()
	if picture != null:
		picture.free()
	chat.free()
	print("  chat lines: newlines, fake server lines, invisible characters, emoji, spaces, the drawn line, captions")


func _test_chat_walk_and_talk() -> void:
	section("CHAT - Enter to talk, Enter to walk, and see-through while you do")

	# ---- the HUD's Enter ----
	var HUD: Script = load("res://src/ui/characterhud.gd") as Script
	var key := func(code: Key, down: bool = true, echo: bool = false) -> InputEventKey:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = down
		k.echo = echo
		return k
	var layer := CanvasLayer.new()
	var box := LineEdit.new()
	var button := Button.new()
	layer.add_child(box)
	layer.add_child(button)
	add_child(layer)
	check("Enter, and the keypad's Enter, open chat from the game",
		HUD.is_chat_key(key.call(KEY_ENTER), null) and HUD.is_chat_key(key.call(KEY_KP_ENTER), null))
	check("  and from a button a click left holding the focus", HUD.is_chat_key(key.call(KEY_ENTER), button))
	check("  but not from a text box: there Enter is the box's own",
		not HUD.is_chat_key(key.call(KEY_ENTER), box))
	box.editable = false
	check("  (one that cannot be typed in does not count)", HUD.is_chat_key(key.call(KEY_ENTER), box))
	check("  and only the press: not its release, not a held key repeating, not another key",
		not HUD.is_chat_key(key.call(KEY_ENTER, false), null)
		and not HUD.is_chat_key(key.call(KEY_ENTER, true, true), null)
		and not HUD.is_chat_key(key.call(KEY_T), null))
	layer.queue_free()

	var hud_src: String = _code_src("res://src/ui/characterhud.gd")
	var input_body := _func_body(hud_src, "func _input(")
	check("the HUD reads Enter in _input, first, before the GUI",
		input_body.get_slice("\n", 1).strip_edges() == "if _chat_key(event):", input_body.left(80))
	var chat_key_body := _func_body(hud_src, "func _chat_key(")
	check("  opens chat to type, and takes the press",
		chat_key_body.contains("open_chat_to_type()") and chat_key_body.contains("set_input_as_handled()"))
	var to_type := _func_body(hud_src, "func open_chat_to_type(")
	check("  a shut chat is opened (which puts the keyboard in the box); an open one is typed in",
		to_type.contains("toggle_chat(true)") and to_type.contains("focus_entry()"))

	# ---- the window ----
	var packed: PackedScene = load("res://scene/ui/chat/chatpanel.tscn") as PackedScene
	if packed == null or not packed.can_instantiate():
		check("chatpanel.tscn loads", false)
		return
	var chat: Control = packed.instantiate() as Control
	add_child(chat)
	var poll_timer: Timer = chat.get_node_or_null("ChatPoll") as Timer
	if poll_timer != null:
		poll_timer.stop()
	await get_tree().process_frame
	var viewport: Viewport = get_viewport()
	var frame: Control = chat.window_frame
	var header: CanvasItem = chat.get_node("frame/margin/rows/headerpanel")
	var entry_row: CanvasItem = chat.get_node("frame/margin/rows/entryrow")
	var entry: LineEdit = chat.entry
	var chrome := func() -> Array:
		return [header.modulate.a, chat.tabs_box.modulate.a, entry_row.modulate.a]
	var see_through := func() -> bool:
		return is_equal_approx(frame.self_modulate.a, chat.IDLE_FRAME_ALPHA) \
			and is_equal_approx(chat.scroll.self_modulate.a, chat.IDLE_LOG_ALPHA) \
			and chrome.call() == [chat.IDLE_CHROME_ALPHA, chat.IDLE_CHROME_ALPHA, chat.IDLE_CHROME_ALPHA] \
			and is_equal_approx(chat.lines_box.modulate.a, 1.0) \
			and is_equal_approx(chat.lines_box.self_modulate.a, 1.0)
	var solid := func() -> bool:
		return is_equal_approx(frame.self_modulate.a, 1.0) \
			and is_equal_approx(chat.scroll.self_modulate.a, 1.0) and chrome.call() == [1.0, 1.0, 1.0]

	chat.focus_entry()
	await get_tree().process_frame
	check("Enter with chat shut opens it with the keyboard in the box",
		chat.visible and viewport.gui_get_focus_owner() == entry and chat.is_typing())
	check("  and drawn whole while typing", solid.call(), [frame.self_modulate.a, chat.scroll.self_modulate.a, chrome.call()])

	entry.text = ""
	viewport.push_input(key.call(KEY_ENTER))
	viewport.push_input(key.call(KEY_ENTER, false))
	await get_tree().process_frame
	check("Enter on an empty box hands the keyboard back to the game",
		chat.visible and viewport.gui_get_focus_owner() == null and not chat.is_typing())
	check("  and the window stays up, see-through: no frame, title, tabs or box; the lines on their backing",
		see_through.call(), [frame.self_modulate.a, chat.scroll.self_modulate.a, chrome.call()])

	chat.focus_entry()
	await get_tree().process_frame
	check("Enter with chat up puts the keyboard back in the box, and wakes it",
		viewport.gui_get_focus_owner() == entry and solid.call())
	chat.hand_back_keyboard()
	chat.whisper_to.grab_focus()
	await get_tree().process_frame
	check("the whisper name box counts as typing too", chat.is_typing() and solid.call())
	chat.hand_back_keyboard()
	check("  and is handed back the same way", viewport.gui_get_focus_owner() == null and see_through.call())

	# THE REAL PATH: motion pushed into the viewport, read by the window's
	# _input, at points in the viewport's coordinates. (Pushed as local: a
	# window's own coordinates would be stretched to the viewport's first, and
	# a headless run's window is a postage stamp.)
	var on_screen: Transform2D = frame.get_global_transform_with_canvas()
	var move_to := func(point: Vector2) -> void:
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		viewport.push_input(motion, true)
	move_to.call(on_screen * (frame.size * 0.5))
	check("the mouse over the window wakes it", chat.is_awake() and solid.call())
	move_to.call(on_screen * (frame.size + Vector2(40, 40)))
	check("  and it goes see-through again when the mouse leaves", not chat.is_awake() and see_through.call())
	move_to.call(on_screen * (frame.size * 0.5))
	chat.close()
	chat.focus_entry()
	chat.hand_back_keyboard()
	check("a window shut with the mouse on it does not open awake", see_through.call())
	chat.close()
	chat.queue_free()

	var chat_src: String = _code_src("res://src/ui/chat/chatpanel.gd")
	var sent := _func_body(chat_src, "func _send(")
	check("a line sent hands the keyboard back - it no longer grabs it again",
		sent.contains("hand_back_keyboard()") and not sent.contains("entry.grab_focus()"))
	var submitted := _func_body(chat_src, "func _on_entry_submitted(")
	check("  an empty Enter is a send when a picture is waiting (the empty line is its caption)",
		submitted.contains("_pending.is_empty()"))
	var reads := _func_body(chat_src, "func _input(")
	check("  and the mouse is read from motion, not every frame",
		reads.contains("InputEventMouseMotion") and reads.contains("mouse_at("))
	print("  walk and talk: Enter in and out, the see-through look, the whisper box, the mouse")


func _test_chat_keeps_your_place() -> void:
	section("CHAT - a new line is added, not the log rebuilt; reading up stays put")

	var packed: PackedScene = load("res://scene/ui/chat/chatpanel.tscn") as PackedScene
	if packed == null or not packed.can_instantiate():
		check("chatpanel.tscn loads", false)
		return
	var chat: Control = packed.instantiate() as Control
	add_child(chat)
	chat.visible = true
	chat.set_process(false)
	# NOTHING ELSE WRITES THE FEED WHILE THIS RUNS. The panel polls a real
	# server if one is answering on this machine - it did, and its hundred
	# lines of world chat landed in the middle of these checks. The first poll
	# is let finish, then the timer is stopped and the gate held shut.
	var poll_timer: Timer = chat.get_node_or_null("ChatPoll") as Timer
	if poll_timer != null:
		poll_timer.stop()
	for i in 300:
		if not chat._in_flight:
			break
		await get_tree().process_frame
	chat._in_flight = true
	await get_tree().process_frame
	var now: int = int(Time.get_unix_time_from_system())
	var said := func(n: int) -> Dictionary:
		return {"kind": "chat", "by": "someone", "role": "player", "at": now, "id": 50000 + n,
			"body": "line %d - long enough to take up most of a row in the chat window, and then some" % n}
	# THE REAL PATH: a tab opened (a reset), and its first read arriving.
	chat._show_channel("world")
	var tail: Array = []
	for i in 60:
		tail.append(said.call(i))
	chat._apply_read("world", {"channel": "world", "available": true, "messages": tail,
		"removed": [], "latest_id": 50059})
	for i in 4:
		await get_tree().process_frame
	check("the first read after a tab opens is drawn once, with nothing left over",
		chat.lines_box.get_child_count() == 60 and not chat._redraw_on_next_read,
		chat.lines_box.get_child_count())
	var sc: ScrollContainer = chat.scroll
	var bar: VScrollBar = sc.get_v_scroll_bar()
	var log_box: Node = chat.lines_box
	check("sixty lines make a log taller than the window", bar.max_value > bar.page + 200,
		[bar.max_value, bar.page])
	var first_before: Node = log_box.get_child(0)
	sc.scroll_vertical = 40
	await get_tree().process_frame
	chat._add_line("world", said.call(60))
	for i in 3:
		await get_tree().process_frame
	check("a new line is added to the log, not the log rebuilt",
		log_box.get_child(0) == first_before and log_box.get_child_count() == 61, log_box.get_child_count())
	check("and a player reading further up stays where they were", sc.scroll_vertical == 40, sc.scroll_vertical)
	check("  and is told there is something new below",
		chat.new_below != null and chat.new_below.visible and chat.new_below.get_parent() == sc.get_parent()
		and chat.new_below.get_index() == sc.get_index() + 1)

	chat._apply_read("world", {"channel": "world", "available": true, "messages": [],
		"removed": [50000 + 59], "latest_id": 50060})
	for i in 3:
		await get_tree().process_frame
	check("a line taken down by staff does not pull a reader to the bottom either",
		sc.scroll_vertical == 40 and log_box.get_child_count() == 60, [sc.scroll_vertical, log_box.get_child_count()])

	sc.scroll_vertical = int(bar.max_value)
	await get_tree().process_frame
	chat._add_line("world", said.call(61))
	for i in 3:
		await get_tree().process_frame
	check("a player reading the newest lines follows the new one",
		float(sc.scroll_vertical) + bar.page >= bar.max_value - 2, [sc.scroll_vertical, bar.page, bar.max_value])
	check("  and reaching the bottom puts the \"new messages\" bar away", not chat.new_below.visible)
	sc.scroll_vertical = 40
	await get_tree().process_frame
	chat._add_line("world", said.call(9990))
	for i in 3:
		await get_tree().process_frame
	var shown_again: bool = chat.new_below.visible
	chat.new_below.pressed.emit()
	for i in 3:
		await get_tree().process_frame
	check("clicking the bar goes to the newest line and puts it away",
		shown_again and not chat.new_below.visible
		and float(sc.scroll_vertical) + bar.page >= bar.max_value - 2, [shown_again, sc.scroll_vertical])

	for i in range(62, 62 + chat.LINES_KEPT):
		chat._add_line("world", said.call(i))
	await get_tree().process_frame
	var kept: Array = chat._feeds["world"]["lines"]
	var top: RichTextLabel = log_box.get_child(0) as RichTextLabel
	check("past the cap, the oldest line leaves the screen with the feed",
		log_box.get_child_count() == kept.size() and kept.size() == chat.LINES_KEPT
		and top != null and top.get_parsed_text().contains("line %d " % int(kept[0]["id"] - 50000)),
		[log_box.get_child_count(), kept.size()])

	# SWITCHING AWAY AND BACK: the old lines stay up while the tail comes, and
	# the tail replaces them rather than landing underneath.
	chat._show_channel("guild")
	chat._show_channel("world")
	var drawn_while_waiting: int = log_box.get_child_count()
	chat._apply_read("world", {"channel": "world", "available": true,
		"messages": [said.call(900), said.call(901)], "removed": [], "latest_id": 50901})
	await get_tree().process_frame
	check("coming back to a tab shows its old lines until the tail arrives, then only the tail",
		drawn_while_waiting > 2 and log_box.get_child_count() == 2, [drawn_while_waiting, log_box.get_child_count()])

	# A READ THAT LEFT BEFORE A RESET is thrown away: its lines came after the
	# old cursor, and /r showed a reply with none of the conversation.
	var poll_body := _func_body(_code_src("res://src/ui/chat/chatpanel.gd"), "func _poll(")
	check("a poll answer from before a feed reset is dropped, and the tail asked for",
		poll_body.contains("if generation != _feed_generation:")
		and poll_body.find("if generation != _feed_generation:") < poll_body.find("_apply_read(asked, data)"))

	var send_body := _func_body(_code_src("res://src/ui/chat/chatpanel.gd"), "func _send(")
	check("your own line brings the log to the end, even scrolled up",
		send_body.find("_stick_to_bottom = true") != -1
		and send_body.find("_stick_to_bottom = true") < send_body.find("_poll()"))
	var add_body := _func_body(_code_src("res://src/ui/chat/chatpanel.gd"), "func _add_line(")
	check("the open channel's new line goes through the append, never a full render",
		add_body.contains("_append_to_log()") and not add_body.contains("_render()"))
	chat.queue_free()
	print("  chat place: appended not rebuilt, reading up kept, newest followed, the cap, your own line")


func _test_whispers_reach_you() -> void:
	section("WHISPERS - said to you with chat shut, or open on another tab, and answered with /r")

	var now: int = int(Time.get_unix_time_from_system())
	var hud_script: Script = load("res://src/ui/characterhud.gd") as Script
	hud_script._forget_chat_news()
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	hud._build_message_box()
	var rows: Control = hud.message_rows
	var chat_button: Button = hud.get_node("%chatbutton") as Button
	var news := func(whisper_id: int, who: String, body: String, at: int, guild: int) -> Dictionary:
		var whisper: Variant = null
		if whisper_id > 0:
			whisper = {"id": whisper_id, "from": who, "body": body, "at": at}
		return {"latest_id": 0, "messages": [], "chat_news": {
			"whisper": whisper,
			"guild": guild, "friends": 0}}

	hud._apply_broadcast(news.call(7, "yesterday", "old news", now - 3600, 3))
	check("the first poll's old whisper and guild lines are where 'new' starts, not news",
		rows.get_child_count() == 0 and chat_button.text == "Chat", [rows.get_child_count(), chat_button.text])
	hud._apply_broadcast(news.call(8, "chatter2", "hey\n\n\nwant to trade?", now, 3))
	var toast: String = (rows.get_child(0) as Label).text if rows.get_child_count() > 0 else ""
	check("a new whisper with chat shut pops the box with who said what, on one line",
		toast == "chatter2 whispers: hey want to trade?", toast)
	check("  lights the Chat button", chat_button.text == "Chat •", chat_button.text)
	check("  and waits for the chat window, which does not exist yet",
		hud_script._whisper_waiting and hud_script._last_whisper_from == "chatter2")
	hud._mark_chat_button(false)
	hud._apply_broadcast(news.call(8, "chatter2", "hey", now, 4))
	check("a new guild line lights the Chat button too", chat_button.text == "Chat •", chat_button.text)
	check("  and the same whisper is not said twice", rows.get_child_count() == 1, rows.get_child_count())
	hud.free()

	# THROUGH A DOOR. Every area has its own HUD; a whisper from a minute ago
	# was said again in each one, and the lit Chat button went dark.
	var next_area: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	next_area._build_message_box()
	next_area._apply_broadcast(news.call(8, "chatter2", "hey", now, 4))
	check("the next area's HUD does not say the same whisper again",
		next_area.message_rows.get_child_count() == 0, next_area.message_rows.get_child_count())
	check("  and the waiting whisper still waits for the chat window",
		hud_script._whisper_waiting and hud_script._last_whisper_from == "chatter2")
	var ready_src := _func_body(_code_src("res://src/ui/characterhud.gd"), "func _ready(")
	check("  and a new area's HUD lights the Chat button again", ready_src.contains("if _chat_dot and _chat_seen_by == Api.username:"))
	next_area.free()

	# ANOTHER ACCOUNT ON THIS MACHINE starts from nothing: the last one's ids
	# are not where "new" starts for it.
	hud_script._chat_seen_by = "someoneelse"
	hud_script._chat_seen = {"whisper": 999999, "guild": 999999, "friends": 999999}
	var other_login: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	other_login._build_message_box()
	other_login._apply_broadcast(news.call(10, "friend", "welcome back", now - 20, 0))
	check("a different account's first poll is its own, not the last player's",
		other_login.message_rows.get_child_count() == 1 and hud_script._chat_seen_by == Api.username,
		other_login.message_rows.get_child_count())
	other_login.free()

	hud_script._forget_chat_news()
	var fresh: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	fresh._build_message_box()
	fresh._apply_broadcast(news.call(9, "justnow", "you there?", now - 30, 0))
	check("a whisper from a moment before you logged in is still said",
		fresh.message_rows.get_child_count() == 1, fresh.message_rows.get_child_count())
	fresh.free()
	hud_script._forget_chat_news()

	var toggle := _func_body(_code_src("res://src/ui/characterhud.gd"), "func toggle_chat(")
	check("the chat window, when it is built, is handed the waiting whisper",
		toggle.contains("chat_panel.whisper_arrived(_last_whisper_from)")
		and toggle.contains("chat_panel.last_whisper_from = _last_whisper_from"))

	# ---- the chat window ----
	var chat: Control = (load("res://scene/ui/chat/chatpanel.tscn") as PackedScene).instantiate() as Control
	add_child(chat)
	var poll_timer: Timer = chat.get_node_or_null("ChatPoll") as Timer
	if poll_timer != null:
		poll_timer.stop()
	for i in 300:
		if not chat._in_flight:
			break
		await get_tree().process_frame
	chat._in_flight = true
	chat.visible = false
	chat.whisper_arrived("chatter2")
	check("shut, a whisper aims the Whisper tab at who sent it and lights it",
		chat._whisper_with == "chatter2" and chat._feeds["private"]["unread"] and chat._whisper_waiting)
	chat.open()
	check("  and the window opens on that conversation, not World",
		chat.visible and chat._channel == "private" and chat._whisper_with == "chatter2", chat._channel)
	chat.close()
	chat.whisper_arrived("newperson")
	chat.open()
	check("  even with another conversation in the box: the window opens on who whispered",
		chat._channel == "private" and chat._whisper_with == "newperson", chat._whisper_with)
	chat._show_channel("world")
	chat._aim_whisper("somebodyelse")
	chat.whisper_arrived("thirdperson")
	check("open on another tab, it says who whispered and how to answer",
		chat.notice.text == "thirdperson whispered you. /r to answer."
		and chat._whisper_with == "somebodyelse", [chat.notice.text, chat._whisper_with])
	chat.room_news("guild")
	chat.room_news("world")
	check("a guild line lights the Guild tab; the open tab is not marked",
		chat._feeds["guild"]["unread"] and not chat._feeds["world"]["unread"])
	chat.last_whisper_from = ""
	chat.entry.text = "/r hello"
	await chat._on_send_pressed()
	check("/r with nobody to answer says so", chat.notice.text == "Nobody has whispered you yet.", chat.notice.text)
	var send_src := _func_body(_code_src("res://src/ui/chat/chatpanel.gd"), "func _on_send_pressed(")
	check("  and otherwise answers whoever whispered last, in the Whisper tab",
		send_src.contains("_aim_whisper(last_whisper_from)") and send_src.contains("await _send(\"private\", answer, \"\")"))
	chat.queue_free()

	var hud_src := _func_body(_code_src("res://src/ui/characterhud.gd"), "func _apply_broadcast(")
	check("the broadcast poll's answer is where the news is read",
		hud_src.contains("_read_chat_news(data.get(\"chat_news\"))"))
	print("  whispers: the baseline, the toast, the button, the waiting window, other tabs, guild, /r, the wiring")


func _test_black_past_the_map() -> void:
	section("MAP BACKDROP - grey in the gaps of the tiles, black past the edge of the map")

	var Backdrop: Script = load("res://src/world/mapbackdrop.gd") as Script
	check("mapbackdrop.gd compiles", Backdrop != null and Backdrop.can_instantiate())
	if Backdrop == null or not Backdrop.can_instantiate():
		return
	# THE EDITOR DRAWS A SCENE OVER THE PROJECT'S CLEAR COLOUR. Set black, every
	# gap in every tile went black there too - the "graphics trip out" report.
	var project_clear: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color")
	check("project.godot keeps the engine's grey, which is what the tiles were painted over",
		project_clear.is_equal_approx(Color(0.3, 0.3, 0.3, 1.0)), project_clear)
	check("  and the gaps are filled with that same grey in the game",
		Backdrop.GAPS.is_equal_approx(project_clear), Backdrop.GAPS)
	check("the game makes the screen black at runtime, for past the edge of the map",
		RenderingServer.get_default_clear_color().is_equal_approx(Backdrop.OUTSIDE)
		and Backdrop.OUTSIDE.is_equal_approx(Color.BLACK), RenderingServer.get_default_clear_color())
	check("every area that opens is given one", get_tree().scene_changed.is_connected(AreaRegistry._on_scene_changed))

	# ---- exactly the tiles, as they are drawn ----
	var area := Node2D.new()
	var layer := TileMapLayer.new()
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(16, 16)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = load("res://art/tiles/tiles4.png") as Texture2D
	atlas.texture_region_size = Vector2i(16, 16)
	atlas.create_tile(Vector2i(0, 0))
	atlas.create_tile(Vector2i(2, 0), Vector2i(2, 2))
	var source_id: int = tiles.add_source(atlas)
	layer.tile_set = tiles
	area.add_child(layer)
	for x in 3:
		layer.set_cell(Vector2i(x, 0), source_id, Vector2i(0, 0))
	layer.set_cell(Vector2i(10, 10), source_id, Vector2i(2, 0))
	var rects: Array = Backdrop.cover(area)
	check("a row of three small tiles is one rectangle, exactly under them",
		rects.has(Rect2(0, 0, 48, 16)), rects)
	check("a 32x32 tile on a 16 grid is covered where it is DRAWN - centred on its cell - not as the cell",
		rects.has(Rect2(152, 152, 32, 32)) and rects.size() == 2, rects)
	var added: Node2D = Backdrop.add_to(area)
	check("the backdrop goes under everything in the area",
		added != null and area.get_child(0) == added and not added.z_as_relative
		and added.z_index == RenderingServer.CANVAS_ITEM_Z_MIN)
	area.free()

	# ---- every real area is covered, cheaply ----
	for area_id in AreaRegistry.AREAS:
		var packed: PackedScene = load(AreaRegistry.AREAS[area_id]) as PackedScene
		if packed == null:
			continue
		var scene: Node = packed.instantiate()
		var cover: Array = Backdrop.cover(scene)
		var layers: int = scene.find_children("*", "TileMapLayer", true, false).size()
		check("%s: every tile layer is covered, in a few hundred rectangles at most" % area_id,
			(layers == 0 and cover.is_empty()) or (not cover.is_empty() and cover.size() < 600),
			[layers, cover.size()])
		scene.free()
	print("  backdrop: the editor's grey, black at runtime, exact rectangles, big tiles, under everything, every area")


func _test_signing_in_never_makes_an_account() -> void:
	section("SIGNING IN - never makes an account; creating one asks the password twice")

	var src: String = _code_src("res://src/ui/menus/loginmenu.gd")
	var pressed: String = _func_body(src, "func _on_login_button_pressed(")
	var create: String = _func_body(src, "func _create_account(")
	# THE BUG: a mistyped name got a 401, the 401 fell through to register(),
	# and the player was in a brand new, empty account - asked for a recovery
	# email for it, with every character "gone".
	check("the sign-in button never registers a name",
		not pressed.contains("Api.register("), "a typo in your own name made a new account")
	check("  a 401 says wrong name or password, and points a new player at the sign-up link",
		pressed.contains("if res.status == 401:") and pressed.contains("Wrong name or password")
		and pressed.contains("CREATE_LINK_TEXT"))
	check("there is exactly one register() call on the screen, in the sign-up form",
		src.count("Api.register(") == 1 and create.contains("Api.register("))
	check("  and it comes after the two passwords are compared",
		create.find("if again != password:") != -1
		and create.find("if again != password:") < create.find("Api.register("))

	var login: Node = _login_screen_for_test()
	login._build_create_account()
	var form: Node = login.get_node("%loginform")
	var password: Node = login.get_node("%passwordlineedit")
	var forgot: Control = login.get_node("%recoverlinkbutton")
	var button: Button = login.get_node("%loginbutton")
	var said: Label = login.get_node("%errorlabel")
	var sign_in_text: String = button.text
	check("the second password box is built hidden, right under the password",
		login.confirm_box != null and not login.confirm_box.visible and login.confirm_box.secret
		and login.confirm_box.get_parent() == form and login.confirm_box.get_index() == password.get_index() + 1)
	check("  and the sign-up link sits under \"Forgot password?\"",
		login.create_link != null and login.create_link.get_index() == forgot.get_index() + 1
		and login.create_link.text == login.CREATE_LINK_TEXT)
	login.create_link.pressed.emit()
	check("the link turns the form into sign-up: second box, button says so, no \"Forgot password?\"",
		login._creating and login.confirm_box.visible and button.text == login.CREATE_BUTTON_TEXT
		and not forgot.visible and login.create_link.text == login.SIGN_IN_LINK_TEXT, button.text)
	login.confirm_box.text = "not the same"
	login._create_account("newplayer", "correcthorse1")
	check("  two different passwords are refused on the spot, in red",
		said.text.contains("not the same") and said.get_theme_color("font_color") == login.SAY_REFUSED
		and not login._request_in_flight, said.text)
	login.create_link.pressed.emit()
	check("and the link takes it back: one box, the scene's own button text, \"Forgot password?\"",
		not login._creating and not login.confirm_box.visible and button.text == sign_in_text
		and forgot.visible and said.text == "", [button.text, said.text])
	login._set_busy(true)
	check("  a request in flight locks the second box and the link too",
		not login.confirm_box.editable and login.create_link.disabled)
	login._set_busy(false)

	# The line a dead server left under the button goes when the server is back.
	login._say("Can't reach the server.", login.SAY_REFUSED)
	login._no_answer_line = "Can't reach the server."
	login._on_connection_changed(true)
	var cleared: bool = said.text == ""
	login._say("Wrong name or password.", login.SAY_REFUSED)
	login._on_connection_changed(true)
	check("\"can't reach the server\" is cleared when it answers again - and nothing else is",
		cleared and said.text == "Wrong name or password.", said.text)
	login.free()
	print("  sign-in: no register on a 401, one register behind two passwords, the form both ways, the stale offline line")


func _test_remember_me_means_it() -> void:
	section("REMEMBER ME - off means closing the game signs you out")

	# THE REAL FILE IS SOMEBODY'S LOGIN. This runs in the developer's own
	# user:// folder, so whatever session.cfg holds is put back afterwards.
	var had_file: bool = FileAccess.file_exists(Api.SESSION_PATH)
	var kept: String = FileAccess.get_file_as_string(Api.SESSION_PATH) if had_file else ""
	var was := [Api.token, Api.username, Api.keep_signed_in]

	Api.token = "test-token-not-real"
	Api.username = "rememberer"
	Api.keep_signed_in = false
	Api._save_session()
	var off_file: bool = FileAccess.file_exists(Api.SESSION_PATH)
	Api.keep_signed_in = true
	Api._save_session()
	var on_file: bool = FileAccess.file_exists(Api.SESSION_PATH)
	Api.keep_signed_in = false
	Api.token = ""
	Api._load_session()
	var loaded: Array = [Api.token, Api.keep_signed_in]
	Api.keep_signed_in = false
	Api._save_session()
	var cleared_file: bool = FileAccess.file_exists(Api.SESSION_PATH)
	check("with the box clear, no login is written to this computer",
		not off_file, "the next person to open the game walked into the account")
	check("with it ticked, it is", on_file)
	check("  and a login read back from disk counts as remembered", loaded == ["test-token-not-real", true], loaded)
	check("  and clearing the box later takes the file away", not cleared_file)

	if had_file:
		var f := FileAccess.open(Api.SESSION_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(kept)
			f.close()
	else:
		DirAccess.remove_absolute(Api.SESSION_PATH)
	Api.token = was[0]
	Api.username = was[1]
	Api.keep_signed_in = was[2]

	var pressed: String = _func_body(_code_src("res://src/ui/menus/loginmenu.gd"), "func _on_login_button_pressed(")
	check("the login screen sets it from the box before signing in or signing up",
		pressed.contains("Api.keep_signed_in = %rememberme.button_pressed")
		and pressed.find("Api.keep_signed_in") < pressed.find("_create_account(")
		and pressed.find("Api.keep_signed_in") < pressed.find("Api.login("))
	var resume: String = _func_body(_code_src("res://src/ui/menus/loginmenu.gd"), "func _check_connection_and_resume(")
	check("a remembered login goes in even while it owes a recovery address",
		not resume.contains("if Api.needs_email:"),
		"it used to stop and ask for a typed sign-in every time, so Remember me did nothing")
	print("  remember me: nothing on disk when off, on disk when on, read back as remembered, the file restored")


func _test_one_game_per_account() -> void:
	section("ONE GAME PER ACCOUNT - the game signed in over says so")

	var elsewhere := {"ok": false, "status": 401, "error": "",
		"data": {"error": "Unauthorized", "signed_in_elsewhere": true}}
	var kicked := {"ok": false, "status": 401, "error": "", "data": {"error": "Unauthorized"}}
	check("a 401 marked signed_in_elsewhere reads as another login, not a kick",
		ApiForTests.signout_notice_for(elsewhere) == Api.SIGNED_IN_ELSEWHERE_NOTICE
		and ApiForTests.signout_notice_for(kicked) == Api.SIGNED_OUT_NOTICE
		and ApiForTests.signout_notice_for({}) == Api.SIGNED_OUT_NOTICE)

	var api_src: String = _code_src("res://src/systems/api.gd")
	var probe: String = _func_body(api_src, "func probe_and_resume(")
	check("reopening the game carries a remembered login on a NEW token",
		probe.contains("post(\"/api/auth/resume\"") and probe.contains("res.data.get(\"token\"")
		and probe.contains("_save_session()"),
		"a second copy of the game found the same token and ran beside the first")
	check("  and falls back to the plain check on a server from before the route",
		probe.contains("== 404:") and probe.contains("get_json(\"/api/auth/session\""))
	var beat: String = _func_body(api_src, "func heartbeat(")
	check("the heartbeat keeps the refusal it was given, so the screen can say why",
		beat.contains("last_refusal = res"))
	var hud_src: String = _code_src("res://src/ui/characterhud.gd")
	var signout: String = _func_body(hud_src, "func _forced_signout(")
	check("the HUD signs out with that reason, from the poll or the heartbeat",
		signout.contains("signout_notice_for(") and signout.contains("Api.forget_session(notice)")
		and _func_body(hud_src, "func _on_broadcast_poll_timeout(").contains("_forced_signout(res)"))
	print("  one game per account: the notice, the resume swap, the old-server fallback, the reason carried")


func _test_email_prompt_can_wait() -> void:
	section("RECOVERY EMAIL - \"Not now\" instead of a door with only Exit")

	var login: Node = _login_screen_for_test()
	if login.email_form == null:
		check("the login scene has its email prompt", false)
		login.free()
		return
	# THROUGH THE WIRING _ready() runs, not the builder alone - a builder
	# nobody calls is a button nobody sees.
	login._wire_email_prompt()
	var later: Button = login.email_later_button
	check("the prompt has a \"Not now\" under its confirm button",
		later != null and later.get_parent() == login.email_form
		and later.get_index() == login.email_confirm_button.get_index() + 1
		and later.text == login.EMAIL_LATER_TEXT)
	login._wire_email_prompt()
	var copies: int = 0
	for child in login.email_form.get_children():
		if child is Button and (child as Button).text == login.EMAIL_LATER_TEXT:
			copies += 1
	check("  built once, however often the prompt is wired", copies == 1, copies)
	login.free()

	var src: String = _code_src("res://src/ui/menus/loginmenu.gd")
	var pressed: String = _func_body(src, "func _on_email_later_pressed(")
	check("\"Not now\" drops the held password and carries on into the game",
		pressed.contains("_password_for_email = \"\"") and pressed.contains("_complete_login(_pending_username)"))
	print("  recovery email: Not now exists, once, in place, forgets the password, goes on in")


func _test_chat_filter() -> void:
	section("CHAT FILTER - whole words, their disguises, and never the words around them")

	var Filter: Script = load("res://src/ui/chat/chatfilter.gd") as Script
	check("the filter script loads", Filter != null)
	if Filter == null:
		return
	var masked := {
		"fuck": "f***", "Fuck!!": "F***!!", "$hit": "$***", "sh1t": "s***",
		"fuuuuuck": "f*******", "shithead": "s*******", "motherfuckers": "m************",
		"what the fuck is this": "what the f*** is this",
	}
	var wrong: Array = []
	for said in masked:
		if Filter.clean(said) != masked[said]:
			wrong.append([said, Filter.clean(said)])
	check("a listed word is masked, with its endings and its disguises", wrong.is_empty(), wrong)
	var clean_words := ["class", "assess", "Scunthorpe", "cocktail", "cocky", "as", "pass", "grape",
		"raccoon", "cumin", "spice", "Dickens", "therapist", "hello there", "sooooo good", "1v1 me"]
	var hit: Array = []
	for said in clean_words:
		if Filter.clean(said) != said:
			hit.append([said, Filter.clean(said)])
	check("and nothing that merely contains one is touched", hit.is_empty(), hit)
	var src: String = FileAccess.get_file_as_string("res://src/ui/chat/chatfilter.gd")
	check("  the list is not readable as a list in the source", not src.contains(" fuck ") and not src.contains("\"fuck"))

	var ChatPanel: Script = load("res://src/ui/chat/chatpanel.gd") as Script
	check("the chat window shows filtered text only when asked to",
		ChatPanel.shown_text("oh\nshit", true) == "oh s***" and ChatPanel.shown_text("oh\nshit", false) == "oh shit")
	check("the setting exists and is on by default", Settings.DEFAULTS.get("chat_filter") == true)
	var node_src: String = _func_body(_code_src("res://src/ui/chat/chatpanel.gd"), "func _node_for(")
	var picture_src: String = _func_body(_code_src("res://src/ui/chat/chatpanel.gd"), "func _picture_node(")
	var hud_src: String = _func_body(_code_src("res://src/ui/characterhud.gd"), "func _whisper_from(")
	check("every place a player's words are drawn goes through it: the line, a caption, the whisper pop-up",
		node_src.contains("shown_text(") and picture_src.contains("shown_text(")
		and hud_src.contains("shown_text(") and hud_src.contains("\"chat_filter\""))
	check("turning it on or off redraws what is on screen",
		_func_body(_code_src("res://src/ui/chat/chatpanel.gd"), "func _on_setting_changed(").contains("_render(true)"))
	print("  chat filter: masks words and disguises, spares Scunthorpe, is a setting, reaches every drawn line")


func _test_chat_safety_menu() -> void:
	section("CHAT SAFETY - the name menu, commands, and a muted box")

	var packed: PackedScene = load("res://scene/ui/chat/chatpanel.tscn") as PackedScene
	var chat: Control = packed.instantiate() as Control
	# Out of the tree: _ready() never runs, so nothing polls a server. The
	# nodes these read are filled by hand.
	chat.entry = chat.get_node_or_null("%chatentry")
	chat.notice = chat.get_node_or_null("%chatnotice")
	for channel in chat.CHANNELS:
		chat._feeds[channel] = {"cursor": 0, "lines": [], "unread": false}
	var was := [Api.username, Api.role, Api.is_owner]
	Api.username = "me_myself"
	Api.role = "player"
	Api.is_owner = false

	var line := {"kind": "chat", "by": "rowdy", "role": "player", "id": 77, "at": 0, "body": "a line"}
	var label: RichTextLabel = chat._node_for(line) as RichTextLabel
	label.meta_clicked.emit("name")
	var menu: PopupMenu = chat.line_menu
	var items: Array = []
	if menu != null:
		for i in menu.item_count:
			if not menu.is_item_separator(i):
				items.append(menu.get_item_text(i))
	check("clicking a name opens its menu: whisper, ignore, what every name offers, and the five reasons to report the line",
		menu != null and chat._menu_line.get("by") == "rowdy"
		and items == ["Whisper", "Ignore", "Add friend", "Trade", "Invite to party", "Invite to guild",
		"Spam", "Harassment", "Hate speech", "Cheating or scams", "Something else"],
		items)
	check("  and a player is offered no mute", not items.has("Unmute"))
	var own: RichTextLabel = chat._node_for({"kind": "chat", "by": "me_myself", "role": "player",
		"id": 78, "at": 0, "body": "mine"}) as RichTextLabel
	chat._menu_line = {}
	chat.open_line_menu({"kind": "chat", "by": "me_myself", "id": 78})
	check("your own name has no menu", chat._menu_line.is_empty())
	chat.open_line_menu({"kind": "chat", "by": "themod", "role": "mod", "id": 79, "body": "x"})
	var ignore_at: int = menu.get_item_index(chat.MENU_IGNORE)
	check("staff cannot be ignored, so it is not offered", menu.is_item_disabled(ignore_at))
	Api.role = "mod"
	chat.open_line_menu(line)
	var staff_items: Array = []
	for i in menu.item_count:
		if not menu.is_item_separator(i):
			staff_items.append(menu.get_item_text(i))
	check("staff get mutes and unmute for a player's line",
		staff_items.has("Mute 10 minutes") and staff_items.has("Mute 1 day") and staff_items.has("Unmute"), staff_items)
	chat.open_line_menu({"kind": "chat", "by": "othermod", "role": "mod", "id": 80, "body": "x"})
	var peer_items: Array = []
	for i in menu.item_count:
		peer_items.append(menu.get_item_text(i))
	check("  and none for a line by their own rank", not peer_items.has("Unmute"), peer_items)
	Api.role = "player"

	chat._feeds["world"]["lines"] = [line, {"by": "Rowdy", "id": 81}, {"by": "fine", "id": 82}]
	chat._feeds["private"]["lines"] = [{"by": "rowdy", "id": 83}]
	var gone: int = chat.forget_author("ROWDY")
	check("ignoring somebody takes their lines out of every feed at once",
		gone == 3 and chat._feeds["world"]["lines"].size() == 1 and chat._feeds["private"]["lines"].is_empty(), gone)

	check("a line starting with / and a letter is a command, and never said out loud",
		chat._looks_like_command("/ignore bob") and chat._looks_like_command("/Help")
		and not chat._looks_like_command("/ ") and not chat._looks_like_command("//x")
		and not chat._looks_like_command("hi /ignore"))
	chat._run_command("/frobnicate now")
	check("an unknown command says so", chat.notice.text.contains("There is no /frobnicate command"), chat.notice.text)
	chat._run_command("/help")
	check("/help lists them", chat.notice.text.contains("/ignore") and chat.notice.text.contains("/unignore"),
		chat.notice.text)
	chat._run_command("/ignore")
	check("a command missing its name says how to use it", chat.notice.text == "Try: /ignore name", chat.notice.text)
	var send_src: String = _func_body(_code_src("res://src/ui/chat/chatpanel.gd"), "func _on_send_pressed(")
	check("  commands are caught before anything is sent",
		send_src.find("_looks_like_command(text)") != -1
		and send_src.find("_looks_like_command(text)") < send_src.find("await _send(_channel, text"))

	var default_hint: String = chat.entry.placeholder_text
	chat._set_muted({"until": 0, "seconds_left": 600, "reason": "spamming world"})
	check("a muted player's box says so before they type",
		chat.entry.placeholder_text == "You are muted for 10 minutes more - spamming world", chat.entry.placeholder_text)
	chat._set_muted(null)
	check("  and goes back when the mute lifts", chat.entry.placeholder_text == default_hint, chat.entry.placeholder_text)
	check("the read carries it", _func_body(_code_src("res://src/ui/chat/chatpanel.gd"), "func _apply_read(")
		.contains("_set_muted(data.get(\"muted\"))"))
	check("a 429 is said in the server's words - typing fast is not about pictures",
		chat._refusal({"status": 429, "error": "Messages are arriving faster than one every 1 seconds."})
			.begins_with("Messages are arriving"))

	# /goto: the owner's way into the Big Field, which no door reaches yet.
	var went: Array = []
	chat.go_to_area = func(area_id: String) -> bool:
		went.append(area_id)
		return true
	chat._run_command("/goto bigfield")
	check("/goto is not a command to a player", went.is_empty()
		and chat.notice.text.contains("There is no /goto command"), chat.notice.text)
	chat._run_command("/help")
	check("  and /help does not mention it", not chat.notice.text.contains("/goto"))
	Api.is_owner = true
	chat._run_command("/help")
	check("the owner's /help lists /goto", chat.notice.text.contains("/goto area"), chat.notice.text)
	chat._run_command("/goto BigField")
	check("  /goto bigfield takes the owner there, any case",
		went == ["bigfield"] and chat.notice.text == "Going to Big Field.", [went, chat.notice.text])
	chat._run_command("/goto nowhere")
	check("  a place that does not exist lists the ones that do",
		went.size() == 1 and chat.notice.text.begins_with("Try: /goto ") and chat.notice.text.contains("bigfield"),
		chat.notice.text)
	Api.is_owner = false

	Api.username = was[0]
	Api.role = was[1]
	Api.is_owner = was[2]
	label.free()
	own.free()
	chat.free()
	print("  chat safety: the menu for others, not yourself, no ignoring staff, mutes for rank, forgetting lines, commands, the muted box")


func _test_staff_reports_and_mutes() -> void:
	section("STAFF - reported lines, and chat mutes")

	var Staff: Script = load("res://src/ui/staff/staffpanel.gd") as Script
	var player := {"username": "rowdy", "role": "player", "actionable": true}
	var can: Dictionary = Staff.actions_for("mod", player)
	check("a mod can mute a player, and there is nothing to unmute yet", can["mute"] and not can["unmute"], can)
	player["mute"] = {"until": 100, "seconds_left": 3600, "reason": "spam"}
	check("  unmute appears once they are muted", Staff.actions_for("mod", player)["unmute"])
	check("  and a mod cannot mute another mod",
		not Staff.actions_for("mod", {"username": "m", "role": "mod", "actionable": true})["mute"])
	check("mute lengths read as people say them",
		[Staff.describe_minutes(600), Staff.describe_minutes(3600), Staff.describe_minutes(86400),
			Staff.describe_minutes(172800), Staff.describe_minutes(5400)]
		== ["10 minutes", "1 hour", "1 day", "2 days", "90 minutes"])
	check("mutes count on a player's record, after bans and kicks",
		Staff.describe_record({"mute": 2, "ban": 1}) == "1 ban · 2 mutes"
		and Staff.describe_record({"mute": 1}, Staff.ROW_RECORD_KINDS) == "1 mute",
		Staff.describe_record({"mute": 2, "ban": 1}))
	check("a mute says how long is left and why",
		Staff.describe_mute(player["mute"]).contains("1 hour left") and Staff.describe_mute(player["mute"]).contains("spam")
		and Staff.describe_mute(null) == "Can talk in chat")
	check("the log names mutes, unmutes and closed reports in words",
		Staff.describe_entry({"by": "m", "action": "mute", "target": "rowdy", "detail": "1 hour: spam"})
			== "m muted rowdy - 1 hour: spam"
		and Staff.KIND_LABELS.has("mute") and Staff.KIND_LABELS.has("report") and Staff.ACCOUNT_KINDS.has("mute"))

	var panel: Control = (load("res://scene/ui/staff/staffpanel.tscn") as PackedScene).instantiate() as Control
	add_child(panel)
	var role_was: String = Api.role
	Api.role = "mod"
	panel._show_detail(player)
	Api.role = role_was
	check("the Actions tab has the mute buttons and the mute on show",
		panel._mute_buttons.size() == Staff.MUTE_PRESETS.size() and not panel._mute_buttons[0].disabled
		and panel.unmute_button != null and not panel.unmute_button.disabled
		and panel.mute_label.text.contains("spam"))
	var report := {"message_id": 5, "reported": "rowdy", "reported_role": "player", "channel": "world",
		"body": "buy gold here", "said_at": 100, "reports": 2, "reporters": ["ann", "cat"],
		"reasons": {"spam": 2}, "actionable": true, "line_exists": true}
	var peer := {"message_id": 6, "reported": "othermod", "reported_role": "mod", "channel": "world",
		"body": "rude", "said_at": 100, "reports": 1, "reporters": ["ann"], "reasons": {"harassment": 1},
		"actionable": false, "line_exists": true}
	panel.apply_reports({"reports": [report, peer], "open": 2, "now": 400})
	var rows: Array = panel.reports_list.get_children()
	var buttons := func(row: Node) -> Array:
		var out: Array = []
		for b in row.find_children("*", "Button", true, false):
			out.append((b as Button).text)
		return out
	check("the Reports tab shows each reported line, and its count in the tab",
		rows.size() == 2 and panel.tabs.get_tab_title(Staff.REPORTS_TAB) == "Reports (2)",
		[rows.size(), panel.tabs.get_tab_title(Staff.REPORTS_TAB)])
	check("  a line you can act on: open the player, delete the line, mute, dismiss",
		buttons.call(rows[0]) == ["Open rowdy", "Delete line", "Mute 1 hour", "Dismiss"], buttons.call(rows[0]))
	check("  a line about your own rank: only open the player, and why",
		buttons.call(rows[1]) == ["Open othermod"], buttons.call(rows[1]))
	check("  what was said is on the row, with who reported it",
		Staff.describe_report(report, 400).contains("reported 2x (spam) by ann, cat"), Staff.describe_report(report, 400))
	panel.apply_reports({"reports": [], "open": 0, "now": 400})
	check("  and an empty tab says so", panel.reports_empty.visible and panel.tabs.get_tab_title(Staff.REPORTS_TAB) == "Reports")

	# ---- ONE CARD PER REPORTED PLAYER (day 1: the tab would flood) ----
	var line_a := {"message_id": 11, "body": "spam line 5", "channel": "world", "said_at": 300,
		"reports": 2, "line_exists": true}
	var line_b := {"message_id": 10, "body": "spam line 4", "channel": "world", "said_at": 290,
		"reports": 1, "line_exists": false}
	var bob_card := {"reported": "bob", "reported_role": "player", "actionable": true, "line_count": 6,
		"reports": 7, "people": 2, "reporters": ["ann", "cat"], "reasons": {"spam": 7},
		"first_at": 100, "last_at": 340, "lines": [line_a, line_b]}
	var mod_card := {"reported": "othermod", "reported_role": "mod", "actionable": false, "line_count": 1,
		"reports": 1, "people": 1, "reporters": ["ann"], "reasons": {"harassment": 1},
		"first_at": 100, "last_at": 100, "lines": [{"message_id": 6, "body": "rude", "channel": "world",
			"said_at": 100, "reports": 1, "line_exists": true}]}
	panel.apply_reports({"players": [bob_card, mod_card], "reports": [report, peer, report],
		"open": 7, "open_players": 2, "now": 400})
	var cards: Array = panel.reports_list.get_children()
	check("the Reports tab is a card per player, and counts players",
		cards.size() == 2 and panel.tabs.get_tab_title(Staff.REPORTS_TAB) == "Reports (2)",
		[cards.size(), panel.tabs.get_tab_title(Staff.REPORTS_TAB)])
	check("  bob's card: delete each line still in chat, then open, mute or dismiss them all",
		cards.size() == 2 and buttons.call(cards[0]) == ["Delete", "Open bob", "Mute 1 hour", "Dismiss all"],
		buttons.call(cards[0]) if cards.size() > 0 else [])
	check("  a card about your own rank only opens the player",
		cards.size() == 2 and buttons.call(cards[1]) == ["Open othermod"], buttons.call(cards[1]) if cards.size() > 1 else [])
	var card_text: Array = []
	if cards.size() > 0:
		for l in (cards[0] as Node).find_children("*", "Label", true, false):
			card_text.append((l as Label).text)
	check("  it says how many lines, people and why, and how many older lines are not shown",
		card_text.has("bob") and "\n".join(card_text).contains("6 lines · 2 people · spam ×7")
		and card_text.has("and 4 older lines") and card_text.has("\"spam line 5\""), card_text)
	check("  each line says how often, where and when, and if it is gone from chat",
		Staff.describe_card_line(line_a, 400).begins_with("×2 · world")
		and Staff.describe_card_line(line_b, 400).ends_with("gone from chat"),
		[Staff.describe_card_line(line_a, 400), Staff.describe_card_line(line_b, 400)])
	check("  and the result is said in a sentence",
		Staff.card_result_words("mute", "bob", {"reports_closed": 6}) == "Muted bob for an hour and closed 6 reported lines."
		and Staff.card_result_words("dismissed", "bob", {"lines": 1}) == "Dismissed 1 reported line about bob.",
		Staff.card_result_words("mute", "bob", {"reports_closed": 6}))
	var card_src: String = _func_body(_code_src("res://src/ui/staff/staffpanel.gd"), "func _act_on_player_reports(")
	check("  Mute is one request - the server closes the card - and Dismiss closes it by name",
		card_src.contains("Api.post(\"/api/staff/mute\"") and not card_src.contains("\"message_id\"")
		and card_src.contains("{\"username\": who, \"outcome\": what}"))
	panel.apply_reports({"reports": [report], "open": 1, "now": 400})
	check("a server from before the cards still gets its per-line rows",
		panel.reports_list.get_child_count() == 1 and buttons.call(panel.reports_list.get_child(0))[0] == "Open rowdy")

	# ---- A QUIETER LOG ----
	var runs: Array = Staff.fold_runs([
		{"id": 9, "at": 1000, "by": "boss", "action": "grant", "target": "boss", "detail": "1 x a"},
		{"id": 8, "at": 990, "by": "boss", "action": "grant", "target": "boss", "detail": "1 x b"},
		{"id": 7, "at": 900, "by": "boss", "action": "grant", "target": "boss", "detail": "1 x c"},
		{"id": 6, "at": 890, "by": "boss", "action": "ban", "target": "rowdy", "detail": "1 days: x"},
		{"id": 5, "at": 880, "by": "boss", "action": "teleport", "target": "fighter", "detail": ""},
		{"id": 4, "at": 100, "by": "boss", "action": "teleport", "target": "fighter", "detail": ""},
		{"id": 3, "at": 90, "by": "warden", "action": "teleport", "target": "fighter", "detail": ""},
	])
	var sizes: Array = []
	for run in runs:
		sizes.append(run.size())
	check("the same thing done again and again folds into one line",
		sizes == [3, 1, 1, 1, 1], sizes)
	check("  but not across a long gap, or a different person",
		runs.size() == 5 and runs[3][0]["id"] == 4 and runs[4][0]["by"] == "warden")
	panel._log = runs[0] + runs[1]
	panel._render_log()
	var folded: Button = panel.log_entries.get_child(0).find_child("fold", true, false) as Button
	check("  drawn as one line with a count, the detail left out",
		folded != null and folded.get_meta("mark", "") == "closed"
		and folded.icon == Marks.texture("closed", folded.get_theme_color("font_color"))
		and folded.text.contains("  boss granted themselves items ×3 · from ")
		and not folded.text.contains("1 x")
		and panel.log_entries.get_child_count() == 2, folded.text if folded != null else "no fold")
	if folded != null:
		folded.pressed.emit()
	await get_tree().process_frame
	var opened: Node = panel.log_entries.get_child(panel.log_entries.get_child_count() - 2)
	var inside: Array = []
	for l in opened.find_children("*", "Label", true, false):
		inside.append((l as Label).text)
	check("  and opened with a click, every entry in it",
		inside.size() == 3 and str(inside[2]).ends_with("1 x c"), inside)
	panel._groups_ok = true
	check("a server that does not know Moderation is asked for everything instead",
		panel._group_refused({"ok": false, "status": 400}, "moderation") and not panel._groups_ok
		and not panel._group_refused({"ok": false, "status": 400}, "moderation"))
	panel._groups_ok = true
	panel.queue_free()

	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	var staff_button: Button = hud.get_node("%staffbutton") as Button
	var was := [Api.role, Api.is_owner]
	Api.role = "mod"
	hud._mark_open_reports(3)
	var lit: String = staff_button.text
	hud._mark_open_reports(0)
	var dark: String = staff_button.text
	Api.role = "player"
	hud._mark_open_reports(5)
	var as_player: String = staff_button.text
	Api.role = was[0]
	Api.is_owner = was[1]
	check("the Staff button counts reported lines waiting, and only for staff",
		lit == "Staff (3)" and dark == "Staff" and as_player == "Staff", [lit, dark, as_player])
	check("  from the poll", _func_body(_code_src("res://src/ui/characterhud.gd"), "func _apply_broadcast(")
		.contains("_mark_open_reports(int(data.get(\"open_reports\", 0)))"))
	Api.role = "mod"
	hud._mark_open_reports(1, 20)
	var by_player: String = staff_button.text
	var by_player_tip: String = staff_button.tooltip_text
	Api.role = was[0]
	check("  players, not lines, from a server that counts them: one spammer is Staff (1)",
		by_player == "Staff (1)" and by_player_tip.contains("1 player reported (20 lines)"), [by_player, by_player_tip])
	check("  read from the poll's open_report_players",
		_func_body(_code_src("res://src/ui/characterhud.gd"), "func _apply_broadcast(")
		.contains("_mark_open_reports(int(data.get(\"open_report_players\", 0)), int(data.get(\"open_reports\", 0)))"))
	hud.free()
	print("  staff: mute rules and words, the Actions row, the Reports tab both ways, the Staff button count")


func _test_a_failed_load_is_not_an_empty_account() -> void:
	section("CHARACTERS - a load that did not arrive is not four empty slots")

	# THE BUG, reproduced live: the character list timed out after the login,
	# character select showed four empty slots, and Create over the warrior
	# pushed an empty backpack over the real one.
	var store_src: String = _func_body(_code_src("res://src/systems/serverstorage.gd"), "func load(")
	check("every part of the load that fails is a failed load - the list, a character, the account",
		store_src.count("return LOAD_FAILED.duplicate()") == 4 and not store_src.contains("continue\n\n\t\tslots[index]"),
		store_src.count("return LOAD_FAILED.duplicate()"))

	# A storage whose load fails, so CharacterData can be watched reading it.
	var failing := GDScript.new()
	failing.source_code = "extends SaveStorage\nvar saves := 0\nfunc load() -> Dictionary:\n\treturn {\"load_failed\": true}\nfunc save(_payload: Dictionary) -> bool:\n\tsaves += 1\n\treturn true\n"
	failing.reload()
	var was := [CharacterData.storage, CharacterData.load_failed, CharacterData.character_slots,
		CharacterData.account_data, CharacterData._save_pending, CharacterData.current_username]
	CharacterData.storage = failing.new()
	CharacterData.load_failed = false
	var loaded: bool = await CharacterData.load_data()
	var flagged: bool = CharacterData.load_failed
	CharacterData._save_pending = false
	var queued: bool = CharacterData.save_data()
	var pending_after: bool = CharacterData._save_pending
	var wrote: bool = CharacterData._write_save_now()
	var handed: int = int(CharacterData.storage.saves)
	CharacterData.storage = was[0]
	CharacterData.load_failed = was[1]
	CharacterData.character_slots = was[2]
	CharacterData.account_data = was[3]
	CharacterData._save_pending = was[4]
	CharacterData.current_username = was[5]
	check("CharacterData marks it as failed, not as a fresh account", not loaded and flagged)
	check("  and saves nothing from it - not queued, not written, nothing handed to the server",
		not queued and not pending_after and not wrote and handed == 0, [queued, pending_after, wrote, handed])
	var ld_src: String = _func_body(_code_src("res://src/systems/characterdata.gd"), "func load_for_user(")
	check("  a new load starts unflagged", ld_src.find("load_failed = false") != -1
		and ld_src.find("load_failed = false") < ld_src.find("await load_data()"))

	var login_src: String = _code_src("res://src/ui/menus/loginmenu.gd")
	var complete: String = _func_body(login_src, "func _complete_login(")
	check("the login screen does not go to character select on a failed load",
		complete.find("if CharacterData.load_failed:") != -1
		and complete.find("if CharacterData.load_failed:") < complete.find("_go_to_character_select()"))
	var pressed: String = _func_body(login_src, "func _on_login_button_pressed(")
	check("  the button tries the load again, not the login - for the same name",
		pressed.find("if _retry_load and Api.is_logged_in()") != -1
		and pressed.find("if _retry_load and Api.is_logged_in()") < pressed.find("Api.login(")
		and pressed.contains("await _complete_login(Api.username)"))
	check("  and nothing wipes the message on the way back",
		pressed.contains("if not CharacterData.load_failed:\n\t\t\t_say(\"\", SAY_WORKING)")
		and _func_body(login_src, "func _create_account(").contains("if not CharacterData.load_failed:"))

	var login: Node = _login_screen_for_test()
	login.email_form.visible = true
	login.login_form.visible = false
	var name_was: String = Api.username
	Api.username = "robert"
	login._show_load_failed()
	Api.username = name_was
	var said: Label = login.get_node("%errorlabel")
	check("it says so, on the sign-in form, with the name filled in",
		login._retry_load and login.login_form.visible and not login.email_form.visible
		and said.text.begins_with("Your characters did not load")
		and said.get_theme_color("font_color") == login.SAY_BLOCKED
		and login.get_node("%usernamelineedit").text == "robert", said.text)
	login.free()
	print("  failed load: every part counts, flagged not fresh, nothing saved, the screen stays and retries")


func _test_character_select_has_a_way_out() -> void:
	section("CHARACTER SELECT - a way back to the login screen, and a slot that says what it holds")

	var Select: Script = load("res://src/ui/menus/characterselect.gd") as Script
	check("an occupied slot says its level, not its class twice",
		Select.slot_text({"character": "warrior", "level": 12}, "warrior") == "Level 12"
		and Select.slot_text({"character": "Warrior", "level": 3}, "warrior") == "Level 3"
		and Select.slot_text({"character": "Grimnir", "level": 5}, "warrior") == "Grimnir  |  Level 5")

	var screen: Node = (load("res://scene/ui/menus/characterselect.tscn") as PackedScene).instantiate()
	screen._build_logout_row()
	var button: Button = screen.logout_button
	var grid: Node = screen.get_node("centercontainer/mainpanel/margincontainer/vboxcontainer/gridcontainer")
	check("there is a Log out button, under the four heroes",
		button != null and button.text == "Log out" and button.get_parent().get_parent() == grid.get_parent()
		and button.get_parent().get_index() == grid.get_index() + 1)
	screen._build_logout_row()
	check("  built once, and by the screen itself",
		grid.get_parent().find_children("logoutrow*", "", false, false).size() == 1
		and _func_body(_code_src("res://src/ui/menus/characterselect.gd"), "func _ready(").contains("_build_logout_row()"))
	screen.free()

	var src: String = _func_body(_code_src("res://src/ui/menus/characterselect.gd"), "func _on_logout_pressed(")
	var saved: int = src.find("await CharacterData.finish_saving()")
	var cleared: int = src.find("CharacterData.clear_current_user()")
	var out: int = src.find("await Api.logout()")
	var gone: int = src.find("change_scene_to_file(LOGIN_MENU_PATH)")
	check("it saves, clears, signs out, then leaves - in that order, like the HUD's",
		saved != -1 and saved < cleared and cleared < out and out < gone, [saved, cleared, out, gone])
	check("  and not while the world is loading", src.contains("if _leaving or _entering:"))
	print("  character select: the level, Log out in place and once, and its order")


# =============================================================================
# THE MYTHIC WEAPONS - a weapon that brings its own attack
# =============================================================================
# Day 2: Ahvassa delivered a meteor, a double axe and a stick of dynamite, and
# the owner decided they are weapons - "an upgraded version of weapons because
# they have their own attack animation". Tier 6, level 22, one per class:
#
#   Meteorite (mage)    a meteor falls where you aim; one cast in ten, two
#   Double Axe (warrior) thrown to a spot, spins there, attack calls it back
#   Dynamite (tank)     a lit stick thrown where you aim, the ring lit while
#                       you throw; one throw in ten a bundle of three, one
#                       in a hundred a barrage of five (0.18.0)
#
# What can go wrong without a sound, and so is held here: an item that is not
# in the catalogue the server reads (it could never be worn), an attack that
# lands nowhere near where it was drawn, a hit that misses what is inside its
# ring or catches what is outside, an axe that never comes home or can be left
# working with nobody playing, a double cast that lands both on one spot, and a
# blast whose ground mark is placed before the blast has been moved - which
# happened: the first crater appeared under the player's spawn point.
