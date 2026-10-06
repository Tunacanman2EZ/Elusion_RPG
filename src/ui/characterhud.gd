# main HUD overlay — shows HP/mana/stamina bars, nav buttons, hotbar, and panels.
# CanvasLayer renders on top of the world. polls active player every frame
# for stat changes and updates bars accordingly. owns lazy-instantiated
# panels (stats, bank, lootbag) so they persist across opens. inventory is
# eagerly instantiated so the hotbar's keys have a backpack to belong to from
# spawn - they are its cells 20-29.
#
# atomic save policy:
# every inventory mutation triggers a full save via the inventory_changed
# signal hook. loot bag transfers also save atomically (in the loot panel).
extends CanvasLayer

# Api's static helpers, called on the script and not on the autoload: a static
# function called through an instance is a warning in the editor's debugger.
const ApiScript := preload("res://src/systems/api.gd")


# =============================================================================
# CONSTANTS
# =============================================================================

const CHARACTER_SELECT_PATH := "res://scene/ui/menus/characterselect.tscn"
# NEW: log out now goes all the way back to the login screen (true logout),
# not just character select — see _on_logout_pressed(). CHARACTER_SELECT_PATH
# is kept in case a separate "switch character" action (distinct from a full
# logout) gets added later, even though nothing in this file uses it right
# now.
const LOGIN_MENU_PATH := "res://scene/ui/menus/loginmenu.tscn"

# HOW OFTEN THE CLIENT ASKS THE SERVER WHAT IS GOING ON. One call does three
# jobs - see _on_broadcast_poll_timeout() - so this is the only timer the HUD
# needs. Ten seconds is comfortably inside the server's ONLINE_WINDOW_SECONDS
# (45), so staff see this client as online, and well inside the default
# maintenance grace window (60) so a closing server is heard in time to save.
const BROADCAST_POLL_SECONDS := 10.0

# How many announcements stay on screen. Old ones scroll off the top.
const MESSAGES_KEPT := 5

# HOW LONG AN ANNOUNCEMENT STAYS UP, then how long it takes to fade out. The
# box is for news, and news that never leaves stops being news and starts being
# furniture - five lines of last week's maintenance parked above the menu bar.
# Eight seconds reads a two-line notice twice over; the chat log keeps every
# one of them for good (see _push_message).
const MESSAGE_SHOW_SECONDS := 8.0
const MESSAGE_FADE_SECONDS := 1.5

# Notices that had nowhere to be RECORDED yet. The chat panel is built the first
# time it is opened, and until then _push_message() had no log to write to - so
# a notice that faded from the box was simply gone. They wait here, oldest
# first, and are written into chat the moment it exists.
const UNLOGGED_KEPT := 50

# preloaded panel scenes
const INVENTORY_SCENE     := preload("res://scene/ui/inventory/inventory.tscn")
const STATSSCREEN_SCENE   := preload("res://scene/ui/statsscreen.tscn")
const EQUIPMENT_SCENE     := preload("res://scene/ui/equipment/equipmentpanel.tscn")
const OPTIONS_SCENE       := preload("res://scene/ui/menus/optionsscreen.tscn")
const MAPSCREEN_SCENE     := preload("res://scene/ui/menus/mapscreen.tscn")
const BANK_SCENE          := preload("res://scene/ui/bank/bankinventory.tscn")
const LOOTBAG_PANEL_SCENE := preload("res://scene/ui/lootbag/lootbaginventory.tscn")
const COOKING_PANEL_SCENE := preload("res://scene/ui/cooking/cookingscreen.tscn")
const SHOP_PANEL_SCENE    := preload("res://scene/ui/shop/shopinventory.tscn")
const KINGDOM_PANEL_SCENE := preload("res://scene/ui/kingdom/kingdomboard.tscn")
const TRADE_PANEL_SCENE   := preload("res://scene/ui/trade/tradepanel.tscn")
# The script as well, for its static result_line() - the one wording of "what a
# trade gave you", shared by the window's history and the HUD's announcement.
const TradePanelScript    := preload("res://src/ui/trade/tradepanel.gd")
const ChatPanelScript     := preload("res://src/ui/chat/chatpanel.gd")
# Owner-only save-viewer panel (see ownerpanel.gd). preload is fine
# here even though most players will never see it — the panel itself
# fails closed via Api.is_owner, so preloading the scene
# doesn't expose anything, it's just an inert resource until the owner
# actually toggles it with the backquote key.
const OWNER_PANEL_SCENE   := preload("res://scene/ui/owner/ownerpanel.tscn")
const ITEM_SPAWNER_SCENE  := preload("res://scene/ui/owner/itemspawner.tscn")
const STAFF_PANEL_SCENE   := preload("res://scene/ui/staff/staffpanel.tscn")
const STAFF_THEME         := preload("res://assets/themes/staff_ui_theme.tres")
const CHAT_PANEL_SCENE    := preload("res://scene/ui/chat/chatpanel.tscn")
const FRIENDS_PANEL_SCENE := preload("res://scene/ui/friends/friendspanel.tscn")
const PLAYERS_PANEL_SCENE := preload("res://scene/ui/players/playerspanel.tscn")
const GUILD_PANEL_SCENE := preload("res://scene/ui/guild/guildpanel.tscn")
const CONTROLS_SCENE := preload("res://scene/ui/controls/controlspanel.tscn")


# =============================================================================
# STATE
# =============================================================================

var active_character: Node = null

# stat bar references — resolved in _ready
# THE EXACT NUMBERS, printed over the bars.
#
# These are the answer to what the visible floor in _displayable() cannot give:
# a bar has to round somewhere, a number does not. So the bar stays readable at
# a glance and the label stays true to the point - and critically, the label
# reads the REAL value, never the floored one, or the two would agree with each
# other and both be wrong.
var healthvalue:   Label = null
var manavalue:     Label = null
var staminavalue:  Label = null

var healthbar:  TextureProgressBar = null
var magicbar:   TextureProgressBar = null
var staminabar: TextureProgressBar = null

# panel references — inventory is eagerly created in set_active_character,
# stats/bank/lootbag/owner stay lazy.
var inventory_screen: InventoryScreen = null

# THE PAPER DOLL - A PANEL OF ITS OWN, with its own nav button and the G key.
#
# It used to open and close with the backpack, on the argument that gear was
# dragged between them so both had to be on screen. That argument lost both its
# legs: clicking a weapon or armour in the bag equips it (use_item() routes
# WEAPON and ARMOR to _equip_item()), and equipping MOVES the item now, so the
# doll holds things the bag does not and is worth opening on its own.
#
# Open both and dragging between them still works. It sits immediately to the
# left of the inventory - the offsets are in equipmentpanel.tscn, and its right
# edge is the inventory's left edge less a small gap - so the two line up
# whenever both are up. It got wider when the character preview went in the
# middle of the doll, and it grew LEFTWARDS for that reason: growing the other
# way would have put it under the bag.
var equipment_panel:  EquipmentPanel  = null
var stats_screen:     Control         = null
var bank_screen:      Control         = null
var lootbag_panel:    Control         = null
var cooking_panel:    Control         = null
var shop_panel:       Control         = null
var kingdom_panel:    Control         = null
var trade_panel:      Control         = null
var owner_panel:      Control         = null
var item_spawner:     Control         = null
var staff_panel:      Control         = null
var chat_panel:       Control         = null
var friends_panel:    Control         = null
var players_panel:    Control         = null
var guild_panel:      Control         = null

# The server's announcements, and the cursor into them. 0 means "I just got
# here" and the server answers with the recent tail rather than the whole
# table. See read_broadcasts() in app.py.
var message_box:      PanelContainer   = null
var message_rows:     VBoxContainer    = null
var _unlogged_lines:  Array            = []
var _broadcast_cursor: int = 0
var _broadcast_poll_in_flight: bool = false

# Said once per closing, not once every ten seconds.
var _maintenance_warned: bool = false

# The last teleport id this client carried out. Kept so a move is not applied
# twice while the acknowledgement is still in flight - the poll can come round
# again before the server has been told.
var _teleport_done: int = 0

# The trade someone opened WITH you that this client has already announced, so
# the toast is said once per trade and not every ten seconds. See _read_trade().
var _trade_announced: String = ""
var options_screen:   Control         = null
var map_screen:       Control         = null
# Every key, and the welcome a new player sees once. See controlspanel.gd.
var controls_panel:   ControlsPanel   = null

# hotbar reference — resolved on _ready
var hotbar: Hotbar = null

# cached previous values so _process only re-reads targets when stats change
var _last_hp:      int = -1
var _last_mana:    int = -1
var _last_stamina: int = -1


# =============================================================================
# BAR SMOOTHING
# =============================================================================
# The bars EASE toward their value instead of snapping to it, and the reason
# is pixels rather than polish.
#
# A bar is 370 screen pixels wide. The warrior's hp at level 22 is 432. That
# is fewer pixels than points, so one point of hp is 0.86 of a pixel — a
# distance that cannot be drawn. Snapping the value meant the fill edge jumped
# an un-drawable amount several times a second, so it moved one pixel on some
# steps and none on others, in an irregular 0,1,1,0,1 pattern. That flutter is
# what read as the bars "wobbling", and it got noticeable the moment regen
# went from 1 point per second to seven.
#
# Easing makes the edge travel continuously instead. It still lands on whole
# pixels, but it crosses them in an even rhythm rather than stuttering, and it
# keeps working at any level — hp can grow to 5000 and the bar still moves
# smoothly, where widening the bar only buys a level or two.
#
# Stamina never wobbled because its bar has 320 pixels for 185 points: nearly
# two pixels per point, so every step was already a clean whole-pixel move.

# How fast a bar catches up, in "fraction of the remaining gap per second".
# Higher is snappier. 6.0 closes ~99.7% of a gap in a second.
const BAR_FILL_SPEED: float = 6.0

# Below this many points of difference, stop easing and just land on it.
# Without it the bar approaches the target asymptotically and never arrives.
const BAR_SNAP_THRESHOLD: float = 0.25

# EMPTY MUST MEAN DEAD, and without this it did not.
#
# A TextureProgressBar draws its fill as a fraction of the progress texture's
# width. The health bar's texture is 148px, so the smallest thing it can draw
# is 1/148th of the bar - and a level 50 tank has 1338 max HP, which is 0.22
# pixels per point. The last FOUR of that tank's hit points round away to
# nothing: the bar reads empty, the player is still alive, and every hit after
# that looks like damage being taken from an empty bar.
#
# A health bar has exactly one reading it must never get wrong, and that is
# this one. So a value above zero is never drawn as less than one pixel of
# fill. It over-reports at the very bottom - a sliver can mean anything from 1
# HP to about 9 on the biggest health pool in the game - and that is the right
# trade: "almost nothing" and "nothing" are different facts and have to look
# different. Exactly zero still draws empty, because that is the fact the
# player needs.
const BAR_MIN_VISIBLE_TEXTURE_PIXELS: float = 1.0

# drag-cursor state — see _update_drag_cursor().
# _mouse_mode_before_drag remembers what the pointer was doing before a drag
# started, so ending one restores that rather than assuming it was visible.
#
# It is typed Input.MouseMode, not int. Input.mouse_mode IS that enum, and
# assigning a plain int back into it makes Godot warn that an integer is being
# used where an enum is expected — the value is right, the type just throws
# away which enum it belongs to. Declaring the enum keeps the round-trip
# honest in both directions.
var _cursor_hidden_for_drag: bool = false
var _mouse_mode_before_drag: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# HIDDEN IN THE SCENE FILE, SHOWN HERE.
	#
	# Both this and the login menu are CanvasLayers, so the 2D editor draws them
	# over the map at a fixed screen position that does not scale with zoom -
	# which makes laying tiles at 30% zoom impossible. They are saved with
	# visible = false so the editor shows the world, and turned on here the
	# moment they enter the tree at runtime.
	#
	# THIS LINE IS WHAT MAKES THAT SAFE. Hiding them without it means they are
	# hidden in the game too, with no error and nothing in the log - the HUD just
	# is not there. If you ever see that, this is the line that went missing.
	visible = true

	add_to_group("hud")
	_resolve_bar_references()
	_resolve_hotbar()
	_wire_nav_buttons()
	_add_version_to_menu()
	_add_owner_button()
	_build_message_box()
	_warn_unprotected_staff()
	# A NEW AREA'S HUD KEEPS THE DOT: something said to you before the door
	# is still unread after it.
	if _chat_dot and _chat_seen_by == Api.username:
		_mark_chat_button(true)
	# AND THE FRIENDS AND GUILD DOTS, for a request still waiting on you.
	if _asks_said_by == Api.username:
		_paint_ask_buttons()
	_build_status_strip()
	_start_broadcast_poll()
	_wire_hotbar()


# The keys that play the game. project.godot puts WASD and the arrows in
# ui_left/right/up/down as well as the move_ actions, and Space in ui_accept as
# well as attack.
const WORLD_KEYS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down", &"attack"]


func _input(event: InputEvent) -> void:
	# A GAME KEY TAKES THE KEYBOARD BACK FROM A CLICKED CONTROL. A click gives a
	# button or slider the keyboard focus, and the GUI then reads the same
	# presses as the player. Measured in Options: after one click on Damage
	# numbers, walking moved the focus from button to button, and Space swung
	# the sword and flipped the setting. After a click on the volume slider,
	# walking right turned the volume up.
	#
	# _input runs before the GUI does, so releasing focus here means the GUI
	# never sees the key as navigation. Movement is polled, so the character
	# walks whether or not this runs. A text box keeps the keyboard, since those
	# keys are letters in it.
	release_for_world_key(event, get_viewport())
	_click_outside_nav_menus(event)


static func release_for_world_key(event: InputEvent, viewport: Viewport) -> bool:
	"""Takes the focus off a clicked control when `event` is a game key being
	pressed. True when it did."""
	var key := event as InputEventKey
	if key == null or not key.pressed or not is_world_key(key):
		return false
	var focused: Control = viewport.gui_get_focus_owner()
	if focused == null or keeps_the_keyboard(focused):
		return false
	focused.release_focus()
	return true


static func is_world_key(event: InputEvent) -> bool:
	# Not exact_match: Shift is sprint, and Shift+W is still walking up.
	for action in WORLD_KEYS:
		if event.is_action(action):
			return true
	return false


static func keeps_the_keyboard(control: Control) -> bool:
	"""True for a text box the player can type in. The same test as
	player.gd's _typing_in_ui(), which stops those keys moving the character."""
	if not control.is_visible_in_tree():
		return false
	if control is LineEdit:
		return (control as LineEdit).editable
	if control is TextEdit:
		return (control as TextEdit).editable
	return false


