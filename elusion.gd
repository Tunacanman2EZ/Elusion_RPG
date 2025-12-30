extends Node2D

# --- Variables ---
var current_player: Node = null

# --- Player Management ---
func spawn_player_from_selection():
	var slot_idx = CharacterData.active_character_index
	var scenes = [
		preload("res://scenes/Warrior.tscn"),
		preload("res://scenes/Mage.tscn"),
		preload("res://scenes/Tank.tscn"),
		preload("res://scenes/Healer.tscn")
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

func wait_for_player():
	while get_player() == null:
		await get_tree().create_timer(0.01).timeout

func get_player():
	var players = get_tree().get_nodes_in_group("player")
	return players[0] if players.size() > 0 else null

# --- Inventory Helpers ---
func get_inventory_grid():
	var inventory_ui = get_node_or_null("MenuScreen/InventoryUI")
	if not inventory_ui:
		return null
	var panel = inventory_ui.get_node_or_null("PanelContainer")
	if not panel:
		return null
	var vbox = panel.get_node_or_null("VBoxContainer")
	if not vbox:
		return null
	var grid_container = vbox.get_node_or_null("GridContainer")
	if not grid_container:
		return null
	return grid_container

func update_inventory_panel():
	var inventory_grid = get_inventory_grid()
	if not inventory_grid:
		return

	var player = get_player()
	if not player:
		return

	# Update currency labels
	var inventory_ui = get_node("MenuScreen/InventoryUI")
	var panel = inventory_ui.get_node("PanelContainer")
	var vbox = panel.get_node("VBoxContainer")
	vbox.get_node("GoldLabel").text = "Gold: " + str(player.gold)
	vbox.get_node("LusionsLabel").text = "Elusions: " + str(player.lusions)

	# Fill the grid slots (blank unless item present)
	for child in inventory_grid.get_children():
		child.queue_free()
	for i in range(20):
		var slot = TextureButton.new()
		slot.custom_minimum_size = Vector2(64, 64)
		# To display an item, you can check your inventory array here in the future
		inventory_grid.add_child(slot)

# --- Button Signal Handlers ---
func _on_InventoryButton_pressed():
	var inventory_ui = get_node("MenuScreen/InventoryUI")
	var panel = inventory_ui.get_node("PanelContainer")
	panel.visible = not panel.visible
	if panel.visible:
		update_inventory_panel()

func _on_DiscordButton_pressed():
	OS.shell_open("https://discord.gg/4PEhh4Uu")

func _on_LogoutButton_pressed():
	if current_player and current_player.is_inside_tree():
		current_player.queue_free()
		current_player = null
	get_tree().quit()

func _on_StatsButton_pressed() -> void:
	pass # TODO: Implement

func _on_ShopButton_pressed() -> void:
	pass # TODO: Implement

func _on_MapButton_pressed() -> void:
	pass # TODO: Implement

func _on_OptionsButton_pressed() -> void:
	pass # TODO: Implement

# --- Node Ready Setup ---
func _ready():
	var inventory_ui = get_node("MenuScreen/InventoryUI")
	var panel = inventory_ui.get_node("PanelContainer")
	panel.visible = false
	spawn_player_from_selection()
