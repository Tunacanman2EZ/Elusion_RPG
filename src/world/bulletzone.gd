# bulletzone.gd - an area's enemy bullets: one BulletField, the area's walls,
# and the one player they can hurt.
#
# THE FIELD IS THE BULLET-HELL ZONE (0.22.0). The owner: "set up field
# monsters to fire more projectiles small patterns and leave large field as it
# is ... keeping rpg and bullet hell both well tuned". field.gd adds one of
# these when its scene says `bullet_zone = true`, which field.tscn does and
# bigfield.tscn does not, so the Big Field fights exactly as before.
#
# WHAT A MONSTER DOES WITH IT: BulletZone.find(self), then one of the shapes
# below - fire_fan(), fire_ring(), fire_chain(), fire_pincer(), fire_helix(),
# fire_mortar(). A fan or a ring can SETTLE (0.25.0): given `stop_at`, its orbs
# slow to a stop that far out and lie there as mines for SETTLE_LINGER
# seconds, fading as they go (BulletField.spawn_settling). A monster with
# no zone in its area (every area but the Field) gets null and fires its
# ordinary projectile, so a monster script supports both with one branch.
#
# EVERY MONSTER THAT FIRES HERE HAS fire_volley(zone, origin, aim, volley,
# reach), and that one signature is the whole contract with monstersync.gd:
# the leader sends where, which way, which volley (a monster with more than
# one, the slime's "split") and how far (the fire sprite's pincer), and a
# follower's own copy of the monster fires it. Damage, element, count and speed
# are never on the wire (0.22.0's rule: a leader can aim a volley, never make
# one hit harder).
#
# WHAT EACH MONSTER FIRES. The owner, 0.24.0: "we are not taking away from my
# artists art but adding to it" - every monster's own shot still flies, the
# artist's sprite and its full damage, and the orbs ride with it, each a
# share of that shot (base_damage()):
#   Bush Sniper     its arrow, slowed, wound round by a helix of 2 and
#                   shedding a chevron wake (BulletWake)     bushsniper.gd
#   Bush Mage       its vine, and a slow ring of 10          bushmage.gd
#   Fire Sprite     its fire orb, and a pincer of 4 closing on the same
#                   spot at the same moment                  firesprite.gd
#   Electric Sprite its electric orb, leading a chain of 5   electricsprite.gd
#   Poison Slime    small: its arrow between a twin; large: its acid ball in
#                   a spray of 5 big orbs that settle where you stood, and
#                   every other shot a MORTAR - the acid ball lobbed onto
#                   your spot, bursting into a crater of 8 settled orbs and
#                   leaving its puddle (BulletLob, 0.25.0); and a ring of 12
#                   as it splits                             poisonslime.gd
#
# THE PLAYER IT HURTS is this game's own (the first node in group "player").
# The hitbox is HITBOX_RADIUS around Targets.body_point() - the body, where
# every monster aims and what the walls stop - not the hurtbox, which sits
# somewhere else for every class (the warrior's is 10 px above its body). A
# fan aimed at the body and judged at the hurtbox would sail under a player
# standing still. Smaller than what you see, on purpose - a bullet hell is fair
# when what has to miss is smaller than the picture - but not by much: 3 px
# until 0.25.3, when an orb could cross the middle of a character's sprite and
# miss, and the owner still wanted "more projectiles to hit player". 6 is about
# the width of a body's middle.
#
# Damage goes through player.take_damage(), so armour, the defense tier, the
# element's resistance, the floating number and the defense XP are all exactly
# what any other hit gets.
#
# EVERY ORB THAT REACHES YOU LANDS (0.25.3). Orbs are small hits - a share of
# the shot each - so a fan that arrives together is several of them, as the
# monster's own shot always was. Until 0.25.3 one hit made every orb pass
# through for CHIP_MERCY seconds (0.2, then 0.1), and of several touching in
# one frame only the strongest landed; the owner, three times: "i want more
# hits to hit player", "0.1 seconds then", "i still want more projectiles to
# hit player". CHIP_MERCY is 0 now and kept as the knob: above 0, every orb
# touching in the frame of a hit still lands, and only the frames after it are
# passed through.
#
# THE WALLS are a grid of 8-pixel cells, solid where a physics point query on
# layer 1 ("ground", which holds the tile walls and solid props, and which the
# game's arrows stop on) finds a body. Built a few rows a frame after the area
# loads, so loading does not hitch, and rebuilt around a spike door whenever
# one rises or lowers, so a door that opens lets the orbs through too.
class_name BulletZone
extends Node2D


const Targets := preload("res://src/shared/targets.gd")
const StatusEffects := preload("res://src/characters/statuseffects.gd")
const HitSource := preload("res://src/shared/hitsource.gd")

