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

# Deaths. Not a currency and not gold, so it gets a hue of its own - a muted
# rust, dark enough that a long column of them does not compete with the
# figures it sits beside. Nobody opens this panel to read the death column
# first.
const DEATH_COLOUR := Color(0.78, 0.45, 0.42)

# HOW LONG THIS PANEL MAY SPEND BUILDING ROWS IN ONE FRAME.
#
# THE MEASUREMENT THAT PUT THIS HERE. Building a full 200-row board in one go
# takes about 79ms. A frame at 30fps is 33.3ms, so the first time somebody
# opened the panel on a busy server the game dropped two or three frames -
# every time, reliably, on the one action that is supposed to be a menu opening.
# Refilling those same rows afterwards costs about 12ms, which is why they are
# pooled and reused rather than rebuilt; the pool just had to be paid for all
# at once on the way in.
#
# So the build is spread across frames instead. Rows appear over the next few
# frames rather than all at once, which nobody can see, and no single frame
# goes over.
#
# A TIME BUDGET RATHER THAN A ROW COUNT, because a row costs what the machine
# says it costs. Four milliseconds is about ten rows here and will be more on a
# better box and fewer on a worse one, and on all three it stays a fraction of
# a frame. A count tuned on one machine is a stutter on another, and this game
# is meant to run on whatever people have.
const ROW_BUILD_BUDGET_MS := 4.0

# The board the panel is trying to show, kept while the pool catches up to it.
# Empty when there is nothing outstanding.
var _rows_pending: Array = []

# How many rows of _rows_pending are already built AND filled.
#
# WITHOUT THIS THE CATCH-UP IS QUADRATIC, which the first version of it was.
# _render_rows() refills every row it walks past, so a slice that started from
# zero spent its whole budget refilling the rows the previous slices had just
# filled, and had nothing left to build with. A 200-row board took 153 frames
# to arrive - two and a half seconds of it visibly filling in - because each
# frame added about one row.
#
# Resuming from here means a slice only touches rows nobody has touched yet,
# so the whole board costs the same as building it in one go, just spread out.
var _rows_done: int = 0

# THE COLUMN WIDTHS, IN ONE PLACE. _make_row() used to carry these as four
# literals; a header row has to line up with the rows underneath it, and two
# hand-typed copies of 76 stay equal only until somebody edits one of them.
const COL_RANK := 34
const COL_GOLD := 76
const COL_LUSIONS := 56
const COL_DEATHS := 58
const COL_SEPARATION := 8

# The coin art the header marks its columns with. Preloaded rather than read
# from ItemRegistry: this is chrome, it never changes at runtime, and a header
# that silently loses its icons because an autoload was not ready yet is a
# worse trade than two more bytes in the scene.
const GOLD_ICON := preload("res://art/pack/currency/goldpile.png")
const LUSION_ICON := preload("res://art/pack/currency/lusions.png")


@onready var close_button: Button = %closebutton
@onready var total_label: Label = %totallabel
@onready var breakdown_label: Label = %breakdownlabel
# OPTIONAL BY CONSTRUCTION. The scene is edited in Godot, not here, so this
# panel has to work whether or not a %taxtotallabel has been added to it yet -
# a missing unique name in an @onready is a hard error that takes the entire
# board down, which is a bad trade for one line of text. _resolve_headline_label()
# builds one above the breakdown if the scene has not got one.
#
# tax_TOTAL_label, because _make_row() and _fill_row() each have a local
# `tax_label` for the per-row column and a member of that name would be
# shadowed inside the two functions most likely to reach for it.
@onready var headline_label: Label = _resolve_headline_label()
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
	# Once, here, rather than on every render: the header never changes and
	# rebuilding it each refresh would be a node churned thirty seconds apart
	# for no reason.
	_build_column_header()
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return

	# FINISH THE LIST BEFORE ANYTHING ELSE. A board part-built because the last
	# frame ran out of budget gets another slice here, and keeps getting one
	# until it is whole. Costs nothing on the overwhelming majority of frames,
	# where _rows_pending is empty.
	if not _rows_pending.is_empty():
		_render_rows(_rows_pending, _rows_done)

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

