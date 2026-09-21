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

# The soft light the player carries in dark scenes. One scene, tuned in one
# place, instanced onto every class rather than copied into four .tscn files.
const PLAYER_LIGHT_SCENE := preload("res://scene/characters/playerlight.tscn")
var _carried_light: PointLight2D = null

# FloatingLabel.Type.NOTICE.
#
# This used to be a bare int with a comment explaining that floatinglabel.gd
# had no class_name, so its enum could not be reached by name from here. It
# has one now — see the note beside it — so the constant is written as what it
# means. The literal 0/1/2/3 in the popup calls further down this file are the
# same workaround and can go the same way as each is next touched.
const NOTICE_LABEL_TYPE: int = FloatingLabel.Type.NOTICE

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

# WADING THROUGH ENEMIES.
#
# The player is NOT solid to enemies and enemies are NOT solid to the player -
# no mask on either side names the other's layer. You walk through them. What
# stops that feeling like walking through fog is the two knobs below: being
# inside a body slows you down, and bodies you walk into get displaced.
#
# THIS REPLACED A SHOVE THAT CAUSED THE THING IT WAS MEANT TO PREVENT.
# Enemies used to be solid to the player one-way, so an enemy could stand in
# your space while you could not move through it, and _shove_blocking_enemies()
# compensated by pushing it at 1.6x ITS OWN CHASE SPEED - explicitly tuned to
# always win the race. Walking into an enemy therefore shoved it clear, freed
# the space, let you advance, and shoved again: that stop-start loop was the
# "latching", and riding a body being moved faster than you walk was the free
# speed. The arms race only existed because a losing push meant being pinned.
# Nothing here can pin you, so nothing here has to win.

# HOW MUCH SPEED THE FIRST BODY COSTS YOU, as a fraction. This is the weight.
@export var enemy_wade_drag: float = 0.30

# ...and each additional body you are standing inside on top of that. A poison
# slime splits into eight, and walking into all eight should feel like walking
# into all eight.
@export var enemy_wade_drag_per_extra: float = 0.10

# The floor, so a crowd slows you rather than trapping you. Pinning is the one
# failure mode this whole approach exists to rule out.
@export var enemy_wade_min_speed: float = 0.45

# HOW FAST A BODY YOU ARE INSIDE GETS PUSHED ASIDE, as a fraction of YOUR
# current speed - never of the enemy's, which is the mistake the old shove made.
# Below 1.0 means you always out-pace what you displace, so there is nothing to
# ride. It can afford to lose to an enemy walking back in, because losing just
# means you wade past it instead of being stopped by it.
@export var enemy_wade_push_ratio: float = 0.6

# A trickle of push while you are standing still, so a pack converging on you
# settles into a ring instead of stacking eight sprites on one pixel.
@export var enemy_wade_idle_push: float = 18.0

# How much of the push goes sideways rather than straight away, so bodies part
# around your shoulders instead of being bulldozed along in front of you.
@export var enemy_wade_sidestep: float = 0.5

# How wide the "inside a body" test is, in pixels, measured from your origin.
@export var enemy_wade_radius: float = 14.0


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
#
# THE DEFAULTS COME FROM PlayerStats NOW, and are no longer literals here. The
# server reconciles healing against these rates (see _report_unexplained_heals
# in app.py), exportgamedata.gd carries them across, and a second copy of
# 0.0167 in this file would be exactly the drift gameconstants.gd was created
# to stop — the XP formula lived in two places, they disagreed, and the
# sanitiser started rewriting honest saves.
#
# Still exports, so a scene can still tune them. Nothing does today, and
# anything that did would be tuning away from the number the server checks
# against — which is worth knowing before you do it.
@export var regen_percent_per_second: float = PlayerStats.REGEN_PERCENT_PER_SECOND

# Floor for small pools. Set to the old flat rate, so nothing in the game
# regenerates any slower than it did before this change — only faster.
@export var regen_minimum_per_second: float = PlayerStats.REGEN_MINIMUM_PER_SECOND

@export var idle_threshold: float = PlayerStats.REGEN_IDLE_THRESHOLD

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

