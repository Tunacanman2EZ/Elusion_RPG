# partypanel.gd - Social > Party: who you are with, and asking somebody to
# join (0.42.0).
#
# The owner: "we need to be able to start parties so we need a tab for
# parties", and of what it should show: the members - each one's class,
# level, area and health - with party chat and each other on the map besides
# (chatpanel.gd's Party tab, mapscreen.gd).
#
# THE SERVER KEEPS THE PARTY (app.py, PARTIES); this window reads GET
# /api/party and posts each action, and every route answers with the whole
# party again, so the window draws exactly what the server holds. Two to
# four: anybody with no party may ask somebody, and the party is made when
# they accept; the leader asks, removes and hands it on; down to one, it is
# gone. An invitation waits two minutes for an answer.
#
# HEALTH, LIVE WHERE IT CAN BE: yours from your own character, a member in your
# area from their picture (remoteplayer.gd, THEIR AIM AND THEIR HEALTH), and
# anybody else from their last save - read again every REFRESH_SECONDS while
# the window is open.
#
# PARTY VOICE (0.43.0, voice.gd): the Voice switch, the microphone's mode (open,
# or push to talk on its key), Mute, and for each member in voice a mark that
# lights while they talk.
#
# VOICE SETTINGS (0.45.0): the owner, "add a settings for it in that menu so
# players can adjust voice volume". A button under the switch turns the member
# list into the settings and back: everyone's voices and each member's own
# (to 200%), this player's microphone (to 200%) with a level bar, the open-mic
# sensitivity (a line on that bar - only what crosses it goes out), and the
# browser's noise suppression and echo cancellation. Each is Voice's, kept on
# this machine, and can be set before voice is on.
extends Control
class_name PartyPanel


signal closed()


const REQUEST_TIMEOUT := 6.0
const REFRESH_SECONDS := 3.0
const NAME_COLOUR := Color(0.95, 0.92, 0.84)
const DETAIL_COLOUR := Color(0.72, 0.68, 0.62)
const AWAY_COLOUR := Color(0.55, 0.52, 0.5)
const GOOD_COLOUR := Color(0.6, 0.9, 0.7)
const LEADER_COLOUR := Color(1.0, 0.82, 0.42)

@onready var close_button: Button = get_node_or_null("%closebutton")
@onready var summary_label: Label = get_node_or_null("%summarylabel")
@onready var list: VBoxContainer = get_node_or_null("%list")
@onready var invites_box: VBoxContainer = get_node_or_null("%invites")
@onready var invite_row: HBoxContainer = get_node_or_null("%inviterow")
@onready var invite_name: LineEdit = get_node_or_null("%invitename")
@onready var invite_button: Button = get_node_or_null("%invitebutton")
@onready var leave_button: Button = get_node_or_null("%leavebutton")
@onready var notice_label: Label = get_node_or_null("%noticelabel")
@onready var voice_box: VBoxContainer = get_node_or_null("%voicebox")
@onready var voice_switch: CheckButton = get_node_or_null("%voiceswitch")
@onready var voice_mode: OptionButton = get_node_or_null("%voicemode")
@onready var mute_button: Button = get_node_or_null("%mutebutton")
@onready var voice_note: Label = get_node_or_null("%voicenote")
@onready var list_scroll: ScrollContainer = get_node_or_null("%listscroll")
@onready var settings_scroll: ScrollContainer = get_node_or_null("%settingsscroll")
@onready var settings_box: VBoxContainer = get_node_or_null("%voicesettings")
@onready var settings_button: Button = get_node_or_null("%settingsbutton")

# The settings' controls, made in _build_settings().
var voices_slider: HSlider
var voices_value: Label
var mic_slider: HSlider
var mic_value: Label
var mic_meter: MicMeter
var meter_note: Label
var sensitivity_slider: HSlider
var sensitivity_value: Label
var sensitivity_note: Label
var noise_box: CheckBox
var echo_box: CheckBox
var each_box: VBoxContainer

# Where requests go; seams for the suite, which answers them itself.
var fetch: Callable = Callable(self, "_fetch")
var send: Callable = Callable(self, "_send")
# The last answer from the server.
var answer: Dictionary = {}

var _window: PanelWindow
var _timer: Timer = null
var _busy: bool = false
# A volume slider is being dragged: the list is not rebuilt under it.
var _sliding: bool = false
# Set while the voice controls are drawn, so drawing them is not a press.
var _drawing_voice: bool = false


