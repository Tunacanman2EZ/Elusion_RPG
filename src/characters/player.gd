# player.gd base player class — inherited by warrior, mage, healer, and tank.
# handles movement, animation, combat, leveling, currency, the death/revive
# sequence including hit flash and game over transition, universal regen,
# AND universal sprint.
#
# stat recompute architecture:
# - max HP / mana / stamina are PURE FUNCTIONS of level via _recompute_max_stats()
# - each subclass sets its six stat constants in _set_stat_curve() before super._ready()
# - on load AND level-up: recompute maxes, then refill current to max
# - skill stats accumulate from skill XP + level-up bonuses (not recomputed)
#
# level-up feedback (NEW):
# - character level-up spawns a big gold "LEVEL UP!\n{level}" floating popup
# - each skill level-up spawns a smaller cyan "{Skill} {level}" popup
# - defense displays as "Defence" (c) per design; code stays "defense" (s)
#
# currency / regen / sprint / feedback architecture: see inline sections.
extends CharacterBody2D


# =============================================================================
# CONSTANTS
# =============================================================================

const FLOATING_LABEL_SCENE := preload("res://scene/ui/floatinglabel.tscn")

# FloatingLabel.Type.NOTICE. Written as a bare int because floatinglabel.gd
# has no class_name, so its enum is not reachable by name from here — the
# existing popup calls in this file pass a literal 3 for LEVELUP for the same
# reason. Named here so there is exactly one place to change if the enum
# order ever shifts (floatinglabel.gd's comment says to append, not insert).
const NOTICE_LABEL_TYPE: int = 5

# how long an IDENTICAL notice is suppressed for, in milliseconds.
const NOTICE_REPEAT_COOLDOWN_MS: int = 750

const SKILL_DISPLAY_NAMES := {
	"attack":  "Attack",
	"defense": "Defence",
	"agility": "Agility",
	"magic":   "Magic",
	"fishing": "Fishing",
	"cooking": "Cooking",
}


# =============================================================================
# IDENTITY
# =============================================================================

var character_name := "player"


# =============================================================================
# LEVEL AND XP
# =============================================================================

# NEW: setter added so max_hp/mana/stamina recompute whenever level changes
# by ANY means — not just the natural level_up() flow below, but also
# typing a new value directly into the Remote Inspector while the game is
# running (e.g. testing "what does level 50 feel like against this boss")
# or a debug key setting it directly. previously max stats only
# recomputed at _ready() and inside level_up() — manually editing level
# any other way left max_hp/mana/stamina stale at whatever they were
# before, not matching the new level at all. runs _recompute_max_stats()
# during the class's own initial declaration too, before _set_stat_curve()
# has set this class's real hp_base/hp_per_lvl/etc — harmless, since
# _ready() calls both again right after in the correct order regardless.
var level: int = 1:
	set(value):
		level = value
		_recompute_max_stats()
		_fill_all_resources()
var xp: int = 0
var xp_next: int = 100


# =============================================================================
# STAT CURVE CONSTANTS
# =============================================================================

var hp_base:    int = 20
var hp_per_lvl: int = 0

var mana_base:    int = 0
var mana_per_lvl: int = 0

var stam_base:    int = 100
var stam_per_lvl: int = 0


# =============================================================================
# CORE STATS
# =============================================================================

var max_hp: int = 20
var hp: int = 20

var max_mana: int = 0
var mana: int = 0

var max_stamina: int = 100
var stamina: int = 100


# =============================================================================
# CURRENCY
# =============================================================================

var gold: int = 0

var lusions: int:
	get:
		return CharacterData.get_account_lusions()
	set(value):
		CharacterData.set_account_lusions(value)


# =============================================================================
# SKILLS
# =============================================================================

var attack: int = 1;   var attack_xp: int = 0;   var attack_xp_next: int = 100
var defense: int = 1;  var defense_xp: int = 0;  var defense_xp_next: int = 100
var agility: int = 1;  var agility_xp: int = 0;  var agility_xp_next: int = 100
var magic: int = 1;    var magic_xp: int = 0;    var magic_xp_next: int = 100
var fishing: int = 1;  var fishing_xp: int = 0;  var fishing_xp_next: int = 100
var cooking: int = 1;  var cooking_xp: int = 0;  var cooking_xp_next: int = 100


# =============================================================================
# MOVEMENT
# =============================================================================

# WAS 75, WHICH WAS SLOWER THAN SIX OF THE SEVEN ENEMIES.
#
# Enemy move speeds run 45 (large poison slime) to 90 (electric sprite), with
# most between 75 and 85. At 75 the player could never break contact with
# anything but the large slime, so every fight was stand-and-trade or spend
# stamina — no repositioning, no kiting, no backing off to heal. For a game
# with a 110 HP mage that is not a difficulty choice, it is a missing verb.
#
# 90 is parity with the fastest thing in the game and above the other six. The
# electric sprite keeps its identity as the one enemy that can run you down;
# everything else can be walked away from.
#
# The real speed is this plus (agility - 1) * 10. That term used to be
# decorative — see the agility block in _handle_movement() for why.
@export var speed := 90
var last_direction := Vector2.DOWN
var is_attacking := false

# NEW: whether entering is_attacking freezes movement. defaults to true so
# mage/tank/healer keep their existing behavior untouched. warrior sets this
# to false in its own _ready() so it can keep walking during its swing —
# melee classes with cursor-aim attacks don't need the WASD-lock that made
# sense for the old fixed-4-direction swing.
@export var attack_locks_movement: bool = true

# HOW HARD THE PLAYER SHOVES AN ENEMY IT WALKS INTO.
#
# Enemies are solid to us but we are not solid to them (no enemy masks the
# player layer), so without a shove an enemy that presses into you pins you
# with no way out.
#
# THIS USED TO BE A FLAT 50 px/sec, AND THE OLD COMMENT SAID TO KEEP IT BELOW
# `speed` so an enemy "yields more slowly than you walk". That is the wrong
# comparison, and it is why the shove never worked. The number a shove
# competes against is not how fast the PLAYER walks — it is how fast the ENEMY
# walks back in. At 50 against chase speeds of 70 to 90, the shove lost to
# every enemy in the game except the large poison slime, which is the one that
# felt fine. Being pushed at 50 while pathing at 80 is a net 30 px/sec toward
# you, forever.
#
# So the push is derived from the enemy's own move speed instead of being a
# constant. A ratio above 1.0 always wins, and it keeps winning for any enemy
# added later without anyone remembering to retune a magic number.
@export var enemy_push_ratio: float = 1.6

# Floor for anything that does not report a get_move_speed() — a prop, a
# scripted body, a future enemy that moves some other way. 0.0 for both this
# and the ratio disables shoving entirely and restores the old pinning.
@export var enemy_push_strength: float = 50.0

# HOW MUCH OF THE SHOVE GOES SIDEWAYS, as a fraction of the straight-away push.
#
# -collision.get_normal() points directly away from the contact, which for a
# head-on walk is exactly your travel direction — so even a shove that wins
# just pushes the enemy ahead of you like a box, and you never get PAST it.
# A tangential component makes it slip to one side instead.
@export var enemy_push_sidestep: float = 0.6


# =============================================================================
# SPRINT
# =============================================================================