# WHAT THIS CHARACTER IS WEARING: {slot_name: item_id}, e.g.
# {"weapon": "ironsword", "helm": "ironhelm"}. An absent key is an empty slot;
# there is no "" placeholder, because a dictionary already has a word for that.
#
# A SLOT POINTS AT A BAG ITEM. IT DOES NOT HOLD ONE.
#
# The alternative — moving the item out of the backpack into an equipment
# container — was considered and rejected, and the reason is that it creates a
# second place an item can be. Every path that touches the bag then has to
# remember the other one: selling, banking, dropping, trading, the death
# penalty, the save. Miss one and the item is in both places or neither, which
# is the duplication bug this genre ships at least once.
#
# Holding only the id means there is nothing to keep in step. Your sword is in
# your bag whether or not you are swinging it. Equipping is one assignment,
# unequipping is one erase, and swapping moves nothing at all.
#
# THE PRICE, PAID IN ONE PLACE. A slot can name an item you no longer have —
# you sold the sword you were holding. CharacterData is where that is
# reconciled, in save_character_state() and in the sanitizer, because those are
# the two moments the bag is actually known: player.inventory_data is assigned
# once at load and never updated, since the live bag lives in the HUD's
# inventory container. A prune written here would read a stale list.
#
# Persisted per character slot by CharacterData, and forwarded to the server's
# saves.equipment column by ServerStorage — the same treatment active_pet_id
# gets above, for the same reason: it is a String map, not an int stat, so it
# falls outside the SAVEABLE_STATS loop and has to be handled explicitly.
var equipped: Dictionary = {}


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

	# WHAT THIS USED TO BE, AND WHY IT WAS WRONG:
	#
	#     CharacterData.load_character_state(self)
	#     _recompute_max_stats()
	#     _fill_all_resources()          # hp = max_hp, unconditionally
	#
	# The load read your saved health and the next line but one threw it away.
	# _ready() runs on every scene load, so walking from town to the field at
	# 1 hp put you in the field at full — and characterdata.gd's own comment
	# had already noticed, in passing, that the saved values have "zero live
	# effect". It was an ordering accident, not a design.
	#
	# It made three other things meaningless at once: potions, because a door
	# heals better; the death penalty, because dying is only expensive if
	# damage persists; and the server's stored hp, which /api/player/status now
	# reconciles against regeneration and authorised potions — a check that
	# cannot mean anything while the client refills on a loading screen.
	#
	# THE RULE THAT REPLACES IT: what was full stays full, what was hurt stays
	# hurt.
	#
	# It has to be "was it full", not "is there a save", because a brand new
	# character is not a blank slot — characterdata.gd seeds one from
	# SAVEABLE_STATS with hp 100 and max_hp 100, and _recompute_max_stats()
	# below is about to raise that ceiling to whatever the class curve says.
	# Testing for a saved value would start every new warrior on 100 of 180.
	# Testing for fullness gets them to 180, keeps a wounded character's exact
	# number, and survives a levelled-up or rebalanced maximum for free.
	var was_full_hp: bool = hp >= max_hp
	var was_full_mana: bool = mana >= max_mana
	var was_full_stamina: bool = stamina >= max_stamina

	_recompute_max_stats()

	# ZERO MEANS DEAD, AND IT SURVIVES A LOGOUT NOW.
	#
	# WHAT THIS USED TO BE:
	#
	#     hp = max_hp if (was_full_hp or hp <= 0) else clampi(hp, 0, max_hp)
	#
	# A character stored at 0 stood up at full, on the reasoning that the
	# alternative is spawning a corpse that dies again on its first frame. The
	# reasoning was right about the symptom and wrong about the cure, and it
	# cost the whole death penalty.
	#
	# BECAUSE DYING WAS A SCREEN, NOT A STATE. gameover.gd applies the penalty
	# — carry gold cleared, carry items cleared — only when you press "return to
	# character select". Logging out never reached it. So: die, quit, log back
	# in, and _ready() handed the character back alive and whole with every item
	# still in the bag. Confirmed by doing it.
	#
	# It also made the server's healing reconciler fire on an honest player: a
	# zero-to-full refill with no kill, no revive and no consume behind it looks
	# exactly like a client inventing health, because from the server's side
	# that is all it is. See E-9.
	#
	# THE SERVER ALREADY KNEW. Stored hp is 0 and has been all along — nothing
	# new has to be recorded or trusted. The client simply has to stop papering
	# over it, which is what the line below does.
	#
	# _died_before_load is read by the world scene one frame later, because
	# changing scenes from inside _ready() is how you get "Parent node is busy
	# setting up children". The game over screen is the only way out of hp 0,
	# whether you got there by dying just now or by logging back in afterwards.
	_died_before_load = hp <= 0
	hp = max_hp if was_full_hp else clampi(hp, 0, max_hp)
	mana = max_mana if (was_full_mana or mana < 0) else clampi(mana, 0, max_mana)
	stamina = max_stamina if (was_full_stamina or stamina < 0) else clampi(stamina, 0, max_stamina)

	# NEW: re-spawn the active pet (if any) on every scene load — this is
	# what actually makes a pet survive a scene transition, since the old
	# pet node itself gets freed along with the rest of the old scene.
	# active_pet_id is just a string (an item_id), not a node reference,
	# which is exactly why it CAN survive — see CharacterData.gd's
	# save_character_state()/load_character_state() for where it persists.
	_restore_active_pet()

	# THE MAP FILLS IN AS YOU WALK. Deferred because current_scene is not
	# necessarily set while a child's _ready() is running, and WorldMap reads
	# it to work out which area this is.
	_prepare_world_map.call_deferred()

	if has_node("animatedsprite2d"):
		$animatedsprite2d.play("idledown")
		if not $animatedsprite2d.animation_finished.is_connected(_on_animatedsprite2d_animation_finished):
			$animatedsprite2d.animation_finished.connect(_on_animatedsprite2d_animation_finished)

	_setup_carried_light()


# =============================================================================
# CARRIED LIGHT  (a torch that follows the player through dark scenes)
# =============================================================================
#
# ATTACHED IN CODE, NOT IN THE FOUR CLASS SCENES, on purpose. warrior, mage,
# tank and healer are separate .tscn files; a light placed in each is four
# copies of one decision, and the first tuning pass would drift three of them.
# Here it is instanced once and every class inherits it.
#
# ON ONLY IN DARK SCENES, decided automatically. A scene that wants to be dark
# darkens itself with a CanvasModulate (the crypt's cryptambience, and now the
# field). If the current scene has one, the player lights their surroundings;
# if it does not, the light stays off so a fully-lit town is not washed out by
# an additive light nobody asked for. No per-scene wiring, nothing to keep in
# sync - add a CanvasModulate to a new dark room and the player is lit there too.

	# ALREADY DEAD WHEN LOADED -> STRAIGHT TO THE SCREEN.
	#
	# DEFERRED, because changing scenes from inside _ready() gives you "Parent
	# node is busy setting up children" - the tree is mid-build and cannot be
	# torn down from within it.
	#
	# is_dying IS SET TOO, and it is doing real work rather than decorating: it
	# is one frame from here to the deferred call, and a character sitting at 0
	# hp for a frame is a character _physics_process() will happily regenerate,
	# move, or run take_damage() on. The flag is what every one of those already
	# checks.
	if _died_before_load:
		is_dying = true
		if OS.is_debug_build():
			print("[PLR]  loaded at 0 hp - dead before this session, to game over")
		call_deferred("_change_to_game_over")

func _setup_carried_light() -> void:
	if not is_instance_valid(_carried_light):
		_carried_light = PLAYER_LIGHT_SCENE.instantiate()
		add_child(_carried_light)
	_carried_light.enabled = false
	# The scene's CanvasModulate may not be in the tree the same frame this
	# player is added to it, so decide one idle frame later, once the world
	# scene is fully built. Each world scene spawns a fresh player, so this
	# re-runs on every scene change - which is exactly what re-checks the dark.
	_update_carried_light.call_deferred()


func set_carried_light(on: bool) -> void:
	# Public override for anything that should force the light regardless of the
	# scene - a torch item, a scripted beat. Leave it unused and scenes decide.
	if is_instance_valid(_carried_light):
		_carried_light.enabled = on


func _update_carried_light() -> void:
	if is_instance_valid(_carried_light):
		_carried_light.enabled = _scene_is_dark()


func _scene_is_dark() -> bool:
	var scene: Node = get_tree().current_scene
	return scene != null and _first_canvas_modulate(scene) != null


func _first_canvas_modulate(node: Node) -> CanvasModulate:
	if node is CanvasModulate:
		return node
	for child in node.get_children():
		var found: CanvasModulate = _first_canvas_modulate(child)
		if found != null:
			return found
	return null


