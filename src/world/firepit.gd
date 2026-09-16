# firepit.gd — world-placed interactable that the player can light and cook at.
#
# state model:
# - lit:   flame animation playing, interact opens the cooking screen
# - unlit: smoke/extinguished animation playing, interact lights it
#
# interact flow:
# 1. player walks into Area2D → player_in_range gets set
# 2. player presses interact → an unlit firepit LIGHTS, a lit one OPENS COOKING
# 3. player walks out of Area2D → reference cleared, any open panel closes
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

# tracks whether the fire is currently lit. starts lit by default — set
# to false in the editor for firepits that should start extinguished.
#
# FIXED: this is @export now. The comment above has always said "set it in the
# editor", but a plain var never appears in the inspector, so there was no way
# to do what the documentation described. An unlit firepit was unbuildable.
@export var is_lit: bool = true

# counts down from SPAWN_GRACE_PERIOD, blocks interaction while > 0
var spawn_timer: float = 0.0

# Whether the cooking screen is currently showing this firepit. Guards against a
# second press re-opening it on top of itself, and is cleared by
# notify_panel_closed() however the panel actually went away.
var _is_open: bool = false

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
		light_fire()


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
	if body != player_in_range:
		return
	player_in_range = null

	# Only announce if something was actually open. A player who never cooked
	# here walking past would otherwise fire a signal with nothing listening.
	var was_open: bool = _is_open
	_is_open = false
	if was_open:
		player_left_range.emit()


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

	# A COOKING SCREEN OPEN ON A DEAD FIRE is the state this has to prevent. The
	# panel refuses to cook on an unlit firepit anyway, so leaving it up would
	# just be a window whose every button says no. Same announcement the
	# walk-away path uses, so the panel has one way to be told to go.
	if _is_open:
		_is_open = false
		player_left_range.emit()


# =============================================================================
# COOKING
# =============================================================================

func cook(player: Node) -> void:
	# Open the cooking screen at this firepit without a keypress — for a quest
	# script, a tutorial, or anything else that wants to put the player in front
	# of it. Only succeeds on a lit firepit, same as the interact path.
	#
	# NOW HAS A CALLER. CLAUDE.md lists this function under "uncalled on purpose
	# — built ahead of their consumers", alongside gain_cooking_xp(). The
	# consumer is here; that note is out of date for cook() and should come out
	# the next time that file is edited.
	if not is_lit:
		return
	if _is_open:
		return

	var previous: Node = player_in_range
	player_in_range = player
	_open_cooking()
	if player_in_range == null:
		player_in_range = previous
