# tradepanel.gd — the two-sided trade window.
#
# NOTHING HERE MOVES AN ITEM OR A COIN. Every button is a request; the swap
# happens inside one server transaction (see _execute_trade in app.py) and this
# panel renders whatever comes back. That is not caution for its own sake: a
# client that granted itself the item AND asserted the gold it paid has asserted
# both halves of the trade, and _reconcile_inventory() only ever checks the
# first. The shop panel's header makes the same point at more length.
#
# THE TAX SHOWN IS THE SERVER'S OWN NUMBER, from the same gamedata.trade_tax()
# that will actually charge it. Computing it here would be a second opinion that
# can disagree, and the one moment a player must not be surprised is the moment
# they press Accept.
extends Control


const REQUEST_TIMEOUT := 6.0

# How often the panel re-reads the trade while it is open. A trade is a
# conversation between two people, so the other side's edits have to arrive
# without anyone pressing anything - but it is a conversation, not a fight, and
# a second is well inside how fast either of them can click.
const POLL_SECONDS := 1.5


@onready var header_label: Label = %headerlabel
@onready var close_button: Button = %closebutton
@onready var start_box: VBoxContainer = %startbox
@onready var start_label: Label = %startlabel
@onready var nearby_list: VBoxContainer = %nearbylist
@onready var username_edit: LineEdit = %usernameedit
@onready var offer_button: Button = %offerbutton
@onready var trade_box: VBoxContainer = %tradebox
@onready var you_header: Label = %youheader
@onready var you_list: VBoxContainer = %youlist
@onready var gold_spin: SpinBox = %goldspin
@onready var you_tax: Label = %youtax
@onready var them_header: Label = %themheader
@onready var them_list: VBoxContainer = %themlist
@onready var them_gold: Label = %themgold
@onready var them_tax: Label = %themtax
@onready var confirm_button: Button = %confirmbutton
@onready var cancel_button: Button = %cancelbutton
@onready var notice_label: Label = %noticelabel


# The player who opened this, for show_notice() and for reading gold.
var _player: Node = null

# Which half of the trade row is ours, "a" or "b". Resolved by comparing
# Api.username against the names the server sends.
var _my_side: String = ""

# ONE REQUEST AT A TIME. The poll, the confirm and an edit can all fire at once,
# and two updates in flight would each replace the whole of our side - so the
# one that landed second would win regardless of which the player made last.
var _busy: bool = false

var _seconds_to_poll: float = 0.0

# Set while our own side is being re-rendered, so the SpinBox value_changed
# signals that fires does not immediately push a half-built offer back.
var _loading_our_side: bool = false

# How stale the nearby list may get before it is re-read. Slower than the trade
# poll because people walk between areas far less often than they edit an offer,
# and this query joins three tables where the trade poll reads one row.
const NEARBY_REFRESH_SECONDS := 6.0
var _seconds_to_nearby: float = 0.0


