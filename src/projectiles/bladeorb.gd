# bladeorb.gd - the warrior's crypt orbs (0.39.0).
#
# The owner, of 0.38.0's arc and afterimages: "its horrible not the kind of
# effects i was thinking of ... the trails are bad i would say maybe the gold
# one is cool but no trails we can use projectiles from crypt to elavate" -
# and of the four ways offered, all four:
#
#   the sword fan      every sword swing flings SWORD_FAN_ORBS small steel
#                      orbs the way it aims, a short way (warrior.gd)
#   the finisher fan   the gold third-swing wave flies with FINISHER_FAN_ORBS
#                      gold orbs fanned out beside it (warrior.gd)
#   the burst          that gold wave bursts into a ring of BURST_ORBS gold
#                      orbs where it first cuts a monster, or breaks on a wall
#                      (slashwave.gd) - flying out from the one it cut, never
#                      back into it
#   the weave          two orbs crossing over every wave as it flies, like the
#                      crypt sniper's helix - a picture only (slashwave.gd)
#
# A CRYPT BULLET, THE PLAYER'S WAY ROUND. The Field's bullets (bulletfield.gd)
# are packed arrays with no physics, because an enemy bullet only has to find
# one player. These have to find monsters, so each is a small Area2D, as the
# slash wave is: the crypt orb's 8 x 8 pixels - a white-hot core, a body and a
# darker rim, steel or gold - unshaded, so it shows in a dark crypt as the
# monsters' do. No trail, and no glow: the owner said no trails.
#
# ONE MONSTER EACH. An orb hits the first monster it touches - take_damage(),
# like the wave - and pops; a wall pops it; it passes the player; and at
# `reach` it pops where it is. `ignore_id` is a monster it passes over: the burst
# starts on the monster the wave cut, and must not cut it eight times more.
# No magic XP: the wave pays that, once per monster it cuts.
#
# A PICTURE OF SOMEBODY ELSE'S (`cosmetic`, remoteattacks.gd) flies and pops
# the same, and touches nothing.
class_name BladeOrb
extends Area2D


const STEEL := &"steel"
const GOLD := &"gold"
# The healer aura's blobs (healblob.gd, 0.40.0) are these orbs too, green.
const HEAL := &"heal"
# The mage's ice shards (frostring.gd, 0.71.0), frost white.
const ICE := &"ice"
# The bodies: a cold steel blue, the crypt's gold (BulletPattern.GOLD, the
# Crowned Beholder's crown), and the healer's green (turretprojectile.gd's
# ORB_GREEN).
const STEEL_BODY := Color(0.62, 0.82, 1.0)
const GOLD_BODY := Color(1.0, 0.83, 0.3)
const HEAL_BODY := Color(0.55, 0.95, 0.42)
const ICE_BODY := Color(0.78, 0.95, 1.0)
const SIZE := 8
# How near a monster counts as touching: the orb's body, not its rim.
const RADIUS := 3.5
# Whether a wall stands between the orb and what it touches (0.69.1).
const Targets := preload("res://src/shared/targets.gd")
const POP_SECONDS := 0.1

var direction: Vector2 = Vector2.RIGHT
var speed: float = 240.0
# How far it flies before it pops, in pixels.
var reach: float = 80.0
var damage: int = 0
var element: int = Element.Type.NONE
var cosmetic: bool = false
var palette: StringName = STEEL
var flown: float = 0.0

var _ignore_id: int = 0
var _done: bool = false

# WHAT A CAST HAS HIT BETWEEN ITS PIECES (0.71.0, frostring.gd): instance id ->
# true, shared with the spikes it came from, or null for an orb on its own. An
# orb passes over what is in it - one hit a monster a cast - and adds what it
# cuts.
var struck: Variant = null

static var _textures: Dictionary = {}


static func fire(parent: Node, at: Vector2, way: Vector2, orb_speed: float, orb_reach: float,
		orb_damage: int, orb_palette: StringName = STEEL, is_cosmetic: bool = false,
		ignore_id: int = 0) -> BladeOrb:
	"""One orb from `at` (in the world) along `way`, passing over the monster
	whose instance id is `ignore_id`. Frees itself. Not from inside a physics
	callback (body_entered and the like): a new Area2D may not join then -
	slashwave.gd's burst defers."""
	var orb := BladeOrb.new()
	orb.name = "bladeorb"
	orb.direction = way.normalized() if way != Vector2.ZERO else Vector2.RIGHT
	orb.speed = orb_speed
	orb.reach = orb_reach
	orb.damage = orb_damage
	orb.palette = orb_palette
	orb.cosmetic = is_cosmetic
	orb._ignore_id = ignore_id
	parent.add_child(orb)
	orb.global_position = at
	# Placed after it went in: without this its first frame is drawn from
	# where it entered (slashwave.gd, warrior.gd's _spawn_slashwave()).
	orb.reset_physics_interpolation()
	return orb


