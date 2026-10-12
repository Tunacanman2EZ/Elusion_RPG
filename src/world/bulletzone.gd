# bulletzone.gd - an area's enemy bullets: one BulletField, the area's walls,
# and the one player they can hurt.
#
# THE FIELD IS THE BULLET-HELL ZONE (0.22.0). The owner: "set up field
# monsters to fire more projectiles small patterns and leave large field as it
# is ... keeping rpg and bullet hell both well tuned". field.gd adds one of
# these when its scene says `bullet_zone = true`, which field.tscn does and
# bigfield.tscn does not, so the Big Field fights exactly as before.
#
# WHAT A MONSTER DOES WITH IT: BulletZone.find(self) and fire_fan(). A monster
# with no zone in its area (every area but the Field) gets null and fires its
# ordinary projectile, so a monster script supports both with one branch.
#
# THE PLAYER IT HURTS is this game's own (the first node in group "player").
# The hitbox is HITBOX_RADIUS around Targets.body_point() - the body, where
# every monster aims and what the walls stop - not the hurtbox, which sits
# somewhere else for every class (the warrior's is 10 px above its body). A
# fan aimed at the body and judged at the hurtbox would sail under a player
# standing still. Small on purpose: a bullet hell is fair when what has to
# miss is smaller than what you see.
#
# Damage goes through player.take_damage(), so armour, the defense tier, the
# element's resistance, the floating number and the defense XP are all exactly
# what any other hit gets.
#
# CHIP DAMAGE AND MERCY. Orbs are small hits meant to be dodged in numbers, so
# after one lands every orb passes through for CHIP_MERCY seconds. Without it a
# fan arriving together would land all of its orbs in one frame. Several orbs
# touching in the same frame are all spent, and only the strongest lands.
#
# THE WALLS are a grid of 8-pixel cells, solid where a physics point query on
# layer 1 ("ground", which holds the tile walls and solid props, and which the
# game's arrows stop on) finds a body. Built a few rows a frame after the area
# loads, so loading does not hitch, and rebuilt around a spike door whenever
# one rises or lowers, so a door that opens lets the orbs through too.
class_name BulletZone
extends Node2D


const Targets := preload("res://src/shared/targets.gd")

const GROUP: StringName = &"bulletzone"
const WALL_CELL: float = 8.0
const WALL_MASK: int = 1
const WALL_ROWS_PER_FRAME: int = 12
const CHIP_MERCY: float = 0.2
const HITBOX_RADIUS: float = 3.0
# An orb lives this long at most; walls and the floor's edge end most sooner.
const LIFE: float = 6.0
# Drawn above the y-sorted world (monsters, players, props): a bullet behind a
# tree is a bullet nobody saw.
const DRAWN_ABOVE: int = 20

var field: BulletField = null

var _mercy_until_ms: int = 0
var _walls: PackedByteArray = PackedByteArray()
var _walls_origin: Vector2 = Vector2.ZERO
var _walls_size: Vector2i = Vector2i.ZERO
var _rows_built: int = 0


static func find(from: Node) -> BulletZone:
	"""The zone in `from`'s area, or null when the area has none."""
	if from == null or not from.is_inside_tree():
		return null
	return from.get_tree().get_first_node_in_group(GROUP) as BulletZone


static func shot_colour(element: int) -> Color:
	"""An orb wears its element's colour (Element.colour_for), lifted a little
	toward white so the darkest of them - dark's deep violet - still reads on
	the crypt floor."""
	return Element.colour_for(element).lerp(Color.WHITE, 0.2)


func _ready() -> void:
	name = "bulletzone"
	add_to_group(GROUP)
	z_index = DRAWN_ABOVE
	field = BulletField.new()
	field.name = "field"
	add_child(field)
	field.bounds = _floor_rect()
	_start_walls()
	for door in get_tree().get_nodes_in_group(&"spikedoors"):
		if door.has_signal(&"raised_changed"):
			door.connect(&"raised_changed", _on_door_changed.bind(door))


func fire_fan(origin: Vector2, aim: float, count: int, spread: float, speed: float,
		damage: int, element: int, big: bool = false) -> void:
	"""`count` orbs spread evenly across `spread` radians, centred on `aim`."""
	var colour: Color = shot_colour(element)
	for k in count:
		var share: float = 0.0 if count <= 1 else float(k) / float(count - 1) - 0.5
		field.spawn(origin, aim + share * spread, speed, colour, big, 0.0, 0.0, LIFE,
			damage, element)


