# itemstack.gd — represents a single instance of an item in inventory.
# holds a reference to ItemData (the shared type definition) plus per-instance
# state like quantity.
#
# example: when you have 5 health potions in a slot, that's ONE ItemStack
# with quantity=5 referencing ONE shared ItemData. ten different inventory
# slots holding healthpotions all point to the SAME ItemData resource.
#
# rules:
# - do NOT modify ItemData fields through a stack — those are the type
# - only mutate quantity (and future per-instance state like durability)
# - duplicate_stack() shares the data reference, copies only the instance state
#
# save format:
# stacks serialize as {"item_id": "...", "quantity": N}. on load, the item_id
# rehydrates back into a full ItemData reference via ItemRegistry. this keeps
# save files small and resilient to balance changes (max_stack, value, etc.).
extends Resource
class_name ItemStack


# =============================================================================
# STATE
# =============================================================================

# the type of item this stack contains — points to a shared ItemData
# loaded from the registry. multiple stacks can reference the same data.
@export var data: ItemData = null

# how many items are in this stack. always respects data.max_stack on adds.
# always 1 for non-stackable items.
@export var quantity: int = 1


# =============================================================================
# CONSTRUCTOR
# =============================================================================

func _init(p_data: ItemData = null, p_quantity: int = 1) -> void:
	# optional-arg constructor — supports both .new() and .new(data, qty).
	# editor-loaded stacks bypass this and set fields directly.
	data = p_data
	quantity = p_quantity


# =============================================================================
# VALIDITY CHECKS
# =============================================================================

func is_valid() -> bool:
	# a stack is valid when it has data AND quantity is at least 1.
	# invalid stacks should be treated as "empty slot" by inventory UI.
	return data != null and quantity > 0


func is_full() -> bool:
	# returns true when this stack cannot accept any more items.
	# non-stackable items are always "full" — they don't merge.
	if not is_valid():
		return false
	if not data.stackable:
		return true
	return quantity >= data.max_stack


func is_empty() -> bool:
	# returns true when this stack has no items.
	# treated equivalently to invalid — slots use this to decide what to render.
	return not is_valid() or quantity <= 0


# =============================================================================
# STACKING
# =============================================================================

func can_stack_with(other: ItemStack) -> bool:
	# returns true if `other` can merge into this stack. requires:
	# - both stacks valid
	# - this stack's ItemData is marked stackable
	# - same item_id (same item type)
	#
	# we compare by item_id rather than data reference equality because two
	# .tres files could theoretically have the same id (registry rejects this,
	# but defense-in-depth is cheap here).
	if not is_valid() or other == null or not other.is_valid():
		return false
	if not data.stackable:
		return false
	return data.item_id == other.data.item_id


func add_to_stack(amount: int) -> int:
	# add quantity to this stack up to data.max_stack.
	# returns leftover that didn't fit (0 if everything fit).
	# non-stackable items reject all additions and return the full amount.
	if not is_valid() or amount <= 0:
		return amount
	if not data.stackable:
		return amount

	var space_available: int = data.max_stack - quantity
	var to_add: int = min(amount, space_available)
	quantity += to_add
	return amount - to_add


func remove_quantity(amount: int) -> int:
	# remove up to `amount` items from this stack.
	# returns how much was actually removed (may be less if stack had fewer).
	# clamps at zero — never goes negative.
	if not is_valid() or amount <= 0:
		return 0

	var to_remove: int = min(amount, quantity)
	quantity -= to_remove
	return to_remove


# =============================================================================
# DUPLICATION
# =============================================================================

func duplicate_stack() -> ItemStack:
	# create an independent copy of this stack.
	# the data reference is SHARED (not copied) — type definition is global,
	# every stack of a given item points at the same ItemData resource.
	# only the per-instance state (quantity) is copied.
	#
	# used by inventory ops that need a working copy without mutating the
	# original (add_stack, sort_by_name, etc.).
	var copy: ItemStack = ItemStack.new()
	copy.data = data  # shared reference — intentional
	copy.quantity = quantity
	return copy


# =============================================================================
# SAVE / LOAD
# =============================================================================
# saves only item_id + quantity, NOT the full ItemData. on load, the item_id
# rehydrates back into a full ItemData via ItemRegistry. this keeps save
# files small and resilient: if you later change max_stack or value on an
# ItemData, existing saves automatically use the new values.

func to_dict() -> Dictionary:
	# serialize this stack to a save-friendly dictionary.
	# empty dict represents an invalid/empty stack — slots use null instead.
	if not is_valid():
		return {}
	return {
		"item_id":  data.item_id,
		"quantity": int(quantity),
	}


static func from_dict(dict: Dictionary) -> ItemStack:
	# deserialize a stack from a saved dictionary.
	# returns null if the dict is malformed OR if item_id isn't in the registry
	# (e.g., an item was renamed or deleted between save and load).
	# the registry already pushed a warning about the unknown id, so we just
	# return null and let the caller treat the slot as empty.
	if not dict.has("item_id") or not dict.has("quantity"):
		return null

	var item_id: String = dict["item_id"]
	var item_data: ItemData = ItemRegistry.get_item(item_id)
	if item_data == null:
		return null

	var stack: ItemStack = ItemStack.new()
	stack.data = item_data
	stack.quantity = int(dict["quantity"])
	return stack
