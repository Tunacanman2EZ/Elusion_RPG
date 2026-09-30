# staffpanel.gd — the moderation desk: find a player, act, and read the record.
# attached to res://scene/ui/staff/staffpanel.tscn, opened by the Staff button
# that characterhud.gd shows to mods, devs and the owner.
#
# Two tabs. PLAYERS is the account list and, for whoever is picked, the
# sanctions (kick, ban, unban, rank) and their RECORD - everything staff have
# done or written about them, with a box for a staff-only note or warning. LOG
# is the whole moderation log, newest first, filterable by player, by member of
# staff and by kind: "what happened while I was away".
#
# =============================================================================
# THE SERVER DECIDES; THIS PANEL ONLY DECLINES TO OFFER
# =============================================================================
# Every action here is an endpoint - /api/staff/kick, ban, unban, note and
# PUT /api/staff/role - each behind require_role("mod") and can_act_on(). So
# nothing in this file is a permission. actions_for() hides buttons the server
# would refuse, which is a courtesy to whoever is using it, and the server
# still refuses them if a patched client shows them anyway.
#
# THE RULES IT MIRRORS, all from app.py:
#   can_act_on       you may act only on someone STRICTLY below you, so a mod
#                    cannot touch a mod and nobody touches the owner.
#   MAX_MOD_BAN_DAYS a mod may ban for up to 30 days, never permanently.
#   set_account_role you cannot grant a rank at or above your own, so a dev
#                    makes mods and only the owner makes devs. "owner" is
#                    never granted - it comes from ELUSION_OWNER.
#   STAFF_PRIVATE_KINDS  notes and warnings are read only by staff who could
#                    act on the account. The server filters them out of what
#                    it sends; this panel never has them to hide.
#
# =============================================================================
# THE SERVER PAGES; THIS PANEL NEVER HOLDS THE WHOLE SERVER
# =============================================================================
# This panel used to fetch every account every ten seconds and search them
# here. At forty players that is nothing; at forty thousand it is the heaviest
# request in the game, sent by the people trying to keep order while it is
# busy. The search, the filter and the order are the server's now, and the
# list arrives a page at a time - see list_accounts() and staff_action_log()
# in app.py. "Load more" follows the server's cursor rather than counting rows,
# so a player registering mid-scroll does not show anybody twice.
#
# =============================================================================
# EVERYTHING THAT REMOVES SOMEBODY ASKS TWICE
# =============================================================================
# The first press arms a button and relabels it "Confirm ...?", the second
# within ARM_SECONDS does it. Same pattern as ownerpanel.gd, for the same
# reason: a ban is one mis-click from the row above. Selecting a different
# account disarms, so a button armed for one person can never fire at another.
# A note does not ask: it takes nothing from anybody, and a second press to
# write down what you saw is friction on exactly the habit worth having.
extends Control


signal closed


# =============================================================================
# CONSTANTS
# =============================================================================

# Lowest to highest. The same order as ROLES in app.py; an unknown rank reads
# as the lowest, as role_for() does, so a newer server naming a rank this build
# has never heard of is never taken for more than a player.
# exchange_text(): the player's own words for what a trade moved, so a
# moderator reads one trade the way the player who made it does.
const TradePanelScript := preload("res://src/ui/trade/tradepanel.gd")

const RANKS: PackedStringArray = ["player", "mod", "dev", "owner"]

# Ban lengths offered as buttons. Days, because that is what the endpoint
# takes. All within MAX_MOD_BAN_DAYS, so a mod gets every one of them and only
# "Permanent" depends on rank.
const BAN_PRESETS: Array[int] = [1, 7, 30]

const ARM_SECONDS := 4.0
const ARMED_PROMPT := "Press again within %d seconds to confirm." % int(ARM_SECONDS)

# The list re-reads while open, so "online" stays true to the minute. The
# server's window is 45 seconds; ten here keeps the dots current without
# making the panel the busiest thing talking to the server.
const AUTO_REFRESH_SECONDS := 10.0

# One page of the list or the log. The server's STAFF_PAGE_DEFAULT and
# STAFF_PAGE_MAX; a refresh re-reads everything loaded so far in one request,
# up to the max, and past it waits for the Refresh button rather than
# re-reading a thousand rows every ten seconds.
const PAGE_SIZE := 50
const PAGE_MAX := 200
const RECORD_PAGE_SIZE := 25

# Which of the detail tabs is Trades. Named, because the tab-changed handler
# and the pick both ask "is the moderator looking at trades".
const TRADES_TAB := 2

# How long typing has to pause before the search goes to the server. A request
# per keystroke would be eight requests to find "tunacan".
const SEARCH_DELAY_SECONDS := 0.35

# The list's filters, in the order offered, with what the server calls them.
# ONLINE FIRST AND THE DEFAULT: the people on right now are who a kick is for,
# and the list used to put them at the top for the same reason.
const SHOW_FILTERS: Array = [
	["online", "Online now"],
	["all", "Everyone"],
	["banned", "Banned"],
	["staff", "Staff"],
]

# What the record line counts, in the order it says them. The list row leaves
# notes out - a note is not a sanction, and a row saying "4 notes" reads as
# trouble when it may be four mods writing "helpful in chat".
const RECORD_KINDS: PackedStringArray = ["ban", "kick", "warn", "note"]
const ROW_RECORD_KINDS: PackedStringArray = ["ban", "kick", "warn"]

# The dropdown's words for the server's action names. A kind this build has
# never heard of still appears, under its own name - the list itself comes
# from the server (`kinds`), so the dropdown cannot be a stale second copy.
const KIND_LABELS: Dictionary = {
	"ban": "Bans", "unban": "Unbans", "kick": "Kicks", "warn": "Warnings",
	"note": "Notes", "role": "Rank changes", "grant": "Item grants",
	"teleport": "Teleports", "chat_delete": "Chat deletions",
	"guild_rename": "Guild renames", "guild_disband": "Guild disbands",
	"maintenance": "Maintenance", "minbuild": "Minimum build", "pvp": "PvP switch",
}

# Which kinds name an ACCOUNT as their target, so a log line can take you to
# that player. Guild actions name a guild; maintenance names "server".
const ACCOUNT_KINDS: PackedStringArray = [
	"ban", "unban", "kick", "warn", "note", "role", "grant", "teleport", "chat_delete",
]

const COLOUR_ONLINE := Color(0.55, 0.9, 0.5)
const COLOUR_OFFLINE := Color(0.62, 0.6, 0.56)
const COLOUR_BANNED := Color(1.0, 0.45, 0.4)
const COLOUR_OK := Color(0.72, 0.9, 0.6)
const COLOUR_PROBLEM := Color(1.0, 0.65, 0.25)
const COLOUR_NOTE := Color(0.78, 0.74, 0.95)
const COLOUR_ENTRY := Color(0.84, 0.8, 0.72)


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var close_button:    Button        = %staffclosebutton
@onready var you_label:       Label         = %staffyoulabel
@onready var tabs:            TabContainer  = %stafftabs

