# formation.gd — the geometry of the ring of ground enemies surround a player on.
#
# This owns the SHAPE of the formation: how many places there are, where each
# one sits relative to whoever is being surrounded, and how far apart they are.
# It owns nothing about who has claimed what, which stays in BaseEnemy with the
# scene tree and the navmesh.
#
# THE MODEL: ENEMIES ARE WEDGES
# -----------------------------
# An enemy standing next to the player occupies an ANGLE, not a tile. Its body
# is a circle of radius BODY_RADIUS, and seen from the player that body covers a
# wedge of 2*asin(BODY_RADIUS / distance) degrees. Lay those wedges side by side
# with no gaps and no overlaps and they close into a full circle - a solid wall
# of enemy with the player in the middle.
#
# That single idea decides every number in this file. It also means the ring
# radius and the number of enemies on it are not two independent choices: pick
# one and the other follows.
#
#     r = BODY_RADIUS / sin(PI / count)
#
# Pick the radius and the count follows, or pick the count and the radius does.
# slots_in_ring() below computes one from the other rather than trusting a
# hardcoded pair to stay consistent.
#
# WHICH ONE TO PICK IS A FEEL DECISION, AND IT IS THE RADIUS.
#
#     11 enemies -> 35.49px -> 18.5px of daylight between the bodies
#      9 enemies -> 29.24px -> 12.2px
#      7 enemies -> 23.05px ->  6.0px
#      5 enemies -> 17.01px ->  0.0px, literally touching
#
# Eleven was tried first and looked wrong for exactly the reason that table
# shows: a ring big enough to hold eleven bodies leaves most of a body-width of
# empty floor between the player and everything attacking them. The enemies were
# in perfect formation and the fight felt distant. Fewer, closer beats more,
# further - so the front rank now holds SEVEN at 24px, six pixels off the
# player's own body, and everyone who does not fit stands on ring 2 right behind
# them rather than being spaced out to make room.
#
# WHY THIS REPLACED A TILE GRID
# -----------------------------
# The previous version placed enemies on whole tiles in a square ring, with a
# stride constant that set the gap between neighbours AND the radius of the ring
# at the same time - so spreading enemies out also pushed them out of attack
# range, and the file carried a warning not to touch it for exactly that reason.
# Wedges separate the two properly: the radius sets the count, and the count is
# derived rather than tuned. A square ring also spaces its corners further from
# the player than its edges, so a "surrounded" player was only really surrounded
# from four directions.
#
# SLIDING OVER TO MAKE ROOM
# -------------------------
# Nothing here does that, and nothing needs to. The slots are fixed angles, and
# BaseEnemy._ensure_slot_claimed() hands an arriving enemy the NEAREST FREE one -
# so an enemy walking into a crowded ring takes the closest gap rather than the
# spot it was aiming at, which from the outside looks exactly like the pack
# shuffling over to let it in. The local avoidance in BaseEnemy is what carries
# it around the outside to get there.
class_name Formation
extends RefCounted


# Radius of an enemy's body. Every enemy scene in the project uses a
# CapsuleShape2D of radius 10 for its bodyshape, so this is measured, not
# chosen. If an enemy is ever added with a genuinely different footprint, the
# ring stops being exact for it - it will leave a gap or overlap by the
# difference, which is a cosmetic problem rather than a broken one.
const BODY_RADIUS := 10.0

# THE RING. Seven bodies close a circle at 23.05px; this is a shade above that,
# so they stand shoulder to shoulder rather than fighting over the same pixel.
#
# Everything about how a surrounded fight FEELS lives in this one number. Larger
# and more enemies reach the player at once but each stands further back; smaller
# and they crowd closer but fewer can touch you. Change it and check
# slots_in_ring(1) to see what count it just chose for you.
#
# 24 IS ALSO WHERE THE BUSH MAGE USED TO HOLD, before any of this existed, and
# that is not a coincidence - it was the distance that felt right. What was
# missing then was anywhere for mage eight onward to go, so they jostled the
# seven in front forever. The distance was never the problem; the absence of a
# second rank was.
const RING_RADIUS := 24.0

# How many rings out to generate for the overflow. Three covers about fifty
# enemies, which is more than any fight in this game.
const RING_COUNT := 3

