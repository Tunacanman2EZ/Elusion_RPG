# healerrun.gd - THE HEALER'S RUN (0.98.0): a shooter like the old Nintendo
# space games, with the healer as the ship. Step 1 of the commit folder's
# HEALER_RUN_PLAN.txt.
#
# The owner, 31 Oct: "healer is constantly walking forward in a loop basically
# add some upgrades drop some enemies and healer trys to avoid running into
# enemies but can also kill them i was thinking power up like those old space
# games", "the character is only walking forward because the scene is moving
# enemies are coming down randomly generated like a dungeon player has free
# movement but scene keeps progressing", "players goal is to kill everything as
# quick as possible", "first power up 2 bullets then 4 then 6 the 8", and "make
# the path wider".
#
# ITS OWN WORLD. The run lives in a SubViewport with a world of its own
# (healerrunscreen.gd), 640 x 360 drawn at whole multiples - so nothing here
# touches the area the player stands in, its physics, its monsters or the
# server. Nothing is reported: the monsters are pictures of the game's own
# monsters moved by this script, not monsters (no BaseEnemy, no kill reports).
# Step 3 of the plan pays gold at the end, through the server.
#
# THE SCENE MOVES, NOT HER. Everything that fights is in screen space, centred
# on this node's origin: the healer, her shots, the monsters, their bullets
# (the shared BulletField). Only `terrain` scrolls - down, at scroll_speed() -
# and it is laid ahead as it comes (_lay_terrain()): the underground floor, the
# crypt's side walls, and every SECTION_LENGTH a section drawn at random - a
# hall, a row of pillars with gaps, a colonnade, a crossing with one way
# through - "like a dungeon". What scrolls off the bottom is freed.
#
# THE RUN: TIERS tiers of WAVES_PER_TIER waves, each tier one of the lands (a
# random order, so no two runs are alike) and ending with that land's boss;
# after the third, the goal marker (0.100.0 - it was five stretches of five and
# one boss). A wave comes when the last is dead - or when its
# time is up, on top of what is left: killing fast makes the run fast.
#
# HER SHOTS: unlimited, always firing (SHOT_GAP); a power-up takes her from 1
# to 2, 4, 6, then 8 (SHOT_STEPS, shot_offsets()). Lives: LIVES_START, a
# potion one more (to LIVES_MOST); one hit is one life, then BLINK_SECONDS
# untouchable, one shot step lost and the screen's bullets cleared.
#
# IT GETS HARDER WITH HER (the old games' hidden rank): rank() is the run's
# heat (two a tier, one more half way through it) plus her shot step, less one for every life lost, held to 0..RANK_MOST. Rank
# makes the monsters tougher (foe_health()), their bullets faster
# (bullet_speed()), their shots more often (fire_gap()), the waves bigger
# (group_extra()) and quicker to come (wave_time()), and the scroll a little
# faster (scroll_speed()).
#
# TUNED AFTER THE FIRST PLAY (0.98.1). The owner: "phase 1 is good need more
# power ups more enemies maybe a fire from behind the ground needs to move
# faster as time progresses just a little at a time", and "when the mini game
# starts we want the healer to be standing on a platform not walking in from
# the black".
# - She starts STANDING on a landing: the floor laid under the whole screen,
#   the crypt's wall behind her and a candelabra either side
#   (_lay_landing()); the path moves only once the run starts.
# - The ground speeds up a little all the time (SCROLL_PER_SECOND), not in
#   steps at each stretch.
# - More power-ups (KINDS' odds, POWER_PITY) and, at eight shots, a
#   power-up is OVERCHARGE: twice the rate of fire for OVERCHARGE_SECONDS.
# - More monsters: bigger waves, and from the second stretch a second, smaller
#   wave of another kind alongside (BOTH_CHANCE).
# - THE FIRE BEHIND HER: from FIRE_AFTER seconds a wall of fire rises from the
#   bottom of the screen, FIRE_RISE px a second, to FIRE_MOST - stand in it
#   and it costs a life. Drawn as a glow and embers (BulletField orbs), no
#   new art.
#
# GOLD, A LASER, A METEOR AND MORE FORMATIONS (0.99.0). The owner: "the
# enemies on the left and right do not sway far enough into the map", "gold
# should be rewarded on the screen then moved to char when hitting leave",
# "we also need more enemy formations", "we can loot a meteor for a special
# weapon for the bosses", "just press space to fire meteor will auto lock",
# "when hitting overcharge nothing happens after lets add a laser".
# - Arcs swing deep into the path (ARC_IN, ARC_TURN): about 180 px in.
# - New formations: a snake weaving down, a pincer from both top corners, a
#   ring turning as it comes, and a wall of slimes with gaps.
# - Gold counts on screen (gold_now()), from the table the server hands the
#   game at Go (`pays`; DEFAULT_PAYS until then): each wave passed, the boss,
#   the goal. The server pays it at Leave (healerrunscreen.gd).
# - At eight shots a power-up is a LASER (LASER_SECONDS): a beam straight up
#   from her, through everything in it. It replaces 0.98.1's overcharge, which
#   nobody could see.
# - A METEOR drops now and then from a mage or a sniper, and one falls ahead
#   of her at the gate; Space calls it down on the boss - or, before the
#   gate, the toughest monster standing (fire_meteor()). Up to METEORS_MOST.
#
# THE LASER GROWS (0.99.0). The owner: "now we need to add layers to the
# lasers add some color more upgrades should make you stronger". Every
# power-up past eight shots is a laser level, to LASER_LEVELS (5), kept for the
# run: each adds a layer of colour (LASER_COLOURS - green, teal, blue, violet,
# gold), more width and damage (laser_half(), laser_dps()), longer time
# (laser_seconds()), and from level 3 a pair of side beams, from level 5 two.
# A hit takes a laser level before a shot step. The rank counts the levels too,
# so the stronger she is, the harder it gets.
#
# BULLETS OVER THE LASER, AND A RED HEART TO THE BEST ONE (0.99.0). The owner:
# "we need to make sure bullets are a layer to the lasers also we can add some
# red in the middle of the best laser". The laser is drawn at BEAM_Z, under her
# shots (SHOTS_Z) and the monsters' bullets (BULLETS_Z) - a bullet in the beam
# is still seen, and dodged - and her shots keep firing beside it, starting
# past its outer edge so the two never overlap (laser_edge(): "bullets need to
# be an addition to laser the do not overlap"). At the top level
# (LASER_LEVELS) its middle is red (LASER_HEART).
#
# MORE OF THEM, AND A FINISH THAT FIGHTS BACK (0.99.0). The owner: "we need
# more enemies finishing should be pretty challenging".
# - Every wave grows by a monster or so a stretch (crowd()), on top of the
#   rank; a second, half-size wave comes alongside more often (BOTH_CHANCE,
#   BOTH_PER_STRETCH), and from stretch 4 sometimes a third (THIRD_CHANCE);
#   waves come sooner (wave_time()).
# - The boss is a wall now: KINDS' 2400 health before rank - built for a
#   full laser, shots and meteors. Every BOSS_ADDS_SECONDS it calls a half-size
#   wave to its side, and under ENRAGE_AT of its health it is enraged: its
#   casts come faster and closer together (ENRAGE_PACE), its rings thicker.
#
# THE LASER BALANCED, AND DROPS CAUGHT FROM ANY SIDE (0.99.2). The owner: "we
# need to balance out the lasers now also noticed when moving backwerds could
# not pick up the drop".
# - The laser: LASER_DPS 24 rising 40% a level (it was 34 rising 50%: a
#   level-5 laser and its side beams did about 300 a second - the boss's 2400
#   melted), side beams a third of it (SIDE_BEAM_SHARE), and LASER_SECONDS 5
#   plus a second a level. Still the strongest thing she has; no longer all
#   of it.
# - Drops: a drop is picked up within PICKUP_REACH of her middle, and one
#   within MAGNET_REACH is drawn to her (MAGNET_SPEED) - from behind as well
#   as ahead. Going back for one that had fallen past meant reaching for it
#   at the bottom of the screen, where she cannot go and the fire is.
#
# THREE TIERS, A BOSS FOR EACH LAND, AND HITS YOU CAN FEEL (0.100.0). The
# owner: "lets progress tiers after round 8 to the next difficulty diff boss
# and effects when hit", choosing a boss every 8 waves.
# - TIERS of WAVES_PER_TIER: every eighth wave ends with its land's boss
#   (BOSS_HEALTH by tier, before rank). Beaten, it bursts with every monster on
#   screen, drops a power-up and a potion, and the next tier starts in the next
#   land, hotter: heat() is two a tier, and it feeds the rank, the crowd, the
#   second and third waves and the bosses' rings. After the third, the goal.
# - Gold by tier (the server's healer_tier_pays(), DEFAULT_PAYS until Go
#   answers): 10, 25, 100 a wave, the bosses 120, 300, 1500, the goal 2000 -
#   up to 5000 a run, 700 of it by the second boss (the owner: "up to 5000
#   gold for passing phase 2").
# - THE FIRE CLIMBS HIGHER, AND POWER PUSHES IT BACK (the owner: "the fire at
#   the bottom gets a bit taller and upgrades push it back down"): it rises
#   FIRE_RISE a second, FIRE_RISE_PER_TIER more each tier, to FIRE_MOST (it
#   was 64), and every power-up - a shot step or a laser level - pushes it
#   down FIRE_PUSH, eased over a moment (_fire_push).
# - EACH LAND'S BOSS FIGHTS ITS OWN WAY: every other cast is its land's own
#   (SIGNATURES, _signature()), said in the banner -
#   fire: Fire rain, fireballs from above and embers that lie burning;
#   ice: Frost volley, fans of freezing shots - one FREEZES her
#     (FREEZE_SECONDS: no moving, no shooting, tinted ice) instead of taking a
#     life, then FROST_PROOF to break free;
#   wind: Gale, a gust shoving her sideways (GUST_PUSH) under crosswinds;
#   water: Tide, rows of weaving drops, a way through each;
#   earth: Rockfall, rocks marked on the floor where she stands, landing in
#     rings of shards with a shake;
#   light: Pillars of light, columns marked then burning down the path;
#   dark: Dark coils, orbs curling in from both sides.
#   The marks, the pillars and the wind are drawn by Hazards; the boss's first
#   (BOSS_ADDS_SECONDS + ADDS_PER_TIER) calls its waves less often.
# - Hits felt (code-drawn, as the meteor's burst): every kill bursts in its
#   land's colour (Burst), a boss struck sparks and the screen shakes a little
#   (BOSS_SHAKE), harder for a meteor, a rock, a hit on her (HURT_SHAKE) and a
#   boss down; a power-up, potion or meteor rings out from her and she shines.
#   The shake moves this node about where it was put (_home), so nothing the
#   run measures moves with it.
# - GOD MODE, the owner's (0.100.0): "i need a godmode switch that only i can
#   see on the screen for this mini game so i can test". With `god` on (the
#   screen's switch sets it) hurt() takes nothing - no life, no shot step, no
#   laser level - from a bullet, a monster, a pillar, a rock, the fire or the
#   scroll; the fire and the scroll still push her clear. A freezing shot
#   still freezes: that is a thing to test, not a hit. `god_used` remembers it
#   was on at any moment of the run, and such a run pays nothing.
#
# No class_name: preloaded by healerrunscreen.gd and the suite.
extends Node2D

signal finished(won: bool)

enum State { READY, RUNNING, BOSS, GOAL, WON, LOST }

const VIEW := Vector2(640.0, 360.0)
const HALF := Vector2(320.0, 180.0)
# THE PATH: 480 of the view's 640 (the owner: "make the path wider"); the dark
# either side holds the screen's words.
const PATH_HALF := 240.0
const WALL_PIECE := "res://scene/crypt/wallsidetall.tscn"
const WALL_STEP := 58.0
const TILE := 16
const FLOOR_SET := "res://scene/world/underground.tres"
const SECTION_LENGTH := 300.0
# The first stretch of path is bare: it starts easy.
const CLEAR_START := 700.0

const TIERS := 3
const WAVES_PER_TIER := 8
# The run's heat: this much a tier, and one more half way through one.
const HEAT_PER_TIER := 2
const READY_SECONDS := 1.6
const BANNER_SECONDS := 2.2
const WAVE_GAP := 1.0

