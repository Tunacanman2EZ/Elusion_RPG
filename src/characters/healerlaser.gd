# healerlaser.gd - the Gold Staff's beam (0.175.1).
#
# The owner, of Ahvassa's three staffs: "the gold one is mythic it will use the
# red crit laser from healers run", then "we need to optimize the laser and put
# the other 2 weapons on standby". So a healer holding the Gold Staff shines
# the Healer's Run's best laser where she aims instead of throwing orbs: its
# five layers of colour and its red heart (healerrun.gd's LASER_COLOURS,
# LASER_HEART, WHITE_FADE - one look, kept there), out to REACH or the first
# wall.
#
# WHAT IT DOES, and the server's books (gamedata.combat_bounds(), the healer's)
# allow every bit of it: each tick of the healer's shot clock - the orbs' own,
# hasten(shot_cooldown), a mana point each - everything standing in the beam
# takes one orb's damage, once; what the red heart touches takes the double
# (healer.gd's DOUBLE_HIT) - the run's critical beam, red in the middle. Per
# monster that is never more than an orb stream that doubled every shot.
#
# CHEAP, ON PURPOSE (the owner: "optimize the laser"):
#   - Drawn once, redrawn only when its length changes (against a wall); its
#     shimmer is the node's own scale, not a redraw. One canvas item, one
#     unshaded material shared by every beam.
#   - What it hits is asked of the physics server once a tick - one shape
#     query, the beam's own rectangle, against the monsters' hurtboxes - not
#     by walking every monster. A swarm's stand-ins have hurtboxes too.
#   - Nothing is made while it shines: the shape, the query and the list of
#     who was struck are kept and reused.
#   - The Endless's swarm puts stand-ins where attacks are out on the floor
#     (swarm.gd, FOCUS_GROUP): FOCUS_POINTS circles strung along the beam ask
#     for them there, and only while it shines.
#
# A PICTURE OF SOMEBODY ELSE'S (remoteattacks.gd, "laser"): `cosmetic`, shown
# from where their beam started to where it ended each tick they tell, for
# SHOW_SECONDS, then gone. It hits nothing and asks the swarm for nothing.
#
# No class_name: preload it by path.
extends Node2D

const Targets := preload("res://src/shared/targets.gd")
const Run := preload("res://src/world/healerrun/healerrun.gd")

# How far it reaches with no wall in the way: past the healer's aim ring and
# most of a screen.
const REACH := 280.0
# Its half width - thin enough that what it strikes shows round it - and the
# red heart's share of it, the run's sixth level (healerrun.gd CRIT_HEART).
const HALF := 6.0
const RED_SHARE := 0.55
# It starts this far ahead of her middle, at the staff rather than over her.
const AHEAD := 8.0
const LAYERS := 5
# The shimmer: the run's pulse, as the node's own height.
const PULSE := 0.15
const PULSE_SPEED := 40.0
# Above the world, as a spell's light is.
const Z := 4
# The monsters' hurtbox layer (swarmproxy.gd HURT_LAYER) - all a tick asks.
const HURT_MASK := 8
const MOST_TARGETS := 64
# Circles along the beam that ask the Endless's swarm for stand-ins.
const FOCUS_POINTS := 3
# A picture stays this long after each tick its maker tells (they tell ten a
# second), so it does not flicker between them.
const SHOW_SECONDS := 0.2

var cosmetic: bool = false
var length: float = REACH
var _drawn_length: float = -1.0
var _flicker: float = 0.0
var _show_left: float = 0.0
var _focus: Array = []
var _shape := RectangleShape2D.new()
var _query := PhysicsShapeQueryParameters2D.new()
var _struck: Dictionary = {}
# Just switched on: the next place it is put is not blended from wherever it
# was last (physics interpolation - CLAUDE.md, "reset_physics_interpolation()
# goes after the position").
var _fresh: bool = true
static var _material: CanvasItemMaterial = null


# The swarm reads a node's swarm_reach() and where it stands.
class Focus extends Node2D:
	var reach: float = 0.0

	func swarm_reach() -> float:
		return reach


static func make(cosmetic_picture: bool = false) -> Node2D:
	var beam: Node2D = (load("res://src/characters/healerlaser.gd") as GDScript).new()
	beam.name = "laser"
	beam.set("cosmetic", cosmetic_picture)
	return beam


func _init() -> void:
	z_index = Z
	z_as_relative = false
	visible = false
	if _material == null:
		_material = CanvasItemMaterial.new()
		# Mixed, not added: the run's own note - added, the layers came out white.
		_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = _material
	_query.shape = _shape
	_query.collision_mask = HURT_MASK
	_query.collide_with_areas = true
	_query.collide_with_bodies = false


func _ready() -> void:
	set_process(visible)


func red_half() -> float:
	return HALF * RED_SHARE


func way() -> Vector2:
	return Vector2.RIGHT.rotated(global_rotation)


func end_point() -> Vector2:
	return global_position + way() * length


func shine(on: bool) -> void:
	"""On while held; off, it asks the swarm for nothing."""
	if visible == on:
		return
	visible = on
	set_process(on)
	_set_focus(on and not cosmetic)
	if on:
		_fresh = true


func aim(from: Vector2, toward: Vector2) -> void:
	"""From `from` (the world: her middle, this side of a wall) along
	`toward`, AHEAD of it, to REACH or the first wall."""
	var start: Vector2 = from
	var reach: float = REACH
	if is_inside_tree():
		start = Targets.short_of_wall(self, from, from + toward * AHEAD)
		var end: Vector2 = Targets.short_of_wall(self, start, start + toward * REACH)
		reach = start.distance_to(end)
	else:
		start = from + toward * AHEAD
	global_position = start
	global_rotation = toward.angle()
	_placed()
	_set_length(reach)


