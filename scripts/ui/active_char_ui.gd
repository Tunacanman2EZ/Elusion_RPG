## ActiveCharUI - Master controller for all character-related UI.[br]
## Manages the HUD, Inventory, and Stats screens for the active character.[br]
## Call set_active_character() when the player spawns or changes.
extends Control
class_name ActiveCharUI

## The currently active character
var active_character: Node = null

## UI component references
@onready var character_hud: CharacterHUD = $CharacterHUD/HUDControl
@onready var inventory_ui: CanvasLayer = $InventoryUI
@onready var inventory_screen: InventoryScreen = $InventoryUI/InventoryScreen
@onready var stats_ui: CanvasLayer = $StatsUI
@onready var stats_screen: StatsScreen = $StatsUI/StatsScreen


func _ready() -> void:
	# Hide panels initially
	if inventory_ui:
		inventory_ui.visible = false
	if stats_ui:
		stats_ui.visible = false
	
	# Connect close signals from panels
	if inventory_screen:
		inventory_screen.close_requested.connect(_on_inventory_close)
	if stats_screen:
		stats_screen.close_requested.connect(_on_stats_close)


## Sets the active character and updates all UI components.[br]
## Call this when the player spawns or when switching characters.
func set_active_character(character: Node) -> void:
	active_character = character
	
	if character_hud:
		character_hud.setup_for_player(character)
	
	# Pre-setup screens so they're ready when opened
	if inventory_screen:
		inventory_screen.setup_for_player(character)
	if stats_screen:
		stats_screen.setup_for_player(character)


## Returns the currently active character
func get_active_character() -> Node:
	return active_character


#region Panel Visibility

## Shows the inventory panel
func show_inventory() -> void:
	_hide_all_panels()
	if inventory_ui:
		inventory_ui.visible = true
		if inventory_screen and active_character:
			inventory_screen.setup_for_player(active_character)


## Shows the stats panel
func show_stats() -> void:
	_hide_all_panels()
	if stats_ui:
		stats_ui.visible = true
		if stats_screen and active_character:
			stats_screen.setup_for_player(active_character)


## Hides all panels
func _hide_all_panels() -> void:
	if inventory_ui:
		inventory_ui.visible = false
	if stats_ui:
		stats_ui.visible = false


## Returns true if any panel is currently visible
func is_panel_open() -> bool:
	return (inventory_ui and inventory_ui.visible) or (stats_ui and stats_ui.visible)


## Toggles the inventory panel
func toggle_inventory() -> void:
	if inventory_ui and inventory_ui.visible:
		inventory_ui.visible = false
	else:
		show_inventory()


## Toggles the stats panel
func toggle_stats() -> void:
	if stats_ui and stats_ui.visible:
		stats_ui.visible = false
	else:
		show_stats()

#endregion


#region Close Handlers

func _on_inventory_close() -> void:
	if inventory_ui:
		inventory_ui.visible = false


func _on_stats_close() -> void:
	if stats_ui:
		stats_ui.visible = false

#endregion

