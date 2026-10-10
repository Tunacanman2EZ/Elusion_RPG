# remoteattacks.gd - another player's attacks, drawn on this screen (0.19.0).
#
# The owner, after his first game with somebody else: "i could not see their
# attacks but they could see mine". A swing was always seen - it is the body's
# own animation, and the presence server has carried that since 0.5. But a
# meteor, a thrown axe, a stick of dynamite, a slash wave or a healer's orb is a
# thing out in the world, and nothing carried those: he saw the student's body
# go through the motions and nothing come of it.
#
# Now the game that makes one tells the presence server (Presence.tell_attack(),
# the wire in presence.py's header), and every other game in the area spawns a
# PICTURE of it here: the very scene the attacker's game spawned, with
# `cosmetic` set, so it flies, spins, falls, blows up and burns exactly as
# theirs does and touches nothing. Each projectile script says what that leaves
# out - the hit, the XP, the camera shake, a pull, a chain - under "A PICTURE OF
# SOMEBODY ELSE'S".
#
# WHY A PICTURE CANNOT HURT ANYTHING, and must not. The monsters belong to the
# area's leader (monstersync.gd). The attacker's game already sends its real
# hits as hits ("h") and its kills to the API, and is paid for them there. A
# copy that hit as well would hit twice - on the leader's screen it would be
# the leader's game doing the damage, with the attacker's numbers.
#
# WHEN. Each attack carries the attacker's clock, and remoteplayer.gd plays it
# when its picture of that player reaches the same moment - so the meteor falls
# as their body finishes the cast, not a fifth of a second before it.
#
# WHAT IT USES FROM THE CLASS. The scenes are the ones the class scripts load
# (the suite holds them to it); the healer's orb, its speed and its tint, and
# the mage's stalagmite, are read from the class scene's own settings, once.
class_name RemoteAttacks
extends RefCounted

# The kinds, as presence.py ATTACK_KINDS has them.
const KINDS: Array = ["slash", "axe", "recall", "stalag", "meteor", "dyn", "orb"]
# What `flags` carries.
const FLAG_PULL := 1      # a meteor that pulls (meteor.gd, THE PULL)
const FLAG_WIDE := 2      # a wide axe (spinningaxe.gd, THE ROLL)
const FLAG_BLOODY := 4    # a bloody one
# The scenes warrior.gd, mage.gd and tank.gd preload. Loaded when first needed
# rather than preloaded: the projectile scripts call go_quiet() below, and a
# preload here would make each scene part of the script that loads it.
const SLASHWAVE_PATH := "res://scene/projectiles/slashwave.tscn"
const SPINNING_AXE_PATH := "res://scene/projectiles/spinningaxe.tscn"
const METEOR_PATH := "res://scene/projectiles/meteor.tscn"
const DYNAMITE_PATH := "res://scene/projectiles/dynamite.tscn"
# How far ahead of a slash wave or an orb its aim point is put on the wire:
# only the direction is read.
const AIM_AHEAD := 100.0

static var _scenes: Dictionary = {}
static var _class_settings: Dictionary = {}


static func go_quiet(area: Area2D) -> void:
	"""A picture's Area2D: it watches nothing and nothing sees it. Deferred, as
	this may run inside a physics callback; the picture's own guards keep the
	frame before it from doing anything."""
	area.set_deferred("monitoring", false)
	area.set_deferred("monitorable", false)
	area.set_deferred("collision_layer", 0)


static func flags_for_axe(wide: bool, bloody: bool) -> int:
	return (FLAG_WIDE if wide else 0) | (FLAG_BLOODY if bloody else 0)


static func fire(body: Node2D, attack: Array) -> Array:
	"""Spawns the picture of one attack - [kind, ts, ox, oy, tx, ty, delay ms,
	flags], as the presence server passes it on - for `body`, the picture of
	the player who made it. Returns what was spawned, for the tests."""
	if body == null or not body.is_inside_tree() or attack.size() < 8:
		return []
	var kind: String = str(attack[0])
	var origin := Vector2(float(attack[2]), float(attack[3]))
	var target := Vector2(float(attack[4]), float(attack[5]))
	var delay: float = clampf(float(attack[6]) / 1000.0, 0.0, 3.0)
	var flags: int = int(attack[7])
	var made: Node = null
	match kind:
		"slash":
			made = _slash(body, origin, target)
		"axe":
			made = _axe(body, origin, target, flags)
		"recall":
			var out: Variant = body.get("axe")
			if out is SpinningAxe and is_instance_valid(out):
				(out as SpinningAxe).recall()
		"stalag":
			made = _stalagmite(body, origin, target)
		"meteor":
			made = _meteor(body, origin, target, delay, flags)
		"dyn":
			made = _stick(body, origin, target, delay)
		"orb":
			made = _orb(body, origin, target)
	return [made] if made != null else []


# =============================================================================
# EACH KIND - what the class script does when it attacks, less the numbers
# =============================================================================

