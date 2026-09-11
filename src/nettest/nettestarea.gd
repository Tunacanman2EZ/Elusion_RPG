# nettestarea.gd — Net-Test branch, screen 3 of 3.
#
# A room with nothing in it but the two things this branch is testing: a HUD
# fed by GET /api/player/status, and a bank panel fed by GET/POST /api/bank.
# There is no player, no enemy and no tilemap, because none of those are what
# is being tested and all of them would make a failure harder to read.
#
# Each panel carries its own LIVE / LOCAL badge. They light up independently,
# which is what makes this branch useful: you can land /api/player/status,
# watch the HUD go green, and know for certain the bank is still on placeholder
# data because its badge is still orange.
extends Control


var _net: NetClient
var _slot: int = 0

# HUD
var _hud_badge: Label
var _hud_rows: Dictionary = {}
var _hud_status: Label

# Bank
var _bank_badge: Label
var _bank_gold: Label
var _bank_capacity: Label
var _bank_list: VBoxContainer
var _bank_status: Label
var _item_field: LineEdit
var _qty_field: SpinBox
var _deposit_button: Button
var _withdraw_button: Button

var _busy: bool = false


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_net = NetClient.new()
	_slot = NetClient.selected_slot

	_build_ui()

	await _refresh_status()
	await _refresh_bank()


# =============================================================================
# UI CONSTRUCTION
# =============================================================================

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	margin.add_child(page)

	page.add_child(_build_header())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(columns)

	columns.add_child(_build_hud_panel())
	columns.add_child(_build_bank_panel())


func _build_header() -> Control:
	var row := HBoxContainer.new()

	var title := Label.new()
	title.text = "TEST AREA — slot %d" % (_slot + 1)
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	var back := Button.new()
	back.text = "Back to characters"
	back.pressed.connect(func():
		get_tree().change_scene_to_file("res://scene/nettest/nettestselect.tscn")
	)
	row.add_child(back)

	return row


func _build_hud_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)
	panel.add_theme_constant_override("separation", 4)

	panel.add_child(_panel_header("HUD", "/api/player/status", func(b): _hud_badge = b))

	# These are exactly the fields the real characterhud.gd shows. Naming them
	# identically now means the swap from local stats to server stats later is
	# a change of source, not a change of shape.
	for key in ["level", "hp", "mana", "stamina", "gold", "xp"]:
		var row := HBoxContainer.new()

		var name_label := Label.new()
		name_label.text = key.capitalize()
		name_label.custom_minimum_size = Vector2(90, 0)
		name_label.modulate = Color(1, 1, 1, 0.6)
		row.add_child(name_label)

		var value_label := Label.new()
		value_label.text = "—"
		row.add_child(value_label)

		_hud_rows[key] = value_label
		panel.add_child(row)

	panel.add_child(_gap(10))

	var refresh := Button.new()
	refresh.text = "Refresh status"
	refresh.pressed.connect(func(): await _refresh_status())
	panel.add_child(refresh)

	_hud_status = _small_label()
	panel.add_child(_hud_status)

	return panel


func _build_bank_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 4)

	panel.add_child(_panel_header("BANK", "/api/bank", func(b): _bank_badge = b))

	_bank_gold = Label.new()
	_bank_gold.text = "Gold: —"
	panel.add_child(_bank_gold)

	_bank_capacity = Label.new()
	_bank_capacity.text = "Slots: —"
	_bank_capacity.modulate = Color(1, 1, 1, 0.6)
	_bank_capacity.add_theme_font_size_override("font_size", 11)
	panel.add_child(_bank_capacity)

	panel.add_child(_gap(8))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(340, 160)
	panel.add_child(scroll)

	_bank_list = VBoxContainer.new()
	_bank_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_bank_list)

	panel.add_child(_gap(8))

	var form := HBoxContainer.new()
	panel.add_child(form)

	_item_field = LineEdit.new()
	_item_field.placeholder_text = "item_id"
	_item_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_item_field)

	_qty_field = SpinBox.new()
	_qty_field.min_value = 1
	_qty_field.max_value = 9999
	_qty_field.value = 1
	form.add_child(_qty_field)

	var buttons := HBoxContainer.new()
	panel.add_child(buttons)

	_deposit_button = Button.new()
	_deposit_button.text = "Deposit"
	_deposit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deposit_button.pressed.connect(func(): await _bank_op("deposit"))
	buttons.add_child(_deposit_button)

	_withdraw_button = Button.new()
	_withdraw_button.text = "Withdraw"
	_withdraw_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_withdraw_button.pressed.connect(func(): await _bank_op("withdraw"))
	buttons.add_child(_withdraw_button)

	_bank_status = _small_label()
	panel.add_child(_bank_status)

	return panel


