# floatinglabel.gd — reusable floating label that appears when entities take
# damage, receive healing, or level up. spawns at a position, BOUNCES upward
# with arc motion while fading, then despawns automatically.
#
# two display modes:
#   show_number(amount, type)        — numeric popups (damage/heal/mana)
#   show_text(message, type)         — word popups (LEVEL UP!, Defence 5)
#
# type conventions:
#   DAMAGE  (red)   — hp went down
#   HEAL    (green) — hp went up
#   MANA    (blue)  — mana restored
#   LEVELUP (gold)  — character level-up: big, long linger, celebratory
#   SKILLUP (cyan)  — skill level-up: smaller, shorter, frequent + informative
#   NOTICE  (amber) — "you can't do that": health full, no mana, bag full.
#                     spawn these through Player.show_notice(), which
#                     de-duplicates repeats so a held key can't stack them.
#
# motion (physics-feel arc):
# labels shoot upward with initial velocity, gravity decelerates them at the
# peak, then they fall back a bit before settling. fade-out runs in parallel.
#
# important: _start_position is captured in the show_* call, NOT _ready().
# _ready fires the moment add_child() runs — BEFORE the spawner sets
# global_position. capturing on show ensures the cached position is correct.
extends Node2D

# REGISTERED AS A GLOBAL CLASS so the enum below is reachable by name.
#
# It was not, and the cost is written out in player.gd:
#
#     "Written as a bare int because floatinglabel.gd has no class_name, so
#      its enum is not reachable by name from here — the existing popup calls
#      in this file pass a literal 3 for LEVELUP for the same reason."
#
# So every caller in the project passes 0, 1, 2 or 3 to a parameter named
# `type`, and the meaning of those numbers lives in one file that none of them
# can see. The enum's own comment says to append rather than insert precisely
# because inserting would silently repoint every one of those literals — which
# is a rule enforced by a comment, on a file nobody editing the callers has
# open.
#
# One line fixes it. FloatingLabel.Type.DAMAGE now works from anywhere, and
# the literals can be replaced as each one is next touched.
class_name FloatingLabel


# =============================================================================
# TYPE ENUM
# =============================================================================

# APPEND NEW TYPES AT THE END, never in the middle. Callers pass these as
# plain ints (this script has no class_name, so player.gd cannot write
# FloatingLabel.Type.LEVELUP and passes 3 instead) — inserting a value would
# silently repaint every existing popup in the game.
enum Type {
	DAMAGE,
	HEAL,
	MANA,
	LEVELUP,
	SKILLUP,
	NOTICE,
}


# =============================================================================
# EXPORTED SETTINGS — TIMING
# =============================================================================

# base visible lifetime in seconds (numeric popups). level-up types override
# this with their own longer/shorter lifetimes in the show calls.
@export var lifetime: float = 1.0

# when fade-out begins as a fraction of lifetime (0.5 = halfway through).
@export var fade_start_progress: float = 0.5


# =============================================================================
# EXPORTED SETTINGS — MOTION
# =============================================================================

@export var initial_velocity_y: float = -180.0
@export var gravity: float = 320.0
@export var horizontal_drift_range: float = 30.0
@export var rotation_jitter_range: float = 0.15

# IMMEDIATE spawn offset, in world pixels.
#
# horizontal_drift_range above only separates labels OVER TIME — it's a
# velocity, so at t=0 every label spawned on the same frame sits at exactly
# the same point, and that's precisely when they're fully opaque and most
# readable. Two hits in one frame rendered as "79" and "10" stacked into an
# unreadable "7910". This pushes each new label off the spawn point straight
# away, so simultaneous popups are already separated on their first frame.
@export var spawn_scatter_radius: float = 10.0

# how much the scatter is squashed vertically. Damage numbers read better
# fanned out sideways than stacked up a column, so this stays below 1.0.
@export var spawn_scatter_vertical_bias: float = 0.45


# =============================================================================
# EXPORTED SETTINGS — COLORS
# =============================================================================

@export var damage_color:  Color = Color(1.0, 0.3, 0.3, 1.0)  # red
@export var heal_color:    Color = Color(0.3, 1.0, 0.3, 1.0)  # green
@export var mana_color:    Color = Color(0.3, 0.5, 1.0, 1.0)  # blue
@export var levelup_color: Color = Color(1.0, 0.84, 0.0, 1.0) # gold
@export var skillup_color: Color = Color(0.3, 0.9, 1.0, 1.0)  # cyan

