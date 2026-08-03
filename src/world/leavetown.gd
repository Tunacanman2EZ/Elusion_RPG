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
			push_warning("LeaveTown: destination_scene not assigned in the Inspector")
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
	# reference it. modulate on the Area2D root fades any child visual
	# (the gate sprite) along with it, since CanvasItem modulate is
	# inherited by children by default.
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 1.0)
	tween.tween_callback(_disable_after_vanish)


func _disable_after_vanish() -> void:
	can_teleport = false        # belt-and-suspenders against any further use
	set_deferred("monitoring", false)  # stop detecting body entry/exit entirely
