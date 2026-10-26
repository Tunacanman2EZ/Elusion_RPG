# elementkit.gd - THE ELEMENT KITS FOR MONSTERS (0.84.0): in the Field's
# bullet zone, a monster's orbs move like its element.
#
# The 42 element variants only changed colour and health: a water archer and
# an ice archer fired the same helix. Now the orbs a family fires into a
# BulletZone are its ELEMENT's, small versions of the bosses' volleys
# (bossenemy.gd, THE KITS):
#   light   prism    a ring of PRISM_ORBS, then a second turned half a step
#   wind    gale     two fans swept one way, GALE_GAP apart
#   water   tide     a slow wide wall with a door in it - never on the shot
#   ice     frost    a fan that settles where you stood, as mines
#   earth   boulder  the stalagmite lobbed onto your spot, bursting into a crater
#   fire    pincer   four orbs curving shut on your spot together
#   dark    one of the six, picked per shot (the band 5 finale)
#
# WHAT STAYS EACH FAMILY'S: how it moves and fights (archers keep range,
# slimes split, mages cast vines), and the artist's own shot - it still flies
# (the owner, 0.24.0: "we are not taking away from my artists art but adding
# to it"), now at the speed its kit says; a boulder carries it as the lob.
# The orbs keep the family's own share of that shot, so a band's damage is
# what it was.
#
# WHAT DOES NOT CHANGE: an element with no kit (lightning, poison, physical)
# fires its family's own volley; a family whose own volley IS its element's
# (the fire sprite's pincer) keeps it; the small slime keeps its twin, the
# split ring stays; and anywhere with no bullet zone (the Big Field, the
# crypt) fires the ordinary projectile, as the owner chose for the Big Field.
#
# ON THE WIRE: the volley name "kit:<n>", n a number the leader rolls, which
# picks a dark monster's kind, the tide's door and the gale's swing. Every
# game fires the same pattern from it (monstersync.gd "b"); damage and
# element are each game's own, as for every volley. A game from before 0.84.0
# fires its family volley for it (or, a slime, nothing).
extends RefCounted

const MARK := "kit:"
const ROLL_MOST := 1000

const KINDS := {
	Element.Type.LIGHT: &"prism",
	Element.Type.WIND: &"gale",
	Element.Type.WATER: &"tide",
	Element.Type.ICE: &"frost",
	Element.Type.EARTH: &"boulder",
	Element.Type.FIRE: &"pincer",
	Element.Type.DARK: &"dark",
}
const DARK_MIX: Array[StringName] = [&"prism", &"gale", &"tide", &"frost", &"boulder", &"pincer"]

const PRISM_ORBS := 7
const PRISM_SPEED := 90.0
const PRISM_AGAIN := 0.25
const GALE_FANS := 2
const GALE_ORBS := 4
const GALE_SPREAD := 0.7
const GALE_SPEED := 150.0
const GALE_GAP := 0.22
const GALE_SWEEP := 0.18
const TIDE_ORBS := 13
const TIDE_SPREAD := 2.0
const TIDE_SPEED := 70.0
const TIDE_DOOR := 3
const FROST_ORBS := 6
const FROST_SPREAD := 1.2
const FROST_SPEED := 150.0
const FROST_NEAREST := 40.0
const FROST_FURTHEST := 160.0
const BOULDER_FLIGHT := 0.9
const BOULDER_ROCKS := 6
const BOULDER_ROCK_SPEED := 110.0
const BOULDER_CRATER := 30.0
const BOULDER_REACH_MIN := 40.0
const BOULDER_REACH_MAX := 220.0
const BOULDER_ART_SCALE := 0.4
const PINCER_OFFSETS: Array[float] = [-0.9, -0.45, 0.45, 0.9]
const PINCER_SPEED := 150.0
const PINCER_REACH_MIN := 60.0
const PINCER_REACH_MAX := 260.0
const REACH_DEFAULT := 160.0

# Loaded when a boulder first flies, not preloaded: every monster script
# reaches this one through baseenemy.gd.
const PILLAR_PATH := "res://scene/projectiles/bossprojectile.tscn"


static func kind_for(element: int) -> StringName:
	"""The element's kit, &"dark" for the mix, or &"" for none."""
	return KINDS.get(element, &"")


static func kind_of(element: int, roll: int) -> StringName:
	"""The kind a shot fires: a dark monster's picked by `roll`."""
	var kind: StringName = kind_for(element)
	if kind == &"dark":
		return DARK_MIX[absi(roll) % DARK_MIX.size()]
	return kind


static func volley_for(element: int, own: StringName = &"") -> String:
	"""The volley name a leader sends for one shot, or "" when this element has
	no kit or its kit is the family's `own` volley."""
	var kind: StringName = kind_for(element)
	if kind == &"" or kind == own:
		return ""
	return MARK + str(randi() % ROLL_MOST)


static func is_kit(volley: String) -> bool:
	return volley.begins_with(MARK)


