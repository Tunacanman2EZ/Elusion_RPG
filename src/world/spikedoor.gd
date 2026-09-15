# spikedoor.gd — spikes that rise from the floor to block a way through.
#
# A door, not a trap. Raised spikes stop you walking past; they do not hurt you
# unless `contact_damage` is set above zero. That default is deliberate — you
# described these as doors, and a door that quietly chips your health is a
# different design decision than a door.
#
# Driven by lever.gd through set_raised(bool), which is the whole interface. It
# does not know what threw it.
#
#
# LAYER 1, WHICH IS NAMED "ground" AND IS NOT ABOUT THE GROUND.
#
# Layer 1 is what every TileMap in this project puts its collision on — shop
# walls, building exteriors, the crypt. Layer 2 is named "walls" and is used
# only by Area2D prop triggers. So geometry that should behave like a wall goes
# on layer 1, and that is what makes raised spikes REAL cover as of today's
# collision work:
#
#   - the player masks it (19 = ground + walls + interactors), so it blocks
#   - enemy projectiles now mask it (5 = ground + player), so shots die on it
#   - baseenemy._has_line_of_sight() raycasts mask 1, so enemies cannot see
#     through it and will hold fire and path around instead
#
# All three fall out of one layer choice. Put these on layer 2 instead and the
# spikes would block movement while arrows sailed straight through them.
extends StaticBody2D


# =============================================================================
# SIGNALS
# =============================================================================

signal raised_changed(is_raised: bool)


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# Whether the spikes are up when the scene loads. A lever pointed at this will
# overwrite it on the first frame, so this only decides what an UNWIRED door
# does — set it to match the lever's starts_on so the room looks right in the
# editor viewport too.
@export var starts_raised: bool = true

# Seconds the rise or fall takes. The collision follows the animation rather
# than snapping: see _finish_transition().
@export var travel_seconds: float = 0.35

# Above zero turns this from a door into a trap. Left at 0 the spikes are
# purely structural.
@export var contact_damage: int = 0


# =============================================================================
# NODES
# =============================================================================

@onready var anim: AnimatedSprite2D = get_node_or_null("animatedsprite2d")
@onready var blocker: CollisionShape2D = get_node_or_null("collisionshape2d")
@onready var hurtzone: Area2D = get_node_or_null("hurtzone")


# =============================================================================
# STATE
# =============================================================================

var _is_raised: bool = true
var _moving: bool = false


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	add_to_group(&"spikedoors")

	# Snapped, not animated. On load the door simply IS open or closed; playing
	# a rise the player never triggered would look like the room reacting to
	# them arriving.
	_is_raised = starts_raised
	_apply_blocking(_is_raised)
	if anim != null:
		anim.play(&"raised" if _is_raised else &"lowered")

	if hurtzone != null:
		hurtzone.monitoring = _is_raised and contact_damage > 0
		if not hurtzone.body_entered.is_connected(_on_hurtzone_body_entered):
			hurtzone.body_entered.connect(_on_hurtzone_body_entered)


# =============================================================================
# THE INTERFACE LEVERS USE
# =============================================================================

func set_raised(raised: bool) -> void:
	if raised == _is_raised and not _moving:
		return

	_is_raised = raised
	_moving = true

	# LOWERING UNBLOCKS IMMEDIATELY, RAISING BLOCKS AT THE END.
	#
	# Both halves are the forgiving choice. A player who threw the lever to open
	# a way should be able to walk through as the spikes drop rather than
	# bouncing off tips that are visually already gone. And spikes closing
	# behind them should not teleport-block a body that is mid-stride over the
	# tile - if they beat the animation, they got through.
	if not raised:
		_apply_blocking(false)

	if hurtzone != null:
		hurtzone.monitoring = false

	if anim != null:
		anim.play(&"raising" if raised else &"lowering")

	Audio.play_at("spikes", global_position)

	await get_tree().create_timer(travel_seconds).timeout

	if not is_instance_valid(self):
		return
	_finish_transition()


func is_raised() -> bool:
	return _is_raised


func _finish_transition() -> void:
	_moving = false

	if _is_raised:
		_apply_blocking(true)

	if anim != null:
		anim.play(&"raised" if _is_raised else &"lowered")

	if hurtzone != null:
		hurtzone.monitoring = _is_raised and contact_damage > 0

	raised_changed.emit(_is_raised)


func _apply_blocking(blocking: bool) -> void:
	if blocker == null:
		push_warning("SpikeDoor (%s): no collisionshape2d — these spikes block nothing" % name)
		return

	# set_deferred, not a direct write. Changing a collision shape from inside a
	# physics callback is a "Can't change this state while flushing queries"
	# error, and set_raised() can be reached from one via a lever a body pushed.
	blocker.set_deferred("disabled", not blocking)


# =============================================================================
# CONTACT DAMAGE (off unless contact_damage is set)
# =============================================================================

func _on_hurtzone_body_entered(body: Node) -> void:
	if contact_damage <= 0 or not _is_raised:
		return
	if body == null or not body.has_method("take_damage"):
		return
	if not body.is_in_group("player"):
		return
	body.take_damage(contact_damage, &"physical")
