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
# - shows the item's icon, display_name, description and what it is worth
#   (quantity rides on the worth line, e.g. "Worth 50 gold each  (800 for 16)")
# - z_index 100 so it renders above all other UI
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

# WHAT CHANGES IF YOU PUT IT ON. Every tier from jade up carries a bonus now,
# and "+45 max health" on its own does not say whether that is more than the
# piece you are already wearing - which is the only thing a player hovering a
# drop wants to know. [field, label, suffix], in the order they are listed.
const COMPARED_STATS := [
	["damage", "Damage", ""],
	["armor_value", "Armour", ""],
	["bonus_max_hp", "Max health", ""],
	["bonus_max_mana", "Max mana", ""],
	["bonus_damage_percent", "Damage bonus", "%"],
]
const COMPARE_BETTER := Color(0.55, 0.85, 0.5)
const COMPARE_WORSE := Color(0.9, 0.45, 0.4)
const COMPARE_SAME := Color(0.8, 0.75, 0.65)


# =============================================================================
# NODE REFERENCES
# =============================================================================
# all use unique-name lookups so the tooltip's internal scene structure
# can be refactored (renest, reparent) without breaking the script.

@onready var name_label:        Label = %tooltipname
@onready var description_label: Label = %tooltipdescription
# THE SCENE HAS THIS AND NOTHING EVER FILLED IT. itemtooltip.tscn carries a
# 32x32 TextureRect in the header, correctly sized and set to keep its aspect,
# which has been drawing nothing since it was added - every tooltip in the game
# has had an empty box where the item's picture goes.
@onready var icon_rect: TextureRect = get_node_or_null("%tooltipicon")
# NO SCENE DECLARES %tooltipquantity. This has always resolved to null, so the
# quantity branch in _populate_labels() has never run once. Left as a
# get_node_or_null rather than deleted because the count is not missing from
# the tooltip - _worth_line() prints "(800 for 16)" for any stack worth
# anything - and if a quantity label is ever added to the scene this lights up
# on its own.
@onready var quantity_label:    Label = get_node_or_null("%tooltipquantity")

# THE STAT ROWS THE SCENE HAS ALWAYS HAD AND NOTHING FILLED. itemtooltip.tscn
# carries a statscontainer with a hidden row template under a second rule, and
# until the comparison below used them every tooltip ended in a rule with an
# empty band under it. They are shown only when there is something to compare.
@onready var stats_box:     VBoxContainer = get_node_or_null("%statscontainer")
@onready var stat_template: Control = get_node_or_null("%stattemplate")
@onready var stats_rule:    Control = get_node_or_null("margincontainer/vboxcontainer/hseparator2")


# =============================================================================
# STATE
# =============================================================================

# A _current_slot tracker lived here, described as detecting a doubled or
# stale mouse_exited. It was assigned on show and cleared on hide and read
# nowhere, so that detection never existed - hide_tooltip() simply hides,
# which is what it did all along and what no bug report has argued with.
#
# IF A STALE EXIT EVER DOES CAUSE TROUBLE - a tooltip hidden by the slot the
# cursor just LEFT, a frame after the slot it just entered showed one - the
# fix is to record the showing slot and ignore a hide from any other. That is
# what this was reaching for; it just never got wired to anything.


# =============================================================================
# LIFECYCLE
# =============================================================================

# The name label's own colour from the scene, for common items.
var _name_default_colour: Color = Color(1, 0.9, 0.6, 1)

# One line under the name saying how rare the thing is, in its colour. Built in
# code so the scene stays the artist-facing layout it is.
var rarity_label: Label = null

# "Compared with your Jade Cuirass", over the comparison rows. Built in code for
# the same reason, and wrapped, because an item's name can be long.
var compare_heading: Label = null


