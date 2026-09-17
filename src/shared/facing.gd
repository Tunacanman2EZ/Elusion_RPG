# facing.gd — turning a direction vector into one of four compass words.
#
# This project is four-directional: sprites, animations, attacks and navigation
# all reduce an arbitrary Vector2 to "up", "down", "left" or "right". The rule
# for doing that is one line of arithmetic, and it was written out ten separate
# times - in player.gd, all four class scripts, pet.gd and twice in
# baseenemy.gd.
#
# THEY HAD ALREADY DRIFTED. Every copy opens `if abs(x) > abs(y)`, but the
# enemy copies then check `abs(y) > 0` and return "" when handed Vector2.ZERO,
# while the player and class copies fall through to their else branch and
# return "up". A still character faces up; a still enemy faces nowhere. Nobody
# decided that.
#
# WHY THERE ARE TWO RULES HERE AND NOT ONE
# ----------------------------------------
# Both behaviours are correct for their caller, which is why this exposes both
# rather than picking a winner:
#
#   from_vec()       returns "" when there is no direction. Navigation wants
#                    this - "I have no heading" is a real answer, and coercing
#                    it to "down" would send an enemy walking for no reason.
#
#   from_vec_total() always returns a direction. Animation wants this - there
#                    is no "no animation" to play, so a still sprite has to be
#                    idling in SOME direction.
#
# What is not correct is having both by accident, in different files, without
# either one saying so.
class_name Facing
extends RefCounted


const NONE  := ""
const UP    := "up"
const DOWN  := "down"
const LEFT  := "left"
const RIGHT := "right"

# In the order a compass would give them, for anything that wants to iterate.
const ALL: PackedStringArray = [UP, DOWN, LEFT, RIGHT]


# =============================================================================
# VECTOR TO WORD
# =============================================================================

static func from_vec(vec: Vector2) -> String:
	# The dominant axis wins. A PERFECT DIAGONAL GOES VERTICAL, because
	# `abs(x) > abs(y)` is false when they are equal - worth knowing, since it
	# means (1, 1) faces down rather than right.
	#
	# Returns NONE for a zero vector. Callers that must always have a heading
	# want from_vec_total() instead.
	if absf(vec.x) > absf(vec.y):
		return RIGHT if vec.x > 0.0 else LEFT
	elif absf(vec.y) > 0.0:
		return DOWN if vec.y > 0.0 else UP
	return NONE


static func from_vec_total(vec: Vector2, fallback: String = UP) -> String:
	# Always a direction. The fallback is only reachable for an exactly zero
	# vector, and it is a parameter rather than a hard-coded constant because
	# "which way does a thing face when it is not moving" is a per-caller
	# decision, not a fact about geometry.
	#
	# THE DEFAULT IS UP, AND THAT IS NOT A PREFERENCE. Every copy of this rule
	# in the project resolved a zero vector to "up", because they all ended
	# `return "...down" if dir.y > 0 else "...up"` and 0 > 0 is false. Nobody
	# chose up; it fell out of the else. DOWN is arguably the better answer for
	# a character facing the camera, but changing it is a gameplay decision to
	# make on purpose, not something to slip into a refactor that claims to
	# change nothing.
	var dir: String = from_vec(vec)
	return dir if dir != NONE else fallback


static func secondary_from_vec(vec: Vector2) -> String:
	# The OTHER axis - the one from_vec() did not pick.
	#
	# This is the wall-slide fallback: an enemy pressed against a wall on its
	# dominant axis tries the perpendicular one instead. Returns NONE when that
	# other axis is exactly zero, because there is genuinely nowhere to go.
	if absf(vec.x) > absf(vec.y):
		if vec.y == 0.0:
			return NONE
		return DOWN if vec.y > 0.0 else UP
	if vec.x == 0.0:
		return NONE
	return RIGHT if vec.x > 0.0 else LEFT


static func from_vec_stable(vec: Vector2, current: String, margin: float = 1.4) -> String:
	# HYSTERESIS. from_vec() picks the dominant axis, so a heading that wanders
	# across the 45-degree line - a near-diagonal chase, a slot that is almost
	# corner-on - flips the answer between two cardinals on tiny frame-to-frame
	# changes, and the walk animation strobes. This keeps the CURRENT facing
	# unless the other axis beats it by `margin`, so the sprite only turns when
	# the new direction has clearly, steadily won. Larger margin = stickier.
	#
	# It needs to be told the current facing because a single vector cannot know
	# what it is turning away from - that state lives with the caller.
	if not is_direction(current):
		return from_vec_total(vec)
	var ax: float = absf(vec.x)
	var ay: float = absf(vec.y)
	if current == LEFT or current == RIGHT:
		if ay > ax * margin:
			return DOWN if vec.y > 0.0 else UP
		if ax > 0.0:
			return RIGHT if vec.x > 0.0 else LEFT
		return current
	# currently vertical (or a zero vector holds the last heading)
	if ax > ay * margin:
		return RIGHT if vec.x > 0.0 else LEFT
	if ay > 0.0:
		return DOWN if vec.y > 0.0 else UP
	return current


# =============================================================================
# WORD TO VECTOR
# =============================================================================

static func to_vec(dir: String) -> Vector2:
	match dir:
		LEFT:  return Vector2.LEFT
		RIGHT: return Vector2.RIGHT
		UP:    return Vector2.UP
		DOWN:  return Vector2.DOWN
	return Vector2.ZERO


static func is_direction(dir: String) -> bool:
	# True only for the four words. Useful for validating anything that arrived
	# from a save, the wire, or a scene file.
	return dir in ALL
