extends Node2D

func spawn_player_from_selection():
	print("spawn_player_from_selection() called.")

	var slot_idx = CharacterData.active_character_index
	print("slot_idx =", slot_idx)

	var scenes = [
		preload("res://scenes/Warrior.tscn"),
		preload("res://scenes/Mage.tscn"),
		preload("res://scenes/Tank.tscn"),
		preload("res://scenes/Healer.tscn")
	]
	print("Available scenes count:", scenes.size())

	if slot_idx < 0 or slot_idx >= scenes.size():
		push_error("No valid character slot selected for spawning! Index: %d" % slot_idx)
		return

	var scene = scenes[slot_idx]
	print("About to instance player from:", scene)

	var player = scene.instantiate()
	if not player:
		push_error("Player scene failed to instance!")
		return

	print("Instanced player:", player)

	var children_names = []
	for child in get_children():
		children_names.append(child.name)
	print("Current children of root node:", children_names)

	var spawn = get_node_or_null("PlayerSpawn")
	if not spawn:
		push_error("PlayerSpawn node not found! Children are: %s" % str(children_names))
		return

	print("PlayerSpawn position:", spawn.global_position)
	player.global_position = spawn.global_position
	add_child(player)
	print("Player added to scene at position:", player.global_position)

# --- Wait for player node to appear (optional utility) ---
func wait_for_player():
	while get_player() == null:
		await get_tree().create_timer(0.01).timeout

func get_player():
	var players = get_tree().get_nodes_in_group("player")
	return players[0] if players.size() > 0 else null

func get_inventory_ui():
	var canvas = get_node_or_null("CanvasLayer")
	if canvas and canvas.has_node("InventoryUI"):
		return canvas.get_node("InventoryUI")
	return null

func _ready():
	print("GETTING CanvasLayer:")
	var canvas = get_node_or_null("CanvasLayer")
	print("CanvasLayer is: ", canvas)
	if canvas:
		var child_names = []
		for c in canvas.get_children():
			child_names.append(c.name)
		print("CanvasLayer children: ", child_names)
		if canvas.has_node("InventoryUI"):
			print("InventoryUI found: ", canvas.get_node("InventoryUI"))
		else:
			print("InventoryUI NOT found!")
	else:
		print("No CanvasLayer node found!")

	var inv_ui = get_inventory_ui()
	if inv_ui:
		inv_ui.visible = false
	else:
		push_error("InventoryUI not found!")
		
func update_inventory_panel():
	var player = get_player()
	if not player:
		push_error("Player node not found for update_inventory_panel!")
		return
	var inv_ui = get_inventory_ui()
	if not inv_ui:
		push_error("InventoryUI not found!")
		return

	# TODO: Add UI update logic when you build out the inventory panel.

func _on_DiscordButton_pressed():
	OS.shell_open("https://discord.gg/4PEhh4Uu")

func _on_LogoutButton_pressed():
	get_tree().quit()

func _on_InventoryButton_pressed():
	var inv_ui = get_inventory_ui()
	if not inv_ui:
		push_error("InventoryUI not found!")
		return
	inv_ui.visible = not inv_ui.visible
	if inv_ui.visible:
		update_inventory_panel()
