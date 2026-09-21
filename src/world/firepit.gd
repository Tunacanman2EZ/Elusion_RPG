# firepit.gd — world-placed interactable that the player can light and cook at.
#
# state model:
# - lit:   flame animation playing, interact opens the cooking screen
# - unlit: smoke/extinguished animation playing, interact kindles it
#
# interact flow:
# 1. player walks into Area2D → player_in_range gets set
# 2. player presses interact → an unlit firepit KINDLES, a lit one OPENS COOKING
# 3. player walks out of Area2D → reference cleared, any open panel closes
# 4. the panel closes, OR the player walks away → the fire burns out a second
#    later, whichever came last
#
# AND THAT LAST STEP IS WHAT MAKES IT A LOOP. Every firepit in the world now
# starts unlit and goes out again once you are done cooking at it, so lighting
# one is something you do each time rather than once per save. A fire that
# stays lit forever turns firemaking into a thing you did in the tutorial.
#
# ONE KEY, TWO MEANINGS, AND THE FIRE STATE PICKS WHICH. Interact used to toggle
# the fire in both directions, which left nowhere to put "cook" without a second
# binding — and CLAUDE.md records that this project has already lost time to
# keybind collisions (the owner panel ended up on backquote after Shift+A
# collided with interact and move_left). Lighting a fire is a thing you do once;
# cooking at it is a thing you do repeatedly, so the repeated action takes the
# key the moment the fire is lit.
#
# EXTINGUISHING LEFT THE INTERACT PATH ENTIRELY. extinguish_fire() is still
# public and unchanged, so a quest script or a weather effect can put a fire
# out — but a player standing at a lit firepit can no longer kill it by accident
# when they meant to cook.
#
# THE PANEL IS NOT THIS SCRIPT'S. Same split as lootbag.gd: this object knows it
# was interacted with and asks the HUD to open the screen. It holds no reference
# to the panel; the panel holds one to this, and calls notify_panel_closed() on
# the way out. Walking away is announced with player_left_range and the panel
# closes itself — see the matching comments in lootbag.gd, which this mirrors
# deliberately so there is one shape to learn rather than two.
extends Area2D


# =============================================================================
# CONSTANTS
# =============================================================================

# how long after scene load the firepit ignores interact input.
# prevents instant toggling if the player spawns nearby while still holding
# the interact key from a previous scene.
const SPAWN_GRACE_PERIOD := 1.0

# How long lighting a fire takes.
#
# WHY IT TAKES ANY TIME AT ALL. Lighting was instant: press interact, is_lit
# flips, done. That is the shape of a checkbox, not of a thing you did — and
# firemaking is the one skill in this genre that everybody remembers, entirely
# because you watch it catch.
#
# It is also why this has no panel and never should. A screen to light a fire
# would be a second window that looks exactly like the cooking one, and two
# near-identical windows is what makes a game feel assembled rather than made.
# The verb lives in the world.
const KINDLE_SECONDS := 1.35

# How long a fire keeps burning after you close the cooking panel.
#
# NOT ZERO, on purpose. Snapping out the instant the panel closes reads as the
# panel turning the fire off — a UI side effect. A beat of the fire still
# burning, seen in the world with the panel gone, reads as the fire dying down
# because you stopped feeding it, which is the same second of wall clock
# describing a different thing.
const PANEL_CLOSE_BURNOUT := 1.0

# How long the stone takes to cool once the flame is out. Longer than it takes
# to light, because that is how heat behaves and because a ring that snaps back
# to grey the frame the flame stops undoes the whole effect.
const COOL_SECONDS := 0.9

# Joined in _ready() rather than set on the scene, so a firepit placed by hand
# in any map is in the group without anyone having to remember to tick a box.
# _is_nearest_firepit() is the only thing that reads it.
const FIREPIT_GROUP := &"firepits"


# =============================================================================
# SIGNALS
# =============================================================================

# emitted when cook() is called on a lit firepit.
# the cooking system listens to this in phase 1 to open the cooking UI.
signal cook_requested(player: Node)

