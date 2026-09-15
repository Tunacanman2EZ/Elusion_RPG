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

static func regen_rate_for(stat_max: int, percent_per_second: float,
		minimum_per_second: float) -> float:
	# Points per second for a pool of this size. The floor matters for classes
	# with small pools — a warrior with 0 max mana, or a 60-stamina pool, would
	# otherwise regenerate a fraction of a point per second and look broken.
	return maxf(minimum_per_second, float(stat_max) * percent_per_second)
