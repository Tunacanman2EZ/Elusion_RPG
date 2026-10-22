# foodbuff.gd - THE MEAL YOU ARE STILL FULL OF (0.74.0), the FoodBuff autoload.
#
# The owner: meals that "heal more and give a short buff". The SERVER holds the
# buff. /api/character/consume records it when a meal with one is eaten - one at
# a time, a new meal replacing the last - and says what is in force afterwards:
# {"item_id", "kind" (the BuffKind's NAME), "amount", "ends_at" (unix seconds)},
# or null. The character the game loads at login carries the same thing
# (serverstorage.gd puts it on the slot as "food_buff"). This file holds the
# last thing the server said, for:
#
#   player.gd   the four numbers a meal can move: damage (MIGHT, a percent,
#               multiplied in get_damage_multiplier() the way a Fury amulet's
#               is), armour (GUARD, added to what is worn in damage_taken()),
#               max health (VIGOUR) and max mana (WISDOM), both added in
#               _recompute_max_stats() beside the amulets'
#   the HUD     the meal's icon and the time left, its name on hover
#
# AN AUTOLOAD, NOT A MEMBER OF THE PLAYER, for the reason the map and the active
# pet's id are not one: the player node is freed at every door, and a buff held
# on it would be gone in the next room. This is never freed, so a meal eaten in
# town is still working in the Field.
#
# NOTHING HERE DECIDES WHETHER A KILL STANDS. The server bounds every kill by its
# own copy of the buff (combat_bounds()); what this moves is the hit the client
# throws and the bar it draws, and both have to agree with the server or the
# books refuse the kill. So the buff is only ever the server's - set from what
# it answered, never from the item a click named.
extends Node


# The buff began, changed, was replaced or ended. player.gd moves its maxima on
# it (refresh_food_stats()), and the HUD redraws its chip and its bars.
signal changed()

# More than the catalogue's biggest meal gives, by a distance, is somebody
# else's answer and is not believed. The largest today are +150 max health and
# +110 max mana; the longest lasts half an hour.
const MOST_AMOUNT := 10000
const MOST_SECONDS := 86400

# How often a buff is looked at to see whether it has ended, in seconds. The
# stats already read it live (is_active() compares the clock), so this is only
# how soon after the end the maxima come down and the chip goes.
const TICK := 1.0

var item_id: String = ""
var kind: int = ItemData.BuffKind.NONE
var amount: int = 0
var ends_at: int = 0

var _tick: float = 0.0


func _process(delta: float) -> void:
	if kind == ItemData.BuffKind.NONE:
		return
	_tick += delta
	if _tick < TICK:
		return
	_tick = 0.0
	# OVER ON ITS OWN CLOCK. The server says when it ends once, at the meal;
	# nothing tells this game again, so the end is noticed here and said.
	if not is_active():
		clear()


# =============================================================================
# WHAT THE SERVER SAID
# =============================================================================

func read_buff(wire: Variant, at: int) -> Dictionary:
	"""One buff from the wire, checked: {} for null, for anything that is not
	one, and for one already over at `at`."""
	if not (wire is Dictionary):
		return {}
	var said: Dictionary = wire
	var kind_name: String = str(said.get("kind", "")).strip_edges().to_upper()
	var named: int = ItemData.BuffKind.keys().find(kind_name)
	var how_much: Variant = said.get("amount")
	var until: Variant = said.get("ends_at")
	if named <= int(ItemData.BuffKind.NONE) or not (how_much is int or how_much is float) \
			or not (until is int or until is float):
		return {}
	var id: String = str(said.get("item_id", "")).strip_edges()
	if id == "" or int(how_much) <= 0 or int(how_much) > MOST_AMOUNT:
		return {}
	if int(until) <= at or int(until) > at + MOST_SECONDS:
		return {}
	return {"item_id": id, "kind": named, "amount": int(how_much), "ends_at": int(until)}


func adopt(wire: Variant) -> bool:
	"""What the server says is in force now - a consume answer's food_buff - in
	place of whatever was. Null, or one already over, is no buff. True when
	there is one afterwards.

	WRITTEN TO THE SLOT TOO, so a character left by Switch Character and picked
	again comes back with the meal it had rather than the one it logged in
	with: the slot is what adopt_for_character() reads, and nothing reloads it
	from the server between the two."""
	_remember(wire)
	return _take(read_buff(wire, now()))


func adopt_for_character(index: int) -> bool:
	"""The meal the chosen character was full of when it was loaded - the
	character select's Play. Nothing written back: it is the slot's own."""
	var slots: Array = CharacterData.character_slots
	var slot: Variant = slots[index] if index >= 0 and index < slots.size() else null
	var wire: Variant = (slot as Dictionary).get("food_buff") if slot is Dictionary else null
	return _take(read_buff(wire, now()))


