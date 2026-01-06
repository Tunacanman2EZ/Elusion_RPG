extends Resource
class_name Item

# Without this line, the init func would push a bunch of warnigns cause the init arguements are 'shadowing' (same name) as the variables we declare (the export vars below) 
@warning_ignore("shadowed_variable")

@export var name: String
@export var description: String
@export var icon: Texture2D
@export var stackable: bool
@export var stack_size: int
@export var value: int
@export var tier: int
@export var required_level: int
# We dont want to edit the slot index, this is just to keep track of it and make inventory management eaier by letting the item have a reference to its position
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
