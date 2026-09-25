# main HUD overlay — shows HP/mana/stamina bars, nav buttons, hotbar, and panels.
# CanvasLayer renders on top of the world. polls active player every frame
# for stat changes and updates bars accordingly. owns lazy-instantiated
# panels (stats, bank, lootbag) so they persist across opens. inventory is
# eagerly instantiated so the hotbar can resolve item lookups from spawn.
#
# atomic save policy:
# every inventory mutation triggers a full save via the inventory_changed
# signal hook. loot bag transfers also save atomically (in the loot panel).
extends CanvasLayer


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
# Owner-only save-viewer panel (see ownerpanel.gd). preload is fine
# here even though most players will never see it — the panel itself
# fails closed via Api.is_owner, so preloading the scene
# doesn't expose anything, it's just an inert resource until the owner
# actually toggles it with the backquote key.
const OWNER_PANEL_SCENE   := preload("res://scene/ui/owner/ownerpanel.tscn")
const CHAT_PANEL_SCENE    := preload("res://scene/ui/chat/chatpanel.tscn")
const FRIENDS_PANEL_SCENE := preload("res://scene/ui/friends/friendspanel.tscn")
const GUILD_PANEL_SCENE := preload("res://scene/ui/guild/guildpanel.tscn")


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
var chat_panel:       Control         = null
var friends_panel:    Control         = null
var guild_panel:      Control         = null

# The server's announcements, and the cursor into them. 0 means "I just got
# here" and the server answers with the recent tail rather than the whole
# table. See read_broadcasts() in app.py.
var message_box:      PanelContainer   = null
var message_rows:     VBoxContainer    = null
var _broadcast_cursor: int = 0
var _broadcast_poll_in_flight: bool = false

# Said once per closing, not once every ten seconds.
var _maintenance_warned: bool = false

# The last teleport id this client carried out. Kept so a move is not applied
# twice while the acknowledgement is still in flight - the poll can come round
# again before the server has been told.
var _teleport_done: int = 0
var options_screen:   Control         = null
var map_screen:       Control         = null

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
	_add_owner_button()
	_build_message_box()
	_start_broadcast_poll()
	_wire_hotbar()


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

	# Backquote / tilde toggles the owner panel. Anyone who is not the owner
	# gets no response at all by design, not even an error — see
	# _toggle_owner_panel().
	#
	# The whole function row was already spoken for. F1-F7 and F9-F12 are
	# player.gd's debug keys, and F8 is Godot's own "stop the running
	# project" shortcut, so binding to it closed the game. Backquote is the
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


func _process(_delta: float) -> void:
	# runs before the active_character guard below on purpose — a drag can be
	# in flight during a scene change, and the cursor still has to come back.
	_update_drag_cursor()

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
	# %navbuttons, NOT "navhbox/navbuttons". The menu has been rearranged twice in
	# two days - the staff buttons into the row the scene had reserved, and then
	# the whole thing into navframe, the PanelContainer that draws the bar - and
	# the second one moved every node in here one level deeper. A path spelled out
	# like that survives no rearrangement at all. A unique name is resolved against
	# the SCENE, so the row can be wrapped or reparented again and this still finds
	# it; the same goes for %staffrow below and %staffbutton in testrunner.gd.
	var nav: Node = get_node_or_null("%navbuttons")
	if nav == null:
		return

	for button in nav.get_children():
		if button is Button:
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
	# The buttons carry size_flags_horizontal = FILL|EXPAND, so they share that
	# width instead of queueing up on the left, and an eleventh costs the others
	# a few pixels each rather than running off the end.
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
		"guildbutton":             "_on_guild_pressed",
		"logoutbutton":            "_on_logout_pressed",
		# NEW: distinct from logout — returns to character select without
		# clearing the logged-in session, so no re-entering a password.
		"switchcharacterbutton":   "_on_switch_character_pressed",
	}
	for btn_name in bindings:
		if nav.has_node(btn_name):
			nav.get_node(btn_name).pressed.connect(Callable(self, bindings[btn_name]))


