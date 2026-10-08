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

# EVERY ROLLED PIECE ASKED FOR SO FAR: rolled id -> its ItemData copy. Kept so
# one id is always one object - the inventory compares stacks by item_id, but
# a tooltip or a slot holding a reference should not see a new copy every
# time it asks. Bounded by what one player is shown, which is a few hundred
# at the very most.
var _rolled: Dictionary = {}

# The shape of a roll after QUALITY_MARK: one lowercase letter and a two- or
# three-digit percent, repeated. Compiled once. \z, NOT $: PCRE's $ also
# matches before a final newline, so "ironsword~d107\n" was read as the 107
# roll - a second spelling of one piece. gamedata.py had the same hole (and
# Unicode digits through \d); both closed 7 Oct.
var _roll_suffix: RegEx = RegEx.create_from_string("^(?:[a-z][0-9]{2,3})+\\z")
var _roll_part: RegEx = RegEx.create_from_string("([a-z])([0-9]{2,3})")

# =============================================================================
# LIFECYCLE
# =============================================================================
func _ready() -> void:
	# scan the items folder once on autoload init. all .tres files under
	# ITEMS_PATH get loaded and indexed by item_id.
	_scan_folder(ITEMS_PATH)

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
	#
	# ResourceLoader.list_directory(), NOT DirAccess. An export converts every
	# .tres to binary and lists it as "<name>.tres.remap", so a DirAccess walk
	# looking for ".tres" found nothing: EVERY EXPORTED BUILD RAN WITH AN EMPTY
	# REGISTRY - no item could be named, drawn or validated. It showed first in
	# the browser build ("ItemRegistry not populated yet" on every login), and
	# it was true of a Windows export all along. list_directory() answers with
	# the names as the editor shows them, remapped or not; folders end in "/".
	if not DirAccess.dir_exists_absolute(path):
		push_error("ItemRegistry: cannot open folder %s" % path)
		return

	for entry in ResourceLoader.list_directory(path):
		# skip hidden files (".hidden") - list_directory gives no "." or ".."
		if entry.begins_with("."):
			continue
		if entry.ends_with("/"):
			_scan_folder(path + entry)
		elif entry.ends_with(".tres"):
			_load_item(path + entry)

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

	# AN EMPTY ID IS "NOTHING", NOT "NOT FOUND", and the difference is the
	# difference between a defect and an ordinary Tuesday.
	#
	# Empty slots are everywhere in this game: a weapon slot before you find a
	# sword, eight armour slots on a new character, a hotbar square nobody has
	# filled. Every one of those reads its id and asks here. Treating "" as an
	# unknown item meant a push_warning — with a full stack trace attached —
	# once per melee swing for an unarmed warrior, which is once a second, for
	# a character doing nothing wrong.
	#
	# The fallback item exists so a TYPO or a renamed item shows up as a
	# visible error item instead of vanishing. "" is neither; nobody mistyped
	# it, it means the slot is empty, and the callers all null-check already.
	if item_id == "":
		return null

	# A ROLLED PIECE: "ironsword~d107". A copy of the sword with its damage at
	# 107%; see rolled_item(). A malformed roll falls through to the warning
	# below, like any other id nobody has heard of.
	if item_id.contains(GameConstants.QUALITY_MARK):
		var rolled: ItemData = rolled_item(item_id)
		if rolled != null:
			return rolled

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
	if item_id.contains(GameConstants.QUALITY_MARK):
		return rolled_item(item_id) != null
	return _items.has(item_id)


# =============================================================================
# PUBLIC API — QUALITY ROLLS
# =============================================================================
# A dropped piece's roll is part of its id (GameConstants.QUALITY_MARK). These
# read it with the server's rules - gamedata.split_variant() and scale_stat()
# are the other half, and the two must agree to the point, because the server
# derives max health from the same rolled numbers this hands to Player.

