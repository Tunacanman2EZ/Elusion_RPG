"""
Character HUD Controller (Godot 4.5)

WHY: Shared by all character classes. Displays HP, Stamina, and action buttons; manages the opening/closing of inventory and stats panels.
HOW: Connects UI elements, responds to updates from player node, spawns/cleans inventory and stats screens, and feeds data into bars/labels.
TODO:
 - Add support for buffs/debuffs and extra vitals (e.g. Mana).
 - Animate vital changes for user feedback.
 - Add tooltips to action buttons.
 - Make panels draggable or resizable.
"""
extends Control
class_name CharacterHUD

# --- PANEL SCENE REFERENCES ---
var inventory_scene: PackedScene = preload("res://scenes/ui/inventory/Inventory.tscn")
var stats_scene: PackedScene = preload("res://scenes/ui/StatsScreen.tscn")

# --- CURRENT PLAYER AND PANEL REFERENCES ---
var player: Node = null  # The player this HUD displays
var current_panel: Control = null  # Panel currently shown above the HUD (inventory or stats)

# --- VITAL BARS AND LABELS ---
@onready var hp_bar: ProgressBar = $HUDPanel/MarginContainer/VBoxContainer/VitalBars/HPContainer/HPBar
@onready var hp_label: Label = $HUDPanel/MarginContainer/VBoxContainer/VitalBars/HPContainer/HPLabel
@onready var stamina_bar: ProgressBar = $HUDPanel/MarginContainer/VBoxContainer/VitalBars/StaminaContainer/StaminaBar
@onready var stamina_label: Label = $HUDPanel/MarginContainer/VBoxContainer/VitalBars/StaminaContainer/StaminaLabel

# --- ACTION BUTTONS (Attack, Interact, etc.) ---
@onready var panel_container: VBoxContainer = $HUDPanel2/VBoxContainer
@onready var attack_button: Button = $HUDPanel2/VBoxContainer/ActionButtons/ButtonsVBox/AttackButton
@onready var interact_button: Button = $HUDPanel2/VBoxContainer/ActionButtons/ButtonsVBox/InteractButton

"""
Sets up button signal connections at startup.
WHY: Ensures HUD is interactive; links button UI to script logic.
"""
func _ready() -> void:
	if attack_button:
		attack_button.pressed.connect(_on_attack_pressed)
	if interact_button:
		interact_button.pressed.connect(_on_interact_pressed)

"""
Updates display every frame if the player exists.
WHY: Ensures HUD bars/labels are always in sync with player data; 
    allows for flashing/animation support later.
"""
func _process(_delta: float) -> void:
	if player:
		update_display()

"""
Sets up the HUD to display data for a given player.
WHY: Needed for scene changes, respawn, or multiplayer expansions.
TODO: Support late player assignment or swaps.
"""
func setup_for_player(p: Node) -> void:
	player = p
	update_display()
	# Pass player to panel if currently open (required for stat/inventory access)
	if current_panel and current_panel.has_method("setup_for_player"):
		current_panel.setup_for_player(player)

"""
Updates HP and stamina visual bars/labels.
WHY: Key gameplay feedback—shows damage/rest/sprint stats.
HOW: Ignores update if player is missing; sets all UI to match current values.
TODO: Add low-health color warning or shake.
"""
func update_display() -> void:
	if player == null:
		return

	# HP
	var hp = player.get("hp")
	var max_hp = player.get("max_hp")
	if hp != null and max_hp != null:
		if hp_bar:
			hp_bar.max_value = max_hp
			hp_bar.value = hp
		if hp_label:
			hp_label.text = "HP: %d/%d" % [hp, max_hp]

	# Stamina
	var stamina = player.get("stamina") if player.get("stamina") != null else 100
	var max_stamina = player.get("max_stamina") if player.get("max_stamina") != null else 100
	if stamina_bar:
		stamina_bar.max_value = max_stamina
		stamina_bar.value = stamina
	if stamina_label:
		stamina_label.text = "Stamina: %d/%d" % [stamina, max_stamina]

#region Panel Management

"""
Instantiates and shows the inventory panel over the HUD.
WHY: Lets player check/manage items at any time.
HOW: Replaces any previous panel; wires “close_requested” for clean removal.
TODO: Animate inventory panel in/out.
"""
func show_inventory() -> void:
	hide_panel()
	current_panel = inventory_scene.instantiate()
	panel_container.add_child(current_panel)
	panel_container.move_child(current_panel, 0)  # Place on top/front
	if current_panel.has_method("setup_for_player") and player:
		current_panel.setup_for_player(player)
	if current_panel.has_signal("close_requested"):
		current_panel.close_requested.connect(hide_panel)

"""
Same as show_inventory, but for the stats panel.
WHY: Lets player view detailed stats mid-game.
"""
func show_stats() -> void:
	hide_panel()
	current_panel = stats_scene.instantiate()
	panel_container.add_child(current_panel)
	panel_container.move_child(current_panel, 0)
	if current_panel.has_method("setup_for_player") and player:
		current_panel.setup_for_player(player)
	if current_panel.has_signal("close_requested"):
		current_panel.close_requested.connect(hide_panel)

"""
Hides/removes the current open panel (if any).
WHY: Makes sure only one panel is shown at a time, and always allows for clean-up.
"""
func hide_panel() -> void:
	if current_panel:
		current_panel.queue_free()
		current_panel = null

"""
Toggles inventory panel. Opens if closed, closes if open.
WHY: Quick access from HUD button; avoids duplicate panels.
"""
func toggle_inventory() -> void:
	if current_panel and current_panel is InventoryScreen:
		hide_panel()
	else:
		show_inventory()

"""
Toggles stats panel like inventory.
WHY: Lets player check stats on the fly.
"""
func toggle_stats() -> void:
	if current_panel and current_panel is StatsScreen:
		hide_panel()
	else:
		show_stats()

"""
Returns true if any panel is open/visible over HUD.
WHY: Useful for input blocking/UI logic.
"""
func is_panel_open() -> bool:
	return current_panel != null

#endregion

#region Button Handlers

"""
Handles press of Attack button (HUDPanel2).
WHY: Central place to trigger player’s main attack.
TODO: Support “cooldown” indicator, button feedback.
"""
func _on_attack_pressed() -> void:
	if player and player.has_method("attack_action"):
		player.attack_action()

"""
Handles press of Interact button (HUDPanel2).
WHY: General use (open doors, talk, pick up items, etc).
TODO: Add context hints or ghosting when inapplicable.
"""
func _on_interact_pressed() -> void:
	if player and player.has_method("interact"):
		player.interact()
	else:
		print("Interact pressed")

#endregion
