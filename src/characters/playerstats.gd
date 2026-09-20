# playerstats.gd — the arithmetic behind a character's numbers, with no character.
#
# Every function here is static and takes plain ints and floats. Nothing reaches
# a node, reads a member, or has a side effect. That is the whole point: this is
# the part of player.gd a test can call.
#
# WHY IT WAS SPLIT OUT
# --------------------
# player.gd was 66KB. Most of it genuinely needs a player in a world — movement,
# collision, animation, the pet in the scene tree. But scattered through it were
# eight pure formulas that decide how hard you hit, how fast you swing, how much
# damage you shrug off and how big your pools are, and those had never been
# checked by anything except playing the game and seeing whether it felt right.
#
# player.gd still exposes all the same methods. They now forward here. That was
# deliberate — moving the maths without moving the call sites means every
# existing caller, subclass and scene keeps working unchanged, so if something
# breaks after this split it is the arithmetic and nothing else.
#
# THE PRECONDITION EVERYTHING HERE SHARES
# ---------------------------------------
# Skill and character levels are assumed to be 1 or greater. They are not
# clamped, because this extraction copied the formulas exactly as they ran in
# player.gd and a refactor that quietly changes behaviour is worse than one that
# preserves a rough edge.
#
# Below 1 the curves invert: max_for(20, 5, 0) returns 15, and
# attack_damage_bonus(0) returns 0.995. Neither is reachable in play —
# CharacterData's sanitiser is what guarantees a level of at least 1, and the
# server owns `level` outright. That guarantee is load-bearing HERE, which is the
# reason this note exists rather than a clamp. If you ever relax the sanitiser,
# clamp these first.
class_name PlayerStats
extends RefCounted


# =============================================================================
# POOL MAXIMA
# =============================================================================

# Level 1 gets exactly the base, which is what the -1 is for. This has to match
# ClassData's documented formula and app.py's copy of it character for
# character — the server computes max_hp from the same two numbers and will
# disagree with the client if it ever drifts. See the CLASS STAT CURVES suite.
static func max_for(base: int, per_level: int, level: int) -> int:
	return base + (level - 1) * per_level


# =============================================================================
# DEFENSE TIERS
# =============================================================================
# Tiered damage reduction from the defense skill. Crossing into a new tier is a
# real milestone the game announces, not a number ticking up invisibly. Capped
# at 50% so a hit always still matters no matter how defended you are.
#
# NOTE: "poise" (resistance to knockback/interrupt at higher tiers) was
# discussed alongside this and deliberately left out — there is no knockback or
# hit-interrupt system for poise to resist, and attaching a perk to a mechanic
# that does not exist is not worth doing. Worth revisiting as its own feature if
# a hit-reaction system ever gets built.
#
# ORDERED HIGHEST FIRST. defense_tier() walks top-down and takes the first
# match, so re-ordering this array silently changes which tier everyone gets.
const DEFENSE_TIERS := [
	{"min_level": 80, "name": "Unbreakable", "reduction": 0.50},
	{"min_level": 60, "name": "Hardened",    "reduction": 0.40},
	{"min_level": 40, "name": "Veteran",     "reduction": 0.30},
	{"min_level": 20, "name": "Trained",     "reduction": 0.20},
	{"min_level": 1,  "name": "Novice",      "reduction": 0.10},
]


static func defense_tier(defense_level: int) -> Dictionary:
	# The highest tier this defense level qualifies for.
	for tier in DEFENSE_TIERS:
		if defense_level >= tier["min_level"]:
			return tier
	return DEFENSE_TIERS[-1]  # defense below 1 — corruption; treat as Novice.


# =============================================================================
# DAMAGE BONUSES
# =============================================================================
# +0.5% damage per point above 1, universal across every class. Each class keeps
# its own primary damage formula unchanged; these layer ON TOP, specifically for
# whichever stat is NOT already that class's primary driver, so attack and magic
# both matter for everyone without double-counting a stat a class already scales
# off. Warrior multiplies its attack-based melee by magic_damage_bonus();
# mage and healer multiply their magic-based spells by attack_damage_bonus();
# tank has no clear primary and applies both to its flat aura damage.
const DAMAGE_BONUS_PER_POINT := 0.005


static func attack_damage_bonus(attack_level: int) -> float:
	return 1.0 + (attack_level - 1) * DAMAGE_BONUS_PER_POINT


static func magic_damage_bonus(magic_level: int) -> float:
	return 1.0 + (magic_level - 1) * DAMAGE_BONUS_PER_POINT