func _ready() -> void:
	close_button.pressed.connect(close_panel)
	offer_button.pressed.connect(_on_offer_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	username_edit.text_submitted.connect(func(_t: String) -> void: _on_offer_pressed())
	gold_spin.value_changed.connect(_on_offer_edited)
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_seconds_to_poll -= delta
	if _seconds_to_poll <= 0.0:
		_seconds_to_poll = POLL_SECONDS
		_poll()

	# Only while there is no trade open - once you are trading, who ELSE is
	# around is not information this panel is showing any more.
	if start_box.visible:
		_seconds_to_nearby -= delta
		if _seconds_to_nearby <= 0.0:
			_seconds_to_nearby = NEARBY_REFRESH_SECONDS
			_load_nearby()


# =============================================================================
# OPEN / CLOSE
# =============================================================================

func open_panel(player: Node) -> void:
	_player = player if is_instance_valid(player) else null
	visible = true
	_seconds_to_poll = POLL_SECONDS
	username_edit.text = ""
	_set_notice("", false)
	_seconds_to_nearby = NEARBY_REFRESH_SECONDS
	await _poll(true)
	if start_box.visible:
		await _load_nearby()


func close_panel() -> void:
	# DOES NOT CANCEL THE TRADE. Closing a window is not withdrawing an offer,
	# and a player who clicks the X to see their own backpack would otherwise
	# pull the rug out from under whoever they were negotiating with. The trade
	# lives on the server; reopening this panel picks it straight back up.
	visible = false
	_clear(you_list)
	_clear(them_list)
	_clear(nearby_list)


func toggle_panel(player: Node) -> void:
	if visible:
		close_panel()
	else:
		await open_panel(player)


# =============================================================================
# READING THE TRADE
# =============================================================================

func _poll(render_our_side: bool = false) -> void:
	if _busy:
		return
	_busy = true
	var res: Dictionary = await Api.get_json("/api/trade", REQUEST_TIMEOUT)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_busy = false

	if not res.get("ok", false):
		_set_notice(_refusal_text(res, "Could not read the trade."), true)
		return

	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	var trade = data.get("trade")
	if trade is Dictionary:
		_render(trade, render_our_side)
	else:
		_show_start()


func _show_start() -> void:
	_my_side = ""
	start_box.visible = true
	trade_box.visible = false
	header_label.text = "Trade"
	_clear(you_list)
	_clear(them_list)
	_seconds_to_nearby = 0.0


# =============================================================================
# WHO ELSE IS HERE
# =============================================================================

func _load_nearby() -> void:
	# NOT GUARDED BY _busy, and deliberately not sharing it either. _busy exists
	# so two writes to the same trade cannot race; this reads a different route
	# and changes nothing, so making it wait behind an offer edit would only
	# make the list feel broken while you are typing.
	var res: Dictionary = await Api.get_json(
		"/api/players/nearby?slot=%d" % CharacterData.active_character_index, REQUEST_TIMEOUT)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	# The list is a convenience on top of the typed field, so a failure to read
	# it is not worth a red message over something the player did not ask for.
	if not res.get("ok", false) or not start_box.visible:
		return

	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	var players: Array = data.get("players", []) if data.get("players", []) is Array else []

	# WORDED FROM THE SERVER'S OWN precision FIELD rather than assumed. It says
	# "area" today because saves.area is the finest thing it knows; when real
	# positions exist it will say something else and this line should follow it
	# rather than keep promising a distance the server never measured.
	var where: String = str(data.get("area", ""))
	if str(data.get("precision", "area")) == "area" and where != "":
		start_label.text = "In %s with you" % where.capitalize()
	else:
		start_label.text = "Nearby"

	_clear(nearby_list)
	if players.is_empty():
		var none := Label.new()
		none.text = "Nobody else is here right now."
		none.add_theme_font_size_override("font_size", 11)
		none.add_theme_color_override("font_color", Color(0.7, 0.66, 0.6))
		nearby_list.add_child(none)
		return

	for entry in players:
		if entry is Dictionary:
			nearby_list.add_child(_build_nearby_row(entry))


func _build_nearby_row(entry: Dictionary) -> Control:
	var username: String = str(entry.get("username", ""))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	# The CHARACTER name is what you see in the world; the ACCOUNT name is what
	# the trade endpoint takes. Showing both means the button you press and the
	# person you meant are never two different people.
	label.text = "%s  (%s)" % [str(entry.get("name", username)), username]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 11)
	row.add_child(label)

	var level := Label.new()
	level.text = "lv %d" % int(entry.get("level", 1))
	level.add_theme_font_size_override("font_size", 11)
	level.add_theme_color_override("font_color", Color(0.7, 0.66, 0.6))
	row.add_child(level)

	var button := Button.new()
	button.text = "Trade"
	button.custom_minimum_size = Vector2(60, 24)
	button.add_theme_font_size_override("font_size", 11)
	# bind() rather than a lambda closing over the loop variable, which on the
	# last iteration would make every button open a trade with the same person.
	button.pressed.connect(_open_with.bind(username, int(entry.get("slot", 0))))
	row.add_child(button)

	return row


func _open_with(username: String, to_slot: int) -> void:
	username_edit.text = username
	await _send_offer(username, to_slot)