# players tab - the list
@onready var search_input:    LineEdit      = %staffsearch
@onready var show_filter:     OptionButton  = %staffshowfilter
@onready var account_list:    VBoxContainer = %staffaccountlist
@onready var empty_label:     Label         = %staffemptylabel
@onready var count_label:     Label         = %staffcountlabel
@onready var more_button:     Button        = %staffmorebutton

# players tab - the detail
@onready var pick_hint:       Label         = %staffpickhint
@onready var detail_box:      Control       = %staffdetail
@onready var name_label:      Label         = %staffnamelabel
@onready var presence_label:  Label         = %staffpresencelabel
@onready var rank_label:      Label         = %staffranklabel
@onready var ban_label:       Label         = %staffbanlabel
@onready var reach_label:     Label         = %staffreachlabel
@onready var record_summary:  Label         = %staffrecordsummary
@onready var detail_tabs:     TabContainer  = %staffdetailtabs
@onready var reason_input:    LineEdit      = %staffreason
@onready var kick_button:     Button        = %staffkickbutton
@onready var ban_row:         HBoxContainer = %staffbanrow
@onready var permanent_button: Button       = %staffpermanentbutton
@onready var unban_button:    Button        = %staffunbanbutton
@onready var rank_row:        HBoxContainer = %staffrankrow
@onready var promote_button:  Button        = %staffpromotebutton
@onready var demote_button:   Button        = %staffdemotebutton
@onready var record_list:     VBoxContainer = %staffrecordlist
@onready var record_empty:    Label         = %staffrecordempty
@onready var record_more:     Button        = %staffrecordmore
@onready var note_input:      LineEdit      = %staffnoteinput
@onready var note_button:     Button        = %staffnotebutton
@onready var warn_button:     Button        = %staffwarnbutton

# players tab - the detail's Trades tab
@onready var trade_summary:   Label         = %stafftradesummary
@onready var trade_list:      VBoxContainer = %stafftradelist
@onready var trade_empty:     Label         = %stafftradeempty
@onready var trade_more:      Button        = %stafftrademore

# log tab
@onready var log_player:      LineEdit      = %stafflogplayer
@onready var log_staff:       LineEdit      = %stafflogstaff
@onready var log_kind:        OptionButton  = %stafflogkind
@onready var log_search:      Button        = %stafflogsearch
@onready var log_entries:     VBoxContainer = %stafflogentries
@onready var log_empty:       Label         = %stafflogempty
@onready var log_more:        Button        = %stafflogmore

@onready var notice_label:    Label         = %staffnotice
@onready var refresh_button:  Button        = %staffrefreshbutton


# =============================================================================
# STATE
# =============================================================================

# The list: what is loaded, and the server's cursor to the rest of it.
var _accounts: Array = []
var _more_accounts: bool = false
var _next_after: String = ""
var _matched: int = 0
var _online_count: int = 0
var _server_now: int = 0           # the server's clock at the last read
var _loading: bool = false
var _search_countdown: float = -1.0

# GENERATIONS, NOT A BUSY FLAG. A search typed while the last one is still in
# flight must win, so each request takes a number and an answer that comes back
# holding an old number is dropped. A flag that refused the second request
# would leave the list showing results for what was typed a keystroke ago.
var _list_generation: int = 0
var _record_generation: int = 0
var _log_generation: int = 0

# WHO IS PICKED, by name and as the last row seen for them. The row is kept
# because the list is a page: a new search can leave the picked account off
# it, and the buttons should not quietly stop being aimed at them.
var _selected: String = ""
var _selected_entry: Dictionary = {}

# The picked account's record.
var _record: Array = []
var _record_summary: Dictionary = {}
var _record_more: bool = false
var _record_before: int = 0

# The log.
# The Trades tab: whose trades are loaded, the page, and the pair cursor
# (updated_at, rowid) the server pages by. Loaded when the tab is opened, not
# on every pick - most picks are to kick or to read the record.
var _trades: Array = []
var _trades_for: String = ""
var _trades_more: bool = false
var _trades_cursor: Dictionary = {}
var _trades_summary: Dictionary = {}
var _trades_now: int = 0
var _trades_generation: int = 0

var _log: Array = []
var _log_more: bool = false
var _log_before: int = 0
var _log_loaded: bool = false
var _log_kinds_filled: bool = false

var _acting: bool = false
var _seconds_until_refresh: float = AUTO_REFRESH_SECONDS

# ARMED-THEN-CONFIRMED. The action carries everything needed to perform it, so
# the second press does exactly what the first press described.
var _armed: Dictionary = {}        # {"key", "button", "label", "until"}
var _preset_buttons: Array[Button] = []


# =============================================================================
# THE RULES, AS PURE FUNCTIONS (the test suite calls these directly)
# =============================================================================

static func rank_index(rank: String) -> int:
	var at: int = RANKS.find(rank)
	return at if at >= 0 else 0


static func actions_for(viewer_rank: String, entry: Dictionary) -> Dictionary:
	# What to OFFER for one account. The server's `actionable` and this
	# client's own reading must BOTH agree before anything is offered: the
	# first is the authority, and the second stops a panel that has not
	# caught up with a demotion from showing buttons its user just lost.
	var mine: int = rank_index(viewer_rank)
	var theirs: int = rank_index(str(entry.get("role", "player")))
	var reach: bool = bool(entry.get("actionable", false)) and mine > theirs
	var senior: bool = mine >= rank_index("dev")

	# Promote one step, but never to your own rank or beyond, and never to
	# owner. A dev promoting a mod would be making a dev: refused by the
	# server, so not offered here.
	var promote_to: String = ""
	var demote_to: String = ""
	if reach and senior:
		var up: int = theirs + 1
		if up < mine and up <= rank_index("dev"):
			promote_to = RANKS[up]
		if theirs > 0:
			demote_to = RANKS[theirs - 1]

	return {
		"kick": reach,
		"ban": reach,
		"ban_permanent": reach and senior,
		"unban": reach and bool(entry.get("banned", false)),
		# A note is reach-gated like a sanction - /api/staff/note runs through
		# _moderation_target() - because only somebody who could act on the
		# account may read it back.
		"note": reach,
		"promote_to": promote_to,
		"demote_to": demote_to,
	}


static func build_query(params: Dictionary) -> String:
	# "?a=1&b=two", in the order given, leaving out what is empty.
	#
	# EMPTY MEANS ABSENT. `q=` is a search for nothing and `before=0` is not a
	# cursor, and sending either would be asking the server a different
	# question than the one meant. Every value is URI-encoded: a search box is
	# typed text, and a name with a `&` in it would otherwise end the query.
	var parts: PackedStringArray = []
	for key in params:
		var value: Variant = params[key]
		if value == null:
			continue
		var text: String = str(value)
		if text == "" or ((value is int or value is float) and int(value) == 0 and key != "limit"):
			continue
		parts.append("%s=%s" % [str(key).uri_encode(), text.uri_encode()])
	return "" if parts.is_empty() else "?" + "&".join(parts)


