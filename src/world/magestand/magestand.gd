# magestand.gd - THE MAGE'S STAND (0.107.0, step 2 of the commit folder's
# MAGES_STAND_PLAN.txt; the owner's alone while it is built).
#
# The owner: "mage would use mythic weapon stand on a wall and protect the
# portal from enemies going in", "we can use the door as the gate enemies
# break it then run through to the portal enemies should flood in in waves
# progressivly getting harder", "make field of view longer for this one so
# players can see further out", "there will be no limit on meteors the goal
# will be to spam them because hordes will come strong and move fast", "the
# door need to be slightly transparent so we can see enemies behind it".
#
# THE PLACE (fixed, VIEW across - half as far again each way as the Healer's
# Run): outside, most of it, where the waves come from; the wall low across
# it (the crypt's brick face, its cap stones on top for her to walk, the
# crypt door as the gate between two pillars, drawn see-through - DOOR_SEE);
# inside, a strip at the bottom, the portal. Monsters and the wall share one
# y-sorted layer (`world`), so a monster at the gate is drawn behind it.
#
# HER: the mage with the Meteorite, walking the wall's top (`steer`, the move
# keys) and raining meteors where you aim (`aim` and `casting`, set by the
# screen from the mouse) - no count, the cast gap the only limit. A meteor
# falls FALL_SECONDS with its shadow and ring, blasts BLAST_REACH (one in
# five critical), and leaves a crater burning BURN_SECONDS.
#
# THE GATE AND THE PORTAL: monsters queue at the gate and hit it (at most
# GATE_HITTERS at once); at nought it breaks and they run through to the
# portal, each draining it (`portal`). Nought there: the run is over. The gate
# is NOT mended after a wave (the owner, 0.109.0: "gate should not auto
# recharge every round"): only the Gate patch card mends it - a broken one
# rebuilt, and while it is broken the patch is always one of the cards.
# Struck, it shakes and flashes; under GATE_LOW its bar pulses red.
#
# WAVES: more, faster and tougher each time (wave_count(), wave_speed(),
# wave_health()), the land changing every LAND_WAVES; no last one - the score
# is the waves held.
#
# THE PICK (0.109.0; the owner, of the mockup: "looks good", then "every 3
# levels passed should pull up upgrade menu"): after every PICK_EVERY-th
# wave held the next one waits (State.PICK) while she picks one of
# PICK_COUNT upgrades, drawn from UPGRADES, for the rest of the run - faster
# casting, a bigger or stronger blast, a longer burn, more criticals, a
# double cast, the pull, or a gate patch. Each but the patch stacks to
# UPGRADE_MOST. The clock stops while she picks. They replace the plan's
# pickups dropped by kills.
#
# EVOLUTIONS (the owner chose them from a list: "these are good ideas"): two
# upgrades both at UPGRADE_MOST bring a card of their own, always offered
# until taken - EVOLUTIONS. A REROLL (`rerolls`, REROLLS_FIRST a run) draws
# three new cards. CALLING EARLY: once a wave has all come in, the next can
# be called while its last are still about (call_early()); each one called
# brings a reroll, and a pick still comes for every PICK_EVERY-th wave held
# among them (`picks_left`).
# Before each group comes in, an arrow at the top shows where (`next_x`).
#
# THE WALL IN STRETCHES (0.110.0; the owner: "enemies just run in a line
# when door is broken focus fire at gate easy could survive days", and of
# the wall breaking anywhere and bombers: "sounds great"): either side of the
# gate the wall is three stretches (STRETCH_EDGES), each with WALL_MOST of
# its own. A monster goes for the gate (GATE_SHARE of them) or the stretch
# nearest where it came in (send_to()); a stretch at nought is a BREACH - its
# face down, rubble in the gap, the caps left over it for her to walk - and
# what was hitting it runs through for the portal. The Repair card mends the
# weakest of the gate and the stretches, rebuilding a breach. BOMBERS (from
# wave BOMBERS_FROM, the land's slime with a lit fuse) make for a stretch and
# blow BOMB_HIT off it; one slain on the way blows up where it stands,
# hurting its neighbours. And a monster burns from one crater at a time.
#
# THE STAR (0.111.0, section 13 of the plan; the owner: "we need 1 giant
# meteor to wipe the whole field but i need to think carefully about how it
# can be used because with 4 people might be too op", then "lets build it"):
# from wave STAR_FROM a wave may drop one (STAR_CHANCE, and sure once
# STAR_SURE waves have passed without) STAR_DROP_AFTER into it. It lies
# glowing on the field STAR_LIFE; meteors landed on it claim it (claim_hits():
# 3 alone, 8 for four). Held - one at a time, for the party - it is called
# down with call_star() (Q, or the screen's button): its shadow spreads over
# the field STAR_FALL, then it lands - every monster there at the call is
# hit by star_hit() (the ordinary slain; elites lose half, keepers a fifth,
# when step 3 brings them). What walks in after the call lives.
#
# No god mode here (the owner: "we also do not need godmode on this mode").
#
# Step 3 brings elites, keepers, shooters and lives; step 4 the
# leaderboards and the Upgrades tab; step 5 the party.
#
# No class_name: preloaded by magestandscreen.gd and the suite.
extends Node2D

signal finished

enum State { READY, WAVE, BETWEEN, LOST, PICK }

const RunScript := preload("res://src/world/healerrun/healerrun.gd")

const VIEW := Vector2(960.0, 540.0)
const HALF := Vector2(480.0, 270.0)
const PATH_HALF := 330.0
# THE WALL: its foot, the gate's gap either side of the middle, and where she
# stands (her picture's middle) on its caps.
const FOOT := 178.0
const GATE_HALF := 39.0
const WALK_Y := FOOT - 54.0
const WALK_SPEED := 130.0
# As far either way as she walks: the wall's ends, short of the side walls.
const WALK_HALF := PATH_HALF - 24.0
# HER SIDE OF THE GATE (0.110.2). The owner: "i need to make sure mage cannot
# walk across the bridge 2 people on left 2 on the right is the idea assuming
# 4 person party". She walked the whole top, over the gate's gap where there
# are no caps. Now she keeps to `her_side` - from the wall's end to the
# pillar by the gate (SIDE_INNER from the middle) - and never crosses it.
# Alone she is on the left; a party's seats take sides in turn (side_for()),
# so two make one each side and four make two.
const SIDE_INNER := GATE_HALF + 9.0
const WALL_PIECES := {101: "res://scene/crypt/wallrun4.tscn", 51: "res://scene/crypt/wallrun2.tscn",
	26: "res://scene/crypt/wallrun1.tscn", 17: "res://scene/crypt/pillar.tscn"}
