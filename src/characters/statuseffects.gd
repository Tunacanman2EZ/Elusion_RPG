# statuseffects.gd - what a boss's element does to you besides the damage
# (0.77.0).
#
# The owner: "we can add real elements and effects slow on ice etc". Until this
# the element of a hit was a colour and a resistance - an ice boss and a fire
# boss differed in numbers, never in how they made you play. Each boss now
# carries one effect (bossenemy.gd, THE KITS), put on you by its stalagmites,
# its bullets and, for the ones that belong to the ground, its puddles:
#
#   chill    ice     20% slower a hit, 40% at two; a third hit freezes you
#   frozen           held where you stand for FROZEN_SECONDS
#   burn     fire    damage over BURN_SECONDS - another hit refreshes it, it
#                    never stacks
#   soaked   water   no sprint for SOAKED_SECONDS
#   shove    wind    knocked back along the hit
#   pull     wind    (its phase-three vortex) drawn toward the boss, slower
#                    than you walk
#   root     earth   held where you stand for ROOT_SECONDS
#   dazzle   light   a flash, and the edges of the screen go dark for
#                    DAZZLE_SECONDS
#   wither   dark    your healing is halved for WITHER_SECONDS
#
# CLEARABLE IS THE RULE EVERY ONE OF THEM IS HELD TO. The owner: "each boss
# needs to be a challenge but also clearable". So:
#   - nothing slows you more than 40% (SLOW_FLOOR);
#   - after frozen or rooted ends, neither can happen again for HOLD_IMMUNITY
#     seconds - nothing can hold you twice in a row;
#   - nothing lasts longer than 3 s, and every one of them refreshes rather
#     than stacks, except chill, whose stacks are the point and are capped;
#   - you can always attack, held or not;
#   - a puddle can chill but never freeze (GROUND): standing on ice slows you,
#     being hit by it is what freezes.
#
# ANY CHARACTER WITH take_damage() CAN CARRY ONE: a child node named
# "statuseffects", made by player.gd, and by the stand-in in the boss
# measurement (tools/bossmeasure.gd), which is how the measurement plays a
# chilled or rooted player honestly. Hazards reach it through apply_to(),
# which does nothing to a body without one.
#
# YOUR OWN PLAYER ONLY, AND NOTHING IS SENT. Every hazard in this game hurts
# the player of the game that draws it (bossprojectile, acidpuddle,
# BulletZone), so each game puts the effects on its own player from its own
# copy of the hazard, the same way it takes the damage.
#
# NO NEW ART. The owner's rule is his artists' art only. An effect is shown as
# a tint on your own sprite (self_modulate, which nothing else on a character
# writes), a word over your head in the game's own floating text when it
# starts, and - for dazzle - a darkening drawn by a shader.
#
# NO class_name, ON PURPOSE (CLAUDE.md, "A brand-new class_name is invisible
# until the editor rescans"): everything that uses this preloads it by path,
#   const StatusEffects := preload("res://src/characters/statuseffects.gd")
# so a checkout the editor has not scanned since this file arrived still runs.
extends Node

const HitSource := preload("res://src/shared/hitsource.gd")


const NODE_NAME := &"statuseffects"
const SELF_PATH := "res://src/characters/statuseffects.gd"

const CHILL := &"chill"
const FROZEN := &"frozen"
const BURN := &"burn"
const SOAKED := &"soaked"
const SHOVE := &"shove"
const PULL := &"pull"
const ROOT := &"root"
const DAZZLE := &"dazzle"
const WITHER := &"wither"

# Which effect a boss of each element carries. The one table: the kits
# (bossenemy.gd), the bullets (BulletZone), the spikes (bossprojectile.gd) and
# the puddles (acidpuddle.gd) all ask here, so a boss's effect cannot differ
# between its own attacks.
const FOR_ELEMENT := {
	Element.Type.ICE: CHILL,
	Element.Type.FIRE: BURN,
	Element.Type.WATER: SOAKED,
	Element.Type.WIND: SHOVE,
	Element.Type.EARTH: ROOT,
	Element.Type.LIGHT: DAZZLE,
	Element.Type.DARK: WITHER,
}

# The ones a puddle may carry: the ones about ground. A puddle that shoved,
# rooted or dazzled you on every tick of standing in it would be a trap, not a
# hazard.
const GROUND := [CHILL, BURN, SOAKED, WITHER]

