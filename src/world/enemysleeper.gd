# enemysleeper.gd - enemies far from the player stop thinking until it comes
# near. Added to every area by AreaRegistry, the way MapBackdrop is.
#
# WHY. Every enemy ran its whole brain on every physics tick, wherever the
# player was: navigation, the formation ring, avoidance, move_and_slide. The
# Field's 35 cost 3.6 ms a tick at 80 ticks a second. A field twice the size,
# packed the way the owner wants it (day 2: "density with enemies"), holds
# four times that many, and nearly all of them are a screen or more away
# doing nothing anybody can see.
#
# HOW. Four times a second, every enemy beyond SLEEP_DISTANCE of the player
# is set to PROCESS_MODE_DISABLED and every sleeper within WAKE_DISTANCE is
# put back. Disabled means no _process, no _physics_process, no animation and
# no timers - a body standing still - while its collision stays where it is.
#
# THE PROCESS MODE, NOT set_physics_process(), ON PURPOSE. field.gd freezes
# every enemy with set_physics_process(false) while the welcome story plays,
# and unfreezes them all afterwards. Using the same switch here would let the
# story's unfreeze wake the whole map, and let a wake here undo the story's
# freeze. The two are separate switches and neither touches the other's.
#
# TWO DISTANCES, so an enemy at the edge does not flick between asleep and
# awake on every check as the player shuffles about.
extends Node

const SLEEP_DISTANCE := 1100.0
const WAKE_DISTANCE := 900.0
const CHECK_SECONDS := 0.25
const NODE_NAME := "enemysleeper"

# Off wakes everyone at once and leaves them awake. For measuring, and an
# escape hatch if a fight ever needs the whole map awake.
var enabled: bool = true:
	set(value):
		enabled = value
		if not enabled:
			_wake_all()

var _left: float = 0.0


static func add_to(scene: Node) -> Node:
	var sleeper := (load("res://src/world/enemysleeper.gd") as GDScript).new() as Node
	sleeper.name = NODE_NAME
	scene.add_child(sleeper)
	return sleeper


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = CHECK_SECONDS
	check_now()


func check_now() -> int:
	"""One pass. Returns how many enemies are asleep after it."""
	if get_tree() == null:
		return 0
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if not enabled or player == null:
		return 0
	var at: Vector2 = player.global_position
	var asleep: int = 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node2D
		if enemy == null or _never_sleeps(enemy):
			continue
		var far: float = at.distance_to(enemy.global_position)
		var sleeping: bool = enemy.has_meta(&"asleep")
		if sleeping and far <= WAKE_DISTANCE:
			_wake(enemy)
		elif not sleeping and far > SLEEP_DISTANCE:
			enemy.process_mode = Node.PROCESS_MODE_DISABLED
			enemy.set_meta(&"asleep", true)
			asleep += 1
		elif sleeping:
			asleep += 1
	return asleep


static func _never_sleeps(enemy: Node) -> bool:
	# A BOSS FIGHTS WHOEVER IS IN ITS ROOM. The arenas are small enough that
	# this never comes up today, and a boss frozen mid-pattern by a player
	# stepping back is not a thing worth finding out about later.
	return enemy.is_in_group("unpushable")


func _wake(enemy: Node) -> void:
	enemy.process_mode = Node.PROCESS_MODE_INHERIT
	enemy.remove_meta(&"asleep")


func _wake_all() -> void:
	if get_tree() == null:
		return
	for node in get_tree().get_nodes_in_group("enemies"):
		if node.has_meta(&"asleep"):
			_wake(node)