func _process(delta: float) -> void:
	_build_some_walls()
	var player: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	var at: Vector2 = Vector2(1.0e9, 1.0e9)
	var untouchable: bool = true
	if player != null and is_instance_valid(player):
		at = Targets.body_point(player)
		untouchable = Time.get_ticks_msec() < _mercy_until_ms or bool(player.get("is_dying"))
	field.step(delta, at, HITBOX_RADIUS, 0.0, untouchable)
	if field.hits.is_empty() or player == null or not player.has_method(&"take_damage"):
		return
	var worst: Vector2i = field.hits[0]
	for hit in field.hits:
		if hit.x > worst.x:
			worst = hit
	_mercy_until_ms = Time.get_ticks_msec() + int(CHIP_MERCY * 1000.0)
	player.call(&"take_damage", maxi(worst.x, 1), worst.y)


func _floor_rect() -> Rect2:
	# The area's floor - the "ground" TileMapLayer's painted cells - plus a
	# margin. No floor (a test world) means nowhere is off the edge.
	var ground: TileMapLayer = null
	if get_parent() != null:
		ground = get_parent().get_node_or_null(^"ground") as TileMapLayer
	if ground == null or ground.tile_set == null:
		return Rect2(-1.0e6, -1.0e6, 2.0e6, 2.0e6)
	var used: Rect2i = ground.get_used_rect()
	var tile: Vector2 = Vector2(ground.tile_set.tile_size)
	var top_left: Vector2 = ground.to_global(Vector2(used.position) * tile)
	return Rect2(top_left, Vector2(used.size) * tile).grow(16.0)


# =============================================================================
# THE WALLS
# =============================================================================

func _start_walls() -> void:
	var rect: Rect2 = field.bounds
	if rect.size.x > 100000.0:
		return
	_walls_origin = rect.position
	_walls_size = Vector2i(ceili(rect.size.x / WALL_CELL), ceili(rect.size.y / WALL_CELL))
	_walls = PackedByteArray()
	_walls.resize(_walls_size.x * _walls_size.y)
	_rows_built = 0


func walls_ready() -> bool:
	return _walls_size != Vector2i.ZERO and _rows_built >= _walls_size.y


func build_all_walls() -> void:
	"""Every remaining row now, rather than a few a frame. For tests."""
	while _walls_size != Vector2i.ZERO and _rows_built < _walls_size.y:
		_scan_rows(_rows_built, _walls_size.y)
		_rows_built = _walls_size.y
	field.set_walls(_walls, _walls_origin, WALL_CELL, _walls_size)


func _build_some_walls() -> void:
	if _walls_size == Vector2i.ZERO or _rows_built >= _walls_size.y:
		return
	var upto: int = mini(_rows_built + WALL_ROWS_PER_FRAME, _walls_size.y)
	_scan_rows(_rows_built, upto)
	_rows_built = upto
	field.set_walls(_walls, _walls_origin, WALL_CELL, _walls_size)


func _scan_rows(from_row: int, to_row: int) -> void:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space == null:
		return
	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.collision_mask = WALL_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	for cy in range(from_row, to_row):
		for cx in _walls_size.x:
			query.position = _walls_origin + Vector2(cx + 0.5, cy + 0.5) * WALL_CELL
			_walls[cy * _walls_size.x + cx] = 1 if not space.intersect_point(query, 1).is_empty() else 0


func _on_door_changed(_is_raised: bool, door: Node) -> void:
	# The door turns its blocker on or off with set_deferred, so the change is
	# only in the physics server a frame or two later.
	if _walls_size == Vector2i.ZERO or not (door is Node2D):
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_instance_valid(door):
		return
	var around: Rect2 = Rect2((door as Node2D).global_position - Vector2(32, 32), Vector2(64, 64))
	var first: Vector2i = Vector2i(((around.position - _walls_origin) / WALL_CELL).floor())
	var last: Vector2i = Vector2i(((around.end - _walls_origin) / WALL_CELL).ceil())
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.collision_mask = WALL_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	for cy in range(maxi(first.y, 0), mini(last.y, _walls_size.y)):
		for cx in range(maxi(first.x, 0), mini(last.x, _walls_size.x)):
			query.position = _walls_origin + Vector2(cx + 0.5, cy + 0.5) * WALL_CELL
			_walls[cy * _walls_size.x + cx] = 1 if not space.intersect_point(query, 1).is_empty() else 0
	field.set_walls(_walls, _walls_origin, WALL_CELL, _walls_size)
