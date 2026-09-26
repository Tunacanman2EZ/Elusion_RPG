# roofswap.gd — hides a house's roof when the player is inside, shows it
# when outside. replaces houseswap.gd's old interior/exterior scene-swap
# approach entirely.
#
# NOTHING REFERENCES THIS RIGHT NOW, and the irony is worth recording rather
# than quietly deleting the file. Its only user was scene/walls/shop.tscn, the
# old shop, which was removed because the only art it drew was a tileset of
# unconfirmed origin (see assetlicense.md). The shop the game actually builds,
# scene/walls/shophouse.tscn, is interior/exterior scenes — the very approach
# the paragraph above says this replaced entirely. So this is the replacement
# that got replaced.
#
# Kept because the design note below is the useful part and the next house that
# wants a roof will want it, not because anything calls it. If you are reading
# this while wiring up a second house, this is the file you want.
#
# WHY THIS IS SIMPLER THAN THE OLD SYSTEM:
# houseswap.gd toggled between two entire pre-built halves (a full
# "interior" node and a full "exterior" node) every time the player
# crossed the trigger. but the ONLY thing that actually needs to disappear
# is the roof — walls, floor, and furniture can all just render
# continuously the whole time, the same way any other Y-sorted world
# object does, whether the player is inside or outside. so this script
# only ever toggles ONE node's visibility, not two.
#
# SCENE SETUP:
# - attach this script to an Area2D sized to the house's interior bounds
#   (same trigger area houseswap.gd used to use)
# - the roof itself gets moved OUT of this house's local node structure
#   and reparented as a child of `aboveworld` (the always-on-top,
#   non-Y-sorted layer already used elsewhere in this project) — that's
#   what makes it correctly render above the player from outside without
#   needing to be Y-sorted against them.
# - assign `roof` in the Inspector to point at that specific roof node.
#   each house needs its OWN trigger with its OWN roof assigned — there's
#   no automatic name-matching between a trigger and a roof, since they no
#   longer live near each other in the tree.
#
# starting state: player begins outside, so roof starts visible.
extends Area2D


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# assign in the Inspector — the specific roof node (living under
# aboveworld) that this trigger controls.
@export var roof: CanvasItem


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_set_initial_visibility()
	_wire_collision_signals()
	_warn_if_roof_missing()


func _set_initial_visibility() -> void:
	# player starts outside every house — roof starts visible.
	if roof != null:
		roof.visible = true


func _wire_collision_signals() -> void:
	# guarded against double-connection in case these are also wired
	# through the editor's Signals panel.
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _warn_if_roof_missing() -> void:
	if roof == null:
		push_warning("RoofSwap: no roof assigned in the Inspector for this trigger — nothing will happen on enter/exit.")


# =============================================================================
# COLLISION HANDLERS
# =============================================================================

func _on_body_entered(body: Node2D) -> void:
	# NOTE: the player's body must be on a collision layer that this
	# Area2D's mask includes — if it isn't, this signal never fires. check
	# both layer and mask in the Inspector if entering the trigger does
	# nothing (same gotcha the old houseswap.gd flagged).
	if not body.is_in_group("player"):
		return
	if roof != null:
		roof.visible = false


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if roof != null:
		roof.visible = true
