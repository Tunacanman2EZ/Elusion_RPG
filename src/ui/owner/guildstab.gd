# guildstab.gd - the GM panel's Guilds tab: every guild, and renaming or
# disbanding one whose name is a problem (0.112.1).
#
# The owner: "can you update all of my tabs in gm panel", and of the four
# ways, "Add what's missing" among them. The server has had both halves since
# guilds came - GET /api/guild/list (every guild, for staff) and POST
# /api/staff/guild (rename or disband, with a reason; the API's guilds/,
# "A NAME IS PUBLIC AND IT FOLLOWS PEOPLE AROUND") - and nothing in the game
# asked either. The eighth tab, in the tab grid's empty eighth place.
#
#   - the guilds: picked from a list - name, members, leader - and what the
#     one picked is
#   - RENAME it: the new name and a reason (the server keeps the reason in the
#     moderation log; the guild's own history says it was renamed, not by whom)
#   - DISBAND it: the same reason, and Disband asks twice (ARM_SECONDS), as a
#     ban does - it takes the guild from every member. Rename first: it takes
#     away the word, not the guild.
#
# (0.168.13, the owner: "we need to improve ui on this") rows, as the Health
# tab has them: the picker names the guild and its size, the rows below say
# who leads it, how many, and when and by whom it was founded - once each,
# where it said "5 members, led by" three times. The new name is checked as
# it is typed, against the server's own rule, so a refusal is seen before it
# is sent. Disband has its own red part at the bottom, apart from Rename.
#
# Read when the panel opens, when the tab is picked and on the panel's clock
# (OwnerPanel.refresh_tab()), and on Refresh; what each button did is said on
# the tab and in the panel's Results box (`report`). No class_name: preloaded
# by ownerpanel.gd and the suite, so a fresh checkout needs no editor rescan.
extends VBoxContainer


const LIST_PATH := "/api/guild/list"
const ACT_PATH := "/api/staff/guild"
const SAY_GOOD := Color(0.55, 0.86, 0.6)
const SAY_BAD := Color(0.95, 0.55, 0.5)
const SAY_WARN := Color(0.95, 0.82, 0.5)
const SAY_NOTE := Color(0.84, 0.8, 0.72)
const HEAD := Color(0.93, 0.73, 0.3)
# The heading over Disband: the panel's heading colour, gone red.
const HEAD_DANGER := Color(0.9, 0.52, 0.45)
const WIDTH := 250.0
# Disband's second press, within this many seconds (the panel's own rule).
const ARM_SECONDS := 4.0
# The server's rule (the API's guilds/services.py GUILD_NAME_PATTERN and
# MAX_GUILD_NAME): a letter or number, then 2 to 11 of those, spaces, ' and -.
const NAME_MAX := 12
const NAME_MIN := 3
const NAME_RULE := "3 to 12 characters: letters, numbers, spaces, ' and -."

# Where requests go; seams for the suite.
var fetch: Callable = Callable(Api, "get_json")
var send: Callable = Callable(Api, "post")
# The panel's Results box (OwnerPanel._say), set by the panel.
var report: Callable = Callable()
# The last list from the server.
var guilds: Array = []

var status_label: Label
var guild_pick: OptionButton
var about_grid: GridContainer
var name_edit: LineEdit
var name_check_label: Label
var reason_edit: LineEdit
var rename_button: Button
var disband_note: Label
var disband_button: Button
var refresh_button: Button
var say_label: Label
var _busy: bool = false
var _armed_left: float = 0.0
var _now: int = 0


func _init() -> void:
	name = "guilds"
	add_theme_constant_override("separation", 6)
	_build()


