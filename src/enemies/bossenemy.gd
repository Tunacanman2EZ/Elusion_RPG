# bossenemy.gd — the crowned boss on the final floor, and the six element
# bosses of the arena, which are this same scene with their own data.
#
# SEVEN BOSSES, SEVEN FIGHTS (0.77.0). Each runs a KIT of its own - three
# stalagmite shapes, a signature volley of orbs, its element's effect - and
# attacks everyone in the fight in turn rather than one player: see THE KITS
# below, and statuseffects.gd for the effects.
#
# THIS SCENE HAD NO SCRIPT AT ALL. bossenemy.tscn was a CharacterBody2D with a
# sprite, a body collider and a health bar: nothing else. No script meant no
# take_damage, so it could not be hurt; no AI, so it never moved or attacked;
# and because enemies join the "enemies" group from BaseEnemy._ready() rather
# than from the scene file, it never joined — so the loot system, the combat
# system and the respawner in boss.tscn all looked straight past it. It was a
# statue you walked into, on a floor built around fighting it.
#
#
# THE ATTACK: one cast marks a PATTERN of ground with red rings and punches a
# stone pillar up through each of them a moment later. Which pattern depends on
# the phase and on a roll — see ATTACK PATTERNS below. Every ring is painted
# where the player WAS at the moment of the cast and none of them follow, ever:
# see the note at the top of bossprojectile.gd for why a telegraph that tracks
# its target is not a telegraph at all.
#
# The spikes in a cast never overlap each other, which is deliberate: at most
# ONE of them can catch the player, so a burst is a positioning test rather than
# a damage multiplier. Every pattern in the ATTACK PATTERNS section below is
# built to hold that rule, and each one says how it does.
#
#
# NO _physics_process OVERRIDE HERE, AND THAT IS DELIBERATE. BushMage replaces
# BaseEnemy's movement wholesale to get chase-and-hold, and the cost is written
# all over that file: it silently lost the leash, it lost the retuned slot
# geometry, and it sat idle for weeks because its hold band no longer
# intersected the grid it stands on. Every one of those was a copy of a rule
# drifting from the original. The boss wants plain "walk up and attack", which
# is what BaseEnemy already does — including the line-of-sight gate — so it
# inherits it instead of growing a second copy to maintain.
extends BaseEnemy
class_name BossEnemy


# This enemy's reward profile — hp, xp, loot tier. See BaseEnemy.enemy_data.
const ENEMY_DATA := preload("res://data/enemies/boss.tres")

# The animation set this boss attacks with. Its sheet carries BOTH a nine-frame
# `attack` set (a melee swing) and a ten-frame `cast` set (eyes charging red to
# white, discharging on frame 7). It summons rather than swings, so it uses
# `cast` — and that choice is why the two overrides further down exist.
const CAST_PREFIX := "cast"

# The other half of the sheet: a nine-frame melee swing. BaseEnemy's default
# animation prefix is "attack", so this matches what it would have played all
# along if this class had not overridden play_attack_animation() to always cast.
const MELEE_PREFIX := "attack"

# Bit VALUE of the player layer, not its number. The player sits on layer 3, and
# a mask is a bitmask, so layer 3 is 2^(3-1) = 4. Get this wrong and the swing
# silently connects with nothing.
const PLAYER_PHYSICS_LAYER := 4


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# Damage the spike deals when the boss's EnemyData does not say. Every boss's
# .tres says now (projectile_damage), so this is the fallback - see
# spike_damage() for why the data has to win.
@export var attack_power: int = 34

# Frame of the cast animation where the eruption is placed. FRAME 7 IS THE
# DISCHARGE — frames 0 to 6 are the eyes charging from red to white, 7 is the
# white burst, 8 and 9 are the afterglow. Spawning earlier means the ring
# appears while the boss is still winding up, which reads as the attack having
# already happened.
@export var cast_frame: int = 7

# The ground-eruption scene. Its root is an Area2D, not a moving body.
@export var eruption_scene: PackedScene = preload("res://scene/projectiles/bossprojectile.tscn")

# THE HAZARD A GATE USES INSTEAD. Same script, same layers, different art and a
# different impact frame - see secondbossprojectile.tscn.
#
# Every pattern in this file already distinguishes gate pillars from ordinary
# ones by TIMING: a gate warns longer, so the way out is the part of the shape
# that is slower to close. That is readable but subtle, and it is the only tell.
# Giving gates their own silhouette makes the route something the player sees
# rather than something they time.
@export var gate_scene: PackedScene = preload("res://scene/projectiles/secondbossprojectile.tscn")

# Passed through to each eruption — the player's reaction window. Kept here as
# well as on the eruption so the boss can be made harder without editing the
# attack it fires, which other things may eventually also use.
@export var eruption_telegraph: float = 0.52

# Prints the shape and the volley chosen on every attack.
#
# OFF BY DEFAULT. It is the right tool while tuning a pattern and pure noise
# during play: the two clocks attack independently, so a normal fight
# prints a line every second or so and buries anything else in the console.
# Tick it in the inspector for a tuning session rather than shipping it on.
@export var debug_patterns: bool = false

# FOUR NESTED RINGS, 65 PILLARS. Read innermost first; the three arrays are one
# table split in three and must stay the same length.
#
# SMALLER PILLARS ARE WHAT BOUGHT THE TIGHTER NEST. Every ring used to carry
# full-size 20px spikes, which put a hard 44px floor under the spacing and
# pushed the outermost ring to 176px. At 10-14px they sit at 28, 54, 86 and 120
# instead - so the pattern is DENSER (65 pillars against 43) and physically
# SMALLER (120px outer against 176) at the same time. Nesting closer was never
# an angle problem; it was a size problem.
#
# A ring of n pillars of radius p at radius r is safe only while
# 2*r*sin(PI/n) >= 2*p. Break that and two pillars overlap, and an overlap means
# one cast can hit the player twice.
const RING_COUNTS := [7, 11, 14, 18]
const RING_RADII := [24.0, 40.0, 64.0, 84.0]
const RING_SPIKE_RADII := [10.0, 11.0, 14.0, 14.0]

# The spike's authored size: the CircleShape2D in bossprojectile.tscn and the
# ring_radius it draws are both 20. Anything smaller is that scene scaled down,
# so this is the number those are divided by - change the scene and change this.
const SPIKE_BASE_RADIUS := 20.0

# WHAT A PILLAR IS BY DEFAULT NOW, and the single change that let everything
# else tighten. The scene is authored at 20; every pattern that does not ask for
# a size gets this instead, so pillars are scaled to 14 across the board.
#
# Shrinking the pillar shrinks the MINIMUM SPACING between two of them, from
# 40px to 28 - and that minimum is what every radius, pitch and wall gap in this
# file is ultimately derived from. Smaller pillars therefore buy two things at
# once: rings that sit closer to the player, and more pillars on each of them.
const PILLAR_RADIUS := 14.0

# HOW FAR AHEAD OF THE PLAYER A PATTERN IS AIMED, as a fraction of its own
# telegraph. This is the difficulty knob that matters, and adding pillars was
# never going to substitute for it.
#
# THE PROBLEM IT SOLVES: every pattern is placed where the player IS and lands
# 0.64s later, and 0.64s of running is 58px in whatever direction they were
# already travelling. So holding ANY direction carried them clear of every
# pattern before it erupted - no reading, no timing, no decision. One strategy
# beat the whole fight, which is what "not hard enough" actually was.
#
# HALF A TELEGRAPH WAS NOT ENOUGH, and it was measured against the wrong clock.
# 0.64 is the PILLAR telegraph; the spike track's patterns run to 1.7s, and a
# multi-rank pattern's later ranks were being aimed with the lead for its first.
# A player running in a straight line stayed 30px ahead of the whole thing, so
# the lazy answer still worked - it just took slightly longer.
#
# So the lead is now taken PER SPIKE, off that spike's own telegraph, at nearly
# the player's full displacement. Each rank of a pattern goes where the player
# will be WHEN THAT RANK LANDS, not where the first rank was aimed. A shape that
# closes over three beats now closes over a moving target.
#
# THE RANKS SHEAR APART WHEN THE PLAYER RUNS, and that is allowed now. This file
# used to enforce a rule that at most one spike from a cast could ever land, and
# the rule was wrong for what this fight is - being caught by one rank of a
# pattern does not buy you the rest of it. Spikes that share a telegraph still
# hold their spacing, because two spikes erupting in the same place at the same
# instant is wasted geometry and unreadable; spikes on different beats are free
# to overlap, because they are different attacks arriving at different times.
#
# NOT QUITE 1.0, deliberately. At 0.9 a player holding a straight line finds the
# pattern centred about 10px behind them - still well inside the spikes nearest
# them, so running is punished, while a player who stops gets no lead at all and
# the pattern lands exactly on them. The counter is to CHANGE DIRECTION, which
# is a real answer available at every moment. The ground still never moves once
# it is marked.
const AIM_LEAD := 0.9

# Hard ceiling on how far ahead a single spike may be thrown, in pixels.
#
# A SAFETY NET, NOT A TUNING KNOB, and the difference matters because tuning it
# was tried first and cannot work. Capping the lead low enough to keep patterns
# near where the player is STANDING also puts them behind a player who is
# running: a spike landing at time t has to be within 21px of v*t to connect, so
# at v = 90 the cap must be at least 90*t - 21 or the pattern simply misses.
# At t = 1.6s that is 123px, which is not a cap at all. Near-now and
# catches-a-runner are the same dial pulled in opposite directions.
#
# WHAT ACTUALLY FIXED THE PATTERNS LANDING MILES AWAY WAS SHORTENING THEM.
# Every telegraph here was roughly halved - the ring resolves in 1.06s where it
# took 1.54, the gate in 1.20 where it took 2.24 - and a pattern that is over
# sooner needs less lead to catch the same runner. The distances came down as a
# consequence of the timing rather than by clamping the geometry.
#
# So this exists only to stop something unforeseen throwing a pattern across the
# room: a speed buff, a knockback, a bad frame putting a huge number in
# velocity. At the player's own 90px/s nothing in this file reaches it.
const AIM_LEAD_MAX := 90.0

# THE TWO PATTERNS THE LEAD MUST NOT TOUCH.
#
# The spiral is drawn around the BOSS rather than around the player - that is
# the one thing making it different from everything else here, and sliding it
# along the player's heading would drag it off the boss and delete the
# difference. The ladder works out its own rung positions from the player's
# actual speed and heading, so leading it again would throw every rung a second
# run's worth of distance down the road and it would miss everything.
const SELF_AIMED := [&"spiral", &"ladder"]

# What share of pillars leave acid behind.
#
# NOT ALL OF THEM, and the arithmetic is why: a 65-pillar cast every 2.16s with
# a 2.5s pool life would keep 75 pools alive and cover 44% of the room in
# standing acid. At a third of that it is 15% - the floor degrades and has to
# be watched, without the fight turning into a swamp you cannot read.
#
# THE 2.5s THIS ASSUMES IS NOW A MIDPOINT, NOT A SETTING. Each element's pool
# has its own lifetime authored in its own scene, from wind's 1.0 to ice's 5.0,
# and bossprojectile.gd's puddle_life_scale (0.6) is what keeps a 65-pillar
# carpet from turning ice's five seconds into a floor with holes in it. Run the
# numbers per element and the band is 0% for light and wind up to 22% for ice -
# the wet elements are wetter, which is the point, and nothing approaches 44%.
#
# IF YOU RAISE A MULTIPLIER, RAISE IT AGAINST THAT BAND. Water is the worked
# example: three pools per roll at a 1.4 multiplier put it at 54%, over the
# line, and it took a chance of 0.5 to bring it back beside fire.
const PUDDLE_CHANCE := 0.35

# THE SPIKE TRACK — a second attack, running beside the pillars.
#
# It is NOT a cast. The pillar patterns all come out of the cast animation, so
# they inherit its wind-up, its cooldown, and the boss having to stand still to
# make them. This track has no tell on the boss at all: the floor simply opens,
# on its own clock, for as long as the boss is alive and engaged.
#
# It wears the spike-gate art so the player can tell the two apart at a glance -
# which is the whole reason the art does not vary WITHIN a pattern any more.
# Quiet floor between one spike attack clearing and the next appearing.
#
# SHORTER THAN THE PILLAR TRACK'S, because the two are meant to interleave
# rather than take turns. The spike track is the faster, lighter of the two;
# if it waits as politely as the pillars do, the fight is back to pulses with
# gaps in them.
const SPIKE_BREATHER := 0.10

# Trimmed per phase so the quiet between spike attacks shrinks as the fight
# goes on. Added on top of the pattern's own length, like the pillar track.
#
# CUT FROM [0.7, 0.3, 0.0] ONCE THE TRACK HAD ITS OWN PATTERNS. Those numbers
# were sized for a track that borrowed four one-beat shapes from the pillar
# library; the spike track now runs multi-rank patterns that carry their own
# rhythm inside them, so the padding between attacks was doing nothing except
# putting empty floor where the next attack should be. What is left is the
# minimum: the pattern's own length, the time for its hit to land, and a breath.
const SPIKE_EXTRA_GAP := [0.35, 0.15, 0.0]


# =============================================================================
# THE KITS (0.77.0)
# =============================================================================
# The owner, 23 Oct: "bosses currently are stale do to only locking on 1
# player ... instead of each boss being a repeat we can add real elements and
# effects slow on ice etc i want to keep the stalagmites but each boss needs to
# be a challenge but also clearable".
#
# WHAT IT WAS. All seven bosses ran this script with one vocabulary: three
# pillar shapes on the cast, eleven spike shapes on a second clock, stalkers
# from phase two, and the swing. The element changed timings, sizes and
# puddles and nothing else, so the seventh fight was the first one recoloured -
# and every shape in it was a ring painted at one player's feet: whoever was
# nearest when the gate opened, for the whole fight.
#
# WHAT IT IS. Each boss has a kit, below:
#   shapes    its own three stalagmite shapes, out of the sixteen in ATTACK
#             PATTERNS, on the stalagmite clock (_on_spike_timer): the first
#             two from the start, the third from phase two (PHASE_TWO_AT)
#   volleys   its signature volley of orbs (BulletZone), fired from the cast
#             where the pillar cast used to be - from the boss outward, so the
#             danger comes from somewhere other than your feet. One list per
#             phase; the Crowned's grows through the other six's
#   stalkers  the Crowned only
# and its element's effect (statuseffects.gd), carried by its stalagmites,
# its orbs and - the ones that belong to the ground - its puddles:
#   Light    lance, ring, arc        PRISM    spokes of light that turn as
#                                             they leave: walk the gaps    dazzle
#   Wind     arc, snare, sweep       GALE     fast fans that shove; VORTEX
#                                             (phase three) pulls you in
#                                             through a ring with a door   shove
#   Water    cage, snare, ladder     TIDE     walls of orbs, each with one
#                                             gap, the gap moving          soaked
#   Ice      ladder, cage, checker   FROST    shards that stop and lie as
#                                             mines across your spot       chill
#   Earth    gate, triwall, rake     BOULDER  stalagmites thrown where you
#                                             stood, bursting into rocks   root
#   Fire     cross, spiral, carpet   PINCER   orbs that curve shut on your
#                                             spot and leave it burning    burn
#   Crowned  ring, cage, gate        one of each of the six's, more each
#                                    phase, and the stalkers           wither
# Fewer moves each than the one shared set had, and each one says something
# about the boss throwing it.
#
# NOBODY IS LOCKED ON. Each attack picks whoever in the fight has gone longest
# without being attacked (next_target()), never the one just attacked while
# anyone else is there. The two clocks take their own turns, the boss walks
# toward whoever its cast is for, and the boulders and the pincers go at up to
# SPLIT_MAX players at once. With one player in the room, all of it is you.
#
# WAVES TAKE TURNS. Two or three bosses loose together each attack more slowly
# (_pace(), WAVE_PACE), speeding back up as their partners fall: a wave of
# three is three fights at a tempo you can follow, not three at full tempo.
#
# THE STALAGMITES KEEP THEIR PROMISE. Every shape here is one of the sixteen
# and holds the rule those are built to - at most one spike in a cast can catch
# you. And ONE clock now carries all of them, so the pairings the two tracks
# were split to keep apart (lance+cross, carpet+spiral and lance+carpet,
# together, left almost no floor) can no longer meet: a clock casts one shape
# at a time.
const KITS := {
	Element.Type.LIGHT: {
		"shapes": [&"lance", &"ring", &"arc"],
		"volleys": [[&"prism"], [&"prism"], [&"prism"]],
	},
	Element.Type.WIND: {
		"shapes": [&"arc", &"snare", &"sweep"],
		"volleys": [[&"gale"], [&"gale"], [&"gale", &"vortex"]],
	},
	Element.Type.WATER: {
		"shapes": [&"cage", &"snare", &"ladder"],
		"volleys": [[&"tide"], [&"tide"], [&"tide"]],
	},
	Element.Type.ICE: {
		"shapes": [&"ladder", &"cage", &"checker"],
		"volleys": [[&"frost"], [&"frost"], [&"frost"]],
	},
	Element.Type.EARTH: {
		"shapes": [&"gate", &"triwall", &"rake"],
		"volleys": [[&"boulder"], [&"boulder"], [&"boulder"]],
	},
	Element.Type.FIRE: {
		"shapes": [&"cross", &"spiral", &"carpet"],
		"volleys": [[&"pincer"], [&"pincer"], [&"pincer"]],
	},
	Element.Type.DARK: {
		"shapes": [&"ring", &"cage", &"gate"],
		"volleys": [[&"prism", &"tide"], [&"prism", &"tide", &"frost", &"gale"],
			[&"prism", &"tide", &"frost", &"gale", &"boulder", &"pincer"]],
		"stalkers": true,
	},
}

