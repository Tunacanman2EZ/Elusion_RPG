extends Area2D

@onready var label: Label = $Label

func _ready() -> void:
	label.visible = false

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		label.visible = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		label.visible = false