func _physics_process(_delta):
	# WAS ANYONE THERE THIS FRAME. Stamped before every early return, for the
	# same reason the attack poll below is: a question about the player, not
	# about the character, and dying or being locked out does not make someone
	# leave the keyboard.
	if Input.is_anything_pressed():
		_last_input_ms = Time.get_ticks_msec()

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
	# NOT WHILE TYPING. Movement is polled, and a poll does not know that a
	# text box has the keyboard - so typing "wade" into a search field walked
	# the character up, left, right and away. The bank's gold box always had
	# this; the staff panel, with a search box and a ban reason, made it
	# impossible to miss. Key EVENTS were already safe: a focused LineEdit
	# consumes them before _unhandled_input sees them. Only the poll leaked.
	if not _typing_in_ui():
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

	# WHO AM I STANDING INSIDE. Sampled once and reused for both halves of the
	# wade, so the bodies that slow you down are exactly the bodies you displace.
	var wading: Array[CharacterBody2D] = _enemies_overlapping()
	if not wading.is_empty():
		velocity *= _wade_drag_factor(wading.size())

	# Captured BEFORE the move so agility can be paid on ground actually
	# covered — see _accrue_agility_from_travel() below.
	var position_before: Vector2 = global_position

	move_and_slide()
	_displace_wading_enemies(wading, _delta)

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
# WADING THROUGH ENEMIES
# =============================================================================
#
# Neither side is solid to the other: the player's mask does not name the
# enemies layer and no enemy's mask names the player layer. You walk through
# them, and none of the weight below comes from the physics response, because
# there is no collision to respond to.
#
# THAT IS WHY THIS IS A QUERY AND NOT A COLLISION CALLBACK. The function this
# replaced looped over get_slide_collision(), which reports nothing once the
# masks stopped overlapping - so it had quietly become a no-op that still ran
# every frame. Enemies felt like fog, and the code responsible for their weight
# was present, called, and doing nothing. A no-op is harder to notice than a
# crash.
#
# Anything that should not be shoved - the boss, a scripted encounter - goes in
# the "unpushable" group and is skipped.

# Physics layer 4, "enemies" in Project Settings. Layers are 1-indexed in the
# inspector and 0-indexed as bits, so layer 4 is bit 3 is value 8.
const ENEMY_PHYSICS_LAYER := 8

# Built once and mutated. A CircleShape2D is a Resource with a shape on the
# physics server behind it; allocating one per physics frame is 80 a second.
var _wade_shape: CircleShape2D = null
var _wade_query: PhysicsShapeQueryParameters2D = null


func _enemies_overlapping() -> Array[CharacterBody2D]:
	var found: Array[CharacterBody2D] = []
	if enemy_wade_radius <= 0.0:
		return found

	if _wade_query == null:
		_wade_shape = CircleShape2D.new()
		_wade_query = PhysicsShapeQueryParameters2D.new()
		_wade_query.shape = _wade_shape
		_wade_query.collision_mask = ENEMY_PHYSICS_LAYER
		_wade_query.collide_with_bodies = true
		_wade_query.collide_with_areas = false
		# Typed so the assignment does not go through a Variant conversion -
		# exclude is Array[RID] and an untyped literal warns.
		var excluded: Array[RID] = [get_rid()]
		_wade_query.exclude = excluded

	# Only written when it actually changes, so the export stays live-tunable
	# in the remote inspector without a server round trip every frame.
	if not is_equal_approx(_wade_shape.radius, enemy_wade_radius):
		_wade_shape.radius = enemy_wade_radius
	_wade_query.transform = Transform2D(0.0, global_position)

	# THE GROUP CHECK IS NOT REDUNDANT WITH THE MASK. Anything sharing the
	# enemies layer comes back from this query, including a pet that ends up on
	# the wrong layer, and only things actually in the "enemies" group should
	# weigh you down or be pushed aside.
	for hit in get_world_2d().direct_space_state.intersect_shape(_wade_query, 16):
		var body := hit.get("collider") as CharacterBody2D
		if body == null or not is_instance_valid(body):
			continue
		if not body.is_in_group("enemies"):
			continue
		if body.is_in_group("unpushable"):
			continue
		found.append(body)
	return found


func _wade_drag_factor(body_count: int) -> float:
	var drag: float = enemy_wade_drag + enemy_wade_drag_per_extra * float(body_count - 1)
	return clampf(1.0 - drag, enemy_wade_min_speed, 1.0)


func _displace_wading_enemies(bodies: Array[CharacterBody2D], delta: float) -> void:
	# FROM YOUR SPEED, NOT THEIRS - see enemy_wade_push_ratio. A ratio below 1.0
	# means you always out-pace what you displace, so there is nothing to ride,
	# and it can afford to lose to an enemy walking back in because losing means
	# wading past it rather than being stopped by it.
	var push_speed: float = maxf(velocity.length() * enemy_wade_push_ratio, enemy_wade_idle_push)
	if push_speed <= 0.0:
		return

	var travel: Vector2 = velocity.normalized()

	for body in bodies:
		# move_and_slide() ran between the query and here, and queue_free() is
		# deferred, so something killed this frame is still in this array and
		# still passes is_instance_valid() until the frame ends.
		if not is_instance_valid(body):
			continue

		var away: Vector2 = body.global_position - global_position

		# Dead centre, which happens constantly with a pack converging on one
		# point. Choosing a direction per frame would flip-flop and cancel
		# itself out, so it is pinned to the instance id - arbitrary, and stable
		# for as long as that body lives.
		if away.length_squared() < 0.0001:
			var angle: float = float(int(body.get_instance_id()) % 360) * (PI / 180.0)
			away = Vector2.RIGHT.rotated(angle)
		away = away.normalized()

		# PART AROUND THE SHOULDERS, DO NOT BULLDOZE. Straight-away push from a
		# head-on walk points along your own travel direction, which shoves the
		# body ahead of you and keeps it in front the whole way. The sideways
		# component sends it to whichever side it is already leaning toward.
		var tangent := Vector2.ZERO
		if travel != Vector2.ZERO:
			tangent = travel.orthogonal()
			if tangent.dot(away) < 0.0:
				tangent = -tangent

		# move_and_collide() rather than assigning global_position, so a pushed
		# body still respects walls - it cannot be shoved through geometry, it
		# just stops once it is pinned against something solid.
		var push: Vector2 = (away + tangent * enemy_wade_sidestep).normalized()
		body.move_and_collide(push * push_speed * delta)


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
# The tier table and the lookup live in PlayerStats. A `const DEFENSE_TIERS`
# alias used to sit here so `Player.DEFENSE_TIERS` would resolve for outside
# readers; the comment claimed the stats screen was one, and it is not —
# statsscreen.gd computes its own combat rows and never touched it. Nothing
# read the alias, so it is gone. Read PlayerStats.DEFENSE_TIERS directly.
func _get_defense_tier() -> Dictionary:
	return PlayerStats.defense_tier(defense)


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


