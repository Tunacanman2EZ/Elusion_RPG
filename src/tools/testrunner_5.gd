# testrunner_5.gd - part 5 of the suite (testrunner.gd says how it is
# split): 40 tests, _test_every_area_floor_is_under_its_floor_effects to _test_the_gm_panel_is_a_window.
extends "res://src/tools/testrunner_4.gd"


func _test_every_area_floor_is_under_its_floor_effects() -> void:
	section("EVERY AREA - its floor draws under what lies on it: craters, scorch, target circles (0.34.1)")
	# What lies on the floor pins an absolute z under the entities' 0: blast
	# marks -2 (blast.gd), a crater's glow, a lit stick, a meteor's shadow, the
	# mage's target circle and the axe's spatter -1, the boss gate's far pane
	# -5. The field, the big field and the town put "ground" at -10 and "water"
	# at -20; the boss room and the arena left both at 0, so every one of those
	# was drawn under the floor there - found while the tank's scorch went in
	# (0.34.0), and checked with a red square at -2 that the arena hid.
	var lowest_effect: int = -5
	var with_ground: Array[String] = []
	var wrong: Array = []
	for area in AreaRegistry.AREAS:
		var src: String = FileAccess.get_file_as_string(str(AreaRegistry.AREAS[area]))
		var ground: Variant = _root_layer_z(src, "ground")
		if ground == null:
			continue
		with_ground.append(str(area))
		var water: Variant = _root_layer_z(src, "water")
		if int(ground) >= lowest_effect or (water != null and int(water) >= int(ground)):
			wrong.append([area, ground, water])
	with_ground.sort()
	check("the ground is below every floor effect, and the water below the ground, in every area that has one",
		wrong.is_empty() and with_ground == ["bigfield", "boss", "bossarena", "elusion", "endless", "field"], [with_ground, wrong])


func _test_monsters_show_who_they_are_after() -> void:
	section("MONSTERS - a red ring round the feet, its dot on whoever the monster is after (0.28.0)")
	# The owner: "i want the same ring for enemies but with a red dot and we
	# will us detection to make the dot aim to the player".
	var sniper: BaseEnemy = (load("res://scene/enemy/darkbushsniper.tscn") as PackedScene).instantiate()
	var ring: ThreatRing = ThreatRing.on(sniper)
	var footprint: Node2D = sniper.get_node("bodyshape") as Node2D
	check("a monster's ring is red, round its feet, and drawn under it",
		sniper.get_child(0) == ring and ring.position.is_equal_approx(footprint.position + Vector2(0, ThreatRing.BELOW_FOOTPRINT))
		and ring.ball_colour.r > 0.9 and ring.ball_colour.g < 0.3 and is_equal_approx(ring.radii.x, 18.0),
		[ring.position, ring.radii, ring.ball_colour])
	var boss: BaseEnemy = (load("res://scene/enemy/bossenemy.tscn") as PackedScene).instantiate()
	var boss_ring: ThreatRing = ThreatRing.on(boss)
	check("  sized to the monster: a boss's is wider than a sniper's",
		boss_ring.radii.x > ring.radii.x + 4.0, [boss_ring.radii, ring.radii])
	boss.free()
	check("every monster puts one on as it is set up, and it flashes as an attack begins",
		_func_body(_code_src("res://src/enemies/baseenemy.gd"), "func _ready(").contains("_threat_ring = ThreatRing.on(self)")
		and _func_body(_code_src("res://src/enemies/baseenemy.gd"), "func _trigger_attack(").contains("_threat_ring.fired()"))

	# Not in the tree: the monster's own setup is navigation and a health bar.
	# Out of the tree _ready() never ran, so its health is set here.
	sniper.set_physics_process(true)
	sniper.position = Vector2.ZERO
	sniper.hp = sniper.max_hp
	sniper.player = null
	ring.visible = true
	ring.refresh()
	check("no one about, or no one after: no ring", not ring.visible, ring.visible)
	# The stand-in player is in the tree (under this Node, so where it is is
	# where it is drawn): out of it, its body's place is never worked out again
	# once read.
	var dummy := ZoneDummy.new()
	add_child(dummy)
	sniper.player = dummy
	var body_of := func() -> Vector2: return (dummy.get_node("bodyshape") as Node2D).global_position
	# Whether it is after them is its AI's (BaseEnemy.keep_after(), 0.30.0),
	# which does not run out of the tree: `think` is that one step of it.
	var think := func() -> void: sniper.keep_after(sniper.global_position.distance_to(dummy.global_position))
	dummy.position = Vector2(-120, 0)
	think.call()
	ring.refresh()
	var toward: Vector2 = (body_of.call() as Vector2).normalized()
	check("a player inside its reach: the ring shows, the dot on their body, full red",
		ring.visible and ring.aim.is_equal_approx(toward) and ring.in_reach
		and is_equal_approx(ring.ball_colour.a, ThreatRing.RED_BALL.a), [ring.visible, ring.aim, toward])
	dummy.position = Vector2(0, sniper.attack_range + 60.0)
	think.call()
	ring.refresh()
	check("  chasing, out of its reach: still shown, the dot dimmed, and it follows",
		ring.visible and not ring.in_reach and ring.ball_colour.a < ThreatRing.RED_BALL.a
		and ring.aim.y > 0.99, [ring.in_reach, ring.aim])
	dummy.position = Vector2(sniper.leash_range + 50.0, 0)
	think.call()
	ring.refresh()
	check("  past the distance it chases from: no ring - it has let them go", not ring.visible)
	dummy.position = Vector2(-120, 0)
	think.call()
	sniper.gated = true
	ring.refresh()
	var gated_hidden: bool = not ring.visible
	sniper.gated = false
	sniper.set_physics_process(false)
	ring.refresh()
	var frozen_hidden: bool = not ring.visible
	sniper.set_physics_process(true)
	sniper._death_resolved = true
	ring.refresh()
	check("  none behind a gate, while frozen (the welcome story) or once dead",
		gated_hidden and frozen_hidden and not ring.visible, [gated_hidden, frozen_hidden, ring.visible])
	sniper._death_resolved = false
	ring.fired()
	check("  and it brightens as an attack begins", ring.get("_glow") > 0.0)
	dummy.free()
	sniper.free()

	# A FOLLOWER'S COPY has no target of its own: it points at the nearest.
	var others: Array = get_tree().get_nodes_in_group(&"player")
	for o in others:
		o.remove_from_group(&"player")
	var world := Node2D.new()
	add_child(world)
	var here := ZoneDummy.new()
	here.position = Vector2(-61000, -61000)
	here.add_to_group(&"player")
	world.add_child(here)
	var copy: BaseEnemy = (load("res://scene/enemy/darkbushsniper.tscn") as PackedScene).instantiate()
	copy.position = Vector2(-61100, -61000)
	world.add_child(copy)
	await get_tree().process_frame
	copy.net_mirror = true
	copy.player = null
	var copy_ring: ThreatRing = copy.get_node_or_null(^"threatring") as ThreatRing
	if copy_ring != null:
		copy_ring.refresh()
	check("a follower's copy of a monster points at the player nearest it",
		copy_ring != null and copy_ring.target() == here and copy_ring.visible and copy_ring.aim.x > 0.9,
		[copy_ring, copy_ring.target() if copy_ring else null])
	world.queue_free()
	for o in others:
		if is_instance_valid(o):
			o.add_to_group(&"player")
	await get_tree().process_frame


# =============================================================================
# HOW FAR THINGS REACH: THE WARRIOR'S REACH, A MONSTER'S DETECTION (0.29.0)
# =============================================================================

func _test_how_far_they_reach() -> void:
	section("RANGE RINGS - how far the warrior's mythic reaches, and how far a monster notices you (0.29.0)")
	# The owner: "now we need one for range on warrior like distance for attack
	# and enemies so i can see their detection range so a much bigger circle",
	# and for the monsters' "Always, faint".
	var line := RangeRing.new()
	line.set_reaches(31.0, 32.0, 25.0, 28.0)
	check("a range line is exact straight out each way, and between them in between",
		is_equal_approx(line.radius_at(PI), 31.0) and is_equal_approx(line.radius_at(0.0), 32.0)
		and is_equal_approx(line.radius_at(-PI / 2.0), 25.0) and is_equal_approx(line.radius_at(PI / 2.0), 28.0)
		and line.radius_at(-PI * 0.75) > 25.0 and line.radius_at(-PI * 0.75) < 31.0,
		[line.radius_at(PI), line.radius_at(0.0), line.radius_at(-PI / 2.0), line.radius_at(PI / 2.0)])
	line.set_radius(500.0)
	check("  a circle is a circle, not squashed like the aim rings: the game measures distance the same every way",
		is_equal_approx(line.radius_at(PI / 2.0), 500.0) and is_equal_approx(line.radius_at(0.7), 500.0))
	check("  dashed, and unshaded (the Field's dark would hide a faint line)",
		line.dash_count() > 100 and line.dash_count() <= RangeRing.MOST_DASHES
		and (line.material as CanvasItemMaterial).light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED,
		line.dash_count())
	line.fired()
	check("  ... and flashes as an attack goes", line.get("_glow") > 0.0 and line.is_processing())
	line.free()

	# THE WARRIOR'S REACH - a mythic's only, since 0.29.1. The owner, of the
	# sword's 25-to-32 px line: "that small circle for warrir for range with that
	# weapon is not needed", and "when holding mythic to show the change in range".
	var warrior: Node2D = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	warrior.call("_add_reach_ring")
	var reach: RangeRing = warrior.get_node_or_null(^"reachring") as RangeRing
	check("the warrior wears a reach ring round its middle, where a throw is measured from, under its sprite",
		reach != null and warrior.get_child(0) == reach and reach.position == Vector2.ZERO, reach)
	check("  with a sword or nothing in hand there is no ring",
		reach != null and not reach.visible and is_zero_approx(warrior.call("mythic_reach", ItemData.WeaponAttack.NONE)),
		reach)
	warrior.call("_show_reach_for", ItemData.WeaponAttack.SPINNING_AXE)
	var axe: float = SpinningAxe.MAX_THROW + SpinningAxe.HIT_RADIUS
	check("  with the Double Axe it shows, at the furthest throw plus the blade, every way (190)",
		reach.visible and is_equal_approx(axe, 190.0) and is_equal_approx(reach.reach_left, axe)
		and is_equal_approx(reach.reach_up, axe) and is_equal_approx(reach.reach_down, axe),
		[reach.visible, reach.reach_left, reach.reach_up])
	warrior.call("_show_reach_for", ItemData.WeaponAttack.NONE)
	check("  and the axe taken off takes the ring with it", not reach.visible)
	warrior.free()
	var wsrc: String = _code_src("res://src/characters/warrior.gd")
	check("  put on in _ready(), refitted when gear changes, flashed by every throw, gone when dying",
		_func_body(wsrc, "func _ready(").contains("_add_reach_ring()")
		and _func_body(wsrc, "func _on_gear_changed(").contains("_fit_reach_ring()")
		and _func_body(wsrc, "func _fit_reach_ring(").contains("_show_reach_for(equipped_weapon_attack())")
		and _func_body(wsrc, "func attack_action(").contains("_reach_ring.fired()")
		and _func_body(wsrc, "func _physics_process(").contains("_reach_ring.visible = _reach_ring_shown()")
		and _func_body(wsrc, "func _reach_ring_shown(").contains("_mythic_reach > 0.0 and not is_dying"))

	# A MONSTER'S DETECTION, round its middle, always there - since 0.30.0 two
	# lines: how close you can come before it notices, and once it is after
	# you, how far you have to get.
	var sniper: BaseEnemy = (load("res://scene/enemy/darkbushsniper.tscn") as PackedScene).instantiate()
	var ring: ThreatRing = ThreatRing.on(sniper)
	var sense: RangeRing = sniper.get_node_or_null(^"detectionring") as RangeRing
	check("a monster carries a detection circle round its middle, beside its red ring, under its picture",
		sense != null and ring.sense == sense and sniper.get_child(0) == ring and sniper.get_child(1) == sense
		and sense.position == Vector2.ZERO, [sense, sniper.get_child(1)])
	sniper.set_physics_process(true)
	sniper.hp = sniper.max_hp
	sniper.player = null
	ring.refresh()
	check("  with no one about it is there all the same, faint, as wide as it notices from (250, inside its 500 leash)",
		sense.visible and is_equal_approx(sense.reach_up, 250.0) and is_equal_approx(sense.reach_left, 250.0)
		and is_equal_approx(sniper.notice_reach(), 250.0) and is_equal_approx(sniper.leash_range, 500.0)
		and sense.colour.is_equal_approx(ThreatRing.SENSE_IDLE), [sense.visible, sense.reach_up, sniper.leash_range])
	var dummy := ZoneDummy.new()
	add_child(dummy)
	sniper.player = dummy
	# Its AI's step (BaseEnemy.keep_after()), which does not run out of the tree.
	var think := func() -> void: sniper.keep_after(sniper.global_position.distance_to(dummy.global_position))
	dummy.position = Vector2(300.0, 0)
	think.call()
	ring.refresh()
	check("  inside its leash but outside that line, it has not noticed you: faint, 250, no red dot",
		sense.visible and sense.colour.is_equal_approx(ThreatRing.SENSE_IDLE) and is_equal_approx(sense.reach_right, 250.0)
		and not ring.visible and not sniper.engaged)
	dummy.position = Vector2(230.0, 0)
	think.call()
	ring.refresh()
	check("  across it, it is after you: the circle goes out to its leash (500), brighter, and the dot is on you",
		sniper.engaged and sense.colour.is_equal_approx(ThreatRing.SENSE_AFTER) and is_equal_approx(sense.reach_right, 500.0)
		and ring.visible, [sniper.engaged, sense.reach_right])
	dummy.position = Vector2(480.0, 0)
	think.call()
	ring.refresh()
	check("  back out past 250 it keeps after you, all the way to the leash",
		sniper.engaged and ring.visible and is_equal_approx(sense.reach_right, 500.0))
	dummy.position = Vector2(520.0, 0)
	think.call()
	ring.refresh()
	check("  past the leash it has let you go: faint, back to 250, no dot",
		not sniper.engaged and sense.colour.is_equal_approx(ThreatRing.SENSE_IDLE)
		and is_equal_approx(sense.reach_right, 250.0) and not ring.visible)
	sniper.leash_range = 1500.0
	think.call()
	ring.refresh()
	check("  a bush mage's 1,500 leash is how far it chases, not how far it notices (still 250)",
		not sniper.engaged and is_equal_approx(sense.reach_right, 250.0))
	sniper.engaged = true
	ring.refresh()
	check("  ... and once after you, its circle is the 1,500", is_equal_approx(sense.reach_right, 1500.0))
	sniper.engaged = false
	sniper.leash_range = 200.0
	ring.refresh()
	check("  a leash shorter than 250 (the Big Field's 250, or less) is how far it notices too",
		is_equal_approx(sniper.notice_reach(), 200.0) and is_equal_approx(sense.reach_right, 200.0))
	sniper.leash_range = 500.0
	sniper.gated = true
	ring.refresh()
	var gated_hidden: bool = not sense.visible
	sniper.gated = false
	sniper.set_physics_process(false)
	ring.refresh()
	var frozen_hidden: bool = not sense.visible
	sniper.set_physics_process(true)
	sniper._death_resolved = true
	ring.refresh()
	check("  none behind a gate, while frozen (the welcome story) or once dead - it notices no one then",
		gated_hidden and frozen_hidden and not sense.visible, [gated_hidden, frozen_hidden, sense.visible])
	dummy.free()
	sniper.free()
	var boss: BaseEnemy = (load("res://scene/enemy/bossenemy.tscn") as PackedScene).instantiate()
	check("  a boss notices as far as it chases, as it always did", is_equal_approx(boss.notice_reach(), boss.leash_range),
		[boss.notice_reach(), boss.leash_range])
	boss.free()


# =============================================================================
# NOTICE CLOSE, CHASE FAR (0.30.0)
# =============================================================================

func _test_monsters_notice_close_and_chase_far() -> void:
	section("MONSTERS - notice you close, chase you far: notice_range, then leash_range (0.30.0)")
	# The owner: "now fix monster leash and radius", picking "Notice close,
	# chase far". A real monster's own AI, in the tree, a long way from
	# everything, with a stand-in player.
	var others: Array = get_tree().get_nodes_in_group(&"player")
	for o in others:
		o.remove_from_group(&"player")
	var world := Node2D.new()
	add_child(world)
	var home := Vector2(-63000, -63000)
	var you := ZoneDummy.new()
	you.position = home + Vector2(320, 0)
	you.add_to_group(&"player")
	world.add_child(you)
	var monster: BaseEnemy = (load("res://scene/enemy/darkbushsniper.tscn") as PackedScene).instantiate()
	monster.position = home
	world.add_child(monster)
	for i in 8:
		await get_tree().physics_frame
	check("a monster with you inside its leash (500) but further than it notices (250) has not noticed you",
		is_instance_valid(monster.player) and monster.player == you and not monster.engaged
		and monster.global_position.distance_to(home) < 2.0,
		[monster.player, monster.engaged, monster.global_position - home])
	you.position = home + Vector2(240, 0)
	for i in 4:
		await get_tree().physics_frame
	check("  step inside 250 and it is after you", monster.engaged and not monster.is_returning_home)
	you.position = home + Vector2(470, 0)
	for i in 4:
		await get_tree().physics_frame
	check("  step back out to 470 and it is still after you - it chases to its leash",
		monster.engaged, monster.global_position.distance_to(you.global_position))
	you.position = home + Vector2(700, 0)
	for i in 4:
		await get_tree().physics_frame
	check("  past the leash it lets you go and heads home", not monster.engaged)
	you.position = monster.global_position + Vector2(380, 0)
	for i in 4:
		await get_tree().physics_frame
	var unnoticed: bool = not monster.engaged
	monster.take_damage(1)
	for i in 4:
		await get_tree().physics_frame
	check("  shot from outside 250 (inside its leash), it notices you all the same",
		unnoticed and monster.engaged, [unnoticed, monster.engaged])
	world.queue_free()
	for o in others:
		if is_instance_valid(o):
			o.add_to_group(&"player")
	await get_tree().process_frame
	var src: String = _code_src("res://src/enemies/bushmage.gd")
	check("the bush mage, which runs its own AI, notices the same way",
		_func_body(src, "func _physics_process(").contains("keep_after(dist)")
		and not _func_body(src, "func _physics_process(").contains("if dist > leash_range"))
	check("a slime's twin and its smalls are after whoever it was after",
		_func_body(_code_src("res://src/enemies/poisonslime.gd"), "func _spawn_slime(").contains("slime.engaged = engaged"))


# =============================================================================
# THE MAGE'S OFF HAND: TOMES, WANDS AND GRIMOIRES (0.32.0)
# =============================================================================

func _test_the_mage_has_an_off_hand() -> void:
	section("MAGE AND HEALER - a tome, a wand or a grimoire in the off hand (0.32.0)")
	# The owner: "i noticed mage hass no offhand", then, shown what the art pack
	# held, "tombs grimoires and off hand wands i can make them special later but
	# give them some stats" - and, for the healer, which had none either: "and
	# the healer?" (0.32.1). Read as text, so a clone without the pack checks
	# the numbers too.
	var dir := "res://data/items/armour/"
	var missing: Array = []
	var wrong_slot: Array = []
	var off_rung: Array = []
	var last_tome := {"armor_value": 0, "bonus_max_mana": 0}
	var last_wand := {"bonus_damage_percent": 0, "bonus_max_mana": 0}
	var tomes_rise := true
	var wands_rise := true
	for row in _OFFHAND_TIERS:
		var t: String = row[0]
		var shield: Dictionary = _tres_fields(dir + t + "shield.tres")
		for kind in ["tome", "wand"]:
			var f: Dictionary = _tres_fields(dir + t + kind + ".tres")
			if f.is_empty():
				missing.append(t + kind)
				continue
			if f.get("equip_slot") != "6" or f.get("required_classes") != "Array[String]([\"mage\", \"healer\"])" \
					or f.get("item_id") != t + kind:
				wrong_slot.append(t + kind)
			for key in ["tier", "required_level", "value"]:
				if f.get(key) != shield.get(key):
					off_rung.append([t + kind, key, f.get(key), shield.get(key)])
			if kind == "tome":
				tomes_rise = tomes_rise and int(f.get("armor_value", "0")) > last_tome["armor_value"] \
					and int(f.get("bonus_max_mana", "0")) > last_tome["bonus_max_mana"]
				last_tome = {"armor_value": int(f.get("armor_value", "0")), "bonus_max_mana": int(f.get("bonus_max_mana", "0"))}
			else:
				wands_rise = wands_rise and int(f.get("bonus_damage_percent", "0")) > last_wand["bonus_damage_percent"] \
					and int(f.get("bonus_max_mana", "0")) > last_wand["bonus_max_mana"]
				last_wand = {"bonus_damage_percent": int(f.get("bonus_damage_percent", "0")), "bonus_max_mana": int(f.get("bonus_max_mana", "0"))}
	check("a tome and a wand at every tier, iron to ember", missing.is_empty(), missing)
	check("  in the off hand (the shield square), for the mage and the healer and nobody else", wrong_slot.is_empty(), wrong_slot)
	check("  each on its tier's shield rung: same tier, level and price", off_rung.is_empty(), off_rung)
	check("  a tome is armour and mana, a wand damage and mana, and each tier is more than the last",
		tomes_rise and wands_rise, [last_tome, last_wand])
	var grimoires_ok := true
	for id in _GRIMOIRES:
		var g: Dictionary = _tres_fields(dir + id + ".tres")
		grimoires_ok = grimoires_ok and g.get("tier") == "5" and g.get("required_level") == "22" \
			and g.get("equip_slot") == "6" and g.get("required_classes") == "Array[String]([\"mage\", \"healer\"])" \
			and int(g.get("bonus_max_mana", "0")) > 0 and int(g.get("bonus_damage_percent", "0")) > 0 \
			and int(g.get("value", "0")) > int(_tres_fields(dir + "embertome.tres").get("value", "0"))
	check("three grimoires at the top: tier 5, level 22, mana and damage, dearer than the ember tome", grimoires_ok)

	# On the shelf: iron to amethyst, like every piece; ember and the grimoires drop.
	var stock: Array[String] = (load("res://data/shops/generalstore.tres") as ShopData).stock
	var shelf := true
	for row in _OFFHAND_TIERS:
		var on: bool = stock.has(row[0] + "tome") and stock.has(row[0] + "wand")
		shelf = shelf and (on if int(row[1]) <= 4 else not on)
	for id in _GRIMOIRES:
		shelf = shelf and not stock.has(id)
	check("the store sells iron to amethyst tomes and wands, beside each shield; ember and grimoires drop",
		shelf and stock.find("irontome") == stock.find("ironshield") + 1)

	# The server's catalogue has them as the game does.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/gamedata.json"))
	var exported: Dictionary = {}
	for item in data.get("items", []):
		exported[str(item.get("item_id", ""))] = item
	var all_ids: Array = _GRIMOIRES.duplicate()
	for row in _OFFHAND_TIERS:
		all_ids.append(row[0] + "tome")
		all_ids.append(row[0] + "wand")
	var not_exported: Array = []
	for id in all_ids:
		if not exported.has(id) or exported[id].get("equip_slot_name") != "SHIELD" \
				or exported[id].get("required_classes") != ["mage", "healer"]:
			not_exported.append(id)
	check("gamedata.json carries all thirteen, in the SHIELD square, the mage's and the healer's", not_exported.is_empty(), not_exported)

	# The pictures, from the Raven Fantasy pack - 16 px like every item icon.
	var bad_icons: Array = []
	for id in all_ids:
		var icon: Texture2D = load("res://art/pack/armour/%s.png" % id) as Texture2D \
			if ResourceLoader.exists("res://art/pack/armour/%s.png" % id) else null
		if icon == null or icon.get_size() != Vector2(16, 16):
			bad_icons.append(id)
	check_needs_pack("  each has its own 16 px icon in the pack", bad_icons.is_empty(), bad_icons)
	var mage_ok: bool = ItemRegistry.has_item("irontome") \
		and ItemRegistry.get_item("irontome").required_classes == ["mage", "healer"] \
		and ItemData.slot_name(ItemRegistry.get_item("embertome").equip_slot) == "shield"
	check_needs_pack("  and the game's registry has them", mage_ok)


# =============================================================================
# PRESSING IN, AND THE RINGS' TWO SWITCHES (0.31.0)
# =============================================================================

func _test_monsters_walk_in_between_attacks() -> void:
	section("MONSTERS - walk in on you between attacks, to half their range (0.31.0)")
	# The owner: "i want enemies to actually chase the player closer while
	# attacking". A real darkbushsniper's AI, in the tree, far from everything.
	var sniper_probe: BaseEnemy = (load("res://scene/enemy/darkbushsniper.tscn") as PackedScene).instantiate()
	var sprite_probe: BaseEnemy = (load("res://scene/enemy/electricsprite.tscn") as PackedScene).instantiate()
	var boss_probe: BaseEnemy = (load("res://scene/enemy/bossenemy.tscn") as PackedScene).instantiate()
	sniper_probe.attack_range = 200.0
	sniper_probe.flee_range = 50.0
	sprite_probe.attack_range = 280.0
	sprite_probe.flee_range = 50.0
	check("a monster walks in to half its attack range, never inside where it would turn and flee",
		is_equal_approx(sprite_probe.press_reach(), 140.0)
		and is_equal_approx(sniper_probe.press_reach(), 50.0 * BaseEnemy.FLEE_RELEASE_FACTOR + BaseEnemy.PRESS_CLEAR),
		[sprite_probe.press_reach(), sniper_probe.press_reach()])
	boss_probe.attack_range = 120.0
	check("  a boss holds its spacing at its attack range", is_equal_approx(boss_probe.press_reach(), 120.0))
	sniper_probe.free()
	sprite_probe.free()
	boss_probe.free()

	var others: Array = get_tree().get_nodes_in_group(&"player")
	for o in others:
		o.remove_from_group(&"player")
	var world := Node2D.new()
	add_child(world)
	var home := Vector2(-65000, -65000)
	var you := ZoneDummy.new()
	# Out of its notice to begin with, so it has not fired before the test
	# puts it between two attacks.
	you.position = home + Vector2(400, 0)
	you.add_to_group(&"player")
	world.add_child(you)
	var monster: BaseEnemy = (load("res://scene/enemy/darkbushsniper.tscn") as PackedScene).instantiate()
	monster.position = home
	world.add_child(monster)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# In the middle of a fight, between two attacks: after you, not ready.
	monster.engaged = true
	monster.attack_ready = false
	you.position = home + Vector2(190, 0)
	var start: float = monster.global_position.distance_to(you.global_position)
	for i in 30:
		await get_tree().physics_frame
	var after: float = monster.global_position.distance_to(you.global_position)
	check("inside its attack range (190 of 200) and between attacks, it walks in on you",
		start > monster.press_reach() and after < start - 15.0 and not monster.is_attacking, [start, after])
	you.position = monster.global_position + Vector2(monster.press_reach() - 10.0, 0)
	var held_at: Vector2 = monster.global_position
	for i in 20:
		await get_tree().physics_frame
	check("  within half its range it holds there and waits for its next attack",
		monster.global_position.distance_to(held_at) < 3.0 and not monster.is_attacking,
		monster.global_position - held_at)
	world.queue_free()
	for o in others:
		if is_instance_valid(o):
			o.add_to_group(&"player")
	await get_tree().process_frame
	check("  and the moment it is ready it attacks from wherever it stands - pressing in only fills the wait",
		_func_body(_code_src("res://src/enemies/baseenemy.gd"), "func _handle_combat(").contains(
			"if not attack_ready and dist_to_player > press_reach():"))


func _test_the_rings_have_switches() -> void:
	section("OPTIONS - Aim rings and Range circles switch the rings on the floor (0.31.0)")
	# The owner: "add the option in options to enable veiw of the circles or
	# disable".
	var kept_aim: bool = bool(Settings.get_value("aim_rings"))
	var kept_range: bool = bool(Settings.get_value("range_circles"))
	check("both are on unless you turn them off",
		Settings.DEFAULTS["aim_rings"] == true and Settings.DEFAULTS["range_circles"] == true)
	Settings.set_value("aim_rings", true)
	Settings.set_value("range_circles", true)

	var warrior: Node2D = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	warrior.call("_add_aim_ring")
	warrior.call("_add_reach_ring")
	var aim: AimRing = warrior.get_node(^"aimring") as AimRing
	var reach: RangeRing = warrior.get_node(^"reachring") as RangeRing
	warrior.call("_point_aim_ring", Vector2.LEFT)
	warrior.call("_show_reach_for", ItemData.WeaponAttack.SPINNING_AXE)
	var both_on: bool = aim.visible and reach.visible
	Settings.set_value("aim_rings", false)
	warrior.call("_point_aim_ring", Vector2.LEFT)
	var aim_off: bool = not aim.visible and reach.visible
	Settings.set_value("range_circles", false)
	warrior.call("_show_reach_for", ItemData.WeaponAttack.SPINNING_AXE)
	var range_off: bool = not reach.visible
	check("Aim rings off takes away your aim ring; Range circles off, the mythic's reach",
		both_on and aim_off and range_off, [both_on, aim_off, range_off])
	warrior.free()

	Settings.set_value("aim_rings", true)
	Settings.set_value("range_circles", true)
	var sniper: BaseEnemy = (load("res://scene/enemy/darkbushsniper.tscn") as PackedScene).instantiate()
	var ring: ThreatRing = ThreatRing.on(sniper)
	sniper.set_physics_process(true)
	sniper.hp = sniper.max_hp
	var dummy := ZoneDummy.new()
	add_child(dummy)
	dummy.position = Vector2(-120, 0)
	sniper.player = dummy
	sniper.engaged = true
	ring.refresh()
	var monster_on: bool = ring.visible and ring.sense.visible
	Settings.set_value("aim_rings", false)
	ring.refresh()
	var red_off: bool = not ring.visible and ring.sense.visible
	Settings.set_value("range_circles", false)
	ring.refresh()
	var sense_off: bool = not ring.sense.visible
	Settings.set_value("aim_rings", true)
	Settings.set_value("range_circles", true)
	ring.refresh()
	var back_on: bool = ring.visible and ring.sense.visible
	check("  a monster's red ring goes with Aim rings, its detection circle with Range circles, and both come back",
		monster_on and red_off and sense_off and back_on, [monster_on, red_off, sense_off, back_on])
	dummy.free()
	sniper.free()

	var screen_src: String = _code_src("res://src/ui/menus/optionsscreen.gd")
	check("  the Options switches set them, and show what is set",
		_func_body(screen_src, "func _on_aim_rings_toggled(").contains("Settings.set_value(\"aim_rings\", pressed)")
		and _func_body(screen_src, "func _on_range_circles_toggled(").contains("Settings.set_value(\"range_circles\", pressed)")
		and screen_src.contains("aim_rings_toggle.button_pressed = bool(Settings.get_value(\"aim_rings\"))")
		and screen_src.contains("range_circles_toggle.button_pressed = bool(Settings.get_value(\"range_circles\"))"))
	Settings.set_value("aim_rings", kept_aim)
	Settings.set_value("range_circles", kept_range)


# =============================================================================
# THE COOKING PANEL'S RUN (0.25.2)
# =============================================================================

