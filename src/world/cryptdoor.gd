# cryptdoor.gd - a door in the crypt's walls, opened and shut with the
# interact key (0.63.0).
#
# THE OWNER, 20 Oct: "for now just interacting with door is enough", the door
# "bigger too". His art (art/floordecoration/cryptdoor.png): two stone sides
# and a plank door between them, the crypt walls' own 28 px height, drawn at
# 2x - 78 x 56 px, a 42 px gap. There is no open picture, so opening lifts
# the planks out of sight and leaves the stone sides standing.
#
# SOLID WHEN SHUT, to players, monsters and shots alike (layer 1, the walls'):
# a monster cannot open a door, so a crypt's skeletons stay in until a player
# lets them out. Only a player in reach - either side of it - can work it.
#
# IT SHUTS ITSELF BEHIND YOU. The owner, 20 Oct: "need a door to close after
# player leaves proximity". CLOSE_AFTER seconds after the player walks out of
# its reach, an open door shuts - unless they came back, or somebody (a
# player or a monster) is standing in the gap, when it waits until the gap is
# clear. It never shuts on a body, the interact key included: a shut door's
# collision dropped on top of someone would shove them out of the wall.
#
# EVERYONE IN THE AREA SEES THE SAME DOOR. It is a lever to presence.gd: in the
# "levers" group, told on with Presence.tell_lever() when worked here, and
# moved by follow_pull() when somebody else works it - now, or before this game
# walked in (the server remembers an area's levers until it empties).
extends Node2D

const LIFT_SECONDS := 0.3
# How far the planks rise as they go, in px.
const LIFT := 10.0
# How long after the player leaves its reach an open door shuts, in seconds.
const CLOSE_AFTER := 0.5
# While somebody stands in the gap, how often to look again, in seconds.
const RECHECK_SECONDS := 0.25
# What may stand in the gap: players (layer 3) and monsters (layer 4).
const GAP_MASK := 4 | 8
# ONE WAY's edge (one_way() below) is on layer 5, which only a player's body
# looks for (its mask is 19): a shot or a monster goes through as before.
const ONE_WAY_LAYER := 16

@export var starts_open: bool = false

# LOCKED (0.93.0, the endless run's door - endlessrun.gd): shut, and the
# interact key does nothing, until unlocked. Locking an open door shuts it as
# soon as nobody stands in the gap.
var locked: bool = false
# HELD OPEN (0.93.3, a party's run): open, and it does not shut itself - not
# when the player walks off, and not on somebody else's pull - until let go.
# The run holds it while the party comes through, and at each new stage.
var held: bool = false
# ONE WAY (0.93.3, the Endless's door): the edge one_way() lays across the
# gap, or null.
var one_way_body: StaticBody2D = null

var _open: bool = false
var _player_nearby: Node = null
var _tween: Tween = null
# Counting down to shutting itself; below zero, nothing is.
var _close_in: float = -1.0
# Whether that shut is told to the area (this game's player walked away) or
# is only somebody else's pull waiting for the gap to clear.
var _close_tells: bool = true

@onready var planks: Sprite2D = $planks
@onready var shut_shape: CollisionShape2D = $body/shut
@onready var reach: Area2D = $reach
@onready var _planks_rest: Vector2 = $planks.position


func _ready() -> void:
	add_to_group(&"levers")
	reach.body_entered.connect(_on_body_entered)
	reach.body_exited.connect(_on_body_exited)
	_show(starts_open, false)
	set_process(false)


func _process(delta: float) -> void:
	if _close_in >= 0.0:
		_close_in -= delta
		if _close_in < 0.0:
			_close_now()
	var near: bool = _player_nearby != null and is_instance_valid(_player_nearby)
	if near and Input.is_action_just_pressed("interact"):
		work()
	if not near and _close_in < 0.0:
		set_process(false)


func work() -> void:
	"""The local player opened or shut it: everyone else in the area is told.
	It does not shut on somebody standing in the gap, nor while held."""
	if locked or (held and _open):
		return
	if _open and gap_taken():
		return
	_close_in = -1.0
	_show(not _open, true)
	if is_inside_tree():
		Presence.tell_lever(self, _open)