func _ready() -> void:
	# register so slots can find this via group lookup
	add_to_group("itemtooltip")

	if name_label != null:
		_name_default_colour = name_label.get_theme_color("font_color")
		rarity_label = Label.new()
		rarity_label.name = "tooltiprarity"
		rarity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rarity_label.add_theme_font_size_override("font_size", 11)
		var header: Node = name_label.get_parent()
		header.get_parent().add_child(rarity_label)
		header.get_parent().move_child(rarity_label, header.get_index() + 1)

	if stats_box != null:
		compare_heading = Label.new()
		compare_heading.name = "compareheading"
		compare_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		compare_heading.add_theme_font_size_override("font_size", 10)
		compare_heading.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55, 1))
		compare_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		compare_heading.custom_minimum_size = Vector2(180, 0)
		stats_box.add_child(compare_heading)
		stats_box.move_child(compare_heading, 0)
	_show_comparison(false)

	# tooltip never captures mouse events — it just displays info, never
	# intercepts clicks meant for slots underneath
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# start hidden — only appears on slot hover
	visible = false

	# render above all other UI so the tooltip is never covered by panels
	z_index = TOOLTIP_Z_INDEX


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

func show_for_stack(stack: ItemStack, source_slot: Node) -> void:
	# THE SLOT IS READ NOW, for one question: is this the piece being worn? A
	# square on the equipment doll compares with nothing - it IS what everything
	# else is compared with. (It was underscored and unused for a while after a
	# tracker that fed it was removed; see the note at the top of this file.)
	#
	# There was a third parameter, a line appended under the description, and
	# its only caller was a hotbar key adding "Linked from inventory". The keys
	# hold their items now, so there is no link to explain and it is gone.
	if stack == null or not stack.is_valid():
		return

	_populate_labels(stack)
	populate_comparison(stack.data, source_slot, get_tree().get_first_node_in_group("player"))

	# FITTED TO WHAT IT NOW HOLDS. A PanelContainer grows to its content and
	# never shrinks back, so without this a short tooltip after a long one
	# keeps the long one's height as empty space.
	reset_size()

	visible = true

	# position immediately so the first frame doesn't show at origin (0, 0)
	global_position = get_global_mouse_position() + CURSOR_OFFSET
	_clamp_to_screen()

func hide_tooltip() -> void:
	# called by slots on mouse_exited.
	visible = false


# =============================================================================
# LABEL POPULATION
# =============================================================================

