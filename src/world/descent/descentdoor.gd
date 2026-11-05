# descentdoor.gd - A DOOR OF THE DESCENT (0.112.0): the crypt door between
# its posts, shut while a room is fought (`set_open()`), and a medallion on it
# saying what waits behind (`set_reward()`). Walked into while open, it says
# so (`walked_in`) and the run takes the player on.
#
# Built from the crypt door's own art (scene/crypt/door.tscn's three pieces,
# without its script - this one opens when the room is clear, not with the
# interact key), and its body: a post each side, always solid, and the shut
# planks between them, solid only while shut. The body is saved in the scene
# (builddescent.gd, make_body()) so the suite's walk of every area meets it
# shut; a door made in code alone builds its own.
#
# No class_name: placed by builddescent.gd, preloaded by the run and the suite.
extends Node2D

signal walked_in(door: Node2D)

const DOOR_ART := "res://art/floordecoration/cryptdoor.png"
const WALLS_ART := "res://art/floordecoration/floorwalls.png"
const ICONS := {
	"upgrade": "res://art/pack/icons/attackiconcharacterstats.png",
	"gold": "res://art/pack/currency/goldpile.png",
	# STEP 2 (0.115.0): the pack's own pictures, whole.
	"shrine": "res://art/pack/icons/magiciconcharacterstats.png",
	"treasure": "res://art/pack/currency/platinumcoin.png",
	"challenge": "res://art/pack/icons/agilityiconcharacterstats.png",
	"rest": "res://art/pack/icons/defenceiconcharacterstats.png",
}
# The rim: gold, the keeper's red, a shrine's violet, a challenge's blue, an
# Impossible room's blood red (0.124.0).
const RIMS := {"keeper": Color(1.0, 0.45, 0.3), "shrine": Color(0.82, 0.5, 1.0), "challenge": Color(0.45, 0.75, 1.0),
	"impossible": Color(1.0, 0.08, 0.12)}
const SKULL := Rect2(123, 91, 9, 9)
const GOLD := Color(1.0, 0.86, 0.45)
const RED := Color(1.0, 0.45, 0.3)
# The medallion's middle over the door's foot, and its size.
const MEDAL_AT := Vector2(0, -30)
const MEDAL_RADIUS := 15.0
# Brighter than white, so the crypt's dark (its CanvasModulate) leaves it lit.
const LIT := Color(1.7, 1.7, 1.5)

@export var reward: String = ""
@export var open: bool = false
# The front door, where a room is come into: always shut, never a reward.
@export var entrance: bool = false

var planks: Sprite2D = null
var shut_shape: CollisionShape2D = null
var trigger: Area2D = null
var medal: Node2D = null
var hole: Node2D = null


class Medal extends Node2D:
	var door: Node2D = null

	func _draw() -> void:
		var kind: String = str(door.get("reward"))
		if kind == "":
			return
		var lit: bool = bool(door.get("open"))
		var a: float = 1.0 if lit else 0.6
		var rim: Color = RIMS.get(kind, GOLD)
		draw_circle(MEDAL_AT, MEDAL_RADIUS, Color(0.05, 0.04, 0.06, 0.9 * a))
		draw_arc(MEDAL_AT, MEDAL_RADIUS, 0.0, TAU, 32, Color(rim, a), 1.5)
		if lit:
			draw_arc(MEDAL_AT, MEDAL_RADIUS + 3.0, 0.0, TAU, 32, Color(rim, 0.4), 1.0)
		var tex: Texture2D = door.call("icon_for", kind)
		if tex != null:
			var side: float = 18.0
			draw_texture_rect(tex, Rect2(MEDAL_AT - Vector2(side, side) / 2.0, Vector2(side, side)), false,
				Color(1, 1, 1, a))
		elif kind == "begin" or kind == "down":
			# DOWN: an arrow, the way deeper.
			var c := Color(GOLD, a)
			draw_colored_polygon(PackedVector2Array([MEDAL_AT + Vector2(-7, -3), MEDAL_AT + Vector2(7, -3),
				MEDAL_AT + Vector2(0, 7)]), c)
			draw_rect(Rect2(MEDAL_AT + Vector2(-2.5, -9), Vector2(5, 7)), c)