# --- chill and frozen ---------------------------------------------------------
const CHILL_STEP := 0.2
const SLOW_FLOOR := 0.6
const CHILL_SECONDS := 2.0
const CHILL_TO_FREEZE := 3
const FROZEN_SECONDS := 0.8

# --- root, and the immunity after either hold ---------------------------------
const ROOT_SECONDS := 0.6
const HOLD_IMMUNITY := 4.0

# --- burn ---------------------------------------------------------------------
const BURN_SECONDS := 3.0
const BURN_TICK := 0.5
# Each tick, this share of the hit that lit it: six ticks, about half the hit
# again over three seconds - for walking out of a fire pincer too late.
const BURN_SHARE := 0.08

# --- soaked -------------------------------------------------------------------
const SOAKED_SECONDS := 3.0

# --- shove and pull -----------------------------------------------------------
# A shove leaves at SHOVE_SPEED and slows evenly to nothing over SHOVE_SECONDS:
# 400 x 0.2 / 2 = 40 px, stopped by walls like any step.
const SHOVE_SPEED := 400.0
const SHOVE_SECONDS := 0.2
# A pull is never as fast as walking (90): you can always walk out of it.
const PULL_SPEED_MAX := 50.0

# --- dazzle -------------------------------------------------------------------
const DAZZLE_SECONDS := 2.0
# At most one flash this often, however many orbs land: a dazzle refreshed by a
# spoke of six is one flash, not six. The flash is a soft veil (FLASH_ALPHA),
# never a strobe.
const DAZZLE_FLASH_GAP := 2.0
const FLASH_ALPHA := 0.4
const FLASH_SECONDS := 0.3
# How far in the dark comes, as a share of the screen's height from its middle
# to where the dark is full (DAZZLE_DARKEST): you can still see round you.
const DAZZLE_CLEAR := 0.36
const DAZZLE_DARKEST := 0.8
const DAZZLE_RAMP := 0.15

# --- wither -------------------------------------------------------------------
const WITHER_SECONDS := 3.0
const WITHER_HEAL := 0.5

# The word over your head when one starts. Refreshing one says nothing.
const WORDS := {
	CHILL: "Chilled", FROZEN: "Frozen", BURN: "Burning", SOAKED: "Soaked",
	ROOT: "Rooted", DAZZLE: "Dazzled", WITHER: "Withered",
}
const WORD_ELEMENT := {
	CHILL: Element.Type.ICE, FROZEN: Element.Type.ICE, BURN: Element.Type.FIRE,
	SOAKED: Element.Type.WATER, ROOT: Element.Type.EARTH, DAZZLE: Element.Type.LIGHT,
	WITHER: Element.Type.DARK,
}

# The tint on your sprite, the strongest effect's when there are several.
const TINT_ORDER := [FROZEN, ROOT, BURN, CHILL, SOAKED, WITHER, DAZZLE]
const TINTS := {
	FROZEN: Color(0.55, 0.78, 1.0),
	ROOT: Color(0.86, 0.74, 0.52),
	BURN: Color(1.0, 0.72, 0.5),
	CHILL: Color(0.74, 0.88, 1.0),
	SOAKED: Color(0.72, 0.82, 1.0),
	WITHER: Color(0.8, 0.68, 0.92),
	DAZZLE: Color(1.0, 1.0, 0.82),
}

const DAZZLE_SHADER := """
shader_type canvas_item;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float clear_share = 0.36;
uniform float darkest = 0.8;
void fragment() {
	vec2 at = SCREEN_UV - vec2(0.5);
	at.x *= SCREEN_PIXEL_SIZE.y > 0.0 ? SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x : 1.0;
	float inner = mix(0.95, clear_share, amount);
	float dark = smoothstep(inner, inner + 0.2, length(at)) * amount * darkest;
	float veil = flash;
	vec3 colour = mix(vec3(0.0), vec3(1.0, 1.0, 0.9), veil / max(veil + dark, 0.0001));
	COLOR = vec4(colour, max(dark, veil));
}
"""


var host: Node2D = null

