## Character HUD - displays HP, Stamina, and action buttons during gameplay.[br]
## Shared by all character classes. Manages inventory and stats panels.
extends Control
class_name CharacterHUD

## Preload panel scenes
var inventory_scene: PackedScene = preload("res://scenes/ui/inventory/Inventory.tscn")
var stats_scene: PackedScene = preload("res://scenes/ui/StatsScreen.tscn")

## Reference to the current player
var player: Node = null

## Currently displayed panel (inventory or stats)
var current_panel: Control = null

## UI element references - Vital bars
@onready var hp_bar: ProgressBar = $HUDPanel/MarginContainer/VBoxContainer/VitalBars/HPContainer/HPBar
@onready var hp_label: Label = $HUDPanel/MarginContainer/VBoxContainer/VitalBars/HPContainer/HPLabel
@onready var stamina_bar: ProgressBar = $HUDPanel/MarginContainer/VBoxContainer/VitalBars/StaminaContainer/StaminaBar
@onready var stamina_label: Label = $HUDPanel/MarginContainer/VBoxContainer/VitalBars/StaminaContainer/StaminaLabel

## UI element references - Action buttons (in HUDPanel2)
@onready var panel_container: VBoxContainer = $HUDPanel2/VBoxContainer
@onready var attack_button: Button = $HUDPanel2/VBoxContainer/ActionButtons/ButtonsVBox/AttackButton
@onready var interact_button: Button = $HUDPanel2/VBoxContainer/ActionButtons/ButtonsVBox/InteractButton


func _ready() -> void:
	# Connect action buttons
	if attack_button:
		attack_button.pressed.connect(_on_attack_pressed)
	if interact_button:
		interact_button.pressed.connect(_on_interact_pressed)


func _process(_delta: float) -> void:
	if player:
		update_display()


## Sets up the HUD for a player character
func setup_for_player(p: Node) -> void:
	player = p
	update_display()
	# Update current panel if open
	if current_panel and current_panel.has_method("setup_for_player"):
		current_panel.setup_for_player(player)


## Updates the HP and Stamina displays
func update_display() -> void:
	if player == null:
		return
	
	# Update HP
	var hp = player.get("hp")
	var max_hp = player.get("max_hp")
	if hp != null and max_hp != null:
		if hp_bar:
			hp_bar.max_value = max_hp
			hp_bar.value = hp
		if hp_label:
			hp_label.text = "HP: %d/%d" % [hp, max_hp]
	
	# Update Stamina
	var stamina = player.get("stamina") if player.get("stamina") != null else 100
	var max_stamina = player.get("max_stamina") if player.get("max_stamina") != null else 100
	if stamina_bar:
		stamina_bar.max_value = max_stamina
		stamina_bar.value = stamina
	if stamina_label:
		stamina_label.text = "Stamina: %d/%d" % [stamina, max_stamina]


#region Panel Management

## Shows the inventory panel
func show_inventory() -> void:
	hide_panel()
	current_panel = inventory_scene.instantiate()
	panel_container.add_child(current_panel)
	panel_container.move_child(current_panel, 0)  # Add above ActionButtons
	if current_panel.has_method("setup_for_player") and player:
		current_panel.setup_for_player(player)
	if current_panel.has_signal("close_requested"):
		current_panel.close_requested.connect(hide_panel)


## Shows the stats panel
func show_stats() -> void:
	hide_panel()
	current_panel = stats_scene.instantiate()
	panel_container.add_child(current_panel)
	panel_container.move_child(current_panel, 0)  # Add above ActionButtons
	if current_panel.has_method("setup_for_player") and player:
		current_panel.setup_for_player(player)
	if current_panel.has_signal("close_requested"):
		current_panel.close_requested.connect(hide_panel)


## Hides the current panel
func hide_panel() -> void:
	if current_panel:
		current_panel.queue_free()
		current_panel = null


## Toggles the inventory panel
func toggle_inventory() -> void:
	if current_panel and current_panel is InventoryScreen:
		hide_panel()
	else:
		show_inventory()


## Toggles the stats panel
func toggle_stats() -> void:
	if current_panel and current_panel is StatsScreen:
		hide_panel()
	else:
		show_stats()


## Returns true if any panel is currently open
func is_panel_open() -> bool:
	return current_panel != null

#endregion


#region Button Handlers

## Handles attack button press
func _on_attack_pressed() -> void:
	if player and player.has_method("attack_action"):
		player.attack_action()


## Handles interact button press
func _on_interact_pressed() -> void:
	if player and player.has_method("interact"):
		player.interact()
	else:
		print("Interact pressed")

#endregion
