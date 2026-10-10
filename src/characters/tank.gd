# tank character — defensive frontliner with placeable aura damage.
# the tank's signature mechanic: a passive AoE damage aura (firering) that
# drains mana while active. press attack to toggle on/off. when mana runs
# out the aura auto-deactivates.
#
# class identity:
# - highest HP by far (the durability king), slowest mover, heavy frontline
# - mana powers the AOE aura instead of casts
# - aura is the ONLY attack — no direct strike, just radiating damage
# - defense climbs faster than other classes via skill_proficiency (see
#   SKILL PROFICIENCY below), through actually taking damage — not a flat
#   per-level bonus. CORRECTED: this comment used to claim a flat +2
#   defense on every character level-up, but no _apply_level_up_skill_bonus()
#   override for that was ever actually in this file — the comment
#   described intended design that was never coded. removed the claim
#   rather than add the bonus now, matching the same "proficiency
#   multiplier does this job, not a flat stack" decision made for
#   warrior/mage/healer.
#
# stat curve (recompute-from-level, set in _set_stat_curve):
#   HP   260 base / +22 per level   (steepest HP — earns it by standing in fire)
#   Mana 200 base / +10 per level   (aura uptime)
#   Stam 100 base / +5  per level
#
# physics_process override:
# tank fully overrides _physics_process for its lerp-based movement (smooth
# heavy-class feel), so nothing written inline in player.gd's loop runs here.
# The steps every class takes are player.gd functions this loop calls by name -
# _stamp_input(), _read_move_direction(), _sprint_tick(), _stop_sprint(),
# _accrue_agility_from_travel(), _tick_regen() and the `moved` signal. A copy
# of any of them goes stale: on day 1 the copied walk had none of the first
# five, and a tank was "away" three minutes after launch and never trained
# agility or defence again. _test_the_tank_loop_takes_every_step holds it.
#
# aura mechanics:
# - toggle on/off via attack button (spacebar)
# - drains mana_drain_cost mana every mana_drain_tick seconds
# - damages enemies in $aura collision area every aura_tick seconds
# - auto-deactivates when mana hits 0 OR tank dies
#
# NO ATTACK XP PER TICK. The aura used to add 2 attack XP per enemy per tick
# on this screen only; attack trains at the kill, on the server, and the bar
# shows that (Player.apply_server_attack()).
extends "res://src/characters/player.gd"

# This class's stat curve. See ClassData — hp_base and friends used to be
# literals in _set_stat_curve() below, which meant the server knew your level
# and your class and still could not work out your maximum health.
const CLASS_DATA := preload("res://data/classes/tank.tres")
# How fast this class walks, before agility and sprinting (player.gd). A
# constant so the exporter can read it: presence.py holds a character to it
# (gamedata.py, "COMBAT BOUNDS").
const CLASS_SPEED := 160


# =============================================================================
# AURA SETTINGS
# =============================================================================

# FOUR, NOT NINE. See mage.gd's note on damage_per_magic. 9 across a 0.25s
# tick was 36/s per enemy against the warrior's 24/s — and this number lands
# on EVERYTHING in range, so a tank in a pack of six was already dealing six
# times it. 4 gives 16/s per enemy, the 0.70x this class is aimed at, and the
# pack multiplier is what the tank is actually paid in.
@export var aura_damage: int = 4
@export var aura_tick: float = 0.25
@export var mana_drain_tick: float = 0.5
@export var mana_drain_cost: int = 2

