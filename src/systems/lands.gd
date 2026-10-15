# lands.gd - THE STIRRING LANDS (0.46.0), the Lands autoload.
#
# The owner: "lets build it in my game if you think it will elavate it" - a
# world that changes on its own. Every few hours one of the seven lands (an
# element, Element.Type DARK to WATER) stirs. The SERVER picks it, and pays
# what it pays itself - more loot, more XP - at the kill (app.py, THE STIRRING
# LANDS). This file holds what the server says, from the broadcast poll every
# game already runs (characterhud.gd, _read_world()), and answers the two
# questions the game applies itself, both in Player.damage_taken():
#
#   hit_scale(element)     how much harder a hit of this element lands
#   resist_scale(element)  how much more resistance to it counts
#
# and, since the owner's "i did not notice dps change on enemies or anything",
# two more for the monsters themselves, in BaseEnemy - with the glow under
# their feet (stirglow.gd) that says which ones they are:
#
#   raised_max_hp(max, element)  the health a monster of this land has
#   speed_scale(element)         how much faster it moves
#
# All are 1.0 (or the health as it was) for any element that is not stirring -
# and for everything when
# nothing is, which is also what this says when the server cannot be heard:
# a stir whose end has passed by STALE_SECONDS is over, whatever was last
# heard. A world that cannot be reached never makes the game harder.
#
# Players' own damage never changes: "elements defend; they do not change what
# anybody hits for" (GameConstants, ELEMENT RESISTANCE).
extends Node


signal changed()

# Past the end of a stir by this much with no word from the server, it is over.
const STALE_SECONDS := 60

# What the server last said. element 0: nothing stirs.
var tick: int = 0
var element: int = 0
var started_at: int = 0
var ends_at: int = 0
# How much harder its monsters hit (0.25 is 25%), how much resistance to it
# counts (1.5 is half again), and - for the words only - the loot and XP the
# server pays (1.5 is half again as often; 0.25 is 25% more).
var hit: float = 0.0
# How much more health its monsters have (0.5 is 50%), and how much faster
# they move (0.15 is 15%).
var health: float = 0.0
var speed: float = 0.0
var resist: float = 1.0
var bags: float = 1.0
var xp: float = 0.0
# The server's clock minus this one's, so a countdown is the server's.
var _clock_offset: int = 0


func apply(data: Variant) -> bool:
	"""What the poll's "world" says. True if a different stir began - a new
	land, or the same one again as a new tick - so the HUD can announce it."""
	var before := [tick, element]
	var was := [tick, element, ends_at, hit, health, speed, resist, bags, xp]
	var said: Dictionary = data if data is Dictionary else {}
	var land: int = int(said.get("element", 0)) if _number(said.get("element")) else 0
	if land < Element.Type.DARK or land > Element.Type.WATER:
		_clear()
	else:
		element = land
		tick = maxi(0, int(said.get("tick", 0))) if _number(said.get("tick")) else 0
		started_at = int(said.get("started_at", 0)) if _number(said.get("started_at")) else 0
		ends_at = int(said.get("ends_at", 0)) if _number(said.get("ends_at")) else 0
		hit = clampf(float(said.get("hit", 0.0)), 0.0, 1.0) if _number(said.get("hit")) else 0.0
		health = clampf(float(said.get("health", 0.0)), 0.0, 2.0) if _number(said.get("health")) else 0.0
		speed = clampf(float(said.get("speed", 0.0)), 0.0, 0.5) if _number(said.get("speed")) else 0.0
		resist = clampf(float(said.get("resist", 1.0)), 1.0, 2.0) if _number(said.get("resist")) else 1.0
		bags = clampf(float(said.get("bags", 1.0)), 1.0, 3.0) if _number(said.get("bags")) else 1.0
		xp = clampf(float(said.get("xp", 0.0)), 0.0, 1.0) if _number(said.get("xp")) else 0.0
		if _number(said.get("now")):
			_clock_offset = int(said.get("now")) - int(Time.get_unix_time_from_system())
	if [tick, element, ends_at, hit, health, speed, resist, bags, xp] != was:
		changed.emit()
	return element != 0 and [tick, element] != before


func clear() -> void:
	"""Nothing stirs - logging out, or the suite."""
	var had: bool = element != 0
	_clear()
	if had:
		changed.emit()


