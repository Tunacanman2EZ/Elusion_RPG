# crownedfight.gd - THE CROWNED, REMADE (0.134.0): step 1 of the commit
# folder's CROWNED_PLAN.txt. The owner, 5-6 Nov: "we remake the last boss and
# the area in the final boss room and we change the boss to be something that
# utilizes a bit of everything", "a beholder is a master of illusions", and of
# the plan, "lets try it out and see what happens".
#
# A child of the Crowned's room (scene/boss.tscn, written by
# src/tools/buildcrowned.gd). Every game runs its own: what it does is drawn
# and felt here, and the boss's kit is the boss's (bossenemy.gd crown_land).
#
# THE SEVEN CROWNS (phase 1, the boss above CROWNS_UNTIL of its health): from
# the moment it turns on somebody (BaseEnemy.engaged) the fight moves through
# the lands in the bands' order, CROWN_SECONDS each - light, wind, water, ice,
# earth, fire, dark, and round again. Each crown at once:
#   - the boss wears it (crown_land): that land's volleys and stalagmites,
#     orbs carrying its effect, and a tint of its colour;
#   - the floor washes in its colour (WASH, added, eased), its weather falls,
#     and its light of the seven round the room burns while the rest are dim;
#   - the floor fights (the Descent's land hazards, descentlands.gd - this
#     node is their host: room_rect, _player(), _edge_spot()): the crown's
#     own, and the last crown's lingering, so two lands overlap and react;
#   - a banner says it ("The Crown of Fire").
# Below CROWNS_UNTIL its last three phases (0.134.1, crownedphases.gd): the
# Sealing, the Trap and the Tear, in a room that lies. Past the walls, the
# rift (crownedrift.gd), which the Tear opens the floor onto.
#
# ILLUSIONS: from DECOY_FIRST, every DECOY_EVERY seconds, DECOY_COUNT decoy
# eyes (crowneddecoy.gd) stand round the boss for DECOY_SECONDS, wearing its
# own pictures - an attack, a pet or the touch aim may pick one, and it
# breaks. The real one is the one that casts. Each game sees its own.
# AND THEY SHUFFLE (0.134.2). The owner, playing it: "illusions are not great
# ig players know exactly where the boss is" - the copies stood round a boss
# that never moved. Now as they appear, and every DECOY_SHUFFLE while any is
# left, every eye blinks out in a flash of dark (shuffle()) and they come back
# in each other's places - the Crowned in any of them. (The game running the
# boss moves it; a picture of another game's boss stays, and only its copies
# trade places.)
#
# When the Crowned falls every light burns (the crowns returned); when it
# turns away (a leash home, nobody left), the room goes quiet and dark.
#
# No class_name: preload it by path.
extends Node2D

const LandsScript := preload("res://src/world/descent/descentlands.gd")
const DecoyScript := preload("res://src/world/crowned/crowneddecoy.gd")
const RiftScript := preload("res://src/world/crowned/crownedrift.gd")
const PhasesScript := preload("res://src/world/crowned/crownedphases.gd")

const CROWN_ORDER := [Element.Type.LIGHT, Element.Type.WIND, Element.Type.WATER, Element.Type.ICE,
	Element.Type.EARTH, Element.Type.FIRE, Element.Type.DARK]
const CROWN_SECONDS := 12.0
const CROWNS_UNTIL := 0.75
# How hard the floor fights: the Descent's fifth floor (descentlands.gd's
# env_gap(), env_share(), env_count(), laser_chance() of it).
const HAZARD_FLOOR := 4
const WASH_Z := -9
const WASH := 0.14
const WASH_EASE := 1.2
const DECOY_FIRST := 10.0
const DECOY_EVERY := 22.0
const DECOY_COUNT := 3
const DECOY_SECONDS := 9.0
const DECOY_SHUFFLE := 3.0
const DECOY_NEAR := 140.0
const DECOY_FAR := 240.0
const LIGHT_DIM := 0.18
const LIGHT_LIT := 1.5
const LIGHT_DONE := 0.9
const LIGHT_EASE := 2.5
const LIGHT_SCALE := 3.2
const BANNER_SECONDS := 2.6
const EDGE_CLEAR := 160.0