# =============================================================================
# DYNAMITE SETTINGS
# =============================================================================
# THE DYNAMITE'S ATTACK - see dynamite.gd. Attack throws a lit stick where
# the tank aims, and since 0.14.0 the ring burns as well.
#
# THE OWNER, 0.14.0: "dynamite needs a bigger blast radios need to be able to
# throw faster and use tank ring i feel like 1 by its self is not enough to be
# impressive", and of all three mythics, "powerful but balanced i mean the
# odds of getting one might aswell pay for". So, against 0.13.0:
#
#   the blast       the meteor's size, 44 (dynamite.gd HIT_RADIUS; was 28)
#   a throw         every 0.75 s (dynamite_cooldown; was 1.0)
#   the ring        LIT BY THROWING: a throw lights it, or keeps it lit, and
#                   it goes out DYNAMITE_RING_LINGER seconds after the last
#                   one. It burns no mana of its own while it is lit that way
#                   - the throws pay for it (was: put out while Dynamite is
#                   worn)
#   the mana        3 a throw (was 4): at 0.75 s that is the ring's own 4 a
#                   second, so Dynamite costs what the ring costs
#   a stick         worth dynamite_stick_ticks ring ticks, 1.5 (was the
#                   cooldown's worth, 4): smaller, because there are more of
#                   them and the ring is burning too
#   every 5th throw a bundle: DYNAMITE_BUNDLE_STICKS sticks in a triangle,
#                   close enough that the first sets off the rest (until
#                   0.18.0 - see THE ROLL, below)
#
# WHAT THAT COMES TO, one target at level 22 with Ember-tier gear, by the
# Boss Sim's model (the site's bosssim.js): an Ember maul tank about 165 a
# second; Dynamite in 0.13.0 about 338; Dynamite now about 440 - the ring
# about half of it, and the bigger blast and the ring both reach more of a
# crowd than one target says.
#
# THE ROLL (0.18.0). The owner, setting one rule for all three mythics - a
# 10% roll and a rarer 1% one - and of this one, "dynamite is already getting a
# bonus from aoe of ring hmm / 10% chance to toss 3 dynamite / 1% chance to toss
# 5 sticks". So the every-fifth-throw bundle and the one-in-ten double are
# gone, and every throw rolls once:
#
#   1 in 100   a barrage: DYNAMITE_BARRAGE_STICKS (5) in a ring round the aim
#   1 in 10    a bundle: DYNAMITE_BUNDLE_STICKS (3) in a triangle round it
#   otherwise  one stick
#
# 1.24 sticks a throw on average where it was 1.48, so Dynamite comes down a
# little: by the Boss Sim's model, at level 22 in Ember gear with skills at 30,
# from about 523 a second to about 486, 7% - the ring is where its weight is.
# The most one throw can be is the barrage's five: the exporter writes the
# bundle's and the barrage's sticks and chances, and gamedata.combat_bounds()
# allows a throw the most of them.
const DYNAMITE_SCENE := preload("res://scene/projectiles/dynamite.tscn")

# The furthest a stick goes. A spot further than this is taken as the
# direction, and the stick lands here.
const DYNAMITE_MAX_THROW := 150.0

# Each stick of a throw of several leaves this much after the one before.
const DYNAMITE_SECOND_DELAY := 0.06

# THE BUNDLE: one throw in ten is DYNAMITE_BUNDLE_STICKS sticks, in a triangle
# DYNAMITE_BUNDLE_SPREAD from the aim (well inside each other's blast, so the
# middle is hit by all three, and inside CHAIN_RADIUS, so the first sets off
# the rest), each DYNAMITE_SECOND_DELAY behind the last.
const DYNAMITE_BUNDLE_CHANCE := 0.10
const DYNAMITE_BUNDLE_STICKS := 3
const DYNAMITE_BUNDLE_SPREAD := 14.0

# THE BARRAGE: one throw in a hundred is DYNAMITE_BARRAGE_STICKS sticks in a
# ring DYNAMITE_BARRAGE_SPREAD from the aim - wider, so it covers more ground,
# and still well inside CHAIN_RADIUS of its neighbours, so it goes up as one.
const DYNAMITE_BARRAGE_CHANCE := 0.01
const DYNAMITE_BARRAGE_STICKS := 5
const DYNAMITE_BARRAGE_SPREAD := 24.0

# The ring a throw lights stays lit this long after the last throw.
const DYNAMITE_RING_LINGER := 3.0

@export var dynamite_mana_cost: int = 3
@export var dynamite_cooldown: float = 0.75
# What a stick is worth, in ring ticks. The exporter writes it for the
# server's books (gamedata.combat_bounds()).
@export var dynamite_stick_ticks: float = 1.5

var _dynamite_cooldown_left: float = 0.0
# The two chances, as vars so a test can make a roll certain either way rather
# than throwing until the dice agree (as Player.double_cast_chance is).
var dynamite_bundle_chance: float = DYNAMITE_BUNDLE_CHANCE
var dynamite_barrage_chance: float = DYNAMITE_BARRAGE_CHANCE
# TRUE while the ring is lit by throwing rather than by the aura key: it
# burns no mana and goes out when _ring_linger_left runs out.
var ring_by_dynamite: bool = false
var _ring_linger_left: float = 0.0

