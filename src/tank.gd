"""
Tank Character Class (Godot 4.5)

WHY: Tank class extending the base Player class.
HOW: Inherits all core player functionality, sets Tank-specific properties.
WHAT: Tank specialization with defensive focus and balanced stats.
TODO:
 - Add Tank-specific abilities (high defense, tanking mechanics).
 - Customize skill progression rates.
"""
extends "res://src/player.gd"

# --- TANK INITIALIZATION ---
"""
Tank-specific initialization.
"""
func _ready():
	super._ready()  # Call parent _ready first
	character_name = "Tank"
