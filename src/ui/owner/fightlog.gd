# fightlog.gd - THE FIGHT LOG (game 0.82.0): every fight the damage meter
# hears, kept and compared.
#
# THE OWNER, 25 Oct: "i need to document the progression of battles to fine
# tune my system based off that experience maybe log 3 battles ... the main
# point is statistics that i can improve upon".
#
# A FIGHT STARTS WITH ITS FIRST HIT AND ENDS AFTER QUIET_SECONDS WITH NONE.
# While it runs, every hit in the server's reports (damagemeter.gd) is added
# to its player's second-by-second line, and every monster it landed on is
# timed from its first hit to its death ("k" in a report, 0.82.0). When it
# ends, finish() turns it into a record: how long, who, how hard - total, DPS,
# best PEAK_SECONDS, hits, average and biggest hit, held, limit - what died and
# how long each took, and the timeline. The last KEEP are saved (SAVE_PATH),
# each also as a CSV beside it for a spreadsheet; any COMPARE_MOST of them on
# the meter's Fights page - one GroupChart with the group's DPS through each,
# and a table of what changed.
#
# ONLY WHAT THE METER HEARS: the server reports to an open meter, so a fight
# fought with it shut is not logged. Pure functions on dictionaries, for the
# test runner; the only side effects are load_log(), save_log() and save_csv().
extends RefCounted

const QUIET_SECONDS := 10.0
const KEEP := 10
const COMPARE_MOST := 3
const PEAK_SECONDS := 5
# THE ENEMY METER (0.83.0): health under this share of its most is danger.
const DANGER_SHARE := 0.25
const FOLDER := "user://fights"
const SAVE_PATH := "user://fights/log.json"


static func begin(now: float, unix: float, area: String) -> Dictionary:
	return {"t0": now, "last": now, "unix": unix, "area": area, "players": {}, "monsters": {}, "events": []}


static func add(fight: Dictionary, report: Dictionary, now: float) -> void:
	"""One report's hits and deaths, heard at `now`."""
	if str(report.get("a", "")) != "":
		fight["area"] = str(report["a"])
	var players: Dictionary = fight["players"]
	var monsters: Dictionary = fight["monsters"]
	var dealers: Variant = report.get("who", {})
	var named: Variant = report.get("m", {})
	if named is Dictionary:
		for key in named:
			var info: Variant = named[key]
			if not (info is Array) or (info as Array).size() < 3:
				continue
			var m: Dictionary = monsters.get(str(key), {"enemy": str(info[0]), "name": str(info[1]),
				"max_hp": 0, "boss": false, "first": -1.0, "last": -1.0, "damage": 0, "killed": -1.0})
			m["max_hp"] = maxi(int(m["max_hp"]), int(info[2]))
			monsters[str(key)] = m
	var at: float = now - float(fight["t0"])
	var second: int = maxi(int(at), 0)
	var hits: Variant = report.get("h", [])
	var any: bool = false
	if hits is Array:
		for hit in hits:
			if not (hit is Array) or (hit as Array).size() < 4:
				continue
			any = true
			var id: String = str(int(hit[0]))
			var booked: int = maxi(int(hit[1]), 0)
			var p: Dictionary = players.get(id, new_player())
			if dealers is Dictionary and dealers.get(id) is Array and (dealers[id] as Array).size() >= 5:
				var d: Array = dealers[id]
				p["name"] = str(d[0])
				p["cls"] = str(d[1])
				p["lvl"] = int(d[2])
				p["allowed"] = int(d[3])
			p["total"] = int(p["total"]) + booked
			p["hits"] = int(p["hits"]) + 1
			p["biggest"] = maxi(int(p["biggest"]), booked)
			p["held"] = int(p["held"]) + maxi(int(hit[2]) - booked, 0)
			var line: Dictionary = p["line"]
			line[second] = int(line.get(second, 0)) + booked
			# Its element (0.82.0, the sixth of a hit): -1 when the server could not say.
			var element: String = str(int(hit[5])) if (hit as Array).size() >= 6 else "-1"
			var elements: Dictionary = p["elements"]
			elements[element] = int(elements.get(element, 0)) + booked
			players[id] = p
			if (hit as Array).size() >= 5 and monsters.has(str(int(hit[4]))):
				var m: Dictionary = monsters[str(int(hit[4]))]
				if float(m["first"]) < 0.0:
					m["first"] = at
				m["last"] = at
				m["damage"] = int(m["damage"]) + booked
				m["boss"] = bool(m["boss"]) or int(hit[3]) != 0
	# DAMAGE TAKEN (0.83.0, "tk"): each player's second - taken, healed,
	# regen, biggest hit, lowest health and its most, taken by element. A player
	# who took something joins the fight; one already in it has every second
	# kept, quiet or not, so their health runs through it.
	var taken: Variant = report.get("tk", {})
	if taken is Dictionary:
		for key in taken:
			var row: Variant = taken[key]
			if not (row is Array) or (row as Array).size() < 6:
				continue
			var id: String = str(int(str(key)))
			var hurt: int = maxi(int(row[0]), 0)
			if hurt <= 0 and not players.has(id):
				continue
			var p: Dictionary = players.get(id, new_player())
			if dealers is Dictionary and dealers.get(id) is Array and (dealers[id] as Array).size() >= 5:
				var d: Array = dealers[id]
				p["name"] = str(d[0])
				p["cls"] = str(d[1])
				p["lvl"] = int(d[2])
				p["allowed"] = int(d[3])
			if not p.has("taken"):
				_add_taken_fields(p)
			p["taken"] = int(p["taken"]) + hurt
			p["healed"] = int(p["healed"]) + maxi(int(row[1]), 0)
			p["regen"] = int(p["regen"]) + maxi(int(row[2]), 0)
			p["biggest_taken"] = maxi(int(p["biggest_taken"]), int(row[3]))
			(p["tline"] as Dictionary)[second] = int((p["tline"] as Dictionary).get(second, 0)) + hurt
			(p["hline"] as Dictionary)[second] = int((p["hline"] as Dictionary).get(second, 0)) \
				+ maxi(int(row[1]), 0) + maxi(int(row[2]), 0)
			if int(row[5]) > 0 and int(row[4]) >= 0:
				var share: float = clampf(float(row[4]) / float(row[5]), 0.0, 1.0)
				var health: Dictionary = p["health"]
				health[second] = minf(float(health.get(second, 1.0)), share)
			if (row as Array).size() >= 7 and row[6] is Dictionary:
				var took: Dictionary = p["took"]
				for element in row[6]:
					took[str(int(str(element)))] = int(took.get(str(int(str(element))), 0)) + maxi(int(row[6][element]), 0)
			players[id] = p
			if hurt > 0:
				any = true
	if any:
		fight["last"] = now
	var changes: Variant = report.get("e", [])
	if changes is Array:
		for change in changes:
			if change is Array and (change as Array).size() >= 3:
				if str(change[0]) == "fell" and players.has(str(int(change[1]))):
					var down: Dictionary = players[str(int(change[1]))]
					down["deaths"] = int(down.get("deaths", 0)) + 1
				var text: String = event_text(str(change[0]), int(change[1]), change[2], monsters)
				if text != "":
					(fight["events"] as Array).append([at, str(change[0]), text])
	var deaths: Variant = report.get("k", [])
	if deaths is Array:
		for death in deaths:
			if death is Array and (death as Array).size() >= 2 and monsters.has(str(int(death[0]))):
				var m: Dictionary = monsters[str(int(death[0]))]
				if float(m["killed"]) < 0.0 and float(m["first"]) >= 0.0:
					m["killed"] = at
					m["boss"] = bool(m["boss"]) or int(death[1]) != 0


