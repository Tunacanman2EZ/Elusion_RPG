extends Resource
class_name Item

@export var name: String
@export var description: String
@export var icon: Texture2D
@export var stackable: bool = false
@export var stack_size: int = 1
@export var value: int
@export var tier: int
@export var required_level: int
@export var slot_index: int = -1

func _init(name: String, description: String, icon: Texture2D, stackable: bool, stack_size: int, value: int, tier: int, required_level: int, slot_index: int) -> void:
	self.name = name
	self.description = description
	self.icon = icon
	self.stackable = stackable
	self.stack_size = stack_size
	self.value = value
	self.tier = tier
	self.required_level = required_level
	self.slot_index = slot_index


