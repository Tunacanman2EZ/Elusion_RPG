# main HUD overlay — shows HP/mana/stamina bars and nav buttons
extends CanvasLayer

# reference to the currently active player character
var active_character: Node = null

# references to the three stat bars in the HUD
var healthbar: TextureProgressBar = null
var magicbar: TextureProgressBar = null
var staminabar: TextureProgressBar = null

func _ready() -> void:
	# find the health bar node inside the bar container
	healthbar = get_node_or_null("barcontainer/healthbar")

	# find the mana bar node inside the bar container
	magicbar = get_node_or_null("barcontainer/magicbar")

	# find the stamina bar node inside the bar container
	staminabar = get_node_or_null("barcontainer/staminabar")

	# find the navigation buttons container
	var nav = get_node_or_null("navhbox/navbuttons")

	if nav:
		# connect each nav button to its handler function if it exists
		if nav.has_node("InventoryButton"):
			nav.get_node("InventoryButton").pressed.connect(_on_inventory_pressed)

		if nav.has_node("StatsButton"):
			nav.get_node("StatsButton").pressed.connect(_on_stats_pressed)

		if nav.has_node("ShopButton"):
			nav.get_node("ShopButton").pressed.connect(_on_shop_pressed)

		if nav.has_node("MapButton"):
			nav.get_node("MapButton").pressed.connect(_on_map_pressed)

		if nav.has_node("OptionsButton"):
			nav.get_node("OptionsButton").pressed.connect(_on_options_pressed)

		if nav.has_node("DiscordButton"):
			nav.get_node("DiscordButton").pressed.connect(_on_discord_pressed)

		if nav.has_node("LogoutButton"):
			nav.get_node("LogoutButton").pressed.connect(_on_logout_pressed)

func set_active_character(character: Node) -> void:
	# safety check — never set active character to null
	if character == null:
		push_error("set_active_character called with null!")
		return

	# store reference to the active player character
	active_character = character

	# immediately update bars to show correct starting values
	update_bars()

func get_active_character() -> Node:
	# returns the currently active character — used by other systems
	return active_character

func update_bars() -> void:
	# do nothing if no character is set
	if active_character == null:
		return

	# get current and max hp from the active character
	var hp = active_character.get("hp")
	var max_hp = active_character.get("max_hp")

	# update health bar if it exists
	if healthbar:
		healthbar.max_value = max_hp  # set the bar maximum
		healthbar.value = hp          # set the bar current fill

	# update mana bar if it exists
	if magicbar:
		# use max() to prevent division by zero if max_mana is 0
		magicbar.max_value = max(active_character.get("max_mana"), 1)
		magicbar.value = active_character.get("mana")

	# update stamina bar if it exists
	if staminabar:
		staminabar.max_value = active_character.get("max_stamina")
		staminabar.value = active_character.get("stamina")

func _process(_delta: float) -> void:
	# update bars every frame so they reflect real time stat changes
	if active_character:
		update_bars()

# --- nav button handlers ---

func _on_inventory_pressed() -> void:
	# open or close the inventory panel
	toggle_inventory()

func _on_stats_pressed() -> void:
	# open or close the stats panel
	toggle_stats()

func _on_shop_pressed() -> void:
	# placeholder — shop UI not yet implemented
	pass

func _on_map_pressed() -> void:
	# placeholder — map UI not yet implemented
	pass

func _on_options_pressed() -> void:
	# placeholder — options UI not yet implemented
	pass

func _on_discord_pressed() -> void:
	# open the elusion studios discord server in the browser
	OS.shell_open("https://discord.gg/4PEhh4Uu")

func _on_logout_pressed() -> void:
	# return to the character select screen
	get_tree().change_scene_to_file("res://scene/menu/characterselect.tscn")

# --- panel toggles — to be implemented in phase 1 ---

func toggle_inventory() -> void:
	# toggle inventory panel open or closed
	pass

func toggle_stats() -> void:
	# toggle stats panel open or closed
	pass

func show_inventory() -> void:
	# force inventory panel open
	pass

func show_stats() -> void:
	# force stats panel open
	pass

func hide_panel() -> void:
	# force all panels closed
	pass

func is_panel_open() -> bool:
	# returns true if any panel is currently open
	return false
