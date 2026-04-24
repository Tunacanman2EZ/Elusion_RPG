extends Area2D

@onready var interior = $"../Interior"
@onready var exterior = $"../Exterior"

func _ready():
	# Only show exterior at start, hide interior
	if interior:
		interior.visible = false
	if exterior:
		exterior.visible = true

func _on_body_entered(body):
	if body.is_in_group("player"):
		print("Player near building: interior visible, exterior hidden.")
		if interior: interior.visible = true
		if exterior: exterior.visible = false

func _on_body_exited(body):
	if body.is_in_group("player"):
		print("Player left: interior hidden, exterior visible.")
		if interior: interior.visible = false
		if exterior: exterior.visible = true
