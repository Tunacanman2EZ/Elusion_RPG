# lightflicker.gd — makes a PointLight2D breathe like an open flame.
#
# Attach to the PointLight2D itself (not its parent). It reads whatever energy
# and texture_scale the light was authored with in the editor as its rest
# values, then modulates around them. Tune the light in the inspector as if
# this script did not exist; the flicker rides on top of your setting.
#
# WHY NOT randf() EVERY FRAME:
# Per-frame random energy is the obvious implementation and it looks wrong —
# it reads as electrical noise or a dying fluorescent tube, not as fire. A real
# flame has momentum: it swells, hangs, collapses. That shape comes from
# summing a few sine waves at frequencies that do not divide into each other,
# so the pattern never visibly repeats but every individual movement is smooth.
#
# WHY EACH LIGHT GETS A RANDOM PHASE:
# Same reason firepit.gd starts its crackle loop at a random offset. Six
# candles in a room all pulsing on the same beat does not look like six
# candles, it looks like someone flipping one switch. The phase offset costs
# nothing and they never line up.
#
# WHY IT MOVES energy AND texture_scale BUT NOT position:
# A flame that only changes brightness looks like a dimmer. A real one also
# changes how far it throws. But this project runs physics interpolation, and
# a Node2D transform written from _process fights the interpolator — the
# renderer is blending between physics transforms and will stomp whatever
# _process wrote. energy and texture_scale are plain Light2D properties, not
# transforms, so nothing interpolates them and they are safe to drive here.
extends PointLight2D


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# How far energy swings, as a fraction of the authored value.
# 0.20 means the light ranges roughly 80%–120% of its rest brightness.
# Small flames flicker HARD (a candle stub is mostly draft); big or shielded
# ones barely move. Set this per prop, not globally.
@export_range(0.0, 1.0, 0.01) var flicker_amount: float = 0.18

# Cycles per second of the base wave. Higher = twitchier.
# A bare candle is fast and nervous; a lantern behind glass is slow.
@export_range(0.5, 20.0, 0.1) var flicker_speed: float = 6.0

# How much the light's REACH moves with its brightness, as a fraction of the
# authored texture_scale. Kept smaller than flicker_amount on purpose: a flame
# brightening throws noticeably more light but the lit radius grows much less
# than the brightness does, so matching the two makes the room pump.
@export_range(0.0, 0.5, 0.01) var reach_amount: float = 0.05

# Turn the whole thing off without deleting the script — useful for a light
# that should be dead steady (a magical rune, a shaft of daylight).
@export var enabled: bool = true


# =============================================================================
# STATE
# =============================================================================

# The values the light was authored with. Captured once in _ready() so the
# inspector stays the single source of truth for how bright this light is.
var _rest_energy: float = 1.0
var _rest_reach: float = 1.0

# This instance's own place in the cycle. Random per light.
var _phase: float = 0.0


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_rest_energy = energy
	_rest_reach = texture_scale
	_phase = randf() * TAU

	if not enabled:
		# Nothing to animate — stop paying for a _process call on every light
		# in the level. With a dozen lights per room this matters more than it
		# looks like it should.
		set_process(false)


func _process(delta: float) -> void:
	_phase += delta * flicker_speed

	# Three sines at deliberately non-harmonic ratios (1 : 2.37 : 4.73). If
	# these were 1 : 2 : 4 they would share a period and the whole pattern
	# would visibly loop about once a second. The odd ratios push the repeat
	# out past anything a player will sit and watch for.
	#
	# Weights fall off with frequency for the same reason: the slow swell is
	# the body of the movement, the fast ones are just surface detail. Sum of
	# weights is 1.0, so `wobble` stays inside -1..1 and flicker_amount means
	# exactly what its name says.
	var wobble: float = (
		sin(_phase) * 0.6
		+ sin(_phase * 2.37 + 1.1) * 0.3
		+ sin(_phase * 4.73 + 2.7) * 0.1
	)

	energy = _rest_energy * (1.0 + wobble * flicker_amount)
	texture_scale = _rest_reach * (1.0 + wobble * reach_amount)
