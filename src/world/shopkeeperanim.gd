# shopkeeperanim.gd — the shopkeeper's idle: a still figure until you come
# close, a small looping wave while you're near, still again when you leave.
#
# WHY THIS IS A SEPARATE SCRIPT AND NOT PART OF vendor.gd. vendor.gd's own
# header calls the vendor "bankchest.gd WITHOUT the animation" — it deliberately
# owns none, because no animation is allowed to gate when the shop panel opens.
# This is the opposite concern: purely cosmetic, and it must never be able to
# change whether or when the panel opens. So it lives on the sprite, only
# listens to the vendor's proximity area, and touches nothing but its own
# playback. vendor.gd stays exactly as written.
#
# THE STILL FRAME IS FRAME 0 OF THE WAVE. An AnimatedSprite2D that is not
# playing shows the current frame of its current animation, so a stopped sprite
# resting on frame 0 IS the "on entry, a still image" the design asks for. We
# only ever call play() and stop(); we never need a second, one-frame "idle"
# animation.
#
# It reuses the vendor's own Area2D rather than adding a second detector, so the
# wave begins exactly when the player is close enough to trade — which is what
# makes "come to my shop" read correctly instead of waving at an empty room.
extends AnimatedSprite2D


# The looping greeting. Named with a direction suffix per the project's
# animation convention (the shopkeeper only ever faces the counter, i.e. down).
const WAVE_ANIM := &"wavedown"


func _ready() -> void:
	# Belt and suspenders. Guarantee we begin stopped on the still frame even if
	# the scene were ever saved mid-play or an autoplay slipped in — the "on
	# entry it's a still image" requirement should not depend on how the .tscn
	# happened to be saved.
	if sprite_frames != null and sprite_frames.has_animation(WAVE_ANIM):
		animation = WAVE_ANIM
	stop()
	frame = 0

	# The proximity area is the vendor Area2D this sprite hangs under. Connecting
	# here (in code) matches how vendor.gd wires its own copy of these signals,
	# and multiple connections to one signal fire independently — ours drives
	# the wave, its drives the shop. Neither knows about the other.
	var area := get_parent()
	if area is Area2D:
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)
	else:
		push_warning("shopkeeperanim: parent is not an Area2D — nothing to wave at")


func _on_body_entered(body: Node) -> void:
	if _is_player(body):
		play(WAVE_ANIM)


func _on_body_exited(body: Node) -> void:
	# Back to the still frame. Two players can never both be "the one nearby"
	# here — a vendor sits in a one-player shop — so there is no need to count
	# bodies; the player leaving always means the room is empty.
	if _is_player(body):
		stop()
		frame = 0


# Same test vendor.gd uses, kept identical on purpose: match the player whether
# it is found by node name or by group, so a rename of one never silently stops
# the wave while the shop still opens (or the reverse).
func _is_player(body: Node) -> bool:
	return body != null and (body.name == "Player" or body.is_in_group("player"))
