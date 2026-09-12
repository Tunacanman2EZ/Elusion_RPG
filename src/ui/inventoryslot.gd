# inventoryslot.gd — a single inventory slot. displays one ItemStack (icon +
# quantity), handles hover highlighting, tooltips, right-click use, double-click
# quick-transfer, and drag-and-drop between slots.
#
# slot_type distinguishes contexts ("inventory", "hotbar", "bank", "lootbag")
# so behavior and drag rules can vary. drag-and-drop is container-agnostic:
# any slot can drop onto any other slot, which is what lets items move freely
# between inventory, bank, hotbar, and loot bags.
#
# visual state:
# three styleboxes — normal, hover, and linked (gold border for items with
# a hotbar assignment). the linked style is queried per-frame from the parent
# container so hotbar changes are reflected immediately across all slots.
#
# drop cases:
# - CASE A: source is HotbarSlot → reference-clear only (no item transfer)
# - CASE B1: target empty → move stack from source to here
# - CASE B2: target matches → merge stacks with overflow to source
# - CASE B3: target differs → swap stacks
extends PanelContainer
class_name InventorySlot


# =============================================================================
# SIGNALS
# =============================================================================

signal slot_clicked(slot: InventorySlot)
signal slot_right_clicked(slot: InventorySlot)
signal slot_hovered(slot: InventorySlot)
signal slot_unhovered(slot: InventorySlot)
signal slot_changed(slot: InventorySlot)
signal slot_double_clicked(slot: InventorySlot)


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

@export var slot_type: String = "inventory"


# =============================================================================
# STATE
# =============================================================================

var stack: ItemStack = null
var slot_index: int = -1

var is_hovered: bool = false
var is_selected: bool = false

var style_normal: StyleBoxFlat = null
var style_hover:  StyleBoxFlat = null
var style_linked: StyleBoxFlat = null


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var icon_rect: TextureRect = $centercontainer/icon
@onready var quantity_label: Label = $quantitylabel


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_build_styles()
	_update_style()
	refresh_display()

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


# =============================================================================
# STYLE
# =============================================================================

func _build_styles() -> void:
	var base: StyleBox = get_theme_stylebox("panel")
	if base is StyleBoxFlat:
		style_normal = base.duplicate()
		style_hover = base.duplicate()
		style_hover.bg_color = style_normal.bg_color.lightened(0.15)

		style_linked = style_normal.duplicate()
		style_linked.border_color = Color(0.95, 0.80, 0.30, 1.0)
	else:
		style_normal = StyleBoxFlat.new()
		style_hover = StyleBoxFlat.new()
		style_linked = StyleBoxFlat.new()


func _update_style() -> void:
	if style_normal == null or style_hover == null:
		return

	if is_hovered or is_selected:
		add_theme_stylebox_override("panel", style_hover)
	elif _is_linked_to_hotbar() and style_linked != null:
		add_theme_stylebox_override("panel", style_linked)
	else:
		add_theme_stylebox_override("panel", style_normal)


func _is_linked_to_hotbar() -> bool:
	if is_empty():
		return false

	var parent_container: Node = get_parent()
	if parent_container == null:
		return false
	if not parent_container.has_method("is_item_linked"):
		return false

	return parent_container.is_item_linked(stack.data.item_id)


# =============================================================================
# STACK MANAGEMENT
# =============================================================================

func set_stack(new_stack: ItemStack) -> void:
	stack = new_stack
	refresh_display()


func clear_stack() -> void:
	stack = null
	refresh_display()


func is_empty() -> bool:
	return stack == null or not stack.is_valid()


func refresh_display() -> void:
	if not is_node_ready():
		return

	if is_empty():
		icon_rect.texture = null
		quantity_label.text = ""
		_update_style()
		return

	icon_rect.texture = stack.data.icon
	if stack.quantity > 1:
		quantity_label.text = str(stack.quantity)
	else:
		quantity_label.text = ""

	_update_style()


