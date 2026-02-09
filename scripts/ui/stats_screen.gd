"""
StatsScreen UI Panel (Godot 4.5)
Displays and updates a detailed player stats panel.
WHY: Allows players to see core stats, progress bars, and skills at a glance.
HOW: Loads all labels/bar references, sets up signals, supports mouse dragging, and persists position.
TODO:
 - Add custom themes or skin support.
 - Save/load stats screen state to player profile.
 - Modularize player stats connections for other player types.
"""
extends Control
class_name StatsScreen

# --- SIGNALS ---
## Emitted when the close button is pressed so parent can react (e.g., hide panel)
signal close_requested()

# --- UI NODE REFERENCES ---
# Main container for moving the whole panel around
@onready var main_panel: PanelContainer = $MainPanel
# Header area (used as drag handle)
@onready var header_panel: PanelContainer = $MainPanel/MarginContainer/VBoxContainer/HeaderPanel
# Close UI button
@onready var close_button: Button = $MainPanel/MarginContainer/VBoxContainer/HeaderPanel/HBoxContainer/CloseButton

# Stat labels and progress bars, using scene unique names (% syntax for auto-binding)
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

# --- STATE VARIABLES ---
## The player node this screen displays stats for (must be set up with setup_for_player)
var current_player: Node = null

# Variables to track drag state for mouse movement.
var _is_dragging := false
var _drag_offset := Vector2.ZERO

# Stores the most recent stats screen position per session. Resets if game closes.
static var _last_position: Vector2 = Vector2(-1, -1)
static var _has_saved_position := false

# --- INITIALIZATION / SIGNAL CONNECTIONS ---
"""
Prepares the panel for interaction:
- Connects close button and drag signals.
- Restores the last saved screen position (if the user moved it last time).
TODO: Add fade-in/out animation for polished UX.
"""
func _ready() -> void:
	# Connect the close button (panel will emit its close_requested signal when pressed)
	if close_button:
		close_button.pressed.connect(_on_close_button_pressed)
	# Allow the entire header to become a drag handle (UX: robust to miss-clicks)
	if header_panel:
		header_panel.gui_input.connect(_on_header_gui_input)
	# Restore position if the player has moved this panel before
	if _has_saved_position and main_panel:
		main_panel.position = _last_position

# --- MAIN LOOP: PANEL DRAGGING SUPPORT ---
"""
Main per-frame update to handle mouse dragging.
WHY: Allows UI to be moved wherever user wants and remembers this spot.
TODO: Snap panel back to screen bounds if it gets dragged offscreen.
"""
func _process(_delta: float) -> void:
	if _is_dragging and main_panel:
		# Follow mouse by offset so grab feels natural.
		main_panel.global_position = get_global_mouse_position() - _drag_offset
		_save_position()

#region Dragging and Close

"""
Handles mouse input events on header for drag start/stop.
WHY: Lets user reposition stats overlay by dragging the top bar.
TODO: Change header appearance ("drag active" highlight) when dragging.
"""
func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Start drag, remember where mouse grabbed the panel
				_is_dragging = true
				_drag_offset = get_global_mouse_position() - main_panel.global_position
			else:
				# Finish drag; update stored/default position so next open remembers spot
				_is_dragging = false
				_save_position()

"""
Stores current position for use next time this panel is opened.
WHY: Feels consistent and respectful of player layout preferences.
TODO: Persist position to config file (currently resets each session).
"""
func _save_position() -> void:
	if main_panel:
		_last_position = main_panel.position
		_has_saved_position = true

"""
Handles UI signal to close the panel (calls signal so other scenes can hide/cleanup).
WHY: Cleaner than hard-disabling nodes outside the UI screen.
"""
func _on_close_button_pressed() -> void:
	close_requested.emit()

#endregion

#region Player Setup

"""
Assigns a player node to drive stat display.
WHY: Makes the screen reusable for multiple player slots/characters.
TODO: Validate node type and provide fallback defaults if misconfigured.
"""
func setup_for_player(player: Node) -> void:
	current_player = player
	update_display()

"""
Refreshes all stat labels/bars to match the current player's values.
WHY: Called after setup_for_player or any time stats change elsewhere.
TODO:
 - Animate numbers (e.g. HP/XP counting up/down).
 - Color bars based on thresholds (e.g. red for low HP).
 - Hide bars if not relevant (future subclasses/expansions).
"""
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

	# Mana (optional, fallback if not present)
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

"""
Handles updating a single stat label for modularity.
WHY: Avoids code duplication, easy to add more stats later.
TODO: Add tooltips to labels to explain stat effects to user.
"""
func _update_stat(stat_name: String, label: Label) -> void:
	if label == null or current_player == null:
		return
	var value = current_player.get(stat_name)
	if value != null:
		label.text = str(value)

#endregion

"""
# --- FUTURE IMPROVEMENTS FOR TEAM ---
- Add APIs for additional skills and dynamic stat lists (not just hardcoded labels).
- Persist UI layout/settings per player profile.
- Support stat color changes or glow effects for buffs/debuffs.
- Modularize drag/close region into reusable UI node.
"""
