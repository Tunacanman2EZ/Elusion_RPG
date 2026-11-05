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
# THE WARD INSTEAD (0.115.0) - the owner: "feels pretty boring and chars die
# fast". A gold shield over your health, WARD_SHARE of your most health,
# taken first by every hit (absorb(), in Player.take_damage() after armour)
# and filled again as each room is cleared (descentrun.gd fill_ward()). Your
# health never goes up, so the server has nothing to take back.
#
# AND THE CRYPT HITS SOFTER (0.115.0): its monsters are the open world's, built
# for groups. `floor_taken` (descentrun.gd FLOORS' "taken", set as each room is
# entered) is in taken_factor(): half on the first floor, then 0.7, then 0.9 -
# and 1 in a keeper's room (0.123.0, descentrun.gd taken_for()).
#
# STEP 2 (0.115.0): RARITIES and five more. Each upgrade is common, rare or
# epic (RARITY_WEIGHTS: a rare one comes about half as often as a common, an
# epic a sixth); a Shrine, a Challenge won and a keeper offer rare or better
# (offers()' `at_least`). The new five:
#
#   Bulwark      the ward a bigger share of your health (ward_share())
#   Thorns       a hit on you cuts every monster near you (thorns(), from
#                Player.take_damage())
#   Execute      a monster under EXECUTE_BELOW dies to any hit (executed(),
#                from BaseEnemy.take_damage())
#   Momentum     each kill in a room a little faster and harder
#                (note_kill(), `room_kills`, in damage_factor/speed_factor)
#   Second Wind  once a floor, a fall leaves you standing, ward full
#                (second_wind(), from descentrun.gd knock_out())
#
# A Shrine's price: the floor's monsters hit SHRINE_CURSE harder for the rest
# of the floor (`shrine_taken`, in taken_factor(); new_floor() lifts it).
#
# THE DOUBLE AXE'S OWN (step 2's second half, 0.115.0) - the owner: "we can
# also use mythic weapon here some how". MYTHIC upgrades, offered only to a
# warrior wearing it (offers()' `axe`), and a keeper always offers one:
#
#   Twin Axes   thrown with a twin (twin_axes(), warrior.gd throw_axe())
#   Storm       the spin a quarter wider a level (axe_reach_scale())
#   Harvester   half again harder coming home a level (harvester_scale())
#   Magnet      the spinning axe pulls monsters in (magnet())
#   Ricochet    the thrown axe flies on to the next monster (ricochet())
#
# EVERY CLASS ITS OWN (0.124.0, DESCENT_PLAN_3.txt step 2 - the owner: "any
# class can join but we have to set up bonuses for all 4 chars"): every
# upgrade with a "class" is offered to that class alone, and a mythic only
# with its "weapon" on (fits(), `class_now`, `weapon_now`). The mage's Arcane
# Edge, Spike Storm, Deep Crits and the Meteorite's Meteor Shower, Comet and
# Long Burn; the tank's Searing Aura, Bastion and the Dynamite's Cluster,
# Barrage and Short Fuse; the healer's Quick Hands, Twin Orbs and Warding
# Light (no mythic: the healer has no mythic weapon yet).
#
# And AXE FURY: every kill fills `fury`; at FURY_NEEDS, Q throws a giant
# spinning axe round the room (descentrun.gd unleash_fury()).
#
# No class_name: preloaded by player.gd, baseenemy.gd, spinningaxe.gd,
# warrior.gd, descentrun.gd and the suite.
extends RefCounted

