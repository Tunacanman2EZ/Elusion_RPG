# enemydata.gd — one enemy's reward profile, as data.
#
# Same pattern as ItemData: a Resource authored in the editor, saved as a .tres
# under data/enemies/, and read by whatever needs it. Drop a new .tres in that
# folder and a new enemy exists.
#
# WHY THIS EXISTS
# ---------------
# These numbers used to live inside each enemy's _ready(). bushmage.gd set
# max_loot_tier = 3 and pet_drop_id = "petmage" as statements, executed at spawn
# time, on the player's machine.
#
# That was fine while the client decided what a kill was worth. It stops being
# fine the moment the SERVER has to decide, because there is then nothing to
# read: an enemy's value is the result of running client code, and the only way
# to learn it is to run that code. The export tool proved it — it instantiated
# every enemy scene, found the scripts had not run, and dutifully wrote out five
# identical enemies with BaseEnemy's bare defaults.
#
# So the rewards become data. Godot authors it, the exporter reads it into
# gamedata.json, and the Flask server reads that. One authored source, two
# consumers, nothing restated.
#
# WHAT IS DELIBERATELY *NOT* HERE
# -------------------------------
# Combat tuning — attack_cooldown, attack_range, flee_range, movement. Those
# stay in each enemy's _ready(). They are client simulation, the server has no
# use for them yet, and some are computed rather than constant (bushmage's
# attack_range is derived from its hold distance). Moving them would widen the
# change for no benefit on either side.
#
# The line is: if the server needs it to decide what a kill is worth, it lives
# here. Otherwise it stays in the script.
#
# ONE RESOURCE PER PAYABLE VARIANT, NOT PER SCENE
# -----------------------------------------------
# poisonslime.tscn is one scene and two different enemies. The small one is a
# 35 hp mob that drops loot and carries both slime pets; the large one is 220 hp
# and drops nothing at all, because it never dies — _die() routes it into
# _begin_split() and it is consumed. Its whole worth walks away as four smalls.
#
# They get two resources. The server has to be able to tell them apart, and a
# name is the only way it ever will.
@tool
extends Resource
class_name EnemyData


# =============================================================================
# IDENTITY
# =============================================================================

# The id the client reports when it claims a kill, and the key the server looks
# up. Must be unique across every .tres in data/enemies/ — the exporter treats a
# duplicate as a hard error, because one of the two would otherwise simply
# vanish from the server's roster with nothing to indicate it.
#
# Convention: matches the filename. Nothing enforces that, but a mismatch makes
# the resource very hard to find from a log line.
@export var enemy_id: String = ""

# For debug output and, later, a bestiary. Never used for lookup.
@export var display_name: String = ""


# =============================================================================
# REWARDS
# =============================================================================

# FALSE for anything that cannot be killed for profit — right now that is the
# large slime alone.
#
# This is not documentation. The server refuses a kill claim naming an enemy
# with grants_rewards = false, so a client that reports "I killed a large
# poison slime" gets a 400 rather than a payout for something the game does not
# actually let you kill.
@export var grants_rewards: bool = true

@export var xp_reward: int = 20
@export var attack_xp_reward: int = 5


# =============================================================================
# LOOT
# =============================================================================

# Chance a loot bag drops at all, 0.0–1.0. A pet win spawns a bag regardless.
@export_range(0.0, 1.0, 0.01) var bag_drop_chance: float = 0.30

# Nothing above this tier can drop, and gold scales with it. Also the default
# source of the pet odds — see pet_odds_override below.
@export var max_loot_tier: int = 1

# How many item slots the bag rolls for, and the chance each one fills.
@export var max_item_slots: int = 3
@export_range(0.0, 1.0, 0.01) var slot_fill_chance: float = 0.15


# =============================================================================
# PETS
# =============================================================================

# The companion this enemy can drop. Empty means it drops none.
#
# This must match the item_id INSIDE the pet's .tres, not its filename. The roll
# checks the registry and bails silently on a mismatch: no error, no drop,
# nothing to chase. That is exactly how the slime pet stayed undroppable.
@export var pet_drop_id: String = ""

# An optional SECOND pet. A winning roll awards one or the other, never both —
# two independent rolls would let one kill hand over the rare pet and the common
# one together, which would make the rare one feel worthless the moment it
# happened.
@export var rare_pet_drop_id: String = ""

# Probability the rare pet is chosen instead of the common one, given that a pet
# was already won.
@export_range(0.0, 1.0, 0.01) var rare_pet_chance: float = 0.25

# "One in N" pet odds. Leave at 0 to use BaseEnemy.PET_ODDS_BY_TIER, keyed on
# max_loot_tier above — which is what almost every enemy should do.
#
# Set it only when an enemy's pet chance has to be reasoned about separately
# from its tier. The slime is the one case: a large slime always becomes four
# smalls, so an encounter is four rolls rather than one, and the per-small
# number is set so the ENCOUNTER lands where a single kill otherwise would.
@export var pet_odds_override: int = 0


# =============================================================================
# STATS
# =============================================================================

# Here rather than with the combat tuning because the server will need it the
# moment it owns enemy health, and because it is genuinely constant per variant
# — unlike attack_range, which some enemies derive.
@export var max_hp: int = 50


# =============================================================================
# ELEMENT
# =============================================================================

