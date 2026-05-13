# main HUD overlay — shows HP/mana/stamina bars, nav buttons, and panels
extends CanvasLayer

# discord invite URL — kept as a constant so it can be updated in one place
const DISCORD_URL := "https://discord.gg/4PEhh4Uu"

# scene path for the character select screen — used by logout
const CHARACTER_SELECT_PATH := "res://scene/ui/menus/characterselect.tscn"

# preloaded reference to the inventory scene
# instantiated lazily when the player first opens the inventory
const INVENTORY_SCENE := preload("res://scene/ui/inventory/inventory.tscn")

# preloaded reference to the stats screen scene
# instantiated lazily on first toggle, then reused (preserves position drag)
const STATSSCREEN_SCENE := preload("res://scene/ui/statsscreen.tscn")

# reference to the currently active player character
var active_character: Node = null

# references to the three stat bars in the HUD
var healthbar: TextureProgressBar = null
var magicbar: TextureProgressBar = null
var staminabar: TextureProgressBar = null

# instance of the inventory screen — created on first toggle, then reused
var inventory_screen: InventoryScreen = null

# instance of the stats screen — created on first toggle, then reused
# preserving the instance keeps the dragged position across opens
var stats_screen: StatsScreen = null

# cached previous values so _process only updates bars when stats actually change
var _last_hp: int = -1
var _last_mana: int = -1
var _last_stamina: int = -1

func _ready() -> void:
	add_to_group("hud")

	healthbar = get_node_or_null("barcontainer/healthbar")
	if healthbar == null:
		push_warning("HUD: healthbar node not found at barcontainer/healthbar")

	magicbar = get_node_or_null("barcontainer/magicbar")
	if magicbar == null:
		push_warning("HUD: magicbar node not found at barcontainer/magicbar")

	staminabar = get_node_or_null("barcontainer/staminabar")
	if staminabar == null:
		push_warning("HUD: staminabar node not found at barcontainer/staminabar")

	var nav = get_node_or_null("navhbox/navbuttons")

	if nav:
		# disable focus on nav buttons so arrow keys don't navigate them
		for button in nav.get_children():
			if button is Button:
				button.focus_mode = Control.FOCUS_NONE

		# wire up each nav button via Callable to avoid forward-reference issues
		if nav.has_node("inventorybutton"):
			nav.get_node("inventorybutton").pressed.connect(Callable(self, "_on_inventory_pressed"))

		if nav.has_node("statsbutton"):
			nav.get_node("statsbutton").pressed.connect(Callable(self, "_on_stats_pressed"))

		if nav.has_node("shopbutton"):
			nav.get_node("shopbutton").pressed.connect(Callable(self, "_on_shop_pressed"))

		if nav.has_node("mapbutton"):
			nav.get_node("mapbutton").pressed.connect(Callable(self, "_on_map_pressed"))

		if nav.has_node("optionsbutton"):
			nav.get_node("optionsbutton").pressed.connect(Callable(self, "_on_options_pressed"))

		if nav.has_node("discordbutton"):
			nav.get_node("discordbutton").pressed.connect(Callable(self, "_on_discord_pressed"))

		if nav.has_node("logoutbutton"):
			nav.get_node("logoutbutton").pressed.connect(Callable(self, "_on_logout_pressed"))

func set_active_character(character: Node) -> void:
	if character == null:
		push_error("set_active_character called with null!")
		return

	active_character = character

	_last_hp = -1
	_last_mana = -1
	_last_stamina = -1

	update_bars()

	# if the inventory screen already exists, refresh its player reference
	if inventory_screen != null:
		inventory_screen.set_player(active_character)

	# if the stats screen already exists, refresh its player reference
	if stats_screen != null:
		stats_screen.setup_for_player(active_character)

func get_active_character() -> Node:
	return active_character

