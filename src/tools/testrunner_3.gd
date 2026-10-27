# testrunner_3.gd - part 3 of the suite (testrunner.gd says how it is
# split): 22 tests, _test_the_shop_gives_the_mythics_away to _test_the_hotbar_grows_for_thumbs.
extends "res://src/tools/testrunner_2.gd"


# =============================================================================
# THE SHOP GIVES THE MYTHICS AWAY (0.69.0)
# =============================================================================
# The owner: "add mythic weapons to the shop marked as free so new players can
# use free"; asked how, "Real ones, free, any level". The general store lists
# each class's mythic under Free, worn from level 1. The rules are the
# server's - one each, the plain catalogue piece, never sold or traded - and
# the panel shows them first, says Free and Take, and leaves the free piece off
# the Sell list while a rolled one (a drop) still sells.
func _test_the_shop_gives_the_mythics_away() -> void:
	section("SHOP - the mythic weapons are free: one each, from level 1, kept not sold")

	var store: ShopData = load("res://data/shops/generalstore.tres") as ShopData
	var free: Array = Array(store.free) if store != null else []
	check("the general store gives away the Meteorite, the Double Axe and Dynamite",
		free == ["meteorite", "doubleaxe", "dynamite"], free)
	var both: Array = free.filter(func(id: String) -> bool: return Array(store.stock).has(id))
	check("  and sells none of them for gold: one item, one price", both.is_empty(), both)

	var exported_shop: Dictionary = {}
	var exported_items: Dictionary = {}
	for shop in _load_gamedata().get("shops", []):
		if shop is Dictionary and str(shop.get("shop_id", "")) == "generalstore":
			exported_shop = shop
	for row in _load_gamedata().get("items", []):
		if row is Dictionary:
			exported_items[str(row.get("item_id", ""))] = row
	check("  gamedata.json gives away the same (re-run the exporter if not)",
		Array(exported_shop.get("free", [])) == free, exported_shop.get("free", "no free list"))
	var classes: Array = []
	var gated: Array = []
	for id in free:
		var row: Dictionary = exported_items.get(id, {})
		classes.append_array(Array(row.get("required_classes", [])))
		if int(row.get("required_level", 0)) != 1 or int(row.get("tier", 0)) != 6:
			gated.append([id, row.get("required_level", -1), row.get("tier", -1)])
	check("  each a mythic worn from level 1, in the server's catalogue too", gated.is_empty(), gated)
	classes.sort()
	check("  one for each class that has one - the healer has none yet",
		classes == ["mage", "tank", "warrior"], classes)

	# THE PANEL, drawn from an answer in the server's shape: what it gives away
	# first, flagged free, at no price.
	var panel: Node = (load("res://scene/ui/shop/shopinventory.tscn") as PackedScene).instantiate()
	add_child(panel)
	var rows: Array = []
	for id in free:
		var item: Dictionary = exported_items.get(id, {})
		rows.append({"item_id": id, "display_name": str(item.get("display_name", id)), "price": 0,
			"free": true, "tier": 6, "type_name": "WEAPON", "required_level": 1,
			"required_classes": Array(item.get("required_classes", []))})
	rows.append({"item_id": "tinyhealthpotion", "display_name": "Tiny Health Potion", "price": 20,
		"tier": 1, "type_name": "CONSUMABLE", "required_level": 1, "required_classes": []})
	panel.show_catalogue({"display_name": "Kingdom Supplies", "stock": rows, "free_ids": free,
		"sell_multiplier": 0.05, "sell_prices": {"meteorite": 1900, "zz_free_potion": 1}})
	var order: Array = []
	for child in panel.stock_list.get_children():
		order.append(child.text if child is Label else str(child.name))
	check("the free shelf comes first, headed with the rule, then the shop's own stock",
		order == [panel.FREE_SHELF_TITLE, "free_meteorite", "free_doubleaxe", "free_dynamite",
			"Potions and supplies", "stock_tinyhealthpotion"], order)
	check("  and the heading says it cannot be sold or traded",
		String(panel.FREE_SHELF_TITLE).contains("cannot be sold or traded"), panel.FREE_SHELF_TITLE)
	var axe: Node = panel.stock_list.get_node_or_null("free_doubleaxe")
	var potion_row: Node = panel.stock_list.get_node_or_null("stock_tinyhealthpotion")
	check("  a free row is priced Free and taken with Take",
		axe != null and (axe.get_node("price") as Label).text == "Free"
		and (axe.get_node("buy") as Button).text == "Take",
		[(axe.get_node("price") as Label).text, (axe.get_node("buy") as Button).text] if axe != null else [])
	check("  and a row for gold is as it was",
		potion_row != null and (potion_row.get_node("price") as Label).text == "20 g"
		and (potion_row.get_node("buy") as Button).text == "Buy")

	# THE SELL LIST: the plain piece is the shop's gift and stays; a rolled one
	# is a drop and sells at the base piece's price, as before.
	# A stand-in potion: the real ones' pictures are in the private pack, which
	# a clone does not have. The mythics' are not.
	var potion: ItemData = _menu_item("zz_free_potion", ItemData.Type.CONSUMABLE, 0, 20)
	ItemRegistry._items[potion.item_id] = potion
	var bag := InventoryContainer.new()
	bag.is_carry = true
	add_child(bag)
	bag.load_save_array([{"item_id": "meteorite", "quantity": 1},
		{"item_id": "meteorite~d104p96", "quantity": 1}, {"item_id": "zz_free_potion", "quantity": 3}])
	panel.inventory_override = bag
	panel.set_mode("sell")
	var selling: Array = []
	for child in panel.stock_list.get_children():
		selling.append(str(child.name))
	check("Sell leaves out the free Meteorite and lists the dropped one and the potions",
		selling == ["sell_1", "sell_2"], selling)

	var Shop: GDScript = load("res://src/ui/shop/shopinventory.gd") as GDScript
	var meteorite: ItemData = ItemRegistry.get_item("meteorite")
	check("taking one says it is free and what that means",
		Shop.purchase_line(meteorite, "meteorite", 0)
		== "You took a free Meteorite. It is yours to keep: it cannot be sold or traded.",
		Shop.purchase_line(meteorite, "meteorite", 0))
	check("  and buying for gold reads as it did",
		Shop.purchase_line(potion, "zz_free_potion", 20).begins_with("Bought "))

	panel.queue_free()
	bag.queue_free()
	ItemRegistry._items.erase(potion.item_id)
	print("  the store gives each class its mythic, once, and the Sell list keeps it")


# =============================================================================
# THE BOSS GATES: a lever on each side, and on means open
# =============================================================================
# The owner, 5 Oct: "set up that lever to release the 3 gates by boss exit".
# The Field's three spike gates stand between the field and the ladder down to
# the bosses, and coming back up lands you inside them - so a lever outside
# opens the way down and one by the ladder means nobody is shut in. Both drive
# the same three gates and always read the same.
func _test_the_boss_gates_lever() -> void:
	section("THE BOSS GATES - a lever on each side, and on means open")

	# ---- the levers themselves, on doors the suite builds ---------------------
	var room := Node2D.new()
	room.name = "leverroom"
	var doors: Array = []
	for i in 4:
		var door: Node = (load("res://scene/interactables/spikedoor.tscn") as PackedScene).instantiate()
		door.name = "door%d" % i
		door.position = Vector2(32 * i, 0)
		room.add_child(door)
		doors.append(door)
	var make := func(lever_name: String, paths: Array[NodePath], flip: bool) -> Node:
		var lever: Node = (load("res://scene/interactables/lever.tscn") as PackedScene).instantiate()
		lever.name = lever_name
		lever.targets = paths
		lever.inverted = flip
		lever.starts_on = flip
		lever.throw_seconds = 0.01
		room.add_child(lever)
		return lever
	var three: Array[NodePath] = [NodePath("../door0"), NodePath("../door1"), NodePath("../door2")]
	var first: Array[NodePath] = [NodePath("../door0")]
	var last: Array[NodePath] = [NodePath("../door3")]
	var outside: Node = make.call("outside", three, false)
	var inside: Node = make.call("inside", three, false)
	# The same door from the other side of a wall: inverted, and started on so
	# it agrees with the gates being up.
	var flipped: Node = make.call("flipped", first, true)
	var elsewhere: Node = make.call("elsewhere", last, false)
	add_child(room)
	await get_tree().process_frame
	await get_tree().process_frame
	var up := func() -> Array:
		return doors.map(func(d): return d.is_raised())
	check("a lever left alone keeps its gates up - on means open",
		up.call() == [true, true, true, true] and not outside.is_on() and not inside.is_on(), up.call())
	outside.throw()
	await get_tree().create_timer(0.1).timeout
	check("pulling the outside lever drops all three", up.call().slice(0, 3) == [false, false, false], up.call())
	check("  and the lever by the ladder now reads open too",
		outside.is_on() and inside.is_on(), [outside.is_on(), inside.is_on()])
	check("  an inverted lever on one of them follows the other way round",
		flipped.is_on() == false, flipped.is_on())
	check("  and a lever on a different door is left alone",
		elsewhere.is_on() == false and doors[3].is_raised(), [elsewhere.is_on(), doors[3].is_raised()])
	inside.throw()
	await get_tree().create_timer(0.1).timeout
	check("pulling the inside one raises them again, and every lever on them agrees",
		up.call().slice(0, 3) == [true, true, true] and not outside.is_on() and not inside.is_on()
		and flipped.is_on(), [up.call(), outside.is_on(), inside.is_on(), flipped.is_on()])
	room.queue_free()

	# ---- the Field: where they are and what they drive ------------------------
	# READ AS TEXT, as the amulet checks read their .tres: the Field is a big
	# scene, and every number under test is in the file.
	var text: String = FileAccess.get_file_as_string("res://scene/field.tscn")
	var nodes: Dictionary = {}
	var current: String = ""
	for line in text.split("\n"):
		if line.begins_with("[node "):
			var at: int = line.find("name=\"") + 6
			current = line.substr(at, line.find("\"", at) - at)
			nodes[current] = {"header": line}
		elif current != "" and line.contains(" = "):
			var key: String = line.substr(0, line.find(" = "))
			nodes[current][key] = line.substr(line.find(" = ") + 3)
	var where := func(node_name: String) -> Vector2:
		var raw: String = str(nodes.get(node_name, {}).get("position", ""))
		var nums: PackedStringArray = raw.trim_prefix("Vector2(").trim_suffix(")").split(",")
		return Vector2(float(nums[0]), float(nums[1])) if nums.size() == 2 else Vector2.INF
	var gates: Array = ["spikedoor", "spikedoor2", "spikedoor3"]
	var wanted: String = "Array[NodePath]([NodePath(\"../../../spikedoor\"), NodePath(\"../../../spikedoor2\"), NodePath(\"../../../spikedoor3\")])"
	check("the Field has its three gates and two levers",
		gates.all(func(g): return nodes.has(g)) and nodes.has("levergatesout") and nodes.has("levergatesin"),
		nodes.keys().filter(func(k): return k.begins_with("lever") or k.begins_with("spikedoor")))
	check("  both levers drive exactly the three gates",
		str(nodes.get("levergatesout", {}).get("targets", "")) == wanted
		and str(nodes.get("levergatesin", {}).get("targets", "")) == wanted,
		[nodes.get("levergatesout", {}).get("targets", ""), nodes.get("levergatesin", {}).get("targets", "")])
	check("  under the interactables, so the paths up to the gates are right",
		str(nodes.get("levergatesout", {}).get("header", "")).contains("parent=\"ysortworld/interactables\"")
		and str(nodes.get("levergatesin", {}).get("header", "")).contains("parent=\"ysortworld/interactables\"")
		and gates.all(func(g): return str(nodes[g]["header"]).contains("parent=\".\"")))
	var top: float = INF
	var bottom: float = -INF
	for g in gates:
		top = minf(top, where.call(g).y)
		bottom = maxf(bottom, where.call(g).y)
	check("  one outside the gates, on the field's side, and one inside by the ladder",
		where.call("levergatesout").y < top - 16 and where.call("levergatesin").y > bottom + 16
		and where.call("ladderdown").y > bottom,
		[where.call("levergatesout"), where.call("levergatesin"), top, bottom])
	# THE LADDER IS A WALK-IN, so a lever whose reach touched it could drop a
	# player into the boss arena on the way to pulling it. Lever reach 24, the
	# ladder's 16, a body's 8.
	check("  and the inside lever is out of the ladder's reach",
		where.call("levergatesin").distance_to(where.call("ladderdown")) > 24 + 16 + 8,
		where.call("levergatesin").distance_to(where.call("ladderdown")))
	check("  and the gates start up: nothing in the scene starts a lever on or a gate down",
		not text.contains("starts_on = true") and not text.contains("starts_raised = false"))
	print("  the boss gates open from either side, and both levers say so")


# =============================================================================
# QUALITY ROLLS: a dropped piece's stats, read from its id the server's way
# =============================================================================
# The owner, 5 Oct: random stats on every item, "because it gives loot a
# better value if a rare max roll". Each stat a dropped piece has rolls on its
# own, 85-115%, and one drop in a hundred is Perfect at 120%. The roll is part
# of the item id ("jadechest~a104h96"); the server rolls it and ItemRegistry
# reads it. test_quality.py in the API is the other half, and both hold the
# same rounding table, because the server derives max health from the very
# numbers ItemRegistry hands to the player.
# =============================================================================
# ARMOUR RESISTS AN ELEMENT (0.11.0)
# =============================================================================
# The owner, 7 Oct: "add resistance to armor with a ? random roll also in the
# shop", "i want elements to do something" - and of weapons, "the main goal
# should be to keep players damage consistent with attack level and gear". So
# every piece of armour rolls one of the seven lands' elements and a percent,
# the last part of its rolled id ("r605": fire, 5%); matching pieces add up to
# RESIST_CAP and take that share off a hit of their element. No weapon ever
# resists, and nothing about a player's own damage changes.
func _test_stirring_lands() -> void:
	section("THE STIRRING LANDS - one land stirs at a time: its monsters hit harder, resistance to it counts more (0.46.0)")
	# The owner: "lets build it in my game if you think it will elavate it",
	# and of the effects, "just make those switches in my gm panel under a new
	# tab that can be adjusted". test_world.py holds the server: the ticks, the
	# pick, the loot and XP it pays, the owner's routes.
	Lands.clear()
	var now: int = int(Time.get_unix_time_from_system())
	var fire: Dictionary = {"on": true, "tick": 12, "element": Element.Type.FIRE, "name": "fire",
		"started_at": now - 600, "ends_at": now + 2 * 3600 + 14 * 60 + 30, "hit": 0.25, "resist": 1.5,
		"bags": 1.5, "xp": 0.0, "health": 0.5, "speed": 0.15, "now": now}

	# ---- what the poll says ------------------------------------------------------
	var began: bool = Lands.apply(fire)
	check("the poll's world: fire stirs, stir 12, with its numbers - and that is a new stir",
		began and Lands.stirring() == Element.Type.FIRE and Lands.tick == 12 and is_equal_approx(Lands.hit, 0.25)
		and is_equal_approx(Lands.resist, 1.5) and is_equal_approx(Lands.bags, 1.5) and Lands.xp == 0.0
		and is_equal_approx(Lands.health, 0.5) and is_equal_approx(Lands.speed, 0.15))
	check("  the same stir heard again is not new", not Lands.apply(fire))
	var next_tick: Dictionary = fire.duplicate()
	next_tick["tick"] = 13
	check("  the same land as a new stir is", Lands.apply(next_tick))
	check("the line on the HUD counts down on the server's clock",
		Lands.line() == "The Fire lands stir - 2h 14m left", Lands.line())
	check("  and what it does, in words, from the numbers sent",
		Lands.effects_line() == "Fire monsters hit 25% harder, have 50% more health, move 15% faster and drop loot 1.5x as often; fire resistance counts 1.5x.",
		Lands.effects_line())
	check("time left reads as people say it",
		Lands.time_text(30) == "under a minute" and Lands.time_text(14 * 60) == "14m"
		and Lands.time_text(3 * 3600 + 5 * 60) == "3h 05m")
	var wild: Dictionary = fire.duplicate()
	wild["hit"] = 9.0
	wild["resist"] = 0.1
	wild["bags"] = "lots"
	wild["health"] = 9.0
	wild["speed"] = "fast"
	Lands.apply(wild)
	check("numbers out of their range are held to it; one of the wrong kind is the plain default",
		is_equal_approx(Lands.hit, 1.0) and is_equal_approx(Lands.resist, 1.0) and is_equal_approx(Lands.bags, 1.0)
		and is_equal_approx(Lands.health, 2.0) and Lands.speed == 0.0)
	for junk in [null, "fire", {}, {"element": 8}, {"element": 0}, {"element": "6"}, {"element": 99}]:
		Lands.apply(fire)
		Lands.apply(junk)
		check("  %s: nothing stirs" % JSON.stringify(junk), Lands.stirring() == 0 and Lands.line() == "")
	var stale: Dictionary = fire.duplicate()
	stale["ends_at"] = now - Lands.STALE_SECONDS - 5
	Lands.apply(stale)
	check("a stir past its end with no word from the server is over: a world that cannot be heard never makes it harder",
		Lands.stirring() == 0 and is_equal_approx(Lands.hit_scale(Element.Type.FIRE), 1.0))

	# ---- the hit ---------------------------------------------------------------------
	var made: Array = []
	var chest: ItemData = _menu_item("ltest_chest", ItemData.Type.ARMOR, ItemData.EquipSlot.CHEST)
	chest.tier = 5
	chest.armor_value = 4
	made.append(chest)
	var helm: ItemData = _menu_item("ltest_helm", ItemData.Type.ARMOR, ItemData.EquipSlot.HELM)
	helm.tier = 5
	helm.armor_value = 2
	made.append(helm)
	for item in made:
		ItemRegistry._items[item.item_id] = item
	var body: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	body._set_stat_curve()
	body.level = 10
	body.equipped = {"chest": "ltest_chest~a100r610"}
	Lands.clear()
	var calm_fire: int = body.damage_taken(1000, Element.Type.FIRE)
	var calm_water: int = body.damage_taken(1000, Element.Type.WATER)
	var reduction: float = body._get_defense_tier()["reduction"]
	var armour: float = PlayerStats.armour_reduction(body.equipped_armor_value())
	Lands.apply(fire)
	var stirred_fire: int = body.damage_taken(1000, Element.Type.FIRE)
	check("fire stirring: a fire hit lands 25%% harder, and 10%% fire resistance counts as 15%% (%d, calm %d)" % [stirred_fire, calm_fire],
		stirred_fire == maxi(1, int(1250.0 * (1.0 - reduction) * (1.0 - armour) * 0.85))
		and calm_fire == maxi(1, int(1000.0 * (1.0 - reduction) * (1.0 - armour) * 0.90)), [stirred_fire, calm_fire])
	check("  a water hit is as it was - only the stirring land's", body.damage_taken(1000, Element.Type.WATER) == calm_water)
	check("  and a physical hit too", is_equal_approx(Lands.hit_scale(Element.Type.NONE), 1.0)
		and is_equal_approx(Lands.resist_scale(Element.Type.NONE), 1.0))
	var capped: Dictionary = fire.duplicate()
	capped["resist"] = 2.0
	Lands.apply(capped)
	body.equipped = {"chest": "ltest_chest~a100r613", "helm": "ltest_helm~a100r613"}
	check("resistance counting double is still held to the 50%% cap: 26%% twice is 50%%, not 52%% (%d)" % body.equipped_resistance(Element.Type.FIRE),
		body.equipped_resistance(Element.Type.FIRE) == 26
		and body.damage_taken(1000, Element.Type.FIRE) == maxi(1, int(1250.0 * (1.0 - reduction)
			* (1.0 - PlayerStats.armour_reduction(body.equipped_armor_value())) * 0.5)))
	var src: String = _code_src("res://src/characters/player.gd")
	check("  and take_damage() still trains defense on the hit as sent, not the stirred one",
		_func_body(src, "func take_damage(").contains("gain_defense_xp(maxi(1, amount / 2))"))
	body.free()
	for item in made:
		ItemRegistry._items.erase(item.item_id)

	# ---- the monsters: tougher, faster, and glowing ------------------------------------
	# The owner: "i did not notice dps change on enemies or anything".
	Lands.apply(fire)
	check("a fire monster of 100 health is born with 150 while fire stirs; a water one, and any while nothing stirs, as it was",
		Lands.raised_max_hp(100, Element.Type.FIRE) == 150 and Lands.raised_max_hp(100, Element.Type.WATER) == 100
		and Lands.raised_max_hp(100, Element.Type.NONE) == 100
		and is_equal_approx(Lands.speed_scale(Element.Type.FIRE), 1.15) and is_equal_approx(Lands.speed_scale(Element.Type.WATER), 1.0))
	var arena := Node2D.new()
	add_child(arena)
	var monster_at := func(scene: String, offset: Vector2) -> BaseEnemy:
		var e: BaseEnemy = (load(scene) as PackedScene).instantiate()
		e.position = Vector2(-81000, -81000) + offset
		arena.add_child(e)
		e.set_physics_process(false)
		return e
	Lands.clear()
	var standing: BaseEnemy = monster_at.call("res://scene/enemy/firesprite.tscn", Vector2(120, 0))
	var calm_max: int = standing.max_hp
	var stirred_max: int = calm_max + roundi(calm_max * 0.5)
	standing.hp = calm_max - 10
	Lands.apply(fire)
	check("a stir that begins while a fire sprite stands raises it then: half again its maximum, added to what it had left (%d of %d)" % [standing.hp, standing.max_hp],
		standing.max_hp == stirred_max and standing.hp == stirred_max - 10 and standing.stir_raised, [standing.hp, standing.max_hp])
	Lands.apply(next_tick)
	check("  once - the same land stirring again adds nothing more", standing.max_hp == stirred_max)
	var born_fire: BaseEnemy = monster_at.call("res://scene/enemy/firesprite.tscn", Vector2.ZERO)
	var born_water: BaseEnemy = monster_at.call("res://scene/enemy/watersprite.tscn", Vector2(60, 0))
	var water_alone: BaseEnemy = (load("res://scene/enemy/watersprite.tscn") as PackedScene).instantiate()
	var water_data_max: int = (water_alone.get("enemy_data") as EnemyData).max_hp if water_alone.get("enemy_data") != null else -1
	water_alone.free()
	check("born while fire stirs: a fire sprite has half again its health, full; a water sprite as it was",
		born_fire.max_hp == stirred_max and born_fire.hp == stirred_max and born_fire.stir_raised
		and born_water.max_hp == water_data_max and not born_water.stir_raised, [born_fire.max_hp, born_water.max_hp, water_data_max])
	check("  and the books are sent that health (\"mh\"), which they take for a stirring land's monster (combatbook.py)",
		_func_body(_code_src("res://src/world/monstersync.gd"), "func record_of(").contains("\"mh\": e.max_hp"))
	check("  it moves 15% faster (stir_speed()), and every velocity in BaseEnemy and BushMage is multiplied by it",
		is_equal_approx(born_fire.stir_speed(), 1.15) and is_equal_approx(born_water.stir_speed(), 1.0)
		and _code_src("res://src/enemies/baseenemy.gd").count("* stir_speed()") == 4
		and _code_src("res://src/enemies/bushmage.gd").contains("get_move_speed() * stir_speed()"))
	await get_tree().process_frame
	var glow: StirGlow = born_fire.get_node_or_null(^"stirglow") as StirGlow
	var water_glow: StirGlow = born_water.get_node_or_null(^"stirglow") as StirGlow
	check("it glows in fire's colour, under everything it draws; the water sprite does not",
		glow != null and glow.visible and glow.get_index() == 0 and glow.colour.is_equal_approx(Element.colour_for(Element.Type.FIRE).lightened(0.25))
		and water_glow != null and not water_glow.visible, [glow != null and glow.visible, water_glow != null and water_glow.visible])
	Lands.apply({"on": false, "tick": 0, "element": 0})
	await get_tree().process_frame
	check("the stir over: never lowered (the books count a death at the health they were told), no faster, no glow",
		standing.max_hp == stirred_max and born_fire.max_hp == stirred_max and is_equal_approx(standing.stir_speed(), 1.0)
		and not glow.visible)
	var copy: BaseEnemy = monster_at.call("res://scene/enemy/firesprite.tscn", Vector2(180, 0))
	copy.net_apply_state(copy.global_position, "", calm_max + 40)
	check("a follower's copy told of more health than it knew takes the leader's word for its maximum",
		copy.max_hp == calm_max + 40 and copy.hp == calm_max + 40, [copy.hp, copy.max_hp])
	arena.queue_free()
	await get_tree().process_frame
	var PlayerScript := preload("res://src/characters/player.gd")
	var player_src: String = _code_src("res://src/characters/player.gd")
	check("a hit the stir made harder is drawn bigger on the player (%sx)" % str(PlayerScript.STIRRED_NUMBER_SCALE),
		PlayerScript.STIRRED_NUMBER_SCALE > 1.0
		and _func_body(player_src, "func _spawn_floating_label(").contains("Lands.hit_scale(element) > 1.0")
		and _func_body(player_src, "func _spawn_floating_label(").contains("STIRRED_NUMBER_SCALE if stirred else 1.0"))

	# ---- the HUD ---------------------------------------------------------------------
	Lands.clear()
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await get_tree().process_frame
	var kept_cursor: int = hud._broadcast_cursor
	hud._broadcast_cursor = 0
	hud._apply_broadcast({"messages": [{"id": 5, "kind": "world", "body": "The fire lands stir for 3 hours.", "at": now}],
		"latest_id": 5, "world": fire})
	var chip: PanelContainer = hud.world_chip
	check("logging in during a stir: the line under the top of the screen, in fire's colour, and no banner",
		chip != null and chip.visible and hud.world_label.text == "The Fire lands stir - 2h 14m left"
		and hud.world_label.get_theme_color("font_color").is_equal_approx(Element.colour_for(Element.Type.FIRE).lightened(0.35))
		and (hud.mythic_banner == null or not is_instance_valid(hud.mythic_banner)), hud.world_label.text if hud.world_label else "")
	var water: Dictionary = fire.duplicate()
	water["tick"] = 14
	water["element"] = Element.Type.WATER
	water["name"] = "water"
	hud._apply_broadcast({"messages": [{"id": 6, "kind": "world", "body": "The water lands stir for 3 hours.", "at": now}],
		"latest_id": 6, "world": water})
	var banner: Node = hud.mythic_banner
	var title: Label = banner.find_child("title", true, false) as Label if banner != null and is_instance_valid(banner) else null
	check("a new stir while playing: a banner across the top in water's colour, saying what it does",
		title != null and title.text == "THE WATER LANDS STIR"
		and title.get_theme_color("font_color").is_equal_approx(Element.colour_for(Element.Type.WATER).lightened(0.35))
		and (banner.find_child("line", true, false) as Label).text.begins_with("Water monsters hit 25% harder"),
		title.text if title else "no banner")
	check("  and the line follows it", hud.world_label.text.begins_with("The Water lands stir"))
	hud.set_world_status("pvp", "PvP is ON")
	check("with the status strip up, the line sits under it",
		hud.status_strip.visible and is_equal_approx(chip.offset_top, 50.0))
	hud.set_world_status("pvp", "")
	check("  and goes back up when it is gone", is_equal_approx(chip.offset_top, 10.0))
	hud._apply_broadcast({"messages": [], "latest_id": 6, "world": {"on": false, "tick": 0, "element": 0}})
	var still_banner: Node = hud.mythic_banner
	var still_title: Label = still_banner.find_child("title", true, false) as Label \
		if still_banner != null and is_instance_valid(still_banner) else null
	check("the lands switched off: the line is gone, and a banner says so in the colour of the land that was stirring",
		not chip.visible and Lands.stirring() == 0 and still_title != null and still_title.text == "THE LANDS GROW STILL"
		and still_title.get_theme_color("font_color").is_equal_approx(Element.colour_for(Element.Type.WATER).lightened(0.35))
		and (still_banner.find_child("line", true, false) as Label).text == "The Water lands are calm again.",
		still_title.text if still_title else "no banner")
	if still_banner != null and is_instance_valid(still_banner):
		still_banner.free()
	hud.mythic_banner = null
	hud._apply_broadcast({"messages": [], "latest_id": 6, "world": water})
	hud.mythic_banner.free()
	hud.mythic_banner = null
	hud._apply_broadcast({"messages": [], "latest_id": 6})
	check("  but a server that goes quiet ends it with no banner - that is not news",
		Lands.stirring() == 0 and hud.mythic_banner == null)
	hud._apply_broadcast({"messages": [], "latest_id": 6})
	check("  and a server from before them says nothing, and nothing stirs", not chip.visible and Lands.stirring() == 0)
	var hud_src: String = _code_src("res://src/ui/characterhud.gd")
	check("the world is read from the poll before its messages (so they are in the land's colour)",
		_func_body(hud_src, "func _apply_broadcast(").find("_read_world(") != -1
		and _func_body(hud_src, "func _apply_broadcast(").find("_read_world(")
			< _func_body(hud_src, "func _apply_broadcast(").find("_read_broadcast_messages("))
	hud._broadcast_cursor = kept_cursor
	hud.queue_free()
	await get_tree().process_frame

	# ---- the GM panel's World tab -----------------------------------------------------
	var was_owner: bool = Api.is_owner
	Api.is_owner = true
	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var tabs: TabContainer = gm.get_node_or_null("%ownertabs") as TabContainer
	var tab: WorldTab = gm.get("world_tab") as WorldTab
	check("the GM panel has a World tab, after Server",
		tabs != null and tab != null and tab.get_parent() == tabs and tabs.get_tab_title(tab.get_index()) == "World"
		and tabs.get_tab_title(tab.get_index() - 1) == "Server")
	if tabs != null and tab != null:
		tabs.current_tab = tab.get_index()
		await get_tree().process_frame
	var wide: float = PanelWindow.content_minimum(gm).x
	check("  and it fits the panel's drawn width (370) - the GM panel is narrow (%d)" % wide, wide <= 370.0, wide)
	var asked: Array = []
	var sent: Array = []
	var view: Variant = JSON.parse_string(JSON.stringify({
		"settings": {"on": true, "hours": 3, "hit_on": true, "hit_percent": 25, "health_on": true, "health_percent": 50,
			"speed_on": true, "speed_percent": 15, "bags_on": true, "bags_times": 1.5,
			"resist_on": true, "resist_times": 1.5, "xp_on": false, "xp_percent": 25},
		"state": {"on": true, "tick": 12, "element": 6, "name": "fire", "started_at": now - 600, "ends_at": now + 3600,
			"hit": 0.25, "resist": 1.5, "bags": 1.5, "xp": 0.0, "now": now},
		"recent": [{"tick": 12, "element": 6, "name": "fire", "started_at": now - 600, "ends_at": now + 3600, "chosen_by": ""},
			{"tick": 11, "element": 3, "name": "ice", "started_at": now - 11400, "ends_at": now - 600, "chosen_by": "Tunacan"}],
		"lands": [{"element": 1, "name": "dark", "kills": 4}, {"element": 6, "name": "fire", "kills": 0}],
		"limits": {"hours": [1, 24]}, "now": now}))
	tab.fetch = func(path: String) -> Dictionary:
		asked.append(path)
		return {"ok": true, "status": 200, "data": view}
	tab.send = func(path: String, said: Dictionary) -> Dictionary:
		sent.append([path, said])
		return {"ok": true, "status": 200, "data": view}
	check("before the server is read, Save and Stir it now wait - the controls are not its settings yet",
		tab.save_button.disabled and tab.stir_button.disabled)
	await tab.save()
	check("  and Save sends nothing yet", sent.is_empty(), sent)
	await tab.refresh()
	check("opened, it reads the server: the switches and amounts as set",
		asked == ["/api/server/world"] and tab.on_switch.button_pressed and is_equal_approx(tab.hours_box.value, 3.0)
		and (tab.effect_switches["hit_on"] as CheckBox).button_pressed and is_equal_approx((tab.effect_amounts["hit_percent"] as SpinBox).value, 25.0)
		and not (tab.effect_switches["xp_on"] as CheckBox).button_pressed and is_equal_approx((tab.effect_amounts["bags_times"] as SpinBox).value, 1.5)
		and (tab.effect_switches["health_on"] as CheckBox).button_pressed and is_equal_approx((tab.effect_amounts["health_percent"] as SpinBox).value, 50.0)
		and is_equal_approx((tab.effect_amounts["speed_percent"] as SpinBox).value, 15.0))
	check("  what stirs now, the last stirs (and who stirred them by hand), and each land's hunting",
		tab.status_label.text == "The Fire lands are stirring - 1h 00m left (stir 12)."
		and tab.recent_label.text == "Last stirs: 12 Fire, 11 Ice (by Tunacan)." and tab.lands_label.text.contains("dark 4, fire 0"),
		[tab.status_label.text, tab.recent_label.text])
	# THE RESULTS BOX. The owner: "i want refresh to say it in the results".
	var results: RichTextLabel = gm.get("results") as RichTextLabel
	check("  opening the panel reads quietly - nothing in Results; the tab reports to the panel's",
		results != null and tab.report.is_valid() and not results.get_parsed_text().contains("Read from the server"))
	tab.refresh_button.pressed.emit()
	await get_tree().process_frame
	var said_after_refresh: String = results.get_parsed_text() if results != null else ""
	check("Refresh says what it read in the GM panel's Results: what stirs now and every setting",
		said_after_refresh.contains("Read from the server. The Fire lands are stirring - 1h 00m left (stir 12). "
			+ "Each stir lasts 3 h. On: hit harder 25%, more health 50%, faster 15%, more loot 1.5x, resistance 1.5x. Off: more XP.")
		and tab.say_label.text == "Read from the server." and asked.size() == 2, said_after_refresh)
	(tab.effect_switches["xp_on"] as CheckBox).button_pressed = true
	(tab.effect_amounts["xp_percent"] as SpinBox).value = 40.0
	(tab.effect_amounts["resist_times"] as SpinBox).value = 1.75
	(tab.effect_amounts["health_percent"] as SpinBox).value = 100.0
	(tab.effect_switches["speed_on"] as CheckBox).button_pressed = false
	tab.hours_box.value = 6.0
	await tab.save()
	check("Save sends every setting at once, as the controls have them",
		sent.size() == 1 and sent[0][0] == "/api/server/world" and sent[0][1] == {"on": true, "hours": 6,
			"hit_on": true, "hit_percent": 25, "health_on": true, "health_percent": 100, "speed_on": false,
			"speed_percent": 15, "bags_on": true, "bags_times": 1.5, "resist_on": true,
			"resist_times": 1.75, "xp_on": true, "xp_percent": 40}, sent)
	check("  and Results says it was saved, with the settings the server now holds - not the \"Saving...\" on the way",
		results.get_parsed_text().contains("Saved - the game hears it within one poll. Each stir lasts 3 h.")
		and not results.get_parsed_text().contains("Saving..."), results.get_parsed_text())
	sent.clear()
	tab.land_pick.select(tab.land_pick.get_item_index(Element.Type.EARTH))
	await tab.stir()
	check("Stir it now: the land picked, to the stir route", sent == [["/api/server/world/stir", {"element": Element.Type.EARTH}]], sent)
	tab.send = func(_path: String, _body: Dictionary) -> Dictionary:
		return {"ok": false, "status": 409, "error": "Conflict"}
	await tab.stir()
	check("  refused because the lands are off: it says to switch them on", tab.say_label.text.begins_with("Switch the stirring lands on"))
	var off_view: Dictionary = view.duplicate(true)
	off_view["settings"]["on"] = false
	tab.show_answer(off_view)
	check("switched off: says so, and Stir it now waits", tab.status_label.text == "Switched off: nothing stirs."
		and tab.stir_button.disabled)
	sent.clear()
	tab.send = func(path: String, said: Dictionary) -> Dictionary:
		sent.append([path, said])
		return {"ok": true, "status": 200, "data": view}
	tab.fetch = func(_path: String) -> Dictionary: return {"ok": false, "status": 404, "error": ""}
	await tab.refresh()
	check("a server without them: says to update it - in Results too - and Save and Stir it now wait again",
		tab.say_label.text.contains("Update the server") and tab.save_button.disabled and tab.stir_button.disabled
		and results.get_parsed_text().contains("This server does not have the stirring lands yet (404)"),
		tab.say_label.text)
	await tab.save()
	await tab.stir()
	check("  and neither Save nor Stir it now sends anything", sent.is_empty(), sent)
	gm.queue_free()
	await get_tree().process_frame
	Api.is_owner = was_owner
	Lands.clear()
	print("  lands: one stir at a time, applied to the hit and the resistance, on the HUD and the GM panel")


