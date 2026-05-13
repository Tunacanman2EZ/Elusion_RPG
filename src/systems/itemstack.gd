# itemstack.gd — represents a single instance of an item in inventory
# holds a reference to ItemData (the shared type definition) plus per-instance
# state like quantity. when you have 5 health potions in a slot, that's
# ONE ItemStack with quantity=5 referencing ONE shared ItemData.
#
# do not modify ItemData fields through a stack — those are the type.
# only mutate quantity (and future per-instance state like durability).
extends Resource
class_name ItemStack

# the type of item this stack contains — points to a shared ItemData
# loaded from the registry. multiple stacks can reference the same data.
@export var data: ItemData = null

# how many items are in this stack — must respect data.max_stack
# always 1 for non-stackable items
@export var quantity: int = 1

func _init(p_data: ItemData = null, p_quantity: int = 1) -> void:
	# constructor with optional args — supports both .new() and .new(data, qty)
	data = p_data
	quantity = p_quantity

func is_valid() -> bool:
	# a stack is valid if it has data and quantity is at least 1
	return data != null and quantity > 0

func can_stack_with(other: ItemStack) -> bool:
	# two stacks can merge if they're both valid, both stackable,
	# and reference the same ItemData (same item_id)
	if not is_valid() or other == null or not other.is_valid():
		return false
	if not data.stackable:
		return false
	# same data reference OR same item_id — both work, item_id is safer
	# in case duplicate ItemData resources somehow exist
	return data.item_id == other.data.item_id

func add_to_stack(amount: int) -> int:
	# add quantity to this stack up to the data's max_stack limit.
	# returns the leftover that didn't fit (0 if everything fit).
	# non-stackable items reject all additions.
	if not is_valid() or amount <= 0:
		return amount
	if not data.stackable:
		return amount

	var space_available: int = data.max_stack - quantity
	var to_add: int = min(amount, space_available)
	quantity += to_add
	return amount - to_add

func remove_quantity(amount: int) -> int:
	# remove up to amount from this stack.
	# returns how much was actually removed.
	# clamps at zero — never goes negative.
	if not is_valid() or amount <= 0:
		return 0

	var to_remove: int = min(amount, quantity)
	quantity -= to_remove
	return to_remove

func is_full() -> bool:
	# returns true when this stack cannot accept any more items
	if not is_valid():
		return false
	if not data.stackable:
		return true  # non-stackable is always "full" at quantity 1
	return quantity >= data.max_stack

func is_empty() -> bool:
	# returns true when this stack has no items
	return not is_valid() or quantity <= 0

func duplicate_stack() -> ItemStack:
	# create an independent copy of this stack.
	# the data reference is SHARED (not copied) — type definition is global.
	# only the per-instance state (quantity) is copied.
	var copy := ItemStack.new()
	copy.data = data  # same reference, intentional
	copy.quantity = quantity
	return copy

# --- save / load helpers ---
# these are the methods the inventory will use to serialize stacks
# to the save file. saves only item_id + quantity, not the full data.

func to_dict() -> Dictionary:
	if not is_valid():
		return {}
	return {
		"item_id": data.item_id,
		"quantity": int(quantity),
	}

static func from_dict(dict: Dictionary) -> ItemStack:
	# deserialize a stack from a saved dictionary.
	# looks up the ItemData via the registry by item_id.
	# returns null if the dict is invalid or item_id isn't in the registry.
	if not dict.has("item_id") or not dict.has("quantity"):
		return null

	var item_id: String = dict["item_id"]
	var item_data: ItemData = ItemRegistry.get_item(item_id)
	if item_data == null:
		# registry already pushed a warning about the unknown id
		return null

	var stack := ItemStack.new()
	stack.data = item_data
	stack.quantity = int(dict["quantity"])
	return stack
