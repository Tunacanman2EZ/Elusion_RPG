# healer character — ranged spell spammer using mana as the cost resource.
# holds spacebar OR left-click to continuously fire projectiles toward cursor,
# and holds right-click to drop its healing aura (THE AURA, 0.40.0).
# each shot drains mana. stamina is reserved for the universal sprint system
# (shared across all classes via player.gd).
#
# class identity:
# - moderate HP (medium fragility), highest mana growth per level
# - mana = spell ammo (one shot per mana point at base cost)
# - cursor-aim projectile spam (10 shots/sec at base cooldown)
# - support archetype — fragile but sustained DPS through volume
#
# THE STAT CURVE IS NOT WRITTEN DOWN HERE ON PURPOSE. It lives in
# data/classes/healer.tres and nowhere else. It used to be listed here too,
# which is a second copy nobody can check against the first — the moment the
# .tres is retuned the comment is a lie that reads like documentation.
# CLASS_DATA below is the one source.
#
# combat model:
# - hold spacebar OR left-click to fire continuously (right-click until 0.40.0)
# - each shot fires toward CURRENT cursor position
# - moving the mouse during a burst creates a spray pattern (player skill)
# - projectile sprite is tinted via modulate (green by default) — set to
#   Color.WHITE in inspector once final attack art is delivered
#
# input model:
# - spacebar held: triggers fire on cooldown
# - left-click held: same as spacebar (alternative for mouse-focused play) -
#   started only by a click no window took (player.gd, left_click_attack_held())
# - right-click: the aura (THE AURA below), not the orbs, since 0.40.0
# - polled in _physics_process
# - attack_action() is overridden to NO-OP so spacebar press doesn't trigger
#   the parent's single-shot attack animation interrupting held-fire
extends "res://src/characters/player.gd"

# This class's stat curve. See ClassData — hp_base and friends used to be
# literals in _set_stat_curve() below, which meant the server knew your level
# and your class and still could not work out your maximum health.
const CLASS_DATA := preload("res://data/classes/healer.tres")
# How fast this class walks, before agility and sprinting (player.gd). A
# constant so the exporter can read it: presence.py holds a character to it
# (gamedata.py, "COMBAT BOUNDS").
const CLASS_SPEED := 140


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

@export var projectile_scene: PackedScene
@export var mana_cost_per_shot: int = 1
@export var shot_cooldown: float = 0.1
# THREE. Raised from two after playtesting. See mage.gd's note on
# damage_per_magic for the arithmetic: base over attack period is the dps
# floor, and at ten shots a second two was a 20/s floor that simply could not
# clear the early mobs at a pace that felt like playing — a 70 hp light slime
# took thirty-five hits, three and a half seconds of unbroken fire, on the most
# fragile class in the game while it paid a mana point every shot.
#
# Three is 30/s. That is ABOVE the warrior's 24/s on paper, and it is meant to
# be now: this used to be aimed at 0.80x the warrior on purpose, and that target
# is what the number could not survive contact with the actual enemy HP. The
# healer buys the lead back the way a glass cannon always does — it is the
# squishiest body in the game and it spends mana to shoot, so a burst that
# whiffs or drains the pool dry costs it the fight. One point of base is a big
# proportional step here (a 50% jump), which is why the knob is this coarse: the
# next stop up, four, is 40/s and a different class entirely.
@export var damage_per_magic: int = 3
@export var projectile_speed: float = 200.0
@export var projectile_tint: Color = Color(1.0, 1.0, 1.0, 1.0)

# THE FAN (0.36.0). The owner, of the healer's attack: keep the orb he paid for
# and mix in "the bullets from crypt" - the Field's glowing orbs - with their
# patterns too. Every FAN_EVERY-th shot also throws FAN_ORBS crypt-style orbs
# FAN_SPREAD_DEGREES either side of it (turretprojectile.gd, `fan`), straight
# like a crypt bullet, each for FAN_SHARE of the shot's damage and no mana of
# its own. Twice a second at the base rate: at most 20% more on one monster,
# if all three hit it - usually they fan out over a pack. The exporter writes
# all four into gamedata.json, and the server's books (gamedata.combat_bounds())
# allow for them.
const FAN_EVERY := 5
const FAN_ORBS := 2
const FAN_SHARE := 0.5
const FAN_SPREAD_DEGREES := 16.0