func _render(trade: Dictionary, render_our_side: bool) -> void:
	var mine: String = Api.username
	var side_a: Dictionary = trade.get("a", {}) if trade.get("a", {}) is Dictionary else {}
	var side_b: Dictionary = trade.get("b", {}) if trade.get("b", {}) is Dictionary else {}
	_my_side = "a" if str(side_a.get("username", "")) == mine else "b"

	var us: Dictionary = side_a if _my_side == "a" else side_b
	var them: Dictionary = side_b if _my_side == "a" else side_a

	start_box.visible = false
	trade_box.visible = true
	header_label.text = "Trading with %s" % str(them.get("username", "?"))

	# THEIR SIDE, EVERY POLL. This is the half that changes without us doing
	# anything, and it is the whole reason the panel polls at all.
	_render_their_side(them)

	# OUR SIDE, ONLY WHEN ASKED - and this is the important half of the rule.
	# Rebuilding our own column on a timer would reset every quantity box the
	# player was in the middle of setting, once every second and a half. So it
	# is rebuilt when the panel opens and after WE change something, which are
	# exactly the moments our side can have changed underneath us.
	if render_our_side:
		_render_our_side(us)
	else:
		_update_our_summary(us)

	_update_buttons(us, them)


func _render_our_side(us: Dictionary) -> void:
	_loading_our_side = true

	_clear(you_list)
	you_header.text = "You%s" % (" — accepted" if bool(us.get("confirmed", false)) else "")

	# Prefill from what the server already has us offering, so reopening the
	# panel shows the offer that is actually standing rather than an empty one.
	var offered: Dictionary = {}
	for entry in (us.get("items", []) if us.get("items", []) is Array else []):
		if entry is Dictionary:
			offered[str(entry.get("item_id", ""))] = int(entry.get("quantity", 0))

	var held: Dictionary = _held_items()
	if held.is_empty():
		var empty := Label.new()
		empty.text = "Your backpack is empty."
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", Color(0.7, 0.66, 0.6))
		you_list.add_child(empty)
	else:
		for item_id in held:
			you_list.add_child(_build_our_row(item_id, int(held[item_id]), int(offered.get(item_id, 0))))

	var purse: int = _current_gold()
	gold_spin.max_value = float(purse)
	gold_spin.value = float(min(int(us.get("gold", 0)), purse))

	_loading_our_side = false
	_update_our_summary(us)


func _update_our_summary(us: Dictionary) -> void:
	you_header.text = "You%s" % (" — accepted" if bool(us.get("confirmed", false)) else "")
	you_tax.text = _tax_text(us)


func _render_their_side(them: Dictionary) -> void:
	_clear(them_list)
	them_header.text = "%s%s" % [
		str(them.get("username", "?")),
		" — accepted" if bool(them.get("confirmed", false)) else "",
	]

	var items: Array = them.get("items", []) if them.get("items", []) is Array else []
	if items.is_empty():
		var empty := Label.new()
		empty.text = "Nothing offered yet."
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", Color(0.7, 0.66, 0.6))
		them_list.add_child(empty)
	else:
		for entry in items:
			if entry is Dictionary:
				them_list.add_child(_build_their_row(entry))

	them_gold.text = "Gold %d" % int(them.get("gold", 0))
	them_tax.text = _tax_text(them)


func _tax_text(side: Dictionary) -> String:
	# The tax a side pays is charged on what they RECEIVE, so the server quotes
	# it on that side's own row already - this only has to print it.
	var tax = side.get("tax")
	if tax == null:
		return ""
	if int(tax) <= 0:
		return "no kingdom cut"
	return "kingdom takes %d" % int(tax)


func _update_buttons(us: Dictionary, them: Dictionary) -> void:
	var we_agreed: bool = bool(us.get("confirmed", false))
	confirm_button.text = "Waiting for them…" if we_agreed else "Accept"
	confirm_button.disabled = we_agreed

	if we_agreed and not bool(them.get("confirmed", false)):
		_set_notice("You have accepted. Waiting for the other side.", false)


# =============================================================================
# OUR OFFER
# =============================================================================

