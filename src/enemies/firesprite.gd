# firesprite enemy — ranged magic caster that fires fire orbs at the player.
extends BaseEnemy
class_name FireSprite

# This enemy's reward profile — see BaseEnemy.enemy_data.
const ENEMY_DATA := preload("res://data/enemies/firesprite.tres")


# =============================================================================
# CONSTANTS
# =============================================================================

const FIRE_ORB_SCENE := preload("res://scene/projectiles/fireprojectile.tscn")
const ORB_RELEASE_FRAME := 5

# THE PINCER (0.23.0). In an area with a BulletZone - the Field - the sprite
# spits four orbs that leave wide of the player on both sides and curve back
# to meet where the player stood when it fired (BulletZone.fire_pincer). Easy
# to see coming and lethal to stand in: step out of the meeting point. Since
# 0.24.0 its own fire orb flies too, straight down the middle, timed to arrive
# as the pincer closes - the artist's art, with the orbs added to it. How far
# that point is (`reach`) goes to the other games with the volley, held to
# PINCER_REACH_MIN..MAX on every one of them.
const PINCER_OFFSETS: Array[float] = [-0.9, -0.45, 0.45, 0.9]
const PINCER_SPEED := 150.0
const PINCER_SHARE := 0.5      # of the fire orb's damage, per orb
const PINCER_REACH_MIN := 60.0
const PINCER_REACH_MAX := 260.0
const PINCER_REACH_DEFAULT := 160.0


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
	attack_range    = 240.0
	flee_range      = 50.0

	super._ready()

	if not sprite.frame_changed.is_connected(_on_frame_changed):
		sprite.frame_changed.connect(_on_frame_changed)


# =============================================================================
# SUBCLASS OVERRIDES
# =============================================================================

func get_move_speed() -> float:
	return 85.0


func fire_projectile() -> void:
	# spawn a fire orb at the directional spawn marker, aimed at the player's
	# position at release. parents into the y-sorted projectiles container.
	var spawn_node: Marker2D = spawn_nodes.get(attack_direction)
	if spawn_node == null or not is_instance_valid(player):
		return
	var zone: BulletZone = BulletZone.find(self)
	if zone != null:
		var origin: Vector2 = spawn_node.global_position
		var to_target: Vector2 = target_point() - origin
		fire_volley(zone, origin, to_target.angle(), "", to_target.length())
		if _net_sync != null and not net_mirror:
			_net_sync.leader_bullets(self, origin, to_target.angle(), "",
				clampf(to_target.length(), PINCER_REACH_MIN, PINCER_REACH_MAX))
		return
	# The element picks the orb — see bushsniper.gd for the full note. The fire
	# sprite itself is FIRE and has no variant, so it fires the artist's own art.
	var orb: Node = Projectiles.variant_of(FIRE_ORB_SCENE, current_element()).instantiate()
	# aim before spawning
	if orb.has_method("shoot_vector"):
		var to_player: Vector2 = target_point() - spawn_node.global_position
		orb.shoot_vector(to_player)
	elif orb.has_method("shoot"):
		orb.shoot(attack_direction)
	spawn_projectile_node(orb, spawn_node.global_position)


func fire_volley(zone: BulletZone, origin: Vector2, aim: float, _volley: String = "",
		reach: float = 0.0) -> void:
	"""The pincer, closing `reach` px along `aim` from `origin`. This sprite's
	own damage and element (BulletZone's header has the contract)."""
	var meet: float = PINCER_REACH_DEFAULT if reach <= 0.0 else clampf(reach, PINCER_REACH_MIN, PINCER_REACH_MAX)
	var damage: int = BulletZone.share_of(BulletZone.base_damage(self, FIRE_ORB_SCENE), PINCER_SHARE)
	zone.fire_pincer(origin, aim, meet, PINCER_OFFSETS, PINCER_SPEED, damage, current_element())
	# THE ARTIST'S FIRE ORB TOO (0.24.0), straight down the middle and timed
	# to arrive as the pincer closes round it.
	var orb: Node = Projectiles.variant_of(FIRE_ORB_SCENE, current_element()).instantiate()
	orb.set("speed", meet / BulletZone.pincer_time(meet, PINCER_OFFSETS, PINCER_SPEED))
	orb.shoot_vector(Vector2.from_angle(aim))
	spawn_projectile_node(orb, origin, false)


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
	if sprite.frame != ORB_RELEASE_FRAME:
		return
	fire_projectile()
