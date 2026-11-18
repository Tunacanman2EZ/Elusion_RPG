# crownfallrun.gd - CROWNFALL's play (0.162.0): a brick breaker through the
# seven monster kingdoms (crownfallmaps.gd has the story and the maps).
#
# The owner: "draw out a brick breaker let me see a video", then "improve the
# game ui majorly and make the bricks more structural brick breaker games were
# known for bonuses and complex maps", then the story and "a ton of new maps".
# Two sketches came first (zz/brickpic.gd, zz/brickpic2.gd); this is the game.
#
# WHAT IS ON SCREEN, all drawn here in code at VIEW (1280 x 720) - the screen
# (crownfallscreen.gd) shows it in a SubViewport, scaled:
#   - the arena (ARENA), its stone frame, and in it the map: bricks set in the
#     stone of the place they belong to, so a hole reads as a hole in a wall;
#   - the paddle, glowing so its ends show from the corner of the eye;
#   - TRACERS - bright streaks along a faint line (the owner kept the idea for
#     this game): the aim before a launch, each ball's own path, the laser;
#   - the top bar (kingdom, map, score, the run's gold, the combo meter,
#     lives), the left panel (bonuses on, and what can fall), the right panel
#     (how much is broken, the kingdom's five maps);
#   - between runs, the kingdom map (State.KINGDOMS): seven kingdoms, the made
#     one's maps to pick from.
#
# THE RULES:
#   - The paddle follows `target_x` (the mouse, keys or a finger, set by the
#     screen). A ball waits on it, aimed, until launch().
#   - A map is cleared when every brick that can break is broken - blight
#     included, which grows back (BLIGHT_EVERY). A citadel is cleared when
#     its ruler falls. Cleared, the next map comes; the run's gold is the sum
#     of what each map cleared pays (`pays`, the server's table, handed in at
#     Go), and the server pays it at Leave.
#   - Every ball lost is a life (LIVES); with none left the run is over.
#   - Bonuses fall from ? bricks and every BONUS_EVERY bricks: the paddle
#     catches them (BONUS, BONUS_ORDER).
#   - A citadel's ruler (the kingdom's monster, from its own art, recoloured
#     by its land) walks its hall, takes the ball's
#     hits, and throws at the paddle: a hit stuns it for STUN_SECONDS.
# No class_name; the screen preloads it.
extends Node2D

const Maps := preload("res://src/world/crownfall/crownfallmaps.gd")
const Boss := preload("res://src/world/crownfall/crownfallboss.gd")

signal map_cleared(index: int)
signal life_lost
signal run_over
signal said(text: String)

enum State { KINGDOMS, AIM, PLAY, CLEARED, OVER }

const VIEW := Vector2(1280, 720)
const ARENA := Rect2(160, 86, 960, 620)
# THE GRID (the owner: "make the maps bigger", "dense maps with designs in
# the bricks"): Maps.COLS (32) bricks of CW x CH across the arena's 960, up
# to Maps.ROWS_MOST (18) rows, the first at MAP_TOP.
const CW := 30.0
const CH := 15.0
const MAP_TOP := 112.0
const ROW_GAP := 2.0
const PADDLE_Y := 662.0
const PADDLE_W := 140.0
const PADDLE_WIDE := 230.0
const PADDLE_SPEED := 1700.0
const SHIELD_Y := 694.0
const BALL_R := 6.0
const SPEED := 560.0
const SLOW_SHARE := 0.62
const MOST_BALLS := 6
# THE BRICKS DRAW ONCE (0.166.1, the owner: "fireball and multiball make the
# map lag", "the layer of effects made it lag"). Every brick was drawn again
# every frame - 4 to 13 ms of a 16.7 ms frame here, the frost, ice and dark
# coats with them - though most look the same from one frame to the next.
# Now each brick is a picture of its own (a Node2D in `brick_layer`), drawn
# again only when its look changes (_brick_look()): struck, burning, warded,
# glowing, frozen or coated, fading in the dark, or a kind that is always
# moving (all but STILL_KINDS). The floor under them (the arena, the tide,
# the ice, the gusts, the rails, the dark) is a layer of its own drawn every
# frame (`floor_layer`); both sit behind the run's own drawing, which is
# everything above the bricks as before. The helpers both share draw on
# `_cv`, the picture being drawn.
# THE STILL BRICKS ARE ONE PICTURE (0.166.2, the owner: "my computer is
# running a little hard playing this i can tell because my fan kicks up"):
# a brick's picture was still a draw of its own every frame - a thousand of
# them on Gilded Gate, most of the frame's work. Now the still ones are drawn
# into `brick_cache` (a SubViewport) only when one of them changes, and the
# run shows that one picture (`brick_pic`). A brick drawn every look - struck,
# burning, shielded, glowing, a lively kind, one that moves - shows its twin
# in `brick_live` over it instead, its place in the picture left empty. The
# order of the picture's bricks never changes, so it looks as it did.
const STILL_KINDS := {"basalt": 1, "boulder": 1, "bumper": 1, "column": 1, "crystal": 1, "drift": 1, "guard": 1, "iron": 1,
	"keg": 1, "key": 1, "land": 1, "lock": 1, "obsidian": 1, "packed": 1, "prism": 1, "sand": 1, "shell": 1, "stone": 1,
	"wood": 1}
const LAND_NO := {"light": 1, "wind": 2, "water": 3, "ice": 4, "earth": 5, "fire": 6, "dark": 7}
# SPARKS: PARTS_MOST alive at most, the oldest let go once a frame; with the
# air half full (a Fireball through a crowd) a burst throws a third as many.
const PARTS_MOST := 350
# THE LAST FEW (the same 0.166.1, the owner: "the last few bricks are hard
# to destroy"): with LAST_FEW or fewer left to break, they glow and every
# ball bends toward the nearest; with none broken for STUCK_SECONDS the balls
# bend too, STUCK_TURN degrees a second (the Wind orb's way, gentler).
# THE FINAL FIREBALL (0.166.4, the owner: "the ball is not locking on sharp
# enough and it becomes to hard to hit that 1 square maybe the final tiles we
# make the ball turn into a fireball"): in the last few every ball in flight
# is a final fireball (final_fire) - through every brick, iron and mirrors
# and shut ones alike, breaking at a touch whatever can break, Guards or no -
# and it locks on: LAST_TURN degrees a second, LAST_TURN_ONE with one or two
# left, and close by never a wider turn than half the way to its brick, so
# it homes in and does not circle (up to LAST_TURN_MOST). Still a bend: the
# ball is seen to travel.
# On a boss's map (0.166.5) the last few are its health: LAST_FEW or fewer
# left to win (to_win()), and the boss is among what they lock on to - and
# cornered (crownfallboss.gd): no dive, no bubble, no ward turns them away.
const LAST_FEW := 5
const STUCK_SECONDS := 12.0
const STUCK_TURN := 50.0
const LAST_TURN := 220.0
const LAST_TURN_ONE := 360.0
const LAST_TURN_MOST := 1440.0
const LIVES := 3
const CLEARED_SECONDS := 2.6
const BLIGHT_EVERY := 9.0
const BLIGHT_MOST := 6
# A bonus every BONUS_EVERY bricks (the maps hold hundreds now), at most
# CAPS_MOST falling at once - a ? brick always drops one, the cap aside.
const BONUS_EVERY := 30
const CAPS_MOST := 3
# A reaction says its name at most every REACT_WORD_GAP seconds; a clash says
# nothing (the owner's pictures: words piled up).
const REACT_WORD_GAP := 0.3
const CAPSULE_FALL := 175.0
const LASER_EVERY := 0.28
const STUN_SECONDS := 0.8
const MIRROR_BEND := 22.0
const STEEPEST_FLAT := 0.28
const AIM_SWAY := 50.0
# The owner (0.166.0): "it sways left and right to fast" - half what it was.
const AIM_SWAY_SPEED := 0.8
# A tracer's bright streaks run along it this fast (px a second), one every
# TRACER_SPACING; the owner, the same day: "the tracer is too fast also"
# (they ran at 1,500).
const TRACER_SPEED := 500.0
const TRACER_SPACING := 170.0
const WORD_TRIES := 8
# The kingdom map's panel: the picked kingdom's maps, five stretches of five,
# each stretch ending in its boss. THE MAP SCREEN, NEATER (0.168.6): the
# owner, "we need to improve this screen". The panel moved left and the
# picked map's card (MAP_CARD) took the empty right, Start inside it (the
# screen's START_BOX); the map's words had sat in small type under the
# panel, the last line off the foot of the screen. The rows' "1 - 5" went,
# each map is a picture of itself (TILE, below), the next map to clear says
# NEXT and a boss says BOSS; each kingdom shows how far you are, a lock until
# you reach it, and the one shown is lit.
const MAP_PANEL := Rect2(150, 368, 600, 286)
const MAP_CARD := Rect2(780, 368, 350, 286)
const NODE_GAP := Vector2(100, 47)
# THE MAPS' PICTURES (0.168.6, the same day): the owner, "we need to add
# icons on them of the maps". Each map is a picture in bricks, so each node is
# a TILE of the map itself - a pixel a brick, in the bricks' own colours
# (_colour_of()), from THUMB_KIND: what each letter of a map makes (the
# letters as _load() reads them; the suite fails on a letter missing here).
# Drawn once a map and kept (map_picture()).
const TILE := Vector2(64, 36)
const THUMB_KIND := {"H": ["heart", "light"], "S": ["stone", ""], "I": ["iron", ""], "M": ["mirror", "light"],
	"T": ["tnt", "fire"], "?": ["bonus", "light"], "B": ["blight", ""], "C": ["crystal", "ice"], "U": ["bumper", "light"],
	"O": ["portal", "dark"], "K": ["key", "light"], "L": ["lock", ""], "G": ["gold", "light"], "N": ["rune", "light"],
	"Z": ["shell", ""], "X": ["prism", "light"], "D": ["guard", "light"], "W": ["whirl", "wind"], "Y": ["mimic", ""],
	"u": ["buoy", "water"], "o": ["bubble", "water"], "Q": ["clam", "water"], "F": ["land", "ice"], "P": ["packed", "ice"],
	"s": ["drift", "ice"], "V": ["icicle", "ice"], "A": ["foot", "earth"], "E": ["column", "earth"], "g": ["ore", "earth"],
	"n": ["sand", "earth"], "h": ["wood", "fire"], "z": ["fuse", "fire"], "J": ["keg", "fire"], "q": ["obsidian", "fire"],
	"r": ["lava", "fire"], "t": ["lantern", "light"], "m": ["shadow", "dark"], "v": ["void", "dark"], "b": ["boulder", "earth"],
	"p": ["plague", ""], "<": ["land", "light"], "k": ["land", "wind"]}
static var _pictures: Dictionary = {}
# THE RULERS ON THE CRESTS (the same 0.168.6): the owner, "we need to add
# icons here now maybe of the bosses". Each kingdom's crest shows its crowned
# ruler (the citadel's boss: ruler_of()) from the monster's own art
# (EnemyPortraits.picture(), its element's recolour; the Inferno in fire, as
# in its fight), at most CREST_FIT px - a whole multiple of the art where it
# fits. A kingdom not reached shows its ruler as a shadow under the padlock.
# Six of the seven share one design, recoloured by land; the Crowned
# Beholder is its own. Looked up one a frame (an enemy's scene
# each); a build without the art keeps the castle. Sprites, not drawing:
# a recolour is a material, and only a node carries one.
const CREST_FIT := 50.0
var crest_art: Node2D = null
var crest_top: Node2D = null
var _crest_sprites: Array = []
var _crests_tried: int = 0
const CRUMBLE_SECONDS := 1.6
const BANNER_SECONDS := 2.4
const WORD_GAP := 6.0
const SCORE := {"land": 50, "stone": 120, "tnt": 80, "bonus": 150, "blight": 60, "heart": 1500, "crystal": 120,
	"key": 200, "gold": 400, "rune": 150, "shell": 100, "prism": 120, "mimic": 100, "plague": 80, "mix": 150,
	"guard": 150, "clam": 250, "buoy": 80, "bubble": 60, "packed": 140, "drift": 90, "icicle": 70,
	"foot": 80, "column": 60, "boulder": 300, "ore": 500, "sand": 40,
	"wood": 60, "fuse": 30, "keg": 150, "obsidian": 200, "lava": 70, "basalt": 120,
	"lantern": 120, "shadow": 90, "void": 250}
const LAND_OF := {"l": "light", "a": "wind", "w": "water", "i": "ice", "e": "earth", "f": "fire", "d": "dark"}
const COLOURS := {
	"dark": Color(0.427, 0.157, 0.851), "fire": Color(1.0, 0.416, 0.122), "earth": Color(0.631, 0.384, 0.027),
	"ice": Color(0.404, 0.91, 0.976), "water": Color(0.231, 0.51, 0.965), "wind": Color(0.655, 0.953, 0.816),
	"light": Color(0.992, 0.902, 0.541),
}
const BLIGHT := Color(0.42, 0.62, 0.24)
const MIRROR_BLUE := Color(0.36, 0.55, 0.92)
# THE SIDE LANES (the owner: "a small gap on the left and right of the maps
# use unbreakable brick"): SIDE_GAP of open floor between each wall and the
# bricks - every map drawn a touch narrower to fit, so no design loses a
# column - and an iron RAIL down the field's side from the arena's top to the
# foot of its rows, open only at two gates GATE_H tall. A ball in a lane
# comes back down unless it is aimed through a gate.
const SIDE_GAP := 32.0
const FIELD_X := 192.0      # ARENA.position.x + SIDE_GAP
const FIELD_W := 896.0      # ARENA.size.x - 2 * SIDE_GAP
const RAIL_W := 5.0
const GATE_H := 36.0
# THE GUARD (the owner: "bricks that protect for defense"): two hits, and
# while it stands no brick touching it - the eight round it - can be hurt.
const GUARD_GLOW := Color(0.55, 0.75, 1.0)
# A GUARD SHUT IN (0.166.2, the owner, of Gilded Gate: "i have no way to
# break this"): a Guard whose every side is a brick it shields can never be
# hit - and while it stands neither can they, so the map could not be
# cleared (a light ball was the only way through). Now a blow on a brick
# shielded only by Guards no ball can get to goes through to the Guard: the
# brick glances, the Guard takes the hit and falls in two. A Guard a ball
# can get to still turns every blow aside. Which cells a ball can get to is
# a flood from the floor (_refresh_reach()): through empty cells, the band
# above the rows, the lanes and their gates.
const DIRS4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIRS8 := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
# THE WALLS CRUMBLE (0.166.2): while the balls seek (the last few, or none
# broken for STUCK_SECONDS) and not one brick left standing can be both
# reached and hurt, CRUMBLE_AFTER seconds on every brick left that counts
# breaks - whatever shut it in, a map can always be cleared. While a final
# fireball is out (0.166.4) the walls wait FINAL_WAITS times as long: it goes
# through them, so it should get there first.
const CRUMBLE_AFTER := 2.0
const FINAL_WAITS := 4.0
const CRUMBLE_LOOK := 0.25
# THE SHIELD CRACKS (0.166.2, the owner: "the final ball keeps bouncing into
# the ice and shield so we need to rethink the logic", and of this, "sounds
# good"): every GUARD_GLANCES blows that glance off a Guard's shield deal the
# Guard a hit of its own - it cracks, then breaks - so a shield can never
# lock a map. And the balls that seek aim only at what a blow can break now:
# a Guard first when one can be reached, never a shielded brick, a shut rune
# or clam, or iron (_seek_targets()).
const GUARD_GLANCES := 3
# THE ELEMENTS MIXED (the owner: "we can mix elements in bricks if needed for
# more effects"): the ball takes the element of each land brick it breaks
# (`el`), and breaking another land's while it carries one sets the two off.
const ELEMENTS := ["light", "wind", "water", "ice", "earth", "fire", "dark"]
const REACTIONS := {
	"fire+ice": "steam", "fire+wind": "firestorm", "ice+water": "glacier", "water+wind": "storm",
	"earth+fire": "magma", "ice+wind": "blizzard", "dark+light": "eclipse",
}
const REACTION_WORDS := {"steam": "STEAM!", "firestorm": "FIRESTORM!", "glacier": "GLACIER!", "storm": "STORM!",
	"magma": "MAGMA!", "blizzard": "BLIZZARD!", "eclipse": "ECLIPSE!", "clash": "CLASH!"}
# A mixed brick (a digit on the map) is its reaction waiting to be broken.
const MIXED := {"1": "steam", "2": "firestorm", "3": "glacier", "4": "storm", "5": "magma", "6": "blizzard",
	"7": "eclipse"}
const MIX_LANDS := {"steam": ["fire", "ice"], "firestorm": ["fire", "wind"], "glacier": ["water", "ice"],
	"storm": ["water", "wind"], "magma": ["earth", "fire"], "blizzard": ["ice", "wind"], "eclipse": ["light", "dark"],
	"clash": ["light", "light"]}
const STORM_JUMPS := 4
const STORM_REACH := 260.0
const DRIP_DEPTH := 6
const DRIP_SPEED := 380.0
const SHARD_DEPTH := 6
const SHATTER_STEP := 0.06
const REACT_DEPTH := 2
# A BALL HITS A BOSS FOR BALL_HIT; a laser for 1: so many bricks' worth off
# what is left to win its map (THE BOSS IS THE FIELD, boss_left()).
const BALL_HIT := 3
# THE BOSS IS THE FIELD (0.166.5, the owner: "how about boss hp is based on
# number of bricks on the field instead so when all bricks break boss is dead
# but hitting the boss reduces what it takes to win"): a boss's health is
# every brick still to break on its map, less what hits have taken
# (boss_left()). It HEALS by building bricks - a mage's stone, the Tide
# Mage's bubbles, sand, ice, water, what its young plant - each one counted,
# up to BOSS_HEALS of what the fight began with; past that a brick it builds
# is only in the way (breaking it still takes one), so a fight always ends.
const BOSS_HEALS := 0.25
const BOSS_HIT_GAP := 0.2
# HOW FAR A REACTION REACHES (measured with the bot, M3: a firestorm burning
# the whole row, and the mixed bricks it burnt each going off, cleared 90%
# of The Mixing Well in under six seconds): a firestorm burns FIRESTORM_REACH
# cells each way; an eclipse hits the ECLIPSE_MOST bricks of the land most
# left nearest it; a mixed brick goes off only when the ball breaks it or a
# reaction does - never a burn, a drip, a shatter or TNT.
const FIRESTORM_REACH := 5
# FIRE SPREADS to the fire bricks touching it, FIRE_SPREAD steps from the
# brick that caught at most (a 48-wide band of fire burnt down whole).
const FIRE_SPREAD := 3
# THE CORE SHATTERED sends a shockwave (the owner: "making the pupil act as
# a high-value weak point"): every brick within CORE_BLAST takes a hit, and
# a bonus always falls.
const CORE_BLAST := 130.0
const ECLIPSE_MOST := 16
# THE NEW BRICKS, and the ones that change
const RUNE_CYCLE := 3.6
const RUNE_LIT := 1.6
const PRISM_EVERY := 1.2
const BUMPER_KICK := 1.4
const PORTAL_WAIT := 0.25
const CRYSTAL_SPREAD := 24.0
const CORRUPT_CHANCE := 0.5
const DRIFT_REACH := 3
const DRIFT_SPEED := 0.8
const PORTAL_HUES := [Color(0.62, 0.32, 0.95), Color(0.2, 0.85, 0.8), Color(1.0, 0.45, 0.75), Color(1.0, 0.6, 0.2)]
# THE LAST FEW BRICKS (the owner's video: a long chase for the last four):
# with PULL_BELOW or fewer standing, they glow and a rising ball turns
# toward the nearest, PULL_TURN degrees a second at most.
const PULL_BELOW := 6
const PULL_TURN := 40.0
const UNBREAKABLE := ["iron", "mirror", "bumper", "portal", "lock", "whirl"]
const NEVER_BREAKS := {"iron": 1, "mirror": 1, "bumper": 1, "portal": 1, "lock": 1, "whirl": 1}
# THE KINGDOM OF WIND (0.163.0): GUSTS - bands of a map's rows ("gusts" in
# its data: [first row, last row, way]) that push a ball sideways while it is
# in them, GUST_PUSH a second; WHIRLS (W) that never break and fling the ball
# off in a direction of their own; KITES (k) - wind bricks that bob up and
# down into the room above and below them, KITE_REACH cells at most.
const GUST_PUSH := 900.0
const KITE_REACH := 2
const KITE_SPEED := 1.3
# THE KINGDOM OF WATER (0.164.0) - "a tide that rebuilds what you leave too
# long". THE TIDE: a map's "tide" is the row it reaches up to. Every
# TIDE_EVERY the water rises from the foot of the rows (TIDE_RISE), stands
# TIDE_HIGH and falls; as it stands, every cell under the mark broken more
# than TIDE_WAIT ago comes back as a one-hit water brick - TIDE_MOST at most a
# tide, the oldest first, never where a ball is, never a core, a Guard, a key,
# a lock or a bonus's cell. BUOYS (u): a water brick that floats up into the
# hole above it, a cell each BUOY_RISE. BUBBLES (o): broken, a bubble rises up
# the column at BUBBLE_SPEED and breaks the first brick it meets. CLAMS (Q):
# open CLAM_OPEN of every CLAM_CYCLE, each at its own moment; shut, nothing
# hurts them; open, one hit, and the pearl always drops a bonus.
const TIDE_EVERY := 30.0
const TIDE_RISE := 2.5
const TIDE_HIGH := 2.0
const TIDE_WAIT := 20.0
const TIDE_MOST := 12
const TIDE_KEEP := ["heart", "guard", "key", "lock", "bonus"]
const BUOY_RISE := 0.3
# A buoy floats BUOY_MOST cells at most (0.166.1, the owner: "had a brick
# travel up all the steel wall" - one beside an iron column climbed it all).
const BUOY_MOST := 2
const BUBBLE_SPEED := 300.0
const CLAM_CYCLE := 5.0
const CLAM_OPEN := 2.0
# THE KINGDOM OF ICE (0.165.0) - "frost that takes two hits, and icicles that
# fall"; the owner: "make them bigger and have bricks that take more then 1
# hit". FROST (F, a map's "frost" rows, the Frost King's young, the Frost
# Mage): a coat on a brick that one hit knocks off before the brick can be
# hurt (`frost`). PACKED ICE (P): three hits, cracking. SNOWDRIFTS (s): two
# hits, and a ball that strikes one keeps DRIFT_KEEP of its speed a moment.
# ICICLES (V): hang under a brick; when that brick goes, or a Snow Sprite's
# icicle has hung ICICLE_HANG, it falls at ICICLE_SPEED, ICICLE_HIT to the
# first brick it meets - or a stun on the paddle if it gets there. SLICK
# ICE (a map's "slick" rows): a ball in them runs SLICK_SPEED times as fast.
const DRIFT_KEEP := 0.55
const ICICLE_SPEED := 430.0
const ICICLE_HIT := 2
const ICICLE_HANG := 4.0
const ICICLE_STUN := 0.6
const SLICK_SPEED := 1.35
const ICED_SECONDS := 2.5
# THE KINGDOM OF EARTH (the same 0.165.0) - "break a pillar's foot and all
# above it falls"; every map big, and bricks that take more than one hit (the
# owner: "sounds good" to the plan). PILLARS: a FOOT (A, two hits, cracked by
# the first) under a column of earth stone (E, two hits) - break the foot and
# every brick stacked on it, up to the first gap, lets go: RUBBLE falls at
# RUBBLE_SPEED and smashes the first brick it meets (RUBBLE_HIT), and the
# topple scores TOPPLE_SCORE a block. BOULDERS (b, two cells to a boulder):
# four hits, cracking. ORE (g): three hits, a shower of score. SAND (n): one
# hit, and it settles - with an empty cell under it, it drops into it, a cell
# every SAND_STEP. TREMORS: on an earth map, every TREMOR_EVERY the ground
# rumbles (TREMOR_WARN before) and shakes - every pillar on a cracked foot
# falls, and every ball is jolted up to TREMOR_TURN degrees. HEAVY (the Rock
# Sniper's shot): the paddle moves at HEAVY_SHARE of its pace.
const RUBBLE_SPEED := 520.0
const RUBBLE_HIT := 1
const TOPPLE_SCORE := 60
const TOPPLE_KEEP := ["heart", "key", "lock", "guard"]
const SAND_STEP := 0.08
const TREMOR_EVERY := 30.0
const TREMOR_WARN := 2.0
const TREMOR_TURN := 10.0
const HEAVY_SHARE := 0.35
# THE KINGDOM OF FIRE (the same 0.165.0) - "TNT that chains, and fire that
# spreads"; every map big (the owner: "sounds good" to the plan). WOOD (h):
# two hits from a ball, but fire catches it - a blast, a Fireball or a fire
# ball, burning wood or fuse beside it, lava or a fire brick broken beside it
# - and it burns WOOD_BURN, then breaks and lights what touches it
# (_catch_round()). FUSE (z): a blow lights it rather than breaks it; it
# burns FUSE_STEP, then lights the fuse, TNT, kegs and wood touching it - the
# spark runs down the line. POWDER KEGS (J): two hits; they blow KEG_BLAST
# wide and set off every TNT and keg in reach. OBSIDIAN (q): four hits. LAVA
# (r): one hit while it is hot; left LAVA_COOL (playing) it cools into
# basalt, three hits. ERUPTIONS: on a fire map, every ERUPT_EVERY the volcano
# rumbles (ERUPT_WARN) and ERUPT_BOMBS lava bombs fall from the sky at
# BOMB_SPEED - on whatever stands they set as lava in the cell over it (empty,
# on the grid, not the hall, no ball there); past the bricks, the paddle they
# fall on is stunned (BOMB_STUN). FIRE ON THE FLOOR (the Flame Sprite): a
# patch on the paddle's line, embers PATCH_WARN then flames PATCH_LIFE - the
# paddle in it is stunned, once a patch. SCORCHED (the Fire Sniper's shot):
# the paddle SCORCH_SHARE of its width.
const WOOD_BURN := 0.9
const FUSE_STEP := 0.12
const KEG_BLAST := 150.0
const LAVA_COOL := 20.0
const ERUPT_EVERY := 30.0
const ERUPT_WARN := 2.0
const ERUPT_BOMBS := 6
const BOMB_SPEED := 340.0
const BOMB_STUN := 0.7
const PATCH_W := 64.0
const PATCH_WARN := 0.9
const PATCH_LIFE := 4.0
const SCORCH_SHARE := 0.6
const CATCHES := ["wood", "fuse", "tnt", "keg"]
# THE KINGDOM OF DARK (the same 0.165.0) - "bricks unseen until your light
# finds them"; every map big, the last kingdom (the owner: "sounds good" to
# the plan). THE DARK (a dark map, `dark`): a brick shows only where light
# falls on it - LIGHT_BALL round each ball (more for a light Elemental Ball),
# LIGHT_PADDLE over the paddle, LANTERN_R round each lantern lit - and fades
# back over SEEN_FADE once the light moves on (`seen`); unseen it is a ghost
# (GHOST). LANTERNS (t): one hit; broken, its light stays for good
# (`lanterns`). SHADOW BRICKS (m): two hits; in the dark one heals a hit every
# SHADOW_HEAL. VOID WELLS (v): three hits; a ball within VOID_REACH is drawn
# toward one, VOID_TURN degrees a second. NIGHTFALL: on a dark map, every
# NIGHT_EVERY the dark deepens (NIGHT_WARN before) for NIGHT_SECONDS - every
# light at NIGHT_SHARE. HEXED (the Shade Sniper's shot): the paddle's left
# and right swapped. LIGHT STOLEN (the Wisp): the balls' light at DIM_SHARE.
# BLACKOUT (the Beholder's eclipse): only the balls give light.
const LIGHT_BALL := 125.0
const LIGHT_PADDLE := 95.0
const LANTERN_R := 160.0
const SEEN_FADE := 1.6
const GHOST := 0.07
const SHADOW_HEAL := 3.0
const VOID_REACH := 95.0
const VOID_TURN := 140.0
const NIGHT_EVERY := 30.0
const NIGHT_WARN := 2.0
const NIGHT_SECONDS := 6.0
const NIGHT_SHARE := 0.5
const DIM_SHARE := 0.3
const DARK_KEEP := ["heart", "guard", "key", "lock", "lantern", "void", "shadow"]
const GOLD := Color(1.0, 0.82, 0.38)
const INK := Color(0.93, 0.95, 1.0)
const PANEL := Color(0.055, 0.06, 0.1, 0.94)
const EDGE := Color(0.36, 0.32, 0.27)
# THE BONUSES IN TURN (0.165.0 added five - the owner: "we also need more
# kinds of power ups magnet was always a good one split balls elemental
# balls"): an Elemental Ball twice in the turn, and an Extra Life in place of
# every LIFE_EVERY-th bonus. CAN_FALL is each kind once, for the panel.
const BONUS_ORDER := ["multi", "laser", "element", "shield", "magnet", "wide", "split", "fire", "element", "slow", "big"]
const CAN_FALL := ["multi", "laser", "shield", "wide", "fire", "slow", "magnet", "split", "big", "element", "life"]
const BONUS := {
	"wide": {"name": "Wide", "land": "earth", "secs": 9.0},
	"laser": {"name": "Laser", "land": "fire", "secs": 6.0},
	"multi": {"name": "x3 Balls", "land": "light", "secs": 0.0},
	"shield": {"name": "Shield", "land": "water", "secs": 8.0},
	"fire": {"name": "Fireball", "land": "fire", "secs": 6.0},
	"slow": {"name": "Slow", "land": "ice", "secs": 6.0},
	"magnet": {"name": "Magnet", "land": "dark", "secs": 12.0},
	"split": {"name": "Split", "land": "wind", "secs": 10.0},
	"big": {"name": "Big Ball", "land": "earth", "secs": 8.0},
	"element": {"name": "Elemental Ball", "land": "light", "secs": 12.0},
	"life": {"name": "Extra Life", "land": "fire", "secs": 0.0},
}
# MAGNET: a ball landing on the paddle sticks where it lands, and goes at a
# click or Space - or by itself after MAGNET_HOLD - off that spot as a bounce
# would. SPLIT: every brick a ball breaks splits it in two (SPLIT_TURN apart),
# MOST_BALLS at most. BIG BALL: BIG_SIZE times the size, and the bricks round
# what it strikes take a hit. EXTRA LIFE: every LIFE_EVERY-th bonus, up to
# LIVES_MOST. ELEMENTAL BALL: the ball keeps one land (ELEMENT_LAND, in turn
# through the seven) - every other land's brick it breaks sets off their
# reaction - and the land's own way: fire sets what it breaks burning, water
# splashes the bricks beside, ice freezes what it hits, wind curves the ball
# toward the nearest brick (WIND_TURN a second), earth hits twice as hard,
# light goes through Guards' shields and finds runes lit and clams open,
# dark doubles the score.
const MAGNET_HOLD := 2.0
const SPLIT_TURN := 20.0
const BIG_SIZE := 1.8
const LIFE_EVERY := 40
const LIVES_MOST := 5
const WIND_TURN := 70.0
const HEART_RED := Color(0.95, 0.28, 0.36)

var state: State = State.KINGDOMS
# The map now, where this run began, and the maps cleared before it (the
# server's count: the next map to clear is `furthest`).
var map_index: int = 0
var start_index: int = 0
var furthest: int = 0
var selected: int = 0
var cleared: int = 0
var pays: Dictionary = {}
var lives: int = LIVES
var score: int = 0
var combo: int = 0
var best_combo: int = 0
var target_x: float = 640.0
var paddle_x: float = 640.0
var paddle_w: float = PADDLE_W
var stunned: float = 0.0
var tugged: float = 0.0         # hooked by the Harpooner: slowed, pulled to tug_x
var tug_x: float = 640.0
var aim: float = -PI / 2.0
var t: float = 0.0
var bricks: Array = []
var cells: Dictionary = {}       # Vector2i -> brick
var footprint: Dictionary = {}   # Vector2i -> true: where the map had bricks
# what counts to clear a map, and what is broken of it - on a boss's map,
# its health too (_boss_field() keeps it with every change)
var breakable: int = 0:
	set(v):
		breakable = v
		_boss_field()
var broken: int = 0:
	set(v):
		broken = v
		_boss_field()
var balls: Array = []
var bolts: Array = []
var caps: Array = []
var active: Dictionary = {}
var parts: Array = []
var words: Array = []
var rings: Array = []
# The map's boss (crownfallboss.gd), or null; it walks `hall`, the R cells.
var boss = null
var boss_base: int = 0     # THE BOSS IS THE FIELD: the bricks to break when it began
var boss_struck: int = 0   # what hits on it have taken, in bricks
var _fighting: bool = false
var hall := Rect2()
var rows_count: int = 0
# THIS MAP'S GRID (the owner: "we can even make the map bigger in some"): a
# map Maps.COLS wide has bricks CW x CH; a big one, Maps.BIG_COLS wide, has
# smaller ones, so the same arena holds more - every brick drawn at its own
# size (_draw_brick scales the standard brick to it).
var cols: int = Maps.COLS
var cw: float = CW
var ch: float = CH
var gap: float = ROW_GAP
var _jolt := Vector2.ZERO
var _jolt_rng := RandomNumberGenerator.new()
var _cv: CanvasItem = null
var floor_layer: Node2D = null
var brick_layer: Node2D = null   # the still bricks, inside brick_cache
var brick_cache: SubViewport = null
var brick_pic: Sprite2D = null
var brick_live: Node2D = null
# the stone the bricks are set in, drawn once a map (0.166.2), and the floor
# over it - tide, slicks, gusts, rails, the dark - every frame
var building_layer: Node2D = null
var floor_top: Node2D = null
var _building_key: int = -1
var _open: Dictionary = {}        # Vector2i -> true: the empty cells a ball can get to
var _open_key: int = -1
var _grid_ver: int = 0            # bumped when a brick is set or moves on the grid
var _crumbling: bool = false
var _shut_t: float = 0.0          # how long nothing standing could be reached and hurt
var _shut_look: float = 0.0
var _guard_list: Array = []
var _guard_key: int = -1
var _glow_last: bool = false
var _since_break: float = 0.0
var _said_last: bool = false
var final_fire: bool = false   # THE FINAL FIREBALL: the last few's balls
var redrawn: int = 0           # bricks drawn again in the last sync (the suite's)
var _sync_n: int = 0
# What the new bricks and the mixing leave going: lava falling down a column,
# lightning and shards drawn a moment, the eclipse's dark, the drifters, the
# prisms, and the keys still to break.
var drips: Array = []
var zaps: Array = []
var movers: Array = []
var gusts: Array = []          # {"y0", "y1", "way"} in px, this map's gusts
var tide_mark: int = -1        # the row this map's tide reaches up to; -1 none
var tide_t: float = 0.0        # how far into its cycle the tide is
var gone_at: Dictionary = {}   # Vector2i -> when the cell's brick broke
var placed: Dictionary = {}    # Vector2i -> the kind the map put there
var buoys: Array = []
var bubbles: Array = []        # {"p", "last"}: rising, to break what they meet
var slicks: Array = []         # {"y0", "y1"} in px: this map's slick ice
var falling: Array = []        # {"p", "last"}: icicles falling
var iced: float = 0.0          # the Ice Sniper's lance: the paddle slides
var paddle_v: float = 0.0
var hanging: Array = []        # the Snow Sprite's icicles, each to fall in its time
var rubble: Array = []         # {"p", "last", "c"}: a toppled pillar, falling
var tremors: bool = false      # this map shakes (the Kingdom of Earth)
var tremor_t: float = 0.0
var heavy: float = 0.0         # the Rock Sniper's shot: the paddle weighed down
var _sand_t: float = 0.0
var _rumbled: bool = false
var bombs: Array = []          # {"p", "last"}: lava bombs falling
var patches: Array = []        # {"x", "warn", "life", "hit"}: fire on the floor
var eruptions: bool = false    # this map erupts (the Kingdom of Fire)
var erupt_t: float = 0.0
var _erupt_warned: bool = false
var scorched: float = 0.0      # the Fire Sniper's shot: the paddle shorter
var dark: bool = false         # this map is dark (the Kingdom of Dark)
var lanterns: Array = []       # Vector2: the lanterns lit, each a light for good
var voids: Array = []          # the void wells
var night_t: float = 0.0
var night_left: float = 0.0
var _night_warned: bool = false
var hexed: float = 0.0         # the Shade Sniper's shot: left and right swapped
var light_stolen: float = 0.0  # the Wisp: the balls' light stolen
# A PHONE (0.166.0, the screen sets it): the left panel's foot is the
# slider (_draw_slider), and the Laser fires on a tap (tap()), not by itself.
var touch_slider: bool = false
var blackout: float = 0.0      # the Beholder's eclipse: only the balls give light
var prisms: Array = []
var keys_left: int = 0
var rails: Array = []          # the lanes' iron rails (in bricks too, off the grid)
var pulling: bool = false
var _eclipse: float = 0.0
var _reacting: int = 0
var _react_said: float = -1.0
var _new_balls: Array = []
var running_by_clock: bool = true
var aim_sways: bool = true
# What the waiting ball says (the screen sets it for a phone).
var launch_hint: String = "Click or Space to launch"
# The kingdom map's last line: how to go in, the picked map's name for %s
# (the owner: "make keyboard/controller navigation completely
# self-explanatory"). The screen sets it for a phone.
var map_hint: String = "Enter / Space: enter %s   ·   Esc: leave"
var rng := RandomNumberGenerator.new()

