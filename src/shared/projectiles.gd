# projectiles.gd — which scene an elemental creature actually fires.
#
# THE SAME MOVE THE PUDDLES MADE, one layer up. Every enemy projectile used to
# be one scene with a ShaderMaterial built onto it at spawn, in
# BaseEnemy._recolour_projectile(). That worked, and it cost a Material per
# BULLET: a Resource allocated, filled and thrown away for every arrow a sniper
# looses and every one of the sixty-five spikes a boss cast erupts. For a game
# meant to end up throwing bullet-hell volumes around, the allocation is in
# exactly the wrong place.
#
# A scene per (family, element) moves it to load time. The material is authored
# once in the file and SHARED by every instance of that scene, the colour is
# something you can see in the editor, and an ice arrow that should fly slower
# than a steel one is a number in icearrow.tscn rather than a branch in code.
#
# WHY THIS IS ITS OWN FILE: puddles.gd carries the long version. Briefly, a
# script cannot preload a scene it is attached to, and the table has to live
# somewhere outside that cycle. Nothing has this script attached.
#
# WHY PRELOAD AND NOT load(): all forty-eight are resident from startup, which
# costs a SpriteFrames and a handful of AtlasTextures each - the textures
# themselves are shared with the base scene, so the real figure is small. The
# alternative is a load() the first time an ice sniper fires, which is a disk
# hit in the middle of a fight. A frame hitch is worse than the memory.
class_name Projectiles
extends RefCounted


