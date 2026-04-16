extends Control
class_name StatsScreenUI

signal close_requested()

# --- UI REFERENCES ---
@onready var main_panel: PanelContainer = $MainPanel
@onready var header_panel: PanelContainer = $MainPanel/MarginContainer/VBoxContainer/HeaderPanel
@onready var close_button: Button = $MainPanel/MarginContainer/VBoxContainer/HeaderPanel/HBoxContainer/CloseButton

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

# --- STATE ---
var current_player: Node = null

var _is_dragging := false
var _drag_offset := Vector2.ZERO

static var _last_position: Vector2 = Vector2(-1, -1)
static var _has_saved_position := false


func _ready() -> void:
	if close_button:
		close_button.pressed.connect(_on_close_button_pressed)

	if header_panel:
		header_panel.gui_input.connect(_on_header_gui_input)

	if _has_saved_position and main_panel:
		main_panel.global_position = _last_position


func _process(_delta: float) -> void:
	# Drag follow
	if _is_dragging and main_panel:
		main_panel.global_position = get_global_mouse_position() - _drag_offset
		_save_position()

	# Prevent stuck dragging
	if _is_dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_is_dragging = false
		_save_position()


#region Dragging

func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_dragging = true
			_drag_offset = get_global_mouse_position() - main_panel.global_position
		else:
			_is_dragging = false
			_save_position()


func _save_position() -> void:
	if main_panel:
		_last_position = main_panel.global_position
		_has_saved_position = true


func _on_close_button_pressed() -> void:
	close_requested.emit()

#endregion


#region Player Setup

func setup_for_player(player: Node) -> void:
	current_player = player
	update_display()


func update_display() -> void:
	if current_player == null:
		return

	# Level
	level_label.text = str(current_player.get("level"))

	# XP
	var xp = current_player.get("xp")
	var xp_next = current_player.get("xp_next")
	if xp != null and xp_next != null:
		xp_label.text = "%d / %d" % [xp, xp_next]
		xp_bar.max_value = xp_next
		xp_bar.value = xp

	# HP
	var hp = current_player.get("hp")
	var max_hp = current_player.get("max_hp")
	if hp != null and max_hp != null:
		hp_label.text = "%d / %d" % [hp, max_hp]
		hp_bar.max_value = max_hp
		hp_bar.value = hp

	# Stamina (safe fallback)
	var stamina = current_player.get("stamina")
	var max_stamina = current_player.get("max_stamina")
	if stamina == null: stamina = 100
	if max_stamina == null: max_stamina = 100

	stamina_label.text = "%d / %d" % [stamina, max_stamina]
	stamina_bar.max_value = max_stamina
	stamina_bar.value = stamina

	# Mana (safe fallback)
	var mana = current_player.get("mana")
	var max_mana = current_player.get("max_mana")
	if mana == null: mana = 100
	if max_mana == null: max_mana = 100

	mana_label.text = "%d / %d" % [mana, max_mana]
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


func _update_stat(stat_name: String, label: Label) -> void:
	if label == null or current_player == null:
		return

	var value = current_player.get(stat_name)
	if value != null:
		label.text = str(value)

#endregion