func _ready() -> void:
	_window = PanelWindow.attach(self, "party")
	if close_button != null:
		close_button.pressed.connect(close)
	if invite_button != null:
		invite_button.pressed.connect(_on_invite_pressed)
	if invite_name != null:
		invite_name.text_submitted.connect(func(_text: String) -> void: _on_invite_pressed())
	if leave_button != null:
		leave_button.pressed.connect(_on_leave_pressed)
	if voice_switch != null:
		voice_switch.toggled.connect(_on_voice_toggled)
	if voice_mode != null:
		voice_mode.clear()
		voice_mode.add_item("Open mic", 0)
		voice_mode.add_item("Push to talk", 1)
		voice_mode.item_selected.connect(_on_voice_mode)
	if mute_button != null:
		mute_button.toggled.connect(_on_mute_toggled)
	if settings_button != null:
		settings_button.toggled.connect(show_settings)
	_build_settings()
	Voice.changed.connect(_on_voice_changed)
	_timer = Timer.new()
	_timer.name = "refresh"
	_timer.wait_time = REFRESH_SECONDS
	_timer.timeout.connect(_on_refresh)
	add_child(_timer)
	visible = false


# =============================================================================
# OPENING AND CLOSING
# =============================================================================

func open() -> void:
	visible = true
	if _timer != null:
		_timer.start()
	await load_party()


func close() -> void:
	visible = false
	if _timer != null:
		_timer.stop()
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		await open()


func _on_refresh() -> void:
	if visible and not _busy:
		await load_party(true)


# =============================================================================
# THE SERVER
# =============================================================================

func load_party(quiet: bool = false) -> void:
	if _busy:
		return
	_busy = true
	if not quiet:
		_say("")
	var res: Dictionary = await fetch.call("/api/party")
	# PAST AN AWAIT: logging out frees every window, a door changes the scene.
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_busy = false
	if not bool(res.get("ok", false)):
		if not quiet:
			_say(refusal_text(res))
		return
	take(res.get("data", {}) if res.get("data", {}) is Dictionary else {})


func take(data: Dictionary) -> void:
	"""An answer from any party route: remember it, tell Party, draw it."""
	answer = data
	Party.apply(data.get("party") if data.get("party") is Dictionary else null)
	render()


func act(path: String, body: Dictionary, done_line: String = "") -> bool:
	"""Post one action; every route answers with the party, drawn at once."""
	var res: Dictionary = await send.call(path, body)
	if not is_instance_valid(self) or not is_inside_tree():
		return false
	if not bool(res.get("ok", false)):
		_say(refusal_text(res))
		return false
	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	if data.has("party"):
		take(data)
	else:
		await load_party(true)
	_say(done_line, true)
	return true


func _fetch(path: String) -> Dictionary:
	return await Api.get_json(path, REQUEST_TIMEOUT)


func _send(path: String, body: Dictionary) -> Dictionary:
	return await Api.post(path, body, REQUEST_TIMEOUT)


static func refusal_text(res: Dictionary) -> String:
	var status: int = int(res.get("status", 0))
	var message: String = str(res.get("error", ""))
	if status == 0:
		return message if message != "" else "No connection to the server."
	if status == 404 and message == "":
		# A game newer than its server: parties are a server change too.
		return "This server does not have parties yet."
	return message if message != "" else "Could not reach the party (HTTP %d)." % status


func _say(line: String, good: bool = false) -> void:
	if notice_label == null:
		return
	notice_label.text = line
	notice_label.visible = line != ""
	notice_label.add_theme_color_override("font_color", GOOD_COLOUR if good else Color(0.95, 0.55, 0.45))


# =============================================================================
# WHAT IT SHOWS
# =============================================================================

func party() -> Dictionary:
	return answer.get("party") if answer.get("party") is Dictionary else {}


func render() -> void:
	var p: Dictionary = party()
	var members: Array = p.get("members", []) if p.get("members", []) is Array else []
	var capacity: int = int(answer.get("capacity", p.get("capacity", 4)))
	var leading: bool = str(p.get("leader", "")) == Api.username
	if summary_label != null:
		if p.is_empty():
			summary_label.text = "You are in no party. Invite somebody to start one - up to %d of you." % capacity
		else:
			summary_label.text = "%d of %d - led by %s" % [members.size(), capacity, str(p.get("leader", ""))]
	if list != null and not _sliding:
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
		for member in members:
			if member is Dictionary:
				list.add_child(member_row(member, leading))
	_render_invites()
	if invite_row != null:
		invite_row.visible = p.is_empty() or (leading and members.size() < capacity)
	if leave_button != null:
		leave_button.visible = not p.is_empty()
	render_voice()