func _populate_labels(stack: ItemStack) -> void:
	# fill in the three labels from the stack's ItemData.

	if icon_rect != null:
		# The item's own icon, the same art the backpack cell draws. The node is
		# already EXPAND_IGNORE_SIZE with a 32x32 minimum, so a large texture
		# cannot push the tooltip open - which is the trap the chat panel fell
		# into with the same property.
		icon_rect.texture = stack.data.icon
		icon_rect.visible = stack.data.icon != null

	if name_label != null:
		name_label.text = stack.data.display_name
		# THE NAME TAKES THE RARITY COLOUR from uncommon up; a common name keeps
		# the tooltip's own gold, so an iron sword looks the way it always did.
		var tier: int = int(stack.data.tier)
		var colour: Color = _name_default_colour
		if tier >= GameConstants.RARITY_FRAME_MIN_TIER:
			colour = GameConstants.rarity_colour(tier)
		# A PERFECT PIECE'S NAME IS GOLD at any tier, the colour its slot is
		# framed in, so the one in a hundred is seen before it is read.
		if stack.data.is_perfect():
			colour = GameConstants.QUALITY_PERFECT_COLOUR
		name_label.add_theme_color_override("font_color", colour)

	if rarity_label != null:
		rarity_label.text = rarity_text(stack.data)
		rarity_label.add_theme_color_override("font_color", GameConstants.rarity_colour(int(stack.data.tier)))

	if description_label != null:
		# description is optional on ItemData — fall back to empty string
		# if the field is missing or unset
		var desc: String = ""
		if "description" in stack.data:
			desc = stack.data.description

		# WHAT IT IS AND WHO CAN USE IT, between the flavour text and the
		# context line.
		#
		# The tooltip showed a name, a description and a quantity - which for a
		# weapon is everything except the two things you hover it to learn. The
		# shop rack made that obvious: an ironsword, an ironmaul, an ironstaff
		# and an ironscepter, same shelf, same level, one per class, and the
		# only way to find out which was yours was to buy it and watch the
		# equip refuse.
		#
		# READ FROM ItemData, not from a server row, because this tooltip is
		# shown over the backpack and the equipment doll as well as a shop -
		# and those have no row. The shop's own line comes from the server for
		# the reason the price does; these two agree because both ultimately
		# read the same .tres.
		var facts: String = _requirement_lines(stack.data)
		if facts != "":
			if desc != "":
				desc += "\n"
			desc += facts

		# WHAT IT IS WORTH, and it goes below the requirements because it is the
		# thing you check last.
		#
		# The tooltip never showed a price. That was survivable while a full iron
		# kit cost six kills and nothing in the backpack was worth thinking about;
		# it stopped being survivable when gear was rescaled x8 and the coin
		# denominations landed. A backpack now holds a silver stack worth 250 and
		# a platinum coin worth 100,000 that look like the same kind of clutter,
		# and a player deciding what to sell had no number to decide on.
		#
		# TAKES THE QUANTITY, because "250 gold" on a pile of forty is the answer
		# to a question nobody asked.
		var worth: String = _worth_line(stack.data, stack.quantity)
		if worth != "":
			if desc != "":
				desc += "\n"
			desc += worth

		description_label.text = desc

	if quantity_label != null:
		# only show quantity for stackable items with more than 1
		if stack.data.stackable and stack.quantity > 1:
			quantity_label.text = "x%d" % stack.quantity
			quantity_label.visible = true
		else:
			quantity_label.visible = false



# =============================================================================
# COMPARED WITH WHAT YOU ARE WEARING
# =============================================================================

static func rarity_text(data: ItemData) -> String:
	# "Rare", and for a piece that dropped with a roll, how good the roll is:
	# "Rare  ·  Quality 104%" - its stats' rolls averaged. A store piece is
	# 100% by definition and says nothing more.
	var text: String = GameConstants.rarity_name(int(data.tier))
	if data.is_rolled():
		text += "  ·  Quality %d%%" % data.quality_percent()
	return text


static func roll_note(data: ItemData, field: String) -> String:
	# " (107%)" after a stat that rolled, "" after one that did not. On every
	# rolled stat, including a +1% that rounds to the same point at 85 and 115:
	# the roll is the piece's, and hiding it where the rounding swallows it
	# would make two pieces of one roll read differently.
	if data == null or not data.rolls.has(field):
		return ""
	return " (%d%%)" % int(data.rolls[field])


static func compare_rows(candidate: ItemData, worn: ItemData) -> Array:
	# One {label, delta, suffix} per stat that would change, in COMPARED_STATS
	# order. `worn` null means the slot is empty, so every stat is a gain.
	var rows: Array = []
	if candidate == null:
		return rows
	for spec in COMPARED_STATS:
		var field: String = spec[0]
		var gets: int = int(candidate.get(field)) if field in candidate else 0
		var has: int = int(worn.get(field)) if worn != null and field in worn else 0
		if gets != has:
			rows.append({"label": spec[1], "delta": gets - has, "suffix": spec[2]})
	return rows


static func compare_heading_text(worn: ItemData) -> String:
	if worn == null:
		return "Nothing is worn there yet - all of it is a gain."
	return "Compared with your %s:" % worn.display_name