func split_roll(item_id: String) -> Dictionary:
	# {"base": "jadechest", "rolls": {"armor_value": 104, "bonus_max_hp": 96},
	# "resist": {"element": 6, "percent": 5}} for a rolled id ("resist" {} when
	# it resists nothing); {"base": item_id, "rolls": {}, "resist": {}} for a
	# plain one; and {} for anything that only looks like a roll.
	#
	# STRICT, BECAUSE THE ID IS THE IDENTITY - the same rules as the server:
	# every stat the base piece has, each once, in QUALITY_FIELDS order, and
	# either all at QUALITY_PERFECT or each inside QUALITY_LOW..QUALITY_HIGH;
	# then at most one resistance, read_resist()'s rules, at the top of its
	# range on a Perfect piece.
	var mark: int = item_id.find(GameConstants.QUALITY_MARK)
	if mark < 0:
		return {"base": item_id, "rolls": {}, "resist": {}}
	var base: String = item_id.substr(0, mark)
	var suffix: String = item_id.substr(mark + 1)
	if not _items.has(base) or _roll_suffix.search(suffix) == null:
		return {}

	var expected: Array = rolled_fields(_items[base])
	var matches: Array = _roll_part.search_all(suffix)
	# THE RESISTANCE COMES LAST, after every stat: its letter, the element's
	# number and the percent in two digits ("r605"). Optional - a piece from
	# before resistances has none - but only on armour, inside its tier's range.
	var resist: Dictionary = {}
	if not matches.is_empty() and matches.back().get_string(1) == GameConstants.RESIST_LETTER:
		resist = read_resist(_items[base], matches.back().get_string(2))
		if resist.is_empty():
			return {}
		matches = matches.slice(0, matches.size() - 1)
	if matches.is_empty() or matches.size() != expected.size():
		return {}
	var rolls: Dictionary = {}
	var perfect_count: int = 0
	for i in matches.size():
		var letter: String = matches[i].get_string(1)
		var digits: String = matches[i].get_string(2)
		if letter != String(expected[i][0]) or digits.begins_with("0"):
			return {}
		var percent: int = int(digits)
		if percent == GameConstants.QUALITY_PERFECT:
			perfect_count += 1
		elif percent < GameConstants.QUALITY_LOW or percent > GameConstants.QUALITY_HIGH:
			return {}
		rolls[String(expected[i][1])] = percent
	if perfect_count != 0 and perfect_count != rolls.size():
		return {}
	# A PERFECT PIECE RESISTS AT THE TOP OF ITS RANGE, as every stat sits at the
	# top of its own - so a Perfect has one spelling per element, not five.
	if perfect_count != 0 and not resist.is_empty() \
			and int(resist["percent"]) != GameConstants.resist_range(int(_items[base].tier)).y:
		return {}
	return {"base": base, "rolls": rolls, "resist": resist}


func read_resist(data: ItemData, digits: String) -> Dictionary:
	# {"element", "percent"} from a resistance's three digits, or {} when they
	# are not one this piece could have rolled - the server's rule
	# (gamedata._parse_variant): armour, one of RESIST_ELEMENTS, inside the
	# tier's range, two digits of percent.
	if data == null or not data.resists_when_rolled() or digits.length() != 3:
		return {}
	var element: int = int(digits.substr(0, 1))
	var percent: int = int(digits.substr(1, 2))
	var window: Vector2i = GameConstants.resist_range(int(data.tier))
	if not GameConstants.RESIST_ELEMENTS.has(element) or percent < window.x or percent > window.y:
		return {}
	return {"element": element, "percent": percent}


func rolled_fields(data: ItemData) -> Array:
	# [[letter, field], ...] for every stat this piece has above zero, in
	# QUALITY_FIELDS order. A potion, a rod or a coin has none and never rolls.
	var out: Array = []
	if data == null:
		return out
	for pair in GameConstants.QUALITY_FIELDS:
		var field: String = String(pair[1])
		if field in data and int(data.get(field)) > 0:
			out.append(pair)
	return out


func scale_stat(number: int, percent: int) -> int:
	# A catalogue number at this percent, to the nearest point, halves up.
	# INTEGER ARITHMETIC, the same sum as gamedata.scale_stat(): a float that
	# rounded differently here would put the client's max health a point away
	# from the server's for as long as the piece is worn.
	if number <= 0:
		return number
	@warning_ignore("integer_division")
	return (number * percent + 50) / 100


func rolled_item(item_id: String) -> ItemData:
	# The ItemData for a rolled id: a copy of its .tres with each rolled stat
	# scaled, item_id the whole rolled id, base_id and rolls filled in, and
	# "Perfect " in front of a Perfect piece's name. null for a malformed roll.
	if _rolled.has(item_id):
		return _rolled[item_id]
	var parts: Dictionary = split_roll(item_id)
	if parts.is_empty() or (parts["rolls"] as Dictionary).is_empty():
		return null
	var base: ItemData = _items[parts["base"]]
	var copy: ItemData = base.duplicate() as ItemData
	copy.item_id = item_id
	copy.base_id = String(parts["base"])
	copy.rolls = parts["rolls"]
	for field in copy.rolls.keys():
		copy.set(field, scale_stat(int(base.get(field)), int(copy.rolls[field])))
	if copy.is_perfect():
		copy.display_name = "Perfect " + base.display_name
	var resist: Dictionary = parts.get("resist", {})
	if not resist.is_empty():
		copy.resist_element = int(resist["element"])
		copy.resist_percent = int(resist["percent"])
	_rolled[item_id] = copy
	return copy

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
