## ActiveCharUI - Master controller for all character-related UI.[br]
## Manages the HUD for the active character.[br]
## Call set_active_character() when the player spawns or changes.
extends Control
class_name ActiveCharUI

## The currently active character
var active_character: Node = null

## UI component references
@onready var character_hud: CharacterHUD = $CharacterHUD/HUDControl


func _ready() -> void:
	pass


## Sets the active character and updates all UI components.[br]
## Call this when the player spawns or when switching characters.
func set_active_character(character: Node) -> void:
	active_character = character
	
	if character_hud:
		character_hud.setup_for_player(character)


## Returns the currently active character
func get_active_character() -> Node:
	return active_character


#region Panel Visibility (delegated to CharacterHUD)

## Shows the inventory panel
func show_inventory() -> void:
	if character_hud:
		character_hud.show_inventory()


## Shows the stats panel
func show_stats() -> void:
	if character_hud:
		character_hud.show_stats()


## Hides all panels
func hide_panel() -> void:
	if character_hud:
		character_hud.hide_panel()


## Returns true if any panel is currently visible
func is_panel_open() -> bool:
	if character_hud:
		return character_hud.is_panel_open()
	return false


## Toggles the inventory panel
func toggle_inventory() -> void:
	if character_hud:
		character_hud.toggle_inventory()


## Toggles the stats panel
func toggle_stats() -> void:
	if character_hud:
		character_hud.toggle_stats()

#endregion
