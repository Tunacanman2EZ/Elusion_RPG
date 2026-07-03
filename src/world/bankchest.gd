# bankchest.gd — world-placed interactable that opens the bank UI.
# player walks into the detection area, presses the interact key, and the
# chest plays an open animation while the bank screen is toggled on.
#
# flow:
# 1. player walks into Area2D → player_nearby gets set
# 2. player presses interact → animation plays, HUD.toggle_bank() called
# 3. player walks out of Area2D → chest closes, bank screen auto-closes
#
# the bank UI itself is owned by the HUD (lazy-instantiated on first toggle).
# this chest just signals when to open it; it doesn't manage the screen state.
extends Area2D


# =============================================================================
# CONSTANTS
# =============================================================================

# how long after scene load the chest ignores interact input.
# prevents the chest from instantly opening if the player spawns on top of it
# while still holding the interact key from the previous scene.
const SPAWN_GRACE_PERIOD := 1.0


# =============================================================================
# STATE
# =============================================================================

# tracks whether the chest is currently in its open visual state
var is_open: bool = false

# reference to the player node when they're inside the detection area.
# null when no player is nearby.
var player_nearby: Node = null

# counts down from SPAWN_GRACE_PERIOD on _ready, blocks interaction while > 0
var spawn_timer: float = 0.0


# =============================================================================
# NODE REFERENCES
# =============================================================================

# animated sprite that plays the idle / open / close visual states
@onready var anim: AnimatedSprite2D = $animatedsprite2d


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# play closed state on spawn (single-frame idle)
	anim.play("idle")

	# start the grace period — interaction blocked until this counts down
	spawn_timer = SPAWN_GRACE_PERIOD

	# wire signals programmatically rather than via the editor — keeps the
	# .tscn lighter and makes the connection easy to trace in the script
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	if anim != null:
		anim.animation_finished.connect(_on_animation_finished)


func _process(delta: float) -> void:
	# count down the spawn grace period before allowing interaction
	if spawn_timer > 0.0:
		spawn_timer -= delta
		return

	# only interact when: player nearby + chest closed + interact key pressed
	if player_nearby == null:
		return
	if is_open:
		return
	if not Input.is_action_just_pressed("interact"):
		return

	_open_chest()


# =============================================================================
# OPEN / CLOSE
# =============================================================================

func _open_chest() -> void:
	# play the open animation and request the HUD show the bank screen.
	# the HUD owns the bank UI instance — we just ask it to toggle.
	anim.play("open")
	is_open = true

	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		push_error("BankChest: CRITICAL — no node in the 'hud' group found")
		return

	if hud.has_method("toggle_bank"):
		hud.toggle_bank()
	else:
		push_error("BankChest: HUD found, but it is missing toggle_bank()")


func _close_chest_on_walk_away() -> void:
	# play the open animation in reverse for a "closing" visual,
	# then ask the bank screen to clean up and save.
	is_open = false
	anim.play_backwards("open")

	# tell the bank screen to close (saves bank state, hides the panel).
	# guarded — bank screen may not exist yet if the chest was opened and
	# the player walked out before the HUD lazy-instantiated it.
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return

	var bank_screen: Node = hud.get_node_or_null("bankinventory")
	if bank_screen != null and bank_screen.has_method("close_bank"):
		bank_screen.close_bank()


# =============================================================================
# AREA SIGNAL HANDLERS
# =============================================================================

func _on_body_entered(body: Node) -> void:
	# track only the player — ignore enemies, projectiles, etc.
	if body.is_in_group("player"):
		player_nearby = body


func _on_body_exited(body: Node) -> void:
	# only respond when the SPECIFIC tracked player exits — guards against
	# unrelated bodies overlapping the chest and clobbering the reference.
	if body != player_nearby:
		return

	player_nearby = null

	# auto-close if the player walks away while the chest is open
	if is_open:
		_close_chest_on_walk_away()


# =============================================================================
# ANIMATION HOOKS
# =============================================================================

func _on_animation_finished() -> void:
	# hold on the last frame of "open" so the chest stays visually open
	# while the player interacts with the bank UI. without this, the sprite
	# would loop back to frame 0 (closed) while the bank screen is still up.
	if anim.animation == "open" and is_open:
		var frame_count: int = anim.sprite_frames.get_frame_count("open")
		anim.frame = frame_count - 1