# THE PLAYER WALKED OFF WITH THE SCREEN OPEN. This object cannot close the
# panel — it has no reference to it — so it announces and the panel, which does
# hold a reference to this, closes itself. Straight port of lootbag.gd's signal
# of the same name, including the reason it only fires when something was
# actually open.
signal player_left_range()


# =============================================================================
# STATE
# =============================================================================

# reference to the player when inside the detection area. null otherwise.
var player_in_range: Node = null

# Whether the fire is currently lit. STARTS FALSE, so every firepit in every
# world scene is cold when you arrive and has to be lit. Tick it in the
# inspector for a pit that should already be burning — a lit camp in a story
# beat, say.
#
# The default flipped when kindling arrived. It was true, which meant the fire
# was on before the player did anything and _kindle() could only ever run on a
# pit that had already burnt out. Nothing in any scene overrides this property,
# so the default is what every firepit in the game actually uses.
#
# This is @export at all because the comment here always claimed you could set
# it in the editor, and a plain var never appears in the inspector — an unlit
# firepit was undocumented and unbuildable at the same time.
@export var is_lit: bool = false

# counts down from SPAWN_GRACE_PERIOD, blocks interaction while > 0
var spawn_timer: float = 0.0

# Whether the cooking screen is currently showing this firepit. Guards against a
# second press re-opening it on top of itself, and is cleared by
# notify_panel_closed() however the panel actually went away.
var _is_open: bool = false

# True while a fire is catching. Guards against a second press restarting the
# kindle, and is cleared by walking away.
var _kindling: bool = false

# Built in code rather than added to firepit.tscn deliberately. The Godot editor
# rewrites an open scene from its in-memory copy on save, and this project has
# already lost three committed .tscn edits that way. A node the script makes
# cannot be clobbered by a save that did not know about it.
var _embers: CPUParticles2D = null

# The stone-warming material on the sprite. See hearth_warm.gdshader: it lights
# the ring and leaves the flame exactly as drawn, which modulate cannot do
# because modulate multiplies the whole node.
const HEARTH_SHADER := preload("res://src/shared/hearth_warm.gdshader")
var _hearth_mat: ShaderMaterial = null

# One tween owns `warmth` at a time. Kindling up and cooling down both animate
# the same uniform, and two live tweens on one value is how sign.gd ended up
# with a label that would not fade.
var _warmth_tween: Tween = null

# Bumped every time a burnout is scheduled OR cancelled. A pending burnout
# compares the generation it captured against this when its timer comes back,
# and does nothing if they differ — which is how re-opening the panel, or
# relighting, cancels a countdown that is already in flight. Same pattern as
# pet.gd's _attack_generation, and for the same reason: you cannot cancel a
# SceneTreeTimer, so you make the thing waiting on it able to tell it is stale.
var _burnout_generation: int = 0

# THE FRAME A PRESS WAS CLAIMED ON, and the whole reason is that
# Input.is_action_just_pressed() is a global state query rather than a
# consumable event: EVERY node polling it on the press frame sees true. Two
# firepits close enough to stand between both saw the same press and both acted.
#
# STATIC, so the claim is shared by every firepit in the scene. lootbag.gd
# carries the long version of this reasoning and does the real work with a
# nearest-candidate test, which _is_nearest_firepit() below mirrors.
#
# WHAT THIS DOES NOT FIX: a firepit and a LOOT BAG on the same tile still both
# see the press, because each class claims against its own counter. Closing that
# needs one claim shared across every interactable, which is a change to
# lootbag.gd and every future interactable rather than to this file.
static var _press_claimed_frame: int = -1


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var anim: AnimatedSprite2D = $animatedsprite2d

# the crackle loop. An AudioStreamPlayer2D living IN this scene rather than a
# call through the Audio autoload, and that is deliberate: the autoload exists
# for one-shots that must outlive whatever triggered them (a death sound has
# to survive the thing that died). This is the opposite case — a continuous
# loop that should stop the moment the firepit stops existing, and should get
# louder as you walk toward it. Both of those come free from a player parented
# to the object making the noise.
@onready var audio: AudioStreamPlayer2D = $audio


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# FIXED: was an unconditional anim.play("lit"), which meant a firepit
	# placed as unlit lit itself the instant the scene loaded. is_lit was
	# being read everywhere EXCEPT the one place that decides what you see.
	if is_lit:
		light_fire()
	else:
		extinguish_fire()

	# start the grace period — interaction blocked until this counts down
	spawn_timer = SPAWN_GRACE_PERIOD

	add_to_group(FIREPIT_GROUP)