func _held_items() -> Dictionary:
	# item_id -> total held, merged across cells, because the offer is a
	# quantity per item and the server merges it the same way.
	var totals: Dictionary = {}
	var container: Node = _player_inventory_container()
	if container == null or not container.has_method("get_all_stacks"):
		return totals
	for stack in container.get_all_stacks():
		if stack == null or stack.data == null:
			continue
		var id: String = str(stack.data.item_id)
		totals[id] = int(totals.get(id, 0)) + int(stack.quantity)
	return totals


func _build_our_row(item_id: String, held: int, offered: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	var data: ItemData = ItemRegistry.get_item(item_id)
	label.text = data.display_name if data != null else item_id
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 11)
	row.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = held
	spin.step = 1
	spin.value = clampi(offered, 0, held)
	spin.custom_minimum_size = Vector2(62, 0)
	# The id travels on the node so _collect_offer() does not have to parse it
	# back out of a label the player never sees the real value of.
	spin.set_meta("item_id", item_id)
	spin.value_changed.connect(_on_offer_edited)
	row.add_child(spin)

	return row


func _build_their_row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var item_id: String = str(entry.get("item_id", ""))
	var label := Label.new()
	var data: ItemData = ItemRegistry.get_item(item_id)
	label.text = data.display_name if data != null else item_id
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 11)
	row.add_child(label)

	var qty := Label.new()
	qty.text = "x%d" % int(entry.get("quantity", 0))
	qty.add_theme_font_size_override("font_size", 11)
	qty.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	row.add_child(qty)

	return row


func _collect_offer() -> Array:
	var items: Array = []
	for row in you_list.get_children():
		for child in row.get_children():
			if child is SpinBox and child.has_meta("item_id") and int(child.value) > 0:
				items.append({
					"item_id": str(child.get_meta("item_id")),
					"quantity": int(child.value),
				})
	return items


func _on_offer_edited(_value: float) -> void:
	if _loading_our_side or not visible or _my_side == "":
		return
	await _push_offer()


func _push_offer() -> void:
	if _busy:
		return
	_busy = true
	var res: Dictionary = await Api.post("/api/trade/update", {
		"items": _collect_offer(),
		"gold": int(gold_spin.value),
	}, REQUEST_TIMEOUT)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_busy = false

	if not res.get("ok", false):
		_set_notice(_refusal_text(res, "The kingdom would not record that offer."), true)
		return

	# CHANGING AN OFFER WITHDRAWS BOTH ACCEPTANCES - the server does that, not
	# this panel. Re-rendering from the response is what makes that visible
	# immediately rather than up to a poll later, which matters because the
	# other player's "accepted" badge disappearing is the feedback that tells
	# you they now have to look again.
	var trade: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	if not trade.is_empty():
		_render(trade, false)
	_set_notice("", false)
	_seconds_to_poll = POLL_SECONDS


# =============================================================================
# ACTIONS
# =============================================================================

func _on_offer_pressed() -> void:
	var who: String = username_edit.text.strip_edges()
	if who == "":
		_set_notice("Pick somebody, or type their account name.", true)
		return
	await _send_offer(who, 0)


func _send_offer(who: String, to_slot: int) -> void:
	if _busy:
		return
	_busy = true
	var res: Dictionary = await Api.post("/api/trade/offer", {
		"slot": CharacterData.active_character_index,
		"username": who,
		"to_slot": to_slot,
	}, REQUEST_TIMEOUT)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_busy = false

	if not res.get("ok", false):
		_set_notice(_refusal_text(res, "Could not open a trade with %s." % who), true)
		return

	var trade: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	if not trade.is_empty():
		_render(trade, true)
	_set_notice("", false)


func _on_confirm_pressed() -> void:
	if _busy:
		return
	_busy = true
	var acting: Node = _player if is_instance_valid(_player) else null
	var res: Dictionary = await Api.post("/api/trade/confirm", {}, REQUEST_TIMEOUT)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_busy = false

	if not res.get("ok", false):
		# A REFUSAL IS NOT A CRASH AND NOT A LOSS. The server rolls the whole
		# attempt back and clears both acceptances, so the trade is still open
		# and still exactly as it was - see _trade_refuse(). Saying why and
		# re-reading is the right response.
		_set_notice(_refusal_text(res, "The trade did not go through."), true)
		await _poll(true)
		return

	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	if str(data.get("state", "")) == "done":
		_apply_result(data, acting)
	else:
		# Only our half landed; the other side has not accepted yet.
		if not data.is_empty():
			_render(data, false)


