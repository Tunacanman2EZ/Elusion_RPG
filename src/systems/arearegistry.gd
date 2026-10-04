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
	# Day 2: the Field at twice the size, built from the blueprint, for the
	# owner to decorate. No door leads here yet; the owner reaches it with
	# /goto bigfield. The day it replaces the Field, the town's portal points
	# here and this note goes.
	"bigfield":  "res://scene/bigfield.tscn",
	"boss":      "res://scene/boss.tscn",
	"bossarena": "res://scene/bossarena.tscn",
	"easteregg": "res://scene/easteregg.tscn",
}

# WHAT A PLAYER READS for each area. Every screen that named an area ran the
# id through capitalize(), so the map, the players list, the trade window and
# a ladder's pin said "Bossarena" and "Easteregg". One table, and
# display_name() is the only way an area id becomes text on screen.
const AREA_NAMES := {
	"elusion":   "Elusion",
	"field":     "Field",
	"bigfield":  "Big Field",
	"boss":      "Boss Room",
	"bossarena": "Boss Arena",
	"easteregg": "Easter Egg",
}


func display_name(area_id: String) -> String:
	# An id this build does not know (a newer server's area) still reads as
	# words rather than as nothing.
	return str(AREA_NAMES.get(area_id, area_id.capitalize()))


# How long a pending spawn keeps looking for a player before giving up. A scene
# change plus two frames of settling is well under a second; five is generous
# and stops a failed transition leaving something armed forever.
const SPAWN_WAIT_SECONDS := 5.0

# Loaded scenes, kept for the session. Areas are re-entered constantly and
# load() on a scene already in memory is wasted work.
#
# THIS IS ALSO WHAT KEEPS A BACKGROUND LOAD ALIVE. Godot's resource cache only
# holds a scene while something references it, so a prefetch that finished and
# was not stored here would be thrown away and loaded again on the way through
# the door. ladder.gd and leavetown.gd still call load() on a path; it is
# instant because the scene is held here.
var _cache: Dictionary = {}

# Areas loading on a worker thread right now: area_id -> true. At most one -
# see _prefetch_queue.
var _prefetching: Dictionary = {}

# Areas asked for that have not started yet, oldest first.
#
# ONE AT A TIME, ON PURPOSE. Every request handed to the loader at once runs on
# its own worker, and a player on a two-core laptop would feel five scenes
# compiling while they walk around town. Queued, the whole set still finishes
# long before anyone reaches the second door.
var _prefetch_queue: Array[String] = []

# Where to put the player once the next area finishes loading. A scene change
# frees the old player and builds a new one, so the position cannot simply be
# assigned across the transition — it has to wait for the new body to exist.
var _pending_spawn: Vector2 = Vector2.ZERO
var _has_pending_spawn: bool = false
var _spawn_wait_left: float = 0.0


const MapBackdrop := preload("res://src/world/mapbackdrop.gd")
const EnemySleeper := preload("res://src/world/enemysleeper.gd")


func _ready() -> void:
	_update_processing()

	# BLACK PAST THE EDGE OF THE MAP, GREY IN THE GAPS OF ITS TILES. The screen
	# is made black here, at runtime, and each area is given a backdrop the
	# grey the tiles were painted over (mapbackdrop.gd has the whole story).
	# project.godot keeps the engine's grey, so the editor shows a scene the
	# way the game does.
	RenderingServer.set_default_clear_color(MapBackdrop.OUTSIDE)
	get_tree().scene_changed.connect(_on_scene_changed)

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


func _on_scene_changed() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null or not AREAS.values().has(scene.scene_file_path):
		return
	if scene.get_node_or_null("mapbackdrop") == null:
		MapBackdrop.add_to(scene)
	# Far-away enemies stop thinking until the player comes near; see
	# enemysleeper.gd.
	if scene.get_node_or_null(EnemySleeper.NODE_NAME) == null:
		EnemySleeper.add_to(scene)


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
	"""The scene for an area, or null. Loaded once and kept.

	Never slower than it was: a scene still loading in the background is
	waited for rather than loaded a second time, and one that never started
	loads the old way, right here."""
	if not AREAS.has(area_id):
		return null
	if _cache.has(area_id):
		return _cache[area_id]
	if _prefetching.has(area_id):
		return _finish_prefetch(area_id)
	_prefetch_queue.erase(area_id)

	var scene = load(AREAS[area_id])
	if scene is PackedScene:
		_cache[area_id] = scene
		return scene

	push_error("AreaRegistry: %s did not load as a PackedScene." % AREAS[area_id])
	return null