const MOST := 5
# id -> name, what it does, how far it stacks.
const BOONS := {
	"might": {"name": "Might", "does": "+15% damage", "most": MOST, "rarity": "common"},
	"iron": {"name": "Iron Skin", "does": "Take 8% less damage", "most": MOST, "rarity": "common"},
	"swift": {"name": "Swift", "does": "+8% walking speed", "most": MOST, "rarity": "common"},
	"fortune": {"name": "Fortune", "does": "+25% gold from rooms", "most": MOST, "rarity": "common"},
	"bulwark": {"name": "Bulwark", "does": "Your ward is 15% more of your health", "most": 3, "rarity": "common"},
	"bloodletter": {"name": "Bloodletter", "does": "Your swings make them bleed", "most": 3, "rarity": "rare", "class": "warrior"},
	"longwave": {"name": "Long Wave", "does": "Your wave is a quarter bigger", "most": 3, "rarity": "rare", "class": "warrior"},
	"thorns": {"name": "Thorns", "does": "A hit on you cuts every monster near you", "most": 3, "rarity": "rare"},
	"execute": {"name": "Execute", "does": "A monster under 15% health dies to any hit", "most": 1, "rarity": "rare"},
	"momentum": {"name": "Momentum", "does": "Each kill in a room: +4% damage and speed, up to 10", "most": 1, "rarity": "rare"},
	"berserk": {"name": "Berserk", "does": "+40% damage, but take 20% more", "most": 1, "rarity": "epic"},
	"whirlwind": {"name": "Whirlwind", "does": "Your swing cuts all the way round you", "most": 1, "rarity": "epic", "class": "warrior"},
	"quickfinish": {"name": "Quick Finisher", "does": "The gold finisher every 2nd swing", "most": 1, "rarity": "epic", "class": "warrior"},
	"secondwind": {"name": "Second Wind", "does": "Once a floor, a fall leaves you standing, ward full", "most": 1, "rarity": "epic"},
	"twinaxes": {"name": "Twin Axes", "does": "Your Double Axe is thrown with a twin", "most": 1, "rarity": "mythic", "class": "warrior", "weapon": "axe"},
	"storm": {"name": "Storm", "does": "Your spinning axe cuts a quarter wider", "most": 3, "rarity": "mythic", "class": "warrior", "weapon": "axe"},
	"harvester": {"name": "Harvester", "does": "Your axe cuts half again harder coming home", "most": 3, "rarity": "mythic", "class": "warrior", "weapon": "axe"},
	"magnet": {"name": "Magnet", "does": "Your spinning axe pulls monsters into it", "most": 1, "rarity": "mythic", "class": "warrior", "weapon": "axe"},
	"ricochet": {"name": "Ricochet", "does": "Your thrown axe flies on to the next monster", "most": 1, "rarity": "mythic", "class": "warrior", "weapon": "axe"},
	# EVERY CLASS ITS OWN (0.124.0, step 2 of DESCENT_PLAN_3.txt): the mage's,
	# the tank's and the healer's, and the Meteorite's and Dynamite's mythics.
	"arcaneedge": {"name": "Arcane Edge", "does": "+10% chance your spikes hit critical", "most": 3, "rarity": "rare", "class": "mage"},
	"spikestorm": {"name": "Spike Storm", "does": "Your triple drop comes a cast sooner", "most": 2, "rarity": "rare", "class": "mage"},
	"deepcrits": {"name": "Deep Crits", "does": "Your critical spikes hit three times, not twice", "most": 1, "rarity": "epic", "class": "mage"},
	"shower": {"name": "Meteor Shower", "does": "Every meteor brings two more beside it", "most": 1, "rarity": "mythic", "class": "mage", "weapon": "meteor"},
	"comet": {"name": "Comet", "does": "Your meteors fall in half the time", "most": 1, "rarity": "mythic", "class": "mage", "weapon": "meteor"},
	"longburn": {"name": "Long Burn", "does": "Your meteor's crater burns half again as long", "most": 2, "rarity": "mythic", "class": "mage", "weapon": "meteor"},
	"searing": {"name": "Searing Aura", "does": "Your aura burns 25% harder", "most": 3, "rarity": "rare", "class": "tank"},
	"bastion": {"name": "Bastion", "does": "Take 20% less while your aura burns", "most": 1, "rarity": "epic", "class": "tank"},
	"cluster": {"name": "Cluster", "does": "Half your throws are a bundle of three", "most": 1, "rarity": "mythic", "class": "tank", "weapon": "dynamite"},
	"barrage": {"name": "Barrage", "does": "One throw in seven is a barrage of five", "most": 1, "rarity": "mythic", "class": "tank", "weapon": "dynamite"},
	"shortfuse": {"name": "Short Fuse", "does": "Your dynamite goes off in half the time", "most": 1, "rarity": "mythic", "class": "tank", "weapon": "dynamite"},
	"quickhands": {"name": "Quick Hands", "does": "+12% shots a second", "most": 3, "rarity": "rare", "class": "healer"},
	"twinorbs": {"name": "Twin Orbs", "does": "Your fan of orbs comes a shot sooner", "most": 2, "rarity": "rare", "class": "healer"},
	"wardinglight": {"name": "Warding Light", "does": "Your healing aura fills your ward as it heals you", "most": 1, "rarity": "epic", "class": "healer"},
}
const ORDER := ["might", "iron", "swift", "fortune", "bulwark", "bloodletter", "longwave", "thorns", "execute",
	"momentum", "berserk", "whirlwind", "quickfinish", "secondwind",
	"twinaxes", "storm", "harvester", "magnet", "ricochet",
	"arcaneedge", "spikestorm", "deepcrits", "shower", "comet", "longburn",
	"searing", "bastion", "cluster", "barrage", "shortfuse",
	"quickhands", "twinorbs", "wardinglight"]
