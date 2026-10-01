# chatpanel.gd — four channels, pictures, and the one window the server talks in.
#
# WHAT THIS IS. A box in the bottom-left corner, above the menu bar, holding
# four conversations: the world, your friends, a private message, and a guild
# channel that is named and waiting for guilds to exist. It opens and closes
# from the Chat button; the rest of the HUD does not change shape around it.
#
# WHY BROADCASTS COME IN HERE AS WELL. The game already had a floating message
# box for server notices, and standing a chat window next to it would put two
# scrolling logs in the same corner arguing over the same space. A maintenance
# warning belongs in the conversation, tagged so it cannot be mistaken for
# somebody talking. When this panel is CLOSED the floating box still pops, so a
# player who never opens chat still gets told the server is going down —
# characterhud.gd decides which of the two gets the line.
#
# WHY THE LOG IS A LIST OF NODES AND NOT ONE RichTextLabel. It used to be one,
# which is simpler for text and cannot hold a picture: an image appended to a
# RichTextLabel is lost the moment the log is rebuilt, and the log is rebuilt
# every time you change channel. A VBox of per-message nodes costs more lines
# here and makes a picture just another kind of row.
#
# POLLING ONLY WHILE OPEN, and only the channel you are looking at. A closed
# window that keeps asking is a request every few seconds, forever, for text
# nobody is reading - and four channels polling at once is four of those.
extends Control

# Api's static helpers, called on the script and not on the autoload: a static
# function called through an instance is a warning in the editor's debugger.
const ApiScript := preload("res://src/systems/api.gd")


# HOW OFTEN AN OPEN WINDOW ASKS. Chat is a conversation and three seconds is
# already at the edge of feeling slow; the broadcast poll next door runs at ten
# because a restart notice can afford to be late and a reply cannot.
const POLL_SECONDS := 3.0

# Matches MAX_CHAT_LENGTH in app.py. Enforced here as well as there so an
# over-long line is stopped at the keyboard rather than silently cut by the
# server after it has been sent.
const MAX_LENGTH := 200

# HOW MANY LINES A CHANNEL KEEPS before the oldest falls off the top. Per
# channel, not in total: a busy world channel must not be able to push a
# private conversation out of its own window.
const LINES_KEPT := 100

# The channels, in the order the tabs sit in. Mirrors CHAT_CHANNELS in app.py -
# a name here that the server does not know is a tab that answers 400.
const CHANNELS := ["world", "friends", "private", "guild"]
const CHANNEL_LABELS := {
	"world": "World",
	"friends": "Friends",
	"private": "Whisper",
	"guild": "Guild",
}

# HOW BIG A PICTURE IS DRAWN IN THE LOG - both ways.
#
# ONLY THE WIDTH WAS CAPPED, and that is a bug you only see with a tall
# picture. A phone photograph is 3 by 4, so at 300 across it was drawn 400
# down - taller than the entire chat panel - and one of them pushed the whole
# conversation off the screen. The log is a conversation, not a gallery.
#
# SMALL ON PURPOSE, NOW THAT IT OPENS. Clicking a picture shows it properly at
# full size, so the version in the log only has to be big enough to recognise
# and to decide whether to open. Both numbers are applied, and whichever is
# tighter for that picture wins - so a wide panorama and a tall portrait both
# end up taking about the same amount of the conversation.
const IMAGE_MAX_WIDTH := 300.0

# THE CEILING, AND A SHARE OF THE ROOM. The panel is resizable - it is a good
# deal taller now than it was authored - and a fixed 140 that looked right in
# a short window is needlessly small in a tall one. So a picture may take up
# to this many pixels OR the share of the visible log below, whichever is
# smaller, with the absolute number stopping a very tall panel from turning
# the log back into a gallery.
const IMAGE_MAX_HEIGHT := 220.0
const IMAGE_MAX_LOG_SHARE := 0.45

# Never smaller than this, however cramped the panel gets. Below it a picture
# is not a picture, it is a smudge you cannot decide whether to open.
const IMAGE_MIN_HEIGHT := 72.0

# The dimmed sheet behind an opened picture, and how much of the window it may
# use. Not the whole window: the edges are what make it read as something
# laid over the game rather than a scene change.
const VIEWER_DIM := Color(0, 0, 0, 0.82)
const VIEWER_MARGIN := 48.0
const VIEWER_LAYER := 128

# =============================================================================
# SENDING A PICTURE
# =============================================================================
# FOUR WAYS IN, ONE WAY OUT. Ctrl+V a copied picture, drag a file onto the
# window, press + and browse, or paste a link - and all four end at the same
# place: a picture waiting in the composer that goes when you press Enter.
#
# NOTHING IS UPLOADED UNTIL YOU SEND. The server allows one picture every
# eight seconds, and spending that budget the moment somebody pastes means a
# paste they immediately cancel costs them the next eight seconds of their
# real message. So a pasted picture is held here, shown as a preview, and only
# leaves the machine when it is actually being said.
#
# THE SERVER'S LIMITS, REPEATED HERE ON PURPOSE. These three numbers match
# IMAGE_MAX_BYTES and IMAGE_MAX_SIDE in app.py. Knowing them means a 4K
# screenshot is shrunk to something that will be accepted BEFORE it is sent,
# rather than travelling for ten seconds to be refused. If the server's
# numbers change, these follow - they are a courtesy, not the enforcement.
const UPLOAD_MAX_BYTES := 8 * 1024 * 1024
const UPLOAD_MAX_MB := 8
const UPLOAD_MAX_SIDE := 1024

# WHEN TO STOP COMPRESSING. Under this, a lossless PNG is left alone: there is
# nothing to win by throwing detail away to save bytes nobody is short of, and
# the upload is already quick. Over it, quality comes down a step at a time.
const UPLOAD_COMFORTABLE_BYTES := 900 * 1024

# Tried in order, best first, and the search stops at the first size that is
# comfortable rather than grinding all the way down.
const UPLOAD_WEBP_LADDER := [0.90, 0.82, 0.72, 0.60]

# How far each pass shrinks a picture that will not fit even at the lowest
# quality. 0.6 rather than 0.5 so the result is not needlessly small - four
# passes still take a 1024px picture under 140px, which nothing real needs.
const UPLOAD_SHRINK_STEP := 0.6
const UPLOAD_SHRINK_PASSES := 4
const UPLOAD_SHRINK_FLOOR := 96

# What the file picker offers and what a dropped file has to be. Also what a
# link has to end in before it is treated as a picture rather than as text.
const UPLOAD_KINDS := ["png", "jpg", "jpeg", "gif", "webp", "bmp"]

# Longer than an ordinary call, because this one is carrying megabytes over
# whatever connection the player has.
const UPLOAD_TIMEOUT := 30.0

# The thumbnail beside the pending picture. Small on purpose: it is a reminder
# of what is attached, not a preview of how it will look.
const ATTACH_THUMB_SIDE := 128

# Kept so the placeholder can go back to what the scene set after a picture is
# sent or taken off.
const ENTRY_PLACEHOLDER := "Say something, or paste a picture with Ctrl+V..."
const ENTRY_PLACEHOLDER_ATTACHED := "Add something to say, or just hit Enter"
# A browser hands a page text from the clipboard, never a picture, so there the
# box points at the two ways that do work: + and dropping a file on the game.
const ENTRY_PLACEHOLDER_WEB := "Say something, or drop a picture on the game..."

# HOW A NAME IS DRAWN: in the colour its player chose, with the owner's crown
# or a MOD / DEV badge in front. It used to be the rank's colour, and the crown
# lived here as a constant of its own; both moved to nametag.gd, which every
# list that draws a name shares, so a crown in chat and a crown in the friends
# list cannot drift apart. The crown is still inline BBCode at the art's own
# 26x15 - a line of chat is one label and the badge has to flow with it.
const NameTag := preload("res://src/shared/nametag.gd")
const ChatFilter := preload("res://src/ui/chat/chatfilter.gd")
const WebPage := preload("res://src/systems/webpage.gd")

# The tint on the tab you are reading, against the ones you are not.
const TAB_ON := Color(1.0, 0.88, 0.62)
const TAB_OFF := Color(0.6, 0.56, 0.5)
const TAB_UNREAD := Color(1.0, 0.78, 0.35)


var _channel: String = "world"
var _whisper_with: String = ""
var _in_flight: bool = false
var _sending: bool = false

# channel -> {"cursor": int, "lines": Array[Dictionary], "unread": bool}
var _feeds: Dictionary = {}

# image id -> {"meta": Dictionary, "frames": Array[Texture2D]}
var _pictures: Dictionary = {}
var _fetching: Dictionary = {}

# Every animated picture currently on screen, so one _process can drive all of
# them instead of each one owning a Timer.
var _playing: Array = []

# The picture waiting to be sent: {"bytes": PackedByteArray, "name": String}.
# Empty when there is none. See the note over UPLOAD_MAX_BYTES for why the
# bytes sit here rather than on the server.
var _pending: Dictionary = {}

# Built the first time somebody presses +, then kept. A FileDialog is a window
# and making a new one per press leaks them.
var _file_dialog: FileDialog = null

# The opened-picture overlay, built once on first use. Its own CanvasLayer:
# this panel is 460 wide in the bottom-left corner, and a full-size picture
# has to escape that to cover the window.
var _viewer: CanvasLayer = null
var _viewer_frame: TextureRect = null
var _viewer_caption: Label = null
var _viewing: String = ""

# Seconds until a picture may go to world again, and the clock this machine
# read it at. From the poll, so somebody is told the wait BEFORE they pick a
# file and compress it - see _world_wait_left().
var _world_wait: int = 0
var _world_wait_read_at: float = 0.0

@onready var lines_box: VBoxContainer = get_node_or_null("%chatlines")
@onready var scroll: ScrollContainer = get_node_or_null("%chatscroll")
@onready var tabs_box: HBoxContainer = get_node_or_null("%chattabs")
@onready var entry: LineEdit = get_node_or_null("%chatentry")
@onready var send_button: Button = get_node_or_null("%chatsendbutton")
@onready var image_button: Button = get_node_or_null("%chatimagebutton")
@onready var close_button: Button = get_node_or_null("%chatclosebutton")
@onready var notice: Label = get_node_or_null("%chatnotice")
@onready var whisper_to: LineEdit = get_node_or_null("%chatto")
@onready var whisper_label: Label = get_node_or_null("%chattolabel")
@onready var attach_row: PanelContainer = get_node_or_null("%attachrow")
@onready var attach_thumb: TextureRect = get_node_or_null("%attachthumb")
@onready var attach_name: Label = get_node_or_null("%attachname")
@onready var attach_size: Label = get_node_or_null("%attachsize")
@onready var attach_remove: Button = get_node_or_null("%attachremove")


# Drag by the header, resize from any edge, and come back where it was left.
# One component for all sixteen panels - see src/shared/panelwindow.gd for why
# this is not thirty lines copied into each of them.
#
# HELD IN A MEMBER, not discarded. It is a RefCounted carrying the drag state
# and the signal connections; letting it go frees it and the panel quietly
# stops responding.
var _window: PanelWindow


func _ready() -> void:
	_window = PanelWindow.attach(self, "chat")
	add_to_group("chatpanel")
	visible = false

	for channel in CHANNELS:
		_feeds[channel] = {"cursor": 0, "lines": [], "unread": false}

	_build_tabs()

	if entry != null:
		entry.max_length = MAX_LENGTH
		entry.placeholder_text = entry_placeholder(WebPage.in_browser())
		entry.text_submitted.connect(_on_entry_submitted)
	if send_button != null:
		send_button.pressed.connect(_on_send_pressed)
	if image_button != null:
		image_button.pressed.connect(_on_image_pressed)
	if close_button != null:
		close_button.pressed.connect(close)
	if whisper_to != null:
		whisper_to.text_changed.connect(_on_whisper_target_changed)
	if attach_remove != null:
		attach_remove.pressed.connect(_clear_pending)

	_clear_pending()

	# A DROPPED FILE IS HANDED TO THE WINDOW, not to whatever is under the
	# cursor - the operating system gives it to the application and Godot
	# passes the whole lot along. So this is connected once, at the window, and
	# the handler decides whether the chat was in a position to want it.
	var window: Window = get_window()
	if window != null and not window.files_dropped.is_connected(_on_files_dropped):
		window.files_dropped.connect(_on_files_dropped)

	_set_notice("")
	_build_new_below()
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)
	_show_channel("world")

	var timer := Timer.new()
	timer.name = "ChatPoll"
	timer.wait_time = POLL_SECONDS
	timer.one_shot = false
	timer.autostart = true
	timer.timeout.connect(_on_poll_timeout)
	add_child(timer)

	set_process(false)


