# controlspanel.gd — every key in the game on one card, and the welcome a new
# player sees once.
#
# WHY IT EXISTS. The day 1 playtest made a brand-new character and found
# nothing on screen saying that Space swings, Shift sprints, E opens the bank,
# or where the Field is. The keys lived in project.godot and in the heads of the
# people who wrote them.
#
# THE KEYS ARE READ FROM THE INPUT MAP, never typed in here. A key changed in
# project.godot changes on this card too, so the card cannot drift from the
# game - the same reason the hotbar prints OS.get_keycode_string() of its keys
# rather than a hand-written digit.
#
# THREE MODES, ONE CARD:
#   open_controls()  H, or Menu > Controls. The key list.
#   open_welcome()   Once per computer, the first time a character stands in
#                    town: where to go, the same key list, and "Got it".
#                    characterhud.gd's offer_welcome() asks has_seen_welcome().
#   open_keys()      "Change keys" on this card, or on Options (0.8.0): every
#                    rebindable action with its two keys as buttons. Click
#                    one, press the new key; Esc cancels, a right-click
#                    clears. The keys are Settings.keys (keybinds.gd).
extends Control
class_name ControlsPanel


signal closed()


const CONTROLS_TITLE := "CONTROLS"
const WELCOME_TITLE := "WELCOME TO ELUSION"
const KEYS_TITLE := "CHANGE KEYS"

const KEYS_HINT := "Click a key, then press the new one. Esc cancels; right-click a key to clear it."
const WAITING_TEXT := "Press a key..."
const NO_KEY_TEXT := "-"
const UNBOUND_COLOR := Color(0.95, 0.55, 0.45)
const WHAT_COLOR := Color(0.85, 0.82, 0.74)
const KEY_COLOR := Color(1.0, 0.86, 0.5)

# THE WAY OUT OF TOWN, walked on day 1 rather than read off the map: south from
# where you appear, the first portal drops you in the town square by the shop,
# and the road north out of the square ends at the Field's portal.
const WELCOME_LINES := [
	"Walk south down the road. The portal there takes you to the town square,",
	"where the shop is. From the square, walk north up the road to the portal",
	"to the Field, where the fighting is.",
	"Every enemy shows its health above its head. Start with the small ones.",
]

const WELCOME_FOOTER := "Press %s any time to see these keys again."

# [what it does, how]. "How" is a word this card knows (move, hotbar), an
# action in the input map, or the words to show as they are.
const ROWS := [
	["Move", "move"],
	["Sprint", "sprint"],
	["Attack, aiming with the mouse", "attack"],
	["Use the shop, bank, fire or fishing spot", "interact"],
	["Use the item on a hotbar key", "hotbar"],
	["Put an item on a hotbar key", "Drag it from your bag"],
	["Use or equip an item", "Right-click it in your bag"],
	["Bag", "inventory_toggle"],
	["Gear", "equipment_toggle"],
	["Stats", "character_toggle"],
	["Map", "minimap_toggle"],
	["Close a window, or open Options", "Esc"],
	["This card", "help_toggle"],
]

# WHERE "SEEN" IS KEPT. Its own file, not options.cfg: every key in Settings'
# DEFAULTS has a control in the Options window, and a flag nobody should set by
# hand is not a setting. A static var so the suite can point it at a scratch
# file and never mark the welcome seen on the machine it runs on.
static var seen_path: String = "user://seen.cfg"


@onready var header_label: Label = get_node_or_null("%headerlabel")
@onready var close_button: Button = get_node_or_null("%closebutton")
@onready var welcome_box: Control = get_node_or_null("%welcomebox")
@onready var welcome_text: Label = get_node_or_null("%welcometext")
@onready var key_grid: GridContainer = get_node_or_null("%keygrid")
@onready var footer_label: Label = get_node_or_null("%footerlabel")
@onready var got_it_button: Button = get_node_or_null("%gotitbutton")
@onready var key_scroll: ScrollContainer = get_node_or_null("%keyscroll")
@onready var key_note: Label = get_node_or_null("%keynote")
@onready var keys_row: Control = get_node_or_null("%keysrow")
@onready var change_keys_button: Button = get_node_or_null("%changekeysbutton")
@onready var reset_keys_button: Button = get_node_or_null("%resetkeysbutton")

