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

# WHAT ONE LUSION IS WORTH IN GOLD.
#
# Needed the moment two currencies are added into one number - the high score
# is the only place that does it - and stated once here rather than inlined
# where they are added, because the day it is tuned it must move everywhere.
#
# WHERE 1000 COMES FROM. It is one gold coin on the denomination ladder, which
# makes the premium currency legible against the thing players actually count:
# a lusion is a gold coin. It also lands the two revive paths near each other
# in cost - the lusion revive is 20 lusions, so 20,000 gold, and the gold
# revive takes 80% of what you hold, which is the same bill for somebody
# carrying about 25,000. Choosing between them is then a real choice.
#
# NOT AN EXCHANGE RATE PLAYERS CAN TRADE AT, and nothing lets them. It is the
# weight used when one number has to describe both.
const LUSION_GOLD_VALUE: int = 1000

# a duplicate pet (rolled but already owned) converts to this many lusions —
# deliberately equal to REVIVE_COST so a dupe pet is exactly one free revive.
const DUPE_PET_LUSIONS: int = 20

# THE OTHER WAY OUT OF A DEATH: pay in gold instead of lusions.
#
# A FRACTION, NOT A PRICE, and that is the whole idea. A flat figure is either
# unaffordable at level 3 or pocket change at level 30, and death is supposed to
# sting the same amount at both ends. Eighty percent of everything you own
# always hurts, and — because it is a share of what you HAVE — it can always be
# paid. Nobody is ever stranded on the death screen with no way back.
#
# OF EVERYTHING, carry and bank together. Banked gold is the part death cannot
# touch, which is exactly why it is worth spending here: it is the only pile
# still standing when you are looking at this screen.
#
# THE GOLD IS NOT MOVED, IT IS DESTROYED, and it lands on the kingdom board
# beside the trade tax. A sink nobody can see is a tax; a sink with a
# scoreboard is a contribution. See gold_ledger and /api/economy/kingdom.
const REVIVE_GOLD_RATE: float = 0.80

# THE FLOOR UNDER THAT SHARE, and it is the one place this design gives
# something up on purpose.
#
# The share alone has a hole at the bottom. Eighty percent of the thirty gold a
# fresh character is carrying is twenty-four gold, which is not a death, it is a
# toll — and it got CHEAPER the less you had, so the cheapest way out of dying
# broke was to die again rather than walk home. A sink that rewards the
# behaviour it is meant to discourage is not a sink.
#
# 100 IS ONE COPPER STACK SHORT OF A SILVER-STACK-AND-CHANGE, which in practice
# is two or three tier-2 kills. Deaths that cost two kills are felt; deaths that
# cost twenty-four gold are not.
#
# WHAT IT COSTS, IN THREE BANDS — and it is three, not two, which is the part
# that is easy to get wrong. The share drops below the floor at 125 gold, but
# the gold route only CLOSES at 100:
#
#   under 100    the price is more than you hold  → the gold route is refused
#   100 to 123   the floor sits above the share   → you pay 100, not the share
#   124 and up   the share sits above the floor   → nothing changed at all
#
# So the old guarantee that this route could always be paid no longer holds,
# but only for the bottom hundred gold. That is deliberate — the lusion revive
# and the walk are both still there — and it is why this constant has a comment
# this long.
#
# ABOVE THE FLOOR NOTHING MOVES. At 5,000 gold the share is 4,000 and this
# number never enters the arithmetic.
const REVIVE_GOLD_MINIMUM: int = 100


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
#
# 1,250 x 1.27, SET BY THE PACE, NOT BY FEEL. It was 100 x 1.15, which with the
# element bands' rewards reached level 22 in about ten minutes. At about five
# kills a minute in the band that matches your level, this curve gives level 5
# in 15 minutes, 10 in under an hour, 16 in about 3 hours and 22 in about 8 -
# the plan in the Economy and Progression doc. _test_the_game_has_a_pace
# recomputes those hours from the enemy data and fails if they drift.
#
# NO LEVEL CAP. Past 22 the dark band keeps paying and the curve keeps rising;
# CharacterData.MAX_LEVEL (99) is a sanity clamp on a loaded save, not a
# design limit, and at this growth level 99 is still inside int64.
const XP_BASE: float = 1250.0
const XP_GROWTH: float = 1.27


