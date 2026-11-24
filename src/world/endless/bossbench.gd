extends Node
# bossbench.gd - Find the limit's boss attacks (0.176.0). The owner: "we need
# to measure final boss and fix costs the attacks should be in testing area
# also everything needs to be measured and optimized".
#
# Two picks in Find the limit (limitsweep.gd):
# - EVERY BOSS ATTACK (attacks()): each of the Crowned's attacks on its own,
#   more and more of it, as Every effect does - its seven volleys and every
#   stalagmite shape a second; the floor's hazards (the meteor storm's
#   meteors among them) and three of its lasers a second; and held out at
#   once: the Trap's wheel, decoy eyes, each weather, the Sealing's lava (rings
#   of it), the Tear's holes, the rift past the floor and the Trap's horde.
# - THE CROWNED'S PHASES (phases()): the whole fight in each of its parts -
#   the crowns, the Sealing, the Trap, the Tear - with the Crowned itself
#   fighting you, alone and with three more players (pictures of a party that
#   it counts and fights, as a real party's). Two rows each: the empty field,
#   then the part; ms each is what the part costs.
#
# THE HOST: the Crowned's own fight (crownedfight.gd), made in the Testing
# Ground for each sweep on a floor the size of the Crowned's room in the
# middle of the arena, with its seven lights - so its lands (descentlands.gd:
# hazards, lasers, weather), its phases (crownedphases.gd: meteor storm, lava,
# wheel, horde, tears) and its rift make each attack with the code the fight
# makes it with. The volleys and shapes come from a hidden caster, the
# Crowned's own scene, as the Descent's are (descentlands.gd _make_caster()).
# The rift is hidden unless it is what is swept. Gone after each sweep (end()).
#
# No class_name: preload it by path.

const GmSpawner := preload("res://src/world/gmspawner.gd")
const FightScript := preload("res://src/world/crowned/crownedfight.gd")
const PhasesScript := preload("res://src/world/crowned/crownedphases.gd")
const RemotePlayerScript := preload("res://src/characters/remoteplayer.gd")
const BOSS_PATH := "res://scene/enemy/bossenemy.tscn"
const BOSS_ID := "bossenemy"
# The Crowned's room's floor (scene/boss.tscn) and its seven lights, from the
# floor's corner (buildcrowned.gd).
const ROOM_SIZE := Vector2(818, 704)
const LIGHT_SPOTS := [Vector2(42, 508), Vector2(42, 267), Vector2(135, 32), Vector2(409, 32),
	Vector2(683, 32), Vector2(776, 267), Vector2(776, 508)]
# Each volley in the land whose kit throws it (bossenemy.gd KITS), at its
# hardest phase.
const VOLLEY_LAND := {
	&"prism": Element.Type.LIGHT, &"gale": Element.Type.WIND, &"vortex": Element.Type.WIND,
	&"tide": Element.Type.WATER, &"frost": Element.Type.ICE, &"boulder": Element.Type.EARTH,
	&"pincer": Element.Type.FIRE,
}
const VOLLEY_PHASE := 2
const RINGS := [&"prism", &"vortex"]
const SHAPES := [&"lance", &"ring", &"arc", &"snare", &"sweep", &"cage", &"ladder", &"checker",
	&"gate", &"triwall", &"rake", &"cross", &"spiral", &"carpet"]
const HAZARDS := ["spark", "hail", "bubble", "gust", "flare", "rock", "wisp", "gas", "meteor"]
const LASERS := ["sweep", "cage", "pulse"]
# How hard the floor fights: the Crowned's (crownedfight.gd HAZARD_FLOOR).
const HAZARD_FLOOR := 4
# The rift as the Tear has it (crownedphases.gd enter()).
const RIFT_INTENSITY := 2.8
# The parts of the fight, each at a share of the Crowned's health inside it.
const PARTS := [["the crowns", 1.0], ["the Sealing", 0.7], ["the Trap", 0.45], ["the Tear", 0.2]]
const PARTY := 3
const PARTY_ID_FROM := -2000
const PARTY_NEAR := 70.0
# You are kept this far inside the host's floor, as the Crowned's walls keep
# you in its room: a gust or a shove would carry you out over the Testing
# Ground's wider floor, where its lasers start past their walls.
const HOLD_IN := 24.0
const KIND_ATTACK := -4
const KIND_PHASE := -5