var chill_stacks: int = 0
var chill_left: float = 0.0
var frozen_left: float = 0.0
var root_left: float = 0.0
var hold_immune_left: float = 0.0
var burn_left: float = 0.0
var burn_damage: int = 0
var _burn_tick_left: float = 0.0
var soaked_left: float = 0.0
var shove_velocity: Vector2 = Vector2.ZERO
var shove_left: float = 0.0
var pull_to: Vector2 = Vector2.ZERO
var pull_left: float = 0.0
var pull_speed: float = 0.0
var dazzle_left: float = 0.0
var wither_left: float = 0.0

# Every effect that started, in order, for the measurement and the tests.
var started: Array[StringName] = []

var _flash_gap_left: float = 0.0
var _flash_left: float = 0.0
var _veil: CanvasLayer = null
var _veil_material: ShaderMaterial = null
var _tinted: bool = false


# =============================================================================
# FINDING ONE
# =============================================================================

static func of(body: Node) -> Node:
	"""The effects a body carries, or null when it carries none."""
	if body == null or not is_instance_valid(body):
		return null
	return body.get_node_or_null(NodePath(NODE_NAME))


static func attach(body: Node2D) -> Node:
	"""Gives `body` its effects node, or hands back the one it has."""
	var have: Node = of(body)
	if have != null:
		return have
	var made: Node = (load(SELF_PATH) as GDScript).new()
	made.name = NODE_NAME
	made.set(&"host", body)
	body.add_child(made)
	return made


static func for_element(element: int) -> StringName:
	"""The effect a boss of `element` carries; &"" for one with none."""
	return FOR_ELEMENT.get(element, &"")


static func apply_to(body: Node, kind: StringName, amount: int = 0,
		from: Vector2 = Vector2.INF, ground: bool = false, strength: float = 1.0) -> bool:
	"""Puts `kind` on `body` if it carries effects; true when something
	started or was refreshed. `amount` is the hit that carried it (burn reads
	it), `from` where it came from (shove reads it), `ground` that it came off a
	puddle (see GROUND), `strength` how hard (1 a boss's; under 1 the Field's,
	0.86.0 - see apply())."""
	if kind == &"":
		return false
	var fx: Node = of(body)
	if fx == null or not fx.has_method(&"apply"):
		return false
	return bool(fx.call(&"apply", kind, amount, from, ground, strength))


# =============================================================================
# PUTTING ONE ON
# =============================================================================

func _ready() -> void:
	if host == null:
		host = get_parent() as Node2D


func apply(kind: StringName, amount: int = 0, from: Vector2 = Vector2.INF,
		ground: bool = false, strength: float = 1.0) -> bool:
	# SOFTER (0.86.0, the Field at 0.5): every effect lasts `strength` as long,
	# a burn bites and a shove pushes `strength` as hard, and under 1 nothing
	# takes the controls away - chill never freezes, earth never roots.
	if _host_dying():
		return false
	if ground and not GROUND.has(kind):
		return false
	var s: float = clampf(strength, 0.1, 1.0)
	var soft: bool = s < 1.0
	match kind:
		CHILL:
			return _chill(ground or soft, s)
		BURN:
			var was: bool = burn_left > 0.0
			burn_left = maxf(burn_left, BURN_SECONDS * s)
			burn_damage = maxi(burn_damage if was else 0, maxi(1, roundi(amount * BURN_SHARE * s)))
			if not was:
				_burn_tick_left = BURN_TICK
				_started(BURN)
			return true
		SOAKED:
			var was_soaked: bool = soaked_left > 0.0
			soaked_left = maxf(soaked_left, SOAKED_SECONDS * s)
			if not was_soaked:
				_started(SOAKED)
			return true
		SHOVE:
			if from == Vector2.INF or host == null:
				return false
			var away: Vector2 = _body_point() - from
			if away.length_squared() < 0.01:
				return false
			shove_velocity = away.normalized() * SHOVE_SPEED * s
			shove_left = SHOVE_SECONDS
			_started(SHOVE, false)
			return true
		ROOT:
			if soft or frozen_left > 0.0 or root_left > 0.0 or hold_immune_left > 0.0:
				return false
			root_left = ROOT_SECONDS
			_started(ROOT)
			return true
		DAZZLE:
			var was_dazzled: bool = dazzle_left > 0.0
			dazzle_left = maxf(dazzle_left, DAZZLE_SECONDS * s)
			if _flash_gap_left <= 0.0:
				_flash_gap_left = DAZZLE_FLASH_GAP
				_flash_left = FLASH_SECONDS
			if not was_dazzled:
				_started(DAZZLE)
			_ensure_veil()
			return true
		WITHER:
			var was_withered: bool = wither_left > 0.0
			wither_left = maxf(wither_left, WITHER_SECONDS * s)
			if not was_withered:
				_started(WITHER)
			return true
	return false


