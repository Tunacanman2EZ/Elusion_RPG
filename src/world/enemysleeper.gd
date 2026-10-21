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
#
# AND OUT OF THE PICTURE (0.66.0). A sleeper is 1,100 px or more from every
# player, and the widest view the camera gives is 640 px across - it is never
# on anybody's screen. Hidden, the renderer stops sorting and culling its five
# or so pictures every frame, which in the Big Field at 4x is 1,100 monsters'
# worth. Woken, it is shown again as it was (a monster something else had
# hidden stays hidden).
#
# A JUMP IS LOOKED AT THE SAME FRAME. Four times a second is plenty for a
# player walking, but a player put somewhere new (a door, a portal inside the
# area) could arrive among hidden monsters and watch them pop in a quarter
# second later. So when this game's player has moved more than JUMP_DISTANCE
# since the last frame - further than any walk or dash covers in one - the
# check runs at once, before that frame is drawn.
#
# AND THE NEAR ONES DOZE (0.66.0). Awake is not the same as busy: in the Big
# Field at 4x, 700 of the 790 awake monsters round one player were standing
# at home with nobody in reach, and their brains were still 2.7 ms of each
# 9 ms physics tick. Each pass, a monster at home that is not after anybody
# and has nobody within its notice_reach() + DOZE_MARGIN is set dozing
# (BaseEnemy.dozing) and skips its brain until the next pass. A player can
# not cover DOZE_MARGIN in a pass, so nothing is noticed any later than it
# was; a hit, a walk home or any movement rouses it on the spot.
extends Node

const Targets := preload("res://src/shared/targets.gd")

const SLEEP_DISTANCE := 1100.0
const WAKE_DISTANCE := 900.0
const CHECK_SECONDS := 0.25
const JUMP_DISTANCE := 150.0
# Further than any player walks or dashes between two passes.
const DOZE_MARGIN := 150.0
const NODE_NAME := "enemysleeper"

# Off wakes everyone at once and leaves them awake. For measuring, and an
# escape hatch if a fight ever needs the whole map awake.
var enabled: bool = true:
	set(value):
		enabled = value
		if not enabled:
			_wake_all()

var _left: float = 0.0
var _seen_at: Vector2 = Vector2.ZERO
var _seen: bool = false


static func add_to(scene: Node) -> Node:
	var sleeper := (load("res://src/world/enemysleeper.gd") as GDScript).new() as Node
	sleeper.name = NODE_NAME
	scene.add_child(sleeper)
	return sleeper


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0 and not player_jumped():
		return
	_left = CHECK_SECONDS
	check_now()


func player_jumped() -> bool:
	"""True when this game's player is further than JUMP_DISTANCE from where it
	stood the last time this asked - see A JUMP IS LOOKED AT THE SAME FRAME."""
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		_seen = false
		return false
	var at: Vector2 = player.global_position
	var jumped: bool = _seen and at.distance_to(_seen_at) > JUMP_DISTANCE
	_seen_at = at
	_seen = true
	return jumped


func check_now() -> int:
	"""One pass. Returns how many enemies are asleep after it."""
	if get_tree() == null:
		return 0
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if not enabled or player == null:
		return 0
	# EVERYBODY THE MONSTERS MAY CHASE, not just this game's player (shared
	# monsters, 0.7.0): on the game running an area, a monster next to another
	# player must stay awake even when this player is a mile off. Read once
	# per pass - a pass is every enemy against every one of these.
	var targets: Array = Targets.all(get_tree())
	var spots: Array[Vector2] = []
	for body in targets:
		spots.append((body as Node2D).global_position)
	if spots.is_empty():
		spots.append(player.global_position)
	var asleep: int = 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node2D
		if enemy == null or _never_sleeps(enemy):
			continue
		var far: float = INF
		for spot in spots:
			far = minf(far, spot.distance_to(enemy.global_position))
		var sleeping: bool = enemy.has_meta(&"asleep")
		if sleeping and far <= WAKE_DISTANCE:
			_wake(enemy)
			sleeping = false
		elif not sleeping and far > SLEEP_DISTANCE:
			put_to_sleep(enemy)
			sleeping = true
		if sleeping:
			asleep += 1
		else:
			doze_or_rouse(enemy, far)
	return asleep


static func doze_or_rouse(enemy: Node, far: float) -> void:
	"""AND THE NEAR ONES DOZE: `far` is how far the nearest player is."""
	var monster := enemy as BaseEnemy
	if monster == null:
		return
	monster.dozing = not monster.engaged and not monster.is_returning_home \
		and far > monster.notice_reach() + DOZE_MARGIN


static func _never_sleeps(enemy: Node) -> bool:
	# A BOSS FIGHTS WHOEVER IS IN ITS ROOM. The arenas are small enough that
	# this never comes up today, and a boss frozen mid-pattern by a player
	# stepping back is not a thing worth finding out about later.
	return enemy.is_in_group("unpushable")


static func put_to_sleep(enemy: Node) -> void:
	"""Stops it thinking and takes it out of the picture - see AND OUT OF THE
	PICTURE above. Remembers whether it was shown, for waking."""
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	enemy.set_meta(&"asleep", true)
	var item := enemy as CanvasItem
	if item != null:
		enemy.set_meta(&"asleep_shown", item.visible)
		item.visible = false


func _wake(enemy: Node) -> void:
	enemy.process_mode = Node.PROCESS_MODE_INHERIT
	enemy.remove_meta(&"asleep")
	var item := enemy as CanvasItem
	if item != null and enemy.has_meta(&"asleep_shown"):
		item.visible = bool(enemy.get_meta(&"asleep_shown"))
		enemy.remove_meta(&"asleep_shown")


func _wake_all() -> void:
	if get_tree() == null:
		return
	for node in get_tree().get_nodes_in_group("enemies"):
		if node.has_meta(&"asleep"):
			_wake(node)
		if node is BaseEnemy:
			(node as BaseEnemy).dozing = false
