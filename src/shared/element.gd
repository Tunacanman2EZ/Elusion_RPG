# element.gd — the game's elemental types, and the one place each one's colour
# is written down.
#
# WHY THIS IS NOT IN gamestate.gd, WHERE IT STARTED
# -------------------------------------------------
# The enum lived there and nothing in the project ever used it — not one
# reference in ten thousand lines. That was not neglect. gamestate.gd is an
# autoload with no class_name, so `GameState.Element` cannot be written in a
# type position: not as an @export on a Resource, not as a parameter type, not
# as a return type. An enum you can only compare ints against is an enum nobody
# reaches for.
#
# A class_name fixes that, and gamestate.gd cannot have one — it would collide
# with its own autoload name. So the enum moves to a file that can, exactly as
# Facing did for the four directions. Same pattern, same reason.
#
# COLOUR LIVES HERE TOO, AND THAT IS THE POINT
# --------------------------------------------
# An element the player cannot see is a number in a save file. The colour is
# how an element becomes a thing you recognise across a room, and keeping it
# beside the enum means there is ONE answer to "what colour is fire" rather
# than one per scene that drew a fire thing.
#
# This is the file the pets' colour chaos was missing. They arrived with two
# and three modulates stacked on different nodes, multiplying into browns
# nobody chose, because there was nowhere to look up the right answer.
class_name Element
extends RefCounted


# =============================================================================
# THE TYPES
# =============================================================================

# NONE is index 0 and means "physical / no element". Keep it first: it is the
# default for any hit that does not name one, and a default that is not zero is
# a default nobody gets.
#
# APPEND ONLY. These values are written into .tres files as integers, so
# inserting a new element in the middle silently rewrites every enemy authored
# after it — a fire sprite becomes a water sprite with no file changing.
enum Type {
	NONE,
	DARK,
	LIGHT,
	ICE,
	WIND,
	EARTH,
	FIRE,
	WATER,
	# APPENDED AFTER THE ART EXISTED, which is the right way round. The artist
	# had already drawn an electric sprite and a poison slime, and neither had
	# an element — so the electric sprite was filed under WIND and the slimes
	# under EARTH, and the recolour shader dutifully turned a blue lightning
	# creature mint green and a green slime brown. The enum was missing two
	# types the game already had creatures for. See COLOURS.
	LIGHTNING,
	POISON,
}


# =============================================================================
# NAMES
# =============================================================================

const NAMES := {
	Type.NONE:  "physical",
	Type.DARK:  "dark",
	Type.LIGHT: "light",
	Type.ICE:   "ice",
	Type.WIND:  "wind",
	Type.EARTH: "earth",
	Type.FIRE:  "fire",
	Type.WATER: "water",
	Type.LIGHTNING: "lightning",
	Type.POISON:    "poison",
}


static func name_for(element: int) -> String:
	# Always a name. An out-of-range value reads as physical rather than
	# throwing, because the callers are damage labels and debug output and
	# neither should be able to crash a fight.
	return NAMES.get(element, "physical")


# =============================================================================
# COLOURS
# =============================================================================

