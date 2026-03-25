extends Area2D

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
var is_open = false

func _ready():
	anim.play("closed")  # Start with chest closed

func _on_body_entered(body):
	if body.is_in_group("player") and not is_open:
		anim.play("open")
		is_open = true
		# emit_signal("bank_open_requested", body)  # Optional: open bank UI

func _on_body_exited(body):
	if body.is_in_group("player") and is_open:
		anim.play("closed")
		is_open = false

func _on_AnimatedSprite2D_animation_finished():
	# Optionally lock on last open frame so chest stays open after anim
	if anim.animation == "open":
		anim.frame = anim.frames.get_frame_count("open") - 1
