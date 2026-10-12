# bushsniper enemy — ranged archer that fires arrows at the player.
extends BaseEnemy
class_name BushSniper

# This enemy's reward profile — see BaseEnemy.enemy_data.
const ENEMY_DATA := preload("res://data/enemies/bushsniper.tres")


# =============================================================================
# CONSTANTS
# =============================================================================

const ARROW_SCENE := preload("res://scene/projectiles/arrow.tscn")
const ARROW_RELEASE_FRAME := 5

# THE FAN (0.22.0). In an area with a BulletZone - the Field - the archer looses
# FAN_ORBS orbs across FAN_SPREAD instead of one arrow. The owner: "lower dps on
# projectiles", so each orb is FAN_SHARE of what the arrow hit for, and the
# orbs are slow enough to read and step between where the arrow is a 400 px/s
# streak. A player who stands still takes the middle orb; one who reads the fan
# takes nothing. Everywhere else it is the arrow, exactly as before.
const FAN_ORBS := 3
const FAN_SPREAD := 0.5        # radians edge to edge, about 29 degrees
const FAN_SPEED := 150.0       # px/s
const FAN_SHARE := 0.6         # of the arrow's damage, per orb

# arrow.gd's own damage, read once from the scene, for a sniper whose .tres
# leaves projectile_damage at 0 (the plain one). Read, not copied, so the two
# cannot drift.
static var _arrow_damage: int = -1


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var sprite: AnimatedSprite2D = $animatedsprite2d
@onready var spawn_nodes: Dictionary = {
	"left":  $projectileleft,
	"right": $projectileright,
	"up":    $projectiletop,
	"down":  $projectilebottom,
}


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	if enemy_data == null:
		enemy_data = ENEMY_DATA

	# Combat tuning only — the reward profile lives in the .tres now.
	attack_cooldown = 2.0
	attack_range    = 200.0

	# THE KITE BAND. Inside 50 the archer backs off; BaseEnemy's flee hysteresis
	# then carries it out to 90 (flee_range * FLEE_RELEASE_FACTOR) before it
	# stops, turns and shoots again. Both numbers sit well inside attack_range,
	# so it is never retreating out of its own reach - it is making room, which
	# is what an archer is for.
	flee_range      = 50.0

	super._ready()

	if not sprite.frame_changed.is_connected(_on_frame_changed):
		sprite.frame_changed.connect(_on_frame_changed)


# =============================================================================
# SUBCLASS OVERRIDES
# =============================================================================

func get_move_speed() -> float:
	return 80.0


func get_flee_speed() -> float:
	# FASTER THAN THE PLAYER (base 90), and this is the whole reason the archer
	# never appeared to run away. It advances at 80, and it was retreating at 80
	# too - so a player simply walking toward it closed ten pixels every second
	# no matter what the archer did. It was fleeing the entire time and losing.
	#
	# Deliberately only a little faster: 105 opens a gap over a couple of
	# seconds rather than instantly, so the player can still corner it by
	# cutting it off rather than by out-running it. Kept under the bush mage's
	# 115 charge speed, so a mage still closes on an archer's position.
	return 105.0


func fire_projectile() -> void:
	# spawn an arrow at the directional spawn marker, aimed at the player's
	# position at the moment of release. parents into the y-sorted projectiles
	# container via the inherited helper so the arrow depth-sorts correctly.
	var spawn_node: Marker2D = spawn_nodes.get(attack_direction)
	if spawn_node == null or not is_instance_valid(player):
		return
	# IN THE BULLET-HELL ZONE, A FAN OF ORBS. The leader tells every other game
	# where it fired and which way (monstersync.gd, event "b"); each of them
	# fires its own copy of this monster's fan.
	var zone: BulletZone = BulletZone.find(self)
	if zone != null:
		var origin: Vector2 = spawn_node.global_position
		var aim: float = (target_point() - origin).angle()
		fire_fan(zone, origin, aim)
		if _net_sync != null and not net_mirror:
			_net_sync.leader_bullets(self, origin, aim)
		return
	# THE ELEMENT PICKS THE ARROW. An ice sniper fires icearrow.tscn, which is
	# this same scene with an authored material on it — so the shot is blue
	# because the file is blue, not because something built a Material for this
	# one arrow on its way out of the bow. The plain sniper is NONE and has no
	# variant, so it gets ARROW_SCENE back untouched.
	var arrow: Node = Projectiles.variant_of(ARROW_SCENE, current_element()).instantiate()
	# aim BEFORE spawning — shoot_vector just sets velocity + rotation, which
	# don't require the node to be in the tree yet.
	var to_player: Vector2 = target_point() - spawn_node.global_position
	arrow.shoot_vector(to_player)
	# parent into the y-sorted projectiles container at the marker position.
	spawn_projectile_node(arrow, spawn_node.global_position)


func fire_fan(zone: BulletZone, origin: Vector2, aim: float) -> void:
	"""The fan, from `origin` toward `aim` (radians). Damage and element are
	this monster's own - which is what a follower relies on when it replays the
	leader's volley: the message says where and which way, never how hard."""
	zone.fire_fan(origin, aim, FAN_ORBS, FAN_SPREAD, FAN_SPEED, orb_damage(), current_element())


func orb_damage() -> int:
	var arrow: int = enemy_data.projectile_damage if enemy_data != null else 0
	if arrow <= 0:
		if _arrow_damage < 0:
			var probe: Node = ARROW_SCENE.instantiate()
			_arrow_damage = int(probe.get("damage"))
			probe.free()
		arrow = _arrow_damage
	return maxi(1, roundi(arrow * FAN_SHARE))


# =============================================================================
# ANIMATION HOOKS
# =============================================================================

func _on_frame_changed() -> void:
	# A mirror's attack is a picture: the shot is the leader's (shared
	# monsters), and arrives from monstersync.gd.
	if net_mirror:
		return
	if not sprite.animation.begins_with("attack"):
		return
	if sprite.frame != ARROW_RELEASE_FRAME:
		return
	fire_projectile()
