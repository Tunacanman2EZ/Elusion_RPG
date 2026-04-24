extends "res://src/characters/player.gd"

func _ready():
	super._ready()
	character_name = "healer"
	speed = 175
	max_hp = 80
	hp = 80
	max_stamina = 0
	stamina = 0
	max_mana = 120
	mana = 120
	magic = 2
