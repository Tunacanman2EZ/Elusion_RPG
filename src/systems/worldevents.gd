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
#   shown()       the events on now that pay: one Double XP, not two (0.50.1)
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
	# ONLY ONE THAT PAYS IS NEWS: two Double XPs set together begin together,
	# and the second is not news; nor is one that only runs a Double XP on
	# past its end.
	var began: Array[Dictionary] = []
	for event in shown():
		if had.has(int(event["id"])):
			continue
		var already: bool = false
		for prior in on_now:
			if had.has(int(prior["id"])) and pays_as_much(prior, event):
				already = true
				break
		if not already:
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


func shown() -> Array[Dictionary]:
	"""The events on now that change what a kill pays: active() less any that
	another of its kind outdoes (outdoes()).

	TWO DOUBLE XPS ARE NOT 4x. The server pays the bigger of each kind, never
	the product (events/services.py, kill_scales()), and while two stir events
	overlap the one that began last stirs (forced_stir()). Two lines both
	saying "Double XP - 2h 59m left" told every player otherwise. So the
	screen shows the one that pays, and one it hid comes up if it outlasts
	it."""
	var on: Array[Dictionary] = active()
	var out: Array[Dictionary] = []
	for event in on:
		var beaten: bool = false
		for other in on:
			if outdoes(other, event):
				beaten = true
				break
		if not beaten:
			out.append(event)
	return out


func outdoes(a: Dictionary, b: Dictionary) -> bool:
	"""Whether `a`, on at the same time as `b`, leaves `b` nothing to add.

	XP or loot: `a` covers every monster `b` does (every monster, or the same
	land) and pays more; or pays the same and covers more; or the same of
	both and ends later (its time left is the true one); or ends together
	and was set first. A stir: `a` began later, as the server has it. Never
	both ways round, so of any two the same, one is always shown."""
	if str(a["kind"]) != str(b["kind"]) or int(a["id"]) == int(b["id"]):
		return false
	if str(a["kind"]) == "stir":
		return int(a["starts_at"]) > int(b["starts_at"]) \
			or (int(a["starts_at"]) == int(b["starts_at"]) and int(a["id"]) > int(b["id"]))
	var a_land: int = int(a["land"])
	var b_land: int = int(b["land"])
	if a_land != 0 and a_land != b_land:
		return false
	var kind: String = str(a["kind"])
	var a_times: float = float((a["multipliers"] as Dictionary).get(kind, 1.0))
	var b_times: float = float((b["multipliers"] as Dictionary).get(kind, 1.0))
	if not is_equal_approx(a_times, b_times):
		return a_times > b_times
	if a_land != b_land:
		return true
	if int(a["ends_at"]) != int(b["ends_at"]):
		return int(a["ends_at"]) > int(b["ends_at"])
	return int(a["id"]) < int(b["id"])


func pays_as_much(a: Dictionary, b: Dictionary) -> bool:
	"""Whether xp or loot event `a` covers every monster `b` does and pays at
	least as much - so `b` beginning while `a` is on changes nothing."""
	if str(a["kind"]) != str(b["kind"]) or str(a["kind"]) == "stir":
		return false
	if int(a["land"]) != 0 and int(a["land"]) != int(b["land"]):
		return false
	var kind: String = str(a["kind"])
	var a_times: float = float((a["multipliers"] as Dictionary).get(kind, 1.0))
	var b_times: float = float((b["multipliers"] as Dictionary).get(kind, 1.0))
	return a_times > b_times or is_equal_approx(a_times, b_times)


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
	"""The HUD's lines: each event on now that pays (shown()) with its time
	left, then the next one to come. Empty when there is nothing to say."""
	var out: Array[String] = []
	var at: int = now()
	for event in shown():
		out.append("%s - %s left" % [str(event["name"]), span_text(int(event["ends_at"]) - at)])
	var next: Dictionary = next_up()
	if not next.is_empty():
		out.append("Next: %s in %s" % [str(next["name"]), span_text(int(next["starts_at"]) - at)])
	return out