func _on_cancel_pressed() -> void:
	if _busy:
		return
	_busy = true
	var res: Dictionary = await Api.post("/api/trade/cancel", {}, REQUEST_TIMEOUT)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_busy = false

	if not res.get("ok", false):
		_set_notice(_refusal_text(res, "Could not cancel."), true)
		return
	_show_start()
	_set_notice("Trade cancelled.", false)


func _apply_result(data: Dictionary, acting: Node) -> void:
	# OUR HALF OF THE RESULT, picked with the side we resolved when the trade
	# was rendered. The response carries no usernames - it does not need to,
	# because a trade can only execute while it is open and _my_side is set for
	# as long as that is true.
	var ours: Dictionary = data.get(_my_side, {}) if data.get(_my_side, {}) is Dictionary else {}

	# THE SERVER'S NUMBERS, NOT A LOCAL SUBTRACTION. It decided the tax and the
	# new balance; recomputing here would be a second opinion that can disagree,
	# and the disagreement shows up as a purse that drifts.
	if ours.has("gold"):
		_write_gold(int(ours["gold"]))

	var cells: Array = ours.get("inventory", []) if ours.get("inventory", []) is Array else []
	if not cells.is_empty():
		var container: Node = _player_inventory_container()
		if container != null:
			container.load_server_array(cells)
		else:
			push_warning("TradePanel: player inventory not found — the server has the items, this screen does not")

	Audio.play("coin")

	var paid: Dictionary = data.get("tax_paid", {}) if data.get("tax_paid", {}) is Dictionary else {}
	var our_tax: int = int(paid.get(_my_side, 0))
	_notify(acting, "Trade complete. The kingdom took %d gold." % our_tax)

	_show_start()
	_set_notice("Trade complete — the kingdom took %d gold in total." % int(data.get("kingdom_take", 0)), false)


# =============================================================================
# PLAYER AND INVENTORY
# =============================================================================

func _player_inventory_container() -> Node:
	# Reached through the HUD rather than held as a reference: the inventory
	# screen is lazily created and freed on logout, so a cached node here would
	# dangle the first time someone logs out and back in.
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return null
	var inventory_screen: Node = hud.get("inventory_screen") if "inventory_screen" in hud else null
	if inventory_screen == null:
		return null
	return inventory_screen.get_node_or_null("%inventorycontainer")


func _current_gold() -> int:
	var player: Node = _player if is_instance_valid(_player) else null
	if player != null and "gold" in player:
		return int(player.gold)
	return 0


func _write_gold(amount: int) -> void:
	var player: Node = _player if is_instance_valid(_player) else null
	if player == null:
		return
	if player.has_method("set_gold"):
		player.set_gold(amount)
	elif "gold" in player:
		player.gold = amount


# =============================================================================
# MESSAGES
# =============================================================================

func _clear(list: VBoxContainer) -> void:
	for child in list.get_children():
		child.queue_free()


func _set_notice(message: String, is_error: bool) -> void:
	notice_label.text = message
	notice_label.add_theme_color_override(
		"font_color",
		Color(1, 0.6, 0.5) if is_error else Color(0.7, 0.66, 0.6),
	)


func _refusal_text(res: Dictionary, fallback: String) -> String:
	# api.gd has already turned the response into a sentence - see
	# _describe_api_error(). Re-deriving it is the mistake shopinventory.gd
	# made, where a 404 with an HTML body fell through to a message about the
	# network and sent the search in entirely the wrong direction.
	var status: int = int(res.get("status", 0))
	var message: String = str(res.get("error", ""))
	if status == 0:
		return message if message != "" else "No connection to the server."
	if status == 404 and message == "":
		push_warning("TradePanel: no /api/trade route — is app.py current and restarted?")
		return "The server does not know about trading yet."
	return message if message != "" else "%s (HTTP %d)" % [fallback, status]


func _notify(player: Node, message: String) -> void:
	if is_instance_valid(player) and player.has_method("show_notice"):
		player.show_notice(message)
