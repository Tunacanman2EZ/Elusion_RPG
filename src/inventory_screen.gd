extends Control
class_name InventoryManager

signal close_requested()

@onready var main_panel: PanelContainer = $MainPanel
@onready var header_panel: PanelContainer = $MainPanel/MarginContainer/VBoxContainer/HeaderPanel
@onready var close_button: Button = $MainPanel/MarginContainer/VBoxContainer/HeaderPanel/HBoxContainer/CloseButton
@onready var inventory_container: InventoryContainer = %InventoryContainer
@onready var gold_label: Label = $MainPanel/MarginContainer/VBoxContainer/CurrencyPanel/CurrencyHBox/GoldContainer/GoldLabel
@onready var lusions_label: Label = $MainPanel/MarginContainer/VBoxContainer/CurrencyPanel/CurrencyHBox/LusionsContainer/LusionsLabel

@onready var item_tooltip: PanelContainer = %ItemTooltip
@onready var tooltip_icon: TextureRect = %TooltipIcon
@onready var tooltip_name: Label = %TooltipName
@onready var tooltip_description: Label = %TooltipDescription
@onready var tooltip_value: Label = %TooltipValue
@onready var tooltip_tier: Label = %TooltipTier
@onready var tooltip_level: Label = %TooltipLevel
@onready var stats_container: VBoxContainer = %StatsContainer

var current_player: Node = null
var selected_slot: InventorySlot = null

const TOOLTIP_PADDING := 12.0

var _is_dragging := false
var _drag_offset := Vector2.ZERO

static var _last_position: Vector2 = Vector2(-1, -1)
static var _has_saved_position := false


func _ready() -> void:
	if inventory_container:
		inventory_container.slot_clicked.connect(_on_slot_clicked)
		inventory_container.slot_right_clicked.connect(_on_slot_right_clicked)
		inventory_container.slot_hovered.connect(_on_slot_hovered)
		inventory_container.slot_unhovered.connect(_on_slot_unhovered)
		inventory_container.inventory_changed.connect(_on_inventory_changed)

	if close_button:
		close_button.pressed.connect(_on_close_button_pressed)

	if header_panel:
		header_panel.gui_input.connect(_on_header_gui_input)

	if _has_saved_position and main_panel:
		main_panel.global_position = _last_position


func _process(_delta: float) -> void:
	if item_tooltip and item_tooltip.visible:
		_update_tooltip_position()

	# Dragging
	if _is_dragging and main_panel:
		main_panel.global_position = get_global_mouse_position() - _drag_offset
		_save_position()

	# Fix stuck dragging
	if _is_dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_is_dragging = false
		_save_position()


#region Dragging

func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_dragging = true
			_drag_offset = get_global_mouse_position() - main_panel.global_position
		else:
			_is_dragging = false
			_save_position()


func _save_position() -> void:
	if main_panel:
		_last_position = main_panel.global_position
		_has_saved_position = true


func _on_close_button_pressed() -> void:
	close_requested.emit()

#endregion


#region Tooltip

func _show_tooltip(item: Item) -> void:
	if item_tooltip == null or item == null:
		return

	tooltip_icon.texture = item.icon
	tooltip_name.text = item.name
	tooltip_description.text = item.description if item.description != "" else "No description."
	tooltip_value.text = str(item.value)
	tooltip_tier.text = _get_tier_name(item.tier)
	tooltip_level.text = str(item.required_level)

	# Fix color stacking
	tooltip_name.remove_theme_color_override("font_color")
	tooltip_name.add_theme_color_override("font_color", _get_tier_color(item.tier))

	item_tooltip.visible = true

	await get_tree().process_frame
	_update_tooltip_position()


func _hide_tooltip() -> void:
	if item_tooltip:
		item_tooltip.visible = false


func _update_tooltip_position() -> void:
	var mouse_pos = get_global_mouse_position()
	var tooltip_size = item_tooltip.get_combined_minimum_size()
	var viewport_size = get_viewport_rect().size
	var viewport_center = viewport_size / 2.0

	var pos := Vector2.ZERO

	if mouse_pos.x > viewport_center.x:
		pos.x = mouse_pos.x - tooltip_size.x - TOOLTIP_PADDING
	else:
		pos.x = mouse_pos.x + TOOLTIP_PADDING

	if mouse_pos.y > viewport_center.y:
		pos.y = mouse_pos.y - tooltip_size.y - TOOLTIP_PADDING
	else:
		pos.y = mouse_pos.y + TOOLTIP_PADDING

	pos.x = clamp(pos.x, 0, viewport_size.x - tooltip_size.x)
	pos.y = clamp(pos.y, 0, viewport_size.y - tooltip_size.y)

	item_tooltip.global_position = pos


