extends "res://src/characters/player.gd"

func _ready():
	super._ready()
	character_name = "tank"
	speed = 140
	max_hp = 150
	hp = 150
	max_stamina = 120
	stamina = 120
	defense = 3
