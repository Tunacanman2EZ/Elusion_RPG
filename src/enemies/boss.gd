# boss.gd — root script for boss.tscn, the final floor reached via
# the ladder down from field.tscn. mirrors field.gd's structure closely:
# spawns the actual player character (same responsibility elusion.gd has
# for town), positions them at the correct FieldPortal arrival marker.
#
# NO story screen here on purpose, unlike field.gd — the "many heroes have
# reincarnated..." narration belongs to the FIRST arrival into danger
# (leaving town), not a second telling on reaching the final floor. if a
# boss-specific narrative beat is ever wanted here (something like "this
# is where it ends"), it'd use the exact same StoryScreen system field.gd
# already uses — just with different text and no reason to duplicate it
# preemptively before you know if you actually want one.
extends Node2D


# =============================================================================
# STATE
# =============================================================================

var current_player: Node = null

@onready var active_char_ui = get_node_or_null("hudcontrol")


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	spawn_player_from_selection()
	_position_player_at_spawn()


# =============================================================================
# PLAYER SPAWN  (mirrors field.gd / elusion.gd)
# =============================================================================

func spawn_player_from_selection() -> void:
	var slot_idx: int = CharacterData.active_character_index

	var scenes := [
		preload("res://scene/characters/warrior.tscn"),  # slot 0
		preload("res://scene/characters/mage.tscn"),     # slot 1
		preload("res://scene/characters/tank.tscn"),     # slot 2
		preload("res://scene/characters/healer.tscn"),   # slot 3
	]

	if slot_idx < 0 or slot_idx >= scenes.size():
		push_error("boss.gd: no valid character slot selected! index: %d" % slot_idx)
		return

	if current_player and current_player.is_inside_tree():
		current_player.queue_free()

	var player: Node = scenes[slot_idx].instantiate()
	if player == null:
		push_error("boss.gd: player scene failed to instance!")
		return

	var spawn_parent: Node = self
	# "ysortworld" — renamed in boss.tscn so all three world scenes agree.
	# This lookup and the scene must always be changed together: the fallback
	# below is a working path, so a mismatch doesn't error, it just parents
	# the player to the scene root outside the Y-sort space and draws them in
	# front of everything. That is exactly how the same typo hid in field.gd.
	var y_world: Node = get_node_or_null("ysortworld")
	if y_world != null:
		var player_container: Node = y_world.get_node_or_null("player")
		spawn_parent = player_container if player_container != null else y_world

	spawn_parent.add_child(player)
	current_player = player

	_attach_player_to_hud()


# =============================================================================
# GLOBAL EVENT RELAY  (REMOVED)
# =============================================================================
# This file used to carry a _wire_player_signals() that bridged the player's
# own signals onto GameState's global bus. It was deleted, along with the
# identical copies in the other two world scripts, because NOTHING SUBSCRIBED
# TO THAT BUS - see the note in gamestate.gd.
#
# The worst of it was player_moved: player.gd emits `moved` on every physics
# frame it is walking, which at 180 ticks/second meant 180 lambda dispatches
# and 180 three-argument signal emissions a second, all arriving nowhere.
#
# gamestate.gd still declares the signals, and its comment explains exactly how
# to wire this back when there is something on the other end.


func _attach_player_to_hud() -> void:
	if active_char_ui and active_char_ui.has_method("set_active_character"):
		active_char_ui.set_active_character(current_player)


# =============================================================================
# SPAWN POSITIONING  (mirrors field.gd)
# =============================================================================

func _position_player_at_spawn() -> void:
	if GameState.next_spawn_id == "":
		return

	var target_id: String = GameState.next_spawn_id
	GameState.next_spawn_id = ""

	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		print("boss.gd: no player found in group 'player' — can't position at spawn")
		push_warning("boss.gd: no player found in group 'player' — can't position at spawn")
		return

	for portal in get_tree().get_nodes_in_group("fieldportals"):
		if "portal_id" in portal and portal.portal_id == target_id:
			player.global_position = portal.global_position
			print("boss.gd: positioned player at spawn '%s' -> %s" % [target_id, portal.global_position])
			return

	print("boss.gd: no FieldPortal found matching id '%s'" % target_id)
	push_warning("boss.gd: no FieldPortal found matching id '%s'" % target_id)
