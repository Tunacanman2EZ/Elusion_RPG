# petcontroller.gd — the mechanics of getting a pet into and out of the world.
#
# Split out of player.gd, which was 63KB and held all of this inline. Player
# still owns `active_pet_id` and still decides WHEN a pet appears; this owns
# HOW, and is the only place that answers "which scene is this pet" or "what
# counts as a pet node".
#
# WHY IT IS NOT A NODE
# --------------------
# Nothing here has state between calls. A pet is found through the scene tree's
# "pets" group and identified through ItemRegistry, so an instance would have
# nothing to remember. Static functions on a RefCounted keep it callable from
# anywhere without adding a node to every character scene.
#
# WHY active_pet_id STAYED ON PLAYER
# ----------------------------------
# CharacterData persists it per character slot and ServerStorage puts it on the
# wire. Moving it would have meant touching the save format to tidy a file,
# which is the wrong trade.
class_name PetController
extends RefCounted


# Where a summoned pet is placed relative to the player. Above them, so it is
# visible immediately rather than underneath the sprite that just summoned it.
const SUMMON_OFFSET := Vector2(0, -40)


# =============================================================================
# LOOKUP
# =============================================================================

static func pet_scene_for(item_id: String) -> PackedScene:
	# The ONE answer to "which scene does this pet item summon", and the one
	# definition of what counts as summonable.
	#
	# THIS USED TO BE TWO CHECKS THAT DISAGREED. summon_pet() required
	# type == PET and a pet_scene; _restore_active_pet() required only a
	# pet_scene. So a save could restore a companion from an item the game
	# would refuse to summon from — not reachable today, because the only thing
	# that writes active_pet_id is the strict path, but two copies of a rule
	# only ever drift further apart.
	#
	# Unifying on the STRICTER of the two is safe in both directions: every
	# value summon_pet() can legitimately have written passes it, and the only
	# values it now rejects are ones a hand-edited or stale save could hold,
	# where refusing is the correct answer.
	if item_id == "":
		return null

	var data: ItemData = ItemRegistry.get_item(item_id)
	if data == null:
		push_warning("PetController: no item '%s' in the registry." % item_id)
		return null
	if data.type != ItemData.Type.PET:
		push_warning("PetController: item '%s' is not a pet." % item_id)
		return null
	if data.pet_scene == null:
		push_warning("PetController: pet item '%s' has no pet_scene assigned." % item_id)
		return null

	return data.pet_scene


# =============================================================================
# SPAWNING AND DESPAWNING
# =============================================================================

static func despawn_all(tree: SceneTree) -> int:
	# Frees every pet currently in the world and reports how many. One pet at a
	# time is the model — active_pet_id is a single string — so summoning is
	# always a replacement, and anything left behind is untracked by definition.
	#
	# THE TYPE CHECK IS NOT BELT AND BRACES. field.tscn once had its pets
	# CONTAINER node in the "pets" group, the same group the pets themselves
	# join, so summoning a pet in the field deleted the container out of the
	# scene. That scene is fixed; a loop that frees whatever a group hands it
	# would do it again the next time a group is mistyped. A pet is a
	# CharacterBody2D. A container is not.
	if tree == null:
		return 0

	var freed: int = 0
	for node in tree.get_nodes_in_group("pets"):
		if not is_instance_valid(node):
			continue
		# queue_free() is DEFERRED. A node stays valid and stays in its groups
		# until the end of the frame, so without this a second call in the same
		# frame counts the same pet again and reports freeing something that was
		# already on its way out.
		if node.is_queued_for_deletion():
			continue
		if not (node is CharacterBody2D):
			push_warning("Node '%s' is in group 'pets' but isn't a pet - skipping." % node.name)
			continue
		node.queue_free()
		freed += 1
	return freed


static func attach(player: Node2D, pet: Node, offset: Vector2) -> void:
	# The single place a pet is put into the world, so no spawn path can forget
	# either of the two orderings below.
	#
	# ORDER 1: owner_player is claimed BEFORE add_child(), because add_child()
	# runs the pet's _ready(), which is where it resolves who to follow. Set it
	# afterwards and the pet has already fallen back to
	# get_nodes_in_group("player")[0] — right by luck with one player, arbitrary
	# with two — and nothing re-resolves it while that stays valid.
	#
	# ORDER 2: reset_physics_interpolation() comes AFTER the position is set.
	# The project runs with interpolation on, so a node that is PLACED rather
	# than moved is otherwise drawn once at the origin and streaks across the
	# map over a single frame.
	if player == null or pet == null:
		return

	if pet is Pet:
		pet.owner_player = player

	player.get_tree().current_scene.add_child(pet)
	pet.global_position = player.global_position + offset
	pet.reset_physics_interpolation()