func _test_player_stats_window() -> void:
	section("PLAYER STATS - who signs up, who comes back, where players stop, from the GM panel (0.47.0)")
	# The owner: "build this and add it in my gm menu as a button somewhere".
	# test_stats.py holds the server's arithmetic; this holds the words and the
	# way in.
	const Stats := preload("res://src/ui/owner/statswindow.gd")
	var sample: Dictionary = JSON.parse_string(JSON.stringify({
		"now": 1800000000, "offset": -300,
		"players": {"total": 6, "staff_left_out": 1, "new_today": 1, "new_7d": 3, "new_30d": 5,
			"seen_today": 2, "seen_7d": 4, "seen_30d": 5},
		"road": {"days": 30, "signed_up": 5, "made_character": 4, "first_kill": 3, "level_5": 2, "level_10": 1,
			"came_back": 2, "came_back_of": 4, "stayed_week": 1, "stayed_week_of": 2, "minutes_to_first_kill": 6.0},
		"quit": {"quiet_days": 3, "players": 3, "never_killed": 1,
			"stayed": [{"label": "under 10 minutes", "players": 1}, {"label": "10 to 60 minutes", "players": 1},
				{"label": "1 to 24 hours", "players": 0}, {"label": "over a week", "players": 1}],
			"levels": [{"label": "level 1", "players": 1}, {"label": "levels 2-4", "players": 1}, {"label": "level 20+", "players": 1}],
			"areas": [{"area": "elusion", "players": 2}, {"area": "field", "players": 1}]},
		"daily": [{"day": "2027-01-15", "new": 1, "played": 2}, {"day": "2027-01-14", "new": 0, "played": 0}],
		"monsters": {"days": 14, "kills": 10, "never": 1, "kinds": 3,
			"most": [{"enemy": "slime", "name": "Slime", "kills": 9, "players": 2}],
			"least": [{"enemy": "boss", "name": "The Crowned", "kills": 0, "players": 0}]},
		"classes": [{"class": "warrior", "characters": 4, "top_level": 12}, {"class": "tank", "characters": 1, "top_level": 22}]}))
	var texts: Array = Stats.report_lines(sample).map(func(line: Array) -> String: return str(line[0]))
	check("the report in words: the players, and the staff left out",
		texts.has("6 players (1 staff left out).") and texts.has("New: 1 today, 3 this week, 5 this month.")
		and texts.has("Seen: 2 today, 4 this week, 5 this month."), texts.slice(0, 4))
	check("  the new players' road, each step with its share, and who came back",
		texts.has("Made a character: 4 (80%)") and texts.has("Killed a monster: 3 (60%)")
		and texts.has("Came back a day or more later: 2 of 4 (50%)") and texts.has("Still around a week later: 1 of 2 (50%)")
		and texts.has("First kill: 6.0 minutes after signing up (the middle player)"), texts)
	check("  and the biggest drop, named: where the most new players stopped",
		texts.has("The biggest drop: 1 of 5 who signed up never made a character."), texts)
	check("  where the ones who stopped stopped - how long, how far, where (areas by name), and never killing",
		texts.has("How long they played: under 10 minutes 1, 10 to 60 minutes 1, over a week 1")
		and texts.has("How far they got: level 1 1, levels 2-4 1, level 20+ 1")
		and texts.has("Where they were last: Elusion 2, Field 1") and texts.has("Never killed anything: 1"), texts)
	check("  day by day in your days, and the monsters and classes",
		texts.has("Jan 15   new 1   played 2") and texts.has("Most hunted: Slime 9 (2 players)")
		and texts.has("Least hunted: The Crowned 0") and texts.has("Never killed: 1 of 3 kinds")
		and texts.has("Warrior 4 (top level 12), Tank 1 (top level 22)"), texts)
	check("the biggest drop is the step that lost the most, and nothing when nobody came",
		Stats.biggest_drop({"signed_up": 10, "made_character": 9, "first_kill": 3, "level_5": 2}) == "The biggest drop: 6 of 9 who made a character never killed a monster."
		and Stats.biggest_drop({"signed_up": 0}) == "" and Stats.share(1, 0) == "" and Stats.day_text("bad") == "bad")
	var quiet: Array = Stats.report_lines({}).map(func(line: Array) -> String: return str(line[0]))
	check("  an empty report says so, rather than erroring", quiet.has("0 players.") and quiet.has("Nobody new in these days."), quiet)

	# ---- the window -------------------------------------------------------------
	var was_owner: bool = Api.is_owner
	Api.is_owner = true
	var window: StatsWindow = (load("res://scene/ui/owner/statswindow.tscn") as PackedScene).instantiate() as StatsWindow
	window.visible = false
	add_child(window)
	await get_tree().process_frame
	var asked: Array = []
	window.get_request = func(path: String) -> Dictionary:
		asked.append(path)
		return {"ok": true, "status": 200, "data": sample}
	# THIS COMPUTER FIVE HOURS BEHIND UTC, whatever the machine running the
	# suite is: the offset sent has to be the computer's, not 0.
	LocalTime._bias_minutes = -300
	LocalTime._bias_known = true
	LocalTime._bias_read_at = Time.get_ticks_msec()
	await window.open()
	LocalTime._bias_known = false
	var shown: String = window.report_box.get_parsed_text()
	check("opened, it reads the server - 30 days, in this computer's day - and shows the report",
		window.visible and asked == ["/api/server/stats?days=30&offset=-300"]
		and shown.contains("PLAYERS") and shown.contains("The biggest drop"), [asked, shown.left(60)])
	window.days_pick.select(window.days_pick.get_item_index(7))
	window.days_pick.item_selected.emit(window.days_pick.selected)
	await get_tree().process_frame
	check("  picking 7 days reads the last week's new players", asked.size() == 2 and asked[1].contains("days=7"), asked)
	window.get_request = func(_path: String) -> Dictionary: return {"ok": false, "status": 404, "error": ""}
	await window.refresh()
	check("  a server without them says to update it", window.status.text.contains("Update the server"), window.status.text)
	Api.is_owner = false
	var asked_before: int = asked.size()
	window.get_request = func(path: String) -> Dictionary:
		asked.append(path)
		return {"ok": true, "status": 200, "data": sample}
	await window.refresh()
	check("  and it never asks for anybody but the owner", asked.size() == asked_before
		and window.status.text == "The player stats are the owner's.")
	Api.is_owner = true
	window.close()
	check("  its x closes it", not window.visible)
	window.queue_free()

	# ---- the way in: a button on the GM panel's Server tab ------------------------
	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var opened: Array = []
	gm.set("open_window", func(method: String, _who: String) -> bool:
		opened.append(method)
		return true)
	var button: Button = gm.get("stats_button") as Button
	var server_page: Node = gm.get_node_or_null("%ownertabs").get_node_or_null(^"server") if gm.get_node_or_null("%ownertabs") else null
	check("the GM panel's Server tab starts with a Player stats button",
		button != null and server_page != null and button.get_parent() == server_page and button.get_index() == 0
		and button.text == "Player stats")
	if button != null:
		button.pressed.emit()
	check("  pressing it opens the Player stats through the HUD", opened == ["open_player_stats"], opened)
	gm.set("open_window", func(_method: String, _who: String) -> bool: return false)
	if button != null:
		button.pressed.emit()
	check("  and out of the game it says so in Results",
		(gm.get("results") as RichTextLabel).get_parsed_text().contains("the player stats open from inside the game"))
	gm.queue_free()
	await get_tree().process_frame
	Api.is_owner = was_owner
	print("  player stats: the report in words, read on opening, owner only, a button on the Server tab")


func _test_world_events() -> void:
	section("THE WORLD'S EVENTS - double XP, more loot, a land made to stir: on the HUD, set from the GM panel (0.48.0)")
	# The owner: "Treat events (double XP, double loot, forced stir, etc.) as
	# their own feature area with a clean public contract". test_events.py
	# holds the server - the rules, the routes, what a kill is paid; this holds
	# what the game shows and how the owner sets them.
	WorldEvents.clear()
	Lands.clear()
	var now: int = int(Time.get_unix_time_from_system())
	var double_xp: Dictionary = {"id": 7, "name": "Double XP", "kind": "xp", "description": "2x XP from every monster.",
		"starts_at": now - 600, "ends_at": now + 2 * 3600 + 30, "land": 0, "multipliers": {"xp": 2.0}}
	var double_loot: Dictionary = {"id": 8, "name": "Double Loot", "kind": "loot",
		"description": "Loot bags drop 2x as often from every monster.", "starts_at": now + 26 * 3600 + 30,
		"ends_at": now + 29 * 3600 + 30, "land": 0, "multipliers": {"loot": 2.0}}

	# ---- what the poll says ------------------------------------------------------
	var read: Dictionary = WorldEvents.read_event(double_xp)
	check("an event from the poll, as the contract has it",
		read.get("id") == 7 and read.get("kind") == "xp" and read.get("name") == "Double XP"
		and is_equal_approx(float(read["multipliers"].get("xp", 0.0)), 2.0) and read.get("land") == 0, read)
	var loud: Dictionary = double_xp.duplicate(true)
	loud["multipliers"] = {"xp": 50.0, "gold": 9.0}
	loud["name"] = "x".repeat(300)
	loud["land"] = 99
	var held: Dictionary = WorldEvents.read_event(loud)
	check("  a number past what the server allows is not believed: 3x at most, a name of 40, a land of 7",
		is_equal_approx(float(held["multipliers"].get("xp", 0.0)), 3.0) and not held["multipliers"].has("gold")
		and str(held["name"]).length() == 40 and held["land"] == Element.Type.WATER, held)
	var bad_kind: Dictionary = double_xp.duplicate()
	bad_kind["kind"] = "gold"
	var backwards: Dictionary = double_xp.duplicate()
	backwards["ends_at"] = backwards["starts_at"]
	var no_id: Dictionary = double_xp.duplicate()
	no_id.erase("id")
	check("  and what is not an event is nothing: a kind it does not know, an end before its start, no id, not a dictionary",
		WorldEvents.read_event(bad_kind).is_empty() and WorldEvents.read_event(backwards).is_empty()
		and WorldEvents.read_event(no_id).is_empty() and WorldEvents.read_event("Double XP").is_empty())
	var heard: Array = []
	var on_change := func() -> void: heard.append(true)
	WorldEvents.changed.connect(on_change)
	var began: Array[Dictionary] = WorldEvents.apply({"events": [double_xp], "next": [double_loot], "now": now})
	check("Double XP on, Double Loot next: that is news, and the lines say so with their times",
		began.size() == 1 and int(began[0]["id"]) == 7 and heard.size() == 1
		and WorldEvents.lines() == ["Double XP - 2h 00m left", "Next: Double Loot in 1d 2h"], WorldEvents.lines())
	began = WorldEvents.apply({"events": [double_xp], "next": [double_loot], "now": now})
	check("  asked again, the same: nothing began, nothing changed", began.is_empty() and heard.size() == 1)
	WorldEvents._clock_offset += 2 * 3600 + 60
	check("  past its end by the server's clock, it is off the screen before the next poll says so",
		WorldEvents.lines() == ["Next: Double Loot in 23h 59m"], WorldEvents.lines())
	WorldEvents._clock_offset -= 2 * 3600 + 60
	WorldEvents.apply(null)
	check("  and a server from before events says none", WorldEvents.lines().is_empty() and heard.size() == 2)
	WorldEvents.changed.disconnect(on_change)
	check("time in words: under a minute, minutes, hours and minutes, days and hours",
		WorldEvents.span_text(30) == "under a minute" and WorldEvents.span_text(600) == "10m"
		and WorldEvents.span_text(7260) == "2h 01m" and WorldEvents.span_text(93600) == "1d 2h")

	# ---- one line for what pays (0.50.1) ---------------------------------------------
	# The owner set Double XP twice in a minute, and every player saw "Double
	# XP - 2h 59m left" twice. The server pays the bigger of each kind, never
	# both (kill_scales()); the screen says what a kill gets.
	var twin: Dictionary = double_xp.duplicate(true)
	twin["id"] = 11
	twin["ends_at"] = int(double_xp["ends_at"]) + 1800
	began = WorldEvents.apply({"events": [double_xp, twin], "next": [], "now": now})
	check("two Double XPs at once: one line - the one that lasts longer - and one event's news, not two",
		WorldEvents.lines() == ["Double XP - 2h 30m left"] and began.size() == 1 and int(began[0]["id"]) == 11,
		[WorldEvents.lines(), began.size()])
	WorldEvents.apply({"events": [double_xp], "next": [], "now": now})
	began = WorldEvents.apply({"events": [double_xp, twin], "next": [], "now": now})
	check("  and one set to run Double XP on past its end is no news while it is on: no banner for it",
		began.is_empty() and WorldEvents.lines() == ["Double XP - 2h 30m left"], [began.size(), WorldEvents.lines()])
	var triple_xp: Dictionary = double_xp.duplicate(true)
	triple_xp["id"] = 12
	triple_xp["name"] = "Triple XP"
	triple_xp["multipliers"] = {"xp": 3.0}
	triple_xp["ends_at"] = now + 3600 + 30
	began = WorldEvents.apply({"events": [double_xp, triple_xp], "next": [], "now": now})
	var while_triple: Array[String] = WorldEvents.lines()
	WorldEvents._clock_offset += 3600 + 60
	var after_triple: Array[String] = WorldEvents.lines()
	WorldEvents._clock_offset -= 3600 + 60
	check("  a bigger one over it: the bigger alone, and news; the smaller comes back when it ends, as it outlasts it",
		while_triple == ["Triple XP - 1h 00m left"] and began.size() == 1 and int(began[0]["id"]) == 12
		and after_triple == ["Double XP - 59m left"], [while_triple, after_triple])
	var fire_double: Dictionary = double_xp.duplicate(true)
	fire_double["id"] = 13
	fire_double["name"] = "Double XP (fire)"
	fire_double["land"] = Element.Type.FIRE
	fire_double["ends_at"] = int(double_xp["ends_at"]) + 600
	var fire_triple: Dictionary = fire_double.duplicate(true)
	fire_triple["ends_at"] = double_xp["ends_at"]
	fire_triple["id"] = 14
	fire_triple["name"] = "Triple XP (fire)"
	fire_triple["multipliers"] = {"xp": 3.0}
	var double_loot_on: Dictionary = double_loot.duplicate(true)
	double_loot_on["starts_at"] = now - 5
	double_loot_on["ends_at"] = now + 3600 + 30
	WorldEvents.apply({"events": [double_xp, fire_double], "next": [], "now": now})
	var lands_same: Array[String] = WorldEvents.lines()
	WorldEvents.apply({"events": [double_xp, fire_triple, double_loot_on], "next": [], "now": now})
	var lands_more: Array[String] = WorldEvents.lines()
	check("  every monster's 2x hides one land's 2x, even one that runs on longer; one land's 3x shows beside it, "
		+ "and loot is never XP's",
		lands_same == ["Double XP - 2h 00m left"]
		and lands_more == ["Double XP - 2h 00m left", "Triple XP (fire) - 2h 00m left", "Double Loot - 1h 00m left"],
		[lands_same, lands_more])
	var stir_old: Dictionary = {"id": 15, "name": "The Fire Lands Stir", "kind": "stir", "description": "",
		"starts_at": now - 900, "ends_at": now + 3600 + 30, "land": Element.Type.FIRE, "multipliers": {}}
	var stir_new: Dictionary = stir_old.duplicate(true)
	stir_new["id"] = 16
	stir_new["name"] = "The Ice Lands Stir"
	stir_new["starts_at"] = now - 60
	WorldEvents.apply({"events": [stir_old, stir_new], "next": [], "now": now})
	check("  two stir events: the one that began last, as the server stirs it",
		WorldEvents.lines() == ["The Ice Lands Stir - 1h 00m left"], WorldEvents.lines())
	var never_both: bool = true
	for pair in [[double_xp, twin], [double_xp, fire_double], [stir_old, stir_new], [double_xp, double_xp]]:
		if WorldEvents.outdoes(pair[0], pair[1]) and WorldEvents.outdoes(pair[1], pair[0]):
			never_both = false
	var same_end: Dictionary = double_xp.duplicate(true)
	same_end["id"] = 17
	check("  never both ways round, so one of any two is always on the screen; alike to the second, the first set stands in",
		never_both and WorldEvents.outdoes(double_xp, same_end) and not WorldEvents.outdoes(same_end, double_xp))
	WorldEvents.clear()

	# ---- the HUD ---------------------------------------------------------------------
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await get_tree().process_frame
	var green: Color = hud.get_script().get_script_constant_map().get("EVENT_COLOUR", Color.BLACK)
	var kept_cursor: int = hud._broadcast_cursor
	hud._broadcast_cursor = 0
	hud._apply_broadcast({"messages": [], "latest_id": 5, "events": {"events": [double_xp], "next": [double_loot], "now": now}})
	var chip: PanelContainer = hud.event_chip
	check("logging in during Double XP: its line and the next one's under the top of the screen, in the events' green, no banner",
		chip != null and chip.visible and hud.event_label.text == "Double XP - 2h 00m left\nNext: Double Loot in 1d 2h"
		and hud.event_label.get_theme_color("font_color").is_equal_approx(green)
		and (hud.mythic_banner == null or not is_instance_valid(hud.mythic_banner)), hud.event_label.text if hud.event_label else "")
	var loot_on: Dictionary = double_loot.duplicate(true)
	loot_on["starts_at"] = now - 5
	loot_on["ends_at"] = now + 3 * 3600 + 30
	hud._apply_broadcast({"messages": [{"id": 6, "kind": "event", "body": "Double Loot has begun, for 3 hours.", "at": now}],
		"latest_id": 6, "events": {"events": [double_xp, loot_on], "next": [], "now": now}})
	var banner: Node = hud.mythic_banner
	var title: Label = banner.find_child("title", true, false) as Label if banner != null and is_instance_valid(banner) else null
	check("one that begins while playing: a banner across the top in the events' green, saying what it does",
		title != null and title.text == "DOUBLE LOOT" and title.get_theme_color("font_color").is_equal_approx(green)
		and (banner.find_child("line", true, false) as Label).text == "Loot bags drop 2x as often from every monster.",
		title.text if title else "no banner")
	var last_line: Dictionary = hud._unlogged_lines.back() if not hud._unlogged_lines.is_empty() else {}
	check("  and the server's sentence is in chat in the same green",
		str(last_line.get("text", "")) == "Double Loot has begun, for 3 hours."
		and Color(last_line.get("color", Color.BLACK)).is_equal_approx(green), last_line)
	check("  both on the line, one under the other", hud.event_label.text.begins_with("Double XP - ")
		and hud.event_label.text.contains("\nDouble Loot - 3h 00m left"), hud.event_label.text)
	if banner != null and is_instance_valid(banner):
		banner.free()
	hud.mythic_banner = null
	var stir_event: Dictionary = {"id": 9, "name": "The Fire Lands Stir", "kind": "stir",
		"description": "The fire lands stir for the whole event.", "starts_at": now - 5, "ends_at": now + 3600 + 30,
		"land": Element.Type.FIRE, "multipliers": {}}
	hud._apply_broadcast({"messages": [], "latest_id": 6,
		"events": {"events": [double_xp, loot_on, stir_event], "next": [], "now": now}})
	check("  a stir event gets no banner of its own: the land's stir is the banner", hud.mythic_banner == null)
	hud._apply_broadcast({"messages": [], "latest_id": 6, "world": {"on": true, "tick": 3, "element": Element.Type.FIRE,
		"name": "fire", "started_at": now - 5, "ends_at": now + 3600, "now": now},
		"events": {"events": [double_xp], "next": [], "now": now}})
	if hud.mythic_banner != null and is_instance_valid(hud.mythic_banner):
		hud.mythic_banner.free()
	hud.mythic_banner = null
	check("with a land stirring, the events' line sits under the land's",
		hud.world_chip.visible and is_equal_approx(chip.offset_top, hud.world_chip.offset_bottom + 4.0), chip.offset_top)
	hud._apply_broadcast({"messages": [], "latest_id": 6, "world": {"on": false, "tick": 0, "element": 0}})
	if hud.mythic_banner != null and is_instance_valid(hud.mythic_banner):
		hud.mythic_banner.free()
	hud.mythic_banner = null
	check("  and with none, where the land's would be - and a server from before events shows no line",
		not hud.world_chip.visible and not chip.visible and is_equal_approx(chip.offset_top, 10.0))
	hud._apply_broadcast({"messages": [], "latest_id": 6, "events": {"events": [double_xp, twin], "next": [], "now": now}})
	var twin_banner: Node = hud.mythic_banner
	var twin_title: Label = twin_banner.find_child("title", true, false) as Label \
		if twin_banner != null and is_instance_valid(twin_banner) else null
	check("Double XP set twice, as the owner's screenshot had it: one line on the HUD and one banner (0.50.1)",
		chip.visible and hud.event_label.text == "Double XP - 2h 30m left"
		and twin_title != null and twin_title.text == "DOUBLE XP", hud.event_label.text)
	if twin_banner != null and is_instance_valid(twin_banner):
		twin_banner.free()
	hud.mythic_banner = null
	hud._apply_broadcast({"messages": [], "latest_id": 6})
	var hud_src: String = _code_src("res://src/ui/characterhud.gd")
	check("the events are read from every poll (the reader is called from _apply_broadcast)",
		_func_body(hud_src, "func _apply_broadcast(").contains("_read_events(data.get(\"events\"))"))
	hud._broadcast_cursor = kept_cursor
	hud.queue_free()
	await get_tree().process_frame
	WorldEvents.clear()
	Lands.clear()
	const StaffScript := preload("res://src/ui/staff/staffpanel.gd")
	check("the staff log says what the owner did, in the server's words",
		StaffScript.describe_entry({"by": "Tunacan", "action": "event", "target": "server",
			"detail": "scheduled #3 Double XP (xp 2.0, land 0) for 3 hours"}) == "Tunacan scheduled #3 Double XP (xp 2.0, land 0) for 3 hours"
		and StaffScript.KIND_LABELS.get("event") == "Events")

	# ---- the GM panel's Events tab ---------------------------------------------------
	LocalTime._bias_minutes = -300
	LocalTime._bias_known = true
	LocalTime._bias_read_at = Time.get_ticks_msec()
	var fixed_now: int = 1800000000
	check("a day and a time on this computer's clock, five hours behind: tomorrow 14:30 and today 00:00",
		EventsTab.start_time(1, 14, 30, fixed_now) == 1800127800 and EventsTab.start_time(0, 0, 0, fixed_now) == 1799989200,
		[EventsTab.start_time(1, 14, 30, fixed_now), EventsTab.start_time(0, 0, 0, fixed_now)])
	var was_owner: bool = Api.is_owner
	Api.is_owner = true
	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var tabs: TabContainer = gm.get_node_or_null("%ownertabs") as TabContainer
	var tab: EventsTab = gm.get("events_tab") as EventsTab
	check("the GM panel has an Events tab, after World",
		tabs != null and tab != null and tab.get_parent() == tabs and tabs.get_tab_title(tab.get_index()) == "Events"
		and tabs.get_tab_title(tab.get_index() - 1) == "World")
	tab.fill_days(fixed_now)
	check("  the days: Now, Today, Tomorrow, then each by its name - sixty of them; further on is the calendar's (0.52.0)",
		tab.day_pick.item_count == 61 and tab.day_pick.get_item_text(0) == "Now" and tab.day_pick.get_item_text(1) == "Today"
		and tab.day_pick.get_item_text(2) == "Tomorrow" and tab.day_pick.get_item_text(3) == "Sun Jan 17"
		and tab.day_pick.get_item_text(60) == "Mon Mar 15", [tab.day_pick.item_count, tab.day_pick.get_item_text(60)])

	# ---- the calendar (0.51.0) -------------------------------------------------------
	# The owner: "i want to set a calendar in schedule that i can use to set
	# events for specific days".
	var october: Array[int] = EventCalendar.month_cells(2026, 10)
	check("the calendar's months, Sunday first: October 2026 begins on a Thursday and has 31 days; "
		+ "February has 29 in 2028 and 2000, 28 in 2100",
		october.size() == 35 and october[0] == 0 and october[3] == 0 and october[4] == 1 and october[34] == 31
		and EventCalendar.days_in_month(2028, 2) == 29 and EventCalendar.days_in_month(2000, 2) == 29
		and EventCalendar.days_in_month(2100, 2) == 28 and EventCalendar.days_in_month(2027, 4) == 30, october)
	LocalTime._bias_known = true
	LocalTime._bias_read_at = Time.get_ticks_msec()
	var hour_s: int = 3600
	check("  a day is counted from today's date on this computer's clock (five hours behind): 23:59 tonight is today, "
		+ "00:00 is tomorrow, and the 59th day is Mon Mar 15",
		EventCalendar.days_on_of(fixed_now + 20 * hour_s + 59 * 60, fixed_now) == 0
		and EventCalendar.days_on_of(fixed_now + 21 * hour_s, fixed_now) == 1
		and EventCalendar.date_of(59, fixed_now).get("month") == 3 and EventCalendar.date_of(59, fixed_now).get("day") == 15
		and EventCalendar.date_of(59, fixed_now).get("weekday") == 1)
	var calendar_marks: Dictionary = EventCalendar.marks([
		{"name": "Late XP", "starts_at": fixed_now + 19 * hour_s, "ends_at": fixed_now + 23 * hour_s},
		{"name": "Day Loot", "starts_at": fixed_now + 45 * hour_s, "ends_at": fixed_now + 69 * hour_s, "state": "coming"},
		{"name": "Old XP", "starts_at": fixed_now - 30 * hour_s, "ends_at": fixed_now - 27 * hour_s, "state": "over"},
		{"name": "Off XP", "starts_at": fixed_now + 70 * hour_s, "ends_at": fixed_now + 72 * hour_s, "state": "cancelled"},
		"not an event"], fixed_now)
	check("  each day an event touches, with its hours that day: across midnight it is on both, all day says so, "
		+ "one gone by says it is over, and one called off is not marked",
		calendar_marks == {0: ["Late XP 22:00-24:00"], 1: ["Late XP 00:00-02:00"], 2: ["Day Loot all day"],
			-2: ["Old XP 21:00-24:00 (over)"]}, calendar_marks)
	# A REAL CALENDAR (0.52.0): "can we make it a real calendar that updates
	# with the years etc?" - any month of any year, the year turning over.
	check("the year turns over: a month on from December 2026 is January 2027, a month back from January is the "
		+ "December before, twelve on is the same month next year - and it stops at 1970 and 2199",
		EventCalendar.month_after(2026, 12, 1) == [2027, 1] and EventCalendar.month_after(2027, 1, -1) == [2026, 12]
		and EventCalendar.month_after(2026, 10, 12) == [2027, 10] and EventCalendar.month_after(2026, 10, -24) == [2024, 10]
		and EventCalendar.month_after(1970, 1, -1) == [1970, 1] and EventCalendar.month_after(2199, 12, 1) == [2199, 12],
		[EventCalendar.month_after(2026, 12, 1), EventCalendar.month_after(2027, 1, -1)])
	check("  a day past the sixty listed is named with its year: 300 days on is Nov 11 2027; how far, in words",
		EventsTab.far_name(300, fixed_now) == "Nov 11 2027" and EventCalendar.reach_words(366) == "a year"
		and EventCalendar.reach_words(60) == "60 days", EventsTab.far_name(300, fixed_now))
	LocalTime._bias_known = false
	check("the calendar button sits beside the minute and opens the month",
		tab.calendar_button.get_parent() == tab.minute_box.get_parent()
		and tab.calendar_button.tooltip_text.begins_with("Calendar")
		and tab.calendar_popup is PopupPanel and tab.calendar.get_parent() == tab.calendar_popup)
	# ONLY THE GAME'S OWN ART (0.54.2): the owner's art or the Clockwork pack's.
	var calendar_code: String = _code_src("res://src/ui/owner/eventcalendar.gd")
	check("  its picture is the pack's book with the red bookmark - none drawn in code, none preloaded",
		EventCalendar.ICON_PATH.begins_with("res://art/pack/") and not calendar_code.contains("Image.create")
		and not calendar_code.contains("set_pixel")
		and not FileAccess.get_file_as_string("res://src/ui/owner/eventcalendar.gd").contains("preload(\"res://art/pack"))
	check_needs_pack("  and it is there: a picture, not a word", tab.calendar_button.icon != null
		and tab.calendar_button.icon.resource_path == EventCalendar.ICON_PATH and tab.calendar_button.text == "",
		tab.calendar_button.text)
	check("  where a clone has no pack, the button says \"%s\" instead" % EventCalendar.ICON_WORD,
		(tab.calendar_button.icon != null and tab.calendar_button.text == "")
		or (tab.calendar_button.icon == null and tab.calendar_button.text == EventCalendar.ICON_WORD))
	LocalTime._bias_known = false
	if tabs != null and tab != null:
		tabs.current_tab = tab.get_index()
		await get_tree().process_frame
	# EVERY DAY'S NAME FITS ITS PICKER, in any month: the picker is one width
	# all year, so the widest weekday with the widest month must fit it.
	var day_font: Font = tab.day_pick.get_theme_font("font")
	var day_size: int = tab.day_pick.get_theme_font_size("font_size")
	var day_box: StyleBox = tab.day_pick.get_theme_stylebox("normal")
	var arrow: Texture2D = tab.day_pick.get_theme_icon("arrow")
	var day_room: float = tab.day_pick.size.x - day_box.get_margin(SIDE_LEFT) - day_box.get_margin(SIDE_RIGHT) \
		- (arrow.get_width() if arrow != null else 0) - tab.day_pick.get_theme_constant("arrow_margin")
	var widest: float = 0.0
	for weekday in LocalTime.WEEKDAYS:
		for month in LocalTime.MONTHS.slice(1):
			widest = maxf(widest, day_font.get_string_size("%s %s 30" % [weekday, month], HORIZONTAL_ALIGNMENT_LEFT, -1, day_size).x)
	check("  every day's name fits its picker in any month - it is one width all year (%d of %d)" % [widest, day_room],
		widest <= day_room, [widest, day_room])
	var widest_far: float = 0.0
	for month in LocalTime.MONTHS.slice(1):
		widest_far = maxf(widest_far, day_font.get_string_size("%s 30 2027" % month, HORIZONTAL_ALIGNMENT_LEFT, -1, day_size).x)
	check("  and so does a far one's, with its year (%d of %d)" % [widest_far, day_room], widest_far <= day_room,
		[widest_far, day_room])
	var wide: float = PanelWindow.content_minimum(gm).x
	check("  and it fits the panel's drawn width (370) (%d)" % wide, wide <= 370.0, wide)
	var asked: Array = []
	var sent: Array = []
	var view: Variant = JSON.parse_string(JSON.stringify({"events": [
		{"id": 8, "name": "Double Loot", "kind": "loot", "description": "", "starts_at": now + 86400, "ends_at": now + 86400 + 3 * 3600,
			"land": 0, "multipliers": {"loot": 2.0}, "created_by": "Tunacan", "cancelled": false, "cancelled_by": "", "state": "coming"},
		{"id": 7, "name": "Double XP", "kind": "xp", "description": "", "starts_at": now - 600, "ends_at": now + 3000,
			"land": 0, "multipliers": {"xp": 2.0}, "created_by": "Tunacan", "cancelled": false, "cancelled_by": "", "state": "on"},
		{"id": 5, "name": "Triple Loot", "kind": "loot", "description": "", "starts_at": now - 9 * 3600, "ends_at": now - 6 * 3600,
			"land": 0, "multipliers": {"loot": 3.0}, "created_by": "Tunacan", "cancelled": false, "cancelled_by": "", "state": "over"},
		{"id": 4, "name": "1.5x XP", "kind": "xp", "description": "", "starts_at": now - 20 * 3600, "ends_at": now - 18 * 3600,
			"land": 0, "multipliers": {"xp": 1.5}, "created_by": "Tunacan", "cancelled": true, "cancelled_by": "Tunacan", "state": "cancelled"}],
		"now": now, "limits": {"amount": [1.25, 3.0], "hours": [1, 72], "days_ahead": 366, "waiting": 20}}))
	tab.fetch = func(path: String) -> Dictionary:
		asked.append(path)
		return {"ok": true, "status": 200, "data": view}
	tab.send = func(path: String, said: Dictionary) -> Dictionary:
		sent.append([path, said])
		return {"ok": true, "status": 201, "data": {"event": {"id": 9, "name": "Double XP", "kind": "xp",
			"description": "2x XP from every monster.", "starts_at": now, "ends_at": now + 3 * 3600}, "now": now}}
	check("before the server is read, an event may be set a year ahead, as FURTHEST in the API's events/services.py "
		+ "has it (0.52.0)", tab.days_ahead() == 366, tab.days_ahead())
	check("before the server is read, Schedule waits", tab.schedule_button.disabled and tab.cancel_button.disabled)
	await tab.schedule()
	check("  and sends nothing", sent.is_empty(), sent)
	await tab.refresh()
	check("opened, it reads the server: what is on, what is coming, and the last that ended",
		asked == ["/api/world/events/schedule"] and tab.status_label.text == "1 on now, 1 coming."
		and tab.list_label.text.begins_with("Double XP - on, 50m left\nDouble Loot - ")
		and tab.list_label.text.ends_with("\nLast: Triple Loot (over), 1.5x XP (called off)"), tab.list_label.text)
	check("  read every time the panel opens, like the World tab - the owner may have set one from another machine",
		_func_body(_code_src("res://src/ui/owner/ownerpanel.gd"), "func _on_visibility_changed(").contains("await events_tab.refresh()"))
	check("  and either of the two can be called off, soonest first",
		tab.cancel_pick.item_count == 2 and tab.cancel_pick.get_item_id(0) == 7 and tab.cancel_pick.get_item_id(1) == 8
		and not tab.cancel_button.disabled and not tab.schedule_button.disabled)
	var results: RichTextLabel = gm.get("results") as RichTextLabel
	check("  opening reads quietly; Refresh says what it read in the GM panel's Results",
		results != null and tab.report.is_valid() and not results.get_parsed_text().contains("Read from the server. 1 on now"))
	tab.refresh_button.pressed.emit()
	await get_tree().process_frame
	check("  Refresh: \"Read from the server. 1 on now, 1 coming.\"",
		results.get_parsed_text().contains("Read from the server. 1 on now, 1 coming."), results.get_parsed_text())
	tab.day_pick.select(0)
	tab.day_pick.item_selected.emit(0)
	tab.open_calendar()
	await get_tree().process_frame
	var cal: EventCalendar = tab.calendar
	var real_now: int = int(Time.get_unix_time_from_system())
	var today_date: Dictionary = EventCalendar.date_of(0, real_now)
	var today_cell: Button = cal.cell_for(int(today_date.get("day", 1)))
	check("the calendar button opens it: this month, today offered, its number in gold, saying Double XP is on",
		tab.calendar_popup.visible and cal.shown_month == int(today_date.get("month", 0))
		and cal.shown_year == int(today_date.get("year", 0))
		and today_cell != null and not today_cell.disabled and today_cell.tooltip_text.begins_with("Today\nDouble XP ")
		and today_cell.get_theme_color("font_color").is_equal_approx(EventCalendar.TODAY),
		today_cell.tooltip_text if today_cell else "no cell")
	# ANY OF TOMORROW'S LINES (0.56.0): run near midnight, the Double XP on now
	# runs past it and marks tomorrow too, and "exactly one line" failed.
	check("  tomorrow marked for the Double Loot coming", cal.marked.has(1)
		and (cal.marked[1] as Array).any(func(line: Variant) -> bool: return str(line).begins_with("Double Loot ")), cal.marked)
	var marked_words: String = str(cal.marked.values())
	check("  Triple Loot, over this morning, marked as over; 1.5x XP, called off, not at all",
		marked_words.contains("Triple Loot ") and marked_words.contains(" (over)") and not marked_words.contains("1.5x XP"),
		marked_words)
	# HOTBAR BOXES (0.52.0): "also i want to use hotbar boxs for the outline on
	# those days".
	var today_socket: StyleBoxTexture = today_cell.get_theme_stylebox("normal") as StyleBoxTexture \
		if today_cell != null else null
	var socket_hover: StyleBoxTexture = today_cell.get_theme_stylebox("hover") as StyleBoxTexture \
		if today_cell != null else null
	check("  a day with an event is in a hotbar box - the hotbar's own slot art, drawn out over its clear rim to the "
		+ "cell's size - lit under the pointer",
		today_socket != null and today_socket.texture != null
		and today_socket.texture.resource_path == "res://art/images/hotbarslot.png"
		and socket_hover != null and socket_hover.modulate_color.v > today_socket.modulate_color.v
		and today_socket.get_expand_margin(SIDE_LEFT) > 0.0,
		today_socket)
	cal.show_days(real_now, 366, -1, [])
	today_cell = cal.cell_for(int(today_date.get("day", 1)))
	var today_box: StyleBoxFlat = today_cell.get_theme_stylebox("normal") as StyleBoxFlat if today_cell != null else null
	var plain_cell_box: StyleBoxFlat = null
	for child in cal.grid.get_children():
		if child is Button and not (child as Button).has_theme_stylebox_override("normal"):
			plain_cell_box = (child as Button).get_theme_stylebox("normal") as StyleBoxFlat
			break
	check("  today with nothing on: a warm fill and a gold edge, in the GM panel's own button style, not the engine's",
		today_box != null and plain_cell_box != null and today_box.bg_color.is_equal_approx(EventCalendar.TODAY_FILL)
		and today_box.border_color.is_equal_approx(EventCalendar.TODAY)
		and today_box.border_width_left == plain_cell_box.border_width_left
		and is_equal_approx(today_box.content_margin_left, plain_cell_box.content_margin_left),
		[today_box.border_color, today_box.content_margin_left] if today_box else ["no box"])
	tab.open_calendar()
	await get_tree().process_frame
	var offered_right: bool = true
	var cells_seen: int = 0
	for child in cal.grid.get_children():
		if child is Button:
			cells_seen += 1
			var on_day: int = int(child.get_meta("days_on"))
			if (child as Button).disabled != (on_day < 0 or on_day >= 366):
				offered_right = false
	check("  this month: every day before today not offered, the rest are", offered_right and cells_seen >= 28, cells_seen)
	check("  and on this month, Today has nowhere to go", cal.today_button.disabled)
	cal.turn(-1)
	var all_gone: bool = true
	for child in cal.grid.get_children():
		if child is Button and not (child as Button).disabled:
			all_gone = false
	check("a REAL calendar (0.52.0): < goes back to last month, there to read, none of its days offered; "
		+ "Today comes back",
		not cal.earlier_button.disabled and all_gone and not cal.today_button.disabled
		and cal.month_label.text.ends_with(str(EventCalendar.month_after(int(today_date.get("year", 0)),
			int(today_date.get("month", 0)), -1)[0])))
	cal.show_today()
	cal.turn(12)
	check("  >> is the same month next year, and the label says so",
		cal.shown_year == int(today_date.get("year", 0)) + 1 and cal.shown_month == int(today_date.get("month", 0))
		and cal.month_label.text == "%s %d" % [EventCalendar.MONTH_NAMES[cal.shown_month], cal.shown_year],
		cal.month_label.text)
	var last_date: Dictionary = EventCalendar.date_of(365, real_now)
	cal.show_month(int(last_date.get("year", 0)), int(last_date.get("month", 0)))
	var last_cell: Button = cal.cell_for(int(last_date.get("day", 1)))
	var past_cell: Button = cal.cell_for(int(last_date.get("day", 1)) + 1)
	check("  a year on, the last day the server takes is offered and the day after it is not - "
		+ "though the months after can still be read",
		last_cell != null and not last_cell.disabled and (past_cell == null or past_cell.disabled)
		and not cal.later_button.disabled and past_cell != null and past_cell.tooltip_text.contains("a year"),
		[last_date, past_cell.tooltip_text if past_cell else ""])
	var far_date: Dictionary = EventCalendar.date_of(200, real_now)
	cal.show_month(int(far_date.get("year", 0)), int(far_date.get("month", 0)))
	var far_cell: Button = cal.cell_for(int(far_date.get("day", 1)))
	if far_cell != null:
		far_cell.pressed.emit()
	await get_tree().process_frame
	var far_index: int = tab.day_index(200)
	check("a day pressed 200 days on, past the sixty listed: it joins the day picker with its year, picked, "
		+ "and the calendar closes",
		far_cell != null and tab.day() == 200 and far_index == 61 and tab.day_pick.selected == far_index
		and tab.day_pick.get_item_text(far_index) == EventsTab.far_name(200, real_now) and not tab.calendar_popup.visible
		and tab.hour_box.editable and tab.say_label.text == "Day picked: %s." % EventsTab.far_name(200, real_now),
		[tab.day(), far_index, tab.say_label.text])
	tab.hour_box.value = 20.0
	tab.minute_box.value = 0.0
	check("  and Schedule would start it then: 20:00 that day on this computer's clock",
		int(tab.event_from_controls(now).get("starts_at", 0)) == EventsTab.start_time(200, 20, 0, int(Time.get_unix_time_from_system())))
	tab.fill_days(int(Time.get_unix_time_from_system()))
	check("  and it stays in the picker when the days are filled again (each read of the server)",
		tab.day() == 200 and tab.day_index(200) == 61)
	tab.open_calendar()
	await get_tree().process_frame
	var again_cell: Button = cal.cell_for(int(far_date.get("day", 1)))
	check("  opened again, it shows that day's month and year with the day pressed in",
		cal.shown_month == int(far_date.get("month", 0)) and cal.shown_year == int(far_date.get("year", 0))
		and again_cell != null and again_cell.button_pressed)
	var day_thirty: Dictionary = EventCalendar.date_of(30, real_now)
	cal.show_month(int(day_thirty.get("year", 0)), int(day_thirty.get("month", 0)))
	var thirty_cell: Button = cal.cell_for(int(day_thirty.get("day", 1)))
	if thirty_cell != null:
		thirty_cell.pressed.emit()
	await get_tree().process_frame
	check("a day within the sixty: the day picker's own item for it, no year needed",
		thirty_cell != null and tab.day() == 30 and tab.day_index(30) == 31 and not tab.calendar_popup.visible
		and tab.say_label.text == "Day picked: %s." % tab.day_pick.get_item_text(31), tab.say_label.text)
	tab.calendar_popup.hide()
	tab.kind_pick.select(0)
	tab.kind_pick.item_selected.emit(0)
	tab.amount_box.value = 2.0
	tab.land_pick.select(tab.land_index(EventsTab.LAND_ANY))
	tab.day_pick.select(0)
	tab.day_pick.item_selected.emit(0)
	tab.hours_box.value = 3.0
	tab.name_edit.text = ""
	check("Now has no hour or minute of its own", not tab.hour_box.editable and not tab.minute_box.editable)
	await tab.schedule()
	var first: Dictionary = sent[0][1] if not sent.is_empty() else {}
	check("Schedule, double XP for every monster, now, for 3 hours: sent as the server's contract asks",
		sent.size() == 1 and sent[0][0] == "/api/world/events" and first.get("kind") == "xp"
		and is_equal_approx(float(first.get("amount", 0.0)), 2.0) and first.get("land") == 0 and first.get("hours") == 3
		and absi(int(first.get("starts_at", 0)) - now) <= 5 and not first.has("name"), first)
	check("  and Results says it was scheduled, what it does, and that everyone is told - then reads the list again",
		results.get_parsed_text().contains("Scheduled: Double XP, now, for 3 h - 2x XP from every monster. Everyone online is told.")
		and asked.size() == 3, results.get_parsed_text())
	sent.clear()
	tab.kind_pick.select(2)
	tab.kind_pick.item_selected.emit(2)
	check("a stir: no amount, and only a land - not every monster or the stirring land's",
		not tab.amount_box.editable and tab.land_pick.is_item_disabled(tab.land_index(EventsTab.LAND_ANY))
		and tab.land_pick.is_item_disabled(tab.land_index(EventsTab.LAND_STIRRING))
		and tab.land() == Element.Type.FIRE)
	tab.day_pick.select(tab.day_index(1))
	tab.day_pick.item_selected.emit(tab.day_pick.selected)
	tab.hour_box.value = 14.0
	tab.minute_box.value = 30.0
	tab.hours_box.value = 6.0
	tab.name_edit.text = "  Fire Night "
	check("  a day picked: its hour and minute are the owner's", tab.hour_box.editable and tab.minute_box.editable)
	await tab.schedule()
	var second: Dictionary = sent[0][1] if not sent.is_empty() else {}
	check("  tomorrow at 14:30 on this computer's clock, for 6 hours, named: sent so",
		second == {"kind": "stir", "starts_at": EventsTab.start_time(1, 14, 30, int(Time.get_unix_time_from_system())),
			"hours": 6, "land": Element.Type.FIRE, "name": "Fire Night"}, second)
	tab.send = func(_path: String, _said: Dictionary) -> Dictionary:
		return {"ok": false, "status": 400, "error": "amount is a number from 1.25 to 3"}
	await tab.schedule()
	check("refused: the server's reason, on the tab and in Results",
		tab.say_label.text == "The server refused (400): amount is a number from 1.25 to 3"
		and results.get_parsed_text().contains("The server refused (400): amount is a number from 1.25 to 3"))
	sent.clear()
	tab.send = func(path: String, said: Dictionary) -> Dictionary:
		sent.append([path, said])
		return {"ok": true, "status": 200, "data": {"cancelled": said.get("id"), "now": now}}
	tab.cancel_pick.select(1)
	await tab.cancel()
	check("Call off: the one picked, by its id - and it says so",
		sent == [["/api/world/events/cancel", {"id": 8}]] and tab.say_label.text.begins_with("Called off: Double Loot ("), sent)
	sent.clear()
	tab.fetch = func(_path: String) -> Dictionary: return {"ok": false, "status": 404, "error": ""}
	await tab.refresh()
	check("a server without events: says to update it, and Schedule and Call off wait again",
		tab.say_label.text.contains("Update the server") and tab.schedule_button.disabled and tab.cancel_button.disabled
		and results.get_parsed_text().contains("This server does not have events yet (404)"), tab.say_label.text)
	await tab.schedule()
	await tab.cancel()
	check("  and neither sends anything", sent.is_empty(), sent)
	gm.queue_free()
	await get_tree().process_frame
	Api.is_owner = was_owner
	print("  world events: read from the poll and held to what the server allows, on the HUD, set from the GM panel")


