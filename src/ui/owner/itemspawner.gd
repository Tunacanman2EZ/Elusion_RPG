# itemspawner.gd - the owner's item menu: every item in the game, one click each.
#
# Day 2: "i need these items as hot keys so i can test - can you create a menu
# in hud that allows me to select and spawn items registered in the game that
# only owner can use". The debug keys hand out a dozen fixed items, only in a
# debug build; the GM panel's Testing tab takes an id typed from memory. This
# is the whole catalogue, with its pictures, searchable, in the released game
# as well as the editor.
#
# - EVERY ITEM ItemRegistry LOADED, so a .tres dropped into data/items/ is in
#   the menu the moment the game starts. Sorted by kind, then tier, then name.
# - A CLICK IS A REQUEST: /api/staff/grant, the route the debug keys and the GM
#   panel already use. The server writes the bag, logs the grant, and sends
#   the bag back; this adopts it, quietly, through CharacterData.
# - "PUT GEAR ON" equips a weapon or armour piece straight from the cell it
#   landed in - the reason this was asked for was testing the mythic weapons,
#   and a spawned sword in the bag is one more step from a sword in the hand.
#   The equip is the ordinary /api/character/equip, so its class and level
#   gates still apply and say why when they refuse.
# - SETTING YOUR LEVEL WAS HERE AND MOVED to the GM panel's Testing tab (Day
#   3, the owner's call), beside the other things done to your own character.
# - "GEAR STATS" says which roll a piece of gear comes with (5 Oct, quality
#   rolls): as the store sells it, rolled the way a drop is, or Perfect - so
#   the one-in-a-hundred can be seen without granting a hundred. The server
#   rolls it; this only names which (QUALITIES).
#
# OWNER ONLY, three times over: the HUD builds the button only for the owner,
# every request here asks Api.is_owner first, and the server is the gate that
# counts - /api/staff/grant needs staff.
class_name ItemSpawner
extends Control


const GRANT_PATH := "/api/staff/grant"

# The kinds, in the order they are listed. "All" first, and what each one holds
# is category_of()'s answer.
const CATEGORIES: Array[String] = [
	"All", "Weapons", "Armour", "Jewellery", "Potions and food", "Pets",
	"Fishing", "Currency", "Other",
]

# What /api/staff/grant's "quality" may be, in the order the list shows them:
# [what the server calls it, what the owner reads].
const QUALITIES: Array = [
	["store", "As the store sells it (100%)"],
	["roll", "Rolled, like a drop"],
	["perfect", "Perfect (every stat at %d%%)" % GameConstants.QUALITY_PERFECT],
]

# A cell: the icon drawn at twice its 16 pixels, inside a two-pixel frame.
const CELL_SIZE := 40

var _window: PanelWindow = null
var _busy: bool = false

# WHERE A REQUEST GOES AND WHERE ITS ANSWER LANDS, as Callables so the suite
# can watch them without a server or a character. In the game they are the
# real ones: Api.post, CharacterData's quiet adoption of a bag and the
# ordinary equip.
var post_request: Callable
var adopt_bag: Callable
var equip_request: Callable

@onready var search: LineEdit = %itemsearch
@onready var category: OptionButton = %itemcategory
@onready var grid: GridContainer = %itemgrid
@onready var count_label: Label = %countlabel
@onready var quantity: SpinBox = %itemquantity
@onready var wear_toggle: CheckBox = %wearit
@onready var quality_pick: OptionButton = %itemquality
@onready var status: Label = %spawnstatus
@onready var close_button: Button = %itemspawnerclose

# One frame per tier, built once: the frame is the rarity colour, so an ember
# piece is orange here as it is in the bag.
static var _frames: Dictionary = {}


func _init() -> void:
	post_request = Callable(Api, "post")
	adopt_bag = _adopt_bag
	equip_request = _equip


func _ready() -> void:
	_window = PanelWindow.attach(self, "itemspawner")
	for name_ in CATEGORIES:
		category.add_item(name_)
	for pair in QUALITIES:
		quality_pick.add_item(String(pair[1]))
	quality_pick.select(0)
	category.item_selected.connect(func(_i: int) -> void: refresh())
	search.text_changed.connect(func(_t: String) -> void: refresh())
	close_button.pressed.connect(close)
	refresh()


func open() -> void:
	visible = true
	refresh()


func close() -> void:
	visible = false


