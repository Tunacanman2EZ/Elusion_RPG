extends Control
class_name CharacterHUD

# --- PANEL SCENE REFERENCES ---
var inventory_scene: PackedScene = preload("res://scenes/ui/inventory/Inventory.tscn")
var stats_scene: PackedScene = preload("res://scenes/ui/StatsScreen.tscn")

# --- CURRENT PLAYER AND PANEL REFERENCES ---
var player: Node = null
var current_panel: Control = null

# --- VITAL BARS AND LABELS ---
@onready var hp_bar: ProgressBar = $HUDPanel/MarginContainer/VBoxContainer/VitalBars/HPContainer/HPBar
@onready var hp_label: Label = $HUDPanel/MarginContainer/VBoxContainer/VitalBars/HPContainer/HPLabel
@onready var stamina_bar: ProgressBar = $HUDPanel/MarginContainer/VBoxContainer/VitalBars/StaminaContainer/StaminaBar
@onready var stamina_label: Label = $HUDPanel/MarginContainer/VBoxContainer/VitalBars/StaminaContainer/StaminaLabel

# --- ACTION BUTTONS ---
@onready var panel_container: VBoxContainer = $HUDPanel2/VBoxContainer
@onready var attack_button: Button = $HUDPanel2/VBoxContainer/ActionButtons/ButtonsVBox/AttackButton
@onready var interact_button: Button = $HUDPanel2/VBoxContainer/ActionButtons/ButtonsVBox/InteractButton

func _ready() -> void:
	if attack_button:
		print("Attack button found, connecting button_down signal.")
		# Only connect if not already connected (avoids error if reloaded)
		if not attack_button.button_down.is_connected(_on_attack_button_button_down):
			attack_button.button_down.connect(_on_attack_button_button_down)
	else:
		print("ERROR: Attack button not found—check node path!")
	if interact_button:
		print("Interact button found, connecting signal.")
		interact_button.pressed.connect(_on_interact_pressed)
	else:
		print("ERROR: Interact button not found—check node path!")

func setup_for_player(p: Node) -> void:
	player = p
	print("HUD: setup_for_player called, player assigned:", player)
	update_display()
	if current_panel and current_panel.has_method("setup_for_player"):
		current_panel.setup_for_player(player)

func update_display() -> void:
	if player == null:
		return
	var hp = player.get("hp")
	var max_hp = player.get("max_hp")
	if hp != null and max_hp != null:
		if hp_bar:
			hp_bar.max_value = max_hp
			hp_bar.value = hp
		if hp_label:
			hp_label.text = "HP: %d/%d" % [hp, max_hp]

	var stamina = player.get("stamina") if player.get("stamina") != null else 100
	var max_stamina = player.get("max_stamina") if player.get("max_stamina") != null else 100
	if stamina_bar:
		stamina_bar.max_value = max_stamina
		stamina_bar.value = stamina
	if stamina_label:
		stamina_label.text = "Stamina: %d/%d" % [stamina, max_stamina]

# --- PANEL MANAGEMENT ---
func show_inventory() -> void:
	hide_panel()
	current_panel = inventory_scene.instantiate()
	panel_container.add_child(current_panel)
	panel_container.move_child(current_panel, 0)
	if current_panel.has_method("setup_for_player") and player:
		current_panel.setup_for_player(player)
	if current_panel.has_signal("close_requested"):
		current_panel.close_requested.connect(hide_panel)

func show_stats() -> void:
	hide_panel()
	current_panel = stats_scene.instantiate()
	panel_container.add_child(current_panel)
	panel_container.move_child(current_panel, 0)
	if current_panel.has_method("setup_for_player") and player:
		current_panel.setup_for_player(player)
	if current_panel.has_signal("close_requested"):
		current_panel.close_requested.connect(hide_panel)

func hide_panel() -> void:
	if current_panel:
		current_panel.queue_free()
		current_panel = null

func toggle_inventory() -> void:
	if current_panel and current_panel is InventoryScreen:
		hide_panel()
	else:
		show_inventory()

func toggle_stats() -> void:
	if current_panel and current_panel is StatsScreen:
		hide_panel()
	else:
		show_stats()

func is_panel_open() -> bool:
	return current_panel != null

# --- BUTTON HANDLERS ---
func _on_attack_button_button_down() -> void:
	print("Attack button (button_down) pressed!")
	if player and player.has_method("attack_action"):
		player.attack_action()

func _on_interact_pressed() -> void:
	print("Interact button pressed!")
	if player and player.has_method("interact"):
		player.interact()
