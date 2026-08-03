# slashwave.gd — sword-wave projectile fired by the warrior on every attack swing.
# uses 4 separate directional animations (slashleft / slashright / slashup /
# slashdown) so no sprite rotation is needed — each direction has its own art.
#
# usage:
# - warrior instantiates the scene and calls add_child
# - then calls shoot(direction_string) which sets direction + plays animation
# - the wave moves in a straight line until hit, screen exit, or impact
# - NEW: warrior also sets `caster` right after spawning, so a successful
#   hit can grant magic XP back to whoever fired it (see MAGIC XP below).
#
# damage rules (different from arrow/fire/magic):
# - damages enemies, NOT players (warrior wave is friendly fire-free)
# - PASSES THROUGH the player without despawning — wave continues past warrior
# - despawns on any other body (walls, props) or first enemy hit
# - despawns when fully off-screen via VisibleOnScreenNotifier2D
#
# animation timing:
# the slash animation is played in shoot() rather than _ready() because
# direction_name isn't known until shoot() is called by the warrior. _ready
# fires at add_child time, BEFORE the warrior sets the direction.
#
# MAGIC XP ON HIT (NEW):
# the slashwave is the ranged/magic-flavored half of warrior's kit — basic
# melee swings already grant attack XP (see warrior.gd's _try_damage()).
# a successful slashwave hit grants magic_xp_on_hit magic XP to `caster`,
# if one was set. caster is optional and defensively checked (has_method)
# so this scene doesn't hard-require a specific caller — if nothing sets
# caster, hits just deal damage with no XP granted, same as before.
extends Area2D
class_name SlashWave


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# travel speed in pixels per second
@export var speed: float = 350.0

# damage dealt to enemies on contact
@export var damage: int = 15

# damage type for the elemental system. StringName literals (&"physical") are
# faster than regular Strings for equality checks — important for damage
# resolution paths that run per-hit.
@export var damage_type: StringName = &"physical"

# NEW: magic XP granted to `caster` on a successful enemy hit. matches
# melee's hardcoded gain_attack_xp(5) for parity — tune independently if
# ranged/magic progression should feel faster or slower than melee.
@export var magic_xp_on_hit: int = 5


# =============================================================================
# STATE
# =============================================================================

# direction of travel, set by shoot() or shoot_vector() before motion begins
var direction: Vector2 = Vector2.ZERO

# cardinal direction name for animation lookup ("left", "right", "up", "down").
# kept in sync with `direction` so the animation matches the travel direction.
var direction_name: String = "down"

# NEW: whoever fired this wave — set by the caster right after instantiate,
# e.g. warrior.gd's _spawn_slashwave() does `wave.caster = self`. optional;
# defensively checked before use, so this scene works fine without one.
var caster: Node = null


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# only collision signals get wired here — animation play moved to shoot()
	# because direction_name isn't known until the warrior calls shoot()
	# AFTER add_child. wiring here vs editor signals is preference; the
	# guard against double-connection covers both bases.
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	# straight-line motion at constant velocity. direction is pre-normalized
	# in shoot() / shoot_vector() so no per-frame normalization needed.
	position += direction * speed * delta


# =============================================================================
# AIM / FIRING
# =============================================================================

func shoot(dir: String) -> void:
	# cardinal-direction interface — primary path used by warrior.gd.
	# sets direction vector + name, then plays the matching animation.
	direction_name = dir
	match dir:
		"left":  direction = Vector2.LEFT
		"right": direction = Vector2.RIGHT
		"up":    direction = Vector2.UP
		"down":  direction = Vector2.DOWN
	_play_directional_animation()


func shoot_vector(dir: Vector2) -> void:
	# arbitrary-angle interface for future warrior abilities (rotational
	# strike, follow-up combo waves, etc.). snaps the angle to nearest
	# cardinal for animation lookup since we only have 4 directional sprites.
	direction = dir.normalized()
	if abs(direction.x) > abs(direction.y):
		direction_name = "right" if direction.x > 0 else "left"
	else:
		direction_name = "down" if direction.y > 0 else "up"
	_play_directional_animation()


func _play_directional_animation() -> void:
	# play the slash animation matching direction_name.
	# falls back to a generic "slash" animation if the directional one
	# isn't defined — keeps the wave from rendering blank during dev.
	if not has_node("animatedsprite2d"):
		return

	var sprite: AnimatedSprite2D = $animatedsprite2d
	var anim_name: String = "slash" + direction_name

	if sprite.sprite_frames.has_animation(anim_name):
		sprite.play(anim_name)
	elif sprite.sprite_frames.has_animation("slash"):
		sprite.play("slash")
	else:
		push_warning("SlashWave: no slash animation found for '%s'" % anim_name)


# =============================================================================
# COLLISION HANDLERS
# =============================================================================

func _on_body_entered(body: Node2D) -> void:
	# hit logic differs from enemy projectiles:
	# - enemies: deal damage and despawn (one wave = one enemy hit)
	# - player: pass through (no friendly fire, wave continues past warrior)
	# - everything else (walls, props): despawn on contact
	if body.is_in_group(&"enemies") and body.has_method(&"take_damage"):
		body.take_damage(damage, damage_type)
		_grant_caster_magic_xp()
		destroy_wave()
		return

	# pass through the player without despawning
	if body.is_in_group(&"player"):
		return

	# any other body (walls, props) — despawn to prevent pass-through
	destroy_wave()


func _on_area_entered(area: Area2D) -> void:
	# area hit (typically an enemy hurtbox) — damage the parent if it's
	# an enemy with take_damage. wave despawns on first hit either way.
	var target: Node = area.get_parent()
	if target == null:
		return
	if target.is_in_group(&"enemies") and target.has_method(&"take_damage"):
		target.take_damage(damage, damage_type)
		_grant_caster_magic_xp()
		destroy_wave()


func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	# despawn when fully off-screen — prevents leaked waves from
	# accumulating if a swing misses and the wave flies off the map.
	destroy_wave()


# =============================================================================
# MAGIC XP
# =============================================================================

func _grant_caster_magic_xp() -> void:
	if caster != null and caster.has_method("gain_magic_xp"):
		caster.gain_magic_xp(magic_xp_on_hit)


# =============================================================================
# CLEANUP
# =============================================================================

func destroy_wave() -> void:
	# single cleanup point — add impact particles, slash sound, hit-stop
	# screen pause, etc. here later. centralizing means you only have to
	# wire visual feedback in one place.
	queue_free()