func _clear() -> void:
	tick = 0
	element = 0
	started_at = 0
	ends_at = 0
	hit = 0.0
	health = 0.0
	speed = 0.0
	resist = 1.0
	bags = 1.0
	xp = 0.0


static func _number(value: Variant) -> bool:
	return value is int or value is float


func now() -> int:
	"""The time on the server's clock, as near as this game knows it."""
	return int(Time.get_unix_time_from_system()) + _clock_offset


func stirring() -> int:
	"""The land stirring now, or 0. A stir long past its end is over."""
	if element == 0 or (ends_at > 0 and now() > ends_at + STALE_SECONDS):
		return 0
	return element


func hit_scale(of_element: int) -> float:
	"""A hit of this element is multiplied by this: 1 + hit for the stirring
	land, 1 for everything else."""
	return 1.0 + hit if of_element != Element.Type.NONE and of_element == stirring() else 1.0


func resist_scale(of_element: int) -> float:
	"""Resistance to this element counts this many times (still held to
	RESIST_CAP): `resist` for the stirring land, 1 for everything else."""
	return resist if of_element != Element.Type.NONE and of_element == stirring() else 1.0


func raised_max_hp(max_hp: int, of_element: int) -> int:
	"""The health a monster of this element with `max_hp` has: `health` more
	for the stirring land's, as it was for every other. The combat books
	(combatbook.py) take a stirred monster's word for a maximum above the
	catalogue's - never one below it."""
	if of_element == Element.Type.NONE or of_element != stirring() or health <= 0.0:
		return max_hp
	return max_hp + roundi(float(max_hp) * health)


func speed_scale(of_element: int) -> float:
	"""A monster of this element moves this many times as fast: 1 + speed for
	the stirring land's, 1 for every other."""
	return 1.0 + speed if of_element != Element.Type.NONE and of_element == stirring() else 1.0


func seconds_left() -> int:
	return maxi(0, ends_at - now()) if stirring() != 0 else 0


func time_text(seconds: int) -> String:
	"""'2h 14m', '14m', 'under a minute'."""
	if seconds < 60:
		return "under a minute"
	@warning_ignore("integer_division")
	var hours: int = seconds / 3600
	@warning_ignore("integer_division")
	var minutes: int = (seconds % 3600) / 60
	if hours == 0:
		return "%dm" % minutes
	return "%dh %02dm" % [hours, minutes]


func land_name() -> String:
	return Element.name_for(stirring()).capitalize() if stirring() != 0 else ""


func line() -> String:
	"""The HUD's line: 'The Fire lands stir - 2h 14m left', or '' for none."""
	if stirring() == 0:
		return ""
	return "The %s lands stir - %s left" % [land_name(), time_text(seconds_left())]


func effects_line() -> String:
	"""What it does, from the numbers the server sent: 'Fire monsters hit 25%
	harder, have 50% more health, move 15% faster and drop loot 1.5x as often;
	fire resistance counts 1.5x.'"""
	if stirring() == 0:
		return ""
	var land: String = land_name()
	var does: Array[String] = []
	if hit > 0.0:
		does.append("hit %d%% harder" % roundi(hit * 100.0))
	if health > 0.0:
		does.append("have %d%% more health" % roundi(health * 100.0))
	if speed > 0.0:
		does.append("move %d%% faster" % roundi(speed * 100.0))
	if bags > 1.0:
		does.append("drop loot %sx as often" % _times(bags))
	if xp > 0.0:
		does.append("give %d%% more XP" % roundi(xp * 100.0))
	var parts: Array[String] = []
	if not does.is_empty():
		var joined: String = does[0] if does.size() == 1 \
			else ", ".join(does.slice(0, does.size() - 1)) + " and " + does[does.size() - 1]
		parts.append("%s monsters %s" % [land, joined])
	if resist > 1.0:
		parts.append("%s resistance counts %sx" % [land.to_lower(), _times(resist)])
	return ("; ".join(parts) + ".") if not parts.is_empty() else "%s is stirring." % land


static func _times(value: float) -> String:
	"""1.5 -> '1.5', 2.0 -> '2', 1.25 -> '1.25'."""
	var text: String = "%.2f" % value
	while text.ends_with("0"):
		text = text.substr(0, text.length() - 1)
	return text.trim_suffix(".")