# =============================================================================
# OPENING AND CLOSING
# =============================================================================

func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	visible = true
	set_process(not _playing.is_empty())

	# A WHISPER WAITING OPENS ON IT. The HUD said "X whispers: ..." and lit the
	# Chat button; the window opened next shows that conversation, not World.
	if _whisper_waiting and last_whisper_from != "":
		_whisper_waiting = false
		_aim_whisper(last_whisper_from)
		_show_channel("private")
	else:
		# START FROM THE TAIL, NOT FROM WHERE WE LEFT OFF. A cursor kept across a
		# close would ask for everything said since, which after an hour away is a
		# page of context nobody wants and a truncated page at that. Zero means
		# "give me the recent conversation", which is what opening a chat window
		# is asking for.
		_reset_feed(_channel)
		_render()
		_poll()

	if entry != null:
		# FOCUS GOES TO THE BOX, because opening chat is something you do in
		# order to type. player.gd's _typing_in_ui() sees the focused LineEdit
		# and stops polling movement and attack, so the keyboard belongs to
		# the conversation until the box is closed or clicked away from.
		entry.grab_focus()


func close() -> void:
	close_viewer()
	visible = false
	set_process(false)
	if entry != null:
		entry.release_focus()


func is_open() -> bool:
	return visible


# =============================================================================
# THE TABS
# =============================================================================

func _build_tabs() -> void:
	if tabs_box == null:
		return
	for channel in CHANNELS:
		var tab := Button.new()
		tab.name = "tab_" + channel
		tab.text = String(CHANNEL_LABELS.get(channel, channel))
		tab.focus_mode = Control.FOCUS_NONE
		tab.add_theme_font_size_override("font_size", 11)
		tab.tooltip_text = _tab_hint(channel)
		tab.pressed.connect(_show_channel.bind(channel))
		tabs_box.add_child(tab)


func _tab_hint(channel: String) -> String:
	match channel:
		"world":
			return "Everyone playing"
		"friends":
			return "You and the people who accepted your friend request"
		"private":
			return "One person, and nobody else can read it"
		"guild":
			# It said "Waiting on guilds" long after guild chat went live.
			return "Your guild, and only its members"
	return ""


func _paint_tabs() -> void:
	if tabs_box == null:
		return
	for channel in CHANNELS:
		var tab: Button = tabs_box.get_node_or_null("tab_" + channel) as Button
		if tab == null:
			continue
		var colour: Color = TAB_OFF
		if channel == _channel:
			colour = TAB_ON
		elif bool(_feeds[channel].get("unread", false)):
			# SOMETHING ARRIVED WHILE YOU WERE LOOKING SOMEWHERE ELSE. Only
			# ever set by a poll of that channel, which happens when you visit
			# it - so this marks "there was more than fitted", not "somebody is
			# talking right now". Honest about what it knows.
			colour = TAB_UNREAD
		tab.add_theme_color_override("font_color", colour)


func _show_channel(channel: String) -> void:
	if not CHANNELS.has(channel):
		return
	_channel = channel
	_feeds[channel]["unread"] = false
	_set_notice("")

	var whispering: bool = channel == "private"
	if whisper_to != null:
		whisper_to.visible = whispering
	if whisper_label != null:
		whisper_label.visible = whispering

	_paint_tabs()
	_render()

	# THE ONLY CHANNEL THIS CLIENT REFUSES ON ITS OWN is a whisper to nobody.
	# Whether you may read or write guild chat is the SERVER's question - it
	# knows whether you are in a guild - and it answers it; see _apply_read().
	var refusal: String = _local_refusal(channel)
	if refusal != "":
		_set_notice(refusal)
		return

	# A CHANNEL IS RE-READ FROM ITS TAIL WHEN YOU SWITCH TO IT, for the same
	# reason opening the window is: what you want when you look at a
	# conversation is the last of it, not everything since you last looked.
	_reset_feed(channel)
	_poll()


# =============================================================================
# WHAT WAS SAID TO YOU ELSEWHERE
# =============================================================================
# This window reads only the tab that is open, while it is open. The HUD's
# broadcast poll reports what was said to this player everywhere else
# (chat_news, _chat_news() in app.py) and hands it here.

# Who whispered last: /r answers them, and a waiting whisper opens on them.
var last_whisper_from: String = ""
var _whisper_waiting: bool = false


func whisper_arrived(who: String) -> void:
	"""Somebody whispered this player. The Whisper tab lights and is aimed at
	them, unless another conversation is already in it; if the window is shut,
	it opens on them next time."""
	if who == "":
		return
	last_whisper_from = who
	if visible and _channel == "private" and _whisper_with.to_lower() == who.to_lower():
		return
	# AN EMPTY WHISPER BOX TAKES THE NAME; one already in use keeps it. A
	# window that is shut is aimed when it opens (open()).
	if _whisper_with == "":
		_aim_whisper(who)
	_feeds["private"]["unread"] = true
	_paint_tabs()
	if not visible:
		_whisper_waiting = true
	else:
		# OPEN ON ANOTHER TAB, OR ANOTHER CONVERSATION: say it where the
		# player is looking, and how to answer.
		_set_notice("%s whispered you. /r to answer." % who)


func room_news(room: String) -> void:
	"""A new line in the guild or among friends while this tab is not open."""
	if not _feeds.has(room) or (visible and _channel == room):
		return
	_feeds[room]["unread"] = true
	_paint_tabs()


func _aim_whisper(who: String) -> void:
	_whisper_with = who
	if whisper_to != null:
		whisper_to.text = who


func _on_whisper_target_changed(text: String) -> void:
	var wanted: String = text.strip_edges()
	if wanted == _whisper_with:
		return
	_whisper_with = wanted
	if _channel != "private":
		return
	_reset_feed("private")
	_render()
	if _whisper_with == "":
		_set_notice("Type who you want to whisper to, up in the corner.")
	else:
		_set_notice("")
		_poll()


# =============================================================================
# WHAT GOES IN THE LOG
# =============================================================================

func push_system_line(text: String, colour: Color, at: int = 0) -> void:
	"""A server announcement, shown in the conversation and marked as one.

	`at` IS THE SERVER'S OWN TIMESTAMP, and passing it is the difference
	between a record and a guess. The broadcast table stamps every notice when
	it is WRITTEN, and the poll has always returned that - so the caller can
	say when a thing happened rather than when this client noticed it. They
	are the same number for a player who was already here and nothing like it
	for one who just logged in, which is precisely who the tail is for.

	0 MEANS "NOW", and it is right for exactly one kind of caller: a notice
	this client generated about itself, which has no server timestamp because
	the server was never involved. Defaulting rather than requiring keeps
	those callers honest-looking instead of making them invent a zero."""
	if text.strip_edges() == "":
		return
	# ALWAYS INTO THE WORLD CHANNEL. A maintenance notice is not a whisper and
	# it is not guild business; it belongs where everybody is looking.
	_add_line("world", {
		"kind": "system",
		"body": text,
		"colour": colour,
		"at": at if at > 0 else int(Time.get_unix_time_from_system()),
	})


func _add_line(channel: String, line: Dictionary) -> void:
	var feed: Dictionary = _feeds[channel]
	var kept: Array = feed["lines"]
	kept.append(line)

	# OLDEST OFF THE TOP, at LINES_KEPT. Without a ceiling a long session turns
	# the log into a slowly growing pile of nodes nobody can scroll back to.
	var trimmed: bool = false
	while kept.size() > LINES_KEPT:
		kept.pop_front()
		feed["unread"] = true
		trimmed = true

	# AND THE SAME CEILING HAS TO REACH THE PICTURES. _pictures held every image
	# anybody had ever posted, decoded, for the whole session - the line above it
	# was long gone and the frames were not. Swept here rather than on a timer,
	# because this is the moment a line stops being reachable.
	if trimmed:
		_sweep_pictures()

	if channel == _channel and visible:
		_append_to_log()
	elif channel != _channel:
		feed["unread"] = true
		_paint_tabs()


# How close to the end of the log still counts as "reading the newest".
const AT_BOTTOM_SLACK := 24

# Set by a send that went through: the player's own line brings the log to the
# end even if they had scrolled up to read, because they just spoke.
var _stick_to_bottom: bool = false


func _append_to_log() -> void:
	"""The newest line of the open channel onto the log, and the oldest off it
	when the feed has trimmed one - without rebuilding the rest.

	THIS USED TO BE _render() FOR EVERY LINE, and that did two things wrong.
	Every line destroyed and rebuilt the whole log - measured, 35 ms a line
	with fifty kept, so a busy world chat stuttered the game while it was
	open. And every rebuild scrolled to the end, so a player who had scrolled
	up to read was pulled back down whenever anybody spoke.

	Now the log follows new lines only when the player is already reading the
	newest ones, or has just sent one."""
	if lines_box == null or _redraw_on_next_read:
		return
	var lines: Array = _feeds[_channel]["lines"]
	if lines.is_empty():
		return
	# A POLL'S LINES ARRIVE TOGETHER, in one frame, and the layout does not
	# catch up between them - so the first one decides for the batch
	# (_apply_read), and the batch scrolls once at the end.
	var follow: bool = _batch_follow if _batching else _should_follow()

	var node: Control = _node_for(lines[-1])
	if node != null:
		lines_box.add_child(_with_staff_controls(lines[-1], node))

	# THE OLDEST LEAVES THE SCREEN WHEN IT LEAVES THE FEED, and a reader
	# further up keeps their place: the log above them got shorter by exactly
	# that line, so the scroll moves up by it.
	var gap: float = float(lines_box.get_theme_constant("separation"))
	var dropped: float = 0.0
	while lines_box.get_child_count() > lines.size():
		var oldest: Node = lines_box.get_child(0)
		if oldest is Control:
			dropped += (oldest as Control).size.y + gap
		lines_box.remove_child(oldest)
		oldest.queue_free()

	set_process(visible and not _playing.is_empty())
	if follow:
		if not _batching:
			_scroll_to_end.call_deferred()
	else:
		_show_new_below(true)
		if dropped > 0.0 and scroll != null:
			scroll.scroll_vertical = maxi(0, scroll.scroll_vertical - int(dropped))


var _batching: bool = false
var _batch_follow: bool = false


func _should_follow() -> bool:
	"""Whether the log should go to the end for what arrives next: the player
	just spoke, the log is empty (a tab just opened), or they are reading the
	newest lines already."""
	var follow: bool = _stick_to_bottom or lines_box == null \
		or lines_box.get_child_count() == 0 or _at_bottom()
	_stick_to_bottom = false
	return follow


func _at_bottom() -> bool:
	if scroll == null or not is_instance_valid(scroll):
		return true
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	return float(scroll.scroll_vertical) + bar.page >= bar.max_value - AT_BOTTOM_SLACK


