# represents a single slot in the inventory grid.
# handles item display, hover and selection states, and user interactions.
# slots own their index; stacks know nothing about where they live.
extends PanelContainer
class_name InventorySlot

# --- signals ---

signal slot_clicked(slot: InventorySlot)
signal slot_right_clicked(slot: InventorySlot)
signal slot_hovered(slot: InventorySlot)
signal slot_unhovered(slot: InventorySlot)

# --- state ---

# the item stack stored in this slot — null if slot is empty
# stacks reference shared ItemData and carry per-instance quantity
var stack: ItemStack = null

# the index of this slot in the inventory grid — set by InventoryContainer
var slot_index: int = -1

# whether the mouse is currently hovering over this slot
var is_hovered: bool = false

# whether this slot is currently selected by the player
var is_selected: bool = false

# --- styles ---

var style_normal: StyleBoxFlat
var style_hover: StyleBoxFlat

# --- node references ---

@onready var icon_rect: TextureRect = $centercontainer/icon
@onready var quantity_label: Label = $quantitylabel

func _ready() -> void:
	_create_styles()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	refresh_display()

func _create_styles() -> void:
	# try to get styles from the project theme first
	var slot_theme: Theme = get_theme()
	if slot_theme != null:
		var theme_normal := slot_theme.get_stylebox("panel", "PanelSlot")
		var theme_hover := slot_theme.get_stylebox("panel", "PanelSlotHover")
		if theme_normal != null:
			style_normal = theme_normal
		if theme_hover != null:
			style_hover = theme_hover

	# fallback — create styles programmatically if theme styles not found
	if style_normal == null:
		style_normal = StyleBoxFlat.new()
		style_normal.bg_color = Color(0.15, 0.12, 0.1, 0.9)
		style_normal.border_width_left   = 2
		style_normal.border_width_top    = 2
		style_normal.border_width_right  = 2
		style_normal.border_width_bottom = 2
		style_normal.border_color = Color(0.4, 0.35, 0.25, 1.0)
		style_normal.corner_radius_top_left     = 2
		style_normal.corner_radius_top_right    = 2
		style_normal.corner_radius_bottom_right = 2
		style_normal.corner_radius_bottom_left  = 2

	if style_hover == null:
		style_hover = StyleBoxFlat.new()
		style_hover.bg_color = Color(0.25, 0.2, 0.15, 0.95)
		style_hover.border_width_left   = 2
		style_hover.border_width_top    = 2
		style_hover.border_width_right  = 2
		style_hover.border_width_bottom = 2
		style_hover.border_color = Color(0.85, 0.75, 0.45, 1.0)
		style_hover.corner_radius_top_left     = 2
		style_hover.corner_radius_top_right    = 2
		style_hover.corner_radius_bottom_right = 2
		style_hover.corner_radius_bottom_left  = 2

	add_theme_stylebox_override("panel", style_normal)

# --- stack management ---

func set_stack(new_stack: ItemStack) -> void:
	# store the new stack in this slot — null clears the slot
	# the slot does NOT track position on the stack — slot owns its index
	stack = new_stack
	refresh_display()

func clear_stack() -> void:
	# remove the stack from this slot
	stack = null
	refresh_display()

func is_empty() -> bool:
	# return true if this slot has no valid stack
	return stack == null or not stack.is_valid()

# --- compatibility shim (temporary, removed in step 5) ---
# inventorycontainer.gd still passes old Item objects until we migrate it.
# these methods convert Item -> ItemStack on the fly via the registry,
# so the container doesn't need to know about ItemStack yet.

func set_item(old_item) -> void:
	# accepts old Item — converts to ItemStack via registry lookup
	# this is a temporary bridge; remove after step 5 migrates the container
	if old_item == null:
		clear_stack()
		return

	# old_item could be an Item resource — look up its ItemData via name
	# this is fragile (matching by name) but only used during the migration
	if "name" in old_item:
		var data: ItemData = _find_itemdata_by_name(old_item.name)
		if data != null:
			var new_stack := ItemStack.new(data, old_item.quantity if "quantity" in old_item else 1)
			set_stack(new_stack)
			return

	# couldn't convert — log and clear
	push_warning("InventorySlot: failed to convert legacy Item to ItemStack")
	clear_stack()

func clear_item() -> void:
	# old name kept for container compatibility — delegates to clear_stack
	clear_stack()

# look up ItemData by display_name (for legacy Item conversion only).
# this is fragile and only works because we're in transition.
# step 5 will use item_id directly and remove this helper.
func _find_itemdata_by_name(item_name: String) -> ItemData:
	for data in ItemRegistry.get_all_items():
		if data.display_name == item_name:
			return data
	return null

# --- legacy property accessor (temporary) ---
# inventorycontainer.gd reads `slot.item.name`, `slot.item.tier`, etc.
# until container is migrated, expose a fake `item` property that proxies
# to the stack's data. read-only. remove after step 5.
var item:
	get:
		if stack == null or not stack.is_valid():
			return null
		return stack  # the stack itself acts as a proxy — has .quantity, .data
	set(value):
		set_item(value)

# --- display ---

func refresh_display() -> void:
	# do nothing if nodes are not ready yet
	if not is_node_ready():
		return

	if stack == null or not stack.is_valid():
		# slot is empty — clear icon and quantity label
		icon_rect.texture = null
		quantity_label.text = ""
	else:
		# slot has a stack — read display info from its ItemData
		icon_rect.texture = stack.data.icon

		# show stack quantity if item is stackable and has more than 1
		if stack.data.stackable and stack.quantity > 1:
			quantity_label.text = str(stack.quantity)
		else:
			quantity_label.text = ""

	_update_style()

func set_hovered(hovered: bool) -> void:
	is_hovered = hovered
	_update_style()

func set_selected(selected: bool) -> void:
	is_selected = selected
	_update_style()

func _update_style() -> void:
	if style_normal == null or style_hover == null:
		return

	if is_selected:
		modulate = Color(1.0, 1.0, 0.7, 1.0)
		add_theme_stylebox_override("panel", style_hover)
	elif is_hovered:
		modulate = Color(1.0, 1.0, 1.0, 1.0)
		add_theme_stylebox_override("panel", style_hover)
	else:
		modulate = Color(1.0, 1.0, 1.0, 1.0)
		add_theme_stylebox_override("panel", style_normal)

# --- input handling ---

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			slot_clicked.emit(self)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			slot_right_clicked.emit(self)

func _on_mouse_entered() -> void:
	set_hovered(true)
	slot_hovered.emit(self)

func _on_mouse_exited() -> void:
	set_hovered(false)
	slot_unhovered.emit(self)