var _combo_t: float = 0.0
var _blight_t: float = BLIGHT_EVERY
var _laser_t: float = 0.0
var _muzzle: float = 0.0
var _shake: float = 0.0
var _shield_flash: float = 0.0
var _healed: float = 0.0
var _cleared_t: float = 0.0
var _next_bonus: int = 0
var _banner_t: float = 0.0
var _popped: Array = []
var ball_land: String = ""      # the Elemental Ball's land while it lasts
var _next_land: int = 0
# THE FRAME'S LIFE (the owner: "make the ui look even better like the area
# outside like score and all the other stuff"): the score shown rolls up to
# the score, gains pop off it, the coin bounces when gold comes in, a heart
# cracks when a life is lost, the multiplier's badge pulses when it rises.
var shown_score: float = 0.0
var score_pops: Array = []     # {"n", "age"}
var _score_was: int = 0
var _gold_was: int = -1
var _gold_bounce: float = 0.0
var _lives_was: int = LIVES
var _heart_crack: float = 0.0
var _mult_was: float = 1.0
var _mult_pop: float = 0.0
var _font: Font
var _bold: FontVariation


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_bold = FontVariation.new()
	_bold.base_font = _font
	_bold.variation_embolden = 0.9
	rng.randomize()
	_jolt_rng.randomize()
	_cv = self
	# the floor, then the bricks, both behind the run's own drawing
	floor_layer = Node2D.new()
	floor_layer.name = "floor_layer"
	floor_layer.show_behind_parent = true
	add_child(floor_layer)
	floor_layer.draw.connect(_paint_floor)
	building_layer = Node2D.new()
	building_layer.name = "building_layer"
	building_layer.show_behind_parent = true
	add_child(building_layer)
	building_layer.draw.connect(_paint_building)
	floor_top = Node2D.new()
	floor_top.name = "floor_top"
	floor_top.show_behind_parent = true
	add_child(floor_top)
	floor_top.draw.connect(_paint_floor_top)
	brick_cache = SubViewport.new()
	brick_cache.name = "brick_cache"
	brick_cache.size = Vector2i(VIEW)
	brick_cache.transparent_bg = true
	brick_cache.disable_3d = true
	brick_cache.world_2d = World2D.new()
	brick_cache.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	brick_cache.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(brick_cache)
	brick_layer = Node2D.new()
	brick_layer.name = "brick_layer"
	brick_cache.add_child(brick_layer)
	brick_pic = Sprite2D.new()
	brick_pic.name = "brick_pic"
	brick_pic.centered = false
	brick_pic.texture = brick_cache.get_texture()
	brick_pic.show_behind_parent = true
	# a canvas drawn on a clear target keeps its colour premultiplied
	var premult := CanvasItemMaterial.new()
	premult.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	brick_pic.material = premult
	add_child(brick_pic)
	brick_live = Node2D.new()
	brick_live.name = "brick_live"
	brick_live.show_behind_parent = true
	add_child(brick_live)


func _process(delta: float) -> void:
	if running_by_clock:
		step(minf(delta, 0.05))
	_jolt = Vector2(_jolt_rng.randf_range(-1, 1), _jolt_rng.randf_range(-1, 1)) * _shake * 4.0
	sync_bricks()
	if state == State.KINGDOMS:
		_dress_crests()
	elif crest_art != null:
		crest_art.visible = false
		crest_top.visible = false
	if floor_layer != null:
		floor_layer.queue_redraw()
		floor_top.queue_redraw()
		building_layer.position = _jolt
		building_layer.visible = state != State.KINGDOMS
		var key: int = hash([map_index, footprint.size(), hall, cols, rows_count, cw, ch])
		if key != _building_key:
			_building_key = key
			building_layer.queue_redraw()


# ---------------------------------------------------------------- the run --

func show_kingdoms(furthest_cleared: int) -> void:
	"""The kingdom map, the next map to clear picked."""
	state = State.KINGDOMS
	furthest = clampi(furthest_cleared, 0, Maps.made_count())
	selected = mini(furthest, Maps.made_count() - 1)
	_clear_map()
	queue_redraw()


func can_start_at(index: int) -> bool:
	"""A map may be started from once every map before it is cleared."""
	return index >= 0 and index < Maps.made_count() and index <= furthest


func begin(index: int) -> void:
	"""A run from map `index`."""
	start_index = clampi(index, 0, Maps.made_count() - 1)
	lives = LIVES
	score = 0
	cleared = 0
	best_combo = 0
	_load(start_index)


func gold_now() -> int:
	"""What this run's cleared maps pay, by the server's table."""
	var out: int = 0
	var each: Array = pays.get("maps", []) if pays.get("maps") is Array else []
	for i in cleared:
		var at: int = start_index + i
		if at < each.size():
			out += int(each[at])
	return out


func playing() -> bool:
	return state in [State.AIM, State.PLAY, State.CLEARED]


func launch() -> void:
	if state == State.AIM and stunned <= 0.0:
		state = State.PLAY
		for b in balls:
			if b["v"] == Vector2.ZERO:
				b["v"] = Vector2.from_angle(aim) * SPEED
	elif state == State.PLAY:
		for b in balls:
			if b.has("stuck"):
				_unstick(b)


func tap() -> void:
	"""A PHONE'S TAP ON THE FIELD (0.166.0): a launch, a ball the Magnet holds
	let go, and - once the ball is flying - the Laser's volley, at most one
	every LASER_EVERY (on a phone it never fires by itself)."""
	var flying: bool = state == State.PLAY
	launch()
	if flying and active.has("laser") and _laser_t <= 0.0:
		_fire_lasers()


func element() -> String:
	"""The Elemental Ball's land while it lasts, else ""."""
	return ball_land if active.has("element") else ""


func ball_r() -> float:
	"""The ball's size: BIG_SIZE times while a Big Ball is on."""
	return BALL_R * (BIG_SIZE if active.has("big") else 1.0)


func _unstick(b: Dictionary) -> void:
	"""A MAGNET lets go: off the paddle from where it sat, as a bounce."""
	var off: float = clampf(float(b["stuck"]) / (paddle_w / 2.0), -1.0, 1.0)
	b.erase("stuck")
	b.erase("stick_t")
	b["v"] = Vector2.from_angle(deg_to_rad(-90.0 + off * 58.0)) * SPEED
	_burst(b["p"], COLOURS["dark"].lightened(0.3), 8, 140.0)


func _load(index: int) -> void:
	_clear_map()
	map_index = index
	var data: Dictionary = Maps.MAPS[index]
	var heart := Rect2()
	var heart_cells: Array = []
	var portals: Array = []
	var drifting: Array = []
	var kites: Array = []
	var rows: Array = data["rows"]
	cols = str(rows[0]).length() if not rows.is_empty() else Maps.COLS
	cw = FIELD_W / cols
	ch = CH if cols <= Maps.COLS else floorf(cw * 0.5)
	gap = ROW_GAP if cols <= Maps.COLS else 1.0
	for row in rows.size():
		var line: String = rows[row]
		for col in line.length():
			var letter: String = line[col]
			if letter == ".":
				continue
			var r := _cell(col, row)
			if letter == "R":
				hall = r if hall.size == Vector2.ZERO else hall.merge(r)
				continue
			if letter == "<":
				drifting.append(Vector2i(col, row))
				continue
			if letter == "k":
				kites.append(Vector2i(col, row))
				continue
			footprint[Vector2i(col, row)] = true
			match letter:
				"H":
					heart = r if heart.size == Vector2.ZERO else heart.merge(r)
					heart_cells.append(Vector2i(col, row))
				"S":
					_add(col, row, "stone", "", 3)
				"I":
					_add(col, row, "iron", "", 0)
				"M":
					_add(col, row, "mirror", "light", 0)
				"T":
					_add(col, row, "tnt", "fire", 1)
				"?":
					_add(col, row, "bonus", "light", 1)
				"B":
					_add(col, row, "blight", "", 1)
				"C":
					_add(col, row, "crystal", "ice", 1)
				"U":
					_add(col, row, "bumper", "light", 0)
				"O":
					portals.append(_add(col, row, "portal", "dark", 0))
				"K":
					_add(col, row, "key", "light", 1)
				"L":
					_add(col, row, "lock", "", 0)
				"G":
					_add(col, row, "gold", "light", 2)
				"N":
					var rune := _add(col, row, "rune", "light", 1)
					rune["phase"] = fmod((col + row) * 0.37, RUNE_CYCLE)
				"Z":
					_add(col, row, "shell", "", 1)
				"X":
					var prism := _add(col, row, "prism", "light", 1)
					prism["phase"] = (col * 3 + row) * 0.29
					prisms.append(prism)
				"D":
					_add(col, row, "guard", "light", 2)
				"W":
					var whirl := _add(col, row, "whirl", "wind", 0)
					whirl["phase"] = (col + row) * 0.7
				"Y":
					_add(col, row, "mimic", "", 1)
				"u":
					buoys.append(_add(col, row, "buoy", "water", 1))
				"o":
					_add(col, row, "bubble", "water", 1)
				"Q":
					var clam := _add(col, row, "clam", "water", 1)
					clam["phase"] = fmod((col * 2 + row) * 0.61, CLAM_CYCLE)
				"F":
					var coated := _add(col, row, "land", "ice", 1)
					coated["frost"] = true
				"P":
					_add(col, row, "packed", "ice", 3)
				"s":
					_add(col, row, "drift", "ice", 2)
				"V":
					_add(col, row, "icicle", "ice", 1)
				"A":
					_add(col, row, "foot", "earth", 2)
				"E":
					_add(col, row, "column", "earth", 2)
				"g":
					_add(col, row, "ore", "earth", 3)
				"n":
					_add(col, row, "sand", "earth", 1)
				"h":
					_add(col, row, "wood", "fire", 2)
				"z":
					_add(col, row, "fuse", "fire", 1)
				"J":
					_add(col, row, "keg", "fire", 2)
				"q":
					_add(col, row, "obsidian", "fire", 4)
				"r":
					var lava := _add(col, row, "lava", "fire", 1)
					lava["cool"] = LAVA_COOL
				"t":
					_add(col, row, "lantern", "light", 1)
				"m":
					_add(col, row, "shadow", "dark", 2)
				"v":
					voids.append(_add(col, row, "void", "dark", 3))
				"b":
					# A BOULDER is two cells: a b beside a one-cell boulder joins it
					var left: Variant = cells.get(Vector2i(col - 1, row))
					if left != null and left["kind"] == "boulder" and (left["cells"] as Array).size() == 1:
						(left["cells"] as Array).append(Vector2i(col, row))
						left["rect"] = (left["rect"] as Rect2).merge(r)
						cells[Vector2i(col, row)] = left
					else:
						var rock := _brick(r, "boulder", "earth", 4)
						rock["cells"] = [Vector2i(col, row)]
						bricks.append(rock)
						cells[Vector2i(col, row)] = rock
				"p":
					_add(col, row, "plague", "", 2)
				"1", "2", "3", "4", "5", "6", "7":
					var mix := _add(col, row, "mix", MIX_LANDS[MIXED[letter]][0], 1)
					mix["mix"] = MIXED[letter]
				_:
					var land: String = LAND_OF.get(letter, "light")
					_add(col, row, "land", land, 2 if land == "earth" else 1)
	if heart.size != Vector2.ZERO:
		# THE CORE IS ONE BRICK over every H cell: each cell names it, so the
		# blight cannot grow into the core while it stands.
		var k := _brick(heart, "heart", "light", 6)
		k["cells"] = heart_cells
		bricks.append(k)
		for c in heart_cells:
			cells[c] = k
	# PORTALS GO IN PAIRS, in reading order; one left over is a wall.
	for i in range(0, portals.size() - 1, 2):
		portals[i]["to"] = portals[i + 1]
		portals[i + 1]["to"] = portals[i]
		portals[i]["pair"] = i >> 1
		portals[i + 1]["pair"] = i >> 1
	_make_drifters(drifting)
	_make_kites(kites, rows.size())
	for g in data.get("gusts", []):
		var y0: float = MAP_TOP + int(g[0]) * (ch + gap) - gap
		var y1: float = minf(MAP_TOP + (int(g[1]) + 1) * (ch + gap), PADDLE_Y - 90.0)
		gusts.append({"y0": y0, "y1": y1, "way": signf(float(g[2]))})
	tide_mark = int(data.get("tide", -1))
	tide_t = 0.0
	tremors = str(Maps.kingdom_of(index).get("land", "")) == "earth"
	eruptions = str(Maps.kingdom_of(index).get("land", "")) == "fire"
	dark = str(Maps.kingdom_of(index).get("land", "")) == "dark"
	for band in data.get("slick", []):
		slicks.append({"y0": MAP_TOP + int(band[0]) * (ch + gap) - gap, "y1": MAP_TOP + (int(band[1]) + 1) * (ch + gap)})
	for band in data.get("frost", []):
		for k in bricks:
			if k.has("cell") and _breaks(k) and not ["heart", "guard", "key"].has(str(k["kind"])) \
					and (k["cell"] as Vector2i).y >= int(band[0]) and (k["cell"] as Vector2i).y <= int(band[1]):
				k["frost"] = true
	for k in bricks:
		if _breaks(k):
			breakable += 1
		if k.has("cell"):
			placed[k["cell"]] = k["kind"]
		for c in k.get("cells", []):
			placed[c] = k["kind"]
		if k["kind"] == "key":
			keys_left += 1
	rows_count = rows.size()
	_make_rails(index)
	if data.get("boss") is Dictionary and hall.size != Vector2.ZERO:
		boss = Boss.new()
		boss.setup(self, data["boss"], str(Maps.kingdom_of(index).get("land", "light")), hall, ARENA, PADDLE_Y, VIEW.y)
		# THE BOSS IS THE FIELD: its health, every brick there is to break
		boss_base = breakable - broken
		boss_struck = 0
		boss.most = maxi(1, boss_base)
		boss.hp = boss_base
		_fighting = true
	_reset_ball()
	_banner_t = BANNER_SECONDS
	said.emit("%s - map %d of %d" % [data["name"], Maps.in_kingdom(index) + 1, Maps.MAPS_A_KINGDOM])
	queue_redraw()


func _clear_map() -> void:
	_fighting = false
	boss_base = 0
	boss_struck = 0
	_since_break = 0.0
	_open.clear()
	_open_key = -1
	_grid_ver += 1
	_shut_t = 0.0
	_guard_key = -1
	_said_last = false
	final_fire = false
	bricks.clear()
	cells.clear()
	footprint.clear()
	balls.clear()
	bolts.clear()
	caps.clear()
	parts.clear()
	words.clear()
	rings.clear()
	active.clear()
	drips.clear()
	zaps.clear()
	movers.clear()
	prisms.clear()
	rails.clear()
	gusts.clear()
	buoys.clear()
	bubbles.clear()
	slicks.clear()
	falling.clear()
	hanging.clear()
	rubble.clear()
	tremors = false
	tremor_t = 0.0
	heavy = 0.0
	_sand_t = 0.0
	_rumbled = false
	bombs.clear()
	patches.clear()
	eruptions = false
	erupt_t = 0.0
	_erupt_warned = false
	scorched = 0.0
	dark = false
	lanterns.clear()
	voids.clear()
	night_t = 0.0
	night_left = 0.0
	_night_warned = false
	hexed = 0.0
	light_stolen = 0.0
	blackout = 0.0
	iced = 0.0
	paddle_v = 0.0
	gone_at.clear()
	placed.clear()
	tide_mark = -1
	tide_t = 0.0
	_new_balls.clear()
	keys_left = 0
	pulling = false
	_eclipse = 0.0
	_popped.clear()
	breakable = 0
	broken = 0
	combo = 0
	stunned = 0.0
	tugged = 0.0
	hall = Rect2()
	rows_count = 0
	if boss != null:
		boss.clear()
	boss = null
	_healed = 0.0
	_blight_t = BLIGHT_EVERY


func _cell(col: int, row: int) -> Rect2:
	return Rect2(FIELD_X + col * cw + 1.0, MAP_TOP + row * (ch + gap), cw - 2.0, ch)


func cell_at(at: Vector2) -> Vector2i:
	"""The grid cell a point is in."""
	return Vector2i(int(floor((at.x - FIELD_X) / cw)), int(floor((at.y - MAP_TOP) / (ch + gap))))


func _bricks_near(at: Vector2) -> Array:
	"""THE BRICKS A BALL AT `at` COULD TOUCH: those in its cell and the eight
	round it (every brick names its cells in `cells`, the core all four) -
	never the whole map, which at 32 x 18 is hundreds."""
	var mid: Vector2i = cell_at(at)
	var out: Array = []
	for r in range(mid.y - 1, mid.y + 2):
		for c in range(mid.x - 1, mid.x + 2):
			var k: Variant = cells.get(Vector2i(c, r))
			if k != null and not out.has(k):
				out.append(k)
	for k in movers:
		if k["hp"] > 0 and (k["rect"] as Rect2).grow(BALL_R + 4.0).has_point(at):
			out.append(k)
	for k in rails:
		if (k["rect"] as Rect2).grow(BALL_R + 4.0).has_point(at):
			out.append(k)
	return out


func field_bottom() -> float:
	"""The foot of the map's rows."""
	return MAP_TOP + maxi(rows_count, 1) * (ch + gap)


func _add(col: int, row: int, kind: String, land: String, hp: int) -> Dictionary:
	var k := _brick(_cell(col, row), kind, land, hp)
	k["cell"] = Vector2i(col, row)
	bricks.append(k)
	cells[Vector2i(col, row)] = k
	_grid_ver += 1
	return k


func _brick(r: Rect2, kind: String, land: String, hp: int) -> Dictionary:
	return {"rect": r, "kind": kind, "land": land, "hp": hp, "most": hp, "flash": 0.0, "burn": -1.0}


func _breaks(k: Dictionary) -> bool:
	return not NEVER_BREAKS.has(k["kind"])


func _make_rails(index: int) -> void:
	"""THE LANES' RAILS: iron down each side of the field, from the arena's
	top to the foot of the rows, broken by two gates GATE_H tall - a third of
	the way down and two thirds, shifted a row or two map by map."""
	var pitch: float = ch + gap
	var rows_in: int = maxi(rows_count, 4)
	var apart: int = ceili(GATE_H / pitch) + 3
	var first: int = clampi(roundi(rows_in * 0.3) + index % 2, 1, maxi(1, rows_in - apart))
	var second: int = clampi(roundi(rows_in * 0.65) - index % 3, first + apart, maxi(first + apart, rows_in))
	var foot: float = field_bottom()
	var spans: Array = []
	for g in [first, second]:
		var top: float = MAP_TOP + g * pitch - gap
		spans.append(Vector2(top, top + GATE_H))
	spans.append(Vector2(foot, foot))
	for x in [FIELD_X - RAIL_W, FIELD_X + FIELD_W]:
		var y: float = ARENA.position.y
		for span in spans:
			if span.x > y + 4.0:
				var k := _brick(Rect2(x, y, RAIL_W, minf(span.x, foot) - y), "iron", "", 0)
				k["rail"] = true
				bricks.append(k)
				rails.append(k)
			y = maxf(y, span.y)
			if y >= foot:
				break


func gates() -> Array:
	"""The gates in the left rail, as (top, bottom) - the pictures' and the
	suite's."""
	var out: Array = []
	var left: Array = rails.filter(func(k: Dictionary) -> bool: return (k["rect"] as Rect2).position.x < FIELD_X)
	for i in range(left.size() - 1):
		out.append(Vector2((left[i]["rect"] as Rect2).end.y, (left[i + 1]["rect"] as Rect2).position.y))
	return out


func _guarded(k: Dictionary) -> bool:
	"""Whether a Guard touching `k` stands that a ball can get to - the blow
	glances off its shield (a Guard is never guarded; one shut in takes the
	blow instead, _shut_guard())."""
	return _open_guard(k) != null


func _open_guard(k: Dictionary) -> Variant:
	"""The first Guard touching `k` that stands and a ball can get to."""
	if _crumbling or k["kind"] == "guard":
		return null
	var own: Array = k.get("cells", [k["cell"]] if k.has("cell") else [])
	for c in own:
		for d in DIRS8:
			var o: Variant = cells.get(c + d)
			if o != null and o["kind"] == "guard" and o["hp"] > 0 and _reachable(o):
				return o
	return null


func _shut_guard(k: Dictionary) -> Variant:
	"""The Guard shielding `k` when every Guard touching it is shut in - no
	ball can get to it - which takes the blow `k` is dealt (0.166.2). Null
	when a Guard touching it can be reached, or none does."""
	if _crumbling or k["kind"] == "guard":
		return null
	var found: Variant = null
	var own: Array = k.get("cells", [k["cell"]] if k.has("cell") else [])
	for c in own:
		for d in DIRS8:
			var o: Variant = cells.get(c + d)
			if o != null and o["kind"] == "guard" and o["hp"] > 0:
				if _reachable(o):
					return null
				if found == null:
					found = o
	return found


func _reachable(k: Dictionary) -> bool:
	"""A ball can get to `k` (0.166.2): on the grid, a cell of it beside an
	empty cell open to the floor; off it, inside the arena."""
	if not k.has("cell") and not k.has("cells"):
		return ARENA.grow(-BALL_R).has_point((k["rect"] as Rect2).get_center())
	_refresh_reach()
	for c in k.get("cells", [k.get("cell")]):
		for d in DIRS4:
			if _open.has(c + d):
				return true
	return false


func _seek_targets() -> Array:
	"""What the balls that seek aim at (THE SHIELD CRACKS): bricks a ball can
	get to and a blow can break now - not shielded, not a shut rune or
	clam, not iron - and of them, Guards first."""
	var guards: Array = []
	var rest: Array = []
	if final_fire:
		# THE FINAL FIREBALL goes through anything: every brick left counts
		for k in bricks:
			if k["hp"] > 0 and _breaks(k):
				rest.append(k)
		return rest
	for k in bricks:
		if _can_hit(k) and not _shut(k):
			if k["kind"] == "guard":
				guards.append(k)
			else:
				rest.append(k)
	return guards if not guards.is_empty() else rest


func _can_hit(k: Dictionary) -> bool:
	"""A brick a ball can get to and hurt now: standing, breakable, under no
	Guard's shield that turns the blow aside. The last few's glow and pull,
	and the stuck balls' search, aim only at these (0.166.2)."""
	return k["hp"] > 0 and _breaks(k) and not _guarded(k) and _reachable(k)


func _refresh_reach() -> void:
	"""THE WAY IN: a flood from under the rows through every empty cell, up
	the lanes and in at their gates, and across the band above the rows -
	the cells a ball can get to. Worked out again only when the grid has
	changed."""
	var key: int = (((((map_index * 131 + cells.size()) * 131 + broken) * 131 + breakable) * 131 + _grid_ver) * 131
		+ rows_count) * 131 + cols * 7 + rails.size()
	if key == _open_key:
		return
	_open_key = key
	_open.clear()
	var rows: int = rows_count
	for c in cells:
		rows = maxi(rows, (c as Vector2i).y + 1)
	var gate_rows: Dictionary = {}
	for g in gates():
		for r in rows:
			var y0: float = MAP_TOP + r * (ch + gap)
			if y0 + ch > (g as Vector2).x and y0 < (g as Vector2).y:
				gate_rows[r] = true
	var todo: Array[Vector2i] = []
	for c in range(-1, cols + 1):
		todo.append(Vector2i(c, rows))
	for r in rows:
		todo.append(Vector2i(-1, r))
		todo.append(Vector2i(cols, r))
	var seen: Dictionary = {}
	for q in todo:
		seen[q] = true
	var i: int = 0
	while i < todo.size():
		var p: Vector2i = todo[i]
		i += 1
		var lane: bool = p.x < 0 or p.x >= cols
		if not lane:
			_open[p] = true
		for d in DIRS4:
			var q: Vector2i = p + d
			if seen.has(q) or q.x < -1 or q.x > cols or q.y < -1 or q.y > rows:
				continue
			var q_lane: bool = q.x < 0 or q.x >= cols
			if q_lane and q.y < 0:
				continue
			if lane != q_lane and not gate_rows.has(p.y):
				continue
			if not q_lane and q.y >= 0 and q.y < rows and cells.has(q):
				continue
			seen[q] = true
			todo.append(q)


func _walls_crumble(dt: float) -> void:
	"""THE WALLS CRUMBLE (0.166.2): while the balls seek and not one brick
	left standing can be reached and hurt (looked at every CRUMBLE_LOOK),
	CRUMBLE_AFTER seconds on every brick left that counts breaks."""
	if boss != null or state != State.PLAY or not seeking():
		_shut_t = 0.0
		return
	_shut_look -= dt
	if _shut_look > 0.0:
		return
	_shut_look = CRUMBLE_LOOK
	if bricks.any(_can_hit):
		_shut_t = 0.0
		return
	_shut_t += CRUMBLE_LOOK
	# a final fireball goes through walls to get at them: the walls wait
	# FINAL_WAITS times as long before they crumble (still the last resort)
	if _shut_t >= CRUMBLE_AFTER * (FINAL_WAITS if final_fire else 1.0):
		_crumble_walls()


func _crumble_walls() -> void:
	_shut_t = 0.0
	_crumbling = true
	_say(Vector2(640, 400), "THE WALLS CRUMBLE", GOLD, 28, 1.4)
	_shake = 1.0
	for k in bricks.duplicate():
		if k["hp"] > 0 and _breaks(k):
			if k["kind"] == "shell":
				k["kind"] = "stone"
			k.erase("frost")
			_damage(k, 99, null)
	_crumbling = false

func _make_kites(spots: Array, rows_in: int) -> void:
	"""KITES (k): wind bricks bobbing up and down into the empty cells above
	and below them, KITE_REACH at most, each on its own beat. Off the grid,
	like drifters: the ball finds them in `movers`."""
	for c in spots:
		var up: int = 0
		while up < KITE_REACH and c.y - up - 1 >= 0 and not cells.has(Vector2i(c.x, c.y - up - 1)) \
				and not spots.has(Vector2i(c.x, c.y - up - 1)):
			up += 1
		var down: int = 0
		while down < KITE_REACH and c.y + down + 1 < rows_in + KITE_REACH and not cells.has(Vector2i(c.x, c.y + down + 1)) \
				and not spots.has(Vector2i(c.x, c.y + down + 1)):
			down += 1
		var k := _brick(_cell(c.x, c.y), "land", "wind", 1)
		k["kite"] = true
		k["home"] = (k["rect"] as Rect2).position.y
		k["lo"] = -up * (ch + gap)
		k["hi"] = down * (ch + gap)
		k["phase"] = (c.x * 0.9 + c.y * 0.4)
		bricks.append(k)
		movers.append(k)


func _gusts(dt: float) -> void:
	"""A ball in a gust's band is pushed its way, its speed kept."""
	if gusts.is_empty():
		return
	for b in balls:
		var v: Vector2 = b["v"]
		if v == Vector2.ZERO:
			continue
		for g in gusts:
			if (b["p"] as Vector2).y >= float(g["y0"]) and (b["p"] as Vector2).y <= float(g["y1"]):
				var speed: float = v.length()
				v.x += float(g["way"]) * GUST_PUSH * dt
				v = steady(v.normalized() * speed)
		b["v"] = v


func fling(b: Dictionary, at: Vector2) -> void:
	"""A whirl's or a whirlwind's throw: the ball off from `at` in a direction
	of its own (never flat), at least full speed."""
	var speed: float = maxf((b["v"] as Vector2).length(), SPEED)
	b["v"] = steady(Vector2.from_angle(rng.randf() * TAU) * speed)
	_burst(at, COLOURS["wind"], 12, 240.0, 0.0)


func _make_drifters(spots: Array) -> void:
	"""DRIFTERS (`<`): runs of light bricks along a row that slide back and
	forth into the empty cells beside them, at most DRIFT_REACH each way. Not
	on the grid (`cells`): the ball finds them in `movers`."""
	var runs: Array = []
	spots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for c in spots:
		if not runs.is_empty() and (runs[-1] as Array)[-1] == c - Vector2i(1, 0):
			(runs[-1] as Array).append(c)
		else:
			runs.append([c])
	for one in runs:
		var first: Vector2i = one[0]
		var last: Vector2i = one[-1]
		var left: int = 0
		while left < DRIFT_REACH and first.x - left - 1 >= 0 and not cells.has(Vector2i(first.x - left - 1, first.y)):
			left += 1
		var right: int = 0
		while right < DRIFT_REACH and last.x + right + 1 < cols and not cells.has(Vector2i(last.x + right + 1, last.y)):
			right += 1
		var phase: float = rng.randf() * TAU
		for c in one:
			var k := _brick(_cell(c.x, c.y), "land", "light", 1)
			k["home"] = (k["rect"] as Rect2).position.x
			k["lo"] = -left * cw
			k["hi"] = right * cw
			k["phase"] = phase
			bricks.append(k)
			movers.append(k)


func _reset_ball() -> void:
	balls.clear()
	balls.append(_ball(Vector2(paddle_x, PADDLE_Y - BALL_R - 8.0), Vector2.ZERO))
	state = State.AIM


func _ball(p: Vector2, v: Vector2) -> Dictionary:
	return {"p": p, "v": v, "trail": PackedVector2Array()}


func step(dt: float) -> void:
	t += dt
	_combo_t -= dt
	if _combo_t <= 0.0:
		combo = 0
	_shake = maxf(0.0, _shake - dt * 2.5)
	_muzzle = maxf(0.0, _muzzle - dt * 6.0)
	_shield_flash = maxf(0.0, _shield_flash - dt * 3.0)
	stunned = maxf(0.0, stunned - dt)
	tugged = maxf(0.0, tugged - dt)
	iced = maxf(0.0, iced - dt)
	heavy = maxf(0.0, heavy - dt)
	scorched = maxf(0.0, scorched - dt)
	hexed = maxf(0.0, hexed - dt)
	light_stolen = maxf(0.0, light_stolen - dt)
	blackout = maxf(0.0, blackout - dt)
	_banner_t = maxf(0.0, _banner_t - dt)
	_effects(dt)
	if state == State.KINGDOMS or state == State.OVER:
		queue_redraw()
		return
	for key in active.keys():
		active[key] -= dt
		if active[key] <= 0.0:
			active.erase(key)
	paddle_w = move_toward(paddle_w, (PADDLE_WIDE if active.has("wide") else PADDLE_W) * (SCORCH_SHARE if scorched > 0.0 else 1.0),
		400.0 * dt)
	var half: float = paddle_w / 2.0
	if stunned <= 0.0:
		# HEXED: the paddle goes to the other side of the arena from where it
		# is sent
		var sent: float = (ARENA.position.x + ARENA.end.x) - target_x if hexed > 0.0 else target_x
		var want: float = clampf(sent, ARENA.position.x + half, ARENA.end.x - half)
		if iced > 0.0:
			# ICED (the Ice Sniper's lance): the paddle slides, slow to start
			# and slow to stop
			var way: float = signf(want - paddle_x) if absf(want - paddle_x) > 6.0 else 0.0
			paddle_v = move_toward(paddle_v, way * PADDLE_SPEED * 0.55, (900.0 if way != 0.0 else 260.0) * dt)
			paddle_x += paddle_v * dt
		else:
			paddle_v = 0.0
			paddle_x = move_toward(paddle_x, want, PADDLE_SPEED * (0.3 if tugged > 0.0 else 1.0)
				* (HEAVY_SHARE if heavy > 0.0 else 1.0) * dt)
	if tugged > 0.0:
		paddle_x = move_toward(paddle_x, tug_x, 170.0 * dt)
	paddle_x = clampf(paddle_x, ARENA.position.x + half, ARENA.end.x - half)
	if state == State.CLEARED:
		_cleared_t -= dt
		_healed = minf(1.0, _healed + dt)
		_crumbles(dt)
		if _cleared_t <= 0.0:
			_next_map()
		queue_redraw()
		return
	if state == State.AIM:
		# THE AIM SWAYS while the ball waits (mouse, keys and a finger alike):
		# launch when it points where you want.
		if aim_sways:
			aim = deg_to_rad(-90.0 + AIM_SWAY * sin(t * AIM_SWAY_SPEED))
		for b in balls:
			b["p"] = Vector2(paddle_x, PADDLE_Y - BALL_R - 8.0)
	else:
		var speed: float = SPEED * (SLOW_SHARE if active.has("slow") else 1.0)
		_since_break += dt
		final_fire = last_few()
		if boss != null:
			boss.cornered = final_fire
		_pull(dt)
		_gusts(dt)
		_wind_ball(dt)
		for b in balls:
			if b.has("stuck"):
				# held by the MAGNET, riding the paddle
				b["p"] = Vector2(paddle_x + float(b["stuck"]), PADDLE_Y - 7.0 - ball_r())
				b["stick_t"] = float(b["stick_t"]) - dt
				if float(b["stick_t"]) <= 0.0:
					_unstick(b)
				continue
			if b["v"] != Vector2.ZERO:
				var pace: float = speed * (SLICK_SPEED if on_slick(b["p"]) else 1.0)
				b["v"] = (b["v"] as Vector2).normalized() * move_toward((b["v"] as Vector2).length(), pace, 600.0 * dt)
			b["portal_t"] = maxf(0.0, float(b.get("portal_t", 0.0)) - dt)
			b["boss_t"] = maxf(0.0, float(b.get("boss_t", 0.0)) - dt)
			_move(b, dt)
		if not _new_balls.is_empty():
			balls.append_array(_new_balls)
			_new_balls.clear()
		var kept: Array = []
		for b in balls:
			if b["p"].y > VIEW.y + 20.0:
				_burst(Vector2(b["p"].x, ARENA.end.y - 6.0), Color(1.0, 0.35, 0.3), 16, 180.0)
			else:
				kept.append(b)
		balls = kept
		if balls.is_empty():
			_lose_life()
	_lasers(dt)
	_boss_step(dt)
	_bricks_move(dt)
	_blight(dt)
	_tide(dt)
	_burns(dt)
	_capsules(dt)
	if state == State.PLAY or state == State.AIM:
		_check_cleared()
	_walls_crumble(dt)
	queue_redraw()


func set_aim(angle: float) -> void:
	"""Where the waiting ball will go, held still (pictures and the suite):
	straight up, give or take 60 degrees."""
	aim_sways = false
	aim = clampf(angle, deg_to_rad(-150.0), deg_to_rad(-30.0))


static func steady(v: Vector2) -> Vector2:
	"""A ball never runs flat along a row: at least STEEPEST_FLAT of its
	speed goes up or down, so it always comes back to the paddle."""
	var speed: float = v.length()
	if speed <= 0.0:
		return v
	var d: Vector2 = v / speed
	if absf(d.y) < STEEPEST_FLAT:
		var x: float = sqrt(1.0 - STEEPEST_FLAT * STEEPEST_FLAT)
		d = Vector2(x if d.x >= 0.0 else -x, STEEPEST_FLAT if d.y >= 0.0 else -STEEPEST_FLAT)
	return d * speed


func _lose_life() -> void:
	lives -= 1
	combo = 0
	active.clear()
	bolts.clear()
	life_lost.emit()
	if lives <= 0:
		state = State.OVER
		run_over.emit()
		return
	_say(Vector2(640, 420), "A LIFE LOST", Color(1.0, 0.45, 0.4), 30, 1.2)
	_reset_ball()


func _check_cleared() -> void:
	var done: bool
	if boss != null:
		done = not boss.alive()
	else:
		done = broken >= breakable and breakable > 0
	if not done:
		return
	state = State.CLEARED
	_cleared_t = CLEARED_SECONDS
	cleared += 1
	balls.clear()
	caps.clear()
	var pay: int = 0
	var each: Array = pays.get("maps", []) if pays.get("maps") is Array else []
	if map_index < each.size():
		pay = int(each[map_index])
	var map_name: String = str(Maps.MAPS[map_index]["name"])
	_say(Vector2(640, 380), "%s - CLEARED" % map_name.to_upper(), GOLD, 34, CLEARED_SECONDS)
	if pay > 0:
		_say(Vector2(640, 424), "+%d gold" % pay, GOLD, 24, CLEARED_SECONDS)
	_say(Vector2(640, 462), "Every land is healed." if final_map() else "The land heals.", Color(0.6, 0.95, 0.55), 20, CLEARED_SECONDS)
	map_cleared.emit(map_index)


func _next_map() -> void:
	var nxt: int = map_index + 1
	furthest = maxi(furthest, nxt)
	if nxt >= Maps.made_count():
		state = State.OVER
		run_over.emit()
		return
	_load(nxt)


# ---------------------------------------------------------------- the ball --