@export var sprint_speed_multiplier: float = 2.0
@export var sprint_stamina_drain_per_sec: float = 15.0
# NEW: agility XP granted per second of actual sprinting. universal here
# (not warrior-specific) since sprinting itself is shared base-class
# movement, not tied to any one class's kit.
@export var sprint_agility_xp_per_sec: float = 1.0

# AGILITY XP FOR ORDINARY MOVEMENT, per 1000 pixels travelled.
#
# Sprinting was the ONLY source of agility XP in the whole codebase, and
# agility 2 costs 100 XP at 1 XP/sec. With a warrior's 80 stamina draining at
# 15/sec, one full bar buys 5.3 seconds of sprint — so a single agility level
# was about nineteen complete stamina bars of pure running, and a mage's 40
# stamina made it thirty-eight. Nobody was ever going to do that.
#
# Which meant (agility - 1) * 10 was permanently zero and the player's real
# speed was the base, forever. The stat existed, was displayed, was saved, and
# did nothing.
#
# At 90 px/sec this is roughly one point every eleven seconds of walking —
# slow enough to still be a reward, fast enough to actually arrive. Sprinting
# earns this AND the per-second rate above, which is the right shape: running
# hard should train running.
@export var agility_xp_per_1000_px: int = 3

var _sprint_drain_accumulator: float = 0.0
var _sprint_agility_xp_accumulator: float = 0.0

# Banked in pixels, spent in thousands. Batched rather than awarded per frame
# because gain_agility_xp() calls save_character_state() every time — a
# per-frame award would be a save every frame.
var _agility_distance_accumulator: float = 0.0
var _is_sprinting: bool = false


# =============================================================================
# REGEN
# =============================================================================

# CHANGED: regen is a PERCENTAGE of each stat's own maximum per second, not a
# flat points-per-second.
#
# WHY: regen_rate was a flat 1.0 while mana_per_lvl adds 16 every level. At
# level 22 the mage had 586 max mana and recovered one point a second — nine
# minutes and forty-six seconds for a full bar, and worse every single level
# after. The pool kept growing; the tap never widened. A flat rate means the
# game gets slower the longer you play it, which is the opposite of what
# levelling is supposed to feel like.
#
# As a percentage, time-to-full is CONSTANT at every level: a level 1 mage and
# a level 50 mage both fill in the same wall-clock time.
#
# 0.0167 ≈ 1/60, so empty to full is about a minute.
@export var regen_percent_per_second: float = 0.0167

# Floor for small pools. Set to the old flat rate, so nothing in the game
# regenerates any slower than it did before this change — only faster.
@export var regen_minimum_per_second: float = 1.0

@export var idle_threshold: float = 1.0

var _idle_timer: float = 0.0

# One accumulator PER STAT, because they have different maximums and therefore
# different rates. A single shared counter can only ever hand the same number
# of points to a 586-mana pool and a 100-stamina pool, which is precisely the
# flat-rate problem in miniature.
#
# They exist because regen is fractional per frame: at 9.8/sec and 80 ticks a
# second each tick earns 0.12 of a point. Accumulating and spending whole
# points keeps hp/mana/stamina as integers without rounding the regen away.
var _regen_hp_accumulator: float = 0.0
var _regen_mana_accumulator: float = 0.0
var _regen_stamina_accumulator: float = 0.0


# =============================================================================
# DEATH AND REVIVE
# =============================================================================

var has_active_revive: bool = false
var is_dying: bool = false

@export var hit_flash_duration: float = 0.15
var _default_modulate: Color = Color.WHITE


# =============================================================================
# INVENTORY
# =============================================================================

var inventory_data: Array = []
var hotbar_assignments: Array = ["", "", "", "", "", "", "", "", ""]

# NEW: which pet (an item_id, e.g. "petsniper") is currently active, if
# any. "" means no active pet. a String, not a node reference — nodes
# don't survive scene changes, this does, since it's handled specially in
# CharacterData.gd's save/load (parallel to hotbar_assignments above,
# outside the int-only SAVEABLE_STATS loop).
var active_pet_id: String = ""


# =============================================================================
# UI REFERENCES
# =============================================================================

var gold_label: Label = null
var lusions_label: Label = null


# =============================================================================
# SIGNALS
# =============================================================================

signal took_damage(amount: int, type: String)
signal died()
signal xp_gained_signal(amount: int)
signal gold_changed_signal(amount: int)
signal lusions_changed_signal(amount: int)
signal moved(position: Vector2, direction: String)


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	add_to_group("player")

	_set_stat_curve()
	_set_skill_proficiency()
	CharacterData.load_character_state(self)
	_recompute_max_stats()
	_fill_all_resources()

	# NEW: re-spawn the active pet (if any) on every scene load — this is
	# what actually makes a pet survive a scene transition, since the old
	# pet node itself gets freed along with the rest of the old scene.
	# active_pet_id is just a string (an item_id), not a node reference,
	# which is exactly why it CAN survive — see CharacterData.gd's
	# save_character_state()/load_character_state() for where it persists.
	_restore_active_pet()

	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("idledown")
		if not $animatedsprite2d.animation_finished.is_connected(_on_animatedsprite2d_animation_finished):
			$animatedsprite2d.animation_finished.connect(_on_animatedsprite2d_animation_finished)