# What this creature's damage IS. See src/shared/element.gd.
#
# NONE (0) is physical and is the right answer for anything that hits you with
# an object rather than a force — the bush sniper's arrow is not an element.
#
# IT DOES NOT HAVE TO MATCH WHAT THE CREATURE LOOKS LIKE, and an earlier
# version of this comment said the opposite. An element is a damage type. The
# colour is the artist's. When those two agree — the fire sprite measures hue
# 0.056 against FIRE's 0.056, which is as close as two numbers get — that is
# because the artist already drew the element, not because a rule forced it.
# When they disagree, the art wins: the boss is gold and its element is DARK,
# and nothing should repaint it to settle the argument.
#
# The one place the two are locked together is a DERIVED variant, which is
# made by recolouring a sheet to an element's hue on purpose. See
# recolour_to_element below.
@export var element: Element.Type = Element.Type.NONE


# =============================================================================
# RECOLOUR — OFF BY DEFAULT, AND THAT DEFAULT IS THE WHOLE POINT
# =============================================================================

# FALSE means "draw the sheet exactly as the artist drew it". That is the
# default, it is what every original creature in this project uses, and a new
# enemy gets it for free by doing nothing.
#
# WHY THIS EXISTS. The recolour shader replaces a pixel's hue outright — that
# is how it turns one sheet into seven creatures without new art. Run it over
# an ORIGINAL sheet and it does the same thing, which is not a tint, not a
# tweak, and not reversible by eye: every chromatic pixel in the drawing is
# flattened to a single hue. Four of this project's six original enemies were
# being rendered that way, and the measurements are what they are —
#
#     electricsprite   drawn #5299C5 blue      rendered as WIND mint green
#     slime            drawn #2F9C1F green     rendered as EARTH brown
#     bushmage         drawn #818A28 olive     rendered as EARTH brown
#     boss             drawn #DE890E gold      rendered as DARK violet
#
# The electric sprite was the clearest case: it was filed under WIND, so it
# rendered as the same mint green as windsprite.tres — the artist's original
# had been overwritten by a recolour of itself.
#
# SO THE DEFAULT IS OFF, not on-unless-suppressed. A flag that has to be
# remembered to protect someone's work is a flag that will be forgotten once.
# Set this TRUE only on a resource that is deliberately a palette-swap of a
# sheet that already exists somewhere else — the six *sprite.tres variants
# built from electricsprite.png are the whole current list.
@export var recolour_to_element: bool = false


# =============================================================================
# APPEARANCE
# =============================================================================

# Colour multiplied over the whole enemy at spawn. WHITE, the default, means
# "draw the art as authored", so every existing enemy is unaffected.
#
# THIS IS WHAT A PALETTE-SWAP VARIANT IS MADE OF. The point of this resource is
# that one scene can be several enemies — poisonslime.tscn is already two — and
# a tougher version of a creature is the classic way to add one: same art, same
# behaviour, more health, better loot, a different colour so the player can see
# which one they are fighting BEFORE it reaches them. That last part is why the
# colour belongs here beside max_hp rather than in the scene: a variant that
# looks identical to the common one is a trap, not a tier.
#
# IT IS ONE COLOUR ON PURPOSE. The pets reached this stage with two and three
# modulates stacked on different nodes, and modulate MULTIPLIES down the tree —
# so three tints are not three dials, they are one unpredictable product. The
# electric sprite's shot was authored green twice and rendered #493C06, a
# brown. One value on the root is the only version anyone can reason about.
#
# WHAT IT CANNOT DO. Multiplying darkens and filters; it cannot move a hue. Art
# that is already strongly coloured — the slimes measure 0.6 saturated green —
# goes darker and duller under any tint, never blue. For those a variant reads
# best as a deeper or more acidic version of the same element, which is also
# the more honest signal: a poison slime that is more poisonous.
@export var body_tint: Color = Color.WHITE


# How hard to push saturation when this creature is recoloured by
# element_recolour.gdshader. 1.0 leaves the art's own saturation alone.
#
# A HUE ROTATION PRESERVES SATURATION, WHICH IS USUALLY RIGHT AND SOMETIMES
# NOT. The sheets are not equally coloured — the bush archer measures 0.18 and
# the slime 0.66 — so one element applied to both gives a washed-out archer
# beside a vivid slime. Element.suggested_saturation_scale() turns a sheet's
# measured saturation into a starting value: 1.6 for the archer and the
# electric sprite, 1.3 for the bush mage, 1.0 for the slime and fire sprite.
#
# Authored per creature rather than computed at runtime, because "how vivid
# should this thing be" is art direction and the measurement is only ever a
# first guess at it.
@export var saturation_scale: float = 1.0


# =============================================================================
# THREAT
# =============================================================================

# Damage this enemy's projectile deals. 0 means "whatever the projectile scene
# already says", so every existing enemy is unaffected and the four projectile
# scripts keep their own defaults as the baseline.
#
# IT HAS TO BE HERE FOR A VARIANT TO MEAN ANYTHING. The enemy scripts
# instantiate a projectile and never touch its damage — electricsprite.gd
# spawns its orb, aims it and fires, and the number comes from
# magicprojectile.gd's export. So two enemies sharing a projectile scene hit
# for the same amount however different their health and rewards are, and a
# "tougher variant" would be a damage sponge that hits like the common one.
#
# Applied in BaseEnemy.spawn_projectile_node(), beside the tint, for the same
# reason: one place that every enemy's shot already passes through.
@export var projectile_damage: int = 0