func _move(b: Dictionary, dt: float) -> void:
	var steps: int = 6
	var rad: float = ball_r()
	for i in steps:
		var prev: Vector2 = b["p"]
		var p: Vector2 = prev + b["v"] * dt / steps
		if p.x - rad < ARENA.position.x or p.x + rad > ARENA.end.x:
			b["v"].x = -b["v"].x
			p.x = clampf(p.x, ARENA.position.x + rad, ARENA.end.x - rad)
		if p.y - rad < ARENA.position.y:
			b["v"].y = absf(b["v"].y)
			p.y = ARENA.position.y + rad
		if b["v"].y > 0.0 and p.y + rad >= PADDLE_Y - 7.0 and p.y < PADDLE_Y + 8.0 \
				and absf(p.x - paddle_x) <= paddle_w / 2.0 + rad:
			var off: float = clampf((p.x - paddle_x) / (paddle_w / 2.0), -1.0, 1.0)
			b["v"] = Vector2.from_angle(deg_to_rad(-90.0 + off * 58.0)) * b["v"].length()
			p.y = PADDLE_Y - 7.0 - rad
			combo = 0
			_burst(p, GOLD, 8, 140.0)
			if active.has("magnet"):
				# THE MAGNET holds it where it landed
				b["stuck"] = p.x - paddle_x
				b["stick_t"] = MAGNET_HOLD
				b["v"] = Vector2.ZERO
				b["p"] = p
				return
		if active.has("shield") and b["v"].y > 0.0 and p.y + rad >= SHIELD_Y:
			b["v"].y = -absf(b["v"].y)
			p.y = SHIELD_Y - rad
			_shield_flash = 1.0
			_burst(p, COLOURS["water"], 12, 200.0, 1.4)
		if boss != null and boss.alive():
			if boss.hittable() and boss.body_rect().grow(rad).has_point(p):
				# off the boss the way it came - up off its head, down off its
				# feet - and one hit a touch: a ball pressed into it, or caught
				# between it and the hall's roof, counts once a BOSS_HIT_GAP
				b["v"].y = -absf(b["v"].y) if p.y < boss.p.y else absf(b["v"].y)
				p.y = prev.y
				if float(b.get("boss_t", 0.0)) <= 0.0:
					b["boss_t"] = BOSS_HIT_GAP
					_hit_boss(BALL_HIT * (2 if element() == "earth" else 1))
			var killed: int = boss.ball_touch(p, rad)
			if killed > 0:
				score += 300 * killed
			var ward: Vector2 = boss.ward_touch(p, rad)
			if ward != Vector2.INF and not final_fire:
				# a final fireball breaks a ward and goes on
				b["v"] = (p - ward).normalized() * (b["v"] as Vector2).length()
				p = prev
		for k in _bricks_near(p):
			var r: Rect2 = k["rect"]
			if (k["hp"] > 0 or not _breaks(k)) and r.grow(rad).has_point(p):
				if final_fire:
					# THE FINAL FIREBALL: through it, whatever it is; what can
					# break, breaks - and on to the next it touches
					if _breaks(k) and k["hp"] > 0:
						_damage(k, 99, b)
					continue
				if k["kind"] == "portal" and k.has("to"):
					# A PORTAL: in one, out of its pair, the way it was going.
					if float(b.get("portal_t", 0.0)) > 0.0:
						continue
					var out: Dictionary = k["to"]
					var d: Vector2 = (b["v"] as Vector2).normalized()
					p = (out["rect"] as Rect2).get_center() + d * (ch * 0.5 + rad + 4.0)
					b["portal_t"] = PORTAL_WAIT
					k["flash"] = 1.0
					out["flash"] = 1.0
					_burst((k["rect"] as Rect2).get_center(), PORTAL_HUES[int(k.get("pair", 0)) % PORTAL_HUES.size()], 10, 160.0, 0.0)
					_burst(p, PORTAL_HUES[int(k.get("pair", 0)) % PORTAL_HUES.size()], 10, 160.0, 0.0)
					break
				if k["kind"] == "whirl":
					# A WHIRL throws the ball off any way it likes
					p = prev
					fling(b, r.get_center())
					k["flash"] = 1.0
					score += 10
					break
				if k["kind"] == "bumper":
					# A BUMPER kicks the ball straight off its middle, faster.
					var away: Vector2 = (p - r.get_center()).normalized()
					if away == Vector2.ZERO:
						away = Vector2.UP
					b["v"] = away * maxf((b["v"] as Vector2).length(), SPEED) * BUMPER_KICK
					p = prev
					k["flash"] = 1.0
					score += 10
					_burst(r.get_center(), Color(1.0, 0.6, 0.85), 8, 200.0, 0.0)
					break
				var through: bool = active.has("fire") and _breaks(k) and not _shut(k)
				if not through:
					var was_out_x: bool = prev.x < r.position.x - rad + 0.5 or prev.x > r.end.x + rad - 0.5
					if was_out_x:
						b["v"].x = -b["v"].x
						p.x = prev.x
					else:
						b["v"].y = -b["v"].y
						p.y = prev.y
				if k["kind"] == "drift":
					# A SNOWDRIFT soaks up the ball's speed a moment
					b["v"] = (b["v"] as Vector2) * DRIFT_KEEP
				if k["kind"] == "mirror":
					# A MIRROR BENDS THE BALL it throws back: a fixed turn,
					# one way on even cells and the other on odd, so a mirror
					# can be learned and aimed off.
					var c: Vector2i = k["cell"]
					var turn: float = MIRROR_BEND if (c.x + c.y) % 2 == 0 else -MIRROR_BEND
					b["v"] = (b["v"] as Vector2).rotated(deg_to_rad(turn))
					k["flash"] = 1.0
					_burst(p, COLOURS["light"], 6, 200.0, 0.0)
				else:
					_damage(k, 99 if through else (2 if element() == "earth" else 1), b)
					if active.has("big"):
						# A BIG BALL: the bricks round what it strikes take a hit
						var home: Vector2i = k["cell"] if k.has("cell") else cell_at(r.get_center())
						for o in _bricks_in(home, 1, 1):
							if o != k:
								_damage(o, 1, null)
				break
		b["v"] = steady(b["v"])
		b["p"] = p
		var trail: PackedVector2Array = b["trail"]
		trail.append(p)
		if trail.size() > 48:
			trail.remove_at(0)
		b["trail"] = trail


func _damage(k: Dictionary, n: int, b) -> void:
	var mid: Vector2 = (k["rect"] as Rect2).get_center()
	k["flash"] = 1.0
	# a light ball - and THE FINAL FIREBALL - pass a shut brick's and a
	# Guard's shield
	var light_ball: bool = b is Dictionary and (element() == "light" or final_fire)
	if not _breaks(k) or (_shut(k) and not light_ball and not _crumbling):
		# iron, a mirror, a lock - or a rune while it is dark, a clam while it
		# is shut: nothing
		_burst(mid, Color(0.85, 0.88, 0.95), 6, 160.0)
		return
	if k["hp"] <= 0:
		return
	var warden: Variant = null if light_ball else _open_guard(k)
	if warden != null:
		# A GUARD STANDS BESIDE IT: the blow glances off its shield - and
		# every GUARD_GLANCES of them crack the shield (THE SHIELD CRACKS)
		k["warded"] = 1.0
		_burst(mid, GUARD_GLOW, 5, 120.0, 0.0)
		warden["glances"] = int(warden.get("glances", 0)) + 1
		if int(warden["glances"]) >= GUARD_GLANCES:
			warden["glances"] = 0
			var wm: Vector2 = (warden["rect"] as Rect2).get_center()
			zaps.append({"pts": PackedVector2Array([mid, wm]), "c": GUARD_GLOW, "age": 0.0})
			if int(warden["hp"]) > 1:
				_say(wm + Vector2(0, -14), "THE SHIELD CRACKS", GUARD_GLOW, 14, 0.8)
			_damage(warden, 1, null)
		return
	var shut_in: Variant = null if light_ball else _shut_guard(k)
	if shut_in != null:
		# A GUARD SHUT IN (0.166.2): no ball can get to it, so the blow on a
		# brick it shields goes through to it
		k["warded"] = 1.0
		_burst(mid, GUARD_GLOW, 5, 120.0, 0.0)
		zaps.append({"pts": PackedVector2Array([mid, (shut_in["rect"] as Rect2).get_center()]), "c": GUARD_GLOW, "age": 0.0})
		_damage(shut_in, n, b)
		return
	if k["kind"] == "fuse" and n < 99 and k["burn"] < 0.0:
		# A FUSE IS LIT, not broken: the spark runs from here
		k["burn"] = FUSE_STEP
		return
	if k["kind"] == "wood" and k["burn"] < 0.0 and b is Dictionary and (active.has("fire") or element() == "fire") and not final_fire:
		# WOOD CATCHES from a Fireball or a fire ball, and burns
		k["burn"] = WOOD_BURN
		return
	if bool(k.get("frozen", false)):
		n = 99
	if k.has("frost"):
		# FROST: the coat takes a blow of its own (fire and a touch to the
		# frozen go straight through it)
		k.erase("frost")
		_burst(mid, Color(0.88, 0.97, 1.0), 10, 170.0, 0.4)
		if n < 99:
			n -= 1
			if n <= 0:
				return
	if k["kind"] == "shell" and k["hp"] - n <= 0 and not (b is Dictionary and final_fire):
		# A SHELL HARDENS: the blow that would break it turns it to stone.
		k["kind"] = "stone"
		k["hp"] = 2
		k["most"] = 3
		_burst(mid, Color(0.93, 0.72, 0.62), 10, 140.0)
		_say(mid + Vector2(0, -12), "HARDENED", Color(0.8, 0.78, 0.74), 16, 0.7)
		return
	k["hp"] -= n
	var c: Color = _colour_of(k)
	if k["hp"] > 0:
		_burst(mid, c, 7, 150.0)
		if b is Dictionary and element() == "ice":
			# AN ICE BALL freezes what it hits: the next touch breaks it
			k["frozen"] = true
		return
	k["hp"] = 0
	if k.has("cell"):
		cells.erase(k["cell"])
		gone_at[k["cell"]] = t
	for spot in k.get("cells", []):
		cells.erase(spot)
		gone_at[spot] = t
	broken += 1
	_since_break = 0.0
	combo += 1
	_combo_t = 1.7
	best_combo = maxi(best_combo, combo)
	score += int(round(int(SCORE.get(k["kind"], 50)) * _multiplier()))
	for mark in [10, 20, 30]:
		if combo == mark and not _popped.has(mark):
			_popped.append(mark)
			_say(Vector2(640, 430), "COMBO x%d!" % combo, COLOURS["fire"], 38, 1.3)
	_shake = minf(1.0, _shake + 0.15)
	if bool(k.get("frozen", false)):
		_shatter_round(k)
	if k.has("cell"):
		_tell_mimics(k)
	if b is Dictionary:
		_ball_breaks(b, k, mid)
	if k.has("cell"):
		var under: Variant = cells.get((k["cell"] as Vector2i) + Vector2i(0, 1))
		if under != null and under["kind"] == "icicle" and under["hp"] > 0:
			drop_icicle(under)
	match k["kind"]:
		"tnt":
			_explode(mid)
		"bonus":
			_burst(mid, GOLD, 26, 260.0, 0.3)
			_drop(mid)
		"heart":
			_burst(mid, COLOURS["light"], 70, 420.0, 0.2)
			_burst(mid, BLIGHT, 40, 300.0, -0.2)
			rings.append({"p": mid, "age": 0.0, "most": 0.7, "c": COLOURS["light"], "r": CORE_BLAST + 40.0})
			_say(mid + Vector2(0, -30), "CORE SHATTERED!", COLOURS["light"], 32, 1.6)
			_shake = 1.0
			_drop(mid)
			for o in bricks:
				if o["hp"] > 0 and _breaks(o) and (o["rect"] as Rect2).get_center().distance_to(mid) < CORE_BLAST:
					_damage(o, 1, null)
		"stone":
			_burst(mid, Color(0.6, 0.58, 0.55), 18, 220.0)
		"blight", "plague":
			_burst(mid, BLIGHT, 16, 200.0, -0.3)
		"crystal":
			# A CRYSTAL SPLITS THE BALL that breaks it.
			_burst(mid, Color(0.8, 0.97, 1.0), 20, 260.0, 0.2)
			if b is Dictionary and balls.size() + _new_balls.size() < MOST_BALLS:
				var twin := _ball(b["p"], (b["v"] as Vector2).rotated(deg_to_rad(CRYSTAL_SPREAD if rng.randf() < 0.5 else -CRYSTAL_SPREAD)))
				twin["el"] = b.get("el", "")
				_new_balls.append(twin)
		"key":
			_burst(mid, GOLD, 20, 220.0, 0.2)
			keys_left -= 1
			if keys_left <= 0:
				_open_locks()
			else:
				_say(mid + Vector2(0, -14), "%d KEY%s LEFT" % [keys_left, "" if keys_left == 1 else "S"], GOLD, 16, 0.9)
		"gold":
			_burst(mid, GOLD, 30, 280.0, 1.2)
			_burst(mid, Color(1.0, 0.95, 0.6), 12, 200.0, -0.2)
			_say(mid + Vector2(0, -12), "+%d" % int(SCORE["gold"]), GOLD, 18, 0.8)
		"mix":
			_burst(mid, c, 14, 220.0)
			if b is Dictionary or _reacting > 0:
				_react(str(k["mix"]), k, mid)
		"mimic":
			_burst(mid, Color(0.7, 0.68, 0.8), 12, 180.0)
		"clam":
			# A CLAM BROKEN OPEN: its pearl always drops a bonus
			_burst(mid, Color(0.95, 0.95, 1.0), 22, 240.0, 0.3)
			_say(mid + Vector2(0, -14), "PEARL!", Color(0.92, 0.94, 1.0), 16, 0.8)
			_drop(mid)
		"bubble":
			# A BUBBLE BROKEN: one rises up the column
			_burst(mid, COLOURS["water"].lightened(0.3), 12, 160.0, -0.4)
			bubbles.append({"p": mid, "last": k.get("cell", cell_at(mid))})
		"buoy":
			_burst(mid, Color(0.95, 0.35, 0.3), 12, 180.0, 1.0)
			_burst(mid, COLOURS["water"], 8, 140.0, 1.2)
		"icicle":
			_burst(mid, Color(0.85, 0.97, 1.0), 12, 200.0, 0.8)
		"drift":
			_burst(mid, Color(0.95, 0.97, 1.0), 20, 160.0, 0.6)
		"foot":
			# A PILLAR'S FOOT GIVES WAY: all above it falls
			_burst(mid, COLOURS["earth"], 18, 220.0, 1.0)
			topple(k)
		"column", "sand":
			_burst(mid, COLOURS["earth"].lightened(0.2 if k["kind"] == "sand" else 0.0), 14, 180.0, 1.2)
		"boulder":
			_burst(mid, Color(0.55, 0.47, 0.38), 30, 260.0, 1.2)
			_say(mid + Vector2(0, -12), "+%d" % int(SCORE["boulder"]), COLOURS["earth"].lightened(0.35), 16, 0.7)
		"keg":
			# A POWDER KEG: a blast twice a TNT's
			_explode(mid, KEG_BLAST)
		"wood", "fuse":
			_burst(mid, Color(0.55, 0.35, 0.18), 14, 180.0, 1.0)
		"lava":
			# LAVA broken while it is hot: what can burn beside it catches
			_burst(mid, COLOURS["fire"], 18, 220.0, 0.6)
			_catch_round(k)
		"obsidian", "basalt":
			_burst(mid, Color(0.25, 0.2, 0.3) if k["kind"] == "obsidian" else Color(0.4, 0.38, 0.38), 20, 240.0, 1.0)
		"lantern":
			# A LANTERN BROKEN: its light stays, for good
			light_lantern(mid)
		"shadow":
			_burst(mid, COLOURS["dark"].lightened(0.2), 16, 180.0, -0.4)
		"void":
			_burst(mid, COLOURS["dark"], 26, 260.0, 0.0)
			rings.append({"p": mid, "age": 0.0, "most": 0.5, "c": COLOURS["dark"].lightened(0.4), "r": VOID_REACH})
		"ore":
			_burst(mid, GOLD, 26, 260.0, 1.2)
			_burst(mid, COLOURS["earth"], 10, 180.0, 1.0)
			_say(mid + Vector2(0, -12), "+%d ORE" % int(SCORE["ore"]), GOLD, 17, 0.8)
		_:
			# a land brick or a prism (breaking as the land it shows)
			_land_breaks(k, mid, b)
			if b is Dictionary:
				_charge(b, str(k["land"]), k, mid)
	if broken % BONUS_EVERY == 0 and caps.size() < CAPS_MOST:
		_drop(mid)


func _ball_breaks(b: Dictionary, k: Dictionary, mid: Vector2) -> void:
	"""What a ball does as it breaks a brick, by the bonuses on: SPLIT in two;
	an Elemental Ball's fire sets the bricks beside burning, its water
	splashes them."""
	if active.has("split") and balls.size() + _new_balls.size() < MOST_BALLS:
		var v: Vector2 = b["v"]
		if v != Vector2.ZERO:
			var twin := _ball(b["p"], v.rotated(deg_to_rad(SPLIT_TURN)))
			twin["el"] = b.get("el", "")
			b["v"] = v.rotated(deg_to_rad(-SPLIT_TURN))
			_new_balls.append(twin)
			_burst(mid, COLOURS["wind"], 8, 180.0, 0.0)
	var home: Vector2i = k["cell"] if k.has("cell") else cell_at(mid)
	match element():
		"fire":
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var o: Variant = cells.get(home + d)
				if o != null and o["hp"] > 0 and _breaks(o) and o["burn"] < 0.0:
					o["burn"] = 0.3
		"water":
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var o: Variant = cells.get(home + d)
				if o != null and o["hp"] > 0 and _breaks(o):
					_damage(o, 1, null)
			_burst(mid, COLOURS["water"].lightened(0.3), 12, 200.0, 1.2)


func last_few() -> bool:
	"""THE LAST FEW: LAST_FEW or fewer left to win the map (to_win()) - the
	bricks glow, and the balls bend toward them (and a boss)."""
	if state != State.PLAY:
		return false
	var left: int = to_win()
	return left > 0 and left <= LAST_FEW


func to_win() -> int:
	"""What is left to win this map: the bricks to break, or on a boss's map
	its health (boss_left())."""
	if boss != null:
		return maxi(0, boss_left()) if boss.alive() else 0
	return breakable - broken


func boss_left() -> int:
	"""THE BOSS IS THE FIELD (0.166.5): a boss's health - every brick still to
	break on its map (what it has built counts, up to BOSS_HEALS of the
	start), less what hits on it have taken. At 0 it falls."""
	var counted: int = mini(breakable, boss_base + ceili(boss_base * BOSS_HEALS))
	return counted - broken - boss_struck


func _boss_field() -> void:
	"""The boss's health kept the field's (boss_left()) whatever changed it -
	a brick broken, a brick built, a hit - and at 0 it falls, whichever way
	the last of it went."""
	if boss == null or not _fighting or not boss.alive():
		return
	if boss.field(boss_left()):
		_boss_falls()


func seeking() -> bool:
	"""The balls bend toward a brick: the last few, or none broken for
	STUCK_SECONDS."""
	return last_few() or (boss == null and state == State.PLAY and breakable - broken > 0 and _since_break >= STUCK_SECONDS)


func _wind_ball(dt: float) -> void:
	"""A WIND BALL curves toward the nearest brick it could break, WIND_TURN
	degrees a second; its target is looked for every few tenths. The last
	few lock every ball on (THE FINAL FIREBALL: LAST_TURN, LAST_TURN_ONE,
	tighter close by); balls stuck STUCK_SECONDS bend STUCK_TURN."""
	var turn: float = 0.0
	if last_few():
		turn = LAST_TURN_ONE if to_win() <= 2 else LAST_TURN
	elif element() == "wind":
		turn = WIND_TURN
	elif seeking():
		turn = STUCK_TURN
	if turn <= 0.0:
		return
	if last_few() and not _said_last:
		_said_last = true
		_say(Vector2(640, 400), "FINAL FIREBALL", COLOURS["fire"], 26, 1.3)
	var aims: Array = []
	for b in balls:
		var v: Vector2 = b["v"]
		if v == Vector2.ZERO:
			continue
		b["seek_t"] = float(b.get("seek_t", 0.0)) - dt
		if float(b["seek_t"]) <= 0.0:
			b["seek_t"] = 0.3
			var best: Vector2 = Vector2.INF
			if aims.is_empty():
				aims = _seek_targets()
			for k in aims:
				var at: Vector2 = (k["rect"] as Rect2).get_center()
				if best == Vector2.INF or at.distance_squared_to(b["p"]) < best.distance_squared_to(b["p"]):
					best = at
			if final_fire and boss != null and boss.hittable():
				# a boss's last few: it counts too, when it is the nearest
				var foe: Vector2 = (boss.body_rect() as Rect2).get_center()
				if best == Vector2.INF or foe.distance_squared_to(b["p"]) < best.distance_squared_to(b["p"]):
					best = foe
			b["seek"] = best
		var to: Vector2 = b.get("seek", Vector2.INF)
		if to == Vector2.INF:
			continue
		var toward: Vector2 = to - (b["p"] as Vector2)
		var rate: float = deg_to_rad(turn)
		if final_fire:
			# close by, never a wider turn than half the way there
			rate = minf(maxf(rate, v.length() / maxf(toward.length() * 0.5, 1.0)), deg_to_rad(LAST_TURN_MOST))
		var want: float = v.angle_to(toward)
		b["v"] = steady(v.rotated(clampf(want, -rate * dt, rate * dt)))


func _land_breaks(k: Dictionary, mid: Vector2, b) -> void:
	var c: Color = COLOURS.get(k["land"], Color.WHITE)
	match k["land"]:
		"fire":
			_burst(mid, c, 18, 240.0)
			var step: int = int(k.get("spark", 0))
			if step < FIRE_SPREAD:
				for o in _bricks_near(mid):
					if o["hp"] > 0 and o["kind"] == "land" and o["land"] == "fire" and o["burn"] < 0.0 \
							and (o["rect"] as Rect2).grow(6.0).intersects(k["rect"]):
						o["burn"] = 0.22
						o["spark"] = step + 1
		"ice":
			_burst(mid, c, 18, 280.0, 0.4)
		"water":
			_burst(mid, c, 18, 220.0, 1.6)
		"wind":
			_burst(mid, c, 14, 360.0, 0.0)
			if b is Dictionary:
				b["v"] = (b["v"] as Vector2).rotated(deg_to_rad(16.0 if rng.randf() < 0.5 else -16.0))
		"dark":
			_burst(mid, c, 16, 160.0, -0.4)
		_:
			_burst(mid, c, 16, 220.0, 0.3)


func _explode(at: Vector2, reach: float = 78.0) -> void:
	"""A BLAST (TNT, a powder keg): the TNT and kegs in `reach` are set off,
	the wood catches, everything else takes two hits (a fuse is lit)."""
	rings.append({"p": at, "age": 0.0, "most": 0.45, "c": COLOURS["fire"], "r": reach + 2.0})
	_burst(at, COLOURS["fire"], 40 if reach < 100.0 else 70, 380.0)
	_shake = 1.0
	for o in bricks:
		if o["hp"] > 0 and _breaks(o) and (o["rect"] as Rect2).get_center().distance_to(at) < reach:
			if o["kind"] == "tnt" or o["kind"] == "keg":
				o["burn"] = 0.12
			elif o["kind"] == "wood":
				if o["burn"] < 0.0:
					o["burn"] = WOOD_BURN
			else:
				_damage(o, 2, null)


func _burns(dt: float) -> void:
	# Only what was burning as the tick began: what catches in it burns from
	# the next, so a chain of wood goes a link at a time whatever the order of
	# the bricks.
	var lit: Array = bricks.filter(func(k: Dictionary) -> bool: return k["burn"] >= 0.0 and k["hp"] > 0)
	for k in lit:
		if k["burn"] >= 0.0 and k["hp"] > 0:
			k["burn"] -= dt
			if rng.randf() < 0.7:
				var r: Rect2 = k["rect"]
				parts.append({"p": Vector2(rng.randf_range(r.position.x, r.end.x), r.position.y),
					"v": Vector2(rng.randf_range(-20, 20), rng.randf_range(-90, -40)), "life": 0.45, "most": 0.45,
					"c": COLOURS["fire"], "s": 2.2, "g": -0.3})
			if k["burn"] < 0.0:
				if k["kind"] == "wood" or k["kind"] == "fuse":
					# burnt out: the fire goes on to what touches it
					_catch_round(k)
				_damage(k, 99, null)


func _blight(dt: float) -> void:
	"""THE BLIGHT GROWS BACK: every BLIGHT_EVERY, each blight brick spreads
	into one empty cell beside it that the map once held, or corrupts a land
	brick beside it into plague-stone - at most BLIGHT_MOST at a time."""
	_blight_t -= dt
	if _blight_t > 0.0:
		return
	_blight_t = BLIGHT_EVERY
	var grown: int = 0
	var sources: Array = []
	for k in bricks:
		if k["kind"] == "blight" and k["hp"] > 0:
			sources.append(k)
	for k in sources:
		if grown >= BLIGHT_MOST:
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var c: Vector2i = k["cell"] + d
			if footprint.has(c) and not cells.has(c) and not _ball_near(_cell(c.x, c.y)):
				var nk := _add(c.x, c.y, "blight", "", 1)
				nk["flash"] = 1.0
				breakable += 1
				_burst(_cell(c.x, c.y).get_center(), BLIGHT, 8, 90.0, -0.2)
				grown += 1
				break
			var near: Variant = cells.get(c)
			if near != null and near["kind"] == "land" and near["hp"] > 0 and rng.randf() < CORRUPT_CHANCE:
				# THE PLAGUE CORRUPTS: a land brick beside the blight turns to
				# plague-stone, two hits
				near["kind"] = "plague"
				near["hp"] = 2
				near["most"] = 2
				near["flash"] = 1.0
				_burst((near["rect"] as Rect2).get_center(), BLIGHT, 8, 90.0, -0.2)
				grown += 1
				break
	if grown > 0:
		_say(Vector2(640, 470), "The blight spreads", BLIGHT.lightened(0.3), 18, 1.0)
	# broken bricks stay in the list for the drawing's sake; the grid forgets them
	bricks = bricks.filter(func(k): return k["hp"] > 0 or not _breaks(k) or k["kind"] != "blight")


func _ball_near(r: Rect2) -> bool:
	for b in balls:
		if r.grow(BALL_R * 3.0).has_point(b["p"]):
			return true
	return false


# ---------------------------------------------------------------- the elements mixed --

func _rune_lit(k: Dictionary) -> bool:
	"""A RUNE is breakable only while lit: RUNE_LIT of every RUNE_CYCLE, each
	at its own moment."""
	return fmod(t + float(k.get("phase", 0.0)), RUNE_CYCLE) < RUNE_LIT


func clam_open(k: Dictionary) -> float:
	"""How open a clam is, 0 shut to 1: open CLAM_OPEN of every CLAM_CYCLE,
	easing a fifth of a second either side."""
	var u: float = fmod(t + float(k.get("phase", 0.0)), CLAM_CYCLE)
	if u >= CLAM_OPEN:
		return 0.0
	return clampf(minf(u, CLAM_OPEN - u) / 0.2, 0.0, 1.0)


func _shut(k: Dictionary) -> bool:
	"""Hard to every blow right now: a rune while it is dark, a clam while it
	is shut."""
	match k["kind"]:
		"rune":
			return not _rune_lit(k)
		"clam":
			return clam_open(k) <= 0.0
	return false


# ---------------------------------------------------------------- the tide --

func tide_level() -> float:
	"""How far up its mark the tide stands, 0 to 1."""
	if tide_mark < 0:
		return 0.0
	var u: float = tide_t - (TIDE_EVERY - 2.0 * TIDE_RISE - TIDE_HIGH)
	if u <= 0.0:
		return 0.0
	if u < TIDE_RISE:
		return smoothstep(0.0, 1.0, u / TIDE_RISE)
	if u < TIDE_RISE + TIDE_HIGH:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (u - TIDE_RISE - TIDE_HIGH) / TIDE_RISE)


func tide_line() -> float:
	"""The tide's mark in px: the top of its row."""
	return MAP_TOP + tide_mark * (ch + gap) - gap


func tide_y() -> float:
	"""Where the water stands now, in px."""
	return lerpf(field_bottom() + 6.0, tide_line(), tide_level())


func tide_now() -> void:
	"""The tide comes in at once (the Tide King's call), when it is out."""
	var low: float = TIDE_EVERY - 2.0 * TIDE_RISE - TIDE_HIGH
	if tide_mark >= 0 and tide_t < low - 0.05:
		tide_t = low - 0.05


func _tide(dt: float) -> void:
	"""The tide's cycle: it says when it comes in, and rebuilds as it stands."""
	if tide_mark < 0:
		return
	var low: float = TIDE_EVERY - 2.0 * TIDE_RISE - TIDE_HIGH
	var before: float = tide_t
	tide_t += dt
	if before < low and tide_t >= low:
		_say(Vector2(640, 470), "THE TIDE COMES IN", COLOURS["water"].lightened(0.35), 20, 1.4)
	if before < low + TIDE_RISE and tide_t >= low + TIDE_RISE:
		tide_rebuild()
	if tide_t >= TIDE_EVERY:
		tide_t -= TIDE_EVERY


func tide_rebuild() -> int:
	"""THE TIDE REBUILDS WHAT YOU LEFT: every empty cell under the mark that
	the map once held, broken more than TIDE_WAIT ago, comes back as a water
	brick - the oldest first, TIDE_MOST at most."""
	var spots: Array = []
	for c in footprint.keys():
		if c.y < tide_mark or cells.has(c) or TIDE_KEEP.has(str(placed.get(c, ""))):
			continue
		if t - float(gone_at.get(c, t)) < TIDE_WAIT:
			continue
		var r := _cell(c.x, c.y)
		if _ball_near(r) or (hall.size != Vector2.ZERO and hall.grow(2.0).intersects(r)):
			continue
		spots.append(c)
	spots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return float(gone_at[a]) < float(gone_at[b]))
	var made: int = 0
	for c in spots.slice(0, TIDE_MOST):
		var k := _add(c.x, c.y, "land", "water", 1)
		k["tide"] = true
		k["flash"] = 1.0
		gone_at.erase(c)
		breakable += 1
		made += 1
		_burst(_cell(c.x, c.y).get_center(), COLOURS["water"].lightened(0.2), 8, 120.0, -0.3)
	if made > 0:
		_say(Vector2(640, 500), "THE TIDE REBUILDS %d" % made, COLOURS["water"].lightened(0.35), 18, 1.2)
	return made


func _waters(dt: float) -> void:
	"""Buoys float up into the holes above them; bubbles rise and burst."""
	for k in buoys:
		if k["hp"] <= 0:
			continue
		var home: Vector2i = k["cell"]
		if k.has("rise"):
			k["rise"] = float(k["rise"]) - dt
			var to: Rect2 = _cell(home.x, home.y)
			var r: Rect2 = to
			r.position.y += (ch + gap) * clampf(float(k["rise"]) / BUOY_RISE, 0.0, 1.0)
			k["rect"] = r
			if float(k["rise"]) <= 0.0:
				k.erase("rise")
				k["rect"] = to
			continue
		var up: Vector2i = home + Vector2i(0, -1)
		if footprint.has(up) and not cells.has(up) and not _ball_near(_cell(up.x, up.y)) and int(k.get("risen", 0)) < BUOY_MOST:
			k["risen"] = int(k.get("risen", 0)) + 1
			cells.erase(home)
			gone_at[home] = t
			cells[up] = k
			k["cell"] = up
			k["rise"] = BUOY_RISE
			_grid_ver += 1
			_burst(_cell(home.x, home.y).get_center(), COLOURS["water"].lightened(0.3), 5, 90.0, -0.5)
	for bu in bubbles:
		bu["p"].y -= BUBBLE_SPEED * dt
		var c: Vector2i = cell_at(bu["p"])
		if c != bu["last"]:
			bu["last"] = c
			var o: Variant = cells.get(c)
			if o != null and (o["hp"] > 0 or not _breaks(o)):
				_damage(o, 1, null)
				bu["dead"] = true
				_burst(bu["p"], COLOURS["water"].lightened(0.45), 10, 150.0, -0.2)
		if bu["p"].y < ARENA.position.y + 6.0:
			bu["dead"] = true
	bubbles = bubbles.filter(func(bu): return not bu.get("dead", false))


static func reaction_of(a: String, b: String) -> String:
	"""What two lands do when the ball mixes them: a named reaction, or a
	clash."""
	var pair: Array = [a, b]
	pair.sort()
	return str(REACTIONS.get("%s+%s" % [pair[0], pair[1]], "clash"))


func _charge(b: Dictionary, land: String, k: Dictionary, at: Vector2) -> void:
	"""THE BALL CARRIES WHAT IT BREAKS: a land brick broken while it carries
	another land sets the two off, and it carries the new one on."""
	var had: String = str(b.get("el", ""))
	if element() != "":
		# AN ELEMENTAL BALL keeps its land: every other land sets it off
		had = element()
	if had != "" and had != land:
		_react(reaction_of(had, land), k, at)
	b["el"] = element() if element() != "" else land


func _react(kind: String, k: Dictionary, at: Vector2) -> void:
	"""A REACTION round the brick `k` at `at` (its cell, even broken). A
	reaction that breaks a mixed brick sets that one off too, REACT_DEPTH
	deep at most."""
	if _reacting >= REACT_DEPTH:
		return
	_reacting += 1
	var lands: Array = MIX_LANDS.get(kind, ["light", "light"])
	var colour: Color = COLOURS[lands[0]].lerp(COLOURS[lands[1]], 0.5)
	score += 100
	if kind != "clash" and t - _react_said >= REACT_WORD_GAP:
		_react_said = t
		_say(at + Vector2(0, -16), str(REACTION_WORDS.get(kind, "!")), colour.lightened(0.2), 20, 0.7)
	var home: Vector2i = k["cell"] if k.has("cell") else cell_at(at)
	match kind:
		"steam":
			# fire and ice: a blast of steam round it
			rings.append({"p": at, "age": 0.0, "most": 0.4, "c": Color(0.95, 0.97, 1.0), "r": 70.0})
			_burst(at, Color(0.95, 0.97, 1.0), 30, 260.0, -0.6)
			for o in _bricks_in(home, 1, 1):
				_damage(o, 2, null)
		"firestorm":
			# fire and wind: the row burns, outward from it, FIRESTORM_REACH each way
			_burst(at, COLOURS["fire"], 24, 320.0, -0.2)
			for o in bricks:
				if o["hp"] > 0 and _breaks(o) and o.has("cell") and (o["cell"] as Vector2i).y == home.y and o["burn"] < 0.0 \
						and absi((o["cell"] as Vector2i).x - home.x) <= FIRESTORM_REACH:
					o["burn"] = 0.05 + absf((o["cell"] as Vector2i).x - home.x) * 0.04
		"glacier":
			# water and ice: everything round it freezes; a frozen brick breaks
			# at a touch, and its frozen neighbours shatter with it
			rings.append({"p": at, "age": 0.0, "most": 0.5, "c": COLOURS["ice"], "r": 90.0})
			for o in _bricks_in(home, 2, 1):
				o["frozen"] = true
				o["flash"] = 1.0
		"storm":
			# water and wind: lightning jumps to the bricks round it
			var near: Array = []
			for o in bricks:
				if o["hp"] > 0 and _breaks(o) and (o["rect"] as Rect2).get_center().distance_to(at) < STORM_REACH:
					near.append(o)
			near.shuffle()
			for o in near.slice(0, STORM_JUMPS):
				_zap(at, (o["rect"] as Rect2).get_center(), Color(0.75, 0.9, 1.0))
				_damage(o, 1, null)
		"magma":
			# earth and fire: lava drips down the column, through what is below
			drips.append({"p": at, "left": DRIP_DEPTH, "last": home})
		"blizzard":
			# ice and wind: shards up the column above it
			var hit: int = 0
			var top: Vector2 = at
			for row in range(home.y - 1, -1, -1):
				var o: Variant = cells.get(Vector2i(home.x, row))
				if o != null and o["hp"] > 0 and _breaks(o):
					_damage(o, 1, null)
					top = (o["rect"] as Rect2).get_center()
					hit += 1
					if hit >= SHARD_DEPTH:
						break
			_zap(at, top + Vector2(0, -10), COLOURS["ice"].lightened(0.3))
		"eclipse":
			# light and dark: the ECLIPSE_MOST bricks of the land most left nearest
			# it take a hit
			var count: Dictionary = {}
			for o in bricks:
				if o["hp"] > 0 and o["kind"] == "land":
					count[o["land"]] = int(count.get(o["land"], 0)) + 1
			var most: String = ""
			for land in count:
				if most == "" or int(count[land]) > int(count[most]):
					most = land
			_eclipse = 0.5
			var dimmed: Array = []
			for o in bricks:
				if o["hp"] > 0 and o["kind"] == "land" and o["land"] == most:
					dimmed.append(o)
			dimmed.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return (x["rect"] as Rect2).get_center().distance_to(at) < (y["rect"] as Rect2).get_center().distance_to(at))
			for o in dimmed.slice(0, ECLIPSE_MOST):
				_damage(o, 1, null)
		_:
			# any other two: a clash - a spark into a brick beside it
			_burst(at, Color(1.0, 0.95, 0.8), 14, 300.0, 0.0)
			var round_it: Array = _bricks_in(home, 1, 1)
			if not round_it.is_empty():
				_damage(round_it[rng.randi_range(0, round_it.size() - 1)], 1, null)
	_reacting -= 1


func _bricks_in(home: Vector2i, wide: int, tall: int) -> Array:
	"""The breakable bricks standing within `wide` cells across and `tall`
	down or up of `home`, on the grid."""
	var out: Array = []
	for row in range(home.y - tall, home.y + tall + 1):
		for col in range(home.x - wide, home.x + wide + 1):
			var o: Variant = cells.get(Vector2i(col, row))
			if o != null and o["hp"] > 0 and _breaks(o) and not out.has(o):
				out.append(o)
	return out


func _zap(from: Vector2, to: Vector2, c: Color) -> void:
	"""A bolt drawn a moment, jagged, from `from` to `to`."""
	var pts := PackedVector2Array([from])
	var steps: int = 5
	for i in range(1, steps):
		var at: Vector2 = from.lerp(to, float(i) / steps)
		pts.append(at + Vector2(rng.randf_range(-9, 9), rng.randf_range(-9, 9)))
	pts.append(to)
	zaps.append({"pts": pts, "age": 0.0, "c": c})


func _shatter_round(k: Dictionary) -> void:
	"""A frozen brick broken: its frozen neighbours shatter a moment later."""
	var home: Vector2i = k["cell"] if k.has("cell") else cell_at((k["rect"] as Rect2).get_center())
	_burst((k["rect"] as Rect2).get_center(), COLOURS["ice"].lightened(0.3), 10, 200.0, 0.6)
	for o in _bricks_in(home, 1, 1):
		if bool(o.get("frozen", false)) and not o.has("shatter"):
			o["shatter"] = SHATTER_STEP


func _tell_mimics(k: Dictionary) -> void:
	"""A MIMIC becomes what broke beside it: the brick's kind, land and full
	strength."""
	if not ["land", "stone", "tnt", "bonus", "gold", "crystal", "shell", "plague", "prism", "mix", "blight"].has(k["kind"]):
		return
	var home: Vector2i = k["cell"]
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var m: Variant = cells.get(home + d)
		if m != null and m["kind"] == "mimic" and m["hp"] > 0:
			m["kind"] = k["kind"]
			m["land"] = k["land"]
			m["hp"] = int(k["most"])
			m["most"] = int(k["most"])
			if k.has("mix"):
				m["mix"] = k["mix"]
			if k["kind"] == "prism":
				m["phase"] = k.get("phase", 0.0)
				prisms.append(m)
			m["flash"] = 1.0
			_burst((m["rect"] as Rect2).get_center(), Color(0.75, 0.7, 0.9), 10, 160.0, 0.0)


