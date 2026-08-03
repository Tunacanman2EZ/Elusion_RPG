# field.gd — root script for field.tscn. spawns the actual player
# character (same responsibility elusion.gd has for town — see that file,
# this mirrors its structure closely), positions them at the correct
# FieldPortal arrival marker, then plays the opening story narration.
#
# CHANGED: this scene previously had NO player-spawning logic at all — the
# "player" node visible in the editor tree is just an empty container,
# never an actual character instance. that's why spawn positioning kept
# finding nothing: there was genuinely no real player anywhere in this
# scene's tree yet, regardless of anything else. this fixes that by
# instantiating the correct class scene here too, same as town does.
#
# NOTE: uses "yworldsort" as the Y-sort container name, matching what's
# actually shown in this project's own scene trees — elusion.gd itself
# looks for "ysortworld" instead, which doesn't match and is worth
# checking separately; not touched here since that's a different file.
extends Node2D


# =============================================================================
# STATE
# =============================================================================

var current_player: Node = null

@onready var active_char_ui = $hudcontrol


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	spawn_player_from_selection()
	_position_player_at_spawn()

	var screen := StoryScreen.new()
	add_child(screen)
	screen.play([
		"Many heroes have reincarnated to a place of untold horror. And I am certain you will return to this spot again. Life is a gamble, but death certainly is a reality.",
		"A solo developer game, used as my college portfolio for Maestro University — coming from zero coding experience. From the creator of Elusion Studios, I humbly present my demo of Elusion. Graphics inspired by Chrono Trigger, gameplay inspired by Darza's Dominion, RuneScape, and Diablo — with the potential to become online one day.",
		"Artist: Ahvassa — https://ahvassa.itch.io/. Everything was handmade and paid for. Claude only helped me as an assistant to my degree, to learn faster.",
	])


# =============================================================================
# PLAYER SPAWN  (NEW — mirrors elusion.gd's spawn_player_from_selection())
# =============================================================================

func spawn_player_from_selection() -> void:
	# instantiates the character scene matching the slot selected at
	# character select, parents it into the y-sorted player container so
	# it depth-sorts correctly against enemies. unlike town, there's no
	# "playerspawn" marker here — initial position doesn't matter, since
	# _position_player_at_spawn() (below) immediately repositions to the
	# correct FieldPortal marker right after this runs.
	var slot_idx: int = CharacterData.active_character_index

	var scenes := [
		preload("res://scene/characters/warrior.tscn"),  # slot 0
		preload("res://scene/characters/mage.tscn"),     # slot 1
		preload("res://scene/characters/tank.tscn"),     # slot 2
		preload("res://scene/characters/healer.tscn"),   # slot 3
	]

	if slot_idx < 0 or slot_idx >= scenes.size():
		push_error("field.gd: no valid character slot selected! index: %d" % slot_idx)
		return

	if current_player and current_player.is_inside_tree():
		current_player.queue_free()

	var player: Node = scenes[slot_idx].instantiate()
	if player == null:
		push_error("field.gd: player scene failed to instance!")
		return

	var spawn_parent: Node = self
	var y_world: Node = get_node_or_null("yworldsort")
	if y_world != null:
		var player_container: Node = y_world.get_node_or_null("player")
		spawn_parent = player_container if player_container != null else y_world

	spawn_parent.add_child(player)
	current_player = player

	_wire_player_signals()
	_attach_player_to_hud()


# =============================================================================
# SIGNAL WIRING  (NEW — mirrors elusion.gd's _wire_player_signals())
# =============================================================================

func _wire_player_signals() -> void:
	if current_player == null:
		return

	current_player.took_damage.connect(func(amount, type):
		GameState.damage_dealt.emit(
			0,
			current_player.get_instance_id(),
			amount,
			type,
		))

	current_player.died.connect(func():
		GameState.player_died.emit(current_player.get_instance_id()))

	current_player.xp_gained_signal.connect(func(amount):
		GameState.xp_gained.emit(current_player.get_instance_id(), amount))

	current_player.gold_changed_signal.connect(func(amount):
		GameState.gold_changed.emit(current_player.get_instance_id(), amount))

	current_player.moved.connect(func(pos, dir):
		GameState.player_moved.emit(
			current_player.get_instance_id(),
			pos,
			dir,
		))


func _attach_player_to_hud() -> void:
	if active_char_ui and active_char_ui.has_method("set_active_character"):
		active_char_ui.set_active_character(current_player)


# =============================================================================
# SPAWN POSITIONING
# =============================================================================

func _position_player_at_spawn() -> void:
	# reads GameState.next_spawn_id (set by leavetown.gd's
	# target_spawn_id before it transitioned here) and moves the player
	# to whichever FieldPortal marker matches that id. if nothing was
	# set, the player just stays wherever spawn_player_from_selection()
	# left them (added into yworldsort/player with no explicit position,
	# so effectively (0,0) local to that container).
	if GameState.next_spawn_id == "":
		return

	var target_id: String = GameState.next_spawn_id
	GameState.next_spawn_id = ""  # consume it — don't let it leak into a later, unrelated scene load

	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		print("field.gd: no player found in group 'player' — can't position at spawn")
		push_warning("field.gd: no player found in group 'player' — can't position at spawn")
		return

	for portal in get_tree().get_nodes_in_group("fieldportals"):
		if "portal_id" in portal and portal.portal_id == target_id:
			player.global_position = portal.global_position
			print("field.gd: positioned player at spawn '%s' -> %s" % [target_id, portal.global_position])
			return

	print("field.gd: no FieldPortal found matching id '%s'" % target_id)
	push_warning("field.gd: no FieldPortal found matching id '%s'" % target_id)
