# itemtooltip.gd — shared tooltip that displays item info on slot hover.
# attached to the root of itemtooltip.tscn (a small Panel UI scene).
# lives as a child of the HUD CanvasLayer so it renders above all panels.
#
# architecture:
# one tooltip instance serves all slots in the game. slots locate it via
# the "itemtooltip" group and call show_for_stack() / hide_tooltip().
# this avoids duplicating tooltip logic in every inventory/bank/shop panel.
#
# behavior:
# - follows the cursor while visible (16px offset to avoid overlapping)
# - clamps to screen edges so it doesn't get cut off near the corners
# - shows display_name, description, quantity, and the item's actual stats
# - z_index 100 so it renders above all other UI
#
# =============================================================================
# WHAT THE STATS BLOCK USED TO BE, AND WHY IT SAID NOTHING
# =============================================================================
# itemtooltip.tscn has had a stats panel since it was first drawn: three rows
# reading "Value: 100", "Tier: 1", "Required Level: 1". This script never
# touched any of them. Those are the placeholder strings typed into the scene,
# and every item in the game — a 1,400 gold ember sword, a 12 gold potion —
# showed the same three numbers, because nothing ever overwrote them.
#
# It was the kind of bug that survives because it does not look like one. The
# panel is there, it is styled, it has plausible numbers in it. You have to
# hover two different items and notice the numbers did not change.
#
# THE ROWS ARE BUILT FROM A TEMPLATE NOW, not hardcoded. The scene keeps one
# hidden row (%stattemplate) that carries the styling; this script duplicates
# it once per stat the hovered item actually has. A weapon shows damage, a
# potion shows what it restores, a crafting material shows neither — rather
# than every item showing an identical list with zeroes in it.
extends Control
class_name ItemTooltip


# =============================================================================
# CONSTANTS
# =============================================================================

# offset from cursor so tooltip doesn't sit directly on top of the cursor.
# applied to both right-down (default) and flipped left-up (near edges).
const CURSOR_OFFSET := Vector2(16, 16)

# z_index used to render above all other UI elements
const TOOLTIP_Z_INDEX := 100

# Row colours. NEUTRAL is the scene's own; the other three carry meaning and
# are the only colours in here that a player has to learn.
const COLOUR_NEUTRAL := Color(0.8, 0.75, 0.65)
const COLOUR_GOLD    := Color(1.0, 0.85, 0.3)
const COLOUR_GOOD    := Color(0.55, 0.85, 0.5)
const COLOUR_BAD     := Color(0.9, 0.45, 0.4)


# =============================================================================
# NODE REFERENCES
# =============================================================================
# all use unique-name lookups so the tooltip's internal scene structure
# can be refactored (renest, reparent) without breaking the script.

@onready var name_label:        Label = %tooltipname
@onready var description_label: Label = %tooltipdescription
@onready var quantity_label:    Label = get_node_or_null("%tooltipquantity")
@onready var stats_container:   Control = get_node_or_null("%statscontainer")
@onready var stat_template:     Control = get_node_or_null("%stattemplate")


# =============================================================================
# STATE
# =============================================================================

# tracks the slot currently being hovered — used to detect when to hide
# even if mouse_exited fires twice or from a stale source.
var _current_slot: Node = null

# Rows built for the item currently shown. Freed and rebuilt on every hover
# rather than pooled: a tooltip is shown once per mouse movement, the row count
# is single digits, and a pool that has to be resized both ways is more code
# than it saves.
var _rows: Array[Control] = []


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# register so slots can find this via group lookup
	add_to_group("itemtooltip")

	# tooltip never captures mouse events — it just displays info, never
	# intercepts clicks meant for slots underneath
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# start hidden — only appears on slot hover
	visible = false

	# render above all other UI so the tooltip is never covered by panels
	z_index = TOOLTIP_Z_INDEX

	# The template is a pattern, never a row. Hidden in the scene too; this is
	# belt and braces for the case where someone unhides it while editing.
	if stat_template != null:
		stat_template.visible = false


func _process(_delta: float) -> void:
	# follow the cursor while visible. _process (not _physics_process) gives
	# smooth tracking even during fast mouse movement.
	if not visible:
		return

	global_position = get_global_mouse_position() + CURSOR_OFFSET
	_clamp_to_screen()