# THE DOUBLE (0.37.0). The owner: "add a 20% chance to deal dbl damage on 1
# main projectile", and "can make a diff color if needed". Each main orb rolls
# DOUBLE_HIT_CHANCE to hit for DOUBLE_HIT times its damage - the fan beside it
# never, it is figured from the shot before the roll - and a doubled orb is
# gold (turretprojectile.gd). The owner panel's "Always roll the 10%" makes
# every orb one (Player.common_forced(), the common roll every class has).
# Exported, and the server's books take the worst of it: every orb doubled.
const DOUBLE_HIT_CHANCE := 0.2
const DOUBLE_HIT := 2
# A var as well, so a test can make the roll certain either way, as
# Player.double_cast_chance is.
var double_hit_chance: float = DOUBLE_HIT_CHANCE

# THE AURA (0.40.0). The owner sent the art for the healer's heal - "the
# character will not be there but will turn into an aoe" - and asked for it on
# right-click, the attacks on "left click" (Space still attacks too). It was
# first dropped by HOLDING right-click a moment, and the owner: "i right click
# and hold takes like 5 seconds should just be right click" - a hold that
# waited out the cooldown or the mana and then dropped it, with nothing to say
# why. So a right-click drops it at once, at the cursor, no further than
# AURA_RANGE from the healer - a HealAura (healaura.gd): it heals every player
# standing in it, the healer too, sends the ones near it its blobs, and burns
# the monsters in it, each tick for AURA_DAMAGE_SHARE of an orb. It costs
# AURA_MANA_COST and comes back after AURA_COOLDOWN; a right-click before then
# drops nothing and says why over the healer (aura_refusal()). Everyone in the
# area sees it ("heal"), and it heals them if they stand in it; the presence
# server writes those heals down for the server's healing check (presence.py).
# The exporter writes the numbers, and the server's books allow for the burn.
const AURA_COOLDOWN := 8.0
const AURA_MANA_COST := 25
const AURA_RANGE := 160.0
const AURA_DAMAGE_SHARE := 2.0


# A cursor delta shorter than this counts as "no direction at all" — see
# _get_direction_to_cursor(). Compared against length_squared() so the check
# costs no sqrt on a path that runs ten times a second: this is 0.001 squared,
# the same threshold warrior uses for the same question.
const AIM_EPSILON_SQUARED: float = 0.000001

# WHERE THE STREAM LEAVES FROM, AND WHERE IT IS AIMED FROM (0.26.0): the middle
# of the healer's picture, 16 px above its feet - its sprite is drawn 15 above
# the node, and the hurtbox sits at 16 - rather than the node's origin, which
# is the feet. The owner, 12 Oct: auto fire "is broken between flipping from
# left auto fire to top left and right to top right where as bottom
# directionals are fine". From the feet, a cursor level with the healer's
# chest was 10 to 20 degrees UP, and a stream aimed up and across left the
# feet and crossed the healer's own body on its way out; aimed down, it left
# from below the body and looked right. Aimed and fired from the middle, the
# stream leaves where the player is looking from in every direction.
const AIM_FROM := Vector2(0.0, -16.0)


# =============================================================================
# STATE
# =============================================================================

var _shot_timer: float = 0.0
# Shots since the healer was made, for THE FAN.
var _shots: int = 0
# THE AURA: the cooldown still to run, and whether right-click was down last
# frame (a click is the frame it goes down).
var aura_cooldown_left: float = 0.0
var _right_was_down: bool = false


# _is_firing USED TO LIVE HERE. It was assigned true on every shot and false on
# every frame between shots, and read by absolutely nothing — not by this file,
# not by player.gd, not by the HUD. Deleted rather than left as a hook for a
# future feature: a variable that is maintained but never consulted looks
# exactly like one that is load-bearing, right up until someone deletes the
# wrong one.


# =============================================================================
# STAT CURVE
# =============================================================================

func _set_stat_curve() -> void:
	# healer: fragile but above the mage's floor, deep mana for sustained
	# projectile spam. called before recompute in player.gd.
	_apply_class_data(CLASS_DATA)


# =============================================================================
# SKILL PROFICIENCY
# =============================================================================

func _set_skill_proficiency() -> void:
	# healer's specialty: magic climbs 50% faster than any other class
	# landing the same shots. The server applies it to what /api/skill/train
	# is told (its own SKILL_PROFICIENCY). Attack trains only at the kill, at
	# the base rate for this class.
	#
	# This replaced a flat +1 magic granted on every character level-up, which
	# paid out however the level was earned. This only pays for landed shots.
	skill_proficiency["magic"] = 1.5


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# class identity — always set, regardless of save state.
	character_name = "healer"
	speed = CLASS_SPEED

	# super._ready() calls _set_stat_curve(), loads save, recomputes maxes
	# from level, and fills resources to full. no manual stat block needed.
	super._ready()

	_add_aim_ring()


