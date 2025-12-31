extends Node
class_name InventoryContainer

## A world/container node that owns an Inventory Resource.
## Used for chests, ground loot piles, etc.

@export var inventory: Inventory

@export_group("Default Inventory (if inventory is empty)")
@export_range(1, 50) var default_rows: int = 4
@export_range(1, 50) var default_columns: int = 5
@export var default_display_name: String = "Container"
@export var default_accepted_flags_mask: int = 0

func _ready() -> void:
	if inventory == null:
		inventory = Inventory.new()
		inventory.display_name = default_display_name
		inventory.rows = default_rows
		inventory.columns = default_columns
		inventory.accepted_flags_mask = default_accepted_flags_mask