# =============================================================================
# PUBLIC API
# =============================================================================

func show_for_stack(stack: ItemStack, source_slot: Node, description_suffix: String = "") -> void:
	# display tooltip with the given stack's info. source_slot is tracked
	# so we can verify hide requests come from the same slot that triggered
	# the show (avoids race conditions when cursor moves between slots fast).
	#
	# description_suffix is optional extra text appended below the description.
	# used by HotbarSlot to add "linked from inventory" hint so players
	# understand the hotbar mirrors inventory items rather than duplicating.
	if stack == null or not stack.is_valid():
		return

	_current_slot = source_slot
	_populate_labels(stack, description_suffix)
	_populate_stats(stack)

	visible = true

	# RESET BEFORE MEASURING. The panel keeps the size it had for the last item
	# until a layout pass runs, so a two-row potion hovered after a nine-row
	# sword would clamp against the sword's height and jump on the next frame.
	# reset_size() asks the container for its own minimum now.
	reset_size()

	# position immediately so the first frame doesn't show at origin (0, 0)
	global_position = get_global_mouse_position() + CURSOR_OFFSET
	_clamp_to_screen()


func hide_tooltip() -> void:
	# hide the tooltip and clear the source-slot tracker.
	# called by slots on mouse_exited.
	visible = false
	_current_slot = null


# =============================================================================
# LABEL POPULATION
# =============================================================================

func _populate_labels(stack: ItemStack, description_suffix: String = "") -> void:
	# fill in the three labels from the stack's ItemData.
	# description_suffix is appended below the base description for
	# context-aware tooltips (e.g., hotbar slots show "linked from inventory").

	if name_label != null:
		name_label.text = stack.data.display_name

	if description_label != null:
		# description is optional on ItemData — fall back to empty string
		# if the field is missing or unset
		var desc: String = ""
		if "description" in stack.data:
			desc = stack.data.description

		# append context suffix on its own line if provided
		if description_suffix != "":
			if desc != "":
				desc += "\n"
			desc += description_suffix

		description_label.text = desc

	if quantity_label != null:
		# only show quantity for stackable items with more than 1
		if stack.data.stackable and stack.quantity > 1:
			quantity_label.text = "x%d" % stack.quantity
			quantity_label.visible = true
		else:
			quantity_label.visible = false


# =============================================================================
# THE STATS BLOCK
# =============================================================================

func _populate_stats(stack: ItemStack) -> void:
	_clear_rows()
	if stats_container == null or stat_template == null:
		return

	var data: ItemData = stack.data
	var player: Node = get_tree().get_first_node_in_group("player")

	# ORDER IS DELIBERATE: what it does, then what it costs you to use it, then
	# what it is worth. A player deciding whether to pick something up reads
	# top-down and stops as soon as they know.
	_add_gear_rows(data, player)
	_add_consumable_rows(data)
	_add_requirement_rows(data, player)
	_add_worth_rows(stack)


func _add_gear_rows(data: ItemData, player: Node) -> void:
	var slot_name: String = ItemData.slot_name(int(data.equip_slot))
	if slot_name == "":
		return

	_add_row("Slot", slot_name.capitalize())

	if data.damage > 0:
		# THE BAND, NOT THE MIDPOINT. `damage` is the middle of a roll — see
		# ItemData.damage_spread — so printing it alone would show a number the
		# player never actually sees land.
		var band: Vector2i = PlayerStats.weapon_damage_range(data.damage, data.damage_spread)
		_add_row("Damage", "%d - %d" % [band.x, band.y])

		# DAMAGE PER SECOND IS THE ONLY HONEST WAY TO COMPARE TWO WEAPONS HERE,
		# and this tooltip is where that stops being an abstraction.
		#
		# An ember scepter carries 13 damage and an ember sword carries 100,
		# and they cost almost the same gold. That is not a mistake: the
		# scepter fires ten times a second and the sword swings once. Per-hit
		# numbers make those two look like a swindle and a bargain; dps makes
		# them look like what they are, which is the same weapon for different
		# hands.
		#
		# The rate comes from the LIVE CHARACTER, via attack_period(), rather
		# than from a table in this file. There is no fifth copy of the
		# cooldowns to drift — and it is also why this row only appears for a
		# weapon the hovered character can actually swing. Showing a warrior
		# the dps a mage would get out of a staff would be worse than showing
		# nothing.
		var period: float = _attack_period_for(data, player)
		if period > 0.0:
			var middle: float = float(band.x + band.y) * 0.5
			_add_row("Damage per second", "%d" % roundi(middle / period))

		_add_comparison_row(data, player, "damage")

	if data.armor_value > 0:
		_add_row("Armour", str(data.armor_value))
		_add_comparison_row(data, player, "armor_value")

	# WHO MAY WEAR IT. Empty means anyone, and an empty row would be noise, so
	# the row only appears when there is a restriction to report. Red when it
	# is not you — this is the single most common reason a piece of gear in
	# your bag refuses to go on.
	if not data.required_classes.is_empty():
		var names := PackedStringArray()
		for class_id in data.required_classes:
			names.append(String(class_id).capitalize())
		var mine: bool = player == null or data.required_classes.has(
			CharacterData.active_class_id())
		_add_row("Class", ", ".join(names),
			COLOUR_NEUTRAL if mine else COLOUR_BAD)