# NOT static, deliberately. Both callers reach this through the GameConstants
# AUTOLOAD — an instance — and calling a static function on an instance makes
# Godot warn on every reload. This file only ever exists as that one autoload,
# so an instance method is the honest signature and the warning goes away
# without either caller changing.
func xp_needed_for_level(level: int) -> int:
	# Level 1 needs XP_BASE; each level after multiplies by XP_GROWTH.
	# At level 99 this is roughly 19 trillion for that single level — absurd,
	# but inside int64 (9.2 quintillion), which the old doubling curve was not.
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
# RARITY — what a tier looks like
# =============================================================================
# One name and one colour per item tier, read by slot borders, the tooltip and
# the loot bag's glow. Nothing marked an item as rare before this: an Ember
# Cuirass sat in a bag looking exactly like an iron one.
#
# THE COLOURS ARE THE MATERIALS. Gear tiers were already named iron, jade,
# cobalt, amethyst and ember, so rarity follows them: an ember piece, its name
# and its bag's glow are all the same orange. Potions and fish carry tiers too
# and take the same colours, so a greater potion reads as a legendary one.
#
# Indexed by tier; index 0 is there so tier 1 can be read directly, and every
# tier past the end is Mythic (cooked fish reach tier 8).
const RARITY_NAMES: Array[String] = [
	"Common", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic",
]
const RARITY_COLOURS: Array[Color] = [
	Color(0.80, 0.80, 0.78), Color(0.80, 0.80, 0.78),  # iron grey
	Color(0.36, 0.86, 0.48),                           # jade
	Color(0.36, 0.64, 1.00),                           # cobalt
	Color(0.78, 0.48, 1.00),                           # amethyst
	Color(1.00, 0.62, 0.20),                           # ember
	Color(1.00, 0.38, 0.38),                           # mythic
]

# The lowest tier that draws a coloured frame round its slot. COMMON DRAWS
# NONE: it is most of what a player owns, and outlining it would put a border
# on everything and so mark nothing.
const RARITY_FRAME_MIN_TIER: int = 2

# The lowest tier that makes a loot bag glow on the ground. Pets count as
# legendary: they were the one rare drop that already had a beam.
const RARE_GLOW_MIN_TIER: int = 4

# THE MYTHIC TIER, AND HOW RARE IT IS. Tier 6 holds the weapons that bring
# their own attack: the Meteorite, the Double Axe and Dynamite. No enemy's
# tier_odds reaches them. Instead every enemy that pays rewards has a "one in
# N" roll of its own, made by the server at the kill (gamedata.roll_mythic),
# and a win is the killer's own class's weapon.
#
# Decided by the owner on day 2: regular mobs and bosses both drop them, "mixed
# rarity but it should be super rewarding getting 1". So the tougher the enemy,
# the better the odds, keyed on max_loot_tier. A boss is
# EnemyData.slots_are_gear.
#
# What that comes to, at the five kills a minute the level curve is built on:
# - The dark band is about one in 65 hours.
# - Light and wind are a lottery ticket.
# - The Crowned is about one in 8 hours, at a kill every three minutes or so
#   with its two-minute respawn. It is set apart with
#   EnemyData.mythic_odds_override, as are the small slimes.
const MYTHIC_TIER: int = 6
const MYTHIC_ODDS_BOSS_BY_TIER := {6: 300, 5: 600}
const MYTHIC_ODDS_BY_TIER := {5: 20000, 4: 50000, 3: 100000, 2: 250000, 1: 500000}

# A bag with a mythic in it stays on the ground this long, instead of
# LOOT_BAG_DESPAWN_SECONDS. A boss fight runs past 45 seconds, and losing the
# rarest drop in the game to a timer would be the opposite of rewarding. It
# stays under the server's LOOT_BAG_TTL_SECONDS (600) for the reason given
# above LOOT_BAG_DESPAWN_SECONDS.
const MYTHIC_BAG_DESPAWN_SECONDS: float = 300.0


