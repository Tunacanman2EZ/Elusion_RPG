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
#
# ACCEPT MEANS WHAT YOU SAW. Every change to either side moves the trade's
# revision, and Accept sends the revision this window last drew. The server
# refuses an accept for any other - so the sword that was swapped for a stick
# a moment before you clicked cannot be "accepted" as the stick. When that
# happens the window redraws the offer as it now stands and says it changed.
#
# THE ONE WHO ACCEPTS FIRST IS TOLD HOW IT ENDED. They are not the one whose
# request runs the trade, so for a long time their window just emptied and
# their bag went on showing what it had - and their next save deleted what the
# trade gave them. The poll now carries the result (see _apply_poll()) and
# CharacterData adopts it.
#
# A TRADE IS MADE FROM THE BAG (0.93.0). The owner: "i find trade screen pretty
# annoying also we need to upgrade the way it works" - too many steps, the
# window in the way, the deal hard to see, and starting one. Your side listed
# every item you held, each with a number box to set, in a window 580 wide in
# the middle of the screen. Now:
#   - the window is smaller and opens BESIDE THE BAG, which opens with it
#     (_bring_the_bag(), docked_at());
#   - your side lists only what you are giving. An item goes on by a
#     double-click in the bag (a finger held, on a phone) or by dragging it onto
#     your side; a stack's - and + and an x on each row change or take it off
#     (add_from_bag(), _offer);
#   - the columns are "You give" and "You get", each with its worth;
#   - and the one asked is shown a card with See offer and No thanks
#     (tradeprompt.gd), not only a dot on the Trade button.
extends Control


const NameTag := preload("res://src/shared/nametag.gd")
const Marks := preload("res://src/shared/marks.gd")
# ago_text(), the guild panel's "2 h ago", aged against the server's clock.
const GuildPanelScript := preload("res://src/ui/guild/guildpanel.gd")

const REQUEST_TIMEOUT := 6.0

# How often the panel re-reads the trade while it is open. A trade is a
# conversation between two people, so the other side's edits have to arrive
# without anyone pressing anything - but it is a conversation, not a fight, and
# a second is well inside how fast either of them can click.
const POLL_SECONDS := 1.5

# How many finished trades the start view lists. The server keeps ten; five is
# what fits under the nearby list without a scrollbar.
const RECENT_SHOWN := 5

# Rows: icon, then the name over its value.
const ICON_SIZE := Vector2(24, 24)
const ROW_FONT_SIZE := 11
const HINT_FONT_SIZE := 9

const COLOUR_HINT := Color(0.7, 0.66, 0.6)
const COLOUR_GOLD := Color(1, 0.9, 0.5)
const COLOUR_AGREED := Color(0.55, 0.9, 0.55)
const COLOUR_WAITING := Color(0.62, 0.86, 1.0)
const COLOUR_WARN := Color(1, 0.6, 0.5)
const COLOUR_ONLINE := Color(0.45, 0.85, 0.45)
const COLOUR_OFFLINE := Color(0.55, 0.55, 0.55)


@onready var header_label: Label = %headerlabel
@onready var close_button: Button = %closebutton
@onready var start_box: VBoxContainer = %startbox
@onready var start_label: Label = %startlabel
@onready var nearby_list: VBoxContainer = %nearbylist
@onready var username_edit: LineEdit = %usernameedit
@onready var offer_button: Button = %offerbutton
@onready var recent_caption: Label = %recentcaption
@onready var recent_list: VBoxContainer = %recentlist
@onready var trade_box: VBoxContainer = %tradebox
@onready var with_row: HBoxContainer = %withrow
@onready var you_panel: PanelContainer = %youpanel
@onready var you_header: Label = %youheader
@onready var you_list: VBoxContainer = %youlist
@onready var gold_spin: SpinBox = %goldspin
@onready var you_worth: Label = %youworth
@onready var them_panel: PanelContainer = %thempanel
@onready var them_header: Label = %themheader
@onready var them_list: VBoxContainer = %themlist
@onready var them_gold: Label = %themgold
@onready var them_worth: Label = %themworth
@onready var summary_label: Label = %summarylabel
@onready var confirm_button: Button = %confirmbutton
@onready var cancel_button: Button = %cancelbutton
@onready var notice_label: Label = %noticelabel


# The player who opened this, for reading gold.
var _player: Node = null

# Which half of the trade row is ours, "a" or "b". Resolved by comparing
# Api.username against the names the server sends. Side a is whoever opened it.
var _my_side: String = ""

# THE REVISION THIS WINDOW LAST DREW, which is what Accept sends. See the header.
var _revision: int = -1

# The trade this window is showing, so that when it disappears from the poll
# the window can say how it ended rather than silently going back to the list.
var _watched_trade_id: String = ""

# What the other side was offering when we last drew it, as text - so a change
# can be pointed out rather than slipped in. "" means "not drawn yet".
var _their_signature: String = ""

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


# Drag by the header, resize from any edge, and come back where it was left.
# One component for all sixteen panels - see src/shared/panelwindow.gd for why
# this is not thirty lines copied into each of them.
#
# HELD IN A MEMBER, not discarded. It is a RefCounted carrying the drag state
# and the signal connections; letting it go frees it and the panel quietly
# stops responding.
var _window: PanelWindow


