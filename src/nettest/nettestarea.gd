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

# Write-back. _stats is the client's working copy: the mutation buttons change
# it immediately so the HUD responds instantly, while StateSync pushes the same
# change up on a debounce. The server's reply then overwrites it, so if the
# server disagrees — a clamp, a rejection — its answer wins on the next tick.
var _sync: StateSync
var _sync_label: Label
var _stats: Dictionary = {}

# Bank
var _bank_badge: Label
var _bank_gold: Label
var _bank_carried: Label
var _gold_amount: SpinBox
var _gold_deposit: Button
var _gold_withdraw: Button
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

	# StateSync needs _process, so it has to be a node in the tree rather than
	# a plain object. Adding it as a child also means it dies with this screen,
	# which is why the back button flushes first.
	_sync = StateSync.new()
	_sync.name = "statesync"
	_sync.configure(_net, _slot)
	add_child(_sync)
	_sync.state_changed.connect(_on_sync_state_changed)
	_sync.synced.connect(_on_synced)

	_build_ui()
	_on_sync_state_changed(_sync.get_state(), "")

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
	# FLUSH BEFORE LEAVING. The debounce timer lives on a node that is about to
	# be freed, so anything still pending would simply never be sent. This is
	# the case a pure timer cannot cover, and it's the one that loses real
	# player progress — the same reason the local save flushes on area change.
	back.pressed.connect(func():
		if _sync.has_pending():
			await _sync.flush()
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

	# Stand-ins for gameplay. In the real game these values move because you
	# got hit or killed something; here they move because you pressed a button.
	# The write path being tested is identical either way.
	var label := Label.new()
	label.text = "simulate gameplay"
	label.add_theme_font_size_override("font_size", 10)
	label.modulate = Color(1, 1, 1, 0.4)
	panel.add_child(label)

	var row_a := HBoxContainer.new()
	panel.add_child(row_a)
	row_a.add_child(_stat_button("-10 hp", "hp", -10))
	row_a.add_child(_stat_button("+10 hp", "hp", 10))

	var row_b := HBoxContainer.new()
	panel.add_child(row_b)
	row_b.add_child(_stat_button("+100 xp", "xp", 100))
	row_b.add_child(_stat_button("+50 gold", "gold", 50))

	panel.add_child(_gap(8))

	_sync_label = Label.new()
	_sync_label.add_theme_font_size_override("font_size", 11)
	panel.add_child(_sync_label)

	var flush := Button.new()
	flush.text = "Save now"
	flush.pressed.connect(func(): await _sync.flush())
	panel.add_child(flush)

	var refresh := Button.new()
	refresh.text = "Refresh status"
	refresh.pressed.connect(func(): await _refresh_status())
	panel.add_child(refresh)

	_hud_status = _small_label()
	panel.add_child(_hud_status)

	return panel


func _stat_button(text: String, field: String, delta: int) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(_adjust_stat.bind(field, delta))
	return b


func _build_bank_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 4)

	panel.add_child(_panel_header("BANK", "/api/bank", func(b): _bank_badge = b))

	_bank_gold = Label.new()
	_bank_gold.text = "Banked gold: —"
	panel.add_child(_bank_gold)

	# Both sides of the transfer are shown, because the server refuses a move
	# larger than the source side holds — and a player who can only see one
	# number has no way to predict which moves are legal.
	_bank_carried = Label.new()
	_bank_carried.text = "Carried gold: —"
	panel.add_child(_bank_carried)

	var gold_row := HBoxContainer.new()
	panel.add_child(gold_row)

	_gold_amount = SpinBox.new()
	_gold_amount.min_value = 1
	_gold_amount.max_value = 999999
	_gold_amount.value = 100
	gold_row.add_child(_gold_amount)

	_gold_deposit = Button.new()
	_gold_deposit.text = "Bank gold"
	_gold_deposit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gold_deposit.pressed.connect(func(): await _gold_op("deposit"))
	gold_row.add_child(_gold_deposit)

	_gold_withdraw = Button.new()
	_gold_withdraw.text = "Take gold"
	_gold_withdraw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gold_withdraw.pressed.connect(func(): await _gold_op("withdraw"))
	gold_row.add_child(_gold_withdraw)

	panel.add_child(_gap(8))

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

	_stats = res.data
	_render_stats()
	_render_carried_gold()


