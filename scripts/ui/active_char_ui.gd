"""
Active Character UI Controller (Godot 4.5)

WHY: Master controller for all UI connected to the currently active player character.
HOW: Stores and updates player reference, delegates inventory/stats/HUD to CharacterHUD child.
WHAT: Always call `set_active_character()` when player spawns or changes class.
TODO:
 - Support hot-swapping characters during gameplay (e.g. party switch).
 - Propagate buffs/debuffs or effects into the HUD dynamically.
 - Add hooks for additional UI panels (quests, skills, etc).
"""
extends Control
class_name ActiveCharUI

# --- STATE ---
## The currently active character (Player node)
var active_character: Node = null

# --- UI COMPONENT REFERENCE ---
@onready var character_hud: CharacterHUD = $CharacterHUD/HUDControl

"""
Called when node is added to scene tree.
WHY: May be used for future initialization or onboarding hints.
"""
func _ready() -> void:
	pass

"""
Sets the active character and updates all UI for new context.

WHY: Connects HUD/stat/inventory to the right player object.
WHEN TO CALL: On player spawn, respawn, or character/class swap.
"""
func set_active_character(character: Node) -> void:
	active_character = character
	if character_hud:
		character_hud.setup_for_player(character)

"""
Returns the currently active character node (for querying by other scripts).
WHY: Centralizes reference for UI/logic that need player info.
"""
func get_active_character() -> Node:
	return active_character

#region Panel Visibility (delegated to CharacterHUD)

"""
Shows the inventory panel via HUD.
WHY: Keeps top-level controller simple—delegates visual logic to CharacterHUD.
"""
func show_inventory() -> void:
	if character_hud:
		character_hud.show_inventory()

"""
Shows stats panel via HUD.
"""
func show_stats() -> void:
	if character_hud:
		character_hud.show_stats()

"""
Closes/hides any open panels in HUD.
"""
func hide_panel() -> void:
	if character_hud:
		character_hud.hide_panel()

"""
Returns true if any detail panel is currently shown.
WHY: Allows blocking input/esc if a modal UI is open.
"""
func is_panel_open() -> bool:
	if character_hud:
		return character_hud.is_panel_open()
	return false

"""
Toggles opening/closing of inventory panel.
"""
func toggle_inventory() -> void:
	if character_hud:
		character_hud.toggle_inventory()

"""
Toggles opening/closing of stats panel.
"""
func toggle_stats() -> void:
	if character_hud:
		character_hud.toggle_stats()

#endregion
