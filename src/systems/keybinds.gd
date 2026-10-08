# keybinds.gd - the keys a player chose, kept in user://keys.cfg and put into
# the InputMap at launch (0.8.0).
#
# The owner, 7 Oct, picking from a list of improvements: "Rebindable keys. The
# Controls page shows the keys, but Options has no way to change them."
#
# ONE OBJECT, OWNED BY Settings (Settings.keys), set up in its _ready() before
# any scene reads a key. Not a setting in DEFAULTS: a binding is a list of keys
# per action, and every DEFAULTS key is one control in the Options window. It
# is changed on the Controls card (controlspanel.gd, "Change keys").
#
# WHAT CAN BE REBOUND is ACTIONS below: moving, sprinting, attacking, using,
# the five window keys, and the ten hotbar keys - each with two keys, a first
# and a second, the way WASD and the arrows both walk. WHAT CANNOT: Escape
# (closes a window, cancels a key being set - a player who bound it away could
# never get out of anything), the backquote (the GM panel's), Enter (sends
# chat). Those are RESERVED, and a press of one while setting a key says why.
#
# THE DEFAULTS ARE NOT TYPED IN HERE. They are project.godot's own input map,
# read at launch before anything is changed, and Hotbar.SLOT_KEYS for the
# hotbar - so a default changed in the editor changes here too. The file holds
# only actions that differ from them.
#
# A KEY ON TWO ACTIONS is moved, not doubled: binding E to the Bag takes it off
# Use, says so, and leaves Use with what else it had. Two actions on one key is
# a press that does two things, which is the bug the debug keys once were.
#
# PHYSICAL KEYS, like project.godot's own bindings: the key in the W position
# walks up on any keyboard layout.
extends RefCounted
class_name Keybinds


signal changed()


# [action, what the Controls card calls it]. Card order.
const ACTIONS := [
	["move_up", "Walk up"],
	["move_left", "Walk left"],
	["move_down", "Walk down"],
	["move_right", "Walk right"],
	["sprint", "Sprint (hold)"],
	["attack", "Attack"],
	["interact", "Use the shop, bank, fire or fishing spot"],
	["inventory_toggle", "Bag"],
	["equipment_toggle", "Gear"],
	["character_toggle", "Stats"],
	["minimap_toggle", "Map"],
	["kills_toggle", "Kills"],
	["help_toggle", "Controls (this card)"],
]

# ACTIONS MADE HERE rather than in project.godot, with the key each starts on:
# the ten hotbar keys (below) and the Kills window (0.9.0). project.godot is
# rewritten by the editor, and an action added to it from outside is lost the
# next time the editor saves its own copy.
const MADE_HERE := {
	"kills_toggle": KEY_K,
}

# Two keys an action: a first and a second.
const SLOTS := 2

const HOTBAR_ACTION := "hotbar_%d"

# Keys nothing may be bound to, and what they already do.
const RESERVED := {
	KEY_ESCAPE: "closing windows",
	KEY_QUOTELEFT: "the GM panel",
	KEY_ENTER: "chat",
	KEY_KP_ENTER: "chat",
}

const SECTION := "keys"

# A static var so the suite can point it at a scratch file and never rebind
# the keys of the machine it runs on - ControlsPanel.seen_path's reason.
static var path: String = "user://keys.cfg"

# action -> [first, second], 0 for none. What the game shipped with.
var _defaults: Dictionary = {}
# action -> [first, second]. What is bound now.
var _keys: Dictionary = {}
# action -> the project's own events, put back exactly for an action at its
# defaults (the Map's M is a printed-letter binding, not a physical one).
var _project_events: Dictionary = {}


# =============================================================================
# THE ACTIONS
# =============================================================================

static func hotbar_action(index: int) -> String:
	"""The action for hotbar key `index` (0 is the first key, 9 the tenth)."""
	return HOTBAR_ACTION % (index + 1)


static func all_actions() -> Array[String]:
	var out: Array[String] = []
	for row in ACTIONS:
		out.append(String(row[0]))
	for i in Hotbar.SLOT_COUNT:
		out.append(hotbar_action(i))
	return out


static func action_label(action: String) -> String:
	for row in ACTIONS:
		if row[0] == action:
			return String(row[1])
	if action.begins_with("hotbar_"):
		return "Hotbar key %s" % action.trim_prefix("hotbar_")
	return action


static func key_name(keycode: int) -> String:
	return OS.get_keycode_string(keycode as Key) if keycode != 0 else ""