static func new_player() -> Dictionary:
	var p: Dictionary = {"name": "", "cls": "", "lvl": 0, "allowed": 0,
		"total": 0, "hits": 0, "biggest": 0, "held": 0, "line": {}, "elements": {}}
	_add_taken_fields(p)
	return p


static func _add_taken_fields(p: Dictionary) -> void:
	p.merge({"taken": 0, "healed": 0, "regen": 0, "biggest_taken": 0, "deaths": 0,
		"tline": {}, "hline": {}, "health": {}, "took": {}})


static func health_line(health: Dictionary, seconds: int) -> Array:
	"""A player's lowest health each second, 0-1, carried over the seconds
	nothing was heard (and back to the start from the first heard); [] when
	none ever was."""
	var out: Array = []
	if health.is_empty():
		return out
	out.resize(seconds)
	out.fill(-1.0)
	for key in health:
		var i: int = clampi(int(key), 0, seconds - 1)
		out[i] = float(health[key]) if float(out[i]) < 0.0 else minf(float(out[i]), float(health[key]))
	var last: float = -1.0
	for i in seconds:
		if float(out[i]) >= 0.0:
			last = float(out[i])
		elif last >= 0.0:
			out[i] = last
	var first: float = -1.0
	for i in range(seconds - 1, -1, -1):
		if float(out[i]) >= 0.0:
			first = float(out[i])
		else:
			out[i] = first
	return out


static func event_text(kind: String, subject: int, detail: Variant, monsters: Dictionary) -> String:
	"""A line for something that changed the fight, or "" for a kind not
	known (presence.py METER_EVENTS)."""
	match kind:
		"grew", "shrank":
			var who: String = str((monsters.get(str(subject), {}) as Dictionary).get("name", "The boss"))
			var after: float = float(detail[1]) if detail is Array and (detail as Array).size() >= 2 else 0.0
			return "%s %s to %s" % [who, kind, short(after)]
		"joined", "left", "fell":
			var named: String = str(detail) if str(detail) != "" else "A player"
			return "%s %s" % [named, kind]
	return ""


static func uptime_of(line: Array) -> float:
	"""The share of a player's own time in the fight - first hit to last -
	in which it dealt damage."""
	var first: int = -1
	var last: int = -1
	var active: int = 0
	for i in line.size():
		if int(line[i]) > 0:
			if first < 0:
				first = i
			last = i
			active += 1
	return 0.0 if first < 0 else float(active) / float(last - first + 1)


