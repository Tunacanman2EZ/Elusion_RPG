# stats screen UI panel — displays player stats with bars and labels.
# attached to res://scene/ui/statsscreen.tscn
# - opens via the stats button in characterhud
# - emits close_requested when the user closes it
# - supports dragging by the header to reposition
# - remembers position across opens within a session (static var)
extends Control
class_name StatsScreen

# emitted when the close button is pressed so parent can hide/cleanup
signal close_requested()

# --- node references — paths match the lowercase scene tree ---
@onready var main_panel: PanelContainer = $mainpanel
@onready var header_panel: PanelContainer = $mainpanel/margincontainer/vboxcontainer/headerpanel
@onready var close_button: Button = $mainpanel/margincontainer/vboxcontainer/headerpanel/hboxcontainer/closebutton

# stat labels and bars — accessed via unique names (% syntax)
# all of these require Access as Unique Name to be enabled in the scene tree
@onready var level_label: Label = %levelvalue
@onready var xp_label: Label = %xpvalue
@onready var xp_bar: ProgressBar = %xpbar
@onready var hp_label: Label = %hpvalue
@onready var hp_bar: ProgressBar = %hpbar
@onready var stamina_label: Label = %staminavalue
@onready var stamina_bar: ProgressBar = %staminabar
@onready var mana_label: Label = %manavalue
@onready var mana_bar: ProgressBar = %manabar
@onready var attack_label: Label = %attackvalue
@onready var defense_label: Label = %defensevalue
@onready var agility_label: Label = %agilityvalue
@onready var magic_label: Label = %magicvalue
@onready var fishing_label: Label = %fishingvalue
@onready var cooking_label: Label = %cookingvalue

# the player whose stats we're displaying. set via setup_for_player()
var current_player: Node = null

# drag state for header-grab repositioning
var _is_dragging := false
var _drag_offset := Vector2.ZERO

# session-persistent position so the player's preferred spot is remembered
# across multiple opens in the same play session.
# resets when the game closes — for true persistence, write to disk later.
static var _last_position: Vector2 = Vector2(-1, -1)
static var _has_saved_position := false

func _ready() -> void:
	# close button
	if close_button != null:
		if not close_button.pressed.is_connected(_on_close_button_pressed):
			close_button.pressed.connect(_on_close_button_pressed)

	# header drag input — clicking and dragging the header repositions the panel
	if header_panel != null:
		if not header_panel.gui_input.is_connected(_on_header_gui_input):
			header_panel.gui_input.connect(_on_header_gui_input)

	# restore previous position if available
	if _has_saved_position and main_panel != null:
		main_panel.position = _last_position

func _process(_delta: float) -> void:
	# follow mouse with stored offset so the grab feels natural
	if _is_dragging and main_panel != null:
		main_panel.global_position = get_global_mouse_position() - _drag_offset
		_save_position()

# --- dragging and close ---

func _on_header_gui_input(event: InputEvent) -> void:
	# left-click on header begins drag; release ends drag
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_dragging = true
				_drag_offset = get_global_mouse_position() - main_panel.global_position
			else:
				_is_dragging = false
				_save_position()

func _save_position() -> void:
	# persist current position to the static var so reopen reuses it
	if main_panel != null:
		_last_position = main_panel.position
		_has_saved_position = true

func _on_close_button_pressed() -> void:
	# emit signal — parent (characterhud) listens and hides the screen
	close_requested.emit()

# --- player setup and display refresh ---

func setup_for_player(player: Node) -> void:
	# called by characterhud when opening the screen.
	# stores the player reference and refreshes all displays immediately.
	current_player = player
	update_display()

func update_display() -> void:
	# refresh every label and bar from the current player's values.
	# safe to call multiple times — each call re-reads fresh values.
	# called automatically by setup_for_player; can also be called
	# externally if the player's stats change while the screen is open.
	if current_player == null:
		return

	# level
	var level = current_player.get("level")
	if level != null and level_label != null:
		level_label.text = str(level)

	# xp + xp bar
	var xp = current_player.get("xp")
	var xp_next = current_player.get("xp_next")
	if xp != null and xp_next != null:
		if xp_label != null:
			xp_label.text = "%d / %d" % [xp, xp_next]
		if xp_bar != null:
			xp_bar.max_value = xp_next
			xp_bar.value = xp

	# hp + hp bar
	var hp = current_player.get("hp")
	var max_hp = current_player.get("max_hp")
	if hp != null and max_hp != null:
		if hp_label != null:
			hp_label.text = "%d / %d" % [hp, max_hp]
		if hp_bar != null:
			hp_bar.max_value = max_hp
			hp_bar.value = hp

	# stamina + stamina bar — defaults to 100/100 if not present on player
	var stamina = current_player.get("stamina") if current_player.get("stamina") != null else 100
	var max_stamina = current_player.get("max_stamina") if current_player.get("max_stamina") != null else 100
	if stamina_label != null:
		stamina_label.text = "%d / %d" % [stamina, max_stamina]
	if stamina_bar != null:
		stamina_bar.max_value = max_stamina
		stamina_bar.value = stamina

	# mana + mana bar — defaults to 100/100 if not present on player
	var mana = current_player.get("mana") if current_player.get("mana") != null else 100
	var max_mana = current_player.get("max_mana") if current_player.get("max_mana") != null else 100
	if mana_label != null:
		mana_label.text = "%d / %d" % [mana, max_mana]
	if mana_bar != null:
		mana_bar.max_value = max_mana
		mana_bar.value = mana

	# combat stats — handled by the helper
	_update_stat("attack", attack_label)
	_update_stat("defense", defense_label)
	_update_stat("agility", agility_label)
	_update_stat("magic", magic_label)

	# skill stats
	_update_stat("fishing", fishing_label)
	_update_stat("cooking", cooking_label)

func _update_stat(stat_name: String, label: Label) -> void:
	# generic helper to set a stat label's text from a player property.
	# avoids the per-stat if-label-not-null repetition.
	if label == null or current_player == null:
		return
	var value = current_player.get(stat_name)
	if value != null:
		label.text = str(value)