func _physics_process(_delta):
	# Sampled FIRST, before any early return below, because the right-click
	# edge detector has to see every frame. If it only ran when the player was
	# alive and idle, a click held through a death or an attack lockout would
	# look like a fresh press the instant that block lifted. Every class used
	# to carry its own copy of this comment and its own copy of the tracker.
	var attack_pressed: bool = _poll_attack_pressed()

	if is_dying:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# CHANGED: only freeze movement during an attack if this class opts into
	# it (attack_locks_movement). warrior sets this false so it can walk
	# while swinging; mage/tank/healer keep the old frozen behavior.
	if is_attacking and attack_locks_movement:
		velocity = Vector2.ZERO
		move_and_slide()
		_set_active()
		return

	if attack_pressed:
		attack_action()
		return

	var direction := Vector2.ZERO
	if Input.is_action_pressed("move_right"): direction.x += 1
	if Input.is_action_pressed("move_left"):  direction.x -= 1
	if Input.is_action_pressed("move_down"):  direction.y += 1
	if Input.is_action_pressed("move_up"):    direction.y -= 1

	if direction != Vector2.ZERO:
		_set_active()

		var wants_sprint: bool = Input.is_action_pressed("sprint") and stamina > 0
		_is_sprinting = wants_sprint

		var base_speed: float = speed + (agility - 1) * 10
		var actual_speed: float = base_speed * sprint_speed_multiplier if _is_sprinting else base_speed
		velocity = direction.normalized() * actual_speed

		if _is_sprinting:
			_sprint_drain_accumulator += sprint_stamina_drain_per_sec * _delta
			if _sprint_drain_accumulator >= 1.0:
				var drain_amount: int = int(_sprint_drain_accumulator)
				_sprint_drain_accumulator -= drain_amount
				stamina = max(0, stamina - drain_amount)

			# NEW: agility XP for actual sprinting, not just holding the
			# sprint key — wants_sprint above already requires stamina > 0
			# and the player to be moving, so standing still holding sprint
			# grants nothing. same fractional-accumulator pattern as the
			# stamina drain right above, since gain_agility_xp() takes an
			# int and per-frame amounts are fractional at this rate.
			_sprint_agility_xp_accumulator += sprint_agility_xp_per_sec * _delta
			if _sprint_agility_xp_accumulator >= 1.0:
				var xp_amount: int = int(_sprint_agility_xp_accumulator)
				_sprint_agility_xp_accumulator -= xp_amount
				gain_agility_xp(xp_amount)

		# CHANGED: guard against stomping an in-progress attack animation,
		# same as the idle guard below. previously this fired every physics
		# frame while a movement key was held, which would immediately
		# overwrite the warrior's swing animation with the walk animation
		# since warrior no longer freezes movement during attacks. because
		# looping animations never fire animation_finished, that left
		# is_attacking permanently stuck true — locking out all future
		# attacks and leaving the sprite stuck on a looping walk/idle frame.
		# now: movement (velocity/position) still happens every frame, but
		# the ANIMATION stays on the attack swing until it finishes, then
		# reverts to reflecting walk/idle normally.
		if has_node("animatedsprite2d") and not is_attacking:
			$animatedsprite2d.play(get_walk_animation(direction))
			$animatedsprite2d.speed_scale = sprint_speed_multiplier if _is_sprinting else 1.0
		last_direction = direction
		take_step()
		moved.emit(global_position, str(last_direction))
	else:
		velocity = Vector2.ZERO
		_is_sprinting = false
		_sprint_drain_accumulator = 0.0
		_sprint_agility_xp_accumulator = 0.0
		if has_node("animatedsprite2d") and not is_attacking:
			$animatedsprite2d.play(get_idle_animation())
			$animatedsprite2d.speed_scale = 1.0

	# Captured BEFORE the move so agility can be paid on ground actually
	# covered — see _accrue_agility_from_travel() below.
	var position_before: Vector2 = global_position

	move_and_slide()
	_shove_blocking_enemies(_delta)

	_accrue_agility_from_travel(global_position.distance_to(position_before))

	_tick_regen(_delta)


# =============================================================================
# AGILITY FROM COVERING GROUND
# =============================================================================

func _accrue_agility_from_travel(distance: float) -> void:
	# MEASURED FROM THE POSITION DELTA, not from velocity * delta.
	#
	# Those are the same number right up until something is in the way, and
	# then they are not: holding a key against a wall sets a velocity every
	# frame and moves you nowhere. Paying on intent rather than travel would
	# make standing in a corner the fastest way to train agility in the game.
	#
	# It also means a shove you are losing pays less, which is correct — you
	# did not get anywhere.
	if agility_xp_per_1000_px <= 0 or distance <= 0.0:
		return

	_agility_distance_accumulator += distance
	if _agility_distance_accumulator < 1000.0:
		return

	# Batched. gain_agility_xp() calls save_character_state() on every call,
	# so awarding per frame would be a save per frame — the 2 second debounce
	# would absorb it, but only by throwing almost all of them away.
	var thousands: int = int(_agility_distance_accumulator / 1000.0)
	_agility_distance_accumulator -= float(thousands) * 1000.0
	gain_agility_xp(thousands * agility_xp_per_1000_px)


# =============================================================================
# ENEMY SHOVING
# =============================================================================
#
# The collision relationship between the player and enemies is deliberately
# one-way: the player's collision_mask includes the enemies layer, but no
# enemy's mask includes the player layer. That makes enemies solid to you
# while you are not solid to them.
#
# On its own that is a trap. An enemy walks into you, you are blocked by it,
# it is not blocked by you, and its AI keeps pressing forward — so you are
# pinned with nothing to push against. This was very visible with the poison
# slime, which splits into eight bodies that all converge on the same spot.
#
# The fix is not to make collision mutual. Mutual collision means a pack of
# slimes jams against itself as well as against you, and pathfinding fights
# the physics. Instead the player explicitly shoves whatever it walks into:
# enemies stay solid and still block you, but leaning into one slides it out
# of the way.
#
# move_and_collide() is used on the enemy rather than assigning
# global_position directly, so the shove still respects walls — an enemy
# cannot be pushed through geometry, it just stops moving once it's pinned
# against something solid.
#
# Anything that should be immovable (the boss, a scripted encounter) can be
# added to the "unpushable" group and this will skip it.
func _shove_blocking_enemies(delta: float) -> void:
	if enemy_push_strength <= 0.0 and enemy_push_ratio <= 0.0:
		return

	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)

		# cast rather than `is` + call: `other` stays statically typed as
		# CharacterBody2D, so is_in_group()/move_and_collide() resolve without
		# the parser complaining about calling Node methods on Object.
		var other := collision.get_collider() as CharacterBody2D
		if other == null or not is_instance_valid(other):
			continue
		if not other.is_in_group("enemies"):
			continue
		if other.is_in_group("unpushable"):
			continue

		# THE SHOVE HAS TO OUTRUN THE CHASE, and only the enemy knows how fast
		# that is. An enemy pushed at 50 while pathing toward you at 80 is not
		# being shoved, it is closing more slowly.
		var chase_speed: float = 0.0
		if other.has_method("get_move_speed"):
			chase_speed = float(other.get_move_speed())
		var push_speed: float = maxf(chase_speed * enemy_push_ratio, enemy_push_strength)

		# get_normal() points OUT of the surface we collided with, i.e. back
		# toward us. Negating it gives the direction that moves the enemy
		# away from the player.
		var away: Vector2 = -collision.get_normal()

		# PUSH IT ASIDE, NOT JUST AHEAD.
		#
		# Which side: whichever one the enemy is already leaning toward, so a
		# body slightly to your left gets nudged further left and you walk
		# through the gap that opens.
		var tangent: Vector2 = away.orthogonal()
		var side: float = tangent.dot(other.global_position - global_position)

		# Dead centre. Either side is equally good, but CHOOSING ONE PER FRAME
		# would flip-flop and cancel itself out, so it is pinned to the enemy's
		# instance id — arbitrary, and stable for as long as that enemy lives.
		if absf(side) < 0.001:
			side = 1.0 if int(other.get_instance_id()) % 2 == 0 else -1.0

		if side < 0.0:
			tangent = -tangent

		# move_and_collide() rather than assigning global_position, so the
		# shove still respects walls — an enemy cannot be pushed through
		# geometry, it just stops once it is pinned against something solid.
		var push: Vector2 = (away + tangent * enemy_push_sidestep).normalized()
		other.move_and_collide(push * push_speed * delta)


# =============================================================================
# STAT CURVE — RECOMPUTE FROM LEVEL
# =============================================================================

func _set_stat_curve() -> void:
	pass


# =============================================================================
# SKILL PROFICIENCY  (NEW)
# =============================================================================
# every class can train every skill from the same universal triggers
# (attack XP from any hit — melee or spell; defense XP from taking damage,
# already true above in take_damage(); magic XP from any spell) — but each
# class climbs its OWN specialty faster. base class = 1.0 (no bias) for all
# six skills. subclasses override _set_skill_proficiency() to boost their
# specialty: warrior -> attack, tank -> defense, mage/healer -> magic.
# applied inside gain_attack_xp()/gain_defense_xp()/gain_magic_xp() below,
# so every caller (existing or new) gets the right scaling automatically —
# no call site needs to know or care which class it's running on.
var skill_proficiency: Dictionary = {
	"attack":  1.0,
	"defense": 1.0,
	"agility": 1.0,
	"magic":   1.0,
	"fishing": 1.0,
	"cooking": 1.0,
}