func populate_comparison(data: ItemData, source_slot: Node, wearer: Node) -> void:
	# NOTHING TO COMPARE, and the rows stay hidden, when the thing is not gear,
	# when it is the worn piece itself, when nobody is playing, or when this
	# class could never wear it - "+40 armour" on plate over a mage's robe is
	# a comparison with a choice nobody has. A level requirement does not hide
	# it: what a piece will be worth at level 16 is worth knowing at 12.
	var slot_name: String = ItemData.slot_name(int(data.equip_slot)) if data != null else ""
	if slot_name == "" or source_slot is EquipmentSlot or wearer == null \
			or not wearer.has_method("equipped_id") or not wearer.has_method("equip_check"):
		_show_comparison(false)
		return
	if str(wearer.equip_check(str(data.item_id)).get("reason", "")) == "class":
		_show_comparison(false)
		return

	var worn: ItemData = ItemRegistry.get_item(wearer.equipped_id(slot_name))
	# AN EMPTY SLOT GETS THE HEADING AND NO ROWS. Against nothing, every row is
	# the item's own number again - the stat line above, said twice in a
	# different case - so the heading says so in one line instead.
	var rows: Array = compare_rows(data, worn) if worn != null else []
	_clear_compare_rows()
	if compare_heading != null:
		compare_heading.text = compare_heading_text(worn)
	if rows.is_empty() and worn != null:
		_add_compare_row("No change", "", COMPARE_SAME)
	for row in rows:
		var delta: int = int(row["delta"])
		_add_compare_row(str(row["label"]), "%+d%s" % [delta, str(row["suffix"])],
			COMPARE_BETTER if delta > 0 else COMPARE_WORSE)
	_show_comparison(true)


func _show_comparison(on: bool) -> void:
	if stats_box != null:
		stats_box.visible = on
	if stats_rule != null:
		stats_rule.visible = on


func _clear_compare_rows() -> void:
	if stats_box == null:
		return
	for child in stats_box.get_children():
		if child.has_meta("compare_row"):
			# Out of the container NOW, so this frame's size does not count it.
			stats_box.remove_child(child)
			child.queue_free()


func _add_compare_row(label: String, value: String, colour: Color) -> void:
	if stats_box == null or stat_template == null:
		return
	var row: Control = stat_template.duplicate() as Control
	row.set_meta("compare_row", true)
	row.visible = true
	var name_cell: Label = row.get_node_or_null("hboxcontainer/statlabel") as Label
	var value_cell: Label = row.get_node_or_null("hboxcontainer/statvalue") as Label
	if name_cell != null:
		name_cell.text = label
	if value_cell != null:
		value_cell.text = value
		value_cell.add_theme_color_override("font_color", colour)
	stats_box.add_child(row)


# =============================================================================
# POSITIONING
# =============================================================================

static func stats_and_needs(data: ItemData) -> String:
	# The stats line and the needs line, for a window with no tooltip of its
	# own to put them in - the trade panel's rows. Static for that reason.
	return _requirement_lines(data)


