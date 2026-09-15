# enemyrespawner.gd — brings back the enemies a scene was authored with.
#
# There was no respawn code anywhere in the project. Enemies are placed in
# field.tscn and elusion.tscn by hand, _die() calls queue_free(), and that was
# the end of them until the scene was reloaded by walking out and back in.
#
# Drop ONE of these into a world scene. It takes a census on the first frame,
# remembers what was standing where, and puts an identical enemy back some time
# after each one dies. No changes to how enemies are placed.
#
#
# ONLY THE CENSUS RESPAWNS, WHICH IS THE WHOLE DESIGN.
#
# The population is snapshotted once, at scene start, before anything has died.
# An enemy spawned at RUNTIME is deliberately not in it — most importantly the
# eight small slimes a large poison slime splits into. Watching every enemy that
# ever exists would turn one large slime into a permanent slime fountain: kill
# the eight children, eight more arrive, forever.
#
# Kill the large slime and a large slime comes back, because that one was in the
# census. Its children are consequences of it, not inhabitants of the room.
#
#
# A NOTE ON TRUST.
#
# This runs on the client, so a modified client could respawn instantly and farm
# kills. That is not a new hole - the client already decides when a kill happens
# at all, and Combat.report_kill() is what the server sees either way. It is
# worth knowing that respawn timing is honour-system, and that the real fix is
# the server owning spawns, not a stricter timer here.
extends Node2D


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# Seconds between an enemy dying and its replacement appearing.
@export var respawn_seconds: float = 30.0

# Adds up to this many seconds of random extra delay, so a pack killed together
# does not reappear in one synchronised block. 0 disables the scatter.
@export var respawn_jitter: float = 6.0

# DO NOT POP IN ON TOP OF THE PLAYER. A respawn this close to them is held back
# and retried rather than cancelled, so clearing a camp and standing in it does
# not farm the timer down to nothing - it just does not spawn until they move.
@export var min_player_distance: float = 140.0

# How often a held-back respawn re-checks the distance above.
@export var retry_seconds: float = 2.0

# Off means the census still happens but nothing ever comes back. Useful for a
# boss arena or a story room that should stay cleared.
@export var enabled: bool = true


# =============================================================================
# STATE
# =============================================================================

# One entry per enemy the scene was authored with.
# { "scene_path": String, "position": Vector2, "parent": NodePath }
var _census: Array[Dictionary] = []


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# ONE FRAME LATER. The enemies' own _ready() has to have run before they are
	# in the "enemies" group, and a census taken in the same frame as theirs
	# would be a race decided by node order.
	await get_tree().process_frame
	if not is_instance_valid(self):
		return

	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node2D
		if enemy == null:
			continue

		# An enemy placed by hand is an instantiated scene and knows its own
		# file. One built node-by-node inside the world scene does not, and
		# cannot be rebuilt from nothing, so it is skipped rather than guessed
		# at - a silent miss is better than respawning the wrong thing.
		if enemy.scene_file_path == "":
			push_warning("EnemyRespawner: '%s' is not a scene instance and will not respawn" % enemy.name)
			continue

		var entry: Dictionary = {
			"scene_path": enemy.scene_file_path,
			"position": enemy.global_position,
			"parent": get_path_to(enemy.get_parent()),
		}
		_census.append(entry)
		_watch(enemy, entry)

	if OS.is_debug_build():
		print("[SPAWN] respawner watching %d enemies" % _census.size())


# =============================================================================
# THE CYCLE
# =============================================================================

func _watch(enemy: Node, entry: Dictionary) -> void:
	# BOUND WITH THE CENSUS ENTRY, not with the enemy. By the time died fires,
	# queue_free() is one line away and nothing about that node can be read -
	# which is why position and scene path were captured up front rather than
	# looked up in the handler.
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died.bind(entry), CONNECT_ONE_SHOT)


func _on_enemy_died(entry: Dictionary) -> void:
	if not enabled:
		return
	_respawn_after(entry, respawn_seconds + randf() * maxf(respawn_jitter, 0.0))


func _respawn_after(entry: Dictionary, delay: float) -> void:
	await get_tree().create_timer(delay).timeout

	# The scene may have changed under this timer. A respawner that outlived its
	# own world would be building enemies into a tree nobody is looking at.
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not enabled:
		return

	var spawn_position: Vector2 = entry.get("position", Vector2.ZERO)
	if _player_too_close(spawn_position):
		# HELD, NOT CANCELLED. Retrying keeps the enemy owed; cancelling would
		# mean a player who camps a spawn point clears the room permanently.
		_respawn_after(entry, maxf(retry_seconds, 0.5))
		return

	var packed: PackedScene = load(entry.get("scene_path", ""))
	if packed == null:
		push_warning("EnemyRespawner: cannot load %s" % entry.get("scene_path", ""))
		return

	var parent: Node = get_node_or_null(entry.get("parent", NodePath()))
	if parent == null or not is_instance_valid(parent):
		# The container the original sat in is gone. Falling back to this node
		# keeps the enemy in the world rather than dropping it silently.
		parent = self

	var enemy := packed.instantiate() as Node2D
	if enemy == null:
		push_warning("EnemyRespawner: %s is not a Node2D" % entry.get("scene_path", ""))
		return

	parent.add_child(enemy)
	enemy.global_position = spawn_position
	_watch(enemy, entry)


func _player_too_close(spawn_position: Vector2) -> bool:
	if min_player_distance <= 0.0:
		return false

	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player == null or not is_instance_valid(player):
		return false

	return player.global_position.distance_to(spawn_position) < min_player_distance


# =============================================================================
# PUBLIC
# =============================================================================

func set_enabled(value: bool) -> void:
	# For a boss arena that should stay cleared once, or a story beat that turns
	# the field hostile again afterwards.
	enabled = value


func census_size() -> int:
	return _census.size()