func _set_skill_proficiency() -> void:
	# base implementation: no class bias. subclasses override to boost
	# their specialty — see warrior/tank/mage/healer for actual values.
	pass


# =============================================================================
# DEFENSE TIERS
# =============================================================================
# The tier table and the lookup now live in PlayerStats. These two lines are
# aliases so `Player.DEFENSE_TIERS` keeps resolving for anything outside this
# file that reads it — the stats screen does.
const DEFENSE_TIERS := PlayerStats.DEFENSE_TIERS


func _get_defense_tier() -> Dictionary:
	return PlayerStats.defense_tier(defense)


# =============================================================================
# COMBAT DAMAGE BONUSES
# =============================================================================
# See PlayerStats for what these mean and which class applies which.
const DAMAGE_BONUS_PER_POINT := PlayerStats.DAMAGE_BONUS_PER_POINT

func get_attack_damage_bonus() -> float:
	return PlayerStats.attack_damage_bonus(attack)

func get_magic_damage_bonus() -> float:
	return PlayerStats.magic_damage_bonus(magic)


func _apply_class_data(data: ClassData) -> void:
	# Copies a class's curve onto this player. Called from each subclass's
	# _set_stat_curve(), which runs before _recompute_max_stats() below.
	#
	# The fields stay as plain vars rather than being read through `data`
	# everywhere, so every existing reference keeps working — this changes where
	# the numbers COME FROM, not how they are used. Same shape as
	# BaseEnemy._apply_enemy_data().
	if data == null:
		# Loud, because the failure is otherwise invisible: the character works,
		# it fights, and it quietly has 20 hp and no mana at every level.
		push_warning("%s: no ClassData — falling back to Player defaults (20 hp, no mana)." % character_name)
		return

	hp_base      = data.hp_base
	hp_per_lvl   = data.hp_per_lvl
	mana_base    = data.mana_base
	mana_per_lvl = data.mana_per_lvl
	stam_base    = data.stam_base
	stam_per_lvl = data.stam_per_lvl


func _recompute_max_stats() -> void:
	max_hp      = PlayerStats.max_for(hp_base,   hp_per_lvl,   level)
	max_mana    = PlayerStats.max_for(mana_base, mana_per_lvl, level)
	max_stamina = PlayerStats.max_for(stam_base, stam_per_lvl, level)


func _fill_all_resources() -> void:
	hp      = max_hp
	mana    = max_mana
	stamina = max_stamina


# =============================================================================
# REGEN HELPERS
# =============================================================================

func _set_active() -> void:
	# Any action — moving, attacking, casting, taking a hit — restarts the
	# idle wait AND discards part-earned points. Regen is strictly a
	# between-fights mechanic; potions are what recover you during one.
	_idle_timer = 0.0
	_regen_hp_accumulator = 0.0
	_regen_mana_accumulator = 0.0
	_regen_stamina_accumulator = 0.0


# THE single regen implementation. tank.gd used to carry its own copy of this
# loop, because it fully overrides _physics_process and so never ran player's
# — its comment literally read "DUPLICATED FROM PLAYER.GD". It now calls this
# instead, so a change here reaches every class instead of three of the four.
func _tick_regen(delta: float) -> void:
	_idle_timer += delta
	if _idle_timer < idle_threshold:
		return

	if hp < max_hp:
		_regen_hp_accumulator += _regen_rate_for(max_hp) * delta
		var points: int = int(_regen_hp_accumulator)
		if points > 0:
			_regen_hp_accumulator -= points
			hp = min(max_hp, hp + points)

	if mana < max_mana:
		_regen_mana_accumulator += _regen_rate_for(max_mana) * delta
		var points: int = int(_regen_mana_accumulator)
		if points > 0:
			_regen_mana_accumulator -= points
			mana = min(max_mana, mana + points)

	if stamina < max_stamina:
		_regen_stamina_accumulator += _regen_rate_for(max_stamina) * delta
		var points: int = int(_regen_stamina_accumulator)
		if points > 0:
			_regen_stamina_accumulator -= points
			stamina = min(max_stamina, stamina + points)


func _regen_rate_for(stat_max: int) -> float:
	return PlayerStats.regen_rate_for(stat_max, regen_percent_per_second, regen_minimum_per_second)


# =============================================================================
# FLOATING LABEL FEEDBACK
# =============================================================================

# Where damage/heal/level-up popups get parented.
#
# BaseEnemy._spawn_floating_label() already looked for a node in the
# "floatinglabels" group — a dedicated, high-z_index, non-y-sorted layer so
# numbers always draw over the world instead of being sorted behind a tree or
# an enemy. The player's popups never used it and went straight to the scene
# root, so the two halves of the same feedback system behaved differently.
# This makes both take the same path.
func _label_container() -> Node:
	var container: Node = get_tree().get_first_node_in_group("floatinglabels")
	if container != null:
		return container
	return get_tree().current_scene


func _spawn_floating_label(amount: int, type: int) -> void:
	if FLOATING_LABEL_SCENE == null:
		push_warning("Player: FLOATING_LABEL_SCENE not loaded")
		return

	var lbl = FLOATING_LABEL_SCENE.instantiate()
	if lbl == null:
		return

	_label_container().add_child(lbl)
	lbl.global_position = global_position + Vector2(0, -30)
	# Without this the label is drawn once at the world origin and streaks
	# into place — see BaseEnemy.spawn_projectile_node() for the mechanism.
	lbl.reset_physics_interpolation()
	if lbl.has_method("show_number"):
		lbl.show_number(amount, type)


# de-duplication state for show_notice(). Kept next to its only user rather
# than up with the stat block, because it is bookkeeping for one function and
# means nothing outside it.
var _last_notice_text: String = ""
var _last_notice_at_ms: int = 0


# PUBLIC. The single way to tell the player "you can't do that right now".
#
# WHY THIS EXISTS: refusals like "health is already full", "not enough mana"
# and "inventory full" were written as print() calls. From the player's side
# that is no feedback at all — the click just does nothing and no reason is
# given. They were console messages wearing the costume of a feature.
#
# Callers are inventoryscreen.gd, lootbaginventory.gd, tank.gd and mage.gd.
# The UI scripts reach it through their player reference; the character
# classes extend this file and call it on self.
func show_notice(message: String) -> void:
	if message == "":
		return

	# DE-DUPLICATION IS THE LOAD-BEARING PART.
	#
	# Every caller is a click or key handler, and those fire far faster than
	# anyone can read. Refusing to cast with no mana while the attack button
	# is held would otherwise stack a fresh label every frame — the same
	# mistake as emitting player_moved 180 times a second, except this one
	# is visible and covers the screen.
	#
	# Only an IDENTICAL message is suppressed, so two different refusals in
	# quick succession both still appear.
	var now_ms: int = Time.get_ticks_msec()
	if message == _last_notice_text:
		if now_ms - _last_notice_at_ms < NOTICE_REPEAT_COOLDOWN_MS:
			return
	_last_notice_text = message
	_last_notice_at_ms = now_ms

	if FLOATING_LABEL_SCENE == null:
		push_warning("Player: FLOATING_LABEL_SCENE not loaded")
		return

	var lbl = FLOATING_LABEL_SCENE.instantiate()
	if lbl == null:
		return

	# higher than damage numbers (-30) and the level-up popup (-40) so a
	# refusal never lands on top of a number that appeared the same frame.
	_label_container().add_child(lbl)
	lbl.global_position = global_position + Vector2(0, -52)
	# Without this the label is drawn once at the world origin and streaks
	# into place — see BaseEnemy.spawn_projectile_node() for the mechanism.
	lbl.reset_physics_interpolation()
	if lbl.has_method("show_text"):
		lbl.show_text(message, NOTICE_LABEL_TYPE, 1.2, 0.9)


