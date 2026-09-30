# hotbar.gd — the ten quickslot keys along the bottom of the HUD.
# parent script for the hotbar container node in characterhud.tscn.
#
# THE KEYS HOLD ITEMS. Each HotbarSlot is a real inventory cell - the player's
# backpack cells 20-29 - so dragging a potion from the bag onto key 1 moves it
# out of the bag, and dragging it back moves it back. This script does not
# keep any state of its own about what is where; the backpack's
# InventoryContainer owns every cell, the keys included, and the server stores
# them as carry_items rows past the bag.
#
# responsibilities:
# - finds its SLOT_COUNT HotbarSlot children by name
# - hands them to the backpack container, which makes them its cells past the
#   grid (set_inventory_container -> attach_remote_slots)
# - number keys 1-9 and 0, and a right-click on a key, use what is on it
#
# usage:
# - the HUD calls set_inventory_container(container) once the inventory screen
#   exists, and answers slot_used by calling InventoryScreen.use_item(slot)
extends Control
class_name Hotbar


# =============================================================================
# SIGNALS
# =============================================================================

# THE SLOT, NOT AN item_id. The HUD passes it straight to use_item(), which
# spends one from THIS cell and names it to the server as `position`. An
# item_id used to go the other way and be looked up in the bag, which is how a
# key and a bag cell holding the same potion could not be told apart.
signal slot_used(slot: HotbarSlot)


# =============================================================================
# CONSTANTS
# =============================================================================

# HOW MANY KEYS THE BAR HAS. The server's HOTBAR_SIZE in app.py is the same
# number, and has to be: the keys are carried cells INVENTORY_CAPACITY and up,
# and the server sends and stores exactly that many.
const SLOT_COUNT := 10

# THE KEYS, IN SLOT ORDER, as they sit on the keyboard: 1 through 9, then 0.
# The keylabel on each slot is drawn from this list too - the suite checks
# every slot's printed number is OS.get_keycode_string() of its key - so the
# number you read on the bar is the key that fires it.
const SLOT_KEYS: Array[Key] = [
	KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0,
]


# =============================================================================
# STATE
# =============================================================================

# the hotbar slot child references — resolved in _ready by name lookup
# (slot1 through slot<SLOT_COUNT> children).
var slots: Array[HotbarSlot] = []


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_resolve_slot_children()
	for slot in slots:
		if slot != null and not slot.slot_right_clicked.is_connected(_on_slot_right_clicked):
			slot.slot_right_clicked.connect(_on_slot_right_clicked)


func _unhandled_input(event: InputEvent) -> void:
	# number keys 1-9 and 0 trigger the corresponding hotbar slot; see
	# slot_for_key() for the mapping.
	#
	# is_echo() rejects the OS key-repeat stream. Holding a number key made
	# the operating system resend the same press every ~30ms once the repeat
	# delay elapsed, and each one was a real InputEventKey with pressed=true —
	# so leaning on "1" drank your entire stack of potions in about a second.
	# A hotbar slot should fire on the press, never on the repeat.
	if not (event is InputEventKey) or not event.pressed or event.is_echo():
		return

	var key_to_slot_index: int = slot_for_key(event.keycode)
	if key_to_slot_index >= 0:
		_use_slot(key_to_slot_index)


static func slot_for_key(keycode: Key) -> int:
	# The slot a key fires, or -1 for a key that is not on the bar.
	#
	# A LOOKUP IN SLOT_KEYS, not arithmetic on keycodes. KEY_1..KEY_9 happen to
	# be consecutive, which made `keycode - KEY_1` tempting - and KEY_0 sits
	# BEFORE KEY_1 in that sequence, so the arithmetic would send 0 to slot -1
	# and drop it. Written out as a list, the tenth key is just the tenth entry.
	return SLOT_KEYS.find(keycode)


# =============================================================================
# INITIALIZATION HELPERS
# =============================================================================

func _resolve_slot_children() -> void:
	# look up slot1 through slot<SLOT_COUNT> children by name. fills `slots`.
	# FOUND BY NAME ANYWHERE UNDER HERE, not as a direct child.
	#
	# This used to be has_node("slot1"), which meant the slots had to be
	# children of the root - and the moment the bar was given a frame and a
	# margin to sit in, every one of them was two levels down and the hotbar
	# came up empty with a warning per key. find_child costs a walk of about a
	# dozen nodes, once, at startup.
	#
	# A missing key is kept as a null and warned about, and the backpack then
	# refuses the whole set - see attach_remote_slots(). Keys that shifted one
	# cell to the left would load every item one key over.
	slots.clear()
	for i in range(SLOT_COUNT):
		var slot_name: String = "slot%d" % (i + 1)
		var found: Node = find_child(slot_name, true, false)
		if found == null:
			push_warning("Hotbar: missing child %s" % slot_name)
			slots.append(null)
			continue
		var slot: HotbarSlot = found as HotbarSlot
		if slot == null:
			push_warning("Hotbar: %s is not a HotbarSlot" % slot_name)
		slots.append(slot)


# =============================================================================
# PUBLIC API
# =============================================================================

func set_inventory_container(container: Node) -> void:
	# Called by the HUD once the inventory screen exists. The keys become the
	# backpack's cells past its grid, and from then on the backpack loads,
	# saves and applies every server answer to them along with the bag.
	if container == null or not container.has_method("attach_remote_slots"):
		return
	container.attach_remote_slots(slots)


# =============================================================================
# USE DISPATCH
# =============================================================================

func _on_slot_right_clicked(slot: InventorySlot) -> void:
	# right-clicking a key uses what is on it, same as pressing its number.
	var key: HotbarSlot = slot as HotbarSlot
	if key == null or key.is_empty():
		return
	slot_used.emit(key)


func _use_slot(slot_index: int) -> void:
	# fire slot_used for the key at this index, if anything is on it.
	# parent HUD subscribes and routes to inventoryscreen's use_item logic.
	if slot_index < 0 or slot_index >= slots.size():
		return

	var slot: HotbarSlot = slots[slot_index]
	if slot == null or slot.is_empty():
		return

	slot_used.emit(slot)
