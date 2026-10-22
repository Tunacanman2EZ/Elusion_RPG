# economytab.gd - the GM panel's Economy tab (0.74.0).
#
# Three of the owner's five economy ideas, "we need to do these tasks also max
# power", on one tab of three pages:
#
#   GOLD FLOW  "A daily report of where gold comes from and where it goes, by
#              source." GET /api/owner/economy/flow?days=N: minted against
#              burned by day (GoldFlowChart), the net, the window's sources and
#              sinks by ledger reason, the gold in the world now, and lusions
#              the same in a line.
#   RULES      "Economy numbers you can change without shipping." GET and PUT
#              /api/owner/economy/rules: every number the server lets the owner
#              set, its bounds beside it; Set sends one, Usual puts the game's
#              own back. The OWNER changes them; a co-owner reads them - the
#              server says which (can_change) and refuses a co-owner's PUT
#              whatever this tab shows. A change asks for the password again on
#              a hardened login (STEP-UP, the HUD's prompt).
#   CANARY     "Checking the gold totals automatically ... it would tell you
#              the same day if gold or lusions appear or vanish without being
#              recorded." GET /api/owner/economy/canary is the hourly check's
#              last word (and says when the timer looks stopped); Check now is
#              POST, the same checks, read-only, this moment.
#
# Built like the World tab (worldtab.gd): made in code, read when the panel
# opens and on Refresh, what each button did said on the tab AND in the
# panel's Results box (`report`, OwnerPanel._say). NARROW AND SHORT: the panel
# is 370 wide and holds its tallest tab at its drawn size, so the three pages
# take turns rather than stack, and nothing here scrolls.
extends VBoxContainer
class_name EconomyTab


const FLOW_PATH := "/api/owner/economy/flow"
const RULES_PATH := "/api/owner/economy/rules"
const CANARY_PATH := "/api/owner/economy/canary"
const SAY_GOOD := Color(0.55, 0.86, 0.6)
const SAY_BAD := Color(0.95, 0.55, 0.5)
const SAY_WARN := Color(0.95, 0.82, 0.5)
const SAY_NOTE := Color(0.78, 0.82, 0.87)
const HEAD := Color(0.93, 0.73, 0.3)
# The GM panel's inside width, near enough (the World tab's).
const WIDTH := 250.0
const DAY_CHOICES := [7, 14, 30, 90]
const PAGES := [["flow", "Gold flow"], ["rules", "Rules"], ["canary", "Canary"]]
# How many sources and sinks a line names before "and N more".
const REASONS_NAMED := 3

# The rules in the owner's words; the server's key for anything new.
const RULE_WORDS := {
	"trade_tax_rate": "Trade tax",
	"trade_tax_minimum": "Tax floor",
	"shop_price_multiplier": "Shop prices",
	"shop_sell_multiplier": "Shop buys at",
	"material_drop_scale": "Material drops",
	"temper_gold_scale": "Temper gold",
	"certification_gold_scale": "Certify gold",
}
# The ledger's reasons in the owner's words; an unknown one as its own id.
const REASON_WORDS := {
	"pile": "gold piles",
	"loot": "loot",
	"shop_sell": "sold to the shop",
	"shop_buy": "bought from the shop",
	"kingdom_tax": "trade tax",
	"revive": "revives",
	"death": "lost by the dead",
	"staff_gold": "staff gold",
	"guild_found": "founding guilds",
	"smith_temper": "the smith",
	"royal_certification": "Royal Certification",
	"donation": "donations",
	"opening_balance": "opening balance",
	"dupe_pet": "pets turned to lusions",
}

# Where requests go; seams for the suite.
var fetch: Callable = Callable(Api, "get_json")
var send: Callable = Callable(Api, "post")
var put_request: Callable = Callable(Api, "put")
# Where results also go: the panel's Results box (OwnerPanel._say).
var report: Callable = Callable()

# The last answers.
var flow_answer: Dictionary = {}
var rules_answer: Dictionary = {}
var canary_answer: Dictionary = {}
var checked_now: Dictionary = {}
var page: String = "flow"