# =============================================================================
# NODE REFERENCES
# =============================================================================
# Resolved once at _ready() instead of looked up by name every time they are
# touched. has_node("x") followed by $x walked the tree twice to answer one
# question, and tank did that on nine sites — two of them in _handle_moving()
# and _handle_idle(), which run EVERY FRAME, and one in _deal_aura_damage(),
# which runs four times a second for as long as the aura is up.
#
# get_node_or_null() rather than $x so a scene without the optional firering
# still loads; every use site checks for null exactly as the old has_node()
# guards did.
@onready var _sprite: AnimatedSprite2D = get_node_or_null("animatedsprite2d")
@onready var _aura: Area2D = get_node_or_null("aura")
@onready var _firering: AnimatedSprite2D = get_node_or_null("firering")


# =============================================================================
# AURA STATE
# =============================================================================

var aura_timer:       float = 0.0
var mana_drain_timer: float = 0.0
var aura_active: bool = false

# right-click edge detection moved to Player — see its ATTACK INPUT section.
# tank still needs its own _physics_process (it replaces the base loop rather
# than extending it), so it calls the inherited _poll_attack_pressed() below
# instead of keeping a private tracker.


# =============================================================================
# STAT CURVE
# =============================================================================

func _set_stat_curve() -> void:
	# tank: steepest HP curve in the game (frontline durability is the whole
	# kit), solid mana for aura uptime. called before recompute in player.gd.
	_apply_class_data(CLASS_DATA)


# =============================================================================
# SKILL PROFICIENCY  (NEW)
# =============================================================================

func _set_skill_proficiency() -> void:
	# tank's specialty: defense climbs 50% faster than any other class
	# taking the same damage. every class already gains SOME defense XP
	# from taking damage at all (see player.gd's take_damage(), which was
	# already universal before this system existed) — this is what keeps
	# tank true to its "durability king" identity on top of that. starting
	# value, tune to taste.
	skill_proficiency["defense"] = 1.5


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# class identity — always set, regardless of save state.
	character_name = "tank"
	speed = CLASS_SPEED

	# super._ready() calls _set_stat_curve(), loads save, recomputes maxes
	# from level, and fills resources to full. no manual stat block needed.
	super._ready()

	# preload the aura sprite but keep it hidden until aura activates
	if _firering != null:
		_firering.play("firering")
		_firering.visible = false


func _physics_process(delta: float) -> void:
	# Sampled FIRST, before every early return below, because the edge
	# detector has to see each frame — a click held through death or an attack
	# lockout must not read as a fresh press the instant that block lifts.
	# Tank replaces the base loop rather than extending it, so it calls the
	# inherited poll explicitly; every other class gets this from super().
	_stamp_input()
	var attack_pressed: bool = _poll_attack_pressed()
	# Space in a chat message is not the aura key. Discarded after the poll,
	# never instead of it - see player.gd's loop.
	if attack_pressed and _typing_in_ui():
		attack_pressed = false

	# block all input/movement during death sequence so the death animation
	# can play through without being overwritten by walk/idle animations.
	if is_dying:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_tick_aura(delta)
	_dynamite_cooldown_left = maxf(0.0, _dynamite_cooldown_left - delta)

	# attack lockout — frozen in place while attack animation plays
	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		_set_active()
		return

	# spacebar OR right-click toggles the aura — both land on attack_action(),
	# same as every other class.
	if attack_pressed:
		attack_action()
		return

	_handle_movement(delta)
	_tick_regen(delta)   # player.gd's, not a local copy


# =============================================================================
# AURA TICKING
# =============================================================================

func _tick_aura(delta: float) -> void:
	# runs every frame while the aura is active. handles both mana drain
	# and damage ticks, plus the auto-deactivate when mana hits 0.
	if not aura_active:
		return

	# active aura counts as "doing something" — reset idle timer so regen
	# doesn't kick in while the tank is actively damaging enemies
	_set_active()

	if ring_by_dynamite:
		# Lit by throwing: the throws paid for it, and it goes out a little
		# after the last one (DYNAMITE SETTINGS).
		_ring_linger_left -= delta
		if _ring_linger_left <= 0.0:
			_deactivate_aura()
			return
	else:
		# mana drain tick
		mana_drain_timer += delta
		if mana_drain_timer >= mana_drain_tick:
			mana_drain_timer = 0.0
			mana = clamp(mana - mana_drain_cost, 0, max_mana)
			if mana <= 0:
				_deactivate_aura()
				return

	# damage tick. hasten() applies agility — read per tick rather than cached,
	# because agility can go up mid-fight on a skill-up and the aura is the one
	# attack in the game that is already running when that happens.
	aura_timer += delta
	if aura_timer >= hasten(aura_tick):
		aura_timer = 0.0
		_deal_aura_damage()


