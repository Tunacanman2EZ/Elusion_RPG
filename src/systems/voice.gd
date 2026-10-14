# voice.gd - PARTY VOICE (0.43.0), the Voice autoload.
#
# The owner: "I really really want the option for voice chat in game for
# parties ... could even be a flappable switch". Asked how, he chose the
# browser's own calling through Cloudflare's relay.
#
# THE SWITCH IS THE PARTY WINDOW'S. Voice on: the server hands out the relay
# (GET /api/party/voice - only to somebody in a party), the browser asks for
# the microphone, and once it has it this game tells the presence socket it is
# in voice ("vs"). The socket answers with who in the party already is, and
# this game calls each of them; anybody who comes in later calls this one. The
# calls themselves are the browser's (voicebridge.gd), and their setup travels
# over the presence socket ("vc"), which passes it only between two games in
# voice in the same party (presence.py, PARTY VOICE).
#
# THE MICROPHONE: open, or push-to-talk on a key (Push to talk, V by default),
# and a mute key (Mute my microphone, B) that beats both. Each other voice has
# its own volume. Both, and the mode, are kept in user://voice.cfg - this
# machine's, like the keys.
#
# THE SETTINGS (0.45.0, the Party window's Voice settings): how loud everyone's
# voices are (voices_volume, to 200%, times each one's own), how loud this
# player is to them (mic_volume, to 200%), the open-mic sensitivity (only what
# is louder than it goes out - the level bar shows both), and the browser's
# noise suppression and echo cancellation. Kept in voice.cfg too, and given to
# the page before it starts, so they hold from the first word.
#
# OFF BY ITSELF when the party goes (left, removed, disbanded) - the server
# takes the game out of voice within seconds and says so, and the poll's Party
# says it here too - and when the window or the game closes. A link that drops
# and comes back says it is in voice again; the calls already made carry on,
# since they never went through it.
#
# Off the web there is no browser to call with: the switch says voice is in
# the browser version, for now.
extends Node


signal changed()

const VOICE_PATH := "/api/party/voice"
const REQUEST_TIMEOUT := 8.0
# How often the page is asked what to send and who is speaking.
const POLL_SECONDS := 0.1
# Loudness (0-1, the root of the mean square) over which somebody is speaking.
const SPEAKING_LEVEL := 0.05
# The most a voice, or the microphone, can be turned up: 200%.
const MOST_VOLUME := 2.0
# The loudness the sensitivity slider's top end stands for, and the level
# bar's full width - the same scale, so the line on the bar is the slider.
const GATE_TOP := 0.3
# How long to wait for the browser's microphone answer before giving up.
const MIC_WAIT_SECONDS := 30.0
const MODE_OPEN := "open"
const MODE_PUSH := "push"
const TALK_ACTION := "voice_talk"
const MUTE_ACTION := "voice_mute"
const SECTION := "voice"

static var path: String = "user://voice.cfg"

# The page's calls (VoiceBridge on the web), or a stand-in from the suite; null
# where there is none.
var bridge: Object = null
# Where requests go, and whether the presence link is up; seams for the suite.
var fetch: Callable = Callable(self, "_fetch")
var link_open: Callable = Callable(Presence, "is_open")
# off, asking (the relay), starting (the microphone), on.
var state: String = "off"
# One line for the Party window: what is happening, or why it is not.
var note: String = ""
var muted: bool = false
var mode: String = MODE_OPEN
# username -> 0..MOST_VOLUME, each other voice's own volume.
var volumes: Dictionary = {}
# Everyone's voices, times each one's own; this player's microphone.
var voices_volume: float = 1.0
var mic_volume: float = 1.0
# Open-mic sensitivity, 0 to 1 of GATE_TOP: 0 sends everything.
var sensitivity: float = 0.0
# The browser's own cleaning of the microphone.
var echo_cancel: bool = true
var noise_suppress: bool = true
# The others in voice now: user id -> username.
var members: Dictionary = {}
# username -> loudness, and username -> the call's state, from the page.
var levels: Dictionary = {}
var calls: Dictionary = {}
var my_level: float = 0.0
# The microphone's level whether or not it is going out (the level bar), and
# whether the open-mic gate is letting it out.
var mic_level: float = 0.0
var gate_open: bool = true

