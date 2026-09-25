# autoload global game state — transient, in-memory values that have to survive
# a scene change and must NOT survive a restart.
#
# Everything here is deliberately unsaved. Each one is a handshake between two
# parts of the game that cannot see each other: a scene being left and the scene
# being entered, or a Control that consumed an event and a character that reads
# the hardware directly. Persistent state belongs in CharacterData, which goes
# through the server.
#
# WHAT LEFT THIS FILE, so the next person looking for it knows where it went:
#
#   Thirteen signals — a designed event bus for multiplayer, carrying instance
#   ids so events could later route to the right peer. Nothing ever connected to
#   one. The relays that fed them were removed first (elusion.gd, field.gd and
#   boss.gd each carried an identical ~35-line _wire_player_signals(), and
#   player_moved alone cost 180 emissions a second arriving nowhere); the
#   declarations followed once it was clear the interface would be designed
#   against a real feature rather than ahead of one. Recoverable from git if
#   multiplayer ever wants a starting point, but a bus built to fit whatever
#   actually needs it will fit better than one built to fit nothing.
#
#   Element.Type and get_element_name() — now src/shared/element.gd, as
#   `Element.Type` and `Element.name_for()`. They were unreachable here: an
#   autoload cannot carry a class_name (it would collide with the autoload's own
#   name), and without one `GameState.Element` cannot be written in a type
#   position — not as an @export on a Resource, not as a parameter type. So the
#   enum could only be compared as a bare int, which is why it went ten thousand
#   lines without a reference. Element also carries each element's colour, which
#   is what makes it worth reaching for: EnemyData.element and EnemyData.body_tint
#   are authored from it, so a palette-swap variant is a .tres rather than a pile
#   of modulates stacked on nodes.
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
# SCENE ARRIVAL
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