func _get_tier_name(tier: int) -> String:
	match tier:
		1: return "Common"
		2: return "Uncommon"
		3: return "Rare"
		4: return "Epic"
		5: return "Legendary"
		_: return "Tier %d" % tier


func _get_tier_color(tier: int) -> Color:
	match tier:
		1: return Color(0.85, 0.82, 0.75)
		2: return Color(0.4, 0.85, 0.4)
		3: return Color(0.4, 0.6, 1.0)
		4: return Color(0.7, 0.4, 1.0)
		5: return Color(1.0, 0.65, 0.2)
		_: return Color(1.0, 0.9, 0.6)

#endregion


#region Player

func setup_for_player(player: Node, _slot_idx: int = 0) -> void:
	current_player = player

	if not inventory_container:
		push_error("InventoryScreen: No InventoryContainer found!")
		return

	_sync_player_inventory_to_container()
	_update_currency_display()


func update_for_player(player: Node, slot_idx: int = 0) -> void:
	setup_for_player(player, slot_idx)


func _sync_player_inventory_to_container() -> void:
	if current_player == null:
		return

	inventory_container.clear_inventory()

	var player_inv = _get_player_inventory_array()
	for item_data in player_inv:
		if item_data == null:
			continue

		if item_data is Item:
			inventory_container.add_item(item_data)
		elif item_data is Dictionary and "name" in item_data:
			var item = _create_item_from_dict(item_data)
			if item:
				inventory_container.add_item(item)


func _create_item_from_dict(dict: Dictionary) -> Item:
	var item = Item.new()
	item.name = dict.get("name", "Unknown")
	item.description = dict.get("description", "")
	item.stackable = dict.has("count") or dict.get("stackable", false)
	item.quantity = dict.get("count", 1)
	item.value = dict.get("value", 0)
	item.tier = dict.get("tier", 1)
	return item


func _get_player_inventory_array() -> Array:
	if current_player == null:
		return []

	var inv = current_player.get("inventory")
	if inv == null:
		return []

	if inv is Array:
		return inv
	elif inv is Object:
		if inv.has_method("get_all_items"):
			return inv.get_all_items()
		if "items" in inv:
			return inv.items

	return []


func _sync_container_to_player_inventory() -> void:
	if current_player == null:
		return

	var items = inventory_container.get_all_items()

	if current_player.get("inventory") is Array:
		current_player.inventory = items
	elif current_player.inventory and current_player.inventory.has_method("set_items"):
		current_player.inventory.set_items(items)


func _update_currency_display() -> void:
	if current_player == null:
		return

	if gold_label:
		var gold = current_player.get("gold")
		if gold != null:
			gold_label.text = "Gold: %d" % gold

	if lusions_label:
		var lusions = current_player.get("lusions")
		if lusions != null:
			lusions_label.text = "Lusions: %d" % lusions

#endregion


#region Slot Interaction

func _on_slot_clicked(slot: InventorySlot) -> void:
	if slot.is_empty():
		_deselect_slot()
		return

	if selected_slot == slot:
		_use_item(slot)
		_deselect_slot()
	else:
		_select_slot(slot)


func _on_slot_right_clicked(slot: InventorySlot) -> void:
	if slot.is_empty():
		return
	print("Right-clicked: %s" % slot.item.name)


func _on_slot_hovered(slot: InventorySlot) -> void:
	if not slot.is_empty():
		_show_tooltip(slot.item)


func _on_slot_unhovered(_slot: InventorySlot) -> void:
	_hide_tooltip()


func _on_inventory_changed() -> void:
	_sync_container_to_player_inventory()


func _select_slot(slot: InventorySlot) -> void:
	if selected_slot:
		selected_slot.set_selected(false)
	selected_slot = slot
	selected_slot.set_selected(true)


func _deselect_slot() -> void:
	if selected_slot:
		selected_slot.set_selected(false)
	selected_slot = null


func _use_item(slot: InventorySlot) -> void:
	if slot.is_empty() or slot.item == null:
		return

	var item = slot.item

	if item.name == "Test Potion":
		if current_player and current_player.has_method("heal"):
			current_player.heal(20)
			print("Test Potion used!")

		inventory_container.remove_quantity_at(slot.slot_index, 1)
	else:
		print("%s is not usable." % item.name)

#endregion