static func event_key(event: InputEvent) -> int:
	"""The key an event is: its physical key, or the printed one when that is
	all it says (project.godot's Map binding; a test's synthetic press)."""
	var key := event as InputEventKey
	if key == null:
		return 0
	return int(key.physical_keycode) if key.physical_keycode != KEY_NONE else int(key.keycode)


static func reserved_for(keycode: int) -> String:
	"""What a reserved key already does, or "" for a key that may be bound."""
	return String(RESERVED.get(keycode, ""))


# =============================================================================
# SETTING UP
# =============================================================================

func setup() -> void:
	"""Once, at launch: the hotbar's actions, the defaults as shipped, then the
	file."""
	_add_hotbar_actions()
	_read_defaults()
	load_keys()


func _add_hotbar_actions() -> void:
	# THE HOTBAR WAS TEN HARD-CODED KEYS (Hotbar.SLOT_KEYS, read straight off
	# the keycode). They are actions now, made here rather than in
	# project.godot so the ten defaults stay in the one list the bar's numbers
	# were already drawn from.
	for i in Hotbar.SLOT_COUNT:
		var action: String = hotbar_action(i)
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if InputMap.action_get_events(action).is_empty():
			InputMap.action_add_event(action, key_press(int(Hotbar.SLOT_KEYS[i])))
	for action in MADE_HERE:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if InputMap.action_get_events(action).is_empty():
			InputMap.action_add_event(action, key_press(int(MADE_HERE[action])))


func _read_defaults() -> void:
	_defaults.clear()
	_project_events.clear()
	for action in all_actions():
		var events: Array = []
		if action.begins_with("hotbar_") or MADE_HERE.has(action):
			events = InputMap.action_get_events(action)
		elif ProjectSettings.has_setting("input/" + action):
			events = (ProjectSettings.get_setting("input/" + action) as Dictionary).get("events", [])
		else:
			events = InputMap.action_get_events(action)
		_project_events[action] = events.duplicate()
		_defaults[action] = default_order(events)


static func default_order(events: Array) -> Array:
	"""[first, second] from a list of events: a letter or digit first, so
	W comes before Up - the card reads "W A S D or arrows"."""
	var codes: Array = []
	for event in events:
		var code: int = event_key(event)
		if code != 0 and not codes.has(code):
			codes.append(code)
	var short: Array = codes.filter(func(c): return key_name(c).length() == 1)
	var long: Array = codes.filter(func(c): return key_name(c).length() != 1)
	var ordered: Array = short + long
	while ordered.size() < SLOTS:
		ordered.append(0)
	return ordered.slice(0, SLOTS)


# =============================================================================
# READING
# =============================================================================

func keys_of(action: String) -> Array:
	"""[first, second] for `action`, 0 where there is none."""
	return (_keys.get(action, _defaults.get(action, [0, 0])) as Array).duplicate()


func defaults_of(action: String) -> Array:
	return (_defaults.get(action, [0, 0]) as Array).duplicate()


func first_key(action: String) -> int:
	for code in keys_of(action):
		if int(code) != 0:
			return int(code)
	return 0


func action_for_key(keycode: int) -> String:
	"""Which rebindable action `keycode` is on now, or ""."""
	if keycode == 0:
		return ""
	for action in all_actions():
		if keys_of(action).has(keycode):
			return action
	return ""


func is_default(action: String = "") -> bool:
	if action != "":
		return keys_of(action) == defaults_of(action)
	for each in all_actions():
		if not is_default(each):
			return false
	return true


func unbound_actions() -> Array[String]:
	var out: Array[String] = []
	for action in all_actions():
		if first_key(action) == 0:
			out.append(action)
	return out


# =============================================================================
# CHANGING
# =============================================================================