static func steadiness_of(line: Array) -> float:
	"""How evenly a player's damage came, the seconds it dealt any: 1 /
	(1 + the spread over the average). 100% is the same every second; 50% is a
	spread as big as the average - damage that lives on a few big seconds."""
	var values: Array = line.filter(func(v: Variant) -> bool: return int(v) > 0)
	if values.size() < 2:
		return 1.0
	var mean: float = 0.0
	for v in values:
		mean += float(v)
	mean /= float(values.size())
	var spread: float = 0.0
	for v in values:
		spread += (float(v) - mean) * (float(v) - mean)
	spread = sqrt(spread / float(values.size()))
	return 1.0 / (1.0 + spread / maxf(mean, 1.0))


static func quiet(fight: Dictionary, now: float) -> bool:
	return not fight.is_empty() and now - float(fight["last"]) >= QUIET_SECONDS


static func peak(line: Array) -> float:
	"""The best PEAK_SECONDS of a second-by-second line, as damage a second."""
	var best: int = 0
	var running: int = 0
	for i in line.size():
		running += int(line[i])
		if i >= PEAK_SECONDS:
			running -= int(line[i - PEAK_SECONDS])
		best = maxi(best, running)
	return float(best) / float(PEAK_SECONDS)


static func finish(fight: Dictionary) -> Dictionary:
	"""The fight as a record to keep, or {} when nobody hit anything."""
	if fight.is_empty() or (fight["players"] as Dictionary).is_empty():
		return {}
	var seconds: int = maxi(1, int(float(fight["last"]) - float(fight["t0"])) + 1)
	var rows: Array = []
	var timeline: Dictionary = {}
	var group: Array = []
	group.resize(seconds)
	group.fill(0)
	var total: int = 0
	var taken_lines: Dictionary = {}
	var heal_lines: Dictionary = {}
	var health_lines: Dictionary = {}
	for id in fight["players"]:
		var p: Dictionary = fight["players"][id]
		var line: Array = []
		line.resize(seconds)
		line.fill(0)
		for second in p["line"]:
			var i: int = clampi(int(second), 0, seconds - 1)
			line[i] = int(line[i]) + int(p["line"][second])
			group[i] = int(group[i]) + int(p["line"][second])
		timeline[str(id)] = line
		var tline: Array = _seconds_of(p.get("tline", {}), seconds)
		var hline: Array = _seconds_of(p.get("hline", {}), seconds)
		var health: Array = health_line(p.get("health", {}), seconds)
		taken_lines[str(id)] = tline
		heal_lines[str(id)] = hline
		health_lines[str(id)] = health
		var danger: int = 0
		var lowest: float = -1.0
		for h in health:
			if float(h) >= 0.0:
				lowest = float(h) if lowest < 0.0 else minf(lowest, float(h))
				if float(h) < DANGER_SHARE:
					danger += 1
		var took: Array = []
		for key in p.get("took", {}):
			took.append([int(key), int(p["took"][key])])
		took.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
		total += int(p["total"])
		var dps: float = float(p["total"]) / float(seconds)
		var elements: Array = []
		for key in p.get("elements", {}):
			elements.append([int(key), int(p["elements"][key])])
		elements.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
		rows.append({
			"id": int(id), "name": str(p["name"]) if str(p["name"]) != "" else "player %s" % str(id),
			"cls": str(p["cls"]), "lvl": int(p["lvl"]), "allowed": int(p["allowed"]),
			"total": int(p["total"]), "dps": dps, "peak": peak(line), "hits": int(p["hits"]),
			"avg": float(p["total"]) / maxf(1.0, float(p["hits"])), "biggest": int(p["biggest"]),
			"held": int(p["held"]), "limit": dps / float(p["allowed"]) if int(p["allowed"]) > 0 else -1.0,
			"uptime": uptime_of(line), "steady": steadiness_of(line), "elements": elements,
			# DAMAGE TAKEN (0.83.0). lowest -1: no health heard.
			"taken": int(p.get("taken", 0)), "taken_ps": float(p.get("taken", 0)) / float(seconds),
			"biggest_taken": int(p.get("biggest_taken", 0)), "healed": int(p.get("healed", 0)),
			"regen": int(p.get("regen", 0)), "lowest": lowest, "danger": danger,
			"deaths": int(p.get("deaths", 0)), "took": took,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["total"]) > int(b["total"]) or (int(a["total"]) == int(b["total"]) and int(a["id"]) < int(b["id"])))
	var kills: Array = []
	for key in fight["monsters"]:
		var m: Dictionary = fight["monsters"][key]
		if float(m["killed"]) >= 0.0:
			kills.append({"name": str(m["name"]), "enemy": str(m["enemy"]), "boss": bool(m["boss"]),
				"max_hp": int(m["max_hp"]), "damage": int(m["damage"]), "at": float(m["killed"]),
				"seconds": maxf(1.0, float(m["killed"]) - float(m["first"]) + 1.0)})
	kills.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (bool(a["boss"]) and not bool(b["boss"])) or (bool(a["boss"]) == bool(b["boss"])
			and float(a["seconds"]) > float(b["seconds"])))
	var uptime: float = 0.0
	var steady: float = 0.0
	for row in rows:
		uptime += float(row["uptime"])
		steady += float(row["steady"])
	var events: Array = []
	for e in fight.get("events", []):
		events.append({"at": float(e[0]), "kind": str(e[1]), "text": str(e[2])})
	return {
		"uptime": uptime / float(rows.size()), "steady": steady / float(rows.size()), "events": events,
		# THE ID IS THE START IN MILLISECONDS: Reset can end one fight and the
		# next hit start another inside the same second.
		"id": int(round(float(fight["unix"]) * 1000.0)),
		"when": Time.get_datetime_string_from_unix_time(int(fight["unix"]), true),
		"area": str(fight["area"]), "seconds": seconds, "total": total, "dps": float(total) / float(seconds),
		"peak": peak(group), "players": rows, "kills": kills, "timeline": timeline,
		"taken_timeline": taken_lines, "heal_timeline": heal_lines, "health_timeline": health_lines,
	}