const WALLS_ART := "res://art/floordecoration/floorwalls.png"
const CAP_REGION := Rect2(326, 118, 9, 58)
const DOOR_ART := "res://art/floordecoration/cryptdoor.png"
# The door, see-through enough to show what is behind it.
const DOOR_SEE := 0.62
const PORTAL_AT := Vector2(0.0, 232.0)
const PORTAL_REACH := 20.0
const PORTAL_MOST := 100
const PORTAL_FRAMES := "res://art/teleport/teleportframes.tres"
const MAGE_SCENE := "res://scene/characters/mage.tscn"
const METEOR_TEXTURE := "res://art/maincharacter/meteor.png"
const FLOOR_SET := "res://scene/world/underground.tres"
const TILE := 16
# THE METEORS: no count - the gap between casts is the limit.
const CAST_GAP := 0.33
const FALL_SECONDS := 0.45
const SKY := Vector2(70.0, -150.0)
const BLAST_REACH := 36.0
const BLAST_DAMAGE := 10.0
const CRIT_CHANCE := 0.2
const CRIT_MULT := 2.0
const BURN_SECONDS := 2.5
const BURN_REACH := 30.0
const BURN_DPS := 4.0
const FIRE := Color(1.0, 0.55, 0.15)
# THE GATE.
const DOOR_MOST := 400.0
const DOOR_HIT := 4.0
const GATE_HITTERS := 10
# Under this share of its most, the gate's bar pulses red.
const GATE_LOW := 0.25
# THE WALL IN STRETCHES: their edges from the gate out (each side), what
# each holds, and how many hit one at once.
const STRETCH_EDGES := [GATE_HALF, 140.0, 241.0, PATH_HALF + 4.5]
const WALL_MOST := 300.0
const WALL_HITTERS := 8
const GATE_SHARE := 0.35
# BOMBERS.
const BOMBERS_FROM := 4
const BOMBER_CHANCE := 0.05
const BOMBER_MORE := 0.01
const BOMBER_MOST := 0.12
const BOMB_HIT := 120.0
const BOMB_REACH := 44.0
const BOMB_DAMAGE := 30.0
const RUBBLE_SCENE := "res://scene/crypt/rubble4.tscn"
# THE STAR (0.111.0): see the header. It lies where a wave drops it; called,
# it lands on STAR_CENTRE, its shadow STAR_SHADOW across (squashed by half,
# the field seen from above at a slant).
const STAR_FROM := 4
const STAR_CHANCE := 0.25
const STAR_SURE := 4
const STAR_DROP_AFTER := 5.0
const STAR_DROP_SECONDS := 0.8
const STAR_LIFE := 10.0
const STAR_RADIUS := 14.0
const STAR_HITS_ALONE := 3
const STAR_HITS_FOUR := 8
const STAR_FALL := 2.0
const STAR_AFTERGLOW := 1.4
const STAR_CENTRE := Vector2(0.0, -70.0)
const STAR_SHADOW := 320.0
const STAR_ELITE_SHARE := 0.5
const STAR_KEEPER_SHARE := 0.2
const STAR_GOLD := Color(1.0, 0.85, 0.4)
# THE WAVES.
const READY_SECONDS := 1.5
const BETWEEN_SECONDS := 3.0
const WAVE_FIRST := 24
const WAVE_MORE := 10
const GROUP_FIRST := 8
const GROUP_GAP := 1.2
const LAND_WAVES := 3
const MONSTERS_MOST := 400
const BANNER_SECONDS := 2.2
# THE PICK.
const PICK_COUNT := 3
const PICK_EVERY := 3
const UPGRADE_MOST := 5
const UPGRADE_ORDER := ["cast", "blast", "power", "burn", "crit", "double", "pull", "patch"]
const UPGRADES := {
	"cast": {"name": "Faster casting", "does": "Meteors 15% faster"},
	"blast": {"name": "Bigger blast", "does": "Blasts 20% wider"},
	"power": {"name": "Stronger blast", "does": "Blasts hit 25% harder"},
	"burn": {"name": "Longer burn", "does": "Craters burn 40% longer"},
	"crit": {"name": "Sharper aim", "does": "8% more criticals"},
	"double": {"name": "Double cast", "does": "15% chance of a second meteor"},
	"pull": {"name": "The pull", "does": "10% chance a blast drags a pack in"},
	"patch": {"name": "Repair", "does": "Mends the weakest wall 30%"},
	"firestorm": {"name": "Firestorm", "does": "Craters burn twice as wide and hot", "evolves": ["blast", "burn"]},
	"shower": {"name": "Meteor shower", "does": "Criticals split into three", "evolves": ["crit", "double"]},
	"comet": {"name": "Comet", "does": "Every 5th meteor is a comet", "evolves": ["cast", "power"]},
}
const EVOLUTIONS := ["firestorm", "shower", "comet"]
const FIRESTORM_MULT := 2.0
const SHOWER_PIECES := 3
const SHOWER_SPREAD := 46.0
const SHOWER_SHARE := 0.5
const COMET_EVERY := 5
const COMET_REACH := 2.0
const COMET_HIT := 3.0
const REROLLS_FIRST := 1
const CAST_STEP := 1.15
const BLAST_STEP := 0.2
const POWER_STEP := 0.25
const BURN_STEP := 0.4
const CRIT_STEP := 0.08
const DOUBLE_STEP := 0.15
const DOUBLE_SPREAD := 40.0
const PULL_STEP := 0.1
# The pull reaches this many blasts wide, and drags what it reaches this
# share of the way in.
const PULL_REACH := 2.5
const PULL_SHARE := 0.7
const PATCH_SHARE := 0.3
# After the pick, a moment before the next wave.
const AFTER_PICK_SECONDS := 1.5
const KINDS := {"sprite": {"health": 6.0, "speed": 48.0, "radius": 8.0, "drain": 1},
	"slime": {"health": 14.0, "speed": 32.0, "radius": 9.0, "drain": 2},
	"bomber": {"health": 10.0, "speed": 44.0, "radius": 9.0, "drain": 2}}
const MONSTER_Z := 0
const HER_Z := 6
# The ground's marks under the monsters, over the floor.
const MARKS_Z := -1
const SKY_Z := 30


class Monster extends Node2D:
	var kind: String = ""
	var health: float = 1.0
	var most: float = 1.0
	var speed: float = 30.0
	var radius: float = 8.0
	var drain: int = 1
	# Where at the gate it heads for: along it, and how far back it queues.
	var stop_x: float = 0.0
	var stop_y: float = 0.0
	var at_gate: bool = false
	# Past the gate, running for the portal.
	var through: bool = false
	var flash: float = 0.0
	var dying: float = -1.0
	var sprite: AnimatedSprite2D = null
	# Where it goes: -1 the gate, else a stretch of the wall.
	var target: int = -1
	var fuse: Node2D = null
	# "" an ordinary monster; "elite" or "keeper" (step 3) - the star hits
	# those for a share of their health (star_hit()).
	var rank: String = ""


# A bomber's lit fuse, drawn over it.
class Fuse extends Node2D:
	func _draw() -> void:
		draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 24, Color(1.0, 0.3, 0.15, 0.8), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_line(Vector2(0, -12), Vector2(-3, -20), Color(0.3, 0.22, 0.15), 2.0)
		draw_circle(Vector2(-3, -21), 7.0, Color(1.0, 0.45, 0.1, 0.35))
		draw_circle(Vector2(-3, -21), 3.5, Color(1.0, 0.85, 0.4))


# The wall's stretches: a bar on each one struck, a mark on each breach.
class WallBars extends Node2D:
	var run: Node2D = null

	func _draw() -> void:
		if run == null:
			return
		for one in run.get("stretches"):
			var mid: float = float(one["side"]) * (float(one["from"]) + float(one["to"])) / 2.0
			var share: float = float(one["health"]) / WALL_MOST
			if bool(one["broken"]) or share >= 1.0:
				continue
			var at := Vector2(mid - 24.0, FOOT - 14.0)
			draw_rect(Rect2(at, Vector2(48.0, 5.0)), Color(0.0, 0.0, 0.0, 0.6))
			var colour: Color = Color(1.0, 0.25, 0.15) if share < GATE_LOW else Color(0.9, 0.6, 0.3)
			draw_rect(Rect2(at + Vector2(1, 1), Vector2(46.0 * share, 3.0)), colour)