func _build() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	add_child(top)
	refresh_button = _button("Refresh", "Read every guild again from the server.")
	refresh_button.name = "refresh"
	refresh_button.pressed.connect(refresh.bind(true))
	top.add_child(refresh_button)
	status_label = _label("Not read yet.", HealthTab.ROW_NAME, false)
	status_label.name = "status"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(status_label)

	add_child(_heading("EVERY GUILD"))
	guild_pick = OptionButton.new()
	guild_pick.name = "pick"
	guild_pick.focus_mode = Control.FOCUS_NONE
	guild_pick.clip_text = true
	guild_pick.custom_minimum_size = Vector2(WIDTH, 0)
	guild_pick.item_selected.connect(_on_picked)
	add_child(guild_pick)
	about_grid = GridContainer.new()
	about_grid.name = "about"
	about_grid.columns = 2
	about_grid.add_theme_constant_override("h_separation", 12)
	about_grid.add_theme_constant_override("v_separation", 3)
	about_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(about_grid)

	add_child(_gap())
	add_child(_heading("RENAME"))
	reason_edit = LineEdit.new()
	reason_edit.name = "reason"
	reason_edit.placeholder_text = "reason - kept in the moderation log"
	reason_edit.tooltip_text = "Needed for Rename and Disband. The moderation log keeps it, and who did it."
	reason_edit.max_length = 500
	add_child(reason_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	name_edit = LineEdit.new()
	name_edit.name = "newname"
	name_edit.placeholder_text = "new name"
	name_edit.tooltip_text = NAME_RULE + " It starts with a letter or a number."
	name_edit.max_length = NAME_MAX
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(_on_name_typed)
	row.add_child(name_edit)
	rename_button = _button("Rename", "Give it the new name. Its members keep their guild; its history says it was renamed, not by whom.")
	rename_button.name = "rename"
	rename_button.pressed.connect(rename)
	row.add_child(rename_button)
	name_check_label = _label(NAME_RULE, HealthTab.ROW_NAME)
	name_check_label.name = "namecheck"
	name_check_label.add_theme_font_size_override("font_size", 12)
	add_child(name_check_label)

	add_child(_gap())
	var danger := _heading("DISBAND")
	danger.add_theme_color_override("font_color", HEAD_DANGER)
	add_child(danger)
	var last := HBoxContainer.new()
	last.add_theme_constant_override("separation", 10)
	add_child(last)
	disband_button = _button("Disband", "Take the guild away from every member. Asks twice. Rename first if it is only the name.")
	disband_button.name = "disband"
	disband_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		disband_button.add_theme_color_override(state, SAY_BAD)
	disband_button.pressed.connect(disband)
	last.add_child(disband_button)
	disband_note = _label("", HealthTab.ROW_NAME)
	disband_note.name = "disbandnote"
	disband_note.custom_minimum_size = Vector2(150, 0)
	disband_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disband_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	last.add_child(disband_note)
	say_label = _label("", SAY_NOTE)
	say_label.name = "say"
	add_child(say_label)
	_show_list()


static func _heading(words: String) -> Label:
	var label := Label.new()
	label.text = words
	label.add_theme_color_override("font_color", Color(0.82, 0.7, 0.45))
	label.add_theme_font_size_override("font_size", 11)
	return label


static func _gap() -> Control:
	"""Room above a heading, after rows (as the Health tab has it)."""
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


func _label(text: String, colour: Color, wraps: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	if wraps:
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


func _say(line: String, colour: Color = SAY_NOTE) -> void:
	say_label.text = line
	say_label.add_theme_color_override("font_color", colour)
	if report.is_valid():
		report.call("[GUILDS] " + line, colour)


static func refusal(res: Dictionary) -> String:
	"""The server's own words for a refusal."""
	var status: int = int(res.get("status", 0))
	if status == 0:
		return "Could not reach the server."
	var said: Variant = res.get("data", {})
	var words: String = str((said as Dictionary).get("message", "")) if said is Dictionary else ""
	if words == "":
		words = str(res.get("error", ""))
	if status == 404 and words == "":
		return "This server does not know that guild, or does not have the guild routes."
	return "The server refused (%d): %s" % [status, words]


static func pick_text(guild: Dictionary) -> String:
	"""What the picker shows: 'The Can (5)'. The rest is in the rows."""
	return "%s (%d)" % [str(guild.get("name", "?")), int(guild.get("size", 0))]


static func line_for(guild: Dictionary) -> String:
	"""'The First - 5 members, led by Tunacan' (the picker's tooltip)."""
	var members: int = int(guild.get("size", 0))
	var leader: String = str(guild.get("leader", ""))
	return "%s - %d member%s%s" % [str(guild.get("name", "?")), members, "" if members == 1 else "s",
		", led by %s" % leader if leader != "" else ""]


static func about_text(guild: Dictionary, now: int) -> String:
	"""'Founded by Tunacan, Oct 28 14:02. 5 members, led by Tunacan.' (the
	rows' tooltip)."""
	var founded: int = int(guild.get("created_at", 0))
	var members: int = int(guild.get("size", 0))
	var bits: Array[String] = []
	var by: String = str(guild.get("founded_by", ""))
	if by != "" or founded > 0:
		bits.append("Founded%s%s." % [" by %s" % by if by != "" else "", ", %s" % LocalTime.stamp(founded, now) if founded > 0 else ""])
	bits.append("%d member%s%s." % [members, "" if members == 1 else "s",
		", led by %s" % str(guild.get("leader", "")) if str(guild.get("leader", "")) != "" else ""])
	return " ".join(bits)


static func about_rows(guild: Dictionary, now: int) -> Array:
	"""The one picked, as rows: each said once."""
	if guild.is_empty():
		return []
	var leader: String = str(guild.get("leader", ""))
	var founded: int = int(guild.get("created_at", 0))
	var when: String = "-"
	if founded > 0:
		var ago: String = LocalTime.ago(founded, now)
		when = LocalTime.date(founded) + (" (%s)" % ago if ago != "" else "")
	var by: String = str(guild.get("founded_by", ""))
	return [["Leader", leader if leader != "" else "nobody", HealthTab.ROW_VALUE if leader != "" else SAY_WARN],
		["Members", str(int(guild.get("size", 0)))],
		["Founded", when],
		["Founded by", by if by != "" else "-"]]


static func name_check(typed: String, current: String = "", taken: Array = []) -> Array:
	"""[what to say, its colour, whether Rename may send it] - the server's rule,
	said before the server has to refuse it."""
	var wanted: String = typed.strip_edges()
	if wanted == "":
		return [NAME_RULE, HealthTab.ROW_NAME, false]
	var first: String = wanted.left(1)
	if not _name_char(first) or first == " " or first == "'" or first == "-":
		return ["Start with a letter or a number.", SAY_BAD, false]
	for i in wanted.length():
		var one: String = wanted.substr(i, 1)
		if not _name_char(one):
			return ["Not allowed: \"%s\". Letters, numbers, spaces, ' and - only." % one, SAY_BAD, false]
	if wanted.length() < NAME_MIN:
		return ["At least %d characters (%d so far)." % [NAME_MIN, wanted.length()], SAY_BAD, false]
	if wanted.length() > NAME_MAX:
		return ["At most %d characters (%d)." % [NAME_MAX, wanted.length()], SAY_BAD, false]
	if wanted.to_lower() == current.to_lower():
		return ["That is its name already.", SAY_WARN, false]
	for other: Variant in taken:
		if str(other).to_lower() == wanted.to_lower():
			return ["Another guild is called that.", SAY_BAD, false]
	return ["Fits: %d of %d." % [wanted.length(), NAME_MAX], SAY_GOOD, true]


static func _name_char(one: String) -> bool:
	"""ASCII letters and numbers, space, ' and - (the server's [A-Za-z0-9 '\\-])."""
	if one.length() != 1:
		return false
	var code: int = one.unicode_at(0)
	return (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) \
		or one == " " or one == "'" or one == "-"


static func disband_text(guild: Dictionary) -> String:
	if guild.is_empty():
		return "Nothing to disband."
	var members: int = int(guild.get("size", 0))
	return "Takes %s from %s. Asks twice." % [
		str(guild.get("name", "?")), "its 1 member" if members == 1 else "all %d members" % members]


# =============================================================================
# THE SERVER
# =============================================================================

func refresh(by_hand: bool = false) -> void:
	"""Every guild, from the server; the one picked stays picked."""
	if _busy:
		return
	_busy = true
	var res: Dictionary = await fetch.call(LIST_PATH)
	_busy = false
	if not is_instance_valid(self):
		return
	if not res.get("ok", false) or not (res.get("data") is Dictionary):
		status_label.text = "Not read."
		_say(refusal(res), SAY_BAD)
		return
	var data: Dictionary = res.get("data")
	guilds = data.get("guilds", []) if data.get("guilds") is Array else []
	guilds.sort_custom(func(a: Variant, b: Variant) -> bool:
		return str((a as Dictionary).get("name", "")).to_lower() < str((b as Dictionary).get("name", "")).to_lower())
	_show_list(int(data.get("now", 0)))
	if by_hand:
		_say("Read %d guild%s from the server." % [guilds.size(), "" if guilds.size() == 1 else "s"], SAY_GOOD)


func picked() -> Dictionary:
	"""The guild picked, or {} for none."""
	var index: int = guild_pick.selected
	if index < 0 or index >= guilds.size():
		return {}
	return guilds[index]


func rename() -> void:
	var guild: Dictionary = picked()
	if _busy or guild.is_empty():
		return
	var wanted: String = name_edit.text.strip_edges()
	var why: String = reason_edit.text.strip_edges()
	if wanted == "":
		_say("Type the new name first.", SAY_BAD)
		return
	var fits: Array = name_check(wanted, str(guild.get("name", "")))
	if not bool(fits[2]):
		_say(str(fits[0]), SAY_BAD)
		return
	if why == "":
		_say("Give a reason - it goes in the moderation log.", SAY_BAD)
		return
	_busy = true
	_say("Renaming %s..." % str(guild.get("name", "")))
	var res: Dictionary = await send.call(ACT_PATH, {"guild": str(guild.get("name", "")), "action": "rename",
		"name": wanted, "reason": why})
	_busy = false
	if not is_instance_valid(self):
		return
	if not res.get("ok", false):
		_say(refusal(res), SAY_BAD)
		return
	var said: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	_say("Renamed %s to %s - its members were not told who did it." % [str(said.get("was", guild.get("name", ""))),
		str(said.get("guild", wanted))], SAY_GOOD)
	name_edit.text = ""
	_check_name()
	await refresh()


func disband() -> void:
	var guild: Dictionary = picked()
	if _busy or guild.is_empty():
		return
	var why: String = reason_edit.text.strip_edges()
	if why == "":
		_say("Give a reason - it goes in the moderation log.", SAY_BAD)
		return
	# ASKS TWICE, as a ban does: it takes the guild from every member.
	if _armed_left <= 0.0:
		_armed_left = ARM_SECONDS
		disband_button.text = "Sure? Disband"
		_say("Press again to disband %s." % str(guild.get("name", "")), SAY_BAD)
		return
	_disarm()
	_busy = true
	var res: Dictionary = await send.call(ACT_PATH, {"guild": str(guild.get("name", "")), "action": "disband",
		"reason": why})
	_busy = false
	if not is_instance_valid(self):
		return
	if not res.get("ok", false):
		_say(refusal(res), SAY_BAD)
		return
	var said: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	_say("Disbanded %s - %d member%s removed." % [str(said.get("guild", guild.get("name", ""))),
		int(said.get("members_removed", 0)), "" if int(said.get("members_removed", 0)) == 1 else "s"], SAY_GOOD)
	await refresh()


func _disarm() -> void:
	_armed_left = 0.0
	if disband_button != null:
		disband_button.text = "Disband"


func _process(delta: float) -> void:
	if _armed_left > 0.0:
		_armed_left -= delta
		if _armed_left <= 0.0 or not is_visible_in_tree():
			_disarm()


# =============================================================================
# WHAT IT SHOWS
# =============================================================================

func _show_list(now: int = 0) -> void:
	var kept: String = str(picked().get("name", "")) if guild_pick.item_count > 0 else ""
	guild_pick.clear()
	for guild in guilds:
		guild_pick.add_item(pick_text(guild))
		guild_pick.set_item_tooltip(guild_pick.item_count - 1, line_for(guild))
	var index: int = 0
	for i in guilds.size():
		if str((guilds[i] as Dictionary).get("name", "")) == kept:
			index = i
	if not guilds.is_empty():
		guild_pick.select(index)
	status_label.text = "No guilds yet." if guilds.is_empty() else "%d guild%s on the server" % [guilds.size(), "" if guilds.size() == 1 else "s"]
	guild_pick.disabled = guilds.is_empty()
	if now > 0:
		_now = now
	_show_about()


func _on_picked(_index: int) -> void:
	_disarm()
	_show_about()


func _show_about() -> void:
	var guild: Dictionary = picked()
	var now: int = _now if _now > 0 else int(Time.get_unix_time_from_system())
	HealthTab.fill_rows(about_grid, about_rows(guild, now), "" if guild.is_empty() else about_text(guild, now))
	guild_pick.tooltip_text = "" if guild.is_empty() else line_for(guild)
	disband_note.text = disband_text(guild)
	disband_button.disabled = guild.is_empty()
	_check_name()


func _on_name_typed(_text: String) -> void:
	_check_name()


func _check_name() -> void:
	"""The new name against the server's rule, as it is typed; Rename waits
	for one that fits."""
	var guild: Dictionary = picked()
	var taken: Array = []
	for other in guilds:
		if str((other as Dictionary).get("name", "")) != str(guild.get("name", "")):
			taken.append(str((other as Dictionary).get("name", "")))
	var said: Array = name_check(name_edit.text, str(guild.get("name", "")), taken)
	name_check_label.text = str(said[0])
	name_check_label.add_theme_color_override("font_color", said[1])
	rename_button.disabled = guild.is_empty() or not bool(said[2])
