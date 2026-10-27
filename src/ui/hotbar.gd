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
# - its keys (1-9 and 0 unless the player chose others), and a right-click on
#   a key, use what is on it - and on a touch screen a tap, with the bar drawn
#   bigger while the touch screen is in use (fit_to_thumbs())
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

# THE DEFAULT KEYS, IN SLOT ORDER, as they sit on the keyboard: 1 through 9,
# then 0. Since 0.8.0 the keys are the actions hotbar_1..hotbar_10, made from
# this list by Keybinds and rebindable on the Controls card; each slot's
# keylabel shows the key its action is on now (refresh_key_labels()), so the
# number you read on the bar is the key that fires it.
const SLOT_KEYS: Array[Key] = [
	KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0,
]

# BIGGER UNDER A THUMB (0.55.0). The owner, on a phone: "hotbar icons are a
# bit small". The keys are 42 units in a 1280-unit game, and a phone held
# sideways shows a unit at about half a CSS pixel, so a key came out 23 CSS
# pixels across with a 15-pixel icon in it. While the touch screen is in use
# the bar is drawn at the pad's scale (touchpad.gd's thumb_scale(): game units
# to a CSS pixel), so a key is the size it is on a laptop. It grows up and to
# the left from its bottom right corner, where it is pinned, and the pad's
# buttons over it move up with its top.
#
# NEVER PAST TOUCH_MOST_SCALE: the widest it can be before its left end
# reaches the stick's part of the screen, (1280 - 4 - 1280 * 0.42) / 396.
const TOUCH_MOST_SCALE := 1.85
const PadScript := preload("res://src/ui/touchpad.gd")

# FIVE KEYS UNDER A THUMB (0.91.0). Ten keys at the touch scale were 731 of
# the game's 1280 units across, half the screen's width, under Attack. On a
# touch screen keys 1 to 5 are shown and the bar is as wide as they are; 6 to
# 0 keep what is on them, and come back with a keyboard.
const TOUCH_KEYS := 5

# The suite's stand-in for a phone's pixels to a CSS pixel; 0 asks the screen.
# A headless run's window is the game's own size at one pixel to one, where
# the bar would never grow at all.
static var pixel_ratio_for_test: float = 0.0


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
		if slot != null and not slot.gui_input.is_connected(_on_slot_touched):
			slot.gui_input.connect(_on_slot_touched.bind(slot))
	refresh_key_labels()
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null and settings.get("keys") is Keybinds:
		var keys: Keybinds = settings.get("keys")
		if not keys.changed.is_connected(refresh_key_labels):
			keys.changed.connect(refresh_key_labels)
	TouchControls.changed.connect(_on_touch_changed)
	get_viewport().size_changed.connect(fit_to_thumbs)
	resized.connect(fit_to_thumbs)
	fit_to_thumbs()


# =============================================================================
# SIZE ON A TOUCH SCREEN
# =============================================================================

static func touch_scale(window_pixels: Vector2, drawn_at: Vector2, pixel_ratio: float) -> float:
	"""How much bigger the bar is drawn while the touch screen is in use: the
	pad's scale, held to TOUCH_MOST_SCALE."""
	return minf(PadScript.thumb_scale(window_pixels, drawn_at, pixel_ratio), TOUCH_MOST_SCALE)


func _on_touch_changed(_on: bool) -> void:
	fit_to_thumbs()


# How wide the bar is with all ten keys, kept as it is narrowed.
var _full_width: float = NAN


func fit_to_thumbs() -> void:
	var grow: float = 1.0
	var window: Window = get_window() if is_inside_tree() else null
	_show_touch_keys(TouchControls.active)
	if TouchControls.active and window != null:
		var view: Vector2 = get_viewport_rect().size
		var drawn_at: Vector2 = Vector2(window.content_scale_size) if window.content_scale_size != Vector2i.ZERO else view
		var ratio: float = pixel_ratio_for_test if pixel_ratio_for_test > 0.0 else DisplayServer.screen_get_scale()
		grow = touch_scale(Vector2(window.size), drawn_at, ratio)
	pivot_offset = size
	scale = Vector2(grow, grow)


