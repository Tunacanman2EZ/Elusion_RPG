# swarmproxy.gd - a stand-in that takes the hits for one swarmling (0.93.0).
#
# swarm.gd has no node per swarmling, and every attack in the game finds its
# target the same way: it touches a hurtbox (an Area2D on layer 8, the
# monsters' hurtbox layer) whose parent is in "enemies" and has
# take_damage(). So the swarm keeps a few of these and moves them each
# physics tick onto the swarmlings nearest the player (stand_on()); a blow on
# one goes to the swarmling it stands on, and the swarm says whether it died.
#
# NOT A MONSTER TO ANYTHING ELSE. It carries the owner's stress-copy mark
# (stress_copy), which every walker of "enemies" that numbers, counts or
# respawns monsters already passes over: monstersync.gd never shares it, the
# respawner's census skips it and BaseEnemy-only code never sees it (it is
# not a BaseEnemy). Aiming (the mage's spike, a pet, the touch aim) may pick
# it, which is what lets those land on the swarm at all.
extends Node2D

const HURT_RADIUS := 10.0
const HURT_LAYER := 8
const STRESS_MARK := &"stress_copy"

var swarm: Node = null
# Which swarmling it stands on; -1, none (parked out of the way).
var slot: int = -1
# What the aim code reads off a monster.
var hp: float = 1.0
var max_hp: float = 1.0
var is_dying: bool = false
var _box: Area2D = null


func _init() -> void:
	add_to_group(&"enemies")
	set_meta(STRESS_MARK, true)
	_box = Area2D.new()
	_box.name = "hurtbox"
	_box.collision_layer = HURT_LAYER
	_box.collision_mask = 0
	_box.monitoring = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HURT_RADIUS
	shape.shape = circle
	shape.position = Vector2(0, -8)
	_box.add_child(shape)
	add_child(_box)
	visible = false
	position = Vector2(-100000, -100000)


func stand_on(index: int, at: Vector2) -> void:
	slot = index
	if index < 0:
		if visible:
			visible = false
			global_position = Vector2(-100000, -100000)
		return
	visible = true
	global_position = at
	if swarm != null:
		hp = float(swarm.hp[index])
		max_hp = float(swarm.max_hp)


func take_damage(amount: float, _element: int = 0) -> void:
	if slot < 0 or swarm == null:
		return
	swarm.call("hurt", slot, float(amount))
	if not bool(swarm.call("is_alive", slot)):
		# Dead under this blow: the next hit of the same swing finds nothing.
		stand_on(-1, Vector2.ZERO)


func can_be_aimed_at() -> bool:
	return slot >= 0