func aim_ring_feet() -> Vector2:
	# The aim ring (player.gd): the healer's feet are its origin, a pixel in.
	return Vector2(-1.0, -1.0)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)

	if is_dying:
		_point_aim_ring(last_direction)
		return

	if _shot_timer > 0.0:
		_shot_timer -= delta

	_point_aim_ring(_get_direction_to_cursor())
	_aura_click(delta, right_click_held(), aim_point())

	if _can_fire():
		_fire_projectile()
		# hasten() applies agility. At ten shots a second the base cooldown is
		# already 0.1, so this is the class where the multiplier does the most
		# in absolute terms — and the one where forgetting it would be least
		# visible, because a shot every 0.05s and one every 0.1s both read as
		# "a stream".
		_shot_timer = hasten(shot_cooldown)


# =============================================================================
# FIRE GATING
# =============================================================================

func _can_fire() -> bool:
	if not _is_attack_input_held():
		return false
	if _shot_timer > 0.0:
		return false
	if mana < mana_cost_per_shot:
		return false
	return true


func _is_attack_input_held() -> bool:
	# healer fires continuously while the input is HELD, so this stays a hold
	# check rather than the edge-detected _poll_attack_pressed() every other
	# class uses. The mouse half is LEFT-click since 0.40.0, as it is for every
	# class (player.gd's left_click_attack_held(): only a click no window took
	# starts it, so a click on the bag or the chat must not drain the mana) -
	# right-click drops THE AURA.
	return Input.is_action_pressed("attack") or left_click_attack_held()


# =============================================================================
# THE AURA (0.40.0) - see the constants
# =============================================================================

func aura_point(cursor: Vector2) -> Vector2:
	"""Where an aura dropped now would go: the cursor, no further than
	AURA_RANGE from the healer."""
	var reach: Vector2 = cursor - global_position
	if reach.length() > AURA_RANGE:
		reach = reach.normalized() * AURA_RANGE
	return global_position + reach


func aura_ready() -> bool:
	return aura_cooldown_left <= 0.0 and mana >= AURA_MANA_COST and not is_dying


func aura_refusal() -> String:
	"""Why a right-click now would drop nothing, in words for over the healer
	- or "" when it would drop."""
	if is_dying:
		return ""
	if aura_cooldown_left > 0.0:
		return "Aura ready in %ds" % ceili(aura_cooldown_left)
	if mana < AURA_MANA_COST:
		return "Not enough mana"
	return ""


func _aura_click(delta: float, down: bool, cursor: Vector2) -> HealAura:
	"""One frame of right-click: the frame it goes down, the aura at the
	cursor if it is ready, or why not. Holding it does nothing more."""
	aura_cooldown_left = maxf(aura_cooldown_left - delta, 0.0)
	var clicked: bool = down and not _right_was_down
	_right_was_down = down
	if not clicked:
		return null
	if aura_ready():
		return drop_aura(aura_point(cursor))
	if is_inside_tree():
		show_notice(aura_refusal())
	return null


func drop_aura(at: Vector2) -> HealAura:
	"""THE AURA, at `at`: the mana, the cooldown, the ring, and the word to
	everyone else in the area."""
	_set_active()
	mana -= AURA_MANA_COST
	aura_cooldown_left = AURA_COOLDOWN
	Audio.play("spell_cast")
	var toward: Vector2 = aim_direction_to(at)
	last_direction = toward
	_play_cast_animation(toward)
	_aim_ring_fired()
	var orb_hit: int = roundi((damage_per_magic + weapon_damage_roll()) * get_damage_multiplier())
	var parent: Node = get_tree().current_scene if is_inside_tree() else get_parent()
	var aura: HealAura = HealAura.drop(parent, at, maxi(1, roundi(orb_hit * AURA_DAMAGE_SHARE)))
	Presence.tell_attack("heal", global_position, at)
	return aura


# =============================================================================
# ATTACK ACTION OVERRIDE
# =============================================================================

func base_attack_damage() -> int:
	# See player.gd's base_attack_damage(). Three, which is small because this
	# fires ten times a second — the number only means anything next to
	# attack_period() below.
	return damage_per_magic


