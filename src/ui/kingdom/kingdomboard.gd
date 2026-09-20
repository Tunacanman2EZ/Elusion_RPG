# kingdomboard.gd — the Kingdom Tax board.
#
# WHAT IT IS FOR. Every trade and every vendor purchase destroys gold, and gold
# destroyed is invisible by nature: the player sees their purse go down and
# nothing anywhere says where it went or that it mattered. This panel is the
# answer to that — the total the realm has taken, and the player's own line in
# it. A sink nobody can see is a tax; a sink with a scoreboard is a contribution.
#
# READS, NEVER WRITES. There is no endpoint here that changes anything, and
# there should not be. The number on screen is a sum of gold_ledger rows the
# server computes on request — see /api/economy/kingdom, which is explicit that
# nothing counts into a column, because a running total is a second place the
# truth lives and the first disagreement is unresolvable.
extends Control


const REQUEST_TIMEOUT := 6.0

# How often the board re-reads itself WHILE OPEN. Slow on purpose: this is a
# leaderboard, not a health bar, and the figure moves when somebody somewhere
# completes a trade. Polling it hard would put every client on a timer against a
# query that sums a growing table, to make a number that changes by the minute
# feel like it changes by the second.
#
# ONLY WHILE VISIBLE. _process() returns immediately when the panel is closed,
# so a player who never opens this costs the server nothing.
const AUTO_REFRESH_SECONDS := 30.0

# THE LEDGER'S REASONS, IN THE PLAYER'S WORDS. The server sends database
# strings — 'kingdom_tax', 'shop_buy' — and a board that printed those would be
# showing the player the shape of a table rather than what happened to their
# gold.
#
# AN UNKNOWN REASON IS RENDERED, NOT DROPPED. A new sink added later shows up as
# a readable version of its own id, which looks unfinished and is meant to: the
# alternative is a line silently missing from a breakdown that then does not add
# up to the total printed above it.
const REASON_LABELS := {
	"kingdom_tax": "trade tax",
	"shop_buy": "spent with merchants",
	# The third sink, and the one with a story: gold burned to buy a character
	# out of a death. Named for what the player did rather than for the
	# endpoint that did it.
	"revive": "paid to cheat death",
}

# The three colours this board adds on top of the theme, named rather than
# repeated at each of the six places they are used.
#
# THE FIRST TWO ARE THE HOUSE VALUES, copied from inventory.tscn and
# bankinventory.tscn rather than chosen again here: every panel in the game
# writes muted text as (0.7, 0.66, 0.6) and a gold figure as (1, 0.9, 0.5), and
# a panel that picks its own is the one that looks wrong. The loot bag was
# exactly that panel once.
const RANK_COLOUR := Color(0.7, 0.66, 0.6)
const GOLD_COLOUR := Color(1, 0.9, 0.5)

# The one new colour, for the player's own row and their own line. Green because
# every other accent on this board is gold, and "which of these is me" has to be
# answerable without reading any of the names.
const YOU_COLOUR := Color(0.6, 0.9, 0.7)

# Lusions, which are not gold and should not look like it. Violet because it is
# the one hue nothing else on this board uses, so the second column reads as a
# different KIND of number rather than a second pile of the same one.
const LUSION_COLOUR := Color(0.78, 0.62, 1.0)


@onready var close_button: Button = %closebutton
@onready var total_label: Label = %totallabel
@onready var breakdown_label: Label = %breakdownlabel
@onready var you_label: Label = %youlabel
@onready var board_list: VBoxContainer = %boardlist
@onready var notice_label: Label = %noticelabel
@onready var refresh_button: Button = %refreshbutton


# The username the server said is ours, so the board can mark our own row. Taken
# from the RESPONSE rather than from Api, so the highlighted row is always the
# account the figures were computed for.
var _me: String = ""

# ONE REQUEST AT A TIME. The refresh button and the auto-refresh can both fire,
# and two reads in flight would render whichever landed last — which is not
# necessarily the newer one.
var _busy: bool = false

var _seconds_until_refresh: float = 0.0


func _ready() -> void:
	close_button.pressed.connect(close_board)
	refresh_button.pressed.connect(_on_refresh_pressed)
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_seconds_until_refresh -= delta
	if _seconds_until_refresh <= 0.0:
		_seconds_until_refresh = AUTO_REFRESH_SECONDS
		_load()


# =============================================================================
# OPEN / CLOSE
# =============================================================================

func open_board() -> void:
	visible = true
	_seconds_until_refresh = AUTO_REFRESH_SECONDS
	await _load()


func close_board() -> void:
	visible = false
	_clear_rows()


func toggle_board() -> void:
	if visible:
		close_board()
	else:
		await open_board()


# =============================================================================
# LOADING
# =============================================================================

