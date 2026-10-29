# testrunner_2.gd - part 2 of the suite (testrunner.gd says how it is
# split): 36 tests, _test_the_crypt_doors to _test_the_shop_buys.
extends "res://src/tools/testrunner_1.gd"


func _test_the_crypt_doors() -> void:
	section("THE CRYPT'S DOORS - the owner's door at 2x, worked with the interact key (0.63.0)")
	var world := Node2D.new()
	world.position = Vector2(-58000, -58000)
	add_child(world)
	var door: Node2D = (load("res://scene/crypt/door.tscn") as PackedScene).instantiate()
	world.add_child(door)
	var planks: Sprite2D = door.get_node("planks") as Sprite2D
	var shut_shape: CollisionShape2D = door.get_node("body/shut") as CollisionShape2D
	var width: float = 0.0
	for part in ["left", "planks", "right"]:
		var spr: Sprite2D = door.get_node(part) as Sprite2D
		width += (spr.texture as AtlasTexture).region.size.x * spr.scale.x
	var tall: float = (planks.texture as AtlasTexture).region.size.y * planks.scale.y
	check("the owner's door, drawn at twice its size: %d x %d px, the planks between two stone sides" % [int(width), int(tall)],
		is_equal_approx(width, 78.0) and is_equal_approx(tall, 56.0)
		and ((planks.texture as AtlasTexture).atlas as Texture2D).resource_path == "res://art/floordecoration/cryptdoor.png",
		[width, tall])
	await get_tree().physics_frame
	check("it starts shut: the planks showing, the gap between the sides blocked, on the walls' own layer",
		not door.call("is_open") and not shut_shape.disabled and is_equal_approx(planks.modulate.a, 1.0)
		and (door.get_node("body") as StaticBody2D).collision_layer == 1, [shut_shape.disabled, planks.modulate.a])
	check("  and it is a lever to presence.gd, so every game in the area sees it the same",
		door.is_in_group(&"levers") and door.has_method("follow_pull")
		and _func_body(_code_src("res://src/world/cryptdoor.gd"), "func work(").contains("Presence.tell_lever(self, _open)"))

	# A body pushed through the gap: stopped shut, through open.
	var walker := CharacterBody2D.new()
	walker.collision_layer = 4
	walker.collision_mask = 1
	var feet := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 6.0
	feet.shape = circle
	walker.add_child(feet)
	walker.position = Vector2(0, 30)
	world.add_child(walker)
	walker.add_to_group(&"player")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var through := Vector2(0, -70)
	check("shut, nobody walks through it", walker.test_move(walker.global_transform, through))

	# The interact key, pressed by a player in reach.
	check("  a player beside it is in its reach", door.get("_player_nearby") == walker, door.get("_player_nearby"))
	await _press_interact_a_frame()
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("the interact key opens it: the gap clears", door.call("is_open") and shut_shape.disabled, shut_shape.disabled)
	check("  and a player walks through", not walker.test_move(walker.global_transform, through))
	await get_tree().create_timer(0.45).timeout
	check("  the planks lifted out of sight, the stone sides standing",
		is_zero_approx(planks.modulate.a) and (door.get_node("left") as Sprite2D).visible and (door.get_node("right") as Sprite2D).visible,
		planks.modulate.a)
	await _press_interact_a_frame()
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("  and pressed again, it shuts", not door.call("is_open") and not shut_shape.disabled
		and walker.test_move(walker.global_transform, through))

	# It shuts itself behind a player who walks away - the owner, 20 Oct: "need
	# a door to close after player leaves proximity" - but not while they are
	# back, and never on anybody standing in the gap.
	var consts: Dictionary = (door.get_script() as GDScript).get_script_constant_map()
	var close_after: float = float(consts["CLOSE_AFTER"])
	await _press_interact_a_frame()
	walker.position = Vector2(0, 400)
	await _door_sees(door, walker, false)
	check("opened, and the player walks out of its reach: open a moment longer",
		door.call("is_open") and door.get("_player_nearby") == null and close_after > 0.0 and close_after <= 1.0, close_after)
	await get_tree().create_timer(close_after + 0.5).timeout
	check("  then it shuts itself behind them: the gap blocked, the planks back (%.1f s)" % close_after,
		not door.call("is_open") and not shut_shape.disabled and is_equal_approx(planks.modulate.a, 1.0)
		and walker.test_move(Transform2D(0.0, door.global_position + Vector2(0, 30)), through),
		[door.call("is_open"), shut_shape.disabled, planks.modulate.a])
	check("  and that shut is told to the area like one made with the key",
		_func_body(_code_src("res://src/world/cryptdoor.gd"), "func _close_now(").contains("Presence.tell_lever(self, false)"))
	walker.position = Vector2(0, 30)
	await _door_sees(door, walker, true)
	await _press_interact_a_frame()
	walker.position = Vector2(0, 400)
	await _door_sees(door, walker, false)
	walker.position = Vector2(0, 30)
	await _door_sees(door, walker, true)
	await get_tree().create_timer(close_after + 0.4).timeout
	check("  a player who steps back into reach before it shuts finds it still open", door.call("is_open") and shut_shape.disabled)
	var standing := CharacterBody2D.new()
	standing.collision_layer = 8
	standing.collision_mask = 0
	var its_feet := CollisionShape2D.new()
	var its_circle := CircleShape2D.new()
	its_circle.radius = 6.0
	its_feet.shape = its_circle
	standing.add_child(its_feet)
	standing.position = Vector2(0, -8)
	world.add_child(standing)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var open_before: bool = door.call("is_open")
	await _press_interact_a_frame()
	check("  the key will not shut it on a monster standing in the gap",
		open_before and door.call("is_open") and door.call("gap_taken"), [open_before, door.call("gap_taken")])
	walker.position = Vector2(0, 400)
	await _door_sees(door, walker, false)
	await get_tree().create_timer(close_after + 0.5).timeout
	check("  nor will it shut itself on them: it waits, open", door.call("is_open") and shut_shape.disabled)
	standing.free()
	await get_tree().physics_frame
	await get_tree().create_timer(float(consts["RECHECK_SECONDS"]) * 2.0 + 0.4).timeout
	check("  and shuts once the gap is clear", not door.call("is_open") and not shut_shape.disabled)

	# Out of reach, the key does nothing; somebody else's pull moves it.
	walker.position = Vector2(0, 400)
	await _door_sees(door, walker, false)
	await _press_interact_a_frame()
	check("a player out of reach cannot work it", not door.call("is_open") and door.get("_player_nearby") == null)
	door.call("follow_pull", true)
	await get_tree().physics_frame
	check("  but another player in the area opening it opens it here", door.call("is_open") and shut_shape.disabled)
	check("a monster cannot work a door: nothing in the enemies' code opens one",
		not _code_src("res://src/enemies/baseenemy.gd").contains("cryptdoor")
		and not _code_src("res://src/enemies/skeleton.gd").contains("follow_pull"))
	world.free()


func _test_monsters_go_out_in_a_burst() -> void:
	section("THE DEATH BURST - a monster with no death of its own breaks into pixels")
	var world := Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	var at := Vector2(-61000, -61000)
	var foe_at := func(path: String, offset: Vector2) -> BaseEnemy:
		var e: BaseEnemy = (load(path) as PackedScene).instantiate()
		e.position = at + offset
		world.add_child(e)
		e.set_physics_process(false)
		return e
	var bursts := func() -> Array:
		return world.get_children().filter(func(c: Node) -> bool: return c is DeathBurst)

	# ---- a fire sprite, killed ----------------------------------------------
	var fire: BaseEnemy = foe_at.call("res://scene/enemy/firesprite.tscn", Vector2.ZERO)
	fire.attack_direction = "down"
	fire.play_idle_animation("down")
	await get_tree().process_frame
	var sprite: AnimatedSprite2D = fire.get_node("animatedsprite2d")
	var shown: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	var stood: Vector2 = fire.global_position
	var fire_element: int = fire.current_element()
	fire.net_take_remote_hit(fire.max_hp * 3)
	var made: Array = bursts.call()
	check("a fire sprite killed leaves one DeathBurst, where it stood",
		made.size() == 1 and (made[0] as Node2D).global_position == stood, made.size())
	check("  and is freed that frame, as it always was - nothing waits on the burst",
		fire.is_queued_for_deletion())
	if made.size() != 1:
		world.free()
		return
	var burst: DeathBurst = made[0]
	burst.set_physics_process(false)
	var body: Sprite2D = burst.get_node("body")
	var white: Sprite2D = burst.get_node("white")
	var pixels: CPUParticles2D = burst.get_node("pixels")
	check("  it is the frame the sprite was showing, placed as the sprite was",
		body.texture == shown and white.texture == shown and body.offset == sprite.offset
		and body.flip_h == sprite.flip_h and body.position == sprite.position, [body.texture, shown])
	check("  it is nobody's target: in no group, nothing in it to hit",
		burst.get_groups().is_empty() and burst.find_children("*", "CollisionObject2D", true, false).is_empty())
	check("  it opens on the killing hit's flash", burst.showing() == &"flash"
		and body.modulate == BaseEnemy.HIT_FLASH_COLOR, burst.showing())
	burst.advance(DeathBurst.FLASH_SECONDS)
	check("  then a white shape, drawn by the crumble shader on a copy",
		burst.showing() == &"white" and white.material is ShaderMaterial
		and (white.material as ShaderMaterial).shader == DeathBurst.CRUMBLE_SHADER and sprite.material != white.material,
		burst.showing())
	burst.advance(DeathBurst.WHITE_SECONDS + DeathBurst.CRUMBLE_SECONDS * 0.5)
	check("  which breaks apart, throwing pixels out of it",
		burst.showing() == &"crumble" and burst.crumble > 0.3 and burst.crumble < 0.7 and pixels.emitting,
		[burst.showing(), burst.crumble])
	check("  the pixels cool from white to the colour of its element",
		pixels.color_ramp.colors[0] == Color.WHITE and pixels.color_ramp.colors[1] == Element.colour_for(fire_element),
		pixels.color_ramp.colors)
	check("  and come out of its body (its hurtbox), not a fixed square",
		pixels.emission_shape == CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		and pixels.amount >= DeathBurst.PIXELS_MIN and pixels.amount <= DeathBurst.PIXELS_MAX, pixels.amount)
	burst.advance(DeathBurst.CRUMBLE_SECONDS)
	check("  until nothing is left of the shape", not white.visible and not body.visible)
	burst.advance(DeathBurst.seconds())
	check("  and it frees itself once the last pixel has landed - about a second",
		burst.is_queued_for_deletion() and DeathBurst.seconds() <= 1.2, DeathBurst.seconds())

	# ---- the ones drawn dying keep their own death ---------------------------
	var small: BaseEnemy = (load("res://scene/enemy/poisonslime.tscn") as PackedScene).instantiate()
	small.set("is_small", true)
	small.position = at + Vector2(200, 0)
	world.add_child(small)
	small.set_physics_process(false)
	var large: BaseEnemy = foe_at.call("res://scene/enemy/poisonslime.tscn", Vector2(300, 0))
	check("the poison slime opts out, both forms: the small has its own death, the large splits",
		not small._bursts_on_death() and not large._bursts_on_death())
	small.net_take_remote_hit(small.max_hp * 3)
	await get_tree().create_timer(float(small.get("small_death_duration")) + 0.15).timeout
	# (The fire sprite's burst freed itself above, so the world holds none.)
	check("  a small slime plays smalldeath and goes, with no burst on top",
		(not is_instance_valid(small) or small.is_queued_for_deletion()) and bursts.call().is_empty(),
		bursts.call().size())
	var boss: BaseEnemy = foe_at.call("res://scene/enemy/bossenemy.tscn", Vector2(500, 0))
	boss.attack_direction = "down"
	var count_now: int = bursts.call().size()
	boss.net_take_remote_hit(boss.max_hp * 3)
	check("the Crowned plays its own death frames, with no burst",
		boss._dying and bursts.call().size() == count_now, [boss._dying, bursts.call().size()])

	# ---- another game's monster --------------------------------------------
	var mirrored: BaseEnemy = foe_at.call("res://scene/enemy/lightsprite.tscn", Vector2(700, 0))
	mirrored.net_mirror = true
	count_now = bursts.call().size()
	mirrored.net_vanish()
	check("a monster another game runs bursts here too when that game says it died",
		bursts.call().size() == count_now + 1)
	var dropped: BaseEnemy = foe_at.call("res://scene/enemy/lightsprite.tscn", Vector2(800, 0))
	count_now = bursts.call().size()
	dropped.net_remove()
	check("  but one simply taken away (net_remove) does not - that was no death",
		bursts.call().size() == count_now)

	# ---- every monster that bursts has a body to burst from ------------------
	var bodiless: Array = []
	var bursting: int = 0
	var dir := DirAccess.open("res://scene/enemy")
	for f in dir.get_files():
		if not f.ends_with(".tscn"):
			continue
		var e: Node = (load("res://scene/enemy/" + f) as PackedScene).instantiate()
		var spr: AnimatedSprite2D = e.get_node_or_null("animatedsprite2d") as AnimatedSprite2D
		var drawn_dying: bool = spr != null and spr.sprite_frames != null and (
			spr.sprite_frames.has_animation(&"deathdown") or spr.sprite_frames.has_animation(&"smalldeathdown"))
		if not drawn_dying and e.has_method("_bursts_on_death") and e.call("_bursts_on_death"):
			bursting += 1
			var box: CollisionShape2D = e.get_node_or_null("hurtbox/collisionshape2d") as CollisionShape2D
			if spr == null or box == null or box.shape == null:
				bodiless.append(f)
		e.free()
	check("every monster that bursts has a sprite and a hurtbox to break up (%d of them)" % bursting,
		bursting > 0 and bodiless.is_empty(), bodiless)

	# ---- what it costs -------------------------------------------------------
	# A meteor or a bundle of dynamite kills a crowd in one frame. Forty bursts
	# made at once, and a frame of all forty running, against the frame budget.
	var crowd: Array = []
	for i in 40:
		crowd.append(foe_at.call("res://scene/enemy/firesprite.tscn", Vector2(1000 + (i % 8) * 40, floorf(i / 8.0) * 40)))
	await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	var many: Array = []
	for e in crowd:
		many.append(DeathBurst.spawn(e))
	var make_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	for b in many:
		(b as DeathBurst).advance(DeathBurst.FLASH_SECONDS + DeathBurst.WHITE_SECONDS + 0.05)
	var run_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	check("forty bursts at once take under a quarter of a frame to make",
		many.size() == 40 and make_ms < FRAME_BUDGET_MS * 0.25, "%.2f ms" % make_ms)
	check("  and a frame of all forty running is a sliver of one",
		run_ms < FRAME_BUDGET_MS * 0.1, "%.2f ms" % run_ms)

	check("the burst is spawned only where a monster has no death* frames, in both deaths",
		_func_body(_code_src("res://src/enemies/baseenemy.gd"), "func _die(").contains("elif _bursts_on_death():")
		and _func_body(_code_src("res://src/enemies/baseenemy.gd"), "func net_vanish(").contains("elif _bursts_on_death():")
		and not _func_body(_code_src("res://src/enemies/baseenemy.gd"), "func net_remove(").contains("DeathBurst"))
	world.free()


# =============================================================================
# THE CRYPT'S SKELETONS (0.60.0, two kinds since 0.63.0)
# =============================================================================
# The owner, 19 Oct: "lets add skeletons" - Ahvassa's sheet - fighting by
# "chase and sword swing"; 20 Oct: "skeletons need a solid tier we wont
# recolor skeletons but we should make them elites and expand their size a
# little bit so normal skeletons and elite skeletons", "more elites in there".
# One body, two profiles: the Soldier (tier 3) in the crypt halls, the Elite
# (tier 4, 1.25x) three to a chamber; a blade that lands on the frame it is
# drawn landing, against wherever the player is by then. skeleton.gd says why.

