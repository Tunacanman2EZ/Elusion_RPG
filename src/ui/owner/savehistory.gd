# savehistory.gd - the owner's Save history: a player's character as it was,
# and a button that puts it back.
#
# The owner, 6 Oct: "roll back and give player item might be useful". The
# server keeps each character a few times over (save_snapshots; SAVE SNAPSHOTS
# AND ROLLBACK in app.py): when the game saves - at most every ten minutes, and
# only when something has changed - before the owner gives them an item, and
# before a rollback, so that a rollback can itself be undone. This window lists
# them for one player and restores one.
#
# - OPENED FROM THE GM PANEL'S Account tab with the name in its username box,
#   or typed here. The character list says which of the account's characters;
#   it starts on the one they are playing.
# - RESTORE ASKS TWICE. The first press turns that row's button into "Sure?"
#   for ARM_SECONDS; a second press inside them sends it. Any other press, a
#   reload or closing the window disarms it.
# - WHAT IT SAYS AFTERWARDS is the server's own answer: what the character was,
#   what it is now, and whether a game was signed out to reload it. The list is
#   read again, and its top line is the snapshot that undoes what just happened.
# - WHAT A ROLLBACK DOES NOT DO is written at the bottom of the window, because
#   it is the part that surprises: the bank and lusions are the account's and
#   stay, and an item traded away since comes back as a second copy.
#
# OWNER ONLY, three times over, like the item catalogue: the HUD builds it only
# for the owner, every request here asks Api.is_owner first, and the server is
# the gate that counts - require_owner, a bare 404 to anybody else.
class_name SaveHistory
extends Control


const HISTORY_PATH := "/api/staff/snapshots"
const ROLLBACK_PATH := "/api/staff/rollback"

# How long a Restore stays armed. Long enough to move the mouse back and press
# again; short enough that nobody comes back to a loaded button.
const ARM_SECONDS := 4.0

# Why a snapshot was taken, as the list says it. A save says nothing - it is
# what nearly every line is.
const REASON_WORDS := {
	"save": "",
	"before-give": "before a gift",
	"before-rollback": "before a rollback",
	# 0.21.0: the GM panel's Set their level.
	"before-level": "before a level change",
}

const COLOUR_BAD := Color(1.0, 0.55, 0.45)
const COLOUR_PLAIN := Color(0.73, 0.78, 0.84)
const COLOUR_ARMED := Color(1.0, 0.62, 0.5)

var _window: PanelWindow = null
var _busy: bool = false

# Whose history is on screen, as the server named them, and which character.
var _username: String = ""
var _slot: int = -1
# [slot, label] for every character on the account, in the order listed.
var _characters: Array = []

# The snapshot whose Restore was pressed once, and until when that counts.
var _armed_id: int = -1
var _armed_until: float = 0.0

# WHERE A REQUEST GOES, as Callables so the suite can answer without a server.
# In the game they are Api.get_json and Api.post.
var get_request: Callable
var post_request: Callable

@onready var name_input: LineEdit = %historyname
@onready var slot_pick: OptionButton = %historyslot
@onready var load_button: Button = %historyload
@onready var now_label: Label = %historynow
@onready var list: VBoxContainer = %historylist
@onready var status: Label = %historystatus
@onready var close_button: Button = %historyclose


func _init() -> void:
	get_request = Callable(Api, "get_json")
	post_request = Callable(Api, "post")


func _ready() -> void:
	_window = PanelWindow.attach(self, "savehistory")
	close_button.pressed.connect(close)
	load_button.pressed.connect(func() -> void: load_history(name_input.text))
	name_input.text_submitted.connect(func(typed: String) -> void: load_history(typed))
	slot_pick.item_selected.connect(_on_slot_picked)


func open_for(username: String) -> void:
	"""Show the window, and the history of `username` if one is named."""
	visible = true
	var who: String = username.strip_edges()
	if who == "":
		_say("Type a player's name, then Load.")
		name_input.grab_focus()
		return
	name_input.text = who
	await load_history(who)


func close() -> void:
	visible = false
	_disarm()


# =============================================================================
# READING
# =============================================================================

