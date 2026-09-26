# bossstalker.gd — a hazard that hunts the player, leaving erupting pillars
# along its path.
#
# WHAT IT IS FOR. Every other thing the boss does is a PATTERN: a shape stamped
# on the floor at one moment, which the player answers by being somewhere else.
# All of them share a weakness — they are over once they land, so the pressure
# comes in pulses with quiet between. The stalker is the opposite: it never
# lands, it just keeps coming, and it is the reason the player cannot stop
# moving between casts.
#
# Together the two make a vice. The patterns punish moving PREDICTABLY, because
# they are aimed where the player is heading (see AIM_LEAD in bossenemy.gd).
# The stalker punishes not moving at all. Neither alone is hard; a player who
# has to keep moving AND keep changing direction is actually being asked
# something.
#
#
# WHY THIS IS FAIR, WHICH MATTERS MORE HERE THAN ANYWHERE ELSE IN THIS FIGHT.
#
# bossprojectile.gd's header is emphatic that a telegraph which tracks its
# target is not a telegraph — it is a delayed guaranteed hit, with no correct
# response, so it teaches nothing. A thing that follows the player looks like
# exactly that mistake, and it is not, for one reason: IT IS SLOWER THAN THEY
# ARE and always visible. Its pillars are still stamped on fixed ground with a
# real warning; only the SOURCE moves. The counter is kiting, which is a real
# answer available at every moment.
#
# The moment STALK_SPEED goes above the player's 90, all of that stops being
# true and this becomes the unfair thing the header warns about.
#
#
# NO SCENE FILE AND NO ART. It is a bare Node2D the boss creates in code; what
# the player sees is the trail of pillars it leaves, which reuses the pillar
# scene the rest of the fight already uses. That is deliberate — a hazard whose
# body is invisible cannot be mistaken for something you are meant to attack.
extends Node2D
class_name BossStalker


# Slower than the player's 90 by a wide margin. See the fairness note above:
# this number is the whole reason the stalker is legitimate, and raising it past
# 90 turns the fight into a coin flip no matter what else is tuned.
@export var stalk_speed: float = 52.0

# Seconds between the pillars it drops. Roughly one every body-length it
# travels, so the trail reads as a continuous line of destruction rather than
# scattered dots.
@export var stalk_interval: float = 0.5

# How long it hunts before giving up. Long enough to matter across two or three
# casts, short enough that the floor is not permanently full of them.
@export var stalk_lifetime: float = 7.0

# A short warning, because the player can SEE this coming — the stalker has
# been walking toward them for seconds. The pattern telegraphs are longer
# because those appear from nothing.
@export var pillar_telegraph: float = 0.5

@export var pillar_damage: int = 22
@export var pillar_radius: float = 16.0

# Stops it grinding into the player's feet once it catches someone who has
# stopped. It still drops pillars; it just does not climb inside them.
@export var contact_distance: float = 14.0

var pillar_scene: PackedScene = null

var _player: Node2D = null
var _age: float = 0.0
var _drop_accumulator: float = 0.0


func setup(player_node: Node2D, scene: PackedScene) -> void:
	# Passed in rather than looked up, because the boss already has both and a
	# second group lookup is a second thing that can disagree with the first.
	_player = player_node
	pillar_scene = scene


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= stalk_lifetime:
		queue_free()
		return

	if not is_instance_valid(_player):
		queue_free()
		return

	# WALK, DO NOT TELEPORT. A constant-speed step toward the player's current
	# position is what makes this readable: its heading changes gradually, so a
	# player can see where it will be and plan around it.
	var to_player: Vector2 = _player_ground() - global_position
	if to_player.length() > contact_distance:
		global_position += to_player.normalized() * stalk_speed * delta

	_drop_accumulator += delta
	if _drop_accumulator >= stalk_interval:
		# Subtracted rather than zeroed, so a long frame does not swallow the
		# remainder and let the drop rate drift.
		_drop_accumulator -= stalk_interval
		_drop_pillar()


# The floor the player is standing on, which is not their node origin - see the
# same note in BossEnemy._aim_point(). The stalker walks along the ground and
# drops hazards on it, so chasing the origin would have it trailing 13px behind
# a warrior's feet and 18px ahead of a tank's.
func _player_ground() -> Vector2:
	if not is_instance_valid(_player):
		return global_position
	var body: Node2D = _player.get_node_or_null("bodyshape") as Node2D
	if body != null:
		return body.global_position
	return _player.global_position


func _drop_pillar() -> void:
	if pillar_scene == null:
		return

	var container: Node = get_tree().get_first_node_in_group("groundeffects")
	if container == null:
		container = get_tree().current_scene
	if container == null:
		return

	var pillar: Node2D = pillar_scene.instantiate()

	# CONFIGURED BEFORE IT ENTERS THE TREE, the same order
	# bossenemy._spawn_one_eruption() and poisonslime._spawn_slime() both use.
	#
	# add_child() runs bossprojectile.gd's _ready(), which calls
	# _apply_element_profile() — and that function MULTIPLIES rather than sets:
	#
	#     telegraph_seconds = telegraph_seconds * p["telegraph"]
	#     damage            = damage * p["damage"]
	#     scale            *= p["size"]
	#
	# These lines used to run AFTER add_child, so all three were applied to the
	# scene's defaults and then flattened by the assignments below — a stalker
	# trail wore its element's ART and nothing else. Every pillar telegraphed in
	# 0.50s and hit for 22 whether it was lightning or earth, while the boss's
	# own cast pillars, spawned correctly, varied 0.25s-0.68s and 19-28.
	#
	# pillar_scene is already the elemental variant (bossenemy hands us
	# Projectiles.variant_of(...) and those scenes author their own `element`),
	# so nothing needs stamping here — the profile only has to run last.
	pillar.damage = pillar_damage
	pillar.telegraph_seconds = pillar_telegraph

	# NO ACID FROM THE TRAIL. The stalker drops a pillar every half second for
	# seven seconds; if each one left a pool, a single stalker would lay a
	# permanent wall of poison across the arena behind it and the room would run
	# out of floor in one pass.
	#
	# GUARDED, because pillar_scene arrives from setup() and this script does not
	# own it. An assignment onto a property that is not there raises, and every
	# statement below it in the function silently never runs.
	if "leaves_puddle" in pillar:
		pillar.leaves_puddle = false

	# THE STALKER'S OWN SIZE PREFERENCE, which the element profile then scales.
	# Set here rather than after add_child so the two COMPOSE — a 0.8 stalker
	# pillar of ice ends up 0.8 x 1.25 — instead of this assignment wiping
	# whatever the profile just produced.
	if not is_equal_approx(pillar_radius, 20.0):
		var s: float = pillar_radius / 20.0
		pillar.scale = Vector2(s, s)

	container.add_child(pillar)
	pillar.global_position = global_position
	pillar.reset_physics_interpolation()
