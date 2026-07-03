# main game scene controller — spawns the active player character based on
# the slot selected at character select, then wires its signals into
# GameState for the rest of the game to react to.
#
# the player is fully driven by signals: combat, XP, gold, movement all
# emit through GameState so any system (achievements, multiplayer sync,
# analytics) can subscribe without coupling to the player directly.
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
	# character select, parents it to this scene at the playerspawn
	# marker, then wires up all signals.
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

	# position then attach. attach last so player._ready() runs with the
	# correct global_position when CharacterData.load_character_state(self)
	# pulls saved stats onto the instance.
	player.global_position = spawn.global_position
	add_child(player)
	current_player = player

	_wire_player_signals()
	_attach_player_to_hud()


# =============================================================================
# SIGNAL WIRING
# =============================================================================

func _wire_player_signals() -> void:
	# bridges the player's per-instance signals into GameState's global
	# signals so any system (HUD, analytics, future multiplayer sync) can
	# subscribe to game-wide events without coupling to the player node.
	if current_player == null:
		return

	# combat damage taken
	current_player.took_damage.connect(func(amount, type):
		GameState.damage_dealt.emit(
			0,
			current_player.get_instance_id(),
			amount,
			type,
		))

	# player death
	current_player.died.connect(func():
		GameState.player_died.emit(current_player.get_instance_id()))

	# XP gained from any source (kills, quests, etc.)
	current_player.xp_gained_signal.connect(func(amount):
		GameState.xp_gained.emit(current_player.get_instance_id(), amount))

	# gold pickup or spend
	current_player.gold_changed_signal.connect(func(amount):
		GameState.gold_changed.emit(current_player.get_instance_id(), amount))

	# position updates for movement tracking
	current_player.moved.connect(func(pos, dir):
		GameState.player_moved.emit(
			current_player.get_instance_id(),
			pos,
			dir,
		))


func _attach_player_to_hud() -> void:
	# hands the player reference to the HUD so stat bars can poll for
	# changes AND so the inventory panel can populate from inventory_data
	# on first open.
	if active_char_ui and active_char_ui.has_method("set_active_character"):
		active_char_ui.set_active_character(current_player)