func load_history(username: String, slot: int = -1) -> void:
	"""Ask the server for one character's snapshots. slot -1 is the character
	they are playing (the server's PLAYING_SLOT_SQL)."""
	if not Api.is_owner:
		_say("The save history is the owner's.", true)
		return
	var who: String = username.strip_edges()
	if who == "":
		_say("Type a player's name first.", true)
		return
	if _busy:
		return
	_busy = true
	_disarm()
	_say("Reading %s's save history..." % who)
	var path: String = "%s?username=%s" % [HISTORY_PATH, who.uri_encode()]
	if slot >= 0:
		path += "&slot=%d" % slot
	var res: Dictionary = await get_request.call(path)
	_busy = false
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not res.get("ok", false):
		_username = ""
		_slot = -1
		_clear_list()
		now_label.text = ""
		_say(_refused(res), true)
		return
	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	show_history(data)


func show_history(data: Dictionary) -> void:
	"""Draw what GET /api/staff/snapshots answered."""
	_username = str(data.get("username", ""))
	_slot = int(data.get("slot", -1))
	var playing: int = int(data.get("playing", -1)) if data.get("playing") != null else -1

	_characters.clear()
	slot_pick.clear()
	var characters: Array = data.get("characters", []) if data.get("characters", []) is Array else []
	for entry in characters:
		if not (entry is Dictionary):
			continue
		var index: int = int(entry.get("slot", -1))
		var label: String = "%s, level %d" % [str(entry.get("name", entry.get("class_id", "?"))),
			int(entry.get("level", 1))]
		if index == playing:
			label += " (playing)"
		_characters.append([index, label])
		slot_pick.add_item(label)
		if index == _slot:
			slot_pick.select(slot_pick.item_count - 1)

	var now: Dictionary = data.get("now", {}) if data.get("now", {}) is Dictionary else {}
	now_label.text = "%s's %s now: level %d, %d gold, %d carried." % [
		_username, str(now.get("name", now.get("class_id", "?"))), int(now.get("level", 1)),
		int(now.get("gold", 0)), int(now.get("items", 0))]

	_clear_list()
	var snapshots: Array = data.get("snapshots", []) if data.get("snapshots", []) is Array else []
	for entry in snapshots:
		if entry is Dictionary:
			list.add_child(_snapshot_row(entry))
	if snapshots.is_empty():
		_say("No snapshots yet. One is kept when their game saves, at most every %d minutes, once something has changed."
			% maxi(1, int(float(data.get("every_seconds", 600)) / 60.0)))
	else:
		_say("%d snapshot%s, newest first. The server keeps the last %d." % [
			snapshots.size(), "" if snapshots.size() == 1 else "s", int(data.get("kept", snapshots.size()))])


func _snapshot_row(entry: Dictionary) -> HBoxContainer:
	var id: int = int(entry.get("id", -1))
	var row := HBoxContainer.new()
	row.name = "snap_%d" % id
	row.add_theme_constant_override("separation", 6)

	var when := Label.new()
	when.name = "when"
	when.text = LocalTime.stamp(int(entry.get("taken_at", 0)))
	when.custom_minimum_size = Vector2(80, 0)
	when.add_theme_font_size_override("font_size", 12)
	when.tooltip_text = LocalTime.full(int(entry.get("taken_at", 0)))
	when.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(when)

	var what := Label.new()
	what.name = "what"
	what.text = "level %d · %d gold · %d carried" % [
		int(entry.get("level", 1)), int(entry.get("gold", 0)), int(entry.get("items", 0))]
	var why: String = str(REASON_WORDS.get(str(entry.get("reason", "")), ""))
	if why != "":
		what.text += " · " + why
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	what.clip_text = true
	what.add_theme_font_size_override("font_size", 12)
	row.add_child(what)

	var button := Button.new()
	button.name = "restore"
	button.text = "Restore"
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "Put the character back to this. Press twice."
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(press_restore.bind(id))
	row.add_child(button)
	return row


func _clear_list() -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()


func _on_slot_picked(index: int) -> void:
	if index < 0 or index >= _characters.size() or _username == "":
		return
	load_history(_username, int(_characters[index][0]))


# =============================================================================
# RESTORING
# =============================================================================

func press_restore(snapshot_id: int) -> void:
	"""A Restore button. The first press arms it; the second, inside
	ARM_SECONDS, sends it."""
	if not Api.is_owner:
		_say("The save history is the owner's.", true)
		return
	if _busy:
		return
	var now_s: float = Time.get_ticks_msec() / 1000.0
	if _armed_id != snapshot_id or now_s > _armed_until:
		_arm(snapshot_id)
		return
	_disarm()
	await restore(snapshot_id)


