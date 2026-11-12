extends RefCounted
# lagtests.gd - the GM panel's lag tests (0.138.0): switch one thing off and
# watch whether the readout's hitches stop.
#
# The owner, of the Boss Arena's hitches in his browser: "can we upgrade the
# test to analyze the lag points". A browser cannot time the graphics card, so
# whether a hitch is the card drawing too much or the browser stalling cannot
# be measured there. It can be tested: hide what a fight draws, one kind at a
# time, and see which takes the hitches with it.
#
#   hide_rings   the spikes' warning rings (spikefx.gd's rings)
#   hide_sparks  their bursts of sparks (spikefx.gd's sparks)
#   hide_pools   the pools they leave (spikefx.gd's holders)
#   lights_off   every light in the area (Light2D.enabled; put back after)
#   hide_arena   a boss's arena (0.139.0, lightarena.gd): its mirrors, flares
#                and the dark (they still turn orbs and burn)
# And the Endless's (0.150.0) - the owner, of a boss fight at 4,572 slimes,
# drawing 13 ms a frame: "test and fix what you need to":
#   hide_slimes   the swarm's slimes (swarm.gd's two MultiMeshes)
#   hide_health   the monsters' health bars and their numbers
#                 (BaseEnemy._paint_bar_shown())
#   hide_numbers  the damage numbers (FloatingLabel.show_number(); words such
#                 as a level-up still show)
#   hide_spikes   the boss spikes themselves (bossprojectile.gd; their rings,
#                 sparks and pools have tests of their own)
#
# TRANSIENT, as God mode is: nothing is saved, and a restart has them all off.
# Hiding is only drawing - the spikes still warn, rise and hit, the pools
# still burn - so a test never changes a fight, only what is drawn of it.
# Kept on through a change of area: the area's spikefx.gd reads them as it is
# made, and AreaRegistry puts the lights out again (apply()).

const GROUP := &"spike_fx"
const WAS_ON_META := &"lagtest_was_on"

static var hide_rings: bool = false
static var hide_sparks: bool = false
static var hide_pools: bool = false
static var lights_off: bool = false
static var hide_arena: bool = false
static var hide_slimes: bool = false
static var hide_health: bool = false
static var hide_numbers: bool = false
static var hide_spikes: bool = false


static func set_test(test: String, on: bool, tree: SceneTree) -> void:
	"""One test on or off ("rings", "sparks", "pools", "lights", "arena"),
	now."""
	match test:
		"rings":
			hide_rings = on
		"sparks":
			hide_sparks = on
		"pools":
			hide_pools = on
		"lights":
			lights_off = on
		"arena":
			hide_arena = on
		"slimes":
			hide_slimes = on
		"health":
			hide_health = on
		"numbers":
			hide_numbers = on
		"spikes":
			hide_spikes = on
	apply(tree)


static func any_on() -> bool:
	return hide_rings or hide_sparks or hide_pools or lights_off or hide_arena \
		or hide_slimes or hide_health or hide_numbers or hide_spikes


static func names_on() -> PackedStringArray:
	"""What is off, in a few words each (the readout's title, the GM panel's
	strip)."""
	var out: PackedStringArray = []
	if hide_rings:
		out.append("rings off")
	if hide_sparks:
		out.append("sparks off")
	if hide_pools:
		out.append("pools off")
	if lights_off:
		out.append("lights off")
	if hide_arena:
		out.append("arena off")
	if hide_slimes:
		out.append("slimes off")
	if hide_health:
		out.append("health off")
	if hide_numbers:
		out.append("numbers off")
	if hide_spikes:
		out.append("spikes off")
	return out


static func apply(tree: SceneTree) -> void:
	"""Every spikefx.gd and boss arena in the tree drawn or not as the tests
	say, and the area's lights out or back as they were."""
	if tree == null:
		return
	for fx in tree.get_nodes_in_group(GROUP):
		if fx.has_method(&"show_tests"):
			fx.call(&"show_tests")
	# The health bars: each monster's, as it would show them now.
	for monster in tree.get_nodes_in_group(&"enemies"):
		if monster.has_method(&"_paint_bar_shown"):
			monster.call(&"_paint_bar_shown")
	var scene: Node = tree.current_scene
	if scene == null:
		return
	for light in scene.find_children("*", "Light2D", true, false):
		var lamp := light as Light2D
		if lights_off:
			if not lamp.has_meta(WAS_ON_META):
				lamp.set_meta(WAS_ON_META, lamp.enabled)
			lamp.enabled = false
		elif lamp.has_meta(WAS_ON_META):
			lamp.enabled = bool(lamp.get_meta(WAS_ON_META))
			lamp.remove_meta(WAS_ON_META)
