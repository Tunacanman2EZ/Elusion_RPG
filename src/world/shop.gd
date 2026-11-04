# shop.gd - the general store's trigger: walk in and its walls and roof (the
# exterior) give way to the room and its furniture; walk out and they come
# back. Only this game's own body opens it: the trigger's mask is the
# player's layer.
#
# OTHER PLAYERS INSIDE (0.112.1). The owner: "when a player goes into a house
# i can see them still they are standing on the house on my screen". Another
# player is a picture with no body, so the house never knew they were in it:
# from outside, the roof was drawn and they stood on it. Every frame, a
# picture whose feet are inside the trigger's box (covers()) is hidden while
# this game's player is outside, and shown while it is in
# (remoteplayer.gd set_hidden_indoors(), its pet with it). Only pictures this
# house hid are shown again (_hid), and all of them when the house goes.
extends Area2D

@onready var interior = $"../shopinterior"
@onready var exterior = $"../shopexterior"
@onready var interior_furniture = $"../interiorfurniture"

var me_inside: bool = false
# Pictures this house has hidden, by instance id.
var _hid: Dictionary = {}


func _ready():
	if interior: interior.visible = false
	if exterior: exterior.visible = true
	if interior_furniture: interior_furniture.visible = false


func _on_body_entered(body):
	if body.is_in_group("player"):
		me_inside = true
		if interior: interior.visible = true
		if exterior: exterior.visible = false
		if interior_furniture: interior_furniture.visible = true


func _on_body_exited(body):
	if body.is_in_group("player"):
		me_inside = false
		if interior: interior.visible = false
		if exterior: exterior.visible = true
		if interior_furniture: interior_furniture.visible = false


func _process(_delta: float) -> void:
	hide_those_inside()


func hide_those_inside() -> void:
	"""Another player inside is hidden from you outside, and shown to you in."""
	var box: CollisionShape2D = get_node_or_null("collisionshape2d") as CollisionShape2D
	for picture in get_tree().get_nodes_in_group(&"remoteplayers"):
		if not (picture is Node2D) or not picture.has_method("set_hidden_indoors"):
			continue
		var id: int = picture.get_instance_id()
		var out_of_sight: bool = not me_inside and box != null and covers(box, (picture as Node2D).global_position)
		if out_of_sight and not _hid.has(id):
			_hid[id] = picture
			picture.call("set_hidden_indoors", true)
		elif not out_of_sight and _hid.has(id):
			_hid.erase(id)
			picture.call("set_hidden_indoors", false)
	for id in _hid.keys():
		if not is_instance_valid(_hid[id]):
			_hid.erase(id)


static func covers(box: CollisionShape2D, point: Vector2) -> bool:
	"""Whether `point` in the world is inside `box`'s rectangle."""
	var rect := box.shape as RectangleShape2D
	if rect == null:
		return false
	var local: Vector2 = box.global_transform.affine_inverse() * point
	return absf(local.x) <= rect.size.x / 2.0 and absf(local.y) <= rect.size.y / 2.0


func _exit_tree() -> void:
	for id in _hid.keys():
		if is_instance_valid(_hid[id]):
			_hid[id].call("set_hidden_indoors", false)
	_hid.clear()