func _test_the_crypt_skeletons() -> void:
	section("THE CRYPT'S SKELETONS - Ahvassa's skeleton, Soldiers and Elites, chasing and swinging (0.60.0, 0.63.0)")
	var Skeleton := preload("res://src/enemies/skeleton.gd")
	var Targets := preload("res://src/shared/targets.gd")
	var packed: PackedScene = load(SKELETON_BODY) as PackedScene
	check("the skeleton's body loads", packed != null)
	if packed == null:
		return

	# ---- Ahvassa's sheet ----------------------------------------------------------
	var probe: Node = packed.instantiate()
	var like: Node = (load("res://scene/enemy/firesprite.tscn") as PackedScene).instantiate()
	var sprite: AnimatedSprite2D = probe.get_node_or_null("animatedsprite2d") as AnimatedSprite2D
	var sf: SpriteFrames = sprite.sprite_frames if sprite != null else null
	check("a monster of its own script, on every other monster's layers, with a hurtbox like theirs",
		probe is BaseEnemy and (probe.get_script() as Script).resource_path == "res://src/enemies/skeleton.gd"
		and (probe as CollisionObject2D).collision_layer == (like as CollisionObject2D).collision_layer
		and (probe as CollisionObject2D).collision_mask == (like as CollisionObject2D).collision_mask
		and probe.get_node_or_null("hurtbox") is Area2D
		and (probe.get_node("hurtbox") as Area2D).collision_layer == (like.get_node("hurtbox") as Area2D).collision_layer,
		[(probe as CollisionObject2D).collision_layer, (probe as CollisionObject2D).collision_mask])
	like.free()
	if sf == null:
		check("it has its frames", false)
		probe.free()
		return
	# Top to bottom: facing right, left, down, up - read off the skull, whose
	# eyes are on the side it faces (the first group's are on the right).
	var groups := ["right", "left", "down", "up"]
	var rows := {"idle": [0, 8], "walk": [1, 6], "attack": [2, 8]}
	var wrong: Array = []
	var speeds := {}
	for g in groups.size():
		for kind in rows:
			var anim := StringName(kind + groups[g])
			if not sf.has_animation(anim):
				wrong.append("%s missing" % anim)
				continue
			var count: int = sf.get_frame_count(anim)
			if count != int(rows[kind][1]):
				wrong.append("%s has %d frames" % [anim, count])
			for i in count:
				var tex: AtlasTexture = sf.get_frame_texture(anim, i) as AtlasTexture
				var want := Rect2(i * 64, (g * 4 + int(rows[kind][0])) * 64, 64, 64)
				if tex == null or tex.atlas == null or tex.atlas.resource_path != SKELETON_SHEET or tex.region != want:
					wrong.append("%s frame %d" % [anim, i])
			if not speeds.has(kind):
				speeds[kind] = []
			if not (speeds[kind] as Array).has(sf.get_animation_speed(anim)):
				(speeds[kind] as Array).append(sf.get_animation_speed(anim))
	check("Ahvassa's sheet, every frame where she drew it: right, left, down, up, each an idle of 8, a walk of 6, a swing of 8",
		wrong.is_empty() and sf.get_animation_names().size() == 12, [wrong.slice(0, 6), sf.get_animation_names().size()])
	check("  each at one speed whichever way it faces", speeds.size() == 3
		and speeds.keys().all(func(k): return (speeds[k] as Array).size() == 1), speeds)
	var loops_wrong: Array = []
	for d in groups:
		if sf.get_animation_loop(StringName("attack" + d)) or not sf.get_animation_loop(StringName("idle" + d)) \
				or not sf.get_animation_loop(StringName("walk" + d)):
			loops_wrong.append(d)
	check("  the swing plays once, at the speed its timing is worked out at, and the idle and walk loop",
		loops_wrong.is_empty() and is_equal_approx(sf.get_animation_speed(&"attackdown"), Skeleton.ATTACK_FPS),
		[loops_wrong, sf.get_animation_speed(&"attackdown")])
	var not_widest: Array = []
	for d in groups:
		var anim := StringName("attack" + d)
		var widest: int = -1
		var most: int = -1
		for i in sf.get_frame_count(anim):
			var drawn: int = _opaque_count(_frame_image(sf, anim, i))
			if drawn > most:
				most = drawn
				widest = i
		if widest != Skeleton.SWING_FRAME:
			not_widest.append("%s: frame %d" % [anim, widest])
	check("the blade lands on the frame she drew the sword widest, every way it faces (frame %d, %.1f s in)"
		% [Skeleton.SWING_FRAME, Skeleton.SWING_FRAME / Skeleton.ATTACK_FPS], not_widest.is_empty(), not_widest)
	var own_death: Array = Array(sf.get_animation_names()).filter(func(a): return str(a).begins_with("death") or str(a).begins_with("hitflash"))
	check("  no death and no flash rows: it breaks up in a burst like any monster without one",
		own_death.is_empty() and (probe as BaseEnemy)._bursts_on_death(), own_death)
	probe.free()

	# ---- two of them: a Soldier and an Elite, one tier each -----------------------
	var rules := preload("res://src/systems/gameconstants.gd")
	var soldier: EnemyData = load("res://data/enemies/skeletonsoldier.tres") as EnemyData
	var elite: EnemyData = load("res://data/enemies/skeletonelite.tres") as EnemyData
	var bodies: Array = []
	for path in [SKELETON_SOLDIER, SKELETON_ELITE]:
		var variant: PackedScene = load(path) as PackedScene
		var base: PackedScene = variant.get_state().get_node_instance(0) if variant != null else null
		var one: Node = variant.instantiate() if variant != null else null
		bodies.append([base.resource_path if base != null else "", one.get("enemy_data") if one != null else null,
			(one as Node2D).scale if one != null else Vector2.ZERO, float(one.get("melee_range")) if one != null else 0.0])
		if one != null:
			one.free()
	check("two skeletons: the Soldier and the Elite, each the one body with its profile in its scene file - a respawn rebuilds from the file",
		soldier != null and elite != null and bodies[0][0] == SKELETON_BODY and bodies[1][0] == SKELETON_BODY
		and bodies[0][1] == soldier and bodies[1][1] == elite, bodies)
	if soldier == null or elite == null:
		return
	check("  one solid tier each, no recolours: every Soldier tier 3, every Elite tier 4",
		soldier.max_loot_tier == 3 and elite.max_loot_tier == 4 and soldier.element == elite.element,
		[soldier.max_loot_tier, elite.max_loot_tier])
	check("  the Elite a size up - 1.25x - and its sword's reach with it",
		bodies[0][2] == Vector2.ONE and bodies[1][2] == Vector2(1.25, 1.25)
		and is_equal_approx(float(bodies[1][3]), float(bodies[0][3]) * 1.25), [bodies[0][2], bodies[1][2], bodies[0][3], bodies[1][3]])
	check("  and tougher, harder hitting and worth more",
		elite.max_hp > soldier.max_hp * 3 and elite.projectile_damage > soldier.projectile_damage
		and elite.xp_reward > soldier.xp_reward * 3, [soldier.max_hp, elite.max_hp])
	var kin3: EnemyData = load("res://data/enemies/earthbushsniper.tres") as EnemyData
	var kin4: EnemyData = load("res://data/enemies/firebushmage.tres") as EnemyData
	check("a Soldier drops like any tier-3 monster: a bag 30% of the time, its tier rolled as theirs",
		is_equal_approx(soldier.bag_drop_chance, kin3.bag_drop_chance) and soldier.tier_odds == kin3.tier_odds
		and soldier.max_item_slots == 1 and is_equal_approx(soldier.slot_fill_chance, 0.3)
		and is_zero_approx(soldier.tier_up_chance), [soldier.bag_drop_chance, soldier.tier_odds])
	check("an Elite always drops a bag - a piece of its tier, a potion half the time - its tier rolled as tier 4's, never a tier up",
		elite.grants_rewards and is_equal_approx(elite.bag_drop_chance, 1.0) and elite.max_item_slots == 1
		and is_equal_approx(elite.slot_fill_chance, 1.0) and is_equal_approx(elite.bonus_potion_chance, 0.5)
		and elite.tier_odds == kin4.tier_odds and is_zero_approx(elite.tier_up_chance))
	# THE SERVER TELLS A BOSS BY ITS BAG: one guaranteed piece of gear
	# (killwatch.py is_boss(), the API's "seven bosses"). A gear-only slot would
	# have made each Elite a boss to the books.
	check("  and neither is a boss to the server, which tells a boss by a gear-only bag",
		not soldier.slots_are_gear and not elite.slots_are_gear)
	var odds: Array = []
	for d in [soldier, elite]:
		var want: int = int(rules.MYTHIC_ODDS_BY_TIER.get(d.max_loot_tier, 0))
		if want <= 0 or d.mythic_odds() != want or d.mythic_odds_override != 0:
			odds.append([d.enemy_id, d.mythic_odds(), want])
	check("  their mythic chance is any monster's of their tier, from the table", odds.is_empty(), odds)
	check("no skeleton pet has been drawn, so neither rolls for one: each says it drops no pet",
		soldier.drops_no_pet and elite.drops_no_pet and soldier.pet_drop_id == "" and elite.pet_drop_id == "")
	check("an Elite comes back three minutes after it falls; a Soldier with the area",
		is_equal_approx(elite.respawn_seconds, 180.0) and is_zero_approx(soldier.respawn_seconds))

	var exported: Dictionary = {}
	var spawns: Dictionary = {}
	var json: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/gamedata.json"))
	if json is Dictionary:
		for e in (json as Dictionary).get("enemies", []):
			exported[str(e.get("enemy_id", ""))] = e
		for sp in (json as Dictionary).get("areas", {}).get("bigfield", {}).get("spawns", []):
			spawns[str(sp.get("e", ""))] = int(spawns.get(str(sp.get("e", "")), 0)) + 1
	var books: Array = []
	for d in [soldier, elite]:
		var e: Dictionary = exported.get(d.enemy_id, {})
		if e.is_empty() or int(e.get("pet_odds", -1)) != 0 or int(e.get("mythic_odds", 0)) != d.mythic_odds() \
				or int(e.get("max_hp", 0)) != d.max_hp or int(e.get("xp_reward", 0)) != d.xp_reward:
			books.append(d.enemy_id)
	var gone: Array = ["skeletonguard", "skeletonwarden", "skeletonknight", "skeletonchampion", "skeletonlord"].filter(
		func(id): return exported.has(id) or ResourceLoader.exists("res://data/enemies/%s.tres" % id))
	check("the export carries both for the server's books - %d Soldiers and %d Elites placed - and the five alcove skeletons are gone"
		% [int(spawns.get("skeletonsoldier", 0)), int(spawns.get("skeletonelite", 0))],
		books.is_empty() and gone.is_empty() and int(spawns.get("skeletonsoldier", 0)) == BIG_FIELD_SOLDIERS
		and int(spawns.get("skeletonelite", 0)) == BIG_FIELD_ELITES, [books, gone])

	# ---- the crypt (0.94.0): its own wing, skeletons and nothing else - Patrols
	# and Warbands of Soldiers, an Elite and its guard in the room furthest in ----
	var field: Node = (load(BIG_FIELD) as PackedScene).instantiate()
	var in_crypt: Dictionary = {}
	var astray: Array = []
	for enemy in field.get_node("ysortworld/enemies").get_children():
		var kind: String = str(enemy.scene_file_path).get_file().get_basename()
		var land: String = str(enemy.name).get_slice("_", 0)
		if land == "plain":
			in_crypt[kind] = int(in_crypt.get(kind, 0)) + 1
			if not kind.begins_with("skeleton"):
				astray.append(enemy.name)
	check("the crypt holds skeletons and nothing else: %s" % [in_crypt],
		int(in_crypt.get("skeletonsoldier", 0)) >= 20 and int(in_crypt.get("skeletonelite", 0)) == 1 and astray.is_empty(),
		[in_crypt, astray.slice(0, 4)])
	field.free()

	# ---- the fight ----------------------------------------------------------------
	var world := Node2D.new()
	add_child(world)
	var at := Vector2(-61000, -61000)
	var foe: BaseEnemy = (load(SKELETON_SOLDIER) as PackedScene).instantiate()
	foe.position = at
	world.add_child(foe)
	foe.set_physics_process(false)
	foe.set_process(false)
	var reach: float = float(foe.get("melee_range"))
	var stand: float = float(foe.call("fighting_distance"))
	var near := SwingDummy.new()
	near.position = at + Vector2(0, stand)
	world.add_child(near)
	var far := SwingDummy.new()
	far.position = at + Vector2(reach + 30.0, 0)
	world.add_child(far)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("it fights up close: it swings from inside its reach, and never backs off",
		is_equal_approx(foe.attack_range, reach) and is_zero_approx(foe.flee_range) and stand < reach
		and Formation.ring_radius(1) <= stand, [foe.attack_range, foe.flee_range, stand, reach])

	# A pack holding the inner ring: the skeleton is handed an outer slot, past
	# a sword, and comes in to fighting distance on that slot's bearing.
	var owners: Dictionary = BaseEnemy._slot_owners
	var owners_were: Dictionary = owners.duplicate()
	owners.clear()
	for i in Formation.slot_count():
		if Formation.ring_of(i) == 1:
			owners[i] = far
	foe.player = near
	var slot_at: Vector2 = foe.call("_get_slot_target_position")
	var slot: int = int(foe.get("_claimed_slot"))
	var raw: Vector2 = Formation.world_position(near.global_position, slot)
	check("handed an outer slot while a pack holds the inner ring, it comes in to sword's reach on that slot's bearing",
		Formation.ring_of(slot) > 1 and raw.distance_to(near.global_position) > reach
		and absf(slot_at.distance_to(near.global_position) - stand) < 0.5
		and absf((slot_at - near.global_position).angle_to(raw - near.global_position)) < 0.01,
		[Formation.ring_of(slot), raw.distance_to(near.global_position), slot_at.distance_to(near.global_position)])
	owners.clear()
	owners.merge(owners_were)
	foe.set("_claimed_slot", -1)
	foe.player = null

	var skel_sprite: AnimatedSprite2D = foe.get_node("animatedsprite2d")
	foe.attack_direction = "down"
	foe.call("_trigger_attack")
	skel_sprite.pause()
	var early: bool = near.taken.is_empty()
	for f in range(1, Skeleton.SWING_FRAME):
		skel_sprite.frame = f
		if not near.taken.is_empty():
			early = false
	check("a swing begun is a warning, not a hit: nothing lands before the blade does",
		str(skel_sprite.animation) == "attackdown" and early, [str(skel_sprite.animation), near.taken])
	skel_sprite.frame = Skeleton.SWING_FRAME
	var blow: int = int(foe.call("swing_damage"))
	check("on the frame it lands, the player in reach takes the profile's blow, once - body and hurtbox are one player",
		near.taken == [[foe.enemy_data.projectile_damage, foe.current_element()]] and blow == foe.enemy_data.projectile_damage,
		near.taken)
	check("  and a player out of reach takes nothing", far.taken.is_empty(), far.taken)
	skel_sprite.frame = Skeleton.SWING_FRAME + 1
	check("  one blow a swing: the frames after it land nothing more", near.taken.size() == 1, near.taken)

	# The next swing, the way the game gets there: the swing ends, the idle
	# plays, the cooldown runs out, it swings again. The player steps back
	# during the wind-up.
	skel_sprite.animation_finished.emit()
	check("the swing ending frees it to move again", not foe.is_attacking and str(skel_sprite.animation) == "idledown",
		[foe.is_attacking, str(skel_sprite.animation)])
	foe.call("_trigger_attack")
	skel_sprite.pause()
	near.position = at + Vector2(0, reach + 30.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	skel_sprite.frame = Skeleton.SWING_FRAME
	check("stepping out of reach during the wind-up works: the blade lands where the player was", near.taken.size() == 1,
		near.taken)
	near.position = at + Vector2(0, stand)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# SHARED MONSTERS. The leader's blow tells the others; a mirror's swing is a
	# picture, and its blow is the leader's, arriving as "m".
	var sync := SwingSync.new()
	world.add_child(sync)
	foe.set("_net_sync", sync)
	skel_sprite.animation_finished.emit()
	foe.call("_trigger_attack")
	skel_sprite.pause()
	skel_sprite.frame = Skeleton.SWING_FRAME
	check("a shared skeleton's blow is told to the other games, as the boss's is",
		sync.events == [{"k": "m"}] and near.taken.size() == 2, [sync.events, near.taken.size()])
	foe.set("_net_sync", null)
	foe.net_mirror = true
	skel_sprite.play(&"idledown")
	skel_sprite.play(&"attackdown")
	skel_sprite.pause()
	skel_sprite.frame = Skeleton.SWING_FRAME
	check("  a mirror's swing lands nothing of its own", near.taken.size() == 2, near.taken.size())
	foe.call("_land_swing")
	check("  and the leader's blow, arriving, lands on this game's player in reach of the mirror",
		near.taken.size() == 3, near.taken.size())
	check("  (monstersync.gd hands \"m\" to any monster with a swing, not only the boss)",
		_func_body(_code_src("res://src/world/monstersync.gd"), "func _apply_event(").contains("mirror.has_method(\"_land_swing\")"))
	foe.net_mirror = false

	# ---- every class, from wherever it stands -----------------------------------------
	var missed: Array = []
	var from_afar: Array = []
	var tank_swung: bool = false
	var tank_stand: Array = [0, INF]
	foe.position = at + Vector2(0, -3000)
	for class_id in ["warrior", "mage", "healer", "tank"]:
		var hero: Node2D = (load("res://scene/characters/%s.tscn" % class_id) as PackedScene).instantiate()
		hero.position = at + Vector2(0, 3000)
		world.add_child(hero)
		hero.set_physics_process(false)
		hero.set_process(false)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var body: Vector2 = Targets.body_point(hero)
		for k in 8:
			var bearing := Vector2.RIGHT.rotated(TAU * k / 8.0)
			foe.global_position = body + bearing * stand
			if not (foe.call("players_in_reach") as Array).has(hero):
				missed.append("%s from %d deg" % [class_id, k * 45])
			foe.global_position = body + bearing * 100.0
			if not (foe.call("players_in_reach") as Array).is_empty():
				from_afar.append("%s from %d deg" % [class_id, k * 45])
		if class_id == "tank":
			# North of a tank, 50 px from where it stands and 34 from its body.
			foe.global_position = hero.global_position + Vector2(0, -50)
			foe.player = hero
			foe.attack_ready = true
			foe.is_attacking = false
			foe.call("play_idle_animation", "down")
			foe.call("_handle_combat", foe.global_position.distance_to(hero.global_position))
			tank_swung = foe.is_attacking and str(skel_sprite.animation).begins_with("attack") \
				and foe.global_position.distance_to(body) < reach
			# South of it, its inner-ring slot is 24 px below the feet and 40
			# from the body: brought in to fighting distance of the body.
			var held: Dictionary = BaseEnemy._slot_owners.duplicate()
			BaseEnemy._slot_owners.clear()
			foe.set("_claimed_slot", -1)
			# Its turn to look for a place now (since 0.68.0 a monster with none
			# looks every SLOT_RETRY_SECONDS, and the swings above had it looking).
			foe.set("_slot_retry_time", 0.0)
			foe.global_position = hero.global_position + Vector2(0, 60)
			var south: Vector2 = foe.call("_get_slot_target_position")
			tank_stand = [Formation.ring_of(int(foe.get("_claimed_slot"))), south.distance_to(body)]
			BaseEnemy._slot_owners.clear()
			BaseEnemy._slot_owners.merge(held)
			foe.set("_claimed_slot", -1)
			foe.player = null
			foe.is_attacking = false
		hero.free()
	check("from fighting distance of the body, on any bearing, the blade reaches every class", missed.is_empty(), missed)
	check("  and from 100 px off it reaches none - not even the tank, whose aura is on the players' layer, 150 px wide",
		from_afar.is_empty(), from_afar)
	check("  and it is in reach when the body is, not the origin: it swings at a tank whose feet are past its sword",
		tank_swung)
	check("  and stands to the body: south of a tank, its inner-ring slot is brought in to fighting distance",
		int(tank_stand[0]) == 1 and float(tank_stand[1]) <= stand + 0.5, tank_stand)
	world.free()

	# ---- three minutes ------------------------------------------------------------
	var arena := Node2D.new()
	add_child(arena)
	var bones: Node2D = (load(SKELETON_ELITE) as PackedScene).instantiate()
	bones.position = Vector2(-9000, -12000)
	arena.add_child(bones)
	var light: Node2D = (load("res://scene/enemy/lightsprite.tscn") as PackedScene).instantiate()
	light.position = Vector2(-9300, -12000)
	arena.add_child(light)
	var clock := RespawnClock.new()
	clock.spawn_scatter = 0.0
	clock.respawn_jitter = 0.0
	arena.add_child(clock)
	await get_tree().process_frame
	await get_tree().process_frame
	bones.set_physics_process(false)
	light.set_physics_process(false)
	bones.emit_signal("died")
	light.emit_signal("died")
	check("a fallen Elite is back in its profile's three minutes, the monsters round it in the area's %d s"
		% int(clock.respawn_seconds), clock.asked == [180.0, clock.respawn_seconds], clock.asked)
	clock.respawn_seconds = 600.0
	check("  never sooner than its area's own time", is_equal_approx(clock.respawn_time_for(bones), 600.0)
		and is_equal_approx(clock.respawn_time_for(light), 600.0))
	clock.asked.clear()
	clock.respawn_seconds = 30.0
	clock.resume_authority()
	check("  and a game taking the area over gives it its full three minutes too",
		clock.asked.has(180.0) and clock.asked.has(30.0), clock.asked)
	arena.free()
	print("  Soldier %d hp, Elite %d hp; a %d px sword landing on frame %d; an Elite back after %d s"
		% [soldier.max_hp, elite.max_hp, int(reach), Skeleton.SWING_FRAME, int(elite.respawn_seconds)])


# =============================================================================
# THE HIT FLASH IS THE ARTIST'S WHITE (0.58.0)
# =============================================================================
# The owner: "every enemy and player has hitflash made for the animations why
# did we not use them?" - and of the fix, "im hoping will not cause issue with
# the frames". Played as animations they cut off whatever was running (the
# boss froze mid-cast), so the flash doubled the sprite's colour instead. Now
# hitflash.gd draws the frame on screen as a solid white shape ON TOP of the
# sprite. These hold it to the owner's worry first: the sprite's animation,
# frame, speed, tint and material are what they were, a cast keyed to its
# frames runs to its end, and the white keeps up with every frame it shows.

func _test_a_hit_flashes_the_artists_white() -> void:
	section("THE HIT FLASH - the artist's white over the frame on screen, the frames untouched")
	var HitFlashScript := preload("res://src/shared/hitflash.gd")
	var white_shader: Shader = preload("res://src/shared/hitflash.gdshader")
	var world := Node2D.new()
	add_child(world)
	var at := Vector2(-63000, -63000)
	var flashes_on := func(on_sprite: AnimatedSprite2D) -> Array:
		return on_sprite.get_children().filter(func(c: Node) -> bool:
			return c is Sprite2D and str(c.name).begins_with("hitflash") and not c.is_queued_for_deletion())

	# ---- a monster, hit mid-swing ------------------------------------------------
	var foe: BaseEnemy = (load("res://scene/enemy/firesprite.tscn") as PackedScene).instantiate()
	foe.position = at
	world.add_child(foe)
	foe.set_physics_process(false)
	foe.set_process(false)
	await get_tree().process_frame
	var sprite: AnimatedSprite2D = foe.get_node("animatedsprite2d")
	sprite.play(&"attackdown")
	sprite.frame = 2
	var tint_before: Color = sprite.modulate
	var material_before: Material = sprite.material
	var speed_before: float = sprite.speed_scale
	foe.play_hit_flash()
	var white: Sprite2D = HitFlashScript.on(sprite)
	check("a hit puts a white copy on top of the monster's sprite, inside it",
		white != null and white.get_parent() == sprite and not white.show_behind_parent and white.z_index == 0, white)
	if white == null:
		world.free()
		return
	white.set_process(false)
	check("  of the frame on screen, placed as the sprite places it",
		white.texture == sprite.sprite_frames.get_frame_texture(&"attackdown", 2) and white.offset == sprite.offset
		and white.centered == sprite.centered and white.flip_h == sprite.flip_h, [white.texture, white.offset])
	var shape: ShaderMaterial = white.material as ShaderMaterial
	check("  drawn as a solid white shape - the artist's flash - with the sprite's own fade",
		shape != null and shape.shader == white_shader
		and white_shader.code.contains("COLOR = vec4(1.0, 1.0, 1.0, COLOR.a);"), shape)
	check("  and the sprite is just as it was: the same swing, the same frame, still playing, its tint, its material, its speed",
		str(sprite.animation) == "attackdown" and sprite.frame == 2 and sprite.is_playing()
		and sprite.modulate == tint_before and sprite.material == material_before and sprite.speed_scale == speed_before,
		[str(sprite.animation), sprite.frame, sprite.is_playing(), sprite.modulate])
	sprite.frame = 3
	check("  the white shows the next frame the moment the sprite does",
		white.texture == sprite.sprite_frames.get_frame_texture(&"attackdown", 3))
	sprite.play(&"walkdown")
	check("  and a new animation", white.texture == sprite.sprite_frames.get_frame_texture(&"walkdown", sprite.frame)
		and str(sprite.animation) == "walkdown")
	sprite.flip_h = not sprite.flip_h
	white.call("advance", 0.0)
	check("  and a turn", white.flip_h == sprite.flip_h)
	sprite.flip_h = not sprite.flip_h
	white.call("advance", foe.hit_flash_duration * 0.5)
	foe.play_hit_flash()
	check("a second hit restarts the flash: one white on the sprite, not two, with its full time",
		flashes_on.call(sprite).size() == 1 and HitFlashScript.on(sprite) == white
		and is_equal_approx(float(white.get("seconds_left")), foe.hit_flash_duration),
		[flashes_on.call(sprite).size(), white.get("seconds_left")])
	white.call("advance", foe.hit_flash_duration + 0.01)
	check("  gone when its time is up, nothing of it left: not on the sprite, not listening to it",
		HitFlashScript.on(sprite) == null and white.is_queued_for_deletion() and not white.visible
		and not sprite.frame_changed.is_connected(Callable(white, "follow")) and sprite.modulate == tint_before
		and sprite.material == material_before)
	foe.play_hit_flash()
	check("  and the next hit flashes afresh", HitFlashScript.on(sprite) != null and HitFlashScript.on(sprite) != white)

	# ---- the boss's cast, the one the frames used to freeze ----------------------
	var boss: BaseEnemy = (load("res://scene/enemy/bossenemy.tscn") as PackedScene).instantiate()
	boss.position = at + Vector2(400, 0)
	world.add_child(boss)
	boss.set_physics_process(false)
	boss.set_process(false)
	await get_tree().process_frame
	var cast: AnimatedSprite2D = boss.get_node("animatedsprite2d")
	var last_frame: int = cast.sprite_frames.get_frame_count(&"castdown") - 1
	var finished: Array = [false]
	cast.animation_finished.connect(func() -> void: finished[0] = true, CONNECT_ONE_SHOT)
	cast.play(&"castdown")
	var shown: Array = []
	var mismatched: Array = []
	var flashed: int = 0
	var waited: float = 0.0
	while not finished[0] and waited < 5.0:
		if cast.frame != (shown[-1] if not shown.is_empty() else -1):
			shown.append(cast.frame)
			# A hit on every frame of the cast: the worst case for the old flash.
			boss.play_hit_flash()
			flashed += 1
		var on_it: Sprite2D = HitFlashScript.on(cast)
		if on_it != null and on_it.texture != cast.sprite_frames.get_frame_texture(cast.animation, cast.frame):
			mismatched.append(cast.frame)
		await get_tree().process_frame
		waited += get_process_delta_time()
	check("the boss hit on every frame of its cast still casts to its end (it froze, when the flash was frames)",
		finished[0] and str(cast.animation) == "castdown" and cast.frame == last_frame and shown.size() >= 3,
		[finished[0], str(cast.animation), cast.frame, last_frame, shown])
	check("  and the white was the frame on screen on every one of them",
		mismatched.is_empty() and flashed == shown.size(), [mismatched, flashed, shown.size()])

	# ---- the four classes -----------------------------------------------------------
	var classes_ok: Array = []
	for class_name_id in ["warrior", "mage", "healer", "tank"]:
		var hero: Node2D = (load("res://scene/characters/%s.tscn" % class_name_id) as PackedScene).instantiate()
		hero.position = at + Vector2(800, 0)
		world.add_child(hero)
		hero.set_physics_process(false)
		hero.set_process(false)
		await get_tree().process_frame
		var body: AnimatedSprite2D = hero.get_node("animatedsprite2d")
		var playing: StringName = body.animation
		var frame_was: int = body.frame
		var tint_was: Color = body.modulate
		hero.call("_play_hit_flash")
		var hero_white: Sprite2D = HitFlashScript.on(body)
		var defended: float = maxf(0.05, float(hero.get("hit_flash_duration"))
			* (1.0 - float((hero.call("_get_defense_tier") as Dictionary)["reduction"])))
		if hero_white == null or body.animation != playing or body.frame != frame_was or body.modulate != tint_was \
				or hero_white.texture != body.sprite_frames.get_frame_texture(body.animation, body.frame) \
				or not is_equal_approx(float(hero_white.get("seconds_left")), defended):
			classes_ok.append([class_name_id, hero_white, str(playing), str(body.animation), body.modulate])
		hero.free()
	check("every class flashes the artist's white over its frame, for as long as its defence says, its own animation untouched",
		classes_ok.is_empty(), classes_ok)
	var swaps: Array = []
	for script_path in _all_files_under("res://src", ".gd"):
		if _is_suite_script(script_path) or script_path.ends_with("poisonslime.gd"):
			continue
		var code: String = FileAccess.get_file_as_string(script_path)
		if code.contains("play(\"hitflash") or code.contains("_set_animation(\"hitflash"):
			swaps.append(script_path)
	check("  and nothing plays a hitflash animation over what a body is doing (the large poison slime's split is its own)",
		swaps.is_empty(), swaps)

	# ---- somebody else, seen here -----------------------------------------------------
	var Remote := preload("res://src/characters/remoteplayer.gd")
	var other: Node2D = Remote.new()
	world.add_child(other)
	other.call("set_identity", {"id": 4321, "name": "flashed", "cls": "warrior"})
	var other_body: AnimatedSprite2D = other.get_node_or_null("animatedsprite2d") as AnimatedSprite2D
	other.call("set_bearing", -1, 80)
	check("another player seen here does not flash while their health holds",
		other_body != null and HitFlashScript.on(other_body) == null)
	other.call("set_bearing", -1, 60)
	var other_white: Sprite2D = HitFlashScript.on(other_body) if other_body != null else null
	check("  and flashes the same white when it drops - every class, where only the tank's ever showed",
		other_white != null and other_white.texture == other_body.sprite_frames.get_frame_texture(other_body.animation, other_body.frame)
		and is_equal_approx(float(other_white.get("seconds_left")), float(Remote.HIT_FLASH_SECONDS)), other_white)
	if other_white != null:
		other_white.call("advance", 1.0)
	other.call("set_bearing", -1, 90)
	check("  but not when it rises", other_body != null and HitFlashScript.on(other_body) == null)
	world.free()


func _test_the_arrival_portal_closes_behind_you() -> void:
	section("THE ARRIVAL PORTAL - it closes as you walk away from where you landed")

	for area_id in ["bigfield", "field"]:
		var area: Node = (load(AreaRegistry.AREAS[area_id]) as PackedScene).instantiate()
		var door: Node = area.get_node_or_null("ysortworld/interactables/fieldteleport")
		check("%s: its arrival portal closes by itself, not only through its trigger" % AreaRegistry.display_name(area_id),
			door != null and bool(door.get("vanish_after_first_use")) and door.has_method("_physics_process"))
		area.free()

	var consts: Dictionary = (load("res://src/world/leavetown.gd") as GDScript).get_script_constant_map()
	var leave: float = float(consts.get("LEAVE_DISTANCE", 0.0))
	var holder := Node2D.new()
	add_child(holder)
	var at := Vector2(5000, 5000)
	var make_portal := func() -> Node:
		var d = (load("res://src/world/leavetown.gd") as GDScript).new()
		d.arrival_only = true
		d.vanish_after_first_use = true
		holder.add_child(d)
		d.global_position = at
		return d
	var walker := Node2D.new()
	walker.name = "walker"
	walker.add_to_group("player")
	holder.add_child(walker)
	walker.global_position = at + Vector2(0, 12)
	check("(the stand-in is the player the portal will find)", get_tree().get_first_node_in_group("player") == walker)
	var portal: Node = make_portal.call()
	for i in 3:
		await get_tree().physics_frame
	check("landing on it, nothing happens yet", not portal.get("_has_vanished") and portal.is_physics_processing())
	walker.global_position += Vector2(leave - 6.0, 0)
	for i in 2:
		await get_tree().physics_frame
	check("  a step or two off the spot, it is still open", not portal.get("_has_vanished"))
	walker.global_position += Vector2(12.0, 0)
	for i in 2:
		await get_tree().physics_frame
	check("walk LEAVE_DISTANCE from where you landed and it closes - the trigger never saw you",
		portal.get("_has_vanished") == true and not portal.is_physics_processing())
	check("  fading quickly", float(consts.get("FADE_SECONDS", 9.0)) <= 0.6, consts.get("FADE_SECONDS"))

	walker.global_position = at + Vector2(400, 0)
	var other: Node = make_portal.call()
	for i in 3:
		await get_tree().physics_frame
	check("a player who arrived somewhere else does not close it from afar",
		not other.get("_has_vanished") and not other.is_physics_processing())
	var exit_door = (load("res://src/world/leavetown.gd") as GDScript).new()
	holder.add_child(exit_door)
	check("and a way out (not an arrival portal) watches nobody", not exit_door.is_physics_processing())
	holder.queue_free()
	await get_tree().process_frame


func _test_the_road_through_the_game() -> void:
	section("THE ROAD - town, Big Field, Field, the gauntlet, the Crowned, and home")

	for hop in ROAD:
		var from_id: String = hop[0]
		var to_id: String = hop[2]
		var from_scene: Node = (load(AreaRegistry.AREAS[from_id]) as PackedScene).instantiate()
		var to_scene: Node = (load(AreaRegistry.AREAS[to_id]) as PackedScene).instantiate()
		var doors: Array = []
		_collect_by_script(from_scene, hop[1], doors)
		# The way on: a door that leads somewhere (an arrival-only portal does not).
		var onward: Array = doors.filter(func(d: Node) -> bool:
			var dest: String = str(d.get("destination_scene_path")) if "destination_scene_path" in d else ""
			if dest == "" and d.get("destination_scene") is PackedScene:
				dest = (d.get("destination_scene") as PackedScene).resource_path
			return dest == str(AreaRegistry.AREAS[to_id]))
		var ids: Array = []
		_collect_portal_ids(to_scene, ids)
		var lands: String = str(onward[0].get("target_spawn_id")) if onward.size() == 1 else "-"
		check("%s leads on to %s" % [AreaRegistry.display_name(from_id), AreaRegistry.display_name(to_id)],
			onward.size() == 1, "%d doors there, none to %s" % [doors.size(), to_id] if onward.is_empty() else str(onward.size()))
		check("  and lands where %s has an arrival for it" % AreaRegistry.display_name(to_id),
			onward.size() == 1 and (lands == "" or ids.has(lands)), "wants '%s', has %s" % [lands, ids])
		from_scene.free()
		to_scene.free()

	# EVERY DOOR IS CONNECTED. A door's script only runs when its Area2D's
	# body_entered reaches it, and the scene file is what connects the two.
	# bigfield.tscn was generated without those lines, so its ladder and its
	# arrival portal never fired - unnoticed while nobody but /goto went there,
	# and found the first time a player walked onto the ladder (0.15.0).
	var unwired: Array = []
	for area_id in AreaRegistry.area_ids():
		var area: Node = (load(AreaRegistry.AREAS[area_id]) as PackedScene).instantiate()
		for script_path in DOOR_SCRIPTS:
			var found: Array = []
			_collect_by_script(area, script_path, found)
			for door in found:
				for sig in [["body_entered", "_on_body_entered"], ["body_exited", "_on_body_exited"]]:
					if door.has_method(sig[1]) and not door.is_connected(sig[0], Callable(door, sig[1])):
						unwired.append("%s %s %s" % [area_id, door.name, sig[0]])
		area.free()
	check("every door in every area hears a player step in and out", unwired.is_empty(), unwired)

	# Nothing else in town leads into the fields: one way out, to the Big Field.
	var town: Node = (load(AreaRegistry.AREAS["elusion"]) as PackedScene).instantiate()
	var exits: Array = []
	_collect_by_script(town, "res://src/world/leavetown.gd", exits)
	check("the town has one way out, and it is to the Big Field",
		exits.size() == 1 and (exits[0].get("destination_scene") as PackedScene).resource_path == str(AreaRegistry.AREAS["bigfield"])
		and str(exits[0].get("target_spawn_id")) == "field_entrance", exits.size())
	town.free()


# =============================================================================
# THE OWNER'S STRESS TEST (0.65.0)
# =============================================================================
# The owner, 21 Oct: "first we need to stress test the game with 2x the
# enemies in big field" - a switch on the owner panel's Testing tab, his game
# only (stresscrowd.gd). Copies fight like the rest and are worth nothing:
# no kill report, never shared, never in the respawner's census.
func _test_the_crowd_takes_seats() -> void:
	# The owner, aiming the stress test at 16x: "i need absolute masterclass
	# help". At 16x, 390 monsters were after one warrior, every one chasing and
	# firing, and the game ran at 5 frames a second. Now FIGHT_SEATS fight a
	# player at once and the rest wait their turn (baseenemy.gd, SEATS).
	section("SEATS - at most 64 fight a player at once, the rest wait their turn (0.76.0)")
	const Crowd := preload("res://src/world/stresscrowd.gd")
	check("the stress test goes to 12x and 16x", Crowd.MULTIPLIERS.has(12) and Crowd.MULTIPLIERS.has(16), Crowd.MULTIPLIERS)
	check("64 seats a player", BaseEnemy.FIGHT_SEATS == 64, BaseEnemy.FIGHT_SEATS)
	BaseEnemy._seats.clear()
	var world := Node2D.new()
	add_child(world)
	var target := Node2D.new()
	target.add_to_group("player")
	world.add_child(target)
	var crowd: Array = []
	for i in 70:
		var monster: BaseEnemy = (load("res://scene/enemy/icefiresprite.tscn") as PackedScene).instantiate()
		monster.position = Vector2(-9000 - i * 40, -9000)
		world.add_child(monster)
		crowd.append(monster)
	await get_tree().process_frame
	for monster in crowd:
		monster.set_physics_process(false)        # its ticks are driven by hand below
		monster.player = target
		monster.engaged = true
	var answers: Array = []
	for i in crowd.size():
		answers.append(crowd[i].take_seat(100.0 + i))
	check("the first 64 after a player take a seat, and the 65th waits",
		answers.slice(0, 64).all(func(a): return a) and answers.slice(64).all(func(a): return not a),
		[answers.count(true), answers.count(false)])
	var seats: Dictionary = BaseEnemy._seats.get(target.get_instance_id(), {})
	check("  64 seats taken, no more", seats.size() == 64, seats.size())
	var near: BaseEnemy = crowd[69]
	near.set("_seat_due_tick", 0)
	var furthest: BaseEnemy = crowd[63]
	check("one much nearer than the furthest seated takes that seat - the ones in front fight",
		near.take_seat(10.0) and not furthest.take_seat(163.0) and int(furthest.get("_seat_target")) == 0
		and seats.size() == 64, [seats.size(), int(furthest.get("_seat_target"))])
	var hit: BaseEnemy = crowd[68]
	hit.take_damage(1)
	check("a waiter that is hit fights back at its next tick, however far",
		hit.take_seat(400.0) and seats.size() == 64)
	var boss: BaseEnemy = crowd[67]
	boss.add_to_group("unpushable")
	check("a boss never waits", boss.take_seat(500.0) and seats.size() == 64)
	boss.remove_from_group("unpushable")
	crowd[0].engaged = false
	var after_leaving: int = seats.size()
	var freed_one: BaseEnemy = crowd[66]
	freed_one.set("_seat_due_tick", 0)
	var took_it: bool = freed_one.take_seat(170.0)
	check("giving up the chase gives the seat up, and the next to ask takes it",
		after_leaving == 63 and took_it and seats.size() == 64, [after_leaving, took_it, seats.size()])
	# A waiter is still, facing its target, off its place on the ring.
	var stander: BaseEnemy = crowd[65]
	stander.velocity = Vector2(30, 0)
	stander.set("_claimed_slot", -1)
	stander._wait_turn()
	check("waiting, it stands still - and says it is waiting", stander.velocity == Vector2.ZERO and stander.waiting_turn)
	# ONE TICK IN WAIT_STRIDE: it thinks once in four, a hit answered at once.
	var thought: int = 0
	for i in BaseEnemy.WAIT_STRIDE:
		await get_tree().physics_frame
		if not stander.waits_this_tick():
			thought += 1
	stander.set("_seat_now", true)
	var answers_hit: bool = not stander.waits_this_tick()
	stander.set("_seat_now", false)
	check("  it thinks one tick in %d, and a hit is answered the next tick" % BaseEnemy.WAIT_STRIDE,
		thought == 1 and answers_hit, thought)
	check("  the readout counts them: fighting and waiting",
		PerfOverlay.fight_counts().x >= 64 and PerfOverlay.fight_counts().y >= 1, PerfOverlay.fight_counts())
	var said: String = PerfOverlay._fight_text()
	check("  and says so, on its own row of the readout (F3): who is after you, and the seats",
		said.contains("waiting their turn") and said.contains("(%d seats a player)" % BaseEnemy.FIGHT_SEATS)
		and _code_src("res://src/systems/perfoverlay.gd").contains('_row("after you", _fight_text())'), said)
	# A SEAT NOBODY SITS IN IS FREE: a holder asleep, stopped or gone stops
	# asking, and after SEAT_STALE_TICKS its seat goes to the next to ask.
	for i in BaseEnemy.SEAT_STALE_TICKS + 2:
		await get_tree().physics_frame
	var late: BaseEnemy = crowd[64]
	late.set("_seat_due_tick", 0)
	check("a seat nobody has sat in for %d ticks goes to whoever asks" % BaseEnemy.SEAT_STALE_TICKS,
		late.take_seat(300.0) and seats.size() == 1, seats.size())
	for monster in crowd:
		monster.queue_free()
	await get_tree().process_frame
	check("  and a monster gone takes its seat with it", not BaseEnemy._seats.has(target.get_instance_id()),
		BaseEnemy._seats.keys())
	world.queue_free()
	var mage_code := _func_body(_code_src("res://src/enemies/bushmage.gd"), "func _physics_process(")
	check("the bush mage, which has a brain of its own, takes a seat too, and waits on the stride",
		mage_code.contains("take_seat(dist)") and mage_code.contains("waits_this_tick()"))
	var ring_code := _func_body(_code_src("res://src/enemies/threatring.gd"), "func _process(")
	check("  and a waiter's ring looks at the idle pace", ring_code.contains("not monster.waiting_turn"))


func _test_the_owner_stress_crowd() -> void:
	section("THE OWNER'S STRESS TEST - more of the Big Field's monsters, his game only, worth nothing (0.65.0)")
	const Crowd := preload("res://src/world/stresscrowd.gd")
	var kept_times: int = Crowd.multiplier
	Crowd.multiplier = 1
	var world := Node2D.new()
	add_child(world)
	var area: Node2D = (load(BIG_FIELD) as PackedScene).instantiate() as Node2D
	world.add_child(area)
	var crowd: Node = Crowd.add_to(area)
	crowd.set("refill_seconds_override", 0.3)
	for i in 4:
		await get_tree().process_frame
	var authored: int = BIG_FIELD_MONSTERS
	check("off, it adds nothing - and it knows the Big Field is its area", int(crowd.call("copy_count")) == 0
		and bool(crowd.call("applies")))

	Crowd.set_multiplier(2, get_tree())
	# Built by the clock: after the census, a frame builds only what fits in
	# BUILD_MS - not the lot at once.
	var first_frames: Array = []
	for i in 12:
		var t0: int = Time.get_ticks_usec()
		await get_tree().process_frame
		first_frames.append([int(crowd.call("copy_count")), Time.get_ticks_usec() - t0])
	await _crowd_settles(crowd, authored)
	var copies: Array = []
	for node in get_tree().get_nodes_in_group("enemies"):
		if Crowd.is_copy(node) and area.is_ancestor_of(node):
			copies.append(node)
	check("2x: a copy beside each of the Big Field's %d monsters (%d built)" % [authored, copies.size()],
		int(crowd.call("source_count")) == authored and copies.size() >= int(authored * 0.99) and copies.size() <= authored,
		[crowd.call("source_count"), copies.size()])
	var map: RID = area.get_world_2d().navigation_map
	var arrival: Vector2 = (area.find_child("arrivalmarker", true, false) as Node2D).global_position
	var unpaid: bool = true
	var paying_sources: int = 0
	var shared_or_census: Array = []
	var misplaced: Array = []
	var unlike: Array = []
	for copy in copies:
		var source_name: String = str(copy.name).trim_prefix("stress_").rsplit("_", true, 1)[0]
		var source: Node2D = copy.get_parent().get_node_or_null(source_name) as Node2D
		# A big slime pays nothing even as itself (it splits), so the
		# check is that no copy pays - and that most of what they copy does.
		if copy.call("get_enemy_id") != "" or source == null:
			unpaid = false
		elif source.call("get_enemy_id") != "":
			paying_sources += 1
		if copy.has_meta(&"net_origin") or int(copy.get("net_id")) >= 0:
			shared_or_census.append(copy.name)
		var spot: Vector2 = (copy as Node2D).global_position
		if source == null or spot.distance_to(source.global_position) > Crowd.SPREAD_MAX + 1.0 \
				or NavigationServer2D.map_get_closest_point(map, spot).distance_to(spot) > 1.5 \
				or spot.distance_to(arrival) < Crowd.ARRIVAL_CLEAR:
			misplaced.append(copy.name)
		if source == null or source.scene_file_path != copy.scene_file_path \
				or not is_equal_approx(float(source.get("leash_range")), float(copy.get("leash_range"))):
			unlike.append(copy.name)
	var grew_over_frames: bool = false
	var counts: Array = first_frames.map(func(f): return int(f[0]))
	for i in range(1, counts.size()):
		if counts[i] > counts[i - 1] and counts[i] < copies.size():
			grew_over_frames = true
	check("  built a few milliseconds a frame (%.0f ms), not all at once: %s" % [Crowd.BUILD_MS, str(counts)],
		grew_over_frames and Crowd.BUILD_MS > 0.0 and Crowd.BUILD_MS <= 5.0
		and not _code_src("res://src/world/stresscrowd.gd").contains("const BATCH"), first_frames)
	check("  each worth nothing: no kill to report, where %d of the monsters they copy have one" % paying_sources,
		unpaid and paying_sources * 2 > copies.size(), paying_sources)
	check("  each the same monster - its scene and its leash", unlike.is_empty(), unlike.slice(0, 4))
	check("  each on the floor, a few steps from it, and none near where players arrive", misplaced.is_empty(), misplaced.slice(0, 4))
	# 0.94.0: and in sight of it - never past a wall the floor joins round a
	# corner, nor over the rift.
	var unseen: Array = []
	var space: PhysicsDirectSpaceState2D = area.get_world_2d().direct_space_state
	for copy in copies:
		var source_name: String = str(copy.name).trim_prefix("stress_").rsplit("_", true, 1)[0]
		var source: Node2D = copy.get_parent().get_node_or_null(source_name) as Node2D
		if source == null:
			continue
		var ray := PhysicsRayQueryParameters2D.create(source.global_position, (copy as Node2D).global_position, Crowd.WALL_MASK)
		if not space.intersect_ray(ray).is_empty():
			unseen.append(copy.name)
	check("  each in sight of the monster it copies: no wall between them", unseen.is_empty(), unseen.slice(0, 4))
	var by_arrival: Variant = crowd.call("_spot_near", {"home": arrival + Vector2(40, 0), "map": map, "arrivals": [arrival]})
	var in_field: Variant = crowd.call("_spot_near", {"home": (copies[0] as Node2D).global_position, "map": map, "arrivals": [arrival]})
	check("  a monster standing by the arrival gets no copy at all - a copy elsewhere gets its spot",
		by_arrival == null and in_field != null, [by_arrival, in_field])
	check("  never numbered for other games or the server's books, and in no respawner's census",
		shared_or_census.is_empty()
		and _func_body(_code_src("res://src/world/monstersync.gd"), "func _all_enemies(").contains("has_meta(&\"stress_copy\")")
		and _func_body(_code_src("res://src/world/enemyrespawner.gd"), "func _ready(").contains("has_meta(&\"stress_copy\")"),
		shared_or_census.slice(0, 4))
	check("  and a big slime's copy splits into copies, worth nothing either",
		_func_body(_code_src("res://src/enemies/poisonslime.gd"), "func _spawn_slime(").contains("slime.set_meta(&\"stress_copy\", true)"))
	check("  the kill report says nothing for a monster with no id", _func_body(_code_src("res://src/systems/combat.gd"), "func report_kill(")
		.contains("if enemy_id == \"\":"))

	# Not a slime: a big one splits, and its halves are copies of their own.
	var victim: Node = copies[0]
	for copy in copies:
		if not str(copy.scene_file_path).contains("slime"):
			victim = copy
			break
	victim.call("_die")
	await get_tree().process_frame
	await get_tree().process_frame
	var after_kill: int = int(crowd.call("copy_count"))
	await get_tree().create_timer(0.6).timeout
	check("a copy killed comes back, after the wait its monster would take",
		after_kill == copies.size() - 1 and int(crowd.call("copy_count")) == copies.size(),
		[copies.size(), after_kill, crowd.call("copy_count")])

	# A player at the arrival: the copies built far from it start asleep, the
	# way the sleeper would put them; any built near it start awake.
	var stand_in := Node2D.new()
	stand_in.add_to_group(&"player")
	area.add_child(stand_in)
	stand_in.global_position = arrival
	# Every copy there already - the 2x ones and the one rebuilt after the
	# kill, both built with nobody in the world - is not this check's.
	var before_three: Dictionary = {}
	for node in get_tree().get_nodes_in_group("enemies"):
		if Crowd.is_copy(node):
			before_three[node] = true
	Crowd.set_multiplier(3, get_tree())
	await _crowd_settles(crowd, authored * 2)
	var born_asleep: int = 0
	var far_awake: Array = []
	for node in get_tree().get_nodes_in_group("enemies"):
		if not Crowd.is_copy(node) or not area.is_ancestor_of(node) or before_three.has(node):
			continue
		var far_off: bool = (node as Node2D).global_position.distance_to(arrival) > 1100.0
		if node.has_meta(&"asleep") and node.process_mode == Node.PROCESS_MODE_DISABLED:
			born_asleep += 1
		elif far_off:
			far_awake.append(node.name)
	check("  copies built far from every player start asleep (%d), none far off awake" % born_asleep,
		born_asleep * 2 > authored and far_awake.is_empty(), far_awake.slice(0, 4))
	stand_in.free()
	var at_three: int = int(crowd.call("copy_count"))
	Crowd.set_multiplier(2, get_tree())
	await _crowd_settles_down(crowd, authored)
	var back_to_two: int = int(crowd.call("copy_count"))
	Crowd.set_multiplier(1, get_tree())
	await _crowd_settles_down(crowd, 0)
	check("3x is two of each, back to 2x takes the extra away, and Off takes them all",
		at_three >= int(authored * 2 * 0.99) and back_to_two <= authored and back_to_two >= int(authored * 0.99)
		and int(crowd.call("copy_count")) == 0, [at_three, back_to_two, crowd.call("copy_count")])
	var elsewhere := Node2D.new()
	world.add_child(elsewhere)
	var other: Node = Crowd.add_to(elsewhere)
	check("  only the Big Field and the Field: anywhere else it does nothing", not bool(other.call("applies"))
		and Crowd.AREAS == ["res://scene/bigfield.tscn", "res://scene/field.tscn"], Crowd.AREAS)
	check("  and the switch is a setting of this run alone - a static, never saved",
		not _code_src("res://src/world/stresscrowd.gd").contains("Settings.set_value")
		and _code_src("res://src/world/stresscrowd.gd").contains("static var multiplier: int = 1"))

	# The owner panel's switch.
	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var pick: OptionButton = gm.get_node_or_null("%stresspick") as OptionButton
	var testing_tab: Node = gm.get_node_or_null("frame/margin/rows/tabsscroll/ownertabs/testing")
	check("the owner panel's Testing tab has it: Off, 2x, 3x, 4x, 6x, 8x, 12x, 16x - \"we can add even more\"",
		pick != null and testing_tab != null and testing_tab.is_ancestor_of(pick) and pick.item_count == 8
		and pick.get_item_text(0) == "Off" and pick.get_item_text(1) == "2x" and pick.get_item_text(5) == "8x"
		and pick.get_item_text(7) == "16x" and pick.selected == 0)
	if pick != null:
		pick.select(1)
		pick.item_selected.emit(1)
		check("  picking 2x sets it, and says it is his game only and worth nothing",
			Crowd.multiplier == 2 and gm.results.get_parsed_text().contains("your game only")
			and gm.results.get_parsed_text().contains("give nothing"), gm.results.get_parsed_text())
		pick.select(0)
		pick.item_selected.emit(0)
		check("  and Off turns it off", Crowd.multiplier == 1)
	gm.queue_free()
	world.queue_free()
	Crowd.multiplier = kept_times
	await get_tree().process_frame
	await get_tree().process_frame


func _test_the_big_field() -> void:
	section("THE BIG FIELD - the crossroads and its wings, a tier each, harder the further you go (0.94.0)")

	check("it is an area: /goto and the walk test can reach it",
		AreaRegistry.has_area("bigfield") and str(AreaRegistry.AREAS.get("bigfield", "")) == BIG_FIELD
		and AreaRegistry.display_name("bigfield") == "Big Field")
	var packed: PackedScene = load(BIG_FIELD) as PackedScene
	check("it loads", packed != null)
	if packed == null:
		return
	var area: Node = packed.instantiate()
	var ground: TileMapLayer = area.get_node_or_null("ground") as TileMapLayer
	var arrival: Node2D = area.get_node_or_null("ysortworld/interactables/fieldteleport/arrivalmarker") as Node2D
	var enemies: Array = area.get_node("ysortworld/enemies").get_children() if area.has_node("ysortworld/enemies") else []
	check("the floor is painted from the Field's own crypt atlas",
		ground != null and ground.get_used_cells().size() > 10000
		and (ground.tile_set.get_source(1) as TileSetAtlasSource).texture.resource_path == "res://art/tiles/underground.png",
		ground.get_used_cells().size() if ground else 0)
	check("players arrive where the town's portal sends them (field_entrance)",
		arrival != null and str(arrival.get("portal_id")) == "field_entrance")
	var ladder: Node = area.get_node_or_null("ysortworld/interactables/ladderdown")
	check("the ladder at the descent's heart goes down to the Field, landing at its arrival (0.15.0)",
		ladder != null and str(ladder.get("destination_scene_path")) == "res://scene/field.tscn"
		and str(ladder.get("target_spawn_id")) == "field_entrance")
	check("a respawner brings the monsters back", area.get_node_or_null("enemyrespawner") != null)
	var skeletons: Dictionary = {}
	for enemy in enemies:
		var kind: String = str(enemy.scene_file_path).get_file().get_basename()
		if kind.begins_with("skeleton"):
			skeletons[kind] = int(skeletons.get(kind, 0)) + 1
	check("%d enemies are placed, %d Skeleton Soldiers and %d Elites among them"
		% [enemies.size(), BIG_FIELD_SOLDIERS, BIG_FIELD_ELITES],
		enemies.size() == BIG_FIELD_MONSTERS and int(skeletons.get("skeletonsoldier", 0)) == BIG_FIELD_SOLDIERS
		and int(skeletons.get("skeletonelite", 0)) == BIG_FIELD_ELITES, [enemies.size(), skeletons])

	# Positions are read relative to the area root, as the scene file holds them.
	var arrive_at: Vector2 = Vector2.ZERO
	if arrival != null:
		arrive_at = (arrival.get_parent() as Node2D).position + (arrival.get_parent() as Node2D).transform.basis_xform(arrival.position)
	# Which wing a spot is in: the build file's rooms and corridors, by cell.
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string(BIG_FIELD_BUILD))
	var rooms: Array = (plan as Dictionary).get("rooms", []) if plan is Dictionary else []
	check("the build file it was made from is beside its tool", not rooms.is_empty(), BIG_FIELD_BUILD)
	var wing_at := func(at: Vector2) -> String:
		var c := Vector2i(floori(at.x / 16.0), floori(at.y / 16.0))
		for r in rooms:
			if c.x >= int(r["x"]) and c.x < int(r["x"]) + int(r["w"]) and c.y >= int(r["y"]) and c.y < int(r["y"]) + int(r["h"]):
				return str(r["wing"])
		return ""
	var too_close: Array = []
	var in_walls: Array = []
	var chase: Array = []
	var astray: Array = []
	var by_tier: Dictionary = {}
	for enemy in enemies:
		var at: Vector2 = (enemy as Node2D).position
		if at.distance_to(arrive_at) < 400.0:
			too_close.append(enemy.name)
		var cell: Vector2i = ground.local_to_map(at)
		var atlas: Vector2i = ground.get_cell_atlas_coords(cell)
		if not (atlas.x >= 1 and atlas.x <= 4 and atlas.y >= 1 and atlas.y <= 3):
			in_walls.append("%s on %s" % [enemy.name, atlas])
		if not is_equal_approx(float(enemy.get("leash_range")), 250.0):
			chase.append(enemy.name)
		var land: String = str(enemy.name).get_slice("_", 0)
		var wing: String = str(BIG_FIELD_LANDS.get(land, "?"))
		if wing_at.call(at) != wing:
			astray.append("%s in %s" % [enemy.name, wing_at.call(at)])
		if BIG_FIELD_TIERS.has(wing):
			var tier: int = int(BIG_FIELD_TIERS[wing])
			if not by_tier.has(tier):
				by_tier[tier] = []
			by_tier[tier].append(at.distance_to(arrive_at))
	check("a safe landing: nothing within 400 px of where players arrive", too_close.is_empty(), too_close)
	check("every enemy stands on open floor, none in a wall tile", in_walls.is_empty(), in_walls.slice(0, 4))
	check("every enemy chases from 250 px, so one pack does not pull the next", chase.is_empty(), chase.slice(0, 4))
	check("every monster stands in its land's wing: light and wind in the courts, water and ice in the chasm, "
		+ "earth in the caverns, fire in the fortress, dark in the descent, the skeletons' own in the crypt",
		astray.is_empty(), astray.slice(0, 4))
	var means: Array = []
	for tier in [1, 2, 3, 4, 5]:
		var ds: Array = by_tier.get(tier, [])
		var total: float = 0.0
		for dd in ds:
			total += float(dd)
		means.append(total / maxf(ds.size(), 1.0))
	check("every tier has its wing, and harder the further you go: the courts' the nearest, the descent's the furthest",
		[1, 2, 3, 4, 5].all(func(t): return by_tier.has(t)) and means[0] == means.min() and means[4] == means.max(),
		means.map(func(m): return int(m)))
	var kinds: Array = []
	for enemy in enemies:
		if not kinds.has(enemy.scene_file_path):
			kinds.append(enemy.scene_file_path)
	area.free()

	# The 250 above is what the scene file says. What counts is the number an
	# enemy chases from once it is in the world: bushmage.gd used to set its
	# own 1,500 in _ready(), after the scene's value, and the file check above
	# passed while every mage in the Big Field crossed the map.
	var holder := Node2D.new()
	holder.position = Vector2(-20000, -20000)
	add_child(holder)
	var placed: Array = []
	for i in kinds.size():
		var one: Node2D = (load(kinds[i]) as PackedScene).instantiate() as Node2D
		one.set("leash_range", 250.0)
		one.position = Vector2(i * 300, 0)
		holder.add_child(one)
		placed.append(one)
	var mage: Node2D = (load("res://scene/enemy/bushmage.tscn") as PackedScene).instantiate() as Node2D
	mage.position = Vector2(0, 600)
	holder.add_child(mage)
	await get_tree().process_frame
	await get_tree().process_frame
	var moved: Array = []
	for one in placed:
		if not is_equal_approx(float(one.get("leash_range")), 250.0):
			moved.append("%s %s" % [str(one.scene_file_path).get_file(), one.get("leash_range")])
	check("  and still 250 once each kind is in the world (%d kinds)" % kinds.size(), moved.is_empty(), moved)
	check("  while a mage nobody set still commits to the chase, as in the Field",
		is_equal_approx(float(mage.get("leash_range")), 1500.0), mage.get("leash_range"))
	holder.free()
	print("  %d enemies, the tiers' mean distance from the arrival %s" % [enemies.size(), means.map(func(m): return int(m))])