# =============================================================================
# THE MAP
# =============================================================================

# The last tile the map was told about. reveal_around() walks a 15x15 block,
# and `moved` fires every physics frame while a key is held — so it is only
# worth calling when the character has actually crossed into a new tile, which
# at walking pace is a few times a second rather than sixty.
#
# Deliberately a coordinate no world contains, so the first step after a load
# always counts as a change.
var _map_last_tile: Vector2i = Vector2i(-2147483648, -2147483648)


func _prepare_world_map() -> void:
	if not WorldMap.ensure_built():
		return

	# REVEALED WHERE YOU ARE STANDING, before taking a step. Otherwise a player
	# who logs in and opens the map immediately sees a black rectangle and
	# concludes it is broken.
	WorldMap.reveal_around(global_position)
	_map_last_tile = WorldMap.tile_at(WorldMap.area_id(), global_position)

	# `moved` was declared, emitted every frame of movement, and connected to
	# nothing at all — tools/audit.py lists it under signals nothing connects.
	# This is its first listener.
	if not moved.is_connected(_on_moved_for_map):
		moved.connect(_on_moved_for_map)


func _on_moved_for_map(at: Vector2, _direction: String) -> void:
	var area: String = WorldMap.area_id()
	if area == "":
		return
	var tile: Vector2i = WorldMap.tile_at(area, at)
	if tile == _map_last_tile:
		return
	_map_last_tile = tile
	WorldMap.reveal_around(at, area)


func _spawn_floating_label(amount: int, type: int, element: int = Element.Type.NONE) -> void:
	# DAMAGE NUMBERS ONLY, and only the damage ones.
	#
	# A player who turns these off is asking not to see a screen full of red
	# numbers while being hit by six things. They are not asking to stop being
	# told they levelled up, or that a potion healed them for 140 — those come
	# through this same function as LEVELUP, SKILLUP, HEAL and NOTICE, and
	# silencing them with the same switch would turn a preference into a
	# feature being taken away.
	if type == FloatingLabel.Type.DAMAGE and not Settings.get_value("damage_numbers"):
		return

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
	# Tint before showing, so the first rendered frame is already the right
	# colour rather than flicking from white on the second.
	if element != Element.Type.NONE and lbl is CanvasItem:
		(lbl as CanvasItem).modulate = Element.colour_for(element)

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


func take_damage(amount: int, element: int = Element.Type.NONE) -> void:
	if is_dying:
		return

	_set_active()

	# NEW: tiered defense reduction — see PlayerStats.DEFENSE_TIERS. XP gain
	# further down still uses the RAW incoming amount, not the reduced
	# one, so higher defense doesn't also slow down future defense XP —
	# that would create a self-limiting feedback loop nobody asked for.
	# maxi(1, ...) guarantees chip damage always gets through — even at
	# the 50% cap, a hit can never be reduced to zero.
	# NEW: ARMOUR, ON TOP OF THE DEFENSE TIER AND MULTIPLIED WITH IT.
	#
	# Two percentages that ADD reach 100% and a character stops taking damage.
	# Two that MULTIPLY each remove a share of what is left, so an ember-plated
	# warrior at Trained defense takes 0.80 x 0.55 = 44% of an incoming hit and
	# no amount of gear ever reaches zero. The maxi(1, ...) below is still the
	# last guarantee underneath both.
	#
	# The defense tier is what you EARN by being hit; armour is what you BUY or
	# find. Keeping them as separate factors is what lets either be tuned
	# without silently retuning the other — see PlayerStats.ARMOUR_HALF_POINT
	# for the scale, and note that enemy damage was deliberately NOT raised to
	# compensate: a geared player taking less is the entire point of armour.
	var reduction: float = _get_defense_tier()["reduction"]
	var armour: float = PlayerStats.armour_reduction(equipped_armor_value())
	var reduced_amount: int = maxi(1, int(amount * (1.0 - reduction) * (1.0 - armour)))

	hp = clamp(hp - reduced_amount, 0, max_hp)
	took_damage.emit(reduced_amount, Element.name_for(element))

	# THE NUMBER WEARS THE ELEMENT THAT CAUSED IT, which is the whole point of
	# carrying one this far. A player standing in a field of six recoloured
	# slimes needs to know which of them is actually hurting, and a white "12"
	# tells them nothing that a blue "12" does not tell them instantly.
	#
	# Physical stays the label's own default colour — an unremarkable hit
	# should look unremarkable.
	_spawn_floating_label(reduced_amount, 0, element)

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
	# already driving damage tiers (PlayerStats.DEFENSE_TIERS) — a Novice takes
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

# TRUE WHEN THIS CHARACTER LOADED ALREADY DEAD, which is a different thing
# from dying while you are playing. is_dying drives the death animation; this
# drives skipping straight to the screen, because the death already happened
# and its animation played in a session that has ended.
var _died_before_load: bool = false


func died_before_load() -> bool:
	return _died_before_load


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
	# THE ONE THAT MATTERS MOST for the AFK guard, and the easiest to miss:
	# combat.gd grants character XP and attack XP from the same kill, in two
	# lines, and gating only the skill one would have left levelling wide open.
	# See _xp_is_earned() for what this is protecting against.
	if not _xp_is_earned():
		return

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


func xp_needed_for_skill_id(skill_id: String, skill_level: int) -> int:
	# THE FACTOR COMES FROM THE TABLE, NOT FROM THE CALL SITE.
	#
	# Each gain_*_xp() below used to pass its own literal - 1.25 for attack,
	# 1.12 for fishing, and so on - while GameConstants.SKILL_XP_GROWTH held the
	# same six numbers and was the copy exported to the server. Two hand-kept
	# copies of one pacing decision, with nothing checking they agreed.
	#
	# That is the exact shape of the bug this project has already paid for once:
	# gameconstants.gd's own header records the character XP formula living in
	# two places, drifting, and the sanitizer rewriting honest saves - 1,636 XP
	# became 52 million at level 20. The skill curves had quietly grown the same
	# problem, and it got worse the moment the server started granting attack,
	# fishing and cooking: a literal drifting here would make the bar the player
	# watches disagree with the level the server actually stores.
	#
	# The fallback is PlayerStats.SKILL_XP_FACTOR, which is also what
	# gamedata.py falls back to for an unlisted skill, so an id missing from the
	# table is paced identically on both sides rather than two different ways.
	return PlayerStats.xp_needed_for_skill(
		skill_level,
		GameConstants.SKILL_XP_BASE,
		float(GameConstants.SKILL_XP_GROWTH.get(skill_id, PlayerStats.SKILL_XP_FACTOR)))


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


