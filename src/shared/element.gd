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
}


static func colour_for(element: int) -> Color:
	# Physical's steel is the fallback as well as its own colour — an unknown
	# element should look unremarkable, not magenta.
	return COLOURS.get(element, COLOURS[Type.NONE])


# =============================================================================
# ITERATION
# =============================================================================

static func all() -> Array:
	# Every element including NONE, in enum order. For building a bestiary, a
	# resistance table, or the loop that authored the elemental enemy set.
	return Type.values()


static func all_elemental() -> Array:
	# Every element EXCEPT NONE — the seven that are actually an element.
	# "Deal 20% more damage against one random element" wants this one; picking
	# "physical" out of that hat is not an elemental effect.
	var out: Array = Type.values()
	out.erase(Type.NONE)
	return out
