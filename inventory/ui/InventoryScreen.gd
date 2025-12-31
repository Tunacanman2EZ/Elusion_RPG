extends Control
class_name InventoryScreen

const InventoryPersist = preload("res://inventory/InventoryPersistence.gd")

@onready var _left_title: Label = %LeftTitle
@onready var _right_title: Label = %RightTitle
@onready var _left_view: InventoryView = %LeftView
@onready var _right_view: InventoryView = %RightView
@onready var _tooltip: InventoryTooltip = %Tooltip

var _slot_idx: int = 0
var _player: Node = null

func setup_for_player(player: Node, slot_idx: int) -> void:
	_player = player
	_slot_idx = slot_idx
	var bag: Inventory = player.inventory if ("inventory" in player) else null
	set_left_inventory(bag)
	set_right_inventory(null)

func set_left_inventory(inv: Inventory) -> void:
	_left_view.inventory = inv
	_left_title.text = inv.display_name if inv != null and inv.display_name != "" else "Bag"

func set_right_inventory(inv: Inventory) -> void:
	_right_view.visible = (inv != null)
	_right_title.visible = (inv != null)
	_right_view.inventory = inv
	_right_title.text = inv.display_name if inv != null and inv.display_name != "" else "Container"

func open_bank() -> void:
	set_right_inventory(InventoryPersist.load_or_create_bank(_slot_idx))

func close_container() -> void:
	set_right_inventory(null)

func _ready() -> void:
	_left_view.slot_hovered.connect(_on_slot_hovered)
	_left_view.slot_unhovered.connect(_on_slot_unhovered)
	_left_view.inventory_mutated.connect(_on_inventory_mutated)
	_right_view.slot_hovered.connect(_on_slot_hovered)
	_right_view.slot_unhovered.connect(_on_slot_unhovered)
	_right_view.inventory_mutated.connect(_on_inventory_mutated)

func _on_slot_hovered(stack: ItemStack, pos: Vector2) -> void:
	if stack == null:
		_tooltip.hide_tooltip()
		return
	_tooltip.show_for_stack(stack)
	_tooltip.global_position = pos + Vector2(16, 16)

func _on_slot_unhovered() -> void:
	_tooltip.hide_tooltip()

func _on_inventory_mutated() -> void:
	# Persist bag and bank whenever they change.
	if _player != null and ("inventory" in _player) and _player.inventory is Inventory:
		InventoryPersist.save_bag(_slot_idx, _player.inventory)
	if _right_view.inventory != null and _right_view.inventory.display_name == "Bank":
		InventoryPersist.save_bank(_slot_idx, _right_view.inventory)