const RARITIES := ["common", "rare", "epic", "mythic"]
const RARITY_WEIGHTS := {"common": 60, "rare": 30, "epic": 10, "mythic": 12}
const RARITY_COLOURS := {"common": Color(0.92, 0.88, 0.78), "rare": Color(0.45, 0.75, 1.0),
	"epic": Color(0.82, 0.5, 1.0), "mythic": Color(1.0, 0.6, 0.2)}
# The Double Axe's: Storm and Harvester a level; Magnet pulls what is within
# this many of its reach, this fast; Ricochet looks this far for the next.
const STORM_STEP := 0.25
const HARVESTER_STEP := 0.5
const MAGNET_REACH := 2.5
const MAGNET_SPEED := 55.0
const RICOCHET_REACH := 140.0
# Axe Fury: kills to fill it.
const FURY_NEEDS := 15
const BULWARK_STEP := 0.15
# Thorns: half a swing a level, to every monster this near, at most this often.
const THORNS_SHARE := 0.5
const THORNS_REACH := 56.0
const THORNS_GAP_MSEC := 300
const EXECUTE_BELOW := 0.15
const MOMENTUM_STEP := 0.04
const MOMENTUM_MOST := 10
const SHRINE_CURSE := 0.15
const MIGHT_STEP := 0.15
const IRON_STEP := 0.08
const SWIFT_STEP := 0.08
const FORTUNE_STEP := 0.25
const BERSERK_DEALT := 1.4
const BERSERK_TAKEN := 1.2
# The ward: this share of your most health.
const WARD_SHARE := 0.4
# A level of Bloodletter bleeds half a swing more; Long Wave a quarter bigger.
const BLEED_STEP := 0.5
const WAVE_STEP := 0.25
const QUICK_FINISHER := 2
# EVERY CLASS ITS OWN (0.124.0): the mage's crit a level, Deep Crits; the
# Meteorite's Comet and Long Burn; the tank's aura a level, Bastion; the
# Dynamite's Cluster, Barrage and Short Fuse; the healer's shots a level and
# the fewest shots between fans.
const CRIT_STEP := 0.1
const DEEP_CRIT := 3.0
const COMET_FALL := 0.5
const LONGBURN_STEP := 0.5
const SEARING_STEP := 0.25
const BASTION_TAKEN := 0.8
const CLUSTER_CHANCE := 0.5
const BARRAGE_CHANCE := 1.0 / 7.0
const SHORT_FUSE := 0.5
const QUICK_HANDS_STEP := 0.12
const FAN_LEAST := 2
# Weapon attack -> the mythic weapon's name in BOONS' "weapon".
const WEAPONS := {ItemData.WeaponAttack.SPINNING_AXE: "axe", ItemData.WeaponAttack.METEOR: "meteor",
	ItemData.WeaponAttack.DYNAMITE: "dynamite"}

static var active: bool = false
static var levels: Dictionary = {}
# WHO IS PLAYING (0.124.0): the class (an upgrade with a "class" is only
# theirs) and the mythic weapon worn (a mythic's "weapon"). The run sets both
# before each pick (descentrun.gd _note_class()); the Descent began as the
# warrior's, so a warrior with the Double Axe until told otherwise.
static var class_now: String = "warrior"
static var weapon_now: String = "axe"
# THE WARD now and at most, and the floor's share of every hit (0.115.0).
static var ward: int = 0
static var ward_most: int = 0
static var floor_taken: float = 1.0
# STEP 2 (0.115.0): kills this room (Momentum), Second Wind spent this floor,
# a Shrine's price, and when Thorns last cut.
static var room_kills: int = 0
static var wind_used: bool = false
static var shrine_taken: float = 1.0
static var _thorns_at: int = -100000
# Axe Fury's kills so far.
static var fury: int = 0


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
	ward = 0
	ward_most = 0
	floor_taken = 1.0
	room_kills = 0
	wind_used = false
	shrine_taken = 1.0
	_thorns_at = -100000
	fury = 0
	class_now = "warrior"
	weapon_now = "axe"


static func new_floor() -> void:
	"""Down a floor: Second Wind back, the Shrines' price lifted."""
	wind_used = false
	shrine_taken = 1.0


