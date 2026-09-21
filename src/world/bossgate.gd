# bossgate.gd — one ice pane holding one boss until its wave comes up.
#
# WHAT A GATE IS FOR, since a spawner would have been less work: the player
# walks into the arena and SEES the whole gauntlet standing behind ice. Bosses
# that appear out of nothing on cue are cheaper to build and read as the room
# cheating - there is no way to judge what is coming, and no moment of dread
# before it arrives.
#
# THE GATE DOES NOT HOLD THE BOSS. BaseEnemy.gated does, and the pane is what
# makes that legible. The collision body is there so the PLAYER cannot walk
# into the cage and so shots stop at the ice; the boss is already immobile and
# immune from the flag. If the two ever disagree, the flag is the truth.
#
# SPRITE2D QUADS, NOT ColorRects, and that distinction cost a run. A Control
# inside a Node2D resolves its rect against the VIEWPORT rather than its
# parent, and a Control that ends up zero-sized draws nothing and reports
# nothing - the prisms were in the scene, instantiated, erroring on nothing,
# and invisible. A Sprite2D with a PlaceholderTexture2D has an explicit size,
# maps UV 0..1 across it for the shader, and has no layout to get wrong.
#
# THE MATERIALS ARE resource_local_to_scene, and leaving that off cost a run.
# A sub-resource in a scene is SHARED by every instance of it, so all six
# prisms held the same two ShaderMaterials: the gauntlet opened wave 1 on
# ready, tweened `dissolve` to 1 on that shared material, and every prism in
# the room erased itself inside 0.6 seconds. They were drawing correctly the
# whole time - the boot line said 80x82 with a shader on both halves - and
# the thing that made them invisible was one gate opening. It also meant the
# per-element tint could not work: six _tint() calls, one material, last one
# wins.
#
# TWO PANES, NOT ONE, and that is what makes it a container rather than a
# wall. "far" draws behind the boss at z_index -5 and "near" in front at +5,
# so the boss is sandwiched between the back and front of the same box. One
# pane, however pretty, only ever reads as glass the boss is standing behind.
#
# SCENE SETUP is in bossgate.tscn: Sprite2D quads named "far" and "near" carrying
# bossgate.gdshader (with its `far` uniform set to match), and a StaticBody2D
# named "bars" on the walls layer - layer 2, which both the player and other
# enemies already mask, so the prism stops everything without naming anything.
#
# SIZED TO THE BOSS, NOT TO THE ROOM. The boss sprite is 64x64, so the prism
# is 80x82 - tight enough that it reads as a thing CONTAINING the boss rather
# than a booth it is standing in. The first version was 170x190, about three
# times too big in every direction, which looked like scenery.
#
# The collision block is the prism's own footprint and nothing more, so it
# cannot surprise anyone: you see solid ice, you do not walk through it. The
# holding is done by BaseEnemy.gated either way - delete the "bars" node and
# the gauntlet still works, it just stops feeling solid.
extends Node2D

# The boss this gate holds. Left empty, the gate is decorative - it will still
# draw and still open on cue, which is useful for a wall of ice that is not
# holding anything.
@export var boss_path: NodePath

# Which wave opens this gate. bossgauntlet.gd reads it; the gate itself never
# decides when to open.
@export var wave: int = 1

# Element.Type. Drives the tint, and defaults to ICE because that is what the
# pane looks like with no element at all.
@export var element: int = Element.Type.ICE

# How long the shatter takes. Short - this is the beat before a boss reaches
# you, not a cutscene.
@export var open_seconds: float = 0.6

var _boss: Node = null
var _open: bool = false

@onready var far_pane: CanvasItem = get_node_or_null("far")
@onready var near_pane: CanvasItem = get_node_or_null("near")
@onready var bars: StaticBody2D = get_node_or_null("bars")