func _unhandled_input(event: InputEvent) -> void:
	# ESCAPE CLOSES WHATEVER IS OPEN. hide_panel() and is_panel_open() were
	# written for this handler and then sat uncalled for months — every panel
	# closed only by its own X, so a player with the bank up had to go find it.
	#
	# THE GUARD IS THE POINT. An unconditional hide_panel() would eat every
	# Escape press in the game, and the pause menu this project will eventually
	# want would never see one. Nothing open means this branch does not run.
	#
	# RAW KEYCODE, NOT "ui_cancel". project.godot redefines six ui_ actions and
	# ui_cancel is not among them, so it would be resolving against an engine
	# default that nothing in this project has ever declared. The backquote
	# check below reads the keycode for the same reason.
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		# AN OPEN DROPDOWN GOES FIRST: it is the thing on top, and it is the
		# thing the player just opened.
		if close_nav_menus():
			get_viewport().set_input_as_handled()
			return
		# CLOSE FIRST, OPEN SECOND. Escape means "get this off my screen" if
		# there is anything on it, and only means "show me the options" when
		# there is not — which is the behaviour the comment above predicted
		# when it said the pause menu this project will eventually want would
		# need to see the press.
		#
		# The open branch is guarded by _any_panel_visible(), not
		# is_panel_open(): the shop and the trade window are deliberately not
		# closed by Escape, and stacking options on top of one would be worse
		# than doing nothing.
		if is_panel_open():
			hide_panel()
			get_viewport().set_input_as_handled()
			return
		if not _any_panel_visible():
			toggle_options()
			get_viewport().set_input_as_handled()
			return

	# THE PANEL KEYS. inventory_toggle is I, character_toggle is C, and
	# minimap_toggle is M — actions rather than raw keycodes, because these are
	# the three the options screen lets a player rebind and a hardcoded keycode
	# would ignore whatever they chose.
	#
	# WHY THEY COULD NOT EXIST BEFORE. player.gd's debug block owned the bare
	# letters: I granted an electric sprite pet, M drained thirty mana, and M
	# was ALSO minimap_toggle, so opening the map cost you mana and nothing
	# anywhere said the two were the same key. Those grants are behind Ctrl now.
	#
	# is_action_pressed, NOT the keycode, and not ui_* either — see the Escape
	# note above for why this project cannot trust an engine default it has
	# never declared.
	if event.is_action_pressed("inventory_toggle"):
		toggle_inventory()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("character_toggle"):
		toggle_stats()
		get_viewport().set_input_as_handled()
		return

	# THE DOLL ON ITS OWN - G, or the Equipment button on the nav bar. It no
	# longer comes up with the bag at all; see the note on equipment_panel.
	if event.is_action_pressed("equipment_toggle"):
		toggle_equipment()
		get_viewport().set_input_as_handled()
		return

	# M, THE MAP. The comment above has named minimap_toggle as one of these
	# keys since the debug block gave M back - and there was no branch for it,
	# so M did nothing and the map opened only from the nav bar.
	if event.is_action_pressed("minimap_toggle"):
		toggle_map()
		get_viewport().set_input_as_handled()
		return

	# H, EVERY KEY IN THE GAME (day 1: nothing told a new player any of them).
	# An action like the four above, so it can be rebound with them.
	if event.is_action_pressed("help_toggle"):
		toggle_controls()
		get_viewport().set_input_as_handled()
		return

	# Backquote / tilde toggles the owner panel. Anyone who is not the owner
	# gets no response at all by design, not even an error — see
	# _toggle_owner_panel().
	#
	# The whole function row was spoken for when this was chosen: F1-F7 were
	# player.gd's debug keys (gone since 0.7.1, the panel does their work),
	# and F8 is Godot's own "stop the running project" shortcut, so binding to
	# it closed the game. Backquote is the
	# conventional dev-console key and collides with nothing here.
	#
	# It was Shift+A before that, which collided with normal play: `interact`
	# WAS Shift and `move_left` is A, so interacting while walking left toggled
	# the panel. interact is E now and sprint has taken Shift, so that specific
	# collision is gone — the binding stays on backquote anyway, because a dev
	# console key that is also a letter is how the collision happened.
	if event is InputEventKey and event.pressed and event.keycode == KEY_QUOTELEFT:
		_toggle_owner_panel()


func _toggle_owner_panel() -> void:
	# THE OWNER SPECIFICALLY, not any rank that can be handed out. A mod or a
	# dev is granted and can be revoked; the owner is named in the server's
	# environment and is the one account that cannot be either. Read straight
	# from Api because rank is never persisted — there is no file holding it
	# to edit.
	#
	# Cosmetic either way. The server is what actually refuses; this only
	# decides whether the panel opens.
	if not Api.is_owner:
		return

	if owner_panel == null:
		owner_panel = OWNER_PANEL_SCENE.instantiate()
		add_child(owner_panel)

	owner_panel.visible = not owner_panel.visible


func toggle_item_spawner() -> void:
	# The owner's item menu (itemspawner.gd). Owner-gated here as a courtesy,
	# like the GM panel; the server refuses everyone else regardless.
	if not Api.is_owner:
		return
	if item_spawner == null:
		item_spawner = ITEM_SPAWNER_SCENE.instantiate()
		item_spawner.visible = false
		add_child(item_spawner)
	if item_spawner.visible:
		item_spawner.close()
	else:
		item_spawner.open()


func _process(_delta: float) -> void:
	# runs before the active_character guard below on purpose — a drag can be
	# in flight during a scene change, and the cursor still has to come back.
	_update_drag_cursor()

	# ALSO BEFORE THE GUARD. Losing the server is exactly as true with no
	# character loaded as with one, and a countdown that stopped ticking while
	# the player was in a menu would be a countdown that lied.
	_tick_connection_status()

	# ALSO BEFORE THE GUARD, for the same reason: a notice that arrives while
	# no character is loaded must still fade, or it sits there until one is.
	_age_messages(Time.get_ticks_msec())

	if active_character == null:
		return

	var hp:      int = active_character.get("hp")
	var mana:    int = active_character.get("mana")
	var stamina: int = active_character.get("stamina")

	if hp != _last_hp or mana != _last_mana or stamina != _last_stamina:
		update_bars()
		_last_hp      = hp
		_last_mana    = mana
		_last_stamina = stamina

	# EVERY frame, not just when a stat changed — the easing needs continuous
	# ticks to move between the discrete points it is easing toward.
	_animate_bars(_delta)

	if stats_screen != null and stats_screen.visible:
		stats_screen.update_display()


# =============================================================================
# DRAG CURSOR
# =============================================================================

func _update_drag_cursor() -> void:
	# While an item is being dragged, the item icon IS the pointer — the
	# system cursor is hidden entirely so nothing rides on top of it.
	#
	# This also removes the circle-with-a-slash for free. That shape is just
	# the cursor in its CURSOR_FORBIDDEN state, which Godot picks whenever
	# whatever sits under the pointer refuses the drag — panel headers, the
	# gaps between slots, the game world between two windows. With no cursor
	# drawn at all there is no shape left to switch to.
	#
	# MOUSE_MODE_HIDDEN only stops it being DRAWN. Position, motion and clicks
	# all still work normally, unlike MOUSE_MODE_CAPTURED. The moment the drag
	# ends the pointer comes straight back.
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return

	var dragging: bool = viewport.gui_is_dragging()
	if dragging == _cursor_hidden_for_drag:
		return

	if dragging:
		# remember the real previous mode instead of hardcoding VISIBLE, so
		# this can never be the thing that turns a hidden pointer back on.
		_mouse_mode_before_drag = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	else:
		Input.mouse_mode = _mouse_mode_before_drag

	_cursor_hidden_for_drag = dragging


func _exit_tree() -> void:
	# a scene change mid-drag would otherwise leave the player with no cursor
	# and no HUD left running to give it back.
	if _cursor_hidden_for_drag:
		Input.mouse_mode = _mouse_mode_before_drag
		_cursor_hidden_for_drag = false


# =============================================================================
# INITIALIZATION HELPERS
# =============================================================================

func _resolve_bar_references() -> void:
	healthvalue   = get_node_or_null("barcontainer/healthbar/healthvalue")
	manavalue     = get_node_or_null("barcontainer/magicbar/manavalue")
	staminavalue  = get_node_or_null("barcontainer/staminabar/staminavalue")

	healthbar  = get_node_or_null("barcontainer/healthbar")
	magicbar   = get_node_or_null("barcontainer/magicbar")
	staminabar = get_node_or_null("barcontainer/staminabar")

	if healthbar == null:
		push_warning("HUD: healthbar not found at barcontainer/healthbar")
	if magicbar == null:
		push_warning("HUD: magicbar not found at barcontainer/magicbar")
	if staminabar == null:
		push_warning("HUD: staminabar not found at barcontainer/staminabar")

	if OS.is_debug_build():
		print("[HUD]  healthbar %s, magicbar %s, staminabar %s" % [
			"OK" if healthbar else "MISSING",
			"OK" if magicbar else "MISSING",
			"OK" if staminabar else "MISSING",
		])


func _resolve_hotbar() -> void:
	if has_node("%hotbar"):
		hotbar = get_node("%hotbar") as Hotbar
	if hotbar == null:
		push_warning("HUD: hotbar node not found (looked up via %hotbar unique name)")


func _wire_nav_buttons() -> void:
	# EVERY BUTTON BY ITS UNIQUE NAME, wherever it sits. Five of them live in the
	# Social dropdown and four in Menu now, and the next rearrangement will move
	# them again; a lookup that goes through %navbuttons would find none of them.
	var nav: Node = get_node_or_null("%navbuttons")
	if nav == null:
		return

	for name_key in NAV_BUTTON_NAMES:
		var button: Button = _nav_button(name_key)
		if button != null:
			button.focus_mode = Control.FOCUS_NONE

	# WHERE THE BAR SITS, AND WHY. A .tscn cannot hold a comment the editor will
	# not strip on the next save, so the numbers are explained here.
	#
	# navframe is pinned to the BOTTOM LEFT: anchors_preset 12 with offset_bottom
	# -8 and grow_vertical = BEGIN, so its bottom edge stays 8px off the floor and
	# it grows UPWARD when the staff row appears. The ordinary menu therefore
	# lands in exactly the same place whether or not you are the owner.
	#
	# offset_right = -334 puts its right edge at x=946. Everything in the bottom
	# right is what that number is dodging: the hotbar at x 956-1276, and the
	# health, magic and stamina bars, whose left edge is x=984 and which run down
	# to y=709 - straight through the bar's height. 946 clears the nearest of
	# them by 10px. It is an anchor rather than a fixed width so the gap holds
	# wherever the right edge ends up.
	#
	# EIGHT BUTTONS, NOT FOURTEEN (day 1: "the bottom bar is crowded"). The
	# windows a player opens every few minutes stay on the bar; Friends,
	# Players, Guild, Trade and Kingdom open from Social, and Controls, Options,
	# Switch character and Log out from Menu. The buttons share the bar's width
	# (FILL|EXPAND), so eight of them get bigger text than fourteen could.
	var bindings := {
		"inventorybutton":         "_on_inventory_pressed",
		"equipmentbutton":         "_on_equipment_pressed",
		"statsbutton":             "_on_stats_pressed",
		"shopbutton":              "_on_shop_pressed",
		"kingdombutton":           "_on_kingdom_pressed",
		"tradebutton":             "_on_trade_pressed",
		"mapbutton":               "_on_map_pressed",
		"optionsbutton":           "_on_options_pressed",
		"chatbutton":              "_on_chat_pressed",
		"friendsbutton":           "_on_friends_pressed",
		"playersbutton":           "_on_players_pressed",
		"guildbutton":             "_on_guild_pressed",
		"logoutbutton":            "_on_logout_pressed",
		# NEW: distinct from logout — returns to character select without
		# clearing the logged-in session, so no re-entering a password.
		"switchcharacterbutton":   "_on_switch_character_pressed",
		"controlsbutton":          "_on_controls_pressed",
	}
	for btn_name in bindings:
		var button: Button = _nav_button(btn_name)
		if button == null:
			continue
		# A CHOICE CLOSES ITS DROPDOWN, and a button on the bar closes whichever
		# is open, before the window it names comes up.
		button.pressed.connect(close_nav_menus)
		button.pressed.connect(Callable(self, bindings[btn_name]))

	for toggle_name in NAV_GROUPS:
		var toggle: Button = _nav_button(toggle_name)
		if toggle != null:
			toggle.pressed.connect(toggle_nav_menu.bind(toggle_name))

	# THE KEY IN THE HINT, read from the input map like the Controls card reads
	# it, so a rebound key is never advertised wrong.
	for btn_name in NAV_KEY_HINTS:
		var button: Button = _nav_button(btn_name)
		if button != null and InputMap.has_action(NAV_KEY_HINTS[btn_name]):
			button.tooltip_text = "%s (%s)" % [button.tooltip_text,
				ControlsPanel.action_key(NAV_KEY_HINTS[btn_name])]
	_paint_group_dots()


# =============================================================================
# THE BAR'S TWO DROPDOWNS - SOCIAL AND MENU
# =============================================================================

# Every button the bar owns, on the bar or in a dropdown.
const NAV_BUTTON_NAMES := [
	"inventorybutton", "equipmentbutton", "statsbutton", "shopbutton", "mapbutton",
	"chatbutton", "socialbutton", "menubutton",
	"friendsbutton", "playersbutton", "guildbutton", "tradebutton", "kingdombutton",
	"controlsbutton", "optionsbutton", "switchcharacterbutton", "logoutbutton",
]

# toggle button -> [the dropdown it opens, the words it says]
const NAV_GROUPS := {
	"socialbutton": ["socialmenu", "Social"],
	"menubutton":   ["systemmenu", "Menu"],
}

const NAV_KEY_HINTS := {
	"inventorybutton": "inventory_toggle",
	"equipmentbutton": "equipment_toggle",
	"statsbutton":     "character_toggle",
	"mapbutton":       "minimap_toggle",
	"controlsbutton":  "help_toggle",
}

# Room left between a dropdown and the button it opened from.
const NAV_MENU_GAP := 6.0


func _nav_button(button_name: String) -> Button:
	return get_node_or_null("%" + button_name) as Button


func _nav_menu(toggle_name: String) -> Control:
	var group: Array = NAV_GROUPS.get(toggle_name, [])
	return get_node_or_null("%" + String(group[0])) as Control if not group.is_empty() else null


func _add_version_to_menu() -> void:
	# WHICH BUILD THIS IS, at the foot of the Menu dropdown under Log out, so a
	# player can tell you without going back to the login screen. Quiet and
	# not a button: nothing happens if it is clicked.
	var items: Node = get_node_or_null("%systemmenu/systemitems")
	if items == null or items.get_node_or_null("versionlabel") != null:
		return
	var tag := Label.new()
	tag.name = "versionlabel"
	tag.text = "Elusion %s" % GameConstants.version_text()
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 11)
	tag.add_theme_color_override("font_color", Color(0.62, 0.58, 0.52))
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	items.add_child(tag)


func toggle_nav_menu(toggle_name: String) -> void:
	var menu: Control = _nav_menu(toggle_name)
	if menu == null:
		return
	var was_open: bool = menu.visible
	close_nav_menus()
	if was_open:
		return
	var toggle: Button = _nav_button(toggle_name)
	menu.visible = true
	# ON TOP OF EVERY WINDOW. The windows are added to this layer after the
	# scene's own nodes, so without this a window opened earlier draws over it.
	menu.move_to_front()
	menu.reset_size()
	if toggle != null and menu.is_inside_tree():
		menu.position = nav_menu_position(toggle.get_global_rect(), menu.size,
			menu.get_viewport_rect().size)


func close_nav_menus() -> bool:
	"""Shuts both dropdowns. True when one was open."""
	var was_open: bool = false
	for toggle_name in NAV_GROUPS:
		var menu: Control = _nav_menu(toggle_name)
		if menu != null and menu.visible:
			menu.visible = false
			was_open = true
	return was_open


static func nav_menu_position(button: Rect2, menu_size: Vector2, screen: Vector2) -> Vector2:
	"""Where a dropdown goes: ABOVE its button, since the bar sits on the floor,
	with the RIGHT edges lined up, and pulled back onto the screen at either side.

	Right, not left: Menu is the last button on the bar, and a dropdown hanging
	off its left edge ran 50px past the bar's end into the health bars - the
	exact strip the bar's own right edge is placed to dodge."""
	var x: float = clampf(button.end.x - menu_size.x, 0.0, maxf(0.0, screen.x - menu_size.x))
	var y: float = maxf(0.0, button.position.y - menu_size.y - NAV_MENU_GAP)
	return Vector2(x, y).floor()


func _click_outside_nav_menus(event: InputEvent) -> void:
	"""A click anywhere but an open dropdown or its own button shuts it, the way
	a menu does everywhere else. The click is not eaten: it still does whatever
	it was going to do."""
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	for toggle_name in NAV_GROUPS:
		var menu: Control = _nav_menu(toggle_name)
		if menu == null or not menu.visible:
			continue
		var toggle: Button = _nav_button(toggle_name)
		var inside: bool = menu.get_global_rect().has_point(click.position) \
			or (toggle != null and toggle.get_global_rect().has_point(click.position))
		if not inside:
			menu.visible = false