# =============================================================================
# FAR ENEMIES SLEEP
# =============================================================================
# Every enemy used to think on every physics tick wherever the player was. The
# Big Field holds 128, so enemysleeper.gd (added to every area by AreaRegistry)
# disables the ones more than SLEEP_DISTANCE away and wakes them inside
# WAKE_DISTANCE. Measured in the Big Field: 87 of 128 asleep where you arrive,
# physics 2.1 ms a frame against 3.3 with the sleeper off.
func _test_far_enemies_sleep() -> void:
	section("FAR ENEMIES SLEEP - beyond 1100 px an enemy stops thinking, inside 900 it wakes")

	var Sleeper := preload("res://src/world/enemysleeper.gd")
	var holder := Node2D.new()
	add_child(holder)
	var player := Node2D.new()
	player.add_to_group("player")
	holder.add_child(player)
	var near := Node2D.new(); near.position = Vector2(500, 0)
	var far := Node2D.new(); far.position = Vector2(1500, 0)
	var boss := Node2D.new(); boss.position = Vector2(1500, 300)
	for e in [near, far, boss]:
		e.add_to_group("enemies")
		holder.add_child(e)
	boss.add_to_group("unpushable")
	var sleeper: Node = Sleeper.add_to(holder)

	var asleep: int = sleeper.check_now()
	check("an enemy 1,500 px away sleeps", far.process_mode == Node.PROCESS_MODE_DISABLED and asleep == 1, asleep)
	check("  one 500 px away stays awake", near.process_mode == Node.PROCESS_MODE_INHERIT)
	check("  and a boss never sleeps", boss.process_mode == Node.PROCESS_MODE_INHERIT)

	# The welcome story freezes enemies with set_physics_process(false); the
	# sleeper must not undo that, nor be undone by it.
	far.set_physics_process(false)
	player.position = Vector2(450, 0)         # far 1,050 away: between the two
	sleeper.check_now()
	check("between 900 and 1,100 a sleeper stays asleep",
		far.process_mode == Node.PROCESS_MODE_DISABLED)
	player.position = Vector2(-500, 0)        # near 1,000 away, far 2,000
	sleeper.check_now()
	check("  and an awake one stays awake (no flicker at the edge)",
		near.process_mode == Node.PROCESS_MODE_INHERIT and far.process_mode == Node.PROCESS_MODE_DISABLED)
	player.position = Vector2(1300, 0)        # 200 from far
	sleeper.check_now()
	check("walking up wakes it", far.process_mode == Node.PROCESS_MODE_INHERIT and not far.has_meta(&"asleep"))
	check("  and waking leaves the story's own freeze alone", not far.is_physics_processing())
	far.set_physics_process(true)
	check("  the near one, now 800 px away, is still awake", near.process_mode == Node.PROCESS_MODE_INHERIT)

	player.position = Vector2(-2000, 0)
	sleeper.check_now()
	sleeper.enabled = false
	check("turning the sleeper off wakes everyone at once",
		near.process_mode == Node.PROCESS_MODE_INHERIT and far.process_mode == Node.PROCESS_MODE_INHERIT)
	check("  and while off it sleeps nobody", sleeper.check_now() == 0
		and far.process_mode == Node.PROCESS_MODE_INHERIT)

	var registry: String = _func_body(_code_src("res://src/systems/arearegistry.gd"), "func _on_scene_changed(")
	check("every area gets one when it opens (AreaRegistry._on_scene_changed)",
		registry.contains("EnemySleeper.add_to(scene)"))
	holder.free()

	# A respawn is a fresh copy of the enemy's scene; the chase range the Big
	# Field gives its monsters has to survive it.
	var Respawner := preload("res://src/world/enemyrespawner.gd")
	var arena := Node2D.new()
	add_child(arena)
	var light: Node2D = (load("res://scene/enemy/lightsprite.tscn") as PackedScene).instantiate()
	light.set("leash_range", 250.0)
	light.position = Vector2(-9000, -9000)
	arena.add_child(light)
	var respawner: Node = Respawner.new()
	respawner.spawn_scatter = 0.0
	arena.add_child(respawner)
	await get_tree().process_frame
	await get_tree().process_frame
	var entry: Dictionary = {}
	for e in respawner._census:
		if (e["position"] as Vector2).distance_to(Vector2(-9000, -9000)) < 1.0:
			entry = e
	check("the respawner's census keeps the chase range a scene set",
		float(entry.get("kept", {}).get("leash_range", 0.0)) == 250.0, entry.get("kept"))
	# DEAD FIRST: since shared monsters a respawn never lands on a spot whose
	# monster is still standing (a game taking an area over can find it alive).
	var light_id: int = light.get_instance_id()
	light.free()
	var before: int = arena.get_child_count()
	await respawner._respawn_after(entry, 0.0)
	var back: Node = arena.get_child(arena.get_child_count() - 1) if arena.get_child_count() > before else null
	check("  and the replacement chases from 250 too, not its scene's own 500",
		back != null and back.get_instance_id() != light_id and float(back.get("leash_range")) == 250.0,
		back.get("leash_range") if back else "nothing came back")
	check("  and its home is where it came back, not the world origin",
		back != null and (back.get("spawn_position") as Vector2).distance_to((back as Node2D).global_position) < 1.0,
		back.get("spawn_position") if back else "nothing came back")
	arena.free()
	print("  sleep beyond %d px, wake inside %d px, every %.2f s"
		% [int(Sleeper.SLEEP_DISTANCE), int(Sleeper.WAKE_DISTANCE), Sleeper.CHECK_SECONDS])



# =============================================================================
# A BIG FIGHT IS CHEAP (0.66.0)
# =============================================================================
# The owner's 4x stress test, and then: "incredible lets refine so it runs
# smooth as butter". 1,470 monsters in the Big Field, measured on the bench at
# 4x round one player in the thick of it:
#   - every awake monster's threat ring worked itself out again every frame:
#     5.7 of the 9 ms the scripts took. Now 20 times a second, each ring at its
#     own moment, and at once when its monster turns on somebody;
#   - every ring, aim ring and recoloured monster had a material of its own,
#     so nothing could be drawn together: 863 draw calls. Now one material for
#     every ring, one per kind and element for the monsters, and the rings on
#     the floor where they batch: 605;
#   - every monster parked on its slot slid every frame: physics about 12 ms,
#     against 9.6 with a parked one sliding five times a second;
#   - a sleeper, never on anybody's screen, was still sorted by the renderer;
#   - 700 awake monsters standing at home with nobody in reach still thought
#     every tick: 2.7 ms. Now they doze between the sleeper's passes.
func _test_a_big_fight_is_cheap() -> void:
	section("A BIG FIGHT IS CHEAP - rings 20 a second, shared materials, parked monsters barely slide (0.66.0)")

	# ---- one material for every ring ----------------------------------------------------------
	var range_a := RangeRing.new()
	var range_b := RangeRing.new()
	var aim_ring := AimRing.new()
	var shared: CanvasItemMaterial = RangeRing.unshaded()
	check("every range ring and aim ring, and its ball, wears the one unshaded material",
		range_a.material == shared and range_b.material == shared and aim_ring.material == shared
		and (aim_ring.get("_ball") as CanvasItem).material == shared
		and shared.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED,
		[range_a.material, aim_ring.material])
	range_a.free()
	range_b.free()
	aim_ring.free()
	check("  and an aim ring is drawn as line segments, the way a range ring is (so they batch)",
		_func_body(_code_src("res://src/characters/aimring.gd"), "func _draw(").contains("draw_multiline(")
		and not _func_body(_code_src("res://src/characters/aimring.gd"), "func _draw(").contains("draw_polyline(")
		and _func_body(_code_src("res://src/shared/rangering.gd"), "func _draw(").contains("draw_multiline("))

	# ---- the threat ring on the floor, its ball where it was ----------------------------------
	var sniper: BaseEnemy = (load("res://scene/enemy/darkbushsniper.tscn") as PackedScene).instantiate()
	var ring: ThreatRing = ThreatRing.on(sniper)
	var ball: CanvasItem = ring.get("_ball") as CanvasItem
	check("a monster's ring and detection circle lie on the floor (z %d) and share that material" % ThreatRing.FLOOR_Z,
		ring.z_index == ThreatRing.FLOOR_Z and ring.z_as_relative and ring.sense.z_index == ThreatRing.FLOOR_Z
		and ring.material == shared and ring.sense.material == shared, [ring.z_index, ring.sense.z_index])
	check("  its ball still over the world, at z 1 as it always was",
		ball.z_as_relative and ring.z_index + ball.z_index == 1, ball.z_index)
	var lowest_world: int = 0
	var highest_floor: int = -100
	for area in AreaRegistry.AREAS:
		var src: String = FileAccess.get_file_as_string(str(AreaRegistry.AREAS[area]))
		for layer in ["ground", "water"]:
			var z: Variant = _root_layer_z(src, layer)
			if z != null:
				highest_floor = maxi(highest_floor, int(z))
	check("  which is over the ground in every area (its highest floor layer is z %d)" % highest_floor,
		highest_floor < ThreatRing.FLOOR_Z and ThreatRing.FLOOR_Z < lowest_world)
	var boss: BaseEnemy = (load("res://scene/enemy/bossenemy.tscn") as PackedScene).instantiate()
	boss.add_to_group(&"unpushable")      # what BossEnemy._ready() does before the ring goes on
	var boss_ring: ThreatRing = ThreatRing.on(boss)
	check("  but a boss's stays in the world at z 0 - one ring, and the arena's dais would cover it",
		boss_ring.z_index == 0 and boss_ring.sense.z_index == 0 and (boss_ring.get("_ball") as CanvasItem).z_index == 1,
		[boss_ring.z_index, boss_ring.sense.z_index])
	boss.free()

	# ---- 20 looks a second, each at its own moment, at once on turning --------------------------
	var starts: Array[float] = []
	for k in 6:
		starts.append(float(ThreatRing.on(sniper).get("_refresh_in")))
	var spread: bool = starts.min() >= 0.0 and starts.max() <= ThreatRing.REFRESH_SECONDS \
		and not is_equal_approx(float(starts.min()), float(starts.max()))
	check("each ring first looks at its own moment within %.2f s, so a crowd's do not land on one frame"
		% ThreatRing.REFRESH_SECONDS, spread, starts)
	sniper.set_physics_process(true)
	sniper.position = Vector2.ZERO
	sniper.hp = sniper.max_hp
	var dummy := ZoneDummy.new()
	add_child(dummy)
	sniper.player = dummy
	dummy.position = Vector2(-120, 0)
	# Its own ring, as BaseEnemy._ready() makes it (out of the tree, _ready never ran).
	sniper.set("_threat_ring", ring)
	ring.set("_refresh_in", 1.0)
	sniper.keep_after(sniper.global_position.distance_to(dummy.global_position))
	check("(set up) the monster is after the stand-in", sniper.engaged)
	check("turning on somebody makes the ring look at once", is_zero_approx(float(ring.get("_refresh_in"))),
		ring.get("_refresh_in"))
	ring._process(0.001)
	var first_aim: Vector2 = ring.aim
	check("  it shows that frame, pointing at them, and then waits %.2f s" % ThreatRing.REFRESH_SECONDS,
		ring.visible and first_aim.x < -0.9
		and absf(float(ring.get("_refresh_in")) - ThreatRing.REFRESH_SECONDS) < 0.002, [ring.visible, first_aim, ring.get("_refresh_in")])
	dummy.position = Vector2(0, -120)
	ring._process(0.02)
	var between: Vector2 = ring.aim
	ring._process(0.04)
	check("  the ball stays put between looks and follows at the next",
		between.is_equal_approx(first_aim) and ring.aim.y < -0.9, [between, ring.aim])
	sniper.engaged = false
	ring._process(0.001)
	check("  letting them go is looked at at once too, and then only %.2f s apart" % ThreatRing.IDLE_REFRESH_SECONDS,
		not ring.visible and absf(float(ring.get("_refresh_in")) - ThreatRing.IDLE_REFRESH_SECONDS) < 0.002,
		[ring.visible, ring.get("_refresh_in")])
	dummy.free()
	sniper.free()

	# ---- one recolour per kind and element ------------------------------------------------------
	var arena := Node2D.new()
	add_child(arena)
	var one: BaseEnemy = (load("res://scene/enemy/icefiresprite.tscn") as PackedScene).instantiate()
	var two: BaseEnemy = (load("res://scene/enemy/icefiresprite.tscn") as PackedScene).instantiate()
	one.position = Vector2(-9000, -9000)
	two.position = Vector2(-9100, -9000)
	arena.add_child(one)
	arena.add_child(two)
	await get_tree().process_frame
	var worn_one: Material = (one.get_node("animatedsprite2d") as CanvasItem).material
	var worn_two: Material = (two.get_node("animatedsprite2d") as CanvasItem).material
	var data: EnemyData = one.enemy_data
	var ice: ShaderMaterial = BaseEnemy.element_material(data, Element.Type.ICE)
	var fire: ShaderMaterial = BaseEnemy.element_material(data, Element.Type.FIRE)
	var ice_sprite: Node = (load("res://scene/enemy/icesprite.tscn") as PackedScene).instantiate()
	var other_kind: EnemyData = ice_sprite.get("enemy_data") as EnemyData
	ice_sprite.free()
	check("two monsters of one kind and element wear the same recolour, not one each",
		worn_one != null and worn_one == worn_two, [worn_one, worn_two])
	check("  another element, or another kind, gets its own",
		ice != fire and other_kind != null and other_kind != data
		and BaseEnemy.element_material(other_kind, Element.Type.ICE) != ice)
	check("  and it is the recolour it always was",
		is_equal_approx(float(ice.get_shader_parameter("element_hue")), Element.hue_for(Element.Type.ICE))
		and is_equal_approx(float(ice.get_shader_parameter("saturation_scale")), data.saturation_scale)
		and is_equal_approx(float(ice.get_shader_parameter("grey_tint")), data.grey_tint))

	# ---- a parked monster barely slides, and still eases out of another ------------------------
	one.set_physics_process(false)
	two.set_physics_process(false)
	two.global_position = one.global_position + Vector2(3, 0)
	await get_tree().physics_frame
	var start_gap: float = one.global_position.distance_to(two.global_position)
	var slides: int = 0
	for frame in 60:
		one.velocity = Vector2.ZERO
		var was: float = float(one.get("_still_slide_in"))
		one.call("_slide")
		if float(one.get("_still_slide_in")) > was:
			slides += 1
		await get_tree().physics_frame
	var end_gap: float = one.global_position.distance_to(two.global_position)
	var ticks: int = Engine.physics_ticks_per_second
	check("a monster standing still slides %d times a second, not %d" % [roundi(1.0 / BaseEnemy.STILL_SLIDE_SECONDS), ticks],
		slides >= 2 and slides <= ceili(60.0 / (BaseEnemy.STILL_SLIDE_SECONDS * ticks)) + 1, [slides, ticks])
	check("  and one put inside another still eases out of it", end_gap > start_gap + 2.0, [start_gap, end_gap])
	one.velocity = Vector2(10, 0)
	one.call("_slide")
	check("  a moving one slides every frame, and the first still frame after settles it",
		is_zero_approx(float(one.get("_still_slide_in"))))
	var bare: Array = []
	for path in ["res://src/enemies/baseenemy.gd", "res://src/enemies/bushmage.gd"]:
		var lines: PackedStringArray = _code_src(path).split("\n")
		for i in lines.size():
			if lines[i].strip_edges() == "move_and_slide()" and not _func_body(_code_src(path), "func _slide(").contains(lines[i]):
				bare.append("%s:%d" % [path.get_file(), i + 1])
	check("  every monster move goes through _slide(), not move_and_slide() itself", bare.is_empty(), bare)
	arena.free()

	# ---- a sleeper is out of the picture -------------------------------------------------------
	var Sleeper := preload("res://src/world/enemysleeper.gd")
	var holder := Node2D.new()
	add_child(holder)
	var player := Node2D.new()
	player.add_to_group("player")
	holder.add_child(player)
	var far := Node2D.new()
	far.position = Vector2(1500, 0)
	var hidden := Node2D.new()
	hidden.position = Vector2(1500, 100)
	hidden.visible = false
	for e in [far, hidden]:
		e.add_to_group("enemies")
		holder.add_child(e)
	var sleeper: Node = Sleeper.add_to(holder)
	sleeper.check_now()
	check("a sleeper is hidden as well as stopped", not far.visible and far.process_mode == Node.PROCESS_MODE_DISABLED)
	player.position = Vector2(1400, 0)
	sleeper.check_now()
	check("  woken, it is shown again", far.visible and far.process_mode == Node.PROCESS_MODE_INHERIT
		and not far.has_meta(&"asleep_shown"))
	check("  and one something else had hidden stays hidden", not hidden.visible)
	# The camera sits on the player (no offset, no smoothing), so the far
	# corner is half the view's diagonal away - 734 px at 1x (0.95.0).
	var view: Vector2 = Vector2(float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height"))) / _SettingsCode.CAMERA_ZOOM_MIN
	check("  never on screen: the widest view is %d x %d, and its far corner is nearer the player than %d px"
		% [int(view.x), int(view.y), int(Sleeper.WAKE_DISTANCE)],
		view.length() / 2.0 < Sleeper.WAKE_DISTANCE
		and str(ProjectSettings.get_setting("display/window/stretch/aspect", "keep")) == "keep", view)
	player.position = Vector2(-1000, 0)
	sleeper.check_now()
	# The round in progress holds only the hidden one, so nothing but the jump
	# can look at `far` this frame (A PASS SPREAD OVER ITS QUARTER SECOND).
	sleeper.set("_round", [hidden])
	sleeper.set("_round_at", 0)
	sleeper.call("player_jumped")
	player.position = Vector2(-990, 0)
	var walked: bool = sleeper.call("player_jumped")
	player.position = Vector2(1450, 0)
	sleeper._process(0.016)
	check("a player put somewhere new is looked at that frame, not a quarter second later",
		not walked and far.visible and far.process_mode == Node.PROCESS_MODE_INHERIT, [walked, far.visible])
	holder.free()

	# ---- a pass is spread over its quarter second (0.76.0) -----------------------------------
	# One pass looked at every monster in one frame: 5,888 at 16x, 19 ms of a
	# frame four times a second - a hitch you could count.
	check("a frame looks at its share of a round: at 60 fps, 393 of 5,888",
		Sleeper.round_share(5888, 1.0 / 60.0) == 393, Sleeper.round_share(5888, 1.0 / 60.0))
	check("  never none while any are left, never more than there are, none of none",
		Sleeper.round_share(3, 0.0001) == 1 and Sleeper.round_share(10, 2.0) == 10 and Sleeper.round_share(0, 0.1) == 0)
	var round_holder := Node2D.new()
	add_child(round_holder)
	var round_player := Node2D.new()
	round_player.add_to_group("player")
	round_holder.add_child(round_player)
	var far_ones: Array = []
	for i in 40:
		var far_one_node := Node2D.new()
		far_one_node.position = Vector2(2000 + i, 0)
		far_one_node.add_to_group("enemies")
		round_holder.add_child(far_one_node)
		far_ones.append(far_one_node)
	var round_sleeper: Node = Sleeper.add_to(round_holder)
	round_sleeper.call("player_jumped")
	round_sleeper._process(Sleeper.CHECK_SECONDS / 4.0)
	var after_one: int = far_ones.filter(func(n): return n.has_meta(&"asleep")).size()
	for i in 3:
		round_sleeper._process(Sleeper.CHECK_SECONDS / 4.0)
	var after_four: int = far_ones.filter(func(n): return n.has_meta(&"asleep")).size()
	check("  a quarter of the round in a quarter of its time, and all of it in all of it",
		after_one == 10 and after_four == 40, [after_one, after_four])
	round_holder.free()

	# ---- awake but idle, with nobody in reach: it dozes ------------------------------------------
	var nap_world := Node2D.new()
	add_child(nap_world)
	var napper: BaseEnemy = (load("res://scene/enemy/icefiresprite.tscn") as PackedScene).instantiate()
	napper.position = Vector2(-9000, -9000)
	nap_world.add_child(napper)
	await get_tree().process_frame
	napper.set_physics_process(false)        # its ticks are driven by hand below
	var far_one := ZoneDummy.new()
	nap_world.add_child(far_one)
	far_one.global_position = napper.global_position + Vector2(2000, 0)
	napper.player = far_one
	napper.velocity = Vector2.ZERO
	var reach: float = napper.notice_reach() + Sleeper.DOZE_MARGIN
	Sleeper.doze_or_rouse(napper, reach + 10.0)
	check("a monster at home with nobody within its notice reach + %d px dozes" % int(Sleeper.DOZE_MARGIN), napper.dozing)
	napper.set("_retarget_left", 5.0)
	napper._physics_process(0.0125)
	check("  and its brain is skipped while it does", napper.dozing
		and is_equal_approx(float(napper.get("_retarget_left")), 5.0), napper.get("_retarget_left"))
	Sleeper.doze_or_rouse(napper, reach - 10.0)
	check("  somebody within that and it is awake again", not napper.dozing)
	napper.is_returning_home = true
	Sleeper.doze_or_rouse(napper, reach + 10.0)
	var walking_dozes: bool = napper.dozing
	napper.is_returning_home = false
	napper.engaged = true
	Sleeper.doze_or_rouse(napper, reach + 10.0)
	check("  one walking home or after somebody never dozes", not walking_dozes and not napper.dozing)
	napper.engaged = false
	Sleeper.doze_or_rouse(napper, reach + 10.0)
	napper.engaged = true                    # what a hit does (take_damage())
	napper._physics_process(0.0125)
	check("  a hit rouses a dozing one, and it thinks that very tick", not napper.dozing
		and float(napper.get("_retarget_left")) < 5.0, [napper.dozing, napper.get("_retarget_left")])
	napper.engaged = false
	napper.velocity = Vector2(30, 0)
	napper.dozing = true
	napper._physics_process(0.0125)
	check("  and so does being on the move", not napper.dozing)
	var doze_sleeper: Node = Sleeper.add_to(nap_world)
	napper.dozing = true
	doze_sleeper.enabled = false
	check("  turning the sleeper off rouses everybody", not napper.dozing)
	nap_world.free()
	check("  and BushMage, whose brain is its own, dozes the same way",
		_func_body(_code_src("res://src/enemies/bushmage.gd"), "func _physics_process(").contains("if _dozes():")
		and _func_body(_code_src("res://src/enemies/baseenemy.gd"), "func _physics_process(").contains("if _dozes():"))


# =============================================================================
# A CROWD THINKS IN TURNS (0.67.0)
# =============================================================================
# The owner, after 0.66.0: "we can make it even faster but i need ideas it can
# almost handle x8" - choosing the ones nobody can see, and "All of these try
# to keep the feel first, before changing fight rules". Timed piece by piece
# at 8x round one warrior: the 200 monsters fighting were 13 ms of a 22 ms
# physics tick - sight checks 2.4, crowd work (who is near me, my place off
# the walls) 3.5, slides 4.7 - and 1,300 dozers still cost a call each tick.
func _test_a_crowd_thinks_in_turns() -> void:
	section("A CROWD THINKS IN TURNS - sight remembered, crowd work on a stride, two slides, dozers off screen stop (0.67.0)")
	var world := Node2D.new()
	add_child(world)
	var at := Vector2(-64000, -64000)
	var seer: BaseEnemy = (load("res://scene/enemy/icefiresprite.tscn") as PackedScene).instantiate()
	seer.position = at
	world.add_child(seer)
	await get_tree().physics_frame
	seer.set_physics_process(false)        # driven by hand below

	# ---- sight, remembered for 0.1 s ----------------------------------------------------------
	var target: Vector2 = at + Vector2(200, 0)
	var first: bool = seer._has_line_of_sight(target)
	var query: Object = seer.get("_sight_query")
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var wall_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 200)
	wall_shape.shape = rect
	wall.add_child(wall_shape)
	wall.position = at + Vector2(100, 0)
	world.add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var remembered: bool = seer._has_line_of_sight(target)
	var moved_end: bool = seer._has_line_of_sight(target + Vector2(0, BaseEnemy.SIGHT_REUSE_PX + 2.0))
	check("a clear line, asked again about the same two ends within %d ticks, is the answer it had"
		% BaseEnemy.SIGHT_REUSE_TICKS, first and remembered, [first, remembered])
	check("  one query object, moved, not one built every ask", query != null and seer.get("_sight_query") == query)
	check("  a point further off than %d px is asked afresh - and the wall is seen" % int(BaseEnemy.SIGHT_REUSE_PX),
		not moved_end)
	for i in BaseEnemy.SIGHT_REUSE_TICKS + 1:
		await get_tree().physics_frame
	check("  and %d ticks on the old answer is gone: the wall is seen from where it stood too"
		% (BaseEnemy.SIGHT_REUSE_TICKS + 1), not seer._has_line_of_sight(target))
	wall.free()

	# ---- the stride, by distance from whoever it is after -------------------------------------
	var dummy := ZoneDummy.new()
	world.add_child(dummy)
	seer.player = dummy
	var stride_at := func(d: float) -> int:
		dummy.global_position = seer.global_position + Vector2(d, 0)
		return seer.think_stride()
	check("crowd work every tick within %d px of its target, every 2nd within %d, every 4th further out"
		% [int(BaseEnemy.NEAR_BAND), int(BaseEnemy.MID_BAND)],
		stride_at.call(40.0) == 1 and stride_at.call(BaseEnemy.NEAR_BAND) == 1
		and stride_at.call(150.0) == 2 and stride_at.call(BaseEnemy.MID_BAND + 1.0) == 4,
		[stride_at.call(40.0), stride_at.call(150.0), stride_at.call(500.0)])
	var phase: int = int(seer.get("_phase"))
	check("  each monster on a tick of its own (a phase 0..3), so a crowd's work is spread", phase >= 0 and phase < 4, phase)

	# ---- neighbours: found on the stride, read where they stand every tick --------------------
	var mate: BaseEnemy = (load("res://scene/enemy/icefiresprite.tscn") as PackedScene).instantiate()
	mate.position = at + Vector2(20, 0)
	world.add_child(mate)
	await get_tree().physics_frame
	mate.set_physics_process(false)
	dummy.global_position = seer.global_position + Vector2(500, 0)      # far: every 4th tick
	var tick: int = Engine.get_physics_frames()
	seer.set("_phase", (5 - tick % 4) % 4)     # (tick + phase) % 4 == 1: three ticks to its turn
	seer.set("_neighbours_tick", -1000)
	var found: Array = seer._nearby_enemy_offsets()
	mate.global_position += Vector2(0, 5)
	var live: Array = seer._nearby_enemy_offsets()
	check("a neighbour is found, and where it stands is read every tick, not remembered",
		found.size() == 1 and (found[0] as Vector2).is_equal_approx(Vector2(20, 0))
		and live.size() == 1 and (live[0] as Vector2).is_equal_approx(Vector2(20, 5)), [found, live])
	var late: BaseEnemy = (load("res://scene/enemy/icefiresprite.tscn") as PackedScene).instantiate()
	late.position = at + Vector2(-20, 0)
	world.add_child(late)
	await get_tree().physics_frame
	late.set_physics_process(false)
	var before_turn: int = seer._nearby_enemy_offsets().size()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var on_turn: int = seer._nearby_enemy_offsets().size()
	check("  one who walks up is noticed on its next turn (at most 4 ticks), not before",
		before_turn == 1 and on_turn == 2, [before_turn, on_turn])
	check("  and its place off the walls is worked out on the stride and carried with the player",
		_func_body(_code_src("res://src/enemies/baseenemy.gd"), "func _get_slot_target_position(").contains("_due(_slot_fix_tick, tick)")
		and _func_body(_code_src("res://src/enemies/baseenemy.gd"), "func clamp_to_navigation(").contains("_map_has_regions(map)"))

	# ---- two slides a tick ------------------------------------------------------------------------
	check("a monster slides at most %d times a tick, not Godot's 4" % BaseEnemy.MAX_SLIDES,
		seer.max_slides == BaseEnemy.MAX_SLIDES and mate.max_slides == BaseEnemy.MAX_SLIDES, seer.max_slides)

	# ---- a dozer off screen stops; anything that rouses it starts it again ---------------------
	var Sleeper := preload("res://src/world/enemysleeper.gd")
	var reach: float = seer.notice_reach() + Sleeper.DOZE_MARGIN
	var on_screen := Rect2(seer.global_position - Vector2(50, 50), Vector2(100, 100))
	var elsewhere := Rect2(seer.global_position + Vector2(5000, 5000), Vector2(100, 100))
	Sleeper.doze_or_rouse(seer, reach + 10.0, on_screen)
	check("a dozer on this game's screen keeps running (its picture and ring live)",
		seer.dozing and seer.process_mode == Node.PROCESS_MODE_INHERIT)
	Sleeper.doze_or_rouse(seer, reach + 10.0, elsewhere)
	check("  one off it stops altogether - and is still drawn",
		seer.dozing and seer.process_mode == Node.PROCESS_MODE_DISABLED and seer.visible)
	var bodies_at := func(spot: Vector2) -> Array:
		var probe := PhysicsPointQueryParameters2D.new()
		probe.position = spot
		probe.collision_mask = 8                 # the enemies' layer
		return (world.get_world_2d().direct_space_state.intersect_point(probe) as Array).map(
			func(hit: Dictionary) -> Object: return hit.get("collider"))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var stopped_in_world: bool = bodies_at.call(seer.global_position).has(seer)
	seer.take_damage(1)
	check("  a hit starts it again that moment", not seer.dozing and seer.process_mode == Node.PROCESS_MODE_INHERIT
		and seer.engaged, [seer.dozing, seer.process_mode])
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("  stopped, it is out of the physics world, as a sleeper is (Godot's disable_mode); roused, back in",
		not stopped_in_world and bodies_at.call(seer.global_position).has(seer), stopped_in_world)
	seer.engaged = false
	Sleeper.doze_or_rouse(seer, reach + 10.0, elsewhere)
	Sleeper.doze_or_rouse(seer, reach - 10.0, elsewhere)
	check("  and so does somebody coming within its reach", not seer.dozing and seer.process_mode == Node.PROCESS_MODE_INHERIT)
	Sleeper.doze_or_rouse(seer, reach + 10.0, elsewhere)
	Sleeper.put_to_sleep(seer)
	seer.dozing = false
	check("  rousing never wakes one the sleeper has put to sleep", seer.process_mode == Node.PROCESS_MODE_DISABLED
		and seer.has_meta(&"asleep"))
	seer.remove_meta(&"asleep")
	seer.process_mode = Node.PROCESS_MODE_INHERIT
	mate.net_mirror = true
	Sleeper.doze_or_rouse(mate, reach + 10.0, elsewhere)
	check("  and a monster another game runs is never stopped - it must keep following",
		mate.process_mode == Node.PROCESS_MODE_INHERIT)
	mate.net_mirror = false
	world.free()