func _start_fire_sound() -> void:
	# Starts the loop at a RANDOM POINT rather than the beginning.
	#
	# Two firepits in one room, both starting their identical 11-second loop
	# on the same frame, stay locked together forever — and two copies of the
	# same waveform in sync do not sound like two fires, they sound like one
	# fire with a strange metallic edge (that edge is comb filtering). A random
	# offset per instance costs nothing and they never line up.
	#
	# Same reasoning as randomising torch animation phase — identical things
	# animating in lockstep is one of the most reliable tells of a fake world.
	if audio == null or audio.stream == null:
		return  # no sound file assigned yet: silent, not broken
	audio.play(randf() * audio.stream.get_length())


func _stop_fire_sound() -> void:
	if audio != null:
		audio.stop()


func _process(delta: float) -> void:
	# count down spawn grace period before allowing interaction
	if spawn_timer > 0.0:
		spawn_timer -= delta
		return

	if _is_open:
		# The cooking screen is already up on this firepit. Pressing interact
		# again while looking at it must not re-open it underneath itself.
		return
	if _kindling:
		# Already catching. Mashing interact must not restart it.
		return
	if player_in_range == null:
		return
	if not Input.is_action_just_pressed("interact"):
		return
	if not _is_nearest_firepit():
		return

	# See _press_claimed_frame. Whichever firepit gets the frame first is the
	# only one that acts on this press.
	var frame: int = Engine.get_process_frames()
	if _press_claimed_frame == frame:
		return
	_press_claimed_frame = frame

	if is_lit:
		_open_cooking()
	else:
		_kindle()


func _is_nearest_firepit() -> bool:
	# Firepits get grouped in _ready(), so a player standing between two of them
	# acts on the one they are actually closest to rather than on whichever the
	# scene tree happens to reach first. Same rule, same reason, as
	# LootBag._is_nearest_candidate().
	if player_in_range == null:
		return false
	var mine: float = global_position.distance_squared_to(player_in_range.global_position)

	for other in get_tree().get_nodes_in_group(FIREPIT_GROUP):
		if other == self or not is_instance_valid(other):
			continue
		if other.player_in_range != player_in_range:
			continue
		if other.global_position.distance_squared_to(player_in_range.global_position) < mine:
			return false
	return true


func _open_cooking() -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("open_cooking"):
		push_warning("FirePit: HUD has no open_cooking() — cannot open the cooking screen")
		return

	_is_open = true
	_cancel_burnout()
	Audio.play("bag_open")

	# The signal fires as well as the HUD call, so anything else that wants to
	# know a player started cooking here (a quest, a tutorial) can listen
	# without this script needing to know about it. cook() is the public
	# equivalent for code that wants to open the screen without a keypress.
	cook_requested.emit(player_in_range)
	hud.open_cooking(self, player_in_range)


func notify_panel_closed() -> void:
	# Called by cookingscreen.gd whenever its panel closes, for any reason — X
	# button, walked away, or the fire going out. The exact counterpart of
	# LootBag.notify_panel_closed(), and it exists for the same specific reason:
	# closing with the X while STILL standing in range never fires body_exited,
	# so without this _is_open would stay true forever and the firepit could
	# never be used again.
	_is_open = false
	_begin_burnout()


# =============================================================================
# BURNING OUT
# =============================================================================

func _begin_burnout() -> void:
	# Start the countdown that puts this fire out. Safe to call when the fire is
	# already cold or a countdown is already running — the second one supersedes
	# the first rather than both firing.
	if not is_lit:
		return

	_burnout_generation += 1
	var generation: int = _burnout_generation

	await get_tree().create_timer(PANEL_CLOSE_BURNOUT).timeout

	# PAST AN AWAIT. Same guard as _kindle() and every other await in src/world/.
	if not is_instance_valid(self) or not is_inside_tree():
		return

	# SUPERSEDED. The player re-opened the panel, or relit the fire, while this
	# was counting. _cancel_burnout() moved the generation on and this one is
	# no longer the live countdown.
	if generation != _burnout_generation:
		return

	# Belt and braces: both of these are what the generation check is for, but
	# they are cheap and they read as the actual rule rather than as a mechanism.
	if _is_open or not is_lit:
		return

	extinguish_fire()


