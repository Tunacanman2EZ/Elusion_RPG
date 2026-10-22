# anvil.gd - the smith's anvil in town. Walk up, press interact, and the smith
# window opens: temper a piece of gear, or earn a Royal Certification.
#
# The owner: "a new smith spends materials plus gold to upgrade gear", and
# "Upgrades that cost materials instead of only gold, plus a 'Royal
# Certification' step to reach higher tiers ... the certification fits the
# kingdom theme".
#
# THE FIREPIT'S RULES, WITHOUT THE FIRE. Structurally this is firepit.gd with
# the kindling taken out: walk into the Area2D, press interact, the HUD opens
# the panel, walking away closes it, and the panel tells this object when it
# shut. There is nothing to light, so the panel arrives on the press, the way
# the vendor's does. Two of firepit.gd's rules are kept on purpose, because
# the reasons for them hold for any station a player can stand between:
#
#   - THE NEAREST ANVIL ACTS. Input.is_action_just_pressed() is a global query,
#     so every anvil in range sees the same press. Only the one the player is
#     closest to opens anything - _is_nearest_anvil(), the same test as
#     FirePit._is_nearest_firepit() and LootBag._is_nearest_candidate().
#   - ONE PRESS, ONE PANEL. The frame a press was claimed on is static, shared
#     by every anvil, so two anvils at the same distance still open one window.
#
# THE PANEL IS NOT THIS SCRIPT'S, the same split as the firepit and the loot
# bag. This object knows it was interacted with and asks the HUD to open the
# smith window. It holds no reference to the window; the window holds one to
# this, calls notify_panel_closed() on the way out, and listens for
# player_left_range so walking off closes it.
#
# WHAT THIS DOES NOT DO: temper anything, take a material or spend a coin. The
# window asks the server, which owns all three (POST /api/smith/temper and
# /api/smith/certify), and this file only decides when the window is on screen.
extends Area2D


# =============================================================================
# CONSTANTS
# =============================================================================

# Matches the firepit, the bank chest and the vendor. Stops the window opening
# on the interact key the player was still holding when the scene loaded.
const SPAWN_GRACE_PERIOD := 1.0

# Joined in _ready() rather than ticked on the scene, so an anvil placed by hand
# in any map is in the group without anyone having to remember a box.
# _is_nearest_anvil() is the only thing that reads it.
const ANVIL_GROUP := &"anvils"


# =============================================================================
# SIGNALS
# =============================================================================

# THE PLAYER WALKED OFF WITH THE WINDOW OPEN. This object cannot close the
# window - it has no reference to it - so it announces, and the window, which
# does hold a reference to this, closes itself. The firepit's signal of the same
# name, and it fires only when something was actually open, for the same reason.
signal player_left_range()


# =============================================================================
# STATE
# =============================================================================

# The player while they stand in the detection area, null otherwise.
var player_in_range: Node = null

# Counts down from SPAWN_GRACE_PERIOD; interact is ignored while it is above 0.
var spawn_timer: float = 0.0

# Whether the smith window is showing this anvil. Guards against a second press
# opening it again underneath itself, and is cleared by notify_panel_closed()
# however the window went away - the X, Escape, or walking off.
var _is_open: bool = false

# The frame a press was claimed on, shared by every anvil. See the header and
# firepit.gd's _press_claimed_frame for the long version.
static var _press_claimed_frame: int = -1


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var anim: AnimatedSprite2D = $animatedsprite2d


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	if anim != null:
		anim.play("idle")

	spawn_timer = SPAWN_GRACE_PERIOD
	add_to_group(ANVIL_GROUP)

	# Wired here rather than in the scene, like bankchest.gd and vendor.gd: the
	# connection is then on the page where the handler is.
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	if spawn_timer > 0.0:
		spawn_timer -= delta
		return

	if _is_open:
		# The window is already up on this anvil. Pressing interact again while
		# reading it must not open it a second time underneath itself.
		return
	if player_in_range == null:
		return
	if not Input.is_action_just_pressed("interact"):
		return
	if not _is_nearest_anvil():
		return

	# Whichever anvil claims the frame first is the only one that acts on it.
	var frame: int = Engine.get_process_frames()
	if _press_claimed_frame == frame:
		return
	_press_claimed_frame = frame

	_open_smith()


func _is_nearest_anvil() -> bool:
	# A player standing between two anvils uses the one they are closest to,
	# rather than whichever the scene tree reaches first. The firepit's rule.
	if player_in_range == null:
		return false
	var mine: float = global_position.distance_squared_to(player_in_range.global_position)

	for other in get_tree().get_nodes_in_group(ANVIL_GROUP):
		if other == self or not is_instance_valid(other):
			continue
		if other.player_in_range != player_in_range:
			continue
		if other.global_position.distance_squared_to(player_in_range.global_position) < mine:
			return false
	return true


func _open_smith() -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("open_smith"):
		push_warning("Anvil: HUD has no open_smith() - cannot open the smith window")
		return

	_is_open = true
	Audio.play("bag_open")
	hud.open_smith(self, player_in_range)


func notify_panel_closed() -> void:
	# Called by smithscreen.gd whenever its window closes, for any reason. The
	# counterpart of FirePit.notify_panel_closed(), and it exists for the same
	# reason: closing with the X while STILL standing here never fires
	# body_exited, so without it _is_open would stay true and this anvil could
	# never be used again.
	_is_open = false


# =============================================================================
# AREA SIGNAL HANDLERS
# =============================================================================

func _on_body_entered(body: Node) -> void:
	# The player only - not a monster crossing the square, not a dropped bag.
	if body.is_in_group("player"):
		player_in_range = body


func _on_body_exited(body: Node) -> void:
	# Only the SPECIFIC player being tracked. An unrelated body leaving must not
	# clear the reference to the one still standing here.
	if body != player_in_range:
		return
	player_in_range = null

	# Only announce if something was actually open. A player walking past an
	# anvil they never used would otherwise signal a window that is not there.
	var was_open: bool = _is_open
	_is_open = false
	if was_open:
		player_left_range.emit()


# =============================================================================
# ON THE MAP
# =============================================================================
# mapscreen.gd draws a pin for everything in "map_landmarks" and asks each one
# what it is. Joined in _init rather than _ready, like every other landmark, so
# the pin exists from the moment the node does.

func _init() -> void:
	add_to_group("map_landmarks")

func map_landmark() -> Dictionary:
	return {"kind": "smith", "label": "Anvil"}