func _test_event_report() -> void:
	section("THE EVENT REPORT AND THE DRY RUN - what each event did, and what one would do (0.49.0)")
	# The owner's: "dashboards that show, for each event: XP/hour and gold/hour
	# before/during/after; player count online vs time; which events actually
	# move the needle", and "a dry-run page". test_events.py holds the server's
	# arithmetic and its guardrails; this holds the words, the chart and the
	# ways in.
	var now: int = int(Time.get_unix_time_from_system())
	var hour: int = 3600

	# ---- the chart's numbers ---------------------------------------------------------
	var filled: Dictionary = OnlineChart.fill([{"at": 1000, "players": 2, "everyone": 3}, {"at": 1600, "players": 1, "everyone": 1},
		{"at": 99999, "players": 9, "everyone": 9}, {"at": 0, "players": -4, "everyone": 2}, "junk"], 0, 1800, 300)
	check("the chart's rows into five-minute buckets: a bucket with no row is nobody, one outside is not drawn",
		filled["players"] == [0, 0, 0, 2, 0, 1] and filled["everyone"] == [2, 0, 0, 3, 0, 1], filled)
	check("  whole-number ticks: every one up to 5, then about four steps",
		OnlineChart.ticks(0) == [0, 1] and OnlineChart.ticks(3) == [0, 1, 2, 3] and OnlineChart.ticks(5) == [0, 1, 2, 3, 4, 5]
		and OnlineChart.ticks(10) == [0, 3, 6, 9, 12],
		[OnlineChart.ticks(0), OnlineChart.ticks(10)])

	# ---- the report in words ---------------------------------------------------------
	var starts: int = now - 30 * hour
	var sample: Dictionary = JSON.parse_string(JSON.stringify({
		"now": now, "chart_from": now - 7 * 86400, "sample_seconds": 300, "sampling_since": now - 40 * hour, "kills_kept_days": 14,
		"kinds": [{"kind": "xp", "events": 2, "counted": 1, "lift": 1.0}, {"kind": "loot", "events": 2, "counted": 0, "lift": null},
			{"kind": "stir", "events": 1, "counted": 1, "lift": 0.0}],
		"events": [
			{"id": 4, "name": "On Now", "kind": "xp", "starts_at": now - 1800, "ends_at": now + 5400, "ended_at": now + 5400,
				"state": "on", "lift": 0.5, "verdict": "Brought players: 0.5 more online on average (0 before, 0.5 during).",
				"windows": {"before": {"online": {"players": 0.0, "peak": 0, "everyone": 0.0}, "xp_per_hour": 0, "gold_per_hour": 0,
					"played": 0, "new_players": 0}, "during": {"online": {"players": 0.5, "peak": 1, "everyone": 1.0}, "xp_per_hour": 1500,
					"gold_per_hour": 20000, "played": 1, "new_players": 0}, "after": null}},
			{"id": 3, "name": "Double XP", "kind": "xp", "starts_at": starts, "ends_at": starts + 2 * hour, "ended_at": starts + 2 * hour,
				"state": "over", "lift": 1.0, "verdict": "Brought players: 1 more online on average (0 before, 1 during).",
				"windows": {"before": {"online": {"players": 0.0, "peak": 0, "everyone": 0.0}, "xp_per_hour": 50, "gold_per_hour": 0,
					"played": 1, "new_players": 0}, "during": {"online": {"players": 1.0, "peak": 2, "everyone": 1.5}, "xp_per_hour": 500,
					"gold_per_hour": 150, "played": 1, "new_players": 1}, "after": {"online": {"players": 1.0, "peak": 1, "everyone": 1.0},
					"xp_per_hour": 0, "gold_per_hour": 0, "played": 0, "new_players": 0}}},
			{"id": 2, "name": "Old Loot", "kind": "loot", "starts_at": now - 20 * 86400, "ends_at": now - 20 * 86400 + hour,
				"ended_at": now - 20 * 86400 + hour, "state": "over", "lift": null, "verdict": "Online not counted for it - the counting began later.",
				"windows": {"before": {"online": null, "xp_per_hour": null, "gold_per_hour": 0, "played": null, "new_players": 0},
					"during": {"online": null, "xp_per_hour": null, "gold_per_hour": 0, "played": null, "new_players": 0},
					"after": {"online": null, "xp_per_hour": null, "gold_per_hour": 0, "played": null, "new_players": 0}}}],
		"online": [{"at": starts, "players": 2, "everyone": 3}, {"at": starts + 300, "players": 1, "everyone": 1}]}))
	var lines: Array = EventReportWindow.report_lines(sample)
	var texts: Array = lines.map(func(line: Array) -> String: return str(line[0]))
	check("which kind moves the needle, in words: +1 for XP events, loot not counted yet, the stir no change",
		texts.has("More XP: +1 player online on average, across 1 event counted.")
		and texts.has("More loot: not counted yet (2 events).")
		and texts.has("A land stirs: no change in who was online, across 1 event counted."), texts.slice(0, 6))
	check("  each event: its name, when and how long, and whether it brought players",
		texts.has("Double XP - %s, 2h 00m (over)" % LocalTime.stamp(starts, now))
		and texts.has("  Brought players: 1 more online on average (0 before, 1 during)."), texts)
	check("  before, during and after: online, XP and gold an hour, who played and who signed up",
		texts.has("  Online: 0 before, 1 during, 1 after") and texts.has("  XP an hour: 50 before, 500 during, 0 after")
		and texts.has("  Gold an hour: 0 before, 150 during, 0 after")
		and texts.has("  Played: 1 before, 1 during, 0 after; new players: 0 before, 1 during, 0 after"), texts)
	check("  one on now has no after yet; one past the kill log has no XP - a dash, not a zero; big numbers short",
		texts.has("  Online: 0 before, 0.5 during, not yet after") and texts.has("  Gold an hour: 0 before, 20K during, not yet after")
		and texts.has("  XP an hour: - before, - during, - after"), texts)
	var quiet: Array = EventReportWindow.report_lines({"now": now}).map(func(line: Array) -> String: return str(line[0]))
	check("  an empty report says so, and that the counting has not begun",
		quiet.has("No events in the last 30 days. Set one on the Events tab.")
		and quiet.has("Who is online has not been counted yet - it is counted while anybody plays."), quiet)

	# ---- the window ------------------------------------------------------------------
	var was_owner: bool = Api.is_owner
	Api.is_owner = true
	var window: EventReportWindow = (load("res://scene/ui/owner/eventreport.tscn") as PackedScene).instantiate() as EventReportWindow
	window.visible = false
	add_child(window)
	await get_tree().process_frame
	var asked: Array = []
	window.get_request = func(path: String) -> Dictionary:
		asked.append(path)
		return {"ok": true, "status": 200, "data": sample}
	await window.open()
	await get_tree().process_frame
	var shown: String = window.report_box.get_parsed_text()
	var chart: OnlineChart = window.chart
	check("opened, it reads the server and shows the report",
		window.visible and asked == ["/api/world/events/report"] and shown.contains("WHAT MOVES THE NEEDLE")
		and shown.contains("Double XP - "), [asked, shown.left(40)])
	@warning_ignore("integer_division")
	var at_double: int = (starts - (now - 7 * 86400)) / 300
	check("  the chart: seven days of five minutes, the counts in their buckets, the events as bands",
		chart.players.size() == 2016 and chart.players[at_double] == 2 and chart.everyone[at_double] == 3
		and chart.bands.size() == 2 and str(chart.bands[1]["name"]) == "Double XP", [chart.players.size(), chart.bands.size()])
	check("  its hover says the time, both counts and the event on then",
		chart.tooltip_lines(at_double) == [LocalTime.stamp(chart.from_at + at_double * 300, chart.from_at + 2016 * 300),
			"Players 2 - everyone 3", "Double XP"], chart.tooltip_lines(at_double))
	chart.size = Vector2(560, 190)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(OnlineChart.PAD_LEFT + 10.0, 100.0)
	chart._gui_input(motion)
	await get_tree().process_frame
	var hovered: int = chart.hover
	# THE HOVER SITS ON THE LINE: a column two pixels wide holds several
	# buckets, the line is drawn at the most of them, and the hover picks that
	# one - so a short visit can be found under the mouse.
	var probe := OnlineChart.new()
	probe.size = Vector2(560, 190)
	probe.players.resize(2016)
	probe.players.fill(0)
	probe.everyone.resize(2016)
	probe.everyone.fill(0)
	var plot: Rect2 = probe._plot()
	var columns: int = int(plot.size.x / 2.0)
	var first_in: int = int(10.0 / columns * 2016)
	var last_in: int = int(11.0 / columns * 2016) - 1
	probe.players[last_in] = 4
	probe.everyone[last_in] = 4
	var picked: int = probe.bucket_under(plot.position.x + (10.5 / columns) * plot.size.x, plot)
	check("  under the mouse, the bucket the line is drawn at - the most in its column - and the line's end said as drawn",
		last_in > first_in and picked == last_in and probe.value_at(probe._y_of(2.0, 3, plot), 3, plot) == 2,
		[first_in, last_in, picked])
	probe.free()
	chart.mouse_exited.emit()
	check("a mouse over it picks the bucket under it, and leaving clears it", hovered >= 0 and hovered < 2016
		and chart.hover == -1, hovered)
	window.get_request = func(_path: String) -> Dictionary: return {"ok": false, "status": 404, "error": ""}
	await window.refresh()
	check("a server without it says to update it", window.status.text.contains("Update the server"), window.status.text)
	Api.is_owner = false
	var asked_before: int = asked.size()
	window.get_request = func(path: String) -> Dictionary:
		asked.append(path)
		return {"ok": true, "status": 200, "data": sample}
	await window.refresh()
	check("  and it never asks for anybody but the owner", asked.size() == asked_before
		and window.status.text == "The event report is the owner's.")
	Api.is_owner = true
	window.close()
	check("  its x closes it", not window.visible)
	window.queue_free()
	await get_tree().process_frame

	# ---- the Events tab: Dry run and Report -------------------------------------------
	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var tab: EventsTab = gm.get("events_tab") as EventsTab
	var tabs: TabContainer = gm.get_node_or_null("%ownertabs") as TabContainer
	if tabs != null and tab != null:
		tabs.current_tab = tab.get_index()
		await get_tree().process_frame
	check("the Events tab has Report beside its status, and Dry run beside Schedule - and still fits 370 (%d)"
		% PanelWindow.content_minimum(gm).x,
		tab.report_button.get_parent() == tab.status_label.get_parent()
		and tab.dry_run_button.get_parent() == tab.schedule_button.get_parent() and PanelWindow.content_minimum(gm).x <= 370.0)
	var sent: Array = []
	var preview: Dictionary = JSON.parse_string(JSON.stringify({
		"allowed": true, "why": "", "warnings": [], "now": now, "peak_online": 3,
		"event": {"id": null, "name": "Double XP", "kind": "xp", "starts_at": now, "ends_at": now + 3 * hour, "land": 0},
		"worst": [{"land": 1, "name": "dark", "xp": 2.0, "loot": 1.5, "together": 3.0}, {"land": 6, "name": "fire", "xp": 2.0, "loot": 1.5, "together": 3.0}],
		"limits": {"xp": 3.0, "loot": 3.0, "together": 6.0},
		"forecast": {"players": 20, "player_hours": 12, "enough": true, "xp": {"usual": [24000, 54000], "with": [48000, 108000]},
			"gold": {"usual": [2400, 5400], "with": [2400, 5400]}}}))
	var schedule_view: Variant = JSON.parse_string(JSON.stringify({"events": [], "now": now, "limits": {}}))
	tab.fetch = func(_path: String) -> Dictionary: return {"ok": true, "status": 200, "data": schedule_view}
	tab.send = func(path: String, said: Dictionary) -> Dictionary:
		sent.append([path, said])
		return {"ok": true, "status": 200, "data": preview}
	check("before the server is read, Dry run waits", tab.dry_run_button.disabled)
	await tab.dry_run()
	check("  and sends nothing", sent.is_empty(), sent)
	await tab.refresh()
	tab.kind_pick.select(0)
	tab.kind_pick.item_selected.emit(0)
	tab.amount_box.value = 2.0
	tab.land_pick.select(tab.land_index(EventsTab.LAND_ANY))
	tab.day_pick.select(0)
	tab.day_pick.item_selected.emit(0)
	tab.hours_box.value = 3.0
	await tab.dry_run()
	var asked_for: Dictionary = sent[0][1] if not sent.is_empty() else {}
	check("Dry run sends what the controls hold, for 20 players, to the dry run - not to Schedule",
		sent.size() == 1 and sent[0][0] == "/api/world/events/preview" and asked_for.get("players") == 20
		and asked_for.get("kind") == "xp" and asked_for.get("hours") == 3, sent)
	var results: RichTextLabel = gm.get("results") as RichTextLabel
	var said_text: String = results.get_parsed_text() if results != null else ""
	check("  and Results says it: allowed, the most at once, and what 20 players might earn",
		tab.say_label.text == "Dry run: allowed - see Results."
		and said_text.contains("Dry run - Double XP, now, for 3 h: allowed.")
		and said_text.contains("The most at once: 2x XP and 1.5x loot (3x together) for every monster. The ceilings: 3x XP, 3x loot, 6x together.")
		and said_text.contains("If 20 players play all 3 h: 24K-54K XP as usual, 48K-108K with it; 2,400-5,400 gold as usual, 2,400-5,400 with it.")
		and said_text.contains("From 12 player-hours of play in the last two weeks. The most players online at once then: 3."), said_text)
	var refused: Dictionary = preview.duplicate(true)
	refused["allowed"] = false
	refused["why"] = "Too much at once for every monster: 3x XP and 2x loot (6x together)."
	refused["worst"] = [{"land": 6, "name": "fire", "xp": 3.0, "loot": 3.0, "together": 9.0}, {"land": 1, "name": "dark", "xp": 3.0, "loot": 1.0, "together": 3.0}]
	refused["forecast"]["enough"] = false
	var refused_lines: Array[String] = EventsTab.dry_run_lines(refused)
	check("  not allowed: why, the land that would be paid too much, and a forecast from too little play said to be a guess",
		refused_lines[0].ends_with(": not allowed.") and refused_lines[1].begins_with("Too much at once")
		and refused_lines[2].begins_with("The most at once: 3x XP and 3x loot (9x together) for the fire lands' monsters.")
		and refused_lines[refused_lines.size() - 1].contains("too few to be more than a guess"), refused_lines)
	tab.send = func(_path: String, _said: Dictionary) -> Dictionary: return {"ok": false, "status": 404, "error": ""}
	await tab.dry_run()
	check("  a server without the dry run says to update it", tab.say_label.text == "This server has no dry run yet (404). Update the server.",
		tab.say_label.text)
	tab.send = func(_path: String, _said: Dictionary) -> Dictionary:
		return {"ok": true, "status": 201, "data": {"event": {"id": 9, "name": "The Ice Lands Stir", "starts_at": now + hour,
			"ends_at": now + 2 * hour, "description": "The ice lands stir for the whole event."}, "now": now,
			"warnings": ["The stirring lands are switched off, so this will stir nothing until they are on (World tab)."]}}
	tab.day_pick.select(tab.day_index(1))
	tab.day_pick.item_selected.emit(tab.day_pick.selected)
	await tab.schedule()
	check("Scheduled with a warning: the warning is in Results too",
		results.get_parsed_text().contains("The stirring lands are switched off, so this will stir nothing until they are on (World tab)."))
	var opened: Array = []
	gm.set("open_window", func(method: String, _who: String) -> bool:
		opened.append(method)
		return true)
	tab.report_button.pressed.emit()
	check("Report opens the Event report through the HUD", opened == ["open_event_report"], opened)
	gm.set("open_window", func(_method: String, _who: String) -> bool: return false)
	tab.report_button.pressed.emit()
	check("  and out of the game it says so", tab.say_label.text == "The event report opens from inside the game.")
	gm.queue_free()
	await get_tree().process_frame

	# ---- the HUD builds it for the owner only ------------------------------------------
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await get_tree().process_frame
	Api.is_owner = false
	hud.open_event_report()
	check("the HUD builds the Event report for nobody but the owner", hud.event_report == null)
	Api.is_owner = was_owner
	hud.queue_free()
	await get_tree().process_frame
	print("  event report: the needle in words, each event's three windows, the chart and its hover; the dry run in Results")


func _test_land_report() -> void:
	section("THE LANDS WINDOW AND THE NEXT STIR - every land's numbers, the world's choice and why (0.50.0)")
	# The owner, from a "Behavior Insights" idea: per land, players, kills, time
	# since its last event, whether it is overfarmed, ignored or healthy; a
	# suggested next stir with a reason; accept or override on the GM panel.
	# test_insights.py holds the server's rules; this holds the words, the
	# hours chart and the ways in.
	var now: int = int(Time.get_unix_time_from_system())

	# ---- the hours, this computer's ----------------------------------------------------
	var utc: Array = []
	utc.resize(24)
	utc.fill(0.0)
	utc[1] = 1.4
	utc[2] = 1.2
	utc[0] = 0.8
	var local: Array[float] = HoursChart.to_local(utc, -300)
	check("players online by UTC hour into this computer's hours: five hours behind, 01:00 UTC is 20:00",
		is_equal_approx(local[20], 1.4) and is_equal_approx(local[21], 1.2) and is_equal_approx(local[19], 0.8)
		and is_equal_approx(local[1], 0.0), local)
	check("  an hour of the day in this computer's clock, half-hour zones too",
		HoursChart.local_hour(1, -300) == "20:00" and HoursChart.local_hour(0, 330) == "05:30"
		and HoursChart.local_hour(23, 60) == "00:00")
	check("  the axis tops at the most, rounded up to a whole player - 1 at least - so halfway is clean too",
		is_equal_approx(HoursChart.top_of([0.4, 1.3] as Array[float]), 2.0) and is_equal_approx(HoursChart.top_of([0.4] as Array[float]), 1.0))
	var chart := HoursChart.new()
	chart.players = local
	check("  the busiest three, most first; the hover says the hour and the average",
		chart.busiest() == [20, 21, 19] and chart.tooltip(20) == "20:00-21:00: 1.4 players on average", chart.busiest())
	chart.players[3] = 1.0
	check("  one player is one player", chart.tooltip(3) == "03:00-04:00: 1 player on average", chart.tooltip(3))
	chart.free()
	check("busiest hours in words - and, before three days are counted, that it is still counting",
		LandReportWindow.hours_text([20, 21, 19] as Array[int], local, 14.0)
			== "Busiest hours, your time: 20:00 (1.4 on average), 21:00 (1.2), 19:00 (0.8) - over 14 days."
		and LandReportWindow.hours_text([] as Array[int], local, 1.0).begins_with("Players online by hour, your time - counting began 1 days ago"),
		LandReportWindow.hours_text([20, 21, 19] as Array[int], local, 14.0))

	# ---- every land, in words -------------------------------------------------------
	check("how long ago: never, now, minutes, hours, days",
		LandReportWindow.ago(null, now) == "never" and LandReportWindow.ago(now - 30, now) == "now"
		and LandReportWindow.ago(now - 2700, now) == "45m ago" and LandReportWindow.ago(now - 3 * 3600, now) == "3h ago"
		and LandReportWindow.ago(now - 3 * 86400, now) == "3d ago")
	var fire_row: Dictionary = {"element": 6, "name": "fire", "kills_day": 12, "kills_week": 13, "players_week": 1,
		"newcomers_now": 0, "last_stirred_at": now - 5 * 3600, "last_event_at": null, "busiest_hour": 1, "status": "busy"}
	var ice_row: Dictionary = {"element": 3, "name": "ice", "kills_day": 1, "kills_week": 2, "players_week": 1,
		"newcomers_now": 1, "last_stirred_at": null, "last_event_at": now - 2 * 86400, "busiest_hour": null, "status": "quiet"}
	check("a land's row: kills today and this week, players, new players now, last stir and event, busiest hour (yours), status",
		LandReportWindow.row_cells(fire_row, now, -300) == ["Fire", "12", "13", "1", "-", "5h ago", "never", "20:00", "busy"]
		and LandReportWindow.row_cells(ice_row, now, -300) == ["Ice", "1", "2", "1", "1", "never", "2d ago", "-", "quiet"],
		LandReportWindow.row_cells(fire_row, now, -300))
	var reason: String = "Wind: the least hunted in the last day (2 kills) without new players in it - passing over Ice (1 new player), where they are learning."
	var sample: Dictionary = JSON.parse_string(JSON.stringify({"now": now, "few": true, "total_week": 18, "new_player_level": 10,
		"next": {"element": 4, "name": "wind", "at": now + 3600, "reason": reason},
		"lands": [fire_row, ice_row], "hours": {"players": utc, "days": 14.0}}))
	var nexts: Array = LandReportWindow.next_lines(sample, now).map(func(line: Array) -> String: return str(line[0]))
	check("the next stir: when, which and why - and where to take it or pick another",
		nexts == ["NEXT TO STIR", "At %s: %s" % [LocalTime.stamp(now + 3600, now), reason],
			"To take it now or pick another, use Stir it now on the World tab."], nexts)
	check("  the lands switched off: nothing, and why",
		LandReportWindow.next_lines({"next": null}, now)[1][0] == "Nothing - the stirring lands are switched off (World tab).")
	check("  a week of few kills is said to be a rough read",
		LandReportWindow.note_lines(sample)[0][0] == "Only 18 kills this week - a rough read.")

	# ---- the window -------------------------------------------------------------------
	var was_owner: bool = Api.is_owner
	Api.is_owner = true
	var window: LandReportWindow = (load("res://scene/ui/owner/landreport.tscn") as PackedScene).instantiate() as LandReportWindow
	window.visible = false
	add_child(window)
	await get_tree().process_frame
	var asked: Array = []
	window.get_request = func(path: String) -> Dictionary:
		asked.append(path)
		return {"ok": true, "status": 200, "data": sample}
	LocalTime._bias_minutes = -300
	LocalTime._bias_known = true
	LocalTime._bias_read_at = Time.get_ticks_msec()
	await window.open()
	LocalTime._bias_known = false
	await get_tree().process_frame
	var shown: String = window.report_box.get_parsed_text()
	check("opened, it reads the server: the next stir, the table of every land, the notes",
		window.visible and asked == ["/api/server/insights"] and shown.contains("NEXT TO STIR") and shown.contains(reason)
		and shown.contains("EVERY LAND, THIS WEEK") and shown.contains("Fire") and shown.contains("5h ago")
		and shown.contains("rough read"), [asked, shown.left(80)])
	check("  and the hours, in this computer's hours, with the busiest said",
		is_equal_approx(window.hours_chart.players[20], 1.4)
		and window.hours_label.text.begins_with("Busiest hours, your time: 20:00 (1.4 on average)"), window.hours_label.text)
	window.get_request = func(_path: String) -> Dictionary: return {"ok": false, "status": 404, "error": ""}
	await window.refresh()
	check("a server without it says to update it", window.status.text.contains("Update the server"), window.status.text)
	Api.is_owner = false
	var asked_before: int = asked.size()
	window.get_request = func(path: String) -> Dictionary:
		asked.append(path)
		return {"ok": true, "status": 200, "data": sample}
	await window.refresh()
	check("  and it never asks for anybody but the owner", asked.size() == asked_before
		and window.status.text == "The land report is the owner's.")
	Api.is_owner = true
	window.close()
	check("  its x closes it", not window.visible)
	window.queue_free()
	await get_tree().process_frame

	# ---- the World tab: the next stir, offered; Lands -----------------------------------
	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var tab: WorldTab = gm.get("world_tab") as WorldTab
	var tabs: TabContainer = gm.get_node_or_null("%ownertabs") as TabContainer
	if tabs != null and tab != null:
		tabs.current_tab = tab.get_index()
		await get_tree().process_frame
	check("the World tab has a Lands button beside Refresh, and still fits 370 (%d)" % PanelWindow.content_minimum(gm).x,
		tab.lands_button.get_parent() == tab.refresh_button.get_parent() and PanelWindow.content_minimum(gm).x <= 370.0)
	var view: Variant = JSON.parse_string(JSON.stringify({
		"settings": {"on": true, "hours": 3}, "state": {"on": true, "tick": 12, "element": 6, "ends_at": now + 3600, "now": now},
		"recent": [], "lands": [{"element": 6, "name": "fire", "kills": 3}], "now": now,
		"next": {"element": 4, "name": "wind", "at": now + 3600, "reason": reason}}))
	tab.fetch = func(_path: String) -> Dictionary: return {"ok": true, "status": 200, "data": view}
	await tab.refresh()
	check("the next stir and why, where the land's kills were - and it is the land offered for Stir it now",
		tab.lands_label.text == "Next to stir (%s): %s" % [LocalTime.stamp(now + 3600, now), reason]
		and tab.land_pick.get_item_id(tab.land_pick.selected) == Element.Type.WIND, tab.lands_label.text)
	var old_view: Dictionary = (view as Dictionary).duplicate(true)
	old_view.erase("next")
	tab.show_answer(old_view)
	check("  a server from before it: the kills, as before", tab.lands_label.text.begins_with("Kills in the last day: fire 3"),
		tab.lands_label.text)
	var opened: Array = []
	gm.set("open_window", func(method: String, _who: String) -> bool:
		opened.append(method)
		return true)
	tab.lands_button.pressed.emit()
	check("Lands opens the Lands window through the HUD", opened == ["open_land_report"], opened)
	gm.set("open_window", func(_method: String, _who: String) -> bool: return false)
	tab.lands_button.pressed.emit()
	check("  and out of the game it says so", tab.say_label.text == "The Lands window opens from inside the game.")
	gm.queue_free()
	await get_tree().process_frame

	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await get_tree().process_frame
	Api.is_owner = false
	hud.open_land_report()
	check("the HUD builds the Lands window for nobody but the owner", hud.land_report == null)
	Api.is_owner = was_owner
	hud.queue_free()
	await get_tree().process_frame
	print("  lands: every land in a table, the next stir and why, the hours in yours; offered on the World tab")