func _remove_lines(channel: String, ids: Array) -> int:
	"""Take lines back out of a feed, because the server says they are gone.

	THE FEED USED TO BE APPEND-ONLY, AND THAT MADE IT UNMODERATABLE. _poll()
	asks for messages with an id past its cursor and calls _add_line(); the only
	way a line ever left was pop_front() at LINES_KEPT. So a mod deleting a
	message stopped it reaching anybody who had not read it yet and did nothing
	at all about the people who had - it sat on their screen until a hundred
	more lines pushed it off, or until they closed the game. The set of players
	who kept seeing it is exactly the set the deletion was for.

	The server now reports `removed` on every poll (see CHAT_DELETION_WINDOW_
	SECONDS in app.py), filtered by the same permission clause as the messages,
	so a line this client was never allowed to read cannot arrive here either.

	Returns how many lines actually went, so the caller only re-renders when
	something changed. Almost every poll carries an empty list.
	"""
	if ids.is_empty() or not _feeds.has(channel):
		return 0

	# A SET, because `removed` repeats for as long as the window lasts - the same
	# id comes back on forty consecutive polls by design, and `has` on a
	# Dictionary beats walking the array once per line.
	var doomed: Dictionary = {}
	for raw_id in ids:
		var id: int = int(raw_id)
		if id > 0:
			doomed[id] = true
	if doomed.is_empty():
		return 0

	var kept: Array = _feeds[channel]["lines"]
	var survivors: Array = []
	var went: int = 0
	var lost_pictures: Dictionary = {}
	for line in kept:
		if line is Dictionary and doomed.has(int(line.get("id", 0))):
			went += 1
			var image_id: String = str(line.get("image", ""))
			if image_id != "":
				lost_pictures[image_id] = true
			continue
		survivors.append(line)
	if went == 0:
		return 0
	_feeds[channel]["lines"] = survivors

	# THE OPEN VIEWER IS THE CASE THAT MAKES THIS WORTH DOING PROPERLY. A player
	# looking at the picture full-screen when a mod deletes it is the person most
	# needing it to go away, and _sweep_pictures() deliberately SPARES _viewing -
	# correctly, for its own job - so sweeping first would keep the picture alive
	# and leave the overlay up. Close it before the sweep, not after.
	if _viewing != "" and lost_pictures.has(_viewing):
		close_viewer()

	# And then the existing sweep does the rest, unchanged: it rebuilds the live
	# set from whatever the feeds still hold, so a picture whose last line just
	# went is dropped without this function knowing anything about ids.
	if not lost_pictures.is_empty():
		_sweep_pictures()

	return went


func _render(keep_place: bool = false) -> void:
	# keep_place: a reader scrolled up stays where they were - for a line taken
	# down, which is not news. Opening the log or changing tab goes to the end.
	if lines_box == null:
		return
	var reading_at: int = -1
	if keep_place and not _at_bottom():
		reading_at = scroll.scroll_vertical

	for child in lines_box.get_children():
		lines_box.remove_child(child)
		child.queue_free()
	_playing.clear()

	for line in _feeds[_channel]["lines"]:
		if not (line is Dictionary):
			continue
		var node: Control = _node_for(line)
		if node != null:
			lines_box.add_child(_with_staff_controls(line, node))

	set_process(visible and not _playing.is_empty())

	# TO THE BOTTOM, AFTER A FRAME. The ScrollContainer does not know how tall
	# its contents are until the layout has run, so asking it to scroll to the
	# end right now scrolls it to the end of the OLD contents.
	if reading_at >= 0:
		_scroll_to.call_deferred(reading_at)
	else:
		_show_new_below(false)
		_scroll_to_end.call_deferred()


func _scroll_to(at: int) -> void:
	if scroll == null or not is_instance_valid(scroll):
		return
	await get_tree().process_frame
	if is_instance_valid(scroll):
		scroll.scroll_vertical = at


func _scroll_to_end() -> void:
	if scroll == null or not is_instance_valid(scroll):
		return
	await get_tree().process_frame
	if not is_instance_valid(scroll):
		return
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


# =============================================================================
# TAKING A LINE DOWN
# =============================================================================
# A small x on the right of every message, for staff only.
#
# THE SERVER DECIDES, NOT THIS. /api/chat/delete is behind require_role("mod")
# and refuses anything above the caller through can_act_on() - a mod cannot
# delete the owner. Hiding the button from players is a courtesy so they are
# not offered something that would be refused; it is not the protection. A
# modified client that draws the button anyway gets a 404 from the server.
#
# ONE CLICK, NOT TWO. The point of this is dealing with somebody spamming, and
# a confirmation on every line makes that ten clicks instead of five. What it
# costs is that a misclick removes a line with no undo - so the notice
# afterwards names whose line it was, which is the difference between noticing
# a mistake and not.

func _with_staff_controls(line: Dictionary, node: Control) -> Control:
	var message_id: int = int(line.get("id", 0))
	if message_id <= 0 or not Api.role_at_least("mod"):
		return node

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(node)

	var who: String = str(line.get("by", "somebody"))
	var button := Button.new()
	button.text = "x"
	button.tooltip_text = "Delete this message from %s. There is no undo." % who
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(18, 18)
	# SHRINK_CENTER so the button sits beside a one-line message rather than
	# stretching down the side of a tall one with a picture in it.
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override("font_color", Color(0.78, 0.45, 0.4))
	button.pressed.connect(_delete_message.bind(message_id, who))
	row.add_child(button)

	return row


func _delete_message(message_id: int, who: String) -> void:
	if _sending:
		return
	_sending = true
	_set_notice("Removing...")

	var res: Dictionary = await Api.post("/api/chat/delete", {"id": message_id})

	if not is_instance_valid(self) or not is_inside_tree():
		return
	_sending = false

	if not res.get("ok", false):
		_set_notice(_refusal(res))
		push_warning("[CHAT] delete refused: HTTP %d - %s (message %d)" % [
			int(res.get("status", 0)), str(res.get("error", "")), message_id])
		return

	_set_notice("Removed %s's message." % who)

	# READ THE CHANNEL AGAIN FROM ITS TAIL. The line is gone on the server, and
	# the only honest way to show that is to ask what is there now - dropping
	# it from the local list would leave this client's idea of the log one edit
	# ahead of everyone else's.
	_reset_feed(_channel)
	_render()
	_poll()


func _node_for(line: Dictionary) -> Control:
	var kind: String = str(line.get("kind", "chat"))

	if kind == "image":
		return _picture_node(line)

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", 13)
	# THE EMOJI FONT RIDES ALONG HERE. The entry box gets it from the scene;
	# these labels are built in code, so they are handed the same one. Without
	# it every pasted emoji is a blank box.
	var typeface: Font = _chat_font()
	if typeface != null:
		label.add_theme_font_override("normal_font", typeface)

	if kind == "system":
		var colour: Color = line.get("colour", Color(1.0, 0.82, 0.42))
		var hex: String = colour.to_html(false)
		# THE ONE LINE THAT MOST NEEDED A TIME WAS THE ONE THAT HAD NONE.
		#
		# This branch returned before the stamp below was ever reached, so
		# every player line carried a clock and every SERVER line did not -
		# and the server lines are the ones a player is handed in bulk the
		# moment they log in. "Tunacan has gone hostile." with no time on it
		# reads as now, whether it happened four seconds or four days ago.
		label.append_text("[color=#6b6055]%s[/color] [color=#%s][SERVER][/color] [color=#%s]%s[/color]"
			% [LocalTime.stamp(int(line.get("at", 0))), hex, hex,
				_escape(str(line.get("body", "")))])
		return label

	var who: String = str(line.get("by", "?"))
	var rank: String = str(line.get("role", "player"))
	var stamp: String = LocalTime.stamp(int(line.get("at", 0)))
	# YOUR OWN NAME IS MARKED. In a channel everybody can write to, finding
	# where you last spoke is otherwise a scan of the whole box.
	var mark: String = " <" if who.to_lower() == Api.username.to_lower() else ""

	# CROWN OR BADGE, GUILD, NAME. The hue and the rank are a snapshot on the
	# line - what it was said with - so an old line keeps the colour it was
	# written in, exactly as it keeps the guild it was said from.
	label.append_text("[color=#6b6055]%s[/color] %s%s%s: %s" % [
		stamp, NameTag.bbcode_mark(rank), _guild_part(line),
		_clickable_name(line, NameTag.bbcode_name(_escape(who) + mark, line.get("name_hue"))),
		_escape(shown_text(str(line.get("body", "")), _filtering()))])
	_wire_name_click(label, line)
	return label


func _guild_part(line: Dictionary) -> String:
	"""The guild tag, coloured and ready to sit before a name. "" for no guild.

	BEFORE THE NAME, AFTER THE CROWN. A rank is a fact about the person and a
	guild is a fact about who they run with, so the guild reads as the thing
	they arrived with rather than as part of what they are called.

	ESCAPED, LIKE EVERYTHING ELSE THAT REACHES THIS RENDERER. The tag comes
	from a guild name somebody chose, and it arrives wrapped in square brackets
	- which is the one character this log must never hand the renderer raw. See
	_escape(): "[img]some-url[/img] makes the client FETCH that url". The
	server's pattern already refuses a bracket inside a name, so this is the
	second lock on a door that is bolted, which is the correct number of locks
	for a public channel."""
	var tag: String = Api.guild_tag_text(str(line.get("guild_tag", "")))
	if tag == "":
		return ""
	return "[color=#%s]%s[/color] " % [
		Api.GUILD_TAG_COLOUR.to_html(false), _escape(tag)]


# The chat typeface, with the bundled colour emoji font behind it. Pulled off
# the entry box rather than loaded again so there is one copy in memory and one
# statement of what chat is set in.
func _chat_font() -> Font:
	if entry == null:
		return null
	return entry.get_theme_font("font")


func _picture_node(line: Dictionary) -> Control:
	var image_id: String = str(line.get("image", ""))
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 2)

	var caption: String = shown_text(str(line.get("body", "")), _filtering())
	var who: String = str(line.get("by", "?"))
	var rank: String = str(line.get("role", "player"))
	var header := RichTextLabel.new()
	header.bbcode_enabled = true
	header.fit_content = true
	header.scroll_active = false
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_font_size_override("normal_font_size", 13)
	var typeface: Font = _chat_font()
	if typeface != null:
		header.add_theme_font_override("normal_font", typeface)
	# THE SAME HEADER AS A TEXT LINE, including the guild. A picture posted by
	# somebody in a guild that did not say so would be the one kind of message
	# where the tag went missing, and nobody would ever work out why.
	header.append_text("[color=#6b6055]%s[/color] %s%s%s: %s" % [
		LocalTime.stamp(int(line.get("at", 0))), NameTag.bbcode_mark(rank), _guild_part(line),
		_clickable_name(line, NameTag.bbcode_name(_escape(who), line.get("name_hue"))),
		_escape(caption) if caption != "" else "[color=#6b6055](a picture)[/color]"])
	_wire_name_click(header, line)
	holder.add_child(header)

	var frame := TextureRect.new()
	frame.name = "picture"
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# EXPAND_IGNORE_SIZE, AND THIS ONE LINE IS THE WHOLE BUG.
	#
	# A TextureRect's default expand_mode is EXPAND_KEEP_SIZE, which means it
	# demands its TEXTURE'S full size as its minimum. custom_minimum_size is a
	# FLOOR, not a ceiling, and layout uses get_combined_minimum_size() - the
	# larger of the two. So capping custom_minimum_size at 300x140 on a
	# 1024x768 photograph produced a combined minimum of 1024x768 and did
	# precisely nothing.
	#
	# WHY IT TOOK THE WHOLE PANEL WITH IT: the ScrollContainer has horizontal
	# scrolling disabled, and a ScrollContainer that cannot scroll sideways
	# folds its content's width into its OWN minimum. So one wide photograph
	# pushed the chat window off the left edge of the screen.
	#
	# The viewer had this set from the start, which is why opening a picture
	# always looked right while the log did not.
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.custom_minimum_size = Vector2(0, 24)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	holder.add_child(frame)

	if _pictures.has(image_id):
		_dress_picture(frame, image_id)
	else:
		_fetch_picture(image_id, frame)

	return holder


