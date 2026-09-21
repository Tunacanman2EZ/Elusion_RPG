# leavetown.gd — teleport trigger that changes to a DIFFERENT SCENE
# entirely, rather than moving the player's position within the current
# scene (see teleportnextarea.gd's script for that simpler in-scene
# version — this mirrors its structure and conventions on purpose).
#
# CHANGED: no longer plays a story sequence here — that moved to
# storyscreen.gd, triggered on field.tscn's own arrival instead of during
# the portal crossing. this is back to its original, simple job: fade to
# black, swap scenes, fade back in.
#
# NEW: optional "vanish after first use" behavior (see
# vanish_after_first_use below) — OFF by default, so the original
# town-side leavetown portal is completely unaffected and stays normally
# reusable. built for fieldteleport specifically: the arrival point in
# the field, where the player first appears coming from town. once they
# walk away from it, the portal fades out and becomes permanently unusable
# for this scene visit — no instantly retreating back to town the moment
# something scary shows up. ties directly into the story text's own
# "life is a gamble" tone.
#
# uses the SceneTransition autoload to fade to black before swapping
# scenes and fade back in after, instead of an abrupt cut.
extends Area2D

# assign in the Inspector — the scene to transition to.
@export var destination_scene: PackedScene

# NEW: opt-in, OFF by default. only enable this on portals meant to be a
# one-time arrival point (e.g. fieldteleport) — never on a portal players
# are expected to use repeatedly.
@export var vanish_after_first_use: bool = false

# WHAT TO FADE, when the portal vanishes. Empty means this node, which fades
# its own children with it.
#
# THIS EXISTS BECAUSE THE OBVIOUS ASSUMPTION WAS WRONG, silently, for as long
# as the feature has been in. _vanish() tweens modulate and its comment said
# that carried "the gate sprite" along, because CanvasItem modulate is
# inherited by children. It is - but field.tscn's portal sprite is not a child.
# The trigger lives at ysortworld/interactables/fieldteleport and the animated
# portal at ysortworld/props/teleport: siblings in different branches, so that
# Area2D has no visual under it at all. The fade ran correctly on every arrival
# and there was nothing beneath it to fade, which is why the portal never went
# away and nothing anywhere reported a problem.
#
# AN EXPORTED PATH RATHER THAN REPARENTING THE SPRITE. Moving it under the
# trigger would make the code work untouched, but it also moves it between
# y-sort branches and multiplies its scale by the trigger's own 1.5 - a visual
# change to fix an invisible one. Naming the target makes the coupling explicit
# instead of resting on a tree shape somebody can break by dragging a node.
@export var visual: NodePath

# This trigger is a DOOR IN, not a way out: it exists to be landed on and then
# to fade, and it is supposed to have no destination_scene.
#
# WHY IT NEEDS SAYING. field.tscn's fieldteleport is exactly that. The player
# arrives from town standing inside it, which fires _on_body_entered on the
# first frame they exist — so the null-destination warning below went off on
# every single trip into the field, naming a node that was configured
# correctly. A warning that cries wolf on a working scene is worse than no
# warning, because it trains you to scroll past the ones that matter.
#
# It is also the only thing keeping that portal from looping: elusion.tscn's
# leavetown sends the player to "field_entrance", which is this node's own
# arrival marker. Give it a destination back to town and arriving in the field
# would immediately bounce the player back, forever.
#
# Left FALSE, an unassigned destination_scene still warns, because on any
# portal that is a real misconfiguration.
@export var arrival_only: bool = false

# NEW: if set, stored on GameState right before transitioning, so the
# destination scene knows which of its (possibly multiple) named arrival
# points — see fieldportal.gd — to place the player at. leave empty to
# fall back to the destination scene's own default player placement,
# which is what every other portal using this script keeps doing.
@export var target_spawn_id: String = ""

var can_teleport := true
var _has_vanished := false

func _on_body_entered(body):
	if body and can_teleport and (body.name == "Player" or body.is_in_group("player")):
		can_teleport = false
		if destination_scene == null:
			# Silent for an arrival-only trigger — that one has no destination
			# BY DESIGN, see arrival_only above. Still warns on every other
			# portal, where an unset destination really is a broken exit.
			if not arrival_only:
				push_warning("LeaveTown (%s): destination_scene not assigned in the Inspector" % name)
			return
		if target_spawn_id != "":
			GameState.next_spawn_id = target_spawn_id
		SceneTransition.change_scene(destination_scene)

func _on_body_exited(body):
	if body and (body.name == "Player" or body.is_in_group("player")):
		can_teleport = true
		# NEW: independent of the teleport logic above — this just
		# watches for "the player walked away from this portal for the
		# first time" and reacts to that, regardless of whether they
		# actually triggered a teleport through it.
		if vanish_after_first_use and not _has_vanished:
			_has_vanished = true
			_vanish()


# =============================================================================
# VANISH  (NEW)
# =============================================================================

func _vanish() -> void:
	# fades out visually, then disables interaction entirely. doesn't
	# free/delete the node — keeps it (now invisible, inert) in the tree
	# rather than removing it outright, in case anything ever needs to
	# reference it.
	var target: CanvasItem = _visual_target()
	var tween := create_tween()
	tween.tween_property(target, "modulate:a", 0.0, 1.0)
	tween.tween_callback(_disable_after_vanish)


func _visual_target() -> CanvasItem:
	# Falls back to self, so a portal whose sprite really is a child keeps
	# working with nothing set — and so a path that has gone stale fades
	# something rather than throwing on a null.
	if visual.is_empty():
		return self

	var node: Node = get_node_or_null(visual)
	if node is CanvasItem:
		return node

	# LOUD, because the symptom otherwise is a portal that quietly stays put
	# and a player who thinks the level is broken. That is exactly the failure
	# this export was added to end, and a typo in the path would reproduce it
	# perfectly.
	push_warning("leavetown (%s): visual path '%s' is not a CanvasItem — fading the trigger instead, which may have nothing under it" % [name, visual])
	return self


func _disable_after_vanish() -> void:
	can_teleport = false        # belt-and-suspenders against any further use
	set_deferred("monitoring", false)  # stop detecting body entry/exit entirely


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
	# NO PIN FOR A DOOR THAT IS NOT A WAY OUT. The field's copy of this script
	# is arrival-only and vanishes after first use - it is where you land from
	# town, not a route back - and a pin on it would advertise an exit that
	# does not exist.
	if arrival_only or _has_vanished:
		return {}
	var where: String = "Exit"
	if destination_scene != null and destination_scene.resource_path != "":
		where = "To " + destination_scene.resource_path.get_file().get_basename().capitalize()
	return {"kind": "exit", "label": where}