func _build_column_header() -> void:
	"""A row of icons over the three number columns, above the list.

	WHY THE COLUMNS NEEDED MARKING AT ALL. A row reads "Tunacan  2,902  20  —"
	and nothing anywhere says which figure is which. Gold, lusions and deaths
	are three different things and only two of them are currencies; the panel
	was asking the reader to infer that from colour alone.

	ICONS RATHER THAN WORDS, because the words do not fit. The fixed columns
	already eat 230 of about 316 usable pixels and the name gets what is left -
	"Lusions" as a header is wider than the column it would label. A 14px coin
	is unambiguous and costs nothing.

	THE DEATH COLUMN GETS A WORD, not an icon, and the asymmetry is the point:
	the first two columns are money and the third is not. Giving deaths a coin
	would put them in the same category as the gold beside them.

	BUILT HERE, NOT IN THE SCENE, so it reads its widths from the same four
	constants _make_row() does. A header in the .tscn would be four more magic
	numbers to keep in step, and they would drift the first time a column moved.
	"""
	var scroll: Node = board_list.get_parent()
	if scroll == null or scroll.get_parent() == null:
		return

	var header := HBoxContainer.new()
	header.name = "columnheader"
	header.add_theme_constant_override("separation", COL_SEPARATION)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Two spacers standing in for the rank and name columns, so the icons land
	# over the figures rather than over the names.
	var rank_gap := Control.new()
	rank_gap.custom_minimum_size = Vector2(COL_RANK, 0)
	header.add_child(rank_gap)

	var name_gap := Control.new()
	name_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_gap)

	header.add_child(_header_icon(GOLD_ICON, COL_GOLD, "Gold given to the kingdom"))
	header.add_child(_header_icon(LUSION_ICON, COL_LUSIONS, "Lusions given"))

	var death_head := Label.new()
	death_head.text = "deaths"
	death_head.custom_minimum_size = Vector2(COL_DEATHS, 0)
	death_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	death_head.add_theme_font_size_override("font_size", 10)
	death_head.add_theme_color_override("font_color", DEATH_COLOUR)
	death_head.tooltip_text = "How many times this player has died"
	death_head.mouse_filter = Control.MOUSE_FILTER_STOP
	header.add_child(death_head)

	var parent: Node = scroll.get_parent()
	parent.add_child(header)
	parent.move_child(header, scroll.get_index())


func _header_icon(art: Texture2D, width: int, tip: String) -> Control:
	"""One coin, right-aligned over its column.

	THE ICON SITS IN A FIXED-WIDTH BOX and is right-aligned inside it, because
	the figures under it are right-aligned too - an icon centred over a
	right-aligned column points at the wrong place as soon as the numbers get
	long enough to fill it.

	EXPAND_IGNORE_SIZE, like every other coin in this project: the art is 16x16
	and without it the TextureRect would demand its texture's size as a minimum
	and quietly widen the column it is supposed to be labelling."""
	var box := HBoxContainer.new()
	box.custom_minimum_size = Vector2(width, 0)
	box.alignment = BoxContainer.ALIGNMENT_END

	var frame := TextureRect.new()
	frame.texture = art
	frame.custom_minimum_size = Vector2(14, 14)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.tooltip_text = tip
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_child(frame)
	return box


func _resolve_headline_label() -> Label:
	"""The scene's own %headlinelabel if it has one, otherwise a label built to
	match the breakdown and slotted in beside it."""
	var existing: Node = get_node_or_null("%headlinelabel")
	if existing is Label:
		return existing as Label

	var made := Label.new()
	made.name = "headlinelabel"
	made.add_theme_font_size_override("font_size", 12)
	made.horizontal_alignment = breakdown_label.horizontal_alignment
	made.autowrap_mode = breakdown_label.autowrap_mode

	# Directly above the breakdown, which is where a reader looking for "what
	# has the tax taken" will already be looking.
	var parent: Node = breakdown_label.get_parent()
	if parent == null:
		add_child(made)
		return made
	parent.add_child(made)
	parent.move_child(made, breakdown_label.get_index())
	return made


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
	var total_taxed: int = int(data.get("total_taxed", 0))
	var total_deaths: int = int(data.get("total_deaths", 0))
	total_label.text = _compact(total)
	# The headline figure is the one most likely to outgrow its panel, and the
	# one people most want the real number for. Compact on the label, exact on
	# the hover.
	#
	# THE TAX SHARE RIDES ON THE SAME HOVER, because the two numbers only mean
	# anything next to each other: 400,000 gold destroyed is a big number until
	# you learn that 1,200 of it was the tax and the rest was people buying
	# potions.
	total_label.tooltip_text = _exact_tooltip(total, "gold")
	if total_taxed > 0:
		total_label.tooltip_text += "\n%s of it the trade tax" % _commas(total_taxed)
	if total_deaths > 0:
		total_label.tooltip_text += "\nand %s death%s along the way" % [
			_commas(total_deaths), "" if total_deaths == 1 else "s"]
	total_label.mouse_filter = Control.MOUSE_FILTER_STOP

	var you: Dictionary = data.get("you", {}) if data.get("you", {}) is Dictionary else {}
	_me = str(you.get("username", ""))

	breakdown_label.text = _breakdown_text(
		data.get("by_reason", {}) if data.get("by_reason", {}) is Dictionary else {},
		data.get("lusions_by_reason", {}) if data.get("lusions_by_reason", {}) is Dictionary else {},
		int(data.get("total_lusions", 0)),
		int(data.get("contributors", 0)))

	# THE TAX GETS ITS OWN LINE ABOVE THE BREAKDOWN. It was already inside
	# by_reason, which the breakdown renders as a run-on of every sink there is;
	# being in that sentence is not the same as being findable. The board's
	# whole claim is that the tax is a contribution rather than a deduction, and
	# a claim like that needs a number of its own.
	# THE LINE THAT USED TO CARRY THE TRADE TAX now carries the realm's deaths.
	# The tax total is still in the breakdown above, where it has always been;
	# what this line is for is a figure worth putting on its own, and "how many
	# times has this world killed somebody" is a better one than a sink total
	# nobody can act on.
	headline_label.text = ("%s death%s across the realm" % [_commas(total_deaths),
		"" if total_deaths == 1 else "s"]) \
		if total_deaths > 0 else "Nobody has died yet."
	headline_label.add_theme_color_override("font_color",
		DEATH_COLOUR if total_deaths > 0 else RANK_COLOUR)

	you_label.text = _your_line(you, int(data.get("contributors", 0)))
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