func _add_owner_button() -> void:
	# THE OWNER'S WAY IN, using the row the scene already reserved.
	#
	# characterhud.tscn has carried a "staffrow" with a hidden Staff button and
	# nothing driving it - a second row put aside for exactly this. Building a
	# THIRD row in code, which is what this used to do, stacked the menu three
	# deep for no reason. These go in the row that was waiting for them.
	#
	# STILL BUILT IN CODE, AND ONLY FOR THE OWNER. A button that exists in the
	# .tscn exists for every player - hidden, but present, and one `visible =
	# true` in a modified client away from being pressed. The server refuses
	# every one of these calls to anyone else regardless, so this is about not
	# shipping a door rather than about the lock.
	var row: Control = get_node_or_null("%staffrow") as Control
	if row == null:
		return

	# AN EMPTY ROW IS STILL A ROW. Left visible it contributes nothing but the
	# VBox's 4px of separation, which reads as the bar sitting slightly crooked
	# on every ordinary player's screen. Hidden, navframe shrinks to exactly one
	# row of buttons.
	#
	# AND ONLY THE OWNER'S BAR IS TWO ROWS TALL: 6 top + 24 + 4 + 28 + 6 bottom =
	# 68 against everyone else's 40. Since navframe grows upward from the floor,
	# that difference is spent on the staff row and the ordinary menu does not
	# move - which is why staffrow is declared FIRST in the scene, above
	# navbuttons rather than below it.
	if not Api.is_owner:
		row.visible = false
		return
	row.visible = true

	if row.has_node("ownerbutton"):
		return

	for spec in [
		["ownerbutton", "Owner",
			"Owner tools: view, kick, ban, rank, and the server switch",
			_toggle_owner_panel],
		["powersbutton", "Powers",
			"What mod, dev and owner can each do - read from the live server",
			_toggle_powers_panel],
	]:
		var button := Button.new()
		button.name = String(spec[0])
		button.text = String(spec[1])
		button.tooltip_text = String(spec[2])
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 12)
		# Matched to the nav row above by hand. That row gets its height from a
		# custom_minimum_size on the container, which cannot be used here - it
		# would hold the row open at that height for every player who is not the
		# owner, and this row has to collapse to nothing.
		button.custom_minimum_size = Vector2(0.0, 24.0)
		# Staff tools read warmer than the ordinary menu, so a glance tells you
		# which row can close the server and which one opens your bag.
		button.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))
		button.pressed.connect(spec[3])
		row.add_child(button)


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

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.058, 0.070, 0.094, 0.97)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.25, 0.33, 0.43)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.content_margin_left = 14.0
	style.content_margin_top = 12.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 12.0
	frame.add_theme_stylebox_override("panel", style)

	var scroll := ScrollContainer.new()
	scroll.name = "scroll"
	var rows := VBoxContainer.new()
	rows.name = "rows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	frame.add_child(scroll)
	add_child(frame)

	_load_powers()