# =============================================================================
# THE LIST
# =============================================================================

static func category_of(item: ItemData) -> String:
	# Which kind an item is listed under. Read from what the item IS - its
	# type and the slot it is worn in - so a new item finds its own place.
	match item.type:
		ItemData.Type.WEAPON:
			return "Weapons"
		ItemData.Type.PET:
			return "Pets"
		ItemData.Type.CURRENCY:
			return "Currency"
		ItemData.Type.FISH:
			return "Fishing"
		ItemData.Type.CONSUMABLE:
			return "Potions and food"
	if item.item_id.ends_with("fishingrod") or item.item_id == "fishingworm":
		return "Fishing"
	match item.equip_slot:
		ItemData.EquipSlot.RING, ItemData.EquipSlot.AMULET:
			return "Jewellery"
		ItemData.EquipSlot.HELM, ItemData.EquipSlot.CHEST, ItemData.EquipSlot.LEGS, \
				ItemData.EquipSlot.BOOTS, ItemData.EquipSlot.SHIELD:
			return "Armour"
	return "Other"


static func matches(item: ItemData, words: String, kind: String) -> bool:
	# The search reads the name and the id, any case, every word: "ember sw"
	# finds the Ember Sword.
	if kind != "All" and category_of(item) != kind:
		return false
	var haystack: String = (item.display_name + " " + item.item_id).to_lower()
	for word in words.to_lower().split(" ", false):
		if not haystack.contains(word):
			return false
	return true


func listed() -> Array[ItemData]:
	var kind: String = CATEGORIES[maxi(category.selected, 0)]
	var found: Array[ItemData] = []
	for item in ItemRegistry.get_all_items():
		if item != null and matches(item, search.text.strip_edges(), kind):
			found.append(item)
	found.sort_custom(func(a: ItemData, b: ItemData) -> bool:
		var ka: int = CATEGORIES.find(category_of(a))
		var kb: int = CATEGORIES.find(category_of(b))
		if ka != kb:
			return ka < kb
		if a.tier != b.tier:
			return a.tier < b.tier
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	return found


func refresh() -> void:
	if grid == null:
		return
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var items: Array[ItemData] = listed()
	for item in items:
		grid.add_child(_make_cell(item))
	count_label.text = GameConstants.counted(items.size(), "item")


func _make_cell(item: ItemData) -> Button:
	var cell := Button.new()
	cell.name = item.item_id
	cell.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	cell.focus_mode = Control.FOCUS_NONE
	cell.icon = item.icon
	cell.expand_icon = true
	cell.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cell.add_theme_constant_override("icon_max_width", 32)
	cell.tooltip_text = describe(item)
	var frame: StyleBoxFlat = _frame_for(item.tier)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		cell.add_theme_stylebox_override(state, frame if state != "hover" else _hover_for(item.tier))
	if item.icon == null:
		# No picture (the private art pack is not here): the name stands in.
		cell.text = item.display_name.left(3)
		cell.add_theme_font_size_override("font_size", 10)
	cell.pressed.connect(spawn.bind(item.item_id))
	return cell


static func describe(item: ItemData) -> String:
	# The tooltip: what it is, how rare, who may use it, and the id - the id
	# is what every other tool and the server's log call it.
	var lines: PackedStringArray = [item.display_name,
		"%s  ·  tier %d" % [GameConstants.rarity_name(item.tier), item.tier]]
	var needs: PackedStringArray = []
	if item.required_level > 1:
		needs.append("level %d" % item.required_level)
	if not item.required_classes.is_empty():
		needs.append(" or ".join(PackedStringArray(item.required_classes)))
	if not needs.is_empty():
		lines.append("Needs " + ", ".join(needs))
	lines.append("id: " + item.item_id)
	return "\n".join(lines)


static func _frame_for(tier: int) -> StyleBoxFlat:
	if not _frames.has(tier):
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.08, 0.09, 0.13)
		box.set_border_width_all(2)
		box.border_color = GameConstants.rarity_colour(tier) if tier >= 2 else Color(0.25, 0.27, 0.33)
		box.set_corner_radius_all(2)
		_frames[tier] = box
	return _frames[tier]


static func _hover_for(tier: int) -> StyleBoxFlat:
	var key: int = 1000 + tier
	if not _frames.has(key):
		var box: StyleBoxFlat = _frame_for(tier).duplicate()
		box.bg_color = Color(0.16, 0.18, 0.25)
		_frames[key] = box
	return _frames[key]