func _paint_group_dots() -> void:
	"""A dropdown's button wears the dot of anything inside it, so a friend
	request or a trade is still seen with Social shut. The button inside keeps
	its own dot and says who."""
	for toggle_name in NAV_GROUPS:
		var toggle: Button = _nav_button(toggle_name)
		var menu: Control = _nav_menu(toggle_name)
		if toggle == null or menu == null:
			continue
		if not toggle.has_meta("dot_base"):
			toggle.set_meta("dot_base", toggle.tooltip_text)
		var lit: Array[String] = []
		var colour: Variant = null
		for child in menu.find_children("*", "Button", true, false):
			var item: Button = child as Button
			if item.text.ends_with(" •"):
				lit.append(item.text.trim_suffix(" •"))
				if colour == null and item.has_theme_color_override("font_color"):
					colour = item.get_theme_color("font_color")
		var words: String = String(NAV_GROUPS[toggle_name][1])
		if lit.is_empty():
			toggle.text = words
			toggle.tooltip_text = String(toggle.get_meta("dot_base"))
			toggle.remove_theme_color_override("font_color")
		else:
			toggle.text = "%s •" % words
			toggle.tooltip_text = "Waiting for you: %s" % ", ".join(lit)
			toggle.add_theme_color_override("font_color", colour if colour is Color else ASK_COLOUR)


func _add_owner_button() -> void:
	# THE STAFF ROW: Staff for mods and up, and Owner and Powers for the owner.
	#
	# characterhud.tscn has carried a "staffrow" with a hidden Staff button
	# since the staff panel was built - and for all that time NOTHING SHOWED
	# IT. This function made the row for the owner's two buttons and hid it
	# from everybody else, mods included, so the moderation desk a mod was
	# meant to run the game from had no door. It was tested, drawn, and
	# unreachable: the recurring bug in this project, a finished half with
	# nothing joined to it. _test_the_staff_desk() now presses the button.
	#
	# OWNER AND POWERS ARE STILL BUILT IN CODE, AND ONLY FOR THE OWNER. A
	# button that exists in the .tscn exists for every player - hidden, but
	# present, and one `visible = true` in a modified client away from being
	# pressed. The server refuses every one of these calls to anyone else
	# regardless, so this is about not shipping a door rather than about the
	# lock. The Staff button is the exception because it was always in the
	# scene, and what it opens asks require_role("mod") for every byte.
	var row: Control = get_node_or_null("%staffrow") as Control
	if row == null:
		return

	# AN EMPTY ROW IS STILL A ROW. Left visible it contributes nothing but the
	# VBox's 4px of separation, which reads as the bar sitting slightly crooked
	# on every ordinary player's screen. Hidden, navframe shrinks to exactly one
	# row of buttons.
	#
	# AND ONLY A STAFF BAR IS TWO ROWS TALL: 6 top + 24 + 4 + 28 + 6 bottom = 68
	# against a player's 40. Since navframe grows upward from the floor, that
	# difference is spent on the staff row and the ordinary menu does not move -
	# which is why staffrow is declared FIRST in the scene, above navbuttons
	# rather than below it.
	if not is_staff():
		row.visible = false
		return
	row.visible = true

	var staff_button: Button = get_node_or_null("%staffbutton") as Button
	if staff_button != null:
		staff_button.visible = true
		staff_button.tooltip_text = "Players, sanctions, notes and the moderation log"
		_style_staff_row_button(staff_button)
		if not staff_button.pressed.is_connected(_toggle_staff_panel):
			staff_button.pressed.connect(_toggle_staff_panel)

	if not Api.is_owner or row.has_node("ownerbutton"):
		return

	for spec in [
		["ownerbutton", "Owner",
			"Owner tools: view, kick, ban, rank, and the server switch",
			_toggle_owner_panel],
		["powersbutton", "Powers",
			"What mod, dev and owner can each do - read from the live server",
			_toggle_powers_panel],
		# THE ITEM MENU had a button here (day 2). It opens from the GM panel's
		# Testing tab now, with Set level beside it (5 Oct, the owner's call);
		# toggle_item_spawner() below is still what opens it.
	]:
		var button := Button.new()
		button.name = String(spec[0])
		button.text = String(spec[1])
		button.tooltip_text = String(spec[2])
		_style_staff_row_button(button)
		button.pressed.connect(spec[3])
		row.add_child(button)


func _style_staff_row_button(button: Button) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 12)
	# Matched to the nav row below by hand. That row gets its height from a
	# custom_minimum_size on the container, which cannot be used here - it
	# would hold the row open at that height for every player who is not
	# staff, and this row has to collapse to nothing.
	button.custom_minimum_size = Vector2(0.0, 24.0)
	# Staff tools read warmer than the ordinary menu, so a glance tells you
	# which row can close the server and which one opens your bag.
	button.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))


const STAFF_BUTTON_TEXT := "Staff"


func _mark_open_reports(count: int, lines: int = -1) -> void:
	"""Players reported and still waiting for staff, on the Staff button - a
	report nobody sees is a report nobody reads. The server sends 0 to anyone
	who is not staff.

	PLAYERS, NOT LINES, since the Reports tab became one card per player:
	twenty lines from one spammer are "Staff (1)", not "Staff (20)". `lines`
	is the count of lines behind them, for the tooltip; -1 when the server is
	one from before the cards and `count` is itself lines."""
	var staff_button: Button = get_node_or_null("%staffbutton") as Button
	if staff_button == null or not is_staff():
		return
	staff_button.text = STAFF_BUTTON_TEXT if count <= 0 else "%s (%d)" % [STAFF_BUTTON_TEXT, count]
	var waiting: String = ""
	if count > 0 and lines < 0:
		waiting = "\n%d reported line%s waiting - see the Reports tab." % [count, "" if count == 1 else "s"]
	elif count > 0:
		waiting = "\n%d player%s reported (%d line%s) - see the Reports tab." % [
			count, "" if count == 1 else "s", lines, "" if lines == 1 else "s"]
	staff_button.tooltip_text = "Players, sanctions, notes and the moderation log" + waiting


static func is_staff() -> bool:
	# Mod and up, which is what require_role("mod") admits on the server.
	# The owner is asked for by name as well as by rank, because Api.role is
	# whatever the login answer said and is_owner is the one flag that
	# cannot be granted.
	return Api.is_owner or Api.role_at_least("mod")


func _toggle_staff_panel() -> void:
	# Cosmetic, like the owner's: every route the desk calls is
	# require_role("mod") on the server, which is the gate that counts.
	if not is_staff():
		return
	if staff_panel == null:
		staff_panel = STAFF_PANEL_SCENE.instantiate()
		add_child(staff_panel)
	await staff_panel.toggle_panel()


func _toggle_powers_panel() -> void:
	# Owner-gated here as a courtesy; the SERVER is the gate that counts, and
	# /api/staff/powers is require_role("mod") on its way in.
	if not Api.is_owner:
		return

	var panel: Control = get_node_or_null("powerspanel")
	if panel != null:
		panel.visible = not panel.visible
		if panel.visible:
			_load_powers()
		return

	var frame := PanelContainer.new()
	frame.name = "powerspanel"
	frame.anchor_left = 0.5
	frame.anchor_top = 0.5
	frame.anchor_right = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -250.0
	frame.offset_top = -230.0
	frame.offset_right = 250.0
	frame.offset_bottom = 230.0

	# THE STAFF WINDOWS' LOOK: navy, with the inventory's gold frame, header
	# box and boxes. One theme for Owner, Staff and Powers (staff_ui_theme.tres).
	frame.theme = STAFF_THEME
	var margin := MarginContainer.new()
	margin.name = "margin"
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	frame.add_child(margin)

	# A HEADER WITH THE PANEL'S ×, like every other window. The only way out
	# used to be the button that opened it.
	var body := VBoxContainer.new()
	body.name = "body"
	body.add_theme_constant_override("separation", 8)
	var header_box := PanelContainer.new()
	header_box.name = "header"
	header_box.theme_type_variation = &"PanelHeader"
	var header := HBoxContainer.new()
	header.name = "headerrow"
	header_box.add_child(header)
	var title := Label.new()
	title.text = "RANKS AND POWERS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", Color(0.93, 0.73, 0.30))
	title.add_theme_font_size_override("font_size", 17)
	header.add_child(title)
	var powers_close := Button.new()
	powers_close.name = "powersclosebutton"
	powers_close.text = "×"
	powers_close.custom_minimum_size = Vector2(24, 24)
	powers_close.focus_mode = Control.FOCUS_NONE
	powers_close.tooltip_text = "Close"
	powers_close.pressed.connect(_close_powers_panel)
	header.add_child(powers_close)
	body.add_child(header_box)

	var list_box := PanelContainer.new()
	list_box.name = "box"
	list_box.theme_type_variation = &"PanelSub"
	list_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list_margin := MarginContainer.new()
	list_margin.name = "margin"
	for side in ["left", "top", "right", "bottom"]:
		list_margin.add_theme_constant_override("margin_" + side, 8)
	list_box.add_child(list_margin)
	var scroll := ScrollContainer.new()
	scroll.name = "scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rows := VBoxContainer.new()
	rows.name = "rows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	list_margin.add_child(scroll)
	body.add_child(list_box)
	margin.add_child(body)
	add_child(frame)

	_load_powers()


func _close_powers_panel() -> void:
	var panel: Control = get_node_or_null("powerspanel")
	if panel != null:
		panel.visible = false


const POWERS_ROWS := "powerspanel/margin/body/box/margin/scroll/rows"


func _powers_line(rows: VBoxContainer, text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	rows.add_child(label)
	return label


func _load_powers() -> void:
	var rows: VBoxContainer = get_node_or_null(POWERS_ROWS)
	if rows == null:
		return
	for child in rows.get_children():
		child.queue_free()

	_powers_line(rows, "Read from the server's own route decorators, not a hand-kept list."
		+ " Point at a line to see the route behind it.", Color(0.45, 0.50, 0.58), 11)

	var res: Dictionary = await Api.get_json("/api/staff/powers", Api.PROBE_TIMEOUT)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	rows = get_node_or_null(POWERS_ROWS)
	if rows == null:
		return

	if not res.get("ok", false):
		_powers_line(rows, "Could not read the server: %s" % str(res.get("error", "")),
			Color(0.95, 0.45, 0.35), 13)
		return

	var data = res.get("data", {})
	if not (data is Dictionary):
		return
	_render_powers(rows, data)


# THE POWERS IN WORDS. Every route arrives with "what", the first line of its
# docstring, and this window used to print only the method and the path - a
# column of "POST /api/staff/ban" that only someone who had read app.py could
# use. The sentence is the line now and the route is its tooltip. A server
# from before the change sends the same fields, so this needs no new server.
func _render_powers(rows: VBoxContainer, data: Dictionary) -> void:
	for entry in data.get("ladder", []):
		if not (entry is Dictionary):
			continue
		var rank: String = str(entry.get("rank", "?")).to_upper()
		var grantable: bool = bool(entry.get("grantable", false))
		_powers_line(rows, "", Color(1, 1, 1), 4)
		_powers_line(rows, "%s%s" % [rank, "" if grantable else "   (cannot be granted)"],
			Color(0.82, 0.70, 0.45), 14)

		var routes: Array = entry.get("routes", [])
		if routes.is_empty() and entry.get("notes", []).is_empty():
			_powers_line(rows, "    nothing beyond playing the game", Color(0.55, 0.60, 0.68), 12)
		for route in routes:
			if route is Dictionary:
				var line: Label = _powers_line(rows, "    " + power_words(route),
					Color(0.78, 0.83, 0.89), 12)
				# A Label ignores the mouse by default, and a control that
				# ignores the mouse never shows its tooltip.
				line.tooltip_text = "%s %s" % [str(route.get("method", "")), str(route.get("path", ""))]
				line.mouse_filter = Control.MOUSE_FILTER_PASS
		for note in entry.get("notes", []):
			_powers_line(rows, "    - %s" % str(note), Color(0.93, 0.80, 0.55), 12)

	_powers_line(rows, "", Color(1, 1, 1), 6)
	var may_grant: Array = data.get("you_may_grant", [])
	var grant_text: String = "nothing"
	if not may_grant.is_empty():
		grant_text = ", ".join(PackedStringArray(may_grant))
	_powers_line(rows, "You are %s. You may grant: %s" % [str(data.get("you_are", "?")), grant_text],
		Color(0.43, 0.84, 0.49), 12)


# One power as a sentence. The route itself when the server has no sentence
# for it (a docstring that starts with its "---", which is how the gold supply
# read "---" here), and without "(owner only)" or "(staff only)", which under
# the OWNER or MOD heading says the same thing twice.
static func power_words(route: Dictionary) -> String:
	var what: String = str(route.get("what", "")).strip_edges()
	if what == "" or what.begins_with("---"):
		return "%s  %s" % [str(route.get("method", "")), str(route.get("path", ""))]
	for said_twice in [" (owner only)", " (staff only)"]:
		what = what.trim_suffix(said_twice)
	return what


func _build_message_box() -> void:
	# Built in code rather than in characterhud.tscn so the HUD scene is not
	# touched: every player gets this, and a scene edit is the thing most likely
	# to collide with work in the editor.
	if has_node("messagebox"):
		return

	var frame := PanelContainer.new()
	frame.name = "messagebox"
	# BOTTOM LEFT, STACKED ABOVE THE MENU BAR. This used to sit at -168/-62,
	# which was the free corner until the menu bar moved down here and took the
	# floor. The numbers below put its bottom edge at y=636, and the bar's top
	# edge is y=644 for the owner (two rows) or 672 for everyone else - so it
	# clears the taller of the two by 8px and never has to know which it is.
	#
	# Sized for the OWNER'S bar on purpose. Measuring the bar and positioning to
	# suit would be exact, but this is built in _ready() before the staff row has
	# been shown or hidden, so it would measure the wrong thing half the time.
	frame.anchor_left = 0.0
	frame.anchor_top = 1.0
	frame.anchor_right = 0.0
	frame.anchor_bottom = 1.0
	frame.offset_left = 12.0
	frame.offset_top = -190.0
	frame.offset_right = 452.0
	frame.offset_bottom = -84.0
	# NEVER EATS A CLICK. This sits over the play area, and a panel that
	# swallowed input would make the world under it dead to the mouse.
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.058, 0.070, 0.094, 0.86)
	style.border_width_left = 3
	style.border_color = Color(0.25, 0.33, 0.43)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = 10.0
	style.content_margin_top = 8.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 8.0
	frame.add_theme_stylebox_override("panel", style)

	var rows := VBoxContainer.new()
	rows.name = "rows"
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 3)
	frame.add_child(rows)

	add_child(frame)
	message_box = frame
	message_rows = rows


# =============================================================================
# THE WORLD STATUS STRIP
# =============================================================================
# THE MESSAGE BOX BELOW AND THIS ARE NOT THE SAME THING, and keeping them apart
# is the whole design. app.py says it about deaths and it is just as true here:
# "A death is a TRANSITION, NOT A STATE, and counting it as a state is the bug
# worth not writing."
#
#   The message box holds EVENTS. They happened, they are history, chat keeps
#   them. "Tunacan has gone hostile." "You found a gold pile."
#
#   This strip holds STATES. They are true right now and they stop being true
#   later. "Connection lost." "Server closes in 47s." "PvP is on."
#
# Mixing them is what the box was doing: four hostile announcements sitting
# there for ever with no timestamps, so a connection warning arriving beside
# them would have looked exactly like two-minute-old news. A state must never
# scroll away and must vanish the moment it stops being true.
#
# ONE LINE, BY PRIORITY, because two stacked warnings is how neither gets read.
# Connection beats everything - if the server cannot be reached, nothing else on
# this list can be trusted to still be true.
# "trade" SITS ABOVE "pvp" ON PURPOSE. PvP is a state of the world that lasts
# hours; a trade request is somebody waiting for you right now, and it goes
# away the moment you answer it. The one you can act on wins the strip.
const STATUS_PRIORITY := ["connection", "maintenance", "trade", "pvp"]

# HOW LONG WITHOUT THE SERVER BEFORE THE PLAYER IS TOLD.
#
# The broadcast poll runs every BROADCAST_POLL_SECONDS (10) and the heartbeat
# every HEARTBEAT_SECONDS (15), so a single missed request is ordinary and
# announcing it would make the strip flicker on every hiccup. Two missed polls
# is not ordinary.
const OFFLINE_GRACE_SECONDS := 25.0

