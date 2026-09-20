# autoload global game state — persists across all scenes. Shared-state
# container, and the declared contract for a game-wide event bus.
#
# READ THIS BEFORE TRUSTING THE SIGNALS BELOW.
#
# NOTHING IN THE GAME CONNECTS TO ANY OF THEM. Not one. They are a designed
# interface for multiplayer that has not been built yet, deliberately kept, and
# they are documented as such rather than left to look finished.
#
# The signals carry instance_id parameters (player_id, enemy_id, ...) so that
# when multiplayer arrives the same events can forward across the network
# without restructuring callers. Single-player would use self-IDs; multiplayer
# routes IDs to the right peer. That design still holds — it is just unbuilt.
#
# WHAT WAS REMOVED, AND WHY
#
# elusion.gd, field.gd and boss.gd each carried an identical ~35-line
# _wire_player_signals() that bridged the player's own signals onto these ones.
# Roughly 105 lines of relay, feeding an empty bus.
#
# The cost was not theoretical. player.gd emits `moved` on every physics frame
# it is walking, so at 180 ticks/second player_moved meant 180 lambda
# dispatches and 180 three-argument emissions a second, arriving nowhere.
# A declared signal nobody emits costs nothing; an emitted signal nobody hears
# costs CPU AND reads as working code. So the declarations stayed and the
# relays went.
#
# TO WIRE IT BACK, in the world script that owns the player:
#
#     current_player.took_damage.connect(func(amount, type):
#         GameState.damage_dealt.emit(0, current_player.get_instance_id(),
#                                     amount, type))
#
# ...and the same shape for died -> player_died, xp_gained_signal -> xp_gained,
# gold_changed_signal -> gold_changed, moved -> player_moved. Add the relay in
# ONE place this time, not once per world scene, and only for the events
# something is actually listening for.
#
# ABOUT THE @warning_ignore LINES
#
# Every declaration below carries @warning_ignore("unused_signal"). Godot is
# correct that they are unused - that is the whole point of this file's
# comment, and the warning is not being hidden because it is wrong. It is
# annotated per-signal rather than switched off project-wide so that an
# unused signal ANYWHERE ELSE in the codebase still warns loudly. These
# thirteen are the known, deliberate exceptions; nothing else gets a pass.
#
# When you wire one up for real, delete its annotation. If the warning does
# not come back, the signal still is not reaching anything.
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
@warning_ignore("unused_signal")
signal player_moved(player_id: int, position: Vector2, direction: String)

# emitted when any damage is dealt — source, target, amount, and type
@warning_ignore("unused_signal")
signal damage_dealt(source_id: int, target_id: int, amount: int, type: String)

# emitted when a player dies — used to trigger death handling server-side
@warning_ignore("unused_signal")
signal player_died(player_id: int)

# emitted when an enemy dies — tracks who killed it for XP and loot
@warning_ignore("unused_signal")
signal enemy_died(enemy_id: int, killer_id: int)


# =============================================================================
# PROGRESSION SIGNALS
# =============================================================================

# emitted when a player gains XP — server validates and updates leaderboard
@warning_ignore("unused_signal")
signal xp_gained(player_id: int, amount: int)

# emitted when a player's gold amount changes
@warning_ignore("unused_signal")
signal gold_changed(player_id: int, amount: int)


# =============================================================================
# INVENTORY AND ITEMS
# =============================================================================

# emitted when a player picks up an item from the world
@warning_ignore("unused_signal")
signal item_picked_up(player_id: int, item_id: String)

# emitted when a player uses an item from their inventory
@warning_ignore("unused_signal")
signal item_used(player_id: int, item_id: String)

# emitted when a player activates a skill from the hotbar
@warning_ignore("unused_signal")
signal skill_used(player_id: int, skill_id: String, target_pos: Vector2)


# =============================================================================
# TANK-SPECIFIC SIGNALS
# =============================================================================

# emitted when the tank's aura deals damage to a nearby enemy
@warning_ignore("unused_signal")
signal aura_damage_dealt(tank_id: int, enemy_id: int, amount: int)

# emitted when the tank activates their taunt skill (phase 2 ability)
@warning_ignore("unused_signal")
signal taunt_activated(tank_id: int, duration: float)


# =============================================================================
# BANK SIGNALS
# =============================================================================

# emitted when a player deposits an item into the bank chest
@warning_ignore("unused_signal")
signal bank_deposited(player_id: int, item_id: String, amount: int)

# emitted when a player withdraws an item from the bank chest
@warning_ignore("unused_signal")
signal bank_withdrawn(player_id: int, item_id: String, amount: int)


# =============================================================================
# ELEMENT TYPES  (MOVED)
# =============================================================================
# The enum and get_element_name() that used to live here are now in
# src/shared/element.gd, as `Element.Type` and `Element.name_for()`.
#
# THEY WERE UNREACHABLE HERE. This file is an autoload with no class_name — it
# cannot have one, because that would collide with the autoload's own name —
# and without a class_name `GameState.Element` cannot be written in a type
# position. Not as an @export on a Resource, not as a parameter type. So the
# enum could only ever be compared against as a bare int, which is why it went
# ten thousand lines without a single reference.
#
# Element also carries each element's COLOUR, which is what makes the enum
# worth reaching for: EnemyData.element and EnemyData.body_tint are authored
# from it, and a palette-swap variant is then a .tres rather than a pile of
# modulates stacked on nodes.
