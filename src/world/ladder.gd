# ladder.gd — teleport trigger that changes to a different scene, for the
# field <-> boss ladder pair specifically. same core teleport pattern as
# leavetown.gd (fade out, swap scenes, fade back in via the SceneTransition
# autoload), but as its own dedicated script rather than reusing that one —
# clearer at a glance what this node actually is, and skips
# leavetown.gd's vanish-after-first-use feature entirely, since that was
# built for a deliberately one-way portal (fieldteleport) and doesn't apply
# here — a ladder should stay usable in both directions indefinitely.
#
# uses the SAME target_spawn_id + FieldPortal pairing pattern already
# proven for field/leavetown: set target_spawn_id here to the portal_id of
# a FieldPortal marker in the DESTINATION scene, so the player lands at a
# specific spot instead of wherever that scene's player node happens to be
# placed by default.
extends Area2D
 
 
# =============================================================================
# EXPORTED SETTINGS
# =============================================================================
 
# assign in the Inspector — path to the scene this ladder leads to.
# a PATH (String) on purpose, NOT a PackedScene ext_resource: a ladder pair
# (e.g. field <-> boss) has each side pointing at the other, and Godot
# can't resolve two .tscn files that eagerly ext_resource each other —
# that's a circular resource load and it fails to parse. loading by path
# at teleport time (see load() below) sidesteps that entirely.
@export_file("*.tscn") var destination_scene_path: String = ""
 
# if set, stored on GameState right before transitioning, so the
# destination scene knows which FieldPortal marker to place the player at.
# leave empty to fall back to that scene's own default player placement.
@export var target_spawn_id: String = ""
 
 
# =============================================================================
# STATE
# =============================================================================
 
var can_teleport := true
 
 
# =============================================================================
# COLLISION HANDLERS
# =============================================================================
 
func _on_body_entered(body):
	if body and can_teleport and (body.name == "Player" or body.is_in_group("player")):
		can_teleport = false
		if destination_scene_path == "":
			push_warning("Ladder (%s): destination_scene_path not assigned in the Inspector" % name)
			return
		var destination_scene: PackedScene = load(destination_scene_path)
		if destination_scene == null:
			push_warning("Ladder (%s): failed to load scene at %s" % [name, destination_scene_path])
			return
		if target_spawn_id != "":
			GameState.next_spawn_id = target_spawn_id

		# Below the two failure returns above, so a ladder with a missing or
		# unloadable destination stays silent instead of promising a trip it
		# cannot make. Through the autoload rather than a player on this node,
		# which is about to be freed by the scene change.
		Audio.play("door")

		SceneTransition.change_scene(destination_scene)
 
 
func _on_body_exited(body):
	if body and (body.name == "Player" or body.is_in_group("player")):
		can_teleport = true


# =============================================================================
# ON THE MAP
# =============================================================================
# mapscreen.gd draws a pin for everything in "map_landmarks" and asks each one
# what it is. Joined in _init rather than _ready so it does not depend on this
# script having a _ready, or on anything a _ready returns early for - and so
# the pin exists from the moment the node does.

func _init() -> void:
	add_to_group("map_landmarks")

func map_landmark() -> Dictionary:
	var where: String = "Ladder"
	if destination_scene_path != "":
		where = "Ladder to " + destination_scene_path.get_file().get_basename().capitalize()
	return {"kind": "ladder", "label": where}