static func read_page(data: Variant, list_key: String, cursor_key: String) -> Dictionary:
	# A page from the server, with every field turned into what it must be.
	#
	# TWO JSON TRAPS IN ONE PLACE. Every number arrives as a float - see
	# "JSON has no integer type" in CLAUDE.md - and the last page's cursor
	# arrives as null, which str() turns into the five characters "<null>"
	# and int() refuses outright. Read raw, the list's cursor becomes a name
	# to search after and "Load more" asks for everybody after "<null>".
	var out: Dictionary = {"rows": [], "more": false, "cursor": null, "data": {}}
	if not (data is Dictionary):
		return out
	out["data"] = data
	for row in data.get(list_key, []):
		if row is Dictionary:
			out["rows"].append(row)
	out["more"] = bool(data.get("more", false))
	var cursor: Variant = data.get(cursor_key)
	if cursor is String:
		out["cursor"] = cursor if cursor != "" else null
	elif cursor is int or cursor is float:
		out["cursor"] = int(cursor) if int(cursor) > 0 else null
	if out["cursor"] == null:
		# No cursor means no next page, whatever `more` claimed. A "Load more"
		# with nothing to follow would load the first page again.
		out["more"] = false
	return out


static func describe_presence(entry: Dictionary, server_now: int) -> String:
	if bool(entry.get("online", false)):
		return "Online now"
	var seen: int = int(entry.get("last_seen_at", 0))
	if seen <= 0 or server_now <= 0:
		return "Offline"
	return "Last seen %s" % LocalTime.ago(seen, server_now)


static func describe_ban(ban: Variant) -> String:
	if not (ban is Dictionary):
		return "Not banned"
	var until: String = "permanently"
	if not bool(ban.get("permanent", false)):
		# Local time, to the minute - see describe_login_refusal() in
		# loginmenu.gd for why not the raw UTC string.
		until = "until " + LocalTime.full(int(ban.get("expires_at", 0)))
	var line: String = "Banned %s by %s" % [until, str(ban.get("banned_by", "?"))]
	var reason: String = str(ban.get("reason", ""))
	if reason != "":
		line += "\n\"%s\"" % reason
	return line


static func describe_record(tally: Variant, kinds: PackedStringArray = RECORD_KINDS) -> String:
	# "2 bans · 1 kick · 3 warnings", in RECORD_KINDS order, or "" for nothing.
	#
	# THE QUESTION A MOD ASKS FIRST is "is this the first time", and the
	# answer is these four numbers, before any line of the record is read.
	if not (tally is Dictionary):
		return ""
	var words: Dictionary = {
		"ban": ["ban", "bans"], "kick": ["kick", "kicks"],
		"warn": ["warning", "warnings"], "note": ["note", "notes"],
	}
	var parts: PackedStringArray = []
	for kind in kinds:
		var n: int = int(tally.get(kind, 0))
		if n <= 0 or not words.has(kind):
			continue
		parts.append("%d %s" % [n, words[kind][0] if n == 1 else words[kind][1]])
	return " · ".join(parts)


static func describe_entry(entry: Dictionary) -> String:
	# One log line in words: "themod banned rowdy - 3 days: language".
	#
	# The server's `detail` is kept whole after the dash - it is the reason a
	# member of staff wrote, and paraphrasing it would be putting words in
	# their mouth. What this adds is the verb, so a column of "ban", "kick",
	# "warn" reads as sentences about people rather than a table of codes.
	var by: String = str(entry.get("by", "?"))
	var kind: String = str(entry.get("action", ""))
	var target: String = str(entry.get("target", ""))
	var detail: String = str(entry.get("detail", ""))
	var line: String
	match kind:
		"ban":
			line = "%s banned %s" % [by, target]
		"unban":
			line = "%s lifted %s's ban" % [by, target]
		"kick":
			line = "%s kicked %s" % [by, target]
		"warn":
			line = "%s warned %s" % [by, target]
		"note":
			line = "%s noted on %s" % [by, target]
		"role":
			line = "%s changed %s's rank" % [by, target]
		"grant":
			line = "%s granted %s items" % [by, "themselves" if target == by else target]
		"teleport":
			line = "%s teleported %s" % [by, target]
		"chat_delete":
			line = "%s deleted a chat line by %s" % [by, target]
		"guild_rename":
			line = "%s renamed the guild %s" % [by, target]
		"guild_disband":
			line = "%s disbanded the guild %s" % [by, target]
		"maintenance", "minbuild", "pvp":
			line = "%s changed %s" % [by, str(KIND_LABELS.get(kind, kind)).to_lower()]
		_:
			# A kind this build does not know yet still says who did what to
			# whom, in the server's own words.
			line = "%s %s %s" % [by, kind, target]
	if detail != "":
		line += " - " + detail
	return line


static func target_is_account(entry: Dictionary) -> bool:
	# Whether a log line's target is a player the panel can open. "everyone"
	# is what a mass teleport names, and a guild action names a guild.
	var target: String = str(entry.get("target", ""))
	return ACCOUNT_KINDS.has(str(entry.get("action", ""))) and target != "" and target != "everyone"


static func colour_for_kind(kind: String) -> Color:
	match kind:
		"ban":
			return COLOUR_BANNED
		"kick", "warn":
			return COLOUR_PROBLEM
		"note":
			return COLOUR_NOTE
		"unban":
			return COLOUR_OK
	return COLOUR_ENTRY


static func describe_count(shown: int, matched: int, online: int) -> String:
	# "50 of 1,204 · 12 online" while there is more to load, "4 accounts ·
	# 1 online" once there is not. MATCHED IS THE SERVER'S COUNT, not the rows
	# held here - the whole point of paging is that this panel does not have
	# them. The online figure is the whole server's, whatever the filter.
	var matched_text: String = GameConstants.commas(matched)
	if shown < matched:
		return "%d of %s · %d online" % [shown, matched_text, online]
	return "%s account%s · %d online" % [matched_text, "" if matched == 1 else "s", online]


static func my_rank() -> String:
	return "owner" if Api.is_owner else Api.role


# =============================================================================
# LIFECYCLE
# =============================================================================

# Drag by the header, resize from any edge, and come back where it was left.
# One component for all sixteen panels - see src/shared/panelwindow.gd for why
# this is not thirty lines copied into each of them.
#
# HELD IN A MEMBER, not discarded. It is a RefCounted carrying the drag state
# and the signal connections; letting it go frees it and the panel quietly
# stops responding.
var _window: PanelWindow


