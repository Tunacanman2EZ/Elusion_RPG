extends Control

var active_character = null

func set_active_character(character):
	active_character = character

func _on_AttackButton_pressed():
	print("Attack button pressed!")
	if active_character:
		active_character.attack_action()
