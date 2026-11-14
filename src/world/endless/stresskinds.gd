extends Node
# stresskinds.gd - Find the limit's shots and effects (0.154.0). The owner:
# "now that we have the spreadsheet it is time to do the math and figure out
# exactly how many enemies i can have for phone and pc but we also have not
# measured effects or projectile yet".
#
# limitsweep.gd sweeps a monster by bringing more of it. Every shot and Every
# effect are swept the same way, with two kinds of "more":
# - A SHOT (shots()): more of it in the air round you. A monster's own shot
#   flies slowly away from you and is made to last (`lifetime`), so the count
#   holds while it is measured and none reaches you; an orb is the bullet
#   field's. ms each is a shot in the air; fits is how many in the air.
# - AN EFFECT (effects()): more of it a second. Another player's attack as
#   your screen draws it (remoteattacks.gd), a blow's sparks, a cast sparkle,
#   a hit with its number on one of CROWD monsters already after you, and a
#   death with the monster made in its place. ms each is one a second; fits is
#   how many a second.
# While an effect is swept this node is the sweep's child: it fires the rate
# (begin(), set_rate()) and keeps the crowd a hit or a death needs. A shot it
# makes is in GROUP, so clear() - which the ground's Clear all calls - takes
# every one away.

const GmSpawner := preload("res://src/world/gmspawner.gd")
const StrikeFx := preload("res://src/shared/strikefx.gd")
const GROUP := &"stress_shot"
const P := "res://scene/projectiles/"
# The crowd a hit or a death is done to: the plain archer, a monster of the
# middle of the sheet.
const CROWD_PATH := "res://scene/enemy/bushsniper.tscn"
const CROWD := 40
const MADE_AWAY := Vector2(360.0, -140.0)
const TOUGH := 1000000
# How slowly a monster's shot flies and how long it lasts while it is held.
const HELD_SPEED := 6.0
const HELD_LIFE := 120.0
# Where a shot or an effect is made: on screen (the widest view is 640 x 360)
# and never within NEAR px of you.
const SPREAD := Vector2(300.0, 170.0)
const NEAR := 60.0
const SHOT_STEP := 100
const SHOT_MOST := 4000
const ORB_STEP := 500
const ORB_MOST := 12000
const RATE_STEP := 10
const RATE_MOST := 400

var target: Dictionary = {}
var rate: float = 0.0
var me: Node2D = null
var _owed: float = 0.0
var _rng := RandomNumberGenerator.new()


static func shots() -> Array:
	"""Every shot, in the sweep's order."""
	var out: Array = []
	for pair in [["Bush sniper arrow", "arrow"], ["Ice arrow (an element's)", "icearrow"],
			["Small slime arrow", "poisonarrow"], ["Large slime acid ball", "poisonball"],
			["Fire sprite orb", "fireprojectile"], ["Electric sprite orb", "magicprojectile"]]:
		out.append({"label": "Shot: " + str(pair[0]), "shot": P + str(pair[1]) + ".tscn", "kind": -2,
			"step": SHOT_STEP, "most": SHOT_MOST})
	out.append({"label": "Shot: bullet orb", "orb": true, "big": false, "kind": -2, "step": ORB_STEP, "most": ORB_MOST})
	out.append({"label": "Shot: big bullet orb", "orb": true, "big": true, "kind": -2, "step": ORB_STEP, "most": ORB_MOST})
	return out


static func effects() -> Array:
	"""Every effect, in the sweep's order."""
	var out: Array = []
	for pair in [["warrior wave", "slash"], ["warrior axe", "axe"], ["mage spike", "stalag"],
			["mage meteor", "meteor"], ["tank dynamite", "dyn"], ["healer orb", "orb"], ["healer heal", "heal"]]:
		out.append({"label": "Effect: party %s" % str(pair[0]), "rate": str(pair[1]), "kind": -3,
			"step": RATE_STEP, "most": RATE_MOST})
	out.append({"label": "Effect: blow sparks", "rate": "sparks", "kind": -3, "step": RATE_STEP * 3, "most": RATE_MOST * 3})
	out.append({"label": "Effect: cast sparkle", "rate": "cast", "kind": -3, "step": RATE_STEP, "most": RATE_MOST})
	out.append({"label": "Effect: hit and its number", "rate": "hit", "kind": -3, "step": RATE_STEP * 3,
		"most": RATE_MOST * 3})
	out.append({"label": "Effect: death and a new monster", "rate": "death", "kind": -3, "step": 2, "most": CROWD})
	return out


static func is_shot(swept: Dictionary) -> bool:
	return swept.has("shot") or bool(swept.get("orb", false))


static func is_rate(swept: Dictionary) -> bool:
	return swept.has("rate")


static func spot(rng: RandomNumberGenerator, around: Vector2) -> Vector2:
	for _try in 20:
		var off := Vector2(rng.randf_range(-SPREAD.x, SPREAD.x), rng.randf_range(-SPREAD.y, SPREAD.y))
		if off.length() > NEAR:
			return around + off
	return around + Vector2(NEAR * 2.0, 0.0)


