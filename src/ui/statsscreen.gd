# statsscreen.gd — stats panel showing the player's level, XP, HP, mana,
# stamina, combat stats, and skill stats with bars and labels.
# attached to res://scene/ui/statsscreen.tscn.
#
# TWO COLUMNS since day 1: the level, experience and the three pools on the
# left, the six skills on the right, so nothing scrolls and no line separates
# anything a box already does. Big numbers are short ("1M", see
# GameConstants.short_number()) and the exact figure is in the tooltip.
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

@onready var close_button: Button         = $mainpanel/margincontainer/vboxcontainer/headerpanel/hboxcontainer/closebutton


# =============================================================================
# NODE REFERENCES — STAT WIDGETS
# =============================================================================

@onready var level_label: Label       = %levelvalue
@onready var xp_label:    Label       = %xpvalue
@onready var xp_bar:      ProgressBar = %xpbar
@onready var xp_next_label: Label     = get_node_or_null("%xpnext")

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


# =============================================================================
# LIFECYCLE
# =============================================================================

# Drag by the header, resize from any edge, and come back where it was left.
# One component for all sixteen panels - see src/shared/panelwindow.gd for why
# this is not thirty lines copied into each of them.
#
# HELD IN A MEMBER, not discarded. It is a RefCounted carrying the drag state
# and the signal connections; letting it go frees it and the panel quietly
# stops responding.
var _window: PanelWindow


func _ready() -> void:
	# "charstats", NOT "stats": a rectangle saved for the old narrow window
	# would open this one 500 tall with a band of nothing under its boxes.
	_window = PanelWindow.attach(self, "charstats")
	_wire_close_button()


# =============================================================================
# INITIALIZATION HELPERS
# =============================================================================

func _wire_close_button() -> void:
	if close_button == null:
		return
	if not close_button.pressed.is_connected(_on_close_button_pressed):
		close_button.pressed.connect(_on_close_button_pressed)


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
		var exact: String = "%s / %s XP" % [GameConstants.commas(int(xp)), GameConstants.commas(int(xp_next))]
		if xp_label != null:
			xp_label.text = "%s / %s" % [GameConstants.short_number(int(xp)), GameConstants.short_number(int(xp_next))]
			xp_label.tooltip_text = exact
		if xp_bar != null:
			xp_bar.max_value = xp_next
			xp_bar.value = xp
			xp_bar.tooltip_text = exact
		if xp_next_label != null:
			xp_next_label.text = xp_next_text(int(xp), int(xp_next), int(level) if level != null else 0)


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
		label.text = "0%"
		return

	var percent: int = int(clamp((float(xp) / float(xp_next)) * 100.0, 0.0, 100.0))
	bar.min_value = 0
	bar.max_value = 100
	bar.value = percent
	# A PERCENTAGE, SAID AS ONE. "%d/100" read as 37 XP out of 100 - the level
	# curve's first threshold - on every skill, whatever it really needed.
	label.text = "%d%%" % percent
	# THE EXACT NUMBERS ON THE ROW, for whoever wants them.
	var row: Control = bar.get_parent() as Control
	if row != null:
		var at: int = int(current_player.get(skill)) if current_player.get(skill) != null else 0
		row.tooltip_text = "%s / %s XP to level %d" % [GameConstants.commas(int(xp)),
			GameConstants.commas(int(xp_next)), at + 1]


static func xp_next_text(xp: int, xp_next: int, level: int) -> String:
	# "1% · 998K to level 30"
	if xp_next <= 0:
		return ""
	var percent: int = int(clamp(float(xp) / float(xp_next) * 100.0, 0.0, 100.0))
	return "%d%% · %s to level %d" % [percent,
		GameConstants.short_number(maxi(0, xp_next - xp)), level + 1]


# =============================================================================
# SHARED HELPERS
# =============================================================================

func _set_bar_and_label(value: int, max_value: int, label: Label, bar: ProgressBar) -> void:
	if label != null:
		label.text = "%s / %s" % [GameConstants.short_number(value), GameConstants.short_number(max_value)]
	if bar != null:
		bar.max_value = max_value
		bar.value = value
		bar.tooltip_text = "%s / %s" % [GameConstants.commas(value), GameConstants.commas(max_value)]


func _update_stat(stat_name: String, label: Label) -> void:
	if label == null or current_player == null:
		return
	var value = current_player.get(stat_name)
	if value != null:
		label.text = str(value)