func _add_consumable_rows(data: ItemData) -> void:
	if data.restore_target == ItemData.RestoreTarget.NONE or data.restore_amount <= 0:
		return
	# BY VALUE, NOT BY POSITION, for the same reason ItemData.slot_name() is:
	# an enum member given an explicit number would make keys()[i] name the
	# wrong pool, and "restores 140 MANA" on a health potion is a lie the UI
	# would tell with total confidence.
	var pool: String = ""
	for key in ItemData.RestoreTarget:
		if int(ItemData.RestoreTarget[key]) == int(data.restore_target):
			pool = String(key)
			break
	if pool == "":
		return
	_add_row("Restores", "%d %s" % [data.restore_amount, pool], COLOUR_GOOD)


func _add_requirement_rows(data: ItemData, player: Node) -> void:
	# THE SAME TWO GATES inventoryscreen.gd checks on click, shown before the
	# click. Its _meets_requirements() tells you why an item refused; this
	# tells you in advance, off the same two fields, in the same order.
	if data.required_level > 1:
		var have: int = int(player.level) if player != null and "level" in player else 1
		_add_row("Required level", str(data.required_level),
			COLOUR_NEUTRAL if have >= data.required_level else COLOUR_BAD)

	var skill: String = String(data.required_skill).strip_edges()
	if skill != "" and data.required_skill_level > 1:
		# A skill the player has no property for is a typo in the .tres.
		# Shown in neutral rather than red, and NOT reported here:
		# inventoryscreen.gd already push_error()s that case on use, and a
		# tooltip that shouts on hover would shout sixty times a minute.
		var have_skill: int = int(player.get(skill)) if player != null and skill in player else 1
		_add_row("Required %s" % skill.capitalize(), str(data.required_skill_level),
			COLOUR_NEUTRAL if have_skill >= data.required_skill_level else COLOUR_BAD)


func _add_worth_rows(stack: ItemStack) -> void:
	if stack.data.tier > 1:
		_add_row("Tier", str(stack.data.tier))

	if stack.data.value <= 0:
		return

	# THE WHOLE STACK, when there is a stack. "12 gold" on a pile of sixteen
	# potions answers the wrong question — the one being asked is what happens
	# if this is sold, and that is 192.
	var text: String = "%d gold" % stack.data.value
	if stack.quantity > 1:
		text = "%d gold  (%d)" % [stack.data.value, stack.data.value * stack.quantity]
	_add_row("Value", text, COLOUR_GOLD)


