# homing.gd — the steering shared by every projectile that follows what it was
# fired at. Pure maths, no state: each projectile keeps its own target and calls
# in once per physics frame.
#
# WHY A TURN RATE AND NOT A SNAP
# ------------------------------
# The obvious homing is to recompute the direction straight at the target every
# frame. That is not homing, it is a guarantee — the shot arrives no matter what
# the enemy does, and the player can watch a projectile pivot 180 degrees in one
# frame, which reads as a bug rather than as tracking.
#
# A turn rate gives the shot a turning circle instead. At radius = speed / rate,
# a pet orb at 300 px/s turning 180 deg/s sweeps a circle about 95px across, so:
#
#     a walking enemy               tracked easily, the shot barely curves
#     an enemy crossing at speed    tracked, but the shot arcs visibly
#     an enemy already beside it    missed, and the miss is legible
#
# That last row is the point. Homing should make a pet reliable, not infallible.
#
# WHY IT STOPS ONCE IT IS PAST
# ----------------------------
# A projectile that can steer forever will orbit anything it overshoots, circling
# until its lifetime runs out. It looks broken and it kills things it had already
# missed. is_past() is the latch: once the target is abeam or behind, the caller
# drops it and the shot flies straight from there.
class_name Homing


# Dot product of the heading against the direction to the target, at or below
# which the target counts as passed. 0.0 is exactly abeam — at that point the
# shot is level with the target and no longer closing, so there is nothing left
# to home on.
const PAST_DOT := 0.0

# Closer than this (squared, in pixels) the direction to the target is mostly
# noise — normalising a near-zero vector swings wildly frame to frame, and at
# this range the hit has already happened or already failed.
const MIN_TRACK_DIST_SQ := 4.0


# True once the shot is level with or behind its target. The caller is expected
# to drop its target when this returns true and never re-acquire: a shot that
# re-engages after passing turns into a boomerang.
static func is_past(heading: Vector2, from: Vector2, to: Vector2) -> bool:
	var offset: Vector2 = to - from
	if offset.length_squared() < MIN_TRACK_DIST_SQ:
		return false
	return heading.dot(offset.normalized()) <= PAST_DOT


# The heading rotated toward the target by at most turn_rate_deg * delta.
# Returns the heading untouched whenever it cannot meaningfully steer, so a
# caller can use the result unconditionally.
static func steer(heading: Vector2, from: Vector2, to: Vector2,
		turn_rate_deg: float, delta: float) -> Vector2:
	if turn_rate_deg <= 0.0 or heading == Vector2.ZERO:
		return heading

	var offset: Vector2 = to - from
	if offset.length_squared() < MIN_TRACK_DIST_SQ:
		return heading

	# angle_to() gives the SIGNED angle between the two, shortest way round,
	# which is what makes clamping it the whole implementation: the clamp caps
	# how far it may turn and the sign already decided which way.
	var wanted: float = heading.angle_to(offset.normalized())
	var most: float = deg_to_rad(turn_rate_deg) * delta
	return heading.rotated(clampf(wanted, -most, most))