func _cancel_burnout() -> void:
	# Invalidates any countdown in flight. Called wherever the fire has a reason
	# to keep burning.
	_burnout_generation += 1


# =============================================================================
# AREA SIGNAL HANDLERS
# =============================================================================

func _on_body_entered(body: Node) -> void:
	# track only the player — ignore enemies, projectiles, drops, etc.
	if body.is_in_group("player"):
		player_in_range = body

		# ARRIVING CANCELS A BURNOUT. Without this, stepping out of range for
		# half a second and stepping straight back killed the fire while you
		# stood at it — the countdown from walking away kept running and there
		# was nothing to call it off.
		#
		# The rule this completes: a fire goes out a second after the last
		# thing that could keep it alive, and standing at it is one of those
		# things. Closing the panel while still in range is NOT — no body
		# entered, so nothing cancels, and the fire dies as asked.
		_cancel_burnout()


func _on_body_exited(body: Node) -> void:
	# only respond when the SPECIFIC tracked player exits — guards against
	# unrelated bodies overlapping the firepit and clobbering the reference.
	if body != player_in_range:
		return
	player_in_range = null

	# Only announce if something was actually open. A player who never cooked
	# here walking past would otherwise fire a signal with nothing listening.
	var was_open: bool = _is_open
	_is_open = false
	if was_open:
		player_left_range.emit()

	# WALKING AWAY ENDS IT TOO, opened panel or not. The panel path already
	# schedules a burnout — player_left_range above closes the panel, which
	# calls notify_panel_closed() — but a fire you lit and then wandered off
	# from without ever cooking had nothing watching it, and stayed burning for
	# the rest of the session. That is the one hole left by hanging the burnout
	# on the panel alone.
	#
	# SCHEDULING TWICE IS HARMLESS, which is why this is unconditional rather
	# than guarded on was_open. _burnout_generation makes the earlier countdown
	# stale the moment this one starts, so the fire goes out once, a second
	# after the last thing that could have kept it alive.
	_begin_burnout()


# =============================================================================
# STATE TRANSITIONS
# =============================================================================

func toggle_fire() -> void:
	# NO LONGER ON THE INTERACT KEY — see the header. Kept, and made public, for
	# the callers the original comment was written for: environmental effects
	# and quest scripts. A player at a lit firepit gets the cooking screen.
	if is_lit:
		extinguish_fire()
	else:
		light_fire()


# =============================================================================
# THE STONE
# =============================================================================

func _ensure_hearth_material() -> void:
	# Built in code, like the embers, and for the same reason: the Godot editor
	# rewrites an open scene from its in-memory copy on save, and this project
	# has already lost committed .tscn edits that way. Nothing the script makes
	# can be clobbered by a save that did not know about it.
	#
	# A FRESH MATERIAL PER FIREPIT. A Material is a Resource, so one shared
	# between instances would mean the last pit to light decided the warmth of
	# every pit on the map — the same trap BaseEnemy._apply_element_recolour()
	# documents for the element shader.
	if _hearth_mat != null:
		return
	if anim == null:
		return
	_hearth_mat = ShaderMaterial.new()
	_hearth_mat.shader = HEARTH_SHADER
	_hearth_mat.set_shader_parameter("warmth", 0.0)
	anim.material = _hearth_mat


func _set_warmth(value: float) -> void:
	_ensure_hearth_material()
	if _hearth_mat == null:
		return
	_kill_warmth_tween()
	_hearth_mat.set_shader_parameter("warmth", clampf(value, 0.0, 1.0))


