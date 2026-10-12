# bulletpattern.gd - one boss cast: a shape of bullets fired on its own clock.
#
# A PREVIEW, NOT WIRED INTO THE GAME. The bullets themselves are
# src/shared/bulletfield.gd, which the Field uses since 0.22.0.
#
# EVERY SHOT IS A FUNCTION OF (kind, seed, start time, density), and that is
# the point of this file. A shot is fired when the cast's clock passes the
# time it was due - not "every N frames" - and the field moves it on by however
# late it is. Anything random (where the gap in a wall of rain falls) comes
# from a RandomNumberGenerator seeded with the cast's seed.
#
# So two games told the same four numbers draw the same bullets in the same
# places, at 30 or at 144 frames a second. That is what makes shared bullet
# hell possible over the network: the leading game sends one line per cast -
# "spiral, seed 90317, at 812.40" - instead of thousands of positions, and
# each game fires the bullets itself and judges only its own player's hits.
# The preview shows that line in its corner.
#
# The one input that is not in the four numbers is where the FAN aims: at the
# player, wherever they are when each volley leaves. Shared, the leader would
# name the target, and each game would aim at that player's position as its
# own copy of the world has it.
class_name BulletPattern
extends RefCounted


enum Kind { RING, SPIRAL, FLOWER, FAN, RAIN, GALAXY }

const NAMES: Dictionary = {
	Kind.RING: "rings",
	Kind.SPIRAL: "spiral",
	Kind.FLOWER: "flower",
	Kind.FAN: "aimed fans",
	Kind.RAIN: "rain wall",
	Kind.GALAXY: "galaxy",
}

# The Crowned Beholder's colours: its violet, its blood red, its crown's gold.
const VIOLET: Color = Color(0.71, 0.36, 1.0)
const BLOOD: Color = Color(1.0, 0.3, 0.42)
const GOLD: Color = Color(1.0, 0.83, 0.3)

var kind: int = Kind.RING
var seed_value: int = 0
var start: float = 0.0
var duration: float = 3.0
var interval: float = 0.5
var density: float = 1.0
var arena: Rect2 = Rect2()

var _shot: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


static func make(pattern_kind: int, pattern_seed: int, at: float, pattern_density: float,
		pattern_arena: Rect2) -> BulletPattern:
	var cast: BulletPattern = BulletPattern.new()
	cast.kind = pattern_kind
	cast.seed_value = pattern_seed
	cast.start = at
	cast.density = pattern_density
	cast.arena = pattern_arena
	cast._rng.seed = pattern_seed
	match pattern_kind:
		Kind.RING:
			cast.duration = 2.4
			cast.interval = 0.6
		Kind.SPIRAL:
			cast.duration = 4.0
			cast.interval = 0.06
		Kind.FLOWER:
			cast.duration = 4.0
			cast.interval = 0.08
		Kind.FAN:
			cast.duration = 3.0
			cast.interval = 0.45
		Kind.RAIN:
			cast.duration = 4.5
			cast.interval = 0.38
		Kind.GALAXY:
			cast.duration = 3.2
			cast.interval = 0.4
	return cast


func title() -> String:
	return str(NAMES.get(kind, "?"))


func done() -> bool:
	return _shot * interval > duration


func update(now: float, field: BulletField, origin: Vector2, target: Vector2) -> void:
	while not done() and start + _shot * interval <= now:
		var late: float = now - (start + _shot * interval)
		_fire(_shot, field, origin, target, late)
		_shot += 1


func _scaled(base: float, least: int) -> int:
	return maxi(least, roundi(base * density))


func _fire(shot: int, field: BulletField, origin: Vector2, target: Vector2, late: float) -> void:
	match kind:
		Kind.RING:
			# Rings, each turned half a gap from the last, so standing still in
			# one gap is a hit on the next ring.
			var n: int = _scaled(28.0, 8)
			var offset: float = (PI / n) * float(shot % 2)
			for k in n:
				var angle: float = offset + TAU * k / n
				field.spawn(origin, angle, 70.0, VIOLET if k % 2 == 0 else BLOOD, false, 0.0, late)
		Kind.SPIRAL:
			var arms: int = _scaled(4.0, 2)
			var turn: float = shot * 0.23
			for k in arms:
				field.spawn(origin, turn + TAU * k / arms, 78.0, BLOOD, false, 0.0, late)
		Kind.FLOWER:
			# Two spirals turning opposite ways: the gaps open and close.
			var arms: int = _scaled(3.0, 2)
			for k in arms:
				var angle: float = TAU * k / arms
				field.spawn(origin, angle + shot * 0.19, 66.0, VIOLET, false, 0.0, late)
				field.spawn(origin, angle - shot * 0.19, 66.0, GOLD, false, 0.0, late)
		Kind.FAN:
			# Aimed at where the player is now: a fan that punishes standing still
			# and is read, then sidestepped, by somebody moving.
			var n: int = _scaled(9.0, 3)
			var spread: float = 0.9
			var aim: float = (target - origin).angle()
			for k in n:
				var share: float = 0.0 if n == 1 else float(k) / float(n - 1) - 0.5
				var big: bool = k == n >> 1
				field.spawn(origin, aim + share * spread, 112.0, GOLD if big else BLOOD, big, 0.0, late)
		Kind.RAIN:
			# A wall falling from the top of the arena with one gap in it. Where
			# the gap falls is the seeded part: every screen opens it in the same place.
			var spacing: float = maxf(8.0, 22.0 / density)
			var gap_width: float = 56.0
			var gap_at: float = _rng.randf_range(arena.position.x + 40.0, arena.end.x - 40.0 - gap_width)
			var x: float = arena.position.x + 4.0
			while x < arena.end.x:
				if x < gap_at or x > gap_at + gap_width:
					field.spawn(Vector2(x, arena.position.y + 4.0), PI / 2.0, 58.0, VIOLET, false, 0.0, late)
				x += spacing
		Kind.GALAXY:
			# Big orbs that curve, the curl changing hands every ring.
			var n: int = _scaled(16.0, 6)
			var curl: float = 0.85 if shot % 2 == 0 else -0.85
			for k in n:
				field.spawn(origin, TAU * k / n, 62.0, GOLD if k % 2 == 0 else VIOLET, true, curl, late)