func _dress_picture(frame: TextureRect, image_id: String) -> void:
	var held: Dictionary = _pictures[image_id]
	var frames: Array = held.get("frames", [])
	if frames.is_empty():
		return

	frame.texture = frames[0]
	var meta: Dictionary = held.get("meta", {})
	var wide: float = float(meta.get("width", 64))
	var tall: float = float(meta.get("height", 64))

	# WHICHEVER LIMIT BITES FIRST. One scale for both axes, so nothing is
	# squashed - a picture is either small enough already or shrunk until both
	# its width and its height fit.
	var width_cap: float = IMAGE_MAX_WIDTH
	var height_cap: float = IMAGE_MAX_HEIGHT
	if scroll != null and is_instance_valid(scroll) and scroll.size.y > 1.0:
		# MEASURED FROM THE LOG AS IT ACTUALLY IS. Before the first layout the
		# scroll has no size, which is why the constants are the fallback
		# rather than the other way round.
		height_cap = min(height_cap, scroll.size.y * IMAGE_MAX_LOG_SHARE)
		width_cap = min(width_cap, max(64.0, scroll.size.x - 24.0))
	height_cap = max(IMAGE_MIN_HEIGHT, height_cap)

	var scale_down: float = min(1.0,
		min(width_cap / max(wide, 1.0), height_cap / max(tall, 1.0)))
	frame.custom_minimum_size = Vector2(wide * scale_down, tall * scale_down)

	# AND IT OPENS. The thumbnail above is deliberately small, which is only
	# reasonable because the full thing is one click away.
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.tooltip_text = "Click to see it full size (%d x %d)" % [int(wide), int(tall)]
	if not frame.gui_input.is_connected(_on_picture_clicked):
		frame.gui_input.connect(_on_picture_clicked.bind(image_id))

	if frames.size() > 1:
		_playing.append({
			"node": frame,
			"frames": frames,
			"frame_ms": max(20, int(meta.get("frame_ms", 100))),
			"at": 0.0,
			"index": 0,
		})
		set_process(visible)


func _process(delta: float) -> void:
	# ONE LOOP FOR EVERY ANIMATION ON SCREEN, rather than a Timer per picture.
	# A log with a dozen GIFs in it would otherwise be a dozen timers, all
	# firing at slightly different moments for no benefit.
	var alive: Array = []
	for play in _playing:
		var node: TextureRect = play["node"]
		if not is_instance_valid(node):
			continue
		alive.append(play)
		play["at"] += delta * 1000.0
		var step: float = float(play["frame_ms"])
		while play["at"] >= step:
			play["at"] -= step
			play["index"] = (int(play["index"]) + 1) % play["frames"].size()
			node.texture = play["frames"][int(play["index"])]
	_playing = alive
	if _playing.is_empty():
		set_process(false)


static func shown_text(text: String, filtered: bool) -> String:
	"""A player's words as the chat window draws them: one line, and with the
	language filter over them when the player has it on. The HUD's whisper
	pop-up uses this too, so the two never disagree."""
	var line: String = one_line(text)
	return ChatFilter.clean(line) if filtered else line


func _filtering() -> bool:
	return bool(Settings.get_value("chat_filter"))


static func one_line(text: String) -> String:
	"""A player's message as one line with nothing invisible in it: the
	server's clean_player_text() done again as it is drawn, for lines stored
	before that rule or by a server without it. A newline, tab or control
	character is a space; a bidi override, zero-width space or other invisible
	format character is dropped (ZWJ stays, for emoji); runs of spaces are one.
	One message of 150 newlines used to be 150 blank lines on every screen."""
	var out := PackedStringArray()
	var last_was_space := true
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code < 32 or code == 127 or (code >= 0x80 and code < 0xA0) \
				or code == 0x2028 or code == 0x2029 or code == 0xA0:
			code = 32
		elif _is_invisible(code):
			continue
		if code == 32:
			if last_was_space:
				continue
			last_was_space = true
		else:
			last_was_space = false
		out.append(String.chr(code))
	return "".join(out).strip_edges()


static func _is_invisible(code: int) -> bool:
	# Unicode's format characters (category Cf) that change nothing but what a
	# line looks like, less U+200D, which joins emoji.
	return code == 0x00AD or code == 0x061C or code == 0x180E \
		or code == 0x200B or code == 0x200C or code == 0x200E or code == 0x200F \
		or (code >= 0x202A and code <= 0x202E) or (code >= 0x2060 and code <= 0x2064) \
		or (code >= 0x2066 and code <= 0x206F) or code == 0xFEFF \
		or (code >= 0xFFF9 and code <= 0xFFFB) or (code >= 0xE0000 and code <= 0xE007F)


func _escape(text: String) -> String:
	# THE ONE THING A PUBLIC CHANNEL MUST NOT DO is hand the renderer whatever
	# somebody typed. This log renders BBCode so staff ranks can be coloured,
	# and BBCode is not only colour: [img]some-url[/img] makes the client
	# FETCH that url, and [url] makes a clickable link out of it. Turning every
	# opening bracket into the literal-bracket tag means a message can say
	# "[color=red]" and that is exactly what everyone reads.
	return text.replace("[", "[lb]")


# _clock() USED TO LIVE HERE and it is now LocalTime.stamp(). It was one of
# four copies of "unix seconds plus the system bias, then decompose", and the
# copy in ownerpanel.gd had lost the bias entirely and was printing UTC. Four
# copies is how that happens; see src/shared/localtime.gd.


# The notice the server gave for a room this player may not read, so the
# moment it opens up - a guild founded with the tab open - exactly that notice
# is taken down. See _apply_read().
var _room_notice: String = ""


func _set_notice(text: String) -> void:
	if notice == null:
		return
	notice.text = text
	notice.visible = text != ""


# =============================================================================
# PICTURES
# =============================================================================

func _fetch_picture(image_id: String, frame: TextureRect) -> void:
	if image_id == "" or _fetching.has(image_id):
		return
	_fetching[image_id] = true

	var res: Dictionary = await Api.get_bytes("/api/chat/image/%s" % image_id)

	if not is_instance_valid(self) or not is_inside_tree():
		return
	_fetching.erase(image_id)

	if not res.get("ok", false):
		return

	var picture := Image.new()
	if not _decode_picture(picture, res.get("bytes", PackedByteArray())):
		return

	var meta: Dictionary = _feeds_meta(image_id)
	_pictures[image_id] = {
		"meta": meta,
		"frames": _slice_sheet(picture, meta),
	}

	if is_instance_valid(frame):
		_dress_picture(frame, image_id)


# =============================================================================
# SEEING A PICTURE PROPERLY
# =============================================================================
# The log draws a thumbnail. This is where the actual picture goes.
#
# A CanvasLayer, NOT A CHILD CONTROL. The chat panel is 460x340 pinned to the
# bottom-left corner, and anything parented inside it is clipped to that. A
# CanvasLayer's children are laid out in screen space whatever their parent is
# doing, which is exactly what "cover the window" needs.
#
# BUILT ON FIRST USE AND KEPT. Nobody opens a picture in most sessions, and
# the nodes cost nothing while they do not exist.

func _on_picture_clicked(event: InputEvent, image_id: String) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	if click.button_index != MOUSE_BUTTON_LEFT:
		return
	_open_viewer(image_id)


func _sweep_pictures() -> void:
	"""Drop decoded pictures no line can reach any more.

	WHY THIS EXISTS. _add_line caps each channel's log at LINES_KEPT and its
	comment is explicit about why: an uncapped log is a slowly growing pile of
	nodes. That cap was applied to the LINES and not to the pictures, so
	_pictures kept the decoded frames of every image ever posted, keyed by id,
	for as long as the session lasted. The line scrolled away; the memory did
	not. In a busy world channel with UPLOAD_MAX_SIDE at 1024 that is megabytes
	per picture, and animated ones hold one texture per frame.

	It is a sweep rather than an eviction policy on purpose. An LRU would need a
	size to tune and a guess at the right number; the log's own window is
	already the correct answer, because an image nothing can scroll to is an
	image nobody can ask to see.

	NOTHING ON SCREEN BREAKS. Textures are reference counted, so a thumbnail or
	the open viewer keeps its own frames alive after the id leaves this
	dictionary. _viewing is held anyway, so closing and reopening the overlay
	does not refetch.
	"""
	var live: Dictionary = {}
	for channel in CHANNELS:
		if not _feeds.has(channel):
			continue
		for line in _feeds[channel]["lines"]:
			if not (line is Dictionary):
				continue
			var id: String = str(line.get("image", ""))
			if id != "":
				live[id] = true
	if _viewing != "":
		live[_viewing] = true

	for id in _pictures.keys():
		if not live.has(id):
			_pictures.erase(id)


func _open_viewer(image_id: String) -> void:
	if not _pictures.has(image_id):
		return
	var held: Dictionary = _pictures[image_id]
	var frames: Array = held.get("frames", [])
	if frames.is_empty():
		return

	_build_viewer()
	_viewing = image_id

	var meta: Dictionary = held.get("meta", {})
	_viewer_frame.texture = frames[0]
	_viewer_caption.text = "%d x %d  -  click anywhere, or press Escape, to close" % [
		int(meta.get("width", 0)), int(meta.get("height", 0))]

	# AN ANIMATION KEEPS MOVING WHEN IT IS OPENED, through the same one loop
	# that drives every other one on screen rather than a second mechanism.
	_playing = _playing.filter(func(play): return play["node"] != _viewer_frame)
	if frames.size() > 1:
		_playing.append({
			"node": _viewer_frame,
			"frames": frames,
			"frame_ms": max(20, int(meta.get("frame_ms", 100))),
			"at": 0.0,
			"index": 0,
		})
		set_process(true)

	_viewer.visible = true


func close_viewer() -> void:
	_viewing = ""
	if _viewer != null:
		_viewer.visible = false
	if _viewer_frame != null:
		# DROPPED FROM THE ANIMATION LOOP, not merely hidden. A closed viewer
		# that is still being stepped every frame is work nobody can see.
		_playing = _playing.filter(func(play): return play["node"] != _viewer_frame)
		_viewer_frame.texture = null


func is_viewing() -> bool:
	return _viewing != ""


func _build_viewer() -> void:
	if _viewer != null:
		return

	_viewer = CanvasLayer.new()
	_viewer.name = "PictureViewer"
	_viewer.layer = VIEWER_LAYER
	_viewer.visible = false
	add_child(_viewer)

	# THE SHEET TAKES THE CLICK. Anywhere at all closes it - people expect a
	# lightbox to shut when they click it, and hunting for an x is a small
	# annoyance repeated every single time.
	var sheet := ColorRect.new()
	sheet.color = VIEWER_DIM
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed:
			close_viewer())
	_viewer.add_child(sheet)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 10)
	column.offset_left = VIEWER_MARGIN
	column.offset_top = VIEWER_MARGIN
	column.offset_right = -VIEWER_MARGIN
	column.offset_bottom = -VIEWER_MARGIN
	# PASSES CLICKS THROUGH TO THE SHEET. Without this the layout node eats
	# them and only the margins would close the viewer.
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewer.add_child(column)

	_viewer_frame = TextureRect.new()
	_viewer_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# KEEP_ASPECT_CENTERED, so a picture bigger than the window is shrunk to
	# fit and a small one is NOT blown up into a smear - pixel art especially.
	_viewer_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_viewer_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_viewer_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewer_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewer_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_viewer_frame)

	_viewer_caption = Label.new()
	_viewer_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_viewer_caption.add_theme_color_override("font_color", Color(0.72, 0.68, 0.6))
	_viewer_caption.add_theme_font_size_override("font_size", 12)
	_viewer_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_viewer_caption)


func _decode_picture(into: Image, raw: PackedByteArray) -> bool:
	"""
	PNG or WebP, decided by the file's own first bytes.

	THE SERVER RE-ENCODES EVERYTHING IT STORES, so this is still a closed set
	of two rather than "whatever arrived". It keeps a still as WebP when WebP
	is smaller, which for a photograph is several times over - one that goes
	up as 265 KB was being stored and re-served as a 1.7 MB PNG, and every
	person in the channel downloaded that. Animations stay PNG: their frames
	are flat or pixel art, which is what PNG is best at and lossy compression
	is worst at.

	BY MAGIC NUMBER RATHER THAN BY THE Content-Type HEADER, because the header
	is a claim and the bytes are the thing. Two comparisons, no round trip,
	and it keeps working if an older server that predates the format column
	answers this client.
	"""
	if raw.size() < 12:
		return false

	# 'RIFF' .... 'WEBP'
	if raw[0] == 0x52 and raw[1] == 0x49 and raw[2] == 0x46 and raw[3] == 0x46 \
			and raw[8] == 0x57 and raw[9] == 0x45 and raw[10] == 0x42 and raw[11] == 0x50:
		return into.load_webp_from_buffer(raw) == OK

	return into.load_png_from_buffer(raw) == OK