func _ready() -> void:
	_boss = get_node_or_null(boss_path) if not boss_path.is_empty() else null

	# GATED FROM THE FIRST FRAME, set here rather than saved into the scene.
	# A boss whose gated flag lived in bossarena.tscn would come up ungated
	# the moment somebody duplicated it and forgot the checkbox; setting it
	# from the thing that holds it means the two cannot drift apart.
	if _boss != null and "gated" in _boss:
		_boss.set("gated", true)

	_tint()

	# SAYS SO ONCE, at boot, in the pane everyone actually reads.
	#
	# The first build of this was invisible with no error anywhere, and there
	# was no way to tell "the gates are missing" from "the gates are there and
	# drawing nothing" without opening the scene. One line removes that whole
	# question. Debug builds only - it is a diagnostic, not a game message.
	if OS.is_debug_build():
		var where: String = _boss.name if _boss != null else "(no boss)"
		# THE PANE STATE, NOT JUST THE WIRING. Two builds of this were present,
		# correctly wired and completely invisible - first a ColorRect with no
		# resolved size, then a PlaceholderTexture2D, which reports a size and
		# rasterises nothing. Both were silent. So the line says whether each
		# half can actually DRAW: a texture with a real size, and a shader on
		# it. "0x0" or "no shader" here names the next failure immediately
		# instead of costing another run.
		var panes := PackedStringArray()
		for pane_name in ["far", "near"]:
			var node: Node = get_node_or_null(pane_name)
			if node == null:
				panes.append("%s MISSING" % pane_name)
				continue
			var size := Vector2.ZERO
			if node is Sprite2D and (node as Sprite2D).texture != null:
				size = (node as Sprite2D).texture.get_size()
			var shaded: bool = node is CanvasItem \
				and (node as CanvasItem).material is ShaderMaterial \
				and ((node as CanvasItem).material as ShaderMaterial).shader != null
			panes.append("%s %dx%d%s" % [pane_name, int(size.x), int(size.y),
				"" if shaded else " NO SHADER"])
		var held: String = "?"
		if _boss != null:
			held = "gated" if bool(_boss.get("gated")) else "NOT GATED"
		print("[GATE] %s wave %d element %d holding %s (%s)  [%s]"
			% [name, wave, element, where, held, ", ".join(panes)])


func _panes() -> Array:
	# Both halves, skipping any the scene is missing - a prism with only its
	# near face still works, it just stops looking like a box.
	var found: Array = []
	for pane in [far_pane, near_pane]:
		if pane != null and pane.material is ShaderMaterial:
			found.append(pane.material as ShaderMaterial)
	return found


func _tint() -> void:
	# Element.COLOURS is the same palette the recolour shader puts on the boss
	# itself, so the prism and the thing inside it always agree.
	var colour: Color = Element.COLOURS.get(element, Element.COLOURS[Element.Type.ICE])
	for material in _panes():
		material.set_shader_parameter("tint", colour)
		material.set_shader_parameter("dissolve", 0.0)


func is_open() -> bool:
	return _open


func open() -> void:
	# IDEMPOTENT. bossgauntlet.gd advances on a died signal, and two bosses
	# dying in the same frame would otherwise run this twice - freeing the
	# same node and re-releasing a boss that is already loose.
	if _open:
		return
	_open = true

	# THE FLAG FIRST, THE ANIMATION SECOND. If the tween is interrupted - a
	# scene change, the arena reset mid-shatter - the boss is already free
	# rather than frozen behind an invisible gate forever.
	if _boss != null and "gated" in _boss:
		_boss.set("gated", false)

	# set_deferred: this can be reached from a signal emitted inside physics,
	# and changing a collision shape mid-step is the classic way to get
	# "Can't change this state while flushing queries".
	if bars != null:
		for child in bars.get_children():
			if child is CollisionShape2D:
				child.set_deferred("disabled", true)

	if _panes().is_empty():
		queue_free()
		return

	# BOTH HALVES SHATTER TOGETHER, on one tween rather than two. Two tweens
	# of the same length still drift by a frame, and a box whose back outlives
	# its front looks like a bug rather than like ice breaking.
	# A NAMED METHOD, NOT A MULTI-LINE LAMBDA. GDScript accepts multi-line
	# lambdas, but one whose body ends mid-argument-list - a for loop followed
	# by the tween's remaining arguments - is exactly the shape that parses
	# differently than it reads. This cannot be misread.
	var tween := create_tween()
	tween.tween_method(_set_dissolve, 0.0, 1.0, open_seconds)
	tween.tween_callback(queue_free)


func _set_dissolve(value: float) -> void:
	for material in _panes():
		material.set_shader_parameter("dissolve", value)


func shut() -> void:
	# For a reset: the arena wipes and the gauntlet starts again. Not called
	# today - the gate frees itself on open and the arena reloads - but the
	# flag half is here so a future reset does not have to reach into
	# BaseEnemy from somewhere else.
	_open = false
	if _boss != null and "gated" in _boss:
		_boss.set("gated", true)


# =============================================================================
# ON THE MAP
# =============================================================================
# mapscreen.gd draws a pin for everything in "map_landmarks" and asks each one
# what it is. Joined in _init rather than _ready so it does not depend on this
# script having a _ready, or on anything a _ready returns early for - and so
# the pin exists from the moment the node does.

func _init() -> void:
	add_to_group("map_landmarks")

func map_landmark() -> Dictionary:
	# In the gate's own element colour - six gates in one room are six
	# identical diamonds otherwise, and which one is which is the question.
	return {
		"kind": "boss",
		"label": Element.name_for(element).capitalize() + " boss",
		"colour": Element.colour_for(element),
	}