func _open_locks() -> void:
	"""Every key broken: every lock shatters (they never counted to clear)."""
	_say(Vector2(640, 400), "THE LOCKS OPEN!", GOLD, 28, 1.2)
	for o in bricks:
		if o["kind"] == "lock" and o["hp"] >= 0:
			o["kind"] = "opened"
			o["hp"] = 0
			if o.has("cell"):
				cells.erase(o["cell"])
			_burst((o["rect"] as Rect2).get_center(), GOLD, 14, 240.0, 0.4)


func _bricks_move(dt: float) -> void:
	"""What moves among the bricks each tick: drifters slide, prisms turn,
	lava falls, frozen bricks shatter, buoys float, bubbles rise, bolts and
	the eclipse fade."""
	_waters(dt)
	_icicles(dt)
	_earth(dt)
	_fire(dt)
	_dark(dt)
	_voids(dt)
	for k in movers:
		if k["hp"] > 0:
			# a Rect2 is a value: set a copy, then put it back
			var r: Rect2 = k["rect"]
			if k.has("kite"):
				var w: float = 0.5 + 0.5 * sin(t * KITE_SPEED + float(k["phase"]))
				r.position.y = float(k["home"]) + lerpf(float(k["lo"]), float(k["hi"]), w)
			else:
				var u: float = 0.5 + 0.5 * sin(t * DRIFT_SPEED + float(k["phase"]))
				r.position.x = float(k["home"]) + lerpf(float(k["lo"]), float(k["hi"]), u)
			k["rect"] = r
	for k in prisms:
		if k["hp"] > 0 and k["kind"] == "prism":
			k["land"] = ELEMENTS[int(floor((t + float(k["phase"])) / PRISM_EVERY)) % ELEMENTS.size()]
	for k in bricks:
		if k.has("shatter") and k["hp"] > 0:
			k["shatter"] -= dt
			if k["shatter"] <= 0.0:
				k.erase("shatter")
				_damage(k, 99, null)
		if k.has("warded"):
			k["warded"] -= dt * 2.5
			if k["warded"] <= 0.0:
				k.erase("warded")
	for d in drips:
		d["p"].y += DRIP_SPEED * dt
		var c: Vector2i = cell_at(d["p"])
		if c != d["last"]:
			d["last"] = c
			var o: Variant = cells.get(c)
			if o != null and o["hp"] > 0 and _breaks(o):
				_damage(o, 1, null)
				d["left"] -= 1
		if rng.randf() < 0.6:
			parts.append({"p": d["p"] + Vector2(rng.randf_range(-4, 4), 0), "v": Vector2(rng.randf_range(-20, 20), -40),
				"life": 0.4, "most": 0.4, "c": COLOURS["fire"], "s": 2.4, "g": 0.4})
		if d["left"] <= 0 or d["p"].y > field_bottom() + 20.0:
			d["dead"] = true
	drips = drips.filter(func(d): return not d.get("dead", false))
	for z in zaps:
		z["age"] += dt
	zaps = zaps.filter(func(z): return z["age"] < 0.3)
	_eclipse = maxf(0.0, _eclipse - dt)


func _pull(dt: float) -> void:
	"""THE LAST FEW BRICKS CALL THE BALL: PULL_BELOW or fewer standing that
	can be hurt now - a guarded brick waits for its Guard - and no boss, a
	rising ball turns toward the nearest."""
	var left: int = breakable - broken
	pulling = false
	if boss != null or left <= 0 or left > PULL_BELOW * 8:
		return
	var targets: Array = []
	for k in _seek_targets():
		targets.append((k["rect"] as Rect2).get_center())
	pulling = not targets.is_empty() and targets.size() <= PULL_BELOW
	if not pulling:
		return
	for b in balls:
		var v: Vector2 = b["v"]
		if v.y >= 0.0 or targets.is_empty():
			continue
		var best: Vector2 = targets[0]
		for at in targets:
			if (at as Vector2).distance_to(b["p"]) < best.distance_to(b["p"]):
				best = at
		var want: float = v.angle_to(best - (b["p"] as Vector2))
		var turn: float = clampf(want, -deg_to_rad(PULL_TURN) * dt, deg_to_rad(PULL_TURN) * dt)
		b["v"] = v.rotated(turn)


# ---------------------------------------------------------------- bonuses --

func _drop(at: Vector2) -> void:
	var kind: String = BONUS_ORDER[_next_bonus % BONUS_ORDER.size()]
	_next_bonus += 1
	if _next_bonus % LIFE_EVERY == 0:
		kind = "life"
	var cap := {"p": at, "kind": kind}
	if kind == "element":
		cap["land"] = ELEMENTS[_next_land % ELEMENTS.size()]
		_next_land += 1
	caps.append(cap)


func _capsules(dt: float) -> void:
	for c in caps:
		c["p"].y += CAPSULE_FALL * dt
		if absf(c["p"].x - paddle_x) < paddle_w / 2.0 + 20.0 and absf(c["p"].y - PADDLE_Y) < 14.0:
			c["taken"] = true
			if c["kind"] == "element":
				ball_land = str(c.get("land", "fire"))
			_take(c["kind"])
	caps = caps.filter(func(c): return not c.get("taken", false) and c["p"].y < VIEW.y + 30.0)


func bonus_name(kind: String) -> String:
	"""A bonus's name - the Elemental Ball's by its land."""
	if kind == "element":
		return "%s Orb" % ball_land.capitalize() if ball_land != "" else "Elemental"
	return str(BONUS[kind]["name"])


func bonus_colour(kind: String) -> Color:
	if kind == "element" and ball_land != "":
		return COLOURS[ball_land]
	if kind == "life":
		return HEART_RED
	return COLOURS[BONUS[kind]["land"]]


func _take(kind: String) -> void:
	var info: Dictionary = BONUS[kind]
	_say(Vector2(paddle_x, PADDLE_Y - 46.0), bonus_name(kind).to_upper() + "!", bonus_colour(kind), 26, 1.1)
	_burst(Vector2(paddle_x, PADDLE_Y - 8.0), bonus_colour(kind), 24, 260.0)
	if kind == "life":
		lives = mini(lives + 1, LIVES_MOST)
		return
	if kind == "element":
		for b in balls:
			b["el"] = ball_land
	if kind == "multi":
		var more: Array = []
		for b in balls:
			for a in [-22.0, 22.0]:
				if balls.size() + more.size() < MOST_BALLS and b["v"] != Vector2.ZERO:
					more.append(_ball(b["p"], (b["v"] as Vector2).rotated(deg_to_rad(a))))
		balls.append_array(more)
	else:
		active[kind] = float(info["secs"])


func _lasers(dt: float) -> void:
	if active.has("laser") and state == State.PLAY:
		_laser_t = maxf(0.0, _laser_t - dt)
		# by itself on a computer; on a phone a tap fires it (tap())
		if _laser_t <= 0.0 and not touch_slider:
			_fire_lasers()
	for bolt in bolts:
		bolt["p"].y -= 950.0 * dt
		if boss != null and boss.alive():
			if boss.hittable() and boss.body_rect().has_point(bolt["p"]):
				_hit_boss(1)
				bolt["dead"] = true
				continue
			if boss.ball_touch(bolt["p"], 4.0) > 0 or boss.ward_touch(bolt["p"], 3.0) != Vector2.INF:
				bolt["dead"] = true
				continue
		for k in _bricks_near(bolt["p"]):
			if (k["hp"] > 0 or not _breaks(k)) and (k["rect"] as Rect2).has_point(bolt["p"]):
				_damage(k, 1, null)
				bolt["dead"] = true
				break
		if bolt["p"].y < ARENA.position.y:
			bolt["dead"] = true
	bolts = bolts.filter(func(b): return not b.get("dead", false))


func _fire_lasers() -> void:
	"""The Laser's volley: a bolt from each end of the paddle."""
	_laser_t = LASER_EVERY
	_muzzle = 1.0
	for side in [-1.0, 1.0]:
		var from := Vector2(paddle_x + side * (paddle_w / 2.0 - 12.0), PADDLE_Y - 14.0)
		bolts.append({"p": from, "from": from})


func _multiplier() -> float:
	"""The combo's multiplier (x4 at most), doubled by a Dark Ball."""
	return minf(4.0, 1.0 + floorf(combo / 5.0) * 0.5) * (2.0 if element() == "dark" else 1.0)


# ---------------------------------------------------------------- the boss --

func _boss_step(dt: float) -> void:
	if boss != null:
		boss.step(dt, state == State.PLAY)
		if state == State.PLAY:
			boss.work_balls(balls, dt)


func gale_from(at: Vector2, reach: float, kick: float) -> void:
	"""THE GALE KING'S STAMP: every ball within `reach` of `at` is knocked
	away from it sideways, its speed kept."""
	for b in balls:
		var v: Vector2 = b["v"]
		if v == Vector2.ZERO or (b["p"] as Vector2).distance_to(at) > reach:
			continue
		var away: float = 1.0 if (b["p"] as Vector2).x >= at.x else -1.0
		b["v"] = steady((v + Vector2(away * kick, 0.0)).normalized() * v.length())
		_burst(b["p"], COLOURS["wind"], 6, 160.0, 0.0)


func stun_paddle(seconds: float, at: Vector2, land: String) -> void:
	"""A boss's shot hit the paddle (crownfallboss.gd)."""
	stunned = seconds
	_burst(at, COLOURS.get(land, Color.WHITE), 20, 240.0)
	_say(Vector2(paddle_x, PADDLE_Y - 40.0), "STUNNED", Color(1.0, 0.5, 0.45), 22, 0.9)


func on_slick(at: Vector2) -> bool:
	for band in slicks:
		if at.y >= float(band["y0"]) and at.y <= float(band["y1"]):
			return true
	return false


func drop_icicle(k: Dictionary) -> void:
	"""AN ICICLE LETS GO: off the grid, falling."""
	if k["hp"] <= 0:
		return
	k["hp"] = 0
	if k.has("cell"):
		cells.erase(k["cell"])
		gone_at[k["cell"]] = t
	broken += 1
	score += int(SCORE["icicle"])
	falling.append({"p": (k["rect"] as Rect2).get_center(), "last": k.get("cell", cell_at((k["rect"] as Rect2).get_center()))})
	_burst((k["rect"] as Rect2).get_center(), Color(0.85, 0.97, 1.0), 6, 90.0, 0.5)


func _icicles(dt: float) -> void:
	"""The Snow Sprite's icicles fall in their time; falling icicles break
	the first brick they meet, ICICLE_HIT, or stun the paddle."""
	for k in hanging:
		if k["hp"] > 0:
			k["hang"] = float(k["hang"]) - dt
			if float(k["hang"]) <= 0.0:
				drop_icicle(k)
	hanging = hanging.filter(func(k: Dictionary) -> bool: return k["hp"] > 0)
	for f in falling:
		f["p"].y += ICICLE_SPEED * dt
		var c: Vector2i = cell_at(f["p"])
		if c != f["last"]:
			f["last"] = c
			var o: Variant = cells.get(c)
			if o != null and (o["hp"] > 0 or not _breaks(o)):
				_damage(o, ICICLE_HIT, null)
				f["dead"] = true
				_burst(f["p"], Color(0.85, 0.97, 1.0), 14, 220.0, 0.8)
				continue
		if (f["p"] as Vector2).y >= PADDLE_Y - 8.0 and (f["p"] as Vector2).y <= PADDLE_Y + 8.0 \
				and absf((f["p"] as Vector2).x - paddle_x) < paddle_w / 2.0 + 4.0:
			stun_paddle(ICICLE_STUN, f["p"], "ice")
			f["dead"] = true
		if (f["p"] as Vector2).y > VIEW.y:
			f["dead"] = true
	falling = falling.filter(func(f: Dictionary) -> bool: return not f.get("dead", false))


func frost_at(at: Vector2) -> bool:
	"""THE FROST KING'S YOUNG: a frost coat on the brick where one lands.
	Whether it took."""
	var o: Variant = cells.get(cell_at(at))
	if o == null or o["hp"] <= 0 or not _breaks(o) or o.has("frost") or ["heart", "guard"].has(str(o["kind"])):
		return false
	o["frost"] = true
	o["flash"] = 1.0
	_burst((o["rect"] as Rect2).get_center(), Color(0.88, 0.97, 1.0), 10, 120.0, 0.3)
	return true


func chill_from(at: Vector2, reach: float, keep: float) -> void:
	"""THE FROST KING'S BREATH: every ball within `reach` slowed to `keep`
	of its speed (it gathers pace again)."""
	for b in balls:
		if b["v"] != Vector2.ZERO and (b["p"] as Vector2).distance_to(at) <= reach:
			b["v"] = (b["v"] as Vector2) * keep
			_burst(b["p"], COLOURS["ice"].lightened(0.3), 6, 120.0, 0.2)


func ice_paddle(seconds: float, at: Vector2) -> void:
	"""THE ICE SNIPER'S LANCE: the paddle slides for `seconds`."""
	iced = seconds
	paddle_v = 0.0
	_burst(at, COLOURS["ice"].lightened(0.3), 20, 220.0)
	_say(Vector2(paddle_x, PADDLE_Y - 40.0), "ICED!", COLOURS["ice"].lightened(0.3), 22, 0.9)


func hang_icicle(x: float) -> bool:
	"""THE SNOW SPRITE: an icicle under the lowest standing brick of a column
	near `x`, in the empty cell below it, to fall in ICICLE_HANG."""
	var col: int = int(floor((x - FIELD_X) / cw))
	for d in [0, 1, -1, 2, -2, 3, -3]:
		var c: int = col + d
		if c < 0 or c >= cols:
			continue
		for row in range(rows_count - 2, -1, -1):
			var above: Variant = cells.get(Vector2i(c, row))
			if above == null:
				continue
			var spot := Vector2i(c, row + 1)
			if cells.has(spot) or (hall.size != Vector2.ZERO and hall.grow(2.0).intersects(_cell(spot.x, spot.y))) \
					or _ball_near(_cell(spot.x, spot.y)):
				continue
			var k := _add(spot.x, spot.y, "icicle", "ice", 1)
			k["hang"] = ICICLE_HANG
			k["flash"] = 1.0
			hanging.append(k)
			footprint[spot] = true
			breakable += 1
			return true
	return false


func ice_wall(row: int, c0: int, c1: int, most: int) -> int:
	"""THE FROST MAGE'S WALL: packed ice, two hits, in the empty cells of
	`row` from `c0` to `c1`, `most` at most, none by a ball. How many."""
	var made: int = 0
	for c in range(maxi(0, c0), mini(cols - 1, c1) + 1):
		var spot := Vector2i(c, row)
		if made >= most or row < 0 or row >= rows_count or cells.has(spot) or _ball_near(_cell(c, row)):
			continue
		var k := _add(c, row, "packed", "ice", 2)
		k["flash"] = 1.0
		footprint[spot] = true
		gone_at.erase(spot)
		breakable += 1
		made += 1
	if made > 0:
		_burst(_cell(int((c0 + c1) / 2.0), row).get_center(), COLOURS["ice"].lightened(0.3), 24, 200.0, 0.4)
	return made


func avalanche(c0: int, c1: int, below: float, most: int) -> int:
	"""THE GLACIER LORD'S AVALANCHE: snow pours down the columns from `c0` to
	`c1`, filling the empty cells the map once held under `below` with
	snowdrifts, the highest first, `most` at most, none by a ball. How many."""
	var spots: Array = []
	for c in range(maxi(0, c0), mini(cols - 1, c1) + 1):
		for row in rows_count:
			var spot := Vector2i(c, row)
			if footprint.has(spot) and not cells.has(spot) and _cell(c, row).position.y > below and not _ball_near(_cell(c, row)):
				spots.append(spot)
	spots.sort_custom(func(a: Vector2i, b2: Vector2i) -> bool: return a.y < b2.y)
	var made: int = 0
	for spot in spots.slice(0, most):
		var k := _add(spot.x, spot.y, "drift", "ice", 2)
		k["flash"] = 1.0
		gone_at.erase(spot)
		breakable += 1
		made += 1
	return made


func topple(foot: Dictionary) -> int:
	"""A PILLAR FALLS: every brick stacked on `foot`'s cell, up to the first
	gap (or a core, a key, a lock, a Guard, iron), lets go as rubble. How
	many."""
	if not foot.has("cell"):
		return 0
	var home: Vector2i = foot["cell"]
	var n: int = 0
	var row: int = home.y - 1
	while row >= 0:
		var o: Variant = cells.get(Vector2i(home.x, row))
		if o == null or not o.has("cell") or o["hp"] <= 0 or not _breaks(o) or TOPPLE_KEEP.has(str(o["kind"])):
			break
		_let_go(o)
		n += 1
		row -= 1
	if n > 0:
		score += int(round(TOPPLE_SCORE * n * _multiplier()))
		_say((foot["rect"] as Rect2).get_center() + Vector2(0, -16), "TOPPLED!", COLOURS["earth"].lightened(0.4), 18, 0.8)
		_shake = minf(1.0, _shake + 0.3)
	return n


func _let_go(k: Dictionary) -> void:
	"""A brick of a falling pillar: off the grid, rubble now."""
	var mid: Vector2 = (k["rect"] as Rect2).get_center()
	k["hp"] = 0
	cells.erase(k["cell"])
	gone_at[k["cell"]] = t
	broken += 1
	score += int(round(int(SCORE.get(k["kind"], 50)) * _multiplier()))
	rubble.append({"p": mid, "last": k["cell"], "c": _colour_of(k)})
	_burst(mid, _colour_of(k), 4, 80.0, 1.0)


func _earth(dt: float) -> void:
	"""The earth's own motion: rubble falling, sand settling, the tremor."""
	for f in rubble:
		f["p"].y += RUBBLE_SPEED * dt
		var c: Vector2i = cell_at(f["p"])
		if c != f["last"]:
			f["last"] = c
			var o: Variant = cells.get(c)
			if o != null and (o["hp"] > 0 or not _breaks(o)):
				_damage(o, RUBBLE_HIT, null)
				f["dead"] = true
				_burst(f["p"], f["c"], 10, 200.0, 1.2)
				continue
		if (f["p"] as Vector2).y > field_bottom() + ch:
			f["dead"] = true
			_burst(f["p"], f["c"], 6, 120.0, 1.0)
	rubble = rubble.filter(func(f: Dictionary) -> bool: return not f.get("dead", false))
	_sand_t -= dt
	if _sand_t <= 0.0:
		_sand_t = SAND_STEP
		_settle()
	if tremors and state == State.PLAY:
		tremor_t += dt
		if tremor_t >= TREMOR_EVERY:
			tremor_t = 0.0
			_rumbled = false
			tremor_now(false)
		elif tremor_t >= TREMOR_EVERY - TREMOR_WARN:
			# THE RUMBLE before it: the arena trembles, and says so once
			_shake = maxf(_shake, 0.25)
			if not _rumbled:
				_rumbled = true
				_say(Vector2(640, 420), "THE GROUND RUMBLES...", COLOURS["earth"].lightened(0.35), 20, TREMOR_WARN)


func _settle() -> void:
	"""SAND SETTLES: each sand brick with an empty cell under it (on the map's
	rows, not the hall, no ball there) drops into it - the lowest first."""
	var sands: Array = []
	for k in bricks:
		if k["kind"] == "sand" and k["hp"] > 0 and k.has("cell"):
			sands.append(k)
	sands.sort_custom(func(a: Dictionary, b2: Dictionary) -> bool: return (a["cell"] as Vector2i).y > (b2["cell"] as Vector2i).y)
	for k in sands:
		var at: Vector2i = k["cell"]
		var below := at + Vector2i(0, 1)
		if below.y >= rows_count or cells.has(below):
			continue
		var r: Rect2 = _cell(below.x, below.y)
		if (hall.size != Vector2.ZERO and hall.grow(2.0).intersects(r)) or _ball_near(r):
			continue
		cells.erase(at)
		gone_at[at] = t
		k["cell"] = below
		k["rect"] = r
		cells[below] = k
		gone_at.erase(below)
		_grid_ver += 1


func tremor_now(all: bool) -> int:
	"""THE GROUND SHAKES (an earth map's tremor, the Stone King's stomp, the
	Mountain Lord's quake): every pillar on a cracked foot falls - with `all`,
	every pillar - and every ball is jolted. How many feet gave way."""
	_shake = 1.0
	var feet: Array = []
	for k in bricks:
		if k["kind"] == "foot" and k["hp"] > 0 and (all or k["hp"] < k["most"]):
			feet.append(k)
	for k in feet:
		_damage(k, 99, null)
	for b in balls:
		if b["v"] != Vector2.ZERO:
			b["v"] = steady((b["v"] as Vector2).rotated(deg_to_rad(rng.randf_range(-TREMOR_TURN, TREMOR_TURN))))
	_burst(Vector2(640, field_bottom()), COLOURS["earth"], 30, 260.0, 1.4)
	_say(Vector2(640, 400), "QUAKE!" if all else "TREMOR!", COLOURS["earth"].lightened(0.35), 26, 0.9)
	return feet.filter(func(k: Dictionary) -> bool: return k["hp"] <= 0).size()


func weigh_paddle(seconds: float, at: Vector2) -> void:
	"""THE ROCK SNIPER'S SHOT: the paddle weighed down for `seconds`."""
	heavy = seconds
	_burst(at, COLOURS["earth"], 20, 220.0, 1.2)
	_say(Vector2(paddle_x, PADDLE_Y - 40.0), "HEAVY!", COLOURS["earth"].lightened(0.35), 22, 0.9)


func pile_sand(at: Vector2) -> bool:
	"""THE STONE KING'S YOUNG: sand where one lands, when the cell is empty,
	on the map's grid and not the hall. Whether it took."""
	var c: Vector2i = cell_at(at)
	if c.x < 0 or c.x >= cols or c.y < 0 or c.y >= maxi(rows_count, 1) or cells.has(c):
		return false
	if hall.size != Vector2.ZERO and hall.grow(2.0).intersects(_cell(c.x, c.y)):
		return false
	var k := _add(c.x, c.y, "sand", "earth", 1)
	k["flash"] = 1.0
	footprint[c] = true
	breakable += 1
	_burst(_cell(c.x, c.y).get_center(), COLOURS["earth"].lightened(0.2), 12, 140.0, 0.6)
	return true


func raise_pillar(x: float, tall: int) -> int:
	"""THE EARTH MAGE'S PILLAR: in the column at `x`, on the lowest empty cell
	with something under it (or the map's last row), a foot and up to
	`tall` - 1 stones above it, in empty cells below the hall, none by a
	ball. How many bricks."""
	var col: int = int(floor((x - FIELD_X) / cw))
	if col < 0 or col >= cols:
		return 0
	var top: int = cell_at(Vector2(x, hall.end.y)).y + 2 if hall.size != Vector2.ZERO else 0
	var base: int = -1
	for row in range(rows_count - 1, top - 1, -1):
		if not cells.has(Vector2i(col, row)):
			base = row
			break
	if base < 0:
		return 0
	var made: int = 0
	for row in range(base, maxi(top, base - tall + 1) - 1, -1):
		var spot := Vector2i(col, row)
		if cells.has(spot) or _ball_near(_cell(col, row)):
			break
		var k := _add(col, row, "foot" if made == 0 else "column", "earth", 2)
		k["flash"] = 1.0
		footprint[spot] = true
		gone_at.erase(spot)
		breakable += 1
		made += 1
	if made > 0:
		_burst(_cell(col, base).get_center(), COLOURS["earth"], 20, 200.0, 1.0)
	return made


func rockfall(c0: int, c1: int, below: float, most: int) -> int:
	"""THE MOUNTAIN LORD'S ROCKFALL: boulders (three hits) dropped into the
	empty pairs of cells the map once held under `below`, from `c0` to `c1`,
	the highest first, `most` at most, none by a ball. How many."""
	var made: int = 0
	for row in rows_count:
		var c: int = maxi(0, c0)
		while c < mini(cols - 1, c1) and made < most:
			var a := Vector2i(c, row)
			var b2 := Vector2i(c + 1, row)
			var ra: Rect2 = _cell(a.x, a.y)
			var rb: Rect2 = _cell(b2.x, b2.y)
			if footprint.has(a) and footprint.has(b2) and not cells.has(a) and not cells.has(b2) \
					and ra.position.y > below and not _ball_near(ra) and not _ball_near(rb):
				var rock := _brick(ra.merge(rb), "boulder", "earth", 3)
				rock["cells"] = [a, b2]
				rock["flash"] = 1.0
				bricks.append(rock)
				cells[a] = rock
				cells[b2] = rock
				gone_at.erase(a)
				gone_at.erase(b2)
				breakable += 1
				made += 1
				c += 2
			else:
				c += 1
	return made


func _catch_round(k: Dictionary) -> void:
	"""FIRE SPREADS from a brick burnt out (wood, a fuse) or from lava broken:
	the wood, fuse, TNT and kegs touching it catch."""
	var spots: Array = k.get("cells", [k["cell"]] if k.has("cell") else [])
	for home in spots:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var o: Variant = cells.get((home as Vector2i) + d)
			if o == null or o == k or o["hp"] <= 0 or o["burn"] >= 0.0 or not CATCHES.has(str(o["kind"])):
				continue
			o["burn"] = WOOD_BURN if o["kind"] == "wood" else (FUSE_STEP if o["kind"] == "fuse" else 0.12)


func _fire(dt: float) -> void:
	"""Fire's own motion: lava cooling, lava bombs falling, fire on the floor,
	the eruption."""
	var playing_now: bool = state == State.PLAY
	if playing_now:
		for k in bricks:
			if k["kind"] == "lava" and k["hp"] > 0:
				k["cool"] = float(k.get("cool", LAVA_COOL)) - dt
				if float(k["cool"]) <= 0.0:
					# LAVA LEFT TOO LONG cools into basalt
					k["kind"] = "basalt"
					k["hp"] = 3
					k["most"] = 3
					k["flash"] = 1.0
					_burst((k["rect"] as Rect2).get_center(), Color(0.55, 0.5, 0.5), 10, 90.0, -0.6)
	for f in bombs:
		f["p"].y += BOMB_SPEED * dt
		var c: Vector2i = cell_at(f["p"])
		if c != f["last"]:
			var before: Vector2i = f["last"]
			f["last"] = c
			if cells.has(c):
				# a bomb on what stands sets as lava over it
				_set_lava(before)
				f["dead"] = true
				_burst(f["p"], COLOURS["fire"], 12, 200.0, 0.8)
				continue
		var at: Vector2 = f["p"]
		if at.y >= PADDLE_Y - 8.0 and at.y <= PADDLE_Y + 8.0 and absf(at.x - paddle_x) < paddle_w / 2.0 + 6.0:
			stun_paddle(BOMB_STUN, at, "fire")
			f["dead"] = true
		if at.y > VIEW.y:
			f["dead"] = true
	bombs = bombs.filter(func(f: Dictionary) -> bool: return not f.get("dead", false))
	for f in patches:
		if float(f["warn"]) > 0.0:
			f["warn"] = float(f["warn"]) - dt
			continue
		f["life"] = float(f["life"]) - dt
		if playing_now and not bool(f["hit"]) and absf(paddle_x - float(f["x"])) < (paddle_w + PATCH_W) / 2.0:
			f["hit"] = true
			stun_paddle(STUN_SECONDS, Vector2(paddle_x, PADDLE_Y), "fire")
	patches = patches.filter(func(f: Dictionary) -> bool: return float(f["life"]) > 0.0)
	if eruptions and playing_now:
		erupt_t += dt
		if erupt_t >= ERUPT_EVERY:
			erupt_t = 0.0
			_erupt_warned = false
			erupt_now(ERUPT_BOMBS)
		elif erupt_t >= ERUPT_EVERY - ERUPT_WARN:
			_shake = maxf(_shake, 0.25)
			if not _erupt_warned:
				_erupt_warned = true
				_say(Vector2(640, 420), "THE VOLCANO RUMBLES...", COLOURS["fire"], 20, ERUPT_WARN)


func _set_lava(spot: Vector2i) -> bool:
	"""Lava in `spot` when it is empty, on the map's grid, not the hall, and no
	ball is there. Whether it took."""
	if spot.x < 0 or spot.x >= cols or spot.y < 0 or spot.y >= maxi(rows_count, 1) or cells.has(spot):
		return false
	var r: Rect2 = _cell(spot.x, spot.y)
	if (hall.size != Vector2.ZERO and hall.grow(2.0).intersects(r)) or _ball_near(r):
		return false
	var k := _add(spot.x, spot.y, "lava", "fire", 1)
	k["cool"] = LAVA_COOL
	k["flash"] = 1.0
	footprint[spot] = true
	gone_at.erase(spot)
	breakable += 1
	return true


func lava_bomb(x: float, from_y: float) -> void:
	"""A LAVA BOMB (an eruption, the Fire Mage's meteor) falling from `from_y`."""
	bombs.append({"p": Vector2(x, from_y), "last": cell_at(Vector2(x, from_y))})


func erupt_now(n: int) -> void:
	"""THE VOLCANO ERUPTS (a fire map's eruption, the Fire King's call, the
	Inferno's): `n` lava bombs from the top of the arena, spread across the
	field."""
	for i in n:
		lava_bomb(FIELD_X + (i + rng.randf_range(0.15, 0.85)) * FIELD_W / n, ARENA.position.y + 4.0)
	_shake = 1.0
	_say(Vector2(640, 400), "ERUPTION!", COLOURS["fire"], 26, 0.9)


func fire_patch(x: float) -> void:
	"""THE FLAME SPRITE: fire on the floor at `x`, embers first."""
	patches.append({"x": clampf(x, ARENA.position.x + PATCH_W / 2.0, ARENA.end.x - PATCH_W / 2.0),
		"warn": PATCH_WARN, "life": PATCH_LIFE, "hit": false})


func scorch_paddle(seconds: float, at: Vector2) -> void:
	"""THE FIRE SNIPER'S SHOT: the paddle scorched short for `seconds`."""
	scorched = seconds
	_burst(at, COLOURS["fire"], 24, 240.0, -0.3)
	_say(Vector2(paddle_x, PADDLE_Y - 40.0), "SCORCHED!", COLOURS["fire"], 22, 0.9)


func lava_at(at: Vector2) -> bool:
	"""THE FIRE KING'S YOUNG: lava where one lands on nothing (whether it took),
	and wood or a fuse where it lands set alight."""
	var c: Vector2i = cell_at(at)
	var o: Variant = cells.get(c)
	if o != null:
		if o["hp"] > 0 and o["burn"] < 0.0 and (o["kind"] == "wood" or o["kind"] == "fuse"):
			o["burn"] = WOOD_BURN if o["kind"] == "wood" else FUSE_STEP
		return false
	if _set_lava(c):
		_burst(_cell(c.x, c.y).get_center(), COLOURS["fire"], 12, 140.0, -0.3)
		return true
	return false


func light_sources() -> Array:
	"""THE LIGHT ON A DARK MAP, as [where, how far]: each ball's (less while
	the Wisp has stolen it, more for a light Elemental Ball) and the paddle's
	(none in the Beholder's eclipse) - all less at nightfall. Lanterns are
	kept on the bricks (`lamp`)."""
	var share: float = NIGHT_SHARE if night_left > 0.0 else 1.0
	var reach: float = LIGHT_BALL * share * (DIM_SHARE if light_stolen > 0.0 else 1.0) * (1.6 if element() == "light" else 1.0)
	var out: Array = []
	for b in balls:
		out.append([b["p"], reach])
	if blackout <= 0.0:
		out.append([Vector2(paddle_x, PADDLE_Y), LIGHT_PADDLE * share])
	return out


func lamp_reach() -> float:
	"""How far a lantern lights now: none in the eclipse, less at nightfall."""
	if blackout > 0.0:
		return 0.0
	return LANTERN_R * (NIGHT_SHARE if night_left > 0.0 else 1.0)


func is_lit(k: Dictionary, lights: Array) -> bool:
	"""Whether light falls on brick `k` now."""
	var mid: Vector2 = (k["rect"] as Rect2).get_center()
	if not k.has("lamp"):
		var near: float = INF
		for at in lanterns:
			near = minf(near, mid.distance_to(at))
		k["lamp"] = near
	if float(k["lamp"]) <= lamp_reach():
		return true
	for light in lights:
		if mid.distance_to(light[0]) <= float(light[1]):
			return true
	return false


func _dark(dt: float) -> void:
	"""A dark map's own motion: what the light finds shows and the rest fades,
	shadow bricks heal in the dark, and the night falls."""
	if not dark:
		return
	var lights: Array = light_sources()
	var playing_now: bool = state == State.PLAY
	for k in bricks:
		if k["hp"] <= 0 and _breaks(k):
			continue
		var on: bool = is_lit(k, lights)
		k["seen"] = move_toward(float(k.get("seen", 0.0)), 1.0 if on else 0.0, dt * (8.0 if on else 1.0 / SEEN_FADE))
		if k["kind"] == "shadow" and playing_now and k["hp"] < k["most"]:
			# A SHADOW BRICK HEALS in the dark
			if float(k["seen"]) < 0.2:
				k["heal"] = float(k.get("heal", 0.0)) + dt
				if float(k["heal"]) >= SHADOW_HEAL:
					k["heal"] = 0.0
					k["hp"] += 1
			else:
				k["heal"] = 0.0
	if not playing_now:
		return
	night_left = maxf(0.0, night_left - dt)
	night_t += dt
	if night_t >= NIGHT_EVERY:
		night_t = 0.0
		_night_warned = false
		night_left = NIGHT_SECONDS
		_say(Vector2(640, 400), "NIGHTFALL", COLOURS["dark"].lightened(0.45), 26, 0.9)
	elif night_t >= NIGHT_EVERY - NIGHT_WARN and not _night_warned:
		_night_warned = true
		_say(Vector2(640, 420), "THE DARK DEEPENS...", COLOURS["dark"].lightened(0.45), 20, NIGHT_WARN)


func _voids(dt: float) -> void:
	"""VOID WELLS draw the balls near them in."""
	voids = voids.filter(func(k: Dictionary) -> bool: return k["hp"] > 0)
	if voids.is_empty() or state != State.PLAY:
		return
	for b in balls:
		var v: Vector2 = b["v"]
		if v == Vector2.ZERO:
			continue
		for w in voids:
			var to: Vector2 = (w["rect"] as Rect2).get_center() - (b["p"] as Vector2)
			if to.length() <= VOID_REACH:
				var turn: float = clampf(v.angle_to(to), -deg_to_rad(VOID_TURN) * dt, deg_to_rad(VOID_TURN) * dt)
				b["v"] = steady(v.rotated(turn))
				break


func light_lantern(at: Vector2) -> void:
	"""A LANTERN LIT (broken): its light for good."""
	lanterns.append(at)
	_relamp()
	_burst(at, Color(1.0, 0.9, 0.55), 30, 240.0, -0.3)
	rings.append({"p": at, "age": 0.0, "most": 0.6, "c": Color(1.0, 0.9, 0.55), "r": LANTERN_R})
	_say(at + Vector2(0, -14), "LIGHT!", Color(1.0, 0.92, 0.6), 18, 0.8)


func _relamp() -> void:
	"""The lanterns changed: every brick works out again how near one is."""
	for k in bricks:
		k.erase("lamp")


func snuff() -> bool:
	"""THE SHADOW KING SNUFFS the last lantern lit. Whether there was one."""
	if lanterns.is_empty():
		return false
	var at: Vector2 = lanterns.pop_back()
	_relamp()
	_burst(at, COLOURS["dark"], 24, 200.0, -0.3)
	_say(at + Vector2(0, -14), "SNUFFED", COLOURS["dark"].lightened(0.4), 18, 0.8)
	return true


func shade_at(at: Vector2) -> bool:
	"""THE SHADOW KING'S YOUNG: the brick where one lands turns to shadow (two
	hits, healing in the dark) - not a core, a Guard, a key, a lock, a lantern
	or a void. Whether it did."""
	var o: Variant = cells.get(cell_at(at))
	if o == null or not o.has("cell") or o["hp"] <= 0 or not _breaks(o) or DARK_KEEP.has(str(o["kind"])):
		return false
	o["kind"] = "shadow"
	o["land"] = "dark"
	o["hp"] = 2
	o["most"] = 2
	o.erase("frost")
	o.erase("frozen")
	o["flash"] = 1.0
	_burst((o["rect"] as Rect2).get_center(), COLOURS["dark"], 10, 120.0, -0.3)
	return true


func open_void(around: Rect2) -> bool:
	"""THE VOID MAGE OPENS A WELL in the empty cell the map once held nearest
	the field below his hall, no ball by it. Whether he did."""
	var toward := Vector2(around.get_center().x, around.end.y + 150.0)
	var best := Vector2i(-1, -1)
	for c in footprint.keys():
		var spot: Vector2i = c
		var r: Rect2 = _cell(spot.x, spot.y)
		if cells.has(spot) or r.position.y <= around.end.y or _ball_near(r):
			continue
		if best.x < 0 or r.get_center().distance_to(toward) < _cell(best.x, best.y).get_center().distance_to(toward):
			best = spot
	if best.x < 0:
		return false
	var k := _add(best.x, best.y, "void", "dark", 3)
	k["flash"] = 1.0
	gone_at.erase(best)
	breakable += 1
	voids.append(k)
	rings.append({"p": (k["rect"] as Rect2).get_center(), "age": 0.0, "most": 0.6, "c": COLOURS["dark"].lightened(0.4), "r": VOID_REACH})
	return true


func hex_paddle(seconds: float, at: Vector2) -> void:
	"""THE SHADE SNIPER'S SHOT: left and right swapped for `seconds`."""
	hexed = seconds
	_burst(at, COLOURS["dark"].lightened(0.3), 22, 220.0, -0.2)
	_say(Vector2(paddle_x, PADDLE_Y - 40.0), "HEXED!", COLOURS["dark"].lightened(0.45), 22, 0.9)


func dim_balls(seconds: float) -> void:
	"""THE WISP STEALS THE LIGHT: the balls' light at DIM_SHARE for `seconds`."""
	light_stolen = seconds
	for b in balls:
		_burst(b["p"], COLOURS["dark"].lightened(0.3), 10, 140.0, -0.2)
	_say(Vector2(640, 420), "YOUR LIGHT IS STOLEN", COLOURS["dark"].lightened(0.45), 20, 0.9)


