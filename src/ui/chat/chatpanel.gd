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

# THE CROWNED'S CROWN, beside the owner's name here as well as over their head.
# Inline BBCode rather than a node, because a line of chat is one label and a
# badge has to flow with the text it belongs to.
#
# SIZED EXPLICITLY AT THE ART'S OWN 26x15. RichTextLabel will scale an [img] to
# whatever it is given, and anything but native size turns 26 columns of pixel
# art into a smear.
const CROWN_TAG := "[img=26x15]res://art/pack/icons/behemothcrown.png[/img] "

# The one rank that wears it. Anything else - dev, mod, player - gets its
# colour and nothing more.
const CROWN_RANK := "owner"

# The tint on the tab you are reading, against the ones you are not.
const TAB_ON := Color(1.0, 0.88, 0.62)
const TAB_OFF := Color(0.6, 0.56, 0.5)
const TAB_UNREAD := Color(1.0, 0.78, 0.35)


var _channel: String = "world"
var _whisper_with: String = ""
var _in_flight: bool = false
var _sending: bool = false
var _timezone_minutes: int = 0

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


func _ready() -> void:
	add_to_group("chatpanel")
	visible = false

	# READ ONCE. get_time_zone_from_system() is a system call and the offset
	# does not change while somebody is playing.
	var zone: Dictionary = Time.get_time_zone_from_system()
	_timezone_minutes = int(zone.get("bias", 0))

	for channel in CHANNELS:
		_feeds[channel] = {"cursor": 0, "lines": [], "unread": false}

	_build_tabs()

	if entry != null:
		entry.max_length = MAX_LENGTH
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

	# START FROM THE TAIL, NOT FROM WHERE WE LEFT OFF. A cursor kept across a
	# close would ask for everything said since, which after an hour away is a
	# page of context nobody wants and a truncated page at that. Zero means
	# "give me the recent conversation", which is what opening a chat window
	# is asking for.
	_feeds[_channel]["cursor"] = 0
	_feeds[_channel]["lines"] = []
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
			return "Waiting on guilds"
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

	if channel == "guild":
		_set_notice("Guilds are not in the game yet.")
		return
	if whispering and _whisper_with == "":
		_set_notice("Type who you want to whisper to, up in the corner.")
		return

	# A CHANNEL IS RE-READ FROM ITS TAIL WHEN YOU SWITCH TO IT, for the same
	# reason opening the window is: what you want when you look at a
	# conversation is the last of it, not everything since you last looked.
	_feeds[channel]["cursor"] = 0
	_feeds[channel]["lines"] = []
	_poll()


func _on_whisper_target_changed(text: String) -> void:
	var wanted: String = text.strip_edges()
	if wanted == _whisper_with:
		return
	_whisper_with = wanted
	if _channel != "private":
		return
	_feeds["private"]["cursor"] = 0
	_feeds["private"]["lines"] = []
	_render()
	if _whisper_with == "":
		_set_notice("Type who you want to whisper to, up in the corner.")
	else:
		_set_notice("")
		_poll()


# =============================================================================
# WHAT GOES IN THE LOG
# =============================================================================

func push_system_line(text: String, colour: Color) -> void:
	"""A server announcement, shown in the conversation and marked as one."""
	if text.strip_edges() == "":
		return
	# ALWAYS INTO THE WORLD CHANNEL. A maintenance notice is not a whisper and
	# it is not guild business; it belongs where everybody is looking.
	_add_line("world", {
		"kind": "system",
		"body": text,
		"colour": colour,
	})


func _add_line(channel: String, line: Dictionary) -> void:
	var feed: Dictionary = _feeds[channel]
	var kept: Array = feed["lines"]
	kept.append(line)

	# OLDEST OFF THE TOP, at LINES_KEPT. Without a ceiling a long session turns
	# the log into a slowly growing pile of nodes nobody can scroll back to.
	while kept.size() > LINES_KEPT:
		kept.pop_front()
		feed["unread"] = true

	if channel == _channel and visible:
		_render()
	elif channel != _channel:
		feed["unread"] = true
		_paint_tabs()


func _render() -> void:
	if lines_box == null:
		return

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
	_scroll_to_end.call_deferred()


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
	_feeds[_channel]["cursor"] = 0
	_feeds[_channel]["lines"] = []
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
		label.append_text("[color=#%s][SERVER][/color] [color=#%s]%s[/color]"
			% [hex, hex, _escape(str(line.get("body", "")))])
		return label

	var who: String = str(line.get("by", "?"))
	var rank: String = str(line.get("role", "player"))
	var stamp: String = _clock(int(line.get("at", 0)))
	var name_colour: String = Api.colour_for_role(rank).to_html(false)
	var crown: String = CROWN_TAG if rank == CROWN_RANK else ""
	# YOUR OWN NAME IS MARKED. In a channel everybody can write to, finding
	# where you last spoke is otherwise a scan of the whole box.
	var mark: String = " <" if who.to_lower() == Api.username.to_lower() else ""

	label.append_text("[color=#6b6055]%s[/color] %s[color=#%s]%s%s[/color]: %s" % [
		stamp, crown, name_colour, _escape(who), mark,
		_escape(str(line.get("body", "")))])
	return label


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

	var caption: String = str(line.get("body", "")).strip_edges()
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
	var crown: String = CROWN_TAG if rank == CROWN_RANK else ""
	header.append_text("[color=#6b6055]%s[/color] %s[color=#%s]%s[/color]: %s" % [
		_clock(int(line.get("at", 0))), crown,
		Api.colour_for_role(rank).to_html(false), _escape(who),
		_escape(caption) if caption != "" else "[color=#6b6055](a picture)[/color]"])
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