func follow_pull(on: bool) -> void:
	"""Somebody else worked this door (presence.gd), now or before this game
	walked in. It moves as if worked here, and is told to nobody - and a shut
	waits, like one here, while somebody stands in the gap. Held, it stays
	open."""
	if held and not on:
		return
	if on:
		_close_in = -1.0
	if on == _open:
		return
	if not on and gap_taken():
		_close_later(RECHECK_SECONDS, false)
		return
	_show(on, true)


func gap_taken() -> bool:
	"""Whether a player or a monster stands where the shut planks would be."""
	if not is_inside_tree():
		return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shut_shape.shape
	query.transform = shut_shape.global_transform
	query.collision_mask = GAP_MASK
	query.collide_with_areas = false
	query.exclude = [($body as StaticBody2D).get_rid()]
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _close_later(seconds: float, tells: bool) -> void:
	_close_in = seconds
	_close_tells = tells
	set_process(true)


func _close_now() -> void:
	"""The countdown ran out: shut, unless the player came back or the gap is
	taken - then look again shortly. A shut of this game's own is told."""
	if not _open or held:
		return
	if not locked and _close_tells and _player_nearby != null and is_instance_valid(_player_nearby):
		return
	if gap_taken():
		_close_later(RECHECK_SECONDS, _close_tells)
		return
	_show(false, true)
	if _close_tells and is_inside_tree():
		Presence.tell_lever(self, false)


func is_open() -> bool:
	return _open


func lock(on: bool) -> void:
	"""Locked: shut (once the gap is clear) and deaf to the interact key."""
	locked = on
	if on:
		held = false
	if on and _open:
		_close_later(0.0, true)


func hold(on: bool) -> void:
	"""Held open, or let go (see `held`): holding opens it now, unlocked and
	told to the area; let go, it shuts once nobody stands in the gap, as when
	the player walks off."""
	if on == held:
		return
	held = on
	if on:
		locked = false
		_close_in = -1.0
		if not _open:
			_show(true, true)
			if is_inside_tree():
				Presence.tell_lever(self, true)
	elif _open:
		_close_later(CLOSE_AFTER, true)


func one_way(on: bool) -> void:
	"""ONE WAY (0.93.3, the Endless's door - endlessrun.gd). The owner: "the
	door needs to be 1 way entry also". In from below (the corridor), never
	back out from above (the arena): an edge across the gap, open door or
	shut, that Godot's one-way collision makes solid only to a body moving
	down onto it. Half way through and back is still allowed - a player is
	not in until they are past it. Only players are stopped (ONE_WAY_LAYER).
	"""
	if not on:
		if one_way_body != null:
			one_way_body.queue_free()
			one_way_body = null
		return
	if one_way_body != null:
		return
	var gap: Vector2 = (shut_shape.shape as RectangleShape2D).size
	var edge := RectangleShape2D.new()
	edge.size = gap
	var shape := CollisionShape2D.new()
	shape.name = "edge"
	shape.shape = edge
	shape.position = shut_shape.position
	shape.one_way_collision = true
	one_way_body = StaticBody2D.new()
	one_way_body.name = "oneway"
	one_way_body.collision_layer = ONE_WAY_LAYER
	one_way_body.collision_mask = 0
	one_way_body.add_child(shape)
	add_child(one_way_body)


func _show(open: bool, animate: bool) -> void:
	_open = open
	# Deferred: a door is often worked from inside a physics callback.
	shut_shape.set_deferred("disabled", open)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var to_alpha: float = 0.0 if open else 1.0
	var to_pos: Vector2 = _planks_rest + (Vector2(0, -LIFT) if open else Vector2.ZERO)
	if not animate or not is_inside_tree():
		planks.modulate.a = to_alpha
		planks.position = to_pos
		return
	Audio.play_at("door", global_position)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(planks, "modulate:a", to_alpha, LIFT_SECONDS)
	_tween.tween_property(planks, "position", to_pos, LIFT_SECONDS)


func _on_body_entered(body: Node) -> void:
	if body != null and body.is_in_group("player"):
		_player_nearby = body
		if _close_tells:
			_close_in = -1.0       # back before it shut: it stays open
		set_process(true)


func _on_body_exited(body: Node) -> void:
	if body != _player_nearby:
		return
	_player_nearby = null
	if _open:
		_close_later(CLOSE_AFTER, true)