static func _seconds_of(by_second: Dictionary, seconds: int) -> Array:
	var out: Array = []
	out.resize(seconds)
	out.fill(0)
	for key in by_second:
		var i: int = clampi(int(key), 0, seconds - 1)
		out[i] = int(out[i]) + int(by_second[key])
	return out


static func clock(seconds: float) -> String:
	var whole: int = int(seconds)
	return "%d:%02d" % [int(whole / 60.0), whole % 60]


static func short(value: float) -> String:
	var v: float = absf(value)
	if v >= 1000000.0:
		return "%.1fM" % (value / 1000000.0)
	if v >= 10000.0:
		return "%.1fk" % (value / 1000.0)
	if v >= 1000.0:
		return "%.2fk" % (value / 1000.0)
	return str(int(round(value)))


static func boss_kill(record: Dictionary) -> Dictionary:
	"""The record's first boss kill (the longest, when several), or {}."""
	for kill in record.get("kills", []):
		if bool(kill["boss"]):
			return kill
	return {}


static func headline(record: Dictionary) -> String:
	"""One line for the list of fights."""
	var line: String = "%s  %s  %s  %d player%s  %s DPS" % [str(record["when"]).substr(5, 11),
		str(record["area"]), clock(float(record["seconds"])), (record["players"] as Array).size(),
		"" if (record["players"] as Array).size() == 1 else "s", short(float(record["dps"]))]
	var boss: Dictionary = boss_kill(record)
	if not boss.is_empty():
		line += "  %s %s" % [str(boss["name"]), clock(float(boss["seconds"]))]
	return line


const COMPARE_LABELS := ["Fought", "Where", "Length", "Players", "Total", "Group DPS", "Best 5 s",
	"Uptime", "Steadiness", "Kills", "Boss kill", "Boss", "Boss health", "Top player", "Held"]


static func compare_rows(records: Array) -> Array:
	"""[label, a value per record] for the side-by-side table."""
	var out: Array = []
	for label in COMPARE_LABELS:
		var line: Array = [label]
		for record in records:
			line.append(compare_value(str(label), record))
		out.append(line)
	return out


static func compare_value(label: String, r: Dictionary) -> String:
	var boss: Dictionary = boss_kill(r)
	var players: Array = r["players"]
	match label:
		"Fought":
			return str(r["when"]).substr(5, 11)
		"Where":
			return str(r["area"])
		"Length":
			return clock(float(r["seconds"]))
		"Players":
			return str(players.size())
		"Total":
			return short(float(r["total"]))
		"Group DPS":
			return short(float(r["dps"]))
		"Best 5 s":
			return short(float(r["peak"]))
		"Uptime":
			return "%d%%" % int(round(100.0 * float(r.get("uptime", 0.0))))
		"Steadiness":
			return "%d%%" % int(round(100.0 * float(r.get("steady", 0.0))))
		"Kills":
			return str((r["kills"] as Array).size())
		"Boss kill":
			return "-" if boss.is_empty() else clock(float(boss["seconds"]))
		"Boss":
			return "-" if boss.is_empty() else str(boss["name"])
		"Boss health":
			return "-" if boss.is_empty() else short(float(boss["max_hp"]))
		"Top player":
			return "-" if players.is_empty() else "%s %s" % [str(players[0]["name"]), short(float(players[0]["dps"]))]
		"Held":
			var held: int = 0
			for p in players:
				held += int(p["held"])
			return short(float(held))
	return ""


# Which way is better, for the rows where there is one: +1 more is better,
# -1 less is. A row not named here is shown without a winner.
const BETTER := {"Group DPS": 1, "Best 5 s": 1, "Uptime": 1, "Steadiness": 1, "Boss kill": -1, "Held": -1}
# The rows a change against the first fight is shown for.
const DELTA_ROWS := ["Length", "Total", "Group DPS", "Best 5 s", "Boss kill", "Boss health", "Held"]


static func compare_number(label: String, r: Dictionary) -> float:
	"""The row's number for a record, or NAN where it has none."""
	var boss: Dictionary = boss_kill(r)
	match label:
		"Length":
			return float(r["seconds"])
		"Total":
			return float(r["total"])
		"Group DPS":
			return float(r["dps"])
		"Best 5 s":
			return float(r["peak"])
		"Uptime":
			return float(r.get("uptime", NAN))
		"Steadiness":
			return float(r.get("steady", NAN))
		"Boss kill":
			return NAN if boss.is_empty() else float(boss["seconds"])
		"Boss health":
			return NAN if boss.is_empty() else float(boss["max_hp"])
		"Held":
			var held: int = 0
			for p in r["players"]:
				held += int(p["held"])
			return float(held)
	return NAN


