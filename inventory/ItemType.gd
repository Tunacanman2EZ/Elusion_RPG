extends Resource
class_name ItemType

## Data definition for an item kind (stacking rules, icon, flags, and basic economy/stats fields).
## Inspired by Wyvernbox, but simplified (no multi-tile sizing, no 3D, no editor tooling).

## All possible slot/category flags for items.
## Keep these even if we don't use equipment right now, so inventories can restrict insertions later.
enum SlotFlags {
	NONE = 0,
	WEAPON = 1 << 0,
	EQUIPMENT = 1 << 1,
	CONSUMABLE = 1 << 2,
	MATERIAL = 1 << 3,
	QUEST = 1 << 4,
	KEY = 1 << 5,
	CURRENCY = 1 << 6,
	AMMO = 1 << 7,
	# Reserved bits for future expansion / equipment sub-slots:
	WEAPON_MAINHAND = 1 << 14,
	WEAPON_OFFHAND = 1 << 15,
	EQUIPMENT_HEAD = 1 << 19,
	EQUIPMENT_NECK = 1 << 20,
	EQUIPMENT_SHOULDERS = 1 << 21,
	EQUIPMENT_BACK = 1 << 22,
	EQUIPMENT_CHEST = 1 << 23,
	EQUIPMENT_WAIST = 1 << 24,
	EQUIPMENT_LEGS = 1 << 25,
	EQUIPMENT_FEET = 1 << 26,
	EQUIPMENT_HANDS = 1 << 27,
	EQUIPMENT_ACCESSORY = 1 << 28,
	EQUIPMENT_MAINHAND = 1 << 29,
	EQUIPMENT_OFFHAND = 1 << 30,
}

@export_flags(
	"None",
	"Weapon",
	"Equipment",
	"Consumable",
	"Material",
	"Quest",
	"Key",
	"Currency",
	"Ammo",
	"#",
	"#",
	"#",
	"#",
	"#",
	"#",
	"Weapon_Mainhand",
	"Weapon_Offhand",
	"#",
	"#",
	"#",
	"Equipment_Head",
	"Equipment_Neck",
	"Equipment_Shoulders",
	"Equipment_Back",
	"Equipment_Chest",
	"Equipment_Waist",
	"Equipment_Legs",
	"Equipment_Feet",
	"Equipment_Hands",
	"Equipment_Accessory",
	"Equipment_Mainhand",
	"Equipment_Offhand"
) var slot_flags: int = SlotFlags.NONE

## Display
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var highlight_color: Color = Color.WHITE

## Stacking
@export_range(1, 9999) var max_stack_size: int = 1

## Economy / basic stats (kept even if vendors are deferred)
@export var value: int = 0
@export var weight: float = 0.0

## Freeform data hooks (kept lightweight; no custom tooling for now)
@export var tags: Array[StringName] = []
@export var properties: Dictionary[StringName, Variant] = {}
@export var default_extra_properties: Dictionary = {}

func get_display_name() -> String:
	return display_name if display_name != "" else resource_name