# =============================================================================
# MOVEMENT (LERP, ON PLAYER.GD'S SHARED STEPS)
# =============================================================================

func _handle_movement(delta: float) -> void:
	# The same WASD as every class (nothing while typing); only the easing of
	# the velocity below is the tank's own.
	var direction: Vector2 = _read_move_direction()

	if direction != Vector2.ZERO:
		_handle_moving(direction, delta)
	else:
		_handle_idle()

	# THE SAME WADE AS EVERY OTHER CLASS, WIRED BY HAND.
	#
	# Tank replaces player.gd's _physics_process instead of extending it, so it
	# inherits these functions but not the call to them - anything added to the
	# base loop has to be repeated here or tank silently does without it. The
	# shove this replaced was never wired here at all, and tank's mask has
	# excluded the enemies layer since well before that, so tank has been
	# walking through enemies with no weight and no latch this entire time.
	var wading: Array[CharacterBody2D] = _enemies_overlapping()
	if not wading.is_empty():
		velocity *= _wade_drag_factor(wading.size())

	var position_before: Vector2 = global_position
	move_and_slide()
	_displace_wading_enemies(wading, delta)
	_accrue_agility_from_travel(global_position.distance_to(position_before))


func _handle_moving(direction: Vector2, delta: float) -> void:
	# moving counts as activity — reset regen timer
	_set_active()

	# sprint check — duplicated from player.gd because tank overrides
	# _physics_process entirely with its lerp-based movement
	var wants_sprint: bool = Input.is_action_pressed("sprint") and stamina > 0
	_is_sprinting = wants_sprint

	# compute target velocity, then lerp toward it for smooth heavy-class feel
	var base_speed:   float = speed + (agility - 1) * 10
	var actual_speed: float = base_speed * sprint_speed_multiplier if _is_sprinting else base_speed
	velocity = velocity.lerp(direction.normalized() * actual_speed, 0.3)

	# stamina out and agility XP in, the same as every class
	if _is_sprinting:
		_sprint_tick(delta)

	# animation + speed scale for sprint visual polish
	if _sprite != null:
		_sprite.play(get_walk_animation(direction))
		_sprite.speed_scale = sprint_speed_multiplier if _is_sprinting else 1.0

	last_direction = direction
	take_step()
	# The map uncovers on this signal (player.gd's _on_moved_for_map).
	moved.emit(global_position, str(last_direction))


func _handle_idle() -> void:
	# lerp velocity to zero for smooth stop (no sudden halt)
	velocity = velocity.lerp(Vector2.ZERO, 0.3)
	_stop_sprint()
	if _sprite != null:
		_sprite.play(get_idle_animation())
		_sprite.speed_scale = 1.0


# =============================================================================
# REGEN (DUPLICATED FROM PLAYER.GD)
# =============================================================================

# REGEN (REMOVED — INHERITED FROM PLAYER.GD)
# =============================================================================
# tank used to carry its own copy of _tick_regen(), from when it fully overrode
# _physics_process() and player.gd's regen therefore never ran. It called
# regen_rate and _regen_stats(), neither of which exists any more: player.gd's
# regen was rewritten to scale with each stat's maximum, because a flat rate of
# 1.0/second against a mana pool that grows by 16 a level meant a high-level
# mage waited minutes for a bar the game expected to refill in about one.
#
# Two copies of a rule is how that drift happens. There is one.


# =============================================================================
# ATTACK OVERRIDE — AURA TOGGLE
# =============================================================================

func attack_action() -> void:
	# OVERRIDE: tank's spacebar attack TOGGLES the aura on or off.
	# the tank has no direct strike — the aura IS the attack. Unless Dynamite is
	# equipped, when attack throws a stick, and the throw lights the ring.
	if equipped_weapon_attack() == ItemData.WeaponAttack.DYNAMITE:
		throw_dynamite(get_global_mouse_position())
		return
	if aura_active:
		_deactivate_aura()
	else:
		_activate_aura()