# base scene path -> { Element.Type: the scene to fire instead }
#
# KEYED ON THE BASE SCENE, NOT ON A FAMILY NAME, and that is what makes
# variant_of() safe to call everywhere. bossenemy.gd's eruption_scene and
# gate_scene are @export: point either at some custom scene and it simply is
# not in this table, so it comes back untouched rather than being silently
# replaced by a boss spike.
const BY_BASE := {
	# the bush sniper's shot. The original is NONE — steel, and the only family whose original has no element.
	"res://scene/projectiles/arrow.tscn": {
		Element.Type.DARK: preload("res://scene/projectiles/darkarrow.tscn"),
		Element.Type.EARTH: preload("res://scene/projectiles/eartharrow.tscn"),
		Element.Type.ICE: preload("res://scene/projectiles/icearrow.tscn"),
		Element.Type.LIGHT: preload("res://scene/projectiles/lightarrow.tscn"),
		Element.Type.WATER: preload("res://scene/projectiles/waterarrow.tscn"),
		Element.Type.WIND: preload("res://scene/projectiles/windarrow.tscn"),
	},
	# the small slime's shot. The original is POISON.
	"res://scene/projectiles/poisonarrow.tscn": {
		Element.Type.DARK: preload("res://scene/projectiles/darkpoisonarrow.tscn"),
		Element.Type.EARTH: preload("res://scene/projectiles/earthpoisonarrow.tscn"),
		Element.Type.ICE: preload("res://scene/projectiles/icepoisonarrow.tscn"),
		Element.Type.LIGHT: preload("res://scene/projectiles/lightpoisonarrow.tscn"),
		Element.Type.WATER: preload("res://scene/projectiles/waterpoisonarrow.tscn"),
		Element.Type.WIND: preload("res://scene/projectiles/windpoisonarrow.tscn"),
	},
	# the large slime's shot. The original is POISON.
	"res://scene/projectiles/poisonball.tscn": {
		Element.Type.DARK: preload("res://scene/projectiles/darkpoisonball.tscn"),
		Element.Type.EARTH: preload("res://scene/projectiles/earthpoisonball.tscn"),
		Element.Type.ICE: preload("res://scene/projectiles/icepoisonball.tscn"),
		Element.Type.LIGHT: preload("res://scene/projectiles/lightpoisonball.tscn"),
		Element.Type.WATER: preload("res://scene/projectiles/waterpoisonball.tscn"),
		Element.Type.WIND: preload("res://scene/projectiles/windpoisonball.tscn"),
	},
	# the fire sprite's shot. The original is FIRE.
	"res://scene/projectiles/fireprojectile.tscn": {
		Element.Type.DARK: preload("res://scene/projectiles/darkfireprojectile.tscn"),
		Element.Type.EARTH: preload("res://scene/projectiles/earthfireprojectile.tscn"),
		Element.Type.ICE: preload("res://scene/projectiles/icefireprojectile.tscn"),
		Element.Type.LIGHT: preload("res://scene/projectiles/lightfireprojectile.tscn"),
		Element.Type.WATER: preload("res://scene/projectiles/waterfireprojectile.tscn"),
		Element.Type.WIND: preload("res://scene/projectiles/windfireprojectile.tscn"),
	},
	# the electric sprite's shot. The original is LIGHTNING.
	"res://scene/projectiles/magicprojectile.tscn": {
		Element.Type.DARK: preload("res://scene/projectiles/darkmagicprojectile.tscn"),
		Element.Type.EARTH: preload("res://scene/projectiles/earthmagicprojectile.tscn"),
		Element.Type.ICE: preload("res://scene/projectiles/icemagicprojectile.tscn"),
		Element.Type.LIGHT: preload("res://scene/projectiles/lightmagicprojectile.tscn"),
		Element.Type.WATER: preload("res://scene/projectiles/watermagicprojectile.tscn"),
		Element.Type.WIND: preload("res://scene/projectiles/windmagicprojectile.tscn"),
	},
	# the bush mage's shot. The original is EARTH.
	"res://scene/projectiles/vine.tscn": {
		Element.Type.DARK: preload("res://scene/projectiles/darkvine.tscn"),
		Element.Type.FIRE: preload("res://scene/projectiles/firevine.tscn"),
		Element.Type.ICE: preload("res://scene/projectiles/icevine.tscn"),
		Element.Type.LIGHT: preload("res://scene/projectiles/lightvine.tscn"),
		Element.Type.WATER: preload("res://scene/projectiles/watervine.tscn"),
		Element.Type.WIND: preload("res://scene/projectiles/windvine.tscn"),
	},
	# the boss's pillar shot. The original is DARK.
	"res://scene/projectiles/bossprojectile.tscn": {
		Element.Type.EARTH: preload("res://scene/projectiles/earthbossprojectile.tscn"),
		Element.Type.FIRE: preload("res://scene/projectiles/firebossprojectile.tscn"),
		Element.Type.ICE: preload("res://scene/projectiles/icebossprojectile.tscn"),
		Element.Type.LIGHT: preload("res://scene/projectiles/lightbossprojectile.tscn"),
		Element.Type.WATER: preload("res://scene/projectiles/waterbossprojectile.tscn"),
		Element.Type.WIND: preload("res://scene/projectiles/windbossprojectile.tscn"),
	},
	# the boss's gate spike shot. The original is DARK.
	"res://scene/projectiles/secondbossprojectile.tscn": {
		Element.Type.EARTH: preload("res://scene/projectiles/earthsecondbossprojectile.tscn"),
		Element.Type.FIRE: preload("res://scene/projectiles/firesecondbossprojectile.tscn"),
		Element.Type.ICE: preload("res://scene/projectiles/icesecondbossprojectile.tscn"),
		Element.Type.LIGHT: preload("res://scene/projectiles/lightsecondbossprojectile.tscn"),
		Element.Type.WATER: preload("res://scene/projectiles/watersecondbossprojectile.tscn"),
		Element.Type.WIND: preload("res://scene/projectiles/windsecondbossprojectile.tscn"),
	},
}


static func variant_of(base: PackedScene, element: int) -> PackedScene:
	# THE BASE IS THE FALLBACK, AND IT IS THE COMMON CASE. Each family's
	# original element has no variant scene - the fire sprite IS fire, the
	# slime IS poison - so firing one of those lands here and gets the art the
	# artist drew, with no shader over it at all.
	#
	# An element with no scene of its own lands here too: a poison sniper, if
	# anyone ever writes one, fires a plain steel arrow rather than nothing,
	# and BaseEnemy._recolour_projectile() still rotates it at runtime because
	# that base scene carries no authored material. Missing a file degrades to
	# the old behaviour instead of to a crash.
	if base == null:
		return null
	var family: Dictionary = BY_BASE.get(base.resource_path, {})
	return family.get(element, base)