var page_buttons: Dictionary = {}
var pages: Dictionary = {}
# Gold flow.
var days_pick: OptionButton
var refresh_button: Button
var chart: GoldFlowChart
var totals_label: Label
var world_label: Label
var sources_label: Label
var sinks_label: Label
var lusions_label: Label
# Rules.
var rules_status: Label
var rules_grid: GridContainer
var rule_boxes: Dictionary = {}
var rule_bounds: Dictionary = {}
var rule_set_buttons: Dictionary = {}
var rule_usual_buttons: Dictionary = {}
var last_change_label: Label
# Canary.
var canary_status: Label
var canary_when: Label
var canary_checks: Label
var check_button: Button
var canary_refresh: Button
var say_label: Label
var _busy: bool = false


func _init() -> void:
	name = "economy"
	add_theme_constant_override("separation", 6)
	_build()


func _build() -> void:
	var strip := HBoxContainer.new()
	strip.name = "pages"
	strip.add_theme_constant_override("separation", 4)
	add_child(strip)
	var group := ButtonGroup.new()
	for spec in PAGES:
		var button := _button(str(spec[1]), "")
		button.name = str(spec[0])
		button.toggle_mode = true
		button.button_group = group
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(show_page.bind(str(spec[0])))
		strip.add_child(button)
		page_buttons[spec[0]] = button
	refresh_button = _button("Refresh", "Read the flow, the rules and the canary again from the server.")
	refresh_button.name = "refresh"
	refresh_button.add_theme_font_size_override("font_size", 14)
	refresh_button.pressed.connect(refresh.bind(true))
	strip.add_child(refresh_button)

	# ---- GOLD FLOW -----------------------------------------------------------
	var flow := _page("flow")
	flow.add_theme_constant_override("separation", 3)
	# The flow's page takes the tab's height, for its chart (below).
	flow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var days_row := HBoxContainer.new()
	days_row.add_theme_constant_override("separation", 6)
	flow.add_child(days_row)
	days_row.add_child(_label("Gold, the last", HEAD, false))
	days_pick = OptionButton.new()
	days_pick.name = "days"
	days_pick.focus_mode = Control.FOCUS_NONE
	for days in DAY_CHOICES:
		days_pick.add_item("%d days" % days, days)
	days_pick.item_selected.connect(func(_index: int) -> void: refresh_flow(true))
	days_row.add_child(days_pick)
	days_row.add_child(_label("(UTC)", SAY_NOTE, false))
	chart = GoldFlowChart.new()
	chart.name = "chart"
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# AS TALL AS THE PAGE LEAVES IT: its minimum is what the busiest flow
	# leaves room for, and an ordinary week gives it the rest.
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	flow.add_child(chart)
	totals_label = _label("", SAY_NOTE)
	totals_label.add_theme_font_size_override("font_size", 12)
	totals_label.name = "totals"
	flow.add_child(totals_label)
	world_label = _label("", SAY_NOTE)
	world_label.add_theme_font_size_override("font_size", 12)
	world_label.name = "world"
	flow.add_child(world_label)
	sources_label = _label("", SAY_NOTE)
	sources_label.add_theme_font_size_override("font_size", 12)
	sources_label.name = "sources"
	flow.add_child(sources_label)
	sinks_label = _label("", SAY_NOTE)
	sinks_label.add_theme_font_size_override("font_size", 12)
	sinks_label.name = "sinks"
	flow.add_child(sinks_label)
	lusions_label = _label("", SAY_NOTE)
	lusions_label.add_theme_font_size_override("font_size", 12)
	lusions_label.name = "lusions"
	flow.add_child(lusions_label)

	# ---- RULES ---------------------------------------------------------------
	var rules := _page("rules")
	rules_status = _label("The economy's numbers: not read yet.", HEAD)
	rules_status.name = "rulesstatus"
	rules.add_child(rules_status)
	rules_grid = GridContainer.new()
	rules_grid.name = "rules"
	rules_grid.columns = 4
	rules_grid.add_theme_constant_override("h_separation", 5)
	rules_grid.add_theme_constant_override("v_separation", 3)
	rules.add_child(rules_grid)
	last_change_label = _label("", SAY_NOTE)
	last_change_label.name = "lastchange"
	rules.add_child(last_change_label)

	# ---- CANARY --------------------------------------------------------------
	var canary := _page("canary")
	canary_status = _label("The canary: not read yet.", HEAD)
	canary_status.name = "canarystatus"
	canary.add_child(canary_status)
	canary_when = _label("", SAY_NOTE)
	canary_when.name = "canarywhen"
	canary.add_child(canary_when)
	canary_checks = _label("", SAY_NOTE)
	canary_checks.name = "canarychecks"
	canary.add_child(canary_checks)
	var canary_row := HBoxContainer.new()
	canary_row.add_theme_constant_override("separation", 8)
	canary.add_child(canary_row)
	check_button = _button("Check now", "Run the canary's checks now, read-only: is every coin and lusion accounted for?")
	check_button.name = "checknow"
	check_button.pressed.connect(check_now)
	canary_row.add_child(check_button)
	canary_refresh = _button("Last hourly check", "Read the last hourly check's report again.")
	canary_refresh.name = "canaryrefresh"
	canary_refresh.pressed.connect(refresh_canary.bind(true))
	canary_row.add_child(canary_refresh)

	say_label = _label("", SAY_NOTE)
	say_label.name = "say"
	say_label.add_theme_font_size_override("font_size", 12)
	add_child(say_label)
	show_page("flow")