func _activate_aura() -> void:
	if mana <= 0:
		# show_notice() comes from player.gd, which this class extends —
		# no reference to look up, and the de-duplication there means
		# mashing the aura key with an empty bar shows one label, not forty.
		Audio.play("refused")
		show_notice("Not enough mana")
		return

	# toggling aura on counts as activity
	_set_active()

	# Below the mana guard — an aura that refused to start should not announce
	# itself. There is no matching id for switching it off; if that turns out
	# to want one, it is a new entry in audio.gd rather than a change here.
	Audio.play("aura_on")

	aura_active      = true
	ring_by_dynamite = false
	aura_timer       = 0.0
	mana_drain_timer = 0.0

	if _firering != null:
		_firering.visible = true
		_firering.play("firering")


func _deactivate_aura() -> void:
	aura_active = false
	ring_by_dynamite = false
	_ring_linger_left = 0.0
	if _firering != null:
		_firering.visible = false


# =============================================================================
# DYNAMITE
# =============================================================================

func throw_dynamite(aimed_at: Vector2) -> Array[Dynamite]:
	# One stick; or one throw in ten a bundle of three; or one in a hundred a
	# barrage of five (THE ROLL) - all for one price. Returns what was thrown
	# - empty when refused - for the tests.
	var thrown: Array[Dynamite] = []
	if _dynamite_cooldown_left > 0.0:
		return thrown
	if mana < dynamite_mana_cost:
		Audio.play("refused")
		show_notice("Not enough mana")
		return thrown

	_set_active()
	mana -= dynamite_mana_cost
	# hasten() applies agility, the same as the aura's tick and the mage's cast.
	_dynamite_cooldown_left = hasten(dynamite_cooldown)
	_light_ring_by_dynamite()
	Audio.play("dynamite_throw")

	var reach: Vector2 = aimed_at - global_position
	if reach.length() > DYNAMITE_MAX_THROW:
		reach = reach.normalized() * DYNAMITE_MAX_THROW
	var landing: Vector2 = global_position + reach
	# The line of the throw. A throw at the tank's own feet has none, so it is
	# taken as thrown to the right.
	var along: Vector2 = reach.normalized() if reach.length() > 0.5 else Vector2.RIGHT
	# The owner panel's "Always roll the 1%" (Player.rare_forced()) is the
	# barrage, and its "Always roll the 10%" (common_forced()) the bundle - the
	# rare one first, with both on, as the dice take it first.
	var count: int = sticks_for(randf(), dynamite_barrage_chance, dynamite_bundle_chance)
	if rare_forced():
		count = DYNAMITE_BARRAGE_STICKS
	elif common_forced():
		count = DYNAMITE_BUNDLE_STICKS
	if count == 1:
		thrown.append(_throw_stick(landing, 0.0))
		return thrown
	# A ring round the aim, one point toward the throw: a bundle's triangle or
	# a barrage's wider five.
	var spread: float = DYNAMITE_BARRAGE_SPREAD if count == DYNAMITE_BARRAGE_STICKS else DYNAMITE_BUNDLE_SPREAD
	for i in count:
		var at: Vector2 = landing + along.rotated(TAU * i / count) * spread
		thrown.append(_throw_stick(at, DYNAMITE_SECOND_DELAY * i))
	return thrown


static func sticks_for(roll: float, barrage_chance: float, bundle_chance: float) -> int:
	"""How many sticks a throw is, for a roll of randf(): the barrage's five
	for the lowest barrage_chance of rolls, the bundle's three for the next
	bundle_chance, one for the rest."""
	if roll < barrage_chance:
		return DYNAMITE_BARRAGE_STICKS
	if roll < barrage_chance + bundle_chance:
		return DYNAMITE_BUNDLE_STICKS
	return 1


func _light_ring_by_dynamite() -> void:
	# A throw lights the ring, or keeps it lit. A ring already lit by the aura
	# key cannot be here: putting Dynamite on puts that one out (_on_gear_changed).
	_ring_linger_left = DYNAMITE_RING_LINGER
	if aura_active:
		return
	Audio.play("aura_on")
	aura_active = true
	ring_by_dynamite = true
	aura_timer = 0.0
	mana_drain_timer = 0.0
	if _firering != null:
		_firering.visible = true
		_firering.play("firering")