func _panel_header(title: String, endpoint: String, capture: Callable) -> Control:
	var box := VBoxContainer.new()

	var row := HBoxContainer.new()
	box.add_child(row)

	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 15)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var badge := Label.new()
	badge.text = "—"
	badge.add_theme_font_size_override("font_size", 11)
	row.add_child(badge)
	capture.call(badge)

	var path := Label.new()
	path.text = endpoint
	path.add_theme_font_size_override("font_size", 10)
	path.modulate = Color(1, 1, 1, 0.4)
	box.add_child(path)

	box.add_child(_gap(6))
	return box


func _small_label() -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 11)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 34)
	return l


func _gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func _set_badge(badge: Label, live: bool) -> void:
	badge.text = "LIVE" if live else "LOCAL"
	badge.modulate = Color(0.4, 1.0, 0.5) if live else Color(1.0, 0.7, 0.3)


# =============================================================================
# HUD
# =============================================================================

func _refresh_status() -> void:
	var res: Dictionary = await _net.fetch_status(_slot)

	if not res.ok:
		_set_badge(_hud_badge, false)
		_hud_status.text = res.error
		return

	_set_badge(_hud_badge, res.live)
	_hud_status.text = "" if res.live else res.error

	var d: Dictionary = res.data
	_hud_rows["level"].text   = str(d.get("level", 0))
	_hud_rows["hp"].text      = "%d / %d" % [d.get("hp", 0), d.get("max_hp", 0)]
	_hud_rows["mana"].text    = "%d / %d" % [d.get("mana", 0), d.get("max_mana", 0)]
	_hud_rows["stamina"].text = "%d / %d" % [d.get("stamina", 0), d.get("max_stamina", 0)]
	_hud_rows["gold"].text    = str(d.get("gold", 0))
	_hud_rows["xp"].text      = "%d  (%d to next)" % [d.get("xp", 0), d.get("xp_to_next", 0)]


# =============================================================================
# BANK
# =============================================================================

func _refresh_bank() -> void:
	var res: Dictionary = await _net.fetch_bank(_slot)
	_apply_bank(res)


func _bank_op(op: String) -> void:
	if _busy:
		return

	var item_id: String = _item_field.text.strip_edges()
	if item_id == "":
		_bank_status.text = "Enter an item_id."
		return

	_set_bank_busy(true)
	_bank_status.text = "%s ..." % op.capitalize()

	var res: Dictionary = await _net.bank_op(_slot, op, item_id, int(_qty_field.value))

	_set_bank_busy(false)

	# A rejected operation keeps the panel showing the LAST KNOWN GOOD bank
	# rather than blanking it. Blanking on error is how a player concludes
	# their items are gone and panics.
	if not res.ok:
		_bank_status.text = res.error
		return

	_apply_bank(res)


func _apply_bank(res: Dictionary) -> void:
	if not res.ok:
		_set_badge(_bank_badge, false)
		_bank_status.text = res.error
		return

	_set_badge(_bank_badge, res.live)
	_bank_status.text = "" if res.live else res.error

	var d: Dictionary = res.data
	var items: Array = d.get("items", [])

	_bank_gold.text = "Gold: %d" % int(d.get("gold", 0))
	_bank_capacity.text = "Slots: %d / %d" % [items.size(), int(d.get("capacity", 0))]

	for child in _bank_list.get_children():
		child.queue_free()

	if items.is_empty():
		var empty := Label.new()
		empty.text = "  (empty)"
		empty.modulate = Color(1, 1, 1, 0.4)
		_bank_list.add_child(empty)
		return

	for item in items:
		var row := HBoxContainer.new()

		var id_label := Label.new()
		id_label.text = str(item.get("item_id", "?"))
		id_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(id_label)

		var qty_label := Label.new()
		qty_label.text = "x%d" % int(item.get("quantity", 0))
		row.add_child(qty_label)

		# Clicking a row fills the form, so withdrawing doesn't mean retyping
		# an item id by hand every time.
		var button := Button.new()
		button.text = "use"
		button.add_theme_font_size_override("font_size", 10)
		button.pressed.connect(func():
			_item_field.text = str(item.get("item_id", ""))
		)
		row.add_child(button)

		_bank_list.add_child(row)


func _set_bank_busy(busy: bool) -> void:
	_busy = busy
	_deposit_button.disabled = busy
	_withdraw_button.disabled = busy