func _test_armour_resistance() -> void:
	section("ARMOUR RESISTS AN ELEMENT - rolled in the id, added up, taken off a hit")

	var T := ItemData.Type
	var S := ItemData.EquipSlot
	# The suite's own pieces, like _test_quality_rolls: a jade chest's shape
	# (tier 2, armour and health) and an iron sword's, so the list below is the
	# server's own list with the ids renamed.
	var chest: ItemData = _menu_item("rtest_chest", T.ARMOR, S.CHEST)
	chest.display_name = "Test Chest"
	chest.tier = 2
	chest.armor_value = 6
	chest.bonus_max_hp = 20
	var helm: ItemData = _menu_item("rtest_helm", T.ARMOR, S.HELM)
	helm.tier = 2
	helm.armor_value = 3
	var ring: ItemData = _menu_item("rtest_ring", T.ARMOR, S.RING)
	ring.tier = 1
	ring.bonus_max_mana = 5
	var sword: ItemData = _menu_item("rtest_sword", T.WEAPON, S.WEAPON)
	sword.tier = 1
	sword.damage = 20
	var stone: ItemData = _menu_item("rtest_stone", T.ARMOR, S.NONE)
	stone.tier = 2
	stone.armor_value = 1
	var bare: ItemData = _menu_item("rtest_bare", T.ARMOR, S.BOOTS)
	bare.tier = 0
	bare.armor_value = 1
	# Armour that could resist but has no stat to roll - no such piece is in
	# the catalogue, so a resistance on its own must still not be a roll.
	var blank: ItemData = _menu_item("rtest_blank", T.ARMOR, S.RING)
	blank.tier = 1
	var boots: ItemData = _menu_item("rtest_boots", T.ARMOR, S.BOOTS)
	boots.tier = 1
	boots.armor_value = 2
	var made: Array = [chest, helm, ring, sword, stone, bare, blank, boots]
	# A whole ember set, every slot but the weapon's, for the cap.
	var ember_slots: Array = [S.HELM, S.CHEST, S.LEGS, S.BOOTS, S.SHIELD, S.RING, S.AMULET]
	var ember: Array = []
	for i in ember_slots.size():
		var piece: ItemData = _menu_item("rtest_ember%d" % i, T.ARMOR, ember_slots[i])
		piece.tier = 5
		piece.armor_value = 1
		ember.append(piece)
	made.append_array(ember)
	for item in made:
		ItemRegistry._items[item.item_id] = item

	# ---- the numbers, on both sides ------------------------------------------
	check("the seven lands' elements, iron 2-5 up to ember 6-13, at most 50%",
		GameConstants.RESIST_ELEMENTS.map(func(e): return Element.name_for(int(e)))
			== ["dark", "light", "ice", "wind", "earth", "fire", "water"]
		and GameConstants.RESIST_RANGES == [[0, 0], [2, 5], [3, 7], [4, 9], [5, 11], [6, 13]]
		and GameConstants.RESIST_CAP == 50 and GameConstants.RESIST_LETTER == "r")
	check("  its letter is no stat's",
		not GameConstants.QUALITY_FIELDS.map(func(pair): return pair[0]).has(GameConstants.RESIST_LETTER))
	check("  every element is one digit, which is how an id spells it",
		GameConstants.RESIST_ELEMENTS.all(func(e): return int(e) >= 1 and int(e) <= 9))
	var consts: Dictionary = _load_gamedata().get("constants", {})
	check("  and gamedata.json says the same to the server (re-run the exporter if not)",
		str(consts.get("resist_letter", "")) == GameConstants.RESIST_LETTER
		and Array(consts.get("resist_elements", [])).map(func(e): return int(e)) == GameConstants.RESIST_ELEMENTS
		and Array(consts.get("resist_ranges", [])).map(func(row): return [int(row[0]), int(row[1])])
			== GameConstants.RESIST_RANGES
		and int(consts.get("resist_cap", -1)) == GameConstants.RESIST_CAP,
		[consts.get("resist_letter"), consts.get("resist_ranges"), consts.get("resist_cap")])
	var exporter: String = FileAccess.get_file_as_string("res://src/tools/exportgamedata.gd")
	var unwritten: Array = ["resist_letter", "resist_elements", "resist_ranges", "resist_cap"].filter(
		func(key): return not exporter.contains("\"%s\":" % key))
	check("  because the exporter writes all four", unwritten.is_empty(), unwritten)
	check("a tier's range, past the table its last row, and none below tier 1",
		GameConstants.resist_range(2) == Vector2i(3, 7) and GameConstants.resist_range(5) == Vector2i(6, 13)
		and GameConstants.resist_range(6) == Vector2i(6, 13) and GameConstants.resist_range(0) == Vector2i.ZERO
		and GameConstants.resist_range(-1) == Vector2i.ZERO)
	check("armour resists when rolled; a weapon, an unworn piece or a tier-0 one never",
		chest.resists_when_rolled() and ring.resists_when_rolled()
		and not sword.resists_when_rolled() and not stone.resists_when_rolled() and not bare.resists_when_rolled())

	# ---- reading one ------------------------------------------------------------
	var rolled: ItemData = ItemRegistry.get_item("rtest_chest~a104h96r605")
	var unresisting: ItemData = ItemRegistry.get_item("rtest_chest~a104h96")
	check("a resisting roll is an item, resisting fire by 5%",
		rolled != null and ItemRegistry.has_item("rtest_chest~a104h96r605")
		and rolled.resist_element == Element.Type.FIRE and rolled.resist_percent == 5,
		str([rolled.resist_element, rolled.resist_percent]) if rolled != null else "null")
	if rolled == null or unresisting == null:
		for item in made:
			ItemRegistry._items.erase(item.item_id)
		return
	check("  its stats are the same roll's without it - a resistance is not a stat",
		rolled.armor_value == unresisting.armor_value and rolled.bonus_max_hp == unresisting.bonus_max_hp
		and rolled.rolls == unresisting.rolls and rolled.base_id == "rtest_chest" and not rolled.is_perfect())
	check("  and says so in words: \"Resists fire 5%\"", rolled.resistance_text() == "Resists fire 5%",
		rolled.resistance_text())
	check("a roll from before resistances is read, and resists nothing",
		unresisting.resist_element == Element.Type.NONE and unresisting.resist_percent == 0
		and unresisting.resistance_text() == "")
	check("the catalogue piece itself resists nothing", chest.resist_percent == 0 and chest.resistance_text() == "")
	var perfect: ItemData = ItemRegistry.get_item("rtest_chest~a120h120r607")
	check("a Perfect resists at the top of its range",
		perfect != null and perfect.is_perfect() and perfect.resist_percent == 7)
	check("split_roll names the resistance beside the rolls",
		ItemRegistry.split_roll("rtest_chest~a104h96r605")
		== {"base": "rtest_chest", "rolls": {"armor_value": 104, "bonus_max_hp": 96},
			"resist": {"element": Element.Type.FIRE, "percent": 5}})

	# THE SAME LIST test_quality.py's Q-8 holds, rtest_chest for jadechest and
	# rtest_sword for ironsword. One roll has one spelling on both sides.
	var malformed: Array = [
		"rtest_sword~d107r605", "rtest_chest~a104h96r608", "rtest_chest~a104h96r602",
		"rtest_chest~a104h96r005", "rtest_chest~a104h96r805", "rtest_chest~a104h96r905",
		"rtest_chest~a104h96r65", "rtest_chest~a104h96r6005", "rtest_chest~r605a104h96",
		"rtest_chest~a104h96r605r605", "rtest_chest~r605", "rtest_chest~a120h120r606",
		"rtest_chest~a104h96R605", "rtest_chest~a104r605h96",
		# and two read as the 107 roll until 7 Oct: the newline by both sides
		# (a regex's $ matches before one), the Arabic-Indic digits by the server
		"rtest_sword~d107\n", "rtest_sword~d\u0661\u0660\u0667",
		# a tier-0 piece, and armour with no stats at all - the server's Q-8
		# makes one for the purpose
		"rtest_bare~r605", "rtest_blank~r303",
	]
	var accepted: Array = malformed.filter(func(id): return ItemRegistry.has_item(id) or not ItemRegistry.split_roll(id).is_empty())
	check("everything that only looks like a resistance is not an item (%d spellings)" % malformed.size(),
		accepted.is_empty(), accepted)
	var every: Array = []
	for element in GameConstants.RESIST_ELEMENTS:
		for percent in range(3, 8):
			if ItemRegistry.get_item("rtest_chest~a100h100r%d%02d" % [int(element), percent]) == null:
				every.append([element, percent])
	check("every element and every percent in a jade piece's range reads", every.is_empty(), every)

	# ---- wearing it ------------------------------------------------------------
	var body: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	body._set_stat_curve()
	body.level = 10
	body.equipped = {}
	check("wearing nothing resists nothing", body.equipped_resistance(Element.Type.FIRE) == 0
		and body.resistances().is_empty())
	body.equipped = {"chest": "rtest_chest~a104h96r605", "helm": "rtest_helm~a100r607",
		"ring": "rtest_ring~m100r303"}
	check("a fire chest and a fire helm add up: 12% against fire",
		body.equipped_resistance(Element.Type.FIRE) == 12, body.equipped_resistance(Element.Type.FIRE))
	check("  an ice ring is 3% against ice and nothing against fire's 12",
		body.equipped_resistance(Element.Type.ICE) == 3)
	check("  a physical hit is armour's alone", body.equipped_resistance(Element.Type.NONE) == 0)
	check("  and the list is strongest first", body.resistances()
		== [[Element.Type.FIRE, 12], [Element.Type.ICE, 3]], body.resistances())
	var plain: int = body.damage_taken(1000, Element.Type.NONE)
	var water_hit: int = body.damage_taken(1000, Element.Type.WATER)
	var fire_hit: int = body.damage_taken(1000, Element.Type.FIRE)
	check("a water hit takes what a physical one does: nothing worn resists water",
		water_hit == plain, [water_hit, plain])
	var reduction: float = body._get_defense_tier()["reduction"]
	var armour: float = PlayerStats.armour_reduction(body.equipped_armor_value())
	check("a fire hit takes 12%% less, after the defense tier and the armour (%d against %d)" % [fire_hit, plain],
		fire_hit == maxi(1, int(1000 * (1.0 - reduction) * (1.0 - armour) * 0.88)) and fire_hit < plain,
		[fire_hit, plain])
	check("  and the smallest hit still lands", body.damage_taken(1, Element.Type.FIRE) == 1)
	var src: String = FileAccess.get_file_as_string("res://src/characters/player.gd")
	var body_at: int = src.find("func take_damage(")
	check("take_damage() lands what damage_taken() says",
		_first_code_index(src, "var reduced_amount: int = damage_taken(amount, element)", body_at) != -1
		and _first_code_index(src, "var reduced_amount: int = damage_taken(amount, element)", body_at)
			< _first_code_index(src, "hp = clamp(hp - reduced_amount", body_at))

	var set_ids: Dictionary = {}
	for i in ember.size():
		set_ids[["helm", "chest", "legs", "boots", "shield", "ring", "amulet"][i]] = "rtest_ember%d~a100r613" % i
	body.equipped = set_ids
	check("a whole fire set at 13% a piece is 91%, held to the 50% cap",
		body.equipped_resistance(Element.Type.FIRE) == GameConstants.RESIST_CAP)
	reduction = body._get_defense_tier()["reduction"]
	armour = PlayerStats.armour_reduction(body.equipped_armor_value())
	check("  so a fire hit is at most halved by it, never gone",
		body.damage_taken(1000, Element.Type.FIRE) == maxi(1, int(1000 * (1.0 - reduction) * (1.0 - armour) * 0.5)))
	check("a sword that somehow said it resisted would add nothing: a weapon never reads one",
		not ItemRegistry.has_item("rtest_sword~d107r605"))

	# ---- the Gear window ----------------------------------------------------------
	var panel: Node = (load("res://scene/ui/equipment/equipmentpanel.tscn") as PackedScene).instantiate()
	add_child(panel)
	await get_tree().process_frame
	panel.player = body
	body.equipped = {}
	panel._refresh_summary()
	check("the Gear window's Resists row is a dash wearing nothing",
		panel.resist_label != null and panel.resist_label.text == "-",
		panel.resist_label.text if panel.resist_label != null else "no row")
	body.equipped = {"chest": "rtest_chest~a104h96r605", "helm": "rtest_helm~a100r607",
		"ring": "rtest_ring~m100r303"}
	panel._refresh_summary()
	check("  and \"Fire 12%, Ice 3%\" in the good colour in a fire chest, a fire helm and an ice ring",
		panel.resist_label.text == "Fire 12%, Ice 3%"
		and panel.resist_label.get_theme_color("font_color") == panel.COLOUR_GOOD, panel.resist_label.text)
	check("  with no hover text, since that is all of them", panel.resist_label.tooltip_text == "")
	body.equipped["boots"] = "rtest_boots~a100r104"
	panel._refresh_summary()
	check("a third element is counted, not spelled: \"Fire 12%, Dark 4% +1\" - the window keeps its width",
		panel.resist_label.text == "Fire 12%, Dark 4% +1", panel.resist_label.text)
	check("  and the whole list is the row's hover text",
		panel.resist_label.tooltip_text == "Fire 12%, Dark 4%, Ice 3%"
		and panel.resist_label.mouse_filter == Control.MOUSE_FILTER_STOP, panel.resist_label.tooltip_text)
	panel.queue_free()
	body.free()

	# ---- the tooltip and the till ---------------------------------------------------
	var shelf: String = ItemTooltip._requirement_lines(chest, true)
	check("on the shelf a piece of armour says it resists \"?\", and its tier's range",
		shelf.contains("Resists ? - one element, 3-7%"), shelf)
	check("  a sword on the shelf says nothing of resisting",
		not ItemTooltip._requirement_lines(sword, true).contains("Resists"))
	check("a piece you own says what it resists", ItemTooltip._requirement_lines(rolled).contains("Resists fire 5%"),
		ItemTooltip._requirement_lines(rolled))
	check("  and one from before says nothing", not ItemTooltip._requirement_lines(unresisting).contains("Resists"))
	var Shop: Script = load("res://src/ui/shop/shopinventory.gd") as Script
	check("buying one says what it resists, beside its quality",
		Shop.purchase_line(rolled, "rtest_chest~a104h96r605", 2000)
		== "Bought Test Chest for %s - quality 100%%, resists fire 5%%." % GameConstants.gold_text(2000),
		Shop.purchase_line(rolled, "rtest_chest~a104h96r605", 2000))
	check("  and a Perfect too", Shop.purchase_line(perfect, "rtest_chest~a120h120r607", 2000)
		.ends_with("every stat at 120%, resists fire 7%!"), Shop.purchase_line(perfect, "rtest_chest~a120h120r607", 2000))
	check("  and a roll from before as it was", Shop.purchase_line(unresisting, "rtest_chest~a104h96", 2000)
		.ends_with("- quality 100%."))

	for item in made:
		ItemRegistry._items.erase(item.item_id)
	for id in ItemRegistry._rolled.keys():
		if String(id).begins_with("rtest_"):
			ItemRegistry._rolled.erase(id)

	# ---- a hazard's hit is an element too ---------------------------------------
	# The spike door handed take_damage() the StringName &"physical" for its
	# int element - a type error the first time a door has contact damage (none
	# does yet), and hazards are where the owner means to take elements next.
	var door: Node = (load("res://scene/interactables/spikedoor.tscn") as PackedScene).instantiate()
	add_child(door)
	await get_tree().process_frame
	door.contact_damage = 7
	door._is_raised = true
	var stand_in := GDScript.new()
	stand_in.source_code = "extends Node\nvar hits: Array = []\nfunc take_damage(amount: int, element: int = 0) -> void:\n\thits.append([amount, element])\n"
	stand_in.reload()
	var walker := Node.new()
	walker.set_script(stand_in)
	walker.add_to_group("player")
	door._on_hurtzone_body_entered(walker)
	check("a spike door's contact damage lands as a physical hit, not a type error",
		walker.hits == [[7, Element.Type.NONE]], walker.hits)
	walker.free()
	door.queue_free()


func _test_quality_rolls() -> void:
	section("QUALITY ROLLS - a dropped piece's stats, read from its id the server's way")

	# The suite's own pieces, registered for the test: the real ones' pictures
	# are in the private art pack, and a clone without it does not load them.
	var T := ItemData.Type
	var S := ItemData.EquipSlot
	var amulet: ItemData = _menu_item("qtest_amulet", T.ARMOR, S.AMULET)
	amulet.display_name = "Test Amulet"
	amulet.tier = 2
	amulet.value = 1456
	amulet.required_level = 5
	amulet.armor_value = 2
	amulet.bonus_max_hp = 10
	amulet.bonus_max_mana = 12
	amulet.bonus_damage_percent = 1
	var sword: ItemData = _menu_item("qtest_sword", T.WEAPON, S.WEAPON)
	sword.display_name = "Test Sword"
	sword.tier = 1
	sword.value = 400
	sword.damage = 20
	var potion: ItemData = _menu_item("qtest_potion", T.CONSUMABLE, S.NONE, 99)
	potion.restore_amount = 50
	for item in [amulet, sword, potion]:
		ItemRegistry._items[item.item_id] = item

	# ---- the range is one number, on both sides -----------------------------
	check("85 to 115, Perfect at 120, one in 100 - the owner's numbers",
		[GameConstants.QUALITY_LOW, GameConstants.QUALITY_HIGH, GameConstants.QUALITY_PERFECT,
		GameConstants.QUALITY_PERFECT_ODDS] == [85, 115, 120, 100])
	var letters: Array = GameConstants.QUALITY_FIELDS.map(func(pair): return pair[0])
	var fields: Array = GameConstants.QUALITY_FIELDS.map(func(pair): return pair[1])
	check("the five stats roll, one letter each",
		fields == ["damage", "armor_value", "bonus_max_hp", "bonus_max_mana", "bonus_damage_percent"]
		and letters == ["d", "a", "h", "m", "p"], GameConstants.QUALITY_FIELDS)
	var consts: Dictionary = _load_gamedata().get("constants", {})
	check("  and gamedata.json says the same to the server (re-run the exporter if not)",
		int(consts.get("quality_low", -1)) == GameConstants.QUALITY_LOW
		and int(consts.get("quality_high", -1)) == GameConstants.QUALITY_HIGH
		and int(consts.get("quality_perfect", -1)) == GameConstants.QUALITY_PERFECT
		and int(consts.get("quality_perfect_odds", -1)) == GameConstants.QUALITY_PERFECT_ODDS
		and str(consts.get("quality_fields", [])) == str(GameConstants.QUALITY_FIELDS),
		consts.get("quality_fields", "missing"))
	var exporter: String = FileAccess.get_file_as_string("res://src/tools/exportgamedata.gd")
	var unwritten: Array = ["quality_low", "quality_high", "quality_perfect", "quality_perfect_odds",
		"quality_fields"].filter(func(key): return not exporter.contains("\"%s\":" % key))
	check("  because the exporter writes all five", unwritten.is_empty(), unwritten)

	# THE SAME TABLE test_quality.py holds. Change the rounding on one side and
	# both suites go red, which is the point: a point of max health apart is a
	# clamp on every save.
	var shared: Array = [[20, 107, 21], [20, 115, 23], [20, 85, 17], [10, 85, 9], [10, 115, 12],
		[1, 85, 1], [1, 120, 1], [3, 120, 4], [3, 115, 3], [6, 96, 6], [100, 87, 87], [0, 120, 0]]
	var off: Array = []
	for row in shared:
		if ItemRegistry.scale_stat(int(row[0]), int(row[1])) != int(row[2]):
			off.append([row[0], row[1], ItemRegistry.scale_stat(int(row[0]), int(row[1]))])
	check("scale_stat matches the server's table, halves up", off.is_empty(), off)

	# ---- reading a roll ----------------------------------------------------------
	var rolled_id: String = "qtest_amulet~a104h96m110p88"
	var rolled: ItemData = ItemRegistry.get_item(rolled_id)
	check("a rolled id is an item", rolled != null and ItemRegistry.has_item(rolled_id))
	if rolled == null:
		for item in [amulet, sword, potion]:
			ItemRegistry._items.erase(item.item_id)
		return
	check("  with each stat at its percent of the .tres",
		[rolled.armor_value, rolled.bonus_max_hp, rolled.bonus_max_mana, rolled.bonus_damage_percent]
		== [ItemRegistry.scale_stat(2, 104), ItemRegistry.scale_stat(10, 96),
			ItemRegistry.scale_stat(12, 110), ItemRegistry.scale_stat(1, 88)],
		[rolled.armor_value, rolled.bonus_max_hp, rolled.bonus_max_mana, rolled.bonus_damage_percent])
	check("  its own id, and what it is a roll of",
		rolled.item_id == rolled_id and rolled.base_id == "qtest_amulet" and rolled.catalogue_id() == "qtest_amulet"
		and rolled.is_rolled() and not rolled.is_perfect()
		and rolled.rolls == {"armor_value": 104, "bonus_max_hp": 96, "bonus_max_mana": 110, "bonus_damage_percent": 88},
		rolled.rolls)
	check("  the .tres's price, tier, slot, level, name and picture",
		rolled.value == amulet.value and rolled.tier == amulet.tier and rolled.equip_slot == amulet.equip_slot
		and rolled.required_level == amulet.required_level and rolled.display_name == amulet.display_name
		and rolled.icon == amulet.icon and not rolled.stackable)
	check("  and its quality is the rolls averaged", rolled.quality_percent() == 100
		and ItemRegistry.get_item("qtest_amulet~a110h110m110p110").quality_percent() == 110)
	check("the same id is the same object every time it is asked for",
		ItemRegistry.get_item(rolled_id) == rolled)
	check("and the .tres itself is untouched",
		amulet.bonus_max_hp == 10 and amulet.item_id == "qtest_amulet" and not amulet.is_rolled()
		and ItemRegistry.get_item("qtest_amulet") == amulet and amulet.catalogue_id() == "qtest_amulet")

	var perfect: ItemData = ItemRegistry.get_item("qtest_amulet~a120h120m120p120")
	check("a Perfect roll is every stat at 120, and says so in its name",
		perfect != null and perfect.is_perfect() and perfect.display_name == "Perfect Test Amulet"
		and perfect.bonus_max_hp == 12 and perfect.bonus_max_mana == 14 and perfect.quality_percent() == 120,
		perfect.display_name if perfect != null else "null")

	var malformed: Array = [
		"qtest_sword~", "qtest_sword~d", "qtest_sword~d999", "qtest_sword~d84", "qtest_sword~d116",
		"qtest_sword~d119", "qtest_sword~d084", "qtest_sword~d0100", "qtest_sword~D100", "qtest_sword~d100x",
		"qtest_sword~a100", "qtest_sword~d100d100", "qtest_amulet~a100h100m100",
		"qtest_amulet~h100a100m100p100", "qtest_amulet~a120h120m120p115",
		"qtest_nothing~d100", "~d100", "qtest_sword~d100~d100", "qtest_potion~d100",
	]
	var accepted: Array = malformed.filter(func(id): return ItemRegistry.has_item(id) or not ItemRegistry.split_roll(id).is_empty())
	check("everything that only looks like a roll is not an item (%d spellings, the server's list)" % malformed.size(),
		accepted.is_empty(), accepted)
	check("a plain id is the catalogue piece, unrolled",
		ItemRegistry.split_roll("qtest_sword") == {"base": "qtest_sword", "rolls": {}, "resist": {}}
		and not sword.is_rolled() and sword.quality_percent() == 100)
	check("nothing on a potion rolls", ItemRegistry.rolled_fields(potion).is_empty()
		and ItemRegistry.rolled_fields(amulet).size() == 4 and ItemRegistry.rolled_fields(sword).size() == 1)

	# ---- wearing one: the rolled number is the one the character gets --------
	var body: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	body._set_stat_curve()
	body.equipped = {}
	body.level = 10
	var bare_hp: int = body.max_hp
	body.hp = bare_hp
	check("a Perfect amulet can be put on", body.equip(perfect.item_id))
	check("  and raises max health by its rolled 12, not the .tres's 10",
		body.max_hp == bare_hp + 12 and body.equipped_bonus("bonus_max_hp") == 12, [body.max_hp, bare_hp])
	body.equip("qtest_amulet~a85h85m85p85")
	check("an 85% one raises it by 9 (8.5, halves up)", body.max_hp == bare_hp + 9, body.max_hp - bare_hp)
	body.free()

	# ---- the tooltip ---------------------------------------------------------
	var sword_roll: ItemData = ItemRegistry.get_item("qtest_sword~d107")
	var lines: String = ItemTooltip._requirement_lines(sword_roll)
	check("the tooltip gives a rolled stat its roll: \"21 Damage (107%)\"",
		lines.contains("21 Damage (107%)"), lines)
	check("  and a store piece no roll at all", not ItemTooltip._requirement_lines(sword).contains("("),
		ItemTooltip._requirement_lines(sword))
	check("the rarity line says how good the roll is",
		ItemTooltip.rarity_text(sword_roll) == "Common  ·  Quality 107%"
		and ItemTooltip.rarity_text(sword) == "Common", ItemTooltip.rarity_text(sword_roll))
	var tip: Control = (load("res://scene/ui/inventory/itemtooltip.tscn") as PackedScene).instantiate()
	add_child(tip)
	await get_tree().process_frame
	tip.show_for_stack(ItemStack.new(perfect, 1), null)
	check("a Perfect piece's name is gold in the tooltip",
		tip.name_label.text == "Perfect Test Amulet"
		and tip.name_label.get_theme_color("font_color") == GameConstants.QUALITY_PERFECT_COLOUR,
		tip.name_label.text)
	tip.queue_free()

	# ---- its slot, and its bag on the ground ----------------------------------
	var slot: InventorySlot = (load("res://scene/ui/inventory/inventoryslot.tscn") as PackedScene).instantiate()
	add_child(slot)
	await get_tree().process_frame
	var frame: Panel = slot.get_node_or_null("rarityframe")
	slot.set_stack(ItemStack.new(ItemRegistry.get_item("qtest_sword~d120"), 1))
	var box: StyleBoxFlat = frame.get_theme_stylebox("panel") as StyleBoxFlat if frame != null else null
	check("a Perfect iron-tier piece frames its slot in gold, a pixel wider",
		frame != null and frame.visible and box.border_color == GameConstants.QUALITY_PERFECT_COLOUR
		and box.border_width_left == 3)
	slot.set_stack(ItemStack.new(sword_roll, 1))
	check("  an ordinary roll of the same piece has no frame, like the store's",
		frame != null and not frame.visible)
	slot.set_stack(ItemStack.new(rolled, 1))
	box = frame.get_theme_stylebox("panel") as StyleBoxFlat
	check("  and a rolled uncommon keeps its uncommon frame",
		frame.visible and box.border_color == GameConstants.rarity_colour(2) and box.border_width_left == 2)
	slot.queue_free()

	var World: Script = load("res://src/world/lootbag.gd")
	check("a bag holding a Perfect piece knows it",
		World.holds_perfect([{"item_id": "qtest_sword~d120", "quantity": 1}])
		and not World.holds_perfect([{"item_id": "qtest_sword~d115", "quantity": 1}, null]))
	var bag: Node2D = (load("res://scene/interactables/lootbag.tscn") as PackedScene).instantiate()
	add_child(bag)
	await get_tree().process_frame
	bag.set_contents([{"item_id": "qtest_sword~d115", "quantity": 1}])
	check("a bag with an ordinary iron roll does not glow", bag.glow_tier() == 0)
	bag.set_contents([{"item_id": "qtest_sword~d120", "quantity": 1}])
	var pool: Sprite2D = bag.get_node_or_null("rareglow/pool")
	check("a bag with a Perfect iron sword glows, and glows gold",
		pool != null and (bag.get_node("rareglow") as Node2D).visible
		and Color((pool.texture as GradientTexture2D).gradient.get_color(0), 1.0)
		== Color(GameConstants.QUALITY_PERFECT_COLOUR, 1.0))
	bag.queue_free()

	# ---- the shop and the trade window ----------------------------------------
	# BY PATH: neither script has a class_name.
	var Shop: Script = load("res://src/ui/shop/shopinventory.gd") as Script
	var Trade: Script = load("res://src/ui/trade/tradepanel.gd") as Script
	check("selling a Perfect piece asks twice, at any tier; an ordinary roll does not",
		Shop.asks_twice(ItemRegistry.get_item("qtest_sword~d120"))
		and not Shop.asks_twice(sword_roll))
	var bag_grid := InventoryContainer.new()
	bag_grid.is_carry = true
	add_child(bag_grid)
	bag_grid.load_save_array([{"item_id": "qtest_sword~d107", "quantity": 1}])
	var panel: Node = (load("res://scene/ui/shop/shopinventory.tscn") as PackedScene).instantiate()
	add_child(panel)
	panel.inventory_override = bag_grid
	panel.shop_id = "generalstore"
	panel.show_catalogue({"display_name": "Kingdom Supplies", "sell_multiplier": 0.05, "stock": [],
		"sell_prices": {"qtest_sword": 20}})
	panel.set_mode("sell")
	var row: Node = panel.stock_list.get_node_or_null("sell_0")
	var pays: Label = row.find_child("pays", true, false) if row != null else null
	check("the Sell list prices a roll as its .tres - the shop lists the catalogue id",
		pays != null and pays.text == "20 g", pays.text if pays != null else "no row")

	# ON THE SHELF, "?" - the shop rolls gear at the till (the owner, 5 Oct:
	# "item stats say ? and are revealed upon buying in shop only").
	check("gear on the shelf rolls when bought; a potion, or a piece already rolled, does not",
		ItemTooltip.rolls_when_bought(amulet) and ItemTooltip.rolls_when_bought(sword)
		and not ItemTooltip.rolls_when_bought(potion) and not ItemTooltip.rolls_when_bought(sword_roll))
	var shelf_lines: String = ItemTooltip._requirement_lines(amulet, true)
	check("its stats read \"?\" and say they roll when bought",
		shelf_lines.contains("? Armour") and shelf_lines.contains("+? Max Health")
		and shelf_lines.contains("+?% Damage Bonus") and shelf_lines.contains("rolled when you buy it")
		and not shelf_lines.contains("12"), shelf_lines)
	var shelf_tip: Control = (load("res://scene/ui/inventory/itemtooltip.tscn") as PackedScene).instantiate()
	add_child(shelf_tip)
	await get_tree().process_frame
	panel.show_catalogue({"display_name": "Kingdom Supplies", "sell_multiplier": 0.05,
		"stock": [{"item_id": "qtest_amulet", "display_name": "Test Amulet", "price": 1456, "tier": 2,
		"type_name": "ARMOR", "required_level": 5}], "sell_prices": {"qtest_sword": 20}})
	panel.set_mode("buy")
	var shelf_row: Control = null
	for child in panel.stock_list.get_children():
		for label in child.find_children("*", "Label", true, false):
			if (label as Label).text == "Test Amulet":
				shelf_row = child
	if shelf_row != null:
		shelf_row.mouse_entered.emit()
	check("hovering the shelf's row shows \"?\" in the tooltip, and nothing to compare",
		shelf_row != null and shelf_tip.visible and shelf_tip.description_label.text.contains("? Armour")
		and not (shelf_tip.stats_box != null and shelf_tip.stats_box.visible),
		shelf_tip.description_label.text if shelf_row != null else "no shelf row")
	panel.set_mode("sell")
	var owned: Node = panel.stock_list.get_node_or_null("sell_0")
	if owned != null:
		owned.mouse_entered.emit()
	check("  while a piece in your bag shows its own numbers in the Sell list",
		owned != null and shelf_tip.description_label.text.contains("21 Damage (107%)"),
		shelf_tip.description_label.text)
	shelf_tip.queue_free()
	check("buying one says what it rolled", Shop.purchase_line(sword_roll, "qtest_sword~d107", 400)
		== "Bought Test Sword for %s - quality 107%%." % GameConstants.gold_text(400),
		Shop.purchase_line(sword_roll, "qtest_sword~d107", 400))
	check("  and a Perfect says so", Shop.purchase_line(ItemRegistry.get_item("qtest_sword~d120"),
		"qtest_sword~d120", 400).ends_with("a Perfect roll, every stat at 120%!"))
	check("  and a potion is bought as before", Shop.purchase_line(potion, "qtest_potion", 200)
		== "Bought qtest_potion for %s." % GameConstants.gold_text(200))
	panel.queue_free()
	bag_grid.queue_free()
	check("the trade window says a roll's quality on its row",
		Trade.quality_hint(sword_roll) == "Quality 107%  ·  " and Trade.quality_hint(sword) == "")
	check("  and its tooltip says what the roll does",
		Trade.item_tooltip("qtest_sword~d107").contains("21 Damage (107%)"),
		Trade.item_tooltip("qtest_sword~d107"))

	# ---- the owner's item menu asks for a roll --------------------------------
	const Spawner := preload("res://src/ui/owner/itemspawner.gd")
	var was_owner: bool = Api.is_owner
	Api.is_owner = true
	var menu: Control = (load("res://scene/ui/owner/itemspawner.tscn") as PackedScene).instantiate() as Control
	add_child(menu)
	await get_tree().process_frame
	var asked: Array = []
	var equipped_ids: Array = []
	menu.post_request = func(path: String, body_: Dictionary) -> Dictionary:
		asked.append([path, body_])
		await get_tree().process_frame
		return {"ok": true, "data": {"granted_item_id": "qtest_sword~d107",
			"inventory": [{"item_id": "qtest_sword~d107", "quantity": 1}], "carry_positions": [0]}}
	menu.adopt_bag = func(_slot: int, _cells: Array) -> void:
		pass
	menu.equip_request = func(id: String, _cell: int) -> bool:
		equipped_ids.append(id)
		return true
	check("the menu offers a plain 100% piece, a drop's roll, and a Perfect",
		menu.quality_pick.item_count == 3 and menu.chosen_quality() == "plain"
		and Spawner.QUALITIES.map(func(q): return q[0]) == ["plain", "roll", "perfect"])
	menu.quality_pick.select(1)
	menu.wear_toggle.button_pressed = false
	await menu.spawn("qtest_sword")
	check("  and asks the server for the one picked",
		asked.size() == 1 and asked[0][1].get("quality") == "roll" and asked[0][1].get("item_id") == "qtest_sword",
		asked)
	check("  and names what arrived, with its quality",
		menu.status.text == "Added Test Sword to your bag, quality 107%.", menu.status.text)
	menu.wear_toggle.button_pressed = true
	await menu.spawn("qtest_sword")
	check("  and puts on the piece that arrived, by its rolled id", equipped_ids == ["qtest_sword~d107"],
		equipped_ids)
	menu.queue_free()
	Api.is_owner = was_owner

	for item in [amulet, sword, potion]:
		ItemRegistry._items.erase(item.item_id)
	for id in ItemRegistry._rolled.keys():
		if str(id).begins_with("qtest_"):
			ItemRegistry._rolled.erase(id)
	print("  a roll is read from the id, scaled like the server, and shown wherever the piece is")


