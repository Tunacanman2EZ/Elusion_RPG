# testrunner_8.gd - part 8 of the suite (testrunner.gd says how it is
# split): 11 tests, _test_the_meteor_pulls to _test_the_field_volleys.
extends "res://src/tools/testrunner_7.gd"


# THE METEOR'S PULL (0.17.0). The owner: "on the spin up of meteor can we pull
# enemies closer to the center?", "like before the meteor falls". While the
# stone comes down, monsters within PULL_RADIUS are drawn toward where it
# lands, through the physics engine, and stop PULL_STOP from the middle. One
# meteor in ten at 0.17.1, one in a hundred since 0.17.2: "1% chance instead
# of 10".
func _test_the_meteor_pulls() -> void:
	section("THE METEOR'S PULL - the vortex draws a pack in before the stone lands")
	var arena := Node2D.new()
	add_child(arena)
	var o := Vector2(-71000, -71000)
	var foe_at := func(path: String, offset: Vector2) -> BaseEnemy:
		var e: BaseEnemy = (load(path) as PackedScene).instantiate()
		e.position = o + offset
		arena.add_child(e)
		e.set_physics_process(false)
		return e
	var near: BaseEnemy = foe_at.call("res://scene/enemy/firesprite.tscn", Vector2(70, 0))
	var close: BaseEnemy = foe_at.call("res://scene/enemy/firesprite.tscn", Vector2(0, 8))
	var far: BaseEnemy = foe_at.call("res://scene/enemy/firesprite.tscn", Vector2(0, -(Meteor.PULL_RADIUS + 25.0)))
	var boss: BaseEnemy = foe_at.call("res://scene/enemy/bossenemy.tscn", Vector2(-60, 0))
	var mirror: BaseEnemy = foe_at.call("res://scene/enemy/firesprite.tscn", Vector2(0, 60))
	mirror.net_mirror = true
	var walled: BaseEnemy = foe_at.call("res://scene/enemy/firesprite.tscn", Vector2(50, 70))
	# A wall between that one and the middle, on the walls layer.
	var wall := StaticBody2D.new()
	wall.collision_layer = 2
	var wall_shape := CollisionShape2D.new()
	var wall_rect := RectangleShape2D.new()
	wall_rect.size = Vector2(80, 6)
	wall_shape.shape = wall_rect
	wall.add_child(wall_shape)
	arena.add_child(wall)
	wall.global_position = o + Vector2(50, 55)
	for i in 3:
		await get_tree().physics_frame
	var near_from: float = near.global_position.distance_to(o)
	var near_hp: int = near.hp
	var boss_at: Vector2 = boss.global_position
	var mirror_at: Vector2 = mirror.global_position
	var far_at: Vector2 = far.global_position
	var walled_from: float = walled.global_position.distance_to(o)

	var met: Meteor = (load("res://scene/projectiles/meteor.tscn") as PackedScene).instantiate()
	met.explosion_damage = 50
	met.delay = 0.2
	met.pulls = true
	arena.add_child(met)
	met.global_position = o
	met.set_physics_process(false)
	for i in 3:
		await get_tree().physics_frame
	met.advance(0.15)
	check("nothing is pulled before the stone starts to fall (a double cast's second waits)",
		met.pulled_count() == 0 and is_equal_approx(near.global_position.distance_to(o), near_from))
	met.advance(0.05)
	var steps: int = 0
	while not met.landed and steps < 200:
		met.advance(1.0 / 60.0)
		steps += 1
		await get_tree().physics_frame
	var near_to: float = near.global_position.distance_to(o) if is_instance_valid(near) else -1.0
	check("a monster inside the pull and outside the hit is drawn in, and is hit",
		near_from > Meteor.HIT_RADIUS and near_to < Meteor.HIT_RADIUS and near.hp < near_hp,
		[near_from, near_to, near.hp])
	check("  not past PULL_STOP from the middle - gathered, not piled on one pixel",
		near_to >= Meteor.PULL_STOP - 0.5 and close.global_position.distance_to(o) >= 8.0 - 0.01,
		[near_to, close.global_position.distance_to(o)])
	check("one beyond the pull stays where it was", far.global_position == far_at, far.global_position - far_at)
	check("a boss holds its ground", boss.global_position == boss_at and not boss.can_be_pulled(),
		boss.global_position - boss_at)
	check("a monster another game runs is not moved here - its own game says where it is",
		mirror.global_position == mirror_at and not mirror.can_be_pulled())
	check("a wall stops the pull the way it stops a monster walking",
		walled.global_position.y > wall.global_position.y and walled.global_position.distance_to(o) < walled_from,
		[walled.global_position - o, walled_from])
	check("  it counts what it drew in: the near one and the walled one",
		met.pulled_count() == 2, met.pulled_count())
	var landed_at: Vector2 = near.global_position
	met.advance(0.3)
	await get_tree().physics_frame
	check("once it has landed it pulls no more", near.global_position == landed_at)
	check("a pulling meteor's ring of fire starts at the pull's edge, so the ring is the pull",
		is_equal_approx(Meteor.HIT_RADIUS * Meteor.PULL_SWIRL_FROM, Meteor.PULL_RADIUS)
		and is_equal_approx(met.swirl_from(), Meteor.PULL_SWIRL_FROM))
	check("the pull reaches twice the hit, and is quick enough to beat a walk (90 a second)",
		is_equal_approx(Meteor.PULL_RADIUS, Meteor.HIT_RADIUS * 2.0)
		and Meteor.PULL_SPEED * lerpf(Meteor.PULL_START, 1.0, 0.5) > 90.0)

	# ---- one in a hundred (0.17.2) -------------------------------------------
	var plain_foe: BaseEnemy = foe_at.call("res://scene/enemy/firesprite.tscn", Vector2(400 + 70, 0))
	for i in 3:
		await get_tree().physics_frame
	var plain_from: Vector2 = plain_foe.global_position
	var plain: Meteor = (load("res://scene/projectiles/meteor.tscn") as PackedScene).instantiate()
	plain.explosion_damage = 50
	arena.add_child(plain)
	plain.global_position = o + Vector2(400, 0)
	plain.set_physics_process(false)
	await get_tree().physics_frame
	steps = 0
	while not plain.landed and steps < 200:
		plain.advance(1.0 / 60.0)
		steps += 1
		await get_tree().physics_frame
	check("a meteor that did not roll the pull draws nothing in",
		plain.pulled_count() == 0 and plain_foe.global_position == plain_from, plain_foe.global_position - plain_from)
	check("  and its ring of fire is the ordinary one, so a player can tell them apart",
		is_equal_approx(plain.swirl_from(), Meteor.SWIRL_FROM) and Meteor.SWIRL_FROM < Meteor.PULL_SWIRL_FROM)
	var rolled: int = 0
	for i in 100000:
		if Meteor.rolls_pull(randf()):
			rolled += 1
	check("one meteor in a hundred pulls", is_equal_approx(Meteor.PULL_CHANCE, 0.01)
		and Meteor.rolls_pull(0.0099) and not Meteor.rolls_pull(0.01)
		and rolled > 850 and rolled < 1150, rolled)
	var drop: String = _func_body(_code_src("res://src/characters/mage.gd"), "func _drop_meteor(")
	check("  rolled by the mage for each meteor it calls, before the meteor is built",
		drop.contains("Meteor.rolls_pull(randf())") and drop.contains("meteor.pulls =")
		and drop.find("meteor.pulls =") < drop.find("add_child(meteor)"))
	arena.free()


# THE DOUBLE AXE'S ROLL (0.18.0). The owner: "warrior 10% chance to expand
# area of attack / 1% chance to cause blood to spray we can just use particles
# to make the axe spin blood everywhere". Rolled apart for each throw.
func _test_the_axe_rolls() -> void:
	section("THE DOUBLE AXE'S ROLL - one throw in ten wide, one in a hundred bloody")
	var arena := Node2D.new()
	add_child(arena)
	var o := Vector2(-81000, -81000)
	var hand: Node2D = _weapon_hand(arena, o)
	var axe_at := func(at: Vector2, is_wide: bool, is_bloody: bool) -> SpinningAxe:
		var a: SpinningAxe = (load("res://scene/projectiles/spinningaxe.tscn") as PackedScene).instantiate()
		a.caster = hand
		a.wounds = false
		a.wide = is_wide
		a.bloody = is_bloody
		arena.add_child(a)
		a.set_physics_process(false)
		a.throw_to(at, at)
		a.advance(0.001)
		return a

	# WIDE: further, from the throw to the catch; no harder.
	check("one throw in ten is wide, reaching half as far again",
		is_equal_approx(SpinningAxe.WIDE_CHANCE, 0.10) and is_equal_approx(SpinningAxe.WIDE_REACH, 1.5)
		and SpinningAxe.rolls(0.0999, 0.10) and not SpinningAxe.rolls(0.10, 0.10))
	# Both inside LEASH of the hand, so neither comes home on its own.
	var plain_spot := o + Vector2(-60, 150)
	var wide_spot := o + Vector2(60, 150)
	var plain_axe: SpinningAxe = axe_at.call(plain_spot, false, false)
	var wide_axe: SpinningAxe = axe_at.call(wide_spot, true, false)
	# 30 px out: past a plain axe's 20 (and the dummy's 5), inside a wide one's.
	var by_plain: CharacterBody2D = _weapon_dummy(arena, plain_spot + Vector2(30, 0))
	var by_wide: CharacterBody2D = _weapon_dummy(arena, wide_spot + Vector2(30, 0))
	for i in 4:
		await get_tree().physics_frame
	plain_axe.advance(SpinningAxe.TICK_SECONDS)
	wide_axe.advance(SpinningAxe.TICK_SECONDS)
	check("  what stands just past a plain axe's reach is cut by a wide one",
		by_plain.taken.is_empty() and by_wide.taken.size() == 1, [by_plain.taken, by_wide.taken])
	check("  on its own circle, as wide as it reaches, and it grows with the spin from there",
		is_equal_approx(wide_axe.base_reach(), SpinningAxe.HIT_RADIUS * SpinningAxe.WIDE_REACH)
		and is_equal_approx((wide_axe.get_node("hitshape").shape as CircleShape2D).radius, wide_axe.reach())
		and is_equal_approx(plain_axe.base_reach(), SpinningAxe.HIT_RADIUS))
	var near_plain: CharacterBody2D = _weapon_dummy(arena, plain_spot + Vector2(0, 10))
	var near_wide: CharacterBody2D = _weapon_dummy(arena, wide_spot + Vector2(0, 10))
	for i in 4:
		await get_tree().physics_frame
	plain_axe.advance(SpinningAxe.TICK_SECONDS)
	wide_axe.advance(SpinningAxe.TICK_SECONDS)
	check("  and cuts no harder - the area is the roll, so the books are unchanged",
		near_plain.taken.size() == 1 and near_wide.taken == near_plain.taken, [near_plain.taken, near_wide.taken])
	wide_axe.recall()
	check("  still wide flying home", is_equal_approx(wide_axe.reach(), SpinningAxe.HIT_RADIUS * SpinningAxe.WIDE_REACH))

	# BLOODY: picture only.
	check("one throw in a hundred is bloody", is_equal_approx(SpinningAxe.BLOOD_CHANCE, 0.01)
		and SpinningAxe.rolls(0.0099, 0.01) and not SpinningAxe.rolls(0.01, 0.01))
	var red: SpinningAxe = axe_at.call(o + Vector2(0, -150), false, true)
	var blood: CPUParticles2D = red.get_node_or_null("blood")
	var spatter: CPUParticles2D = red.get_node_or_null("spatter")
	check("  a bloody axe flings blood as it spins, and spatters the ground round it",
		blood != null and spatter != null and blood.emitting and spatter.emitting
		and not blood.local_coords and not spatter.local_coords and spatter.z_index < 0)
	check("  a plain one has no blood at all", plain_axe.get_node_or_null("blood") == null
		and plain_axe.get_node_or_null("spatter") == null)
	check("  its wind runs red", (red.get_node("whirl") as CPUParticles2D).color_ramp.colors[1].r
		> (red.get_node("whirl") as CPUParticles2D).color_ramp.colors[1].g * 3.0)
	check("  and it is picture only: the cuts never ask whether it is bloody",
		not _func_body(_code_src("res://src/projectiles/spinningaxe.gd"), "func _cut(").contains("bloody")
		and not _func_body(_code_src("res://src/projectiles/spinningaxe.gd"), "func _cut_everything_near(").contains("bloody"))
	red.recall()
	check("  called back, the blood stops", blood != null and not blood.emitting and not spatter.emitting)

	# THE WARRIOR ROLLS BOTH, apart, for each throw.
	var rolled_wide: int = 0
	var rolled_blood: int = 0
	for i in 100000:
		if SpinningAxe.rolls(randf(), SpinningAxe.WIDE_CHANCE):
			rolled_wide += 1
		if SpinningAxe.rolls(randf(), SpinningAxe.BLOOD_CHANCE):
			rolled_blood += 1
	check("the dice agree: about 10,000 wide and 1,000 bloody in 100,000 throws",
		rolled_wide > 9400 and rolled_wide < 10600 and rolled_blood > 850 and rolled_blood < 1150,
		[rolled_wide, rolled_blood])
	var warrior: Node = (load("res://src/characters/warrior.gd") as GDScript).new()
	warrior._set_stat_curve()
	warrior.spawn_parent_override = arena
	warrior.equipped = {"weapon": "doubleaxe"}
	warrior.position = o + Vector2(0, 600)
	warrior.axe_wide_chance = 1.0
	warrior.axe_blood_chance = 1.0
	var both: SpinningAxe = warrior.throw_axe(warrior.position + Vector2(80, 0))
	check("the warrior rolls them for the throw, and one throw can be both",
		both != null and both.wide and both.bloody and both.get_node_or_null("blood") != null)
	var throw_src: String = _func_body(_code_src("res://src/characters/warrior.gd"), "func throw_axe(")
	check("  rolled before the axe is built, so its circle and its blood are made to match",
		throw_src.find("_axe.wide =") < throw_src.find("add_child(_axe)")
		and throw_src.find("_axe.bloody =") < throw_src.find("add_child(_axe)"))
	both.queue_free()
	warrior.free()
	arena.free()


# ALWAYS ROLL THE 1% (0.18.1) AND THE 10% (0.18.2). Owner switches on the
# Testing tab. The 1%: every meteor pulls, every axe throw is bloody, every
# Dynamite throw is five sticks - the owner, after not seeing two of them: "yes
# that sounds amazing". The 10%: every cast is two meteors, every axe throw is
# wide, every Dynamite throw is three - "do another switch for 10% casts".
func _test_the_rare_roll_switch() -> void:
	section("ALWAYS ROLL THE 1% AND THE 10% - the owner's switches for seeing the rolls")
	var was_role: String = Api.role
	var was_rare: bool = GameState.force_rare_rolls
	var was_common: bool = GameState.force_common_rolls
	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var rare: CheckButton = gm.get_node_or_null("%rarebutton") as CheckButton
	var common: CheckButton = gm.get_node_or_null("%commonbutton") as CheckButton
	var testing_tab: Node = gm.get_node_or_null("frame/margin/rows/tabsscroll/ownertabs/testing")
	check("the Testing tab has an \"Always roll the 1%\" switch and an \"Always roll the 10%\" one",
		rare != null and common != null and testing_tab != null and testing_tab.is_ancestor_of(rare)
		and testing_tab.is_ancestor_of(common) and rare.text.contains("1%") and common.text.contains("10%"))
	if rare == null or common == null:
		gm.queue_free()
		return

	var arena := Node2D.new()
	add_child(arena)
	var o := Vector2(-91000, -91000)
	var mage: Node = (load("res://src/characters/mage.gd") as GDScript).new()
	mage.spawn_parent_override = arena
	mage.equipped = {"weapon": "meteorite"}
	mage.double_cast_chance = 0.0
	mage.position = o
	var warrior: Node = (load("res://src/characters/warrior.gd") as GDScript).new()
	warrior._set_stat_curve()
	warrior.spawn_parent_override = arena
	warrior.equipped = {"weapon": "doubleaxe"}
	warrior.position = o + Vector2(0, 300)
	warrior.axe_blood_chance = 0.0
	warrior.axe_wide_chance = 0.0
	var tank: Node = (load("res://src/characters/tank.gd") as GDScript).new()
	tank._set_stat_curve()
	tank.level = 22
	tank.spawn_parent_override = arena
	tank.equipped = {"weapon": "dynamite"}
	tank.refresh_gear_stats()
	tank.position = o + Vector2(0, 600)
	tank.dynamite_bundle_chance = 0.0
	tank.dynamite_barrage_chance = 0.0
	# Every chance is zero, so whatever rolls, a switch made it.
	# ALL BUT ONE. The meteor's pull is Meteor.PULL_CHANCE, a constant, not a
	# var on the mage, so it cannot be set to zero like the rest - and one cast
	# in a hundred pulled on its own and failed a "nothing rolls" check about
	# one run in thirty (seen 11 Oct, in a run without the art pack). So the
	# dice are seeded before every roll here: none of the first forty draws of
	# pull_seed is under 0.01, so no pull happens unless a switch forces it.
	# randomize() puts the dice back at the end of the section.
	var pull_seed: int = 20261011
	var roll_all := func() -> Dictionary:
		seed(pull_seed)
		var met: Array = mage.call_meteor(o + Vector2(40, 0))
		var axe: SpinningAxe = warrior.throw_axe(warrior.position + Vector2(60, 0))
		tank.mana = 100
		tank._dynamite_cooldown_left = 0.0
		var sticks: Array = tank.throw_dynamite(tank.position + Vector2(0, 80))
		var rolled: Dictionary = {
			"meteors": met.size(),
			"pull": not met.is_empty() and met.all(func(m) -> bool: return (m as Meteor).pulls),
			"wide": axe != null and axe.wide,
			"blood": axe != null and axe.bloody,
			"sticks": sticks.size(),
		}
		for m in met:
			(m as Node).queue_free()
		if axe != null:
			axe.queue_free()
			warrior._axe = null
		for st in sticks:
			(st as Node).queue_free()
		return rolled
	var plain := {"meteors": 1, "pull": false, "wide": false, "blood": false, "sticks": 1}

	Api.role = "owner"
	GameState.force_rare_rolls = false
	GameState.force_common_rolls = false
	gm._sync_rare_button()
	var got: Dictionary = roll_all.call()
	check("  both off, with every chance at zero, nothing rolls", got == plain, got)
	rare.button_pressed = true
	got = roll_all.call()
	check("the 1% on: the meteor pulls, the axe bleeds, five sticks - and nothing of the 10%",
		GameState.force_rare_rolls and got == {"meteors": 1, "pull": true, "wide": false, "blood": true,
		"sticks": tank.DYNAMITE_BARRAGE_STICKS}, got)
	check("  and the panel says what it does", gm.results.get_parsed_text().contains("rare rolls ON"),
		gm.results.get_parsed_text())
	rare.button_pressed = false
	common.button_pressed = true
	got = roll_all.call()
	check("the 10% on: two meteors, a wide axe, three sticks - and nothing of the 1%",
		GameState.force_common_rolls and got == {"meteors": 2, "pull": false, "wide": true, "blood": false,
		"sticks": tank.DYNAMITE_BUNDLE_STICKS}, got)
	check("  and the panel says what it does", gm.results.get_parsed_text().contains("10% rolls ON"),
		gm.results.get_parsed_text())
	rare.button_pressed = true
	got = roll_all.call()
	check("both on: two meteors that both pull, a wide bloody axe, and the five - the rare one wins a throw",
		got == {"meteors": 2, "pull": true, "wide": true, "blood": true, "sticks": tank.DYNAMITE_BARRAGE_STICKS}, got)
	Api.role = "dev"
	got = roll_all.call()
	check("flags left on do nothing for anyone below the owner - the rank is read every roll", got == plain, got)
	gm._sync_rare_button()
	check("  and their switches are disabled", rare.disabled and common.disabled)
	rare.button_pressed = false
	common.button_pressed = false
	check("  turning them off from there is refused too - only the owner flips them",
		GameState.force_rare_rolls and GameState.force_common_rolls and rare.button_pressed and common.button_pressed)
	Api.role = "owner"
	gm._sync_rare_button()
	rare.button_pressed = false
	common.button_pressed = false
	got = roll_all.call()
	check("off again, back to the dice", not GameState.force_rare_rolls and not GameState.force_common_rolls
		and got == plain, got)
	var gs: String = FileAccess.get_file_as_string("res://src/systems/gamestate.gd")
	check("the flags live on GameState, which never survives a restart",
		gs.contains("var force_rare_rolls: bool = false") and gs.contains("var force_common_rolls: bool = false"))

	GameState.force_rare_rolls = was_rare
	GameState.force_common_rolls = was_common
	Api.role = was_role
	randomize()
	mage.free()
	warrior.free()
	tank.free()
	arena.queue_free()
	gm.queue_free()
	await get_tree().process_frame


