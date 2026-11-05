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
	"bloodletter": {"name": "Bloodletter", "does": "Your swings make them bleed", "most": 3, "rarity": "rare"},
	"longwave": {"name": "Long Wave", "does": "Your wave is a quarter bigger", "most": 3, "rarity": "rare"},
	"thorns": {"name": "Thorns", "does": "A hit on you cuts every monster near you", "most": 3, "rarity": "rare"},
	"execute": {"name": "Execute", "does": "A monster under 15% health dies to any hit", "most": 1, "rarity": "rare"},
	"momentum": {"name": "Momentum", "does": "Each kill in a room: +4% damage and speed, up to 10", "most": 1, "rarity": "rare"},
	"berserk": {"name": "Berserk", "does": "+40% damage, but take 20% more", "most": 1, "rarity": "epic"},
	"whirlwind": {"name": "Whirlwind", "does": "Your swing cuts all the way round you", "most": 1, "rarity": "epic"},
	"quickfinish": {"name": "Quick Finisher", "does": "The gold finisher every 2nd swing", "most": 1, "rarity": "epic"},
	"secondwind": {"name": "Second Wind", "does": "Once a floor, a fall leaves you standing, ward full", "most": 1, "rarity": "epic"},
	"twinaxes": {"name": "Twin Axes", "does": "Your Double Axe is thrown with a twin", "most": 1, "rarity": "mythic"},
	"storm": {"name": "Storm", "does": "Your spinning axe cuts a quarter wider", "most": 3, "rarity": "mythic"},
	"harvester": {"name": "Harvester", "does": "Your axe cuts half again harder coming home", "most": 3, "rarity": "mythic"},
	"magnet": {"name": "Magnet", "does": "Your spinning axe pulls monsters into it", "most": 1, "rarity": "mythic"},
	"ricochet": {"name": "Ricochet", "does": "Your thrown axe flies on to the next monster", "most": 1, "rarity": "mythic"},
}
const ORDER := ["might", "iron", "swift", "fortune", "bulwark", "bloodletter", "longwave", "thorns", "execute",
	"momentum", "berserk", "whirlwind", "quickfinish", "secondwind",
	"twinaxes", "storm", "harvester", "magnet", "ricochet"]
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

static var active: bool = false
static var levels: Dictionary = {}
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
				and (axe or rarity(id) != "mythic"):
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
