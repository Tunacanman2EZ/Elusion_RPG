# elusion.gd main game scene controller — spawns the active player character based on
# the slot selected at character select, then wires its signals into
# GameState for the rest of the game to react to.
#
# the player is fully driven by signals: combat, XP, gold, movement all
# emit through GameState so any system (achievements, multiplayer sync,
# analytics) can subscribe without coupling to the player directly.
#
# y-sort: the player spawns into ysortworld/player so it depth-sorts against
# pre-placed enemies. everything upright (player, enemies, projectiles, pets,
# props) lives under the y-sorted ysortworld container.
extends Node2D


# =============================================================================
# STATE
# =============================================================================

# reference to the currently active player node — set on spawn, freed on logout
var current_player: Node = null

# HUD canvas layer that displays bars and owns the lazy-instantiated panels.
# resolved on _ready via the @onready binding.
@onready var active_char_ui = $hudcontrol


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	print("ELUSION READY CALLED")
	spawn_player_from_selection()


# =============================================================================
# PLAYER SPAWN
# =============================================================================

func spawn_player_from_selection() -> void:
	# instantiates the character scene matching the slot selected at
	# character select, parents it into the y-sorted player container so it
	# depth-sorts correctly against pre-placed enemies, then wires signals.
	var slot_idx: int = CharacterData.active_character_index

	# preloaded character scenes — array index matches slot index, so
	# warrior is always slot 0, mage always slot 1, etc.
	var scenes := [
		preload("res://scene/characters/warrior.tscn"),  # slot 0
		preload("res://scene/characters/mage.tscn"),     # slot 1
		preload("res://scene/characters/tank.tscn"),     # slot 2
		preload("res://scene/characters/healer.tscn"),   # slot 3
	]

	if slot_idx < 0 or slot_idx >= scenes.size():
		push_error("no valid character slot selected! index: %d" % slot_idx)
		return

	# clean up any existing player (e.g., on re-spawn after a death revive)
	if current_player and current_player.is_inside_tree():
		current_player.queue_free()

	# instantiate the chosen character scene
	var player: Node = scenes[slot_idx].instantiate()
	if player == null:
		push_error("player scene failed to instance!")
		return

	# locate the spawn marker placed in the editor — without it we can't
	# position the player and the spawn aborts
	var spawn: Node = get_node_or_null("playerspawn")
	if spawn == null:
		push_error("playerspawn node not found!")
		return

	# resolve the spawn container. the player MUST land inside ysortworld's
	# sort space to depth-sort against enemies. prefer ysortworld/player,
	# fall back to ysortworld, then to self (degraded but non-crashing).
	var spawn_parent: Node = self
	var ysort_world: Node = get_node_or_null("ysortworld")
	if ysort_world != null:
		var player_container: Node = ysort_world.get_node_or_null("player")
		spawn_parent = player_container if player_container != null else ysort_world

	# position then attach. attach last so player._ready() runs with the
	# correct global_position when CharacterData.load_character_state(self)
	# pulls saved stats onto the instance.
	player.global_position = spawn.global_position
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
	# hands the player reference to the HUD so stat bars can poll for
	# changes AND so the inventory panel can populate from inventory_data
	# on first open.
	if active_char_ui and active_char_ui.has_method("set_active_character"):
		active_char_ui.set_active_character(current_player)
