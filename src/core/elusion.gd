extends Node2D

var current_player: Node = null

@onready var active_char_ui = $hudcontrol

func _ready():
	print("ELUSION READY CALLED")
	spawn_player_from_selection()

func spawn_player_from_selection():
	var slot_idx = CharacterData.active_character_index
	var scenes = [
		preload("res://scene/characters/warrior.tscn"),
		preload("res://scene/characters/mage.tscn"),
		preload("res://scene/characters/tank.tscn"),
		preload("res://scene/characters/healer.tscn"),
	]
	if slot_idx < 0 or slot_idx >= scenes.size():
		push_error("no valid character slot selected! index: %d" % slot_idx)
		return
	if current_player and current_player.is_inside_tree():
		current_player.queue_free()
	var scene = scenes[slot_idx]
	var player = scene.instantiate()
	if not player:
		push_error("player scene failed to instance!")
		return
	var spawn = get_node_or_null("playerspawn")
	if not spawn:
		push_error("playerspawn node not found!")
		return
	player.global_position = spawn.global_position
	add_child(player)
	current_player = player
	CharacterData.load_character_state(current_player)

	current_player.took_damage.connect(func(amount, type):
		GameState.damage_dealt.emit(
			0,
			current_player.get_instance_id(),
			amount,
			type
		))
	current_player.died.connect(func():
		GameState.player_died.emit(current_player.get_instance_id()))
	current_player.xp_gained_signal.connect(func(amount):
		GameState.xp_gained.emit(current_player.get_instance_id(), amount))
	current_player.gold_changed_signal.connect(func(amount):
		GameState.gold_changed.emit(current_player.get_instance_id(), amount))
	current_player.moved.connect(func(pos, dir):
		GameState.player_moved.emit(
			current_player.get_instance_id(),
			pos,
			dir
		))

	if current_player == null:
		OS.alert("PLAYER IS NULL!")
		return

	if active_char_ui and active_char_ui.has_method("set_active_character"):
		OS.alert("CALLING SET ACTIVE CHARACTER")
		active_char_ui.set_active_character(current_player)

func _on_InventoryButton_pressed():
	if active_char_ui and active_char_ui.has_method("toggle_inventory"):
		active_char_ui.toggle_inventory()

func _on_StatsButton_pressed():
	if active_char_ui and active_char_ui.has_method("toggle_stats"):
		active_char_ui.toggle_stats()

func _on_ShopButton_pressed():
	pass

func _on_MapButton_pressed():
	pass

func _on_OptionsButton_pressed():
	pass

func _on_DiscordButton_pressed():
	OS.shell_open("https://discord.gg/4PEhh4Uu")

func _on_LogoutButton_pressed():
	if current_player and current_player.is_inside_tree():
		CharacterData.save_character_state(current_player)
		current_player.queue_free()
		current_player = null
	get_tree().change_scene_to_file("res://scene/menu/characterselect.tscn")
