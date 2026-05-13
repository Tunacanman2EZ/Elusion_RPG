# itemregistry.gd — autoload that loads all ItemData .tres files at startup
# provides item lookup by item_id from anywhere in the game
# scans res://data/items/ recursively, including all subfolders
extends Node

# folder to scan for .tres item files — recursively walks all subfolders
const ITEMS_PATH := "res://data/items/"

# dictionary mapping item_id (String) to ItemData (Resource)
# this is the lookup table the rest of the game uses
var _items: Dictionary = {}

# whether the registry has finished its initial scan
var _is_loaded: bool = false

func _ready() -> void:
	# scan the items folder and load every .tres file we find
	_scan_folder(ITEMS_PATH)
	_is_loaded = true
	print("=== ITEMREGISTRY READY: loaded %d items ===" % _items.size())

func _scan_folder(path: String) -> void:
	# recursively walks the folder tree and loads every .tres file as ItemData
	# subfolders like data/items/consumables/ and data/items/weapons/ are
	# scanned automatically — you don't need to register folders manually

	var dir := DirAccess.open(path)
	if dir == null:
		push_error("ItemRegistry: cannot open folder %s" % path)
		return

	dir.list_dir_begin()
	var entry: String = dir.get_next()

	while entry != "":
		# skip hidden files and current/parent dir markers
		if entry.begins_with("."):
			entry = dir.get_next()
			continue

		var full_path: String = path + entry

		if dir.current_is_dir():
			# recurse into subfolder — note the trailing slash
			_scan_folder(full_path + "/")
		elif entry.ends_with(".tres"):
			# load this resource and try to register it as ItemData
			_load_item(full_path)

		entry = dir.get_next()

	dir.list_dir_end()

func _load_item(path: String) -> void:
	# loads a single .tres file, validates it's ItemData with valid item_id,
	# and registers it in the dictionary

	var resource: Resource = load(path)

	# the resource exists but might not be ItemData — could be any other
	# .tres file someone dropped in the items folder. ignore non-ItemData.
	if not resource is ItemData:
		return

	var item: ItemData = resource

	# item_id is required and must be unique
	if item.item_id == "":
		push_error("ItemRegistry: %s has empty item_id (skipping)" % path)
		return

	if _items.has(item.item_id):
		push_error("ItemRegistry: duplicate item_id '%s' at %s (already registered from %s)" % [
			item.item_id, path, _items[item.item_id].resource_path
		])
		return

	# register the item
	_items[item.item_id] = item

# --- public API ---

func get_item(item_id: String) -> ItemData:
	# returns the ItemData for the given id, or null if not found
	# log a warning if asking for an item that doesn't exist —
	# helps catch typos in code that references item_ids
	if not _items.has(item_id):
		push_warning("ItemRegistry: requested unknown item_id '%s'" % item_id)
		return null
	return _items[item_id]

func has_item(item_id: String) -> bool:
	# returns true if an item with this id exists in the registry
	return _items.has(item_id)

func get_all_items() -> Array[ItemData]:
	# returns every registered ItemData — useful for shop UIs that
	# want to display all available items, or for debug menus
	var all: Array[ItemData] = []
	for item in _items.values():
		all.append(item)
	return all

func get_items_by_type(item_type: ItemData.Type) -> Array[ItemData]:
	# returns all items matching a given Type enum value
	# useful for "show me all weapons" or "list all consumables"
	var matching: Array[ItemData] = []
	for item in _items.values():
		if item.type == item_type:
			matching.append(item)
	return matching

func is_loaded() -> bool:
	# returns true once the initial scan has completed
	# other systems can wait for this if needed
	return _is_loaded