var _window: PanelWindow

# The keys this card changes: Settings' own, unless a test hands it others.
var keys: Keybinds = null

var _editing: bool = false
# [action, slot] while a key button is waiting for a press, else empty.
var _capture: Array = []


func _ready() -> void:
	# It opens in the middle of the screen every time, like the cooking window
	# (see _show()); the key is what lets it be dragged while it is open.
	_window = PanelWindow.attach(self, "controls")
	if close_button != null:
		close_button.pressed.connect(close)
	if got_it_button != null:
		got_it_button.pressed.connect(close)
	if welcome_text != null:
		welcome_text.text = "\n".join(WELCOME_LINES)
	if change_keys_button != null:
		change_keys_button.pressed.connect(_on_change_keys_pressed)
	if reset_keys_button != null:
		reset_keys_button.pressed.connect(_on_reset_keys_pressed)
	# THE CARD IS TALL WITH TWENTY-TWO KEYS ON IT, taller than the screen at
	# the larger text sizes; past that it scrolls.
	_window.keep_scroll_fitted(key_scroll)
	if keys == null:
		var settings: Node = get_node_or_null("/root/Settings")
		if settings != null and settings.get("keys") is Keybinds:
			keys = settings.get("keys")
	if keys != null and not keys.changed.is_connected(_on_keys_changed):
		keys.changed.connect(_on_keys_changed)
	build_rows()


# =============================================================================
# OPENING AND CLOSING
# =============================================================================

func open_controls() -> void:
	_editing = false
	_show(false)


func open_keys() -> void:
	"""Every rebindable key, as buttons to change it."""
	_editing = true
	_show(false)
	_say(KEYS_HINT)


func is_editing() -> bool:
	return _editing


func open_welcome() -> void:
	# SEEN WHEN SHOWN, not when dismissed: a crash or a quit with the card up
	# should not bring it back at every launch.
	mark_welcome_seen()
	_editing = false
	_show(true)


func close() -> void:
	_capture = []
	visible = false
	closed.emit()


func is_welcome() -> bool:
	return welcome_box != null and welcome_box.visible


func _show(welcome: bool) -> void:
	_capture = []
	if header_label != null:
		header_label.text = WELCOME_TITLE if welcome else (KEYS_TITLE if _editing else CONTROLS_TITLE)
	if welcome_box != null:
		welcome_box.visible = welcome
	if footer_label != null:
		footer_label.visible = welcome
		footer_label.text = WELCOME_FOOTER % key_text("help_toggle")
	if got_it_button != null:
		got_it_button.visible = welcome
	# THE WELCOME IS NOT WHERE KEYS ARE CHANGED: it is a new player's first
	# minute, and "Change keys" under directions to the Field is a distraction.
	if keys_row != null:
		keys_row.visible = not welcome and keys != null
	if change_keys_button != null:
		change_keys_button.text = "Done" if _editing else "Change keys"
	if reset_keys_button != null:
		reset_keys_button.visible = _editing
	if key_note != null:
		key_note.visible = _editing
	build_rows()
	visible = true
	# SIZED TO WHAT IS SHOWING, then centred: the welcome is taller than the
	# key list, and a plain Control does not size itself to its children.
	if _window != null:
		_window.refit_scrolls()
	_size_to_content()
	# AND AGAIN AT THE END OF THE FRAME: the key list's scroll lets go of its
	# scrollbar only when it lays itself out, and until then it counts the
	# bar's width in what it needs.
	_size_to_content.call_deferred()


func _size_to_content() -> void:
	if not visible:
		return
	size = PanelWindow.content_minimum(self)
	if is_inside_tree():
		position = ((get_viewport_rect().size - size) * 0.5).floor()


# =============================================================================
# THE ROWS
# =============================================================================