# BOSSES THAT SCALE (0.80.0). The owner, after a rating of the game: "we need to
# think outside the box ... lets fix it up". Measured on 0.77.0, a level-22
# warrior in ember killed the Light boss in under ten seconds and the Crowned
# in about twenty-five: a boss was the same fight for one player of its band
# as for four at the level cap. Now its health is set by who is fighting it,
# on the game that runs it (never a mirror) - scale_for():
#   - each fighter counts min(LEVEL_MOST, 1 + LEVEL_SHARE x the levels they
#     stand above the boss's band, BAND_TOP - CLAUDE.md, "The pace"), and the
#     boss takes their mean;
#   - times 1 + PARTY_SHARE for every fighter after the first (PARTY_MOST
#     counted at most, the highest levels);
#   - times its own HEALTH_BASE: the Crowned's 2.5, the finale at the level it
#     is for.
# Checked every SCALE_SECONDS while it fights: somebody joining raises it, the
# damage already done kept (raise_for_scale()); nobody leaving lowers it - the
# server's books count down from what the game says, and a health lowered
# under them is a death they cannot agree to (raise_for_stir() says the same).
# Back home at full health it is itself again (unscale()). Every screen is told
# ("mh", monstersync.gd), and so are the books (combatbook.py,
# BOSS_RAISED_MOST: a boss's health raised by its fight, never lowered below
# the catalogue's).
const BAND_TOP := {
	Element.Type.LIGHT: 4, Element.Type.WIND: 4, Element.Type.WATER: 9, Element.Type.ICE: 9,
	Element.Type.EARTH: 15, Element.Type.FIRE: 21, Element.Type.DARK: 22,
}
const HEALTH_BASE := {Element.Type.DARK: 2.5}
const LEVEL_SHARE := 0.2
const LEVEL_MOST := 5.0
const PARTY_SHARE := 0.6
const PARTY_MOST := 16
const SCALE_SECONDS := 1.0

# The shapes that rise as the stone pillar (eruption_scene) rather than the
# spike cluster (gate_scene): the three that were the old pillar cast's, so
# each shape still wears the art it always did.
const PILLAR_SHAPES := [&"ring", &"cage", &"gate"]

# Every name a kit may list, and so every name fire_volley() answers to. A
# volley sent with any other name fires nothing.
const VOLLEYS := [&"prism", &"gale", &"vortex", &"tide", &"frost", &"boulder", &"pincer"]

# Everybody in the fight is counted as somebody to share the attacks with; this
# many at most get a boulder or a pincer each from one cast.
const SPLIT_MAX := 3

# Each orb, this share of the boss's spike: many small hits, like every orb in
# the game (BulletZone.share_of).
const ORB_SHARE := 0.3

# How long each volley holds the cast before the next may start, and the rest
# after it, by phase - both stretched by _pace() while partners are loose.
const VOLLEY_BUSY := {
	&"prism": 1.7, &"gale": 0.9, &"vortex": 2.2, &"tide": 1.4,
	&"frost": 1.0, &"boulder": 1.2, &"pincer": 1.2,
}
const VOLLEY_REST := [1.0, 0.6, 0.3]

# EACH PHASE IS HARDER THAN THE LAST, and not only by a third shape. The
# stalagmite clock runs this much faster in each phase (its wait times this),
# every volley has more in it (the per-phase counts below), and the rest
# between casts shortens (VOLLEY_REST). Measured against the same dodging
# stand-in (tools/bossmeasure.gd on the website), the first version of the
# kits was gentler than the one shared set had been - fewer moves, the same
# tempo - and the owner's word was "too easy", so the tempo climbs instead.
const PHASE_TEMPO := [1.0, 0.85, 0.7]

# AND THE SWING STOPS BEING SAFE. Up close the boss swings rather than casts;
# from phase two, after this many swings in a row it casts anyway - a volley at
# point blank - so standing in its reach is a choice with a cost, not the
# safest place in the room. 0 never (phase one).
const SWINGS_BEFORE_CAST := [0, 3, 2]

# PRISM (light). PRISM_BURSTS rings of spokes, PRISM_GAP apart, each turned
# PRISM_TURN further: the spokes curve as they spread, and over the volley
# they sweep 1.35 rad or more - further than the gap between two spokes (1.05
# at six), so standing still is always crossed by one. You walk with the turn,
# or into a gap as it opens; a gap is wider than you from 20 px out.
const PRISM_SPOKES := [6, 7, 8]
const PRISM_BURSTS := [10, 12, 16]
const PRISM_GAP := 0.14
const PRISM_SPEED := 70.0
const PRISM_TURN := 0.15

# GALE (wind). GALE_FANS fans GALE_GAP apart, each swept GALE_SWEEP on: a
# wall of orbs 0.8 rad wide, about 70 px at the boss's attack range - one step
# sideways clears it, standing in it is three shoves back.
const GALE_FANS := [3, 4, 5]
const GALE_GAP := 0.22
const GALE_ORBS := [5, 7, 7]
const GALE_SPREAD := 0.8
const GALE_SPEED := 150.0
const GALE_SWEEP := 0.15

# VORTEX (wind, phase three). Everyone within VORTEX_REACH is drawn toward the
# boss at VORTEX_PULL - under half your walk, so you can always walk out - for
# VORTEX_SECONDS, while VORTEX_RINGS rings leave it, each with a door of
# VORTEX_DOOR orbs missing in a different place. Big orbs, so a ring of
# VORTEX_ORBS is solid out to 100 px and the door is the only way through.
const VORTEX_REACH := 170.0
const VORTEX_SECONDS := 2.2
const VORTEX_PULL := 40.0
const VORTEX_RINGS := 2
const VORTEX_GAP := 0.9
const VORTEX_ORBS := 28
const VORTEX_DOOR := 4
const VORTEX_SPEED := 55.0

# TIDE (water). TIDE_WAVES walls of big orbs across TIDE_SPREAD, TIDE_GAP
# apart, each with a gap TIDE_DOOR orbs wide that moves TIDE_DOOR_STEP orbs
# along between waves: walk with the gap. The wall is solid out to 200 px; the
# gap is wider than you from 51 px (68 at the narrower door of phases two and
# three).
const TIDE_WAVES := [3, 4, 5]
const TIDE_GAP := 0.55
const TIDE_ORBS := 23
const TIDE_SPREAD := 2.5
const TIDE_SPEED := 60.0
const TIDE_DOOR := [3, 2, 2]
const TIDE_DOOR_STEP := 3
const TIDE_DOOR_NEAR := 4

# FROST (ice). A fan of shards that slow to a stop at the distance you stood
# and lie there as mines (BulletZone.SETTLE_LINGER) - the middle one on your
# spot, the others a wall either side. Step back past them, not into them on
# the way in. From phase two a second arc FROST_SECOND_IN nearer the boss
# follows FROST_SECOND_AFTER later.
const FROST_SHARDS := [9, 11, 13]
const FROST_SPREAD := 1.4
const FROST_SPEED := 150.0
const FROST_NEAREST := 40.0
const FROST_FURTHEST := 160.0
const FROST_SECOND_IN := 34.0
const FROST_SECOND_AFTER := 0.3

# BOULDER (earth). The boss's own stalagmite thrown over everything onto the
# spot you stood on (BulletLob), landing BOULDER_FLIGHT later for its spike's
# full hit and bursting into BOULDER_ROCKS rocks that settle round the crater.
# One for each player in the fight; from phase two more at the one it is
# facing, thrown where they are running (or either side of them, standing).
const BOULDER_FLIGHT := 1.0
const BOULDER_ROCKS := [8, 10, 12]
const BOULDER_ROCK_SPEED := 110.0
const BOULDER_CRATER := 34.0
const BOULDER_LOBS := [1, 2, 3]
const BOULDER_SPREAD := 46.0
const BOULDER_REACH_MAX := 260.0

# PINCER (fire). Orbs that leave either side of you and curve shut on your spot
# all at once (BulletZone.fire_pincer), one pincer for each player in the
# fight; where each shuts, the floor burns (a fire puddle that carries burn).
const PINCER_ARMS := [
	[-0.9, -0.45, 0.45, 0.9],
	[-1.0, -0.6, -0.25, 0.25, 0.6, 1.0],
	[-1.1, -0.75, -0.4, 0.4, 0.75, 1.1],
]
const PINCER_SPEED := 120.0
const PINCER_AGAIN := 0.45
const PINCER_REACH_MIN := 40.0

# Each other boss loose in the same fight slows this one's clocks by this share:
# x1.35 beside one partner, x1.7 beside two.
const WAVE_PACE := 0.35
const BOSS_GROUP := &"bosses"

const StatusEffects := preload("res://src/characters/statuseffects.gd")


# =============================================================================
# THE STALKER
# =============================================================================
# A SECOND ATTACK RUNNING ON ITS OWN CLOCK, independent of the cast cycle.
#
# Patterns are pulses - they land and they are over, so pressure arrives in
# bursts with quiet between, and the quiet is where a fight stops being hard.
# The stalker is continuous: it walks at the player leaving erupting pillars
# until it expires, straight through however many casts happen meanwhile.
#
# The pair of them is the point. Patterns are aimed where the player is HEADING,
# so they punish moving predictably; the stalker punishes not moving at all.
# Answering one makes the other harder, which is a thing neither could be on
# its own. See bossstalker.gd for why a follower is legitimate here at all.
const STALKER_SCRIPT := preload("res://src/enemies/bossstalker.gd")

# Held back until phase 2. Phase 1 is where the player learns to read patterns,
# and learning to read them while something is chasing you is learning neither.
const STALKER_FROM_PHASE := 1

# Seconds between stalkers. Shorter than their 7s lifetime on purpose from
# phase 3, so the last third of the fight has two of them out at once.
const STALKER_INTERVAL_PHASE_TWO := 9.0
const STALKER_INTERVAL_PHASE_THREE := 5.5

# Where it starts. Out of the boss itself, so it reads as something the boss
# sent rather than something that appeared.
const STALKER_SPAWN_OFFSET := 18.0


# =============================================================================
# THE ARC — the spike track's light attack
# =============================================================================
# A short arc of spikes near the player, with the whole rest of the circle open.
# Cheap to answer on purpose: it is the filler between the spike track's heavier
# patterns, not something that kills on its own. See _pattern_arc().

# Spikes in the arc, per phase.
const TRAP_COUNT := [3, 4, 5]

# Where the arc sits and how wide it spans.
#
# 70px AND 100 DEGREES ARE A PAIR, not two free numbers. The spikes have to sit
# at least 28px apart or two of them overlap, and arc length is radius times
# angle - so at 70px and 100 degrees five spikes land 30.5px apart, which
# clears it. Narrow the span or pull the radius in without dropping the count
# and they start overlapping: at 60px and 80 degrees, five spikes are 20.9px
# apart and three of them are inside each other.
const TRAP_RADIUS := 56.0
const TRAP_SPAN := 120.0

# Shorter than a cast telegraph because the attack is smaller, but still a real
# window: 0.55s is 50px of movement against the 21px needed to step off a
# 14px spike.
const TRAP_TELEGRAPH := 0.50


# =============================================================================
# THE TRIWALL — three walls at once, closing
# =============================================================================
# The spike track's signature. Three walls, 120 degrees apart, all landing in
# the same instant, then again a rank closer, then again - so the player is
# inside a shrinking triangle with a doorway in each side.
#
# WHY THREE AT ONCE RATHER THAN ONE AFTER ANOTHER. The pillar track's gate
# already does walls one at a time, and one wall is answered by running along
# it until you find the door. Three walls arriving together have no "along" -
# every direction is a wall, so the only answer is a door, and the door is a
# decision taken before the wall exists.
#
# THE CENTRE ERUPTS TOO, first or last depending on which way the ranks run -
# the same trick _pattern_ring() uses, and for the same reason. Three lines at
# 120 degrees can never cover the middle of the triangle they make, so without
# a centre spike this whole pattern is answered by standing perfectly still.

const TRIWALL_WALLS := 3

# The three ranks, as distances from the player. Reversed at random, so the
# triangle either closes in on the player or opens out from them.
const TRIWALL_RANKS := [68.0, 46.0, 26.0]

# Distance between neighbouring pillars along a wall. Same 32 the gate uses,
# which is 28px of pillar plus 4px of daylight.
const TRIWALL_PITCH := 32.0

# Pillars left out of each wall to make a doorway.
const TRIWALL_DOOR_WIDTH := 2

const TRIWALL_TELEGRAPH := 0.48
const TRIWALL_RANK_STEP := 0.16

# HOW THE CORNERS ARE KEPT APART, and the reason a wall's pillar count is
# derived rather than written down.
#
# Three lines each at distance d from a point, with their normals 120 degrees
# apart, form an equilateral triangle of inradius d whose sides are 2*d*tan(60)
# long. A wall spanning its whole side therefore ENDS EXACTLY WHERE THE NEXT
# WALL BEGINS - two pillars in the same place, which is the overlap this file
# spends most of its geometry avoiding. Adjacent walls meet at 60 degrees, so
# pulling each back by s along its own line opens s of daylight between the
# corner pillars; 28 is one pillar diameter, so that is what each wall gives up.
#
# At the three ranks above that works out to 9, 5 and 1 pillars per wall - the
# innermost rank collapsing to a single spike per bearing is not a degenerate
# case, it is the crush: three dots at 120 degrees around the player with about
# 27px of daylight between them.
const TRIWALL_CORNER_CLEAR := 28.0


# =============================================================================
# THE RAKE — parallel rows sweeping across
# =============================================================================
# Four long rows, all facing the same way, firing one after another across the
# player. No doorways: the rows are solid, and the gaps that matter are the
# 40px lanes BETWEEN them.
#
# THE ANSWER IS TO STAND STILL IN A LANE, which no other pattern in this fight
# rewards - everything else is punishing you for not moving. That is why it is
# here. A player who has learned to run from every telegraph runs straight
# across the rows and takes all four.
#
# ALTERNATE ROWS ARE SHIFTED HALF A PITCH so the 4px gaps between pillars do not
# line up into a clear column running through every row. Aligned, the whole
# pattern has one free lane straight through it and the sweep is decoration.
const RAKE_ROWS := 4
const RAKE_ROW_GAP := 34.0
const RAKE_PILLARS := 5
const RAKE_PITCH := 32.0
const RAKE_TELEGRAPH := 0.46
const RAKE_STEP := 0.15


# =============================================================================
# THE SNARE — a tight collar with one late gap
# =============================================================================
# Nine spikes in a ring 44px out: close enough that the player is already inside
# it when it appears, and there is not time to cross it.
#
# ONE SPIKE IS LATE, and that is the entire attack. The other eight land
# together and close the circle; the ninth hangs for another third of a second,
# which makes it the only way out and says exactly where it is. Answering the
# snare is spotting which spike has not fired yet and being through that gap
# before it does.
#
# 44 AND 9 ARE A PAIR. Nine spikes on a 44px circle sit 30.1px apart, which
# clears the 28px two pillars need. Pull the radius in or add a tenth and they
# overlap.
const SNARE_SPIKES := 9
const SNARE_RADIUS := 44.0
const SNARE_TELEGRAPH := 0.46
const SNARE_GAP_DELAY := 0.22


