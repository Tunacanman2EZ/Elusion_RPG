# crowneddecoy.gd - an illusion of the Crowned (0.134.0, step 1 of the commit
# folder's CROWNED_PLAN.txt: "Decoy eyes: copies appear, only one real; a blow
# on a copy does nothing but break it; the real one is the one that casts").
#
# Made by crownedfight.gd. It wears the Crowned's own pictures (its sprite
# frames, material, scale and colour, the same animation each frame) and its
# health bar, moves as the Crowned moves (keeping where it stood from it, in
# the room), and stands among the monsters - in "enemies", with
# a hurtbox on the hurt layer - so an attack, a pet or the touch aim may pick
# it, which is the illusion working. It carries the stress-copy mark, as the
# Endless's stand-ins do, so nothing that numbers, counts, reports or
# respawns monsters sees it. Any blow breaks it (a ring of light, and gone);
# so does its time running out. It never attacks.
#
# No class_name: preload it by path.
extends Node2D

const HURT_LAYER := 8
const STRESS_MARK := &"stress_copy"
const HURT_RADIUS := 16.0
const BREAK_SECONDS := 0.35
const FADE_IN := 0.4

var source: Node2D = null
var life: float = 9.0
var broken: bool = false
var hp: float = 1.0
var max_hp: float = 1.0
var _sprite: AnimatedSprite2D = null
var _box: Area2D = null
var _age: float = 0.0
var _break_left: float = 0.0
var _bar: Range = null
var _offset: Vector2 = Vector2.ZERO
# Where it may stand (the room's floor); empty, anywhere.
var room: Rect2 = Rect2()


func _init() -> void:
	add_to_group(&"enemies")
	set_meta(STRESS_MARK, true)
	_box = Area2D.new()
	_box.name = "hurtbox"
	_box.collision_layer = HURT_LAYER
	_box.collision_mask = 0
	_box.monitoring = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HURT_RADIUS
	shape.shape = circle
	shape.position = Vector2(0, 2)
	_box.add_child(shape)
	add_child(_box)


func dress(boss: Node2D, seconds: float) -> void:
	"""Wear `boss`'s pictures for `seconds`."""
	source = boss
	life = seconds
	var theirs: AnimatedSprite2D = boss.get_node_or_null("animatedsprite2d") as AnimatedSprite2D
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "animatedsprite2d"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if theirs != null:
		_sprite.sprite_frames = theirs.sprite_frames
		_sprite.material = theirs.material
		_sprite.scale = theirs.scale
		_sprite.offset = theirs.offset
		_sprite.modulate = theirs.modulate
		_sprite.play(theirs.animation)
	add_child(_sprite)
	# ITS HEALTH BAR TOO, or the bar is the tell: a copy of the Crowned's,
	# kept at its numbers.
	var their_bar: Range = boss.get_node_or_null("healthbar") as Range
	if their_bar != null:
		_bar = their_bar.duplicate() as Range
		_bar.name = "healthbar"
		add_child(_bar)
	modulate.a = 0.0


func place(at: Vector2) -> void:
	"""Stand at `at`, and from now on move as the Crowned moves."""
	global_position = at
	if source != null and is_instance_valid(source):
		_offset = at - source.global_position
	reset_physics_interpolation()


func _physics_process(_delta: float) -> void:
	if broken or source == null or not is_instance_valid(source):
		return
	var at: Vector2 = source.global_position + _offset
	if room.size != Vector2.ZERO:
		at = Vector2(clampf(at.x, room.position.x, room.end.x), clampf(at.y, room.position.y, room.end.y))
	global_position = at


func _process(delta: float) -> void:
	_age += delta
	if broken:
		_break_left -= delta
		queue_redraw()
		if _break_left <= 0.0:
			queue_free()
		return
	life -= delta
	if life <= 0.0:
		shatter()
		return
	modulate.a = clampf(_age / FADE_IN, 0.0, 1.0)
	if source == null or not is_instance_valid(source):
		return
	var their_bar: Range = source.get_node_or_null("healthbar") as Range
	if _bar != null and their_bar != null:
		_bar.max_value = their_bar.max_value
		_bar.value = their_bar.value
		_bar.visible = their_bar.visible
		for k in mini(_bar.get_child_count(), their_bar.get_child_count()):
			var mine: Label = _bar.get_child(k) as Label
			var their_label: Label = their_bar.get_child(k) as Label
			if mine != null and their_label != null:
				mine.text = their_label.text
	if _sprite != null:
		var theirs: AnimatedSprite2D = source.get_node_or_null("animatedsprite2d") as AnimatedSprite2D
		if theirs != null:
			if _sprite.animation != theirs.animation and _sprite.sprite_frames != null \
					and _sprite.sprite_frames.has_animation(theirs.animation):
				_sprite.play(theirs.animation)
			_sprite.flip_h = theirs.flip_h
			_sprite.modulate = theirs.modulate
			_sprite.material = theirs.material


func take_damage(_amount: float, _element: int = 0) -> void:
	shatter()


func shatter() -> void:
	"""Broken: a ring of light where it stood, and gone."""
	if broken:
		return
	broken = true
	_break_left = BREAK_SECONDS
	remove_from_group(&"enemies")
	_box.set_deferred("monitorable", false)
	if _sprite != null:
		_sprite.visible = false
	if _bar != null:
		_bar.visible = false
	queue_redraw()


func can_be_aimed_at() -> bool:
	return not broken


func pass_key() -> int:
	"""Its own, for an attack that cuts each once (Targets.hit_key())."""
	return -get_instance_id()


func _draw() -> void:
	if not broken:
		return
	var t: float = 1.0 - clampf(_break_left / BREAK_SECONDS, 0.0, 1.0)
	var colour := Color(0.85, 0.75, 1.0, 1.0 - t)
	draw_arc(Vector2(0, -6), 6.0 + 26.0 * t, 0.0, TAU, 32, colour, 2.0)
	draw_arc(Vector2(0, -6), 3.0 + 14.0 * t, 0.0, TAU, 24, Color(1, 1, 1, (1.0 - t) * 0.8), 1.5)
