# hotbarslot.gd — extends InventorySlot for the hotbar quickslot system.
#
# key difference from regular inventory slots:
# - inventory slots OWN their ItemStack
# - hotbar slots store a REFERENCE (item_id string) and look up the live
#   stack from the player's inventory on every refresh
#
# this means:
# - hotbar always shows current inventory quantity (drink a potion, count drops)
# - if player runs out of an item, the slot auto-clears
# - dragging the same item to a different slot moves it (one slot per item_id)
#
# visual cues that hotbar slots are LINKS not COPIES:
# - tooltip says "Linked from inventory" under the description
# - assigned slots get a gold-tinted border (vs the default brown)
# both communicate to the player that the hotbar mirrors inventory items
# rather than duplicating them, preventing "why is this item in two places?"
# confusion.
#
# empty-state filler art:
# each slot has an `empty_icon` export. when no item is assigned, this art
# shows as a placeholder. when an item is assigned, the item's icon takes over.
extends InventorySlot
class_name HotbarSlot


# =============================================================================
# CONSTANTS
# =============================================================================

# fixed slot size — matches the 32x32 pixel art convention.
const SLOT_SIZE := Vector2(32, 32)

# tooltip suffix added when hovering an assigned hotbar slot.
# communicates the link-not-copy relationship to the player.
const TOOLTIP_LINK_SUFFIX := "Linked from inventory"


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# placeholder art shown when the slot has no item assigned.
@export var empty_icon: Texture2D = null


# =============================================================================
# STATE
# =============================================================================

# the item_id this slot points to. empty string means unassigned.
var assigned_item_id: String = ""

# gold-tinted stylebox for assigned hotbar slots. built once in _ready.
# applied in _update_style when is_assigned() returns true.
var style_assigned: StyleBoxFlat = null


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	slot_type = "hotbar"
	custom_minimum_size = SLOT_SIZE
	super._ready()
	_build_assigned_style()
	_show_empty_state()


# =============================================================================
# STYLE SETUP
# =============================================================================

func _build_assigned_style() -> void:
	# build a gold-tinted variant of the normal slot style.
	# used to visually signal that the slot has an item linked from inventory.
	# duplicates the existing style_normal so size, padding, and corners stay
	# consistent — only the border color changes to gold.
	if style_normal == null:
		return

	style_assigned = style_normal.duplicate()
	style_assigned.border_color = Color(0.95, 0.80, 0.30, 1.0)  # gold border


# =============================================================================
# PUBLIC API
# =============================================================================

func set_item_id(item_id: String) -> void:
	assigned_item_id = item_id
	_update_style()  # repaint border tint to match new state


func get_item_id() -> String:
	return assigned_item_id


func is_assigned() -> bool:
	return assigned_item_id != ""


func refresh_from_inventory(inventory_container: Node) -> void:
	# update display by looking up the assigned item_id in inventory.
	# clears the assignment if the player has 0 of the item, and shows
	# the empty_icon as a placeholder.
	if assigned_item_id == "":
		stack = null
		_show_empty_state()
		return

	if inventory_container == null:
		return

	# renamed from slot_index to found_index to avoid shadowing the
	# inherited InventorySlot.slot_index member (this is inventory's index,
	# not this hotbar slot's own index).
	var found_index: int = inventory_container.find_first_index_of(assigned_item_id)
	if found_index == -1:
		# player has none of this item — auto-clear and show empty art
		assigned_item_id = ""
		stack = null
		_show_empty_state()
		return

	# show the item from inventory
	stack = inventory_container.get_stack_at(found_index)
	refresh_display()


func clear() -> void:
	# wipe the slot. used on death cleanup.
	assigned_item_id = ""
	stack = null
	_show_empty_state()


# =============================================================================
# EMPTY STATE DISPLAY
# =============================================================================

func _show_empty_state() -> void:
	# replace the standard "empty slot" rendering with the empty_icon art.
	if not is_node_ready():
		return
	if icon_rect == null:
		return
	icon_rect.texture = empty_icon
	if quantity_label != null:
		quantity_label.text = ""
	_update_style()


# =============================================================================
# STYLE OVERRIDE — ASSIGNED BORDER TINT
# =============================================================================

func _update_style() -> void:
	# extends the inherited style logic with an extra state: assigned slots
	# get a gold border to signal "this slot is linked to inventory."
	# selected and hovered states still take priority over assigned.
	if style_normal == null or style_hover == null:
		return

	if is_selected:
		modulate = Color(1.0, 1.0, 0.7, 1.0)
		add_theme_stylebox_override("panel", style_hover)
	elif is_hovered:
		modulate = Color(1.0, 1.0, 1.0, 1.0)
		add_theme_stylebox_override("panel", style_hover)
	elif is_assigned() and style_assigned != null:
		# assigned slot — show gold border to signal the inventory link
		modulate = Color(1.0, 1.0, 1.0, 1.0)
		add_theme_stylebox_override("panel", style_assigned)
	else:
		modulate = Color(1.0, 1.0, 1.0, 1.0)
		add_theme_stylebox_override("panel", style_normal)


# =============================================================================
# TOOLTIP OVERRIDE — LINKED-FROM-INVENTORY HINT
# =============================================================================

func _show_tooltip() -> void:
	# extends the inherited tooltip with a "Linked from inventory" suffix.
	# explains to the player that hotbar items mirror inventory items rather
	# than being duplicates — prevents the "why is this item in two places?"
	# confusion that comes with reference-based hotbars.
	if is_empty():
		return

	var tooltip: Node = get_tree().get_first_node_in_group("itemtooltip")
	if tooltip == null:
		return
	if tooltip.has_method("show_for_stack"):
		tooltip.show_for_stack(stack, self, TOOLTIP_LINK_SUFFIX)


# =============================================================================
# DRAG/DROP OVERRIDES
# =============================================================================

func _get_drag_data(_at_position: Vector2) -> Variant:
	if not is_assigned() or stack == null or not stack.is_valid():
		return null

	_hide_tooltip()

	var preview: TextureRect = TextureRect.new()
	preview.texture = icon_rect.texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.custom_minimum_size = Vector2(40, 40)
	set_drag_preview(preview)

	return {
		"stack":         stack.duplicate_stack(),
		"source_slot":   self,
		"source_type":   slot_type,
		"hotbar_id":     assigned_item_id,
	}


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var source_slot = data.get("source_slot")
	var dragged_stack: ItemStack = data.get("stack")

	if dragged_stack == null or not dragged_stack.is_valid():
		return

	var new_item_id: String = dragged_stack.data.item_id

	if source_slot == self:
		return

	if source_slot is HotbarSlot:
		# hotbar-to-hotbar swap: give the source THIS slot's current item,
		# and take the dragged item into this slot. (no separate source_id
		# needed — assigned_item_id IS this slot's current item pre-swap.)
		source_slot.set_item_id(assigned_item_id)
		set_item_id(new_item_id)
	else:
		set_item_id(new_item_id)

	slot_changed.emit(self)
	if source_slot != null and source_slot.has_signal("slot_changed"):
		source_slot.slot_changed.emit(source_slot)
