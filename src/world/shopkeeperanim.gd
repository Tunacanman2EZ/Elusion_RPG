# shopkeeperanim.gd — the shopkeeper greets you once when you walk up, then goes
# back to standing there breathing. A wave is a GREETING, not a state.
#
# WHY THIS IS A SEPARATE SCRIPT AND NOT PART OF vendor.gd. vendor.gd's own
# header calls the vendor "bankchest.gd WITHOUT the animation" — it deliberately
# owns none, because no animation is allowed to gate when the shop panel opens.
# This is the opposite concern: purely cosmetic, and it must never be able to
# change whether or when the panel opens. So it lives on the sprite, only
# listens to the vendor's proximity area, and touches nothing but its own
# playback. vendor.gd stays exactly as written.
#
# WHAT THIS USED TO BE, AND WHY THE OLD COMMENT WAS FALSE ABOUT THE ART:
#
#     const WAVE_ANIM := &"wavedown"    # loop = true in the scene
#     _on_body_entered:  play(WAVE_ANIM)
#     _on_body_exited:   stop(); frame = 0
#
# and above it, in capitals, "THE STILL FRAME IS FRAME 0 OF THE WAVE ... we
# never need a second, one-frame idle animation."
#
# THAT WAS TRUE OF THE DESIGN AND NOT OF THE SHEET. The ten frames actually
# shipped in art/npc/shopkeeper.png started mid-wave: frame 0 was the arm fully
# extended, hand out. So the "still figure" the header promised was a man
# frozen with his arm in the air, and the wave itself had no rest pose to
# return to — it could only ever loop, because looping was the only state the
# frames could express. The comment described what somebody meant; nothing
# checked it against the pixels, and a comment cannot fail.
#
# The artist's full set fixes it at the source. There is a real seven-frame
# idle now (a blink), and the wave is eleven frames that BEGIN at rest, raise,
# wave four times and lower. So:
#
#   - the wave does not loop; it plays once per arrival, which is what a
#     greeting is
#   - when it ends we return to the idle, we do NOT stop on the last frame.
#     The wave's last frame is the arm still up at the shoulder — the artist
#     ended it mid-lower so it can be cut back to idle cleanly. Stopping there
#     would reintroduce exactly the frozen-arm bug in a new place.
#   - leaving does nothing at all. The wave is already finite, so cutting it
#     short on exit only means a player who steps back gets half a greeting.
#
# It reuses the vendor's own Area2D rather than adding a second detector, so the
# wave begins exactly when the player is close enough to trade — which is what
# makes "come to my shop" read correctly instead of waving at an empty room.
extends AnimatedSprite2D


# Named with a direction suffix per the project's animation convention (the
# shopkeeper only ever faces the counter, i.e. down). Note the two vocabularies:
# animations end up/down/left/right, Marker2D nodes end top/bottom/left/right.
const IDLE_ANIM := &"idledown"
const WAVE_ANIM := &"wavedown"


func _ready() -> void:
	# Belt and suspenders. Whatever the .tscn was saved mid-doing, we begin on
	# the idle — the resting state should not depend on how the scene happened
	# to be saved. A missing animation is a warning rather than a crash, because
	# this is decoration and decoration must never take the shop down with it.
	if sprite_frames == null:
		push_warning("shopkeeperanim: no SpriteFrames — nothing to play")
	else:
		for required in [IDLE_ANIM, WAVE_ANIM]:
			if not sprite_frames.has_animation(required):
				push_warning("shopkeeperanim: missing animation '%s'" % required)

	_play_idle()

	# The wave is finite, so it ENDS, and that signal is the whole mechanism for
	# getting back to the idle. It never fires for the idle itself, which loops.
	if not animation_finished.is_connected(_on_animation_finished):
		animation_finished.connect(_on_animation_finished)

	# The proximity area is the vendor Area2D this sprite hangs under. Connecting
	# here (in code) matches how vendor.gd wires its own copy of these signals,
	# and multiple connections to one signal fire independently — ours drives
	# the wave, its drives the shop. Neither knows about the other.
	var area := get_parent()
	if area is Area2D:
		area.body_entered.connect(_on_body_entered)
	else:
		push_warning("shopkeeperanim: parent is not an Area2D — nothing to wave at")


func _on_body_entered(body: Node) -> void:
	# ONE GREETING PER ARRIVAL. play() from the top restarts the wave even if one
	# is already running, which is right: walking out and straight back in is a
	# new arrival and deserves a new wave.
	if _is_player(body) and sprite_frames != null \
			and sprite_frames.has_animation(WAVE_ANIM):
		play(WAVE_ANIM)


func _on_animation_finished() -> void:
	# ONLY the wave. Asking which animation ended rather than assuming, so that
	# adding a second non-looping animation later cannot silently be swallowed
	# by this handler.
	if animation == WAVE_ANIM:
		_play_idle()


func _play_idle() -> void:
	if sprite_frames != null and sprite_frames.has_animation(IDLE_ANIM):
		play(IDLE_ANIM)
	else:
		# No idle to fall back to. Stopping is better than leaving the wave's
		# last frame on screen, which is the arm half-raised.
		stop()
		frame = 0


# Same test vendor.gd uses, kept identical on purpose: match the player whether
# it is found by node name or by group, so a rename of one never silently stops
# the wave while the shop still opens (or the reverse).
func _is_player(body: Node) -> bool:
	return body != null and (body.name == "Player" or body.is_in_group("player"))