func _powers_line(rows: VBoxContainer, text: String, color: Color, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	rows.add_child(label)


func _load_powers() -> void:
	var rows: VBoxContainer = get_node_or_null("powerspanel/scroll/rows")
	if rows == null:
		return
	for child in rows.get_children():
		child.queue_free()

	_powers_line(rows, "RANKS AND POWERS", Color(0.93, 0.73, 0.30), 17)
	_powers_line(rows, "Read from the server's own route decorators, not a hand-kept list.",
		Color(0.45, 0.50, 0.58), 11)

	var res: Dictionary = await Api.get_json("/api/staff/powers", Api.PROBE_TIMEOUT)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	rows = get_node_or_null("powerspanel/scroll/rows")
	if rows == null:
		return

	if not res.get("ok", false):
		_powers_line(rows, "Could not read the server: %s" % str(res.get("error", "")),
			Color(0.95, 0.45, 0.35), 13)
		return

	var data = res.get("data", {})
	if not (data is Dictionary):
		return

	for entry in data.get("ladder", []):
		if not (entry is Dictionary):
			continue
		var rank: String = str(entry.get("rank", "?")).to_upper()
		var grantable: bool = bool(entry.get("grantable", false))
		_powers_line(rows, "", Color(1, 1, 1), 4)
		_powers_line(rows, "%s%s" % [rank, "" if grantable else "   (cannot be granted)"],
			Color(0.50, 0.66, 0.85), 14)

		var routes: Array = entry.get("routes", [])
		if routes.is_empty() and entry.get("notes", []).is_empty():
			_powers_line(rows, "    nothing beyond playing the game", Color(0.55, 0.60, 0.68), 12)
		for route in routes:
			if route is Dictionary:
				_powers_line(rows, "    %s  %s" % [str(route.get("method", "")), str(route.get("path", ""))],
					Color(0.78, 0.83, 0.89), 12)
		for note in entry.get("notes", []):
			_powers_line(rows, "    - %s" % str(note), Color(0.93, 0.80, 0.55), 12)

	_powers_line(rows, "", Color(1, 1, 1), 6)
	var may_grant: Array = data.get("you_may_grant", [])
	var grant_text: String = "nothing"
	if not may_grant.is_empty():
		grant_text = ", ".join(PackedStringArray(may_grant))
	_powers_line(rows, "You are %s. You may grant: %s" % [str(data.get("you_are", "?")), grant_text],
		Color(0.43, 0.84, 0.49), 12)


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


func _push_message(text: String, color: Color) -> void:
	if text.strip_edges() == "":
		return

	# ONE NOTICE, ONE PLACE. With world chat open the conversation IS the
	# message log, so the line goes there and the floating box stays down;
	# with it closed the box is the only channel the player has and it pops as
	# it always did. Printing to both would double every maintenance warning.
	if chat_panel != null and chat_panel.visible:
		if chat_panel.has_method("push_system_line"):
			chat_panel.push_system_line(text, color)
			return

	if message_rows == null:
		return

	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 13)
	message_rows.add_child(label)

	# Oldest off the top, so the box never grows past its corner.
	while message_rows.get_child_count() > MESSAGES_KEPT:
		var oldest := message_rows.get_child(0)
		message_rows.remove_child(oldest)
		oldest.queue_free()

	if message_box != null:
		message_box.visible = true


func _start_broadcast_poll() -> void:
	if has_node("BroadcastPoll"):
		return
	var timer := Timer.new()
	timer.name = "BroadcastPoll"
	timer.wait_time = BROADCAST_POLL_SECONDS
	timer.one_shot = false
	timer.autostart = true
	timer.timeout.connect(_on_broadcast_poll_timeout)
	add_child(timer)


func _on_broadcast_poll_timeout() -> void:
	# Nothing to ask on behalf of nobody, and never two at once - a slow or
	# dead server must not stack requests behind each other.
	if _broadcast_poll_in_flight or not Api.is_logged_in():
		return
	_broadcast_poll_in_flight = true

	var res: Dictionary = await Api.get_json(
		"/api/server/broadcasts?since=%d" % _broadcast_cursor, Api.PROBE_TIMEOUT)

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
		_forced_signout()
		return
	if verdict != "ok":
		return

	var data = res.get("data", {})
	if not (data is Dictionary):
		return

	_read_maintenance(data.get("maintenance"))
	_read_teleport(data.get("teleport"))

	for entry in data.get("messages", []):
		if not (entry is Dictionary):
			continue
		var body: String = str(entry.get("body", ""))
		var kind: String = str(entry.get("kind", "system"))
		_push_message(body, Color(1.0, 0.82, 0.42) if kind == "system" else Color(0.85, 0.89, 0.94))

	var newest: int = int(data.get("latest_id", _broadcast_cursor))
	if newest > _broadcast_cursor:
		_broadcast_cursor = newest


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
		AreaRegistry.go_to(area, spot)
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
		return

	if _maintenance_warned:
		return
	_maintenance_warned = true

	var seconds: int = int(notice.get("seconds_left", 0))
	_push_message("The server is closing in %ds. Saving your progress now." % seconds,
		Color(0.95, 0.45, 0.35))

	# THE CLIENT'S HALF OF "SAVE EVERYONE BEFORE DISCONNECTING". The server
	# holds the door open for a grace window precisely so this can happen; a
	# debounced write that happened to be two seconds away is not good enough
	# when the room is about to empty.
	if CharacterData != null and CharacterData.has_method("flush_save"):
		CharacterData.flush_save()