var _poll: float = 0.0
var _waited: float = 0.0
var _link_was_open: bool = false
var _talk_held: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	if bridge == null:
		bridge = VoiceBridge.make()
	Presence.voice_message.connect(hear)


func _notification(what: int) -> void:
	# A key let go while the window had no focus never arrives: push-to-talk
	# would stay open. Losing focus lets go of it.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _talk_held:
		_talk_held = false
		_apply_mic()
		changed.emit()


func available() -> bool:
	return bridge != null


func is_on() -> bool:
	return state == "on"


func wanted() -> bool:
	return state != "off"


# =============================================================================
# THE SWITCH
# =============================================================================

func switch(on: bool) -> void:
	if on == wanted():
		return
	if on:
		await _start()
	else:
		stop("")


func _start() -> void:
	if bridge == null:
		_say("Voice is in the browser version of the game for now.")
		return
	if not Party.in_one():
		_say("Voice is for parties: invite somebody first.")
		return
	state = "asking"
	note = "Connecting voice..."
	changed.emit()
	var res: Dictionary = await fetch.call(VOICE_PATH)
	if state != "asking":
		return
	var data: Variant = res.get("data", {})
	if not res.get("ok", false) or not (data is Dictionary):
		state = "off"
		_say(refusal_text(res))
		return
	var config := {
		"ice_servers": data.get("ice_servers", []),
		"policy": "all" if str(data.get("policy", "relay")) == "all" else "relay",
		"me": Presence.my_id(),
	}
	# THE SETTINGS FIRST, so the microphone opens with them.
	bridge.set_processing(echo_cancel, noise_suppress)
	bridge.set_mic_volume(mic_volume)
	_apply_gate()
	bridge.start(JSON.stringify(config))
	state = "starting"
	_waited = 0.0
	note = "Allow the microphone when your browser asks."
	changed.emit()


func stop(why: String = "") -> void:
	"""Out of voice: every call hung up, the microphone let go, and the socket
	told. `why` is what the Party window says."""
	var was_in: bool = state == "on"
	state = "off"
	if bridge != null:
		bridge.stop()
	if was_in:
		Presence.send_voice({"t": "vs", "on": false})
	members.clear()
	levels.clear()
	calls.clear()
	my_level = 0.0
	mic_level = 0.0
	gate_open = true
	_say(why)


func _say(line: String) -> void:
	note = line
	changed.emit()


static func refusal_text(res: Dictionary) -> String:
	var status: int = int(res.get("status", 0))
	var message: String = str(res.get("error", ""))
	if status == 0:
		return message if message != "" else "No connection to the server."
	if status == 404 and message == "":
		return "This server does not have voice yet."
	return message if message != "" else "Voice could not start (HTTP %d)." % status


func _fetch(route: String) -> Dictionary:
	return await Api.get_json(route, REQUEST_TIMEOUT)


# =============================================================================
# THE MICROPHONE
# =============================================================================

func set_muted(on: bool) -> void:
	muted = on
	_apply_mic()
	save_settings()
	changed.emit()


func set_mode(new_mode: String) -> void:
	mode = MODE_PUSH if new_mode == MODE_PUSH else MODE_OPEN
	_apply_mic()
	_apply_gate()
	save_settings()
	changed.emit()


func mic_open() -> bool:
	"""Whether this game's voice is going out now."""
	return state == "on" and not muted and (mode == MODE_OPEN or _talk_held)


func _apply_mic() -> void:
	if bridge != null and state == "on":
		bridge.set_mic(mic_open())


func _unhandled_input(event: InputEvent) -> void:
	# A key typed into chat never reaches here: the text box takes it.
	if state != "on":
		return
	if event.is_action_pressed(MUTE_ACTION) and not event.is_echo():
		set_muted(not muted)
	if event.is_action(TALK_ACTION) and not event.is_echo():
		var held: bool = event.is_pressed()
		if held != _talk_held:
			_talk_held = held
			_apply_mic()
			changed.emit()


func volume_of(username: String) -> float:
	"""`username`'s own volume, 0 to MOST_VOLUME (1 is as they come)."""
	return clampf(float(volumes.get(username.to_lower(), 1.0)), 0.0, MOST_VOLUME)


