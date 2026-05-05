# base item resource — all items in the game inherit from this class
# saved as a Resource so items can be created as .tres files in the editor
extends Resource
class_name Item

# --- item type enum ---
# determines how the item behaves when used from inventory or hotbar
enum Type {
	CONSUMABLE, # potions, food — used on self for instant effect
	WEAPON,     # swords, bows — equippable combat items
	ARMOR,      # chest, helmet — equippable defense items
	MATERIAL,   # crafting ingredients, quest drops
	QUEST       # quest items — cannot be dropped or traded
}

# --- exported properties ---
# all properties are exported so items can be configured in the Godot editor

# the display name shown in tooltips and inventory
@export var name: String = ""

# short description shown in the item tooltip
@export var description: String = ""

# the icon texture displayed in the inventory slot
@export var icon: Texture2D = null

# whether this item can stack with others of the same type in one slot
@export var stackable: bool = false

# current quantity in this stack — starts at 1
@export var quantity: int = 1

# maximum number that can fit in a single stack
@export var max_stack: int = 99

# gold value of this item — used by shops and trading
@export var value: int = 0

# rarity tier — 1 is common, higher numbers are rarer
# used for color coding and drop rate calculations
@export var tier: int = 1

# minimum character level required to use or equip this item
@export var required_level: int = 1

# which inventory slot this item currently occupies
# -1 means the item is not in any inventory slot
@export var slot_index: int = -1

# the item type — determines behavior when used
@export var type: Type = Type.MATERIAL

# --- constructor ---

# suppress warning about parameter names shadowing class variables
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
	# assign all properties from constructor arguments
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

func can_stack_with(other: Item) -> bool:
	# items can only stack if both are stackable and same name and tier
	if not stackable or other == null:
		return false

	# name and tier must match exactly to stack together
	return name == other.name and tier == other.tier

func add_to_stack(amount: int) -> int:
	# non-stackable items cannot receive additional quantity
	if not stackable:
		return amount

	# calculate how much space is available in this stack
	var space_available = max_stack - quantity

	# add as much as possible without exceeding max stack size
	var to_add = min(amount, space_available)
	quantity += to_add

	# return leftover amount that didn't fit — 0 means everything fit
	return amount - to_add

func duplicate_item() -> Item:
	# create a fresh copy of this item for inventory operations
	# slot_index is reset to -1 since the copy has no slot yet
	var new_item = Item.new(
		name, description, icon, stackable,
		max_stack, value, tier, required_level, -1, type
	)

	# copy the current stack quantity to the duplicate
	new_item.quantity = quantity

	return new_item