func eclipse_now(seconds: float) -> void:
	"""THE BEHOLDER'S ECLIPSE: only the balls give light for `seconds`."""
	blackout = seconds
	_say(Vector2(640, 400), "ECLIPSE!", COLOURS["dark"].lightened(0.45), 28, 1.0)


func final_map() -> bool:
	"""Whether this is the last map of all - the seventh crown - with every
	kingdom made."""
	return map_index == Maps.MAPS.size() - 1 and Maps.made_count() == Maps.MAPS.size() \
		and Maps.made_count() == Maps.KINGDOMS.size() * Maps.MAPS_A_KINGDOM


func tug_paddle(seconds: float, to_x: float, land: String) -> void:
	"""THE HARPOONER'S HOOK: the paddle slowed and pulled toward `to_x`."""
	tugged = seconds
	tug_x = to_x
	_burst(Vector2(paddle_x, PADDLE_Y - 6.0), COLOURS.get(land, Color.WHITE), 18, 220.0)
	_say(Vector2(paddle_x, PADDLE_Y - 40.0), "HOOKED!", Color(1.0, 0.65, 0.35), 22, 0.9)


func splash_from(at: Vector2, reach: float, kick: float) -> void:
	"""A SPLASH (the Undine, the Leviathan surfacing): every ball within
	`reach` thrown straight away from `at`, a touch faster."""
	for b in balls:
		var v: Vector2 = b["v"]
		if v == Vector2.ZERO or (b["p"] as Vector2).distance_to(at) > reach:
			continue
		var away: Vector2 = ((b["p"] as Vector2) - at).normalized()
		if away == Vector2.ZERO:
			away = Vector2.DOWN
		b["v"] = steady(away * maxf(v.length(), SPEED) * kick)
		_burst(b["p"], COLOURS["water"], 6, 160.0, 0.0)
	_burst(at, COLOURS["water"].lightened(0.3), 30, 300.0, 0.8)
	_say(at + Vector2(0, -40), "SPLASH!", COLOURS["water"].lightened(0.4), 20, 0.7)


func plant_water(at: Vector2) -> bool:
	"""THE TIDE KING'S YOUNG: a water brick where one lands, when the cell is
	empty, on the map's grid and not the hall. Whether it took."""
	var c: Vector2i = cell_at(at)
	if c.x < 0 or c.x >= cols or c.y < 0 or c.y >= maxi(rows_count, 1) or cells.has(c):
		return false
	if hall.size != Vector2.ZERO and hall.grow(2.0).intersects(_cell(c.x, c.y)):
		return false
	var k := _add(c.x, c.y, "land", "water", 1)
	k["flash"] = 1.0
	k["tide"] = true
	footprint[c] = true
	breakable += 1
	_burst(_cell(c.x, c.y).get_center(), COLOURS["water"], 12, 140.0, -0.2)
	return true


func wave_brick(x: float, below: float) -> bool:
	"""THE LEVIATHAN'S WAKE: a water brick in an empty cell of the column at
	`x` the map once held, under `below`, no ball near. Whether one was."""
	var col: int = int(floor((x - FIELD_X) / cw))
	if col < 0 or col >= cols:
		return false
	var spots: Array = []
	for row in rows_count:
		var c := Vector2i(col, row)
		var r := _cell(col, row)
		if footprint.has(c) and not cells.has(c) and r.position.y > below and not _ball_near(r):
			spots.append(c)
	if spots.is_empty():
		return false
	var c: Vector2i = spots[rng.randi_range(0, spots.size() - 1)]
	var k := _add(c.x, c.y, "land", "water", 1)
	k["flash"] = 1.0
	k["tide"] = true
	gone_at.erase(c)
	breakable += 1
	return true


func burst_at(at: Vector2, land: String, n: int) -> void:
	_burst(at, COLOURS.get(land, Color.WHITE), n, 220.0)


func rebuild_near(n: int, around: Rect2, kind: String = "stone") -> void:
	"""THE BUSH MAGE REBUILDS: the `n` broken cells nearest its hall (cells the
	map once held, empty now) come back as stone, two hits - or, the Tide
	Mage's, as bubble bricks; the Frost Mage's, frost-coated ice; the Dust
	Sprite's, sand; the Fire Mage's, obsidian; the Void Mage's, shadow."""
	var spots: Array = []
	for c in footprint.keys():
		if not cells.has(c):
			spots.append(c)
	var foot: Vector2 = Vector2(around.get_center().x, around.end.y)
	spots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _cell(a.x, a.y).get_center().distance_to(foot) < _cell(b.x, b.y).get_center().distance_to(foot))
	var made: int = 0
	for c in spots:
		if made >= n:
			break
		if _ball_near(_cell(c.x, c.y)):
			continue
		var k: Dictionary
		if kind == "bubble":
			k = _add(c.x, c.y, "bubble", "water", 1)
		elif kind == "frost":
			k = _add(c.x, c.y, "land", "ice", 1)
			k["frost"] = true
		elif kind == "sand":
			k = _add(c.x, c.y, "sand", "earth", 1)
		elif kind == "obsidian":
			k = _add(c.x, c.y, "obsidian", "fire", 3)
			k["most"] = 4
		elif kind == "shadow":
			k = _add(c.x, c.y, "shadow", "dark", 2)
		else:
			k = _add(c.x, c.y, "stone", "", 2)
			k["most"] = 3
		k["flash"] = 1.0
		gone_at.erase(c)
		breakable += 1
		made += 1
		_burst(_cell(c.x, c.y).get_center(), Color(0.6, 0.58, 0.55), 8, 120.0, -0.2)
	if made > 0:
		_say(Vector2(around.get_center().x, around.end.y + 30.0), "REBUILT", Color(0.75, 0.72, 0.68), 16, 0.8)


func plant_blight(at: Vector2) -> void:
	"""A SMALL SLIME PLANTS THE PLAGUE where it lands: a blight brick in the
	cell, when the cell is empty, on the map's grid and not the hall."""
	var c: Vector2i = cell_at(at)
	if c.x < 0 or c.x >= cols or c.y < 0 or c.y >= maxi(rows_count, 1) or cells.has(c):
		return
	if hall.size != Vector2.ZERO and hall.grow(2.0).intersects(_cell(c.x, c.y)):
		return
	var k := _add(c.x, c.y, "blight", "", 1)
	k["flash"] = 1.0
	footprint[c] = true
	breakable += 1
	_burst(_cell(c.x, c.y).get_center(), BLIGHT, 10, 120.0, -0.2)


func _crumble() -> void:
	"""THE BOSS FALLEN, ITS WALLS COME DOWN: every brick still standing that
	can break is given a moment in CRUMBLE_SECONDS to fall (no score - the
	map is already won). Iron and mirrors stay: they are the place."""
	for k in bricks:
		if k["hp"] > 0 and _breaks(k):
			var r: Rect2 = k["rect"]
			# from the hall outward: nearer the ruler, sooner
			var far: float = clampf(r.get_center().distance_to(boss.p) / 700.0, 0.0, 1.0)
			k["crumble"] = 0.15 + far * CRUMBLE_SECONDS + rng.randf_range(0.0, 0.25)


func _crumbles(dt: float) -> void:
	for k in bricks:
		if k.has("crumble") and k["hp"] > 0:
			k["crumble"] -= dt
			if k["crumble"] <= 0.0:
				k["hp"] = 0
				var mid: Vector2 = (k["rect"] as Rect2).get_center()
				_burst(mid, _colour_of(k), 10, 160.0, 1.2)
				_burst(mid, Color(0.6, 0.95, 0.55), 4, 90.0, -0.5)


func _hit_boss(n: int) -> void:
	"""A HIT ON THE BOSS: `n` bricks' worth off what is left to win
	(boss_left()); its splits come from hits alone (boss.hit())."""
	if boss == null or not boss.alive():
		return
	var land: String = boss.land
	score += 200
	_burst(boss.p, COLOURS.get(land, Color.WHITE), 10, 200.0)
	boss_struck += n
	# its health was the field's, so less `n` it is again
	if boss.hit(n):
		_boss_falls()
	else:
		_boss_field()


func _boss_falls() -> void:
	"""THE BOSS DEFEATED - by a hit or by the last brick it needed."""
	var land: String = boss.land
	score += 5000
	_burst(boss.p, COLOURS.get(land, Color.WHITE), 80, 460.0, 0.2)
	_burst(boss.p, GOLD, 40, 320.0, -0.2)
	rings.append({"p": boss.p, "age": 0.0, "most": 0.9, "c": GOLD, "r": 220.0})
	# The moment is the boss's: what was on screen goes, so the cleared
	# lines always stand under it.
	words.clear()
	if boss.crowned and final_map():
		# THE SEVENTH CROWN: the end of Crownfall
		_say(Vector2(640, 330), "THE LAST CROWN FALLS!", GOLD, 40, CLEARED_SECONDS)
	elif boss.crowned:
		_say(Vector2(640, 330), "THE CROWN FALLS!", GOLD, 38, CLEARED_SECONDS)
	else:
		_say(Vector2(640, 330), "%s IS DEFEATED!" % str(boss.title).to_upper(), GOLD, 34, CLEARED_SECONDS)
	_crumble()
	_shake = 1.0


# ---------------------------------------------------------------- effects --

func _effects(dt: float) -> void:
	_frame_life(dt)
	for k in bricks:
		k["flash"] = maxf(0.0, k["flash"] - dt * 5.0)
	for p in parts:
		p["p"] += p["v"] * dt
		p["v"] *= 0.94
		p["v"].y += 260.0 * dt * p.get("g", 1.0)
		p["life"] -= dt
	parts = parts.filter(func(p): return p["life"] > 0.0)
	if parts.size() > PARTS_MOST:
		parts = parts.slice(parts.size() - PARTS_MOST)
	for w in words:
		w["p"].y -= 30.0 * dt
		w["life"] -= dt
		w["age"] += dt
	words = words.filter(func(w): return w["life"] > 0.0)
	for r in rings:
		r["age"] += dt
	rings = rings.filter(func(r): return r["age"] < r["most"])


func _frame_life(dt: float) -> void:
	"""The frame's own motion: the rolling score and its pops, the coin, the
	hearts, the multiplier's badge."""
	if score != _score_was:
		if score > _score_was:
			if not score_pops.is_empty() and float(score_pops[-1]["age"]) < 0.25:
				score_pops[-1]["n"] = int(score_pops[-1]["n"]) + score - _score_was
			else:
				score_pops = [{"n": score - _score_was, "age": 0.0}]
		else:
			shown_score = float(score)
			score_pops.clear()
		_score_was = score
	shown_score = move_toward(shown_score, float(score), maxf(400.0, absf(float(score) - shown_score) * 6.0) * dt)
	for pop in score_pops:
		pop["age"] = float(pop["age"]) + dt
	score_pops = score_pops.filter(func(pop: Dictionary) -> bool: return float(pop["age"]) < 0.9)
	var g: int = gold_now()
	if _gold_was >= 0 and g > _gold_was:
		_gold_bounce = 1.0
	_gold_was = g
	_gold_bounce = maxf(0.0, _gold_bounce - dt * 2.5)
	if lives < _lives_was:
		_heart_crack = 1.0
	_lives_was = lives
	_heart_crack = maxf(0.0, _heart_crack - dt * 1.6)
	var m: float = _multiplier()
	if m > _mult_was:
		_mult_pop = 1.0
	_mult_was = m
	_mult_pop = maxf(0.0, _mult_pop - dt * 3.0)


func _burst(at: Vector2, c: Color, n: int, speed: float, gravity: float = 1.0) -> void:
	if parts.size() > PARTS_MOST / 2:
		# the air is full (a Fireball through a crowd): a third as many
		n = ceili(n * 0.35)
	for i in n:
		var v := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.3, 1.0) * speed
		var life: float = rng.randf_range(0.35, 0.8)
		parts.append({"p": at, "v": v, "life": life, "most": life, "c": c, "s": rng.randf_range(1.5, 3.2), "g": gravity})


func _say(at: Vector2, text: String, c: Color, size: int, life: float = 0.9) -> void:
	"""A WORD THAT POPS UP never lands on another (the owner, of the sketch:
	"SHIELD" and "3 BALLS!" stacked on top of each other): it is kept inside
	the arena, clear of the side panels, and moved up past every word on
	screen it would touch - asked again after each move, so a word moved off
	one cannot land on the next."""
	var w_px: float = _word_width(text, size)
	var half: float = w_px / 2.0 + 10.0
	at.x = clampf(at.x, ARENA.position.x + half, ARENA.end.x - half)
	for attempt in WORD_TRIES:
		var mine := _word_rect(at, w_px, size)
		var clash: Dictionary = {}
		for w in words:
			if _word_rect(w["p"], _word_width(w["text"], int(w["size"])), int(w["size"])).intersects(mine):
				clash = w
				break
		if clash.is_empty():
			break
		at.y = float(clash["p"].y) - float(clash["size"]) - WORD_GAP
	at.y = maxf(at.y, ARENA.position.y + size + 4.0)
	words.append({"p": at, "text": text, "life": life, "most": life, "c": c, "size": size, "age": 0.0})


func _word_width(text: String, size: int) -> float:
	if _bold == null:
		return text.length() * size * 0.6
	return _bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


static func _word_rect(at: Vector2, width: float, size: int) -> Rect2:
	"""Where a word drawn centred on `at` (its baseline) stands."""
	return Rect2(at.x - width / 2.0 - 6.0, at.y - size, width + 12.0, size + 6.0)


func _colour_of(k: Dictionary) -> Color:
	match k["kind"]:
		"stone":
			return Color(0.56, 0.54, 0.52)
		"iron":
			return Color(0.42, 0.45, 0.52)
		"mirror":
			return MIRROR_BLUE.lightened(0.4)
		"tnt":
			return Color(0.86, 0.16, 0.14)
		"bonus":
			return GOLD
		"blight":
			return BLIGHT
		"heart":
			return COLOURS["light"]
		"crystal":
			return Color(0.72, 0.93, 1.0)
		"key":
			return GOLD
		"gold":
			return Color(1.0, 0.76, 0.18)
		"shell":
			return Color(0.93, 0.74, 0.64)
		"mimic":
			return Color(0.58, 0.56, 0.68)
		"plague":
			return Color(0.3, 0.42, 0.22)
		"mix":
			return COLOURS[MIX_LANDS.get(str(k.get("mix", "clash")), ["light"])[0]]
		"rune":
			return Color(0.95, 0.8, 0.4)
		"packed":
			return Color(0.45, 0.72, 0.95)
		"drift":
			return Color(0.92, 0.95, 1.0)
		"foot":
			return Color(0.78, 0.36, 0.16)
		"column":
			return Color(0.7, 0.58, 0.42)
		"boulder":
			return Color(0.66, 0.56, 0.46)
		"ore":
			return Color(0.42, 0.38, 0.36)
		"sand":
			return Color(0.93, 0.8, 0.52)
		"wood":
			return Color(0.72, 0.48, 0.26)
		"fuse":
			return Color(0.62, 0.5, 0.34)
		"keg":
			return Color(0.6, 0.36, 0.2)
		"obsidian":
			return Color(0.22, 0.18, 0.3)
		"lava":
			return Color(1.0, 0.45, 0.1)
		"basalt":
			return Color(0.36, 0.34, 0.35)
		"lantern":
			return Color(0.95, 0.8, 0.42)
		"shadow":
			return Color(0.34, 0.3, 0.42)
		"void":
			return Color(0.14, 0.06, 0.24)
		"bumper":
			return Color(1.0, 0.6, 0.85)
		"portal":
			return Color(0.6, 0.3, 0.9)
		"lock":
			return Color(0.42, 0.45, 0.52)
	return COLOURS.get(k["land"], Color.WHITE)


func _draw_frost_coat(r: Rect2) -> void:
	"""A FROST COAT: a pale sheet over the brick, rime along its top."""
	_cv.draw_rect(r, Color(0.86, 0.95, 1.0, 0.42))
	_cv.draw_rect(Rect2(r.position, Vector2(r.size.x, maxf(2.0, r.size.y * 0.25))), Color(1, 1, 1, 0.55))
	var step: float = maxf(4.0, r.size.x / 5.0)
	var x: float = r.position.x + step * 0.5
	while x < r.end.x - 1.0:
		_cv.draw_line(Vector2(x, r.position.y), Vector2(x, r.position.y + r.size.y * 0.45), Color(1, 1, 1, 0.65), 1.0)
		x += step
	_cv.draw_rect(r, Color(0.9, 0.98, 1.0, 0.85), false, 1.0)


func _draw_patch(f: Dictionary) -> void:
	"""FIRE ON THE FLOOR: embers on the paddle's line while it warns, then
	flames licking up."""
	var x0: float = float(f["x"]) - PATCH_W / 2.0
	var y: float = PADDLE_Y + 9.0
	if float(f["warn"]) > 0.0:
		var blink: float = 0.4 + 0.6 * absf(sin(t * 14.0))
		for i in 7:
			draw_circle(Vector2(x0 + 4.0 + i * (PATCH_W - 8.0) / 6.0, y), 2.0, Color(1.0, 0.45, 0.15, blink))
		return
	var fade: float = clampf(float(f["life"]) / 0.5, 0.0, 1.0)
	draw_rect(Rect2(x0, y - 4.0, PATCH_W, 6.0), Color(1.0, 0.35, 0.1, 0.35 * fade))
	for i in 6:
		var fx: float = x0 + 5.0 + i * (PATCH_W - 10.0) / 5.0
		var h: float = 14.0 + 8.0 * absf(sin(t * 9.0 + i * 1.7))
		draw_colored_polygon(PackedVector2Array([Vector2(fx - 5, y), Vector2(fx, y - h), Vector2(fx + 5, y)]), Color(1.0, 0.5, 0.12, 0.85 * fade))
		draw_colored_polygon(PackedVector2Array([Vector2(fx - 2.5, y), Vector2(fx, y - h * 0.55), Vector2(fx + 2.5, y)]), Color(1.0, 0.9, 0.5, 0.9 * fade))


func _draw_dark() -> void:
	"""THE DARK: the arena dimmed, a glow round every light - the balls',
	the paddle's, each lantern lit."""
	_cv.draw_rect(ARENA, Color(0.01, 0.008, 0.03, 0.66 if blackout <= 0.0 else 0.82))
	for light in light_sources():
		var at: Vector2 = light[0]
		var reach: float = light[1]
		for i in 4:
			_cv.draw_circle(at, reach * (1.0 - i * 0.22), Color(0.75, 0.8, 1.0, 0.025))
	var lamp: float = lamp_reach()
	if lamp > 0.0:
		for at in lanterns:
			for i in 4:
				_cv.draw_circle(at, lamp * (1.0 - i * 0.22), Color(1.0, 0.85, 0.5, 0.03))


func _draw_slicks() -> void:
	"""SLICK ICE: a pale band, glints running across it."""
	for band in slicks:
		var y0: float = band["y0"]
		var y1: float = band["y1"]
		_cv.draw_rect(Rect2(ARENA.position.x, y0, ARENA.size.x, y1 - y0), Color(COLOURS["ice"], 0.06))
		for i in 6:
			var x: float = ARENA.position.x + fposmod(t * 220.0 + i * 167.0, ARENA.size.x - 40.0)
			_cv.draw_line(Vector2(x, y1 - 2.0), Vector2(x + 26.0, y0 + 2.0), Color(1, 1, 1, 0.12), 2.0)
		for x in [ARENA.position.x + 3.0, ARENA.end.x - 3.0]:
			_cv.draw_line(Vector2(x, y0), Vector2(x, y1), Color(COLOURS["ice"], 0.5), 2.0)


func _draw_frozen(r: Rect2) -> void:
	"""Ice over a frozen brick: one touch breaks it."""
	_cv.draw_rect(r.grow(1.0), Color(0.75, 0.95, 1.0, 0.45))
	_cv.draw_line(r.position + Vector2(3, 3), r.get_center() + Vector2(2, 1), Color(1, 1, 1, 0.8), 1.0)
	_cv.draw_line(r.get_center() + Vector2(2, 1), r.end - Vector2(4, 3), Color(1, 1, 1, 0.8), 1.0)
	_cv.draw_rect(r.grow(1.0), Color(0.9, 1.0, 1.0, 0.9), false, 1.0)


# ---------------------------------------------------------------- drawing --

func _draw() -> void:
	_cv = self
	if state == State.KINGDOMS:
		_draw_kingdoms()
		return
	# the floor and the bricks are layers of their own, behind this
	# (_paint_floor(), _paint_brick()); from the guards up, as it always was
	draw_set_transform(_jolt)
	_draw_guards()
	_draw_tide_top()
	for bu in bubbles:
		var at: Vector2 = bu["p"] + Vector2(sin(t * 9.0 + bu["p"].y * 0.05) * 2.5, 0)
		draw_circle(at, 6.0, Color(COLOURS["water"], 0.25))
		draw_arc(at, 5.0, 0, TAU, 16, Color(0.8, 0.92, 1.0, 0.9), 1.4)
		draw_circle(at + Vector2(-1.8, -1.8), 1.3, Color(1, 1, 1, 0.9))
	for f in falling:
		var at: Vector2 = f["p"]
		draw_colored_polygon(PackedVector2Array([at + Vector2(-5, -10), at + Vector2(5, -10), at + Vector2(0, 10)]), Color(0.86, 0.97, 1.0))
		draw_line(at + Vector2(-1, -9), at + Vector2(0, 6), Color(1, 1, 1, 0.9), 1.2)
	for f in rubble:
		# A TOPPLED PILLAR'S RUBBLE: a tumbling chunk of its stone
		var spin: float = t * 9.0 + (f["p"] as Vector2).x * 0.3
		var half_w: float = maxf(4.0, cw * 0.32)
		var chunk := PackedVector2Array()
		for i in 5:
			chunk.append((f["p"] as Vector2) + Vector2.from_angle(spin + i * TAU / 5.0) * half_w * (0.8 + 0.2 * (i % 2)))
		draw_colored_polygon(chunk, (f["c"] as Color).darkened(0.1))
		draw_circle((f["p"] as Vector2) + Vector2(-1.5, -1.5), half_w * 0.3, Color(1, 1, 1, 0.25))
	for f in bombs:
		# A LAVA BOMB: a glowing blob, a smoky tail
		var at: Vector2 = f["p"]
		for i in 4:
			draw_circle(at - Vector2(0, 8.0 + i * 7.0), 4.0 - i * 0.8, Color(0.35, 0.3, 0.3, 0.35 - i * 0.07))
		draw_circle(at, 9.0, Color(COLOURS["fire"], 0.3))
		draw_circle(at, 5.5, Color(1.0, 0.5, 0.12))
		draw_circle(at + Vector2(-1.5, -1.5), 2.2, Color(1.0, 0.92, 0.6))
	for d in drips:
		draw_circle(d["p"], 9.0, Color(COLOURS["fire"], 0.3))
		draw_circle(d["p"], 5.0, Color(1.0, 0.55, 0.15))
		draw_circle(d["p"], 2.5, Color(1.0, 0.9, 0.6))
	for z in zaps:
		var a: float = 1.0 - float(z["age"]) / 0.3
		draw_polyline(z["pts"], Color(z["c"], 0.35 * a), 7.0, true)
		draw_polyline(z["pts"], Color(Color.WHITE, a), 2.0, true)
	if _eclipse > 0.0:
		draw_rect(ARENA, Color(0.05, 0.0, 0.12, 0.45 * _eclipse / 0.5))
	_draw_boss()
	if state == State.AIM:
		_draw_tracer(_path(Vector2(paddle_x, PADDLE_Y - BALL_R - 8.0), Vector2.from_angle(aim), 1000.0), INK, true)
	for bolt in bolts:
		_draw_tracer(PackedVector2Array([bolt["from"], bolt["p"]]), COLOURS["fire"], false, true)
	for c in caps:
		_draw_capsule(c)
	if active.has("shield"):
		var a: float = 0.55 + 0.25 * sin(t * 6.0) + _shield_flash * 0.4
		draw_line(Vector2(ARENA.position.x + 6, SHIELD_Y), Vector2(ARENA.end.x - 6, SHIELD_Y), Color(COLOURS["water"], a * 0.35), 10.0)
		draw_line(Vector2(ARENA.position.x + 6, SHIELD_Y), Vector2(ARENA.end.x - 6, SHIELD_Y), Color(0.7, 0.85, 1.0, a), 2.5)
	for b in balls:
		_draw_trail(b)
	for b in balls:
		_draw_ball(b)
	_draw_paddle()
	for f in patches:
		# fire on the floor licks up over the paddle
		_draw_patch(f)
	for r in rings:
		var u: float = r["age"] / r["most"]
		draw_arc(r["p"], r["r"] * u, 0, TAU, 48, Color(r["c"], 1.0 - u), 6.0 * (1.0 - u) + 1.0)
	for p in parts:
		var a: float = clampf(p["life"] / p["most"], 0.0, 1.0)
		draw_circle(p["p"], p["s"] * (0.5 + a * 0.5), Color(p["c"], a))
	for w in words:
		var a: float = clampf(w["life"] / 0.45, 0.0, 1.0)
		var pop: float = 1.0 + 0.35 * maxf(0.0, 1.0 - w["age"] / 0.12)
		_text(w["p"], w["text"], int(w["size"] * pop), Color(w["c"], a), null, true, a)
	draw_set_transform(Vector2.ZERO)
	_draw_banner()
	if state == State.AIM and _banner_t <= 0.0 and launch_hint != "":
		_text(Vector2(paddle_x, PADDLE_Y - 34.0), launch_hint, 14, Color(INK, 0.55 + 0.25 * sin(t * 3.0)), _font, true)
	_draw_hud()
	_draw_left_panel()
	_draw_right_panel()


func _draw_banner() -> void:
	"""A MAP OPENS WITH ITS NAME: a band across the arena, under the bricks
	and over the paddle, for BANNER_SECONDS - which map of the kingdom (or
	its citadel), its name, and its line."""
	if _banner_t <= 0.0 or state == State.KINGDOMS:
		return
	var a: float = clampf(_banner_t / 0.4, 0.0, 1.0) * clampf((BANNER_SECONDS - _banner_t) / 0.25, 0.0, 1.0)
	var data: Dictionary = Maps.MAPS[map_index]
	var kingdom: Dictionary = Maps.kingdom_of(map_index)
	var colour: Color = COLOURS.get(kingdom.get("land", "light"), GOLD)
	var band := Rect2(ARENA.position.x, 432, ARENA.size.x, 116)
	draw_rect(band, Color(0, 0, 0, 0.62 * a))
	draw_line(band.position, Vector2(band.end.x, band.position.y), Color(colour, 0.7 * a), 2.0)
	draw_line(Vector2(band.position.x, band.end.y), band.end, Color(colour, 0.7 * a), 2.0)
	var which: String = "MAP %d OF %d" % [Maps.in_kingdom(map_index) + 1, Maps.MAPS_A_KINGDOM]
	if data.get("boss") is Dictionary:
		which = ("THE CITADEL" if bool(data["boss"].get("crown", false)) else "A GUARDIAN") + "  ·  " + which
	_text(Vector2(640, 462), "%s  ·  %s" % [which, str(kingdom.get("name", "")).to_upper()], 14, Color(colour, a), null, true, a)
	_text(Vector2(640, 506), str(data["name"]).to_upper(), 40, Color(INK, a), null, true, a)
	_text(Vector2(640, 534), str(data["line"]), 16, Color(INK, 0.75 * a), _font, true, a)


func _draw_backdrop() -> void:
	_cv.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(VIEW.x, 0), VIEW, Vector2(0, VIEW.y)]),
		PackedColorArray([Color(0.05, 0.05, 0.1), Color(0.05, 0.05, 0.1), Color(0.02, 0.02, 0.04), Color(0.02, 0.02, 0.04)]))
	for i in 70:
		var s := Vector2(fmod(i * 197.3, VIEW.x), fmod(i * 83.1 + 40.0, VIEW.y))
		_cv.draw_circle(s, 0.9 + (i % 3) * 0.4, Color(1, 1, 1, 0.06 + 0.05 * sin(t * 1.3 + i)))


func _draw_arena() -> void:
	var sick: float = 0.0 if breakable <= 0 else clampf(1.0 - float(broken) / float(breakable), 0.0, 1.0)
	sick *= 1.0 - _healed
	var top := Color(0.075, 0.08, 0.13).lerp(Color(0.09, 0.11, 0.06), sick * 0.8)
	var low := Color(0.04, 0.045, 0.075).lerp(Color(0.05, 0.07, 0.03), sick * 0.8)
	if _healed > 0.0:
		top = top.lerp(Color(0.08, 0.13, 0.1), _healed * 0.6)
		low = low.lerp(Color(0.05, 0.09, 0.06), _healed * 0.6)
	_cv.draw_polygon(PackedVector2Array([ARENA.position, Vector2(ARENA.end.x, ARENA.position.y), ARENA.end,
		Vector2(ARENA.position.x, ARENA.end.y)]), PackedColorArray([top, top, low, low]))
	for gx in range(int(ARENA.position.x) + 40, int(ARENA.end.x), 40):
		_cv.draw_line(Vector2(gx, ARENA.position.y), Vector2(gx, ARENA.end.y), Color(1, 1, 1, 0.022), 1.0)
	for gy in range(int(ARENA.position.y) + 40, int(ARENA.end.y), 40):
		_cv.draw_line(Vector2(ARENA.position.x, gy), Vector2(ARENA.end.x, gy), Color(1, 1, 1, 0.016), 1.0)
	_draw_air()
	# THE PLAGUE'S HAZE, thinning as the map is broken
	if sick > 0.0:
		for i in 7:
			var y: float = ARENA.end.y - 40.0 - i * 26.0 + sin(t * 0.7 + i) * 6.0
			_cv.draw_line(Vector2(ARENA.position.x, y), Vector2(ARENA.end.x, y), Color(BLIGHT, 0.035 * sick), 22.0)
	var jolt := Vector2.ZERO
	_cv.draw_set_transform(Vector2(paddle_x, PADDLE_Y + 14.0) + jolt, 0.0, Vector2(1.0, 0.22))
	for i in 5:
		_cv.draw_circle(Vector2.ZERO, paddle_w * (0.7 + i * 0.22), Color(GOLD, 0.05))
	_cv.draw_set_transform(_jolt)


func _draw_arena_frame() -> void:
	"""The arena's frame and its gold corners - the last of the arena, drawn
	with the building, once a map (0.166.2)."""
	for i in 6:
		_cv.draw_rect(ARENA.grow(-i * 5.0), Color(0, 0, 0, 0.09), false, 5.0)
	_cv.draw_rect(ARENA.grow(7), EDGE, false, 10.0)
	_cv.draw_rect(ARENA.grow(13), Color(0.14, 0.12, 0.11), false, 2.0)
	_cv.draw_rect(ARENA.grow(2.5), Color(GOLD, 0.35), false, 1.5)
	for corner in [ARENA.position, Vector2(ARENA.end.x, ARENA.position.y), ARENA.end, Vector2(ARENA.position.x, ARENA.end.y)]:
		_cv.draw_colored_polygon(PackedVector2Array([corner + Vector2(0, -11), corner + Vector2(11, 0), corner + Vector2(0, 11),
			corner + Vector2(-11, 0)]), GOLD)
		_cv.draw_colored_polygon(PackedVector2Array([corner + Vector2(0, -5), corner + Vector2(5, 0), corner + Vector2(0, 5),
			corner + Vector2(-5, 0)]), Color(0.3, 0.2, 0.05))


func _draw_air() -> void:
	"""THE KINGDOM'S AIR, behind everything in the arena: motes rising in
	Light, streaks blowing across in Wind, small bubbles rising in Water -
	faint and small, so none is taken for a ball."""
	var land: String = str(Maps.kingdom_of(map_index).get("land", "light"))
	var c: Color = COLOURS.get(land, GOLD)
	var w: float = ARENA.size.x
	var h: float = ARENA.size.y
	match land:
		"wind":
			for i in 16:
				var y: float = ARENA.position.y + fmod(i * 97.0 + 23.0, h)
				var x: float = ARENA.position.x + fposmod(t * (70.0 + (i % 4) * 20.0) + i * 211.0, w - 36.0)
				_cv.draw_line(Vector2(x, y), Vector2(x + 34.0, y), Color(c, 0.07), 1.5)
		"water":
			for i in 26:
				var x: float = clampf(ARENA.position.x + fmod(i * 137.5, w) + sin(t * 1.3 + i) * 5.0, ARENA.position.x + 4.0, ARENA.end.x - 4.0)
				var y: float = ARENA.end.y - 4.0 - fposmod(t * (18.0 + (i % 5) * 6.0) + i * 53.0, h - 8.0)
				_cv.draw_arc(Vector2(x, y), 1.4 + (i % 3) * 0.6, 0, TAU, 8, Color(c.lightened(0.4), 0.16), 1.0)
		_:
			for i in 28:
				var x: float = clampf(ARENA.position.x + fmod(i * 137.5, w) + sin(t * 0.8 + i * 1.7) * 8.0, ARENA.position.x + 4.0, ARENA.end.x - 4.0)
				var y: float = ARENA.end.y - 4.0 - fposmod(t * (10.0 + (i % 4) * 4.0) + i * 61.0, h - 8.0)
				_cv.draw_circle(Vector2(x, y), 1.0 + (i % 3) * 0.5, Color(c, 0.12 + 0.06 * sin(t * 2.0 + i)))


func _draw_building() -> void:
	"""THE STONE THE BRICKS ARE SET IN: behind every cell the map held, so a
	hole reads as a hole in a wall and not a gap in a row."""
	for c in footprint.keys():
		var r := _cell(c.x, c.y).grow(1.5)
		_cv.draw_rect(r, Color(0.12, 0.115, 0.14))
	for c in footprint.keys():
		var r := _cell(c.x, c.y).grow(1.5)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if footprint.has(c + d):
				continue
			match d:
				Vector2i(1, 0):
					_cv.draw_line(Vector2(r.end.x, r.position.y), r.end, Color(0.33, 0.31, 0.29), 2.0)
				Vector2i(-1, 0):
					_cv.draw_line(r.position, Vector2(r.position.x, r.end.y), Color(0.33, 0.31, 0.29), 2.0)
				Vector2i(0, 1):
					_cv.draw_line(Vector2(r.position.x, r.end.y), r.end, Color(0.33, 0.31, 0.29), 2.0)
				Vector2i(0, -1):
					_cv.draw_line(r.position, Vector2(r.end.x, r.position.y), Color(0.33, 0.31, 0.29), 2.0)
	if hall.size != Vector2.ZERO:
		_cv.draw_rect(hall.grow(2.0), Color(0.09, 0.08, 0.1))
		_cv.draw_rect(hall.grow(2.0), Color(GOLD, 0.25), false, 1.5)
		for i in 6:
			var x: float = hall.position.x + (i + 0.5) * hall.size.x / 6.0
			_cv.draw_line(Vector2(x, hall.position.y + 4), Vector2(x, hall.end.y - 4), Color(1, 1, 1, 0.04), 8.0)


func _draw_rails() -> void:
	"""The lanes' floor a shade darker, and their iron rails: dark steel, a
	lit edge, rivets, and a gold cap at each gate."""
	for x in [ARENA.position.x, FIELD_X + FIELD_W + RAIL_W]:
		_cv.draw_rect(Rect2(x, ARENA.position.y, SIDE_GAP - RAIL_W, field_bottom() - ARENA.position.y), Color(0, 0, 0, 0.18))
	for k in rails:
		var r: Rect2 = k["rect"]
		_cv.draw_rect(r.grow(1.0), Color(GOLD, 0.22))
		_cv.draw_rect(r, Color(0.34, 0.37, 0.45).lerp(Color.WHITE, float(k["flash"]) * 0.5))
		_cv.draw_rect(Rect2(r.position, Vector2(1.5, r.size.y)), Color(0.8, 0.84, 0.92))
		for y in range(int(r.position.y) + 10, int(r.end.y) - 4, 24):
			_cv.draw_circle(Vector2(r.get_center().x, y), 1.2, Color(0.75, 0.78, 0.85))
		for y in [r.position.y, r.end.y]:
			if y > ARENA.position.y + 1.0:
				_cv.draw_rect(Rect2(r.position.x - 1.5, y - 1.5, r.size.x + 3.0, 3.0), GOLD)


func _draw_gusts() -> void:
	"""A gust: a faint band of its own, streaks running its way through it,
	and chevrons at its edges pointing that way."""
	for g in gusts:
		var y0: float = g["y0"]
		var y1: float = g["y1"]
		var way: float = g["way"]
		_cv.draw_rect(Rect2(ARENA.position.x, y0, ARENA.size.x, y1 - y0), Color(COLOURS["wind"], 0.05))
		var lanes: int = maxi(2, int((y1 - y0) / 11.0))
		for i in lanes:
			var y: float = y0 + (i + 0.5) * (y1 - y0) / lanes
			var run_x: float = fposmod(t * 260.0 * way + i * 137.0, ARENA.size.x + 120.0) - 60.0
			for j in 3:
				var x: float = ARENA.position.x + fposmod(run_x + j * (ARENA.size.x / 3.0), ARENA.size.x)
				_cv.draw_line(Vector2(x, y), Vector2(x - way * 46.0, y), Color(COLOURS["wind"], 0.28), 2.0)
		for edge in [ARENA.position.x + 12.0, ARENA.end.x - 12.0]:
			var mid: float = (y0 + y1) / 2.0
			_cv.draw_polyline(PackedVector2Array([Vector2(edge - way * 5.0, mid - 7.0), Vector2(edge + way * 5.0, mid),
				Vector2(edge - way * 5.0, mid + 7.0)]), Color(COLOURS["wind"], 0.7), 2.0)