# Set by the builder: the room's floor inside its walls, and where the seven
# lights stand (in CROWN_ORDER).
@export var room_rect: Rect2 = Rect2()
@export var light_spots: PackedVector2Array = PackedVector2Array()

var boss: Node2D = null
var fighting: bool = false
var fight_clock: float = 0.0
# Which of CROWN_ORDER is on (-1: none - phase 1 over, or no fight).
var crown: int = -1
var decoys: Array = []
var decoys_made: int = 0
var won: bool = false
# The suite's player.
var player_override: Node2D = null
var lands: Node2D = null
var phases: Node2D = null
var rift: Node2D = null
var _wash: ColorRect = null
var _wash_want: Color = Color(0, 0, 0, 0)
var _lights: Array = []
var _light_want: Array = []
var _decoy_left: float = DECOY_FIRST
var _shuffle_left: float = DECOY_SHUFFLE
var shuffles: int = 0
var _banner: Label = null
var _banner_left: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_make_wash()
	_make_lights()
	_make_banner()
	lands = LandsScript.new()
	lands.name = "crownlands"
	lands.z_index = -1
	lands.set("run", self)
	add_child(lands)
	phases = PhasesScript.new()
	phases.name = "crownphases"
	phases.z_index = -1
	phases.set("fight", self)
	phases.set("lands", lands)
	phases.set("room", room_rect)
	phases.set("ground", get_parent().get_node_or_null("ground") if get_parent() != null else null)
	add_child(phases)
	_make_rift()


# =============================================================================
# EACH FRAME
# =============================================================================

func _process(delta: float) -> void:
	var found: Node2D = find_boss()
	if found != boss:
		boss = found
	var on: bool = boss != null and boss_alive(boss) and bool(boss.get("engaged"))
	if on and not fighting:
		begin()
	elif fighting and not on:
		finish(boss == null or not boss_alive(boss))
	if fighting:
		fight_clock += delta
		if share_left() > CROWNS_UNTIL:
			var want: int = crown_at(fight_clock)
			if want != crown:
				set_crown(want)
		else:
			if crown >= 0:
				leave_crowns()
			phases.call("step", delta, share_left())
		lands.call("step", delta)
		_step_decoys(delta)
	_ease(delta)


static func crown_at(seconds: float) -> int:
	"""Which crown is on `seconds` into the fight."""
	return int(floor(maxf(0.0, seconds) / CROWN_SECONDS)) % CROWN_ORDER.size()


func share_left() -> float:
	if boss == null or not is_instance_valid(boss):
		return 0.0
	return float(boss.get("hp")) / float(maxi(1, int(boss.get("max_hp"))))


func find_boss() -> Node2D:
	"""The Crowned in this room: the boss whose monster is "boss" - the
	respawner's new node, or a mirror of another game's, as it comes."""
	if boss != null and is_instance_valid(boss) and boss.is_inside_tree():
		return boss
	if not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if node is BossEnemy and is_instance_valid(node) and not (node as Node).has_meta(DecoyScript.STRESS_MARK):
			var data: Resource = (node as Node).get("enemy_data")
			if data != null and str(data.get("enemy_id")) == "boss":
				return node as Node2D
	return null


static func boss_alive(node: Node2D) -> bool:
	return node != null and is_instance_valid(node) and int(node.get("hp")) > 0 \
		and not bool(node.get("_dying"))


# =============================================================================
# THE FIGHT
# =============================================================================

func begin() -> void:
	fighting = true
	won = false
	fight_clock = 0.0
	crown = -1
	_decoy_left = DECOY_FIRST


func finish(fell: bool) -> void:
	"""The fight over: the crowns off, the floor quiet; every light burns if it
	fell, all dim if it only turned away."""
	fighting = false
	won = fell
	crown = -1
	if boss != null and is_instance_valid(boss):
		boss.set("crown_land", -1)
		_tint_boss(-1)
	lands.call("end")
	phases.call("end")
	lands.call("set_weathers", [], room_rect)
	_wash_want = Color(0, 0, 0, 0)
	for k in _light_want.size():
		_light_want[k] = LIGHT_DONE if fell else LIGHT_DIM
	for decoy in decoys:
		if is_instance_valid(decoy):
			(decoy as Node).call("shatter")
	decoys = []
	if fell:
		say("The crowns are free")