func _take(read: Dictionary) -> bool:
	if read.is_empty():
		clear()
		return false
	var before: Array = [item_id, kind, amount, ends_at]
	item_id = str(read["item_id"])
	kind = int(read["kind"])
	amount = int(read["amount"])
	ends_at = int(read["ends_at"])
	_tick = 0.0
	if [item_id, kind, amount, ends_at] != before:
		changed.emit()
		# AND THE SERVER'S BOOKS HEAR OF IT NOW, as after an equip
		# (CharacterData's): presence.py bounds every hit by what the ticket
		# says this fighter is, a ticket is renewed once a minute, and a Might
		# meal eaten mid-fight would be read against the old one until then.
		var link: Node = get_node_or_null(^"/root/Presence")
		if link != null and link.has_method("renew_soon"):
			link.renew_soon()
	return true


func clear() -> void:
	"""No buff. Logout, Switch Character, and a buff that has run out."""
	var had: bool = kind != ItemData.BuffKind.NONE
	item_id = ""
	kind = ItemData.BuffKind.NONE
	amount = 0
	ends_at = 0
	_tick = 0.0
	if had:
		changed.emit()


func _remember(wire: Variant) -> void:
	var slots: Array = CharacterData.character_slots
	var index: int = CharacterData.active_character_index
	if index < 0 or index >= slots.size() or not (slots[index] is Dictionary):
		return
	var kept: Variant = null
	if wire is Dictionary:
		kept = (wire as Dictionary).duplicate()
	(slots[index] as Dictionary)["food_buff"] = kept


# =============================================================================
# WHAT IT IS WORTH, NOW
# =============================================================================

func now() -> int:
	"""The server's clock as near as this game knows it - the same one the
	events' countdowns run on - because ends_at is the server's second."""
	return WorldEvents.now()


func is_active() -> bool:
	return kind != ItemData.BuffKind.NONE and now() < ends_at


func seconds_left() -> int:
	return maxi(ends_at - now(), 0) if is_active() else 0


func _of(which: int) -> int:
	return amount if kind == which and is_active() else 0


func damage_percent() -> int:
	return _of(ItemData.BuffKind.MIGHT)


func damage_factor() -> float:
	"""1.05 for a +5% meal. Through the same floor as a Fury amulet, so a bad
	number can never make a hit heal."""
	return PlayerStats.gear_damage_factor(damage_percent())


func armour() -> int:
	return _of(ItemData.BuffKind.GUARD)


func max_hp() -> int:
	return _of(ItemData.BuffKind.VIGOUR)


func max_mana() -> int:
	return _of(ItemData.BuffKind.WISDOM)


# =============================================================================
# WHAT THE HUD SAYS
# =============================================================================

func item() -> ItemData:
	"""The meal, or null for an id this catalogue does not know - a server a
	version ahead. has_item() first: get_item() hands back a placeholder."""
	if item_id == "" or not ItemRegistry.has_item(item_id):
		return null
	return ItemRegistry.get_item(item_id)


func clock_text(seconds: int) -> String:
	"""Minutes and seconds: "14:59", "0:07". A meal never lasts an hour, and one
	that did would read "75:00" rather than wrap."""
	var left: int = maxi(seconds, 0)
	@warning_ignore("integer_division")
	var minutes: int = left / 60
	return "%d:%02d" % [minutes, left % 60]


# THE AMULETS' COLOURS, because the families are the same four stats: Fury's
# crimson for damage, Ward's purple for armour, Vitality's green for health and
# Arcana's blue for mana - lightened to read as text on the dark windows. The
# cooking window's buff line and the HUD's chip both wear them, so a meal's
# colour on the fire is its colour on the screen while it lasts.
const BUFF_COLOURS := {
	ItemData.BuffKind.MIGHT: Color(0.98, 0.52, 0.45),
	ItemData.BuffKind.GUARD: Color(0.78, 0.62, 0.98),
	ItemData.BuffKind.VIGOUR: Color(0.55, 0.88, 0.5),
	ItemData.BuffKind.WISDOM: Color(0.5, 0.72, 1.0),
}
const NO_BUFF_COLOUR := Color(0.9, 0.85, 0.75)


func colour_for(which: int) -> Color:
	return BUFF_COLOURS.get(which, NO_BUFF_COLOUR)


func effect_text() -> String:
	"""What it adds, in the tooltip's words for the same stat on gear: "+45 max
	health". "" with no buff."""
	if not is_active() or not ItemData.BUFF_WORDS.has(kind):
		return ""
	return String(ItemData.BUFF_WORDS[kind]) % amount


func describe() -> String:
	"""The chip's tooltip: "Bone Broth: +45 max health, 14:59 left"."""
	if not is_active():
		return ""
	var meal: ItemData = item()
	var title: String = meal.display_name if meal != null else item_id
	return "%s: %s, %s left" % [title, effect_text(), clock_text(seconds_left())]