func heard_volume(username: String) -> float:
	"""How loud `username` is played: everyone's volume times their own, at
	most MOST_VOLUME."""
	return clampf(voices_volume * volume_of(username), 0.0, MOST_VOLUME)


func set_volume(username: String, volume: float) -> void:
	volumes[username.to_lower()] = clampf(volume, 0.0, MOST_VOLUME)
	_apply_volumes()
	save_settings()


func set_voices_volume(volume: float) -> void:
	voices_volume = clampf(volume, 0.0, MOST_VOLUME)
	_apply_volumes()
	save_settings()


func _apply_volumes() -> void:
	if bridge == null:
		return
	for id in members:
		bridge.set_volume(int(id), heard_volume(str(members[id])))


# =============================================================================
# THE SETTINGS (0.45.0)
# =============================================================================

func set_mic_volume(volume: float) -> void:
	mic_volume = clampf(volume, 0.0, MOST_VOLUME)
	if bridge != null:
		bridge.set_mic_volume(mic_volume)
	save_settings()


func set_sensitivity(share: float) -> void:
	"""Open-mic sensitivity, 0 (send everything) to 1 (only the loudest)."""
	sensitivity = clampf(share, 0.0, 1.0)
	_apply_gate()
	save_settings()


func gate_level() -> float:
	"""The loudness under which an open mic sends nothing - 0 for push to
	talk, which the key gates already, and with the sensitivity off."""
	return sensitivity * GATE_TOP if mode == MODE_OPEN else 0.0


func _apply_gate() -> void:
	if bridge != null:
		bridge.set_gate(gate_level())


func set_processing(echo: bool, noise: bool) -> void:
	"""The browser's echo cancellation and noise suppression. Changed with
	voice on, the page opens the microphone again with them, mid-call."""
	echo_cancel = echo
	noise_suppress = noise
	if bridge != null:
		bridge.set_processing(echo_cancel, noise_suppress)
	save_settings()


func meter_share() -> float:
	"""The microphone's level as a share of the level bar, 0 to 1."""
	return clampf(mic_level / GATE_TOP, 0.0, 1.0)


# =============================================================================
# WHAT THE SOCKET SAYS
# =============================================================================

func hear(message: Dictionary) -> void:
	"""A PARTY VOICE message from the presence socket."""
	if state != "on":
		return
	match str(message.get("t", "")):
		"vs":
			if message.get("in") is Array:
				for entry in message["in"]:
					if entry is Dictionary:
						_meet(entry, true)
			if message.get("join") is Dictionary:
				_meet(message["join"], false)
			if message.has("left"):
				var id: int = int(message.get("left", 0))
				members.erase(id)
				bridge.hangup(id)
				changed.emit()
			if message.has("off"):
				stop("Voice is off: you are not in a party any more.")
		"vc":
			var from: int = int(message.get("from", 0))
			if from > 0 and members.has(from) and message.get("d") is Dictionary:
				bridge.hear(from, JSON.stringify(message["d"]))


func _meet(entry: Dictionary, call_them: bool) -> void:
	"""Somebody in voice: told we joined ("in", and we call them), or that they
	did ("join", and they call us). EVERY MEETING IS A NEW CALL: somebody
	already known is somebody whose link dropped and came back, and whatever
	call there was is hung up first - the one who said it joined calls again,
	the other waits for it."""
	var id: int = int(entry.get("id", 0))
	var who: String = str(entry.get("name", ""))
	if id <= 0 or id == Presence.my_id():
		return
	if members.has(id):
		bridge.hangup(id)
	members[id] = who
	bridge.set_volume(id, heard_volume(who))
	if call_them:
		bridge.dial(id)
	changed.emit()


# =============================================================================
# EVERY TENTH OF A SECOND
# =============================================================================