func _test_the_cooking_window_cooks_meals() -> void:
	section("COOKING - the Recipes tab: every meal, have and need, Cook and Cook all on the fire (0.74.0)")
	var herb := _larder_item("zz_larder_herb", "Test Herb", Color(0.6, 1, 0.6))
	var flour := _larder_item("zz_larder_flour", "Test Flour", Color(1, 1, 0.9))
	var salt := _larder_item("zz_larder_salt", "Test Salt", Color(0.9, 0.9, 1))
	# A bread that never burns, a soup made FROM the bread that can, and a feast
	# a level-20 cook cannot make yet.
	var bread := _larder_meal("zz_larder_bread", "Test Bread", Color(1, 0.8, 0.5),
		{"zz_larder_herb": 1, "zz_larder_flour": 2}, 1, 1, 14, ItemData.BuffKind.VIGOUR, 10, 600)
	var soup := _larder_meal("zz_larder_soup", "Test Soup", Color(0.8, 0.6, 1),
		{"zz_larder_bread": 1, "zz_larder_salt": 1}, 5, 30, 30, ItemData.BuffKind.GUARD, 3, 900)
	var feast := _larder_meal("zz_larder_feast", "Test Feast", Color(1, 0.5, 0.5),
		{"zz_larder_herb": 1}, 50, 60, 80, ItemData.BuffKind.MIGHT, 5, 600)
	var made: Array[ItemData] = [herb, flour, salt, bread, soup, feast]
	for data in made:
		ItemRegistry._items[data.item_id] = data

	var server := LarderServer.new()
	add_child(server)
	if not server.start():
		check("a free local port for the suite's larder server", false)
		server.queue_free()
		for data in made:
			ItemRegistry._items.erase(data.item_id)
		return
	var kept: Array = _larder_serve(server)
	var huds: Array = get_tree().get_nodes_in_group(&"hud")
	for h in huds:
		h.remove_from_group(&"hud")
	var hud := CookingHud.new()
	hud.add_to_group(&"hud")
	add_child(hud)
	var screen_node := Node.new()
	hud.add_child(screen_node)
	hud.inventory_screen = screen_node
	var bag := CookingBag.new()
	bag.name = "inventorycontainer"
	screen_node.add_child(bag)
	bag.owner = screen_node
	bag.unique_name_in_owner = true
	bag.counts = {"zz_larder_herb": 3, "zz_larder_flour": 6}
	server.bag = bag
	server.burns = [false, true, false]
	var cook := CookingCook.new()
	add_child(cook)

	var panel: Control = (load("res://scene/ui/cooking/cookingscreen.tscn") as PackedScene).instantiate()
	add_child(panel)
	panel.set("cook_duration", 0.1)
	panel.set("cook_interval", 0.05)
	panel.set("burnt_hold", 0.25)
	panel.open_for_firepit(null, cook)
	await get_tree().process_frame
	var Cooking: Script = panel.get_script() as Script
	var fish_tab: Button = panel.find_child("fishtab", true, false) as Button
	var recipes_tab: Button = panel.find_child("recipestab", true, false) as Button
	var grid: Control = panel.find_child("fishgrid", true, false) as Control
	var scroll: ScrollContainer = panel.find_child("recipescroll", true, false) as ScrollContainer
	var list: Control = panel.find_child("recipelist", true, false) as Control
	check("the cooking window opens on its Fish tab, with the fish under the fire as before",
		fish_tab != null and recipes_tab != null and fish_tab.button_pressed and not recipes_tab.button_pressed
		and grid.visible and not scroll.visible)

	var top: float = panel.position.y
	var middle: float = panel.position.x + panel.size.x * 0.5
	recipes_tab.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check("the Recipes tab shows the meals in the fish's place, and is the tab held down",
		scroll.visible and not grid.visible and recipes_tab.button_pressed and not fish_tab.button_pressed)
	# THE TOP STAYS unless the taller window would then hang off the bottom of
	# the screen, when it is pushed up just far enough (PanelWindow.fit_to()).
	var room: float = panel.get_viewport_rect().size.y - panel.size.y
	check("  the window fits what it now holds, its middle where it was and its top too, unless the screen says no",
		panel.size == PanelWindow.content_minimum(panel) and is_equal_approx(panel.position.y, minf(top, room))
		and absf(panel.position.x + panel.size.x * 0.5 - middle) <= 1.0,
		[panel.size, PanelWindow.content_minimum(panel), panel.position, top, middle])
	var first_row: float = (list.get_child(0) as Control).get_combined_minimum_size().y if list.get_child_count() > 0 else 0.0
	var four: float = first_row * Cooking.RECIPE_ROWS_SHOWN \
		+ float(list.get_theme_constant("separation")) * (Cooking.RECIPE_ROWS_SHOWN - 1)
	# MORE MEALS THAN FOUR ROWS needs the real catalogue: a clone without the
	# art pack loads none of its meals (their icons are the pack's), and the
	# stand-ins alone are a list too short to scroll (0.74.0, at the merge).
	if list.get_child_count() > Cooking.RECIPE_ROWS_SHOWN:
		check("  and the list shows four whole meals and scrolls the rest, rather than growing off the screen",
			Cooking.RECIPE_ROWS_SHOWN == 4 and first_row > 0.0 and list.get_combined_minimum_size().y > four
			and is_equal_approx(scroll.custom_minimum_size.y, four)
			and panel.position.y >= 0.0 and panel.position.y + panel.size.y <= panel.get_viewport_rect().size.y,
			[scroll.custom_minimum_size, four, list.get_combined_minimum_size()])
	else:
		check_needs_pack("  and the list shows four whole meals and scrolls the rest, rather than growing off the screen",
			false, "fewer meals than four rows - the real catalogue's are missing")
		check("  and a list shorter than four rows shows every meal whole, with nothing to scroll",
			first_row > 0.0 and is_equal_approx(scroll.custom_minimum_size.y, list.get_combined_minimum_size().y),
			[scroll.custom_minimum_size, list.get_combined_minimum_size()])

	var meals: Array = Cooking.meals()
	var every_meal: int = 0
	for data in ItemRegistry.get_all_items():
		if data != null and data.is_meal():
			every_meal += 1
	var by_level: bool = true
	for i in range(1, meals.size()):
		if (meals[i] as ItemData).recipe_level < (meals[i - 1] as ItemData).recipe_level:
			by_level = false
	var row_names: Array = list.get_children().map(func(n: Node) -> String: return str(n.name))
	check("every meal in the catalogue has a row, by the cooking level it needs",
		meals.size() == every_meal and by_level and meals.size() >= 3
		and row_names == meals.map(func(m: ItemData) -> String: return "recipe_" + m.item_id),
		[meals.size(), every_meal, row_names.size()])

	var rows: Dictionary = panel.get("_recipe_rows")
	var count_of := func(meal_id: String, part: String) -> Label:
		return (rows[meal_id]["counts"] as Dictionary)[part]
	var bread_row: Dictionary = rows.get("zz_larder_bread", {})
	var soup_row: Dictionary = rows.get("zz_larder_soup", {})
	var feast_row: Dictionary = rows.get("zz_larder_feast", {})
	var herb_count: Label = count_of.call("zz_larder_bread", "zz_larder_herb")
	var flour_count: Label = count_of.call("zz_larder_bread", "zz_larder_flour")
	check("each ingredient shows have/need from the bag, green when there is enough",
		herb_count.text == "3/1" and flour_count.text == "6/2"
		and herb_count.get_theme_color("font_color").is_equal_approx(Cooking.HAVE_ENOUGH)
		and flour_count.get_theme_color("font_color").is_equal_approx(Cooking.HAVE_ENOUGH),
		[herb_count.text, flour_count.text])
	var soup_bread: Label = count_of.call("zz_larder_soup", "zz_larder_bread")
	var soup_salt: Label = count_of.call("zz_larder_soup", "zz_larder_salt")
	check("  red when it is short - and a meal can be an ingredient: the soup counts the breads in the bag",
		soup_bread.text == "0/1" and soup_salt.text == "0/1"
		and soup_bread.get_theme_color("font_color").is_equal_approx(Cooking.HAVE_SHORT)
		and soup_salt.get_theme_color("font_color").is_equal_approx(Cooking.HAVE_SHORT),
		[soup_bread.text, soup_salt.text])
	var bread_effects: Control = (bread_row["row"] as Node).find_child("effects", true, false) as Control
	var heal_label: Label = bread_effects.get_node("heal") as Label
	var buff_label: Label = bread_effects.get_node("buff") as Label
	check("a row says what the meal heals and the buff it gives, in the buff's colour",
		heal_label.text == "Heals 14" and buff_label.text == bread.buff_text() and bread.buff_text() != ""
		and buff_label.get_theme_color("font_color").is_equal_approx(FoodBuff.colour_for(ItemData.BuffKind.VIGOUR)),
		[heal_label.text, buff_label.text])
	var bread_cook: Button = bread_row["cook"]
	var bread_all: Button = bread_row["cookall"]
	check("  and the level it needs, in gold when yours is enough; Cook and Cook all (3) are there to press",
		(bread_row["level"] as Label).text == "Lv 1"
		and (bread_row["level"] as Label).get_theme_color("font_color").is_equal_approx(Cooking.LEVEL_OPEN)
		and not bread_cook.disabled and not bread_all.disabled and bread_all.text == "Cook all (3)",
		[(bread_row["level"] as Label).text, bread_cook.disabled, bread_all.text])
	check("a meal the bag cannot make is greyed out of its buttons, and says what is missing",
		(soup_row["cook"] as Button).disabled and (soup_row["cookall"] as Button).disabled
		and (soup_row["cook"] as Button).tooltip_text == "You are missing Test Bread",
		(soup_row["cook"] as Button).tooltip_text)
	var feast_level: Label = feast_row["level"]
	check("a meal above your cooking level is locked: its level greyed, its buttons off, the level on them",
		feast_level.text == "Lv 50" and feast_level.get_theme_color("font_color").is_equal_approx(Cooking.LEVEL_LOCKED)
		and (feast_row["cook"] as Button).disabled and (feast_row["cookall"] as Button).disabled
		and (feast_row["cook"] as Button).tooltip_text == "Needs cooking level 50",
		[feast_level.text, (feast_row["cook"] as Button).tooltip_text])
	var flash: Label = panel.find_child("flash", true, false) as Label
	panel.call("_start_recipe", "zz_larder_feast", 1)
	check("  and asked anyway, it says why and asks the server nothing",
		flash.text == "Needs cooking level 50." and server.asked.is_empty(), [flash.text, server.asked])

	# ---- Cook: one meal, on the fire like a fish ----
	var icon: TextureRect = panel.find_child("cookicon", true, false) as TextureRect
	var bar: ProgressBar = panel.find_child("riskbar", true, false) as ProgressBar
	var words: Label = panel.find_child("catchlabel", true, false) as Label
	var events: Array = []
	panel.connect(&"fish_started", func(id: String) -> void:
		var stop_text: String = ""
		if rows.has(id):
			stop_text = (rows[id]["cookall"] as Button).text
		events.append({"k": "on", "id": id, "tint": icon.modulate, "icon": icon.texture, "words": words.text,
			"all": stop_text, "herbs": herb_count.text}))
	panel.connect(&"fish_done", func(id: String, burnt: bool) -> void:
		var fill: StyleBoxFlat = bar.get_theme_stylebox("fill") as StyleBoxFlat
		events.append({"k": "done", "id": id, "burnt": burnt, "tint": icon.modulate, "icon": icon.texture,
			"words": words.text, "bar": bar.value, "fill": fill.bg_color if fill != null else Color.BLACK}))
	panel.connect(&"run_ended", func() -> void: events.append({"k": "end", "flash": flash.text}))
	var ended := func(n: int) -> bool:
		return events.filter(func(e: Dictionary) -> bool: return e.k == "end").size() >= n

	bread_cook.pressed.emit()
	await _larder_wait(ended.bind(1), 5.0)
	var first: Dictionary = server.asked[0] if not server.asked.is_empty() else {}
	check("Cook asks /api/cooking/recipe for one of that meal, by its recipe id and nothing else",
		server.asked.size() == 1 and str(first.get("path", "")) == "/api/cooking/recipe"
		and (first.get("body", {}) as Dictionary).get("recipe_id") == "zz_larder_bread"
		and not (first.get("body", {}) as Dictionary).has("item_id")
		and (first.get("body", {}) as Dictionary).has("slot"), server.asked)
	var ons: Array = events.filter(func(e: Dictionary) -> bool: return e.k == "on")
	var dones: Array = events.filter(func(e: Dictionary) -> bool: return e.k == "done")
	check("  the meal goes on the fire as itself, faded, its name under it (a bread that cannot burn says no chance)",
		ons.size() == 1 and ons[0].icon == bread.icon
		and (ons[0].tint as Color).is_equal_approx(bread.icon_tint * Cooking.MEAL_COOKING_TINT)
		and str(ons[0].words) == "Test Bread", ons)
	check("  and comes off solid, its bar full and gold",
		dones.size() == 1 and not dones[0].burnt and dones[0].icon == bread.icon
		and (dones[0].tint as Color).is_equal_approx(bread.icon_tint) and str(dones[0].words) == "Test Bread"
		and is_equal_approx(float(dones[0].bar), 100.0) and (dones[0].fill as Color).is_equal_approx(Cooking.COOK_FILL),
		dones)
	check("the server's bag is the one drawn: the ingredients gone, the meal in",
		bag.get_quantity_of("zz_larder_herb") == 2 and bag.get_quantity_of("zz_larder_flour") == 4
		and bag.get_quantity_of("zz_larder_bread") == 1, bag.counts)
	check("  and the rows count again from it: the soup now has its bread",
		herb_count.text == "2/1" and flour_count.text == "4/2" and soup_bread.text == "1/1"
		and soup_bread.get_theme_color("font_color").is_equal_approx(Cooking.HAVE_ENOUGH),
		[herb_count.text, flour_count.text, soup_bread.text])

	# ---- Cook all: as many as the bag makes, one request at a time ----
	bread_all.pressed.emit()
	await _larder_wait(ended.bind(2), 6.0)
	ons = events.filter(func(e: Dictionary) -> bool: return e.k == "on")
	dones = events.filter(func(e: Dictionary) -> bool: return e.k == "done")
	var ends: Array = events.filter(func(e: Dictionary) -> bool: return e.k == "end")
	check("Cook all cooks as many as the bag holds the ingredients for - two more - one request each",
		server.recipes_asked().size() == 3 and dones.size() == 3, [server.recipes_asked().size(), dones.size()])
	check("  the rows count again after every meal of a run, not only when it ends",
		ons.size() == 3 and str(ons[1].herbs) == "2/1" and str(ons[2].herbs) == "1/1",
		ons.map(func(e: Dictionary) -> String: return str(e.herbs)))
	check("  its button reads Stop while its meals are on the fire",
		ons.size() == 3 and str(ons[1].all) == "Stop" and str(ons[2].all) == "Stop", ons.map(func(e: Dictionary) -> String: return str(e.all)))
	check("a burnt meal stays on the fire charred, \"Burnt!\" under it and its bar ash",
		dones.size() == 3 and dones[1].burnt and (dones[1].tint as Color).is_equal_approx(Cooking.BURNT_TINT)
		and str(dones[1].words) == "Burnt!" and (dones[1].fill as Color).is_equal_approx(Cooking.BURNT_FILL),
		dones[1] if dones.size() > 1 else null)
	check("  and its ingredients are gone all the same: two cooked of three, the bag empty of herbs and flour",
		bag.get_quantity_of("zz_larder_bread") == 2 and bag.get_quantity_of("zz_larder_herb") == 0
		and bag.get_quantity_of("zz_larder_flour") == 0, bag.counts)
	check("the run ends with its tally, and the button is Cook all again - off, with nothing left to cook",
		ends.size() == 2 and str(ends[1].flash) == "Cooked 1, burnt 1." and bread_all.text == "Cook all"
		and bread_all.disabled and bread_cook.disabled and bread_cook.tooltip_text == "You are missing Test Herb",
		[ends, bread_all.text, bread_cook.tooltip_text])

	# ---- a meal made from a meal ----
	bag.counts["zz_larder_salt"] = 1
	panel.call("_refresh")
	var soup_cook: Button = soup_row["cook"]
	check("with salt in the bag the soup can be cooked from the bread", not soup_cook.disabled
		and soup_salt.text == "1/1", [soup_cook.disabled, soup_salt.text])
	soup_cook.pressed.emit()
	await _larder_wait(ended.bind(3), 5.0)
	ons = events.filter(func(e: Dictionary) -> bool: return e.k == "on")
	var burn: float = float(panel.call("_burn_chance", soup, 20))
	check("  it burns on the fish's curve from its own level and mastery, and says so under it",
		ons.size() == 4 and burn > 0.0 and str(ons[3].words) == str(Cooking.risk_text("Test Soup", burn))
		and str(ons[3].words).ends_with("% burn"), [burn, ons[3].words if ons.size() > 3 else ""])
	check("  and a bread goes into it: one bread and the salt taken, a soup made",
		bag.get_quantity_of("zz_larder_bread") == 1 and bag.get_quantity_of("zz_larder_salt") == 0
		and bag.get_quantity_of("zz_larder_soup") == 1
		and str((server.asked[-1].body as Dictionary).get("recipe_id", "")) == "zz_larder_soup", bag.counts)

	# ---- Stop ----
	bag.counts = {"zz_larder_herb": 3, "zz_larder_flour": 6}
	panel.call("_refresh")
	var before_stop: int = server.recipes_asked().size()
	var stopped := [false]
	var stop_it := func(_id: String) -> void:
		if not stopped[0]:
			stopped[0] = true
			bread_all.pressed.emit()
	panel.connect(&"fish_started", stop_it)
	bread_all.pressed.emit()
	await _larder_wait(ended.bind(4), 5.0)
	panel.disconnect(&"fish_started", stop_it)
	check("Stop lets the meal on the fire finish and starts no other",
		stopped[0] and server.recipes_asked().size() == before_stop + 1, server.recipes_asked().size() - before_stop)

	fish_tab.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check("the Fish tab brings the fish back, and the window back to their size",
		grid.visible and not scroll.visible and fish_tab.button_pressed
		and panel.size == PanelWindow.content_minimum(panel), [panel.size, PanelWindow.content_minimum(panel)])

	panel.queue_free()
	hud.queue_free()
	cook.queue_free()
	server.queue_free()
	for data in made:
		ItemRegistry._items.erase(data.item_id)
	for h in huds:
		if is_instance_valid(h):
			h.add_to_group(&"hud")
	_larder_unserve(kept)
	await get_tree().process_frame


func _test_a_meal_buff_works_while_it_lasts() -> void:
	section("FOOD BUFFS - one meal at a time, on the numbers it moves, gone on time (0.74.0)")
	# adopt() writes the meal onto the active slot: the suite's own slots, put
	# back at the end, so nothing here is left on anybody else's.
	var kept_slots: Array = CharacterData.character_slots
	var kept_index: int = CharacterData.active_character_index
	CharacterData.character_slots = [null, null, null, null]
	CharacterData.active_character_index = 0
	FoodBuff.clear()
	var now: int = FoodBuff.now()
	var read := func(said: Variant) -> Dictionary: return FoodBuff.read_buff(said, now)
	check("a buff is read off the wire: its kind by name, its amount and its end, numbers as JSON sends them",
		read.call({"item_id": "zz_buff_x", "kind": "VIGOUR", "amount": 25.0, "ends_at": float(now + 600)})
			== {"item_id": "zz_buff_x", "kind": ItemData.BuffKind.VIGOUR, "amount": 25, "ends_at": now + 600},
		read.call({"item_id": "zz_buff_x", "kind": "VIGOUR", "amount": 25.0, "ends_at": float(now + 600)}))
	check("  and null, an unknown kind, NONE, nothing to add, or one already over is no buff",
		read.call(null).is_empty()
		and read.call({"item_id": "x", "kind": "HASTE", "amount": 5, "ends_at": now + 60}).is_empty()
		and read.call({"item_id": "x", "kind": "NONE", "amount": 5, "ends_at": now + 60}).is_empty()
		and read.call({"item_id": "x", "kind": "MIGHT", "amount": 0, "ends_at": now + 60}).is_empty()
		and read.call({"item_id": "x", "kind": "MIGHT", "amount": 5, "ends_at": now}).is_empty())
	check("FoodBuff is an autoload, so a meal eaten in town is still working in the Field",
		get_node_or_null("/root/FoodBuff") != null
		and FileAccess.get_file_as_string("res://project.godot").contains("FoodBuff=\"*res://src/systems/foodbuff.gd\""))
	# THE BOOKS ARE TOLD AT ONCE (0.74.0, found at the merge): presence.py
	# bounds every hit by the ticket, and a ticket is renewed once a minute, so
	# a new meal asks for one now, as an equip does.
	var kept_phase: String = Presence._phase
	var kept_clock: float = Presence._renew_clock
	Presence._phase = "open"
	Presence._renew_clock = 0.0
	FoodBuff._take(read.call({"item_id": "zz_buff_renew", "kind": "MIGHT", "amount": 5, "ends_at": now + 600}))
	var renewed_on_new: bool = is_equal_approx(Presence._renew_clock, Presence.RENEW_SECONDS)
	Presence._renew_clock = 0.0
	FoodBuff._take(read.call({"item_id": "zz_buff_renew", "kind": "MIGHT", "amount": 5, "ends_at": now + 600}))
	var renewed_on_same: bool = Presence._renew_clock > 0.0
	FoodBuff.clear()
	Presence._phase = kept_phase
	Presence._renew_clock = kept_clock
	check("a new meal renews the presence ticket at once, and the same meal read again does not",
		renewed_on_new and not renewed_on_same, [renewed_on_new, renewed_on_same])

	# THE BODY WITHOUT THE WORLD, as the amulets' test builds it.
	var body: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	body._set_stat_curve()
	body.equipped = {}
	body.level = 10
	var refresh := Callable(body, "refresh_food_stats")
	FoodBuff.changed.connect(refresh)
	var bare_hp: int = body.max_hp
	var bare_mana: int = body.max_mana
	var bare_mult: float = body.get_damage_multiplier()
	var bare_armour: int = body.armour_total()
	var bare_hit: int = body.damage_taken(200)

	FoodBuff.adopt({"item_id": "zz_buff_omelette", "kind": "MIGHT", "amount": 10, "ends_at": now + 600})
	check("a MIGHT meal multiplies every hit by its percent",
		is_equal_approx(body.get_damage_multiplier(), bare_mult * 1.10), [body.get_damage_multiplier(), bare_mult])
	check("  and moves nothing else",
		body.max_hp == bare_hp and body.max_mana == bare_mana and body.armour_total() == bare_armour)
	FoodBuff.adopt({"item_id": "zz_buff_soup", "kind": "GUARD", "amount": 40, "ends_at": now + 600})
	check("a new meal replaces the last: GUARD's armour on, MIGHT's percent gone",
		body.armour_total() == bare_armour + 40 and body.equipped_armor_value() == bare_armour
		and is_equal_approx(body.get_damage_multiplier(), bare_mult), [body.armour_total(), bare_armour])
	check("  and a hit lands lighter for it", body.damage_taken(200) < bare_hit, [body.damage_taken(200), bare_hit])
	body.hp = bare_hp
	FoodBuff.adopt({"item_id": "zz_buff_broth", "kind": "VIGOUR", "amount": 50, "ends_at": now + 600})
	check("a VIGOUR meal raises max health by its amount", body.max_hp == bare_hp + 50, [body.max_hp, bare_hp])
	check("  but not health - the ceiling moves, and the meal's own heal is what fills it", body.hp == bare_hp, body.hp)
	body.hp = body.max_hp
	body.mana = bare_mana
	FoodBuff.adopt({"item_id": "zz_buff_tart", "kind": "WISDOM", "amount": 30, "ends_at": now + 600})
	check("a WISDOM meal raises max mana by its amount, and the VIGOUR it replaced comes off",
		body.max_mana == bare_mana + 30 and body.max_hp == bare_hp, [body.max_mana, body.max_hp])
	check("  a full bar comes down to the new full - clamped, never emptied", body.hp == bare_hp, body.hp)

	# ON TIME. The end is the server's second; past it the meal adds nothing
	# at once, and the next tick says it is over.
	body.mana = body.max_mana
	body.hp = 40
	var heard: Array = []
	var listen := func() -> void: heard.append(FoodBuff.kind)
	FoodBuff.changed.connect(listen)
	FoodBuff.ends_at = now
	check("a buff past its end adds nothing, before anything has noticed",
		not FoodBuff.is_active() and FoodBuff.max_mana() == 0 and FoodBuff.seconds_left() == 0)
	FoodBuff._process(FoodBuff.TICK * 0.5)
	var waited: bool = FoodBuff.kind == ItemData.BuffKind.WISDOM and heard.is_empty()
	FoodBuff._process(FoodBuff.TICK * 0.6)
	check("  on its tick it is over, and said so once",
		waited and FoodBuff.kind == ItemData.BuffKind.NONE and heard == [ItemData.BuffKind.NONE], [waited, heard])
	check("  max mana back down and the full mana with it; a wounded character exactly as wounded",
		body.max_mana == bare_mana and body.mana == bare_mana and body.hp == 40, [body.max_mana, body.mana, body.hp])
	FoodBuff.adopt({"item_id": "zz_buff_tart", "kind": "WISDOM", "amount": 30, "ends_at": now + 600})
	FoodBuff._process(FoodBuff.TICK * 1.5)
	check("a buff still running is left running by the tick", FoodBuff.is_active() and heard.size() == 2, heard)
	FoodBuff.changed.disconnect(listen)
	FoodBuff.changed.disconnect(refresh)
	body.free()
	FoodBuff.clear()

	# ---- at login, and across Switch Character ----
	CharacterData.character_slots = [{"character": "mage"}, {"character": "warrior", "food_buff":
		{"item_id": "zz_buff_omelette", "kind": "MIGHT", "amount": 7, "ends_at": now + 300}}, null, null]
	CharacterData.active_character_index = 1
	check("picking a character takes up the meal its load says it is still full of",
		FoodBuff.adopt_for_character(1) and FoodBuff.damage_percent() == 7 and FoodBuff.item_id == "zz_buff_omelette")
	FoodBuff.adopt({"item_id": "zz_buff_broth", "kind": "VIGOUR", "amount": 45, "ends_at": now + 900})
	check("a meal eaten is written onto the character's slot",
		(CharacterData.character_slots[1] as Dictionary).get("food_buff", {}).get("item_id") == "zz_buff_broth")
	FoodBuff.clear()
	check("so Switch Character and back brings the meal eaten, not the one logged in with",
		FoodBuff.adopt_for_character(1) and FoodBuff.max_hp() == 45 and FoodBuff.damage_percent() == 0)
	check("  and a character with none has none, whoever was played before",
		not FoodBuff.adopt_for_character(0) and not FoodBuff.is_active())
	CharacterData.character_slots = [null, null, null, null]
	CharacterData.active_character_index = 0

	var storage := ServerStorage.new()
	var wire := {"item_id": "zz_buff_omelette", "kind": "MIGHT", "amount": 3, "ends_at": now + 900}
	var loaded: Dictionary = storage._slot_from_server({"class_id": "warrior", "food_buff": wire})
	check("the character the game loads keeps its food_buff on the slot, as sent",
		loaded.get("food_buff") is Dictionary and (loaded["food_buff"] as Dictionary).get("kind") == "MIGHT",
		loaded.get("food_buff"))
	check("  null when there is none, and from the listing when the character route has none",
		storage._slot_from_server({"class_id": "warrior", "food_buff": null}).get("food_buff") == null
		and ServerStorage.with_listing({"class_id": "warrior"}, {"food_buff": wire}).get("food_buff") == wire)
	var select_src: String = _code_src("res://src/ui/menus/characterselect.gd")
	var select_body: String = _func_body(select_src, "func _select_character(")
	check("Play takes it up from the slot before the world loads",
		select_body.contains("FoodBuff.adopt_for_character(idx)")
		and select_body.find("FoodBuff.adopt_for_character(idx)") < select_body.find("_enter_world(idx)"))
	check("  logout and Switch Character forget it",
		_func_body(_code_src("res://src/systems/characterdata.gd"), "func clear_current_user(").contains("FoodBuff.clear()")
		and _func_body(_code_src("res://src/ui/characterhud.gd"), "func _on_switch_character_pressed(").contains("FoodBuff.clear()"))
	check("  and every player in the world listens for it",
		_func_body(_code_src("res://src/characters/player.gd"), "func _ready(").contains("FoodBuff.changed.connect(refresh_food_stats)"))

	# ---- eating one: the consume answer's food_buff ----
	var bread := _larder_meal("zz_buff_bread", "Test Bread", Color(1, 0.8, 0.5),
		{"zz_larder_herb": 1}, 1, 1, 14, ItemData.BuffKind.VIGOUR, 10, 600)
	var potion := _larder_item("zz_buff_potion", "Test Potion", Color(1, 0.4, 0.4))
	potion.type = ItemData.Type.CONSUMABLE
	potion.restore_target = ItemData.RestoreTarget.HP
	potion.restore_amount = 20
	ItemRegistry._items[bread.item_id] = bread
	ItemRegistry._items[potion.item_id] = potion
	var server := LarderServer.new()
	add_child(server)
	if not server.start():
		check("a free local port for the suite's larder server", false)
	else:
		var kept: Array = _larder_serve(server)
		var screen: Control = (load("res://scene/ui/inventory/inventory.tscn") as PackedScene).instantiate()
		add_child(screen)
		await get_tree().process_frame
		var eater_script := GDScript.new()
		eater_script.source_code = "extends Node2D\nvar level: int = 1\nvar hp: int = 100\nvar max_hp: int = 100\n" \
			+ "var healed: int = 0\nvar healed_under_buff: bool = false\nvar said: Array = []\n" \
			+ "func heal(amount: int) -> void:\n\thealed += amount\n\thealed_under_buff = FoodBuff.is_active()\n" \
			+ "func show_notice(message: String) -> void:\n\tsaid.append(message)\n"
		eater_script.reload()
		var eater := Node2D.new()
		eater.set_script(eater_script)
		add_child(eater)
		screen.set_player(eater)
		var container: Node = screen.get("_container")
		container.load_server_array([{"item_id": "zz_buff_bread", "quantity": 3}])
		var buff_wire := {"item_id": "zz_buff_bread", "kind": "VIGOUR", "amount": 10, "ends_at": now + 600}
		server.consume_answer = {"slot": 0, "item_id": "zz_buff_bread", "consumed": 1, "remaining": 2,
			"restores": {"target": "HP", "amount": 14}, "inventory": [{"item_id": "zz_buff_bread", "quantity": 2}],
			"food_buff": buff_wire}
		await screen.use_item(container.get("slots")[0])
		check("a meal with a buff is eaten at full health - the buff is the reason to - and the buff is the server's",
			server.asked.size() == 1 and str(server.asked[0].path) == "/api/character/consume"
			and FoodBuff.is_active() and FoodBuff.max_hp() == 10 and FoodBuff.item_id == "zz_buff_bread"
			and not eater.get("said").has("Health already full"), [server.asked, eater.get("said")])
		check("  it says the buff it started, and the bag is the server's after",
			eater.get("said").has("Test Bread: +10 max health for 10 min")
			and container.get_quantity_of("zz_buff_bread") == 2, [eater.get("said"), container.get_quantity_of("zz_buff_bread")])
		FoodBuff.clear()
		eater.set("hp", 50)
		server.consume_answer["inventory"] = [{"item_id": "zz_buff_bread", "quantity": 1}]
		await screen.use_item(container.get("slots")[0])
		check("  wounded, the buff is taken before the heal, so a VIGOUR meal's heal fills the room it made",
			int(eater.get("healed")) == 14 and bool(eater.get("healed_under_buff")), [eater.get("healed"), eater.get("healed_under_buff")])
		container.load_server_array([{"item_id": "zz_buff_potion", "quantity": 2}])
		server.consume_answer = {"slot": 0, "item_id": "zz_buff_potion", "consumed": 1, "remaining": 1,
			"restores": {"target": "HP", "amount": 20}, "inventory": [{"item_id": "zz_buff_potion", "quantity": 1}]}
		await screen.use_item(container.get("slots")[0])
		check("a potion from a server that sends no food_buff leaves the meal alone",
			FoodBuff.is_active() and FoodBuff.item_id == "zz_buff_bread")
		server.consume_answer["food_buff"] = null
		await screen.use_item(container.get("slots")[0])
		check("  and when the server says nothing is in force, nothing is", not FoodBuff.is_active())
		screen.queue_free()
		eater.queue_free()
		_larder_unserve(kept)
	server.queue_free()

	# ---- the HUD ----
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	hud._resolve_bar_references()
	hud._build_food_chip()
	var chip: PanelContainer = hud.get("food_chip")
	check("with no meal in force the HUD shows no meal", chip != null and not chip.visible)
	# A STAND-IN PLAYER THAT HEARS THE SIGNAL AFTER THE HUD DOES, the order a
	# HUD built before the player connects in: the bar must still follow.
	var body_script := GDScript.new()
	body_script.source_code = "extends Node\nvar hp: int = 100\nvar max_hp: int = 100\nvar mana: int = 10\n" \
		+ "var max_mana: int = 10\nvar stamina: int = 100\nvar max_stamina: int = 100\n" \
		+ "func grow() -> void:\n\tmax_hp = 100 + FoodBuff.max_hp()\n"
	body_script.reload()
	var stand := Node.new()
	stand.set_script(body_script)
	hud.set("active_character", stand)
	var grow := Callable(stand, "grow")
	FoodBuff.changed.connect(grow)
	FoodBuff.adopt({"item_id": "zz_buff_bread", "kind": "VIGOUR", "amount": 45, "ends_at": now + 754})
	await get_tree().process_frame
	var health: Range = hud.get("healthbar")
	check("  a VIGOUR meal's new maximum reaches the health bar, whoever heard of it first",
		health != null and is_equal_approx(health.max_value, 145.0), health.max_value if health != null else -1.0)
	FoodBuff.changed.disconnect(grow)
	hud.set("active_character", null)
	stand.free()
	var clock: Label = hud.get("food_clock")
	var face: TextureRect = hud.get("food_icon")
	var left: String = FoodBuff.clock_text(FoodBuff.seconds_left())
	check("a meal in force shows on the HUD: its own picture, and the minutes and seconds left",
		chip.visible and face.texture == bread.icon and clock.text == left
		and RegEx.create_from_string("^1[12]:[0-9][0-9]$").search(clock.text) != null, [chip.visible, clock.text])
	check("  hover names it", chip.tooltip_text == "Test Bread: +45 max health, %s left" % left, chip.tooltip_text)
	var bar: Control = hud.get("staminabar")
	var style: StyleBoxFlat = chip.get_theme_stylebox("panel") as StyleBoxFlat
	check("  beside the stamina bar on its row, clear of the hotbar over the health bar, in the buff's colour",
		chip.get_parent() == bar.get_parent() and chip.offset_right <= bar.offset_left
		and is_equal_approx(chip.offset_top, bar.offset_top) and is_equal_approx(chip.anchor_top, bar.anchor_top)
		and chip.grow_horizontal == Control.GROW_DIRECTION_BEGIN
		and style != null and style.border_color.is_equal_approx(FoodBuff.colour_for(ItemData.BuffKind.VIGOUR)),
		[chip.offset_right, chip.offset_top, bar.offset_left, bar.offset_top])
	check("the clock reads minutes:seconds",
		FoodBuff.clock_text(754) == "12:34" and FoodBuff.clock_text(7) == "0:07" and FoodBuff.clock_text(-3) == "0:00")
	FoodBuff.clear()
	check("and when the meal is over the chip goes", not chip.visible)
	hud.free()
	ItemRegistry._items.erase(bread.item_id)
	ItemRegistry._items.erase(potion.item_id)
	FoodBuff.clear()
	CharacterData.character_slots = kept_slots
	CharacterData.active_character_index = kept_index
	await get_tree().process_frame


