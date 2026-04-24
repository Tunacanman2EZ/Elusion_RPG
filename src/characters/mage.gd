extends "res://src/characters/player.gd"

func _ready():
	super._ready()
	character_name = "mage"
	speed = 160
	max_hp = 60
	hp = 60
	max_stamina = 0
	stamina = 0
	max_mana = 100
	mana = 100
	magic = 3
