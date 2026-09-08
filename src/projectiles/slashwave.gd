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
# - CLEAVES: damages every enemy it passes through, each one only once.
#   max_pierce caps how many; 0 means unlimited. this is why the wave keeps
#   a record of who it has already struck — see _try_hit().
# - despawns on any other body (walls, props)
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
# HITBOX GEOMETRY
# =============================================================================
# NEW: per-direction hitbox, measured from the actual visible pixels of each
# slash sprite.
#
# THE BUG THIS FIXES: the scene ships a single CircleShape2D with radius 32 —
# a 64x64 hit area — used for all four directions. But the art is a thin
# directional slash: 50x17 horizontally, 39x29 vertically, drawn off-centre
# on a 64x64 canvas. So the hitbox stuck out well past the visible wave,
# worst of all PERPENDICULAR to the slash, where a horizontal wave was
# nearly four times taller in collision than in pixels.
#
# The symptom was the wave appearing to vanish before reaching an enemy
# while the enemy still took damage — which is exactly right, because the
# hit was real. The oversized circle touched the enemy, dealt damage and
# despawned the wave, all while the art was still short of the target.
#
# Sizes and offsets are in the Area2D's own space, i.e. sprite-local pixels
# recentred on the 64x64 canvas plus the (0, 8) offset both the sprite and
# the collision node already carry in the scene.
# CHANGED AGAIN: these were briefly pixel-exact to each sprite's bounding
# box, which was wrong for a different reason. A slash wave is an AREA
# sweep, and what decides how many enemies it catches is its extent
# PERPENDICULAR to travel — how wide a swathe the blade covers — not its
# bounding box.
#
# Measured off the art, that perpendicular sweep was wildly asymmetric:
#
#     slashup / slashdown      38px sweep   (a proper wide crescent)
#     slashleft / slashright   16px sweep   (a thin flat streak, mostly tail)
#
# So swinging vertically cleaved a swathe more than TWICE as wide as
# swinging horizontally — same ability, same mana, less than half the
# coverage depending on which way you happened to face. That's an art
# asymmetry, not a code one, but it plays as a bug.
#
# These rects give all four directions the same 38px sweep (the width the
# vertical arcs already had) and anchor the box on the CRESCENT — the
# leading edge that does the cutting — rather than on the trailing streak,
# which shouldn't damage anything.
#
# KNOWN TRADEOFF: because the horizontal art really is only ~17px tall, its
# hitbox is now taller than its visible pixels. That is deliberate — it
# buys consistent coverage — but it means a left/right wave can catch an
# enemy slightly above or below the visible streak. The proper fix is
# redrawing slashleft/slashright as full crescents to match slashup and
# slashdown; then these numbers describe the art exactly.
#
# Sizes and offsets are in the Area2D's own space: sprite-local pixels
# recentred on the 64x64 canvas, plus the (0, 8) offset the sprite and
# collision nodes already carry in the scene.
const HITBOX_RECTS := {
	"right": { "size": Vector2(18, 38), "offset": Vector2( 13.0,  12.5) },
	"left":  { "size": Vector2(18, 38), "offset": Vector2(-19.0,  12.5) },
	"up":    { "size": Vector2(38, 18), "offset": Vector2( -0.5,  -7.0) },
	"down":  { "size": Vector2(38, 18), "offset": Vector2( -0.5,  20.0) },
}


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

# NEW: the impact flourish. destroy_wave() used to be a bare queue_free(),
# so a connecting wave blinked out of existence with nothing to sell the
# hit — which reads as the wave vanishing early even when the hitbox is
# perfectly aligned. It now swells slightly and dissolves on contact,
# built from the sprite already in the scene rather than new art.
#
# Keep it SHORT. This fires on every swing that connects, and anything
# long enough to admire becomes something to sit through.
@export var impact_duration: float = 0.12
@export var impact_scale: float = 1.35