# Once this close to its slot, an enemy stops and holds an idle pose.
#
# WHY IT EXISTS: right at the point of arriving, tiny positional noise - from
# contact with another enemy, or the player shifting slightly - can flip which
# axis wins in the direction picker every single frame, even though the enemy is
# not meaningfully moving. That is what looked like animations "flipping out"
# while the formation itself was correctly shaped.
const ARRIVAL_THRESHOLD := 6.0


# Built once on first use and shared by every enemy. _rings is the same length
# as _offsets and says which ring each entry belongs to, because "how far out is
# this slot" is the FIRST thing slot selection sorts on and recovering it from
# the offset's length afterwards would be arithmetic done twice.
static var _offsets: Array[Vector2] = []
static var _rings: Array[int] = []


# Distance from the player to the enemies standing on ring N.
#
# Each ring sits one body DIAMETER beyond the one inside it, so an enemy in
# ring 2 is touching the back of the enemy in front of it rather than trying to
# stand inside it.
static func ring_radius(ring: int) -> float:
	return RING_RADIUS + float(ring - 1) * BODY_RADIUS * 2.0


# How many enemies fit shoulder to shoulder on ring N.
#
# DERIVED, NEVER HARDCODED. The whole point of the wedge model is that this
# number is a consequence of the radius, so writing it down separately would
# only create something that can disagree with the geometry. Ring 1 comes out at
# SEVEN; ring 2 at thirteen; ring 3 at twenty. Forty slots in all.
#
# Those three numbers used to read eleven, seventeen and twenty-three, which is
# what a half-wedge — asin(BODY/r) rather than the 2*asin below — would give.
# The code was right and the comment was wrong, and it stayed wrong because a
# comment cannot fail. The count is asserted in testrunner.gd's FORMATION
# section now, derived rather than pinned, so the geometry is free to move and
# a contradiction between the two shows up as a failure instead of prose.
static func slots_in_ring(ring: int) -> int:
	var r: float = ring_radius(ring)
	if r <= BODY_RADIUS:
		return 1
	var wedge: float = 2.0 * asin(clampf(BODY_RADIUS / r, 0.0, 1.0))
	if wedge <= 0.0:
		return 1
	return maxi(1, int(floor(TAU / wedge)))


static func slot_offsets() -> Array[Vector2]:
	if _offsets.is_empty():
		for ring in range(1, RING_COUNT + 1):
			var r: float = ring_radius(ring)
			var count: int = slots_in_ring(ring)

			# HALF A WEDGE OF ROTATION ON EVERY RING PAST THE FIRST, so the
			# enemies behind stand in the gaps between the ones in front rather
			# than directly behind their backs. Lined up, a second rank is
			# invisible from the player's position and reads as enemies queueing;
			# offset, it reads as a crowd.
			var phase: float = 0.0
			if ring > 1:
				phase = PI / float(count)

			for i in range(count):
				var a: float = phase + TAU * float(i) / float(count)
				_offsets.append(Vector2(cos(a), sin(a)) * r)
				_rings.append(ring)
	return _offsets


# Which ring a slot belongs to. 1 is the ring touching the player.
#
# An out-of-range slot answers with a ring WORSE than any real one rather than
# with an error, so slot scoring can treat "no slot" as the worst option without
# a special case for it.
static func ring_of(slot: int) -> int:
	slot_offsets()
	if slot < 0 or slot >= _rings.size():
		return RING_COUNT + 1
	return _rings[slot]


# Which direction a slot lies in from the player, in radians.
static func bearing_of(slot: int) -> float:
	return offset_for(slot).angle()


static func slot_count() -> int:
	return slot_offsets().size()


static func offset_for(slot: int) -> Vector2:
	# Vector2.ZERO for an invalid index, which reads as "stand on the anchor" -
	# the same thing BaseEnemy falls back to when it holds no slot at all.
	var offsets: Array[Vector2] = slot_offsets()
	if slot < 0 or slot >= offsets.size():
		return Vector2.ZERO
	return offsets[slot]


static func world_position(anchor: Vector2, slot: int) -> Vector2:
	# Pure arithmetic, and DELIBERATELY UNCLAMPED. A slot is an offset from the
	# anchor and arithmetic knows nothing about walls, so part of a ring can land
	# inside geometry. Clamping needs the navigation map, which is BaseEnemy's
	# to reach - see clamp_to_navigation() at the call sites.
	return anchor + offset_for(slot)