const LIVES_START := 3
const LIVES_MOST := 5
const BLINK_SECONDS := 2.0
const SHOT_STEPS := [1, 2, 4, 6, 8]
const SHOT_GAP := 0.12
const SHOT_SPEED := 420.0
const SHOT_DAMAGE := 1.0
const SHOT_MOST := 320
const MOVE_SPEED := 150.0
const FOCUS_SPEED := 70.0
# Her hitbox: a few pixels at her middle, as the old games had it - the sprite
# is decoration.
const HITBOX := 2.5
const HITBOX_AT := Vector2(0.0, -10.0)
const BODY := 5.0
const SHOT_COLOUR := Color(0.55, 1.0, 0.62)

const RANK_MOST := 10
const SCROLL_START := 28.0
# A little faster every second of the run (6 px/s a minute), and a little
# with rank; never past SCROLL_MOST.
const SCROLL_PER_SECOND := 0.1
const SCROLL_PER_RANK := 1.5
const SCROLL_MOST := 95.0
const LASER_SECONDS := 5.0
const LASER_DPS := 24.0
const LASER_PER_LEVEL := 0.4
const PICKUP_REACH := 20.0
const MAGNET_REACH := 56.0
const MAGNET_SPEED := 260.0
const LASER_HALF := 7.0
const LASER_LEVELS := 5
# Each level's layer, from the inside out.
const LASER_COLOURS := [Color(0.55, 1.0, 0.62), Color(0.35, 0.95, 0.9), Color(0.4, 0.6, 1.0),
	Color(0.75, 0.45, 1.0), Color(1.0, 0.8, 0.3)]
# Side beams: this far either side of the main one, at this share of its damage.
const LASER_HEART := Color(1.0, 0.18, 0.15, 0.95)
const BEAM_Z := 10
const SHOTS_Z := 20
const BULLETS_Z := 21
const SIDE_BEAM_GAP := 18.0
const SIDE_BEAM_SHARE := 0.35
const METEORS_MOST := 3
const METEOR_FALL := 0.45
const METEOR_REACH := 70.0
const METEOR_HIT := 30.0
# A meteor takes this share of a boss's health (never less than METEOR_HIT).
const METEOR_BOSS_SHARE := 0.15
const METEOR_DROP := 0.05
const METEOR_TEXTURE := "res://art/maincharacter/meteor.png"
const METEOR_ITEM := "res://data/items/weapons/meteorite.tres"
# Arcs: in from a side this fast, turning back this hard - about 180 px in.
const ARC_IN := 165.0
const ARC_TURN := 75.0
# Until the server says (its answer to Go, "tiers"): the same table as
# minigames/services.py's healer_tier_pays().
const DEFAULT_PAYS := {"wave_gold": [10, 25, 100], "waves_per_tier": 8, "boss_gold": [120, 300, 1500],
	"goal_gold": 2000, "most": 5000}
# From the second heat, the chance a wave brings a second, smaller one of
# another kind alongside - more with each.
const BOTH_CHANCE := 0.45
const BOTH_PER_HEAT := 0.15
const THIRD_CHANCE := 0.3
const BOSS_ADDS_SECONDS := 7.0
# The earlier bosses call their waves this much less often a tier before the last.
const ADDS_PER_TIER := 2.0
# Each tier's boss's health before rank: the third is the old gate's wall.
const BOSS_HEALTH := [700.0, 1300.0, 2400.0]
# THE BOSSES' OWN CASTS, by land: what the banner says, and how many volleys.
const SIGNATURE := 4
const SIGNATURES := {Element.Type.FIRE: "Fire rain", Element.Type.ICE: "Frost volley",
	Element.Type.WIND: "Gale", Element.Type.WATER: "Tide", Element.Type.EARTH: "Rockfall",
	Element.Type.LIGHT: "Pillars of light", Element.Type.DARK: "Dark coils"}
const SIGNATURE_VOLLEYS := {Element.Type.FIRE: 6, Element.Type.ICE: 4, Element.Type.WIND: 7,
	Element.Type.WATER: 4, Element.Type.EARTH: 3, Element.Type.LIGHT: 3, Element.Type.DARK: 7}
# A freezing shot carries this in its damage; the rest carry 0.
const FREEZE_MARK := 1
const FREEZE_SECONDS := 0.9
const FROST_PROOF := 1.5
const ICE_TINT := Color(0.55, 0.8, 1.7)
const GUST_SECONDS := 2.6
const GUST_PUSH := 95.0
const PILLAR_HALF := 9.0
const PILLAR_WARN := 0.9
const PILLAR_BURN := 0.45
const ROCK_WARN := 0.9
const ROCK_REACH := 20.0
# Hits felt: how hard the screen shakes (px), and how fast it settles.
const SHAKE_FADE := 18.0
const SHAKE_MOST := 8.0
const BOSS_SHAKE := 1.5
const BOSS_SHAKE_GAP := 0.3
const HURT_SHAKE := 6.0
const METEOR_SHAKE := 4.0
const ROCK_SHAKE := 2.5
const BOSS_DOWN_SHAKE := 8.0
const BURST_Z := 19
const HAZARD_Z := 15
const ENRAGE_AT := 0.5
const ENRAGE_PACE := 0.65
const BOSS_ADDS := ["vee", "arcs", "pincer", "snake", "ring", "sweep"]
const FIRE_AFTER := 20.0
const FIRE_RISE := 0.4
const FIRE_RISE_PER_TIER := 0.15
const FIRE_MOST := 96.0
const FIRE_PUSH := 16.0
const FIRE_COLOURS := [Color(1.0, 0.45, 0.12), Color(1.0, 0.7, 0.2), Color(1.0, 0.25, 0.1)]
# The landing she starts on: the crypt's wall behind her, end to end between
# the side walls (wallrun pieces 101 and 51 wide, pillars 17).
const LANDING_WIDTHS := [101, 101, 17, 51, 17, 101, 101]
const LANDING_PIECES := {101: "res://scene/crypt/wallrun4.tscn", 51: "res://scene/crypt/wallrun2.tscn",
	17: "res://scene/crypt/pillar.tscn"}
const BULLET_SPEED := 105.0

# What each kind of monster is: its health before rank, how big it is to a
# shot, and its chance of dropping a power-up or a potion.
const KINDS := {
	"sprite": {"health": 3.0, "radius": 9.0, "power": 0.09, "potion": 0.025},
	"slime": {"health": 7.0, "radius": 9.0, "power": 0.16, "potion": 0.04},
	"mage": {"health": 12.0, "radius": 11.0, "power": 0.45, "potion": 0.07},
	"sniper": {"health": 8.0, "radius": 10.0, "power": 0.4, "potion": 0.06},
	"boss": {"health": 2400.0, "radius": 24.0, "power": 0.0, "potion": 0.0},
}
# After this many kills with no power-up, the next kill drops one.
const POWER_PITY := 12
const WAVE_KINDS := ["vee", "sweep", "mages", "slimes", "arcs", "snipers", "snake", "pincer", "ring", "wall"]

const LANDS := [Element.Type.LIGHT, Element.Type.WIND, Element.Type.WATER, Element.Type.ICE,
	Element.Type.EARTH, Element.Type.FIRE, Element.Type.DARK]
# Each land's monsters (scene/enemy/<id>.tscn); "" where a land has none.
const SPRITES := {Element.Type.DARK: "darksprite", Element.Type.LIGHT: "lightsprite", Element.Type.ICE: "icesprite",
	Element.Type.WIND: "windsprite", Element.Type.EARTH: "earthsprite", Element.Type.FIRE: "firesprite",
	Element.Type.WATER: "watersprite"}
const SLIMES := {Element.Type.DARK: "darkslime", Element.Type.LIGHT: "lightslime", Element.Type.ICE: "iceslime",
	Element.Type.WIND: "windslime", Element.Type.EARTH: "earthslime", Element.Type.FIRE: "",
	Element.Type.WATER: "waterslime"}
const MAGES := {Element.Type.DARK: "darkbushmage", Element.Type.LIGHT: "lightbushmage", Element.Type.ICE: "icebushmage",
	Element.Type.WIND: "windbushmage", Element.Type.EARTH: "bushmage", Element.Type.FIRE: "firebushmage",
	Element.Type.WATER: "waterbushmage"}
const SNIPERS := {Element.Type.DARK: "darkbushsniper", Element.Type.LIGHT: "lightbushsniper",
	Element.Type.ICE: "icebushsniper", Element.Type.WIND: "windbushsniper", Element.Type.EARTH: "earthbushsniper",
	Element.Type.FIRE: "bushsniper", Element.Type.WATER: "waterbushsniper"}
const BOSSES := {Element.Type.DARK: "bossenemy", Element.Type.LIGHT: "lightboss", Element.Type.ICE: "iceboss",
	Element.Type.WIND: "windboss", Element.Type.EARTH: "earthboss", Element.Type.FIRE: "fireboss",
	Element.Type.WATER: "waterboss"}
const ESSENCES := {Element.Type.DARK: "darkessence", Element.Type.LIGHT: "lightessence", Element.Type.ICE: "iceessence",
	Element.Type.WIND: "windessence", Element.Type.EARTH: "earthessence", Element.Type.FIRE: "fireessence",
	Element.Type.WATER: "wateressence"}
const POTION_ITEM := "res://data/items/consumables/smallhealthpotion.tres"
const HEALER_SCENE := "res://scene/characters/healer.tscn"


# A monster of the run: a picture of one of the game's own, moved by its kind.
class Foe extends Node2D:
	var kind: String = ""
	var health: float = 1.0
	var most: float = 1.0
	var radius: float = 9.0
	var age: float = 0.0
	var velocity: Vector2 = Vector2.ZERO
	var side: float = 1.0
	var stop_y: float = 0.0
	var shoot_in: float = 0.0
	var casts_left: int = 0
	var leaving: bool = false
	var flash: float = 0.0
	var dying: float = -1.0
	var wave: int = 0
	# How a sprite flies: "dive" straight down, "sweep" across, "arc" in from a
	# side and back out the way it came, "snake" weaving down, "ring" turning
	# round a point that comes down.
	var path: String = ""
	var anchor: Vector2 = Vector2.ZERO
	var phase: float = 0.0
	var sprite: AnimatedSprite2D = null


# THE LASER, drawn: a white core and a layer of colour for each level, the
# newest outermost; side beams from level 3.
class Beam extends Node2D:
	var length: float = 300.0
	var flicker: float = 0.0
	var level: int = 1
	# Set by the run each frame: the main beam's half width, where side beams stand.
	var half: float = LASER_HALF
	var sides: Array = []

	func _draw() -> void:
		var pulse: float = 1.0 + 0.15 * sin(flicker * 40.0)
		_one(0.0, half * pulse, level)
		for x in sides:
			_one(float(x), LASER_HALF * 0.6 * pulse, maxi(1, level - 2))

	func _one(x: float, wide: float, layers: int) -> void:
		for i in range(layers - 1, -1, -1):
			var colour: Color = LASER_COLOURS[i]
			var w: float = wide * (0.45 + 0.55 * float(i + 1) / float(layers))
			colour.a = 0.3 + 0.35 * (1.0 - float(i) / float(maxi(1, layers)))
			draw_rect(Rect2(x - w, -length, w * 2.0, length), colour)
		var heart: Color = LASER_HEART if layers >= LASER_LEVELS else Color(0.9, 1.0, 0.95, 0.85)
		draw_rect(Rect2(x - wide * 0.3, -length, wide * 0.6, length), heart)
		draw_rect(Rect2(x - 1.0, -length, 2.0, length), Color(1.0, 1.0, 1.0, 0.95))


# A HIT FELT: a ring and sparks flying out of a point, fading - a kill, a
# struck boss, a power-up. Drawn, not art; gone when it is spent.
class Burst extends Node2D:
	var colour: Color = Color.WHITE
	var life: float = 0.3
	var most: float = 0.3
	var reach: float = 16.0
	var sparks: int = 8
	var ring: bool = true
	var turn: float = 0.0

	func _process(delta: float) -> void:
		life -= delta
		if life <= 0.0:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var done: float = 1.0 - clampf(life / maxf(most, 0.001), 0.0, 1.0)
		var fade: float = 1.0 - done
		var r: float = reach * (0.3 + 0.7 * sqrt(done))
		if ring:
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(colour, 0.85 * fade), 1.0 + 2.0 * fade)
		for k in sparks:
			var dir: Vector2 = Vector2.from_angle(turn + TAU * k / maxi(1, sparks))
			draw_line(dir * r * 0.5, dir * r * (0.9 + 0.4 * fade), Color(colour.lightened(0.4), fade), 2.0)
		draw_circle(Vector2.ZERO, r * 0.35 * fade, Color(1.0, 1.0, 1.0, 0.9 * fade))


