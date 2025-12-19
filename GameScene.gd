extends Node2D  # Root node must be Node2D in your scene

"""
Main game scene setup:
- Selects and spawns the correct player character at the spawn point.
- Adds Menu_Screen UI overlay.
- (Optional) Sets up Discord button handler.
"""

func _ready():
	"""Initializes the main game scene."""
	print("GameScene _ready() called!")

	# Get active character slot index
	var slot = CharacterData.active_character_index

	# Check that the selected slot is valid and contains a character
	if CharacterData.character_slots.size() <= slot or CharacterData.character_slots[slot] == null:
		print("No valid character selected!")
		return

	# Get info for chosen character
	var char_info = CharacterData.character_slots[slot]

	# Try to find the spawn point node (must be named "PlayerSpawn" in the scene)
	var spawn_point = null
	if has_node("PlayerSpawn"):
		spawn_point = get_node("PlayerSpawn")
	else:
		print("Spawn point node not found: PlayerSpawn")

	# Will hold scene reference for the chosen character's class
	var character_scene: PackedScene = null

	# Choose which scene to load (based on class)
	match char_info["class"]:
		"Warrior":
			character_scene = preload("res://scenes/Warrior.tscn")
		"Mage":
			character_scene = preload("res://scenes/Mage.tscn")
		"Tank":
			character_scene = preload("res://scenes/Tank.tscn")
		"Healer":
			character_scene = preload("res://scenes/Healer.tscn")

	# Spawn the character if everything is set up
	if character_scene and spawn_point:
		var character = character_scene.instantiate()
		character.global_position = spawn_point.global_position  # Set character position
		add_child(character)
		print("Spawned character of class: ", char_info["class"])
		print("Spawn position: ", spawn_point.global_position)
		print("Children now: ", get_child_count())
	else:
		if not character_scene:
			print("No character scene found for: ", char_info["class"])

	# --- Add Menu_Screen UI ---
	# Loads and adds the universal menu overlay (inventory, stats, options, map, Discord link, etc.)
	var menu_screen_scene = preload("res://scenes/menu_screen.tscn")
	var menu_screen = menu_screen_scene.instantiate()

	# --- (Optional) Discord button logic ---
	# If your Menu_Screen includes a button named "DiscordButton", connect its pressed() signal.
	if menu_screen.has_node("DiscordButton"):
		menu_screen.get_node("DiscordButton").pressed.connect(_on_DiscordButton_pressed)
		# Make sure your Menu_Screen has a Button named "DiscordButton"

func _on_DiscordButton_pressed():
	"""Opens the Discord invite link in the system browser."""
	OS.shell_open("https://discord.com/your_invite_link")