static func compare_cells(records: Array) -> Array:
	"""compare_rows() dressed for the table: [label, [{text, delta, best,
	trend}, ...]] - `delta` the change against the first record ("+12%", ""
	for it and for a row without a number), `best` true for the one record that
	wins a row BETTER names (none on a tie), `trend` +1 where that change is
	for the better, -1 the worse, 0 neither or no such row."""
	var out: Array = []
	for row in compare_rows(records):
		var label: String = str(row[0])
		var numbers: Array = []
		for record in records:
			numbers.append(compare_number(label, record))
		var winner: int = -1
		if BETTER.has(label) and records.size() > 1:
			var way: int = int(BETTER[label])
			for i in numbers.size():
				if is_nan(float(numbers[i])):
					continue
				if winner < 0 or float(numbers[i]) * way > float(numbers[winner]) * way:
					winner = i
			for i in numbers.size():
				if i != winner and not is_nan(float(numbers[i])) and winner >= 0 \
						and is_equal_approx(float(numbers[i]), float(numbers[winner])):
					winner = -1
					break
		var cells: Array = []
		for i in records.size():
			var delta: String = ""
			var trend: int = 0
			var base: float = float(numbers[0])
			if i > 0 and DELTA_ROWS.has(label) and not is_nan(float(numbers[i])) and not is_nan(base) and base != 0.0:
				var change: float = (float(numbers[i]) - base) / absf(base)
				delta = "%+d%%" % int(round(100.0 * change))
				if BETTER.has(label) and int(round(100.0 * change)) != 0:
					trend = 1 if change * int(BETTER[label]) > 0.0 else -1
			cells.append({"text": str(row[i + 1]), "delta": delta, "best": i == winner, "trend": trend})
		out.append([label, cells])
	return out


static func compare_text(records: Array) -> String:
	var lines: PackedStringArray = []
	for row in compare_rows(records):
		lines.append("\t".join(PackedStringArray(row)))
	for record in records:
		lines.append("")
		lines.append(headline(record))
		lines.append("\t".join(PackedStringArray(["Player", "Total", "DPS", "Best 5 s", "Hits", "Average", "Biggest", "Held", "Limit",
			"Uptime", "Steadiness", "Elements", "Taken", "Taken/s", "Biggest taken", "Healed", "Regen", "Lowest",
			"Danger s", "Deaths", "Took"])))
		for p in record["players"]:
			lines.append("\t".join(PackedStringArray([
				"%s (%s %d)" % [p["name"], p["cls"], int(p["lvl"])], str(int(p["total"])),
				str(int(round(float(p["dps"])))), str(int(round(float(p["peak"])))), str(int(p["hits"])),
				str(int(round(float(p["avg"])))), str(int(p["biggest"])), str(int(p["held"])),
				("%d%%" % int(round(100.0 * float(p["limit"])))) if float(p["limit"]) >= 0.0 else "-",
				"%d%%" % int(round(100.0 * float(p.get("uptime", 0.0)))), "%d%%" % int(round(100.0 * float(p.get("steady", 0.0)))),
				elements_text(p.get("elements", []), int(p["total"]))]) + taken_cells(p)))
		for e in record.get("events", []):
			lines.append("  %s  %s" % [clock(float(e["at"])), str(e["text"])])
	return "\n".join(lines)


static func csv(record: Dictionary) -> String:
	"""The record for a spreadsheet: its summary, its players, its kills, and
	the damage each player did each second."""
	var lines: PackedStringArray = []
	lines.append("Fight,%s,%s,%d seconds,%d total,%d group DPS,%d best 5 s" % [str(record["when"]),
		_cell(str(record["area"])), int(record["seconds"]), int(record["total"]), int(round(float(record["dps"]))),
		int(round(float(record["peak"])))])
	lines.append("")
	lines.append("Player,Class,Level,Total,DPS,Best 5 s,Hits,Average hit,Biggest hit,Held,Allowed DPS,Limit used,Uptime,Steadiness,Elements,"
		+ "Taken,Taken a second,Biggest taken,Healed,Regen,Lowest health,Danger seconds,Deaths,Took by element")
	for p in record["players"]:
		lines.append("%s,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%s,%d%%,%d%%,%s,%s" % [_cell(str(p["name"])), str(p["cls"]), int(p["lvl"]),
			int(p["total"]), int(round(float(p["dps"]))), int(round(float(p["peak"]))), int(p["hits"]),
			int(round(float(p["avg"]))), int(p["biggest"]), int(p["held"]), int(p["allowed"]),
			("%d%%" % int(round(100.0 * float(p["limit"])))) if float(p["limit"]) >= 0.0 else "",
			int(round(100.0 * float(p.get("uptime", 0.0)))), int(round(100.0 * float(p.get("steady", 0.0)))),
			_cell(elements_text(p.get("elements", []), int(p["total"]))), ",".join(taken_cells(p))])
	lines.append("")
	lines.append("Killed,Boss,Health,Damage taken,Seconds to kill")
	for k in record["kills"]:
		lines.append("%s,%s,%d,%d,%d" % [_cell(str(k["name"])), "yes" if bool(k["boss"]) else "no",
			int(k["max_hp"]), int(k["damage"]), int(round(float(k["seconds"])))])
	lines.append("")
	lines.append("Second,What happened")
	for e in record.get("events", []):
		lines.append("%d,%s" % [int(float(e["at"])), _cell(str(e["text"]))])
	lines.append("")
	var heading: PackedStringArray = ["Second"]
	var ids: Array = []
	for p in record["players"]:
		heading.append(_cell(str(p["name"])))
		ids.append(str(p["id"]))
	lines.append(",".join(heading))
	for second in int(record["seconds"]):
		var row: PackedStringArray = [str(second)]
		for id in ids:
			var line: Array = record["timeline"].get(id, [])
			row.append(str(int(line[second]) if second < line.size() else 0))
		lines.append(",".join(row))
	# DAMAGE TAKEN (0.83.0): what each took, was given back, and their lowest health, each second.
	if took_anything(record):
		lines.append("")
		var head: PackedStringArray = ["Second"]
		for p in record["players"]:
			for what in ["taken", "healed", "health"]:
				head.append(_cell("%s %s" % [str(p["name"]), what]))
		lines.append(",".join(head))
		for second in int(record["seconds"]):
			var row: PackedStringArray = [str(second)]
			for id in ids:
				for key in ["taken_timeline", "heal_timeline"]:
					var line: Array = (record.get(key, {}) as Dictionary).get(id, [])
					row.append(str(int(line[second]) if second < line.size() else 0))
				var health: Array = (record.get("health_timeline", {}) as Dictionary).get(id, [])
				var h: float = float(health[second]) if second < health.size() else -1.0
				row.append(("%d%%" % int(round(100.0 * h))) if h >= 0.0 else "")
			lines.append(",".join(row))
	return "\n".join(lines) + "\n"


