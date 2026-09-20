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

	# RAW FISH. Its own type rather than MATERIAL, and the reason is loot:
	# gamedata.py picks mob drops with pick_weighted_item_id(), which excludes
	# by TYPE NAME and lets every MATERIAL through. Filed as MATERIAL, a tier 8
	# Reef Clown became a legal drop from any high-tier enemy — free from a
	# slime, which is the whole point of the fishing skill handed out for
	# nothing. FISH is in EXCLUDED_FROM_LOOT server-side, so fish come out of
	# water and nowhere else.
	#
	# COOKED fish are NOT this type. They are CONSUMABLE with a restore_target
	# of HP, because that is exactly what they do and the use-handler already
	# knows how to route it. Raw is an ingredient, cooked is food; one type
	# covering both would need the use-handler to ask which it was holding.
	FISH,
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

# Colour multiplied over `icon` wherever it is drawn — the slot, the hotbar and
# the drag preview. WHITE, the default, means "draw the art as authored", so
# every existing item is unaffected and no .tres has to mention this.
#
# WHY IT HAS TO EXIST AT ALL. A pet's colour lives in its SCENE, as a modulate
# on the root: the electric sprite companion is green while the enemy it drops
# from is the untinted blue-grey of the shared sheet. The icon is an
# AtlasTexture pointing into that same sheet, and AtlasTexture carries no
# colour, so the inventory showed the enemy's blue for a pet that is green in
# the world — two pictures of the same creature that disagreed, with nothing
# in either file to say which was right.
#
# Keep this equal to the pet scene's root modulate. They are the same fact
# written twice, which is not ideal, but the alternative is instantiating a
# PackedScene to draw an inventory square.
@export var icon_tint: Color = Color.WHITE


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

# WHICH SKILL, IF ANY, ALSO GATES USING THIS — and why required_level above is
# not enough on its own.
#
# required_level is a CHARACTER level, which is the right axis for something you
# BUY OR FIND. A Greater Health Potion is 260 HP for 600 gold off a vendor
# shelf, and character level is the one thing gold cannot buy — so that is what
# stops a funded level-1 alt drinking it.
#
# It is the WRONG axis for something you MADE. Fishing and cooking are
# independent skills here, with their own XP and their own growth factors
# (CharacterData.SKILL_GROWTH_FACTORS), so a player can reach fishing 60 and
# cooking 70 at character level 25. Gating their Reef Clown on character level
# would refuse them the fish they caught and cooked themselves, which is a worse
# bug than the twinking the gate exists to stop.
#
# SO A COOKED FISH GATES ON COOKING. The rule is one sentence — if you could
# have cooked it, you can eat it — and the number is the raw fish's cook_level,
# so the game has ONE tier ladder rather than two that drift apart.
#
# "" means no skill requirement, which is every item that is not food. The
# string matches the skill ids player.gd exposes as properties (attack, defense,
# agility, magic, fishing, cooking). A typo names a skill the player has no
# property for, and inventoryscreen.gd pushes an error rather than letting the
# item silently stop gating — a gate that quietly opens is worse than no gate.
@export var required_skill: String = ""

# Level in required_skill needed to use this. Meaningless while required_skill
# is "". 1 means "no gate": MIN_SKILL_LEVEL is 1, so every character already
# satisfies it, and a fish left at the default behaves exactly as it did before
# this field existed.
@export var required_skill_level: int = 1

# Whether an enemy may ever roll this as loot.
#
# TIER IS NOT ENOUGH ON ITS OWN, and cooked fish are the case that proved it.
# The server excludes PET, QUEST, CURRENCY and FISH from drops by TYPE, which
# covers raw fish — but a cooked fish is a Type.CONSUMABLE, exactly like a
# potion, because that is what it does when you use it. So the moment mobs could
# roll tier 1 and 2, a slime started dropping cooked mudfish and cooked marsh
# carp. Every fish the player could be bothered to catch and cook was also
# falling out of the nearest slime, which takes the point out of the skill.
#
# The alternatives were both worse. Making cooked fish their own type costs them
# the restore_target routing the use-handler already does for free. Pushing
# their tier above every ceiling breaks the correspondence with the raw fish
# they come from, and is a trick rather than a statement.
#
# SO IT IS ITS OWN AXIS: tier says how rare a thing is WHEN it drops, and this
# says whether it drops at all. It is also the switch to reach for when content
# outruns the tier ladder — anything finished but not ready to appear can be
# held back here without moving files or inventing an enemy to gate it.
@export var droppable: bool = true


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


