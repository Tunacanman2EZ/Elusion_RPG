extends Area2D

@onready var destination_point = $DestinationPoint

var can_teleport := true

func _on_body_entered(body):
	if body and can_teleport and body.is_in_group("player"):
		can_teleport = false
		body.global_position = destination_point.global_position
		print("Teleported", body.name, "to", destination_point.global_position)

func _on_body_exited(body):
	if body and body.is_in_group("player"):
		can_teleport = true
