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


# NOT static, deliberately. Both callers reach this through the GameConstants
# AUTOLOAD — an instance — and calling a static function on an instance makes
# Godot warn on every reload. This file only ever exists as that one autoload,
# so an instance method is the honest signature and the warning goes away
# without either caller changing.
func xp_needed_for_level(level: int) -> int:
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
#
# WAS 20.0, which is shorter than a fight. A pull that ran long meant the bags
# worth opening - the two and three item ones dropped early - timed out while
# the single-coin bags dropped last survived, so what you actually collected
# was biased toward whatever died most recently rather than what dropped best.
#
# HARD CEILING IS THE SERVER'S LOOT_BAG_TTL_SECONDS (600), and this must stay
# well under it. The server deletes the row past its TTL and answers a take
# with a 410, so a client that outlived it would leave a bag sitting there,
# openable, that errors the moment you touch it. Losing a bag to the despawn
# animation is fair; losing it to a phantom is not. Raise both together if 45
# is still not enough.
const LOOT_BAG_DESPAWN_SECONDS: float = 45.0


# =============================================================================
# FISHING AND COOKING
# =============================================================================
# THESE TWO LIVE HERE BECAUSE THE SERVER DECIDES WITH THEM.
#
# /api/fishing/catch and /api/cooking/cook own the rolls - a client that decided
# its own catch or its own burn would simply never fail. But gamedata.py's
# header is equally clear that it restates nothing: "if a value is not in the
# JSON, that is a bug in the exporter, not something to paper over with a
# default." A burn curve invented in Python is a balance number living where
# nobody editing the game would look for it.
#
# So they are authored here, exported by exportgamedata.gd, and read by both
# sides. cookingscreen.gd shows the player the chance; the server rolls it.

# Chance a fish burns when cooked at exactly its cook_level, sliding to zero at
# its cook_mastery_level. The whole reason the cooking skill has teeth.
const COOK_BURN_MAX: float = 0.40

# Fishing levels needed to reach one fish tier beyond what the rod alone allows.
# The rod sets the floor, the skill raises it: an iron rod at fishing 60 reaches
# the same water as a cobalt rod at fishing 20.
const FISHING_TIER_PER_LEVEL: int = 20

# Per-skill XP curve, mirroring the six calls in player.gd's gain_*_xp():
# attack 1.25, defense 1.20, agility 1.15, magic 1.25, fishing 1.12,
# cooking 1.10, all on a base of 100.
#
# EXPORTED BECAUSE THE SERVER LEVELS TWO OF THEM NOW. /api/fishing/catch and
# /api/cooking/cook grant XP against rows the server owns, so they need the same
# thresholds the client draws its bars from. The other four are still granted
# client-side and are here for completeness — when they move, the curve is
# already where the server can read it.
#
# EACH SKILL HAS ITS OWN FACTOR, and that is the whole reason this is a
# dictionary rather than one number. Cooking at 1.10 climbs noticeably faster
# than attack at 1.25; a single shared growth would flatten six deliberate
# pacing decisions into one.
const SKILL_XP_BASE: int = 100
const SKILL_XP_GROWTH: Dictionary = {
	"attack": 1.25,
	"defense": 1.20,
	"agility": 1.15,
	"magic": 1.25,
	"fishing": 1.12,
	"cooking": 1.10,
}