func _draw_tide_body() -> void:
	"""THE TIDE: its mark in each lane and faint across the field, always; the
	water itself from the foot of the rows up to where it stands, under the
	bricks."""
	if tide_mark < 0:
		return
	var mark: float = tide_line()
	var blue: Color = COLOURS["water"]
	for x in range(int(FIELD_X) + 4, int(FIELD_X + FIELD_W) - 4, 14):
		_cv.draw_line(Vector2(x, mark), Vector2(x + 6, mark), Color(blue, 0.18), 1.0)
	for x in [ARENA.position.x + 4.0, FIELD_X + FIELD_W + RAIL_W + 4.0]:
		for i in 2:
			var y: float = mark - 3.0 + i * 5.0
			_cv.draw_polyline(PackedVector2Array([Vector2(x, y), Vector2(x + 5, y - 2.5), Vector2(x + 10, y), Vector2(x + 15, y - 2.5),
				Vector2(x + 20, y)]), Color(blue.lightened(0.3), 0.75), 1.4)
	var level: float = tide_level()
	if level <= 0.0:
		return
	var top: float = tide_y()
	var foot: float = field_bottom() + 6.0
	_cv.draw_rect(Rect2(ARENA.position.x, top, ARENA.size.x, foot - top), Color(blue, 0.16 + 0.06 * level))
	for i in 3:
		var y: float = top + 14.0 + i * 22.0
		if y < foot - 4.0:
			_cv.draw_line(Vector2(ARENA.position.x, y), Vector2(ARENA.end.x, y), Color(blue.lightened(0.2), 0.05), 6.0)


func _draw_tide_top() -> void:
	"""Over the bricks: the water they stand in, tinting them blue, and its
	surface - a moving wave, foam on its crests."""
	var level: float = tide_level()
	if tide_mark < 0 or level <= 0.0:
		return
	var top: float = tide_y()
	draw_rect(Rect2(ARENA.position.x, top, ARENA.size.x, field_bottom() + 6.0 - top), Color(COLOURS["water"], 0.2 * level))
	var pts := PackedVector2Array()
	var x: float = ARENA.position.x
	while x <= ARENA.end.x:
		pts.append(Vector2(x, top + sin(x * 0.045 + t * 3.0) * 3.0 + sin(x * 0.11 - t * 2.0) * 1.5))
		x += 8.0
	draw_polyline(pts, Color(COLOURS["water"].lightened(0.25), 0.55 * level), 4.0)
	draw_polyline(pts, Color(0.88, 0.95, 1.0, 0.8 * level), 1.5)


func _draw_half_shell(mid: Vector2, w: float, h: float, up: bool, c: Color) -> void:
	"""Half an ellipse, flat side to `mid`: up, the clam's lid; down, its foot."""
	var pts := PackedVector2Array([mid + Vector2(-w, 0)])
	for i in range(1, 12):
		var a: float = PI * i / 12.0
		pts.append(mid + Vector2(-cos(a) * w, sin(a) * h * (-1.0 if up else 1.0)))
	pts.append(mid + Vector2(w, 0))
	_cv.draw_colored_polygon(pts, c)
	for i in [-1, 0, 1]:
		_cv.draw_line(mid, mid + Vector2(i * w * 0.55, h * 0.8 * (-1.0 if up else 1.0)), Color(0, 0, 0, 0.25), 1.0)


func _draw_guards() -> void:
	"""Round every standing Guard, the cells it shields: a soft blue frame."""
	var pulse: float = 0.5 + 0.5 * sin(t * 3.0)
	var gk: int = bricks.size()
	if gk != _guard_key:
		_guard_key = gk
		_guard_list = bricks.filter(func(x: Dictionary) -> bool: return x["kind"] == "guard")
	for k in _guard_list:
		if k["kind"] == "guard" and k["hp"] > 0 and k.has("cell"):
			var c: Vector2i = k["cell"]
			var box: Rect2 = _cell(c.x - 1, c.y - 1).merge(_cell(c.x + 1, c.y + 1)).grow(2.0)
			# in the dark, only as much as the Guard itself is seen
			var shown: float = GHOST + (1.0 - GHOST) * float(k.get("seen", 0.0)) if dark else 1.0
			draw_rect(box, Color(GUARD_GLOW, (0.05 + 0.04 * pulse) * shown))
			draw_rect(box, Color(GUARD_GLOW, (0.4 + 0.25 * pulse) * shown), false, 1.5)


func _paint_floor() -> void:
	"""THE FLOOR, behind the bricks, every frame: the backdrop and the arena
	(then the building, a layer drawn once a map, and the floor over it)."""
	_cv = floor_layer
	_draw_backdrop()
	if state != State.KINGDOMS:
		floor_layer.draw_set_transform(_jolt)
		_draw_arena()
	_cv = self


func _paint_building() -> void:
	"""THE STONE THE BRICKS ARE SET IN, drawn again only when a map's shape
	changes (0.166.2) - it was drawn every frame, the floor's dearest part.
	The layer is moved with the shake instead."""
	_cv = building_layer
	_draw_arena_frame()
	_draw_building()
	_cv = self


func _paint_floor_top() -> void:
	"""Over the building, every frame: the tide, the ice, the gusts, the
	rails, the dark."""
	if state == State.KINGDOMS:
		return
	_cv = floor_top
	floor_top.draw_set_transform(_jolt)
	_draw_tide_body()
	_draw_slicks()
	_draw_gusts()
	_draw_rails()
	if dark:
		_draw_dark()
	_cv = self


func sync_bricks() -> void:
	"""THE BRICKS DRAW ONCE: a picture each (made the first time it is
	seen), hidden once broken, drawn again only when _brick_look() says its
	look has changed. A brick struck is drawn again at once; the rest are
	looked at half each frame, so a kind always moving is drawn every other
	frame. What moves (drifters, kites, buoys) is put in place every frame.
	Pictures whose bricks have gone (a new map, the blight's dead) are let
	go. THE STILL BRICKS ARE ONE PICTURE: the cache is drawn again only on
	a frame one of its bricks changed; a brick drawn every look shows its
	twin (k["twin"], in brick_live) instead."""
	redrawn = 0
	if brick_layer == null:
		return
	_sync_n += 1
	brick_pic.position = _jolt
	brick_live.position = _jolt
	brick_pic.visible = state != State.KINGDOMS
	brick_live.visible = brick_pic.visible
	_glow_last = last_few()
	var glow: bool = pulling or _glow_last
	var seen: int = 0
	var half: int = _sync_n % 2
	var dirty: bool = false
	for k in bricks:
		var node: Node2D = k.get("node")
		if node == null:
			if k.has("rail"):
				continue
			node = Node2D.new()
			node.position = (k["rect"] as Rect2).position
			brick_layer.add_child(node)
			node.draw.connect(_paint_brick.bind(k, node))
			k["node"] = node
			k["look"] = -2
			k["half"] = seen % 2
			k["shown"] = true
			k["live"] = false
			dirty = true
		seen += 1
		if not k["shown"] and k["hp"] <= 0:
			# long gone: nothing to look at
			continue
		if k["hp"] <= 0 and not NEVER_BREAKS.has(k["kind"]):
			if k["shown"]:
				k["shown"] = false
				dirty = dirty or node.visible
				node.visible = false
				if k.has("twin"):
					(k["twin"] as Node2D).visible = false
			continue
		if not k["shown"]:
			k["shown"] = true
			dirty = _show_brick(k, node) or dirty
		if k["flash"] > 0.0:
			# struck: its twin flashes over it; the picture keeps it under
			k["look"] = -1
			if not k["live"]:
				_brick_live(k, node, true, true)
			(k["twin"] as Node2D).queue_redraw()
			redrawn += 1
			continue
		if k["half"] != half and k["look"] != -2:
			continue
		var at: Vector2 = (k["rect"] as Rect2).position
		if node.position != at:
			node.position = at
			dirty = dirty or not k["live"]
		var look: int = _brick_look(k, glow)
		var live: bool = look == -1 or _whole_twin(k)
		if live and not k["live"]:
			_brick_live(k, node, true, false)
			dirty = true
		elif live and k.get("under", false):
			# drawn every look for longer than a blow: only its shadow stays
			# in the picture
			k["under"] = false
			k["cached"] = -5
			node.queue_redraw()
			(k["twin"] as Node2D).queue_redraw()
			dirty = true
		elif not live and k["live"]:
			dirty = _brick_still(k, node) or dirty
		if look == -1 or look != k["look"]:
			k["look"] = look
			if live:
				(k["twin"] as Node2D).queue_redraw()
				redrawn += 1
			elif int(k.get("cached", -3)) != look:
				k["cached"] = look
				node.queue_redraw()
				dirty = true
				redrawn += 1
	for list in [movers, buoys]:
		for k in list:
			var node: Node2D = k.get("node")
			if node == null:
				continue
			if not k.has("moves"):
				# what moves leaves the picture altogether: its twin draws it
				# all, its shadow too
				k["moves"] = true
				if not k["live"]:
					_brick_live(k, node, true, false)
				k["under"] = false
				node.visible = false
				(k["twin"] as Node2D).queue_redraw()
				dirty = true
			var at: Vector2 = (k["rect"] as Rect2).position
			if node.position != at:
				node.position = at
			if k.has("twin") and (k["twin"] as Node2D).position != at:
				(k["twin"] as Node2D).position = at
	if brick_layer.get_child_count() > seen:
		var keep: Dictionary = {}
		for k in bricks:
			if k.has("node"):
				keep[k["node"]] = true
			if k.has("twin"):
				keep[k["twin"]] = true
		for layer in [brick_layer, brick_live]:
			for n in (layer as Node).get_children():
				if not keep.has(n) and not n.is_queued_for_deletion():
					n.queue_free()
					dirty = dirty or layer == brick_layer
	if dirty:
		brick_cache.render_target_update_mode = SubViewport.UPDATE_ONCE


func _show_brick(k: Dictionary, node: Node2D) -> bool:
	"""A brick back (the tide's, a hidden one shown): its place in the
	picture, and its twin if it has one on. True when the picture changes."""
	if k["live"]:
		(k["twin"] as Node2D).visible = true
	node.visible = not _whole_twin(k)
	return node.visible


func _whole_twin(k: Dictionary) -> bool:
	"""Out of the still picture altogether, its twin drawing it all: what
	moves, and every brick on a dark map (the dark over each brick reaches
	over its neighbours, so their order is kept by drawing them all as
	before)."""
	return dark or k.has("moves")


func _brick_live(k: Dictionary, node: Node2D, live: bool, under: bool) -> void:
	"""A brick drawn every look, on its twin over the still picture: for a
	blow's flash the picture keeps the whole brick under it (`under`); for
	longer, only its shadow, so the picture's order of shadows holds. Back,
	_brick_still()."""
	k["live"] = live
	var twin: Node2D = k.get("twin")
	if twin == null:
		twin = Node2D.new()
		brick_live.add_child(twin)
		twin.draw.connect(_paint_brick.bind(k, twin))
		k["twin"] = twin
	twin.position = node.position
	twin.visible = true
	twin.queue_redraw()
	k["under"] = under
	if _whole_twin(k):
		k["under"] = false
		node.visible = false
	elif not under:
		k["cached"] = -5
		node.queue_redraw()


func _brick_still(k: Dictionary, node: Node2D) -> bool:
	"""Back into the still picture from its twin: true when the picture has
	to be drawn again (it held only the shadow)."""
	k["live"] = false
	if k.has("twin"):
		(k["twin"] as Node2D).visible = false
	if k.get("under", false):
		k["under"] = false
		return false
	k["cached"] = -5
	node.visible = true
	return true


func _brick_look(k: Dictionary, glow: bool = false) -> int:
	"""What a brick looks like, as one number - or -1 for one drawn every
	time it is looked at: struck, burning, warded, glowing, or a kind always
	moving."""
	var kind: String = k["kind"]
	if not STILL_KINDS.has(kind) or k["flash"] > 0.0 or k["burn"] >= 0.0 or k.has("warded"):
		return -1
	var hp: int = k["hp"]
	if glow and _can_hit(k):
		return -1
	var look: int = ((hp * 64 + k["most"]) * 16 + LAND_NO.get(k["land"], 0)) * 4
	if k.get("frozen", false):
		look += 2
	if k.has("frost"):
		look += 1
	if dark:
		look = look * 32 + int(k.get("seen", 0.0) * 24.0)
	return look


func _paint_brick(k: Dictionary, node: Node2D) -> void:
	"""ONE BRICK'S PICTURE where it stands (the layer is shaken with the run):
	its shadow, the brick - on a big map the standard brick scaled into its
	rect - and what lies on it."""
	if not (k["hp"] > 0 or not _breaks(k)):
		return
	_cv = node
	var r: Rect2 = k["rect"]
	var here := Rect2(Vector2.ZERO, r.size)
	var twin: bool = node == k.get("twin")
	if not twin or _whole_twin(k):
		# the shadow in the still picture, where the bricks' order keeps it
		# (THE STILL BRICKS ARE ONE PICTURE); a twin draws the rest
		node.draw_rect(Rect2(Vector2(2, 3), r.size), Color(0, 0, 0, 0.38))
	if not twin and k.get("live", false) and not k.get("under", false):
		return
	var standard := Vector2(CW - 2.0, CH)
	if r.size.is_equal_approx(standard) or k["kind"] == "heart" or k["kind"] == "boulder":
		_draw_brick_in(k, here)
	else:
		node.draw_set_transform(Vector2.ZERO, 0.0, r.size / standard)
		_draw_brick_in(k, Rect2(Vector2.ZERO, standard))
		node.draw_set_transform(Vector2.ZERO)
	if k.has("warded") and k["hp"] > 0:
		node.draw_rect(here.grow(1.5), Color(GUARD_GLOW, float(k["warded"])), false, 2.0)
	if bool(k.get("frozen", false)) and k["hp"] > 0:
		_draw_frozen(here)
	if k.has("frost") and k["hp"] > 0:
		_draw_frost_coat(here)
	if (pulling or _glow_last) and _can_hit(k):
		var glow: float = 0.5 + 0.5 * sin(t * 6.0)
		node.draw_rect(here.grow(3.0 + glow * 3.0), Color(GOLD, 0.35 + 0.35 * glow), false, 2.0)
	if dark:
		# UNSEEN: the dark over it, a ghost of it left
		var shown: float = GHOST + (1.0 - GHOST) * float(k.get("seen", 0.0))
		if shown < 1.0:
			node.draw_rect(Rect2(Vector2(-1, -1), r.size + Vector2(4, 5)), Color(0.015, 0.012, 0.04, 1.0 - shown))
	_cv = self


func _draw_brick_in(k: Dictionary, r: Rect2) -> void:
	var c: Color = _colour_of(k)
	var flash: float = k["flash"]
	var lit: float = 0.5 + 0.5 * sin(t * 40.0) if k["burn"] >= 0.0 else 0.0
	var mid: Vector2 = r.get_center()
	match k["kind"]:
		"iron":
			_cv.draw_rect(r, Color(0.2, 0.22, 0.27).lerp(Color.WHITE, flash * 0.5))
			_cv.draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(0.62, 0.66, 0.75))
			_cv.draw_rect(r, GOLD.darkened(0.3), false, 1.5)
			for x in [r.position.x + 4, r.end.x - 4]:
				for y in [r.position.y + 4, r.end.y - 4]:
					_cv.draw_circle(Vector2(x, y), 1.4, Color(0.75, 0.78, 0.85))
			return
		"mirror":
			# A DEEPER BLUE THAN ANY STONE (the owner: mirrors beside grey
			# stone should "pop immediately as angled deflectors"), with a
			# soft blue rim and the glint along its slant.
			_cv.draw_rect(r.grow(1.5), Color(MIRROR_BLUE, 0.35 + 0.15 * sin(t * 2.0 + r.position.x * 0.05)), false, 2.0)
			_cv.draw_rect(r, MIRROR_BLUE.darkened(0.25).lerp(Color.WHITE, flash * 0.7))
			_cv.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5)), MIRROR_BLUE.lerp(Color.WHITE, 0.15 + flash * 0.6))
			var shine: float = 0.5 + 0.5 * sin(t * 2.0 + r.position.x * 0.05)
			_cv.draw_line(r.position + Vector2(4, r.size.y - 3), r.position + Vector2(r.size.x - 4, 3), Color(1, 1, 1, 0.55 + 0.4 * shine), 2.5)
			_cv.draw_rect(r, Color(0.85, 0.93, 1.0, 0.8), false, 1.2)
			return
		"bumper":
			# round, pink, and it lights when struck
			var ring_r: float = r.size.y * 0.5 + 1.0
			_cv.draw_circle(mid, ring_r + 3.0 + flash * 3.0, Color(1.0, 0.45, 0.8, 0.25 + flash * 0.3))
			_cv.draw_circle(mid, ring_r, Color(0.55, 0.18, 0.45).lerp(Color.WHITE, flash * 0.5))
			_cv.draw_circle(mid, ring_r - 3.0, Color(1.0, 0.55, 0.85).lerp(Color.WHITE, flash * 0.6))
			_cv.draw_circle(mid + Vector2(-2, -2), 2.0, Color(1, 1, 1, 0.9))
			return
		"portal":
			# a swirl, its pair's colour
			var hue: Color = PORTAL_HUES[int(k.get("pair", 0)) % PORTAL_HUES.size()] if k.has("to") else Color(0.4, 0.4, 0.45)
			_cv.draw_rect(r, Color(0.06, 0.03, 0.1))
			for i in 3:
				var a0: float = t * 3.0 + i * TAU / 3.0
				_cv.draw_arc(mid, 6.0 - i * 1.5, a0, a0 + PI * 1.2, 10, Color(hue.lerp(Color.WHITE, flash * 0.6), 0.9 - i * 0.2), 1.6)
			_cv.draw_rect(r, Color(hue, 0.8), false, 1.2)
			return
		"whirl":
			# A WHIRL: a pinwheel always turning, faster when struck
			_cv.draw_rect(r, Color(0.08, 0.16, 0.14))
			var spin: float = t * (5.0 + flash * 14.0) + float(k.get("phase", 0.0))
			for i in 4:
				var a: float = spin + i * TAU / 4.0
				var tip: Vector2 = mid + Vector2.from_angle(a) * (r.size.y * 0.5 + 2.0)
				var side: Vector2 = mid + Vector2.from_angle(a + 0.9) * (r.size.y * 0.32)
				_cv.draw_colored_polygon(PackedVector2Array([mid, tip, side]), COLOURS["wind"].lerp(Color.WHITE, 0.15 + flash * 0.5))
			_cv.draw_circle(mid, 2.0, Color(1, 1, 1, 0.9))
			_cv.draw_rect(r, Color(COLOURS["wind"], 0.6), false, 1.2)
			return
		"guard":
			# A GUARD: a steel plate, a gold shield on it (dimmed once struck)
			_cv.draw_rect(r, Color(0.22, 0.3, 0.45).lerp(Color.WHITE, flash * 0.5))
			_cv.draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(0.55, 0.68, 0.9))
			var crest := PackedVector2Array([mid + Vector2(-5, -5), mid + Vector2(5, -5), mid + Vector2(5, 0),
				mid + Vector2(0, 6), mid + Vector2(-5, 0)])
			_cv.draw_colored_polygon(crest, GOLD if k["hp"] >= 2 else GOLD.darkened(0.45))
			crest.append(crest[0])
			_cv.draw_polyline(crest, Color(0.3, 0.2, 0.05), 1.0)
			_cv.draw_rect(r, GUARD_GLOW, false, 1.5)
			return
		"lock":
			_cv.draw_rect(r, Color(0.2, 0.22, 0.27).lerp(Color.WHITE, flash * 0.4))
			_cv.draw_rect(r, GOLD.darkened(0.3), false, 1.5)
			_cv.draw_arc(mid + Vector2(0, -1), 3.5, PI, TAU, 10, GOLD, 1.6)
			_cv.draw_rect(Rect2(mid + Vector2(-4.5, -1), Vector2(9, 6)), GOLD)
			_cv.draw_circle(mid + Vector2(0, 2), 1.2, Color(0.2, 0.15, 0.05))
			return
		"rune":
			var on: float = 1.0 if _rune_lit(k) else 0.0
			_cv.draw_rect(r, Color(0.12, 0.13, 0.2).lerp(Color(0.45, 0.35, 0.12), on * 0.6).lerp(Color.WHITE, flash * 0.4))
			var glyph: Color = Color(1.0, 0.85, 0.35, 0.35 + on * 0.65)
			_cv.draw_polyline(PackedVector2Array([mid + Vector2(0, -5), mid + Vector2(5, 0), mid + Vector2(0, 5), mid + Vector2(-5, 0),
				mid + Vector2(0, -5)]), glyph, 1.4)
			_cv.draw_line(mid + Vector2(0, -5), mid + Vector2(0, 5), glyph, 1.2)
			if on > 0.0:
				_cv.draw_rect(r.grow(1.5), Color(1.0, 0.85, 0.35, 0.5), false, 1.5)
			else:
				_cv.draw_rect(r, Color(0.4, 0.45, 0.6, 0.6), false, 1.0)
			return
		"mix":
			# two lands, split on the diagonal
			var lands: Array = MIX_LANDS.get(str(k.get("mix", "clash")), ["light", "light"])
			var a_col: Color = COLOURS[lands[0]].lerp(Color.WHITE, flash * 0.5)
			var b_col: Color = COLOURS[lands[1]].lerp(Color.WHITE, flash * 0.5)
			_cv.draw_rect(r, a_col.darkened(0.15))
			_cv.draw_colored_polygon(PackedVector2Array([Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
				b_col.darkened(0.1))
			_cv.draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(1, 1, 1, 0.4))
			var spark: float = 0.6 + 0.4 * sin(t * 6.0 + r.position.x)
			_cv.draw_line(mid + Vector2(-3, -3), mid + Vector2(3, 3), Color(1, 1, 1, spark), 1.4)
			_cv.draw_line(mid + Vector2(-3, 3), mid + Vector2(3, -3), Color(1, 1, 1, spark), 1.4)
			_cv.draw_rect(r, Color(1, 1, 1, 0.35), false, 1.0)
			return
		"drift":
			# A SNOWDRIFT: soft white, heaped along its top
			var snow := Color(0.9, 0.94, 1.0).lerp(Color.WHITE, flash * 0.5)
			_cv.draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.35), Vector2(r.size.x, r.size.y * 0.65)), snow.darkened(0.08))
			for i in 4:
				_cv.draw_circle(Vector2(r.position.x + r.size.x * (0.14 + i * 0.24), r.position.y + r.size.y * 0.45), r.size.y * 0.36, snow)
			_cv.draw_rect(Rect2(r.position.x, r.end.y - 2.0, r.size.x, 2.0), Color(0.6, 0.7, 0.85, 0.6))
			if k["hp"] <= 1:
				_cv.draw_line(r.position + Vector2(r.size.x * 0.3, r.size.y * 0.3), r.get_center() + Vector2(3, 3), Color(0.55, 0.65, 0.8), 1.2)
			return
		"icicle":
			# AN ICICLE: hanging from the brick above; a Snow Sprite's blinks
			# as its time runs out
			var ice := Color(0.82, 0.95, 1.0)
			if k.has("hang") and float(k["hang"]) < 1.5:
				ice = ice.lerp(Color.WHITE, 0.5 + 0.5 * sin(t * 18.0))
			_cv.draw_colored_polygon(PackedVector2Array([r.position + Vector2(r.size.x * 0.2, 0), Vector2(r.end.x - r.size.x * 0.2, r.position.y),
				Vector2(mid.x, r.end.y + r.size.y * 0.25)]), ice.lerp(Color.WHITE, flash * 0.5))
			_cv.draw_line(Vector2(mid.x - 1.5, r.position.y + 1.0), Vector2(mid.x, r.end.y), Color(1, 1, 1, 0.9), 1.2)
			return
		"clam":
			# A CLAM: its lid lifts when it opens, the pearl shining inside
			var o: float = clam_open(k)
			_cv.draw_rect(r, Color(0.08, 0.14, 0.24).lerp(Color.WHITE, flash * 0.4))
			var shell := Color(0.72, 0.62, 0.78).lerp(Color.WHITE, flash * 0.5)
			var hinge: Vector2 = mid + Vector2(0, 2.0)
			if o > 0.0:
				_cv.draw_circle(hinge + Vector2(0, -2.0 * o), 3.4, Color(1, 1, 1, 0.25 * o))
				_cv.draw_circle(hinge + Vector2(0, -2.0 * o), 2.6, Color(0.96, 0.96, 1.0, o))
			_draw_half_shell(hinge, r.size.x * 0.4, r.size.y * 0.42, false, shell.darkened(0.15))
			_draw_half_shell(hinge + Vector2(0, -1.0 - 4.5 * o), r.size.x * 0.4, r.size.y * 0.5, true, shell)
			_cv.draw_rect(r, Color(0.85, 0.75, 0.95, 0.4 + 0.5 * o), false, 1.2)
			return
		"boulder":
			# A BOULDER: a round-shouldered rock two cells wide, at its own size,
			# cracking with every hit
			var rock: Color = c.lerp(Color.WHITE, flash * 0.5)
			_cv.draw_rect(r.grow(1.0), Color(0.15, 0.1, 0.06, 0.8), false, 1.0)
			var inset: float = minf(r.size.y * 0.3, 4.0)
			_cv.draw_rect(Rect2(r.position + Vector2(inset, 0), Vector2(r.size.x - inset * 2.0, r.size.y)), rock.darkened(0.12))
			_cv.draw_rect(Rect2(r.position + Vector2(0, inset), Vector2(r.size.x, r.size.y - inset * 2.0)), rock.darkened(0.12))
			for cx in [r.position.x + inset, r.end.x - inset]:
				for cy in [r.position.y + inset, r.end.y - inset]:
					_cv.draw_circle(Vector2(cx, cy), inset, rock.darkened(0.12))
			_cv.draw_rect(Rect2(r.position + Vector2(inset, 1), Vector2(r.size.x - inset * 2.0, r.size.y * 0.4)), rock.lightened(0.12))
			for i in 3:
				_cv.draw_circle(Vector2(r.position.x + r.size.x * (0.22 + i * 0.28), mid.y + (1.0 if i % 2 else -1.0) * r.size.y * 0.15),
					maxf(1.0, r.size.y * 0.1), rock.darkened(0.45))
			var crack := Color(0.12, 0.08, 0.05, 0.8)
			var most_hp: int = int(k["most"])
			if k["hp"] < most_hp:
				_cv.draw_polyline(PackedVector2Array([Vector2(r.position.x + r.size.x * 0.3, r.position.y + 1), Vector2(r.position.x + r.size.x * 0.38, mid.y),
					Vector2(r.position.x + r.size.x * 0.33, r.end.y - 1)]), crack, 1.2)
			if k["hp"] < most_hp - 1:
				_cv.draw_polyline(PackedVector2Array([Vector2(r.position.x + r.size.x * 0.68, r.position.y + 1), Vector2(r.position.x + r.size.x * 0.6, mid.y),
					Vector2(r.position.x + r.size.x * 0.72, r.end.y - 1)]), crack, 1.2)
			if k["hp"] <= 1:
				_cv.draw_line(Vector2(r.position.x + 3, mid.y), Vector2(r.end.x - 3, mid.y + 1), crack, 1.2)
			return
		"lava":
			# LAVA: molten under a dark crust, bubbling and glowing - it greys
			# as it cools toward basalt
			var cool: float = clampf(1.0 - float(k.get("cool", LAVA_COOL)) / LAVA_COOL, 0.0, 1.0)
			var throb: float = 0.5 + 0.5 * sin(t * 4.0 + r.position.x * 0.05)
			_cv.draw_rect(r, Color(0.4, 0.07, 0.02).lerp(Color(0.3, 0.27, 0.27), cool).lerp(Color.WHITE, flash * 0.5))
			var molten := Color(1.0, 0.82, 0.25).lerp(Color(1.0, 0.45, 0.1), 0.4 * throb).lerp(Color(0.5, 0.33, 0.28), cool)
			_cv.draw_rect(Rect2(r.position + Vector2(2, 2), r.size - Vector2(4, 4)), molten)
			for i in 3:
				var bx: float = r.position.x + 6.0 + i * 8.0
				var rise: float = fmod(t * 1.3 + i * 0.37 + r.position.x * 0.01, 1.0)
				_cv.draw_circle(Vector2(bx, r.end.y - 3.0 - rise * (r.size.y - 6.0)), 1.6 * (1.0 - rise) + 0.6,
					Color(1.0, 1.0, 0.8, (1.0 - cool) * 0.9))
			_cv.draw_rect(r.grow(1.0), Color(1.0, 0.55, 0.1, (0.35 + 0.4 * throb) * (1.0 - cool)), false, 1.5)
			return
		"heart":
			var pulse: float = 0.5 + 0.5 * sin(t * 3.0)
			var hw: float = r.size.x * 0.46
			var hh: float = r.size.y * 0.5 + 3.0
			_cv.draw_circle(mid, hw + 6.0 + pulse * 5.0, Color(BLIGHT, 0.10 + 0.05 * pulse))
			var gem := PackedVector2Array([mid + Vector2(0, -hh), mid + Vector2(hw, 0), mid + Vector2(0, hh), mid + Vector2(-hw, 0)])
			_cv.draw_colored_polygon(gem, BLIGHT.darkened(0.3).lerp(COLOURS["light"], 0.25 + pulse * 0.2).lerp(Color.WHITE, flash * 0.6))
			_cv.draw_colored_polygon(PackedVector2Array([gem[0], gem[1], mid]), Color(1, 1, 1, 0.25))
			_cv.draw_polyline(PackedVector2Array([gem[0], gem[1], gem[2], gem[3], gem[0]]), COLOURS["light"], 2.0)
			for i in k["most"]:
				_cv.draw_circle(mid + Vector2(-12.5 + i * 5.0, hh + 6.0), 2.0, COLOURS["light"] if i < k["hp"] else Color(1, 1, 1, 0.15))
			return
	var base: Color = c.darkened(0.38).lerp(COLOURS["fire"], lit * 0.6).lerp(Color.WHITE, flash * 0.55)
	_cv.draw_rect(r, base)
	_cv.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.48)), c.lerp(Color.WHITE, 0.1).lerp(Color.WHITE, flash * 0.55))
	_cv.draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(1, 1, 1, 0.38))
	_cv.draw_rect(Rect2(r.position.x, r.end.y - 2, r.size.x, 2), Color(0, 0, 0, 0.4))
	var ink := Color(1, 1, 1, 0.6)
	if k.has("tide"):
		# BROUGHT BACK BY THE TIDE: foam along its top
		for i in 4:
			_cv.draw_arc(Vector2(r.position.x + 3.5 + i * (r.size.x - 7.0) / 3.0, r.position.y + 2.0), 2.4, 0, PI, 6,
				Color(0.9, 0.97, 1.0, 0.8), 1.2)
	if k.has("kite"):
		# A KITE: a cross-spar, and a tail of bows fluttering under it
		_cv.draw_line(Vector2(mid.x, r.position.y + 1), Vector2(mid.x, r.end.y - 1), Color(1, 1, 1, 0.45), 1.0)
		for i in 3:
			var at: Vector2 = Vector2(mid.x + sin(t * 6.0 + i + r.position.y) * 3.0, r.end.y + 4.0 + i * 5.0)
			_cv.draw_line(at + Vector2(-3, -2), at + Vector2(3, 2), Color(COLOURS["fire"], 0.85), 2.0)
			_cv.draw_line(at + Vector2(-3, 2), at + Vector2(3, -2), Color(COLOURS["fire"], 0.85), 2.0)
	match k["kind"]:
		"stone":
			_cv.draw_line(Vector2(r.position.x, mid.y), Vector2(r.end.x, mid.y), Color(0, 0, 0, 0.28), 1.0)
			_cv.draw_line(Vector2(mid.x - 6, r.position.y), Vector2(mid.x - 6, mid.y), Color(0, 0, 0, 0.28), 1.0)
			_cv.draw_line(Vector2(mid.x + 8, mid.y), Vector2(mid.x + 8, r.end.y), Color(0, 0, 0, 0.28), 1.0)
			if k["hp"] <= 2:
				_cv.draw_polyline(PackedVector2Array([r.position + Vector2(6, 2), mid + Vector2(-3, 1), mid + Vector2(5, -3)]), Color(0, 0, 0, 0.7), 1.4)
			if k["hp"] <= 1:
				_cv.draw_polyline(PackedVector2Array([mid + Vector2(-3, 1), mid + Vector2(2, 7), r.end - Vector2(5, 2)]), Color(0, 0, 0, 0.7), 1.4)
		"tnt":
			_cv.draw_rect(Rect2(r.position.x + 4, mid.y - 2, r.size.x - 8, 4), Color(0.25, 0.08, 0.05))
			_cv.draw_circle(mid + Vector2(11, -5), 1.8 + sin(t * 20.0), Color(1, 0.8, 0.3))
			_text(mid + Vector2(0, 4), "TNT", 9, Color(1, 0.95, 0.85), null, true, 1.0, 0)
		"bonus":
			var glow: float = 0.5 + 0.5 * sin(t * 5.0)
			_cv.draw_rect(r.grow(2.0 + glow * 2.0), Color(GOLD, 0.25 * glow), false, 2.0)
			_text(mid + Vector2(0, 5), "?", 13, Color(0.35, 0.22, 0.02), null, true, 1.0, 0)
		"blight", "plague":
			for i in 3:
				var at: Vector2 = mid + Vector2(-7 + i * 7, sin(t * 3.0 + i + r.position.x) * 1.5)
				_cv.draw_circle(at, 1.8, Color(0.75, 0.95, 0.35, 0.8))
			if k["kind"] == "plague":
				_cv.draw_rect(r, Color(0.1, 0.16, 0.06, 0.8), false, 1.5)
				if k["hp"] <= 1:
					_cv.draw_line(r.position + Vector2(5, 2), mid + Vector2(2, 3), Color(0, 0, 0, 0.6), 1.2)
		"crystal":
			_cv.draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -6), mid + Vector2(7, 0), mid + Vector2(0, 6), mid + Vector2(-7, 0)]),
				Color(1, 1, 1, 0.85))
			_cv.draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -6), mid + Vector2(7, 0), mid]), Color(0.6, 0.9, 1.0, 0.9))
		"key":
			_cv.draw_circle(mid + Vector2(-6, 0), 3.2, Color(0.4, 0.26, 0.04))
			_cv.draw_line(mid + Vector2(-3, 0), mid + Vector2(8, 0), Color(0.4, 0.26, 0.04), 1.8)
			_cv.draw_line(mid + Vector2(5, 0), mid + Vector2(5, 3), Color(0.4, 0.26, 0.04), 1.6)
			_cv.draw_line(mid + Vector2(8, 0), mid + Vector2(8, 3), Color(0.4, 0.26, 0.04), 1.6)
		"gold":
			_cv.draw_circle(mid, 4.5, Color(1.0, 0.92, 0.5))
			_cv.draw_arc(mid, 4.5, 0, TAU, 14, Color(0.55, 0.38, 0.05), 1.2)
			var sweep: float = fmod(t * 0.8 + r.position.x * 0.01, 1.6) - 0.3
			if sweep >= 0.0 and sweep <= 1.0:
				var x: float = r.position.x + r.size.x * sweep
				_cv.draw_line(Vector2(x, r.position.y + 1), Vector2(x - 4, r.end.y - 1), Color(1, 1, 1, 0.6), 2.0)
			if k["hp"] <= 1:
				_cv.draw_line(r.position + Vector2(4, 1), mid + Vector2(-1, 2), Color(0, 0, 0, 0.5), 1.2)
		"shell":
			for i in 3:
				_cv.draw_arc(mid + Vector2(0, 6), 3.0 + i * 3.0, PI * 1.15, PI * 1.85, 10, Color(0.55, 0.35, 0.3, 0.8), 1.2)
		"prism":
			for i in ELEMENTS.size():
				var w: float = r.size.x / ELEMENTS.size()
				_cv.draw_rect(Rect2(r.position.x + i * w, r.end.y - 3, w, 3), COLOURS[ELEMENTS[i]])
			_cv.draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -5), mid + Vector2(5, 3), mid + Vector2(-5, 3)]), Color(1, 1, 1, 0.75))
		"packed":
			# PACKED ICE: dense blue, a sheen across it, cracking as it is hit
			_cv.draw_line(r.position + Vector2(4, r.size.y - 3), r.position + Vector2(r.size.x * 0.45, 3), Color(1, 1, 1, 0.35), 2.0)
			if k["hp"] <= 2:
				_cv.draw_polyline(PackedVector2Array([r.position + Vector2(6, 2), mid + Vector2(-3, 1), mid + Vector2(5, -3)]), Color(0.1, 0.25, 0.4, 0.8), 1.4)
			if k["hp"] <= 1:
				_cv.draw_polyline(PackedVector2Array([mid + Vector2(-3, 1), mid + Vector2(2, 7), r.end - Vector2(5, 2)]), Color(0.1, 0.25, 0.4, 0.8), 1.4)
		"column":
			# A PILLAR'S STONE: fluted, cracked once struck
			for f in [0.3, 0.5, 0.7]:
				_cv.draw_line(Vector2(r.position.x + r.size.x * f, r.position.y + 2), Vector2(r.position.x + r.size.x * f, r.end.y - 2),
					Color(0.25, 0.18, 0.1, 0.45), 1.2)
			if k["hp"] <= 1:
				_cv.draw_polyline(PackedVector2Array([r.position + Vector2(5, 2), mid + Vector2(-2, 1), mid + Vector2(6, 4)]), Color(0, 0, 0, 0.7), 1.3)
		"foot":
			# A PILLAR'S FOOT: a plinth, wider at its base; cracked, it glows
			# along the crack - the next blow or tremor brings the pillar down
			_cv.draw_rect(Rect2(r.position.x, r.end.y - 4, r.size.x, 4), Color(0.22, 0.1, 0.04, 0.85))
			_cv.draw_colored_polygon(PackedVector2Array([mid + Vector2(-7, 3), mid + Vector2(0, -5), mid + Vector2(7, 3)]), Color(0.3, 0.12, 0.04, 0.85))
			_cv.draw_colored_polygon(PackedVector2Array([mid + Vector2(-4, 2), mid + Vector2(0, -2), mid + Vector2(4, 2)]), Color(1.0, 0.75, 0.4, 0.9))
			if k["hp"] < k["most"]:
				var glow: float = 0.55 + 0.45 * sin(t * 7.0 + r.position.x * 0.1)
				var split := PackedVector2Array([r.position + Vector2(3, 3), mid + Vector2(-4, 2), mid + Vector2(3, -2), r.end - Vector2(4, 3)])
				_cv.draw_polyline(split, Color(1.0, 0.72, 0.3, 0.6 * glow), 3.0)
				_cv.draw_polyline(split, Color(0.1, 0.05, 0.0, 0.9), 1.3)
		"ore":
			# ORE: dark rock, gold glinting in it
			for at in [Vector2(-8, -2), Vector2(-1, 3), Vector2(6, -3), Vector2(10, 3)]:
				var fleck: Vector2 = mid + at
				_cv.draw_colored_polygon(PackedVector2Array([fleck + Vector2(0, -3.5), fleck + Vector2(3.5, 0), fleck + Vector2(0, 3.5), fleck + Vector2(-3.5, 0)]),
					GOLD.lerp(Color.WHITE, 0.3 * (0.5 + 0.5 * sin(t * 4.0 + at.x))))
			if k["hp"] <= 2:
				_cv.draw_polyline(PackedVector2Array([r.position + Vector2(5, 1), mid + Vector2(-4, 0), mid + Vector2(2, 6)]), Color(0, 0, 0, 0.7), 1.3)
			if k["hp"] <= 1:
				_cv.draw_polyline(PackedVector2Array([mid + Vector2(2, -6), mid + Vector2(5, 1), r.end - Vector2(4, 2)]), Color(0, 0, 0, 0.7), 1.3)
		"lantern":
			# A LANTERN: a lamp behind glass, its flame flickering
			_cv.draw_rect(Rect2(mid.x - 5, r.position.y + 2, 10, r.size.y - 4), Color(1.0, 0.85, 0.45, 0.35))
			_cv.draw_rect(Rect2(mid.x - 5, r.position.y + 2, 10, r.size.y - 4), Color(0.25, 0.2, 0.1), false, 1.2)
			var flick: float = 0.8 + 0.2 * sin(t * 13.0 + r.position.x)
			_cv.draw_colored_polygon(PackedVector2Array([mid + Vector2(-2.5, 3), mid + Vector2(0, -4.5 * flick), mid + Vector2(2.5, 3)]), Color(1.0, 0.95, 0.6))
			_cv.draw_line(Vector2(mid.x - 7, r.position.y + 2), Vector2(mid.x + 7, r.position.y + 2), Color(0.25, 0.2, 0.1), 1.5)
		"shadow":
			# A SHADOW BRICK: smoke curling in it; it heals in the dark
			for i in 3:
				var sx: float = r.position.x + 6.0 + i * 8.0 + sin(t * 2.0 + i) * 2.0
				_cv.draw_arc(Vector2(sx, mid.y), 3.0, t * 2.0 + i, t * 2.0 + i + PI * 1.3, 8, Color(0.75, 0.6, 1.0, 0.55), 1.2)
			if k["hp"] <= 1:
				_cv.draw_line(r.position + Vector2(5, 2), mid + Vector2(2, 4), Color(0.85, 0.75, 1.0, 0.7), 1.2)
		"void":
			# A VOID WELL: a hole of night, its rim turning inward
			_cv.draw_circle(mid, r.size.y * 0.42, Color(0.02, 0.0, 0.05))
			for i in 3:
				var a0: float = -t * 4.0 + i * TAU / 3.0
				_cv.draw_arc(mid, r.size.y * 0.42 + 1.5, a0, a0 + 1.6, 8, Color(0.75, 0.55, 1.0, 0.85), 1.5)
			if k["hp"] < k["most"]:
				_cv.draw_line(r.position + Vector2(3, 2), r.position + Vector2(8, 6), Color(0.85, 0.75, 1.0, 0.7), 1.2)
			if k["hp"] <= 1:
				_cv.draw_line(r.end - Vector2(3, 2), r.end - Vector2(8, 6), Color(0.85, 0.75, 1.0, 0.7), 1.2)
		"wood":
			# WOOD: planks and grain; struck once, split
			for f in [0.33, 0.66]:
				_cv.draw_line(Vector2(r.position.x + 2, r.position.y + r.size.y * f), Vector2(r.end.x - 2, r.position.y + r.size.y * f),
					Color(0.3, 0.16, 0.06, 0.6), 1.0)
			for i in 3:
				var gx: float = r.position.x + 5.0 + i * 8.0
				_cv.draw_arc(Vector2(gx, mid.y), 2.0, 0, TAU, 8, Color(0.35, 0.2, 0.08, 0.6), 1.0)
			if k["hp"] <= 1:
				_cv.draw_line(r.position + Vector2(6, 1), mid + Vector2(3, 6), Color(0, 0, 0, 0.7), 1.3)
		"fuse":
			# A FUSE: a cord along a dark slot; lit, a spark runs on it
			_cv.draw_rect(Rect2(r.position.x, mid.y - 3, r.size.x, 6), Color(0.15, 0.1, 0.06, 0.8))
			for i in 4:
				var fx: float = r.position.x + 3.0 + i * (r.size.x - 6.0) / 3.0
				_cv.draw_line(Vector2(fx - 3, mid.y - 2), Vector2(fx + 3, mid.y + 2), Color(0.85, 0.75, 0.5), 1.4)
			if k["burn"] >= 0.0:
				_cv.draw_circle(mid, 4.0 + 1.5 * sin(t * 30.0), Color(1.0, 0.85, 0.3, 0.9))
				_cv.draw_circle(mid, 2.0, Color(1, 1, 1))
		"keg":
			# A POWDER KEG: a barrel, iron bands, its mark
			_cv.draw_rect(Rect2(r.position.x + 2, r.position.y + 1, r.size.x - 4, r.size.y - 2), Color(0.45, 0.25, 0.12, 0.6))
			for f in [0.2, 0.8]:
				_cv.draw_rect(Rect2(r.position.x + 1, r.position.y + r.size.y * f - 1, r.size.x - 2, 2), Color(0.25, 0.25, 0.28))
			_text(mid + Vector2(0, 4), "!!", 10, Color(1.0, 0.85, 0.35), null, true, 1.0, 0)
			if k["hp"] <= 1:
				_cv.draw_line(r.position + Vector2(5, 2), mid + Vector2(-2, 3), Color(0, 0, 0, 0.7), 1.3)
		"obsidian":
			# OBSIDIAN: black glass, a violet sheen, cracking
			_cv.draw_line(r.position + Vector2(4, r.size.y - 3), r.position + Vector2(r.size.x * 0.5, 2), Color(0.75, 0.6, 1.0, 0.45), 2.0)
			if k["hp"] < k["most"]:
				_cv.draw_polyline(PackedVector2Array([r.position + Vector2(6, 2), mid + Vector2(-3, 1), mid + Vector2(5, -3)]), Color(0.8, 0.7, 1.0, 0.7), 1.2)
			if k["hp"] <= 2:
				_cv.draw_polyline(PackedVector2Array([mid + Vector2(-3, 1), mid + Vector2(2, 7), r.end - Vector2(5, 2)]), Color(0.8, 0.7, 1.0, 0.7), 1.2)
			if k["hp"] <= 1:
				_cv.draw_line(Vector2(r.position.x + 3, mid.y + 2), Vector2(r.end.x - 3, mid.y - 1), Color(0.8, 0.7, 1.0, 0.7), 1.2)
		"basalt":
			# BASALT: cooled lava, dark columns
			for f in [0.25, 0.5, 0.75]:
				_cv.draw_line(Vector2(r.position.x + r.size.x * f, r.position.y + 1), Vector2(r.position.x + r.size.x * f, r.end.y - 1),
					Color(0, 0, 0, 0.45), 1.0)
			if k["hp"] <= 2:
				_cv.draw_line(r.position + Vector2(4, 2), mid + Vector2(2, 2), Color(0, 0, 0, 0.7), 1.3)
			if k["hp"] <= 1:
				_cv.draw_line(mid + Vector2(2, 2), r.end - Vector2(4, 2), Color(0, 0, 0, 0.7), 1.3)
		"sand":
			# SAND: fine grains, a ripple along its top
			for i in 6:
				_cv.draw_circle(Vector2(r.position.x + 3.0 + i * (r.size.x - 6.0) / 5.0, mid.y + (2.0 if i % 2 else -1.0) + 1.5), 0.9,
					Color(0.55, 0.42, 0.2, 0.8))
			for i in 3:
				_cv.draw_arc(Vector2(r.position.x + 5.0 + i * (r.size.x - 10.0) / 2.0, r.position.y + 4.0), 3.5, PI * 1.1, PI * 1.9, 6,
					Color(1, 1, 1, 0.5), 1.0)
		"buoy":
			# A BUOY: a red float banded white, its lamp blinking
			var float_r := Rect2(mid.x - r.size.x * 0.28, r.position.y + 2.5, r.size.x * 0.56, r.size.y - 5.0)
			_cv.draw_rect(float_r, Color(0.9, 0.24, 0.2).lerp(Color.WHITE, flash * 0.5))
			_cv.draw_rect(Rect2(float_r.position.x, mid.y - 1.5, float_r.size.x, 3.0), Color(0.97, 0.95, 0.92))
			_cv.draw_rect(Rect2(float_r.position, Vector2(float_r.size.x, 1.5)), Color(1, 1, 1, 0.45))
			var blink: float = 0.5 + 0.5 * sin(t * 5.0 + r.position.x * 0.07)
			_cv.draw_circle(Vector2(mid.x, float_r.position.y + 0.5), 1.6, Color(1.0, 0.95, 0.55, 0.4 + 0.6 * blink))
			_cv.draw_line(Vector2(r.position.x + 2, r.end.y - 2.5), Vector2(r.end.x - 2, r.end.y - 2.5), Color(0.8, 0.92, 1.0, 0.5), 1.0)
		"bubble":
			# A BUBBLE BRICK: bubbles caught in it, wobbling
			for i in 3:
				var at: Vector2 = mid + Vector2(-7 + i * 7, sin(t * 4.0 + i * 1.7 + r.position.x) * 2.0)
				_cv.draw_arc(at, 2.2 + (i % 2) * 1.2, 0, TAU, 10, Color(0.85, 0.95, 1.0, 0.85), 1.1)
		"mimic":
			var shimmer: float = 0.5 + 0.5 * sin(t * 4.0 + r.position.x * 0.1)
			_cv.draw_arc(mid, 4.0, t * 4.0, t * 4.0 + PI * 1.4, 10, Color(1, 1, 1, 0.5 + 0.4 * shimmer), 1.4)
			_cv.draw_circle(mid + Vector2(5, 3), 1.2, Color(1, 1, 1, 0.7))
		"land":
			match k["land"]:
				"fire":
					_cv.draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -5), mid + Vector2(3.5, 1.5), mid + Vector2(0, 5), mid + Vector2(-3.5, 1.5)]), ink)
				"ice":
					for a in 3:
						var d := Vector2.from_angle(a * PI / 3.0) * 4.5
						_cv.draw_line(mid - d, mid + d, ink, 1.3)
				"water":
					_cv.draw_arc(mid + Vector2(-3.5, 1), 3.5, PI, TAU, 8, ink, 1.2)
					_cv.draw_arc(mid + Vector2(3.5, 1), 3.5, 0, PI, 8, ink, 1.2)
				"wind":
					_cv.draw_line(mid + Vector2(-6, -2), mid + Vector2(4, -2), ink, 1.2)
					_cv.draw_line(mid + Vector2(-4, 2.5), mid + Vector2(6, 2.5), ink, 1.2)
				"earth":
					_cv.draw_rect(Rect2(mid - Vector2(3.5, 3.5), Vector2(7, 7)), ink, false, 1.2)
					if k["hp"] == 1:
						_cv.draw_polyline(PackedVector2Array([r.position + Vector2(5, 0), mid + Vector2(-2, 2), r.end - Vector2(6, 0)]), Color(0, 0, 0, 0.6), 1.3)
				"light":
					_cv.draw_circle(mid, 2.5, ink)
				"dark":
					_cv.draw_arc(mid, 4.5, 0, TAU, 14, ink, 1.2)


