extends Control
class_name ActiveCharUI

# --- STATE ---
var active_character: Node = null   # The currently active player character node

# --- UI COMPONENT REFERENCE ---
@onready var character_hud: CharacterHUD = $CharacterHUD/HUDControl

func _ready() -> void:
	pass

# -- Character assignment and HUD setup --
func set_active_character(character: Node) -> void:
	active_character = character
	if character_hud:
		character_hud.setup_for_player(character)

func get_active_character() -> Node:
	return active_character

# -- Panel Visibility/Delegation to CharacterHUD --
func show_inventory() -> void:
	if character_hud:
		character_hud.show_inventory()

func show_stats() -> void:
	if character_hud:
		character_hud.show_stats()

func hide_panel() -> void:
	if character_hud:
		character_hud.hide_panel()

func is_panel_open() -> bool:
	if character_hud:
		return character_hud.is_panel_open()
	return false

func toggle_inventory() -> void:
	if character_hud:
		character_hud.toggle_inventory()

func toggle_stats() -> void:
	if character_hud:
		character_hud.toggle_stats()