func pull(toward: Vector2, seconds: float, speed: float) -> void:
	"""Draws the body toward `toward` for `seconds` at `speed` (held under
	PULL_SPEED_MAX, so walking always beats it)."""
	if _host_dying():
		return
	pull_to = toward
	pull_left = maxf(pull_left, seconds)
	pull_speed = clampf(speed, 0.0, PULL_SPEED_MAX)
	_started(PULL, false)


func _chill(ground: bool, strength: float = 1.0) -> bool:
	if frozen_left > 0.0:
		return false
	var was: int = chill_stacks
	chill_stacks += 1
	chill_left = maxf(chill_left, CHILL_SECONDS * strength)
	if strength < 1.0:
		# Soft: one stack at most, a fifth slower, never frozen.
		chill_stacks = mini(chill_stacks, 1)
	if chill_stacks >= CHILL_TO_FREEZE:
		if ground or hold_immune_left > 0.0:
			chill_stacks = CHILL_TO_FREEZE - 1
		else:
			chill_stacks = 0
			chill_left = 0.0
			frozen_left = FROZEN_SECONDS
			_started(FROZEN)
			return true
	if was == 0:
		_started(CHILL)
	return true


func _started(kind: StringName, say: bool = true) -> void:
	started.append(kind)
	if say and host != null and host.has_method(&"show_status_word") and WORDS.has(kind):
		host.call(&"show_status_word", WORDS[kind], int(WORD_ELEMENT.get(kind, Element.Type.NONE)))


# =============================================================================
# WHAT THE CHARACTER ASKS
# =============================================================================

func speed_scale() -> float:
	"""What your walk is multiplied by: 0 while held, down to SLOW_FLOOR."""
	if frozen_left > 0.0 or root_left > 0.0:
		return 0.0
	return maxf(SLOW_FLOOR, 1.0 - CHILL_STEP * chill_stacks)


func can_sprint() -> bool:
	return soaked_left <= 0.0 and speed_scale() > 0.0


func heal_scale() -> float:
	return WITHER_HEAL if wither_left > 0.0 else 1.0


func is_held() -> bool:
	return frozen_left > 0.0 or root_left > 0.0


func push_velocity() -> Vector2:
	"""Movement on top of your own this frame: a shove, a pull, both or none.
	Added to velocity for the move and taken off again after it, so a class
	that eases its velocity (the tank) does not carry it into the next."""
	var push: Vector2 = Vector2.ZERO
	if shove_left > 0.0:
		push += shove_velocity * (shove_left / SHOVE_SECONDS)
	if pull_left > 0.0 and host != null:
		var toward: Vector2 = pull_to - _body_point()
		if toward.length() > 4.0:
			push += toward.normalized() * pull_speed
	return push


func active() -> Array[StringName]:
	"""What is on the body right now."""
	var on: Array[StringName] = []
	if chill_stacks > 0:
		on.append(CHILL)
	if frozen_left > 0.0:
		on.append(FROZEN)
	if burn_left > 0.0:
		on.append(BURN)
	if soaked_left > 0.0:
		on.append(SOAKED)
	if shove_left > 0.0:
		on.append(SHOVE)
	if pull_left > 0.0:
		on.append(PULL)
	if root_left > 0.0:
		on.append(ROOT)
	if dazzle_left > 0.0:
		on.append(DAZZLE)
	if wither_left > 0.0:
		on.append(WITHER)
	return on


func clear_all() -> void:
	chill_stacks = 0
	chill_left = 0.0
	frozen_left = 0.0
	root_left = 0.0
	hold_immune_left = 0.0
	burn_left = 0.0
	burn_damage = 0
	soaked_left = 0.0
	shove_left = 0.0
	pull_left = 0.0
	dazzle_left = 0.0
	wither_left = 0.0
	_flash_left = 0.0
	_show()


# =============================================================================
# THE CLOCK
# =============================================================================