func _your_line(you: Dictionary, contributors: int = 0) -> String:
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
	# THREE SHORT LINES, BROKEN WHERE I CHOOSE, and that is the whole point of
	# the change.
	#
	# This was one long sentence with "  —  rank 1" glued to the end of it, in a
	# label with autowrap_mode 2 and about 300px to work with. The label broke
	# it wherever it ran out of room, which was between the word "rank" and the
	# number - so the panel read "...and 20 Lusions.  —  rank" and then a "1"
	# sitting alone and centred on the next line, looking like a bullet point
	# or a bug.
	#
	# A LABEL WILL ALWAYS BREAK SOMEWHERE. The fix is not to make the sentence
	# shorter and hope; it is to put the breaks in explicitly, so the only
	# wrapping left to chance happens INSIDE a clause rather than between a
	# noun and the number that gives it meaning.
	var lines := PackedStringArray()
	lines.append("You have given %s gold and %s Lusions." % [
		_commas(given), _commas(lusions),
	])

	# YOUR OWN DEATHS, only when there are some. "You have died 0 times" on the
	# line of somebody who has never died reads as a taunt rather than a fact.
	var deaths: int = int(you.get("deaths", 0))
	if deaths > 0:
		lines.append("You have died %s time%s." % [
			_commas(deaths), "" if deaths == 1 else "s"])

	# RANK LAST, ON ITS OWN LINE, WITH NON-BREAKING SPACES IN IT.
	#
	# The newline is what fixes the reported bug. The NBSPs are belt and braces
	# for the day somebody narrows this panel or a rank runs to four digits:
	# U+00A0 is a space the line breaker is not allowed to break at, so "Rank 1"
	# and "of 214" each stay whole whatever the width.
	#
	# "of N" ONLY WHEN THERE IS SOMEBODY ELSE. "Rank 1 of 1" is a true sentence
	# and a joyless one; on a server with one player it just says rank 1.
	var rank_value = you.get("rank")
	if rank_value != null:
		if contributors > 1:
			lines.append("Rank\u00A0%d of\u00A0%d." % [int(rank_value), contributors])
		else:
			lines.append("Rank\u00A0%d." % int(rank_value))
	return "\n".join(lines)


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