func _ready() -> void:
	_window = PanelWindow.attach(self, "staff")
	visible = false
	close_button.pressed.connect(close_panel)
	refresh_button.pressed.connect(_on_refresh_pressed)

	# TAB TITLES FROM HERE, NOT FROM NODE NAMES. A TabContainer titles a tab
	# after its child, and node names in this project are lowercase.
	tabs.set_tab_title(0, "Players")
	tabs.set_tab_title(1, "Log")
	tabs.tab_changed.connect(_on_tab_changed)
	detail_tabs.set_tab_title(0, "Actions")
	detail_tabs.set_tab_title(1, "Record")
	detail_tabs.set_tab_title(TRADES_TAB, "Trades")
	detail_tabs.tab_changed.connect(_on_detail_tab_changed)
	trade_more.pressed.connect(func(): _load_trades("more"))

	for pair in SHOW_FILTERS:
		show_filter.add_item(str(pair[1]))
		show_filter.set_item_metadata(show_filter.item_count - 1, str(pair[0]))
	show_filter.select(0)
	show_filter.item_selected.connect(func(_i): _load("fresh"))
	search_input.text_changed.connect(func(_t): _search_countdown = SEARCH_DELAY_SECONDS)
	search_input.text_submitted.connect(func(_t): _search_now())
	more_button.pressed.connect(func(): _load("more"))

	kick_button.pressed.connect(_on_action_pressed.bind(kick_button, "kick", 0))
	permanent_button.pressed.connect(_on_action_pressed.bind(permanent_button, "ban", -1))
	unban_button.pressed.connect(_on_action_pressed.bind(unban_button, "unban", 0))
	promote_button.pressed.connect(_on_action_pressed.bind(promote_button, "promote", 0))
	demote_button.pressed.connect(_on_action_pressed.bind(demote_button, "demote", 0))

	record_more.pressed.connect(func(): _load_record("more"))
	note_button.pressed.connect(_on_note_pressed.bind("note"))
	warn_button.pressed.connect(_on_note_pressed.bind("warn"))
	note_input.text_submitted.connect(func(_t): _on_note_pressed("note"))

	log_kind.add_item("Everything")
	log_kind.set_item_metadata(0, "")
	log_kind.item_selected.connect(func(_i): _load_log("fresh"))
	log_search.pressed.connect(func(): _load_log("fresh"))
	log_player.text_submitted.connect(func(_t): _load_log("fresh"))
	log_staff.text_submitted.connect(func(_t): _load_log("fresh"))
	log_more.pressed.connect(func(): _load_log("more"))

	# The day buttons are made here from BAN_PRESETS, ahead of Permanent, so
	# the lengths live in one list rather than in a scene and a script.
	for days in BAN_PRESETS:
		var button := Button.new()
		button.text = "%d day%s" % [days, "" if days == 1 else "s"]
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_action_pressed.bind(button, "ban", days))
		ban_row.add_child(button)
		ban_row.move_child(button, ban_row.get_child_count() - 2)
		_preset_buttons.append(button)

	_show_detail({})


func _process(delta: float) -> void:
	if not visible:
		return
	if not _armed.is_empty() and Time.get_ticks_msec() / 1000.0 > float(_armed["until"]):
		_disarm()
	if _search_countdown > 0.0:
		_search_countdown -= delta
		if _search_countdown <= 0.0:
			_search_now()
	_seconds_until_refresh -= delta
	if _seconds_until_refresh <= 0.0:
		_seconds_until_refresh = AUTO_REFRESH_SECONDS
		# Only the list ticks. The log and a record are read when asked for:
		# they are history, and history does not need re-reading every ten
		# seconds by somebody who is reading it.
		# Not mid-search either: the box holds half a name until the pause.
		if tabs.current_tab == 0 and _search_countdown <= 0.0:
			_load("refresh")


# =============================================================================
# OPEN / CLOSE
# =============================================================================

func open_panel() -> void:
	visible = true
	you_label.text = "You: %s" % my_rank()
	_seconds_until_refresh = AUTO_REFRESH_SECONDS
	await _load("fresh")


func close_panel() -> void:
	_disarm()
	visible = false
	# Focus goes with it. A reason box left focused behind a closed panel
	# would go on eating keystrokes nobody can see.
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()
	closed.emit()


func toggle_panel() -> void:
	if visible:
		close_panel()
	else:
		await open_panel()


func _on_tab_changed(index: int) -> void:
	_disarm()
	# The log is read the first time anybody looks at it, not on open: most
	# visits to this panel are to act on somebody, not to read history.
	if index == 1 and not _log_loaded:
		await _load_log("fresh")


func _on_refresh_pressed() -> void:
	_seconds_until_refresh = AUTO_REFRESH_SECONDS
	if tabs.current_tab == 1:
		await _load_log("fresh")
		return
	await _load("refresh")
	if _selected != "":
		await _load_record("fresh")


# =============================================================================
# THE LIST
# =============================================================================

func _search_now() -> void:
	_search_countdown = -1.0
	await _load("fresh")


func _show_value() -> String:
	if show_filter.selected < 0:
		return "online"
	return str(show_filter.get_item_metadata(show_filter.selected))


func _load(mode: String = "fresh") -> void:
	# "fresh"   a new question - first page of a new search or filter
	# "refresh" the same question again, as much of it as is loaded
	# "more"    the next page after the server's cursor
	#
	# Only a fresh load may overtake one in flight; a tick of the auto-refresh
	# landing on top of "Load more" would otherwise throw the new page away.
	if mode != "fresh" and _loading:
		return
	var params: Dictionary = _list_params(mode)
	if params.is_empty():
		return

	_list_generation += 1
	var generation: int = _list_generation
	_loading = true
	more_button.disabled = true
	var res: Dictionary = await Api.get_json("/api/staff/users" + build_query(params))
	# PAST AN AWAIT: the panel can be closed, or the whole HUD freed by a
	# scene change, while the server was answering.
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if generation != _list_generation:
		# A newer question was asked while this one was out. Its answer owns
		# the list, and it clears _loading when it lands.
		return
	_apply_list_page(res, mode)


func _list_params(mode: String) -> Dictionary:
	# What to ask the server, or {} for "do not ask". SEPARATE FROM THE
	# REQUEST so the suite can hold every branch of it without a server.
	var params: Dictionary = {"show": _show_value(), "q": search_input.text.strip_edges()}
	match mode:
		"more":
			if not _more_accounts or _next_after == "":
				return {}
			params["after"] = _next_after
			params["limit"] = PAGE_SIZE
		"refresh":
			if _accounts.size() > PAGE_MAX:
				# Deep in the list: re-reading hundreds of rows every ten
				# seconds costs more than a slightly stale dot. Refresh does it.
				return {}
			params["limit"] = clampi(_accounts.size(), PAGE_SIZE, PAGE_MAX)
		_:
			params["limit"] = PAGE_SIZE
	return params