# WHAT A BOSS'S OWN CAST MARKS ON THE PATH, drawn from the run's lists each
# frame: light's pillars (a thin warning line, then the column burning), the
# rocks' marks (a ring closing on the spot), and the wind's streaks.
class Hazards extends Node2D:
	var pillars: Array = []
	var rocks: Array = []
	var gust: float = 0.0
	var gust_side: float = 1.0
	var clock: float = 0.0
	var rock_colour: Color = Color(0.75, 0.55, 0.3)

	func _draw() -> void:
		for p in pillars:
			var x: float = float(p["x"])
			if float(p["warn"]) > 0.0:
				var blink: float = 0.35 + 0.35 * sin(clock * 30.0)
				draw_rect(Rect2(x - 1.0, -HALF.y, 2.0, VIEW.y), Color(1.0, 0.95, 0.6, blink))
				draw_rect(Rect2(x - PILLAR_HALF, -HALF.y, PILLAR_HALF * 2.0, VIEW.y), Color(1.0, 0.95, 0.6, 0.08))
			else:
				var burn: float = clampf(float(p["burn"]) / PILLAR_BURN, 0.0, 1.0)
				draw_rect(Rect2(x - PILLAR_HALF * 1.5, -HALF.y, PILLAR_HALF * 3.0, VIEW.y), Color(1.0, 0.9, 0.45, 0.25 * burn))
				draw_rect(Rect2(x - PILLAR_HALF, -HALF.y, PILLAR_HALF * 2.0, VIEW.y), Color(1.0, 0.95, 0.7, 0.75 * burn))
				draw_rect(Rect2(x - 2.0, -HALF.y, 4.0, VIEW.y), Color(1.0, 1.0, 1.0, burn))
		for rock in rocks:
			var at: Vector2 = rock["at"]
			var left: float = clampf(float(rock["warn"]) / ROCK_WARN, 0.0, 1.0)
			draw_circle(at, ROCK_REACH, Color(0.0, 0.0, 0.0, 0.35 * (1.0 - left) + 0.1))
			draw_arc(at, ROCK_REACH * (0.6 + 1.4 * left), 0.0, TAU, 28, Color(rock_colour, 0.9), 2.0)
			draw_arc(at, ROCK_REACH, 0.0, TAU, 28, Color(rock_colour, 0.5), 1.0)
		if gust > 0.0:
			var strength: float = clampf(gust / 0.5, 0.0, 1.0)
			for i in 18:
				var y: float = -HALF.y + 12.0 + fmod(float(i) * 37.0, VIEW.y - 24.0)
				var run: float = fmod(clock * 520.0 + float(i) * 113.0, PATH_HALF * 2.0 + 120.0) - 60.0
				var x: float = -PATH_HALF + run if gust_side > 0.0 else PATH_HALF - run
				draw_line(Vector2(x, y), Vector2(x - gust_side * (26.0 + float(i % 3) * 10.0), y),
					Color(0.85, 1.0, 0.95, 0.45 * strength), 1.0)


# The suite's doors: which way she is steered, and whether she is focusing.
var steer: Callable = Callable(self, "_read_steer")
var focusing: Callable = Callable(self, "_read_focus")
var seed_value: int = 0

var state: int = State.READY
var lives: int = LIVES_START
var power: int = 0
var setbacks: int = 0
# Which tier (0 to TIERS - 1), and how many of its waves have passed.
var tier: int = 0
var wave_in_tier: int = 0
var waves_done: int = 0
var run_seconds: float = 0.0
var slain: int = 0
var banner: String = ""
var banner_left: float = 0.0
var untouchable: float = 0.0
var scrolled: float = 0.0
var boss: Foe = null
var lands: Array = []

var terrain: Node2D = null
var floor_layer: TileMapLayer = null
var props: Node2D = null
var foes: Node2D = null
var drops: Node2D = null
var healer: Node2D = null
var healer_sprite: AnimatedSprite2D = null
var field: BulletField = null
var goal: Node2D = null

var _rng := RandomNumberGenerator.new()
var _state_left: float = READY_SECONDS
var _wave: int = 0
var _wave_due: float = 0.0
var _wave_started: float = 0.0
# During a tier's banner, when its first wave comes; -1 otherwise.
var _between: float = -1.0
var _since_power: int = 0
var _shot_in: float = 0.0
var _shot_pos := PackedVector2Array()
var _shot_vel := PackedVector2Array()
var _shot_mesh: MultiMesh = null
var _shot_buffer := PackedFloat32Array()
# The floor and walls are laid from just below the screen's bottom, so she
# never stands over the dark.
var _painted_top: int = floori((HALF.y + 64.0) / TILE) + 1
var _painted_bottom: int = floori((HALF.y + 64.0) / TILE)
var _wall_top: int = floori((HALF.y + 64.0) / WALL_STEP) + 1
var laser: float = 0.0
# How strong her laser is (0: none yet): kept for the run, one lost to a hit.
var laser_level: int = 0
var meteors: int = 0
# How many bosses are down (0 to TIERS): the server is told at Leave.
var bosses_beaten: int = 0
# What a wave, the boss and the goal pay (the server's answer to Go).
var pays: Dictionary = DEFAULT_PAYS.duplicate(true)
var beam: Beam = null
var _falling: Array = []
var fire_height: float = 0.0
# How much of a power-up's push the fire has still to give back.
var _fire_push: float = 0.0
var embers: BulletField = null
var fire_glow: TextureRect = null
var _ember_in: float = 0.0
var _fire_told: bool = false
var _section_top: float = -CLEAR_START
var _obstacles: Array = []
var _boss_cast: float = 0.0
var _boss_casting: int = 0
var _boss_shots: float = 0.0
var _boss_fired: int = 0
var _boss_adds_in: float = BOSS_ADDS_SECONDS
var enraged: bool = false
var _goal_paid: bool = false
var _boss_casts: int = 0
# Where she was when the run ended (for result_text()).
var _fell_in: int = State.RUNNING
# God mode (the owner's switch on the screen), and whether it was on at all this run.
var god: bool = false
var god_used: bool = false
# Frozen by a freezing shot: still, not shooting, tinted - then a moment
# no freezing shot can take her again.
var frozen: float = 0.0
var _frost_proof: float = 0.0
# The wind's shove: how long left, and which way.
var gust: float = 0.0
var gust_side: float = 1.0
var hazards: Hazards = null
var _pillars: Array = []
var _rocks: Array = []
# Hits felt: how hard the screen shakes now, where the run was put, and her shine.
var shake: float = 0.0
var _home: Vector2 = Vector2.ZERO
var _shine_left: float = 0.0
var _boss_shook: float = 0.0
var _spark_in: float = 0.0
# Only for the look of things, so the run's own dice are the same either way.
var _fx_rng := RandomNumberGenerator.new()

static var _looks: Dictionary = {}


func _ready() -> void:
	# Moved every frame from _process: nothing to blend between physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rng.seed = seed_value if seed_value != 0 else int(Time.get_ticks_usec())
	_fx_rng.seed = _rng.seed + 1
	_home = position
	lands = LANDS.duplicate()
	for i in range(lands.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var swap: Variant = lands[i]
		lands[i] = lands[j]
		lands[j] = swap
	var dark := ColorRect.new()
	dark.color = Color(0.02, 0.02, 0.03)
	dark.position = -HALF - Vector2(40, 40)
	dark.size = VIEW + Vector2(80, 80)
	dark.z_index = -100
	add_child(dark)
	var ambience := CanvasModulate.new()
	ambience.color = Color(0.55, 0.55, 0.65)
	add_child(ambience)
	# BEYOND THE WALLS IS DARK, over everything: a monster coming in from a
	# side comes from behind the wall, and nothing is drawn under the
	# screen's words either side.
	for x in [-HALF.x - 40.0, PATH_HALF + 9.0]:
		var beyond := ColorRect.new()
		beyond.color = Color(0.0, 0.0, 0.0)
		beyond.position = Vector2(x, -HALF.y - 40.0)
		beyond.size = Vector2(HALF.x + 40.0 - PATH_HALF - 9.0, VIEW.y + 80.0)
		beyond.z_index = 50
		add_child(beyond)
	terrain = Node2D.new()
	terrain.name = "terrain"
	add_child(terrain)
	floor_layer = TileMapLayer.new()
	floor_layer.name = "floor"
	floor_layer.tile_set = load(FLOOR_SET) as TileSet
	floor_layer.collision_enabled = false
	floor_layer.navigation_enabled = false
	terrain.add_child(floor_layer)
	props = Node2D.new()
	props.name = "props"
	terrain.add_child(props)
	drops = Node2D.new()
	drops.name = "drops"
	add_child(drops)
	foes = Node2D.new()
	foes.name = "foes"
	add_child(foes)
	_make_healer()
	_make_shots()
	field = BulletField.new()
	field.name = "bullets"
	field.z_index = BULLETS_Z
	field.capacity = 2500
	field.bounds = Rect2(-HALF - Vector2(24, 24), VIEW + Vector2(48, 48))
	add_child(field)
	_make_fire()
	beam = Beam.new()
	beam.name = "laser"
	beam.z_index = BEAM_Z
	var glow := CanvasItemMaterial.new()
	glow.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	# Mixed, not added: added, the layers of a strong laser all came out white.
	beam.material = glow
	beam.visible = false
	add_child(beam)
	hazards = Hazards.new()
	hazards.name = "hazards"
	hazards.z_index = HAZARD_Z
	hazards.material = _glow_material()
	add_child(hazards)
	_lay_terrain()
	_lay_landing()
	banner = "Get ready"
	banner_left = READY_SECONDS


func _make_healer() -> void:
	healer = Node2D.new()
	healer.name = "healer"
	healer.position = Vector2(0.0, HALF.y - 50.0)
	var look: Dictionary = look_of_scene(HEALER_SCENE, false)
	healer_sprite = AnimatedSprite2D.new()
	healer_sprite.sprite_frames = look.get("frames") as SpriteFrames
	healer_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	healer_sprite.offset = look.get("offset", Vector2.ZERO)
	healer.add_child(healer_sprite)
	# STANDING on the landing until the run starts (step()).
	if healer_sprite.sprite_frames != null and healer_sprite.sprite_frames.has_animation("idleup"):
		healer_sprite.play("idleup")
	var glow := (load("res://scene/characters/playerlight.tscn") as PackedScene).instantiate() as PointLight2D
	if glow != null:
		glow.enabled = true
		healer.add_child(glow)
	add_child(healer)


func _make_fire() -> void:
	"""The fire behind her: a glow up from the bottom of the screen (an
	unshaded gradient, as the Endless washes its floor) and embers rising
	from it - nothing drawn for it, only made here."""
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.35, 0.08, 0.0))
	ramp.set_color(1, Color(1.0, 0.4, 0.1, 0.85))
	ramp.add_point(0.55, Color(1.0, 0.55, 0.15, 0.45))
	var fade := GradientTexture2D.new()
	fade.gradient = ramp
	fade.fill_from = Vector2(0.5, 0.0)
	fade.fill_to = Vector2(0.5, 1.0)
	fade.width = 4
	fade.height = 64
	fire_glow = TextureRect.new()
	fire_glow.name = "fire"
	fire_glow.texture = fade
	fire_glow.stretch_mode = TextureRect.STRETCH_SCALE
	fire_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fire_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	fire_glow.material = unshaded
	fire_glow.z_index = 40
	fire_glow.visible = false
	add_child(fire_glow)
	embers = BulletField.new()
	embers.name = "embers"
	embers.capacity = 400
	embers.bounds = Rect2(-PATH_HALF - 10.0, -HALF.y - 10.0, PATH_HALF * 2.0 + 20.0, VIEW.y + 20.0)
	embers.z_index = 41
	add_child(embers)


func fire_top() -> float:
	"""Where the fire reaches up to, in screen space; past the bottom when none."""
	return HALF.y - fire_height


