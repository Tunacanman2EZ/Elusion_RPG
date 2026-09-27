class_name SafeSpot
extends RefCounted

# Somewhere a character can actually stand, at or near a point.
#
# TWO CALLERS, ONE RULE, and they want subtly different things:
#
#   ownerpanel.gd  "go to them" must land BESIDE a player, never inside them,
#                  and must not put the owner in a wall or off the map.
#   characterhud.gd every teleport that ARRIVES lands on coordinates the server
#                  chose with no idea where the walls are.
#
# The second one is the important one and it is easy to miss. The server spaces a
# group perfectly - teleport_offset() in app.py packs them into hexagonal rings
# at TELEPORT_SPACING and hands each client its own final coordinates, so nobody
# stacks and no client has to repeat the arithmetic. But that is pure geometry.
# Move fifty people into the town square and the outer ring is 192px out, which
# in a tight room is inside the scenery. THE SERVER CANNOT KNOW THAT. The client
# is the only side holding the collision shapes, so the nudge belongs here.
#
# WHY A HEX RING RATHER THAN A RANDOM SCATTER. It mirrors teleport_offset()
# exactly - same 48px step, same six-per-ring packing - so a nudged player lands
# on a spot the server would have considered legitimate for somebody else, and a
# group that gets nudged stays looking arranged rather than sprayed.
#
# WHAT IT DELIBERATELY WILL NOT DO is invent a spot. If nothing within RINGS is
# clear it returns Vector2.INF and the caller refuses the move. Landing a player
# outside the map is worse than not moving them, and "it did nothing and said so"
# is a bug report; "it put me in the void" is a lost character.

# Mirrors TELEPORT_SPACING in app.py. Kept in sync by hand - there is no wire to
# carry it, and the server sends its own value on the teleport response, which
# is the one that decides where a GROUP lands. This is only for the nudge.
const SPACING := 48.0

# Three rings is 18 candidate spots out to 144px. Past that a "safe spot near
# you" is far enough away to be its own surprise.
const RINGS := 3

# How far off the navigation mesh a point may be and still count as on it.
# NavigationServer2D.map_get_closest_point() always returns SOMETHING, so the
# distance back is the only signal that the query point was really walkable.
const NAV_TOLERANCE := 24.0


static func find(body: CharacterBody2D, anchor: Vector2, start_ring: int = 0) -> Vector2:
	"""A clear spot at or near `anchor`, or Vector2.INF if there is not one.

	start_ring 0 tries the anchor itself first - what an arriving teleport wants,
	because the server already picked that spot on purpose. start_ring 1 skips
	it, which is what "stand next to them" means.
	"""
	if body == null or not is_instance_valid(body):
		return anchor

	for ring in range(max(0, start_ring), RINGS + 1):
		if ring == 0:
			if _is_clear(body, anchor):
				return anchor
			continue

		# Six per ring, times the ring number - the same packing app.py uses.
		var slots: int = 6 * ring
		for index in slots:
			var angle: float = (TAU * float(index)) / float(slots)
			var candidate: Vector2 = anchor + Vector2(cos(angle), sin(angle)) * (ring * SPACING)
			if _is_clear(body, candidate):
				return candidate

	return Vector2.INF


static func _is_clear(body: CharacterBody2D, point: Vector2) -> bool:
	# BOTH TESTS, because neither is enough on its own.
	#
	# Navigation knows where the FLOOR is, which is the only thing that answers
	# "off the map" - a point past the edge of the world is clear of every
	# collider precisely because there is nothing there. But only field.tscn and
	# bossarena.tscn carry a NavigationRegion2D; elusion.tscn does not, so a
	# navigation-only test would silently pass everything in town.
	#
	# Physics knows where the WALLS are, and works everywhere.
	return _on_navigable_ground(body, point) and _nothing_in_the_way(body, point)


static func _on_navigable_ground(body: CharacterBody2D, point: Vector2) -> bool:
	# NO NAVMESH IN THIS SCENE: not a failure, and not a reason to refuse. The
	# physics half below still applies, and it is the one that works in town.
	var map: RID = body.get_world_2d().get_navigation_map()
	if not map.is_valid() or NavigationServer2D.map_get_regions(map).is_empty():
		return true

	# map_get_closest_point() always returns a point, so it can never say "no".
	# The DISTANCE is the answer: a query that was already on the mesh comes
	# back where it started, and one out in the void comes back at the edge.
	var nearest: Vector2 = NavigationServer2D.map_get_closest_point(map, point)
	return nearest.distance_to(point) <= NAV_TOLERANCE


static func _nothing_in_the_way(body: CharacterBody2D, point: Vector2) -> bool:
	var shape_node: CollisionShape2D = body.get_node_or_null("bodyshape") as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		# NO SHAPE TO TEST WITH. Say yes rather than no: refusing every teleport
		# because a scene was built differently is a worse failure than landing
		# somewhere snug, and the navigation half above still ran.
		return true

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape_node.shape
	query.transform = Transform2D(0.0, point + shape_node.position)

	# THE BODY'S OWN MASK, so "in the way" means whatever this character already
	# cannot walk through - and not a number typed here that drifts from it the
	# first time a layer is added.
	query.collision_mask = body.collision_mask
	query.collide_with_bodies = true

	# ITSELF EXCLUDED. A character standing at the anchor collides with the
	# anchor, so without this the spot you are already in never reads as clear.
	query.exclude = [body.get_rid()]

	return body.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()
