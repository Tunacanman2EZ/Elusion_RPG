# spelltargetcircle.gd — stalagmite spell that drops at a target position.
# spawned by mage.gd at cursor position. plays a fall animation, damages
# enemies inside the radius on impact frame, despawns when animation ends.
#
# spawn flow:
# 1. mage casts → instantiates this scene at cursor position
# 2. mage sets explosion_damage based on magic skill, and caster (NEW,
#    see below) to itself
# 3. _ready validates the animation, plays "fall", queues redraw of the
#    targeting ring
# 4. on frame 4 (visual impact), damage applies to all enemies inside the
#    Area2D's collision shape, and XP is granted back to caster per enemy
#    hit (NEW)
# 5. on animation_finished, the scene despawns
#
# why frame 4:
# the 8-frame "fall" animation peaks visually at frame 4 (stalagmite slams
# into the ground). damage on frame 4 syncs the gameplay hit with the
# visual impact. adjust if you retime the animation.
#
# scene structure:
# - Area2D root (this script)
# - stalagmiteprojectile (AnimatedSprite2D) — sprite offset upward in the
#   scene so the stalagmite renders above ground and falls down through
#   animation frames
# - CollisionShape2D — circular, matches circle_radius for AoE detection
extends Area2D

# Whether a wall stands between this and what it would hit (0.69.1,
# src/shared/targets.gd).
const Targets := preload("res://src/shared/targets.gd")
# The ice shards a spike leaves spinning (0.71.0).
const FrostRing := preload("res://src/projectiles/frostring.gd")


# =============================================================================
# CONSTANTS
# =============================================================================

# frame of the "fall" animation where damage is applied.
# tune to match the visual impact (stalagmite touching ground).
const IMPACT_FRAME := 4


# =============================================================================
# STATE
# =============================================================================

# damage dealt to enemies on impact frame — set by mage when spawning.
# scales with the mage's magic skill (magic × damage_per_magic in mage.gd).
var explosion_damage: int = 0

# A PICTURE OF SOMEBODY ELSE'S (0.19.0). With `cosmetic` set, this is a copy of
# an attack another player made, drawn on this screen from the presence
# server's word (remoteattacks.gd): it flies, spins, falls and burns exactly as
# theirs does, and it touches nothing - no hit, no XP, no camera shake, and
# nothing set off or pulled. The monsters are the area's leader's and every
# hit still travels as a hit; this is only what the owner asked to see: "i
# could not see their attacks but they could see mine".
var cosmetic: bool = false

# NEW: identifies who cast this spell — set by mage.gd on spawn, mirrors
# slashwave.gd's caster reference for warrior. used to grant XP back to
# the caster on impact, see _grant_caster_xp() below. null-guarded
# throughout in case something ever spawns this scene without setting it.
var caster: Node = null

# Magic XP PER ENEMY hit, not once per cast, so an AoE that catches three
# enemies trains magic three times. Reported to the server (SkillTrainer),
# which applies the mage's specialty. There is no attack XP here: attack
# trains at the kill, on the server - see Player.apply_server_attack().
@export var magic_xp_on_hit: int = 5

# visual radius of the target ring drawn on the ground.
# does NOT control the actual damage area — that's the CollisionShape2D on the
# Area2D root (CircleShape2D radius 18). MATCHED to it on purpose: the ring was
# 14 while the hit landed at 18, so it under-sold the AoE by four pixels and a
# player standing just outside the drawn ring still got hit. If the collision
# shape's radius changes in the scene, change this with it.
var circle_radius: float = 18.0

# THE MARK IT FOLLOWS DOWN (0.70.0, mage.gd's SPIKE_SEEK_RADIUS): set by the
# mage before add_child(), or null for a spike aimed at the ground. Until it
# strikes, the spike keeps over the mark's feet - so a monster walking away in
# the third of a second it takes to fall is still under it. It lets go of a
# mark that goes behind a wall, dies or is put to sleep.
var target: Node2D = null

# WHAT THIS CAST'S SPIKES HAVE HIT, shared by all of them (THE THIRD CAST,
# mage.gd): instance id -> true. A monster takes one spike a cast.
var struck: Dictionary = {}
# How often this cast's ice shards have hit each monster, shared by all its
# spikes' shards (frostring.gd, 0.71.1): instance id -> hits.
var shard_hits: Dictionary = {}