const GROUP: StringName = &"bulletzone"
const WALL_CELL: float = 8.0
const WALL_MASK: int = 1
const WALL_ROWS_PER_FRAME: int = 12
# 0.2 until 0.23.1, 0.1 until 0.25.3 - see the header.
const CHIP_MERCY: float = 0.0
const HITBOX_RADIUS: float = 6.0
# An orb lives this long at most; walls and the floor's edge end most sooner.
const LIFE: float = 6.0
# A settled orb lies on the floor this long once it has stopped (0.25.0).
const SETTLE_LINGER: float = 3.0
# Drawn above the y-sorted world (monsters, players, props): a bullet behind a
# tree is a bullet nobody saw.
const DRAWN_ABOVE: int = 20

var field: BulletField = null

# THE BOSS ROOMS' ORBS CARRY THEIR ELEMENT'S EFFECT (0.77.0). boss.gd turns it
# on for the arena and the Crowned's room; the Field leaves it off, so a fire
# sprite's orbs there burn no more than they ever did. See statuseffects.gd for
# what each element does and bossenemy.gd, THE KITS, for who fires what.
var element_effects: bool = false

# scene path -> its script's own `damage`, for a monster whose .tres leaves
# projectile_damage at 0. Read once per scene, not copied into a constant, so
# the two cannot drift.
static var _scene_damage: Dictionary = {}

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


static func base_damage(enemy: BaseEnemy, scene: PackedScene, fallback: int = 0) -> int:
	"""What the shot a volley replaces would have hit for: the monster's
	EnemyData.projectile_damage when it has one (every elemental variant
	does), else `fallback` when given, else the shot scene's own `damage`."""
	if enemy != null and enemy.enemy_data != null and enemy.enemy_data.projectile_damage > 0:
		return enemy.enemy_data.projectile_damage
	if fallback > 0:
		return fallback
	if scene == null:
		return 1
	var key: String = scene.resource_path
	if not _scene_damage.has(key):
		var probe: Node = scene.instantiate()
		_scene_damage[key] = maxi(1, int(probe.get("damage")) if probe.get("damage") != null else 1)
		probe.free()
	return int(_scene_damage[key])


static func share_of(damage: int, share: float) -> int:
	return maxi(1, roundi(damage * share))


func fire_fan(origin: Vector2, aim: float, count: int, spread: float, speed: float,
		damage: int, element: int, big: bool = false, stop_at: float = 0.0,
		gap_from: int = -1, gap_width: int = 0) -> void:
	"""`count` orbs spread evenly across `spread` radians, centred on `aim`.
	Given `stop_at`, they settle that far out (see the header). Given a gap
	(0.77.0), the `gap_width` orbs from index `gap_from` are left out: the way
	through a wall of them."""
	var colour: Color = shot_colour(element)
	for k in count:
		if gap_from >= 0 and k >= gap_from and k < gap_from + gap_width:
			continue
		var share: float = 0.0 if count <= 1 else float(k) / float(count - 1) - 0.5
		_spawn_one(origin, aim + share * spread, speed, colour, big, damage, element, stop_at)


func fire_ring(origin: Vector2, aim: float, count: int, speed: float, damage: int,
		element: int, big: bool = false, stop_at: float = 0.0, start_out: float = 0.0,
		gap_from: int = -1, gap_width: int = 0) -> void:
	"""`count` orbs evenly round a circle, one of them along `aim`: a player
	who stands still in front of the caster meets that one. Given `stop_at`,
	they settle into a ring that far out. Given `start_out`, they leave from a
	circle that wide rather than from the point itself. Given a gap (0.77.0),
	the `gap_width` orbs from index `gap_from` are left out."""
	var colour: Color = shot_colour(element)
	for k in count:
		if gap_from >= 0 and k >= gap_from and k < gap_from + gap_width:
			continue
		var angle: float = aim + TAU * k / maxi(count, 1)
		var settle: float = maxf(stop_at - start_out, 1.0) if stop_at > 0.0 else 0.0
		_spawn_one(origin + Vector2.from_angle(angle) * start_out, angle, speed, colour, big, damage,
			element, settle)


func _spawn_one(origin: Vector2, angle: float, speed: float, colour: Color, big: bool,
		damage: int, element: int, stop_at: float) -> void:
	if stop_at > 0.0:
		field.spawn_settling(origin, angle, speed, colour, stop_at, SETTLE_LINGER, damage, element, big)
	else:
		field.spawn(origin, angle, speed, colour, big, 0.0, 0.0, LIFE, damage, element)


func fire_chain(origin: Vector2, aim: float, count: int, slowest: float, fastest: float,
		damage: int, element: int) -> void:
	"""`count` orbs down one line at speeds from `slowest` to `fastest`: they
	leave together and string out, so the volley arrives as a stream that a
	sidestep clears and standing still eats several of."""
	var colour: Color = shot_colour(element)
	for k in count:
		var speed: float = slowest if count <= 1 else lerpf(slowest, fastest, float(k) / float(count - 1))
		field.spawn(origin, aim, speed, colour, false, 0.0, 0.0, LIFE, damage, element)


