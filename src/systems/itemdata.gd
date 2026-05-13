# itemdata.gd — defines a TYPE of item (e.g. "iron sword", "health potion")
# one .tres file per item kind, lives in res://data/items/
# this is the shared, immutable definition — every iron sword in the game
# references the same ItemData. instance state (quantity, durability, etc.)
# lives in ItemStack, not here.
extends Resource
class_name ItemData

# --- item type enum ---
# determines how the item behaves when used from inventory or hotbar
enum Type {
	CONSUMABLE,  # potions, food — used on self for instant effect
	WEAPON,      # swords, bows — equippable combat items
	ARMOR,       # chest, helmet — equippable defense items
	MATERIAL,    # crafting ingredients, quest drops
	QUEST,       # quest items — cannot be dropped or traded
}

# --- exported properties ---
# all set in the Godot editor when creating .tres files

# unique identifier for this item type — used by save files and the registry
# must be unique across all items. use lowercase_with_underscores.
# examples: "iron_sword", "health_potion_minor", "quest_amulet_of_ages"
@export var item_id: String = ""

# the display name shown in tooltips and inventory
@export var display_name: String = ""

# short description shown in the item tooltip
@export var description: String = ""

# the icon texture displayed in the inventory slot
@export var icon: Texture2D = null

# whether this item type can stack with others of the same type in one slot
@export var stackable: bool = false

# maximum number that can fit in a single stack
@export var max_stack: int = 99

# gold value of this item — used by shops and trading
@export var value: int = 0

# rarity tier — 1 is common, higher numbers are rarer
# used for color coding and drop rate calculations
@export var tier: int = 1

# minimum character level required to use or equip this item
@export var required_level: int = 1

# how much health this item restores when used as a consumable.
# only meaningful for items where type == Type.CONSUMABLE.
# 0 means non-healing item.
@export var restore_amount: int = 0

# the item type — determines behavior when used
@export var type: Type = Type.MATERIAL