# THE CRITICAL SPIKE (0.71.0, mage.gd's CRIT_CHANCE): its hit is already
# CRIT_MULT times as hard (the mage rolled it into explosion_damage); this
# makes it gold, its numbers big and gold, and its shatter wider.
#
# GOLD, AS EVERY CLASS'S BIG ROLL IS. The owner: "we need that critical to be
# gold like the other chars" - "well the spike gold". The healer's double flies
# gold (turretprojectile.gd) and the warrior's finisher swings gold
# (slashwave.gd); a critical spike comes down gold:
#   the spike   the ice art, its hue turned to gold (element_recolour.gdshader,
#               the palette-swap shader the monsters use - a modulate can only
#               darken blue, never turn it gold), its shades lifted so it is
#               gold and not brown, its whites warmed;
#   the ring    and its glints, gold where they were ice;
#   the shatter tinted gold (CRIT_TINT, over 1 so pale ice comes out gold);
#   the shards  the warrior's gold orbs (BladeOrb.GOLD).
# Set before add_child(), by the mage or by a picture of somebody else's.
var critical: bool = false
# How much wider a critical spike's shatter is.
const CRIT_SHATTER := 1.6
const CRIT_SHADER := preload("res://src/shared/element_recolour.gdshader")
# The healer's double's gold (turretprojectile.gd's GOLD), as a hue.
const CRIT_HUE := 0.12
const CRIT_SATURATION := 1.35
const CRIT_WARM_WHITES := 0.3
# The ice's blues are dark; gold at their brightness is brown.
const CRIT_LIFT := 0.45
const CRIT_RING := Color(1.0, 0.82, 0.3, 0.9)
const CRIT_GLINT := Color(1.0, 0.95, 0.7, 1.0)
const CRIT_TINT := Color(1.4, 0.9, 0.3)


# =============================================================================
# NODE REFERENCES
# =============================================================================

# the falling stalagmite sprite. positioned in the scene with a Y-offset so
# it renders ABOVE the ground at frame 0 and falls down through frame 4.
@onready var anim: AnimatedSprite2D = $stalagmiteprojectile


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# validate the animation setup defensively — without these guards, a
	# missing or empty animation would crash on play() with a cryptic error.
	# fail loudly with a queue_free so dev catches the issue immediately.
	if not _validate_animation():
		queue_free()
		return

	_layer_ring_on_the_ground()
	if critical:
		_dress_gold()
	if cosmetic:
		RemoteAttacks.go_quiet(self)

	anim.animation_finished.connect(_on_animation_finished)
	anim.frame_changed.connect(_on_frame_changed)
	anim.play("fall")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# trigger _draw so the targeting ring renders on the first frame; _process
	# redraws it as it frosts in.
	queue_redraw()


func _layer_ring_on_the_ground() -> void:
	# THE RING IS A GROUND DECAL; THE STALAGMITE FALLS ON TOP OF IT.
	#
	# mage.gd spawns this whole scene as a child of the scene ROOT, which makes
	# it a sibling drawn AFTER `ysortworld` — the y-sorted layer every enemy and
	# player lives in. So by default BOTH the _draw() ring and the falling
	# stalagmite paint over every enemy, and the ring "pastes on top" instead of
	# lying on the floor.
	#
	# The field stacks its layers by z: Black(-100) < water(-20) < ground(-10) <
	# grounddecals(0) <= ysortworld(0, the entities). To read as a decal the ring
	# has to sit BELOW the entities but ABOVE the floor, so the root — which is
	# what _draw() paints on — goes to an absolute z of -1: over the ground, under
	# every enemy.
	#
	# The stalagmite must NOT follow the root down there (it drops from the sky
	# and should cover what it lands on), so it is pinned to its own absolute
	# layer at z 0 — exactly where the whole spell used to sit, i.e. over the
	# entities by tree order — instead of inheriting the root's new z.
	#
	# z only reorders drawing; the Area2D's collision shape is untouched, so the
	# damage radius is exactly what it was.
	z_index = -1
	z_as_relative = false
	anim.z_index = 0
	anim.z_as_relative = false