func _ready() -> void:
	var art: Texture2D = load(DOOR_ART) as Texture2D
	hole = Node2D.new()
	hole.name = "hole"
	hole.draw.connect(_draw_hole)
	add_child(hole)
	for part in [["left", Rect2(14, 19, 9, 28), -30.0], ["planks", Rect2(23, 19, 21, 28), 0.0],
			["right", Rect2(44, 19, 9, 28), 30.0]]:
		var tex := AtlasTexture.new()
		tex.atlas = art
		tex.region = part[1]
		var piece := Sprite2D.new()
		piece.name = str(part[0])
		piece.texture = tex
		piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		piece.scale = Vector2(2, 2)
		piece.position = Vector2(float(part[2]), -28.0)
		add_child(piece)
		if part[0] == "planks":
			planks = piece
	var body: Node = get_node_or_null("body")
	if body == null:
		body = make_body()
		add_child(body)
	shut_shape = body.get_node_or_null("shut") as CollisionShape2D
	if not entrance:
		trigger = Area2D.new()
		trigger.name = "through"
		trigger.collision_layer = 0
		trigger.collision_mask = 4
		trigger.monitorable = false
		var reach := CollisionShape2D.new()
		var reach_box := RectangleShape2D.new()
		reach_box.size = Vector2(40, 14)
		reach.shape = reach_box
		reach.position = Vector2(0, -26)
		trigger.add_child(reach)
		add_child(trigger)
		trigger.body_entered.connect(_on_body_entered)
	medal = Medal.new()
	medal.name = "medal"
	medal.door = self
	medal.z_index = 20
	medal.self_modulate = LIT
	add_child(medal)
	_show()


static func make_body() -> StaticBody2D:
	"""The door's body: a post each side and the shut planks between (as
	scene/crypt/door.tscn's)."""
	var body := StaticBody2D.new()
	body.name = "body"
	for side in [["sideleft", -30.0], ["sideright", 30.0]]:
		var post := CollisionShape2D.new()
		post.name = str(side[0])
		var post_box := RectangleShape2D.new()
		post_box.size = Vector2(18, 16)
		post.shape = post_box
		post.position = Vector2(float(side[1]), -8)
		body.add_child(post)
	var shut := CollisionShape2D.new()
	shut.name = "shut"
	var shut_box := RectangleShape2D.new()
	shut_box.size = Vector2(42, 16)
	shut.shape = shut_box
	shut.position = Vector2(0, -8)
	body.add_child(shut)
	return body


func set_open(now: bool) -> void:
	open = now and not entrance
	_show()


func set_reward(kind: String) -> void:
	reward = "" if entrance else kind
	_show()


func _show() -> void:
	if planks != null:
		planks.visible = not open
	if shut_shape != null:
		shut_shape.set_deferred("disabled", open)
	if hole != null:
		hole.queue_redraw()
	if medal != null:
		medal.queue_redraw()


func _draw_hole() -> void:
	"""The way through, while open: dark, a little lit at the floor."""
	if not open:
		return
	hole.draw_rect(Rect2(-21, -56, 42, 56), Color(0.0, 0.0, 0.0))
	for k in 6:
		hole.draw_rect(Rect2(-21, -8 - k * 8, 42, 8), Color(0.25, 0.2, 0.35, 0.06 * (6 - k)))


func icon_for(kind: String) -> Texture2D:
	"""The medallion's picture: the pack's icon or coin, the crypt's skull for
	an elite or the keeper - none where a clone has no pack (it draws the ring
	alone)."""
	if kind == "elite" or kind == "keeper" or kind == "impossible":
		var skull := AtlasTexture.new()
		skull.atlas = load(WALLS_ART) as Texture2D
		skull.region = SKULL
		return skull
	var path: String = str(ICONS.get(kind, ""))
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _on_body_entered(body: Node) -> void:
	if open and body != null and body.is_in_group(&"player"):
		walked_in.emit(self)