static func _slash(body: Node2D, origin: Vector2, target: Vector2) -> Node:
	var wave: SlashWave = _scene(SLASHWAVE_PATH).instantiate()
	wave.cosmetic = true
	wave.damage = 0
	_parent(body, true).add_child(wave)
	wave.global_position = origin
	wave.reset_physics_interpolation()
	wave.shoot_vector(_aim(origin, target))
	return wave


static func _axe(body: Node2D, origin: Vector2, target: Vector2, flags: int) -> Node:
	# One axe out per warrior, as warrior.gd has it: a new throw takes the
	# place of a picture that somehow never came home.
	var old: Variant = body.get("axe")
	if old is Node and is_instance_valid(old):
		(old as Node).queue_free()
	var axe: SpinningAxe = _scene(SPINNING_AXE_PATH).instantiate()
	axe.cosmetic = true
	axe.wounds = false
	# Home is their picture: it flies back to the body this screen draws.
	axe.caster = body
	axe.wide = flags & FLAG_WIDE != 0
	axe.bloody = flags & FLAG_BLOODY != 0
	_parent(body, true).add_child(axe)
	axe.throw_to(origin, target)
	body.set("axe", axe)
	Audio.play_at("axe_throw", origin)
	return axe


static func _stalagmite(body: Node2D, origin: Vector2, target: Vector2) -> Node:
	var scene: PackedScene = class_setting("mage", "target_circle_scene") as PackedScene
	if scene == null:
		return null
	var spell: Node2D = scene.instantiate() as Node2D
	if "cosmetic" in spell:
		spell.set("cosmetic", true)
	body.get_tree().current_scene.add_child(spell)
	spell.global_position = target
	spell.reset_physics_interpolation()
	Audio.play_at("spell_cast", origin)
	return spell


static func _meteor(body: Node2D, origin: Vector2, target: Vector2, delay: float, flags: int) -> Node:
	var meteor: Meteor = _scene(METEOR_PATH).instantiate()
	meteor.cosmetic = true
	meteor.delay = delay
	meteor.pulls = flags & FLAG_PULL != 0
	_parent(body, false).add_child(meteor)
	meteor.global_position = target
	meteor.reset_physics_interpolation()
	if delay <= 0.0:
		Audio.play_at("spell_cast", origin)
	return meteor


static func _stick(body: Node2D, origin: Vector2, target: Vector2, delay: float) -> Node:
	var stick: Dynamite = _scene(DYNAMITE_PATH).instantiate()
	stick.cosmetic = true
	stick.delay = delay
	_parent(body, true).add_child(stick)
	stick.throw_from(origin, target)
	if delay <= 0.0:
		Audio.play_at("dynamite_throw", origin)
	return stick


static func _orb(body: Node2D, origin: Vector2, target: Vector2) -> Node:
	# Ten a second from a healer, so no sound: their own game plays it for them.
	var scene: PackedScene = class_setting("healer", "projectile_scene") as PackedScene
	if scene == null:
		return null
	var orb: Node2D = scene.instantiate() as Node2D
	if "cosmetic" in orb:
		orb.set("cosmetic", true)
	body.get_tree().current_scene.add_child(orb)
	orb.global_position = origin
	orb.reset_physics_interpolation()
	orb.modulate = class_setting("healer", "projectile_tint", Color.WHITE)
	if "direction" in orb:
		orb.set("direction", _aim(origin, target))
	if "speed" in orb:
		orb.set("speed", float(class_setting("healer", "projectile_speed", 200.0)))
	if "damage" in orb:
		orb.set("damage", 0)
	return orb


# =============================================================================
# HELPERS
# =============================================================================

static func _aim(origin: Vector2, target: Vector2) -> Vector2:
	var aim: Vector2 = target - origin
	return aim.normalized() if aim.length() > 0.01 else Vector2.DOWN


static func _parent(body: Node2D, in_the_air: bool) -> Node:
	# Where the attacker's own game puts it: player.gd's spawn_parent().
	var tree: SceneTree = body.get_tree()
	if in_the_air:
		var container: Node = tree.get_first_node_in_group("projectiles")
		if container != null:
			return container
	return tree.current_scene


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


static func class_setting(cls: String, property: String, fallback: Variant = null) -> Variant:
	"""A setting from a class scene - its projectile, how fast and what colour
	- read once from the scene itself, as remoteplayer.gd reads its sprites."""
	if not _class_settings.has(cls):
		var settings: Dictionary = {}
		var path: String = "res://scene/characters/%s.tscn" % cls
		var packed: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else null
		var instance: Node = packed.instantiate() if packed != null else null
		if instance != null:
			for name in ["projectile_scene", "projectile_speed", "projectile_tint", "target_circle_scene"]:
				if name in instance:
					settings[name] = instance.get(name)
			instance.free()
		_class_settings[cls] = settings
	var found: Variant = (_class_settings[cls] as Dictionary).get(property)
	return found if found != null else fallback
