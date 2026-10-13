# healblob.gd - a green orb the healer's aura sends to a player outside its
# ring, healing them when it reaches them (0.40.0).
#
# The owner: "energy beam crashes down around the circle green orbs spawn
# around the circle and each blob travels to players outside of the circle
# giving them hp". The aura (healaura.gd) spawns them on its ring as the beam
# lands and gives each one a player; this is one of them.
#
# A CRYPT ORB IN THE HEALER'S GREEN (BladeOrb.texture_for(HEAL)), unshaded, no
# trail. It lifts off the ring for RISE_SECONDS, then flies at SPEED to the
# middle of its player - following them, if they move - and on reaching them
# gives `amount` hp and a puff of green motes. It heals only when `heals` is
# set: the aura sets it for this game's own player and for nobody else, as
# every game heals its own player and draws everyone else's. A blob whose
# player is gone, or that has not arrived in LIFE seconds, fades where it is;
# one with no player at all (nobody outside the ring) lifts off and fades.
class_name HealBlob
extends Node2D


const SPEED := 230.0
const RISE_SECONDS := 0.15
const RISE := 6.0
const LIFE := 2.0
# Close enough to have arrived.
const ARRIVE := 6.0
# Aimed at the middle of the player's picture, not their feet.
const AIM_ABOVE_FEET := Vector2(0.0, -14.0)

var target: Node2D = null
var heals: bool = false
var amount: int = 0
var arrived: bool = false
var age: float = 0.0

var _done: bool = false


static func send(parent: Node, from: Vector2, to: Node2D, heal_amount: int, does_heal: bool) -> HealBlob:
	"""A blob from `from` (in the world) to `to`. Frees itself."""
	var blob := HealBlob.new()
	blob.name = "healblob"
	blob.target = to
	blob.amount = heal_amount
	blob.heals = does_heal
	parent.add_child(blob)
	blob.global_position = from
	blob.reset_physics_interpolation()
	return blob


static func aim_of(body: Node2D) -> Vector2:
	"""Where a blob flies to on `body`: the middle of its picture."""
	return HealAura.feet_of(body) + AIM_ABOVE_FEET


func _ready() -> void:
	z_as_relative = false
	z_index = HealAura.SKY_Z
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var picture := Sprite2D.new()
	picture.name = "picture"
	picture.texture = BladeOrb.texture_for(BladeOrb.HEAL)
	picture.material = BladeOrb.unshaded_material()
	add_child(picture)


func _physics_process(delta: float) -> void:
	if _done:
		return
	step(delta)


func step(delta: float) -> void:
	"""One step: lift, then fly, then arrive - or give up."""
	age += delta
	if target == null:
		# Nobody to go to: it lifts off the ring a little longer, and fades.
		if age <= RISE_SECONDS * 3.0:
			position += Vector2(0.0, -RISE / RISE_SECONDS * delta)
		else:
			fade()
		return
	if not is_instance_valid(target) or not target.is_inside_tree() or age > LIFE:
		fade()
		return
	if age <= RISE_SECONDS:
		position += Vector2(0.0, -RISE / RISE_SECONDS * delta)
		return
	var to: Vector2 = aim_of(target) - global_position
	var stride: float = SPEED * delta
	if to.length() <= maxf(stride, ARRIVE):
		global_position = aim_of(target)
		arrive()
		return
	global_position += to.normalized() * stride


func arrive() -> void:
	"""At the player: the hp, if it is this game's own, and green motes."""
	if _done:
		return
	_done = true
	arrived = true
	if heals and amount > 0 and is_instance_valid(target) and target.has_method(&"heal") \
			and not bool(target.get("is_dying")):
		target.call("heal", amount)
	if is_instance_valid(target) and target.is_inside_tree():
		CastSparkle.muzzle(target, aim_of(target) - target.global_position, aim_of(target) + Vector2.UP)
	queue_free()


func fade() -> void:
	"""Gone where it is, healing nobody."""
	if _done:
		return
	_done = true
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.15)
	t.tween_callback(queue_free)