func _draw_boss() -> void:
	"""The boss's own drawing (its shots, its minions' shadows), and its health
	along the arena's top over its hall."""
	if boss == null:
		return
	var c: Color = COLOURS.get(boss.land, Color.WHITE)
	boss.draw(self, c, INK)
	var bar := Rect2(hall.position.x + 20, ARENA.position.y + 9, hall.size.x - 40, 6)
	draw_rect(bar.grow(2), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(boss.hp) / float(boss.most), bar.size.y)), c)
	_text(Vector2(hall.position.x + 10, hall.position.y + 14), str(boss.title), 12, INK)


func _draw_capsule(c: Dictionary) -> void:
	"""A FALLING BONUS: a capsule in its own colour with its own mark - an
	Elemental Ball's in its land's colour with its land's brick mark, so a
	Light from a Dark reads in the air."""
	var col: Color = COLOURS[str(c["land"])] if c.has("land") else bonus_colour(str(c["kind"]))
	var p: Vector2 = c["p"]
	p.x = clampf(p.x, ARENA.position.x + 42.0, ARENA.end.x - 42.0)
	var r := Rect2(p - Vector2(30, 11), Vector2(60, 22))
	draw_circle(p, 28.0, Color(col, 0.12 + 0.06 * sin(t * 8.0)))
	draw_rect(r, col.darkened(0.45))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 9)), col)
	draw_circle(Vector2(r.position.x, p.y), 11.0, col.darkened(0.2))
	draw_circle(Vector2(r.end.x, p.y), 11.0, col.darkened(0.2))
	if c["kind"] == "element":
		draw_circle(p, 9.5, col.darkened(0.5))
		_draw_land_mark(str(c.get("land", "light")), p, Color(1, 1, 1), 1.5)
		draw_arc(p, 9.5, 0, TAU, 18, Color(1, 1, 1, 0.7), 1.2)
	else:
		_draw_icon(c["kind"], p, Color(1, 1, 1), 1.0)


func _draw_icon(kind: String, p: Vector2, ink: Color, s: float) -> void:
	match kind:
		"multi":
			for i in 3:
				draw_circle(p + Vector2(-8 + i * 8, 0) * s, 3.2 * s, ink)
		"wide":
			draw_line(p + Vector2(-11, 0) * s, p + Vector2(11, 0) * s, ink, 2.5 * s)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-14, 0) * s, p + Vector2(-8, -5) * s, p + Vector2(-8, 5) * s]), ink)
			draw_colored_polygon(PackedVector2Array([p + Vector2(14, 0) * s, p + Vector2(8, -5) * s, p + Vector2(8, 5) * s]), ink)
		"laser":
			for x in [-5.0, 5.0]:
				draw_line(p + Vector2(x, 7) * s, p + Vector2(x, -6) * s, ink, 2.5 * s)
				draw_circle(p + Vector2(x, -7) * s, 2.0 * s, ink)
		"shield":
			draw_arc(p + Vector2(0, 6) * s, 11.0 * s, PI * 1.15, PI * 1.85, 12, ink, 2.5 * s)
		"fire":
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -9) * s, p + Vector2(6, 2) * s, p + Vector2(0, 8) * s,
				p + Vector2(-6, 2) * s]), ink)
		"slow":
			for a in 3:
				var d := Vector2.from_angle(a * PI / 3.0) * 8.0 * s
				draw_line(p - d, p + d, ink, 2.0 * s)
		"magnet":
			draw_arc(p + Vector2(0, -1) * s, 7.0 * s, 0.0, PI, 12, ink, 3.0 * s)
			for x in [-7.0, 7.0]:
				draw_line(p + Vector2(x, -1) * s, p + Vector2(x, -8) * s, ink, 3.0 * s)
				draw_line(p + Vector2(x, -6) * s, p + Vector2(x, -9) * s, Color(1.0, 0.45, 0.45), 3.0 * s)
		"split":
			draw_line(p + Vector2(0, 8) * s, p + Vector2(0, 1) * s, ink, 2.5 * s)
			for x in [-7.0, 7.0]:
				draw_line(p + Vector2(0, 1) * s, p + Vector2(x, -6) * s, ink, 2.5 * s)
				draw_circle(p + Vector2(x, -7) * s, 2.6 * s, ink)
		"big":
			draw_arc(p, 8.0 * s, 0, TAU, 18, ink, 2.0 * s)
			draw_circle(p, 4.0 * s, ink)
		"life":
			_heart(p + Vector2(0, -1) * s, 0.9 * s, ink)
		"element":
			for i in ELEMENTS.size():
				var a0: float = i * TAU / ELEMENTS.size()
				draw_arc(p, 7.5 * s, a0, a0 + TAU / ELEMENTS.size(), 4, COLOURS[ELEMENTS[i]].lightened(0.3), 3.0 * s)
			draw_circle(p, 3.0 * s, ink)


func _draw_land_mark(land: String, p: Vector2, ink: Color, s: float) -> void:
	"""A land's mark, as its bricks wear it (fire a flame, ice a star...)."""
	match land:
		"fire":
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -5) * s, p + Vector2(3.5, 1.5) * s, p + Vector2(0, 5) * s,
				p + Vector2(-3.5, 1.5) * s]), ink)
		"ice":
			for a in 3:
				var d := Vector2.from_angle(a * PI / 3.0) * 4.5 * s
				draw_line(p - d, p + d, ink, 1.3 * s)
		"water":
			draw_arc(p + Vector2(-3.5, 1) * s, 3.5 * s, PI, TAU, 8, ink, 1.2 * s)
			draw_arc(p + Vector2(3.5, 1) * s, 3.5 * s, 0, PI, 8, ink, 1.2 * s)
		"wind":
			draw_line(p + Vector2(-6, -2) * s, p + Vector2(4, -2) * s, ink, 1.2 * s)
			draw_line(p + Vector2(-4, 2.5) * s, p + Vector2(6, 2.5) * s, ink, 1.2 * s)
		"earth":
			draw_rect(Rect2(p - Vector2(3.5, 3.5) * s, Vector2(7, 7) * s), ink, false, 1.2 * s)
		"light":
			draw_circle(p, 2.5 * s, ink)
		"dark":
			draw_arc(p, 4.5 * s, 0, TAU, 14, ink, 1.2 * s)


func _draw_ball(b: Dictionary) -> void:
	var p: Vector2 = b["p"]
	var fire: bool = active.has("fire") or final_fire
	var el: String = str(b.get("el", ""))
	var core: Color = Color(1.0, 0.75, 0.4) if fire else Color(0.92, 0.99, 1.0)
	var halo: Color = COLOURS["fire"] if fire else Color(0.7, 0.95, 1.0)
	if not fire and el != "":
		# CHARGED: the ball wears the land it carries
		halo = COLOURS[el]
		core = COLOURS[el].lerp(Color.WHITE, 0.55)
	var rad: float = ball_r()
	draw_circle(p, rad * 2.8, Color(halo, 0.10))
	draw_circle(p, rad * 1.7, Color(halo, 0.24))
	draw_circle(p, rad, core)
	if element() != "":
		# AN ELEMENTAL BALL: its land's sparks circling it
		for i in 3:
			var a: float = t * 6.0 + i * TAU / 3.0
			draw_circle(p + Vector2.from_angle(a) * rad * 1.9, 1.8, COLOURS[element()].lightened(0.4))
	draw_circle(p + Vector2(-2.3, -2.3) * rad / BALL_R, rad * 0.35, Color(1, 1, 1))


func _draw_paddle() -> void:
	var half: float = paddle_w / 2.0
	var r := Rect2(paddle_x - half, PADDLE_Y - 7.0, paddle_w, 14.0)
	var glow: Color = Color(0.6, 0.6, 0.7) if stunned > 0.0 else GOLD
	for i in 4:
		draw_rect(r.grow(3.0 + i * 3.0), Color(glow, 0.09 - i * 0.018))
	draw_rect(r, Color(0.2, 0.18, 0.25))
	draw_circle(Vector2(r.position.x, PADDLE_Y), 7.0, Color(0.2, 0.18, 0.25))
	draw_circle(Vector2(r.end.x, PADDLE_Y), 7.0, Color(0.2, 0.18, 0.25))
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 5.0), glow)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 2.0), Color(1, 0.95, 0.8))
	var core: float = 0.6 + 0.4 * sin(t * 6.0)
	draw_line(Vector2(r.position.x + 14, PADDLE_Y + 2), Vector2(r.end.x - 14, PADDLE_Y + 2), Color(0.55, 0.95, 1.0, core), 2.0)
	for x in [r.position.x, r.end.x]:
		draw_circle(Vector2(x, PADDLE_Y), 4.0, glow)
		draw_circle(Vector2(x, PADDLE_Y), 2.0, Color(1, 1, 1))
	if iced > 0.0:
		# ICED: frost over the paddle while it slides
		draw_rect(r.grow(2.0), Color(0.85, 0.96, 1.0, 0.45))
		for x in range(int(r.position.x) + 6, int(r.end.x) - 4, 12):
			draw_line(Vector2(x, r.position.y - 2.0), Vector2(x + 4, r.position.y + 5.0), Color(1, 1, 1, 0.8), 1.0)
	if hexed > 0.0:
		# HEXED: a violet sheen, arrows crossed over it
		draw_rect(r.grow(1.5), Color(COLOURS["dark"].lightened(0.2), 0.35 + 0.15 * sin(t * 10.0)))
		for side in [-1.0, 1.0]:
			var tip := Vector2(paddle_x + side * 16.0, PADDLE_Y - 14.0)
			draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-side * 7.0, -4.0), tip + Vector2(-side * 7.0, 4.0)]),
				COLOURS["dark"].lightened(0.5))
	if scorched > 0.0:
		# SCORCHED: charred, smouldering along its top
		draw_rect(r.grow(1.0), Color(0.25, 0.08, 0.02, 0.45))
		for x in range(int(r.position.x) + 5, int(r.end.x) - 3, 9):
			var up: float = fmod(t * 40.0 + x * 3.0, 10.0)
			draw_circle(Vector2(x, r.position.y - 1.0 - up), 1.5, Color(1.0, 0.6, 0.2, 1.0 - up / 10.0))
	if heavy > 0.0:
		# HEAVY: rocks piled on the paddle while it drags
		draw_rect(r.grow(1.5), Color(0.3, 0.22, 0.12, 0.4))
		var n: int = int(r.size.x / 22.0)
		for i in n:
			var at := Vector2(r.position.x + 11.0 + i * (r.size.x - 22.0) / maxf(1.0, n - 1.0), r.position.y - 3.0 - (i % 2) * 2.0)
			draw_circle(at, 4.5, Color(0.45, 0.38, 0.3))
			draw_circle(at + Vector2(-1.2, -1.4), 1.6, Color(0.7, 0.62, 0.52))
	if active.has("magnet"):
		# THE MAGNET: a purple field over the paddle, pulsing
		var pulse: float = 0.5 + 0.5 * sin(t * 5.0)
		draw_rect(Rect2(r.position.x, r.position.y - 6.0, r.size.x, 6.0), Color(COLOURS["dark"].lightened(0.3), 0.18 + 0.15 * pulse))
		for x in [r.position.x + 10.0, r.end.x - 10.0]:
			draw_arc(Vector2(x, PADDLE_Y - 2.0), 5.0, PI, TAU, 8, COLOURS["dark"].lightened(0.4), 2.0)
	if active.has("laser"):
		for side in [-1.0, 1.0]:
			var cx: float = paddle_x + side * (half - 12.0)
			draw_rect(Rect2(cx - 4, PADDLE_Y - 15, 8, 10), Color(0.75, 0.25, 0.12))
			draw_rect(Rect2(cx - 2, PADDLE_Y - 18, 4, 4), Color(1, 0.7, 0.4))
			if _muzzle > 0.0:
				draw_circle(Vector2(cx, PADDLE_Y - 20), 6.0 * _muzzle, Color(1, 0.85, 0.5, _muzzle))


func _path(from: Vector2, dir: Vector2, length: float) -> PackedVector2Array:
	"""Where a ball from `from` along `dir` goes: off the walls, to the first
	row of bricks it meets, and no further than the paddle's line."""
	var pts := PackedVector2Array([from])
	var p := from
	var d := dir
	var left := length
	for i in 4:
		var hit_t: float = INF
		var normal := Vector2.ZERO
		if d.x < 0.0:
			var tx: float = (ARENA.position.x + BALL_R - p.x) / d.x
			if tx < hit_t:
				hit_t = tx
				normal = Vector2.RIGHT
		if d.x > 0.0:
			var tx: float = (ARENA.end.x - BALL_R - p.x) / d.x
			if tx < hit_t:
				hit_t = tx
				normal = Vector2.LEFT
		if d.y > 0.0:
			var tp: float = (PADDLE_Y - 10.0 - p.y) / d.y
			if tp < hit_t:
				hit_t = tp
				normal = Vector2.ZERO
		if d.y < 0.0:
			var ty: float = (ARENA.position.y + BALL_R - p.y) / d.y
			for k in bricks:
				if k["hp"] <= 0 and _breaks(k):
					continue
				var r: Rect2 = (k["rect"] as Rect2).grow(BALL_R)
				var tb: float = (r.end.y - p.y) / d.y
				if tb > 0.0 and tb < ty:
					var x: float = p.x + d.x * tb
					if x >= r.position.x and x <= r.end.x:
						ty = tb
			if ty < hit_t:
				hit_t = ty
				normal = Vector2.DOWN
		if hit_t == INF or hit_t > left:
			pts.append(p + d * left)
			break
		p = p + d * hit_t
		pts.append(p)
		left -= hit_t
		if normal == Vector2.ZERO:
			break
		d = d.bounce(normal)
	return pts


func _draw_tracer(pts: PackedVector2Array, c: Color, aiming: bool, bolt: bool = false) -> void:
	"""A TRACER: the faint line, and bright streaks running along it."""
	if pts.size() < 2:
		return
	draw_polyline(pts, Color(c, 0.24 if bolt else 0.22), 2.0, true)
	var lens: Array = []
	var total: float = 0.0
	for i in pts.size() - 1:
		var l: float = pts[i].distance_to(pts[i + 1])
		lens.append(l)
		total += l
	if bolt:
		var seg := _segment_along(pts, lens, total - 34.0, total)
		if seg.size() >= 2:
			draw_polyline(seg, Color(c, 0.3), 9.0, true)
			draw_polyline(seg, Color(1, 0.9, 0.7), 3.0, true)
		return
	var spacing: float = TRACER_SPACING
	var head: float = fmod(t * TRACER_SPEED, spacing)
	while head < total:
		var seg := _segment_along(pts, lens, head - 46.0, head)
		if seg.size() >= 2:
			var fade: float = 1.0 - head / total if aiming else 1.0
			draw_polyline(seg, Color(c, 0.25 * fade), 9.0, true)
			draw_polyline(seg, Color(c, 0.95 * fade), 3.5, true)
			draw_circle(seg[seg.size() - 1], 3.0, Color(1, 1, 1, fade))
		head += spacing


func _segment_along(pts: PackedVector2Array, lens: Array, a: float, b: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var at: float = 0.0
	a = maxf(a, 0.0)
	for i in lens.size():
		var l: float = lens[i]
		var s0: float = at
		var s1: float = at + l
		if l > 0.0 and s1 >= a and s0 <= b:
			var p0: Vector2 = pts[i].lerp(pts[i + 1], clampf((a - s0) / l, 0.0, 1.0))
			var p1: Vector2 = pts[i].lerp(pts[i + 1], clampf((b - s0) / l, 0.0, 1.0))
			if out.is_empty():
				out.append(p0)
			out.append(p1)
		at = s1
	return out


func _draw_trail(b: Dictionary) -> void:
	var trail: PackedVector2Array = b["trail"]
	if trail.size() < 3:
		return
	var fire: bool = active.has("fire") or final_fire
	var c: Color = Color(1.0, 0.7, 0.4) if fire else Color(0.8, 0.97, 1.0)
	if not fire and str(b.get("el", "")) != "":
		c = COLOURS[str(b["el"])].lerp(Color.WHITE, 0.3)
	draw_polyline(trail, Color(c, 0.2), 2.0, true)
	var n: int = trail.size()
	var head := trail.slice(maxi(0, n - 9), n)
	draw_polyline(head, Color(c, 0.25), 10.0, true)
	draw_polyline(head, Color(c, 0.95), 4.0, true)
	for k in [[20, 15, 0.6], [34, 30, 0.35]]:
		var bit := trail.slice(maxi(0, n - int(k[0])), maxi(0, n - int(k[1])))
		if bit.size() >= 2:
			draw_polyline(bit, Color(c, float(k[2])), 3.0, true)


# ---------------------------------------------------------------- the frame --

func _panel(r: Rect2, tint: Color = GOLD) -> void:
	"""A FRAME: a soft shadow, a body lit from above, a bronze edge, a fine
	inner line in `tint`, and gold diamonds at its corners (the arena's)."""
	draw_rect(Rect2(r.position + Vector2(3, 5), r.size), Color(0, 0, 0, 0.45))
	var top := Color(0.085, 0.09, 0.14, 0.96)
	var foot := Color(0.04, 0.042, 0.07, 0.96)
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, foot, foot]))
	draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4, 1.5)), Color(1, 1, 1, 0.08))
	draw_rect(r, EDGE, false, 2.0)
	draw_rect(r.grow(-4), Color(tint, 0.22), false, 1.0)
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		_diamond(corner, 5.0, GOLD)


func _diamond(at: Vector2, size: float, c: Color) -> void:
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -size), at + Vector2(size, 0), at + Vector2(0, size),
		at + Vector2(-size, 0)]), c)
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -size * 0.45), at + Vector2(size * 0.45, 0),
		at + Vector2(0, size * 0.45), at + Vector2(-size * 0.45, 0)]), c.darkened(0.6))


func _divider(y: float, x0: float, x1: float, c: Color) -> void:
	"""A heading's rule: fading out both ways from a small gem."""
	var mid: float = (x0 + x1) / 2.0
	draw_polygon(PackedVector2Array([Vector2(x0, y - 0.5), Vector2(mid, y - 1.0), Vector2(x1, y - 0.5), Vector2(x1, y + 0.5),
		Vector2(mid, y + 1.0), Vector2(x0, y + 0.5)]), PackedColorArray([Color(c, 0.0), Color(c, 0.6), Color(c, 0.0),
		Color(c, 0.0), Color(c, 0.6), Color(c, 0.0)]))
	_diamond(Vector2(mid, y), 3.5, c)


func _heart(at: Vector2, size: float, c: Color) -> void:
	draw_circle(at + Vector2(-4.2, -2.0) * size, 4.6 * size, c)
	draw_circle(at + Vector2(4.2, -2.0) * size, 4.6 * size, c)
	draw_colored_polygon(PackedVector2Array([at + Vector2(-8.6, -0.6) * size, at + Vector2(8.6, -0.6) * size,
		at + Vector2(0, 9.0) * size]), c)


func _half_heart(at: Vector2, side: float, c: Color) -> void:
	"""One side of a heart (side -1 left, 1 right) - a heart cracking."""
	draw_circle(at + Vector2(side * 4.2, -2.0), 4.6, c)
	draw_colored_polygon(PackedVector2Array([at + Vector2(side * 8.6, -0.6), at + Vector2(0, -1.5), at + Vector2(0, 9.0)]), c)


func _crest(p: Vector2, c: Color) -> void:
	"""A kingdom's crest, small (the kingdom map's): its ring and castle."""
	draw_circle(p, 26.0, Color(c, 0.12))
	draw_circle(p, 22.0, c.darkened(0.55))
	draw_arc(p, 22.0, 0, TAU, 32, c, 2.0)
	var k: float = 0.62
	var base: Vector2 = p + Vector2(0, 10)
	var castle := PackedVector2Array()
	for v in [Vector2(-20, 0), Vector2(-20, -22), Vector2(-14, -22), Vector2(-14, -16), Vector2(-6, -16), Vector2(-6, -30),
			Vector2(6, -30), Vector2(6, -16), Vector2(14, -16), Vector2(14, -22), Vector2(20, -22), Vector2(20, 0)]:
		castle.append(base + v * k)
	draw_colored_polygon(castle, Color(c, 0.9))


func _text(at: Vector2, s: String, size: int, c: Color, f: Font = null, centre: bool = false, alpha: float = 1.0,
		outline: int = 4) -> void:
	var use: Font = _bold if f == null else f
	if centre:
		at.x -= use.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x / 2.0
	if outline > 0:
		_cv.draw_string_outline(use, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(0, 0, 0, 0.75 * alpha))
	_cv.draw_string(use, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)