# =============================================================================
# UNIVERSAL DAMAGE SCALING
# =============================================================================
# Attack AND magic both contribute to EVERY class's every attack, melee or
# spell, not just whichever skill that class's kit uses as its own scaling.
# This is what gives attack and magic XP real payoff across the whole roster:
# tank, mage and healer all earn attack XP, and without this that XP had no
# effect on their damage at all — only warrior's melee formula ever read it.
#
# Separate constants from DAMAGE_BONUS_PER_POINT above on purpose. That one is
# the cross-stat top-up a class applies to its off-stat; this is the multiplier
# every attack goes through regardless of class. They are tuned independently.
const ATTACK_DAMAGE_PERCENT_PER_LEVEL: float = 0.01
const MAGIC_DAMAGE_PERCENT_PER_LEVEL:  float = 0.01


static func damage_multiplier(attack_level: int, magic_level: int) -> float:
	return 1.0 \
		+ (attack_level - 1) * ATTACK_DAMAGE_PERCENT_PER_LEVEL \
		+ (magic_level - 1) * MAGIC_DAMAGE_PERCENT_PER_LEVEL


# =============================================================================
# WHAT A WEAPON ADDS
# =============================================================================
# A WEAPON ADDS TO THE CLASS'S OWN DAMAGE RATHER THAN REPLACING IT. Unarmed is
# still a real state with a real number, which is what makes the first weapon
# feel like something rather than like the game finally switching on.
#
# THE SPREAD IS THE POINT, not decoration. A number that is the same every
# swing reads as arithmetic; a number that moves reads as a hit landing well or
# badly, and it is the thing that makes an affix roll legible later — a loot
# system that rolls a weapon's damage is rolling the middle of this band, and
# nothing downstream has to change to accommodate it.
#
# ROLLED PER HIT, NOT PER SWING, and that falls out of where it is called from:
# warrior._try_damage() asks once per enemy it cleaves, so five targets get five
# rolls. The tank's aura rolls once per tick and shares it, because a tick is
# one event that happens to touch several things.
static func roll_weapon_damage(damage: int, spread: float) -> int:
	# A NON-WEAPON RETURNS 0 rather than 1. Every caller adds this to a class
	# base, so a floor of 1 would quietly hand a damage point to anyone holding
	# nothing at all, and the difference between unarmed and armed is exactly
	# what this is here to express.
	if damage <= 0:
		return 0

	var band: float = clampf(spread, 0.0, 0.9)
	var low: int = maxi(1, floori(float(damage) * (1.0 - band)))
	var high: int = maxi(low, ceili(float(damage) * (1.0 + band)))
	return randi_range(low, high)


static func weapon_damage_range(damage: int, spread: float) -> Vector2i:
	# The same band without rolling it, for a tooltip that wants to say
	# "15 - 25" rather than a number the player never actually sees.
	if damage <= 0:
		return Vector2i.ZERO
	var band: float = clampf(spread, 0.0, 0.9)
	var low: int = maxi(1, floori(float(damage) * (1.0 - band)))
	return Vector2i(low, maxi(low, ceili(float(damage) * (1.0 + band))))


# =============================================================================
# WHAT ARMOUR TAKES OFF
# =============================================================================
# A PERCENTAGE WITH DIMINISHING RETURNS, not a flat subtraction, and the
# numbers are why. A full ember kit is 167 armour and the hardest thing in the
# game hits for 35 — flat subtraction would make an end-game character
# immortal, and the only way to stop that is to inflate enemy damage until an
# under-geared player is deleted by the same attack.
#
#     reduction = armour / (armour + ARMOUR_HALF_POINT)
#
# The constant is the armour value at which incoming damage is HALVED, which is
# what makes it a number anyone can reason about. At 200 the ladder reads:
#
#     iron plate     28 ->  12%      iron cloth     15 ->   7%
#     jade plate     49 ->  20%      jade cloth     25 ->  11%
#     cobalt plate   79 ->  28%      cobalt cloth   43 ->  18%
#     amethyst      116 ->  37%      amethyst       62 ->  24%
#     ember plate   167 ->  45%      ember cloth    90 ->  31%
#
# Cloth sits at a little over half of plate the whole way up, which is the
# ladder the .tres files were already authored to — this constant did not
# invent that relationship, it just gives it a scale.
#
# IT STACKS MULTIPLICATIVELY WITH THE DEFENSE TIER above, not additively. Two
# additive percentages reach 100% and a character stops taking damage at all;
# multiplying them means each one removes a share of what is LEFT, so an ember
# warrior at Trained defense takes 0.80 x 0.55 = 44% of an incoming hit and no
# combination of the two ever reaches zero. take_damage()'s maxi(1, ...) floor
# is still there underneath as a last guarantee.
const ARMOUR_HALF_POINT: float = 200.0