func build_rows() -> void:
	if key_grid == null:
		return
	for child in key_grid.get_children():
		key_grid.remove_child(child)
		child.queue_free()
	if _editing and keys != null:
		_build_key_buttons()
		return
	key_grid.columns = 2
	for row in ROWS:
		var what := Label.new()
		what.text = String(row[0])
		what.add_theme_color_override("font_color", WHAT_COLOR)
		var how := Label.new()
		how.text = key_text(String(row[1]))
		how.add_theme_color_override("font_color", KEY_COLOR)
		key_grid.add_child(what)
		key_grid.add_child(how)


func _build_key_buttons() -> void:
	key_grid.columns = 1 + Keybinds.SLOTS
	for action in Keybinds.all_actions():
		var what := Label.new()
		what.name = "label_%s" % action
		what.text = Keybinds.action_label(action)
		key_grid.add_child(what)
		for slot in Keybinds.SLOTS:
			var button := Button.new()
			button.name = "%s_%d" % [action, slot]
			button.focus_mode = Control.FOCUS_NONE
			button.custom_minimum_size = Vector2(108, 26)
			button.tooltip_text = "%s: %s key" % [Keybinds.action_label(action),
				"first" if slot == 0 else "second"]
			button.pressed.connect(start_capture.bind(action, slot))
			button.gui_input.connect(_on_key_button_input.bind(action, slot))
			key_grid.add_child(button)
	_paint_keys()


func _paint_keys() -> void:
	# IN PLACE, never by building the rows again: this runs from a button's
	# own press, and a button freed inside its own signal is a crash waiting.
	if key_grid == null or keys == null or not _editing:
		return
	for action in Keybinds.all_actions():
		var bound: Array = keys.keys_of(action)
		var what: Label = key_grid.get_node_or_null("label_%s" % action) as Label
		if what != null:
			# AN ACTION WITH NO KEY AT ALL is red, so a key taken for
			# something else does not quietly leave Walk up unreachable.
			what.add_theme_color_override("font_color",
				UNBOUND_COLOR if keys.first_key(action) == 0 else WHAT_COLOR)
		for slot in Keybinds.SLOTS:
			var button: Button = key_button(action, slot)
			if button == null:
				continue
			var code: int = int(bound[slot])
			var waiting: bool = _capture == [action, slot]
			button.text = WAITING_TEXT if waiting else (Keybinds.key_name(code) if code != 0 else NO_KEY_TEXT)
			button.add_theme_color_override("font_color", KEY_COLOR if code != 0 or waiting else WHAT_COLOR)


func key_button(action: String, slot: int) -> Button:
	"""The button for one key, in edit mode; null otherwise."""
	if key_grid == null:
		return null
	return key_grid.get_node_or_null("%s_%d" % [action, slot]) as Button


# =============================================================================
# CHANGING A KEY
# =============================================================================

func _on_change_keys_pressed() -> void:
	if _editing:
		open_controls()
	else:
		open_keys()


func _on_reset_keys_pressed() -> void:
	if keys == null:
		return
	_capture = []
	keys.reset_all()
	_say("Every key is back to how the game came.")


func _on_keys_changed() -> void:
	if not visible:
		return
	if _editing:
		_paint_keys()
	else:
		build_rows()


func start_capture(action: String, slot: int) -> void:
	"""The key button was pressed: the next key pressed goes there. Pressing
	the same button again lets it go."""
	if _capture == [action, slot]:
		_capture = []
		_say(KEYS_HINT)
	else:
		_capture = [action, slot]
		_say("Press the new key for %s. Esc cancels." % Keybinds.action_label(action))
	_paint_keys()


func is_capturing() -> bool:
	return not _capture.is_empty()


func _input(event: InputEvent) -> void:
	# _input, not _unhandled_input: the HUD's own key handling is unhandled,
	# and the press that is being bound must reach this card first and nothing
	# else - pressing I to put the Bag on I must not also open the bag.
	if _capture.is_empty() or not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	press_key(Keybinds.event_key(key))


