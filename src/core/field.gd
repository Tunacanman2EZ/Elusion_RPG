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

@onready var active_char_ui = get_node_or_null("hudcontrol")


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	spawn_player_from_selection()
	_position_player_at_spawn()
	_freeze_enemies()

	var screen := StoryScreen.new()
	add_child(screen)
	screen.finished.connect(_unfreeze_enemies)
	screen.play([
		"Welcome to Elusion explorers and developers; I am happy to show you my progress. I absolutely am so excited you are here with me, it means a lot to me; love you all",
		"A Solo Developer Game, used as my college portfolio for Maestro the worlds first Native AI University — coming from zero coding experience, and never using Godot or any engine. From the creator of Elusion Studios, I humbly present my dedication of Elusion. Graphics inspired by Chrono Trigger, gameplay inspired by Darza's Dominion, Tibia, Mirage Realms.",
		
		"I am using Claude as:\n"
		+ "architect's assistant,\n"
		+ "code reviewer,\n"
		+ "design rubber duck,\n"
		+ "and test-thinking partner.\n"
		+ "And I am backing it all with:\n"
		+ "Git history that explains my decisions,\n"
		+ "diffs I actually read,\n"
		+ "and tests that prove things work.",

		"Main Artist: Ahvassa — https://ahvassa.itch.io/\n"
		+ "Icon Asset Pack From Artist: Caio — https://www.patreon.com/clockworkravenstudios\n"
		+ "Thanks for checking out my game; I really appreciate you!",
	], true)


# =============================================================================
# ENEMY FREEZE  (NEW)
# =============================================================================
# nothing previously stopped enemies from freely chasing and converging
# on the player's fixed arrival position for the whole duration of the
# story screen — the black overlay only hides that visually, it doesn't
# pause anything underneath. by the time it faded out, enemies placed
# apart in the editor could have already bunched up around the player,
# which is very likely what caused the "spawned on top of each other"
# observation — they hadn't actually spawned that way, they'd just had
# time to converge before the player ever saw the scene. set_physics_process
# is the same built-in Node method used to freeze the player during the
# earlier (since-removed) leavetown-triggered story sequence, just
# applied to every enemy here instead.

func _freeze_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)


func _unfreeze_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			enemy.set_physics_process(true)


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