var target: Dictionary = {}
var rate: float = 0.0
var me: Node2D = null
# Where the host is made: the Testing Ground's scene (the run's parent).
var world: Node = null
var host: Node2D = null
var caster: Node2D = null
var boss: Node2D = null
var party: Array = []
var wanted: int = 0
# The middle of the arena: the host's floor is round it.
var middle: Vector2 = Vector2.ZERO
var _owed: float = 0.0
var _rng := RandomNumberGenerator.new()


# ---- what is swept ----------------------------------------------------------------

static func attacks() -> Array:
	"""Every boss attack, in the sweep's order."""
	var out: Array = []
	for volley in VOLLEY_LAND:
		out.append(_entry("%s volley" % volley, "volley", String(volley), "a second", 2, 20))
	for shape in SHAPES:
		out.append(_entry("%s shape" % shape, "shape", String(shape), "a second", 2, 20))
	for kind in HAZARDS:
		out.append(_entry("floor %s" % kind, "hazard", kind, "a second", 5, 100))
	for shape in LASERS:
		out.append(_entry("%s laser" % shape, "laser", shape, "a second", 1, 20))
	out.append(_entry("the Trap's wheel", "wheel", "", "lit", 1, 1))
	out.append(_entry("decoy eyes", "decoys", "", "out", 3, 30))
	for land in FightScript.CROWN_ORDER:
		out.append(_entry("%s weather" % Element.name_for(int(land)), "weather", str(int(land)), "on", 1, 1))
	out.append(_entry("the Sealing's lava", "lava", "", "rings", 1, PhasesScript.LAVA_MOST))
	out.append(_entry("the Tear's holes", "holes", "", "open", 2, PhasesScript.TEAR_MOST))
	out.append(_entry("the rift", "rift", "", "on", 1, 1))
	out.append(_entry("the Trap's horde", "horde", "", "out", 50, 1000))
	return out


static func phases() -> Array:
	"""Every part of the Crowned's fight, alone and with a party of four."""
	var out: Array = []
	for part in PARTS:
		for others in [0, PARTY]:
			var entry: Dictionary = {"label": "Crowned: %s, %d player%s" % [str(part[0]), others + 1, "" if others == 0 else "s"],
				"boss": "phase", "what": str(part[0]), "share": float(part[1]), "party": others,
				"per": "on", "kind": KIND_PHASE, "step": 1, "most": 1}
			out.append(entry)
	return out


static func _entry(label: String, what: String, which: String, per: String, step: int, most: int) -> Dictionary:
	return {"label": "Boss: " + label, "boss": what, "what": which, "per": per, "kind": KIND_ATTACK,
		"step": step, "most": most}


static func is_boss(swept: Dictionary) -> bool:
	return swept.has("boss")


static func is_rate(swept: Dictionary) -> bool:
	"""Made so many a second; the rest are held out, so many at once."""
	return is_boss(swept) and str(swept.get("per", "")) == "a second"


# ---- a sweep --------------------------------------------------------------------------

func begin(swept: Dictionary, player: Node2D, in_world: Node, arena_middle: Vector2) -> void:
	"""Ready to sweep `swept`: the host made in `in_world`, its floor round
	`arena_middle`."""
	end()
	target = swept
	me = player
	world = in_world
	middle = arena_middle
	rate = 0.0
	_owed = 0.0
	wanted = 0
	_rng.seed = 176
	_make_host()
	if str(target.get("boss", "")) in ["volley", "shape", "decoys"]:
		_make_caster()