func _test_the_catch_names_its_bait() -> void:
	section("BAIT - any bait casts, and the catch says which one it took (0.74.0)")
	var FishingSpot: Script = load("res://src/world/fishingspot.gd") as Script
	check("the catch notice names the bait the server says it took",
		FishingSpot.catch_text("Raw Mudfish", 1, "Lugworm") == "Caught Raw Mudfish on a Lugworm"
		and FishingSpot.catch_text("Raw Carp", 2, "Glowgrub") == "Caught Raw Carp x2 on a Glowgrub"
		and FishingSpot.catch_text("Raw Carp", 1, "Eel Bait") == "Caught Raw Carp on an Eel Bait",
		FishingSpot.catch_text("Raw Mudfish", 1, "Lugworm"))
	check("  and with none named it is the notice it always was",
		FishingSpot.catch_text("Raw Mudfish", 1) == "Caught Raw Mudfish"
		and FishingSpot.catch_text("Raw Mudfish", 3, "") == "Caught Raw Mudfish x3")

	var grub := _larder_item("zz_bait_grub", "Test Glowgrub", Color(0.7, 1, 0.4))
	grub.bait_rolls = 3
	var perch := _larder_item("zz_bait_perch", "Raw Test Perch", Color(0.6, 0.8, 1))
	ItemRegistry._items[grub.item_id] = grub
	ItemRegistry._items[perch.item_id] = perch
	var server := LarderServer.new()
	add_child(server)
	if not server.start():
		check("a free local port for the suite's larder server", false)
		server.queue_free()
		ItemRegistry._items.erase(grub.item_id)
		ItemRegistry._items.erase(perch.item_id)
		return
	var kept: Array = _larder_serve(server)
	var huds: Array = get_tree().get_nodes_in_group(&"hud")
	for h in huds:
		h.remove_from_group(&"hud")
	var hud := CookingHud.new()
	hud.add_to_group(&"hud")
	add_child(hud)
	var screen_node := Node.new()
	hud.add_child(screen_node)
	hud.inventory_screen = screen_node
	var bag := CookingBag.new()
	bag.name = "inventorycontainer"
	screen_node.add_child(bag)
	bag.owner = screen_node
	bag.unique_name_in_owner = true
	bag.counts = {"zz_bait_grub": 2}
	server.bag = bag

	var listener_script := GDScript.new()
	listener_script.source_code = "extends Node\nvar said: Array = []\nfunc show_notice(message: String) -> void:\n\tsaid.append(message)\n"
	listener_script.reload()
	var angler := Node.new()
	angler.set_script(listener_script)
	add_child(angler)
	var spot: Node = (load("res://scene/interactables/fishingspot.tscn") as PackedScene).instantiate()
	add_child(spot)
	spot.set("player_in_range", angler)
	check("a bag with a better bait and no worm has bait - the cast is not refused before the server is asked",
		int(spot.call("_bait_count")) == 2, spot.call("_bait_count"))
	server.catch_answer = {"item_id": "zz_bait_perch", "quantity": 1, "levelled_up": false, "bait": "zz_bait_grub"}
	await spot._land_catch()
	check("a catch the server says took a glowgrub says so: \"Caught Raw Test Perch on a Test Glowgrub\"",
		angler.get("said") == ["Caught Raw Test Perch on a Test Glowgrub"], angler.get("said"))
	server.catch_answer = {"item_id": "zz_bait_perch", "quantity": 1, "levelled_up": false}
	await spot._land_catch()
	check("  and one whose answer names no bait says only the fish, not the last one's bait",
		(angler.get("said") as Array).size() == 2 and str(angler.get("said")[1]) == "Caught Raw Test Perch",
		angler.get("said"))

	spot.queue_free()
	angler.queue_free()
	hud.queue_free()
	server.queue_free()
	for h in huds:
		if is_instance_valid(h):
			h.add_to_group(&"hud")
	ItemRegistry._items.erase(grub.item_id)
	ItemRegistry._items.erase(perch.item_id)
	_larder_unserve(kept)
	await get_tree().process_frame


func _test_a_tooltip_says_what_food_is_for() -> void:
	section("TOOLTIPS - a meal's heal, buff and makings; what a material is for; how a bait works (0.74.0)")
	var herb := _larder_item("zz_tip_herb", "Test Herb", Color(0.6, 1, 0.6))
	var salt := _larder_item("zz_tip_salt", "Test Salt", Color(0.9, 0.9, 1))
	var stew := _larder_meal("zz_tip_stew", "Test Stew", Color(1, 0.7, 0.5),
		{"zz_tip_herb": 2, "zz_tip_salt": 1}, 12, 32, 30, ItemData.BuffKind.VIGOUR, 25, 900)
	stew.required_level = 5
	var pie := _larder_meal("zz_tip_pie", "Test Pie", Color(1, 0.9, 0.6),
		{"zz_tip_stew": 1}, 20, 40, 60, ItemData.BuffKind.NONE, 0, 0)
	var made: Array[ItemData] = [herb, salt, stew, pie]
	for data in made:
		ItemRegistry._items[data.item_id] = data
	var lines: String = ItemTooltip._requirement_lines(stew)
	var said: PackedStringArray = lines.split("\n")
	check("a meal's tooltip says what it heals", said.has("Restores 30 Health"), lines)
	check("  the buff it gives, in buff_text()'s words", said.has("+25 max health for 15 min"), lines)
	check("  and what it is made from, and at what cooking level",
		said.has("Made from Test Herb x2 and Test Salt - cooking level 12"), lines)
	check("  with who may eat it still last", said[said.size() - 1] == "Needs Lv 5", lines)
	check("a meal that goes into another says it is a cooking ingredient as well",
		said.has(ItemTooltip.COOKING_INGREDIENT), lines)
	check("a meal with no buff says none, and lists its one ingredient plainly",
		not ItemTooltip._requirement_lines(pie).contains(" for ")
		and ItemTooltip._requirement_lines(pie).contains("Made from Test Stew - cooking level 20"),
		ItemTooltip._requirement_lines(pie))
	check("an ingredient says it is one, and nothing else",
		ItemTooltip._requirement_lines(salt) == "Cooking ingredient", ItemTooltip._requirement_lines(salt))
	var ore := _larder_item("ironore", "Test Ore", Color(0.7, 0.7, 0.7))
	check("a material the smith takes says so",
		ItemTooltip._requirement_lines(ore) == "Used by the smith", ItemTooltip._requirement_lines(ore))
	var smith_ids: Array = []
	for row in GameConstants.TEMPER_COSTS + GameConstants.CERTIFICATIONS:
		for need in (row as Dictionary).get("materials", []):
			if not smith_ids.has(str(need["item_id"])):
				smith_ids.append(str(need["item_id"]))
	check("  read off the smith's own costs: every material a temper or certificate takes, nothing else",
		smith_ids.size() >= 10 and smith_ids.all(func(id: String) -> bool: return ItemTooltip.is_smith_material(id))
		and not ItemTooltip.is_smith_material("zz_tip_salt") and not ItemTooltip.is_smith_material(""), smith_ids)
	var grub := _larder_item("zz_tip_grub", "Test Grub", Color(0.7, 1, 0.4))
	grub.bait_rolls = 3
	var worm := _larder_item("zz_tip_worm", "Test Worm", Color(1, 0.6, 0.6))
	worm.bait_rolls = 1
	check("a bait says how many rolls a catch gets",
		ItemTooltip._requirement_lines(grub) == "Bait - each catch is rolled 3 times, the best fish kept"
		and ItemTooltip._requirement_lines(worm) == "Bait - each catch is rolled once",
		[ItemTooltip._requirement_lines(grub), ItemTooltip._requirement_lines(worm)])
	var potion := ItemData.new()
	potion.item_id = "zz_tip_potion"
	potion.restore_amount = 260
	potion.restore_target = ItemData.RestoreTarget.HP
	check("and a potion, which is none of these, says what it always said",
		ItemTooltip._requirement_lines(potion) == "Restores 260 Health", ItemTooltip._requirement_lines(potion))

	var tip: Control = (load("res://scene/ui/inventory/itemtooltip.tscn") as PackedScene).instantiate()
	add_child(tip)
	await get_tree().process_frame
	tip.show_for_stack(ItemStack.new(stew, 2), null)
	var shown: String = (tip.find_child("tooltipdescription", true, false) as Label).text
	check("the tooltip itself shows all of it over the bag", shown.contains("+25 max health for 15 min")
		and shown.contains("Made from Test Herb x2 and Test Salt") and shown.contains("Restores 30 Health"), shown)
	tip.queue_free()
	for data in made:
		ItemRegistry._items.erase(data.item_id)

	# THE REAL LARDER, where the pack is here to load it.
	var real: Dictionary = {}
	for id in ["salt", "wildherb", "ironore", "lugworm", "fishingworm", "bonebroth"]:
		real[id] = ItemTooltip._requirement_lines(ItemRegistry.get_item(id)) if ItemRegistry.has_item(id) else "missing"
	check_needs_pack("the real ones: salt and wild herb cook, iron ore is the smith's, a lugworm rolls twice and the worm once",
		str(real["salt"]).contains("Cooking ingredient") and str(real["wildherb"]).contains("Cooking ingredient")
		and str(real["ironore"]).contains("Used by the smith")
		and str(real["lugworm"]).contains("rolled 2 times") and str(real["fishingworm"]).contains("rolled once"), real)
	check_needs_pack("  and Bone Broth heals, buffs, is made from bone, onion and salt, and goes into a soup",
		str(real["bonebroth"]).contains("Restores 45 Health") and str(real["bonebroth"]).contains("+45 max health for 15 min")
		and str(real["bonebroth"]).contains("Made from Old Bone x2") and str(real["bonebroth"]).contains("Cooking ingredient"),
		real["bonebroth"])
	await get_tree().process_frame


func _test_the_fire_shows_the_fish_it_cooks() -> void:
	section("COOKING - the fire shows the fish it is cooking, and how each came out (0.25.2)")
	# The owner: "cooking meter was not matching up and burned fish vanished to
	# quickly". Recorded before the fix: a burnt fish stayed charred on the fire
	# through the NEXT fish's bar; a click on another fish showed that fish while
	# the first kind went on cooking; the bar flipped to the burn chance between
	# fish; and the last burnt fish was gone 0.35 s after it burnt.
	# STAND-IN FISH, so this runs in a clone without the private art pack (the
	# real fish's icons are in it, and without them they are not loaded). A
	# mudfish-like one that never burns at level 20, and a carp-like one that
	# does 5% of the time, each cooking into a fish with a picture of its own.
	var made: Array[ItemData] = []
	for spec in [["zz_cook_a", "Raw Test Mudfish", "zz_cook_a_done", 1, 1, Color(1, 0.8, 0.8)],
			["zz_cook_b", "Raw Test Carp", "zz_cook_b_done", 5, 22, Color(0.8, 1, 0.8)],
			["zz_cook_a_done", "Cooked Test Mudfish", "", 1, 1, Color(1, 1, 0.7)],
			["zz_cook_b_done", "Cooked Test Carp", "", 1, 1, Color(0.7, 1, 1)]]:
		var fish := ItemData.new()
		fish.item_id = spec[0]
		fish.display_name = spec[1]
		fish.cooks_into = spec[2]
		fish.cook_level = spec[3]
		fish.cook_mastery_level = spec[4]
		fish.icon_tint = spec[5]
		var picture := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		picture.fill(spec[5])
		fish.icon = ImageTexture.create_from_image(picture)
		ItemRegistry._items[fish.item_id] = fish
		made.append(fish)

	var server := CookingServer.new()
	add_child(server)
	if not server.start():
		check("a free local port for the suite's cooking server", false)
		server.queue_free()
		for fish in made:
			ItemRegistry._items.erase(fish.item_id)
		return
	var kept_url: String = ApiForTests.BASE_URL
	var kept_token: String = Api.token
	var kept_online: bool = Api.server_online
	var kept_known: bool = Api.reachability_known
	ApiForTests.BASE_URL = "http://127.0.0.1:%d" % server.port
	Api.token = "suite"
	var huds: Array = get_tree().get_nodes_in_group(&"hud")
	for h in huds:
		h.remove_from_group(&"hud")

	var hud := CookingHud.new()
	hud.add_to_group(&"hud")
	add_child(hud)
	var screen_node := Node.new()
	hud.add_child(screen_node)
	hud.inventory_screen = screen_node
	var bag := CookingBag.new()
	bag.name = "inventorycontainer"
	screen_node.add_child(bag)
	bag.owner = screen_node
	bag.unique_name_in_owner = true
	bag.counts = {"zz_cook_a": 2, "zz_cook_b": 3}
	server.bag = bag
	server.burns = [false, true, false, true]
	var cook := CookingCook.new()
	add_child(cook)

	var panel: Control = (load("res://scene/ui/cooking/cookingscreen.tscn") as PackedScene).instantiate()
	add_child(panel)
	panel.set("cook_duration", 0.15)
	panel.set("cook_interval", 0.1)
	panel.set("burnt_hold", 0.5)
	panel.open_for_firepit(null, cook)
	var icon: TextureRect = panel.find_child("cookicon", true, false) as TextureRect
	var bar: ProgressBar = panel.find_child("riskbar", true, false) as ProgressBar
	var words: Label = panel.find_child("catchlabel", true, false) as Label
	var Cooking: Script = panel.get_script() as Script
	var events: Array = []
	panel.connect(&"fish_started", func(id: String) -> void:
		events.append({"k": "on", "id": id, "at": Time.get_ticks_msec(), "tint": icon.modulate, "words": words.text}))
	panel.connect(&"fish_done", func(id: String, burnt: bool) -> void:
		var fill: StyleBoxFlat = bar.get_theme_stylebox("fill") as StyleBoxFlat
		events.append({"k": "done", "id": id, "burnt": burnt, "at": Time.get_ticks_msec(), "tint": icon.modulate,
			"icon": icon.texture, "words": words.text, "bar": bar.value, "fill": fill.bg_color if fill != null else Color.BLACK}))
	panel.connect(&"run_ended", func() -> void:
		events.append({"k": "end", "at": Time.get_ticks_msec(), "shown": icon.visible, "tint": icon.modulate}))

	panel.call("_start_run", "zz_cook_a")
	var waited := 0.0
	while events.filter(func(e: Dictionary) -> bool: return e.k == "done").is_empty() and waited < 5.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	# A click on the carp while the first mudfish is showing how it came out.
	panel.call("_start_run", "zz_cook_b")
	waited = 0.0
	while events.filter(func(e: Dictionary) -> bool: return e.k == "end").is_empty() and waited < 10.0:
		await get_tree().process_frame
		waited += get_process_delta_time()

	check("a click on another fish mid-run cooks that fish next, not more of the first",
		server.asked == ["zz_cook_a", "zz_cook_b", "zz_cook_b", "zz_cook_b"], server.asked)
	var ons: Array = events.filter(func(e: Dictionary) -> bool: return e.k == "on")
	var dones: Array = events.filter(func(e: Dictionary) -> bool: return e.k == "done")
	var ends: Array = events.filter(func(e: Dictionary) -> bool: return e.k == "end")
	var mud: ItemData = made[0]
	var carp: ItemData = made[1]
	var cooked_mud: ItemData = made[2]
	check("  and the fire shows each fish as its bar starts: the mudfish, then the carp",
		ons.size() == 4 and ons.map(func(e: Dictionary) -> String: return e.id) \
			== ["zz_cook_a", "zz_cook_b", "zz_cook_b", "zz_cook_b"], ons.size())
	check("a fish going on after a burnt one is shown raw, not still charred from the last",
		ons.size() == 4 and (ons[2].tint as Color).is_equal_approx(carp.icon_tint), ons[2].tint if ons.size() == 4 else null)
	check("a cooked fish comes off as the cooked fish, its bar full and gold",
		dones.size() == 4 and not dones[0].burnt and dones[0].icon == cooked_mud.icon
		and dones[0].words == cooked_mud.display_name and is_equal_approx(dones[0].bar, 100.0)
		and (dones[0].fill as Color).is_equal_approx(Cooking.COOK_FILL), dones[0] if dones.size() > 0 else null)
	check("  a burnt one stays on, charred, \"Burnt!\" under it and its bar ash",
		dones.size() == 4 and dones[1].burnt and (dones[1].tint as Color).is_equal_approx(Cooking.BURNT_TINT)
		and dones[1].words == "Burnt!" and (dones[1].fill as Color).is_equal_approx(Cooking.BURNT_FILL),
		dones[1] if dones.size() > 1 else null)
	var held: int = int(ons[2].at) - int(dones[1].at) if ons.size() == 4 and dones.size() == 4 else -1
	var brief: int = int(ons[1].at) - int(dones[0].at) if ons.size() == 4 and dones.size() == 4 else -1
	check("  for burnt_hold before the next fish goes on, where a cooked one moves on after cook_interval",
		held >= 450 and brief >= 80 and brief < 400, [held, brief])
	check("the burn chance is words under the fish (\"5% burn\"); the bar is the cook alone",
		ons.size() == 4 and str(ons[1].words) == "Raw Test Carp  ·  5% burn" and str(ons[0].words) == mud.display_name
		and Cooking.risk_text("Raw Mudfish", 0.0) == "Raw Mudfish" and Cooking.risk_text("X", 0.001) == "X  ·  1% burn",
		[ons[1].words if ons.size() > 1 else "", ons[0].words if ons.size() > 0 else ""])
	var last_held: int = int(ends[0].at) - int(dones[3].at) if ends.size() == 1 and dones.size() == 4 else -1
	check("the last fish, burnt, is still on the fire when the run ends - held, not cleared at once",
		ends.size() == 1 and last_held >= 450 and bool(ends[0].shown)
		and (ends[0].tint as Color).is_equal_approx(Cooking.BURNT_TINT), [last_held, ends])
	await get_tree().create_timer(0.6).timeout
	check("  then it fades off and the fire is empty", not icon.visible and words.text == "" and not bar.visible,
		[icon.visible, words.text, bar.visible])

	panel.queue_free()
	hud.queue_free()
	cook.queue_free()
	server.queue_free()
	for fish in made:
		ItemRegistry._items.erase(fish.item_id)
	for h in huds:
		if is_instance_valid(h):
			h.add_to_group(&"hud")
	ApiForTests.BASE_URL = kept_url
	Api.token = kept_token
	Api.server_online = kept_online
	Api.reachability_known = kept_known
	await get_tree().process_frame


func _test_the_powers_panel_closes() -> void:
	section("POWERS - the owner's ranks window has a × like every other")

	# Asked for on day 1: the only way out of it was the button that opened it.
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	var kept_owner: bool = Api.is_owner
	Api.is_owner = true
	hud._toggle_powers_panel()
	var panel: Control = hud.get_node_or_null("powerspanel")
	var x: Button = panel.find_child("powersclosebutton", true, false) as Button if panel != null else null
	check("the Powers window opens with a × in its header",
		panel != null and panel.visible and x != null and x.text == "×" and x.focus_mode == Control.FOCUS_NONE,
		[panel != null, x.text if x != null else "no button"])
	if x != null:
		x.pressed.emit()
	check("  pressing it closes the window", panel != null and not panel.visible)
	hud._toggle_powers_panel()
	check("  and the Powers button opens it again", panel != null and panel.visible)
	check("  its list is still where the server's answer is written",
		hud.get_node_or_null(hud.POWERS_ROWS) is VBoxContainer)
	Api.is_owner = kept_owner
	hud.free()


func _test_the_powers_read_in_words() -> void:
	section("POWERS - each one is a sentence, with its route on the tooltip")

	# 5 Oct, the owner: "update powers tab". Every line was "POST /api/staff/ban"
	# while the server sent "Ban an account" beside it, unread. Rendered from a
	# server answer written here, so no server is needed.
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	var rows := VBoxContainer.new()
	hud.add_child(rows)
	hud._render_powers(rows, {
		"ladder": [
			{"rank": "player", "grantable": true, "routes": [], "notes": []},
			{"rank": "mod", "grantable": true, "routes": [
				{"method": "POST", "path": "/api/staff/ban", "what": "Ban an account"},
				{"method": "GET", "path": "/api/staff/users", "what": "List accounts (staff only)"},
			], "notes": ["Mute for at most a day - longer is refused."]},
			{"rank": "dev", "grantable": true, "routes": [
				{"method": "GET", "path": "/api/economy/supply", "what": "---"},
			], "notes": []},
			{"rank": "owner", "grantable": false, "routes": [
				{"method": "POST", "path": "/api/staff/level",
					"what": "Set your own character's level, for testing (owner only)"},
				# On the owner's list since 0.6.1, as the server sends it now.
				{"method": "POST", "path": "/api/staff/grant", "what": "Give yourself an item (owner only)"},
			], "notes": []},
		],
		"you_are": "owner",
		"you_may_grant": ["player", "mod", "dev"],
	})
	var by_text: Dictionary = {}
	for child in rows.get_children():
		if child is Label:
			by_text[(child as Label).text.strip_edges()] = child
	var texts: Array = by_text.keys()

	var ban: Label = by_text.get("Ban an account")
	check("a power reads as what it does", ban != null, texts)
	check("  and no line is a bare route any more, where the server said what it was",
		not texts.any(func(t: String) -> bool: return t.contains("/api/staff/")), texts)
	check("  the route is on its tooltip, for finding it in app.py",
		ban != null and ban.tooltip_text == "POST /api/staff/ban", ban.tooltip_text if ban != null else "")
	check("  and the line takes the mouse, or the tooltip never shows",
		ban != null and ban.mouse_filter == Control.MOUSE_FILTER_PASS)
	check("\"(staff only)\" and \"(owner only)\" go - the heading above already says it",
		by_text.has("List accounts") and by_text.has("Give yourself an item")
		and by_text.has("Set your own character's level, for testing"), texts)
	check("a power the server has no sentence for shows its route instead of \"---\"",
		by_text.has("GET  /api/economy/supply") and not by_text.has("---"), texts)
	check("the notes are still under their rank", by_text.has("- Mute for at most a day - longer is refused."), texts)
	check("a rank with nothing extra says so", by_text.has("nothing beyond playing the game"), texts)
	check("the owner's rank says it cannot be granted", by_text.has("OWNER   (cannot be granted)"), texts)
	check("and the last line says who you are and what you may grant",
		by_text.has("You are owner. You may grant: player, mod, dev"), texts)

	const HUD := preload("res://src/ui/characterhud.gd")
	check("power_words() with no sentence at all is the route",
		HUD.power_words({"method": "PUT", "path": "/api/staff/role"}) == "PUT  /api/staff/role")
	hud.free()
	print("  powers: each one a sentence, its route on the tooltip")


func _test_the_staff_windows_share_one_look() -> void:
	section("STAFF WINDOWS - Owner, Staff and Powers wear one navy and gold theme")

	# Asked for on day 1: the three staff windows had three looks (navy, brown,
	# navy) and none had the inventory's gold boxes. They now share
	# staff_ui_theme.tres, so a colour changed there changes all three.
	const STAFF_THEME_PATH := "res://assets/themes/staff_ui_theme.tres"
	var theme: Theme = load(STAFF_THEME_PATH) as Theme
	check("the staff theme loads", theme != null)
	if theme == null:
		return
	var window: StyleBoxFlat = theme.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	var tab_on: StyleBoxFlat = theme.get_stylebox("tab_selected", "TabContainer") as StyleBoxFlat
	var tab_box: StyleBoxFlat = theme.get_stylebox("panel", "TabContainer") as StyleBoxFlat
	var is_navy := func(c: Color) -> bool: return c.b > c.r and c.b > c.g and c.v < 0.2
	var is_gold := func(c: Color) -> bool: return c.r > c.g and c.g > c.b and c.r > 0.45
	check("  its windows are navy with a gold frame",
		window != null and is_navy.call(window.bg_color) and is_gold.call(window.border_color)
		and window.border_width_left >= 2,
		str(window.bg_color) + " " + str(window.border_color) if window != null else "no window style")
	check("  its tabs and the page under them are boxed in gold",
		tab_on != null and tab_box != null and is_gold.call(tab_on.border_color)
		and is_gold.call(tab_box.border_color) and tab_box.border_width_top >= 1)
	check("  it has the header box and the inner box every window uses",
		theme.get_type_variation_base(&"PanelHeader") == &"PanelContainer"
		and theme.get_type_variation_base(&"PanelSub") == &"PanelContainer")
	var staff_menu: StyleBoxFlat = theme.get_stylebox("panel", "PopupMenu") as StyleBoxFlat
	check("  and its dropdown lists and menus are navy in a gold frame, not Godot's grey",
		theme.has_stylebox("panel", "PopupMenu") and staff_menu != null
		and is_navy.call(staff_menu.bg_color) and is_gold.call(staff_menu.border_color))

	# NO WINDOW MAY QUIETLY KEEP ITS OLD LOOK. A per-node style override beats
	# the theme, so one left behind keeps an old colour no matter what the theme
	# says. Only the red and green action buttons keep their own colours.
	const KEEP_OWN_COLOURS := ["banbutton", "unbanbutton", "maintenancebutton"]
	var leftovers := func(root: Node) -> Array:
		var found: Array = []
		var nodes: Array = [root]
		nodes.append_array(root.find_children("*", "", true, false))
		for node in nodes:
			if not (node is Button or node is LineEdit or node is TabContainer or node is PanelContainer):
				continue
			if str(node.name) in KEEP_OWN_COLOURS:
				continue
			for style in ["normal", "hover", "pressed", "focus", "panel",
					"tab_selected", "tab_unselected", "tab_hovered"]:
				if (node as Control).has_theme_stylebox_override(style):
					found.append("%s/%s" % [node.name, style])
		return found

	var owner_panel: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate()
	var owner_left: Array = leftovers.call(owner_panel)
	check("the Owner window wears the staff theme",
		owner_panel.theme != null and owner_panel.theme.resource_path == STAFF_THEME_PATH,
		owner_panel.theme.resource_path if owner_panel.theme != null else "no theme")
	check("  with no button, field, tab or box keeping its own old style", owner_left.is_empty(), owner_left)
	var owner_header: Control = owner_panel.find_child("headerpanel", true, false)
	check("  and its title sits in the gold header box",
		owner_header != null and owner_header.theme_type_variation == &"PanelHeader")
	owner_panel.free()

	var staff_panel: Control = (load("res://scene/ui/staff/staffpanel.tscn") as PackedScene).instantiate()
	var staff_main: Control = staff_panel.get_node_or_null("mainpanel")
	var staff_left: Array = leftovers.call(staff_panel)
	check("the Staff window wears the staff theme, not the brown one",
		staff_main != null and staff_main.theme != null and staff_main.theme.resource_path == STAFF_THEME_PATH,
		staff_main.theme.resource_path if staff_main != null and staff_main.theme != null else "no theme")
	check("  with no button, field, tab or box keeping its own old style", staff_left.is_empty(), staff_left)
	staff_panel.free()

	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	var kept_owner: bool = Api.is_owner
	Api.is_owner = true
	hud._toggle_powers_panel()
	var powers: Control = hud.get_node_or_null("powerspanel")
	var powers_header: Control = powers.find_child("header", true, false) if powers != null else null
	check("the Powers window wears the staff theme",
		powers != null and powers.theme != null and powers.theme.resource_path == STAFF_THEME_PATH)
	check("  with its title in the gold header box and no style of its own",
		powers_header != null and powers_header.theme_type_variation == &"PanelHeader"
		and powers != null and leftovers.call(powers).is_empty(),
		leftovers.call(powers) if powers != null else "no window")
	Api.is_owner = kept_owner
	hud.free()