# AND HOW LONG BEFORE GIVING UP. Past this the client stops pretending: the
# player goes back to the login screen with the reason, because everything done
# since the last successful save is not coming back and letting somebody keep
# playing into that is worse than interrupting them.
#
# Ninety seconds is deliberately generous - a laptop lid, a lift, a router
# reboot all fit inside it, and the countdown is visible for the last sixty-five
# of them so nobody is surprised.
const OFFLINE_SIGNOUT_SECONDS := 90.0

# AND HOW OFTEN TO ASK WHILE THE STRIP IS UP. At the usual ten seconds, a
# server back after a short restart was heard up to ten seconds late, so
# "Connection lost" stayed on screen after the server was answering again
# (measured on day 1: a 16-second restart showed the strip for 12 seconds
# after the server was back). Five, not less: every player who lost the
# server asks at this pace the moment it returns, and the poll is the route
# they all ask.
const OFFLINE_POLL_SECONDS := 5.0

var status_strip: PanelContainer = null
var status_label: Label = null

# WHEN THE SERVER WAS LAST HEARD FROM. Set on every verdict of "ok" - the
# broadcast poll and the heartbeat both produce one - and read by _process to
# decide whether this client is alone.
var _last_contact_msec: int = 0

# The live states, by key. Empty string means "not true right now".
var _status_states: Dictionary = {}


func _build_status_strip() -> void:
	# TOP CENTRE, which is empty on this HUD and is where a player's eye goes
	# for something wrong. The message box owns the bottom-left corner.
	var frame := PanelContainer.new()
	frame.name = "statusstrip"
	frame.anchor_left = 0.5
	frame.anchor_top = 0.0
	frame.anchor_right = 0.5
	frame.anchor_bottom = 0.0
	frame.offset_left = -260.0
	frame.offset_top = 10.0
	frame.offset_right = 260.0
	frame.offset_bottom = 44.0

	# NEVER EATS A CLICK, same as the message box: this sits over the play area.
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.06, 0.06, 0.92)
	style.border_width_bottom = 2
	style.border_color = Color(0.95, 0.45, 0.35)
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 14.0
	style.content_margin_top = 6.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 6.0
	frame.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.name = "line"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	frame.add_child(label)

	add_child(frame)
	status_strip = frame
	status_label = label


func set_world_status(key: String, text: String, colour: Color = Color(0.95, 0.45, 0.35)) -> void:
	"""Say that `key` is true, with this wording. An empty text clears it.

	KEYED, so each state can be set and cleared by whatever knows about it
	without any of them having to know about the others. The strip decides what
	is shown; the callers only report what is true.
	"""
	if text == "":
		_status_states.erase(key)
	else:
		_status_states[key] = {"text": text, "colour": colour}
	_paint_status_strip()


func _paint_status_strip() -> void:
	if status_strip == null or status_label == null:
		return

	for key in STATUS_PRIORITY:
		if _status_states.has(key):
			var state: Dictionary = _status_states[key]
			status_label.text = str(state["text"])
			status_label.add_theme_color_override("font_color", state["colour"])
			status_strip.visible = true
			return

	# NOTHING IS TRUE, so there is nothing to say. A strip that lingers on its
	# last message is a strip that lies.
	status_strip.visible = false


func _note_server_contact() -> void:
	# CALLED ON EVERY "ok", from both polls. Recovery has to be as automatic as
	# the warning was, or a player who reconnects sits looking at a stale alarm.
	_last_contact_msec = Time.get_ticks_msec()
	_set_poll_pace(BROADCAST_POLL_SECONDS)
	if _status_states.has("connection"):
		set_world_status("connection", "")
		_push_message("Reconnected.", Color(0.55, 0.85, 0.5))


func _set_poll_pace(seconds: float) -> void:
	"""How often the broadcast poll asks. Faster while the server is lost, so its
	return is heard soon; the usual pace again on the first answer."""
	var timer: Timer = get_node_or_null("BroadcastPoll") as Timer
	if timer == null or is_equal_approx(timer.wait_time, seconds):
		return
	timer.wait_time = seconds
	# A SHORTER PACE STARTS NOW, not when the old ten seconds run out.
	if timer.is_inside_tree() and timer.time_left > seconds:
		timer.start(seconds)


func _tick_connection_status() -> void:
	# NOT A TIMER. This has to count down every frame to read as a countdown,
	# and _process is already running for the bars.
	if not Api.is_logged_in():
		# On the login screen or between characters: there is nothing to warn
		# about, and _last_contact_msec from a previous session would fire
		# immediately on the next login.
		if _status_states.has("connection"):
			set_world_status("connection", "")
		return

	if _last_contact_msec == 0:
		# FIRST FRAME OF A SESSION. Nothing has answered yet and that is not the
		# same as having gone quiet - start the clock rather than the alarm.
		_last_contact_msec = Time.get_ticks_msec()
		return

	var silent: float = float(Time.get_ticks_msec() - _last_contact_msec) / 1000.0
	if silent < OFFLINE_GRACE_SECONDS:
		return

	var left: int = int(ceil(OFFLINE_SIGNOUT_SECONDS - silent))
	if left <= 0:
		# GIVING UP. The reason travels to the login screen, because "it just
		# went back to the menu" is the version of this that gets reported as a
		# crash.
		set_world_status("connection", "")
		CharacterData.clear_current_user()
		Api.forget_session("Lost connection to the server. Anything since your"
			+ " last save is not saved.")
		if is_instance_valid(self) and is_inside_tree():
			get_tree().change_scene_to_file(LOGIN_MENU_PATH)
		return

	_set_poll_pace(OFFLINE_POLL_SECONDS)
	set_world_status("connection",
		"Connection lost - retrying. Signing out in %s" % _clock(left),
		Color(1.0, 0.45, 0.35))


static func _clock(seconds: int) -> String:
	# m:ss, because "89 seconds" is a number to work out and "1:29" is a time.
	var whole: int = maxi(0, seconds)
	# The truncation IS the minute hand, and the remainder below is the second
	# hand - so nothing is being lost. Annotated in the same style chatpanel.gd
	# uses for its atlas row, because an unexplained integer division reads like
	# somebody forgot a .0, and four of these were filling his editor log.
	@warning_ignore("integer_division")
	var minutes: int = whole / 60
	return "%d:%02d" % [minutes, whole % 60]


func _warn_unprotected_staff() -> void:
	# This staff login needed no code: the account has no confirmed recovery
	# address, or the server cannot send mail (STAFF LOGIN CODES in app.py).
	# Once per login, not once per area.
	if Api.take_staff_unprotected_notice():
		_push_message("Your staff login needed no code from your email. Confirm a recovery "
			+ "email in Options, or, if you have one, the server's mail is off.",
			Color(1.0, 0.82, 0.42))


func _push_message(text: String, color: Color, at: int = 0, announce: bool = true) -> void:
	# `announce` false writes the record and pops nothing - for the backlog a
	# first poll catches up on. See _on_broadcast_poll_timeout().
	if text.strip_edges() == "":
		return

	# THE LOG ALWAYS GETS IT. THE BOX ONLY POPS WHEN NOBODY IS LOOKING.
	#
	# This used to be either/or: into the chat log if chat happened to be OPEN
	# at that instant, otherwise into the floating box - which fades. So a
	# player with chat closed got a few seconds of "Tunacan has gone hostile."
	# and then nothing, and opening chat afterwards showed no trace of it. The
	# notice reached exactly the people who did not need telling twice and
	# nobody else.
	#
	# The old comment here said printing to both would double every warning,
	# and that was true of the BOX, not of the log. They are different things:
	# the box is an announcement, which is an event and should fade; the log is
	# a record, which should not. So the record is written either way and the
	# announcement is skipped when the record is already on screen - which is
	# also the only case where it would genuinely have been a duplicate.
	#
	# AND "ALWAYS" NOW MEANS ALWAYS. The chat panel is built the first time it
	# is opened, so for a player who has not opened it there was no log at all
	# - the notice went to the box, the box faded, and it was gone. It waits in
	# _unlogged_lines until chat exists instead.
	var logged: bool = false
	if chat_panel != null and chat_panel.has_method("push_system_line"):
		chat_panel.push_system_line(text, color, at)
		logged = true
	else:
		_unlogged_lines.append({"text": text, "color": color,
			"at": at if at > 0 else int(Time.get_unix_time_from_system())})
		while _unlogged_lines.size() > UNLOGGED_KEPT:
			_unlogged_lines.pop_front()
	if logged and chat_panel.visible:
		return
	if not announce:
		return
	_pop_message(text, color)


func _pop_message(text: String, color: Color) -> void:
	"""The fading box alone, with no record in the chat log. For a whisper:
	its record is the conversation itself, on the Whisper tab."""
	if message_rows == null:
		return

	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 13)
	# Stamped on this machine's clock, not the server's `at`: what fades a line
	# is how long it has been ON SCREEN, which only this client knows.
	label.set_meta("shown_msec", Time.get_ticks_msec())
	message_rows.add_child(label)

	# Oldest off the top, so the box never grows past its corner.
	while message_rows.get_child_count() > MESSAGES_KEPT:
		var oldest := message_rows.get_child(0)
		message_rows.remove_child(oldest)
		oldest.queue_free()

	if message_box != null:
		message_box.visible = true


func _age_messages(now_msec: int) -> void:
	"""Fade and drop announcements by how long each has been on screen, and
	hide the box once it is empty.

	THE BOX WAS NEVER TOLD TO FADE. Every comment about it said it did - "the
	floating box, which fades", "the box is an announcement ... and should
	fade" - and nothing anywhere faded it. Lines left only by being pushed off
	the top by newer ones, so the last five notices of the week sat above the
	menu bar for as long as the game was open. A comment describing a wire
	nobody ran, again.

	TAKES THE CLOCK AS AN ARGUMENT so the suite can age a line by ten seconds
	without waiting ten seconds."""
	if message_rows == null or message_box == null:
		return
	var show_ms: float = MESSAGE_SHOW_SECONDS * 1000.0
	var fade_ms: float = MESSAGE_FADE_SECONDS * 1000.0
	for line in message_rows.get_children():
		var age: float = float(now_msec - int(line.get_meta("shown_msec", now_msec)))
		if age >= show_ms + fade_ms:
			message_rows.remove_child(line)
			line.queue_free()
		elif age > show_ms:
			line.modulate.a = 1.0 - (age - show_ms) / fade_ms
		else:
			line.modulate.a = 1.0
	# EMPTY IS HIDDEN, and so is anything while chat is up - the two share a
	# corner, and chat already shows the same lines.
	var chat_up: bool = chat_panel != null and chat_panel.visible
	message_box.visible = message_rows.get_child_count() > 0 and not chat_up


func _flush_unlogged_lines() -> void:
	"""Write every notice that arrived before chat existed into chat, in order,
	each with the time it happened rather than the time it was flushed."""
	if chat_panel == null or not chat_panel.has_method("push_system_line"):
		return
	for line in _unlogged_lines:
		chat_panel.push_system_line(str(line["text"]), line["color"], int(line["at"]))
	_unlogged_lines.clear()


# Guards against a storm. Several panels can each hold a request that 401s at the
# same moment - chat, friends and the guild list all poll - and every one of them
# makes api.gd emit. One probe answers all of them.
var _revocation_probe_in_flight: bool = false


func _on_unauthorized_seen() -> void:
	"""A 401 arrived somewhere. Ask the one question that decides, now.

	WHY THIS IS NOT "SHOW A NOT-AUTHORIZED OVERLAY". api.gd's comment on the
	signal is emphatic and it is right: a 401 is not proof the session is gone.
	Changing a password answers 401 for a mistyped CURRENT password, so a client
	that treats every 401 as revocation signs people out for typos. The 401 means
	"ask now rather than in up to ten seconds". heartbeat() is what decides, and
	_forced_signout() is the only thing that acts.

	WHAT THIS BUYS. Revocation on the server is instant - /api/staff/ban deletes
	the session rows in the same transaction that sets the ban. The client used
	to find out on the broadcast poll, so a banned player kept going for up to
	BROADCAST_POLL_SECONDS. The signal existed for this and nothing was listening;
	api.gd's comment described a wire that was never run.

	NO LOOP. heartbeat() asks /api/auth/session, and _request() deliberately
	excludes that path from emitting unauthorized_seen - otherwise this probe's
	own 401 would call it straight back.
	"""
	if _revocation_probe_in_flight or not Api.is_logged_in():
		return
	_revocation_probe_in_flight = true

	var verdict: String = await Api.heartbeat()

	# PAST AN AWAIT. Up to PROBE_TIMEOUT has passed and this node may be gone -
	# the same guard, for the same reason, as _on_broadcast_poll_timeout().
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_revocation_probe_in_flight = false

	# THE PROBE IS ALSO CONTACT. It asked /api/auth/session and got an answer, so
	# whatever it decided about the login, the server is plainly there - and not
	# saying so here would let the offline countdown run while a request was
	# succeeding every few seconds.
	if verdict == "ok":
		_note_server_contact()

	# Only "revoked" acts. "offline" and "stale" say nothing about the login, and
	# throwing somebody to the login screen over a hiccup is the failure the
	# whole verdict function exists to prevent.
	if verdict == "revoked":
		_forced_signout()


func _start_broadcast_poll() -> void:
	# THE 401 SHORTCUT IS WIRED HERE, beside the poll it shortcuts, because the
	# two are the same job at two speeds: the timer is the floor, and the signal
	# is what makes a ban land before the next tick.
	if not Api.unauthorized_seen.is_connected(_on_unauthorized_seen):
		Api.unauthorized_seen.connect(_on_unauthorized_seen)

	# A TRADE RESULT, HOWEVER IT ARRIVED. The broadcast poll below is one of
	# three routes that can deliver one; all three hand it to CharacterData, and
	# CharacterData tells us here - so it is announced once, in one wording.
	if not CharacterData.carry_adopted.is_connected(_on_carry_adopted):
		CharacterData.carry_adopted.connect(_on_carry_adopted)

	if has_node("BroadcastPoll"):
		return
	var timer := Timer.new()
	timer.name = "BroadcastPoll"
	timer.wait_time = BROADCAST_POLL_SECONDS
	timer.one_shot = false
	timer.autostart = true
	timer.timeout.connect(_on_broadcast_poll_timeout)
	add_child(timer)

	# ONE POLL NOW, NOT TEN SECONDS FROM NOW. The poll is also how the server
	# learns which character this is (see _broadcast_path()), and until it
	# hears, a trade opened by typing your name goes to whichever character you
	# saved last. It is also what paints the guild tag and the pvp strip, which
	# had been arriving a full poll after you walked in. Deferred so the HUD
	# has finished building before the answer lands on it.
	_on_broadcast_poll_timeout.call_deferred()


func _on_broadcast_poll_timeout() -> void:
	# Nothing to ask on behalf of nobody, and never two at once - a slow or
	# dead server must not stack requests behind each other.
	if _broadcast_poll_in_flight or not Api.is_logged_in():
		return
	_broadcast_poll_in_flight = true

	var res: Dictionary = await Api.get_json(_broadcast_path(), Api.PROBE_TIMEOUT)

	# PAST AN AWAIT. Up to the timeout has passed and this node may be gone -
	# the player died, or something else changed scenes. Same guard and same
	# reason as _on_logout_pressed().
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_broadcast_poll_in_flight = false

	# ONE PLACE DECIDES WHAT A RESPONSE MEANS. heartbeat_verdict() is in api.gd
	# and the test suite pins it: only a 401 signs anyone out. A 500, a 404 from
	# some other program on the port, or no answer at all says nothing about
	# whether this login is still good, and throwing the player to the login
	# screen over a hiccup would turn every restart of app.py into a mass kick.
	var verdict: String = Api.heartbeat_verdict(res)
	if verdict == "revoked":
		_forced_signout(res)
		return
	if verdict != "ok":
		# "offline" WAS ALREADY THE ANSWER AND NOTHING ACTED ON IT.
		# heartbeat_verdict() has returned three values all along - ok, revoked,
		# offline - and this line threw the third away. So a client that could
		# not reach the server went on playing with nothing on screen to say so,
		# and whatever happened after the last successful save was lost quietly.
		# _tick_connection_status() is what acts on it now; this just stops
		# pretending the silence was contact.
		return

	_note_server_contact()

	var data = res.get("data", {})
	if not (data is Dictionary):
		return
	_apply_broadcast(data)