func _tween_warmth(to: float, seconds: float) -> void:
	_ensure_hearth_material()
	if _hearth_mat == null:
		return
	_kill_warmth_tween()
	_warmth_tween = create_tween()
	_warmth_tween.tween_property(
		_hearth_mat, "shader_parameter/warmth", clampf(to, 0.0, 1.0), seconds)


func _kill_warmth_tween() -> void:
	if _warmth_tween != null and _warmth_tween.is_valid():
		_warmth_tween.kill()
	_warmth_tween = null


func _kindle() -> void:
	# The fire catching, as something you watch rather than something that has
	# already happened. Embers first, then the flame.
	#
	# NOTHING IS CONSUMED AND NO XP IS GRANTED YET, and both are deliberate
	# gaps rather than oversights. Firemaking as a skill needs logs and a
	# tinderbox, which means art this project does not have, and it needs XP,
	# which under the wire rule has to come from an endpoint — a client-side
	# grant is overwritten by the next sync. See PUT /api/character/skills,
	# which already drops the rows the server owns.
	#
	# WHERE THOSE SLOT IN: the item check goes at the top of this function,
	# before _kindling is set, and the XP grant goes beside light_fire() at the
	# bottom, from the endpoint's reply. The feel is the part that can be built
	# now, and it is the part that matters for whether the skill is any fun.
	if is_lit or _kindling:
		return
	_kindling = true

	_ensure_embers()
	if _embers != null:
		_embers.emitting = true

	Audio.play("fire_light")

	# THE BRICKS WARM UP OVER THE KINDLE, which is the thing you actually watch.
	# It used to be a modulate on the whole sprite, so the flame warmed with the
	# stone and the effect read as the sprite being tinted rather than as rock
	# catching light. hearth_warm.gdshader separates them by saturation.
	_tween_warmth(1.0, KINDLE_SECONDS)

	await get_tree().create_timer(KINDLE_SECONDS).timeout

	# PAST AN AWAIT, and every other await in src/world/ carries this guard:
	# fishingspot, enemyrespawner, teleporter, lever. A SceneTreeTimer belongs to
	# the tree rather than to this node, so it outlives a scene change and would
	# otherwise resume on a freed Area2D. It goes FIRST, before anything below
	# reads a node.
	if not is_instance_valid(self) or not is_inside_tree():
		return

	_kindling = false
	if _embers != null:
		_embers.emitting = false

	# WALKING AWAY CANCELS IT. Holding a fire half-lit across the map and having
	# it finish behind you would be the instant version again, just delayed.
	#
	# The stone cools back down rather than snapping, so an abandoned kindle
	# looks like a fire that did not take instead of a visual glitch.
	if player_in_range == null:
		_tween_warmth(0.0, COOL_SECONDS)
		return

	light_fire()


func _ensure_embers() -> void:
	if is_instance_valid(_embers):
		return

	# A RAW Gradient, NOT A GradientTexture1D. CPUParticles2D.color_ramp is typed
	# Gradient; it is ParticleProcessMaterial — what the GPU emitter uses — whose
	# color_ramp is a texture. The two emitters read the same-named property as
	# different types, and wrapping the gradient here was a hard parse error.
	# scale_amount_curve is the same story: Curve on this node, CurveTexture on
	# the material.
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	ramp.colors = PackedColorArray([
		Color(1.0, 0.85, 0.45, 1.0),
		Color(1.0, 0.42, 0.12, 0.8),
		Color(0.5, 0.12, 0.04, 0.0),
	])

	_embers = CPUParticles2D.new()
	_embers.name = "kindleembers"
	_embers.emitting = false
	_embers.amount = 14
	_embers.lifetime = 0.9
	_embers.local_coords = false
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_embers.emission_rect_extents = Vector2(6, 2)
	_embers.direction = Vector2(0, -1)
	_embers.spread = 32.0
	_embers.gravity = Vector2(0, -26)
	_embers.initial_velocity_min = 8.0
	_embers.initial_velocity_max = 26.0
	_embers.scale_amount_min = 0.6
	_embers.scale_amount_max = 1.4
	_embers.color_ramp = ramp
	_embers.z_index = 1
	_embers.position = anim.position + Vector2(0, -2)
	add_child(_embers)