# NEW: how many enemies one wave may strike before it despawns.
# 0 = unlimited — it cleaves through everything in its path and only stops
# at a wall or the edge of the screen.
#
# This is the balance dial for the whole ability. Every enemy struck is a
# full `damage` hit AND another `magic_xp_on_hit` to the caster, so against
# a tight group the swing's value scales linearly with how many bodies are
# lined up. Mana cost is per SWING, not per enemy (see warrior.gd's
# slashwave_mana_cost), so packs are where the warrior gets paid.
@export var max_pierce: int = 0

# NEW: scales the whole hitbox up or down without editing HITBOX_RECTS.
# 1.0 = the measured values. Raise it if the wave still feels like it's
# missing enemies it visually swept through; lower it if it starts catching
# things it clearly shouldn't. This is the knob to reach for first.
@export var hitbox_scale: float = 1.0


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

# NEW: true once this wave is despawning and playing its dissolve out.
# Stops destroy_wave() running twice, and stops the collision handlers
# doing any more work while the sprite fades.
var _is_dying: bool = false

# NEW: instance IDs of every enemy this wave has already damaged. See
# _try_hit() for why this exists and why it stores IDs rather than nodes.
var _hit_targets: Array[int] = []

# NEW: the sprite's authored scale, captured before anything animates it.
# Both the per-hit pulse and the dissolve scale FROM this rather than from
# the sprite's current scale, so repeated hits can't compound.
var _base_scale: Vector2 = Vector2.ONE

# NEW: the running per-hit pulse, kept so a fresh hit can cancel it instead
# of stacking a second tween on the same property.
var _pulse_tween: Tween = null


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

	# NEW: remember the authored scale before any tween touches it — see
	# _base_scale's comment.
	var sprite: AnimatedSprite2D = get_node_or_null("animatedsprite2d")
	if sprite != null:
		_base_scale = sprite.scale


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
	_apply_directional_hitbox()


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
	_apply_directional_hitbox()


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


func _apply_directional_hitbox() -> void:
	# NEW: resize the collision shape to match the slash art for whichever
	# direction this wave is travelling. See HITBOX_RECTS above for why the
	# single 64x64 circle in the scene was wrong.
	var shape_node: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if shape_node == null:
		return

	var spec: Dictionary = HITBOX_RECTS.get(direction_name, {})
	if spec.is_empty():
		return

	# A FRESH shape per wave, deliberately. Shapes are Resources, and the one
	# authored in slashwave.tscn is shared by every instance of the scene —
	# mutating it in place would resize every other wave currently in flight,
	# and the change would persist into the next one spawned.
	var rect := RectangleShape2D.new()
	rect.size = spec["size"] * hitbox_scale

	shape_node.shape = rect
	# the offset scales too, so growing the hitbox keeps it centred on the
	# crescent instead of drifting back toward the wave's origin.
	shape_node.position = spec["offset"] * hitbox_scale


# =============================================================================
# COLLISION HANDLERS
# =============================================================================

func _on_body_entered(body: Node2D) -> void:
	# hit logic differs from enemy projectiles:
	# - enemies: deal damage and KEEP GOING (see _try_hit / max_pierce)
	# - player: pass through (no friendly fire, wave continues past warrior)
	# - everything else (walls, props): despawn on contact
	if _is_dying:
		return

	if body.is_in_group(&"enemies"):
		_try_hit(body)
		return

	# pass through the player without despawning
	if body.is_in_group(&"player"):
		return

	# any other body (walls, props) — despawn to prevent pass-through
	destroy_wave()


func _on_area_entered(area: Area2D) -> void:
	# area hit (typically an enemy hurtbox) — the enemy itself is the area's
	# parent. routed through the same _try_hit() as body contact so an enemy
	# with BOTH a body and a hurtbox can't be counted twice.
	if _is_dying:
		return

	var target: Node = area.get_parent()
	if target == null:
		return
	if target.is_in_group(&"enemies"):
		_try_hit(target)


# =============================================================================
# HIT RESOLUTION
# =============================================================================