func _spawn_levelup_popup() -> void:
	if FLOATING_LABEL_SCENE == null:
		return
	var lbl = FLOATING_LABEL_SCENE.instantiate()
	if lbl == null:
		return
	_label_container().add_child(lbl)
	lbl.global_position = global_position + Vector2(0, -40)
	# Without this the label is drawn once at the world origin and streaks
	# into place — see BaseEnemy.spawn_projectile_node() for the mechanism.
	lbl.reset_physics_interpolation()
	if lbl.has_method("show_text"):
		lbl.show_text("LEVEL UP!\n%d" % level, 3, 2.0, 1.5)


func _spawn_defense_tier_popup(tier_name: String) -> void:
	# NEW: crossing a defense tier gets the same visual weight as a
	# character level-up (same color type, size, duration) — it's a bigger
	# moment than a routine skill-up, worth treating that way.
	if FLOATING_LABEL_SCENE == null:
		return
	var lbl = FLOATING_LABEL_SCENE.instantiate()
	if lbl == null:
		return
	_label_container().add_child(lbl)
	lbl.global_position = global_position + Vector2(0, -45)
	# Without this the label is drawn once at the world origin and streaks
	# into place — see BaseEnemy.spawn_projectile_node() for the mechanism.
	lbl.reset_physics_interpolation()
	if lbl.has_method("show_text"):
		lbl.show_text("DEFENSE TIER\n%s" % tier_name, 3, 2.0, 1.5)


func _spawn_skillup_popup(skill_code: String, new_level: int) -> void:
	# ABOVE the early return. The skill level went up whether or not there is a
	# label scene to announce it with, and a missing scene should not silence
	# the event as well as hiding it.
	Audio.play("skill_up")

	if FLOATING_LABEL_SCENE == null:
		return
	var display: String = SKILL_DISPLAY_NAMES.get(skill_code, skill_code.capitalize())
	var lbl = FLOATING_LABEL_SCENE.instantiate()
	if lbl == null:
		return
	_label_container().add_child(lbl)
	lbl.global_position = global_position + Vector2(0, -35)
	# Without this the label is drawn once at the world origin and streaks
	# into place — see BaseEnemy.spawn_projectile_node() for the mechanism.
	lbl.reset_physics_interpolation()
	if lbl.has_method("show_text"):
		lbl.show_text("%s %d" % [display, new_level], 4, 1.2, 0.9)


# =============================================================================
# ANIMATION HELPERS
# =============================================================================

# An animation name is a prefix plus one of Facing's four words: "walk" + "left"
# is "walkleft", which is what every SpriteFrames in the project is named. The
# axis rule that picks the word lives in Facing now - it was written out
# thirteen times across this file, the four class scripts, pet.gd and
# baseenemy.gd, and the copies had already stopped agreeing.
#
# from_vec_total, not from_vec: there is no "no animation" to play, so a zero
# vector still has to resolve to something. It resolves to UP, because that is
# what the code these replaced returned.
func get_walk_animation(dir: Vector2) -> String:
	return "walk" + Facing.from_vec_total(dir)


func get_idle_animation() -> String:
	return "idle" + Facing.from_vec_total(last_direction)


func get_attack_animation(dir: Vector2) -> String:
	return "attack" + Facing.from_vec_total(dir)


func _on_animatedsprite2d_animation_finished() -> void:
	if not has_node("animatedsprite2d"):
		return
	var anim_name: String = $animatedsprite2d.animation

	if anim_name.begins_with("attack"):
		is_attacking = false
		$animatedsprite2d.play(get_idle_animation())
		return

	if anim_name.begins_with("death"):
		call_deferred("_change_to_game_over")
		return


# =============================================================================
# ATTACK INPUT — SPACE + RIGHT CLICK
# =============================================================================
# Attack fires on the "attack" action (spacebar) OR right mouse, for every
# class. Right-click used to be polled privately by warrior, mage and tank,
# each with its own held-tracker and its own edge detection, because binding
# a mouse button onto the shared action would have collided with mage's
# separate right-click cast. That collision no longer exists — mage's
# attack_action() already IS the stalagmite cast — so the four copies are
# gone and this is the one place right-click is read.

# Right-click hold state from the previous physics frame, for edge detection.
var _right_click_was_held: bool = false


func right_click_attack_held() -> bool:
	# Right mouse as an ATTACK input: held, and NOT part of a click the UI
	# already consumed. Public because healer polls it for continuous fire.
	#
	# Input.is_mouse_button_pressed() reads the hardware, not the scene tree,
	# so a click a Control already handled with accept_event() is still
	# "pressed" as far as this loop is concerned. That is why right-clicking
	# an item in the inventory to drink a potion ALSO swung the weapon.
	# inventoryslot.gd raises GameState.ui_absorbed_right_click when it takes
	# a click; this clears it the moment the button physically comes back up,
	# so the suppression covers exactly that one click and no longer.
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		GameState.ui_absorbed_right_click = false
		return false
	return not GameState.ui_absorbed_right_click


func _poll_attack_pressed() -> bool:
	# One frame's worth of attack input, edge-detected so a held right button
	# fires once rather than every frame. MUST be called exactly once per
	# physics frame, unconditionally — see the call site in _physics_process.
	var right_now: bool = right_click_attack_held()
	var right_edge: bool = right_now and not _right_click_was_held
	_right_click_was_held = right_now
	return Input.is_action_just_pressed("attack") or right_edge


# =============================================================================
# COMBAT
# =============================================================================

func attack_action() -> void:
	if is_attacking:
		return
	_set_active()
	is_attacking = true

	# The base swing. Every class overrides attack_action() and none of them
	# call super(), so this fires only for a class that has not replaced it —
	# which is why warrior, mage, tank and healer each carry their own call.
	Audio.play("attack_swing")

	var anim := get_attack_animation(last_direction)
	if has_node("animatedsprite2d"):
		var sprite: AnimatedSprite2D = $animatedsprite2d
		if sprite.sprite_frames.has_animation(anim):
			sprite.play(anim)
		else:
			push_warning("Player: missing animation '%s' — attack canceled" % anim)
			is_attacking = false


func take_step() -> void:
	pass