# QUALITY ROLLS. A dropped piece of gear rolls every stat it has - damage,
# armour, max health, max mana, the damage bonus - each on its own, from
# QUALITY_LOW to QUALITY_HIGH percent of the number in its .tres, most often
# near 100. One drop in QUALITY_PERFECT_ODDS is Perfect instead: every stat at
# QUALITY_PERFECT, and "Perfect" in front of its name. A piece bought from the
# shop rolls the same way, at the till: the shelf shows "?" for its stats and
# the roll is revealed when it is bought (the owner, 5 Oct: "item stats say ?
# and are revealed upon buying in shop only"), at the shelf's price whatever
# it rolls.
#
# The owner, 5 Oct: "random stats on all items because it gives loot a better
# value if a rare max roll", with the range, the Perfect and "each stat
# separately" chosen the same day.
#
# THE ROLL IS PART OF THE ITEM ID. "jadechest~a104h96" is a Jade Cuirass with
# its armour at 104% and its health at 96%: QUALITY_MARK, then one letter from
# QUALITY_FIELDS and a percent for every stat the piece has, in that order. The
# server rolls it (gamedata.roll_quality) and ItemRegistry.get_item() reads it,
# handing back a copy of the piece with those numbers - so everything that
# reads damage or bonus_max_hp off an ItemData gets the rolled number without
# knowing a roll exists. The server reads all of these through gamedata.json.
#
# A ROLL CHANGES WHAT A PIECE DOES, NOT ITS PRICE. value stays the .tres's, so
# the shop pays the same for any roll; a Perfect is worth what a player will
# give for it.
const QUALITY_LOW: int = 85
const QUALITY_HIGH: int = 115
const QUALITY_PERFECT: int = 120
const QUALITY_PERFECT_ODDS: int = 100
const QUALITY_MARK: String = "~"
const QUALITY_FIELDS: Array = [
	["d", "damage"],
	["a", "armor_value"],
	["h", "bonus_max_hp"],
	["m", "bonus_max_mana"],
	["p", "bonus_damage_percent"],
]
# A Perfect piece's name, in the tooltip and on its slot's frame.
const QUALITY_PERFECT_COLOUR: Color = Color(1.0, 0.86, 0.35)


# THE LANDS EACH GEAR TIER COMES FROM, indexed by tier like the two above. The
# element bands decide what drops where - light and wind creatures drop up to
# iron, water and ice up to jade, earth cobalt, fire amethyst, dark ember - and
# the shop heads each tier's shelf with the lands a player fights in for it, so
# saving for the next set reads as a place to go. The suite holds this against
# data/enemies/*.tres (every normal of these elements drops up to this tier), so
# it cannot drift away from the drops it describes.
const TIER_ELEMENTS: Array = [
	[],
	[Element.Type.LIGHT, Element.Type.WIND],
	[Element.Type.WATER, Element.Type.ICE],
	[Element.Type.EARTH],
	[Element.Type.FIRE],
	[Element.Type.DARK],
]

# Gear tiers are named for their material. The shop sells iron to amethyst;
# ember (legendary) is found, never bought - decided by the owner on day 1.
const TIER_MATERIALS: Array[String] = ["", "Iron", "Jade", "Cobalt", "Amethyst", "Ember"]


func tier_lands(tier: int) -> String:
	"""'Water and Ice' for tier 2 - the elements that drop this tier, said as
	the lands a player goes to. Empty past the table."""
	if tier < 1 or tier >= TIER_ELEMENTS.size():
		return ""
	var words := PackedStringArray()
	for element in TIER_ELEMENTS[tier]:
		words.append(Element.name_for(int(element)).capitalize())
	return " and ".join(words)


func rarity_name(tier: int) -> String:
	return RARITY_NAMES[clampi(tier, 0, RARITY_NAMES.size() - 1)]


func rarity_colour(tier: int) -> Color:
	return RARITY_COLOURS[clampi(tier, 0, RARITY_COLOURS.size() - 1)]


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