func _test_other_players_are_drawn() -> void:
	section("OTHER PLAYERS - drawn from what the presence server says, and only that")

	# ---- the pieces are there --------------------------------------------------
	check("Presence is an autoload, so it lives across every area change",
		get_node_or_null("/root/Presence") != null)
	if require_script("res://src/characters/remoteplayer.gd", "a remote player") == null:
		return
	# DRIVEN BY HAND. Its own loop would find nobody logged in and switch it off
	# between two steps of this test.
	Presence.set_process(false)
	Presence.stop()
	var world := Node2D.new()
	world.name = "presenceworld"
	# NOT AT THE ORIGIN: the wire carries world positions, and a body is placed
	# inside the world node.
	world.position = Vector2(100, 50)
	add_child(world)
	Presence.world_override = world
	Presence._world = world
	# THE PLAYBACK'S CLOCK BY HAND (remoteplayer.gd, PLAYED BACK, 0.19.0): these
	# moves carry no clock of their own, as a server from before sends them, so
	# each is timed by when it arrives, and the body is drawn PLAYBACK_DELAY
	# behind.
	var Remote := preload("res://src/characters/remoteplayer.gd")
	Remote.clock_override = 100.0
	var cleanup := func() -> void:
		Presence.stop()
		Presence.world_override = null
		Presence._world = null
		Presence.request_ticket = Callable(Presence, "_post_ticket")
		Presence._failures = 0
		Presence.set_process(true)
		Remote.clock_override = -1.0

	# ---- who joins ---------------------------------------------------------------
	Presence.handle_message({"t": "welcome", "id": 7})
	Presence.handle_message({"t": "join", "p": [
		{"id": 7, "name": "me", "cls": "warrior", "x": 0.0, "y": 0.0, "m": "idledown", "fx": [], "pet": ""},
		{"id": 11, "name": "Tunacan", "cls": "tank", "role": "owner", "hue": 200, "guild": "ELUSION",
			"lvl": 20, "x": 300.0, "y": 250.0, "m": "walkleft", "fx": ["firering"], "pet": "petfiresprite"},
		{"id": 12, "name": "Mira", "cls": "healer", "role": "mod", "hue": null, "guild": "", "lvl": 3,
			"x": 140.0, "y": 90.0, "m": "attackdown", "fx": [], "pet": ""},
		{"id": 13, "name": "Bram", "cls": "warrior", "role": "player", "hue": 40, "guild": "", "lvl": 9,
			"x": 400.0, "y": 90.0, "m": "attackdown", "fx": [], "pet": ""},
	]})
	await get_tree().process_frame
	var drawn: Array = Presence.remotes().keys()
	drawn.sort()
	check("everybody the server names is drawn - and never yourself", drawn == [11, 12, 13], drawn)
	var tank: Node2D = Presence.remotes().get(11)
	var healer: Node2D = Presence.remotes().get(12)
	var warrior: Node2D = Presence.remotes().get(13)
	if tank == null or healer == null or warrior == null:
		world.queue_free()
		cleanup.call()
		return
	check("  standing in the world the player stands in", tank.get_parent() == world and healer.get_parent() == world)
	check("  and not in the player group - everything asking for 'the player' still finds you",
		not tank.is_in_group("player") and not healer.is_in_group("player"))
	check("  named for who they are", str(tank.name) == "remote_11", tank.name)
	check("  where the server said, in the world's own space, at once - no gliding in from the corner",
		tank.position == Vector2(200, 200), tank.position)

	# ---- the body: the class's own art ------------------------------------------
	var real: Node = (load("res://scene/characters/tank.tscn") as PackedScene).instantiate()
	var real_body: AnimatedSprite2D = real.get_node("animatedsprite2d") as AnimatedSprite2D
	var body: AnimatedSprite2D = tank.get_node_or_null("animatedsprite2d") as AnimatedSprite2D
	check("the body is the class scene's own sprite - frames, offset and scale",
		body != null and body.sprite_frames == real_body.sprite_frames and body.offset == real_body.offset
		and body.scale == real_body.scale and body.position == real_body.position,
		[body, real_body.offset, real_body.scale])
	real.free()
	check("  playing what they are doing, facing the way they face",
		body != null and str(body.animation) == "walkleft" and body.is_playing(),
		str(body.animation) if body != null else "no body")
	var fire: CanvasItem = tank.get_node_or_null("firering") as CanvasItem
	var ring: CanvasItem = tank.get_node_or_null("ring") as CanvasItem
	check("  a tank's lit aura is drawn, and the unlit one is not",
		fire != null and fire.visible and ring != null and not ring.visible,
		[fire != null and fire.visible, ring != null and ring.visible])
	var remote_burn: AuraBurn = tank.get_node_or_null(^"auraburn") as AuraBurn
	check("  and it burns the ground here too, lit with it, under the body (auraburn.gd, 0.34.0)",
		remote_burn != null and remote_burn.fire == fire and remote_burn.lit and tank.get_child(0) == remote_burn, remote_burn)
	var healer_body: AnimatedSprite2D = healer.get_node_or_null("animatedsprite2d") as AnimatedSprite2D
	Remote.clock_override = 100.1
	Presence.handle_message({"t": "moves", "p": [[12, 140.0, 90.0, "attackleft", [], ""]]})
	Remote.clock_override = 100.1 + Remote.PLAYBACK_DELAY + 0.01
	healer._process(1.0 / 60.0)
	check("  a class with no swing of its own stands facing the same way rather than vanish",
		healer_body != null and str(healer_body.animation) == "idleleft" and healer_body.is_playing(),
		str(healer_body.animation) if healer_body != null else "no body")
	var swing: AnimatedSprite2D = warrior.get_node_or_null("animatedsprite2d") as AnimatedSprite2D
	if swing != null:
		swing.stop()
		swing.animation_finished.emit()
	check("  an attack keeps swinging until they stop - the game says 'attacking' once",
		swing != null and str(swing.animation) == "attackdown" and swing.is_playing(),
		[str(swing.animation) if swing != null else "no body", swing != null and swing.is_playing()])

	# ---- the nameplate -------------------------------------------------------------
	var plate: Label = tank.plate()
	check("the plate reads the guild over the name, as yours does",
		plate != null and plate.text == "%s\nTunacan" % Api.guild_tag_text("ELUSION") and plate.visible,
		plate.text if plate != null else "no plate")
	check("  in the colour they chose", plate != null
		and plate.get_theme_color("font_color") == NameTag.colour(200))
	var crown: CanvasItem = tank.get_node_or_null("nameplatecrown") as CanvasItem
	check("  and the owner wears the crown", crown != null and crown.visible)
	var healer_plate: Label = healer.plate()
	var badge: Label = healer.get_node_or_null("nameplatebadge") as Label
	check("a moderator's plate carries the badge, and no guild line when there is no guild",
		healer_plate != null and healer_plate.text == "Mira" and badge != null and badge.visible
		and badge.text == NameTag.badge("mod") and badge.text != "",
		[healer_plate.text if healer_plate != null else "no plate", badge.text if badge != null else "no badge"])
	check("  a name never coloured is drawn in the default colour",
		healer_plate != null and healer_plate.get_theme_color("font_color") == NameTag.colour(null))
	var healer_crown: CanvasItem = healer.get_node_or_null("nameplatecrown") as CanvasItem
	check("  and only the owner has a crown", healer_crown == null or not healer_crown.visible)

	# ---- the pet --------------------------------------------------------------------
	var pet: AnimatedSprite2D = tank.pet_sprite()
	var pet_scene: PackedScene = PetController.pet_scene_for("petfiresprite")
	var real_pet: Node = pet_scene.instantiate() if pet_scene != null else null
	var real_pet_frames: SpriteFrames = null
	if real_pet != null:
		var real_pet_body: AnimatedSprite2D = real_pet.get_node_or_null("animatedsprite2d") as AnimatedSprite2D
		real_pet_frames = real_pet_body.sprite_frames if real_pet_body != null else null
		real_pet.free()
	check("their pet is out, drawn from the pet's own scene",
		pet != null and real_pet_frames != null and pet.sprite_frames == real_pet_frames,
		[pet, real_pet_frames])
	check("  beside them in the world, so it sorts by where it stands",
		pet != null and pet.get_parent() == world, pet.get_parent() if pet != null else null)
	check("  and nobody without one has one", healer.pet_sprite() == null)

	# ---- moving: played back, a fifth of a second behind (0.19.0) --------------------
	# The tank joined at 100.0 at (200, 200); this step, 0.2 later, is 10 along.
	Remote.clock_override = 100.2
	Presence.handle_message({"t": "moves", "p": [[11, 310.0, 250.0, "walkright", [], "petfiresprite"]]})
	Remote.clock_override = 100.25
	tank._process(1.0 / 60.0)
	check("a step is played back at the pace it was walked: a quarter of the way a quarter of the time in",
		tank.target() == Vector2(210, 200) and is_equal_approx(tank.position.x, 202.5)
		and is_equal_approx(tank.position.y, 200.0), [tank.target(), tank.position])
	check("  still doing what they were doing until the playback reaches the step that says otherwise",
		body != null and str(body.animation) == "walkleft" and fire != null and fire.visible,
		str(body.animation) if body != null else "no body")
	Remote.clock_override = 100.2 + Remote.PLAYBACK_DELAY
	tank._process(1.0 / 60.0)
	check("  turning plays the new way round when it does", body != null and str(body.animation) == "walkright"
		and tank.position == Vector2(210, 200), [str(body.animation) if body != null else "no body", tank.position])
	check("  and the aura goes out when they put it out", fire != null and not fire.visible)
	Remote.clock_override = 100.5
	Presence.handle_message({"t": "moves", "p": [[11, 1100.0, 1050.0, "idledown", [], "petfiresprite"]]})
	Remote.clock_override = 100.55
	tank._process(1.0 / 60.0)
	var before_jump: Vector2 = tank.position
	Remote.clock_override = 100.5 + Remote.PLAYBACK_DELAY
	tank._process(1.0 / 60.0)
	check("a jump too far to be a walk - a door, a teleport - is made when the playback reaches it, not glided",
		before_jump == Vector2(210, 200) and tank.position == Vector2(1000, 1000), [before_jump, tank.position])
	Presence.handle_message({"t": "moves", "p": [[7, 5.0, 5.0, "walkup", [], ""], [99, 5.0, 5.0, "walkup", [], ""]]})
	check("a move for yourself or for somebody never introduced draws nothing",
		Presence.remotes().size() == 3 and not Presence.remotes().has(99) and not Presence.remotes().has(7),
		Presence.remotes().keys())

	# ---- leaving --------------------------------------------------------------------
	Presence.handle_message({"t": "leave", "ids": [11, 12]})
	await get_tree().process_frame
	check("somebody leaving takes their body off the screen",
		not is_instance_valid(tank) and not is_instance_valid(healer) and Presence.remotes().keys() == [13],
		Presence.remotes().keys())
	check("  and their pet with them", pet == null or not is_instance_valid(pet))
	var world2 := Node2D.new()
	world2.name = "presenceworld2"
	add_child(world2)
	Presence._phase = "open"
	Presence._sync_pending = false
	Presence.world_override = world2
	Presence._follow_world(world2)
	await get_tree().process_frame
	check("a new world is a new screen: everybody from the old one is forgotten",
		Presence.remotes().is_empty() and not is_instance_valid(warrior), Presence.remotes().keys())
	check("  and the server is asked who is here", Presence._sync_pending)
	Presence._phase = "off"
	Presence._sync_pending = false
	Presence.world_override = world
	Presence._world = world

	# ---- what this game says about its own player -------------------------------------
	var stand_in_script := GDScript.new()
	stand_in_script.source_code = "extends Node2D\nvar active_pet_id: String = \"petmage\"\nfunc get_idle_animation() -> String:\n\treturn \"idleleft\"\n"
	stand_in_script.reload()
	var stand_in: Node2D = stand_in_script.new()
	stand_in.position = Vector2(23.456, 28.91)
	var own_body := AnimatedSprite2D.new()
	own_body.name = "animatedsprite2d"
	var warrior_scene: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	own_body.sprite_frames = (warrior_scene.get_node("animatedsprite2d") as AnimatedSprite2D).sprite_frames
	warrior_scene.free()
	stand_in.add_child(own_body)
	var own_fire := Sprite2D.new()
	own_fire.name = "firering"
	stand_in.add_child(own_fire)
	var own_ring := Sprite2D.new()
	own_ring.name = "ring"
	own_ring.visible = false
	stand_in.add_child(own_ring)
	world.add_child(stand_in)
	own_body.play("walkup")
	var said: Dictionary = Presence.state_for(stand_in)
	check("the game says where it stands, in world space, to a tenth of a pixel",
		said.get("t") == "s" and is_equal_approx(float(said.get("x")), 123.5)
		and is_equal_approx(float(said.get("y")), 78.9), said)
	check("  which area it is in", said.get("a") == AreaRegistry.current_area_id(), said.get("a"))
	check("  what its body is playing", said.get("m") == "walkup", said.get("m"))
	check("  which aura is lit", said.get("fx") == ["firering"], said.get("fx"))
	check("  and which pet is out", said.get("pet") == "petmage", said.get("pet"))
	check("  and nothing about who it is - the server says that",
		not said.has("name") and not said.has("role") and not said.has("hue") and not said.has("cls"), said.keys())
	check("standing still says the same thing twice, so nothing is sent", Presence.state_for(stand_in) == said)
	var odd := SpriteFrames.new()
	odd.add_animation(&"projectile")
	own_body.sprite_frames = odd
	own_body.animation = &"projectile"
	check("an animation the server would refuse is sent as the idle one instead",
		Presence.state_for(stand_in).get("m") == "idleleft", Presence.state_for(stand_in).get("m"))

	# ---- when it cannot connect ----------------------------------------------------------
	var asked: Array = []
	Presence._failures = 0
	Presence.request_ticket = func(path: String, request: Dictionary) -> Dictionary:
		asked.append([path, request])
		return {"ok": false, "error": "no"}
	await Presence._begin()
	check("a refused ticket waits and tries again later, and says nothing",
		Presence.phase() == "waiting" and is_equal_approx(Presence._retry_clock, 2.0),
		[Presence.phase(), Presence._retry_clock])
	check("  the ticket was asked for this character, at the presence route",
		asked.size() == 1 and asked[0][0] == "/api/presence/ticket"
		and asked[0][1].get("slot") == CharacterData.active_character_index, asked)
	await Presence._begin()
	check("  and waits longer each time it fails", is_equal_approx(Presence._retry_clock, 5.0), Presence._retry_clock)
	# A SERVER THAT TAKES THE KNOCK AND NEVER SPEAKS (0.56.1): a port that
	# listens and is never read, so the handshake waits on every system alike.
	# Before, this was port 9 with nobody on it, and only Linux refuses that
	# at once - Windows knocks again for two seconds, a headless run's 300
	# frames were over sooner, and the check passed or failed by the PC.
	var silent := TCPServer.new()
	silent.listen(0, "127.0.0.1")
	var silent_url: String = "ws://127.0.0.1:%d/ws/presence" % silent.get_local_port()
	Presence._failures = 0
	Presence.request_ticket = func(_path: String, _request: Dictionary) -> Dictionary:
		return {"ok": true, "data": {"ticket": "t", "socket_url": silent_url}}
	await Presence._begin()
	var connecting: String = Presence.phase()
	var knocked: float = 0.0
	var gave_up_at: float = -1.0
	while knocked < Presence.CONNECT_SECONDS + 1.0:
		Presence._pump(1.0 / 60.0, stand_in)
		knocked += 1.0 / 60.0
		if Presence.phase() != "connecting":
			gave_up_at = knocked
			break
		if roundi(knocked * 60.0) % 30 == 0:
			await get_tree().process_frame
	check("a socket that never answers is given up on, and tried again later",
		silent.is_listening() and connecting == "connecting" and Presence.phase() == "waiting"
		and Presence.remotes().is_empty() and is_equal_approx(Presence._retry_clock, 2.0),
		[connecting, Presence.phase(), Presence._retry_clock])
	check("  after CONNECT_SECONDS of knocking, not before",
		gave_up_at >= Presence.CONNECT_SECONDS - 0.001 and gave_up_at < Presence.CONNECT_SECONDS + 0.05, gave_up_at)
	silent.stop()
	# A port nobody listens on: refused at once, or given up on in time.
	Presence._failures = 0
	Presence.request_ticket = func(_path: String, _request: Dictionary) -> Dictionary:
		return {"ok": true, "data": {"ticket": "t", "socket_url": "ws://127.0.0.1:9/ws/presence"}}
	await Presence._begin()
	knocked = 0.0
	while Presence.phase() == "connecting" and knocked < Presence.CONNECT_SECONDS + 1.0:
		Presence._pump(1.0 / 60.0, stand_in)
		knocked += 1.0 / 60.0
		if roundi(knocked * 60.0) % 30 == 0:
			await get_tree().process_frame
	check("  and so is a port nobody is on, refused or not", Presence.phase() == "waiting", Presence.phase())

	# ---- with nobody to draw for --------------------------------------------------------
	Presence.handle_message({"t": "welcome", "id": 7})
	Presence.handle_message({"t": "join", "p": [{"id": 21, "name": "Late", "cls": "mage", "x": 0.0, "y": 0.0,
		"m": "idledown", "fx": [], "pet": ""}]})
	Presence.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var logged_in: bool = Api.is_logged_in()
	var in_world: bool = get_tree().get_first_node_in_group("player") != null
	check("with nobody logged in and playing, it switches off and draws nobody",
		logged_in and in_world or (Presence.phase() == "off" and Presence.remotes().is_empty()),
		[Presence.phase(), Presence.remotes().keys(), logged_in, in_world])

	world.queue_free()
	world2.queue_free()
	cleanup.call()


# PLAYED BACK, NOT CHASED (0.19.0). The owner, running past the first other
# player he played with: "i noticed some lag wobble". Their picture eased
# toward each step as it came, and steps come unevenly. Now it is played back
# on their clock, PLAYBACK_DELAY behind (remoteplayer.gd).
func _test_other_players_move_evenly() -> void:
	section("OTHER PLAYERS - played back evenly, on their own clock, however the steps arrive")
	var Remote := preload("res://src/characters/remoteplayer.gd")
	var holder := Node2D.new()
	add_child(holder)
	var them: Node2D = Remote.new()
	them.user_id = 601
	holder.add_child(them)
	them.set_identity({"id": 601, "name": "Runner", "cls": "warrior", "lvl": 3, "v": 2})
	them.set_process(false)
	Remote.clock_override = 50.0
	them.set_motion("walkright", [], "")
	them.place(Vector2.ZERO, 1000)
	# Six steps a tenth apart on their clock, 10 along each - arriving as a
	# network delivers them: a little late, later, two together, on time.
	var arrives: Array = [50.13, 50.21, 50.30, 50.48, 50.50, 50.65]
	var next_step: int = 0
	var xs: Array = []
	for i in 13:
		var now: float = 50.2 + 0.05 * i
		while next_step < arrives.size() and float(arrives[next_step]) <= now:
			Remote.clock_override = float(arrives[next_step])
			them.push_step(Vector2(10.0 * (next_step + 1), 0.0), "walkright", [], "", 1000 + 100 * (next_step + 1))
			next_step += 1
		Remote.clock_override = now
		them._process(1.0 / 60.0)
		xs.append(them.position.x)
	var steps: Array = []
	for i in range(1, xs.size()):
		steps.append(snappedf(float(xs[i]) - float(xs[i - 1]), 0.001))
	var even: bool = true
	for step in steps:
		even = even and absf(float(step) - 5.0) < 0.01
	check("steps that arrived unevenly are walked evenly: the same distance every twentieth of a second",
		even and is_equal_approx(float(xs[0]), 0.0) and is_equal_approx(float(xs.back()), 60.0), [xs, steps])
	check("  a fifth of a second behind their newest step", is_equal_approx(Remote.PLAYBACK_DELAY, 0.2)
		and them.target() == Vector2(60, 0))
	check("  and how fast they go is known, for a boss to lead", them.velocity.x > 95.0 and them.velocity.x < 101.0,
		them.velocity)
	Remote.clock_override = 51.5
	them._process(1.0 / 60.0)
	check("past their last step it holds there: they stopped", them.position == Vector2(60, 0), them.position)
	# A second and a half standing still, then off again: their game sends
	# nothing while they stand.
	Remote.clock_override = 52.05
	them.push_step(Vector2(70, 0), "walkright", [], "", 3000)
	var at_start: Array = []
	for now in [52.1, 52.15, 52.2]:
		Remote.clock_override = now
		them._process(1.0 / 60.0)
		at_start.append(them.position.x)
	check("setting off after a stand starts from where they stood, a step before - not a crawl across the pause",
		is_equal_approx(float(at_start[0]), 60.0) and is_equal_approx(float(at_start[1]), 65.0)
		and is_equal_approx(float(at_start[2]), 70.0), at_start)
	Remote.clock_override = 53.0
	them.push_step(Vector2(500, 0), "walkright", [], "", 50)
	them._process(1.0 / 60.0)
	check("their clock starting again (their game restarted) starts the playback again, where they are",
		them.position == Vector2(500, 0), them.position)
	Remote.clock_override = 53.1
	them.push_step(Vector2(510, 0), "walkright", [], "", 150)
	Remote.clock_override = 53.25
	them._process(1.0 / 60.0)
	check("  and plays on from there", them.position.x > 500.0 and them.position.x < 510.0, them.position)

	# THE ROAD GETS QUICKER: steps that took a tenth longer start arriving on
	# time. The link moves to it a little at a time - no skip.
	var quick: Node2D = Remote.new()
	quick.user_id = 603
	holder.add_child(quick)
	quick.set_identity({"id": 603, "name": "Quick", "cls": "tank", "lvl": 3, "v": 2})
	quick.set_process(false)
	Remote.clock_override = 80.1
	quick.place(Vector2.ZERO, 1000)
	var quick_xs: Array = []
	var k_next: int = 1
	for i in 40:
		var now: float = 80.4 + 0.05 * i
		while k_next <= 40:
			var lag: float = 0.1 if k_next <= 4 else 0.0
			var lands: float = 80.0 + 0.1 * k_next + lag
			if lands > now:
				break
			Remote.clock_override = lands
			quick.push_step(Vector2(10.0 * k_next, 0.0), "walkright", [], "", 1000 + 100 * k_next)
			k_next += 1
		Remote.clock_override = now
		quick._process(1.0 / 60.0)
		quick_xs.append(quick.position.x)
	var biggest: float = 0.0
	var least: float = INF
	for i in range(1, quick_xs.size()):
		biggest = maxf(biggest, float(quick_xs[i]) - float(quick_xs[i - 1]))
		least = minf(least, float(quick_xs[i]) - float(quick_xs[i - 1]))
	check("a road that gets quicker is caught up with a little faster for a moment, never a skip",
		biggest <= 5.0 * (1.0 + Remote.CLOCK_SLEW) + 0.01 and least >= 4.99 and biggest > 5.01, [least, biggest])
	# THE QUICKEST ROAD WANDERS: the step that set the link leaves the window
	# and the rest took a few milliseconds longer. Inside the deadband the pace
	# does not move at all.
	var steady: Node2D = Remote.new()
	steady.user_id = 605
	holder.add_child(steady)
	steady.set_identity({"id": 605, "name": "Steady", "cls": "warrior", "lvl": 3, "v": 2})
	steady.set_process(false)
	Remote.clock_override = 90.0
	steady.place(Vector2.ZERO, 1000)
	var steady_xs: Array = []
	var s_next: int = 1
	var steps_total: int = int((Remote.CLOCK_WINDOW + 2.0) / 0.1)
	for i in int((Remote.CLOCK_WINDOW + 1.0) / 0.05):
		var now: float = 90.3 + 0.05 * i
		while s_next <= steps_total:
			var lands: float = 90.0 + 0.1 * s_next + (0.0 if s_next <= 3 else Remote.CLOCK_DEADBAND * 0.6)
			if lands > now:
				break
			Remote.clock_override = lands
			steady.push_step(Vector2(10.0 * s_next, 0.0), "walkright", [], "", 1000 + 100 * s_next)
			s_next += 1
		Remote.clock_override = now
		steady._process(1.0 / 60.0)
		steady_xs.append(steady.position.x)
	var steady_even: bool = true
	for i in range(1, steady_xs.size()):
		steady_even = steady_even and absf(float(steady_xs[i]) - float(steady_xs[i - 1]) - 5.0) < 0.01
	check("a quickest road that wanders by a few milliseconds leaves the pace exactly as it was",
		steady_even and steady_xs.size() > int(Remote.CLOCK_WINDOW / 0.05), steady_xs.slice(0, 8))
	# A join from a player who has stood still for a minute carries a clock a
	# minute old.
	var stood: Node2D = Remote.new()
	stood.user_id = 604
	holder.add_child(stood)
	stood.set_identity({"id": 604, "name": "Stood", "cls": "mage", "lvl": 3, "v": 2})
	stood.set_process(false)
	Remote.clock_override = 70.0
	stood.place(Vector2.ZERO, 1000)
	Remote.clock_override = 70.05
	stood.push_step(Vector2(10, 0), "walkdown", [], "", 61000)
	Remote.clock_override = 70.2
	stood._process(1.0 / 60.0)
	check("a join a minute old does not hold their picture a minute behind: the next step sets it right",
		is_equal_approx(stood.position.x, 5.0), stood.position)

	# A game from before 0.19.0 sends no clock: its steps are timed by arrival.
	var old_game: Node2D = Remote.new()
	old_game.user_id = 602
	holder.add_child(old_game)
	old_game.set_identity({"id": 602, "name": "Old", "cls": "mage", "lvl": 3, "v": 2})
	old_game.set_process(false)
	Remote.clock_override = 60.0
	old_game.place(Vector2.ZERO)
	for k in [1, 2, 3]:
		Remote.clock_override = 60.0 + 0.1 * k
		old_game.push_step(Vector2(10.0 * k, 0.0), "walkdown", [], "")
	Remote.clock_override = 60.35
	old_game._process(1.0 / 60.0)
	check("a game that sends no clock is played back by when its steps arrived",
		is_equal_approx(old_game.position.x, 15.0), old_game.position)
	Remote.clock_override = 60.4
	old_game.push_step(Vector2(1.0, 0.0), "walkdown", [], "", -1)
	old_game.push_step(Vector2(2.0, 0.0), "walkdown", [], "", -1)
	check("  and a step no newer than the last is not played twice", old_game.target() == Vector2(1, 0),
		old_game.target())
	Remote.clock_override = -1.0
	holder.free()
	print("  playback: even steps, the delay, a stop, a start, a restart, a game with no clock")


