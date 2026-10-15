# worldtab.gd - the GM panel's World tab: the stirring lands (0.46.0).
#
# The owner: "just make those switches in my gm panel under a new tab that can
# be adjusted". Everything about the stirring lands the server lets the owner
# set (app.py, THE STIRRING LANDS), on one tab:
#
#   - the lands on or off, and how many hours a stir lasts
#   - each effect, a switch and an amount: monsters hit harder (%), have more
#     health (%) and move faster (%), loot drops more often (x), resistance
#     counts more (x), more XP (%)
#   - stir a land now, for a whole stir
#   - what is stirring now, the last few stirs, and how hunted each land has
#     been today (the least hunted is the next to stir)
#
# Read from GET /api/server/world when the panel opens or Refresh is pressed;
# what each button did is said on the tab AND in the panel's Results box
# (`report`, OwnerPanel._say) - the owner: "i want refresh to say it in the
# results". Opening the panel reads quietly; only a failure is reported then.
# Save sends every setting at once to POST /api/server/world, and Stir it now
# POST /api/server/world/stir. Both are owner-only and ask for the password
# again on a hardened login (STEP-UP, the HUD's prompt). The server checks
# every value; the controls only offer the ranges it allows.
extends VBoxContainer
class_name WorldTab


const PATH := "/api/server/world"
const STIR_PATH := "/api/server/world/stir"
const SAY_GOOD := Color(0.55, 0.86, 0.6)
const SAY_BAD := Color(0.95, 0.55, 0.5)
const SAY_NOTE := Color(0.78, 0.82, 0.87)
const HEAD := Color(0.93, 0.73, 0.3)
# The GM panel's inside width, near enough: it is 370 wide.
const WIDTH := 250.0
const LANDS := [Element.Type.DARK, Element.Type.LIGHT, Element.Type.ICE, Element.Type.WIND,
	Element.Type.EARTH, Element.Type.FIRE, Element.Type.WATER]
# The effects, in the order they are drawn: [switch key, amount key, words,
# unit, low, high, step, hint].
const EFFECTS := [
	["hit_on", "hit_percent", "Hit harder", "%", 0.0, 100.0, 5.0,
		"How much harder the stirring land's monsters hit."],
	["health_on", "health_percent", "More health", "%", 0.0, 200.0, 10.0,
		"How much more health its monsters have - from birth, or from the stir's start for one already standing."],
	["speed_on", "speed_percent", "Faster", "%", 0.0, 50.0, 5.0,
		"How much faster its monsters move."],
	["bags_on", "bags_times", "More loot", "x", 1.0, 3.0, 0.1,
		"How many times as often its monsters drop a loot bag (the server rolls it)."],
	["resist_on", "resist_times", "Resistance", "x", 1.0, 2.0, 0.05,
		"How many times armour's resistance to it counts - still held to the 50% cap."],
	["xp_on", "xp_percent", "More XP", "%", 0.0, 100.0, 5.0,
		"How much more XP its monsters give (the server pays it)."],
]

# Where requests go; seams for the suite.
var fetch: Callable = Callable(Api, "get_json")
var send: Callable = Callable(Api, "post")
# Where results also go: the GM panel's Results box, set by the panel
# (OwnerPanel._say). Unset, they show on the tab alone.
var report: Callable = Callable()
# The last answer from the server.
var answer: Dictionary = {}

var status_label: Label
var on_switch: CheckButton
var hours_box: SpinBox
var effect_switches: Dictionary = {}
var effect_amounts: Dictionary = {}
var save_button: Button
var refresh_button: Button
var land_pick: OptionButton
var stir_button: Button
var lands_label: Label
var recent_label: Label
var say_label: Label
var _busy: bool = false


func _init() -> void:
	name = "world"
	add_theme_constant_override("separation", 6)
	_build()