# =============================================================================
# THE KINGDOM TAX
# =============================================================================
# Every player-to-player trade is taxed, and the tax is DESTROYED rather than
# paid to anyone. That is the whole point: it is the only structural gold sink
# in the game.
#
# WHY A TAX AND NOT A FEE TO AN NPC. A fee that lands in somebody's pocket moves
# gold; it does not remove it. Supply keeps climbing and the only question is
# who is holding it. Burning it is what lets total supply find an equilibrium
# instead of growing without bound - at a faucet rate F, a tax rate r and a
# trade velocity v, supply settles near F / (r * v) rather than at infinity.
#
# THE RATE IS THE ONE DIAL. Raise it and the world drains faster and players
# trade less; lower it and supply climbs. 0.05 is a starting position, not a
# measurement: velocity cannot be known before there are players to observe, and
# v is half of what sets the equilibrium. Expect to retune this against a real
# server, and retune it HERE - /api/economy/supply is the instrument for it.
const KINGDOM_TAX_RATE: float = 0.05

# THE FLOOR, AND IT IS WHAT STOPS TRADE-SPLITTING.
#
# Round a 5% tax down and any trade under 20 gold of value is free. Free trades
# are a laundering channel: move 10,000 gold as a thousand untaxed dribbles and
# the sink never fires. Rounding UP with a floor of 1 makes splitting strictly
# more expensive than not splitting - one trade worth 100 costs 5, the same 100
# as ten trades of 10 costs 10 - so the cheapest way to move value is the honest
# one. Same rule and same reason as shop_price().
const KINGDOM_TAX_MINIMUM: int = 1


# =============================================================================
# NUMBER FORMATTING
# =============================================================================

func commas(amount: int) -> String:
	# Thousands separators, because the economy grew past the point where a bare
	# run of digits is readable.
	#
	# WHY THIS IS SUDDENLY WORTH AN AUTOLOAD FUNCTION. It used to live as a
	# private _commas() in kingdomboard.gd, with a comment saying a shared helper
	# was not worth the indirection for one call site. That was true when the
	# kingdom board held the only genuinely large number in the game. It stopped
	# being true when gear was rescaled x8 and the jackpot dice started paying
	# six figures: "Gold: 131760" is now a number a player reads in the backpack,
	# the bank, the shop and the HUD, and four hand-rolled copies of this loop is
	# four places for it to drift.
	#
	# GDScript's String has no thousands separator and % does not do grouping, so
	# this is built by hand. Negative amounts keep their sign outside the groups
	# (-1,204, not -,1204), which matters because bank and trade deltas are shown
	# signed.
	var digits: String = str(absi(amount))
	var out: String = ""
	var count: int = 0
	for index in range(digits.length() - 1, -1, -1):
		out = digits[index] + out
		count += 1
		if count % 3 == 0 and index > 0:
			out = "," + out
	return ("-" + out) if amount < 0 else out


func short_number(amount: int) -> String:
	# "9,391", "12K", "998K", "1M", "1.2M", "45M", "1.5B" - for a number in a
	# small space, where "1,007,892" is seven digits nobody reads. Under ten
	# thousand is written out whole, because "9.4K" hides what "9,391" says in
	# the same room. Rounded DOWN, so 1,999,999 is "1.9M": a short number
	# never claims more than is there. Where the exact figure matters, show
	# commas() beside it or in a tooltip.
	var size: int = absi(amount)
	var minus: String = "-" if amount < 0 else ""
	if size < 10_000:
		return commas(amount)
	var units: Array = [[1_000_000_000, "B"], [1_000_000, "M"], [1_000, "K"]]
	for unit in units:
		var step: int = unit[0]
		if size < step:
			continue
		@warning_ignore("integer_division")
		var whole: int = size / step
		# A TENTH ONLY UNDER TEN: "1.2M" says something "1M" does not, and
		# "45.6M" is three digits again.
		if whole >= 10:
			return "%s%d%s" % [minus, whole, unit[1]]
		@warning_ignore("integer_division")
		var tenths: int = (size % step) / (step / 10)
		if tenths == 0:
			return "%s%d%s" % [minus, whole, unit[1]]
		return "%s%d.%d%s" % [minus, whole, tenths, unit[1]]
	return commas(amount)