func attack_period() -> float:
	# Ten shots a second. See player.gd's attack_period() for what reads this.
	#
	# This is the class the whole dps row exists for: a scepter's damage number
	# is tiny — 3 at iron, 13 at ember — precisely BECAUSE of this 0.1, and a
	# player comparing it to a 100-damage sword without the division would
	# reasonably conclude the healer had been abandoned.
	# hasten() applies agility, so this is the rate actually delivered.
	return hasten(shot_cooldown)


func attack_action() -> void:
	# NOTHING: the healer's attack is the stream of orbs (_physics_process,
	# _is_attack_input_held()). Without this the base swing ran on every click
	# and Space - a sword's swoosh, and "Player: missing animation
	# 'attackright' - attack canceled" - which is what 0.40.0 shipped, this
	# block lost in the aura's rewrite (the owner's log, 0.40.1).
	return


# =============================================================================
# PROJECTILE FIRING
# =============================================================================

func _fire_projectile() -> void:
	if projectile_scene == null:
		push_warning("Healer: projectile_scene not assigned in inspector")
		return

	_set_active()

	# The healer's attack IS the projectile, so this is the cast rather than a
	# swing. Below the projectile_scene guard above, which returns on a
	# misconfigured inspector.
	Audio.play("spell_cast")

	mana -= mana_cost_per_shot

	var direction: Vector2 = _get_direction_to_cursor()
	last_direction = direction

	_shots += 1
	_play_cast_animation(direction)
	_spawn_projectile(direction, fans_on(_shots))
	_aim_ring_fired()
	# Motes where the orb leaves (castsparkle.gd, 0.36.0).
	CastSparkle.muzzle(self, AIM_FROM, aim_origin() + direction * RemoteAttacks.AIM_AHEAD)


func rolls_double_hit() -> bool:
	"""Whether the next main orb is THE DOUBLE."""
	return common_forced() or randf() < double_hit_chance


static func fans_on(shot: int) -> bool:
	"""Whether shot number `shot` (the first is 1) throws the fan."""
	return shot > 0 and shot % FAN_EVERY == 0


static func fan_directions(direction: Vector2) -> Array[Vector2]:
	"""The fan's orbs' ways, FAN_SPREAD_DEGREES either side of `direction`."""
	var out: Array[Vector2] = []
	for i in FAN_ORBS:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var step: float = float(i >> 1) + 1.0
		out.append(direction.rotated(deg_to_rad(FAN_SPREAD_DEGREES * step * side)))
	return out


func _get_direction_to_cursor() -> Vector2:
	# ALWAYS A REAL DIRECTION. Vector2.normalized() on a zero-length vector
	# returns Vector2.ZERO, not an error — and the cursor sitting exactly on the
	# character makes it zero-length.
	#
	# That fed two things at once. last_direction went to ZERO, which is what
	# every idle and walk animation lookup reads, and the projectile was handed
	# direction = ZERO, so it spawned and then sat perfectly still until its
	# lifetime ran out. At ten shots a second that is a growing pile of
	# motionless orbs on top of the player. Falling back to the last real facing
	# fires the shot the way the player is already looking, which is the only
	# answer that isn't a guess.
	return aim_direction_to(aim_point())


func aim_origin() -> Vector2:
	"""Where a shot leaves from and is aimed from: the middle of the body (see
	AIM_FROM)."""
	return global_position + AIM_FROM


func aim_direction_to(point: Vector2) -> Vector2:
	"""The way a shot at `point` goes - the cursor, for a real shot, and the
	same answer the aim ring shows."""
	var to_point: Vector2 = point - aim_origin()
	if to_point.length_squared() <= AIM_EPSILON_SQUARED:
		return last_direction
	return to_point.normalized()


func _play_cast_animation(direction: Vector2) -> void:
	# get_node_or_null() rather than has_node() then $node, which walked the
	# same path twice to answer one question. sprite_frames is checked too:
	# has_animation() on a null SpriteFrames is a crash, not a false.
	var sprite: AnimatedSprite2D = get_node_or_null("animatedsprite2d")
	if sprite == null or sprite.sprite_frames == null:
		return

	var anim_name: String = "attack" + _direction_to_string(direction)
	if sprite.sprite_frames.has_animation(anim_name):
		sprite.play(anim_name)