func _test_players_right_click_menu() -> void:
	section("PLAYERS - right-click a name to whisper, add as a friend or trade")

	# Asked for on day 1. Out of the tree, like the chat menu's test: _ready()
	# never runs, so nothing polls a server, and with no token nothing is sent.
	var was := [Api.username, Api.token]
	Api.username = "me_myself"
	Api.token = ""
	var panel: Control = (load("res://scene/ui/players/playerspanel.tscn") as PackedScene).instantiate()
	var stranger: Control = panel._row({"username": "rowdy", "name": "mage", "level": 3,
		"area": "field", "role": "player", "guild_tag": "ABC", "guild": "Abc"})
	var mine: Control = panel._row({"username": "Me_Myself", "name": "warrior", "level": 9,
		"area": "field", "role": "player", "guild_tag": ""})
	check("somebody else's row can be right-clicked, and says so",
		stranger.tooltip_text == panel.ROW_HINT and not stranger.gui_input.get_connections().is_empty(),
		stranger.tooltip_text)
	check("  your own row has no menu",
		mine.tooltip_text == "" and mine.gui_input.get_connections().is_empty())
	var stops: Array = []
	for node in stranger.find_children("*", "Control", true, false):
		if (node as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
			stops.append(str(node.name))
	check("  nothing on the row, the guild tag included, keeps the click from the row",
		stops.is_empty(), stops)

	var heard: Array = []
	panel.whisper_asked.connect(func(who: String) -> void: heard.append("whisper " + who))
	panel.friend_asked.connect(func(who: String) -> void: heard.append("friend " + who))
	panel.trade_asked.connect(func(who: String) -> void: heard.append("trade " + who))
	panel.party_asked.connect(func(who: String) -> void: heard.append("party " + who))
	panel.guild_asked.connect(func(who: String) -> void: heard.append("guild " + who))
	panel.report_asked.connect(func(who: String, why: String) -> void: heard.append("report %s %s" % [who, why]))

	var left := InputEventMouseButton.new()
	left.button_index = MOUSE_BUTTON_LEFT
	left.pressed = true
	stranger.gui_input.emit(left)
	check("a left click opens nothing", panel.row_menu == null)
	# A TAP DOES (0.56.0): on a touch screen there is no right button.
	TouchControls.set_active(true)
	stranger.gui_input.emit(left)
	TouchControls.set_active(false)
	var tapped_open: bool = panel.row_menu != null
	check("  but on a touch screen a tap does - a phone has no right button", tapped_open)
	if panel.row_menu != null:
		panel.row_menu.hide()
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	stranger.gui_input.emit(right)
	var menu: PopupMenu = panel.row_menu
	var items: Array = []
	var title: String = ""
	if menu != null:
		for i in menu.item_count:
			if menu.is_item_separator(i):
				if title == "":
					title = menu.get_item_text(i)
			else:
				items.append(menu.get_item_text(i))
	check("a right click opens their menu - what every name offers (playermenu.gd, 0.43.0)",
		menu != null and title == "rowdy" and items == ["Whisper", "Add friend", "Trade", "Invite to party",
		"Invite to guild", "Spam", "Harassment", "Hate speech", "Cheating or scams", "Something else"], [title, items])
	if menu != null:
		for id in [panel.MENU_WHISPER, panel.MENU_FRIEND, panel.MENU_TRADE, panel.MENU_PARTY, panel.MENU_GUILD,
				PlayerMenu.REPORT + 3]:
			menu.id_pressed.emit(id)
	check("  and each asks for that, for them - the report with its reason",
		heard == ["whisper rowdy", "friend rowdy", "trade rowdy", "party rowdy", "guild rowdy",
		"report rowdy cheating"], heard)
	panel._menu_who = ""
	panel.open_row_menu("ME_MYSELF")
	check("  there is no menu for yourself, however it is typed", panel._menu_who == "")
	# THE MENU WEARS THE GAME'S LOOK. A theme with no PopupMenu in it leaves
	# Godot's grey box, which is what the first version of this menu showed.
	var game_theme: Theme = load("res://assets/themes/rpg_ui_theme.tres") as Theme
	var menu_box: StyleBoxFlat = game_theme.get_stylebox("panel", "PopupMenu") as StyleBoxFlat \
		if game_theme != null and game_theme.has_stylebox("panel", "PopupMenu") else null
	check("  and the menu is a dark box in a gold frame, like the windows",
		menu_box != null and menu_box.bg_color.v < 0.15 and menu_box.border_color.r > menu_box.border_color.b
		and menu_box.border_width_top >= 1 and game_theme.has_stylebox("hover", "PopupMenu"))
	stranger.free()
	mine.free()
	panel.free()

	# THE HUD SENDS EACH TO THE WINDOW THAT ALREADY DOES IT.
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	var built: Control = hud._build_players_panel()
	check("the HUD connects all three to its own windows",
		built.whisper_asked.is_connected(hud.whisper_player)
		and built.friend_asked.is_connected(hud.ask_to_be_friends)
		and built.trade_asked.is_connected(hud.trade_with))
	var hud_src: String = _code_src("res://src/ui/characterhud.gd")
	check("  Whisper opens chat on the Whisper tab, Add friend asks from the Friends window,"
		+ " Trade offers from the Trade window",
		_func_body(hud_src, "func whisper_player(").contains("chat_panel.start_whisper(who)")
		and _func_body(hud_src, "func ask_to_be_friends(").contains("friends_panel.ask_from_elsewhere(who)")
		and _func_body(hud_src, "func trade_with(").contains("trade_panel.offer_to(active_character, who)"))
	check("  and opening the list is what builds and wires it",
		_func_body(hud_src, "func toggle_players(").contains("_build_players_panel()"))
	built.free()
	hud.free()

	# WHISPER: the same path as the chat log's name menu.
	var chat: Control = (load("res://scene/ui/chat/chatpanel.tscn") as PackedScene).instantiate()
	chat.whisper_to = chat.get_node_or_null("%chatto")
	for channel in chat.CHANNELS:
		chat._feeds[channel] = {"cursor": 0, "lines": [], "unread": false}
	chat.visible = true
	chat.start_whisper("  rowdy ")
	check("start_whisper opens the Whisper tab aimed at them",
		chat._channel == "private" and chat._whisper_with == "rowdy"
		and chat.whisper_to != null and chat.whisper_to.text == "rowdy",
		[chat._channel, chat._whisper_with])
	chat._menu_line = {"kind": "chat", "by": "other", "id": 5}
	chat._on_line_menu_id(chat.MENU_WHISPER)
	check("  and the chat log's own Whisper goes the same way", chat._whisper_with == "other")
	chat.free()

	# ADD FRIEND: the same checks as the box at the top of the Friends window.
	var friends: Control = (load("res://scene/ui/friends/friendspanel.tscn") as PackedScene).instantiate()
	friends.notice = friends.get_node_or_null("%friendsnotice")
	friends._name_check.compile(friends.NAME_PATTERN)
	var sent_self: bool = await friends.ask("Me_Myself")
	check("asking yourself is refused before anything is sent",
		not sent_self and friends.notice != null and friends.notice.text == "You cannot add yourself.",
		friends.notice.text if friends.notice != null else "no notice")
	var sent_bad: bool = await friends.ask("no spaces allowed")
	check("  and so is a name that cannot exist", not sent_bad)
	check("  the box at the top asks through the same function",
		_func_body(_code_src("res://src/ui/friends/friendspanel.gd"), "func _on_add_pressed(").contains("ask(add_entry.text)"))
	friends.free()

	# TRADE: the same request as a typed name - no slot, the server finds it.
	check("Trade from the list sends the typed-name offer",
		_func_body(_code_src("res://src/ui/trade/tradepanel.gd"), "func offer_to(").contains("_send_offer(who, -1)"))

	Api.username = was[0]
	Api.token = was[1]


func _test_the_stats_window_reads_cleanly() -> void:
	section("STATS WINDOW - two columns, short numbers, no lines between boxes")

	# Asked for on day 1: "1,007,892" in a small window, a separator line
	# between every box, and the level and XP floating in a gap.
	var short := func(n: int) -> String: return GameConstants.short_number(n)
	check("a big number is short: 1,007,892 is 1M, and never rounded up",
		short.call(1_007_892) == "1M" and short.call(1_999_999) == "1.9M"
		and short.call(12_345) == "12K" and short.call(998_501) == "998K"
		and short.call(45_600_000) == "45M" and short.call(1_500_000_000) == "1.5B",
		[short.call(1_007_892), short.call(1_999_999), short.call(12_345), short.call(998_501)])
	check("  a small one is written out, and a negative keeps its sign",
		short.call(9_391) == "9,391" and short.call(0) == "0" and short.call(-25_000) == "-25K",
		[short.call(9_391), short.call(-25_000)])

	var scene_text: String = FileAccess.get_file_as_string("res://scene/ui/statsscreen.tscn")
	var stats: Node = (load("res://scene/ui/statsscreen.tscn") as PackedScene).instantiate()
	var columns: Node = stats.find_child("statscontainer", true, false)
	check("two columns: level, experience and the pools beside the skills",
		columns is HBoxContainer and columns.find_child("leftcolumn", false, false) != null
		and columns.find_child("rightcolumn", false, false) != null
		and columns.find_child("leftcolumn", false, false).find_child("hpbar", true, false) != null
		and columns.find_child("rightcolumn", false, false).find_child("attackbar", true, false) != null)
	check("  with no separator lines - the boxes already separate",
		not scene_text.contains("HSeparator") and not scene_text.contains("VSeparator"))
	var tints: Dictionary = {}
	for key in ["hp", "stamina", "mana"]:
		var bar: ProgressBar = stats.find_child(key + "bar", true, false) as ProgressBar
		var fill: StyleBoxFlat = bar.get_theme_stylebox("fill") as StyleBoxFlat if bar != null and bar.has_theme_stylebox_override("fill") else null
		var value: Label = stats.find_child(key + "value", true, false) as Label
		tints[key] = null
		if fill != null:
			tints[key] = fill.bg_color
		if value == null or value.get_parent() != bar:
			tints[key] = "number not inside the bar"
	check("  health red, stamina gold and mana blue, each number inside its bar",
		tints["hp"] is Color and tints["hp"].r > 0.6 and tints["hp"].g < 0.3
		and tints["stamina"] is Color and tints["stamina"].r > 0.6 and tints["stamina"].b < 0.3
		and tints["mana"] is Color and tints["mana"].b > 0.6 and tints["mana"].r < 0.4, tints)
	# The level sits in a hotbar slot (day 1, "make that a hotbar slot"): the
	# theme's PanelSocket, the same socket as the hotbar and every grid cell.
	var badge: PanelContainer = stats.find_child("levelbadge", true, false) as PanelContainer
	var level_value: Label = stats.find_child("levelvalue", true, false) as Label
	check("  the level sits in a hotbar slot, square, with the number inside it",
		badge != null and badge.theme_type_variation == &"PanelSocket"
		and badge.custom_minimum_size.x == badge.custom_minimum_size.y
		and level_value != null and badge.is_ancestor_of(level_value),
		str(badge.theme_type_variation) if badge else "no levelbadge")
	stats.free()

	var Stats: Script = load("res://src/ui/statsscreen.gd") as Script
	check("under the XP bar: how far, and how much is left to the next level",
		Stats.xp_next_text(9_391, 1_007_892, 29) == "0% · 998K to level 30"
		and Stats.xp_next_text(50, 100, 3) == "50% · 50 to level 4",
		Stats.xp_next_text(9_391, 1_007_892, 29))
	var code: String = _code_src("res://src/ui/statsscreen.gd")
	check("  and the exact figures are in the tooltips",
		_func_body(code, "func _update_progression(").contains("tooltip_text = exact")
		and _func_body(code, "func _set_bar_and_label(").contains("bar.tooltip_text"))
	print("  stats: short numbers, two columns, coloured pools, the next level in words")


func _test_bank_buttons_and_the_cooking_window() -> void:
	section("BANK AND COOKING - hotbar buttons, one row of fish, a window in the middle")

	# Asked for on day 1: Deposit and Withdraw in the hotbar's style; twelve
	# empty boxes under the fire; the cooking window opening in the corner.
	var theme: Theme = load("res://assets/themes/rpg_ui_theme.tres") as Theme
	var socket: StyleBoxTexture = theme.get_stylebox("panel", &"PanelSocket") as StyleBoxTexture
	var normal: StyleBoxTexture = theme.get_stylebox("normal", &"ButtonSocket") as StyleBoxTexture
	var hover: StyleBoxTexture = theme.get_stylebox("hover", &"ButtonSocket") as StyleBoxTexture
	var pressed: StyleBoxTexture = theme.get_stylebox("pressed", &"ButtonSocket") as StyleBoxTexture
	check("the theme has a button drawn like a hotbar slot",
		theme.get_type_variation_base(&"ButtonSocket") == &"Button" and socket != null and normal != null
		and normal.texture == socket.texture and normal.texture.resource_path.ends_with("hotbarslot.png"))
	check("  which lights up under the pointer and darkens when pressed",
		hover != null and pressed != null and hover.texture == socket.texture
		and hover.modulate_color.v > normal.modulate_color.v and pressed.modulate_color.v < normal.modulate_color.v)
	var bank: Node = (load("res://scene/ui/bank/bankinventory.tscn") as PackedScene).instantiate()
	var dressed: Array = []
	for name_of in ["depositbuttons", "withdrawbutton"]:
		var b: Button = bank.find_child(name_of, true, false) as Button
		dressed.append(b != null and b.theme_type_variation == &"ButtonSocket" and not b.has_theme_stylebox_override("normal"))
	check("the bank's Deposit and Withdraw wear it", dressed == [true, true], dressed)
	bank.free()

	var Cooking: Script = load("res://src/ui/cooking/cookingscreen.gd") as Script
	check("one row of six, and a second only past six kinds of fish",
		Cooking.GRID_COLUMNS == 6 and Cooking.rows_for(0) == 1 and Cooking.rows_for(6) == 1
		and Cooking.rows_for(7) == 2 and Cooking.rows_for(12) == 2 and Cooking.rows_for(13) == 3)
	var joined: Array = Cooking.one_cell_per_kind([
		{"item_id": "rawmudfish", "quantity": 3}, {"item_id": "rawsilverfin", "quantity": 1},
		{"item_id": "rawmudfish", "quantity": 4}, {"item_id": "", "quantity": 9}])
	check("  one cell per kind: two stacks of mudfish are one cell of seven",
		joined == [{"item_id": "rawmudfish", "quantity": 7}, {"item_id": "rawsilverfin", "quantity": 1}], joined)

	var cooking: Control = (load("res://scene/ui/cooking/cookingscreen.tscn") as PackedScene).instantiate()
	add_child(cooking)
	var grid: Node = cooking.find_child("fishgrid", true, false)
	check("  the scene starts with one row", grid != null and grid.grid_width == 6 and grid.grid_height == 1
		and grid.get_child_count() == 6, [grid.grid_height if grid != null else -1])
	cooking.position = Vector2(58, 40)
	cooking.open_for_firepit(null, null)
	await get_tree().process_frame
	var wanted: Vector2 = PanelWindow.content_minimum(cooking)
	var middle: Vector2 = ((cooking.get_viewport_rect().size - cooking.size) * 0.5).floor()
	check("the cooking window is as big as what is in it, not 0x0",
		cooking.size.x >= 300.0 and cooking.size == wanted, [cooking.size, wanted])
	check("  and opens in the middle of the screen, wherever it was left",
		cooking.position == middle, [cooking.position, middle])
	var fire: Node2D = cooking.find_child("firepit", true, false) as Node2D
	var box: Control = cooking.find_child("firebox", true, false) as Control
	var fire_x: float = fire.position.x
	box.size = Vector2(box.size.x + 100.0, box.size.y)
	await get_tree().process_frame
	check("  a wider window keeps the fire in the middle of its box",
		is_equal_approx(fire.position.x, fire_x + 50.0), [fire_x, fire.position.x])
	# THE HEADER, day 1: it read "Cooking  Cooking 1  ×" with the title pushed
	# off centre. Now the level is a badge as wide as the ×, so the title sits
	# in the middle like BANK and INVENTORY.
	var badge: Label = cooking.find_child("skilllabel", true, false) as Label
	var title: Label = cooking.find_child("headerlabel", true, false) as Label
	var shut: Button = cooking.find_child("closebutton", true, false) as Button
	check("the cooking header is COOKING between a level badge and the ×, both as wide",
		title != null and title.text == "COOKING" and badge != null and badge.text.begins_with("Lv ")
		and shut != null and badge.get_index() == 0 and shut.get_index() == title.get_index() + 1
		and badge.size.x == shut.size.x
		and is_equal_approx(title.get_global_rect().get_center().x,
			(title.get_parent() as Control).get_global_rect().get_center().x),
		[badge.text if badge else "-", str(badge.size) if badge else "-", str(shut.size) if shut else "-"])
	grid.resize_grid(6, 2)
	check("a grid can be given another row", grid.get_child_count() == 12 and grid.columns == 6)
	cooking.queue_free()
	await get_tree().process_frame
	print("  bank and cooking: the hotbar's button, one row of fish, a sized and centred window")


func _test_the_tank_loop_takes_every_step() -> void:
	section("TANK - its own walk takes every step the other classes' walk takes")

	# Day 1: "tank not getting stamina xp". Tank replaces player.gd's
	# _physics_process() with an eased walk of its own, and that copy had
	# drifted: it never noted a key press (so the tank was "away" three minutes
	# after launch and earned no defence or agility XP), never paid agility for
	# sprinting or ground covered, never uncovered the map, and walked and
	# toggled its aura while chat was typed in. Each step is one player.gd
	# function now, and both loops must call every one of them.
	const STEPS := ["_stamp_input()", "_read_move_direction()", "_sprint_tick(",
		"_stop_sprint()", "_accrue_agility_from_travel(", "moved.emit(", "_tick_regen(",
		"_typing_in_ui()"]
	var player_src: String = _code_src("res://src/characters/player.gd")
	var tank_src: String = _code_src("res://src/characters/tank.gd")
	var base_loop: String = _func_body(player_src, "func _physics_process(")
	var tank_loop: String = ""
	for fn in ["func _physics_process(", "func _handle_movement(", "func _handle_moving(", "func _handle_idle("]:
		tank_loop += _func_body(tank_src, fn) + "\n"
	var base_missing: Array = []
	var tank_missing: Array = []
	for step in STEPS:
		if not base_loop.contains(step):
			base_missing.append(step)
		if not tank_loop.contains(step):
			tank_missing.append(step)
	check("the base loop is built from the shared steps", base_missing.is_empty(), base_missing)
	check("  and the tank's loop calls every one of them", tank_missing.is_empty(), tank_missing)
	check("  with no copy of its own of the keys or the sprint",
		not tank_src.contains("is_action_pressed(\"move_") and not tank_src.contains("_sprint_drain_accumulator +=")
		and not tank_src.contains("stamina - drain"))
	var stamp_at: int = tank_loop.find("_stamp_input()")
	check("  noting the key press before anything can return early",
		stamp_at != -1 and stamp_at < tank_loop.find("if is_dying:"))

	# AND WHAT THE STEPS DO, on a tank built outside the tree.
	var tank: Node = (load("res://src/characters/tank.gd") as GDScript).new()
	tank._last_input_ms = -1_000_000
	Input.action_press("move_right")
	tank._stamp_input()
	var noted: bool = not tank.is_afk()
	Input.action_release("move_right")
	check("a key press marks the tank as here, so its skill XP is earned", noted)
	tank.stamina = 100
	tank.sprint_agility_xp_per_sec = 0.0
	tank._sprint_tick(0.5)
	tank._sprint_tick(0.5)
	check("  a second of sprinting costs the tank stamina at the shared rate",
		tank.stamina == 100 - int(tank.sprint_stamina_drain_per_sec), tank.stamina)
	# Part-way to a point on both, so a _stop_sprint() that forgets either one
	# carries it into the next sprint.
	tank._is_sprinting = true
	tank._sprint_drain_accumulator = 0.5
	tank._sprint_agility_xp_accumulator = 0.5
	tank._stop_sprint()
	check("  and stopping clears what was banked toward the next point",
		not tank._is_sprinting and tank._sprint_drain_accumulator == 0.0
		and tank._sprint_agility_xp_accumulator == 0.0)
	tank.free()
	print("  tank: every step of the walk, shared - key presses, sprint, ground, map, typing")


func _test_the_game_says_its_version() -> void:
	section("VERSION - the game says which build it is, MAJOR.MINOR.PATCH")

	# The owner, 6 Oct, on numbering releases: MAJOR.MINOR.PATCH, 0.x until
	# launch. The number lives in Api.DISPLAY_VERSION and nowhere else;
	# everything that shows it reads it from there.
	var version: String = GameConstants.game_version()
	var shape := RegEx.create_from_string("^\\d+\\.\\d+\\.\\d+$")
	check("the game has a version, three whole numbers, from Api.DISPLAY_VERSION",
		shape.search(version) != null and version == Api.DISPLAY_VERSION, version)
	check("  and it is shown with a v in front", GameConstants.version_text() == "v" + version,
		GameConstants.version_text())

	# THE WINDOWS FILE SAYS THE SAME. Windows wants four numbers, so it is the
	# version with .0 after it, and an export carries whatever is typed here -
	# 0.1.0.0 sat in it unchanged while the game moved on.
	var presets: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	var file_version := RegEx.create_from_string("application/file_version=\"([^\"]*)\"").search(presets)
	var product_version := RegEx.create_from_string("application/product_version=\"([^\"]*)\"").search(presets)
	check("the Windows export's file and product versions are the game's",
		file_version != null and product_version != null
		and file_version.get_string(1) == version + ".0" and product_version.get_string(1) == version + ".0",
		[file_version.get_string(1) if file_version else "none", product_version.get_string(1) if product_version else "none"])

	# THE LOGIN SCREEN, in the bottom-right corner.
	var login: Control = (load("res://src/ui/menus/loginmenu.gd") as GDScript).new() as Control
	login._add_version_label()
	login._add_version_label()
	var corner: Label = login.get_node_or_null("versionlabel") as Label
	check("the login screen shows it in the bottom-right corner, once",
		corner != null and corner.text == "v" + version and corner.anchor_left == 1.0 and corner.anchor_top == 1.0
		and login.find_children("versionlabel", "", true, false).size() == 1,
		corner.text if corner != null else "no label")
	check("  and it never catches a click meant for the screen",
		corner != null and corner.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	login.free()
	check("  built when the screen opens, and the Menu's when the HUD does",
		_func_body(_code_src("res://src/ui/menus/loginmenu.gd"), "func _ready(").contains("_add_version_label()")
		and _func_body(_code_src("res://src/ui/characterhud.gd"), "func _ready(").contains("_add_version_to_menu()"))

	# AND UNDER THE MENU, while playing.
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	hud._add_version_to_menu()
	var foot: Label = hud.get_node_or_null("%systemmenu/systemitems/versionlabel") as Label
	var items: Node = hud.get_node_or_null("%systemmenu/systemitems")
	check("the Menu dropdown ends with it, under Log out",
		foot != null and foot.text == "Elusion v" + version and items != null
		and items.get_child(items.get_child_count() - 1) == foot,
		foot.text if foot != null else "no label")
	hud.free()


func _test_the_first_five_minutes() -> void:
	section("FIRST FIVE MINUTES - nine buttons, a Controls card, a welcome, the right name")

	# Day 1, played as a brand-new player: fourteen small buttons on the bar,
	# nothing anywhere saying what a key does or where the Field is, a login
	# button that named another game, and two windows out of line.

	# ---- the bar: eight buttons, and two dropdowns for the rest ----
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	var row: Array[String] = []
	for child in hud.get_node("%navbuttons").get_children():
		if child is Button:
			row.append(str(child.name))
	check("the bar is nine buttons, the everyday windows first (Minigames since 0.93.3)",
		row == ["inventorybutton", "equipmentbutton", "statsbutton", "shopbutton", "mapbutton",
			"chatbutton", "socialbutton", "minigamesbutton", "menubutton"], row)
	var held := func(menu_name: String) -> Array[String]:
		var out: Array[String] = []
		for b in hud.get_node("%" + menu_name).find_children("*", "Button", true, false):
			out.append(str(b.name))
		return out
	check("  Social holds Friends, Players, Guild, Party, Trade, Kingdom and Kills",
		held.call("socialmenu") == ["friendsbutton", "playersbutton", "guildbutton", "partybutton", "tradebutton", "kingdombutton", "killsbutton"],
		held.call("socialmenu"))
	check("  Menu holds Controls, Options, Switch character and Log out",
		held.call("systemmenu") == ["controlsbutton", "optionsbutton", "switchcharacterbutton", "logoutbutton"],
		held.call("systemmenu"))

	hud._wire_nav_buttons()
	var social: Control = hud.get_node("%socialmenu")
	var system: Control = hud.get_node("%systemmenu")
	check("  both shut until asked", not social.visible and not system.visible)
	(hud.get_node("%socialbutton") as Button).pressed.emit()
	check("pressing Social opens its dropdown", social.visible and not system.visible)
	(hud.get_node("%menubutton") as Button).pressed.emit()
	check("  Menu shuts it and opens its own", system.visible and not social.visible)
	(hud.get_node("%menubutton") as Button).pressed.emit()
	check("  a second press shuts it", not system.visible)
	(hud.get_node("%socialbutton") as Button).pressed.emit()
	(hud.get_node("%inventorybutton") as Button).pressed.emit()
	check("  and any button on the bar shuts it", not social.visible)
	(hud.get_node("%menubutton") as Button).pressed.emit()
	(hud.get_node("%controlsbutton") as Button).pressed.emit()
	check("a choice in a dropdown shuts it and opens what it names",
		not system.visible and hud.controls_panel != null and hud.controls_panel.visible)
	(hud.get_node("%socialbutton") as Button).pressed.emit()
	check("Escape shuts an open dropdown, and says when there was none",
		hud.close_nav_menus() and not social.visible and not hud.close_nav_menus())
	var hud_code: String = _code_src("res://src/ui/characterhud.gd")
	var esc_body: String = _func_body(hud_code, "func _unhandled_input(")
	var shut_at: int = esc_body.find("close_nav_menus()")
	check("  before it closes any window",
		shut_at != -1 and shut_at < esc_body.find("is_panel_open()"))
	check("  and a click anywhere else shuts it too",
		_func_body(hud_code, "func _input(").contains("_click_outside_nav_menus(event)"))

	var at: Vector2 = hud.nav_menu_position(Rect2(824, 676, 116, 30), Vector2(170, 178), Vector2(1280, 720))
	check("a dropdown opens above its button, right edges lined up, clear of the health bars",
		at == Vector2(770, 492), at)
	at = hud.nav_menu_position(Rect2(10, 676, 60, 30), Vector2(170, 178), Vector2(1280, 720))
	check("  and never off the left of the screen", at.x == 0.0, at)

	var social_button: Button = hud.get_node("%socialbutton") as Button
	var social_tip: String = social_button.tooltip_text
	hud._mark_trade_button(true, "caster")
	check("a trade waiting inside Social lights Social, and says what",
		social_button.text == "Social •" and social_button.tooltip_text == "Waiting for you: Trade",
		[social_button.text, social_button.tooltip_text])
	hud._mark_trade_button(false)
	check("  and goes out with it", social_button.text == "Social" and social_button.tooltip_text == social_tip,
		[social_button.text, social_button.tooltip_text])
	var hud_script: Script = hud.get_script()
	hud_script._asks_last = {"friends": {"count": 1, "newest": "medic", "at": 1}}
	hud._paint_ask_buttons()
	check("  a friend request lights it too", social_button.text == "Social •"
		and social_button.tooltip_text == "Waiting for you: Friends", social_button.tooltip_text)
	hud_script._forget_asks()
	hud._paint_ask_buttons()
	check("the bar says each window's key", (hud.get_node("%inventorybutton") as Button).tooltip_text.ends_with(
		"(%s)" % ControlsPanel.action_key("inventory_toggle"))
		and (hud.get_node("%controlsbutton") as Button).tooltip_text.ends_with("(%s)" % ControlsPanel.action_key("help_toggle")),
		(hud.get_node("%inventorybutton") as Button).tooltip_text)
	hud.free()

	# ---- the Controls card, read from the input map ----
	var card: ControlsPanel = (load("res://scene/ui/controls/controlspanel.tscn") as PackedScene).instantiate() as ControlsPanel
	add_child(card)
	card.open_controls()
	var keys: Dictionary = {}
	for i in range(0, card.key_grid.get_child_count() - 1, 2):
		keys[(card.key_grid.get_child(i) as Label).text] = (card.key_grid.get_child(i + 1) as Label).text
	check("the Controls card has a line for every row", keys.size() == ControlsPanel.ROWS.size(), keys.size())
	check("  Space or left-click attacks, Shift sprints, E uses, H is the card - and right-click is the healer's aura",
		keys.get("Attack, aiming with the mouse") == "Space or left-click" and keys.get("Sprint") == "Hold Shift"
		and keys.get("Healer: drop a healing aura at the mouse") == "Right-click"
		and keys.get("Use the shop, bank, fire or fishing spot") == "E" and keys.get("This card") == "H", keys)
	check("  W A S D walk, and the hotbar is 1 to 0",
		keys.get("Move") == "W A S D or arrows" and keys.get("Use the item on a hotbar key") == "1 to 0",
		[keys.get("Move"), keys.get("Use the item on a hotbar key")])
	var leaked: Array = []
	for how in keys.values():
		if String(how).contains("_") or String(how).contains("?"):
			leaked.append(how)
	check("  every key it names is bound - no action name shown as words", leaked.is_empty(), leaked)
	# EVERY KEY THE GAME BINDS IS ON THE CARD. A new action added to
	# project.godot with no line here would be a key nobody is told about.
	var named: Dictionary = {}
	for spec in ControlsPanel.ROWS:
		named[String(spec[1])] = true
	var untold: Array[String] = []
	for prop in ProjectSettings.get_property_list():
		var key_path: String = str(prop.name)
		if not key_path.begins_with("input/") or key_path.begins_with("input/ui_"):
			continue
		var action: String = key_path.trim_prefix("input/")
		if not (named.has(action) or (action.begins_with("move_") and named.has("move"))):
			untold.append(action)
	check("  and no key the game binds is missing from it", untold.is_empty(), untold)
	await get_tree().process_frame
	var middle: Vector2 = ((card.get_viewport_rect().size - card.size) * 0.5).floor()
	check("  in the middle of the screen, as big as what is on it",
		card.position == middle and card.size == PanelWindow.content_minimum(card)
		and card.size.x >= 400.0, [card.position, middle, card.size])
	check("  with no welcome on it", not card.welcome_box.visible and not card.got_it_button.visible
		and card.header_label.text == "CONTROLS")

	# ---- the welcome, once ----
	var was_seen_path: String = ControlsPanel.seen_path
	ControlsPanel.seen_path = "user://_suite_seen.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ControlsPanel.seen_path))
	check("a computer that has never played has not seen the welcome", not ControlsPanel.has_seen_welcome())
	card.open_welcome()
	check("the welcome says where to go, then the keys, then Got it",
		card.header_label.text == "WELCOME TO ELUSION" and card.welcome_box.visible
		and card.welcome_text.text.contains("Field") and card.got_it_button.visible
		and card.footer_label.text == "Press H any time to see these keys again.", card.footer_label.text)
	check("  and is marked seen the moment it shows", ControlsPanel.has_seen_welcome())
	card.got_it_button.pressed.emit()
	check("Got it closes it", not card.visible)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ControlsPanel.seen_path))
	ControlsPanel.seen_path = was_seen_path
	card.queue_free()
	check("the welcome comes up in town and nowhere else - never in this suite",
		hud_script.welcome_belongs_in("res://scene/elusion.tscn")
		and not hud_script.welcome_belongs_in("res://scene/field.tscn")
		and not hud_script.welcome_belongs_in("res://scene/tests/tests.tscn"))
	check("  offered when a character arrives, and only if not yet seen",
		_func_body(hud_code, "func set_active_character(").contains("_offer_welcome_soon()")
		and _func_body(hud_code, "func offer_welcome(").contains("ControlsPanel.has_seen_welcome()")
		and _func_body(hud_code, "func offer_welcome(").contains("welcome_belongs_in("))

	# ---- the login button names this game ----
	var login_text: String = FileAccess.get_file_as_string("res://scene/ui/menus/loginmenu.tscn")
	check("the login button says Enter Elusion",
		str(_node_prop_in_scene("res://scene/ui/menus/loginmenu.tscn",
			"centercontainer/mainpanel/margincontainer/vboxcontainer/loginform/loginbutton", "text")) == "Enter Elusion")
	check("  and no screen anywhere says Elysium", not login_text.contains("Elysium")
		and not hud_code.contains("Elysium"))

	# ---- the Gear window's title, like the others ----
	var inv_size: Variant = _node_prop_in_scene("res://scene/ui/inventory/inventory.tscn",
		"mainpanel/margincontainer/vboxcontainer/headerpanel/hboxcontainer/headerlabel", "theme_override_font_sizes/font_size")
	var eq_path := "mainpanel/margincontainer/vboxcontainer/headerpanel/hboxcontainer/headerlabel"
	check("the Gear window's title is EQUIPMENT, centred, the size of INVENTORY's",
		str(_node_prop_in_scene("res://scene/ui/equipment/equipmentpanel.tscn", eq_path, "text")) == "EQUIPMENT"
		and int(_node_prop_in_scene("res://scene/ui/equipment/equipmentpanel.tscn", eq_path, "horizontal_alignment")) == HORIZONTAL_ALIGNMENT_CENTER
		and _node_prop_in_scene("res://scene/ui/equipment/equipmentpanel.tscn", eq_path, "theme_override_font_sizes/font_size") == inv_size,
		inv_size)

	# ---- Character Stats: the left column from top to bottom ----
	var stats: Control = (load("res://scene/ui/statsscreen.tscn") as PackedScene).instantiate() as Control
	add_child(stats)
	stats.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	var frame: Control = stats.find_child("leftcolumn", true, false) as Control
	var level_row: Control = stats.find_child("levelrow", true, false) as Control
	var mana_row: Control = stats.find_child("manastat", true, false) as Control
	var top_gap: float = level_row.get_global_rect().position.y - frame.get_global_rect().position.y
	var bottom_gap: float = frame.get_global_rect().end.y - mana_row.get_global_rect().end.y
	check("Character Stats: LEVEL sits at the top of its box, Mana at the bottom",
		top_gap <= 16.0 and bottom_gap <= 16.0 and absf(top_gap - bottom_gap) <= 4.0, [top_gap, bottom_gap])
	stats.queue_free()
	print("  first five minutes: nine buttons, every key on a card, a welcome once, Enter Elusion")