# =============================================================================
# THE LADDER — rungs laid down the road the player is running
# =============================================================================
# THE ANSWER TO "IT MISSES ME WHEN I RUN", made literal. Every other pattern is
# a shape placed on the player and then led; this one is not a shape at all. It
# takes the player's heading and their speed, works out where they will be at
# each of four moments, and puts a rung across the road at each of them.
#
# So running in a straight line does not carry you past it - it carries you
# INTO it, four times. The rungs are wide but not infinite, and the counter is
# the one this fight keeps asking for: stop, or turn.
#
# SELF-AIMED, see SELF_AIMED above. It leads itself by construction, so putting
# it through _lead_pattern() as well would throw every rung a second run's worth
# of distance down the road and it would miss everything.
const LADDER_RUNGS := 3
const LADDER_PILLARS := 5
const LADDER_PITCH := 32.0
const LADDER_TELEGRAPH := 0.48
const LADDER_STEP := 0.30

# How much of the player's real displacement each rung is placed at. Slightly
# under 1, for the reason AIM_LEAD is: a rung placed exactly on the prediction
# is beaten by the smallest change of pace, and one placed a fraction short is
# still inside its own hit radius.
const LADDER_LEAD := 0.9

# Below this speed the player counts as standing still, and the ladder stops
# predicting where they are going because they are not going anywhere.
#
# THIS REPLACED A FLOOR THAT WAS QUIETLY BROKEN. The old version clamped the
# speed used for spacing up to 90 so a crawling player would not get all the
# rungs stacked in one place. It worked for a crawling player and was a disaster
# for a STATIONARY one: rung k sits at speed * lands * lead, so a player who was
# not moving at all still got rungs laid out 42, 73 and 104px down a road they
# were not travelling. Measured against a standing player, ZERO PERCENT of the
# ladder's spikes landed within 35px of them - the whole pattern fired into
# empty floor, every time.
#
# It is a road when the player is running and a ring of rungs marching outward
# when they are not, which is the only honest reading of "lay spikes where they
# are going" for someone going nowhere.
const LADDER_MOVING_SPEED := 22.0

# Distance between rungs for a stationary player, with the first ON them.
#
# Slightly more than the 28px two spikes need, so consecutive rungs read as
# separate lines rather than a smear. A moving player gets
# speed * step * lead instead, which at 90px/s comes out at 24px.
const LADDER_STANDING_SPACING := 34.0


# =============================================================================
# THE SWEEP — a radar arm turning around the player
# =============================================================================
# One arm of four spikes reaching out from the player, turning 40 degrees a beat
# for six beats - most of a full circle, swept rather than stamped.
#
# It is the only pattern here that has to be read as MOTION. Everything else is
# a shape that appears; this one has a direction of travel, and the whole
# question is whether you run with the arm or against it. Running with it is
# wrong - it catches you. The centre erupts on the last beat, so the hub the arm
# turns around is not a place to wait it out either.
const SWEEP_BEATS := 6
const SWEEP_ARM := 3

# 44 IS THE INNER RADIUS FOR THE SAME REASON THE SNARE'S IS. Consecutive arms
# are 40 degrees apart, so the innermost spikes of two neighbouring beats sit
# 2*44*sin(20) = 30.1px apart. Pull the hub in or slow the turn and they stack.
const SWEEP_INNER := 38.0
const SWEEP_SPACING := 30.0
const SWEEP_TURN := 46.0
const SWEEP_TELEGRAPH := 0.46
const SWEEP_STEP := 0.10


# =============================================================================
# THE CHECKER — two interlocking grids, one beat each
# =============================================================================
# A 5x5 lattice where the black squares erupt, then the white ones. There is no
# running out of it and no corridor through it: the answer is ONE STEP, onto the
# squares that are not about to open, and then one step back.
#
# THE ONLY PATTERN HERE THAT ASKS FOR PRECISION RATHER THAN DISTANCE. Everything
# else is answered by covering ground; this is answered by covering exactly 40px
# and stopping. A player who has learned to sprint from every telegraph sprints
# across three cells and lands on the wrong colour.
#
# WHICH COLOUR GOES FIRST IS A COIN FLIP, so the player cannot pre-commit to the
# step - the cell they are standing on when it appears is either about to kill
# them or about to be the safest ground in the room.
const CHECKER_CELLS := 5

# 40 IS SET BY THE HIT RADIUS, NOT BY TASTE. A spike denies 21px around itself,
# so the player has to be able to stand somewhere that is more than 21 from
# every cell of one colour - which, on a lattice, is the centre of a cell of the
# other colour, exactly one pitch away. Drop the pitch to 40 and that gap is
# 19px of daylight; drop it to 34 and there is nowhere safe at all.
const CHECKER_PITCH := 36.0
const CHECKER_TELEGRAPH := 0.46

# The step has to be affordable: 40px at the player's 90px/s is 0.45s, so this
# is that plus a margin. Tighten it and the pattern stops being a step and
# becomes a dice roll.
const CHECKER_BEAT := 0.42


var _spike_timer: Timer = null

# HOW MANY PILLARS PER RING ARE GATES INSTEAD.
#
# A gate is a pillar that erupts LATE, so the ring lands with holes in it and
# those holes close a moment later. Without them a 51-spike nest leaves 15% of
# the floor standable and the route through is whatever the rotation happened to
# leave; with them it is 28%, and the route is something the boss decided and
# the player can read.
const RING_GATES := 2

# How long a gate stays open after its own ring has landed. The same idea as the
# cage doorway and checked the same way: 0.40s is 36px of movement, against the
# 27px needed to clear a full-size pillar and 19px for a small one.
const RING_GATE_DELAY := 0.18

# How far the gates of one ring can swing round from the gates of the ring
# inside it, in radians. Zero would stack every gate on one bearing and carve a
# straight corridor out - which is readable but solved once. This much drift
# makes the way out bend, so it has to be followed rather than aimed at.
const RING_GATE_DRIFT := 0.5

# THE GAP BETWEEN RINGS ERUPTING, AND THE MOST IMPORTANT NUMBER IN THIS FILE.
#
# Twenty-five spikes landing at once leaves 3.6% of the floor standable, which
# is not a fight. The same twenty-five staggered leaves 15% and turns the attack
# into a route: be in this ring's gap now, that ring's gap a fifth of a second
# later. Density in SPACE is capped by geometry - spikes are 40px wide and a
# ring only holds so many before it closes. Density in TIME is not, and that is
# the whole reason this pattern can be as big as it is.
#
# 0.18 SPECIFICALLY, because it is the value at which the attack stops being
# outrunnable. The outer ring lands at 0.9 + 4*0.18 = 1.62s, by which point the
# player has covered 146px - well short of the 203px needed to clear a 176px
# ring. Stagger it wider and they simply leave: at 0.30 on the older three-ring
# version, 80% of measured survivors had fled rather than woven, and every ring
# inside the last became decoration. RAISING THIS MAKES THE ATTACK EASIER, NOT
# SLOWER, which is the opposite of what the number looks like it does.
const RING_STAGGER := 0.09


# =============================================================================
# ATTACK PATTERNS AND PHASES
# =============================================================================
# THREE PHASES, EACH WITH ITS OWN SHAPE OF ATTACK, gated on remaining health.
#
#   phase 1, above 66%   RING and CAGE   - learn the rules
#   phase 2, 66% to 33%  LANCE and CROSS - directional waves to step off
#   phase 3, below 33%   CARPET          - no puzzle left, just keep moving
#
# EVERY PATTERN MUST LEAVE A REACHABLE ANSWER. The player moves at 90px/s, so a
# 0.9s telegraph is 81px of travel - that budget is what decides whether a shape
# is a fight or a cheap shot, and each pattern below states how it is beaten.
# A pattern that asks the player to travel further gets a LONGER telegraph
# rather than being made smaller; that is why the cage warns for 1.3s.
#
# PILLARS ARE 14px NOW, NOT 20, and that is what made everything else possible.
# The minimum spacing between two of them fell from 40px to 28, so every ring
# sits closer to the player AND holds more pillars. The whole pattern set got
# smaller and denser at the same time.
#
# ONE COUNTER-INTUITIVE RESULT WORTH KNOWING BEFORE TUNING: tightening a pattern
# makes it EASIER, not harder. Measured on the ring set, compressing it from a
# 152px outer ring to 120px moved survivable floor from 21% to 26% - because the
# distance the player has to cover to escape shrinks faster than the gaps they
# have to thread do. Density is paid for with the telegraph, not with geometry,
# which is why the base warning came down to 0.64s in the same pass.

# Below these fractions of max health, the boss moves to the next phase.
const PHASE_TWO_AT := 0.66
const PHASE_THREE_AT := 0.33

# CAGE: a near-solid ring with one doorway.
#
# At r=102 sixteen spikes sit 40px apart and are 40px across, so they touch -
# the ring reads as a wall rather than a dotted line. Omitting one leaves a 40px
# doorway, comfortable for a 14px-wide player. Reaching it from the centre is
# 102px, or 1.13s at full speed, so the telegraph has to clear that: 1.3s.
const CAGE_COUNTS := [12, 18]
const CAGE_RADII := [56.0, 84.0]
const CAGE_TELEGRAPH := 0.60

# THE DOORWAY IS NOT MISSING, IT IS LATE. The gap spike still erupts, just this
# much after the rest of the wall - so the way out closes behind you and the
# cage becomes "go now" instead of "go eventually".
#
# 0.45 IS A FLOOR, NOT A FEEL. Reaching the doorway from the centre is 102px
# (1.13s) and stepping clear of the doorway spike is another 27px (0.30s), so
# the run costs 1.43s against a seal at 1.75s. The tighter number that was
# tempting, 0.30, seals at 1.60s and leaves a player standing IN the doorway
# exactly 27px of movement to escape a 27px radius - a dodge with zero margin,
# which is the same thing as no dodge. Do not lower this without redoing that
# arithmetic.
const CAGE_DOOR_DELAY := 0.22

# How long after the inner cage the outer one lands.
const CAGE_RING_STEP := 0.18

# LANCE: a line fired from the boss straight through the player.
#
# Beaten by stepping ACROSS it, which is 27px - a third of a second - so it can
# warn briefly and still be fair. The spikes erupt outward one after another,
# which is what makes it read as a wave travelling at you rather than a row
# appearing at once.
const LANCE_SPIKES := 5
const LANCE_SPACING := 32.0
const LANCE_TELEGRAPH := 0.50
const LANCE_ROLL := 0.05

# CROSS: four arms radiating from where the player is standing.
#
# The answer is to move diagonally, into a quadrant. The first spike of each arm
# sits 44px out because closer than that the diagonal gap between two arms
# shrinks below the player's own width - at 34px it is 8px of clear floor, which
# is not an escape.
const CROSS_ARMS := 4
const CROSS_PER_ARM := 3
const CROSS_INNER := 32.0

# Where a SIX-arm cross has to start instead. At 44px six arms leave a 4px
# wedge, which is narrower than the player and so not an escape at all; at 64px
# it opens to 24px. This is the number to move if CROSS_ARMS ever grows again -
# the wedge is 2*inner*sin(PI/arms) - 40 and it has to stay above 14.
const CROSS_INNER_WIDE := 44.0
const CROSS_SPACING := 26.0
const CROSS_TELEGRAPH := 0.56
const CROSS_ROLL := 0.05

# CARPET: scattered spikes over a wide area, no shape to read.
#
# Sized to the room rather than to the player - 200x160 keeps it inside a 240px
# tall arena. Ten spikes cover about a third of that box, so there is always
# somewhere to stand, but not for long.
const CARPET_SPIKES := 12
const CARPET_WIDTH := 130.0
const CARPET_HEIGHT := 104.0
const CARPET_TELEGRAPH := 0.50
const CARPET_ROLL := 0.035

# Minimum distance between two carpet spikes. One spike diameter, which is
# exactly the point at which two of them stop overlapping - see the note in
# _pattern_carpet() for why that matters more here than anywhere else.
const CARPET_MIN_GAP := 30.0

# How many times to re-roll a clumped position before giving up on that spike.
const CARPET_PLACE_ATTEMPTS := 24

# GATE: walls sweeping across the player, each with a doorway to run through.
#
# NOT THE SAME THING AS THE RING'S GATES, despite the name. Those are late
# pillars inside a ring; these walls have real holes in them, and the attack is
# built around the holes rather than decorated with them.
#
# Five walls 52px apart sweep over the player one after another, so there is
# nowhere between them to simply stand - every wall has to be answered. The
# doorway is two pillars wide and slides by up to one slot per wall, so the way
# through is a line that bends and the player runs it rather than parking in it.
#
# 0.42s BETWEEN WALLS is 38px of movement, against the 46px it takes to shift a
# whole doorway slot sideways. That is deliberately just short: drifting one slot
# means the player has to already be moving when the next wall lands, not react
# to it. Simulated at 38.8% of floor survivable.
const GATE_WALLS := 5
const GATE_WALL_GAP := 32.0
const GATE_PILLARS := 7
const GATE_PITCH := 32.0
const GATE_STEP := 0.17
const GATE_DOOR_WIDTH := 2
const GATE_DRIFT_SLOTS := 1
const GATE_TELEGRAPH := 0.52

# SPIRAL: two arms winding outward from the boss, erupting root to tip.
#
# The only pattern here that is not centred on the player - it grows out of the
# BOSS, so where it is safe depends on where the player is standing relative to
# it, and the answer is to move with the rotation rather than away from it.
#
# Small pillars (14px) because an arm is a continuous curve and full-size ones
# cannot follow it without overlapping each other.
const SPIRAL_ARMS := 3
const SPIRAL_LENGTH := 7
const SPIRAL_START := 20.0
const SPIRAL_GROWTH := 10.0
const SPIRAL_TWIST := 0.70
const SPIRAL_ROLL := 0.06
const SPIRAL_SPIKE_RADIUS := 11.0
const SPIRAL_TELEGRAPH := 0.50

# How close the boss has to be to the player for the spiral to be worth casting.
#
# THE ONE PATTERN THAT IS NOT AIMED AT ANYBODY. Every other shape here is drawn
# around the player, so "is it near them" is true by construction. The spiral is
# drawn around the BOSS - that is its whole identity, and the reason it asks a
# different question - which also means that when the boss is across the room it
# is a firework going off in the corner. Measured, its spikes landed a median of
# 145px from the player and caught a running one 10% of the time, both far worse
# than anything else in the file.
#
# Shortening it helped and could not fix it, because the distance is not the
# spiral's size, it is the gap between the boss and the player. So the gap is
# what gets checked: the spiral stays boss-anchored and simply is not chosen
# when it would land nowhere near the fight. 130 is a little past the arm's
# reach at SPIRAL_START + SPIRAL_GROWTH * (SPIRAL_LENGTH - 1) = 80.
const SPIRAL_MAX_RANGE := 130.0


# =============================================================================
# PATTERN PACING
# =============================================================================
# THE COOLDOWN FOLLOWS THE PATTERN, and until it did the fight was unreadable.
#
# attack_cooldown is one number and the patterns are not one length. The ring
# set with its gates finishes 2.52s after it spawns; the cooldown was 1.5s. So
# the boss started its next cast a full second before the last one had left the
# floor, and TWO patterns were telegraphing on top of each other at all times.
# A gate arriving a fifth of a second late is invisible inside that - which is
# exactly why the gates could not be seen.
#
# So each cast now sets its own cooldown from the pattern it actually threw:
# the last spike's telegraph, plus the time that spike spends on screen, plus a
# breather. Big patterns get room; a quick lance comes straight back. The boss's
# rhythm varying with its move is a bonus rather than the point.

# How long a spike is on screen after its telegraph ends.
#
# MEASURED OFF THE SCENE AT STARTUP, not written down here. This number feeds
# every cooldown the boss uses, so a hardcoded copy going stale does not fail
# loudly - it just quietly re-introduces the overlapping-patterns bug that made
# the gates invisible. Re-time the spike art and the pacing follows it.
#
# The constant below is only the fallback for a scene that cannot be measured.
const SPIKE_LIFETIME_FALLBACK := 0.5
var _spike_lifetime: float = SPIKE_LIFETIME_FALLBACK

# How long the SPIKE track's hazard takes to RESOLVE - to reach the frame that
# deals its damage - as opposed to how long it takes to finish sinking.
#
# THE TWO TRACKS WAIT ON DIFFERENT THINGS, deliberately. The pillar track waits
# for its pattern to leave the floor completely, because two pillar patterns
# telegraphing at once is the unreadable mush that hid the gates. The spike
# track only waits for the hit to land: once a spike has reached full height and
# dealt its damage, the rest of its animation is aftermath, and holding the
# whole track hostage to aftermath is what made it slow.
#
# Concretely: a gate spike lives 1.33s but resolves at 0.33s. Waiting for the
# first number costs a full second of pressure per attack and buys nothing the
# player can act on.
var _gate_resolve: float = 0.35