func _process(delta: float) -> void:
	if state == "off" or bridge == null:
		return
	_poll += delta
	if _poll < POLL_SECONDS:
		return
	var step: float = _poll
	_poll = 0.0
	if state == "starting":
		_waited += step
		var got: String = bridge.status()
		if got == "live":
			state = "on"
			note = ""
			_link_was_open = false
			_apply_mic()
			changed.emit()
		elif got == "denied":
			stop("Your browser did not allow the microphone. Allow it for this site, then switch voice on again.")
			return
		elif got == "error" or got == "off" or _waited >= MIC_WAIT_SECONDS:
			var why: String = bridge.reason()
			stop("Voice could not start%s." % (": " + why if why != "" else ""))
			return
	if state != "on":
		return
	if not Party.in_one():
		stop("Voice is off: you are not in a party any more.")
		return
	# SAID AGAIN after the link comes back (the server forgot), and at first.
	var up: bool = bool(link_open.call())
	if up and not _link_was_open:
		Presence.send_voice({"t": "vs", "on": true})
	_link_was_open = up
	var out: Variant = JSON.parse_string(bridge.take_outbox())
	if out is Array:
		for pair in out:
			if pair is Array and pair.size() == 2 and pair[1] is Dictionary:
				Presence.send_voice({"t": "vc", "to": int(pair[0]), "d": pair[1]})
	_read_levels(bridge.levels())


func _read_levels(raw: String) -> void:
	var read: Variant = JSON.parse_string(raw)
	if not (read is Dictionary):
		return
	my_level = float(read.get("me", 0.0)) if mic_open() else 0.0
	mic_level = float(read.get("mic", read.get("me", 0.0)))
	gate_open = bool(read.get("gate", true))
	var before: Dictionary = calls.duplicate()
	levels.clear()
	calls.clear()
	var peers: Variant = read.get("peers", {})
	if peers is Dictionary:
		for key in peers:
			var who: String = str(members.get(int(str(key)), ""))
			var row: Variant = peers[key]
			if who == "" or not (row is Dictionary):
				continue
			levels[who.to_lower()] = float(row.get("lv", 0.0))
			calls[who.to_lower()] = str(row.get("st", ""))
	if calls != before:
		changed.emit()


func speaking(username: String) -> bool:
	"""Whether `username` is talking now - this player too."""
	if username == "":
		return false
	if Api.username != "" and username.to_lower() == Api.username.to_lower():
		return mic_open() and my_level > SPEAKING_LEVEL
	return float(levels.get(username.to_lower(), 0.0)) > SPEAKING_LEVEL


func in_voice(username: String) -> bool:
	"""Whether `username` is in the party's voice with this player."""
	for id in members:
		if str(members[id]).to_lower() == username.to_lower():
			return true
	return false


func call_state(username: String) -> String:
	return str(calls.get(username.to_lower(), ""))


# =============================================================================
# KEPT ON THIS MACHINE
# =============================================================================

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	mode = MODE_PUSH if str(config.get_value(SECTION, "mode", MODE_OPEN)) == MODE_PUSH else MODE_OPEN
	muted = bool(config.get_value(SECTION, "muted", false))
	var stored: Variant = config.get_value(SECTION, "volumes", {})
	volumes = {}
	if stored is Dictionary:
		for key in stored:
			var v: Variant = stored[key]
			if (v is float or v is int) and str(key).length() <= 64:
				volumes[str(key).to_lower()] = clampf(float(v), 0.0, MOST_VOLUME)
	voices_volume = _number(config.get_value(SECTION, "voices_volume", 1.0), 1.0, MOST_VOLUME)
	mic_volume = _number(config.get_value(SECTION, "mic_volume", 1.0), 1.0, MOST_VOLUME)
	sensitivity = _number(config.get_value(SECTION, "sensitivity", 0.0), 0.0, 1.0)
	echo_cancel = _switched_on(config.get_value(SECTION, "echo_cancel", true))
	noise_suppress = _switched_on(config.get_value(SECTION, "noise_suppress", true))


static func _switched_on(value: Variant) -> bool:
	"""A stored switch: off only when it says false - the browser's cleaning
	stays on for anything else."""
	return not (value is bool and value == false)


static func _number(value: Variant, fallback: float, most: float) -> float:
	"""A stored number, kept in 0..most - or `fallback` for anything else."""
	if not (value is float or value is int):
		return fallback
	return clampf(float(value), 0.0, most)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "mode", mode)
	config.set_value(SECTION, "muted", muted)
	config.set_value(SECTION, "volumes", volumes)
	config.set_value(SECTION, "voices_volume", voices_volume)
	config.set_value(SECTION, "mic_volume", mic_volume)
	config.set_value(SECTION, "sensitivity", sensitivity)
	config.set_value(SECTION, "echo_cancel", echo_cancel)
	config.set_value(SECTION, "noise_suppress", noise_suppress)
	config.save(path)
