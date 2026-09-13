# firepit.gd — world-placed interactable that the player can light, extinguish,
# or cook at. press the interact key while nearby to toggle the flame state.
#
# state model:
# - lit:   flame animation playing, cook_requested signal fires when cook()
#          is called by the cooking system
# - unlit: smoke/extinguished animation playing, cook() rejected
#
# interact flow:
# 1. player walks into Area2D → player_in_range gets set
# 2. player presses interact → toggle is_lit, swap animation
# 3. player walks out of Area2D → reference cleared
#
# the cooking system itself lives elsewhere — this script just signals when
# the player wants to cook at a lit firepit. cooking UI hooks into the
# cook_requested signal in phase 1 of the cooking implementation.
extends Area2D


# =============================================================================
# CONSTANTS
# =============================================================================

# how long after scene load the firepit ignores interact input.
# prevents instant toggling if the player spawns nearby while still holding
# the interact key from a previous scene.
const SPAWN_GRACE_PERIOD := 1.0


# =============================================================================
# SIGNALS
# =============================================================================

# emitted when cook() is called on a lit firepit.
# the cooking system listens to this in phase 1 to open the cooking UI.
signal cook_requested(player: Node)


# =============================================================================
# STATE
# =============================================================================

# reference to the player when inside the detection area. null otherwise.
var player_in_range: Node = null

# tracks whether the fire is currently lit. starts lit by default — set
# to false in the editor for firepits that should start extinguished.
#
# FIXED: this is @export now. The comment above has always said "set it in the
# editor", but a plain var never appears in the inspector, so there was no way
# to do what the documentation described. An unlit firepit was unbuildable.
@export var is_lit: bool = true

# counts down from SPAWN_GRACE_PERIOD, blocks interaction while > 0
var spawn_timer: float = 0.0


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

	# toggle the fire state when player nearby and pressing interact
	if player_in_range == null:
		return
	if not Input.is_action_just_pressed("interact"):
		return

	_toggle_fire()


# =============================================================================
# AREA SIGNAL HANDLERS
# =============================================================================

func _on_body_entered(body: Node) -> void:
	# track only the player — ignore enemies, projectiles, drops, etc.
	if body.is_in_group("player"):
		player_in_range = body


func _on_body_exited(body: Node) -> void:
	# only respond when the SPECIFIC tracked player exits — guards against
	# unrelated bodies overlapping the firepit and clobbering the reference.
	if body == player_in_range:
		player_in_range = null


# =============================================================================
# STATE TRANSITIONS
# =============================================================================

func _toggle_fire() -> void:
	# called when the player presses interact near the firepit.
	# extracted so the toggle behavior can be triggered programmatically too
	# (e.g., environmental effects, quest scripts).
	if is_lit:
		extinguish_fire()
	else:
		light_fire()


func light_fire() -> void:
	# transition to lit state. plays the flame animation and starts the crackle.
	is_lit = true
	anim.play("lit")
	_start_fire_sound()


func extinguish_fire() -> void:
	# transition to extinguished state. plays the smoke/dead animation and
	# stops the crackle — an extinguished fire that still crackles is worse
	# than one that never made a sound at all.
	is_lit = false
	anim.play("unlit")
	_stop_fire_sound()


# =============================================================================
# COOKING
# =============================================================================

func cook(player: Node) -> void:
	# request cooking at this firepit. only succeeds on lit firepits.
	# the cooking system listens to cook_requested to open the cooking UI;
	# this script doesn't know about cooking mechanics, just signals intent.
	if not is_lit:
		return
	cook_requested.emit(player)