func press_key(code: int) -> void:
	"""What happens to a key pressed while a button is waiting: Esc cancels,
	anything else is bound if it may be, and the line under the keys says what
	happened."""
	if _capture.is_empty() or keys == null:
		return
	var action: String = _capture[0]
	var slot: int = _capture[1]
	_capture = []
	if code == KEY_ESCAPE:
		_say("Nothing changed.")
		_paint_keys()
		return
	var result: Dictionary = keys.bind(action, slot, code)
	if not bool(result.get("ok", false)):
		_say(String(result.get("why", "That key cannot be used.")))
		_paint_keys()
		return
	var line: String = "%s is on %s now." % [Keybinds.action_label(action), Keybinds.key_name(code)]
	var took: String = String(result.get("took_from", ""))
	if took != "":
		var left: int = keys.first_key(took)
		line += " It was %s's, which %s." % [Keybinds.action_label(took),
			("still has %s" % Keybinds.key_name(left)) if left != 0 else "has no key now"]
	_say(line)
	_paint_keys()


func _on_key_button_input(event: InputEvent, action: String, slot: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_RIGHT or keys == null:
		return
	_capture = []
	keys.clear(action, slot)
	_say("%s has no %s key now." % [Keybinds.action_label(action), "first" if slot == 0 else "second"])
	_paint_keys()


func _say(line: String) -> void:
	if key_note != null:
		key_note.text = line


static func key_text(how: String) -> String:
	"""What to press, in words. `how` is "move", "hotbar", an input action, or
	text to show as it is."""
	match how:
		"move":
			return move_text()
		"hotbar":
			return hotbar_text()
		"attack":
			# The right button swings too; player.gd's right_click_attack_held()
			# is the second half of the attack poll, and it is not in the map.
			return "%s or right-click" % action_key("attack")
		"sprint":
			return "Hold %s" % action_key("sprint")
	if InputMap.has_action(how):
		return action_key(how)
	return how


static func action_key(action: String) -> String:
	"""The first key bound to `action`, as the keyboard prints it."""
	var names: Array[String] = action_keys(action)
	return names[0] if not names.is_empty() else "no key"


static func hotbar_text() -> String:
	"""The ten hotbar keys: "1 to 0" as shipped, or each one when changed."""
	var names: Array[String] = []
	var shipped: bool = true
	for i in Hotbar.SLOT_COUNT:
		var code: int = Hotbar.key_for_slot(i)
		if code != int(Hotbar.SLOT_KEYS[i]):
			shipped = false
		if code != 0:
			names.append(Keybinds.key_name(code))
	if shipped:
		return "%s to %s" % [names[0], names[-1]]
	return " ".join(names) if not names.is_empty() else "no keys"


static func action_keys(action: String) -> Array[String]:
	var out: Array[String] = []
	if not InputMap.has_action(action):
		return out
	for event in InputMap.action_get_events(action):
		var code: int = Keybinds.event_key(event)
		if code != 0:
			out.append(Keybinds.key_name(code))
	return out


static func move_text() -> String:
	"""The four movement letters in reading order, and the arrows when they are
	bound too. Both are in the map; the letters are what a new player looks for."""
	var letters: Array[String] = []
	var arrows: bool = false
	for action in ["move_up", "move_left", "move_down", "move_right"]:
		for key_name in action_keys(action):
			if key_name.length() == 1:
				letters.append(key_name)
				break
		for key_name in action_keys(action):
			if key_name in ["Up", "Down", "Left", "Right"]:
				arrows = true
	var text: String = " ".join(letters)
	return text + " or arrows" if arrows else text


# =============================================================================
# SEEN
# =============================================================================

static func has_seen_welcome() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(seen_path) != OK:
		return false
	return bool(cfg.get_value("seen", "welcome", false))


static func mark_welcome_seen() -> void:
	var cfg := ConfigFile.new()
	# READ THEN WRITE, so anything else kept in the file survives.
	cfg.load(seen_path)
	cfg.set_value("seen", "welcome", true)
	cfg.save(seen_path)
