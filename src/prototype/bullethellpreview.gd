# bullethellpreview.gd - the Crowned Beholder at bullet-hell density, to play.
#
# A PREVIEW, NOT WIRED INTO THE GAME: nothing loads this scene, it talks to no
# server and it saves nothing. Open scene/prototype/bullethellpreview.tscn and
# press F6.
#
#   WASD / arrows  move            Shift  focus: slow, and shows the hitbox
#   Space          dash            1-5    how dense
#   Z              zoom 2x / 3x    R      reset the counters
#
# What it is for:
#   - FEEL. A tiny hitbox, focus and a dash against the Beholder's colours,
#     in six patterns: rings, a spiral, a flower, aimed fans, a falling wall
#     with a gap, and curving orbs.
#   - NUMBERS. The corner shows bullets on screen and what moving them cost
#     this frame, so the same scene can be timed in the editor and in a
#     browser build.
#   - ZOOM. The game draws at 3x. Bullet hell needs room to read a pattern
#     coming, and 2x shows over twice the floor. Z flips between them.
#
# Two command-line switches, for running it without anybody at the keys
# (after `--`, e.g. `godot --path . res://scene/prototype/bullethellpreview.tscn -- --demo`):
#   --demo   an autopilot dodges and the density climbs on its own: for recordings
#   --bench  times the bullet field at every density and the game's own arrow
#            scene at the same counts, prints the table, and quits. Headless is fine.
extends Node2D


const ARENA: Rect2 = Rect2(-280.0, -160.0, 560.0, 320.0)

const LEVELS: Array[Dictionary] = [
	{"name": "Today's boss", "density": 0.35, "at_once": 1},
	{"name": "Hard", "density": 1.0, "at_once": 1},
	{"name": "Bullet hell", "density": 1.8, "at_once": 2},
	{"name": "Hardcore", "density": 3.0, "at_once": 2},
	{"name": "Stress test", "density": 6.0, "at_once": 3},
]

# A new cast this often, divided by how many run at once.
const CAST_EVERY: float = 4.2
# The warning before a cast: the Beholder starts its cast animation and a ring
# closes on it. A bullet hell is fair when every big attack is announced.
const TELEGRAPH: float = 0.6

const MOVE_SPEED: float = 90.0     # the game's own base speed (player.gd)
const FOCUS_SPEED: float = 42.0
const DASH_SPEED: float = 330.0
const DASH_SECONDS: float = 0.16
const DASH_UNTOUCHABLE: float = 0.24
const DASH_COOLDOWN: float = 0.9
# After a hit, how long bullets pass through. The owner, 12 Oct: "i want more
# hits to hit player reduce the time to 0.50 sec" - it was 1.0. The Field
# itself uses BulletZone.CHIP_MERCY (0.1 since 0.23.1).
const HIT_UNTOUCHABLE: float = 0.5

# The player's hitbox: a few pixels at the chest, about the size of the real
# hurtbox (warrior.tscn's capsule is 3 wide), drawn when focusing.
const HITBOX_RADIUS: float = 2.0
const HITBOX_OFFSET: Vector2 = Vector2(1.0, 2.0)
const GRAZE_RADIUS: float = 12.0

const KINDS: Array[int] = [
	BulletPattern.Kind.RING, BulletPattern.Kind.SPIRAL, BulletPattern.Kind.FAN,
	BulletPattern.Kind.FLOWER, BulletPattern.Kind.RAIN, BulletPattern.Kind.GALAXY,
]

const FLOOR: Color = Color(0.17, 0.16, 0.19)
const FLOOR_LINE: Color = Color(0.2, 0.19, 0.23)
const WALL: Color = Color(0.1, 0.09, 0.12)
const TRIM: Color = Color(0.36, 0.31, 0.4)


class Overlay extends Node2D:
	# Drawn above the bullets: the warning ring and the player's hitbox.
	var host: Node = null

	func _draw() -> void:
		if host != null:
			host.draw_overlay(self)


var field: BulletField = null
var level: int = 2
var clock: float = 0.0

var _boss: Node2D = null
var _boss_sprite: AnimatedSprite2D = null
var _player: Node2D = null
var _player_sprite: AnimatedSprite2D = null
var _camera: Camera2D = null
var _overlay: Overlay = null
var _top_label: Label = null
var _help_label: Label = null

var _casts: Array[BulletPattern] = []
var _cast_index: int = 0
var _next_cast_at: float = 1.0
var _telegraph_until: float = -1.0
var _last_cast_line: String = ""

