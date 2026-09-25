# arearegistry.gd — the one place that knows an area's name and its scene.
#
# WHY THIS HAD TO EXIST. Until now nothing in the game could turn the string
# "field" into something to load. Areas were reached only by walking into a
# specific node that carried its own exported PackedScene — ladder.gd and
# leavetown.gd each hold one — so the destination was baked into the furniture
# rather than named anywhere. That works for a door. It does not work for
# anything that has to send somebody somewhere by NAME:
#
#   - a staff teleport, which arrives as {"area": "field", "x": ..., "y": ...}
#   - the server spawning a player back where they logged out, since
#     saves.area is a string
#   - any future "return to town", world map travel, or summon
#
# THE ID IS THE SCENE'S FILENAME, and that is not a new convention — it is the
# one WorldMap.area_id() already uses, and its comment explains why: the
# filename cannot drift from reality the way a hand-kept label can. Matching it
# exactly is the point. If these two ever disagreed, the minimap would be
# drawing one area while the game thought you were in another, so _ready()
# asserts the agreement rather than trusting it.
#
# NOT EVERY SCENE IS AN AREA. ladderup.tscn and ladderdown.tscn are Area2D
# props you walk into, not places, so they are deliberately absent.
extends Node


# area id -> scene path. The key MUST equal the file's basename; _ready()
# refuses to let that slide.
const AREAS := {
	"elusion":   "res://scene/elusion.tscn",
	"field":     "res://scene/field.tscn",
	"boss":      "res://scene/boss.tscn",
	"bossarena": "res://scene/bossarena.tscn",
	"easteregg": "res://scene/easteregg.tscn",
}

# How long a pending spawn keeps looking for a player before giving up. A scene
# change plus two frames of settling is well under a second; five is generous
# and stops a failed transition leaving something armed forever.
const SPAWN_WAIT_SECONDS := 5.0

# Loaded scenes, kept for the session. Areas are re-entered constantly and
# load() on a scene already in memory is wasted work.
var _cache: Dictionary = {}

# Where to put the player once the next area finishes loading. A scene change
# frees the old player and builds a new one, so the position cannot simply be
# assigned across the transition — it has to wait for the new body to exist.
var _pending_spawn: Vector2 = Vector2.ZERO
var _has_pending_spawn: bool = false
var _spawn_wait_left: float = 0.0


func _ready() -> void:
	set_process(false)

	if not OS.is_debug_build():
		return

	# BOTH OF THESE ARE DEBUG-ONLY AND LOUD ON PURPOSE. A missing scene or a
	# drifted id is a bug that otherwise surfaces as a teleport that silently
	# does nothing, which is the hardest kind to chase.
	for area_id in AREAS:
		var path: String = AREAS[area_id]
		if not ResourceLoader.exists(path):
			push_error("AreaRegistry: '%s' points at %s, which does not exist." % [area_id, path])
		elif path.get_file().get_basename() != area_id:
			push_error("AreaRegistry: '%s' maps to %s — the id must equal the filename, "
				% [area_id, path] + "because WorldMap.area_id() derives it that way.")

	print("[BOOT] AreaRegistry: %d areas" % AREAS.size())


# =============================================================================
# LOOKUP
# =============================================================================

func has_area(area_id: String) -> bool:
	return AREAS.has(area_id)


func area_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for area_id in AREAS:
		ids.append(area_id)
	ids.sort()
	return ids


func scene_for(area_id: String) -> PackedScene:
	"""The scene for an area, or null. Loaded once and kept."""
	if not AREAS.has(area_id):
		return null
	if _cache.has(area_id):
		return _cache[area_id]

	var scene = load(AREAS[area_id])
	if scene is PackedScene:
		_cache[area_id] = scene
		return scene

	push_error("AreaRegistry: %s did not load as a PackedScene." % AREAS[area_id])
	return null


func current_area_id() -> String:
	# DELEGATED, NOT DUPLICATED. WorldMap already answers this, and two
	# implementations of "where am I" is one more than can be kept in step.
	if WorldMap != null and WorldMap.has_method("area_id"):
		return WorldMap.area_id()
	var scene: Node = get_tree().current_scene if get_tree() != null else null
	if scene == null or scene.scene_file_path == "":
		return ""
	return scene.scene_file_path.get_file().get_basename()


# =============================================================================
# GOING THERE
# =============================================================================

func go_to(area_id: String, spawn_position = null) -> bool:
	"""
	Travel to an area, optionally landing on a specific spot.

	Returns false when the area is unknown — the caller can then say so rather
	than fading to black and arriving nowhere.
	"""
	var scene: PackedScene = scene_for(area_id)
	if scene == null:
		push_warning("AreaRegistry: no area called '%s'." % area_id)
		return false

	if spawn_position is Vector2:
		_arm_spawn(spawn_position)

	# ALREADY THERE: no transition, just move. Fading the screen to black to
	# arrive in the room you are standing in reads as a bug.
	if current_area_id() == area_id:
		_apply_spawn_now()
		return true

	SceneTransition.change_scene(scene)
	return true


func place_player(spawn_position: Vector2) -> bool:
	"""Move the player within the area they are already in. True if it landed."""
	var player: Node = _find_player()
	if player == null:
		return false
	player.global_position = spawn_position
	return true


# =============================================================================
# LANDING AFTER A TRANSITION
# =============================================================================

func _arm_spawn(spawn_position: Vector2) -> void:
	_pending_spawn = spawn_position
	_has_pending_spawn = true
	_spawn_wait_left = SPAWN_WAIT_SECONDS
	set_process(true)


func _apply_spawn_now() -> void:
	if not _has_pending_spawn:
		return
	if place_player(_pending_spawn):
		_has_pending_spawn = false
		set_process(false)


func _process(delta: float) -> void:
	# WAITING FOR A BODY THAT DOES NOT EXIST YET. change_scene_to_packed is
	# deferred and the new player runs its own _ready() afterwards, so there is
	# no single moment to hook — node_added fires before the player has joined
	# its group, and awaiting frames inside go_to() would make every caller a
	# coroutine for the sake of one assignment. Watching for it is the simplest
	# thing that is actually correct.
	if not _has_pending_spawn:
		set_process(false)
		return

	_spawn_wait_left -= delta
	if _spawn_wait_left <= 0.0:
		# GIVE UP RATHER THAN LINGER. An armed spawn that never fired would
		# teleport the player the next time any scene happened to load.
		push_warning("AreaRegistry: no player appeared to place; dropping the spawn.")
		_has_pending_spawn = false
		set_process(false)
		return

	_apply_spawn_now()


func _find_player() -> Node:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("player")
