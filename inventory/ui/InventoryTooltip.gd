extends PanelContainer
class_name InventoryTooltip

@onready var _name_label: Label = %Name
@onready var _desc_label: Label = %Desc
@onready var _meta_label: Label = %Meta

func show_for_stack(stack: ItemStack) -> void:
	if stack == null or not stack.is_valid():
		hide()
		return

	var it := stack.item_type
	_name_label.text = it.get_display_name()
	_desc_label.text = it.description
	_meta_label.text = "Qty: %s  Value: %s  Weight: %s" % [str(stack.quantity), str(it.value), str(it.weight)]
	show()

func hide_tooltip() -> void:
	hide()