func counted(amount: int, word: String, many: String = "") -> String:
	# "1 day" / "3 days" / "1,204 lusions". A count and the word that goes with
	# it, so "1 days ago", "1 seconds" and "between 1 of you" cannot be written
	# again by formatting a number into a plural that was typed once. `many` is
	# for a plural that is not word + "s".
	var noun: String = word if amount == 1 else (many if many != "" else word + "s")
	return "%s %s" % [commas(amount), noun]


func gold_text(amount: int) -> String:
	# "1 gold" / "1,204 gold". One place decides the noun so a stray "1 golds"
	# cannot appear in one panel and not another.
	return "%s gold" % commas(amount)


# =============================================================================
# THE COIN LADDER, FOR DISPLAY
# =============================================================================
#
# WHICH COIN A BALANCE LOOKS LIKE. Eight denominations exist, they are drawn,
# priced and dropped - and until now the only place a player ever saw one was
# the moment it landed in the backpack. Every gold figure in the UI sat beside
# the same single icon whether it read 40 or 131,760.
#
# THE RULE IS THE LARGEST COIN THAT FITS, which is the first coin make_change()
# would reach for. 40 gold is a copper stack; 1,760 is a gold coin; 131,760 is
# platinum. That makes the ladder legible from the HUD rather than from a wiki,
# and it means the icon changes as you get richer, which is the whole reward.
#
# READ OFF ItemRegistry, NOT A TABLE HERE. Each coin's value lives on its
# ItemData where it belongs, and the ORDER lives on BaseEnemy.GOLD_DENOMINATION_
# IDS where the server reads it from. A third copy in this file is a third thing
# to keep in step - the exact drift exportgamedata.gd exists to prevent.

# Built once on first use, because it walks eight resources and the answer only
# changes when the game is rebuilt.
var _gold_ladder: Array = []


func _gold_ladder_cached() -> Array:
	# [[value, item_id], ...] richest first.
	if not _gold_ladder.is_empty():
		return _gold_ladder
	if not is_instance_valid(ItemRegistry):
		return []
	var built: Array = []
	for item_id in BaseEnemy.GOLD_DENOMINATION_IDS:
		var data: ItemData = ItemRegistry.get_item(String(item_id))
		# has_item() first would be a second lookup; get_item() answering null
		# is the same question asked once. A missing coin is skipped rather
		# than faked - an icon for a denomination that does not exist would be
		# a lie the player cannot check.
		if data == null:
			continue
		var worth: int = int(data.value)
		if worth > 0:
			built.append([worth, String(item_id)])
	built.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	_gold_ladder = built
	return _gold_ladder


func gold_denomination_for(amount: int) -> String:
	# The item_id of the largest coin that fits in `amount`, or the smallest
	# coin on the ladder when nothing does.
	#
	# EMPTY POCKETS GET THE COPPER COIN rather than no icon at all. A missing
	# icon reads as a broken panel; a copper coin reads as being broke, which is
	# the true and more useful statement.
	var ladder: Array = _gold_ladder_cached()
	if ladder.is_empty():
		return ""
	for rung in ladder:
		if amount >= int(rung[0]):
			return String(rung[1])
	return String(ladder[ladder.size() - 1][1])


func gold_icon_for(amount: int) -> Texture2D:
	# The coin's own icon, straight off its ItemData - the same art the backpack
	# draws, so the thing in your purse and the thing on the label cannot end up
	# being different pictures.
	var item_id: String = gold_denomination_for(amount)
	if item_id == "":
		return null
	var data: ItemData = ItemRegistry.get_item(item_id)
	return data.icon if data != null else null


func apply_gold_icon(node: Node, amount: int) -> bool:
	# Point a TextureRect at the coin for this balance. Returns whether it did.
	#
	# TAKES A Node AND CHECKS, because the panels that call this find their icon
	# by name in a scene the designer owns, and that scene is edited in Godot.
	# A null node or a node that is not a TextureRect is a scene that has moved
	# on, not a crash - the label beside it still says the number.
	if node == null or not (node is TextureRect):
		return false
	var texture: Texture2D = gold_icon_for(amount)
	if texture == null:
		return false
	(node as TextureRect).texture = texture
	return true
