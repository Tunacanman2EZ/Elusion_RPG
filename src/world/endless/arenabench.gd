extends Node
# THE ARENAS IN THE TESTING GROUND (0.176.1). The owner: "we need to add every
# effect into testing area from cown and all minigames and measure and
# optimize them all and the effects outside of final boss also", and of the
# Earth boss's box of stalagmites: "faults crack had a hitch drop".
#
# Find the limit sweeps each elemental boss's arena - the arenas that fight
# back (lightarena.gd and its five siblings, bossenemy.gd ARENAS):
# - each arena whole ("the earth arena"): its boss stands at the top of the
#   floor at its last phase's health, its brain stopped, and the arena leads
#   as it does in a fight - faults, rocks, the quake and all - round you;
# - each of its effects alone ("earth faults"): the boss is a follower's copy
#   (net_mirror), so its arena makes nothing of its own, and the bench hands
#   it the event a leader would send - through the arena's own hear(), the
#   way every other game in a fight makes it - so many a second round you.
# Same interface as bossbench.gd (begin, end, make, count, set_rate), and its
# entries carry "boss", so limitsweep.gd sweeps them as it sweeps the boss's
# attacks.
const GmSpawner := preload("res://src/world/gmspawner.gd")

const LANDS := ["light", "wind", "water", "ice", "earth", "fire"]
const KIND_ARENA := -6
# [effect, the event a leader sends for it, how many more a step, most] -
# so many a second.
const EFFECTS := {
	"light": [["flares", "flare", 2, 40]],
	"wind": [["gusts", "gust", 1, 20]],
	"water": [["rain", "rain", 1, 10]],
	"ice": [["frost", "frost", 2, 40], ["ice walls", "wall", 1, 12], ["hail", "hail", 2, 40]],
	"earth": [["faults", "box", 1, 12], ["falling rock", "rock", 2, 40], ["pits", "pit", 1, 12]],
	"fire": [["embers", "ember", 2, 40], ["vent sweeps", "sweep", 1, 10]],
}
# The boss is held at this share of its health: its last phase.
const LAST_PHASE_SHARE := 0.2
# It stands this far above the middle, where you are.
const BOSS_ABOVE := 160.0
# The effects come down within this of you.
const NEAR := 120.0
# A frost's size, as the Ice boss's leader sends it (icearena.gd).
const FROST_R := 40.0
# A sweep of the fire's vents: so many vents, from one at random.
const SWEEP_VENTS := 5

var target: Dictionary = {}
var rate: float = 0.0
var me: Node2D = null
var world: Node = null
var middle: Vector2 = Vector2.ZERO
var boss: Node2D = null
var _owed: float = 0.0
var _walls: int = 0
# The whole arena is on (it is counted) once make() has been asked for it:
# its boss may have made it already, looking for it each half second.
var _on: bool = false
var _rng := RandomNumberGenerator.new()


# ---- what is swept ----------------------------------------------------------------

static func arenas() -> Array:
	"""Every arena whole, then every effect of each, in the sweep's order."""
	var out: Array = []
	for land in LANDS:
		out.append(_entry("the %s arena" % land, "arena", land, "on", 1, 1))
	for land in LANDS:
		for effect in EFFECTS.get(land, []):
			out.append(_entry("%s %s" % [land, effect[0]], "arena_event", "%s:%s" % [land, effect[1]],
				"a second", int(effect[2]), int(effect[3])))
	return out


static func _entry(label: String, what: String, which: String, per: String, step: int, most: int) -> Dictionary:
	return {"label": "Arena: " + label, "boss": what, "what": which, "per": per, "kind": KIND_ARENA,
		"step": step, "most": most}


static func is_arena(swept: Dictionary) -> bool:
	return str(swept.get("boss", "")) in ["arena", "arena_event"]


func land() -> String:
	return str(target.get("what", "")).get_slice(":", 0)


func event_kind() -> String:
	return str(target.get("what", "")).get_slice(":", 1)


# ---- begun and ended ----------------------------------------------------------------