func _physics_process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	"""Runs every effect on by `delta` seconds. The tests call it directly."""
	if _host_dying():
		if not active().is_empty() or _flash_left > 0.0:
			clear_all()
		return

	if chill_left > 0.0:
		chill_left -= delta
		if chill_left <= 0.0:
			chill_left = 0.0
			chill_stacks = 0

	var was_held: bool = is_held()
	frozen_left = maxf(0.0, frozen_left - delta)
	root_left = maxf(0.0, root_left - delta)
	if was_held and not is_held():
		hold_immune_left = HOLD_IMMUNITY
	elif hold_immune_left > 0.0:
		hold_immune_left = maxf(0.0, hold_immune_left - delta)

	if burn_left > 0.0:
		var burning: float = minf(delta, burn_left)
		burn_left -= delta
		_burn_tick_left -= burning
		while _burn_tick_left <= 0.000001 and burn_damage > 0:
			_burn_tick_left += BURN_TICK
			if host != null and host.has_method(&"take_damage") and not _host_dying():
				HitSource.blame("effect:burn")
				host.call(&"take_damage", burn_damage, Element.Type.FIRE)
		if burn_left <= 0.0:
			burn_left = 0.0
			burn_damage = 0

	soaked_left = maxf(0.0, soaked_left - delta)
	shove_left = maxf(0.0, shove_left - delta)
	pull_left = maxf(0.0, pull_left - delta)
	dazzle_left = maxf(0.0, dazzle_left - delta)
	wither_left = maxf(0.0, wither_left - delta)
	_flash_gap_left = maxf(0.0, _flash_gap_left - delta)
	_flash_left = maxf(0.0, _flash_left - delta)
	_show()


# =============================================================================
# HOW IT IS SHOWN
# =============================================================================

func _show() -> void:
	_tint()
	if _veil_material != null:
		var amount: float = 0.0
		if dazzle_left > 0.0:
			var since: float = DAZZLE_SECONDS - dazzle_left
			amount = clampf(since / DAZZLE_RAMP, 0.0, 1.0) * clampf(dazzle_left / 0.5, 0.0, 1.0)
		_veil_material.set_shader_parameter(&"amount", amount)
		_veil_material.set_shader_parameter(&"flash", FLASH_ALPHA * _flash_left / FLASH_SECONDS)
		_veil.visible = amount > 0.0 or _flash_left > 0.0


func tint() -> Color:
	"""The colour your sprite wears now: the strongest effect's, or white."""
	var on: Array[StringName] = active()
	for kind in TINT_ORDER:
		if on.has(kind):
			return TINTS[kind]
	return Color.WHITE


func _tint() -> void:
	if host == null:
		return
	var sprite: CanvasItem = host.get_node_or_null(^"animatedsprite2d") as CanvasItem
	if sprite == null:
		return
	var colour: Color = tint()
	if colour == Color.WHITE and not _tinted:
		return
	sprite.self_modulate = colour
	_tinted = colour != Color.WHITE


func _ensure_veil() -> void:
	# THE DARK IS ON YOUR SCREEN ONLY, so only your own player gets one - a
	# stand-in or a test body carrying effects has no screen to darken.
	if _veil != null or host == null or not host.is_in_group(&"player") or not is_inside_tree():
		return
	_veil = CanvasLayer.new()
	_veil.name = "dazzle"
	# Over the world, under the menus.
	_veil.layer = 40
	var rect := ColorRect.new()
	rect.name = "veil"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = DAZZLE_SHADER
	_veil_material = ShaderMaterial.new()
	_veil_material.shader = shader
	_veil_material.set_shader_parameter(&"clear_share", DAZZLE_CLEAR)
	_veil_material.set_shader_parameter(&"darkest", DAZZLE_DARKEST)
	rect.material = _veil_material
	_veil.add_child(rect)
	_veil.visible = false
	add_child(_veil)


func _host_dying() -> bool:
	if host == null or not is_instance_valid(host):
		return true
	var dying: Variant = host.get(&"is_dying")
	return dying is bool and dying


func _body_point() -> Vector2:
	if host == null:
		return Vector2.ZERO
	var shape: Node2D = host.get_node_or_null(^"bodyshape") as Node2D
	return shape.global_position if shape != null else host.global_position