func _slice_sheet(picture: Image, meta: Dictionary) -> Array:
	"""
	One texture, or one per frame of a spritesheet.

	THE SERVER FLATTENED THE ANIMATION so this does not have to decode a GIF -
	Godot cannot - and cutting a grid back up is something this project has
	been doing since the first enemy.
	"""
	var whole := ImageTexture.create_from_image(picture)
	var frames: int = int(meta.get("frames", 1))
	if frames <= 1:
		return [whole]

	var columns: int = max(1, int(meta.get("columns", 1)))
	var cell_w: int = int(meta.get("width", picture.get_width()))
	var cell_h: int = int(meta.get("height", picture.get_height()))
	var out: Array = []
	for index in range(frames):
		# WHOLE CELLS, DELIBERATELY. A grid position is a count of rows and a
		# count across, so the discarded remainder is the answer rather than a
		# rounding loss - @warning_ignore says that out loud, because an
		# unexplained integer division reads like somebody forgot a .0.
		@warning_ignore("integer_division")
		var row: int = index / columns
		var column: int = index % columns
		var piece := AtlasTexture.new()
		piece.atlas = whole
		piece.region = Rect2(column * cell_w, row * cell_h, cell_w, cell_h)
		out.append(piece)
	return out


func _feeds_meta(image_id: String) -> Dictionary:
	# Whatever the last poll said about this picture. Kept on the line rather
	# than in a table of its own, because a picture only matters to the line
	# that posted it.
	for channel in CHANNELS:
		for line in _feeds[channel]["lines"]:
			if line is Dictionary and str(line.get("image", "")) == image_id:
				var meta = line.get("meta", {})
				if meta is Dictionary and not meta.is_empty():
					return meta
	return {"frames": 1, "columns": 1, "width": 0, "height": 0, "frame_ms": 0}


# =============================================================================
# TALKING TO THE SERVER
# =============================================================================

func _on_poll_timeout() -> void:
	if not visible:
		return
	_poll()


# Moved on every feed reset. A poll that left before a reset is answering a
# question nobody is asking any more: see _poll().
var _feed_generation: int = 0


func _reset_feed(channel: String) -> void:
	"""Empty a feed so the next read fetches its tail."""
	_feeds[channel]["cursor"] = 0
	_feeds[channel]["lines"] = []
	_feed_generation += 1
	# WHAT IS ON SCREEN IS NOW THE OLD FEED - a tab switch draws what it had
	# while the tail is fetched, rather than a blank window. The tail replaces
	# it in one render; appending it below would show everything twice.
	if channel == _channel:
		_redraw_on_next_read = true


var _redraw_on_next_read: bool = false


func _poll() -> void:
	# Never two at once, and nothing to ask on behalf of nobody. Same guard as
	# the HUD's broadcast poll and for the same reason: a slow server must not
	# end up with a queue of requests stacked behind each other.
	if _in_flight or not Api.is_logged_in():
		return
	var path: String = _poll_path()
	if path == "":
		return
	var asked: String = _channel
	var generation: int = _feed_generation

	_in_flight = true
	var res: Dictionary = await Api.get_json(path, Api.PROBE_TIMEOUT)

	# PAST AN AWAIT. Up to the timeout has passed and this node may be gone -
	# the player died, or the scene changed underneath it.
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_in_flight = false

	# THE FEED WAS RESET WHILE THIS WAS IN FLIGHT - a tab opened, /r or /w to
	# the same person, a message removed. This answer carries only what came
	# after the OLD cursor, and applying it would set the cursor past the
	# history the reset asked for: /r showed your reply and none of the
	# conversation it answered. Dropped, and the tail asked for instead -
	# straight away, not a poll later: a whisper opened from the HUD's notice
	# sat empty for three seconds.
	if generation != _feed_generation:
		if visible:
			_poll()
		return

	# SILENT ON FAILURE, DELIBERATELY. The HUD's own poll is what decides that
	# a session has ended, and it is already running; a chat window that threw
	# up an error every three seconds during a server restart would be the
	# loudest thing on screen and would be saying nothing new.
	if not res.get("ok", false):
		return

	var data = res.get("data", {})
	if not (data is Dictionary):
		return
	_apply_read(asked, data)


func _poll_path() -> String:
	"""What the poll asks for the open tab, or "" when there is nothing to ask.

	THE GUILD TAB USED TO BE "" HERE, with "Guilds are not in the game yet."
	on the screen, long after guilds were in the game. The server had guild
	chat - send, read, and the membership check - and this client never asked
	for it: the same finished-half-with-nothing-joined-to-it that this project
	keeps finding. Now only a whisper with nobody to whisper to is "". """
	if _local_refusal(_channel) != "":
		return ""
	var path: String = "/api/chat?channel=%s&since=%d" % [
		_channel, int(_feeds[_channel]["cursor"])]
	if _channel == "private":
		path += "&with=" + _whisper_with.uri_encode()
	return path


func _local_refusal(channel: String) -> String:
	"""The one thing this client refuses without asking: a whisper to nobody.

	ONE FUNCTION FOR THE TAB, THE POLL, THE SAY BUTTON AND THE PICTURE BUTTON.
	Those were four copies of the same two refusals, which is how the guild one
	outlived guilds in all four at once."""
	if channel == "private" and _whisper_with == "":
		return "Type who you want to whisper to, up in the corner."
	return ""


func _apply_read(asked: String, data: Dictionary) -> void:
	"""One answer from GET /api/chat, onto the feed it was asked for. Split
	from the request so the suite can hand it an answer and look.

	`available: false` IS THE SERVER SAYING THIS ROOM IS NOT YOURS - today only
	guild chat, for somebody not in a guild - and its `notice` is shown as it
	is, because it is the one that knows why."""
	# TAKEN FROM EVERY ANSWER, INCLUDING ONE FOR THE WRONG CHANNEL. How long
	# until a picture may go to world does not depend on which channel was
	# read, and throwing the number away below because the tab changed would
	# leave the warning showing a wait that has already passed.
	if data.has("world_image_wait"):
		_world_wait = maxi(0, int(data.get("world_image_wait", 0)))
		_world_wait_read_at = float(Time.get_ticks_msec()) / 1000.0
	# AND WHETHER YOU MAY SPEAK AT ALL, for the same reason: said in the box
	# before you type, not after you press Enter.
	if data.has("muted"):
		_set_muted(data.get("muted"))

	# THE ANSWER MAY BE FOR A CHANNEL NOBODY IS LOOKING AT ANY MORE. Three
	# seconds is long enough to change tab twice, and filing a world reply into
	# an open whisper would be a small disaster.
	if str(data.get("channel", asked)) != asked:
		return

	# NOT YOURS TO READ - the server's word, and its words. The feed is
	# emptied as well: somebody removed from a guild should not go on reading
	# the last page of it from their own screen.
	if not bool(data.get("available", true)):
		_feeds[asked]["lines"] = []
		if asked == _channel:
			_redraw_on_next_read = false
			_room_notice = str(data.get("notice", "This channel is not open to you."))
			_set_notice(_room_notice)
			if visible:
				_render()
		return
	# AND WHEN IT OPENS AGAIN - you founded or joined a guild with this tab
	# open - that notice goes, and only that one: a refusal from a send that
	# happened meanwhile is still the thing to read.
	if asked == _channel and _room_notice != "" and notice != null and notice.text == _room_notice:
		_set_notice("")
	_room_notice = ""

	var pictures = data.get("images", {})
	var batch: Array = data.get("messages", []) if data.get("messages") is Array else []
	if asked == _channel and visible and not batch.is_empty():
		_batch_follow = _should_follow()
		_batching = true
	for entry_data in batch:
		if not (entry_data is Dictionary):
			continue
		_add_line(asked, _line_from_server(entry_data, pictures))
	if _batching:
		_batching = false
		if _batch_follow and not _redraw_on_next_read:
			_scroll_to_end.call_deferred()
		elif not _redraw_on_next_read:
			_show_new_below(true)
	# THE FIRST READ AFTER A RESET REPLACES THE SCREEN, empty answer or not.
	if _redraw_on_next_read and asked == _channel:
		_redraw_on_next_read = false
		if visible:
			_render()

	# WHAT HAS BEEN TAKEN BACK DOWN. After the additions, so a line deleted in
	# the same three seconds it was posted cannot arrive and then be spared
	# because the removal was processed first.
	var removed = data.get("removed", [])
	if removed is Array and not removed.is_empty():
		if _remove_lines(asked, removed) > 0 and asked == _channel and visible:
			_render(true)

	var newest: int = int(data.get("latest_id", _feeds[asked]["cursor"]))
	if newest > int(_feeds[asked]["cursor"]):
		_feeds[asked]["cursor"] = newest


# ONE PLACE TURNS A SERVER MESSAGE INTO A LINE, and it is a function rather
# than six statements buried in the poll so that a test can hand it a real
# server message and check what comes out.
#
# THAT IS NOT A THEORETICAL BENEFIT. The staff delete button reads line["id"],
# the id was being dropped here, and every single test of that button passed -
# because every one of them built its own dictionary by hand with an id in it
# rather than asking for the one the poll actually makes. The button was
# tested; the path to the button was not.
func _line_from_server(entry_data: Dictionary, pictures: Variant) -> Dictionary:
	var line: Dictionary = {
		"kind": "chat",
		# THE SERVER'S OWN ROW ID. Staff need it to point at exactly this line
		# when taking it down; nothing else uses it, and a line this client
		# invented - a system notice - has none, which is what stops the x
		# appearing beside something the server has never heard of.
		"id": int(entry_data.get("id", 0)),
		"by": entry_data.get("by", "?"),
		"role": entry_data.get("role", "player"),
		# WHAT THEY WERE FLYING WHEN THEY SAID IT. The server denormalises the
		# guild onto the row beside username and role, for the reasons its own
		# comment gives: the read is a poll every three seconds and must not
		# grow a join, and the line should still make sense after the author has
		# left the guild or the guild is gone. So this is a SNAPSHOT, not a
		# lookup, and it is right that an old line keeps an old tag.
		#
		# CARRIED HERE, which is the whole point of the note above this
		# function. A renderer cannot draw a field this dictionary does not
		# have, and a test that builds its own dictionary would never find out.
		"guild_tag": str(entry_data.get("guild_tag", "")),
		# THE COLOUR THEY HAD CHOSEN WHEN THEY SAID IT - a snapshot, like the
		# tag. Left out, every name in chat is drawn in the default colour
		# while the friends list beside it shows the real one: which is exactly
		# what the first live run of this showed, and exactly what the note
		# above this function says will happen to any field not copied here.
		# null stays null ("never chose"), so it is not coerced.
		"name_hue": entry_data.get("name_hue"),
		"body": entry_data.get("body", ""),
		"at": int(entry_data.get("at", 0)),
	}

	var image_id: String = str(entry_data.get("image", ""))
	if image_id != "":
		line["kind"] = "image"
		line["image"] = image_id
		if pictures is Dictionary and pictures.has(image_id):
			line["meta"] = pictures[image_id]
	return line


# =============================================================================
# IGNORE, REPORT, MUTE - and the name you click to reach them
# =============================================================================
# Click a name in the log for a small menu: whisper, ignore, report the line,
# and for staff, mute. The same things are commands (/help lists them). The
# server decides every one of them - see IGNORE, REPORT, MUTE in app.py; this
# is only the way to ask.

const REPORT_CHOICES := [["spam", "Spam"], ["harassment", "Harassment"],
	["hate", "Hate speech"], ["cheating", "Cheating or scams"], ["other", "Something else"]]
const MUTE_CHOICES := [[10, "Mute 10 minutes"], [60, "Mute 1 hour"], [1440, "Mute 1 day"]]
const MENU_WHISPER := 1
const MENU_IGNORE := 2
const MENU_REPORT := 10
const MENU_MUTE := 20
const MENU_UNMUTE := 30
const RANK_ORDER := ["player", "mod", "dev", "owner"]
const NEW_BELOW_TEXT := "New messages below - click to see them"
const COMMANDS_HELP := "/w name text  whisper   /r text  answer the last whisper\n" \
	+ "/ignore name   /unignore name   /ignored  who you are ignoring"
const STAFF_COMMANDS_HELP := "\n/mute name minutes reason   /unmute name"

var line_menu: PopupMenu = null
var _menu_line: Dictionary = {}
var new_below: Button = null
# null, or {until, seconds_left, reason} from the last read - see _set_muted().
var _muted: Variant = null


