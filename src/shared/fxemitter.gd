# fxemitter.gd - a particle cloud with nothing of its own to work out or draw
# (0.174.4): fxparticles.gd draws it, with every other cloud of its layer, in
# one draw, and where each particle is comes from the card.
#
# The owner, of the Every effect sweep on his card: "we need to majorly
# refine mages meteor and mages spike and dynamite". Each meteor, blast and
# burning crater had CPUParticles2D of its own - 500 to 634 of them at once
# at the rates swept - and each was worked out on the processor and sent and
# drawn on its own every frame: about half of what those effects cost to
# draw (zz bench v16, "particles hidden").
#
# A STAND-IN FOR CPUParticles2D: the same names for what the effects set -
# amount, lifetime, emitting, one_shot, explosiveness, the emission shapes,
# direction and spread, gravity, speed, damping, orbit, scale (and its
# curve), the colour ramps, texture, local_coords - so an effect makes one of
# these where it made a CPUParticles2D, and a scene's node is one with this
# script. What it does not have, nothing here used: angles, hue, animation,
# radial and tangential acceleration.
#
# No class_name: preload it by path.
extends Node2D

# The drawer's script, loaded when the first emitter joins: not preloaded,
# as the drawer preloads this one.
const DRAWER_PATH := "res://src/shared/fxparticles.gd"
static var _drawer_script: GDScript = null

# CPUParticles2D's emission shapes, by the same numbers.
const EMISSION_SHAPE_POINT := 0
const EMISSION_SHAPE_SPHERE := 1
const EMISSION_SHAPE_SPHERE_SURFACE := 2
const EMISSION_SHAPE_RECTANGLE := 3

# CPUParticles2D's defaults, so a scene or a script that leaves one out gets
# what it got before.
var amount: int = 8: set = _set_amount
var lifetime: float = 1.0: set = _set_lifetime
var lifetime_randomness: float = 0.0: set = _set_lifetime_randomness
var explosiveness: float = 0.0: set = _set_explosiveness
var one_shot: bool = false: set = _set_one_shot
var emission_shape: int = EMISSION_SHAPE_POINT: set = _set_emission_shape
var emission_sphere_radius: float = 1.0: set = _set_emission_sphere_radius
var emission_rect_extents: Vector2 = Vector2.ONE: set = _set_emission_rect_extents
var direction: Vector2 = Vector2(1.0, 0.0): set = _set_direction
var spread: float = 45.0: set = _set_spread
var gravity: Vector2 = Vector2(0.0, 980.0): set = _set_gravity
var initial_velocity_min: float = 0.0: set = _set_initial_velocity_min
var initial_velocity_max: float = 0.0: set = _set_initial_velocity_max
var damping_min: float = 0.0: set = _set_damping_min
var damping_max: float = 0.0: set = _set_damping_max
var orbit_velocity_min: float = 0.0: set = _set_orbit_velocity_min
var orbit_velocity_max: float = 0.0: set = _set_orbit_velocity_max
var scale_amount_min: float = 1.0: set = _set_scale_amount_min
var scale_amount_max: float = 1.0: set = _set_scale_amount_max
var scale_amount_curve: Curve = null: set = _set_scale_amount_curve
var color_ramp: Gradient = null: set = _set_color_ramp
var color_initial_ramp: Gradient = null: set = _set_color_initial_ramp
var texture: Texture2D = null: set = _set_texture
var local_coords: bool = false: set = _set_local_coords
var emitting: bool = true: set = set_emitting

# A GLIDE (glide()): where it is drawn going from `glide_from` (its own
# axes, from where it stands) to where it stands, over `glide_seconds`,
# eased by progress to the power `glide_power` - worked out on the card, so
# nothing is written while it moves. A meteor's trail: left behind exactly
# along the fall, which a guess from its speed could not do on a fall that
# speeds up.
var glide_from: Vector2 = Vector2.ZERO
var glide_seconds: float = 0.0
var glide_power: float = 1.0
# Faded by a parent's modulate (a frost mark fading): the drawer reads its
# alpha every frame. Off, only its own show and hide are seen.
var follow_fades: bool = false

# The drawer's, while in a tree: which layer, which slot, when it began and
# stopped emitting (on the drawer's clock), its seed, and its rows.
var fx_drawer: Node = null
var fx_group: String = ""
var fx_slot: int = -1
var fx_t0: float = 0.0
var fx_t1: float = 1.0e9
var fx_seed: int = 0
var fx_row: int = 0
var fx_ramp: int = 0
var fx_curve: int = -1
var fx_was: Vector2 = Vector2.ZERO
var fx_params_dirty: bool = true
# Which layer it belongs in (z index, texture, lighting) asked again at its
# next write: its texture set, or it shown, after it joined.
var fx_key_dirty: bool = true
var fx_glide_start: float = 0.0
var fx_glide_pending: bool = false
var fx_alpha: float = -1.0


func _init() -> void:
	set_notify_transform(true)


func _enter_tree() -> void:
	if _drawer_script == null:
		_drawer_script = load(DRAWER_PATH) as GDScript
	fx_drawer = _drawer_script.call("of", self)
	if fx_drawer != null:
		fx_drawer.call("add", self)


