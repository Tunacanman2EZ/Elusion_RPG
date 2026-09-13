# itemregistry.gd — autoload that loads all ItemData .tres files at startup
# and provides item lookup by item_id from anywhere in the game.
#
# scans res://data/items/ recursively, including all subfolders. drop a new
# item.tres file anywhere under that path and it gets picked up automatically
# on next game launch — no manual registration needed.
#
# usage from other scripts:
# var data: ItemData = ItemRegistry.get_item("healthpotion")
# if ItemRegistry.has_item("ironsword"): ...
# var all_weapons = ItemRegistry.get_items_by_type(ItemData.Type.WEAPON)
#
# validation:
# - empty item_id → error logged, item skipped
# - duplicate item_id → error logged showing both .tres paths, second skipped
# - .tres files that aren't ItemData → silently ignored (could be any resource)
extends Node

# =============================================================================
# CONSTANTS
# =============================================================================
# root folder to scan for .tres item files — recursively walks all subfolders
const ITEMS_PATH := "res://data/items/"

# safe fallback item id when a requested item doesn't exist
const FALLBACK_ITEM_ID := "error_item"

# =============================================================================
# STATE
# =============================================================================
# dictionary mapping item_id (String) to ItemData (Resource).
# this is the lookup table the rest of the game uses.
var _items: Dictionary = {}

# whether the registry has finished its initial scan.
# other systems can poll is_loaded() if they need to wait.
var _is_loaded: bool = false

# how many ItemData resources the scan actually found on disk, counted
# BEFORE the item_id validation below can reject any of them.
#
# WHY THIS EXISTS: the boot line used to report only _items.size(), and a
# count on its own cannot tell you anything is wrong — it just reads as a
# smaller number. petpoisonslimesmall.tres shipped with a copy-pasted
# item_id once, got rejected as a duplicate, and the log said "loaded 13"
# as confidently as it had said 14 the launch before. Reporting found and
# registered side by side makes the gap self-evident without anyone having
# to remember what the number is supposed to be.
#
# It counts ItemData specifically, not every .tres, so unrelated resource
# types living under data/items/ (themes, palettes) can never look like a
# skipped item.
var _item_files_seen: int = 0

# =============================================================================
# LIFECYCLE
# =============================================================================
func _ready() -> void:
	# scan the items folder once on autoload init. all .tres files under
	# ITEMS_PATH get loaded and indexed by item_id.
	_scan_folder(ITEMS_PATH)
	_is_loaded = true

	var loaded: int = _items.size()
	if OS.is_debug_build():
		print("[BOOT] ItemRegistry: scanned %d, loaded %d" % [_item_files_seen, loaded])

	# deliberately NOT gated on is_debug_build(). Every other startup print is
	# routine chatter and has no business in a Release build, but this one only
	# ever fires when an item the game expects to exist is missing from the
	# lookup table — which is a real defect, and one the player would otherwise
	# meet as an item that silently fails to appear.
	if loaded != _item_files_seen:
		push_warning(
			"ItemRegistry: %d of %d item resources were rejected — see the errors above for which and why."
			% [_item_files_seen - loaded, _item_files_seen]
		)

# =============================================================================
# FILESYSTEM SCAN
# =============================================================================
func _scan_folder(path: String) -> void:
	# recursively walks the folder tree and loads every .tres file as ItemData.
	# subfolders like data/items/consumables/ and data/items/weapons/ are
	# scanned automatically — you don't need to register folders manually.
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		push_error("ItemRegistry: cannot open folder %s" % path)
		return

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		# skip hidden files and current/parent dir markers (".", "..", ".hidden")
		if entry.begins_with("."):
			entry = dir.get_next()
			continue

		var full_path: String = path + entry
		if dir.current_is_dir():
			# recurse into subfolder — trailing slash is required for DirAccess
			_scan_folder(full_path + "/")
		elif entry.ends_with(".tres"):
			_load_item(full_path)

		entry = dir.get_next()
	dir.list_dir_end()

func _load_item(path: String) -> void:
	# loads a single .tres file, validates it's ItemData with a valid item_id,
	# and registers it in the lookup dictionary.
	var resource: Resource = load(path)
	
	# silently ignore .tres files that aren't ItemData — the items folder
	# might contain other resource types (palette tres, theme tres, etc.)
	if not resource is ItemData:
		return

	var item: ItemData = resource

	# counted here rather than in _scan_folder: at this point we know the file
	# IS an item, and we have not yet judged whether it is a valid one. Every
	# return below this line is a rejection, and every rejection is the gap
	# the boot line reports.
	_item_files_seen += 1

	# item_id is required as the registry key
	if item.item_id == "":
		push_error("ItemRegistry: %s has empty item_id (skipping)" % path)
		return

	# item_id must be unique — duplicates are usually a copy-paste mistake
	# where the developer forgot to change the id field on a duplicated .tres
	if _items.has(item.item_id):
		push_error("ItemRegistry: duplicate item_id '%s' at %s (already registered from %s)" % [
			item.item_id,
			path,
			_items[item.item_id].resource_path,
		])
		return

	_items[item.item_id] = item

# =============================================================================
# PUBLIC API — LOOKUPS
# =============================================================================
func get_item(item_id: String) -> ItemData:
	# returns the ItemData for the given id, or a safe fallback if not found.
	if not _items.has(item_id):
		push_warning("ItemRegistry: requested unknown item_id '%s'. Reverting to fallback." % item_id)
		
		# check if our fallback item actually exists in the scanned files
		if _items.has(FALLBACK_ITEM_ID):
			return _items[FALLBACK_ITEM_ID]
			
		# absolute emergency backup if even the error item is missing from the directory
		return null
		
	return _items[item_id]

func has_item(item_id: String) -> bool:
	# silent check — returns true if an item with this id exists in the
	# registry. unlike get_item, doesn't warn on miss. use this when
	# checking optional items (e.g., "does this loot table item exist?").
	return _items.has(item_id)

# =============================================================================
# PUBLIC API — BULK QUERIES
# =============================================================================
func get_all_items() -> Array[ItemData]:
	# returns every registered ItemData — useful for shop UIs that want to
	# display all available items, debug menus, or save-format migrations.
	var all: Array[ItemData] = []
	for item in _items.values():
		all.append(item)
	return all

func get_items_by_type(item_type: ItemData.Type) -> Array[ItemData]:
	# returns all items matching a given Type enum value.
	# useful for "show me all weapons" or "list all consumables" filters.
	var matching: Array[ItemData] = []
	for item in _items.values():
		if item.type == item_type:
			matching.append(item)
	return matching

# =============================================================================
# STATE QUERY
# =============================================================================
func is_loaded() -> bool:
	# returns true once the initial scan has completed.
	# other systems can poll this if they need to wait for the registry
	# to be ready before doing item lookups.
	return _is_loaded