func take_damage(amount: int, _type: StringName = &"physical") -> void:
	if is_dying:
		return

	_set_active()

	# NEW: tiered defense reduction — see DEFENSE_TIERS below. XP gain
	# further down still uses the RAW incoming amount, not the reduced
	# one, so higher defense doesn't also slow down future defense XP —
	# that would create a self-limiting feedback loop nobody asked for.
	# maxi(1, ...) guarantees chip damage always gets through — even at
	# the 50% cap, a hit can never be reduced to zero.
	var reduction: float = _get_defense_tier()["reduction"]
	var reduced_amount: int = maxi(1, int(amount * (1.0 - reduction)))

	hp = clamp(hp - reduced_amount, 0, max_hp)
	took_damage.emit(reduced_amount, str(_type))

	_spawn_floating_label(reduced_amount, 0)

	_play_hit_flash()

	if hp <= 0:
		died.emit()
		_start_death_sequence()
		return

	# Survival only — the death sound belongs to _start_death_sequence(), which
	# is the one that knows whether a revive token is about to cancel the death.
	Audio.play("player_hurt")

	# integer division on purpose — defense XP is half the damage taken,
	# rounded down, and maxi() guarantees a 1-damage hit still trains it.
	# spelled with @warning_ignore so the intent is on the record rather
	# than the editor flagging it as a possible accident every reload.
	@warning_ignore("integer_division")
	gain_defense_xp(maxi(1, amount / 2))


func _play_hit_flash() -> void:
	if not has_node("animatedsprite2d"):
		return
	var sprite: AnimatedSprite2D = $animatedsprite2d
	# NEW: flash duration scales down with the same reduction percentage
	# already driving damage tiers (see DEFENSE_TIERS) — a Novice takes
	# the full flash, an Unbreakable character's is noticeably brighter,
	# briefer. this is what "poise" actually became once real knockback
	# turned out to need new art this project doesn't have: not a
	# gameplay-affecting resistance, just defense having a real, felt
	# difference in how a hit LOOKS, using assets that already exist.
	# maxf floor keeps it from ever going imperceptibly short.
	var reduction: float = _get_defense_tier()["reduction"]
	var scaled_duration: float = maxf(0.05, hit_flash_duration * (1.0 - reduction))
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.0)
	tween.tween_property(sprite, "modulate", _default_modulate, scaled_duration)


func heal(amount: int) -> void:
	var actual_heal: int = min(amount, max_hp - hp)
	if actual_heal <= 0:
		return
	hp = min(max_hp, hp + amount)
	_spawn_floating_label(actual_heal, 1)


func restore_mana(amount: int) -> void:
	var actual_restore: int = min(amount, max_mana - mana)
	if actual_restore <= 0:
		return
	mana = clamp(mana + amount, 0, max_mana)
	_spawn_floating_label(actual_restore, 2)


# =============================================================================
# DEATH SEQUENCE
# =============================================================================

func _start_death_sequence() -> void:
	is_dying = true
	velocity = Vector2.ZERO

	if has_active_revive:
		has_active_revive = false
		_fill_all_resources()
		is_dying = false
		if OS.is_debug_build():
			print("[PLR]  revive token consumed — full resources")
		return

	# BELOW the revive branch on purpose. A consumed revive token is not a
	# death, and playing the death sound before checking would make the most
	# dramatic sound in the game fire for something that did not happen.
	Audio.play("player_death")

	var death_anim: String = _get_death_animation()
	if has_node("animatedsprite2d"):
		var sprite: AnimatedSprite2D = $animatedsprite2d
		if sprite.sprite_frames.has_animation(death_anim):
			sprite.play(death_anim)
			return

	call_deferred("_change_to_game_over")


func _get_death_animation() -> String:
	return "death" + Facing.from_vec_total(last_direction)


func _change_to_game_over() -> void:
	GameState.death_state = {
		"character_name": character_name,
		"death_position": global_position,
		"max_hp": max_hp,
	}
	get_tree().change_scene_to_file("res://scene/ui/menus/gameover.tscn")


# =============================================================================
# LEVELING
# =============================================================================

func level_up() -> void:
	level += 1
	Audio.play("level_up")
	_recompute_max_stats()
	_fill_all_resources()
	_apply_level_up_skill_bonus()
	_spawn_levelup_popup()
	# the player already sees this — _spawn_levelup_popup() just put it on
	# screen. The print is only for reading the progression curve in a log.
	if OS.is_debug_build():
		print("[PLR]  %s reached level %d" % [character_name, level])


func _apply_level_up_skill_bonus() -> void:
	pass


func gain_xp(amount: int) -> void:
	# CHANGED: xp_next used to be `xp_next *= 2` — a raw doubling
	# accumulator that overflows a 64-bit int somewhere around level 58
	# (2^57 alone is already past int64's range). the sanity-check side of
	# this got a safety clamp earlier, but that only stopped CharacterData's
	# anti-tamper pass from producing garbage — it never fixed this, the
	# ACTUAL formula every real level-up runs through. now recomputed fresh
	# from the current level each time, same deterministic pattern already
	# used for skill XP (xp_needed_for_skill below) — 1.15 is the same
	# growth factor already proven safe there. at level 99 this needs
	# ~240M total XP for that single level, well within int64's range with
	# enormous headroom, instead of overflowing entirely.
	xp += amount
	xp_gained_signal.emit(amount)
	while xp >= xp_next:
		level_up()
		xp -= xp_next
		xp_next = GameConstants.xp_needed_for_level(level)
	CharacterData.save_character_state(self)


func xp_needed_for_skill(skill_level: int, base := 100, factor := 1.18) -> int:
	# Defaults repeated here rather than referencing PlayerStats.SKILL_XP_BASE,
	# because a default argument is part of this method's public signature and
	# several callers pass their own. PlayerStats holds the same two numbers.
	return PlayerStats.xp_needed_for_skill(skill_level, base, factor)


# =============================================================================
# UNIVERSAL DAMAGE SCALING
# =============================================================================
# Aliases. The formulas and the reasoning behind both of these — including why
# the attack-speed multiplier is capped — are in PlayerStats.
const ATTACK_DAMAGE_PERCENT_PER_LEVEL := PlayerStats.ATTACK_DAMAGE_PERCENT_PER_LEVEL
const MAGIC_DAMAGE_PERCENT_PER_LEVEL  := PlayerStats.MAGIC_DAMAGE_PERCENT_PER_LEVEL

func get_damage_multiplier() -> float:
	return PlayerStats.damage_multiplier(attack, magic)


const AGILITY_ATTACK_SPEED_PERCENT_PER_LEVEL := PlayerStats.AGILITY_ATTACK_SPEED_PERCENT_PER_LEVEL
const MAX_ATTACK_SPEED_MULTIPLIER := PlayerStats.MAX_ATTACK_SPEED_MULTIPLIER


func get_attack_speed_multiplier() -> float:
	# How much faster than base this character attacks. 1.0 at agility 1.
	# DIVIDE a cooldown by this; don't multiply a rate by it and forget the cap.
	return PlayerStats.attack_speed_multiplier(agility)


# =============================================================================
# SKILL XP
# =============================================================================