func _show_touch_keys(touch: bool) -> void:
	"""Keys past TOUCH_KEYS hidden on a touch screen, and the bar narrowed to
	the ones left, from its right edge, where it is pinned."""
	var narrowed: bool = not is_nan(_full_width)
	if touch == narrowed:
		return
	if touch:
		_full_width = offset_right - offset_left
	for i in slots.size():
		if slots[i] != null:
			slots[i].visible = not touch or i < TOUCH_KEYS
	if touch:
		offset_left = offset_right - get_combined_minimum_size().x
	else:
		offset_left = offset_right - _full_width
		_full_width = NAN


func _unhandled_input(event: InputEvent) -> void:
	# The key on each slot's action fires that slot; see slot_for_event().
	#
	# is_echo() rejects the OS key-repeat stream. Holding a number key made
	# the operating system resend the same press every ~30ms once the repeat
	# delay elapsed, and each one was a real InputEventKey with pressed=true —
	# so leaning on "1" drank your entire stack of potions in about a second.
	# A hotbar slot should fire on the press, never on the repeat.
	if not (event is InputEventKey) or not event.pressed or event.is_echo():
		return

	var key_to_slot_index: int = slot_for_event(event)
	if key_to_slot_index >= 0:
		_use_slot(key_to_slot_index)


static func slot_for_event(event: InputEvent) -> int:
	"""The slot a press fires, or -1: whichever hotbar action holds its key -
	the key in that place on the keyboard, or the printed one for a press
	that says only that."""
	return slot_for_key(Keybinds.event_key(event) as Key)


static func slot_for_key(keycode: Key) -> int:
	# The slot a key fires, or -1 for a key that is not on the bar.
	#
	# A LOOKUP, not arithmetic on keycodes. KEY_1..KEY_9 happen to be
	# consecutive, which made `keycode - KEY_1` tempting - and KEY_0 sits
	# BEFORE KEY_1 in that sequence, so the arithmetic would send 0 to slot -1
	# and drop it. Each slot's action is asked by name instead; with no
	# actions made yet (a scene loaded on its own), the default list.
	for i in SLOT_COUNT:
		var action: String = Keybinds.hotbar_action(i)
		if not InputMap.has_action(action):
			return SLOT_KEYS.find(keycode)
		for bound in InputMap.action_get_events(action):
			if Keybinds.event_key(bound) == int(keycode):
				return i
	return -1


static func key_for_slot(index: int) -> int:
	"""The key slot `index` is on now (its action's first key), or 0."""
	var action: String = Keybinds.hotbar_action(index)
	if not InputMap.has_action(action):
		return int(SLOT_KEYS[index]) if index < SLOT_KEYS.size() else 0
	for bound in InputMap.action_get_events(action):
		var code: int = Keybinds.event_key(bound)
		if code != 0:
			return code
	return 0


func refresh_key_labels() -> void:
	for i in slots.size():
		var slot: Node = slots[i]
		if slot == null:
			continue
		var label: Label = slot.get_node_or_null("keylabel") as Label
		if label != null:
			label.text = Keybinds.key_name(key_for_slot(i))


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


# A FINGER ON A KEY (0.53.0). A touch screen has no right button and no number
# keys, so a tap on a key uses it: down and up again on the key, quickly and
# without the slide that drags it - a finger slid off it is still the drag it
# always was.
const TAP_SLIDE := 14.0
const TAP_MSEC := 600
# finger -> [the key it went down on, where, when]
var _taps: Dictionary = {}


func _on_slot_touched(event: InputEvent, slot: HotbarSlot) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null:
		return
	if touch.pressed:
		_taps[touch.index] = [slot, touch.position, Time.get_ticks_msec()]
		return
	var began: Array = _taps.get(touch.index, [])
	_taps.erase(touch.index)
	if began.is_empty() or began[0] != slot or touch.canceled:
		return
	if touch.position.distance_to(began[1]) > TAP_SLIDE or Time.get_ticks_msec() - int(began[2]) > TAP_MSEC:
		return
	_on_slot_right_clicked(slot)


func _use_slot(slot_index: int) -> void:
	# fire slot_used for the key at this index, if anything is on it.
	# parent HUD subscribes and routes to inventoryscreen's use_item logic.
	if slot_index < 0 or slot_index >= slots.size():
		return

	var slot: HotbarSlot = slots[slot_index]
	if slot == null or slot.is_empty():
		return

	slot_used.emit(slot)
