# slashwave.gd — sword-wave projectile fired by the warrior on every attack swing.
#
# FIRES AT ANY ANGLE. The warrior aims at the cursor, so there are not four
# directions here, there are 360 degrees of them, and three separate things
# have to agree about that:
#
#   spawn point   warrior.gd offsets it along the exact aim vector    360
#   travel        `direction` keeps the exact vector, unrounded        360
#   hitbox        one box, rotated onto the travel angle               360
#   animation     snapped to the nearest of 4, because 4 were drawn      4
#
# Only the last one snaps, and it is the only one a player cannot feel: a
# diagonal wave shows the leftward slash sprite while flying and cutting
# up-left. When the diagonal art arrives, `direction_name` gains four cases
# and nothing else in this file changes.
#
# usage:
# - warrior instantiates the scene and calls add_child
# - then calls shoot_vector(aim) which sets direction, animation and hitbox
#   (shoot(name) is the cardinal-only convenience form, unused by warrior)
# - the wave moves in a straight line until hit, screen exit, or impact
# - warrior also sets `caster` right after spawning, so a successful hit can
#   grant magic XP back to whoever fired it (see MAGIC XP below).
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
# animation and hitbox timing:
# both are set from the firing call rather than _ready(), because neither the
# direction nor the angle is known until the warrior makes it. _ready() fires
# at add_child time, BEFORE the warrior has said which way this wave is going.
#
# MAGIC XP ON HIT:
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
# ONE hitbox, defined relative to the direction of travel and rotated onto it.
# Not four axis-aligned boxes chosen by cardinal name.
#
# HOW THIS ARRIVED HERE, because the shape of the mistake matters twice:
#
# 1. The scene ships a single CircleShape2D of radius 32 — a 64x64 hit area
#    for every direction. The art is a thin directional slash: 50x17
#    horizontally, 39x29 vertically, drawn off-centre on a 64x64 canvas. So
#    the hitbox stuck out well past the visible wave, worst of all
#    PERPENDICULAR to the slash, where a horizontal wave was nearly four
#    times taller in collision than in pixels. The symptom was the wave
#    appearing to vanish before reaching an enemy while the enemy still took
#    damage — correct behaviour, in fact: the oversized circle really did
#    touch, damage and despawn while the art was still short of the target.
#
# 2. Replacing it with four per-direction rects fixed that for the four
#    cardinals and broke it everywhere else, because the wave does not
#    travel in four directions. shoot_vector() takes any angle, and an
#    axis-aligned box on a diagonal wave sits up to 17px to the SIDE of the
#    line the wave is actually flying along — nearly half a wave-width, on a
#    38px wave. Same failure as the circle, opposite sign: the art sweeps
#    through an enemy and the hitbox misses it.
#
# So the box is described once, in the wave's own frame of reference, and put
# where the wave is going:
#
#     THICKNESS   along travel        — how deep the cutting edge is
#     SWEEP       across travel       — how wide a swathe it cleaves
#     REACH       ahead of the origin — where the crescent sits
#
# SWEEP is 38 for every direction on purpose. Measured off the art it wasn't:
# slashup/slashdown are proper 38px crescents while slashleft/slashright are
# 16px flat streaks that are mostly tail, so swinging vertically cleaved a
# swathe more than twice as wide as swinging horizontally — same ability,
# same mana, less than half the coverage depending on which way you happened
# to be facing. That is an art asymmetry rather than a code one, but it plays
# as a bug, so the code refuses to reproduce it.
#
# KNOWN TRADEOFF, unchanged from when the rects did this: the horizontal art
# really is only ~17px tall, so its hitbox is taller than its visible pixels.
# Deliberate — it buys consistent coverage — but a left/right wave can catch
# an enemy slightly above or below the visible streak. The proper fix is
# redrawing slashleft/slashright as full crescents; then these numbers
# describe the art exactly.
#
# REACH is the average of the four distances the per-direction rects used
# (13, 19, 12, 15). Any single number has to be, now that one box serves every
# angle — the individual values differed because the four sprites are drawn
# off-centre by different amounts, not because the ability reaches further
# to the left.
const HITBOX_THICKNESS: float = 18.0
const HITBOX_SWEEP: float = 38.0
const HITBOX_REACH: float = 15.0

