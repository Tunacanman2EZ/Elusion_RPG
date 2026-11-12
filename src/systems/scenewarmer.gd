extends Node
# scenewarmer.gd - READY BEFORE THEY COME (0.152.0): the scenes a minigame
# will bring, loaded before it brings them.
#
# The owner: "lets work on chunking the mini games and measuring everything
# in those". Measured in the container (zz/mgbench/loadcost.gd): a monster's
# first appearance was nearly all LOADING its scene - a wind sprite 95 ms,
# the earth boss 304 ms, a wave of five in the Descent 25-28 ms - and making
# one after that well under a millisecond. A minigame brings its monsters by
# path, so nothing loaded them with the area: the first of each kind loaded
# in the frame it came, in the middle of a fight.
#
# HOW. A minigame hands its warmer every scene it may bring, in the order it
# will want them (warm()). Where loading runs on a worker thread
# (AreaRegistry.loads_in_background() - the desktop builds) they load one at
# a time in the background and cost the game's frames nothing. Where it
# cannot (the browser build has no threads: there a request IS a load), one
# a frame, and only while the minigame says the moment is calm (`calm`: a
# corridor, a countdown, a start screen, between fights) - a short stall
# nobody is fighting through. Each loaded scene is held (`held`), so Godot's
# cache keeps it; it goes with the minigame. A scene still cold when it is
# wanted loads then, as it always did. The readout names the time
# (PerfOverlay.spend(&"warming")) and marks each one ("scenes warmed").

const NODE_NAME := "scenewarmer"

# Whether now is a calm moment for a load that holds the frame (the browser).
var calm: Callable = func() -> bool: return true
# Whether loads run on a worker thread here (a seam for the suite).
var threads: Callable = func() -> bool: return bool(AreaRegistry.call("loads_in_background"))
var queue: PackedStringArray = PackedStringArray()
var held: Dictionary = {}
var _loading: String = ""
var _refused: bool = false


static func add_to(parent: Node) -> Node:
	"""A warmer for `parent`'s minigame, made once."""
	var have: Node = parent.get_node_or_null(NodePath(NODE_NAME))
	if have != null:
		return have
	var warmer: Node = (load("res://src/systems/scenewarmer.gd") as GDScript).new()
	warmer.name = NODE_NAME
	parent.add_child(warmer)
	return warmer


func _ready() -> void:
	set_process(not queue.is_empty())


func _exit_tree() -> void:
	# A load still on its worker is collected, so none is left unclaimed.
	if _loading != "":
		ResourceLoader.load_threaded_get(_loading)
		_loading = ""


func warm(paths: Array) -> void:
	"""Load these scenes before they are wanted, in this order."""
	for each in paths:
		var path: String = str(each)
		if path == "" or held.has(path) or queue.has(path) or path == _loading:
			continue
		if not ResourceLoader.exists(path):
			continue
		queue.append(path)
	set_process(not queue.is_empty() or _loading != "")


func is_warm(path: String) -> bool:
	return held.has(path)


func cold() -> int:
	"""How many are still to load."""
	return queue.size() + (1 if _loading != "" else 0)


func _process(_delta: float) -> void:
	var from: int = Time.get_ticks_usec()
	_step()
	PerfOverlay.spend(&"warming", Time.get_ticks_usec() - from)


func _step() -> void:
	if _loading != "":
		var status: int = ResourceLoader.load_threaded_get_status(_loading)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			held[_loading] = ResourceLoader.load_threaded_get(_loading)
			PerfOverlay.mark(&"scenes warmed")
		_loading = ""
	if queue.is_empty():
		set_process(false)
		return
	var path: String = queue[0]
	if ResourceLoader.has_cached(path):
		queue.remove_at(0)
		held[path] = load(path)
		return
	if bool(threads.call()) and not _refused:
		if ResourceLoader.load_threaded_request(path, "PackedScene") == OK:
			queue.remove_at(0)
			_loading = path
			return
		# Refused: the rest load as the browser's do.
		_refused = true
	if not bool(calm.call()):
		return
	queue.remove_at(0)
	held[path] = load(path)
	PerfOverlay.mark(&"scenes warmed")