# Quiet floor between one pattern clearing and the next appearing. Without some
# gap the next set of rings fades in as the last spikes sink, and the two read
# as one continuous event.
const PATTERN_BREATHER := 0.05


# =============================================================================
# EXPORTED SETTINGS — MELEE
# =============================================================================

# Inside this, the boss swings instead of casting.
#
# Comfortably past touching distance (its body is radius 10, the player's is 7,
# so they make contact at 17) because a swing that only lands at the exact pixel
# of contact never lands at all - the player is moving, and the check happens on
# the contact frame rather than when the swing started.
@export var melee_range: float = 40.0

# Frame of the nine-frame swing where the blow actually connects. Same idea as
# cast_frame above and as contact_frame on the bush mage: damage belongs on the
# frame the art makes contact, not at the start of the wind-up.
@export var melee_frame: int = 4

# Kept SEPARATE from attack_power, which the spikes use.
#
# Melee is the boss's answer to someone standing on top of it, and it asks for
# something the spike does not: the player has to already be inside its reach,
# with a swing they can still walk out of because the check happens on contact.
# Paying better for that is the point - if the two were one number, tuning the
# ranged attack would silently retune the melee.
#
# CALIBRATED AGAINST THE ACTUAL HEALTH POOLS, not picked for feel. Level-one
# classes have 110 (mage), 140 (healer), 180 (warrior) and 260 (tank), and
# player.gd reduces incoming damage by up to 50% at the top defence tier. At the
# old 24 this swing was chip damage - ten hits to drop a well-defended mage,
# twenty-two to drop a tank, which is not a boss punishing you for standing on
# it, it is a boss you can safely ignore at melee range. At 45:
#
#              raw          at 50% defence
#   mage       3 hits       5 hits
#   healer     4            7
#   warrior    4            9
#   tank       6           12
#
# Two and a half times the spike's 18, which is the shape this fight wants: the
# ranged attack is constant chip you dodge by moving, and the melee is the price
# of being close enough to hit back.
#
# THIS IS NOW THE FALLBACK, like attack_power. With a projectile_damage in the
# .tres the swing is MELEE_SHARE of it - the 45-against-34 this was tuned at -
# so each band's boss keeps this fight's shape at its own size. The swing still
# has its own number; it is a ratio now instead of a constant.
@export var melee_power: int = 45

# THE SHAPE OF THE FIGHT, AS RATIOS OF THE SPIKE. The swing and the stalker's
# trail were tuned at 45 and 22 against a 34 spike, and the band sets the
# spike. Written as the fractions they came from so the history is readable.
const MELEE_SHARE := 45.0 / 34.0
const TRAIL_SHARE := 22.0 / 34.0


# =============================================================================
# STATE
# =============================================================================

# One eruption per cast. frame_changed fires for every frame change, and an
# animation that restarts would otherwise stack rings on one cast — the same
# guard, for the same reason, as BushMage._vine_spawned_this_attack.
var _erupted_this_cast: bool = false

# Same guard for the melee swing, for the same reason.
var _swing_landed: bool = false

# Which attack THIS cycle is. Decided in _trigger_attack() and read by
# play_attack_animation(), because by the time the animation is being chosen the
# distance that justified the choice may already have changed - the player is
# moving, and an attack that picks its animation from a fresh distance check can
# play the swing while the eruption code is waiting for a cast frame that never
# comes.
var _swinging: bool = false

# The last shape the stalagmite clock raised, so it does not repeat itself
# back to back.
var _last_spike: StringName = &""

# Drives the stalker on its own clock. A TIMER RATHER THAN AN OVERRIDE of
# _physics_process, deliberately: this class does not override that method, and
# the note at the top of this file is about what overriding it costs - BushMage
# did and silently lost the leash and the slot geometry with it. A Timer gets
# the same behaviour without taking on that debt.
var _stalker_timer: Timer = null

# WHO WAS LAST ATTACKED WHEN, by instance id -> msec (next_target()).
var _last_aimed: Dictionary = {}
# The body the stalagmite clock attacked last, and the one its shapes are being
# built for right now (_aim_body()).
var _last_stalagmite_body: Node2D = null
var _aim_target: Node2D = null
# The volley the cast threw last, so a kit with more than one does not repeat.
var _last_volley: StringName = &""
# Swings since the last cast (SWINGS_BEFORE_CAST).
var _swings_in_a_row: int = 0


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var sprite: AnimatedSprite2D = $animatedsprite2d


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Stats BEFORE super._ready(), so BaseEnemy wires the health bar and the
	# attack timer with the right numbers. Guarded so a per-placement override
	# set in the Inspector still wins.
	if enemy_data == null:
		enemy_data = ENEMY_DATA

	# NOT SHOVED. player.gd's wade query skips anything in "unpushable" - its
	# comment names the boss as the thing that group is for - and nothing ever
	# joined it, so walking into a boss slowed you like a crowd and pushed it
	# across the floor like a slime.
	add_to_group(&"unpushable")
	# Every boss, so each can see how many partners are loose (_pace()).
	add_to_group(BOSS_GROUP)
	# BOSSES THAT SCALE: who is fighting it, looked at every SCALE_SECONDS.
	_scale_timer = Timer.new()
	_scale_timer.name = "scaletimer"
	_scale_timer.wait_time = SCALE_SECONDS
	_scale_timer.autostart = true
	_scale_timer.timeout.connect(_on_scale_tick)
	add_child(_scale_timer)

	# COMBAT TUNING LIVES HERE, not in the .tres — the .tres is the reward
	# profile. attack_range in particular is a statement about how this fight
	# is spaced, not a number that belongs in a data file.
	#
	# THE COOLDOWN HAS A HARD FLOOR OF 1.40s, AND IT IS DERIVED, NOT FELT.
	#
	# One attack occupies the floor for longer than the cast animation does. The
	# ring spawns at cast_frame 7, which is 0.70s into a ten-frame cast at speed
	# 10; it then fills for telegraph_seconds (0.9); the spike itself is five
	# frames at speed 10, another 0.50s. So a single attack is still on screen
	# 2.10s after its cast began, while the NEXT ring appears at
	# cooldown + 0.70s. Set the cooldown below 1.40 and two rings are live at
	# once - which is not a crash, it just stops the rings reading as individual
	# attacks, and the player can no longer tell which promise is about to be
	# kept.
	#
	# 1.5 is that floor plus a tenth of a second of daylight: 40 attacks a
	# minute where it used to be 25. If this needs to go faster still, the thing
	# to shorten is the telegraph or the cast animation - NOT this number, which
	# has nowhere left to go.
	attack_cooldown = 1.5
	attack_range = 120.0

	# THE BOSS DOES NOT RETREAT, AND UNTIL NOW IT DID.
	#
	# This class never set flee_range, so it inherited BaseEnemy's default of 40
	# — and _handle_combat() backs an enemy away whenever the player is closer
	# than that. So the boss was walking BACKWARDS out of its own melee range
	# every time the player closed, which is why the swing never happened: it
	# was not that the melee branch was missing, it was that the boss refused to
	# be anywhere the melee could trigger.
	#
	# It was not even a competent retreat. The boss moves at 45 and the player
	# at 90, so it could never open the gap - it just shuffled backwards while
	# being hit. Zero disables the flee branch outright.
	flee_range = 0.0

	super._ready()

	sprite.frame_changed.connect(_on_frame_changed)

	_measure_spike_lifetime()
	# THE CROWNED'S ALONE NOW (0.77.0, THE KITS).
	if bool(kit().get("stalkers", false)):
		_setup_stalker_timer()
	_setup_spike_timer()


func notice_reach() -> float:
	# A BOSS NOTICES AS FAR AS IT CHASES (0.30.0). Every other monster takes
	# notice inside notice_range, closer than its leash (BaseEnemy); a boss is
	# the fight its room is built round, and once its gate is open it comes for
	# whoever is in there, as it always did.
	return leash_range


func press_reach() -> float:
	# A BOSS HOLDS ITS SPACING (0.31.0). Other monsters walk in between attacks
	# to half their attack range (BaseEnemy, PRESSING IN); this fight is spaced
	# round attack_range (above) and melee_range decides swing or cast, so it
	# keeps standing where it can reach you, as it always did.
	return attack_range


# =============================================================================
# ANIMATION OVERRIDES
# =============================================================================

func play_attack_animation(dir: String) -> void:
	# Which animation plays IS which attack this is - _on_frame_changed() below
	# branches on the animation name, so these two must never disagree. That is
	# why the choice is made once in _trigger_attack() and only read here.
	if dir == "":
		return
	if _swinging:
		_set_animation(MELEE_PREFIX + dir)
	else:
		_set_animation(CAST_PREFIX + dir)


func _on_animation_finished() -> void:
	# AND THIS IS THE HALF THAT IS EASY TO MISS. BaseEnemy clears is_attacking
	# only when the finished animation begins with "attack" — so overriding the
	# animation above without also handling "cast" would leave is_attacking
	# true forever after the first cast, freezing the boss mid-fight with no
	# error to explain it.
	super._on_animation_finished()
	if net_mirror:
		return

	if not has_node("animatedsprite2d"):
		return
	if sprite.animation.begins_with(CAST_PREFIX):
		is_attacking = false
		play_idle_animation(attack_direction)


# =============================================================================
# ATTACK
# =============================================================================

func _trigger_attack() -> void:
	# Reset the guards, then let BaseEnemy set attack_ready, is_attacking, start
	# the cooldown and play the animation. The eruption and the blow are both
	# delivered from frame_changed, not here — this only opens the window.
	_erupted_this_cast = false
	_swing_landed = false

	# SWING OR CAST, DECIDED ONCE, BEFORE super PLAYS THE ANIMATION. super
	# immediately calls play_attack_animation(), which reads this.
	_swinging = is_instance_valid(player) \
		and global_position.distance_to(player.global_position) <= melee_range
	# FROM PHASE TWO A RUN OF SWINGS ENDS IN A CAST (0.77.0) - see
	# SWINGS_BEFORE_CAST.
	var cap: int = int(SWINGS_BEFORE_CAST[_current_phase()])
	if _swinging and cap > 0 and _swings_in_a_row >= cap:
		_swinging = false
	_swings_in_a_row = _swings_in_a_row + 1 if _swinging else 0

	super._trigger_attack()


func _on_frame_changed() -> void:
	# A MIRROR'S CAST IS A PICTURE. The spikes and the swing it would deliver
	# on these frames are the leader's, and arrive from monstersync.gd.
	if net_mirror:
		return
	var playing: String = sprite.animation

	if playing.begins_with(CAST_PREFIX):
		if _erupted_this_cast:
			return
		if sprite.frame != cast_frame:
			return
		_cast_signature()
		_erupted_this_cast = true
		return

	if playing.begins_with(MELEE_PREFIX):
		if _swing_landed:
			return
		if sprite.frame != melee_frame:
			return
		_land_swing()
		_swing_landed = true
		return

	# Outside either attack, reset both guards so the next one starts clean.
	# This also covers the idle -> attack transition without a separate hook.
	# Safe against the other animation names on this sheet: idle, walk, death
	# and hitflash begin with none of these prefixes.
	_erupted_this_cast = false
	_swing_landed = false


func _land_swing() -> void:
	# CHECKED ON THE CONTACT FRAME, not when the swing began - so stepping out of
	# reach during the wind-up actually works. That is the whole difference in
	# feel between this and the spikes: the spikes promise a piece of floor and
	# keep that promise whatever happens, while the swing is a live check against
	# wherever the player is at the moment of impact.
	#
	# The query is built here rather than cached because it runs once per swing,
	# at most a few times a second, and caching it would mean melee_range stopped
	# working as an Inspector value the moment anyone changed it mid-scene.
	var shape := CircleShape2D.new()
	shape.radius = melee_range

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = PLAYER_PHYSICS_LAYER
	query.collide_with_bodies = true
	# Areas ON, because some characters expose a hurtbox Area2D whose PARENT is
	# the real thing to damage. Same reason bossprojectile checks both lists.
	query.collide_with_areas = true
	var ignore_self: Array[RID] = [get_rid()]
	query.exclude = ignore_self

	# ONE hit per player, however many of their collision nodes are in reach.
	# A character with a body and a hurtbox on the same layer would otherwise
	# take the swing twice - the same dedupe bossprojectile does, for the same
	# reason.
	var already_hit: Array[int] = []

	for hit in get_world_2d().direct_space_state.intersect_shape(query, 8):
		var node: Object = hit.get("collider")
		if node == null or not is_instance_valid(node):
			continue

		# An Area2D stands in for its owner; a body speaks for itself.
		var target: Node = node as Node
		if node is Area2D:
			target = (node as Area2D).get_parent()

		if not _is_damageable_player(target):
			continue

		var id: int = target.get_instance_id()
		if id in already_hit:
			continue
		already_hit.append(id)

		HitSource.blame(HitSource.of(self, "swing"))
		target.take_damage(melee_damage(), current_element())

	# SHARED MONSTERS: the swing lands on every screen. This game's query only
	# ever finds this game's player; each other game runs the same query
	# around its copy of the boss, against its own player.
	if _net_sync != null and not net_mirror:
		_net_sync.leader_event(self, {"k": "m"})


func _is_damageable_player(node: Node) -> bool:
	return node != null \
		and node.is_in_group(&"player") \
		and node.has_method(&"take_damage")


# =============================================================================
# HOW HARD IT HITS: THE BAND, FROM THE BOSS'S OWN DATA
# =============================================================================
# All seven bosses run this script, and all seven used to hit for the same
# 34 / 45 / 22 whatever their .tres said - projectile_damage was set on six of
# them and read by nothing, because the spike is placed here rather than
# through BaseEnemy.spawn_projectile_node(). So when the normals moved into
# element bands the bosses stayed put: the Crowned's spike (37 after dark's
# profile) hit softer than a dark bush mage (55), and the light boss hit
# nearly three times as hard as anything around it.
#
# The spike is projectile_damage now, 1.5x its band's normal hit, and the swing
# and the trail follow it by the shares above. The element profile still
# scales the spike and the trail on top (earth x1.25 down to water x0.85), so
# the bosses of one band still differ by element; the band sets the size.
#
# Read from ENEMY_DATA when enemy_data is still null, which is exactly what
# _ready() does - so a bare bossenemy.tscn outside the tree answers as the
# Crowned it will become, not as the fallback.

func _damage_data() -> EnemyData:
	return enemy_data if enemy_data != null else ENEMY_DATA


func spike_damage() -> int:
	var data: EnemyData = _damage_data()
	if data != null and data.projectile_damage > 0:
		return data.projectile_damage
	return attack_power


func melee_damage() -> int:
	var data: EnemyData = _damage_data()
	if data != null and data.projectile_damage > 0:
		return maxi(1, roundi(data.projectile_damage * MELEE_SHARE))
	return melee_power


# 0 means "the stalker's own pillar_damage", the same convention
# projectile_damage itself uses.
func trail_damage() -> int:
	var data: EnemyData = _damage_data()
	if data != null and data.projectile_damage > 0:
		return maxi(1, roundi(data.projectile_damage * TRAIL_SHARE))
	return 0


func _setup_spike_timer() -> void:
	_spike_timer = Timer.new()
	_spike_timer.one_shot = false
	_spike_timer.wait_time = 2.0
	_spike_timer.timeout.connect(_on_spike_timer)
	add_child(_spike_timer)
	_spike_timer.start()


func _on_spike_timer() -> void:
	# A mirror's clocks are paused (net_set_mirror), and this says so again:
	# its spikes are the leader's.
	if net_mirror:
		return
	# IN A FIGHT ONLY. Dying, dead, caged, walking home on the leash - or with
	# nobody near - the boss is not fighting anyone, and stalagmites erupting
	# in an empty room read as a bug rather than an attack.
	if not in_fight():
		_spike_timer.wait_time = 2.0
		return

	_cast_spike_pattern()


