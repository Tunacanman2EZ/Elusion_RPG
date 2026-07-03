# statsscreen.gd — stats panel showing the player's level, XP, HP, mana,
# stamina, combat stats, and skill stats with bars and labels.
# attached to res://scene/ui/statsscreen.tscn.
#
# skill XP bars:
# each of the 6 skills has a ProgressBar (0..100) + centered "XX/100" label
# showing progress to the next skill level. fills as (skill_xp / skill_xp_next)
# * 100; on skill level-up, skill_xp resets so the bar empties and refills.
#
# refresh model:
# update_display() reads fresh values from the player on each call. the HUD
# polls this every frame while the screen is open (characterhud._process).
extends Control


# =============================================================================
# SIGNALS
# =============================================================================

signal close_requested()


# =============================================================================
# NODE REFERENCES — STRUCTURE
# =============================================================================

@onready var main_panel:   PanelContainer = $mainpanel
@onready var header_panel: PanelContainer = $mainpanel/margincontainer/vboxcontainer/headerpanel
@onready var close_button: Button         = $mainpanel/margincontainer/vboxcontainer/headerpanel/hboxcontainer/closebutton


# =============================================================================
# NODE REFERENCES — STAT WIDGETS
# =============================================================================

@onready var level_label: Label       = %levelvalue
@onready var xp_label:    Label       = %xpvalue
@onready var xp_bar:      ProgressBar = %xpbar

@onready var hp_label:      Label       = %hpvalue
@onready var hp_bar:        ProgressBar = %hpbar
@onready var stamina_label: Label       = %staminavalue
@onready var stamina_bar:   ProgressBar = %staminabar
@onready var mana_label:    Label       = %manavalue
@onready var mana_bar:      ProgressBar = %manabar

@onready var attack_label:  Label = %attackvalue
@onready var defense_label: Label = %defensevalue
@onready var agility_label: Label = %agilityvalue
@onready var magic_label:   Label = %magicvalue

@onready var fishing_label: Label = %fishingvalue
@onready var cooking_label: Label = %cookingvalue


# =============================================================================
# NODE REFERENCES — SKILL XP BARS + LABELS
# =============================================================================

@onready var attack_bar:   ProgressBar = %attackbar
@onready var defense_bar:  ProgressBar = %defensebar
@onready var agility_bar:  ProgressBar = %agilitybar
@onready var magic_bar:    ProgressBar = %magicbar
@onready var fishing_bar:  ProgressBar = %fishingbar
@onready var cooking_bar:  ProgressBar = %cookingbar

@onready var attack_bar_label:   Label = %attackbarlabel
@onready var defense_bar_label:  Label = %defensebarlabel
@onready var agility_bar_label:  Label = %agilitybarlabel
@onready var magic_bar_label:    Label = %magicbarlabel
@onready var fishing_bar_label:  Label = %fishingbarlabel
@onready var cooking_bar_label:  Label = %cookingbarlabel


# =============================================================================
# STATE
# =============================================================================

var current_player: Node = null

var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO


# =============================================================================
# SESSION-PERSISTENT POSITION
# =============================================================================

static var _last_position: Vector2 = Vector2(-1, -1)
static var _has_saved_position: bool = false


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_wire_close_button()
	_wire_header_drag()
	_restore_last_position()


func _process(_delta: float) -> void:
	if _is_dragging and main_panel != null:
		main_panel.global_position = get_global_mouse_position() - _drag_offset
		_save_position()


# =============================================================================
# INITIALIZATION HELPERS
# =============================================================================

func _wire_close_button() -> void:
	if close_button == null:
		return
	if not close_button.pressed.is_connected(_on_close_button_pressed):
		close_button.pressed.connect(_on_close_button_pressed)


func _wire_header_drag() -> void:
	if header_panel == null:
		return
	if not header_panel.gui_input.is_connected(_on_header_gui_input):
		header_panel.gui_input.connect(_on_header_gui_input)


func _restore_last_position() -> void:
	if _has_saved_position and main_panel != null:
		main_panel.position = _last_position