func _clickable_name(line: Dictionary, name_bbcode: String) -> String:
	"""The name wrapped in a link to its line's menu - not your own name, and
	not a line the server has not numbered."""
	var who: String = str(line.get("by", ""))
	if int(line.get("id", 0)) <= 0 or who == "" or who.to_lower() == Api.username.to_lower():
		return name_bbcode
	return "[url=name]%s[/url]" % name_bbcode


func _wire_name_click(label: RichTextLabel, line: Dictionary) -> void:
	label.meta_underlined = false
	label.meta_clicked.connect(func(_meta: Variant) -> void: open_line_menu(line))


func _ensure_line_menu() -> PopupMenu:
	if line_menu == null:
		line_menu = PopupMenu.new()
		line_menu.name = "linemenu"
		add_child(line_menu)
		line_menu.id_pressed.connect(func(id: int) -> void: _on_line_menu_id(id))
	return line_menu


static func rank_at(rank: String) -> int:
	return maxi(0, RANK_ORDER.find(rank))


func open_line_menu(line: Dictionary) -> void:
	"""The menu for one line's author, at the mouse."""
	var who: String = str(line.get("by", ""))
	if who == "" or who.to_lower() == Api.username.to_lower():
		return
	var menu: PopupMenu = _ensure_line_menu()
	menu.clear()
	_menu_line = line
	var rank: String = str(line.get("role", "player"))
	menu.add_separator(who)
	menu.add_item("Whisper", MENU_WHISPER)
	menu.add_item("Ignore", MENU_IGNORE)
	# STAFF CANNOT BE IGNORED - the server refuses it, so it is not offered.
	if rank_at(rank) >= rank_at("mod"):
		var at: int = menu.get_item_index(MENU_IGNORE)
		menu.set_item_disabled(at, true)
		menu.set_item_tooltip(at, "Staff cannot be ignored. Report the message instead.")
	if int(line.get("id", 0)) > 0:
		menu.add_separator("Report this message")
		for i in REPORT_CHOICES.size():
			menu.add_item(REPORT_CHOICES[i][1], MENU_REPORT + i)
	var mine: int = rank_at("owner" if Api.is_owner else Api.role)
	if mine >= rank_at("mod") and mine > rank_at(rank):
		menu.add_separator("Staff")
		for i in MUTE_CHOICES.size():
			menu.add_item(MUTE_CHOICES[i][1], MENU_MUTE + i)
		menu.add_item("Unmute", MENU_UNMUTE)
	menu.reset_size()
	if is_inside_tree():
		menu.position = Vector2i(get_viewport().get_mouse_position())
		menu.popup()


func _on_line_menu_id(id: int) -> void:
	var line: Dictionary = _menu_line
	var who: String = str(line.get("by", ""))
	if who == "":
		return
	if id == MENU_WHISPER:
		_aim_whisper(who)
		_show_channel("private")
		if entry != null and entry.is_inside_tree():
			entry.grab_focus()
	elif id == MENU_IGNORE:
		await ignore_player(who)
	elif id >= MENU_REPORT and id < MENU_REPORT + REPORT_CHOICES.size():
		await report_line(int(line.get("id", 0)), REPORT_CHOICES[id - MENU_REPORT][0])
	elif id >= MENU_MUTE and id < MENU_MUTE + MUTE_CHOICES.size():
		# THE LINE IS THE REASON. A mute needs one on the record, and the line
		# that earned it is the most useful thing to put there.
		await mute_player(who, int(MUTE_CHOICES[id - MENU_MUTE][0]),
			"Said: \"%s\"" % one_line(str(line.get("body", ""))).left(120))
	elif id == MENU_UNMUTE:
		await unmute_player(who)


func ignore_player(who: String) -> void:
	var res: Dictionary = await Api.post("/api/ignores", {"username": who})
	if not is_instance_valid(self):
		return
	if not res.get("ok", false):
		_set_notice(_refusal(res))
		return
	var ignored: String = str(res.get("data", {}).get("username", who))
	forget_author(ignored)
	_set_notice("You will not see %s's messages. /unignore %s to undo." % [ignored, ignored])


func forget_author(who: String) -> int:
	"""Every line by `who`, out of every feed - ignoring somebody takes their
	lines off the screen now, not when the next poll happens to leave them out."""
	var gone: int = 0
	for channel in _feeds:
		var kept: Array = []
		for line in _feeds[channel]["lines"]:
			if line is Dictionary and str(line.get("by", "")).to_lower() == who.to_lower():
				gone += 1
				continue
			kept.append(line)
		_feeds[channel]["lines"] = kept
	if gone > 0 and visible:
		_render(true)
	return gone


func unignore_player(who: String) -> void:
	var res: Dictionary = await Api.post("/api/ignores/remove", {"username": who})
	if not is_instance_valid(self):
		return
	if not res.get("ok", false):
		_set_notice(_refusal(res))
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	var heard: String = str(data.get("username", who))
	if not bool(data.get("was_ignored", true)):
		_set_notice("You were not ignoring %s." % heard)
		return
	_set_notice("You will see %s's messages again." % heard)
	# Read the room again from its tail, with their lines in it.
	_reset_feed(_channel)
	_poll()


func list_ignored() -> void:
	var res: Dictionary = await Api.get_json("/api/ignores")
	if not is_instance_valid(self):
		return
	if not res.get("ok", false):
		_set_notice(_refusal(res))
		return
	var names: PackedStringArray = []
	for row in res.get("data", {}).get("ignored", []):
		if row is Dictionary:
			names.append(str(row.get("username", "")))
	_set_notice("You are not ignoring anybody." if names.is_empty()
		else "Ignoring: %s. /unignore name to stop." % ", ".join(names))


func report_line(message_id: int, reason: String) -> void:
	var res: Dictionary = await Api.post("/api/chat/report", {"id": message_id, "reason": reason})
	if not is_instance_valid(self):
		return
	if not res.get("ok", false):
		_set_notice(_refusal(res))
		return
	_set_notice("You already reported that message." if bool(res.get("data", {}).get("already", false))
		else "Reported. Thank you - staff will look at it.")


func mute_player(who: String, minutes: int, reason: String) -> void:
	var res: Dictionary = await Api.post("/api/staff/mute",
		{"username": who, "minutes": minutes, "reason": reason})
	if not is_instance_valid(self):
		return
	if not res.get("ok", false):
		_set_notice(_refusal(res))
		return
	_set_notice("Muted %s for %s." % [who, _readable_wait(minutes * 60)])


func unmute_player(who: String) -> void:
	var res: Dictionary = await Api.post("/api/staff/unmute", {"username": who})
	if not is_instance_valid(self):
		return
	_set_notice(_refusal(res) if not res.get("ok", false) else "%s can talk again." % who)


static func _looks_like_command(text: String) -> bool:
	return text.length() >= 2 and text.begins_with("/") and \
		((text[1] >= "a" and text[1] <= "z") or (text[1] >= "A" and text[1] <= "Z"))


func _run_command(text: String) -> void:
	var bits: PackedStringArray = text.strip_edges().split(" ", false)
	var command: String = bits[0].to_lower()
	var arg: String = bits[1] if bits.size() > 1 else ""
	match command:
		"/help", "/commands", "/?":
			_set_notice(COMMANDS_HELP + (STAFF_COMMANDS_HELP if Api.role_at_least("mod") else ""))
		"/ignore", "/block":
			if arg == "":
				_set_notice("Try: /ignore name")
			else:
				await ignore_player(arg)
		"/unignore", "/unblock":
			if arg == "":
				_set_notice("Try: /unignore name")
			else:
				await unignore_player(arg)
		"/ignored", "/ignorelist", "/blocked":
			await list_ignored()
		"/mute":
			var minutes: int = int(bits[2]) if bits.size() > 2 and bits[2].is_valid_int() else 0
			if arg == "" or minutes <= 0 or bits.size() < 4:
				_set_notice("Try: /mute name minutes reason")
			else:
				await mute_player(arg, minutes, " ".join(bits.slice(3)))
		"/unmute":
			if arg == "":
				_set_notice("Try: /unmute name")
			else:
				await unmute_player(arg)
		_:
			_set_notice("There is no %s command. /help lists them." % command)


func _set_muted(state: Variant) -> void:
	"""The server's word on whether this player may speak, onto the box."""
	_muted = state if state is Dictionary else null
	if entry == null:
		return
	if _muted == null:
		if entry.placeholder_text.begins_with("You are muted"):
			entry.placeholder_text = entry_placeholder(WebPage.in_browser())
		return
	var line: String = "You are muted for %s more" % _readable_wait(int(_muted.get("seconds_left", 0)))
	var reason: String = str(_muted.get("reason", ""))
	entry.placeholder_text = line + (" - %s" % reason if reason != "" else "")


func _build_new_below() -> void:
	"""A bar under the log, shown when a line arrives while the player is
	reading further up. Without it, the only sign that anybody spoke was a
	scroll bar that got a little shorter."""
	if scroll == null or new_below != null:
		return
	var rows: Node = scroll.get_parent()
	if rows == null:
		return
	new_below = Button.new()
	new_below.name = "newbelow"
	new_below.text = NEW_BELOW_TEXT
	new_below.focus_mode = Control.FOCUS_NONE
	new_below.add_theme_font_size_override("font_size", 11)
	new_below.add_theme_color_override("font_color", TAB_UNREAD)
	new_below.visible = false
	rows.add_child(new_below)
	rows.move_child(new_below, scroll.get_index() + 1)
	new_below.pressed.connect(func() -> void:
		_show_new_below(false)
		_scroll_to_end())
	scroll.get_v_scroll_bar().value_changed.connect(func(_value: float) -> void:
		if new_below.visible and _at_bottom():
			_show_new_below(false))


func _show_new_below(on: bool) -> void:
	if new_below != null:
		new_below.visible = on


func _on_setting_changed(key: String, _value: Variant) -> void:
	# THE FILTER APPLIES TO WHAT IS ALREADY ON SCREEN, both ways.
	if key == "chat_filter" and visible:
		_render(true)


func _on_entry_submitted(_text: String) -> void:
	_on_send_pressed()


func _on_send_pressed() -> void:
	if entry == null or _sending:
		return

	var text: String = entry.text.strip_edges()

	# A PICTURE WAITING IS THE MESSAGE, and whatever is typed rides along as
	# its caption. This is why an empty box is not an empty message here and
	# why the check below comes second.
	if not _pending.is_empty():
		await _send_pending(text)
		return

	if text == "":
		return

	# /r MESSAGE answers whoever whispered you last - the other half of /w.
	if text == "/r" or text.begins_with("/r "):
		var answer: String = text.substr(2).strip_edges()
		if last_whisper_from == "":
			_set_notice("Nobody has whispered you yet.")
			return
		if answer == "":
			_set_notice("Try: /r what you want to say back")
			return
		_aim_whisper(last_whisper_from)
		_show_channel("private")
		await _send("private", answer, "")
		return

	# /w NAME MESSAGE, from any channel. It is what people type, and it saves
	# changing tab and filling a box in to answer one question.
	if text.begins_with("/w ") or text.begins_with("/whisper "):
		var rest: String = text.split(" ", true, 1)[1].strip_edges()
		var bits: PackedStringArray = rest.split(" ", true, 1)
		if bits.size() < 2 or bits[1].strip_edges() == "":
			_set_notice("Try: /w name what you want to say")
			return
		if whisper_to != null:
			whisper_to.text = bits[0]
		_whisper_with = bits[0].strip_edges()
		_show_channel("private")
		await _send("private", bits[1].strip_edges(), "")
		return

	# THE OTHER COMMANDS - /ignore, /report's cousins, /help. A line that starts
	# with "/" and a letter is never sent to chat: a mistyped command said
	# out loud in world is the one thing worse than it not working.
	if _looks_like_command(text):
		if entry != null:
			entry.text = ""
		await _run_command(text)
		return

	# A LINK ON ITS OWN IS A PICTURE. Nobody should have to find a button to
	# post one - they paste and press Enter, like everywhere else they have
	# ever pasted a link. A link with words around it stays a line of text.
	if _looks_like_picture_link(text):
		await _send_link(text)
		return

	var refusal: String = _local_refusal(_channel)
	if refusal != "":
		_set_notice(refusal)
		return

	await _send(_channel, text, "")