func gain_attack_xp(amount: int) -> void:
	# NEW: scaled by skill_proficiency["attack"] — this is what makes
	# attack XP universal (any class can call this) while still letting
	# warrior climb it faster than everyone else. see SKILL PROFICIENCY
	# section above.
	var scaled_amount: int = maxi(1, int(amount * skill_proficiency.get("attack", 1.0)))
	attack_xp += scaled_amount
	while attack_xp >= attack_xp_next:
		attack += 1
		attack_xp -= attack_xp_next
		attack_xp_next = xp_needed_for_skill(attack, 100, 1.25)
		_spawn_skillup_popup("attack", attack)
	CharacterData.save_character_state(self)


func gain_defense_xp(amount: int) -> void:
	# NEW: scaled by skill_proficiency["defense"] — take_damage() above
	# already grants this universally to every class; this is what lets
	# tank climb it faster without touching take_damage() at all.
	var scaled_amount: int = maxi(1, int(amount * skill_proficiency.get("defense", 1.0)))
	var tier_before: String = _get_defense_tier()["name"]
	defense_xp += scaled_amount
	while defense_xp >= defense_xp_next:
		defense += 1
		defense_xp -= defense_xp_next
		defense_xp_next = xp_needed_for_skill(defense, 100, 1.20)
		_spawn_skillup_popup("defense", defense)
	# NEW: a tier crossing (Novice -> Trained -> ... -> Unbreakable) is a
	# bigger moment than an ordinary skill level-up, so it gets its own,
	# more prominent popup on top of the normal one above.
	var tier_after: String = _get_defense_tier()["name"]
	if tier_after != tier_before:
		_spawn_defense_tier_popup(tier_after)
	CharacterData.save_character_state(self)


func gain_agility_xp(amount: int) -> void:
	agility_xp += amount
	while agility_xp >= agility_xp_next:
		agility += 1
		agility_xp -= agility_xp_next
		agility_xp_next = xp_needed_for_skill(agility, 100, 1.15)
		_spawn_skillup_popup("agility", agility)
	CharacterData.save_character_state(self)


func gain_magic_xp(amount: int) -> void:
	# NEW: scaled by skill_proficiency["magic"] — this is what lets
	# mage/healer climb magic faster than a class that only occasionally
	# lands a spell hit.
	var scaled_amount: int = maxi(1, int(amount * skill_proficiency.get("magic", 1.0)))
	magic_xp += scaled_amount
	while magic_xp >= magic_xp_next:
		magic += 1
		magic_xp -= magic_xp_next
		magic_xp_next = xp_needed_for_skill(magic, 100, 1.25)
		_spawn_skillup_popup("magic", magic)
	CharacterData.save_character_state(self)


func gain_fishing_xp(amount: int) -> void:
	fishing_xp += amount
	while fishing_xp >= fishing_xp_next:
		fishing += 1
		fishing_xp -= fishing_xp_next
		fishing_xp_next = xp_needed_for_skill(fishing, 100, 1.12)
		_spawn_skillup_popup("fishing", fishing)
	CharacterData.save_character_state(self)


func gain_cooking_xp(amount: int) -> void:
	cooking_xp += amount
	while cooking_xp >= cooking_xp_next:
		cooking += 1
		cooking_xp -= cooking_xp_next
		cooking_xp_next = xp_needed_for_skill(cooking, 100, 1.10)
		_spawn_skillup_popup("cooking", cooking)
	CharacterData.save_character_state(self)


# =============================================================================
# CURRENCY
# =============================================================================

func add_gold(amount: int) -> void:
	gold += amount
	gold_changed_signal.emit(gold)
	update_gold_label()
	CharacterData.save_character_state(self)


func set_gold(total: int) -> void:
	# THE SERVER'S NUMBER, NOT A DELTA.
	#
	# /api/loot/take credits gold against its own row and hands the BALANCE back.
	# Adding the amount here instead would mean this client is keeping its own
	# running total, and it still pushes `gold` on every save — so one response
	# lost to a timeout would overwrite the server's figure with a stale one on
	# the very next save, and the loss would look like nothing at all.
	#
	# Landing on the total means a missed response is corrected by the next one
	# that arrives rather than compounding.
	gold = maxi(total, 0)
	gold_changed_signal.emit(gold)
	update_gold_label()
	CharacterData.save_character_state(self)


func update_gold_label() -> void:
	if gold_label:
		gold_label.text = "gold: " + str(gold)


func add_lusions(amount: int) -> void:
	CharacterData.add_account_lusions(amount)
	lusions_changed_signal.emit(CharacterData.get_account_lusions())
	update_lusions_label()


func set_lusions(total: int) -> void:
	# Same reasoning as set_gold() above: the loot endpoint hands back the
	# balance it landed on, and applying that rather than the amount means a
	# response this client never saw is corrected by the next one it does.
	#
	# Goes through CharacterData because lusions are account-shared — the
	# `lusions` property on this class is a view of that pool, not a field.
	CharacterData.set_account_lusions(maxi(total, 0))
	lusions_changed_signal.emit(CharacterData.get_account_lusions())
	update_lusions_label()


func update_lusions_label() -> void:
	if lusions_label:
		lusions_label.text = "lusions: " + str(lusions)


# =============================================================================
# UI HELPERS
# =============================================================================

func update_stats_labels(statspanel) -> void:
	statspanel.get_node("levellabel").text   = "level: " + str(level)
	statspanel.get_node("hplabel").text      = "hp: " + str(hp) + "/" + str(max_hp)
	statspanel.get_node("staminalabel").text = "stamina: " + str(stamina) + "/" + str(max_stamina)
	statspanel.get_node("manalabel").text    = "mana: " + str(mana) + "/" + str(max_mana)
	statspanel.get_node("attacklabel").text  = "attack: " + str(attack)
	statspanel.get_node("defenselabel").text = "defense: " + str(defense)
	statspanel.get_node("agilitylabel").text = "agility: " + str(agility)
	statspanel.get_node("magiclabel").text   = "magic: " + str(magic)
	statspanel.get_node("fishinglabel").text = "fishing: " + str(fishing)
	statspanel.get_node("cookinglabel").text = "cooking: " + str(cooking)
	statspanel.get_node("xplabel").text      = "total xp: " + str(xp)


# =============================================================================
# DEBUG
# =============================================================================

# TWO GATES, AND NEITHER IS A SECURITY BOUNDARY. Read the second paragraph
# before relying on either.
#
# is_debug_build() keeps these keys out of a Release export. It is not enough on
# its own: a DEBUG-template export reports is_debug_build() as true, and picking
# the wrong template in the Export dialog is a single mis-click. So the rank is
# checked too, and an ordinary player holding a debug build gets nothing.
#
# WHAT THIS DOES NOT DO: stop a modified client. Api.role is client memory set
# from a login response, so a patched build sets it to "owner" and these keys
# work again. It would not even need to - the keys add items to the LOCAL
# inventory and the client pushes that to the server on save, and the backpack
# ledger is still client-asserted (see Known gaps in CLAUDE.md). Anyone able to
# edit the client can grant themselves items with or without this function.
#
# WHAT IT DOES BUY: an honest player in a debug build cannot press P and own a
# pet. Pets are loot. Every key below hands out something a player is supposed
# to earn - gear, currency, skill XP - so the gate is on the whole block rather
# than the pet row alone.
func _staff_debug_allowed() -> bool:
	return OS.is_debug_build() and Api.role_at_least(Api.DEBUG_KEYS_MIN_ROLE)