func _burn(delta: float) -> void:
	if run_seconds >= FIRE_AFTER:
		fire_height = minf(FIRE_MOST, fire_height + (FIRE_RISE + FIRE_RISE_PER_TIER * tier) * delta)
	if _fire_push > 0.0:
		# PUSHED BACK by a power-up, over a moment.
		var give: float = minf(_fire_push, FIRE_PUSH * 4.0 * delta)
		_fire_push -= give
		fire_height = maxf(0.0, fire_height - give)
	if fire_height > 0.0 and not _fire_told:
		_fire_told = true
		_say("The fire is behind you")
	var glow_height: float = fire_height * 1.6 + (14.0 if fire_height > 0.0 else 0.0)
	fire_glow.visible = glow_height > 0.0
	fire_glow.position = Vector2(-PATH_HALF, HALF.y - glow_height)
	fire_glow.size = Vector2(PATH_HALF * 2.0, glow_height)
	if fire_height > 0.0:
		_ember_in -= delta
		while _ember_in <= 0.0:
			_ember_in += 0.03
			var x: float = _rng.randf_range(-PATH_HALF, PATH_HALF)
			var colour: Color = FIRE_COLOURS[_rng.randi_range(0, FIRE_COLOURS.size() - 1)]
			var speed: float = _rng.randf_range(30.0, 70.0)
			embers.spawn(Vector2(x, HALF.y + 4.0), -PI / 2.0 + _rng.randf_range(-0.3, 0.3), speed, colour,
				_rng.randf() < 0.2, 0.0, 0.0, (fire_height + 16.0) / speed)
	embers.step(delta, Vector2(99999.0, 99999.0), 0.0, 0.0, true)
	if fire_height > 0.0 and healer.position.y + HITBOX_AT.y > fire_top():
		hurt()
		healer.position.y = minf(healer.position.y, fire_top() - 24.0)


static func laser_half(level: int) -> float:
	return LASER_HALF * (1.0 + 0.25 * (maxi(1, level) - 1))


static func laser_dps(level: int) -> float:
	return LASER_DPS * (1.0 + LASER_PER_LEVEL * (maxi(1, level) - 1))


static func laser_seconds(level: int) -> float:
	return LASER_SECONDS + 1.0 * (maxi(1, level) - 1)


static func side_beams(level: int) -> Array:
	"""Where the side beams stand, either side of the main one."""
	if level >= 5:
		return [-SIDE_BEAM_GAP, SIDE_BEAM_GAP, -SIDE_BEAM_GAP * 2.0, SIDE_BEAM_GAP * 2.0]
	if level >= 3:
		return [-SIDE_BEAM_GAP, SIDE_BEAM_GAP]
	return []


func _shine(delta: float) -> void:
	"""The laser: up from her through everything in its column - and its
	side beams' - harder at each level."""
	beam.visible = laser > 0.0 and frozen <= 0.0
	if laser <= 0.0 or frozen > 0.0:
		return
	var level: int = maxi(1, laser_level)
	beam.level = level
	beam.half = laser_half(level)
	beam.sides = side_beams(level)
	beam.position = healer.position + Vector2(0.0, -18.0)
	beam.length = beam.position.y + HALF.y
	beam.flicker += delta
	beam.queue_redraw()
	var columns: Array = [[0.0, laser_half(level), laser_dps(level)]]
	for x in side_beams(level):
		columns.append([float(x), LASER_HALF * 0.6, laser_dps(level) * SIDE_BEAM_SHARE])
	for foe in foes.get_children():
		var f := foe as Foe
		if f == null or f.dying >= 0.0 or f.position.y > beam.position.y or f.position.y < -HALF.y - 8.0:
			continue
		for column in columns:
			if absf(f.position.x - beam.position.x - float(column[0])) <= float(column[1]) + f.radius:
				_strike(f, float(column[2]) * delta)


func gain_meteor() -> void:
	meteors = mini(METEORS_MOST, meteors + 1)
	_say("Meteor - press Space")
	_ring_out(Color(1.0, 0.7, 0.3))


func meteor_target() -> Foe:
	"""The boss at the gate; before it, the toughest monster on screen."""
	if boss != null and is_instance_valid(boss) and boss.dying < 0.0:
		return boss
	var best: Foe = null
	for foe in foes.get_children():
		var f := foe as Foe
		if f == null or f.dying >= 0.0 or f.position.y < -HALF.y or f.position.y > HALF.y:
			continue
		if best == null or f.health > best.health:
			best = f
	return best


func fire_meteor() -> bool:
	"""Space: a meteor called down on meteor_target(). False with none held,
	nothing to aim at, or the run not on."""
	if meteors <= 0 or (state != State.RUNNING and state != State.BOSS):
		return false
	var target: Foe = meteor_target()
	if target == null:
		return false
	meteors -= 1
	var rock := Sprite2D.new()
	rock.texture = load(METEOR_TEXTURE) as Texture2D
	rock.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rock.z_index = 35
	rock.position = Vector2(target.position.x, -HALF.y - 40.0)
	add_child(rock)
	_falling.append({"rock": rock, "target": target, "left": METEOR_FALL, "from": rock.position})
	return true


func _meteors_fall(delta: float) -> void:
	var still: Array = []
	for fall in _falling:
		var rock: Sprite2D = fall["rock"]
		var target: Foe = fall["target"] if is_instance_valid(fall["target"]) else null
		var to: Vector2 = target.position + Vector2(0.0, -8.0) if target != null else rock.position + Vector2(0.0, 40.0)
		fall["left"] = float(fall["left"]) - delta
		var done: float = 1.0 - clampf(float(fall["left"]) / METEOR_FALL, 0.0, 1.0)
		rock.position = (fall["from"] as Vector2).lerp(to, done * done)
		rock.rotation += delta * 6.0
		if float(fall["left"]) > 0.0:
			still.append(fall)
			continue
		_land_meteor(rock.position, target)
		rock.queue_free()
	_falling = still


func _land_meteor(at: Vector2, target: Foe) -> void:
	if target != null and target == boss and target.dying < 0.0:
		_strike(target, maxf(METEOR_HIT, target.most * METEOR_BOSS_SHARE))
	for foe in foes.get_children():
		var f := foe as Foe
		if f != null and f != boss and f.dying < 0.0 and f.position.distance_to(at) <= METEOR_REACH:
			_strike(f, METEOR_HIT)
	var burst := Polygon2D.new()
	var ring := PackedVector2Array()
	for k in 20:
		ring.append(Vector2.from_angle(TAU * k / 20.0) * METEOR_REACH * 0.6)
	burst.polygon = ring
	burst.color = Color(1.0, 0.75, 0.35, 0.7)
	burst.position = at
	burst.z_index = 34
	var glow := CanvasItemMaterial.new()
	glow.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	burst.material = glow
	add_child(burst)
	var fade := burst.create_tween()
	fade.tween_property(burst, "scale", Vector2.ONE * 1.6, 0.3)
	fade.parallel().tween_property(burst, "modulate:a", 0.0, 0.3)
	fade.tween_callback(burst.queue_free)
	shake_by(METEOR_SHAKE)


# =============================================================================
# GOLD
# =============================================================================

func gold_now() -> int:
	"""What the run has earned so far, by the server's table: each wave
	passed by its tier, each boss down, the goal."""
	var table: Array = pays.get("wave_gold") if pays.get("wave_gold") is Array else DEFAULT_PAYS["wave_gold"]
	var bosses: Array = pays.get("boss_gold") if pays.get("boss_gold") is Array else DEFAULT_PAYS["boss_gold"]
	var per: int = maxi(1, int(pays.get("waves_per_tier", WAVES_PER_TIER)))
	var passed: int = mini(waves_done, TIERS * WAVES_PER_TIER)
	var gold: int = 0
	for i in passed:
		gold += int(table[mini(i / per, table.size() - 1)])
	for k in mini(bosses_beaten, bosses.size()):
		gold += int(bosses[k])
	if state == State.WON:
		gold += int(pays.get("goal_gold", DEFAULT_PAYS["goal_gold"]))
	return gold


static func pays_from(answer: Dictionary) -> Dictionary:
	"""The table to count by, from the server's answer to Go: its "tiers"
	(0.100.0); the default when it has none - a server not yet updated, whose
	old table is for five stretches."""
	if answer.get("tiers") is Dictionary and (answer["tiers"] as Dictionary).get("wave_gold") is Array:
		return (answer["tiers"] as Dictionary).duplicate(true)
	return DEFAULT_PAYS.duplicate(true)


func _make_shots() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_shot_mesh = MultiMesh.new()
	_shot_mesh.transform_format = MultiMesh.TRANSFORM_2D
	_shot_mesh.use_colors = true
	_shot_mesh.mesh = quad
	_shot_mesh.instance_count = SHOT_MOST
	_shot_mesh.visible_instance_count = 0
	_shot_buffer.resize(SHOT_MOST * BulletField.STRIDE)
	var shader := Shader.new()
	shader.code = BulletField.SHADER_CODE
	var shading := ShaderMaterial.new()
	shading.shader = shader
	var drawer := MultiMeshInstance2D.new()
	drawer.name = "shots"
	drawer.z_index = SHOTS_Z
	drawer.multimesh = _shot_mesh
	drawer.texture = BulletField.orb_texture()
	drawer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	drawer.material = shading
	# Rewritten every frame, in whatever order: never blended by the engine.
	drawer.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(drawer)
	RenderingServer.multimesh_set_physics_interpolated(_shot_mesh.get_rid(), false)


# =============================================================================
# THE NUMBERS
# =============================================================================

func rank() -> int:
	return clampi(heat() + power + laser_level - setbacks, 0, RANK_MOST)


func heat() -> int:
	"""How far the run is in: HEAT_PER_TIER a tier, and one more half way
	through one - 0 to 5. The next tier starts hotter than the last ended."""
	return tier * HEAT_PER_TIER + (1 if wave_in_tier >= WAVES_PER_TIER / 2 else 0)


static func foe_health(base: float, at_rank: int) -> float:
	return base * (1.0 + 0.18 * at_rank)


static func bullet_speed(at_rank: int) -> float:
	return BULLET_SPEED * (1.0 + 0.06 * at_rank)


static func fire_gap(base: float, at_rank: int) -> float:
	return base * maxf(0.5, 1.0 - 0.05 * at_rank)


static func group_extra(at_rank: int) -> int:
	return at_rank / 3


static func wave_time(at_rank: int) -> float:
	return maxf(6.0, 12.0 - 0.6 * at_rank)


func scroll_speed() -> float:
	return minf(SCROLL_MOST, SCROLL_START + SCROLL_PER_SECOND * run_seconds + SCROLL_PER_RANK * rank())


static func shot_offsets(count: int) -> Array:
	"""[x offset, angle in degrees from straight up] for each shot of a volley:
	2 side by side, then each step a pair fanning wider (the owner's 2, 4, 6,
	8). One goes straight up from her middle."""
	if count <= 1:
		return [[0.0, 0.0]]
	var out: Array = [[-4.0, 0.0], [4.0, 0.0]]
	var spread: float = 7.0
	while out.size() < count:
		out.append([-6.0, -spread])
		out.append([6.0, spread])
		spread += 8.0
	return out


func land() -> int:
	return int(lands[mini(tier, TIERS - 1)])


func time_text() -> String:
	var whole: int = int(run_seconds)
	return "%d:%02d" % [whole / 60, whole % 60]


func land_name(element: int) -> String:
	return Element.name_for(element).capitalize()


# =============================================================================
# EACH FRAME
# =============================================================================

func _process(delta: float) -> void:
	step(minf(delta, 0.05))


func step(delta: float) -> void:
	"""One frame of the run; the suite calls it with its own delta."""
	if state == State.WON or state == State.LOST:
		return
	banner_left = maxf(0.0, banner_left - delta)
	if banner_left <= 0.0:
		banner = ""
	if state == State.READY:
		_state_left -= delta
		_move_healer(delta)
		if _state_left <= 0.0:
			state = State.RUNNING
			if healer_sprite.sprite_frames != null and healer_sprite.sprite_frames.has_animation("walkup"):
				healer_sprite.play("walkup")
			_start_wave()
		return
	run_seconds += delta
	if god:
		god_used = true
	untouchable = maxf(0.0, untouchable - delta)
	laser = maxf(0.0, laser - delta)
	frozen = maxf(0.0, frozen - delta)
	_frost_proof = maxf(0.0, _frost_proof - delta)
	gust = maxf(0.0, gust - delta)
	_scroll(delta)
	_move_healer(delta)
	_fire(delta)
	_move_shots(delta)
	_move_foes(delta)
	_move_drops(delta)
	_burn(delta)
	_shine(delta)
	_meteors_fall(delta)
	_hazards_step(delta)
	var hit: Vector2i = field.step(delta, healer.position + HITBOX_AT, HITBOX, 0.0, untouchable > 0.0)
	if hit.x > 0:
		_take_hits()
	healer.visible = untouchable <= 0.0 or int(untouchable * 12.0) % 2 == 0
	_feel(delta)
	match state:
		State.RUNNING:
			_waves(delta)
		State.BOSS:
			_boss_step(delta)
		State.GOAL:
			if goal != null and goal.position.y + terrain.position.y >= healer.position.y - 20.0:
				_finish(true)