func fire_pincer(origin: Vector2, aim: float, reach: float, offsets: Array[float], speed: float,
		damage: int, element: int) -> void:
	"""Orbs that leave at `offsets` radians either side of `aim` and curve back
	to meet `reach` px along it - where the player stood when the volley left -
	all at the same moment.

	Each flies a circular arc: leaving at angle t to the chord of length D, the
	arc turns through 2t, its radius is D / (2 sin t) and its length is
	t * D / sin t. The widest orb flies at `speed`; the others are slowed so
	they take as long, which is what makes it close like a pincer rather than
	arrive as a stream (the first version did). The turn rate that bends an orb
	of speed v onto its arc is -2 * v * sin t / D. They live a little past the
	meeting point and are gone, rather than carrying on round the circle."""
	var colour: Color = shot_colour(element)
	var d: float = maxf(reach, 1.0)
	var meet_time: float = pincer_time(d, offsets, speed)
	for t in offsets:
		var own_speed: float = _arc_length(absf(t), d) / meet_time
		var turn: float = 0.0 if absf(t) < 0.001 else -2.0 * own_speed * sin(t) / d
		field.spawn(origin, aim + t, own_speed, colour, false, turn, 0.0, meet_time * 1.4,
			damage, element)


func fire_helix(origin: Vector2, aim: float, speed: float, count: int, width: float, rate: float,
		damage: int, element: int) -> void:
	"""`count` orbs flying down `aim` at `speed`, each weaving `width` px
	either side of the line `rate` radians a second, their phases spread
	evenly: two of them cross over the line twice a turn, like a strand of
	DNA wound round whatever flies down the middle (the sniper's arrow)."""
	var colour: Color = shot_colour(element)
	for k in count:
		field.spawn_swaying(origin, aim, speed, colour, width, 0.0, rate, PI * 2.0 * k / maxi(count, 1),
			damage, element, LIFE)


func fire_mortar(origin: Vector2, aim: float, reach: float, flight: float, art: Node2D,
		impact: int, ring: int, ring_speed: float, crater: float, ring_damage: int,
		element: int, puddle: PackedScene = null) -> BulletLob:
	"""A lob (bulletlob.gd): `art` thrown from `origin` over everything to the
	spot `reach` px along `aim`, landing `flight` seconds later. There it hits
	for `impact`, bursts into `ring` orbs that settle `crater` px out, each
	`ring_damage`, and leaves `puddle`. The spot is marked from the start."""
	var lob: BulletLob = BulletLob.new()
	lob.name = "lob"
	lob.zone = self
	lob.from = origin
	lob.to = origin + Vector2.from_angle(aim) * maxf(reach, 0.0)
	lob.aim = aim
	lob.flight = maxf(flight, 0.05)
	lob.art = art
	lob.element = element
	lob.impact_damage = impact
	lob.ring = ring
	lob.ring_speed = ring_speed
	lob.crater = crater
	lob.ring_damage = ring_damage
	lob.puddle = puddle
	lob.source = HitSource.stamp
	add_child(lob)
	return lob


static func pincer_time(reach: float, offsets: Array[float], speed: float) -> float:
	"""How long a pincer takes to close: the widest orb's arc at `speed`. A
	shot sent straight down the middle at reach / this arrives with it."""
	var widest: float = 0.0
	for t in offsets:
		widest = maxf(widest, absf(t))
	return _arc_length(widest, maxf(reach, 1.0)) / maxf(speed, 1.0)


static func _arc_length(t: float, chord: float) -> float:
	return chord if t < 0.001 else t * chord / sin(t)


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
	if CHIP_MERCY > 0.0:
		_mercy_until_ms = Time.get_ticks_msec() + int(CHIP_MERCY * 1000.0)
	# Each its own hit, so each is armoured, resisted and numbered on its own.
	for n in field.hits.size():
		var hit: Vector2i = field.hits[n]
		if bool(player.get("is_dying")):
			break
		# WHAT HIT ME (0.85.0): the orb's stamp, as the meter will name it.
		HitSource.blame(HitSource.name_of(field.hit_source[n] if n < field.hit_source.size() else 0))
		player.call(&"take_damage", maxi(hit.x, 1), hit.y)
		# And, in a boss room, what its element does (0.77.0). After the
		# damage, so a hit that kills you does not also freeze a corpse.
		if element_effects:
			StatusEffects.apply_to(player, StatusEffects.for_element(hit.y), maxi(hit.x, 1),
				field.hit_from[n] if n < field.hit_from.size() else Vector2.INF)


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
