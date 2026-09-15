# lever.gd — a wall lever the player throws to toggle something else.
#
# Knows nothing about spikes. It toggles a bool and tells whatever is listed in
# `targets`, so the same lever drives a spike door, a gate, a bridge or three of
# them at once without this file changing. A target only has to answer
# set_raised(bool).
#
# Interaction follows sign.gd and bankchest.gd: Area2D on layer 16
# ("interactors") masking layer 4 ("player"), body_entered/body_exited wired in
# the scene, and the interact key polled in _process while somebody is standing
# in the zone.
#
#
# ONE PRESS CAN STILL REACH TWO DIFFERENT KINDS OF INTERACTABLE.
#
# Input.is_action_just_pressed() is a global state query, not a consumable
# event, so every node polling it on the press frame sees true. lootbag.gd
# solves this among bags with a nearest-wins check and a shared frame claim, but
# that only coordinates bags with other bags. Stand on a loot bag AND in a
# lever's zone and one press does both.
#
# Not worth an interaction manager until it actually bites — a lever is on a
# wall and a bag is on the floor where something died. If it does bite, the fix
# is one arbiter that picks the nearest interactable of ANY type, and these
# per-class checks collapse into it.
extends Area2D


# =============================================================================
# SIGNALS
# =============================================================================

# Emitted after the throw animation starts, with the state being moved INTO.
# Anything that wants to react without being listed in `targets` can connect.
signal toggled(is_on: bool)


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# What this lever drives. Drag the spike doors (or anything with set_raised)
# here in the Inspector.
#
# NodePaths rather than a group name: a level usually has several levers, and a
# group would need a unique name per lever invented by hand and kept in sync in
# two places. A path is wrong only if you move the node, and then the editor
# tells you.
@export var targets: Array[NodePath] = []

# Which way round this lever reads. A lever that starts thrown holds its door
# OPEN until the player closes it, which is how you build a room that seals
# behind them.
@export var starts_on: bool = false

# INVERTS what `on` means for the targets, per lever. Two levers driving the
# same door from opposite sides of a wall, or a lever that RAISES spikes to
# block a corridor rather than lowering them to open one.
@export var inverted: bool = false

# A lever that can be thrown once and then never again — for a trap that arms,
# or a door that is meant to be a commitment rather than a toggle.
@export var one_shot: bool = false

# Seconds the throw animation takes. The targets are told at the START of it,
# so spikes and lever move together rather than the door lagging the handle.
@export var throw_seconds: float = 0.25


# =============================================================================
# NODES
# =============================================================================

@onready var anim: AnimatedSprite2D = get_node_or_null("animatedsprite2d")


# =============================================================================
# STATE
# =============================================================================

var _is_on: bool = false
var _player_nearby: Node = null
var _spent: bool = false
var _throwing: bool = false


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	add_to_group(&"levers")

	_is_on = starts_on
	_show_state(_is_on)

	# The targets are pushed into their starting position on the first frame
	# rather than here, because a target elsewhere in the scene may not have run
	# its own _ready() yet and set_raised() would land on a node whose
	# AnimatedSprite2D is still null.
	call_deferred("_apply_to_targets")

	# Nothing to poll until somebody walks up. Same reasoning as lootbag.gd: a
	# node that provably cannot act on the key should not be asking for it.
	set_process(false)


func _process(_delta: float) -> void:
	if _player_nearby == null or _throwing:
		return
	if _spent:
		return
	if not Input.is_action_just_pressed("interact"):
		return
	throw()


# =============================================================================
# THE THROW
# =============================================================================

func throw() -> void:
	# Public so a cutscene, a boss phase or a pressure plate can throw a lever
	# without a player standing at it.
	if _throwing or _spent:
		return

	_is_on = not _is_on
	_throwing = true
	if one_shot:
		_spent = true

	# TARGETS FIRST, ANIMATION SECOND. The door should start moving on the same
	# frame the handle does; telling the targets after the animation finished
	# would read as the door reacting to the lever rather than being driven by
	# it.
	_apply_to_targets()
	toggled.emit(_is_on)

	Audio.play_at("lever", global_position)

	if anim != null:
		anim.play(&"throwon" if _is_on else &"throwoff")

	await get_tree().create_timer(throw_seconds).timeout

	# Re-checked after the await: the scene may have changed underneath this.
	if not is_instance_valid(self):
		return
	_throwing = false
	_show_state(_is_on)


func is_on() -> bool:
	return _is_on


# =============================================================================
# TARGETS
# =============================================================================

func _apply_to_targets() -> void:
	var raised: bool = _is_on != inverted

	for path in targets:
		if path.is_empty():
			continue

		var target: Node = get_node_or_null(path)
		if target == null:
			push_warning("Lever (%s): target %s is not in this scene" % [name, path])
			continue

		# DUCK-TYPED ON PURPOSE. This file should not have to know what a spike
		# door is, and a future portcullis or drawbridge should work by
		# implementing set_raised() rather than by editing this list.
		if not target.has_method("set_raised"):
			push_warning("Lever (%s): %s has no set_raised(bool)" % [name, target.name])
			continue

		target.set_raised(raised)


func _show_state(on: bool) -> void:
	if anim != null:
		anim.play(&"on" if on else &"off")


# =============================================================================
# AREA SIGNALS
# =============================================================================

func _on_body_entered(body: Node) -> void:
	if body != null and body.is_in_group("player"):
		_player_nearby = body
		set_process(true)


func _on_body_exited(body: Node) -> void:
	if body != _player_nearby:
		return
	_player_nearby = null
	set_process(false)