func _scroll(delta: float) -> void:
	scrolled += scroll_speed() * delta
	terrain.position.y = roundf(scrolled)
	_lay_terrain()
	# What scrolls stands on the floor: pushed by a pillar she cannot get past
	# and she is crushed off the bottom of the screen.
	for o in _obstacles:
		var rect: Rect2 = o["rect"]
		rect.position.y += terrain.position.y
		healer.position = _pushed_out(healer.position, BODY, rect)
	if healer.position.y > HALF.y + 6.0:
		hurt()
		healer.position.y = HALF.y - 50.0


func _move_healer(delta: float) -> void:
	var dir: Vector2 = steer.call()
	if dir.length() > 1.0:
		dir = dir.normalized()
	if frozen > 0.0:
		dir = Vector2.ZERO
	var speed: float = FOCUS_SPEED if bool(focusing.call()) else MOVE_SPEED
	var at: Vector2 = healer.position + dir * speed * delta
	if gust > 0.0:
		# THE GALE shoves her; she can walk against it, slowly.
		at.x += gust_side * GUST_PUSH * delta
	at.x = clampf(at.x, -PATH_HALF + 8.0, PATH_HALF - 8.0)
	at.y = clampf(at.y, -HALF.y + 30.0, HALF.y - 12.0)
	for o in _obstacles:
		var rect: Rect2 = o["rect"]
		rect.position.y += terrain.position.y
		at = _pushed_out(at, BODY, rect)
	healer.position = at


static func _pushed_out(point: Vector2, radius: float, rect: Rect2) -> Vector2:
	"""`point`, a circle of `radius`, out of `rect` the shortest way."""
	var grown: Rect2 = rect.grow(radius)
	if not grown.has_point(point):
		return point
	var left: float = point.x - grown.position.x
	var right: float = grown.end.x - point.x
	var up: float = point.y - grown.position.y
	var down: float = grown.end.y - point.y
	var least: float = minf(minf(left, right), minf(up, down))
	if least == down:
		return Vector2(point.x, grown.end.y)
	if least == up:
		return Vector2(point.x, grown.position.y)
	if least == left:
		return Vector2(grown.position.x, point.y)
	return Vector2(grown.end.x, point.y)


func _read_steer() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_right"): dir.x += 1.0
	if Input.is_action_pressed("move_left"): dir.x -= 1.0
	if Input.is_action_pressed("move_down"): dir.y += 1.0
	if Input.is_action_pressed("move_up"): dir.y -= 1.0
	return dir


func _read_focus() -> bool:
	return Input.is_action_pressed("sprint")


# =============================================================================
# HER SHOTS
# =============================================================================

func _fire(delta: float) -> void:
	_shot_in -= delta
	if _shot_in > 0.0:
		return
	if frozen > 0.0:
		_shot_in = 0.0
		return
	_shot_in += SHOT_GAP
	var from: Vector2 = healer.position + Vector2(0.0, -16.0)
	# WITH THE LASER ON, HER SHOTS GO BESIDE IT, never through it (the owner:
	# "bullets need to be an addition to laser the do not overlap"): each
	# starts out past the beam's outer edge, its own side.
	var clear: float = laser_edge() if laser > 0.0 else 0.0
	for shot in shot_offsets(int(SHOT_STEPS[power])):
		if _shot_pos.size() >= SHOT_MOST:
			break
		var x: float = float(shot[0])
		if clear > 0.0:
			x = signf(x if x != 0.0 else float(shot[1])) * (clear + absf(x))
		_shot_pos.append(from + Vector2(x, 0.0))
		_shot_vel.append(Vector2.UP.rotated(deg_to_rad(float(shot[1]))) * SHOT_SPEED)


func laser_edge() -> float:
	"""How far either side of her the laser reaches, side beams and all, and
	a little more: where her shots start while it is on."""
	var level: int = maxi(1, laser_level)
	var edge: float = laser_half(level)
	for x in side_beams(level):
		edge = maxf(edge, absf(float(x)) + LASER_HALF * 0.6)
	return edge + 3.0


func shots_flying() -> int:
	return _shot_pos.size()


func _move_shots(delta: float) -> void:
	var i: int = 0
	while i < _shot_pos.size():
		var at: Vector2 = _shot_pos[i] + _shot_vel[i] * delta
		var spent: bool = at.y < -HALF.y - 12.0 or absf(at.x) > PATH_HALF + 4.0
		if not spent:
			for o in _obstacles:
				var rect: Rect2 = o["art"]
				rect.position.y += terrain.position.y
				if rect.has_point(at):
					spent = true
					break
		if not spent:
			for foe in foes.get_children():
				var f := foe as Foe
				if f == null or f.dying >= 0.0 or f.position.y < -HALF.y - 8.0:
					continue
				if at.distance_squared_to(f.position + Vector2(0, -8)) <= (f.radius + 3.0) * (f.radius + 3.0):
					_strike(f, SHOT_DAMAGE)
					spent = true
					break
		if spent:
			var last: int = _shot_pos.size() - 1
			_shot_pos[i] = _shot_pos[last]
			_shot_vel[i] = _shot_vel[last]
			_shot_pos.resize(last)
			_shot_vel.resize(last)
			continue
		_shot_pos[i] = at
		i += 1
	for k in _shot_pos.size():
		var o: int = k * BulletField.STRIDE
		var dir: Vector2 = _shot_vel[k].normalized()
		_shot_buffer[o] = -dir.y * 6.0
		_shot_buffer[o + 1] = dir.x * 9.0
		_shot_buffer[o + 2] = 0.0
		_shot_buffer[o + 3] = roundf(_shot_pos[k].x)
		_shot_buffer[o + 4] = dir.x * 6.0
		_shot_buffer[o + 5] = dir.y * -9.0
		_shot_buffer[o + 6] = 0.0
		_shot_buffer[o + 7] = roundf(_shot_pos[k].y)
		_shot_buffer[o + 8] = SHOT_COLOUR.r
		_shot_buffer[o + 9] = SHOT_COLOUR.g
		_shot_buffer[o + 10] = SHOT_COLOUR.b
		_shot_buffer[o + 11] = 1.0
	_shot_mesh.buffer = _shot_buffer
	_shot_mesh.visible_instance_count = _shot_pos.size()


func _strike(f: Foe, damage: float) -> void:
	f.health -= damage
	f.flash = 0.08
	if f == boss and f.dying < 0.0:
		# A BOSS STRUCK sparks where it is hit, and the screen shakes a little.
		if _boss_shook <= 0.0:
			_boss_shook = BOSS_SHAKE_GAP
			shake_by(BOSS_SHAKE)
		if _spark_in <= 0.0:
			_spark_in = 0.08
			var at: Vector2 = f.position + Vector2(_fx_rng.randf_range(-14.0, 14.0), _fx_rng.randf_range(-26.0, -4.0))
			_burst(at, Color(1.0, 0.95, 0.8), 9.0, 5, 0.15, false)
	if f.health <= 0.0:
		_kill(f)


func _kill(f: Foe) -> void:
	f.dying = 0.25
	slain += 1
	_since_power += 1
	var info: Dictionary = KINDS.get(f.kind, {})
	var potion_odds: float = float(info.get("potion", 0.0)) * maxf(0.4, 1.0 - 0.1 * heat())
	if f.kind != "boss":
		# EVERY KILL BURSTS, in its land's colour.
		var big: bool = f.kind == "mage" or f.kind == "sniper"
		_burst(f.position + Vector2(0.0, -8.0), Element.colour_for(land()).lightened(0.25),
			24.0 if big else 16.0, 10 if big else 7, 0.35 if big else 0.28)
	if (f.kind == "mage" or f.kind == "sniper") and _rng.randf() < METEOR_DROP:
		_drop("meteor", f.position)
	elif f.kind != "boss":
		if _since_power >= POWER_PITY or _rng.randf() < float(info.get("power", 0.0)):
			_drop("power", f.position)
			_since_power = 0
		elif _rng.randf() < potion_odds:
			_drop("potion", f.position)
	if f == boss:
		_boss_down()


# =============================================================================
# LIVES AND DROPS
# =============================================================================

func hurt() -> void:
	"""One hit, one life: she blinks, loses a shot step, and the screen's
	bullets go - a breath before the next."""
	if untouchable > 0.0 or state == State.WON or state == State.LOST or state == State.READY:
		return
	if god:
		god_used = true
		return
	lives -= 1
	setbacks += 1
	# A laser level goes first, then a shot step.
	if laser_level > 0:
		laser_level -= 1
		if laser_level == 0:
			laser = 0.0
	else:
		power = maxi(0, power - 1)
	untouchable = BLINK_SECONDS
	field.clear()
	frozen = 0.0
	shake_by(HURT_SHAKE)
	_burst(healer.position + HITBOX_AT, Color(1.0, 0.3, 0.25), 34.0, 12, 0.45)
	if lives <= 0:
		_finish(false)


func gain_power() -> void:
	_fire_push += FIRE_PUSH
	if power >= SHOT_STEPS.size() - 1:
		# At eight shots, a power-up is the LASER - a level stronger each time.
		laser_level = mini(LASER_LEVELS, laser_level + 1)
		laser = laser_seconds(laser_level)
		_say("Laser %d" % laser_level)
		_ring_out(LASER_COLOURS[laser_level - 1])
		return
	power += 1
	_say("Shots %d" % int(SHOT_STEPS[power]))
	_ring_out(SHOT_COLOUR)


func gain_life() -> void:
	lives = mini(LIVES_MOST, lives + 1)
	_say("A life more" if lives < LIVES_MOST else "Lives full")
	_ring_out(Color(1.0, 0.45, 0.5))


func _say(words: String) -> void:
	"""A short word in the banner - unless a tier's or the gate's is up."""
	if banner_left > 1.2 and banner != "" and not banner.begins_with("Shots") and not banner.begins_with("A life") \
			and not banner.begins_with("Lives") and not banner.begins_with("Laser") and not banner.begins_with("Meteor") \
			and not banner.begins_with("The keeper"):
		return
	banner = words
	banner_left = 1.0


func _drop(what: String, at: Vector2) -> void:
	var item_path: String = POTION_ITEM if what == "potion" else (METEOR_ITEM if what == "meteor"
		else "res://data/items/materials/%s.tres" % str(ESSENCES.get(land(), "lightessence")))
	var item: Resource = load(item_path) if ResourceLoader.exists(item_path) else null
	var icon := Sprite2D.new()
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var texture: Texture2D = item.get("icon") as Texture2D if item != null else null
	if texture != null:
		icon.texture = texture
		var size: Vector2 = texture.get_size()
		icon.scale = Vector2.ONE * (14.0 / maxf(1.0, maxf(size.x, size.y)))
	icon.set_meta(&"drop", what)
	icon.position = at
	drops.add_child(icon)


func _move_drops(delta: float) -> void:
	for node in drops.get_children():
		var icon := node as Node2D
		var to_her: Vector2 = (healer.position + HITBOX_AT) - icon.position
		if to_her.length() <= MAGNET_REACH:
			# Drawn to her, from whichever side.
			icon.position += to_her.limit_length(MAGNET_SPEED * delta)
		else:
			icon.position.y += (scroll_speed() + 25.0) * delta
		if icon.position.distance_to(healer.position + HITBOX_AT) <= PICKUP_REACH:
			match str(icon.get_meta(&"drop")):
				"potion":
					gain_life()
				"meteor":
					gain_meteor()
				_:
					gain_power()
			_gone(icon)
		elif icon.position.y > HALF.y + 40.0:
			_gone(icon)


# =============================================================================
# THE WAVES
# =============================================================================

func _waves(_delta: float) -> void:
	if _between >= 0.0:
		if run_seconds >= _between:
			_between = -1.0
			_start_wave()
		return
	if wave_left() == 0 and _wave_due > run_seconds + WAVE_GAP:
		_wave_due = run_seconds + WAVE_GAP
	if run_seconds >= _wave_due:
		_next_wave()


func wave_left() -> int:
	"""How many of the newest wave are still standing."""
	var left: int = 0
	for foe in foes.get_children():
		var f := foe as Foe
		if f != null and f.wave == _wave and f.dying < 0.0:
			left += 1
	return left


func _next_wave() -> void:
	waves_done += 1
	wave_in_tier += 1
	if wave_in_tier >= WAVES_PER_TIER:
		# THE TIER'S LAST WAVE PASSED: its land's boss.
		_start_boss()
		return
	_start_wave()