func set_crown(index: int) -> void:
	"""Crown `index` of CROWN_ORDER on: the boss's kit, the wash, the weather,
	the light, the floor's hazards (this land's and the last one's)."""
	var last: int = crown
	crown = index
	var land: int = int(CROWN_ORDER[index])
	if boss != null and is_instance_valid(boss):
		boss.set("crown_land", land)
		_tint_boss(land)
	var colour: Color = Element.colour_for(land)
	_wash_want = Color(colour.r, colour.g, colour.b, WASH)
	for k in _light_want.size():
		_light_want[k] = LIGHT_LIT if k == index else LIGHT_DIM
	var on_floor: Array = [land]
	if last >= 0 and int(CROWN_ORDER[last]) != land:
		on_floor.append(int(CROWN_ORDER[last]))
	lands.call("set_weathers", [land], room_rect)
	lands.call("begin_env", on_floor, HAZARD_FLOOR)
	say("The Crown of %s" % Element.name_for(land).capitalize())


func leave_crowns() -> void:
	"""Phase 1 over: the Crowned fights in its own dark again."""
	crown = -1
	if boss != null and is_instance_valid(boss):
		boss.set("crown_land", -1)
		_tint_boss(-1)
	lands.call("end")
	lands.call("set_weathers", [Element.Type.DARK], room_rect)
	var colour: Color = Element.colour_for(Element.Type.DARK)
	_wash_want = Color(colour.r, colour.g, colour.b, WASH)
	for k in _light_want.size():
		_light_want[k] = LIGHT_DIM
	say("The Crowned sheds its crowns")


func mood(land: int) -> void:
	"""The floor washed in `land`'s colour and its weather falling."""
	lands.call("set_weathers", [land], room_rect)
	var colour: Color = Element.colour_for(land)
	_wash_want = Color(colour.r, colour.g, colour.b, WASH)


func flash_wash(land: int) -> void:
	"""The room lies: the floor washes in `land`'s colour a moment, then eases
	back (_ease())."""
	if _wash == null:
		return
	var colour: Color = Element.colour_for(land)
	_wash.color = Color(colour.r, colour.g, colour.b, WASH * 1.8)


func _make_rift() -> void:
	"""The rift past the walls, behind the whole world (crownedrift.gd)."""
	var layer := CanvasLayer.new()
	layer.name = "riftlayer"
	layer.layer = -1
	layer.follow_viewport_enabled = true
	rift = RiftScript.new()
	rift.name = "rift"
	rift.set("room", room_rect if room_rect.size != Vector2.ZERO else Rect2(0, 0, 1024, 768))
	layer.add_child(rift)
	add_child(layer)


func _tint_boss(land: int) -> void:
	"""The Crowned in the land's colours: the game's own element recolour
	(BaseEnemy.element_material(), which a monster's shader draws - it writes
	its colour without the node's modulate), and back to what it wore."""
	var sprite: CanvasItem = boss.get_node_or_null("animatedsprite2d") as CanvasItem
	if sprite == null:
		return
	if not sprite.has_meta(&"crown_worn"):
		sprite.set_meta(&"crown_worn", sprite.material)
	var data: EnemyData = boss.get("enemy_data") as EnemyData
	if land < 0 or data == null:
		sprite.material = sprite.get_meta(&"crown_worn") as Material
		sprite.remove_meta(&"crown_worn")
	else:
		sprite.material = BaseEnemy.element_material(data, land)


# =============================================================================
# ILLUSIONS
# =============================================================================

