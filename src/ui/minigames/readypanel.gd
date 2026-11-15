# readypanel.gd - THE READY PANEL FOR A WALK-IN MINIGAME (0.161.0). The owner,
# of the Mage's Stand's new start panel: "lets fix the other minigames with
# the same idea" - "we need healers run tanks and warriors and arena" - and of
# the Endless, the Forge and the Descent, which start in the world (through
# the door, at the anvil), he chose the full Ready panel: "the door or anvil
# opens only once all are ready".
#
# A CanvasLayer the run makes while it waits (endlessrun.gd, forgerun.gd,
# descentrun.gd): the title, a line under it, HOW TO PLAY and - with the party
# here - its seats, "N of M ready" and what it waits for (startpanel.gd, the
# Stand's look), and the button: Start (Space) alone, Ready / Not ready with
# the party. Alone, Start lets the run begin (go_pressed). With the party,
# each says Ready in its own line to the others (the run's "me", `said_ready`)
# and the run opens when all_ready(): everyone here has said so. A game from
# before 0.161.0 says no Ready at all - ready_of() answers 1 for it, so it
# never holds the party up.
#
# No class_name: preloaded by the runs.
extends CanvasLayer

const StartPanel := preload("res://src/ui/minigames/startpanel.gd")

signal go_pressed

const LAYER := 5
const READY := 1
const SEAT_SLOTS := [0, 1, 2, 3]
const PANEL_BACK := Color(0.1, 0.08, 0.07, 0.95)
const PANEL_EDGE := Color(0.85, 0.65, 0.25)

var title: String = ""
var subtitle: String = ""
var keys: Array = []
var lines: Array = []
# Line number -> the words on a phone.
var touch_lines: Dictionary = {}
# The run's party node (anything with active()) and the presence link (its
# remotes() are who is here; the party's own link when none is given) - the
# suite's stand-ins in the suite.
var party: Node = null
var link: Node = null
# id -> 1 ready, 0 not, -1 not heard yet (the run's party, ready_of()).
var ready_of: Callable = Callable()
# This player's Ready, said to the others in the run's "me".
var said_ready: bool = false
# This player's name on the seats (the suite's door).
var own_name: Callable = Callable(self, "_own_name")

var panel: PanelContainer = null
var start_button: Button = null
var party_box: VBoxContainer = null
var party_count: Label = null
var party_line: Label = null
var _seat_cards: Array = []
var _how_lines: Array = []
var _seats_said: String = ""
var _worded: int = -1
var _party_shown: bool = false


func _ready() -> void:
	layer = LAYER
	_build()


func _build() -> void:
	panel = PanelContainer.new()
	panel.name = "ready"
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BACK
	style.border_color = PANEL_EDGE
	style.set_border_width_all(3)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	column.add_child(StartPanel.words(title, 30, StartPanel.GOLD))
	if subtitle != "":
		column.add_child(StartPanel.words(subtitle, 15, StartPanel.HINT))
	column.add_child(StartPanel.rule())
	column.add_child(StartPanel.head("HOW TO PLAY"))
	column.add_child(StartPanel.how_grid(keys, lines, _how_lines))
	var part: Dictionary = StartPanel.party_part(SEAT_SLOTS)
	party_box = part["box"]
	party_count = part["count"]
	_seat_cards = part["cards"]
	party_line = part["line"]
	(part["side"] as Node).queue_free()
	column.add_child(party_box)
	var room := Control.new()
	room.custom_minimum_size = Vector2(0, 4)
	column.add_child(room)
	start_button = StartPanel.go_button("Start  (Space)", press)
	column.add_child(start_button)
	_centre()


func _centre() -> void:
	panel.reset_size()
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


func _own_name() -> String:
	return str(Api.username) if str(Api.username) != "" else "You"


# =============================================================================
# WHO IS HERE, AND READY
# =============================================================================

func here() -> bool:
	"""The party is here to share the run with."""
	return party != null and is_instance_valid(party) and bool(party.call("active"))


func _link() -> Node:
	"""Who is here: the link given, or the party's own."""
	if link != null and is_instance_valid(link):
		return link
	var theirs: Variant = party.get("link") if party != null and is_instance_valid(party) and "link" in party else null
	return theirs as Node if is_instance_valid(theirs) else null


func _ids() -> Array:
	var here_now: Node = _link()
	var ids: Array = (here_now.call("remotes") as Dictionary).keys() if here_now != null and here_now.has_method("remotes") else []
	ids.sort()
	return ids


func _name_of(id: int) -> String:
	var here_now: Node = _link()
	var body: Variant = (here_now.call("remotes") as Dictionary).get(id) if here_now != null and here_now.has_method("remotes") else null
	if is_instance_valid(body):
		for field in ["display_name", "username", "player_name"]:
			if field in body and str(body.get(field)) != "":
				return str(body.get(field))
	return "a player"


func _said_of(id: int) -> int:
	return int(ready_of.call(id)) if ready_of.is_valid() else -1


func rows() -> Array:
	"""Everyone here, this player first: {name, flags, heard, me}."""
	var out: Array = [{"name": str(own_name.call()), "flags": READY if said_ready else 0, "heard": true, "me": true}]
	if not here():
		return out
	for id in _ids():
		var said: int = _said_of(int(id))
		out.append({"name": _name_of(int(id)), "flags": READY if said == 1 else 0, "heard": said >= 0, "me": false})
	return out


func all_ready() -> bool:
	"""With the party here: this player and everyone else have said Ready."""
	if not here() or not said_ready:
		return false
	for id in _ids():
		if _said_of(int(id)) != 1:
			return false
	return true


func press() -> void:
	"""Start, or Ready / Not ready."""
	if not visible:
		return
	if here():
		said_ready = not said_ready
		paint()
		return
	said_ready = true
	go_pressed.emit()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if visible and key != null and key.pressed and not key.echo and key.keycode == KEY_SPACE:
		press()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible:
		paint()


func paint() -> void:
	var touch: int = 1 if TouchControls.active else 0
	if touch != _worded:
		_worded = touch
		for k in _how_lines.size():
			(_how_lines[k] as Label).text = str(touch_lines[k]) if touch == 1 and touch_lines.has(k) else str(lines[k])
	var space: String = "" if touch == 1 else "  (Space)"
	var with_party: bool = here()
	if with_party != _party_shown:
		_party_shown = with_party
		party_box.visible = with_party
		_centre()
	if not with_party:
		start_button.text = "Start" + space
		StartPanel.paint_go(start_button, true)
		return
	var everyone: Array = rows()
	var said: Array = []
	for k in _seat_cards.size():
		said.append(StartPanel.seat_said(everyone[k] if k < everyone.size() else {}, true, READY))
	party_count.text = "%d of %d ready" % [StartPanel.ready_count(said), everyone.size()]
	party_line.text = StartPanel.waiting_text(everyone, said_ready, READY, -1.0)
	var signature: String = str(said)
	if signature != _seats_said:
		_seats_said = signature
		StartPanel.paint_seats(_seat_cards, said)
	start_button.text = ("Not ready" if said_ready else "Ready") + space
	StartPanel.paint_go(start_button, not said_ready)