static func ward_share() -> float:
	return WARD_SHARE + BULWARK_STEP * level("bulwark")


static func fill_ward(most_health: int, over: float = 1.0) -> void:
	"""The ward full again: ward_share() of `most_health`, times `over` (a
	Rest's half again). Nothing off a run."""
	if not active:
		return
	ward_most = maxi(0, roundi(float(most_health) * ward_share() * over))
	ward = ward_most


static func absorb(amount: int) -> int:
	"""How much of a hit the ward takes - the rest is the health's."""
	if not active or ward <= 0 or amount <= 0:
		return 0
	var took: int = mini(ward, amount)
	ward -= took
	return took


static func damage_factor() -> float:
	if not active:
		return 1.0
	return (1.0 + MIGHT_STEP * level("might")) * (BERSERK_DEALT if level("berserk") > 0 else 1.0) * momentum()


static func taken_factor() -> float:
	if not active:
		return 1.0
	return maxf(0.2, 1.0 - IRON_STEP * level("iron")) * (BERSERK_TAKEN if level("berserk") > 0 else 1.0) \
		* floor_taken * shrine_taken


static func speed_factor() -> float:
	if not active:
		return 1.0
	return (1.0 + SWIFT_STEP * level("swift")) * momentum()


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


static func offers(rng: RandomNumberGenerator, count: int = 3, at_least: String = "", axe: bool = false,
		one_mythic: bool = false, not_these: Array = []) -> Array:
	"""Up to `count` different upgrades not yet at their most, drawn by their
	rarity's weight - only `at_least` ("rare") or better if asked. Mythic
	ones only for a warrior wearing the Double Axe (`axe`); `one_mythic` (a
	keeper's pick) makes sure one is among them. A REROLL passes the cards it
	replaces as `not_these`, left out while there are enough others."""
	var floor_rank: int = maxi(0, RARITIES.find(at_least))
	var open: Array = []
	for id in ORDER:
		if level(id) < int(BOONS[id]["most"]) and RARITIES.find(rarity(id)) >= floor_rank \
				and (axe or rarity(id) != "mythic") and fits(id):
			open.append(id)
	var every: Array = open.duplicate()
	var fresh: Array = open.filter(func(id: String) -> bool: return not not_these.has(id))
	if fresh.size() >= count:
		open = fresh
	if axe and one_mythic:
		var mythics: Array = open.filter(func(id: String) -> bool: return rarity(id) == "mythic")
		# A keeper's reroll keeps its mythic even if the one on the table was
		# the last.
		if mythics.is_empty():
			mythics = every.filter(func(id: String) -> bool: return rarity(id) == "mythic")
		if not mythics.is_empty():
			var first: String = str(mythics[rng.randi_range(0, mythics.size() - 1)])
			open.erase(first)
			var rest: Array = offers_from(rng, open, count - 1)
			rest.insert(rng.randi_range(0, rest.size()), first)
			return rest
	return offers_from(rng, open, count)


static func fits(id: String) -> bool:
	"""This upgrade is for whoever is playing: anyone's, or their class's -
	a mythic only with its weapon on."""
	var boon: Dictionary = BOONS[id]
	if boon.has("class") and str(boon["class"]) != class_now:
		return false
	return rarity(id) != "mythic" or str(boon.get("weapon", "")) == weapon_now


static func weapon_for(attack: int) -> String:
	return str(WEAPONS.get(attack, ""))


# ---- every class's own (0.124.0) ----

static func crit_more() -> float:
	return CRIT_STEP * level("arcaneedge") if active else 0.0


static func triple_every(usual: int) -> int:
	return maxi(1, usual - level("spikestorm")) if active else usual


static func crit_mult(usual: float) -> float:
	return DEEP_CRIT if active and level("deepcrits") > 0 else usual


static func meteor_shower() -> bool:
	return active and level("shower") > 0


static func meteor_fall_scale() -> float:
	return COMET_FALL if active and level("comet") > 0 else 1.0


static func crater_scale() -> float:
	return 1.0 + LONGBURN_STEP * level("longburn") if active else 1.0


static func aura_scale() -> float:
	return 1.0 + SEARING_STEP * level("searing") if active else 1.0


static func bastion_scale(aura_on: bool) -> float:
	return BASTION_TAKEN if active and aura_on and level("bastion") > 0 else 1.0


static func bundle_chance(usual: float) -> float:
	return maxf(usual, CLUSTER_CHANCE) if active and level("cluster") > 0 else usual


