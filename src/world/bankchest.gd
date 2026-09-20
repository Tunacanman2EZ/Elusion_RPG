# bankchest.gd — world-placed interactable that opens the bank UI.
# player walks into the detection area, presses the interact key, and the
# chest plays an open animation, and the bank screen comes up partway
# through it rather than instantly.
#
# flow:
# 1. player walks into Area2D → player_nearby gets set
# 2. player presses interact → open animation plays
# 3. animation reaches BANK_UI_FRAME → HUD.toggle_bank() called
# 4. player walks out of Area2D → chest closes, bank screen auto-closes
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

# frame of the "open" animation at which the bank panel appears.
#
# the panel used to pop up on the same frame the interact key was pressed,
# while the lid was still visibly shut — the UI arrived before the thing it
# belongs to had opened. now the animation drives it: the chest finishes
# swinging open and the bank comes up with it.
#
# this is a frame index, not a delay, so retiming the animation moves the
# panel with it instead of silently desyncing. _bank_ui_frame() clamps it to
# the animation's real length, so shortening "open" can't leave the panel
# waiting for a frame that never arrives.
const BANK_UI_FRAME := 6


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
	# play the open animation. the bank screen is NOT shown here any more —
	# we watch the animation and show it when it reaches BANK_UI_FRAME.
	anim.play("open")
	is_open = true

	# With the animation, not with the panel. The panel appears several frames
	# later at BANK_UI_FRAME, and a chest whose lid creaks open after it has
	# already opened reads as lag.
	Audio.play("bank_open")

	if not anim.frame_changed.is_connected(_on_open_frame_changed):
		anim.frame_changed.connect(_on_open_frame_changed)

	# the animation can already be sitting at or past the trigger frame if the
	# player re-opens a chest whose reverse-close never ran to completion.
	# frame_changed would never fire again in that case and the panel would
	# wait forever, so check the current frame once immediately.
	_on_open_frame_changed()


func _on_open_frame_changed() -> void:
	# fires on every frame step of whatever this sprite is playing, including
	# the reverse close, so each of these guards is load-bearing:
	#   is_open        — the player walked away; the close is running now
	#   animation name — some other animation is playing
	#   frame          — the lid is still on its way up
	if not is_open:
		return
	if anim.animation != "open":
		return
	if anim.frame < _bank_ui_frame():
		return

	_stop_watching_open()
	_show_bank_ui()


func _bank_ui_frame() -> int:
	# BANK_UI_FRAME clamped to the animation that actually exists, so the
	# panel still appears (on the last frame) if "open" is ever shortened.
	if anim == null or anim.sprite_frames == null:
		return BANK_UI_FRAME
	var last_frame: int = anim.sprite_frames.get_frame_count("open") - 1
	if last_frame < 0:
		return BANK_UI_FRAME
	return clampi(BANK_UI_FRAME, 0, last_frame)


func _stop_watching_open() -> void:
	if anim != null and anim.frame_changed.is_connected(_on_open_frame_changed):
		anim.frame_changed.disconnect(_on_open_frame_changed)


func _show_bank_ui() -> void:
	# the HUD owns the bank UI instance — we just ask it to toggle.
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		push_error("BankChest: CRITICAL — no node in the 'hud' group found")
		return

	if not hud.has_method("toggle_bank"):
		push_error("BankChest: HUD found, but it is missing toggle_bank()")
		return

	hud.toggle_bank()

	# LISTEN FOR THE PANEL CLOSING ITSELF.
	#
	# is_open was cleared in exactly one place — _close_chest_on_walk_away(),
	# reached only from _on_body_exited. Click the panel's X while still
	# standing on the chest and body_exited never fires, so is_open stayed true,
	# _process()'s `if is_open: return` swallowed every further interact press,
	# and the chest was a permanently-open prop until you walked fully out of
	# its Area2D and back in.
	#
	# BankInventory has emitted `closed` for exactly this the whole time and
	# nothing listened — its own comment at the signal says so. This is the
	# same shape lootbag.gd solved with notify_panel_closed().
	var panel: Node = hud.get("bank_screen")
	if panel != null and panel.has_signal("closed") \
			and not panel.closed.is_connected(notify_panel_closed):
		panel.closed.connect(notify_panel_closed)


func notify_panel_closed() -> void:
	# The panel shut itself — X button, or the HUD tearing it down. Mirrors
	# LootBag.notify_panel_closed() and FirePit.notify_panel_closed(), and
	# exists for the same reason both of those do.
	#
	# Guarded on is_open because `closed` also fires on the walk-away path,
	# which has already run _close_chest_on_walk_away() by then — without this
	# the chest would run its closing animation twice.
	if not is_open:
		return

	is_open = false
	_stop_watching_open()
	if anim != null and anim.animation == "open":
		anim.play_backwards("open")


func _close_chest_on_walk_away() -> void:
	# play the open animation in reverse for a "closing" visual,
	# then ask the bank screen to clean up and save.
	is_open = false

	# cancel any pending open. walking away mid-animation is now a real window
	# (the lid takes a few frames to finish), and without this the reverse
	# close would keep stepping frames past the trigger with the watch still
	# live — the panel would be waiting to appear on a chest already shutting.
	_stop_watching_open()

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