func hasten(seconds: float) -> float:
	# A COOLDOWN, SHORTENED BY AGILITY — and the only place that division
	# happens, which is the whole reason it exists.
	#
	# get_attack_speed_multiplier() was defined, unit tested, and called by
	# nothing on the player. pet.gd found it and used it, so agility made your
	# PET attack faster while you attacked at exactly the base rate. The stat
	# sold one thing and delivered it to somebody else.
	#
	# Four classes gate their attacks on four different exported values —
	# attack_lock_duration, spell_cooldown, shot_cooldown, aura_tick — so the
	# obvious fix is four divisions in four files, which is four chances to
	# forget one and no way to notice which. They all come through here.
	#
	# GUARDED AGAINST A ZERO MULTIPLIER. It cannot be zero today, because
	# attack_speed_multiplier() clamps to at least 1.0 — but dividing by a stat
	# is not the place to depend on someone else's clamp holding forever.
	var multiplier: float = get_attack_speed_multiplier()
	if multiplier <= 0.0:
		return seconds
	return seconds / multiplier


# =============================================================================
# SKILL XP
# =============================================================================

# =============================================================================
# THE AFK GUARD
# =============================================================================
# WHAT THIS CLOSES. Summon a pet, walk into a corner of the navmesh where
# enemies can reach you but cannot surround you, and leave. The pet keeps
# killing; combat.gd grants the kill's attack XP to its owner; the enemies
# keep hitting you and take_damage() grants defense XP for each hit; and
# percentage-based regen refills the chip damage between swings. Nothing about
# that loop needs a person in the chair, and it runs until the client is
# closed.
#
# THE REGEN IS NOT THE BUG, which is worth saying because it looks like it.
# take_damage() calls _set_active(), so being hit already stops regen dead and
# discards part-earned points — regen is strictly a between-fights mechanic and
# it behaves like one. It just happens that an enemy landing a hit every couple
# of seconds leaves gaps longer than the one-second idle threshold, and a
# character with several hundred max HP refills faster in those gaps than a
# low-level enemy empties it. Tightening that would make ordinary combat harsher
# for everyone in order to punish something only the AFK case does.
#
# So the guard is on the REWARD, not on the survival. Skill XP stops accruing
# once nobody has touched an input for a while. It changes nothing for anyone
# playing — three minutes without a single keypress is not a lull in a fight,
# it is an empty chair — and the pet still fights, the loot still drops, and
# the character still survives. You simply stop levelling for being absent.
#
# HONEST ABOUT WHAT IT DOES NOT STOP: a weight on a key, or an autoclicker,
# still reads as input. That is a much higher bar than walking away, and the
# real answer for it is server-side kill validation, which this client cannot
# do alone — see the note about unverified kill events in the server work.
const AFK_XP_CUTOFF_SECONDS: float = 180.0

var _last_input_ms: int = 0
var _afk_notified: bool = false


func seconds_since_input() -> float:
	# Time.get_ticks_msec() starts at 0, and so does _last_input_ms, so a
	# character who has genuinely never pressed anything reads as idle from
	# the moment the game has been open longer than the cutoff. That is the
	# correct answer rather than an edge case to paper over.
	return float(Time.get_ticks_msec() - _last_input_ms) / 1000.0


func is_afk() -> bool:
	return seconds_since_input() >= AFK_XP_CUTOFF_SECONDS


func _xp_is_earned() -> bool:
	# Called by all three gain_*_xp() functions. Says so once and then stays
	# quiet: a notice every time an enemy hit an absent player would be its own
	# kind of spam, and the one line is for the person who comes back and
	# wonders why nothing moved.
	if not is_afk():
		_afk_notified = false
		return true

	if not _afk_notified:
		_afk_notified = true
		show_notice("Away — no skill XP")
	return false


func gain_attack_xp(amount: int) -> void:
	if not _xp_is_earned():
		return
	# NEW: scaled by skill_proficiency["attack"] — this is what makes
	# attack XP universal (any class can call this) while still letting
	# warrior climb it faster than everyone else. see SKILL PROFICIENCY
	# section above.
	var scaled_amount: int = maxi(1, int(amount * skill_proficiency.get("attack", 1.0)))
	attack_xp += scaled_amount
	while attack_xp >= attack_xp_next:
		attack += 1
		attack_xp -= attack_xp_next
		attack_xp_next = xp_needed_for_skill_id("attack", attack)
		_spawn_skillup_popup("attack", attack)
	CharacterData.save_character_state(self)


func gain_defense_xp(amount: int) -> void:
	if not _xp_is_earned():
		return
	# NEW: scaled by skill_proficiency["defense"] — take_damage() above
	# already grants this universally to every class; this is what lets
	# tank climb it faster without touching take_damage() at all.
	var scaled_amount: int = maxi(1, int(amount * skill_proficiency.get("defense", 1.0)))
	var tier_before: String = _get_defense_tier()["name"]
	defense_xp += scaled_amount
	while defense_xp >= defense_xp_next:
		defense += 1
		defense_xp -= defense_xp_next
		defense_xp_next = xp_needed_for_skill_id("defense", defense)
		_spawn_skillup_popup("defense", defense)
	# NEW: a tier crossing (Novice -> Trained -> ... -> Unbreakable) is a
	# bigger moment than an ordinary skill level-up, so it gets its own,
	# more prominent popup on top of the normal one above.
	var tier_after: String = _get_defense_tier()["name"]
	if tier_after != tier_before:
		_spawn_defense_tier_popup(tier_after)
	CharacterData.save_character_state(self)


func gain_agility_xp(amount: int) -> void:
	# Gated like the rest, for consistency rather than because this one is
	# exploitable: agility XP comes from sprinting, which means holding a key,
	# which is already the thing is_afk() measures. Left ungated it would be
	# the one skill that still climbed while away, which is the kind of
	# inconsistency that later reads as an oversight rather than a decision.
	if not _xp_is_earned():
		return
	agility_xp += amount
	while agility_xp >= agility_xp_next:
		agility += 1
		agility_xp -= agility_xp_next
		agility_xp_next = xp_needed_for_skill_id("agility", agility)
		_spawn_skillup_popup("agility", agility)
	CharacterData.save_character_state(self)