# The bank's "carried" figure is updated ONLY from server-confirmed values,
# never from the optimistic local copy. It is the number the server validates a
# transfer against, so showing an unconfirmed one would tell the player a
# deposit is possible moments before the server refuses it — which is exactly
# what happened the first time this screen was used.
func _render_carried_gold() -> void:
	if _bank_carried == null or _stats.is_empty():
		return
	_bank_carried.text = "Carried gold: %d" % int(_stats.get("gold", 0))


func _render_stats() -> void:
	var d: Dictionary = _stats
	_hud_rows["level"].text   = str(d.get("level", 0))
	_hud_rows["hp"].text      = "%d / %d" % [d.get("hp", 0), d.get("max_hp", 0)]
	_hud_rows["mana"].text    = "%d / %d" % [d.get("mana", 0), d.get("max_mana", 0)]
	_hud_rows["stamina"].text = "%d / %d" % [d.get("stamina", 0), d.get("max_stamina", 0)]
	_hud_rows["gold"].text    = str(d.get("gold", 0))
	_hud_rows["xp"].text      = "%d  (%d to next)" % [d.get("xp", 0), d.get("xp_to_next", 0)]


# =============================================================================
# WRITE-BACK
# =============================================================================

func _adjust_stat(field: String, delta: int) -> void:
	if _stats.is_empty():
		_hud_status.text = "No status loaded yet."
		return

	var value: int = int(_stats.get(field, 0)) + delta

	# Clamp locally to what the server will accept, so the common case doesn't
	# spend a round trip earning a 400. The server checks again regardless —
	# this is a courtesy, not a substitute for validation.
	value = max(value, 0)
	if field == "hp":
		value = min(value, int(_stats.get("max_hp", value)))
	elif field == "mana":
		value = min(value, int(_stats.get("max_mana", value)))
	elif field == "stamina":
		value = min(value, int(_stats.get("max_stamina", value)))

	_stats[field] = value
	_render_stats()
	_sync.mark(field, value)


func _on_sync_state_changed(state: int, detail: String) -> void:
	if _sync_label == null:
		return
	_sync_label.text = StateSync.state_name(state)
	match state:
		StateSync.State.SYNCED:
			_sync_label.modulate = Color(0.4, 1.0, 0.5)
		StateSync.State.FAILED:
			_sync_label.modulate = Color(1.0, 0.45, 0.45)
			_sync_label.text += " — " + detail
		StateSync.State.SYNCING:
			_sync_label.modulate = Color(0.6, 0.8, 1.0)
		_:
			_sync_label.modulate = Color(1, 1, 1, 0.5)


func _on_synced(status: Dictionary) -> void:
	# The server's reply is authoritative. If it clamped or corrected anything,
	# this is where the client finds out and stops showing its own guess.
	_stats = status
	_render_stats()
	_render_carried_gold()


func _gold_op(op: String) -> void:
	if _busy:
		return

	# FLUSH BEFORE TRANSFERRING. A gold transfer is validated server-side
	# against saves.gold, so any stat push still sitting in the debounce has to
	# land first. Without this, earning gold and immediately banking it is
	# refused — the client knows about the gold and the server doesn't yet.
	#
	# This is the general shape of the problem: a debounced write is fine until
	# something else depends on it having happened. Those points have to flush.
	if _sync.has_pending():
		_bank_status.text = "Saving stats first..."
		await _sync.flush()

	_set_gold_busy(true)
	_bank_status.text = "%s gold..." % op.capitalize()

	var res: Dictionary = await _net.bank_gold_op(_slot, op, int(_gold_amount.value))

	_set_gold_busy(false)

	if not res.ok:
		_bank_status.text = res.error
		return

	_apply_bank(res)

	# Carried gold just changed on the server, so the HUD's copy is stale.
	# Pull rather than guess — the transfer is the server's arithmetic.
	await _refresh_status()


func _set_gold_busy(busy: bool) -> void:
	_busy = busy
	_gold_deposit.disabled = busy
	_gold_withdraw.disabled = busy


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

	_bank_gold.text = "Banked gold: %d" % int(d.get("gold", 0))
	_bank_carried.text = "Carried gold: %d" % int(d.get("carried_gold", 0))
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
