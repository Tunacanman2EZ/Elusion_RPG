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


static func nearest_distance(tree: SceneTree, from: Vector2) -> float:
	"""How far the closest of all() is, or INF when there is nobody."""
	var body: Node2D = nearest(tree, from)
	return from.distance_to(body.global_position) if body != null else INF