func _spawn_projectile(direction: Vector2, fanned: bool = false) -> void:
	var projectile: Node = projectile_scene.instantiate()
	# THE DOUBLE, rolled before add_child(): the orb's _ready() dresses it gold.
	var doubled: bool = rolls_double_hit()
	if "doubled" in projectile:
		projectile.set("doubled", doubled)
	get_tree().current_scene.add_child(projectile)

	projectile.global_position = aim_origin()

	# THE ONLY SPAWNER IN THE PROJECT THAT WAS MISSING THIS. mage.gd, warrior.gd,
	# pet.gd, petcontroller.gd, baseenemy.gd, bossenemy.gd, bushmage.gd,
	# poisonslime.gd, poisonprojectile.gd, combat.gd and teleporter.gd all call
	# it; healer.gd did not.
	#
	# The project runs common/physics_interpolation, so the renderer draws every
	# node blended between its previous and current physics transforms. A node
	# that has just entered the tree has no meaningful previous transform, so its
	# first rendered frame is a blend from the scene origin toward wherever it
	# was just placed — the shot visibly smears in from off-screen instead of
	# leaving the staff. mage.gd's _spawn_stalagmite() has the long-form version
	# of this explanation.
	#
	# It MUST come after global_position is set, never before.
	projectile.reset_physics_interpolation()

	projectile.modulate = projectile_tint

	if "direction" in projectile:
		projectile.direction = direction
	if "speed" in projectile:
		projectile.speed = projectile_speed
	if "damage" in projectile:
		# damage_per_magic is a flat base scaled by get_damage_multiplier(),
		# which folds in both magic and attack and is shared across every class
		# (see player.gd). It was magic * damage_per_magic — the same
		# reinterpretation mage's stalagmite went through.
		#
		# NEW: THE EQUIPPED SCEPTER, ADDED RATHER THAN SUBSTITUTED. The scepter
		# ladder is small on purpose — 3 at iron, 13 at ember — because this
		# fires ten times a second. A scepter carrying the sword's 20 would
		# have given the healer 170 dps at tier 1 and 1,370 at ember, against a
		# warrior's 233. It adds the same PROPORTION of the healer's own damage
		# that a sword adds of the warrior's; the dps it buys is identical.
		#
		# roundi rather than int matters most here. A base of 3 truncated at a
		# 1.16 multiplier is still 3 — the healer was the class paying most for
		# a rounding mode nobody chose.
		projectile.damage = roundi(
			(damage_per_magic + weapon_damage_roll()) * get_damage_multiplier())
	if "owner_group" in projectile:
		projectile.owner_group = "player"
	# Identifies the healer for the projectile's XP-on-hit — same
	# pattern as slashwave.gd's caster reference for warrior, and mage's
	# equivalent addition to _spawn_stalagmite(). lets the projectile grant
	# attack XP (universal) AND magic XP (healer's boosted specialty) back
	# to whoever fired it, on impact. the projectile script itself still
	# needs its own matching XP-grant call added — that part isn't done
	# here, since it lives in projectile_scene's own script, not this one.
	if "caster" in projectile:
		projectile.caster = self
	if "damage" in projectile:
		# The fan from the shot as rolled, then the double on the main orb alone.
		var shot_damage: int = int(projectile.damage)
		if fanned:
			_spawn_fan(direction, shot_damage)
		if doubled:
			projectile.damage = shot_damage * DOUBLE_HIT
	# A picture of it for everyone else in the area (0.19.0, remoteattacks.gd),
	# with the fan when it has one (0.36.0) and gold when it doubled (0.37.0).
	Presence.tell_attack("orb", aim_origin(), aim_origin() + direction * RemoteAttacks.AIM_AHEAD, 0.0,
		(RemoteAttacks.FLAG_FAN if fanned else 0) | (RemoteAttacks.FLAG_DOUBLE if doubled else 0))


func _spawn_fan(direction: Vector2, shot_damage: int) -> Array[Node]:
	"""THE FAN's orbs beside a shot that did `shot_damage`. Returned for the
	tests."""
	var made: Array[Node] = []
	for way in fan_directions(direction):
		var orb: Node2D = projectile_scene.instantiate() as Node2D
		# Before add_child(): _ready() reads it, to fly straight and look like a
		# crypt bullet.
		orb.set("fan", true)
		orb.set("direction", way)
		orb.set("speed", projectile_speed)
		orb.set("damage", maxi(1, roundi(shot_damage * FAN_SHARE)))
		orb.set("owner_group", "player")
		orb.set("caster", self)
		get_tree().current_scene.add_child(orb)
		orb.global_position = aim_origin()
		orb.reset_physics_interpolation()
		orb.modulate = projectile_tint
		made.append(orb)
	return made


# =============================================================================
# HELPERS
# =============================================================================

func _direction_to_string(dir: Vector2) -> String:
	return Facing.from_vec_total(dir)