static func _requirement_lines(data: ItemData) -> String:
	# One line of stats, one of requirements, either omitted when empty.
	#
	# NOTHING FOR A PLAIN MATERIAL, which is most of the catalogue. A tooltip
	# that prints "Needs: anyone" on every rock is noise paid on every hover to
	# help on a few.
	var lines := PackedStringArray()

	var stats := PackedStringArray()
	# A ROLLED PIECE'S NUMBERS ARE ALREADY ITS OWN - ItemRegistry scaled them -
	# and each one says its roll after it: "22 damage (110%)".
	if "damage" in data and int(data.damage) > 0:
		stats.append("%d damage%s" % [int(data.damage), roll_note(data, "damage")])
	if "armor_value" in data and int(data.armor_value) > 0:
		stats.append("%d armour%s" % [int(data.armor_value), roll_note(data, "armor_value")])
	# WHAT THE AMULETS ADD. Signed, because these are added to the character
	# rather than being the item's own number the way damage and armour are.
	if "bonus_max_hp" in data and int(data.bonus_max_hp) > 0:
		stats.append("+%d max health%s" % [int(data.bonus_max_hp), roll_note(data, "bonus_max_hp")])
	if "bonus_max_mana" in data and int(data.bonus_max_mana) > 0:
		stats.append("+%d max mana%s" % [int(data.bonus_max_mana), roll_note(data, "bonus_max_mana")])
	if "bonus_damage_percent" in data and int(data.bonus_damage_percent) > 0:
		# "damage bonus", not "damage": a sword's line read "32 Damage, +2%
		# Damage", one word for two different numbers. The comparison rows and
		# the Gear window call it the same thing.
		stats.append("+%d%% damage bonus%s" % [int(data.bonus_damage_percent),
			roll_note(data, "bonus_damage_percent")])
	if "restore_amount" in data and int(data.restore_amount) > 0:
		var pool: String = ItemData.RestoreTarget.keys()[int(data.restore_target)] \
			if int(data.restore_target) < ItemData.RestoreTarget.size() else ""
		# THE ONLY PLACE THE NUMBER IS SAID. Every potion and cooked fish used to
		# end its description with "Restores 260 HP." as well, so the tooltip
		# said it twice - once as typed, once from the data, and capitalize()
		# turned the second "hp" into "Hp". The descriptions are flavour now and
		# this line, which cannot drift from restore_amount, is the number.
		if pool != "" and pool != "NONE":
			var noun: String = "health" if pool == "HP" else pool.to_lower()
			stats.append("restores %d %s" % [int(data.restore_amount), noun])
	if not stats.is_empty():
		lines.append(", ".join(stats).capitalize())

	var needs := PackedStringArray()
	if "required_level" in data and int(data.required_level) > 1:
		needs.append("Lv %d" % int(data.required_level))
	if "required_skill" in data and str(data.required_skill) != "" \
			and int(data.required_skill_level) > 1:
		needs.append("%s %d" % [str(data.required_skill).capitalize(),
			int(data.required_skill_level)])

	# " or ", NOT a comma. Iron plate is ["warrior", "tank"] and "Warrior, Tank"
	# reads as needing to be both.
	if "required_classes" in data and not data.required_classes.is_empty():
		var names := PackedStringArray()
		for c in data.required_classes:
			names.append(str(c).capitalize())
		needs.append(" or ".join(names))

	if not needs.is_empty():
		lines.append("Needs %s" % ", ".join(needs))

	return "\n".join(lines)


func _worth_line(data: ItemData, quantity: int) -> String:
	# One line, or nothing at all for the things that have no price.
	#
	# TWO WORDINGS, BECAUSE THERE ARE TWO MEANINGS OF value.
	#
	# On a sword, `value` is what a vendor pays and the shop charges - it is a
	# price, and the item is the thing you own. "Worth 200 gold" is right.
	#
	# On a coin it is not a price, it is the face value: a gold stack IS 5,000
	# gold, the way a banknote is not worth money but is money. Calling that
	# "worth" invites the reading that a vendor might pay something else for it,
	# which is exactly the confusion the eight-rung denomination ladder can
	# cause. "Cash in for" says what right-clicking it actually does.
	if data == null:
		return ""

	var unit: int = int(data.value)
	if unit <= 0:
		return ""

	var count: int = maxi(1, quantity)
	var total: int = unit * count

	if int(data.type) == int(ItemData.Type.CURRENCY):
		# LUSIONS ARE NOT GOLD. The premium currency has value = 1 and a pile of
		# them cashes in for lusions, so naming gold here would be a lie in the
		# one place a player is most likely to believe it.
		#
		# THE SAME TEST inventoryscreen.gd::_use_currency_pile() routes on, and
		# deliberately so: if the tooltip and the right-click ever disagreed about
		# which pool a pile feeds, the tooltip would be the one lying.
		if "lusion" in str(data.item_id).to_lower():
			return "Cash in for %s" % GameConstants.counted(total, "lusion")
		return "Cash in for %s" % GameConstants.gold_text(total)

	if count > 1:
		return "Worth %s each  (%s for %d)" % [
			GameConstants.gold_text(unit), GameConstants.commas(total), count]
	return "Worth %s" % GameConstants.gold_text(unit)


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