# One colour per element, chosen to stay apart from each other on a dark field
# rather than to be individually pretty. Eight hues that a player can tell
# apart at a glance mid-fight is the whole requirement; a palette where dark
# and earth read as the same brown fails even if both swatches look good.
#
# THESE ARE MULTIPLIED OVER ART, NOT PAINTED ONTO IT. modulate darkens and
# filters — it cannot move a hue. Against near-neutral art (the electric sprite
# sheet measures 0.28 saturation, the bush archer 0.18) these land close to
# true. Against art that is already strongly coloured — the slimes are 0.6
# saturated green — every one of them comes out a darker, duller green. That is
# a property of the blend, not a bug to fix here: an elemental family wants a
# pale base sprite, and the two above are the ones that have it.
const COLOURS := {
	Type.NONE:  Color(0.79607844, 0.83529414, 0.88235295),  # #CBD5E1  steel
	Type.DARK:  Color(0.42745098, 0.15686275, 0.8509804),   # #6D28D9  deep violet
	Type.LIGHT: Color(0.99215686, 0.9019608, 0.5411765),    # #FDE68A  pale gold
	Type.ICE:   Color(0.40392157, 0.9098039, 0.9764706),    # #67E8F9  pale cyan
	Type.WIND:  Color(0.654902, 0.9529412, 0.8156863),      # #A7F3D0  mint
	Type.EARTH: Color(0.6313726, 0.38431373, 0.02745098),   # #A16207  ochre
	Type.FIRE:  Color(1.0, 0.41568628, 0.12156863),         # #FF6A1F  ember
	Type.WATER: Color(0.23137255, 0.50980395, 0.9647059),   # #3B82F6  blue

	# THESE TWO ARE MEASURED FROM THE ART, NOT PICKED. Every colour above was
	# chosen on a palette; these two were sampled out of the artist's own
	# sheets — the saturation-weighted mean hue of every chromatic pixel in
	# electricsprite.png and slime.png. The creature came first and the element
	# is named after it, so the element's colour is the creature's colour by
	# definition rather than by luck.
	#
	# LIGHTNING SITS BETWEEN ICE AND WATER, at 0.564 against 0.519 and 0.603.
	# That is tight for three colours a player has to tell apart on a floating
	# damage number, and it is deliberate: the electric sprite IS that blue and
	# moving it to make the palette tidier would be inventing a colour for a
	# creature that already has one. If the labels ever need separating, change
	# how labels are drawn, not what the artist painted.
	Type.LIGHTNING: Color(0.32268293, 0.59910947, 0.77315128),  # #5299C5  electricsprite.png
	Type.POISON:    Color(0.18372081, 0.61082840, 0.12159075),  # #2F9C1F  slime.png
}


# The same palette expressed as a hue, 0-1, for element_recolour.gdshader.
#
# DERIVED FROM COLOURS ABOVE, not chosen separately — each of these is that
# colour's own hue. Two numbers for one fact is how a palette drifts, so if you
# retune a colour, run its hue again rather than nudging this by eye.
const HUES := {
	Type.NONE:  0.5909,
	Type.DARK:  0.7316,
	Type.LIGHT: 0.1333,
	Type.ICE:   0.5194,
	Type.WIND:  0.4232,
	Type.EARTH: 0.0985,
	Type.FIRE:  0.0558,
	Type.WATER: 0.6034,
	Type.LIGHTNING: 0.5644,
	Type.POISON:    0.3122,
}


static func hue_for(element: int) -> float:
	return HUES.get(element, HUES[Type.NONE])


# How much to push saturation for a given sheet, so a pale creature recolours
# with the same conviction as a vivid one.
#
# THE SHEETS ARE NOT EQUALLY COLOURED, and a hue rotation preserves saturation
# by design — which means a 0.28-saturation electric sprite turned to fire
# looks washed out beside a 0.66-saturation slime turned to fire.
#
# MEASURED SHEET SATURATIONS, for whoever authors the next elemental family:
#
#     busharcher      0.18     needs the most push, roughly 1.6
#     electricsprite  0.28     1.6
#     bushmage        0.40     1.3
#     firesprite      0.59     1.0
#     slime           0.66     needs none
#
# ONLY DERIVED VARIANTS EVER SEE THIS. An original sheet is drawn exactly as
# authored — see EnemyData.recolour_to_element — so these numbers apply to the
# copies made FROM a sheet, never to the sheet itself.
#
# The scale is authored per creature on its own material rather than computed,
# because "how vivid should this creature be" is art direction, not arithmetic.


static func colour_for(element: int) -> Color:
	# Physical's steel is the fallback as well as its own colour — an unknown
	# element should look unremarkable, not magenta.
	return COLOURS.get(element, COLOURS[Type.NONE])


# NOTHING HERE ITERATES THE ENUM, AND NOTHING RESISTS ANYTHING YET. all(),
# all_elemental() and a flat resistance() stub all lived here and had no
# callers; `Type.values()` is what they wrapped. When the resistance table is
# actually designed it belongs in this file, taking attacker and defender
# elements and returning a multiplier — the three call sites that would need it
# (player.take_damage, BaseEnemy.take_damage, the projectile scripts) already
# carry an element each, which was the hard part and is done.