func tier_banner() -> String:
	return "Tier %d - the %s lands" % [tier + 1, land_name(land())]


func _start_wave() -> void:
	_wave += 1
	_wave_started = run_seconds
	_wave_due = run_seconds + wave_time(rank())
	if waves_done == 0:
		banner = tier_banner()
		banner_left = BANNER_SECONDS
	var kind: String = _pick_kind()
	spawn_wave(kind)
	var hot: int = heat()
	if hot >= 1 and _rng.randf() < BOTH_CHANCE + BOTH_PER_HEAT * (hot - 1):
		var other: String = kind
		while other == kind:
			other = str(WAVE_KINDS[_rng.randi_range(0, WAVE_KINDS.size() - 1)])
		spawn_wave(other, 0.5)
		if hot >= 3 and _rng.randf() < THIRD_CHANCE:
			var third: String = other
			while third == other or third == kind:
				third = str(WAVE_KINDS[_rng.randi_range(0, WAVE_KINDS.size() - 1)])
			spawn_wave(third, 0.5)


func crowd() -> int:
	"""How many more monsters each wave brings: one a heat (to four), and the rank's."""
	return group_extra(rank()) + mini(heat(), 4)


func _pick_kind() -> String:
	# The first waves are the gentlest: a V, then a sweep.
	if waves_done == 0:
		return "vee"
	if waves_done == 1:
		return "sweep"
	return str(WAVE_KINDS[_rng.randi_range(0, WAVE_KINDS.size() - 1)])


func spawn_wave(kind: String, share: float = 1.0) -> Array:
	"""One wave of `kind`, of this tier's land - `share` of its size when it
	comes alongside another. Returned for the suite."""
	var made: Array = []
	var r: int = rank()
	var top: float = -HALF.y - 24.0
	match kind:
		"vee":
			var count: int = _sized(mini(13, 7 + crowd()), share)
			var centre: float = _rng.randf_range(-PATH_HALF + 90.0, PATH_HALF - 90.0)
			for i in count:
				var off: float = float(i) - float(count - 1) / 2.0
				var f := _foe("sprite", Vector2(centre + off * 26.0, top - absf(off) * 22.0))
				f.path = "dive"
				f.velocity = Vector2(0.0, 70.0 + 5.0 * r)
				f.shoot_in = _rng.randf_range(1.2, 2.4)
				made.append(f)
		"sweep":
			var count: int = _sized(mini(14, 8 + crowd()), share)
			var side: float = -1.0 if _rng.randf() < 0.5 else 1.0
			var row_y: float = _rng.randf_range(-HALF.y + 40.0, -HALF.y + 90.0)
			for i in count:
				var f := _foe("sprite", Vector2(-side * (PATH_HALF + 20.0 + i * 30.0), row_y))
				f.side = side
				f.path = "sweep"
				f.velocity = Vector2(side * 95.0, 10.0)
				f.shoot_in = _rng.randf_range(0.8, 2.0)
				made.append(f)
		"mages":
			var count: int = _sized(3 + (1 if r >= 4 else 0) + (1 if heat() >= 3 else 0), share)
			for i in count:
				var x: float = (float(i) - float(count - 1) / 2.0) * 150.0
				var f := _foe("mage", Vector2(x, top))
				f.velocity = Vector2(0.0, 60.0)
				f.stop_y = -HALF.y + 70.0 + _rng.randf_range(0.0, 30.0)
				f.casts_left = 3
				f.shoot_in = 1.0
				made.append(f)
		"slimes":
			var count: int = _sized(6 + crowd(), share)
			for i in count:
				var f := _foe("slime", Vector2(_rng.randf_range(-PATH_HALF + 30.0, PATH_HALF - 30.0),
					top - _rng.randf_range(0.0, 80.0)))
				f.velocity = Vector2(0.0, 32.0 + 3.0 * r)
				f.side = _rng.randf_range(0.0, TAU)
				made.append(f)
		"arcs":
			var count: int = _sized(8 + crowd(), share)
			for i in count:
				var side: float = -1.0 if i % 2 == 0 else 1.0
				var f := _foe("sprite", Vector2(side * (PATH_HALF + 16.0), -HALF.y - 10.0 - float(i / 2) * 34.0))
				f.side = side
				f.path = "arc"
				f.velocity = Vector2(-side * ARC_IN, 70.0)
				f.shoot_in = _rng.randf_range(1.0, 2.0)
				made.append(f)
		"snipers":
			for side in ([-1.0, 1.0, -0.5, 0.5] if heat() >= 3 else [-1.0, 1.0]):
				var f := _foe("sniper", Vector2(side * (PATH_HALF - 50.0), top))
				f.velocity = Vector2(0.0, 55.0)
				f.stop_y = -HALF.y + 45.0
				f.side = side
				f.casts_left = 6 + crowd()
				f.shoot_in = 1.0
				made.append(f)
		"snake":
			# A column weaving down the path.
			var count: int = _sized(8 + crowd(), share)
			var centre: float = _rng.randf_range(-PATH_HALF + 90.0, PATH_HALF - 90.0)
			for i in count:
				var f := _foe("sprite", Vector2(centre, top - i * 24.0))
				f.path = "snake"
				f.anchor = Vector2(centre, 0.0)
				f.side = 70.0
				f.phase = -i * 0.5
				f.velocity = Vector2(0.0, 62.0 + 4.0 * r)
				f.shoot_in = _rng.randf_range(1.2, 2.6)
				made.append(f)
		"pincer":
			# Two lines in from the top corners, crossing in the middle.
			var count: int = _sized(5 + crowd(), share)
			for side in [-1.0, 1.0]:
				for i in count:
					var f := _foe("sprite", Vector2(side * (PATH_HALF + 16.0 + i * 22.0), top - i * 26.0))
					f.path = "dive"
					f.velocity = Vector2(-side * 85.0, 80.0 + 4.0 * r)
					f.shoot_in = _rng.randf_range(1.0, 2.2)
					made.append(f)
		"ring":
			# A ring turning round a point coming down.
			var count: int = _sized(8 + crowd(), share)
			var centre := Vector2(_rng.randf_range(-PATH_HALF + 80.0, PATH_HALF - 80.0), top - 60.0)
			for i in count:
				var f := _foe("sprite", centre)
				f.path = "ring"
				f.anchor = centre
				f.phase = TAU * i / count
				f.velocity = Vector2(0.0, 45.0 + 3.0 * r)
				f.shoot_in = _rng.randf_range(1.5, 3.0)
				made.append(f)
		"wall":
			# Slimes across the path, one way through.
			var gap: float = _rng.randf_range(-PATH_HALF + 70.0, PATH_HALF - 70.0)
			var x: float = -PATH_HALF + 24.0
			while x < PATH_HALF - 20.0:
				if absf(x - gap) > 44.0:
					var f := _foe("slime", Vector2(x, top))
					f.velocity = Vector2(0.0, 30.0 + 2.0 * r)
					f.side = 0.0
					made.append(f)
				x += 34.0
	return made


static func _sized(count: int, share: float) -> int:
	return maxi(2, roundi(count * share)) if share < 1.0 else count


func _foe(kind: String, at: Vector2) -> Foe:
	var element: int = land()
	var scene_id: String = ""
	match kind:
		"sprite":
			scene_id = str(SPRITES.get(element, "windsprite"))
		"slime":
			scene_id = str(SLIMES.get(element, ""))
			if scene_id == "":
				scene_id = str(SPRITES.get(element, "windsprite"))
		"mage":
			scene_id = str(MAGES.get(element, "bushmage"))
		"sniper":
			scene_id = str(SNIPERS.get(element, "bushsniper"))
		"boss":
			scene_id = str(BOSSES.get(element, "bossenemy"))
	var f := Foe.new()
	f.kind = kind
	f.wave = _wave
	var info: Dictionary = KINDS.get(kind, {})
	var base: float = float(BOSS_HEALTH[mini(tier, TIERS - 1)]) if kind == "boss" else float(info.get("health", 3.0))
	f.most = foe_health(base, rank())
	f.health = f.most
	f.radius = float(info.get("radius", 9.0))
	f.position = at
	var look: Dictionary = look_of_scene("res://scene/enemy/%s.tscn" % scene_id)
	f.sprite = AnimatedSprite2D.new()
	f.sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	f.sprite.sprite_frames = look.get("frames") as SpriteFrames
	f.sprite.material = look.get("material") as Material
	f.sprite.self_modulate = look.get("modulate", Color.WHITE)
	f.sprite.offset = look.get("offset", Vector2.ZERO)
	f.sprite.scale = look.get("scale", Vector2.ONE)
	f.add_child(f.sprite)
	var walk: String = str(look.get("walk", ""))
	if walk != "":
		f.sprite.play(walk)
	foes.add_child(f)
	return f


func _move_foes(delta: float) -> void:
	var r: int = rank()
	var colour: Color = Element.colour_for(land())
	for foe in foes.get_children():
		var f := foe as Foe
		if f == null:
			continue
		if f.dying >= 0.0:
			f.dying -= delta
			f.modulate.a = clampf(f.dying / 0.25, 0.0, 1.0)
			f.scale = Vector2.ONE * (1.0 + (0.25 - f.dying) * 1.2)
			if f.dying <= 0.0:
				_gone(f)
			continue
		f.age += delta
		f.flash = maxf(0.0, f.flash - delta)
		f.modulate = Color(2.2, 2.2, 2.2) if f.flash > 0.0 else Color.WHITE
		match f.kind:
			"sprite":
				if f.path == "arc":
					# In from a side, bending back out the way it came.
					f.velocity.x += f.side * ARC_TURN * delta
				if f.path == "snake":
					f.position.y += f.velocity.y * delta
					f.position.x = f.anchor.x + sin(f.age * 2.2 + f.phase) * f.side
				elif f.path == "ring":
					f.anchor.y += f.velocity.y * delta
					var turn: float = f.phase + f.age * 1.4
					f.position = f.anchor + Vector2(cos(turn), sin(turn)) * 52.0
				else:
					f.position += f.velocity * delta
				f.shoot_in -= delta
				if f.shoot_in <= 0.0 and f.position.y > -HALF.y + 10.0 and f.position.y < HALF.y - 120.0:
					f.shoot_in = fire_gap(2.6, r)
					_aimed(f.position, colour, bullet_speed(r))
			"slime":
				f.position.y += f.velocity.y * delta
				f.position.x += sin(f.age * 2.2 + f.side) * 22.0 * delta
			"mage", "sniper":
				if not f.leaving and f.position.y < f.stop_y:
					f.position.y = minf(f.stop_y, f.position.y + f.velocity.y * delta)
				elif f.leaving:
					f.position.y += 90.0 * delta
				else:
					f.shoot_in -= delta
					if f.shoot_in <= 0.0:
						if f.kind == "mage":
							_fan(f.position, colour, 5 + r / 3, 0.7, bullet_speed(r) * 0.9)
							f.shoot_in = fire_gap(1.8, r)
						else:
							_aimed(f.position, colour, bullet_speed(r) * 1.6)
							f.shoot_in = fire_gap(1.1, r)
						f.casts_left -= 1
						if f.casts_left <= 0:
							f.leaving = true
			"boss":
				pass
		if f.kind != "boss":
			if f.position.distance_to(healer.position + HITBOX_AT) < f.radius + BODY - 2.0:
				hurt()
				if f.kind == "sprite":
					_kill(f)
			if f.position.y > HALF.y + 40.0 or absf(f.position.x) > HALF.x + 120.0:
				_gone(f)


static func _gone(node: Node) -> void:
	"""Out of the run at once - off its parent this frame, freed after - so
	nothing later in the same step counts it again."""
	var parent: Node = node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()


func _aimed(from: Vector2, colour: Color, speed: float) -> void:
	var aim: float = ((healer.position + HITBOX_AT) - from).angle()
	field.spawn(from, aim, speed, colour)


func _fan(from: Vector2, colour: Color, count: int, spread: float, speed: float) -> void:
	var aim: float = ((healer.position + HITBOX_AT) - from).angle()
	for k in count:
		var share: float = 0.0 if count == 1 else float(k) / float(count - 1) - 0.5
		field.spawn(from, aim + share * spread, speed, colour, k == count / 2)


# =============================================================================
# HITS FELT
# =============================================================================

static var _materials: Dictionary = {}


static func _glow_material(added: bool = false) -> CanvasItemMaterial:
	"""Unshaded (the crypt's dark does not dim it); added light for bursts."""
	if not _materials.has(added):
		var glow := CanvasItemMaterial.new()
		glow.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		if added:
			glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_materials[added] = glow
	return _materials[added]