func show_between(from: Vector2, to: Vector2) -> void:
	"""A picture: where another player's beam started and ended this tick."""
	var was_shown: bool = visible
	global_position = from
	var span: Vector2 = to - from
	if span.length_squared() > 0.01:
		global_rotation = span.angle()
	_set_length(span.length())
	_show_left = SHOW_SECONDS
	shine(true)
	if not was_shown:
		_placed()


func _placed() -> void:
	if _fresh and is_inside_tree():
		_fresh = false
		reset_physics_interpolation()


func strike(damage: int, critical: int, always_critical: bool = false) -> int:
	"""One tick: everything standing in the beam takes `damage`, what the red
	heart touches `critical` - each once. Returns how many it struck."""
	if cosmetic or not visible or not is_inside_tree() or damage <= 0:
		return 0
	var world: World2D = get_world_2d()
	if world == null or world.direct_space_state == null:
		return 0
	var along: Vector2 = way()
	_shape.size = Vector2(maxf(length, 1.0), HALF * 2.0)
	_query.transform = Transform2D(global_rotation, global_position + along * length * 0.5)
	var found: Array = world.direct_space_state.intersect_shape(_query, MOST_TARGETS)
	_struck.clear()
	var count: int = 0
	var red: float = red_half()
	for row in found:
		var box: Node2D = row.get("collider") as Node2D
		if box == null:
			continue
		var foe: Node = box.get_parent()
		if foe == null or not foe.is_in_group(&"enemies") or not foe.has_method("take_damage"):
			continue
		# A caged boss or a corpse is not in reach (turretprojectile.gd's rule).
		if foe.has_method("can_be_aimed_at") and not foe.call("can_be_aimed_at"):
			continue
		var key: int = Targets.hit_key(foe)
		if _struck.has(key):
			continue
		_struck[key] = true
		var middle: Vector2 = _hurt_middle(box)
		var across: float = absf((middle - global_position).cross(along))
		var in_red: bool = always_critical or across <= red + _hurt_radius(box)
		foe.call("take_damage", critical if in_red else damage)
		count += 1
	return count


static func _hurt_shape(box: Node2D) -> CollisionShape2D:
	"""A hurtbox's shape: "collisionshape2d" on a monster, the first one on a
	swarm's stand-in (swarmproxy.gd names none)."""
	var shape: CollisionShape2D = box.get_node_or_null(^"collisionshape2d") as CollisionShape2D
	if shape != null:
		return shape
	for i in box.get_child_count():
		shape = box.get_child(i) as CollisionShape2D
		if shape != null:
			return shape
	return null


func _hurt_middle(box: Node2D) -> Vector2:
	var shape: CollisionShape2D = _hurt_shape(box)
	return shape.global_position if shape != null else box.global_position


func _hurt_radius(box: Node2D) -> float:
	var shape: CollisionShape2D = _hurt_shape(box)
	if shape != null and shape.shape is CircleShape2D:
		return (shape.shape as CircleShape2D).radius * absf(shape.global_scale.x)
	if shape != null and shape.shape is CapsuleShape2D:
		return (shape.shape as CapsuleShape2D).radius * absf(shape.global_scale.x)
	return 8.0


func _set_length(reach: float) -> void:
	length = maxf(reach, 0.0)
	if absf(length - _drawn_length) >= 0.5:
		_drawn_length = length
		queue_redraw()
	for i in _focus.size():
		var f: Focus = _focus[i]
		f.position = Vector2(length * (float(i) + 0.5) / float(FOCUS_POINTS), 0.0)
		f.reach = length * 0.5 / float(FOCUS_POINTS) + HALF


func _set_focus(on: bool) -> void:
	if on and _focus.is_empty():
		for i in FOCUS_POINTS:
			var f := Focus.new()
			f.name = "focus%d" % i
			add_child(f)
			_focus.append(f)
		_set_length(length)
	for f in _focus:
		if on:
			(f as Node).add_to_group(&"swarm_focus")
		elif (f as Node).is_in_group(&"swarm_focus"):
			(f as Node).remove_from_group(&"swarm_focus")


func _process(delta: float) -> void:
	_flicker += delta
	scale = Vector2(1.0, 1.0 + PULSE * sin(_flicker * PULSE_SPEED))
	if cosmetic:
		_show_left -= delta
		if _show_left <= 0.0:
			shine(false)


func _draw() -> void:
	"""The run's beam (healerrun.gd Beam._one), along +x: its layers, a little
	faded, and its red heart, with round ends."""
	var reach: float = length
	if reach <= 0.0:
		return
	var colours: Array = Run.LASER_COLOURS
	for i in range(LAYERS - 1, -1, -1):
		var colour: Color = colours[i]
		var w: float = HALF * (0.45 + 0.55 * float(i + 1) / float(LAYERS))
		colour.a = (0.3 + 0.35 * (1.0 - float(i) / float(LAYERS))) * Run.WHITE_FADE
		draw_rect(Rect2(0.0, -w, reach, w * 2.0), colour)
		draw_circle(Vector2(reach, 0.0), w, colour)
		draw_circle(Vector2.ZERO, w * 0.8, colour)
	var red: float = red_half()
	var heart: Color = Run.LASER_HEART
	heart.a = 1.0
	draw_rect(Rect2(0.0, -red - 1.0, reach, (red + 1.0) * 2.0), Color(heart, 0.45))
	draw_rect(Rect2(0.0, -red, reach, red * 2.0), heart)
	draw_circle(Vector2(reach, 0.0), red, heart)
	draw_rect(Rect2(0.0, -1.0, reach, 2.0), Color(1.0, 0.75, 0.7, 0.95))
