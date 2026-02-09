"""
Mage Character Class (Godot 4.5)

WHY: Mage class extending the base Player class.
HOW: Inherits all core player functionality, overrides stamina with mana.
WHAT: Mage specialization with spellcasting focus and mana resource.
TODO:
 - Add Mage-specific abilities (spells, magic focus).
 - Customize skill progression rates.
 - Implement mana regeneration.
"""
extends "res://scripts/characters/player.gd"

# Mage-specific properties (override stamina with mana)
var max_mana := 100
var mana := 100

# --- MAGE INITIALIZATION ---
"""
Mage-specific initialization.
"""
func _ready():
	super._ready()  # Call parent _ready first
	character_name = "Mage"
	# Mage uses mana instead of stamina
	max_stamina = max_mana
	stamina = mana