func _test_the_mythic_weapons() -> void:
	section("MYTHIC WEAPONS - the meteor, the double axe and the dynamite")

	# --- THE ITEMS -----------------------------------------------------------
	check("the attacks are appended, never renumbered: NONE 0, METEOR 1, SPINNING_AXE 2, DYNAMITE 3",
		ItemData.WeaponAttack.NONE == 0 and ItemData.WeaponAttack.METEOR == 1
		and ItemData.WeaponAttack.SPINNING_AXE == 2 and ItemData.WeaponAttack.DYNAMITE == 3)
	var gamedata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/gamedata.json"))
	var exported: Dictionary = {}
	for row in gamedata.get("items", []):
		exported[str(row.get("item_id", ""))] = row
	for id in MYTHIC_WEAPONS:
		var want: Dictionary = MYTHIC_WEAPONS[id]
		var item: ItemData = ItemRegistry.get_item(id)
		check("%s is in the catalogue" % id, item != null)
		if item == null:
			continue
		# Ember read from the export, not the registry: ember's icons are in
		# the private pack, and a clone without it does not load those items.
		var ember: Dictionary = exported.get(want["ember"], {})
		# WORN FROM LEVEL 1 since 0.69.0 (it was 22): the general store gives
		# each class its own - see _test_the_shop_gives_the_mythics_away().
		check("  a tier 6 %s weapon from level 1, attack %d" % [want["class"], want["attack"]],
			item.tier == 6 and item.required_level == 1 and item.type == ItemData.Type.WEAPON
			and item.equip_slot == ItemData.EquipSlot.WEAPON and item.required_classes == [want["class"]]
			and int(item.weapon_attack) == int(want["attack"]),
			[item.tier, item.required_level, item.required_classes, item.weapon_attack])
		check("  a little above ember: more damage and a bigger bonus than %s" % want["ember"],
			not ember.is_empty() and item.damage > int(ember.get("damage", 0))
			and item.bonus_damage_percent > int(ember.get("bonus_damage_percent", 0)),
			[item.damage, ember.get("damage", -1)])
		check("  its icon is drawn %dx%d, whole pixels in the slot" % [want["icon"], want["icon"]],
			item.icon != null and item.icon.get_width() == want["icon"] and item.icon.get_height() == want["icon"])
		check("  its description says what attack does", item.description.contains("Your attack"), item.description)
		var row: Dictionary = exported.get(id, {})
		check("  and the server's catalogue agrees, so it can be worn",
			int(row.get("tier", 0)) == 6 and int(row.get("required_level", 0)) == 1
			and Array(row.get("required_classes", [])) == [want["class"]]
			and str(row.get("equip_slot_name", "")) == "WEAPON", row)

	# Not sold for gold, and no enemy's tier ladder reaches them. A mythic is a
	# roll of its own at every kill - see _test_mythic_drops(). The general
	# store GIVES them away (ShopData.free, 0.69.0), which is not the stock.
	var sold: Array = []
	var shops := DirAccess.open("res://data/shops")
	for file in shops.get_files():
		if file.ends_with(".tres"):
			var shop: Resource = load("res://data/shops/" + file)
			for id in MYTHIC_WEAPONS:
				if Array(shop.get("stock")).has(id):
					sold.append("%s sells %s" % [file, id])
	check("no shop sells them for gold", sold.is_empty(), sold)
	var droppers: Array = []
	var enemies_dir := DirAccess.open("res://data/enemies")
	for file in enemies_dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var enemy: EnemyData = load("res://data/enemies/" + file) as EnemyData
		if enemy == null:
			continue
		var odds: PackedFloat32Array = enemy.tier_odds
		var top_share: float = odds[0] if odds.size() > 0 else 0.15
		if (enemy.max_loot_tier >= 6 and top_share > 0.0) or (enemy.max_loot_tier >= 5 and enemy.tier_up_chance > 0.0):
			droppers.append(enemy.enemy_id)
	check("and no enemy's tier ladder can roll tier 6 - a mythic is its own roll", droppers.is_empty(), droppers)
	for id in ["meteor_impact", "axe_throw", "axe_catch", "dynamite_throw", "explosion"]:
		check("the %s sound has a slot waiting for its file" % id, Audio.SOUNDS.has(id))

	# Which attack each weapon gives, asked of a character built outside the tree.
	var mage: Node = (load("res://src/characters/mage.gd") as GDScript).new()
	var asked: Array = []
	for pair in [["", 0], ["emberstaff", 0], ["meteorite", 1], ["doubleaxe", 2], ["dynamite", 3]]:
		mage.equipped = {} if pair[0] == "" else {"weapon": pair[0]}
		asked.append(mage.equipped_weapon_attack() == pair[1])
	check("bare hands and ember keep the class attack; each mythic weapon brings its own",
		not asked.has(false), asked)

	var arena := Node2D.new()
	add_child(arena)
	var o := Vector2(9000, 9000)

	# --- THE METEOR ----------------------------------------------------------
	var inside: CharacterBody2D = _weapon_dummy(arena, o + Vector2(12, 0))
	var outside: CharacterBody2D = _weapon_dummy(arena, o + Vector2(Meteor.HIT_RADIUS + 12.0, 0))
	# Records the element too, for the fire the crater leaves.
	var fire_log := GDScript.new()
	fire_log.source_code = "extends CharacterBody2D\nvar taken: Array = []\n" \
		+ "func take_damage(amount: int, element: int = 0) -> void:\n\ttaken.append([amount, element])\n"
	fire_log.reload()
	var in_fire := CharacterBody2D.new()
	in_fire.set_script(fire_log)
	in_fire.collision_layer = 8
	in_fire.collision_mask = 0
	var in_fire_shape := CollisionShape2D.new()
	var in_fire_circle := CircleShape2D.new()
	in_fire_circle.radius = 5.0
	in_fire_shape.shape = in_fire_circle
	in_fire.add_child(in_fire_shape)
	in_fire.add_to_group("enemies")
	arena.add_child(in_fire)
	in_fire.global_position = o + Vector2(0, 20)
	var caster: Node2D = _weapon_hand(arena, o + Vector2(-100, 0))
	var meteor: Meteor = (load("res://scene/projectiles/meteor.tscn") as PackedScene).instantiate()
	meteor.explosion_damage = 50
	meteor.caster = caster
	arena.add_child(meteor)
	meteor.global_position = o
	meteor.set_physics_process(false)
	# FOUR FRAMES, NOT TWO. An Area2D added in the same frame as the body it
	# should see reports nothing for its first couple of physics steps -
	# measured here, where the first area of a fresh arena saw nobody after
	# two. In the game the meteor falls for forty-four frames first.
	for i in 4:
		await get_tree().physics_frame
	meteor.advance(Meteor.FALL_SECONDS * 0.5)
	check("halfway down the meteor is in the sky, up and to one side of where it lands",
		not meteor.landed and meteor.rock.visible and meteor.rock.position.y < -20.0 and meteor.rock.position.x < 0.0,
		meteor.rock.position)
	check("  its shadow is already on the ground, and nobody has been hit",
		meteor.shadow.visible and inside.taken.is_empty())
	# THE FIRE VORTEX (0.14.0). The owner: "can you add a fire vortex around the
	# meteo when it falls to really draw out that final fantasy effect".
	var swirl: CPUParticles2D = meteor.get_node_or_null("swirl")
	var whirl: CPUParticles2D = meteor.get_node_or_null("whirl")
	check("  wrapped in its fire vortex: ribbons round its path, sparks round the stone, fire swirling on a glowing ground",
		meteor.vortex_burning() and meteor.get_node_or_null("vortex") is Node2D
		and whirl != null and whirl.position == meteor.rock.position
		and meteor.get_node_or_null("floorglow") is Sprite2D and (meteor.get_node("floorglow") as Sprite2D).visible)
	check("  the ground's ring of fire swirling in from past the hit toward the landing spot",
		swirl != null and swirl.emission_sphere_radius < Meteor.HIT_RADIUS * Meteor.SWIRL_FROM
		and swirl.emission_sphere_radius > Meteor.HIT_RADIUS * Meteor.SWIRL_TO, swirl.emission_sphere_radius if swirl else -1.0)
	check("  the ribbons in the sky with the stone, over everything",
		(meteor.get_node("vortex") as Node2D).z_index == meteor.rock.z_index)
	meteor.advance(Meteor.FALL_SECONDS * 0.6)
	check("it lands, and the enemy inside its ring takes the hit once", meteor.landed and inside.taken == [50], inside.taken)
	check("  and the vortex goes out as it does - the blast takes over", not meteor.vortex_burning()
		and not (meteor.get_node("floorglow") as Sprite2D).visible)
	check("  the one outside the ring is not touched", outside.taken.is_empty(), outside.taken)
	check("  the caster is paid the stalagmite's magic XP for each enemy it hit (two are inside)",
		meteor.hit_count() == 2 and caster.magic_xp == Meteor.MAGIC_XP_ON_HIT * 2, [meteor.hit_count(), caster.magic_xp])
	check("  and the crater is where it landed, not where the world begins",
		_marks_at(arena, o) == 1 and get_tree().get_nodes_in_group("blastmarks").size() == 1)
	check("the stone stays in its crater, on the floor", meteor.rock.visible and meteor.rock.z_index == -1)
	check("the meteor is twice as wide as it was (0.12.0), and its shape matches its ring",
		is_equal_approx(Meteor.HIT_RADIUS, 44.0)
		and is_equal_approx((meteor.get_node("hitshape").shape as CircleShape2D).radius, Meteor.HIT_RADIUS))

	# THE BURNING CRATER (0.12.0). The owner: "leave burning crator with fire
	# damage", "fire effects on the ground where meteor hits", and no knockback.
	var craters: Array = arena.get_children().filter(func(n: Node) -> bool: return n is BurningCrater)
	check("where it lands, the crater burns, as wide as the hit", craters.size() == 1
		and (craters[0] as BurningCrater).global_position.distance_to(o) < 0.5
		and is_equal_approx((craters[0] as BurningCrater).radius, Meteor.HIT_RADIUS)
		and (craters[0] as BurningCrater).burning(), craters.size())
	if craters.size() == 1:
		var fire: BurningCrater = craters[0]
		fire.set_physics_process(false)
		for i in 4:
			await get_tree().physics_frame
		check("  with flames rising out of it and the ground glowing",
			fire.get_node_or_null("flames") is CPUParticles2D and (fire.get_node("flames") as CPUParticles2D).emitting
			and fire.get_node_or_null("glow") is Sprite2D and (fire.get_node("glow") as Sprite2D).visible)
		var stood_at: Vector2 = inside.global_position
		fire.advance(BurningCrater.BURN_EVERY)
		check("every half second it burns what stands in it for a fifth of the meteor's hit",
			inside.taken == [50, 10] and fire.burn_damage() == 10, inside.taken)
		check("  as fire", in_fire.taken.size() == 2 and in_fire.taken[1] == [10, Element.Type.FIRE], in_fire.taken)
		check("  not what stands outside it", outside.taken.is_empty(), outside.taken)
		check("  and nobody is pushed", inside.global_position == stood_at)
		var second: BurningCrater = BurningCrater.spawn(arena, o + Vector2(6, 0), 50, Meteor.HIT_RADIUS, caster)
		second.set_physics_process(false)
		for i in 4:
			await get_tree().physics_frame
		fire.advance(BurningCrater.BURN_EVERY)
		second.advance(BurningCrater.BURN_EVERY)
		check("two craters on one enemy burn it once a bite, not twice", inside.taken == [50, 10, 10], inside.taken)
		fire.advance(BurningCrater.BURN_SECONDS)
		check("it burns for BURN_SECONDS - five bites in all - then goes out",
			inside.taken.count(10) == 5 and not fire.burning()
			and not (fire.get_node("flames") as CPUParticles2D).emitting, inside.taken)
		second.advance(BurningCrater.BURN_EVERY)
		check("  and the other crater takes over the burn once it has", inside.taken.count(10) == 6, inside.taken)
		second.advance(BurningCrater.BURN_SECONDS)
		check("  until that one goes out too", inside.taken.count(10) == 6 + 3 and not second.burning(), inside.taken)
		second.queue_free()
		fire.queue_free()
	in_fire.queue_free()
	meteor.advance(Meteor.COOL_SECONDS + Meteor.FADE_SECONDS + 0.05)
	check("  then cools and is gone", meteor.is_queued_for_deletion())

	mage.spawn_parent_override = arena
	mage.equipped = {"weapon": "meteorite"}
	mage.double_cast_chance = 0.0
	var aim: Vector2 = o + Vector2(0, 200)
	var one: Array = mage.call_meteor(aim)
	check("a cast with the double-cast roll missed calls one meteor, where it was aimed",
		one.size() == 1 and one[0].global_position == aim and one[0].delay == 0.0 and one[0].caster == mage)
	check("  hitting for the staff formula with the Meteorite's damage in it",
		one.size() == 1 and one[0].explosion_damage > roundi(mage.damage_per_magic * mage.get_damage_multiplier()),
		one[0].explosion_damage if one.size() == 1 else -1)
	mage.double_cast_chance = 1.0
	var two: Array = mage.call_meteor(aim)
	var apart: float = two[1].global_position.distance_to(aim) if two.size() == 2 else -1.0
	check("a double cast calls two, the second beside the first rather than on it",
		two.size() == 2 and two[0].global_position == aim
		and apart >= mage.METEOR_SPREAD_MIN - 0.01 and apart <= mage.METEOR_SPREAD_MAX + 0.01, apart)
	check("  and a moment later, so they land one after the other",
		two.size() == 2 and is_equal_approx(two[1].delay, mage.METEOR_SECOND_DELAY))
	two[1].set_physics_process(false)
	two[1].advance(mage.METEOR_SECOND_DELAY * 0.5)
	check("  the second is not even in the sky until then", not two[1].rock.visible)
	check("the mage's cast calls the meteor in place of the stalagmite when one is worn",
		_func_body(_code_src("res://src/characters/mage.gd"), "func _cast_stalagmite_drop(").contains(
			"var meteor: bool = equipped_weapon_attack() == ItemData.WeaponAttack.METEOR\n\tif meteor:\n\t\tcall_meteor("))

	# --- THE DOUBLE AXE ------------------------------------------------------
	var row_y := o + Vector2(0, 500)
	var hand: Node2D = _weapon_hand(arena, row_y)
	var passed_by: CharacterBody2D = _weapon_dummy(arena, row_y + Vector2(60, 0))
	var at_spot: CharacterBody2D = _weapon_dummy(arena, row_y + Vector2(160, 0))
	var axe: SpinningAxe = (load("res://scene/projectiles/spinningaxe.tscn") as PackedScene).instantiate()
	axe.caster = hand
	# The cuts alone here; the wounds they leave are counted below (BLEED).
	axe.wounds = false
	arena.add_child(axe)
	axe.set_physics_process(false)
	axe.throw_to(hand.global_position, hand.global_position + Vector2(150, 0))
	var steps := 0
	while axe.state == SpinningAxe.State.OUT and steps < 200:
		await get_tree().physics_frame
		axe.advance(1.0 / 80.0)
		steps += 1
	check("thrown, the axe flies to the spot and starts spinning there",
		axe.state == SpinningAxe.State.SPINNING and axe.global_position.distance_to(row_y + Vector2(150, 0)) < 1.0,
		[axe.state, axe.global_position - row_y])
	check("  cutting what it passed on the way out, once, for a swing", passed_by.taken == [40], passed_by.taken)
	for i in 4:
		await get_tree().physics_frame
		axe.advance(SpinningAxe.TICK_SECONDS)
	check("spinning, it cuts what is near it every tick, for a tick's share of a swing",
		at_spot.taken == [40, 10, 10, 10, 10], at_spot.taken)
	check("  and nothing further away", passed_by.taken == [40], passed_by.taken)
	axe.recall()
	steps = 0
	while is_instance_valid(axe) and not axe.is_queued_for_deletion() and steps < 200:
		await get_tree().physics_frame
		axe.advance(1.0 / 80.0)
		steps += 1
	check("called back, it cuts what it passes on the way home too", passed_by.taken == [40, 40], passed_by.taken)
	check("  and the warrior catches it", hand.caught == 1 and (not is_instance_valid(axe) or axe.is_queued_for_deletion()))

	# SPIN UP (0.11.9). The owner: "double axe needs to speed up when left
	# deployed". Left spinning it climbs from 1x to SPIN_MAX_RATE over
	# SPIN_RAMP_SECONDS; each tick is still a tick's share of a swing, so it is
	# the number of cuts a second that climbs.
	var ramp_spot: CharacterBody2D = _weapon_dummy(arena, row_y + Vector2(100, -60))
	var ramp: SpinningAxe = (load("res://scene/projectiles/spinningaxe.tscn") as PackedScene).instantiate()
	ramp.caster = hand
	ramp.wounds = false
	arena.add_child(ramp)
	ramp.set_physics_process(false)
	ramp.throw_to(hand.global_position, ramp_spot.global_position)
	steps = 0
	while ramp.state == SpinningAxe.State.OUT and steps < 200:
		await get_tree().physics_frame
		ramp.advance(1.0 / 80.0)
		steps += 1
	await get_tree().physics_frame
	ramp_spot.taken.clear()
	check("it lands spinning at 1x", ramp.state == SpinningAxe.State.SPINNING
		and is_equal_approx(ramp.spin_rate(), 1.0), ramp.spin_rate())
	for i in 80:
		ramp.advance(1.0 / 80.0)
	var first_second: int = ramp_spot.taken.size()
	var climbing: float = ramp.spin_rate()
	for i in roundi((SpinningAxe.SPIN_RAMP_SECONDS - 1.0) * 80.0):
		ramp.advance(1.0 / 80.0)
	ramp_spot.taken.clear()
	for i in 80:
		ramp.advance(1.0 / 80.0)
	var top_second: int = ramp_spot.taken.size()
	check("its first second cuts about four times, as before", first_second >= 4 and first_second <= 5, first_second)
	check("  and it is climbing by the end of it", climbing > 1.0 and climbing < SpinningAxe.SPIN_MAX_RATE, climbing)
	check("after SPIN_RAMP_SECONDS it spins at SPIN_MAX_RATE, and holds there",
		is_equal_approx(ramp.spin_rate(), SpinningAxe.SPIN_MAX_RATE) and SpinningAxe.SPIN_MAX_RATE > 1.0,
		ramp.spin_rate())
	check("  cutting SPIN_MAX_RATE times as often", top_second == roundi(4.0 * SpinningAxe.SPIN_MAX_RATE),
		[top_second, first_second])
	check("  each cut still a tick's share of a swing", ramp_spot.taken.all(func(d) -> bool: return d == 10),
		ramp_spot.taken)
	check("  and the picture spins that much faster", is_equal_approx(ramp.spin.speed_scale, SpinningAxe.SPIN_MAX_RATE),
		ramp.spin.speed_scale)
	ramp.recall()
	check("called back, the picture slows to its own speed", is_equal_approx(ramp.spin.speed_scale, 1.0))
	ramp.throw_to(hand.global_position, ramp_spot.global_position + Vector2(10, 0))
	ramp.state = SpinningAxe.State.SPINNING
	check("  and a new throw starts again at 1x", is_equal_approx(ramp.spin_rate(), 1.0), ramp.spin_rate())
	ramp.queue_free()
	ramp_spot.queue_free()

	# THE WHIRLWIND (0.14.0). The owner: "we need to add a effect to double axe
	# also to give it that feel". Its reach grows with the spin, on its own
	# copy of the circle, and the wind is drawn.
	var gust_at: Vector2 = row_y + Vector2(0, 150)
	var rim: CharacterBody2D = _weapon_dummy(arena, gust_at + Vector2(SpinningAxe.HIT_RADIUS + 8.0, 0))
	var gust: SpinningAxe = (load("res://scene/projectiles/spinningaxe.tscn") as PackedScene).instantiate()
	gust.caster = hand
	gust.wounds = false
	arena.add_child(gust)
	gust.set_physics_process(false)
	var circle: CircleShape2D = (gust.get_node("hitshape") as CollisionShape2D).shape
	var shared: CircleShape2D = ((load("res://scene/projectiles/spinningaxe.tscn") as PackedScene).instantiate().get_node("hitshape") as CollisionShape2D).shape
	check("each axe cuts with its own circle, not the one the scene shares", circle != shared
		and is_equal_approx(circle.radius, SpinningAxe.HIT_RADIUS) and is_equal_approx(shared.radius, SpinningAxe.HIT_RADIUS),
		[circle.radius, shared.radius])
	gust.throw_to(gust_at, gust_at)
	gust.advance(0.001)
	for i in 4:
		await get_tree().physics_frame
	check("it lands with its own reach, and the wind is up", gust.state == SpinningAxe.State.SPINNING
		and is_equal_approx(gust.reach(), SpinningAxe.HIT_RADIUS) and (gust.get_node("whirl") as CPUParticles2D).emitting,
		gust.reach())
	for i in 4:
		gust.advance(SpinningAxe.TICK_SECONDS * 0.99)
	check("  what stands just past that reach is not cut at 1x", rim.taken.is_empty(), rim.taken)
	for i in roundi(SpinningAxe.SPIN_RAMP_SECONDS * 20.0):
		gust.advance(0.05)
	for i in 4:
		await get_tree().physics_frame
	rim.taken.clear()
	gust.advance(SpinningAxe.TICK_SECONDS)
	check("at the top of the spin its reach is REACH_AT_TOP times as far, on its circle",
		is_equal_approx(gust.reach(), SpinningAxe.HIT_RADIUS * SpinningAxe.REACH_AT_TOP) and SpinningAxe.REACH_AT_TOP > 1.0
		and is_equal_approx(circle.radius, gust.reach()), [gust.reach(), circle.radius])
	check("  and cuts what stands there", not rim.taken.is_empty(), rim.taken)
	check("  the scene's own circle is untouched", is_equal_approx(shared.radius, SpinningAxe.HIT_RADIUS), shared.radius)
	check("  the dust is swept round the rim, faster with the spin",
		is_equal_approx((gust.get_node("whirl") as CPUParticles2D).emission_sphere_radius, gust.reach())
		and (gust.get_node("whirl") as CPUParticles2D).orbit_velocity_min >= 0.7 * SpinningAxe.SPIN_MAX_RATE - 0.01)
	check("  and the streaks are drawn by the axe itself, while it spins",
		_func_body(_code_src("res://src/projectiles/spinningaxe.gd"), "func _draw(").contains("draw_arc("))
	gust.recall()
	check("called back, it is back to its own reach and the wind drops",
		is_equal_approx(gust.reach(), SpinningAxe.HIT_RADIUS) and is_equal_approx(circle.radius, SpinningAxe.HIT_RADIUS)
		and not (gust.get_node("whirl") as CPUParticles2D).emitting, [gust.reach(), circle.radius])
	gust.queue_free()
	rim.queue_free()

	# THE BLEED (0.14.0). Every cut opens a wound: BLEED_SHARE of a swing every
	# BLEED_EVERY for BLEED_SECONDS after the last cut, one wound per enemy.
	var cut_at: Vector2 = row_y + Vector2(0, 300)
	var bled: CharacterBody2D = _weapon_dummy(arena, cut_at)
	var slicer: SpinningAxe = (load("res://scene/projectiles/spinningaxe.tscn") as PackedScene).instantiate()
	slicer.caster = hand
	arena.add_child(slicer)
	slicer.set_physics_process(false)
	slicer.throw_to(cut_at, cut_at)
	slicer.advance(0.001)
	for i in 4:
		await get_tree().physics_frame
	slicer.advance(SpinningAxe.TICK_SECONDS)
	var wounds: Array = bled.get_children().filter(func(n: Node) -> bool: return n is Bleed)
	for w in wounds:
		(w as Bleed).set_physics_process(false)
	check("a cut opens a wound on what it cut, a quarter of the swing it was part of",
		wounds.size() == 1 and (wounds[0] as Bleed).bite == roundi(40 * Bleed.BLEED_SHARE)
		and (wounds[0] as Bleed).bleeding(), [wounds.size(), bled.taken])
	check("  with red drops falling from it", wounds.size() == 1
		and (wounds[0] as Bleed).get_node_or_null("drops") is CPUParticles2D
		and ((wounds[0] as Bleed).get_node("drops") as CPUParticles2D).emitting)
	slicer.advance(SpinningAxe.TICK_SECONDS)
	slicer.advance(SpinningAxe.TICK_SECONDS)
	var still: Array = bled.get_children().filter(func(n: Node) -> bool: return n is Bleed)
	check("  more cuts keep the one wound open rather than opening another", still.size() == 1, still.size())
	if wounds.size() == 1:
		var wound: Bleed = wounds[0]
		slicer.queue_free()
		var cuts: int = bled.taken.size()
		wound.advance(Bleed.BLEED_EVERY)
		check("every BLEED_EVERY seconds it bleeds the enemy for its bite",
			bled.taken.size() == cuts + 1 and bled.taken[-1] == wound.bite, bled.taken)
		wound.advance(Bleed.BLEED_SECONDS * 3.0)
		check("  for BLEED_SECONDS after the last cut, then it closes",
			not wound.bleeding() and wound.bites_dealt == roundi(Bleed.BLEED_SECONDS / Bleed.BLEED_EVERY),
			[wound.bites_dealt, bled.taken])
		check("  and the drops stop", not (wound.get_node("drops") as CPUParticles2D).emitting)
		var reopened: Bleed = Bleed.open(bled, 40, hand)
		check("a cut after it has closed opens a new one", reopened != null and reopened != wound and reopened.bleeding())
		if reopened != null:
			reopened.set_physics_process(false)
			reopened.queue_free()
	bled.queue_free()

	var far_throw: SpinningAxe = (load("res://scene/projectiles/spinningaxe.tscn") as PackedScene).instantiate()
	far_throw.caster = hand
	arena.add_child(far_throw)
	far_throw.set_physics_process(false)
	far_throw.throw_to(hand.global_position, hand.global_position + Vector2(0, 1000))
	check("a spot too far is taken as a direction: it goes as far as a throw goes",
		is_equal_approx(far_throw.target.distance_to(hand.global_position), SpinningAxe.MAX_THROW))
	far_throw.state = SpinningAxe.State.SPINNING
	hand.global_position = far_throw.global_position + Vector2(SpinningAxe.LEASH + 5.0, 0)
	far_throw.advance(0.01)
	check("walk off past the leash and it comes home on its own", far_throw.state == SpinningAxe.State.RETURNING)
	far_throw.state = SpinningAxe.State.SPINNING
	hand.global_position = far_throw.global_position + Vector2(20, 0)
	hand.afk = true
	far_throw.advance(0.01)
	check("go away from the keyboard and it comes home - no axe left grinding a spawn",
		far_throw.state == SpinningAxe.State.RETURNING)
	hand.afk = false
	hand.is_dying = true
	far_throw.advance(0.01)
	check("die and it is simply gone", far_throw.is_queued_for_deletion())
	hand.is_dying = false

	var wall := StaticBody2D.new()
	wall.collision_layer = 2
	var wall_shape := CollisionShape2D.new()
	var wall_rect := RectangleShape2D.new()
	wall_rect.size = Vector2(8, 200)
	wall_shape.shape = wall_rect
	wall.add_child(wall_shape)
	arena.add_child(wall)
	wall.global_position = hand.global_position + Vector2(80, 0)
	var stopped: SpinningAxe = (load("res://scene/projectiles/spinningaxe.tscn") as PackedScene).instantiate()
	stopped.caster = hand
	arena.add_child(stopped)
	stopped.set_physics_process(false)
	stopped.throw_to(hand.global_position, hand.global_position + Vector2(150, 0))
	steps = 0
	while stopped.state == SpinningAxe.State.OUT and steps < 200:
		await get_tree().physics_frame
		stopped.advance(1.0 / 80.0)
		steps += 1
	check("thrown at a wall, it stops at the wall and spins there rather than passing through",
		stopped.state == SpinningAxe.State.SPINNING and stopped.global_position.x < wall.global_position.x,
		stopped.global_position - hand.global_position)
	stopped.queue_free()

	var warrior: Node = (load("res://src/characters/warrior.gd") as GDScript).new()
	warrior._set_stat_curve()
	warrior.spawn_parent_override = arena
	warrior.equipped = {"weapon": "doubleaxe"}
	warrior.position = o + Vector2(0, 800)
	warrior.axe_wide_chance = 0.0
	warrior.axe_blood_chance = 0.0
	var thrown: SpinningAxe = warrior.throw_axe(warrior.position + Vector2(100, 0))
	check("the warrior throws one axe, at the spot", thrown != null and warrior.axe_is_out()
		and thrown.caster == warrior and thrown.target == warrior.position + Vector2(100, 0))
	check("  and only one: asking again while it is out hands back the same axe",
		warrior.throw_axe(warrior.position + Vector2(0, 100)) == thrown)
	warrior.attack_action()
	check("attack while it is out calls it back", thrown.state == SpinningAxe.State.RETURNING)
	var attack_src: String = _func_body(_code_src("res://src/characters/warrior.gd"), "func attack_action(")
	check("  and the swing that throws it carries no hitbox and no slash wave",
		attack_src.contains("_swing_hitbox = null") and attack_src.contains("_wave_spawned_this_swing = true")
		and attack_src.contains("throw_axe("))
	warrior.equipped = {}
	warrior.refresh_gear_stats()
	check("taking the axe off while it is out takes it out of the world",
		not warrior.axe_is_out() and thrown.is_queued_for_deletion())

	# --- THE DYNAMITE --------------------------------------------------------
	var land := o + Vector2(0, 1100)
	var near_blast: CharacterBody2D = _weapon_dummy(arena, land + Vector2(15, 0))
	var past_blast: CharacterBody2D = _weapon_dummy(arena, land + Vector2(Dynamite.HIT_RADIUS + 10.0, 0))
	var stick: Dynamite = (load("res://scene/projectiles/dynamite.tscn") as PackedScene).instantiate()
	stick.explosion_damage = 30
	arena.add_child(stick)
	stick.set_physics_process(false)
	stick.throw_from(land + Vector2(-120, 0), land)
	stick.advance(Dynamite.FLIGHT_SECONDS * 0.5)
	check("halfway there the stick is in the air above its shadow, partway along",
		stick.state == Dynamite.State.FLYING and stick.stick.position.y < -15.0
		and stick.global_position.x > land.x - 120.0 and stick.global_position.x < land.x,
		[stick.stick.position, stick.global_position - land])
	stick.advance(Dynamite.FLIGHT_SECONDS * 0.5 + 0.01)
	check("it lands where it was thrown and lies there, fuse lit",
		stick.state == Dynamite.State.FUSE and stick.global_position == land and stick.stick.position.y > -5.0)
	for i in 4:
		await get_tree().physics_frame
	stick.advance(0.5)
	check("  the fuse burns - half a second on, nothing has been hit yet", not stick.exploded and near_blast.taken.is_empty())
	stick.advance(Dynamite.FUSE_SECONDS)
	check("then it goes off: the enemy inside the blast is hit once", stick.exploded and near_blast.taken == [30], near_blast.taken)
	check("  the one outside it is not", past_blast.taken.is_empty(), past_blast.taken)
	check("  and the scorch is where it went off", _marks_at(arena, land) == 1)
	check("the blast is the meteor's size since 0.14.0, and its shape matches its ring",
		is_equal_approx(Dynamite.HIT_RADIUS, Meteor.HIT_RADIUS) and Dynamite.CHAIN_RADIUS >= Dynamite.HIT_RADIUS * 1.5 - 0.01
		and is_equal_approx(((load("res://scene/projectiles/dynamite.tscn") as PackedScene).instantiate().get_node("hitshape").shape as CircleShape2D).radius,
			Dynamite.HIT_RADIUS))

	# THE SMOULDER (0.13.0). The owner: "we need some sort of bonus damage for
	# tnt like a field effect". The scorch keeps biting for FIELD_SECONDS.
	var smoulders: Array = arena.get_children().filter(func(n: Node) -> bool:
		return n is BurningCrater and (n as BurningCrater).smoulder)
	check("the blast leaves its scorch smouldering, as wide as the blast", smoulders.size() == 1
		and (smoulders[0] as BurningCrater).global_position == land
		and is_equal_approx((smoulders[0] as BurningCrater).radius, Dynamite.HIT_RADIUS)
		and (smoulders[0] as BurningCrater).burning(), smoulders.size())
	if smoulders.size() == 1:
		var smoke: BurningCrater = smoulders[0]
		smoke.set_physics_process(false)
		for i in 4:
			await get_tree().physics_frame
		check("  smoke and sparks rising from it, not the meteor's flames",
			smoke.get_node_or_null("flames") is CPUParticles2D and smoke.get_node_or_null("embers") is CPUParticles2D
			and smoke.name == "smoulder")
		smoke.advance(Dynamite.FIELD_EVERY)
		check("every half second it bites what stands in it for FIELD_SHARE of the stick's hit",
			near_blast.taken == [30, roundi(30 * Dynamite.FIELD_SHARE)] and smoke.burn_damage() == roundi(30 * Dynamite.FIELD_SHARE),
			near_blast.taken)
		check("  not what stands outside it", past_blast.taken.is_empty(), past_blast.taken)
		check("  and it keeps its own mark, apart from a meteor's crater - two players' fires",
			smoke.owner_meta != &"burning_by" and near_blast.has_meta(smoke.owner_meta))
		smoke.advance(Dynamite.FIELD_SECONDS)
		check("  FIELD_SECONDS of bites, then it goes out",
			near_blast.taken.size() == 1 + roundi(Dynamite.FIELD_SECONDS / Dynamite.FIELD_EVERY) and not smoke.burning(),
			near_blast.taken)
		smoke.queue_free()

	# CHAIN REACTION (0.12.0). The owner: "chain reaction sounds cool". A blast
	# sets off every lit stick within CHAIN_RADIUS, CHAIN_DELAY later and
	# CHAIN_BONUS harder; one further away, or still in the air, is not.
	var chain_at := o + Vector2(0, 1250)
	var lay := func(spot: Vector2) -> Dynamite:
		var d: Dynamite = (load("res://scene/projectiles/dynamite.tscn") as PackedScene).instantiate()
		d.explosion_damage = 40
		arena.add_child(d)
		d.set_physics_process(false)
		d.throw_from(spot - Vector2(0, 60), spot)
		d.advance(Dynamite.FLIGHT_SECONDS + 0.01)
		return d
	var first: Dynamite = lay.call(chain_at)
	var chained_stick: Dynamite = lay.call(chain_at + Vector2(Dynamite.CHAIN_RADIUS - 2.0, 0))
	var far_one: Dynamite = lay.call(chain_at + Vector2(Dynamite.CHAIN_RADIUS * 2.0 + 10.0, 0))
	var by_first: CharacterBody2D = _weapon_dummy(arena, chain_at + Vector2(-15, 0))
	var by_second: CharacterBody2D = _weapon_dummy(arena, chained_stick.global_position + Vector2(15, 0))
	var by_far: CharacterBody2D = _weapon_dummy(arena, far_one.global_position + Vector2(15, 0))
	var in_air: Dynamite = (load("res://scene/projectiles/dynamite.tscn") as PackedScene).instantiate()
	in_air.explosion_damage = 40
	arena.add_child(in_air)
	in_air.set_physics_process(false)
	in_air.throw_from(chain_at + Vector2(0, 90), chain_at + Vector2(0, 10))
	in_air.advance(Dynamite.FLIGHT_SECONDS * 0.5)
	for i in 4:
		await get_tree().physics_frame
	check("three sticks lie lit, a fourth is in the air",
		[first, chained_stick, far_one].all(func(d: Dynamite) -> bool: return d.state == Dynamite.State.FUSE)
		and in_air.state == Dynamite.State.FLYING)
	first.explode()
	check("one goes off and hits what it reaches, as ever", first.exploded and by_first.taken == [40], by_first.taken)
	check("  and sets off the lit stick beside it - not at once, a beat later",
		chained_stick.chained and not chained_stick.exploded and by_second.taken.is_empty())
	check("  but not the stick further away", not far_one.chained, far_one.global_position - chain_at)
	check("  nor the one still in the air", not in_air.chained)
	chained_stick.advance(Dynamite.CHAIN_DELAY + 0.01)
	check("the chained stick goes off, CHAIN_BONUS harder",
		chained_stick.exploded and by_second.taken == [roundi(40 * (1.0 + Dynamite.CHAIN_BONUS))], by_second.taken)
	check("  and what is beyond its reach is still untouched", not far_one.exploded and by_far.taken.is_empty(), by_far.taken)
	chained_stick.set_off()
	check("a stick already gone cannot be set off again", by_second.taken.size() == 1)
	var tank_scene: Node = (load("res://scene/characters/tank.tscn") as PackedScene).instantiate()
	check("the fuse outlasts a throw, so the next stick at one spot lands while the last still burns",
		Dynamite.FUSE_SECONDS > float(tank_scene.get("dynamite_cooldown")), tank_scene.get("dynamite_cooldown"))
	tank_scene.free()
	far_one.queue_free()
	in_air.queue_free()
	by_first.queue_free()
	by_second.queue_free()
	by_far.queue_free()

	var tank: Node = (load("res://src/characters/tank.gd") as GDScript).new()
	tank._set_stat_curve()
	tank.level = 22
	tank.spawn_parent_override = arena
	tank.equipped = {"weapon": "dynamite"}
	tank.refresh_gear_stats()
	tank.mana = 100
	tank.position = o + Vector2(0, 1400)
	tank.dynamite_bundle_chance = 0.0
	tank.dynamite_barrage_chance = 0.0
	check("the ring is out until the first throw", not tank.aura_active)
	var sticks: Array = tank.throw_dynamite(tank.position + Vector2(1000, 0))
	check("the tank throws one stick, as far as a throw goes, for its mana",
		sticks.size() == 1 and sticks[0].landing_spot() == tank.position + Vector2(tank.DYNAMITE_MAX_THROW, 0)
		and tank.mana == 100 - tank.dynamite_mana_cost,
		[sticks.size(), tank.mana])
	check("  worth dynamite_stick_ticks ring ticks, with the Dynamite's damage in them - more than one tick",
		sticks.size() == 1 and tank.dynamite_stick_ticks > 1.0
		and sticks[0].explosion_damage >= roundi(tank.aura_damage * tank.get_damage_multiplier() * tank.dynamite_stick_ticks),
		sticks[0].explosion_damage if sticks.size() == 1 else -1)
	check("  and not again until the cooldown is over",
		tank.throw_dynamite(tank.position + Vector2(50, 0)).is_empty() and tank.mana == 100 - tank.dynamite_mana_cost)
	check("faster than a throw a second (0.14.0)", tank.dynamite_cooldown < 1.0, tank.dynamite_cooldown)

	# DYNAMITE'S MANA, A SHARE OF THE BAR (0.59.0). The owner: "if players
	# wanna spam they can waste magic potions", and of the throws a full bar
	# gives, "much less then 10 ... if even 3 people have these weps could
	# break the game". 3 a throw was 137 throws on a level-22 bar.
	var bar_22: int = PlayerStats.max_for(tank.mana_base, tank.mana_per_lvl, 22)
	check("a throw costs a fifth of the mana the tank has at its level - 82 at level 22, the Dynamite's own",
		tank.DYNAMITE_THROWS_PER_BAR == 5 and bar_22 == 410 and tank.dynamite_mana_cost == 82,
		[tank.dynamite_mana_cost, bar_22])
	var per_level: Array = []
	for lv in [1, 22, 32, 47, 99]:
		var bar: int = PlayerStats.max_for(tank.mana_base, tank.mana_per_lvl, lv)
		var cost: int = tank.dynamite_mana_cost_at(tank.mana_base, tank.mana_per_lvl, lv)
		per_level.append([lv, bar, cost, floori(float(bar) / float(cost))])
	check("  so a full bar is DYNAMITE_THROWS_PER_BAR throws at every level, the price climbing with it",
		per_level.all(func(row: Array) -> bool: return row[3] == tank.DYNAMITE_THROWS_PER_BAR)
		and per_level[1][2] < per_level[2][2] and per_level[2][2] < per_level[3][2], per_level)
	var cost_before_gear: int = tank.dynamite_mana_cost
	tank.max_mana += 80
	check("  priced on the level's bar, not the gear's: mana gear is spare, never a dearer throw",
		tank.dynamite_mana_cost == cost_before_gear, [tank.dynamite_mana_cost, cost_before_gear])
	tank.max_mana -= 80
	check("  and a throw the bar cannot pay for is refused at that price, spending nothing - a potion buys it back",
		_func_body(_code_src("res://src/characters/tank.gd"), "func throw_dynamite(").contains("if mana < dynamite_mana_cost:"))

	# THE RING (0.14.0). The owner: "use tank ring". A throw lights it; it
	# burns no mana of its own, and goes out DYNAMITE_RING_LINGER after the
	# last throw.
	check("the throw lit the ring, the Dynamite's way", tank.aura_active and tank.ring_by_dynamite)
	var mana_lit: int = tank.mana
	tank._tick_aura(tank.DYNAMITE_RING_LINGER * 0.5)
	check("  it burns no mana of its own - the throws pay for it",
		tank.aura_active and tank.mana == mana_lit, tank.mana)
	tank._dynamite_cooldown_left = 0.0
	tank.mana = 100
	tank.throw_dynamite(tank.position + Vector2(60, 0))
	tank._tick_aura(tank.DYNAMITE_RING_LINGER * 0.75)
	check("  each throw keeps it lit", tank.aura_active and tank.ring_by_dynamite)
	tank._tick_aura(tank.DYNAMITE_RING_LINGER * 0.5)
	check("  and it goes out a little after the last one", not tank.aura_active and not tank.ring_by_dynamite)

	# THE ROLL (0.18.0). The owner: "10% chance to toss 3 dynamite / 1% chance
	# to toss 5 sticks". One roll a throw; the every-fifth bundle and the double
	# are gone.
	check("one throw in ten is a bundle of three, one in a hundred a barrage of five, the rest one stick",
		is_equal_approx(tank.DYNAMITE_BUNDLE_CHANCE, 0.10) and is_equal_approx(tank.DYNAMITE_BARRAGE_CHANCE, 0.01)
		and tank.DYNAMITE_BUNDLE_STICKS == 3 and tank.DYNAMITE_BARRAGE_STICKS == 5
		and tank.sticks_for(0.0099, 0.01, 0.10) == 5 and tank.sticks_for(0.01, 0.01, 0.10) == 3
		and tank.sticks_for(0.1099, 0.01, 0.10) == 3 and tank.sticks_for(0.11, 0.01, 0.10) == 1)
	var roll_counts: Dictionary = {1: 0, 3: 0, 5: 0}
	for i in 100000:
		var n: int = tank.sticks_for(randf(), tank.DYNAMITE_BARRAGE_CHANCE, tank.DYNAMITE_BUNDLE_CHANCE)
		roll_counts[n] = int(roll_counts.get(n, 0)) + 1
	check("  and the dice agree: about 10,000 bundles and 1,000 barrages in 100,000 throws",
		roll_counts[3] > 9400 and roll_counts[3] < 10600 and roll_counts[5] > 850 and roll_counts[5] < 1150
		and roll_counts.size() == 3, roll_counts)
	check("  no double any more - the throw does not ask for one",
		not _func_body(_code_src("res://src/characters/tank.gd"), "func throw_dynamite(").contains("rolls_double"))

	# THE BUNDLE: three sticks in a triangle, close enough that the first sets
	# off the rest.
	tank._dynamite_cooldown_left = 0.0
	tank.mana = 100
	tank.dynamite_bundle_chance = 1.0
	var bundle_aim: Vector2 = tank.position + Vector2(0, 120)
	var bundle: Array = tank.throw_dynamite(bundle_aim)
	for d in bundle:
		(d as Dynamite).set_physics_process(false)
	var bundle_spots: Array = bundle.map(func(d): return (d as Dynamite).landing_spot())
	check("a bundle is DYNAMITE_BUNDLE_STICKS sticks round the aim",
		bundle.size() == tank.DYNAMITE_BUNDLE_STICKS
		and bundle_spots.all(func(p: Vector2) -> bool: return absf(p.distance_to(bundle_aim) - tank.DYNAMITE_BUNDLE_SPREAD) < 0.01),
		bundle_spots)
	check("  each a beat behind the last, for one throw's mana",
		bundle.size() == 3 and bundle[0].delay == 0.0 and is_equal_approx(bundle[1].delay, tank.DYNAMITE_SECOND_DELAY)
		and is_equal_approx(bundle[2].delay, tank.DYNAMITE_SECOND_DELAY * 2.0) and tank.mana == 100 - tank.dynamite_mana_cost)
	var middle: CharacterBody2D = _weapon_dummy(arena, bundle_aim)
	for d in bundle:
		(d as Dynamite).advance((d as Dynamite).delay + Dynamite.FLIGHT_SECONDS + 0.01)
	for i in 4:
		await get_tree().physics_frame
	check("  all three land lit", bundle.all(func(d) -> bool: return (d as Dynamite).state == Dynamite.State.FUSE))
	(bundle[0] as Dynamite).explode()
	for d in bundle.slice(1):
		(d as Dynamite).advance(Dynamite.CHAIN_DELAY + 0.01)
	var expected_bites: Array = [bundle[0].explosion_damage,
		roundi(bundle[1].explosion_damage * (1.0 + Dynamite.CHAIN_BONUS)), roundi(bundle[2].explosion_damage * (1.0 + Dynamite.CHAIN_BONUS))]
	check("  the first sets off the other two, and what stands in the middle is hit by all three, two of them chained",
		middle.taken == expected_bites, [middle.taken, expected_bites])
	middle.queue_free()

	# THE BARRAGE: five, in a wider ring, still going up as one.
	tank._dynamite_cooldown_left = 0.0
	tank.mana = 100
	tank.dynamite_bundle_chance = 0.0
	tank.dynamite_barrage_chance = 1.0
	var barrage_aim: Vector2 = tank.position + Vector2(0, -120)
	var barrage: Array = tank.throw_dynamite(barrage_aim)
	for d in barrage:
		(d as Dynamite).set_physics_process(false)
	var barrage_spots: Array = barrage.map(func(d): return (d as Dynamite).landing_spot())
	check("a barrage is DYNAMITE_BARRAGE_STICKS sticks in a wider ring round the aim, for one throw's mana",
		barrage.size() == tank.DYNAMITE_BARRAGE_STICKS and tank.DYNAMITE_BARRAGE_SPREAD > tank.DYNAMITE_BUNDLE_SPREAD
		and barrage_spots.all(func(p: Vector2) -> bool: return absf(p.distance_to(barrage_aim) - tank.DYNAMITE_BARRAGE_SPREAD) < 0.01)
		and tank.mana == 100 - tank.dynamite_mana_cost, barrage_spots)
	var nearest_apart: float = INF
	for a in barrage_spots:
		for b in barrage_spots:
			if a != b:
				nearest_apart = minf(nearest_apart, (a as Vector2).distance_to(b))
	check("  each within CHAIN_RADIUS of its neighbours, so the first sets off the ring",
		nearest_apart <= Dynamite.CHAIN_RADIUS, nearest_apart)
	for d in barrage:
		(d as Dynamite).queue_free()
	tank.dynamite_barrage_chance = 0.0

	# THE GEAR AND THE RING.
	tank._deactivate_aura()
	tank.equipped = {}
	tank.refresh_gear_stats()
	tank._activate_aura()
	check("without Dynamite the aura key lights the ring as ever, paid by the second",
		tank.aura_active and not tank.ring_by_dynamite)
	tank.equipped = {"weapon": "dynamite"}
	tank.refresh_gear_stats()
	check("Dynamite put on while that ring burns puts it out - attack no longer reaches it", not tank.aura_active)
	tank._dynamite_cooldown_left = 0.0
	tank.mana = 100
	tank.throw_dynamite(tank.position + Vector2(40, 0))
	check("  the next throw lights it the Dynamite's way", tank.aura_active and tank.ring_by_dynamite)
	tank.equipped = {}
	tank.refresh_gear_stats()
	check("taken off, the ring its throws lit goes out - nothing would be paying for it",
		not tank.aura_active and not tank.ring_by_dynamite)
	check("attack throws dynamite instead of toggling the aura when it is worn",
		_func_body(_code_src("res://src/characters/tank.gd"), "func attack_action(").contains(
			"if equipped_weapon_attack() == ItemData.WeaponAttack.DYNAMITE:\n\t\tthrow_dynamite("))
	check("  and the cooldown runs down in the tank's own loop",
		_func_body(_code_src("res://src/characters/tank.gd"), "func _physics_process(").contains("_dynamite_cooldown_left"))

	arena.queue_free()
	await get_tree().process_frame
	mage.free()
	warrior.free()
	tank.free()
	print("  mythic weapons: three items, the meteor, the axe out and home, the dynamite, double casts")


