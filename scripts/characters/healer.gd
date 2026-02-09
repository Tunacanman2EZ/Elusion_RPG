"""
Healer Character Class (Godot 4.5)

WHY: Healer class extending the base Player class.
HOW: Inherits all core player functionality, overrides stamina with mana.
WHAT: Healer specialization with healing focus and mana resource.
TODO:
 - Add Healer-specific abilities (healing spells, support focus).
 - Customize skill progression rates.
 - Implement mana regeneration.
"""
extends "res://scripts/characters/player.gd"

# Healer-specific properties (override stamina with mana)
var max_mana := 100
var mana := 100

# --- HEALER INITIALIZATION ---
"""
Healer-specific initialization.
"""
func _ready():
	super._ready()  # Call parent _ready first
	character_name = "Healer"
	# Healer uses mana instead of stamina
	max_stamina = max_mana
	stamina = mana