func _apply_broadcast(data: Dictionary) -> void:
	"""One answer from the broadcast poll, onto the HUD.

	SPLIT FROM THE REQUEST so the suite can hand it an answer and look. Every
	reader below is fed from here and nowhere else - so a reader that is written
	and tested but never called from the poll (this project's most repeated
	bug) shows up as a failing check on THIS function, not as a feature that
	silently never runs."""
	_read_maintenance(data.get("maintenance"))
	_read_teleport(data.get("teleport"))

	_read_pvp(data)
	_read_guild(data)
	_read_trade(data.get("trade"))
	_read_trade_resync(data.get("trade_resync"))
	_read_chat_news(data.get("chat_news"))
	_read_asks(data.get("asks"))
	if data.has("open_report_players"):
		_mark_open_reports(int(data.get("open_report_players", 0)), int(data.get("open_reports", 0)))
	else:
		_mark_open_reports(int(data.get("open_reports", 0)))
	# THE FIRST ANSWER IS HISTORY, NOT NEWS. A poll from cursor 0 is answered
	# with the recent TAIL - up to a week of notices at once - and every one of
	# them used to pop the box on login: "Update in progress", "The server is
	# open again", "Everyone has been moved to elusion", all long over. They
	# still go to the chat log, where history belongs. Only what arrives after
	# this client has caught up is announced. Anything that is still TRUE -
	# maintenance, pvp - is on the status strip, which is where a player who
	# just arrived needs it.
	_read_broadcast_messages(data.get("messages", []), _broadcast_cursor > 0)

	var newest: int = int(data.get("latest_id", _broadcast_cursor))
	if newest > _broadcast_cursor:
		_broadcast_cursor = newest


func _broadcast_path() -> String:
	"""The poll's URL: where the cursor is, and WHICH CHARACTER THIS IS.

	The slot is how the server knows who you are playing (stamp_presence in
	app.py). It used to guess from whichever save was written last, and a save
	is only written when something changes - so for the first minute after
	picking a character the server thought you were still the one you played
	yesterday, and a trade opened by typing your name went to her."""
	return "/api/server/broadcasts?since=%d&slot=%d" % [
		_broadcast_cursor, CharacterData.active_character_index]


func _read_trade(summary: Variant) -> void:
	"""Somebody opened a trade with you: say so, and keep saying so until it is
	answered.

	BEFORE THIS NOTHING DID. The trade window polls the trade, but only while it
	is open - and the person being asked had no reason to open it. So a trade
	sat there unseen until it expired, and the one who opened it assumed they
	were being ignored.

	THE STRIP IS THE STATE, THE TOAST IS THE EVENT - the same split as the
	maintenance notice. The toast is said once per trade; the strip and the
	Trade button stay lit for as long as the trade is waiting on you."""
	var window_open: bool = trade_panel != null and trade_panel.visible
	if not (summary is Dictionary):
		_trade_announced = ""
		set_world_status("trade", "")
		_mark_trade_button(false)
		return

	var who: String = str(summary.get("with", "?"))
	var they_asked: bool = bool(summary.get("from_them", false))
	var they_accepted: bool = bool(summary.get("they_accepted", false))
	var you_accepted: bool = bool(summary.get("you_accepted", false))

	# WAITING ON YOU is the only case worth a light: they asked and you have not
	# answered, or they have accepted and you have not. A trade you opened and
	# are waiting on them for is not news to you.
	var waiting_on_you: bool = (they_asked or they_accepted) and not you_accepted
	if not waiting_on_you or window_open:
		set_world_status("trade", "")
		_mark_trade_button(false)
	else:
		set_world_status("trade",
			"%s accepted your trade - waiting on you" % who if they_accepted
				else "%s wants to trade with you" % who,
			Color(0.62, 0.86, 1.0))
		_mark_trade_button(true, who)

	var trade_id: String = str(summary.get("trade_id", ""))
	if they_asked and trade_id != "" and trade_id != _trade_announced and not window_open:
		_trade_announced = trade_id
		_push_message("%s wants to trade with you. Open Trade to see the offer." % who,
			Color(0.62, 0.86, 1.0))


func _mark_trade_button(lit: bool, who: String = "") -> void:
	var button: Button = _nav_button("tradebutton")
	if button == null:
		return
	# A DOT, NOT A NUMBER. There is only ever one trade, so a count would always
	# say 1; the dot says "something is waiting here", which is the whole message.
	button.text = "Trade •" if lit else "Trade"
	button.tooltip_text = "%s is waiting on you" % who if lit else ""
	if lit:
		button.add_theme_color_override("font_color", Color(0.62, 0.86, 1.0))
	else:
		button.remove_theme_color_override("font_color")
	_paint_group_dots()


# =============================================================================
# WHAT WAS SAID TO YOU IN CHAT
# =============================================================================
# The chat window reads only the tab that is open, and only while it is open.
# So a whisper reached nobody - chat closed, or open on World - and the Whisper
# tab shows only a conversation with a name you already typed. The broadcast
# poll now carries the newest whisper to this player, and the newest line in
# their guild and among their friends (chat_news, _chat_news() in app.py).

const WHISPER_COLOUR := Color(0.93, 0.62, 0.95)

# A whisper already on the server when this client arrives is said only if it
# is this recent: enough to catch somebody who spoke a moment before you logged
# in, not so much that yesterday's greets you at every login.
const WHISPER_CATCH_UP_SECONDS := 600

# PER LOGIN, NOT PER HUD. Every area has its own HUD, so anything kept on one
# was forgotten at the next door: a whisper from two minutes ago was said again
# in every area walked into, and a lit Chat button went dark. Static, and
# forgotten when a different account is playing.
#
# The newest id seen of each, -1 until the first poll has set where "new" starts.
static var _chat_seen: Dictionary = {"whisper": -1, "guild": -1, "friends": -1}
static var _chat_seen_by: String = ""
static var _last_whisper_from: String = ""
# A whisper not yet looked at: the chat window opens on it, in any area.
static var _whisper_waiting: bool = false
static var _chat_dot: bool = false


static func _forget_chat_news() -> void:
	_chat_seen = {"whisper": -1, "guild": -1, "friends": -1}
	_chat_seen_by = ""
	_last_whisper_from = ""
	_whisper_waiting = false
	_chat_dot = false


func _read_chat_news(news: Variant) -> void:
	if not (news is Dictionary):
		return
	if _chat_seen_by != Api.username:
		_forget_chat_news()
		_chat_seen_by = Api.username
	var first: bool = int(_chat_seen["whisper"]) < 0
	var whisper: Variant = news.get("whisper")
	var whisper_id: int = int(whisper.get("id", 0)) if whisper is Dictionary else 0
	if whisper_id > int(_chat_seen["whisper"]):
		var at: int = int(whisper.get("at", 0)) if whisper is Dictionary else 0
		var recent: bool = int(Time.get_unix_time_from_system()) - at <= WHISPER_CATCH_UP_SECONDS
		if whisper_id > 0 and (not first or recent):
			_whisper_from(str(whisper.get("from", "?")), str(whisper.get("body", "")))
		_chat_seen["whisper"] = whisper_id
	for room in ["guild", "friends"]:
		var newest: int = int(news.get(room, 0))
		if newest > int(_chat_seen[room]):
			if not first:
				_room_news(room)
			_chat_seen[room] = newest


func _whisper_from(who: String, body: String) -> void:
	_last_whisper_from = who
	var chat_open: bool = chat_panel != null and chat_panel.visible
	if chat_panel != null:
		chat_panel.whisper_arrived(who)
	if not chat_open:
		_whisper_waiting = true
		_pop_message("%s whispers: %s" % [who, ChatPanelScript.shown_text(body,
			bool(Settings.get_value("chat_filter")))], WHISPER_COLOUR)
		_mark_chat_button(true)


func _room_news(room: String) -> void:
	if chat_panel != null:
		chat_panel.room_news(room)
	if chat_panel == null or not chat_panel.visible:
		_mark_chat_button(true)


func _mark_chat_button(lit: bool) -> void:
	_chat_dot = lit
	var button: Button = _nav_button("chatbutton")
	if button == null:
		return
	# A DOT, like Trade: something was said to you and the window is shut.
	button.text = "Chat •" if lit else "Chat"
	button.tooltip_text = "Something was said to you" if lit else ""
	if lit:
		button.add_theme_color_override("font_color", WHISPER_COLOUR)
	else:
		button.remove_theme_color_override("font_color")


# =============================================================================
# WHAT IS WAITING ON YOUR ANSWER
# =============================================================================
# A friend request or a guild invitation is answered from its own panel, and
# on day 1 nothing told the player to open it: a request to somebody standing
# next to you sat there until they happened to look. The broadcast poll
# carries `asks` now (_waiting_asks() in app.py): how many of each are
# waiting, and the newest one's name and time.
#
# THE BUTTON IS THE STATE, THE TOAST IS THE EVENT, as with Trade. "Friends •"
# and "Guild •" stay lit while anything is waiting; the newest is said once.
#
# PER LOGIN, NOT PER HUD, for the reason _chat_seen is: every area has its own
# HUD, and a toast remembered on one would be said again at every door.

const ASK_COLOUR := Color(1.0, 0.82, 0.42)

# The newest request's time already said, of each kind.
static var _asks_said: Dictionary = {"friends": 0, "guild": 0}
static var _asks_said_by: String = ""
# The last answer, so a new area's HUD can light its buttons before its first poll.
static var _asks_last: Dictionary = {}


static func _forget_asks() -> void:
	_asks_said = {"friends": 0, "guild": 0}
	_asks_said_by = ""
	_asks_last = {}


static func ask_text(kind: String, newest: String, count: int) -> String:
	"""What the toast says about the newest request of a kind."""
	var more: String = " and %d more" % (count - 1) if count > 1 else ""
	if kind == "guild":
		return "%s%s invited you to join. Open Guild to answer." % [newest, more]
	return "%s%s asked to be your friend. Open Friends to answer." % [newest, more]


func _read_asks(asks: Variant) -> void:
	if not (asks is Dictionary):
		return
	if _asks_said_by != Api.username:
		_forget_asks()
		_asks_said_by = Api.username
	_asks_last = asks.duplicate(true)
	_paint_ask_buttons()
	for kind in ["friends", "guild"]:
		var one: Variant = asks.get(kind)
		if not (one is Dictionary):
			continue
		var count: int = int(one.get("count", 0))
		var at: int = int(one.get("at", 0))
		# A REQUEST THAT WAS WAITING BEFORE THIS LOGIN IS SAID TOO. Unlike an
		# old whisper, it is still waiting on an answer.
		if count > 0 and at > int(_asks_said.get(kind, 0)):
			_asks_said[kind] = at
			_push_message(ask_text(kind, str(one.get("newest", "")), count), ASK_COLOUR)


func _paint_ask_buttons() -> void:
	for kind in ["friends", "guild"]:
		var button: Button = _nav_button("%sbutton" % kind)
		if button == null:
			continue
		var one: Variant = _asks_last.get(kind)
		var count: int = int(one.get("count", 0)) if one is Dictionary else 0
		# The button's own words and hint, kept from the scene the first time,
		# so a dot that goes out puts back exactly what was there.
		if not button.has_meta("ask_base"):
			button.set_meta("ask_base", [button.text, button.tooltip_text])
		var base: Array = button.get_meta("ask_base")
		if count > 0:
			button.text = "%s •" % base[0]
			button.tooltip_text = "%s is waiting on your answer" % str(one.get("newest", "")) if count == 1 \
				else "%d are waiting on your answer" % count
			button.add_theme_color_override("font_color", ASK_COLOUR)
		else:
			button.text = base[0]
			button.tooltip_text = base[1]
			button.remove_theme_color_override("font_color")
	_paint_group_dots()


func _read_trade_resync(resync: Variant) -> void:
	"""A trade finished without this client asking - hand the result over.

	The broadcast poll is the route for a player whose trade window is shut:
	they accepted, closed the window, and the other side accepted a minute
	later. CharacterData does the adopting and announces it; see
	_on_carry_adopted()."""
	if resync is Dictionary:
		CharacterData.apply_server_carry(resync)


func _on_carry_adopted(resync: Dictionary) -> void:
	# A SAVE BUILT ON AN OLD BAG is said nothing about. The bag the server sent
	# back is the one this screen was already showing, nearly always - the cook
	# or the pickup that moved it on had been shown when it happened - so a
	# message would announce a change nobody saw.
	if str(resync.get("reason", "")) == "stale_save":
		return
	var record = resync.get("trade")
	if record is Dictionary:
		_push_message(TradePanelScript.result_line(record), Color(0.55, 0.85, 0.5))
	else:
		_push_message("Your backpack was updated by the server.", Color(0.55, 0.85, 0.5))


func _read_pvp(data: Dictionary) -> void:
	"""PVP IS A STATE, and the quietest of the three - which is exactly why it
	belongs on a strip rather than in a message that scrolls. A player who logs
	in after the announcement has gone out has no other way to know.

	AND SINCE WHEN. "PvP is ON" answers a different question from the one
	somebody who just arrived is asking, and the server already knew the
	answer: server_settings has stamped updated_at on every key since the table
	was created, so pvp_since() on that side is a read, not a new column.

	NAMED RATHER THAN INLINE, like _read_maintenance() and _read_teleport()
	beside it, because a thing that cannot be called cannot be tested."""
	if not bool(data.get("pvp", false)):
		set_world_status("pvp", "")
		return
	var thrown: int = int(data.get("pvp_at", 0))
	set_world_status("pvp",
		"PvP is ON" if thrown <= 0 else "PvP is ON since %s" % LocalTime.stamp(thrown),
		Color(1.0, 0.55, 0.42))


func _read_guild(data: Dictionary) -> void:
	"""Your own guild, from the poll, onto your own nameplate.

	A NAMEPLATE HAS TO BE TRUE RIGHT NOW. GET /api/guild is the only other
	route that says which guild you are in and nothing calls it on a timer, so
	a tag fed from the guild panel would appear whenever that panel happened to
	be opened and then go on being whatever it was - including after you were
	kicked out. That is the shape of defect this project has spent the most
	time removing: a display fed by something nobody schedules.

	SO IT RIDES THE POLL THAT ALREADY RUNS, beside pvp and maintenance and for
	the same reason they are there. Being removed from a guild, or a mod
	renaming or disbanding it, reaches the plate within one poll.

	WRITTEN EVERY POLL RATHER THAN ON CHANGE. set_nameplate() is three property
	writes and a reposition; comparing first would buy nothing and would need a
	cached copy that could fall out of step with the plate it describes."""
	# OUT OF THE TREE THERE IS NO PLAYER TO LABEL - and get_tree() is null, so
	# asking it would stop every reader after this one.
	if not is_inside_tree():
		return
	var body: Node = get_tree().get_first_node_in_group("player")
	if body == null or not body.has_method("set_nameplate"):
		return
	body.set_nameplate(Api.username, Api.role, str(data.get("guild_tag", "")))


func _read_broadcast_messages(messages: Variant, announce: bool = true) -> void:
	"""Everything the server has said since the last poll, onto the screen.

	entry["at"] IS THE SERVER'S OWN STAMP AND IT WAS BEING DROPPED HERE.

	read_broadcasts() has always returned it. This loop read `body` and `kind`
	and threw the rest away, so every notice was stamped - once system lines
	were stamped at all - with the moment THIS client read it. For a player who
	was already online that is the same number. For everybody else it is wrong
	by however long ago they logged in, and a first poll asks since=0, which
	returns the TAIL: up to a week of notices, all arriving in one second.

	That is the shape of bug this project keeps finding: the server half right
	and tested, the client half never wired to it. Which is also why this is a
	function with a name - the previous version of this code was six lines
	inside a poll handler, and the only way to test it was to read it."""
	if not (messages is Array):
		return
	for entry in messages:
		if not (entry is Dictionary):
			continue
		var kind: String = str(entry.get("kind", "system"))
		var body: String = str(entry.get("body", ""))
		var colour: Color = Color(1.0, 0.82, 0.42) if kind == "system" else Color(0.85, 0.89, 0.94)
		var bannered: bool = false
		if kind == MYTHIC_BROADCAST_KIND:
			colour = GameConstants.rarity_colour(GameConstants.MYTHIC_TIER)
			# EVERYONE ELSE GETS THE BANNER. The finder's own game already
			# celebrated when the kill answer landed (Combat.celebrate_mythic),
			# so a find signed with their own name is only written into chat.
			# The backlog a first poll catches up on is not announced either:
			# an hour-old find is news for the log, not the screen.
			bannered = announce and str(entry.get("by", "")) != Api.username
			if bannered:
				show_mythic_banner("MYTHIC FOUND", body, false)
		_push_message(body, colour, int(entry.get("at", 0)), announce and not bannered)