func _apply_list_page(res: Dictionary, mode: String) -> void:
	# The server's answer, landed. Also the suite's way in: it hands this a
	# made-up answer and reads what the panel did with it.
	_loading = false
	more_button.disabled = false

	if not res.get("ok", false):
		if int(res.get("status", 0)) == 404:
			# require_role answers a non-staff caller with 404. Reaching here
			# means this account was demoted while the panel was open.
			_accounts = []
			_more_accounts = false
			_next_after = ""
			_render_list()
			_say("The server no longer lists you as staff.", false)
		else:
			_say(str(res.get("error", "Could not load accounts.")), false)
		return

	var page: Dictionary = read_page(res.get("data"), "accounts", "next_after")
	var data: Dictionary = page["data"]
	_server_now = int(data.get("now", 0))
	_matched = int(data.get("matched", 0))
	_online_count = int(data.get("online", 0))
	_more_accounts = bool(page["more"])
	_next_after = str(page["cursor"]) if page["cursor"] != null else ""
	if mode == "more":
		_accounts.append_array(page["rows"])
	else:
		_accounts = page["rows"]

	# The picked account's row is refreshed when the page carries it, and kept
	# as it was when it does not - see _selected_entry.
	var fresh: Dictionary = _entry_named(_selected)
	if not fresh.is_empty():
		_selected_entry = fresh
	you_label.text = "You: %s" % my_rank()
	_render_list()


func _render_list() -> void:
	for child in account_list.get_children():
		child.queue_free()

	empty_label.visible = _accounts.is_empty()
	if _accounts.is_empty():
		var looked_for: String = search_input.text.strip_edges()
		if _show_value() == "online" and looked_for != "":
			# The one empty list that is a trap: the player is offline, the
			# filter says Online, and "no match" reads as "no such player".
			empty_label.text = "Nobody online matches. Show Everyone to search offline players too."
		elif looked_for != "":
			empty_label.text = "No accounts match."
		elif _show_value() == "online":
			empty_label.text = "Nobody is online."
		else:
			empty_label.text = "No accounts here."
	count_label.text = describe_count(_accounts.size(), _matched, _online_count)
	more_button.visible = _more_accounts

	for entry in _accounts:
		account_list.add_child(_make_row(entry))

	_show_detail(_selected_entry)


func _make_row(entry: Dictionary) -> Button:
	var name_text: String = str(entry.get("username", "?"))
	var tags: PackedStringArray = []
	var rank: String = str(entry.get("role", "player"))
	if rank != "player":
		tags.append(rank)
	if bool(entry.get("banned", false)):
		tags.append("banned")
	if name_text == Api.username:
		tags.append("you")
	var record: String = describe_record(entry.get("record", {}), ROW_RECORD_KINDS)
	if record != "":
		tags.append(record)

	var row := Button.new()
	row.focus_mode = Control.FOCUS_NONE
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.toggle_mode = true
	row.button_pressed = name_text == _selected
	# CLIPPED, WITH THE WHOLE LINE IN THE TOOLTIP. A row carrying a rank, a
	# ban and a record is wider than the column, and an unclipped Button
	# widens its container instead - the list would scroll sideways.
	row.clip_text = true
	row.text = "%s %s%s" % [
		"●" if bool(entry.get("online", false)) else "○",
		name_text,
		("   " + " · ".join(tags)) if not tags.is_empty() else "",
	]
	row.tooltip_text = row.text
	var colour: Color = COLOUR_OFFLINE
	if bool(entry.get("banned", false)):
		colour = COLOUR_BANNED
	elif bool(entry.get("online", false)):
		colour = COLOUR_ONLINE
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		row.add_theme_color_override(state, colour)
	# The name rides on the row itself rather than being read back out of its
	# label, which carries a dot and tags around it.
	row.set_meta("username", name_text)
	row.pressed.connect(_on_row_pressed.bind(name_text))
	return row


func _on_row_pressed(username: String) -> void:
	_pick(username)


func _pick(username: String) -> void:
	if username != _selected:
		_disarm()
		reason_input.text = ""
		note_input.text = ""
		_record = []
		_record_summary = {}
		_record_more = false
		_forget_trades()
	_selected = username
	var found: Dictionary = _entry_named(username)
	if not found.is_empty():
		_selected_entry = found
	for child in account_list.get_children():
		if child is Button:
			child.set_pressed_no_signal(str(child.get_meta("username", "")) == username)
	_show_detail(_selected_entry)
	# THE TRADES TAB FOLLOWS THE PICK if it is the tab being looked at - a
	# moderator going down a list of names is reading trades, not records.
	if detail_tabs.current_tab == TRADES_TAB and _trades_for != username:
		_load_trades("fresh")
	await _load_record("fresh")


func _entry_named(username: String) -> Dictionary:
	if username == "":
		return {}
	for entry in _accounts:
		if str(entry.get("username", "")) == username:
			return entry
	return {}


func _open_player(username: String) -> void:
	# From a log line to that player, ready to act on: the Players tab,
	# searched for exactly them across everyone, and picked.
	tabs.current_tab = 0
	search_input.text = username
	_search_countdown = -1.0
	for i in show_filter.item_count:
		if str(show_filter.get_item_metadata(i)) == "all":
			show_filter.select(i)
	_selected_entry = {}
	await _load("fresh")
	if not is_instance_valid(self) or not is_inside_tree():
		return
	var found: Dictionary = _entry_named(username)
	if found.is_empty():
		# A deleted account's lines stay in the log; its row does not.
		_say("%s is not an account any more - the log keeps their name." % username, false)
		return
	await _pick(username)


# =============================================================================
# THE DETAIL
# =============================================================================

func _show_detail(entry: Dictionary) -> void:
	if entry.is_empty():
		detail_box.visible = false
		pick_hint.visible = true
		return
	detail_box.visible = true
	pick_hint.visible = false

	var can: Dictionary = actions_for(my_rank(), entry)
	name_label.text = str(entry.get("username", "?"))
	presence_label.text = describe_presence(entry, _server_now)
	presence_label.add_theme_color_override("font_color",
		COLOUR_ONLINE if bool(entry.get("online", false)) else COLOUR_OFFLINE)
	rank_label.text = "Rank: %s" % str(entry.get("role", "player"))
	ban_label.text = describe_ban(entry.get("ban"))
	ban_label.add_theme_color_override("font_color",
		COLOUR_BANNED if bool(entry.get("banned", false)) else COLOUR_OFFLINE)

	var reach: bool = bool(can["kick"])
	reach_label.visible = not reach
	if name_label.text == Api.username:
		reach_label.text = "This is you."
	else:
		reach_label.text = "Your rank does not reach this account."

	reason_input.editable = reach
	kick_button.disabled = not can["kick"]
	for button in _preset_buttons:
		button.disabled = not can["ban"]
	permanent_button.disabled = not can["ban_permanent"]
	unban_button.disabled = not can["unban"]
	note_input.editable = can["note"]
	note_button.disabled = not can["note"]
	warn_button.disabled = not can["note"]

	# The rank row exists only for devs and the owner - the rank changes the
	# user asked for were theirs, and a mod could never make one anyway.
	rank_row.visible = rank_index(my_rank()) >= rank_index("dev")
	promote_button.visible = can["promote_to"] != ""
	demote_button.visible = can["demote_to"] != ""
	if can["promote_to"] != "":
		promote_button.text = "Promote to %s" % can["promote_to"]
	if can["demote_to"] != "":
		demote_button.text = "Demote to %s" % can["demote_to"]

	_render_record_summary()

	# Re-applying the labels above would wipe an armed "Confirm ...?" - put it
	# back, so a refresh landing between the two presses does not disarm it
	# silently while the timer says otherwise.
	if not _armed.is_empty() and is_instance_valid(_armed["button"]):
		(_armed["button"] as Button).text = _confirm_text(str(_armed["key"]))