var _facing: String = "down"
var _focus: bool = false
var _dash_left: float = 0.0
var _dash_dir: Vector2 = Vector2.DOWN
var _dash_ready_at: float = 0.0
var _untouchable_until: float = 0.0
var _zoom_three: bool = false

var _hits: int = 0
var _grazes: int = 0
var _since_hit: float = 0.0
var _best_since_hit: float = 0.0

var _demo: bool = false
var _bench: bool = false
var _auto_dir: Vector2 = Vector2.ZERO
var _auto_focus: bool = false
var _auto_think: float = 0.0
var _fps_shown: float = 60.0
var _bench_field_on: bool = false


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_demo = args.has("--demo")
	_bench = args.has("--bench")

	# DRAW ORDER IS A DESIGN CHOICE. The player is drawn under the bullets, so
	# no bullet hides behind the sprite; the Beholder over them, so its body is
	# never lost in its own spiral; the hitbox over everything (the overlay).
	field = BulletField.new()
	field.name = "field"
	# Gone at the wall: a bullet is never removed while it can be seen, and
	# never drawn over the wall either.
	field.bounds = ARENA.grow(2.0)

	_boss = Node2D.new()
	_boss.name = "boss"
	_boss.position = Vector2(0.0, -80.0)
	_boss_sprite = _sprite_from("res://scene/enemy/bossenemy.tscn", "idledown")
	_boss.add_child(_boss_sprite)

	_player = Node2D.new()
	_player.name = "player"
	_player.position = Vector2(0.0, 100.0)
	_player_sprite = _sprite_from("res://scene/characters/warrior.tscn", "idledown")
	_player_sprite.position = Vector2(0.0, 13.0)
	_player_sprite.offset = Vector2(0.0, -16.0)
	_player.add_child(_player_sprite)
	add_child(_player)
	add_child(field)
	add_child(_boss)

	_overlay = Overlay.new()
	_overlay.name = "overlay"
	_overlay.host = self
	add_child(_overlay)

	_camera = Camera2D.new()
	_camera.zoom = Vector2(2.0, 2.0)
	add_child(_camera)
	_camera.make_current()

	_build_hud()
	if _demo:
		level = 1
	if _bench:
		_run_bench.call_deferred()


func _process(delta: float) -> void:
	if _bench:
		if _bench_field_on:
			field.step(delta, Vector2(0.0, 999.0), HITBOX_RADIUS, GRAZE_RADIUS, false)
		return
	clock += delta
	if _demo:
		_demo_schedule()

	_move_boss()
	_schedule_casts()
	# Back to idle a moment after the cast leaves, whether or not the cast
	# animation loops.
	if _boss_sprite.animation == &"castdown" and clock > _telegraph_until + 0.5:
		_play(_boss_sprite, "idledown")
	for cast in _casts:
		cast.update(clock, field, _boss.position, _player.position + HITBOX_OFFSET)
	_casts = _casts.filter(func(c: BulletPattern) -> bool: return not c.done())

	_move_player(delta)
	var untouchable: bool = clock < _untouchable_until
	var result: Vector2i = field.step(delta, _player.position + HITBOX_OFFSET, HITBOX_RADIUS,
		GRAZE_RADIUS, untouchable)
	_grazes += result.y
	if result.x > 0:
		_on_hit()
	else:
		_since_hit += delta
		_best_since_hit = maxf(_best_since_hit, _since_hit)

	_update_camera()
	_update_hud(delta)
	_overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			level = key.keycode - KEY_1
		KEY_Z:
			_zoom_three = not _zoom_three
		KEY_R:
			_hits = 0
			_grazes = 0
			_since_hit = 0.0
			_best_since_hit = 0.0
			field.clear()


# =============================================================================
# THE BOSS
# =============================================================================

func _move_boss() -> void:
	# A slow figure-eight across the top of the arena: on a clock, so it is in
	# the same place on every screen too.
	_boss.position = Vector2(sin(clock * 0.37) * 150.0, -82.0 + sin(clock * 0.74) * 18.0)


func _schedule_casts() -> void:
	var settings: Dictionary = LEVELS[level]
	if clock >= _next_cast_at - TELEGRAPH and _telegraph_until < _next_cast_at:
		_telegraph_until = _next_cast_at
		_play(_boss_sprite, "castdown")
	if clock < _next_cast_at:
		return
	var kind: int = KINDS[_cast_index % KINDS.size()]
	var cast_seed: int = 7919 * _cast_index + 104729
	var cast: BulletPattern = BulletPattern.make(kind, cast_seed, _next_cast_at,
		float(settings["density"]), ARENA)
	_casts.append(cast)
	_last_cast_line = "cast %d: %s, seed %d, at %.2f s" % [_cast_index, cast.title(), cast_seed, cast.start]
	_cast_index += 1
	_next_cast_at += CAST_EVERY / float(settings["at_once"])