func member_row(member: Dictionary, leading: bool) -> Control:
	"""One member: their name (a star for the leader), what they are playing,
	where, their health - and, for the leader, Lead and Remove."""
	var who: String = str(member.get("username", ""))
	var row := VBoxContainer.new()
	row.name = "member_%s" % who
	row.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	row.add_child(top)
	var name_label := Label.new()
	name_label.name = "name"
	name_label.text = who
	name_label.add_theme_color_override("font_color", NAME_COLOUR if who == Api.username else Party.COLOUR)
	name_label.add_theme_font_size_override("font_size", 15)
	top.add_child(name_label)
	if bool(member.get("leader", false)):
		var lead_label := Label.new()
		lead_label.name = "leader"
		lead_label.text = "LEADER"
		lead_label.add_theme_color_override("font_color", LEADER_COLOUR)
		lead_label.add_theme_font_size_override("font_size", 11)
		top.add_child(lead_label)
	var detail := Label.new()
	detail.name = "detail"
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.text = detail_text(member)
	var online: bool = bool(member.get("online", false)) or who == Api.username
	detail.add_theme_color_override("font_color", DETAIL_COLOUR if online else AWAY_COLOUR)
	detail.add_theme_font_size_override("font_size", 13)
	detail.clip_text = true
	top.add_child(detail)
	if leading and who != Api.username:
		top.add_child(_small_button("Lead", "Hand the party to %s" % who,
			func() -> void: act("/api/party/lead", {"username": who}, "%s leads the party now." % who)))
		top.add_child(_small_button("Remove", "Take %s out of the party" % who,
			func() -> void: act("/api/party/kick", {"username": who}, "%s is out of the party." % who)))
	if Voice.is_on() and (who == Api.username or Voice.in_voice(who)):
		var mark := SpeakMark.new()
		mark.name = "voice"
		mark.who = who
		mark.tooltip_text = "In voice" if who == Api.username else "In voice - %s" % _call_words(who)
		top.add_child(mark)
		top.move_child(mark, 0)
	var bar := HealthStrip.new()
	bar.name = "health"
	bar.share = health_share(member)
	row.add_child(bar)
	return row


static func _call_words(who: String) -> String:
	match Voice.call_state(who):
		"connected":
			return "connected"
		"failed", "disconnected":
			return "the call dropped; it will try again"
		_:
			return "connecting"


func _small_button(words: String, hint: String, then: Callable) -> Button:
	var button := Button.new()
	button.text = words
	button.tooltip_text = hint
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(64, 24)
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(then)
	return button


static func detail_text(member: Dictionary) -> String:
	"""'Lv 12 Warrior - Field', or '- away' for somebody not on."""
	var cls: String = str(member.get("class_id", ""))
	var level: int = int(member.get("level", 0))
	var bits: Array[String] = []
	if level > 0 and cls != "":
		bits.append("Lv %d %s" % [level, cls.capitalize()])
	var area: String = str(member.get("area", ""))
	var online: bool = bool(member.get("online", false)) or str(member.get("username", "")) == Api.username
	if not online:
		bits.append("away")
	elif area != "":
		bits.append(AreaRegistry.display_name(area))
	return " - ".join(bits)


func health_share(member: Dictionary) -> float:
	"""How full their health is, 0 to 1 - live where this game can see them."""
	var who: String = str(member.get("username", ""))
	if who == Api.username:
		var me: Node = get_tree().get_first_node_in_group(&"player") if is_inside_tree() else null
		if me != null and "hp" in me and "max_hp" in me and int(me.get("max_hp")) > 0:
			return clampf(float(me.get("hp")) / float(me.get("max_hp")), 0.0, 1.0)
	var picture: Node = Presence.remote_named(who) if is_inside_tree() else null
	if picture != null and int(picture.get("health_percent")) >= 0:
		return float(picture.get("health_percent")) / 100.0
	var most: int = int(member.get("max_hp", 0))
	return clampf(float(member.get("hp", 0)) / float(most), 0.0, 1.0) if most > 0 else 0.0


