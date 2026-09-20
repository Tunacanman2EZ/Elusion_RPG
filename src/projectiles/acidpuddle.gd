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
# One script, many scenes. Every <element>puddle.tscn runs this; what differs
# between them is authored in the scene, not branched on here.
class_name AcidPuddle

# The hue-replacement shader every elemental creature already uses. See
# _apply_element_recolour() for why this sprite takes this one and the boss
# spike takes hearth_warm instead.
const SLAG_SHADER := preload("res://src/shared/element_recolour.gdshader")

# Every live pool joins this. Nothing needs it today — the group is here so a
# level-clear, a boss reset or a debug count can reach every pool on the floor
# without walking the tree.
const PUDDLE_GROUP := &"acidpuddles"


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
# The element this projectile deals. Element.Type is an int, not the
# StringName this used to be: an enum is checked when the file is parsed,
# and &"posion" was only ever going to be found by someone wondering why a
# resistance did nothing.
#
# Overwritten at spawn for anything an enemy fires — see
# BaseEnemy.spawn_projectile_node(), which stamps the caster's element on
# it so a water slime's shot IS water without a second scene existing.
# POISON, NOT EARTH, and this is a correction rather than a preference.
#
# The splat this scene draws is slime.png's, which measures hue 112 degrees -
# green, at 0.88 saturation. EARTH is ochre. The two disagreed because POISON
# did not exist as an element when this was written and earth was the closest
# thing on the list; now that it does, the data can say what the art has always
# shown. It matters more than it used to: the recolour below rotates this
# sprite to whatever element it carries, so a puddle mislabelled EARTH would
# have turned the poison slime's acid brown.
@export var element: int = Element.Type.POISON

# how long the fade-out at the end of `lifetime` takes. Doubles as the
# player's warning that this patch of ground is about to be safe again.
@export var fade_duration: float = 0.75

# Whether CONTACT hurts, or only staying does.
#
# TRUE now, and the rename in meaning is the fix. It used to mean "tick once in
# _ready()", which only covered someone already standing on the spot when the
# puddle appeared. What it means now is "the first tick for a given player
# happens when they touch the acid, not up to tick_interval later" — which is
# what makes standing in a pool hurt continuously instead of occasionally.
#
# Set it false for a pool that should be safe to dash through and only punish
# lingering.
@export var damages_on_spawn: bool = true


# WHICH SIDE THIS POOL BURNS.
#
# Every scene using this script is an ENEMY hazard, so "player" is the default
# and the nine elemental puddles keep working without carrying the line at all.
#
# It exists because a pet needed the same pool pointed the other way. The pet
# boss's spike leaves acid exactly like the boss's does, and without this the
# only ways to get there were a second copy of this file — 300 lines of
# per-target tick clocks and fade handling, duplicated to change one group
# name — or a pool that overlaps enemies and damages nobody, which is the
# worse bug because it looks like it works.
#
# The contact bookkeeping below is unchanged and already handles the enemy
# case: _on_area_begin() resolves a hurtbox to its parent and _contacts counts
# per node, so a CharacterBody2D that reports through both its body and its
# hurtbox still runs ONE clock.
@export var target_group: StringName = &"player"


# =============================================================================
# STATE
# =============================================================================

# Where to land. Set by the spawner BEFORE add_child so _ready() can place
# this itself - which turns three deferred calls per pool into one. At sixty
# pools a cast that is a hundred and twenty fewer calls queued in a frame the
# game is already spending on sixty-five erupting spikes.
var spawn_at: Vector2 = Vector2.ZERO

var _age: float = 0.0

# HOW MANY OF A PLAYER'S COLLISION NODES ARE INSIDE, keyed by instance id. A
# character carries a body AND a hurtbox, so both can report entering; this is
# a refcount rather than a flag so one of them leaving does not stop the ticks
# while the other is still standing in the acid.
var _contacts: Dictionary = {}

# The player node itself, so a tick does not have to look anyone up.
var _nodes: Dictionary = {}

# Seconds until the next tick, PER PLAYER, keyed by instance id.
#
# WHY NOT ONE ACCUMULATOR FOR THE WHOLE PUDDLE, which is what this was: that
# clock starts when the puddle spawns and runs regardless of who is standing in
# it. Walk into a pool a frame after it ticked and you get nothing for another
# half second; walk out before the next one and you took no damage at all for
# having been in acid. With a 2.5s boss pool and a 0.5s interval that is the
# difference between five hits and one, decided entirely by when you happened
# to step in.
#
# A timer per player fixes both ends: everyone is hurt the moment they make
# contact, and everyone gets the full interval before the next one regardless
# of when anybody else arrived. It also means two players in the same pool are
# on their own clocks rather than sharing one.
var _next_tick: Dictionary = {}


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	if has_node("animatedsprite2d"):
		var sprite: AnimatedSprite2D = $animatedsprite2d
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("puddle"):
			sprite.play("puddle")
		_apply_element_recolour(sprite)

	# PLACED HERE RATHER THAN BY THE SPAWNER. See spawn_at: the caller sets the
	# field and defers one add_child, instead of deferring a position and an
	# interpolation reset on top of it.
	global_position = spawn_at
	reset_physics_interpolation()

	add_to_group(PUDDLE_GROUP)

	# SIGNALS, NOT POLLING, and this is the whole efficiency fix.
	#
	# This used to ask the physics server who was overlapping, every physics
	# frame, for its entire life. Two queries per pool per frame: at sixty
	# pools alive for 2.5 seconds that is twenty thousand queries for one boss
	# cast, in the same frames the game is already erupting sixty-five spikes.
	# Frames were being dropped, which is what made pools look like they were
	# not spawning at all.
	#
	# The physics server already knows when something enters and leaves an
	# area, and will tell you for free. Asking it every frame is paying for an
	# answer it was going to volunteer.
	body_entered.connect(_on_contact_begin)
	body_exited.connect(_on_contact_end)
	area_entered.connect(_on_area_begin)
	area_exited.connect(_on_area_end)