func gain_magic_xp(amount: int) -> void:
	if not _xp_is_earned():
		return
	# NEW: scaled by skill_proficiency["magic"] — this is what lets
	# mage/healer climb magic faster than a class that only occasionally
	# lands a spell hit.
	var scaled_amount: int = maxi(1, int(amount * skill_proficiency.get("magic", 1.0)))
	magic_xp += scaled_amount
	while magic_xp >= magic_xp_next:
		magic += 1
		magic_xp -= magic_xp_next
		magic_xp_next = xp_needed_for_skill_id("magic", magic)
		_spawn_skillup_popup("magic", magic)
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


func _typing_in_ui() -> bool:
	# A text field that is visible and can be typed into holds the keyboard.
	# Read-only fields do not count - nothing is being typed into them.
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused == null or not focused.is_visible_in_tree():
		return false
	if focused is LineEdit:
		return (focused as LineEdit).editable
	if focused is TextEdit:
		return (focused as TextEdit).editable
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not _staff_debug_allowed():
		return

	if event is InputEventKey and event.pressed:
		# FUNCTION KEYS, UNMODIFIED. They collide with nothing a player presses,
		# so they stay exactly where the muscle memory is.
		#
		# NOT F8: that is the editor's "Stop running project" shortcut and it
		# kills the game even when the game window has focus.
		match event.keycode:
			KEY_F1: _debug_give_item("tinyhealthpotion", 5)
			KEY_F2: _debug_give_item("ironsword", 1)
			KEY_F3: _debug_give_item("bushamulet", 1)
			KEY_F4: _debug_give_item("smallamountofgold", 1)
			KEY_F5: _debug_give_lusions(20)
			KEY_F6: _debug_give_item("lusions", 5)
			KEY_F7: _debug_give_item("tinymanapotion", 5)
			KEY_F9:  gain_attack_xp(30)
			KEY_F10: gain_defense_xp(30)
			KEY_F11: gain_agility_xp(30)
			KEY_F12: gain_magic_xp(30)

		# LETTERS, BEHIND CTRL — and that modifier is the whole fix.
		#
		# These used to be bare letters, which meant the debug block owned I, M,
		# B, K, R and the P O I U Y T row outright. M was the worst of them: it
		# was ALSO the minimap_toggle action, so opening the map drained thirty
		# mana, and nothing anywhere said the two were the same key.
		#
		# A player never reaches any of this - _staff_debug_allowed() gates the
		# whole function on a debug build AND a staff role - but the letters were
		# unavailable to the KEYMAP, which is a different thing from unavailable
		# to a player. inventory_toggle could not be I while this owned it.
		#
		# ONE RULE, NOT A NEW LAYOUT: every grant keeps its letter and gains
		# Ctrl. Nothing has to be relearned, and the unmodified letters go back
		# to the game.
		if not event.ctrl_pressed:
			return

		match event.keycode:
			# PETS — the P O I U Y T row, one key per pet, reading leftward,
			# plus B for the boss pet (see below).
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
			KEY_P: _debug_give_item("petsniper", 1)
			KEY_O: _debug_give_item("petmage", 1)
			KEY_I: _debug_give_item("petelectricsprite", 1)
			KEY_U: _debug_give_item("petfiresprite", 1)
			KEY_Y: _debug_give_item("petpoisonslimesmall", 1)
			KEY_T: _debug_give_item("petpoisonslimelarge", 1)
			# B FOR BOSS, deliberately off the row. The row above reads
			# leftward from P and stops at T because R is already the fishing
			# kit, so there is no seventh key to continue it with. Shuffling
			# six bindings that are already in muscle memory to gain one slot
			# is a worse trade than giving the newest pet a mnemonic of its
			# own.
			#
			# Same rule as the rest of the row: this grants the ITEM, not a
			# pet node. petboss is the first pet whose .tres, .tscn and
			# projectile were all authored at once, so it is exactly the case
			# a direct-spawn helper would have hidden — if the item is
			# missing from ItemRegistry, this key does nothing and says so.
			KEY_B: _debug_give_item("petboss", 1)
			# R FOR ROD — the whole gathering loop from one key.
			#
			# A rod alone tests nothing: fishingspot.gd checks the rod FIRST and
			# the bait second, so without worms you get as far as "You need worms
			# for bait" and stop. The two items are one tool, so they are one key.
			#
			# The iron rod specifically, because it is tier 1 and usable at
			# fishing level 1 — a fresh character can cast with it immediately.
			# The other four (jade, cobalt, amethyst, ember) are the tier ladder
			# and gate which fish bite; grant those by id when testing the ladder
			# rather than the loop.
			#
			# THIS IS THE WHOLE COOKING TEST TOO. Cooking has no debug key of its
			# own and does not need one: raw fish only exist as something you
			# caught, so the honest way to get one into a firepit is to fish it
			# out first. Same reasoning as the pet row above — the key grants the
			# item and the real path does the rest.
			KEY_R: _debug_give_fishing_kit()
			# K FOR COOKED — three Mudfish and three Reef Clowns, which is the
			# cooking gate's easy case and its hardest one side by side.
			#
			# Granting a finished fish is not a hole in the gate, it is the hole
			# the gate was built for: a cooked fish arriving in a bag without
			# having been cooked there is exactly what a trade looks like. The
			# key stops at the bag; right-clicking is still the real path, and
			# _meets_requirements() gets the same look at it either way.
			KEY_K: _debug_give_cooked_fish()
			KEY_M:
				mana = max(mana - 30, 0)
				print("DEBUG: drained 30 mana (now %d)" % mana)


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


# =============================================================================
# EQUIPMENT
# =============================================================================
# THE SLOT NAMES ARE NOT WRITTEN OUT HERE. ItemData.slot_name() derives them
# from ItemData.EquipSlot itself, which is the only place on the client that
# knows what a slot is called — see the long note beside that function for why
# a second copy is a bug waiting rather than a convenience.

static func slot_name_for_item(item_id: String) -> String:
	# Which slot an item is worn in, or "" if it is not equipment at all.
	var data: ItemData = ItemRegistry.get_item(item_id)
	if data == null:
		return ""
	return ItemData.slot_name(int(data.equip_slot))


func equipped_id(slot_name: String) -> String:
	return str(equipped.get(slot_name, ""))


