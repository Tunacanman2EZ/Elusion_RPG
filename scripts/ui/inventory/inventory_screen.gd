## Main inventory UI controller.[br]
## Manages the inventory display, player data syncing, and user interactions.[br]
## Supports dragging and remembers position between opens.
extends Control
class_name InventoryScreen

## Emitted when the close button is pressed
signal close_requested()

## Reference to the main panel (for dragging)
@onready var main_panel: PanelContainer = $MainPanel
## Reference to the header panel (drag handle)
@onready var header_panel: PanelContainer = $MainPanel/MarginContainer/VBoxContainer/HeaderPanel
## Reference to close button
@onready var close_button: Button = $MainPanel/MarginContainer/VBoxContainer/HeaderPanel/HBoxContainer/CloseButton
## Reference to the inventory container
@onready var inventory_container: InventoryContainer = %InventoryContainer
## Reference to gold display label
@onready var gold_label: Label = $MainPanel/MarginContainer/VBoxContainer/CurrencyPanel/CurrencyHBox/GoldContainer/GoldLabel
## Reference to lusions display label
@onready var lusions_label: Label = $MainPanel/MarginContainer/VBoxContainer/CurrencyPanel/CurrencyHBox/LusionsContainer/LusionsLabel

## Tooltip panel references
@onready var item_tooltip: PanelContainer = %ItemTooltip
@onready var tooltip_icon: TextureRect = %TooltipIcon
@onready var tooltip_name: Label = %TooltipName
@onready var tooltip_description: Label = %TooltipDescription
@onready var tooltip_value: Label = %TooltipValue
@onready var tooltip_tier: Label = %TooltipTier
@onready var tooltip_level: Label = %TooltipLevel
@onready var stats_container: VBoxContainer = %StatsContainer

## Currently active player reference
var current_player: Node = null
## Currently selected slot (for actions)
var selected_slot: InventorySlot = null

## Padding between tooltip and mouse cursor
const TOOLTIP_PADDING := 12.0

## Dragging state
var _is_dragging := false
var _drag_offset := Vector2.ZERO

## Static position memory (persists between opens)
static var _last_position: Vector2 = Vector2(-1, -1)
static var _has_saved_position := false


func _ready() -> void:
	if inventory_container:
		inventory_container.slot_clicked.connect(_on_slot_clicked)
		inventory_container.slot_right_clicked.connect(_on_slot_right_clicked)
		inventory_container.slot_hovered.connect(_on_slot_hovered)
		inventory_container.slot_unhovered.connect(_on_slot_unhovered)
		inventory_container.inventory_changed.connect(_on_inventory_changed)
	
	# Connect close button
	if close_button:
		close_button.pressed.connect(_on_close_button_pressed)
	
	# Connect header for dragging
	if header_panel:
		header_panel.gui_input.connect(_on_header_gui_input)
	
	# Restore last position if saved
	if _has_saved_position and main_panel:
		main_panel.position = _last_position


func _process(_delta: float) -> void:
	# Update tooltip position to follow mouse
	if item_tooltip and item_tooltip.visible:
		_update_tooltip_position()
	
	# Handle dragging
	if _is_dragging and main_panel:
		main_panel.global_position = get_global_mouse_position() - _drag_offset
		_save_position()


#region Dragging and Close

## Handles input on the header panel for dragging
func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_dragging = true
				_drag_offset = get_global_mouse_position() - main_panel.global_position
			else:
				_is_dragging = false
				_save_position()


## Saves the current panel position
func _save_position() -> void:
	if main_panel:
		_last_position = main_panel.position
		_has_saved_position = true


## Handles close button press
func _on_close_button_pressed() -> void:
	close_requested.emit()

#endregion


#region Tooltip Methods

## Shows the tooltip for the given item at the current mouse position.
func _show_tooltip(item: Item) -> void:
	if item_tooltip == null or item == null:
		return
	
	# Set tooltip content
	tooltip_icon.texture = item.icon
	tooltip_name.text = item.name
	tooltip_description.text = item.description if item.description else "No description."
	tooltip_value.text = str(item.value)
	tooltip_tier.text = _get_tier_name(item.tier)
	tooltip_level.text = str(item.required_level)
	
	# Color the name based on tier
	tooltip_name.add_theme_color_override("font_color", _get_tier_color(item.tier))
	
	# Show the tooltip
	item_tooltip.visible = true
	_update_tooltip_position()


## Hides the tooltip.
func _hide_tooltip() -> void:
	if item_tooltip:
		item_tooltip.visible = false


## Updates the tooltip position based on mouse quadrant.[br]
## Tooltip appears in the opposite quadrant from the mouse to avoid overlap.
func _update_tooltip_position() -> void:
	var mouse_pos = get_global_mouse_position()
	var tooltip_size = item_tooltip.size
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


## Returns a display name for the tier level.
func _get_tier_name(tier: int) -> String:
	match tier:
		1: return "Common"
		2: return "Uncommon"
		3: return "Rare"
		4: return "Epic"
		5: return "Legendary"
		_: return "Tier %d" % tier


## Returns a color for the tier level.
func _get_tier_color(tier: int) -> Color:
	match tier:
		1: return Color(0.85, 0.82, 0.75, 1.0)
		2: return Color(0.4, 0.85, 0.4, 1.0)
		3: return Color(0.4, 0.6, 1.0, 1.0)
		4: return Color(0.7, 0.4, 1.0, 1.0)
		5: return Color(1.0, 0.65, 0.2, 1.0)
		_: return Color(1.0, 0.9, 0.6, 1.0)

