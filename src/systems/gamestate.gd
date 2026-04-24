extends Node

# --- global signals for multiplayer ready architecture ---
signal player_moved(player_id: int, position: Vector2, direction: String)
signal damage_dealt(source_id: int, target_id: int, amount: int, type: String)
signal player_died(player_id: int)
signal enemy_died(enemy_id: int, killer_id: int)
signal xp_gained(player_id: int, amount: int)
signal gold_changed(player_id: int, amount: int)
signal item_picked_up(player_id: int, item_id: String)
signal item_used(player_id: int, item_id: String)
signal skill_used(player_id: int, skill_id: String, target_pos: Vector2)
signal aura_damage_dealt(tank_id: int, enemy_id: int, amount: int)
signal taunt_activated(tank_id: int, duration: float)
signal bank_deposited(player_id: int, item_id: String, amount: int)
signal bank_withdrawn(player_id: int, item_id: String, amount: int)

# --- global state ---
var player_position := Vector2()
var logged_in_username := ""

# --- element types ---
enum Element {
	NONE, DARK, LIGHT, ICE, WIND, EARTH, FIRE, WATER
}

func get_element_name(element) -> String:
	match element:
		1: return "dark"
		2: return "light"
		3: return "ice"
		4: return "wind"
		5: return "earth"
		6: return "fire"
		7: return "water"
		_: return "none"
