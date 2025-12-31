extends PanelContainer
class_name InventorySlotView

signal hovered(stack: ItemStack, global_pos: Vector2)
signal unhovered()
signal inventory_mutated()

@onready var _icon: TextureRect = %Icon
@onready var _qty: Label = %Qty

var index: int = -1
var inventory: Inventory
var grabbed_preview_scene: PackedScene

func _ready() -> void:
	_refresh()

func bind(inv: Inventory, idx: int, preview_scene: PackedScene) -> void:
	inventory = inv
	index = idx
	grabbed_preview_scene = preview_scene
	_refresh()

func _refresh() -> void:
	if not is_node_ready():
		return
	var stack := inventory.get_stack(index) if inventory != null else null
	if stack == null or not stack.is_valid():
		_icon.texture = null
		_qty.text = ""
		return
	_icon.texture = stack.item_type.icon
	_qty.text = str(stack.quantity) if stack.quantity > 1 else ""

func _get_drag_data(_at_position: Vector2) -> Variant:
	if inventory == null:
		return null
	var stack := inventory.get_stack(index)
	if stack == null:
		return null

	var data := {
		"from_inventory": inventory,
		"from_index": index,
	}

	if grabbed_preview_scene != null:
		var preview := grabbed_preview_scene.instantiate()
		if preview is GrabbedItemStackView:
			(preview as GrabbedItemStackView).set_stack(stack)
		set_drag_preview(preview)

	return data

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if inventory == null:
		return false
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if not data.has("from_inventory") or not data.has("from_index"):
		return false
	var from_inv: Inventory = data["from_inventory"]
	var from_idx: int = data["from_index"]
	if from_inv == null:
		return false
	var from_stack := from_inv.get_stack(from_idx)
	if from_stack == null:
		return false
	# Restriction check.
	return inventory.can_accept_stack(from_stack)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if inventory == null:
		return
	if typeof(data) != TYPE_DICTIONARY:
		return
	var from_inv: Inventory = data.get("from_inventory", null)
	var from_idx: int = data.get("from_index", -1)
	if from_inv == null or from_idx < 0:
		return

	var changed := false
	if from_inv == inventory:
		changed = inventory.move_within(from_idx, index)
	else:
		changed = from_inv.try_transfer_to(inventory, from_idx, index)

	if changed:
		inventory_mutated.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		if inventory != null:
			hovered.emit(inventory.get_stack(index), get_global_mouse_position())
	if what == NOTIFICATION_MOUSE_EXIT:
		unhovered.emit()
