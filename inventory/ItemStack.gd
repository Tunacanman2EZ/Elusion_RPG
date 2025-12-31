extends Resource
class_name ItemStack

## Instance data for a stack of an ItemType.

@export var item_type: ItemType
@export_range(1, 9999) var quantity: int = 1
@export var extra_properties: Dictionary = {}

func _init(itm_type: ItemType = null, itm_quantity: int = 1, itm_extra_properties: Dictionary = {}):
	item_type = itm_type
	quantity = max(1, itm_quantity)
	extra_properties = itm_extra_properties.duplicate(true) if itm_extra_properties != null else {}
	if item_type != null and extra_properties.is_empty():
		extra_properties = item_type.default_extra_properties.duplicate(true)

func is_valid() -> bool:
	return item_type != null and quantity > 0

func can_stack_with(other: ItemStack, compare_extras: bool = true) -> bool:
	if other == null:
		return false
	if item_type != other.item_type:
		return false
	return (not compare_extras) or (extra_properties == other.extra_properties)

func duplicate_with_quantity(new_quantity: int) -> ItemStack:
	return ItemStack.new(item_type, max(1, new_quantity), extra_properties.duplicate(true))