func _cast_spike_pattern() -> void:
	# THE STALAGMITE CLOCK (0.77.0): one of this boss's own three shapes (THE
	# KITS), at whoever in the fight it has left alone longest.
	if gate_scene == null or eruption_scene == null:
		return

	var container: Node = get_tree().get_first_node_in_group("groundeffects")
	if container == null:
		container = get_tree().current_scene
	if container == null:
		return

	var target: Node2D = next_target(_last_stalagmite_body)
	if target == null:
		_spike_timer.wait_time = 2.0
		return
	_last_stalagmite_body = target
	_mark_aimed(target)

	var phase: int = _current_phase()
	var pool: Array[StringName] = stalagmite_pool(phase)

	# The spiral is drawn around the boss rather than the player, so it is only
	# an attack while the two are close. See SPIRAL_MAX_RANGE.
	if global_position.distance_to(target.global_position) > SPIRAL_MAX_RANGE and pool.size() > 1:
		pool.erase(&"spiral")

	var choice: StringName = pool[randi() % pool.size()]
	var guard: int = 0
	while choice == _last_spike and pool.size() > 1 and guard < 32:
		choice = pool[randi() % pool.size()]
		guard += 1
	_last_spike = choice

	# Built for THIS target: _aim_point() and _player_velocity() read
	# _aim_body(), which is it for as long as the shape is being laid out.
	_aim_target = target
	var origin: Vector2 = _aim_point()
	var pattern: Array[Dictionary] = _lead_pattern(
		_pattern_by_name(choice, origin), choice)
	_aim_target = null

	var scene: PackedScene = eruption_scene if choice in PILLAR_SHAPES else gate_scene
	var last: float = 0.0
	for spike in pattern:
		last = maxf(last, float(spike["telegraph"]))
		var pos: Vector2 = clamp_to_navigation(spike["pos"])
		_spawn_one_eruption(container, pos, float(spike["telegraph"]),
			float(spike.get("radius", PILLAR_RADIUS)), scene)

	# Paced off its own shape. A pillar shape waits for its pillars to leave
	# the floor - two of those telegraphing at once is the mush that hid the
	# gates (PATTERN PACING); a spike shape only for its hit to land (see
	# _gate_resolve). Then the wave's pace on top (_pace()).
	var clear: float = _spike_lifetime + PATTERN_BREATHER if scene == eruption_scene \
		else _gate_resolve + SPIKE_BREATHER + float(SPIKE_EXTRA_GAP[phase])
	_spike_timer.wait_time = maxf(0.2, (last + clear) * float(PHASE_TEMPO[phase]) * _pace())

	if debug_patterns:
		print("[BOSS] phase %d  STALAGMITES %s at %s  (next in %.2fs)"
			% [phase + 1, choice, target.name, _spike_timer.wait_time])


func _measure_spike_lifetime() -> void:
	var pillar: Vector2 = _measure_scene_timing(eruption_scene)
	if pillar.x > 0.0:
		_spike_lifetime = pillar.x

	var gate: Vector2 = _measure_scene_timing(gate_scene)
	if gate.y > 0.0:
		_gate_resolve = gate.y


# Returns (total run time, time until the damage frame) for a hazard scene, in
# seconds. Zeroes if it cannot be read.
#
# MEASURED RATHER THAN WRITTEN DOWN, because these numbers feed every cooldown
# the boss uses and a stale copy does not fail loudly - it quietly re-creates
# the overlapping-patterns bug that made the gates invisible. Re-time the art
# and the pacing follows on its own.
func _measure_scene_timing(scene: PackedScene) -> Vector2:
	if scene == null:
		return Vector2.ZERO

	# Instantiated and thrown away WITHOUT ever entering the tree, so its
	# _ready() never runs: nothing validates, hides itself or starts a
	# telegraph. All that is read is authored data.
	var probe: Node = scene.instantiate()

	# NAMED probe_sprite, NOT sprite. `sprite` is this class's own @onready
	# reference to the BOSS's AnimatedSprite2D, and a local of that name shadows
	# it for the rest of the function — which reads fine here, and is one await
	# away from being the firepit bug, where a member shadowed by a local across
	# a suspension point left the wrong node being animated. Godot warns about
	# it (SHADOWED_VARIABLE) for that reason. The rename also says the true
	# thing: this is the probe's sprite, not the boss's.
	var probe_sprite: AnimatedSprite2D = probe.get_node_or_null("animatedsprite2d") as AnimatedSprite2D

	var result: Vector2 = Vector2.ZERO
	if probe_sprite != null and probe_sprite.sprite_frames != null \
			and probe_sprite.sprite_frames.has_animation(&"projectile"):
		var frames: SpriteFrames = probe_sprite.sprite_frames
		var speed: float = frames.get_animation_speed(&"projectile")
		if speed > 0.0:
			# The hazard's own impact_frame, read off the instance - the two
			# hazards do not agree on it, and guessing is how damage ends up
			# landing while the spike is still visibly underground.
			var impact: int = 1
			if "impact_frame" in probe:
				impact = int(probe.get("impact_frame"))

			# Summed rather than assumed equal: SpriteFrames allows per-frame
			# durations, and both these scenes now hold their impact frame
			# several times longer than the rest.
			var total: float = 0.0
			var to_impact: float = 0.0
			for i in range(frames.get_frame_count(&"projectile")):
				var d: float = frames.get_frame_duration(&"projectile", i)
				if i < impact:
					to_impact += d
				total += d
			result = Vector2(total / speed, to_impact / speed)

	probe.free()
	return result


func _pattern_arc(origin: Vector2) -> Array[Dictionary]:
	# The spike track's light attack: a short arc near the player, with the
	# whole rest of the circle open. Cheap to answer on purpose - it is the
	# filler between the heavier spike patterns, not a thing that kills alone.
	#
	# TRAP_RADIUS AND TRAP_SPAN ARE A PAIR, not two free numbers. Spikes need
	# 28px between centres or two of them overlap, and arc length is radius
	# times angle - so at 70px and 100 degrees five spikes land 30.5px apart,
	# which clears it. Pull the radius in or narrow the span without dropping
	# the count and they start overlapping: at 60px and 80 degrees five spikes
	# are 20.9px apart, with three of them inside each other.
	var count: int = maxi(int(TRAP_COUNT[_current_phase()]), 1)
	var span: float = deg_to_rad(TRAP_SPAN)
	var bearing: float = randf() * TAU
	var step: float = span / float(maxi(count - 1, 1))

	# THE SPIKE ON THE PLAYER. Without it the arc is a curve 70px away from
	# wherever the player is predicted to be, which means a player running in a
	# straight line is led into the exact middle of it and never touched - the
	# lead makes a ring-shaped pattern MISS a runner rather than catch one. Every
	# pattern drawn around the player needs something at its centre for that
	# reason; see the same spike in _pattern_ring, _pattern_triwall and
	# _pattern_sweep.
	var out: Array[Dictionary] = [{
		"pos": origin,
		"telegraph": TRAP_TELEGRAPH,
	}]

	for i in range(count):
		var a: float = bearing - span * 0.5 + step * float(i)
		out.append({
			"pos": origin + Vector2(cos(a), sin(a)) * TRAP_RADIUS,
			"telegraph": TRAP_TELEGRAPH,
		})
	return out


func _pattern_triwall(origin: Vector2) -> Array[Dictionary]:
	# Three walls at a time, three times over. See the TRIWALL block for why
	# three at once is a different question from three in a row, and why the
	# pillar count per wall is computed here instead of being a constant.
	var out: Array[Dictionary] = []
	var base: float = randf() * TAU

	# CLOSING OR OPENING, picked per cast. Closing walks the player's back to a
	# wall; opening pushes them out through ranks that are getting wider, which
	# sounds easier and is not - the doorways are further apart every beat, so
	# committing to the wrong one costs the whole pattern.
	var inward: bool = randf() < 0.5
	var ranks: Array = TRIWALL_RANKS.duplicate()
	if not inward:
		ranks.reverse()

	# The centre goes first when the walls close in and last when they open out,
	# so in both cases it is the end of the route that lands on the player rather
	# than an afterthought in the middle of one. _pattern_ring() does the same.
	var centre_slot: int = 0 if inward else ranks.size()
	out.append({
		"pos": origin,
		"telegraph": TRIWALL_TELEGRAPH + float(centre_slot) * TRIWALL_RANK_STEP,
	})

	for k in range(ranks.size()):
		var dist: float = float(ranks[k])

		# tan(60) is half the triangle's side over its inradius; the corner
		# clearance comes off the end of every wall. See TRIWALL_CORNER_CLEAR.
		var half_span: float = dist * tan(PI / 3.0) - TRIWALL_CORNER_CLEAR
		var reach: int = maxi(int(floor(half_span / TRIWALL_PITCH)), 0)
		var pillars: int = reach * 2 + 1

		var slot: int = (k + 1) if inward else k
		var lands: float = TRIWALL_TELEGRAPH + float(slot) * TRIWALL_RANK_STEP

		for w in range(TRIWALL_WALLS):
			var a: float = base + TAU * float(w) / float(TRIWALL_WALLS)
			var toward: Vector2 = Vector2(cos(a), sin(a))
			var across: Vector2 = Vector2(-toward.y, toward.x)

			# NO DOORWAY ON A WALL TOO SHORT TO HAVE ONE. A door needs a pillar
			# either side of it to read as a door rather than as the wall simply
			# being shorter, and the inner rank is one pillar wide.
			var door: int = -1
			if pillars > TRIWALL_DOOR_WIDTH + 2:
				door = randi_range(1, pillars - TRIWALL_DOOR_WIDTH - 1)

			for i in range(pillars):
				if door >= 0 and i >= door and i < door + TRIWALL_DOOR_WIDTH:
					continue
				out.append({
					"pos": origin + toward * dist
						+ across * ((float(i) - float(reach)) * TRIWALL_PITCH),
					"telegraph": lands,
				})

	return out


func _pattern_rake(origin: Vector2) -> Array[Dictionary]:
	# Solid rows with lanes between them, sweeping one way. See the RAKE block:
	# this is the one pattern here whose answer is to hold still.
	var heading: float = randf() * TAU
	var sweep: Vector2 = Vector2(cos(heading), sin(heading))
	var across: Vector2 = Vector2(-sweep.y, sweep.x)

	var out: Array[Dictionary] = []
	var centre: float = float(RAKE_PILLARS - 1) * 0.5
	var first: float = float(RAKE_ROWS - 1) * 0.5

	for r in range(RAKE_ROWS):
		var along: float = (first - float(r)) * RAKE_ROW_GAP

		# Half a pitch on every other row, so the daylight between pillars never
		# lines up into a lane running through the whole rake.
		var shift: float = 0.5 if r % 2 == 1 else 0.0

		for i in range(RAKE_PILLARS):
			out.append({
				"pos": origin + sweep * along
					+ across * ((float(i) - centre + shift) * RAKE_PITCH),
				"telegraph": RAKE_TELEGRAPH + float(r) * RAKE_STEP,
			})

	return out


func _pattern_snare(origin: Vector2) -> Array[Dictionary]:
	# Eight spikes close the circle, the ninth is late. See the SNARE block.
	var phase: float = randf() * TAU
	var gap: int = randi() % SNARE_SPIKES

	# THE MIDDLE GOES WHEN THE GAP DOES, which is what turns the snare from a
	# fence into a demand. The collar closes, one spike is late and shows you the
	# way out, and the ground you are standing on opens at the same moment that
	# last spike arrives - so the gap is not an option, it is the only answer.
	# It also stops a led pattern from depositing a running player in its own
	# hole; see the note in _pattern_arc.
	var out: Array[Dictionary] = [{
		"pos": origin,
		"telegraph": SNARE_TELEGRAPH + SNARE_GAP_DELAY,
	}]

	for i in range(SNARE_SPIKES):
		var a: float = phase + TAU * float(i) / float(SNARE_SPIKES)
		out.append({
			"pos": origin + Vector2(cos(a), sin(a)) * SNARE_RADIUS,
			"telegraph": SNARE_TELEGRAPH + (SNARE_GAP_DELAY if i == gap else 0.0),
		})
	return out


func _pattern_ladder(origin: Vector2) -> Array[Dictionary]:
	# Rungs down the road the player is running. See the LADDER block - this one
	# aims itself and must stay out of _lead_pattern().
	var vel: Vector2 = _player_velocity()
	var run: Vector2 = vel

	# STANDING STILL STILL GETS A LADDER, laid along the way out - directly away
	# from the boss, which is where a cornered player goes. It is the road they
	# are about to take rather than the one they are on.
	if run.length() < 8.0:
		run = origin - global_position
	if run.length() < 1.0:
		run = Vector2.RIGHT

	var dir: Vector2 = run.normalized()
	var across: Vector2 = Vector2(-dir.y, dir.x)

	var speed: float = vel.length()
	var moving: bool = speed >= LADDER_MOVING_SPEED

	var out: Array[Dictionary] = []
	var centre: float = float(LADDER_PILLARS - 1) * 0.5

	for k in range(LADDER_RUNGS):
		var lands: float = LADDER_TELEGRAPH + float(k) * LADDER_STEP

		var ahead: float = 0.0
		if moving:
			# Exactly where they will be at that moment, at the pace they are
			# keeping now. This is the pattern doing its job.
			ahead = speed * lands * LADDER_LEAD
		else:
			# STANDING STILL, so there is no road to lay rungs down. The first
			# lands ON them and the rest march outward - see LADDER_MOVING_SPEED
			# for what the old floor did to this case.
			ahead = float(k) * LADDER_STANDING_SPACING

		for i in range(LADDER_PILLARS):
			out.append({
				"pos": origin + dir * ahead + across * ((float(i) - centre) * LADDER_PITCH),
				"telegraph": lands,
			})

	return out


func _pattern_sweep(origin: Vector2) -> Array[Dictionary]:
	# A turning arm rather than a stamped shape. See the SWEEP block.
	var base: float = randf() * TAU
	var turn: float = deg_to_rad(SWEEP_TURN)
	if randf() < 0.5:
		turn = -turn

	var out: Array[Dictionary] = []
	for b in range(SWEEP_BEATS):
		var a: float = base + turn * float(b)
		var dir: Vector2 = Vector2(cos(a), sin(a))
		var lands: float = SWEEP_TELEGRAPH + float(b) * SWEEP_STEP
		for i in range(SWEEP_ARM):
			out.append({
				"pos": origin + dir * (SWEEP_INNER + SWEEP_SPACING * float(i)),
				"telegraph": lands,
			})

	# The hub, last. Without it the point the arm turns around is a place to
	# stand and wait, which would make the whole sweep free.
	out.append({
		"pos": origin,
		"telegraph": SWEEP_TELEGRAPH + float(SWEEP_BEATS) * SWEEP_STEP,
	})
	return out


func _pattern_checker(origin: Vector2) -> Array[Dictionary]:
	# Black squares, then white. See the CHECKER block.
	#
	# ROTATED AT RANDOM, because a lattice squared up to the world is a lattice
	# the player can learn once and step through on muscle memory forever.
	var tilt: float = randf() * TAU
	var ux: Vector2 = Vector2(cos(tilt), sin(tilt)) * CHECKER_PITCH
	var uy: Vector2 = Vector2(-ux.y, ux.x)

	# Which colour opens first, and therefore whether the square the player is
	# standing on right now is the trap or the answer.
	var first: int = randi() % 2

	var out: Array[Dictionary] = []

	# THE TRUNCATION IS THE POINT, which is why the warning is silenced rather
	# than the arithmetic changed. The loop below runs range(-half, half + 1),
	# so the grid comes out 2*half + 1 cells per side. At CHECKER_CELLS = 5 that
	# is half = 2 and exactly 5 cells, which is what the constant promises.
	#
	# IT ONLY PROMISES THAT FOR AN ODD VALUE. Set CHECKER_CELLS to 6 and you get
	# 7 cells per side and 49 spikes instead of 36 — the constant would quietly
	# mean something other than its name. Keep it odd, or change the loop too.
	@warning_ignore("integer_division")
	var half: int = CHECKER_CELLS / 2

	for i in range(-half, half + 1):
		for j in range(-half, half + 1):
			var parity: int = posmod(i + j, 2)
			var beat: int = 0 if parity == first else 1
			out.append({
				"pos": origin + ux * float(i) + uy * float(j),
				"telegraph": CHECKER_TELEGRAPH + float(beat) * CHECKER_BEAT,
			})

	return out


func _setup_stalker_timer() -> void:
	_stalker_timer = Timer.new()
	_stalker_timer.one_shot = false
	_stalker_timer.wait_time = STALKER_INTERVAL_PHASE_TWO
	_stalker_timer.timeout.connect(_on_stalker_timer)
	add_child(_stalker_timer)
	_stalker_timer.start()


func _on_stalker_timer() -> void:
	# RE-READ THE INTERVAL EVERY TIME rather than reconfiguring the timer when
	# the phase changes. There is no "phase changed" event to hook - the phase
	# is derived from current health - so anything that had to be told would
	# need one inventing. Asking here costs nothing and cannot fall out of sync.
	if net_mirror:
		return
	var phase: int = _current_phase()
	_stalker_timer.wait_time = STALKER_INTERVAL_PHASE_THREE if phase >= 2 \
		else STALKER_INTERVAL_PHASE_TWO

	if phase < STALKER_FROM_PHASE:
		return
	if not in_fight():
		return

	# The next one in the fight, like every attack (0.77.0).
	var target: Node2D = next_target()
	if target == null:
		return
	_mark_aimed(target)
	_spawn_stalker(target)