static func took_anything(record: Dictionary) -> bool:
	"""Whether anyone in the record took or was given back any health, or had
	their health heard - a fight from before 0.83.0 never has."""
	for p in record.get("players", []):
		if int(p.get("taken", 0)) > 0 or int(p.get("healed", 0)) > 0 or int(p.get("regen", 0)) > 0 \
				or float(p.get("lowest", -1.0)) >= 0.0:
			return true
	return false


static func taken_cells(p: Dictionary) -> PackedStringArray:
	"""DAMAGE TAKEN (0.83.0) for one player: taken, a second, biggest, healed,
	regen, lowest health, danger seconds, deaths, by element."""
	var lowest: float = float(p.get("lowest", -1.0))
	return PackedStringArray([str(int(p.get("taken", 0))), str(int(round(float(p.get("taken_ps", 0.0))))),
		str(int(p.get("biggest_taken", 0))), str(int(p.get("healed", 0))), str(int(p.get("regen", 0))),
		("%d%%" % int(round(100.0 * lowest))) if lowest >= 0.0 else "-", str(int(p.get("danger", 0))),
		str(int(p.get("deaths", 0))), _cell(elements_text(p.get("took", []), int(p.get("taken", 0))))])


static func elements_text(elements: Array, total: int) -> String:
	"""'fire 62% ice 38%' - a player's damage by element, biggest first."""
	var parts: PackedStringArray = []
	for pair in elements:
		parts.append("%s %d%%" % [element_name(int(pair[0])), int(round(100.0 * float(pair[1]) / maxf(1.0, float(total))))])
	return " ".join(parts)


static func element_name(element: int) -> String:
	if element < 0:
		return "unknown"
	return Element.name_for(element)


static func _cell(text: String) -> String:
	if text.contains(",") or text.contains("\"") or text.contains("\n"):
		return "\"%s\"" % text.replace("\"", "\"\"")
	return text


# ---- keeping them ------------------------------------------------------------

static func load_log(path: String = SAVE_PATH) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Array):
		return []
	var out: Array = []
	for record in parsed:
		if record is Dictionary and (record as Dictionary).has_all(["id", "players", "kills", "timeline", "seconds"]):
			out.append(record)
	return out.slice(0, KEEP)


static func save_log(records: Array, path: String = SAVE_PATH) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(records.slice(0, KEEP)))
	file.close()
	return true


static func csv_path(record: Dictionary, folder: String = FOLDER) -> String:
	var when: String = str(record["when"]).replace("-", "").replace(":", "").replace(" ", "_").replace("T", "_")
	var where: String = str(record["area"]).validate_filename().replace(" ", "")
	return "%s/fight_%s_%s.csv" % [folder, when, where]


static func save_csv(record: Dictionary, folder: String = FOLDER) -> String:
	DirAccess.make_dir_recursive_absolute(folder)
	var path: String = csv_path(record, folder)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(csv(record))
	file.close()
	return path


# ---- the chart ------------------------------------------------------------------

static func group_line(record: Dictionary, smooth_seconds: int = 5) -> Array:
	"""The whole group's damage a second, second by second, each the average
	of the `smooth_seconds` before it."""
	var raw: Array = []
	raw.resize(maxi(int(record.get("seconds", 0)), 0))
	raw.fill(0)
	for id in record.get("timeline", {}):
		var line: Array = record["timeline"][id]
		for i in mini(line.size(), raw.size()):
			raw[i] = int(raw[i]) + int(line[i])
	var out: Array = []
	var running: int = 0
	for i in raw.size():
		running += int(raw[i])
		if i >= smooth_seconds:
			running -= int(raw[i - smooth_seconds])
		out.append(float(running) / float(mini(i + 1, smooth_seconds)))
	return out