func _page(page_name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = page_name
	box.add_theme_constant_override("separation", 5)
	add_child(box)
	pages[page_name] = box
	return box


func _label(text: String, colour: Color, wraps: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	if wraps:
		# Given the tab's width, so it is measured as it will be drawn (the
		# World tab's lesson: a wrapping label with no width is one word a line).
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(WIDTH, 0)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_font_size_override("font_size", 13)
	return label


func _button(text: String, hint: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = hint
	button.focus_mode = Control.FOCUS_NONE
	return button


func show_page(which: String) -> void:
	page = which if pages.has(which) else "flow"
	for key in pages:
		(pages[key] as Control).visible = key == page
	for key in page_buttons:
		(page_buttons[key] as Button).set_pressed_no_signal(key == page)


func _say(line: String, colour: Color = SAY_NOTE, results: String = "") -> void:
	"""On the tab, and in the Results box: `results` there when given."""
	_say_here(line, colour)
	if report.is_valid():
		report.call("[ECONOMY] " + (results if results != "" else line), colour)


func _say_here(line: String, colour: Color = SAY_NOTE) -> void:
	say_label.text = line
	say_label.add_theme_color_override("font_color", colour)


static func refusal(res: Dictionary, what: String) -> String:
	var status: int = int(res.get("status", 0))
	if status == 0:
		return "Could not reach the server."
	if status == 404:
		# Only the owner and a co-owner see this tab, so a 404 is a server from
		# before 0.74.0 - its update not pushed, or update_server.sh not run.
		return "This server does not have the %s yet (404). Update the server, then Refresh." % what
	var data: Variant = res.get("data", {})
	var message: String = str((data as Dictionary).get("message", "")) if data is Dictionary else ""
	return "The server refused (%d): %s" % [status, message if message != "" else str(res.get("error", ""))]


# =============================================================================
# THE SERVER
# =============================================================================

func refresh(by_hand: bool = false) -> void:
	"""All three, from the server. By hand (Refresh), what was read goes in
	the Results box; opening the panel reads quietly."""
	await refresh_flow(by_hand)
	await refresh_rules(by_hand)
	await refresh_canary(by_hand)


func days_wanted() -> int:
	return days_pick.get_item_id(days_pick.selected) if days_pick.selected >= 0 else DAY_CHOICES[0]


func refresh_flow(by_hand: bool = false) -> void:
	var res: Dictionary = await fetch.call("%s?days=%d" % [FLOW_PATH, days_wanted()])
	if not is_instance_valid(self):
		return
	if not res.get("ok", false) or not (res.get("data") is Dictionary):
		flow_answer = {}
		chart.show_days([])
		for label in [totals_label, world_label, sources_label, sinks_label, lusions_label]:
			(label as Label).text = ""
		_say(refusal(res, "gold flow"), SAY_BAD)
		return
	show_flow(res.get("data"))
	if by_hand:
		_say("Read the gold flow.", SAY_GOOD, "Gold, the last %d days: %s" % [int(flow_answer.get("days", 0)),
			totals_label.text])


func refresh_rules(by_hand: bool = false) -> void:
	var res: Dictionary = await fetch.call(RULES_PATH)
	if not is_instance_valid(self):
		return
	if not res.get("ok", false) or not (res.get("data") is Dictionary):
		rules_answer = {}
		rules_status.text = "The economy's numbers: not read."
		_show_rule_rows([], false)
		_say(refusal(res, "economy rules"), SAY_BAD)
		return
	show_rules(res.get("data"))
	if by_hand:
		_say("Read the economy's numbers.", SAY_GOOD, "The economy's numbers: " + rules_text(rules_answer))


func refresh_canary(by_hand: bool = false) -> void:
	var res: Dictionary = await fetch.call(CANARY_PATH)
	if not is_instance_valid(self):
		return
	if not res.get("ok", false) or not (res.get("data") is Dictionary):
		canary_answer = {}
		canary_status.text = "The canary: not read."
		_say(refusal(res, "canary's report"), SAY_BAD)
		return
	show_canary(res.get("data"))
	if by_hand:
		_say("Read the last hourly check.", SAY_GOOD, "The canary: " + canary_status.text)


func check_now() -> void:
	if _busy:
		return
	_busy = true
	check_button.disabled = true
	_say_here("Checking...")
	var res: Dictionary = await send.call(CANARY_PATH, {})
	_busy = false
	if not is_instance_valid(self):
		return
	check_button.disabled = false
	if not res.get("ok", false) or not (res.get("data") is Dictionary):
		_say(refusal(res, "canary's Check now"), SAY_BAD)
		return
	checked_now = res.get("data")
	var broken: Array = checked_now.get("failures", []) if checked_now.get("failures") is Array else []
	canary_checks.text = checks_text(checked_now)
	if bool(checked_now.get("ok", false)):
		_say("Checked now: every number adds up.", SAY_GOOD)
	else:
		_say("Checked now: %d check%s broke - %s." % [broken.size(), "" if broken.size() == 1 else "s",
			failures_text(broken)], SAY_BAD)


func set_rule(key: String) -> void:
	"""Send the number in `key`'s box."""
	var box: SpinBox = rule_boxes.get(key) as SpinBox
	if box == null:
		return
	await _change(key, snappedf(box.value, 0.0001))


func usual_rule(key: String) -> void:
	"""Put the game's own number back: the owner's row goes."""
	await _change(key, null)


func _change(key: String, value: Variant) -> void:
	if _busy or rules_answer.is_empty() or not bool(rules_answer.get("can_change", false)):
		if not rules_answer.is_empty() and not bool(rules_answer.get("can_change", false)):
			_say("Only the owner changes the economy's numbers.", SAY_BAD)
		return
	_busy = true
	_say_here("Saving...")
	var res: Dictionary = await put_request.call(RULES_PATH, {"key": key, "value": value})
	_busy = false
	if not is_instance_valid(self):
		return
	if not res.get("ok", false) or not (res.get("data") is Dictionary):
		_say(refusal(res, "economy rules"), SAY_BAD)
		return
	show_rules(res.get("data"))
	var row: Dictionary = rule_row(key)
	# THE OWNER'S OWN GAME HEARS IT AT ONCE: the four the game draws.
	if not row.is_empty():
		EconomyRules.adopt({key: float(row.get("value", 0.0))})
	if not bool((res.get("data") as Dictionary).get("changed", true)):
		_say("%s was already %s - nothing changed." % [rule_name(key), number_text(float(row.get("value", 0.0)))],
			SAY_NOTE)
	elif value == null:
		_say("%s is back to the usual, %s." % [rule_name(key), number_text(float(row.get("value", 0.0)))], SAY_GOOD,
			"%s is back to the usual, %s - every game within %d seconds." % [rule_name(key),
				number_text(float(row.get("value", 0.0))), int(rules_answer.get("cache_seconds", 15))])
	else:
		_say("%s is now %s." % [rule_name(key), number_text(float(row.get("value", 0.0)))], SAY_GOOD,
			"%s is now %s - every game within %d seconds." % [rule_name(key),
				number_text(float(row.get("value", 0.0))), int(rules_answer.get("cache_seconds", 15))])


# =============================================================================
# WHAT IT SHOWS
# =============================================================================

func show_flow(data: Dictionary) -> void:
	flow_answer = data
	var gold: Dictionary = data.get("gold", {}) if data.get("gold") is Dictionary else {}
	chart.show_days(gold.get("days", []))
	totals_label.text = totals_text(gold)
	world_label.text = world_text(gold.get("in_world", {}))
	sources_label.text = reasons_text("Came from", gold.get("reasons", []), "minted")
	sinks_label.text = reasons_text("Went to", gold.get("reasons", []), "burned")
	lusions_label.text = lusions_text(data.get("lusions", {}))


func show_rules(data: Dictionary) -> void:
	rules_answer = data
	var can: bool = bool(data.get("can_change", false))
	rules_status.text = "The economy's numbers - yours to change." if can \
		else "The economy's numbers - the owner changes them; you can read them."
	_show_rule_rows(data.get("rules", []), can)
	last_change_label.text = last_change_text(data.get("changes", []))


func _show_rule_rows(rows: Variant, can: bool) -> void:
	for child in rules_grid.get_children():
		rules_grid.remove_child(child)
		child.queue_free()
	rule_boxes = {}
	rule_bounds = {}
	rule_set_buttons = {}
	rule_usual_buttons = {}
	if not (rows is Array):
		return
	for row in rows:
		if not (row is Dictionary):
			continue
		var key: String = str(row.get("key", ""))
		var low: float = float(row.get("min", 0.0))
		var high: float = float(row.get("max", 0.0))
		var whole: bool = bool(row.get("whole", false))
		var name_label := _label(rule_name(key), SAY_WARN if bool(row.get("set", false)) else SAY_NOTE, false)
		name_label.name = "name_" + key
		name_label.custom_minimum_size = Vector2(76, 0)
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.tooltip_text = rule_hint(row)
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		rules_grid.add_child(name_label)
		var box := SpinBox.new()
		box.name = "value_" + key
		box.min_value = low
		box.max_value = high
		box.step = 1.0 if whole else 0.01
		box.custom_minimum_size = Vector2(60, 0)
		box.set_value_no_signal(float(row.get("value", 0.0)))
		box.editable = can
		box.tooltip_text = rule_hint(row)
		rules_grid.add_child(box)
		rule_boxes[key] = box
		var bounds := _label(bounds_text(row), SAY_NOTE, false)
		bounds.name = "bounds_" + key
		bounds.add_theme_font_size_override("font_size", 11)
		rules_grid.add_child(bounds)
		rule_bounds[key] = bounds
		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 2)
		rules_grid.add_child(buttons)
		var set_button := _button("Set", "Send this number to the server.")
		set_button.name = "set_" + key
		set_button.add_theme_font_size_override("font_size", 12)
		set_button.disabled = not can
		set_button.pressed.connect(set_rule.bind(key))
		buttons.add_child(set_button)
		rule_set_buttons[key] = set_button
		var usual_button := _button("Usual", "Put the game's own number back (%s)." % number_text(float(row.get("default", 0.0))))
		usual_button.name = "usual_" + key
		usual_button.add_theme_font_size_override("font_size", 12)
		usual_button.disabled = not can or not bool(row.get("set", false))
		usual_button.pressed.connect(usual_rule.bind(key))
		buttons.add_child(usual_button)
		rule_usual_buttons[key] = usual_button


func show_canary(data: Dictionary) -> void:
	canary_answer = data
	canary_status.text = canary_text(data)
	var colour: Color = HEAD
	if data.get("checked_at") == null:
		colour = SAY_WARN
	elif bool(data.get("ok", false)):
		colour = SAY_GOOD
	else:
		colour = SAY_BAD
	canary_status.add_theme_color_override("font_color", colour)
	canary_when.text = canary_when_text(data, int(Time.get_unix_time_from_system()))
	canary_checks.text = checks_text(data)


func rule_row(key: String) -> Dictionary:
	var rows: Variant = rules_answer.get("rules", [])
	if rows is Array:
		for row in rows:
			if row is Dictionary and str(row.get("key", "")) == key:
				return row
	return {}


static func rule_name(key: String) -> String:
	return str(RULE_WORDS.get(key, key.replace("_", " ")))


static func reason_name(reason: String) -> String:
	return str(REASON_WORDS.get(reason, reason.replace("_", " ")))


static func number_text(value: float) -> String:
	"""0.05 -> '0.05', 1.0 -> '1', 2.5 -> '2.5'."""
	var text: String = "%.4f" % value
	while text.ends_with("0"):
		text = text.substr(0, text.length() - 1)
	return text.trim_suffix(".")


static func bounds_text(row: Dictionary) -> String:
	"""'0-0.5', the bounds the server allows."""
	return "%s-%s" % [number_text(float(row.get("min", 0.0))), number_text(float(row.get("max", 0.0)))]


static func rule_hint(row: Dictionary) -> String:
	"""What it does, its bounds, the usual, and who set it."""
	var text: String = "%s\nFrom %s to %s. The usual: %s." % [str(row.get("about", "")),
		number_text(float(row.get("min", 0.0))), number_text(float(row.get("max", 0.0))),
		number_text(float(row.get("default", 0.0)))]
	if bool(row.get("set", false)):
		text += "\nSet by %s." % str(row.get("updated_by", "?"))
	return text


static func amount_text(amount: int) -> String:
	"""Gold or lusions as a line says them: in full below a million, compact
	above it (1.5M, 151M) - the GM panel is narrow, and a summary line of
	nine-digit numbers is three lines of digits. The exact figures are the
	ledger's, a GET away."""
	return GameConstants.commas(amount) if absi(amount) < 1000000 else GoldFlowChart.compact(amount)


static func signed(amount: int) -> String:
	return ("+" if amount > 0 else ("-" if amount < 0 else "")) + amount_text(absi(amount))


static func totals_text(gold: Dictionary) -> String:
	"""'Minted 12,345 - burned 10,000 - net +2,345.'"""
	return "Minted %s - burned %s - net %s." % [amount_text(int(gold.get("minted", 0))),
		amount_text(int(gold.get("burned", 0))), signed(int(gold.get("net", 0)))]


static func world_text(world: Variant) -> String:
	"""'Held now: 123,456 (100,000 carried, 23,456 banked).'"""
	if not (world is Dictionary):
		return ""
	var held: Dictionary = world
	return "Held now: %s (%s carried, %s banked)." % [amount_text(int(held.get("total", 0))),
		amount_text(int(held.get("carried", 0))), amount_text(int(held.get("banked", 0)))]


static func reasons_text(head: String, reasons: Variant, side: String) -> String:
	"""'Came from: loot 9,000, sold to the shop 1,000, and 2 more.' - the
	reasons with any of `side` ("minted" or "burned"), the most first."""
	var rows: Array = []
	if reasons is Array:
		for row in reasons:
			if row is Dictionary and int(row.get(side, 0)) > 0:
				rows.append(row)
	if rows.is_empty():
		return "%s: nothing." % head
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get(side, 0)) > int(b.get(side, 0)) \
			or (int(a.get(side, 0)) == int(b.get(side, 0)) and str(a.get("reason", "")) < str(b.get("reason", ""))))
	var bits: Array[String] = []
	for i in mini(REASONS_NAMED, rows.size()):
		bits.append("%s %s" % [reason_name(str(rows[i].get("reason", ""))), amount_text(int(rows[i].get(side, 0)))])
	var text: String = "%s: %s" % [head, ", ".join(bits)]
	if rows.size() > REASONS_NAMED:
		text += ", and %d more" % (rows.size() - REASONS_NAMED)
	return text + "."


