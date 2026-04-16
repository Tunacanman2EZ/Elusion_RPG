extends Control

# --- STATE ---
var active_character: Node = null

# --- UI COMPONENT REFERENCE ---
var hud_scene: PackedScene = preload("res://scene/ui/characterhud.tscn")
var hud_instance: Control = null

func _ready() -> void:
	hud_instance = hud_scene.instantiate()
	if hud_instance:
		add_child(hud_instance)
		hud_instance.position = Vector2.ZERO

# --- CHARACTER ASSIGNMENT AND HUD SETUP ---
func set_active_character(character: Node) -> void:
	active_character = character
	if hud_instance and hud_instance.has_method("setup_for_player"):
		hud_instance.setup_for_player(character)

func get_active_character() -> Node:
	return active_character

# --- PANEL VISIBILITY / DELEGATION TO CHARACTERHUD ---
func show_inventory() -> void:
	if hud_instance and hud_instance.has_method("show_inventory"):
		hud_instance.show_inventory()

func show_stats() -> void:
	if hud_instance and hud_instance.has_method("show_stats"):
		hud_instance.show_stats()

func hide_panel() -> void:
	if hud_instance and hud_instance.has_method("hide_panel"):
		hud_instance.hide_panel()

func is_panel_open() -> bool:
	if hud_instance and hud_instance.has_method("is_panel_open"):
		return hud_instance.is_panel_open()
	return false

func toggle_inventory() -> void:
	if hud_instance and hud_instance.has_method("toggle_inventory"):
		hud_instance.toggle_inventory()

func toggle_stats() -> void:
	if hud_instance and hud_instance.has_method("toggle_stats"):
		hud_instance.toggle_stats()