# =============================================================================
# PARTY VOICE
# =============================================================================

func render_voice() -> void:
	"""The switch, the mode, Mute and the line under them, as Voice has them."""
	if voice_box == null:
		return
	voice_box.visible = not party().is_empty() or Voice.wanted()
	_drawing_voice = true
	if voice_switch != null:
		voice_switch.button_pressed = Voice.wanted()
		voice_switch.text = "Voice on" if Voice.is_on() else ("Voice..." if Voice.wanted() else "Voice")
	# PUSH TO TALK NEEDS A KEY (0.56.0). On a touch screen there is none to hold,
	# so it is not offered there - picked, the microphone never opened and the
	# window said "Hold V to talk" to a phone. A touch screen in that mode is
	# put back on Open mic.
	var touch: bool = TouchControls.active
	if touch and Voice.mode == Voice.MODE_PUSH:
		Voice.set_mode(Voice.MODE_OPEN)
	if voice_mode != null:
		voice_mode.select(1 if Voice.mode == Voice.MODE_PUSH else 0)
		voice_mode.set_item_text(1, PUSH_ON_TOUCH if touch else "Push to talk (%s)" % talk_key())
		voice_mode.set_item_disabled(1, touch)
	if mute_button != null:
		mute_button.button_pressed = Voice.muted
		mute_button.text = "Unmute" if Voice.muted else "Mute"
		mute_button.disabled = not Voice.is_on()
		mute_button.tooltip_text = "Your microphone (%s)" % mute_key()
	_drawing_voice = false
	if voice_note != null:
		voice_note.text = voice_line()
		voice_note.visible = voice_note.text != ""
	if not voice_box.visible and settings_open():
		show_settings(false)
	render_settings()


const PUSH_ON_TOUCH := "Push to talk (needs a keyboard)"


static func talk_key() -> String:
	var code: int = Settings.keys.first_key(Voice.TALK_ACTION) if Settings.keys != null else 0
	return Keybinds.key_name(code) if code != 0 else "no key"


static func mute_key() -> String:
	var code: int = Settings.keys.first_key(Voice.MUTE_ACTION) if Settings.keys != null else 0
	return Keybinds.key_name(code) if code != 0 else "no key"


static func voice_line() -> String:
	"""Under the switch: why voice is not on, or who is in it."""
	if Voice.note != "":
		return Voice.note
	if not Voice.is_on():
		return ""
	if Voice.members.is_empty():
		return "Nobody else is in voice yet."
	if Voice.muted:
		return "You are muted."
	if Voice.mode == Voice.MODE_PUSH:
		return "Hold %s to talk." % talk_key()
	return ""


func _on_voice_toggled(on: bool) -> void:
	if _drawing_voice:
		return
	await Voice.switch(on)
	if is_instance_valid(self):
		render_voice()


func _on_voice_mode(index: int) -> void:
	if not _drawing_voice:
		Voice.set_mode(Voice.MODE_PUSH if index == 1 else Voice.MODE_OPEN)


func _on_mute_toggled(on: bool) -> void:
	if not _drawing_voice:
		Voice.set_muted(on)


func _on_voice_changed() -> void:
	if is_instance_valid(self) and visible:
		render()


func _process(_delta: float) -> void:
	if not visible:
		return
	if settings_open() and mic_meter != null:
		mic_meter.queue_redraw()
		_render_meter_note()
	if list == null or not Voice.is_on():
		return
	for row in list.get_children():
		var mark: Node = row.find_child("voice", true, false)
		if mark is SpeakMark:
			(mark as SpeakMark).set_lit(Voice.speaking((mark as SpeakMark).who))


# =============================================================================
# VOICE SETTINGS (0.45.0)
# =============================================================================

func settings_open() -> bool:
	return settings_scroll != null and settings_scroll.visible


func show_settings(on: bool) -> void:
	"""The member list, or the voice settings in its place."""
	if settings_scroll == null or list_scroll == null:
		return
	settings_scroll.visible = on
	list_scroll.visible = not on
	if settings_button != null:
		settings_button.set_pressed_no_signal(on)
		settings_button.text = "Back to the party" if on else "Voice settings"
	if on:
		render_settings()