static func barrage_chance(usual: float) -> float:
	return maxf(usual, BARRAGE_CHANCE) if active and level("barrage") > 0 else usual


static func fuse_scale() -> float:
	return SHORT_FUSE if active and level("shortfuse") > 0 else 1.0


static func shot_rate() -> float:
	return 1.0 + QUICK_HANDS_STEP * level("quickhands") if active else 1.0


static func fan_every(usual: int) -> int:
	return maxi(FAN_LEAST, usual - level("twinorbs")) if active else usual


static func warding_light(amount: int) -> void:
	"""Warding Light: a heal from your own aura fills your ward as much."""
	if active and level("wardinglight") > 0 and amount > 0:
		ward = mini(ward_most, ward + amount)


static func offers_from(rng: RandomNumberGenerator, from: Array, count: int) -> Array:
	"""`count` of `from`, different, drawn by their rarity's weight."""
	var open: Array = from.duplicate()
	var out: Array = []
	while out.size() < count and not open.is_empty():
		var total: int = 0
		for id in open:
			total += int(RARITY_WEIGHTS[rarity(id)])
		var roll: int = rng.randi_range(1, total)
		for id in open:
			roll -= int(RARITY_WEIGHTS[rarity(id)])
			if roll <= 0:
				out.append(id)
				open.erase(id)
				break
	return out


static func rarity(id: String) -> String:
	return str((BOONS.get(id, {}) as Dictionary).get("rarity", "common"))


# =============================================================================
# THE NEW FIVE'S HOOKS (0.115.0)
# =============================================================================

static func momentum() -> float:
	if not active or level("momentum") <= 0:
		return 1.0
	return 1.0 + MOMENTUM_STEP * mini(room_kills, MOMENTUM_MOST)


static func note_kill() -> void:
	if active:
		room_kills += 1
		fury = mini(FURY_NEEDS, fury + 1)


# =============================================================================
# THE DOUBLE AXE'S HOOKS (0.115.0)
# =============================================================================

static func axe_reach_scale() -> float:
	return 1.0 + STORM_STEP * level("storm") if active else 1.0


static func harvester_scale() -> float:
	return 1.0 + HARVESTER_STEP * level("harvester") if active else 1.0


static func magnet() -> bool:
	return active and level("magnet") > 0


static func ricochet() -> bool:
	return active and level("ricochet") > 0


static func twin_axes() -> bool:
	return active and level("twinaxes") > 0


static func fury_full() -> bool:
	return active and fury >= FURY_NEEDS


static func executed(hp: int, most: int, amount: int) -> int:
	"""A hit on a monster: all it has left if Execute is taken and it is
	under EXECUTE_BELOW of its most - else the hit as it was."""
	if not active or level("execute") <= 0 or most <= 0 or hp <= amount:
		return amount
	return hp if float(hp) <= float(most) * EXECUTE_BELOW else amount


static func second_wind() -> bool:
	"""A fall: true (and spent for the floor) if Second Wind catches it."""
	if not active or level("secondwind") <= 0 or wind_used:
		return false
	wind_used = true
	return true


static func thorns_cut(swing: float) -> int:
	"""What Thorns cuts each near monster for, from the player's swing."""
	return roundi(swing * THORNS_SHARE * level("thorns")) if active and level("thorns") > 0 else 0


static func thorns(player: Node2D) -> int:
	"""A hit landed on `player`: Thorns cuts every monster within
	THORNS_REACH, at most every THORNS_GAP_MSEC. Answers how many it cut."""
	if not active or level("thorns") <= 0 or player == null or not player.is_inside_tree():
		return 0
	var now: int = Time.get_ticks_msec()
	if now - _thorns_at < THORNS_GAP_MSEC:
		return 0
	_thorns_at = now
	var span: Vector2i = player.call("attack_damage_range") if player.has_method("attack_damage_range") else Vector2i.ZERO
	var cut: int = thorns_cut((span.x + span.y) / 2.0)
	if cut <= 0:
		return 0
	var count: int = 0
	for monster in player.get_tree().get_nodes_in_group("enemies"):
		if monster is Node2D and monster.has_method("take_damage") \
				and (monster as Node2D).global_position.distance_to(player.global_position) <= THORNS_REACH:
			monster.call("take_damage", cut)
			count += 1
	return count


static func level_text(id: String) -> String:
	var most: int = int(BOONS[id]["most"])
	if most == 1:
		return "Only one"
	return "New" if level(id) == 0 else "Level %d of %d" % [level(id) + 1, most]