func _spawn_stalker(target: Node2D = null) -> void:
	if target == null:
		target = player as Node2D
	if not is_instance_valid(target):
		return
	var container: Node = get_tree().get_first_node_in_group("groundeffects")
	if container == null:
		container = get_tree().current_scene
	if container == null:
		return

	var stalker: Node2D = Node2D.new()
	stalker.set_script(STALKER_SCRIPT)
	container.add_child(stalker)

	# Pushed out of the boss toward the player so it does not spend its first
	# second walking out of the thing that made it.
	var away: Vector2 = (target.global_position - global_position).normalized()
	if away == Vector2.ZERO:
		away = Vector2.DOWN
	stalker.global_position = global_position + away * STALKER_SPAWN_OFFSET
	# Placed, not moved (0.72.2): drawn its first frame on the way in from the
	# container's origin otherwise.
	stalker.reset_physics_interpolation()

	# RESOLVED HERE, NOT IN THE STALKER. bossstalker.gd is not a BaseEnemy and
	# has no element of its own — it drops whatever pillar it was handed. Handing
	# it the resolved variant means its trail wears the boss's element without
	# the stalker needing to know elements exist, and its pillars pick up the
	# element from the scene rather than staying NONE, which is what they were.
	stalker.setup(target, Projectiles.variant_of(eruption_scene, current_element()), trail_damage(),
		current_element())
	# Whose trail it is, so each pillar it drops can be shown on every screen.
	stalker.net_owner = self

	if debug_patterns:
		print("[BOSS] stalker released (phase %d)" % [_current_phase() + 1])


# Which phase the fight is in: 0, 1 or 2.
func _current_phase() -> int:
	var frac: float = float(hp) / float(maxi(max_hp, 1))
	if frac > PHASE_TWO_AT:
		return 0
	if frac > PHASE_THREE_AT:
		return 1
	return 2


# The shape of one cast, as a list of { "pos": Vector2, "telegraph": float }.
#
# SEPARATED FROM SPAWNING ON PURPOSE. A pattern is pure geometry - it can be
# reasoned about, and checked, without a scene tree. Everything about whether
# an attack is survivable lives in these five functions and nowhere else.
func _aim_point() -> Vector2:
	# WHERE THE PLAYER IS. The lead used to be baked in here, off a single fixed
	# telegraph for every pattern; it now happens per spike in _lead_pattern(),
	# which is the only place that knows when each spike actually lands.
	#
	# WHICH PLAYER is _aim_body()'s (0.77.0): whoever the shape is being laid
	# out for, which is not always the one the boss is walking toward.
	var body: Node2D = _aim_body()
	if body == null:
		return global_position

	# THE GROUND THEY ARE STANDING ON, WHICH IS NOT THEIR NODE ORIGIN.
	#
	# Every pattern in this file is a promise about a piece of FLOOR, and the
	# floor a character occupies is where their body collision is - not where
	# the scene happens to put their origin. Those two are not the same and the
	# four playable classes do not even agree on the sign: the warrior's body
	# sits 13px below its origin, the tank's 18px above, the mage and healer a
	# few px above. Aiming at the origin therefore misses by up to 31px
	# depending on who is playing, which against a 14px spike is most of the
	# margin - and it is the difference between a pattern that reads as tight
	# and one that reads as broken.
	# Targets.body_point() is that same body, and every other enemy's sight
	# line and aim go through it too (6 Oct: they used the origin, and held
	# fire at a player pressed against a wall).
	return Targets.body_point(body)


func _aim_body() -> Node2D:
	"""Who a shape is being laid out for: the stalagmite clock's target while
	it builds one, otherwise the one the boss is facing."""
	if is_instance_valid(_aim_target):
		return _aim_target
	return player as Node2D if is_instance_valid(player) else null


func _player_velocity() -> Vector2:
	# ANY TARGET THAT KNOWS ITS SPEED. The local player is a CharacterBody2D;
	# another player's picture (shared monsters) works its velocity out from
	# the positions it is sent. Either way the boss leads a runner.
	return _velocity_of(_aim_body())


func _velocity_of(body: Node) -> Vector2:
	if not is_instance_valid(body):
		return Vector2.ZERO
	var v: Variant = body.get("velocity")
	return v if v is Vector2 else Vector2.ZERO


# Slides every spike along the player's heading by however long that spike has
# left before it erupts. See AIM_LEAD for why this is per spike and not per
# pattern, and why the ranks are allowed to shear into each other.
func _lead_pattern(pattern: Array[Dictionary], pattern_name: StringName) -> Array[Dictionary]:
	if pattern_name in SELF_AIMED:
		return pattern

	var vel: Vector2 = _player_velocity()

	# A stationary player gets no lead at all, which is correct: the pattern
	# lands exactly on them. Squared length, so a player being nudged by a
	# collision does not count as running.
	if vel.length_squared() < 64.0:
		return pattern

	for spike in pattern:
		var shift: Vector2 = vel * float(spike["telegraph"]) * AIM_LEAD
		if shift.length() > AIM_LEAD_MAX:
			shift = shift.normalized() * AIM_LEAD_MAX
		spike["pos"] = (spike["pos"] as Vector2) + shift
	return pattern


func _pattern_by_name(pattern_name: StringName, origin: Vector2) -> Array[Dictionary]:
	# EVERY NAME EITHER TRACK CAN THROW HAS TO BE HERE. The fallback is the ring,
	# which is a pillar pattern - so a spike-track name missing from this list
	# does not fail, it quietly casts a sixty-five pillar shockwave out of the
	# spike timer with no cast animation in front of it. That is how a typo in a
	# pool turns into a bug that looks like a balance problem.
	match pattern_name:
		&"cage":    return _pattern_cage(origin)
		&"gate":    return _pattern_gate(origin)
		&"lance":   return _pattern_lance(origin)
		&"cross":   return _pattern_cross(origin)
		&"spiral":  return _pattern_spiral(origin)
		&"carpet":  return _pattern_carpet(origin)
		&"arc":     return _pattern_arc(origin)
		&"triwall": return _pattern_triwall(origin)
		&"rake":    return _pattern_rake(origin)
		&"snare":   return _pattern_snare(origin)
		&"ladder":  return _pattern_ladder(origin)
		&"sweep":   return _pattern_sweep(origin)
		&"checker": return _pattern_checker(origin)
		_:          return _pattern_ring(origin)


func _pattern_ring(origin: Vector2) -> Array[Dictionary]:
	# A SHOCKWAVE, NOT A SNAPSHOT. One spike on the player so standing still is
	# never an answer, then three concentric rings erupting in sequence. The
	# player is not dodging a shape, they are running a route through it.
	#
	# TWO DIRECTIONS, PICKED AT RANDOM, and they demand opposite instincts:
	#
	#   OUTWARD  centre first, rings expanding. Feels like an explosion; the
	#            answer is to move out through each gap as it opens.
	#   INWARD   outer ring first, collapsing toward the player. Every instinct
	#            says run from the boss, and running is exactly wrong - the safe
	#            ground is behind you, toward the middle.
	#
	# Both were simulated before being used: outward leaves 15% of the floor
	# standable, inward 14%. Neither can be outrun.
	#
	# A FRESH ROTATION EVERY CAST. Fixed compass points would let the fight be
	# solved once and replayed from memory - always break north-east, forever.
	var out: Array[Dictionary] = []
	var phase: float = randf() * TAU
	var inward: bool = randf() < 0.5
	var ring_count: int = RING_COUNTS.size()

	# The centre spike goes first when the wave expands and LAST when it
	# collapses, so in both cases it is the end of the route that lands on the
	# player rather than an afterthought in the middle of one.
	var centre_slot: int = ring_count if inward else 0
	out.append({
		"pos": origin,
		"telegraph": eruption_telegraph + float(centre_slot) * RING_STAGGER,
		"radius": float(RING_SPIKE_RADII[0]),
	})

	# THE WAY OUT, chosen once and then bent ring by ring. Each ring's gates are
	# the pillars nearest this heading, so they line up into a corridor rather
	# than scattering into unrelated holes - and the drift means that corridor
	# curves, so it has to be followed instead of aimed at from the middle.
	var corridor: float = randf() * TAU

	for k in range(ring_count):
		var count: int = RING_COUNTS[k]
		if count <= 0:
			continue

		# EVERY OTHER RING IS ROTATED HALF A STEP so its spikes sit behind the
		# previous ring's GAPS rather than behind its spikes. Lined up, the rings
		# form spokes with clear lanes running straight out between them and
		# everything past the first ring is decoration; offset, getting through
		# means moving sideways as well as outward.
		var offset: float = (PI / float(count)) if k % 2 == 1 else 0.0

		# Ring k is the (k+1)th thing to erupt going out, and the reverse coming
		# in. The centre occupies the slot at whichever end that leaves.
		var slot: int = (ring_count - 1 - k) if inward else (k + 1)
		var lands: float = eruption_telegraph + float(slot) * RING_STAGGER
		var spike_r: float = float(RING_SPIKE_RADII[k])

		corridor += randf_range(-RING_GATE_DRIFT, RING_GATE_DRIFT)

		for i in range(count):
			var a: float = phase + offset + TAU * float(i) / float(count)

			# A pillar within half a gate's width of the corridor heading is a
			# GATE: same place, same pillar, just late. Measuring by angle rather
			# than by index means the gates stay put as the ring rotates, which
			# is what keeps the corridor continuous from one ring to the next.
			var off_corridor: float = absf(angle_difference(a, corridor))
			var gate_span: float = TAU * float(RING_GATES) / float(count) * 0.5
			var is_gate: bool = off_corridor <= gate_span

			out.append({
				"pos": origin + Vector2(cos(a), sin(a)) * float(RING_RADII[k]),
				"telegraph": lands + (RING_GATE_DELAY if is_gate else 0.0),
				"radius": spike_r,
			})

	return out


func _pattern_cage(origin: Vector2) -> Array[Dictionary]:
	# TWO WALLS NOW, one inside the other, with their doorways on the SAME
	# bearing. The inner wall lands first and the outer a moment later, so the
	# player has to commit to the doorway immediately and keep running through
	# both - getting out of the first wall and then stopping is how the second
	# one catches you.
	#
	# Aligned doorways rather than offset ones on purpose. Offset would make it
	# a maze, and a maze at this size is not readable inside a second; aligned
	# makes it a single decision taken early, which is a different and better
	# kind of pressure.
	var out: Array[Dictionary] = []
	var phase: float = randf() * TAU
	var doorway: float = randf() * TAU

	for k in range(CAGE_COUNTS.size()):
		var count: int = CAGE_COUNTS[k]
		var radius: float = float(CAGE_RADII[k])
		var lands: float = CAGE_TELEGRAPH + float(k) * CAGE_RING_STEP

		# One pillar's worth of doorway, measured by angle so it stays the same
		# physical width on both walls despite the outer one holding more.
		var span: float = TAU / float(count) * 0.5

		for i in range(count):
			var a: float = phase + TAU * float(i) / float(count)

			# The doorway pillar is placed like all the others and simply warns
			# for longer, so the player sees a wall that is a fraction slower to
			# close on one side. That is the tell - and standing in it is only
			# safe for a moment.
			var is_door: bool = absf(angle_difference(a, doorway)) <= span

			out.append({
				"pos": origin + Vector2(cos(a), sin(a)) * radius,
				"telegraph": lands + (CAGE_DOOR_DELAY if is_door else 0.0),
			})

	# THE MIDDLE COLLAPSES LAST, after both walls have closed. Hiding in the
	# centre while a cage builds around you is the obvious move and it was, until
	# now, completely free - the doorway was an option rather than the answer.
	# This makes it the answer. It is also what stops the cage missing a running
	# player entirely, for the reason written out in _pattern_arc.
	out.append({
		"pos": origin,
		"telegraph": CAGE_TELEGRAPH + float(CAGE_COUNTS.size()) * CAGE_RING_STEP
			+ CAGE_DOOR_DELAY,
	})

	return out