func _build_settings() -> void:
	if settings_box == null:
		return
	settings_box.add_child(_heading("VOICE SETTINGS"))
	var grid := GridContainer.new()
	grid.name = "levels"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	settings_box.add_child(grid)
	var made: Array = _slider_row(grid, "Voices", "How loud everyone in your party is - each one's own volume is below.",
		200.0, func(v: float) -> void: Voice.set_voices_volume(v / 100.0))
	voices_slider = made[0]
	voices_value = made[1]
	made = _slider_row(grid, "My microphone", "How loud you are to your party.",
		200.0, func(v: float) -> void: Voice.set_mic_volume(v / 100.0))
	mic_slider = made[0]
	mic_value = made[1]
	mic_meter = MicMeter.new()
	mic_meter.name = "meter"
	mic_meter.tooltip_text = "Your microphone. With open-mic sensitivity on, only what crosses the line goes out."
	settings_box.add_child(mic_meter)
	meter_note = _small_label("")
	meter_note.name = "meternote"
	settings_box.add_child(meter_note)
	var gate_grid := GridContainer.new()
	gate_grid.name = "gate"
	gate_grid.columns = 3
	gate_grid.add_theme_constant_override("h_separation", 8)
	settings_box.add_child(gate_grid)
	made = _slider_row(gate_grid, "Open-mic sensitivity",
		"With an open mic, send only what is louder than the line on the bar - keys and the room stay out.",
		100.0, func(v: float) -> void: Voice.set_sensitivity(v / 100.0))
	sensitivity_slider = made[0]
	sensitivity_value = made[1]
	sensitivity_note = _small_label("")
	sensitivity_note.name = "sensitivitynote"
	settings_box.add_child(sensitivity_note)
	var switches := HBoxContainer.new()
	switches.name = "switches"
	switches.alignment = BoxContainer.ALIGNMENT_CENTER
	switches.add_theme_constant_override("separation", 14)
	settings_box.add_child(switches)
	noise_box = _switch("Noise suppression", "Your browser takes steady noise - fans, hum - out of your microphone.")
	echo_box = _switch("Echo cancellation",
		"Your browser keeps your speakers out of your microphone. Turn it off only with headphones.")
	switches.add_child(noise_box)
	switches.add_child(echo_box)
	noise_box.toggled.connect(func(on: bool) -> void:
		if not _drawing_voice:
			Voice.set_processing(Voice.echo_cancel, on))
	echo_box.toggled.connect(func(on: bool) -> void:
		if not _drawing_voice:
			Voice.set_processing(on, Voice.noise_suppress))
	settings_box.add_child(_heading("EACH PLAYER"))
	each_box = VBoxContainer.new()
	each_box.name = "each"
	each_box.add_theme_constant_override("separation", 4)
	settings_box.add_child(each_box)


func _heading(words: String) -> Label:
	var label := Label.new()
	label.name = words.to_lower().replace(" ", "")
	label.text = words
	label.add_theme_color_override("font_color", LEADER_COLOUR)
	label.add_theme_font_size_override("font_size", 13)
	return label


func _small_label(words: String) -> Label:
	var label := Label.new()
	label.text = words
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", DETAIL_COLOUR)
	label.add_theme_font_size_override("font_size", 12)
	return label


func _switch(words: String, hint: String) -> CheckBox:
	var box := CheckBox.new()
	box.name = words.to_lower().replace(" ", "")
	box.text = words
	box.tooltip_text = hint
	box.focus_mode = Control.FOCUS_NONE
	box.add_theme_font_size_override("font_size", 13)
	return box


