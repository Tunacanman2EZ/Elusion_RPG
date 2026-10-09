# deathburst.gd - how a monster with no death of its own goes (0.16.0).
#
# Only two creatures in the game were drawn dying: the Crowned Beholder (and
# the element bosses built on it) has death* frames, and the small poison slime
# has smalldeath*. Everything else - every sprite, bush mage and bush sniper -
# was simply there one frame and gone the next. The owner wanted the website's
# arena to show each creature's death, and a creature with no death cannot be
# shown dying; so this gives them one, in the game first, and the website
# shows what the game does.
#
# WHAT IT DOES, in the order a player sees it:
#
#   FLASH     the killing hit's flash: the monster's last frame, overexposed
#             by BaseEnemy.HIT_FLASH_COLOR exactly as any hit flashes it
#   WHITE     that frame as a pure white shape (death_crumble.gdshader)
#   CRUMBLE   the shape breaks into squares of its own pixels, top first,
#             lifting a little as it goes, while a handful of single pixels
#             are thrown up out of it - white, cooling to the colour of the
#             monster's element - and fall away
#
# then frees itself. About half a second in all, the last pixels a little
# after.
#
# A COPY, NOT THE MONSTER. baseenemy.gd frees the monster the moment it dies,
# as it always has: the kill is reported, the respawner's clock starts, a
# gauntlet wave counts it, the slot it held is released - none of that waits
# on this, and none of it can be changed by it. This is a picture of the last
# frame the monster showed, left where the monster stood, beside it in the
# world (so it sorts with the trees and the other monsters the way the monster
# did). It is in no group, has no collision and cannot be hit.
#
# THE TIMELINE IS ADVANCED BY advance(), which _physics_process calls with the
# frame's delta; a test calls it directly.
class_name DeathBurst
extends Node2D


const CRUMBLE_SHADER := preload("res://src/shared/death_crumble.gdshader")

const FLASH_SECONDS := 0.05
const WHITE_SECONDS := 0.07
const CRUMBLE_SECONDS := 0.4
# How far the white shape lifts while it breaks up, in world pixels.
const LIFT := 3.0
# The size of the squares it breaks into, in the art's own pixels.
const BLOCK := 2.0

# The pixels thrown out of it: one for about every PIXEL_AREA square world
# pixels of the monster's hurtbox, between PIXELS_MIN and PIXELS_MAX.
const PIXEL_AREA := 14.0
const PIXELS_MIN := 12
const PIXELS_MAX := 48
const PIXEL_SECONDS := 0.5
# Out over most of the crumble, not all at once: the shape sheds them as it
# goes. (0 would be a steady stream, 1 all in one frame.)
const PIXEL_EXPLOSIVENESS := 0.35

# Where the pixels come from when the monster has no hurtbox to measure.
const FALLBACK_BODY := Rect2(-8, -24, 16, 24)

var element_colour: Color = Color.WHITE
var crumble: float = 0.0

var _age: float = 0.0
var _done: bool = false
var _body: Sprite2D = null
var _white: Sprite2D = null
var _white_from: Vector2 = Vector2.ZERO
var _pixels: CPUParticles2D = null
var _thrown: bool = false


static func spawn(enemy: Node2D) -> DeathBurst:
	"""Leaves a burst where enemy stands, made from the frame it is showing.
	Returns it, or null for a monster with nothing on screen to break up."""
	if enemy == null or not is_instance_valid(enemy) or not enemy.is_inside_tree():
		return null
	var sprite: AnimatedSprite2D = enemy.get_node_or_null("animatedsprite2d") as AnimatedSprite2D
	if sprite == null or not sprite.is_visible_in_tree() or sprite.sprite_frames == null \
			or not sprite.sprite_frames.has_animation(sprite.animation):
		return null
	var frame: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	var parent: Node = enemy.get_parent()
	if frame == null or parent == null:
		return null
	var burst := DeathBurst.new()
	burst.name = "deathburst"
	parent.add_child(burst)
	# The monster's whole placement - a creature placed at one and a half times
	# its size breaks up at that size.
	burst.global_transform = enemy.global_transform
	burst.reset_physics_interpolation()
	# The tint a whole creature is given (EnemyData.body_tint) is on the enemy
	# itself, so the copy wears it too.
	burst.modulate = enemy.modulate
	# BUILT HERE, NOT IN _ready(), for the reason blast.gd gives: _ready() runs
	# inside add_child(), before the line above has put it in place.
	burst._build(enemy, sprite, frame)
	return burst