func _test_staff_panel() -> void:
	section("STAFF PANEL")

	var panel_script: Script = require_script(
		"res://src/ui/staff/staffpanel.gd", "the staff panel")
	if panel_script == null:
		return
	var offer := func(viewer: String, role: String, actionable: bool, banned: bool = false) -> Dictionary:
		return panel_script.actions_for(viewer, {"role": role, "actionable": actionable, "banned": banned})

	# ---- reach: can_act_on() is STRICTLY above ----
	var o: Dictionary = offer.call("mod", "player", true)
	check("a mod may kick and ban a player", o.kick and o.ban, o)
	check("but not permanently - MAX_MOD_BAN_DAYS", not o.ban_permanent, o)
	check("and changes no ranks", o.promote_to == "" and o.demote_to == "", o)
	check("unban is only offered on a ban", not o.unban and offer.call("mod", "player", true, true).unban)

	o = offer.call("mod", "mod", false)
	check("a mod cannot touch another mod", not o.kick and not o.ban and not o.unban, o)

	# BOTH SIDES MUST AGREE. The server's `actionable` is the authority, and
	# the client's own rank stops a panel that has not caught up with a
	# demotion from showing buttons its user just lost.
	check("a stale 'actionable' from the server offers nothing to an equal",
		not offer.call("mod", "mod", true).kick)
	check("and a client that thinks it outranks, against the server's no, offers nothing",
		not offer.call("owner", "player", false).kick)

	# ---- promotion: never to your own rank, never to owner ----
	o = offer.call("dev", "player", true)
	check("a dev may promote a player to mod", o.promote_to == "mod", o)
	check("and ban permanently", o.ban_permanent, o)
	o = offer.call("dev", "mod", true)
	check("a dev may not promote a mod - that would make a dev", o.promote_to == "", o)
	check("a dev may demote a mod to player", o.demote_to == "player", o)
	o = offer.call("owner", "mod", true)
	check("the owner may make a mod a dev", o.promote_to == "dev", o)
	o = offer.call("owner", "dev", true)
	check("owner is never offered as a promotion", o.promote_to == "", o)
	check("the owner may demote a dev to mod", o.demote_to == "mod", o)
	check("nobody is offered anything against the owner",
		not offer.call("owner", "owner", false).kick and not offer.call("dev", "owner", false).kick)

	# FAILS LOW, like Api.role_at_least(): a rank this build has never heard of
	# is a player, on either side.
	check("an unknown viewer rank is offered nothing", not offer.call("superuser", "player", true).kick)
	check("an unknown target rank reads as a player", offer.call("mod", "wizard", true).kick)

	# ---- a note is reach-gated like a sanction ----
	check("a note is offered wherever a kick is",
		offer.call("mod", "player", true).note and not offer.call("mod", "mod", false).note)

	# ---- what goes on the wire ----
	# THE SEARCH AND THE FILTERS ARE THE SERVER'S NOW - see "THE SERVER PAGES"
	# at the top of staffpanel.gd. So what is worth pinning here is the question
	# as it leaves: encoded, and with nothing empty in it, because `q=` is a
	# search for nothing and `before=0` is not a cursor.
	check("a query is encoded and keeps its order",
		panel_script.build_query({"show": "all", "q": "a b&c", "limit": 50}) == "?show=all&q=a%20b%26c&limit=50",
		panel_script.build_query({"show": "all", "q": "a b&c", "limit": 50}))
	check("an empty search is left out, not sent as q=",
		panel_script.build_query({"show": "online", "q": "", "limit": 50}) == "?show=online&limit=50")
	check("a zero cursor is left out, not sent as before=0",
		panel_script.build_query({"player": "rowdy", "before": 0, "limit": 25}) == "?player=rowdy&limit=25")
	check("nothing at all is no query at all", panel_script.build_query({}) == "")

	# ---- what comes back ----
	# THE TWO JSON TRAPS: numbers arrive as floats, and the last page's cursor
	# arrives as null - which str() makes "<null>", a name to page after.
	var last_page: Dictionary = panel_script.read_page(
		{"accounts": [{"username": "a"}, "junk"], "more": true, "next_after": null}, "accounts", "next_after")
	check("a null cursor is no cursor", last_page.cursor == null, last_page)
	check("and no cursor means no next page, whatever `more` says", last_page.more == false, last_page)
	check("only dictionaries are rows", last_page.rows.size() == 1, last_page.rows)
	var log_page: Dictionary = panel_script.read_page(
		{"actions": [], "more": true, "next_before": 12.0}, "actions", "next_before")
	check("a float cursor is an int", log_page.cursor is int and log_page.cursor == 12 and log_page.more, log_page)
	check("an answer that is not a dictionary is an empty page",
		panel_script.read_page("oops", "accounts", "next_after").rows.is_empty())

	# ---- the record, in words ----
	var tally: Dictionary = {"note": 1.0, "warn": 3.0, "ban": 2.0, "kick": 1.0, "unban": 4.0}
	check("a record reads bans, kicks, warnings, notes - in that order, with plurals",
		panel_script.describe_record(tally) == "2 bans · 1 kick · 3 warnings · 1 note",
		panel_script.describe_record(tally))
	check("the list row leaves the notes out - a note is not a sanction",
		panel_script.describe_record(tally, panel_script.ROW_RECORD_KINDS) == "2 bans · 1 kick · 3 warnings")
	check("a clean record says nothing", panel_script.describe_record({}) == ""
		and panel_script.describe_record(null) == "")

	check("a ban reads as a sentence, with the reason kept whole",
		panel_script.describe_entry({"by": "themod", "action": "ban", "target": "rowdy",
			"detail": "3 days: language"}) == "themod banned rowdy - 3 days: language")
	check("a warning",
		panel_script.describe_entry({"by": "themod", "action": "warn", "target": "rowdy",
			"detail": "spam"}) == "themod warned rowdy - spam")
	check("no detail, no dash",
		panel_script.describe_entry({"by": "thedev", "action": "unban", "target": "rowdy"})
		== "thedev lifted rowdy's ban")
	check("a kind this build has never heard of still says who, what and whom",
		panel_script.describe_entry({"by": "boss", "action": "smite", "target": "rowdy", "detail": "x"})
		== "boss smite rowdy - x")
	check("a log line about a player opens that player",
		panel_script.target_is_account({"action": "kick", "target": "rowdy"}))
	check("a line about a guild does not pretend it is an account",
		not panel_script.target_is_account({"action": "guild_rename", "target": "Shared"}))
	check("nor does a teleport of everyone",
		not panel_script.target_is_account({"action": "teleport", "target": "everyone"}))
	check("the count says how much of the match is loaded",
		panel_script.describe_count(50, 1204, 12) == "50 of 1,204 · 12 online",
		panel_script.describe_count(50, 1204, 12))
	check("and just the total once it all is",
		panel_script.describe_count(12, 12, 3) == "12 accounts · 3 online"
		and panel_script.describe_count(1, 1, 0) == "1 account · 0 online",
		panel_script.describe_count(12, 12, 3))

	# ---- presence text, against the SERVER'S clock ----
	var now := 1_000_000
	check("online reads as online", panel_script.describe_presence({"online": true}, now) == "Online now")
	check("minutes", panel_script.describe_presence({"last_seen_at": now - 300}, now) == "Last seen 5 min ago",
		panel_script.describe_presence({"last_seen_at": now - 300}, now))
	check("hours", panel_script.describe_presence({"last_seen_at": now - 7200}, now) == "Last seen 2 h ago")
	check("days", panel_script.describe_presence({"last_seen_at": now - 3 * 86400}, now) == "Last seen 3 days ago")
	check("no heartbeat at all is just offline", panel_script.describe_presence({"last_seen_at": 0}, now) == "Offline")

	# ---- the scene carries every node the script reaches for ----
	# DERIVED FROM THE SCRIPT, not a list typed here. The list this replaced was
	# the panel's twenty-four nodes as of the day it was written, and the panel
	# grew twenty more - a hand list checks the old panel and passes.
	var scene: Node = (load("res://scene/ui/staff/staffpanel.tscn") as PackedScene).instantiate()
	var node_ref := RegEx.new()
	node_ref.compile("= %([a-z][a-z0-9_]+)")
	var missing: Array = []
	var asked: int = 0
	for m in node_ref.search_all(_code_only(FileAccess.get_file_as_string("res://src/ui/staff/staffpanel.gd"))):
		asked += 1
		if scene.get_node_or_null("%" + m.get_string(1)) == null:
			missing.append(m.get_string(1))
	check("staffpanel.tscn has every node staffpanel.gd uses",
		missing.is_empty() and asked >= 40, "missing: %s (%d asked)" % [missing, asked])
	scene.free()

	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	# BY UNIQUE NAME, NOT BY PATH. This read "navhbox/staffrow/staffbutton" until
	# the nav row was wrapped in navframe to give it a frame. A hard-coded path
	# survives no rearrangement at all, and when it breaks it fails HERE, saying
	# the scene has lost its Staff button, when the button is sitting exactly
	# where it was and only the path to it moved. The unique name is resolved
	# against the scene, so wrapping the row again costs nothing.
	var staff_button: Node = hud.get_node_or_null("%staffbutton")
	check("the HUD has a Staff button on a row of its own", staff_button is Button)
	# HIDDEN IN THE FILE. The script shows it to staff; a player must never see
	# it even for the frame before the script runs.
	check("and it starts hidden", staff_button is Button and not (staff_button as Button).visible)

	# ---- the menu bar: the two lookups characterhud.gd makes by name ----
	# unique_name_in_owner is one checkbox in the inspector, and turning it off
	# costs nothing visible: the scene still opens, the buttons still draw, and
	# _wire_nav_buttons() quietly connects NOTHING, so every button in the menu
	# does nothing when clicked. That is the failure this pair of lines catches.
	var nav_row: Node = hud.get_node_or_null("%navbuttons")
	check("the HUD registers %navbuttons", nav_row != null)
	check("the HUD registers %staffrow", hud.get_node_or_null("%staffrow") != null)

	# AND THE BUTTONS THEMSELVES. _wire_nav_buttons() connects by UNIQUE NAME and
	# skips anything it cannot find, so a renamed button - or one whose "unique
	# name" box was unticked - is a dead button with no error. Nine of them sit
	# in the Social and Menu dropdowns now, not on the row.
	var absent: Array = []
	for wanted in hud.NAV_BUTTON_NAMES:
		if not (hud.get_node_or_null("%" + wanted) is Button):
			absent.append(wanted)
	check("every button characterhud.gd wires up is in the scene", absent.is_empty(), absent)

	# ---- where the bar sits, checked against the things it has to miss ----
	var frame: Control = hud.get_node_or_null("%navframe") as Control
	check("the nav bar is framed", frame is PanelContainer)
	check("it hangs off the bottom of the screen",
		frame != null and frame.anchor_bottom == 1.0 and frame.offset_bottom < 0.0)
	# GROWING UPWARD IS THE POINT. The owner gets a second row; with the bottom
	# edge pinned, that row is added ABOVE and the ordinary menu stays put. Flip
	# this to END and the whole menu jumps whenever the owner signs in.
	check("and grows upward, so the menu sits in one place for everyone",
		frame != null and frame.grow_vertical == Control.GROW_DIRECTION_BEGIN)

	# THE RIGHT EDGE IS DODGING THE READOUTS, not a number picked by eye. The
	# health and magic bars run from barcontainer's offset plus their own, down
	# to y=709 - straight through the height of the menu bar. Both numbers are
	# read out of the scene here so that moving either one fails this line
	# instead of silently putting Logout underneath the health bar.
	var screen_w: float = float(ProjectSettings.get_setting(
		"display/window/size/viewport_width", 1280))
	var holder: Control = hud.get_node_or_null("barcontainer") as Control
	var hp: Control = hud.get_node_or_null("barcontainer/healthbar") as Control
	if frame != null and holder != null and hp != null:
		var bar_right: float = screen_w + frame.offset_right
		var readouts_left: float = holder.offset_left + hp.offset_left
		check("and it stops clear of the health and magic bars", bar_right < readouts_left,
			"bar ends at %.0f, the readouts begin at %.0f" % [bar_right, readouts_left])
	else:
		check("and it stops clear of the health and magic bars", false, "nodes missing")
	hud.free()

	# ---- the two social panels carry what their scripts reach for ----
	# Same failure as the HUD's own unique names, and the same silence: every
	# lookup in these two is get_node_or_null, so a missing name is a panel
	# that opens, draws, and does nothing at all when clicked.
	for spec in [
		["res://scene/ui/chat/chatpanel.tscn",
			["chatlines", "chatscroll", "chattabs", "chatentry", "chatsendbutton",
			"chatimagebutton", "chatclosebutton", "chatnotice", "chatto", "chattolabel"]],
		["res://scene/ui/friends/friendspanel.tscn",
			["friendsrows", "friendsaddentry", "friendsaddbutton", "friendsclosebutton",
			"friendstitle", "friendsrequests", "friendsnotice", "friendscount"]],
		["res://scene/ui/equipment/equipmentpanel.tscn",
			["equipclosebutton", "equipdamagevalue", "equipspeedvalue", "equiparmourvalue",
			"equipsoakvalue", "equippreview", "equippreviewbox", "equippreviewhint",
			"equiphealthbonusvalue", "equipmanabonusvalue", "equipdamagebonusvalue",
			"equipresistvalue"]],
		["res://scene/ui/guild/guildpanel.tscn",
			["guildrows", "guildtitle", "guildtag", "guildcount", "guildentry",
			"guildactionbutton", "actionpanel", "guildclosebutton",
			"guildnotice", "footerbox",
			"guildleavebutton", "guilddisbandbutton"]],
	]:
		var built: Node = (load(String(spec[0])) as PackedScene).instantiate()
		var gone: Array = []
		for unique in spec[1]:
			if built.get_node_or_null("%" + String(unique)) == null:
				gone.append(unique)
		check("%s has every node its script uses" % String(spec[0]).get_file(),
			gone.is_empty(), gone)
		built.free()

	# ---- world chat cannot be used to paint the log ----
	# The log renders BBCode so staff ranks can be coloured, and BBCode is not
	# only colour: [img]url[/img] makes the client FETCH that url. A message is
	# text, so every opening bracket in one has to stop being a tag.
	var chat: Node = (load("res://scene/ui/chat/chatpanel.tscn") as PackedScene).instantiate()
	check("a bracket in a message is neutralised",
		chat._escape("[color=red]hi[/color]") == "[lb]color=red]hi[lb]/color]",
		chat._escape("[color=red]hi[/color]"))
	check("and so is an image tag",
		not chat._escape("[img]http://x/y.png[/img]").begins_with("[img"))
	check("ordinary text is left alone", chat._escape("hello there") == "hello there")

	# ---- four channels, and the client agrees with the server about them ----
	check("the client knows five channels - party since 0.42.0", chat.CHANNELS.size() == 5 and chat.CHANNELS.has("party"), chat.CHANNELS)
	var unlabelled: Array = []
	for room in chat.CHANNELS:
		if not chat.CHANNEL_LABELS.has(room):
			unlabelled.append(room)
	check("and every one has a tab label", unlabelled.is_empty(), unlabelled)
	check("world is among them", chat.CHANNELS.has("world"))
	check("so is a private one", chat.CHANNELS.has("private"))
	check("and guild - which is live; see _test_guild_chat_is_open()",
		chat.CHANNELS.has("guild"))

	# THE CAP THE BRIEF ASKED FOR, and it is PER CHANNEL. Shared, a busy world
	# channel would push a whisper out of its own window.
	check("a channel keeps 100 lines", chat.LINES_KEPT == 100, chat.LINES_KEPT)

	# ---- a picture is never loaded from the link somebody pasted ----
	# The whole reason the relay exists. If this file ever grows a call that
	# loads a remote URL directly, every viewer's address goes to whoever
	# posted it.
	var chat_source: String = FileAccess.get_file_as_string(
		"res://src/ui/chat/chatpanel.gd")
	check("the client asks the server to fetch pictures",
		chat_source.contains("/api/chat/image"))
	check("and decodes only what the server sent it",
		chat_source.contains("load_png_from_buffer"))
	check("nothing here opens a remote address itself",
		not chat_source.contains("http://") or chat_source.contains("begins_with(\"http://\")"))
	chat.free()

	# ---- the emoji font ships ----
	# A pasted emoji with no colour font behind it is a blank box, on every
	# machine, for everyone.
	check("the colour emoji font is in the project",
		ResourceLoader.exists("res://assets/fonts/NotoColorEmoji.ttf"))

	# ---- the hotbar ----
	# THE SLOTS MOVED TWO LEVELS DOWN when the bar was given a frame, and the
	# lookup that finds them used to be has_node("slot1") - a direct-child
	# check. That fails silently: nine warnings in the log, a hotbar that draws
	# perfectly and does nothing at all when you press a number key.
	var bar: Node = (load("res://scene/ui/hotbar.tscn") as PackedScene).instantiate()
	var lost: Array = []
	var keyless: Array = []
	for n in range(1, Hotbar.SLOT_COUNT + 1):
		var slot: Node = bar.find_child("slot%d" % n, true, false)
		if slot == null:
			lost.append("slot%d" % n)
			continue
		# AND THE KEY NUMBER IS A NODE NOW, not baked into the empty art - so
		# it is still there once a slot has something in it. That was the whole
		# complaint: a filled slot used to stop saying which key it was.
		#
		# READ OFF THE KEY, not off the slot's number. The tenth slot is fired
		# by 0, so str(n) would demand it say "10" - a number no key has.
		var key: Label = slot.get_node_or_null("keylabel") as Label
		var wanted: String = OS.get_keycode_string(Hotbar.SLOT_KEYS[n - 1]) \
			if n - 1 < Hotbar.SLOT_KEYS.size() else "?"
		if key == null or key.text != wanted:
			keyless.append("slot%d says %s, its key is %s" % [n,
				key.text if key != null else "nothing", wanted])
	check("every hotbar slot is findable", lost.is_empty(), lost)
	check("and each one shows its own key number", keyless.is_empty(), keyless)
	check("the bar itself is a framed panel", bar is PanelContainer, bar.get_class())

	# ---- the commissioned slot art is the slot ----
	# It used to be a 32px picture sitting INSIDE a panel the theme drew, which
	# meant an item icon covered it completely and the art you paid for was
	# only ever visible on an empty slot. As a nine-patched stylebox it frames
	# every slot, full or empty, and the item sits inside it.
	check("the slot art ships with the game",
		ResourceLoader.exists("res://art/images/hotbarslot.png"))
	var one: Control = bar.find_child("slot1", true, false) as Control
	var skin: StyleBox = one.get_theme_stylebox("panel") if one != null else null
	check("and it is what draws a slot", skin is StyleBoxTexture, skin)
	if skin is StyleBoxTexture:
		var skinned: StyleBoxTexture = skin as StyleBoxTexture
		# NINE-PATCHED. Without margins the frame stretches with the slot and
		# the artist's 1px outline turns into a smear.
		check("nine-patched, so the frame never stretches",
			skinned.texture_margin_left > 0.0 and skinned.texture_margin_top > 0.0,
			skinned.texture_margin_left)
		check("with the content pushed inside the frame",
			skinned.content_margin_left >= skinned.texture_margin_left,
			skinned.content_margin_left)
	# AND THE SLOT IS BIG ENOUGH TO HOLD SOMETHING. The art's hole is 18px at
	# its native 32; a 32px item icon in that is an icon wearing the frame as a
	# belt. See SLOT_SIZE in hotbarslot.gd.
	check("a slot is large enough for an item inside its frame",
		one != null and one.custom_minimum_size.x >= 40.0,
		str(one.custom_minimum_size) if one else "no slot")
	bar.free()

	# ---- one statement of what a rank looks like ----
	# The nameplate over a player's head, their name in chat and their row in
	# the friends list all paint from this. Three copies would drift.
	check("every rank has a colour", Api.RANK_COLOURS.size() == Api.RANK_ORDER.size(), Api.RANK_COLOURS.size())
	check("the owner's is not the player's",
		Api.colour_for_role("owner") != Api.colour_for_role("player"))
	check("a rank this build has never heard of paints as a player",
		Api.colour_for_role("archmage") == Api.colour_for_role("player"))
	check("the client can be told when its rank changes",
		Api.has_signal("identity_changed"))

	# ---- the stat bars' numbers are anchored, not hand-placed ----
	# EVERY ONE OF THESE WAS WRONG IN A DIFFERENT WAY. The six labels had five
	# geometries between them: one at a fixed offset_left of 86, three anchored
	# full-width but with offsets of 85 and -87 that go NEGATIVE on any bar
	# narrower than 172, and two correct. The bars carry FILL|EXPAND, so none of
	# those numbers survives the panel being any width but the one they were
	# placed at - which is how "52/100" ended up sitting right of centre and
	# "85/100" ended up clipped.
	var stats: Node = (load("res://scene/ui/statsscreen.tscn") as PackedScene).instantiate()
	var adrift: Array = []
	for bar_name in ["attack", "defense", "agility", "magic", "fishing", "cooking"]:
		var tag: Control = stats.get_node_or_null("%" + bar_name + "barlabel") as Control
		if tag == null:
			adrift.append(bar_name + ": missing")
			continue
		# Anchored across the whole bar with no horizontal offsets is the only
		# arrangement that is centred at EVERY width.
		if tag.anchor_left != 0.0 or tag.anchor_right != 1.0:
			adrift.append("%s: anchors %.2f..%.2f" % [bar_name, tag.anchor_left, tag.anchor_right])
		elif tag.offset_left != 0.0 or tag.offset_right != 0.0:
			adrift.append("%s: offsets %.0f/%.0f" % [bar_name, tag.offset_left, tag.offset_right])
		elif tag.horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER:
			adrift.append(bar_name + ": not centred")
	check("every stat bar's number is centred on its bar", adrift.is_empty(), adrift)

	# AND THE TWO SECTIONS LINE UP. The skills rows' name labels expanded while
	# the combat rows' held a fixed 90, so the two blocks' bars started at
	# different x down the same panel.
	var ragged: Array = []
	for row_name in ["attackrow", "defenserow", "agilityrow", "magicrow",
			"fishingrow", "cookingrow"]:
		# find_child rather than a path: these six sit at the bottom of two
		# different seven-deep branches, and writing those out would make this
		# check break every time the panel is re-nested.
		var found: Node = stats.find_child(row_name, true, false)
		if found == null:
			ragged.append(row_name + ": missing")
			continue
		var name_tag: Control = found.get_node_or_null("label") as Control
		if name_tag == null or name_tag.custom_minimum_size.x != 90.0:
			ragged.append(row_name)
	check("every stat row's name holds the same width", ragged.is_empty(), ragged)
	stats.free()

	# ---- the window actually fills the screen ----
	# THIS IS THE ONE THAT MADE FULLSCREEN LOOK BROKEN. With
	# scale_mode="integer" the canvas is only ever drawn at a WHOLE multiple,
	# and 1920x1080 is 1.5x of the project's 1280x720 - so fullscreen on the
	# most common monitor there is drew the game at 1x in the middle of the
	# display inside a thick black frame. "fractional" is what makes 1.5x a
	# real scale.
	check("the canvas scales fractionally, so 1.5x is a real size",
		str(ProjectSettings.get_setting("display/window/stretch/scale_mode", "")) == "fractional",
		ProjectSettings.get_setting("display/window/stretch/scale_mode", ""))
	# AND THE ASPECT IS PINNED. "keep" is what holds the viewport at exactly
	# 1280x720 game units whatever the window is, which is what every offset in
	# every .tscn in this project was placed against. "expand" would hand a
	# wider monitor a wider viewport, and every hand-placed HUD element would
	# land somewhere else.
	check("and the aspect is kept, so every .tscn offset still lands",
		str(ProjectSettings.get_setting("display/window/stretch/aspect", "")) == "keep",
		ProjectSettings.get_setting("display/window/stretch/aspect", ""))

	# EVERY OFFERED SIZE IS THE VIEWPORT'S OWN SHAPE. With the aspect kept, a
	# window of any other shape gets black bars - so a size in this list that
	# is not 16:9 is a size that cannot fill its own window.
	var base_w: float = float(ProjectSettings.get_setting(
		"display/window/size/viewport_width", 1280))
	var base_h: float = float(ProjectSettings.get_setting(
		"display/window/size/viewport_height", 720))
	var wrong_shape: Array = []
	for option in Settings.WINDOW_SIZES:
		if not is_equal_approx(float(option.x) / float(option.y), base_w / base_h):
			wrong_shape.append("%dx%d" % [option.x, option.y])
	check("every window size offered is the viewport's own shape",
		wrong_shape.is_empty(), wrong_shape)
	check("and 1920x1080 is among them now",
		Settings.WINDOW_SIZES.has(Vector2i(1920, 1080)), Settings.WINDOW_SIZES)

	# ---- the camera view setting ----
	check("the camera setting defaults to what the scenes were authored at",
		is_equal_approx(float(Settings.DEFAULTS["camera_zoom"]), 3.0),
		Settings.DEFAULTS.get("camera_zoom"))
	check("and 3.0 is the ceiling",
		is_equal_approx(Settings.CAMERA_ZOOM_MAX, 3.0), Settings.CAMERA_ZOOM_MAX)
	# A HAND-EDITED options.cfg MUST NOT BE ABLE TO BREAK THE VIEW.
	check("a silly number out of the file is clamped, not obeyed",
		is_equal_approx(float(Settings._normalise("camera_zoom", 40.0)),
			Settings.CAMERA_ZOOM_MAX),
		Settings._normalise("camera_zoom", 40.0))
	check("and so is one below the floor",
		is_equal_approx(float(Settings._normalise("camera_zoom", -5.0)),
			Settings.CAMERA_ZOOM_MIN))
	# THE FLOOR IS 1.0 AGAIN (0.95.0; it was 2.0). The owner, of the big maps:
	# "all the way out". Below 1x the sleeper's hidden monsters would be on
	# screen - testrunner_2's sleeper check holds that.
	check("the camera goes out as far as 1x, and no further",
		is_equal_approx(Settings.CAMERA_ZOOM_MIN, 1.0), Settings.CAMERA_ZOOM_MIN)

	var probe := Camera2D.new()
	probe.zoom = Vector2(3.0, 3.0)
	# A LEGAL SETTING, WHICH 1.5 HAS NOT BEEN SINCE THE FLOOR WENT TO 2.0.
	# This asked for 1.5 and expected 1.5 back, so once the floor was raised the
	# clamp did its job, handed back 2.0, and the test called correct behaviour a
	# failure - two red lines that mean "the constant above me changed", which is
	# the check three lines up already saying it louder.
	#
	# 2.5 is inside the range AND different from the 3.0 the probe starts at, so
	# a write that never happens still fails this the way it always should have.
	const LEGAL_ZOOM := 2.5
	Settings._apply_camera_zoom_to(probe, LEGAL_ZOOM)
	check("the setting reaches a camera",
		is_equal_approx(probe.zoom.x, LEGAL_ZOOM), probe.zoom)
	check("on both axes", is_equal_approx(probe.zoom.y, LEGAL_ZOOM), probe.zoom)
	Settings._apply_camera_zoom_to(probe, 99.0)
	check("and cannot push one past the ceiling",
		is_equal_approx(probe.zoom.x, Settings.CAMERA_ZOOM_MAX), probe.zoom)
	probe.free()

	# ---- the options screen carries the control ----
	var opts: Node = (load("res://scene/ui/menus/optionsscreen.tscn") as PackedScene).instantiate()
	var no_control: Array = []
	for unique in ["camerazoom", "camerazoomvalue"]:
		if opts.get_node_or_null("%" + unique) == null:
			no_control.append(unique)
	check("the options screen has the camera slider", no_control.is_empty(), no_control)
	var no_colour: Array = []
	for unique in ["namehue", "namecolourswatch", "namecolourpreview"]:
		if opts.get_node_or_null("%" + unique) == null:
			no_colour.append(unique)
	check("and the name colour slider", no_colour.is_empty(), no_colour)
	var slider: Range = opts.get_node_or_null("%camerazoom") as Range
	check("whose range matches the setting's own",
		slider != null and is_equal_approx(slider.min_value, Settings.CAMERA_ZOOM_MIN)
			and is_equal_approx(slider.max_value, Settings.CAMERA_ZOOM_MAX),
		"%s..%s" % [str(slider.min_value) if slider else "?", str(slider.max_value) if slider else "?"])
	var hue_slider: Range = opts.get_node_or_null("%namehue") as Range
	check("whose range is the whole hue wheel",
		hue_slider != null and is_equal_approx(hue_slider.min_value, Settings.NAME_HUE_MIN)
			and is_equal_approx(hue_slider.max_value, Settings.NAME_HUE_MAX))
	opts.free()

	# ---- the name colour ----
	# EVERY POSITION ON THE SLIDER HAS TO BE READABLE. Saturation and value are
	# fixed for exactly that reason, so the check is that they really are fixed
	# and that the wheel wraps rather than clamping at its ends.
	var dull: Array = []
	var hue: float = 0.0
	while hue < 360.0:
		var painted: Color = Settings.name_colour(hue)
		if not is_equal_approx(painted.v, Settings.NAME_VALUE):
			dull.append("hue %d is value %.2f" % [int(hue), painted.v])
		elif not is_equal_approx(painted.s, Settings.NAME_SATURATION):
			dull.append("hue %d is saturation %.2f" % [int(hue), painted.s])
		hue += 15.0
	check("every hue comes out at the one readable saturation", dull.is_empty(), dull)
	check("the wheel wraps rather than stopping",
		is_equal_approx(float(Settings._normalise("name_hue", 400.0)), 40.0),
		Settings._normalise("name_hue", 400.0))
	check("and wraps backwards too",
		is_equal_approx(float(Settings._normalise("name_hue", -20.0)), 340.0),
		Settings._normalise("name_hue", -20.0))
	check("the default hue is near the parchment the names already were",
		Settings.name_colour(float(Settings.DEFAULTS["name_hue"])).r > 0.9,
		Settings.name_colour(float(Settings.DEFAULTS["name_hue"])))

	# ---- colour is yours, rank is a badge ----
	# THIS SECTION USED TO SAY THE OPPOSITE: "staff keep their rank colour
	# whatever the slider says". While rank was a colour that was the only way
	# to keep it true, and the price was an Options slider that silently did
	# nothing for staff - which is how it was reported. Rank is worn ABOVE the
	# name now (the crown, or MOD / DEV), so the colour is free for everybody,
	# and what has to stay true is the badge, which only the server's rank sets.
	var body: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	# THE PLATE WITHOUT THE PLAYER. Adding a warrior to the tree runs all of
	# player.gd's _ready() - camera, pets, the save - for a check about a label.
	body._setup_nameplate()
	check("this client's own name is the colour its player chose",
		body._nameplate_colour() == Settings.name_colour(), body._nameplate_colour())
	check("a body told about somebody else is drawn in THEIR colour, not ours",
		body._nameplate_colour(300) == NameTag.colour(300)
		and NameTag.colour(300) != NameTag.colour(20))
	var plate: Label = body.get("_nameplate")
	var crown_node: TextureRect = body.get("_nameplate_crown")
	var badge_node: Label = body.get("_nameplate_badge")
	check("the plate, its crown and its badge are built", plate != null and crown_node != null and badge_node != null)
	if plate != null and crown_node != null and badge_node != null:
		var worn: Dictionary = {}
		for staff_rank in ["player", "mod", "dev", "owner"]:
			body.set_nameplate("somebody", staff_rank)
			worn[staff_rank] = [
				plate.get_theme_color("font_color") == Settings.name_colour(),
				crown_node.visible, badge_node.visible, badge_node.text,
				badge_node.get_theme_color("font_color") == Api.colour_for_role(staff_rank)]
		check("staff choose their colour like anybody - the slider is not ignored for them",
			worn["mod"][0] and worn["dev"][0] and worn["owner"][0] and worn["player"][0], worn)
		check("the owner wears the crown and nothing else",
			worn["owner"][1] and not worn["owner"][2], worn["owner"])
		check("a mod wears MOD, in the mod colour", not worn["mod"][1] and worn["mod"][2]
			and worn["mod"][3] == "MOD" and worn["mod"][4], worn["mod"])
		check("a dev wears DEV, in the dev colour", worn["dev"][2] and worn["dev"][3] == "DEV"
			and worn["dev"][4], worn["dev"])
		check("a player wears nothing - which is what makes the other three stand out",
			not worn["player"][1] and not worn["player"][2], worn["player"])
		# THE TAG SURVIVES A NEW COLOUR. Picking a colour repainted the plate
		# through set_nameplate() with no tag, and the tag vanished until the
		# next broadcast poll put it back.
		# SIGNED IN AS SOMEBODY, whoever this machine last signed in as. The
		# repaint reads Api.username, and a machine whose last session was
		# logged out has none - which blanked the plate and failed this check
		# on a clean state rather than on a defect.
		var was_user: String = Api.username
		Api.username = "somebody"
		body.set_nameplate("somebody", "player", "LIFERS")
		body._on_setting_changed("name_hue", 0.0)
		check("picking a new colour keeps the guild tag on the plate",
			plate.text.contains("[LIFERS]"), plate.text)
		body._on_identity_changed("somebody", "mod")
		check("and so does a rank change", plate.text.contains("[LIFERS]"), plate.text)
		Api.username = was_user

	# ---- and the plate sits on the head, not above it ----
	# ONE NUMBER FOR FOUR CLASSES WAS THE BUG. The warrior's head is at -17 and
	# the mage's at -41; a shared -42 floated the warrior's name 25px of empty
	# air clear of them, which at 3x zoom is 75 screen pixels.
	var heads: Dictionary = body.NAMEPLATE_HEAD_Y
	check("every class has a measured head height",
		heads.has("warrior") and heads.has("mage") and heads.has("healer")
			and heads.has("tank"), heads)
	var same: bool = (float(heads["warrior"]) == float(heads["mage"]))
	check("and they are not all the same number", not same, heads)

	# ---- the crown ----
	# ONE ACCOUNT WEARS IT. The rank it keys off is the server's, copied into
	# the chat row by app.py and read out of /api/friends - not the name colour
	# beside it, which each player chooses.
	var crown_file: String = body.NAMEPLATE_CROWN_PATH
	check("the crown art ships with the game", ResourceLoader.exists(crown_file),
		crown_file)
	var crown_art: Texture2D = load(crown_file) as Texture2D
	check("and loads as a texture", crown_art != null)
	check("at the size the chat tag and the plate both assume",
		crown_art != null and crown_art.get_width() == 26 and crown_art.get_height() == 15,
		str(crown_art.get_size()) if crown_art else "none")
	check("only the owner wears it", body.NAMEPLATE_CROWN_RANK == "owner",
		body.NAMEPLATE_CROWN_RANK)
	check("the nameplate and every list agree on the art and on who wears it",
		NameTag.CROWN_PATH == crown_file and NameTag.CROWN_RANK == body.NAMEPLATE_CROWN_RANK
		and NameTag.CROWN_SIZE == Vector2(26, 15))

	# ONE FUNCTION DRAWS A NAME IN EVERY LIST. The crown used to be a constant
	# in chat, another in the friends list and a third over the head - three
	# chances for one to point at nothing, and a missing [img] fails silently.
	for path in ["res://src/ui/chat/chatpanel.gd", "res://src/ui/friends/friendspanel.gd",
			"res://src/ui/players/playerspanel.gd", "res://src/ui/guild/guildpanel.gd"]:
		var body_src: String = _code_only(FileAccess.get_file_as_string(path))
		check("%s draws names through nametag.gd" % path.get_file(),
			body_src.contains('preload("res://src/shared/nametag.gd")')
			and body_src.contains("NameTag."), path)
		check("%s no longer paints a name by rank" % path.get_file(),
			not body_src.contains("colour_for_role("), path)

	# AND IT IS ACTUALLY DRAWN, not merely named. Built into a real row.
	var row := HBoxContainer.new()
	var drawn: Label = NameTag.add_to(row, "boss", "owner", 200)
	var crowns: Array = row.find_children("*", "TextureRect", true, false)
	check("an owner's row carries the crown, before the name",
		crowns.size() == 1 and (crowns[0] as TextureRect).texture != null
		and row.get_child(0) == crowns[0] and row.get_child(1) == drawn)
	check("and the name is in the owner's own colour, not a rank colour",
		drawn.get_theme_color("font_color") == NameTag.colour(200))
	row.free()
	row = HBoxContainer.new()
	drawn = NameTag.add_to(row, "helper", "mod", null)
	var mod_badge: Label = row.get_node_or_null("badge") as Label
	check("a mod's row carries MOD in the mod colour",
		mod_badge != null and mod_badge.text == "MOD"
		and mod_badge.get_theme_color("font_color") == Api.colour_for_role("mod"))
	check("and somebody who never chose a colour is drawn in the default one",
		drawn.get_theme_color("font_color") == Settings.name_colour(float(Settings.DEFAULTS["name_hue"])))
	row.free()
	check("chat's crown is the same art at the same size",
		NameTag.bbcode("boss", "owner", 10).begins_with("[img=26x15]%s[/img]" % crown_file),
		NameTag.bbcode("boss", "owner", 10))
	check("chat's badge is a word in the rank colour, then the name in theirs",
		NameTag.bbcode("helper", "dev", 10).contains("DEV")
		and NameTag.bbcode("helper", "dev", 10).contains(Api.colour_for_role("dev").to_html(false))
		and NameTag.bbcode("helper", "dev", 10).contains(NameTag.colour(10).to_html(false)))
	check("a hue off the wire that is not on the wheel is drawn as the default, not trusted",
		NameTag.colour(999) == NameTag.colour(null) and NameTag.colour("red") == NameTag.colour(null))

	# ---- the colour travels ----
	# THE SERVER HOLDS IT NOW (users.name_hue), so the slider's colour is what
	# everybody else sees too. Checked without writing the player's own
	# options file: the suite never moves anybody's settings.
	var here: int = wrapi(int(round(float(Settings.get_value("name_hue")))), 0, 360)
	var was_synced: Variant = Api.get("_synced_name_hue")
	Api.adopt_name_hue({"name_hue": here})
	check("after a login the server's hue is the one held, so nothing echoes back up",
		Api.name_hue_to_push() == -1, Api.name_hue_to_push())
	Api.set("_synced_name_hue", (here + 5) % 360)
	check("and a hue the server does not hold yet is pushed", Api.name_hue_to_push() == here,
		Api.name_hue_to_push())
	Api.set("_synced_name_hue", was_synced)
	var api_src: String = _code_only(FileAccess.get_file_as_string("res://src/systems/api.gd"))
	var fn := func(fn_name: String) -> Array:
		var at: int = _first_code_index(api_src, "func %s(" % fn_name, 0)
		return [at, _first_code_index(api_src, "\nfunc ", at + 1)]
	var span: Array = fn.call("adopt_name_hue")
	check("the server's colour wins at login: it is written into Settings",
		_within(_first_code_index(api_src, 'Settings.set_value("name_hue"', span[0]), span[1]) != -1)
	span = fn.call("push_name_hue_soon")
	check("and the slider's colour is sent to the server",
		_within(_first_code_index(api_src, 'put("/api/account/name-colour"', span[0]), span[1]) != -1)
	span = fn.call("_adopt_session")
	check("a login adopts it", _within(_first_code_index(api_src, "adopt_name_hue(", span[0]), span[1]) != -1)
	span = fn.call("probe_and_resume")
	check("and so does resuming a saved session",
		_within(_first_code_index(api_src, "adopt_name_hue(", span[0]), span[1]) != -1)
	body.free()

	# ---- the heartbeat: only a 401 signs anyone out ----
	check("a live session beats ok", Api.heartbeat_verdict({"ok": true, "status": 200}) == "ok")
	check("a 401 is a kick, a ban or an expiry", Api.heartbeat_verdict({"ok": false, "status": 401}) == "revoked")
	# A SERVER RESTART MUST NOT BE A MASS KICK.
	for status in [0, 404, 500, 503]:
		check("HTTP %d signs nobody out" % status,
			Api.heartbeat_verdict({"ok": false, "status": status}) == "offline")
	# THE BEAT IS THE BROADCAST POLL, AND THIS CHECK USED TO NAME THE WRONG
	# CONSTANT.
	#
	# It asserted HEARTBEAT_SECONDS * 3 <= 45 and passed for months while the
	# thing it describes was not happening: Api.heartbeat() is called from
	# exactly one place in this project - the 401 handler - and nothing fires
	# it on a timer. So the arithmetic was sound and about a request nobody
	# made, and sessions.last_seen_at was stamped once at login and never
	# again. Forty-five seconds later the friends list, the guild roster and
	# the players menu all read the player as offline. It showed up in game as
	# a guild panel saying "0 online of 1" to the only member, who was reading
	# it at the time.
	#
	# The stamp rides the broadcast poll now (app.py, stamp_presence), so THIS
	# is the interval that has to fit inside the window - and it is the one a
	# timer actually drives.
	var beat: float = load("res://src/ui/characterhud.gd").BROADCAST_POLL_SECONDS
	check("three beats fit inside the server's 45 s online window",
		beat * 3.0 <= 45.0, beat)
	# READ FRESH, because `hud_src` is not in scope here and reaching for a
	# variable from another section is how a check ends up measuring whichever
	# file happened to be loaded last.
	var hud_text: String = FileAccess.get_file_as_string(
		"res://src/ui/characterhud.gd")
	check("and the beat is the poll a timer really runs",
		hud_text.contains("timer.wait_time = BROADCAST_POLL_SECONDS"),
		"a constant nothing schedules is a comment with a number in it")

	# ---- what a banned player is told ----
	var login_script: Script = require_script(
		"res://src/ui/menus/loginmenu.gd", "the login menu")
	if login_script == null:
		return
	var told: String = login_script.describe_login_refusal({"status": 403,
		"data": {"message": "This account is banned.", "ban": {"permanent": true, "reason": "cheating"}}})
	check("a permanent ban says so, and why", told.contains("permanently") and told.contains("cheating"), told)
	told = login_script.describe_login_refusal({"status": 403,
		"data": {"ban": {"permanent": false, "expires_at": 1_900_000_000, "reason": ""}}})
	check("a timed ban gives its date", told.begins_with("This account is banned until 20"), told)
	told = login_script.describe_login_refusal({"status": 500, "error": "Server error."})
	check("anything else passes the error through", told == "Server error.", told)


