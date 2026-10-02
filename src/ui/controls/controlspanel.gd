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
# TWO MODES, ONE CARD:
#   open_controls()  H, or Menu > Controls. The key list.
#   open_welcome()   Once per computer, the first time a character stands in
#                    town: where to go, the same key list, and "Got it".
#                    characterhud.gd's offer_welcome() asks has_seen_welcome().
extends Control
class_name ControlsPanel


signal closed()


const CONTROLS_TITLE := "CONTROLS"
const WELCOME_TITLE := "WELCOME TO ELUSION"

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

var _window: PanelWindow


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
	build_rows()


# =============================================================================
# OPENING AND CLOSING
# =============================================================================

func open_controls() -> void:
	_show(false)


func open_welcome() -> void:
	# SEEN WHEN SHOWN, not when dismissed: a crash or a quit with the card up
	# should not bring it back at every launch.
	mark_welcome_seen()
	_show(true)


func close() -> void:
	visible = false
	closed.emit()


func is_welcome() -> bool:
	return welcome_box != null and welcome_box.visible


func _show(welcome: bool) -> void:
	if header_label != null:
		header_label.text = WELCOME_TITLE if welcome else CONTROLS_TITLE
	if welcome_box != null:
		welcome_box.visible = welcome
	if footer_label != null:
		footer_label.visible = welcome
		footer_label.text = WELCOME_FOOTER % key_text("help_toggle")
	if got_it_button != null:
		got_it_button.visible = welcome
	build_rows()
	visible = true
	# SIZED TO WHAT IS SHOWING, then centred: the welcome is taller than the
	# key list, and a plain Control does not size itself to its children.
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
	for row in ROWS:
		var what := Label.new()
		what.text = String(row[0])
		what.add_theme_color_override("font_color", Color(0.85, 0.82, 0.74))
		var how := Label.new()
		how.text = key_text(String(row[1]))
		how.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
		key_grid.add_child(what)
		key_grid.add_child(how)


static func key_text(how: String) -> String:
	"""What to press, in words. `how` is "move", "hotbar", an input action, or
	text to show as it is."""
	match how:
		"move":
			return move_text()
		"hotbar":
			return "%s to %s" % [OS.get_keycode_string(Hotbar.SLOT_KEYS[0] as Key),
				OS.get_keycode_string(Hotbar.SLOT_KEYS[-1] as Key)]
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
	var keys: Array[String] = action_keys(action)
	return keys[0] if not keys.is_empty() else "?"


static func action_keys(action: String) -> Array[String]:
	var out: Array[String] = []
	if not InputMap.has_action(action):
		return out
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key == null:
			continue
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if code != KEY_NONE:
			out.append(OS.get_keycode_string(code))
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