func equip_check(item_id: String) -> Dictionary:
	# MAY THIS CHARACTER WEAR THIS? The same three questions gamedata.py's
	# equip_check() asks, in the same order, returning the same shape:
	#
	#     {"ok": false, "reason": "unknown"}                  no such item
	#     {"ok": false, "reason": "notgear"}                  not equipment
	#     {"ok": false, "reason": "class", "allowed": [...]}  wrong class
	#     {"ok": false, "reason": "level", "needs": N}        too low
	#     {"ok": true,  "slot": "helm"}
	#
	# TWO COPIES OF ONE RULE, DELIBERATELY, and the same arrangement
	# inventoryscreen.gd already uses for consumables: the client refusing is a
	# courtesy — it greys the slot out and says why — and the server refusing
	# is the rule. If these two ever disagree the server wins, and the symptom
	# is a save that comes back 400 rather than a stat nobody earned.
	#
	# THE SLOT ITSELF IS NOT A QUESTION HERE. The server checks that a sword
	# was not sent for the helm slot because it receives both halves and has to
	# assume neither. This function derives the slot FROM the item, so there is
	# nothing to disagree with.
	var data: ItemData = ItemRegistry.get_item(item_id)
	if data == null:
		return {"ok": false, "reason": "unknown"}

	var slot_name: String = ItemData.slot_name(int(data.equip_slot))
	if slot_name == "":
		return {"ok": false, "reason": "notgear"}

	# AN EMPTY required_classes MEANS ANYONE. Rings and amulets are shared by
	# every class, so emptiness is tested before membership — reading an empty
	# list as "nobody" would take all the jewellery away from everybody.
	if not data.required_classes.is_empty():
		var class_id: String = CharacterData.active_class_id()
		if not data.required_classes.has(class_id):
			return {"ok": false, "reason": "class", "allowed": data.required_classes}

	if level < data.required_level:
		return {"ok": false, "reason": "level", "needs": data.required_level}

	return {"ok": true, "slot": slot_name}


func equip(item_id: String) -> bool:
	# Wearing something is one assignment. WHAT WAS THERE IS NOT PUT ANYWHERE,
	# because it never left the bag to begin with: a slot holds an item_id, not
	# the item, so swapping a sword for a better sword moves nothing and the
	# old one is still sitting where it was.
	#
	# That is the whole reason the "slots point at a bag item" shape was chosen
	# over moving items into an equipment container. There is no second place
	# for an item to be, so there is no way for one to be in both or neither —
	# which is the bug every inventory system in this genre ships at least once.
	var verdict: Dictionary = equip_check(item_id)
	if not verdict["ok"]:
		return false
	equipped[str(verdict["slot"])] = item_id
	return true


func unequip(slot_name: String) -> String:
	# Returns what came off, or "" if the slot was already empty. Nothing is
	# given back because nothing was taken.
	var was: String = equipped_id(slot_name)
	if was != "":
		equipped.erase(slot_name)
	return was


func equipped_weapon_damage() -> int:
	# THE MIDDLE OF THE BAND, not a hit. For tooltips and for anything that
	# wants to compare two weapons without rolling dice at them.
	var data: ItemData = ItemRegistry.get_item(equipped_id("weapon"))
	if data == null:
		return 0
	return data.damage


func equipped_weapon_range() -> Vector2i:
	# What a tooltip should print: "15 - 25", the band a hit actually lands in.
	var data: ItemData = ItemRegistry.get_item(equipped_id("weapon"))
	if data == null:
		return Vector2i.ZERO
	return PlayerStats.weapon_damage_range(data.damage, data.damage_spread)


func weapon_damage_roll() -> int:
	# ONE HIT'S WORTH OF WEAPON, rolled fresh. 0 when nothing is equipped,
	# which is what makes the class's own base damage a real floor rather than
	# a formality — see PlayerStats.roll_weapon_damage().
	#
	# ADDED TO THE CLASS BASE BY ITS CALLER, never substituted for it. All four
	# classes read this the same way:
	#
	#     roundi((own_base + weapon_damage_roll()) * get_damage_multiplier())
	#
	# WHY ADDING RATHER THAN REPLACING, since warrior.gd's own comment used to
	# ask for a replacement: replacing means an unarmed character deals nothing,
	# which turns the first weapon into a power switch rather than an upgrade.
	# It also has no sensible answer for the tank, whose damage is an aura
	# ticking four times a second, or the healer, who fires ten shots a second
	# — a weapon's damage is one number and those are not one kind of hit.
	# ASKED ONLY WHEN THERE IS SOMETHING TO ASK ABOUT. An empty weapon slot is
	# the normal state of a character who has not found a sword yet, not a
	# lookup failure — but ItemRegistry.get_item("") cannot tell those apart
	# and warns about an unknown item_id, once per swing. At one swing a
	# second that is a warning per second, through a push_warning that carries
	# a full stack trace, for a character doing nothing wrong.
	var worn: String = equipped_id("weapon")
	if worn == "":
		return 0

	var data: ItemData = ItemRegistry.get_item(worn)
	if data == null:
		return 0
	return PlayerStats.roll_weapon_damage(data.damage, data.damage_spread)


func base_attack_damage() -> int:
	# WHAT THIS CLASS HITS FOR WITH ITS HANDS EMPTY. Overridden by all four;
	# the base answers 0, which reads as "this class has no attack".
	#
	# It exists so that nothing outside the class scripts has to know whether
	# the number is called base_melee_damage, damage_per_magic or aura_damage.
	# The equipment panel wants to print what the character actually hits for,
	# and asking it that question directly is better than teaching a UI panel
	# three different field names and which class uses which.
	return 0


func attack_damage_range() -> Vector2i:
	# WHAT ONE HIT ACTUALLY LANDS FOR, low and high, weapon and skills folded
	# in — the same arithmetic the four classes do at the moment they swing:
	#
	#     roundi((own_base + weapon_damage_roll()) * get_damage_multiplier())
	#
	# with the roll's two extremes in place of the roll. So the pair of numbers
	# the equipment panel prints are the pair a player will actually see pop
	# off an enemy, rather than a separate estimate that drifts the first time
	# one of the four is tuned.
	var low: int = base_attack_damage()
	var high: int = low

	var data: ItemData = ItemRegistry.get_item(equipped_id("weapon"))
	if data != null and data.damage > 0:
		var band: Vector2i = PlayerStats.weapon_damage_range(data.damage, data.damage_spread)
		low += band.x
		high += band.y

	var mult: float = get_damage_multiplier()
	return Vector2i(roundi(float(low) * mult), roundi(float(high) * mult))