# OTHER PLAYERS' ATTACKS (0.19.0). The owner: "i could not see their attacks
# but they could see mine". The attacker's game sends a picture of each one and
# this game spawns it from the class's own scene, with `cosmetic` set
# (remoteattacks.gd): drawn exactly as theirs, touching nothing.
func _test_parties() -> void:
	section("PARTIES - a Party window, party chat, and your party and the monsters on the map (0.42.0)")
	# The owner: "we need to be able to start parties so we need a tab for
	# parties", then "Party tab + members", "Party chat", "Party on the map" and
	# "monsters on map also by element color". test_parties.py holds the server.
	var kept_name: String = Api.username
	Api.username = "pme"
	Party.forget()

	# ---- the state ----
	var before: int = Party.revision
	var changed: bool = Party.apply({"id": 7, "leader": "pme", "members": ["pme", "PBob", "pcat"]})
	check("the poll's party is kept: who is in it, who leads, and the revision moves",
		changed and Party.in_one() and Party.is_leader() and Party.is_member("pbob") and Party.is_member("PCAT")
		and not Party.is_member("stranger") and Party.revision == before + 1)
	check("  the same answer again changes nothing",
		not Party.apply({"id": 7, "leader": "pme", "members": ["pme", "PBob", "pcat"]}) and Party.revision == before + 1)
	Api.username = "somebodyelse"
	var other_login: bool = Party.in_one() or Party.is_member("pbob")
	Api.username = "pme"
	Party.apply({"id": 0, "leader": "", "members": []})
	check("  another login sees none of it, and no party is nobody",
		not other_login and not Party.in_one() and not Party.is_member("pbob"))

	# ---- the window ----
	var panel: PartyPanel = (load("res://scene/ui/party/partypanel.tscn") as PackedScene).instantiate() as PartyPanel
	add_child(panel)
	var sent: Array = []
	var answers: Array = [{"ok": true, "data": {"party": null, "invites": [{"from": "pamy", "at": 100}],
		"capacity": 4, "invite_seconds": 120}}]
	panel.fetch = func(_path: String) -> Dictionary: return answers[0]
	panel.send = func(path: String, body: Dictionary) -> Dictionary:
		sent.append([path, body])
		return answers[0]
	await panel.open()
	var invite_row: Node = panel.invites_box.get_node_or_null(^"invite_pamy")
	check("no party: it says how to start one, with the invitation waiting - Join and No",
		panel.visible and panel.summary_label.text.contains("no party") and invite_row != null
		and invite_row.get_child_count() == 3 and panel.invite_row.visible and not panel.leave_button.visible,
		panel.summary_label.text)
	var party_answer: Dictionary = {"ok": true, "data": {"capacity": 4, "invites": [], "party": {
		"id": 9, "leader": "pme", "size": 3, "capacity": 4, "members": [
			{"username": "pme", "leader": true, "online": true, "class_id": "warrior", "level": 12, "area": "field", "hp": 50, "max_hp": 100},
			{"username": "pbob", "leader": false, "online": true, "class_id": "mage", "level": 5, "area": "field", "hp": 30, "max_hp": 120},
			{"username": "pcat", "leader": false, "online": false, "class_id": "tank", "level": 9, "area": "town", "hp": 200, "max_hp": 200}]}}}
	answers[0] = party_answer
	await panel.load_party()
	var bob_row: Node = panel.list.get_node_or_null(^"member_pbob")
	var cat_row: Node = panel.list.get_node_or_null(^"member_pcat")
	var bob_buttons: Array = bob_row.find_children("*", "Button", true, false).map(func(b: Node) -> String: return (b as Button).text) if bob_row else []
	var bob_detail: String = (bob_row.find_child("detail", true, false) as Label).text if bob_row else ""
	var cat_detail: String = (cat_row.find_child("detail", true, false) as Label).text if cat_row else ""
	var bob_health: Control = bob_row.find_child("health", true, false) as Control if bob_row else null
	check("a party: each member's class, level and area - away for somebody not on - and the leader marked",
		panel.list.get_child_count() == 3 and bob_detail == "Lv 5 Mage - %s" % AreaRegistry.display_name("field")
		and cat_detail.ends_with("away") and panel.list.get_node(^"member_pme").find_child("leader", true, false) != null
		and panel.summary_label.text == "3 of 4 - led by pme", [bob_detail, cat_detail, panel.summary_label.text])
	check("  their health as a bar - from the save when they are not in sight",
		bob_health != null and is_equal_approx(float(bob_health.get("share")), 0.25), str(bob_health.get("share")) if bob_health else "no bar")
	check("  the leader may hand it on or remove somebody, may ask a fourth, and may leave",
		bob_buttons == ["Lead", "Remove"] and panel.invite_row.visible and panel.leave_button.visible, bob_buttons)
	check("  and Party knows it at once, without waiting for the poll",
		Party.in_one() and Party.is_member("pcat") and Party.leader == "pme")
	(party_answer["data"]["party"] as Dictionary)["leader"] = "pbob"
	((party_answer["data"]["party"] as Dictionary)["members"][0] as Dictionary)["leader"] = false
	await panel.load_party()
	bob_row = panel.list.get_node_or_null(^"member_pbob")
	check("not the leader: no Lead or Remove, and nobody to ask",
		bob_row != null and bob_row.find_children("*", "Button", true, false).is_empty() and not panel.invite_row.visible)
	sent.clear()
	await panel.invite_player("pdan")
	await panel.act("/api/party/kick", {"username": "pcat"})
	await panel.act("/api/party/leave", {})
	check("asking, removing and leaving are posted to the server, and its answer is drawn",
		sent == [["/api/party/invite", {"username": "pdan"}], ["/api/party/kick", {"username": "pcat"}],
			["/api/party/leave", {}]], sent)
	answers[0] = {"ok": false, "status": 400, "error": "pdan is already in a party"}
	await panel.act("/api/party/invite", {"username": "pdan"})
	check("  and a refusal is said as the server says it",
		panel.notice_label.visible and panel.notice_label.text == "pdan is already in a party", panel.notice_label.text)
	panel.close()
	check("  closing it stops its reading", not panel.visible and panel._timer.is_stopped())
	panel.queue_free()

	# ---- the HUD: the poll, the asks, the chat room ----
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await get_tree().process_frame
	hud._apply_broadcast({"party": {"id": 11, "leader": "pamy", "members": ["pamy", "pme"]}})
	check("the broadcast poll's party reaches Party", Party.id == 11 and Party.is_member("pamy") and not Party.is_leader())
	hud._read_asks({"party": {"count": 1, "newest": "pamy", "at": 5000}, "friends": {"count": 0}, "guild": {"count": 0}})
	var party_button: Button = hud.get_node_or_null("%partybutton") as Button
	check("an invitation lights Social > Party, and says who asked",
		party_button != null and party_button.text == "Party •"
		and hud.ask_text("party", "pamy", 1) == "pamy invited you to their party. Open Party to answer.",
		party_button.text if party_button else "no button")
	hud.party_panel = (load("res://scene/ui/party/partypanel.tscn") as PackedScene).instantiate() as PartyPanel
	hud.add_child(hud.party_panel)
	var built: PartyPanel = hud.party_panel
	check("  and Party opens its window, which Escape closes",
		hud._escape_windows().any(func(pair: Array) -> bool: return pair[0] == built and pair[1] is String and pair[1] == "close")
		and _func_body(_code_src("res://src/ui/characterhud.gd"), "func toggle_party(").contains("PARTY_PANEL_SCENE.instantiate()")
		and _func_body(_code_src("res://src/ui/characterhud.gd"), "func _apply_broadcast(").contains("_read_party(data.get(\"party\"))"))
	var chat_src: String = _code_src("res://src/ui/characterhud.gd")
	check("party chat lights the Chat button like guild chat does",
		_func_body(chat_src, "func _read_chat_news(").contains("for room in [\"guild\", \"friends\", \"party\"]"))
	hud.queue_free()

	# ---- their names in the party's colour ----
	var Remote := preload("res://src/characters/remoteplayer.gd")
	var them: Node2D = Remote.new()
	them.user_id = 661
	add_child(them)
	them.set_identity({"id": 661, "name": "pamy", "cls": "healer", "lvl": 8, "v": 2})
	var stranger: Node2D = Remote.new()
	stranger.user_id = 662
	add_child(stranger)
	stranger.set_identity({"id": 662, "name": "pzed", "cls": "mage", "lvl": 8, "v": 2})
	var plate_colour := func(body: Node) -> Color:
		return (body.call("plate") as Label).get_theme_color("font_color")
	var ours: Color = plate_colour.call(them)
	var theirs: Color = plate_colour.call(stranger)
	Party.apply({"id": 0})
	them.call("_process", 0.016)
	var after_leaving: Color = plate_colour.call(them)
	check("your party's names are drawn in the party's colour - and go back when the party does",
		ours == Party.COLOUR and theirs != Party.COLOUR and after_leaving != Party.COLOUR, [ours, theirs, after_leaving])
	them.queue_free()
	stranger.queue_free()

	# ---- the map ----
	var map_src: String = _code_src("res://src/ui/menus/mapscreen.gd")
	var fire: BaseEnemy = (load("res://scene/enemy/firesprite.tscn") as PackedScene).instantiate() as BaseEnemy
	var MapScript := preload("res://src/ui/menus/mapscreen.gd")
	var dead: bool = fire._death_resolved
	check("the map draws every monster alive on explored ground as a dot in its element's colour, and your party in this area with their names",
		MapScript.monster_colour(fire) == Element.colour_for(fire.current_element()) and MapScript.shows_monster(fire)
		and not dead and _func_body(map_src, "func _draw_markers(").contains("_draw_monsters()")
		and _func_body(map_src, "func _draw_monsters(").contains("WorldMap.is_seen(_area, WorldMap.tile_at(_area, where))")
		and _func_body(map_src, "func _draw_markers(").contains("_draw_party()")
		and _func_body(map_src, "func _draw_party(").contains("Party.is_member(who)"))
	fire._death_resolved = true
	check("  not one that has died", not MapScript.shows_monster(fire))
	fire.free()

	# ---- the chat tab ----
	var ChatScript := preload("res://src/ui/chat/chatpanel.gd")
	check("the chat window has a Party tab", ChatScript.CHANNELS.has("party") and ChatScript.CHANNEL_LABELS.get("party") == "Party")

	Party.forget()
	Api.username = kept_name
	await get_tree().process_frame


func _test_names_open_the_player_menu() -> void:
	section("A NAME, CLICKED - add friend, invite to party or guild, report, wherever the name is (0.43.0)")
	# The owner: "clicking over a person should have add friend inv to guild or
	# party and report button that syncs to our mod/dev/owner same thing in chat
	# if i hover over some ones name". test_voice.py holds the report's server.
	var kept_name: String = Api.username
	Api.username = "nme"
	Party.forget()

	# ---- the items ----
	var menu := PopupMenu.new()
	add_child(menu)
	PlayerMenu.fill(menu, "gary")
	var items: Array = []
	var separators: Array = []
	for i in menu.item_count:
		if menu.is_item_separator(i):
			separators.append(menu.get_item_text(i))
		else:
			items.append(menu.get_item_text(i))
	check("every name offers Whisper, Add friend, Trade, Invite to party, Invite to guild, and a report for each reason",
		items == ["Whisper", "Add friend", "Trade", "Invite to party", "Invite to guild", "Spam", "Harassment",
		"Hate speech", "Cheating or scams", "Something else"] and separators == ["Report gary"], [items, separators])
	var actions: Array = []
	for id in [PlayerMenu.WHISPER, PlayerMenu.FRIEND, PlayerMenu.TRADE, PlayerMenu.PARTY, PlayerMenu.GUILD,
			PlayerMenu.REPORT, PlayerMenu.REPORT + 4]:
		actions.append(PlayerMenu.action_of(id))
	check("  each item says what it is, a report with its reason",
		actions == [["whisper", ""], ["friend", ""], ["trade", ""], ["party", ""], ["guild", ""], ["report", "spam"],
		["report", "other"]] and not PlayerMenu.is_ours(1) and not PlayerMenu.is_ours(PlayerMenu.REPORT + 5), actions)
	check("  the reasons are the server's (app.py REPORT_REASONS)",
		PlayerMenu.REPORT_REASONS.map(func(r: Array) -> String: return r[0]) == ["spam", "harassment", "hate", "cheating", "other"])
	Party.apply({"id": 3, "leader": "nme", "members": ["nme", "Gary"]})
	menu.clear()
	PlayerMenu.fill(menu, "gary")
	check("  somebody already in your party is not invited to it again",
		menu.is_item_disabled(menu.get_item_index(PlayerMenu.PARTY)))
	Party.forget()
	menu.free()

	# ---- the name over their head ----
	var Remote := preload("res://src/characters/remoteplayer.gd")
	var host := MenuHost.new()
	host.add_to_group(&"player_menu_host")
	add_child(host)
	var them: Node2D = Remote.new()
	them.user_id = 652
	add_child(them)
	them.set_identity({"id": 652, "name": "Gary", "cls": "mage", "lvl": 4, "v": 2})
	them.set_process(false)
	var plate: Label = them.plate()
	check("the name over another player is a button: it takes the click, under a pointing hand",
		plate != null and plate.mouse_filter == Control.MOUSE_FILTER_STOP
		and plate.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	plate.gui_input.emit(click)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	plate.gui_input.emit(right)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	plate.gui_input.emit(wheel)
	check("  a left or right click on it opens their menu (the wheel does not)", host.opened == ["Gary", "Gary"], host.opened)
	var player_src: String = _func_body(FileAccess.get_file_as_string("res://src/characters/player.gd"), "func _unhandled_input(")
	check("  and never swings: attacks hear only clicks no control took (player.gd _unhandled_input)",
		player_src.contains("_left_click_down = true") and not FileAccess.get_file_as_string(
		"res://src/characters/player.gd").contains("func _input(event"))
	plate.mouse_entered.emit()
	var lit: bool = plate.modulate != Color.WHITE
	plate.mouse_exited.emit()
	check("  hovered, it brightens", lit and plate.modulate == Color.WHITE)
	them.free()
	host.free()

	# ---- the HUD's menu and where each item goes ----
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	add_child(hud)
	check("the HUD answers names clicked in the world", hud.is_in_group(&"player_menu_host"))
	hud.open_player_menu("Gary")
	var hud_menu: PopupMenu = hud.player_menu
	var hud_items: Array = []
	var hud_title: String = ""
	if hud_menu != null:
		for i in hud_menu.item_count:
			if hud_menu.is_item_separator(i):
				if hud_title == "":
					hud_title = hud_menu.get_item_text(i)
			else:
				hud_items.append(hud_menu.get_item_text(i))
	check("  their menu, with their name on top", hud_menu != null and hud_title == "Gary" and hud_items.size() == 10
		and hud_items[3] == "Invite to party" and hud_items[4] == "Invite to guild", [hud_title, hud_items])
	hud.player_menu.clear()
	hud.open_player_menu("NME")
	check("  none for yourself", hud.player_menu.item_count == 0)
	var posted: Array = []
	var reply: Array = [{"ok": true, "status": 200, "data": {"reported": true}}]
	hud.api_post = func(route: String, body: Dictionary) -> Dictionary:
		posted.append([route, body])
		return reply[0]
	await hud.player_action("report", "Gary", "harassment")
	await hud.player_action("guild", "Gary")
	reply[0] = {"ok": false, "status": 403, "error": "Only the leader and officers can invite."}
	await hud.player_action("guild", "Gary")
	var report_body: Dictionary = posted[0][1] if posted.size() > 0 else {}
	check("Report sends the player, the reason and where you are to /api/report/player",
		posted.size() == 3 and posted[0][0] == "/api/report/player" and report_body.get("username") == "Gary"
		and report_body.get("reason") == "harassment" and report_body.get("area") == AreaRegistry.current_area_id(), posted)
	check("  Invite to guild asks the guild's own route; the server's refusal is said as it is",
		posted.size() == 3 and posted[1] == ["/api/guild/invite", {"username": "Gary"}]
		and posted[2][0] == "/api/guild/invite" and hud._refusal_line(reply[0], "x") == "Only the leader and officers can invite.")
	var hud_src: String = FileAccess.get_file_as_string("res://src/ui/characterhud.gd")
	var action_body: String = _func_body(hud_src, "func player_action(")
	check("  and the rest go where they always went: whisper, the Friends, Trade and Party windows",
		action_body.contains("whisper_player(who)") and action_body.contains("ask_to_be_friends(who)")
		and action_body.contains("trade_with(who)") and action_body.contains("invite_to_party(who)"))
	hud.queue_free()
	await get_tree().process_frame

	# ---- the chat's name ----
	var chat_src: String = FileAccess.get_file_as_string("res://src/ui/chat/chatpanel.gd")
	check("in chat, a hovered name is underlined under a pointing hand, and its items go to the HUD",
		_func_body(chat_src, "func _wire_name_click(").contains("meta_hover_started")
		and _func_body(chat_src, "func _wire_name_click(").contains("CURSOR_POINTING_HAND")
		and _func_body(chat_src, "func _on_line_menu_id(").contains("&\"player_action\""))

	# ---- the staff card ----
	var Staff := preload("res://src/ui/staff/staffpanel.gd")
	check("on the staff card a report about the player says so - not a quote nobody said, not 'gone from chat'",
		Staff.quoted("Reported in field", "player") == "Reported in field"
		and Staff.quoted("hello", "world") == "\"hello\""
		and not Staff.describe_card_line({"channel": "player", "line_exists": false, "said_at": 0}, 0).contains("gone")
		and Staff.describe_card_line({"channel": "player", "line_exists": false, "said_at": 0}, 0).contains("the player")
		and Staff.describe_card_line({"channel": "world", "line_exists": false, "said_at": 0}, 0).contains("gone from chat"))
	Api.username = kept_name


func _test_party_voice() -> void:
	section("PARTY VOICE - the browser's own calls through the relay, a switch, mute and push to talk (0.43.0)")
	# The owner: "I really really want the option for voice chat in game for
	# parties ... could even be a flappable switch". test_voice.py holds the
	# relay's route, test_presence.py P-11 who may pass a call's setup to whom.
	var kept := {"name": Api.username, "bridge": Voice.bridge, "fetch": Voice.fetch, "path": Voice.path,
		"mode": Voice.mode, "muted": Voice.muted, "volumes": Voice.volumes.duplicate(), "link": Voice.link_open,
		"send": Presence.send_override, "id": Presence._my_id, "voices": Voice.voices_volume,
		"mic": Voice.mic_volume, "sensitivity": Voice.sensitivity, "echo": Voice.echo_cancel,
		"noise": Voice.noise_suppress}
	Api.username = "vme"
	Party.forget()
	Voice.stop()
	Voice.path = "user://test_voice_settings.cfg"
	DirAccess.remove_absolute(Voice.path)
	Voice.mode = Voice.MODE_OPEN
	Voice.muted = false
	Voice.volumes = {}
	var sent: Array = []
	Presence.send_override = func(message: Dictionary) -> void: sent.append(message)
	Voice.link_open = func() -> bool: return true
	Presence._my_id = 30

	# ---- the JavaScript ----
	var js: String = VoiceBridge.SOURCE
	var missing: Array = []
	for piece in ["V.start", "V.stop", "V.status", "V.reason", "V.dial", "V.hear", "V.hangup", "V.setMic",
			"V.setVolume", "V.takeOutbox", "V.levels", "V.setMicVolume", "V.setGate", "V.setProcessing"]:
		if not js.contains(piece + " = function"):
			missing.append(piece)
	if not js.contains("window.elusionVoice = V;"):
		missing.append("window.elusionVoice")
	check("the browser's side defines every call the game makes on it", missing.is_empty(), missing)
	check("  with no backslash in it (it sits inside a GDScript string)", not js.contains("\\"))
	check("  every call through the relay unless the server says otherwise, and the browser's echo cancellation and noise suppression",
		js.contains("iceTransportPolicy: V.cfg.policy === \"all\" ? \"all\" : \"relay\"")
		and js.contains("echoCancellation: V.ec, noiseSuppression: V.ns") and js.contains("ec: true,")
		and js.contains("ns: true"))
	check("  and none of its names is one GDScript's Object already has (call, connect, set, get, free)",
		not js.contains("V.call = ") and not js.contains("V.connect = ") and not js.contains("V.set = ")
		and not js.contains("V.get = ") and not js.contains("V.free = "))
	check("off the web there is no bridge", VoiceBridge.make() == null)

	# ---- the switch, before it can work ----
	Voice.bridge = null
	await Voice.switch(true)
	check("where there is no browser, the switch says voice is in the browser version",
		not Voice.wanted() and Voice.note.contains("browser version"), Voice.note)
	var fake := FakeVoiceBridge.new()
	Voice.bridge = fake
	await Voice.switch(true)
	check("  in no party, that voice is for parties", not Voice.wanted() and Voice.note.contains("for parties"), Voice.note)
	Party.apply({"id": 5, "leader": "vme", "members": ["vme", "VBob", "vcat"]})
	var asked: Array = []
	var relay: Array = [{"ok": false, "status": 503, "error": "Voice is not set up on this server yet."}]
	Voice.fetch = func(route: String) -> Dictionary:
		asked.append(route)
		return relay[0]
	await Voice.switch(true)
	check("  a server without a relay: said as the server says it, and voice stays off",
		not Voice.wanted() and Voice.note == "Voice is not set up on this server yet." and asked == ["/api/party/voice"]
		and fake.calls.is_empty(), [Voice.note, asked])

	# ---- on ----
	relay[0] = {"ok": true, "status": 200, "data": {"policy": "relay", "expires_at": 1,
		"ice_servers": [{"urls": ["turns:turn.example.com:443?transport=tcp"], "username": "u", "credential": "c"}]}}
	await Voice.switch(true)
	var config: Variant = JSON.parse_string(fake.started_with)
	check("with a relay: the browser is started with it, told 'relay', and who this player is",
		Voice.state == "starting" and config is Dictionary and config.get("policy") == "relay"
		and (config.get("ice_servers") as Array).size() == 1 and int(config.get("me", 0)) == 30
		and Voice.note.contains("microphone"), [Voice.state, fake.started_with])
	Voice._process(0.2)
	check("  waiting for the microphone, nothing is said to anybody", Voice.state == "starting" and sent.is_empty())
	fake.st = "live"
	Voice._process(0.2)
	check("  with it: on, and the socket told this game is in voice",
		Voice.is_on() and sent == [{"t": "vs", "on": true}] and fake.mic, sent)
	Voice.hear({"t": "vs", "in": [{"id": 40, "name": "VBob"}]})
	check("told who is already in voice, it calls each of them",
		fake.calls.has("dial 40") and Voice.members == {40: "VBob"} and Voice.in_voice("vbob"), fake.calls)
	Voice.hear({"t": "vs", "join": {"id": 41, "name": "vcat"}})
	check("  told somebody came, it waits for their call", not fake.calls.has("dial 41") and Voice.in_voice("vcat"))
	Voice.hear({"t": "vc", "from": 40, "d": {"k": "sdp", "sdp": {"type": "answer"}}})
	Voice.hear({"t": "vc", "from": 99, "d": {"k": "ice"}})
	var heard: Array = fake.calls.filter(func(e: String) -> bool: return e.begins_with("hear"))
	check("  a call's setup from somebody in voice goes to the browser - from anybody else, nowhere",
		heard.size() == 1 and heard[0].begins_with("hear 40 ") and heard[0].contains("answer"), heard)
	fake.outbox = [[40, {"k": "ice", "c": {"candidate": "x"}}]]
	sent.clear()
	Voice._process(0.2)
	check("  and what the browser wants sent goes over the socket, to whom it is for",
		sent == [{"t": "vc", "to": 40, "d": {"k": "ice", "c": {"candidate": "x"}}}], sent)

	# ---- who is talking ----
	fake.lv = {"st": "live", "me": 0.3, "peers": {"40": {"lv": 0.4, "st": "connected"}, "41": {"lv": 0.0, "st": "connecting"}}}
	Voice._process(0.2)
	check("who is talking: the browser's loudness, by name, over SPEAKING_LEVEL - you too, while your microphone is open",
		Voice.speaking("vbob") and not Voice.speaking("vcat") and Voice.speaking("vme")
		and Voice.call_state("VBob") == "connected" and Voice.call_state("vcat") == "connecting")
	var Remote := preload("res://src/characters/remoteplayer.gd")
	var bob: Node2D = Remote.new()
	bob.user_id = 40
	add_child(bob)
	bob.set_identity({"id": 40, "name": "VBob", "cls": "warrior", "lvl": 3, "v": 2})
	bob.set_process(false)
	bob.call("_show_talking", Voice.speaking("VBob"))
	var mark: Node2D = bob.get_node_or_null(^"talkmark") as Node2D
	check("  and over their head, a speaker beside their name", mark != null and mark.visible)
	bob.call("_show_talking", false)
	check("  gone when they stop", mark != null and not mark.visible)
	bob.free()

	# ---- the microphone ----
	Voice.set_muted(true)
	var muted_off: bool = not fake.mic and not Voice.mic_open() and not Voice.speaking("vme")
	Voice.set_muted(false)
	Voice.set_mode(Voice.MODE_PUSH)
	var push_idle: bool = not fake.mic
	var talk := InputEventAction.new()
	talk.action = Voice.TALK_ACTION
	talk.pressed = true
	Voice._unhandled_input(talk)
	var push_held: bool = fake.mic
	var let_go := InputEventAction.new()
	let_go.action = Voice.TALK_ACTION
	let_go.pressed = false
	Voice._unhandled_input(let_go)
	check("Mute closes the microphone; push to talk opens it only while the key is held",
		muted_off and push_idle and push_held and not fake.mic, [muted_off, push_idle, push_held])
	Voice._unhandled_input(talk)
	Voice._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check("  and the window losing focus lets go of it - the key's release would never arrive", not fake.mic)
	var mute_key := InputEventAction.new()
	mute_key.action = Voice.MUTE_ACTION
	mute_key.pressed = true
	Voice._unhandled_input(mute_key)
	var by_key: bool = Voice.muted
	Voice._unhandled_input(mute_key)
	check("  the mute key toggles it", by_key and not Voice.muted)
	check("both keys can be rebound, V and B to start, on keys nothing else uses",
		Keybinds.all_actions().has(Voice.TALK_ACTION) and Keybinds.all_actions().has(Voice.MUTE_ACTION)
		and Settings.keys.first_key(Voice.TALK_ACTION) == KEY_V and Settings.keys.first_key(Voice.MUTE_ACTION) == KEY_B
		and Settings.keys.action_for_key(KEY_V) == Voice.TALK_ACTION and Settings.keys.action_for_key(KEY_B) == Voice.MUTE_ACTION)

	# ---- volumes, kept ----
	Voice.set_volume("VBob", 0.4)
	check("each voice has its own volume, set on its call", is_equal_approx(float(fake.vols.get(40, -1.0)), 0.4))
	Voice.volumes = {}
	Voice.mode = Voice.MODE_OPEN
	Voice.load_settings()
	check("  kept on this machine with the mode: read back after a restart",
		is_equal_approx(Voice.volume_of("vbob"), 0.4) and Voice.mode == Voice.MODE_PUSH, [Voice.volumes, Voice.mode])

	# ---- the Party window ----
	var panel: PartyPanel = (load("res://scene/ui/party/partypanel.tscn") as PackedScene).instantiate() as PartyPanel
	add_child(panel)
	var party_answer: Dictionary = {"ok": true, "data": {"capacity": 4, "invites": [], "party": {
		"id": 5, "leader": "vme", "size": 3, "capacity": 4, "members": [
			{"username": "vme", "leader": true, "online": true, "class_id": "healer", "level": 8, "area": "field", "hp": 50, "max_hp": 100},
			{"username": "VBob", "leader": false, "online": true, "class_id": "warrior", "level": 5, "area": "field", "hp": 30, "max_hp": 120},
			{"username": "vdan", "leader": false, "online": true, "class_id": "tank", "level": 9, "area": "town", "hp": 200, "max_hp": 200}]}}}
	panel.fetch = func(_path: String) -> Dictionary: return party_answer
	panel.send = func(_path: String, _body: Dictionary) -> Dictionary: return party_answer
	await panel.open()
	var bob_row: Node = panel.list.get_node_or_null(^"member_VBob")
	var dan_row: Node = panel.list.get_node_or_null(^"member_vdan")
	var bob_mark: Node = bob_row.find_child("voice", true, false) if bob_row else null
	var bob_volume: HSlider = bob_row.find_child("volume", true, false) as HSlider if bob_row else null
	check("the Party window: the Voice switch on, push to talk named with its key, Mute",
		panel.voice_box.visible and panel.voice_switch.button_pressed and panel.voice_switch.text == "Voice on"
		and panel.voice_mode.selected == 1 and panel.voice_mode.get_item_text(1) == "Push to talk (V)"
		and not panel.mute_button.disabled, [panel.voice_switch.text, panel.voice_mode.get_item_text(1)])
	check("  each member in voice: a speaker that lights while they talk (their volume is in Voice settings since 0.45.0)",
		bob_mark != null and bob_volume == null
		and dan_row != null and dan_row.find_child("voice", true, false) == null, [bob_mark != null, bob_volume != null])
	panel._process(0.1)
	check("  lit now: VBob is talking", bob_mark != null and bool(bob_mark.get("lit")))
	check("  and under the switch, how to talk", PartyPanel.voice_line() == "Hold V to talk.", PartyPanel.voice_line())
	panel.mute_button.button_pressed = true
	check("Mute in the window mutes", Voice.muted and PartyPanel.voice_line() == "You are muted.")
	panel.mute_button.button_pressed = false
	panel.voice_mode.select(0)
	panel.voice_mode.item_selected.emit(0)
	check("  the mode in the window sets it", Voice.mode == Voice.MODE_OPEN)

	# ---- out again ----
	fake.calls.clear()
	Voice.hear({"t": "vs", "left": 40})
	check("somebody leaving voice: their call hung up", fake.calls == ["hangup 40"] and not Voice.in_voice("vbob"), fake.calls)
	Voice.hear({"t": "vs", "join": {"id": 41, "name": "vcat"}})
	check("  somebody known saying they joined again (their link dropped): the old call hung up, and they call anew",
		fake.calls.has("hangup 41") and not fake.calls.has("dial 41"), fake.calls)
	sent.clear()
	Party.apply({"id": 0, "leader": "", "members": []})
	Voice._process(0.2)
	check("the party gone: voice off by itself, the socket told, and why said",
		not Voice.wanted() and fake.st == "off" and sent == [{"t": "vs", "on": false}]
		and Voice.note.contains("not in a party"), [sent, Voice.note])
	Party.apply({"id": 5, "leader": "vme", "members": ["vme", "VBob"]})
	await Voice.switch(true)
	fake.st = "denied"
	Voice._process(0.2)
	check("a microphone the browser was not allowed: off, and it says how to allow it",
		not Voice.wanted() and Voice.note.contains("did not allow the microphone"), Voice.note)
	await Voice.switch(true)
	fake.st = "live"
	Voice._process(0.2)
	Voice.hear({"t": "vs", "off": "party"})
	check("the server taking this game out of voice turns it off", not Voice.wanted() and Voice.note.contains("not in a party"))
	await Voice.switch(true)
	fake.st = "live"
	Voice._process(0.2)
	panel.voice_switch.button_pressed = false
	await get_tree().process_frame
	check("the switch off: off", not Voice.wanted() and fake.st == "off")

	panel.queue_free()
	await get_tree().process_frame
	Voice.stop()
	Party.forget()
	DirAccess.remove_absolute(Voice.path)
	Voice.path = kept["path"]
	Voice.bridge = kept["bridge"]
	Voice.fetch = kept["fetch"]
	Voice.mode = kept["mode"]
	Voice.muted = kept["muted"]
	Voice.volumes = kept["volumes"]
	Voice.voices_volume = kept["voices"]
	Voice.mic_volume = kept["mic"]
	Voice.sensitivity = kept["sensitivity"]
	Voice.echo_cancel = kept["echo"]
	Voice.noise_suppress = kept["noise"]
	Voice.note = ""
	Voice.link_open = kept["link"]
	Presence.send_override = kept["send"]
	Presence._my_id = kept["id"]
	Api.username = kept["name"]


func _test_voice_settings() -> void:
	section("VOICE SETTINGS - voices, each player, the microphone and its level, open-mic sensitivity, noise and echo (0.45.0)")
	# The owner: "add a settings for it in that menu so players can adjust
	# voice volume". The browser's side - the gain, the call to itself that
	# keeps a boosted voice inside echo cancellation, the gate, a microphone
	# swapped mid-call - was run for real in Chromium (CLAUDE.md, "Voice
	# settings"); here, the game's.
	var kept := {"name": Api.username, "bridge": Voice.bridge, "fetch": Voice.fetch, "path": Voice.path,
		"mode": Voice.mode, "muted": Voice.muted, "volumes": Voice.volumes.duplicate(), "link": Voice.link_open,
		"send": Presence.send_override, "id": Presence._my_id, "voices": Voice.voices_volume,
		"mic": Voice.mic_volume, "sensitivity": Voice.sensitivity, "echo": Voice.echo_cancel,
		"noise": Voice.noise_suppress}
	Api.username = "sme"
	Party.forget()
	Voice.stop()
	Voice.path = "user://test_voice_settings2.cfg"
	DirAccess.remove_absolute(Voice.path)
	Voice.mode = Voice.MODE_OPEN
	Voice.muted = false
	Voice.volumes = {}
	Voice.voices_volume = 1.0
	Voice.mic_volume = 1.0
	Voice.sensitivity = 0.0
	Voice.echo_cancel = true
	Voice.noise_suppress = true
	Presence.send_override = func(_message: Dictionary) -> void: pass
	Voice.link_open = func() -> bool: return true
	Presence._my_id = 50
	var fake := FakeVoiceBridge.new()
	Voice.bridge = fake
	Voice.fetch = func(_route: String) -> Dictionary:
		return {"ok": true, "status": 200, "data": {"policy": "relay", "ice_servers": []}}
	Party.apply({"id": 6, "leader": "sme", "members": ["sme", "SBob", "sdan"]})

	# ---- set before voice is on, used from the first word ----
	Voice.set_voices_volume(1.5)
	Voice.set_mic_volume(1.8)
	Voice.set_sensitivity(0.4)
	Voice.set_processing(false, true)
	fake.order.clear()
	await Voice.switch(true)
	var start_at: int = fake.order.find("start")
	check("set before voice is on, the settings reach the page before the microphone opens",
		start_at > 0 and fake.order.slice(0, start_at).has("mic_volume") and fake.order.slice(0, start_at).has("gate")
		and fake.order.slice(0, start_at).has("processing")
		and is_equal_approx(fake.mic_volume, 1.8) and is_equal_approx(fake.gate, 0.4 * Voice.GATE_TOP)
		and fake.processing == [false, true], [fake.order, fake.mic_volume, fake.gate, fake.processing])
	fake.st = "live"
	Voice._process(0.2)
	Voice.hear({"t": "vs", "in": [{"id": 60, "name": "SBob"}]})
	check("everyone's voices times each one's own: SBob, at his own 100%, plays at 150%",
		is_equal_approx(float(fake.vols.get(60, -1.0)), 1.5), fake.vols)
	Voice.set_volume("SBob", 2.0)
	check("  his own turned to 200% plays at the most there is, 200%",
		is_equal_approx(float(fake.vols.get(60, -1.0)), 2.0) and is_equal_approx(Voice.volume_of("sbob"), 2.0), fake.vols)
	Voice.set_voices_volume(0.5)
	check("  everyone's at 50% halves him at once: 100%", is_equal_approx(float(fake.vols.get(60, -1.0)), 1.0), fake.vols)
	Voice.set_volume("SBob", 0.0)
	check("  and his own at 0 silences him, whatever everyone's is", is_equal_approx(float(fake.vols.get(60, -1.0)), 0.0))
	Voice.set_volume("SBob", 1.0)

	# ---- the microphone ----
	Voice.set_mic_volume(5.0)
	check("the microphone's volume goes to the page, at most 200%", is_equal_approx(fake.mic_volume, 2.0)
		and is_equal_approx(Voice.mic_volume, 2.0))
	Voice.set_mode(Voice.MODE_PUSH)
	var push_gate: float = fake.gate
	Voice.set_mode(Voice.MODE_OPEN)
	check("open-mic sensitivity is the open mic's: push to talk turns the gate off, open mic puts it back",
		push_gate == 0.0 and is_equal_approx(fake.gate, 0.4 * Voice.GATE_TOP), [push_gate, fake.gate])
	Voice.set_sensitivity(0.0)
	check("  and at 0 it is off: everything goes out", fake.gate == 0.0)
	Voice.set_sensitivity(0.4)
	fake.lv = {"st": "live", "mic": 0.15, "me": 0.0, "gate": false, "peers": {}}
	Voice._process(0.2)
	check("the page's level reaches the bar while nothing goes out (quiet, under the line)",
		is_equal_approx(Voice.mic_level, 0.15) and not Voice.gate_open and is_equal_approx(Voice.meter_share(), 0.5)
		and not Voice.speaking("sme"), [Voice.mic_level, Voice.gate_open, Voice.meter_share()])
	fake.lv = {"st": "live", "mic": 0.2, "me": 0.2, "gate": true, "peers": {}}
	Voice._process(0.2)
	check("  over it, out it goes - and you light up as talking", Voice.gate_open and Voice.speaking("sme"))
	Voice.set_processing(true, false)
	check("noise suppression and echo cancellation go to the page as they are switched",
		fake.processing == [true, false] and Voice.echo_cancel and not Voice.noise_suppress)

	# ---- kept ----
	Voice.voices_volume = 1.0
	Voice.mic_volume = 1.0
	Voice.sensitivity = 0.0
	Voice.echo_cancel = false
	Voice.noise_suppress = true
	Voice.volumes = {}
	Voice.load_settings()
	check("all of it kept on this machine, and read back after a restart",
		is_equal_approx(Voice.voices_volume, 0.5) and is_equal_approx(Voice.mic_volume, 2.0)
		and is_equal_approx(Voice.sensitivity, 0.4) and Voice.echo_cancel and not Voice.noise_suppress
		and is_equal_approx(Voice.volume_of("sbob"), 1.0),
		[Voice.voices_volume, Voice.mic_volume, Voice.sensitivity, Voice.echo_cancel, Voice.noise_suppress])
	var junk := ConfigFile.new()
	junk.set_value(Voice.SECTION, "voices_volume", "loud")
	junk.set_value(Voice.SECTION, "mic_volume", 9)
	junk.set_value(Voice.SECTION, "sensitivity", -3.0)
	junk.set_value(Voice.SECTION, "echo_cancel", "x")
	junk.set_value(Voice.SECTION, "volumes", {"sbob": 7.0, "sdan": "quiet"})
	junk.save(Voice.path)
	Voice.load_settings()
	check("  a damaged file reads as sense: words as the default, numbers held to their range, echo cancellation on",
		is_equal_approx(Voice.voices_volume, 1.0) and is_equal_approx(Voice.mic_volume, 2.0)
		and Voice.sensitivity == 0.0 and Voice.echo_cancel and is_equal_approx(Voice.volume_of("sbob"), 2.0)
		and is_equal_approx(Voice.volume_of("sdan"), 1.0),
		[Voice.voices_volume, Voice.mic_volume, Voice.sensitivity, Voice.echo_cancel, Voice.volumes])
	Voice.set_voices_volume(0.5)
	Voice.set_mic_volume(2.0)
	Voice.set_sensitivity(0.4)
	Voice.set_processing(true, false)
	Voice.set_volume("SBob", 1.0)

	# ---- the Party window ----
	var panel: PartyPanel = (load("res://scene/ui/party/partypanel.tscn") as PackedScene).instantiate() as PartyPanel
	add_child(panel)
	var party_answer: Dictionary = {"ok": true, "data": {"capacity": 4, "invites": [], "party": {
		"id": 6, "leader": "sme", "size": 3, "capacity": 4, "members": [
			{"username": "sme", "leader": true, "online": true, "class_id": "healer", "level": 8, "area": "field", "hp": 50, "max_hp": 100},
			{"username": "SBob", "leader": false, "online": true, "class_id": "warrior", "level": 5, "area": "field", "hp": 30, "max_hp": 120},
			{"username": "sdan", "leader": false, "online": false, "class_id": "tank", "level": 9, "area": "town", "hp": 200, "max_hp": 200}]}}}
	panel.fetch = func(_path: String) -> Dictionary: return party_answer
	panel.send = func(_path: String, _body: Dictionary) -> Dictionary: return party_answer
	await panel.open()
	check("the Party window has Voice settings under the switch, and the member list until it is pressed",
		panel.settings_button != null and panel.settings_button.is_visible_in_tree()
		and panel.settings_button.text == "Voice settings" and panel.list_scroll.visible and not panel.settings_scroll.visible)
	panel.settings_button.button_pressed = true
	check("  pressed: the settings take the list's place, and the button goes back",
		panel.settings_scroll.visible and not panel.list_scroll.visible and panel.settings_button.text == "Back to the party")
	check("  showing what is set: voices 50%, microphone 200%, sensitivity 40%, noise off, echo on",
		is_equal_approx(panel.voices_slider.value, 50.0) and panel.voices_value.text == "50%"
		and is_equal_approx(panel.mic_slider.value, 200.0) and panel.mic_value.text == "200%"
		and is_equal_approx(panel.sensitivity_slider.value, 40.0) and panel.sensitivity_value.text == "40%"
		and not panel.noise_box.button_pressed and panel.echo_box.button_pressed,
		[panel.voices_value.text, panel.mic_value.text, panel.sensitivity_value.text])
	panel.voices_slider.value = 120.0
	panel.mic_slider.value = 80.0
	panel.sensitivity_slider.value = 25.0
	check("  each slider sets Voice, and says its value",
		is_equal_approx(Voice.voices_volume, 1.2) and panel.voices_value.text == "120%"
		and is_equal_approx(Voice.mic_volume, 0.8) and is_equal_approx(fake.mic_volume, 0.8)
		and is_equal_approx(Voice.sensitivity, 0.25) and panel.sensitivity_value.text == "25%",
		[Voice.voices_volume, Voice.mic_volume, Voice.sensitivity])
	panel.noise_box.button_pressed = true
	panel.echo_box.button_pressed = false
	check("  the two switches set the browser's cleaning", fake.processing == [false, true]
		and Voice.noise_suppress and not Voice.echo_cancel, fake.processing)
	var players: Node = panel.each_box.get_node_or_null(^"players")
	var bob_volume: HSlider = players.get_node_or_null(^"volume_SBob") as HSlider if players else null
	var dan_volume: HSlider = players.get_node_or_null(^"volume_sdan") as HSlider if players else null
	check("each other member has a volume - in voice or not yet, online or not - and you have none",
		bob_volume != null and dan_volume != null and players.get_node_or_null(^"volume_sme") == null)
	if dan_volume != null:
		dan_volume.value = 150.0
	check("  set before they come: sdan will play at 150% of everyone's", is_equal_approx(Voice.volume_of("sdan"), 1.5))
	if bob_volume != null:
		bob_volume.value = 30.0
	check("  set while in voice: SBob's call plays at once at his times everyone's (30% x 120%)",
		is_equal_approx(float(fake.vols.get(60, -1.0)), 0.36), fake.vols)

	# ---- the bar ----
	var meter: PartyPanel.MicMeter = panel.mic_meter
	fake.lv = {"st": "live", "mic": 0.05, "me": 0.0, "gate": false, "peers": {}}
	Voice._process(0.2)
	panel._process(0.1)
	check("the level bar: quiet under the line is grey, and says nothing is going out",
		meter != null and not meter.sending() and panel.meter_note.text == "Quiet: nothing is going out.",
		panel.meter_note.text)
	fake.lv = {"st": "live", "mic": 0.2, "me": 0.2, "gate": true, "peers": {}}
	Voice._process(0.2)
	panel._process(0.1)
	check("  over it, green and no words", meter != null and meter.sending() and not panel.meter_note.visible)
	Voice.set_mode(Voice.MODE_PUSH)
	panel.render()
	check("push to talk: the sensitivity is set aside, and the key named",
		not panel.sensitivity_slider.editable and panel.sensitivity_note.text.begins_with("Push to talk: holding V"),
		panel.sensitivity_note.text)
	Voice.set_mode(Voice.MODE_OPEN)
	Voice.set_sensitivity(0.0)
	panel.render()
	check("  open mic with the sensitivity at 0: Off, and it says everything goes out",
		panel.sensitivity_value.text == "Off" and panel.sensitivity_note.text.contains("sends everything"))
	Voice.stop()
	panel.render()
	panel._process(0.1)
	check("with voice off the settings can still be set, and the bar says how to see it",
		panel.settings_scroll.visible and panel.meter_note.text.begins_with("Switch voice on"), panel.meter_note.text)
	panel.settings_button.button_pressed = false
	check("Back to the party: the member list again", panel.list_scroll.visible and not panel.settings_scroll.visible
		and panel.settings_button.text == "Voice settings")
	panel.settings_button.button_pressed = true
	party_answer["data"]["party"] = {}
	Party.apply({"id": 0, "leader": "", "members": []})
	panel.take(party_answer["data"])
	check("  out of the party (no voice to set), the window goes back to the list by itself",
		panel.list_scroll.visible and not panel.settings_scroll.visible)

	panel.queue_free()
	await get_tree().process_frame
	Voice.stop()
	Party.forget()
	DirAccess.remove_absolute(Voice.path)
	Voice.path = kept["path"]
	Voice.bridge = kept["bridge"]
	Voice.fetch = kept["fetch"]
	Voice.mode = kept["mode"]
	Voice.muted = kept["muted"]
	Voice.volumes = kept["volumes"]
	Voice.voices_volume = kept["voices"]
	Voice.mic_volume = kept["mic"]
	Voice.sensitivity = kept["sensitivity"]
	Voice.echo_cancel = kept["echo"]
	Voice.noise_suppress = kept["noise"]
	Voice.note = ""
	Voice.link_open = kept["link"]
	Presence.send_override = kept["send"]
	Presence._my_id = kept["id"]
	Api.username = kept["name"]


func _test_other_players_aim_and_health() -> void:
	section("OTHER PLAYERS - their aim ring and their health, as they see their own (0.41.0)")
	# The owner: "i need to be able to see other players directional bar etc ...
	# i want players to see everything i see and everything i see players also
	# see".
	var Remote := preload("res://src/characters/remoteplayer.gd")
	var kept_rings: bool = bool(Settings.get_value("aim_rings"))
	Settings.set_value("aim_rings", true)
	var arena := Node2D.new()
	add_child(arena)

	# ---- what this game sends ----
	var me: Node2D = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	me.set_physics_process(false)
	me.set_process(false)
	arena.add_child(me)
	me.call("_add_aim_ring")
	const PresenceScript := preload("res://src/systems/presence.gd")
	var sent: Array = []
	for way in [Vector2.RIGHT, Vector2.UP, Vector2.RIGHT.rotated(deg_to_rad(40.0))]:
		(me.get_node(^"aimring") as AimRing).point_at(way)
		sent.append(PresenceScript.aim_degrees_of(me))
	me.set("max_hp", 74)
	me.set("hp", 37)
	var state: Dictionary = Presence.state_for(me)
	check("the state carries where this player's aim ring points, in whole degrees stepped to AIM_STEP_DEGREES, and its health in whole percent",
		sent == [0, 272, 40] and Presence.AIM_STEP_DEGREES == 8
		and state.get("aim") == 40 and state.get("hp") == 50, [sent, state.get("aim"), state.get("hp")])
	var ringless := Node2D.new()
	check("  -1 for a body with no ring or no health", PresenceScript.aim_degrees_of(ringless) == -1 and PresenceScript.health_percent_of(ringless) == -1)
	ringless.free()

	# ---- each class's ring, placed as its own scene places it ----
	var misplaced: Array = []
	for cls in ["warrior", "mage", "tank", "healer"]:
		var body: Node = (load("res://scene/characters/%s.tscn" % cls) as PackedScene).instantiate()
		body.call("_add_aim_ring")
		var theirs: AimRing = body.get_node_or_null(^"aimring") as AimRing
		var spec: Dictionary = Remote.class_ring(cls)
		if theirs == null or spec.is_empty() or theirs.position != spec["position"] or theirs.drawn_at != spec["drawn_at"] \
				or theirs.radii != spec["radii"] or theirs.line != spec["line"]:
			misplaced.append(cls)
		body.free()
	check("every class's ring on somebody else is where their own game puts it - the same feet, size and line",
		misplaced.is_empty(), misplaced)

	# ---- drawn here ----
	var them: Node2D = Remote.new()
	them.user_id = 651
	arena.add_child(them)
	them.set_identity({"id": 651, "name": "Gary", "cls": "warrior", "lvl": 12, "v": 2})
	them.set_process(false)
	them.place(Vector2(-77000, -77000))
	them.set_bearing(90, 40)
	them.call("_follow_aim", 1.0)
	var ring: AimRing = them.aim_ring()
	var bar: Node2D = them.health_bar()
	var body_sprite: Node2D = them.get_node_or_null(^"animatedsprite2d") as Node2D
	check("their aim ring is drawn, pointing where theirs does, under their body",
		ring != null and ring.visible and ring.aim.dot(Vector2.DOWN) > 0.999
		and body_sprite != null and (them.get_children().find(ring) < them.get_children().find(body_sprite)
			or (them.y_sort_enabled and ring.position.y <= body_sprite.position.y)),
		[ring != null, str(ring.aim) if ring != null else "no ring"])
	check("  and their health as a bar under their name - 40%, so amber",
		bar != null and bar.visible and is_equal_approx(float(bar.get("share")), 0.4)
		and Remote.RemoteHealthBar.colour_for(0.4) == Remote.RemoteHealthBar.colour_for(0.3)
		and Remote.RemoteHealthBar.colour_for(0.9) != Remote.RemoteHealthBar.colour_for(0.4)
		and Remote.RemoteHealthBar.colour_for(0.1) != Remote.RemoteHealthBar.colour_for(0.4)
		and bar.position.y < 0.0, [bar != null, bar.get("share") if bar else null])
	them.set_bearing(180, 40)
	them.call("_follow_aim", 1.0 / 60.0)
	var swinging: Vector2 = ring.aim if ring != null else Vector2.ZERO
	them.call("_follow_aim", 1.0)
	check("  the ball swings round to a new aim rather than jumping, and arrives",
		ring != null and swinging.dot(Vector2.LEFT) < 0.99 and swinging.dot(Vector2.DOWN) < 0.99 and ring.aim.dot(Vector2.LEFT) > 0.999,
		[str(swinging), str(ring.aim) if ring != null else "no ring"])
	Settings.set_value("aim_rings", false)
	them.call("_follow_aim", 1.0 / 60.0)
	var off_with_switch: bool = ring != null and not ring.visible
	Settings.set_value("aim_rings", true)
	them.set_motion("deathdown", [], "")
	them.call("_follow_aim", 1.0 / 60.0)
	var off_dying: bool = ring != null and not ring.visible
	them.set_motion("idledown", [], "")
	them.set_bearing(-1, -1)
	them.call("_follow_aim", 1.0 / 60.0)
	check("  none with Aim rings switched off here, while they are dying, or from a game or server that sends none",
		off_with_switch and off_dying and ring != null and not ring.visible and (bar == null or not bar.visible))

	# ---- off the wire ----
	Presence._remotes[651] = them
	Presence.handle_message({"t": "moves", "p": [[651, -77000.0, -77000.0, "walkdown", [], "", 1000, 304, 25]]})
	var from_moves: Array = [them.aim_degrees, them.health_percent]
	Presence.handle_message({"t": "moves", "p": [[651, -77000.0, -77000.0, "walkdown", [], "", 1100]]})
	var old_server: Array = [them.aim_degrees, them.health_percent]
	Presence._remotes.erase(651)
	them.set_bearing(400, 250)
	var clamped: Array = [them.aim_degrees, them.health_percent]
	check("a step's eighth and ninth are their aim and health; a server from before sends seven, and changes nothing",
		from_moves == [304, 25] and old_server == [304, 25], [from_moves, old_server])
	check("  and an aim past a turn is none, a health past 100 is 100", clamped == [-1, 100], clamped)
	Settings.set_value("aim_rings", kept_rings)
	arena.queue_free()
	await get_tree().process_frame


func _test_attacks_aim_with_no_cursor() -> void:
	section("THE CURSOR, WHEN THERE IS ONE - no mouse on the game, and an attack aims the way the character faces (0.41.0)")
	# Gary, in Chrome: "he can only attack left also with warrior". A game that
	# never saw the mouse has it at (0, 0), the top-left corner, and every
	# attack aims at the cursor - Space too - so from the keyboard every swing
	# went left. Reproduced in Chromium before the fix: walk any way, Space,
	# attackleft.
	const PlayerScript := preload("res://src/characters/player.gd")
	var kept: bool = PlayerScript.pointer_on_game
	var arena := Node2D.new()
	add_child(arena)
	var warrior: Node2D = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	warrior.set_physics_process(false)
	warrior.set_process(false)
	arena.add_child(warrior)
	warrior.global_position = Vector2(-76000, -76000)
	PlayerScript.pointer_on_game = false
	var faced: Array = []
	for way in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2(1, 1).normalized()]:
		warrior.set("last_direction", way)
		faced.append((warrior.aim_direction_to(warrior.aim_point()) as Vector2).dot(way) > 0.9999
			and absf(warrior.global_position.distance_to(warrior.aim_point()) - PlayerScript.KEYBOARD_AIM_REACH) < 0.05)
	check("no cursor on the game - the mouse off the page, a keyboard player: an attack aims the way they face, never at the screen's corner",
		faced == [true, true, true, true, true], faced)
	PlayerScript.pointer_on_game = true
	check("  a cursor on the game: at the cursor, as ever (where it is this tick - steady_mouse_position())",
		warrior.aim_point() == warrior.steady_mouse_position())
	PlayerScript.pointer_on_game = false
	warrior.set("_pointer_was", warrior.get_viewport().get_mouse_position() + Vector2(3, 0))
	warrior.call("_watch_pointer")
	var moved_on: bool = PlayerScript.pointer_on_game
	warrior.call("_on_pointer_left_window")
	var left_it: bool = PlayerScript.pointer_on_game
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	warrior.call("_unhandled_input", click)
	var clicked: bool = PlayerScript.pointer_on_game
	PlayerScript.pointer_on_game = false
	warrior.call("_watch_pointer")
	var still: bool = PlayerScript.pointer_on_game
	check("  the mouse is on the game once it moves over it or clicks it, and off it as it leaves the window - a still one is not news",
		moved_on and not left_it and clicked and not still, [moved_on, left_it, clicked, still])
	check("  the window's mouse_exited is listened to, and the watch runs every physics frame",
		_func_body(_code_src("res://src/characters/player.gd"), "func _ready(").contains("get_window().mouse_exited.connect(_on_pointer_left_window)")
		and _func_body(_code_src("res://src/characters/player.gd"), "func _physics_process(").contains("_watch_pointer()"))
	var read_directly: Array = []
	for cls in ["warrior", "mage", "tank", "healer"]:
		if _code_src("res://src/characters/%s.gd" % cls).contains("get_global_mouse_position()"):
			read_directly.append(cls)
	check("every class aims its attacks, its aim ring and its aura through aim_point() - none reads the cursor itself",
		read_directly.is_empty(), read_directly)
	PlayerScript.pointer_on_game = kept
	arena.queue_free()
	await get_tree().process_frame