# THE SLOT'S NAME LIVES NEXT TO THE SLOT'S ENUM, and nowhere else on the client.
#
# Four things have to agree about what a slot is called: this enum, the
# exporter that writes it into gamedata.json, the server that validates a save
# against it, and the client code that fills the slots. The server's copy was
# typed from memory and was wrong in both directions at once — it carried a
# "robe" slot this enum has never defined, and no BOOTS, which it does. Nothing
# errored. Nothing could: a private copy of a vocabulary has no way to find out
# that it disagrees.
#
# So there is one derivation, here, and everything on the client calls it.
# exportgamedata.gd deliberately keeps its own list, because it is the thing
# that has to NOTICE a change: it refuses the export when this enum grows a
# member that list does not have, and that check only works if the two are
# separate.
#
# LOWERCASED, because that is the spelling on the wire and in the
# saves.equipment column. The export writes "HELM" to match the enum's own
# spelling and gamedata.py lowercases it on the way in; this is the same
# translation on the other side.
#
# LOOKED UP BY VALUE, NOT BY POSITION. A GDScript enum is a Dictionary in
# declaration order, so the two agree today — and stop agreeing the moment
# someone gives a member an explicit number. The failure would be a helmet
# silently filed as a chest piece, which is the exact class of bug this
# function exists to prevent.
static func slot_name(slot_index: int) -> String:
	# "" for NONE and for any value the enum has no member for — the same
	# answer the server gives for "this is not equipment".
	if slot_index <= 0:
		return ""
	for key in EquipSlot:
		if int(EquipSlot[key]) == slot_index:
			return String(key).to_lower()
	return ""


static func slot_names() -> Array:
	# Every slot a character has, in enum order, NONE excluded. The equip panel
	# draws itself from this, so a slot added above shows up in the UI without
	# an edit anywhere else.
	var names: Array = []
	for key in EquipSlot:
		if int(EquipSlot[key]) <= 0:
			continue
		names.append(String(key).to_lower())
	return names


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

# HOW MUCH A HIT VARIES, as a fraction of `damage` either side of it. 0.25
# means an iron sword at 20 lands somewhere in 15-25, rerolled every hit.
#
# WHY VARIANCE AT ALL, when a flat number is easier to reason about: a number
# that never moves reads as arithmetic. A number that moves reads as a blow
# landing well or badly, and it is the difference between watching a health bar
# decrease and feeling like you hit something. It is also what makes a rolled
# affix legible later — a loot system that rolls a weapon's damage is rolling
# the MIDDLE of this band, and nothing downstream has to change to take it.
#
# DEFAULTED RATHER THAN AUTHORED, which is why no weapon .tres mentions it. A
# property equal to its default is omitted from the file entirely, so every
# weapon in the game inherits this and a piece of armour carries it harmlessly
# — the roll is skipped outright when `damage` is 0.
#
# 0.0 means "always exactly `damage`", which is the right answer for a weapon
# whose whole character is reliability, if one is ever authored.
@export var damage_spread: float = 0.25

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
# COOKING (only meaningful when type == Type.FISH)
# =============================================================================
# THE RECIPE LIVES ON THE INGREDIENT, not in a table somewhere else.
#
# The obvious alternative was to derive it from the id — every raw fish is
# "raw<name>" and every cooked one is "cooked<name>", so a string swap would
# work today and cost nothing. It is not written that way because it would make
# the naming convention load-bearing: the first ingredient that is not a fish,
# or the first cooked item whose name is not its raw name with a different
# prefix, silently stops cooking with nothing anywhere to say why.
#
# THE SERVER READS THESE, via exportgamedata.gd. /api/cooking/cook decides what
# a raw fish becomes, whether the player is skilled enough to attempt it, and
# whether it burned - so these four numbers have to reach it as DATA rather than
# being restated in Python. gamedata.py's header is explicit that it restates
# nothing that lives in the game.

# item_id of what this becomes when cooked. "" means it is not cookable.
@export var cooks_into: String = ""

# Cooking level needed to attempt it at all. Below this the firepit refuses.
@export var cook_level: int = 1

# Cooking XP granted per fish successfully cooked. Burning grants nothing —
# there has to be a cost to cooking above your level or the burn chance is
# just a slower way to the same place.
@export var cook_xp: int = 0

# Cooking level at which this stops burning entirely.
#
# BURN CHANCE RIDES BETWEEN cook_level AND THIS. At cook_level it is at its
# worst, at cook_mastery_level it is zero, and it slides linearly between them —
# so a fish you have just unlocked is a gamble and one you have outgrown is
# free. Setting this at or below cook_level means "never burns".
@export var cook_mastery_level: int = 1


# =============================================================================
# FISHING (only meaningful when type == Type.FISH)
# =============================================================================
# Fishing XP awarded for landing one of these.
#
# ON THE FISH, FOR THE SAME REASON THE COOKING RECIPE IS ON THE INGREDIENT.
# /api/fishing/catch decides what was caught and has to know what it was worth,
# and gamedata.py's own header forbids it inventing the number: "Nothing in here
# restates a number that lives in the game; if a value is not in the JSON, that
# is a bug in the exporter." Deriving it from tier in Python would be exactly
# that - a balance curve living on the server where nobody editing the game
# would think to look for it.
#
# SEPARATE FROM cook_xp, because catching a fish and cooking it are two
# different skills being trained by two different actions.
@export var fishing_xp: int = 0


# =============================================================================
# PET (only meaningful when type == Type.PET)
# =============================================================================
# the pet entity scene this item summons when activated. assign the pet's
# .tscn here in the inspector. null for all non-pet items.
@export var pet_scene: PackedScene = null

# which enemy this pet came from — display flair for the future pet-collection
# UI and for organizing pets by source. e.g. "Archer", "Fire Sprite", "Boss".
@export var pet_source_name: String = ""