# =============================================================================
# LOADING AHEAD
# =============================================================================
#
# THE LOGIN SCREEN USED TO LOAD THE WHOLE WORLD BEFORE IT APPEARED. The chain:
# loginmenu.tscn exports characterselect.tscn, characterselect.gd preloaded
# elusion.tscn, and elusion.tscn exports field.tscn - so the first frame of the
# login screen waited on the town, the field, the HUD, every panel and about
# sixty scripts compiling. Measured cold in the sandbox that was 1.8 of the 2.6
# seconds from launch to a login box; gameover.tscn, which pulls none of it,
# loads in 25 ms.
#
# Now the login screen asks for the town here and appears straight away, and
# the town loads on a worker thread while the player types. Character select
# takes it with scene_for(), which only waits if the player beat the loader.

func scene_at(path: String) -> PackedScene:
	"""A scene by file path - for the doors that name their destination that way
	(ladder.gd, victoryteleporter.gd, gameover.gd). An area's path goes through
	scene_for(); anything else is an ordinary load().

	NEVER load() AN AREA'S PATH DIRECTLY. In Godot 4.6.1 a main-thread load() of
	a scene that is loading in the background waits forever: reproduced in the
	sandbox with boss.tscn and bossarena.tscn (not with a small scene, and not
	with any of their dependencies), and found because a sabotage of scene_for()
	made the suite hang instead of fail. The game would freeze on the door with
	no error. scene_for() collects the background load with load_threaded_get(),
	which is the one call that is safe while it runs."""
	for area_id in AREAS:
		if AREAS[area_id] == path:
			return scene_for(area_id)
	var scene = load(path)
	return scene if scene is PackedScene else null


static func loads_in_background() -> bool:
	"""False in a build without threads - which is how the browser build is
	exported (export_presets.cfg, variant/thread_support).

	THERE, load_threaded_request() IS A LOAD. Measured in Chromium on the 4.6.1
	no-threads web export: asking for the town as the login screen opened held
	that screen's first frame 2.2 s longer - the login box at 4.35 s against
	2.1-2.25 s without the request - because the whole town loaded inside it.
	So a build without threads loads nothing ahead. Each area loads when it is
	entered: behind a door's fade, or under "Loading the world..." at character
	select, where a player expects to wait."""
	return not OS.has_feature("nothreads")


func prefetch(area_id: String) -> bool:
	"""Start loading an area in the background. True when it is loaded, loading
	or queued - or, where nothing loads ahead (loads_in_background()), when it
	will load on the way in; false for an area that does not exist."""
	if not AREAS.has(area_id):
		return false
	if not loads_in_background():
		return true
	if _cache.has(area_id) or _prefetching.has(area_id) or _prefetch_queue.has(area_id):
		return true
	if _prefetching.is_empty():
		_start_prefetch(area_id)
	else:
		_prefetch_queue.append(area_id)
	return true


func prefetch_all() -> void:
	"""Queue every area, so no door in the game waits on the disk. Called once
	the player is in the world; the set is small and kept for the session."""
	for area_id in area_ids():
		prefetch(area_id)


func is_ready(area_id: String) -> bool:
	"""True when scene_for() would return without waiting."""
	if _cache.has(area_id):
		return true
	if _prefetching.has(area_id):
		return ResourceLoader.load_threaded_get_status(AREAS[area_id]) \
			!= ResourceLoader.THREAD_LOAD_IN_PROGRESS
	return false


func is_loading(area_id: String) -> bool:
	"""True while an area is loading or waiting its turn in the background."""
	return _prefetching.has(area_id) or _prefetch_queue.has(area_id)


