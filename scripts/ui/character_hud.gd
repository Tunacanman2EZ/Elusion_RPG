## Character HUD - displays HP, Stamina, and action buttons during gameplay.[br]
## Shared by all character classes.
extends Control
class_name CharacterHUD

## Reference to the current player
var player: Node = null

## UI element references
@onready var hp_bar: ProgressBar = $HUDPanel/MarginContainer/VBoxContainer/VitalBars/HPContainer/HPBar
@onready var hp_label: Label = $HUDPanel/MarginContainer/VBoxContainer/VitalBars/HPContainer/HPLabel
@onready var stamina_bar: ProgressBar = $HUDPanel/MarginContainer/VBoxContainer/VitalBars/StaminaContainer/StaminaBar
@onready var stamina_label: Label = $HUDPanel/MarginContainer/VBoxContainer/VitalBars/StaminaContainer/StaminaLabel
@onready var attack_button: Button = $HUDPanel/MarginContainer/VBoxContainer/ActionButtons/AttackButton
@onready var interact_button: Button = $HUDPanel/MarginContainer/VBoxContainer/ActionButtons/InteractButton


func _ready() -> void:
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

