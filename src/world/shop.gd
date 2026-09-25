extends Area2D

@onready var interior = $"../shopinterior"
@onready var exterior = $"../shopexterior"
@onready var interior_furniture = $"../interiorfurniture"

func _ready():
	if interior: interior.visible = false
	if exterior: exterior.visible = true
	if interior_furniture: interior_furniture.visible = false

func _on_body_entered(body):
	if body.is_in_group("player"):
		if interior: interior.visible = true
		if exterior: exterior.visible = false
		if interior_furniture: interior_furniture.visible = true

func _on_body_exited(body):
	if body.is_in_group("player"):
		if interior: interior.visible = false
		if exterior: exterior.visible = true
		if interior_furniture: interior_furniture.visible = false