static func roll_of(volley: String) -> int:
	var tail: String = volley.substr(MARK.length())
	return absi(int(tail)) % ROLL_MOST if tail.is_valid_int() else 0


static func fire(zone: BulletZone, enemy: Node, origin: Vector2, aim: float, volley: String,
		reach: float, orb: int, impact: int, lob_art: Node2D = null) -> float:
	"""The kit's orbs for one shot of `enemy` into `zone`: each `orb`, a
	boulder's landing `impact`. Returns the speed the family's own shot flies
	at down `aim`, or 0 when it is not to fly (a boulder carries it). A
	`lob_art` the family gives is the boulder's; otherwise its element's
	stalagmite. A name that is not a kit's fires nothing and returns 0."""
	if zone == null or not is_kit(volley):
		if lob_art != null:
			lob_art.free()
		return 0.0
	var element: int = int(enemy.call("current_element"))
	var roll: int = roll_of(volley)
	var kind: StringName = kind_of(element, roll)
	var far: float = REACH_DEFAULT if reach <= 0.0 else reach
	if kind != &"boulder" and lob_art != null:
		lob_art.free()
	match kind:
		&"prism":
			zone.fire_ring(origin, aim, PRISM_ORBS, PRISM_SPEED, orb, element)
			_later(enemy, PRISM_AGAIN, zone.fire_ring.bind(origin, aim + PI / PRISM_ORBS, PRISM_ORBS,
				PRISM_SPEED, orb, element))
			return PRISM_SPEED
		&"gale":
			var swing: float = 1.0 if roll % 2 == 0 else -1.0
			for f in GALE_FANS:
				var turn: float = aim + (float(f) - float(GALE_FANS - 1) * 0.5) * GALE_SWEEP * swing
				if f == 0:
					zone.fire_fan(origin, turn, GALE_ORBS, GALE_SPREAD, GALE_SPEED, orb, element)
				else:
					_later(enemy, GALE_GAP * f, zone.fire_fan.bind(origin, turn, GALE_ORBS, GALE_SPREAD,
						GALE_SPEED, orb, element))
			return GALE_SPEED
		&"tide":
			zone.fire_fan(origin, aim, TIDE_ORBS, TIDE_SPREAD, TIDE_SPEED, orb, element, false, 0.0,
				tide_door(roll), TIDE_DOOR)
			return TIDE_SPEED
		&"frost":
			zone.fire_fan(origin, aim, FROST_ORBS, FROST_SPREAD, FROST_SPEED, orb, element, false,
				clampf(far, FROST_NEAREST, FROST_FURTHEST))
			return FROST_SPEED
		&"boulder":
			var art: Node2D = lob_art if lob_art != null else boulder_art(element)
			zone.fire_mortar(origin, aim, clampf(far, BOULDER_REACH_MIN, BOULDER_REACH_MAX), BOULDER_FLIGHT,
				art, impact, BOULDER_ROCKS, BOULDER_ROCK_SPEED, BOULDER_CRATER, orb, element)
			return 0.0
		&"pincer":
			var meet: float = clampf(far, PINCER_REACH_MIN, PINCER_REACH_MAX)
			zone.fire_pincer(origin, aim, meet, PINCER_OFFSETS, PINCER_SPEED, orb, element)
			return meet / BulletZone.pincer_time(meet, PINCER_OFFSETS, PINCER_SPEED)
	return 0.0


static func tide_door(roll: int) -> int:
	"""Where the tide's door starts: never on the middle orb, which the
	family's own shot flies down, so the way through is always beside it - one
	to three orbs to the left or the right."""
	var middle: int = TIDE_ORBS >> 1
	var step: int = 1 + (roll >> 1) % 3
	return middle + step if roll % 2 == 0 else middle - step - TIDE_DOOR + 1


static func boulder_art(element: int) -> Node2D:
	"""The element's stalagmite, as the bosses throw (bossenemy.gd _lob_art()),
	smaller: the owner's art, not new art."""
	var holder := Node2D.new()
	var pillar: Node = Projectiles.variant_of(load(PILLAR_PATH) as PackedScene, element).instantiate()
	var art: AnimatedSprite2D = pillar.get_node_or_null(^"animatedsprite2d") as AnimatedSprite2D
	if art != null:
		art.owner = null
		pillar.remove_child(art)
		art.stop()
		if art.sprite_frames != null and art.sprite_frames.has_animation(&"projectile"):
			art.animation = &"projectile"
			art.frame = mini(1, art.sprite_frames.get_frame_count(&"projectile") - 1)
		art.scale = Vector2.ONE * BOULDER_ART_SCALE
		holder.add_child(art)
	pillar.free()
	return holder


static func _later(enemy: Node, seconds: float, shot: Callable) -> void:
	"""`shot` `seconds` from now, on a tween of the monster's own - so a monster
	that is freed takes the rest of its volley with it."""
	if not enemy.is_inside_tree():
		return
	var tween: Tween = enemy.create_tween()
	tween.tween_interval(seconds)
	tween.tween_callback(shot)
