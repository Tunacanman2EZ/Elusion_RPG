# dynamite.gd - one stick of the tank's attack while Dynamite is equipped.
#
# Thrown by tank.gd, its ring lit as it throws. The stick and its lit fuse are
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
# CHAIN REACTION (0.12.0). The owner, offered it: "chain reaction sounds cool".
# A blast sets off every lit stick within CHAIN_RADIUS of it, CHAIN_DELAY later
# - a ripple, not one bang - and a stick set off that way hits for CHAIN_BONUS
# more, with a bigger fireball. A chained stick's own blast sets off the next,
# so a cluster goes up one after another. Sticks in the air are not lit yet and
# are not set off. The fuse is FUSE_SECONDS, longer than the throw's cooldown,
# so a stick thrown at the spot of the last one lands while that one is still
# lit: every second stick at one spot is a chain, and a faster tank chains
# more. The server's books allow for the bonus: the exporter writes it as the
# tank's dynamite_chain_bonus, and gamedata.combat_bounds() reads it.
#
# THE SMOULDER (0.13.0). The owner: "we need some sort of bonus damage for tnt
# like a field effect". Every blast leaves its scorch smouldering for
# FIELD_SECONDS - smoke and spitting sparks - and every FIELD_EVERY seconds
# whatever stands in it takes FIELD_SHARE of the stick's hit (the plain hit,
# not a chained one's) as fire. It is BurningCrater with Dynamite's numbers
# and look (BurningCrater.spawn_smoulder()): one smoulder per enemy at a time,
# so a chain's overlapping scorches do not stack. The books allow for it: the
# exporter writes the tank's dynamite_field_share and dynamite_field_every.
#
# BIGGER, FASTER, AND THE RING (0.14.0). The owner: "dynamite needs a bigger
# blast radios need to be able to throw faster and use tank ring i feel like 1
# by its self is not enough to be impressive". The blast is the meteor's size
# (HIT_RADIUS 44, from 28), so the chain reaches further with it (CHAIN_RADIUS
# 66) and the smoulder is as wide. tank.gd throws more of them, lights its
# ring while it throws, and makes every fifth throw a bundle of three - see
# its DYNAMITE SETTINGS for the numbers and what they come to.
#
# One throw in ten is two sticks, spread either side of the aim, and every
# fifth is a bundle of three in a triangle - tank.gd decides that and throws
# that many of these.
#
# THE TIMELINE IS ADVANCED BY advance(), which _physics_process calls with the
# frame's delta; a test calls it directly.
class_name Dynamite
extends Area2D


enum State { FLYING, FUSE }

const FLIGHT_SECONDS := 0.45
const ARC_HEIGHT := 26.0
# 1.2, not the 0.9 it was before 0.12.0: longer than tank.gd's
# dynamite_cooldown (0.75 since 0.14.0) less the flight, so the next stick
# lands while this one burns - the chain reaction needs two sticks lit at once.
const FUSE_SECONDS := 1.2

# CHAIN REACTION: how far a blast reaches another lit stick (the blast's own
# reach and half again, so a double throw's two sticks, 56 px apart, and a
# bundle's three set each other off), how long the next one takes to go, and
# how much harder it hits.
const CHAIN_RADIUS := 66.0
const CHAIN_DELAY := 0.1
const CHAIN_BONUS := 0.25

# THE SMOULDER: how long a scorch keeps biting, how often, and how much of the
# stick's hit a bite is. Three bites of 15%: nearly half a stick again for
# whatever stays in it - about a quarter more damage a second on one target,
# with the double throws and chains counted.
const FIELD_SECONDS := 1.5
const FIELD_EVERY := 0.5
const FIELD_SHARE := 0.15

# MATCHED to the CollisionShape2D in dynamite.tscn and to the scorch it leaves.
# The meteor's size (0.14.0; it was 28): "dynamite needs a bigger blast".
const HIT_RADIUS := 44.0

# A PICTURE OF SOMEBODY ELSE'S (0.19.0). With `cosmetic` set, this is a copy of
# an attack another player made, drawn on this screen from the presence
# server's word (remoteattacks.gd): it flies, spins, falls and burns exactly as
# theirs does, and it touches nothing - no hit, no XP, no camera shake, and
# nothing set off or pulled. The monsters are the area's leader's and every
# hit still travels as a hit; this is only what the owner asked to see: "i
# could not see their attacks but they could see mine".
# A picture's blast sets off only other pictures, and a real one's only real
# ones: somebody else's stick going off beside yours does not light your fuse.
var cosmetic: bool = false
var explosion_damage: int = 0
var caster: Node = null

# The second stick of a double throw leaves a moment after the first.
var delay: float = 0.0

var state: State = State.FLYING
var exploded: bool = false
# Set off by another stick's blast: goes CHAIN_DELAY later, for CHAIN_BONUS more.
var chained: bool = false
var _chain_left: float = -1.0
var hits_dealt: int = 0
var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _age: float = 0.0

@onready var stick: AnimatedSprite2D = $stick
@onready var shadow: Sprite2D = $shadow


func _init() -> void:
	add_to_group(&"dynamite_sticks")


func _ready() -> void:
	stick.play("lit")
	shadow.texture = Blast.shadow_texture(5, 2)
	visible = delay <= 0.0
	if cosmetic:
		RemoteAttacks.go_quiet(self)


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

	if _chain_left >= 0.0:
		_chain_left -= delta
		if _chain_left <= 0.0:
			explode()
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
	if cosmetic:
		Audio.play_at("explosion", global_position)
	else:
		Audio.play("explosion")
		var damage: int = blast_damage()
		for body in get_overlapping_bodies():
			if not body.is_in_group("enemies") or not body.has_method("take_damage"):
				continue
			body.take_damage(damage)
			hits_dealt += 1
	# A chained blast's fireball is bigger; what it reaches is not.
	Blast.spawn(get_parent(), global_position, &"dynamite", HIT_RADIUS * (1.3 if chained else 1.0), not cosmetic)
	var field: BurningCrater = BurningCrater.spawn_smoulder(get_parent(), global_position, explosion_damage,
		HIT_RADIUS, caster, FIELD_SHARE, FIELD_EVERY, FIELD_SECONDS)
	field.cosmetic = cosmetic
	_set_off_the_rest()
	queue_free()


func blast_damage() -> int:
	if chained:
		return roundi(float(explosion_damage) * (1.0 + CHAIN_BONUS))
	return explosion_damage


func _set_off_the_rest() -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group(&"dynamite_sticks"):
		if node == self or not (node is Dynamite) or not is_instance_valid(node):
			continue
		var other: Dynamite = node
		if other.cosmetic != cosmetic:
			continue
		if other.global_position.distance_to(global_position) <= CHAIN_RADIUS:
			other.set_off()


func set_off() -> void:
	"""Another stick's blast reached this one. A lit stick goes CHAIN_DELAY
	later, chained; one in the air, already going, or already gone does not."""
	if exploded or chained or state != State.FUSE:
		return
	chained = true
	_chain_left = CHAIN_DELAY


func _draw() -> void:
	# The reach of the blast, while the fuse burns: the stalagmite's red,
	# brightening as the fuse runs down.
	if state != State.FUSE or exploded:
		return
	var lit_for: float = _age - delay - FLIGHT_SECONDS
	var a: float = lerpf(0.25, 0.7, clampf(lit_for / FUSE_SECONDS, 0.0, 1.0))
	draw_arc(Vector2.ZERO, HIT_RADIUS, 0.0, TAU, 64, Color(1.0, 0.2, 0.1, a), 1.0, false)