# =============================================================================
# THE CRYPT CROWD IS CHEAP (0.68.0)
# =============================================================================
# The owner's 8x video (0.67.0): 60 fps in the open, and 8 fps among the
# crypt's skeletons - physics 13 to 18 ms a tick on his PC against 12.5, so
# Godot ran extra ticks to catch up and frames reached 125 ms. On the bench at
# the hall door the tick was 71 ms, and two things in it were not the crowd at
# all: the 160 skeletons without a place in the ring each searched all 40
# places every tick (18.6 ms - in a corridor half the ring is wall, so those
# places never fill and everyone kept asking the navmesh about them), and
# every skeleton re-planned its route round the walls every tick, because
# Godot plans afresh each time a target is SET (9 ms).
func _test_the_crypt_crowd_is_cheap() -> void:
	section("THE CRYPT CROWD IS CHEAP - a place sought every 0.1 s, walls asked once a tick, routes re-planned only on a move (0.68.0)")
	var world := Node2D.new()
	add_child(world)
	var at := Vector2(-66000, -66000)
	var foe: BaseEnemy = (load("res://scene/enemy/skeletonsoldier.tscn") as PackedScene).instantiate()
	foe.position = at
	world.add_child(foe)
	await get_tree().physics_frame
	foe.set_physics_process(false)
	var dummy := ZoneDummy.new()
	world.add_child(dummy)
	dummy.global_position = at + Vector2(150, 0)
	foe.player = dummy

	# ---- a route re-planned only once its target has moved ------------------------------------
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var wall_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 200)
	wall_shape.shape = rect
	wall.add_child(wall_shape)
	wall.position = at + Vector2(75, 0)
	world.add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var goal: Vector2 = at + Vector2(150, 0)
	foe._heading_vector_to(goal)
	var first_route: Vector2 = foe.get("_route_to")
	var agent_first: Vector2 = foe.nav_agent.target_position
	foe._heading_vector_to(goal + Vector2(BaseEnemy.REROUTE_PX - 3.0, 0))
	var kept: Vector2 = foe.get("_route_to")
	var agent_kept: Vector2 = foe.nav_agent.target_position
	foe._heading_vector_to(goal + Vector2(BaseEnemy.REROUTE_PX + 3.0, 0))
	var moved: Vector2 = foe.get("_route_to")
	check("behind a wall, the route is planned for where its target is",
		first_route.is_equal_approx(goal) and agent_first.is_equal_approx(goal), [first_route, agent_first])
	check("  a target moved less than %d px keeps the route it has (Godot re-plans on every set)" % int(BaseEnemy.REROUTE_PX),
		kept.is_equal_approx(goal) and agent_kept.is_equal_approx(goal), [kept, agent_kept])
	check("  and one moved further is planned afresh", moved.is_equal_approx(goal + Vector2(BaseEnemy.REROUTE_PX + 3.0, 0)), moved)
	wall.free()

	# ---- no place in the ring: it looks again every 0.1 s, not every tick ----------------------
	var owners: Dictionary = BaseEnemy._slot_owners
	var kept_owners: Dictionary = owners.duplicate()
	owners.clear()
	var holder := Node2D.new()
	world.add_child(holder)
	for i in Formation.slot_count():
		owners[i] = holder                      # every place taken
	foe.set("_claimed_slot", -1)
	foe.set("_slot_retry_time", 0.0)
	foe._ensure_slot_claimed()
	var waiting: float = float(foe.get("_slot_retry_time"))
	owners.erase(3)                            # a place comes free
	foe._ensure_slot_claimed()
	var still_none: int = int(foe.get("_claimed_slot"))
	check("a monster that finds no place waits about %.2f s before it looks again" % BaseEnemy.SLOT_RETRY_SECONDS,
		waiting >= BaseEnemy.SLOT_RETRY_SECONDS * 0.7 and waiting <= BaseEnemy.SLOT_RETRY_SECONDS * 1.3, waiting)
	check("  and a place that comes free meanwhile is not taken before then", still_none == -1, still_none)
	foe.set("_slot_retry_time", 0.0)
	foe._ensure_slot_claimed()
	check("  when it looks, it takes it", int(foe.get("_claimed_slot")) == 3 and owners.get(3) == foe,
		foe.get("_claimed_slot"))
	foe.set("_slot_retry_time", 1.0)
	foe._release_slot()
	check("  and one that gives a place up looks for another at once, not after the wait",
		is_zero_approx(float(foe.get("_slot_retry_time"))))
	owners.clear()
	for k in kept_owners:
		owners[k] = kept_owners[k]

	# ---- which places are in a wall: asked once a tick, for everybody ---------------------------
	var anchor: Vector2 = dummy.global_position
	var slot_at: Vector2 = Formation.world_position(anchor, 0)
	var walled: bool = foe._slot_in_wall(anchor, 0, slot_at)
	var cache: Dictionary = BaseEnemy._walls
	var asked_once: bool = cache.size() == 1 and (cache.values()[0] as PackedByteArray)[0] != 0
	var same: bool = foe._slot_in_wall(anchor, 0, slot_at) == walled
	check("whether a place is in a wall is asked of the navmesh once and read by everyone that tick",
		asked_once and same and walled == (foe.clamp_to_navigation(slot_at).distance_to(slot_at) > Formation.BODY_RADIUS),
		[cache.size(), walled])
	await get_tree().physics_frame
	foe._slot_in_wall(anchor + Vector2(1, 0), 0, slot_at)
	check("  and asked afresh the next tick (the player has moved, the walls are where they were)",
		BaseEnemy._walls.size() == 1 and not BaseEnemy._walls.has(Vector3i(roundi(anchor.x), roundi(anchor.y),
			foe.get_world_2d().navigation_map.get_id() & 0x7fffffff)))
	check("  the search uses it", _func_body(_code_src("res://src/enemies/baseenemy.gd"), "func _ensure_slot_claimed(").contains("_slot_in_wall(anchor"))
	world.free()


# =============================================================================
# A CROWD WAITS ITS TURN (0.73.0)
# =============================================================================
# The owner, of the 8x stress test: "my pc fires up a bit and some lag is going
# on". Timed on the bench at a crypt door, 200 skeletons after one player:
# 120 stood more than 48 px from where they were walking, wedged behind each
# other, and still steered and shoved every tick - 10 of the 14 ms their brains
# cost. Now one held up by the crowd waits its turn (baseenemy.gd, IN A JAM, IT
# WAITS ITS TURN), and a place is found in one pass rather than a sort.
func _test_a_crowd_waits_its_turn() -> void:
	section("A CROWD WAITS ITS TURN - a jam stands still, and a place is found in one pass (0.73.0)")
	# ---- the places, and their lists ----------------------------------------------------------------
	var total := 0
	for ring in range(1, Formation.RING_COUNT + 1):
		total += Formation.slots_in_ring(ring)
	check("three rings of places round a player still, 40 in all - seven were tried, and were slower",
		Formation.RING_COUNT == 3 and total == 40 and Formation.slot_count() == total, [Formation.RING_COUNT, total])
	var lists_agree := true
	var rings: PackedInt32Array = Formation.ring_list()
	var bearings: PackedFloat32Array = Formation.bearing_list()
	for i in Formation.slot_count():
		lists_agree = lists_agree and rings[i] == Formation.ring_of(i) \
			and absf(angle_difference(bearings[i], Formation.bearing_of(i))) < 0.0001
	check("  each place's ring and bearing are kept in a list for the search, and agree with ring_of() and bearing_of()",
		lists_agree and rings.size() == total and bearings.size() == total)

	# ---- the one-pass search finds what the sort did ------------------------------------------------
	var world := Node2D.new()
	add_child(world)
	var at := Vector2(-71000, -71000)
	var foe: BaseEnemy = (load("res://scene/enemy/skeletonsoldier.tscn") as PackedScene).instantiate()
	foe.position = at
	world.add_child(foe)
	await get_tree().physics_frame
	foe.set_physics_process(false)
	var dummy := ZoneDummy.new()
	world.add_child(dummy)
	dummy.global_position = at + Vector2(150, 0)
	foe.player = dummy
	var owners: Dictionary = BaseEnemy._slot_owners
	var kept_owners: Dictionary = owners.duplicate()
	var holder := Node2D.new()
	world.add_child(holder)
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	var mismatches: Array = []
	for trial in 60:
		owners.clear()
		for i in Formation.slot_count():
			if rng.randf() < 0.6:
				owners[i] = holder
		foe.global_position = dummy.global_position + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20.0, 220.0)
		var holds_one: bool = rng.randf() < 0.5
		var mine: int = -1
		if holds_one:
			for i in Formation.slot_count():
				if not owners.has(i):
					mine = i
					break
			owners[mine] = foe
		foe.set("_claimed_slot", mine)
		foe.set("_last_released_slot", -1)
		foe.set("_slot_retry_time", 0.0)
		foe.set("_slot_review_time", 0.0)
		# The old way: every free place scored, sorted, the first that clears the margin.
		var anchor: Vector2 = dummy.global_position
		var to_anchor: Vector2 = foe.global_position - anchor
		var weight: float = foe._bearing_weight(to_anchor.length())
		var current: float = foe._slot_score(mine, to_anchor.angle(), weight) if holds_one else INF
		var want_score: float = INF
		for i in Formation.slot_count():
			if i == mine or (owners.get(i) != null and is_instance_valid(owners.get(i))):
				continue
			var sc: float = foe._slot_score(i, to_anchor.angle(), weight)
			if sc <= current - BaseEnemy.SLOT_SWITCH_MARGIN and sc < want_score:
				want_score = sc
		foe._ensure_slot_claimed()
		var got: int = int(foe.get("_claimed_slot"))
		var got_score: float = INF if got == mine else foe._slot_score(got, to_anchor.angle(), weight)
		if want_score == INF:
			if got != mine:
				mismatches.append([trial, "moved", got])
		elif absf(got_score - want_score) > 0.01:
			mismatches.append([trial, got, got_score, want_score])
	check("the one-pass search takes the place the sort took, every time (60 crowds, held and not)",
		mismatches.is_empty(), mismatches.slice(0, 4))
	owners.clear()
	for k in kept_owners:
		owners[k] = kept_owners[k]

	# ---- a jam stands still, a wall or a chase does not ----------------------------------------------
	var neighbour := Node2D.new()
	world.add_child(neighbour)
	var target: Vector2 = foe.global_position + Vector2(100, 0)
	var ticks: int = ceili(BaseEnemy.QUEUE_AFTER_SECONDS * 80.0) + 1
	var stand := func(pressed: Array, step: Vector2) -> float:
		foe.set("_neighbours", pressed)
		foe.set("_queue_time", 0.0)
		foe.set("_queue_tries", 0)
		foe.set("_headway", 0.0)
		foe.set("_headway_time", 0.0)
		for i in ticks:
			var before: Vector2 = foe.global_position
			foe.global_position += step
			foe._note_headway(before, target)
		return float(foe.get("_queue_time"))
	var crowd: Array[Node2D] = [neighbour]
	var none: Array[Node2D] = []
	var jammed: float = stand.call(crowd, Vector2.ZERO)
	var shoved: float = stand.call(crowd, Vector2(0, 0.9))
	var walled: float = stand.call(none, Vector2.ZERO)
	var speed: float = foe.get_move_speed() / 80.0
	var chasing: float = stand.call(crowd, Vector2(speed, 0))
	check("held up %.2f s with monsters pressed round it, it waits its turn, %.2f s or so" % [BaseEnemy.QUEUE_AFTER_SECONDS, BaseEnemy.QUEUE_SECONDS],
		jammed >= BaseEnemy.QUEUE_SECONDS * 0.7 and jammed <= BaseEnemy.QUEUE_SECONDS * 1.3, jammed)
	check("  shoved sideways round the crowd is no headway either", shoved > 0.0, shoved)
	check("  but stuck on a wall with nobody near, it does not - that is the old escalation's", walled == 0.0, walled)
	check("  and walking at its place, crowd or no crowd, it does not", chasing == 0.0, chasing)
	foe.set("_neighbours", crowd)
	foe.set("_queue_tries", 0)
	owners.clear()
	owners[5] = foe
	foe.set("_claimed_slot", 5)
	var waits := 0
	var held_until := -1
	for attempt in BaseEnemy.QUEUE_TRIES:
		foe.set("_queue_time", 0.0)
		foe.set("_headway", 0.0)
		foe.set("_headway_time", 0.0)
		for i in ticks:
			foe._note_headway(foe.global_position, target)
		if float(foe.get("_queue_time")) > 0.0:
			waits += 1
		if int(foe.get("_claimed_slot")) == 5:
			held_until = attempt
	check("  it waits every time the queue has not moved, and at wait %d in a row gives its place up and looks again, so a jam still breaks" % BaseEnemy.QUEUE_TRIES,
		waits == BaseEnemy.QUEUE_TRIES and held_until == BaseEnemy.QUEUE_TRIES - 2 and not owners.has(5)
		and int(foe.get("_queue_tries")) == 0, [waits, held_until, owners.keys()])
	owners.clear()
	for k in kept_owners:
		owners[k] = kept_owners[k]
	foe.set("_queue_time", 0.2)
	foe.velocity = Vector2(30, 0)
	foe._chase_slot()
	check("  waiting, it stands: no step, and its wait runs down", foe.velocity == Vector2.ZERO
		and float(foe.get("_queue_time")) < 0.2, [foe.velocity, foe.get("_queue_time")])
	check("  and the chase hears it: every step's headway is noted",
		_func_body(_code_src("res://src/enemies/baseenemy.gd"), "func _chase_slot(").contains("_note_headway(pos_before, slot_target)"))
	world.free()


# =============================================================================
# EVERY CLASS IS DRAWN IN FRONT OF A WALL IT STANDS AGAINST (0.68.1)
# =============================================================================
# The owner, 21 Oct, a screenshot of a mage at the crypt's north wall with only
# the hem of its robe showing under the bricks: "big error on walls". A
# y-sorted body sorts each of its pictures by that picture's own height, and
# the mage's picture is placed 19 px above its feet - so walked up to a wall,
# the picture sorted 9 px north of the wall's foot and the wall was drawn over
# it. Worked out here for every class from its own scene: walked up to a wall
# (the top of its body on the wall's foot), the height it sorts at must be
# south of that foot. The warrior's picture sits at its feet, the healer is not
# y-sorted, the tank's capsule keeps it 32 px off; the mage was the one wrong.
func _test_every_class_stands_in_front_of_a_wall() -> void:
	section("WALLS - every class walked up to a wall is drawn in front of it, not under it (0.68.1)")
	var wrong: Array = []
	var seen: Array = []
	for cls in ["warrior", "mage", "healer", "tank"]:
		var hero := (load("res://scene/characters/%s.tscn" % cls) as PackedScene).instantiate() as Node2D
		var body := hero.get_node_or_null(^"bodyshape") as CollisionShape2D
		var picture := hero.get_node_or_null(^"animatedsprite2d") as Node2D
		var top: float = INF
		if body != null and body.shape is CircleShape2D:
			top = body.position.y - (body.shape as CircleShape2D).radius
		elif body != null and body.shape is CapsuleShape2D:
			top = body.position.y - (body.shape as CapsuleShape2D).height * 0.5
		elif body != null and body.shape is RectangleShape2D:
			top = body.position.y - (body.shape as RectangleShape2D).size.y * 0.5
		if top == INF or picture == null or not is_zero_approx(body.rotation):
			wrong.append("%s: no body this can measure" % cls)
			hero.free()
			continue
		# Its origin, with the top of its body on a wall's foot at y = 0.
		var at_wall: float = -top
		var sorts_at: float = at_wall + (picture.position.y if hero.y_sort_enabled else 0.0)
		seen.append("%s %+.1f" % [cls, sorts_at])
		if sorts_at <= 0.0:
			wrong.append("%s sorts %.1f px behind the wall it stands against" % [cls, -sorts_at])
		hero.free()
	check("every class stands in front of a wall it walks up to: its picture sorts south of the wall's foot",
		wrong.is_empty(), [wrong, seen])
	# The walls' side of it: a crypt wall piece sorts at its foot - its node
	# origin is the bottom of its picture and of its body.
	var off_foot: Array = []
	for piece in ["wallrun1", "wallrun2", "wallrun4"]:
		var wall := (load("res://scene/crypt/%s.tscn" % piece) as PackedScene).instantiate() as Node2D
		var art := wall.get_node(^"sprite") as Sprite2D
		var shape := wall.get_node(^"body/collisionbase") as CollisionShape2D
		var art_foot: float = art.position.y + art.offset.y + art.texture.get_height() * 0.5
		var body_foot: float = shape.position.y + (shape.shape as RectangleShape2D).size.y * 0.5
		if not is_zero_approx(art_foot) or not is_zero_approx(body_foot):
			off_foot.append([piece, art_foot, body_foot])
		wall.free()
	check("  and a crypt wall's picture and body both end at its origin, the line it sorts on", off_foot.is_empty(), off_foot)


# =============================================================================
# ONE CHARACTER'S MAP IS NOT ANOTHER'S WORLD (0.68.1)
# =============================================================================
# The owner's log, 21 Oct, logging in his tank: "WorldMap: the stored map for
# 'bigfield' would not decompress to the size it claims." The area's terrain
# outlives a character - another one had walked the Big Field that session, so
# it was built at today's size - and the tank's bits, saved before the crypt
# made the field bigger, were kept beside it. The next save wrote today's width
# and height round the old bits, which no load could read back.
func _test_one_characters_map_is_not_anothers_world() -> void:
	section("WORLD MAP - a saved map that does not fit the world as built starts again, and none is written that cannot be read (0.68.1)")
	var kept_seen: Dictionary = WorldMap._seen.duplicate(true)
	var kept_terrain: Dictionary = WorldMap._terrain.duplicate(true)
	var kept_cache: Dictionary = WorldMap._save_cache.duplicate(true)
	var kept_dirty: bool = WorldMap._save_dirty
	const AREA := "zz_maptest"
	var blob := func(w: int, h: int) -> Dictionary:
		var bits := PackedByteArray()
		bits.resize((w * h + 7) >> 3)
		bits.fill(255)
		return {"w": w, "h": h, "ox": 0, "oy": 0,
			"bits": Marshalls.raw_to_base64(bits.compress(FileAccess.COMPRESSION_DEFLATE))}
	var readable := func(written: Dictionary) -> Array:
		var bad: Array = []
		for area in written:
			var e: Dictionary = written[area]
			var want: int = (int(e["w"]) * int(e["h"]) + 7) >> 3
			var got: int = Marshalls.base64_to_raw(str(e["bits"])).decompress(want, FileAccess.COMPRESSION_DEFLATE).size()
			if got != want:
				bad.append([area, e["w"], e["h"], got, want])
		return bad
	# Another character walked it this session: built, 20 x 10 tiles now.
	var built := Image.create_empty(20, 10, false, Image.FORMAT_RGBA8)
	WorldMap._terrain[AREA] = {"image": built, "origin": Vector2i.ZERO, "size": Vector2i(20, 10), "tile": Vector2i(16, 16)}
	# This character's save is from when it was 12 x 10.
	WorldMap.from_save({AREA: blob.call(12, 10)})
	var kept_bits = WorldMap._seen.get(AREA, null)
	check("a map saved for an area of another size than it is built at is not kept beside it",
		not (kept_bits is PackedByteArray) or (kept_bits as PackedByteArray).size() == (20 * 10 + 7) >> 3,
		str((kept_bits as PackedByteArray).size()) if kept_bits is PackedByteArray else "none")
	var bad_after: Array = readable.call(WorldMap.to_save())
	check("  and every map written can be read back at the size it says", bad_after.is_empty(), bad_after)
	# Not built this session, but stubbed from another character's save at 12 x 10:
	# this one's, at 14 x 10, replaces the stub rather than being written round it.
	WorldMap._terrain[AREA] = {"image": null, "origin": Vector2i.ZERO, "size": Vector2i(12, 10), "tile": Vector2i(16, 16)}
	WorldMap.from_save({AREA: blob.call(14, 10)})
	var saved: Dictionary = WorldMap.to_save()
	check("  a stub from another character's save is replaced by this one's shape",
		readable.call(saved).is_empty() and saved.has(AREA) and int((saved[AREA] as Dictionary)["w"]) == 14,
		saved.get(AREA, {}).get("w"))
	# And the writer's own guard: bits that do not fit are never written.
	WorldMap._terrain[AREA] = {"image": built, "origin": Vector2i.ZERO, "size": Vector2i(20, 10), "tile": Vector2i(16, 16)}
	var wrong := PackedByteArray()
	wrong.resize(5)
	WorldMap._seen[AREA] = wrong
	WorldMap._save_dirty = true
	check("  and bits that do not fit their area's size are left out of a save, not written broken",
		not WorldMap.to_save().has(AREA))
	WorldMap._seen = kept_seen
	WorldMap._terrain = kept_terrain
	WorldMap._save_cache = kept_cache
	WorldMap._save_dirty = kept_dirty

func _test_the_larder_loads() -> void:
	section("LARDER - the 67 new materials, staples, baits and meals load, each with a picture of its own (0.74.0)")

	# THE REGISTRY'S OWN BOOT LINE, as a check. scanned N, loaded M is how a
	# duplicate id or a bad header shows itself, and only if somebody reads it.
	var all_items: Array[ItemData] = ItemRegistry.get_all_items()
	check("the registry loaded every item resource it found",
		ItemRegistry._item_files_seen == all_items.size(),
		"scanned %d, loaded %d" % [ItemRegistry._item_files_seen, all_items.size()])

	var expected: Dictionary = _larder_expected()
	check("the larder is 67 items: 22 for the smith, 14 produce, 10 staples, 2 baits, 19 meals",
		expected.size() == 67 and LARDER_SMITH.size() == 22 and LARDER_PRODUCE.size() == 14
		and LARDER_STAPLES.size() == 10 and LARDER_BAITS.size() == 2 and LARDER_MEALS.size() == 19,
		expected.size())

	var absent: Array = []
	var wrong_icon: Array = []
	var wrong_kind: Array = []
	for id in expected:
		if not ItemRegistry.has_item(id):
			absent.append(id)
			continue
		var item: ItemData = ItemRegistry.get_item(id)
		var want: Array = expected[id]
		var icon_path: String = "res://art/pack/%s/%s.png" % [want[0], id]
		# THE PNG ITSELF, not only what loads: the import cache keeps serving a
		# picture whose file is gone, on the one machine that has the cache.
		if item.icon == null or item.icon.resource_path != icon_path \
				or item.icon.get_size() != Vector2(16, 16) or not FileAccess.file_exists(icon_path):
			wrong_icon.append("%s: %s" % [id, item.icon.resource_path if item.icon != null else "no icon"])
		# Its own file, under its own id: the convention that makes a log line
		# findable, and the one a copy-pasted .tres breaks first.
		if item.item_id != id or item.resource_path.get_file() != "%s.tres" % id \
				or int(item.type) != int(want[1]) or not item.stackable \
				or item.max_stack != int(want[2]) or item.droppable or item.display_name == "" \
				or item.description == "" or item.value <= 0:
			wrong_kind.append(id)
	check_needs_pack("every one of them is in the registry", absent.is_empty(), absent)
	check_needs_pack("  each with its icon, 16 x 16, cut to art/pack/<materials|food|fishing>/<id>.png",
		wrong_icon.is_empty(), wrong_icon)
	check_needs_pack("  and its type, its stack, a name, a description, a price, and never generic loot",
		wrong_kind.is_empty(), wrong_kind)

	# NO TWO ITEMS SHARE A PICTURE. The owner's rule is one whole cell of the
	# Raven Fantasy sheet per icon; two items on one cell is two things a player
	# cannot tell apart in a bag. Compared by pixels, against every item in the
	# game, so an old icon reused under a new name is caught as well.
	var owner_of: Dictionary = {}
	var shared: Array = []
	for item in all_items:
		if item.icon == null:
			continue
		var pixels: PackedByteArray = item.icon.get_image().get_data()
		if owner_of.has(pixels):
			if expected.has(item.item_id) or expected.has(String(owner_of[pixels])):
				shared.append("%s and %s" % [owner_of[pixels], item.item_id])
		else:
			owner_of[pixels] = item.item_id
	var anvil: Texture2D = load("res://art/pack/smith/anvil.png") as Texture2D \
		if ResourceLoader.exists("res://art/pack/smith/anvil.png") \
			and FileAccess.file_exists("res://art/pack/smith/anvil.png") else null
	if anvil != null and owner_of.has(anvil.get_image().get_data()):
		shared.append("the anvil and %s" % owner_of[anvil.get_image().get_data()])
	check_needs_pack("no new icon is the same picture as any other item's", shared.is_empty(), shared)
	check_needs_pack("  and the smith's anvil is cut too, 16 x 16 (art/pack/smith/anvil.png)",
		anvil != null and anvil.get_size() == Vector2(16, 16))

	# ---- the recipes ------------------------------------------------------------
	var meals: Array[ItemData] = []
	for id in LARDER_MEALS:
		if ItemRegistry.has_item(id):
			meals.append(ItemRegistry.get_item(id))
	var bad_recipes: Array = []
	var recipes: Dictionary = {}
	for meal in meals:
		recipes[meal.item_id] = meal.recipe_ingredients
		# "meals that combine 2-3+ ingredients"
		if not meal.is_meal() or meal.recipe_ingredients.size() < 2:
			bad_recipes.append("%s takes %d ingredient(s)" % [meal.item_id, meal.recipe_ingredients.size()])
		for ingredient in meal.recipe_ingredients:
			var count: Variant = meal.recipe_ingredients[ingredient]
			if not (ingredient is String) or not ItemRegistry.has_item(String(ingredient)):
				bad_recipes.append("%s needs '%s', which is no item" % [meal.item_id, ingredient])
			if typeof(count) != TYPE_INT or int(count) < 1:
				bad_recipes.append("%s needs %s of %s" % [meal.item_id, str(count), ingredient])
		if meal.recipe_level < 1 or meal.recipe_mastery_level < meal.recipe_level or meal.recipe_xp <= 0:
			bad_recipes.append("%s: level %d, mastery %d, xp %d" % [meal.item_id,
				meal.recipe_level, meal.recipe_mastery_level, meal.recipe_xp])
	check_needs_pack("every recipe combines two or more real items, at least one of each, and trains cooking",
		meals.size() == LARDER_MEALS.size() and bad_recipes.is_empty(), bad_recipes)
	var loops: Array = _larder_recipe_loops(recipes)
	check_needs_pack("  and no recipe needs itself, however many meals it goes through",
		not recipes.is_empty() and loops.is_empty(), loops)
	check("  (the loop finder finds one when it is there, two meals deep and through itself)",
		_larder_recipe_loops({"a": {"b": 1}, "b": {"salt": 1, "a": 1}}).size() == 1
		and _larder_recipe_loops({"a": {"a": 1}}).size() == 1
		and _larder_recipe_loops({"soup": {"broth": 1}, "broth": {"bone": 2}}).is_empty())
	check_needs_pack("  a meal can be made from another: Shadowcap Soup takes Bone Broth, the Royal Banquet a sushi and a tart",
		recipes.get("shadowcapsoup", {}).has("bonebroth")
		and recipes.get("royalbanquet", {}).has("azuretangsushi")
		and recipes.get("royalbanquet", {}).has("nightberrytart"))

	# ---- what eating one does -------------------------------------------------
	var no_heal: Array = []
	var no_buff: Array = []
	var gated: Array = []
	var not_more: Array = []
	for meal in meals:
		if meal.type != ItemData.Type.CONSUMABLE or meal.restore_target != ItemData.RestoreTarget.HP \
				or meal.restore_amount <= 0:
			no_heal.append(meal.item_id)
		if meal.buff_kind == ItemData.BuffKind.NONE or meal.buff_amount <= 0 or meal.buff_seconds <= 0 \
				or not meal.buff_text().begins_with("+") or not meal.buff_text().contains(" for "):
			no_buff.append("%s: '%s'" % [meal.item_id, meal.buff_text()])
		# ANYONE MAY EAT A MEAL - a cook can sell what they make. The fish keep
		# their cooking gate; a meal's gate is the character level alone.
		if meal.required_skill != "":
			gated.append(meal.item_id)
		# "heal more": a meal with a fish in it beats that fish cooked alone.
		for ingredient in meal.recipe_ingredients:
			var raw: ItemData = ItemRegistry.get_item(String(ingredient)) \
				if ItemRegistry.has_item(String(ingredient)) else null
			if raw == null or raw.cooks_into == "" or not ItemRegistry.has_item(raw.cooks_into):
				continue
			var cooked: ItemData = ItemRegistry.get_item(raw.cooks_into)
			if meal.restore_amount <= cooked.restore_amount:
				not_more.append("%s %d vs %s %d" % [meal.item_id, meal.restore_amount,
					cooked.item_id, cooked.restore_amount])
	check_needs_pack("every meal heals", meals.size() == LARDER_MEALS.size() and no_heal.is_empty(), no_heal)
	check_needs_pack("  and gives a buff that says what it is and how long it lasts", no_buff.is_empty(), no_buff)
	check_needs_pack("  and needs no cooking level to eat", gated.is_empty(), gated)
	check_needs_pack("  and a meal with a fish in it heals more than the fish cooked on its own",
		not_more.is_empty(), not_more)

	# THE WORDS. The same as the tooltip's for the same stat on gear, so a meal
	# and an amulet that add the same thing say it the same way.
	var probe := ItemData.new()
	check("an item with no buff and no recipe says nothing about either, and is not bait",
		probe.buff_text() == "" and not probe.is_meal() and probe.bait_rolls == 0
		and probe.buff_kind == ItemData.BuffKind.NONE)
	var worded: Array = []
	for row in [[ItemData.BuffKind.MIGHT, 5, 1200, "+5% damage for 20 min"],
			[ItemData.BuffKind.GUARD, 3, 900, "+3 armour for 15 min"],
			[ItemData.BuffKind.VIGOUR, 25, 600, "+25 max health for 10 min"],
			[ItemData.BuffKind.WISDOM, 12, 90, "+12 max mana for 1 min 30 s"],
			[ItemData.BuffKind.MIGHT, 2, 45, "+2% damage for 45 s"],
			[ItemData.BuffKind.MIGHT, 0, 600, ""],
			[ItemData.BuffKind.GUARD, 4, 0, ""]]:
		var buffed := ItemData.new()
		buffed.buff_kind = row[0]
		buffed.buff_amount = int(row[1])
		buffed.buff_seconds = int(row[2])
		if buffed.buff_text() != String(row[3]):
			worded.append("'%s' for '%s'" % [buffed.buff_text(), row[3]])
	check("  buff_text() reads like the tooltip: \"+5% damage for 20 min\", and nothing for half a buff",
		worded.is_empty(), worded)
	var enum_names: Array = ItemData.BuffKind.keys().map(func(key: Variant) -> String: return String(key))
	check("  and the buff kinds are named in the enum's own order, for the server",
		GameConstants.BUFF_KINDS == enum_names, [GameConstants.BUFF_KINDS, enum_names])

	# ---- bait ------------------------------------------------------------------
	var worm: ItemData = ItemRegistry.get_item("fishingworm") if ItemRegistry.has_item("fishingworm") else null
	var weak_bait: Array = []
	for id in LARDER_BAITS:
		var bait: ItemData = ItemRegistry.get_item(id) if ItemRegistry.has_item(id) else null
		if bait == null or bait.bait_rolls != int(LARDER_BAITS[id]) or worm == null \
				or bait.bait_rolls <= worm.bait_rolls:
			weak_bait.append("%s: %s" % [id, str(bait.bait_rolls) if bait != null else "missing"])
	check_needs_pack("the worm is bait that rolls once", worm != null and worm.bait_rolls == 1,
		str(worm.bait_rolls) if worm != null else "no worm")
	check_needs_pack("  and the lugworm and the glowgrub roll more than the worm: 2 and 3",
		weak_bait.is_empty(), weak_bait)

	# ---- and nothing older changed meaning -------------------------------------
	# The new fields default to "not a meal, no buff, not bait", so every item
	# that existed before them is exactly what it was. Only the worm gained one.
	var changed: Array = []
	for item in all_items:
		if expected.has(item.item_id):
			continue
		if item.is_meal() or item.buff_kind != ItemData.BuffKind.NONE or item.buff_amount != 0 \
				or item.buff_seconds != 0 or (item.bait_rolls != 0 and item.item_id != "fishingworm"):
			changed.append(item.item_id)
	check_needs_pack("no item from before the larder is a meal, carries a buff, or is bait but the worm",
		all_items.size() > expected.size() and changed.is_empty(), changed)
	check("  and a monster with no material_drops in its .tres drops none",
		EnemyData.new().material_drops.is_empty())