func _test_aim_holds_still_while_walking() -> void:
	section("THE AIM HOLDS STILL WHILE YOU WALK - the cursor read where the camera is this tick, not where the last frame drew it (0.46.1)")
	# The owner: "when moving left and right that ball wobbles ... if my mouse
	# is not moving and the ball is wobbling means there is a tiny issue". The
	# cursor was mapped through the canvas transform of the last DRAWN frame -
	# the camera part-way between two physics ticks (interpolation; 60 frames
	# to 80 ticks) - and the aim worked out from this tick's position. Measured
	# walking right with the cursor still, before: the ball's angle went
	# -135.58, -135.47, -135.36, -135.69 and round again; after: -135.0 every
	# tick. Here the drawn frame is made to lag on purpose.
	const PlayerScript := preload("res://src/characters/player.gd")
	var kept: bool = PlayerScript.pointer_on_game
	var arena := Node2D.new()
	add_child(arena)
	var warrior: Node2D = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	warrior.set_physics_process(false)
	warrior.set_process(false)
	arena.add_child(warrior)
	warrior.global_position = Vector2(-75000, -75000)
	var camera: Camera2D = warrior.get_node_or_null(^"camera2d") as Camera2D
	PlayerScript.pointer_on_game = true
	var viewport: Viewport = warrior.get_viewport()
	var kept_canvas: Transform2D = viewport.canvas_transform
	var view: Rect2 = viewport.get_visible_rect()
	var mouse: Vector2 = viewport.get_mouse_position()
	var wanted: Vector2 = Vector2.ZERO
	var off_by: Array = []
	if camera != null:
		camera.make_current()
		for lag in [Vector2(-2.5, 0.0), Vector2(-0.7, 0.0), Vector2(0.0, 1.6), Vector2(1.9, -1.2)]:
			# The frame as drawn: centred `lag` away from where the camera is.
			var drawn_at: Vector2 = camera.global_position + (lag as Vector2)
			viewport.canvas_transform = Transform2D(0.0, camera.zoom, 0.0, view.get_center() - drawn_at * camera.zoom)
			wanted = camera.global_position + (mouse - view.get_center()) / camera.zoom
			off_by.append(snappedf(warrior.steady_mouse_position().distance_to(wanted), 0.001))
		viewport.canvas_transform = kept_canvas
	check("the cursor is read where the camera is this tick, however far the drawn frame lags: the same point every time (%s)" % str(off_by),
		camera != null and off_by.size() == 4 and off_by.all(func(d): return d < 0.01), off_by)
	check("  and every class aims through it: aim_point() is steady_mouse_position() while the cursor is on the game",
		_func_body(_code_src("res://src/characters/player.gd"), "func aim_point(").contains("return steady_mouse_position()"))
	check("  read off the camera's own node - get_screen_center_position() answers with the drawn, in-between centre too",
		not _func_body(_code_src("res://src/characters/player.gd"), "func _as_this_tick(").contains("camera.get_screen_center_position()")
		and _func_body(_code_src("res://src/characters/player.gd"), "func _as_this_tick(").contains("camera.global_position + camera.offset")
		and _func_body(_code_src("res://src/characters/player.gd"), "func steady_mouse_position(").contains("_as_this_tick(get_global_mouse_position())"))
	PlayerScript.pointer_on_game = kept
	arena.queue_free()
	await get_tree().process_frame


func _test_a_touch_screen_plays_the_game() -> void:
	section("ON A TOUCH SCREEN - a pad for the thumbs, pressing the actions the keys press (0.53.0)")
	# The owner: "make the game mobile", and which way: "Phone browsers
	# (Recommended)". The game is played through input actions, so a phone is
	# played the same way: touchpad.gd on the HUD says what the thumbs do, and
	# touchcontrols.gd presses move_*, sprint, attack and interact for them.
	const PlayerScript := preload("res://src/characters/player.gd")
	const PadScript := preload("res://src/ui/touchpad.gd")
	const TouchScript := preload("res://src/systems/touchcontrols.gd")
	var kept_pointer: bool = PlayerScript.pointer_on_game
	TouchControls.set_active(false)

	# ---- on at a finger, off at a key or a real mouse --------------------------
	var finger := InputEventScreenTouch.new()
	finger.pressed = true
	finger.index = 0
	finger.position = Vector2(100, 100)
	TouchControls._input(finger)
	var on_at_touch: bool = TouchControls.active
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_W
	TouchControls._input(key)
	var off_at_key: bool = not TouchControls.active
	TouchControls._input(finger)
	var copied := InputEventMouseButton.new()
	copied.pressed = true
	copied.button_index = MOUSE_BUTTON_LEFT
	copied.device = InputEvent.DEVICE_ID_EMULATION
	TouchControls._input(copied)
	var on_past_copy: bool = TouchControls.active
	var real := InputEventMouseButton.new()
	real.pressed = true
	real.button_index = MOUSE_BUTTON_LEFT
	TouchControls._input(real)
	var off_at_mouse: bool = not TouchControls.active
	check("the pad comes on at a finger on the screen and goes at a key, or a click from a real mouse",
		on_at_touch and off_at_key and off_at_mouse, [on_at_touch, off_at_key, off_at_mouse])
	check("  but not at the first finger's own copied click (emulate_mouse_from_touch)", on_past_copy)
	var line := LineEdit.new()
	add_child(line)
	line.grab_focus()
	TouchControls._input(finger)
	TouchControls._input(key)
	var kept_typing: bool = TouchControls.active
	line.queue_free()
	await get_tree().process_frame
	check("  nor at a key typed into a text box - a phone's own keyboard sends keys", kept_typing)

	# ---- the stick is the move keys, eight ways --------------------------------
	TouchControls.set_active(true)
	var eight: Array = []
	var wanted: Array = []
	for step in 8:
		var angle: float = -TAU * step / 8.0
		TouchControls.stick = Vector2(cos(angle), sin(angle))
		TouchControls.stick_held = true
		TouchControls._physics_process(0.0)
		eight.append([int(Input.is_action_pressed("move_right")) - int(Input.is_action_pressed("move_left")),
			int(Input.is_action_pressed("move_down")) - int(Input.is_action_pressed("move_up"))])
		wanted.append([int(round(cos(angle) * 1.3)) if absf(cos(angle)) > 0.5 else 0, int(round(sin(angle) * 1.3)) if absf(sin(angle)) > 0.5 else 0])
	check("the stick presses the move keys eight ways: right, up-right, up, up-left, left and round", eight == wanted, [eight, wanted])
	TouchControls.stick = Vector2(0.1, -0.05)
	TouchControls._physics_process(0.0)
	var dead: bool = not Input.is_action_pressed("move_right") and not Input.is_action_pressed("move_up")
	TouchControls.stick = Vector2(0.9, 0.3)
	TouchControls._physics_process(0.0)
	var slice: bool = Input.is_action_pressed("move_right") and not Input.is_action_pressed("move_down")
	check("  a thumb barely off the middle is no way at all, and one a little below right is right", dead and slice, [dead, slice])
	check("  move_way() is that rule: each of x and y -1, 0 or 1",
		TouchScript.move_way(Vector2(0.7, 0.7)) == Vector2(1, 1) and TouchScript.move_way(Vector2(-0.95, 0.2)) == Vector2(-1, 0)
		and TouchScript.move_way(Vector2(0.05, 0.0)) == Vector2.ZERO)

	# ---- Run: on for this run --------------------------------------------------
	TouchControls.stick = Vector2(1, 0)
	TouchControls.toggle_sprint()
	TouchControls._physics_process(0.0)
	var running: bool = Input.is_action_pressed("sprint")
	TouchControls.stick_held = false
	TouchControls.stick = Vector2.ZERO
	TouchControls._physics_process(0.0)
	var ran_out: bool = not Input.is_action_pressed("sprint") and not TouchControls.sprint_on
	TouchControls.toggle_sprint()
	TouchControls._physics_process(0.0)
	var waits: bool = TouchControls.sprint_on and not Input.is_action_pressed("sprint")
	TouchControls.sprint_on = false
	check("Run sprints while the stick moves, and ends as the thumb leaves the stick", running and ran_out, [running, ran_out])
	check("  tapped before moving, it waits for the stick rather than switching itself off", waits)

	# ---- Attack and Use: the keys they stand for --------------------------------
	# Latched for no class in particular: held like a key (the tank's, the
	# healer's). The class's own say comes below.
	TouchControls.press_attack()
	TouchControls._latch_attack(null)
	var down: bool = Input.is_action_pressed("attack")
	TouchControls._latch_attack(null)
	var held: bool = Input.is_action_pressed("attack")
	TouchControls.release_attack()
	TouchControls._latch_attack(null)
	var up: bool = not Input.is_action_pressed("attack")
	TouchControls.press_attack()
	TouchControls.release_attack()
	TouchControls._latch_attack(null)
	var tapped: bool = Input.is_action_pressed("attack")
	TouchControls._latch_attack(null)
	var tap_over: bool = not Input.is_action_pressed("attack")
	check("Attack is the attack key: down while the thumb is", down and held and up, [down, held, up])
	check("  and a tap quicker than a frame is still one press, for one frame", tapped and tap_over, [tapped, tap_over])
	TouchControls.press_use()
	TouchControls.release_use()
	TouchControls._physics_process(0.0)
	var used: bool = Input.is_action_pressed("interact")
	TouchControls._physics_process(0.0)
	check("Use is the interact key - the shop, the bank, the fire and the fishing spot ask for it, and a tap is one press",
		used and not Input.is_action_pressed("interact"))
	var asking: Array = []
	for path in ["res://src/world/vendor.gd", "res://src/world/bankchest.gd", "res://src/world/firepit.gd",
			"res://src/world/fishingspot.gd", "res://src/world/lootbag.gd", "res://src/world/lever.gd"]:
		if _code_src(path).contains("Input.is_action_just_pressed(\"interact\")"):
			asking.append(path.get_file())
	check("  every one of them still asks the action, so Use reaches all six", asking.size() == 6, asking)

	# ---- held, Attack keeps attacking where a second press is another swing ---
	var arena := Node2D.new()
	add_child(arena)
	var warrior: Node2D = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	warrior.set_physics_process(false)
	warrior.set_process(false)
	arena.add_child(warrior)
	warrior.global_position = Vector2(-73000, -73000)
	var beats: Array = []
	TouchControls.press_attack()
	for frame in 6:
		if frame == 2:
			warrior.set("is_attacking", true)
		if frame == 4:
			warrior.set("is_attacking", false)
		TouchControls._latch_attack(warrior)
		beats.append(int(Input.is_action_pressed("attack")))
	TouchControls.release_attack()
	TouchControls._latch_attack(warrior)
	check("held, the warrior's Attack presses again each time the last swing is over - never mid-swing, so it walks no slower than clicking (%s)" % str(beats),
		beats == [1, 0, 0, 0, 1, 0], beats)
	check("  the warrior and the mage repeat; the tank (attack is its aura's switch) and the Double Axe (the next press calls it home) do not",
		warrior.call("touch_attack_repeats") == true
		and _func_body(_code_src("res://src/characters/warrior.gd"), "func touch_attack_repeats(").contains("SPINNING_AXE")
		and _code_src("res://src/characters/mage.gd").contains("func touch_attack_repeats(")
		and not _code_src("res://src/characters/tank.gd").contains("func touch_attack_repeats(")
		and not _code_src("res://src/characters/healer.gd").contains("func touch_attack_repeats("))
	check("  a mage presses again only with the mana for it: a refused press is still a frame it does not walk",
		_func_body(_code_src("res://src/characters/mage.gd"), "func touch_attack_ready(").contains("mana >= spell_mana_cost"))

	# ---- the aim: a finger on the world, a drag, the nearest monster, the facing
	warrior.set("last_direction", Vector2.RIGHT)
	TouchControls._aim_frame = -1
	var faced: Vector2 = warrior.aim_point()
	check("on a touch screen with no monster near, an attack aims the way the character faces, as a keyboard's",
		TouchControls.aim_for(warrior) == null
		and faced.is_equal_approx(warrior.global_position + Vector2.RIGHT * PlayerScript.KEYBOARD_AIM_REACH), faced)
	var near := Node2D.new()
	near.add_to_group("enemies")
	arena.add_child(near)
	near.global_position = warrior.global_position + Vector2(0, 120)
	var far := Node2D.new()
	far.add_to_group("enemies")
	arena.add_child(far)
	far.global_position = warrior.global_position + Vector2(TouchScript.AUTO_AIM_RANGE + 40.0, 0)
	var corpse_script := GDScript.new()
	corpse_script.source_code = "extends Node2D\nfunc can_be_aimed_at() -> bool:\n\treturn false\n"
	corpse_script.reload()
	var corpse: Node2D = corpse_script.new()
	corpse.add_to_group("enemies")
	arena.add_child(corpse)
	corpse.global_position = warrior.global_position + Vector2(-30, 0)
	near.remove_from_group("enemies")
	TouchControls._aim_frame = -1
	var only_far: Variant = TouchControls.aim_for(warrior)
	near.add_to_group("enemies")
	check("  a monster further off than AUTO_AIM_RANGE is not aimed at: the facing, still", only_far == null, only_far)
	TouchControls._aim_frame = -1
	check("  a monster in reach and it aims at that one - the nearest that can still be hit, not a corpse closer by",
		warrior.aim_point().is_equal_approx(near.global_position), warrior.aim_point())
	check("  a monster's body, not its origin: its \"bodyshape\", where it has one",
		_func_body(_code_src("res://src/systems/touchcontrols.gd"), "static func target_point(").contains("bodyshape"))
	check("  and a monster dying, or behind a boss gate, is never picked (BaseEnemy.can_be_aimed_at())",
		_func_body(_code_src("res://src/enemies/baseenemy.gd"), "func can_be_aimed_at(").contains("not _dying")
		and _func_body(_code_src("res://src/enemies/baseenemy.gd"), "func can_be_aimed_at(").contains("not gated"))
	TouchControls.press_attack()
	TouchControls.attack_drag = Vector2(0, -1)
	var dragged: Vector2 = warrior.aim_point()
	TouchControls.attack_drag = Vector2(0, -0.1)
	var barely: Vector2 = warrior.aim_point()
	TouchControls.release_attack()
	check("  Attack dragged aims the way it is dragged - up, past the monster below - all the way at DRAG_REACH",
		dragged.is_equal_approx(warrior.global_position + Vector2.UP * TouchScript.DRAG_REACH), dragged)
	check("  and a thumb that hardly moved has not dragged: the monster still", barely.is_equal_approx(near.global_position), barely)
	var on_world := InputEventScreenTouch.new()
	on_world.pressed = true
	on_world.index = 2
	on_world.position = Vector2(900, 200)
	TouchControls._unhandled_input(on_world)
	var finger_aim: Vector2 = warrior.aim_point()
	var as_world: Vector2 = warrior.world_point_at(Vector2(900, 200))
	TouchControls._physics_process(0.0)
	var world_attacks: bool = Input.is_action_pressed("attack")
	on_world.pressed = false
	TouchControls._unhandled_input(on_world)
	var still_there: Vector2 = warrior.aim_point()
	TouchControls._physics_process(0.0)
	TouchControls._physics_process(0.0)
	TouchControls._aim_frame = -1
	var after: Vector2 = warrior.aim_point()
	check("a finger on the world - on no button or window - is an attack, aimed where it touched, as a click is",
		world_attacks and finger_aim.is_equal_approx(as_world), [world_attacks, finger_aim, as_world])
	check("  lifted quicker than a frame, it still aims there for the frame its press lands on; after, the monster again",
		still_there.is_equal_approx(as_world) and after.is_equal_approx(near.global_position), [still_there, after])
	var quick := InputEventScreenTouch.new()
	quick.pressed = true
	quick.index = 4
	quick.position = Vector2(1000, 150)
	TouchControls._unhandled_input(quick)
	quick.pressed = false
	TouchControls._unhandled_input(quick)
	TouchControls._latch_attack(null)
	var quick_struck: bool = Input.is_action_pressed("attack")
	TouchControls._latch_attack(null)
	check("  a tap on the world quicker than a frame is still an attack, once",
		quick_struck and not Input.is_action_pressed("attack"), quick_struck)
	TouchControls._physics_process(0.0)
	TouchControls._physics_process(0.0)
	check("  where it touched in the world as it is this tick - the cursor's rule (world_point_at() and steady_mouse_position() agree)",
		warrior.world_point_at(warrior.get_viewport().get_mouse_position()).is_equal_approx(warrior.steady_mouse_position()))

	# ---- the first finger's copied clicks never swing --------------------------
	PlayerScript.pointer_on_game = false
	warrior.set("_left_click_down", false)
	warrior.call("_unhandled_input", copied)
	var copy_swung: bool = bool(warrior.get("_left_click_down")) or PlayerScript.pointer_on_game
	var mouse := InputEventMouseButton.new()
	mouse.pressed = true
	mouse.button_index = MOUSE_BUTTON_LEFT
	warrior.call("_unhandled_input", mouse)
	var mouse_swung: bool = bool(warrior.get("_left_click_down"))
	warrior.set("_left_click_down", false)
	PlayerScript.pointer_on_game = true
	warrior.call("_watch_pointer")
	var no_cursor: bool = not PlayerScript.pointer_on_game
	check("the player takes no click copied from a finger - a thumb on the stick is not a swing - and still every real one",
		not copy_swung and mouse_swung, [copy_swung, mouse_swung])
	check("  and on a touch screen there is no cursor on the game: the copied one stays where the finger last lifted",
		no_cursor)

	# ---- the healer's Aura button -----------------------------------------------
	var healer: Node2D = (load("res://scene/characters/healer.tscn") as PackedScene).instantiate()
	healer.set_physics_process(false)
	healer.set_process(false)
	arena.add_child(healer)
	healer.global_position = Vector2(-72000, -72000)
	var reach: float = float(healer.call("touch_skill_reach"))
	var at_feet: Vector2 = TouchControls.skill_point(healer, Vector2.ZERO)
	var nudged: Vector2 = TouchControls.skill_point(healer, Vector2(0.1, 0.0))
	var full: Vector2 = TouchControls.skill_point(healer, Vector2(1, 0))
	var half: Vector2 = TouchControls.skill_point(healer, Vector2(0, 0.6))
	check("the Aura button: a tap drops it at the healer's feet, a drag the way and as far as it went, up to its reach",
		at_feet == healer.global_position and nudged == healer.global_position and full.is_equal_approx(healer.global_position + Vector2(reach, 0))
		and half.y > healer.global_position.y + TouchScript.SKILL_NEAREST and half.y < healer.global_position.y + reach
		and healer.call("touch_skill_name") == "Aura", [at_feet, full, half])
	check("  only the healer has one: every other class says no skill", warrior.call("touch_skill_name") == "")
	TouchControls.press_skill()
	TouchControls._physics_process(0.0)
	var not_yet: bool = not TouchControls.skill_fired
	TouchControls.skill_drag = Vector2(1, 0)
	TouchControls.release_skill()
	TouchControls._physics_process(0.0)
	var fired: bool = TouchControls.skill_fired and TouchControls.skill_fired_drag == Vector2(1, 0)
	TouchControls._physics_process(0.0)
	check("  it drops as the thumb lets go - where it was dragged - for the one frame", not_yet and fired and not TouchControls.skill_fired,
		[not_yet, fired])
	check("  and the healer takes it as a right-click, at that point",
		_func_body(_code_src("res://src/characters/healer.gd"), "func _physics_process(").contains("right_click_held() or touched")
		and _func_body(_code_src("res://src/characters/healer.gd"), "func _physics_process(").contains("TouchControls.skill_point(self, TouchControls.skill_fired_drag)"))

	# ---- off: every key it pressed is let go -------------------------------------
	TouchControls.stick = Vector2(1, 0)
	TouchControls.stick_held = true
	TouchControls.press_attack()
	TouchControls.press_use()
	TouchControls._physics_process(0.0)
	TouchControls.set_active(false)
	var any_left: Array = []
	for action in [&"move_right", &"attack", &"interact", &"sprint"]:
		if Input.is_action_pressed(action):
			any_left.append(action)
	check("switched off - a key pressed - and every action it held is let go", any_left.is_empty() and not TouchControls.attack_held, any_left)
	check("  and it presses them before any other node reads them: first in the physics frame, an autoload",
		TouchControls.process_physics_priority < 0 and warrior.process_physics_priority == 0
		and FileAccess.get_file_as_string("res://project.godot").contains("TouchControls=\"*res://src/systems/touchcontrols.gd\""))
	arena.queue_free()
	await get_tree().process_frame

	# ---- the pad: on the HUD, under it, thumb-sized ------------------------------
	check("thumb-sized: one game unit to a CSS pixel on a laptop, near two on a phone held sideways, never past %.1f" % PadScript.MOST_SCALE,
		is_equal_approx(PadScript.thumb_scale(Vector2(1280, 720), Vector2(1280, 720), 1.0), 1.0)
		and is_equal_approx(PadScript.thumb_scale(Vector2(2560, 1440), Vector2(1280, 720), 1.0), 1.0)
		and absf(PadScript.thumb_scale(Vector2(2532, 1170), Vector2(1280, 720), 3.0) - 1.846) < 0.01
		and is_equal_approx(PadScript.thumb_scale(Vector2(600, 300), Vector2(1280, 720), 3.0), PadScript.MOST_SCALE),
		[PadScript.thumb_scale(Vector2(2532, 1170), Vector2(1280, 720), 3.0)])
	var clashes: Array = []
	for f in [1.0, 1.4, 1.85, 2.4]:
		for has_skill in [false, true]:
			var at: Dictionary = PadScript.layout(Vector2(1280, 720), f, 557.0, 672.0, has_skill)
			# Each socket as far as it answers a touch, and a small one's word.
			var parts: Array = []
			for id in ["attack", "use", "run", "skill"]:
				if at.has(id):
					var socket: Rect2 = at[id]
					parts.append([id, socket.grow(socket.size.x * (PadScript.REACH - 1.0) / 2.0)])
					if id != "attack":
						parts.append([id + " word", PadScript.caption_box(socket, at["words"])])
			var zone: Rect2 = at["zone"]
			for part in parts:
				var box: Rect2 = part[1]
				if not Rect2(0, 0, 1280, 720).encloses(box) or box.end.y > 557.0 or box.intersects(zone):
					clashes.append([f, part[0], "off the screen, on the hotbar or on the stick"])
				for other in parts:
					if String(part[0]) < String(other[0]) and not String(other[0]).begins_with(String(part[0]).get_slice(" ", 0) + " ") \
							and not String(part[0]).begins_with(String(other[0]).get_slice(" ", 0) + " ") and box.intersects(other[1]):
						clashes.append([f, part[0], other[0]])
			var rest: Vector2 = at["stick_rest"]
			var r: float = at["stick_radius"]
			if not zone.encloses(Rect2(rest - Vector2(r, r), Vector2(r, r) * 2.0)) or zone.end.y > 672.0:
				clashes.append([f, "stick", "outside its zone, or on the menu bar"])
	check("laid out at every size, with and without a skill: on the screen, off the hotbar and the menu bar, no socket or its word on another or on the stick",
		clashes.is_empty(), clashes)
	# ONLY THE GAME'S OWN ART (0.54.0). The owner: "we need to use my art only
	# there is no shortcuts we can look at potential stuff from clockwork".
	var pad_code: String = _code_src("res://src/ui/touchpad.gd")
	var drawn_here: Array = []
	for making in ["Image.create", "set_pixel", "draw_circle(", "draw_arc(", "draw_rect(", "draw_polygon(", "draw_line("]:
		if pad_code.contains(making):
			drawn_here.append(making)
	check("ONLY THE GAME'S OWN ART: the pad draws no picture of its own - the sockets are the hotbar's slot, every icon and the knob the Clockwork pack's (0.54.0)",
		drawn_here.is_empty() and PadScript.SOCKET.resource_path == "res://art/images/hotbarslot.png"
		and PadScript.ICON_PATHS.values().all(func(path: String) -> bool: return path.begins_with("res://art/pack/"))
		and String(PadScript.KNOB_PATH).begins_with("res://art/pack/")
		and PadScript.ICON_PATHS.has("attack") and PadScript.ICON_PATHS.has("use")
		and PadScript.ICON_PATHS.has("run") and PadScript.ICON_PATHS.has("skill"), drawn_here)
	check("  and none of the pack is preloaded - a clone has no pack, and a preload of a missing file stops the script compiling",
		not FileAccess.get_file_as_string("res://src/ui/touchpad.gd").contains("preload(\"res://art/pack"))
	var missing_art: Array = []
	for path in PadScript.ICON_PATHS.values() + [PadScript.KNOB_PATH]:
		if PadScript.Art.picture(path) == null:
			missing_art.append(path)
	check_needs_pack("  every one of them is in the pack and loads", missing_art.is_empty(), missing_art)
	check("  where it is not, nothing breaks: no picture, and the button says its word in its socket",
		PadScript.Art.picture("res://art/pack/icons/no_such_icon.png") == null
		and _func_body(pad_code, "	func _draw(").contains("if picture == null:"))
	var whole: Array = []
	for per_unit in [1.0, 1.3125, 1.625, 2.17]:
		var px: float = PadScript.art_pixel(170.0, PadScript.ATTACK_ART, per_unit)
		var texel: float = PadScript.Art.texel_size(130.0, 16, per_unit)
		if absf(px * per_unit - roundf(px * per_unit)) > 0.001 or absf(texel * per_unit - roundf(texel * per_unit)) > 0.001:
			whole.append([per_unit, px, texel])
	check("  a socket's pixel and an icon's are whole screen pixels at every screen scale, as crisp as the hotbar's", whole.is_empty(), whole)
	var hud := Control.new()
	hud.size = Vector2(1280, 720)
	var hotbar := Control.new()
	hotbar.name = "hotbar"
	hotbar.position = Vector2(880, 557)
	hotbar.size = Vector2(396, 52)
	hud.add_child(hotbar)
	add_child(hud)
	var pad: Control = TouchControls.attach(hud)
	var first: bool = hud.get_child(0) == pad
	TouchControls.set_active(false)
	pad._process(0.0)
	var hidden_off: bool = not pad.visible
	TouchControls.set_active(true)
	pad._process(0.0)
	var shown_on: bool = pad.visible
	check("the pad goes on the HUD as its first child - every bar, button and window there is over it and takes a touch first",
		first and _func_body(_code_src("res://src/ui/characterhud.gd"), "func _ready(").contains("TouchControls.attach(self)"))
	check("  shown while the touch screen is in use, and not otherwise", hidden_off and shown_on, [hidden_off, shown_on])
	var outside: Array = []
	for id in ["attack", "use", "run"]:
		var socket_button: Control = pad.get(id)
		var inside: Rect2 = (socket_button.get("box") as Rect2).grow(-float(socket_button.get("pixel")) * PadScript.SOCKET_FRAME)
		var drawn_at: Rect2 = socket_button.call("icon_rect")
		if socket_button.get("picture") != null and not inside.encloses(drawn_at):
			outside.append([id, drawn_at, inside])
	check_needs_pack("  each icon sits inside its socket's frame", outside.is_empty(), outside)
	var attack_button: Control = pad.get("attack")
	var thumb := InputEventScreenTouch.new()
	thumb.index = 1
	thumb.pressed = true
	thumb.position = attack_button.size / 2.0
	attack_button.call("_gui_input", thumb)
	var stick_part: Control = pad.get("stick")
	var left_thumb := InputEventScreenTouch.new()
	left_thumb.index = 0
	left_thumb.pressed = true
	left_thumb.position = Vector2(200, 300)
	stick_part.call("_gui_input", left_thumb)
	var landed_still: bool = (TouchControls.stick_held and TouchControls.stick == Vector2.ZERO
		and (stick_part.get("base") as Vector2) == Vector2(200, 300))
	var slide := InputEventScreenDrag.new()
	slide.index = 0
	slide.position = Vector2(200 + float(stick_part.get("radius")) * 3.0, 300)
	stick_part.call("_gui_input", slide)
	var both: bool = TouchControls.attack_held and TouchControls.stick_held and TouchControls.stick.is_equal_approx(Vector2(1, 0))
	var followed: bool = (stick_part.get("base") as Vector2).x > 200.0
	var other_finger := InputEventScreenTouch.new()
	other_finger.index = 5
	other_finger.pressed = false
	attack_button.call("_gui_input", other_finger)
	var still_held: bool = TouchControls.attack_held
	thumb.pressed = false
	attack_button.call("_gui_input", thumb)
	left_thumb.pressed = false
	stick_part.call("_gui_input", left_thumb)
	check("two thumbs are two presses: the stick held right while Attack is down, each by its own finger",
		both and still_held, [TouchControls.attack_held, TouchControls.stick_held, TouchControls.stick])
	check("  the stick comes to exactly where the thumb lands - a touch alone walks nowhere", landed_still)
	check("  the stick follows a thumb that slides past its rim", followed)
	check("  and lifting each lets go of each", not TouchControls.attack_held and not TouchControls.stick_held
		and TouchControls.stick == Vector2.ZERO)
	check("  the first finger's copied mouse is the pad's too, kept from the world (accept_event())",
		_func_body(_code_src("res://src/ui/touchpad.gd"), "func _gui_input(").contains("event is InputEventMouseButton or event is InputEventMouseMotion"))
	TouchControls.press_attack()
	hud.queue_free()
	await get_tree().process_frame
	check("  the pad gone with its HUD, every thumb is up", not TouchControls.attack_held)
	TouchControls.set_active(false)

	# ---- the Controls card tells the thumbs ---------------------------------------
	TouchControls.set_active(true)
	var card: ControlsPanel = (load("res://scene/ui/controls/controlspanel.tscn") as PackedScene).instantiate() as ControlsPanel
	add_child(card)
	card.open_controls()
	var touch_rows: int = int(card.key_grid.get_child_count() / 2.0)
	var first_how: String = (card.key_grid.get_child(1) as Label).text
	var touch_footer: String = card.footer_label.text if card.footer_label != null else ""
	var no_rebinding: bool = card.keys_row == null or not card.keys_row.visible
	TouchControls.set_active(false)
	card.open_controls()
	var key_rows: int = int(card.key_grid.get_child_count() / 2.0)
	check("on a touch screen the Controls card says what the thumbs do - the stick, Run, Attack, Use, a tap on a key - not keys",
		touch_rows == ControlsPanel.TOUCH_ROWS.size() and first_how == ControlsPanel.TOUCH_ROWS[0][1]
		and touch_footer == ControlsPanel.TOUCH_FOOTER and no_rebinding, [touch_rows, first_how, touch_footer])
	check("  and with the keyboard, the keys again", key_rows == ControlsPanel.ROWS.size(), key_rows)
	card.queue_free()
	await get_tree().process_frame

	# ---- the page -------------------------------------------------------------------
	var presets: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	var shell: String = FileAccess.get_file_as_string("res://web/shell.html")
	check("a phone's own keyboard comes up for the login and the chat (html/experimental_virtual_keyboard)",
		presets.contains("html/experimental_virtual_keyboard=true"))
	check("  the page asks for the phone sideways while it is upright, with a way past it for a tablet",
		shell.contains("id=\"turn\"") and shell.contains("(orientation: portrait) and (pointer: coarse)") and shell.contains("id=\"turn-anyway\""))
	check("  and offers the whole screen where the browser has one to give, holding it sideways there",
		shell.contains("id=\"fullscreen\"") and shell.contains("requestFullscreen") and shell.contains("screen.orientation.lock('landscape')"))
	check("  and keeps the browser's own gestures - pull to refresh, the long-press menu - off the game",
		shell.contains("overscroll-behavior: none") and shell.contains("-webkit-touch-callout: none"))
	PlayerScript.pointer_on_game = kept_pointer

