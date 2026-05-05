# main game scene controller — spawns the player and connects all core systems
extends Node2D

# reference to the currently active player node
var current_player: Node = null

# reference to the HUD canvas layer for updating bars and UI
@onready var active_char_ui = $hudcontrol

func _ready():
	# confirm elusion scene is loading correctly
	print("ELUSION READY CALLED")

	# spawn the correct character based on the selected slot
	spawn_player_from_selection()

func spawn_player_from_selection():
	# get which slot index was selected on the character select screen
	var slot_idx = CharacterData.active_character_index

	# preload all 4 character scenes — index matches slot index
	var scenes = [
		preload("res://scene/characters/warrior.tscn"),  # slot 0
		preload("res://scene/characters/mage.tscn"),     # slot 1
		preload("res://scene/characters/tank.tscn"),     # slot 2
		preload("res://scene/characters/healer.tscn"),   # slot 3
	]

	# validate the slot index is within range
	if slot_idx < 0 or slot_idx >= scenes.size():
		push_error("no valid character slot selected! index: %d" % slot_idx)
		return

	# if a player already exists in the scene remove them first
	if current_player and current_player.is_inside_tree():
		current_player.queue_free()

	# create an instance of the selected character scene
	var scene = scenes[slot_idx]
	var player = scene.instantiate()

	# stop if the scene failed to instantiate
	if not player:
		push_error("player scene failed to instance!")
		return

	# find the spawn point marker in the scene
	var spawn = get_node_or_null("playerspawn")

	# stop if no spawn point exists
	if not spawn:
		push_error("playerspawn node not found!")
		return

	# place the player at the spawn point position
	player.global_position = spawn.global_position

	# add the player to the scene tree so it becomes active
	add_child(player)

	# store reference to the active player
	current_player = player

	# load saved stats into the player from characterdata
	CharacterData.load_character_state(current_player)

	# connect player took_damage signal to GameState for multiplayer ready architecture
	current_player.took_damage.connect(func(amount, type):
		GameState.damage_dealt.emit(
			0,
			current_player.get_instance_id(),
			amount,
			type
		))

	# connect player died signal to GameState
	current_player.died.connect(func():
		GameState.player_died.emit(current_player.get_instance_id()))

	# connect player xp gained signal to GameState
	current_player.xp_gained_signal.connect(func(amount):
		GameState.xp_gained.emit(current_player.get_instance_id(), amount))

	# connect player gold changed signal to GameState
	current_player.gold_changed_signal.connect(func(amount):
		GameState.gold_changed.emit(current_player.get_instance_id(), amount))

	# connect player moved signal to GameState
	current_player.moved.connect(func(pos, dir):
		GameState.player_moved.emit(
			current_player.get_instance_id(),
			pos,
			dir
		))

	# safety check — confirm player was assigned correctly
	if current_player == null:
		return

	# pass the player reference to the HUD so bars can update
	if active_char_ui and active_char_ui.has_method("set_active_character"):
		active_char_ui.set_active_character(current_player)

# --- nav button handlers — connected via elusion.tscn signals ---

func _on_InventoryButton_pressed():
	# toggle the inventory panel open or closed
	if active_char_ui and active_char_ui.has_method("toggle_inventory"):
		active_char_ui.toggle_inventory()

func _on_StatsButton_pressed():
	# toggle the stats panel open or closed
	if active_char_ui and active_char_ui.has_method("toggle_stats"):
		active_char_ui.toggle_stats()

func _on_ShopButton_pressed():
	# placeholder — shop not yet implemented
	pass

func _on_MapButton_pressed():
	# placeholder — map not yet implemented
	pass

func _on_OptionsButton_pressed():
	# placeholder — options not yet implemented
	pass

func _on_DiscordButton_pressed():
	# open elusion studios discord in the browser
	OS.shell_open("https://discord.gg/4PEhh4Uu")

func _on_LogoutButton_pressed():
	# save current player state before logging out
	if current_player and current_player.is_inside_tree():
		CharacterData.save_character_state(current_player)
		# remove player from scene
		current_player.queue_free()
		current_player = null

	# return to character select screen
	get_tree().change_scene_to_file("res://scene/menu/characterselect.tscn")