static func armour_reduction(armour_value: int) -> float:
	if armour_value <= 0:
		return 0.0
	return float(armour_value) / (float(armour_value) + ARMOUR_HALF_POINT)


# =============================================================================
# AGILITY DRIVES ATTACK SPEED
# =============================================================================
# Agility used to do exactly one thing: move_speed = speed + (agility-1)*10. It
# was the only skill with no combat effect, so sprinting to level it bought
# movement and nothing else. This gives it a second job without touching
# movement.
#
# THE CAP IS THE IMPORTANT PART. Callers divide a cooldown by this. An uncapped
# stat eventually divides by a large enough number to make that cooldown
# effectively zero — an attack every frame, which breaks animations, spawns
# projectiles faster than they despawn, and is nobody's idea of a fun build.
# 2.0 means "at best, twice as fast as base", reached at agility 101 and never
# exceeded.
const AGILITY_ATTACK_SPEED_PERCENT_PER_LEVEL: float = 0.01
const MAX_ATTACK_SPEED_MULTIPLIER: float = 2.0


static func attack_speed_multiplier(agility_level: int) -> float:
	# DIVIDE a cooldown by this. Do not multiply a rate by it and forget the cap.
	var multiplier: float = 1.0 + (agility_level - 1) * AGILITY_ATTACK_SPEED_PERCENT_PER_LEVEL
	return clampf(multiplier, 1.0, MAX_ATTACK_SPEED_MULTIPLIER)


# =============================================================================
# SKILL XP
# =============================================================================
# Separate from GameConstants.xp_needed_for_level(), which is the CHARACTER
# curve the server also computes. This one is per-skill, client-only, and grows
# faster (1.18 against 1.15) because there are six skills competing for the same
# play time.
const SKILL_XP_BASE: int = 100
const SKILL_XP_FACTOR: float = 1.18


static func xp_needed_for_skill(skill_level: int, base: int = SKILL_XP_BASE,
		factor: float = SKILL_XP_FACTOR) -> int:
	return int(base * pow(factor, skill_level - 1))


# =============================================================================
# REGEN
# =============================================================================

# THE THREE NUMBERS THAT DECIDE HOW FAST YOU RECOVER, and they live here rather
# than as bare literals on player.gd's exports because the SERVER now needs
# them.
#
# PUT /api/player/status reconciles any rise in hp, mana or stamina against
# what regeneration could plausibly have produced since the last write - see
# _report_unexplained_heals() in app.py. To do that it has to know the rate,
# and until these were constants the only way to get it was to retype 0.0167
# into Python and hope. This project already has that scar: the XP formula
# lived in two places, they drifted, and the sanitiser started overwriting
# honest saves with garbage. gameconstants.gd exists because of it.
#
# So: constants here, player.gd's exports default to them, exportgamedata.gd
# carries them to the server. One number, three readers, no copies.
#
# 0.0167 is about 1/60, so an empty bar fills in roughly a minute at any level.
const REGEN_PERCENT_PER_SECOND: float = 0.0167

# Floor for small pools, set to the old flat rate so nothing regenerates slower
# than it did before percentages replaced it - only faster.
const REGEN_MINIMUM_PER_SECOND: float = 1.0

# Seconds of doing NOTHING before regeneration starts; any action resets it.
# Regen is strictly a between-fights mechanic - potions are what recover you
# during one. See player.gd::_set_active().
#
# THE SERVER CANNOT USE THIS YET, and that is worth stating. It has no idea
# whether you stood still, so it allows regeneration for the whole elapsed
# window: the most generous reading, and therefore the safe one for a check
# that must never fire on honest play. Exported anyway, because the moment the
# server can see movement this is the number that makes the allowance tight
# rather than merely correct.
const REGEN_IDLE_THRESHOLD: float = 1.0


static func regen_rate_for(stat_max: int,
		percent_per_second: float = REGEN_PERCENT_PER_SECOND,
		minimum_per_second: float = REGEN_MINIMUM_PER_SECOND) -> float:
	# Points per second for a pool of this size. The floor matters for classes
	# with small pools — a warrior with 0 max mana, or a 60-stamina pool, would
	# otherwise regenerate a fraction of a point per second and look broken.
	return maxf(minimum_per_second, float(stat_max) * percent_per_second)
