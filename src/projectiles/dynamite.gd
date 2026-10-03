# dynamite.gd - one stick of the tank's attack while Dynamite is equipped.
#
# Thrown by tank.gd in place of the aura. The stick and its lit fuse are
# Ahvassa's art; the throw, the wait and the bang are here:
#
#   FLYING   an arc from the tank to the spot aimed at, turning end over end,
#            with its shadow on the ground under it - the shadow is where it
#            really is, and the picture is drawn above it by the arc's height
#   FUSE     it lies there sparking for FUSE_SECONDS, flashing faster near the
#            end, with a ring showing how far the blast will reach
#   (gone)   the blast (Blast, &"dynamite"): every enemy inside HIT_RADIUS is
#            hit once, and the stick is freed
#
# One throw in ten is two sticks, spread either side of the aim - tank.gd
# decides that and throws two of these.
#
# THE TIMELINE IS ADVANCED BY advance(), which _physics_process calls with the
# frame's delta; a test calls it directly.
class_name Dynamite
extends Area2D


enum State { FLYING, FUSE }

const FLIGHT_SECONDS := 0.45
const ARC_HEIGHT := 26.0
const FUSE_SECONDS := 0.9

# MATCHED to the CollisionShape2D in dynamite.tscn and to the scorch it leaves.
# Bigger than the meteor's: one stick a second against two meteors a second.
const HIT_RADIUS := 28.0

var explosion_damage: int = 0
var caster: Node = null

# The second stick of a double throw leaves a moment after the first.
var delay: float = 0.0

var state: State = State.FLYING
var exploded: bool = false
var hits_dealt: int = 0
var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _age: float = 0.0

@onready var stick: AnimatedSprite2D = $stick
@onready var shadow: Sprite2D = $shadow


func _ready() -> void:
	stick.play("lit")
	shadow.texture = Blast.shadow_texture(5, 2)
	visible = delay <= 0.0


func throw_from(from: Vector2, to: Vector2) -> void:
	# Called once, by the tank, after the stick is in the tree.
	_from = from
	_to = to
	global_position = from
	reset_physics_interpolation()


func landing_spot() -> Vector2:
	return _to


func _physics_process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if exploded:
		return
	_age += delta
	var t: float = _age - delay
	if t < 0.0:
		return
	visible = true

	if state == State.FLYING:
		var f: float = clampf(t / FLIGHT_SECONDS, 0.0, 1.0)
		global_position = _from.lerp(_to, f)
		var height: float = sin(PI * f) * ARC_HEIGHT
		stick.position = Vector2(0, -3.0 - height).round()
		stick.rotation = f * TAU * 1.5
		shadow.modulate.a = lerpf(0.8, 0.35, sin(PI * f))
		if f >= 1.0:
			state = State.FUSE
			stick.position = Vector2(0, -3)
			stick.rotation = 0.0
			# Down from the air (z 5, over everything) to the floor with its
			# ring: anyone standing on it now stands in front of it.
			stick.z_as_relative = true
			stick.z_index = 0
			queue_redraw()
		return

	var lit_for: float = t - FLIGHT_SECONDS
	# Faster and faster in the last third: the warning that it is about to go.
	var left: float = FUSE_SECONDS - lit_for
	if left < FUSE_SECONDS * 0.35:
		var blink: bool = int(lit_for * (8.0 + 30.0 * (1.0 - left / FUSE_SECONDS))) % 2 == 0
		stick.modulate = Color(1.8, 1.3, 1.3) if blink else Color.WHITE
	queue_redraw()
	if lit_for >= FUSE_SECONDS:
		explode()


func explode() -> void:
	if exploded:
		return
	exploded = true
	Audio.play("explosion")
	for body in get_overlapping_bodies():
		if not body.is_in_group("enemies") or not body.has_method("take_damage"):
			continue
		body.take_damage(explosion_damage)
		hits_dealt += 1
	Blast.spawn(get_parent(), global_position, &"dynamite", HIT_RADIUS)
	queue_free()


func _draw() -> void:
	# The reach of the blast, while the fuse burns: the stalagmite's red,
	# brightening as the fuse runs down.
	if state != State.FUSE or exploded:
		return
	var lit_for: float = _age - delay - FLIGHT_SECONDS
	var a: float = lerpf(0.25, 0.7, clampf(lit_for / FUSE_SECONDS, 0.0, 1.0))
	draw_arc(Vector2.ZERO, HIT_RADIUS, 0.0, TAU, 44, Color(1.0, 0.2, 0.1, a), 1.0, false)