func shake_by(amount: float) -> void:
	"""The screen shakes this hard (px), or harder if it already is."""
	shake = minf(SHAKE_MOST, maxf(shake, amount))


func _burst(at: Vector2, colour: Color, reach: float, sparks: int, life: float, ring: bool = true) -> Burst:
	var b := Burst.new()
	b.colour = colour
	b.reach = reach
	b.sparks = sparks
	b.life = life
	b.most = life
	b.ring = ring
	b.turn = _fx_rng.randf() * TAU
	b.position = at
	b.z_index = BURST_Z
	b.material = _glow_material(true)
	add_child(b)
	return b


func _ring_out(colour: Color) -> void:
	"""A power-up, a potion or a meteor taken: a ring out from her, and she shines."""
	_burst(healer.position + HITBOX_AT, colour, 30.0, 6, 0.35)
	_shine_left = 0.15


func _feel(delta: float) -> void:
	"""The look of the hits: the shake settling, her shine and her frost."""
	_boss_shook = maxf(0.0, _boss_shook - delta)
	_spark_in = maxf(0.0, _spark_in - delta)
	_shine_left = maxf(0.0, _shine_left - delta)
	shake = maxf(0.0, shake - SHAKE_FADE * delta)
	if shake > 0.05:
		position = (_home + Vector2(_fx_rng.randf_range(-1.0, 1.0), _fx_rng.randf_range(-1.0, 1.0)) * shake).round()
	else:
		position = _home
	if healer_sprite.sprite_frames == null:
		return
	if frozen > 0.0:
		healer_sprite.modulate = ICE_TINT
		if healer_sprite.is_playing():
			healer_sprite.pause()
	else:
		healer_sprite.modulate = Color(2.0, 2.0, 2.0) if _shine_left > 0.0 else Color.WHITE
		if not healer_sprite.is_playing():
			healer_sprite.play()


func _take_hits() -> void:
	"""What reached her this frame: a freezing shot freezes her (once, then
	FROST_PROOF to break free); anything else is a life."""
	var harm: bool = false
	var chill: bool = false
	for hit in field.hits:
		if hit.x == FREEZE_MARK:
			chill = true
		else:
			harm = true
	if harm:
		hurt()
	elif chill and frozen <= 0.0 and _frost_proof <= 0.0:
		freeze()


func freeze() -> void:
	frozen = FREEZE_SECONDS
	_frost_proof = FREEZE_SECONDS + FROST_PROOF
	_say("Frozen")
	_burst(healer.position + HITBOX_AT, Color(0.7, 0.95, 1.0), 26.0, 8, 0.4)


func _hazards_step(delta: float) -> void:
	"""Light's pillars burning down and earth's rocks landing, then drawn."""
	var her: Vector2 = healer.position + HITBOX_AT
	var still: Array = []
	for p in _pillars:
		if float(p["warn"]) > 0.0:
			p["warn"] = float(p["warn"]) - delta
		else:
			p["burn"] = float(p["burn"]) - delta
			if absf(her.x - float(p["x"])) <= PILLAR_HALF + HITBOX:
				hurt()
			if float(p["burn"]) <= 0.0:
				continue
		still.append(p)
	_pillars = still
	still = []
	for rock in _rocks:
		rock["warn"] = float(rock["warn"]) - delta
		if float(rock["warn"]) > 0.0:
			still.append(rock)
		else:
			_land_rock(rock["at"], rock["colour"])
	_rocks = still
	hazards.clock += delta
	hazards.pillars = _pillars
	hazards.rocks = _rocks
	hazards.gust = gust
	hazards.gust_side = gust_side
	hazards.queue_redraw()


func _land_rock(at: Vector2, colour: Color) -> void:
	if (healer.position + HITBOX_AT).distance_to(at) <= ROCK_REACH:
		hurt()
	for k in 10:
		field.spawn(at, TAU * k / 10.0 + 0.2, bullet_speed(rank()) * 0.55, colour)
	_burst(at, Color(0.85, 0.65, 0.4), 30.0, 10, 0.4)
	shake_by(ROCK_SHAKE)


func _signature(from: Vector2, r: int, colour: Color) -> float:
	"""One volley of this land's boss's own cast (SIGNATURES); answers the
	wait before the next, before the boss's pace."""
	var her: Vector2 = healer.position + HITBOX_AT
	var speed: float = bullet_speed(r)
	var element: int = land()
	if element == Element.Type.FIRE:
		# FIRE RAIN: fireballs from above, and an ember that lies burning.
		for k in 3 + tier:
			var x: float = _rng.randf_range(-PATH_HALF + 12.0, PATH_HALF - 12.0)
			field.spawn(Vector2(x, -HALF.y - 6.0), PI / 2.0 + _rng.randf_range(-0.15, 0.15),
				speed * _rng.randf_range(0.8, 1.1), Color(1.0, 0.5, 0.15), true)
		field.spawn_settling(Vector2(_rng.randf_range(-PATH_HALF + 20.0, PATH_HALF - 20.0), -HALF.y - 6.0),
			PI / 2.0, speed * 0.9, Color(1.0, 0.35, 0.1), _rng.randf_range(140.0, 300.0), 1.8, 0, 0, true)
		return 0.4
	if element == Element.Type.ICE:
		# FROST VOLLEY: a fan of freezing shots at her, a ring of shards between.
		var aim: float = (her - from).angle()
		var count: int = 5 + tier
		for k in count:
			var share: float = float(k) / float(count - 1) - 0.5
			field.spawn(from, aim + share * 0.8, speed * 0.85, Color(0.7, 0.95, 1.0), true, 0.0, 0.0, 14.0,
				FREEZE_MARK)
		if _boss_fired % 2 == 1:
			for k in 10:
				field.spawn(from, TAU * k / 10.0 + 0.3, speed * 0.6, colour)
		return 0.7
	if element == Element.Type.WIND:
		# GALE: the gust shoves her, and crosswinds blow with it.
		if _boss_fired == 0:
			gust_side = -1.0 if _rng.randf() < 0.5 else 1.0
			gust = GUST_SECONDS
		for k in 3 + tier:
			var y: float = _rng.randf_range(-HALF.y + 40.0, HALF.y - 60.0)
			field.spawn(Vector2(-gust_side * (PATH_HALF - 4.0), y), 0.0 if gust_side > 0.0 else PI, speed * 0.9,
				Color(0.8, 1.0, 0.9))
		return 0.38
	if element == Element.Type.WATER:
		# TIDE: a row of weaving drops across the path, a way through each.
		var gap_at: float = _rng.randf_range(-PATH_HALF + 60.0, PATH_HALF - 60.0)
		var x: float = -PATH_HALF + 10.0
		while x < PATH_HALF - 4.0:
			if absf(x - gap_at) > 46.0:
				field.spawn_swaying(Vector2(x, -HALF.y + 2.0), PI / 2.0, speed * 0.55, Color(0.45, 0.75, 1.0),
					12.0, 0.0, 4.0, x * 0.04)
			x += 24.0
		return 1.0
	if element == Element.Type.EARTH:
		# ROCKFALL: rocks marked on the floor - the first where she stands.
		for k in 2 + tier:
			var at: Vector2 = her if k == 0 else Vector2(_rng.randf_range(-PATH_HALF + 30.0, PATH_HALF - 30.0),
				_rng.randf_range(-HALF.y + 120.0, HALF.y - 30.0))
			_rocks.append({"at": at, "warn": ROCK_WARN + 0.12 * k, "colour": colour})
		return 1.2
	if element == Element.Type.LIGHT:
		# PILLARS OF LIGHT: columns marked, then burning down the path - one on her.
		var xs: Array = [clampf(her.x, -PATH_HALF + 10.0, PATH_HALF - 10.0)]
		var tries: int = 0
		while xs.size() < 2 + tier and tries < 40:
			tries += 1
			var x: float = _rng.randf_range(-PATH_HALF + 16.0, PATH_HALF - 16.0)
			var clear: bool = true
			for other in xs:
				clear = clear and absf(x - float(other)) > 48.0
			if clear:
				xs.append(x)
		for x in xs:
			_pillars.append({"x": x, "warn": PILLAR_WARN, "burn": PILLAR_BURN})
		_fan(from, colour, 5, 0.6, speed * 0.8)
		return 1.1
	# DARK COILS: orbs curling in, each volley the other way.
	var turn: float = 0.9 if _boss_fired % 2 == 0 else -0.9
	for k in 6:
		field.spawn(from, TAU * k / 6.0 + _boss_fired * 0.2, speed * 0.7, Color(0.65, 0.4, 0.95), true, turn)
	return 0.35


# =============================================================================
# THE BOSS AND THE GOAL
# =============================================================================

func _start_boss() -> void:
	state = State.BOSS
	wave_in_tier = WAVES_PER_TIER - 1
	banner = "The gate - and its keeper" if tier >= TIERS - 1 else "The %s keeper" % land_name(land())
	banner_left = BANNER_SECONDS
	_wave += 1
	boss = _foe("boss", Vector2(0.0, -HALF.y - 60.0))
	enraged = false
	# A METEOR AT THE GATE, falling ahead of her: Space calls it on the boss.
	_drop("meteor", Vector2(clampf(healer.position.x, -PATH_HALF + 30.0, PATH_HALF - 30.0), -HALF.y + 50.0))
	_boss_cast = 2.5
	_boss_casting = -1
	_boss_casts = 0
	_boss_adds_in = adds_gap()


func adds_gap() -> float:
	"""How often this tier's boss calls a wave: less often before the last."""
	return BOSS_ADDS_SECONDS + ADDS_PER_TIER * (TIERS - 1 - mini(tier, TIERS - 1))


func _boss_step(delta: float) -> void:
	if boss == null or not is_instance_valid(boss) or boss.dying >= 0.0:
		return
	var home := Vector2(sin(boss.age * 0.6) * 140.0, -HALF.y + 70.0)
	boss.position = boss.position.move_toward(home, 60.0 * delta)
	var r: int = rank()
	var colour: Color = Element.colour_for(land())
	# ITS CALL: every BOSS_ADDS_SECONDS a half-size wave to its side.
	_boss_adds_in -= delta
	if _boss_adds_in <= 0.0:
		_boss_adds_in = adds_gap() * (ENRAGE_PACE if enraged else 1.0)
		spawn_wave(str(BOSS_ADDS[_rng.randi_range(0, BOSS_ADDS.size() - 1)]), 0.5)
	if not enraged and boss_share() < ENRAGE_AT:
		enraged = true
		banner = "The keeper is enraged"
		banner_left = BANNER_SECONDS
	var pace: float = ENRAGE_PACE if enraged else 1.0
	_boss_cast -= delta
	if _boss_casting < 0 and _boss_cast <= 0.0:
		# EVERY OTHER CAST IS THE LAND'S OWN, the first of them first.
		_boss_casting = SIGNATURE if _boss_casts % 2 == 0 else _rng.randi_range(0, 3)
		_boss_casts += 1
		_boss_shots = 0.0
		_boss_fired = 0
		if _boss_casting == SIGNATURE:
			_say(str(SIGNATURES.get(land(), "")))
	if _boss_casting < 0:
		return
	_boss_shots -= delta
	if _boss_shots > 0.0:
		return
	var from: Vector2 = boss.position + Vector2(0.0, -12.0)
	match _boss_casting:
		0:
			var n: int = 16 + 2 * r + (8 if enraged else 0)
			var turn: float = (PI / n) * float(_boss_fired % 2)
			for k in n:
				field.spawn(from, turn + TAU * k / n, bullet_speed(r) * 0.7, colour)
			_boss_shots = 0.7 * pace
		1:
			_fan(from, colour, 7 + r / 2 + (2 if enraged else 0), 0.9, bullet_speed(r))
			_boss_shots = 0.5 * pace
		2:
			var gap_at: float = _rng.randf_range(-PATH_HALF + 40.0, PATH_HALF - 100.0)
			var x: float = -PATH_HALF + 6.0
			while x < PATH_HALF:
				if x < gap_at or x > gap_at + 64.0:
					field.spawn(Vector2(x, -HALF.y + 4.0), PI / 2.0, bullet_speed(r) * 0.6, colour)
				x += 20.0
			_boss_shots = 1.0 * pace
		3:
			for k in 4:
				field.spawn(from, _boss_fired * 0.23 + TAU * k / 4.0, bullet_speed(r) * 0.75, colour)
			_boss_shots = 0.07
		SIGNATURE:
			_boss_shots = _signature(from, r, colour) * pace
	_boss_fired += 1
	var volleys: int = int(SIGNATURE_VOLLEYS.get(land(), 3)) if _boss_casting == SIGNATURE \
		else int([3, 5, 3, 40][_boss_casting])
	if _boss_fired >= volleys:
		_boss_casting = -1
		_boss_cast = 1.4 * pace