func _build() -> void:
	# NARROW AND SHORT: the GM panel is 370 wide and holds its tallest tab at
	# its drawn size (the suite measures it), so this tab is laid out to fit.
	status_label = _label("The stirring lands: not read yet.", HEAD)
	status_label.name = "status"
	add_child(status_label)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	add_child(top)
	on_switch = CheckButton.new()
	on_switch.name = "on"
	on_switch.text = "Lands stir"
	on_switch.focus_mode = Control.FOCUS_NONE
	on_switch.tooltip_text = "Off: nothing stirs, and the game is as it was."
	top.add_child(on_switch)
	top.add_child(_label("Each lasts", SAY_NOTE, false))
	hours_box = _spin(1.0, 24.0, 1.0, " h")
	hours_box.name = "hours"
	hours_box.tooltip_text = "Hours a land stirs. A change applies from the next stir."
	top.add_child(hours_box)

	var grid := GridContainer.new()
	grid.name = "effects"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	add_child(grid)
	for effect in EFFECTS:
		var box := CheckBox.new()
		box.name = str(effect[0])
		box.text = str(effect[2])
		box.tooltip_text = str(effect[7])
		box.focus_mode = Control.FOCUS_NONE
		grid.add_child(box)
		effect_switches[effect[0]] = box
		var amount: SpinBox = _spin(float(effect[4]), float(effect[5]), float(effect[6]), " " + str(effect[3]))
		amount.name = str(effect[1])
		amount.tooltip_text = str(effect[7])
		grid.add_child(amount)
		effect_amounts[effect[1]] = amount

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	add_child(buttons)
	save_button = _button("Save settings", "Send every setting above to the server.")
	save_button.name = "save"
	save_button.pressed.connect(save)
	# NOT UNTIL THE SERVER HAS BEEN READ: unread, the controls hold their
	# lowest values, and Save would send those as the owner's settings.
	save_button.disabled = true
	buttons.add_child(save_button)
	refresh_button = _button("Refresh", "Read them again from the server.")
	refresh_button.name = "refresh"
	refresh_button.pressed.connect(refresh.bind(true))
	buttons.add_child(refresh_button)

	var stir_row := HBoxContainer.new()
	stir_row.add_theme_constant_override("separation", 8)
	add_child(stir_row)
	stir_row.add_child(_label("Stir now:", SAY_NOTE, false))
	land_pick = OptionButton.new()
	land_pick.name = "land"
	land_pick.focus_mode = Control.FOCUS_NONE
	for element in LANDS:
		land_pick.add_item(Element.name_for(element).capitalize(), element)
	stir_row.add_child(land_pick)
	stir_button = _button("Stir it now", "Ends the stir going on and starts this land's - a whole stir long, announced to everyone.")
	stir_button.name = "stir"
	stir_button.pressed.connect(stir)
	stir_button.disabled = true
	stir_row.add_child(stir_button)

	lands_label = _label("", SAY_NOTE)
	lands_label.name = "lands"
	add_child(lands_label)
	recent_label = _label("", SAY_NOTE)
	recent_label.name = "recent"
	add_child(recent_label)
	say_label = _label("", SAY_NOTE)
	say_label.name = "say"
	add_child(say_label)


