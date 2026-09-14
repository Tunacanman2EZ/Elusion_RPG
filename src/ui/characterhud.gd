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

const DISCORD_URL := "https://discord.gg/4PEhh4Uu"
const CHARACTER_SELECT_PATH := "res://scene/ui/menus/characterselect.tscn"
# NEW: log out now goes all the way back to the login screen (true logout),
# not just character select — see _on_logout_pressed(). CHARACTER_SELECT_PATH
# is kept in case a separate "switch character" action (distinct from a full
# logout) gets added later, even though nothing in this file uses it right
# now.
const LOGIN_MENU_PATH := "res://scene/ui/menus/loginmenu.tscn"

# preloaded panel scenes
const INVENTORY_SCENE     := preload("res://scene/ui/inventory/inventory.tscn")
const STATSSCREEN_SCENE   := preload("res://scene/ui/statsscreen.tscn")
const BANK_SCENE          := preload("res://scene/ui/bank/bankinventory.tscn")
const LOOTBAG_PANEL_SCENE := preload("res://scene/ui/lootbag/lootbaginventory.tscn")
# Owner-only save-viewer panel (see ownerpanel.gd). preload is fine
# here even though most players will never see it — the panel itself
# fails closed via Api.is_owner, so preloading the scene
# doesn't expose anything, it's just an inert resource until the owner
# actually toggles it with the backquote key.
const OWNER_PANEL_SCENE   := preload("res://scene/ui/owner/ownerpanel.tscn")


# =============================================================================
# STATE
# =============================================================================

var active_character: Node = null

# stat bar references — resolved in _ready
var healthbar:  TextureProgressBar = null
var magicbar:   TextureProgressBar = null
var staminabar: TextureProgressBar = null

# panel references — inventory is eagerly created in set_active_character,
# stats/bank/lootbag/owner stay lazy.
var inventory_screen: InventoryScreen = null
var stats_screen:     Control         = null
var bank_screen:      Control         = null
var lootbag_panel:    Control         = null
var owner_panel:      Control         = null

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
	add_to_group("hud")
	_resolve_bar_references()
	_resolve_hotbar()
	_wire_nav_buttons()
	_wire_hotbar()


func _unhandled_input(event: InputEvent) -> void:
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
	# is Shift and `move_left` is A, so interacting while walking left
	# toggled the panel.
	if event is InputEventKey and event.pressed and event.keycode == KEY_QUOTELEFT:
		_toggle_owner_panel()


func _toggle_owner_panel() -> void:
	# THE OWNER, not merely an admin. is_admin is a database column that a
	# future mod or dev could hold; the owner is named in the server's
	# environment and is the one account that cannot be granted. Read straight
	# from Api rather than through CharacterData, because that flag is never
	# persisted — there is no file holding it to edit.
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
	var nav: Node = get_node_or_null("navhbox/navbuttons")
	if nav == null:
		return

	for button in nav.get_children():
		if button is Button:
			button.focus_mode = Control.FOCUS_NONE

	var bindings := {
		"inventorybutton":         "_on_inventory_pressed",
		"statsbutton":             "_on_stats_pressed",
		"shopbutton":              "_on_shop_pressed",
		"mapbutton":               "_on_map_pressed",
		"optionsbutton":           "_on_options_pressed",
		"discordbutton":           "_on_discord_pressed",
		"logoutbutton":            "_on_logout_pressed",
		# NEW: distinct from logout — returns to character select without
		# clearing the logged-in session, so no re-entering a password.
		"switchcharacterbutton":   "_on_switch_character_pressed",
	}
	for btn_name in bindings:
		if nav.has_node(btn_name):
			nav.get_node(btn_name).pressed.connect(Callable(self, bindings[btn_name]))


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
	if stats_screen != null:
		stats_screen.setup_for_player(active_character)

	if hotbar != null:
		hotbar.set_player(active_character)


func get_active_character() -> Node:
	return active_character


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

	if healthbar:
		healthbar.max_value = active_character.get("max_hp")
		healthbar.value     = active_character.get("hp")

	if magicbar:
		magicbar.max_value = max(active_character.get("max_mana"), 1)
		magicbar.value     = active_character.get("mana")

	if staminabar:
		staminabar.max_value = active_character.get("max_stamina")
		staminabar.value     = active_character.get("stamina")