func _escape(text: String) -> String:
	# THE ONE THING A PUBLIC CHANNEL MUST NOT DO is hand the renderer whatever
	# somebody typed. This log renders BBCode so staff ranks can be coloured,
	# and BBCode is not only colour: [img]some-url[/img] makes the client
	# FETCH that url, and [url] makes a clickable link out of it. Turning every
	# opening bracket into the literal-bracket tag means a message can say
	# "[color=red]" and that is exactly what everyone reads.
	return text.replace("[", "[lb]")


func _clock(unix_time: int) -> String:
	if unix_time <= 0:
		return "--:--"
	var local: Dictionary = Time.get_datetime_dict_from_unix_time(
		unix_time + _timezone_minutes * 60)
	return "%02d:%02d" % [int(local.get("hour", 0)), int(local.get("minute", 0))]


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


func _poll() -> void:
	# Never two at once, and nothing to ask on behalf of nobody. Same guard as
	# the HUD's broadcast poll and for the same reason: a slow server must not
	# end up with a queue of requests stacked behind each other.
	# ONE GUARD, FOUR REASONS. Never two polls at once, nothing to ask on
	# behalf of nobody, nothing behind the guild tab yet, and a whisper with
	# no recipient is not a conversation to read.
	var nothing_to_ask: bool = (_in_flight
		or not Api.is_logged_in()
		or _channel == "guild"
		or (_channel == "private" and _whisper_with == ""))
	if nothing_to_ask:
		return

	var asked: String = _channel
	var path: String = "/api/chat?channel=%s&since=%d" % [
		asked, int(_feeds[asked]["cursor"])]
	if asked == "private":
		path += "&with=" + _whisper_with.uri_encode()

	_in_flight = true
	var res: Dictionary = await Api.get_json(path, Api.PROBE_TIMEOUT)

	# PAST AN AWAIT. Up to the timeout has passed and this node may be gone -
	# the player died, or the scene changed underneath it.
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_in_flight = false

	# SILENT ON FAILURE, DELIBERATELY. The HUD's own poll is what decides that
	# a session has ended, and it is already running; a chat window that threw
	# up an error every three seconds during a server restart would be the
	# loudest thing on screen and would be saying nothing new.
	if not res.get("ok", false):
		return

	var data = res.get("data", {})
	if not (data is Dictionary):
		return

	# TAKEN FROM EVERY ANSWER, INCLUDING ONE FOR THE WRONG CHANNEL. How long
	# until a picture may go to world does not depend on which channel was
	# read, and throwing the number away below because the tab changed would
	# leave the warning showing a wait that has already passed.
	if data.has("world_image_wait"):
		_world_wait = maxi(0, int(data.get("world_image_wait", 0)))
		_world_wait_read_at = float(Time.get_ticks_msec()) / 1000.0

	# THE ANSWER MAY BE FOR A CHANNEL NOBODY IS LOOKING AT ANY MORE. Three
	# seconds is long enough to change tab twice, and filing a world reply into
	# an open whisper would be a small disaster.
	if str(data.get("channel", asked)) != asked:
		return

	var pictures = data.get("images", {})
	for entry_data in data.get("messages", []):
		if not (entry_data is Dictionary):
			continue
		_add_line(asked, _line_from_server(entry_data, pictures))

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

	# A LINK ON ITS OWN IS A PICTURE. Nobody should have to find a button to
	# post one - they paste and press Enter, like everywhere else they have
	# ever pasted a link. A link with words around it stays a line of text.
	if _looks_like_picture_link(text):
		await _send_link(text)
		return

	if _channel == "guild":
		_set_notice("Guilds are not in the game yet.")
		return
	if _channel == "private" and _whisper_with == "":
		_set_notice("Type who you want to whisper to, up in the corner.")
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
			+ "and there is %s to go. Whisper it, or send it to friends."
			% _readable_wait(waiting))
	else:
		_set_notice("Ready - press Enter to send it.")


func _clear_pending() -> void:
	_pending = {}
	if attach_row != null:
		attach_row.visible = false
	if attach_thumb != null:
		attach_thumb.texture = null
	if entry != null:
		entry.placeholder_text = ENTRY_PLACEHOLDER


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
	return "%d seconds" % seconds


func _postable_channel() -> String:
	# WHERE A PICTURE CAN GO, and the sentence to show when the answer is
	# nowhere. Previously a picture posted to a channel you were not really in
	# was quietly redirected to world, which is a surprising place for a
	# private one to turn up.
	if _channel == "guild":
		_set_notice("Guilds are not in the game yet.")
		return ""
	if _channel == "private" and _whisper_with == "":
		_set_notice("Type who you want to whisper to, up in the corner.")
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
		return "No answer from the server. Is it running?"
	if status == 401:
		return "You are not signed in."
	if status == 429:
		return "Slow down a moment - one picture every few seconds."
	if status == 503:
		return "This server cannot handle pictures yet (Pillow is not installed)."

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
		return "The server does not have that route. Restart it."
	return "That did not send (HTTP %d)." % status
