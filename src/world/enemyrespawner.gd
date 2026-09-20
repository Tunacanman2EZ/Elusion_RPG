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
#
# 250, AND THE NUMBER IS MEASURED RATHER THAN CHOSEN.
#
# The player camera is zoom 3 on a 1280x720 viewport, so the visible world is
# 427 x 240 pixels: half-width 213, half-height 120. At the old 140 an enemy
# was off-screen vertically (140 > 120) and firmly ON-screen horizontally,
# about two thirds of the way to the edge - so respawns popped into existence
# in plain sight to the left and right and nowhere else, which is a strange
# effect to watch and an easy one to miss while testing by walking upward.
#
# The worst case is the corner: sqrt(213^2 + 120^2) = 244. 250 clears it.
#
# THE COST OF RAISING IT is that a player standing in a small room holds more
# respawns back at once. That is the held-not-cancelled behaviour above working
# as designed, but in a tight arena it can mean nothing returns while they are
# in it. If a room needs a different answer, this is per-respawner.
@export var min_player_distance: float = 250.0

# How far from its authored position a respawn may appear, in pixels.
#
# WITHOUT THIS EVERY RESPAWN IS THE SAME PIXEL. A cleared camp rebuilt itself
# in precisely the formation that was just killed, which reads as a machine
# rather than a world and makes a spawn point something you can stand on
# exactly rather than approximately.
#
# Scattered points are checked against the navigation map and REJECTED back to
# the authored position if they do not land on it - see _scattered_position().
# The authored spot is the one position known to be standable, because someone
# placed an enemy there on purpose, so it is the right thing to fall back to.
#
# 0 disables the scatter and restores the old exact behaviour.
@export var spawn_scatter: float = 48.0

# How often a held-back respawn re-checks the distance above.
@export var retry_seconds: float = 2.0

# Off means the census still happens but nothing ever comes back. Useful for a
# boss arena or a story room that should stay cleared.
@export var enabled: bool = true


# =============================================================================
# STATE
# =============================================================================

# How far a scattered point may be dragged by the navigation map before it is
# abandoned in favour of the authored position.
#
# map_get_closest_point() always answers. Ask it about a point inside a wall
# and it hands back the nearest walkable spot, which can be most of a room
# away — so without a ceiling, scattering toward a wall would slide the spawn
# along it rather than rejecting the roll.
const SCATTER_SNAP_MAX := 24.0