func boss_share() -> float:
	if boss == null or not is_instance_valid(boss):
		return 0.0
	return clampf(boss.health / boss.most, 0.0, 1.0)


func _boss_down() -> void:
	bosses_beaten += 1
	field.clear()
	_pillars.clear()
	_rocks.clear()
	gust = 0.0
	frozen = 0.0
	# IT GOES WITH A BANG, and every monster on screen with it (counted, no drops).
	var at := Vector2(0.0, -HALF.y + 70.0)
	if boss != null and is_instance_valid(boss):
		at = boss.position + Vector2(0.0, -12.0)
	var colour: Color = Element.colour_for(land()).lightened(0.3)
	shake_by(BOSS_DOWN_SHAKE)
	_burst(at, colour, 84.0, 18, 0.8)
	_burst(at, Color(1.0, 1.0, 1.0), 44.0, 10, 0.5)
	for foe in foes.get_children():
		var f := foe as Foe
		if f == null or f == boss or f.dying >= 0.0:
			continue
		f.dying = 0.25
		slain += 1
		_burst(f.position + Vector2(0.0, -8.0), colour, 16.0, 7, 0.28)
	if bosses_beaten < TIERS:
		# THE NEXT TIER: the boss's spoils, then the next land, hotter.
		_drop("power", at + Vector2(-16.0, 16.0))
		_drop("potion", at + Vector2(16.0, 16.0))
		state = State.RUNNING
		boss = null
		enraged = false
		tier += 1
		wave_in_tier = 0
		banner = tier_banner()
		banner_left = BANNER_SECONDS
		_between = run_seconds + BANNER_SECONDS
		return
	state = State.GOAL
	banner = "The way is open"
	banner_left = BANNER_SECONDS
	# THE GOAL MARKER, laid ahead on the path: two pillars, the gold arrow
	# over the way between them, and what reaching it is worth.
	goal = Node2D.new()
	goal.name = "goal"
	goal.position = Vector2(0.0, -terrain.position.y - HALF.y - 40.0)
	for x in [-36.0, 36.0]:
		var pillar := (load("res://scene/crypt/pillar.tscn") as PackedScene).instantiate() as Node2D
		pillar.position = Vector2(x, 0.0)
		goal.add_child(pillar)
	var arrow: Node2D = (load("res://src/shared/beckonarrow.gd") as GDScript).call("make", Vector2(0.0, -22.0))
	goal.add_child(arrow)
	var goal_sign := Label.new()
	goal_sign.text = "GOAL - %d gold" % int(pays.get("most", DEFAULT_PAYS["most"]))
	goal_sign.add_theme_font_size_override("font_size", 10)
	goal_sign.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	goal_sign.add_theme_color_override("font_outline_color", Color.BLACK)
	goal_sign.add_theme_constant_override("outline_size", 3)
	goal_sign.position = Vector2(-44.0, -52.0)
	goal.add_child(goal_sign)
	props.add_child(goal)


func _finish(won: bool) -> void:
	_fell_in = state
	state = State.WON if won else State.LOST
	shake = 0.0
	position = _home
	field.clear()
	_shot_pos.resize(0)
	_shot_vel.resize(0)
	_shot_mesh.visible_instance_count = 0
	banner = ""
	finished.emit(won)


func result_text() -> String:
	if state == State.WON:
		return "Cleared in %s - %d slain" % [time_text(), slain]
	if _fell_in == State.GOAL:
		return "Fell at the gate after %s - %d slain" % [time_text(), slain]
	if _fell_in == State.BOSS:
		return "Fell to the %s keeper in tier %d, after %s - %d slain" % [land_name(land()), tier + 1,
			time_text(), slain]
	return "Fell in tier %d, wave %d, after %s - %d slain" % [tier + 1, wave_in_tier + 1, time_text(), slain]


func goal_reached() -> bool:
	return state == State.WON


# =============================================================================
# THE PATH, LAID AHEAD AS IT COMES
# =============================================================================

func _lay_terrain() -> void:
	var top: float = -terrain.position.y - HALF.y - 64.0
	var bottom: float = -terrain.position.y + HALF.y + 64.0
	# The floor, a row of tiles at a time.
	var want_top: int = floori(top / TILE)
	while _painted_top > want_top:
		_painted_top -= 1
		for c in range(-int(PATH_HALF) / TILE, int(PATH_HALF) / TILE):
			floor_layer.set_cell(Vector2i(c, _painted_top), 1, Vector2i(_rng.randi_range(1, 4), _rng.randi_range(1, 3)))
	var want_bottom: int = floori(bottom / TILE)
	while _painted_bottom > want_bottom:
		for c in range(-int(PATH_HALF) / TILE, int(PATH_HALF) / TILE):
			floor_layer.erase_cell(Vector2i(c, _painted_bottom))
		_painted_bottom -= 1
	if _painted_bottom < _painted_top:
		_painted_bottom = _painted_top
	# The side walls, a piece every WALL_STEP.
	var wall_want: int = floori(top / WALL_STEP)
	while _wall_top > wall_want:
		_wall_top -= 1
		for x in [-PATH_HALF - 4.5, PATH_HALF + 4.5]:
			var piece := (load(WALL_PIECE) as PackedScene).instantiate() as Node2D
			piece.position = Vector2(x, float(_wall_top) * WALL_STEP)
			piece.set_meta(&"wall", true)
			props.add_child(piece)
	# A section ahead every SECTION_LENGTH.
	while _section_top > top:
		_section_top -= SECTION_LENGTH
		_lay_section(_section_top)
	# What has gone by.
	for piece in props.get_children():
		if piece != goal and (piece as Node2D).position.y > bottom + 40.0:
			_gone(piece)
	var kept: Array = []
	for o in _obstacles:
		if (o["rect"] as Rect2).position.y < bottom + 40.0:
			kept.append(o)
	_obstacles = kept


func _lay_landing() -> void:
	"""Where she starts, standing: the crypt's wall behind her across the
	path, a candelabra either side. It scrolls away once the run starts."""
	var foot: float = HALF.y + 4.0
	var x: float = -PATH_HALF - 4.5
	for width in LANDING_WIDTHS:
		_prop(str(LANDING_PIECES[int(width)]), Vector2(x + float(width) / 2.0, foot))
		x += float(width)
	_obstacles.append({"rect": Rect2(-PATH_HALF, foot - 12.0, PATH_HALF * 2.0, 12.0),
		"art": Rect2(-PATH_HALF, foot - 28.0, PATH_HALF * 2.0, 28.0)})
	for side in [-1.0, 1.0]:
		_prop("res://scene/crypt/candelabra.tscn", Vector2(side * 64.0, HALF.y - 34.0))


func _lay_section(at_y: float) -> void:
	"""A piece of the dungeon from at_y up SECTION_LENGTH: decoration always,
	and - past the start - one of the shapes that change how the path plays."""
	for i in _rng.randi_range(1, 3):
		var decor: Array = ["res://scene/crypt/candelabra.tscn", "res://scene/crypt/skullpile.tscn",
			"res://scene/crypt/bones.tscn", "res://scene/crypt/rubble2.tscn", "res://scene/crypt/rubble4.tscn"]
		var path: String = str(decor[_rng.randi_range(0, decor.size() - 1)])
		var x: float = (PATH_HALF - 18.0) * (-1.0 if _rng.randf() < 0.5 else 1.0)
		if path.ends_with("bones.tscn") or path.contains("rubble"):
			x = _rng.randf_range(-PATH_HALF + 20.0, PATH_HALF - 20.0)
		_prop(path, Vector2(x, at_y + _rng.randf_range(20.0, SECTION_LENGTH - 20.0)))
	# Nothing in the way at the start, nor at the gate: the boss is enough.
	if at_y > -CLEAR_START or state == State.BOSS or state == State.GOAL:
		return
	match _rng.randi_range(0, 3):
		0:
			pass  # a hall: nothing in the way
		1:
			# A row of pillars, gaps between.
			var y: float = at_y + SECTION_LENGTH * 0.5
			var x: float = -PATH_HALF + _rng.randf_range(50.0, 90.0)
			while x < PATH_HALF - 40.0:
				_pillar(Vector2(x, y))
				x += _rng.randf_range(90.0, 130.0)
		2:
			# A colonnade: pillars down both sides of the middle.
			var y: float = at_y + 40.0
			while y < at_y + SECTION_LENGTH - 30.0:
				_pillar(Vector2(-110.0, y))
				_pillar(Vector2(110.0, y))
				y += 80.0
		3:
			# A crossing: a wall of pillars with one way through.
			var y: float = at_y + SECTION_LENGTH * 0.5
			var gap: float = _rng.randf_range(-PATH_HALF + 70.0, PATH_HALF - 70.0)
			var x: float = -PATH_HALF + 12.0
			while x < PATH_HALF - 8.0:
				if absf(x - gap) > 48.0:
					_pillar(Vector2(x, y))
				x += 24.0


func _prop(path: String, at: Vector2) -> Node2D:
	if not ResourceLoader.exists(path):
		return null
	var piece := (load(path) as PackedScene).instantiate() as Node2D
	piece.position = at
	props.add_child(piece)
	return piece


func _pillar(at: Vector2) -> void:
	_prop("res://scene/crypt/pillar.tscn", at)
	# Its foot (pillar.tscn's body) stops her; its whole picture stops a shot.
	_obstacles.append({"rect": Rect2(at + Vector2(-8.5, -12.0), Vector2(17.0, 12.0)),
		"art": Rect2(at + Vector2(-8.5, -30.0), Vector2(17.0, 30.0))})


func obstacle_count() -> int:
	return _obstacles.size()


# =============================================================================
# PICTURES OF THE GAME'S OWN
# =============================================================================

static func look_of_scene(path: String, instance: bool = true) -> Dictionary:
	"""{frames, material, modulate, offset, scale, walk} of the first
	AnimatedSprite2D in the scene at `path`, read from an instance that is never
	added (its scripts' _ready never run), its element's recolour as the world
	draws it (BaseEnemy.element_material). {} when there is none."""
	if _looks.has(path):
		return _looks[path]
	var out: Dictionary = {}
	var packed: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else null
	if packed != null and not instance:
		# A player's scene is read, never made: none of its scripts run.
		var state_of: SceneState = packed.get_state()
		for n in state_of.get_node_count():
			if state_of.get_node_type(n) != &"AnimatedSprite2D":
				continue
			out = {"frames": null, "offset": Vector2.ZERO, "scale": Vector2.ONE, "walk": "walkup",
				"modulate": Color.WHITE, "material": null}
			for p in state_of.get_node_property_count(n):
				match state_of.get_node_property_name(n, p):
					&"sprite_frames":
						out["frames"] = state_of.get_node_property_value(n, p)
					&"offset":
						out["offset"] = state_of.get_node_property_value(n, p)
					&"scale":
						out["scale"] = state_of.get_node_property_value(n, p)
			break
		_looks[path] = out
		return out
	if packed != null:
		var node: Node = packed.instantiate()
		var sprite: AnimatedSprite2D = null
		for child in node.get_children():
			if child is AnimatedSprite2D:
				sprite = child
				break
		if sprite != null and sprite.sprite_frames != null:
			var frames: SpriteFrames = sprite.sprite_frames
			var walk: String = ""
			for wanted in ["walkdown", "idledown", "walkup"]:
				if frames.has_animation(wanted) and frames.get_frame_count(wanted) > 0:
					walk = wanted
					break
			out = {"frames": frames, "offset": sprite.offset, "scale": sprite.scale * ((node as Node2D).scale
				if node is Node2D else Vector2.ONE), "walk": walk, "modulate": Color.WHITE, "material": null}
			var data: Variant = node.get("enemy_data")
			if data is EnemyData:
				var element: int = int((data as EnemyData).element)
				var override: Variant = node.get("element_override")
				if override is int and int(override) >= 0:
					element = int(override)
				var recolour: bool = (data as EnemyData).recolour_to_element or (override is int and int(override) >= 0)
				if recolour and element != Element.Type.NONE:
					out["material"] = BaseEnemy.element_material(data, element)
				out["modulate"] = (data as EnemyData).body_tint
		node.free()
	_looks[path] = out
	return out