func _start_prefetch(area_id: String) -> void:
	var err := ResourceLoader.load_threaded_request(AREAS[area_id], "PackedScene")
	if err != OK:
		# NOT FATAL. scene_for() loads it the old way when it is needed; the
		# only cost of a refused request is the wait this was meant to hide.
		push_warning("AreaRegistry: could not start loading %s in the background (error %d)."
			% [AREAS[area_id], err])
		_start_next_prefetch()
		return
	_prefetching[area_id] = true
	_update_processing()


func _start_next_prefetch() -> void:
	while _prefetching.is_empty() and not _prefetch_queue.is_empty():
		var next: String = _prefetch_queue.pop_front()
		if not _cache.has(next):
			_start_prefetch(next)


func _collect_prefetches() -> void:
	for area_id in _prefetching.keys():
		if ResourceLoader.load_threaded_get_status(AREAS[area_id]) \
				== ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_finish_prefetch(area_id)
	_start_next_prefetch()
	_update_processing()


func _finish_prefetch(area_id: String) -> PackedScene:
	# load_threaded_get() WAITS when the load is still running, which is what
	# scene_for() wants when the player is at the door before the loader is.
	# It is also the ONLY way to release the loader's hold on the request, so
	# a finished prefetch is always collected, failed or not.
	var scene = ResourceLoader.load_threaded_get(AREAS[area_id])
	_prefetching.erase(area_id)
	if scene is PackedScene:
		_cache[area_id] = scene
		_start_next_prefetch()
		_update_processing()
		return scene
	push_error("AreaRegistry: %s did not load as a PackedScene in the background." % AREAS[area_id])
	_start_next_prefetch()
	_update_processing()
	return null


func _update_processing() -> void:
	# _process() has two jobs now - landing a player after a teleport, and
	# collecting finished background loads - and runs while either needs it.
	# Each job used to be able to switch it off on its own, which would have
	# stranded the other.
	set_process(_has_pending_spawn or not _prefetching.is_empty() or not _prefetch_queue.is_empty())


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
	# PLACED, NOT MOVED: told so after the position (CLAUDE.md, "reset_physics_
	# interpolation() goes after the position"), or it is drawn streaking in
	# from where it stood - and the camera goes with it at once.
	if player is Node2D:
		(player as Node2D).reset_physics_interpolation()
	if player.has_method("snap_camera"):
		player.snap_camera()
	return true


# =============================================================================
# LANDING AFTER A TRANSITION
# =============================================================================

func _arm_spawn(spawn_position: Vector2) -> void:
	_pending_spawn = spawn_position
	_has_pending_spawn = true
	_spawn_wait_left = SPAWN_WAIT_SECONDS
	_update_processing()


func _apply_spawn_now() -> void:
	if not _has_pending_spawn:
		return
	if place_player(_pending_spawn):
		_has_pending_spawn = false
		_update_processing()


func _process(delta: float) -> void:
	# WAITING FOR A BODY THAT DOES NOT EXIST YET. change_scene_to_packed is
	# deferred and the new player runs its own _ready() afterwards, so there is
	# no single moment to hook — node_added fires before the player has joined
	# its group, and awaiting frames inside go_to() would make every caller a
	# coroutine for the sake of one assignment. Watching for it is the simplest
	# thing that is actually correct.
	#
	# AND COLLECTING BACKGROUND LOADS, which is the other reason this runs.
	if not _prefetching.is_empty() or not _prefetch_queue.is_empty():
		_collect_prefetches()

	if not _has_pending_spawn:
		_update_processing()
		return

	_spawn_wait_left -= delta
	if _spawn_wait_left <= 0.0:
		# GIVE UP RATHER THAN LINGER. An armed spawn that never fired would
		# teleport the player the next time any scene happened to load.
		push_warning("AreaRegistry: no player appeared to place; dropping the spawn.")
		_has_pending_spawn = false
		_update_processing()
		return

	_apply_spawn_now()


func _find_player() -> Node:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("player")