# =============================================================================
# THE PLAYER
# =============================================================================

func _move_player(delta: float) -> void:
	var wanted: Vector2 = Vector2.ZERO
	var dash_pressed: bool = false
	if _demo:
		_think(delta)
		wanted = _auto_dir
		_focus = _auto_focus
	else:
		wanted = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if wanted == Vector2.ZERO:
			wanted = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		_focus = Input.is_key_pressed(KEY_SHIFT)
		dash_pressed = Input.is_key_pressed(KEY_SPACE)

	if dash_pressed and clock >= _dash_ready_at and wanted != Vector2.ZERO:
		_dash_left = DASH_SECONDS
		_dash_dir = wanted.normalized()
		_dash_ready_at = clock + DASH_COOLDOWN
		_untouchable_until = maxf(_untouchable_until, clock + DASH_UNTOUCHABLE)

	var velocity: Vector2 = Vector2.ZERO
	if _dash_left > 0.0:
		_dash_left -= delta
		velocity = _dash_dir * DASH_SPEED
	elif wanted != Vector2.ZERO:
		velocity = wanted.normalized() * (FOCUS_SPEED if _focus else MOVE_SPEED)

	var inner: Rect2 = ARENA.grow(-10.0)
	_player.position = (_player.position + velocity * delta).clamp(inner.position, inner.end)

	if velocity != Vector2.ZERO:
		_facing = _facing_of(velocity)
		_play(_player_sprite, "walk" + _facing)
	else:
		_play(_player_sprite, "idle" + _facing)

	var blinking: bool = clock < _untouchable_until and _dash_left <= 0.0
	_player_sprite.modulate.a = 0.35 if blinking and int(clock * 12.0) % 2 == 0 else 1.0
	if _dash_left > 0.0:
		_player_sprite.modulate = Color(0.7, 0.9, 1.0, 0.6)
	elif not blinking:
		_player_sprite.modulate = Color.WHITE


func _on_hit() -> void:
	_hits += 1
	_since_hit = 0.0
	_untouchable_until = clock + HIT_UNTOUCHABLE
	_player_sprite.modulate = Color(1.0, 0.35, 0.35)


func _facing_of(v: Vector2) -> String:
	if absf(v.x) > absf(v.y):
		return "right" if v.x > 0.0 else "left"
	return "down" if v.y > 0.0 else "up"


# =============================================================================
# THE AUTOPILOT (--demo)
# =============================================================================

func _demo_schedule() -> void:
	# The recording climbs: hard, bullet hell, hardcore, then the stress test.
	var wanted: int = 1
	if clock > 7.0:
		wanted = 2
	if clock > 16.0:
		wanted = 3
	if clock > 25.0:
		wanted = 4
	level = wanted


func _think(delta: float) -> void:
	# Ten times a second, try seventeen moves - still, and sixteen directions at
	# both speeds' worth of travel - and take the one whose landing spot will
	# hold the fewest bullets, with a pull back toward the lower middle so it
	# does not get pinned in a corner. Good enough to film, not to beat.
	_auto_think -= delta
	if _auto_think > 0.0:
		return
	_auto_think = 0.1
	var here: Vector2 = _player.position + HITBOX_OFFSET
	var home: Vector2 = Vector2(0.0, 90.0)
	var best_score: float = INF
	var best_dir: Vector2 = Vector2.ZERO
	var best_focus: bool = false
	for k in 17:
		var dir: Vector2 = Vector2.ZERO if k == 16 else Vector2.from_angle(TAU * k / 16.0)
		for slow in [true, false]:
			if k == 16 and not slow:
				continue
			var speed: float = FOCUS_SPEED if slow else MOVE_SPEED
			var spot: Vector2 = (here + dir * speed * 0.3).clamp(ARENA.position + Vector2(14, 14),
				ARENA.end - Vector2(14, 14))
			var score: float = field.danger_at(spot, 0.3, 30.0) * 40.0 \
				+ field.danger_at(spot, 0.15, 18.0) * 80.0 \
				+ spot.distance_squared_to(home) * 0.00002
			if dir.dot(_auto_dir) > 0.5:
				score *= 0.9
			if score < best_score:
				best_score = score
				best_dir = dir
				best_focus = slow
	_auto_dir = best_dir
	_auto_focus = best_focus and best_dir != Vector2.ZERO