# =============================================================================
# THE MYTHIC BANNER
# =============================================================================
# The rarest thing that can happen in the game, across the top of the screen in
# the mythic red. It is shown two ways:
# - To the finder, from Combat.celebrate_mythic(), as "MYTHIC DROP!" and the
#   piece's name, with a red flash over the whole screen.
# - To everyone else online, from a broadcast of kind "mythic", as the
#   server's sentence: "Tunacan found the Meteorite on The Crowned!".
# One at a time. A second find replaces the first rather than stacking.
const MYTHIC_BROADCAST_KIND := "mythic"
const MYTHIC_BANNER_SECONDS := 5.0
var mythic_banner: Control = null


func show_mythic_banner(title: String, subtitle: String, flash: bool = false) -> void:
	if mythic_banner != null and is_instance_valid(mythic_banner):
		mythic_banner.queue_free()
	var red: Color = GameConstants.rarity_colour(GameConstants.MYTHIC_TIER)

	var root := Control.new()
	root.name = "mythicbanner"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	mythic_banner = root

	if flash:
		var veil := ColorRect.new()
		veil.name = "flash"
		veil.color = Color(red, 0.38)
		veil.set_anchors_preset(Control.PRESET_FULL_RECT)
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(veil)
		if veil.is_inside_tree():
			veil.create_tween().tween_property(veil, "color:a", 0.0, 0.8) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Full width, a sixth of the way down, growing downward to fit: above the
	# action, below the bars.
	var rows := VBoxContainer.new()
	rows.name = "rows"
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.anchor_left = 0.0
	rows.anchor_right = 1.0
	rows.anchor_top = 0.16
	rows.anchor_bottom = 0.16
	rows.add_theme_constant_override("separation", 2)
	root.add_child(rows)
	rows.add_child(_mythic_banner_label("title", title, 30, red))
	rows.add_child(_mythic_banner_label("line", subtitle, 15, Color(1.0, 0.93, 0.88)))

	# In with a short drop, held, then out. A HUD built outside the tree (the
	# suite builds them that way) cannot make tweens, and gets the banner
	# standing still.
	if not rows.is_inside_tree():
		return
	rows.modulate.a = 0.0
	rows.position.y -= 16.0
	var motion := rows.create_tween()
	motion.tween_property(rows, "modulate:a", 1.0, 0.25)
	motion.parallel().tween_property(rows, "position:y", rows.position.y + 16.0, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	motion.tween_interval(MYTHIC_BANNER_SECONDS)
	motion.tween_property(rows, "modulate:a", 0.0, 1.0)
	motion.tween_callback(root.queue_free)


func _mythic_banner_label(label_name: String, text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.name = label_name
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color(0.12, 0.0, 0.02))
	label.add_theme_constant_override("outline_size", 6 if size >= 24 else 4)
	return label


func _read_teleport(order) -> void:
	# SENT BY STAFF, CARRIED OUT HERE. The server decided the destination AND
	# the exact spot - it spaces a group out on hex rings so nobody lands on
	# anybody - so this does not compute a position, it goes where it is told.
	if not (order is Dictionary):
		return

	var teleport_id: int = int(order.get("id", 0))
	if teleport_id == 0 or teleport_id == _teleport_done:
		return
	# Claimed before the trip, because go_to() may change scene and the next
	# poll can land before the ack does.
	_teleport_done = teleport_id

	var area: String = str(order.get("area", ""))
	var spot := Vector2(float(order.get("x", 0.0)), float(order.get("y", 0.0)))
	var by: String = str(order.get("by", "staff"))
	var of_many: int = int(order.get("of", 1))

	if AreaRegistry.has_area(area):
		# THE SERVER PICKED THIS SPOT WITH NO IDEA WHERE THE WALLS ARE.
		#
		# It spaces a group properly - teleport_offset() packs everyone into
		# hexagonal rings at TELEPORT_SPACING so nobody stacks, and it hands each
		# client its own final coordinates rather than the arithmetic. That part
		# is right and this code does not second-guess it.
		#
		# What it cannot do is look at the map. Move fifty people into the town
		# square and the outer ring is 192px out, which in a tight room is inside
		# the scenery. So the spot is checked here, where the collision shapes
		# are, and nudged to the nearest clear one on the same hex grid the
		# server used. start_ring 0: the server's own choice is tried first,
		# because it is usually right and it is what keeps a moved group looking
		# arranged.
		var body: CharacterBody2D = get_tree().get_first_node_in_group("player") as CharacterBody2D
		var landing: Vector2 = SafeSpot.find(body, spot, 0)
		if landing == Vector2.INF:
			# NOTHING CLEAR WITHIN THREE RINGS. Go anyway, to the spot we were
			# given: refusing a staff teleport would strand somebody who was
			# being moved OUT of a bad place, and this is the one case where the
			# server knows something the client does not.
			push_warning("Teleport %d: no clear spot near (%.0f, %.0f) in %s."
				% [teleport_id, spot.x, spot.y, area])
			landing = spot
		AreaRegistry.go_to(area, landing)
		if of_many > 1:
			_push_message("%s moved everyone to %s." % [by, area], Color(1.0, 0.82, 0.42))
		else:
			_push_message("%s moved you to %s." % [by, area], Color(1.0, 0.82, 0.42))
	else:
		# UNKNOWN AREA. Acked anyway rather than left queued: an order this
		# build cannot carry out would otherwise be retried on every login
		# forever. The warning names the id so it can be looked up.
		push_warning("Teleport %d names area '%s', which is not in AreaRegistry."
			% [teleport_id, area])
		_push_message("A teleport arrived for an area this build does not know: %s" % area,
			Color(0.95, 0.45, 0.35))

	# TOLD LAST. The server keeps the order until somebody says it was carried
	# out, so a crash between arriving and acking costs a repeat, not a loss.
	await Api.post("/api/teleport/ack", {"id": teleport_id})


func _read_maintenance(notice) -> void:
	if not (notice is Dictionary) or not bool(notice.get("on", false)):
		# Reopened. Arm the warning again so the NEXT closing is announced.
		_maintenance_warned = false
		# AND TAKE THE STATE DOWN. The one-off message below announced the
		# closing and nothing ever un-announced it, so a server that reopened
		# left its warning on screen until the player happened to scroll it off.
		set_world_status("maintenance", "")
		return

	var seconds: int = int(notice.get("seconds_left", 0))

	# THE STRIP IS A STATE AND IS RE-SET ON EVERY POLL, ABOVE THE ONCE-ONLY
	# GUARD. That placement is the whole fix and it is worth saying why, because
	# the previous version sat BELOW the guard with a comment claiming it was
	# re-set every poll. It was not: _maintenance_warned returned early from the
	# second poll onward, so set_world_status ran exactly once and the number
	# froze at whatever the first poll happened to read.
	#
	# The server sends a fresh seconds_left on every broadcast poll (10s) and
	# every heartbeat (15s) - maintenance_public() recomputes it per request -
	# so every one of those numbers was being thrown away. A player who read
	# "closes in 4:00" went on reading 4:00 until the room emptied underneath
	# them, which is precisely the failure the comment above it warned about.
	#
	# It is also how a closing that ALREADY HAPPENED becomes permanent. Log in
	# after the window is spent and the first poll reads seconds_left 0, paints
	# "Server closes in 0:00 - your progress is being saved", and never touches
	# it again. Reported as a server that "never actually shut down".
	set_world_status("maintenance", _maintenance_line(seconds),
		Color(1.0, 0.65, 0.25) if seconds > 0 else Color(0.95, 0.45, 0.35))

	# THE TOAST AND THE FLUSH ARE AN EVENT, and events happen once. A closing
	# server deserves the louder treatment, but it deserves it on the poll that
	# first sees it - not every ten seconds for four minutes.
	if _maintenance_warned:
		return
	_maintenance_warned = true

	_push_message(_maintenance_announcement(seconds), Color(0.95, 0.45, 0.35))

	# THE CLIENT'S HALF OF "SAVE EVERYONE BEFORE DISCONNECTING". The server
	# holds the door open for a grace window precisely so this can happen; a
	# debounced write that happened to be two seconds away is not good enough
	# when the room is about to empty.
	if CharacterData != null and CharacterData.has_method("flush_save"):
		CharacterData.flush_save()


static func _maintenance_line(seconds: int) -> String:
	"""What the status strip says about a closing or closed server.

	STATIC AND PURE so the suite can ask it directly for each of the three
	states rather than driving a poll. It reads Api.is_owner, which is a global
	rather than an argument - so the one input that cannot be passed in is the
	one the suite sets on Api itself.

	THREE STATES, NOT TWO, AND THE THIRD IS THE ONE THAT WAS MISSING.

	  counting down   the window is open, everyone is saving
	  spent, player   the window is over; the next request ends this session
	  spent, owner    the window is over; the owner is EXEMPT and still playing

	The owner line exists because maintenance_refusal() and
	maintenance_disconnect() both skip the owner by name - deliberately, so
	nobody can lock themselves out of their own server. The consequence is that
	throwing the switch does nothing visible from the owner's chair: the players
	are gone, the owner is not, and the only thing on screen is a banner.
	Saying "you are exempt" is what turns that from a switch that looks broken
	into a switch that reports what it did.

	AND "your progress is being saved" IS ONLY TRUE WHILE THE WINDOW IS OPEN.
	Past it the saving is over, and a line promising it is a line that lies to
	the one player who most needs to know the session is about to end."""
	if seconds > 0:
		return "Server closes in %s - your progress is being saved" % _clock(seconds)
	if Api != null and Api.is_owner:
		return "Server is CLOSED to players - you are exempt as owner"
	return "Server is closed - you will be signed out"


static func _maintenance_announcement(seconds: int) -> String:
	"""The one-off chat line. Same three states, past tense once the window is
	spent - a notice saying "closing in 0s" is a countdown nobody can act on,
	and it was appearing in the log of players who arrived long afterwards."""
	if seconds > 0:
		return "The server is closing in %ds. Saving your progress now." % seconds
	if Api != null and Api.is_owner:
		return "The server is closed to players. You are exempt as owner."
	return "The server is closed. You will be signed out."


func _forced_signout(refusal: Dictionary = {}) -> void:
	# The server has already destroyed this session - kicked, banned, the
	# grace window on a closing server ran out, or the account signed in
	# somewhere else. Api.logout() would spend a request on a token that no
	# longer exists, which is exactly what forget_session() exists for: keep the
	# reason for the login screen, drop the token, and go.
	#
	# THE REASON COMES FROM THE 401 ITSELF - the broadcast poll's, or the one
	# heartbeat() kept. See Api.signout_notice_for().
	var notice: String = ApiScript.signout_notice_for(refusal if not refusal.is_empty() else Api.last_refusal)
	Api.last_refusal = {}
	_push_message("Signed in somewhere else." if notice == Api.SIGNED_IN_ELSEWHERE_NOTICE
		else "Signed out by the server.", Color(0.95, 0.45, 0.35))

	# Flushes any pending debounced save on the way out.
	CharacterData.clear_current_user()
	Api.forget_session(notice)

	if not is_instance_valid(self) or not is_inside_tree():
		return
	get_tree().change_scene_to_file(LOGIN_MENU_PATH)


func _wire_hotbar() -> void:
	if hotbar == null:
		return
	if not hotbar.slot_used.is_connected(_on_hotbar_slot_used):
		hotbar.slot_used.connect(_on_hotbar_slot_used)


# =============================================================================
# INVENTORY EAGER INSTANTIATION
# =============================================================================

func _ensure_inventory_screen() -> void:
	if inventory_screen != null:
		return

	inventory_screen = INVENTORY_SCENE.instantiate()
	add_child(inventory_screen)
	inventory_screen.closed.connect(hide_inventory)

	inventory_screen.visible = false

	_load_player_inventory_into_container()
	_attach_inventory_to_hotbar()


func _load_player_inventory_into_container() -> void:
	if active_character == null or inventory_screen == null:
		return
	if not "inventory_data" in active_character:
		return

	var container: Node = inventory_screen.get_node_or_null("%inventorycontainer")
	if container == null:
		return
	if not container.has_method("load_save_array"):
		return

	var inventory_data: Array = active_character.inventory_data
	if typeof(inventory_data) == TYPE_ARRAY:
		container.load_save_array(inventory_data)


# =============================================================================
# ACTIVE CHARACTER
# =============================================================================

func set_active_character(character: Node) -> void:
	if character == null:
		push_error("set_active_character called with null!")
		return

	active_character = character
	_last_hp      = -1
	_last_mana    = -1
	_last_stamina = -1
	update_bars()

	_ensure_inventory_screen()

	if inventory_screen != null:
		inventory_screen.set_player(active_character)
	# Only if it already exists: the doll is built the first time the backpack
	# opens, and instantiating it here would put a panel on screen for a
	# character who has not asked to see it.
	if equipment_panel != null:
		equipment_panel.set_player(active_character)
	if map_screen != null and map_screen.has_method("set_player"):
		map_screen.set_player(active_character)
	if stats_screen != null:
		stats_screen.setup_for_player(active_character)

	_offer_welcome_soon()

	# NO hotbar.set_player() ANY MORE. The keys hold items, and those arrive
	# with the backpack: _load_player_inventory_into_container() fills cells
	# 20-29 along with the bag.


# =============================================================================
# BAR UPDATES
# =============================================================================

func update_bars() -> void:
	# Sets the RANGES and snaps every bar to the current value. Called when the
	# active character changes, where easing would be wrong — switching
	# characters should not show one character's bars sliding to another's.
	# Ongoing movement is _animate_bars()' job.
	if active_character == null:
		return

	# Through _displayable() like the animated path, or switching characters
	# would snap the bars to a raw value the eased path never shows - the same
	# number drawn two different ways depending on how you arrived at it.
	if healthbar:
		healthbar.max_value = maxf(active_character.get("max_hp"), 1.0)
		healthbar.value     = _displayable(healthbar, active_character.get("hp"))

	if magicbar:
		magicbar.max_value = maxf(active_character.get("max_mana"), 1.0)
		magicbar.value     = _displayable(magicbar, active_character.get("mana"))

	if staminabar:
		staminabar.max_value = maxf(active_character.get("max_stamina"), 1.0)
		staminabar.value     = _displayable(staminabar, active_character.get("stamina"))

	_write_readouts()


func _write_readouts() -> void:
	# STRAIGHT FROM THE CHARACTER, not from bar.value. bar.value has been put
	# through _displayable() and is deliberately a little generous at the
	# bottom; printing that would turn one honest approximation into two
	# numbers that lie in agreement.
	if active_character == null:
		return
	_write_readout(healthvalue,  active_character.get("hp"),      active_character.get("max_hp"))
	_write_readout(manavalue,    active_character.get("mana"),    active_character.get("max_mana"))
	_write_readout(staminavalue, active_character.get("stamina"), active_character.get("max_stamina"))


func _write_readout(label: Label, amount: float, amount_max: float) -> void:
	if label == null:
		return
	# Rounded rather than truncated: at 0.6 HP left, "0 / 432" beside a bar
	# that still shows something is the same contradiction this whole change
	# exists to remove.
	label.text = "%d / %d" % [roundi(amount), roundi(maxf(amount_max, 1.0))]


func _animate_bars(delta: float) -> void:
	if active_character == null:
		return

	_ease_bar(healthbar,   active_character.get("hp"),      active_character.get("max_hp"),      delta)
	_ease_bar(magicbar,    active_character.get("mana"),    active_character.get("max_mana"),    delta)
	_ease_bar(staminabar,  active_character.get("stamina"), active_character.get("max_stamina"), delta)

	_write_readouts()


func _ease_bar(bar: TextureProgressBar, target: float, stat_max: float, delta: float) -> void:
	if bar == null:
		return

	# keep the range current — max_hp changes on every level-up
	bar.max_value = maxf(stat_max, 1.0)

	# Everything below works on what is DRAWN, not on the raw stat - see
	# _displayable(). Easing toward the raw value and only flooring at the end
	# would make the bar creep below its own floor and back.
	var shown: float = _displayable(bar, target)

	# DROPS SNAP. Damage has to read instantly: a health bar that glides down
	# after a hit tells you a moment late that you were hit, and in a fight
	# that moment is the whole point of having a health bar. Only refilling
	# eases, which is where the wobble lived anyway.
	if shown <= bar.value:
		bar.value = shown
		return

	if shown - bar.value <= BAR_SNAP_THRESHOLD:
		bar.value = shown
		return

	# Exponential ease, framerate independent. Using exp() rather than a plain
	# lerp(a, b, speed * delta) matters: the naive version moves a different
	# fraction of the gap at 60fps than at 144, so the bars would fill at
	# different speeds on different machines.
	bar.value = lerpf(bar.value, shown, 1.0 - exp(-BAR_FILL_SPEED * delta))


func _displayable(bar: TextureProgressBar, amount: float) -> float:
	"""What to DRAW for this amount: the amount itself, or the smallest sliver
	the bar can actually render, whichever is larger. Zero draws zero."""
	if bar == null or amount <= 0.0:
		return 0.0

	# Measured off the texture rather than hard-coded, so a bar with different
	# art gets the floor its own art deserves. Falling back to 100 makes the
	# floor 1% if a bar somehow has no progress texture, which is a harmless
	# answer for a bar that cannot be seen anyway.
	var texture: Texture2D = bar.texture_progress
	var width: float = float(texture.get_width()) if texture != null else 100.0
	var floor_value: float = bar.max_value * (BAR_MIN_VISIBLE_TEXTURE_PIXELS / maxf(width, 1.0))
	return maxf(amount, floor_value)


# =============================================================================
# NAV BUTTON HANDLERS
# =============================================================================

func _on_inventory_pressed() -> void:
	toggle_inventory()


func _on_equipment_pressed() -> void:
	toggle_equipment()


func _on_stats_pressed() -> void:
	toggle_stats()


func _on_shop_pressed() -> void:
	# WHAT THIS USED TO BE, in full:
	#
	#     print("shop pressed (not yet implemented)")
	#
	# The last of the three handlers tools/audit.py found under "handlers wired
	# to nothing". The shop itself was never missing — vendor.gd has called
	# open_shop() on this node since it was written, and walking up to a vendor
	# and pressing interact has always worked. Only the button was dead.
	#
	# THE SHOP IS A PLACE, NOT A SCREEN, which is why this cannot simply open a
	# panel the way Inventory and Stats do. There is no such thing as "the"
	# shop: each vendor carries its own ShopData, and which catalogue you get
	# depends on whose counter you are standing at.
	#
	# So the button does what the player means by pressing it — open the shop
	# I am standing in front of — and says so plainly when there isn't one.
	# Silence was the original bug; replacing a print with a different silence
	# would not be a fix.
	var nearby: Node = null
	for vendor in get_tree().get_nodes_in_group("vendors"):
		if vendor.has_method("can_open_for_player") and vendor.can_open_for_player():
			nearby = vendor
			break

	if nearby == null:
		_notify("There is no shop here.")
		return

	nearby.open_for_player()


func _notify(message: String) -> void:
	# Routed through the player because that is where show_notice() lives and
	# where the floating label is spawned — see player.gd's note on why those
	# refusals stopped being print() calls. The HUD has no label of its own and
	# should not grow one for this.
	if active_character != null and active_character.has_method("show_notice"):
		active_character.show_notice(message)
	elif OS.is_debug_build():
		print("[HUD]  %s" % message)


func _on_trade_pressed() -> void:
	await toggle_trade()


func _on_kingdom_pressed() -> void:
	await toggle_kingdom()


func _ensure_map_screen() -> void:
	if map_screen != null:
		return
	map_screen = MAPSCREEN_SCENE.instantiate()
	add_child(map_screen)
	if active_character != null and map_screen.has_method("set_player"):
		map_screen.set_player(active_character)
	map_screen.visible = false


func toggle_map() -> void:
	_ensure_map_screen()
	if map_screen == null:
		return
	if map_screen.visible:
		map_screen.close()
	else:
		if active_character != null and map_screen.has_method("set_player"):
			map_screen.set_player(active_character)
		map_screen.open()


func _on_map_pressed() -> void:
	# WHAT THIS USED TO BE, in full:
	#
	#     print("map pressed (not yet implemented)")
	#
	# tools/audit.py found it under "handlers wired to nothing", alongside the
	# shop button, which is still there.
	toggle_map()


func _ensure_options_screen() -> void:
	if options_screen != null:
		return
	options_screen = OPTIONS_SCENE.instantiate()
	add_child(options_screen)
	options_screen.visible = false

	# NOTHING IS CONNECTED TO `closed`, ON PURPOSE. There is nothing to tear
	# down: the panel writes through Settings, which has already applied and
	# saved by the time it closes.
	#
	# A handler was written here and it did nothing but `pass` — which
	# tools/audit.py flagged within the hour, under "handlers wired to
	# nothing", which is the check that exists because of the Options button
	# this panel replaced. A signal connected to an empty function is a
	# connection someone later has to read and decide about. The signal stays
	# declared for anything that does want it.


func toggle_options() -> void:
	_ensure_options_screen()
	if options_screen == null:
		return
	if options_screen.visible:
		options_screen.close()
	else:
		options_screen.open()


func _on_options_pressed() -> void:
	# WHAT THIS USED TO BE, in full:
	#
	#     print("options pressed (not yet implemented)")
	#
	# The button has been on the nav row the whole time, styled and wired, and
	# pressing it printed a line to a console the player does not have.
	toggle_options()


# =============================================================================
# CONTROLS AND THE WELCOME
# =============================================================================

const TOWN_SCENE_PATH := "res://scene/elusion.tscn"

# How long a new character stands in town before the welcome comes up: long
# enough for the fade-in to finish, short enough that they have not wandered.
const WELCOME_DELAY := 0.8


func _ensure_controls_panel() -> void:
	if controls_panel != null:
		return
	controls_panel = CONTROLS_SCENE.instantiate() as ControlsPanel
	add_child(controls_panel)
	controls_panel.visible = false


func toggle_controls() -> void:
	_ensure_controls_panel()
	if controls_panel == null:
		return
	if controls_panel.visible:
		controls_panel.close()
	else:
		controls_panel.open_controls()


func _on_controls_pressed() -> void:
	toggle_controls()


func _offer_welcome_soon() -> void:
	"""The welcome, once per computer, the first time a character stands in
	town. Asked after a short wait because this runs from the area's _ready(),
	and the tree only names the new area its current scene after that returns."""
	if ControlsPanel.has_seen_welcome() or not is_inside_tree():
		return
	get_tree().create_timer(WELCOME_DELAY).timeout.connect(offer_welcome)


static func welcome_belongs_in(scene_path: String) -> bool:
	return scene_path == TOWN_SCENE_PATH


func offer_welcome() -> void:
	# TOWN ONLY, because the welcome gives directions from where a new
	# character appears. And never inside the test runner, which is not a world
	# scene: a suite run must not mark the welcome seen on the machine it runs on.
	if not is_inside_tree() or ControlsPanel.has_seen_welcome():
		return
	var scene: Node = get_tree().current_scene
	if scene == null or not welcome_belongs_in(scene.scene_file_path):
		return
	_ensure_controls_panel()
	if controls_panel != null and not controls_panel.visible:
		controls_panel.open_welcome()


var _logging_out: bool = false


func _on_logout_pressed() -> void:
	# ONE LOGOUT AT A TIME. The await below can sit for the full request
	# timeout against an unreachable server, and the button stays clickable the
	# whole time. A second press re-ran all of this: freeing panels that were
	# already queued for deletion, clearing an already-cleared session, and
	# racing a second change_scene_to_file() against the first.
	if _logging_out:
		return
	_logging_out = true

	# CHANGED: was sending to CHARACTER_SELECT_PATH, which only lets you pick
	# a different character within the SAME already-authenticated session —
	# not a real logout. now that there's an actual login screen, "Log Out"
	# should mean returning all the way to it.
	if active_character != null:
		CharacterData.save_character_state(active_character)
	active_character = null

	# NULLED AS WELL AS FREED, and that is not tidiness.
	#
	# The await further down can sit for the full 10-second request timeout
	# against a dead server, and this HUD keeps running the whole time: _process
	# ticks, hotbar keys 1-9 and 0 still fire, _unhandled_input still routes. Every
	# guard on these references is `!= null`, and a queue_freed node is NOT null
	# — bankinventory.gd says exactly this ("the cache holds a freed instance,
	# which is not null"). So a hotbar key pressed during a slow logout reached
	# get_node_or_null() on a freed inventory screen.
	#
	# Freeing and nulling together makes those same guards tell the truth for
	# the seconds where it matters.
	if inventory_screen: inventory_screen.queue_free()
	if stats_screen:     stats_screen.queue_free()
	if bank_screen:      bank_screen.queue_free()
	if lootbag_panel:    lootbag_panel.queue_free()
	if cooking_panel:    cooking_panel.queue_free()
	if shop_panel:       shop_panel.queue_free()
	if kingdom_panel:    kingdom_panel.queue_free()
	if trade_panel:      trade_panel.queue_free()
	if owner_panel:      owner_panel.queue_free()
	if item_spawner:     item_spawner.queue_free()
	if staff_panel:      staff_panel.queue_free()

	inventory_screen = null
	stats_screen     = null
	bank_screen      = null
	lootbag_panel    = null
	cooking_panel    = null
	shop_panel       = null
	kingdom_panel    = null
	trade_panel      = null
	owner_panel      = null
	item_spawner     = null
	staff_panel      = null

	# NEW (E-2): send any training XP (defense/agility/magic) that has not hit
	# its 20s flush timer yet, while the token and active slot are still valid.
	# Awaited so it lands before Api.logout() clears the session below — after
	# that the server would reject it, and clear_current_user() resets the slot
	# it needs. A logout is the one deliberate "leaving" moment worth the wait;
	# an abrupt window-close still loses at most one flush interval. See
	# skilltrainer.gd.
	await SkillTrainer.flush()

	# AND THE SAVE, WAITED FOR. clear_current_user() below only STARTS the last
	# push, whose PUTs go one after another, and Api.logout() revokes the token
	# and clears it here - a race the push won on localhost, and one the order
	# should decide, not the network. Bounded, so a dead server cannot hold the
	# logout past CharacterData.QUIT_SAVE_SECONDS.
	await CharacterData.finish_saving()

	# NEW: reset CharacterData's in-memory state too — logout was only ever
	# clearing the UI panels, never actually telling CharacterData the user
	# session ended. without this, a second user logging in during the same
	# run would briefly (or permanently, if load_for_user() somehow didn't
	# fire) see whatever the previous user's data was.
	# (this also flushes any pending debounced save — see CharacterData.)
	CharacterData.clear_current_user()

	# NEW: end the SERVER session too, and wait for it before leaving.
	# Without this the cached token in user://session.cfg survives, the
	# login screen's _try_resume_session() finds it still valid, and it
	# sends you straight back to character select — making the login form
	# unreachable. Awaiting matters: Api.logout() only clears the local
	# token after the server call returns, so changing scene first would
	# race the login screen's check against it.
	await Api.logout()

	# PAST AN AWAIT. Up to the request timeout has passed, and this node can be
	# gone by now - the player died and the game-over screen took the scene with
	# it, or something else changed scenes while the server was not answering.
	# Same guard and same reason as fishingspot.gd and cookingscreen.gd.
	#
	# Worth being exact about what is at stake, because it is not an error in the
	# log: Api.logout() has already cleared the token by the time we get here, so
	# the account IS logged out either way. What a dropped or guarded coroutine
	# loses is only the change_scene below. Whichever scene took over is the one
	# the player is looking at, and sending them to the login menu from under it
	# would be the worse outcome. Returning is the right answer, not a fallback.
	if not is_instance_valid(self) or not is_inside_tree():
		return

	get_tree().change_scene_to_file(LOGIN_MENU_PATH)


func _on_switch_character_pressed() -> void:
	# "Switch Character" — return to character select WITHOUT a full
	# logout. deliberately does NOT call CharacterData.clear_current_user():
	# current_username and storage stay pointed at the same account, so
	# nothing needs re-entering. this is exactly what CHARACTER_SELECT_PATH
	# was kept around for after _on_logout_pressed() stopped using it — a
	# genuinely distinct action, not the old logout behavior repurposed.
	#
	# the active pet (if any) doesn't need special handling here — leaving
	# this scene frees it along with everything else, and whichever
	# character gets picked next will have its OWN active_pet_id restored
	# correctly when elusion.tscn reloads, same as any other scene change.
	if active_character != null:
		CharacterData.save_character_state(active_character)
	active_character = null

	# NULLED AS WELL AS FREED, and that is not tidiness.
	#
	# The await further down can sit for the full 10-second request timeout
	# against a dead server, and this HUD keeps running the whole time: _process
	# ticks, hotbar keys 1-9 and 0 still fire, _unhandled_input still routes. Every
	# guard on these references is `!= null`, and a queue_freed node is NOT null
	# — bankinventory.gd says exactly this ("the cache holds a freed instance,
	# which is not null"). So a hotbar key pressed during a slow logout reached
	# get_node_or_null() on a freed inventory screen.
	#
	# Freeing and nulling together makes those same guards tell the truth for
	# the seconds where it matters.
	if inventory_screen: inventory_screen.queue_free()
	if stats_screen:     stats_screen.queue_free()
	if bank_screen:      bank_screen.queue_free()
	if lootbag_panel:    lootbag_panel.queue_free()
	if cooking_panel:    cooking_panel.queue_free()
	if shop_panel:       shop_panel.queue_free()
	if kingdom_panel:    kingdom_panel.queue_free()
	if trade_panel:      trade_panel.queue_free()
	if owner_panel:      owner_panel.queue_free()
	if item_spawner:     item_spawner.queue_free()
	if staff_panel:      staff_panel.queue_free()

	inventory_screen = null
	stats_screen     = null
	bank_screen      = null
	lootbag_panel    = null
	cooking_panel    = null
	shop_panel       = null
	kingdom_panel    = null
	trade_panel      = null
	owner_panel      = null
	item_spawner     = null
	staff_panel      = null

	get_tree().change_scene_to_file(CHARACTER_SELECT_PATH)


# =============================================================================
# HOTBAR DISPATCH
# =============================================================================

func _on_hotbar_slot_used(slot: HotbarSlot) -> void:
	# THE KEY ITSELF IS USED, not the first bag cell holding the same item. It
	# is one of the backpack's cells, so use_item() spends from it and names it
	# to the server, and the count on the key is the count that goes down.
	if inventory_screen == null or slot == null or slot.is_empty():
		return
	inventory_screen.use_item(slot)


# =============================================================================
# INVENTORY ATOMIC SAVE
# =============================================================================

func _on_inventory_atomic_save() -> void:
	if active_character == null:
		return
	CharacterData.save_character_state(active_character)


# =============================================================================
# PANEL TOGGLES — INVENTORY
# =============================================================================

func toggle_inventory() -> void:
	if inventory_screen == null:
		_ensure_inventory_screen()
		if inventory_screen == null:
			return

	# THE BAG ONLY. It used to bring the doll up with it, and that pairing is
	# what put the doll over the shop's stock list and over the bank - every
	# screen that opens the bag so you can move items got a paper doll it never
	# asked for. The doll has its own button now; see the note on
	# equipment_panel near the top of this file.
	if inventory_screen.visible:
		inventory_screen.hide_inventory()
	else:
		if active_character != null:
			inventory_screen.set_player(active_character)
		inventory_screen.show_inventory()


func toggle_equipment() -> void:
	# The Equipment nav button and the G key. Opens and closes the doll and
	# nothing else - whether the bag is up is the bag's business.
	if equipment_panel != null and equipment_panel.visible:
		_hide_equipment_panel()
		return
	_show_equipment_panel()


func show_inventory() -> void:
	# NO with_equipment PARAMETER ANY MORE. It existed so the shop could pass
	# false, and the reason it had to was that the default was true - so every
	# other caller that opens the bag to move items (toggle_bank() here, and
	# bankinventory.gd) was still getting the doll, and nobody had noticed
	# because the shop was the only one anyone had complained about. Removing
	# the parameter removes the question: the bag opens alone, everywhere.
	if inventory_screen == null:
		_ensure_inventory_screen()
		if inventory_screen == null:
			return

	if active_character != null:
		inventory_screen.set_player(active_character)
	inventory_screen.show_inventory()


func hide_inventory() -> void:
	# The bag only, for the same reason. This is what the bag's own close button
	# routes to (inventory_screen.closed), and what the bank calls on its way
	# out - neither of which has any business closing a doll the player opened
	# themselves. Escape still closes both; see hide_panel().
	if inventory_screen != null:
		inventory_screen.hide_inventory()


# =============================================================================
# PANEL TOGGLES — EQUIPMENT
# =============================================================================
# ITS OWN PANEL: the Equipment nav button, or G. This header used to say "NOT
# ITS OWN TOGGLE" and describe a rule - "one panel that is only useful next to
# another is not two panels" - that stopped being true the day equipping became
# a move rather than a pointer into the bag. The code changed and the header did
# not, which left this file arguing with itself for a day.

func _ensure_equipment_panel() -> void:
	if equipment_panel != null:
		return

	equipment_panel = EQUIPMENT_SCENE.instantiate()
	add_child(equipment_panel)

	# NOTHING CONNECTED TO `closed` ANY MORE, and that is the fix for a real bug.
	# It was wired to hide_inventory(), so pressing the doll's own X closed the
	# BAG as well - fine while the two always travelled together, wrong the
	# moment G could open the doll alone. The X already hides the panel itself
	# (equipmentpanel.gd _on_close_pressed), so there is nothing left for the
	# HUD to do when it fires.

	if active_character != null:
		equipment_panel.set_player(active_character)
	equipment_panel.visible = false


func _show_equipment_panel() -> void:
	_ensure_equipment_panel()
	if equipment_panel == null:
		return
	if active_character != null:
		equipment_panel.set_player(active_character)
	equipment_panel.show_panel()


func _hide_equipment_panel() -> void:
	if equipment_panel != null:
		equipment_panel.hide_panel()


func _attach_inventory_to_hotbar() -> void:
	if hotbar == null or inventory_screen == null:
		return

	var container: Node = inventory_screen.get_node_or_null("%inventorycontainer")
	if container == null:
		return

	hotbar.set_inventory_container(container)

	if container.has_signal("inventory_changed"):
		if not container.inventory_changed.is_connected(_on_inventory_atomic_save):
			container.inventory_changed.connect(_on_inventory_atomic_save)


# =============================================================================
# PANEL TOGGLES — STATS
# =============================================================================

func toggle_stats() -> void:
	if stats_screen == null:
		stats_screen = STATSSCREEN_SCENE.instantiate()
		add_child(stats_screen)
		if not stats_screen.close_requested.is_connected(_on_stats_close_requested):
			stats_screen.close_requested.connect(_on_stats_close_requested)
		if active_character != null:
			stats_screen.setup_for_player(active_character)
		stats_screen.visible = true
		return

	if stats_screen.visible:
		stats_screen.visible = false
	else:
		if active_character != null:
			stats_screen.setup_for_player(active_character)
		stats_screen.visible = true


func _on_stats_close_requested() -> void:
	if stats_screen != null:
		stats_screen.visible = false


# =============================================================================
# PANEL TOGGLES — BANK
# =============================================================================

func toggle_bank() -> void:
	if bank_screen == null:
		bank_screen = BANK_SCENE.instantiate()
		add_child(bank_screen)

	if bank_screen.visible:
		if bank_screen.has_method("close_bank"):
			bank_screen.close_bank()
	else:
		show_inventory()
		if bank_screen.has_method("open_bank"):
			bank_screen.open_bank()


# =============================================================================
# PANEL TOGGLES — LOOT BAG
# =============================================================================

func open_lootbag(world_bag: Node, player: Node) -> void:
	# lazy-instantiate the loot bag panel (like stats/inventory), then point it
	# at the specific world bag being opened and show it. the panel loads the
	# bag's contents, resolves dupe pets to lusions, and syncs changes back.
	if lootbag_panel == null:
		lootbag_panel = LOOTBAG_PANEL_SCENE.instantiate()
		add_child(lootbag_panel)

	if lootbag_panel.has_method("open_for_bag"):
		lootbag_panel.open_for_bag(world_bag, player)


# =============================================================================
# PANEL TOGGLES — SHOP
# =============================================================================

func open_shop(shop_id: String, player: Node) -> void:
	# Lazy like every other panel here: built the first time a vendor is used
	# and kept afterwards, so walking back to the counter does not re-parse the
	# scene. The catalogue itself is re-fetched on every open, because stock and
	# prices are the server's and may have changed while the player was away.
	if shop_panel == null:
		shop_panel = SHOP_PANEL_SCENE.instantiate()
		add_child(shop_panel)

	# WITH the inventory, not instead of it. A shop the player cannot see their
	# own bag next to is one where they buy a second sword because they forgot
	# about the first — and the purchase lands in that bag, so it wants to be on
	# screen when it does. Same reason toggle_bank() shows it.
	# THE BACKPACK ONLY - which is now simply what show_inventory() does, so
	# there is no false to pass. Selling needs the bag on screen; nothing about a
	# shop needs the doll. Take gear off first if you mean to sell it - a real
	# action rather than bookkeeping, since unequipping puts the item back in the
	# bag. The Equipment button is right there on the nav bar if you want it.
	show_inventory()

	if shop_panel.has_method("open_for_shop"):
		shop_panel.open_for_shop(shop_id, player)


func toggle_trade() -> void:
	# Built on first use, like every other panel here. It polls while visible
	# and not at all while closed, so a player who never trades costs the
	# server nothing.
	if trade_panel == null:
		trade_panel = TRADE_PANEL_SCENE.instantiate()
		add_child(trade_panel)

	# OPENING IT IS THE ANSWER to "somebody is waiting on you", so the light
	# goes out now rather than a poll later. If the window is shut again with
	# the trade still waiting, the next poll lights it again.
	set_world_status("trade", "")
	_mark_trade_button(false)

	if trade_panel.has_method("toggle_panel"):
		await trade_panel.toggle_panel(active_character)


func toggle_kingdom() -> void:
	# BUILT ON FIRST USE, like every other panel here. Most players open this
	# rarely, and a board instantiated at spawn is a node polling nothing and
	# holding a scroll container for a screen nobody asked for.
	if kingdom_panel == null:
		kingdom_panel = KINGDOM_PANEL_SCENE.instantiate()
		add_child(kingdom_panel)

	if kingdom_panel.has_method("toggle_board"):
		await kingdom_panel.toggle_board()


func _on_chat_pressed() -> void:
	toggle_chat()


func _on_friends_pressed() -> void:
	toggle_friends()


func _on_players_pressed() -> void:
	toggle_players()


func _on_guild_pressed() -> void:
	toggle_guild()


func toggle_chat() -> void:
	# BUILT ON FIRST USE, like every other panel here. It also polls, so a
	# player who never opens it never starts that timer.
	if chat_panel == null:
		chat_panel = CHAT_PANEL_SCENE.instantiate()
		add_child(chat_panel)
		_flush_unlogged_lines()
		# A whisper that came before the window existed: it opens on it.
		chat_panel.last_whisper_from = _last_whisper_from
		if _whisper_waiting:
			chat_panel.whisper_arrived(_last_whisper_from)

	if chat_panel.has_method("toggle"):
		chat_panel.toggle()
	if chat_panel.visible:
		_mark_chat_button(false)
		_whisper_waiting = false

	# THE FLOATING BOX STANDS DOWN WHILE CHAT IS UP. The two live in the same
	# corner and would otherwise overlap, and every server notice would be
	# printed twice - once in each.
	if message_box != null and chat_panel.visible:
		message_box.visible = false


func toggle_friends() -> void:
	if friends_panel == null:
		friends_panel = FRIENDS_PANEL_SCENE.instantiate()
		add_child(friends_panel)

	if friends_panel.has_method("toggle"):
		friends_panel.toggle()


func toggle_players() -> void:
	# BUILT ON FIRST USE, like every other panel here. It polls while open, so a
	# player who never presses the button never starts that timer.
	if players_panel == null:
		players_panel = _build_players_panel()
		add_child(players_panel)

	if players_panel.has_method("toggle"):
		players_panel.toggle()


func _build_players_panel() -> Control:
	var panel: Control = PLAYERS_PANEL_SCENE.instantiate()
	# RIGHT-CLICK A NAME in the list: each goes to the window that already does
	# it, so there is one way to whisper, ask a friend or offer a trade.
	panel.whisper_asked.connect(whisper_player)
	panel.friend_asked.connect(ask_to_be_friends)
	panel.trade_asked.connect(trade_with)
	return panel


func whisper_player(who: String) -> void:
	"""Chat, open on the Whisper tab aimed at `who`."""
	if chat_panel == null or not chat_panel.visible:
		toggle_chat()
	chat_panel.start_whisper(who)


func ask_to_be_friends(who: String) -> void:
	"""The Friends window, open, with a request to `who` sent from it."""
	if friends_panel == null:
		friends_panel = FRIENDS_PANEL_SCENE.instantiate()
		add_child(friends_panel)
	await friends_panel.ask_from_elsewhere(who)


func trade_with(who: String) -> void:
	"""The Trade window, open on an offer to `who`."""
	if trade_panel == null:
		trade_panel = TRADE_PANEL_SCENE.instantiate()
		add_child(trade_panel)
	# Same as toggle_trade(): opening the window answers "somebody is waiting".
	set_world_status("trade", "")
	_mark_trade_button(false)
	await trade_panel.offer_to(active_character, who)


func toggle_guild() -> void:
	# BUILT ON FIRST USE, like every other panel here. It polls while open, so
	# a player who never presses the button never starts that timer.
	if guild_panel == null:
		guild_panel = GUILD_PANEL_SCENE.instantiate()
		add_child(guild_panel)

	if guild_panel.has_method("toggle"):
		guild_panel.toggle()


func close_shop() -> void:
	# Safe to call when nothing is open: the vendor calls this on walk-away
	# without knowing whether the player ever pressed interact.
	if shop_panel != null and shop_panel.has_method("close_shop"):
		shop_panel.close_shop()


# =============================================================================
# PANEL TOGGLES — COOKING
# =============================================================================

func open_cooking(firepit: Node, player: Node) -> void:
	# Lazy-instantiated on first use and then kept, exactly like the loot bag
	# panel above — a firepit is a thing most players walk past, so the scene is
	# not built until someone actually cooks at one.
	#
	# The HUD does not set .visible here. The panel owns its own visibility, the
	# same split open_lootbag() uses: this function's whole job is to make sure
	# the panel exists and to point it at the right firepit.
	if cooking_panel == null:
		cooking_panel = COOKING_PANEL_SCENE.instantiate()
		add_child(cooking_panel)

	if cooking_panel.has_method("open_for_firepit"):
		cooking_panel.open_for_firepit(firepit, player)


# =============================================================================
# PANEL STATE QUERIES
# =============================================================================

func hide_panel() -> void:
	# ESCAPE CLOSES EVERYTHING, so both panels, by name.
	#
	# This used to lean on hide_inventory() taking the doll down with the bag,
	# and a comment here explained why that mattered: the line once called the
	# inner inventory_screen.hide_inventory() instead, and Escape left the doll
	# hanging on its own. Now that the two really are separate panels,
	# hide_inventory() closes the bag and nothing else - so leaning on it would
	# reintroduce exactly that bug. The doll is closed here explicitly instead.
	hide_inventory()
	_hide_equipment_panel()
	if stats_screen != null:
		stats_screen.visible = false
	if bank_screen != null and bank_screen.visible:
		if bank_screen.has_method("close_bank"):
			bank_screen.close_bank()
	# The cooking panel counts in is_panel_open() below, so it has to close
	# here too — otherwise Escape would report "something is open", swallow the
	# press, and shut nothing.
	if cooking_panel != null and cooking_panel.visible:
		if cooking_panel.has_method("close_panel"):
			cooking_panel.close_panel()
	if options_screen != null and options_screen.visible:
		options_screen.close()
	if map_screen != null and map_screen.visible:
		map_screen.close()
	# CHAT CLOSES ON ESCAPE TOO, and it has to be listed in is_panel_open()
	# below for that to work - a panel that closes here but does not count
	# there lets Escape fall through to whatever else is open behind it.
	if chat_panel != null and chat_panel.visible:
		chat_panel.close()
	if friends_panel != null and friends_panel.visible:
		friends_panel.close()
	if guild_panel != null and guild_panel.visible:
		guild_panel.close()
	# The GM panel too, since it has an x now - Esc closing everything except
	# the one panel that sits on top of the others was the odd one out.
	if owner_panel != null and owner_panel.visible and owner_panel.has_method("close"):
		owner_panel.close()
	if item_spawner != null and item_spawner.visible:
		item_spawner.close()
	# And the staff desk, which is counted in is_panel_open() below for the
	# reason the chat panel gives: closed here, counted there, or Escape falls
	# through to whatever is behind it.
	if staff_panel != null and staff_panel.visible:
		staff_panel.close_panel()
	# And the Controls card, counted below for the same reason.
	if controls_panel != null and controls_panel.visible:
		controls_panel.close()


func is_panel_open() -> bool:
	var inv_open:   bool = inventory_screen != null and inventory_screen.visible
	var stats_open: bool = stats_screen     != null and stats_screen.visible
	var bank_open:  bool = bank_screen      != null and bank_screen.visible
	var cook_open:  bool = cooking_panel    != null and cooking_panel.visible
	var opts_open:  bool = options_screen   != null and options_screen.visible
	var map_open:   bool = map_screen       != null and map_screen.visible
	var chat_open:  bool = chat_panel      != null and chat_panel.visible
	var mates_open: bool = friends_panel   != null and friends_panel.visible
	# LISTED HERE BECAUSE IT CLOSES ON ESCAPE ABOVE. A panel that closes there
	# but does not count here lets Escape fall through to whatever is open
	# behind it - the comment over the chat panel says the same thing, and it
	# is the exact mistake this pair of lists exists to prevent.
	var guild_open: bool = guild_panel     != null and guild_panel.visible
	var staff_open: bool = staff_panel     != null and staff_panel.visible
	var keys_open:  bool = controls_panel  != null and controls_panel.visible
	var items_open: bool = item_spawner    != null and item_spawner.visible
	return (inv_open or stats_open or bank_open or cook_open or opts_open
		or map_open or chat_open or mates_open or guild_open or staff_open or keys_open
		or items_open)


func _any_panel_visible() -> bool:
	# EVERY PANEL, not the five is_panel_open() knows about.
	#
	# The two questions are different and it matters. is_panel_open() means
	# "is there something Escape should close", and it deliberately leaves out
	# the shop, the kingdom board, the loot bag, the trade window and the owner
	# panel — the trade window in particular has a server-side counterpart and
	# is not something a stray keypress should shut.
	#
	# THIS one means "is the screen already busy", and it is the guard on
	# Escape OPENING the options panel. Without it, pressing Escape at a
	# vendor would stack options on top of the shop, because is_panel_open()
	# would answer false about a panel that is plainly on screen.
	# equipment_panel is in the list even though it never appears without the
	# inventory. That pairing is a rule this file enforces, not a fact about
	# the node — and a list that says EVERY panel and then leaves one out is
	# how the pairing quietly stops being true.
	for panel in [inventory_screen, equipment_panel, stats_screen, bank_screen,
			lootbag_panel, cooking_panel, shop_panel, kingdom_panel,
			trade_panel, owner_panel, staff_panel, options_screen, map_screen,
			controls_panel, item_spawner]:
		if panel != null and panel.visible:
			return true
	return false
