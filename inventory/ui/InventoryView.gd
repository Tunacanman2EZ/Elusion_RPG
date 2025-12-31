extends Control
class_name InventoryView

signal slot_hovered(stack: ItemStack, global_pos: Vector2)
signal slot_unhovered()
signal inventory_mutated()

@export var slot_scene: PackedScene
@export var grabbed_preview_scene: PackedScene

@onready var _grid: GridContainer = %Grid

var _inventory: Inventory = null

var inventory: Inventory:
	get:
		return _inventory
	set(value):
		_set_inventory(value)

var _slot_views: Array[InventorySlotView] = []

func _ready() -> void:
	if slot_scene == null:
		slot_scene = preload("res://inventory/ui/InventorySlotView.tscn")
	if grabbed_preview_scene == null:
		grabbed_preview_scene = preload("res://inventory/ui/GrabbedItemStackView.tscn")
	if _inventory != null:
		_set_inventory(_inventory)

func _exit_tree() -> void:
	_disconnect_inventory()

func _disconnect_inventory() -> void:
	if _inventory == null:
		return
	if _inventory.is_connected("slot_changed", Callable(self, "_on_slot_changed")):
		_inventory.disconnect("slot_changed", Callable(self, "_on_slot_changed"))
	if _inventory.is_connected("changed_all", Callable(self, "_refresh_all")):
		_inventory.disconnect("changed_all", Callable(self, "_refresh_all"))
	if _inventory.is_connected("resized", Callable(self, "_on_resized")):
		_inventory.disconnect("resized", Callable(self, "_on_resized"))

func _set_inventory(inv: Inventory) -> void:
	_disconnect_inventory()
	_inventory = inv
	_rebuild()
	if _inventory == null:
		return
	_inventory.connect("slot_changed", Callable(self, "_on_slot_changed"))
	_inventory.connect("changed_all", Callable(self, "_refresh_all"))
	_inventory.connect("resized", Callable(self, "_on_resized"))
	_refresh_all()

func _rebuild() -> void:
	# Clear old
	for c in _grid.get_children():
		c.queue_free()
	_slot_views.clear()

	if _inventory == null:
		return

	_grid.columns = _inventory.columns
	var cap := _inventory.get_capacity()
	for i in range(cap):
		var slot := slot_scene.instantiate() as InventorySlotView
		slot.bind(_inventory, i, grabbed_preview_scene)
		slot.hovered.connect(func(stack: ItemStack, pos: Vector2): slot_hovered.emit(stack, pos))
		slot.unhovered.connect(func(): slot_unhovered.emit())
		slot.inventory_mutated.connect(func(): inventory_mutated.emit())
		_grid.add_child(slot)
		_slot_views.append(slot)

func _on_resized(_old_r: int, _old_c: int, _new_r: int, _new_c: int) -> void:
	_rebuild()

func _on_slot_changed(index: int) -> void:
	if index < 0 or index >= _slot_views.size():
		return
	_slot_views[index]._refresh()

func _refresh_all() -> void:
	for s in _slot_views:
		s._refresh()