func _on_refresh_pressed() -> void:
	_seconds_until_refresh = AUTO_REFRESH_SECONDS
	await _load()


func _load() -> void:
	if _busy:
		return
	_busy = true
	_set_notice("Reading the ledgers…", false)

	var res: Dictionary = await Api.get_json("/api/economy/kingdom", REQUEST_TIMEOUT)

	# PAST AN AWAIT. Logout frees every panel and a ladder changes the scene,
	# either of which can happen while this request is in flight. Same guard and
	# same reason as shopinventory.gd's catalogue load.
	if not is_instance_valid(self) or not is_inside_tree():
		return

	_busy = false

	if not res.get("ok", false):
		_set_notice(_refusal_text(res), true)
		return

	_render(res.get("data", {}) if res.get("data", {}) is Dictionary else {})


func _render(data: Dictionary) -> void:
	_set_notice("", false)

	var total: int = int(data.get("total", 0))
	total_label.text = _compact(total)
	# The headline figure is the one most likely to outgrow its panel, and the
	# one people most want the real number for. Compact on the label, exact on
	# the hover.
	total_label.tooltip_text = _exact_tooltip(total, "gold")
	total_label.mouse_filter = Control.MOUSE_FILTER_STOP

	var you: Dictionary = data.get("you", {}) if data.get("you", {}) is Dictionary else {}
	_me = str(you.get("username", ""))

	breakdown_label.text = _breakdown_text(
		data.get("by_reason", {}) if data.get("by_reason", {}) is Dictionary else {},
		data.get("lusions_by_reason", {}) if data.get("lusions_by_reason", {}) is Dictionary else {},
		int(data.get("total_lusions", 0)),
		int(data.get("contributors", 0)))

	you_label.text = _your_line(you)
	you_label.add_theme_color_override("font_color",
		YOU_COLOUR if (int(you.get("contributed", 0)) > 0
			or int(you.get("lusions", 0)) > 0) else RANK_COLOUR)

	var top: Array = data.get("top", []) if data.get("top", []) is Array else []
	if top.is_empty():
		_clear_rows()
		_set_notice("Nobody has given anything yet.", false)
		return
	_render_rows(top)


func _breakdown_text(by_reason: Dictionary, lusions_by_reason: Dictionary,
		total_lusions: int, contributors: int) -> String:
	var parts := PackedStringArray()
	# `label`, not `name` — every Node has a `name` property, and a local by
	# that name shadows it for the rest of the block.
	for reason in by_reason:
		var label: String = REASON_LABELS.get(reason, String(reason).replace("_", " "))
		parts.append("%s %s" % [_compact(int(by_reason[reason])), label])

	var line: String = "  ·  ".join(parts)

	# LUSIONS ON THEIR OWN LINE. They belong in the breakdown - a revive paid in
	# lusions is a contribution - but folding them into the gold list would put
	# two units in one sentence and make the figures above stop adding up.
	if total_lusions > 0:
		var lusion_parts := PackedStringArray()
		for reason in lusions_by_reason:
			var label: String = REASON_LABELS.get(reason, String(reason).replace("_", " "))
			lusion_parts.append("%s %s" % [_compact(int(lusions_by_reason[reason])), label])
		line += "\nand %s lusions  (%s)" % [
			_compact(total_lusions), "  ·  ".join(lusion_parts)]

	if contributors > 0:
		line += "\nfrom %d %s" % [contributors, "subject" if contributors == 1 else "subjects"]
	return line


func _your_line(you: Dictionary) -> String:
	var given: int = int(you.get("contributed", 0))
	var lusions: int = int(you.get("lusions", 0))
	if given <= 0 and lusions <= 0:
		return "You have given the kingdom nothing yet."

	# BOTH CURRENCIES, ALWAYS, even the one sitting at zero.
	#
	# The first version listed only what you had actually given, which read
	# perfectly and taught the player the wrong thing: somebody who has only
	# ever spent gold never sees the word Lusions here and has no reason to
	# think a revive paid in them would count. Naming both is how the line says
	# what the board measures, rather than only what you happen to have done.
	#
	# YOUR OWN LINE PRINTS IN FULL, however large it gets. The compact form
	# exists so two hundred other people's figures fit in a column; there is
	# one of these and it is the number the player came to read.
	var line: String = "You have given %s gold and %s Lusions." % [
		_commas(given), _commas(lusions),
	]

	var rank_value = you.get("rank")
	if rank_value != null:
		line += "  —  rank %d" % int(rank_value)
	return line


# =============================================================================
# THE LIST
# =============================================================================
#
# REUSED, NOT REBUILT, and at two hundred rows that stopped being a nicety.
#
# The old render queue_free()d every row and made new ones. At ten rows nobody
# could tell. At two hundred it is a thousand nodes destroyed and a thousand
# created every thirty seconds for a panel that is usually just sitting open,
# and — worse than the cost — it threw away the scroll position, so a player
# reading rank 87 was yanked back to the top on every auto-refresh. A
# leaderboard you cannot stay still in is one you cannot read.
#
# So rows are built once and refilled in place, and only the DIFFERENCE in
# count is created or freed.