func _slider_row(grid: GridContainer, words: String, hint: String, most: float, then: Callable) -> Array:
	"""A name, a slider (0 to `most`, in percent) and its value, in `grid`."""
	var label := Label.new()
	label.text = words
	label.tooltip_text = hint
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.add_theme_color_override("font_color", NAME_COLOUR)
	label.add_theme_font_size_override("font_size", 13)
	grid.add_child(label)
	var slider := HSlider.new()
	slider.name = words.to_lower().replace(" ", "").replace("-", "")
	slider.min_value = 0.0
	slider.max_value = most
	slider.step = 5.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(110, 18)
	slider.focus_mode = Control.FOCUS_NONE
	slider.tooltip_text = hint
	grid.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size = Vector2(42, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_color_override("font_color", DETAIL_COLOUR)
	value.add_theme_font_size_override("font_size", 12)
	grid.add_child(value)
	slider.value_changed.connect(func(v: float) -> void:
		if not _drawing_voice:
			then.call(v)
		_render_values())
	slider.drag_started.connect(func() -> void: _sliding = true)
	slider.drag_ended.connect(func(_changed: bool) -> void: _sliding = false)
	return [slider, value]


static func percent(share: float) -> String:
	return "%d%%" % int(roundf(share * 100.0))


static func sensitivity_text(share: float) -> String:
	return "Off" if share <= 0.0 else percent(share)


func render_settings() -> void:
	"""The settings as Voice has them, and a volume for each other member."""
	if settings_box == null or voices_slider == null:
		return
	_drawing_voice = true
	voices_slider.set_value_no_signal(Voice.voices_volume * 100.0)
	mic_slider.set_value_no_signal(Voice.mic_volume * 100.0)
	sensitivity_slider.set_value_no_signal(Voice.sensitivity * 100.0)
	sensitivity_slider.editable = Voice.mode == Voice.MODE_OPEN
	noise_box.set_pressed_no_signal(Voice.noise_suppress)
	echo_box.set_pressed_no_signal(Voice.echo_cancel)
	_drawing_voice = false
	_render_values()
	if sensitivity_note != null:
		if Voice.mode != Voice.MODE_OPEN:
			sensitivity_note.text = "Push to talk: holding %s decides what goes out." % talk_key()
		elif Voice.sensitivity <= 0.0:
			sensitivity_note.text = "Off: an open mic sends everything it hears."
		else:
			sensitivity_note.text = "Only what crosses the line on the bar goes out."
	_render_meter_note()
	if each_box != null and not _sliding:
		for child in each_box.get_children():
			each_box.remove_child(child)
			child.queue_free()
		var others: Array = []
		var p: Dictionary = party()
		for member in (p.get("members", []) if p.get("members", []) is Array else []):
			if member is Dictionary and str(member.get("username", "")) != Api.username:
				others.append(str(member.get("username", "")))
		if others.is_empty():
			each_box.add_child(_small_label("Nobody else is in your party yet."))
		var grid := GridContainer.new()
		grid.name = "players"
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 8)
		each_box.add_child(grid)
		for who in others:
			var made: Array = _slider_row(grid, who, "How loud %s is to you" % who, 200.0,
				func(v: float) -> void: Voice.set_volume(who, v / 100.0))
			(made[0] as HSlider).name = "volume_%s" % who
			_drawing_voice = true
			(made[0] as HSlider).set_value_no_signal(Voice.volume_of(who) * 100.0)
			_drawing_voice = false
			(made[1] as Label).text = percent(Voice.volume_of(who))
			var name_label: Label = grid.get_child(grid.get_child_count() - 3) as Label
			if name_label != null:
				name_label.add_theme_color_override("font_color", Party.COLOUR)


func _render_values() -> void:
	if voices_value != null:
		voices_value.text = percent(voices_slider.value / 100.0)
	if mic_value != null:
		mic_value.text = percent(mic_slider.value / 100.0)
	if sensitivity_value != null:
		sensitivity_value.text = sensitivity_text(sensitivity_slider.value / 100.0)
	if each_box != null:
		var grid: Node = each_box.get_node_or_null(^"players")
		if grid != null:
			for i in range(1, grid.get_child_count(), 3):
				var slider: HSlider = grid.get_child(i) as HSlider
				var value: Label = grid.get_child(i + 1) as Label if i + 1 < grid.get_child_count() else null
				if slider != null and value != null:
					value.text = percent(slider.value / 100.0)


func _render_meter_note() -> void:
	if meter_note == null:
		return
	var words: String = ""
	if not Voice.is_on():
		words = "Switch voice on to see your microphone here."
	elif Voice.muted:
		words = "You are muted - the bar still shows what you would send."
	elif Voice.mode == Voice.MODE_OPEN and Voice.sensitivity > 0.0 and not Voice.gate_open:
		words = "Quiet: nothing is going out."
	if meter_note.text != words:
		meter_note.text = words
	meter_note.visible = words != ""