func attack_period() -> float:
	# SECONDS BETWEEN ONE HIT AND THE NEXT, for this class. Overridden by all
	# four; the base answers 0.0, which every caller reads as "do not know".
	#
	# IT EXISTS FOR THE TOOLTIP, and for the reason the tooltip needs it: an
	# ember scepter carries 13 damage and an ember sword carries 100, for
	# almost the same gold, because one fires ten times a second and the other
	# swings once. Per-hit numbers make that pair look like a swindle and a
	# bargain. Damage per second makes them look like what they are, and this
	# is the number the division needs.
	#
	# ASKED OF THE LIVE CHARACTER rather than read from a table, so there is no
	# copy of the four cooldowns to drift out of step with the four @exports
	# that actually govern them.
	#
	# AGILITY IS FOLDED IN, because it is now actually delivered. Each override
	# returns hasten(its own cooldown), so the dps this feeds is the rate the
	# character really attacks at rather than the rate it would attack at with
	# no agility.
	#
	# This comment used to say the opposite, and said so accurately: the
	# multiplier existed, was tested, and nothing called it. The tooltip
	# deliberately under-promised rather than advertise a speed the game did
	# not deliver. Both halves are fixed together — see Player.hasten().
	return 0.0


func equipped_armor_value() -> int:
	# The defensive half, summed across every worn piece — read by take_damage()
	# through PlayerStats.armour_reduction(). A weapon contributes 0 and is
	# summed anyway rather than skipped: the day a sword carries armour, this
	# should not be the line that has to remember.
	var total: int = 0
	for slot_name in equipped:
		var data: ItemData = ItemRegistry.get_item(str(equipped[slot_name]))
		if data != null:
			total += data.armor_value
	return total


# BOTH _debug_* functions below repeat the gate rather than trusting it.
#
# They are already unreachable for a player, because the only thing that calls
# them is _unhandled_input(), which returns early - but that is a fact about a
# different function two hundred lines up, and it stops being true the moment
# anyone wires one of these to a button, a console command or a test. These hand
# out free items, free pets and free lusions; they should refuse on their own
# authority rather than inherit safety from their caller.
func _debug_give_fishing_kit() -> void:
	# AWAITED ONE AFTER THE OTHER, NOT FIRED TOGETHER.
	#
	# _debug_give_item() is a coroutine: it POSTs to /api/staff/grant and the
	# SERVER rewrites carry_items. Starting both without awaiting puts two grants
	# in flight against the same slot, and the two read-modify-writes can
	# interleave — both read the bag as it was, both append their own item, and
	# the second write lands on top of the first. You would get the worms and no
	# rod, intermittently, in a way that looks like the grant endpoint is flaky.
	#
	# The await makes the second request start after the first has been recorded.
	# Two round trips instead of one, for a debug key nobody presses in a loop.
	await _debug_give_item("ironfishingrod", 1)
	await _debug_give_item("fishingworm", 25)


func _debug_give_cooked_fish() -> void:
	# BOTH ENDS OF THE COOKING GATE IN ONE KEY, and it has to be both.
	#
	# A key that only granted the Reef Clown would prove a refusal happened; it
	# could not tell you whether the gate was reading cooking level or had simply
	# broken eating altogether. The Mudfish is the control: same type, same
	# handler, same restore_target, gate satisfied at cooking 1. If the Clown
	# refuses and the Mudfish heals, the gate is reading the number. If BOTH
	# refuse, _meets_requirements() is wrong and the log will say which check.
	#
	# WHY THIS DOES NOT BREAK KEY_R's RULE two hundred lines up. That comment says
	# cooking needs no debug key because raw fish should be fished for - and it is
	# right, for testing the cooking LOOP. This is not the loop. It hands over a
	# FINISHED fish, exactly as a trade would, which is the one way into the
	# player's bag that the gate exists to answer. Earning it would take fishing
	# 60 and cooking 70 and would test the gate no better.
	#
	# Awaited in sequence for the same reason as the fishing kit above: two
	# grants in flight against one slot can interleave and lose one.
	await _debug_give_item("cookedmudfish", 3)
	await _debug_give_item("cookedreefclown", 3)


func _debug_give_item(item_id: String, quantity: int) -> void:
	# THE SERVER GRANTS IT. THIS DOES NOT.
	#
	# This used to build an ItemStack and push it into the local grid, then save -
	# so the item existed because the client said so, and the rank check that
	# guarded the key lived in the client too. A patched build set Api.role to
	# "owner" and had the keys back; it did not even need to, since it could write
	# the item straight into the array it was about to send.
	#
	# POST /api/staff/grant is @require_role("mod") on the server, writes
	# carry_items itself, and records the grant in staff_actions. The decision is
	# now on the side of the wire the player does not control, and every staff
	# item has a line in the audit log next to the bans.
	#
	# _staff_debug_allowed() stays as the early exit. It stops an honest player
	# firing a request that would be refused; it is not what does the refusing.
	if not _staff_debug_allowed():
		return

	var res: Dictionary = await Api.post("/api/staff/grant", {
		"slot": CharacterData.active_character_index,
		"item_id": item_id,
		"quantity": quantity,
	})

	# PAST AN AWAIT. If this player was freed while the request was in flight
	# Godot drops the coroutine here and nothing below runs, which is the correct
	# outcome - but it means anything after this point must not assume the world
	# is as it was. Re-find the grid rather than holding a reference across it.
	if not res.get("ok", false):
		var status: int = int(res.get("status", 0))
		if status == 404:
			print("DEBUG: refused - not staff on the server, or no character in this slot")
		elif status == 409:
			print("DEBUG: refused - backpack full")
		elif status == 0:
			print("DEBUG: refused - server unreachable (%s)" % res.get("error", ""))
		else:
			print("DEBUG: refused - %d %s" % [status, res.get("error", "")])
		return

	var container: Node = _debug_inventory_container()
	if container == null:
		# The server HAS granted it. Saying so matters: the item is real and will
		# be there on the next load, and "nothing happened" would be a lie.
		print("DEBUG: granted %d x %s - reopen the inventory to see it" % [quantity, item_id])
		return

	container.load_server_array(res.data.get("inventory", []))
	print("DEBUG: granted %d x %s" % [quantity, item_id])


func _debug_inventory_container() -> Node:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		print("DEBUG: HUD not found in 'hud' group")
		return null
	if hud.inventory_screen == null:
		print("DEBUG: open the inventory at least once before using debug keys")
		return null
	return hud.inventory_screen.get_node_or_null("%inventorycontainer")


func _debug_give_lusions(amount: int) -> void:
	if not _staff_debug_allowed():
		return
	add_lusions(amount)
	print("DEBUG: gave %d lusions (now %d total)" % [amount, lusions])
