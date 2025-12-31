extends Node2D

# --- Variables ---
var current_player: Node = null

const InventoryPersist = preload("res://inventory/InventoryPersistence.gd")

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
	# Load or create the player's persistent bag inventory for this character slot.
	if "inventory" in player:
		player.inventory = InventoryPersist.load_or_create_bag(slot_idx)

func wait_for_player():
	while get_player() == null:
		await get_tree().create_timer(0.01).timeout

func get_player():
	var players = get_tree().get_nodes_in_group("player")
	return players[0] if players.size() > 0 else null

func _get_inventory_screen():
	var inventory_ui = get_node_or_null("MenuScreen/InventoryUI")
	if not inventory_ui:
		return null
	var panel = inventory_ui.get_node_or_null("PanelContainer")
	if not panel:
		return null
	var vbox = panel.get_node_or_null("VBoxContainer")
	if not vbox:
		return null

	var screen = vbox.get_node_or_null("InventoryScreen")
	if screen != null:
		return screen

	# Replace the legacy slot grid with our new InventoryScreen at runtime.
	var legacy_grid := vbox.get_node_or_null("GridContainer")
	if legacy_grid:
		legacy_grid.visible = false

	var screen_scene := preload("res://inventory/ui/InventoryScreen.tscn")
	screen = screen_scene.instantiate()
	screen.name = "InventoryScreen"
	vbox.add_child(screen)
	if legacy_grid:
		vbox.move_child(screen, legacy_grid.get_index())
	return screen

# --- Inventory Helpers ---
func update_inventory_panel():
	var player = get_player()
	if not player:
		return

	# Update currency labels
	var inventory_ui = get_node("MenuScreen/InventoryUI")
	var panel = inventory_ui.get_node("PanelContainer")
	var vbox = panel.get_node("VBoxContainer")
	vbox.get_node("GoldLabel").text = "Gold: " + str(player.gold)
	vbox.get_node("LusionsLabel").text = "Elusions: " + str(player.lusions)

	var screen: Node = _get_inventory_screen()
	if screen != null and screen.has_method("setup_for_player"):
		screen.call("setup_for_player", player, CharacterData.active_character_index)

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