func _forced_signout() -> void:
	# The server has already destroyed this session - kicked, banned, or the
	# grace window on a closing server ran out. Api.logout() would spend a
	# request on a token that no longer exists, which is exactly what
	# forget_session() exists for: keep the reason for the login screen, drop
	# the token, and go.
	_push_message("Signed out by the server.", Color(0.95, 0.45, 0.35))

	# Flushes any pending debounced save on the way out.
	CharacterData.clear_current_user()
	Api.forget_session("You were signed out by the server.")

	if not is_instance_valid(self) or not is_inside_tree():
		return
	get_tree().change_scene_to_file(LOGIN_MENU_PATH)


func _wire_hotbar() -> void:
	if hotbar == null:
		return
	if not hotbar.item_used.is_connected(_on_hotbar_item_used):
		hotbar.item_used.connect(_on_hotbar_item_used)


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

	if hotbar != null:
		hotbar.set_player(active_character)


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
	# ticks, hotbar keys 1-9 still fire, _unhandled_input still routes. Every
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

	inventory_screen = null
	stats_screen     = null
	bank_screen      = null
	lootbag_panel    = null
	cooking_panel    = null
	shop_panel       = null
	kingdom_panel    = null
	trade_panel      = null
	owner_panel      = null

	# NEW (E-2): send any training XP (defense/agility/magic) that has not hit
	# its 20s flush timer yet, while the token and active slot are still valid.
	# Awaited so it lands before Api.logout() clears the session below — after
	# that the server would reject it, and clear_current_user() resets the slot
	# it needs. A logout is the one deliberate "leaving" moment worth the wait;
	# an abrupt window-close still loses at most one flush interval. See
	# skilltrainer.gd.
	await SkillTrainer.flush()

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
	# get_tree() on a freed node errors, and the logout never finishes. Same
	# guard and same reason as fishingspot.gd and cookingscreen.gd.
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
	# ticks, hotbar keys 1-9 still fire, _unhandled_input still routes. Every
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

	inventory_screen = null
	stats_screen     = null
	bank_screen      = null
	lootbag_panel    = null
	cooking_panel    = null
	shop_panel       = null
	kingdom_panel    = null
	trade_panel      = null
	owner_panel      = null

	get_tree().change_scene_to_file(CHARACTER_SELECT_PATH)


# =============================================================================
# HOTBAR DISPATCH
# =============================================================================

func _on_hotbar_item_used(item_id: String) -> void:
	if inventory_screen == null:
		return

	var container: Node = inventory_screen.get_node_or_null("%inventorycontainer")
	if container == null:
		return

	var slot_index: int = container.find_first_index_of(item_id)
	if slot_index == -1:
		return

	var slot: InventorySlot = container.get_slot_at(slot_index)
	if slot == null:
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


func _on_guild_pressed() -> void:
	toggle_guild()


func toggle_chat() -> void:
	# BUILT ON FIRST USE, like every other panel here. It also polls, so a
	# player who never opens it never starts that timer.
	if chat_panel == null:
		chat_panel = CHAT_PANEL_SCENE.instantiate()
		add_child(chat_panel)

	if chat_panel.has_method("toggle"):
		chat_panel.toggle()

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
	return (inv_open or stats_open or bank_open or cook_open or opts_open
		or map_open or chat_open or mates_open or guild_open)


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
			trade_panel, owner_panel, options_screen, map_screen]:
		if panel != null and panel.visible:
			return true
	return false