func _pattern_lance(origin: Vector2) -> Array[Dictionary]:
	# Fired from the BOSS through the player and out the far side, so it always
	# reads as coming from the thing that cast it. Rolling outward one spike at
	# a time is what makes it a wave rather than a row.
	var dir: Vector2 = (origin - global_position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT

	# A SECOND LANCE ACROSS THE FIRST, a third of the time. One lance is beaten
	# by stepping either way off it, which is the same decision every time it
	# appears; crossed at 60 degrees it closes one of those two sides, so the
	# player has to notice WHICH way is still open instead of just moving.
	var blades: int = 2 if randf() < 0.33 else 1
	var spread: float = deg_to_rad(60.0)

	# THE TRUNCATION IS THE POINT, same as _pattern_checker above, which is why
	# the warning is silenced rather than the arithmetic changed. Spikes are laid
	# at indices 0..LANCE_SPIKES-1 and this is the one the blade is centred on.
	# At LANCE_SPIKES = 5 that is index 2, with two spikes either side of it.
	#
	# IT ONLY LANDS ON THE PLAYER FOR AN ODD VALUE. Set LANCE_SPIKES to 6 and mid
	# is 3, which is the spike just PAST centre — the blade would sit half a step
	# off the player, and the second blade would skip the wrong one. Keep it odd.
	#
	# Hoisted out of the loop because it was written twice below, and the two
	# copies have to agree: the spike the blade is centred on is the same spike
	# the crossing blade skips. Two expressions that must stay equal are one
	# edit away from not being.
	@warning_ignore("integer_division")
	var mid: int = LANCE_SPIKES / 2

	var out: Array[Dictionary] = []
	for b in range(blades):
		var d: Vector2 = dir.rotated(-spread * 0.5 + spread * float(b)) if blades > 1 else dir
		# Centred on the player so the middle of each blade passes through them.
		var start: Vector2 = origin - d * LANCE_SPACING * float(mid)
		for i in range(LANCE_SPIKES):
			# The centre spike of the second blade would land on top of the
			# first blade's, so it is skipped - two spikes in one place is the
			# overlap this whole file is built to avoid.
			if b > 0 and i == mid:
				continue
			out.append({
				"pos": start + d * LANCE_SPACING * float(i),
				"telegraph": LANCE_TELEGRAPH + float(i) * LANCE_ROLL,
			})
	return out


func _pattern_cross(origin: Vector2) -> Array[Dictionary]:
	# Four arms from where the player stands, rolling outward. The answer is to
	# move diagonally into a quadrant - which is why the arms start 44px out,
	# far enough that the diagonal gap is wider than the player.
	# FOUR ARMS OR SIX. Six narrows every escape wedge, so the same shape asks a
	# noticeably harder question without becoming a different attack - and the
	# player cannot tell which it is until the rings appear.
	#
	# Six is the most the geometry allows. The arms are 44px out at their
	# closest, where a wedge between six arms is 2*44*sin(30) - 40 = 4px of
	# clear floor... which is nothing. So a six-arm cross pushes its inner ring
	# out to CROSS_INNER_WIDE, where that wedge opens back up to a real gap.
	var arms: int = 6 if randf() < 0.35 else CROSS_ARMS
	var inner: float = CROSS_INNER_WIDE if arms > CROSS_ARMS else CROSS_INNER

	# The hub the arms radiate from, which is otherwise the safest ground in the
	# pattern and exactly where a led pattern puts a running player. Same spike,
	# same reason, as _pattern_arc's.
	var out: Array[Dictionary] = [{
		"pos": origin,
		"telegraph": CROSS_TELEGRAPH,
	}]

	var phase: float = randf() * TAU
	for arm in range(arms):
		var a: float = phase + TAU * float(arm) / float(arms)
		var dir: Vector2 = Vector2(cos(a), sin(a))
		for i in range(CROSS_PER_ARM):
			out.append({
				"pos": origin + dir * (inner + CROSS_SPACING * float(i)),
				"telegraph": CROSS_TELEGRAPH + float(i) * CROSS_ROLL,
			})
	return out


func _pattern_gate(origin: Vector2) -> Array[Dictionary]:
	# Walls sweeping across the player, each with a doorway. The player is never
	# between walls with nothing to do - every wall has to be answered, and the
	# doorway moves, so answering it means already running when the next lands.
	var heading: float = randf() * TAU
	var sweep: Vector2 = Vector2(cos(heading), sin(heading))
	var across: Vector2 = Vector2(-sweep.y, sweep.x)

	var out: Array[Dictionary] = []
	var centre: float = float(GATE_PILLARS - 1) * 0.5
	var first: float = float(GATE_WALLS - 1) * 0.5

	# Kept off the two ends so a doorway is always something to run THROUGH
	# rather than around, which would make the wall irrelevant.
	var door: int = randi_range(1, GATE_PILLARS - GATE_DOOR_WIDTH - 1)

	for w in range(GATE_WALLS):
		var along: float = (first - float(w)) * GATE_WALL_GAP

		door += randi_range(-GATE_DRIFT_SLOTS, GATE_DRIFT_SLOTS)
		door = clampi(door, 1, GATE_PILLARS - GATE_DOOR_WIDTH - 1)

		for i in range(GATE_PILLARS):
			if i >= door and i < door + GATE_DOOR_WIDTH:
				continue  # the doorway
			out.append({
				"pos": origin + sweep * along + across * ((float(i) - centre) * GATE_PITCH),
				"telegraph": GATE_TELEGRAPH + float(w) * GATE_STEP,
			})

	return out


func _pattern_spiral(origin: Vector2) -> Array[Dictionary]:
	# GROWN FROM THE BOSS, not from the player - the only pattern here that is.
	# Where it is safe therefore depends on where the player is standing relative
	# to the boss, and the answer is to move around with the winding rather than
	# straight away from it.
	var _unused: Vector2 = origin
	var base: float = randf() * TAU
	var out: Array[Dictionary] = []

	for arm in range(SPIRAL_ARMS):
		for i in range(SPIRAL_LENGTH):
			var theta: float = base + TAU * float(arm) / float(SPIRAL_ARMS) \
				+ float(i) * SPIRAL_TWIST
			var radius: float = SPIRAL_START + SPIRAL_GROWTH * float(i)
			out.append({
				"pos": global_position + Vector2(cos(theta), sin(theta)) * radius,
				"telegraph": SPIRAL_TELEGRAPH + float(i) * SPIRAL_ROLL,
				"radius": SPIRAL_SPIKE_RADIUS,
			})

	return out


func _pattern_carpet(origin: Vector2) -> Array[Dictionary]:
	# No shape to read, which is the point - the last phase stops asking a
	# question and just demands movement. Scattered around the player rather
	# than around the boss so it always lands where the fight is.
	#
	# SPACED, NOT PURELY RANDOM, and this is not cosmetic. Uniform random points
	# clump: a straight scatter of ten put two spikes 14px apart, and two
	# overlapping spikes can BOTH hit the player in one cast. Every other pattern
	# here is built so at most one spike can land, which is what keeps a burst a
	# positioning test instead of a damage multiplier - the carpet has to hold
	# the same rule or it quietly becomes the one attack that doubles up.
	#
	# Rejection sampling with a bounded number of attempts: a candidate is kept
	# only if it clears every spike already placed. Ten spikes fit easily in this
	# box, so the cap is a safety net against an unlucky run rather than an
	# expected outcome - and if it ever is hit, the spike is dropped rather than
	# placed badly.
	var out: Array[Dictionary] = []
	var placed: Array[Vector2] = []
	var min_gap: float = CARPET_MIN_GAP * CARPET_MIN_GAP

	for i in range(CARPET_SPIKES):
		for attempt in range(CARPET_PLACE_ATTEMPTS):
			var candidate: Vector2 = origin + Vector2(
				randf_range(-CARPET_WIDTH * 0.5, CARPET_WIDTH * 0.5),
				randf_range(-CARPET_HEIGHT * 0.5, CARPET_HEIGHT * 0.5))

			var clear: bool = true
			for other in placed:
				if candidate.distance_squared_to(other) < min_gap:
					clear = false
					break
			if not clear:
				continue

			placed.append(candidate)
			out.append({
				"pos": candidate,
				"telegraph": CARPET_TELEGRAPH + float(i) * CARPET_ROLL,
			})
			break

	return out


# =============================================================================
# THE SIGNATURE VOLLEY (0.77.0) - what the cast throws now
# =============================================================================

func _cast_signature() -> void:
	# On the cast's discharge frame (cast_frame), at the one the boss is
	# facing - whoever next_target() handed it after its last cast.
	if not is_instance_valid(player):
		return
	var zone: BulletZone = BulletZone.find(self)
	if zone == null:
		# NO ZONE, NO ORBS: a room without one (a test world) still gets an
		# attack - one of this boss's stalagmite shapes, as the cast used to
		# throw - so a boss is never a statue for want of a bullet zone.
		_cast_stalagmites_from_cast()
		return

	var phase: int = _current_phase()
	var kind: StringName = _pick_volley(phase)
	var origin: Vector2 = global_position
	var target: Node2D = player as Node2D
	var shots: Array[Dictionary] = []
	var aimed: Array = [target]
	match kind:
		&"boulder":
			aimed = split_targets(target)
			for body in aimed:
				shots.append(_shot_at(origin, Targets.body_point(body), kind, phase))
			# MORE AT THE ONE IT FACES, thrown where they are running - or,
			# standing, either side of them.
			var spot: Vector2 = Targets.body_point(target)
			var run: Vector2 = _velocity_of(target) * BOULDER_FLIGHT * AIM_LEAD
			var across: Vector2 = (spot - origin).normalized().orthogonal()
			for k in range(1, int(BOULDER_LOBS[phase])):
				var extra: Vector2 = run * float(k) if run.length() > 8.0 \
					else across * BOULDER_SPREAD * (1.0 if k % 2 == 1 else -1.0)
				shots.append(_shot_at(origin, spot + extra, kind, phase))
		&"pincer":
			aimed = split_targets(target)
			for body in aimed:
				shots.append(_shot_at(origin, Targets.body_point(body), kind, phase))
		_:
			shots.append(_shot_at(origin, Targets.body_point(target), kind, phase, randi() % 64))

	for shot in shots:
		fire_volley(zone, origin, float(shot["aim"]), str(shot["v"]), float(shot["r"]))
		# SHARED MONSTERS: every game fires its own copy of each (monstersync's
		# "b"), with its own copy's damage - a leader can aim a volley, never
		# make one hit harder.
		if _net_sync != null and not net_mirror:
			_net_sync.leader_bullets(self, origin, float(shot["aim"]), str(shot["v"]), float(shot["r"]))

	_set_cast_cooldown(_volley_busy(kind, phase) + float(VOLLEY_REST[phase]))

	# AND THE NEXT CAST IS FOR SOMEBODY ELSE, if anybody else is here: the
	# boss turns and walks to them - one it can see, so it never sets off
	# round a wall after someone it has no way to reach.
	for body in aimed:
		_mark_aimed(body)
	var after: Node2D = next_target(target)
	if after != null and after != target and _has_line_of_sight(Targets.body_point(after)):
		player = after
		_release_slot()

	if debug_patterns:
		print("[BOSS] phase %d  VOLLEY %s x%d  hp %d/%d" % [phase + 1, kind, shots.size(), hp, max_hp])


func _shot_at(origin: Vector2, at: Vector2, kind: StringName, phase: int, extra: int = 0) -> Dictionary:
	var name_sent: String = "%s%d" % [kind, phase]
	if extra != 0:
		name_sent += ":%d" % extra
	return {"aim": (at - origin).angle(), "r": origin.distance_to(at), "v": name_sent}


func _volley_busy(kind: StringName, phase: int) -> float:
	"""How long `kind` holds the cast in `phase`: the ones that come in beats
	for as long as their beats last and a little, the rest VOLLEY_BUSY."""
	match kind:
		&"prism":
			return float(PRISM_BURSTS[phase]) * PRISM_GAP + 0.3
		&"gale":
			return float(GALE_FANS[phase]) * GALE_GAP + 0.5
		&"tide":
			return float(TIDE_WAVES[phase]) * TIDE_GAP + 0.6
	return float(VOLLEY_BUSY.get(kind, 1.0))


func _pick_volley(phase: int) -> StringName:
	var lists: Array = kit()["volleys"]
	var pool: Array = lists[clampi(phase, 0, lists.size() - 1)]
	var choice: StringName = pool[randi() % pool.size()]
	var guard: int = 0
	while choice == _last_volley and pool.size() > 1 and guard < 32:
		choice = pool[randi() % pool.size()]
		guard += 1
	_last_volley = choice
	return choice


func _set_cast_cooldown(seconds: float) -> void:
	# RESTARTED FROM THE DISCHARGE, the same as _apply_pattern_cooldown(): the
	# attack timer has been running since _trigger_attack(), measured from the
	# wrong moment.
	if not has_node("attacktimer"):
		return
	var timer: Timer = $attacktimer
	timer.stop()
	timer.wait_time = maxf(0.2, seconds * _pace())
	timer.start()


func _cast_stalagmites_from_cast() -> void:
	var container: Node = get_tree().get_first_node_in_group("groundeffects")
	if container == null:
		container = get_tree().current_scene
	if container == null or eruption_scene == null:
		return
	var pool: Array[StringName] = stalagmite_pool(_current_phase())
	var choice: StringName = pool[randi() % pool.size()]
	var pattern: Array[Dictionary] = _lead_pattern(_pattern_by_name(choice, _aim_point()), choice)
	_apply_pattern_cooldown(pattern)
	var scene: PackedScene = eruption_scene if choice in PILLAR_SHAPES else gate_scene
	for spike in pattern:
		_spawn_one_eruption(container, clamp_to_navigation(spike["pos"]), float(spike["telegraph"]),
			float(spike.get("radius", PILLAR_RADIUS)), scene)


func fire_volley(zone: BulletZone, origin: Vector2, aim: float, volley: String = "",
		reach: float = 0.0) -> void:
	"""One of this boss's volleys into `zone`: `volley` is its name and the
	phase it was cast in ("tide2"), and for some a number after a colon
	("tide2:17", where the tide's gap starts). `reach` is how far off the
	player stood. This boss's own damage and element - the contract is in
	BulletZone's header - and a name that is not one of VOLLEYS fires nothing.
	Every game runs this for every volley: the leader as it casts, the others
	from its "b" (monstersync.gd)."""
	if zone == null:
		return
	var parts: PackedStringArray = volley.split(":")
	var head: String = parts[0]
	if head.length() < 2 or not head.right(1).is_valid_int():
		return
	var kind: StringName = StringName(head.left(head.length() - 1))
	if not VOLLEYS.has(kind):
		return
	var phase: int = clampi(int(head.right(1)), 0, 2)
	# WHAT HIT ME (0.85.0): every orb of it is this boss's `kind`.
	HitSource.stamp_for(self, String(kind))
	var extra: int = absi(int(parts[1])) if parts.size() > 1 and parts[1].is_valid_int() else 0
	var element: int = current_element()
	var orb: int = BulletZone.share_of(spike_damage(), ORB_SHARE)
	match kind:
		&"prism":
			var spokes: int = int(PRISM_SPOKES[phase])
			var turn: float = PRISM_TURN * (1.0 if extra % 2 == 0 else -1.0)
			for b in int(PRISM_BURSTS[phase]):
				_on_beat(PRISM_GAP * b, zone.fire_ring.bind(origin, aim + turn * b, spokes,
					PRISM_SPEED, orb, element))
		&"gale":
			var swing: float = 1.0 if extra % 2 == 0 else -1.0
			var fans: int = int(GALE_FANS[phase])
			for f in fans:
				_on_beat(GALE_GAP * f, zone.fire_fan.bind(origin,
					aim + (float(f) - float(fans - 1) * 0.5) * GALE_SWEEP * swing,
					int(GALE_ORBS[phase]), GALE_SPREAD, GALE_SPEED, orb, element))
		&"vortex":
			_pull_my_player(origin)
			for r in VORTEX_RINGS:
				var door: int = (extra + r * 9) % (VORTEX_ORBS - VORTEX_DOOR)
				_on_beat(VORTEX_GAP * r, zone.fire_ring.bind(origin, aim, VORTEX_ORBS, VORTEX_SPEED,
					orb, element, true, 0.0, 0.0, door, VORTEX_DOOR))
		&"tide":
			# The first door within TIDE_DOOR_NEAR orbs of the one aimed at you,
			# so it is always a few steps away; then it walks.
			var width: int = int(TIDE_DOOR[phase])
			var middle: int = (TIDE_ORBS - width) >> 1
			var first: int = middle - TIDE_DOOR_NEAR + (extra % (TIDE_DOOR_NEAR * 2 + 1))
			var step: int = TIDE_DOOR_STEP if ((extra >> 4) & 1) == 0 else -TIDE_DOOR_STEP
			for w in int(TIDE_WAVES[phase]):
				var door_at: int = clampi(first + step * w, 1, TIDE_ORBS - 1 - width)
				_on_beat(TIDE_GAP * w, zone.fire_fan.bind(origin, aim, TIDE_ORBS, TIDE_SPREAD,
					TIDE_SPEED, orb, element, true, 0.0, door_at, width))
		&"frost":
			var stop: float = clampf(reach, FROST_NEAREST, FROST_FURTHEST)
			var shards: int = int(FROST_SHARDS[phase])
			zone.fire_fan(origin, aim, shards, FROST_SPREAD, FROST_SPEED, orb, element, true, stop)
			if phase >= 1:
				_on_beat(FROST_SECOND_AFTER, zone.fire_fan.bind(origin, aim, maxi(shards - 2, 3),
					FROST_SPREAD, FROST_SPEED, orb, element, true,
					maxf(FROST_NEAREST * 0.75, stop - FROST_SECOND_IN)))
			# AND PHASE THREE ONE FURTHER OUT: stepping straight back is no
			# longer enough - between the arcs, or round their ends.
			if phase >= 2:
				_on_beat(FROST_SECOND_AFTER * 2.0, zone.fire_fan.bind(origin, aim, shards,
					FROST_SPREAD * 0.8, FROST_SPEED, orb, element, true,
					minf(FROST_FURTHEST + FROST_SECOND_IN, stop + FROST_SECOND_IN)))
		&"boulder":
			var landing: float = clampf(reach, 0.0, BOULDER_REACH_MAX)
			zone.fire_mortar(origin, aim, landing, BOULDER_FLIGHT, _lob_art(), spike_damage(),
				int(BOULDER_ROCKS[phase]), BOULDER_ROCK_SPEED, BOULDER_CRATER, orb, element,
				Puddles.scene_for(element))
		&"pincer":
			var arms: Array[float] = []
			arms.assign(PINCER_ARMS[phase])
			var shut_at: float = maxf(reach, PINCER_REACH_MIN)
			zone.fire_pincer(origin, aim, shut_at, arms, PINCER_SPEED, orb, element)
			_on_beat(BulletZone.pincer_time(shut_at, arms, PINCER_SPEED),
				_burn_floor.bind(origin + Vector2.from_angle(aim) * shut_at, element))
			# PHASE THREE SHUTS TWICE: the same spot again PINCER_AGAIN later,
			# with the arms between the first's, for whoever stepped back in.
			if phase >= 2:
				var between: Array[float] = []
				for t in arms:
					between.append(t * 0.8)
				_on_beat(PINCER_AGAIN, zone.fire_pincer.bind(origin, aim, shut_at, between,
					PINCER_SPEED, orb, element))


func _on_beat(seconds: float, shot: Callable) -> void:
	"""Fires `shot` `seconds` from now, unless the boss has died meanwhile.
	On a tween of the boss's own, so a boss that is freed takes its volley
	with it (a timer of the tree's would fire into a scene that has gone).
	With the stamp it has now (WHAT HIT ME, hitsource.gd)."""
	shot = HitSource.later(shot)
	if seconds <= 0.0:
		_fire_if_fighting(shot)
		return
	if not is_inside_tree():
		return
	var tween: Tween = create_tween()
	tween.tween_interval(seconds)
	tween.tween_callback(_fire_if_fighting.bind(shot))


func _fire_if_fighting(shot: Callable) -> void:
	if _dying or _death_resolved:
		return
	var zone: Object = shot.get_object()
	if zone != null and not is_instance_valid(zone):
		return
	shot.call()


func _pull_my_player(origin: Vector2) -> void:
	# THIS GAME'S OWN PLAYER, on every game: each one runs this volley, so
	# each pulls the one player it moves.
	var me: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	if me == null or Targets.body_point(me).distance_to(origin) > VORTEX_REACH:
		return
	var fx: Node = StatusEffects.of(me)
	if fx != null and fx.has_method(&"pull"):
		fx.call(&"pull", origin, VORTEX_SECONDS, VORTEX_PULL)


func _burn_floor(at: Vector2, element: int) -> void:
	# Where a pincer shuts, the floor carries the element on: fire burns,
	# dark withers - the boss's own puddle, carrying its effect.
	var container: Node = get_tree().get_first_node_in_group("groundeffects")
	if container == null:
		container = get_tree().current_scene
	if container == null:
		return
	var pool: Node = Puddles.scene_for(element).instantiate()
	if "element" in pool:
		pool.set("element", element)
	HitSource.tag(pool, self, "burn")
	var effect: StringName = StatusEffects.for_element(element)
	if "status" in pool and StatusEffects.GROUND.has(effect):
		pool.set("status", effect)
	pool.set("spawn_at", clamp_to_navigation(at))
	container.add_child.call_deferred(pool)


func _lob_art() -> Node2D:
	"""The boss's own stalagmite, for a boulder to carry: the risen frame of
	its element's pillar, taken off the scene with its colouring and the rest
	thrown away - the owner's art, not new art (bulletlob.gd)."""
	var pillar: Node = Projectiles.variant_of(eruption_scene, current_element()).instantiate()
	var art: AnimatedSprite2D = pillar.get_node_or_null(^"animatedsprite2d") as AnimatedSprite2D
	if art != null:
		art.owner = null
		pillar.remove_child(art)
		art.stop()
		if art.sprite_frames != null and art.sprite_frames.has_animation(&"projectile"):
			art.animation = &"projectile"
			art.frame = mini(1, art.sprite_frames.get_frame_count(&"projectile") - 1)
		art.scale = Vector2.ONE * 0.6
	pillar.free()
	return art


# =============================================================================
# WHO IS ATTACKED (0.77.0) - see THE KITS, NOBODY IS LOCKED ON
# =============================================================================

func kit() -> Dictionary:
	"""This boss's kit: its element's, or the Crowned's for an element with
	none of its own."""
	return KITS.get(current_element(), KITS[Element.Type.DARK])


func stalagmite_pool(phase: int) -> Array[StringName]:
	"""The shapes this boss may raise in `phase`: its first two, then all
	three from phase two."""
	var shapes: Array = kit()["shapes"]
	var pool: Array[StringName] = []
	for k in mini(shapes.size(), 2 if phase <= 0 else 3):
		pool.append(shapes[k])
	return pool


# =============================================================================
# BOSSES THAT SCALE (0.80.0) - see the top
# =============================================================================

# What its health is times, now: 1.0 until a fight raises it.
var health_scale: float = 1.0
# Its health before a fight raised it, kept whole so a second raise and the
# way back down are worked from it, not from a rounded raise.
var _unscaled_max: int = 0
var _scale_timer: Timer = null


static func scale_for(element: int, levels: Array) -> float:
	"""How many times its catalogue health a boss of this element has for
	fighters of these levels (the highest PARTY_MOST counted)."""
	var base: float = float(HEALTH_BASE.get(element, 1.0))
	if levels.is_empty():
		return base
	var counted: Array = levels.duplicate()
	counted.sort()
	counted.reverse()
	counted = counted.slice(0, PARTY_MOST)
	var top: float = float(BAND_TOP.get(element, BAND_TOP[Element.Type.DARK]))
	var total: float = 0.0
	for level in counted:
		total += minf(LEVEL_MOST, 1.0 + LEVEL_SHARE * maxf(0.0, float(level) - top))
	return base * (total / float(counted.size())) * (1.0 + PARTY_SHARE * float(counted.size() - 1))


func fighter_levels() -> Array:
	"""The level of everybody in this fight (fight_targets())."""
	var levels: Array = []
	for body in fight_targets():
		var level: Variant = body.get("level")
		levels.append(maxi(1, int(level)) if level != null else 1)
	return levels


func raise_for_scale() -> void:
	"""(The game running it.) Its health for who is fighting it now: raised,
	never lowered, the damage already done kept."""
	if net_mirror or _dying or _death_resolved or hp <= 0:
		return
	var want: float = scale_for(current_element(), fighter_levels())
	if want <= health_scale + 0.001:
		return
	if health_scale <= 1.001:
		_unscaled_max = max_hp
	var new_max: int = maxi(max_hp, roundi(float(_unscaled_max) * want))
	hp += new_max - max_hp
	max_hp = new_max
	health_scale = want
	_refresh_health_display()
	_tell_scale()


func unscale() -> void:
	"""(The game running it.) Home, out of the fight and at full health:
	itself again, for whoever comes next."""
	if net_mirror or health_scale <= 1.001 or engaged or is_returning_home or _dying or _death_resolved \
			or hp < max_hp:
		return
	max_hp = _unscaled_max if _unscaled_max > 0 else maxi(1, roundi(float(max_hp) / health_scale))
	hp = max_hp
	health_scale = 1.0
	_refresh_health_display()
	_tell_scale()


func net_rescale(new_max: int, new_hp: int) -> void:
	"""(Mirror.) The game running this boss changed its health for who is
	fighting it ("mh")."""
	if new_max <= 0:
		return
	note_told_max(new_max)
	max_hp = new_max
	hp = clampi(new_hp, 0, max_hp)
	_refresh_health_display()


func note_told_max(new_max: int) -> void:
	"""(Mirror, before its maximum becomes `new_max`.) Keep how many times
	its own health the game running it has raised it, so that if this game
	takes the fight over - its leader fell or left - it starts from the
	scale the fight already has. A mirror kept 1.0, so its first
	raise_for_scale() after taking over took the RAISED maximum for the
	unraised one, raised it again and added the difference to its health:
	the owner's friend died beside him and the boss was all but full again
	(0.96.1)."""
	if new_max <= 0 or new_max == max_hp:
		return
	if _unscaled_max <= 0:
		_unscaled_max = max_hp
	health_scale = maxf(1.0, float(new_max) / float(_unscaled_max))


func _tell_scale() -> void:
	if _net_sync != null and not net_mirror:
		_net_sync.leader_event(self, {"k": "mh", "mh": max_hp, "hp": hp})


func _on_scale_tick() -> void:
	if in_fight():
		raise_for_scale()
	else:
		unscale()


func in_fight() -> bool:
	"""True while this boss is loose and after somebody: not caged, dying,
	dead or walking home, and its target inside the leash."""
	if gated or _dying or _death_resolved or is_returning_home or not engaged:
		return false
	if not is_instance_valid(player):
		return false
	return global_position.distance_to(player.global_position) <= leash_range


func fight_targets() -> Array:
	"""Everybody in this fight: everyone a monster may chase (Targets.all)
	within the leash of where the boss stands, and not dying."""
	var found: Array = []
	for body in Targets.all(get_tree()):
		if not (body is Node2D) or not is_instance_valid(body):
			continue
		var dying: Variant = body.get("is_dying")
		if dying is bool and dying:
			continue
		if global_position.distance_to((body as Node2D).global_position) <= leash_range:
			found.append(body)
	return found


func next_target(exclude: Node = null) -> Node2D:
	"""Whoever in the fight has gone longest without being attacked; never
	`exclude` (the one just attacked) while there is anyone else. Ties go to
	the nearer. Null when nobody is in the fight."""
	var bodies: Array = fight_targets()
	if bodies.is_empty():
		return null
	if bodies.size() == 1:
		return bodies[0]
	var best: Node2D = null
	var best_at: int = 0
	var best_d: float = INF
	for body in bodies:
		if body == exclude:
			continue
		var at: int = int(_last_aimed.get(body.get_instance_id(), -1))
		var d: float = global_position.distance_squared_to((body as Node2D).global_position)
		if best == null or at < best_at or (at == best_at and d < best_d):
			best = body
			best_at = at
			best_d = d
	return best


func split_targets(first: Node2D) -> Array:
	"""Who a split volley goes at: `first`, then the others in the fight in the
	order next_target() would take them, SPLIT_MAX at most."""
	var out: Array = [first]
	var others: Array = fight_targets()
	others.erase(first)
	others.sort_custom(func(a: Node, b: Node) -> bool:
		return int(_last_aimed.get(a.get_instance_id(), -1)) < int(_last_aimed.get(b.get_instance_id(), -1)))
	for body in others:
		if out.size() >= SPLIT_MAX:
			break
		out.append(body)
	return out


func _mark_aimed(body: Node) -> void:
	if is_instance_valid(body):
		_last_aimed[body.get_instance_id()] = Time.get_ticks_msec()


func _pace() -> float:
	"""How much slower this boss's clocks run for the partners loose beside
	it: 1 alone, WAVE_PACE more for each other boss in a fight."""
	var others: int = 0
	for boss in get_tree().get_nodes_in_group(BOSS_GROUP):
		if boss == self or not is_instance_valid(boss) or not boss.has_method(&"in_fight"):
			continue
		if bool(boss.call(&"in_fight")):
			others += 1
	return 1.0 + WAVE_PACE * float(others)


func _apply_pattern_cooldown(pattern: Array[Dictionary]) -> void:
	if pattern.is_empty() or not has_node("attacktimer"):
		return

	var last: float = 0.0
	for spike in pattern:
		last = maxf(last, float(spike["telegraph"]))

	# RESTARTED FROM NOW, not adjusted. The timer has been running since
	# _trigger_attack() and is part-way through a cooldown measured from the
	# wrong moment - the cast started, but the pattern only exists now. Measuring
	# from the spikes appearing is what makes the number mean "wait for this
	# attack to finish".
	var timer: Timer = $attacktimer
	timer.stop()
	timer.wait_time = last + _spike_lifetime + PATTERN_BREATHER
	timer.start()


func _spawn_one_eruption(container: Node, pos: Vector2, telegraph: float,
		spike_radius: float, scene: PackedScene, puddle_seed: int = 0) -> void:
	# THE SCENE IS THE TRACK. Pillars and spikes are two separate attacks
	# running at once, and which art a hazard wears is how the player tells
	# which attack it belongs to - so it is decided by the CALLER, per cast,
	# never per pillar. Mixing the two inside one pattern is what made a "gate"
	# pillar indistinguishable from a spike-track attack.
	if scene == null:
		return

	# THE ELEMENT PICKS THE VARIANT, and it happens HERE because this is the one
	# function both tracks pass through — the pillar cast and the gate spike each
	# hand their own scene in, and each gets its own six.
	#
	# variant_of() is keyed on the base scene, which is what makes this safe to
	# put in front of a parameter: eruption_scene and gate_scene are @export, so
	# a scene pointed somewhere custom is not in the table and comes straight
	# back out. The line below cannot silently replace a designer's choice.
	var eruption: Node2D = Projectiles.variant_of(scene, current_element()).instantiate()
	HitSource.tag(eruption, self, "spike")

	# CONFIGURED BEFORE IT ENTERS THE TREE. add_child() is what runs _ready(),
	# and bossprojectile._ready() applies its element profile there — scaling
	# the telegraph, the size and the damage this function sets. Set them after
	# add_child and the profile multiplies values that do not exist yet, so
	# every spike comes out at the scene defaults. poisonslime._spawn_slime()
	# carries the same note for is_small, and for exactly the same reason.
	eruption.damage = spike_damage()

	# GUARDED, AND THE GUARD IS NOT DEFENSIVE PROGRAMMING - it is load-bearing.
	#
	# Both eruption scenes this boss spawns, bossprojectile.tscn and
	# secondbossprojectile.tscn, run bossprojectile.gd, and that script has no
	# leaves_puddle. Only poisonprojectile.gd does. So this line raised
	#
	#   Invalid assignment of property or key 'leaves_puddle' with value of
	#   type 'bool' on a base object of type 'Area2D (bossprojectile.gd)'
	#
	# on EVERY pillar of EVERY cast - and GDScript aborts the function on an
	# invalid assignment, so the three statements below this one never ran. That
	# is the real damage: no spike was ever scaled to its pattern's radius, no
	# spike ever got its own telegraph (they all sat at bossprojectile.gd's
	# default 0.9), and none of them reset interpolation, so every one slid in
	# from the top-left of the map on its first frame. The staggered patterns -
	# lance, cross, carpet - have never rolled outward.
	#
	# THE GUARD STAYS even though bossprojectile.gd now has these properties.
	# This function takes the scene from its CALLER, and eruption_scene and
	# gate_scene are both @export - point either at something else and an
	# unguarded assignment is the same crash again.
	#
	# THE ROLL MOVED INTO THE PROJECTILE. This used to be randf() < PUDDLE_CHANCE
	# here, handing down a bool — and a bool cannot carry "fire leaves acid 30%
	# more often than earth does". Passing the chance instead lets each element
	# scale it. The constant still lives here, with the arithmetic that chose it.
	if "leaves_puddle" in eruption:
		eruption.leaves_puddle = true
	if "puddle_chance" in eruption:
		eruption.puddle_chance = PUDDLE_CHANCE

	# THE CASTER'S ELEMENT, so a fire boss throws fire spikes and leaves fire
	# behind. Eruptions are added to the container directly rather than through
	# BaseEnemy.spawn_projectile_node(), which is where every other enemy's shot
	# gets stamped — so without this line every spike from every one of the six
	# elemental bosses was element NONE, and so was its acid.
	if "element" in eruption:
		eruption.element = current_element()

	# AND WHAT THE ELEMENT DOES (0.77.0): an ice boss's stalagmite chills, an
	# earth boss's roots (statuseffects.gd). From the element here, on every
	# game that draws the spike, so each copy carries the same effect.
	if "status" in eruption:
		eruption.status = StatusEffects.for_element(current_element())

	# THE PUDDLE IS ROLLED FROM A SEED, so every game drawing this spike leaves
	# the same acid in the same places (shared monsters). The seed is drawn
	# here, from the global RNG, so a lone player's odds are what they were.
	if puddle_seed == 0:
		puddle_seed = (randi() | 1)
	if "puddle_seed" in eruption:
		eruption.puddle_seed = puddle_seed

	# SCALED, NOT RESIZED. The pillar's hitbox, its sprite and the warning ring
	# it draws are all authored at SPIKE_BASE_RADIUS, so scaling the node moves
	# all three together and they cannot drift apart.
	#
	# Setting the CollisionShape2D's radius directly would have been the obvious
	# way and it is a trap: sub-resources are SHARED between instances of a
	# scene unless explicitly made local, so resizing one pillar would silently
	# resize every other pillar on screen.
	if not is_equal_approx(spike_radius, SPIKE_BASE_RADIUS):
		var s: float = spike_radius / SPIKE_BASE_RADIUS
		eruption.scale = Vector2(s, s)

	# PER-SPIKE, NOT PER-CAST. The ring and the cage give every spike the same
	# telegraph so the pattern fills and erupts as one readable event; the lance,
	# cross and carpet stagger theirs slightly so the attack rolls outward. Each
	# ring draws its own countdown, so six different clocks are still six things
	# the player can read at a glance rather than six things to remember.
	eruption.telegraph_seconds = telegraph

	# NOW it enters the tree, which runs _ready() and applies the element
	# profile on top of everything set above.
	container.add_child(eruption)
	eruption.global_position = pos

	# AFTER the position is set. Physics interpolation blends from the node's
	# previous transform, and a freshly added node's previous transform is
	# wherever the scene was authored — (0, 0). Without this the spike visibly
	# slides in from the top-left corner of the map on its first frame. See
	# BaseEnemy.spawn_projectile_node() for the full explanation.
	eruption.reset_physics_interpolation()

	# SHARED MONSTERS: the same spike, in the same place, on every screen. The
	# BASE scene goes, not the variant: the copy runs this same function on
	# its mirror of this boss, which picks the variant from the same element.
	if _net_sync != null and not net_mirror:
		_net_sync.leader_event(self, {"k": "e", "s": scene.resource_path,
			"x": snappedf(pos.x, 0.1), "y": snappedf(pos.y, 0.1),
			"t": snappedf(telegraph, 0.001), "r": snappedf(spike_radius, 0.01), "sd": puddle_seed})


# =============================================================================
# SUBCLASS OVERRIDES
# =============================================================================

# A BOSS HOLDS ITS GROUND against a meteor's vortex (meteor.gd, THE PULL): its
# rings, spikes and swings are placed from where it stands, and a boss a mage
# could drag about would turn its fight into something nobody designed.
func can_be_pulled() -> bool:
	return false


func get_move_speed() -> float:
	# STILL SLOWER THAN THE PLAYER (90), and that ceiling is the real rule: a
	# boss that can outrun you turns the telegraph into decoration, because you
	# cannot dodge a ring if the thing placing it is already on top of you again.
	#
	# But 45 was half your speed, which made it a turret - it never closed, so
	# its melee never came up and you could read every cast from a safe distance
	# and stroll out. 70 keeps the ceiling intact while making distance
	# something you have to spend effort holding.
	return 70.0


func fire_projectile() -> void:
	# BaseEnemy's hook for enemies that shoot on a timer. This boss spawns from
	# frame_changed instead, so the hook stays empty on purpose — same as
	# BushMage. Left here rather than deleted so the next person looking for
	# "where does the boss attack" finds this note instead of concluding the
	# hook was forgotten.
	pass
