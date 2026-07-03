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
#
# motion (physics-feel arc):
# labels shoot upward with initial velocity, gravity decelerates them at the
# peak, then they fall back a bit before settling. fade-out runs in parallel.
#
# important: _start_position is captured in the show_* call, NOT _ready().
# _ready fires the moment add_child() runs — BEFORE the spawner sets
# global_position. capturing on show ensures the cached position is correct.
extends Node2D


# =============================================================================
# TYPE ENUM
# =============================================================================

enum Type {
	DAMAGE,
	HEAL,
	MANA,
	LEVELUP,
	SKILLUP,
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


# =============================================================================
# EXPORTED SETTINGS — COLORS
# =============================================================================

@export var damage_color:  Color = Color(1.0, 0.3, 0.3, 1.0)  # red
@export var heal_color:    Color = Color(0.3, 1.0, 0.3, 1.0)  # green
@export var mana_color:    Color = Color(0.3, 0.5, 1.0, 1.0)  # blue
@export var levelup_color: Color = Color(1.0, 0.84, 0.0, 1.0) # gold
@export var skillup_color: Color = Color(0.3, 0.9, 1.0, 1.0)  # cyan


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
