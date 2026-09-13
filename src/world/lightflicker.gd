# lightflicker.gd — makes a PointLight2D breathe like an open flame.
#
# Attach to the PointLight2D itself (not its parent). It reads whatever energy
# and texture_scale the light was authored with in the editor as its rest
# values, then modulates around them. Tune the light in the inspector as if
# this script did not exist; the movement rides on top of your setting.
#
# TWO LAYERS, AND THE SLOW ONE IS THE ONE YOU ACTUALLY SEE.
#
# A flame moves on two timescales at once, and they do different jobs:
#
#   SWELL   — slow, seconds long, large. The fire finds more fuel and the
#             room brightens; it runs low and the walls sink back toward
#             black. This is the layer a player consciously notices, and it
#             is what "dim then brighten" means.
#   FLICKER — fast, several times a second, small. Draft and turbulence on
#             the flame itself. On its own it reads as electrical noise; its
#             job is to stop the swell looking like someone turning a dial.
#
# The first version of this script only had the fast layer, which is why the
# lights looked steady: fast movement below a certain size averages out in
# the eye. Brightness has to travel a real distance over a real second to
# register as a flame.
#
# WHY SINES AND NOT randf() EVERY FRAME:
# Per-frame randomness is the obvious implementation and it looks wrong —
# a failing fluorescent tube, not fire. A real flame has momentum: it swells,
# hangs, collapses. That comes from summing waves at frequencies that do not
# divide into each other, so the pattern never visibly repeats while every
# individual movement stays smooth.
#
# WHY EACH LIGHT GETS A RANDOM PHASE:
# Same reason firepit.gd starts its crackle loop at a random offset. Six
# candles pulsing on the same beat does not look like six candles, it looks
# like one switch. The phase offset costs nothing and they never line up.
#
# WHY IT MOVES energy AND texture_scale BUT NOT position:
# A flame that only changes brightness looks like a dimmer; a real one also
# changes how far it throws. But this project runs physics interpolation, and
# a Node2D transform written from _process fights the interpolator — the
# renderer blends between physics transforms and stomps whatever _process
# wrote. energy and texture_scale are plain Light2D properties, not
# transforms, so nothing interpolates them and they are safe to drive here.
extends PointLight2D


# =============================================================================
# EXPORTED SETTINGS — THE SLOW LAYER
# =============================================================================

# How far the slow swell carries brightness, as a fraction of the authored
# energy. 0.30 means the light travels roughly 70%–130% of its rest value
# over the course of a few seconds.
#
# This is the dial to turn when the lights look too steady. flicker_amount
# will not fix that no matter how high you push it — see the header.
@export_range(0.0, 1.0, 0.01) var swell_amount: float = 0.28

# Cycles per second of the swell. Deliberately well under 1.0: a full
# dim-and-recover should take somewhere between two and five seconds. Push
# this past about 1.5 and it stops reading as fire and starts reading as a
# pulsing magical object, which is a fine effect but a different one.
@export_range(0.05, 3.0, 0.05) var swell_speed: float = 0.55


# =============================================================================
# EXPORTED SETTINGS — THE FAST LAYER
# =============================================================================

# How far the fast flicker swings, as a fraction of the authored energy.
# Small flames flicker HARD (a candle stub is mostly draft); big or shielded
# ones barely move. Set this per prop, not globally.
@export_range(0.0, 1.0, 0.01) var flicker_amount: float = 0.18

# Cycles per second of the base flicker wave. Higher = twitchier.
# A bare candle is fast and nervous; a lantern behind glass is slow.
@export_range(0.5, 20.0, 0.1) var flicker_speed: float = 6.0


# =============================================================================
# EXPORTED SETTINGS — SHARED
# =============================================================================

# How much of the brightness movement the light's REACH copies, as a fraction.
# 0.0 means the lit radius never changes and only brightness moves; 1.0 means
# they move together.
#
# Kept low on purpose. A brightening flame does throw further, but the radius
# grows far less than the brightness does — matching them one-to-one makes the
# whole room pump in and out, which looks like a camera problem rather than a
# fire.
@export_range(0.0, 1.0, 0.01) var reach_response: float = 0.3

# Turn the movement off without deleting the script — useful for a light that
# should be dead steady (a magical rune, a shaft of daylight).
#
# NAMED flicker_enabled, NOT enabled: Light2D already has an `enabled`
# property, and that one controls whether the light emits at all. Two
# different switches. Godot rejects the collision outright rather than
# letting a script quietly shadow a native member, which is the correct call
# — the same protection that caught `snapped` in baseenemy.gd.
@export var flicker_enabled: bool = true


# =============================================================================
# STATE
# =============================================================================

# The values the light was authored with. Captured once in _ready() so the
# inspector stays the single source of truth for how bright this light is.
var _rest_energy: float = 1.0
var _rest_reach: float = 1.0

# This instance's own place in each cycle. Random per light, and the two are
# seeded independently so a light is not guaranteed to start its swell and its
# flicker at the same point.
var _phase: float = 0.0
var _swell_phase: float = 0.0


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_rest_energy = energy
	_rest_reach = texture_scale
	_phase = randf() * TAU
	_swell_phase = randf() * TAU

	if not flicker_enabled:
		# Nothing to animate — stop paying for a _process call on every light
		# in the level. With a dozen lights per room this matters more than it
		# looks like it should.
		set_process(false)


func _process(delta: float) -> void:
	_phase += delta * flicker_speed
	_swell_phase += delta * swell_speed

	# FAST LAYER. Three sines at deliberately non-harmonic ratios
	# (1 : 2.37 : 4.73). If these were 1 : 2 : 4 they would share a period and
	# the pattern would visibly loop about once a second. The odd ratios push
	# the repeat out past anything a player will sit and watch for.
	#
	# Weights fall off with frequency because the slow component is the body
	# of the movement and the fast ones are surface detail. They sum to 1.0,
	# so the result stays inside -1..1 and flicker_amount means exactly what
	# its name says.
	var flicker: float = (
		sin(_phase) * 0.6
		+ sin(_phase * 2.37 + 1.1) * 0.3
		+ sin(_phase * 4.73 + 2.7) * 0.1
	)

	# SLOW LAYER. Same trick, two waves instead of three — the swell wants to
	# be readable, not busy. The 1.63 ratio is enough to keep it from feeling
	# metronomic.
	var swell: float = sin(_swell_phase) * 0.7 + sin(_swell_phase * 1.63 + 0.7) * 0.3

	# One combined offset drives both properties, so brightness and reach can
	# never drift out of agreement — a light that got dimmer while reaching
	# further would look distinctly wrong.
	var variation: float = swell * swell_amount + flicker * flicker_amount

	# maxf guards the floor. With a large swell_amount and flicker_amount both
	# bottoming out on the same frame, the sum can pass -1.0 and ask for
	# negative energy — which on an additive light means it starts SUBTRACTING
	# from the scene and punches a black hole where the candle is.
	energy = maxf(0.0, _rest_energy * (1.0 + variation))
	texture_scale = _rest_reach * (1.0 + variation * reach_response)
