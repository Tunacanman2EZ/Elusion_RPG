"""
Game Main Scene Controller (Godot 4.5)

WHY: Manages spawning the correct player character, 
     connects UI (ActiveCharUI), and handles main menu/nav actions.
HOW: Loads player scene based on active_character_index; 
     shows/hides UI panels.
TODO:
 - Add shop, options, and map panels.
 - Refactor scene loading logic for DLC/expansion classes.
 - Add save/load support for player/scene state.
"""
extends Node2D

# Current player node loaded in the scene (set on spawn)
var current_player: Node = null

## Reference to the ActiveCharUI controller for showing 
## inventory/stats dynamically (assigned in-scene)
@onready var active_char_ui: ActiveCharUI = $MenuScreen/ActiveCharUI

# --- Player Management ---
"""
Loads the player character chosen at selection and spawns them at the start location.

WHY: Supports multi-class gameplay and per-user character appearance.
HOW:
  - Gets index from CharacterData.
  - Loads specific scene for class.
  - Handles error cases (no slot, spawn failure, etc).
  - Links UI to new player instance.
TODO:
  - Support customization/gear loading.
  - Pool scenes for delayed instancing.
"""
func spawn_player_from_selection():
	var slot_idx = CharacterData.active_character_index
	var scenes = [
		preload("res://scenes/characters/Warrior.tscn"),
		preload("res://scenes/characters/Mage.tscn"),
		preload("res://scenes/characters/Tank.tscn"),
		preload("res://scenes/characters/Healer.tscn"),
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
		active_char_ui.set_active_character(current_player)

"""
Finds the currently active player object from the group.
WHY: Utility for scripts that need to know “who is the player.”
TODO: Support multi-player by returning an array.
"""
func get_player():
	var players = get_tree().get_nodes_in_group("player")
	return players[0] if players.size() > 0 else null

# --- Navigation Button Handlers ---
"""
Toggles the inventory UI panel for the current character.
WHY: Player can check items or equipment at any time.
TODO: Add feedback (sound, animation) on toggle.
"""
func _on_InventoryButton_pressed():
	if active_char_ui:
		active_char_ui.toggle_inventory()

"""
Toggles the detailed stats UI for current character.
WHY: UX—players can see their progression live.
TODO: Animate stats sliding in/out.
"""
func _on_StatsButton_pressed():
	if active_char_ui:
		active_char_ui.toggle_stats()

"""
Handles Shop button.
TODO: Implement shop UI!
"""
func _on_ShopButton_pressed():
	pass

"""
Handles Map button.
TODO: Implement map UI with zoom/pan or fast travel.
"""
func _on_MapButton_pressed():
	pass

"""
Handles Options/settings button.
TODO: Show in-game settings; adjust controls/audio/video, etc.
"""
func _on_OptionsButton_pressed():
	pass

"""
Opens the Discord invite link in browser.
WHY: Community support.
"""
func _on_DiscordButton_pressed():
	OS.shell_open("https://discord.gg/4PEhh4Uu")

"""
Handles Logout: cleans up player and quits to desktop.
WHY: Security/convenience for user logout flow.
TODO: Return to login screen instead of quitting directly.
"""
func _on_LogoutButton_pressed():
	if current_player and current_player.is_inside_tree():
		current_player.queue_free()
		current_player = null
	get_tree().quit()

# --- Node Ready Setup ---
"""
Runs whenever the node is entered in the scene tree.
WHY: Ensures the chosen player is spawned immediately at scene start.
TODO: Run async loading in parallel with splash/intro for faster boot.
"""
func _ready():
	spawn_player_from_selection()