func _test_collision_contract() -> void:
	section("COLLISION CONTRACT — can each projectile see what it damages?")

	# EVERY NUMBER BELOW IS A BIT POSITION, and bit positions mean nothing on
	# their own. Reordering the layer list in Project Settings renames the bits
	# without touching a single scene, so every mask in the project would keep
	# its value and quietly change its meaning. Check the names first, so a
	# reorder fails here rather than in combat.
	_check_layer_name(3, "player")
	_check_layer_name(4, "enemies")
	_check_layer_name(6, "playerprojectile")
	_check_layer_name(7, "enemyprojectile")

	for path in PLAYER_PROJECTILE_SCENES:
		_check_projectile(path, LAYER_PLAYERPROJECTILE, "playerprojectile",
			LAYER_ENEMIES, "enemies")

	for path in ENEMY_PROJECTILE_SCENES:
		_check_projectile(path, LAYER_ENEMYPROJECTILE, "enemyprojectile",
			LAYER_PLAYER, "player")


# =============================================================================
# REACH — does every pet's shot get as far as the pet looks?
# =============================================================================
# THE FIRE PET'S MASK, ONE NUMBER OVER. The Electric Sprite pet's orb
# (petmagicprojectile.tscn) carried speed = 20 where every other pet's shot flies
# at 300, and it lives 4 s: about 80 px. The pet picks a target up to 280 px away
# and holds it to 322, so from anywhere but beside its target the orb faded out
# on the way - for as long as the game had the pet. Nothing logged and nothing
# errored; the pet just seemed to keep missing. Found in 0.11.5 by measuring
# every pet against a boss for the website's Boss Sim.
#
# A shot that flies (it has a speed and a lifetime) has to cover the distance its
# pet keeps a target at. One that is put down on the target - the mage's vine,
# the Crowned's rupture - has no distance to cover, and is not asked.
func _test_pet_shots_reach() -> void:
	section("REACH — does every pet's shot get as far as the pet looks?")
	var folder := "res://scene/pets/"
	var flying := 0
	for file in DirAccess.get_files_at(folder):
		if not file.ends_with(".tscn"):
			continue
		var pet: Node = (load(folder + file) as PackedScene).instantiate()
		var scene: PackedScene = pet.get("projectile_scene") as PackedScene
		var holds: float = float(pet.get("aggro_range")) * Pet.TARGET_KEEP_SLACK
		if scene != null:
			var shot: Node = scene.instantiate()
			if "speed" in shot and "lifetime" in shot:
				flying += 1
				var reach: float = float(shot.get("speed")) * float(shot.get("lifetime"))
				check("%s: its shot flies %d px, past the %d px it keeps a target at" % [
					file.get_basename(), int(reach), int(holds)], reach >= holds,
					"%s: speed %s x lifetime %s" % [scene.resource_path.get_file(), shot.get("speed"), shot.get("lifetime")])
			shot.free()
		pet.free()
	check("  five pets fire a shot that flies, and all five were measured", flying == 5, flying)


func _test_only_levelling_up_refills() -> void:
	section("REFILLING - only levelling up fills all three pools")

	var player_src: String = FileAccess.get_file_as_string(
		"res://src/characters/player.gd")
	check("player.gd is readable", player_src != "")
	if player_src == "":
		return
	var code: String = _code_only(player_src)

	# COUNTED IN CODE, AND THE DEFINITION DOES NOT COUNT AS A CALL. `func
	# _fill_all_resources() -> void:` contains the string, which is the exact
	# mistake `hud.count("_note_server_contact()")` made - the definition
	# counting itself, and removing a real call still leaving the total right.
	var call_sites: int = code.count("_fill_all_resources()") \
		- code.count("func _fill_all_resources()")
	check("_fill_all_resources() has exactly one call site", call_sites == 1,
		"%d found - every one of them is a free full heal" % call_sites)

	# AND IT IS INSIDE level_up(). A count alone passes on one call in the wrong
	# function, which is precisely the state this section exists to forbid.
	var level_up_at: int = _first_code_index(code, "func level_up(", 0)
	var next_func_at: int = _first_code_index(code, "\nfunc ", level_up_at + 1)
	check("level_up() exists", level_up_at != -1)
	# SEARCHED FROM level_up(), NOT FROM ZERO. From zero the first hit is
	# `func _fill_all_resources() -> void:` - the definition, hundreds of lines
	# earlier - and the check went red on correct code the first time it ran.
	# The definition-counts-as-a-call trap, twice in one section.
	var fill_at: int = _first_code_index(code, "_fill_all_resources()", level_up_at)
	check("and the one call site is inside it",
		level_up_at != -1 and _within(fill_at, next_func_at) != -1,
		"call at %d, level_up() spans %d..%d" % [fill_at, level_up_at, next_func_at])

	# THE SETTER. It must still recompute the maxima - that is what it is for,
	# and the Remote Inspector case its comment describes depends on it - and it
	# must not touch the pools.
	var setter_at: int = _first_code_index(code, "var level: int = 1:", 0)
	var xp_at: int = _first_code_index(code, "var xp: int = 0", 0)
	check("the level setter is where it was", setter_at != -1)
	var setter_body: String = code.substr(setter_at, maxi(xp_at - setter_at, 0)) \
		if setter_at != -1 and xp_at > setter_at else ""
	check("the level setter still recomputes the maxima",
		setter_body.contains("_recompute_max_stats()"))
	check("THE LEVEL SETTER DOES NOT REFILL THE POOLS",
		not setter_body.contains("_fill_all_resources()"),
		"load_character_state() assigns `level` first, so this fires on every load")

	# _ready() RESTORES, IT DOES NOT FILL. The long comment in _ready() explains
	# why at length; this is the machine-readable half of it.
	var ready_at: int = _first_code_index(code, "func _ready() -> void:", 0)
	var after_ready: int = _first_code_index(code, "\nfunc ", ready_at + 1)
	check("_ready() exists", ready_at != -1)
	check("_ready() does not fill the pools",
		_within(_first_code_index(code, "_fill_all_resources()", ready_at),
			after_ready) == -1)

	# THE THREE CONDITIONALS, BY POSITION. was_full_* has to be measured against
	# the SAVED maxima, so it must come before _recompute_max_stats() replaces
	# them, and the assignments must come after.
	var was_full_at: int = _first_code_index(code, "var was_full_hp:", ready_at)
	var recompute_at: int = _first_code_index(code, "_recompute_max_stats()", ready_at)
	var assign_at: int = _first_code_index(code, "hp = max_hp if was_full_hp", ready_at)
	check("fullness is measured before the maxima are recomputed",
		was_full_at != -1 and recompute_at != -1 and was_full_at < recompute_at,
		"measuring after would compare the saved hp against the NEW maximum")
	check("and the restore happens after",
		assign_at != -1 and recompute_at < assign_at)
	for vital in ["mana = max_mana if", "stamina = max_stamina if"]:
		check("%s... is conditional too" % vital.split(" ")[0],
			_within(_first_code_index(code, vital, ready_at), after_ready) != -1)

	# THE OTHER HALF OF THE OLD ACCIDENT, asserted so it cannot rot into being
	# load-bearing again: the save really does carry all six, so the conditional
	# restore above has real numbers to work with.
	var saveable: Dictionary = CharacterData.SAVEABLE_STATS
	for key in ["hp", "max_hp", "mana", "max_mana", "stamina", "max_stamina", "level"]:
		check("SAVEABLE_STATS carries %s" % key, saveable.has(key))

	print("  %d call site(s) for _fill_all_resources(), setter clean" % call_sites)


# =============================================================================
# THE SMITH: AN ANVIL IN TOWN, TEMPERING, THE ROYAL CERTIFICATION (0.74.0)
# =============================================================================
# The owner: "a new smith spends materials plus gold to upgrade gear", and
# "Upgrades that cost materials instead of only gold, plus a 'Royal
# Certification' step to reach higher tiers ... the certification fits the
# kingdom theme".
#
# Four sections. The anvil as a thing in the world - placed by the shop, solid,
# reachable from where players arrive, clear of every door - and as a station
# that opens the smith window on one press, at the nearest anvil only. The
# window's Temper tab against a stand-in server that keeps the SPEC's rules,
# and its Royal Certification tab the same way. And patronage on the kingdom
# board: the Donate control, and the titles it buys.
#
# STAND-IN GEAR AND MATERIALS, and a stand-in price list handed to the stand-in
# server, so these run in a clone without the private art pack (every real ore
# and essence draws its icon from it, and without the pack they do not load) -
# the cooking section's reason for its stand-in fish.

func _test_the_anvil_stands_by_the_shop() -> void:
	section("THE ANVIL - by the shop, solid, at 1x, reached from where players arrive, clear of every door (0.74.0)")
	var packed: PackedScene = load("res://scene/interactables/anvil.tscn") as PackedScene
	check("anvil.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate():
		return
	var anvil: Area2D = packed.instantiate() as Area2D
	check("its root is the anvil script on an Area2D",
		anvil != null and anvil.get_script() != null
		and (anvil.get_script() as Script).resource_path == "res://src/world/anvil.gd")
	var sprite: AnimatedSprite2D = anvil.get_node_or_null("animatedsprite2d") as AnimatedSprite2D
	var art: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, 0) \
		if sprite != null and sprite.sprite_frames != null else null
	check_needs_pack("its picture is the pack's anvil, art/pack/smith/anvil.png",
		art != null and art.resource_path == "res://art/pack/smith/anvil.png", art.resource_path if art != null else "")
	check_needs_pack("  a 16 px cell drawn at 1x - the world's own tile size",
		art != null and art.get_size() == Vector2(16, 16) and sprite.scale == Vector2.ONE
		and anvil.scale == Vector2.ONE, [art.get_size() if art != null else Vector2.ZERO, sprite.scale if sprite != null else Vector2.ZERO])
	check("  drawn nearest-neighbour, like every pixel in the world",
		sprite != null and sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)

	# THE STATION'S REACH: an interact ring on the root, as the firepit has.
	var reach: CollisionShape2D = anvil.get_node_or_null("collisionshape2d") as CollisionShape2D
	check("it has a reach to stand in, on the root", reach != null and reach.shape is CircleShape2D)
	check("  and it notices the player and nothing else",
		(anvil.collision_mask & LAYER_PLAYER) != 0 and anvil.collision_mask == LAYER_PLAYER, anvil.collision_mask)

	# SOLID, the firepit's rules (see SOLID PROPS above): a body on a layer the
	# player collides with, which the anvil's own reach cannot see, unscaled,
	# covering where the art meets the ground, and actually stopping a walker.
	var player_layer: int = int(_scene_root_prop("res://scene/characters/warrior.tscn", "collision_layer", 0))
	var player_mask: int = int(_scene_root_prop("res://scene/characters/warrior.tscn", "collision_mask", 0))
	var body: StaticBody2D = anvil.get_node_or_null("body") as StaticBody2D
	var foot: CollisionShape2D = body.get_node_or_null("collision") as CollisionShape2D if body != null else null
	check("it has a solid body with a shape", foot != null and foot.shape is RectangleShape2D)
	if foot == null:
		anvil.free()
		return
	check("  on a layer the player collides with", (body.collision_layer & player_mask) != 0,
		[body.collision_layer, player_mask])
	check("  that its own reach cannot see", (body.collision_layer & anvil.collision_mask) == 0)
	check("  sized, not scaled", body.scale == Vector2.ONE and foot.scale == Vector2.ONE)
	var aim: float = _art_ground_y(anvil)
	check_needs_pack("  its footprint covers where its art meets the ground", _shape_covers(foot, aim),
		"art ground at y=%.1f, shape at y=%.1f" % [aim, foot.position.y])
	# DRIVEN AT THE ART, NOT AT THE SHAPE - the SOLID PROPS section's lesson: a
	# walker aimed at the shape finds it wherever it has been moved to. Without
	# the pack there is no art to read, and the shape is all there is to aim at.
	var drive_y: float = aim if art != null else foot.position.y
	var blocked: float = await _walk_into(anvil, player_layer, player_mask, drive_y)
	foot.disabled = true
	var through: float = await _walk_into(anvil, player_layer, player_mask, drive_y)
	foot.disabled = false
	check("  it stops a body walking into it, which goes straight through with the shape off",
		blocked < 0.0 and through > 20.0, [blocked, through])
	check("the map pins it as the smith, and the map can draw that pin",
		str(anvil.map_landmark().get("kind", "")) == "smith"
		and (load("res://src/ui/menus/mapscreen.gd") as Script).get_script_constant_map()["LANDMARK_STYLE"].has("smith"))
	anvil.free()

	# ---- IN THE TOWN ------------------------------------------------------------------
	var town: Node = (load("res://scene/elusion.tscn") as PackedScene).instantiate()
	var found: Array = []
	_collect_by_script(town, "res://src/world/anvil.gd", found)
	check("the town has one anvil", found.size() == 1, found.size())
	if found.size() != 1:
		town.free()
		return
	var placed: Node2D = found[0]
	var at: Vector2 = _area_xform(placed, town).origin
	var shop: Node = town.get_node_or_null("ysortworld/interactables/shophouse")
	var shop_door: Node = shop.get_node_or_null("shopexterior/door") if shop != null else null
	var door_at: Vector2 = _area_xform(shop_door, town).origin if shop_door is Node2D else Vector2.INF
	check("  by the shop - within twelve tiles of its door", at.distance_to(door_at) < 192.0,
		"%s from the door at %s" % [at, door_at])
	# THE SHOP'S ROOF LIFTS FOR ANYBODY INSIDE ITS TRIGGER, which reaches well
	# past the walls. Standing at the anvil - anywhere its reach can see your
	# feet - must not show the shop's insides.
	var roof: Node = shop.get_node_or_null("trigger") if shop != null else null
	var roof_rects: Array = _door_rects(roof, town) if roof != null else []
	var reach_node: CollisionShape2D = placed.get_node("collisionshape2d") as CollisionShape2D
	var reach_rect: Rect2 = (_area_xform(reach_node, town) * reach_node.shape.get_rect()).grow(7.0)
	check("  and using it never lifts the shop's roof", not roof_rects.is_empty()
		and roof_rects.filter(func(r: Rect2) -> bool: return r.intersects(reach_rect)).is_empty(), [reach_rect, roof_rects])
	var door_rects: Array = []
	for script_path in DOOR_SCRIPTS:
		var doors: Array = []
		_collect_by_script(town, script_path, doors)
		for door in doors:
			door_rects.append_array(_door_rects(door, town))
	var body_rect: Rect2 = _area_xform(placed.get_node("body/collision"), town) \
		* (placed.get_node("body/collision") as CollisionShape2D).shape.get_rect()
	var in_a_door: Array = door_rects.filter(func(r: Rect2) -> bool: return r.grow(16.0).intersects(body_rect))
	check("  and a tile clear of the shop's door and every way out of town", in_a_door.is_empty(), in_a_door)
	var spawn: Node = town.get_node_or_null("playerspawn")
	check("  nowhere near where players arrive",
		spawn is Node2D and at.distance_to(_area_xform(spawn, town).origin) > 96.0, at)

	# REACHED FROM WHERE PLAYERS ARRIVE. The doors walk (AREAS) floods the town
	# from every arrival with the warrior's own feet; a stand-in door laid over
	# the anvil's reach asks that same flood whether a player can get there. A
	# ladder with somewhere to go is a door to it - and nothing here enters the
	# tree, so the stand-in never runs.
	var stand_in := Area2D.new()
	stand_in.name = "anvilreach"
	stand_in.set_script(load("res://src/world/ladder.gd"))
	stand_in.set("destination_scene_path", "res://scene/elusion.tscn")
	var ring := CollisionShape2D.new()
	var square := RectangleShape2D.new()
	square.size = Vector2(44, 40)
	ring.shape = square
	ring.position = Vector2(0, -4)
	stand_in.add_child(ring)
	placed.add_child(stand_in)
	var warrior: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	var feet_node: CollisionShape2D = warrior.get_node("bodyshape") as CollisionShape2D
	var probe := CharacterBody2D.new()
	probe.collision_layer = 0
	probe.collision_mask = (warrior as CollisionObject2D).collision_mask
	var probe_shape := CollisionShape2D.new()
	probe_shape.shape = feet_node.shape
	probe_shape.position = feet_node.position
	probe.add_child(probe_shape)
	var radius: float = (feet_node.shape as CircleShape2D).radius
	var feet_offset: Vector2 = feet_node.position
	warrior.free()
	var report: Dictionary = await _walk_area(town, probe, feet_offset, radius)
	probe.free()
	town.free()
	check("  a player walks up to it from the town's arrival",
		not report.is_empty() and not (report.unreached as Array).has("anvilreach"), report.get("unreached"))
	check("  and every door the town had is still reached with it there",
		not report.is_empty() and (report.unreached as Array).is_empty(), report.get("unreached"))
	print("  the anvil at %s, by the shop's door" % at)


func _test_the_anvil_opens_the_smith() -> void:
	section("THE ANVIL - interact at the nearest anvil opens the smith window, once a press (0.74.0)")
	var packed: PackedScene = load("res://scene/interactables/anvil.tscn") as PackedScene
	if packed == null:
		check("anvil.tscn loads", false)
		return
	var huds: Array = get_tree().get_nodes_in_group(&"hud")
	for h in huds:
		h.remove_from_group(&"hud")
	var hud := SmithHud.new()
	hud.add_to_group(&"hud")
	add_child(hud)
	var world := Node2D.new()
	add_child(world)
	var walker := CharacterBody2D.new()
	walker.add_to_group("player")
	walker.collision_layer = LAYER_PLAYER
	walker.collision_mask = 0
	var shape := CollisionShape2D.new()
	var feet := CircleShape2D.new()
	feet.radius = 7.0
	shape.shape = feet
	walker.add_child(shape)
	world.add_child(walker)
	walker.global_position = Vector2(0, 600)
	walker.reset_physics_interpolation()

	# THE FARTHER ONE FIRST IN THE TREE, so it is the first to see a press: it
	# is the nearest-anvil rule, and not the order nodes happen to process in,
	# that has to send the press to the other.
	var near: Area2D = packed.instantiate() as Area2D
	var far: Area2D = packed.instantiate() as Area2D
	world.add_child(far)
	world.add_child(near)
	near.global_position = Vector2(0, 0)
	near.reset_physics_interpolation()
	far.global_position = Vector2(36, 0)
	far.reset_physics_interpolation()
	await get_tree().process_frame
	near.spawn_timer = 0.0
	far.spawn_timer = 0.0

	# THE CONTROL: the stand-in HUD really is reached, or every "nothing opened"
	# below would be a stand-in nobody could have called.
	near.player_in_range = walker
	near._open_smith()
	check("the stand-in HUD receives open_smith(), for this anvil and this player",
		hud.opened.size() == 1 and hud.opened[0][0] == near and hud.opened[0][1] == walker, hud.opened)
	near.notify_panel_closed()
	near.player_in_range = null
	hud.opened.clear()

	await _press_interact_a_frame()
	check("a press with nobody at the anvil opens nothing", hud.opened.is_empty(), hud.opened.size())

	# Walked up for real: the reach sees the body, as it will in town.
	walker.global_position = Vector2(14, 12)
	walker.reset_physics_interpolation()
	for i in 20:
		await get_tree().physics_frame
		if near.player_in_range == walker and far.player_in_range == walker:
			break
	check("standing between the two, both anvils see the player",
		near.player_in_range == walker and far.player_in_range == walker)
	await _press_interact_a_frame()
	check("ONE PRESS OPENS ONE WINDOW, AT THE NEAREST ANVIL",
		hud.opened.size() == 1 and hud.opened[0][0] == near, hud.opened)
	await _press_interact_a_frame()
	check("  pressed again with the window up, nothing opens underneath it", hud.opened.size() == 1, hud.opened.size())
	near.notify_panel_closed()
	await _press_interact_a_frame()
	check("  closed with its X and pressed again, it opens again - not a prop stuck open",
		hud.opened.size() == 2, hud.opened.size())

	# TWO ANVILS EXACTLY AS FAR AWAY. Neither is nearer, so both pass that test;
	# the press is claimed by whichever sees it first, and the other stands down.
	near.notify_panel_closed()
	far.global_position = Vector2(28, 0)
	far.reset_physics_interpolation()
	for i in 20:
		await get_tree().physics_frame
		if far.player_in_range == walker:
			break
	hud.opened.clear()
	await _press_interact_a_frame()
	check("  two anvils at the same distance: one press, one window", hud.opened.size() == 1, hud.opened)
	near.notify_panel_closed()
	far.notify_panel_closed()
	# The window up at the near anvil again, for the walk away.
	near._open_smith()

	var left: Array = []
	near.player_left_range.connect(func() -> void: left.append(true))
	walker.global_position = Vector2(0, 600)
	walker.reset_physics_interpolation()
	for i in 20:
		await get_tree().physics_frame
		if near.player_in_range == null:
			break
	check("walking off with the window up tells the window to go", left.size() == 1 and not near._is_open, left.size())
	far.player_in_range = null

	world.queue_free()
	hud.queue_free()
	for h in huds:
		if is_instance_valid(h):
			h.add_to_group(&"hud")
	await get_tree().process_frame

	# The HUD's own half: the window built on first use, pointed at the anvil.
	var hud_src: String = _code_src("res://src/ui/characterhud.gd")
	check("the HUD builds the smith window on first use and points it at the anvil",
		_func_body(hud_src, "func open_smith(").contains("SMITH_PANEL_SCENE.instantiate()")
		and _func_body(hud_src, "func open_smith(").contains("open_for_anvil(anvil, player)"))
	check("  and closes it on Escape, with its own x", _func_body(hud_src, "func _escape_windows(").contains("[smith_panel, \"close_panel\"]"))


func _test_the_smith_tempers() -> void:
	section("THE SMITH - Temper: the piece, now and after, the cost with have / need, the gate, the bag after (0.74.0)")
	_smith_stand_ins()
	var server := SmithServer.new()
	add_child(server)
	if not server.start():
		check("a free local port for the suite's smith", false)
		server.queue_free()
		_smith_forget_stand_ins()
		return
	server.costs = SMITH_TEST_COSTS
	server.certs = SMITH_TEST_CERTS
	server.purse = 18450
	server.level = 12
	var cells: Array = []
	cells.resize(30)
	cells[0] = {"item_id": "zz_smith_blade~d104", "quantity": 1}
	cells[1] = {"item_id": "zz_smith_ore", "quantity": 5}
	cells[3] = {"item_id": "zz_smith_plate~a113h96", "quantity": 1}
	cells[4] = {"item_id": "zz_smith_blade~d120", "quantity": 1}
	cells[6] = {"item_id": "zz_smith_blade~d115", "quantity": 1}
	cells[7] = {"item_id": "zz_smith_bone", "quantity": 2}
	cells[8] = {"item_id": "zz_smith_essence", "quantity": 4}
	cells[22] = {"item_id": "zz_smith_blade", "quantity": 1}
	server.bag = cells
	var kept_url: String = ApiForTests.BASE_URL
	var kept_token: String = Api.token
	var kept_online: bool = Api.server_online
	var kept_known: bool = Api.reachability_known
	ApiForTests.BASE_URL = "http://127.0.0.1:%d" % server.port
	Api.token = "suite"
	var stage: Dictionary = _smith_stage(server)
	var window: Control = stage.window
	var bag: Node = stage.bag
	var player: SmithPlayer = stage.player
	var anvil: Area2D = (load("res://scene/interactables/anvil.tscn") as PackedScene).instantiate() as Area2D
	add_child(anvil)
	await get_tree().process_frame

	await window.open_for_anvil(anvil, player)
	check("opening reads the smith's status for this character",
		server.asked == ["GET /api/smith/status"], server.asked)
	check("  the window shows, sized from what is in it, inside the screen",
		window.visible and window.size.x >= 300.0
		and Rect2(Vector2.ZERO, window.get_viewport_rect().size).encloses(window.get_global_rect()), window.get_global_rect())

	# ---- THE GEAR ------------------------------------------------------------------
	var listed: Array = (window.get("_gear") as Array).map(func(g: Dictionary) -> int: return int(g["cell"]))
	check("the bag's weapons and armour are listed, the hotbar's keys too, in bag order - no ore, no bone",
		listed == [0, 3, 4, 6, 22], listed)
	var grid: Node = window.get_node("%geargrid")
	var first: InventorySlot = (grid.get("slots") as Array)[0]
	check("  as views: a slot of the grid cannot be dragged out of", first.slot_type == "lootbag", first.slot_type)

	# ---- A PIECE ON THE ANVIL ------------------------------------------------------
	server.clear()
	await window.choose_cell(0)
	check("picking the blade asks for a quote naming its cell and the piece in it",
		server.asked == ["POST /api/smith/quote"] and int(server.bodies[-1].get("position", -1)) == 0
		and str(server.bodies[-1].get("item_id", "")) == "zz_smith_blade~d104"
		and int(server.bodies[-1].get("slot", -9)) == CharacterData.active_character_index, [server.asked, server.bodies.back()])
	var stats: PackedStringArray = _texts_under(window.get_node("%statgrid"))
	check("  each stat now and after: 104 (104%) and, tempered by three points, 107 (107%)",
		stats.has("104 (104%)") and stats.has("107 (107%)"), stats)
	var costs: PackedStringArray = _texts_under(window.get_node("%costgrid"))
	check("  the cost: the gold against the purse, and each material have / need",
		costs.has("Gold") and costs.has("18,450 / 50") and costs.has("Test Ore") and costs.has("5 / 3"), costs)
	var temper_button: Button = window.get_node("%temperbutton")
	check("  a tier anybody may temper says so, and Temper is offered",
		(window.get_node("%certline") as Label).text == "Any smith may temper this tier." and not temper_button.disabled,
		(window.get_node("%certline") as Label).text)

	server.clear()
	await window.temper()
	check("Temper sends the cell and the piece, then quotes the same piece again",
		server.asked == ["POST /api/smith/temper", "POST /api/smith/quote"]
		and int(server.bodies[0].get("position", -1)) == 0 and str(server.bodies[0].get("item_id", "")) == "zz_smith_blade~d104",
		server.asked)
	check("  THE BAG TAKES THE ANSWER: the tempered blade in its cell, three ore gone",
		_cell_id(bag, 0) == "zz_smith_blade~d107" and bag.get_quantity_of("zz_smith_ore") == 2,
		[_cell_id(bag, 0), bag.get_quantity_of("zz_smith_ore")])
	check("  and the purse is the server's number", player.gold == 18400 and server.purse == 18400, player.gold)
	stats = _texts_under(window.get_node("%statgrid"))
	costs = _texts_under(window.get_node("%costgrid"))
	check("  the anvil now shows the blade as it is: 107 to 110", stats.has("107 (107%)") and stats.has("110 (110%)"), stats)
	check("  and two ore against three is short: red, and Temper is not offered, with the server's reason",
		costs.has("2 / 3") and temper_button.disabled
		and (window.get_node("%tempernotice") as Label).text == "You are missing Test Ore.",
		[costs, (window.get_node("%tempernotice") as Label).text])
	var short_label: Label = null
	for label in window.get_node("%costgrid").find_children("*", "Label", true, false):
		if (label as Label).text == "2 / 3":
			short_label = label
	check("  the short line is drawn in the tooltip's worse colour",
		short_label != null and short_label.get_theme_color("font_color").is_equal_approx(ItemTooltip.COMPARE_WORSE))
	server.clear()
	await window.temper()
	check("  pressing Temper anyway sends nothing", server.asked.is_empty(), server.asked)

	# ---- PERFECT, FULLY TEMPERED, AND A PIECE THAT NEVER ROLLED ----------------------
	server.clear()
	await window.choose_cell(4)
	var notice: Label = window.get_node("%tempernotice")
	check("a Perfect piece is shown and refused, and no quote is asked for",
		server.asked.is_empty() and temper_button.disabled and notice.text.begins_with("Perfect"), [server.asked, notice.text])
	await window.choose_cell(6)
	check("  a piece at the cap on every stat is refused as fully tempered",
		server.asked.is_empty() and temper_button.disabled and notice.text.begins_with("Fully tempered"), [server.asked, notice.text])
	await window.choose_cell(22)
	check("  and a piece that never rolled has nothing to raise",
		server.asked.is_empty() and temper_button.disabled and notice.text.contains("never rolled"), notice.text)
	var perfect_slot: InventorySlot = (grid.get("slots") as Array)[2]
	var blade_slot: InventorySlot = (grid.get("slots") as Array)[0]
	check("  the pieces the hammer cannot help are dimmed in the grid, the others not",
		perfect_slot.icon_rect.modulate.r < 0.9 and blade_slot.icon_rect.modulate.r > 0.9,
		[perfect_slot.icon_rect.modulate, blade_slot.icon_rect.modulate])

	# ---- THE CAP, AND THE CERTIFICATION'S GATE ----------------------------------------
	server.bag[1] = {"item_id": "zz_smith_ore", "quantity": 9}
	bag.load_server_array(server.bag)
	server.clear()
	await window.choose_cell(3)
	stats = _texts_under(window.get_node("%statgrid"))
	check("a stat three points from the cap stops AT the cap: armour 113% to 115%, health 96% to 99%",
		stats.has("45 (113%)") and stats.has("46 (115%)") and stats.has("19 (96%)") and stats.has("20 (99%)"), stats)
	var cert_line: Label = window.get_node("%certline")
	check("  a tier above your rank names the certification it needs, and Temper is not offered",
		cert_line.text == "Needs a Journeyman Smith. Earn it under Royal Certification." and temper_button.disabled
		and cert_line.get_theme_color("font_color").is_equal_approx(ItemTooltip.COMPARE_WORSE), cert_line.text)
	server.clear()
	await window.temper()
	check("  and nothing is sent for it", server.asked.is_empty(), server.asked)

	server.rank = 1
	await window.call("_load_status")
	await window.choose_cell(3)
	check("held, the gate says so and Temper is offered",
		cert_line.text == "Needs a Journeyman Smith - you are one." and not temper_button.disabled, cert_line.text)
	await window.temper()
	stats = _texts_under(window.get_node("%statgrid"))
	check("  tempered, the plate is 115 / 99 and its armour now reads as at the cap",
		_cell_id(bag, 3) == "zz_smith_plate~a115h99" and stats.has("at the cap") and stats.has("20 (102%)"),
		[_cell_id(bag, 3), stats])

	# ---- PAST AN AWAIT ---------------------------------------------------------------
	await window.choose_cell(3)
	anvil.set("_is_open", true)
	var flying: Array = []
	(func() -> void:
		await window.temper()
		flying.append(true)).call()
	window.close_panel()
	var waited := 0.0
	while flying.is_empty() and waited < 5.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	check("closed while the hammer is down, the bag still takes the server's answer",
		_cell_id(bag, 3) == "zz_smith_plate~a115h102" and not window.visible, _cell_id(bag, 3))
	check("  and the anvil was told the window shut", not bool(anvil.get("_is_open")))

	# ---- THE BAG MOVED UNDER THE WINDOW ------------------------------------------------
	# A trade put another piece in cell 0, and this game has not been told yet.
	await window.open_for_anvil(anvil, player)
	server.bag[0] = {"item_id": "zz_smith_plate~a100h100", "quantity": 1}
	await window.choose_cell(0)
	check("a quote for a cell that changed brings the server's bag back, and says the bag changed",
		_cell_id(bag, 0) == "zz_smith_plate~a100h100" and notice.text.contains("changed") and temper_button.disabled,
		[_cell_id(bag, 0), notice.text])

	# ---- WALKING AWAY -----------------------------------------------------------------
	anvil.player_left_range.emit()
	check("the anvil's walk-away closes the window", not window.visible)

	anvil.queue_free()
	_smith_unstage(stage)
	server.stop()
	server.queue_free()
	_smith_forget_stand_ins()
	ApiForTests.BASE_URL = kept_url
	Api.token = kept_token
	Api.server_online = kept_online
	Api.reachability_known = kept_known
	await get_tree().process_frame


