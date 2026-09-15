# formation.gd — the geometry of the ring of tiles enemies surround a player on.
#
# Split out of baseenemy.gd. This owns the SHAPE of the formation: how many
# slots there are, where each one sits relative to whoever is being surrounded,
# and how far apart they are. It owns nothing about who has claimed what, which
# stays in BaseEnemy with the scene tree and the navmesh.
#
# THE PROBLEM THE FORMATION SOLVES
# --------------------------------
# Enemies used to path at the player's raw position, so once enemy-to-enemy
# collision existed they converged and physically fought over one spot. Each
# enemy now claims a tile in a ring around the player and paths to that instead,
# which spreads them into a surrounding shape rather than a scrum.
#
# WHY A GRID RATHER THAN ANGLES
# -----------------------------
# The first version placed slots at arbitrary angles on a circle. The direction
# picker (see Facing) resolves a vector to one of four words by whichever axis
# is larger, so a target sitting near 45 degrees flips between two answers on
# tiny position changes - and free angles put a lot of targets near exactly
# that. A tile grid mostly avoids it: only the true corner tiles sit at 45.
class_name Formation
extends RefCounted


# One real grid tile.
const TILE_SIZE := 20.0

# How many rings out to generate. 3 gives 48 slots, more than any real fight.
const RING_COUNT := 3

# TILES BETWEEN ONE SLOT AND THE NEXT, and the reason enemies stopped looking
# piled up.
#
# This was effectively 1. A slot is 20px from its neighbour, but the large
# slime's sprite is 31px wide - so two enemies in adjacent slots overlapped by
# 11px, and their collision bodies (radius 5, 10px across) were far too small
# for physics to push them apart. The art was three times wider than the thing
# keeping them separated.
#
# A stride of 2 puts a full empty tile between neighbours: 40px between centres
# against a 31px sprite, about 9px of clear ground. Ring 1 still sits 40px from
# the player, so no attack range changed.
const SLOT_STRIDE := 2

# Once this close to its slot, an enemy stops and holds an idle pose.
#
# WHY IT EXISTS: right at the point of arriving, tiny positional noise - from
# collision with another enemy, or the player shifting slightly - can flip which
# axis wins in the direction picker every single frame, even though the enemy is
# not meaningfully moving. That is what looked like animations "flipping out"
# while the formation itself was correctly shaped.
const ARRIVAL_THRESHOLD := 6.0


# Built once on first use and shared by every enemy. Ring N is every tile at
# Chebyshev distance N * SLOT_STRIDE from the centre, so ring 1 is the
# perimeter just outside the player's own footprint, ring 2 the next out.
static var _offsets: Array[Vector2i] = []


static func slot_offsets() -> Array[Vector2i]:
	if _offsets.is_empty():
		for ring in range(1, RING_COUNT + 1):
			var d: int = ring * SLOT_STRIDE
			for dx in range(-d, d + 1, SLOT_STRIDE):
				for dy in range(-d, d + 1, SLOT_STRIDE):
					# The PERIMETER of this ring, not its interior - the inner
					# tiles already belong to a ring generated before it.
					if maxi(absi(dx), absi(dy)) == d:
						_offsets.append(Vector2i(dx, dy))
	return _offsets


static func slot_count() -> int:
	return slot_offsets().size()


static func offset_for(slot: int) -> Vector2i:
	# Vector2i.ZERO for an invalid index, which reads as "stand on the anchor" -
	# the same thing BaseEnemy falls back to when it holds no slot at all.
	var offsets: Array[Vector2i] = slot_offsets()
	if slot < 0 or slot >= offsets.size():
		return Vector2i.ZERO
	return offsets[slot]


static func world_position(anchor: Vector2, slot: int, tile_size: float = TILE_SIZE) -> Vector2:
	# Pure arithmetic, and DELIBERATELY UNCLAMPED. A slot is an offset from the
	# anchor and arithmetic knows nothing about walls, so half a ring can land
	# inside geometry. Clamping needs the navigation map, which is BaseEnemy's
	# to reach - see clamp_to_navigation() at the call sites.
	var offset: Vector2i = offset_for(slot)
	return anchor + Vector2(offset.x, offset.y) * tile_size