func _apply_element_recolour(sprite: AnimatedSprite2D) -> void:
	# ROTATED, NOT TINTED, because the splat is 100% chromatic at 0.88
	# saturation - a multiply over art that saturated only ever darkens it, and
	# green times blue is a darker green. Hue replacement keeps the value and
	# the saturation, so an ice pool reads as the same puddle in a different
	# colour rather than as a flat blue blob. bossprojectile.gd's spike takes
	# the opposite shader for the opposite reason; both notes explain why.
	if sprite == null:
		return

	# THE SCENE WINS, AND THIS IS THE FALLBACK.
	#
	# Every <element>puddle.tscn authors its own ShaderMaterial with its own
	# element_hue, which means the colour is a thing you can see in the editor
	# and one Resource shared by every instance of that scene rather than a new
	# Material allocated per pool. If the sprite already has a material, it came
	# from the scene and it is already correct - overwriting it here would throw
	# away the authored version and reintroduce the per-pool allocation.
	#
	# What is left below only runs for a pool with no material of its own: a
	# hand-placed Area2D, or a tenth element added to the enum before anyone
	# builds it a scene. Better a rotated hue than a green blob labelled ICE.
	if sprite.material != null:
		return

	# POISON IS A NO-OP AND THAT IS THE POINT, not a special case: the art's own
	# hue is 0.311 and POISON's is 0.3122, so the slime's acid rotates onto
	# itself and comes out exactly as drawn. Nothing here needs to know that the
	# green one is the original.
	if element == Element.Type.NONE:
		return

	var mat := ShaderMaterial.new()
	mat.shader = SLAG_SHADER
	mat.set_shader_parameter("element_hue", Element.hue_for(element))
	mat.set_shader_parameter("amount", 1.0)
	sprite.material = mat


func _physics_process(delta: float) -> void:
	_age += delta

	if _age >= lifetime:
		queue_free()
		return

	_update_fade()
	_tick_players_inside(delta)


# =============================================================================
# DAMAGE
# =============================================================================

func _on_contact_begin(body: Node) -> void:
	_enter(body)


func _on_contact_end(body: Node) -> void:
	_leave(body)


func _on_area_begin(area: Area2D) -> void:
	# A hurtbox Area2D whose PARENT is the real character - the same two-list
	# shape the old overlap check had, just delivered rather than polled.
	_enter(area.get_parent())


func _on_area_end(area: Area2D) -> void:
	_leave(area.get_parent())


func _enter(node: Node) -> void:
	if not _is_damageable_player(node):
		return

	var id: int = node.get_instance_id()
	_contacts[id] = int(_contacts.get(id, 0)) + 1

	# Already standing in it with their other collision node. Count the contact
	# so leaving one does not stop the ticks, but do not start a second clock.
	if _contacts[id] > 1:
		return

	_nodes[id] = node
	_next_tick[id] = tick_interval

	# damages_on_spawn decides whether touching the acid costs anything or only
	# staying in it does.
	if damages_on_spawn:
		node.take_damage(tick_damage, element)


func _leave(node: Node) -> void:
	if node == null:
		return
	var id: int = node.get_instance_id()
	if not _contacts.has(id):
		return

	_contacts[id] = int(_contacts[id]) - 1
	if _contacts[id] > 0:
		return

	# Fully out. Forgetting the clock is what makes stepping back in a fresh
	# contact rather than resuming whatever was left on the old timer.
	_contacts.erase(id)
	_nodes.erase(id)
	_next_tick.erase(id)


func _tick_players_inside(delta: float) -> void:
	# NO PHYSICS QUERIES. This walks a dictionary that is almost always empty
	# and never longer than the number of players standing in one pool.
	if _next_tick.is_empty():
		return

	for id in _next_tick.keys():
		var node: Node = _nodes.get(id)

		# A player can be freed - death, a scene change - while inside. The
		# exit signal does not fire for a node that simply stopped existing.
		if not is_instance_valid(node):
			_next_tick.erase(id)
			_nodes.erase(id)
			_contacts.erase(id)
			continue

		_next_tick[id] = float(_next_tick[id]) - delta
		if _next_tick[id] <= 0.0:
			node.take_damage(tick_damage, element)
			# ADDED, not reset, so a long frame does not swallow the leftover
			# and drift the rate.
			_next_tick[id] = float(_next_tick[id]) + tick_interval


func _is_damageable_player(node: Node) -> bool:
	# Named for the common case rather than renamed across the file: everything
	# here still reads "player" because on nine of the ten scenes that is what
	# it is. target_group is the one thing that varies. See its comment above.
	return node != null \
		and node.is_in_group(target_group) \
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
