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

# preloaded panel scenes
const INVENTORY_SCENE     := preload("res://scene/ui/inventory/inventory.tscn")
const STATSSCREEN_SCENE   := preload("res://scene/ui/statsscreen.tscn")
const BANK_SCENE          := preload("res://scene/ui/bank/bankinventory.tscn")
const LOOTBAG_PANEL_SCENE := preload("res://scene/ui/lootbag/lootbaginventory.tscn")


# =============================================================================
# STATE
# =============================================================================

var active_character: Node = null

# stat bar references — resolved in _ready
var healthbar:  TextureProgressBar = null
var magicbar:   TextureProgressBar = null
var staminabar: TextureProgressBar = null

# panel references — inventory is eagerly created in set_active_character,
# stats/bank/lootbag stay lazy.
var inventory_screen: InventoryScreen = null
var stats_screen:     Control         = null
var bank_screen:      Control         = null
var lootbag_panel:    Control         = null

# hotbar reference — resolved on _ready
var hotbar: Hotbar = null

# cached previous values so _process only updates bars when stats change
var _last_hp:      int = -1
var _last_mana:    int = -1
var _last_stamina: int = -1


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	add_to_group("hud")
	_resolve_bar_references()
	_resolve_hotbar()
	_wire_nav_buttons()
	_wire_hotbar()


func _process(_delta: float) -> void:
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

	if stats_screen != null and stats_screen.visible:
		stats_screen.update_display()


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

	print("HUD INIT: healthbar=%s, magicbar=%s, staminabar=%s" % [
		"OK" if healthbar else "NULL",
		"OK" if magicbar else "NULL",
		"OK" if staminabar else "NULL",
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
		"inventorybutton": "_on_inventory_pressed",
		"statsbutton":     "_on_stats_pressed",
		"shopbutton":      "_on_shop_pressed",
		"mapbutton":       "_on_map_pressed",
		"optionsbutton":   "_on_options_pressed",
		"discordbutton":   "_on_discord_pressed",
		"logoutbutton":    "_on_logout_pressed",
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
	if active_character != null:
		CharacterData.save_character_state(active_character)
	active_character = null

	if inventory_screen: inventory_screen.queue_free()
	if stats_screen:     stats_screen.queue_free()
	if bank_screen:      bank_screen.queue_free()
	if lootbag_panel:    lootbag_panel.queue_free()

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