func _validate_animation() -> bool:
	# checks the AnimatedSprite2D exists, has the "fall" animation, and that
	# the animation has at least one frame. returns true if everything's
	# valid, false otherwise (caller queue_free's on false).
	if anim == null:
		push_error("spelltargetcircle: stalagmiteprojectile AnimatedSprite2D not found")
		return false
	if not anim.sprite_frames.has_animation("fall"):
		push_error("spelltargetcircle: SpriteFrames missing 'fall' animation")
		return false
	if anim.sprite_frames.get_frame_count("fall") == 0:
		push_error("spelltargetcircle: 'fall' animation has zero frames")
		return false
	return true


# =============================================================================
# THE FROST RING AND THE SHADOW (0.35.0)
# =============================================================================
# The owner: "time to give the mages attack some effects" - and of the four
# offered, "Frost ring + shadow" among them. Until 0.35.0 this was a red
# antialiased circle, 2 px, drawn once: the only thing on the floor before
# the spike landed.
#
# NOW IT FROSTS IN as the spike falls, in whole pixels like the rest of the
# floor: a 1 px ring of ice-blue, faint at the cast and full as it lands, a
# fainter band 3 px inside it, and six glints round it that turn as it comes.
# It is still exactly the hit - circle_radius, the collision shape's 18 - and
# still a circle, because the hit is one.
#
# AND A SHADOW under the spike, a pixel-art ellipse (Blast.shadow_texture(),
# the meteor's) that grows as it comes down, so where it will land reads
# before it does. After the impact both fade over the shatter's frames; the
# shatter itself, and the frost it leaves, are Blast's "stalagmite" kind,
# spawned on IMPACT_FRAME.

const RING_COLOUR := Color(0.7, 0.92, 1.0, 0.9)
const GLINT_COLOUR := Color(0.92, 0.98, 1.0, 1.0)
const GLINTS := 6
# How far round the glints turn while it falls, in turns.
const GLINT_TURN := 0.35
# The shadow's half-width at the impact; it is half as tall.
const SHADOW_MAX := 7


func fall_progress() -> float:
	"""0 as the spike appears, 1 as it lands (IMPACT_FRAME), read off the
	animation so the ring and the shadow keep time with the art."""
	if anim == null:
		return 1.0
	return clampf((float(anim.frame) + anim.frame_progress) / float(IMPACT_FRAME), 0.0, 1.0)


func after_progress() -> float:
	"""0 at the impact, 1 as the last frame ends: how far the ring has faded."""
	if anim == null or anim.sprite_frames == null:
		return 0.0
	var frames: int = anim.sprite_frames.get_frame_count("fall")
	var past: float = float(anim.frame) + anim.frame_progress - float(IMPACT_FRAME)
	return clampf(past / float(maxi(frames - IMPACT_FRAME, 1)), 0.0, 1.0)


func _process(_delta: float) -> void:
	queue_redraw()


func _physics_process(_delta: float) -> void:
	follow()


func follow() -> void:
	"""One tick of following the mark down, before the strike."""
	if target == null:
		return
	if not is_instance_valid(target) or not target.is_inside_tree() or not target.is_visible_in_tree() \
			or (anim != null and anim.frame >= IMPACT_FRAME):
		target = null
		return
	if target.has_method("can_be_aimed_at") and not target.call("can_be_aimed_at"):
		target = null
		return
	var feet: Vector2 = Targets.body_point(target)
	if not Targets.clear_between(self, global_position, feet):
		target = null
		return
	global_position = feet


func _dress_gold() -> void:
	"""THE CRITICAL SPIKE, gold: the falling spike's art turned to gold."""
	var gold := ShaderMaterial.new()
	gold.shader = CRIT_SHADER
	gold.set_shader_parameter("element_hue", CRIT_HUE)
	gold.set_shader_parameter("saturation_scale", CRIT_SATURATION)
	gold.set_shader_parameter("grey_tint", CRIT_WARM_WHITES)
	gold.set_shader_parameter("value_lift", CRIT_LIFT)
	anim.material = gold


func ring_colour() -> Color:
	return CRIT_RING if critical else RING_COLOUR


func glint_colour() -> Color:
	return CRIT_GLINT if critical else GLINT_COLOUR


