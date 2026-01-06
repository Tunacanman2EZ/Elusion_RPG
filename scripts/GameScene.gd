extends Node2D

"""
Main game scene setup:
- Selects and spawns the correct player character at the spawn point.
- Adds MenuScreen UI overlay as child of GameScene (never child of player!).
"""

var warrior_scene: PackedScene = preload("res://scenes/characters/Warrior.tscn")
var mage_scene: PackedScene = preload("res://scenes/characters/Mage.tscn")
var tank_scene: PackedScene = preload("res://scenes/characters/Tank.tscn")
var healer_scene: PackedScene = preload("res://scenes/characters/Healer.tscn")
var menu_screen_scene: PackedScene = preload("res://scenes/ui/menus/menu_screen.tscn")


func _ready():
	print("GameScene _ready() called!")

	# Get active character slot index
	var slot = CharacterData.active_character_index

	# Safety: Check that the selected slot is valid and contains a character
	if CharacterData.character_slots.size() <= slot or CharacterData.character_slots[slot] == null:
		print("No valid character selected!")
		return

	# Get info for chosen character
	var char_info = CharacterData.character_slots[slot]

	# Find the spawn point node (must be named "PlayerSpawn" in the scene tree)
	var spawn_point := $PlayerSpawn if has_node("PlayerSpawn") else null
	if not spawn_point:
		print("Spawn point node not found: PlayerSpawn")
		return

	# Pick correct character scene
	var character_scene: PackedScene = null
	match char_info["class"]:
		"Warrior":
			if ResourceLoader.exists("res://scenes/characters/Warrior.tscn"):
				print("Warrior scene found, setting character scene to Warrior")
				character_scene = warrior_scene
		"Mage":
			if ResourceLoader.exists("res://scenes/characters/Warrior.tscn"):
				print("Mage scene found, setting character scene to Mage")
				character_scene = mage_scene
		"Tank":
			if ResourceLoader.exists("res://scenes/characters/Warrior.tscn"):
				print("Tank scene found, setting character scene to Tank")
				character_scene = tank_scene
		"Healer":
			if ResourceLoader.exists("res://scenes/characters/Warrior.tscn"):
				print("Healer scene found, setting character scene to Healer")
				character_scene = healer_scene
		_:
			print("Unknown class: ", char_info["class"])
			return

	# Spawn the character if scene and spawn point exist
	if character_scene and spawn_point:
		var character = character_scene.instantiate()
		character.global_position = spawn_point.global_position
		print("Spawned character of class: ", char_info["class"])
		print("Spawn position: ", spawn_point.global_position)
		add_child(character)  # Add as sibling

	else:
		if not character_scene:
			print("No character scene found for: ", char_info["class"])
		return # Stop further initialization if failed!

	# Add MenuScreen UI as child of GameScene (never as child of character/player!)
	var menu_screen = menu_screen_scene.instantiate()
	add_child(menu_screen)  # Add to GameScene so it stays on screen

	# Optional: Connect Discord button signal, adapt the path as needed!
	# if menu_screen.has_node("NavButton/DiscordButton"):
	#	menu_screen.get_node("NavButton/DiscordButton").pressed.connect(_on_DiscordButton_pressed)

func _on_DiscordButton_pressed():
	OS.shell_open("https://discord.gg/ArqdVsrM")