# =============================================================================
# THE FOUR WAYS TO ADD A PICTURE
# =============================================================================

# ---------------------------------------------------------------------------
# ONE: CTRL+V
#
# In _input rather than on the LineEdit, because the LineEdit would otherwise
# eat the keystroke first and paste the clipboard's TEXT - which, when what is
# on the clipboard is a screenshot, is nothing at all. This runs before the GUI
# gets a look, checks whether there is really a picture there, and only then
# takes the event. An ordinary Ctrl+V on ordinary text falls straight through
# and the box pastes as it always has.
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible:
		return

	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return

	# ESCAPE CLOSES AN OPEN PICTURE FIRST, and takes the key so it does not
	# also close the chat or open the menu behind it. Checked before the
	# _sending guard below: an upload in flight must not trap somebody inside
	# a full-screen overlay for thirty seconds.
	if key.keycode == KEY_ESCAPE and is_viewing():
		get_viewport().set_input_as_handled()
		close_viewer()
		return

	if _sending:
		return
	if key.keycode != KEY_V:
		return
	# meta as well as ctrl: Cmd+V is the paste on a Mac and this costs one
	# comparison to get right.
	if not (key.ctrl_pressed or key.meta_pressed):
		return

	# ONLY WHILE THE BOX HAS FOCUS. Ctrl+V anywhere else in the game is not
	# somebody trying to post a picture, and swallowing it here would break
	# pasting in the whisper box two nodes away.
	if entry == null or not entry.has_focus():
		return
	if not DisplayServer.clipboard_has_image():
		return

	get_viewport().set_input_as_handled()
	_attach_image(DisplayServer.clipboard_get_image(), "pasted picture.png")


# ---------------------------------------------------------------------------
# TWO: DRAG A FILE ONTO THE WINDOW
# ---------------------------------------------------------------------------

func _on_files_dropped(files: PackedStringArray) -> void:
	# NOT WHILE THE CHAT IS SHUT. A file dropped on the game during a fight is
	# not a message somebody meant to send, and silently attaching it to a
	# window they cannot see is the worst of both.
	if not visible or _sending:
		return

	for path in files:
		if UPLOAD_KINDS.has(path.get_extension().to_lower()):
			_attach_file(path)
			return

	_set_notice("Drop a picture - %s." % ", ".join(UPLOAD_KINDS))


# ---------------------------------------------------------------------------
# THREE: THE + BUTTON
# ---------------------------------------------------------------------------

func _on_image_pressed() -> void:
	if _sending:
		return

	# IN A BROWSER THE PICKER IS THE PAGE'S. Godot's own FileDialog there shows
	# the engine's virtual disk, a folder of nothing, so + asks the browser.
	if WebPage.in_browser():
		var accept: Array = UPLOAD_KINDS.map(func(kind: String) -> String: return "." + kind)
		_web_pick = WebPage.pick_file(",".join(PackedStringArray(accept)), _on_web_file_picked)
		return

	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.title = "Pick a picture"
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		# ACCESS_FILESYSTEM, not ACCESS_RESOURCES. A player's pictures live in
		# their own folders; the default would show them the inside of the game
		# and nothing else, which looks like the picker is broken.
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.use_native_dialog = true

		var patterns := PackedStringArray()
		for kind in UPLOAD_KINDS:
			patterns.append("*." + kind)
		_file_dialog.add_filter(", ".join(patterns), "Pictures")
		_file_dialog.file_selected.connect(_attach_file)
		add_child(_file_dialog)

	_file_dialog.popup_centered_ratio(0.6)


# The browser picker's input and callbacks, kept until the file arrives.
var _web_pick: Array = []


func _on_web_file_picked(bytes: PackedByteArray, file_name: String) -> void:
	"""A file from the browser's picker: written where a dropped file lands, in
	the page's own memory, then attached exactly as a dropped one is."""
	_web_pick = []
	if bytes.is_empty():
		_set_notice("That file could not be read.")
		return
	var folder: String = "/tmp/elusion-pick"
	DirAccess.make_dir_recursive_absolute(folder)
	var path: String = folder.path_join(file_name.get_file().replace("\\", "_"))
	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		_set_notice("That file could not be read.")
		return
	out.store_buffer(bytes)
	out.close()
	_attach_file(path)


# ---------------------------------------------------------------------------
# FOUR: A PASTED LINK, which needs no button at all - see _on_send_pressed.
# ---------------------------------------------------------------------------

func _looks_like_picture_link(text: String) -> bool:
	# THE WHOLE MESSAGE, OR IT IS A SENTENCE. "look at https://x/y.png" is
	# somebody talking about a picture; "https://x/y.png" on its own is
	# somebody posting one. Only the second is turned into an image.
	if text.contains(" ") or text.contains("\n"):
		return false
	if not (text.begins_with("http://") or text.begins_with("https://")):
		return false

	# AND IT HAS TO LOOK LIKE A FILE. A link to a web page would be sent to the
	# relay, fetched, and refused - so a plain link stays a plain line of text
	# rather than costing a round trip and an error message.
	var without_query: String = text.get_slice("?", 0).get_slice("#", 0).to_lower()
	for kind in UPLOAD_KINDS:
		if without_query.ends_with("." + kind):
			return true
	return false


# =============================================================================
# THE PICTURE WAITING TO BE SENT
# =============================================================================

func _attach_image(picture: Image, label: String) -> void:
	if picture == null or picture.is_empty():
		_set_notice("There was no picture on the clipboard.")
		return

	_set_notice("Squeezing that picture down...")
	var prepared: Dictionary = _compress(picture)
	if prepared.is_empty():
		_set_notice("That picture could not be made small enough to send.")
		return

	var bytes: PackedByteArray = prepared["bytes"]
	_hold(bytes, label, picture,
		"%s %s" % [prepared.get("kind", ""), prepared.get("note", "")])


func _attach_file(path: String) -> void:
	var extension: String = path.get_extension().to_lower()
	if not UPLOAD_KINDS.has(extension):
		_set_notice("That is not a picture file.")
		return

	var raw: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if raw.is_empty():
		_set_notice("That file could not be read.")
		return

	var preview := Image.new()
	if preview.load(path) != OK:
		_set_notice("That file is not a picture this game can read.")
		return

	# AN ANIMATION TRAVELS EXACTLY AS IT IS. Godot can show a GIF's first frame
	# but cannot write one back out, so re-encoding here would quietly turn a
	# moving picture into a still. Under the cap it goes untouched and the
	# server splits the frames, which it already knows how to do.
	if extension == "gif":
		if raw.size() > UPLOAD_MAX_BYTES:
			# NAMES BOTH NUMBERS. "Too big" on its own leaves somebody
			# guessing how much smaller is small enough.
			_set_notice("That GIF is %s and the limit is %d MB. Shrinking it here "
				% [_readable_size(raw.size()), UPLOAD_MAX_MB]
				+ "would flatten the animation, so it has to be trimmed first.")
			return
		_hold(raw, path.get_file(), preview,
			"animation, %s, sent as-is" % _readable_size(raw.size()))
		return

	# THE ORIGINAL FILE IF IT IS ALREADY SMALL AND SMALL ENOUGH. Re-encoding a
	# 200 KB PNG through Godot only makes it bigger and slightly worse.
	var widest: int = maxi(preview.get_width(), preview.get_height())
	if raw.size() <= UPLOAD_COMFORTABLE_BYTES and widest <= UPLOAD_MAX_SIDE:
		_hold(raw, path.get_file(), preview,
			"%dx%d, %s, sent as-is" % [preview.get_width(), preview.get_height(),
				_readable_size(raw.size())])
		return

	_set_notice("Squeezing that picture down...")
	var before: int = raw.size()
	var prepared: Dictionary = _compress(preview)
	if prepared.is_empty():
		_set_notice("That picture could not be made small enough to send.")
		return

	var bytes: PackedByteArray = prepared["bytes"]
	var note: String = "%s %s" % [prepared.get("kind", ""), prepared.get("note", "")]
	if before > bytes.size():
		note += "  (was %s)" % _readable_size(before)
	_hold(bytes, path.get_file(), preview, note)


func _hold(payload: PackedByteArray, label: String, preview: Image,
		note: String = "") -> void:
	_pending = {"bytes": payload, "name": label}

	if attach_thumb != null:
		attach_thumb.texture = _thumbnail(preview)
	if attach_name != null:
		attach_name.text = label
	if attach_size != null:
		# WHAT IT COST, not just what it is. Somebody who pasted a 4 MB
		# screenshot and is about to send 180 KB of it should be able to see
		# that happened, and see it BEFORE they press Enter rather than
		# wondering afterwards why it looks soft.
		attach_size.text = note if note != "" else _readable_size(payload.size())
	if attach_row != null:
		attach_row.visible = true
	if entry != null:
		entry.placeholder_text = ENTRY_PLACEHOLDER_ATTACHED
		entry.grab_focus()

	# SAID AT THE MOMENT OF ATTACHING, not only when Enter is pressed. Whoever
	# just dragged a file in should find out now that world is closed to them
	# for another twenty minutes, while choosing to whisper it instead is
	# still an easy thing to do.
	var waiting: int = _world_wait_left() if _channel == "world" else 0
	if waiting > 0:
		_set_notice("Ready - but world chat takes one picture every half hour, "
			+ "and the next can go in %s. Whisper it, or send it to friends."
			% _readable_wait(waiting))
	else:
		_set_notice("Ready - press Enter to send it.")


static func entry_placeholder(in_browser: bool) -> String:
	return ENTRY_PLACEHOLDER_WEB if in_browser else ENTRY_PLACEHOLDER


func _clear_pending() -> void:
	_pending = {}
	if attach_row != null:
		attach_row.visible = false
	if attach_thumb != null:
		attach_thumb.texture = null
	if entry != null:
		entry.placeholder_text = entry_placeholder(WebPage.in_browser())


