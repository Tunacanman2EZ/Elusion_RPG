# puddles.gd — which ground hazard an element leaves behind.
#
# WHY THIS IS ITS OWN FILE AND NOT A CONST IN acidpuddle.gd
# ---------------------------------------------------------
# Every one of the scenes below runs acidpuddle.gd. A script cannot preload a
# scene that its own script is attached to — Godot reports a cyclic dependency
# and refuses to parse. poisonslime.gd hit the same wall and worked around it
# with a runtime load(); this is the tidier half of that lesson: put the table
# somewhere that is not itself part of the cycle.
#
# Nothing has this script attached, so it can preload all nine.
#
# WHY NINE SCENES INSTEAD OF ONE RECOLOURED AT RUNTIME
# -----------------------------------------------------
# The single scene worked — a ShaderMaterial built per pool, hue set from the
# element. It also meant every pool allocated its own Material, and the thing
# that decides what fire acid looks like lived in a table in GDScript rather
# than in a file you can open and look at.
#
# A scene per element is the version you can actually work with: the material
# is authored once and SHARED by every instance of that scene, the colour is
# visible in the editor, and tuning how long ice lingers is a number in
# icepuddle.tscn rather than a row in someone's dictionary. It costs nine small
# files, which is not a cost.
class_name Puddles
extends RefCounted


# Element.Type -> the scene that element leaves behind.
#
# LIGHT AND WIND HAVE ENTRIES even though the boss profile never rolls a pool
# for them: the elemental slimes do, and an element that has no scene would
# fall through to poison and drop green acid out of a wind creature.
const BY_ELEMENT := {
	Element.Type.POISON: preload("res://scene/projectiles/poisonpuddle.tscn"),
	Element.Type.FIRE: preload("res://scene/projectiles/firepuddle.tscn"),
	Element.Type.ICE: preload("res://scene/projectiles/icepuddle.tscn"),
	Element.Type.EARTH: preload("res://scene/projectiles/earthpuddle.tscn"),
	Element.Type.WATER: preload("res://scene/projectiles/waterpuddle.tscn"),
	Element.Type.DARK: preload("res://scene/projectiles/darkpuddle.tscn"),
	Element.Type.LIGHTNING: preload("res://scene/projectiles/lightningpuddle.tscn"),
	Element.Type.LIGHT: preload("res://scene/projectiles/lightpuddle.tscn"),
	Element.Type.WIND: preload("res://scene/projectiles/windpuddle.tscn"),
}


static func scene_for(element: int) -> PackedScene:
	# POISON IS THE FALLBACK because it is the original — the art these are all
	# recolours of is the slime's, so an element with no scene of its own comes
	# out as the acid this game already had rather than as nothing at all.
	#
	# NONE lands here too, and that is deliberate: a hazard with no element is
	# still a hazard, and returning null would silently delete it.
	return BY_ELEMENT.get(element, BY_ELEMENT[Element.Type.POISON])
