# acidpuddle.gd — the ground hazard left behind where a slime's acid ball
# lands. Spawned by poisonprojectile.gd on impact.
#
# WHAT IT IS FOR: the acid ball on its own is a hit you either take or dodge,
# and then it's over. The puddle turns that into a decision — the ground you
# were standing on is now hostile, and staying there costs you. It's what
# makes the slime a fight about position rather than a damage race.
#
# STACKING IS THE POINT, and it's why this is a plain per-instance node with
# its own timer rather than anything shared. Two puddles overlapping are two
# separate nodes ticking independently, so standing in both hurts twice as
# fast. Being cornered by your own dodges is the failure state the design
# wants — see the note on tick_damage below before tuning it.
#
# RENDER ORDER: spawned into the Y-sorted "groundeffects" container, the
# same one bushmage's vine uses, so it draws UNDER characters. A puddle
# painted over the player's feet reads as fog, not ground.
#
# ONLY DAMAGES PLAYERS. This is an enemy's attack; the slimes that made it
# wade through it freely, and a small slime standing in its parent's acid
# shouldn't die to it.
extends Area2D


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# how long the puddle lasts, in seconds, including its fade.
@export var lifetime: float = 4.0

# damage per tick to a player standing in it.
#
# TUNING NOTE: the real number to think about is damage-per-second AT A
# STACK, not per puddle. At the defaults one puddle is 6 dps; three
# overlapping is 18, which is the situation the ability is actually built
# around. Raise this and the stacked case gets punishing much faster than
# the single case suggests.
@export var tick_damage: int = 3

# seconds between ticks. Also the grace period — step out before the next
# tick lands and you take nothing more.
@export var tick_interval: float = 0.5

# matches the acid ball's own type so any future poison resistance applies
# to the puddle as well.
@export var damage_type: StringName = &"poison"

# how long the fade-out at the end of `lifetime` takes. Doubles as the
# player's warning that this patch of ground is about to be safe again.
@export var fade_duration: float = 0.75

# whether the puddle ticks the moment it appears. FALSE by default: being
# hit by the ball already deals its own damage, and an instant tick on top
# reads as the same hit landing twice with no chance to react.
@export var damages_on_spawn: bool = false


# =============================================================================
# STATE
# =============================================================================

var _age: float = 0.0
var _tick_accumulator: float = 0.0


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	if has_node("animatedsprite2d"):
		var sprite: AnimatedSprite2D = $animatedsprite2d
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("puddle"):
			sprite.play("puddle")

	if damages_on_spawn:
		_damage_players_inside()


func _physics_process(delta: float) -> void:
	_age += delta

	if _age >= lifetime:
		queue_free()
		return

	_update_fade()

	_tick_accumulator += delta
	if _tick_accumulator >= tick_interval:
		# subtract rather than reset to 0, so a long frame doesn't quietly
		# swallow the leftover time and drift the tick rate.
		_tick_accumulator -= tick_interval
		_damage_players_inside()


# =============================================================================
# DAMAGE
# =============================================================================

func _damage_players_inside() -> void:
	# ONE hit per player per tick, no matter how many of their collision
	# nodes are inside the puddle. A character with both a body and a
	# hurtbox area would otherwise take two ticks for every one — the same
	# double-hit that slashwave.gd had to solve.
	var already_hit: Array[int] = []

	for target in _overlapping_player_nodes():
		var id: int = target.get_instance_id()
		if id in already_hit:
			continue
		already_hit.append(id)
		target.take_damage(tick_damage, damage_type)


func _overlapping_player_nodes() -> Array[Node]:
	# collects players from BOTH overlap lists: some things collide as
	# bodies, some expose a hurtbox Area2D whose parent is the real
	# character. poisonprojectile.gd checks both for the same reason.
	var found: Array[Node] = []

	for body in get_overlapping_bodies():
		if _is_damageable_player(body):
			found.append(body)

	for area in get_overlapping_areas():
		var parent: Node = area.get_parent()
		if _is_damageable_player(parent):
			found.append(parent)

	return found


func _is_damageable_player(node: Node) -> bool:
	return node != null \
		and node.is_in_group(&"player") \
		and node.has_method(&"take_damage")


# =============================================================================
# FADE
# =============================================================================

func _update_fade() -> void:
	# fades over the last fade_duration seconds of life rather than
	# vanishing on a frame boundary — an instant disappearance leaves the
	# player unsure whether the ground is still dangerous.
	var remaining: float = lifetime - _age
	if remaining >= fade_duration:
		return
	if not has_node("animatedsprite2d"):
		return

	var sprite: AnimatedSprite2D = $animatedsprite2d
	sprite.modulate.a = clampf(remaining / fade_duration, 0.0, 1.0)
