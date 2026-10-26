# hitsource.gd - WHAT HIT ME (0.85.0): the enemy meter's phase 2.
#
# Every hit on this game's player is said to come from "<monster>:<attack>" -
# "icesprite:frost", "lightbushsniper:arrow", "boss:prism", "spikedoor:spikes"
# - so the fight log can say which monster and which of its attacks hurt
# most. The monster is its profile's file name (data/enemies/<name>.tres, the
# id the server's catalogue names it by); the attack is the volley's kind, the
# shot's scene, "swing" or "touch".
#
# HOW A HIT CARRIES IT, without a new argument on take_damage() and its forty
# callers:
#   - a SHOT (arrow, orb, vine, spike) carries it as the meta HIT_META, set
#     where it is made (BaseEnemy.spawn_projectile_node() and the few that are
#     placed by hand), and says blame_node(self) the line before it calls
#     take_damage();
#   - an ORB in a bullet zone is stamped when it is spawned (BulletField reads
#     `stamp`, which a monster's fire_volley() sets) and BulletZone blames its
#     stamp as it lands. An orb fired on a later beat keeps the stamp of the
#     volley it belongs to (later());
#   - a swing or a touch blames its monster directly.
# Player.take_damage() takes the blame (take()) whatever happens to the hit,
# so a stale one never lands on the next. Nothing blamed is "unknown:hit".
extends RefCounted

const HIT_META := &"hit_source"
const UNKNOWN := "unknown:hit"
const PART_MOST := 24
# Element words a shot's scene name may start with ("icearrow"), taken off so
# every archer's arrow is an "arrow".
const ELEMENT_WORDS := ["light", "wind", "water", "ice", "earth", "fire", "dark", "poison", "electric"]

static var names: PackedStringArray = PackedStringArray([UNKNOWN])
static var _ids: Dictionary = {UNKNOWN: 0}
static var stamp: int = 0
static var pending: String = ""


static func id_of(source: String) -> int:
	if not _ids.has(source):
		_ids[source] = names.size()
		names.append(source)
	return int(_ids[source])


static func name_of(id: int) -> String:
	return names[id] if id >= 0 and id < names.size() else UNKNOWN


static func clean(text: String, fallback: String) -> String:
	"""Lower case, letters, digits and _ only, at most PART_MOST - the shape
	the server takes (presence.py SOURCE_PATTERN)."""
	var out: String = ""
	for c in text.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_":
			out += c
	out = out.left(PART_MOST)
	return out if out != "" else fallback


static func monster_of(node: Node) -> String:
	"""The monster's name as the catalogue has it: its profile's file name."""
	if node == null or not is_instance_valid(node):
		return "unknown"
	var data: Variant = node.get("enemy_data")
	if data is Resource and (data as Resource).resource_path != "":
		return clean((data as Resource).resource_path.get_file().get_basename(), "unknown")
	return clean(String(node.name), "unknown")


static func of(node: Node, kind: String) -> String:
	return "%s:%s" % [monster_of(node), clean(kind, "hit")]


static func shot_kind(shot: Node) -> String:
	"""A shot's attack name: its scene's file name, the element word off the
	front ("icearrow" -> "arrow", "fireprojectile" -> "projectile")."""
	var base: String = shot.scene_file_path.get_file().get_basename() if shot != null else ""
	for word in ELEMENT_WORDS:
		if base.begins_with(word) and base.length() > String(word).length():
			base = base.substr(String(word).length())
			break
	return clean(base, "shot")


static func tag(shot: Node, caster: Node, kind: String = "") -> void:
	"""Marks `shot` as `caster`'s, its attack `kind` or its own scene's name."""
	if shot != null:
		shot.set_meta(HIT_META, of(caster, kind if kind != "" else shot_kind(shot)))


static func stamp_for(caster: Node, kind: String) -> void:
	"""The orbs spawned from now are `caster`'s `kind`."""
	stamp = id_of(of(caster, kind))


static func later(shot: Callable) -> Callable:
	"""`shot`, to be called on a later beat, with the stamp it has now."""
	var mine: int = stamp
	return func() -> void:
		var was: int = _swap(mine)
		shot.call()
		_swap(was)


static func _swap(to: int) -> int:
	var was: int = stamp
	stamp = to
	return was


static func blame(source: String) -> void:
	pending = source


static func blame_node(node: Node, fallback_kind: String = "hit") -> void:
	"""The next hit is `node`'s: its tag, or an unknown monster's
	`fallback_kind`."""
	if node != null and node.has_meta(HIT_META):
		pending = str(node.get_meta(HIT_META))
	else:
		pending = "unknown:" + clean(fallback_kind, "hit")


static func take() -> String:
	"""(Player.take_damage().) The blame for this hit, cleared."""
	var source: String = pending if pending != "" else UNKNOWN
	pending = ""
	return source