func _add_comparison_row(data: ItemData, player: Node, field: String) -> void:
	# AGAINST WHAT YOU ARE ALREADY WEARING, which is the question a player is
	# actually asking when they hover something on the ground.
	#
	# Silent when there is nothing in that slot, because "+20 damage" against
	# an empty hand is just the item's own number said twice; and silent when
	# you are hovering the piece you have on, because comparing a thing to
	# itself always reads +0 and teaches nobody anything.
	#
	# SILENT ACROSS CLASSES TOO, which the first version was not, and it read
	# badly enough to be worth naming: an ember scepter hovered by a warrior
	# holding an iron sword showed "vs Iron Sword: -7". Both numbers are real
	# and the subtraction is correct, and the row is still nonsense — a
	# scepter fires ten times a second, the comparison is between two things
	# that were never alternatives, and no warrior can hold it anyway. A
	# comparison is only a comparison between two things you could choose.
	if player == null or not ("equipped" in player):
		return
	if not _usable_by_player(data):
		return

	var slot_name: String = ItemData.slot_name(int(data.equip_slot))
	var worn_id: String = str(player.equipped.get(slot_name, ""))
	if worn_id == "" or worn_id == data.item_id:
		return

	var worn: ItemData = ItemRegistry.get_item(worn_id)
	if worn == null:
		return

	var delta: int = int(data.get(field)) - int(worn.get(field))
	if delta == 0:
		return

	_add_row("vs %s" % worn.display_name, "%+d" % delta,
		COLOUR_GOOD if delta > 0 else COLOUR_BAD)


# =============================================================================
# ROW PLUMBING
# =============================================================================

func _add_row(label: String, value: String, colour: Color = COLOUR_NEUTRAL) -> void:
	var row: Control = stat_template.duplicate() as Control
	if row == null:
		return

	# BY PATH, NOT BY UNIQUE NAME. %-lookups resolve against a node's OWNER,
	# and a duplicate added at runtime has none — so %statvalue on a copied row
	# either finds nothing or finds the template's own label, which would make
	# every row show the last value written.
	var name_node: Label = row.get_node_or_null("hboxcontainer/statlabel") as Label
	var value_node: Label = row.get_node_or_null("hboxcontainer/statvalue") as Label
	if name_node == null or value_node == null:
		row.queue_free()
		push_error("ItemTooltip: %stattemplate no longer has hboxcontainer/statlabel and statvalue")
		return

	name_node.text = "%s:" % label
	value_node.text = value
	value_node.add_theme_color_override("font_color", colour)

	# A duplicate has no owner, so the template's unique_name_in_owner flag
	# cannot register anything — cleared anyway, because an inert flag that
	# WOULD do something the day this row gets an owner is not worth carrying.
	row.unique_name_in_owner = false
	row.visible = true
	stats_container.add_child(row)
	_rows.append(row)


func _clear_rows() -> void:
	for row in _rows:
		if is_instance_valid(row):
			row.queue_free()
	_rows.clear()


func _usable_by_player(data: ItemData) -> bool:
	# CLASS ONLY, not level. An item you are four levels short of is still
	# YOURS — you will wear it — and the rows that depend on this (damage per
	# second, and the comparison against what you have on) are exactly what a
	# player wants to see while deciding whether it is worth carrying. An item
	# of another class is never going to be worn, and its numbers are not
	# measured in the same units as yours.
	#
	# An empty required_classes means anyone, which includes you.
	if data.required_classes.is_empty():
		return true
	return data.required_classes.has(CharacterData.active_class_id())


func _attack_period_for(data: ItemData, player: Node) -> float:
	# Seconds between hits for the character holding this, or 0.0 when the
	# question does not apply — no player in the scene, a weapon this class
	# cannot use, or a class whose script has not been given an attack_period().
	if player == null or not player.has_method("attack_period"):
		return 0.0
	if not _usable_by_player(data):
		return 0.0
	return float(player.attack_period())


# =============================================================================
# POSITIONING
# =============================================================================

func _clamp_to_screen() -> void:
	# keep the tooltip on-screen when cursor is near the right or bottom edge.
	# without this, tooltips near those edges get cut off by the viewport.
	# we flip to LEFT-UP positioning when the default RIGHT-DOWN would overflow.
	var screen_size: Vector2 = get_viewport_rect().size
	var our_size:    Vector2 = size

	if global_position.x + our_size.x > screen_size.x:
		# would overflow right edge — flip to the left of the cursor
		global_position.x = get_global_mouse_position().x - our_size.x - CURSOR_OFFSET.x

	if global_position.y + our_size.y > screen_size.y:
		# would overflow bottom edge — flip above the cursor
		global_position.y = get_global_mouse_position().y - our_size.y - CURSOR_OFFSET.y
