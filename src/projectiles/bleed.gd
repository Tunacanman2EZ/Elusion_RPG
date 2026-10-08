# bleed.gd - the wound a Double Axe cut leaves (0.14.0).
#
# The owner: "we need to add a effect to double axe also to give it that feel",
# after the Meteorite's burning crater and Dynamite's smoulder. Every cut the
# axe makes - thrown out, spinning, called home - opens a wound on what it
# cut. For BLEED_SECONDS after the LAST cut the enemy bleeds: red drops fall
# from it, and every BLEED_EVERY seconds it takes BLEED_SHARE of a swing.
# Four bites of a quarter: one more swing, spread over two seconds, for
# anything the axe has touched.
#
# ONE WOUND PER ENEMY. The spinning axe cuts four to eight times a second, so
# a wound per cut would bleed an enemy four to eight times over. A fresh cut
# keeps the wound it already has open (to BLEED_SECONDS from now, at the new
# cut's size) rather than opening a second, and the wound bites on its own
# clock, from the first cut. So the most any one enemy bleeds is BLEED_SHARE
# of a swing every BLEED_EVERY seconds: the figure the server's books allow
# for. The exporter writes BLEED_SHARE and BLEED_EVERY into gamedata.json as
# the warrior's axe_bleed_share and axe_bleed_every, and
# gamedata.combat_bounds() adds them to a warrior holding the Double Axe.
#
# A CHILD OF THE ENEMY, so it goes where the enemy goes and is freed with it.
# Its hit is the enemy's own take_damage(), like a crater's: an enemy already
# dying takes nothing (baseenemy.gd), and a shared monster's mirror sends it
# to the game that runs it. advance() is the timeline; _physics_process calls
# it, and a test calls it directly.
class_name Bleed
extends Node2D


const BLEED_SECONDS := 2.0
const BLEED_EVERY := 0.5
const BLEED_SHARE := 0.25

# Where the enemy keeps its wound's instance id.
const META := &"bleed_wound"

# The drops start from about where a body is, above the enemy's feet.
const DROPS_AT := Vector2(0, -8)

var bite: int = 0
var caster: Node = null
var bites_dealt: int = 0

var _age: float = 0.0
var _ends: float = 0.0
var _bites: int = 0
var _out: bool = false
var _drops: CPUParticles2D = null


static func open(enemy: Node, from_swing: int, by: Node) -> Bleed:
	"""Opens a wound on enemy for a swing of from_swing, or keeps the one it
	has open. Returns the wound, or null for something that cannot bleed."""
	if enemy == null or not is_instance_valid(enemy) or not (enemy is Node2D) or not enemy.is_inside_tree():
		return null
	var size: int = maxi(1, roundi(float(from_swing) * BLEED_SHARE))
	var had: Object = instance_from_id(int(enemy.get_meta(META, 0))) if enemy.has_meta(META) else null
	if had != null and is_instance_valid(had) and had is Bleed and (had as Bleed).bleeding() \
			and (had as Bleed).get_parent() == enemy:
		var wound: Bleed = had
		wound.bite = size
		wound.caster = by
		wound._ends = wound._age + BLEED_SECONDS
		return wound
	var fresh := Bleed.new()
	fresh.name = "bleed"
	fresh.bite = size
	fresh.caster = by
	fresh._ends = BLEED_SECONDS
	enemy.add_child(fresh)
	enemy.set_meta(META, fresh.get_instance_id())
	fresh._build()
	return fresh


func _build() -> void:
	position = DROPS_AT
	# Over the enemy it is falling from.
	z_index = 1
	_drops = CPUParticles2D.new()
	_drops.name = "drops"
	_drops.amount = 10
	_drops.lifetime = 0.6
	_drops.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_drops.emission_sphere_radius = 4.0
	_drops.direction = Vector2(0, 1)
	_drops.spread = 50.0
	_drops.gravity = Vector2(0, 160)
	_drops.initial_velocity_min = 8.0
	_drops.initial_velocity_max = 22.0
	_drops.scale_amount_min = 1.5
	_drops.scale_amount_max = 2.5
	# Squares, whole pixels, like Blast's sparks.
	_drops.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	ramp.colors = PackedColorArray([Color(0.85, 0.08, 0.1), Color(0.6, 0.02, 0.05), Color(0.35, 0.0, 0.02, 0.0)])
	_drops.color_ramp = ramp
	# Left where they fall as the enemy walks on.
	_drops.local_coords = false
	add_child(_drops)


func _physics_process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if _out:
		return
	var host: Node = get_parent()
	if host == null or host.get(&"_dying") == true or host.get(&"_death_resolved") == true:
		_stop()
		return
	_age += delta
	# By the bite's own time, as a crater does (burningcrater.gd): a long step
	# still bites every time it should have, and never past the end.
	while float(_bites + 1) * BLEED_EVERY <= minf(_age, _ends) + 0.0001:
		_bites += 1
		if host.has_method("take_damage"):
			host.take_damage(bite)
			bites_dealt += 1
	if _age >= _ends:
		_stop()


func bleeding() -> bool:
	return not _out


func _stop() -> void:
	_out = true
	var host: Node = get_parent()
	if host != null and int(host.get_meta(META, 0)) == get_instance_id():
		host.remove_meta(META)
	if _drops != null:
		_drops.emitting = false
	# The last drops finish falling first. Connected to this node's own method
	# (see burningcrater.gd's _go_out()).
	if is_inside_tree():
		get_tree().create_timer(0.7).timeout.connect(queue_free)
	else:
		queue_free()
