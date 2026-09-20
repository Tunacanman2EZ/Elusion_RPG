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
# NOTE: the Y-sort container is "ysortworld". This file used to look up
# "yworldsort" and carried a note blaming elusion.gd for the mismatch. That
# had it backwards — field.tscn and elusion.tscn both say ysortworld, and
# elusion.gd was right all along. (boss.tscn genuinely does use yworldsort,
# and boss.gd matches it; that pair is consistent and correct.)
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
		"Welcome to Elusion, explorers and developers. I am happy to show you my progress. I am so excited that you are here with me; it means a lot. Love you all.",

		"A solo-developed game, built as my college portfolio for Maestro, the world's first Native AI University. I started with zero coding experience, and I had never used Godot or any other engine. From the creator of Elusion Studios, I humbly present my dedication to Elusion. Graphics inspired by Chrono Trigger; gameplay inspired by Darza's Dominion, Tibia, and Mirage Realms.",

		"I am using Claude as:\n"
		+ "an architect's assistant,\n"
		+ "a code reviewer,\n"
		+ "a design rubber duck,\n"
		+ "and a test-thinking partner.\n"
		+ "And I am backing it all up with:\n"
		+ "a Git history that explains my decisions,\n"
		+ "diffs I actually read,\n"
		+ "and tests that prove things work.",

		"Main Artist: Ahvassa — https://ahvassa.itch.io/\n"
		+ "Icon Asset Pack: Caio — https://www.patreon.com/clockworkravenstudios\n"
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
	# "ysortworld", not "yworldsort". field.tscn names this container
	# ysortworld in all 31 places it appears; this lookup had the middle two
	# syllables swapped, so get_node_or_null() quietly returned null and the
	# player was added to the scene ROOT instead — outside the Y-sort space.
	# That is what drew the player in front of every tree, wall and enemy in
	# the field no matter where they were standing.
	#
	# get_node_or_null() is why this was never reported as an error: the
	# fallback below is a real working path, so the typo degraded silently
	# into wrong-looking depth instead of anything that would get chased.
	var y_world: Node = get_node_or_null("ysortworld")
	if y_world != null:
		var player_container: Node = y_world.get_node_or_null("player")
		spawn_parent = player_container if player_container != null else y_world

	spawn_parent.add_child(player)
	current_player = player

	if OS.is_debug_build():
		# names the container the player ACTUALLY landed in. Given the comment
		# above, this scene has already paid for that typo once — this line is
		# what makes the same mistake visible on the launch it happens, rather
		# than after the depth-sorting looks wrong for a while.
		var fallback_note: String = ""
		if spawn_parent == self:
			fallback_note = "  (FALLBACK — no ysortworld, Y-sorting is OFF)"
		print("[WORLD] field — %s into %s%s" % [
			player.name,
			spawn_parent.name,
			fallback_note,
		])

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
# SPAWN POSITIONING
# =============================================================================

func _position_player_at_spawn() -> void:
	# reads GameState.next_spawn_id (set by leavetown.gd's
	# target_spawn_id before it transitioned here) and moves the player
	# to whichever FieldPortal marker matches that id. if nothing was
	# set, the player just stays wherever spawn_player_from_selection()
	# left them (added into ysortworld/player with no explicit position,
	# so effectively (0,0) local to that container).
	if GameState.next_spawn_id == "":
		return

	var target_id: String = GameState.next_spawn_id
	GameState.next_spawn_id = ""  # consume it — don't let it leak into a later, unrelated scene load

	# the print/push_warning pairs here used to say the same sentence twice,
	# once to stdout and once to the debugger. Only the warning is kept: a
	# spawn that cannot be resolved is a defect, and a defect should be loud
	# in one place rather than half-loud in two.
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("field.gd: no player in group 'player' — can't position at spawn '%s'" % target_id)
		return

	for portal in get_tree().get_nodes_in_group("fieldportals"):
		if "portal_id" in portal and portal.portal_id == target_id:
			player.global_position = portal.global_position
			# THE WHOLE SCREEN SMEARS WITHOUT THIS, not just the player.
			#
			# spawn_player_from_selection() adds the player with no explicit
			# position — see the comment at the top of this function, which
			# says so — so they enter the tree at (0, 0) and this line is what
			# puts them at the arrival portal. That is a move AFTER add_child()
			# reset interpolation, which is the streak teleporter.gd already
			# handles for in-world teleports. Arriving from another scene took
			# a different path here and never got the same call.
			#
			# It reads as the entire view sliding into place because the camera
			# is parented to the player and inherits the blend.
			player.reset_physics_interpolation()
			if OS.is_debug_build():
				print("[WORLD] field — spawn '%s' -> %s" % [target_id, portal.global_position])
			return

	push_warning("field.gd: no FieldPortal matching id '%s' — player left at default position" % target_id)