func _exit_tree() -> void:
	if fx_drawer != null and is_instance_valid(fx_drawer):
		fx_drawer.call("remove", self)
	fx_drawer = null


func _notification(what: int) -> void:
	if fx_drawer == null:
		return
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		fx_drawer.call("moved", self)
	elif what == NOTIFICATION_VISIBILITY_CHANGED:
		fx_key_dirty = true
		fx_drawer.call("touched", self)


func set_emitting(on: bool) -> void:
	var was: bool = emitting
	emitting = on
	if fx_drawer != null and (on != was or (on and one_shot)):
		fx_drawer.call("emitting_changed", self)


func glide(from: Vector2, seconds: float, power: float = 1.0, already: float = 0.0) -> void:
	"""Drawn from `from` (its own axes, from where it stands) to where it
	stands, over `seconds`, `already` of them gone - eased by progress to the
	`power`. Set its position to the end first."""
	glide_from = from
	glide_seconds = maxf(seconds, 0.0)
	glide_power = maxf(power, 0.01)
	fx_glide_pending = fx_drawer == null
	fx_glide_start = (float(fx_drawer.get("now")) if fx_drawer != null else 0.0) - already
	_changed()


func gliding() -> bool:
	return glide_seconds > 0.0


func restart() -> void:
	"""As CPUParticles2D's: from the start again."""
	emitting = true
	if fx_drawer != null:
		fx_drawer.call("emitting_changed", self)


func relayer() -> void:
	"""Its z index or material changed after its first frame: the drawer
	puts it in the right layer at its next write. (Set before then, they are
	read anyway.)"""
	fx_key_dirty = true
	if fx_drawer != null:
		fx_drawer.call("touched", self)


func fx_numbers(most: int) -> PackedFloat32Array:
	"""Its numbers as the drawer's `params` row holds them (fxparticles.gd
	_rows_for() fills in the rows of its ramps). Read here, by name, as fast
	as GDScript reads anything."""
	var tex_size: Vector2 = texture.get_size() if texture != null else Vector2.ONE
	return PackedFloat32Array([
		float(mini(amount, most)), lifetime, lifetime_randomness, explosiveness,
		1.0 if one_shot else 0.0, float(emission_shape), emission_sphere_radius, emission_rect_extents.x,
		emission_rect_extents.y, direction.x, direction.y, deg_to_rad(spread),
		initial_velocity_min, initial_velocity_max, damping_min, damping_max,
		gravity.x, gravity.y, orbit_velocity_min, orbit_velocity_max,
		scale_amount_min, scale_amount_max, 1.0 if local_coords else 0.0, tex_size.x,
		tex_size.y, 0.0, 0.0, 0.0,
		glide_from.x, glide_from.y, glide_seconds, glide_power])


func unshaded() -> bool:
	var mat: CanvasItemMaterial = material as CanvasItemMaterial
	return mat != null and mat.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED


func _changed() -> void:
	fx_params_dirty = true
	if fx_drawer != null:
		fx_drawer.call("touched", self)


func _set_amount(v: int) -> void:
	amount = v
	_changed()


func _set_lifetime(v: float) -> void:
	lifetime = v
	_changed()


func _set_lifetime_randomness(v: float) -> void:
	lifetime_randomness = v
	_changed()


func _set_explosiveness(v: float) -> void:
	explosiveness = v
	_changed()


func _set_one_shot(v: bool) -> void:
	one_shot = v
	_changed()


func _set_emission_shape(v: int) -> void:
	emission_shape = v
	_changed()


func _set_emission_sphere_radius(v: float) -> void:
	emission_sphere_radius = v
	_changed()


func _set_emission_rect_extents(v: Vector2) -> void:
	emission_rect_extents = v
	_changed()


func _set_direction(v: Vector2) -> void:
	direction = v
	_changed()


func _set_spread(v: float) -> void:
	spread = v
	_changed()


func _set_gravity(v: Vector2) -> void:
	gravity = v
	_changed()


func _set_initial_velocity_min(v: float) -> void:
	initial_velocity_min = v
	_changed()


func _set_initial_velocity_max(v: float) -> void:
	initial_velocity_max = v
	_changed()


func _set_damping_min(v: float) -> void:
	damping_min = v
	_changed()


func _set_damping_max(v: float) -> void:
	damping_max = v
	_changed()


func _set_orbit_velocity_min(v: float) -> void:
	orbit_velocity_min = v
	_changed()


func _set_orbit_velocity_max(v: float) -> void:
	orbit_velocity_max = v
	_changed()


func _set_scale_amount_min(v: float) -> void:
	scale_amount_min = v
	_changed()


func _set_scale_amount_max(v: float) -> void:
	scale_amount_max = v
	_changed()


func _set_scale_amount_curve(v: Curve) -> void:
	scale_amount_curve = v
	_changed()


func _set_color_ramp(v: Gradient) -> void:
	color_ramp = v
	_changed()


func _set_color_initial_ramp(v: Gradient) -> void:
	color_initial_ramp = v
	_changed()


func _set_texture(v: Texture2D) -> void:
	texture = v
	fx_key_dirty = true
	_changed()


func _set_local_coords(v: bool) -> void:
	local_coords = v
	_changed()