func _render_rows(top: Array, resume_from: int = 0) -> void:
	"""Draw the board, spending at most ROW_BUILD_BUDGET_MS building new rows.

	resume_from is for the catch-up pass only: rows below it are already built
	and already hold this same data, so walking them again would be work with
	no effect. _render() always passes 0, because its data is new."""
	var scroll: ScrollContainer = board_list.get_parent() as ScrollContainer
	var offset: int = scroll.scroll_vertical if scroll != null else 0

	var existing: Array = board_list.get_children()

	# Trim the surplus first, so the loop below never indexes past the end.
	for index in range(existing.size() - 1, top.size() - 1, -1):
		var spare: Node = existing[index]
		board_list.remove_child(spare)
		spare.queue_free()

	# SPENT, NOT COUNTED. Every row built adds to this; when it passes the
	# budget the rest are left for the next frame. Rows that already exist are
	# only refilled, which is cheap, so the budget only ever bites on growth.
	var started: int = Time.get_ticks_usec()
	var ran_out: bool = false
	var reached: int = top.size()

	for index in range(resume_from, top.size()):
		var entry = top[index]
		if not (entry is Dictionary):
			continue
		var row: HBoxContainer
		if index < existing.size():
			row = existing[index] as HBoxContainer
		elif ran_out:
			# Out of frame. Everything from here is next frame's problem, and
			# _process() picks it up from _rows_pending.
			reached = index
			break
		else:
			row = _make_row()
			board_list.add_child(row)
			# CHECKED AFTER THE BUILD, not before, so a slice always makes at
			# least one row of progress. A check first could spend the whole
			# frame on the refill above and then decline to build anything,
			# which is how a list never finishes.
			if (Time.get_ticks_usec() - started) / 1000.0 >= ROW_BUILD_BUDGET_MS:
				ran_out = true
		# THE SERVER'S RANK, not the row's position. They differ the moment two
		# players are tied — the board is 1, 1, 3 and the list is 1, 2, 3 — and
		# they would differ again if this list were ever a page rather than the
		# whole top. index + 1 is only the fallback for an older server.
		_fill_row(row, int(entry.get("rank", index + 1)), entry)

	# WHAT IS LEFT, IF ANYTHING. Holding the whole array rather than an index:
	# the next frame re-runs the same function against the same data, so the
	# rows that exist get refilled with what they already hold and the ones that
	# do not get built. That is idempotent, which an index would not be if a
	# refresh landed in between.
	if ran_out:
		_rows_pending = top
		_rows_done = reached
	else:
		_rows_pending = []
		_rows_done = 0

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
	row.add_theme_constant_override("separation", COL_SEPARATION)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var rank_label := Label.new()
	rank_label.name = "rank"
	# 34, not 28: "200." is a character wider than "10." and the column was
	# sized when ten was the whole board.
	rank_label.custom_minimum_size = Vector2(COL_RANK, 0)
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
	given_label.custom_minimum_size = Vector2(COL_GOLD, 0)
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
	lusions_label.custom_minimum_size = Vector2(COL_LUSIONS, 0)
	lusions_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lusions_label.add_theme_font_size_override("font_size", 12)
	row.add_child(lusions_label)

	# DEATHS, WHICH ARE NOT MONEY AND ARE THE POINT OF THE COLUMN.
	#
	# This was the trade tax per player, and it came out for a measured reason:
	# it was a second GROUP BY over every destroyed-gold row in the ledger, and
	# on a year of play it was four fifths of the board's cost. The realm's tax
	# total is still in the breakdown; what is gone is the per-player slice.
	#
	# Deaths cost nothing to read - a counter on the users row the ranking query
	# already joins - and they answer a question the gold columns cannot: who
	# has actually been through it.
	#
	# LAST, so the two money columns stay adjacent and the one that is not money
	# sits at the edge.
	var death_label := Label.new()
	death_label.name = "deaths"
	death_label.mouse_filter = Control.MOUSE_FILTER_STOP
	death_label.custom_minimum_size = Vector2(COL_DEATHS, 0)
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	death_label.add_theme_font_size_override("font_size", 12)
	row.add_child(death_label)

	return row


func _fill_row(row: HBoxContainer, rank: int, entry: Dictionary) -> void:
	var username: String = str(entry.get("username", "?"))
	var given: int = int(entry.get("contributed", 0))
	var lusions: int = int(entry.get("lusions", 0))
	var deaths: int = int(entry.get("deaths", 0))
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

	var death_label: Label = row.get_node("deaths")
	death_label.text = _commas(deaths) if deaths > 0 else "—"
	death_label.tooltip_text = ("Died %s time%s" % [_commas(deaths),
		"" if deaths == 1 else "s"]) if deaths > 0 else "Never died"
	death_label.add_theme_color_override("font_color",
		DEATH_COLOUR if deaths > 0 else RANK_COLOUR)


func _clear_rows() -> void:
	# The pending board goes with the rows, or _process() would spend the next
	# few frames rebuilding a list this call just decided to throw away.
	_rows_pending = []
	_rows_done = 0
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
	# The loop that used to live here now lives in GameConstants.commas(), and
	# the comment that used to sit here said a shared helper was not worth the
	# indirection for one call site. That was true; a kingdom total was the only
	# genuinely large number in the game. The x8 gear rescale and the coin
	# denominations made it false - see the note on GameConstants.commas().
	#
	# THE WRAPPER STAYS so the eight call sites below read the same as before.
	return GameConstants.commas(amount)


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
