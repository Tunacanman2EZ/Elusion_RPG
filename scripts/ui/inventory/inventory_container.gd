extends GridContainer
class_name InventoryContainer

## The containers number of columns
@export var width: int = 1
## The containers number of rows
@export var height: int = 1

@export_category("Scene Connections")
@export var inventory_slot_scene: PackedScene = preload("res://scenes/ui/inventory/inventory_slot.tscn")

@export_category("Do Not Edit This Section in Inspector")
## The containers total capacity; w * h [br]
## Shown for devex 
@export var capacity: int = width * height

@export var items: Array[Item] 



func _init(wdth:int, hght: int) -> void:
	self.width = wdth
	self.height = hght

func _ready() -> void:
	capacity = width * height

func resize(w:int, h:int) -> void:
	width = w
	height = h