func _try_hit(target: Node) -> void:
	# NEW: the wave CLEAVES — it damages an enemy and keeps travelling
	# instead of despawning on first contact.
	#
	# _hit_targets is what makes that safe. A wave takes several physics
	# frames to pass through a body, and an enemy with both a
	# CharacterBody2D and a hurtbox Area2D fires two separate signals for
	# the same creature. Without a record of who's already been struck,
	# either of those means one enemy soaking the full damage repeatedly
	# from a single swing.
	#
	# Instance IDs rather than node references: an enemy killed by this very
	# wave gets freed, and a freed node is a dangling reference that throws
	# the moment anything touches it. An int stays an int.
	if not target.has_method(&"take_damage"):
		return

	var target_id: int = target.get_instance_id()
	if target_id in _hit_targets:
		return
	_hit_targets.append(target_id)

	target.take_damage(damage, damage_type)
	_grant_caster_magic_xp()
	_play_hit_pulse()

	# max_pierce = 0 means unlimited — the wave runs until it meets a wall
	# or leaves the screen.
	if max_pierce > 0 and _hit_targets.size() >= max_pierce:
		destroy_wave()


func _play_hit_pulse() -> void:
	# NEW: per-hit feedback that does NOT kill the wave. The dissolve in
	# destroy_wave() reads as "this attack is over", which is wrong now that
	# a wave survives its first hit — a cleave needs to register each
	# connection while staying on screen. So: a quick swell and settle.
	#
	# Scales from _base_scale rather than the sprite's CURRENT scale, so
	# rapid hits on a crowd can't compound into a comically growing wave.
	var sprite: AnimatedSprite2D = get_node_or_null("animatedsprite2d")
	if sprite == null:
		return

	# restart cleanly if a previous pulse is still running — two tweens
	# animating the same property fight each other.
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()

	sprite.scale = _base_scale
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(sprite, "scale", _base_scale * impact_scale, impact_duration * 0.35) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_pulse_tween.tween_property(sprite, "scale", _base_scale, impact_duration * 0.65) \
		.set_ease(Tween.EASE_IN_OUT)


func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	# despawn when fully off-screen — prevents leaked waves from
	# accumulating if a swing misses and the wave flies off the map.
	# CHANGED: skips the impact flourish. This isn't a hit, and the wave is
	# off-camera by definition, so there'd be nothing to see.
	destroy_wave(false)


# =============================================================================
# MAGIC XP
# =============================================================================

func _grant_caster_magic_xp() -> void:
	if caster != null and caster.has_method("gain_magic_xp"):
		caster.gain_magic_xp(magic_xp_on_hit)


# =============================================================================
# CLEANUP
# =============================================================================

func destroy_wave(with_impact: bool = true) -> void:
	# single cleanup point. CHANGED: was a bare queue_free().
	#
	# with_impact = false skips the flourish entirely — used by the
	# screen-exit path, where the wave is off-camera and animating it would
	# just be work nobody sees.
	if _is_dying:
		return
	_is_dying = true

	if not with_impact:
		queue_free()
		return

	# Stop dead before the flourish plays: motion off so it doesn't drift
	# past the thing it just hit, collisions off so the fading sprite can't
	# register more hits.
	#
	# set_deferred() rather than direct assignment because this runs inside
	# a collision callback, and changing physics state there throws
	# "Can't change this state while flushing queries". The _is_dying guard
	# in the handlers above is what actually stops damage this frame —
	# set_deferred doesn't take effect until the next one.
	direction = Vector2.ZERO
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

	var sprite: AnimatedSprite2D = get_node_or_null("animatedsprite2d")
	if sprite == null:
		queue_free()
		return

	# a per-hit pulse may still be mid-flight; two tweens on the same
	# property fight, and the dissolve has to win.
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()

	# swell + dissolve at the point of contact, so the end of the wave reads
	# as it breaking ON something rather than blinking out just short of it.
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", _base_scale * impact_scale, impact_duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(sprite, "modulate:a", 0.0, impact_duration) \
		.set_ease(Tween.EASE_IN)
	# chain() makes this run AFTER the parallel pair above, not alongside it.
	tween.chain().tween_callback(queue_free)
