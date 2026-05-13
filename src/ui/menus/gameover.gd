# gameover.gd — displayed after the player's death animation finishes.
# offers a revive (costs lusions) or a return to character select.
# the player's death state is held in GameState.death_state (in-memory)
# and also persisted to disk in player.gd's _change_to_game_over.
extends Control

# the cost in lusions to revive from this screen
@export var revive_cost: int = 20

# the character select scene path — for "return" button
@export var character_select_path: String = "res://scene/ui/menus/characterselect.tscn"

# the world scene path — for "revive" button (returns to game)
@export var world_scene_path: String = "res://scene/elusion.tscn"

func _ready() -> void:
	_update_display()
	_wire_buttons()

func _wire_buttons() -> void:
	if has_node("%revivebutton"):
		var btn: Button = $"%revivebutton"
		if not btn.pressed.is_connected(_on_revive_pressed):
			btn.pressed.connect(_on_revive_pressed)
	if has_node("%returnbutton"):
		var btn: Button = $"%returnbutton"
		if not btn.pressed.is_connected(_on_return_pressed):
			btn.pressed.connect(_on_return_pressed)

func _update_display() -> void:
	var current_lusions: int = _get_current_lusions()

	if has_node("%lusionslabel"):
		$"%lusionslabel".text = "Lusions: %d" % current_lusions

	if has_node("%revivebutton"):
		var btn: Button = $"%revivebutton"
		btn.text = "Revive (%d Lusions)" % revive_cost
		btn.disabled = current_lusions < revive_cost

func _get_current_lusions() -> int:
	# read from the in-memory death snapshot first — that was captured at the
	# exact moment of death and is the most accurate value to display.
	# fall back to disk if death_state is empty (e.g., scene was loaded directly).
	var death_state: Dictionary = GameState.death_state
	if not death_state.is_empty() and death_state.has("lusions"):
		return int(death_state["lusions"])

	if death_state.is_empty():
		return 0
	var char_name: String = death_state.get("character_name", "")
	if char_name == "":
		return 0
	var slot_data: Dictionary = CharacterData.get_character_by_name(char_name)
	return int(slot_data.get("lusions", 0))

func _on_revive_pressed() -> void:
	# spend lusions, restore full HP, return to the world.
	# the lusions deduction is persisted immediately to disk so the player
	# can't dupe by reviving and then force-quitting before the next save.
	var death_state: Dictionary = GameState.death_state
	if death_state.is_empty():
		push_warning("gameover: no death_state to revive from")
		return

	var current_lusions: int = int(death_state.get("lusions", 0))
	if current_lusions < revive_cost:
		print("gameover: insufficient lusions for revive")
		return

	var char_name: String = death_state.get("character_name", "")
	var max_hp: int = int(death_state.get("max_hp", 100))

	# deduct in the in-memory state
	GameState.death_state["lusions"] = current_lusions - revive_cost

	# persist to disk — write back to the character slot so it survives force-quit
	var slot_data: Dictionary = CharacterData.get_character_by_name(char_name)
	if not slot_data.is_empty():
		slot_data["lusions"] = current_lusions - revive_cost
		slot_data["hp"] = max_hp
		CharacterData.save_character_slot(char_name, slot_data)

	# mark that we're returning from a revive — world scene will check this
	# on load to position the player at death_state.death_position
	GameState.reviving = true
	get_tree().change_scene_to_file(world_scene_path)

func _on_return_pressed() -> void:
	# accept the death — drop items (when implemented), clear state, go to select
	# TODO: implement item drop on map at death_state.death_position when ready
	GameState.death_state = {}
	GameState.reviving = false
	get_tree().change_scene_to_file(character_select_path)