func _build(enemy: Node2D, sprite: AnimatedSprite2D, frame: Texture2D) -> void:
	# Where the sprite sits on the monster, carried over to the copy.
	var on_body: Transform2D = enemy.global_transform.affine_inverse() * sprite.global_transform

	_body = _copy_of(sprite, frame, on_body)
	_body.name = "body"
	# The monster's own material, so an element's recolour is kept.
	_body.material = sprite.material
	_body.modulate = BaseEnemy.HIT_FLASH_COLOR
	add_child(_body)

	_white = _copy_of(sprite, frame, on_body)
	_white.name = "white"
	var shape := ShaderMaterial.new()
	shape.shader = CRUMBLE_SHADER
	shape.set_shader_parameter("block", BLOCK)
	var region: Rect2 = Rect2(Vector2.ZERO, frame.get_size())
	if frame is AtlasTexture:
		region = (frame as AtlasTexture).region
	shape.set_shader_parameter("frame_top", region.position.y)
	shape.set_shader_parameter("frame_height", region.size.y)
	_white.material = shape
	_white.visible = false
	_white_from = _white.position
	add_child(_white)

	var element: int = int(enemy.call("current_element")) if enemy.has_method("current_element") else Element.Type.NONE
	element_colour = Element.colour_for(element)
	_pixels = _thrown_pixels(_body_rect(enemy))
	add_child(_pixels)


static func _copy_of(sprite: AnimatedSprite2D, frame: Texture2D, at: Transform2D) -> Sprite2D:
	var copy := Sprite2D.new()
	copy.texture = frame
	copy.centered = sprite.centered
	copy.offset = sprite.offset
	copy.flip_h = sprite.flip_h
	copy.flip_v = sprite.flip_v
	copy.transform = at
	copy.z_index = sprite.z_index
	copy.z_as_relative = sprite.z_as_relative
	copy.texture_filter = sprite.texture_filter
	return copy


func _body_rect(enemy: Node2D) -> Rect2:
	# The monster's hurtbox - what a player hits - as the body the pixels come
	# out of, in this node's space (which is the monster's).
	var box: CollisionShape2D = enemy.get_node_or_null("hurtbox/collisionshape2d") as CollisionShape2D
	if box == null or box.shape == null:
		box = enemy.get_node_or_null("bodyshape") as CollisionShape2D
	if box == null or box.shape == null:
		return FALLBACK_BODY
	var local: Transform2D = enemy.global_transform.affine_inverse() * box.global_transform
	return local * box.shape.get_rect()


func _thrown_pixels(body: Rect2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "pixels"
	p.one_shot = true
	p.emitting = false
	p.amount = clampi(int(body.get_area() / PIXEL_AREA), PIXELS_MIN, PIXELS_MAX)
	p.lifetime = PIXEL_SECONDS
	p.lifetime_randomness = 0.4
	p.explosiveness = PIXEL_EXPLOSIVENESS
	p.position = body.get_center()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = body.size * 0.5
	p.direction = Vector2(0, -1)
	p.spread = 65.0
	p.initial_velocity_min = 18.0
	p.initial_velocity_max = 48.0
	p.damping_min = 10.0
	p.damping_max = 25.0
	p.gravity = Vector2(0, 110)
	# Single squares of whole world pixels, like Blast's sparks and the
	# bleed's drops.
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var ramp := Gradient.new()
	var faded := element_colour
	faded.a = 0.0
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	ramp.colors = PackedColorArray([Color.WHITE, element_colour, faded])
	p.color_ramp = ramp
	# Where they land as the shape lifts away.
	p.local_coords = false
	return p


func _physics_process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if _done:
		return
	_age += delta
	var white_at: float = FLASH_SECONDS
	var crumble_at: float = FLASH_SECONDS + WHITE_SECONDS
	if _age >= white_at and _body.visible:
		_body.visible = false
		_white.visible = true
	if _age >= crumble_at:
		if not _thrown:
			_thrown = true
			_pixels.emitting = true
		crumble = clampf((_age - crumble_at) / CRUMBLE_SECONDS, 0.0, 1.0)
		(_white.material as ShaderMaterial).set_shader_parameter("crumble", crumble)
		_white.position = _white_from + Vector2(0, -LIFT * crumble).round()
		if crumble >= 1.0:
			_white.visible = false
	if _age >= crumble_at + lasts():
		_done = true
		queue_free()


static func lasts() -> float:
	"""From the start of the crumble to the last pixel landing: the last one
	leaves (1 - PIXEL_EXPLOSIVENESS) of a lifetime in and lives a lifetime."""
	return maxf(CRUMBLE_SECONDS, PIXEL_SECONDS * (2.0 - PIXEL_EXPLOSIVENESS))


static func seconds() -> float:
	"""How long a burst is on screen, start to finish."""
	return FLASH_SECONDS + WHITE_SECONDS + lasts()


func showing() -> StringName:
	"""Which part a player sees right now: &"flash", &"white", &"crumble" or
	&"gone" - for the tests."""
	if _done or (not _body.visible and not _white.visible):
		return &"gone"
	if _body.visible:
		return &"flash"
	return &"white" if crumble <= 0.0 else &"crumble"
