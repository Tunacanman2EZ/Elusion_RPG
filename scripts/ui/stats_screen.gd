## Stats Screen - displays detailed character statistics.[br]
## Supports dragging and remembers position between opens.
extends Control
class_name StatsScreen

## Emitted when the close button is pressed
signal close_requested()

## Reference to the main panel (for dragging)
@onready var main_panel: PanelContainer = $MainPanel
## Reference to the header panel (drag handle)
@onready var header_panel: PanelContainer = $MainPanel/MarginContainer/VBoxContainer/HeaderPanel
## Reference to close button
@onready var close_button: Button = $MainPanel/MarginContainer/VBoxContainer/HeaderPanel/HBoxContainer/CloseButton

## Stat labels using unique names (%)
@onready var level_label: Label = %LevelValue
@onready var xp_label: Label = %XPValue
@onready var xp_bar: ProgressBar = %XPBar
@onready var hp_label: Label = %HPValue
@onready var hp_bar: ProgressBar = %HPBar
@onready var stamina_label: Label = %StaminaValue
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var mana_label: Label = %ManaValue
@onready var mana_bar: ProgressBar = %ManaBar
@onready var attack_label: Label = %AttackValue
@onready var defense_label: Label = %DefenseValue
@onready var agility_label: Label = %AgilityValue
@onready var magic_label: Label = %MagicValue
@onready var fishing_label: Label = %FishingValue
@onready var cooking_label: Label = %CookingValue

## Currently active player reference
var current_player: Node = null

## Dragging state
var _is_dragging := false
var _drag_offset := Vector2.ZERO

## Static position memory (persists between opens)
static var _last_position: Vector2 = Vector2(-1, -1)
static var _has_saved_position := false


func _ready() -> void:
	# Connect close button
	if close_button:
		close_button.pressed.connect(_on_close_button_pressed)
	
	# Connect header for dragging
	if header_panel:
		header_panel.gui_input.connect(_on_header_gui_input)
	
	# Restore last position if saved
	if _has_saved_position and main_panel:
		main_panel.position = _last_position


func _process(_delta: float) -> void:
	# Handle dragging
	if _is_dragging and main_panel:
		main_panel.global_position = get_global_mouse_position() - _drag_offset
		_save_position()


#region Dragging and Close

## Handles input on the header panel for dragging
func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_dragging = true
				_drag_offset = get_global_mouse_position() - main_panel.global_position
			else:
				_is_dragging = false
				_save_position()


## Saves the current panel position
func _save_position() -> void:
	if main_panel:
		_last_position = main_panel.position
		_has_saved_position = true


## Handles close button press
func _on_close_button_pressed() -> void:
	close_requested.emit()

#endregion


#region Player Setup

## Sets up the stats screen for a player
func setup_for_player(player: Node) -> void:
	current_player = player
	update_display()


## Updates all stat displays
func update_display() -> void:
	if current_player == null:
		return
	
	# Level
	var level = current_player.get("level")
	if level != null and level_label:
		level_label.text = str(level)
	
	# XP
	var xp = current_player.get("xp")
	var xp_next = current_player.get("xp_next")
	if xp != null and xp_next != null:
		if xp_label:
			xp_label.text = "%d / %d" % [xp, xp_next]
		if xp_bar:
			xp_bar.max_value = xp_next
			xp_bar.value = xp
	
	# HP
	var hp = current_player.get("hp")
	var max_hp = current_player.get("max_hp")
	if hp != null and max_hp != null:
		if hp_label:
			hp_label.text = "%d / %d" % [hp, max_hp]
		if hp_bar:
			hp_bar.max_value = max_hp
			hp_bar.value = hp
	
	# Stamina
	var stamina = current_player.get("stamina") if current_player.get("stamina") != null else 100
	var max_stamina = current_player.get("max_stamina") if current_player.get("max_stamina") != null else 100
	if stamina_label:
		stamina_label.text = "%d / %d" % [stamina, max_stamina]
	if stamina_bar:
		stamina_bar.max_value = max_stamina
		stamina_bar.value = stamina
	
	# Mana
	var mana = current_player.get("mana") if current_player.get("mana") != null else 100
	var max_mana = current_player.get("max_mana") if current_player.get("max_mana") != null else 100
	if mana_label:
		mana_label.text = "%d / %d" % [mana, max_mana]
	if mana_bar:
		mana_bar.max_value = max_mana
		mana_bar.value = mana
	
	# Combat stats
	_update_stat("attack", attack_label)
	_update_stat("defense", defense_label)
	_update_stat("agility", agility_label)
	_update_stat("magic", magic_label)
	
	# Skills
	_update_stat("fishing", fishing_label)
	_update_stat("cooking", cooking_label)


## Updates a single stat label
func _update_stat(stat_name: String, label: Label) -> void:
	if label == null or current_player == null:
		return
	var value = current_player.get(stat_name)
	if value != null:
		label.text = str(value)

#endregion