func begin(swept: Dictionary, player: Node2D, in_world: Node, arena_middle: Vector2) -> void:
	"""Ready to sweep `swept`: its land's boss made above `arena_middle`."""
	end()
	target = swept
	me = player
	world = in_world
	middle = arena_middle
	rate = 0.0
	_owed = 0.0
	_walls = 0
	_on = false
	_rng.seed = 176
	_make_boss()


func end() -> void:
	"""The boss and its arena, gone."""
	var gone: Node2D = arena()
	if gone != null:
		gone.queue_free()
	if boss != null and is_instance_valid(boss):
		boss.queue_free()
	boss = null
	target = {}
	rate = 0.0
	_on = false


func _make_boss() -> void:
	var path: String = "res://scene/enemy/%sboss.tscn" % land()
	var before: Array = get_tree().get_nodes_in_group(GmSpawner.GROUP)
	if GmSpawner.spawn(get_tree(), path, 1, middle + Vector2(0.0, -BOSS_ABOVE)) <= 0:
		return
	for monster in get_tree().get_nodes_in_group(GmSpawner.GROUP):
		if not before.has(monster) and str(monster.scene_file_path) == path and not monster.is_queued_for_deletion():
			boss = monster as Node2D
	if boss == null:
		return
	# Its effects alone: a follower's copy, whose arena makes nothing itself.
	boss.set("net_mirror", str(target.get("boss", "")) == "arena_event")
	_hold_boss()


func arena() -> Node2D:
	"""The boss's arena now, or null."""
	if boss == null or not is_instance_valid(boss):
		return null
	return boss.call("arena") as Node2D


# ---- how many ------------------------------------------------------------------------

func set_rate(per_second: float) -> void:
	rate = maxf(0.0, per_second)


func make(more: int) -> int:
	"""The arena made now (it is looked for each half second once its boss is
	loose); how many more there are."""
	if boss == null or not is_instance_valid(boss) or more <= 0:
		return 0
	var before: int = count()
	if arena() == null:
		boss.call("_keep_arena", 1.0)
	# What is measured is the arena: the boss stands, its brain stopped.
	boss.set_physics_process(false)
	_on = arena() != null
	return count() - before


func count() -> int:
	"""How many of what is swept are out now (a rate: how many a second)."""
	if str(target.get("per", "")) == "a second":
		return int(rate)
	var now: Node2D = arena()
	return 1 if _on and now != null and float(now.get("_ending")) < 0.0 else 0


# ---- each frame ---------------------------------------------------------------------

func _process(_delta: float) -> void:
	if target.is_empty():
		return
	_hold_boss()


func _hold_boss() -> void:
	"""The boss kept at its last phase's health."""
	if boss == null or not is_instance_valid(boss):
		return
	var want: int = maxi(1, int(float(boss.get("max_hp")) * LAST_PHASE_SHARE))
	if absi(int(boss.get("hp")) - want) > 1:
		boss.set("hp", want)


func _physics_process(delta: float) -> void:
	if target.is_empty() or rate <= 0.0 or me == null or not is_instance_valid(me):
		return
	if arena() == null and boss != null and is_instance_valid(boss):
		boss.call("_keep_arena", 1.0)
		boss.set_physics_process(false)
	_owed += rate * delta
	while _owed >= 1.0:
		_owed -= 1.0
		_one()


func _one() -> void:
	"""One effect, as the leader's event for it makes it on a follower's game."""
	var now: Node2D = arena()
	if now == null:
		return
	var at: Vector2 = me.global_position + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * NEAR
	var event: Dictionary = {"h": event_kind(), "x": snappedf(at.x, 0.1), "y": snappedf(at.y, 0.1)}
	match event_kind():
		"frost":
			event["r"] = FROST_R
		"wall":
			_walls += 1
			event["a"] = _rng.randf() * TAU
			event["n"] = _walls
		"gust":
			event["a"] = _rng.randf() * TAU
		"sweep":
			event = {"h": "sweep", "s": _rng.randi() % 32, "d": 1 if _rng.randf() < 0.5 else -1, "n": SWEEP_VENTS}
	now.call("hear", event)
