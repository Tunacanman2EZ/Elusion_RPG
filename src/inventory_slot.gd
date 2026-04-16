extends PanelContainer
class_name InventorySlotUI

## Emitted when slot is left clicked
signal slot_clicked(slot: InventorySlotUI)
## Emitted when slot is right-clicked
signal slot_right_clicked(slot: InventorySlotUI)
## Emitted when mouse enters the slot
signal slot_hovered(slot: InventorySlotUI)
## Emitted when mouse exits the slot
signal slot_unhovered(slot: InventorySlotUI)

## The item stored in this slot (null if empty)
var item: Item = null
## The index of this slot in the inventory grid
var slot_index: int = -1
## Whether the slot is currently hovered
var is_hovered: bool = false
## Whether the slot is currently selected
var is_selected: bool = false

## Normal style for the slot panel
var style_normal: StyleBoxFlat
## Hover style for the slot panel
var style_hover: StyleBoxFlat

## Reference to the item icon
@onready var icon_rect: TextureRect = $CenterContainer/Icon
## Reference to the stack quantity label
@onready var quantity_label: Label = $QuantityLabel


func _ready() -> void:
	_create_styles()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	refresh_display()


## Creates the slot styles
func _create_styles() -> void:
	var slot_theme = get_theme()

	if slot_theme:
		var theme_normal = slot_theme.get_stylebox("panel", "PanelSlot")
		var theme_hover = slot_theme.get_stylebox("panel", "PanelSlotHover")

		if theme_normal:
			style_normal = theme_normal.duplicate()
		if theme_hover:
			style_hover = theme_hover.duplicate()

	# Fallback styles
	if style_normal == null:
		style_normal = StyleBoxFlat.new()
		style_normal.bg_color = Color(0.15, 0.12, 0.1, 0.9)
		style_normal.set_border_width_all(2)
		style_normal.border_color = Color(0.4, 0.35, 0.25)
		style_normal.set_corner_radius_all(2)

	if style_hover == null:
		style_hover = StyleBoxFlat.new()
		style_hover.bg_color = Color(0.25, 0.2, 0.15, 0.95)
		style_hover.set_border_width_all(2)
		style_hover.border_color = Color(0.85, 0.75, 0.45)
		style_hover.set_corner_radius_all(2)

	add_theme_stylebox_override("panel", style_normal)


## Sets the item in this slot
func set_item(new_item: Item) -> void:
	item = new_item
	if item != null:
		item.slot_index = slot_index
	refresh_display()


## Clears the item
func clear_item() -> void:
	item = null
	refresh_display()


## Returns true if empty
func is_empty() -> bool:
	return item == null


## Updates visuals
func refresh_display() -> void:
	if not is_node_ready():
		return

	if item == null:
		icon_rect.texture = null
		quantity_label.text = ""
	else:
		icon_rect.texture = item.icon
		if item.stackable and item.quantity > 1:
			quantity_label.text = str(item.quantity)
		else:
			quantity_label.text = ""

	_update_style()


## Hover state
func set_hovered(hovered: bool) -> void:
	is_hovered = hovered
	_update_style()


## Selected state
func set_selected(selected: bool) -> void:
	is_selected = selected
	_update_style()


## Updates style
func _update_style() -> void:
	if style_normal == null or style_hover == null:
		return

	if is_selected:
		modulate = Color(1.0, 1.0, 0.7)
		add_theme_stylebox_override("panel", style_hover)
	elif is_hovered:
		modulate = Color(1.0, 1.0, 1.0)
		add_theme_stylebox_override("panel", style_hover)
	else:
		modulate = Color(1.0, 1.0, 1.0)
		add_theme_stylebox_override("panel", style_normal)


## Input handling
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			slot_clicked.emit(self)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			slot_right_clicked.emit(self)


## Mouse enter
func _on_mouse_entered() -> void:
	set_hovered(true)
	slot_hovered.emit(self)


## Mouse exit
func _on_mouse_exited() -> void:
	set_hovered(false)
	slot_unhovered.emit(self)
