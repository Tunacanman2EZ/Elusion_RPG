# nettestselect.gd — Net-Test branch, screen 2 of 3.
#
# Pulls the account's character slots from GET /api/save and renders four
# buttons. Occupied slots show class, name and level; empty ones say so.
#
# The badge in the corner reads LIVE or LOCAL. That is the entire point of
# this branch: you watch each screen flip from LOCAL to LIVE as the matching
# Flask route lands, without changing a line of the screen's own code.
extends Control

const SLOT_COUNT: int = 4


var _net: NetClient
var _rows: Array[Button] = []
var _badge: Label
var _status: Label
var _refresh_button: Button

var _slots_by_index: Dictionary = {}


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_net = NetClient.new()
	_build_ui()
	await _load()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.custom_minimum_size = Vector2(420, 0)
	root.position = Vector2(-210, -180)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	var title := Label.new()
	title.text = "CHARACTERS"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_badge = Label.new()
	_badge.add_theme_font_size_override("font_size", 12)
	header.add_child(_badge)

	var who := Label.new()
	who.text = "signed in as %s" % Api.username
	who.add_theme_font_size_override("font_size", 11)
	who.modulate = Color(1, 1, 1, 0.5)
	root.add_child(who)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	root.add_child(gap)

	for i in SLOT_COUNT:
		var b := Button.new()
		b.custom_minimum_size = Vector2(420, 44)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_slot_pressed.bind(i))
		root.add_child(b)
		_rows.append(b)

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 12)
	root.add_child(gap2)

	var buttons := HBoxContainer.new()
	root.add_child(buttons)

	_refresh_button = Button.new()
	_refresh_button.text = "Refresh"
	_refresh_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refresh_button.pressed.connect(func(): await _load())
	buttons.add_child(_refresh_button)

	var logout := Button.new()
	logout.text = "Log out"
	logout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	logout.pressed.connect(_on_logout)
	buttons.add_child(logout)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(420, 34)
	root.add_child(_status)


# =============================================================================
# LOAD
# =============================================================================

func _load() -> void:
	_refresh_button.disabled = true
	_status.text = "Loading /api/save ..."

	var res: Dictionary = await _net.fetch_save()

	_refresh_button.disabled = false

	if not res.ok:
		_set_badge(false)
		_status.text = res.error
		for b in _rows:
			b.text = "  — unavailable —"
			b.disabled = true
		return

	_set_badge(res.live)
	_status.text = "" if res.live else "Showing local placeholder: %s" % res.error

	_slots_by_index.clear()
	for row in res.data.get("slots", []):
		var index: int = int(row.get("slot", -1))
		if index >= 0 and index < SLOT_COUNT:
			_slots_by_index[index] = row

	_render_rows()


func _render_rows() -> void:
	for i in SLOT_COUNT:
		var b: Button = _rows[i]
		if _slots_by_index.has(i):
			var row: Dictionary = _slots_by_index[i]
			b.text = "  %d.  %s  —  %s  (level %d)" % [
				i + 1,
				str(row.get("name", "?")),
				str(row.get("class_id", "?")).capitalize(),
				int(row.get("level", 1)),
			]
			b.disabled = false
		else:
			b.text = "  %d.  empty" % (i + 1)
			b.disabled = true


func _set_badge(live: bool) -> void:
	_badge.text = "LIVE" if live else "LOCAL"
	_badge.modulate = Color(0.4, 1.0, 0.5) if live else Color(1.0, 0.7, 0.3)


# =============================================================================
# ACTIONS
# =============================================================================

func _on_slot_pressed(index: int) -> void:
	# The chosen slot is the only thing the test area needs from this screen,
	# and it has to survive a scene change — so it goes in NetClient's static
	# var. Statics outlive the scene tree, and keeping it there rather than on
	# GameState means this branch adds nothing to an autoload that main shares.
	NetClient.selected_slot = index
	get_tree().change_scene_to_file("res://scene/nettest/nettestarea.tscn")


func _on_logout() -> void:
	await Api.logout()
	get_tree().change_scene_to_file("res://scene/nettest/nettestlogin.tscn")
