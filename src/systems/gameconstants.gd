# gameconstants.gd — game-wide tuning constants in one place for easy balancing.
# registered as an autoload singleton (named GameConstants), so any script
# reads e.g. GameConstants.REVIVE_COST without importing anything.
#
# put numbers here that (a) are referenced in more than one place, or
# (b) you'll want to tune during balancing without hunting through scripts.
extends Node


# =============================================================================
# CURRENCY / DEATH
# =============================================================================

# lusions required to revive at the game-over screen.
const REVIVE_COST: int = 20

# a duplicate pet (rolled but already owned) converts to this many lusions —
# deliberately equal to REVIVE_COST so a dupe pet is exactly one free revive.
const DUPE_PET_LUSIONS: int = 20


# =============================================================================
# PROGRESSION
# =============================================================================

# XP required to advance FROM `level` to the next one.
#
# THIS LIVES HERE BECAUSE IT USED TO LIVE IN TWO PLACES AND THEY DRIFTED APART.
#
# player.gd's gain_xp() computed the curve for real play. characterdata.gd's
# anti-tamper sanitizer recomputed it independently to detect edited saves.
# When the live formula was changed away from doubling — which overflowed
# int64 somewhere around level 58 — to this 1.15 growth curve, the sanitizer
# was not changed with it. It still expected doubling, decided the honest saved
# value was tampered with, and OVERWROTE it on every single load.
#
# At level 10 that turned a real requirement of 351 XP into 51,200. At level 20
# it turned 1,636 into 52,428,800. And because the rewritten value genuinely
# differed from what had been loaded, every load was also marked dirty — which
# is the "save rewritten on every login" symptom that _values_differ() was
# written to cure. That fix was correct; this was a second, independent cause
# sitting behind it.
#
# Both callers now read this one function. There is one curve.
const XP_BASE: float = 100.0
const XP_GROWTH: float = 1.15


static func xp_needed_for_level(level: int) -> int:
	# Level 1 needs XP_BASE; each level after multiplies by XP_GROWTH.
	# At level 99 this is roughly 89 million for that single level — large, but
	# comfortably inside int64, which the old doubling curve was not.
	# max() guards a corrupted level of 0 or below producing a fractional power.
	return int(XP_BASE * pow(XP_GROWTH, max(level - 1, 0)))


# =============================================================================
# LOOT DROPS (centralize here as you tune; baseenemy can read these later)
# =============================================================================

# how long a loot bag survives on the ground before auto-despawning, if it
# still has items left in it after the player took some.
const LOOT_BAG_DESPAWN_SECONDS: float = 20.0
