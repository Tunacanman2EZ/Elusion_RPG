extends Node2D

# Current player node loaded in the scene (set on spawn)
var current_player: Node = null
var mana := 0
var max_mana := 100
## Reference to the ActiveCharacterUI controller for showing
## inventory/stats dynamically (assigned in-scene)
@onready var active_char_ui: Control = $MenuScreen/ActiveCharUI

# --- Player Management ---
func spawn_player_from_selection():
	var slot_idx = CharacterData.active_character_index
	var scenes = [
		preload("res://scene/characters/warrior.tscn"),
		preload("res://scene/characters/mage.tscn"),
		preload("res://scene/characters/tank.tscn"),
		preload("res://scene/characters/healer.tscn"),
	]
	if slot_idx < 0 or slot_idx >= scenes.size():
		push_error("No valid character slot selected! Index: %d" % slot_idx)
		return
	if current_player and current_player.is_inside_tree():
		current_player.queue_free()  # Remove previous player if still present
	var scene = scenes[slot_idx]
	var player = scene.instantiate()
	if not player:
		push_error("Player scene failed to instance!")
		return
	var spawn = get_node_or_null("PlayerSpawn")
	if not spawn:
		push_error("PlayerSpawn node not found!")
		return
	player.global_position = spawn.global_position
	add_child(player)
	current_player = player

	# Setup UI controller to reference new player
	if active_char_ui:
		# Add a safety check to prevent recursion
		if active_char_ui.has_method("set_active_character"):
			active_char_ui.set_active_character(current_player)

func get_player():
	var players = get_tree().get_nodes_in_group("player")
	return players[0] if players.size() > 0 else null

# --- Navigation Button Handlers ---
func _on_InventoryButton_pressed():
	if active_char_ui and active_char_ui.has_method("toggle_inventory"):
		active_char_ui.toggle_inventory()

func _on_StatsButton_pressed():
	if active_char_ui and active_char_ui.has_method("toggle_stats"):
		active_char_ui.toggle_stats()

func _on_ShopButton_pressed():
	pass

func _on_MapButton_pressed():
	pass

func _on_OptionsButton_pressed():
	pass

func _on_DiscordButton_pressed():
	OS.shell_open("https://discord.gg/4PEhh4Uu")

func _on_LogoutButton_pressed():
	if current_player and current_player.is_inside_tree():
		current_player.queue_free()
		current_player = null
	get_tree().quit()
