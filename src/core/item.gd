extends Resource
class_name Item

enum Type { CONSUMABLE, WEAPON, ARMOR, MATERIAL, QUEST }

## The display name of the item
@export var name: String = ""
## A brief description shown in tooltips
@export var description: String = ""
## The icon texture displayed in inventory slots
@export var icon: Texture2D = null
## Whether multiple of this item can occupy the same slot
@export var stackable: bool = false
## Current quantity of items in this stack
@export var quantity: int = 1
## Maximum number of items that can be stacked in one slot
@export var max_stack: int = 99
## Base value of the item
@export var value: int = 0
## Item tier/rarity level (1 = common, higher = rarer)
@export var tier: int = 1
## Minimum character level required to use this item
@export var required_level: int = 1
## The slot index this item occupies in the inventory (-1 if not in inventory)
@export var slot_index: int = -1
## Item type — determines how it behaves when used
@export var type: Type = Type.MATERIAL

@warning_ignore("shadowed_variable")
func _init(
	name: String = "",
	description: String = "",
	icon: Texture2D = null,
	stackable: bool = false,
	max_stack: int = 99,
	value: int = 0,
	tier: int = 1,
	required_level: int = 1,
	slot_index: int = -1,
	type: Type = Type.MATERIAL
) -> void:
	self.name = name
	self.description = description
	self.icon = icon
	self.stackable = stackable
	self.max_stack = max_stack
	self.value = value
	self.tier = tier
	self.required_level = required_level
	self.slot_index = slot_index
	self.type = type

## Returns true if this item can stack with another item.
func can_stack_with(other: Item) -> bool:
	if not stackable or other == null:
		return false
	return name == other.name and tier == other.tier

## Attempts to add quantity to this stack.
## Returns the leftover amount that couldn't fit (0 if all fit).
func add_to_stack(amount: int) -> int:
	if not stackable:
		return amount
	var space_available = max_stack - quantity
	var to_add = min(amount, space_available)
	quantity += to_add
	return amount - to_add

## Creates a duplicate of this item for inventory operations.
func duplicate_item() -> Item:
	var new_item = Item.new(
		name, description, icon, stackable,
		max_stack, value, tier, required_level, -1, type
	)
	new_item.quantity = quantity
	return new_item