# The wave's visual centre inside this Area2D. The sprite and the authored
# CollisionShape2D both carry this offset in slashwave.tscn, so the hitbox is
# placed from here rather than from the node origin.
const SPRITE_CENTRE := Vector2(0, 8)


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# travel speed in pixels per second
@export var speed: float = 350.0

# damage dealt to enemies on contact
@export var damage: int = 15

# The element this projectile deals. Element.Type is an int, not the
# StringName this used to be: an enum is checked when the file is parsed,
# and &"posion" was only ever going to be found by someone wondering why a
# resistance did nothing.
#
# Overwritten at spawn for anything an enemy fires — see
# BaseEnemy.spawn_projectile_node(), which stamps the caster's element on
# it so a water slime's shot IS water without a second scene existing.
@export var element: int = Element.Type.NONE

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
	# Cardinal-direction convenience interface. NOT the path warrior takes —
	# warrior calls shoot_vector() with the raw cursor aim — but kept because
	# every other projectile in the project offers the same pair, and a future
	# caller that genuinely only knows "left" shouldn't have to build a vector
	# to say so.
	direction_name = dir
	match dir:
		"left":  direction = Vector2.LEFT
		"right": direction = Vector2.RIGHT
		"up":    direction = Vector2.UP
		"down":  direction = Vector2.DOWN
	_play_directional_animation()
	_apply_directional_hitbox()


func shoot_vector(dir: Vector2) -> void:
	# The real entry point: warrior aims at the cursor, so this takes any angle.
	#
	# TRAVEL AND HITBOX ARE FULL 360. ANIMATION IS NOT, and that split is the
	# whole design. `direction` keeps the exact angle and drives both the
	# straight-line motion in _physics_process() and the rotated collision box
	# in _apply_directional_hitbox(). `direction_name` snaps to the nearest of
	# four purely to pick a sprite, because only four were drawn.
	#
	# So a wave fired up-left flies up-left and cuts up-left, while showing the
	# leftward slash art. The remaining mismatch is what a viewer sees, not
	# what the game does — it closes when the diagonal sprites are drawn, and
	# nothing here has to change when they are.
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
	# Build the collision shape for the angle this wave is actually flying at.
	# See HITBOX GEOMETRY above for why it is one rotated box rather than four
	# fixed ones, and why the scene's 64x64 circle was wrong before either.
	var shape_node: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if shape_node == null:
		return

	# direction is normalized by shoot()/shoot_vector() before this runs. A
	# zero vector would have no angle to rotate onto, so leave the authored
	# shape alone rather than installing a box pointing at 0°.
	if direction == Vector2.ZERO:
		return

	# A FRESH shape per wave, deliberately. Shapes are Resources, and the one
	# authored in slashwave.tscn is shared by every instance of the scene —
	# mutating it in place would resize every other wave currently in flight,
	# and the change would persist into the next one spawned.
	var rect := RectangleShape2D.new()
	rect.size = Vector2(HITBOX_THICKNESS, HITBOX_SWEEP) * hitbox_scale

	shape_node.shape = rect

	# ROTATION IS WHAT MAKES THE SIZE MEAN ANYTHING. The rect is authored with
	# its x axis along travel and its y axis across it; turning the node so
	# local +x points down the travel line is what turns "18 thick, 38 wide"
	# from a claim about the screen into a claim about the wave.
	shape_node.rotation = direction.angle()

	# Centred on the wave's visual middle, pushed forward along the exact aim
	# angle. The reach scales with hitbox_scale so growing the box keeps it on
	# the crescent instead of letting it drift back toward the origin.
	shape_node.position = SPRITE_CENTRE + direction * (HITBOX_REACH * hitbox_scale)


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

	target.take_damage(damage, element)
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