func _draw() -> void:
	var fall: float = fall_progress()
	var left: float = 1.0 - after_progress()
	if left <= 0.0:
		return
	# The shadow: two pixels across at the cast, SHADOW_MAX at the impact.
	var rx: int = maxi(2, roundi(lerpf(2.0, float(SHADOW_MAX), fall)))
	var shadow: Texture2D = Blast.shadow_texture(rx, maxi(1, int(rx / 2.0)))
	draw_texture(shadow, -(shadow.get_size() / 2.0).floor(), Color(1, 1, 1, left))
	# The ring, frosting in.
	var ring: Color = ring_colour()
	ring.a = ring_colour().a * lerpf(0.35, 1.0, fall) * left
	draw_arc(Vector2.ZERO, circle_radius, 0.0, TAU, 48, ring, 1.0, false)
	var band: Color = ring
	band.a *= 0.35
	draw_arc(Vector2.ZERO, circle_radius - 3.0, 0.0, TAU, 40, band, 1.0, false)
	# The glints: a pixel and its four neighbours, turning as it falls.
	var glint: Color = glint_colour()
	glint.a = lerpf(0.4, 1.0, fall) * left
	var arm: Color = glint
	arm.a *= 0.5
	for i in GLINTS:
		var angle: float = TAU * (float(i) / GLINTS + fall * GLINT_TURN)
		var at: Vector2 = (Vector2.from_angle(angle) * circle_radius).round()
		draw_rect(Rect2(at, Vector2.ONE), glint)
		for step in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_rect(Rect2(at + step, Vector2.ONE), arm)


# =============================================================================
# IMPACT / DAMAGE
# =============================================================================

func _on_frame_changed() -> void:
	# damage fires on IMPACT_FRAME — the visual moment the stalagmite hits
	# the ground. naturally fires once per cast since the animation doesn't
	# loop and only one cast spawns this scene.
	if anim.animation != "fall":
		return
	if anim.frame != IMPACT_FRAME:
		return
	_apply_area_damage()
	_shatter()
	_spin_shards()


func _spin_shards() -> void:
	# THE ICE SHARDS (0.71.0): a ring of them round the frost ring, spinning,
	# then out (frostring.gd) - sharing what this cast has hit.
	var parent: Node = get_parent()
	if parent == null:
		return
	FrostRing.spin(parent, global_position, circle_radius, explosion_damage, shard_hits, cosmetic,
		BladeOrb.GOLD if critical else BladeOrb.ICE)


func _shatter() -> void:
	# THE SHATTER (0.35.0): Blast's "stalagmite" kind - a cold flash, a ring of
	# air, ice shards, mist and glints, and frost left on the floor to melt.
	# Beside this, not on it, so it outlives the spell's own short life. A
	# picture of somebody else's shakes nobody's camera.
	var parent: Node = get_parent()
	if parent == null:
		return
	var shatter: Blast = Blast.spawn(parent, global_position, &"stalagmite",
		circle_radius * (CRIT_SHATTER if critical else 1.0), not cosmetic)
	# A critical one shatters gold.
	if critical:
		shatter.modulate = CRIT_TINT


func _apply_area_damage() -> void:
	# damage all enemies currently inside the Area2D's collision shape.
	# scans get_overlapping_bodies at the moment of impact — enemies that
	# enter the area AFTER this frame are not hit (instant AoE, no DoT).
	if cosmetic:
		return
	for body in Targets.touching(self):  # bodies and hurtboxes, once (0.93.1)
		if not body.is_in_group("enemies"):
			continue
		if not body.has_method("take_damage"):
			continue
		# Not past a wall from where it landed (0.69.1, Targets).
		if not Targets.can_reach(self, global_position, body):
			continue
		# One spike a cast for any monster (THE THIRD CAST, mage.gd).
		var id: int = body.get_instance_id()
		if struck.has(id):
			continue
		struck[id] = true
		# A critical spike's number is big and gold (BaseEnemy).
		if critical and body.has_method("take_critical_damage"):
			body.take_critical_damage(explosion_damage)
		else:
			body.take_damage(explosion_damage)
		_grant_caster_xp()


func _grant_caster_xp() -> void:
	# Magic XP to whoever cast this, once per enemy hit (see magic_xp_on_hit).
	# null-guarded since caster isn't guaranteed to be set if something spawns
	# this scene without going through mage.gd's normal cast flow.
	if caster == null:
		return
	if caster.has_method("gain_magic_xp"):
		caster.gain_magic_xp(magic_xp_on_hit)


# =============================================================================
# CLEANUP
# =============================================================================

func _on_animation_finished() -> void:
	# despawn when the fall animation completes.
	# guarded against finishing OTHER animations in case future variants
	# play multiple sequences (impact debris, residual particles, etc.).
	if anim.animation == "fall":
		queue_free()