func update_bars() -> void:
	if active_character == null:
		print("HUD UPDATE_BARS: active_character is NULL")
		return

	var hp: int = active_character.get("hp")
	var max_hp: int = active_character.get("max_hp")

	if healthbar:
		healthbar.max_value = max_hp
		healthbar.value = hp

	if magicbar:
		var current_mana = active_character.get("mana")
		var max_mana = max(active_character.get("max_mana"), 1)
		print("HUD UPDATE_BARS: setting magicbar to %d/%d (character=%s)" % [
			current_mana, max_mana, active_character.name
		])
		magicbar.max_value = max_mana
		magicbar.value = current_mana
	else:
		print("HUD UPDATE_BARS: magicbar is NULL!")

	if staminabar:
		staminabar.max_value = active_character.get("max_stamina")
		staminabar.value = active_character.get("stamina")

func _process(_delta: float) -> void:
	if active_character == null:
		return

	var hp: int = active_character.get("hp")
	var mana: int = active_character.get("mana")
	var stamina: int = active_character.get("stamina")

	if hp != _last_hp or mana != _last_mana or stamina != _last_stamina:
		update_bars()
		_last_hp = hp
		_last_mana = mana
		_last_stamina = stamina

		# also refresh stats screen if it's open — keeps the displayed
		# stats in sync with the HUD bars when player takes damage etc
		if stats_screen != null and stats_screen.visible:
			stats_screen.update_display()

# --- nav button handlers ---

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

	get_tree().change_scene_to_file(CHARACTER_SELECT_PATH)

# --- panel toggles ---

func toggle_inventory() -> void:
	if inventory_screen == null:
		inventory_screen = INVENTORY_SCENE.instantiate()
		add_child(inventory_screen)
		inventory_screen.closed.connect(hide_inventory)
		if active_character != null:
			inventory_screen.set_player(active_character)
		_populate_inventory_from_player()
		inventory_screen.show_inventory()
	elif inventory_screen.visible:
		inventory_screen.hide_inventory()
	else:
		inventory_screen.show_inventory()

func toggle_stats() -> void:
	# lazy-instantiate the stats screen on first toggle.
	# subsequent toggles just show/hide the same instance so the dragged
	# position and any internal state are preserved across opens.
	if stats_screen == null:
		stats_screen = STATSSCREEN_SCENE.instantiate()
		add_child(stats_screen)

		# wire the close button signal — emitted from statsscreen.gd when
		# the player clicks the X on the panel
		if not stats_screen.close_requested.is_connected(_on_stats_close_requested):
			stats_screen.close_requested.connect(_on_stats_close_requested)

		# initial setup with the active player
		if active_character != null:
			stats_screen.setup_for_player(active_character)

		stats_screen.visible = true
		return

	# toggle visibility on subsequent presses
	if stats_screen.visible:
		stats_screen.visible = false
	else:
		# re-refresh display before showing — picks up stat changes since last view
		if active_character != null:
			stats_screen.setup_for_player(active_character)
		stats_screen.visible = true

func _on_stats_close_requested() -> void:
	# called when the player presses the X on the stats screen
	if stats_screen != null:
		stats_screen.visible = false

func show_inventory() -> void:
	if inventory_screen == null:
		toggle_inventory()
	else:
		inventory_screen.show_inventory()

func show_stats() -> void:
	# force the stats screen open
	if stats_screen == null:
		toggle_stats()  # creates and shows
	else:
		if active_character != null:
			stats_screen.setup_for_player(active_character)
		stats_screen.visible = true

func hide_inventory() -> void:
	if inventory_screen != null:
		inventory_screen.hide_inventory()

func hide_stats() -> void:
	# force the stats screen closed
	if stats_screen != null:
		stats_screen.visible = false

func hide_panel() -> void:
	# force all panels closed
	if inventory_screen != null:
		inventory_screen.hide_inventory()
	if stats_screen != null:
		stats_screen.visible = false

func is_panel_open() -> bool:
	# returns true if any panel is currently open
	var inv_open: bool = inventory_screen != null and inventory_screen.visible
	var stats_open: bool = stats_screen != null and stats_screen.visible
	return inv_open or stats_open

func _populate_inventory_from_player() -> void:
	if active_character == null:
		return
	if not "inventory_data" in active_character:
		return

	var container: Node = inventory_screen.get_node_or_null("%inventorycontainer")
	if container == null or not container.has_method("load_save_array"):
		return

	var saved: Array = active_character.inventory_data
	if saved.size() > 0:
		container.load_save_array(saved)