func _render_rows(top: Array) -> void:
	var scroll: ScrollContainer = board_list.get_parent() as ScrollContainer
	var offset: int = scroll.scroll_vertical if scroll != null else 0

	var existing: Array = board_list.get_children()

	# Trim the surplus first, so the loop below never indexes past the end.
	for index in range(existing.size() - 1, top.size() - 1, -1):
		var spare: Node = existing[index]
		board_list.remove_child(spare)
		spare.queue_free()

	for index in top.size():
		var entry = top[index]
		if not (entry is Dictionary):
			continue
		var row: HBoxContainer
		if index < existing.size():
			row = existing[index] as HBoxContainer
		else:
			row = _make_row()
			board_list.add_child(row)
		# THE SERVER'S RANK, not the row's position. They differ the moment two
		# players are tied — the board is 1, 1, 3 and the list is 1, 2, 3 — and
		# they would differ again if this list were ever a page rather than the
		# whole top. index + 1 is only the fallback for an older server.
		_fill_row(row, int(entry.get("rank", index + 1)), entry)

	# AFTER THE LAYOUT, not before it. The container has not resized yet at this
	# point, so ScrollContainer would clamp the value against the old content
	# height and land somewhere near the top. Deferred, it runs once the new
	# height is known.
	if scroll != null and offset > 0:
		_restore_scroll.call_deferred(scroll, offset)


func _restore_scroll(scroll: ScrollContainer, offset: int) -> void:
	if is_instance_valid(scroll):
		scroll.scroll_vertical = offset


func _make_row() -> HBoxContainer:
	"""One empty row: four labels that never change shape, only content.

	Everything here is layout and styling — nothing that depends on WHICH
	player this row is for, because that is _fill_row()'s job and the whole
	point of the split."""
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var rank_label := Label.new()
	rank_label.name = "rank"
	# 34, not 28: "200." is a character wider than "10." and the column was
	# sized when ten was the whole board.
	rank_label.custom_minimum_size = Vector2(34, 0)
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rank_label.add_theme_font_size_override("font_size", 12)
	rank_label.add_theme_color_override("font_color", RANK_COLOUR)
	row.add_child(rank_label)

	var name_label := Label.new()
	name_label.name = "who"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 12)
	# A long username must not push the figures off the right-hand edge, and a
	# board of two hundred will contain one.
	name_label.clip_text = true
	row.add_child(name_label)

	var given_label := Label.new()
	given_label.name = "gold"
	# A Label ignores the mouse by default, and a tooltip on a node that cannot
	# be hovered is a tooltip nobody will ever see.
	given_label.mouse_filter = Control.MOUSE_FILTER_STOP
	given_label.custom_minimum_size = Vector2(76, 0)
	given_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	given_label.add_theme_font_size_override("font_size", 12)
	given_label.add_theme_color_override("font_color", GOLD_COLOUR)
	row.add_child(given_label)

	# LUSIONS BESIDE GOLD, NOT ADDED TO IT. There is no exchange rate between
	# them, and inventing one would be this panel deciding what a lusion is
	# worth. Twenty lusions and twenty gold are different sacrifices.
	var lusions_label := Label.new()
	lusions_label.name = "lusions"
	lusions_label.mouse_filter = Control.MOUSE_FILTER_STOP
	lusions_label.custom_minimum_size = Vector2(56, 0)
	lusions_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lusions_label.add_theme_font_size_override("font_size", 12)
	row.add_child(lusions_label)

	return row


func _fill_row(row: HBoxContainer, rank: int, entry: Dictionary) -> void:
	var username: String = str(entry.get("username", "?"))
	var given: int = int(entry.get("contributed", 0))
	var lusions: int = int(entry.get("lusions", 0))
	var is_me: bool = username != "" and username == _me

	var rank_label: Label = row.get_node("rank")
	rank_label.text = "%d." % rank

	var name_label: Label = row.get_node("who")
	name_label.text = username
	# Your own row is tinted rather than marked with a symbol, so the list reads
	# the same length whether you are on it or not.
	#
	# SET BOTH WAYS ROUND, because a reused row may have been somebody else's a
	# moment ago — an override that is only ever added is an override that
	# never goes away, and the tint would creep down the board as ranks moved.
	if is_me:
		name_label.add_theme_color_override("font_color", YOU_COLOUR)
	else:
		name_label.remove_theme_color_override("font_color")

	var given_label: Label = row.get_node("gold")
	given_label.text = _compact(given)
	given_label.tooltip_text = _exact_tooltip(given, "gold")

	# A dash rather than a zero when someone has given none, because a column of
	# zeroes reads as a broken feature and a column of dashes reads as "not this
	# one".
	var lusions_label: Label = row.get_node("lusions")
	lusions_label.text = _compact(lusions) if lusions > 0 else "—"
	lusions_label.tooltip_text = _exact_tooltip(lusions, "lusions")
	lusions_label.add_theme_color_override("font_color",
		LUSION_COLOUR if lusions > 0 else RANK_COLOUR)