static func player_line(record: Dictionary, id: int, smooth_seconds: int = 5) -> Array:
	"""One player's damage a second through a fight, smoothed like
	group_line() - or [] when they were not in it."""
	var raw: Array = (record.get("timeline", {}) as Dictionary).get(str(id), [])
	var out: Array = []
	var running: int = 0
	for i in raw.size():
		running += int(raw[i])
		if i >= smooth_seconds:
			running -= int(raw[i - smooth_seconds])
		out.append(float(running) / float(mini(i + 1, smooth_seconds)))
	return out


static func smoothed(raw: Array, smooth_seconds: int = 5) -> Array:
	"""Each second the average of the `smooth_seconds` before it."""
	var out: Array = []
	var running: int = 0
	for i in raw.size():
		running += int(raw[i])
		if i >= smooth_seconds:
			running -= int(raw[i - smooth_seconds])
		out.append(float(running) / float(mini(i + 1, smooth_seconds)))
	return out


static func taken_line(record: Dictionary, id: int, smooth_seconds: int = 5) -> Array:
	"""DAMAGE TAKEN (0.83.0): what one player took a second through a fight,
	smoothed like player_line(); id -1 the whole group's. [] for a fight from
	before 0.83.0."""
	return _line_of(record.get("taken_timeline", {}), id, int(record.get("seconds", 0)), smooth_seconds)


static func heal_line(record: Dictionary, id: int, smooth_seconds: int = 5) -> Array:
	"""What healing and regen gave one player back a second, smoothed."""
	return _line_of(record.get("heal_timeline", {}), id, int(record.get("seconds", 0)), smooth_seconds)


static func _line_of(lines: Dictionary, id: int, seconds: int, smooth_seconds: int) -> Array:
	if lines.is_empty():
		return []
	if id >= 0:
		return smoothed(lines.get(str(id), []), smooth_seconds)
	var raw: Array = []
	raw.resize(maxi(seconds, 0))
	raw.fill(0)
	for key in lines:
		for i in mini((lines[key] as Array).size(), raw.size()):
			raw[i] = int(raw[i]) + int(lines[key][i])
	return smoothed(raw, smooth_seconds)


static func player_in(record: Dictionary, id: int) -> Dictionary:
	"""A player's row in a fight, or {}."""
	for p in record.get("players", []):
		if int(p["id"]) == id:
			return p
	return {}


