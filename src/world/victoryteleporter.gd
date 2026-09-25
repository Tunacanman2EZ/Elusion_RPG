# victoryteleporter.gd — the way home, and it exists only once you have won.
#
# Sits in the boss arena, hidden and untouchable, until the gauntlet is
# cleared. When the last boss falls it appears, and stepping onto it takes the
# player back to the start — the town — the same fade-and-swap every other
# scene change uses.
#
# IT IS THE ONLY WAY OUT. The arena used to also have a ladder back up to the
# field, so this node was the reward and the ladder was the escape hatch. The
# ladder is gone: walk in and the room is a commitment. That makes everything
# below load-bearing in a way it was not before — if this teleporter fails to
# appear there is no second door, so the failure mode is a player standing in
# an empty room with nothing left to kill. testrunner.gd's BOSS ARENA section
# guards the wiring for exactly that reason.
#
# =============================================================================
# IT LISTENS; IT DOES NOT POLL
# =============================================================================
# bossgauntlet.gd already emits `gauntlet_cleared` when the final wave dies,
# and its own comment says the signal is there "so the HUD or an ambience track
# can react without polling." This is exactly that reactor. The gauntlet does
# not know this node exists — it is found through the "bossgauntlet" group and
# wired at runtime — so the win condition stays owned by the one script that
# sequences the fight, and this one only reacts to it.
#
# NOT A MAP LANDMARK, on purpose. mapscreen.gd draws a pin for every node in
# "map_landmarks" whether or not it is visible, so joining that group would put
# a teleport pin in the arena from the first frame, before the fight. This node
# is deliberately absent from it — it has nothing to advertise until it is real.
#
# =============================================================================
# THE TELEPORT ITSELF
# =============================================================================
# Same pattern as ladder.gd: load the destination by PATH (not an
# ext_resource, so no circular-load risk), stash a spawn id on GameState if one
# is set, and hand off to SceneTransition. The town (elusion.gd) places the
# player at its own `playerspawn`, so the trip lands you back where the run
# began — the start teleporter — regardless of `target_spawn_id`, which is kept
# only for a destination that reads FieldPortal ids.
extends Area2D


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# Where "home" is. A path, not a PackedScene — see ladder.gd for why a
# String beats an ext_resource here (circular loads between paired scenes).
@export_file("*.tscn") var destination_scene_path: String = "res://scene/elusion.tscn"

# Stashed on GameState before the swap, for a destination that positions by
# FieldPortal id. The town does not — it uses its own playerspawn — so this is
# empty by default and the player simply arrives at the start.
@export var target_spawn_id: String = ""

# The beat between the last boss dying and the teleporter appearing. NOT zero,
# and not only for feel — see _on_gauntlet_cleared() for the physics reason it
# must be at least a frame.
@export var appear_delay: float = 1.2

# How this node finds the sequencer. bossgauntlet.gd joins this group in _init.
@export var gauntlet_group: StringName = &"bossgauntlet"


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var _sprite: AnimatedSprite2D = get_node_or_null("teleporter")
@onready var _shape: CollisionShape2D = get_node_or_null("collisionshape2d")


# =============================================================================
# STATE
# =============================================================================

# Guards a double-fire on the same step-on, exactly like ladder.gd's.
var can_teleport := true

# False until the win reveals it. body_entered checks this so the player cannot
# be sent home by brushing the spot where the teleporter will be.
var _armed := false


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_hide_until_won()

	# CONNECT, don't reach in. The gauntlet is found by group, so this node
	# does not name a path into the arena's tree - move the gauntlet in the
	# editor and this still finds it.
	var gauntlet: Node = get_tree().get_first_node_in_group(gauntlet_group)
	if gauntlet != null and gauntlet.has_signal("gauntlet_cleared"):
		var cb := Callable(self, "_on_gauntlet_cleared")
		if not gauntlet.is_connected("gauntlet_cleared", cb):
			gauntlet.connect("gauntlet_cleared", cb)
	else:
		# A boss arena with no sequencer to clear is a scene wired wrong, and
		# the honest failure is to stay hidden - offering a way home from a
		# fight that never happens is worse than the teleporter never showing.
		push_warning("victoryteleporter: no '%s' in the scene - it will never appear" % gauntlet_group)


func _hide_until_won() -> void:
	visible = false
	_armed = false
	can_teleport = true
	# Monitoring off AND the shape disabled: the player must not be able to
	# step onto a teleporter that is not there yet. The scene sets these too,
	# so there is no one-frame window where a hidden teleporter is live.
	monitoring = false
	if _shape != null:
		_shape.disabled = true
	if _sprite != null:
		_sprite.stop()


# =============================================================================
# APPEARING
# =============================================================================

func _on_gauntlet_cleared() -> void:
	# gauntlet_cleared fires INSIDE the dying boss's own frame - bossgauntlet
	# emits it straight from _advance(), not through a timer. Turning a
	# collision shape on there is "touching collision shapes mid-physics",
	# which is the exact thing the gauntlet defers its gate-opening to avoid.
	# So the reveal waits at least a frame - and the wait also reads better:
	# the room noticing you won, rather than a teleporter blinking on over the
	# last boss before the body has finished falling.
	if appear_delay > 0.0:
		await get_tree().create_timer(appear_delay).timeout
	else:
		await get_tree().process_frame

	# PAST AN AWAIT. A SceneTreeTimer outlives this node, and the arena can still
	# change out from under it during the delay - a player who dies to the last
	# boss's parting shot is on the game-over screen before this resumes, and
	# resuming there means touching a freed Area2D. (It used to be the ladder
	# back up to the field that did this; that ladder is gone, and the guard
	# still earns its place.) Same guard every await in src/world/ carries.
	if not is_instance_valid(self) or not is_inside_tree():
		return

	_appear()


func _appear() -> void:
	visible = true
	_armed = true
	can_teleport = true
	if _sprite != null:
		_sprite.play()

	# DEFERRED, because this can run from a timer that lands inside a physics
	# step. `monitoring` and the shape's `disabled` are both physics state;
	# set_deferred applies them at the frame boundary, where it is safe.
	set_deferred("monitoring", true)
	if _shape != null:
		_shape.set_deferred("disabled", false)

	# A discontinuity, not motion - collapse the interpolation so the sprite
	# does not smear in from wherever it sat while hidden. Same call, same
	# reason, as teleporter.gd and the spawn code.
	reset_physics_interpolation()

	Audio.play("teleport")
	if OS.is_debug_build():
		print("[WORLD] victory teleporter appeared - the way home is open")


# =============================================================================
# THE TRIP HOME
# =============================================================================

func _on_body_entered(body: Node) -> void:
	# _armed first: before the win this node's monitoring is off anyway, but a
	# check here means the guarantee does not depend on the collision state
	# alone. Then the same body test and one-shot guard ladder.gd uses.
	if not _armed or not can_teleport:
		return
	if not (body and (body.name == "Player" or body.is_in_group("player"))):
		return

	can_teleport = false

	if destination_scene_path == "":
		push_warning("victoryteleporter: destination_scene_path is empty")
		can_teleport = true
		return
	var destination_scene: PackedScene = load(destination_scene_path)
	if destination_scene == null:
		push_warning("victoryteleporter: failed to load '%s'" % destination_scene_path)
		can_teleport = true
		return

	if target_spawn_id != "":
		GameState.next_spawn_id = target_spawn_id

	Audio.play("teleport")
	SceneTransition.change_scene(destination_scene)


func _on_body_exited(body: Node) -> void:
	if body and (body.name == "Player" or body.is_in_group("player")):
		can_teleport = true
