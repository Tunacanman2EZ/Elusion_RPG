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
# - shows display_name, description, and quantity (if stackable + >1)
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


# =============================================================================
# NODE REFERENCES
# =============================================================================
# all use unique-name lookups so the tooltip's internal scene structure
# can be refactored (renest, reparent) without breaking the script.

@onready var name_label:        Label = %tooltipname
@onready var description_label: Label = %tooltipdescription
@onready var quantity_label:    Label = get_node_or_null("%tooltipquantity")


# =============================================================================
# STATE
# =============================================================================

# tracks the slot currently being hovered — used to detect when to hide
# even if mouse_exited fires twice or from a stale source.
var _current_slot: Node = null


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

	visible = true

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