# =============================================================================
# THE RECORD
# =============================================================================

func _load_record(mode: String = "fresh") -> void:
	var username: String = _selected
	var params: Dictionary = _record_params(mode)
	if params.is_empty():
		return

	_record_generation += 1
	var generation: int = _record_generation
	record_more.disabled = true
	var res: Dictionary = await Api.get_json("/api/staff/actions" + build_query(params))
	if not is_instance_valid(self) or not is_inside_tree():
		return
	# DROPPED IF ANYBODY ELSE WAS PICKED MEANWHILE. Otherwise a slow answer
	# about the last player lands under the name of the next one.
	if generation != _record_generation or username != _selected:
		return
	_apply_record_page(res, mode)


func _record_params(mode: String) -> Dictionary:
	if _selected == "":
		return {}
	var params: Dictionary = {"player": _selected, "limit": RECORD_PAGE_SIZE}
	if mode == "more":
		if not _record_more or _record_before <= 0:
			return {}
		params["before"] = _record_before
	return params


func _apply_record_page(res: Dictionary, mode: String) -> void:
	record_more.disabled = false
	if not res.get("ok", false):
		record_empty.visible = true
		record_empty.text = "Could not read the record: %s" % str(res.get("error", "no answer"))
		return

	var page: Dictionary = read_page(res.get("data"), "actions", "next_before")
	if mode == "more":
		_record.append_array(page["rows"])
	else:
		_record = page["rows"]
	_record_more = bool(page["more"])
	_record_before = int(page["cursor"]) if page["cursor"] != null else 0
	# The tally rides on every page, and is the whole record rather than the
	# page - the server counts it with the same filter and no cursor.
	var summary: Variant = page["data"].get("summary", {})
	_record_summary = summary if summary is Dictionary else {}
	_render_record()


func _render_record() -> void:
	for child in record_list.get_children():
		child.queue_free()
	for entry in _record:
		record_list.add_child(_make_entry_row(entry, false))
	record_empty.visible = _record.is_empty()
	if _record.is_empty():
		record_empty.text = "Nothing on record. Notes you add are for staff only."
	record_more.visible = _record_more
	_render_record_summary()


func _render_record_summary() -> void:
	var line: String = describe_record(_record_summary)
	record_summary.text = "Record: " + (line if line != "" else "clean")
	var sanctions: int = 0
	for kind in ROW_RECORD_KINDS:
		sanctions += int(_record_summary.get(kind, 0))
	record_summary.add_theme_color_override("font_color",
		COLOUR_PROBLEM if sanctions > 0 else COLOUR_OFFLINE)
	# The tab says it too, so a record is noticed from the Actions tab - which
	# is where somebody about to ban is looking.
	detail_tabs.set_tab_title(1, ("Record (%d)" % sanctions) if sanctions > 0 else "Record")


# =============================================================================
# TRADES - "he scammed me"
# =============================================================================
# Every finished trade is kept for good so that a report can be checked, and
# this is where it is checked: what the account gave and got, with whom, on
# which character, and what the kingdom took - newest first, paged, under the
# same reach rule as the record. GET /api/staff/trades.

func _on_detail_tab_changed(index: int) -> void:
	if index == TRADES_TAB and _selected != "" and _trades_for != _selected:
		await _load_trades("fresh")


func _forget_trades() -> void:
	_trades = []
	_trades_for = ""
	_trades_more = false
	_trades_cursor = {}
	_trades_summary = {}
	_trades_generation += 1
	if trade_list != null:
		for child in trade_list.get_children():
			child.queue_free()
		trade_summary.text = "Trades"
		trade_more.visible = false
		trade_empty.visible = false
		detail_tabs.set_tab_title(TRADES_TAB, "Trades")


func _trades_params(mode: String) -> Dictionary:
	if _selected == "":
		return {}
	var params: Dictionary = {"username": _selected, "limit": RECORD_PAGE_SIZE}
	if mode == "more":
		if not _trades_more or _trades_cursor.is_empty():
			return {}
		params["before_at"] = int(_trades_cursor["at"])
		params["before_seq"] = int(_trades_cursor["seq"])
	return params


func _load_trades(mode: String = "fresh") -> void:
	var username: String = _selected
	var params: Dictionary = _trades_params(mode)
	if params.is_empty():
		return
	_trades_generation += 1
	var generation: int = _trades_generation
	trade_more.disabled = true
	if mode == "fresh":
		trade_empty.visible = true
		trade_empty.text = "Reading %s's trades..." % username
	var res: Dictionary = await Api.get_json("/api/staff/trades" + build_query(params))
	if not is_instance_valid(self) or not is_inside_tree():
		return
	# DROPPED IF ANYBODY ELSE WAS PICKED MEANWHILE, like the record.
	if generation != _trades_generation or username != _selected:
		return
	_apply_trades_page(res, mode, username)


func _apply_trades_page(res: Dictionary, mode: String, username: String) -> void:
	"""One page from GET /api/staff/trades onto the tab. Split from the
	request so the suite can hand it pages and look."""
	trade_more.disabled = false
	if not res.get("ok", false):
		trade_empty.visible = true
		# 404 IS "NO SUCH ACCOUNT" AND "NOT YOURS TO READ", deliberately the
		# same answer - see _moderation_target() on the server.
		trade_empty.text = ("You cannot read this account's trades."
			if int(res.get("status", 0)) == 404
			else "Could not read trades: %s" % str(res.get("error", "no answer")))
		return
	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	var rows: Array = []
	for row in data.get("trades", []):
		if row is Dictionary:
			rows.append(row)
	if mode == "more":
		_trades.append_array(rows)
	else:
		_trades = rows
	_trades_for = username
	_trades_cursor = trade_cursor(data)
	# NO CURSOR, NO NEXT PAGE, whatever `more` claimed - the same rule
	# read_page() keeps for the other lists.
	_trades_more = bool(data.get("more", false)) and not _trades_cursor.is_empty()
	var summary: Variant = data.get("summary", {})
	_trades_summary = summary if summary is Dictionary else {}
	_trades_now = int(data.get("now", 0))
	_render_trades()