func _test_monsters_drop_what_fits_them() -> void:
	section("LARDER - monsters drop materials that fit them, each a real item at a sane chance (0.74.0)")

	# READ AGAINST THE EXPORT, which needs no art: a material drop is only an id
	# and three numbers, and gamedata.json is what the server rolls them from.
	var rows: Dictionary = {}
	for row in _load_gamedata().get("items", []):
		if row is Dictionary:
			rows[String(row.get("item_id", ""))] = row
	check("gamedata.json lists the items to check against", not rows.is_empty(),
		"re-run src/tools/exportgamedata.gd")

	var bad: Array = []
	var loot: Array = []
	var eyes_from: Dictionary = {}
	var droppers: int = 0
	var entries: int = 0
	var dir := DirAccess.open("res://data/enemies")
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var enemy: EnemyData = load("res://data/enemies/" + file) as EnemyData
		if enemy == null:
			continue
		if not enemy.material_drops.is_empty():
			droppers += 1
		for entry in enemy.material_drops:
			entries += 1
			var keys: Array = entry.keys()
			keys.sort()
			var item_id: String = String(entry.get("item_id", ""))
			var chance: Variant = entry.get("chance", 0.0)
			var low: Variant = entry.get("min", 0)
			var high: Variant = entry.get("max", 0)
			if keys != ["chance", "item_id", "max", "min"]:
				bad.append("%s: keys %s" % [enemy.enemy_id, str(keys)])
			if not rows.has(item_id):
				bad.append("%s drops '%s', which is no item" % [enemy.enemy_id, item_id])
			elif bool(rows[item_id].get("droppable", true)) \
					or (ItemRegistry.has_item(item_id) and ItemRegistry.get_item(item_id).droppable):
				loot.append(item_id)
			if typeof(chance) != TYPE_FLOAT or float(chance) <= 0.0 or float(chance) > 1.0:
				bad.append("%s drops %s at chance %s" % [enemy.enemy_id, item_id, str(chance)])
			if typeof(low) != TYPE_INT or typeof(high) != TYPE_INT or int(low) < 1 or int(high) < int(low):
				bad.append("%s drops %s-%s of %s" % [enemy.enemy_id, str(low), str(high), item_id])
			if item_id.ends_with("beholdereye"):
				var droppers_of_eye: Array = eyes_from.get(item_id, [])
				droppers_of_eye.append([enemy.enemy_id, float(chance)])
				eyes_from[item_id] = droppers_of_eye
	check("monsters drop materials at all", droppers > 0 and entries > 0, "%d monsters, %d drops" % [droppers, entries])
	check("  every drop names a real item, at a chance above 0 and at most 1, of at least one and min <= max",
		bad.is_empty(), bad)
	check("  and none of them is in the generic loot pool - it falls from the monster it fits, nowhere else",
		loot.is_empty(), loot)
	var eyes_wrong: Array = []
	for boss_id in LARDER_EYES:
		var eye: String = String(LARDER_EYES[boss_id])
		var dropped_by: Array = eyes_from.get(eye, [])
		if dropped_by.size() != 1 or String(dropped_by[0][0]) != String(boss_id) \
				or not is_equal_approx(float(dropped_by[0][1]), 1.0):
			eyes_wrong.append("%s: %s" % [eye, str(dropped_by)])
	check("each Beholder drops its own eye every time, and no other monster drops one",
		eyes_wrong.is_empty() and eyes_from.size() == LARDER_EYES.size(), eyes_wrong)


func _test_the_store_sells_the_larder() -> void:
	section("LARDER - the general store sells every staple and bait at its value, on shelves of their own (0.74.0)")
	var store: ShopData = load("res://data/shops/generalstore.tres") as ShopData
	check("generalstore.tres loads", store != null)
	if store == null:
		return
	var stock: Array[String] = store.stock
	var wanted: Array = LARDER_STAPLES + LARDER_BAITS.keys()
	var unsold: Array = wanted.filter(func(id: String) -> bool: return not stock.has(id))
	check("the store sells all ten staples and both baits", unsold.is_empty(), unsold)
	# After the fishing items, so the shelves still run potions, fishing, then
	# the gear by tier - the order _test_the_store_sells_the_next_set holds.
	var last_rod: int = stock.find("amethystfishingrod")
	var first_gear: int = stock.find("ironsword")
	var misplaced: Array = wanted.filter(func(id: String) -> bool:
		return stock.find(id) <= last_rod or stock.find(id) >= first_gear)
	check("  placed after the fishing items and before the gear", last_rod >= 0 and misplaced.is_empty(), misplaced)

	# AT ITS VALUE: the till charges value x price_multiplier (and the server's
	# live multiplier on top), and the server reads the value from the export.
	var rows: Dictionary = {}
	for row in _load_gamedata().get("items", []):
		if row is Dictionary:
			rows[String(row.get("item_id", ""))] = row
	var mispriced: Array = []
	for id in wanted:
		var row: Dictionary = rows.get(id, {})
		var own: int = ItemRegistry.get_item(id).value if ItemRegistry.has_item(id) else -1
		if int(row.get("value", -2)) != own or own <= 0:
			mispriced.append("%s: .tres %d, export %s" % [id, own, str(row.get("value", "none"))])
	check("  at its value", is_equal_approx(store.price_multiplier, 1.0), store.price_multiplier)
	check_needs_pack("  and gamedata.json says the same value as each .tres", mispriced.is_empty(), mispriced)

	# THE SHELVES: bait with the rods, staples on a cooking shelf of their own.
	# Before that shelf existed the staples fell to "supplies" AFTER the fishing
	# shelf and the panel opened a second "Potions and supplies" heading.
	var panel_script: GDScript = load("res://src/ui/shop/shopinventory.gd") as GDScript
	var shelved_wrong: Array = []
	for id in LARDER_BAITS:
		if panel_script.shelf_of(rows.get(id, {"item_id": id})) != "fishing":
			shelved_wrong.append(id)
	for id in LARDER_STAPLES:
		if panel_script.shelf_of(rows.get(id, {"item_id": id})) != "cooking":
			shelved_wrong.append(id)
	check("  the baits sit on the fishing shelf and the staples on the cooking shelf", shelved_wrong.is_empty(),
		shelved_wrong)
	# The server's catalogue rows carry no bait_rolls; the registry answers.
	var server_row: Dictionary = {"item_id": "glowgrub", "type_name": "MATERIAL", "tier": 3}
	check_needs_pack("  and a bait is on the fishing shelf from the server's row too, which has no bait_rolls",
		panel_script.shelf_of(server_row) == "fishing", panel_script.shelf_of(server_row))


func _test_the_export_carries_the_larder() -> void:
	section("LARDER - gamedata.json carries the recipes, buffs, bait, drops and the smith's numbers (0.74.0)")
	var data: Dictionary = _load_gamedata()
	check("data/gamedata.json still parses, at schema 1", not data.is_empty() and int(data.get("schema", 0)) == 1,
		"re-run src/tools/exportgamedata.gd")
	if data.is_empty():
		return

	# EVERY ROW HAS THE NEW FIELDS, a non-meal with its empty answers, so the
	# server reads them without asking what it is holding first.
	var rows: Dictionary = {}
	var shapeless: Array = []
	for row in data.get("items", []):
		if not (row is Dictionary):
			continue
		var item_id: String = String(row.get("item_id", ""))
		rows[item_id] = row
		if typeof(row.get("bait_rolls")) != TYPE_FLOAT or typeof(row.get("buff_kind")) != TYPE_FLOAT \
				or typeof(row.get("buff_kind_name")) != TYPE_STRING or typeof(row.get("buff_amount")) != TYPE_FLOAT \
				or typeof(row.get("buff_seconds")) != TYPE_FLOAT or typeof(row.get("recipe")) != TYPE_DICTIONARY:
			shapeless.append(item_id)
	check("every item row carries bait_rolls, buff_kind, buff_kind_name, buff_amount, buff_seconds and recipe",
		not rows.is_empty() and shapeless.is_empty(), shapeless.slice(0, 8))
	var missing_rows: Array = _larder_expected().keys().filter(func(id: String) -> bool: return not rows.has(id))
	check("  and all 67 larder items are in it", missing_rows.is_empty(), missing_rows)

	# A MEAL'S ROW IS ITS .tres: the ingredients sorted by id, the three numbers,
	# and the buff by number and by name.
	var disagree: Array = []
	for id in LARDER_MEALS:
		if not ItemRegistry.has_item(id) or not rows.has(id):
			continue
		var meal: ItemData = ItemRegistry.get_item(id)
		var want_ingredients: Array = []
		var ingredient_ids: Array = meal.recipe_ingredients.keys()
		ingredient_ids.sort()
		for ingredient in ingredient_ids:
			want_ingredients.append({"item_id": String(ingredient), "quantity": int(meal.recipe_ingredients[ingredient])})
		var want: Dictionary = {"recipe": {"ingredients": want_ingredients, "level": meal.recipe_level,
				"xp": meal.recipe_xp, "mastery_level": meal.recipe_mastery_level},
			"buff_kind": int(meal.buff_kind), "buff_kind_name": GameConstants.BUFF_KINDS[int(meal.buff_kind)],
			"buff_amount": meal.buff_amount, "buff_seconds": meal.buff_seconds, "bait_rolls": 0,
			"restore_amount": meal.restore_amount}
		for key in want:
			if _larder_canonical(rows[id].get(key)) != _larder_canonical(want[key]):
				disagree.append("%s.%s" % [id, key])
	for id in ["fishingworm"] + LARDER_BAITS.keys():
		if ItemRegistry.has_item(id) and int(rows.get(id, {}).get("bait_rolls", -1)) != ItemRegistry.get_item(id).bait_rolls:
			disagree.append("%s.bait_rolls" % id)
	check_needs_pack("  each meal's recipe and buff, and each bait's rolls, are its .tres's (re-run the exporter if not)",
		disagree.is_empty(), disagree)

	# THE DROPS, row for row against the .tres files.
	var enemy_rows: Dictionary = {}
	for row in data.get("enemies", []):
		if row is Dictionary:
			enemy_rows[String(row.get("enemy_id", ""))] = row
	var stale_drops: Array = []
	var dir := DirAccess.open("res://data/enemies")
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var enemy: EnemyData = load("res://data/enemies/" + file) as EnemyData
		if enemy == null:
			continue
		var row: Dictionary = enemy_rows.get(enemy.enemy_id, {})
		if not row.has("material_drops") or _larder_canonical(row["material_drops"]) != _larder_canonical(enemy.material_drops):
			stale_drops.append(enemy.enemy_id)
	check("  every enemy row carries its material_drops, [] for none, as its .tres has them",
		not enemy_rows.is_empty() and stale_drops.is_empty(), stale_drops)

	# THE SMITH'S NUMBERS, exactly as GameConstants has them.
	var consts: Dictionary = data.get("constants", {})
	var unlike: Array = []
	for pair in [["temper_step", GameConstants.TEMPER_STEP], ["temper_cap", GameConstants.TEMPER_CAP],
			["temper_gold_rate", GameConstants.TEMPER_GOLD_RATE], ["temper_costs", GameConstants.TEMPER_COSTS],
			["certifications", GameConstants.CERTIFICATIONS], ["patron_titles", GameConstants.PATRON_TITLES],
			["donation_minimum", GameConstants.DONATION_MINIMUM], ["buff_kinds", GameConstants.BUFF_KINDS]]:
		if not consts.has(pair[0]) or _larder_canonical(consts[pair[0]]) != _larder_canonical(pair[1]):
			unlike.append(pair[0])
	check("  and constants carry the smith, the certificates, the patrons and the buff kinds as GameConstants has them",
		unlike.is_empty(), unlike)
	var exporter: String = FileAccess.get_file_as_string("res://src/tools/exportgamedata.gd")
	var unwritten: Array = ["bait_rolls", "buff_kind", "buff_kind_name", "buff_amount", "buff_seconds", "recipe",
		"material_drops", "temper_step", "temper_cap", "temper_gold_rate", "temper_costs", "certifications",
		"patron_titles", "donation_minimum", "buff_kinds"].filter(
			func(key: String) -> bool: return not exporter.contains("\"%s\":" % key))
	check("  because the exporter writes every one of them", unwritten.is_empty(), unwritten)

	# AND THE NUMBERS MAKE SENSE TOGETHER. Tempering stops short of a Perfect;
	# every material a temper or a certificate takes is a real item; and the
	# rank a tier needs is the lowest rank that reaches it.
	check("tempering is capped below a Perfect, so a Perfect is only ever found",
		GameConstants.TEMPER_STEP >= 1 and GameConstants.TEMPER_CAP > 100
		and GameConstants.TEMPER_CAP < GameConstants.QUALITY_PERFECT, GameConstants.TEMPER_CAP)
	var unknown: Array = []
	var ladder: Array = []
	for cost in GameConstants.TEMPER_COSTS:
		for material in cost["materials"]:
			if not rows.has(String(material["item_id"])):
				unknown.append(material["item_id"])
		var needs: int = int(cost["certification"])
		var reaches: int = 2
		if needs > 0:
			reaches = int(GameConstants.CERTIFICATIONS[needs - 1]["max_tier"])
		var below: int = 0 if needs <= 1 else int(GameConstants.CERTIFICATIONS[needs - 2]["max_tier"])
		if int(cost["tier"]) > reaches or (needs > 0 and int(cost["tier"]) <= below):
			ladder.append("tier %d needs rank %d" % [int(cost["tier"]), needs])
	for cert in GameConstants.CERTIFICATIONS:
		for material in cert["materials"]:
			if not rows.has(String(material["item_id"])):
				unknown.append(material["item_id"])
	check("  every temper and certificate takes real items", unknown.is_empty(), unknown)
	check("  and each tier needs the lowest rank that reaches it", ladder.is_empty(), ladder)
	var royal: Array = (GameConstants.CERTIFICATIONS[-1]["materials"] as Array).map(
		func(material: Dictionary) -> String: return String(material["item_id"]))
	check("  the Royal Smith asks for one eye of every Beholder",
		LARDER_EYES.values().all(func(eye: String) -> bool: return royal.has(eye)), royal)


func _test_a_broken_map_is_mended_once() -> void:
	section("WORLD MAP - a saved map that cannot be read is replaced in the save, so it warns once and not at every login (0.73.1)")
	var kept_seen: Dictionary = WorldMap._seen.duplicate(true)
	var kept_terrain: Dictionary = WorldMap._terrain.duplicate(true)
	var kept_cache: Dictionary = WorldMap._save_cache.duplicate(true)
	var kept_dirty: bool = WorldMap._save_dirty
	var kept_pending: bool = WorldMap._revision_pending
	var kept_dropped: PackedStringArray = WorldMap._dropped_on_load.duplicate()
	const GOOD := "zz_mendgood"
	const BROKEN := "zz_mendbroken"
	var bits_of := func(count: int) -> String:
		var raw := PackedByteArray()
		raw.resize(count)
		raw.fill(255)
		return Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))
	# 12 x 10 tiles is 15 bytes of bits. The broken map says 20 x 10 (25 bytes)
	# round 15 bytes - what the saves written before 0.68.1 can hold.
	var good := {"w": 12, "h": 10, "ox": 0, "oy": 0, "bits": bits_of.call(15)}
	var broken := {"w": 20, "h": 10, "ox": 0, "oy": 0, "bits": bits_of.call(15)}
	WorldMap._terrain.erase(GOOD)
	WorldMap._terrain.erase(BROKEN)
	WorldMap._revision_pending = false
	WorldMap.from_save({GOOD: good})
	check("a map that reads is dropped from nothing, and is no change to save",
		WorldMap.dropped_on_load().is_empty() and not WorldMap._revision_pending,
		[WorldMap.dropped_on_load(), WorldMap._revision_pending])
	WorldMap.from_save({GOOD: good, BROKEN: broken})
	check("  one that does not read is named as dropped, and is a change to save",
		Array(WorldMap.dropped_on_load()) == [BROKEN] and WorldMap._revision_pending,
		[WorldMap.dropped_on_load(), WorldMap._revision_pending])

	# The loader mends the save, with a stand-in storage that only counts.
	var store_script := GDScript.new()
	store_script.source_code = "extends SaveStorage\nfunc save(_payload: Dictionary) -> bool:\n\treturn true\n" \
		+ "func requests_before_leaving(_payload: Dictionary) -> Array:\n\treturn []\n"
	store_script.reload()
	var was_storage = CharacterData.storage
	var was_pending: bool = CharacterData._save_pending
	var was_failed: bool = CharacterData.load_failed
	var was_index: int = CharacterData.active_character_index
	var was_slots: Array = CharacterData.character_slots.duplicate()
	CharacterData.storage = store_script.new()
	CharacterData.load_failed = false
	CharacterData._save_pending = false
	CharacterData.active_character_index = 0
	CharacterData.character_slots = [{"name": "Stand-in", "character": "warrior",
		"explored": {GOOD: good, BROKEN: broken}}, null, null, null]
	var fingerprints := ServerStorage.new()
	var seeded: String = JSON.stringify(fingerprints._save_fingerprint(0, CharacterData.character_slots[0]))
	var stand := Node2D.new()
	CharacterData.load_character_state(stand)
	var mended: Dictionary = CharacterData.character_slots[0]
	var map: Dictionary = mended.get("explored", {})
	check("  the loader puts the map as it now is into the slot: the broken one gone, the good one kept",
		map.has(GOOD) and not map.has(BROKEN), map.keys())
	var after: String = JSON.stringify(fingerprints._save_fingerprint(0, mended))
	check("  and saves it - its revision moved, so the push differs from what the server holds",
		CharacterData._save_pending and after != seeded, [CharacterData._save_pending, after == seeded])
	CharacterData._save_pending = false
	CharacterData.load_character_state(stand)
	check("  so the next login reads it clean: nothing dropped, no warning, nothing new to save",
		WorldMap.dropped_on_load().is_empty() and not CharacterData._save_pending,
		[WorldMap.dropped_on_load(), CharacterData._save_pending])
	stand.free()
	CharacterData.storage = was_storage
	CharacterData._save_pending = was_pending
	CharacterData.load_failed = was_failed
	CharacterData.active_character_index = was_index
	CharacterData.character_slots = was_slots
	WorldMap._seen = kept_seen
	WorldMap._terrain = kept_terrain
	WorldMap._save_cache = kept_cache
	WorldMap._save_dirty = kept_dirty
	WorldMap._revision_pending = kept_pending
	WorldMap._dropped_on_load = kept_dropped

func _test_every_area_can_be_walked() -> void:
	section("AREAS - you arrive clear of the doors, the walls hold, every door can be walked to")

	var warrior: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	var feet_node: CollisionShape2D = warrior.get_node_or_null("bodyshape") as CollisionShape2D
	var feet: CircleShape2D = feet_node.shape as CircleShape2D if feet_node != null else null
	check("the player's feet are a circle this can stand in for", feet != null,
		"warrior.tscn bodyshape is not a CircleShape2D any more - the overlap maths below assumes one")
	if feet == null:
		warrior.free()
		return
	var feet_offset: Vector2 = feet_node.position
	var probe := CharacterBody2D.new()
	probe.collision_layer = 0
	probe.collision_mask = (warrior as CollisionObject2D).collision_mask
	var probe_shape := CollisionShape2D.new()
	probe_shape.shape = feet
	probe_shape.position = feet_offset
	probe.add_child(probe_shape)
	warrior.free()

	var walked: Array = []
	var no_map: Array = []
	for area_id in AreaRegistry.area_ids():
		var packed: PackedScene = load(AreaRegistry.AREAS[area_id]) as PackedScene
		if packed == null:
			check("%s loads" % area_id, false)
			continue
		var area: Node = packed.instantiate()
		var report: Dictionary = await _walk_area(area, probe, feet_offset, feet.radius)
		area.free()
		if report.is_empty():
			no_map.append(area_id)
			continue
		walked.append(area_id)

		check("%s: every arrival lands clear of every door" % area_id,
			report.landed_in.is_empty(), "arrives standing in a door: %s" % [report.landed_in])
		check("%s: the walls hold - nowhere a player can walk is off the map" % area_id,
			report.void_spots.is_empty() and not report.escaped,
			"%d spots with no tile under them%s, e.g. %s" % [report.void_spots.size(),
				" and it walked clean off the edge" if report.escaped else "", report.void_spots.slice(0, 4)])
		check("%s: every door can be walked to from where players arrive" % area_id,
			report.unreached.is_empty(), "never reached: %s" % [report.unreached])

	probe.free()
	check("the town, the field, the Big Field, the arena and the boss room were all walked",
		walked.has("elusion") and walked.has("field") and walked.has("bigfield") and walked.has("bossarena")
		and walked.has("boss"), walked)
	print("  walked %s; no map to walk in %s" % [walked, no_map])


func _test_the_credits() -> void:
	section("THE CREDITS - Options > Credits: the art, the sound, the supporters, the engine")
	const Credits := preload("res://src/ui/menus/creditsscreen.gd")

	# ---- the way in -------------------------------------------------------------
	var options: Control = (load("res://scene/ui/menus/optionsscreen.tscn") as PackedScene).instantiate() as Control
	add_child(options)
	await get_tree().process_frame
	var asked: Array = []
	options.credits_requested.connect(func(): asked.append(true))
	var button: Button = options.get_node_or_null("%optionscreditsbutton") as Button
	check("Options has a Credits button", button != null and button.text == "Credits")
	if button != null:
		button.pressed.emit()
	check("  and it asks for the Credits window", asked.size() == 1)
	options.queue_free()
	var hud_code: String = _code_src("res://src/ui/characterhud.gd")
	check("  which the HUD opens, in front of Options",
		hud_code.contains("options_screen.credits_requested.connect(open_credits)")
		and _func_body(hud_code, "func open_credits(").contains("credits_panel.open()")
		and _func_body(hud_code, "func open_credits(").contains("move_to_front()"))

	var screen: Node = (load("res://scene/ui/menus/creditsscreen.tscn") as PackedScene).instantiate()
	add_child(screen)
	await get_tree().process_frame
	screen.open()
	await get_tree().process_frame
	check("it opens on Art", screen.visible and screen.tab == Credits.Tab.ART
		and screen.art_button.button_pressed and not screen.engine_button.button_pressed)
	# 0.21.1: the owner, of AllMind, back as co-owner - "he built my inventory
	# and helped me with ui".
	var byline: Label = screen.get_node_or_null("%bylinelabel") as Label
	check("the byline names the two of them",
		byline != null and byline.text == "Elusion RPG - a game by Robert and AllMind, Elusion Studios",
		byline.text if byline != null else "")

	# ---- Art ------------------------------------------------------------------------
	var art: Array = _credit_texts(screen)
	var links: Dictionary = {}
	for node in screen.page().find_children("*", "LinkButton", true, false):
		links[(node as LinkButton).text] = (node as LinkButton).uri
	check("Ahvassa, linked to his page", links.get("Ahvassa", "") == "https://ahvassa.itch.io/", links)
	check("  Caio Carlos and Clockwork Raven Studios, linked to theirs",
		links.get("Caio Carlos - Clockwork Raven Studios", "") == "https://www.clockworkravenstudios.com/", links)
	check("  each saying what they made", art.any(func(t): return str(t).contains("mythic weapons"))
		and art.any(func(t): return str(t).contains("items and icons")))
	var unfonted: Array = []
	for style in Settings.FONT_STYLES:
		var file: String = str(Settings.FONT_STYLES[style][1])
		if file != "" and not Credits.FONTS.any(func(f): return str(f["file"]) == file):
			unfonted.append(style)
	check("every font Options offers is credited", unfonted.is_empty(), unfonted)
	check("  and the emoji font chat uses",
		Credits.FONTS.any(func(f): return str(f["file"]) == "res://assets/fonts/NotoColorEmoji.ttf"))
	var gone: Array = Credits.FONTS.filter(func(f): return not FileAccess.file_exists(str(f["file"])))
	check("  and every font credited is one the game ships", gone.is_empty(), gone)
	check("  with its copyright line, and the licence they share",
		art.has("Copyright 2011 wmk69 (Wojciech Kalinowski)") and art.has(Credits.FONT_LICENCE))

	var screen_names: Array = []
	for tab in [Credits.Tab.ART, Credits.Tab.AUDIO]:
		screen.show_tab(tab)
		screen_names.append_array(_credit_texts(screen))
	var owners: Array = []
	for folder in LICENSED_ART_FOLDERS:
		var holder: String = str(LICENSED_ART_FOLDERS[folder])
		if not owners.has(holder):
			owners.append(holder)
	var uncredited: Array = []
	for holder in owners:
		if not CREDITED_OWNERS.has(holder):
			uncredited.append("%s: no credit says who" % holder)
			continue
		for who in CREDITED_OWNERS[holder]:
			if not screen_names.has(who):
				uncredited.append("%s: %s" % [holder, who])
	check("every owner of art, sound and type in the game is in the credits", uncredited.is_empty(), uncredited)

	# ---- Audio ------------------------------------------------------------------------
	screen.audio_button.pressed.emit()
	var audio: Array = _credit_texts(screen)
	check("Audio: who recorded the sounds, and on what",
		screen.tab == Credits.Tab.AUDIO and audio.has("Robert - Elusion Studios")
		and audio.any(func(t): return str(t).contains("Stylophone")), audio)

	# ---- Support ------------------------------------------------------------------------
	screen.support_button.pressed.emit()
	var support: Array = _credit_texts(screen)
	var shown: Array = screen.page().get_children().filter(func(n): return n.has_meta("supporter"))
	check("Support: a name for everyone on the list, in its order",
		shown.map(func(n): return str(n.text)) == Array(Credits.SUPPORTERS), shown.size())
	check("  and why the game is free, on the website", screen.page().find_children("*", "LinkButton", true, false)
		.any(func(b): return (b as LinkButton).uri == "https://elusionrpg.com/contribute.html"))
	check("  that the game is free with nothing to buy (0.79.1), and thanks when there are names",
		Credits.support_intro([]).contains("nothing to buy") and not Credits.support_intro([]).contains("cocoa")
		and Credits.support_intro(["Ada"]).contains("Thank you")
		and support.has(Credits.support_intro(Credits.SUPPORTERS)))
	var bad_names: Array = []
	for supporter in Credits.SUPPORTERS:
		if supporter.strip_edges() != supporter or supporter == "" or Credits.SUPPORTERS.count(supporter) > 1:
			bad_names.append(supporter)
	check("  every name on it written once, as it should show", bad_names.is_empty(), bad_names)

	# ---- Engine ------------------------------------------------------------------------
	screen.engine_button.pressed.emit()
	var engine: Array = _credit_texts(screen)
	check("Engine: Godot's licence, read from the engine itself",
		engine.has(Credits.reflow(Engine.get_license_text())) and engine.has("Made with Godot Engine"))
	check("  as paragraphs, not the 80-column lines it comes in",
		Credits.reflow("one\ntwo\n\nthree\r\nfour\n") == "one two\n\nthree four"
		and not Credits.reflow(Engine.get_license_text()).contains("\nEXPRESS OR"))
	var notices: Array = Credits.engine_notices()
	var named: Array = notices.map(func(n): return str(n["name"]))
	check("  and FreeType's, ENet's and Mbed TLS's - all three still in this build of Godot",
		named.has("The FreeType Project") and named.has("ENet") and named.has("Mbed TLS"), named)
	var freetype_line: bool = false
	for line in engine:
		if str(line).begins_with("Portions of this software are copyright © ") \
				and str(line).ends_with("The FreeType Project (www.freetype.org). All rights reserved."):
			freetype_line = true
	check("  FreeType's credit in the words its licence asks for", freetype_line)
	var licence_texts: Dictionary = Engine.get_license_info()
	var unshown: Array = []
	for notice in notices:
		var full: String = Credits.reflow(str(licence_texts.get(str(notice["licence"]), "missing")))
		if not engine.has(full):
			unshown.append(notice["name"])
	check("  each with its licence in full", unshown.is_empty(), unshown)
	var engine_page: Node = screen.page()
	screen.art_button.pressed.emit()
	screen.engine_button.pressed.emit()
	check("a tab is built once: back on Engine is the same page, and the only one showing",
		screen.page() == engine_page and screen.list.get_children().filter(func(n): return n.visible).size() == 1)
	check("  and every other part of Godot named, with its licence",
		engine.has(Credits.engine_components_text())
		and Credits.engine_components_text().split("\n").size() >= Engine.get_copyright_info().size())

	screen.close()
	check("its x closes it", not screen.visible)
	screen.queue_free()

	# WITH NAMES IN IT: the real list starts empty, so a window that never drew
	# a name would pass above.
	var named_screen: Node = (load("res://scene/ui/menus/creditsscreen.tscn") as PackedScene).instantiate()
	add_child(named_screen)
	await get_tree().process_frame
	named_screen.supporters = ["Ada L.", "Jordan"] as Array[String]
	named_screen.open()
	named_screen.support_button.pressed.emit()
	var drawn: Array = named_screen.page().get_children().filter(func(n): return n.has_meta("supporter"))
	check("two supporters are two names, in order, under the thanks",
		drawn.map(func(n): return str(n.text)) == ["Ada L.", "Jordan"]
		and _credit_texts(named_screen).has(Credits.support_intro(["Ada L."])), drawn.size())
	named_screen.queue_free()

	var field: String = _code_src("res://src/world/field.gd")
	print("  the field's welcome %s the old credits page" % ("still carries" if field.contains("ahvassa.itch.io") else "no longer carries"))


func _test_the_welcome_plays_once_a_login() -> void:
	section("THE FIELD'S WELCOME - once a login, not on every arrival")

	check("GameState remembers whether this login has heard it",
		"opening_story_told" in GameState)

	var field: String = FileAccess.get_file_as_string("res://src/world/field.gd")
	var ready_at: int = _first_code_index(field, "func _ready(", 0)
	var ready_end: int = _first_code_index(field, "\nfunc ", ready_at + 1)
	var guard: int = _within(_first_code_index(field, "if GameState.opening_story_told:", ready_at), ready_end)
	var told: int = _within(_first_code_index(field, "GameState.opening_story_told = true", ready_at), ready_end)
	var freeze: int = _within(_first_code_index(field, "_freeze_enemies()", ready_at), ready_end)
	var story: int = _within(_first_code_index(field, "StoryScreen.new()", ready_at), ready_end)
	var skip: int = _within(_first_code_index(field, "return", guard), told) if guard != -1 else -1
	check("the field asks before it plays the welcome",
		guard != -1 and story != -1 and guard < story, "guard at %d, story at %d" % [guard, story])
	check("  and a login that heard it goes no further", skip != -1,
		"nothing returns between the question and the answer")
	check("  and playing it marks it heard",
		told != -1 and guard < told and told < story, "marked at %d" % told)
	check("  and the enemies are frozen only for a welcome that plays",
		freeze != -1 and guard < freeze, "freeze at %d" % freeze)

	var data: String = FileAccess.get_file_as_string("res://src/systems/characterdata.gd")
	var clear_at: int = _first_code_index(data, "func clear_current_user(", 0)
	var clear_end: int = _first_code_index(data, "\nfunc ", clear_at + 1)
	check("every login and logout puts it back",
		_within(_first_code_index(data, "GameState.opening_story_told = false", clear_at), clear_end) != -1)
	var load_at: int = _first_code_index(data, "func load_for_user(", 0)
	var load_end: int = _first_code_index(data, "\nfunc ", load_at + 1)
	check("  and a login runs that reset",
		_within(_first_code_index(data, "clear_current_user()", load_at), load_end) != -1)
	print("  the welcome plays on the first field arrival of a login, and not again until the next")


# =============================================================================
# CHARACTER SELECT - a line about each class, and deleting a character
# =============================================================================
# Both asked for on day 1. Every account has four fixed slots, one per class,
# and there was no way to start a class again; and nothing on the screen said
# what a class is before you picked it.
#
# The screen is instanced but not entered, so its buttons are real and nothing
# is sent anywhere. What needs the server - the delete itself - is the API's
# test_chardelete.py; here are the order of what the game does around it and
# what the player is shown.