# =============================================================================
# THE OWNER'S ITEM MENU - every item, one click, and the level to wear it
# =============================================================================
# Day 2: "i need these items as hot keys so i can test - can you create a menu
# in hud that allows me to select and spawn items registered in the game that
# only owner can use". And, because the weapons it was for need level 22, the
# owner's own level, set on the server. Driven here through the panel's own
# doors: post_request, adopt_bag, equip_request and apply_level are Callables
# the suite swaps for stubs that write down what they were asked.

func _test_mythic_drops() -> void:
	section("MYTHIC DROPS - any enemy, the tougher the better, and a moment when one lands")

	# --- THE ODDS --------------------------------------------------------------
	# Day 2, the owner: regular mobs and bosses both drop the mythic weapons,
	# "mixed rarity but it should be super rewarding getting 1". The server
	# rolls (gamedata.roll_mythic); the game authors the odds and exports them.
	check("the mythic tier is 6", GameConstants.MYTHIC_TIER == 6
		and GameConstants.rarity_name(GameConstants.MYTHIC_TIER) == "Mythic")
	var boss_table: Dictionary = GameConstants.MYTHIC_ODDS_BOSS_BY_TIER
	var table: Dictionary = GameConstants.MYTHIC_ODDS_BY_TIER
	check("every boss rate beats every regular rate",
		boss_table.values().max() < table.values().min(), [boss_table, table])
	var tiers: Array = table.keys()
	tiers.sort()
	var ordered: bool = tiers == [1, 2, 3, 4, 5]
	for i in range(1, tiers.size()):
		ordered = ordered and int(table[tiers[i]]) < int(table[tiers[i - 1]])
	check("every band has a rate, and a higher band always has the better odds", ordered, table)
	check("a mythic bag stays longer than any other, and inside the server's 600 seconds",
		GameConstants.MYTHIC_BAG_DESPAWN_SECONDS > GameConstants.LOOT_BAG_DESPAWN_SECONDS
		and GameConstants.MYTHIC_BAG_DESPAWN_SECONDS < 600.0, GameConstants.MYTHIC_BAG_DESPAWN_SECONDS)

	var rule := EnemyData.new()
	rule.max_loot_tier = 3
	var normal_odds: int = rule.mythic_odds()
	rule.slots_are_gear = true
	rule.max_loot_tier = 5
	var boss_odds: int = rule.mythic_odds()
	rule.mythic_odds_override = 150
	var override_odds: int = rule.mythic_odds()
	rule.grants_rewards = false
	var unpaid_odds: int = rule.mythic_odds()
	var beyond := EnemyData.new()
	beyond.max_loot_tier = 9
	check("EnemyData.mythic_odds(): the regular table by tier", normal_odds == int(table[3]), normal_odds)
	check("  the boss table for a boss", boss_odds == int(boss_table[5]), boss_odds)
	check("  the override over either", override_odds == 150, override_odds)
	check("  never for an enemy that pays nothing", unpaid_odds == 0, unpaid_odds)
	check("  and never for a tier the tables do not name", beyond.mythic_odds() == 0, beyond.mythic_odds())

	# The authored enemies, against the export the server reads.
	var gamedata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/gamedata.json"))
	var rows: Dictionary = {}
	for row in gamedata.get("enemies", []):
		rows[str(row.get("enemy_id", ""))] = row
	var stale: Array = []
	var unpaid: Array = []
	var best_id: String = ""
	var best: int = 0
	var enemies_dir := DirAccess.open("res://data/enemies")
	for file in enemies_dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var enemy: EnemyData = load("res://data/enemies/" + file) as EnemyData
		if enemy == null:
			continue
		var odds: int = enemy.mythic_odds()
		if int(rows.get(enemy.enemy_id, {}).get("mythic_odds", -1)) != odds:
			stale.append("%s: %d here, %s exported" % [enemy.enemy_id, odds, rows.get(enemy.enemy_id, {}).get("mythic_odds", "none")])
		if enemy.grants_rewards and odds <= 0:
			unpaid.append(enemy.enemy_id)
		if odds > 0 and (best == 0 or odds < best):
			best = odds
			best_id = enemy.enemy_id
	check("the export the server reads has every enemy's mythic odds, and they are current", stale.is_empty(), stale)
	check("every enemy that pays rewards can drop one", unpaid.is_empty(), unpaid)
	check("the Crowned is the best hunt in the game", best_id == "boss", [best_id, best])
	check("and the export names the tier they pay from",
		int(gamedata.get("constants", {}).get("mythic_tier", 0)) == GameConstants.MYTHIC_TIER)

	# --- THE BAG -------------------------------------------------------------
	var bag_scene: PackedScene = load("res://scene/interactables/lootbag.tscn") as PackedScene
	var plain: Node = bag_scene.instantiate()
	add_child(plain)
	var bag: Node = bag_scene.instantiate()
	add_child(bag)
	await get_tree().process_frame
	check("an ordinary bag stays %d seconds" % int(GameConstants.LOOT_BAG_DESPAWN_SECONDS),
		is_equal_approx(plain.despawn_timer.wait_time, GameConstants.LOOT_BAG_DESPAWN_SECONDS)
		and not plain.is_mythic(), plain.despawn_timer.wait_time)
	plain.free()
	bag.set_contents([{"item_id": "meteorite", "quantity": 1}])
	bag.despawn_timer.paused = true
	bag.set_mythic(true)
	check("a mythic bag stays five minutes", is_equal_approx(bag.despawn_timer.wait_time,
		GameConstants.MYTHIC_BAG_DESPAWN_SECONDS) and not bag.despawn_timer.is_stopped(), bag.despawn_timer.wait_time)
	check("  and a pause the open panel put on it holds", bag.despawn_timer.paused)
	check("  it glows mythic red", bag.glow_tier() == GameConstants.MYTHIC_TIER, bag.glow_tier())
	var pillar: Sprite2D = bag.get_node_or_null("rareglow/pillar") as Sprite2D
	check("  with the pillar raised high above the sack", pillar != null and pillar.scale == bag.MYTHIC_GLOW_SCALE
		and pillar.position.y < -bag.GLOW_PILLAR_HEIGHT, ("%s at %s" % [pillar.scale, pillar.position]) if pillar != null else "no pillar")
	check("  and a burst of sparks as it lands", bag.get_node_or_null("mythicsparks") is CPUParticles2D)
	bag.set_contents([null])
	check("taking the mythic out ends the show", not bag.is_mythic() and bag.glow_tier() == 0)
	bag.free()

	# --- THE FINDER'S MOMENT -------------------------------------------------
	# Combat._spawn_loot_bag() with the answer a mythic kill gets. A HUD and a
	# player stand in as stubs that remember what they were asked.
	for old in get_tree().get_nodes_in_group(&"lootbags"):
		old.free()
	var stub_script := GDScript.new()
	stub_script.source_code = "extends Node2D\nvar banners: Array = []\nvar shakes: Array = []\n" \
		+ "func show_mythic_banner(title: String, line: String, flash: bool = false) -> void:\n" \
		+ "\tbanners.append([title, line, flash])\n" \
		+ "func shake_camera(strength: float, seconds: float) -> void:\n" \
		+ "\tshakes.append([strength, seconds])\n"
	stub_script.reload()
	var hud_stub := Node2D.new()
	hud_stub.set_script(stub_script)
	add_child(hud_stub)
	hud_stub.add_to_group("hud")
	var finder := Node2D.new()
	finder.set_script(stub_script)
	add_child(finder)
	var hud_first: bool = get_tree().get_first_node_in_group("hud") == hud_stub
	check("(the stub is the HUD Combat finds)", hud_first)
	Combat._spawn_loot_bag({"bag_id": "mythictest", "mythic": "meteorite",
		"contents": [{"position": 0, "item_id": "meteorite", "quantity": 1}]}, finder, Vector2(40, 40))
	var spawned: Node = null
	for node in get_tree().get_nodes_in_group(&"lootbags"):
		if node.has_method("get_bag_id") and node.get_bag_id() == "mythictest":
			spawned = node
	check("a mythic kill's bag is a mythic bag", spawned != null and spawned.is_mythic())
	check("the finder gets the MYTHIC DROP banner, naming the piece, with the flash",
		hud_first and hud_stub.banners == [["MYTHIC DROP!", "Meteorite", true]], hud_stub.banners)
	check("  and a camera shake harder than any weapon's",
		finder.shakes == [[Combat.MYTHIC_SHAKE_STRENGTH, Combat.MYTHIC_SHAKE_SECONDS]]
		and Combat.MYTHIC_SHAKE_STRENGTH > 3.0, finder.shakes)
	var combat_src: String = FileAccess.get_file_as_string("res://src/systems/combat.gd")
	check("  and the mythic_drop sound", _first_code_index(combat_src, "Audio.play(\"mythic_drop\")", 0) != -1
		and Audio.SOUNDS.has("mythic_drop"))
	if spawned != null:
		spawned.free()
	Combat._spawn_loot_bag({"bag_id": "plaintest",
		"contents": [{"position": 0, "item_id": "meteorite", "quantity": 1}]}, finder, Vector2(40, 40))
	var ordinary: Node = null
	for node in get_tree().get_nodes_in_group(&"lootbags"):
		if node.has_method("get_bag_id") and node.get_bag_id() == "plaintest":
			ordinary = node
	check("a kill the server did not name a mythic gets no show",
		ordinary != null and not ordinary.is_mythic() and hud_stub.banners.size() == 1, hud_stub.banners)
	if ordinary != null:
		ordinary.free()
	hud_stub.free()
	finder.free()

	# --- EVERYONE ELSE -------------------------------------------------------
	var was_name: String = Api.username
	Api.username = "watcher"
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	hud._build_message_box()
	var red: Color = GameConstants.rarity_colour(GameConstants.MYTHIC_TIER)
	var said: String = "Tunacan found the Meteorite on The Crowned Beholder!"
	hud._read_broadcast_messages([{"kind": "mythic", "body": said, "by": "Tunacan", "at": 1700000000}], true)
	var banner: Control = hud.mythic_banner
	check("a find by somebody else puts the red banner up for everyone online",
		banner != null and (banner.get_node("rows/title") as Label).text == "MYTHIC FOUND"
		and (banner.get_node("rows/line") as Label).text == said, banner)
	check("  with no flash - that is the finder's", banner != null and banner.get_node_or_null("flash") == null)
	var last: Variant = hud._unlogged_lines.back() if not hud._unlogged_lines.is_empty() else null
	check("  and writes it into chat in the mythic red",
		last is Dictionary and last["text"] == said and last["color"] == red and int(last["at"]) == 1700000000, last)
	check("  without a second box popping under the banner", hud.message_rows.get_child_count() == 0,
		hud.message_rows.get_child_count())
	banner.free()
	hud.mythic_banner = null
	hud._read_broadcast_messages([{"kind": "mythic", "body": "watcher found the Dynamite on a Light Slime!",
		"by": "watcher", "at": 1700000001}], true)
	check("your own find is only written into chat - your game already celebrated",
		hud.mythic_banner == null and hud._unlogged_lines.back()["color"] == red)
	hud._read_broadcast_messages([{"kind": "mythic", "body": said, "by": "Tunacan", "at": 1600000000}], false)
	check("an old find a first poll catches up on is not announced", hud.mythic_banner == null)
	hud._read_broadcast_messages([{"kind": "system", "body": "Server restarting soon.", "by": "boss", "at": 1700000002}], true)
	check("an ordinary notice is still gold, with no banner",
		hud.mythic_banner == null and hud._unlogged_lines.back()["color"] == Color(1.0, 0.82, 0.42))
	hud.free()
	Api.username = was_name


