# worldevents.gd - THE WORLD'S EVENTS (0.48.0), the WorldEvents autoload.
#
# The owner: "Treat events (double XP, double loot, forced stir, etc.) as their
# own feature area with a clean public contract". The SERVER holds them (the
# API's events/ package) and pays what they pay itself, at the kill. This file
# holds what the server says, from the broadcast poll every game already runs
# (characterhud.gd, _read_events()) - the contract's body, {"events": on now,
# "next": coming, "now": the server's clock} - for the HUD to show:
#
#   lines()       "Double XP - 2h 14m left", and "Next: Double Loot in 2d 4h"
#   apply()       hands back the events that began since the last poll, for
#                 the banner
#
# NOTHING HERE CHANGES WHAT A KILL PAYS. The multipliers are words on the
# screen; the XP and loot come from the server's own table, whatever this
# game believes. An event past its end is over on the screen at its end, and
# a server from before events (no "events") is no events.
extends Node


signal changed()

const KINDS := ["xp", "loot", "stir"]
# More than the server ever sends is somebody else's answer.
const MOST_ON := 10
const MOST_NEXT := 5
const NAME_LENGTH := 40
const DESCRIPTION_LENGTH := 160
# The server allows 1.25x to 3x; anything past 3 is not believed.
const MOST_TIMES := 3.0

# What the server last said, each event as the contract has it, checked.
var on_now: Array[Dictionary] = []
var coming: Array[Dictionary] = []
# The server's clock minus this one's, so a countdown is the server's.
var _clock_offset: int = 0


func apply(data: Variant) -> Array[Dictionary]:
	"""The poll's "events". Hands back the events on now that were not on at
	the last poll - for the HUD's banner, which skips the first poll itself."""
	var had: Array[int] = ids()
	var was: Array = [on_now.duplicate(true), coming.duplicate(true)]
	var said: Dictionary = data if data is Dictionary else {}
	on_now = _read_list(said.get("events"), MOST_ON)
	coming = _read_list(said.get("next"), MOST_NEXT)
	if _number(said.get("now")):
		_clock_offset = int(said.get("now")) - int(Time.get_unix_time_from_system())
	var began: Array[Dictionary] = []
	for event in on_now:
		if not had.has(int(event["id"])):
			began.append(event)
	if [on_now, coming] != was:
		changed.emit()
	return began


func clear() -> void:
	"""No events - the suite, or a server from before them."""
	var had: bool = not on_now.is_empty() or not coming.is_empty()
	on_now = []
	coming = []
	if had:
		changed.emit()


static func _number(value: Variant) -> bool:
	return value is int or value is float


func _read_list(list: Variant, most: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (list is Array):
		return out
	for entry in list:
		var event: Dictionary = read_event(entry)
		if not event.is_empty():
			out.append(event)
		if out.size() >= most:
			break
	return out


func read_event(entry: Variant) -> Dictionary:
	"""One event from the wire, checked: {} for anything that is not one."""
	if not (entry is Dictionary):
		return {}
	var said: Dictionary = entry
	var kind: String = str(said.get("kind", ""))
	if not KINDS.has(kind) or not _number(said.get("id")) or int(said.get("id")) <= 0 \
			or not _number(said.get("starts_at")) or not _number(said.get("ends_at")) \
			or int(said.get("ends_at")) <= int(said.get("starts_at")):
		return {}
	var multipliers: Dictionary = {}
	var given: Dictionary = said.get("multipliers") if said.get("multipliers") is Dictionary else {}
	for key in ["xp", "loot"]:
		if _number(given.get(key)):
			multipliers[key] = clampf(float(given.get(key)), 1.0, MOST_TIMES)
	var title: String = str(said.get("name", "")).strip_edges().left(NAME_LENGTH)
	return {
		"id": int(said.get("id")),
		"kind": kind,
		"name": title if title != "" else {"xp": "More XP", "loot": "More loot", "stir": "A land stirs"}[kind],
		"description": str(said.get("description", "")).strip_edges().left(DESCRIPTION_LENGTH),
		"starts_at": int(said.get("starts_at")),
		"ends_at": int(said.get("ends_at")),
		"land": clampi(int(said.get("land", 0)) if _number(said.get("land")) else 0, -1, Element.Type.WATER),
		"multipliers": multipliers,
	}


func now() -> int:
	"""The time on the server's clock, as near as this game knows it."""
	return int(Time.get_unix_time_from_system()) + _clock_offset


func ids() -> Array[int]:
	var out: Array[int] = []
	for event in on_now:
		out.append(int(event["id"]))
	return out


func active() -> Array[Dictionary]:
	"""The events on now - by the server's clock, so one past its end is gone
	from the screen at its end, before the next poll says so."""
	var at: int = now()
	var out: Array[Dictionary] = []
	for event in on_now:
		if int(event["starts_at"]) <= at and at < int(event["ends_at"]):
			out.append(event)
	return out


func next_up() -> Dictionary:
	"""The nearest event still to come, or {}."""
	var at: int = now()
	for event in coming:
		if int(event["starts_at"]) > at:
			return event
	return {}


func span_text(seconds: int) -> String:
	"""'2d 4h', '2h 14m', '14m', 'under a minute'."""
	if seconds < 60:
		return "under a minute"
	@warning_ignore("integer_division")
	var days: int = seconds / 86400
	@warning_ignore("integer_division")
	var hours: int = (seconds % 86400) / 3600
	@warning_ignore("integer_division")
	var minutes: int = (seconds % 3600) / 60
	if days > 0:
		return "%dd %dh" % [days, hours]
	if hours > 0:
		return "%dh %02dm" % [hours, minutes]
	return "%dm" % minutes


func lines() -> Array[String]:
	"""The HUD's lines: each event on now with its time left, then the next
	one to come. Empty when there is nothing to say."""
	var out: Array[String] = []
	var at: int = now()
	for event in active():
		out.append("%s - %s left" % [str(event["name"]), span_text(int(event["ends_at"]) - at)])
	var next: Dictionary = next_up()
	if not next.is_empty():
		out.append("Next: %s in %s" % [str(next["name"]), span_text(int(next["starts_at"]) - at)])
	return out
