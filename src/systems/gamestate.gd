# autoload global game state — persists across all scenes
# contains multiplayer-ready signals and shared game data
extends Node

# --- multiplayer ready signals ---
# these signals are emitted by game systems and will be forwarded
# to the server when multiplayer is implemented in phase 3

# emitted every time the player moves — sends position and direction
signal player_moved(player_id: int, position: Vector2, direction: String)

# emitted when any damage is dealt — source, target, amount, and type
signal damage_dealt(source_id: int, target_id: int, amount: int, type: String)

# emitted when a player dies — used to trigger death handling server side
signal player_died(player_id: int)

# emitted when an enemy dies — tracks who killed it for xp and loot
signal enemy_died(enemy_id: int, killer_id: int)

# emitted when a player gains xp — server validates and updates leaderboard
signal xp_gained(player_id: int, amount: int)

# emitted when a player's gold amount changes
signal gold_changed(player_id: int, amount: int)

# emitted when a player picks up an item from the world
signal item_picked_up(player_id: int, item_id: String)

# emitted when a player uses an item from their inventory
signal item_used(player_id: int, item_id: String)

# emitted when a player activates a skill from the hotbar
signal skill_used(player_id: int, skill_id: String, target_pos: Vector2)

# emitted when the tank's aura deals damage to a nearby enemy
signal aura_damage_dealt(tank_id: int, enemy_id: int, amount: int)

# emitted when the tank activates their taunt skill
signal taunt_activated(tank_id: int, duration: float)

# emitted when a player deposits an item into the bank chest
signal bank_deposited(player_id: int, item_id: String, amount: int)

# emitted when a player withdraws an item from the bank chest
signal bank_withdrawn(player_id: int, item_id: String, amount: int)

# --- global state ---

# tracks the player's last known world position — used by multiplayer sync
var player_position := Vector2()

# stores the logged in username — set after Firebase auth in phase 2
var logged_in_username := ""

# --- element types ---

# enum of all elemental damage types used in combat and dungeons
enum Element {
	NONE,   # no element — physical damage
	DARK,   # dark element
	LIGHT,  # light element
	ICE,    # ice element
	WIND,   # wind element
	EARTH,  # earth element
	FIRE,   # fire element
	WATER   # water element
}

func get_element_name(element) -> String:
	# converts an Element enum value to a readable string
	match element:
		1: return "dark"
		2: return "light"
		3: return "ice"
		4: return "wind"
		5: return "earth"
		6: return "fire"
		7: return "water"
		_: return "none"  # default — covers NONE and any invalid values