func _test_the_smith_certifies() -> void:
	section("THE SMITH - Royal Certification: four ranks, what each costs, Earn on the next one only (0.74.0)")
	_smith_stand_ins()
	var server := SmithServer.new()
	add_child(server)
	if not server.start():
		check("a free local port for the suite's smith", false)
		server.queue_free()
		_smith_forget_stand_ins()
		return
	server.costs = SMITH_TEST_COSTS
	server.certs = SMITH_TEST_CERTS
	server.purse = 7000
	server.level = 12
	var cells: Array = []
	cells.resize(30)
	cells[0] = {"item_id": "zz_smith_plate~a100h100", "quantity": 1}
	cells[1] = {"item_id": "zz_smith_essence", "quantity": 3}
	cells[2] = {"item_id": "zz_smith_bone", "quantity": 2}
	server.bag = cells
	var kept_url: String = ApiForTests.BASE_URL
	var kept_token: String = Api.token
	var kept_online: bool = Api.server_online
	var kept_known: bool = Api.reachability_known
	ApiForTests.BASE_URL = "http://127.0.0.1:%d" % server.port
	Api.token = "suite"
	var stage: Dictionary = _smith_stage(server)
	var window: Control = stage.window
	var bag: Node = stage.bag
	var player: SmithPlayer = stage.player
	await get_tree().process_frame
	await window.open_for_anvil(null, player)
	window.show_certification()
	await get_tree().process_frame
	var rows: Node = window.get_node("%rankrows")
	check("the Royal Certification tab lists the ranks the server sent, in order",
		rows.get_child_count() == 2 and str((rows.get_child(0).find_child("title", true, false) as Label).text) == "Journeyman Smith",
		rows.get_child_count())
	check("  and says what you hold and how far it lets you temper",
		(window.get_node("%ranklabel") as Label).text.begins_with("You hold no certification yet")
		and (window.get_node("%ranklabel") as Label).text.contains("Common gear (tier 1)"), (window.get_node("%ranklabel") as Label).text)
	var first: Control = rows.get_child(0)
	var second: Control = rows.get_child(1)
	var texts: PackedStringArray = _texts_under(first)
	check("  each rank: what it opens, the level it asks, the gold and each material have / need",
		texts.has("Opens Rare gear (tier 3)  -  needs character level 10") and texts.has("7,000 / 5,000") and texts.has("3 / 4"),
		texts)
	var earn: Button = first.find_child("earn", true, false) as Button
	check("ONLY THE NEXT RANK HAS AN EARN BUTTON", earn != null and second.find_child("earn", true, false) == null)
	check("  and while something is short it is not pressable, and says what is missing",
		earn != null and earn.disabled and texts.has("Still needed: 1 Test Essence"), texts)
	server.clear()
	await window.earn(1)
	check("  so nothing is sent", server.asked.is_empty(), server.asked)

	server.bag[1] = {"item_id": "zz_smith_essence", "quantity": 5}
	bag.load_server_array(server.bag)
	window.call("_render_ranks")
	first = rows.get_child(0)
	earn = first.find_child("earn", true, false) as Button
	check("with everything in the bag the button can be pressed", earn != null and not earn.disabled)
	# OUT OF ORDER, WITH EVERYTHING IT COSTS TO HAND: the level, the gold and the
	# bones are all here, so it is the order alone that must stop it.
	player.level = 30
	player.gold = 40000
	bag.load_server_array(server.bag.map(func(c: Variant) -> Variant:
		return {"item_id": "zz_smith_bone", "quantity": 9} if c is Dictionary and str(c["item_id"]) == "zz_smith_bone" else c))
	server.clear()
	await window.earn(2)
	check("asking for a rank out of order sends nothing, even with all it costs to hand", server.asked.is_empty(), server.asked)
	player.level = 12
	player.gold = 7000
	bag.load_server_array(server.bag)
	await window.earn(1)
	check("Earn asks for the next rank by number", server.asked == ["POST /api/smith/certify"]
		and int(server.bodies[0].get("rank", 0)) == 1, [server.asked, server.bodies])
	first = rows.get_child(0)
	second = rows.get_child(1)
	check("  the rank is earned: the first row says so, and the Earn button has moved to the next",
		first.find_child("earn", true, false) == null and (first.find_child("state", true, false) as Label).text == "Earned"
		and second.find_child("earn", true, false) != null)
	check("  the bag and purse are the server's after it took its gold and materials",
		player.gold == 2000 and bag.get_quantity_of("zz_smith_essence") == 1, [player.gold, bag.get_quantity_of("zz_smith_essence")])
	check("  and the window says so", (window.get_node("%noticelabel") as Label).text.contains("Journeyman Smith"),
		(window.get_node("%noticelabel") as Label).text)
	check("  the header's badge names the rank on its hover",
		(window.get_node("%rankbadge") as Control).tooltip_text == "Royal Certification: Journeyman Smith")

	# AN ANSWER WITHOUT THE BAG: the window asks for it rather than drawing
	# materials the Crown has already taken.
	server.rank = 0
	server.purse = 9000
	server.certify_carries_bag = false
	player.gold = 9000
	server.bag[1] = {"item_id": "zz_smith_essence", "quantity": 4}
	bag.load_server_array(server.bag)
	await window.call("_load_status")
	server.clear()
	await window.earn(1)
	check("an answer that carries no bag sends the window to ask for it",
		server.asked == ["POST /api/smith/certify", "GET /api/character"] and bag.get_quantity_of("zz_smith_essence") == 0,
		[server.asked, bag.get_quantity_of("zz_smith_essence")])

	_smith_unstage(stage)
	server.stop()
	server.queue_free()
	_smith_forget_stand_ins()
	ApiForTests.BASE_URL = kept_url
	Api.token = kept_token
	Api.server_online = kept_online
	Api.reachability_known = kept_known
	await get_tree().process_frame


func _test_the_board_takes_gifts() -> void:
	section("PATRONAGE - a Donate control on the kingdom board, and titles beside names (0.74.0)")
	const Board := preload("res://src/ui/kingdom/kingdomboard.gd")
	# "12.400" IS HOW HALF THE WORLD WRITES TWELVE THOUSAND FOUR HUNDRED, and
	# String.to_int() stops at the point and gives 12.
	check("a gift's box reads digits: \"12,400\" and \"12.400\" are 12,400, and a word is nothing",
		Board.typed_gold("12,400") == 12400 and Board.typed_gold("12.400") == 12400
		and Board.typed_gold("abc") == 0 and Board.typed_gold("") == 0, Board.typed_gold("12.400"))
	check("your line: a title and the way to the next",
		Board.patron_line(12400, "Patron", "Benefactor", 100000) == "Patron  -  12,400 / 100,000 to Benefactor",
		Board.patron_line(12400, "Patron", "Benefactor", 100000))
	check("  no title yet: only the way to the first",
		Board.patron_line(2500, "", "Patron", 10000) == "2,500 / 10,000 to Patron", Board.patron_line(2500, "", "Patron", 10000))
	check("  the top title says it is the top",
		Board.patron_line(12000000, "Royal Patron", "", 0) == "Royal Patron  -  the highest title there is")
	var colours: Array = []
	for row in GameConstants.PATRON_TITLES:
		colours.append(Board.title_colour(str(row["title"])))
	check("each title wears a rarity's colour, lowest first from uncommon, each its own",
		colours.size() == 4 and colours[0] == GameConstants.rarity_colour(2) and colours[3] == GameConstants.rarity_colour(5)
		and colours[1] != colours[2], colours)
	var labels: Dictionary = Board.REASON_LABELS
	check("the breakdown has words for a temper, a certification and a gift",
		labels.has("smith_temper") and labels.has("royal_certification") and labels.has("donation"))

	var server := SmithServer.new()
	add_child(server)
	if not server.start():
		check("a free local port for the suite's kingdom", false)
		server.queue_free()
		return
	server.purse = 5000
	server.donated = 9000
	server.board_rows = [
		{"username": "aldra", "contributed": 2400000, "lusions": 0, "deaths": 1, "rank": 1, "title": "Noble Patron"},
		{"username": "rowan", "contributed": 300, "lusions": 0, "deaths": 0, "rank": 3, "title": ""},
	]
	var kept_url: String = ApiForTests.BASE_URL
	var kept_token: String = Api.token
	var kept_online: bool = Api.server_online
	var kept_known: bool = Api.reachability_known
	ApiForTests.BASE_URL = "http://127.0.0.1:%d" % server.port
	Api.token = "suite"
	var players: Array = get_tree().get_nodes_in_group(&"player")
	for p in players:
		p.remove_from_group(&"player")
	var giver := SmithPlayer.new()
	giver.gold = 5000
	giver.add_to_group(&"player")
	add_child(giver)
	var layer := CanvasLayer.new()
	add_child(layer)
	var board: Control = (load("res://scene/ui/kingdom/kingdomboard.tscn") as PackedScene).instantiate() as Control
	layer.add_child(board)
	await get_tree().process_frame
	await board.open_board()
	# THE ROWS ARE BUILT ON A TIME BUDGET (ROW_BUILD_BUDGET_MS), a slice a
	# frame, so on a busy machine the last of them arrive a frame or two later.
	var settling := 0.0
	while not (board.get("_rows_pending") as Array).is_empty() and settling < 2.0:
		await get_tree().process_frame
		settling += get_process_delta_time()
	var list: Node = board.get("board_list")
	var by_name: Dictionary = {}
	for row in list.get_children():
		by_name[(row.get_node("names/who") as Label).text] = row.get_node("names/sub/title")
	var noble: Label = by_name.get("aldra")
	var plain: Label = by_name.get("rowan")
	check("a patron's row shows the title under the name, in its colour",
		noble != null and noble.visible and noble.text == "Noble Patron"
		and noble.get_theme_color("font_color") == Board.title_colour("Noble Patron"), noble.text if noble != null else "")
	check("  and says on its hover what it took", noble != null and noble.tooltip_text.contains("1,000,000"),
		noble.tooltip_text if noble != null else "")
	check("  a row without one shows none", plain != null and not plain.visible)
	var reused: HBoxContainer = noble.get_parent().get_parent().get_parent() as HBoxContainer if noble != null else list.get_child(0)
	board._fill_row(reused, 1, {"username": "nobody", "contributed": 1, "lusions": 0, "deaths": 0})
	check("  a reused row does not keep the last player's title",
		not (reused.get_node("names/sub/title") as Label).visible)
	var patron: Label = board.get("patron_label")
	var bar: ProgressBar = board.get("patron_bar")
	check("your own line shows the way to your first title, with a bar",
		patron.visible and patron.text == "9,000 / 10,000 to Patron" and bar.visible and is_equal_approx(bar.value, 0.9),
		[patron.text, bar.value])
	check("the minimum is shown beside the box", (board.get("donate_minimum") as Label).text == "at least 100")

	server.clear()
	await board.donate(50)
	check("a gift under the minimum is refused here, and nothing is sent",
		server.asked.is_empty() and (board.get("notice_label") as Label).text.contains("at least 100"),
		[server.asked, (board.get("notice_label") as Label).text])
	await board.donate(6000)
	check("  so is one larger than the purse", server.asked.is_empty(), server.asked)

	(board.get("donate_input") as LineEdit).text = "1,500"
	await board._on_donate_pressed()
	check("Donate sends the typed amount for this character",
		server.asked.size() >= 1 and server.asked[0] == "POST /api/kingdom/donate"
		and int(server.bodies[0].get("amount", 0)) == 1500 and int(server.bodies[0].get("slot", -9)) == CharacterData.active_character_index,
		[server.asked, server.bodies])
	check("  the purse is the server's after it", giver.gold == 3500, giver.gold)
	check("  the title it earned is yours at once, with the way to the next",
		patron.text == "Patron  -  10,500 / 100,000 to Benefactor" and patron.get_theme_color("font_color") == Board.title_colour("Patron"),
		patron.text)
	check("  the board is read again, so the realm's total and your row move",
		server.asked.has("GET /api/economy/kingdom"), server.asked)
	check("  and it thanks you, naming the title",
		(board.get("notice_label") as Label).text == "You gave the Crown 1,500 gold. You are named Patron!",
		(board.get("notice_label") as Label).text)
	check("  the box is emptied for the next gift", (board.get("donate_input") as LineEdit).text == "")

	# THE TALLEST THE BOARD GETS: a reader's line of four sentences, a title
	# with the way to the next, at the largest text size in the tallest font.
	# The board was authored to fit a 720-high screen just so - 719 pixels with
	# an empty breakdown - and in a real realm it is taller than the screen
	# there already. The patron line, its bar and the Donate row must not make
	# that worse: the ranking, which scrolls anyway, gives their room back.
	var scroll: ScrollContainer = list.get_parent() as ScrollContainer
	var kept_size: Variant = Settings.get_value("text_size")
	var kept_font: Variant = Settings.get_value("font")
	(board.get("you_label") as Label).text = "You have given 12,400 gold and 0 Lusions.\n400 of that was lost, not given.\nYou have died 3 times.\nRank\u00A04 of\u00A06."
	board._show_patron({"donated": 120000, "title": "Benefactor", "next_title": "Noble Patron", "next_at": 1000000})
	Settings.set_value("font", "fell")
	Settings.set_value("text_size", 1.5)
	var added: Array = [board.get("patron_label"), board.get("patron_bar"), (board.get("donate_input") as Control).get_parent()]
	for part in added:
		(part as Control).visible = false
	scroll.custom_minimum_size.y = 220.0
	await get_tree().process_frame
	await get_tree().process_frame
	var as_it_was: float = PanelWindow.content_minimum(board).y
	for part in added:
		(part as Control).visible = true
	await get_tree().process_frame
	board._fit_list_to_screen()
	await get_tree().process_frame
	var as_it_is: float = PanelWindow.content_minimum(board).y
	check("at the largest size the gift's three new lines cost the board no height: the ranking gives it back",
		as_it_is <= maxf(720.0, as_it_was) + 0.5 and scroll.custom_minimum_size.y < 220.0,
		[as_it_is, as_it_was, scroll.custom_minimum_size.y])
	Settings.set_value("text_size", 1.0)
	Settings.set_value("font", "standard")
	await get_tree().process_frame
	await get_tree().process_frame
	board._fit_list_to_screen()
	check("  and at the normal size the ranking is its authored 220 again", is_equal_approx(scroll.custom_minimum_size.y, 220.0),
		scroll.custom_minimum_size.y)
	Settings.set_value("text_size", kept_size)
	Settings.set_value("font", kept_font)

	layer.queue_free()
	giver.queue_free()
	for p in players:
		if is_instance_valid(p):
			p.add_to_group(&"player")
	server.stop()
	server.queue_free()
	ApiForTests.BASE_URL = kept_url
	Api.token = kept_token
	Api.server_online = kept_online
	Api.reachability_known = kept_known
	await get_tree().process_frame


# =============================================================================
# THE SHOPKEEPER WAVES ONCE
# =============================================================================
# A wave is a GREETING, not a state. It used to loop for as long as the player
# stood in the shop, and the script's own header explained why that was fine:
# "THE STILL FRAME IS FRAME 0 OF THE WAVE ... we never need a second, one-frame
# idle animation."
#
# THAT WAS TRUE OF THE DESIGN AND FALSE OF THE SHEET. The ten frames actually
# shipped in art/npc/shopkeeper.png began mid-wave - frame 0 was the arm fully
# extended, hand out - so the "still figure" the comment promised was a man
# frozen with his arm in the air, and the wave had no rest pose to return to. It
# could only loop, because looping was the only state those frames could express.
#
# A comment cannot fail, so nobody compared the sentence to the pixels for as
# long as it existed. This section does, which is why two of these checks read
# images rather than strings.
#
# The artist's full set fixes it at the source: a seven-frame idle, and an
# eleven-frame wave that begins at rest, raises, waves and lowers. The wave does
# not loop; when it ends, animation_finished puts the idle back.
#
# THE WAVE'S LAST FRAME IS NOT THE REST POSE - it is the arm still up at the
# shoulder, ended mid-lower so it cuts cleanly back to the idle. So "stop on the
# last frame" is not an option here, and there is a check saying so, because it
# is the obvious simplification and it reintroduces the frozen-arm bug.