func end() -> void:
	"""Everything the sweep made, gone - the floor given back."""
	for picture in party:
		if is_instance_valid(picture):
			(picture as Node).queue_free()
	party = []
	if host != null and is_instance_valid(host):
		host.set("boss", null)
		for decoy in host.get("decoys"):
			if is_instance_valid(decoy):
				(decoy as Node).queue_free()
		host.set("decoys", [])
		host.call("_drop_ahead")
		var phases_node: Node = host.get("phases")
		if phases_node != null:
			phases_node.call("end")
			var lava: Node = phases_node.get("lava")
			if lava != null and is_instance_valid(lava):
				lava.queue_free()
		var lands: Node = host.get("lands")
		if lands != null:
			lands.call("end")
			lands.call("set_weathers", [], host.get("room_rect"))
		host.queue_free()
	host = null
	if caster != null and is_instance_valid(caster):
		caster.queue_free()
	caster = null
	if boss != null and is_instance_valid(boss):
		boss.queue_free()
	boss = null
	target = {}
	rate = 0.0
	wanted = 0


func room() -> Rect2:
	"""The host's floor: the Crowned's room's size, round the arena's middle."""
	return Rect2(middle - ROOM_SIZE / 2.0, ROOM_SIZE)


func _make_host() -> void:
	if world == null:
		return
	var floor_rect: Rect2 = room()
	host = FightScript.new()
	host.name = "benchcrowned"
	host.set("room_rect", floor_rect)
	var spots := PackedVector2Array()
	for spot in LIGHT_SPOTS:
		spots.append(floor_rect.position + (spot as Vector2))
	host.set("light_spots", spots)
	host.set("player_override", me)
	world.add_child(host)
	# Not a minigame of the Testing Ground's (the readout's Measure).
	host.remove_from_group(&"minigame_run")
	(host.get("lands") as Node).set("env_floor", HAZARD_FLOOR)
	_show_rift(false)


func _show_rift(on: bool) -> void:
	var layer: CanvasLayer = host.get_node_or_null("riftlayer") as CanvasLayer if host != null else null
	if layer != null:
		layer.visible = on
	var rift: Node = host.get("rift") if host != null else null
	if rift != null:
		rift.set("intensity", RIFT_INTENSITY if on else 1.0)
		# As with a hole open: no floor kept whole under it.
		rift.set("solid", Rect2())
		rift.set_process(on)


func _make_caster() -> void:
	"""THE CROWNED, HIDDEN, as the Descent's keepers are: its own scene, not
	drawn, not in "enemies", its brain and clocks stopped."""
	var lands: Node = host.get("lands") if host != null else null
	if lands == null:
		return
	caster = lands.call("_make_caster", BOSS_ID)
	if caster == null:
		return
	var land: int = Element.Type.DARK
	match str(target.get("boss", "")):
		"volley":
			land = int(VOLLEY_LAND.get(StringName(str(target.get("what", ""))), Element.Type.DARK))
		"shape":
			land = shape_land(StringName(str(target.get("what", ""))))
	caster.set("crown_land", land)
	caster.set("player", me)
	# In the middle of the floor, where the Crowned stands: its eyes are made
	# round it, and above the room (where the Descent keeps its keepers)
	# half of them found no floor.
	caster.global_position = room().get_center()
	caster.reset_physics_interpolation()


static func shape_land(shape: StringName) -> int:
	"""The first land in the crowns' order whose kit raises `shape`."""
	for land in FightScript.CROWN_ORDER:
		var kit: Dictionary = BossEnemy.KITS.get(int(land), {})
		if (kit.get("shapes", []) as Array).has(shape):
			return int(land)
	return Element.Type.DARK


func set_rate(per_second: float) -> void:
	rate = maxf(0.0, per_second)


func make(more: int) -> int:
	"""`more` of what is held out (or the part of the fight on); how many
	more there are now."""
	if host == null or more <= 0:
		return 0
	var before: int = count()
	var phases_node: Node2D = host.get("phases")
	match str(target.get("boss", "")):
		"wheel":
			wanted = 1
			phases_node.call("begin_wheel", me)
		"decoys":
			wanted += more
			_top_up_decoys()
		"weather":
			(host.get("lands") as Node).call("set_weathers", [int(str(target.get("what", "0")))], host.get("room_rect"))
		"lava":
			phases_node.set("phase", 2)
			phases_node.call("set_lava_depth", mini(PhasesScript.LAVA_MOST, int(phases_node.get("lava_depth")) + more))
		"holes":
			phases_node.set("phase", 4)
			_open_holes(more)
		"rift":
			_show_rift(true)
		"horde":
			if phases_node.get("swarm") == null:
				phases_node.call("_make_horde")
			var swarm: Node = phases_node.get("swarm")
			swarm.call("spawn", more, me.global_position if me != null else room().get_center())
		"phase":
			_start_part()
	return count() - before