func _throw_stick(landing: Vector2, delay: float) -> Dynamite:
	var stick: Dynamite = DYNAMITE_SCENE.instantiate()
	# A stick is worth dynamite_stick_ticks ring ticks - see DYNAMITE SETTINGS.
	# Rolled per stick: two sticks are two hits.
	stick.explosion_damage = roundi((aura_damage + weapon_damage_roll()) * get_damage_multiplier() * dynamite_stick_ticks)
	stick.caster = self
	stick.delay = delay
	spawn_parent().add_child(stick)
	stick.throw_from(global_position, landing)
	return stick


func _on_gear_changed() -> void:
	var dynamite: bool = equipped_weapon_attack() == ItemData.WeaponAttack.DYNAMITE
	# Dynamite put on while the aura key's ring is burning: it goes out,
	# because attack no longer reaches it to turn it off. The first throw
	# lights it again, the Dynamite's way.
	if aura_active and dynamite and not ring_by_dynamite:
		_deactivate_aura()
	# Dynamite taken off while its throws have the ring lit: out, or it would
	# burn on with nothing paying for it.
	if aura_active and ring_by_dynamite and not dynamite:
		_deactivate_aura()


func _deal_aura_damage() -> void:
	# damage all enemies currently inside the $aura collision area.
	#
	# This used to also emit GameState.aura_damage_dealt on every hit,
	# described as being "for analytics / multiplayer sync." Neither existed —
	# nothing connected to that signal, and it fired once per enemy per aura
	# tick into an empty bus, which is the most expensive place in this file to
	# do nothing. The emit went first; the declaration went with the rest of
	# that bus later (see the note at the top of gamestate.gd). When multiplayer
	# is real, the signal it needs should be designed around what listens.
	if _aura == null:
		return

	# Scaled by get_damage_multiplier(), the same shared function every class's
	# damage uses (see player.gd). It was a flat aura_damage constant with no
	# scaling at all, so the tank gained attack XP from every tick while that
	# skill never affected the tank's own output. Computed once outside the
	# loop: every enemy in range takes the same number, and the multiplier is
	# not recomputed per body.
	# NEW: THE EQUIPPED MAUL, ADDED TO THE AURA RATHER THAN REPLACING IT.
	#
	# A weapon's damage is one number and an aura tick is not one kind of hit —
	# this one lands four times a second on everything in range, which is why
	# aura_damage is 9 where the warrior's swing is 24. The maul ladder is
	# scaled to that: 8 at iron rather than the 24 it was authored with, so a
	# maul adds the same PROPORTION of the tank's damage that a sword adds of
	# the warrior's. Authored flat, an ember maul would have put 120 on a tick
	# that fires four times a second and made the tank do 968 dps to the
	# warrior's 233.
	#
	# ROLLED ONCE PER TICK AND SHARED, not once per enemy. A tick is a single
	# event that happens to touch several things — the whole ring pulses with
	# one value, and rolling per body would make a crowd look like static.
	var scaled_aura_damage: int = roundi(
		(aura_damage + weapon_damage_roll()) * get_damage_multiplier())

	# NO XP HERE - see the class comment. Attack trains at the kill, on the
	# server; this loop only hurts things.
	for body in _aura.get_overlapping_bodies():
		if not body.is_in_group("enemies"):
			continue
		if not body.has_method("take_damage"):
			continue
		body.take_damage(scaled_aura_damage)


# =============================================================================
# ANIMATION OVERRIDES
# =============================================================================

# get_walk_animation() and get_idle_animation() used to be overridden here with
# code CHARACTER FOR CHARACTER IDENTICAL to Player's. They are deleted rather
# than converted: an override that does exactly what it overrides is a place for
# the two to drift apart, and that already happened once in this file with the
# regen loop, whose own comment read "DUPLICATED FROM PLAYER.GD".
#
# get_attack_animation below is a real override - the tank has no attack
# animation and holds its idle pose - so it stays.
func get_attack_animation(_dir: Vector2) -> String:
	# tank has no direct attack — toggling the aura doesn't play an
	# attack animation. fall back to idle so the player sprite stays
	# in a clean state if attack_action ever calls this externally.
	return get_idle_animation()


func base_attack_damage() -> int:
	# See player.gd's base_attack_damage(). The aura's per-tick damage, which
	# lands on everything in range rather than on one target.
	return aura_damage


func attack_period() -> float:
	# The aura's tick, four times a second. See player.gd's attack_period()
	# for what reads this and why it is asked of the live character.
	#
	# The dps it produces is PER ENEMY IN RANGE, not total. A tank standing in
	# a pack of six is dealing six times the number the tooltip shows, which is
	# the tank's entire point and not something one figure can say.
	# hasten() applies agility, so this is the rate actually delivered.
	return hasten(aura_tick)


