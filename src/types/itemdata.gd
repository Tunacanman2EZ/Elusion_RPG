# itemdata.gd — defines a TYPE of item (e.g. "iron sword", "health potion").
# one .tres file per item kind, lives in res://data/items/.
#
# this is the shared, immutable definition — every iron sword in the game
# references the same ItemData resource. instance state (quantity, the
# specific slot it's in, future durability) lives in ItemStack, not here.
#
# workflow:
# 1. create a new ItemData .tres asset in res://data/items/
# 2. configure properties via the Godot inspector
# 3. ItemRegistry scans the folder on game start, indexes by item_id
# 4. runtime code looks up by id via ItemRegistry.get_item(item_id)
#
# why this is split from ItemStack:
# - ItemData = the "what" of an item (read-only template)
# - ItemStack = the "where" + "how many" (runtime instance)
# saves only store item_id + quantity, hydrated against ItemData on load.
extends Resource
class_name ItemData


# =============================================================================
# ITEM TYPE ENUM
# =============================================================================
# determines how the item behaves when used from inventory or hotbar.
# add new types at the END to preserve integer order.
enum Type {
	CONSUMABLE,  # potions, food — used on self for instant effect
	WEAPON,      # swords, bows — equippable combat items
	ARMOR,       # chest, helmet, amulets — equippable defense items
	MATERIAL,    # crafting ingredients, quest drops
	QUEST,       # quest items — cannot be dropped or traded
	PET,         # companion items — activated to summon a following pet
	CURRENCY,    # gold and lusions — converts to a pool on use/pickup
}


# =============================================================================
# RESTORE TARGET ENUM
# =============================================================================
# for CONSUMABLE items: which resource restore_amount is applied to when used.
# lets the use-handler route restore to the right stat WITHOUT matching
# item_id strings — a new potion just sets Type=CONSUMABLE + a restore_target.
enum RestoreTarget {
	NONE,     # not a restoring consumable (e.g. food that does something else)
	HP,       # health potions
	MANA,     # mana potions
	STAMINA,  # stamina potions
}


# =============================================================================
# IDENTITY
# =============================================================================
# unique identifier for this item type — used by save files and the registry.
# convention: lowercase, no underscores, no spaces, concatenated
# (e.g. "ironsword", "tinyhealthpotion", "smallamountofgold").
@export var item_id: String = ""


# =============================================================================
# DISPLAY
# =============================================================================
# the display name shown in tooltips and inventory
@export var display_name: String = ""

# short description shown in the item tooltip
@export var description: String = ""

# the icon texture displayed in the inventory slot. swappable art layer.
@export var icon: Texture2D = null


# =============================================================================
# STACKING
# =============================================================================
# whether this item type can stack with others of the same type in one slot
@export var stackable: bool = false

# maximum number that can fit in a single stack
@export var max_stack: int = 99


# =============================================================================
# ECONOMY AND PROGRESSION
# =============================================================================
# gold value of this item — used by shops and trading. for CURRENCY items,
# this is the per-pile amount (a stack of 5 piles at value=10 = 50 currency).
@export var value: int = 0

# rarity tier — 1 is common, higher numbers are rarer.
# enemy drop rolls gate by tier: a starter mob can only roll low-tier items.
@export var tier: int = 1

# minimum character level required to use or equip this item
@export var required_level: int = 1


# =============================================================================
# EQUIPMENT
# =============================================================================
# WHICH SLOT THIS OCCUPIES, and the reason Type.ARMOR is not enough on its own.
#
# Type says what an item IS. It cannot say where it goes: boots, a helm, a ring
# and a shield are all Type.ARMOR, so nothing could enforce "one helm AND one
# chest" rather than "two helms". The slot has to be its own axis.
#
# RING IS DELIBERATELY ONE SLOT, not two. Two ring slots is a balance decision
# that doubles the strongest stat stacking in the game, and it is far easier to
# add a second slot later than to take one away from players already wearing it.
enum EquipSlot {
	NONE,     # not equippable — every consumable, material and pet
	WEAPON,
	HELM,
	CHEST,
	LEGS,
	BOOTS,
	SHIELD,
	RING,
	AMULET,
}

@export var equip_slot: EquipSlot = EquipSlot.NONE

# WHICH CLASSES MAY EQUIP THIS. Empty means anyone, which is the right default:
# rings and amulets are shared by everybody.
#
# AN ARRAY, NOT A SINGLE STRING, and that is not over-engineering. Plate is worn
# by the warrior AND the tank; robes by the mage AND the healer. A single string
# cannot express either, which is exactly the wall the first version of this
# field hit the moment armour got split by class.
#
# Strings matching each class resource's own id (warrior / mage / tank /
# healer), NOT an enum, so adding a fifth class is a new .tres in data/classes/
# rather than an edit here plus a migration of every saved item.
@export var required_classes: Array[String] = []

# WHAT AN EQUIPPED WEAPON HITS FOR, before scaling.
#
# Named to slot straight into the hole warrior.gd:21 already describes: "when
# the equipment system is built, base_melee_damage should be replaced by the
# equipped weapon's damage". warrior.gd currently does
#     int(base_melee_damage * get_damage_multiplier())
# with base_melee_damage exported at 20, so a tier 1 sword carrying damage = 20
# reproduces today's balance exactly and the ladder climbs from there.
#
# 0 on anything that is not a weapon, which is every item in the game today
# except the swords. Meaningless until an equipped slot exists - see the note
# on armor_value below, which has the same status.
@export var damage: int = 0

# The defensive mirror of damage, for Type.ARMOR. Nothing wears armour yet and
# there is no armour item, but the field exists so the two halves of equipment
# are designed together rather than one being retrofitted around the other.
@export var armor_value: int = 0


# =============================================================================
# TYPE AND BEHAVIOR
# =============================================================================
# the item type — determines behavior when used
@export var type: Type = Type.MATERIAL

# how much HP/mana/stamina this item restores when used as a consumable.
# only meaningful when type == Type.CONSUMABLE. 0 means non-restoring.
@export var restore_amount: int = 0

# for CONSUMABLE items: which stat restore_amount is applied to. set HP on
# health potions, MANA on mana potions, STAMINA on stamina potions. the
# use-handler routes by this field, so no item_id matching is needed.
@export var restore_target: RestoreTarget = RestoreTarget.NONE


# =============================================================================
# PET (only meaningful when type == Type.PET)
# =============================================================================
# the pet entity scene this item summons when activated. assign the pet's
# .tscn here in the inspector. null for all non-pet items.
@export var pet_scene: PackedScene = null

# which enemy this pet came from — display flair for the future pet-collection
# UI and for organizing pets by source. e.g. "Archer", "Fire Sprite", "Boss".
@export var pet_source_name: String = ""