class MicMeter extends Control:
	"""The microphone's level, and the open-mic sensitivity as a line across
	it: green while what it hears is going out."""
	const BACK := Color(0.08, 0.07, 0.09, 0.9)
	const SENDING := Color(0.35, 0.85, 0.45)
	const HELD := Color(0.45, 0.45, 0.48)
	const LINE := Color(1.0, 0.82, 0.42)

	func _init() -> void:
		custom_minimum_size = Vector2(0, 12)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func sending() -> bool:
		return Voice.mic_open() and Voice.gate_open

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), BACK)
		var filled: float = roundf(size.x * Voice.meter_share())
		if filled > 0.0:
			draw_rect(Rect2(Vector2.ZERO, Vector2(filled, size.y)), SENDING if sending() else HELD)
		if Voice.mode == Voice.MODE_OPEN and Voice.sensitivity > 0.0:
			var x: float = roundf(size.x * Voice.sensitivity)
			draw_rect(Rect2(Vector2(x - 1.0, 0.0), Vector2(2.0, size.y)), LINE)


func _render_invites() -> void:
	if invites_box == null:
		return
	for child in invites_box.get_children():
		invites_box.remove_child(child)
		child.queue_free()
	var waiting: Array = answer.get("invites", []) if answer.get("invites", []) is Array else []
	for one in waiting:
		if not (one is Dictionary):
			continue
		var from: String = str(one.get("from", ""))
		var row := HBoxContainer.new()
		row.name = "invite_%s" % from
		row.add_theme_constant_override("separation", 6)
		var words := Label.new()
		words.text = "%s invites you to their party" % from
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_theme_color_override("font_color", Party.COLOUR)
		words.add_theme_font_size_override("font_size", 13)
		row.add_child(words)
		row.add_child(_small_button("Join", "Join %s's party" % from,
			func() -> void: act("/api/party/respond", {"from": from, "accept": true}, "You are in %s's party." % from)))
		row.add_child(_small_button("No", "Turn it down",
			func() -> void: act("/api/party/respond", {"from": from, "accept": false})))
		invites_box.add_child(row)
	invites_box.visible = invites_box.get_child_count() > 0


# =============================================================================
# ASKING AND LEAVING
# =============================================================================

func _on_invite_pressed() -> void:
	if invite_name == null:
		return
	var who: String = invite_name.text.strip_edges()
	if who == "":
		_say("Type a name to invite.")
		return
	if await act("/api/party/invite", {"username": who},
			"Asked %s - the invitation waits two minutes." % who):
		invite_name.text = ""


func invite_player(who: String) -> void:
	"""Asked from elsewhere - a right-click in the players list: the window
	opens and the invitation goes from it, so its answer is seen."""
	if not visible:
		await open()
	if invite_name != null:
		invite_name.text = who
	_on_invite_pressed()


func _on_leave_pressed() -> void:
	await act("/api/party/leave", {}, "You left the party.")


# =============================================================================
# A MEMBER'S HEALTH
# =============================================================================

class SpeakMark extends Control:
	"""A small speaker, lit while `who` talks."""
	const LIT := Color(0.55, 1.0, 0.6)
	const DIM := Color(0.45, 0.5, 0.48)
	var who: String = ""
	var lit: bool = false

	func _init() -> void:
		custom_minimum_size = Vector2(16, 16)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func set_lit(on: bool) -> void:
		if on != lit:
			lit = on
			queue_redraw()

	func _draw() -> void:
		var c: Color = LIT if lit else DIM
		var mid: Vector2 = size / 2.0
		draw_rect(Rect2(mid + Vector2(-6, -2), Vector2(3, 4)), c)
		draw_colored_polygon(PackedVector2Array([mid + Vector2(-3, -2), mid + Vector2(1, -5),
			mid + Vector2(1, 5), mid + Vector2(-3, 2)]), c)
		if lit:
			draw_arc(mid + Vector2(1, 0), 4.0, -0.9, 0.9, 6, c, 1.0)
			draw_arc(mid + Vector2(1, 0), 7.0, -0.9, 0.9, 8, c, 1.0)


class HealthStrip extends Control:
	"""A member's health: a thin bar across the row, green to red as it falls."""
	var share: float = 1.0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 5)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.07, 0.09, 0.9))
		var colour: Color = Color(0.35, 0.85, 0.35) if share > 0.5 \
			else (Color(0.95, 0.8, 0.25) if share > 0.25 else Color(0.9, 0.25, 0.2))
		var filled: float = roundf(size.x * clampf(share, 0.0, 1.0))
		if filled > 0.0:
			draw_rect(Rect2(Vector2.ZERO, Vector2(filled, size.y)), colour)