static func trade_cursor(data: Dictionary) -> Dictionary:
	"""{"at", "seq"} from a page's next_before, or {} when there is none.

	A PAIR, not the single id the log pages by: trades are ordered by when they
	ended, which is whole seconds, and the rowid breaks the tie."""
	var cursor: Variant = data.get("next_before")
	if not (cursor is Dictionary):
		return {}
	var at: int = int(cursor.get("at", 0))
	var seq: int = int(cursor.get("seq", 0))
	if at <= 0 or seq <= 0:
		return {}
	return {"at": at, "seq": seq}


static func describe_trade_summary(tally: Variant) -> String:
	"""'17 finished · 13 called off · 1 open', or 'no trades'."""
	if not (tally is Dictionary):
		return "no trades"
	var parts: PackedStringArray = []
	for pair in [["done", "finished"], ["cancelled", "called off"], ["open", "open"]]:
		var n: int = int((tally as Dictionary).get(pair[0], 0))
		if n > 0:
			parts.append("%d %s" % [n, pair[1]])
	return "no trades" if parts.is_empty() else " · ".join(parts)


static func describe_trade(record: Dictionary) -> String:
	"""One trade from the account's side, for a moderator:
	'with Bram (bob), as Aldra: got 300 gold for Iron Sword. The kingdom took 15 gold.'

	THE SAME WORDS THE PLAYER'S OWN HISTORY USES for what moved -
	TradePanel.exchange_text() - so a moderator and the player describe one
	trade the same way when they talk about it."""
	var who: String = str(record.get("with_name", ""))
	var account: String = str(record.get("with", "?"))
	var partner: String = "%s (%s)" % [who, account] if who != "" else account
	var character: String = str(record.get("character", ""))
	var head: String = "with %s%s: " % [partner, (", as %s" % character) if character != "" else ""]
	var exchange: String = TradePanelScript.exchange_text(record)
	match str(record.get("state", "")):
		"cancelled":
			return head + "called off" + ("" if exchange == "nothing changed hands"
				else " (it would have " + exchange + ")")
		"open":
			return head + "still open" + ("" if exchange == "nothing changed hands"
				else " (so far it would " + exchange.replace("got ", "get ").replace("gave ", "give ") + ")")
	var line: String = head + exchange + "."
	var tax: int = int(record.get("tax", 0))
	if tax > 0:
		line += " The kingdom took %s." % GameConstants.gold_text(tax)
	return line


func _render_trades() -> void:
	for child in trade_list.get_children():
		trade_list.remove_child(child)
		child.queue_free()
	for record in _trades:
		trade_list.add_child(_make_trade_row(record))
	trade_empty.visible = _trades.is_empty()
	if _trades.is_empty():
		trade_empty.text = "%s has not traded with anybody." % _trades_for
	trade_more.visible = _trades_more
	trade_summary.text = "Trades: " + describe_trade_summary(_trades_summary)
	var done: int = int(_trades_summary.get("done", 0))
	detail_tabs.set_tab_title(TRADES_TAB, ("Trades (%d)" % done) if done > 0 else "Trades")


func _make_trade_row(record: Dictionary) -> Control:
	# A Label like the record's rows, for the same reason: it wraps, and a
	# trade of eight kinds of item is longer than the panel is wide.
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(1, 0)
	label.add_theme_font_size_override("font_size", 12)
	var state: String = str(record.get("state", ""))
	label.add_theme_color_override("font_color",
		COLOUR_ENTRY if state == "done" else (COLOUR_PROBLEM if state == "open" else COLOUR_OFFLINE))
	var at: int = int(record.get("at", 0))
	label.text = "%s  %s" % [LocalTime.stamp(at), describe_trade(record)]
	# THE TRADE ID IS IN THE TOOLTIP because the ledger's burn rows name it -
	# "trade 3kF9aQ2x receiving 450" - and that is how a trade is found there.
	var partner: String = str(record.get("with", ""))
	label.tooltip_text = "Opened %s, %s %s\nTrade %s\nClick to open %s" % [
		LocalTime.full(int(record.get("opened_at", 0))),
		"ended" if state != "open" else "last changed",
		LocalTime.full(at), str(record.get("trade_id", "")).left(8), partner]
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	# THE OTHER SIDE IS ONE CLICK AWAY. A scam report is about two people.
	if partner != "" and partner != "?":
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		label.gui_input.connect(_on_entry_input.bind(partner))
	return label


func _make_entry_row(entry: Dictionary, clickable: bool) -> Control:
	# One line of history. A Label, not a Button: it wraps, and a reason
	# typed by a member of staff is often longer than the panel is wide.
	#
	# add_text-safe by construction - a Label draws its text literally, so a
	# note reading "[color=red]" shows those characters rather than obeying
	# them. That matters: the text is typed by staff about players, and some
	# of it will be quoting what a player typed.
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(1, 0)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", colour_for_kind(str(entry.get("action", ""))))
	var at: int = int(entry.get("at", 0))
	label.text = "%s  %s" % [LocalTime.stamp(at), describe_entry(entry)]
	label.tooltip_text = LocalTime.full(at)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	if clickable and target_is_account(entry):
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		label.tooltip_text += " - click to open %s" % str(entry.get("target", ""))
		label.gui_input.connect(_on_entry_input.bind(str(entry.get("target", ""))))
	return label