#endregion


#region Player Setup

## Sets up the inventory screen for a player.[br]
## Loads the player's inventory and updates currency display.
func setup_for_player(player: Node, _slot_idx: int = 0) -> void:
	current_player = player
	
	if not inventory_container:
		push_error("InventoryScreen: No InventoryContainer found!")
		return
	
	_sync_player_inventory_to_container()
	_update_currency_display()


## Refreshes the display for the current player.
func update_for_player(player: Node, slot_idx: int = 0) -> void:
	setup_for_player(player, slot_idx)


## Syncs the player's inventory array to the InventoryContainer.
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


## Creates an Item resource from a legacy dictionary format.
func _create_item_from_dict(dict: Dictionary) -> Item:
	var item = Item.new()
	item.name = dict.get("name", "Unknown")
	item.description = dict.get("description", "")
	item.stackable = dict.has("count") or dict.get("stackable", false)
	item.quantity = dict.get("count", 1)
	item.value = dict.get("value", 0)
	item.tier = dict.get("tier", 1)
	return item


## Gets the player's raw inventory array.
func _get_player_inventory_array() -> Array:
	if current_player == null:
		return []
	
	var inv = current_player.get("inventory")
	if inv == null:
		return []
	
	if typeof(inv) == TYPE_ARRAY:
		return inv
	elif typeof(inv) == TYPE_OBJECT:
		if inv.has_method("get_all_items"):
			return inv.get_all_items()
		if "items" in inv:
			return inv.items
	return []


## Syncs changes back to the player's inventory array.
func _sync_container_to_player_inventory() -> void:
	if current_player == null:
		return
	
	var items = inventory_container.get_all_items()
	current_player.inventory = items


## Updates the currency display labels with player data.
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


#region Add Item Methods

## Adds an item to the inventory (first available slot).
func add_item(item: Item) -> bool:
	if inventory_container == null:
		return false
	var result = inventory_container.add_item(item)
	if result:
		_sync_container_to_player_inventory()
	return result


## Adds an item to a specific slot index.
func add_item_at(index: int, item: Item) -> bool:
	if inventory_container == null:
		return false
	var result = inventory_container.add_item_at(index, item)
	if result:
		_sync_container_to_player_inventory()
	return result


## Adds an item by name (creates a basic stackable Item resource).
func loot_item(player: Node, item_name: String) -> void:
	current_player = player
	var item = Item.new()
	item.name = item_name
	item.stackable = true
	item.quantity = 1
	
	if inventory_container.add_item(item):
		_sync_container_to_player_inventory()
		print("Looted: %s" % item_name)
	else:
		print("Inventory full! Cannot loot: %s" % item_name)

#endregion


#region Remove Item Methods

## Removes the item at the specified slot index.
func remove_item_at(index: int) -> Item:
	if inventory_container == null:
		return null
	var result = inventory_container.remove_item_at(index)
	if result:
		_sync_container_to_player_inventory()
	return result


## Removes the first occurrence of a matching item.
func remove_item(item: Item) -> Item:
	if inventory_container == null:
		return null
	var result = inventory_container.remove_item(item)
	if result:
		_sync_container_to_player_inventory()
	return result


## Removes a specific quantity from the slot at the given index.
func remove_quantity_at(index: int, amount: int) -> int:
	if inventory_container == null:
		return 0
	var result = inventory_container.remove_quantity_at(index, amount)
	if result > 0:
		_sync_container_to_player_inventory()
	return result


## Removes a specific quantity of a matching item from any slots.
func remove_quantity(item: Item, amount: int) -> int:
	if inventory_container == null:
		return 0
	var result = inventory_container.remove_quantity(item, amount)
	if result > 0:
		_sync_container_to_player_inventory()
	return result

#endregion


#region Slot Interaction Handlers

## Handles left-click on a slot.
func _on_slot_clicked(slot: InventorySlot) -> void:
	if slot.is_empty():
		_deselect_slot()
		return
	
	if selected_slot == slot:
		_use_item(slot)
		_deselect_slot()
	else:
		_select_slot(slot)


## Handles right-click on a slot.
func _on_slot_right_clicked(slot: InventorySlot) -> void:
	if slot.is_empty():
		return
	print("Right-clicked: %s" % slot.item.name)


## Handles mouse entering a slot (shows tooltip).
func _on_slot_hovered(slot: InventorySlot) -> void:
	if not slot.is_empty():
		_show_tooltip(slot.item)


## Handles mouse exiting a slot (hides tooltip).
func _on_slot_unhovered(_slot: InventorySlot) -> void:
	_hide_tooltip()


## Handles inventory content changes.
func _on_inventory_changed() -> void:
	_sync_container_to_player_inventory()


## Selects a slot and applies visual feedback.
func _select_slot(slot: InventorySlot) -> void:
	if selected_slot:
		selected_slot.set_selected(false)
	selected_slot = slot
	selected_slot.set_selected(true)


## Deselects the currently selected slot.
func _deselect_slot() -> void:
	if selected_slot:
		selected_slot.set_selected(false)
	selected_slot = null


## Uses the item in the given slot.
func _use_item(slot: InventorySlot) -> void:
	if slot.is_empty():
		return
	
	var item = slot.item
	var item_name = item.name
	
	if item_name == "Test Potion":
		if current_player and current_player.has_method("heal"):
			current_player.heal(20)
			print("Test Potion used! Player healed for 20 HP.")
		
		inventory_container.remove_quantity_at(slot.slot_index, 1)
	else:
		print("%s is not usable." % item_name)

#endregion

