# hitflash.gd - a hit's flash: the frame on screen drawn pure white over
# itself for a moment (0.58.0).
#
# THE ARTIST'S FLASH, ON EVERY FRAME. Each class and the boss were drawn with
# a hitflash: the pose, the same pose as a solid white shape, the pose again
# (measured: the white frame is the pose's own outline, 93-99% of its pixels
# for the four classes). Played as an animation it REPLACED whatever was
# running - a swing or a cast cut off, the boss frozen for good when its
# attack never finished (baseenemy.gd, "THE HIT FLASH IS DRAWN OVER WHATEVER
# FRAME") - so the game brightened the sprite instead, which leaves the
# outline and every dark pixel dark. The owner, 19 Oct: "every enemy and
# player has hitflash made for the animations why did we not use them?"
#
# So this draws what the artist drew, a solid white copy of the pose, ON TOP
# of whatever frame is showing, and keeps up with it frame by frame. Standing
# still it is his white frame; mid-swing it is the swing, white, and the
# swing goes on.
#
# IT NEVER TOUCHES THE SPRITE. Not its animation, its frame, its speed, its
# modulate or its material: it is a Sprite2D child that READS them, so nothing
# keyed to a frame or waiting on animation_finished can be moved by it, and
# nothing on the sprite can be left half white - the flash is a node, and it
# frees itself. A second hit restarts the flash already there rather than
# stacking another. (The same reason DeathBurst works on a copy.)
extends Sprite2D


const SHADER := preload("res://src/shared/hitflash.gdshader")
const PATH := "res://src/shared/hitflash.gd"
const NODE_NAME := "hitflash"

var seconds_left: float = 0.0
var _sprite: AnimatedSprite2D = null


static func flash(sprite: AnimatedSprite2D, seconds: float) -> Sprite2D:
	"""Shows sprite's frame pure white for `seconds`, following every frame
	it shows meanwhile. Returns the flash, or null when there is nothing to
	draw - no sprite, no frames, or no time."""
	if sprite == null or not is_instance_valid(sprite) or sprite.sprite_frames == null or seconds <= 0.0:
		return null
	var white: Sprite2D = sprite.get_node_or_null(NODE_NAME) as Sprite2D
	if white == null or white.is_queued_for_deletion():
		white = (load(PATH) as GDScript).new() as Sprite2D
		white.name = NODE_NAME
		sprite.add_child(white)
		white.call("_watch", sprite)
	white.set("seconds_left", seconds)
	white.call("follow")
	return white


static func on(sprite: AnimatedSprite2D) -> Sprite2D:
	"""The flash showing on sprite now, or null."""
	if sprite == null or not is_instance_valid(sprite):
		return null
	var white: Sprite2D = sprite.get_node_or_null(NODE_NAME) as Sprite2D
	return white if white != null and not white.is_queued_for_deletion() else null


func _watch(sprite: AnimatedSprite2D) -> void:
	_sprite = sprite
	var shape := ShaderMaterial.new()
	shape.shader = SHADER
	material = shape
	# Drawn after its parent, at its parent's depth: on top of the frame.
	show_behind_parent = false
	z_index = 0
	z_as_relative = true
	# The frame changes when the sprite says so, not a frame later.
	sprite.frame_changed.connect(follow)
	sprite.animation_changed.connect(follow)
	sprite.sprite_frames_changed.connect(follow)


func follow() -> void:
	"""The sprite's current frame, placed as the sprite places it."""
	if _sprite == null or not is_instance_valid(_sprite):
		return
	var frames: SpriteFrames = _sprite.sprite_frames
	if frames == null or not frames.has_animation(_sprite.animation) \
			or _sprite.frame >= frames.get_frame_count(_sprite.animation):
		texture = null
		return
	texture = frames.get_frame_texture(_sprite.animation, _sprite.frame)
	centered = _sprite.centered
	offset = _sprite.offset
	flip_h = _sprite.flip_h
	flip_v = _sprite.flip_v


func advance(delta: float) -> void:
	"""The flash's clock; _process() calls it, and a test may."""
	follow()
	seconds_left -= delta
	if seconds_left <= 0.0:
		_finish()


func _process(delta: float) -> void:
	advance(delta)


func _finish() -> void:
	if is_queued_for_deletion():
		return
	if _sprite != null and is_instance_valid(_sprite):
		for signal_name in ["frame_changed", "animation_changed", "sprite_frames_changed"]:
			if _sprite.is_connected(signal_name, follow):
				_sprite.disconnect(signal_name, follow)
	# Out of the way at once: a hit in the same frame starts a new flash under
	# the name, rather than finding this one on its way out.
	name = NODE_NAME + "_gone"
	visible = false
	queue_free()
