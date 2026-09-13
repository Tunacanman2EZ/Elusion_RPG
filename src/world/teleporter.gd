extends Area2D

@onready var destination_point = $destinationpoint

# NEW: a real-time cooldown after teleporting, on top of the existing
# can_teleport/body_exited guard. WHY: if destination_point sits inside
# (or very close to) this same trigger's own collision shape, an instant
# position jump via global_position = ... doesn't behave like normal
# continuous movement — the physics engine can end up re-firing
# body_entered again immediately, even though the player never
# meaningfully "left." that produced a rapid loop (confirmed directly:
# the same exact coordinates printed to the console many times in a
# fraction of a second — the player being yanked back to the same spot
# faster than visibly perceptible, not "nothing happening").
#
# the cooldown timer is a robust fallback regardless of the exact
# mechanism causing that re-trigger — even if body_exited never correctly
# fires in the broken case, this guarantees teleporting can't fire again
# until real time has actually passed. body_exited is kept too, so the
# NORMAL case (player walks in, teleports, later genuinely walks away)
# still re-enables immediately rather than always waiting out the full
# cooldown unnecessarily.
#
# NOTE: this makes the script robust, but doesn't replace fixing the
# actual root cause — destination_point should still be moved clear of
# this trigger's own collision shape if it currently overlaps it.
@export var reenter_cooldown: float = 0.5

var can_teleport := true

func _on_body_entered(body):
	if body and can_teleport and (body.name == "Player" or body.is_in_group("player")):
		can_teleport = false
		body.global_position = destination_point.global_position

		# NEW: kills the visible smear across the map during a teleport.
		#
		# This project runs with common/physics_interpolation=true, so the
		# renderer draws every node blended between its PREVIOUS and CURRENT
		# physics transforms. That's what makes normal movement smooth at any
		# framerate — but a teleport isn't movement, it's a discontinuity.
		# Without being told that, the renderer dutifully interpolates the
		# player across the entire gap over one frame, which is exactly the
		# graphic jump you see at the moment of teleport.
		#
		# reset_physics_interpolation() collapses previous and current to the
		# same transform, so there is nothing left to blend. It MUST be called
		# AFTER the position is set, never before.
		#
		# It propagates to children, so the camera2d inside the player scene
		# is covered by this same call — without that the view would smear
		# even if the sprite itself didn't.
		body.reset_physics_interpolation()

		if OS.is_debug_build():
			print("[WORLD] teleported %s to %s" % [body.name, destination_point.global_position])
		_start_cooldown()

func _start_cooldown() -> void:
	await get_tree().create_timer(reenter_cooldown).timeout
	can_teleport = true

func _on_body_exited(body):
	if body and (body.name == "Player" or body.is_in_group("player")):
		can_teleport = true
