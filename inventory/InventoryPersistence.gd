extends Object
class_name InventoryPersistence

## Save/load Inventory Resources for character-specific storage.

static func _char_dir(slot_idx: int) -> String:
	return "user://inventories/char_%d" % slot_idx

static func _bag_path(slot_idx: int) -> String:
	return _char_dir(slot_idx) + "/bag.tres"

static func _bank_path(slot_idx: int) -> String:
	return _char_dir(slot_idx) + "/bank.tres"

static func _ensure_dir(path: String) -> void:
	# path is expected to be a directory path (user://...).
	if DirAccess.dir_exists_absolute(path):
		return
	DirAccess.make_dir_recursive_absolute(path)

static func load_or_create_bag(slot_idx: int, default_rows: int = 4, default_columns: int = 5) -> Inventory:
	_ensure_dir(_char_dir(slot_idx))
	var path := _bag_path(slot_idx)
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is Inventory:
			return res as Inventory

	var inv := Inventory.new()
	inv.display_name = "Bag"
	inv.rows = default_rows
	inv.columns = default_columns
	InventorySeed.seed_bag_if_empty(inv)
	save_bag(slot_idx, inv)
	return inv

static func save_bag(slot_idx: int, inv: Inventory) -> void:
	if inv == null:
		return
	_ensure_dir(_char_dir(slot_idx))
	var path := _bag_path(slot_idx)
	ResourceSaver.save(inv, path)

static func load_or_create_bank(slot_idx: int, default_rows: int = 6, default_columns: int = 8) -> Inventory:
	_ensure_dir(_char_dir(slot_idx))
	var path := _bank_path(slot_idx)
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is Inventory:
			return res as Inventory

	var inv := Inventory.new()
	inv.display_name = "Bank"
	inv.rows = default_rows
	inv.columns = default_columns
	save_bank(slot_idx, inv)
	return inv

static func save_bank(slot_idx: int, inv: Inventory) -> void:
	if inv == null:
		return
	_ensure_dir(_char_dir(slot_idx))
	var path := _bank_path(slot_idx)
	ResourceSaver.save(inv, path)