func _test_a_character_can_be_deleted() -> void:
	section("CHARACTER SELECT - a line about each class, and Delete that asks first")

	var Select: Script = load("res://src/ui/menus/characterselect.gd") as Script
	for class_id in ["warrior", "mage", "tank", "healer"]:
		var line: String = Select.class_line(class_id)
		check("the %s has a line saying how it plays" % class_id,
			line.length() >= 20 and line.length() <= 64 and not line.contains("\n"), line)
	# Day 1: "mage has pillars that rise from the ground". The line said it
	# dropped stone spikes, which is not what the player watches the spell do.
	check("the mage's line says its pillars rise, as the spell does",
		Select.class_line("mage").begins_with("Pillars") and not Select.class_line("mage").contains("spikes"),
		Select.class_line("mage"))

	var screen: Control = (load("res://scene/ui/menus/characterselect.tscn") as PackedScene).instantiate()
	screen._build_slot_extras()
	screen._build_slot_extras()
	var grid: Node = screen.get_node(screen.GRID_PATH)
	var placed: bool = true
	var once: bool = true
	var narrow: bool = true
	for i in 4:
		var column: Node = grid.get_node("%s/vbox" % screen.SLOT_CLASSES[i])
		var line: Label = screen.class_lines[i]
		placed = placed and line != null and line.get_parent() == column \
			and line.get_index() == column.get_node("classname").get_index() + 1 \
			and line.text == Select.class_line(screen.SLOT_CLASSES[i])
		once = once and column.find_children("classline*", "", false, false).size() == 1
		narrow = narrow and line.custom_minimum_size.x <= 210.0 and line.autowrap_mode != TextServer.AUTOWRAP_OFF
	check("each line is under its class's name", placed)
	check("  built once, and by the screen itself", once
		and _func_body(_code_src("res://src/ui/menus/characterselect.gd"), "func _ready(").contains("_build_slot_extras()"))
	check("  and it wraps inside the panel rather than widening all four", narrow)

	# ---- Delete, where Create was ----
	var kept: Array = CharacterData.character_slots.duplicate(true)
	CharacterData.character_slots = [{"character": "warrior", "level": 12, "gold": 1204}, null, null, null]
	screen.update_slot_labels()
	var buttons: Array = screen.delete_buttons
	check("an occupied slot offers Delete in place of Create",
		buttons[0].visible and not buttons[0].disabled and not screen.get_node("%createbutton1").visible,
		[buttons[0].visible, screen.get_node("%createbutton1").visible])
	check("  an empty one offers Create and no Delete",
		not buttons[1].visible and screen.get_node("%createbutton2").visible)
	var two: bool = true
	for i in 4:
		var shown: int = 0
		for child in buttons[i].get_parent().get_children():
			if child is Button and child.visible:
				shown += 1
		two = two and shown == 2
	check("  and every slot still has two buttons, so the panels keep their width", two)

	# ---- it asks ----
	screen._ask_delete(0)
	check("Delete asks first", screen.confirm_box != null and screen.confirm_box.visible)
	check("  naming the character", screen.confirm_title.text == "Delete your Warrior?", screen.confirm_title.text)
	var body: String = screen.confirm_body.text
	check("  and what goes with it, and what stays",
		body.contains("Level 12") and body.contains("1,204 gold") and body.contains("bank")
		and body.contains("cannot be undone"), body)
	check("  and it wants the name typed", screen.confirm_name.placeholder_text == "Type WARRIOR to delete it"
		and screen.confirm_delete_button.disabled, screen.confirm_name.placeholder_text)
	screen._on_confirm_name_changed("warr")
	var half: bool = screen.confirm_delete_button.disabled
	screen._on_confirm_name_changed("mage")
	var wrong: bool = screen.confirm_delete_button.disabled
	screen._on_confirm_name_changed("  Warrior ")
	check("half the name, or another name, does not arm it; the name in any case does",
		half and wrong and not screen.confirm_delete_button.disabled)
	screen._close_confirm()
	check("Keep it closes the question and forgets the slot",
		not screen.confirm_box.visible and screen._deleting_slot == -1)
	screen._ask_delete(1)
	check("an empty slot is not asked about", not screen.confirm_box.visible)
	screen._entering = true
	screen._ask_delete(0)
	check("  nor anything while the world is loading", not screen.confirm_box.visible)
	screen._entering = false
	check("a character with no gold is not said to have any",
		not screen.delete_warning({"level": 1, "gold": 0}).contains("gold"),
		screen.delete_warning({"level": 1, "gold": 0}))
	CharacterData.character_slots = kept
	screen.free()

	# ---- the order around the request ----
	var confirm: String = _func_body(_code_src("res://src/ui/menus/characterselect.gd"), "func _confirm_delete(")
	var sent: int = confirm.find("await CharacterData.delete_character(")
	var guard: int = confirm.find("if not is_instance_valid(self) or not is_inside_tree():")
	var redrawn: int = confirm.find("update_slot_labels()")
	check("the box sends what was typed, and redraws the slots only if the screen is still there",
		sent != -1 and sent < guard and guard < redrawn, [sent, guard, redrawn])
	check("  and says the server's reason when it refuses", confirm.contains("res.get(\"error\""))
	var data: String = _func_body(_code_src("res://src/systems/characterdata.gd"), "func delete_character(")
	var flushed: int = data.find("await finish_saving()")
	var posted: int = data.find("Api.post(\"/api/character/delete\"")
	var refused: int = data.find("if not res.get(\"ok\", false):")
	var emptied: int = data.find("character_slots[slot_idx] = null")
	var forgot: int = data.find("storage.forget_slot(slot_idx)")
	check("CharacterData saves what is on its way before it asks the server to delete",
		flushed != -1 and flushed < posted, [flushed, posted])
	check("  and empties the slot only once the server said yes",
		posted < refused and refused < emptied and emptied != -1 and forgot > refused, [posted, refused, emptied, forgot])
	var select_src: String = _func_body(_code_src("res://src/ui/menus/characterselect.gd"), "func _select_character(")
	check("a character cannot be picked while a delete is on its way",
		select_src.contains("if _entering or _deleting:"))

	# ---- a new character in the slot is pushed, not skipped ----
	var store := ServerStorage.new()
	for key in ["save:1", "status:1", "save:2", "lusions"]:
		store._last_pushed[key] = "pushed"
	store._failed_keys["status:1"] = true
	store.forget_slot(1)
	check("the storage forgets what it pushed for a deleted slot, so the next character there is sent",
		not store._last_pushed.has("save:1") and not store._last_pushed.has("status:1")
		and not store._failed_keys.has("status:1"),
		store._last_pushed)
	check("  and nothing about the other slots or the account",
		store._last_pushed.has("save:2") and store._last_pushed.has("lusions"))
	check("  by the same names its pushes use",
		ServerStorage._slot_keys(3) == store._slot_sections(3, {"character": "healer"}).map(
			func(part: Array) -> String: return part[0]))

	# ---- a character made again starts whole ----
	# Found by deleting and making a warrior live: the new character was pushed
	# with SAVEABLE_STATS' 100s, the server took that as damage from its 180,
	# and the full bars the game then drew were clamped as an unexplained heal.
	var whole: bool = true
	var seen: Array = []
	for class_id in ["warrior", "mage", "tank", "healer"]:
		var made: Dictionary = (load("res://src/systems/characterdata.gd") as GDScript).new_character(class_id)
		var cls: ClassData = load("res://data/classes/%s.tres" % class_id) as ClassData
		var ok: bool = cls != null and int(made["hp"]) == cls.hp_base and int(made["max_hp"]) == cls.hp_base \
			and int(made["mana"]) == cls.mana_base and int(made["max_mana"]) == cls.mana_base \
			and int(made["stamina"]) == cls.stam_base and int(made["max_stamina"]) == cls.stam_base
		whole = whole and ok
		seen.append("%s %s/%s" % [class_id, made["hp"], made["max_hp"]])
	check("a new character starts on its class's full pools, not a flat 100", whole, seen)
	check("  and Create makes it that way",
		_func_body(_code_src("res://src/systems/characterdata.gd"), "func create_character(")
			.contains("new_character(character_name)"))
	print("  character select: the class lines, Delete in Create's place, the question, and the order")


# =============================================================================
# STAFF LOGINS: ONE CODE PER COMPUTER
# =============================================================================
# A code on every staff login was the owner's own complaint the first day he
# had it. A login that got in with a code is answered with a device token
# (TRUSTED DEVICES in app.py, test_staffcode.py); the game keeps it per account
# and sends it with the next login from this computer.

func _test_one_code_per_computer() -> void:
	section("STAFF LOGINS - the code once per computer, not once per login")

	# The suite's own writes go in a copy it puts back afterwards.
	var kept: String = FileAccess.get_file_as_string(Api.DEVICES_PATH) \
		if FileAccess.file_exists(Api.DEVICES_PATH) else ""
	check("an account never proved on this computer has no device token",
		Api.device_token_for("nobody-proved-this") == "")
	Api._remember_device("  Warden ", "device-abc")
	check("a token kept for an account is found again, whatever case the name is typed in",
		Api.device_token_for("warden") == "device-abc" and Api.device_token_for("WARDEN") == "device-abc")
	Api._remember_device("keeper", "device-xyz")
	check("  each account keeps its own", Api.device_token_for("warden") == "device-abc"
		and Api.device_token_for("keeper") == "device-xyz")
	check("it is kept apart from the session, which Remember me and Log out throw away",
		Api.DEVICES_PATH != Api.SESSION_PATH
		and not _func_body(_code_src("res://src/systems/api.gd"), "func _clear_session(").contains("DEVICES_PATH"))

	var login_src: String = _func_body(_code_src("res://src/systems/api.gd"), "func login(")
	var sent: int = login_src.find("body[\"device\"] = device")
	var posted: int = login_src.find("await post(\"/api/auth/login\", body)")
	var adopted: int = login_src.find("_adopt_session(res.data)")
	var kept_at: int = login_src.find("_remember_device(user,")
	check("the login sends this computer's token with the password",
		sent != -1 and sent < posted, [sent, posted])
	check("  and keeps the one the server hands back, only on a login that got in",
		adopted != -1 and posted < adopted and adopted < kept_at, [posted, adopted, kept_at])

	if kept == "":
		DirAccess.remove_absolute(Api.DEVICES_PATH)
	else:
		var file := FileAccess.open(Api.DEVICES_PATH, FileAccess.WRITE)
		file.store_string(kept)
		file.close()
	print("  staff logins: a device token per account, apart from the session, sent and kept")


# =============================================================================
# THIS COPY OF THE GAME - the install id a ban follows through a VPN
# =============================================================================
# The server refuses a new account from a computer a banned account has used
# (INSTALL IDS in app.py, test_security.py E-5f). That only works if the game
# makes the id once, keeps it where logging out cannot reach it, and sends it
# on every way in.

func _test_install_id_is_kept_and_sent() -> void:
	section("INSTALL ID - one per computer, kept, sent on every way in")

	# The suite's own writes go in a copy it puts back afterwards.
	var kept: String = FileAccess.get_file_as_string(Api.INSTALL_PATH) \
		if FileAccess.file_exists(Api.INSTALL_PATH) else ""
	var was_cached: String = Api._install_id

	DirAccess.remove_absolute(Api.INSTALL_PATH)
	Api._install_id = ""
	var first: String = Api.install_id()
	check("a computer with no id is given one: 64 hex characters",
		first.length() == 64 and first.is_valid_hex_number(), first)
	check("  asking again gives the same one", Api.install_id() == first)
	Api._install_id = ""
	check("  and it comes back from the file after a restart", Api.install_id() == first)
	# On the script, not the autoload: it is static (STATIC_CALLED_ON_INSTANCE).
	var api_script: GDScript = load("res://src/systems/api.gd") as GDScript
	check("  each new computer gets its own", str(api_script.call("_fresh_install_id")) != first)

	var junk := ConfigFile.new()
	junk.set_value("install", "id", "not an id")
	junk.save(Api.INSTALL_PATH)
	Api._install_id = ""
	var mended: String = Api.install_id()
	check("a damaged file is replaced, not sent", mended != "not an id"
		and mended.length() == 64 and mended.is_valid_hex_number(), mended)

	var api_src: String = _code_src("res://src/systems/api.gd")
	check("it lives apart from the session, which Log out and Remember me throw away",
		Api.INSTALL_PATH != Api.SESSION_PATH and Api.INSTALL_PATH != Api.DEVICES_PATH
		and not _func_body(api_src, "func _clear_session(").contains("INSTALL_PATH"))
	check("the login sends it",
		_func_body(api_src, "func login(").contains("\"install\": install_id()"))
	check("  so does registering - the request the ban actually refuses",
		_func_body(api_src, "func register(").contains("\"install\": install_id()"))
	check("  and resuming a remembered login",
		_func_body(api_src, "func probe_and_resume(").contains(
			"post(\"/api/auth/resume\", {\"install\": install_id()}"))

	# The staff view says how two accounts are linked; "same computer" is the
	# half a VPN does not change, so it has to read as such.
	const OwnerPanelScript := preload("res://src/ui/owner/ownerpanel.gd")
	check("the staff view names a shared computer",
		OwnerPanelScript.linked_how({"shared_computers": 1}) == "same computer")
	check("  beside the addresses when there are both",
		OwnerPanelScript.linked_how({"shared_addresses": 2, "quietest_address_accounts": 3,
			"shared_computers": 1}) == "shares 2 addresses, quietest holds 3, same computer")
	check("  and how crowded the computer is, when it is",
		OwnerPanelScript.linked_how({"shared_computers": 1, "quietest_computer_accounts": 9})
			== "same computer, 9 accounts on it")
	check("  and an address-only link reads as it always did",
		OwnerPanelScript.linked_how({"shared_addresses": 1, "quietest_address_accounts": 2})
			== "shares 1 address, quietest holds 2")

	if kept == "":
		DirAccess.remove_absolute(Api.INSTALL_PATH)
	else:
		var file := FileAccess.open(Api.INSTALL_PATH, FileAccess.WRITE)
		file.store_string(kept)
		file.close()
	Api._install_id = was_cached
	print("  install id: made once, kept apart from the session, sent with login, register and resume")


# =============================================================================
# STAFF PANEL - what it offers each rank, and how a kick reaches a player
# =============================================================================
# The server decides every one of these; the panel only declines to offer what
# would be refused. So the failure worth guarding is the panel drifting from
# app.py - offering a mod a permanent ban, or hiding a demotion the owner is
# allowed - which looks like a broken button either way. The rules are pure
# static functions on staffpanel.gd precisely so they can be pinned here
# without a server. The live run - real panel, real app.py, every button
# pressed - is in the commit that added this.