# =============================================================================
# SPAWNING
# =============================================================================

static func quantity_for(item: ItemData, wanted: int) -> int:
	# One request, one stack: a sword is one at a time, potions up to their
	# stack. The server refuses more than that, so asking for it would only
	# turn a click into an error.
	var most: int = maxi(1, item.max_stack) if item.stackable else 1
	return clampi(wanted, 1, most)


func typed_quantity() -> int:
	# WHAT IS IN THE BOX, ENTERED OR NOT. A SpinBox keeps typed text in its
	# LineEdit until Enter or until it loses focus, and the item cells take no
	# focus, so a "7" typed and a potion clicked used to ask for whatever the
	# box held before. apply() is the Enter the player did not press. It reads
	# the text, and the text catches up with a value set from code a frame
	# late, so code that sets the value waits a frame before it clicks (the
	# suite does). A player cannot click that fast.
	quantity.apply()
	return int(quantity.value)


func chosen_quality() -> String:
	# The roll the owner picked, as the server names it.
	return String(QUALITIES[clampi(quality_pick.selected, 0, QUALITIES.size() - 1)][0])


func spawn(item_id: String) -> void:
	if not Api.is_owner:
		_say("The item menu is the owner's.", true)
		return
	if _busy:
		return
	var item: ItemData = ItemRegistry.get_item(item_id)
	if item == null:
		return
	var how_many: int = quantity_for(item, typed_quantity())
	_busy = true
	_say("Asking the server for %s..." % item.display_name)
	var res: Dictionary = await post_request.call(GRANT_PATH, {
		"slot": CharacterData.active_character_index,
		"item_id": item_id,
		"quantity": how_many,
		"quality": chosen_quality(),
	})
	_busy = false
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not res.get("ok", false):
		_say(_refused(res), true)
		return

	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	var cells: Array = data.get("inventory", []) if data.get("inventory", []) is Array else []
	adopt_bag.call(CharacterData.active_character_index, cells)
	# WHAT ARRIVED, which for rolled gear is a piece with its own id: the roll
	# is the server's, so the line, the name and the equip all use its answer.
	var granted_id: String = str(data.get("granted_item_id", item_id))
	var granted: ItemData = ItemRegistry.get_item(granted_id) if granted_id != item_id else item
	if granted == null:
		granted = item
		granted_id = item_id
	item = granted
	var line: String = "Added %d × %s to your bag." % [how_many, item.display_name]
	if item.is_rolled():
		line = "Added %s to your bag, quality %d%%." % [item.display_name, item.quality_percent()]

	var wearable: bool = item.equip_slot != ItemData.EquipSlot.NONE
	if wearable and wear_toggle.button_pressed:
		var written: Array = data.get("carry_positions", []) if data.get("carry_positions", []) is Array else []
		var cell: int = int(written[0]) if not written.is_empty() else -1
		var worn: bool = await equip_request.call(granted_id, cell)
		if not is_instance_valid(self) or not is_inside_tree():
			return
		line = ("Added %s and put it on." % item.display_name) if worn \
			else line + " It could not be put on - see why above the bar."
	_say(line)


# =============================================================================
# THE REAL CALLABLES
# =============================================================================

func _player() -> Node:
	return get_tree().get_first_node_in_group("player") if is_inside_tree() else null


func _adopt_bag(slot_index: int, cells: Array) -> void:
	CharacterData.adopt_granted_bag(slot_index, cells, _player())


func _equip(item_id: String, cell: int) -> bool:
	var player: Node = _player()
	if player == null:
		return false
	return await CharacterData.equip_item(player, item_id, cell)


func _refused(res: Dictionary) -> String:
	# The server's own sentence when there is one, as the GM panel says it.
	var code: int = int(res.get("status", 0))
	var said: String = str(res.get("error", "")).strip_edges()
	if code == 0:
		return ApiScript.no_answer_text()
	if code == 404 and (said == "" or said == "Not found."):
		return "The server refused - is it running the latest app.py?"
	if said != "":
		return said
	return "Refused (HTTP %d)." % code


const ApiScript := preload("res://src/systems/api.gd")


func _say(line: String, bad: bool = false) -> void:
	if status == null:
		return
	status.text = line
	status.add_theme_color_override("font_color",
		Color(1.0, 0.55, 0.45) if bad else Color(0.73, 0.78, 0.84))