func _ready() -> void:
	_window = PanelWindow.attach(self, "trade")
	close_button.pressed.connect(close_panel)
	offer_button.pressed.connect(_on_offer_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	username_edit.text_submitted.connect(func(_t: String) -> void: _on_offer_pressed())
	gold_spin.value_changed.connect(_on_offer_edited)
	# ANYWHERE ON OUR SIDE TAKES A DROP from the bag: the panel, the list and
	# the space under it.
	for part: Control in [you_panel, you_list, you_list.get_parent() as Control]:
		part.set_drag_forwarding(Callable(), _can_drop_offer, _drop_offer)
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
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if trade_box.visible:
		_bring_the_bag()
	if start_box.visible:
		await _check_trading_open()
		_load_recent()
		await _load_nearby()


# THE OWNER'S TRADE SWITCH (POST /api/server/trade). Off, nobody can open a
# new trade and a trade already open may still finish, so the window asks
# /api/status when it opens on the start page and says so before anybody types
# a name, rather than after the server refuses. A seam for the suite.
const TRADING_OFF_TEXT := "Trading is switched off for now. A trade already open can still finish."
var status_request: Callable = Callable(Api, "get_json")


func _check_trading_open() -> void:
	var res: Dictionary = await status_request.call("/api/status")
	if not is_instance_valid(self) or not is_inside_tree():
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	# An older server, or no answer, says nothing about trading: leave it on and
	# let the server's own answer to an offer speak.
	var trading: bool = not res.get("ok", false) or bool(data.get("trade", true))
	offer_button.disabled = not trading
	if not trading:
		_set_notice(TRADING_OFF_TEXT, true)


func close_panel() -> void:
	# DOES NOT CANCEL THE TRADE. Closing a window is not withdrawing an offer,
	# and a player who clicks the X to see their own backpack would otherwise
	# pull the rug out from under whoever they were negotiating with. The trade
	# lives on the server; reopening this panel picks it straight back up, and
	# the HUD's poll says if the other side does anything meanwhile.
	visible = false
	_wire_bag(false)
	_clear(you_list)
	_clear(them_list)
	_clear(nearby_list)
	_clear(recent_list)


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
	# AN EDIT MADE DURING THE POLL GOES NOW (see _push_offer()).
	if _offer_dirty:
		_push_offer.call_deferred()

	if not res.get("ok", false):
		_set_notice(_refusal_text(res, "Could not read the trade."), true)
		return

	_apply_poll(res.get("data", {}) if res.get("data", {}) is Dictionary else {}, render_our_side)


func _apply_poll(data: Dictionary, render_our_side: bool = false) -> void:
	"""One answer from GET /api/trade, onto the window. SPLIT FROM _poll() so the
	suite can hand it a made-up answer and look at the result.

	THREE THINGS CAN BE IN IT. "trade", the open trade or null. "resync", a bag
	and purse to adopt because a trade finished while we were not the one
	asking. And "last", how the most recent trade ended - which is what lets a
	window that was watching a trade say "complete" or "called off" instead of
	quietly going back to the list as if nothing had happened."""
	var resync = data.get("resync")
	if resync is Dictionary:
		# CharacterData adopts it and the HUD announces it; see apply_server_carry().
		CharacterData.apply_server_carry(resync, _player)

	var trade = data.get("trade")
	if trade is Dictionary:
		_render(trade, render_our_side)
		return

	if _watched_trade_id != "":
		_set_notice(ending_text(_watched_trade_id, data.get("last"), resync), false)
		_watched_trade_id = ""
		_show_start()
	elif not start_box.visible:
		_show_start()


static func ending_text(watched: String, last: Variant, resync: Variant) -> String:
	"""What to say when the trade this window was showing is no longer open."""
	if resync is Dictionary and resync.get("trade") is Dictionary \
			and str((resync["trade"] as Dictionary).get("trade_id", "")) == watched:
		return "Trade complete."
	if last is Dictionary and str((last as Dictionary).get("trade_id", "")) == watched:
		match str((last as Dictionary).get("state", "")):
			"done":
				return "Trade complete."
			"cancelled":
				return "The trade was called off."
	# NOT THE LAST ONE, AND NOT FINISHED: it ran out of time. A trade nobody
	# touches for ten minutes is dropped by the server rather than kept open.
	return "The trade expired."


func _show_start() -> void:
	_my_side = ""
	_revision = -1
	_their_signature = ""
	start_box.visible = true
	trade_box.visible = false
	header_label.text = "Trade"
	_wire_bag(false)
	_offer.clear()
	_clear(you_list)
	_clear(them_list)
	_clear(with_row)
	_seconds_to_nearby = 0.0
	_load_recent()


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
	_apply_nearby(res.get("data", {}) if res.get("data", {}) is Dictionary else {})


func _apply_nearby(data: Dictionary) -> void:
	var players: Array = data.get("players", []) if data.get("players", []) is Array else []

	# WORDED FROM THE SERVER'S OWN precision FIELD rather than assumed. It says
	# "area" today because saves.area is the finest thing it knows; when real
	# positions exist it will say something else and this line should follow it
	# rather than keep promising a distance the server never measured.
	var where: String = str(data.get("area", ""))
	if str(data.get("precision", "area")) == "area" and where != "":
		start_label.text = "In %s with you" % AreaRegistry.display_name(where)
	else:
		start_label.text = "Nearby"

	_clear(nearby_list)
	if players.is_empty():
		nearby_list.add_child(_hint_label("Nobody else is here right now."))
		return

	for entry in players:
		if entry is Dictionary:
			nearby_list.add_child(_build_nearby_row(entry))


func _build_nearby_row(entry: Dictionary) -> Control:
	var username: String = str(entry.get("username", ""))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# THE CHARACTER NAME, drawn the way every other list draws a name: in the
	# colour its owner chose, with the rank as a badge. See nametag.gd.
	NameTag.add_to(row, str(entry.get("name", username)), str(entry.get("role", "player")),
		entry.get("name_hue"), ROW_FONT_SIZE + 1)

	# The ACCOUNT name is what the trade endpoint takes. Showing both means the
	# button you press and the person you meant are never two different people.
	var account := Label.new()
	account.text = "(%s)" % username
	account.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	account.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	account.add_theme_color_override("font_color", COLOUR_HINT)
	row.add_child(account)

	var level := Label.new()
	level.text = "lv %d" % int(entry.get("level", 1))
	level.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	level.add_theme_color_override("font_color", COLOUR_HINT)
	row.add_child(level)

	var button := Button.new()
	button.name = "tradewith"
	button.text = "Trade"
	button.custom_minimum_size = Vector2(60, 24)
	button.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	# bind() rather than a lambda closing over the loop variable, which on the
	# last iteration would make every button open a trade with the same person.
	button.pressed.connect(_open_with.bind(username, int(entry.get("slot", 0))))
	row.add_child(button)

	return row


func _open_with(username: String, to_slot: int) -> void:
	username_edit.text = username
	await _send_offer(username, to_slot)


# =============================================================================
# YOUR RECENT TRADES
# =============================================================================

func _load_recent() -> void:
	# ONCE PER VISIT TO THE LIST, not on the poll. History only changes when a
	# trade finishes, and every finish brings the window back here - which is
	# exactly when this runs.
	if not is_inside_tree():
		return
	var res: Dictionary = await Api.get_json("/api/trade/history", REQUEST_TIMEOUT)
	if not is_instance_valid(self) or not is_inside_tree() or not start_box.visible:
		return
	if not res.get("ok", false):
		return
	_apply_recent(res.get("data", {}) if res.get("data", {}) is Dictionary else {})


func _apply_recent(data: Dictionary) -> void:
	var trades: Array = data.get("trades", []) if data.get("trades", []) is Array else []
	var now: int = int(data.get("now", 0))
	_clear(recent_list)
	recent_caption.visible = true
	if trades.is_empty():
		recent_list.add_child(_hint_label("None yet. Finished trades are listed here."))
		return
	for record in trades.slice(0, RECENT_SHOWN):
		if record is Dictionary:
			recent_list.add_child(_build_recent_row(record, now))


func _build_recent_row(record: Dictionary, now: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.tooltip_text = result_line(record)
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var what := Label.new()
	what.text = history_line(record)
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	what.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	# THIS ONE MAY CLIP, and it is the only label in the window that may: it is
	# a one-line summary with the whole sentence in the tooltip. See CLAUDE.md
	# on the Label that gives way - the name that loses a row is the thing a
	# panel is about, and here the thing the row is about is the whole line.
	what.clip_text = true
	what.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	what.custom_minimum_size = Vector2(120, 0)
	row.add_child(what)

	var when := Label.new()
	when.text = GuildPanelScript.ago_text(int(record.get("at", 0)), now)
	when.add_theme_font_size_override("font_size", HINT_FONT_SIZE + 1)
	when.add_theme_color_override("font_color", COLOUR_HINT)
	row.add_child(when)
	return row


static func item_name(item_id: String) -> String:
	var data: ItemData = ItemRegistry.get_item(item_id)
	return data.display_name if data != null and data.display_name != "" else item_id


static func goods_text(items: Variant, gold: int) -> String:
	"""'Iron Sword, 3 x Tiny Health Potion and 300 gold' - or 'nothing'."""
	var parts: PackedStringArray = []
	for entry in (items if items is Array else []):
		if not (entry is Dictionary):
			continue
		var quantity: int = int(entry.get("quantity", 1))
		var called: String = item_name(str(entry.get("item_id", "")))
		parts.append(called if quantity == 1 else "%d x %s" % [quantity, called])
	if gold > 0:
		parts.append(GameConstants.gold_text(gold))
	if parts.is_empty():
		return "nothing"
	if parts.size() == 1:
		return parts[0]
	return "%s and %s" % [", ".join(parts.slice(0, parts.size() - 1)), parts[parts.size() - 1]]


static func exchange_text(record: Dictionary) -> String:
	"""'got X for Y', or 'got X' / 'gave Y' when one side put up nothing - a
	gift reads as a gift, not as a trade "for nothing"."""
	var got: String = goods_text(record.get("got"), int(record.get("gold_got", 0)))
	var gave: String = goods_text(record.get("gave"), int(record.get("gold_gave", 0)))
	if got != "nothing" and gave != "nothing":
		return "got %s for %s" % [got, gave]
	if got != "nothing":
		return "got %s" % got
	if gave != "nothing":
		return "gave %s" % gave
	return "nothing changed hands"


static func history_line(record: Dictionary) -> String:
	"""One finished trade, short: who, and what came to you for what went."""
	var who: String = str(record.get("with_name", ""))
	if who == "":
		who = str(record.get("with", "?"))
	return "%s: %s" % [who, exchange_text(record)]


static func result_line(record: Dictionary) -> String:
	"""The sentence a finished trade gets in the message box and the history
	tooltip - from YOUR side, which is how the server words the record."""
	var exchange: String = exchange_text(record)
	var line: String = "Trade with %s complete: %s." % [str(record.get("with", "?")),
		exchange if exchange == "nothing changed hands" else "you " + exchange]
	var tax: int = int(record.get("tax", 0))
	if tax > 0:
		line += " The kingdom took %s." % GameConstants.gold_text(tax)
	return line


# =============================================================================
# DRAWING AN OPEN TRADE
# =============================================================================

func _render(trade: Dictionary, render_our_side: bool) -> void:
	var mine: String = Api.username
	var side_a: Dictionary = trade.get("a", {}) if trade.get("a", {}) is Dictionary else {}
	var side_b: Dictionary = trade.get("b", {}) if trade.get("b", {}) is Dictionary else {}
	var new_trade: bool = str(trade.get("trade_id", "")) != _watched_trade_id
	_my_side = "a" if str(side_a.get("username", "")) == mine else "b"
	_watched_trade_id = str(trade.get("trade_id", ""))
	_revision = int(trade.get("revision", -1))

	var us: Dictionary = side_a if _my_side == "a" else side_b
	var them: Dictionary = side_b if _my_side == "a" else side_a

	# A DIFFERENT TRADE IS A FRESH LOOK, including at our own column - a window
	# reopened on a new trade must not keep the quantity boxes of the last one.
	if new_trade:
		_their_signature = ""
		render_our_side = true

	start_box.visible = false
	trade_box.visible = true
	header_label.text = "Trade"
	_render_with_row(them)

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

	summary_label.text = summary_text(us, them)
	_update_buttons(us, them)

	# A NEW TRADE ON SCREEN BRINGS THE BAG, and stands beside it. Only on a
	# new one: once it is up the player may move either window.
	if new_trade:
		_bring_the_bag.call_deferred()


func _render_with_row(them: Dictionary) -> void:
	"""Who this trade is with: a presence dot, their character in their colour
	with their rank, their account and level."""
	_clear(with_row)
	var online: bool = bool(them.get("online", true))
	var dot: TextureRect = Marks.make("online" if online else "offline",
		COLOUR_ONLINE if online else COLOUR_OFFLINE, "online" if online else "offline")
	dot.name = "presence"
	with_row.add_child(dot)

	var caption := Label.new()
	caption.text = "Trading with"
	caption.add_theme_color_override("font_color", COLOUR_HINT)
	caption.add_theme_font_size_override("font_size", 13)
	with_row.add_child(caption)

	var shown: String = str(them.get("name", ""))
	if shown == "":
		shown = str(them.get("username", "?"))
	NameTag.add_to(with_row, shown, str(them.get("role", "player")), them.get("name_hue"), 14)

	var detail := Label.new()
	detail.name = "detail"
	detail.text = "(%s) · lv %d" % [str(them.get("username", "?")), int(them.get("level", 1))]
	detail.add_theme_color_override("font_color", COLOUR_HINT)
	detail.add_theme_font_size_override("font_size", 12)
	with_row.add_child(detail)


func _render_our_side(us: Dictionary) -> void:
	_loading_our_side = true

	# WHAT THE SERVER HAS US OFFERING, so reopening the panel shows the offer
	# that is actually standing rather than an empty one - and an offer the
	# server refused is put back to what it holds.
	_offer.clear()
	for entry in (us.get("items", []) if us.get("items", []) is Array else []):
		if entry is Dictionary and int(entry.get("quantity", 0)) > 0:
			_offer[str(entry.get("item_id", ""))] = int(entry.get("quantity", 0))
	_draw_offer()

	var purse: int = _current_gold()
	gold_spin.max_value = float(purse)
	gold_spin.value = float(min(int(us.get("gold", 0)), purse))
	gold_spin.tooltip_text = "You carry %d gold" % purse

	_loading_our_side = false
	_update_our_summary(us)


func _draw_offer() -> void:
	"""Our column from `_offer`: a row for each thing we are giving, or the
	words that say how to give something."""
	var was_loading: bool = _loading_our_side
	_loading_our_side = true
	_clear(you_list)
	var held: Dictionary = _held_items()
	if _offer.is_empty():
		you_list.add_child(_hint_label(EMPTY_SIDE_TOUCH if TouchControls.active else EMPTY_SIDE))
	for item_id in _offer:
		you_list.add_child(_build_our_row(item_id, int(held.get(item_id, 0)), int(_offer[item_id])))
	_loading_our_side = was_loading


func _update_our_summary(us: Dictionary) -> void:
	var agreed: bool = bool(us.get("confirmed", false))
	you_header.text = column_header("You give", agreed)
	you_header.add_theme_color_override("font_color", COLOUR_AGREED if agreed else Color(0.6, 0.9, 0.7))
	you_worth.text = worth_text(us.get("offering_value"))


func _render_their_side(them: Dictionary) -> void:
	var signature: String = offer_signature(them)
	var changed: bool = _their_signature != "" and signature != _their_signature
	_their_signature = signature

	_clear(them_list)
	var agreed: bool = bool(them.get("confirmed", false))
	them_header.text = column_header("You get", agreed)
	them_header.add_theme_color_override("font_color", COLOUR_AGREED if agreed else Color(0.95, 0.85, 0.6))

	var items: Array = them.get("items", []) if them.get("items", []) is Array else []
	if items.is_empty():
		them_list.add_child(_hint_label("Nothing offered yet."))
	else:
		for entry in items:
			if entry is Dictionary:
				them_list.add_child(_build_their_row(entry))

	them_gold.text = "Gold %s" % GameConstants.commas(int(them.get("gold", 0)))
	them_worth.text = worth_text(them.get("offering_value"))

	# A CHANGE IS POINTED OUT, NOT SLIPPED IN. The server has already withdrawn
	# any acceptance; this is the half that tells the person looking why, and
	# makes them look again before they press anything.
	if changed:
		_set_notice("%s changed their offer. Check it before you accept."
			% _display_name(them), true)
		_flash(them_panel)


static func column_header(words: String, agreed: bool) -> String:
	return "%s  · accepted" % words if agreed else words


static func offer_signature(side: Dictionary) -> String:
	"""What a side is offering, as comparable text: items in the server's order,
	then gold. Two answers with the same signature are the same offer."""
	var parts: PackedStringArray = []
	for entry in (side.get("items", []) if side.get("items", []) is Array else []):
		if entry is Dictionary:
			parts.append("%s:%d" % [str(entry.get("item_id", "")), int(entry.get("quantity", 0))])
	parts.append("gold:%d" % int(side.get("gold", 0)))
	return ",".join(parts)


static func worth_text(value: Variant) -> String:
	# NULL MEANS THE SERVER CANNOT VALUE IT - an item it does not know - which
	# is a refusal at execution, not a zero. Saying "worth 0" would be a lie
	# about exactly the case that matters.
	if value == null:
		return "contains something the server cannot value"
	return "worth %s" % GameConstants.gold_text(int(value))


static func summary_text(us: Dictionary, them: Dictionary) -> String:
	"""The line above the buttons: what you are about to receive, and the cut.

	THE TAX IS THE SERVER'S QUOTE for this side - charged on what you RECEIVE,
	after the swap, so the gold you are handed can pay it."""
	var tax = us.get("tax")
	var receiving = them.get("offering_value")
	if tax == null or receiving == null:
		return "This trade contains an item the server does not know, and it cannot go through."
	if int(receiving) <= 0:
		return "You receive nothing yet."
	if int(tax) <= 0:
		return "You receive %s gold's worth. No kingdom cut." % GameConstants.commas(int(receiving))
	return "You receive %s gold's worth. The kingdom takes %s from you." % [
		GameConstants.commas(int(receiving)), GameConstants.gold_text(int(tax))]


static func accept_state(us: Dictionary, them: Dictionary) -> Dictionary:
	"""{text, disabled, colour} for the Accept button. Named and static so the
	four states can be checked without a window."""
	var who: String = str(them.get("name", ""))
	if who == "":
		who = str(them.get("username", "them"))
	if bool(us.get("confirmed", false)):
		return {"text": "Waiting for %s…" % who, "disabled": true, "colour": COLOUR_HINT}
	if not bool(them.get("online", true)):
		# ACCEPTING IS HARMLESS BUT POINTLESS - nobody is there to accept back -
		# and a lit button invites the wait. Cancel stays live.
		return {"text": "%s is offline" % who, "disabled": true, "colour": COLOUR_OFFLINE}
	if bool(them.get("confirmed", false)):
		return {"text": "Accept (%s has)" % who, "disabled": false, "colour": COLOUR_AGREED}
	return {"text": "Accept", "disabled": false, "colour": Color(0.95, 0.9, 0.8)}


static func cancel_text(my_side: String, us: Dictionary) -> String:
	# SIDE B WAS ASKED. Until they have agreed to anything, turning it down is
	# a decline, and the button should say the word they are thinking.
	if my_side == "b" and not bool(us.get("confirmed", false)):
		return "Decline"
	return "Cancel trade"


func _update_buttons(us: Dictionary, them: Dictionary) -> void:
	var state: Dictionary = accept_state(us, them)
	confirm_button.text = str(state["text"])
	confirm_button.disabled = bool(state["disabled"])
	confirm_button.add_theme_color_override("font_color", state["colour"])
	cancel_button.text = cancel_text(_my_side, us)

	if not bool(them.get("online", true)):
		_set_notice("%s has gone offline. The trade cannot finish until they are back."
			% _display_name(them), true)
	elif bool(us.get("confirmed", false)) and not bool(them.get("confirmed", false)):
		_set_notice("You have accepted. Waiting for %s." % _display_name(them), false)


static func _display_name(side: Dictionary) -> String:
	var shown: String = str(side.get("name", ""))
	return shown if shown != "" else str(side.get("username", "They"))


# =============================================================================
# OUR OFFER
# =============================================================================

func _held_items() -> Dictionary:
	# item_id -> total held, merged across cells, because the offer is a
	# quantity per item and the server merges it the same way. The hotbar's keys
	# are cells of the same container and count too - the server takes from the
	# bag before the keys, so offering five of your ten potions leaves key 1
	# alone.
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
	"""One thing we are giving: the item, a number box when there can be more
	than one of it, and an x that takes it off."""
	var row := _item_row(item_id)
	var most: int = maxi(held, offered)
	# A STACK HAS - AND +, not a number box: a box wide enough for its arrows
	# left the name three letters, and a thumb hits a button.
	if most > 1:
		var less: Button = _small_button("less", "-", "One fewer")
		less.disabled = offered <= 1
		less.pressed.connect(_step_quantity.bind(item_id, -1))
		row.add_child(less)
	var count := Label.new()
	count.name = "quantity"
	count.text = "x%d" % offered
	count.tooltip_text = "You have %d" % held
	count.mouse_filter = Control.MOUSE_FILTER_PASS
	count.add_theme_font_size_override("font_size", ROW_FONT_SIZE + 1)
	count.add_theme_color_override("font_color", COLOUR_GOLD)
	row.add_child(count)
	if most > 1:
		var more: Button = _small_button("more", "+", "One more")
		more.disabled = offered >= held
		more.pressed.connect(_step_quantity.bind(item_id, 1))
		row.add_child(more)
	var off: Button = _small_button("remove", "×", "Take it off the trade")
	off.pressed.connect(remove_from_offer.bind(item_id))
	row.add_child(off)
	return row


func _small_button(id: String, text: String, tip: String) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(22, 22)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.tooltip_text = tip
	return button


func _build_their_row(entry: Dictionary) -> Control:
	var item_id: String = str(entry.get("item_id", ""))
	var row := _item_row(item_id)

	var qty := Label.new()
	qty.name = "quantity"
	qty.text = "x%d" % int(entry.get("quantity", 0))
	qty.add_theme_font_size_override("font_size", ROW_FONT_SIZE + 1)
	qty.add_theme_color_override("font_color", COLOUR_GOLD)
	row.add_child(qty)
	return row


func _item_row(item_id: String) -> HBoxContainer:
	"""Icon, then the name over its value. Both columns start the same way so
	the two sides of a trade read as one table."""
	var data: ItemData = ItemRegistry.get_item(item_id)

	var row := HBoxContainer.new()
	row.name = "item_%s" % item_id
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.tooltip_text = item_tooltip(item_id)

	# THE ICON'S SPACE IS KEPT EVEN WITHOUT AN ICON, so names line up down the
	# column. EXPAND_IGNORE_SIZE or custom_minimum_size is only a floor and the
	# art sets the real width - the trap nametag.gd's crown notes.
	var icon := TextureRect.new()
	icon.name = "icon"
	icon.custom_minimum_size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if data != null and data.icon != null:
		icon.texture = data.icon
		icon.modulate = data.icon_tint
	row.add_child(icon)

	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", -2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)

	var label := Label.new()
	label.name = "name"
	label.text = item_name(item_id)
	label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	# THE TWO COLUMNS ARE EVEN (0.93.0): a long name gives way with "…" rather
	# than widening its column; the row's tooltip has it whole. Both labels are
	# in a column that expands and has the row to itself - the rule under "A
	# Label that shares a row gives way" in CLAUDE.md.
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	words.add_child(label)

	var hint := Label.new()
	hint.name = "value"
	hint.text = quality_hint(data) + value_hint(data)
	hint.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	hint.add_theme_color_override("font_color", COLOUR_HINT)
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	words.add_child(hint)
	return row


static func value_hint(data: ItemData) -> String:
	# "EACH" ONLY WHERE THERE CAN BE MORE THAN ONE. A companion or a sword is
	# one of a kind in a cell, and "16,000 gold each" reads as if it were not.
	if data == null or data.value <= 0:
		return ""
	if data.stackable:
		return "%s each" % GameConstants.gold_text(data.value)
	return "worth %s" % GameConstants.gold_text(data.value)


static func quality_hint(data: ItemData) -> String:
	# "Quality 104%  ·  " in front of a rolled piece's worth, "" for anything
	# else. Two rolls of one piece are two rows with one name, and the roll is
	# the whole difference between them - so it is on the row, not only in the
	# tooltip. A Perfect one says so in its name already.
	if data == null or not data.is_rolled():
		return ""
	return "Quality %d%%  ·  " % data.quality_percent()


static func item_tooltip(item_id: String) -> String:
	var data: ItemData = ItemRegistry.get_item(item_id)
	if data == null:
		return item_id
	var lines: PackedStringArray = [data.display_name]
	if data.description != "":
		lines.append(data.description)
	# WHAT IT DOES, rolled numbers and all, because a trade is where a roll
	# changes hands and the other player cannot hover your bag.
	var facts: String = ItemTooltip.stats_and_needs(data)
	if facts != "":
		lines.append(facts)
	var hint: String = value_hint(data)
	if hint != "":
		lines.append(hint[0].to_upper() + hint.substr(1))
	return "\n".join(lines)


func _collect_offer() -> Array:
	var items: Array = []
	for item_id in _offer:
		if int(_offer[item_id]) > 0:
			items.append({"item_id": str(item_id), "quantity": int(_offer[item_id])})
	return items


# =============================================================================
# GIVING FROM THE BAG
# =============================================================================

# What we are giving, item id -> how many, in the order it went on. The rows
# are drawn from it and the offer is sent from it.
var _offer: Dictionary = {}

const EMPTY_SIDE := "Double-click an item in your bag, or drag it here, to give it."
const EMPTY_SIDE_TOUCH := "Hold an item in your bag to give it."


func trading() -> bool:
	"""A trade is open and on screen - the only time the bag gives to it."""
	return visible and trade_box.visible and _my_side != ""


func add_from_bag(item_id: String, quantity: int) -> void:
	"""Put `quantity` more of `item_id` on our side, up to what we hold."""
	if not trading() or item_id == "" or quantity <= 0:
		return
	var held: int = int(_held_items().get(item_id, 0))
	if held <= 0:
		return
	var now: int = mini(held, int(_offer.get(item_id, 0)) + quantity)
	if now == int(_offer.get(item_id, 0)):
		_set_notice("All your %s is on the trade already." % item_name(item_id), false)
		return
	_offer[item_id] = now
	_draw_offer()
	Audio.play("ui_click")
	await _push_offer()


func remove_from_offer(item_id: String) -> void:
	if not _offer.has(item_id):
		return
	_offer.erase(item_id)
	_draw_offer()
	await _push_offer()


func _step_quantity(item_id: String, by: int) -> void:
	if not trading() or not _offer.has(item_id):
		return
	var held: int = int(_held_items().get(item_id, 0))
	var now: int = clampi(int(_offer[item_id]) + by, 1, maxi(1, held))
	if now == int(_offer[item_id]):
		return
	_offer[item_id] = now
	_draw_offer()
	await _push_offer()


# THE BAG, WIRED ONLY WHILE A TRADE IS ON SCREEN - the bank's rule
# (bankinventory.gd, _wire_carry_container()): a double-click in the bag
# means "give it" here and must go back to meaning nothing the moment the trade
# is gone. A finger held is that double-click, for exactly as long. If the
# bank already holds the bag (its window is open) the trade leaves it alone.
var _bag: Node = null


func _wire_bag(on: bool) -> void:
	var carry: Node = _player_inventory_container() if on else _bag
	if on and carry == _bag:
		return
	if _bag != null and is_instance_valid(_bag):
		if _bag.slot_double_clicked.is_connected(_on_bag_double_clicked):
			_bag.slot_double_clicked.disconnect(_on_bag_double_clicked)
		_bag.set("held_is_double_click", false)
	_bag = null
	if not on or carry == null or not carry.has_signal("slot_double_clicked"):
		return
	if carry.get("held_is_double_click") == true:
		return
	_bag = carry
	_bag.set("held_is_double_click", true)
	_bag.slot_double_clicked.connect(_on_bag_double_clicked)


func _on_bag_double_clicked(slot: Node) -> void:
	if slot == null or not trading() or slot.call("is_empty"):
		return
	var stack: Variant = slot.get("stack")
	if stack == null or stack.data == null:
		return
	await add_from_bag(str(stack.data.item_id), int(stack.quantity))


func _can_drop_offer(_at: Vector2, data: Variant) -> bool:
	"""A cell of the bag or a hotbar key dragged onto our side. Not the bank's
	or a loot bag's: those are not ours to give."""
	if not trading() or not (data is Dictionary) or not data.has("stack"):
		return false
	return not (str(data.get("source_type", "")) in ["bank", "lootbag"])


func _drop_offer(_at: Vector2, data: Variant) -> void:
	var stack: Variant = data.get("stack")
	if stack == null or stack.data == null:
		return
	await add_from_bag(str(stack.data.item_id), int(stack.quantity))


# =============================================================================
# BESIDE THE BAG
# =============================================================================

const DOCK_GAP := 8.0


static func docked_at(mine: Vector2, bag: Rect2, screen: Vector2) -> Vector2:
	"""Where the window goes beside the bag: to its left if it fits, else to
	its right, else as near as the screen allows - level with the bag's top."""
	var x: float = bag.position.x - DOCK_GAP - mine.x
	if x < 0.0:
		x = bag.end.x + DOCK_GAP
		if x + mine.x > screen.x:
			x = screen.x - mine.x
	x = clampf(x, 0.0, maxf(0.0, screen.x - mine.x))
	var y: float = clampf(bag.position.y, 0.0, maxf(0.0, screen.y - mine.y))
	return Vector2(x, y).floor()


func _bring_the_bag() -> void:
	"""Open the bag and stand beside it: a trade is made from the bag."""
	if bag_override != null:
		_wire_bag(true)
		return
	var hud: Node = get_tree().get_first_node_in_group("hud") if is_inside_tree() else null
	if hud == null or not hud.has_method("show_inventory"):
		return
	hud.call("show_inventory")
	await get_tree().process_frame
	if not is_instance_valid(self) or not is_inside_tree() or not trading():
		return
	_wire_bag(true)
	var bag: Control = hud.get("inventory_screen") as Control
	if bag == null or not bag.is_visible_in_tree():
		return
	position = docked_at(size * scale, bag.get_global_rect(), get_viewport_rect().size)


func _on_offer_edited(_value: float) -> void:
	if _loading_our_side or not visible or _my_side == "":
		return
	await _push_offer()


# AN EDIT THAT COULD NOT GO YET (0.56.0). A box changed while a poll or the
# last push was out was dropped - the box said 1, the server still had 9, and
# Accept traded 9. It is sent the moment the window is free instead.
var _offer_dirty: bool = false


func _push_offer() -> void:
	if _busy:
		_offer_dirty = true
		return
	_busy = true
	_offer_dirty = false
	var res: Dictionary = await Api.post("/api/trade/update", {
		"items": _collect_offer(),
		"gold": int(gold_spin.value),
	}, REQUEST_TIMEOUT)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_busy = false

	if _offer_dirty:
		await _push_offer()
		return
	if not res.get("ok", false):
		_set_notice(_refusal_text(res, "The kingdom would not record that offer."), true)
		# THE BOXES SAY WHAT THE SERVER HOLDS, not the value it refused (0.56.0).
		_poll.call_deferred(true)
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
	# NO SLOT. A typed name means "that person", and the server works out which
	# character they are playing. This used to send 0 - their first character,
	# whoever they were actually playing.
	await _send_offer(who, -1)


func offer_to(player: Node, who: String) -> void:
	"""Open the window on an offer to `who` - from the Players window's menu.
	The same request as typing their name and pressing Offer, so the server
	works out which character they are playing (no slot)."""
	who = who.strip_edges()
	if who == "":
		return
	if not visible:
		await open_panel(player)
		if not is_instance_valid(self) or not is_inside_tree():
			return
	username_edit.text = who
	await _send_offer(who, -1)


func _offer_body(who: String, to_slot: int) -> Dictionary:
	var body := {"slot": CharacterData.active_character_index, "username": who}
	# A slot from the nearby list is the one the server reported them playing,
	# and sending it back lets the server refuse if they have switched since.
	if to_slot >= 0:
		body["to_slot"] = to_slot
	return body


func _send_offer(who: String, to_slot: int) -> void:
	if _busy:
		return
	_busy = true
	var res: Dictionary = await Api.post("/api/trade/offer", _offer_body(who, to_slot), REQUEST_TIMEOUT)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_busy = false

	if not res.get("ok", false):
		_set_notice(_refusal_text(res, "Could not open a trade with %s." % who), true)
		return

	var trade: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	if not trade.is_empty():
		_render(trade, true)
	_set_notice("Trade opened. %s has been asked." % who, false)


func _confirm_body() -> Dictionary:
	# THE REVISION THIS WINDOW DREW. See the header: this is what makes Accept
	# mean the offer on the screen.
	return {"revision": _revision}


func _on_confirm_pressed() -> void:
	# ACCEPT MEANS WHAT YOU SAW, YOUR SIDE INCLUDED (0.56.0): an edit still
	# waiting to go is sent first, and the window waits for a poll in flight
	# rather than dropping the press.
	var until: int = Time.get_ticks_msec() + int(REQUEST_TIMEOUT * 1000.0) + 500
	while _busy and is_inside_tree() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	if not is_instance_valid(self) or not is_inside_tree() or _busy:
		return
	if _offer_dirty:
		await _push_offer()
		if not is_instance_valid(self) or not is_inside_tree() or _busy:
			return
	_busy = true
	var acting: Node = _player if is_instance_valid(_player) else null
	var res: Dictionary = await Api.post("/api/trade/confirm", _confirm_body(), REQUEST_TIMEOUT)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_busy = false
	_apply_confirm(res, acting)


func _apply_confirm(res: Dictionary, acting: Node) -> void:
	"""The answer to Accept, onto the window. Split out so the suite can hand it
	each of the answers the server gives."""
	if not res.get("ok", false):
		var refusal: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
		# THE OFFER CHANGED UNDER THE BUTTON. The refusal carries the offer as it
		# now stands, so it is drawn at once - with the change pointed out -
		# rather than left for the next poll to reveal.
		if int(res.get("status", 0)) == 409 and refusal.get("trade") is Dictionary:
			_render(refusal["trade"], false)
			var them: Dictionary = refusal["trade"].get("b" if _my_side == "a" else "a", {})
			_set_notice("%s changed the offer before your accept arrived. Look again, then accept."
				% _display_name(them if them is Dictionary else {}), true)
			_flash(them_panel)
			return
		# A REFUSAL IS NOT A CRASH AND NOT A LOSS. The server rolls the whole
		# attempt back and clears both acceptances, so the trade is still open
		# and still exactly as it was - see _trade_refuse(). Saying why and
		# re-reading is the right response.
		_set_notice(_refusal_text(res, "The trade did not go through."), true)
		_poll(true)
		return

	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	if str(data.get("state", "")) == "done":
		_apply_result(data, acting)
	elif not data.is_empty():
		# Only our half landed; the other side has not accepted yet.
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
	_watched_trade_id = ""
	_show_start()
	_set_notice("Trade called off.", false)


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
		_write_gold(int(ours["gold"]), acting)

	var cells: Array = ours.get("inventory", []) if ours.get("inventory", []) is Array else []
	if not cells.is_empty():
		var container: Node = _player_inventory_container()
		if container != null:
			container.load_server_array(cells)
		else:
			push_warning("TradePanel: player inventory not found — the server has the items, this screen does not")

	Audio.play("coin")

	# NO TOAST HERE. The server flags this character for a re-read as well
	# (in case this very response had been lost), the window's next poll picks
	# that up, and the HUD announces it in the same words the other side sees.
	_watched_trade_id = ""
	_show_start()
	_set_notice("Trade complete. The kingdom took %s in total."
		% GameConstants.gold_text(int(data.get("kingdom_take", 0))), false)


# =============================================================================
# PLAYER AND INVENTORY
# =============================================================================

# The suite's bag: a grid of its own in place of the HUD's.
var bag_override: Node = null


func _player_inventory_container() -> Node:
	# Reached through the HUD rather than held as a reference: the inventory
	# screen is lazily created and freed on logout, so a cached node here would
	# dangle the first time someone logs out and back in.
	if bag_override != null and is_instance_valid(bag_override):
		return bag_override
	if not is_inside_tree():
		return null
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


func _write_gold(amount: int, acting: Node = null) -> void:
	var player: Node = acting if is_instance_valid(acting) else (_player if is_instance_valid(_player) else null)
	if player == null:
		return
	if player.has_method("set_gold"):
		player.set_gold(amount)
	elif "gold" in player:
		player.gold = amount


# =============================================================================
# MESSAGES
# =============================================================================

func _clear(list: Container) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()


func _hint_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	label.add_theme_color_override("font_color", COLOUR_HINT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _flash(panel: Control) -> void:
	# A SHORT PULSE on the column that changed - enough to pull the eye, not
	# enough to be mistaken for a button.
	if panel == null or not is_inside_tree():
		return
	panel.modulate = Color(1.35, 1.2, 0.85)
	var tween := create_tween()
	tween.tween_property(panel, "modulate", Color.WHITE, 0.9)


func _set_notice(message: String, is_error: bool) -> void:
	notice_label.text = message
	notice_label.add_theme_color_override("font_color", COLOUR_WARN if is_error else COLOUR_HINT)


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
