# autoload global game state — persists across all scenes.
# this is the central signal bus and shared-state container for the game.
# any system that needs to react to gameplay events subscribes to the
# signals here rather than coupling directly to the emitter.
#
# multiplayer-ready architecture:
# the signals below carry instance_id parameters (player_id, enemy_id, etc.)
# so when multiplayer is added in phase 3, the same signals forward across
# the network without restructuring callers. single-player today uses
# self-IDs only; multiplayer routes IDs to the right peer.
extends Node


# =============================================================================
# DEATH AND REVIVE STATE
# =============================================================================
# transient state used by the death/revive system. stored in memory only
# (no disk write) so force-quitting during the death sequence does NOT
# preserve a "frozen" state for exploit. on next login the player loads
# from their last legitimate save instead.

# packed character + death context (set by player._change_to_game_over).
# the gameover scene reads this to display info and route the revive choice.
var death_state: Dictionary = {}

# true between gameover screen and world scene reload when player chose to
# revive. the world scene checks this on load to teleport the player to
# death_state.death_position and skip default spawn behavior.
var reviving: bool = false


# =============================================================================
# SCENE ARRIVAL  (NEW)
# =============================================================================
# same transient, in-memory-only philosophy as death_state/reviving above —
# set by a portal/teleport trigger (see leavetown.gd's target_spawn_id)
# just before changing scenes, so the new scene knows WHICH of its
# (possibly multiple) named arrival points to place the player at — see
# fieldportal.gd — instead of just wherever the player node happens to be
# manually placed in the new scene's file. empty string means "no specific
# arrival point requested," and the new scene falls back to its own
# default placement. the reading scene is responsible for clearing this
# back to "" once consumed, so it can't leak into a later, unrelated
# scene load that never intended to use it.
var next_spawn_id: String = ""


# =============================================================================
# GLOBAL STATE
# =============================================================================

# last known player world position — used by multiplayer sync.
# currently set passively by player_moved signal listeners.
var player_position: Vector2 = Vector2()

# logged-in username — populated after Firebase auth in phase 2.
# empty string means anonymous/offline mode.
var logged_in_username: String = ""

# true while a right-click that the UI already consumed is still held down.
#
# set by inventoryslot.gd when a slot handles a right-click; read by
# player.gd's right_click_attack_held(), which clears it the moment the
# button comes back up.
#
# WHY THIS HAS TO BE GLOBAL: accept_event() stops an event travelling through
# the scene tree, but the character classes read the mouse with
# Input.is_mouse_button_pressed(), which asks the hardware and knows nothing
# about what a Control consumed. So right-clicking a potion to drink it also
# swung the player's weapon. This flag is the handshake between the two.
#
# it lives here rather than as a static on player.gd because that needed a
# class_name, and a class_name only exists once Godot has rescanned the file —
# which is a bootstrapping problem the autoload simply doesn't have.
var ui_absorbed_right_click: bool = false


# =============================================================================
# MOVEMENT AND COMBAT SIGNALS
# =============================================================================

# emitted every time the player moves — sends position and direction
signal player_moved(player_id: int, position: Vector2, direction: String)

# emitted when any damage is dealt — source, target, amount, and type
signal damage_dealt(source_id: int, target_id: int, amount: int, type: String)

# emitted when a player dies — used to trigger death handling server-side
signal player_died(player_id: int)

# emitted when an enemy dies — tracks who killed it for XP and loot
signal enemy_died(enemy_id: int, killer_id: int)


# =============================================================================
# PROGRESSION SIGNALS
# =============================================================================

# emitted when a player gains XP — server validates and updates leaderboard
signal xp_gained(player_id: int, amount: int)

# emitted when a player's gold amount changes
signal gold_changed(player_id: int, amount: int)


# =============================================================================
# INVENTORY AND ITEMS
# =============================================================================

# emitted when a player picks up an item from the world
signal item_picked_up(player_id: int, item_id: String)

# emitted when a player uses an item from their inventory
signal item_used(player_id: int, item_id: String)

# emitted when a player activates a skill from the hotbar
signal skill_used(player_id: int, skill_id: String, target_pos: Vector2)


# =============================================================================
# TANK-SPECIFIC SIGNALS
# =============================================================================

# emitted when the tank's aura deals damage to a nearby enemy
signal aura_damage_dealt(tank_id: int, enemy_id: int, amount: int)

# emitted when the tank activates their taunt skill (phase 2 ability)
signal taunt_activated(tank_id: int, duration: float)


# =============================================================================
# BANK SIGNALS
# =============================================================================

# emitted when a player deposits an item into the bank chest
signal bank_deposited(player_id: int, item_id: String, amount: int)

# emitted when a player withdraws an item from the bank chest
signal bank_withdrawn(player_id: int, item_id: String, amount: int)


# =============================================================================
# ELEMENT TYPES
# =============================================================================

# enum of all elemental damage types used in combat and dungeons.
# NONE is index 0 for "no element / physical damage" — keep this as the
# default for any non-elemental hit.
enum Element {
	NONE,   # physical / no element
	DARK,
	LIGHT,
	ICE,
	WIND,
	EARTH,
	FIRE,
	WATER,
}


func get_element_name(element: int) -> String:
	# converts an Element enum value to a readable lowercase string.
	# used by UI, damage labels, and debug output. the default branch
	# catches both NONE and any invalid out-of-range value, returning
	# "none" so callers never get a crash from a bad enum.
	match element:
		Element.DARK:  return "dark"
		Element.LIGHT: return "light"
		Element.ICE:   return "ice"
		Element.WIND:  return "wind"
		Element.EARTH: return "earth"
		Element.FIRE:  return "fire"
		Element.WATER: return "water"
		_:             return "none"
