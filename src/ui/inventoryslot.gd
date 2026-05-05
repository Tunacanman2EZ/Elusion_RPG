# represents a single slot in the inventory grid
# handles item display, hover and selection states, and user interactions
extends PanelContainer
class_name InventorySlot

# --- signals ---

# emitted when slot is left clicked — passes this slot as reference
signal slot_clicked(slot: InventorySlot)

# emitted when slot is right clicked — passes this slot as reference
signal slot_right_clicked(slot: InventorySlot)

# emitted when mouse enters the slot — used to show tooltip
signal slot_hovered(slot: InventorySlot)

# emitted when mouse exits the slot — used to hide tooltip
signal slot_unhovered(slot: InventorySlot)

# --- state ---

# the item stored in this slot — null if slot is empty
var item: Item = null

# the index of this slot in the inventory grid — set by InventoryContainer
var slot_index: int = -1

# whether the mouse is currently hovering over this slot
var is_hovered: bool = false

# whether this slot is currently selected by the player
var is_selected: bool = false

# --- styles ---

# normal appearance when slot is not hovered or selected
var style_normal: StyleBoxFlat

# highlighted appearance when slot is hovered or selected
var style_hover: StyleBoxFlat

# --- node references ---

# the texture rect that displays the item icon
@onready var icon_rect: TextureRect = $CenterContainer/Icon

# the label that shows stack quantity for stackable items
@onready var quantity_label: Label = $QuantityLabel

func _ready() -> void:
	# create or load slot visual styles
	_create_styles()

	# connect mouse enter signal to hover handler
	mouse_entered.connect(_on_mouse_entered)

	# connect mouse exit signal to unhover handler
	mouse_exited.connect(_on_mouse_exited)

	# connect input event signal to click handler
	gui_input.connect(_on_gui_input)

	# refresh display to show correct initial state
	refresh_display()

func _create_styles() -> void:
	# try to get styles from the project theme first
	var slot_theme = get_theme()
	if slot_theme:
		# look for a custom PanelSlot stylebox in the theme
		var theme_normal = slot_theme.get_stylebox("panel", "PanelSlot")
		var theme_hover = slot_theme.get_stylebox("panel", "PanelSlotHover")

		# use theme styles if they exist
		if theme_normal:
			style_normal = theme_normal
		if theme_hover:
			style_hover = theme_hover

	# fallback — create styles programmatically if theme styles not found
	if style_normal == null:
		style_normal = StyleBoxFlat.new()
		style_normal.bg_color = Color(0.15, 0.12, 0.1, 0.9)  # dark brown background
		style_normal.border_width_left   = 2
		style_normal.border_width_top    = 2
		style_normal.border_width_right  = 2
		style_normal.border_width_bottom = 2
		style_normal.border_color = Color(0.4, 0.35, 0.25, 1.0)  # muted gold border
		style_normal.corner_radius_top_left     = 2
		style_normal.corner_radius_top_right    = 2
		style_normal.corner_radius_bottom_right = 2
		style_normal.corner_radius_bottom_left  = 2

	if style_hover == null:
		style_hover = StyleBoxFlat.new()
		style_hover.bg_color = Color(0.25, 0.2, 0.15, 0.95)  # slightly lighter on hover
		style_hover.border_width_left   = 2
		style_hover.border_width_top    = 2
		style_hover.border_width_right  = 2
		style_hover.border_width_bottom = 2
		style_hover.border_color = Color(0.85, 0.75, 0.45, 1.0)  # bright gold border on hover
		style_hover.corner_radius_top_left     = 2
		style_hover.corner_radius_top_right    = 2
		style_hover.corner_radius_bottom_right = 2
		style_hover.corner_radius_bottom_left  = 2

	# apply the normal style as the starting appearance
	add_theme_stylebox_override("panel", style_normal)

func set_item(new_item: Item) -> void:
	# store the new item in this slot
	item = new_item

	# update the item's slot index to match this slot position
	if item != null:
		item.slot_index = slot_index

	# refresh the visual display
	refresh_display()

func clear_item() -> void:
	# remove the item from this slot
	item = null

	# refresh display to show empty state
	refresh_display()

func is_empty() -> bool:
	# return true if this slot has no item
	return item == null

func refresh_display() -> void:
	# do nothing if nodes are not ready yet
	if not is_node_ready():
		return

	if item == null:
		# slot is empty — clear icon and quantity label
		icon_rect.texture = null
		quantity_label.text = ""
	else:
		# slot has item — show its icon
		icon_rect.texture = item.icon

		# show stack quantity if item is stackable and has more than 1
		if item.stackable and item.quantity > 1:
			quantity_label.text = str(item.quantity)
		else:
			# hide quantity label for non-stackable or single items
			quantity_label.text = ""

	# update visual style after content change
	_update_style()

func set_hovered(hovered: bool) -> void:
	# update hover state and refresh style
	is_hovered = hovered
	_update_style()

func set_selected(selected: bool) -> void:
	# update selected state and refresh style
	is_selected = selected
	_update_style()

func _update_style() -> void:
	# do nothing if styles haven't been created yet
	if not style_normal or not style_hover:
		return

	if is_selected:
		# selected state — yellow tint and hover style
		modulate = Color(1.0, 1.0, 0.7, 1.0)
		add_theme_stylebox_override("panel", style_hover)
	elif is_hovered:
		# hovered state — normal tint and hover style
		modulate = Color(1.0, 1.0, 1.0, 1.0)
		add_theme_stylebox_override("panel", style_hover)
	else:
		# default state — normal tint and normal style
		modulate = Color(1.0, 1.0, 1.0, 1.0)
		add_theme_stylebox_override("panel", style_normal)

func _on_gui_input(event: InputEvent) -> void:
	# handle mouse button clicks on this slot
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# left click — emit slot clicked signal
			slot_clicked.emit(self)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# right click — emit slot right clicked signal
			slot_right_clicked.emit(self)

func _on_mouse_entered() -> void:
	# mouse entered — set hovered and emit signal for tooltip
	set_hovered(true)
	slot_hovered.emit(self)

func _on_mouse_exited() -> void:
	# mouse exited — clear hovered and emit signal to hide tooltip
	set_hovered(false)
	slot_unhovered.emit(self)