func count() -> int:
	"""How many of what is swept are out now (a rate: how many a second)."""
	if is_rate(target):
		return int(rate)
	if host == null:
		return 0
	var phases_node: Node2D = host.get("phases")
	match str(target.get("boss", "")):
		"wheel":
			return 1 if float(phases_node.get("wheel_t")) >= 0.0 else 0
		"decoys":
			return _live_decoys().size()
		"weather":
			return 1 if not ((host.get("lands") as Node).get("_weathers") as Array).is_empty() else 0
		"lava":
			return int(phases_node.get("lava_depth"))
		"holes":
			var open: int = 0
			for piece in (phases_node.get("tears") as Dictionary).values():
				if bool((piece as Dictionary).get("open", false)):
					open += 1
			return open
		"rift":
			var layer: CanvasLayer = host.get_node_or_null("riftlayer") as CanvasLayer
			return 1 if layer != null and layer.visible else 0
		"horde":
			var swarm: Node = phases_node.get("swarm")
			return int(swarm.get("alive")) if swarm != null else 0
		"phase":
			# On from the moment it stands there: it turns on you the next frame.
			return 1 if boss != null and is_instance_valid(boss) and int(boss.get("hp")) > 0 else 0
	return 0


# ---- held out ----------------------------------------------------------------------

func _live_decoys() -> Array:
	return (host.get("decoys") as Array).filter(func(d: Object) -> bool:
		return is_instance_valid(d) and not bool(d.get("broken")))


func _top_up_decoys() -> void:
	"""As many eyes as asked for: one gone (DECOY_SECONDS) is made again."""
	if caster == null or not is_instance_valid(caster):
		return
	host.set("boss", caster)
	var live: Array = _live_decoys()
	host.set("decoys", live)
	var short: int = wanted - live.size()
	if short > 0:
		host.call("make_decoys", short)


func _open_holes(more: int) -> void:
	"""`more` pieces of the floor torn open at once, the rift under them."""
	var phases_node: Node2D = host.get("phases")
	var span: Rect2i = phases_node.call("_piece_span")
	var opened: int = 0
	for tries in 200:
		if opened >= more:
			break
		var piece := Vector2i(_rng.randi_range(0, span.size.x - 1), _rng.randi_range(0, span.size.y - 1))
		if not bool(phases_node.call("cut", piece)):
			continue
		var held: Dictionary = (phases_node.get("tears") as Dictionary)[piece]
		held["t"] = PhasesScript.TEAR_WARN + PhasesScript.TEAR_DROP
		held["open"] = true
		for cell in phases_node.call("_piece_lava_cells", piece):
			phases_node.call("_take", phases_node.call("_ground_cells", cell))
		opened += 1


func _keep_holes_open(delta: float) -> void:
	"""Open ones stay open (the clock that would knit them goes round), and
	are drawn as the Tear draws them."""
	var phases_node: Node2D = host.get("phases")
	var open_from: float = PhasesScript.TEAR_WARN + PhasesScript.TEAR_DROP
	var close_at: float = PhasesScript.TEAR_WARN + PhasesScript.TEAR_OPEN - 0.1
	for held in (phases_node.get("tears") as Dictionary).values():
		var t: float = float(held["t"]) + delta
		held["t"] = open_from if t >= close_at else t
	phases_node.call("redraw_floor")