# =============================================================================
# INPUT — LEFT CLICK (select) + RIGHT CLICK (use) + DOUBLE CLICK (quick transfer)
# =============================================================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.double_click and not is_empty():
				slot_double_clicked.emit(self)
			else:
				slot_clicked.emit(self)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			slot_right_clicked.emit(self)
			accept_event()


# =============================================================================
# HOVER + TOOLTIP
# =============================================================================

func _on_mouse_entered() -> void:
	is_hovered = true
	_update_style()
	slot_hovered.emit(self)
	_show_tooltip()


func _on_mouse_exited() -> void:
	is_hovered = false
	_update_style()
	slot_unhovered.emit(self)
	_hide_tooltip()


func _show_tooltip() -> void:
	if is_empty():
		return
	var tooltip: Node = get_tree().get_first_node_in_group("itemtooltip")
	if tooltip == null:
		return
	if tooltip.has_method("show_for_stack"):
		tooltip.show_for_stack(stack, self)


func _hide_tooltip() -> void:
	var tooltip: Node = get_tree().get_first_node_in_group("itemtooltip")
	if tooltip == null:
		return
	if tooltip.has_method("hide_tooltip"):
		tooltip.hide_tooltip()


# =============================================================================
# DRAG AND DROP — SOURCE
# =============================================================================

func _get_drag_data(_at_position: Vector2) -> Variant:
	if is_empty():
		return null

	_hide_tooltip()

	var preview: TextureRect = TextureRect.new()
	preview.texture = icon_rect.texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.custom_minimum_size = Vector2(40, 40)

	# DRAW THE DRAGGED ICON ABOVE EVERY PANEL.
	#
	# set_drag_preview() parents the preview to the control it is called on —
	# this slot. So the icon you drag lives inside whichever panel you picked
	# it up from, and any panel drawn after that one covers it. The bank is
	# added to the HUD after the inventory, so dragging inventory -> bank sent
	# the icon behind the bank window for the whole trip.
	#
	# Every panel here is in the same CanvasLayer (characterhud, layer 0), so
	# z_index settles the order. It has to be ABSOLUTE: z_index is added to
	# the parent's by default, which would just offset it from whatever the
	# source panel happens to be at. z_as_relative = false ignores the parent
	# and 4096 is the engine's maximum, so the icon is on top of the whole UI
	# no matter which panel the drag started in or where it is headed.
	preview.z_as_relative = false
	preview.z_index = 4096

	set_drag_preview(preview)

	return {
		"stack":       stack.duplicate_stack(),
		"source_slot": self,
		"source_type": slot_type,
	}


# =============================================================================
# DRAG AND DROP — TARGET
# =============================================================================

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY \
		and data.has("stack") \
		and data.has("source_slot")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var incoming:    ItemStack     = data["stack"]
	var source_slot: InventorySlot = data["source_slot"]

	if source_slot == self:
		return

	# CASE A — drag from HotbarSlot. hotbar is just a reference layer; the
	# actual stack already lives in inventory. clearing the hotbar removes
	# the link without touching real inventory contents.
	if source_slot is HotbarSlot:
		source_slot.clear()
		source_slot.slot_changed.emit(source_slot)
		return

	# B1: empty target — move incoming here, clear source
	if is_empty():
		set_stack(incoming)
		source_slot.clear_stack()
		_emit_both_changed(source_slot)
		return

	# B2: target has matching stackable item — merge with overflow handling
	if stack.can_stack_with(incoming):
		var leftover: int = stack.add_to_stack(incoming.quantity)
		if leftover > 0:
			incoming.quantity = leftover
			source_slot.set_stack(incoming)
		else:
			source_slot.clear_stack()
		refresh_display()
		_emit_both_changed(source_slot)
		return

	# B3: different items — swap the two slots' stacks
	var our_old_stack: ItemStack = stack
	set_stack(incoming)
	source_slot.set_stack(our_old_stack)
	_emit_both_changed(source_slot)


func _emit_both_changed(source_slot: InventorySlot) -> void:
	slot_changed.emit(self)
	source_slot.slot_changed.emit(source_slot)