func _thumbnail(picture: Image) -> Texture2D:
	if picture == null or picture.is_empty():
		return null
	var small: Image = _workable(picture)
	if small == null:
		return null

	var widest: int = maxi(small.get_width(), small.get_height())
	if widest > ATTACH_THUMB_SIDE:
		var factor: float = float(ATTACH_THUMB_SIDE) / float(widest)
		small.resize(
			maxi(1, int(round(small.get_width() * factor))),
			maxi(1, int(round(small.get_height() * factor))),
			Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(small)


func _workable(picture: Image) -> Image:
	# A COPY, ALWAYS, in a format resize() and the PNG writer will accept. The
	# clipboard hands over something already plain, but an Image loaded from a
	# file can arrive compressed, and resize() on a compressed image does
	# nothing at all - quietly, which is the part that costs an afternoon.
	var working: Image = picture.duplicate() as Image
	if working == null:
		return null
	if working.is_compressed() and working.decompress() != OK:
		return null
	if working.get_format() != Image.FORMAT_RGBA8:
		working.convert(Image.FORMAT_RGBA8)
	return working


func _compress(picture: Image) -> Dictionary:
	"""
	{"bytes", "kind", "note"} for a picture ready to send, or {} if it could
	not be made small enough.

	`note` is the sentence shown under the thumbnail - what was done to it and
	what it cost - because a picture that silently comes out softer than the
	one you pasted is worse than one that says why.
	"""
	var working: Image = _workable(picture)
	if working == null:
		return {}

	var from_size := Vector2i(working.get_width(), working.get_height())
	var scaled := false

	var widest: int = maxi(working.get_width(), working.get_height())
	if widest > UPLOAD_MAX_SIDE:
		# STRAIGHT TO THE SERVER'S OWN CEILING. It scales anything bigger down
		# to this the moment it arrives, so sending more is paying to upload
		# detail that is thrown away on receipt.
		var factor: float = float(UPLOAD_MAX_SIDE) / float(widest)
		working.resize(
			maxi(1, int(round(working.get_width() * factor))),
			maxi(1, int(round(working.get_height() * factor))),
			Image.INTERPOLATE_LANCZOS)
		scaled = true

	for _pass in range(UPLOAD_SHRINK_PASSES):
		var best: Dictionary = _smallest_encoding(working)
		if best.is_empty():
			return {}

		var encoded: PackedByteArray = best["bytes"]
		if encoded.size() <= UPLOAD_MAX_BYTES:
			best["note"] = _compression_note(from_size, working, scaled, encoded.size())
			return best

		if working.get_width() <= UPLOAD_SHRINK_FLOOR \
				or working.get_height() <= UPLOAD_SHRINK_FLOOR:
			break
		working.resize(
			maxi(1, int(working.get_width() * UPLOAD_SHRINK_STEP)),
			maxi(1, int(working.get_height() * UPLOAD_SHRINK_STEP)),
			Image.INTERPOLATE_LANCZOS)
		scaled = true

	return {}


func _smallest_encoding(working: Image) -> Dictionary:
	"""
	The smaller of PNG and WebP, measured rather than guessed.

	THE GUESS IS WRONG HALF THE TIME, which is why this encodes both. Measured
	in this project at 1024-1920 across:

		a screenshot   PNG    30 KB   WebP    78 KB   -> PNG, by a mile
		a photograph   PNG  2.7 MB    WebP  1.09 MB   -> WebP, by a mile
		flat artwork   PNG     7 KB   WebP    25 KB   -> PNG

	Flat colour and sharp text are exactly what PNG is for; continuous tone is
	exactly what it is worst at. Choosing by file extension or by guessing at
	"photo-ness" gets one of those three wrong. Encoding both costs a fraction
	of a second and removes the question entirely.
	"""
	var png: PackedByteArray = working.save_png_to_buffer()
	if png.is_empty():
		return {}

	var best := {"bytes": png, "kind": "PNG"}
	if png.size() <= UPLOAD_COMFORTABLE_BYTES:
		# Lossless and already small. Nothing to win.
		return best

	for quality in UPLOAD_WEBP_LADDER:
		var webp: PackedByteArray = working.save_webp_to_buffer(true, float(quality))
		if webp.is_empty():
			# No WebP in this build of Godot. PNG stands, and the caller will
			# shrink the picture instead if it is still too big.
			break
		var current: PackedByteArray = best["bytes"]
		if webp.size() < current.size():
			best = {"bytes": webp, "kind": "WebP"}
		var chosen: PackedByteArray = best["bytes"]
		if chosen.size() <= UPLOAD_COMFORTABLE_BYTES:
			break

	return best


func _compression_note(from_size: Vector2i, working: Image, scaled: bool,
		final_bytes: int) -> String:
	var parts := PackedStringArray()
	if scaled:
		parts.append("scaled from %dx%d" % [from_size.x, from_size.y])
	parts.append("%dx%d, %s" % [working.get_width(), working.get_height(),
		_readable_size(final_bytes)])
	return ", ".join(parts)


func _ascii_label(text: String) -> String:
	var out := ""
	for i in text.length():
		var code: int = text.unicode_at(i)
		# Printable ASCII only, and no quotes or control characters - the
		# things that would end a header value early.
		if code >= 32 and code <= 126 and code != 34 and code != 59:
			out += char(code)
		else:
			out += "_"
	out = out.strip_edges()
	return out.left(96) if out != "" else "picture"


func _readable_size(count: int) -> String:
	if count >= 1024 * 1024:
		return "%.1f MB" % (float(count) / (1024.0 * 1024.0))
	if count >= 1024:
		return "%d KB" % int(float(count) / 1024.0)
	return "%d bytes" % count


# =============================================================================
# SENDING IT
# =============================================================================

func _world_wait_left() -> int:
	"""Seconds until a picture may go to world, counted down since the poll.

	COUNTED DOWN LOCALLY rather than asked for every few seconds. The server
	is the one that decides - it refuses the send regardless of what this
	says - and this is only here so the warning is not wrong by up to a poll
	interval, which looks like the game cannot count.
	"""
	if _world_wait <= 0:
		return 0
	var elapsed: float = float(Time.get_ticks_msec()) / 1000.0 - _world_wait_read_at
	return maxi(0, _world_wait - int(elapsed))


func _readable_wait(seconds: int) -> String:
	if seconds >= 120:
		return "%d minutes" % int(ceil(float(seconds) / 60.0))
	if seconds >= 60:
		return "a minute"
	return GameConstants.counted(seconds, "second")


func _postable_channel() -> String:
	# WHERE A PICTURE CAN GO, and the sentence to show when the answer is
	# nowhere. Previously a picture posted to a channel you were not really in
	# was quietly redirected to world, which is a surprising place for a
	# private one to turn up.
	var refusal: String = _local_refusal(_channel)
	if refusal != "":
		_set_notice(refusal)
		return ""

	# THE WORLD LIMIT, CHECKED BEFORE THE UPLOAD RATHER THAN AFTER IT. The
	# server decides, and refuses the send whatever this says - but by then a
	# file has been picked, compressed and sent across the network, and being
	# told "wait 22 minutes" only at that point is the version of this that
	# feels broken. Whispers and friends are untouched; only world.
	if _channel == "world":
		var waiting: int = _world_wait_left()
		if waiting > 0:
			_set_notice("One picture in world chat every half hour - %s to go. "
				% _readable_wait(waiting)
				+ "You can still send it to a friend, or whisper it.")
			return ""

	return _channel


func _send_pending(caption: String) -> void:
	if _pending.is_empty() or _sending:
		return
	var channel: String = _postable_channel()
	if channel == "":
		return

	var payload: PackedByteArray = _pending.get("bytes", PackedByteArray())
	var label: String = str(_pending.get("name", "picture"))

	_sending = true
	_set_notice("Sending %s..." % _readable_size(payload.size()))

	var res: Dictionary = await Api.post_bytes(
		"/api/chat/upload",
		payload,
		"application/octet-stream",
		# ASCII ONLY, AND SHORT. This rides in an HTTP header, and a header is
		# not a place for arbitrary text: Godot writes UTF-8, Werkzeug reads
		# headers as latin-1, and a filename with an accent or a curly
		# apostrophe - which a screenshot picks up from whatever named it -
		# comes out mangled at best and refused at worst. The name is only a
		# label a moderator might read, so nothing is lost by flattening it.
		{"X-Picture-Name": _ascii_label(label)},
		UPLOAD_TIMEOUT)

	# PAST AN AWAIT - the panel may be gone, and this one takes seconds.
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_sending = false

	if not res.get("ok", false):
		# THE PICTURE STAYS ATTACHED. Whatever went wrong - offline, cooldown,
		# server busy - pressing Enter again should be the whole retry, not
		# "find the file again".
		_set_notice(_refusal(res))
		# AND THE WHOLE TRUTH IN THE CONSOLE. The notice is one line in a
		# corner of a game; when something goes wrong the person debugging it
		# needs the status code and the server's exact words, which is what
		# turns "it did not send" into a thing somebody can fix.
		push_warning("[CHAT] picture upload failed: HTTP %d - %s (%s, %s)" % [
			int(res.get("status", 0)), str(res.get("error", "")),
			label, _readable_size(payload.size())])
		return

	var data = res.get("data", {})
	var image_id: String = str(data.get("id", "")) if data is Dictionary else ""
	if image_id == "":
		_set_notice("That did not come back as a picture.")
		return

	# CLEARED ONLY NOW, once the server has it and given it an id. If the
	# message itself fails from here the caption comes back in the box and the
	# picture is already stored, so nothing has to be uploaded twice.
	_clear_pending()
	if entry != null:
		entry.text = ""
	_set_notice("")
	await _send(channel, caption, image_id)


func _send_link(link: String) -> void:
	var channel: String = _postable_channel()
	if channel == "":
		return

	if entry != null:
		entry.text = ""
	_sending = true
	_set_notice("Fetching that picture...")

	# THE SERVER FETCHES IT, NOT US. Loading the link here would mean every
	# client in the channel doing the same, which hands whoever posted it a
	# log of everyone who saw it. See the relay in app.py.
	var res: Dictionary = await Api.post("/api/chat/image", {"url": link}, UPLOAD_TIMEOUT)

	if not is_instance_valid(self) or not is_inside_tree():
		return
	_sending = false

	if not res.get("ok", false):
		if entry != null and entry.text == "":
			entry.text = link
		_set_notice(_refusal(res))
		push_warning("[CHAT] picture link refused: HTTP %d - %s (%s)" % [
			int(res.get("status", 0)), str(res.get("error", "")), link])
		return

	var data = res.get("data", {})
	var image_id: String = str(data.get("id", "")) if data is Dictionary else ""
	if image_id == "":
		_set_notice("That did not come back as a picture.")
		return

	_set_notice("")
	await _send(channel, "", image_id)


func _send(channel: String, text: String, image_id: String) -> void:
	if _sending:
		return

	# CLEARED BEFORE THE REQUEST, not after it. A send takes a round trip, and
	# a box that still holds the message for that long gets it typed over or
	# sent twice by somebody who thought the first press missed.
	if entry != null and image_id == "":
		entry.text = ""
	_sending = true
	_set_notice("")

	var body: Dictionary = {"body": text, "channel": channel}
	if image_id != "":
		body["image"] = image_id
	if channel == "private":
		body["to"] = _whisper_with

	var res: Dictionary = await Api.post("/api/chat/send", body)

	if not is_instance_valid(self) or not is_inside_tree():
		return
	_sending = false

	if res.get("ok", false):
		# STRAIGHT TO THE NEXT POLL rather than echoing it locally. The line
		# has an id and a server timestamp now, and drawing our own guess at
		# those would show a message that looks subtly unlike everyone else's.
		_stick_to_bottom = true
		_poll()
		if entry != null:
			entry.grab_focus()
		return

	# PUT IT BACK. The message was never said, and losing what somebody typed
	# because the server was busy is worse than the refusal itself.
	if entry != null and entry.text == "" and text != "":
		entry.text = text
	_set_notice(_refusal(res))
	push_warning("[CHAT] message refused: HTTP %d - %s (channel %s%s)" % [
		int(res.get("status", 0)), str(res.get("error", "")), channel,
		", with a picture" if image_id != "" else ""])


func _refusal(res: Dictionary) -> String:
	# THE SERVER'S OWN SENTENCE, whenever there is one.
	#
	# THIS FUNCTION USED TO THROW IT AWAY, and it is worth being exact about
	# how, because the shape of the mistake is the useful part. Api._request
	# returns {"ok", "status", "data", "error"} and has ALREADY dug the
	# server's explanation out of the body and put it in `error`. This read
	# res["message"] - a key that layer has never set - so every refusal not
	# named by status below fell through to the default and came out as
	# "That did not send."
	#
	# Which is the one answer nobody can act on. "That picture is over 8 MB",
	# "that file is not a picture this server can read", and "the server has
	# no such route - restart it" were all sitting in `error`, correct and
	# specific, and all three were shown as the same four useless words.
	var status: int = int(res.get("status", 0))
	var said: String = str(res.get("error", "")).strip_edges()

	# These few read better in this panel's voice than the server's, and they
	# are the ones where the server has nothing extra to add anyway.
	if status == 0:
		return ApiScript.no_answer_text()
	if status == 401:
		return "You are not signed in."
	# THE SERVER'S WORDS FOR A 429 TOO. There are four of them - typing too
	# fast, a picture too soon after the last, too many reports - and this
	# used to answer all of them "one picture every few seconds", so a player
	# typing quickly was told off about pictures.
	if status == 429:
		return said if said != "" else "Slow down a moment."
	if status == 503:
		return "This server cannot handle pictures yet (Pillow is not installed)." \
			if OS.is_debug_build() else "This server cannot take pictures right now."

	# EVERYTHING ELSE DEFERS. A 400 is the server telling you exactly what was
	# wrong with the file, and no sentence written here could be better.
	if said != "":
		return said
	if status == 413:
		return "That file is too big for the server to accept."
	if status == 405:
		# 405 ON THIS CLIENT HAS ONE CAUSE, and it cost an evening to read.
		# Every path here is posted to by exactly one function, so the method
		# is never in doubt - a "method not allowed" means the running server
		# does not have this route and something ELSE answered on that path.
		# In practice: it was started before the route was added.
		return "The server does not have that route. Restart it." if OS.is_debug_build() \
			else "The server could not take that right now."
	return "That did not send (HTTP %d)." % status