# The ground's marks and the sky's trails, drawn from the run's lists each
# frame: one node each, not one a meteor.
class Marks extends Node2D:
	var run: Node2D = null
	var sky: bool = false

	func _draw() -> void:
		if run == null:
			return
		if sky:
			for fall in run.get("falling"):
				var done: float = 1.0 - clampf(float(fall["left"]) / FALL_SECONDS, 0.0, 1.0)
				var at: Vector2 = fall["at"]
				var stone: Vector2 = (at + SKY).lerp(at, done * done)
				for k in 8:
					var t: float = float(k) / 8.0
					draw_circle(stone + (SKY.normalized() * 10.0 * k), 7.0 - k * 0.7,
						Color(1.0, 0.45 + t * 0.3, 0.1, (0.75 - t * 0.7)))
			if bool(run.call("arrow_showing")):
				var ax: float = float(run.get("next_x"))
				var bob: float = sin(float(run.get("run_seconds")) * 6.0) * 3.0
				var tip := Vector2(ax, -HALF.y + 88.0 + bob)
				for k in 2:
					var y: float = tip.y - 12.0 * k
					draw_colored_polygon(PackedVector2Array([Vector2(ax - 11.0, y - 10.0), Vector2(ax, y),
						Vector2(ax + 11.0, y - 10.0), Vector2(ax, y - 5.0)]), Color(1.0, 0.45, 0.25, 0.85 - 0.3 * k))
			_draw_star_sky()
			if bool(run.get("showing_aim")):
				var aim: Vector2 = run.get("aim")
				draw_arc(aim, 22.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.5, 0.9), 1.0)
				draw_line(aim + Vector2(-6, 0), aim + Vector2(6, 0), Color(1.0, 0.85, 0.5, 0.9), 1.0)
				draw_line(aim + Vector2(0, -6), aim + Vector2(0, 6), Color(1.0, 0.85, 0.5, 0.9), 1.0)
			return
		for crater in run.get("craters"):
			var at: Vector2 = crater["at"]
			var fade: float = clampf(float(crater["left"]) / BURN_SECONDS, 0.0, 1.0)
			draw_set_transform(at, 0.0, Vector2(1.0, 0.55))
			var burn_reach: float = float(run.call("burn_reach"))
			draw_circle(Vector2.ZERO, burn_reach, Color(1.0, 0.35, 0.05, 0.25 * fade))
			draw_circle(Vector2.ZERO, burn_reach * 0.6, Color(1.0, 0.55, 0.15, 0.4 * fade))
			draw_circle(Vector2.ZERO, 9.0, Color(0.2, 0.12, 0.1, 0.9 * fade))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var flick: float = float(crater["seed"]) + float(crater["left"]) * 9.0
			for k in 7:
				var p := at + Vector2(sin(flick * 1.3 + k * 2.1) * 20.0, cos(k * 1.7) * 6.0)
				var tall: float = (6.0 + 5.0 * absf(sin(flick + k))) * fade
				draw_colored_polygon(PackedVector2Array([p + Vector2(-3, 0), p + Vector2(3, 0), p + Vector2(0, -tall)]),
					Color(1.0, 0.6 + 0.3 * absf(sin(k + flick)), 0.15, 0.85 * fade))
		for fall in run.get("falling"):
			var done: float = 1.0 - clampf(float(fall["left"]) / FALL_SECONDS, 0.0, 1.0)
			var at: Vector2 = fall["at"]
			draw_set_transform(at, 0.0, Vector2(1.0, 0.5))
			draw_circle(Vector2.ZERO, 8.0 + 14.0 * done, Color(0.0, 0.0, 0.0, 0.2 + 0.25 * done))
			draw_arc(Vector2.ZERO, float(run.call("blast_reach")), 0.0, TAU, 40, Color(FIRE, 0.4 + 0.4 * done), 2.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_draw_star_ground()

	func _draw_star_ground() -> void:
		"""Under the monsters: the lying star's glow, the called star's shadow
		spreading, and the scorch after it lands."""
		var star: String = str(run.get("star_state"))
		var t: float = float(run.get("run_seconds"))
		if star == "lying":
			var at: Vector2 = run.get("star_at")
			draw_set_transform(at, 0.0, Vector2(1.0, 0.5))
			var pulse: float = 0.5 + 0.5 * sin(t * 6.0)
			draw_circle(Vector2.ZERO, STAR_RADIUS * 3.0, Color(STAR_GOLD, 0.12 + 0.1 * pulse))
			draw_circle(Vector2.ZERO, STAR_RADIUS * 1.6, Color(STAR_GOLD, 0.25 + 0.15 * pulse))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif star == "falling":
			var done: float = 1.0 - clampf(float(run.get("star_left")) / STAR_FALL, 0.0, 1.0)
			draw_set_transform(STAR_CENTRE, 0.0, Vector2(1.0, 0.5))
			var r: float = STAR_SHADOW * (0.35 + 0.65 * done)
			draw_circle(Vector2.ZERO, r, Color(0.0, 0.0, 0.0, 0.12 + 0.2 * done))
			draw_circle(Vector2.ZERO, r * 0.6, Color(0.0, 0.0, 0.0, 0.08 + 0.15 * done))
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 96, Color(1.0, 0.45, 0.15, 0.5 + 0.4 * done), 4.0)
			draw_arc(Vector2.ZERO, r * 0.94, 0.0, TAU, 96, Color(1.0, 0.75, 0.3, 0.3 + 0.3 * done), 2.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var after: float = float(run.get("star_afterglow")) / STAR_AFTERGLOW
		if after > 0.0:
			draw_set_transform(STAR_CENTRE, 0.0, Vector2(1.0, 0.55))
			draw_circle(Vector2.ZERO, STAR_SHADOW, Color(1.0, 0.45, 0.1, 0.22 * after))
			draw_circle(Vector2.ZERO, STAR_SHADOW * 0.66, Color(1.0, 0.6, 0.2, 0.25 * after))
			draw_circle(Vector2.ZERO, 60.0, Color(0.15, 0.08, 0.06, 0.85 * after))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			# The stone in its crater, glowing as it cools.
			var stone: Texture2D = load(METEOR_TEXTURE) as Texture2D
			if stone != null:
				var side: Vector2 = Vector2(stone.get_size()) * 4.0
				draw_texture_rect(stone, Rect2(STAR_CENTRE + Vector2(0.0, -10.0) - side / 2.0, side), false,
					Color(1.5, 0.85, 0.55, minf(1.0, after * 1.5)))
			var r2 := RandomNumberGenerator.new()
			r2.seed = 8
			for k in 70:
				var a: float = r2.randf() * TAU
				var d: float = r2.randf_range(40.0, STAR_SHADOW * 0.92)
				var p: Vector2 = STAR_CENTRE + Vector2(cos(a) * d, sin(a) * d * 0.55)
				var tall: float = r2.randf_range(8.0, 20.0) * after
				draw_colored_polygon(PackedVector2Array([p + Vector2(-4, 0), p + Vector2(4, 0), p + Vector2(0, -tall)]),
					Color(1.0, 0.55 + r2.randf() * 0.35, 0.12, 0.9 * after))

	func _draw_star_sky() -> void:
		"""Over everything: the claim ring round a lying star (a mark a hit
		it needs, lit as they land), the called star's fire trail, and the
		blast's ring and flash."""
		var star: String = str(run.get("star_state"))
		if star == "lying":
			var at: Vector2 = run.get("star_at")
			var need: int = maxi(1, int(run.call("claim_hits", int(run.get("players")))))
			var got: int = int(run.get("star_hits"))
			var each: float = TAU / float(need)
			for k in need:
				var from: float = -PI / 2.0 + each * k + 0.14
				var colour: Color = STAR_GOLD if k < got else Color(STAR_GOLD, 0.3)
				draw_arc(at, STAR_RADIUS * 2.6, from, from + each - 0.28, 16, Color(0.0, 0.0, 0.0, 0.6), 7.0)
				draw_arc(at, STAR_RADIUS * 2.6, from, from + each - 0.28, 16, colour, 4.0)
			# The time left, a thin ring closing.
			var left: float = clampf(float(run.get("star_left")) / STAR_LIFE, 0.0, 1.0)
			draw_arc(at, STAR_RADIUS * 2.6 + 7.0, -PI / 2.0, -PI / 2.0 + TAU * left, 40, Color(1.0, 1.0, 1.0, 0.55), 2.0)
		elif star == "falling":
			var done: float = 1.0 - clampf(float(run.get("star_left")) / STAR_FALL, 0.0, 1.0)
			var stone: Vector2 = run.call("star_sky_at", done)
			var back: Vector2 = (run.call("star_sky_at", 0.0) as Vector2 - stone).normalized()
			for k in 14:
				var u: float = float(k) / 14.0
				draw_circle(stone + back * (14.0 + 26.0 * k), 46.0 - k * 2.6,
					Color(1.0, 0.35 + u * 0.45, 0.08, 0.85 - u * 0.8))
		var after: float = float(run.get("star_afterglow")) / STAR_AFTERGLOW
		if after > 0.0:
			var grown: float = 1.0 - after
			draw_set_transform(STAR_CENTRE, 0.0, Vector2(1.0, 0.55))
			draw_arc(Vector2.ZERO, STAR_SHADOW * (0.9 + 0.35 * grown), 0.0, TAU, 96, Color(1.0, 0.95, 0.8, 0.9 * after), 6.0)
			draw_arc(Vector2.ZERO, STAR_SHADOW * (1.0 + 0.4 * grown), 0.0, TAU, 96, Color(1.0, 0.7, 0.4, 0.5 * after), 3.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_rect(Rect2(-HALF, VIEW), Color(1.0, 0.75, 0.4, 0.3 * maxf(0.0, after * 2.0 - 1.0)))


var steer: Callable = Callable(self, "_read_steer")
# Set by the screen each frame: where the mouse points, in the run's own
# space, and whether the button is held.
var aim: Vector2 = Vector2(0.0, -100.0)
var casting: bool = false
var showing_aim: bool = true
var seed_value: int = 0

var state: int = State.READY
var wave: int = 0
var waves_held: int = 0
var slain: int = 0
var run_seconds: float = 0.0
var door: float = DOOR_MOST
var door_most: float = DOOR_MOST
var portal: int = PORTAL_MOST
var banner: String = ""
var banner_left: float = 0.0
# The run's upgrades (id -> level), and the ones offered while picking.
var levels: Dictionary = {}
var offers: Array = []
var rerolls: int = REROLLS_FIRST
# Picks still owed for the waves just held (more than one after calling early).
var picks_left: int = 0
var called_early: int = 0
# Where the next group comes in (along the top), for the arrow.
var next_x: float = 0.0
# The gate struck this frame: it shakes and flashes.
var gate_struck: bool = false
# The wall's stretches: {side, from, to, health, broken, pieces, rubble}.
var stretches: Array = []
var wall_bars: WallBars = null
var falling: Array = []
var craters: Array = []
var casts: int = 0
var crits: int = 0

var world: Node2D = null
var floor_layer: TileMapLayer = null
var monsters: Node2D = null
var mage: AnimatedSprite2D = null
# Her side of the gate: -1 left, 1 right (SIDE_INNER).
var her_side: float = -1.0
var door_planks: Sprite2D = null
var door_parts: Array = []
var portal_sprite: AnimatedSprite2D = null
var ground_marks: Marks = null
var sky_marks: Marks = null

var _rng := RandomNumberGenerator.new()
var _fx_rng := RandomNumberGenerator.new()
var _left: float = READY_SECONDS
var _to_spawn: int = 0
var _group_in: float = 0.0
var _cast_in: float = 0.0
var _comet_count: int = 0

# THE STAR: "" none; "dropping" onto the field; "lying" there to be claimed;
# "held"; "falling" (called, its shadow spreading). star_left is the time
# left in the state; star_hits the meteors landed on it while it lies.
var star_state: String = ""
var star_at: Vector2 = Vector2.ZERO
var star_left: float = 0.0
var star_hits: int = 0
# Waves from STAR_FROM in a row that dropped none; seconds until this
# wave's drops (-1 none coming).
var star_waves_without: int = 0
var star_drop_in: float = -1.0
var stars_dropped: int = 0
var stars_called: int = 0
# What was on the field at the call (it alone is hit), and the glow after.
var star_marked: Array = []
var star_afterglow: float = 0.0
# The party (step 5): its size sets the hits a star needs.
var players: int = 1
var _star_rng := RandomNumberGenerator.new()
var _star_rock: Sprite2D = null


func _ready() -> void:
	# MEASURE HERE (0.152.0): the readout's Measure names this minigame.
	add_to_group(&"minigame_run")
	if seed_value != 0:
		_rng.seed = seed_value
		# The star rolls on its own, so the waves come as they did before it.
		_star_rng.seed = seed_value + 7919
	else:
		_rng.randomize()
		_star_rng.randomize()
	_fx_rng.randomize()
	_build()
	next_x = _group_x()
	# READY BEFORE THEY COME (0.152.0, scenewarmer.gd): every land's sprite
	# and slime, in the order the waves bring them, loaded between waves.
	var warmer: Node = (load("res://src/systems/scenewarmer.gd") as GDScript).call("add_to", self)
	warmer.set("calm", func() -> bool: return state != State.WAVE)
	warmer.call("warm", scenes_to_warm())


func _build() -> void:
	var dark := ColorRect.new()
	dark.color = Color(0.03, 0.03, 0.05)
	dark.position = -HALF - Vector2(40, 40)
	dark.size = VIEW + Vector2(80, 80)
	dark.z_index = -100
	add_child(dark)
	var ambience := CanvasModulate.new()
	ambience.color = Color(0.62, 0.62, 0.74)
	add_child(ambience)
	floor_layer = TileMapLayer.new()
	floor_layer.name = "floor"
	floor_layer.tile_set = load(FLOOR_SET) as TileSet
	floor_layer.collision_enabled = false
	floor_layer.navigation_enabled = false
	floor_layer.z_index = -10
	for y in range(floori(-HALF.y / TILE) - 1, ceili(HALF.y / TILE) + 1):
		for x in range(floori(-PATH_HALF / TILE), ceili(PATH_HALF / TILE)):
			floor_layer.set_cell(Vector2i(x, y), 1, Vector2i(_fx_rng.randi_range(1, 4), _fx_rng.randi_range(1, 3)))
	add_child(floor_layer)
	# Monsters, the wall and the gate share one layer sorted by y: whatever
	# is further down is drawn over what is behind it.
	world = Node2D.new()
	world.name = "world"
	world.y_sort_enabled = true
	add_child(world)
	monsters = Node2D.new()
	monsters.name = "monsters"
	monsters.y_sort_enabled = true
	world.add_child(monsters)
	_lay_walls()
	_lay_gate()
	_lay_portal()
	_make_mage()
	ground_marks = Marks.new()
	ground_marks.name = "ground"
	ground_marks.run = self
	ground_marks.z_index = MARKS_Z
	add_child(ground_marks)
	sky_marks = Marks.new()
	sky_marks.name = "sky"
	sky_marks.run = self
	sky_marks.sky = true
	sky_marks.z_index = SKY_Z
	add_child(sky_marks)
	wall_bars = WallBars.new()
	wall_bars.name = "wallbars"
	wall_bars.run = self
	wall_bars.z_index = HER_Z - 1
	add_child(wall_bars)
	# Beyond the side walls, dark over everything.
	for x in [-HALF.x - 40.0, PATH_HALF + 9.0]:
		var beyond := ColorRect.new()
		beyond.color = Color.BLACK
		beyond.position = Vector2(x, -HALF.y - 40.0)
		beyond.size = Vector2(HALF.x + 40.0 - PATH_HALF - 9.0, VIEW.y + 80.0)
		beyond.z_index = 50
		add_child(beyond)


func _lay_walls() -> void:
	# The side walls, as the Healer's Run's, over everything.
	var y: float = -HALF.y
	while y < HALF.y + RunScript.WALL_STEP:
		for x in [-PATH_HALF - 4.5, PATH_HALF + 4.5]:
			var side := _piece(RunScript.WALL_PIECE, Vector2(x, y), self)
			if side != null:
				side.z_index = RunScript.WALL_Z
		y += RunScript.WALL_STEP
	# The wall across: its face either side of the gate, laid end to end from
	# the gate out (the owner: "there is a gap on the right side of the
	# wall" - laid left to right, the right end stopped 13 px short), the last
	# piece running on under the side wall, where it is not seen.
	stretches = []
	for side in [-1.0, 1.0]:
		for k in STRETCH_EDGES.size() - 1:
			stretches.append({"side": side, "from": float(STRETCH_EDGES[k]), "to": float(STRETCH_EDGES[k + 1]),
				"health": WALL_MOST, "broken": false, "pieces": [], "rubble": []})
	for side in [-1.0, 1.0]:
		var x0: float = GATE_HALF
		while x0 < PATH_HALF + 4.5:
			var room: float = PATH_HALF + 4.5 - x0
			var w: int = 101 if room >= 101.0 else (51 if room >= 51.0 else 26)
			var face: Node2D = _piece(str(WALL_PIECES[w]), Vector2(side * (x0 + w / 2.0), FOOT), world)
			var at_stretch: int = stretch_at(side, x0 + w / 2.0)
			if face != null and at_stretch >= 0:
				(stretches[at_stretch]["pieces"] as Array).append(face)
			x0 += w
	# Its top, where she walks: the crypt's caps (the side walls' column,
	# turned to run along it), two rows, stopping at the gatehouse. Not in
	# the sorted layer: she is drawn over them (HER_Z), monsters never reach.
	var caps := AtlasTexture.new()
	caps.atlas = load(WALLS_ART) as Texture2D
	caps.region = CAP_REGION
	for row in 2:
		for side in [-1.0, 1.0]:
			# From the gate's posts out, over the pillars' tops (the owner: "fix
			# the missing squares by the gate" - from the pillars out, a
			# notch was left above each), under the side wall at the end.
			var from_gate: float = GATE_HALF
			while from_gate < PATH_HALF + 4.5:
				var cap := Sprite2D.new()
				cap.texture = caps
				cap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				cap.rotation = PI / 2.0
				cap.position = Vector2(side * (from_gate + CAP_REGION.size.y / 2.0), FOOT - 32.5 - row * 9.0)
				cap.z_index = 1
				add_child(cap)
				from_gate += CAP_REGION.size.y
	for side in [-1.0, 1.0]:
		_piece("res://scene/crypt/pillar.tscn", Vector2(side * 48.0, FOOT + 2.0), world)
	# Outside: rubble and bones; inside: candles.
	for at in [Vector2(-260, -200), Vector2(250, -180), Vector2(-90, -120), Vector2(140, -40), Vector2(-280, 40)]:
		_piece("res://scene/crypt/rubble4.tscn", at, self).z_index = -5
	_piece("res://scene/crypt/skullpile.tscn", Vector2(290, -60), self).z_index = -5
	for at in [Vector2(-160, 236), Vector2(160, 236)]:
		_piece("res://scene/crypt/candelabra.tscn", at, world)


func _lay_gate() -> void:
	"""The crypt door as the gate, from its own art (the door scene's three
	pieces, without its script), see-through."""
	var art: Texture2D = load(DOOR_ART) as Texture2D
	var gate := Node2D.new()
	gate.name = "gate"
	gate.position = Vector2(0.0, FOOT)
	world.add_child(gate)
	for part in [[Rect2(14, 19, 9, 28), -30.0], [Rect2(23, 19, 21, 28), 0.0], [Rect2(44, 19, 9, 28), 30.0]]:
		var tex := AtlasTexture.new()
		tex.atlas = art
		tex.region = part[0]
		var piece := Sprite2D.new()
		piece.texture = tex
		piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		piece.scale = Vector2(2, 2)
		piece.position = Vector2(float(part[1]), -28.0)
		piece.modulate.a = DOOR_SEE
		gate.add_child(piece)
		door_parts.append(piece)
	door_planks = door_parts[1]


func _lay_portal() -> void:
	var glow := Node2D.new()
	glow.name = "portalglow"
	glow.position = PORTAL_AT
	glow.z_index = -1
	glow.draw.connect(_draw_portal_glow.bind(glow))
	add_child(glow)
	portal_sprite = AnimatedSprite2D.new()
	portal_sprite.name = "portal"
	portal_sprite.sprite_frames = load(PORTAL_FRAMES) as SpriteFrames
	if portal_sprite.sprite_frames != null:
		portal_sprite.play("default")
	portal_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portal_sprite.scale = Vector2(2.0, 2.0)
	portal_sprite.position = PORTAL_AT
	world.add_child(portal_sprite)


func _draw_portal_glow(glow: Node2D) -> void:
	var strength: float = clampf(float(portal) / PORTAL_MOST, 0.0, 1.0)
	for k in 6:
		glow.draw_circle(Vector2.ZERO, 42.0 - k * 6.0, Color(0.55, 0.35, 1.0, (0.05 + k * 0.025) * (0.3 + 0.7 * strength)))


func _make_mage() -> void:
	var look: Dictionary = RunScript.look_of_scene(MAGE_SCENE, false)
	mage = AnimatedSprite2D.new()
	mage.name = "mage"
	mage.sprite_frames = look.get("frames") as SpriteFrames
	mage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mage.offset = look.get("offset", Vector2.ZERO)
	mage.position = Vector2(-150.0, WALK_Y)
	mage.z_index = HER_Z
	_play("idleup")
	var glow := (load("res://scene/characters/playerlight.tscn") as PackedScene).instantiate() as PointLight2D
	if glow != null:
		glow.enabled = true
		mage.add_child(glow)
	add_child(mage)


func _piece(path: String, at: Vector2, parent: Node) -> Node2D:
	if not ResourceLoader.exists(path):
		return null
	var p := (load(path) as PackedScene).instantiate() as Node2D
	p.position = at
	parent.add_child(p)
	return p


func _play(animation: String) -> void:
	if mage != null and mage.sprite_frames != null and mage.sprite_frames.has_animation(animation) \
			and mage.animation != animation:
		mage.play(animation)


# =============================================================================
# THE RUN, A FRAME AT A TIME
# =============================================================================

# WHO SPENT IT (0.152.0): this minigame's own frame, timed, so a slow
# frame on the readout names it (PerfOverlay.spend()).
func _process(delta: float) -> void:
	var spent_from: int = Time.get_ticks_usec()
	_timed_process(delta)
	PerfOverlay.spend(&"mage's stand", Time.get_ticks_usec() - spent_from)


func _timed_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	"""One frame; the suite calls it with its own delta."""
	ground_marks.queue_redraw()
	sky_marks.queue_redraw()
	if wall_bars != null:
		wall_bars.queue_redraw()
	if state == State.LOST:
		return
	if state == State.PICK:
		# THE NEXT WAVE WAITS, and the clock with it, until she picks.
		_falls(delta)
		_burn(delta)
		_move_monsters(delta)
		return
	run_seconds += delta
	banner_left = maxf(0.0, banner_left - delta)
	if banner_left <= 0.0:
		banner = ""
	_walk(delta)
	_cast(delta)
	_falls(delta)
	_star(delta)
	_burn(delta)
	_move_monsters(delta)
	_waves(delta)
	var glow: Node2D = get_node_or_null("portalglow")
	if glow != null:
		glow.queue_redraw()


func _read_steer() -> float:
	# A thumb on the stick: as it lies (0.110.2).
	if TouchControls.stick_held:
		return TouchControls.analog_move().x
	var dir: float = 0.0
	if Input.is_action_pressed("move_right"):
		dir += 1.0
	if Input.is_action_pressed("move_left"):
		dir -= 1.0
	return dir


static func side_for(seat: int) -> float:
	"""A party's seat to its side of the gate: the first left, the second
	right, and so on - two each side for four."""
	return -1.0 if seat % 2 == 0 else 1.0


static func walk_span(on_side: float) -> Vector2:
	"""Where on `on_side` she may stand: x from, x to."""
	return Vector2(-WALK_HALF, -SIDE_INNER) if on_side < 0.0 else Vector2(SIDE_INNER, WALK_HALF)


func _walk(delta: float) -> void:
	var dir: float = clampf(float(steer.call()), -1.0, 1.0)
	var span: Vector2 = walk_span(her_side)
	mage.position.x = clampf(mage.position.x + dir * WALK_SPEED * delta, span.x, span.y)
	mage.position.y = WALK_Y
	if casting:
		_play("attackup")
	elif dir < 0.0:
		_play("walkleft")
	elif dir > 0.0:
		_play("walkright")
	else:
		_play("idleup")


# =============================================================================
# THE METEORS
# =============================================================================

func _cast(delta: float) -> void:
	_cast_in = maxf(0.0, _cast_in - delta)
	if casting and _cast_in <= 0.0 and (state == State.WAVE or state == State.BETWEEN):
		_cast_in = cast_gap()
		drop_meteor(aim)
		if level("double") > 0 and _rng.randf() < double_chance():
			drop_meteor(aim + Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * DOUBLE_SPREAD)


func drop_meteor(at: Vector2, small: bool = false) -> void:
	"""A meteor called down at `at` (held to the field); `small` is a piece of
	a Meteor shower - half as hard, never critical, never a comet."""
	var spot := Vector2(clampf(at.x, -PATH_HALF + 6.0, PATH_HALF - 6.0), clampf(at.y, -HALF.y + 6.0, HALF.y - 6.0))
	var rock := Sprite2D.new()
	rock.texture = load(METEOR_TEXTURE) as Texture2D
	rock.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rock.z_index = SKY_Z + 1
	rock.position = spot + SKY
	add_child(rock)
	if small:
		rock.scale = Vector2(0.6, 0.6)
		falling.append({"at": spot, "left": FALL_SECONDS * 0.6, "rock": rock, "crit": false, "small": true})
		return
	casts += 1
	var comet: bool = false
	if level("comet") > 0:
		_comet_count += 1
		comet = _comet_count % COMET_EVERY == 0
	var crit: bool = _rng.randf() < crit_chance()
	if crit:
		crits += 1
		rock.modulate = Color(1.6, 0.8, 0.6)
	if comet:
		rock.scale = Vector2(1.8, 1.8)
		rock.modulate = Color(1.4, 1.1, 1.6)
	falling.append({"at": spot, "left": FALL_SECONDS, "rock": rock, "crit": crit, "comet": comet})


func _falls(delta: float) -> void:
	var still: Array = []
	for fall in falling:
		fall["left"] = float(fall["left"]) - delta
		var rock: Sprite2D = fall["rock"]
		var done: float = 1.0 - clampf(float(fall["left"]) / FALL_SECONDS, 0.0, 1.0)
		if is_instance_valid(rock):
			rock.position = (fall["at"] + SKY).lerp(fall["at"], done * done)
			rock.rotation += delta * 6.0
		if float(fall["left"]) > 0.0:
			still.append(fall)
		else:
			_land(fall)
	falling = still


func _land(fall: Dictionary) -> void:
	var at: Vector2 = fall["at"]
	var rock: Sprite2D = fall["rock"]
	if is_instance_valid(rock):
		rock.queue_free()
	var damage: float = blast_damage() * (CRIT_MULT if bool(fall["crit"]) else 1.0)
	var reach: float = blast_reach()
	if bool(fall.get("comet", false)):
		damage *= COMET_HIT
		reach *= COMET_REACH
	if bool(fall.get("small", false)):
		damage *= SHOWER_SHARE
		reach *= SHOWER_SHARE
	if level("pull") > 0 and _rng.randf() < pull_chance():
		_pull(at, reach * PULL_REACH)
	for node in monsters.get_children():
		var m := node as Monster
		if m != null and m.dying < 0.0 and m.position.distance_to(at) <= reach + m.radius:
			hurt(m, damage)
	if star_state == "lying" and at.distance_to(star_at) <= reach + STAR_RADIUS:
		_strike_star()
	craters.append({"at": at, "left": burn_seconds(), "seed": _fx_rng.randf() * 100.0})
	if bool(fall["crit"]) and level("shower") > 0:
		for i in SHOWER_PIECES:
			var turn: float = TAU * float(i) / float(SHOWER_PIECES) + _fx_rng.randf() * 0.6
			drop_meteor(at + Vector2(cos(turn), sin(turn) * 0.6) * SHOWER_SPREAD, true)
	var burst = RunScript.Burst.new()
	burst.position = at
	burst.colour = Color(1.0, 0.4, 0.2) if bool(fall["crit"]) else FIRE
	burst.reach = reach * (1.3 if bool(fall["crit"]) else 1.0)
	burst.sparks = 12
	burst.life = 0.35
	burst.most = 0.35
	burst.z_index = SKY_Z - 1
	add_child(burst)


func _pull(at: Vector2, reach: float) -> void:
	"""THE PULL: what is outside the gate within `reach` is dragged most of
	the way in, so the blast that follows catches the pack."""
	for node in monsters.get_children():
		var m := node as Monster
		if m != null and m.dying < 0.0 and not m.through and m.position.distance_to(at) <= reach:
			m.position = m.position.lerp(at, PULL_SHARE)
			m.at_gate = false


func _burn(delta: float) -> void:
	"""Craters burn what stands in them - from ONE crater at a time, however
	many overlap (0.110.0: stacked on the gate they melted everything)."""
	var still: Array = []
	for crater in craters:
		crater["left"] = float(crater["left"]) - delta
		if float(crater["left"]) > 0.0:
			still.append(crater)
	craters = still
	if craters.is_empty():
		return
	var reach: float = burn_reach()
	for node in monsters.get_children():
		var m := node as Monster
		if m == null or m.dying >= 0.0:
			continue
		for crater in craters:
			if m.position.distance_to(crater["at"]) <= reach + m.radius:
				hurt(m, burn_dps() * delta)
				break


func hurt(m: Monster, damage: float) -> void:
	if m.dying >= 0.0:
		return
	m.health -= damage
	m.flash = 0.08
	if m.health <= 0.0:
		m.dying = 0.25
		slain += 1
		if m.kind == "bomber":
			_blow_up(m.position)


func _blow_up(at: Vector2) -> void:
	"""A bomber slain on its way: it goes up where it stands, hurting what is
	round it (other bombers too)."""
	_bang(at, BOMB_REACH)
	for node in monsters.get_children():
		var other := node as Monster
		if other != null and other.dying < 0.0 and other.position.distance_to(at) <= BOMB_REACH + other.radius:
			hurt(other, BOMB_DAMAGE)


# =============================================================================
# THE STAR: a giant meteor, dropped by a wave, claimed, held, called down
# =============================================================================

static func star_comes(at_wave: int, waves_without: int, roll: float) -> bool:
	"""Does wave `at_wave` drop a star? From STAR_FROM, one in STAR_CHANCE -
	and surely once STAR_SURE - 1 waves in a row have dropped none."""
	return at_wave >= STAR_FROM and (roll < STAR_CHANCE or waves_without >= STAR_SURE - 1)


static func claim_hits(party: int) -> int:
	"""Meteors to land on a star to claim it: STAR_HITS_ALONE alone,
	STAR_HITS_FOUR for four - a party claims as fast as one alone, the horde
	already scaled for it."""
	var n: int = clampi(party, 1, 4)
	return roundi(lerpf(float(STAR_HITS_ALONE), float(STAR_HITS_FOUR), float(n - 1) / 3.0))


static func star_hit(m: Monster) -> float:
	"""What the star takes from `m`: all of an ordinary monster, half an
	elite's health, a fifth of a keeper's."""
	if m.rank == "keeper":
		return m.most * STAR_KEEPER_SHARE
	if m.rank == "elite":
		return m.most * STAR_ELITE_SHARE
	return m.health


func _roll_star() -> void:
	"""At a wave's start: one star at a time - none rolled while one is about."""
	if wave < STAR_FROM or star_state != "" or star_drop_in >= 0.0:
		return
	if star_comes(wave, star_waves_without, _star_rng.randf()):
		star_waves_without = 0
		star_drop_in = STAR_DROP_AFTER
	else:
		star_waves_without += 1


func _drop_star() -> void:
	star_drop_in = -1.0
	stars_dropped += 1
	star_state = "dropping"
	star_left = STAR_DROP_SECONDS
	star_hits = 0
	star_at = Vector2(_star_rng.randf_range(-PATH_HALF + 70.0, PATH_HALF - 70.0),
		_star_rng.randf_range(-HALF.y + 110.0, FOOT - 150.0))
	_star_rock = Sprite2D.new()
	_star_rock.name = "star"
	_star_rock.texture = load(METEOR_TEXTURE) as Texture2D
	_star_rock.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_star_rock.scale = Vector2(2.5, 2.5)
	_star_rock.modulate = Color(1.5, 1.25, 0.8)
	_star_rock.z_index = SKY_Z - 2
	_star_rock.position = star_at + SKY * 2.0
	add_child(_star_rock)
	banner = "A star fell! Land %d meteors on it to claim it" % claim_hits(players)
	banner_left = BANNER_SECONDS * 1.5


func _strike_star() -> void:
	star_hits += 1
	if is_instance_valid(_star_rock):
		_star_rock.modulate = Color(2.2, 1.8, 1.2)
	if star_hits >= claim_hits(players):
		star_state = "held"
		_drop_star_rock()
		banner = "The star is yours - call it down when the horde is thick"
		banner_left = BANNER_SECONDS * 1.5


func _drop_star_rock() -> void:
	if is_instance_valid(_star_rock):
		_star_rock.queue_free()
	_star_rock = null


func can_call_star() -> bool:
	return star_state == "held" and state == State.WAVE


func call_star() -> bool:
	"""THE STAR CALLED: its shadow spreads, and STAR_FALL later it lands on
	what is on the field now."""
	if not can_call_star():
		return false
	star_state = "falling"
	star_left = STAR_FALL
	stars_called += 1
	star_marked.clear()
	for node in monsters.get_children():
		var m := node as Monster
		if m != null and m.dying < 0.0:
			star_marked.append(m)
	_star_rock = Sprite2D.new()
	_star_rock.name = "star"
	_star_rock.texture = load(METEOR_TEXTURE) as Texture2D
	_star_rock.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_star_rock.scale = Vector2(6.0, 6.0)
	_star_rock.z_index = SKY_Z + 2
	_star_rock.position = star_sky_at(0.0)
	add_child(_star_rock)
	banner = "A star falls!"
	banner_left = STAR_FALL
	return true


static func star_sky_at(done: float) -> Vector2:
	"""Where the called star is, `done` of the way down."""
	return (STAR_CENTRE + Vector2(230.0, -250.0)).lerp(STAR_CENTRE + Vector2(0.0, -10.0), pow(done, 1.6))


func _star(delta: float) -> void:
	star_afterglow = maxf(0.0, star_afterglow - delta)
	if star_drop_in >= 0.0:
		star_drop_in -= delta
		if star_drop_in < 0.0:
			_drop_star()
	match star_state:
		"dropping":
			star_left -= delta
			var done: float = 1.0 - clampf(star_left / STAR_DROP_SECONDS, 0.0, 1.0)
			if is_instance_valid(_star_rock):
				_star_rock.position = (star_at + SKY * 2.0).lerp(star_at, done * done)
				_star_rock.rotation += delta * 4.0
			if star_left <= 0.0:
				star_state = "lying"
				star_left = STAR_LIFE
				_bang(star_at, STAR_RADIUS * 2.5)
		"lying":
			star_left -= delta
			if is_instance_valid(_star_rock):
				_star_rock.position = star_at + Vector2(0.0, sin(run_seconds * 3.0) * 2.0)
				_star_rock.rotation += delta * 0.6
				var glow: float = 1.25 + 0.25 * sin(run_seconds * 6.0)
				_star_rock.modulate = _star_rock.modulate.lerp(Color(1.5 * glow, 1.25 * glow, 0.8), minf(1.0, delta * 6.0))
				# It blinks as it fades.
				_star_rock.visible = star_left > 3.0 or fmod(star_left, 0.4) > 0.15
			if star_left <= 0.0:
				star_state = ""
				star_hits = 0
				_drop_star_rock()
				banner = "The star faded"
				banner_left = BANNER_SECONDS
		"falling":
			star_left -= delta
			var done: float = 1.0 - clampf(star_left / STAR_FALL, 0.0, 1.0)
			if is_instance_valid(_star_rock):
				_star_rock.position = star_sky_at(done)
				_star_rock.rotation += delta * 2.0
			if star_left <= 0.0:
				_star_lands()


func _star_lands() -> void:
	"""Every monster on the field at the call: the ordinary slain, elites and
	keepers hurt (star_hit())."""
	star_state = ""
	_drop_star_rock()
	for node in star_marked:
		if not is_instance_valid(node):
			continue
		var m := node as Monster
		if m != null and m.dying < 0.0:
			hurt(m, star_hit(m))
	star_marked.clear()
	star_afterglow = STAR_AFTERGLOW
	banner = "The field is wiped!"
	banner_left = BANNER_SECONDS


func _bang(at: Vector2, reach: float) -> void:
	var burst = RunScript.Burst.new()
	burst.position = at
	burst.colour = Color(1.0, 0.75, 0.3)
	burst.reach = reach
	burst.sparks = 16
	burst.life = 0.4
	burst.most = 0.4
	burst.z_index = SKY_Z - 1
	add_child(burst)


# =============================================================================
# THE HORDE, THE GATE AND THE PORTAL
# =============================================================================

func wave_count(n: int) -> int:
	return WAVE_FIRST + WAVE_MORE * (maxi(1, n) - 1)


static func wave_speed(n: int) -> float:
	"""Faster each wave, to twice as fast."""
	return minf(2.0, 1.0 + 0.06 * (maxi(1, n) - 1))


static func wave_health(n: int) -> float:
	return 1.0 + 0.15 * (maxi(1, n) - 1)


static func bomber_chance(n: int) -> float:
	"""A share of each group are bombers from BOMBERS_FROM, more each wave."""
	if n < BOMBERS_FROM:
		return 0.0
	return minf(BOMBER_MOST, BOMBER_CHANCE + BOMBER_MORE * (n - BOMBERS_FROM))


static func wave_hit(n: int) -> float:
	return 1.0 + 0.1 * (maxi(1, n) - 1)


static func scenes_to_warm() -> Array:
	"""Each land's sprite and slime, in the order the waves come to them."""
	var out: Array = []
	for element in RunScript.LANDS:
		# As spawn() chooses them, the stand-in where a land has none.
		var sprite: String = str(RunScript.SPRITES.get(element, "windsprite"))
		var slime: String = str(RunScript.SLIMES.get(element, ""))
		for scene_id in [sprite, slime if slime != "" else sprite]:
			var path: String = "res://scene/enemy/%s.tscn" % str(scene_id)
			if not out.has(path):
				out.append(path)
	return out


func land() -> int:
	@warning_ignore("integer_division")
	return int(RunScript.LANDS[((maxi(1, wave) - 1) / LAND_WAVES) % RunScript.LANDS.size()])


func land_name() -> String:
	return Element.name_for(land()).capitalize()


func living() -> int:
	var count: int = 0
	for node in monsters.get_children():
		var m := node as Monster
		if m != null and m.dying < 0.0:
			count += 1
	return count


func spawn(kind: String, at: Vector2) -> Monster:
	var element: int = land()
	var scene_id: String = str(RunScript.SPRITES.get(element, "windsprite")) if kind == "sprite" \
		else str(RunScript.SLIMES.get(element, ""))
	if scene_id == "":
		scene_id = str(RunScript.SPRITES.get(element, "windsprite"))
	var info: Dictionary = KINDS[kind]
	var m := Monster.new()
	m.kind = kind
	m.most = float(info["health"]) * wave_health(wave)
	m.health = m.most
	m.speed = float(info["speed"]) * wave_speed(wave) * _rng.randf_range(0.85, 1.15)
	m.radius = float(info["radius"])
	m.drain = int(info["drain"])
	m.stop_y = pow(_rng.randf(), 1.5) * 70.0
	send_to(m, choose_target(kind, at.x))
	m.position = at
	m.z_index = MONSTER_Z
	var look: Dictionary = RunScript.look_of_scene("res://scene/enemy/%s.tscn" % scene_id)
	m.sprite = AnimatedSprite2D.new()
	m.sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	m.sprite.sprite_frames = look.get("frames") as SpriteFrames
	m.sprite.material = look.get("material") as Material
	m.sprite.self_modulate = look.get("modulate", Color.WHITE)
	m.sprite.offset = look.get("offset", Vector2.ZERO)
	m.sprite.scale = look.get("scale", Vector2.ONE)
	m.add_child(m.sprite)
	var walk: String = str(look.get("walk", ""))
	if walk != "":
		m.sprite.play(walk)
	if kind == "bomber":
		m.sprite.self_modulate = Color(1.5, 0.7, 0.55)
		m.fuse = Fuse.new()
		m.add_child(m.fuse)
	monsters.add_child(m)
	return m


func stretch_at(side: float, out: float) -> int:
	"""Which stretch is `out` from the gate on `side` (-1 left, 1 right)."""
	for k in STRETCH_EDGES.size() - 1:
		if out >= float(STRETCH_EDGES[k]) and out < float(STRETCH_EDGES[k + 1]):
			return k + (0 if side < 0.0 else STRETCH_EDGES.size() - 1)
	return -1


func choose_target(kind: String, from_x: float) -> int:
	"""The gate for GATE_SHARE of them (never a bomber); else the stretch
	nearest where it came in, give or take."""
	if kind != "bomber" and _rng.randf() < GATE_SHARE:
		return -1
	var near_x: float = from_x + _rng.randf_range(-120.0, 120.0)
	var best: int = 0
	var best_far: float = INF
	for i in stretches.size():
		var one: Dictionary = stretches[i]
		var mid: float = float(one["side"]) * (float(one["from"]) + float(one["to"])) / 2.0
		if absf(mid - near_x) < best_far:
			best_far = absf(mid - near_x)
			best = i
	return best


func send_to(m: Monster, target: int) -> void:
	"""Point a monster at the gate (-1) or a stretch: where along it it stops."""
	m.target = target
	if target < 0 or target >= stretches.size():
		m.target = -1
		m.stop_x = _rng.randf_range(-GATE_HALF + 6.0, GATE_HALF - 6.0)
		return
	var one: Dictionary = stretches[target]
	var out: float = _rng.randf_range(float(one["from"]) + 10.0, minf(float(one["to"]), PATH_HALF) - 12.0)
	m.stop_x = float(one["side"]) * out


func target_open(m: Monster) -> bool:
	"""Is the way through where it is going open: the gate broken, or its
	stretch breached?"""
	if m.target < 0:
		return door <= 0.0
	return bool(stretches[m.target]["broken"])


func _in_opening(m: Monster) -> bool:
	if m.target < 0:
		return absf(m.position.x) <= GATE_HALF
	var one: Dictionary = stretches[m.target]
	return signf(m.position.x) == float(one["side"]) and absf(m.position.x) >= float(one["from"]) - 4.0 \
		and absf(m.position.x) <= float(one["to"]) + 4.0


func _breach(i: int) -> void:
	"""A stretch at nought: its face down, rubble in the gap."""
	var one: Dictionary = stretches[i]
	one["health"] = 0.0
	one["broken"] = true
	for face in one["pieces"]:
		if is_instance_valid(face):
			(face as Node2D).visible = false
	var mid: float = float(one["side"]) * (float(one["from"]) + minf(float(one["to"]), PATH_HALF)) / 2.0
	for dx in [-22.0, 18.0]:
		var rubble: Node2D = _piece(RUBBLE_SCENE, Vector2(mid + dx, FOOT - 4.0), world)
		if rubble != null:
			(one["rubble"] as Array).append(rubble)
	banner = "The wall is breached!"
	banner_left = BANNER_SECONDS


func _rebuild(i: int, share: float) -> void:
	var one: Dictionary = stretches[i]
	one["health"] = minf(WALL_MOST, float(one["health"]) + WALL_MOST * share)
	if bool(one["broken"]):
		one["broken"] = false
		for face in one["pieces"]:
			if is_instance_valid(face):
				(face as Node2D).visible = true
		for rubble in one["rubble"]:
			if is_instance_valid(rubble):
				(rubble as Node).queue_free()
		one["rubble"] = []


func breaches() -> int:
	var count: int = 0
	for one in stretches:
		count += 1 if bool(one["broken"]) else 0
	return count


func weakest() -> int:
	"""The weakest of the wall, by share of its most: -1 the gate, else a
	stretch (a breach is nought). -2 when all of it is whole."""
	var low: float = door / maxf(1.0, door_most)
	var which: int = -1
	for i in stretches.size():
		var share: float = 0.0 if bool(stretches[i]["broken"]) else float(stretches[i]["health"]) / WALL_MOST
		if share < low:
			low = share
			which = i
	return -2 if low >= 1.0 else which


func _repair(share: float) -> void:
	var which: int = weakest()
	if which == -1:
		_mend_gate(share)
	elif which >= 0:
		_rebuild(which, share)


func _move_monsters(delta: float) -> void:
	# How many hit each part of the wall (-1 the gate, else a stretch).
	var hits: Dictionary = {}
	for node in monsters.get_children():
		var m := node as Monster
		if m == null:
			continue
		if m.dying >= 0.0:
			m.dying -= delta
			m.modulate.a = clampf(m.dying / 0.25, 0.0, 1.0)
			if m.dying <= 0.0:
				_gone(m)
			continue
		m.flash = maxf(0.0, m.flash - delta)
		m.modulate = Color(2.2, 2.2, 2.2) if m.flash > 0.0 else Color.WHITE
		if m.fuse != null:
			# A bomber: its fuse flickers and it pulses red.
			var pulse: float = absf(sin(run_seconds * 7.0 + m.stop_y))
			m.fuse.modulate.a = 0.55 + 0.45 * absf(sin(run_seconds * 13.0 + m.stop_y))
			if m.flash <= 0.0:
				m.modulate = Color(1.0 + 0.7 * pulse, 1.0 - 0.45 * pulse, 1.0 - 0.45 * pulse)
		var open: bool = target_open(m)
		if not m.through and open and m.position.y >= FOOT - 40.0 and _in_opening(m):
			m.through = true
		if m.through:
			# THROUGH THE GATE: for the portal.
			var to_portal: Vector2 = PORTAL_AT - m.position
			if to_portal.length() <= PORTAL_REACH:
				_into_portal(m)
				continue
			m.position += to_portal.limit_length(m.speed * delta)
			continue
		var goal := Vector2(m.stop_x, FOOT - 26.0 - m.stop_y)
		if m.kind == "bomber":
			goal.y = FOOT - 24.0
		if open:
			goal = Vector2(m.stop_x * (0.6 if m.target < 0 else 1.0), FOOT - 20.0)
		var to_goal: Vector2 = goal - m.position
		if to_goal.length() <= 1.5:
			m.position = goal
			m.at_gate = not open
		else:
			m.at_gate = false
			m.position += to_goal.limit_length(m.speed * delta)
		if m.at_gate and m.kind == "bomber":
			_bomb_the_wall(m)
			continue
		if m.at_gate:
			hits[m.target] = int(hits.get(m.target, 0)) + 1
	var strength: float = DOOR_HIT * wave_hit(wave) * delta
	gate_struck = door > 0.0 and int(hits.get(-1, 0)) > 0
	if gate_struck:
		door = maxf(0.0, door - strength * mini(int(hits[-1]), GATE_HITTERS))
		if door <= 0.0:
			gate_struck = false
			_break_gate()
	for i in stretches.size():
		var count: int = int(hits.get(i, 0))
		if count > 0 and not bool(stretches[i]["broken"]):
			stretches[i]["health"] = maxf(0.0, float(stretches[i]["health"]) - strength * mini(count, WALL_HITTERS))
			if float(stretches[i]["health"]) <= 0.0:
				_breach(i)
	_shake_gate()


func _bomb_the_wall(m: Monster) -> void:
	"""A bomber at the wall: BOMB_HIT off its stretch (or the gate), and gone -
	no kill to anyone."""
	if m.target < 0:
		door = maxf(0.0, door - BOMB_HIT)
		if door <= 0.0:
			_break_gate()
	elif not bool(stretches[m.target]["broken"]):
		stretches[m.target]["health"] = maxf(0.0, float(stretches[m.target]["health"]) - BOMB_HIT)
		if float(stretches[m.target]["health"]) <= 0.0:
			_breach(m.target)
	_bang(m.position, BOMB_REACH)
	_gone(m)


func _break_gate() -> void:
	"""Broken: its planks down in the gap, and they run for the portal."""
	door_planks.rotation = 1.45
	door_planks.position = Vector2(4.0, -6.0)
	door_planks.modulate = Color(0.55, 0.45, 0.4, DOOR_SEE)
	banner = "The gate is broken!"
	banner_left = BANNER_SECONDS


func _shake_gate() -> void:
	"""Struck, the gate shakes and flashes; still, it stands as built."""
	var gate: Node2D = world.get_node_or_null("gate")
	if gate == null:
		return
	gate.position.x = sin(run_seconds * 47.0) * 1.5 if gate_struck else 0.0
	var flash: float = maxf(0.0, sin(run_seconds * 14.0)) * 0.7 if gate_struck else 0.0
	for part in door_parts:
		if part == door_planks and door <= 0.0:
			continue
		(part as Sprite2D).modulate = Color(1.0 + flash, 1.0 - flash * 0.3, 1.0 - flash * 0.4, DOOR_SEE)


func gate_low() -> bool:
	return door > 0.0 and door < door_most * GATE_LOW


func _mend_gate(share: float) -> void:
	"""The Gate patch: mended `share` of its most - a broken one rebuilt."""
	door = minf(door_most, door + door_most * share)
	door_planks.rotation = 0.0
	door_planks.position = Vector2(0.0, -28.0)
	door_planks.modulate = Color(1.0, 1.0, 1.0, DOOR_SEE)


func gate_broken() -> bool:
	return door <= 0.0


func _into_portal(m: Monster) -> void:
	portal = maxi(0, portal - m.drain)
	_gone(m)
	if portal <= 0 and state != State.LOST:
		state = State.LOST
		banner = "The portal fell"
		banner_left = BANNER_SECONDS * 3.0
		finished.emit()


static func _gone(node: Node) -> void:
	var parent: Node = node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()


func _waves(delta: float) -> void:
	match state:
		State.READY, State.BETWEEN:
			_left -= delta
			if _left <= 0.0:
				_start_wave()
		State.WAVE:
			if _to_spawn > 0:
				_group_in -= delta
				if _group_in <= 0.0 and monsters.get_child_count() < MONSTERS_MOST:
					_group_in = GROUP_GAP
					_spawn_group()
			elif living() == 0:
				_end_wave()


func _group_x() -> float:
	return _rng.randf_range(-PATH_HALF + 60.0, PATH_HALF - 60.0)


func arrow_showing() -> bool:
	"""The arrow over where the next group comes in: before a wave, and while
	more of one are still to come."""
	return state == State.READY or state == State.BETWEEN or state == State.PICK \
		or (state == State.WAVE and _to_spawn > 0)


func can_call_early() -> bool:
	"""Once a wave has all come in and some of it is still about."""
	return state == State.WAVE and _to_spawn == 0 and living() > 0


func call_early() -> bool:
	"""The next wave now, on top of what is left of this one: a reroll for it,
	and its pick still comes when the field is clear."""
	if not can_call_early():
		return false
	called_early += 1
	rerolls += 1
	_start_wave()
	banner = "Wave %d called early - a reroll for it" % wave
	return true


func _start_wave() -> void:
	wave += 1
	_to_spawn = wave_count(wave)
	_group_in = 0.0
	state = State.WAVE
	banner = "Wave %d - the %s lands" % [wave, land_name()]
	banner_left = BANNER_SECONDS
	_roll_star()


func _spawn_group() -> void:
	"""One group of the wave flooding in from the top: bigger each wave."""
	var size: int = mini(_to_spawn, GROUP_FIRST + wave)
	var centre: float = next_x
	next_x = _group_x()
	for i in size:
		var kind: String = "sprite" if _rng.randf() < 0.5 else "slime"
		if wave >= BOMBERS_FROM and _rng.randf() < bomber_chance(wave):
			kind = "bomber"
		var at := Vector2(clampf(centre + _rng.randf_range(-70.0, 70.0), -PATH_HALF + 12.0, PATH_HALF - 12.0),
			-HALF.y - 12.0 - _rng.randf_range(0.0, 40.0))
		spawn(kind, at)
	_to_spawn -= size


func _end_wave() -> void:
	var before: int = waves_held
	waves_held = wave
	picks_left = picks_due(before, waves_held)
	offers = roll_offers() if picks_left > 0 else []
	if offers.is_empty():
		picks_left = 0
		state = State.BETWEEN
		_left = BETWEEN_SECONDS
		var next_pick: int = (floori(float(waves_held) / PICK_EVERY) + 1) * PICK_EVERY
		banner = "Wave %d held - an upgrade after wave %d" % [wave, next_pick]
		banner_left = BANNER_SECONDS
	else:
		state = State.PICK
		banner = ""


# =============================================================================
# THE PICK: one upgrade of three after each wave, for the rest of the run
# =============================================================================

static func picks_due(held_before: int, held_now: int) -> int:
	"""A pick for every PICK_EVERY-th wave passed between the two."""
	return floori(float(held_now) / PICK_EVERY) - floori(float(held_before) / PICK_EVERY)


func level(id: String) -> int:
	return int(levels.get(id, 0))


func cast_gap() -> float:
	return CAST_GAP / pow(CAST_STEP, level("cast"))


func blast_reach() -> float:
	return BLAST_REACH * (1.0 + BLAST_STEP * level("blast"))


func blast_damage() -> float:
	return BLAST_DAMAGE * (1.0 + POWER_STEP * level("power"))


func burn_seconds() -> float:
	return BURN_SECONDS * (1.0 + BURN_STEP * level("burn"))


func burn_reach() -> float:
	return BURN_REACH * (FIRESTORM_MULT if level("firestorm") > 0 else 1.0)


func burn_dps() -> float:
	return BURN_DPS * (FIRESTORM_MULT if level("firestorm") > 0 else 1.0)


func most_of(id: String) -> int:
	return 1 if EVOLUTIONS.has(id) or id == "patch" else UPGRADE_MOST


func evolution_ready(id: String) -> bool:
	"""Its two upgrades both at their most, and not yet taken."""
	if level(id) > 0:
		return false
	for part in UPGRADES[id]["evolves"]:
		if level(str(part)) < UPGRADE_MOST:
			return false
	return true


func crit_chance() -> float:
	return CRIT_CHANCE + CRIT_STEP * level("crit")


func double_chance() -> float:
	return DOUBLE_STEP * level("double")


func pull_chance() -> float:
	return PULL_STEP * level("pull")


func roll_offers() -> Array:
	"""Up to PICK_COUNT different cards: an evolution ready is always among
	them, and the patch while the gate is broken; the rest drawn at random
	from the upgrades short of their most (the patch while the gate is
	short of its own)."""
	var sure: Array = []
	for id in EVOLUTIONS:
		if evolution_ready(id):
			sure.append(id)
	if door <= 0.0 or breaches() > 0:
		sure.append("patch")
	var pool: Array = []
	for id in UPGRADE_ORDER:
		if sure.has(id):
			continue
		if id == "patch":
			if weakest() != -2:
				pool.append(id)
		elif level(id) < UPGRADE_MOST:
			pool.append(id)
	for i in range(pool.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var keep = pool[i]
		pool[i] = pool[j]
		pool[j] = keep
	return (sure + pool).slice(0, PICK_COUNT)


func reroll() -> bool:
	"""Three new cards, while there is a reroll left."""
	if state != State.PICK or rerolls <= 0:
		return false
	rerolls -= 1
	offers = roll_offers()
	return true


func offer_level_text(id: String) -> String:
	"""What a card says under its name: how many times it has been taken this
	run (the owner: "we only want to see how many times been upgraded"), or
	for the patch where the gate stands."""
	if id == "patch":
		var which: int = weakest()
		if which == -1:
			return "Gate broken" if door <= 0.0 else "Gate %d%% now" % roundi(door / maxf(1.0, door_most) * 100.0)
		if which >= 0:
			return "A breach to mend" if bool(stretches[which]["broken"]) \
				else "Wall %d%% now" % roundi(float(stretches[which]["health"]) / WALL_MOST * 100.0)
		return "All whole"
	if EVOLUTIONS.has(id):
		return "Evolution"
	return "Upgraded %d of %d" % [level(id), UPGRADE_MOST]


func pick(index: int) -> bool:
	"""Take offer `index`: its level up (or the gate patched), and the next
	wave comes AFTER_PICK_SECONDS later."""
	if state != State.PICK or index < 0 or index >= offers.size():
		return false
	var id: String = str(offers[index])
	if id == "patch":
		_repair(PATCH_SHARE)
		banner = "Repaired"
	elif EVOLUTIONS.has(id):
		levels[id] = 1
		banner = "%s!" % str(UPGRADES[id]["name"])
	else:
		levels[id] = level(id) + 1
		banner = "%s %d" % [str(UPGRADES[id]["name"]), level(id)]
	banner_left = BANNER_SECONDS
	picks_left = maxi(0, picks_left - 1)
	offers = roll_offers() if picks_left > 0 else []
	if offers.is_empty():
		picks_left = 0
		state = State.BETWEEN
		_left = AFTER_PICK_SECONDS
	return true


func time_text() -> String:
	var whole: int = int(run_seconds)
	@warning_ignore("integer_division")
	return "%d:%02d" % [whole / 60, whole % 60]


func result_text() -> String:
	return "The portal fell in wave %d.\n%s held - %d slain" % [wave, waves_words(waves_held), slain]


static func waves_words(count: int) -> String:
	return "1 wave" if count == 1 else "%d waves" % count


func measure_label() -> String:
	"""Where this minigame stands, for the readout's Measure (placemeasure.gd)."""
	return "The Mage's Stand - wave %d" % wave