func _test_a_phone_saves_its_battery() -> void:
	section("A PHONE'S BATTERY - brightness, the battery saver, and a phone drawn at what it needs (0.54.0)")
	# The owner: "i also need to add a brightness setting in options to reduce
	# charge on battery also need to make sure the game runs smooth on any
	# phone".
	const SettingsScript := preload("res://src/systems/settings.gd")
	# ---- the frame cap --------------------------------------------------------------
	var caps: Array = [
		SettingsScript.fps_cap_for(0, true, true, 0.0, false, true),
		SettingsScript.fps_cap_for(0, true, true, 0.0, true, false),
		SettingsScript.fps_cap_for(144, true, true, 0.0, true, false),
		SettingsScript.fps_cap_for(20, true, true, 0.0, true, false),
		SettingsScript.fps_cap_for(0, true, true, 0.0, true, true),
		SettingsScript.fps_cap_for(0, false, true, 0.0, false, true),
		SettingsScript.fps_cap_for(0, true, true, 0.0, false, false),
	]
	check("a phone with no cap draws %d a second - a 120 Hz phone does not draw every frame twice" % SettingsScript.PHONE_FPS,
		caps[0] == SettingsScript.PHONE_FPS, caps)
	check("  the battery saver: %d, below any cap above it and never raising one below it, phone or not" % SettingsScript.SAVER_FPS,
		caps[1] == SettingsScript.SAVER_FPS and caps[2] == SettingsScript.SAVER_FPS and caps[3] == 20
		and caps[4] == SettingsScript.SAVER_FPS, caps)
	check("  in the background still the background's, and a laptop's no cap is still none",
		caps[5] == SettingsScript.BACKGROUND_FPS and caps[6] == 0, caps)
	check("  and the cap the engine gets is asked with both (_apply_fps_cap())",
		_func_body(_code_src("res://src/systems/settings.gd"), "func _apply_fps_cap(").contains("bool(get_value(\"battery_saver\")), on_phone()")
		and Settings.DEFAULTS.get("battery_saver") == false)

	# ---- brightness ---------------------------------------------------------------
	var kept_brightness: float = float(Settings.get_value("brightness"))
	Settings.set_value("brightness", 0.5)
	var veil: ColorRect = Settings.get("_dimmer") as ColorRect
	var dimmed: bool = (veil != null and is_equal_approx(veil.color.a, 0.5) and veil.color.r == 0.0
		and (veil.get_parent() as CanvasLayer).visible and (veil.get_parent() as CanvasLayer).layer == SettingsScript.DIMMER_LAYER)
	var lets_through: bool = veil != null and veil.mouse_filter == Control.MOUSE_FILTER_IGNORE
	Settings.set_value("brightness", 0.1)
	var floor_held: bool = is_equal_approx(float(Settings.get_value("brightness")), SettingsScript.BRIGHTNESS_MIN)
	Settings.set_value("brightness", 1.0)
	var gone_at_full: bool = veil != null and not (veil.get_parent() as CanvasLayer).visible
	Settings.set_value("brightness", kept_brightness)
	check("brightness lays a dark veil over everything the game draws - half dark at 50%, over the scene fades too",
		dimmed and SettingsScript.DIMMER_LAYER > 100 and SettingsScript.DIMMER_LAYER < 128, [dimmed, veil])
	check("  it never takes a touch or a click", lets_through)
	check("  no darker than %d%%, and at full it is gone - nothing drawn, nothing paid" % roundi(SettingsScript.BRIGHTNESS_MIN * 100.0),
		floor_held and gone_at_full and Settings.DEFAULTS.get("brightness") == 1.0, [floor_held, gone_at_full])
	var options: Node = (load("res://scene/ui/menus/optionsscreen.tscn") as PackedScene).instantiate()
	add_child(options)
	var slider: HSlider = options.get_node_or_null("%brightness") as HSlider
	var saver: CheckButton = options.get_node_or_null("%batterysaver") as CheckButton
	check("  Options has both: a Brightness slider over the setting's own range, and a Battery saver switch",
		slider != null and saver != null and is_equal_approx(slider.min_value, SettingsScript.BRIGHTNESS_MIN)
		and is_equal_approx(slider.max_value, SettingsScript.BRIGHTNESS_MAX)
		and _func_body(_code_src("res://src/ui/menus/optionsscreen.gd"), "func _connect_controls(").contains("brightness.min_value = Settings.BRIGHTNESS_MIN"),
		[slider, saver])
	options.queue_free()
	await get_tree().process_frame

	# ---- a phone's own defaults, once ------------------------------------------------
	var first: Dictionary = SettingsScript.phone_changes(true, 0)
	check("a phone's first launch draws at the game's own size and lifts the dark rather than lighting every candle",
		first.get("render_resolution") == "low" and first.get("lighting") == "simple", first)
	check("  and since 0.55.0 turns the battery saver on - half the frames, half the heat",
		first.get("battery_saver") == true and first == SettingsScript.PHONE_DEFAULTS, first)
	check("  a step at a time: a phone tuned by 0.54.0 (which wrote true) is given only the battery saver",
		SettingsScript.phone_changes(true, SettingsScript.phone_steps_stored(true)) == {"battery_saver": true}
		and SettingsScript.phone_steps_stored(false) == 0 and SettingsScript.phone_steps_stored(2) == 2,
		SettingsScript.phone_changes(true, 1))
	check("  once: a phone that has taken every step, or a laptop, is left as it is - a player who sets one back keeps it",
		SettingsScript.phone_changes(true, SettingsScript.PHONE_STEPS.size()).is_empty() and SettingsScript.phone_changes(false, 0).is_empty())
	check("  and the file remembers how many it took, beside the settings (save_settings())",
		_func_body(_code_src("res://src/systems/settings.gd"), "func save_settings(").contains("PHONE_TUNED_KEY, _phone_steps")
		and _func_body(_code_src("res://src/systems/settings.gd"), "func load_settings(").contains("phone_changes(on_phone(), _phone_steps)"))
	check("  a phone is the browser on Android or iOS (Godot's web_android and web_ios)",
		_func_body(_code_src("res://src/systems/settings.gd"), "static func on_phone(").contains("web_android")
		and _func_body(_code_src("res://src/systems/settings.gd"), "static func on_phone(").contains("web_ios"))
	var shell: String = FileAccess.get_file_as_string("res://web/shell.html")
	var capped_at: int = shell.find("Object.defineProperty(window, 'devicePixelRatio'")
	check("the page draws a phone at most two pixels to a CSS pixel, set before the engine loads",
		capped_at > 0 and capped_at < shell.find("<script src=\"$GODOT_URL\"></script>") and shell.contains("const MOST = 2;")
		and shell.contains("'(pointer: coarse)'"))


# =============================================================================
# A FINGER HELD ON AN ITEM, AND A HOTBAR FOR THUMBS (0.55.0)
# =============================================================================
# The owner, on a phone: "looted a mage pet but is not deploying", and
# "hotbar icons are a bit small". Everything in a bag was used with the right
# button, which a phone does not have, so a finger held still on a cell is that
# click now (inventoryslot.gd). And while the touch screen is in use the bar is
# drawn at the pad's scale (hotbar.gd fit_to_thumbs()).

func _test_a_finger_held_uses_an_item() -> void:
	section("A FINGER HELD ON AN ITEM - the right-click a phone does not have (0.55.0)")
	var pet: ItemData = ItemRegistry.get_item("petmage")
	check("the mage pet the owner looted is in the game, and it summons a scene",
		pet != null and int(pet.type) == int(ItemData.Type.PET) and PetController.pet_scene_for("petmage") != null)
	if pet == null:
		return
	var long_enough: float = InventorySlot.HOLD_SEC + 0.15
	var spot := Vector2(10, 10)

	# ---- one cell ---------------------------------------------------------------------
	var slot: InventorySlot = (load("res://scene/ui/inventory/inventoryslot.tscn") as PackedScene).instantiate()
	add_child(slot)
	await get_tree().process_frame
	slot.set_stack(ItemStack.new(pet, 1))
	var used: Array = []
	var taken: Array = []
	slot.slot_right_clicked.connect(func(s: InventorySlot): used.append(s))
	slot.slot_double_clicked.connect(func(s: InventorySlot): taken.append(s))
	_finger_on(slot, spot, true)
	await get_tree().create_timer(long_enough).timeout
	var while_down: int = used.size()
	_finger_on(slot, spot, false)
	check("a finger held still on a cell is a right-click on it: once, while the finger is still down",
		while_down == 1 and used.size() == 1 and taken.is_empty(), [while_down, used.size(), taken.size()])
	_finger_on(slot, spot, true)
	await get_tree().create_timer(0.1).timeout
	_finger_on(slot, spot, false)
	await get_tree().create_timer(long_enough).timeout
	check("  a tap is not - that is still the tooltip", used.size() == 1, used.size())
	_finger_on(slot, spot, true)
	var slide := InputEventScreenDrag.new()
	slide.index = 0
	slide.position = spot + Vector2(InventorySlot.HOLD_SLIDE + 6.0, 0)
	slot.call("_gui_input", slide)
	await get_tree().create_timer(long_enough).timeout
	_finger_on(slot, slide.position, false)
	check("  nor a finger that slides - that is the drag that moves the item", used.size() == 1, used.size())
	_finger_on(slot, spot, true)
	await get_tree().create_timer(InventorySlot.HOLD_SEC * 0.6).timeout
	_finger_on(slot, spot, false)
	_finger_on(slot, spot, true)
	await get_tree().create_timer(InventorySlot.HOLD_SEC * 0.6).timeout
	var too_soon: int = used.size()
	await get_tree().create_timer(long_enough).timeout
	_finger_on(slot, spot, false)
	check("  lifted and put down again, only the second hold counts, timed from when it began",
		too_soon == 1 and used.size() == 2, [too_soon, used.size()])
	slot.clear_stack()
	_finger_on(slot, spot, true)
	await get_tree().create_timer(long_enough).timeout
	_finger_on(slot, spot, false)
	check("  an empty cell does nothing", used.size() == 2, used.size())
	slot.set_stack(ItemStack.new(pet, 1))
	slot.slot_type = InventorySlot.LOOT_SLOT_TYPE
	_finger_on(slot, spot, true)
	await get_tree().create_timer(long_enough).timeout
	_finger_on(slot, spot, false)
	slot.slot_type = InventorySlot.BANK_SLOT_TYPE
	_finger_on(slot, spot, true)
	await get_tree().create_timer(long_enough).timeout
	_finger_on(slot, spot, false)
	check("  in a loot bag or the bank it is the double-click that takes the item, as the mouse does there",
		taken.size() == 2 and used.size() == 2, [taken.size(), used.size()])
	# THE BAG BESIDE AN OPEN BANK (0.56.2): there the double-click is the
	# deposit, and the hold drank the potion instead.
	var bag_grid := InventoryContainer.new()
	add_child(bag_grid)
	slot.slot_type = "inventory"
	slot.home_container = bag_grid
	bag_grid.held_is_double_click = true
	_finger_on(slot, spot, true)
	await get_tree().create_timer(long_enough).timeout
	_finger_on(slot, spot, false)
	var deposited: bool = taken.size() == 3 and used.size() == 2
	bag_grid.held_is_double_click = false
	_finger_on(slot, spot, true)
	await get_tree().create_timer(long_enough).timeout
	_finger_on(slot, spot, false)
	check("  in the bag while the bank is open it is the double-click that deposits, and the right-click again once it shuts",
		deposited and taken.size() == 3 and used.size() == 3, [taken.size(), used.size()])
	var wiring: String = _func_body(_code_src("res://src/ui/bank/bankinventory.gd"), "func _wire_carry_container(")
	check("    the bank turns that on as it opens and off as it shuts, with the deposit's own double-click",
		wiring.contains("carry.set(\"held_is_double_click\", connected)")
		and wiring.find("held_is_double_click") < wiring.find("if connected:"))
	slot.home_container = null
	bag_grid.queue_free()
	slot.queue_free()

	# ---- a hotbar key and a piece of gear ------------------------------------------------
	var bar: Hotbar = (load("res://scene/ui/hotbar.tscn") as PackedScene).instantiate() as Hotbar
	add_child(bar)
	await get_tree().process_frame
	var key: HotbarSlot = bar.slots[0]
	key.set_stack(ItemStack.new(pet, 1))
	var key_used: Array = []
	key.slot_right_clicked.connect(func(s: InventorySlot): key_used.append(s))
	_finger_on(key, spot, true)
	await get_tree().create_timer(long_enough).timeout
	_finger_on(key, spot, false)
	check("  not on a hotbar key, which a tap uses already - held, it would be used twice",
		not key.holds_to_use and key_used.is_empty(), key_used.size())
	bar.queue_free()
	var panel: Control = (load("res://scene/ui/equipment/equipmentpanel.tscn") as PackedScene).instantiate() as Control
	add_child(panel)
	# Open, as it is when a finger is on it: a hold on a hidden window is nothing.
	panel.visible = true
	await get_tree().process_frame
	var pieces: Array = []
	_collect_by_script(panel, "res://src/ui/equipment/equipmentslot.gd", pieces)
	var off: Array = []
	if not pieces.is_empty():
		var piece: InventorySlot = pieces[0]
		piece.set_stack(ItemStack.new(pet, 1))
		piece.slot_right_clicked.connect(func(s: InventorySlot): off.append(s))
		_finger_on(piece, spot, true)
		await get_tree().create_timer(long_enough).timeout
		_finger_on(piece, spot, false)
	check("  and on the gear doll it is the right-click that takes a piece off", off.size() == 1, [pieces.size(), off.size()])
	panel.queue_free()

	# ---- the owner's pet, from the bag --------------------------------------------------------
	var screen: Control = (load("res://scene/ui/inventory/inventory.tscn") as PackedScene).instantiate()
	add_child(screen)
	await get_tree().process_frame
	var stand_script := GDScript.new()
	stand_script.source_code = "extends Node2D\nvar level: int = 1\nvar active_pet_id: String = \"\"\nvar asked: Array = []\n" \
		+ "func summon_pet(id: String) -> bool:\n\tasked.append(id)\n\tactive_pet_id = id\n\treturn true\n" \
		+ "func dismiss_pet() -> void:\n\tasked.append(\"away\")\n\tactive_pet_id = \"\"\n"
	stand_script.reload()
	var stand := Node2D.new()
	stand.set_script(stand_script)
	add_child(stand)
	screen.set_player(stand)
	var cell: InventorySlot = screen.get_node("%inventorycontainer").get_slot_at(0)
	cell.set_stack(ItemStack.new(pet, 1))
	for _i in 2:
		_finger_on(cell, spot, true)
		await get_tree().create_timer(long_enough).timeout
		_finger_on(cell, spot, false)
	check("in the bag, a hold on the mage pet brings it out and a second puts it away",
		stand.get("asked") == ["petmage", "away"], stand.get("asked"))
	screen.queue_free()
	stand.queue_free()

	# ---- and it says so --------------------------------------------------------------------
	check("the pet's tooltip says hold on a touch screen, and right-click with a mouse",
		ItemTooltip.use_line(pet, true) == ItemTooltip.PET_USE_LINE_TOUCH and ItemTooltip.PET_USE_LINE_TOUCH.begins_with("Hold")
		and ItemTooltip.use_line(pet) == ItemTooltip.PET_USE_LINE)
	var tip: Control = (load("res://scene/ui/inventory/itemtooltip.tscn") as PackedScene).instantiate()
	add_child(tip)
	await get_tree().process_frame
	TouchControls.set_active(true)
	tip.show_for_stack(ItemStack.new(pet, 1), null)
	var touch_words: String = tip.description_label.text
	TouchControls.set_active(false)
	tip.show_for_stack(ItemStack.new(pet, 1), null)
	var mouse_words: String = tip.description_label.text
	check("  and the tooltip over it is the one for the screen in use",
		touch_words.contains(ItemTooltip.PET_USE_LINE_TOUCH) and mouse_words.contains(ItemTooltip.PET_USE_LINE),
		[touch_words, mouse_words])
	tip.queue_free()
	var hows: Array = ControlsPanel.TOUCH_ROWS.map(func(row: Array) -> String: return row[1])
	check("  as does the Controls card on a touch screen: hold it in the bag, in Gear, in a loot bag",
		hows.has("Hold it in your bag") and hows.has("Hold it in Gear") and hows.has("Hold it, or tap Take all"), hows)
	await get_tree().process_frame


func _test_the_hotbar_grows_for_thumbs() -> void:
	section("THE HOTBAR FOR THUMBS - drawn at the pad's scale on a touch screen (0.55.0)")
	const PadScript := preload("res://src/ui/touchpad.gd")
	check("as big under a thumb as on a laptop: one on a laptop, the pad's 1.85 on a phone held sideways, never past %.2f" % Hotbar.TOUCH_MOST_SCALE,
		is_equal_approx(Hotbar.touch_scale(Vector2(1280, 720), Vector2(1280, 720), 1.0), 1.0)
		and absf(Hotbar.touch_scale(Vector2(2532, 1170), Vector2(1280, 720), 3.0) - 1.846) < 0.01
		and is_equal_approx(Hotbar.touch_scale(Vector2(600, 300), Vector2(1280, 720), 3.0), Hotbar.TOUCH_MOST_SCALE),
		Hotbar.touch_scale(Vector2(2532, 1170), Vector2(1280, 720), 3.0))
	var hud_path := "res://scene/ui/characterhud.tscn"
	var right: float = 1280.0 + float(_node_prop_in_scene(hud_path, "hotbar", "offset_right"))
	var width: float = float(_node_prop_in_scene(hud_path, "hotbar", "offset_right")) - float(_node_prop_in_scene(hud_path, "hotbar", "offset_left"))
	var bottom: float = 720.0 + float(_node_prop_in_scene(hud_path, "hotbar", "offset_bottom"))
	var height: float = float(_node_prop_in_scene(hud_path, "hotbar", "offset_bottom")) - float(_node_prop_in_scene(hud_path, "hotbar", "offset_top"))
	var left_end: float = right - width * Hotbar.TOUCH_MOST_SCALE
	check("  at its biggest its left end is still clear of the stick's part of the screen",
		width > 0.0 and left_end >= 1280.0 * PadScript.STICK_ZONE_WIDTH, [left_end, 1280.0 * PadScript.STICK_ZONE_WIDTH])
	var over: Array = []
	for f in [1.0, 1.4, 1.85, 2.4]:
		var top: float = bottom - height * minf(f, Hotbar.TOUCH_MOST_SCALE)
		var at: Dictionary = PadScript.layout(Vector2(1280, 720), f, top, 672.0, true)
		for id in ["attack", "use", "skill"]:
			var socket: Rect2 = at[id]
			var reach: Rect2 = socket.grow(socket.size.x * (PadScript.REACH - 1.0) / 2.0)
			if reach.end.y > top or reach.position.y < 0.0:
				over.append([f, id, reach, top])
	check("  and the pad's buttons stand on the grown bar at every size, still on the screen", over.is_empty(), over)

	var hud := Control.new()
	hud.size = Vector2(1280, 720)
	add_child(hud)
	var bar: Hotbar = (load("res://scene/ui/hotbar.tscn") as PackedScene).instantiate() as Hotbar
	hud.add_child(bar)
	bar.position = Vector2(right - width, bottom - height)
	bar.size = Vector2(width, height)
	TouchControls.set_active(false)
	# AS A PHONE: two pixels to a CSS pixel. A headless window is the game's
	# own size at one to one, where the bar would not grow at all.
	Hotbar.pixel_ratio_for_test = 2.0
	# Laid out with a mouse in use, against the bar at its own size.
	var pad: Control = TouchControls.attach(hud)
	await get_tree().process_frame
	var resting: Rect2 = bar.get_global_rect()
	# As if it had looked a moment ago: its next look is half a second off.
	pad.set("_look_left", 0.5)
	TouchControls.set_active(true)
	var window: Window = get_window()
	var drawn_at: Vector2 = Vector2(window.content_scale_size) if window.content_scale_size != Vector2i.ZERO else get_viewport().get_visible_rect().size
	var want: float = Hotbar.touch_scale(Vector2(window.size), drawn_at, 2.0)
	var grown: Rect2 = bar.get_global_rect()
	check("  while the touch screen is in use the bar is that size, grown up and left from its bottom right corner",
		want > 1.2 and is_equal_approx(bar.scale.x, want) and is_equal_approx(bar.scale.y, want) and grown.end.is_equal_approx(resting.end)
		and is_equal_approx(grown.size.y, resting.size.y * want), [want, bar.scale, resting, grown])
	# FIVE KEYS UNDER A THUMB (0.91.0): 1 to 5 shown, the bar as wide as they are.
	var shown_keys: int = bar.slots.filter(func(key: Control) -> bool: return key.visible).size()
	check("  and it shows keys 1 to 5 only, narrowed to them from its right edge (0.91.0)",
		shown_keys == Hotbar.TOUCH_KEYS and bar.slots[0].visible and not bar.slots[Hotbar.TOUCH_KEYS].visible
		and grown.size.x < resting.size.x * want * 0.6, [shown_keys, grown.size.x, resting.size.x * want])
	pad._process(0.0)
	var attack_rect: Rect2 = (pad.get("attack") as Control).get_global_rect()
	check("  and the pad lays out over it the frame it appears - Attack stands on its top",
		attack_rect.end.y <= grown.position.y + 0.5, [attack_rect, grown])
	TouchControls.set_active(false)
	Hotbar.pixel_ratio_for_test = 0.0
	check("  back to its own size with a mouse or the keys, all ten keys again",
		bar.scale == Vector2.ONE and bar.get_global_rect().is_equal_approx(resting)
		and bar.slots.all(func(key: Control) -> bool: return key.visible), [bar.scale, bar.get_global_rect()])
	hud.queue_free()
	await get_tree().process_frame
	var shell: String = FileAccess.get_file_as_string("res://web/shell.html")
	var button_at: int = shell.find("<button id=\"fullscreen\"")
	var button_html: String = shell.substr(button_at, shell.find("</button>", button_at) - button_at)
	check("the page's Full screen button is a square in the corner - no words to reach over the Bag's close button",
		button_at > 0 and button_html.contains("aria-label=\"Full screen\"") and not button_html.contains("\tFull screen")
		and shell.contains("width: 34px;"), button_html)


# =============================================================================
# A PHONE KEPT COOL, A SCREEN KEPT UNBURNT, AND PROJECTILES AS BRIGHT AS ASKED (0.55.0)
# =============================================================================
# The owner: "major things i want to avoid phone over heating and a image
# burned on the screen we need a slider for bullet projectile brightness and
# make the game super user friendly on the tutorial screen i think we should
# mention to players it would be a good idea to adjust options".