static func fan_ways(aim: Vector2, count: int, spread_degrees: float, beside: bool) -> Array[Vector2]:
	"""`count` ways round `aim`, `spread_degrees` apart, as even either side
	of it as they go: with one down the aim itself, or - `beside` - none down
	it, for orbs that fly beside something that does (the finisher's wave)."""
	var ways: Array[Vector2] = []
	var step: float = deg_to_rad(spread_degrees)
	for i in count:
		var offset: float
		if beside:
			# ±1, ±2, ... steps: 1, -1, 2, -2.
			offset = step * float(floori(i / 2.0) + 1) * (1.0 if i % 2 == 0 else -1.0)
		else:
			offset = step * (float(i) - float(count - 1) / 2.0)
		ways.append(aim.rotated(offset))
	return ways


static func ring_ways(first: Vector2, count: int) -> Array[Vector2]:
	"""`count` ways evenly round, the first along `first`."""
	var ways: Array[Vector2] = []
	var start: Vector2 = first.normalized() if first != Vector2.ZERO else Vector2.RIGHT
	for i in count:
		ways.append(start.rotated(TAU * float(i) / float(count)))
	return ways


static func texture_for(orb_palette: StringName) -> ImageTexture:
	"""The Field's bullet (bulletfield.gd's orb_texture()), coloured: a
	white-hot core, the body, a darker rim. SIZE x SIZE."""
	if _textures.has(orb_palette):
		return _textures[orb_palette]
	var body: Color = GOLD_BODY if orb_palette == GOLD else (HEAL_BODY if orb_palette == HEAL
		else (ICE_BODY if orb_palette == ICE else STEEL_BODY))
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var middle: float = float(SIZE) / 2.0 - 0.5
	for y in SIZE:
		for x in SIZE:
			var gap: float = Vector2(x - middle, y - middle).length()
			if gap <= 1.6:
				image.set_pixel(x, y, Color.WHITE)
			elif gap <= 2.6:
				image.set_pixel(x, y, body)
			elif gap <= 3.9:
				image.set_pixel(x, y, Color(body.r * 0.55, body.g * 0.55, body.b * 0.55))
	var texture := ImageTexture.create_from_image(image)
	_textures[orb_palette] = texture
	return texture


static func unshaded_material() -> CanvasItemMaterial:
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return unshaded


func _init() -> void:
	# A player's projectile, as the slash wave is (slashwave.tscn): on layer 6,
	# looking at the walls, the player and the monsters' hurtboxes.
	collision_layer = 32
	collision_mask = 11
	var picture := Sprite2D.new()
	picture.name = "picture"
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.material = unshaded_material()
	add_child(picture)
	var shape := CollisionShape2D.new()
	shape.name = "shape"
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)


func _ready() -> void:
	(get_node(^"picture") as Sprite2D).texture = texture_for(palette)
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	if cosmetic:
		monitorable = false
		collision_layer = 0


func _physics_process(delta: float) -> void:
	if _done:
		return
	var step: float = speed * delta
	position += direction * step
	flown += step
	if flown >= reach:
		pop()


func _on_body_entered(body: Node2D) -> void:
	if _done:
		return
	if body.is_in_group(&"enemies"):
		_try_hit(body)
		return
	if body.is_in_group(&"player"):
		return
	# A wall, a prop: it breaks on it.
	pop()


func _on_area_entered(area: Area2D) -> void:
	if _done:
		return
	var target: Node = area.get_parent()
	if target != null and target.is_in_group(&"enemies"):
		_try_hit(target)


func _try_hit(target: Node) -> void:
	if target.get_instance_id() == _ignore_id or not target.has_method(&"take_damage"):
		return
	# NOT THROUGH A WALL (0.69.1): a monster's hurtbox stands taller than the
	# wall its feet are behind, and an orb touching that is at the wall - it
	# breaks there, as on the wall itself.
	if not Targets.can_reach(self, global_position, target):
		pop()
		return
	if struck is Dictionary:
		var id: int = target.get_instance_id()
		if (struck as Dictionary).has(id):
			return
		(struck as Dictionary)[id] = true
	if not cosmetic and damage > 0:
		target.take_damage(damage, element)
	pop()


func pop() -> void:
	"""Gone: a quick swell and fade where it is, touching nothing more."""
	if _done:
		return
	_done = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	var picture: Sprite2D = get_node(^"picture") as Sprite2D
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(picture, "scale", Vector2(1.5, 1.5), POP_SECONDS)
	t.tween_property(picture, "modulate:a", 0.0, POP_SECONDS)
	t.chain().tween_callback(queue_free)