# =============================================================================
# DRAWING
# =============================================================================

func _draw() -> void:
	draw_rect(ARENA.grow(40.0), Color(0.07, 0.07, 0.07))
	draw_rect(ARENA.grow(6.0), WALL)
	draw_rect(ARENA.grow(3.0), TRIM)
	draw_rect(ARENA, FLOOR)
	var x: float = ARENA.position.x + 16.0
	while x < ARENA.end.x:
		draw_line(Vector2(x, ARENA.position.y), Vector2(x, ARENA.end.y), FLOOR_LINE, 1.0)
		x += 16.0
	var y: float = ARENA.position.y + 16.0
	while y < ARENA.end.y:
		draw_line(Vector2(ARENA.position.x, y), Vector2(ARENA.end.x, y), FLOOR_LINE, 1.0)
		y += 16.0


func draw_overlay(canvas: Node2D) -> void:
	# The warning: a ring closing on the Beholder for the TELEGRAPH before a cast.
	var warn: float = _telegraph_until - clock
	if warn > 0.0 and warn <= TELEGRAPH:
		var share: float = warn / TELEGRAPH
		canvas.draw_arc(_boss.position, 14.0 + 46.0 * share, 0.0, TAU, 32,
			Color(1.0, 0.3, 0.42, 0.85 - 0.5 * share), 2.0)
	# The hitbox, while focusing: what actually has to miss.
	if _focus:
		var at: Vector2 = _player.position + HITBOX_OFFSET
		canvas.draw_arc(at, HITBOX_RADIUS + GRAZE_RADIUS, 0.0, TAU, 24, Color(1, 1, 1, 0.18), 1.0)
		canvas.draw_circle(at, HITBOX_RADIUS + 1.0, Color(1.0, 0.25, 0.3))
		canvas.draw_circle(at, HITBOX_RADIUS, Color.WHITE)


func _update_camera() -> void:
	if _zoom_three:
		_camera.zoom = Vector2(3.0, 3.0)
		var half: Vector2 = get_viewport_rect().size / 6.0
		var lo: Vector2 = ARENA.position + half - Vector2(6, 6)
		var hi: Vector2 = ARENA.end - half + Vector2(6, 6)
		_camera.position = Vector2(clampf(_player.position.x, lo.x, maxf(lo.x, hi.x)),
			clampf(_player.position.y, lo.y, maxf(lo.y, hi.y)))
	else:
		_camera.zoom = Vector2(2.0, 2.0)
		_camera.position = ARENA.get_center()


func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var style: LabelSettings = LabelSettings.new()
	style.font_size = 15
	style.outline_size = 5
	style.outline_color = Color(0, 0, 0, 0.9)
	_top_label = Label.new()
	_top_label.label_settings = style
	_top_label.position = Vector2(12, 8)
	layer.add_child(_top_label)
	_help_label = Label.new()
	_help_label.label_settings = style
	_help_label.position = Vector2(12, 690)
	_help_label.text = "Move: WASD / arrows    Shift: focus (shows hitbox)    Space: dash    1-5: density    Z: zoom 2x / 3x    R: reset"
	layer.add_child(_help_label)


func _update_hud(delta: float) -> void:
	if delta > 0.0:
		_fps_shown = lerpf(_fps_shown, 1.0 / delta, 0.05)
	var settings: Dictionary = LEVELS[level]
	var dash_text: String = "ready" if clock >= _dash_ready_at else "%.1f s" % (_dash_ready_at - clock)
	_top_label.text = "\n".join([
		"BULLET HELL PREVIEW   density %d/5: %s   zoom %dx" % [level + 1, settings["name"], 3 if _zoom_three else 2],
		"bullets on screen: %d    moving them: %.2f ms    fps: %d" % [field.count,
			field.last_step_usec / 1000.0, roundi(_fps_shown)],
		"hits: %d    grazes: %d    without a hit: %.1f s (best %.1f s)    dash: %s" % [_hits, _grazes,
			_since_hit, _best_since_hit, dash_text],
		"%s   <- all another player's game would need" % _last_cast_line,
	])


