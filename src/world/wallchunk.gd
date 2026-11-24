# wallchunk.gd - a chunk of the Big Field's walls: their pictures are its
# children, and the boxes they block with are one body it makes (0.176.1).
#
# THE WALLS FLATTENED. The owner, of the Big Field's arrival: "yes" to the
# plan. Its 4,555 wall pieces were each a crypt scene - a Node2D, its
# Sprite2D, a StaticBody2D and one or two CollisionShape2Ds: 18,846 nodes
# that cost 55 ms to put in the world on arrival and 96 ms to take out on
# leaving (zz/bfbranches). buildbigfield.gd now writes each piece's picture
# straight into its chunk (a Sprite2D at its foot, sorted there as the piece
# was) and its boxes into `boxes`; here they become ONE StaticBody2D, on the
# walls' layer as every piece's body was, a shape each - made as the chunk
# enters the world, an internal child (get_children() is the pictures).
#
# Hidden or shown by propchunks.gd as before: a hidden chunk still blocks.
# No class_name: the builder preloads it by path.
extends Node2D

# Each box: x, y, width, height, in the chunk's space - the world's, a chunk
# stands at the origin.
@export var boxes: PackedFloat32Array = PackedFloat32Array()

const BODY := "body"

# One RectangleShape2D a size, for every chunk.
static var _shapes: Dictionary = {}


func _ready() -> void:
	if boxes.size() < 4 or has_node(BODY):
		return
	var body := StaticBody2D.new()
	body.name = BODY
	for k in range(0, boxes.size() - 3, 4):
		var size := Vector2(boxes[k + 2], boxes[k + 3])
		var id: int = body.create_shape_owner(body)
		body.shape_owner_add_shape(id, shape_of(size))
		body.shape_owner_set_transform(id, Transform2D(0.0, Vector2(boxes[k], boxes[k + 1]) + size / 2.0))
	add_child(body, false, Node.INTERNAL_MODE_BACK)


static func shape_of(size: Vector2) -> RectangleShape2D:
	var key: String = "%s" % size
	if not _shapes.has(key):
		var shape := RectangleShape2D.new()
		shape.size = size
		_shapes[key] = shape
	return _shapes[key]


func box_rects() -> Array[Rect2]:
	"""Its boxes, as rectangles in its space."""
	var out: Array[Rect2] = []
	for k in range(0, boxes.size() - 3, 4):
		out.append(Rect2(boxes[k], boxes[k + 1], boxes[k + 2], boxes[k + 3]))
	return out