func _step_decoys(delta: float) -> void:
	decoys = decoys.filter(func(d: Object) -> bool: return is_instance_valid(d) and not bool(d.get("broken")))
	if not decoys.is_empty():
		_shuffle_left -= delta
		if _shuffle_left <= 0.0:
			_shuffle_left = DECOY_SHUFFLE
			shuffle()
	_decoy_left -= delta
	if _decoy_left > 0.0:
		return
	_decoy_left = DECOY_EVERY
	if not make_decoys(DECOY_COUNT).is_empty():
		shuffle()
		_shuffle_left = DECOY_SHUFFLE


func shuffle() -> void:
	"""Every eye blinks out and comes back in another's place: the Crowned and
	its copies trade the spots they stood on."""
	if boss == null or not is_instance_valid(boss):
		return
	decoys = decoys.filter(func(d: Object) -> bool: return is_instance_valid(d) and not bool(d.get("broken")))
	var spots: Array = [boss.global_position]
	for decoy in decoys:
		spots.append((decoy as Node2D).global_position)
	if spots.size() < 2:
		return
	var order: Array = spots.duplicate()
	order.shuffle()
	if order == spots:
		order.push_back(order.pop_front())
	for at in spots:
		lands.call("burst_at", at, Element.Type.DARK)
	if not bool(boss.get("net_mirror")):
		boss.global_position = order[0]
		boss.reset_physics_interpolation()
		if boss is CharacterBody2D:
			(boss as CharacterBody2D).velocity = Vector2.ZERO
		order.remove_at(0)
	else:
		order.erase(boss.global_position)
	for k in decoys.size():
		var decoy: Node2D = decoys[k]
		decoy.call("place", order[k % order.size()])
		decoy.reset_physics_interpolation()
	shuffles += 1


func make_decoys(count: int) -> Array:
	"""`count` illusions of the Crowned round it, in the room, for
	DECOY_SECONDS."""
	var made: Array = []
	if boss == null or not is_instance_valid(boss) or boss.get_parent() == null:
		return made
	var holder: Node = boss.get_parent()
	var start: float = _rng.randf() * TAU
	for k in count:
		var spot: Vector2 = Vector2.INF
		for attempt in 12:
			var angle: float = start + TAU * float(k) / float(maxi(1, count)) + _rng.randf_range(-0.4, 0.4)
			var at: Vector2 = boss.global_position + Vector2.from_angle(angle) * _rng.randf_range(DECOY_NEAR, DECOY_FAR)
			if room_rect.size == Vector2.ZERO or room_rect.grow(-40.0).has_point(at):
				spot = at
				break
		if spot == Vector2.INF:
			continue
		var decoy: Node2D = DecoyScript.new()
		decoy.name = "crowneddecoy"
		decoy.set("room", room_rect.grow(-24.0))
		decoy.call("dress", boss, DECOY_SECONDS)
		holder.add_child(decoy)
		decoy.call("place", spot)
		decoy.reset_physics_interpolation()
		decoys.append(decoy)
		made.append(decoy)
		decoys_made += 1
	return made


# =============================================================================
# THE HOST OF THE LANDS' HAZARDS (descentlands.gd asks these)
# =============================================================================

func _player() -> Node2D:
	if player_override != null:
		return player_override if is_instance_valid(player_override) else null
	return get_tree().get_first_node_in_group(&"player") as Node2D if is_inside_tree() else null


func _edge_spot() -> Vector2:
	"""Somewhere along the room's walls, clear of the player."""
	var me: Node2D = _player()
	var mine: Vector2 = me.global_position if me != null else room_rect.get_center()
	var inner: Rect2 = room_rect.grow(-20.0)
	var at: Vector2 = inner.position
	for attempt in 24:
		match _rng.randi_range(0, 3):
			0:
				at = Vector2(_rng.randf_range(inner.position.x, inner.end.x), inner.position.y)
			1:
				at = Vector2(_rng.randf_range(inner.position.x, inner.end.x), inner.end.y)
			2:
				at = Vector2(inner.position.x, _rng.randf_range(inner.position.y, inner.end.y))
			_:
				at = Vector2(inner.end.x, _rng.randf_range(inner.position.y, inner.end.y))
		if at.distance_to(mine) >= EDGE_CLEAR:
			return at
	return at


# =============================================================================
# THE ROOM'S LOOK: the wash, the seven lights, the banner
# =============================================================================