# 0.7.6. The owner, 7 Oct: "the game runs really rough on my screen but only
# this screen not my other 2 ... we might have to add more to the settings menu
# to really be user friendly". Three screens - 180, 100 and 59.94 Hz - and the
# game rough only on the 59.94 Hz one. MONITORS AND WINDOW MODES in
# settings.gd. A headless run has no desktop, so what moves windows is checked
# through the pieces that decide where, and the parts that touch a window by
# reading them.
func _test_monitors_and_window_modes() -> void:
	section("DISPLAY - window mode, monitor, where it was, and Match screen")
	const SettingsScript := preload("res://src/systems/settings.gd")
	const Options := preload("res://src/ui/menus/optionsscreen.gd")

	# --- the window mode --------------------------------------------------------
	check("three modes: windowed, borderless, exclusive",
		Settings.WINDOW_MODES == ["windowed", "borderless", "exclusive"], Settings.WINDOW_MODES)
	check("  each the engine's own mode",
		SettingsScript.window_mode_for("windowed") == DisplayServer.WINDOW_MODE_WINDOWED
		and SettingsScript.window_mode_for("borderless") == DisplayServer.WINDOW_MODE_FULLSCREEN
		and SettingsScript.window_mode_for("exclusive") == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	check("windowed is the default, as before",
		Settings.DEFAULTS["window_mode"] == "windowed" and not Settings.DEFAULTS.has("fullscreen"))
	check("an old fullscreen=true means borderless, which is what it was",
		SettingsScript.normalise_window_mode(true) == "borderless"
		and SettingsScript.normalise_window_mode(false) == "windowed")
	check("  case does not matter, and nonsense is windowed",
		SettingsScript.normalise_window_mode("Exclusive") == "exclusive"
		and SettingsScript.normalise_window_mode("banana") == "windowed")
	var old_file := ConfigFile.new()
	old_file.set_value(SettingsScript.SECTION, "fullscreen", true)
	var new_file := ConfigFile.new()
	new_file.set_value(SettingsScript.SECTION, "fullscreen", true)
	new_file.set_value(SettingsScript.SECTION, "window_mode", "exclusive")
	check("an options.cfg from before 0.7.6 comes up borderless",
		SettingsScript.stored_value(old_file, "window_mode") == "borderless"
		and SettingsScript.stored_value(ConfigFile.new(), "window_mode") == "windowed")
	check("  and a file that has a mode is read as it says",
		SettingsScript.stored_value(new_file, "window_mode") == "exclusive")
	check("the screen comes before the mode, so a window is on its screen before it fills it",
		Settings.DEFAULTS.keys().find("screen") < Settings.DEFAULTS.keys().find("window_mode"))
	var settings_src: String = _code_only(FileAccess.get_file_as_string("res://src/systems/settings.gd"))
	var to_mode: String = _func_body(settings_src, "func _apply_window_mode(")
	check("a browser has one fullscreen: exclusive is borderless there",
		to_mode.contains("OS.has_feature(\"web\")") and to_mode.contains("WINDOW_MODE_FULLSCREEN"))
	check("  and one fullscreen to the other goes by way of a window",
		to_mode.contains("window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)"))

	# --- which screen -------------------------------------------------------------
	check("no screen is chosen by default - nothing moves a window nobody placed",
		Settings.DEFAULTS["screen"] == -1 and Settings.DEFAULTS["window_x"] == -1
		and Settings.DEFAULTS["window_y"] == -1)
	var samsung := {"index": 1, "size": Vector2i(1920, 1080), "hz": 59.94, "primary": false}
	var ultragear := {"index": 0, "size": Vector2i(1920, 1080), "hz": 180.0, "primary": true}
	var ultrawide := {"index": 2, "size": Vector2i(3440, 1440), "hz": 100.0, "primary": false}
	check("a screen is named by its size and rate, rounded",
		SettingsScript.screen_label(samsung) == "1920 x 1080, 60 Hz", SettingsScript.screen_label(samsung))
	check("  and the main one says so",
		SettingsScript.screen_label(ultragear) == "1920 x 1080, 180 Hz (main)", SettingsScript.screen_label(ultragear))
	check("  and one that cannot say its rate gives only its size",
		SettingsScript.screen_label({"size": Vector2i(1280, 720), "hz": -1.0}) == "1280 x 720")
	var move: String = _func_body(settings_src, "func _apply_screen(")
	check("a window is moved only when it is somewhere else, and never to a screen that is gone",
		move.contains("window_get_current_screen() == want") and move.contains("want >= DisplayServer.get_screen_count()"))
	var leave_at: int = move.find("window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)")
	check("  out of fullscreen to move, and back in on the other screen",
		leave_at >= 0 and leave_at < move.find("window_set_current_screen(want)")
		and move.contains("DisplayServer.window_set_mode(mode)"))
	check("  and a window too big for the new screen is brought down to fit",
		move.contains("set_value(\"window_width\"") and move.contains("_center_window()"))

	# --- where it was ---------------------------------------------------------
	var kept: Dictionary = {}
	for key in ["screen", "window_x", "window_y"]:
		kept[key] = Settings.get_value(key)
	Settings._window_watch_at = Vector2i(-1, -1)
	Settings.note_window_place(2, Vector2i(300, 120), true)
	check("a window still being dragged is not remembered yet",
		Settings.get_value("screen") == kept["screen"] and Settings.get_value("window_x") == kept["window_x"])
	Settings.note_window_place(2, Vector2i(300, 120), true)
	check("one that has held still is: its screen, and its spot on that screen",
		Settings.get_value("screen") == 2 and Settings.get_value("window_x") == 300
		and Settings.get_value("window_y") == 120,
		[Settings.get_value("screen"), Settings.get_value("window_x"), Settings.get_value("window_y")])
	Settings.note_window_place(1, Vector2i(-40, 10), true)
	Settings.note_window_place(1, Vector2i(-40, 10), true)
	check("  hanging off a screen's edge, the screen is kept and the spot is not - it opens centred",
		Settings.get_value("screen") == 1 and Settings.get_value("window_x") == -1
		and Settings.get_value("window_y") == -1)
	Settings.note_window_place(0, Vector2i(0, 0), false)
	Settings.note_window_place(0, Vector2i(0, 0), false)
	check("  fullscreen on another screen is that screen, and no spot",
		Settings.get_value("screen") == 0 and Settings.get_value("window_x") == -1)
	for key in kept:
		Settings.set_value(key, kept[key])
	check("the game never writes override.cfg from the editor or the suite",
		not Settings._writes_display_override())

	var none: Dictionary = SettingsScript.display_override("windowed", -1, Vector2i(-1, -1), Vector2i.ZERO, 3)
	check("nobody placed it: override.cfg says nothing about the window",
		none.size() == SettingsScript.DISPLAY_OVERRIDE_KEYS.size() and none.values().all(func(v): return v == null))
	var gone: Dictionary = SettingsScript.display_override("exclusive", 5, Vector2i(10, 10), Vector2i.ZERO, 3)
	check("  nor when the remembered screen is not plugged in any more",
		gone.values().all(func(v): return v == null))
	var full: Dictionary = SettingsScript.display_override("exclusive", 1, Vector2i(-1, -1), Vector2i(1920, 0), 3)
	check("exclusive on the Samsung: the next launch starts there, in that mode, centred",
		full["window/size/mode"] == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		and full["window/size/initial_screen"] == 1
		and full["window/size/initial_position_type"] == 3 and full["window/size/initial_position"] == null, full)
	var full_spot: Dictionary = SettingsScript.display_override("borderless", 1, Vector2i(40, 30), Vector2i(1920, 0), 3)
	check("  a fullscreen window fills its screen, whatever spot its window had",
		full_spot["window/size/initial_position_type"] == 3 and full_spot["window/size/initial_position"] == null,
		full_spot)
	var left: Dictionary = SettingsScript.display_override("windowed", 2, Vector2i(100, 50), Vector2i(-3440, 0), 3)
	check("  a window on a screen left of the main one starts at its spot, in desktop pixels",
		left["window/size/mode"] == DisplayServer.WINDOW_MODE_WINDOWED
		and left["window/size/initial_position_type"] == 0
		and left["window/size/initial_position"] == Vector2i(-3340, 50), left)
	# THE FILE ITSELF, written for real - to a file of the suite's own, never
	# to the project's override.cfg.
	var probe_path := "user://suite_override_probe.cfg"
	var before := ConfigFile.new()
	before.set_value("rendering", "renderer/rendering_method", "gl_compatibility")
	before.set_value("display", "window/size/initial_position", Vector2i(5, 5))
	before.save(probe_path)
	var errors_seen := EngineErrorCounter.new()
	OS.add_logger(errors_seen)
	SettingsScript.write_display_override_to(probe_path, full)
	OS.remove_logger(errors_seen)
	check("  writing keys the file did not have yet logs no engine error",
		errors_seen.count == 0, "%d: %s" % [errors_seen.count, "; ".join(errors_seen.where)])
	var after := ConfigFile.new()
	after.load(probe_path)
	check("written to override.cfg: the mode, the screen and how to place it",
		after.get_value("display", "window/size/mode", -9) == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		and after.get_value("display", "window/size/initial_screen", -9) == 1
		and after.get_value("display", "window/size/initial_position_type", -9) == 3)
	check("  an old spot it no longer wants is erased",
		not after.has_section_key("display", "window/size/initial_position"))
	check("  and the renderer the player chose is left exactly as it was",
		after.get_value("rendering", "renderer/rendering_method", "") == "gl_compatibility")
	SettingsScript.write_display_override_to(probe_path, none)
	after = ConfigFile.new()
	after.load(probe_path)
	check("  reset, every key it owns goes, and still only those",
		not after.has_section("display")
		and after.get_value("rendering", "renderer/rendering_method", "") == "gl_compatibility")
	DirAccess.remove_absolute(probe_path)
	SettingsScript.write_display_override_to(probe_path, none)
	check("  and nothing to say writes no file at all", not FileAccess.file_exists(probe_path))
	var rescue: String = _func_body(settings_src, "func _rescue_offscreen_window(")
	check("a window that opens on no screen is brought to the middle of the main one",
		rescue.contains("get_primary_screen()") and rescue.contains("_center_window()"))

	# --- Match screen ------------------------------------------------------------------
	check("Match screen is offered second, after Unlimited",
		Settings.FRAME_CAPS[1] == Settings.FRAME_CAP_MATCH and Settings.FRAME_CAP_MATCH == -1)
	check("  and survives being read back, where any other negative is no cap",
		SettingsScript.normalise_frame_cap(-1) == -1 and SettingsScript.normalise_frame_cap(-5) == 0)
	check("it is the screen's own rate, rounded: 60 on the Samsung, 100 on the ultrawide",
		SettingsScript.fps_cap_for(-1, true, true, 59.94) == 60
		and SettingsScript.fps_cap_for(-1, true, true, 100.0) == 100)
	check("  no cap when the screen cannot say its rate",
		SettingsScript.fps_cap_for(-1, true, true, -1.0) == 0)
	check("  and the background limit still wins in the background",
		SettingsScript.fps_cap_for(-1, false, true, 180.0) == Settings.BACKGROUND_FPS)
	var watch: String = _func_body(settings_src, "func _watch_window(")
	check("moving to another screen works the cap out again",
		watch.contains("_apply_fps_cap()") and watch.contains("here != _window_watch_screen"))
	check("the picker names the number it is on this screen",
		Options.frame_cap_label(-1, 59.94) == "Match screen (60)"
		and Options.frame_cap_label(-1, -1.0) == "Match screen"
		and Options.frame_cap_label(0, 60.0) == "Unlimited" and Options.frame_cap_label(144, 60.0) == "144 fps")

	# --- the readout says which screen is timing the game ------------------------
	var others := [180.0, 100.0]
	check("100 fps on the 59.94 Hz screen beside a 100 Hz one: timed by the 100",
		SettingsScript.timed_by_screen(59.94, 100.0, "on", 0, others) == 100.0)
	check("  180 fps there: timed by the 180",
		SettingsScript.timed_by_screen(59.94, 179.0, "on", 0, others) == 180.0)
	check("  60 fps there is in step - nothing to say",
		SettingsScript.timed_by_screen(59.94, 60.0, "on", 0, others) == 0.0)
	check("  2400 fps is a driver ignoring V-Sync, not another screen",
		SettingsScript.timed_by_screen(59.94, 2400.0, "on", 0, others) == 0.0)
	check("  V-Sync off or Fast draw freely on purpose",
		SettingsScript.timed_by_screen(59.94, 100.0, "off", 0, [100.0]) == 0.0
		and SettingsScript.timed_by_screen(59.94, 100.0, "fast", 0, [100.0]) == 0.0)
	check("  and a cap at this screen's rate is already the cure",
		SettingsScript.timed_by_screen(59.94, 100.0, "on", 60, [100.0]) == 0.0)
	check("  a faster screen paced by a faster one still: 180 fps on the 100 Hz",
		SettingsScript.timed_by_screen(100.0, 180.0, "on", 0, [180.0, 59.94]) == 180.0)
	var timed_hint: String = Options.pacing_hint_for({"refresh": 59.94, "fps": 100.0, "vsync": "on",
		"cap": 0, "overridden": false, "timed_by": 100.0})
	check("the hint names both screens and the two cures",
		timed_hint.contains("This screen is 60 Hz") and timed_hint.contains("your 100 Hz screen")
		and timed_hint.contains("Exclusive fullscreen") and timed_hint.contains("Match screen"), timed_hint)
	check("  a driver override still gets its own words",
		Options.pacing_hint_for({"refresh": 60.0, "fps": 2400.0, "overridden": true, "timed_by": 0.0}).contains("overriding V-Sync"))
	check("  and a screen in step gets no hint at all",
		Options.pacing_hint_for({"refresh": 60.0, "fps": 60.0, "overridden": false, "timed_by": 0.0}) == "")

	# --- the Options rows ------------------------------------------------------------
	var screen: Control = (load("res://scene/ui/menus/optionsscreen.tscn") as PackedScene).instantiate() as Control
	add_child(screen)
	await get_tree().process_frame
	check("Options has a Monitor row and a Window mode picker, and no Fullscreen switch",
		screen.get_node_or_null("%screenpick") != null and screen.get_node_or_null("%windowmode") != null
		and screen.get_node_or_null("%fullscreentoggle") == null)
	check("  the window mode picker lists the three modes in their order",
		screen.window_mode.item_count == 3 and screen.window_mode.get_item_text(0) == "Windowed"
		and screen.window_mode.get_item_text(2) == "Exclusive fullscreen")
	screen._refresh_screens([ultragear, samsung, ultrawide], 1)
	check("  the monitor picker lists every screen, the one the window is on selected",
		screen.screen_pick.item_count == 3 and screen.screen_pick.selected == 1
		and screen.screen_pick.get_item_text(1) == "1920 x 1080, 60 Hz"
		and screen.screen_pick.get_item_text(2) == "3440 x 1440, 100 Hz")
	check("  and is shown when there is a choice", screen.screen_row.visible)
	screen._refresh_screens([ultragear], 0)
	check("  and hidden when there is not - one screen is no choice", not screen.screen_row.visible)
	screen._refresh_screens([samsung, ultrawide, ultragear], 0)
	var kept_screen: Variant = Settings.get_value("screen")
	screen._on_screen_selected(1)
	check("picking the ultrawide sets the screen to its index, not its place in the list",
		Settings.get_value("screen") == 2, Settings.get_value("screen"))
	Settings.set_value("screen", kept_screen)
	var kept_mode: Variant = Settings.get_value("window_mode")
	screen._on_window_mode_selected(2)
	check("picking Exclusive fullscreen sets it", Settings.get_value("window_mode") == "exclusive")
	check("  and greys out the window size, which only a window has", screen.window_size.disabled)
	screen._on_window_mode_selected(1)
	check("  and so does Borderless", screen.window_size.disabled)
	screen._on_window_mode_selected(0)
	check("  and Windowed brings the size back", not screen.window_size.disabled)
	Settings.set_value("window_mode", kept_mode)
	screen._label_match_cap(59.94)
	check("the frame cap's Match screen says this screen's number",
		screen.frame_cap.get_item_text(1) == "Match screen (60)", screen.frame_cap.get_item_text(1))
	screen.queue_free()
	await get_tree().process_frame


# =============================================================================
# TEXT SIZE AND FONT (0.8.0)
# =============================================================================
# The owner, 7 Oct: "UI and text size and font", and then "what we need is
# style fonts". Every font size in the interface times the text size and the
# font's own scale; the world's writing takes only the font's scale; a window
# that would pass the screen scrolls instead.
func _test_windows_snap_to_their_text() -> void:
	# The owner, of the smith window with a hand's breadth of nothing under its
	# last row: "I need ui to snap into correct sizing when someone adjusts
	# font size, some people have a hard time seeing." A window grew to fit
	# what it held and never shrank; opened at Largest and set back to Normal,
	# 16 of 27 were left bigger than they open (panelwindow.gd, THE SIZE A
	# WINDOW SHOULD BE).
	section("WINDOWS - every one snaps to its text, both ways (0.75.0)")
	var kept_size: float = float(Settings.get_value("text_size"))
	var kept_font: String = str(Settings.get_value("font"))
	Settings.set_value("text_size", 1.0)
	Settings.set_value("font", "standard")
	var layer := CanvasLayer.new()
	add_child(layer)

	# ---- an empty line -----------------------------------------------------------
	# Godot 4.7.2 keeps the height an EMPTY Label had at its old size, so every
	# window with an empty notice line stood a line too tall after the text was
	# made smaller (settings.gd, AN EMPTY LABEL IS NOT MEASURED AGAIN).
	var empty := Label.new()
	empty.add_theme_font_size_override("font_size", 12)
	layer.add_child(empty)
	await get_tree().process_frame
	var empty_at_normal: float = empty.get_combined_minimum_size().y
	Settings.set_value("text_size", 1.5)
	await get_tree().process_frame
	var empty_at_largest: float = empty.get_combined_minimum_size().y
	Settings.set_value("text_size", 1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	check("an empty line is as tall at Normal again as it was before Largest",
		empty_at_largest > empty_at_normal and is_equal_approx(empty.get_combined_minimum_size().y, empty_at_normal),
		[empty_at_normal, empty_at_largest, empty.get_combined_minimum_size().y])
	empty.queue_free()

	# ---- every window, Largest and back ------------------------------------------
	var scenes: Array[String] = []
	var walk: Array[String] = ["res://scene/ui"]
	while not walk.is_empty():
		var dir_path: String = walk.pop_back()
		for sub in DirAccess.get_directories_at(dir_path):
			walk.append(dir_path.path_join(sub))
		for file in DirAccess.get_files_at(dir_path):
			if not file.ends_with(".tscn"):
				continue
			var text: String = FileAccess.get_file_as_string(dir_path.path_join(file))
			var at: int = text.find("path=\"res://src/")
			if at < 0:
				continue
			var script_path: String = text.substr(at + 6, text.find("\"", at + 6) - at - 6)
			if script_path.ends_with(".gd") and FileAccess.get_file_as_string(script_path).contains("PanelWindow.attach("):
				scenes.append(dir_path.path_join(file))
	var windows: Array = []
	for path in scenes:
		var window: Control = (load(path) as PackedScene).instantiate() as Control
		layer.add_child(window)
		window.visible = true
		windows.append(window)
	for i in 3:
		await get_tree().process_frame
	Settings.set_value("text_size", 1.5)
	for i in 3:
		await get_tree().process_frame
	var grew: Array = []
	for window in windows:
		var panel: PanelWindow = window.get("_window") as PanelWindow
		if panel != null and panel.hand_sized:
			grew.append(window.scene_file_path.get_file())
	check("a text size change forgets every size the player chose - it was for the old text",
		grew.is_empty(), grew)
	Settings.set_value("text_size", 1.0)
	for i in 3:
		await get_tree().process_frame
	var left_big: Array = []
	var looked: int = 0
	for window in windows:
		var panel: PanelWindow = window.get("_window") as PanelWindow
		if panel == null or not window.is_visible_in_tree():
			continue
		looked += 1
		var want: Vector2 = PanelWindow.fit_to(Rect2(window.global_position, panel.natural_size()),
			get_viewport().get_visible_rect().size, panel.natural_size()).size
		if absf(window.size.x - want.x) > 1.0 or absf(window.size.y - want.y) > 1.0:
			left_big.append("%s %s, should be %s" % [window.scene_file_path.get_file(), window.size, want])
	check("set back to Normal from Largest, every window is its natural size again - no gap under it",
		looked >= 20 and left_big.is_empty(), [looked, left_big])
	for window in windows:
		window.queue_free()
	await get_tree().process_frame

	# ---- the rule, on one window --------------------------------------------------
	var host := Control.new()
	host.name = "snaphost"
	host.size = Vector2(300, 200)
	host.position = Vector2(100, 100)
	layer.add_child(host)
	var frame := PanelContainer.new()
	frame.name = "frame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(frame)
	var margin := MarginContainer.new()
	margin.name = "margin"
	frame.add_child(margin)
	var rows := VBoxContainer.new()
	rows.name = "rows"
	margin.add_child(rows)
	var head := PanelContainer.new()
	head.name = "headerpanel"
	rows.add_child(head)
	var tall := Control.new()
	tall.custom_minimum_size = Vector2(200, 400)
	rows.add_child(tall)
	var win: PanelWindow = PanelWindow.attach(host, "")
	await get_tree().process_frame
	await get_tree().process_frame
	check("a window grows to what it holds", host.size.y >= 400.0, host.size)
	tall.custom_minimum_size = Vector2(200, 80)
	await get_tree().process_frame
	await get_tree().process_frame
	check("  and shrinks back when that needs less - to what its scene drew, no smaller",
		is_equal_approx(host.size.y, 200.0) and is_equal_approx(host.size.x, 300.0), host.size)
	check("  its top left corner where it was", host.position == Vector2(100, 100), host.position)
	win.hand_sized = true
	host.size = Vector2(420, 360)
	tall.custom_minimum_size = Vector2(200, 60)
	await get_tree().process_frame
	await get_tree().process_frame
	check("a window the player sized keeps that size when what it holds needs less",
		host.size == Vector2(420, 360), host.size)
	tall.custom_minimum_size = Vector2(200, 500)
	await get_tree().process_frame
	await get_tree().process_frame
	check("  and still grows when it needs more", host.size.y >= 500.0, host.size)
	tall.custom_minimum_size = Vector2(200, 60)
	Settings.set_value("text_size", 1.15)
	await get_tree().process_frame
	await get_tree().process_frame
	check("  until the text size changes: then it is its natural size again",
		not win.hand_sized and is_equal_approx(host.size.y, 200.0), [win.hand_sized, host.size])
	Settings.set_value("text_size", 1.0)
	await get_tree().process_frame
	host.queue_free()

	# ---- what panels.cfg keeps -------------------------------------------------------
	var cfg_path: String = PanelWindow.layout_path
	var cfg := ConfigFile.new()
	cfg.load(cfg_path)
	cfg.set_value("_snaptest_old", "x", 40.0)
	cfg.set_value("_snaptest_old", "y", 50.0)
	cfg.set_value("_snaptest_old", "w", 900.0)
	cfg.set_value("_snaptest_old", "h", 700.0)
	cfg.set_value("_snaptest_mine", "x", 40.0)
	cfg.set_value("_snaptest_mine", "y", 50.0)
	cfg.set_value("_snaptest_mine", "w", 500.0)
	cfg.set_value("_snaptest_mine", "h", 400.0)
	cfg.set_value("_snaptest_mine", "sized", true)
	cfg.save(cfg_path)
	var sizes: Dictionary = {}
	for key in ["_snaptest_old", "_snaptest_mine"]:
		var saved := Control.new()
		saved.size = Vector2(300, 200)
		var saved_head := PanelContainer.new()
		saved_head.name = "headerpanel"
		var saved_rows := VBoxContainer.new()
		saved_rows.name = "rows"
		var saved_margin := MarginContainer.new()
		saved_margin.name = "margin"
		var saved_frame := PanelContainer.new()
		saved_frame.name = "frame"
		saved_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		saved.add_child(saved_frame)
		saved_frame.add_child(saved_margin)
		saved_margin.add_child(saved_rows)
		saved_rows.add_child(saved_head)
		layer.add_child(saved)
		var saved_win: PanelWindow = PanelWindow.attach(saved, key)
		await get_tree().process_frame
		await get_tree().process_frame
		sizes[key] = [saved.position, saved.size, saved_win.hand_sized]
		saved.queue_free()
	check("a size saved before 0.75.0 is taken as a place, not a size - those were the old rule's leftovers",
		sizes["_snaptest_old"][0] == Vector2(40, 50) and sizes["_snaptest_old"][1] == Vector2(300, 200)
		and not sizes["_snaptest_old"][2], sizes["_snaptest_old"])
	check("  a size the player chose is put back, and kept as theirs",
		sizes["_snaptest_mine"][1] == Vector2(500, 400) and sizes["_snaptest_mine"][2], sizes["_snaptest_mine"])
	cfg.load(cfg_path)
	cfg.erase_section("_snaptest_old")
	cfg.erase_section("_snaptest_mine")
	cfg.save(cfg_path)
	var pw_code := _code_src("res://src/shared/panelwindow.gd")
	check("  a resize by hand is what marks it the player's, and the file says so",
		_func_body(pw_code, "func _on_grip_input(").contains("hand_sized = true")
		and _func_body(pw_code, "func _remember()").contains("cfg.set_value(key, \"sized\", hand_sized)"))

	# ---- the smith: the window in the owner's picture -------------------------------
	var smith: Control = (load("res://scene/ui/smith/smithscreen.tscn") as PackedScene).instantiate() as Control
	layer.add_child(smith)
	var ranks: Array = []
	for cert in GameConstants.CERTIFICATIONS:
		var row: Dictionary = (cert as Dictionary).duplicate(true)
		row["earned"] = false
		ranks.append(row)
	smith.set("_status", {"rank": 0, "ranks": ranks, "temper_costs": GameConstants.TEMPER_COSTS})
	smith.call("_render_ranks")
	smith.visible = true
	smith.show_certification()
	for i in 4:
		await get_tree().process_frame
	var at_normal: Vector2 = smith.size
	Settings.set_value("text_size", 1.5)
	for i in 4:
		await get_tree().process_frame
	var screen: Vector2 = get_viewport().get_visible_rect().size
	var rect: Rect2 = smith.get_global_rect()
	var ranks_scroll: ScrollContainer = smith.get_node("%rankscroll") as ScrollContainer
	var rows_need: float = PanelWindow.scroll_content(ranks_scroll).get_combined_minimum_size().y
	check("the smith's ranks at Largest: the whole window on the screen, its header and x with it",
		rect.position.y >= 0.0 and rect.end.y <= screen.y + 0.5 and smith.get_node("%closebutton").get_global_rect().position.y >= 0.0,
		rect)
	check("  the ranks scroll, rather than run off the bottom - and fill the room the screen leaves them",
		ranks_scroll.custom_minimum_size.y >= PanelWindow.SCROLL_LEAST and ranks_scroll.custom_minimum_size.y + 0.5 < rows_need
		and rect.end.y > screen.y - 2.0, [ranks_scroll.custom_minimum_size.y, rows_need, rect])
	check("  and the window widens with its text, so it wraps as it does at Normal",
		is_equal_approx(smith.get_node("%certifyview").custom_minimum_size.x, roundf(372.0 * 1.5))
		and smith.size.x > at_normal.x + 100.0, [smith.get_node("%certifyview").custom_minimum_size.x, smith.size])
	Settings.set_value("text_size", 1.0)
	for i in 8:
		await get_tree().process_frame
	rows_need = PanelWindow.scroll_content(ranks_scroll).get_combined_minimum_size().y
	check("  and at Normal again it is the size it was, with nothing under the last rank",
		smith.size.distance_to(at_normal) < 1.5 and absf(ranks_scroll.custom_minimum_size.y - rows_need) < 0.5,
		[smith.size, at_normal, ranks_scroll.custom_minimum_size.y, rows_need, ranks_scroll.get_v_scroll_bar().visible])
	smith.queue_free()

	# ---- the cooking window's meals ---------------------------------------------
	var cook: Control = (load("res://scene/ui/cooking/cookingscreen.tscn") as PackedScene).instantiate() as Control
	layer.add_child(cook)
	var chef := CookingCook.new()
	add_child(chef)
	cook.set("_view", 1)
	cook.open_for_firepit(null, chef)
	for i in 4:
		await get_tree().process_frame
	var recipes_at_normal: Vector2 = cook.size
	# OPENED AT LARGEST, as a player who reads at Largest opens it, so the
	# list is measured in Largest rows - then set back.
	Settings.set_value("text_size", 1.5)
	cook.open_for_firepit(null, chef)
	for i in 4:
		await get_tree().process_frame
	Settings.set_value("text_size", 1.0)
	for i in 4:
		await get_tree().process_frame
	check("the cooking window's meals, Largest and back: the size it opens at",
		cook.size.distance_to(recipes_at_normal) < 1.5, [cook.size, recipes_at_normal])
	cook.call("_set_view", 0)
	for i in 3:
		await get_tree().process_frame
	# THE FISH TAB IS THE SHORTER ONE with the art pack's meals; a clone has
	# none of their icons and a short list, so the window is held to the Fish
	# tab's own size, whichever way that is.
	var fish_want: Vector2 = (cook.get("_window") as PanelWindow).natural_size()
	check("  and the Fish tab takes the window to its own size - down, from the meals",
		cook.size.distance_to(fish_want) < 1.5, [cook.size, fish_want, recipes_at_normal])
	cook.queue_free()
	chef.queue_free()

	layer.queue_free()
	Settings.set_value("text_size", kept_size)
	Settings.set_value("font", kept_font)


func _test_text_size_and_font() -> void:
	section("TEXT SIZE AND FONT - every size scaled, five style fonts, nothing off the screen")
	const SettingsScript := preload("res://src/systems/settings.gd")
	var kept_size: Variant = Settings.get_value("text_size")
	var kept_font: Variant = Settings.get_value("font")
	Settings.set_value("text_size", 1.0)
	Settings.set_value("font", "standard")

	# --- the settings ----------------------------------------------------------
	check("text size and font are settings, the game as built by default",
		Settings.DEFAULTS["text_size"] == 1.0 and Settings.DEFAULTS["font"] == "standard")
	check("  four sizes, Normal first", Settings.TEXT_SIZES == [1.0, 1.15, 1.3, 1.5], Settings.TEXT_SIZES)
	check("  a size not on the list is the nearest one",
		SettingsScript.normalise_text_size(1.2) == 1.15 and SettingsScript.normalise_text_size(9) == 1.5
		and SettingsScript.normalise_text_size(0) == 1.0 and SettingsScript.normalise_text_size("x") == 1.0)
	Settings.set_value("font", "comic")
	check("  a font that is not one of them is the standard one", Settings.get_value("font") == "standard")
	check("six fonts, Standard first, every one named",
		Settings.FONT_STYLE_ORDER.size() == 6 and Settings.FONT_STYLE_ORDER[0] == "standard"
		and Settings.FONT_STYLE_ORDER.size() == Settings.FONT_STYLES.size(), Settings.FONT_STYLE_ORDER)
	check("  a size times the font's scale, rounded, never below 1",
		SettingsScript.scaled_font_size(12, 1.5) == 18 and SettingsScript.scaled_font_size(10, 1.15) == 12
		and SettingsScript.scaled_font_size(1, 0.1) == 1)

	# --- the files and their licences ---------------------------------------------
	var unlicensed: Array = []
	var unloadable: Array = []
	for style in Settings.FONT_STYLE_ORDER:
		var file: String = str(Settings.FONT_STYLES[style][1])
		if style == "standard":
			continue
		if not (load(file) is FontFile):
			unloadable.append(file)
		if THIRD_PARTY_LICENCES.get(file, "") != file.get_base_dir():
			unlicensed.append(file)
		elif not FileAccess.get_file_as_string(file.get_base_dir().path_join("OFL.txt")).begins_with("Copyright"):
			unlicensed.append(file + " (no copyright line)")
	check("every style font loads", unloadable.is_empty(), unloadable)
	check("  each is checked for its licence, in a folder of its own with the OFL.txt it came with",
		unlicensed.is_empty(), unlicensed)
	var stray: Array = []
	var named: Array = []
	for style in Settings.FONT_STYLES:
		named.append(str(Settings.FONT_STYLES[style][1]))
	for folder in DirAccess.get_directories_at("res://assets/stylefonts"):
		for file in DirAccess.get_files_at("res://assets/stylefonts".path_join(folder)):
			if file.get_extension() in ["ttf", "otf", "woff", "woff2"]:
				var full: String = "res://assets/stylefonts".path_join(folder).path_join(file)
				if not named.has(full):
					stray.append(full)
	check("  and no font sits in that folder that Options does not offer", stray.is_empty(), stray)

	# --- scaling the interface -----------------------------------------------------
	var host := Control.new()
	add_child(host)
	var plain := Label.new()
	var sized := Label.new()
	sized.add_theme_font_size_override("font_size", 12)
	var rich := RichTextLabel.new()
	rich.add_theme_font_size_override("normal_font_size", 10)
	host.add_child(plain)
	host.add_child(sized)
	host.add_child(rich)
	var theme_size: int = plain.get_theme_font_size("font_size")
	check("at Normal in the standard font nothing is touched - no size, no note",
		not plain.has_theme_font_size_override("font_size") and not plain.has_meta(SettingsScript._META_FONT_SIZES)
		and sized.get_theme_font_size("font_size") == 12)
	Settings.set_value("text_size", 1.5)
	check("Largest: a size the scene gave is half again", sized.get_theme_font_size("font_size") == 18,
		sized.get_theme_font_size("font_size"))
	check("  so is one the theme gave", plain.get_theme_font_size("font_size") == roundi(theme_size * 1.5),
		[plain.get_theme_font_size("font_size"), theme_size])
	check("  and a rich text box's", rich.get_theme_font_size("normal_font_size") == 15,
		rich.get_theme_font_size("normal_font_size"))
	var late := Label.new()
	late.add_theme_font_size_override("font_size", 14)
	host.add_child(late)
	check("  writing made after the setting is born scaled", late.get_theme_font_size("font_size") == 21,
		late.get_theme_font_size("font_size"))
	sized.add_theme_font_size_override("font_size", 20)
	check("  a script that sets a new size later has it scaled too",
		sized.get_theme_font_size("font_size") == 30, sized.get_theme_font_size("font_size"))
	Settings.set_value("text_size", 1.0)
	check("back to Normal: every size is the one it was given, and the theme's is the theme's again",
		sized.get_theme_font_size("font_size") == 20 and late.get_theme_font_size("font_size") == 14
		and rich.get_theme_font_size("normal_font_size") == 10
		and not plain.has_theme_font_size_override("font_size"),
		[sized.get_theme_font_size("font_size"), late.get_theme_font_size("font_size"),
		rich.get_theme_font_size("normal_font_size")])

	# THE WORLD'S WRITING: a name over a head is under a Node2D.
	var body := Node2D.new()
	var name_tag := Label.new()
	name_tag.add_theme_font_size_override("font_size", 10)
	body.add_child(name_tag)
	add_child(body)
	Settings.set_value("text_size", 1.5)
	check("a name over a head keeps its size at Largest - it is the world's",
		SettingsScript.is_world_text(name_tag) and name_tag.get_theme_font_size("font_size") == 10
		and not SettingsScript.is_world_text(sized), name_tag.get_theme_font_size("font_size"))
	Settings.set_value("text_size", 1.0)
	Settings.set_value("font", "tiny5")
	check("  but takes a font's own scale, so it looks the same size in it",
		name_tag.get_theme_font_size("font_size") == SettingsScript.scaled_font_size(10, SettingsScript.font_style_scale("tiny5")),
		name_tag.get_theme_font_size("font_size"))
	check("the interface takes the text size times the font's scale",
		is_equal_approx(Settings.text_factor(), SettingsScript.font_style_scale("tiny5"))
		and sized.get_theme_font_size("font_size") == SettingsScript.scaled_font_size(20, SettingsScript.font_style_scale("tiny5")))

	# --- the typeface ---------------------------------------------------------------
	Settings.set_value("font", "standard")
	var theme: Theme = ThemeDB.get_default_theme()
	var standard: Font = theme.default_font
	var bold: FontVariation = theme.get_font("bold_font", "RichTextLabel") as FontVariation
	var bold_base: Font = bold.base_font if bold != null else null
	Settings.set_value("font", "pixelify")
	check("a style font becomes the default theme's font, which every control reads",
		theme.default_font != null and theme.default_font.resource_path == str(Settings.FONT_STYLES["pixelify"][1]),
		theme.default_font.resource_path if theme.default_font != null else "none")
	check("  with the standard font behind it for a letter it lacks",
		theme.default_font.fallbacks.has(standard))
	check("  and bold rich text in it too", bold == null or bold.base_font == theme.default_font)
	check("  a label drawn now draws in it", plain.get_theme_font("font") == theme.default_font)
	Settings.set_value("font", "standard")
	check("Standard is exactly what it was", theme.default_font == standard
		and (bold == null or bold.base_font == bold_base))

	# --- Options ------------------------------------------------------------------------
	var screen: Control = (load("res://scene/ui/menus/optionsscreen.tscn") as PackedScene).instantiate() as Control
	add_child(screen)
	await get_tree().process_frame
	check("Options has Text size and Font",
		screen.text_size != null and screen.font_style != null
		and screen.text_size.item_count == 4 and screen.font_style.item_count == 6)
	check("  the sizes say how much", screen.text_size.get_item_text(0) == "Normal (100%)"
		and screen.text_size.get_item_text(3) == "Largest (150%)", screen.text_size.get_item_text(3))
	check("  the fonts by name", screen.font_style.get_item_text(0) == "Standard"
		and screen.font_style.get_item_text(1) == "Pixelify Sans", screen.font_style.get_item_text(1))
	# SOMETHING IN THE SCROLL GROWING ON ITS OWN - the account form opening -
	# grows the window too; nothing outside the scroll changed to say so.
	var columns_scroll: ScrollContainer = screen.get_node("%columnsscroll") as ScrollContainer
	# AS WINDOWS DRAWS IT, WHATEVER RUNS THE SUITE (0.56.1). The Graphics API
	# row is Windows' alone (rows_hidden_on()), so a Linux run measured a
	# window one row shorter than a player's: 713 there was 746 on the PC,
	# past the 720 a 720-high window has, and Options scrolled. The suite
	# measures the taller one, the one players get.
	screen.api_row.visible = true
	# The game window changing size while Options is shut measures it too.
	screen._window._on_viewport_resized()
	screen.open()
	await get_tree().process_frame
	await get_tree().process_frame
	# 681 since 0.54.0: Brightness and the Battery saver in its right column.
	# 713 since 0.55.0 - measured without the Windows row. 702 since 0.56.1,
	# with it: both columns 4 apart, not 6, and the right one 598 of the 616
	# a 720-high window leaves it.
	check("Options opens at the size it was drawn at - a hidden window is not measured",
		screen.size.y == 702.0 and columns_scroll.custom_minimum_size.y + 0.5
		>= PanelWindow.scroll_content(columns_scroll).get_combined_minimum_size().y, screen.size)
	var before: float = columns_scroll.custom_minimum_size.y
	screen._show_account_form(screen.account_password_form)
	await get_tree().process_frame
	await get_tree().process_frame
	check("the password form opens beside the taller column, and nothing scrolls",
		screen.account_password_form.visible
		and columns_scroll.custom_minimum_size.y + 0.5 >= PanelWindow.scroll_content(columns_scroll).get_combined_minimum_size().y
		and screen.size.y <= 720.0,
		[before, columns_scroll.custom_minimum_size.y, screen.size.y])
	# The email form is the taller of the two: it has to grow the window.
	screen._show_account_form(screen.account_email_form)
	await get_tree().process_frame
	await get_tree().process_frame
	check("the email form opening makes room for itself rather than scrolling",
		screen.account_email_form.visible and columns_scroll.custom_minimum_size.y > before
		and columns_scroll.custom_minimum_size.y + 0.5 >= PanelWindow.scroll_content(columns_scroll).get_combined_minimum_size().y
		and screen.size.y <= 720.0,
		[before, columns_scroll.custom_minimum_size.y, screen.size.y])
	screen._show_account_form(null)
	await get_tree().process_frame
	# A HINT IN THE TALLER COLUMN: a line growing in the shorter one fits
	# beside the other and needs no room (the right one since 0.54.0).
	var left_col: Control = columns_scroll.find_child("leftcol", true, false) as Control
	var right_col: Control = columns_scroll.find_child("rightcol", true, false) as Control
	var taller_left: bool = left_col.get_combined_minimum_size().y >= right_col.get_combined_minimum_size().y
	var hint: Label = columns_scroll.find_child("camerahint" if taller_left else "batteryhint", true, false) as Label
	var hint_text: String = hint.text
	before = columns_scroll.custom_minimum_size.y
	hint.text = hint_text + "\n\n\n\n"
	await get_tree().process_frame
	await get_tree().process_frame
	check("  and so does a line in it growing taller and no wider",
		columns_scroll.custom_minimum_size.y > before, [before, columns_scroll.custom_minimum_size.y])
	hint.text = hint_text
	screen._on_text_size_selected(2)
	screen._on_font_style_selected(4)
	check("picking them sets them", Settings.get_value("text_size") == 1.3 and Settings.get_value("font") == "fell",
		[Settings.get_value("text_size"), Settings.get_value("font")])
	screen.refresh()
	check("  and the panel shows what is set", screen.text_size.selected == 2 and screen.font_style.selected == 4)
	screen.queue_free()
	Settings.set_value("text_size", 1.0)
	Settings.set_value("font", "standard")

	# A WINDOW SHUT WHILE THE SIZE CHANGED is measured again when it opens:
	# Stats, which says nothing new when it comes back.
	var stats: Control = (load("res://scene/ui/statsscreen.tscn") as PackedScene).instantiate() as Control
	add_child(stats)
	stats.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	stats.visible = false
	Settings.set_value("text_size", 1.3)
	await get_tree().process_frame
	stats.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	var stats_scroll: ScrollContainer = stats.find_child("statsccroll", true, false) as ScrollContainer
	check("a window shut while the size changed grows to it when it opens",
		stats_scroll.custom_minimum_size.y + 0.5 >= PanelWindow.scroll_content(stats_scroll).get_combined_minimum_size().y,
		[stats_scroll.custom_minimum_size.y, PanelWindow.scroll_content(stats_scroll).get_combined_minimum_size().y])
	stats.queue_free()
	Settings.set_value("text_size", 1.0)

	# --- nothing off the screen ------------------------------------------------------------
	check("a scroll is as tall as what it holds while the window fits",
		PanelWindow.scroll_height(300.0, 300.0, 720.0) == 300.0)
	check("  no taller than the room left once it does not",
		PanelWindow.scroll_height(500.0, 300.0, 720.0) == 420.0, PanelWindow.scroll_height(500.0, 300.0, 720.0))
	check("  never squeezed to nothing", PanelWindow.scroll_height(500.0, 700.0, 720.0) == PanelWindow.SCROLL_LEAST)
	check("  and with no screen to measure, all of it", PanelWindow.scroll_height(500.0, 300.0, INF) == 500.0)

	# EVERY WINDOW, found by what it calls rather than listed, at the largest
	# size in the two tallest fonts.
	var scenes: Array[String] = []
	var walk: Array[String] = ["res://scene/ui"]
	while not walk.is_empty():
		var dir_path: String = walk.pop_back()
		for sub in DirAccess.get_directories_at(dir_path):
			walk.append(dir_path.path_join(sub))
		for file in DirAccess.get_files_at(dir_path):
			if not file.ends_with(".tscn"):
				continue
			var text: String = FileAccess.get_file_as_string(dir_path.path_join(file))
			var at: int = text.find("path=\"res://src/")
			if at < 0:
				continue
			var script_path: String = text.substr(at + 6, text.find("\"", at + 6) - at - 6)
			if script_path.ends_with(".gd") and FileAccess.get_file_as_string(script_path).contains("PanelWindow.attach("):
				scenes.append(dir_path.path_join(file))
	check("every window was found", scenes.size() >= 20, scenes.size())
	var layer := CanvasLayer.new()
	add_child(layer)
	var windows: Array = []
	for path in scenes:
		var window: Control = (load(path) as PackedScene).instantiate() as Control
		layer.add_child(window)
		window.visible = true
		windows.append(window)
	var cards: Array = windows.filter(func(w): return w is ControlsPanel)
	for card in cards:
		card.open_keys()
	await get_tree().process_frame
	# THE WINDOWS THAT PASS THE SCREEN AT LARGEST keep their body in a scroll
	# that PanelWindow sizes; at Normal it shows all it holds - nothing in
	# them scrolls that did not before.
	var fitted: Dictionary = {}
	var cut_at_normal: Array = []
	for window in windows:
		var panel: PanelWindow = window.get("_window") as PanelWindow
		if panel == null:
			continue
		for scroll in panel._scrolls:
			fitted[window.scene_file_path.get_file()] = true
			var content: Control = PanelWindow.scroll_content(scroll)
			# Unless it would pass the screen even so: twenty-two keys do.
			if scroll.custom_minimum_size.y + 0.5 < content.get_combined_minimum_size().y \
					and PanelWindow.content_minimum(window).y < 719.0:
				cut_at_normal.append(window.scene_file_path.get_file())
	check("Options, the GM panel, Stats and the Controls card fit their scroll to what it holds",
		fitted.has("optionsscreen.tscn") and fitted.has("ownerpanel.tscn") and fitted.has("statsscreen.tscn")
		and fitted.has("controlspanel.tscn"), fitted.keys())
	check("  and at Normal it all shows - nothing scrolls that fits", cut_at_normal.is_empty(), cut_at_normal)
	var too_tall: Array = []
	for style in ["fell", "tiny5"]:
		Settings.set_value("font", style)
		Settings.set_value("text_size", 1.5)
		await get_tree().process_frame
		await get_tree().process_frame
		for window in windows:
			var need: Vector2 = PanelWindow.content_minimum(window)
			if need.y > 720.0 or need.x > 1280.0:
				too_tall.append("%s in %s: %s" % [window.scene_file_path.get_file(), style, need])
			var panel: PanelWindow = window.get("_window") as PanelWindow
			var kept_scrolls: Array = panel._scrolls if panel != null else []
			for scroll in kept_scrolls:
				if scroll.custom_minimum_size.y + 0.5 < PanelWindow.scroll_content(scroll).get_combined_minimum_size().y \
						and need.y < 719.0:
					cut_at_normal.append("%s in %s at Largest" % [window.scene_file_path.get_file(), style])
	check("at Largest in the tallest fonts, every window fits a 1280 x 720 screen - the rest scrolls",
		too_tall.is_empty(), too_tall)
	check("  and a window with room to grow grew, rather than scrolling", cut_at_normal.is_empty(), cut_at_normal)
	Settings.set_value("text_size", 1.0)
	Settings.set_value("font", "standard")
	layer.queue_free()
	host.queue_free()
	body.queue_free()
	Settings.set_value("text_size", kept_size)
	Settings.set_value("font", kept_font)
	await get_tree().process_frame


# =============================================================================
# REBINDABLE KEYS (0.8.0)
# =============================================================================
func _test_rebindable_keys() -> void:
	section("KEYS - every key can be changed, on the Controls card")
	var kept_path: String = Keybinds.path
	Keybinds.path = "user://_suite_keys.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Keybinds.path))
	var keys: Keybinds = Settings.keys
	keys.load_keys()

	# --- what can be changed -------------------------------------------------------
	var missing: Array[String] = []
	for prop in ProjectSettings.get_property_list():
		var key_path: String = str(prop.name)
		if key_path.begins_with("input/") and not key_path.begins_with("input/ui_"):
			if not Keybinds.all_actions().has(key_path.trim_prefix("input/")):
				missing.append(key_path.trim_prefix("input/"))
	check("every key the game binds can be changed", missing.is_empty(), missing)
	var hotbar_ok: bool = true
	for i in Hotbar.SLOT_COUNT:
		if not InputMap.has_action(Keybinds.hotbar_action(i)) or keys.first_key(Keybinds.hotbar_action(i)) != int(Hotbar.SLOT_KEYS[i]):
			hotbar_ok = false
	check("  the ten hotbar keys are actions now, on 1 to 0", hotbar_ok)
	check("the defaults are the project's own: W and Up walk up, E uses, M is the map",
		keys.keys_of("move_up") == [KEY_W, KEY_UP] and keys.keys_of("interact") == [KEY_E, 0]
		and keys.keys_of("minimap_toggle") == [KEY_M, 0], [keys.keys_of("move_up"), keys.keys_of("interact")])
	check("  and nothing is changed until somebody changes it", keys.is_default())

	# --- changing one ----------------------------------------------------------------
	var result: Dictionary = keys.bind("inventory_toggle", 0, KEY_E)
	var e := InputEventKey.new()
	e.physical_keycode = KEY_E
	e.pressed = true
	check("putting the Bag on E works, and says it took E from Use",
		result.get("ok") == true and result.get("took_from") == "interact", result)
	check("  E opens the bag now and uses nothing", e.is_action_pressed("inventory_toggle")
		and not e.is_action_pressed("interact") and keys.action_for_key(KEY_E) == "inventory_toggle")
	check("  Use has no key, and says so", keys.first_key("interact") == 0
		and keys.unbound_actions().size() == 1 and keys.unbound_actions()[0] == "interact", keys.unbound_actions())
	var file := ConfigFile.new()
	file.load(Keybinds.path)
	check("the file holds what changed, and only that",
		file.get_value("keys", "inventory_toggle", []) == [KEY_E, 0] and file.get_value("keys", "interact", []) == [0, 0]
		and not file.has_section_key("keys", "move_up"), file.get_section_keys("keys") if file.has_section("keys") else PackedStringArray())
	var again := Keybinds.new()
	again._defaults = keys._defaults.duplicate(true)
	again._project_events = keys._project_events.duplicate(true)
	again.load_keys()
	check("  and the next launch reads it back", again.keys_of("inventory_toggle") == [KEY_E, 0]
		and again.keys_of("interact") == [0, 0])

	var refused: Dictionary = keys.bind("attack", 0, KEY_ESCAPE)
	check("Escape cannot be bound - it is how you get out of things",
		refused.get("ok") == false and String(refused.get("why")).contains("closing windows")
		and keys.keys_of("attack") == [KEY_SPACE, 0], refused)
	check("  nor the GM panel's key", String(keys.bind("attack", 0, KEY_QUOTELEFT).get("why")).contains("GM panel"))
	check("  nor Enter, which sends chat", keys.bind("sprint", 1, KEY_ENTER).get("ok") == false)
	keys.bind("move_up", 1, KEY_W)
	check("a key put in the other slot of its own action swaps, never doubles",
		keys.keys_of("move_up") == [KEY_UP, KEY_W], keys.keys_of("move_up"))
	keys.clear("move_up", 0)
	check("  clearing the first key moves the second up", keys.keys_of("move_up") == [KEY_W, 0], keys.keys_of("move_up"))

	# --- the hotbar -----------------------------------------------------------------------
	var bar: Hotbar = (load("res://scene/ui/hotbar.tscn") as PackedScene).instantiate() as Hotbar
	add_child(bar)
	keys.bind(Keybinds.hotbar_action(0), 0, KEY_F)
	var f := InputEventKey.new()
	f.physical_keycode = KEY_F
	f.pressed = true
	check("the first hotbar key on F: F fires it, 1 fires nothing",
		Hotbar.slot_for_event(f) == 0 and Hotbar.slot_for_key(KEY_1) == -1, Hotbar.slot_for_key(KEY_1))
	var key_label: Label = bar.find_child("slot1", true, false).get_node("keylabel") as Label
	check("  and the key says F on the bar", key_label.text == "F", key_label.text)
	check("  and on the Controls card", ControlsPanel.hotbar_text() == "F 2 3 4 5 6 7 8 9 0", ControlsPanel.hotbar_text())
	bar.queue_free()

	# --- a file edited by hand ----------------------------------------------------------------
	var hand := ConfigFile.new()
	hand.set_value("keys", "attack", "banana")
	hand.set_value("keys", "sprint", [KEY_ESCAPE, KEY_Q])
	hand.set_value("keys", "move_down", [KEY_G, 0])
	hand.save(Keybinds.path)
	keys.load_keys()
	check("a hand-edited file: nonsense is ignored, Escape dropped, a key on two actions kept once",
		keys.keys_of("attack") == [KEY_SPACE, 0] and keys.keys_of("sprint") == [KEY_Q, 0]
		and keys.keys_of("move_down") == [KEY_G, 0] and keys.keys_of("equipment_toggle") == [0, 0],
		[keys.keys_of("attack"), keys.keys_of("sprint"), keys.keys_of("equipment_toggle")])

	keys.reset_all()
	var m := InputEventKey.new()
	m.keycode = KEY_M
	m.pressed = true
	check("Reset puts every key back as the game came, the Map's printed M included",
		keys.is_default() and m.is_action_pressed("minimap_toggle") and Hotbar.slot_for_key(KEY_1) == 0)

	# --- the Controls card -------------------------------------------------------------------------
	var card: ControlsPanel = (load("res://scene/ui/controls/controlspanel.tscn") as PackedScene).instantiate() as ControlsPanel
	add_child(card)
	card.open_controls()
	check("the Controls card has Change keys, and the welcome does not",
		card.keys_row.visible and card.change_keys_button.text == "Change keys" and not card.reset_keys_button.visible)
	card.open_keys()
	check("Change keys: every key as a button, first and second",
		card.header_label.text == "CHANGE KEYS" and card.key_button("move_up", 0).text == "W"
		and card.key_button("move_up", 1).text == "Up" and card.key_button("interact", 1).text == "-"
		and card.key_button(Keybinds.hotbar_action(9), 0).text == "0")
	check("  with Done, Reset keys and how to do it", card.change_keys_button.text == "Done"
		and card.reset_keys_button.visible and card.key_note.visible and card.key_note.text == ControlsPanel.KEYS_HINT)
	card.start_capture("inventory_toggle", 0)
	check("a key button pressed waits for the key", card.is_capturing()
		and card.key_button("inventory_toggle", 0).text == ControlsPanel.WAITING_TEXT)
	card.start_capture("inventory_toggle", 0)
	check("  pressed again, it stops waiting", not card.is_capturing()
		and card.key_button("inventory_toggle", 0).text == "I")
	card.start_capture("inventory_toggle", 0)
	var press := InputEventKey.new()
	press.physical_keycode = KEY_E
	press.pressed = true
	card._input(press)
	check("  the next key pressed goes there, and the card says whose it was",
		not card.is_capturing() and keys.keys_of("inventory_toggle")[0] == KEY_E
		and card.key_note.text == "Bag is on E now. It was Use the shop, bank, fire or fishing spot's, which has no key now.",
		card.key_note.text)
	check("  the action left with no key turns red",
		(card.key_grid.get_node("label_interact") as Label).get_theme_color("font_color") == ControlsPanel.UNBOUND_COLOR
		and card.key_button("inventory_toggle", 0).text == "E")
	card.start_capture("attack", 0)
	card.press_key(KEY_ESCAPE)
	check("Esc while waiting changes nothing", card.key_note.text == "Nothing changed."
		and keys.keys_of("attack") == [KEY_SPACE, 0])
	card.start_capture("attack", 0)
	card.press_key(KEY_QUOTELEFT)
	check("  a kept key says what it is kept for", card.key_note.text.contains("GM panel")
		and keys.keys_of("attack") == [KEY_SPACE, 0], card.key_note.text)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	card._on_key_button_input(right, "move_up", 1)
	check("a right-click clears a key", keys.keys_of("move_up") == [KEY_W, 0]
		and card.key_button("move_up", 1).text == "-")
	card.reset_keys_button.pressed.emit()
	check("Reset keys puts them all back", keys.is_default() and card.key_button("interact", 0).text == "E"
		and card.key_note.text.contains("back"))
	card.change_keys_button.pressed.emit()
	check("Done goes back to the list", not card.is_editing() and card.header_label.text == "CONTROLS")
	card.open_welcome()
	check("  the welcome has no keys to change", not card.keys_row.visible)
	card.queue_free()

	var options: Control = (load("res://scene/ui/menus/optionsscreen.tscn") as PackedScene).instantiate() as Control
	add_child(options)
	await get_tree().process_frame
	var asked: Array = []
	options.keys_requested.connect(func(): asked.append(true))
	(options.get_node("%optionskeysbutton") as Button).pressed.emit()
	check("Options has Change keys, and it asks for the card", asked.size() == 1)
	options.queue_free()
	var hud_code: String = _code_src("res://src/ui/characterhud.gd")
	check("  which the HUD opens ready to change them",
		hud_code.contains("options_screen.keys_requested.connect(open_key_settings)")
		and _func_body(hud_code, "func open_key_settings(").contains("controls_panel.open_keys()"))
	check("the bar's key hints are read again when a key changes",
		_func_body(hud_code, "func _wire_nav_buttons(").contains("keys.changed.connect(_paint_nav_key_hints)"))
	var card_code: String = _code_src("res://src/ui/controls/controlspanel.gd")
	check("the key being set reaches the card first and nothing else",
		_func_body(card_code, "func _input(").contains("set_input_as_handled()"))

	DirAccess.remove_absolute(ProjectSettings.globalize_path(Keybinds.path))
	Keybinds.path = kept_path
	keys.load_keys()
	await get_tree().process_frame


# =============================================================================
# THE KILL RECORD (0.9.0)
# =============================================================================
# The owner, 7 Oct: "lets make a button in game that records all players kills
# with icons of the enemies". The server's half - what is counted, the two
# routes, the opening count - is test_killrecord.py.
func _test_the_kill_record() -> void:
	section("KILLS - every monster with its picture, yours and everybody's")

	# --- every monster that pays has a picture ---------------------------------
	EnemyPortraits.forget()
	var roster: Array = EnemyPortraits.roster()
	var paying: Array = []
	for entry in ResourceLoader.list_directory("res://data/enemies/"):
		var data: EnemyData = load("res://data/enemies/" + String(entry)) as EnemyData
		if data != null and data.grants_rewards:
			paying.append(data.enemy_id)
	var listed: Array = roster.map(func(m): return str(m["enemy_id"]))
	paying.sort()
	listed.sort()
	check("the roster is every monster that pays when killed, and no other",
		listed == paying and listed.size() >= 40, [listed.size(), paying.size()])
	check("  by name", str(roster[0]["name"]) <= str(roster[-1]["name"]))
	var pictureless: Array = []
	for monster in roster:
		var picture: Dictionary = EnemyPortraits.picture(str(monster["enemy_id"]))
		if picture.is_empty() or not (picture.get("texture") is Texture2D):
			pictureless.append(monster["enemy_id"])
	check("every one has a picture from its own art", pictureless.is_empty(), pictureless)
	var sprite_picture: Texture2D = EnemyPortraits.picture("firesprite").get("texture") as Texture2D
	var sprite_image: Image = sprite_picture.get_image() if sprite_picture != null else null
	check("  cut to the creature - a small sprite is not a speck in an empty cell",
		sprite_image != null and sprite_image.get_used_rect().size == sprite_image.get_size(),
		str([sprite_image.get_size(), sprite_image.get_used_rect()]) if sprite_image != null else "no image")
	check("the three whose scenes are named otherwise find them",
		EnemyPortraits.scene_path("boss").ends_with("bossenemy.tscn")
		and EnemyPortraits.scene_path("poisonslimesmall").ends_with("poisonslime.tscn")
		and ResourceLoader.exists(EnemyPortraits.scene_path("poisonslimelarge")))
	var fire: EnemyData = EnemyPortraits.data_for("fireboss")
	var recoloured: Dictionary = EnemyPortraits.picture("fireboss")
	check("a recoloured monster is pictured in its element's colour, as in the world",
		fire != null and fire.recolour_to_element and recoloured.get("material") is ShaderMaterial
		and is_equal_approx(float((recoloured["material"] as ShaderMaterial).get_shader_parameter("element_hue")),
			Element.hue_for(Element.Type.FIRE)))
	var original: EnemyData = EnemyPortraits.data_for("electricsprite")
	check("  and an original sheet as drawn", original != null and not original.recolour_to_element
		and EnemyPortraits.picture("electricsprite").get("material") == null)
	check("a monster this build does not know still has a name", EnemyPortraits.display_name("newmonster") == "Newmonster")

	# --- the words ------------------------------------------------------------------
	check("counts have their thousands marked", KillRecord.count_text(1234567) == "1,234,567"
		and KillRecord.count_text(999) == "999")
	check("how long ago, in words", KillRecord.ago_text(1000, 1030) == "just now"
		and KillRecord.ago_text(1000, 1000 + 600) == "10 min ago"
		and KillRecord.ago_text(1000, 1000 + 7200) == "2 h ago" and KillRecord.ago_text(0, 86400) == "1 day ago")
	check("the day counting began", KillRecord.since_text(1791374400).contains("7 Oct 2026")
		and KillRecord.since_text(0) == "")

	# --- the window -------------------------------------------------------------------
	var asked: Array = []
	var answers: Dictionary = {
		"/api/kills?slot=%d" % CharacterData.active_character_index: {"ok": true, "data": {
			"slot": CharacterData.active_character_index, "since": 1791374400, "total": 5, "kinds": 2,
			"kills": [{"enemy_id": "darkslime", "kills": 4, "first_at": 1, "last_at": int(Time.get_unix_time_from_system()) - 7200},
				{"enemy_id": "firesprite", "kills": 1, "first_at": 1, "last_at": 1}]}},
		"/api/kills/everyone": {"ok": true, "data": {"since": 1791374400, "total": 12, "players": 3,
			"kills": [{"enemy_id": "darkslime", "kills": 11, "players": 3, "top": "rival", "top_kills": 5, "yours": 4},
				{"enemy_id": "firesprite", "kills": 1, "players": 1, "top": "kt_me", "top_kills": 1, "yours": 1}]}},
	}
	var card: KillRecord = (load("res://scene/ui/kills/killrecord.tscn") as PackedScene).instantiate() as KillRecord
	add_child(card)
	await get_tree().process_frame
	card.fetch = func(path: String) -> Dictionary:
		asked.append(path)
		return answers.get(path, {"ok": false, "status": 404})
	var was_name: String = Api.username
	Api.username = "kt_me"
	await card.open()
	var rows: Array = card.list.get_children()
	check("the window opens on your kills", card.visible and card.tab == KillRecord.Tab.YOU
		and asked == ["/api/kills?slot=%d" % CharacterData.active_character_index], asked)
	check("  most killed first, then every monster not killed yet",
		rows.size() == roster.size() and str(rows[0].name) == "row_darkslime" and str(rows[1].name) == "row_firesprite",
		[rows.size(), roster.size()])
	var first: Control = rows[0]
	check("  each with its picture, its name and its count",
		(first.get_node("portrait") as TextureRect).texture != null
		and (first.get_node("count") as Label).text == "4"
		and not (first.find_child("name", true, false) as Label).text.is_empty())
	check("  and when the last one fell", (first.find_child("detail", true, false) as Label).text == "Last one 2 h ago",
		(first.find_child("detail", true, false) as Label).text)
	var last: Control = rows[-1]
	check("  a monster not killed yet is greyed and says so", last.modulate.a < 1.0
		and (last.find_child("detail", true, false) as Label).text == "Not killed yet"
		and (last.get_node("count") as Label).text == "-")
	check("  the summary says how many, of how many kinds, and since when",
		card.summary_label.text == "5 kills - 2 of %d kinds of monster, counted since 7 Oct 2026." % roster.size(),
		card.summary_label.text)

	card.everyone_button.pressed.emit()
	await get_tree().process_frame
	rows = card.list.get_children()
	check("Everyone: every player's kills of each monster", card.tab == KillRecord.Tab.EVERYONE
		and (rows[0].get_node("count") as Label).text == "11" and asked.size() == 2)
	check("  how many players, who has killed the most, and your own",
		(rows[0].find_child("detail", true, false) as Label).text == "3 players - most: rival (5) - you: 4",
		(rows[0].find_child("detail", true, false) as Label).text)
	var mine_top: Label = rows[1].find_child("detail", true, false) as Label
	check("  and when the most is you, it says so, in your colour",
		mine_top.text == "1 player - most: you (1)" and mine_top.get_theme_color("font_color") == KillRecord.YOU_COLOUR,
		mine_top.text)
	check("  with the realm's total", card.summary_label.text == "12 kills by 3 players, counted since 7 Oct 2026.",
		card.summary_label.text)
	card.yours_button.pressed.emit()
	await get_tree().process_frame
	check("going back reads nothing again for a while", asked.size() == 2 and card.tab == KillRecord.Tab.YOU)
	card.close()
	await card.open()
	check("  but opening it again does - kills happen while it is shut", asked.size() == 3)
	answers.erase("/api/kills/everyone")
	await card.show_tab(KillRecord.Tab.EVERYONE)
	check("a server with no kill record says so", card.notice_label.visible
		and card.notice_label.text == "This server does not keep a kill record yet.", card.notice_label.text)
	check("no connection says so too", KillRecord.refusal_text({"ok": false, "status": 0}) == "No connection to the server.")
	Api.username = was_name
	card.queue_free()

	# --- reaching it ------------------------------------------------------------------------
	var hud_scene: String = FileAccess.get_file_as_string("res://scene/ui/characterhud.tscn")
	var hud_code: String = _code_src("res://src/ui/characterhud.gd")
	check("Kills is on the Social dropdown, beside Kingdom",
		hud_scene.contains("[node name=\"killsbutton\" type=\"Button\" parent=\"socialmenu/socialitems\"")
		and hud_code.contains("\"killsbutton\":             \"_on_kills_pressed\""))
	var k := InputEventKey.new()
	k.physical_keycode = KEY_K
	k.pressed = true
	check("K opens it, and K can be changed like every other key",
		k.is_action_pressed("kills_toggle") and Keybinds.all_actions().has("kills_toggle")
		and _func_body(hud_code, "func _unhandled_input(").contains("toggle_kills()"))
	var listed_on_card: bool = false
	for spec in ControlsPanel.ROWS:
		if String(spec[1]) == "kills_toggle":
			listed_on_card = true
	check("  and the Controls card says so", listed_on_card and ControlsPanel.key_text("kills_toggle") == "K")


func _test_a_window_never_outgrows_the_screen() -> void:
	section("OPTIONS - a window size bigger than the screen")
	# Called on the script, not the autoload: they are static.
	const SettingsScript := preload("res://src/systems/settings.gd")

	# Day 1: 2560x1440 picked on a smaller monitor put the window's title bar
	# off the top of the screen, Options with it, and the way back was editing
	# options.cfg by hand. A 1920x1080 screen with a taskbar and a title bar
	# has about 1904x1001 of room.
	var room := Vector2i(1904, 1001)
	check("a window too wide for the screen comes down to the widest size that fits",
		SettingsScript.fit_window_side(2560, room.x, 0) == 1600, SettingsScript.fit_window_side(2560, room.x, 0))
	check("  and one too tall to the tallest, which is the same size",
		SettingsScript.fit_window_side(1440, room.y, 1) == 900, SettingsScript.fit_window_side(1440, room.y, 1))
	check("  3840x2160 too",
		SettingsScript.fit_window_side(3840, room.x, 0) == 1600 and SettingsScript.fit_window_side(2160, room.y, 1) == 900)
	check("  a size that fits is left alone",
		SettingsScript.fit_window_side(1280, room.x, 0) == 1280 and SettingsScript.fit_window_side(1920, 2544, 0) == 1920)
	check("  a screen too small for any of them gets 1280x720, the smallest window the game allows",
		SettingsScript.fit_window_side(1600, 1350, 0) == 1280 and SettingsScript.fit_window_side(900, 700, 1) == 720)
	check("  and a screen that cannot be measured shrinks nothing",
		SettingsScript.fit_window_side(3840, 0, 0) == 3840
		and SettingsScript.window_fits(Vector2i(3840, 2160), Vector2i.ZERO))

	# THE FILE GOES THROUGH IT TOO, which is what fixes a window already saved
	# too big: the next launch reads options.cfg through _normalise(). This run
	# is headless and has no screen to measure, so the wiring is read instead.
	var source: String = (load("res://src/systems/settings.gd") as GDScript).source_code
	var normalise: String = source.substr(source.find("func _normalise("))
	normalise = normalise.substr(0, normalise.find("\nfunc ", 10))
	check("  a size read from options.cfg is shrunk to fit as it is read",
		normalise.contains("fit_window_side(int(typed), window_room().x, 0)")
		and normalise.contains("fit_window_side(int(typed), window_room().y, 1)"))

	# THE PICKER greys out what does not fit, and says why.
	var screen: Node = (load("res://scene/ui/menus/optionsscreen.tscn") as PackedScene).instantiate()
	screen.window_size = screen.get_node("%windowsize")
	screen._populate_window_sizes()
	screen._mark_window_sizes(room)
	var picker: OptionButton = screen.window_size
	var offered: Array = []
	var refused: Array = []
	for i in picker.item_count:
		(refused if picker.is_item_disabled(i) else offered).append(Settings.WINDOW_SIZES[i])
	check("Options offers only the sizes this screen has room for",
		offered == [Vector2i(1280, 720), Vector2i(1600, 900)], offered)
	check("  the rest are greyed out and say why",
		refused.size() == 3 and picker.get_item_text(4).ends_with("too big for this screen"),
		picker.get_item_text(4))
	screen._mark_window_sizes(Vector2i(7680, 4320))
	var all_back := true
	for i in picker.item_count:
		if picker.is_item_disabled(i) or picker.get_item_text(i).contains("too big"):
			all_back = false
	check("  and on a bigger screen they all come back", all_back)
	screen.free()


func _test_banked_gold_goes_through_the_server() -> void:
	section("BANK - gold is moved by the server, or not at all")

	# Day 1: banking 200 of 257 showed 57 carried and 200 banked, and the server
	# still held 257 carried and 0 banked. The two functions moved the numbers
	# on this machine and nothing ever called /api/bank/gold, so a relog put the
	# gold back in the purse and a death would have burned all of it.
	var holder := GDScript.new()
	holder.source_code = "extends Node\nvar gold: int = 257\nvar notices: Array = []\nfunc show_notice(m): notices.append(m)\n"
	holder.reload()
	var fake: Node = holder.new()
	var kept_bank: int = CharacterData.get_bank_gold()
	var kept_slot: int = CharacterData.active_character_index
	var kept_slots: Array = CharacterData.character_slots.duplicate(true)
	CharacterData.account_data["bank_gold"] = 0
	var asked: Array = []

	# A REFUSAL MOVES NOTHING, and says why.
	CharacterData.bank_gold_request = func(body: Dictionary) -> Dictionary:
		asked.append(body)
		return {"ok": false, "status": 400, "error": "Cannot deposit 200 - only 57 carried."}
	var moved: bool = await CharacterData.deposit_gold_to_bank(200, fake)
	check("a deposit asks the server, with the amount and the operation",
		asked.size() == 1 and asked[0].get("op") == "deposit" and int(asked[0].get("amount", 0)) == 200
			and asked[0].has("slot"), asked)
	check("  and when it refuses, neither the purse nor the bank moves",
		not moved and fake.gold == 257 and CharacterData.get_bank_gold() == 0,
		[moved, fake.gold, CharacterData.get_bank_gold()])
	check("  and the player is told why", fake.notices.size() == 1 and str(fake.notices[0]).contains("only 57"),
		fake.notices)

	# AN ANSWER IS COPIED, NOT ADDED UP. The server's two figures are what the
	# screen shows, even when they are not what this side would have worked out.
	CharacterData.bank_gold_request = func(body: Dictionary) -> Dictionary:
		asked.append(body)
		return {"ok": true, "status": 200, "data": {"carried_gold": 50, "bank_gold": 207}}
	moved = await CharacterData.deposit_gold_to_bank(200, fake)
	check("a deposit the server took shows the server's purse and bank",
		moved and fake.gold == 50 and CharacterData.get_bank_gold() == 207,
		[moved, fake.gold, CharacterData.get_bank_gold()])
	CharacterData.bank_gold_request = func(body: Dictionary) -> Dictionary:
		asked.append(body)
		return {"ok": true, "status": 200, "data": {"carried_gold": 80, "bank_gold": 177}}
	moved = await CharacterData.withdraw_gold_from_bank(30, fake)
	check("  and so does a withdrawal",
		moved and asked[-1].get("op") == "withdraw" and fake.gold == 80 and CharacterData.get_bank_gold() == 177,
		[asked[-1], fake.gold, CharacterData.get_bank_gold()])

	CharacterData.bank_gold_request = Callable()
	CharacterData.account_data["bank_gold"] = kept_bank
	CharacterData.active_character_index = kept_slot
	CharacterData.character_slots = kept_slots
	fake.free()
	print("  gold between the purse and the bank is the server's to move")


func _test_the_store_sells_the_next_set() -> void:
	section("SHOP - iron to amethyst on sale, a shelf per band")

	# Day 1, decided by the owner: the general store sells every weapon and
	# armour piece from iron to amethyst at its value, so a player farming one
	# band saves for the next band's set. Ember stays drop-only. Anyone may buy
	# any piece; the level gate is on wearing it (test_pacing.py holds that,
	# and the saving pace, against the real server).
	var store: ShopData = load("res://data/shops/generalstore.tres") as ShopData
	check("generalstore.tres loads as a ShopData", store != null)
	if store == null:
		return
	# THE REGISTRY NEEDS THE PACK: every item's icon is in art/pack, and an item
	# whose icon will not load is not registered. Without it these are skips.
	var stock: Array[String] = store.stock
	var missing: Array = []
	var too_good: Array = []
	var gear_seen := 0
	for item in ItemRegistry.get_all_items():
		if item.type != ItemData.Type.WEAPON and item.type != ItemData.Type.ARMOR:
			continue
		gear_seen += 1
		if item.tier >= 1 and item.tier <= 4 and not stock.has(item.item_id):
			missing.append(item.item_id)
		if item.tier >= 5 and stock.has(item.item_id):
			too_good.append(item.item_id)
	check_needs_pack("every weapon and armour piece of iron to amethyst is stocked",
		gear_seen > 0 and missing.is_empty(), missing)
	check_needs_pack("  and nothing of ember or above", too_good.is_empty(), too_good)
	var unknown: Array = stock.filter(func(id: String) -> bool: return not ItemRegistry.has_item(id))
	check_needs_pack("  every stocked id is a real item", unknown.is_empty(), unknown)
	check("  sold at its value", is_equal_approx(store.price_multiplier, 1.0), store.price_multiplier)

	# THE SERVER SELLS FROM gamedata.json, not from the .tres. An export that
	# was not re-run (or not copied across) leaves the server on the old shelf.
	var exported: Dictionary = {}
	for shop in _load_gamedata().get("shops", []):
		if shop is Dictionary and str(shop.get("shop_id", "")) == store.shop_id:
			exported = shop
	check("data/gamedata.json carries the same stock in the same order",
		Array(exported.get("stock", [])) == Array(stock), "re-run src/tools/exportgamedata.gd")

	# ONE SHELF PER BAND, which needs the stock in shelf order: show_catalogue()
	# starts a heading whenever the kind of row changes, so a tier that came
	# back after another would get a second heading. Read from the export, which
	# carries each item's type and tier without needing the art.
	var panel_script: GDScript = load("res://src/ui/shop/shopinventory.gd") as GDScript
	var exported_items: Dictionary = {}
	for row in _load_gamedata().get("items", []):
		if row is Dictionary:
			exported_items[str(row.get("item_id", ""))] = row
	var shelves: Array = []
	for id in stock:
		var shelf: String = panel_script.shelf_of(exported_items.get(id, {}))
		if shelves.is_empty() or shelves[-1] != shelf:
			shelves.append(shelf)
	# The cooking staples (0.74.0) have a shelf of their own, after the fishing.
	check("the stock runs potions, fishing, cooking, then iron, jade, cobalt, amethyst, each once",
		shelves == ["supplies", "fishing", "cooking", "gear 1", "gear 2", "gear 3", "gear 4"], shelves)

	# EVERY POTION, TINY TO GREATER (0.25.4). The owner: "need to unlock all of
	# the potions we set up" - the large and greater ones were drops only.
	var potions: Array = stock.filter(func(id: String) -> bool:
		return panel_script.shelf_of(exported_items.get(id, {"item_id": id})) == "supplies")
	var every_potion: Array = []
	for size in ["tiny", "small", "medium", "large", "greater"]:
		for pool in ["health", "mana", "stamina"]:
			every_potion.append("%s%spotion" % [size, pool])
	check("the supplies shelf is every potion, tiny to greater, health, mana and stamina of each (0.25.4)",
		potions == every_potion, potions)

	# FISHING: the worm and every rod but ember, decided by the owner on day 1.
	# Only the iron rod could be had before, and worms dropped one at a time.
	# The better baits joined them in 0.74.0 ("bait and supplies from the shop").
	var fishing: Array = stock.filter(func(id: String) -> bool:
		return panel_script.shelf_of(exported_items.get(id, {"item_id": id})) == "fishing")
	check("the fishing shelf has the worm, the iron to amethyst rods, the lugworm and the glowgrub, and no ember rod",
		fishing == ["fishingworm", "ironfishingrod", "jadefishingrod", "cobaltfishingrod", "amethystfishingrod",
			"lugworm", "glowgrub"],
		fishing)
	var pond: Node = (load("res://scene/interactables/fishingspot.tscn") as PackedScene).instantiate()
	check("  the shelf's bait is the pond's", panel_script.FISHING_BAIT_ID == str(pond.bait_item_id),
		pond.bait_item_id)
	pond.free()

	# THE LANDS ON A HEADING ARE THE LANDS THAT DROP THE TIER. Read off every
	# normal enemy, so moving an element to another band without updating
	# TIER_ELEMENTS fails here instead of sending players to the wrong place.
	var listed: Dictionary = {}
	for tier in GameConstants.TIER_ELEMENTS.size():
		for element in GameConstants.TIER_ELEMENTS[tier]:
			check("  %s is listed under one tier" % Element.name_for(int(element)), not listed.has(element))
			listed[element] = tier
	var wrong: Array = []
	var normals := 0
	var dir := DirAccess.open("res://data/enemies")
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var enemy: EnemyData = load("res://data/enemies/" + file) as EnemyData
		if enemy == null or enemy.slots_are_gear or not listed.has(enemy.element):
			continue
		normals += 1
		if enemy.max_loot_tier != listed[enemy.element]:
			wrong.append("%s drops tier %d, listed under %d" % [enemy.enemy_id, enemy.max_loot_tier, listed[enemy.element]])
	if normals == 0:
		wrong.append("no normal enemies were read")
	check("every normal enemy drops the tier its element is listed under", wrong.is_empty(), wrong)
	check("  tier 2 is the Water and Ice lands", GameConstants.tier_lands(2) == "Water and Ice",
		GameConstants.tier_lands(2))
	var named_ok := true
	for tier in range(1, GameConstants.TIER_MATERIALS.size()):
		var sword: Dictionary = exported_items.get(GameConstants.TIER_MATERIALS[tier].to_lower() + "sword", {})
		if int(sword.get("tier", -1)) != tier:
			named_ok = false
	check("  each tier's material names its sword", named_ok)

	# THE PANEL, drawn from an answer in the server's shape - the rows the
	# server builds from the same export.
	var panel: Node = (load("res://scene/ui/shop/shopinventory.tscn") as PackedScene).instantiate()
	panel.header_label = panel.get_node("%headerlabel")
	panel.stock_list = panel.get_node("%stocklist")
	panel.notice_label = panel.get_node("%noticelabel")
	var rows: Array = []
	for id in ["tinyhealthpotion", "fishingworm", "jadefishingrod", "ironsword", "ironhelm", "jadesword",
			"cobaltsword", "amethystsword"]:
		var item: Dictionary = exported_items.get(id, {})
		rows.append({"item_id": id, "display_name": str(item.get("display_name", id)),
			"price": int(item.get("value", 0)), "tier": int(item.get("tier", 1)),
			"type_name": str(item.get("type_name", "")), "required_level": int(item.get("required_level", 1)),
			"required_classes": []})
	panel.show_catalogue({"display_name": "General Store", "stock": rows})
	var headings: Array = []
	var row_count := 0
	for child in panel.stock_list.get_children():
		if child is Label:
			headings.append(child.text)
		else:
			row_count += 1
	check("the panel heads each shelf once, in order", headings == [
		"Potions and supplies",
		"Fishing  ·  rods and worms",
		"Iron  ·  the Light and Wind lands  ·  level 1",
		"Jade  ·  the Water and Ice lands  ·  level 5",
		"Cobalt  ·  the Earth lands  ·  level 10",
		"Amethyst  ·  the Fire lands  ·  level 16"], headings)
	check("  with every row under them", row_count == rows.size(), row_count)
	panel.show_catalogue({"display_name": "General Store", "stock": rows})
	check("  and drawing it again does not double it",
		panel.stock_list.get_child_count() == rows.size() + 6, panel.stock_list.get_child_count())
	panel.free()
	print("  the store sells the next set, and the shelf says where its band is")


# =============================================================================
# THE SHOP BUYS
# =============================================================================
# 5 Oct, the owner: "we should be able to sell items to the shop". Every piece
# of a tier is the same piece, so a second jade sword was worth nothing to its
# finder. The shop panel has Buy and Sell under the purse; Sell lists the
# backpack at the prices the server sent, a cell at a time, and draws the
# purse and bag the server answers with.
func _test_the_shop_buys() -> void:
	section("SHOP - the shop buys: the backpack, priced by the server, a cell at a time")

	const T := ItemData.Type
	var potion: ItemData = _menu_item("zz_sell_potion", T.CONSUMABLE, 0, 20)
	potion.tier = 1
	var sword: ItemData = _menu_item("zz_sell_sword", T.WEAPON, ItemData.EquipSlot.WEAPON)
	sword.tier = 2
	var chest: ItemData = _menu_item("zz_sell_chest", T.ARMOR, ItemData.EquipSlot.CHEST)
	chest.tier = 5
	var coin: ItemData = _menu_item("zz_sell_coin", T.CURRENCY, 0, 99)
	for item in [potion, sword, chest, coin]:
		ItemRegistry._items[item.item_id] = item

	var bag := InventoryContainer.new()
	bag.is_carry = true
	add_child(bag)
	bag.load_save_array([{"item_id": "zz_sell_potion", "quantity": 6}, null,
		{"item_id": "zz_sell_sword", "quantity": 1}, {"item_id": "zz_sell_coin", "quantity": 40},
		{"item_id": "zz_sell_chest", "quantity": 1}])

	var panel: Node = (load("res://scene/ui/shop/shopinventory.tscn") as PackedScene).instantiate()
	add_child(panel)
	panel.inventory_override = bag
	panel.shop_id = "generalstore"
	var sent: Array = []
	var answer: Array = [{}]
	panel.post_request = func(path: String, body: Dictionary) -> Dictionary:
		sent.append([path, body])
		return answer[0]

	var mode_row: Node = panel.find_child("moderow", true, false)
	var buy_mode: Button = mode_row.get_node_or_null("buymode") if mode_row != null else null
	var sell_mode: Button = mode_row.get_node_or_null("sellmode") if mode_row != null else null
	check("the panel has Buy and Sell under the purse, on Buy",
		buy_mode != null and sell_mode != null and buy_mode.button_pressed and not sell_mode.button_pressed)

	panel.show_catalogue({"display_name": "Kingdom Supplies", "sell_multiplier": 0.05, "stock": [],
		"sell_prices": {"zz_sell_potion": 10, "zz_sell_sword": 52, "zz_sell_chest": 1464}})
	sell_mode.pressed.emit()
	var rows: Dictionary = {}
	for child in panel.stock_list.get_children():
		rows[str(child.name)] = child
	check("Sell lists what the shop buys, by the cell it is in",
		rows.has("sell_0") and rows.has("sell_2") and rows.has("sell_4") and panel.mode == "sell", rows.keys())
	check("  and not what it does not - the pile of coins is cashed, not sold",
		not rows.has("sell_3"), rows.keys())
	var pays: Label = rows["sell_0"].find_child("pays", true, false) if rows.has("sell_0") else null
	check("  a stack shows what all of it fetches, at the server's price",
		pays != null and pays.text == "60 g", pays.text if pays != null else "")
	check("  and offers Sell 1 and Sell all; one piece just Sell",
		rows.has("sell_0") and rows["sell_0"].find_child("sellone", true, false) != null
		and rows.has("sell_2") and rows["sell_2"].find_child("sellone", true, false) == null
		and (rows["sell_2"].find_child("sellall", true, false) as Button).text == "Sell")
	check("  and says what share the shop pays", panel.notice_label.text.contains("5%"), panel.notice_label.text)

	answer[0] = {"ok": true, "status": 200, "data": {"item_id": "zz_sell_sword", "quantity": 1,
		"total_received": 52, "gold": 552, "inventory": [{"item_id": "zz_sell_potion", "quantity": 6}, null, null,
		{"item_id": "zz_sell_coin", "quantity": 40}, {"item_id": "zz_sell_chest", "quantity": 1}]}}
	(rows["sell_2"].find_child("sellall", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	check("Sell names the cell and the item seen in it, and how many",
		sent.size() == 1 and sent[0][0] == "/api/shop/sell" and sent[0][1].get("position") == 2
		and sent[0][1].get("item_id") == "zz_sell_sword" and sent[0][1].get("quantity") == 1
		and sent[0][1].get("shop_id") == "generalstore", sent)
	check("  and the bag the server answers with is drawn", bag.get_stack_at(2) == null
		and bag.get_stack_at(0) != null and bag.get_stack_at(0).quantity == 6)
	var names: Array = []
	for child in panel.stock_list.get_children():
		names.append(str(child.name))
	check("  and the list follows it", not names.has("sell_2") and names.has("sell_0"), names)

	# A legendary piece asks twice.
	var chest_row: Node = null
	for child in panel.stock_list.get_children():
		if str(child.name) == "sell_4":
			chest_row = child
	var chest_button: Button = chest_row.find_child("sellall", true, false) if chest_row != null else null
	chest_button.pressed.emit()
	check("a legendary piece asks again before it goes, and nothing is sent",
		sent.size() == 1 and chest_button.text == "Sure?" and panel.notice_label.text.begins_with("Click again"),
		[sent.size(), chest_button.text])
	answer[0] = {"ok": true, "status": 200, "data": {"item_id": "zz_sell_chest", "quantity": 1,
		"total_received": 1464, "gold": 2016, "inventory": [{"item_id": "zz_sell_potion", "quantity": 6}, null,
		null, {"item_id": "zz_sell_coin", "quantity": 40}, null]}}
	chest_button.pressed.emit()
	await get_tree().process_frame
	check("  and the second click sells it", sent.size() == 2 and sent[1][1].get("item_id") == "zz_sell_chest")

	# The bag moved under the panel: the server says so and sends its own.
	answer[0] = {"ok": false, "status": 409, "error": "Your backpack changed on the server. It has been reloaded.",
		"data": {"resync": {"slot": 0, "gold": 2016, "inventory": [{"item_id": "zz_sell_potion", "quantity": 2},
		null, null, null, null]}}}
	var one: Button = null
	for child in panel.stock_list.get_children():
		if str(child.name) == "sell_0":
			one = child.find_child("sellone", true, false)
	one.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check("a stale cell is the server's bag, adopted and redrawn",
		bag.get_stack_at(0) != null and bag.get_stack_at(0).quantity == 2
		and panel.notice_label.text.contains("changed"), panel.notice_label.text)

	answer[0] = {"ok": false, "status": 400, "error": "The shop does not buy that.", "data": {}}
	for child in panel.stock_list.get_children():
		if str(child.name) == "sell_0":
			one = child.find_child("sellall", true, false)
	one.pressed.emit()
	await get_tree().process_frame
	check("a refusal is said in the server's words", panel.notice_label.text == "The shop does not buy that.",
		panel.notice_label.text)

	buy_mode.pressed.emit()
	check("Buy goes back to the stock", panel.mode == "buy" and buy_mode.button_pressed and not sell_mode.button_pressed)
	check("ShopInventory.asks_twice: ember and mythic gear, not a potion",
		panel.asks_twice(chest) and not panel.asks_twice(sword) and not panel.asks_twice(potion))

	# WHAT THE STORE PAYS IS ITS OWN, AUTHORED HERE AND EXPORTED. Below what it
	# charges, or buying to sell is a printing press.
	var store: ShopData = load("res://data/shops/generalstore.tres") as ShopData
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/gamedata.json"))
	var exported_rate: float = -1.0
	if data is Dictionary:
		for row in data.get("shops", []):
			if str(row.get("shop_id", "")) == "generalstore":
				exported_rate = float(row.get("sell_multiplier", -1.0))
	check("the store pays a twentieth of value, well under what it charges",
		store != null and is_equal_approx(store.sell_multiplier, 0.05)
		and store.sell_multiplier < store.price_multiplier, str(store.sell_multiplier) if store != null else "no store")
	check("  and gamedata.json says the same (re-run the exporter if not)",
		store != null and is_equal_approx(exported_rate, store.sell_multiplier), exported_rate)

	panel.queue_free()
	bag.queue_free()
	for item in [potion, sword, chest, coin]:
		ItemRegistry._items.erase(item.item_id)
	print("  the shop buys what drops, a cell at a time, at the server's price")