func _test_the_item_menu() -> void:
	section("THE ITEM MENU - the owner's whole catalogue, spawned and worn")

	# BY PATH, NOT BY class_name. A class_name is known to a headless run only
	# after the editor has rescanned (see "A brand-new class_name is invisible
	# until the editor rescans" in CLAUDE.md), and this file naming ItemSpawner
	# made the whole suite fail to compile on a checkout the editor had not
	# opened since the menu arrived. A preload resolves by path either way.
	const Spawner := preload("res://src/ui/owner/itemspawner.gd")

	var packed: PackedScene = load("res://scene/ui/owner/itemspawner.tscn") as PackedScene
	check("itemspawner.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate():
		return
	var was_owner: bool = Api.is_owner
	var was_role: String = Api.role
	Api.is_owner = true
	Api.role = "owner"
	var menu: Control = packed.instantiate() as Control
	add_child(menu)
	await get_tree().process_frame
	check("it is a window of its own", menu.get("_window") != null)

	# --- WHERE EVERYTHING IS LISTED ---
	var T := ItemData.Type
	var S := ItemData.EquipSlot
	var kinds: Array = [
		[_menu_item("w", T.WEAPON, S.WEAPON), "Weapons"],
		[_menu_item("h", T.ARMOR, S.HELM), "Armour"],
		[_menu_item("s", T.ARMOR, S.SHIELD), "Armour"],
		[_menu_item("a", T.ARMOR, S.AMULET), "Jewellery"],
		[_menu_item("r", T.ARMOR, S.RING), "Jewellery"],
		[_menu_item("p", T.CONSUMABLE, S.NONE, 99), "Potions and food"],
		[_menu_item("pet", T.PET), "Pets"],
		[_menu_item("fish", T.FISH), "Fishing"],
		[_menu_item("ironfishingrod", T.MATERIAL), "Fishing"],
		[_menu_item("fishingworm", T.MATERIAL, S.NONE, 99), "Fishing"],
		[_menu_item("coin", T.CURRENCY), "Currency"],
		[_menu_item("trophy", T.ARMOR, S.NONE), "Other"],
	]
	var wrong: Array = []
	for pair in kinds:
		if Spawner.category_of(pair[0]) != pair[1]:
			wrong.append("%s -> %s" % [pair[0].item_id, Spawner.category_of(pair[0])])
	check("every item is listed under what it is", wrong.is_empty(), wrong)
	check("  and every kind it can be is one of the menu's",
		kinds.all(func(pair): return Spawner.CATEGORIES.has(pair[1])))

	menu.search.text = ""
	menu.category.select(0)
	menu.refresh()
	var everything: int = ItemRegistry.get_all_items().size()
	check("All lists every item the registry loaded", menu.listed().size() == everything
		and menu.grid.get_child_count() == everything, [menu.listed().size(), everything])
	menu.search.text = "METEOR"
	menu.refresh()
	var found: Array = menu.listed().map(func(i): return i.item_id)
	check("the search reads names and ids, any case", found.has("meteorite"), found)
	menu.search.text = "double axe"
	menu.refresh()
	found = menu.listed().map(func(i): return i.item_id)
	check("  and every word of it", found == ["doubleaxe"], found)
	menu.search.text = "doubleaxe"
	menu.refresh()
	found = menu.listed().map(func(i): return i.item_id)
	check("  and the id the server and the logs call it by", found == ["doubleaxe"], found)
	menu.search.text = ""
	menu.category.select(Spawner.CATEGORIES.find("Weapons"))
	menu.refresh()
	check("a kind lists that kind and nothing else",
		not menu.listed().is_empty() and menu.listed().all(func(i): return i.type == ItemData.Type.WEAPON))
	var tiers: Array = menu.listed().map(func(i): return i.tier)
	var sorted_tiers: Array = tiers.duplicate()
	sorted_tiers.sort()
	check("  cheapest first, the mythic weapons last", tiers == sorted_tiers, tiers)
	var axe_cell: Button = menu.grid.get_node_or_null("doubleaxe") as Button
	check("a cell shows the item's picture and says what it is",
		axe_cell != null and axe_cell.icon != null and axe_cell.tooltip_text.contains("Double Axe")
		and axe_cell.tooltip_text.contains("Needs warrior") and axe_cell.tooltip_text.contains("id: doubleaxe"),
		axe_cell.tooltip_text if axe_cell != null else "")
	check("one click spawns it", axe_cell != null and axe_cell.pressed.get_connections().size() > 0)

	check("a sword comes one at a time, however many are asked for",
		Spawner.quantity_for(_menu_item("w", T.WEAPON, S.WEAPON), 40) == 1)
	check("  and potions up to their stack, never past it",
		Spawner.quantity_for(_menu_item("p", T.CONSUMABLE, S.NONE, 99), 40) == 40
		and Spawner.quantity_for(_menu_item("p", T.CONSUMABLE, S.NONE, 99), 500) == 99)

	# --- SPAWNING, through the stubs ---
	var asked: Array = []
	var adopted: Array = []
	var equipped: Array = []
	var answer: Array = [{"ok": true, "data": {"inventory": [null, {"item_id": "doubleaxe", "quantity": 1}],
		"carry_positions": [1]}}]
	menu.post_request = func(path: String, body: Dictionary) -> Dictionary:
		asked.append([path, body])
		await get_tree().process_frame
		return answer[0]
	menu.adopt_bag = func(slot_index: int, bag_cells: Array) -> void:
		adopted.append([slot_index, bag_cells])
	menu.equip_request = func(id: String, cell: int) -> bool:
		equipped.append([id, cell])
		return true

	menu.quantity.value = 5
	# A frame, as a player's next click is: the box's text follows its value a
	# frame late, and typed_quantity() reads the text.
	await get_tree().process_frame
	menu.wear_toggle.button_pressed = true
	await menu.spawn("doubleaxe")
	check("a click asks the server for it: the grant route, this character, one axe",
		asked.size() == 1 and asked[0][0] == "/api/staff/grant" and asked[0][1].get("item_id") == "doubleaxe"
		and asked[0][1].get("quantity") == 1 and asked[0][1].get("slot") == CharacterData.active_character_index,
		asked)
	check("  the bag the server sends back is adopted", adopted.size() == 1 and adopted[0][1].size() == 2)
	check("  and the axe is put on from the cell it landed in", equipped == [["doubleaxe", 1]], equipped)
	check("  and the menu says so", menu.status.text == "Added Double Axe and put it on.", menu.status.text)

	menu.wear_toggle.button_pressed = false
	await menu.spawn("doubleaxe")
	check("with \"put gear on\" off, it only goes in the bag",
		equipped.size() == 1 and menu.status.text == "Added 1 × Double Axe to your bag.", menu.status.text)
	# A potion of the suite's own, registered for the moment: the real ones'
	# pictures are in the private art pack, and a clone without it does not
	# load them.
	var potion: ItemData = _menu_item("menutest_potion", T.CONSUMABLE, S.NONE, 99)
	ItemRegistry._items[potion.item_id] = potion
	menu.wear_toggle.button_pressed = true
	await menu.spawn("menutest_potion")
	ItemRegistry._items.erase(potion.item_id)
	check("something that is not gear is never put on, and comes as many as asked",
		equipped.size() == 1 and asked[-1][1].get("item_id") == "menutest_potion"
		and asked[-1][1].get("quantity") == 5, [equipped, asked[-1]])

	# A NUMBER TYPED AND NOT ENTERED STILL COUNTS. A SpinBox keeps typed text
	# in its LineEdit until Enter or the box loses focus, and the cells take no
	# focus - so "7" typed and a potion clicked asked for whatever the box held
	# before. The same thing sent the owner's typed level 99 as the 29 already
	# in the box (5 Oct, on play.elusionrpg.com).
	ItemRegistry._items[potion.item_id] = potion
	menu.quantity.get_line_edit().text = "7"
	await menu.spawn("menutest_potion")
	ItemRegistry._items.erase(potion.item_id)
	check("a number typed into How many and not entered is the number asked for",
		asked[-1][1].get("quantity") == 7, asked[-1])

	answer[0] = {"ok": false, "status": 409, "error": "Your backpack is full."}
	var adopted_before: int = adopted.size()
	await menu.spawn("meteorite")
	check("a refusal is said in the server's words, and nothing is adopted",
		menu.status.text == "Your backpack is full." and adopted.size() == adopted_before, menu.status.text)

	Api.is_owner = false
	var asked_before: int = asked.size()
	await menu.spawn("meteorite")
	check("anyone but the owner is told it is the owner's, and nothing is asked",
		asked.size() == asked_before and menu.status.text.contains("owner"), menu.status.text)
	Api.is_owner = true

	# THE LEVEL LIVES IN THE GM PANEL'S TESTING TAB NOW, with the other things
	# the owner does to their own character (_test_the_gm_panel_sets_a_level).
	check("the level is not set from here any more - it is the GM panel's",
		menu.get_node_or_null("%levelbox") == null and not menu.has_method("set_level"))

	# --- THE CHARACTER'S HALF ---
	var warrior: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	warrior._set_stat_curve()
	warrior.equipped = {}
	warrior.level = 3
	warrior.hp = 5
	warrior.apply_server_level({"level": 22, "xp": 0, "xp_to_next": 777, "hp": 9999, "mana": 3, "stamina": 40})
	check("a character copies a level the server set: level, XP and the next step",
		warrior.level == 22 and warrior.xp == 0 and warrior.xp_next == 777)
	check("  the maxima follow the level, and the pools are the server's, never over the maxima",
		warrior.max_hp == PlayerStats.max_for(warrior.hp_base, warrior.hp_per_lvl, 22)
		and warrior.hp == warrior.max_hp and warrior.mana == 3 and warrior.stamina == 40, [warrior.hp, warrior.max_hp])
	warrior.free()

	var said: Array = []
	var listener := func(r): said.append(r)
	CharacterData.carry_adopted.connect(listener)
	var saved_slots = CharacterData.character_slots.duplicate(true)
	var saved_index: int = CharacterData.active_character_index
	CharacterData.character_slots = [{"character": "warrior", "inventory": []}, null, null, null]
	CharacterData.active_character_index = 0
	var cells: Array = [{"item_id": "doubleaxe", "quantity": 1}, null]
	var landed: bool = CharacterData.adopt_granted_bag(0, cells, null)
	var bag = CharacterData.character_slots[0].get("inventory", [])
	CharacterData.carry_adopted.disconnect(listener)
	CharacterData.character_slots = saved_slots
	CharacterData.active_character_index = saved_index
	check("the granted bag lands on the character", landed and bag is Array and bag.size() == 2
		and bag[0] is Dictionary and bag[0].get("item_id") == "doubleaxe")
	check("  without \"your backpack was updated by the server\" - you asked", said.is_empty(), said)

	# --- THE DOOR, on the real HUD built out of the tree ---
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	var row: Control = hud.get_node_or_null("%staffrow") as Control
	Api.role = "mod"
	Api.is_owner = false
	hud._add_owner_button()
	check("a mod has no Items button", row != null and not row.has_node("itemsbutton"))
	Api.role = "owner"
	Api.is_owner = true
	hud._add_owner_button()
	check("and nor does the owner any more - it opens from the GM panel's Testing tab",
		row != null and row.has_node("ownerbutton") and not row.has_node("itemsbutton"))
	check("  where a button opens it, through the HUD that owns it",
		FileAccess.get_file_as_string("res://scene/ui/owner/ownerpanel.tscn").contains("[node name=\"cataloguebutton\"")
		and _code_only(FileAccess.get_file_as_string("res://src/ui/owner/ownerpanel.gd")).contains("hud.toggle_item_spawner()"))
	hud.item_spawner = menu
	menu.visible = true
	check("Escape counts the menu as open", hud.is_panel_open())
	hud.hide_panel()
	check("  and closes it", not menu.visible)
	hud.item_spawner = null
	hud.free()

	menu.queue_free()
	Api.is_owner = was_owner
	Api.role = was_role
	await get_tree().process_frame
	print("  item menu: every item, searchable, spawned and worn, as many as typed; owner only")


# =============================================================================
# THE GM PANEL SETS YOUR LEVEL
# =============================================================================
# 5 Oct, on play.elusionrpg.com: the owner typed 99 into the Items window's
# level box, pressed Set level, and was told "Level 29, from 29". A SpinBox
# keeps typed text in its LineEdit until Enter or until it loses focus, and the
# button took no focus, so the request carried the 29 already in the box. The
# owner's call, the same day: the level belongs in the GM panel, under Testing,
# beside the gold and the item rows - which are plain LineEdits, read as typed
# at the moment the button is pressed.

func _test_the_gm_panel_sets_a_level() -> void:
	section("GM PANEL - Testing sets your level, as typed")

	var packed: PackedScene = load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene
	var panel: Control = packed.instantiate() as Control
	add_child(panel)
	await get_tree().process_frame

	var box: LineEdit = panel.get_node_or_null("%levelinput") as LineEdit
	var button: Button = panel.get_node_or_null("%levelbutton") as Button
	var testing: Node = panel.get_node_or_null("frame/margin/rows/tabsscroll/ownertabs/testing")
	check("the Testing tab has a level box and a Set level button",
		box != null and button != null and testing != null
		and testing.is_ancestor_of(box) and testing.is_ancestor_of(button))
	if box == null or button == null:
		panel.queue_free()
		return
	check("  the button sends it, and so does Enter in the box",
		button.pressed.get_connections().size() > 0 and box.text_submitted.get_connections().size() > 0)

	var asked: Array = []
	var applied: Array = []
	var answer: Array = [{"ok": true, "data": {"level": 99, "was": 29, "xp": 0, "xp_to_next": 12,
		"hp": 900, "mana": 800, "stamina": 300}}]
	panel.post_request = func(path: String, body: Dictionary) -> Dictionary:
		asked.append([path, body])
		await get_tree().process_frame
		return answer[0]
	panel.apply_level = func(data: Dictionary) -> void:
		applied.append(data)
	var was_owner: bool = Api.is_owner
	Api.is_owner = true

	# THE CATALOGUE BUTTON opens the HUD's item window. A stand-in HUD in the
	# group, so the press can be counted without building the real one.
	var catalogue: Button = panel.get_node_or_null("%cataloguebutton") as Button
	check("the Testing tab opens the item catalogue",
		catalogue != null and testing.is_ancestor_of(catalogue)
		and catalogue.pressed.get_connections().size() > 0)
	var hud_shape := GDScript.new()
	hud_shape.source_code = "extends Node\nvar opened: int = 0\nfunc toggle_item_spawner() -> void:\n\topened += 1\n"
	hud_shape.reload()
	var stand_in := Node.new()
	stand_in.set_script(hud_shape)
	add_child(stand_in)
	stand_in.add_to_group("hud")
	if catalogue != null:
		catalogue.pressed.emit()
	check("  pressing it asks the HUD to open it", stand_in.get("opened") == 1, stand_in.get("opened"))
	stand_in.queue_free()

	# TYPED, NOT ENTERED, THEN PRESSED - exactly what failed.
	box.text = "99"
	await panel._on_level_pressed()
	check("a level typed and not entered is the level asked for: the owner's route, this character",
		asked.size() == 1 and asked[0][0] == "/api/staff/level" and asked[0][1].get("level") == 99
		and asked[0][1].get("slot") == CharacterData.active_character_index, asked)
	check("  the character takes the server's answer", applied.size() == 1 and applied[0].get("level") == 99)
	check("  and the panel says what changed",
		panel.results != null and panel.results.get_parsed_text().contains("Level 99, from 29"),
		panel.results.get_parsed_text() if panel.results != null else "")

	for bad in ["", "abc", "0", "-5", "2.5"]:
		box.text = bad
		await panel._on_level_pressed()
	check("an empty box, words, 0, a minus and a fraction are refused here, and nothing is asked",
		asked.size() == 1, asked.size())
	check("  and the box holds two digits, so 100 cannot be typed (the server's top is %d)" % panel.LEVEL_MAX,
		box.max_length == 2 and panel.LEVEL_MAX == 99)

	answer[0] = {"ok": false, "status": 400, "error": "level must be 1-99"}
	box.text = "50"
	await panel._on_level_pressed()
	check("a refusal is said in the server's words, and nothing is applied",
		applied.size() == 1 and panel.results.get_parsed_text().contains("level must be 1-99"))

	Api.is_owner = false
	box.text = "50"
	var asked_before: int = asked.size()
	await panel._on_level_pressed()
	check("anyone but the owner is told it is the owner's, and nothing is asked",
		asked.size() == asked_before and panel.results.get_parsed_text().contains("owner's"))
	Api.is_owner = was_owner

	panel.queue_free()
	await get_tree().process_frame
	print("  the GM panel's Testing tab sets your level, read as typed, owner only")


func _test_the_gm_panel_sets_skills() -> void:
	section("GM PANEL - Testing sets your skill levels, one or all six")

	# The owner, 6 Oct: "i want full control of my stats in admin panel so i can
	# do more testing". The level row's twin, for the six skills.
	var packed: PackedScene = load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene
	var panel: Control = packed.instantiate() as Control
	add_child(panel)
	await get_tree().process_frame

	var pick: OptionButton = panel.get_node_or_null("%skillpick") as OptionButton
	var box: LineEdit = panel.get_node_or_null("%skillinput") as LineEdit
	var button: Button = panel.get_node_or_null("%skillbutton") as Button
	var testing: Node = panel.get_node_or_null("frame/margin/rows/tabsscroll/ownertabs/testing")
	check("the Testing tab has a skill picker, a level box and a Set skill button",
		pick != null and box != null and button != null and testing != null
		and testing.is_ancestor_of(pick) and testing.is_ancestor_of(box) and testing.is_ancestor_of(button))
	if pick == null or box == null or button == null:
		panel.queue_free()
		return
	check("  the button sends it, and so does Enter in the box",
		button.pressed.get_connections().size() > 0 and box.text_submitted.get_connections().size() > 0)

	var ids: Array = []
	for i in pick.item_count:
		ids.append(str(pick.get_item_metadata(i)))
	var six: Array = GameConstants.SKILL_XP_GROWTH.keys()
	var named: Array = ids.slice(1)
	named.sort()
	six.sort()
	check("  it offers all six skills by the names the game and the server use, and \"all\" first",
		ids.size() == 7 and ids[0] == "all" and named == six, ids)
	check("  and opens on all of them", panel.chosen_skill() == "all", panel.chosen_skill())

	var asked: Array = []
	var applied: Array = []
	var answer: Array = [{"ok": true, "data": {"slot": 0, "level": 40,
		"skills": {"agility": {"level": 40, "xp": 0, "xp_next": 900, "was": 7}}}}]
	panel.post_request = func(path: String, body: Dictionary) -> Dictionary:
		asked.append([path, body])
		await get_tree().process_frame
		return answer[0]
	panel.apply_skills = func(data: Dictionary) -> void:
		applied.append(data)
	var was_owner: bool = Api.is_owner
	Api.is_owner = true

	pick.select(ids.find("agility"))
	box.text = "40"
	await panel._on_skill_pressed()
	check("the skill picked and the level typed are what is asked: the owner's route, this character",
		asked.size() == 1 and asked[0][0] == "/api/staff/skill" and asked[0][1].get("skill") == "agility"
		and asked[0][1].get("level") == 40 and asked[0][1].get("slot") == CharacterData.active_character_index,
		asked)
	check("  the character takes the server's answer", applied.size() == 1
		and applied[0].get("skills", {}).has("agility"))
	check("  and the panel says what changed",
		panel.results != null and panel.results.get_parsed_text().contains("Agility 40, from 7"),
		panel.results.get_parsed_text() if panel.results != null else "")

	answer[0] = {"ok": true, "data": {"slot": 0, "level": 99, "skills": {}}}
	pick.select(0)
	box.text = "99"
	await panel._on_skill_pressed()
	check("\"all\" asks for every skill at once, and says so",
		asked.size() == 2 and asked[1][1].get("skill") == "all"
		and panel.results.get_parsed_text().contains("Every skill is level 99"), asked)

	for bad in ["", "abc", "0", "-5", "2.5"]:
		box.text = bad
		await panel._on_skill_pressed()
	check("an empty box, words, 0, a minus and a fraction are refused here, and nothing is asked",
		asked.size() == 2, asked.size())
	check("  and the box holds two digits, so 100 cannot be typed (the server's top is %d)" % panel.SKILL_MAX,
		box.max_length == 2 and panel.SKILL_MAX == 99)

	answer[0] = {"ok": false, "status": 400, "error": "level must be 1-99"}
	box.text = "50"
	await panel._on_skill_pressed()
	check("a refusal is said in the server's words, and nothing is applied",
		applied.size() == 2 and panel.results.get_parsed_text().contains("level must be 1-99"))

	Api.is_owner = false
	box.text = "50"
	var asked_before: int = asked.size()
	await panel._on_skill_pressed()
	check("anyone but the owner is told it is the owner's, and nothing is asked",
		asked.size() == asked_before and panel.results.get_parsed_text().contains("owner's"))
	Api.is_owner = was_owner
	panel.queue_free()

	# --- THE CHARACTER'S HALF ---
	var warrior: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	warrior.attack = 2
	warrior.attack_xp = 55
	warrior.cooking = 4
	warrior.apply_server_skills({"skills": {
		"attack": {"level": 60, "xp": 0, "xp_next": 1234, "was": 2},
		"agility": {"level": 99, "xp": 0, "xp_next": 0, "was": 1},
		"defense": {"level": 99, "xp": 0, "xp_next": 77, "was": 1},
		"strength": {"level": 50, "xp": 0, "xp_next": 10, "was": 1},
	}})
	check("a character copies the skills the server set: level, no XP into it, the next step",
		warrior.attack == 60 and warrior.attack_xp == 0 and warrior.attack_xp_next == 1234,
		[warrior.attack, warrior.attack_xp, warrior.attack_xp_next])
	check("  a missing next step is worked out from the skill's own curve",
		warrior.agility == 99 and warrior.agility_xp_next == warrior.xp_needed_for_skill_id("agility", 99),
		[warrior.agility, warrior.agility_xp_next])
	check("  a skill it did not name is left where it was", warrior.cooking == 4, warrior.cooking)
	check("  and a name that is not a skill sets nothing", warrior.get("strength") == null)
	check("  the new levels are what the fight reads: attack speed and the defense tier",
		is_equal_approx(warrior.get_attack_speed_multiplier(), PlayerStats.attack_speed_multiplier(99))
		and warrior._get_defense_tier()["name"] == PlayerStats.defense_tier(99)["name"],
		[warrior.get_attack_speed_multiplier(), warrior._get_defense_tier()])
	warrior.free()
	await get_tree().process_frame
	print("  the GM panel's Testing tab sets your skills, one or all, owner only")


# =============================================================================
# THE BULLET-HELL ZONE (0.22.0)
# =============================================================================

func _test_the_bullet_zone() -> void:
	section("THE BULLET-HELL ZONE (0.22.0) - the Field's orbs: one draw, your hits only, stopped by walls")
	const Targets := preload("res://src/shared/targets.gd")
	# THE FAMILIES' OWN VOLLEYS: since 0.84.0 an element monster fires its
	# element's kit (elementkit.gd, _test_monsters_fire_their_element); these
	# checks are of the volley each family fires without one.
	const Kit := preload("res://src/enemies/elementkit.gd")
	Kit.family_only = true

	check("the Field is the bullet-hell zone", _root_property("res://scene/field.tscn", &"bullet_zone") == true)
	check("  and the Big Field is not: it stays the RPG",
		_root_property("res://scene/bigfield.tscn", &"bullet_zone") != true)
	check("orbs are drawn unshaded, so the crypt's CanvasModulate cannot swallow them",
		BulletField.SHADER_CODE.contains("render_mode unshaded"))
	var drawn := BulletField.new()
	add_child(drawn)
	var drawer: MultiMeshInstance2D = drawn.get_node_or_null(^"bullets") as MultiMeshInstance2D
	check("orbs are not physics-interpolated: they move every frame, and the editor warned (0.23.1)",
		drawer != null and drawer.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF
		and not drawer.is_physics_interpolated())
	drawn.queue_free()
	check("no orb passes through after a hit any more, and the hitbox is 6 px - the owner's \"more projectiles to hit player\" (0.25.3)",
		is_zero_approx(BulletZone.CHIP_MERCY) and is_equal_approx(BulletZone.HITBOX_RADIUS, 6.0),
		[BulletZone.CHIP_MERCY, BulletZone.HITBOX_RADIUS])
	var culled := BulletField.new()
	add_child(culled)
	culled.bounds = Rect2(-64, 600, 1600, 700)
	var box: AABB = culled._multimesh.custom_aabb
	check("the renderer is told the bullets are on the floor, wherever the floor is (the Field drew no orbs without it)",
		box.has_point(Vector3(1500, 1250, 0)) and box.has_point(Vector3(-60, 610, 0)), box)
	culled.queue_free()
	check("an orb wears its element's colour, lifted toward white",
		BulletZone.shot_colour(Element.Type.ICE).is_equal_approx(
			Element.colour_for(Element.Type.ICE).lerp(Color.WHITE, 0.2)))

	# --- the field on its own -------------------------------------------------
	var far := Vector2(9999, 9999)
	var f := BulletField.new()
	add_child(f)
	f.bounds = Rect2(-500, -500, 1000, 1000)
	f.spawn(Vector2.ZERO, 0.0, 100.0, Color.RED, false, 0.0, 0.0, 10.0, 7, Element.Type.FIRE)
	f.step(0.5, far, 3.0, 0.0, false)
	check("an orb flies its own line at its own speed",
		f.count == 1 and f.position_of(0).distance_to(Vector2(50, 0)) < 0.01, f.position_of(0))
	var result: Vector2i = f.step(0.5, Vector2(100, 0), 3.0, 0.0, false)
	check("one that reaches the hitbox is a hit, carrying its damage and element, and is spent",
		result.x == 1 and f.hits == [Vector2i(7, Element.Type.FIRE)] and f.count == 0, [result, f.hits, f.count])
	f.spawn(Vector2.ZERO, 0.0, 100.0, Color.RED, false, 0.0, 0.0, 10.0, 7, 0)
	f.step(1.0, Vector2(100, 0), 3.0, 0.0, true)
	check("  while untouchable it passes through and flies on", f.count == 1 and f.hits.is_empty())
	f.step(5.0, far, 3.0, 0.0, false)
	check("  and the floor's edge ends it", f.count == 0)

	for k in 3:
		f.spawn(Vector2(0, k * 50), 0.0, 10.0, Color.RED, false, 0.0, 0.0, 10.0, k + 1, k)
	f.step(0.1, Vector2(1, 50), 3.0, 0.0, false)
	var left: Array = []
	for i in f.count:
		left.append([f.damage_of(i), f.element_of(i), roundi(f.position_of(i).y)])
	left.sort()
	check("taking one out of the middle leaves the others their own damage, element and place",
		f.count == 2 and left == [[1, 0, 0], [3, 2, 100]], left)
	f.clear()

	var on_time := BulletField.new()
	var late := BulletField.new()
	add_child(on_time)
	add_child(late)
	on_time.bounds = f.bounds
	late.bounds = f.bounds
	# A curving one, the hard case: on time and stepped in uneven frames, or
	# fired 0.25 s late and caught up in one go.
	on_time.spawn(Vector2.ZERO, 0.3, 80.0, Color.WHITE, false, 0.6)
	for frame in [0.016, 0.05, 0.034, 0.1, 0.05]:
		on_time.step(frame, far, 3.0, 0.0, false)
	late.spawn(Vector2.ZERO, 0.3, 80.0, Color.WHITE, false, 0.6, 0.25)
	late.step(0.0, far, 3.0, 0.0, false)
	check("a shot fired 0.25 s late is caught up to where one fired on time is - every screen draws the same orb",
		on_time.position_of(0).distance_to(late.position_of(0)) < 0.05,
		[on_time.position_of(0), late.position_of(0)])
	on_time.queue_free()
	late.queue_free()

	# 0.25.0: an orb that settles - slows evenly to a stop and lies there.
	var even := BulletField.new()
	var chopped := BulletField.new()
	add_child(even)
	add_child(chopped)
	even.bounds = f.bounds
	chopped.bounds = f.bounds
	even.spawn_settling(Vector2.ZERO, 0.0, 150.0, Color.GREEN, 120.0, 3.0, 4, 0, true)
	chopped.spawn_settling(Vector2.ZERO, 0.0, 150.0, Color.GREEN, 120.0, 3.0, 4, 0, true)
	even.step(2.0, far, 3.0, 0.0, false)
	for frame in [0.016, 0.05, 0.3, 0.034, 0.1, 0.3, 0.5, 0.4]:
		chopped.step(frame, far, 3.0, 0.0, false)
	check("a settling orb slows to a stop exactly where it was told, however the time is cut into frames (0.25.0)",
		even.position_of(0).distance_to(Vector2(120, 0)) < 0.01 and chopped.position_of(0).distance_to(Vector2(120, 0)) < 0.01
		and even.velocity_of(0) == Vector2.ZERO and chopped.velocity_of(0) == Vector2.ZERO,
		[even.position_of(0), chopped.position_of(0)])
	var half := BulletField.new()
	add_child(half)
	half.bounds = f.bounds
	half.spawn_settling(Vector2.ZERO, 0.0, 150.0, Color.GREEN, 120.0, 3.0)
	half.step(0.8, far, 3.0, 0.0, false)
	check("  slowing evenly on the way: halfway through its time it has gone three quarters of the way",
		absf(half.position_of(0).x - 90.0) < 0.01 and absf(half.velocity_of(0).length() - 75.0) < 0.01, half.position_of(0))
	half.queue_free()
	var solid: float = even._buffer[11]
	even.step(2.3, far, 3.0, 0.0, false)
	var fading: float = even._buffer[11]
	check("  it lies there for its 3 s, and fades over the last %.2f s of them" % BulletField.FADE_SECONDS,
		even.count == 1 and even.position_of(0).distance_to(Vector2(120, 0)) < 0.01
		and is_equal_approx(solid, 1.0) and fading > 0.0 and fading < 0.5, [even.count, solid, fading])
	even.step(0.5, far, 3.0, 0.0, false)
	check("  then it is gone", even.count == 0, even.count)
	var mine: Vector2 = chopped.position_of(0)
	var mine_hit: Vector2i = chopped.step(0.1, mine, 3.0, 0.0, false)
	check("  and a player who walks onto it is hit, and it is spent", mine_hit.x == 1 and chopped.count == 0, mine_hit)
	even.queue_free()
	chopped.queue_free()

	var cells := PackedByteArray()
	cells.resize(100)
	cells[5 * 10 + 6] = 1
	f.set_walls(cells, Vector2.ZERO, 8.0, Vector2i(10, 10))
	f.spawn(Vector2(4, 44), 0.0, 100.0, Color.RED)
	f.spawn(Vector2(4, 36), 0.0, 100.0, Color.RED)
	f.step(0.3, far, 3.0, 0.0, false)
	check("orbs fly on until a wall", f.count == 2)
	f.step(0.2, far, 3.0, 0.0, false)
	check("  the one that flies into a wall cell is gone, and the one beside it is not",
		f.count == 1 and roundi(f.position_of(0).y) == 36, [f.count, f.position_of(0)])
	f.queue_free()

	# --- the zone, and the player it hurts -----------------------------------
	var others: Array = get_tree().get_nodes_in_group(&"player")
	for o in others:
		o.remove_from_group(&"player")
	var world := Node2D.new()
	add_child(world)
	var zone := BulletZone.new()
	world.add_child(zone)
	zone.set_process(false)
	var dummy := ZoneDummy.new()
	dummy.position = Vector2(-30000, -30000)
	dummy.add_to_group(&"player")
	world.add_child(dummy)
	check("the zone is found from anything in its area", BulletZone.find(dummy) == zone)

	var body: Vector2 = Targets.body_point(dummy)
	zone.field.spawn(body + Vector2(-2, 0), 0.0, 1.0, Color.RED, false, 0.0, 0.0, 6.0, 9, Element.Type.ICE)
	zone.field.spawn(body + Vector2(2, 0), 0.0, 1.0, Color.RED, false, 0.0, 0.0, 6.0, 4, Element.Type.ICE)
	zone._process(0.01)
	check("orbs that reach the body hurt through take_damage, with the element: every one of a frame lands (0.25.3)",
		dummy.taken == [[9, Element.Type.ICE], [4, Element.Type.ICE]], dummy.taken)
	check("  and every orb that touched is spent", zone.field.count == 0)
	zone.field.spawn(body, 0.0, 1.0, Color.RED, false, 0.0, 0.0, 6.0, 9, Element.Type.ICE)
	zone._process(0.01)
	check("the next orb lands at once - nothing passes through after a hit",
		dummy.taken.size() == 3 and zone.field.count == 0, [dummy.taken, zone.field.count])
	zone.field.spawn(body + Vector2(7, 0), 0.0, 0.0, Color.RED, false, 0.0, 0.0, 6.0, 2, 0)
	zone.field.spawn(body + Vector2(0, -11), 0.0, 0.0, Color.RED, false, 0.0, 0.0, 6.0, 1, 0)
	zone._process(0.01)
	check("an orb across the middle of the body lands (7 px off; 3 px of hitbox let it by), one 11 px off does not",
		dummy.taken.size() == 4 and int(dummy.taken[3][0]) == 2 and zone.field.count == 1,
		[dummy.taken, zone.field.count])
	zone.field.clear()
	dummy.is_dying = true
	zone.field.spawn(body, 0.0, 1.0, Color.RED, false, 0.0, 0.0, 6.0, 9, 0)
	zone._process(0.01)
	check("a dying player is not hit again", dummy.taken.size() == 4)
	dummy.is_dying = false
	zone.field.clear()

	zone.fire_fan(Vector2(100, 0), PI, 3, 0.5, 150.0, 5, Element.Type.DARK)
	var angles: Array = []
	for i in zone.field.count:
		angles.append(snappedf((zone.field.position_of(i) - Vector2(100, 0)).angle(), 0.01))
	check("a fan is its orbs spread evenly about the aim",
		zone.field.count == 3 and zone.field.damage_of(0) == 5 and zone.field.element_of(0) == Element.Type.DARK
		and zone.field.colour_of(0).is_equal_approx(BulletZone.shot_colour(Element.Type.DARK)), angles)
	zone.field.clear()

	# --- walls from the physics world, and a door that opens -------------------
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var wall_shape := CollisionShape2D.new()
	var wall_rect := RectangleShape2D.new()
	wall_rect.size = Vector2(16, 64)
	wall_shape.shape = wall_rect
	wall.add_child(wall_shape)
	wall.position = Vector2(-29900, -30000)
	world.add_child(wall)
	zone.field.bounds = Rect2(-30200, -30200, 400, 400)
	zone._start_walls()
	await get_tree().physics_frame
	await get_tree().physics_frame
	zone.build_all_walls()
	check("the wall grid is solid where a body on layer 1 stands, and open beside it",
		zone.walls_ready() and zone.field.is_wall(Vector2(-29900, -30000))
		and not zone.field.is_wall(Vector2(-29950, -30000)))
	zone.field.spawn(Vector2(-29960, -30000), 0.0, 120.0, Color.RED)
	for frame in 60:
		zone.field.step(1.0 / 60.0, far, 3.0, 0.0, false)
	check("  so an orb fired at it stops there", zone.field.count == 0)

	var door: Node2D = (load("res://scene/interactables/spikedoor.tscn") as PackedScene).instantiate()
	door.position = Vector2(-30100, -30100)
	world.add_child(door)
	door.raised_changed.connect(zone._on_door_changed.bind(door))
	for i in 3:
		await get_tree().physics_frame
	zone._start_walls()
	zone.build_all_walls()
	var closed: bool = zone.field.is_wall(Vector2(-30100, -30100))
	door.call("set_raised", false)
	await get_tree().create_timer(float(door.get("travel_seconds")) + 0.15).timeout
	check("a raised spike door is a wall, and once lowered it is not",
		closed and not zone.field.is_wall(Vector2(-30100, -30100)), closed)

	# --- the Bush Sniper -------------------------------------------------------
	var shots := Node2D.new()
	shots.add_to_group(&"projectiles")
	world.add_child(shots)
	var sn: BaseEnemy = (load("res://scene/enemy/darkbushsniper.tscn") as PackedScene).instantiate()
	sn.position = Vector2(-30100, -30000)
	world.add_child(sn)
	await get_tree().process_frame
	sn.player = dummy
	sn.attack_direction = "right"
	zone.field.clear()
	sn.call("fire_projectile")
	await get_tree().process_frame
	var dark_arrow: int = (sn.enemy_data as EnemyData).projectile_damage
	var helix_hit: int = roundi(dark_arrow * 0.35)
	var helix: Array[int] = []
	for i in zone.field.count:
		if zone.field.damage_of(i) == helix_hit:
			helix.append(i)
	var arrow: Node = shots.get_child(0) if shots.get_child_count() == 1 else null
	check("a sniper in the zone looses its own arrow, slowed to 160 px/s, with a helix of 2 orbs (0.24.0)",
		arrow != null and is_equal_approx(float(arrow.get("speed")), 160.0) and helix.size() == 2,
		[shots.get_child_count(), helix.size()])
	check("  the orbs in its element, each 35%% of its arrow (%d -> %d)" % [dark_arrow, helix_hit],
		helix.size() == 2 and zone.field.element_of(helix[0]) == Element.Type.DARK)
	var nearest_aim: float = INF
	for i in helix:
		var to_body: float = (Targets.body_point(dummy) - zone.field.anchor_of(i)).angle()
		nearest_aim = minf(nearest_aim, absf(angle_difference(zone.field.velocity_of(i).angle(), to_body)))
	check("  winding round the arrow's line, which aims at the player's body", nearest_aim < 0.05, nearest_aim)
	zone.field.step(0.15, Vector2(99999, 99999), 3.0, 0.0, false)
	var sides: Array[float] = []
	for i in helix:
		var off: Vector2 = zone.field.position_of(i) - zone.field.anchor_of(i)
		sides.append(off.dot(zone.field.velocity_of(i).normalized().orthogonal()))
	check("  weaving up to 12 px either side of it, on opposite sides",
		sides.size() == 2 and absf(sides[0]) > 8.0 and absf(sides[0]) <= 12.01 and sides[0] * sides[1] < 0.0, sides)
	var wake: BulletWake = arrow.get_node_or_null(^"wake") as BulletWake if arrow != null else null
	var shed_from: int = zone.field.count
	if wake != null:
		wake.shed_once(Vector2(-30000, -30000), Vector2.LEFT)
	var backs: Array = []
	for i in range(shed_from, zone.field.count):
		backs.append(snappedf(zone.field.velocity_of(i).angle(), 0.01))
	backs.sort()
	check("the arrow sheds a wake: pairs flying back and out, a < behind an arrow flying left",
		wake != null and backs.size() == 2 and is_equal_approx(backs[0], -0.55) and is_equal_approx(backs[1], 0.55)
		and zone.field.damage_of(shed_from) == roundi(dark_arrow * 0.2), backs)
	zone.queue_free()
	await get_tree().process_frame
	zone = null
	var before_shots: int = shots.get_child_count()
	sn.call("fire_projectile")
	await get_tree().process_frame
	var plain: Node = shots.get_child(shots.get_child_count() - 1) if shots.get_child_count() > before_shots else null
	check("the same sniper with no zone in its area fires its plain arrow, as everywhere but the Field",
		plain != null and is_equal_approx(float(plain.get("speed")), 400.0) and plain.get_node_or_null(^"wake") == null,
		shots.get_child_count() - before_shots)
	Kit.family_only = false
	world.queue_free()
	for o in others:
		if is_instance_valid(o):
			o.add_to_group(&"player")
	await get_tree().process_frame


func _test_the_bullet_zone_is_shared() -> void:
	section("THE BULLET-HELL ZONE - a volley is shared as where and which way, never how hard")
	var others: Array = get_tree().get_nodes_in_group(&"player")
	for o in others:
		o.remove_from_group(&"player")

	# The leader: its sniper's volley goes out in the next tick.
	var world: Node2D = _sm_world()
	var zone := BulletZone.new()
	world.add_child(zone)
	zone.set_process(false)
	var sn: BaseEnemy = world.get_node("enemies/sn1")
	var dummy := ZoneDummy.new()
	dummy.position = Vector2(-19950, -20000)
	dummy.add_to_group(&"player")
	world.add_child(dummy)
	var link := FakeLink.new()
	link.area = SM_AREA
	link.leader = 1
	add_child(link)
	var sync: Node = _sm_sync(link)
	world.add_child(sync)
	await get_tree().process_frame
	sn.player = dummy
	sn.attack_direction = "right"
	link.sent_world.clear()
	sn.call("fire_projectile")
	sync.tick_lead()
	var volley: Dictionary = {}
	for event in _sm_last_world(link).get("ev", []):
		if str(event.get("k", "")) == "b":
			volley = event
	var shots_sent: int = 0
	for event in _sm_last_world(link).get("ev", []):
		if str(event.get("k", "")) == "p" and int(event.get("id", -1)) == sn.net_id:
			shots_sent += 1
	check("the leader's volley goes to the others as {k: b, id, x, y, a}",
		int(volley.get("id", -1)) == sn.net_id and volley.has("a") and volley.has("x")
		and not volley.has("d") and zone.field.count >= 2, volley)
	check("  and its arrow is not sent again as a shot: the volley brings it (0.24.0)", shots_sent == 0, shots_sent)
	world.queue_free()
	link.queue_free()
	await get_tree().process_frame

	# A follower: the volley is fired by its own copy of the monster.
	var world2: Node2D = _sm_world()
	var zone2 := BulletZone.new()
	world2.add_child(zone2)
	zone2.set_process(false)
	var sn2: BaseEnemy = world2.get_node("enemies/sn1")
	var fs2: BaseEnemy = world2.get_node("enemies/fs1")
	var link2 := FakeLink.new()
	link2.me = 2
	add_child(link2)
	var sync2: Node = _sm_sync(link2)
	world2.add_child(sync2)
	await get_tree().process_frame
	link2.lead_changed.emit(SM_AREA, 1, 1)
	sync2._enemies[7] = sn2
	sync2._enemies[8] = fs2
	var shots2: Node = world2.get_node("shots")
	var shots2_before: int = shots2.get_child_count()
	sync2.apply_world({"ev": [{"k": "b", "id": 7, "x": -20090.0, "y": -20000.0, "a": 0.25, "d": 9999}]})
	await get_tree().process_frame
	var helix2: int = 0
	for i in zone2.field.count:
		if zone2.field.damage_of(i) == int(sn2.call("orb_damage")) \
				and zone2.field.anchor_of(i).distance_to(Vector2(-20090, -20000)) < 6.0:
			helix2 += 1
	check("a follower fires the leader's volley from where it left, which way it went - its arrow and helix",
		helix2 == 2 and shots2.get_child_count() == shots2_before + 1,
		[helix2, shots2.get_child_count() - shots2_before])
	check("  with its own copy's damage: anything the leader adds is ignored",
		zone2.field.damage_of(0) == int(sn2.call("orb_damage")) and zone2.field.damage_of(0) < 9999,
		zone2.field.damage_of(0))
	var before: int = zone2.field.count
	sync2.apply_world({"ev": [{"k": "b", "id": 99, "x": 0.0, "y": 0.0, "a": 0.0}]})
	check("  one this game does not have fires nothing", zone2.field.count == before, zone2.field.count)

	# 0.23.0: "r", how far - the fire sprite's pincer closes where the leader's
	# did, held to the sprite's own range on this screen.
	zone2.field.clear()
	sync2.apply_world({"ev": [{"k": "b", "id": 8, "x": -20000.0, "y": -20000.0, "a": 0.0, "r": 120.0}]})
	var meet := Vector2(-20000.0 + 120.0, -20000.0)
	for frame in 120:
		zone2.field.step(1.0 / 60.0, Vector2(9999, 9999), 3.0, 0.0, false)
		var close: int = 0
		for i in zone2.field.count:
			if zone2.field.position_of(i).distance_to(meet) < 4.0:
				close += 1
		if close == 4:
			break
	var gathered: int = 0
	for i in zone2.field.count:
		if zone2.field.position_of(i).distance_to(meet) < 4.0:
			gathered += 1
	check("a follower's fire sprite closes its pincer where the leader's reach says (\"r\")",
		gathered == 4, gathered)
	zone2.field.clear()
	sync2.apply_world({"ev": [{"k": "b", "id": 8, "x": -20000.0, "y": -20000.0, "a": 0.0, "r": 99999.0}]})
	var far_meet := Vector2(-20000.0 + float(fs2.get("PINCER_REACH_MAX")), -20000.0)
	var closed: bool = false
	for frame in 240:
		zone2.field.step(1.0 / 60.0, Vector2(9999, 9999), 3.0, 0.0, false)
		var close2: int = 0
		for i in zone2.field.count:
			if zone2.field.position_of(i).distance_to(far_meet) < 4.0:
				close2 += 1
		if close2 == 4:
			closed = true
			break
	check("  and a reach past the sprite's own is held to it", closed)

	# 0.23.0: "v", which volley - a large slime's split ring, and only that.
	var slime: BaseEnemy = (load("res://scene/enemy/darkslimelarge.tscn") as PackedScene).instantiate()
	slime.position = Vector2(-20200, -20000)
	world2.get_node("enemies").add_child(slime)
	await get_tree().process_frame
	sync2._enemies[9] = slime
	zone2.field.clear()
	sync2.apply_world({"ev": [{"k": "b", "id": 9, "x": -20200.0, "y": -20000.0, "a": 0.0, "v": "split"}]})
	check("a follower's large slime fires the split ring when the volley says \"split\"",
		zone2.field.count == int(slime.get("SPLIT_ORBS")), zone2.field.count)
	zone2.field.clear()
	sync2.apply_world({"ev": [{"k": "b", "id": 9, "x": -20200.0, "y": -20000.0, "a": 0.0, "v": "everything"}]})
	check("  a volley it does not have fires nothing", zone2.field.count == 0, zone2.field.count)
	sync2.apply_world({"ev": [{"k": "b", "id": 9, "x": -20200.0, "y": -20000.0, "a": PI / 2.0, "v": "mortar", "r": 150.0}]})
	var lobs2: Array = []
	for child in zone2.get_children():
		if child is BulletLob:
			lobs2.append(child)
	check("a follower's large slime lobs the mortar where the leader's landed (0.25.0)",
		lobs2.size() == 1 and (lobs2[0] as BulletLob).to.distance_to(Vector2(-20200, -19850)) < 0.5,
		[lobs2.size(), str((lobs2[0] as BulletLob).to) if lobs2.size() > 0 else "none"])
	for l in lobs2:
		l.free()
	sync2.apply_world({"ev": [{"k": "b", "id": 9, "x": -20200.0, "y": -20000.0, "a": 0.0, "v": "mortar", "r": 99999.0}]})
	var far_lob: BulletLob = null
	for child in zone2.get_children():
		if child is BulletLob:
			far_lob = child
	check("  no further than its own range, whatever the reach says",
		far_lob != null and is_equal_approx(far_lob.to.x - (-20200.0), float(slime.get("MORTAR_REACH_MAX"))),
		str(far_lob.to) if far_lob != null else "none")
	if far_lob != null:
		far_lob.free()
	zone2.field.clear()
	sync2.apply_world({"ev": [{"k": "b", "id": 9, "x": -20200.0, "y": -20000.0, "a": 0.0, "r": 100.0}]})
	for frame in 120:
		zone2.field.step(1.0 / 60.0, Vector2(9999, 9999), 3.0, 0.0, false)
	var settled2: bool = zone2.field.count == 5
	for i in zone2.field.count:
		settled2 = settled2 and absf(zone2.field.anchor_of(i).distance_to(Vector2(-20200, -20000)) - 100.0) < 0.5
	check("  and settles its spray as far off as the leader's (\"r\")", settled2, zone2.field.count)
	zone2.field.clear()
	world2.queue_free()
	link2.queue_free()
	for o in others:
		if is_instance_valid(o):
			o.add_to_group(&"player")
	await get_tree().process_frame


func _test_the_field_volleys() -> void:
	section("THE FIELD'S VOLLEYS (0.23.0) - every monster there fires its own shape, a share of its shot")
	# The families' own volleys: the element kits off while these run (see
	# _test_the_bullet_zone).
	const Kit := preload("res://src/enemies/elementkit.gd")
	Kit.family_only = true
	const Targets := preload("res://src/shared/targets.gd")
	var others: Array = get_tree().get_nodes_in_group(&"player")
	for o in others:
		o.remove_from_group(&"player")
	var world := Node2D.new()
	add_child(world)
	var zone := BulletZone.new()
	world.add_child(zone)
	zone.set_process(false)
	var shots := Node2D.new()
	shots.add_to_group(&"projectiles")
	world.add_child(shots)
	var ground := Node2D.new()
	ground.add_to_group(&"groundeffects")
	world.add_child(ground)
	var dummy := ZoneDummy.new()
	dummy.position = Vector2(-40000, -40000)
	dummy.add_to_group(&"player")
	world.add_child(dummy)
	var body: Vector2 = Targets.body_point(dummy)

	# --- the Bush Mage: the vine, and a ring with its gap toward you -----------
	var mage: BaseEnemy = (load("res://scene/enemy/darkbushmage.tscn") as PackedScene).instantiate()
	mage.position = body + Vector2(-36, 0)
	world.add_child(mage)
	await get_tree().process_frame
	mage.player = dummy
	mage.attack_direction = "right"
	mage.call("_spawn_vine")
	var orbs: int = zone.field.count
	var to_you: float = (body - (mage as Node2D).global_position).angle()
	var nearest: float = INF
	for i in zone.field.count:
		nearest = minf(nearest, absf(angle_difference(zone.field.velocity_of(i).angle(), to_you)))
	var mage_hit: int = (mage.enemy_data as EnemyData).projectile_damage
	check("a Bush Mage in the zone still raises its vine", ground.get_child_count() == 1, ground.get_child_count())
	check("  and sends a ring of %d orbs, %d each (35%% of the vine's %d)" % [orbs, roundi(mage_hit * 0.35), mage_hit],
		orbs == 10 and zone.field.damage_of(0) == roundi(mage_hit * 0.35)
		and zone.field.element_of(0) == Element.Type.DARK, [orbs, zone.field.damage_of(0)])
	check("  with a gap, not an orb, toward the player", absf(nearest - PI / 10.0) < 0.02, nearest)
	zone.field.clear()

	# --- the Fire Sprite: a pincer that closes where you stood -----------------
	var fire: BaseEnemy = (load("res://scene/enemy/darkfiresprite.tscn") as PackedScene).instantiate()
	fire.position = body + Vector2(-150, 0)
	world.add_child(fire)
	await get_tree().process_frame
	fire.player = dummy
	fire.attack_direction = "right"
	fire.call("fire_projectile")
	var fire_hit: int = (fire.enemy_data as EnemyData).projectile_damage
	check("a Fire Sprite looses a pincer of 4 orbs, %d each (half its %d)" % [roundi(fire_hit * 0.5), fire_hit],
		zone.field.count == 4 and zone.field.damage_of(0) == roundi(fire_hit * 0.5), [zone.field.count, zone.field.damage_of(0)])
	await get_tree().process_frame
	var fire_orb: Node = shots.get_child(0) if shots.get_child_count() == 1 else null
	var fire_meet: float = (body - (fire.get_node("projectileright") as Node2D).global_position).length()
	check("  and its own fire orb flies down the middle, timed to arrive as the pincer closes (0.24.0)",
		fire_orb != null and absf(float(fire_orb.get("speed"))
			- fire_meet / BulletZone.pincer_time(fire_meet, fire.get("PINCER_OFFSETS"), 150.0)) < 0.5,
		[shots.get_child_count(), fire_orb.get("speed") if fire_orb != null else 0])
	for s in shots.get_children():
		s.free()
	var started_wide: bool = true
	for i in zone.field.count:
		var off: float = absf(angle_difference(zone.field.velocity_of(i).angle(),
			(body - zone.field.position_of(i)).angle()))
		started_wide = started_wide and off > 0.4
	var met: bool = false
	for frame in 180:
		zone.field.step(1.0 / 60.0, Vector2(99999, 99999), 3.0, 0.0, false)
		var close: int = 0
		for i in zone.field.count:
			if zone.field.position_of(i).distance_to(body) < 4.0:
				close += 1
		if close == 4:
			met = true
			break
	check("  the orbs leave wide of the player and all four meet where the player stood",
		started_wide and met, [started_wide, met])
	zone.field.clear()

	# --- the Electric Sprite: a chain that strings out --------------------------
	var spark: BaseEnemy = (load("res://scene/enemy/darksprite.tscn") as PackedScene).instantiate()
	spark.position = body + Vector2(-150, 0)
	world.add_child(spark)
	await get_tree().process_frame
	spark.player = dummy
	spark.attack_direction = "right"
	spark.call("fire_projectile")
	var speeds: Array = []
	var line: bool = true
	var aim: float = zone.field.velocity_of(0).angle() if zone.field.count > 0 else 0.0
	for i in zone.field.count:
		speeds.append(roundi(zone.field.velocity_of(i).length()))
		line = line and absf(angle_difference(zone.field.velocity_of(i).angle(), aim)) < 0.001
	speeds.sort()
	var spark_hit: int = (spark.enemy_data as EnemyData).projectile_damage
	check("an Electric Sprite looses a chain of 5 down one line, 110 to 170 px/s, %d each" % roundi(spark_hit * 0.5),
		zone.field.count == 5 and line and speeds == [110, 125, 140, 155, 170]
		and zone.field.damage_of(0) == roundi(spark_hit * 0.5), [speeds, line])
	await get_tree().process_frame
	var spark_orb: Node = shots.get_child(0) if shots.get_child_count() == 1 else null
	check("  its own electric orb at the head of the chain, at 170 px/s (0.24.0)",
		spark_orb != null and is_equal_approx(float(spark_orb.get("speed")), 170.0), shots.get_child_count())
	for s in shots.get_children():
		s.free()
	zone.field.clear()

	# --- the Poison Slime: twin, spray, and the ring as it splits ---------------
	var small: BaseEnemy = (load("res://scene/enemy/poisonslime.tscn") as PackedScene).instantiate()
	small.set("is_small", true)
	small.position = body + Vector2(-100, 0)
	world.add_child(small)
	await get_tree().process_frame
	small.player = dummy
	small.attack_direction = "right"
	small.call("fire_projectile")
	await get_tree().process_frame
	check("a small slime looses a twin, its own arrow between them (0.24.0)",
		zone.field.count == 2 and shots.get_child_count() == 1 and zone.field.radius_of(0) < 3.0,
		[zone.field.count, shots.get_child_count()])
	for s in shots.get_children():
		s.free()
	zone.field.clear()
	var large: BaseEnemy = (load("res://scene/enemy/darkslimelarge.tscn") as PackedScene).instantiate()
	large.position = body + Vector2(-120, 0)
	world.add_child(large)
	await get_tree().process_frame
	large.player = dummy
	large.attack_direction = "right"
	large.call("fire_projectile")
	var large_hit: int = (large.enemy_data as EnemyData).projectile_damage
	check("a large slime sprays 5 big orbs, %d each (45%% of its %d)" % [roundi(large_hit * 0.45), large_hit],
		zone.field.count == 5 and zone.field.radius_of(0) > 5.0
		and zone.field.damage_of(0) == roundi(large_hit * 0.45), [zone.field.count, zone.field.damage_of(0)])
	var stood: float = ((large.get_node("projectileright") as Node2D).global_position).distance_to(body)
	var spray_from: Vector2 = (large.get_node("projectileright") as Node2D).global_position
	for frame in 150:
		zone.field.step(1.0 / 60.0, Vector2(99999, 99999), 3.0, 0.0, false)
	var settled: Array = []
	for i in zone.field.count:
		settled.append(roundi(zone.field.position_of(i).distance_to(spray_from)))
	check("  that leave at 150 px/s and settle where the player stood, %d px off (0.25.0)" % roundi(stood),
		zone.field.count == 5 and settled.all(func(d: int) -> bool: return absi(d - roundi(stood)) <= 1)
		and zone.field.velocity_of(0) == Vector2.ZERO, settled)
	await get_tree().process_frame
	check("  its own acid ball in the middle of the spray (0.24.0)", shots.get_child_count() == 1,
		shots.get_child_count())
	for s in shots.get_children():
		s.free()
	zone.field.clear()

	# 0.25.0: and every other shot, the mortar.
	large.call("fire_projectile")
	var lob: BulletLob = null
	for child in zone.get_children():
		if child is BulletLob:
			lob = child
	if lob != null:
		lob.set_process(false)
	await get_tree().process_frame
	check("its next shot is the mortar: nothing flies straight, a lob goes up (0.25.0)",
		lob != null and zone.field.count == 0 and shots.get_child_count() == 0,
		[lob, zone.field.count, shots.get_child_count()])
	if lob != null:
		var lob_art: AnimatedSprite2D = lob.art as AnimatedSprite2D
		var ball: Node = Projectiles.variant_of(load("res://scene/projectiles/poisonball.tscn"),
			Element.Type.DARK).instantiate()
		var ball_frames: SpriteFrames = (ball.get_node("animatedsprite2d") as AnimatedSprite2D).sprite_frames
		ball.free()
		check("  what it lobs is the artist's acid ball - its own sprite, in its element",
			lob_art != null and lob_art.get_parent() == lob and lob_art.sprite_frames == ball_frames, lob_art)
		check("  onto the spot the player stood on, marked on the floor from the start",
			lob.to.distance_to(body) < 0.5 and is_equal_approx(lob.crater, 40.0), [lob.to, body])
		lob.advance(0.5)
		check("  up over everything on the way: at the top of its arc and drawn twice its size",
			lob.height() > 20.0 and is_equal_approx(lob_art.scale.x, 2.0) and zone.field.count == 0,
			[lob.height(), lob_art.scale])
		lob.advance(0.51)
		check("  it lands after 1 s: one big orb on the spot and a ring of 8 around it",
			zone.field.count == 9 and lob.is_queued_for_deletion(), zone.field.count)
		var impact: int = -1
		var ring_share: int = roundi(large_hit * 0.35)
		var ring_count: int = 0
		for i in zone.field.count:
			if zone.field.damage_of(i) == large_hit and zone.field.radius_of(i) > 5.0:
				impact = i
			elif zone.field.damage_of(i) == ring_share:
				ring_count += 1
		check("  the one on the spot is the whole acid ball (%d); the ring %d each" % [large_hit, ring_share],
			impact >= 0 and ring_count == 8, [impact, ring_count])
		for frame in 60:
			zone.field.step(1.0 / 60.0, Vector2(99999, 99999), 3.0, 0.0, false)
		var crater: Array = []
		for i in zone.field.count:
			crater.append(roundi(zone.field.position_of(i).distance_to(body)))
		check("  the ring settles into a crater 40 px out, and the spot itself is clear again",
			zone.field.count == 8 and crater.all(func(d: int) -> bool: return d == 40), crater)
		await get_tree().process_frame
		var pool: Node = ground.get_child(ground.get_child_count() - 1) if ground.get_child_count() > 0 else null
		check("  and it leaves the acid puddle the ball leaves on a hit, in its element, on the spot",
			pool is AcidPuddle and int(pool.get("element")) == Element.Type.DARK
			and (pool as Node2D).global_position.distance_to(body) < 0.5
			and pool.scene_file_path == Puddles.scene_for(Element.Type.DARK).resource_path, pool)
		if pool != null:
			pool.free()
	zone.field.clear()
	var from_marker: Vector2 = (large.get_node("projectileright") as Node2D).global_position
	large.call("fire_volley", zone, from_marker, (body - from_marker).angle(), "mortar", from_marker.distance_to(body))
	var lob2: BulletLob = null
	for child in zone.get_children():
		if child is BulletLob and not child.is_queued_for_deletion():
			lob2 = child
	if lob2 != null:
		lob2.set_process(false)
		lob2.advance(1.0)
	zone._mercy_until_ms = 0
	dummy.taken.clear()
	zone._process(0.01)
	check("  a player still standing there when it lands takes the acid ball",
		dummy.taken.size() == 1 and int(dummy.taken[0][0]) == large_hit and int(dummy.taken[0][1]) == Element.Type.DARK,
		dummy.taken)
	zone.field.clear()
	await get_tree().process_frame
	for child in ground.get_children():
		child.free()
	large.call("fire_projectile")
	var turns: int = zone.field.count
	for child in zone.get_children():
		if child is BulletLob:
			turns = -1
	check("  and the shot after that is the spray again: they take turns", turns == 5, turns)
	await get_tree().process_frame
	for s in shots.get_children():
		s.free()
	zone.field.clear()
	large.call("_begin_split")
	check("  and bursts into a ring of 12 as it splits, %d each" % roundi(large_hit * 0.35),
		zone.field.count == 12 and zone.field.damage_of(0) == roundi(large_hit * 0.35), zone.field.count)
	zone.field.clear()
	world.queue_free()
	await get_tree().process_frame

	# --- the leader: a split's ring goes out ahead of the large's death --------
	var lead_world: Node2D = _sm_world()
	var lead_zone := BulletZone.new()
	lead_world.add_child(lead_zone)
	lead_zone.set_process(false)
	var big: BaseEnemy = (load("res://scene/enemy/darkslimelarge.tscn") as PackedScene).instantiate()
	big.name = "sl1"
	big.position = Vector2(-20200, -20000)
	lead_world.get_node("enemies").add_child(big)
	var lead_fire: BaseEnemy = lead_world.get_node("enemies/fs1")
	var lead_dummy := ZoneDummy.new()
	lead_dummy.position = Vector2(-19950, -20000)
	lead_dummy.add_to_group(&"player")
	lead_world.add_child(lead_dummy)
	var link := FakeLink.new()
	link.area = SM_AREA
	link.leader = 1
	add_child(link)
	var sync: Node = _sm_sync(link)
	lead_world.add_child(sync)
	await get_tree().process_frame
	link.sent_world.clear()
	lead_fire.player = lead_dummy
	lead_fire.attack_direction = "right"
	lead_fire.call("fire_projectile")
	big.call("_begin_split")
	sync.tick_lead()
	var kinds: Array = []
	var pincer: Dictionary = {}
	for event in _sm_last_world(link).get("ev", []):
		if int(event.get("id", -1)) == big.net_id:
			kinds.append(str(event.get("k", "")) + ":" + str(event.get("v", "")))
		if int(event.get("id", -1)) == lead_fire.net_id and str(event.get("k", "")) == "b":
			pincer = event
	check("the leader's fire sprite sends its reach with its volley (\"r\")",
		float(pincer.get("r", 0.0)) > 0.0 and not pincer.has("v"), pincer)
	check("the leader's large slime sends its split ring, then its death",
		kinds == ["b:split", "die:"], kinds)

	# 0.25.0: the large's two shots, spray then mortar, each with its reach.
	var big2: BaseEnemy = (load("res://scene/enemy/darkslimelarge.tscn") as PackedScene).instantiate()
	big2.position = Vector2(-20200, -20100)
	lead_world.get_node("enemies").add_child(big2)
	await get_tree().process_frame
	sync.tick_lead()
	big2.player = lead_dummy
	big2.attack_direction = "right"
	link.sent_world.clear()
	big2.call("fire_projectile")
	sync.tick_lead()
	big2.call("fire_projectile")
	sync.tick_lead()
	var big2_volleys: Array = []
	for sent in link.sent_world:
		for event in ((sent as Array)[0] as Dictionary).get("ev", []):
			if int(event.get("id", -1)) == big2.net_id and str(event.get("k", "")) == "b":
				big2_volleys.append(event)
	check("the leader's large slime sends its spray with its reach, then its mortar (\"v\": \"mortar\") (0.25.0)",
		big2_volleys.size() == 2 and not big2_volleys[0].has("v") and float(big2_volleys[0].get("r", 0.0)) > 100.0
		and str(big2_volleys[1].get("v", "")) == "mortar" and float(big2_volleys[1].get("r", 0.0)) > 100.0, big2_volleys)
	lead_world.queue_free()
	link.queue_free()
	for o in others:
		if is_instance_valid(o):
			o.add_to_group(&"player")
	await get_tree().process_frame
	Kit.family_only = false


func _test_field_effects() -> void:
	section("THE FIELD'S ELEMENTS DO SOMETHING (0.86.0) - its orbs carry their effect, at half a boss room's strength")
	var FX: GDScript = load("res://src/characters/statuseffects.gd") as GDScript
	var field_src: String = _code_src("res://src/world/field.gd")
	check("the Field's zone carries its orbs' effects, at FIELD_EFFECTS (0.5)",
		field_src.contains("zone.element_effects = true") and field_src.contains("zone.effect_strength = FIELD_EFFECTS")
		and is_equal_approx(float((load("res://src/world/field.gd") as GDScript).get_script_constant_map().get("FIELD_EFFECTS", 0.0)), 0.5))
	check("  and the zone hands that strength to every effect it puts on",
		_code_src("res://src/world/bulletzone.gd").contains("false, effect_strength)")
		and is_equal_approx(BulletZone.new().effect_strength, 1.0))
	var host := Node2D.new()
	var soft: Node = FX.new()
	soft.host = host
	for k in 5:
		soft.apply(FX.CHILL, 10, Vector2.INF, false, 0.5)
	check("soft: chill is one stack at most, half as long, and never freezes",
		int(soft.chill_stacks) == 1 and float(soft.frozen_left) == 0.0
		and is_equal_approx(float(soft.chill_left), FX.CHILL_SECONDS * 0.5), [soft.chill_stacks, soft.frozen_left, soft.chill_left])
	check("  earth never roots", not soft.apply(FX.ROOT, 10, Vector2.INF, false, 0.5) and float(soft.root_left) == 0.0)
	soft.apply(FX.BURN, 100, Vector2.INF, false, 0.5)
	check("  a burn bites half as hard for half as long",
		int(soft.burn_damage) == maxi(1, roundi(100 * FX.BURN_SHARE * 0.5))
		and is_equal_approx(float(soft.burn_left), FX.BURN_SECONDS * 0.5), [soft.burn_damage, soft.burn_left])
	host.position = Vector2(10, 0)
	soft.apply(FX.SHOVE, 10, Vector2.ZERO, false, 0.5)
	check("  a shove pushes half as hard", is_equal_approx((soft.shove_velocity as Vector2).length(), FX.SHOVE_SPEED * 0.5),
		soft.shove_velocity)
	soft.apply(FX.SOAKED, 10, Vector2.INF, false, 0.5)
	soft.apply(FX.WITHER, 10, Vector2.INF, false, 0.5)
	check("  soaked and withered for half as long",
		is_equal_approx(float(soft.soaked_left), FX.SOAKED_SECONDS * 0.5)
		and is_equal_approx(float(soft.wither_left), FX.WITHER_SECONDS * 0.5))
	var full: Node = FX.new()
	full.host = host
	for k in FX.CHILL_TO_FREEZE:
		full.apply(FX.CHILL, 10)
	check("a boss room's are as they were: chilled to frozen", float(full.frozen_left) > 0.0, full.frozen_left)
	soft.free()
	full.free()
	host.free()
	print("  field effects checked")


# =============================================================================
# THE SERVER OWNS THEIR HEALTH (0.87.0)
# =============================================================================
# The owner, of the leader still being trusted with the monsters: "fix this".
# A server that says "sh" sends its own count of every monster's health each
# tick, and the monsters it brought to zero. A mirror shows that count and
# never the leader's; the leader's own monsters come down to it and never up;
# and a death the count makes is a death on every screen, reported once.

func _test_the_server_owns_monster_health() -> void:
	section("THE SERVER OWNS THEIR HEALTH - every game draws the server's count, and its deaths are deaths")
	var world: Node2D = _sm_world()
	var fs: BaseEnemy = world.get_node("enemies/fs1")
	var link := HealthLink.new()
	link.me = 2
	add_child(link)
	var sync: Node = _sm_sync(link)
	var kills: Array = []
	sync.report_kill = func(enemy_id: String, at: Vector2, _who: Node) -> void: kills.append([enemy_id, at])
	world.add_child(sync)
	await get_tree().process_frame
	link.lead_changed.emit(SM_AREA, 1, 1)
	var origin_fs: String = str(fs.get_meta(&"net_origin", ""))
	link.world_received.emit(JSON.parse_string(JSON.stringify({"full": true, "reset": false, "part": 0,
		"parts": 1, "wave": -1, "spawn": [{"id": 4, "o": origin_fs, "s": "res://scene/enemy/firesprite.tscn",
			"pp": "smworld/enemies", "x": -19950.0, "y": -20000.0, "a": "idledown", "hp": 300,
			"mh": fs.max_hp, "p": fs.net_props()}]})))
	await get_tree().process_frame
	check("a follower draws the leader's monster as before", sync.monsters().get(4) == fs and fs.hp == 300,
		[sync.monsters().keys(), fs.hp])

	sync.apply_world({"snap": [[4, -19950.0, -20000.0, "idledown", 9999]]})
	check("the leader's word on a mirror's health is passed over", fs.hp == 300, fs.hp)
	link.deliver_health([[4, 210, fs.max_hp]])
	check("  the server's count is what it shows", fs.hp == 210, fs.hp)
	link.deliver_health([[4, 260, fs.max_hp]])
	check("  up or down: a mirror shows the count as it is", fs.hp == 260, fs.hp)

	fs.take_damage(12)
	check("your hit on it still goes to the leader, and changes nothing here", fs.hp == 260)
	var fs_id: String = fs.get_enemy_id()
	link.deliver_health([], [4])
	check("a death the server's count made is a death here", fs._death_resolved, fs._death_resolved)
	check("  and your kill, since you hit it - reported once", kills.size() == 1 and kills[0][0] == fs_id, kills)
	sync.apply_world({"ev": [{"k": "die", "id": 4, "x": 0.0, "y": 0.0}]})
	check("  the leader's own word on that death, coming second, reports nothing more", kills.size() == 1, kills)
	world.free()
	link.free()
	await get_tree().process_frame

	# The leader: its monsters come down to the count, never up, and die at its word.
	world = _sm_world()
	fs = world.get_node("enemies/fs1")
	var sn: BaseEnemy = world.get_node("enemies/sn1")
	link = HealthLink.new()
	link.area = SM_AREA
	link.leader = 1
	link.n = 1
	add_child(link)
	sync = _sm_sync(link)
	world.add_child(sync)
	await get_tree().process_frame
	check("the leader runs its own", sync.has_authority() and not fs.net_mirror)
	var top: int = fs.max_hp
	link.deliver_health([[fs.net_id, top - 50, top]])
	check("a hit the server counted that never reached the leader still lands there", fs.hp == top - 50, fs.hp)
	link.deliver_health([[fs.net_id, top, top]])
	check("  but the server never heals what the leader's game has hurt", fs.hp == top - 50, fs.hp)
	link.sent_world.clear()
	var sn_id: int = sn.net_id
	sn._net_remote_hit = true          # somebody else's kill: nothing to report from here
	link.deliver_health([], [sn_id])
	check("a monster the count brought to zero dies on the leader's game too, as from a blow",
		sn._death_resolved and sn.hp == 0, [sn._death_resolved, sn.hp])
	sync.tick_lead()
	var died: bool = false
	for ev in _sm_last_world(link).get("ev", []):
		if ev.get("k", "") == "die" and int(ev.get("id", -1)) == sn_id:
			died = true
	check("  and the leader says so, as for any death", died, _sm_last_world(link))

	link.sent_world.clear()
	link.n = 0
	sync.leader_event(fs, {"k": "mh", "mh": top + 100, "hp": top + 50})
	sync.tick_lead()
	var raised: bool = false
	for ev in _sm_last_world(link).get("ev", []):
		if ev.get("k", "") == "mh" and int(ev.get("id", -1)) == fs.net_id:
			raised = true
	check("a change to a monster's health is told even alone, for the server's count", raised, _sm_last_world(link))
	check("raise_for_stir() tells the area's sync when this game runs the monster",
		_code_src("res://src/enemies/baseenemy.gd").contains('_net_sync.leader_event(self, {"k": "mh", "mh": max_hp, "hp": hp})'))

	var plain := FakeLink.new()
	add_child(plain)
	var sync2: Node = _sm_sync(plain)
	check("a link from before the server owned health is still listened to (no health signal needed)",
		not plain.has_signal(&"health_received") and not sync2._server_health())
	sync2.free()
	plain.free()
	world.free()
	link.free()
	await get_tree().process_frame
	print("  the server's count of monster health checked")