func light_fire() -> void:
	# transition to lit state. plays the flame animation and starts the crackle.
	#
	# Cancels any burnout in flight, so relighting a fire that is one frame from
	# going out gives you a fire rather than a fire that dies in your hands.
	_cancel_burnout()
	is_lit = true
	anim.play("lit")

	# HOT, IMMEDIATELY. The kindle already tweened the stone the whole way, so
	# this is a no-op on that path. It matters for every other caller — _ready()
	# on a pit authored lit, a quest script, toggle_fire() — none of which went
	# through a kindle and all of which would otherwise show a burning fire
	# sitting in cold grey stone.
	#
	# This also kills the cooling tween, and with it the callback that would
	# have stopped the dying embers — so relighting during a cool-down has to
	# stop them here. A lit firepit has its flame; it does not need embers too.
	_set_warmth(1.0)
	if is_instance_valid(_embers):
		_embers.emitting = false
	_start_fire_sound()


func extinguish_fire() -> void:
	# transition to extinguished state. plays the smoke/dead animation and
	# stops the crackle — an extinguished fire that still crackles is worse
	# than one that never made a sound at all.
	#
	# CAPTURED BEFORE is_lit MOVES, because everything below needs to know
	# whether there was actually a fire here to go out. _ready() calls this on
	# every cold firepit in the world to put it in its starting state, and a
	# pit that was never lit must not puff embers at scene load.
	var was_lit: bool = is_lit

	is_lit = false
	anim.play("unlit")
	_stop_fire_sound()

	if was_lit:
		# The flame stops at once and the stone cools over COOL_SECONDS, which
		# is the right way round: the fire going out is an event, the rock
		# losing its heat is not.
		_tween_warmth(0.0, COOL_SECONDS)

		# THE SAME EMBERS THAT LIT IT, RUNNING THE OTHER WAY. Kindling throws
		# them as the fire catches; this throws them as it dies, for exactly as
		# long as the stone takes to cool. Same emitter, no second effect to
		# keep in sync.
		#
		# The tail is free: a particle lives 0.9s, so the last ones emitted are
		# still drifting up after the stone has gone grey. Embers outlasting
		# the heat that made them is the correct way round, and it costs
		# nothing.
		_ensure_embers()
		if _embers != null:
			_embers.emitting = true

		# Chained onto the cooling tween rather than an await, so the embers
		# stop the moment the stone is cold and not a frame either side. If
		# something relights the fire mid-cool, _set_warmth() kills that tween
		# and this callback never runs — which is why light_fire() stops them
		# itself rather than trusting this to have happened.
		if _warmth_tween != null and _warmth_tween.is_valid():
			_warmth_tween.tween_callback(func() -> void:
				if is_instance_valid(_embers):
					_embers.emitting = false)

	elif _warmth_tween == null or not _warmth_tween.is_valid():
		# ALREADY COLD, AND NOTHING IS COOLING. Just make sure the material
		# exists and reads as cold — this is the _ready() path for every unlit
		# firepit in the world.
		#
		# THE elif IS LOAD-BEARING. extinguish_fire() is public and documented
		# for quest scripts and weather, so calling it on a fire that is already
		# going out is a thing that will happen. Re-tweening warmth there would
		# kill the cool-down in flight AND the callback riding on it, and the
		# embers would emit for the rest of the session with nothing left to
		# turn them off.
		_set_warmth(0.0)

	# A COOKING SCREEN OPEN ON A DEAD FIRE is the state this has to prevent. The
	# panel refuses to cook on an unlit firepit anyway, so leaving it up would
	# just be a window whose every button says no. Same announcement the
	# walk-away path uses, so the panel has one way to be told to go.
	if _is_open:
		_is_open = false
		player_left_range.emit()


# =============================================================================
# ON THE MAP
# =============================================================================
# mapscreen.gd draws a pin for everything in "map_landmarks" and asks each one
# what it is. Joined in _init rather than _ready so it does not depend on this
# script having a _ready, or on anything a _ready returns early for - and so
# the pin exists from the moment the node does.

func _init() -> void:
	add_to_group("map_landmarks")

func map_landmark() -> Dictionary:
	return {"kind": "cooking", "label": "Firepit"}