func _clear_rows() -> void:
	for child in board_list.get_children():
		child.queue_free()


# =============================================================================
# FORMATTING
# =============================================================================

# Where exact digits stop helping and start crowding. Below this the figure is
# printed in full; above it, three significant figures and a suffix.
#
# 100,000 rather than 1,000,000 because the row labels are 76px wide. "104,300"
# already overflows them and "1,381,947" is unreadable at a glance even when it
# fits - which is the actual problem, not the pixels.
const COMPACT_THRESHOLD := 100000

const COMPACT_SUFFIXES := ["", "K", "M", "B", "T"]


func _compact(amount: int) -> String:
	"""A figure short enough to read, with the exact one a hover away.

	THE ROUNDING IS A DISPLAY, NEVER THE RECORD. "1.38M" is 1,381,947 and the
	tooltip says so; the server holds the integer and the ledger sums the
	integer. This function exists so a board that has been running for five
	years still fits in its own panel, not to simplify the arithmetic.

	THREE SIGNIFICANT FIGURES, always - 1.38M, 13.8M, 138M - so the width of a
	column never changes by more than a character no matter how the total
	grows. That is the property a scoreboard needs; a number that is sometimes
	four characters and sometimes eleven makes every row jump."""
	var negative: bool = amount < 0
	var value: float = float(absi(amount))
	if value < COMPACT_THRESHOLD:
		return _commas(amount)

	var tier: int = 0
	# 999.5 rather than 1000, so 999,999,999 reads "1.00B" rather than "1000M".
	# Rounding up into a tier it has not quite reached is the honest answer:
	# three significant figures of 999,999,999 IS 1.00 billion.
	while value >= 999.5 and tier < COMPACT_SUFFIXES.size() - 1:
		value /= 1000.0
		tier += 1

	# THE THRESHOLDS ARE THE ROUNDED VALUE, NOT THE RAW ONE. At 99.95 the
	# one-decimal form prints "100.0", which is four significant figures and a
	# character wider than every other row. Testing against 99.95 and 9.995
	# hands those to the branch above, which is what three significant figures
	# actually means.
	var text: String
	if value >= 99.95:
		text = "%d" % roundi(value)
	elif value >= 9.995:
		text = "%.1f" % value
	else:
		text = "%.2f" % value
	return ("-" if negative else "") + text + COMPACT_SUFFIXES[tier]


func _exact_tooltip(amount: int, noun: String) -> String:
	"""The number the display rounded, spelled out. Only worth attaching when
	the display actually rounded - a tooltip repeating "1,204" under a label
	reading "1,204" is noise that teaches people to ignore tooltips."""
	if absi(amount) < COMPACT_THRESHOLD:
		return ""
	return "%s %s" % [_commas(amount), noun]


func _commas(amount: int) -> String:
	# A kingdom total is the one number in this game that gets genuinely large,
	# and "1381947" is unreadable at a glance in a way "1,381,947" is not. Built
	# by hand because String has no thousands separator and pulling in a format
	# helper for one call site is not worth the indirection.
	var digits: String = str(absi(amount))
	var out: String = ""
	var count: int = 0
	for index in range(digits.length() - 1, -1, -1):
		out = digits[index] + out
		count += 1
		if count % 3 == 0 and index > 0:
			out = "," + out
	return ("-" + out) if amount < 0 else out


func _set_notice(message: String, is_error: bool) -> void:
	notice_label.text = message
	notice_label.add_theme_color_override(
		"font_color",
		Color(1, 0.6, 0.5) if is_error else Color(0.7, 0.66, 0.6),
	)


func _refusal_text(res: Dictionary) -> String:
	# api.gd has already turned the response into a sentence — see
	# _describe_api_error(). Re-deriving it here is the mistake shopinventory.gd
	# made, where a 404 with an HTML body fell through to a message about the
	# network and sent the search in the wrong direction.
	var status: int = int(res.get("status", 0))
	var message: String = str(res.get("error", ""))
	if status == 0:
		return message if message != "" else "No connection to the server."
	if status == 404:
		push_warning("KingdomBoard: no /api/economy/kingdom route — is app.py current and restarted?")
		return "The server has no record of the kingdom's coffers."
	return message if message != "" else "Could not read the ledgers (HTTP %d)." % status