class GroupChart extends Control:
	## THE CHART (0.82.0): the group's DPS over each picked fight, one line a
	## fight in its slot's colour, on one time axis - the longest fight's - so
	## fights are compared second for second. A dashed line in a fight's colour
	## where its boss fell.
	var records: Array = []
	var slot_colours: Array = []
	var lines: Array = []
	# THE EVENTS (0.82.0), when shown: a mark in the fight's colour at the top
	# of the chart for each - ^ a boss grew, v it shrank, + a player joined,
	# - one left, x one fell.
	var show_events: bool = false
	const MARKS := {"grew": "^", "shrank": "v", "joined": "+", "left": "-", "fell": "x"}
	# DAMAGE TAKEN (0.83.0), when shown: a fight's taken dashed in its colour,
	# and - one player focused - its healing dotted and a strip of their health
	# under the chart, 0-100%, red under DANGER_SHARE. Never netted: heal and
	# damage are two lines.
	var show_taken: bool = false
	var taken_lines: Array = []
	var heal_lines: Array = []
	var health_lines: Array = []
	const STRIP_ROW := 10
	const STRIP_GAP := 3
	const DANGER := Color(0.95, 0.35, 0.3)

	func _init() -> void:
		custom_minimum_size = Vector2(420, 150)

	func set_taken(on: bool, taken: Array, healed: Array, health: Array) -> void:
		"""Each picked fight's taken_line(), heal_line() and health (0-1 a
		second; [] for none), drawn while `on`."""
		show_taken = on
		taken_lines = taken
		heal_lines = healed
		health_lines = health
		custom_minimum_size.y = 150 + strip_height()
		queue_redraw()

	func strip_height() -> int:
		if not show_taken:
			return 0
		var rows: int = 0
		for h in health_lines:
			if not (h as Array).is_empty():
				rows += 1
		return 0 if rows == 0 else 6 + rows * (STRIP_ROW + STRIP_GAP)

	func _dashed(points: PackedVector2Array, colour: Color, width: float, on: float, off: float) -> void:
		"""A polyline drawn in dashes `on` long with gaps `off` long, the
		pattern running on along the whole line rather than starting again at
		every second's point."""
		var carry: float = 0.0
		var drawing: bool = true
		for k in range(1, points.size()):
			var a: Vector2 = points[k - 1]
			var b: Vector2 = points[k]
			var length: float = a.distance_to(b)
			var at: float = 0.0
			while at < length:
				var step: float = minf((on if drawing else off) - carry, length - at)
				if drawing:
					draw_line(a.lerp(b, at / length), a.lerp(b, (at + step) / length), colour, width, true)
				at += step
				carry += step
				if carry >= (on if drawing else off) - 0.001:
					carry = 0.0
					drawing = not drawing

	func set_records(chosen: Array, colours: Array, group_lines: Array) -> void:
		"""The fights, their colours, and each one's group_line()."""
		records = chosen
		slot_colours = colours
		lines = group_lines
		queue_redraw()

	func _time(seconds: int) -> String:
		return "%d:%02d" % [int(seconds / 60.0), seconds % 60]

	func _draw() -> void:
		var font: Font = get_theme_default_font()
		var small: int = 11
		var dim := Color(0.55, 0.6, 0.67, 0.9)
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.035))
		var strip: int = strip_height()
		var plot := Rect2(Vector2(6, 18), size - Vector2(12, 36 + strip))
		var top: float = 1.0
		var length: int = 2
		var everything: Array = lines + (taken_lines + heal_lines if show_taken else [])
		for line in everything:
			length = maxi(length, (line as Array).size())
			for v in line:
				top = maxf(top, float(v))
		draw_string(font, Vector2(plot.position.x, 13), "%d DPS" % int(round(top)), HORIZONTAL_ALIGNMENT_LEFT,
			-1, small, dim)
		top *= 1.1
		for q in [0.25, 0.5, 0.75, 1.0]:
			var y: float = plot.position.y + plot.size.y * (1.0 - q)
			draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(1, 1, 1, 0.05), 1.0)
		draw_line(Vector2(plot.position.x, plot.end.y), plot.end, Color(1, 1, 1, 0.22), 1.0)
		var last: int = length - 1
		for at in [0, int(last / 2.0), last]:
			var label: String = _time(length if at == last else at)
			var x: float = plot.position.x + plot.size.x * float(at) / float(last)
			var width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
			draw_string(font, Vector2(clampf(x - width / 2.0, 0.0, size.x - width), plot.end.y + 14), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, small, dim)
		for i in records.size():
			var colour: Color = slot_colours[i] if i < slot_colours.size() else Color.WHITE
			for kill in records[i].get("kills", []):
				if bool(kill["boss"]) and float((kill as Dictionary).get("at", -1.0)) >= 0.0:
					var kx: float = plot.position.x + plot.size.x * clampf(float(kill["at"]) / float(last), 0.0, 1.0)
					draw_dashed_line(Vector2(kx, plot.position.y), Vector2(kx, plot.end.y), colour, 1.0, 3.0)
			var values: Array = lines[i]
			if values.size() < 2:
				continue
			var points := PackedVector2Array()
			for j in values.size():
				var x: float = plot.position.x + plot.size.x * float(j) / float(last)
				var y: float = plot.position.y + plot.size.y * (1.0 - float(values[j]) / top)
				points.append(Vector2(x, y))
			draw_polyline(points, colour, 2.0, true)
		if show_taken:
			for i in records.size():
				var colour: Color = slot_colours[i] if i < slot_colours.size() else Color.WHITE
				for pair in [[taken_lines, 6.0, 4.0], [heal_lines, 1.5, 3.5]]:
					var values: Array = pair[0][i] if i < (pair[0] as Array).size() else []
					if values.size() < 2:
						continue
					var points := PackedVector2Array()
					for j in values.size():
						points.append(Vector2(plot.position.x + plot.size.x * float(j) / float(last),
							plot.position.y + plot.size.y * (1.0 - float(values[j]) / top)))
					_dashed(points, colour, 2.0, float(pair[1]), float(pair[2]))
			if strip > 0:
				var y0: float = plot.end.y + 22.0
				for i in records.size():
					var health: Array = health_lines[i] if i < health_lines.size() else []
					if health.is_empty():
						continue
					var colour: Color = slot_colours[i] if i < slot_colours.size() else Color.WHITE
					draw_rect(Rect2(plot.position.x, y0, plot.size.x, STRIP_ROW), Color(1, 1, 1, 0.05))
					var w: float = maxf(1.0, plot.size.x / float(maxi(last, 1)))
					for j in health.size():
						var h: float = float(health[j])
						if h < 0.0:
							continue
						var hx: float = plot.position.x + plot.size.x * float(j) / float(last)
						var tall: float = maxf(1.0, STRIP_ROW * h)
						draw_rect(Rect2(hx, y0 + STRIP_ROW - tall, minf(w, plot.end.x - hx), tall),
							DANGER if h < DANGER_SHARE else Color(colour.r, colour.g, colour.b, 0.75))
					y0 += STRIP_ROW + STRIP_GAP
		if not show_events:
			return
		for i in records.size():
			var colour: Color = slot_colours[i] if i < slot_colours.size() else Color.WHITE
			for e in records[i].get("events", []):
				var mark: String = str(MARKS.get(str(e["kind"]), "*"))
				var ex: float = plot.position.x + plot.size.x * clampf(float(e["at"]) / float(last), 0.0, 1.0)
				draw_line(Vector2(ex, plot.position.y), Vector2(ex, plot.end.y), Color(colour.r, colour.g, colour.b, 0.18), 1.0)
				var w: float = font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
				draw_string(font, Vector2(ex - w / 2.0, plot.position.y + 10 + 11 * (i % 3)), mark,
					HORIZONTAL_ALIGNMENT_LEFT, -1, small, colour)
