# targets.gd - who a monster may go after: you, and anybody else sharing it.
#
# Until 0.7.0 every monster chased "the player" - the one node in the "player"
# group, which is always the local player. With shared monsters (monstersync.gd)
# the game that runs an area's monsters has to let them chase everybody in it:
# its own player, and the RemotePlayer pictures of the others whose games share
# monsters. Everything that asks "who is near this monster" asks here, so the
# answer is the same for the AI, the sleeper and the respawner.
#
# NOT THE "player" GROUP, ON PURPOSE. Twenty-odd things in the game ask that
# group for "the player" and mean YOU - the HUD, the bank, the shop, the camera.
# Putting other people in it would hand them your inventory screen.
#
# Preloaded where used (const Targets := preload(...)) rather than a
# class_name, like marks.gd, so a fresh checkout needs no editor rescan.
extends RefCounted


static func touching(area: Area2D, group: StringName = &"enemies") -> Array:
	"""What a player's blow, blast or ring touches: the bodies AND the
	hurtboxes' owners in `group`, one entry each (0.93.1). A monster has both
	- read alone, a blast would hit it twice - and the Endless's swarm has
	only hurtboxes (swarmproxy.gd), so a weapon that read bodies alone did
	nothing to it: the owner, "tanks aura is doing no damage to these mobs".
	spinningaxe.gd and the warrior's swing read both their own way."""
	var seen: Dictionary = {}
	var found: Array = []
	if area == null:
		return found
	var touched: Array = area.get_overlapping_bodies()
	for box in area.get_overlapping_areas():
		touched.append((box as Node).get_parent())
	for thing in touched:
		if thing == null or not is_instance_valid(thing) or not (thing as Node).is_in_group(group):
			continue
		var id: int = thing.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		found.append(thing)
	return found


static func all(tree: SceneTree) -> Array:
	"""Every body a monster may chase: the local player, and each remote
	player whose game shares monsters and who is not playing their death."""
	var found: Array = []
	if tree == null:
		return found
	for node in tree.get_nodes_in_group("player"):
		if is_instance_valid(node) and node is Node2D:
			found.append(node)
	for node in tree.get_nodes_in_group("remoteplayers"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		if not bool(node.get("shares")):
			continue
		if node.has_method("is_dying") and node.call("is_dying"):
			continue
		found.append(node)
	return found


static func nearest(tree: SceneTree, from: Vector2) -> Node2D:
	"""The closest of all(), or null when there is nobody."""
	var best: Node2D = null
	var best_d: float = INF
	for body in all(tree):
		var d: float = from.distance_squared_to((body as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = body
	return best


static func body_point(body: Node2D) -> Vector2:
	"""Where a player's BODY is - the "bodyshape" collision - rather than the
	node origin, which is somewhere else for every class: the warrior's body is
	13 px below its origin, the tank's 16 px above. Anything that aims at a
	player or asks whether it can see one asks here. A RemotePlayer carries a
	"bodyshape" marker for the same reason; anything without one is its origin.

	THE ORIGIN CAN BE INSIDE A WALL. A warrior walked up into a north wall has
	its body touching the wall and its origin 6 px into it, so a ray to the
	origin hits masonry and every enemy held fire (6 Oct, "walking up to the
	wall enemies dont attack"). The body is never inside a wall - it is the
	thing that collides with it."""
	if body == null:
		return Vector2.ZERO
	var shape: Node2D = body.get_node_or_null("bodyshape") as Node2D
	return shape.global_position if shape != null else body.global_position


static func nearest_distance(tree: SceneTree, from: Vector2) -> float:
	"""How far the closest of all() is, or INF when there is nobody."""
	var body: Node2D = nearest(tree, from)
	return from.distance_to(body.global_position) if body != null else INF


# =============================================================================
# WALLS BETWEEN: what stops an attack (0.69.1)
# =============================================================================
# The owner, in the Big Field: "players can attack enemies through doors/
# walls". Every way a player hurts a monster found its targets by overlap or
# by distance, and nothing asked whether a wall stood between - a swing, a
# spike or an aura reached through masonry, a closed crypt door and a pillar
# alike. A monster already asked (BaseEnemy._has_line_of_sight()); now a
# player's attack asks the same question here.
#
# WHAT BLOCKS: layer 1, where every TileMap, wall piece, crypt door and solid
# prop sits (the layer a monster's sight ray masks), and layer 2, the boss
# gates' bars - the spinning axe stopped at both already (WALL_LAYERS).
const BLOCKERS := 0b11

# How far short of a wall a clamped point stops, so what lands there is not
# inside the masonry it was stopped by.
const WALL_MARGIN := 4.0


static func clear_between(any: Node2D, from: Vector2, to: Vector2) -> bool:
	"""True when nothing solid stands between `from` and `to`. `any` is any
	node in the world, for its physics space; outside a world, or with no
	space to ask, nothing blocks.

	FROM A BODY, NEVER A NODE ORIGIN, for anything that has one: a ray that
	starts inside a wall does not see that wall, and an origin can be inside
	one (body_point()). Ask with body_point() of the attacker, or the middle of
	the effect - and of the monster, whose hurtbox can stand taller than the
	wall its feet are behind."""
	if any == null or not any.is_inside_tree():
		return true
	var world: World2D = any.get_world_2d()
	if world == null:
		return true
	var space: PhysicsDirectSpaceState2D = world.direct_space_state
	if space == null or from.distance_squared_to(to) < 0.01:
		return true
	var query := PhysicsRayQueryParameters2D.create(from, to, BLOCKERS)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space.intersect_ray(query).is_empty()


static func can_reach(attacker: Node2D, from: Vector2, target: Node) -> bool:
	"""May an attack from `from` touch `target`? The line to the target's
	body must be clear. A target that is not a Node2D has nowhere to be
	blocked, so it may."""
	if not (target is Node2D):
		return true
	return clear_between(attacker, from, body_point(target as Node2D))


static func short_of_wall(any: Node2D, from: Vector2, to: Vector2) -> Vector2:
	"""`to`, or the last point before the first wall on the way there from
	`from` - WALL_MARGIN short of it, so a spell cast at a wall lands on this
	side of it rather than on the other or inside it."""
	if any == null or not any.is_inside_tree():
		return to
	var world: World2D = any.get_world_2d()
	if world == null or world.direct_space_state == null or from.distance_squared_to(to) < 0.01:
		return to
	var query := PhysicsRayQueryParameters2D.create(from, to, BLOCKERS)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return to
	var at: Vector2 = hit["position"]
	var back: Vector2 = (from - at).normalized() * minf(WALL_MARGIN, at.distance_to(from))
	return at + back