func _test_the_shopkeeper_waves_once() -> void:
	section("THE SHOPKEEPER - one wave per arrival, then back to the idle")

	var packed: PackedScene = load("res://scene/walls/shophouse.tscn") as PackedScene
	check("shophouse.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate():
		return

	var house: Node = packed.instantiate()
	add_child(house)
	var sprite: AnimatedSprite2D = house.get_node_or_null(
		"interiorfurniture/shopvendor/animatedsprite2d") as AnimatedSprite2D
	check("the shopkeeper sprite is where the scene says it is", sprite != null)
	if sprite == null:
		house.queue_free()
		return

	var sf: SpriteFrames = sprite.sprite_frames
	check("it has SpriteFrames", sf != null)
	if sf == null:
		house.queue_free()
		return

	check("there is an idle at all", sf.has_animation(&"idledown"))
	check("and a wave", sf.has_animation(&"wavedown"))
	check("the idle loops", sf.get_animation_loop(&"idledown"))
	check("THE WAVE DOES NOT LOOP", not sf.get_animation_loop(&"wavedown"),
		"a looping animation never emits animation_finished, so it can never end")
	check("the idle is the artist's seven frames",
		sf.get_frame_count(&"idledown") == 7, sf.get_frame_count(&"idledown"))
	check("the wave is the artist's eleven frames",
		sf.get_frame_count(&"wavedown") == 11, sf.get_frame_count(&"wavedown"))
	check("the scene rests on the idle, not the wave",
		sprite.animation == &"idledown", sprite.animation)

	# REGIONS READ OFF THE TEXTURE, NOT OFF THE LOOP COUNTER. The first draft of
	# this recorded `seen[i * 64]` - the index being iterated rather than the
	# region just fetched - so the set was eighteen wide whatever the scene said,
	# and the check could not fail. Sabotage found it. Same family as a count
	# that includes the function's own definition.
	var regions_ok: bool = true
	var columns: Dictionary = {}
	for pair in [[&"idledown", 7, 0], [&"wavedown", 11, 7]]:
		for i in range(int(pair[1])):
			var tex: AtlasTexture = sf.get_frame_texture(pair[0], i) as AtlasTexture
			if tex == null:
				regions_ok = false
				continue
			if tex.region != Rect2((int(pair[2]) + i) * 64, 0, 64, 64):
				regions_ok = false
			columns[tex.region.position.x] = true
	check("every frame reads its own column of the sheet", regions_ok)
	check("all eighteen columns are used exactly once", columns.size() == 18,
		"%d distinct columns" % columns.size())

	# AGAINST THE PIXELS. "the still frame is frame 0 of the wave" is exactly the
	# claim the old comment made about a sheet that did not support it.
	var wave_first: Image = _frame_image(sf, &"wavedown", 0)
	var idle_first: Image = _frame_image(sf, &"idledown", 0)
	var wave_last: Image = _frame_image(sf, &"wavedown",
		sf.get_frame_count(&"wavedown") - 1)
	check("the wave begins on the pose the idle rests on",
		_images_match(idle_first, wave_first, 20),
		"the cut from idle into wave would jump")
	check("the wave's LAST frame is NOT that rest pose",
		not _images_match(wave_last, wave_first, 20),
		"if it were, stopping on it would do - and this whole change is pointless")

	# BEHAVIOUR, WITH THE TREE RUNNING. Calling the handler by hand proves the
	# handler; only waiting proves the SIGNAL, and the signal is the mechanism.
	var probe: AnimatedSprite2D = AnimatedSprite2D.new()
	probe.sprite_frames = sf
	var area: Area2D = Area2D.new()
	area.add_child(probe)
	probe.set_script(load("res://src/world/shopkeeperanim.gd"))
	add_child(area)

	# _ready() DOES NOT RUN UNTIL THE TREE TICKS. Without this the node never
	# enters the tree, every check below reads the SpriteFrames' default
	# animation instead of the script's, and they all pass blind - which is how
	# the sabotage "boot straight into the wave" first stayed green.
	await get_tree().process_frame
	check("the probe is really in the tree, so _ready() ran", probe.is_inside_tree())
	check("it starts on the idle", probe.animation == &"idledown", probe.animation)

	var body: CharacterBody2D = CharacterBody2D.new()
	body.add_to_group("player")
	probe._on_body_entered(body)
	check("walking up plays the wave", probe.animation == &"wavedown",
		probe.animation)

	probe.speed_scale = 30.0
	await get_tree().create_timer(0.6).timeout
	check("THE WAVE ENDS ON ITS OWN AND THE IDLE COMES BACK",
		probe.animation == &"idledown", probe.animation)
	check("and it is playing the idle rather than stopped on a frame",
		probe.animation == &"idledown" and probe.is_playing())

	var rock: CharacterBody2D = CharacterBody2D.new()
	probe._on_body_entered(rock)
	check("an enemy crossing the shop does not get waved at",
		probe.animation == &"idledown", probe.animation)

	var anim_src: String = FileAccess.get_file_as_string(
		"res://src/world/shopkeeperanim.gd")
	check("leaving is not wired to anything - the wave is finite already",
		not _code_only(anim_src).contains("body_exited.connect"))
	check("the finished handler returns to the idle rather than stopping",
		_code_only(anim_src).contains("_play_idle()"))

	body.free()
	rock.free()
	area.queue_free()
	house.queue_free()
	print("  one wave per arrival, 11 frames, then the 7-frame idle")


func _test_props_block_the_player() -> void:
	section("SOLID PROPS — the chest and the firepit push back")

	# READ OFF THE REAL PLAYER, not typed in here. A second copy of "19" would
	# agree with itself forever while the classes moved underneath it.
	var player_layer: int = int(_scene_root_prop(
		"res://scene/characters/warrior.tscn", "collision_layer", 0))
	var player_mask: int = int(_scene_root_prop(
		"res://scene/characters/warrior.tscn", "collision_mask", 0))
	check("the player's own layer and mask are readable",
		player_layer != 0 and player_mask != 0,
		"layer %d mask %d" % [player_layer, player_mask])
	if player_layer == 0 or player_mask == 0:
		return

	for path in BLOCKING_PROPS:
		var what: String = BLOCKING_PROPS[path]
		var packed: PackedScene = load(path) as PackedScene
		check("%s loads" % what, packed != null and packed.can_instantiate())
		if packed == null or not packed.can_instantiate():
			continue

		var prop: Node2D = packed.instantiate() as Node2D
		var body: StaticBody2D = prop.get_node_or_null("body") as StaticBody2D
		check("%s has a solid body" % what, body != null,
			"an Area2D detects, it does not push back")
		if body == null:
			prop.free()
			continue

		var shape_node: CollisionShape2D = body.get_node_or_null("collision") \
			as CollisionShape2D
		check("%s's body carries a shape" % what,
			shape_node != null and shape_node.shape != null)
		if shape_node == null or shape_node.shape == null:
			prop.free()
			continue

		check("%s blocks on a layer the player actually collides with" % what,
			(body.collision_layer & player_mask) != 0,
			"body layer %d vs player mask %d" % [body.collision_layer, player_mask])

		# THE PROP MUST NOT SEE ITS OWN BLOCKER.
		var root_mask: int = int(prop.get("collision_mask")) if "collision_mask" in prop else 0
		check("%s cannot detect its own blocker" % what,
			(body.collision_layer & root_mask) == 0,
			"body layer %d is inside the Area2D's mask %d" % [body.collision_layer, root_mask])

		check("%s's body is not scaled" % what, body.scale == Vector2.ONE, body.scale)
		check("%s's shape node is not scaled" % what,
			shape_node.scale == Vector2.ONE, shape_node.scale)

		# AIMED AT THE ART, NOT AT THE SHAPE, and this is the whole point.
		# The first version drove the mover at `shape_node.position.y` - so
		# parking the shape a hundred pixels off the sprite moved the TEST with
		# it and stayed green. A check that aims at the thing it is checking
		# cannot find it missing. Third time today; see the column-counter in
		# the shopkeeper section and the call count above.
		#
		# _art_ground_y() reads the sprite's lowest non-transparent row and
		# transforms it through the sprite's own offset and scale, so the aim
		# point is where the prop MEETS THE GROUND however the shape is set up.
		var aim: float = _art_ground_y(prop)
		check("%s's footprint covers where its art meets the ground" % what,
			_shape_covers(shape_node, aim), "art ground line at y=%.1f, shape at "
			% aim + "y=%.1f" % shape_node.position.y)

		var blocked: float = await _walk_into(prop, player_layer, player_mask, aim)
		shape_node.disabled = true
		var through: float = await _walk_into(prop, player_layer, player_mask, aim)
		shape_node.disabled = false

		check("%s stops a body walking into it" % what, blocked < 0.0,
			"ended at x=%.1f, which is past the prop" % blocked)
		check("and the same body goes straight through when the shape is off" % [],
			through > 20.0,
			"ended at x=%.1f with collision disabled - the drive never moved, so "
			% through + "the check above proves nothing")
		check("%s: blocked and unblocked differ" % what, through - blocked > 20.0,
			"blocked %.1f vs through %.1f" % [blocked, through])

		prop.free()

	print("  drove a player-shaped body into each prop, with and without its shape")


func _test_nothing_shadows_its_base_class() -> void:
	section("SHADOWING — no local hides a property its base class already has")

	var offenders: Array[String] = []
	var props: Dictionary = {}
	var scanned: Array[int] = [0]
	_scan_shadowing("res://src", offenders, props, scanned)
	offenders.sort()

	check("nothing declares a name its own base class already owns",
		offenders.is_empty(), "\n         ".join(offenders))
	check("and the scan actually read the project",
		scanned[0] > 50, "%d scripts scanned" % scanned[0])

	# THE PARSER, TESTED DIRECTLY, because the paragraph above this section
	# explains the rule by quoting `var size` at the start of a line - and a
	# scanner that read prose would report its own explanation. Sixth time in
	# this file that a text check could have matched the comment describing the
	# thing it forbids, so it gets an assertion rather than a hope.
	check("a comment that merely says 'var size' is not a declaration",
		_declared_name("\t# var size: int = 0   <- the rule, not a use") == "",
		_declared_name("\t# var size: int = 0   <- the rule, not a use"))
	check("but a real declaration still is",
		_declared_name("\tvar size: int = 0") == "size")
	check("and so is a for loop variable",
		_declared_name("\tfor name in things:") == "name")

	print("  %d scripts, %d base classes consulted through ClassDB"
		% [scanned[0], props.size()])


# =============================================================================
# NOTHING SHADOWS A MEMBER OF ITS OWN SCRIPT (0.64.0)
# =============================================================================
# The owner's editor, 20 Oct, four warnings: "The local function parameter
# "path" is shadowing an already-declared variable at line 55 in the current
# class", and three "local variable" ones - settings.gd's own `static var
# path` hidden by locals called path. SHADOWED_VARIABLE is an editor warning,
# like the base-class one above: a headless run never prints it, so it is
# scanned for. The first scan found two more the editor would have said
# next: a parameter in optionsscreen.gd hiding its `frame_cap` picker, and a
# `var skipped` in this file hiding the suite's own count of skips.
#
# MEMBERS are what a script declares at its left edge - var, static var,
# const, with any annotations before them. LOCALS are `var`, `const` and `for`
# inside a function, and every function's parameters. An inner class's lines
# are its own and are skipped, and so is anything between triple quotes.

func _test_nothing_shadows_its_own_members() -> void:
	section("SHADOWING - no local or parameter hides a member of its own script")
	var offenders: Array[String] = []
	var scanned: int = 0
	for script_file in _all_gd_under("res://src"):
		scanned += 1
		offenders.append_array(_own_member_shadows(script_file, FileAccess.get_file_as_string(script_file)))
	check("no local, loop or parameter hides a var or const of its own script (%d scripts)" % scanned,
		offenders.is_empty() and scanned > 50, "\n         ".join(offenders))
	var probe: String = "\n".join([
		"static var path: String = \"x\"",
		"@export_range(0, 1, 0.5) var level: float = 0.5",
		"",
		"func load_from(path: String,",
		"\t\tlevel: float = 1.0) -> void:",
		"\tvar path_too: int = 1",
		"\tfor path in []:",
		"\t\tpass",
		"\t\"\"\"",
		"\tvar level := 2",
		"\t\"\"\"",
		"",
		"class Inner:",
		"\tvar path: int = 2",
	])
	var found: Array[String] = _own_member_shadows("probe.gd", probe)
	check("  the scan itself: a parameter over two lines, a member behind an annotation and a for loop are found; a longer name, a docstring and an inner class's own are not",
		found.size() == 3 and "\n".join(found).contains("parameter 'path'") and "\n".join(found).contains("parameter 'level'")
		and "\n".join(found).contains("probe.gd:7"),
		found)


func _test_every_resource_reference_exists() -> void:
	section("REFERENCES — every ext_resource names a file that exists")

	var missing: Array[String] = []
	var checked: Array[int] = [0, 0]  # [references checked, files read]
	_scan_resource_refs("res://scene", missing, checked)
	_scan_resource_refs("res://data", missing, checked)
	_scan_resource_refs("res://art", missing, checked)
	_scan_resource_refs("res://assets", missing, checked)
	missing.sort()

	check("every ext_resource path resolves to a real file", missing.is_empty(),
		"\n         ".join(missing))
	# THRESHOLDS NEAR THE REAL FIGURES, NOT TOKEN ONES. The first draft asked
	# for 200 references across 50 files, and deleting the `res://scene` scan
	# entirely left it green - data/, art/ and assets/ alone clear a token
	# threshold comfortably. A count check that survives losing the largest of
	# four scan roots is not checking the scan. 897 across 416 today.
	check("and the scan actually read something",
		checked[0] > 600 and checked[1] > 250,
		"%d references across %d files - a scan root has gone quiet"
			% [checked[0], checked[1]])

	# THE PROBE ITSELF, asserted, because the whole check rests on one fact that
	# is easy to "simplify" into uselessness. A reader who swaps FileAccess for
	# ResourceLoader.exists() would leave every check above green for ever.
	check("FileAccess is what answers 'is the source file there'",
		FileAccess.file_exists("res://project.godot"))
	check("and a path that was never real is answered honestly",
		not FileAccess.file_exists("res://art/this-file-has-never-existed.png"))

	print("  %d ext_resource references across %d scenes and resources"
		% [checked[0], checked[1]])


func _test_panels_fill_their_window() -> void:
	section("PANEL GEOMETRY — the drawn panel is exactly where the grips are")

	var panels: Array[String] = []
	_find_window_scenes("res://scene/ui", panels)
	panels.sort()
	check("the PanelWindow scenes were found by reading the scripts",
		panels.size() >= 14, "%d found" % panels.size())

	var wrong: Array[String] = []
	for path in panels:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			wrong.append("%s does not load" % path)
			continue
		var state: SceneState = packed.get_state()
		var first: int = _first_child_index(state)
		if first == -1:
			wrong.append("%s has no child under its root" % path)
			continue
		var geo: Dictionary = {}
		for key in ["anchor_left", "anchor_top", "anchor_right", "anchor_bottom",
				"offset_left", "offset_top", "offset_right", "offset_bottom"]:
			geo[key] = 0.0
		for i in range(state.get_node_property_count(first)):
			var pname: String = state.get_node_property_name(first, i)
			if geo.has(pname):
				geo[pname] = float(state.get_node_property_value(first, i))
		var fills: bool = geo["anchor_left"] == 0.0 and geo["anchor_top"] == 0.0 \
			and geo["anchor_right"] == 1.0 and geo["anchor_bottom"] == 1.0 \
			and geo["offset_left"] == 0.0 and geo["offset_top"] == 0.0 \
			and geo["offset_right"] == 0.0 and geo["offset_bottom"] == 0.0
		if not fills:
			wrong.append("%s  %s  anchors (%s,%s,%s,%s) offsets (%s,%s,%s,%s)" % [
				path.get_file(), state.get_node_name(first),
				geo["anchor_left"], geo["anchor_top"], geo["anchor_right"], geo["anchor_bottom"],
				geo["offset_left"], geo["offset_top"], geo["offset_right"], geo["offset_bottom"]])
	check("every panel fills its window exactly - no overhang, no zero-size window",
		wrong.is_empty(), "\n         ".join(wrong))

	# WHILE RESIZING. Build a window whose content needs 300 x 250 and ask.
	var host: Control = Control.new()
	var frame: PanelContainer = PanelContainer.new()
	var content: Control = Control.new()
	content.custom_minimum_size = Vector2(300, 250)
	frame.add_child(content)
	host.add_child(frame)
	# THROUGH _minimum(), NOT AROUND IT. The first draft asked the static
	# content_minimum() directly and handed that to resize_rect() - so it proved
	# the helper worked and never proved anything USED it. Sabotaging _minimum()
	# to ignore the content left it green. What resize and fit actually consult
	# is _minimum(), so that is what gets asked.
	var probe: PanelWindow = PanelWindow.new()
	probe.window = host
	var needed: Vector2 = probe._minimum()
	check("the window's minimum includes what its content needs",
		needed.x >= 300.0 and needed.y >= 250.0, needed)
	var squeezed: Rect2 = PanelWindow.resize_rect(Rect2(0, 0, 400, 400),
		Vector2(-390, -390), PanelWindow.EDGE_RIGHT | PanelWindow.EDGE_BOTTOM,
		needed, Vector2(1920, 1080))
	check("so dragging it smaller stops where the content would start to overflow",
		squeezed.size.x >= 300.0 and squeezed.size.y >= 250.0, squeezed.size)
	frame.visible = false
	check("and a hidden child does not hold the window open",
		PanelWindow.content_minimum(host) == Vector2.ZERO,
		PanelWindow.content_minimum(host))
	host.free()

	print("  %d panel scenes, every one filling its window" % panels.size())


func _test_a_lit_fire_opens_cooking() -> void:
	section("FIREPIT — kindling a fire ends in the cooking screen")

	var packed: PackedScene = load("res://scene/interactables/firepit.tscn") as PackedScene
	check("firepit.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate():
		return

	var fake_script := GDScript.new()
	fake_script.source_code = "extends Node\nvar opened: Array = []\n" \
		+ "func open_cooking(pit, who) -> void:\n\topened.append([pit, who])\n"
	fake_script.reload()
	var hud: Node = Node.new()
	hud.set_script(fake_script)
	hud.add_to_group("hud")
	add_child(hud)

	var cook: CharacterBody2D = CharacterBody2D.new()
	cook.add_to_group("player")
	add_child(cook)

	# THE CONTROL. Prove the stand-in is reachable before trusting its silence.
	var probe_pit: Area2D = packed.instantiate() as Area2D
	add_child(probe_pit)
	await get_tree().process_frame
	probe_pit.player_in_range = cook
	probe_pit._open_cooking()
	check("the stand-in HUD really does receive open_cooking()",
		hud.opened.size() == 1, hud.opened.size())
	probe_pit.queue_free()
	hud.opened.clear()

	# THE ONE PRESS.
	var pit: Area2D = packed.instantiate() as Area2D
	add_child(pit)
	await get_tree().process_frame
	check("a firepit starts cold", not pit.is_lit)
	pit.player_in_range = cook
	pit._kindle()
	check("kindling does not open the screen before the fire has caught",
		hud.opened.is_empty(), hud.opened.size())
	await get_tree().create_timer(float(pit.KINDLE_SECONDS) + 0.3).timeout
	check("once the kindle finishes the fire is lit", pit.is_lit)
	check("AND THE COOKING SCREEN OPENS, ONCE, WITHOUT A SECOND PRESS",
		hud.opened.size() == 1, hud.opened.size())
	check("for this fire and this player",
		hud.opened.size() == 1 and hud.opened[0][0] == pit and hud.opened[0][1] == cook)
	check("and the fire knows its panel is up", pit._is_open)
	pit.queue_free()
	hud.opened.clear()

	# WALKING AWAY MID-KINDLE CANCELS ALL OF IT.
	var left: Area2D = packed.instantiate() as Area2D
	add_child(left)
	await get_tree().process_frame
	left.player_in_range = cook
	left._kindle()
	left.player_in_range = null
	await get_tree().create_timer(float(left.KINDLE_SECONDS) + 0.3).timeout
	check("walk away during the kindle and no screen opens", hud.opened.is_empty(),
		hud.opened.size())
	check("and no fire is left burning behind you", not left.is_lit)
	left.queue_free()

	# light_fire() ON ITS OWN IS THE _ready()/QUEST PATH, AND MUST STAY QUIET.
	var authored: Area2D = packed.instantiate() as Area2D
	add_child(authored)
	await get_tree().process_frame
	authored.player_in_range = cook
	authored.light_fire()
	await get_tree().process_frame
	check("a fire lit by anything but the player's own kindle opens nothing",
		hud.opened.is_empty(),
		"a camp authored lit would pop the cooking screen at everyone arriving")
	authored.queue_free()

	cook.queue_free()
	hud.queue_free()
	print("  one press on a cold fire: kindle, then the cooking screen")


# =============================================================================
# THE INVENTORY WEARS THE HOTBAR'S SLOTS, AND THE TRASH IS A SLOT TOO
# =============================================================================
# Asked for as "use hotbar slots for inventory boxes, just no numbers". The
# hotbar's socket - art/images/hotbarslot.png, nine-sliced at 7px - is now a
# named theme style, PanelSocket, and inventoryslot.tscn wears it. Every grid
# that InventoryContainer builds uses that one slot scene, so the inventory,
# the bank, the loot bag and the cooking screen all changed together, which is
# the point: one slot, everywhere a slot appears.
#
# "JUST NO NUMBERS" is structural rather than a setting. The hotbar draws its
# key number as a separate `keylabel` Label on top of the socket; the socket art
# itself has no number in it. So the inventory slot gets the art and not the
# label, and a check says the label stays out.
#
# THE HOTBAR STILL HAS ITS OWN COPY of the socket style, inline in hotbar.tscn,
# and that is deliberate: it was not asked to change. The price is two copies
# that could drift, so they are compared here - texture and all eight margins -
# and the day one is edited without the other, this goes red.
#
# THE TRASH was a TextureButton with a sentence hung off it at a fixed offset.
# It is a socket now, the same size as a slot, in the inventory and the bank,
# and it glows red while something it would accept is over it.

func _test_slots_wear_the_hotbar_socket() -> void:
	section("SLOTS — the hotbar's socket, no numbers, and a trash slot that is one")

	var theme: Theme = load("res://assets/themes/rpg_ui_theme.tres") as Theme
	check("the UI theme loads", theme != null)
	if theme == null:
		return
	var socket: StyleBoxTexture = theme.get_stylebox("panel", &"PanelSocket") as StyleBoxTexture
	check("the theme names the socket as PanelSocket",
		socket != null and socket.texture != null)
	if socket == null or socket.texture == null:
		return
	check("and it is the hotbar's slot art",
		socket.texture.resource_path == "res://art/images/hotbarslot.png",
		socket.texture.resource_path)

	# THE TWO COPIES AGREE.
	var hotbar_socket: StyleBoxTexture = _node_prop_in_scene("res://scene/ui/hotbar.tscn",
		"margin/slots/slot1", "theme_override_styles/panel") as StyleBoxTexture
	check("the hotbar's own socket is readable", hotbar_socket != null)
	if hotbar_socket != null:
		var drift: Array[String] = []
		if hotbar_socket.texture == null or \
				hotbar_socket.texture.resource_path != socket.texture.resource_path:
			drift.append("texture")
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			if hotbar_socket.get_texture_margin(side) != socket.get_texture_margin(side):
				drift.append("texture margin %d" % side)
			if hotbar_socket.get_content_margin(side) != socket.get_content_margin(side):
				drift.append("content margin %d" % side)
		check("the inventory's socket and the hotbar's are the same socket",
			drift.is_empty(), "differ in: " + ", ".join(drift))

	# THE SLOT, AS IT ACTUALLY RESOLVES.
	var slot_scene: PackedScene = load("res://scene/ui/inventory/inventoryslot.tscn") as PackedScene
	check("inventoryslot.tscn loads", slot_scene != null and slot_scene.can_instantiate())
	if slot_scene != null and slot_scene.can_instantiate():
		var slot: Control = slot_scene.instantiate() as Control
		slot.theme = theme
		add_child(slot)
		var worn: StyleBoxTexture = slot.get_theme_stylebox("panel") as StyleBoxTexture
		check("an inventory slot wears the socket",
			worn != null and worn.texture != null
				and worn.texture.resource_path == "res://art/images/hotbarslot.png",
			worn)
		check("and carries no key number - that is the hotbar's keylabel, not the art",
			slot.find_child("keylabel", true, false) == null)
		slot.queue_free()

	# ONE SLOT SCENE FOR EVERY GRID. A scene that points its container at a slot
	# scene of its own quietly stops matching the others.
	var own_slots: Array[String] = []
	for path in ["res://scene/ui/inventory/inventory.tscn", "res://scene/ui/bank/bankinventory.tscn",
			"res://scene/ui/lootbag/lootbaginventory.tscn", "res://scene/ui/cooking/cookingscreen.tscn"]:
		if FileAccess.get_file_as_string(path).contains("inventory_slot_scene"):
			own_slots.append(path.get_file())
	check("the inventory, bank, loot bag and cooking grids all use the one slot",
		own_slots.is_empty(), "overridden in: " + ", ".join(own_slots))

	# THE GEAR SQUARES (day 1, "now the gear slots"). equipmentslot.tscn wears
	# the socket itself; the eight squares on the doll each used to override it
	# with the flat PanelSlot. Read as each square resolves, so an override left
	# on one square is caught by name.
	var gear: Node = (load("res://scene/ui/equipment/equipmentpanel.tscn") as PackedScene).instantiate()
	var flat_squares: Array[String] = []
	for square_name in ["helm", "chest", "legs", "boots", "weapon", "shield", "amulet", "ring"]:
		var square: Control = gear.find_child(square_name, true, false) as Control
		var face: StyleBoxTexture = null
		if square is EquipmentSlot:
			face = theme.get_stylebox("panel", square.theme_type_variation) as StyleBoxTexture
		if face == null or face.texture != socket.texture:
			flat_squares.append(square_name)
	gear.free()
	check("the eight gear squares wear the hotbar's socket too",
		flat_squares.is_empty(), "not a socket: " + ", ".join(flat_squares))

	# THE TRASH, IN BOTH PLACES.
	for path in ["res://scene/ui/inventory/inventory.tscn", "res://scene/ui/bank/bankinventory.tscn"]:
		var where: String = path.get_file()
		var trash_path: String = "mainpanel/margincontainer/vboxcontainer/trashrow/trashslot"
		var node_type: String = str(_node_type_in_scene(path, trash_path))
		check("%s has a trash slot" % where, node_type == "PanelContainer", node_type)
		check("%s's trash wears the socket" % where,
			str(_node_prop_in_scene(path, trash_path, "theme_type_variation")) == "PanelSocket")
		var script: Script = _node_prop_in_scene(path, trash_path, "script") as Script
		check("%s's trash runs trashslot.gd" % where,
			script != null and script.resource_path == "res://src/ui/inventory/trashslot.gd")
		check("%s's trash asks before it destroys anything" % where,
			str(_node_type_in_scene(path, trash_path + "/confirmationdialog")) == "ConfirmationDialog")
		for child in ["/centercontainer", "/centercontainer/icon"]:
			# NULL-SAFE ON PURPOSE: with the trash node missing entirely there
			# is no filter to read, and int(null) would unwind the rest of the
			# section - the glow checks below included - while the run still
			# printed 0 failed. Every check here fails by name instead.
			var filter: Variant = _node_prop_or_default(path, trash_path + child, "mouse_filter")
			check("%s: the trash's %s lets the drop through" % [where, child.get_file()],
				filter != null and int(filter) == Control.MOUSE_FILTER_IGNORE,
				"a child left on its default filter swallows the drag and the trash accepts nothing")

	# THE GLOW, AS BEHAVIOUR.
	var trash: PanelContainer = PanelContainer.new()
	trash.theme = theme
	trash.theme_type_variation = &"PanelSocket"
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.name = "confirmationdialog"
	trash.add_child(dialog)
	trash.set_script(load("res://src/ui/inventory/trashslot.gd"))
	add_child(trash)
	check("the trash probe is in the tree, so _ready() ran", trash.is_inside_tree())
	check("it rests unlit", not trash.is_hot())
	var idle_style: StyleBox = trash.get_theme_stylebox("panel")

	var from_bag: Dictionary = {"stack": null, "source_slot": null, "source_type": "inventory"}
	check("it accepts an item dragged from the bag", trash._can_drop_data(Vector2.ZERO, from_bag))
	check("AND GLOWS WHILE IT IS OVER IT", trash.is_hot())
	var hot_style: StyleBoxTexture = trash.get_theme_stylebox("panel") as StyleBoxTexture
	check("the glow is really a different look, not the same socket",
		hot_style != null and idle_style != hot_style and hot_style.modulate_color != Color.WHITE,
		str(hot_style.modulate_color) if hot_style != null else "no style")

	trash.notification(Control.NOTIFICATION_DRAG_END)
	check("and goes out when the drag ends", not trash.is_hot())

	# A SECOND DROP WHILE ONE IS BEING CONFIRMED is the drag it refuses now.
	# It used to refuse every hotbar drag too, back when a key only pointed at
	# a bag item; see _test_the_hotbar_holds_items() for the key it accepts.
	trash.confirm_dialog.visible = true
	check("it refuses a second drop while a delete is being confirmed",
		not trash._can_drop_data(Vector2.ZERO, from_bag))
	check("and does not glow for something it will refuse", not trash.is_hot(),
		"a target that lights up and then says no is worse than one that never lit")
	trash.confirm_dialog.visible = false

	trash._can_drop_data(Vector2.ZERO, from_bag)
	trash.notification(Control.NOTIFICATION_MOUSE_EXIT)
	check("and goes out when you drag away from it", not trash.is_hot())
	trash.queue_free()

	print("  one socket for every slot, and a trash slot in the bag and the bank")


func _test_the_bank_reads_well() -> void:
	section("BANK — the balance you came for, beside what moves it")

	var scene_path: String = "res://scene/ui/bank/bankinventory.tscn"
	var script_path: String = "res://src/ui/bank/bankinventory.gd"
	var VB: String = "mainpanel/margincontainer/vboxcontainer"

	check("the header says BANK, matching INVENTORY",
		str(_node_prop_in_scene(scene_path, VB + "/headerpanel/hboxcontainer/headerlabel", "text")) == "BANK"
			and str(_node_prop_in_scene("res://scene/ui/inventory/inventory.tscn",
				VB + "/headerpanel/hboxcontainer/headerlabel", "text")) == "INVENTORY")

	# LAYOUT, BY PARENTAGE.
	var balance: String = VB + "/currencypanel/currencyvbox/goldcontainer"
	var actions: String = VB + "/currencypanel/currencyvbox/actionrow"
	for pair in [[balance, "goldicon"], [balance, "goldlabel"], [balance, "carrylabel"],
			[actions, "goldinput"], [actions, "depositbuttons"], [actions, "withdrawbutton"]]:
		check("%s sits in the %s row" % [pair[1], "balance" if pair[0] == balance else "action"],
			_node_type_in_scene(scene_path, pair[0] + "/" + pair[1]) != null)
	var placeholder: String = str(_node_prop_in_scene(scene_path, actions + "/goldinput", "placeholder_text"))
	check("the amount field says it is gold", placeholder.to_lower().contains("gold"),
		"'%s' - beside Deposit AND Withdraw, 'Enter amount' does not say of what" % placeholder)
	var icon_size: Variant = _node_prop_in_scene(scene_path, balance + "/goldicon", "custom_minimum_size")
	check("the coin is big enough to read", icon_size is Vector2 and (icon_size as Vector2).y >= 24.0, icon_size)

	# EVERY %NAME THE SCRIPT USES IS A UNIQUE NODE IN THE SCENE.
	var src: String = _code_only(FileAccess.get_file_as_string(script_path))
	var packed: PackedScene = load(scene_path) as PackedScene
	var unique_names: Dictionary = {}
	if packed != null:
		var state: SceneState = packed.get_state()
		for i in range(state.get_node_count()):
			for p in range(state.get_node_property_count(i)):
				if state.get_node_property_name(i, p) == "unique_name_in_owner" \
						and bool(state.get_node_property_value(i, p)):
					unique_names[str(state.get_node_name(i))] = true
	# ONLY THE SCRIPT'S OWN LOOKUPS. The first version matched every "%word" in
	# the file, and reported "%d" and "%s" - format specifiers, `"%s in bank" %
	# ...` - plus `inv_screen.get_node_or_null("%inventorycontainer")`, which is
	# a unique name in a DIFFERENT scene, resolved on a different node. Two
	# shapes are this node's own: `= %name`, and get_node[_or_null]("%name")
	# called with no receiver in front of it.
	var used: Dictionary = {}
	var direct := RegEx.new()
	direct.compile("=\\s*%([a-z_][a-z0-9_]*)")
	var by_call := RegEx.new()
	by_call.compile("(?<![.\\w])get_node(?:_or_null)?\\(\\s*\"%([a-z_][a-z0-9_]*)\"")
	for rx in [direct, by_call]:
		for m in rx.search_all(src):
			used[m.get_string(1)] = true
	var dangling: Array[String] = []
	for name_used in used:
		if not unique_names.has(name_used):
			dangling.append("%" + name_used)
	check("the script found some %names to check", used.size() >= 5, used.keys())
	check("every %name bankinventory.gd reaches exists, and is unique, in the scene",
		dangling.is_empty(), "missing or not unique: " + ", ".join(dangling))
	check("and the gold controls are reached by name, not by a path that can move",
		not src.contains("$mainpanel/margincontainer/vboxcontainer/currencypanel")
			and not src.contains("goldbuttons/"))

	# BOTH PILES ARE WRITTEN.
	var upd: int = _first_code_index(src, "func _update_gold_ui(", 0)
	var upd_end: int = _first_code_index(src, "\nfunc ", upd + 1)
	check("refreshing the gold writes what you carry as well as what is banked",
		upd != -1 and _within(_first_code_index(src, "carry_label.text", upd), upd_end) != -1
			and _within(_first_code_index(src, "gold_label.text", upd), upd_end) != -1)

	# THE GRID: NO SCROLL, NO PARTIAL ROW.
	# THE INVENTORY TOO. Asked for next ("space inventory closer also"), and the
	# two are open side by side whenever you bank, so they are held to the same
	# rule in the same place. Its old fixed 200px scroll height would have left
	# a 20px empty band under a grid that is 180px at the new spacing.
	var grids: Array = [
		["the bank", scene_path, VB + "/bankscroll", VB + "/bankscroll/bankcontainer"],
		["the inventory", "res://scene/ui/inventory/inventory.tscn", VB + "/inventoryscroll",
			VB + "/inventoryscroll/scrollcontent/inventorycontainer"],
	]
	for g in grids:
		check("%s no longer scrolls vertically" % g[0],
			int(_node_prop_or_default(g[1], g[2], "vertical_scroll_mode")) \
				== ScrollContainer.SCROLL_MODE_DISABLED)
	var probe_scroll := ScrollContainer.new()
	probe_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var probe_grid := GridContainer.new()
	probe_grid.columns = 10
	probe_grid.add_theme_constant_override("h_separation", -4)
	probe_grid.add_theme_constant_override("v_separation", -4)
	for _i in range(50):
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(48, 48)
		probe_grid.add_child(cell)
	probe_scroll.add_child(probe_grid)
	add_child(probe_scroll)
	# AT LEAST THE GRID, NOT EXACTLY IT. The first version asserted equality and
	# measured 232 against 224: the ScrollContainer adds its own panel's content
	# margins on top of the child. More than the grid is exactly what "no partial
	# row" needs, so that is the claim.
	var grid_h: float = probe_grid.get_combined_minimum_size().y
	check("five rows of 48px at -4 separation are 224px of grid",
		grid_h == 5 * 48 - 4 * 4, grid_h)
	check("and a ScrollContainer that does not scroll grows to hold all of it",
		probe_scroll.get_combined_minimum_size().y >= grid_h,
		"%s for a %s grid - the engine behaviour this layout rests on" % [
			probe_scroll.get_combined_minimum_size().y, grid_h])
	probe_scroll.queue_free()

	# THE BOXES: -4, BECAUSE THE ART'S TRANSPARENT BORDER IS 4.
	var art: Image = (load("res://art/images/hotbarslot.png") as Texture2D).get_image()
	var used_rect: Rect2i = art.get_used_rect()
	var padding: int = used_rect.position.x
	check("the socket art's transparent border is the same on all four sides",
		used_rect.position.x == used_rect.position.y
			and art.get_width() - used_rect.end.x == padding
			and art.get_height() - used_rect.end.y == padding, used_rect)
	for g in grids:
		var hsep: Variant = _node_prop_in_scene(g[1], g[3], "theme_override_constants/h_separation")
		var vsep: Variant = _node_prop_in_scene(g[1], g[3], "theme_override_constants/v_separation")
		check("%s's boxes sit closer - overlapping only the art's transparent border" % g[0],
			hsep != null and vsep != null and int(hsep) == -padding and int(vsep) == -padding,
			"separation (%s, %s), border %d - any further and one socket covers the next" % [hsep, vsep, padding])

	# AND THE HOTBAR, asked for last ("make hotbar closer"). Same socket art, so
	# the same number - but an HBoxContainer spells it `separation`, not
	# h_/v_separation, so it gets its own line rather than a row in the loop.
	var bar_sep: Variant = _node_prop_in_scene("res://scene/ui/hotbar.tscn", "margin/slots",
		"theme_override_constants/separation")
	check("the hotbar's boxes sit closer too, by the same border",
		bar_sep != null and int(bar_sep) == -padding,
		"separation %s, border %d - the hotbar and the bag should read as one set of slots" % [bar_sep, padding])

	# THE SCROLLBAR, EVERYWHERE.
	var theme: Theme = load("res://assets/themes/rpg_ui_theme.tres") as Theme
	check("scrollbars are themed, not Godot's default grey",
		theme != null and theme.has_stylebox("grabber", &"VScrollBar")
			and theme.has_stylebox("scroll", &"VScrollBar"))

	print("  balance and carry side by side, the buttons by their field, the whole grid on show")


# =============================================================================
# THE GM PANEL IS A WINDOW, AND SAYS WHAT IT DID
# =============================================================================
# Asked for as "gm panel needs a x button to close - can you improve this also",
# and then all four of: results in the panel, drag/resize/stay put, tidy the
# look, tabs instead of scrolling.
#
# THE ONE THAT MATTERED MOST WAS NOT ON SCREEN. Every result - View account, a
# kick, a ban, a rank change, closing the server - went through _say(), which
# printed to the Output console and nowhere else, and only in a debug build. In
# an exported game the panel for acting on other people never said what it had
# done. Everything lands in a results box now.
#
# Instanced for real: its _ready() asks /api/status, which fails quietly with
# no server here, and nothing below depends on the answer.

func _test_the_gm_panel_is_a_window() -> void:
	section("GM PANEL — an x, a window, three tabs, and results on screen")

	var packed: PackedScene = load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene
	check("ownerpanel.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate():
		return
	var panel: Control = packed.instantiate() as Control
	add_child(panel)
	panel.visible = true
	await get_tree().process_frame

	# ---- a window ----
	check("it is attached as a window, so it drags, resizes and remembers",
		panel.get("_window") != null)

	# ---- the x ----
	var close: Button = panel.get_node_or_null("%ownerclosebutton") as Button
	var header: Node = panel.get_node_or_null("frame/margin/rows/headerpanel")
	check("there is an x", close != null)
	check("and it sits in the header, where every other panel keeps its x",
		close != null and header != null and header.is_ancestor_of(close))
	if close != null:
		close.pressed.emit()
	check("pressing it closes the panel", not panel.visible)
	# ESCAPE: in the HUD's one list of windows, closed by its own close() -
	# _test_escape_closes_every_window() presses Escape on it for real.
	var hud_src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/characterhud.gd"))
	check("and Esc closes it too, with the rest",
		_func_body(hud_src, "func _escape_windows(").contains("[owner_panel, \"close\"]"))
	panel.visible = true
	await get_tree().process_frame

	# ---- every node the script reads is in the scene ----
	var script_src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/owner/ownerpanel.gd"))
	# THE TWO WAYS THIS SCRIPT NAMES A NODE: `= %name` and get_node_or_null(
	# "%name"). A bare %name pattern also matches every "%s" and "%d" in the
	# file's format strings, which is noise, not evidence.
	var unique := RegEx.new()
	unique.compile("(?:= %|get_node(?:_or_null)?\\(\"%)([a-z][a-z0-9_]+)")
	var missing: Array[String] = []
	var asked: int = 0
	for m in unique.search_all(script_src):
		var wanted: String = m.get_string(1)
		asked += 1
		if wanted == "inventorycontainer":
			continue  # the HUD's, not this panel's
		if panel.get_node_or_null("%" + wanted) == null:
			missing.append(wanted)
	check("every control the script asks for by name is in the scene",
		missing.is_empty() and asked >= 25, "missing, so silently skipped: %s (%d asked)" % [missing, asked])

	# ---- three tabs, no scrolling ----
	var tabs: TabContainer = panel.get_node_or_null("%ownertabs") as TabContainer
	check("the sections are tabs", tabs != null)
	if tabs == null:
		panel.queue_free()
		return
	var titles: Array[String] = []
	for i in tabs.get_tab_count():
		titles.append(tabs.get_tab_title(i))
	# AND WORLD (0.46.0): the stirring lands' switches (worldtab.gd); AND
	# EVENTS (0.48.0), the world's events (eventstab.gd).
	# AND ECONOMY (0.74.0): the gold flow, the economy's numbers and the canary
	# (economytab.gd). AND HEALTH (0.78.0): the live server and the kill
	# receipts (healthtab.gd).
	check("Account, Testing, Server, World, Events, Economy and Health",
		titles == ["Account", "Testing", "Server", "World", "Events", "Economy", "Health"], titles)
	check("sized to the tallest tab, so switching never resizes the window",
		tabs.use_hidden_tabs_for_min_size)
	# OWNED ONLY: an OptionButton's popup carries a ScrollContainer of its own,
	# which is the engine's and not this scene's.
	#
	# ONE EXCEPTION, AND ONLY ONE: the list of who is online (0.7.4). It is as
	# long as the server is busy - up to ONLINE_LIST_LIMIT, sixty - so it is the
	# one thing here that cannot be laid out to fit. Every other control still
	# must, and the window still holds its tallest tab without growing.
	#
	# AND THE TABS' OWN SCROLL (0.8.0), which scrolls only when the window
	# would pass the screen - at the largest text size - and is otherwise as
	# tall as the tabs (PanelWindow.keep_scroll_fitted()).
	var scrollers: Array = panel.find_children("*", "ScrollContainer", true, true)
	var others: Array = scrollers.filter(func(n: Node) -> bool:
		return n.name != "onlinescroll" and n.name != "tabsscroll")
	check("and nothing in it scrolls but the list of who is online", others.is_empty()
		and scrollers.size() == 2, "%d ScrollContainer(s)" % scrollers.size())
	check("  and the tabs, only when the window would pass the screen",
		panel._window._scrolls.has(panel.get_node("%tabsscroll")))

	var mins: Array[float] = []
	var cut: Array[String] = []
	for i in tabs.get_tab_count():
		tabs.current_tab = i
		await get_tree().process_frame
		mins.append(PanelWindow.content_minimum(panel).y)
		# A HINT THAT IS CUT OFF is not a hint. Measured with the box's own
		# font, size and padding, on the tab that is actually showing.
		for edit in tabs.get_current_tab_control().find_children("*", "LineEdit", true, true):
			var line: LineEdit = edit as LineEdit
			if line.placeholder_text == "" or not line.is_visible_in_tree():
				continue
			var font: Font = line.get_theme_font("font")
			var fsize: int = line.get_theme_font_size("font_size")
			var box: StyleBox = line.get_theme_stylebox("normal")
			var room: float = line.size.x - (box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT) if box != null else 0.0)
			var need: float = font.get_string_size(line.placeholder_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
			if need > room:
				cut.append("%s: '%s' needs %d, has %d" % [line.name, line.placeholder_text, need, room])
	check("the window is the same height on every tab", mins.max() == mins.min(), mins)
	check("no input's hint is cut off", cut.is_empty(), cut)
	tabs.current_tab = 0

	# THE AUTHORED RECTANGLE ALREADY HOLDS THE TALLEST TAB, so the panel opens at
	# its drawn size rather than being grown by PanelWindow on first show - and
	# it clears the menu bar along the bottom of a 1280x720 screen.
	# READ FROM THE SCENE, not the live node: PanelWindow may have restored a
	# rectangle saved by an earlier run, and that is not what a new player gets.
	var need_h: float = PanelWindow.content_minimum(panel).y
	var top: float = 0.0
	var bottom: float = 0.0
	var root_state: SceneState = packed.get_state()
	for p in root_state.get_node_property_count(0):
		match root_state.get_node_property_name(0, p):
			"offset_top":
				top = float(root_state.get_node_property_value(0, p))
			"offset_bottom":
				bottom = float(root_state.get_node_property_value(0, p))
	var authored_h: float = bottom - top
	check("its default size holds its tallest tab",
		authored_h + 0.5 >= need_h, "authored %d, needs %d" % [authored_h, need_h])
	check("and it opens clear of the menu bar", bottom <= 720.0 - 76.0, bottom)

	# ---- tidy: no button left on the engine's default look ----
	# THE STYLE THE BUTTON ENDS UP WITH, not whether it carries an override.
	# Since day 1 the staff theme dresses them, and an override per button is
	# exactly what would stop a theme change reaching them.
	var engine_button: StyleBox = ThemeDB.get_default_theme().get_stylebox("normal", "Button")
	var plain: Array[String] = []
	for node in panel.find_children("*", "Button", true, true):
		if node is CheckButton or node is OptionButton:
			continue
		var worn: StyleBox = (node as Button).get_theme_stylebox("normal")
		if worn == null or worn == engine_button:
			plain.append(String(node.name))
	check("every button wears the panel's style", plain.is_empty(), plain)

	# ---- results on screen ----
	var results: RichTextLabel = panel.get_node_or_null("%ownerresults") as RichTextLabel
	check("there is a results box", results != null)
	if results != null:
		panel._say("[GM] signed 'probe' out of 2 place(s).", panel.SAY_GOOD)
		var shown: String = results.get_parsed_text()
		check("a result lands in the box", shown.contains("signed 'probe' out"), shown)
		check("without the console's tag", not shown.contains("[GM]"), shown)
		panel._say("[b]not bold[/b] from a username")
		check("and a name or an error is text, never markup",
			results.get_parsed_text().contains("[b]not bold[/b]"), results.get_parsed_text())
		# NOT ONLY IN A DEBUG BUILD. The suite always runs one, so a behavioural
		# check cannot see the guard that made the old panel silent in an export.
		# The write has to sit outside it, at the function's own indentation.
		var say_at: int = _first_code_index(script_src, "func _say(", 0)
		var say_end: int = _first_code_index(script_src, "\nfunc ", say_at + 1)
		check("and it is written in every build, not just a debug one",
			_within(_first_code_index(script_src, "\n\t_write(line, colour)", say_at), say_end) != -1)

		# THE QUICK ANSWERS TOO. The Testing tab and the teleport row had labels
		# of their own that grew the tab past its window whenever they spoke;
		# they write here now.
		panel._set_testing_status("Added 1 x probeitem to your bag.")
		panel._set_teleport_status("[GM] type a username first.")
		check("the Testing tab's answers land in the box too",
			results.get_parsed_text().contains("Added 1 x probeitem"))
		check("and so do the teleport row's",
			results.get_parsed_text().contains("type a username first."))
		panel._print_save_summary("probe", {"username": "probe", "role": "mod",
			"characters": [], "kills": []})
		shown = results.get_parsed_text()
		check("an account view appears in the box", shown.contains("rank      : mod"), shown)
		check("AFTER what was already there - a rank change's confirmation survives the view it triggers",
			shown.contains("signed 'probe' out") and shown.find("signed 'probe' out") < shown.find("rank      : mod"))
		var clear: Button = panel.get_node_or_null("%ownerresultsclear") as Button
		if clear != null:
			clear.pressed.emit()
		check("and Clear empties it", results.get_parsed_text().strip_edges() == "",
			results.get_parsed_text())

	panel.queue_free()
	await get_tree().process_frame
	print("  a window with an x, three tabs, and a results box instead of the console")


# =============================================================================
# NOTICES FADE, AND LOGGING IN IS QUIET
# =============================================================================
# Reported with a screenshot of five lines parked above the menu bar - "The
# server is open again", "Update in progress", "Everyone has been moved to
# elusion" twice - and "we need a way to hide this so it's not distracting".
#
# TWO DEFECTS MADE THAT PICTURE, and the comments described neither:
#
#   The box never faded. Every comment about it said it did; nothing did. A
#   line left only when a newer one pushed it off the top.
#
#   Logging in announced a week. The first poll asks since=0 and gets the
#   recent TAIL, and every entry in it popped the box as if it were news.
#
# And a third, found on the way: "the log always gets it" was only true once
# chat had been opened, because chat is built on first use. Before that a
# notice that faded was gone. So the fade could not be added without first
# making sure fading loses nothing.
#
# Driven on a bare HUD instance, never added to the tree - _ready() would start
# polling a server. _age_messages() takes its clock as an argument, so a line
# ages ten seconds without the suite waiting ten seconds.