func is_armed(snapshot_id: int) -> bool:
	return _armed_id == snapshot_id and Time.get_ticks_msec() / 1000.0 <= _armed_until


func _arm(snapshot_id: int) -> void:
	_disarm()
	var button: Button = _restore_button(snapshot_id)
	if button == null:
		return
	_armed_id = snapshot_id
	_armed_until = Time.get_ticks_msec() / 1000.0 + ARM_SECONDS
	button.text = "Sure?"
	button.add_theme_color_override("font_color", COLOUR_ARMED)
	_say("Press Sure? to put %s back. It signs them out so their game reloads it." % _username)
	# A TIMER, NOT _process: nothing here needs to run every frame for a
	# button that is pressed twice a month.
	if is_inside_tree():
		get_tree().create_timer(ARM_SECONDS + 0.05).timeout.connect(_disarm_if_stale.bind(snapshot_id))


func _disarm_if_stale(snapshot_id: int) -> void:
	# Only the press this timer was started for, and only once it has run out:
	# a second, later arm of the same row has a timer of its own.
	if _armed_id == snapshot_id and not is_armed(snapshot_id):
		_disarm()


func _disarm() -> void:
	if _armed_id >= 0:
		var button: Button = _restore_button(_armed_id)
		if button != null:
			button.text = "Restore"
			button.remove_theme_color_override("font_color")
	_armed_id = -1
	_armed_until = 0.0


func _restore_button(snapshot_id: int) -> Button:
	var row: Node = list.get_node_or_null("snap_%d" % snapshot_id) if list != null else null
	return row.get_node_or_null("restore") as Button if row != null else null


func restore(snapshot_id: int) -> void:
	"""POST /api/staff/rollback, then read the list again and say what changed."""
	if not Api.is_owner or _username == "":
		return
	_busy = true
	_say("Putting %s back..." % _username)
	var res: Dictionary = await post_request.call(ROLLBACK_PATH,
		{"username": _username, "snapshot_id": snapshot_id})
	_busy = false
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not res.get("ok", false):
		_say(_refused(res), true)
		return
	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	var line: String = restored_line(data, Api.username)
	await load_history(_username, _slot)
	_say(line)


static func restored_line(data: Dictionary, me: String) -> String:
	"""What a rollback did, in a sentence, from the server's answer."""
	var was: Dictionary = data.get("was", {}) if data.get("was", {}) is Dictionary else {}
	var now: Dictionary = data.get("now", {}) if data.get("now", {}) is Dictionary else {}
	var who: String = str(data.get("username", "?"))
	# NO ARROWS: the game's font has no U+2192, and a browser draws a box.
	var line: String = "Put %s's %s back to %s. It was level %d, %d gold, %d carried; now level %d, %d gold, %d carried." % [
		who, str(data.get("character", "character")), LocalTime.stamp(int(data.get("taken_at", 0))),
		int(was.get("level", 0)), int(was.get("gold", 0)), int(was.get("items", 0)),
		int(now.get("level", 0)), int(now.get("gold", 0)), int(now.get("items", 0))]
	if who.to_lower() == me.to_lower():
		line += " You are being signed out so your game reloads it."
	elif int(data.get("sessions_ended", 0)) > 0:
		line += " They were signed out so their game reloads it."
	else:
		line += " They were not signed in; they get it when they next sign in."
	if bool(data.get("pet_cleared", false)):
		line += " The pet it had out is held nowhere now, so none is out."
	line += " The top line undoes this."
	return line


# =============================================================================
# SAYING
# =============================================================================

func _refused(res: Dictionary) -> String:
	# The server's own sentence when there is one, as the GM panel says it.
	var code: int = int(res.get("status", 0))
	var said: String = str(res.get("error", "")).strip_edges()
	if code == 0:
		return ApiScript.no_answer_text()
	if code == 404 and (said == "" or said == "Not found."):
		return "The server refused - is it running the latest app.py?"
	if said != "":
		return said
	return "Refused (HTTP %d)." % code


const ApiScript := preload("res://src/systems/api.gd")


func _say(line: String, bad: bool = false) -> void:
	if status == null:
		return
	status.text = line
	status.add_theme_color_override("font_color", COLOUR_BAD if bad else COLOUR_PLAIN)