func _sprite_from(scene_path: String, animation: String) -> AnimatedSprite2D:
	# The game's own SpriteFrames, read out of the scene WITHOUT instancing it,
	# so none of the boss's or the warrior's scripts run here.
	var sprite: AnimatedSprite2D = AnimatedSprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return sprite
	var state: SceneState = packed.get_state()
	for n in state.get_node_count():
		if state.get_node_type(n) != &"AnimatedSprite2D":
			continue
		for p in state.get_node_property_count(n):
			if state.get_node_property_name(n, p) == &"sprite_frames":
				sprite.sprite_frames = state.get_node_property_value(n, p) as SpriteFrames
	_play(sprite, animation)
	return sprite


func _play(sprite: AnimatedSprite2D, animation: String) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	if not sprite.sprite_frames.has_animation(animation):
		return
	if sprite.animation != animation or not sprite.is_playing():
		sprite.play(animation)


# =============================================================================
# THE BENCHMARK (--bench)
# =============================================================================

func _run_bench() -> void:
	# Everything here is frame by frame on purpose: process_frame is awaited so
	# the engine really runs its frame (physics included, for the arrows)
	# between measurements. Run with --fixed-fps 60 for a steady clock.
	print("[BENCH] the bullet field at each density, 10 s each, player untouchable")
	for index in LEVELS.size():
		level = index
		field.clear()
		_casts.clear()
		clock = 0.0
		_cast_index = 0
		_next_cast_at = 0.5
		_telegraph_until = -1.0
		var steps: Array[int] = []
		var peak: int = 0
		for frame in 600:
			var delta: float = 1.0 / 60.0
			clock += delta
			_move_boss()
			_schedule_casts()
			for cast in _casts:
				cast.update(clock, field, _boss.position, _player.position)
			_casts = _casts.filter(func(c: BulletPattern) -> bool: return not c.done())
			field.step(delta, _player.position, HITBOX_RADIUS, GRAZE_RADIUS, true)
			if frame >= 180:
				steps.append(field.last_step_usec)
				peak = maxi(peak, field.count)
			await get_tree().process_frame
		steps.sort()
		var total: int = 0
		for s in steps:
			total += s
		print("[BENCH] field  %-13s peak %5d bullets   avg %.2f ms   95%% %.2f ms" % [LEVELS[index]["name"],
			peak, total / 1000.0 / steps.size(), steps[int(steps.size() * 0.95)] / 1000.0])

	print("[BENCH] the same counts two ways: the field, and the game's arrow scene (one node each)")
	field.clear()
	_casts.clear()
	var arrow_scene: PackedScene = load("res://scene/projectiles/arrow.tscn") as PackedScene
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345
	# WALL-CLOCK FRAMES, both ways and with nothing at all, so each is charged
	# only for itself: script, physics and everything the engine does per node.
	var idle: float = await _frame_ms(90)
	print("[BENCH] an empty frame: %.2f ms" % idle)
	for n in [250, 500, 1000, 2000, 4000, 8000]:
		field.clear()
		for k in n:
			field.spawn(Vector2(rng.randf_range(-250, 250), rng.randf_range(-140, 140)),
				rng.randf_range(0.0, TAU), 12.0, BulletPattern.VIOLET, false, 0.0, 0.0, 600.0)
		_bench_field_on = true
		var field_ms: float = await _frame_ms(90)
		_bench_field_on = false
		field.clear()

		var node_ms: float = -1.0
		if arrow_scene != null and n <= 4000:
			var holder: Node2D = Node2D.new()
			add_child(holder)
			for k in n:
				var arrow: Node = arrow_scene.instantiate()
				arrow.set("speed", 12.0)
				arrow.set("lifetime", 600.0)
				holder.add_child(arrow)
				(arrow as Node2D).position = Vector2(rng.randf_range(-250, 250), rng.randf_range(-140, 140))
				arrow.call("shoot_vector", Vector2.from_angle(rng.randf_range(0.0, TAU)))
			await _frame_ms(10)
			node_ms = await _frame_ms(60)
			holder.queue_free()
			await get_tree().process_frame
		print("[BENCH] %5d bullets   field %6.2f ms   arrow nodes %s a frame" % [n,
			maxf(0.0, field_ms - idle),
			"%6.2f ms" % maxf(0.0, node_ms - idle) if node_ms >= 0.0 else "   (not run)"])
	print("[BENCH] done")
	get_tree().quit()


func _frame_ms(frames: int) -> float:
	# The average wall-clock length of the next `frames` frames.
	var started: int = Time.get_ticks_usec()
	for frame in frames:
		await get_tree().process_frame
	return (Time.get_ticks_usec() - started) / 1000.0 / frames