func _unhandled_input(event: InputEvent) -> void:
	if not _staff_debug_allowed():
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1: _debug_give_item("tinyhealthpotion", 5)
			KEY_F2: _debug_give_item("ironsword", 1)
			KEY_F3: _debug_give_item("bushamulet", 1)
			KEY_F4: _debug_give_item("smallamountofgold", 1)
			KEY_F5: _debug_give_lusions(20)
			KEY_F6: _debug_give_item("lusions", 5)
			KEY_F7: _debug_give_item("tinymanapotion", 5)
			# PETS — the P O I U Y T row, one key per pet, reading leftward.
			#
			# Every one of these grants the pet ITEM. None of them spawns a pet
			# directly, and that is the entire point: the key puts the item in
			# your bag and you use it from the inventory, which runs the real
			# path — inventory -> use -> summon_pet() -> active_pet_id ->
			# persisted by CharacterData -> restored on the next scene load.
			#
			# P O I U used to call _debug_spawn_pet*(), which assembled a pet
			# node by hand from a hardcoded res:// path and set active_pet_id
			# itself. That bypassed summon_pet() and ItemRegistry completely,
			# so pets always tested fine while the pet ITEMS were broken —
			# including the stretch where petpoisonslimesmall.tres carried a
			# copy-pasted item_id and was being silently rejected at load.
			# Four debug helpers that could not fail were standing in front of
			# the one path that could. They are gone.
			#
			# NOT F8: that's the editor's "Stop running project" shortcut and
			# it kills the game even when the game window has focus.
			KEY_P: _debug_give_item("petsniper", 1)
			KEY_O: _debug_give_item("petmage", 1)
			KEY_I: _debug_give_item("petelectricsprite", 1)
			KEY_U: _debug_give_item("petfiresprite", 1)
			KEY_Y: _debug_give_item("petpoisonslimesmall", 1)
			KEY_T: _debug_give_item("petpoisonslimelarge", 1)
			KEY_M:
				mana = max(mana - 30, 0)
				print("DEBUG: drained 30 mana (now %d)" % mana)
			KEY_F9:  gain_attack_xp(30)
			KEY_F10: gain_defense_xp(30)
			KEY_F11: gain_agility_xp(30)
			KEY_F12: gain_magic_xp(30)


# =============================================================================
# DIRECT PET SPAWNING  (REMOVED)
# =============================================================================
# _debug_spawn_pet(), _debug_spawn_pet_mage(), _debug_spawn_pet_electric() and
# _debug_spawn_pet_fire() used to live here — one per pet, each loading a
# hardcoded res:// scene path, attaching the node and assigning active_pet_id
# by hand.
#
# They were four near-identical copies of a worse summon_pet(). Worse because
# they never touched ItemRegistry, so they proved nothing about whether the
# pet's .tres existed, carried the right item_id, or pointed at the right
# scene — the three things that actually broke. A pet could spawn perfectly
# on KEY_P while its item was unobtainable in the real game.
#
# The P O I U Y T keys now grant the pet item instead and the pet is summoned
# through the same path a player uses. If you need a pet in front of you fast,
# press the key and use the item; it is two keystrokes and it tests something.


# =============================================================================
# PETS
# =============================================================================
# The mechanics live in PetController. What stays here is the state and the
# decisions: active_pet_id is persisted per character slot by CharacterData, so
# it belongs to the character rather than to the system that spawns things.

func _restore_active_pet() -> void:
	# Re-spawns the active pet on scene load. See active_pet_id's comment for
	# why a String survives a scene change when a node reference cannot.
	#
	# No despawn first, deliberately: the previous pet was freed along with the
	# previous scene, so there is nothing left to remove.
	if active_pet_id == "":
		return

	var scene: PackedScene = PetController.pet_scene_for(active_pet_id)
	if scene == null:
		# The warning naming the reason already came from pet_scene_for().
		# Clearing matters: left set, this would warn on every scene load for
		# the rest of the character's life.
		active_pet_id = ""
		return

	PetController.attach(self, scene.instantiate(), PetController.SUMMON_OFFSET)
	if OS.is_debug_build():
		print("[PET]  restored '%s'" % active_pet_id)


func summon_pet(item_id: String) -> bool:
	# Called when a PET item is used from the inventory.
	#
	# RETURNS FALSE WITHOUT CHANGING ANYTHING if the item cannot be summoned,
	# so the caller can leave it sitting in the inventory rather than consuming
	# it for nothing. That is the whole reason this returns a bool.
	var scene: PackedScene = PetController.pet_scene_for(item_id)
	if scene == null:
		return false

	# One pet at a time, matching the single active_pet_id model - summoning a
	# second REPLACES the first rather than stacking companions.
	PetController.despawn_all(get_tree())
	PetController.attach(self, scene.instantiate(), PetController.SUMMON_OFFSET)

	# Set LAST, and only once everything above succeeded. _restore_active_pet()
	# trusts this string to name a pet that resolves, and CharacterData persists
	# it, so a bad value here would follow the save around.
	active_pet_id = item_id

	# Success path only. A summon sound for a pet that never appeared is worse
	# than silence.
	Audio.play("pet_summon")

	if OS.is_debug_build():
		print("[PET]  summoned '%s'" % active_pet_id)
	return true


func dismiss_pet() -> void:
	# Despawn AND forget. The despawn on its own is what summon_pet() does when
	# replacing a pet, where active_pet_id is about to be overwritten anyway.
	# This is for genuinely putting the pet away, so it has to clear the id too
	# or the pet reappears on the next scene load.
	PetController.despawn_all(get_tree())
	active_pet_id = ""


# BOTH _debug_* functions below repeat the gate rather than trusting it.
#
# They are already unreachable for a player, because the only thing that calls
# them is _unhandled_input(), which returns early - but that is a fact about a
# different function two hundred lines up, and it stops being true the moment
# anyone wires one of these to a button, a console command or a test. These hand
# out free items, free pets and free lusions; they should refuse on their own
# authority rather than inherit safety from their caller.
func _debug_give_item(item_id: String, quantity: int) -> void:
	if not _staff_debug_allowed():
		return
	var data := ItemRegistry.get_item(item_id)
	if data == null:
		print("DEBUG: item '%s' not found in registry" % item_id)
		return

	var stack := ItemStack.new(data, quantity)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		print("DEBUG: HUD not found in 'hud' group")
		return

	if hud.inventory_screen == null:
		print("DEBUG: open the inventory at least once before using debug keys")
		return

	var container: Node = hud.inventory_screen.get_node_or_null("%inventorycontainer")
	if container == null:
		print("DEBUG: inventorycontainer not found in inventory_screen")
		return

	if container.add_stack(stack):
		print("DEBUG: gave %d x %s" % [quantity, data.display_name])
		CharacterData.save_character_state(self)
	else:
		print("DEBUG: inventory full or partial fit — couldn't add full quantity")


func _debug_give_lusions(amount: int) -> void:
	if not _staff_debug_allowed():
		return
	add_lusions(amount)
	print("DEBUG: gave %d lusions (now %d total)" % [amount, lusions])