# NOTICE (amber) — "you can't do that right now": health already full, not
# enough mana, inventory full. Deliberately NOT damage red, which in this game
# means hp went down and would read as being hurt by your own potion.
@export var notice_color:  Color = Color(1.0, 0.76, 0.28, 1.0)  # amber


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var label: Label = $label


# =============================================================================
# STATE
# =============================================================================

var _elapsed: float = 0.0
var _start_position: Vector2
var _velocity: Vector2 = Vector2.ZERO

# Shared across every label in the game. Each new popup takes the next index
# and scatters along the golden angle, which is the classic way to place
# points so that CONSECUTIVE ones never land near each other — random offsets
# would still collide roughly as often as they don't. Wrapping the counter
# keeps it from growing without bound over a long session.
static var _spawn_index: int = 0

# active lifetime for THIS instance — set per show call so level-up popups
# can linger longer (or shorter) than the default numeric lifetime.
var _active_lifetime: float = 1.0


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# intentionally empty. _start_position is captured in the show call
	# because _ready fires before the spawner sets global_position.
	pass


func _process(delta: float) -> void:
	# physics-style arc: integrate velocity, apply gravity, update position.
	# fade kicks in at fade_start_progress and runs to lifetime end.
	_elapsed += delta

	if _elapsed >= _active_lifetime:
		queue_free()
		return

	_velocity.y += gravity * delta
	global_position += _velocity * delta

	var progress: float = _elapsed / _active_lifetime
	if progress >= fade_start_progress:
		var fade_progress: float = (progress - fade_start_progress) / (1.0 - fade_start_progress)
		modulate.a = 1.0 - fade_progress
	else:
		modulate.a = 1.0


# =============================================================================
# PUBLIC API — NUMERIC POPUPS (damage / heal / mana)
# =============================================================================

func show_number(amount: int, type: Type, scale_factor: float = 1.0) -> void:
	scale = Vector2(scale_factor, scale_factor)
	_begin(str(amount), type, lifetime)


# =============================================================================
# PUBLIC API — TEXT POPUPS (level-up / skill-up)
# =============================================================================

func show_text(message: String, type: Type, life_override: float = -1.0, scale_factor: float = 1.0) -> void:
	# word popup for LEVEL UP! / Defence 5 etc. life_override lets the caller
	# set a longer/shorter linger; scale_factor sizes the whole label.
	var life: float = life_override if life_override > 0.0 else lifetime
	scale = Vector2(scale_factor, scale_factor)
	_begin(message, type, life)


# =============================================================================
# SHARED SETUP
# =============================================================================

func _begin(text: String, type: Type, life: float) -> void:
	# shared spawn logic for both numeric and text popups. captures position,
	# sets text + color by type, randomizes drift + jitter, starts the arc.
	if label == null:
		push_warning("FloatingLabel: child 'label' node missing — text won't render")
		return

	_active_lifetime = life
	_elapsed = 0.0

	# fan out from the spawn point BEFORE caching the position, so labels that
	# appear on the same frame are already separated rather than relying on
	# drift velocity to pull them apart later.
	if spawn_scatter_radius > 0.0:
		_spawn_index = (_spawn_index + 1) % 1000
		var angle: float = float(_spawn_index) * 2.3999632  # golden angle, radians
		global_position += Vector2(
			cos(angle),
			sin(angle) * spawn_scatter_vertical_bias
		) * spawn_scatter_radius

	# cache position NOW — this is the spawner's intended location
	_start_position = global_position

	# upward pop + small random horizontal drift so multi-hit popups spread
	var drift: float = randf_range(-horizontal_drift_range, horizontal_drift_range)
	_velocity = Vector2(drift, initial_velocity_y)

	# small random rotation jitter for visual variety
	rotation = randf_range(-rotation_jitter_range, rotation_jitter_range)

	label.text = text

	match type:
		Type.DAMAGE:  label.modulate = damage_color
		Type.HEAL:    label.modulate = heal_color
		Type.MANA:    label.modulate = mana_color
		Type.LEVELUP: label.modulate = levelup_color
		Type.SKILLUP: label.modulate = skillup_color
		Type.NOTICE:  label.modulate = notice_color
