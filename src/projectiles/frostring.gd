# frostring.gd — the mage's ice shards (0.71.0): a ring of them spins round a
# spike's frost ring as it lands, then flies outward.
#
# The owner: "maybe some ice bullets that spin in a circle around the ring".
# When a stalagmite strikes (spelltargetcircle.gd, IMPACT_FRAME), SHARDS ice
# shards appear on a circle just outside its frost ring, spin round it for
# ORBIT_SECONDS, and then fly straight out, SHARD_REACH more, cutting what they
# touch for SHARD_SHARE of the spike's hit.
#
# EVERY SHARD HITS WHAT IT TOUCHES, AND IS SPENT ON IT (0.71.1). The owner: "the
# spinning balls are not hitting the enemies, really we need to increase the
# amount of times a enemy can be damaged and make sure bullets are absorbed by
# impacts". In 0.71.0 the shards shared the spike's "one hit a monster a cast",
# so a shard spinning through the very monster the spike had hit passed over it
# untouched - and kept going, through it. Now:
#   - a shard that touches a monster hits it - the spike's mark too - and is
#     gone, absorbed where it struck (BladeOrb.pop());
#   - a monster takes SHARD_HITS_EACH shards a cast at most, on top of the
#     spike, counted across all the cast's spikes (`cast_hits`); one past that
#     is still absorbed, for nothing - a bullet never passes through a body.
# So a monster takes up to 1 + SHARD_HITS_EACH hits a cast, and SHARD_SHARE is
# a fifth so that is at most 1.4 spikes' worth: the server's bound on a mage
# (gamedata.combat_bounds()) counts every cast as that, critical, from the
# shard_hits_each and shard_share the exporter writes.
#
# ONE CASTER'S COUNT. The counts are this cast's, of this mage's: four players
# on one monster each land every hit they make (monstersync.gd sends each one).
#
# THE SHARDS ARE BladeOrbs (bladeorb.gd, ICE), the warrior's crypt orbs in frost
# white - gold round a critical spike (GOLD, the warrior's finisher's). They
# break on walls, never cut through one (Targets), none starts past one, and a
# picture of somebody else's cuts nothing. They are children of this node, so
# spinning is turning it; let go, each flies out along its own spoke.
#
# PRELOADED WHERE USED, NOT A class_name (like targets.gd and marks.gd), so a
# fresh checkout needs no editor rescan before the stalagmite can load.
extends Node2D

const PATH := "res://src/projectiles/frostring.gd"
const Targets := preload("res://src/shared/targets.gd")


const SHARDS := 6
# Just outside the spike's frost ring (its circle_radius, 18).
const ORBIT_PAD := 6.0
const ORBIT_SECONDS := 0.5
# How far round the ring spins while it holds them, in turns.
const ORBIT_TURNS := 0.75
const SHARD_SPEED := 220.0
const SHARD_REACH := 70.0
# Each shard's hit, as a share of the spike's (0.4 in 0.71.0, when one monster
# could take no shard at all after the spike).
const SHARD_SHARE := 0.2
# The most shards one monster takes from one cast, after the spike.
const SHARD_HITS_EACH := 2
# Gone by now whatever happened, so nothing is ever left spinning.
const MAX_SECONDS := 3.0

var released: bool = false
var _age: float = 0.0


static func spin(parent: Node, centre: Vector2, ring_radius: float, spike_damage: int,
		cast_hits: Dictionary, is_cosmetic: bool = false, palette: StringName = BladeOrb.ICE) -> Node2D:
	"""SHARDS ice shards round `centre`, on a circle ring_radius + ORBIT_PAD out,
	each for SHARD_SHARE of `spike_damage`, SHARD_HITS_EACH a monster at most
	across the cast (`cast_hits`, shared by its spikes' shards) - frost white,
	or a critical spike's gold (BladeOrb.GOLD)."""
	var ring: Node2D = (load(PATH) as GDScript).new()
	ring.name = "frostring"
	parent.add_child(ring)
	ring.global_position = centre
	ring.reset_physics_interpolation()
	# A spike that hurts nothing (one set down with no damage) throws shards
	# that hurt nothing either.
	var each: int = maxi(1, roundi(float(spike_damage) * SHARD_SHARE)) if spike_damage > 0 else 0
	var out: float = ring_radius + ORBIT_PAD
	for i in SHARDS:
		var spoke := Vector2.from_angle(TAU * float(i) / float(SHARDS))
		var at: Vector2 = centre + spoke * out
		# None that would start past a wall: a spike landed against a 2 px
		# Big Field wall would put half its ring in the black.
		if not Targets.clear_between(ring, centre, at):
			continue
		# Held still while it spins (speed 0): the ring turns it round, and a
		# wall it turns into breaks it.
		var shard: BladeOrb = BladeOrb.fire(ring, at, spoke.orthogonal(), 0.0,
			SHARD_REACH, 0 if is_cosmetic else each, palette, is_cosmetic)
		shard.cast_hits = cast_hits
		shard.cast_hits_each = SHARD_HITS_EACH
		# Drawn along the ring while it is carried round it.
		shard.stretched_still = true
		shard.face()
	return ring


func _physics_process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	"""One step: spinning, then let go; gone once its shards are."""
	_age += delta
	if not released:
		if _age < ORBIT_SECONDS:
			rotation += TAU * ORBIT_TURNS / ORBIT_SECONDS * delta
			return
		release()
	if get_child_count() == 0 or _age >= MAX_SECONDS:
		queue_free()


func release() -> void:
	"""Every shard flies out along its spoke, from where it is now."""
	if released:
		return
	released = true
	for child in get_children():
		var shard := child as BladeOrb
		if shard == null or shard._done:
			continue
		# In this node's own frame, which stops turning now: outward is away
		# from the middle.
		shard.direction = shard.position.normalized() if shard.position != Vector2.ZERO else Vector2.RIGHT
		shard.speed = SHARD_SPEED
		shard.flown = 0.0
		shard.face()
