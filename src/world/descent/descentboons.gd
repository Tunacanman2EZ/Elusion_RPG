# descentboons.gd - THE DESCENT'S UPGRADES (0.112.0): what a run has picked,
# and what that does to the character while the run goes on.
#
# The owner, of the mock-up (the commit folder's roguelike_mockup.png): "that
# looks so cool incredible simply the best lets try it out". Played as your
# own warrior (the warrior's minigame); step 1's upgrades work on what every
# class shares, three numbers player.gd asks of every hit and step - the
# warrior's own moves come in step 2:
#
#   damage_factor()  in get_damage_multiplier() - every class's hit and the
#                    pet's shot come through it (Might, Berserk)
#   taken_factor()   in effects_damage_scale() - every hit on a player comes
#                    through damage_taken() (Iron Skin, Berserk)
#   speed_factor()   in effects_speed_scale() - both movement loops ask it
#                    (Swift)
#
# All 1 unless a run is on (`active`), so the rest of the world never feels
# them: the run sets `active` as it starts and clear() takes everything off
# when it ends, falls or the area is left (descentrun.gd _exit_tree()).
#
# AND THE WARRIOR'S OWN (it is the warrior's Descent - the owner: "this will
# be the warriors decent"), asked by warrior.gd and slashwave.gd:
#
#   whirlwind()        the swing cuts all four ways at once (Whirlwind)
#   bleed_swings()     each swing's cut bleeds this many swings more over
#                      bleed.gd's two seconds (Bloodletter)
#   finisher_every()   the gold finisher every 2nd swing (Quick Finisher)
#   wave_scale()       the wave, its picture and its box, bigger (Long Wave)
#
# NO HEALING HERE, on purpose: health is the client's and the server takes
# back a heal it cannot explain (the API's heal reconciliation), so a boon
# that heals would be clamped on the next status push. Healing comes when the
# server grants it (step 3 of the plan).
#
# No class_name: preloaded by player.gd, descentrun.gd and the suite.
extends RefCounted

const MOST := 5
# id -> name, what it does, how far it stacks.
const BOONS := {
	"might": {"name": "Might", "does": "+15% damage", "most": MOST},
	"iron": {"name": "Iron Skin", "does": "Take 8% less damage", "most": MOST},
	"swift": {"name": "Swift", "does": "+8% walking speed", "most": MOST},
	"fortune": {"name": "Fortune", "does": "+25% gold from rooms", "most": MOST},
	"berserk": {"name": "Berserk", "does": "+40% damage, but take 20% more", "most": 1},
	"whirlwind": {"name": "Whirlwind", "does": "Your swing cuts all the way round you", "most": 1},
	"bloodletter": {"name": "Bloodletter", "does": "Your swings make them bleed", "most": 3},
	"quickfinish": {"name": "Quick Finisher", "does": "The gold finisher every 2nd swing", "most": 1},
	"longwave": {"name": "Long Wave", "does": "Your wave is a quarter bigger", "most": 3},
}
const ORDER := ["might", "iron", "swift", "fortune", "berserk", "whirlwind", "bloodletter", "quickfinish", "longwave"]
const MIGHT_STEP := 0.15
const IRON_STEP := 0.08
const SWIFT_STEP := 0.08
const FORTUNE_STEP := 0.25
const BERSERK_DEALT := 1.4
const BERSERK_TAKEN := 1.2
# A level of Bloodletter bleeds half a swing more; Long Wave a quarter bigger.
const BLEED_STEP := 0.5
const WAVE_STEP := 0.25
const QUICK_FINISHER := 2

static var active: bool = false
static var levels: Dictionary = {}


static func level(id: String) -> int:
	return int(levels.get(id, 0))


static func take(id: String) -> bool:
	"""One more level of `id`, never past its most."""
	if not BOONS.has(id) or level(id) >= int(BOONS[id]["most"]):
		return false
	levels[id] = level(id) + 1
	return true


static func clear() -> void:
	active = false
	levels = {}


static func damage_factor() -> float:
	if not active:
		return 1.0
	return (1.0 + MIGHT_STEP * level("might")) * (BERSERK_DEALT if level("berserk") > 0 else 1.0)


static func taken_factor() -> float:
	if not active:
		return 1.0
	return maxf(0.2, 1.0 - IRON_STEP * level("iron")) * (BERSERK_TAKEN if level("berserk") > 0 else 1.0)


static func speed_factor() -> float:
	if not active:
		return 1.0
	return 1.0 + SWIFT_STEP * level("swift")


static func gold_factor() -> float:
	if not active:
		return 1.0
	return 1.0 + FORTUNE_STEP * level("fortune")


static func whirlwind() -> bool:
	return active and level("whirlwind") > 0


static func bleed_swings() -> float:
	return BLEED_STEP * level("bloodletter") if active else 0.0


static func finisher_every(usual: int) -> int:
	return QUICK_FINISHER if active and level("quickfinish") > 0 else usual


static func wave_scale() -> float:
	return 1.0 + WAVE_STEP * level("longwave") if active else 1.0


static func offers(rng: RandomNumberGenerator, count: int = 3) -> Array:
	"""Up to `count` different upgrades not yet at their most, at random."""
	var open: Array = []
	for id in ORDER:
		if level(id) < int(BOONS[id]["most"]):
			open.append(id)
	for i in range(open.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Variant = open[i]
		open[i] = open[j]
		open[j] = swap
	return open.slice(0, count)


static func level_text(id: String) -> String:
	var most: int = int(BOONS[id]["most"])
	if most == 1:
		return "Once a run"
	return "New" if level(id) == 0 else "Level %d of %d" % [level(id) + 1, most]
