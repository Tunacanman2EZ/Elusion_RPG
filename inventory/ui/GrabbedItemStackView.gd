extends Control
class_name GrabbedItemStackView

@onready var _icon: TextureRect = %Icon
@onready var _qty: Label = %Qty

func set_stack(stack: ItemStack) -> void:
	if not is_node_ready():
		await ready
	if stack == null or not stack.is_valid():
		_icon.texture = null
		_qty.text = ""
		return
	_icon.texture = stack.item_type.icon
	_qty.text = str(stack.quantity) if stack.quantity > 1 else ""