func _label(text: String, colour: Color, wraps: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	if wraps:
		# A WRAPPING LABEL WITH NO WIDTH OF ITS OWN is measured at one word
		# a line, which made this tab 720 tall in a 626 window. Given the
		# tab's width, it is measured as it will be drawn.
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(WIDTH, 0)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_font_size_override("font_size", 13)
	return label


func _spin(low: float, high: float, step: float, suffix: String) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = low
	box.max_value = high
	box.step = step
	box.suffix = suffix.strip_edges()
	box.custom_minimum_size = Vector2(84, 0)
	return box


func _button(text: String, hint: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = hint
	button.focus_mode = Control.FOCUS_NONE
	return button


func _say(line: String, colour: Color = SAY_NOTE, results: String = "") -> void:
	"""On the tab, and in the Results box: `results` there when given (a
	fuller line), else the same words. A line still in progress ("Saving...")
	is the tab's alone - say it with _say_here()."""
	_say_here(line, colour)
	if report.is_valid():
		report.call("[WORLD] " + (results if results != "" else line), colour)


func _say_here(line: String, colour: Color = SAY_NOTE) -> void:
	say_label.text = line
	say_label.add_theme_color_override("font_color", colour)


static func settings_text(settings: Dictionary) -> String:
	"""The settings in a line: 'Each stir lasts 3 h. On: hit harder 25%, more
	health 50%, ... Off: more XP.' - or 'Switched off.'"""
	if not bool(settings.get("on", false)):
		return "Switched off: nothing stirs."
	var on: Array[String] = []
	var off: Array[String] = []
	for effect in EFFECTS:
		var amount: float = float(settings.get(effect[1], effect[4]))
		var shown: String = ("%d%%" % roundi(amount)) if str(effect[3]) == "%" else (_times_text(amount) + "x")
		# "More XP" reads "more XP": only the first letter comes down.
		var words: String = str(effect[2]).left(1).to_lower() + str(effect[2]).substr(1)
		if bool(settings.get(effect[0], false)):
			on.append("%s %s" % [words, shown])
		else:
			off.append(words)
	var text: String = "Each stir lasts %d h." % int(settings.get("hours", 3))
	if not on.is_empty():
		text += " On: " + ", ".join(on) + "."
	if not off.is_empty():
		text += " Off: " + ", ".join(off) + "."
	return text


static func _times_text(value: float) -> String:
	"""1.5 -> '1.5', 2.0 -> '2', 1.25 -> '1.25'."""
	var text: String = "%.2f" % value
	while text.ends_with("0"):
		text = text.substr(0, text.length() - 1)
	return text.trim_suffix(".")


static func refusal(res: Dictionary) -> String:
	var status: int = int(res.get("status", 0))
	if status == 0:
		return "Could not reach the server."
	if status == 404:
		# Only the owner sees this tab, so a 404 here is a server from before
		# 0.46.0 - its update not pushed, or update_server.sh not run since.
		return "This server does not have the stirring lands yet (404). Update the server, then Refresh."
	return "The server refused (%d): %s" % [status, str(res.get("error", ""))]


# =============================================================================
# THE SERVER
# =============================================================================

func refresh(by_hand: bool = false) -> void:
	"""Read the settings and the world again. By hand (Refresh), what was read
	goes in the Results box; opening the panel reads quietly."""
	if _busy:
		return
	_busy = true
	var res: Dictionary = await fetch.call(PATH)
	_busy = false
	if not is_instance_valid(self):
		return
	if not res.get("ok", false) or not (res.get("data") is Dictionary):
		# What the controls hold now is not the server's, so nothing is sent
		# from them until a read works.
		answer = {}
		save_button.disabled = true
		stir_button.disabled = true
		status_label.text = "The stirring lands: not read."
		_say(refusal(res), SAY_BAD)
		return
	show_answer(res.get("data"))
	if by_hand:
		var data: Dictionary = res.get("data")
		var settings: Dictionary = data.get("settings", {}) if data.get("settings") is Dictionary else {}
		_say("Read from the server.", SAY_GOOD,
			"Read from the server. %s %s" % [status_text(data), settings_text(settings)]
			if bool(settings.get("on", false)) else "Read from the server. " + settings_text(settings))


func settings_from_controls() -> Dictionary:
	"""Every setting as the controls have it - what Save sends."""
	var out := {"on": on_switch.button_pressed, "hours": int(hours_box.value)}
	for effect in EFFECTS:
		out[effect[0]] = (effect_switches[effect[0]] as CheckBox).button_pressed
		var amount: float = (effect_amounts[effect[1]] as SpinBox).value
		if str(effect[3]) == "%":
			out[effect[1]] = int(roundf(amount))
		else:
			out[effect[1]] = snappedf(amount, 0.01)
	return out


func save() -> void:
	if _busy or answer.is_empty():
		return
	_busy = true
	_say_here("Saving...")
	var res: Dictionary = await send.call(PATH, settings_from_controls())
	_busy = false
	if not is_instance_valid(self):
		return
	if not res.get("ok", false):
		_say(refusal(res), SAY_BAD)
		return
	var saved: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	show_answer(saved)
	var now_set: Dictionary = saved.get("settings", {}) if saved.get("settings") is Dictionary else {}
	_say("Saved. The game hears it within one poll.", SAY_GOOD,
		"Saved - the game hears it within one poll. " + settings_text(now_set))


func stir() -> void:
	if _busy or answer.is_empty() or land_pick.selected < 0:
		return
	var element: int = land_pick.get_item_id(land_pick.selected)
	_busy = true
	_say_here("Stirring the %s lands..." % Element.name_for(element))
	var res: Dictionary = await send.call(STIR_PATH, {"element": element})
	_busy = false
	if not is_instance_valid(self):
		return
	if not res.get("ok", false):
		_say(refusal(res) if int(res.get("status", 0)) != 409
			else "Switch the stirring lands on first (and save).", SAY_BAD)
		return
	show_answer(res.get("data", {}) if res.get("data") is Dictionary else {})
	_say("The %s lands stir - announced to everyone online." % Element.name_for(element).capitalize(), SAY_GOOD)


# =============================================================================
# WHAT IT SHOWS
# =============================================================================

func show_answer(data: Dictionary) -> void:
	answer = data
	var settings: Dictionary = data.get("settings", {}) if data.get("settings") is Dictionary else {}
	on_switch.set_pressed_no_signal(bool(settings.get("on", false)))
	hours_box.set_value_no_signal(float(settings.get("hours", 3)))
	for effect in EFFECTS:
		(effect_switches[effect[0]] as CheckBox).set_pressed_no_signal(bool(settings.get(effect[0], false)))
		(effect_amounts[effect[1]] as SpinBox).set_value_no_signal(float(settings.get(effect[1], effect[4])))
	status_label.text = status_text(data)
	var state: Dictionary = data.get("state", {}) if data.get("state") is Dictionary else {}
	var land: int = int(state.get("element", 0))
	status_label.add_theme_color_override("font_color",
		Element.colour_for(land).lightened(0.35) if land != 0 else HEAD)
	lands_label.text = lands_text(data.get("lands", []))
	recent_label.text = recent_text(data.get("recent", []))
	save_button.disabled = false
	stir_button.disabled = not bool(settings.get("on", false))


static func status_text(data: Dictionary) -> String:
	var settings: Dictionary = data.get("settings", {}) if data.get("settings") is Dictionary else {}
	var state: Dictionary = data.get("state", {}) if data.get("state") is Dictionary else {}
	if not bool(settings.get("on", false)):
		return "Switched off: nothing stirs."
	var land: int = int(state.get("element", 0))
	if land == 0:
		return "Nothing is stirring."
	var left: int = maxi(0, int(state.get("ends_at", 0)) - int(data.get("now", state.get("now", 0))))
	return "The %s lands are stirring - %s left (stir %d)." % [Element.name_for(land).capitalize(),
		Lands.time_text(left), int(state.get("tick", 0))]


static func lands_text(lands: Variant) -> String:
	"""'Hunted today: dark 12, light 0, ...' - the least hunted stirs next."""
	if not (lands is Array) or (lands as Array).is_empty():
		return ""
	var bits: Array[String] = []
	for row in lands:
		if row is Dictionary:
			bits.append("%s %d" % [str(row.get("name", "?")), int(row.get("kills", 0))])
	return "Kills in the last day: %s. The least hunted stirs next." % ", ".join(bits)


static func recent_text(recent: Variant) -> String:
	"""'Last stirs: 12 Fire, 11 Ice (by Tunacan), ...' - newest first; one
	stirred by hand names who did it."""
	if not (recent is Array) or (recent as Array).is_empty():
		return ""
	var bits: Array[String] = []
	for row in recent:
		if not (row is Dictionary):
			continue
		var who: String = str(row.get("chosen_by", ""))
		bits.append("%d %s%s" % [int(row.get("tick", 0)), str(row.get("name", "?")).capitalize(),
			" (by %s)" % who if who != "" else ""])
	return "Last stirs: %s." % ", ".join(bits)