func _get_dir_string() -> String:
	# The cardinal matching last_direction, for hitflash animation lookup
	# (hitflashleft / right / up / down).
	return Facing.from_vec_total(last_direction)


# =============================================================================
# DAMAGE HANDLING OVERRIDE
# =============================================================================

func take_damage(amount: int, element: int = Element.Type.NONE) -> void:
	# wraps player.take_damage with tank-specific behavior:
	# - plays a directional hitflash animation if still alive
	# - deactivates the aura if the hit killed the tank
	var was_alive: bool = hp > 0
	super.take_damage(amount, element)

	# play tank-specific hitflash ONLY if still alive after the hit.
	# without this guard, hitflash would overwrite the death animation
	# that parent's _start_death_sequence just started playing.
	if _sprite != null and hp > 0 and not is_dying:
		_sprite.play("hitflash" + _get_dir_string())

	# deactivate aura if tank just died so it doesn't keep ticking damage
	# during the death animation
	if was_alive and hp <= 0:
		_deactivate_aura()


# =============================================================================
# PHASE 2 ABILITY STUB
# =============================================================================

# TRUE while an expand is running. See the note in activate_expand().
var _expanding: bool = false


func activate_expand() -> void:
	# 4-second sprite scale-up. costs 25 mana.
	#
	# NOTHING CALLS THIS YET - it is the Phase 2 stub. The two guards below are
	# here anyway, because the bug they prevent is invisible while the function
	# is unreachable and lands on whoever wires it up.
	#
	# FOUR SECONDS IS A LONG AWAIT ON A TANK. This is the class built to stand
	# in damage, so dying during the hold is the expected case, not the edge
	# one - and a death takes the scene with it. There is nothing in the log
	# when that happens: a coroutine whose node is gone is dropped silently, not
	# with an error. combat.gd has the measured table.
	#
	# Death is the harmless version, because the node and its 1.5 scale go
	# together. The case to actually think about when wiring this up is the one
	# the guard catches - alive, out of the tree - because the guard returns
	# BEFORE `_expanding = false`. Come back into the tree and the flag is still
	# true, so the `if _expanding: return` at the top rejects every future press
	# and the sprite stays at 1.5 forever. Whoever calls this first should decide
	# whether the restore belongs in a deferred/`tree_exiting` path instead; it
	# is left as-is rather than guessed at, since nothing calls it yet.
	#
	# AND IT MUST NOT OVERLAP ITSELF. Two presses inside four seconds used to
	# start two timers; the first to fire shrank the sprite while the second
	# hold was still paid for and supposedly running. The player loses the
	# ability they just spent 25 mana on.
	if _expanding:
		return
	if mana >= 25:
		_expanding = true
		mana = clamp(mana - 25, 0, max_mana)
		# RESTORE WHAT WAS THERE, NOT WHAT SOMEBODY ASSUMED WAS THERE.
		#
		# The shrink below used to write Vector2(1.0, 1.0) to both. The scene had
		# the root at 0.9 and the fire ring at 1.625 x 1.597, so the first expand
		# would have left the tank permanently resized and the ring a third
		# smaller - invisible only because nothing calls this yet.
		#
		# The root is 1.0 in the scene now (the 0.9 made the sprite ripple while
		# walking - see the commit that changed tank.tscn), which happens to make
		# the old root line right. The ring's would still have been wrong, and the
		# next person to tune either value in the editor would break it again.
		# Captured here, so neither number is written down twice.
		var root_scale_before: Vector2 = scale
		var ring_scale_before: Vector2 = _firering.scale if _firering != null else Vector2.ONE
		scale = Vector2(1.5, 1.5)
		if _firering != null:
			_firering.scale = Vector2(1.5, 1.5)
		await get_tree().create_timer(4.0).timeout
		# PAST AN AWAIT - same guard and same reason as fishingspot.gd and
		# characterhud.gd. Nothing below is safe on a node that has been freed.
		if not is_instance_valid(self) or not is_inside_tree():
			return
		_expanding = false
		scale = root_scale_before
		# is_instance_valid rather than a null check, uniquely here: this is the
		# far side of a four-second await, and a cached reference to a freed
		# node is non-null while has_node() would have returned false.
		if is_instance_valid(_firering):
			_firering.scale = ring_scale_before