func bind(action: String, slot: int, keycode: int) -> Dictionary:
	"""Puts `keycode` on `action` as its first (0) or second (1) key. Answers
	{ok, why, took_from}: why is a sentence when it is refused, took_from the
	action the key was moved off, or ""."""
	if not _defaults.has(action):
		return {"ok": false, "why": "There is no such action.", "took_from": ""}
	if slot < 0 or slot >= SLOTS:
		return {"ok": false, "why": "There is no such key slot.", "took_from": ""}
	if keycode == 0:
		return {"ok": false, "why": "That is not a key.", "took_from": ""}
	var reserved: String = reserved_for(keycode)
	if reserved != "":
		return {"ok": false, "why": "%s is kept for %s." % [key_name(keycode), reserved],
			"took_from": ""}

	var took_from: String = ""
	var holder: String = action_for_key(keycode)
	if holder != "" and holder != action:
		var theirs: Array = keys_of(holder)
		theirs[theirs.find(keycode)] = 0
		_keys[holder] = _packed(theirs)
		took_from = holder

	var mine: Array = keys_of(action)
	# THE SAME KEY IN THE OTHER SLOT of this action moves rather than doubles.
	var other: int = mine.find(keycode)
	if other >= 0 and other != slot:
		mine[other] = mine[slot]
	mine[slot] = keycode
	_keys[action] = mine
	_after_change()
	return {"ok": true, "why": "", "took_from": took_from}


func clear(action: String, slot: int) -> void:
	if not _defaults.has(action) or slot < 0 or slot >= SLOTS:
		return
	var mine: Array = keys_of(action)
	mine[slot] = 0
	_keys[action] = _packed(mine)
	_after_change()


func reset_all() -> void:
	_keys.clear()
	_after_change()


static func _packed(pair: Array) -> Array:
	# A second key with no first moves up, so "first" is never empty while
	# something is bound.
	if int(pair[0]) == 0 and int(pair[1]) != 0:
		return [pair[1], 0]
	return pair


func _after_change() -> void:
	# The defaults are not stored: the file says only what is different.
	for action in _keys.keys():
		if _keys[action] == _defaults.get(action):
			_keys.erase(action)
	apply()
	save_keys()
	changed.emit()


# =============================================================================
# THE INPUT MAP
# =============================================================================

func apply() -> void:
	for action in all_actions():
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		if not _keys.has(action):
			# AT ITS DEFAULTS: the project's own events, exactly as shipped.
			for event in _project_events.get(action, []):
				InputMap.action_add_event(action, event)
			continue
		for code in _keys[action]:
			if int(code) != 0:
				InputMap.action_add_event(action, key_press(int(code)))


static func key_press(code: int) -> InputEventKey:
	"""A binding for the key in `code`'s place on any keyboard, from any
	keyboard - project.godot's own shape for a key."""
	var press := InputEventKey.new()
	press.physical_keycode = code as Key
	press.device = -1
	return press


# =============================================================================
# THE FILE
# =============================================================================

func load_keys() -> void:
	_keys.clear()
	var config := ConfigFile.new()
	var err: int = config.load(path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("Keybinds: could not read %s (error %d) - using the default keys." % [path, err])
	if err == OK:
		for action in all_actions():
			if not config.has_section_key(SECTION, action):
				continue
			var stored: Variant = config.get_value(SECTION, action)
			var pair: Array = _clean_pair(stored)
			if not pair.is_empty():
				_keys[action] = pair
		_drop_doubles()
	apply()


static func _clean_pair(stored: Variant) -> Array:
	"""A stored binding as [first, second], or [] for anything a hand-edit or an
	older build could have left there: not a list, not whole numbers, a
	reserved key."""
	if not (stored is Array):
		return []
	var out: Array = []
	for value in stored:
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			return []
		var code: int = int(value)
		if code < 0 or reserved_for(code) != "":
			code = 0
		out.append(code)
	while out.size() < SLOTS:
		out.append(0)
	return _packed(out.slice(0, SLOTS))


func _drop_doubles() -> void:
	# A FILE WITH ONE KEY ON TWO ACTIONS (edited by hand) keeps it where the
	# file put it - the player's choice over a default - then on the first in
	# card order, and takes it off the rest.
	var seen: Dictionary = {}
	var order: Array[String] = []
	for action in all_actions():
		if _keys.has(action):
			order.append(action)
	for action in all_actions():
		if not _keys.has(action):
			order.append(action)
	for action in order:
		var mine: Array = keys_of(action)
		var changed_here: bool = false
		for i in mine.size():
			var code: int = int(mine[i])
			if code == 0:
				continue
			if seen.has(code):
				mine[i] = 0
				changed_here = true
			else:
				seen[code] = action
		if changed_here:
			_keys[action] = _packed(mine)


func save_keys() -> void:
	var config := ConfigFile.new()
	for action in _keys:
		config.set_value(SECTION, action, _keys[action])
	var err: int = config.save(path)
	if err != OK:
		push_warning("Keybinds: could not write %s (error %d)." % [path, err])
