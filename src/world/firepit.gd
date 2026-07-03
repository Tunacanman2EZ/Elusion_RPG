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
var is_lit: bool = true

# counts down from SPAWN_GRACE_PERIOD, blocks interaction while > 0
var spawn_timer: float = 0.0


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var anim: AnimatedSprite2D = $animatedsprite2d


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# start with the fire lit and playing the lit animation
	anim.play("lit")

	# start the grace period — interaction blocked until this counts down
	spawn_timer = SPAWN_GRACE_PERIOD


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
	# transition to lit state. plays the flame animation.
	is_lit = true
	anim.play("lit")


func extinguish_fire() -> void:
	# transition to extinguished state. plays the smoke/dead animation.
	is_lit = false
	anim.play("unlit")


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