func _on_entry_input(event: InputEvent, username: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		await _open_player(username)


func _on_note_pressed(kind: String) -> void:
	var entry: Dictionary = _selected_entry
	if entry.is_empty() or _acting:
		return
	if not actions_for(my_rank(), entry)["note"]:
		return
	var text: String = note_input.text.strip_edges()
	if text == "":
		_say("Write the note first.", false)
		note_input.grab_focus()
		return

	var username: String = str(entry.get("username", ""))
	_acting = true
	var res: Dictionary = await Api.post("/api/staff/note",
		{"username": username, "text": text, "kind": kind})
	_acting = false
	if not is_instance_valid(self) or not is_inside_tree():
		return

	if not res.get("ok", false):
		if int(res.get("status", 0)) == 404:
			_say("Refused: %s is out of your reach (or gone)." % username, false)
		else:
			_say("Refused: %s" % str(res.get("error", "unknown error")), false)
		return

	note_input.text = ""
	if kind == "warn":
		# SAID PLAINLY, because the button could be read as sending one.
		_say("Warning logged on %s's record. Staff only - the game does not tell them." % username, true)
	else:
		_say("Note saved on %s's record. Staff only." % username, true)
	await _load_record("fresh")
	await _load("refresh")


# =============================================================================
# THE LOG
# =============================================================================

func _log_kind_value() -> String:
	if log_kind.selected < 0:
		return ""
	return str(log_kind.get_item_metadata(log_kind.selected))


func _load_log(mode: String = "fresh") -> void:
	var params: Dictionary = _log_params(mode)
	if params.is_empty():
		return

	_log_generation += 1
	var generation: int = _log_generation
	log_more.disabled = true
	var res: Dictionary = await Api.get_json("/api/staff/actions" + build_query(params))
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if generation != _log_generation:
		return
	_apply_log_page(res, mode)


func _log_params(mode: String) -> Dictionary:
	var params: Dictionary = {
		"player": log_player.text.strip_edges(),
		"staff": log_staff.text.strip_edges(),
		"action": _log_kind_value(),
		"limit": PAGE_SIZE,
	}
	if mode == "more":
		if not _log_more or _log_before <= 0:
			return {}
		params["before"] = _log_before
	return params


func _apply_log_page(res: Dictionary, mode: String) -> void:
	log_more.disabled = false
	_log_loaded = true

	if not res.get("ok", false):
		_say("The log: %s" % str(res.get("error", "no answer")), false)
		return

	var page: Dictionary = read_page(res.get("data"), "actions", "next_before")
	_fill_log_kinds(page["data"].get("kinds", []))
	if mode == "more":
		_log.append_array(page["rows"])
	else:
		_log = page["rows"]
	_log_more = bool(page["more"])
	_log_before = int(page["cursor"]) if page["cursor"] != null else 0
	_render_log()


func _fill_log_kinds(kinds: Variant) -> void:
	# Once, from the server's own list. Refilling on every page would reset
	# the dropdown under somebody's cursor.
	if _log_kinds_filled or not (kinds is Array) or kinds.is_empty():
		return
	_log_kinds_filled = true
	for kind in kinds:
		log_kind.add_item(str(KIND_LABELS.get(str(kind), str(kind))))
		log_kind.set_item_metadata(log_kind.item_count - 1, str(kind))


func _render_log() -> void:
	for child in log_entries.get_children():
		child.queue_free()
	for entry in _log:
		log_entries.add_child(_make_entry_row(entry, true))
	log_empty.visible = _log.is_empty()
	var filtered: bool = log_player.text.strip_edges() != "" \
		or log_staff.text.strip_edges() != "" or _log_kind_value() != ""
	log_empty.text = "Nothing matches those filters." if filtered else "Nothing has been logged yet."
	log_more.visible = _log_more


# =============================================================================
# ACTIONS
# =============================================================================

func _on_action_pressed(button: Button, action: String, days: int) -> void:
	var entry: Dictionary = _selected_entry
	if entry.is_empty() or _acting:
		return

	var key: String = "%s:%d:%s" % [action, days, _selected]

	if action == "ban" and reason_input.text.strip_edges() == "":
		# Asked for BEFORE arming. The server requires one, and a confirm
		# that then fails on a missing reason is two clicks for an error.
		_say("Type a reason first - every ban needs one.", false)
		reason_input.grab_focus()
		return

	# FIRST PRESS ARMS.
	if _armed.get("key", "") != key:
		_disarm()
		_armed = {
			"key": key,
			"button": button,
			"label": button.text,
			"until": Time.get_ticks_msec() / 1000.0 + ARM_SECONDS,
		}
		button.text = _confirm_text(key)
		_say(ARMED_PROMPT, true)
		return

	# SECOND PRESS DOES IT.
	_disarm()
	await _perform(action, days, entry)


func _confirm_text(key: String) -> String:
	var parts: PackedStringArray = key.split(":")
	var action: String = parts[0]
	var days: int = int(parts[1])
	match action:
		"kick":
			return "Confirm kick?"
		"ban":
			return "Confirm permanent?" if days < 0 else "Confirm %dd?" % days
		"unban":
			return "Confirm unban?"
		"promote", "demote":
			return "Confirm?"
	return "Confirm?"


func _disarm() -> void:
	if _armed.is_empty():
		return
	var button: Variant = _armed.get("button")
	if is_instance_valid(button):
		(button as Button).text = str(_armed["label"])
	_armed = {}
	# The prompt goes with the arm. Left up, it tells whoever looks next to
	# press something that is no longer armed.
	if notice_label.text == ARMED_PROMPT:
		_say("", true)


func _perform(action: String, days: int, entry: Dictionary) -> void:
	var username: String = str(entry.get("username", ""))
	var reason: String = reason_input.text.strip_edges()
	var can: Dictionary = actions_for(my_rank(), entry)

	var res: Dictionary
	_acting = true
	match action:
		"kick":
			var body: Dictionary = {"username": username}
			if reason != "":
				body["reason"] = reason
			res = await Api.post("/api/staff/kick", body)
		"ban":
			# NO `days` MEANS PERMANENT, which is how the endpoint reads it.
			var body: Dictionary = {"username": username, "reason": reason}
			if days > 0:
				body["days"] = days
			res = await Api.post("/api/staff/ban", body)
		"unban":
			res = await Api.post("/api/staff/unban", {"username": username})
		"promote", "demote":
			var to: String = str(can["promote_to" if action == "promote" else "demote_to"])
			res = await Api.put("/api/staff/role", {"username": username, "role": to})
	_acting = false

	if not is_instance_valid(self) or not is_inside_tree():
		return

	if not res.get("ok", false):
		var status: int = int(res.get("status", 0))
		if status == 404:
			# The same answer for "no such account" and "out of your reach",
			# on purpose - see _moderation_target() in app.py.
			_say("Refused: %s is out of your reach (or gone)." % username, false)
		else:
			_say("Refused: %s" % str(res.get("error", "unknown error")), false)
		await _load("refresh")
		return

	var data: Variant = res.get("data", {})
	match action:
		"kick":
			var ended: int = int(data.get("sessions_ended", 0)) if data is Dictionary else 0
			if ended == 0:
				_say("%s had no live session - nothing to end." % username, true)
			else:
				_say("Kicked %s - they are back at the login screen within 15 seconds." % username, true)
		"ban":
			_say("Banned %s %s." % [username, "permanently" if days < 0 else "for %d day%s" % [days, "" if days == 1 else "s"]], true)
		"unban":
			_say("Unbanned %s. They can log in again." % username, true)
		"promote", "demote":
			_say("%s is now %s." % [username, str(data.get("role", "?")) if data is Dictionary else "?"], true)

	reason_input.text = ""
	# The record gains the line this just wrote, and the list its new state.
	await _load("refresh")
	await _load_record("fresh")


func _say(line: String, good: bool) -> void:
	notice_label.text = line
	notice_label.add_theme_color_override("font_color", COLOUR_OK if good else COLOUR_PROBLEM)