static func lusions_text(lusions: Variant) -> String:
	"""'Lusions: 30 in, 25 out, 1,234 held.'"""
	if not (lusions is Dictionary):
		return ""
	var held: Dictionary = lusions.get("in_world", {}) if (lusions as Dictionary).get("in_world") is Dictionary else {}
	return "Lusions: %s in, %s out, %s held." % [amount_text(int((lusions as Dictionary).get("minted", 0))),
		amount_text(int((lusions as Dictionary).get("burned", 0))), amount_text(int(held.get("total", 0)))]


static func rules_text(data: Dictionary) -> String:
	"""Every rule in a line, the ones the owner set marked."""
	var bits: Array[String] = []
	var rows: Variant = data.get("rules", [])
	if rows is Array:
		for row in rows:
			if row is Dictionary:
				bits.append("%s %s%s" % [rule_name(str(row.get("key", ""))), number_text(float(row.get("value", 0.0))),
					" (set)" if bool(row.get("set", false)) else ""])
	return ", ".join(bits) + "."


static func last_change_text(changes: Variant) -> String:
	"""'Last change: Trade tax 0.05 -> 0.1, by Tunacan.' - or nothing."""
	if not (changes is Array) or (changes as Array).is_empty() or not ((changes as Array)[0] is Dictionary):
		return "Nothing changed yet: every number is the game's own."
	var change: Dictionary = (changes as Array)[0]
	var before: String = "usual" if change.get("old_value") == null else number_text(float(change.get("old_value")))
	var after: String = "usual" if change.get("new_value") == null else number_text(float(change.get("new_value")))
	return "Last change: %s %s -> %s, by %s." % [rule_name(str(change.get("key", ""))), before, after,
		str(change.get("by", "?"))]