static func make_shots(tree: SceneTree, swept: Dictionary, count: int, around: Vector2,
		rng: RandomNumberGenerator) -> int:
	"""`count` more of a shot round `around`, each flying slowly away from it."""
	if tree == null or tree.current_scene == null:
		return 0
	if bool(swept.get("orb", false)):
		var zone: BulletZone = tree.get_first_node_in_group(BulletZone.GROUP) as BulletZone
		if zone == null or zone.field == null:
			return 0
		var room: int = mini(count, zone.field.capacity - zone.field.count)
		for _n in room:
			var at: Vector2 = spot(rng, around)
			zone.field.spawn(at, (at - around).angle(), HELD_SPEED, Color(0.6, 0.9, 1.0),
				bool(swept.get("big", false)), 0.0, 0.0, HELD_LIFE, 0, 0)
		return maxi(0, room)
	var packed: PackedScene = load(str(swept.get("shot", ""))) as PackedScene
	if packed == null:
		return 0
	var holder: Node = tree.get_first_node_in_group(&"projectiles")
	if holder == null:
		holder = tree.current_scene
	for _n in count:
		var shot := packed.instantiate() as Node2D
		shot.add_to_group(GROUP)
		if "lifetime" in shot:
			shot.set("lifetime", HELD_LIFE)
		if "damage" in shot:
			shot.set("damage", 0)
		if "speed" in shot:
			shot.set("speed", HELD_SPEED)
		holder.add_child(shot)
		var at: Vector2 = spot(rng, around)
		shot.global_position = at
		shot.reset_physics_interpolation()
		if shot.has_method("shoot_vector"):
			shot.call("shoot_vector", (at - around).normalized())
	return count


static func count_shots(tree: SceneTree, swept: Dictionary) -> int:
	if tree == null:
		return 0
	if bool(swept.get("orb", false)):
		var zone: BulletZone = tree.get_first_node_in_group(BulletZone.GROUP) as BulletZone
		return zone.field.count if zone != null and zone.field != null else 0
	var n: int = 0
	for shot in tree.get_nodes_in_group(GROUP):
		if not shot.is_queued_for_deletion():
			n += 1
	return n


static func clear(tree: SceneTree) -> int:
	"""Every shot made here, gone. How many."""
	if tree == null:
		return 0
	var n: int = 0
	for shot in tree.get_nodes_in_group(GROUP):
		if not shot.is_queued_for_deletion():
			shot.queue_free()
			n += 1
	return n


# ---- an effect, a second ------------------------------------------------------------

func begin(swept: Dictionary, player: Node2D) -> void:
	target = swept
	me = player
	rate = 0.0
	_owed = 0.0
	_rng.seed = 154


func end() -> void:
	target = {}
	rate = 0.0
	_owed = 0.0


func set_rate(per_second: float) -> void:
	rate = maxf(0.0, per_second)


func _crowd() -> Array:
	var out: Array = []
	for m in get_tree().get_nodes_in_group(GmSpawner.GROUP):
		if not m.is_queued_for_deletion() and str(m.scene_file_path) == CROWD_PATH and int(m.get("hp")) > 0:
			out.append(m)
	return out


func needs_crowd() -> bool:
	var what: String = str(target.get("rate", ""))
	return what == "hit" or what == "death"


func _process(_delta: float) -> void:
	# The crowd a hit or a death needs, kept at CROWD: a hit's tough, a
	# death's as they come.
	if not is_inside_tree() or me == null or not needs_crowd():
		return
	var crowd: Array = _crowd()
	if crowd.size() < CROWD:
		# Made away from the crowd and walked in, as a respawn or a wave is:
		# a spot inside the crowd took GmSpawner 5 to 13 ms a monster.
		GmSpawner.spawn(get_tree(), CROWD_PATH, CROWD - crowd.size(), me.global_position + MADE_AWAY)
	if str(target.get("rate", "")) == "hit":
		for m in crowd:
			if not m.has_meta(&"stress_tough"):
				m.set_meta(&"stress_tough", true)
				m.set("max_hp", TOUGH)
				m.set("hp", TOUGH)


func _physics_process(delta: float) -> void:
	if rate <= 0.0 or target.is_empty() or me == null or not is_instance_valid(me):
		return
	_owed += rate * delta
	while _owed >= 1.0:
		_owed -= 1.0
		_one()


func _one() -> void:
	var what: String = str(target.get("rate", ""))
	var at: Vector2 = spot(_rng, me.global_position)
	match what:
		"sparks":
			var holder: Node = get_tree().get_first_node_in_group(&"projectiles")
			StrikeFx.sparks(holder if holder != null else get_tree().current_scene, at, StrikeFx.STEEL)
		"cast":
			CastSparkle.burst(me, "down", at)
		"hit", "death":
			var crowd: Array = _crowd()
			if crowd.is_empty():
				return
			var m: Node = crowd[_rng.randi() % crowd.size()]
			if what == "hit":
				m.call("take_damage", 1, 0)
				m.set("hp", TOUGH)
			else:
				m.call("take_damage", int(m.get("hp")) + TOUGH, 0)
		_:
			var aim: Vector2 = at + (at - me.global_position).normalized() * 120.0
			RemoteAttacks.fire(me, [what, 0, at.x, at.y, aim.x, aim.y, 0, 0])
