# spikepath.gd - the wind stages' spike paths in the Endless (0.93.3).
#
# The owner, 28 Oct: "for shove its a 3 animation of earth spike however each
# one of those ticks should push player back and damage so player gets hit 3
# times if stuck in the pathway". A row of the spike door's own spikes
# (art/doors: spikesdown, spikeshalf, spikesup - his art, no new pictures)
# rises across the floor near you:
#
#   warning   the down picture, faint, for WARN_SECONDS: step out now
#   down      a tick: in the path, you are pushed along it and hit
#   half      a tick, the same
#   up        a tick, the same - stay in and the pushes keep you there, so
#             all three land
#   then it sinks (fades) and is gone.
#
# A tick pushes with the effects' own shove (statuseffects.gd SHOVE, from
# behind you on the path, so along it) and hits for `damage` as wind, through
# take_damage() - armour, resistance, god mode and the defence XP as ever.
#
# YOUR OWN PLAYER ONLY, AND NOTHING IS SENT: each game raises its own paths
# for its own player (endlessrun.gd raise_spikes()), the way every hazard in
# this game hurts the player of the game that draws it.
#
# Built in code, no class_name, so a fresh checkout needs no editor rescan.
extends Node2D

const StatusEffects := preload("res://src/characters/statuseffects.gd")
const HitSource := preload("res://src/shared/hitsource.gd")
const Targets := preload("res://src/shared/targets.gd")
const FRAMES := [
	preload("res://art/doors/spikesdown.png"),
	preload("res://art/doors/spikeshalf.png"),
	preload("res://art/doors/spikesup.png"),
]
const WARN_SECONDS := 0.7
const TICK_SECONDS := 0.3
const SINK_SECONDS := 0.4
const WARN_ALPHA := 0.35
# Between one spike's middle and the next, along the path.
const SPACING := 34.0
# How far either side of the path's line a body is in it.
const HALF_WIDTH := 18.0
# The pictures' feet: 28 px under their middle (64 x 64, drawn to row 60).
const FEET := 28.0

# Set before add_child().
var direction: Vector2 = Vector2.RIGHT
var count: int = 8
var damage: int = 10
# The one body it can hurt: this game's player.
var target: Node2D = null

# How many ticks found the target in the path (the tests read it).
var hits: int = 0
var spikes: Array[Sprite2D] = []
var _clock: float = 0.0
var _tick: int = -1


func _ready() -> void:
	y_sort_enabled = true
	direction = direction.normalized() if direction.length_squared() > 0.0 else Vector2.RIGHT
	for i in maxi(1, count):
		var spike := Sprite2D.new()
		spike.texture = FRAMES[0]
		spike.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spike.offset = Vector2(0, -FEET)
		spike.position = direction * SPACING * i
		spike.modulate.a = WARN_ALPHA
		add_child(spike)
		spikes.append(spike)


func _physics_process(delta: float) -> void:
	advance(delta)


func length() -> float:
	return SPACING * float(maxi(1, count) - 1)


func advance(delta: float) -> void:
	"""Runs the path on by `delta` seconds. The tests call it directly."""
	_clock += delta
	if _clock >= WARN_SECONDS:
		var due: int = mini(int(floorf((_clock - WARN_SECONDS) / TICK_SECONDS)), FRAMES.size() - 1)
		while _tick < due:
			_tick += 1
			for spike in spikes:
				spike.texture = FRAMES[_tick]
				spike.modulate.a = 1.0
			strike()
	var risen: float = WARN_SECONDS + TICK_SECONDS * FRAMES.size()
	if _clock > risen:
		var left: float = clampf(1.0 - (_clock - risen) / SINK_SECONDS, 0.0, 1.0)
		for spike in spikes:
			spike.modulate.a = left
		if left <= 0.0 and is_inside_tree():
			queue_free()


func in_path(point: Vector2) -> bool:
	"""Whether `point` (a body's feet) stands in the path."""
	var local: Vector2 = point - global_position
	var along: float = local.dot(direction)
	var across: float = absf(local.dot(direction.orthogonal()))
	return along >= -HALF_WIDTH and along <= length() + HALF_WIDTH and across <= HALF_WIDTH


func strike() -> bool:
	"""One tick: the target pushed along the path and hit, if it is in it."""
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return false
	var feet: Vector2 = Targets.body_point(target)
	if not in_path(feet):
		return false
	hits += 1
	# The push first: a hit that ends a run moves the player to the corridor,
	# and a shove after that would push them about there.
	StatusEffects.apply_to(target, StatusEffects.SHOVE, damage, feet - direction * 10.0)
	if target.has_method(&"take_damage"):
		HitSource.blame("endless:spikes")
		target.call(&"take_damage", damage, Element.Type.WIND)
	return true