func _start_part() -> void:
	"""The Crowned in the middle, fighting you at the part's share of its
	health - with a party of pictures when the part has one."""
	var at: Vector2 = middle
	if GmSpawner.spawn(get_tree(), BOSS_PATH, 1, at) <= 0:
		return
	for monster in get_tree().get_nodes_in_group(GmSpawner.GROUP):
		if str(monster.scene_file_path) == BOSS_PATH and not monster.is_queued_for_deletion() and monster != boss:
			boss = monster as Node2D
	host.set("boss", boss)
	for k in int(target.get("party", 0)):
		var picture: Node2D = RemotePlayerScript.new()
		var holder: Node = me.get_parent() if me != null and me.get_parent() != null else world
		holder.add_child(picture)
		picture.call("set_identity", {"id": PARTY_ID_FROM - k, "name": "Party %d" % (k + 2),
			"cls": ["warrior", "mage", "healer", "tank"][k % 4], "lvl": 22, "v": 2})
		var spot: Vector2 = (me.global_position if me != null else at) \
			+ Vector2.from_angle(TAU * float(k) / float(PARTY)) * PARTY_NEAR
		picture.call("place", spot)
		picture.global_position = spot
		picture.reset_physics_interpolation()
		picture.call("set_motion", "idledown", [], "")
		# A party's player the Crowned fights (Targets.all()); standing.
		picture.set("shares", true)
		picture.set_process(false)
		party.append(picture)


func _hold_part() -> void:
	"""The Crowned kept at the part's share of its health, after you."""
	if boss == null or not is_instance_valid(boss):
		return
	var want: int = int(float(boss.get("max_hp")) * float(target.get("share", 1.0)))
	if absi(int(boss.get("hp")) - want) > 1:
		boss.set("hp", want)
	if not bool(boss.get("engaged")) and me != null:
		boss.set("player", me)
		boss.set("engaged", true)


# ---- each frame ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if host == null or not is_instance_valid(host) or target.is_empty():
		return
	var what: String = str(target.get("boss", ""))
	# The fight steps its floor only while it fights: here, always.
	if what != "phase":
		(host.get("lands") as Node).call("step", delta)
	var phases_node: Node2D = host.get("phases")
	match what:
		"wheel":
			phases_node.call("_step_wheel", delta, me)
			if wanted > 0 and float(phases_node.get("wheel_t")) < 0.0:
				phases_node.call("begin_wheel", me)
		"decoys":
			_top_up_decoys()
		"lava":
			phases_node.set("phase_clock", float(phases_node.get("phase_clock")) + delta)
			phases_node.queue_redraw()
		"holes":
			_keep_holes_open(delta)
		"phase":
			_hold_part()


func _physics_process(delta: float) -> void:
	if target.is_empty() or host == null or me == null or not is_instance_valid(me):
		return
	_hold_inside()
	if rate <= 0.0:
		return
	_owed += rate * delta
	while _owed >= 1.0:
		_owed -= 1.0
		_one()


func _hold_inside() -> void:
	var inner: Rect2 = room().grow(-HOLD_IN)
	var at: Vector2 = me.global_position
	if not inner.has_point(at):
		me.global_position = Vector2(clampf(at.x, inner.position.x, inner.end.x), clampf(at.y, inner.position.y, inner.end.y))


func _one() -> void:
	var lands: Node = host.get("lands")
	var which: String = str(target.get("what", ""))
	match str(target.get("boss", "")):
		"volley":
			if caster == null or not is_instance_valid(caster):
				return
			var kind := StringName(which)
			var origin: Vector2 = lands.call("_ring_spot", me.global_position) if kind in RINGS else host.call("_edge_spot")
			caster.call("fire_volley", BulletZone.find(lands), origin, (me.global_position - origin).angle(),
				"%s%d:%d" % [which, VOLLEY_PHASE, _rng.randi() % 64], origin.distance_to(me.global_position))
		"shape":
			if caster == null or not is_instance_valid(caster):
				return
			caster.set("player", me)
			caster.call("cast_shape", StringName(which))
		"hazard":
			lands.call("spawn_env", which, me)
		"laser":
			var land: int = int(FightScript.CROWN_ORDER[_rng.randi() % FightScript.CROWN_ORDER.size()])
			match which:
				"sweep":
					lands.call("sweep", me, land)
				"cage":
					lands.call("cage", me, land)
				_:
					lands.call("pulse_beam", me, land)