static func canary_text(data: Dictionary) -> String:
	if data.get("checked_at") == null:
		return "Never checked: the hourly timer has not run on this server yet."
	if bool(data.get("ok", false)):
		return "Every number adds up."
	var broken: Array = data.get("failures", []) if data.get("failures") is Array else []
	return "BROKEN: %s." % failures_text(broken)


static func failures_text(broken: Array) -> String:
	var bits: Array[String] = []
	for failure in broken:
		if failure is Dictionary:
			bits.append("%s (%s)" % [str(failure.get("name", "")), str(failure.get("detail", ""))])
	return "; ".join(bits)


static func canary_when_text(data: Dictionary, now: int) -> String:
	"""When the hourly check last ran, how long ago, whether that is too long,
	and what its mail did."""
	if data.get("checked_at") == null:
		return "deploy/update_server.sh sets the timer up (DEPLOY.md, \"Watching the live economy\"). Check now works without it."
	var at: int = int(data.get("checked_at", 0))
	var ago: int = int(data.get("age_seconds", maxi(0, now - at)))
	var text: String = "Last hourly check: %s (%s ago)." % [LocalTime.stamp(at, now), Lands.time_text(maxi(60, ago))]
	if bool(data.get("stale", false)):
		text += " That is more than two hours - the timer may have stopped."
	var mail: String = str(data.get("mail", ""))
	if mail == "sent":
		text += " Mailed %d owner address%s." % [int(data.get("mailed", 0)), "" if int(data.get("mailed", 0)) == 1 else "es"]
	elif mail == "not configured":
		text += " No mail is set up on the server, so nobody was told."
	elif mail == "no confirmed owner address":
		text += " No owner has a confirmed recovery address, so nobody was told."
	elif mail.begins_with("failed"):
		text += " The mail %s." % mail
	return text


static func checks_text(data: Dictionary) -> String:
	"""Each check on a line: 'hold  gold conservation - recorded 5, held 5'."""
	var lines: Array[String] = []
	var checks: Variant = data.get("checks", [])
	if checks is Array:
		for check_row in checks:
			if check_row is Dictionary:
				lines.append("%s  %s - %s" % ["hold" if bool(check_row.get("ok", false)) else "BROKEN",
					str(check_row.get("name", "")), str(check_row.get("detail", ""))])
	return "\n".join(lines)