func _make_wash() -> void:
	_wash = ColorRect.new()
	_wash.name = "crownwash"
	_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wash.position = room_rect.position
	_wash.size = room_rect.size
	_wash.z_index = WASH_Z
	_wash.z_as_relative = false
	var adding := CanvasItemMaterial.new()
	adding.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_wash.material = adding
	_wash.color = Color(0, 0, 0, 0)
	add_child(_wash)


func _make_lights() -> void:
	var glow := GradientTexture2D.new()
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(0.5, 0.0)
	glow.width = 128
	glow.height = 128
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	glow.gradient = fade
	for k in mini(light_spots.size(), CROWN_ORDER.size()):
		var land: int = int(CROWN_ORDER[k])
		var holder := Node2D.new()
		holder.name = "crownlight%d" % k
		holder.position = light_spots[k]
		var light := PointLight2D.new()
		light.name = "light"
		light.texture = glow
		light.texture_scale = LIGHT_SCALE
		light.color = Element.colour_for(land)
		light.energy = LIGHT_DIM
		holder.add_child(light)
		holder.set_meta(&"land", land)
		holder.draw.connect(_draw_light.bind(holder))
		add_child(holder)
		_lights.append(holder)
		_light_want.append(LIGHT_DIM)


func _draw_light(holder: Node2D) -> void:
	"""A crown on a stone: the land's colour, as bright as its light."""
	var land: int = int(holder.get_meta(&"land", Element.Type.NONE))
	var light: PointLight2D = holder.get_node("light") as PointLight2D
	var lit: float = clampf(light.energy / LIGHT_LIT, 0.0, 1.0)
	var colour: Color = Element.colour_for(land)
	holder.draw_circle(Vector2(0, 2), 7.0, Color(0.12, 0.1, 0.14, 0.9))
	holder.draw_arc(Vector2(0, 2), 7.0, 0.0, TAU, 20, Color(0.35, 0.3, 0.38), 1.0)
	var tip := Color(colour.r, colour.g, colour.b, 0.35 + 0.65 * lit)
	var crown_shape := PackedVector2Array([Vector2(-5, 0), Vector2(-5, -6), Vector2(-2.5, -3),
		Vector2(0, -8), Vector2(2.5, -3), Vector2(5, -6), Vector2(5, 0)])
	holder.draw_colored_polygon(crown_shape, tip)
	if lit > 0.5:
		holder.draw_circle(Vector2(0, -4), 2.0 + 2.0 * lit, Color(1, 1, 1, 0.25 * lit))


func _make_banner() -> void:
	var layer := CanvasLayer.new()
	layer.name = "crownbanner"
	layer.layer = 40
	add_child(layer)
	_banner = Label.new()
	_banner.name = "banner"
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_top = 70.0
	_banner.offset_left = -300.0
	_banner.offset_right = 300.0
	_banner.add_theme_font_size_override("font_size", 22)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	layer.add_child(_banner)


func say(text: String) -> void:
	if _banner == null:
		return
	_banner.text = text
	var land: int = int(CROWN_ORDER[crown]) if crown >= 0 else Element.Type.DARK
	_banner.add_theme_color_override("font_color", Color.WHITE.lerp(Element.colour_for(land), 0.5))
	_banner_left = BANNER_SECONDS


func _ease(delta: float) -> void:
	if _wash != null:
		_wash.color = _wash.color.lerp(_wash_want, clampf(delta * WASH_EASE, 0.0, 1.0))
	for k in _lights.size():
		var holder: Node2D = _lights[k]
		var light: PointLight2D = holder.get_node("light") as PointLight2D
		var want: float = float(_light_want[k])
		if absf(light.energy - want) > 0.005:
			light.energy = lerpf(light.energy, want, clampf(delta * LIGHT_EASE, 0.0, 1.0))
			holder.queue_redraw()
	if _banner != null and _banner_left > 0.0:
		_banner_left -= delta
		_banner.modulate.a = clampf(minf(_banner_left / 0.5, (BANNER_SECONDS - _banner_left) / 0.3), 0.0, 1.0)