func _animate_bars(delta: float) -> void:
	if active_character == null:
		return

	_ease_bar(healthbar,   active_character.get("hp"),      active_character.get("max_hp"),      delta)
	_ease_bar(magicbar,    active_character.get("mana"),    active_character.get("max_mana"),    delta)
	_ease_bar(staminabar,  active_character.get("stamina"), active_character.get("max_stamina"), delta)


func _ease_bar(bar: TextureProgressBar, target: float, stat_max: float, delta: float) -> void:
	if bar == null:
		return

	# keep the range current — max_hp changes on every level-up
	bar.max_value = maxf(stat_max, 1.0)

	# DROPS SNAP. Damage has to read instantly: a health bar that glides down
	# after a hit tells you a moment late that you were hit, and in a fight
	# that moment is the whole point of having a health bar. Only refilling
	# eases, which is where the wobble lived anyway.
	if target <= bar.value:
		bar.value = target
		return

	if target - bar.value <= BAR_SNAP_THRESHOLD:
		bar.value = target
		return

	# Exponential ease, framerate independent. Using exp() rather than a plain
	# lerp(a, b, speed * delta) matters: the naive version moves a different
	# fraction of the gap at 60fps than at 144, so the bars would fill at
	# different speeds on different machines.
	bar.value = lerpf(bar.value, target, 1.0 - exp(-BAR_FILL_SPEED * delta))


# =============================================================================
# NAV BUTTON HANDLERS
# =============================================================================

func _on_inventory_pressed() -> void:
	toggle_inventory()


func _on_stats_pressed() -> void:
	toggle_stats()


func _on_shop_pressed() -> void:
	print("shop pressed (not yet implemented)")


func _on_map_pressed() -> void:
	print("map pressed (not yet implemented)")


func _on_options_pressed() -> void:
	print("options pressed (not yet implemented)")


func _on_discord_pressed() -> void:
	OS.shell_open(DISCORD_URL)


func _on_logout_pressed() -> void:
	# CHANGED: was sending to CHARACTER_SELECT_PATH, which only lets you pick
	# a different character within the SAME already-authenticated session —
	# not a real logout. now that there's an actual login screen, "Log Out"
	# should mean returning all the way to it.
	if active_character != null:
		CharacterData.save_character_state(active_character)
	active_character = null

	if inventory_screen: inventory_screen.queue_free()
	if stats_screen:     stats_screen.queue_free()
	if bank_screen:      bank_screen.queue_free()
	if lootbag_panel:    lootbag_panel.queue_free()
	if owner_panel:      owner_panel.queue_free()

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

	if inventory_screen: inventory_screen.queue_free()
	if stats_screen:     stats_screen.queue_free()
	if bank_screen:      bank_screen.queue_free()
	if lootbag_panel:    lootbag_panel.queue_free()
	if owner_panel:      owner_panel.queue_free()

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

	if inventory_screen.visible:
		inventory_screen.hide_inventory()
	else:
		if active_character != null:
			inventory_screen.set_player(active_character)
		inventory_screen.show_inventory()


func show_inventory() -> void:
	if inventory_screen == null:
		_ensure_inventory_screen()
		if inventory_screen == null:
			return

	if active_character != null:
		inventory_screen.set_player(active_character)
	inventory_screen.show_inventory()


func hide_inventory() -> void:
	if inventory_screen != null:
		inventory_screen.hide_inventory()


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


func show_stats() -> void:
	if stats_screen == null:
		toggle_stats()
		return

	if active_character != null:
		stats_screen.setup_for_player(active_character)
	stats_screen.visible = true


func hide_stats() -> void:
	if stats_screen != null:
		stats_screen.visible = false


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
# PANEL STATE QUERIES
# =============================================================================

func hide_panel() -> void:
	if inventory_screen != null:
		inventory_screen.hide_inventory()
	if stats_screen != null:
		stats_screen.visible = false
	if bank_screen != null and bank_screen.visible:
		if bank_screen.has_method("close_bank"):
			bank_screen.close_bank()


func is_panel_open() -> bool:
	var inv_open:   bool = inventory_screen != null and inventory_screen.visible
	var stats_open: bool = stats_screen     != null and stats_screen.visible
	var bank_open:  bool = bank_screen      != null and bank_screen.visible
	return inv_open or stats_open or bank_open
