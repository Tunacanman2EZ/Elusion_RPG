extends CanvasLayer

var active_character: Node = null
var healthbar: TextureProgressBar = null
var magicbar: TextureProgressBar = null
var staminabar: TextureProgressBar = null

func _ready() -> void:
	healthbar = get_node_or_null("barcontainer/healthbar")
	magicbar = get_node_or_null("barcontainer/magicbar")
	staminabar = get_node_or_null("barcontainer/staminabar")

	var nav = get_node_or_null("navhbox/navbuttons")
	if nav:
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
	if character == null:
		push_error("set_active_character called with null!")
		return
	active_character = character
	update_bars()

func get_active_character() -> Node:
	return active_character

func update_bars() -> void:
	if active_character == null:
		return
	var hp = active_character.get("hp")
	var max_hp = active_character.get("max_hp")
	if healthbar:
		healthbar.max_value = max_hp
		healthbar.value = hp
	if magicbar:
		magicbar.max_value = max(active_character.get("max_mana"), 1)
		magicbar.value = active_character.get("mana")
	if staminabar:
		staminabar.max_value = active_character.get("max_stamina")
		staminabar.value = active_character.get("stamina")

func _process(_delta: float) -> void:
	if active_character:
		update_bars()

func _on_inventory_pressed() -> void:
	toggle_inventory()

func _on_stats_pressed() -> void:
	toggle_stats()

func _on_shop_pressed() -> void:
	pass

func _on_map_pressed() -> void:
	pass

func _on_options_pressed() -> void:
	pass

func _on_discord_pressed() -> void:
	OS.shell_open("https://discord.gg/4PEhh4Uu")

func _on_logout_pressed() -> void:
	get_tree().change_scene_to_file("res://scene/menu/characterselect.tscn")

func toggle_inventory() -> void:
	pass

func toggle_stats() -> void:
	pass

func show_inventory() -> void:
	pass

func show_stats() -> void:
	pass

func hide_panel() -> void:
	pass

func is_panel_open() -> bool:
	return false
