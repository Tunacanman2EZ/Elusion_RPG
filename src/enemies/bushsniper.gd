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

# THE HELIX AND THE WAKE (0.24.0). In an area with a BulletZone - the Field.
# 0.22.0 replaced the arrow with a fan of three orbs. The owner, of that: "i
# want the orbs to spin in a circle around the arrows", then, of the helix
# that came of it, "if only the arrow hits its pointless howabout the vortex
# stays but it sprays bullet like a < if the arrow fired left" - and of every
# monster, "we are not taking away from my artists art but adding to it".
#
# So the ARROW flies again, the artist's own, slowed to HELIX_SPEED so what
# rides it can be seen; two orbs wind round its line HELIX_WIDTH px either
# side, crossing over it (the helix, BulletZone.fire_helix); and it sheds a
# pair of orbs every WAKE_INTERVAL back and out to both sides, drawing a
# chevron behind it (BulletWake). Everywhere else it is the arrow, as ever.
const HELIX_ORBS := 2
const HELIX_SPEED := 160.0     # px/s, the arrow and the orbs together
const HELIX_WIDTH := 12.0      # px either side of the arrow
const HELIX_RATE := 10.0       # radians a second: a full weave every 0.63 s
const HELIX_SHARE := 0.35      # of the arrow's damage, per orb
const WAKE_SHARE := 0.2        # of the arrow's damage, per wake orb


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
		fire_volley(zone, origin, aim)
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


func fire_volley(zone: BulletZone, origin: Vector2, aim: float, _volley: String = "",
		_reach: float = 0.0) -> void:
	"""The helix: the arrow, slowed, from `origin` toward `aim` (radians), and
	its orbs winding round it. Damage and element are this monster's own -
	which is what a follower relies on when it replays the leader's volley:
	the message says where and which way, never how hard. The archer has one
	volley, so the name and reach a message may carry are ignored
	(BulletZone's header has the contract)."""
	var arrow: Node = Projectiles.variant_of(ARROW_SCENE, current_element()).instantiate()
	arrow.set("speed", HELIX_SPEED)
	arrow.shoot_vector(Vector2.from_angle(aim))
	var arrow_damage: int = BulletZone.base_damage(self, ARROW_SCENE)
	BulletWake.on(arrow, zone, BulletZone.share_of(arrow_damage, WAKE_SHARE), current_element())
	spawn_projectile_node(arrow, origin, false)
	zone.fire_helix(origin, aim, HELIX_SPEED, HELIX_ORBS, HELIX_WIDTH, HELIX_RATE, orb_damage(),
		current_element())


func orb_damage() -> int:
	return BulletZone.share_of(BulletZone.base_damage(self, ARROW_SCENE), HELIX_SHARE)


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