# One entry per enemy the scene was authored with.
# { "scene_path": String, "packed": PackedScene, "position": Vector2,
#   "parent": NodePath }
#
# THE PackedScene IS HELD, NOT LOADED PER RESPAWN. load() used to run the first
# time each enemy type came back, which is a disk hit during play — Godot caches
# after that, so it was exactly one stutter per type, landing mid-fight rather
# than during a loading screen. Resolving them while the census is taken moves
# that cost to where the player is already waiting, and keeping the reference
# alive is what stops the cache dropping it again.
var _census: Array[Dictionary] = []


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# ONE FRAME LATER. The enemies' own _ready() has to have run before they are
	# in the "enemies" group, and a census taken in the same frame as theirs
	# would be a race decided by node order.
	await get_tree().process_frame

	# BOTH CHECKS, not just the first. A node removed from the tree but not yet
	# freed passes is_instance_valid(), and get_tree() then returns null — so
	# the next line raised "Attempt to call get_nodes_in_group on a null
	# instance" and the census was never taken, meaning nothing in that scene
	# ever respawned. _respawn_after() below checks both; this was the
	# inconsistent copy.
	if not is_instance_valid(self) or not is_inside_tree():
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

		# PRE-WARMED HERE. See the note on _census — this is the one disk hit
		# per enemy type, taken during load instead of during a fight. A path
		# that fails to load is kept in the census with a null scene so the
		# warning below names it once, rather than warning on every respawn.
		var packed: PackedScene = load(enemy.scene_file_path) as PackedScene
		if packed == null:
			push_warning("EnemyRespawner: cannot load %s — '%s' will not respawn"
				% [enemy.scene_file_path, enemy.name])
			continue

		var entry: Dictionary = {
			"scene_path": enemy.scene_file_path,
			"packed": packed,
			"position": enemy.global_position,
			"parent": get_path_to(enemy.get_parent()),
		}
		_census.append(entry)
		_watch(enemy, entry)

	if OS.is_debug_build():
		var kinds: Dictionary = {}
		for e in _census:
			kinds[e.get("scene_path", "")] = true
		print("[SPAWN] respawner watching %d enemies, %d scenes pre-loaded"
			% [_census.size(), kinds.size()])


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

	# THE AUTHORED POINT IS WHAT THE DISTANCE CHECK USES, not the scattered one.
	#
	# Rolling the scatter first and testing that would let a roll that happened
	# to land away from the player slip past a check the authored spot would
	# have failed — so standing on a spawn point would still leak an enemy in
	# behind you every so often. Decide whether this spawn may happen at all,
	# then decide where.
	var home: Vector2 = entry.get("position", Vector2.ZERO)
	if _player_too_close(home):
		# HELD, NOT CANCELLED. Retrying keeps the enemy owed; cancelling would
		# mean a player who camps a spawn point clears the room permanently.
		_respawn_after(entry, maxf(retry_seconds, 0.5))
		return

	var spawn_position: Vector2 = _scattered_position(home)

	var packed: PackedScene = entry.get("packed") as PackedScene
	if packed == null:
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

	# THE RESPAWNED ENEMY IS DRAWN SLIDING IN FROM THE WORLD ORIGIN WITHOUT
	# THIS — a whole sprite streaking across the map, not a subtle one.
	#
	# add_child() is what resets interpolation automatically, and it runs on
	# the line ABOVE the position. So the reset captured (0, 0) as both the
	# previous and current transform, and then global_position moved the node
	# to its spawn point — leaving exactly the blend the reset was meant to
	# prevent. Setting the position first would work equally well; the
	# explicit call is used because BaseEnemy._ready() reads global_position
	# to set spawn_position, and _ready() runs inside add_child().
	#
	# Same mechanism as BaseEnemy.spawn_projectile_node(), which carries the
	# long explanation. This is the one place it was missed, and it is the
	# most visible one in the game because it fires every time anything
	# respawns.
	enemy.reset_physics_interpolation()

	_watch(enemy, entry)


func _scattered_position(base: Vector2) -> Vector2:
	if spawn_scatter <= 0.0:
		return base

	# sqrt(randf()) SPREADS EVENLY OVER THE DISC. A plain randf() on the radius
	# clusters toward the centre, because a ring at radius r has circumference
	# proportional to r and there is more room further out. Same idiom
	# bossprojectile.gd uses for water's extra pools.
	var angle: float = randf() * TAU
	var dist: float = spawn_scatter * sqrt(randf())
	var candidate: Vector2 = base + Vector2(cos(angle), sin(angle)) * dist

	var world: World2D = get_world_2d()
	if world == null:
		return base

	var map: RID = world.navigation_map
	if not map.is_valid():
		return base

	# NO NAVMESH MEANS NO SCATTER, and that is deliberately stricter than
	# BaseEnemy.clamp_to_navigation(), which returns the unclamped point in
	# this case. It can afford to: it is placing a telegraphed spike, and a
	# spike slightly off is a spike slightly off. An ENEMY placed inside a wall
	# is a bug the player has to walk away from.
	#
	# elusion.tscn has no NavigationRegion2D and field.tscn does, so this is a
	# live branch rather than a hypothetical: spawns scatter in the field and
	# stay exact in town.
	if NavigationServer2D.map_get_regions(map).is_empty():
		return base

	var nav: Vector2 = NavigationServer2D.map_get_closest_point(map, candidate)

	# REJECTED BACK TO THE AUTHORED SPOT, not clamped onto the nearest floor.
	# map_get_closest_point() always answers, so a roll into a wall comes back
	# as the nearest walkable tile — which could be through the wall, in the
	# next room. A bad roll should be discarded, not relocated.
	if nav.distance_to(candidate) > SCATTER_SNAP_MAX:
		return base

	return nav


func _player_too_close(spawn_position: Vector2) -> bool:
	if min_player_distance <= 0.0:
		return false

	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player == null or not is_instance_valid(player):
		return false

	return player.global_position.distance_to(spawn_position) < min_player_distance
