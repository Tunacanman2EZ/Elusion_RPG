extends Node2D

const InventoryPersist = preload("res://inventory/InventoryPersistence.gd")

var current_player: Node = null
var last_panel: String = ""

# --- Panel/Screen Helpers ---
func _get_panelcontainer():
	return get_node("MenuScreen/InventoryUI/PanelContainer")

func _get_vbox():
	return _get_panelcontainer().get_node("VBoxContainer")

func _get_inventory_screen():
	return _get_vbox().get_node("InventoryScreen")

# --- General toggle logic for any panel or screen ---
func toggle_panel(panel_name: String):
	var container = _get_panelcontainer()
	# Specialized: Inventory toggles VBoxContainer + InventoryScreen together
	if panel_name == "InventoryScreen":
		var vbox = _get_vbox()
		var inv_screen = _get_inventory_screen()
		var is_open = container.visible and vbox.visible and inv_screen.visible
		# Hide all
		for child in container.get_children():
			child.visible = false
		for node in vbox.get_children():
			node.visible = false
		vbox.visible = false
		container.visible = false
		if not is_open:
			container.visible = true
			vbox.visible = true
			inv_screen.visible = true
		return
	# Normal: Toggle panel by name (e.g., Stats, Shop, etc)
	var panel = container.get_node_or_null(panel_name)
	if panel:
		var was_open = container.visible and panel.visible
		for child in container.get_children():
			child.visible = false
		container.visible = false
		if not was_open:
			container.visible = true
			panel.visible = true

# --- Player Management ---
func spawn_player_from_selection():
	var slot_idx = CharacterData.active_character_index
	var scenes = [
		preload("res://scenes/Warrior.tscn"),
		preload("res://scenes/Mage.tscn"),
		preload("res://scenes/Tank.tscn"),
		preload("res://scenes/Healer.tscn"),
	]
	if slot_idx < 0 or slot_idx >= scenes.size():
		push_error("No valid character slot selected! Index: %d" % slot_idx)
		return
	if current_player and current_player.is_inside_tree():
		current_player.queue_free()
	var scene = scenes[slot_idx]
	var player = scene.instantiate()
	if not player:
		push_error("Player scene failed to instance!")
		return
	var spawn = get_node_or_null("PlayerSpawn")
	if not spawn:
		push_error("PlayerSpawn node not found!")
		return
	player.global_position = spawn.global_position
	add_child(player)
	current_player = player
	if "inventory" in player:
		player.inventory = InventoryPersist.load_or_create_bag(slot_idx)
	update_stats_panel()
	update_inventory_panel()

func get_player():
	var players = get_tree().get_nodes_in_group("player")
	return players[0] if players.size() > 0 else null

# --- Inventory Panel Update ---
func update_inventory_panel():
	var player = get_player()
	if not player:
		return
	var inv_screen = _get_inventory_screen()
	if inv_screen:
		inv_screen.get_node("GoldLabel").text = "Gold: " + str(player.gold)
		inv_screen.get_node("LusionsLabel").text = "Elusions: " + str(player.lusions)
		if inv_screen.has_method("setup_for_player"):
			inv_screen.call("setup_for_player", player, CharacterData.active_character_index)

# --- Stats Panel Update ---
func update_stats_panel():
	var player = get_player()
	if not player:
		return
	var stats = _get_panelcontainer().get_node("Stats")
	if stats and player.has_method("update_stats_labels"):
		player.update_stats_labels(stats)

# --- Button Signal Handlers (all toggle mode) ---
func _on_InventoryButton_pressed():
	toggle_panel("InventoryScreen")
	if _get_panelcontainer().visible and _get_inventory_screen().visible:
		update_inventory_panel()

func _on_StatsButton_pressed():
	toggle_panel("Stats")
	if _get_panelcontainer().visible and _get_panelcontainer().get_node("Stats").visible:
		update_stats_panel()

func _on_ShopButton_pressed():
	toggle_panel("ShopScreen")

func _on_MapButton_pressed():
	toggle_panel("MapScreen")

func _on_OptionsButton_pressed():
	toggle_panel("OptionsScreen")

func _on_DiscordButton_pressed():
	OS.shell_open("https://discord.gg/4PEhh4Uu")

func _on_LogoutButton_pressed():
	if current_player and current_player.is_inside_tree():
		current_player.queue_free()
		current_player = null
	get_tree().quit()

# --- Node Ready Setup ---
func _ready():
	var container = _get_panelcontainer()
	container.visible = false
	for child in container.get_children():
		child.visible = false
	var vbox = _get_vbox()
	vbox.visible = false
	for node in vbox.get_children():
		node.visible = false
	spawn_player_from_selection()