static func thousands(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _draw_hud() -> void:
	"""THE TOP BAR, in the kingdom's colour: its crest and the map; the score
	rolling up with its gains popping off it; the gold, its coin bouncing as
	gold comes in; the combo's flame meter and the multiplier's badge; the
	lives as hearts."""
	var bar := Rect2(10, 8, 1260, 64)
	var kingdom: Dictionary = Maps.kingdom_of(map_index)
	var colour: Color = COLOURS.get(kingdom.get("land", "light"), GOLD)
	_panel(bar, colour)
	draw_polygon(PackedVector2Array([bar.position + Vector2(4, 4), bar.position + Vector2(430, 4), bar.position + Vector2(430, 60),
		bar.position + Vector2(4, 60)]), PackedColorArray([Color(colour, 0.22), Color(colour, 0.0), Color(colour, 0.0), Color(colour, 0.22)]))
	_crest(Vector2(48, 40), colour)
	var data: Dictionary = Maps.MAPS[map_index]
	_text(Vector2(82, 38), str(data["name"]), 21, INK)
	var sub: String = "Map %d of %d  ·  %s" % [Maps.in_kingdom(map_index) + 1, Maps.MAPS_A_KINGDOM, str(kingdom.get("name", ""))]
	if data.get("boss") is Dictionary:
		sub = ("The citadel" if bool(data["boss"].get("crown", false)) else "A guardian") + "  ·  " + sub
	_text(Vector2(82, 58), sub, 12, Color(colour.lightened(0.35), 0.85), _font)
	# the score
	_text(Vector2(440, 31), "SCORE", 11, Color(INK, 0.55), _font)
	_text(Vector2(440, 60), thousands(int(round(shown_score))), 26, GOLD.lerp(Color.WHITE, 0.3))
	for pop in score_pops:
		var u: float = float(pop["age"]) / 0.9
		_text(Vector2(490, 31 - u * 12.0), "+" + thousands(int(pop["n"])), 13, Color(GOLD, 1.0 - u), null, false, 1.0 - u)
	# the gold
	var hop: float = sin(_gold_bounce * PI) * 7.0
	var coin := Vector2(612, 41 - hop)
	draw_circle(Vector2(612, 55), 9.0 - hop * 0.4, Color(0, 0, 0, 0.35))
	draw_circle(coin, 13.0, Color(0.55, 0.38, 0.05))
	draw_circle(coin, 11.0, GOLD)
	draw_arc(coin, 7.0, 0, TAU, 20, Color(0.78, 0.56, 0.1), 1.5)
	var glint: float = fmod(t * 0.7, 3.0)
	draw_circle(coin + Vector2(-3.5, -3.5), 3.2 + (2.0 if glint < 0.25 else 0.0), Color(1, 0.97, 0.8, 0.95))
	_text(Vector2(634, 31), "GOLD", 11, Color(INK, 0.55), _font)
	_text(Vector2(634, 60), thousands(gold_now()), 24, INK.lerp(GOLD, _gold_bounce))
	# the combo: five segments to the next step of the multiplier
	var mult: float = _multiplier()
	var maxed: bool = mult >= 4.0
	var lit: int = 5 if maxed else combo % 5
	for i in 5:
		var x0: float = 744.0 + i * 34.0
		var seg := PackedVector2Array([Vector2(x0 + 6, 24), Vector2(x0 + 32, 24), Vector2(x0 + 26, 42), Vector2(x0, 42)])
		var heat: Color = COLOURS["fire"].lerp(GOLD, i / 4.0)
		if i < lit:
			var glow := PackedVector2Array([Vector2(x0 + 3, 21), Vector2(x0 + 35, 21), Vector2(x0 + 29, 45), Vector2(x0 - 3, 45)])
			draw_colored_polygon(glow, Color(heat, 0.25 + 0.1 * sin(t * 8.0 + i)))
			draw_colored_polygon(seg, heat)
			draw_line(Vector2(x0 + 7, 25.5), Vector2(x0 + 31, 25.5), Color(1, 1, 1, 0.5), 1.5)
		else:
			draw_colored_polygon(seg, Color(1, 1, 1, 0.06))
		var edge := seg.duplicate()
		edge.append(seg[0])
		draw_polyline(edge, Color(1, 1, 1, 0.22 if i < lit else 0.12), 1.0)
	if lit > 0 and combo > 0:
		var tip: Vector2 = Vector2(744.0 + (lit - 1) * 34.0 + 19.0, 22.0)
		var f: float = sin(t * 18.0) * 1.5
		draw_colored_polygon(PackedVector2Array([tip + Vector2(-5, 0), tip + Vector2(0, -9 - f), tip + Vector2(5, 0)]), Color(1.0, 0.75, 0.3, 0.9))
	_text(Vector2(744, 60), "COMBO %d" % combo, 13, Color(INK, 0.8))
	# the multiplier's badge, pulsing when it rises
	var badge := Vector2(942, 40)
	var grow: float = 1.0 + 0.3 * _mult_pop
	var hexa := PackedVector2Array()
	for i in 6:
		hexa.append(badge + Vector2.from_angle(PI / 6.0 + i * TAU / 6.0) * 21.0 * grow)
	var hot: bool = mult > 1.0
	draw_colored_polygon(hexa, COLOURS["fire"].darkened(0.45) if hot else Color(0.16, 0.16, 0.2))
	hexa.append(hexa[0])
	draw_polyline(hexa, COLOURS["fire"].lerp(GOLD, 0.4) if hot else Color(1, 1, 1, 0.2), 2.0)
	if _mult_pop > 0.0:
		draw_circle(badge, 26.0 * grow, Color(COLOURS["fire"], 0.25 * _mult_pop))
	_text(badge + Vector2(0, 6), "x%s" % (str(mult) if mult != floorf(mult) else str(int(mult))), int(16 * grow),
		Color.WHITE if hot else Color(INK, 0.5), null, true)
	# the lives, as hearts
	_text(Vector2(1006, 31), "LIVES", 11, Color(INK, 0.55), _font)
	for i in mini(maxi(LIVES, lives), LIVES_MOST):
		var at := Vector2(1018 + i * 30, 50)
		if i < lives:
			draw_circle(at + Vector2(0, 1), 13.0, Color(1.0, 0.3, 0.38, 0.12 + 0.05 * sin(t * 3.0 + i)))
			_heart(at, 1.0, HEART_RED)
			draw_circle(at + Vector2(-5, -4), 1.8, Color(1, 1, 1, 0.75))
		elif i == lives and _heart_crack > 0.0:
			var u: float = 1.0 - _heart_crack
			_half_heart(at + Vector2(-6.0 * u, 4.0 * u), -1.0, Color(0.95, 0.28, 0.36, _heart_crack))
			_half_heart(at + Vector2(6.0 * u, 4.0 * u), 1.0, Color(0.95, 0.28, 0.36, _heart_crack))
		else:
			_heart(at, 1.0, Color(0.2, 0.19, 0.24))


func _draw_left_panel() -> void:
	var r := Rect2(10, 86, 138, 620)
	_panel(r, COLOURS.get(Maps.kingdom_of(map_index).get("land", "light"), GOLD))
	_text(Vector2(79, 112), "BONUSES", 14, GOLD, null, true)
	_divider(122, 22, 136, GOLD)
	var y: float = 134.0
	if active.is_empty():
		_text(Vector2(79, 152), "none on", 12, Color(INK, 0.4), _font, true)
	var on: Array = CAN_FALL.filter(func(kind: String) -> bool: return active.has(kind))
	# a card each, smaller when many are on, so they always fit above the ball
	var tall: float = minf(50.0, 262.0 / maxf(1.0, on.size()))
	var big_card: bool = tall >= 46.0
	for kind in on:
		# each bonus on: its time a ring round its icon, blinking in its last
		# two seconds
		var info: Dictionary = BONUS[kind]
		var col: Color = bonus_colour(kind)
		var left: float = clampf(active[kind] / float(info["secs"]), 0.0, 1.0)
		var blink: float = (0.5 + 0.5 * sin(t * 14.0)) if float(active[kind]) < 2.0 else 1.0
		var box := Rect2(18, y, 122, tall - 6.0)
		draw_rect(box, Color(col, 0.08 + 0.08 * blink))
		draw_rect(box, Color(col, 0.3 + 0.45 * blink), false, 1.0)
		var ring_r: float = 17.5 if big_card else (tall - 6.0) * 0.42
		var at := Vector2(18 + 6 + ring_r, y + (tall - 6.0) / 2.0)
		draw_circle(at, ring_r - 2.5, col.darkened(0.45))
		draw_arc(at, ring_r, 0, TAU, 28, Color(0, 0, 0, 0.55), 3.0)
		draw_arc(at, ring_r, -PI / 2.0, -PI / 2.0 + TAU * left, 28, col.lightened(0.25), 3.0)
		var icon_s: float = 0.75 if big_card else ring_r / 23.0
		if kind == "element":
			_draw_land_mark(ball_land, at, Color(1, 1, 1), icon_s * 1.4)
		else:
			_draw_icon(kind, at, Color(1, 1, 1), icon_s)
		var tx: float = at.x + ring_r + 6.0
		if big_card:
			_text(Vector2(tx, y + 20), bonus_name(kind), 13, INK)
			_text(Vector2(tx, y + 36), "%ds" % ceili(float(active[kind])), 11, Color(col.lightened(0.3), 0.55 + 0.45 * blink), _font)
		else:
			_text(Vector2(tx, at.y + 4), bonus_name(kind), 11, INK)
			var secs: String = "%ds" % ceili(float(active[kind]))
			_text(Vector2(136 - _word_width(secs, 10), at.y + 4), secs, 10, Color(col.lightened(0.3), 0.55 + 0.45 * blink), _font)
		y += tall
	# THE BALL'S CHARGE: what it carries, and what it would set off next
	var el: String = str(balls[0].get("el", "")) if not balls.is_empty() else ""
	_text(Vector2(79, 414), "THE BALL", 13, GOLD, null, true)
	_divider(424, 22, 136, GOLD)
	var orb := Vector2(42, 452)
	var ec: Color = COLOURS.get(el, Color(0.62, 0.64, 0.72))
	if el != "":
		draw_circle(orb, 20.0, Color(ec, 0.14 + 0.06 * sin(t * 3.0)))
	draw_circle(orb, 14.0, ec.darkened(0.4) if el != "" else Color(0.22, 0.23, 0.28))
	draw_circle(orb, 11.0, ec if el != "" else Color(0.42, 0.44, 0.52))
	if el != "":
		draw_arc(orb, 7.5, t * 3.0, t * 3.0 + 2.4, 12, Color(1, 1, 1, 0.55), 1.5)
	draw_circle(orb + Vector2(-4, -4), 2.8, Color(1, 1, 1, 0.75))
	_text(Vector2(64, 450), el.to_upper() if el != "" else "PLAIN", 13, ec.lightened(0.3) if el != "" else Color(INK, 0.5))
	_text(Vector2(64, 465), "it carries" if el != "" else "carries nothing", 10, Color(INK, 0.45), _font)
	var yy: float = 492.0
	if el == "":
		_text(Vector2(79, yy), "break a land brick", 10, Color(INK, 0.45), _font, true)
		_text(Vector2(79, yy + 13), "to carry it", 10, Color(INK, 0.45), _font, true)
	else:
		for other in ELEMENTS:
			var kind: String = reaction_of(el, other)
			if other == el or kind == "clash":
				continue
			draw_circle(Vector2(27, yy - 4), 4.0, COLOURS[other])
			_text(Vector2(35, yy), "+ " + other, 10, Color(INK, 0.7), _font)
			var word: String = str(REACTION_WORDS[kind]).trim_suffix("!")
			var lands: Array = MIX_LANDS[kind]
			_text(Vector2(136 - _word_width(word, 10), yy), word, 10, COLOURS[lands[0]].lerp(COLOURS[lands[1]], 0.5).lightened(0.3))
			yy += 15.0
	if touch_slider:
		_draw_slider()
		return
	# what can fall, each kind once
	_text(Vector2(79, 556), "CAN FALL", 13, GOLD, null, true)
	_divider(566, 22, 136, GOLD)
	var i: int = 0
	for kind in CAN_FALL:
		var p := Vector2(34 + (i % 4) * 30, 588 + floorf(i / 4.0) * 30)
		var col: Color = HEART_RED if kind == "life" else COLOURS[BONUS[kind]["land"]]
		draw_rect(Rect2(p - Vector2(13, 13), Vector2(26, 26)), col.darkened(0.6))
		draw_rect(Rect2(p - Vector2(13, 13), Vector2(26, 26)), Color(col, 0.7), false, 1.0)
		draw_rect(Rect2(p - Vector2(12, 12), Vector2(24, 2)), Color(1, 1, 1, 0.12))
		_draw_icon(kind, p, Color(1, 1, 1, 0.9), 0.6)
		i += 1
	_text(Vector2(79, 680), "? bricks drop", 11, Color(INK, 0.5), _font, true)
	_text(Vector2(79, 694), "one for sure", 11, Color(INK, 0.5), _font, true)


func _draw_slider() -> void:
	"""A PHONE'S SLIDER: a sunken pad like a little arena floor, a ruler along
	it, and the paddle in small riding it where the paddle is in the arena
	(the ball on it while it waits). The pad is where the thumb is shown to
	go: any finger that lands left of the field moves the paddle
	(crownfallscreen.gd, A PHONE)."""
	var land: Color = COLOURS.get(Maps.kingdom_of(map_index).get("land", "light"), GOLD)
	var breathe: float = 0.5 + 0.5 * sin(t * 3.0)
	_text(Vector2(79, 556), "MOVE", 13, GOLD, null, true)
	_divider(566, 22, 136, GOLD)
	# the pad: sunken, its top in shadow, edged in the kingdom's colour
	var pad := Rect2(20, 578, 118, 76)
	draw_rect(pad, Color(0.015, 0.015, 0.03, 0.9))
	draw_rect(Rect2(pad.position, Vector2(pad.size.x, 7)), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(pad.position.x, pad.end.y - 22, pad.size.x, 22), Color(land, 0.07))
	draw_rect(pad, Color(land, 0.45), false, 1.0)
	draw_rect(pad.grow(-3), Color(1, 1, 1, 0.035), false, 1.0)
	for corner in [pad.position, Vector2(pad.end.x, pad.position.y), pad.end, Vector2(pad.position.x, pad.end.y)]:
		_diamond(corner, 3.5, GOLD)
	_text(Vector2(79, pad.position.y + 17), "slide here", 10, Color(INK, 0.45), _font, true)
	# its floor: a lit line and a ruler under it
	var lane: float = pad.position.y + 52.0
	var x0: float = pad.position.x + 18.0
	var x1: float = pad.end.x - 18.0
	draw_line(Vector2(x0, lane), Vector2(x1, lane), Color(land, 0.55), 2.0)
	for i in 9:
		var tx: float = lerpf(x0, x1, i / 8.0)
		draw_line(Vector2(tx, lane + 4), Vector2(tx, lane + (9.0 if i % 4 == 0 else 6.0)), Color(INK, 0.3 if i % 4 else 0.5), 1.0)
	# chevrons at its ends, breathing
	for side in [-1.0, 1.0]:
		var tip := Vector2(79.0 + side * 52.0, lane - 9.0)
		var arm := Vector2(-side * 5.0, 5.0)
		draw_polyline(PackedVector2Array([tip + Vector2(arm.x, -arm.y), tip, tip + arm]), Color(GOLD, 0.35 + 0.45 * breathe), 2.0)
	# the paddle in small, where the paddle is
	var share: float = clampf((paddle_x - ARENA.position.x - paddle_w / 2.0) / maxf(1.0, ARENA.size.x - paddle_w), 0.0, 1.0)
	var at := Vector2(lerpf(x0, x1, share), lane - 9.0)
	# where the thumb goes: a soft glow, a ring of dashes turning slowly
	draw_circle(at + Vector2(0, 3), 17.0, Color(land, 0.1 + 0.06 * breathe))
	for d in 10:
		var a0: float = t * 0.8 + d * TAU / 10.0
		draw_arc(at + Vector2(0, 3), 19.0, a0, a0 + TAU / 20.0, 4, Color(GOLD, 0.3 + 0.3 * breathe), 1.5)
	var body := Rect2(at.x - 15.0, at.y - 4.5, 30.0, 9.0)
	draw_rect(body.grow(2.0), Color(GOLD, 0.15))
	draw_rect(body, Color(0.2, 0.18, 0.25))
	draw_circle(Vector2(body.position.x, at.y), 4.5, Color(0.2, 0.18, 0.25))
	draw_circle(Vector2(body.end.x, at.y), 4.5, Color(0.2, 0.18, 0.25))
	draw_rect(Rect2(body.position, Vector2(body.size.x, 3.5)), GOLD)
	draw_line(Vector2(body.position.x + 6, at.y + 1.5), Vector2(body.end.x - 6, at.y + 1.5), Color(0.55, 0.95, 1.0, 0.8), 1.0)
	draw_rect(Rect2(body.position, Vector2(body.size.x, 1.0)), Color(1, 0.95, 0.8))
	for x in [body.position.x, body.end.x]:
		draw_circle(Vector2(x, at.y), 2.4, GOLD)
		draw_circle(Vector2(x, at.y), 1.1, Color(1, 1, 1))
	if state == State.AIM:
		draw_circle(at + Vector2(0, -9), 5.0, Color(0.75, 0.95, 1.0, 0.25))
		draw_circle(at + Vector2(0, -9), 3.0, Color(0.92, 0.98, 1.0))
	# what a tap does
	_text(Vector2(79, 674), "TAP THE FIELD", 11, GOLD, null, true)
	_text(Vector2(79, 690), "launch · fire · let go", 11, Color(INK, 0.6), _font, true)


func _draw_right_panel() -> void:
	var r := Rect2(1132, 86, 138, 620)
	var kingdom: Dictionary = Maps.kingdom_of(map_index)
	var colour: Color = COLOURS.get(kingdom.get("land", "light"), GOLD)
	_panel(r, colour)
	if boss != null:
		_text(Vector2(1201, 112), "THE RULER" if boss.crowned else "THE GUARDIAN", 14, GOLD, null, true)
	else:
		_text(Vector2(1201, 112), "THE WALLS", 14, GOLD, null, true)
	_divider(122, 1144, 1258, GOLD)
	var done: float
	if boss != null:
		done = 1.0 - float(boss.hp) / float(boss.most)
	else:
		done = float(broken) / float(maxi(1, breakable))
	# THE RING: the walls broken in the kingdom's colour, a boss's health
	# taken in red; ticks every tenth, a glow, and a bright head
	var ring: Color = Color(1.0, 0.38, 0.32) if boss != null else colour.lightened(0.15)
	var c := Vector2(1201, 186)
	draw_circle(c, 54.0, Color(ring, 0.05))
	draw_arc(c, 44.0, 0, TAU, 64, Color(0, 0, 0, 0.5), 11.0)
	for k in 20:
		var a: float = -PI / 2.0 + TAU * k / 20.0
		draw_line(c + Vector2.from_angle(a) * 33.0, c + Vector2.from_angle(a) * (36.0 if k % 2 else 38.0), Color(1, 1, 1, 0.18), 1.0)
	if done > 0.0:
		var end_a: float = -PI / 2.0 + TAU * done
		draw_arc(c, 44.0, -PI / 2.0, end_a, 64, Color(ring, 0.22), 17.0)
		draw_arc(c, 44.0, -PI / 2.0, end_a, 64, ring, 9.0)
		draw_circle(c + Vector2.from_angle(end_a) * 44.0, 5.5, ring.lightened(0.45))
	_text(c + Vector2(0, 9), "%d%%" % int(round(done * 100.0)), 24, INK, null, true)
	if boss != null:
		_text(Vector2(1201, 254), str(boss.title), 12, ring.lightened(0.35), null, true)
		_text(Vector2(1201, 270), "%d to go" % int(boss.hp), 11, Color(INK, 0.55), _font, true)
	else:
		_text(Vector2(1201, 258), "%d left" % maxi(0, breakable - broken), 12, Color(INK, 0.6), _font, true)
	# THIS STRETCH: the five maps the one now is among, its boss last.
	var at: int = Maps.in_kingdom(map_index)
	var first: int = at - at % Maps.BOSS_EVERY
	_text(Vector2(1201, 302), "MAPS %d - %d" % [first + 1, first + Maps.BOSS_EVERY], 13, GOLD, null, true)
	_divider(312, 1144, 1258, GOLD)
	# ALL FIVE ALWAYS (the owner: "adding the 5th node ... will complete the
	# tier ladder"): a map not built yet is a dim slot under its number, the
	# stretch's boss under its name. The path between maps cleared is lit.
	var mine: Array = Maps.maps_of(str(kingdom.get("id", "light")))
	for j in Maps.BOSS_EVERY:
		var slot: int = first + j
		var made: bool = slot < mine.size()
		var idx: int = int(mine[slot]) if made else -1
		var p := Vector2(1162, 342 + j * 52)
		var boss_slot: bool = j == Maps.BOSS_EVERY - 1
		if j < Maps.BOSS_EVERY - 1:
			var lit_path: bool = made and idx < map_index
			if lit_path:
				draw_line(p + Vector2(0, 12), p + Vector2(0, 40), Color(GOLD, 0.25), 6.0)
			draw_line(p + Vector2(0, 12), p + Vector2(0, 40), Color(GOLD, 0.85) if lit_path else Color(1, 1, 1, 0.16), 2.0)
		var here: bool = made and idx == map_index
		var done_map: bool = made and (idx < map_index or (here and state == State.CLEARED))
		var col: Color = GOLD if done_map else (COLOURS["fire"] if here else Color(1, 1, 1, 0.25 if made else 0.14))
		var radius: float = 12.0 if boss_slot else 10.0
		if here:
			draw_circle(p, radius + 6.0 + 2.5 * sin(t * 4.0), Color(col, 0.18))
			draw_arc(p, radius + 4.0 + 2.5 * sin(t * 4.0), 0, TAU, 24, Color(col, 0.5), 1.0)
		draw_circle(p, radius, col.darkened(0.35) if not here else col)
		draw_arc(p, radius, 0, TAU, 20, col, 1.5)
		if boss_slot:
			var top: Vector2 = p + Vector2(0, -radius - 1.0)
			if made and Maps.MAPS[idx].get("boss") is Dictionary and bool(Maps.MAPS[idx]["boss"].get("crown", false)):
				draw_colored_polygon(PackedVector2Array([top + Vector2(-7, 2), top + Vector2(-7, -5), top + Vector2(-3, -1),
					top + Vector2(0, -7), top + Vector2(3, -1), top + Vector2(7, -5), top + Vector2(7, 2)]), col)
			else:
				for side in [-1.0, 1.0]:
					draw_colored_polygon(PackedVector2Array([top + Vector2(side * 3, 2), top + Vector2(side * 8, -5), top + Vector2(side * 8, 3)]), col)
		if done_map:
			draw_line(p + Vector2(-4, 0), p + Vector2(-1, 4), Color(1, 1, 1), 2.0)
			draw_line(p + Vector2(-1, 4), p + Vector2(5, -4), Color(1, 1, 1), 2.0)
		var slot_name: String
		if made:
			slot_name = Maps.short_name(idx)
		elif boss_slot:
			@warning_ignore("integer_division")
			slot_name = str(Maps.BOSS_SLOTS[mini(first / Maps.BOSS_EVERY, Maps.BOSS_SLOTS.size() - 1)])
		else:
			slot_name = "Map %d" % (slot + 1)
		_text(p + Vector2(16, 5), slot_name, 12, INK if made and idx <= map_index else Color(INK, 0.4 if made else 0.28),
			_font if not here else null)
	# the run's best combo, in a box of its own
	var box := Rect2(1146, 628, 110, 64)
	draw_rect(box, Color(0, 0, 0, 0.3))
	draw_rect(box, Color(GOLD, 0.25), false, 1.0)
	_text(Vector2(1201, 650), "BEST COMBO", 10, Color(INK, 0.55), _font, true)
	_text(Vector2(1201, 678), "%d" % best_combo, 22, GOLD.lerp(Color.WHITE, 0.3) if best_combo > 0 else Color(INK, 0.4), null, true)


# ---------------------------------------------------------------- the kingdoms --

func kingdom_spot(i: int) -> Vector2:
	"""Where kingdom `i` sits on the kingdom map: an arc, gentlest at the left."""
	var u: float = float(i) / 6.0
	return Vector2(170.0 + u * 940.0, 270.0 - sin(u * PI) * 90.0)


func map_spot(index: int) -> Vector2:
	"""Where a made map's node sits in the kingdom panel (MAP_PANEL): its
	kingdom's maps in rows of five, each row a stretch ending in its boss."""
	return slot_spot(Maps.in_kingdom(index))


func slot_spot(slot: int) -> Vector2:
	"""Where the `slot`th map of a kingdom (from 0) sits, made or not."""
	@warning_ignore("integer_division")
	var stretch: int = slot / Maps.BOSS_EVERY
	return MAP_PANEL.position + Vector2(100.0 + (slot % Maps.BOSS_EVERY) * NODE_GAP.x, 71.0 + stretch * NODE_GAP.y)


func kingdom_at(point: Vector2) -> int:
	"""The made kingdom whose crest is at `point` (the kingdom map), or -1."""
	for i in Maps.KINGDOMS.size():
		if bool(Maps.KINGDOMS[i]["made"]) and kingdom_spot(i).distance_to(point) <= 46.0:
			return i
	return -1


func open_map_in(kingdom: int) -> int:
	"""The map to pick in a kingdom: the next to clear there, or its last once
	all are cleared; -1 while none of it is open."""
	if kingdom < 0 or kingdom >= Maps.KINGDOMS.size():
		return -1
	var mine: Array = Maps.maps_of(str(Maps.KINGDOMS[kingdom]["id"]))
	if mine.is_empty() or not can_start_at(int(mine[0])):
		return -1
	return mini(furthest, int(mine[-1]))


func kingdom_index(index: int) -> int:
	"""Which kingdom (in KINGDOMS) map `index` is in."""
	var id: String = str(Maps.kingdom_of(index).get("id", ""))
	for i in Maps.KINGDOMS.size():
		if Maps.KINGDOMS[i]["id"] == id:
			return i
	return 0


func pick_at(point: Vector2) -> int:
	"""The made map whose node is at `point` (the kingdom map), or -1: only
	the maps of the kingdom on show."""
	var shown: String = str(Maps.kingdom_of(selected).get("id", ""))
	for i in Maps.made_count():
		if str(Maps.MAPS[i]["kingdom"]) == shown and Rect2(map_spot(i) - TILE / 2.0, TILE).grow(4.0).has_point(point):
			return i
	return -1


func _draw_kingdoms() -> void:
	_text(Vector2(640, 70), "CROWNFALL", 40, GOLD, null, true)
	_text(Vector2(640, 102), "Seven kingdoms of plague-stone. Seven crowns. Break the walls, heal the land.", 16, Color(INK, 0.75), _font, true)
	# the road between them
	var road := PackedVector2Array()
	for i in 7:
		road.append(kingdom_spot(i))
	draw_polyline(road, Color(GOLD, 0.25), 3.0, true)
	var shown: Dictionary = Maps.kingdom_of(selected)
	for i in Maps.KINGDOMS.size():
		var k: Dictionary = Maps.KINGDOMS[i]
		var p: Vector2 = kingdom_spot(i)
		var c: Color = COLOURS[k["land"]]
		var made: bool = bool(k["made"])
		var theirs: Array = Maps.maps_of(k["id"])
		var cleared_all: bool = made and not theirs.is_empty() and furthest > int(theirs[-1])
		var locked: bool = kingdom_locked(i)
		var lit: bool = made and not locked
		var here: bool = str(k["id"]) == str(shown.get("id", ""))
		# the one shown is lifted: a wider glow and a ring that breathes
		if here:
			draw_circle(p, 56.0, Color(c, 0.16))
			draw_arc(p, 42.0 + 1.5 * sin(t * 3.0), 0, TAU, 48, Color(GOLD, 0.85), 2.5)
		# EVERY CREST GLOWS ITS LAND (the owner: "giving Wind (teal), Water
		# (blue), Ice (cyan), and Earth (amber/green) those same subtle inner
		# glows"): a kingdom still to come, or locked, is a dim crest with its
		# colour inside; one you can play is the bright one.
		draw_circle(p, 46.0, Color(c, 0.10 if lit else 0.06))
		if lit:
			# darker behind a ruler, so a light one stands out from a gold crest
			draw_circle(p, 34.0, c.darkened(0.78 if ruled_here(i) else 0.55))
		else:
			draw_circle(p, 34.0, Color(0.1, 0.1, 0.12).lerp(c, 0.16))
			draw_circle(p, 24.0, Color(c, 0.10))
			draw_circle(p, 14.0, Color(c, 0.08))
		draw_arc(p, 34.0, 0, TAU, 40, Color(c, 0.9 if lit else 0.45), 2.5)
		# a castle on each
		var base: Vector2 = p + Vector2(0, 14)
		var castle := PackedVector2Array([base + Vector2(-20, 0), base + Vector2(-20, -22), base + Vector2(-14, -22), base + Vector2(-14, -16),
			base + Vector2(-6, -16), base + Vector2(-6, -30), base + Vector2(6, -30), base + Vector2(6, -16), base + Vector2(14, -16),
			base + Vector2(14, -22), base + Vector2(20, -22), base + Vector2(20, 0)])
		if not ruled_here(i):
			draw_colored_polygon(castle, Color(c, 0.85) if lit else Color(0.3, 0.3, 0.33).lerp(c, 0.22))
			if locked:
				_padlock(self, p + Vector2(0, 6))
		# the crown over it, gold while its ruler wears it
		var top: Vector2 = p + Vector2(0, -48)
		var crown := PackedVector2Array([top + Vector2(-12, 5), top + Vector2(-12, -5), top + Vector2(-6, 0), top + Vector2(0, -8),
			top + Vector2(6, 0), top + Vector2(12, -5), top + Vector2(12, 5)])
		draw_colored_polygon(crown, Color(0.35, 0.35, 0.37) if cleared_all else GOLD)
		_text(p + Vector2(0, 62), str(k["name"]).replace("The Kingdom of ", ""), 18, INK if lit else Color(INK, 0.45), null, true)
		if not made:
			_text(p + Vector2(0, 80), "coming", 13, Color(INK, 0.35), _font, true)
		elif cleared_all:
			_text(p + Vector2(0, 80), "crown taken", 13, Color(0.6, 0.95, 0.55), _font, true)
		elif locked:
			_text(p + Vector2(0, 80), "locked", 13, Color(INK, 0.4), _font, true)
		else:
			_text(p + Vector2(0, 80), "%d / %d" % [kingdom_cleared(i), Maps.MAPS_A_KINGDOM], 13, Color(GOLD, 0.9), _font, true)
	# THE PICKED MAP'S KINGDOM: its maps in five stretches of five, every
	# fifth a boss (horns over it; the citadel's a crown). A map not made yet
	# is a dim slot.
	var kingdom: Dictionary = shown
	var colour: Color = COLOURS.get(kingdom.get("land", "light"), GOLD)
	_panel(MAP_PANEL)
	_text(Vector2(MAP_PANEL.get_center().x, MAP_PANEL.position.y + 28), str(kingdom.get("name", "")).to_upper(), 16, GOLD, null, true)
	draw_line(MAP_PANEL.position + Vector2(20, 38), Vector2(MAP_PANEL.end.x - 20, MAP_PANEL.position.y + 38), Color(GOLD, 0.3), 1.0)
	var mine: Array = Maps.maps_of(str(kingdom.get("id", "")))
	var each: Array = pays.get("maps", []) if pays.get("maps") is Array else []
	for stretch in Maps.STRETCHES:
		var left: Vector2 = slot_spot(stretch * Maps.BOSS_EVERY)
		draw_line(left, slot_spot(stretch * Maps.BOSS_EVERY + Maps.BOSS_EVERY - 1), Color(GOLD, 0.18), 2.0)
	for slot in Maps.MAPS_A_KINGDOM:
		var p: Vector2 = slot_spot(slot)
		var made: bool = slot < mine.size()
		var i: int = int(mine[slot]) if made else -1
		var big: bool = (slot + 1) % Maps.BOSS_EVERY == 0
		var tile := Rect2(p - TILE / 2.0, TILE)
		if not made:
			draw_rect(tile, Color(0.1, 0.1, 0.12).lerp(colour, 0.06))
			draw_rect(tile, Color(colour, 0.18), false, 1.2)
			_text(p + Vector2(0, 5), str(slot + 1), 13, Color(INK, 0.22), _font, true)
			continue
		var open: bool = can_start_at(i)
		var done: bool = i < furthest
		var col: Color = GOLD if done else (colour if open else Color(1, 1, 1, 0.25))
		if i == selected:
			draw_rect(tile.grow(5.0 + 1.5 * sin(t * 4.0)), Color(col, 0.22))
		if big:
			var crown: bool = Maps.MAPS[i].get("boss") is Dictionary and bool(Maps.MAPS[i]["boss"].get("crown", false))
			var top: Vector2 = Vector2(p.x, tile.position.y - 1.0)
			if crown:
				draw_colored_polygon(PackedVector2Array([top + Vector2(-9, 3), top + Vector2(-9, -4), top + Vector2(-4, 0),
					top + Vector2(0, -6), top + Vector2(4, 0), top + Vector2(9, -4), top + Vector2(9, 3)]), col)
			else:
				for side in [-1.0, 1.0]:
					draw_colored_polygon(PackedVector2Array([top + Vector2(side * 14, 2), top + Vector2(side * 21, -8),
						top + Vector2(side * 20, 3)]), col)
			_text(Vector2(tile.end.x + 7.0, p.y + 5.0), "CROWN" if crown else "BOSS", 11, Color(col, 0.75), _font)
		# the map itself, dimmed until it can be played
		draw_rect(tile, Color(0.04, 0.04, 0.06))
		var pic: ImageTexture = map_picture(i)
		var fit: float = minf((TILE.x - 4.0) / pic.get_width(), (TILE.y - 4.0) / pic.get_height())
		var size: Vector2 = Vector2(pic.get_width(), pic.get_height()) * fit
		draw_texture_rect(pic, Rect2(p - size / 2.0, size), false, Color(1, 1, 1) if open else Color(0.5, 0.5, 0.55, 0.55))
		if not open:
			draw_rect(tile, Color(0.05, 0.05, 0.08, 0.35))
		draw_rect(tile, col, false, 2.0 if open else 1.2)
		# the next map to clear: a frame that pulses, and NEXT on its foot
		if i == furthest:
			draw_rect(tile.grow(3.0 + 1.5 * sin(t * 5.0)), Color(GOLD, 0.9), false, 2.5)
			var tag_w: float = _bold.get_string_size("NEXT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 10.0
			draw_rect(Rect2(p.x - tag_w / 2.0, tile.end.y - 7.0, tag_w, 15.0), Color(GOLD, 0.95))
			_text(Vector2(p.x, tile.end.y + 5.0), "NEXT", 11, Color(0.12, 0.09, 0.05), null, true, 1.0, 0)
		# its number, or a tick once cleared, in the top left corner
		var badge: Vector2 = tile.position + Vector2(2, 2)
		draw_circle(badge, 9.0, GOLD if done else Color(0.1, 0.1, 0.13))
		draw_arc(badge, 9.0, 0, TAU, 20, col, 1.4)
		if done:
			draw_line(badge + Vector2(-4, 0), badge + Vector2(-1, 4), Color(0.12, 0.09, 0.05), 2.0)
			draw_line(badge + Vector2(-1, 4), badge + Vector2(5, -4), Color(0.12, 0.09, 0.05), 2.0)
		else:
			_text(badge + Vector2(0, 4), str(slot + 1), 11, INK if open else Color(INK, 0.5), null, true, 1.0, 3)
	_draw_map_card(kingdom, each)
	if map_hint != "":
		var pick: Dictionary = Maps.MAPS[selected]
		var hint: String = map_hint % str(pick["name"]) if map_hint.contains("%s") else map_hint
		_text(Vector2(640, 688), hint, 14, Color(INK, 0.45 + 0.15 * sin(t * 2.5)), _font, true)


func map_picture(index: int) -> ImageTexture:
	"""Map `index` as a picture, a pixel a brick (kept once drawn)."""
	if _pictures.has(index):
		return _pictures[index]
	var rows: Array = Maps.MAPS[index]["rows"]
	var wide: int = 1
	for line in rows:
		wide = maxi(wide, str(line).length())
	var img := Image.create(wide, maxi(1, rows.size()), false, Image.FORMAT_RGBA8)
	var hall_tint: Color = Color(COLOURS.get(str(Maps.kingdom_of(index).get("land", "light")), GOLD), 0.22)
	for row in rows.size():
		var line: String = rows[row]
		for c in line.length():
			var letter: String = line[c]
			var paint := Color(0, 0, 0, 0)
			if letter == "R":
				paint = hall_tint
			elif LAND_OF.has(letter):
				paint = COLOURS[LAND_OF[letter]]
			elif MIXED.has(letter):
				paint = _colour_of({"kind": "mix", "land": "", "mix": MIXED[letter]})
			elif THUMB_KIND.has(letter):
				paint = _colour_of({"kind": THUMB_KIND[letter][0], "land": THUMB_KIND[letter][1]})
			elif letter != ".":
				paint = Color(0.6, 0.6, 0.6)
			img.set_pixel(c, row, paint)
	var tex := ImageTexture.create_from_image(img)
	_pictures[index] = tex
	return tex


func ruled_here(i: int) -> bool:
	"""Whether kingdom `i`'s crest shows its ruler (else its castle)."""
	return i < _crest_sprites.size() and _crest_sprites[i] != null


func ruler_of(i: int) -> Dictionary:
	"""Kingdom `i`'s crowned ruler: its citadel boss's line, {} if none."""
	for index in Maps.maps_of(str(Maps.KINGDOMS[i]["id"])):
		var info: Variant = Maps.MAPS[index].get("boss")
		if info is Dictionary and bool(info.get("crown", false)):
			return info
	return {}


func _dress_crests() -> void:
	"""The rulers over the crests: one more looked up each frame, and each
	shaded for its kingdom - itself, a shadow while locked, grey once taken."""
	if crest_art == null:
		crest_art = Node2D.new()
		crest_art.name = "crest_art"
		add_child(crest_art)
		crest_top = Node2D.new()
		crest_top.name = "crest_top"
		add_child(crest_top)
		crest_top.draw.connect(_draw_crest_locks)
		_crest_sprites.resize(Maps.KINGDOMS.size())
	crest_art.visible = true
	crest_top.visible = true
	if _crests_tried < Maps.KINGDOMS.size():
		var i: int = _crests_tried
		_crests_tried += 1
		var info: Dictionary = ruler_of(i)
		var pic: Dictionary = EnemyPortraits.picture(str(info.get("enemy", ""))) if not info.is_empty() else {}
		var tex: Texture2D = pic.get("texture") as Texture2D
		if tex != null:
			var art := Sprite2D.new()
			art.name = "ruler_%d" % i
			art.texture = tex
			art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			art.material = pic.get("material") as Material
			if str(info.get("tint", "")) == "fire":
				art.material = BaseEnemy.element_material(EnemyPortraits.data_for(str(info["enemy"])), Element.Type.FIRE)
			var most: float = maxf(tex.get_width(), tex.get_height())
			var k: float = CREST_FIT / most
			if k >= 1.0:
				k = floorf(k)
			art.scale = Vector2(k, k)
			art.position = kingdom_spot(i) + Vector2(0, 2)
			art.set_meta("body", pic.get("modulate", Color.WHITE))
			art.set_meta("recolour", art.material)
			crest_art.add_child(art)
			_crest_sprites[i] = art
	for i in _crest_sprites.size():
		var art: Sprite2D = _crest_sprites[i]
		if art == null:
			continue
		var theirs: Array = Maps.maps_of(str(Maps.KINGDOMS[i]["id"]))
		var taken: bool = not theirs.is_empty() and furthest > int(theirs[-1])
		var body: Color = art.get_meta("body", Color.WHITE)
		# a recolour's shader paints over a tint, so a shadow goes without it;
		# a ruler whose crown is taken keeps its colours (its crown above the
		# crest goes grey, and "crown taken" under it)
		var locked: bool = kingdom_locked(i)
		art.material = null if locked else art.get_meta("recolour") as Material
		art.modulate = Color(0.0, 0.0, 0.02, 0.9) if locked else body
	crest_top.queue_redraw()


func _draw_crest_locks() -> void:
	for i in _crest_sprites.size():
		if _crest_sprites[i] != null and kingdom_locked(i):
			_padlock(crest_top, kingdom_spot(i) + Vector2(0, 14))


func _padlock(on: CanvasItem, at: Vector2) -> void:
	"""A padlock: its shackle, its body, its keyhole."""
	on.draw_arc(at + Vector2(0, -8), 6.0, PI, TAU, 12, Color(0.85, 0.85, 0.9), 2.5)
	on.draw_rect(Rect2(at + Vector2(-9, -8), Vector2(18, 14)), Color(0.75, 0.75, 0.8))
	on.draw_circle(at + Vector2(0, -2), 2.0, Color(0.2, 0.2, 0.24))


func kingdom_locked(i: int) -> bool:
	"""A made kingdom not reached yet: its first map is past the next to clear."""
	var theirs: Array = Maps.maps_of(Maps.KINGDOMS[i]["id"])
	return bool(Maps.KINGDOMS[i]["made"]) and not theirs.is_empty() and int(theirs[0]) > furthest


func kingdom_cleared(i: int) -> int:
	"""How many of a kingdom's maps are cleared."""
	return Maps.maps_of(Maps.KINGDOMS[i]["id"]).filter(func(m: int) -> bool: return m < furthest).size()


func _draw_map_card(kingdom: Dictionary, each: Array) -> void:
	"""The picked map, on a card of its own beside the panel: which it is,
	its name, its gold, what it holds, the kingdom's trick; the screen's
	Start sits at its foot (crownfallscreen.gd START_BOX)."""
	var pick: Dictionary = Maps.MAPS[selected]
	var colour: Color = COLOURS.get(kingdom.get("land", "light"), GOLD)
	_panel(MAP_CARD)
	var x: float = MAP_CARD.position.x + 20.0
	var width: float = MAP_CARD.size.x - 40.0
	var y: float = MAP_CARD.position.y + 30.0
	var boss_map: bool = (Maps.in_kingdom(selected) + 1) % Maps.BOSS_EVERY == 0
	_text(Vector2(x, y), "MAP %d OF %d%s" % [Maps.in_kingdom(selected) + 1, Maps.MAPS_A_KINGDOM, "   ·   BOSS" if boss_map else ""],
		13, Color(INK, 0.6), _font)
	y += 30.0
	_text(Vector2(x, y), str(pick["name"]).to_upper(), 22, GOLD)
	y += 26.0
	if selected < each.size():
		_text(Vector2(x, y), "Pays %s gold" % thousands(int(each[selected])), 15, INK, _font)
		y += 12.0
	y += 14.0
	y += _wrapped(Vector2(x, y), str(pick["line"]), width, 14, Color(INK, 0.75), 3) + 8.0
	_wrapped(Vector2(x, y), str(kingdom.get("trick", "")), width, 14, colour.lightened(0.35), 2)
	if not can_start_at(selected):
		_text(Vector2(MAP_CARD.get_center().x, MAP_CARD.end.y - 76.0), "Clear map %d first" % (Maps.in_kingdom(furthest) + 1)
			if furthest < Maps.made_count() and str(Maps.kingdom_of(furthest).get("id", "")) == str(kingdom.get("id", ""))
			else "Locked until you get here", 13, Color(INK, 0.5), _font, true)


func _wrapped(at: Vector2, s: String, width: float, size: int, c: Color, lines: int) -> float:
	"""Words wrapped to `width`, at most `lines` lines, from `at` (the first
	line's baseline); how far down they went."""
	if s == "":
		return 0.0
	_cv.draw_multiline_string_outline(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, lines, 3, Color(0, 0, 0, 0.6))
	_cv.draw_multiline_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, lines, c)
	var tall: float = _font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, size, lines).y
	return tall