# =============================================================================
# DRAG HANDLING
# =============================================================================

func _on_header_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.pressed:
		_is_dragging = true
		_drag_offset = get_global_mouse_position() - main_panel.global_position
	else:
		_is_dragging = false
		_save_position()


func _save_position() -> void:
	if main_panel != null:
		_last_position = main_panel.position
		_has_saved_position = true


# =============================================================================
# CLOSE BUTTON
# =============================================================================

func _on_close_button_pressed() -> void:
	close_requested.emit()


# =============================================================================
# PLAYER SETUP
# =============================================================================

func setup_for_player(player: Node) -> void:
	current_player = player
	update_display()


# =============================================================================
# DISPLAY REFRESH
# =============================================================================

func update_display() -> void:
	if current_player == null:
		return

	_update_progression()
	_update_resource_bars()
	_update_combat_stats()
	_update_skill_stats()
	_update_skill_xp_bars()


func _update_progression() -> void:
	var level = current_player.get("level")
	if level != null and level_label != null:
		level_label.text = str(level)

	var xp = current_player.get("xp")
	var xp_next = current_player.get("xp_next")
	if xp != null and xp_next != null:
		if xp_label != null:
			xp_label.text = "%d / %d" % [xp, xp_next]
		if xp_bar != null:
			xp_bar.max_value = xp_next
			xp_bar.value = xp


func _update_resource_bars() -> void:
	var hp = current_player.get("hp")
	var max_hp = current_player.get("max_hp")
	if hp != null and max_hp != null:
		_set_bar_and_label(hp, max_hp, hp_label, hp_bar)

	var stamina = current_player.get("stamina") if current_player.get("stamina") != null else 100
	var max_stamina = current_player.get("max_stamina") if current_player.get("max_stamina") != null else 100
	_set_bar_and_label(stamina, max_stamina, stamina_label, stamina_bar)

	var mana = current_player.get("mana") if current_player.get("mana") != null else 100
	var max_mana = current_player.get("max_mana") if current_player.get("max_mana") != null else 100
	_set_bar_and_label(mana, max_mana, mana_label, mana_bar)


func _update_combat_stats() -> void:
	_update_stat("attack",  attack_label)
	_update_stat("defense", defense_label)
	_update_stat("agility", agility_label)
	_update_stat("magic",   magic_label)


func _update_skill_stats() -> void:
	_update_stat("fishing", fishing_label)
	_update_stat("cooking", cooking_label)


# =============================================================================
# SKILL XP BARS
# =============================================================================

func _update_skill_xp_bars() -> void:
	_update_skill_bar("attack",  attack_bar,  attack_bar_label)
	_update_skill_bar("defense", defense_bar, defense_bar_label)
	_update_skill_bar("agility", agility_bar, agility_bar_label)
	_update_skill_bar("magic",   magic_bar,   magic_bar_label)
	_update_skill_bar("fishing", fishing_bar, fishing_bar_label)
	_update_skill_bar("cooking", cooking_bar, cooking_bar_label)


func _update_skill_bar(skill: String, bar: ProgressBar, label: Label) -> void:
	if bar == null or label == null:
		return

	var xp = current_player.get(skill + "_xp")
	var xp_next = current_player.get(skill + "_xp_next")

	if xp == null or xp_next == null or xp_next <= 0:
		bar.value = 0
		label.text = "0/100"
		return

	var percent: int = int(clamp((float(xp) / float(xp_next)) * 100.0, 0.0, 100.0))
	bar.min_value = 0
	bar.max_value = 100
	bar.value = percent
	label.text = "%d/100" % percent


# =============================================================================
# SHARED HELPERS
# =============================================================================

func _set_bar_and_label(value: int, max_value: int, label: Label, bar: ProgressBar) -> void:
	if label != null:
		label.text = "%d / %d" % [value, max_value]
	if bar != null:
		bar.max_value = max_value
		bar.value = value


func _update_stat(stat_name: String, label: Label) -> void:
	if label == null or current_player == null:
		return
	var value = current_player.get(stat_name)
	if value != null:
		label.text = str(value)
