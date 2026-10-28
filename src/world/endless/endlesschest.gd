# endlesschest.gd - the Endless's chest, in the corridor beside the ladder up
# (0.93.4). Made by endlessrun.gd at its chest_spot.
#
# The owner, 28 Oct: "the goal is to acquire gold so every elite and boss has
# chance for drops from the table", and earlier "if player dies they can walk to
# the chest and collect". A bag on the arena floor would be lost to anybody who
# falls (the door is one way) and to everybody when the arena empties, so each
# elite and boss a run's player kills pays into this character's chest instead:
# BaseEnemy._die() -> Combat.report_endless_kill() -> POST /api/minigames/kill,
# which rolls the monster's own loot (no XP, the owner's "Loot only") into the
# server's chest. It is kept there until it is taken or the account's next Go.
#
# THIS NODE IS A PICTURE OF THE SERVER'S CHEST, as a loot bag's node is of its
# bag: walk up and press interact, and it asks GET /api/loot/chest and opens
# the loot window on what came back (hud.open_lootbag(self, player)), which
# takes each cell through /api/loot/take by the chest's id. So it answers the
# loot window as a bag does - get_bag_id(), get_contents(), set_contents(),
# notify_panel_closed(), despawn_now() (here: the lid shuts; a chest stays),
# player_left_range - plus panel_cells, panel_columns and panel_title, which
# size and name the window. Press interact again and it is Take all, as on a
# bag (0.93.3).
#
# The picture is the bank chest's own (scene/interactables/bankchest.tscn, his
# art): its frames are borrowed, nothing new is drawn. Over it, how many cells
# hold something (`count_label`), from the chest's answer and from each kill's.
#
# Built in code, no class_name, so a fresh checkout needs no editor rescan.
extends Area2D

signal player_left_range()

const BANK_CHEST := "res://scene/interactables/bankchest.tscn"
const GAME := "endless"
const CHEST_CELLS := 36
const CHEST_COLUMNS := 6
const TITLE := "Your chest"
# How long after the area loads the key is ignored (the bank chest's reason: a
# key still held from the last scene).
const SPAWN_GRACE := 0.4
const READ_TIMEOUT := 4.0

# The loot window reads these (lootbaginventory.gd open_for_bag()).
var panel_cells: int = CHEST_CELLS
var panel_columns: int = CHEST_COLUMNS
var panel_title: String = TITLE

# SEAMS FOR THE SUITE. In the game: GET /api/loot/chest for this character.
var chest_request: Callable = Callable()
var slot_now: Callable = Callable()

var anim: AnimatedSprite2D = null
var count_label: Label = null
var player_nearby: Node = null
var is_open: bool = false
# How many cells hold something, as the server last said.
var used: int = 0

var _bag_id: String = ""
var _contents: Array = []
var _grace: float = SPAWN_GRACE
var _asking: bool = false


func _ready() -> void:
	y_sort_enabled = true
	collision_layer = 16
	collision_mask = 6
	var reach := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 42.0
	reach.shape = circle
	reach.position = Vector2(1, 3)
	add_child(reach)
	var body := StaticBody2D.new()
	var block := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(17, 10)
	block.shape = box
	block.position = Vector2(0.5, 3)
	body.add_child(block)
	add_child(body)
	anim = AnimatedSprite2D.new()
	anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	anim.position = Vector2(0, 4)
	anim.offset = Vector2(0, -8)
	anim.speed_scale = 0.75
	anim.sprite_frames = _bank_frames()
	add_child(anim)
	if anim.sprite_frames != null and anim.sprite_frames.has_animation(&"idle"):
		anim.play(&"idle")
	anim.animation_finished.connect(_on_animation_finished)
	count_label = Label.new()
	count_label.add_theme_font_size_override("font_size", 9)
	count_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	count_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	count_label.add_theme_constant_override("outline_size", 3)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.size = Vector2(60, 12)
	count_label.position = Vector2(-30, -30)
	count_label.z_index = 2
	count_label.visible = false
	add_child(count_label)
	add_to_group(&"endless_chest")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# What earlier kills left in it, said over the lid from the start.
	_read.call_deferred(false)


static func _bank_frames() -> SpriteFrames:
	"""The bank chest's own frames - idle, open, closed - borrowed from its
	scene, so the Endless's chest is the same picture."""
	var packed: PackedScene = load(BANK_CHEST) as PackedScene
	if packed == null:
		return null
	var chest: Node = packed.instantiate()
	var sprite: AnimatedSprite2D = chest.get_node_or_null("animatedsprite2d") as AnimatedSprite2D
	var frames: SpriteFrames = sprite.sprite_frames if sprite != null else null
	chest.free()
	return frames


func _process(delta: float) -> void:
	if _grace > 0.0:
		_grace -= delta
		return
	if player_nearby == null or _asking:
		return
	if not Input.is_action_just_pressed("interact"):
		return
	press()


func press() -> void:
	"""The interact key: open it, or, open, Take all (0.93.3's rule)."""
	if is_open:
		var panel: Node = _panel()
		if panel != null and panel.has_method("showing") and bool(panel.call("showing", self)):
			panel.call("take_all")
		return
	_read(true)


# =============================================================================
# THE SERVER'S CHEST
# =============================================================================

func _slot() -> int:
	return int(slot_now.call()) if slot_now.is_valid() else CharacterData.active_character_index


func _read(then_open: bool) -> void:
	"""Ask the server what is in the chest; open the window on it if asked."""
	if _asking:
		return
	_asking = true
	if then_open:
		_open_lid()
	var res: Dictionary
	if chest_request.is_valid():
		res = await chest_request.call(GAME, _slot())
	else:
		res = await Api.get_json("/api/loot/chest?game=%s&slot=%d" % [GAME, _slot()], READ_TIMEOUT)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_asking = false
	if not res.get("ok", false):
		if then_open:
			_shut_lid()
			_say("The chest would not open - try again.")
		return
	adopt(res.get("data", {}) if res.get("data") is Dictionary else {})
	if not then_open:
		return
	if used == 0:
		_shut_lid()
		_say("Your chest is empty - the elites and bosses you slay pay into it.")
		return
	var hud: Node = get_tree().get_first_node_in_group("hud")
	var who: Node = player_nearby if is_instance_valid(player_nearby) else null
	if hud == null or not hud.has_method("open_lootbag") or who == null:
		_shut_lid()
		return
	hud.call("open_lootbag", self, who)


func adopt(answer: Dictionary) -> void:
	"""The server's answer for the chest: its id, size and cells, laid out by
	position (null where a cell is empty), as the loot window takes them."""
	_bag_id = str(answer.get("bag_id", ""))
	panel_cells = maxi(1, int(answer.get("cells", CHEST_CELLS)))
	panel_columns = maxi(1, int(answer.get("columns", CHEST_COLUMNS)))
	var cells: Array = []
	cells.resize(panel_cells)
	var held: int = 0
	for entry in answer.get("contents", []):
		if not (entry is Dictionary):
			continue
		var at: int = int(entry.get("position", -1))
		if at < 0 or at >= panel_cells:
			continue
		cells[at] = {"item_id": str(entry.get("item_id", "")), "quantity": maxi(1, int(entry.get("quantity", 1)))}
		held += 1
	_contents = cells
	note_used(held)


func note_win(data: Dictionary) -> void:
	"""A kill's answer (Combat.report_endless_kill()): how many cells hold
	something now."""
	note_used(int(data.get("used", used)))


func note_used(cells: int) -> void:
	used = maxi(0, cells)
	if count_label != null:
		count_label.text = "×%d" % used
		count_label.visible = used > 0


func cells_text() -> String:
	return count_label.text if count_label != null and count_label.visible else ""


func _say(message: String) -> void:
	var who: Node = player_nearby if is_instance_valid(player_nearby) else null
	if who != null and who.has_method("show_notice"):
		who.call("show_notice", message)


func _panel() -> Node:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	return hud.get("lootbag_panel") if hud != null and "lootbag_panel" in hud else null


# =============================================================================
# WHAT THE LOOT WINDOW ASKS OF A BAG
# =============================================================================

func get_bag_id() -> String:
	return _bag_id


func get_contents() -> Array:
	return _contents


func set_contents(contents: Array) -> void:
	"""The window's picture of what is left, written back on a take."""
	_contents = contents
	var held: int = 0
	for entry in contents:
		if entry is Dictionary and str(entry.get("item_id", "")) != "":
			held += 1
	note_used(held)


func notify_panel_closed() -> void:
	_shut_lid()


func despawn_now() -> void:
	"""The window calls this on a bag it emptied. A chest stays: its lid shuts."""
	note_used(0)
	_shut_lid()


# =============================================================================
# THE LID
# =============================================================================

func _open_lid() -> void:
	is_open = true
	if anim != null and anim.sprite_frames != null and anim.sprite_frames.has_animation(&"open"):
		anim.play(&"open")
	Audio.play("bank_open")


func _shut_lid() -> void:
	is_open = false
	if anim != null and anim.sprite_frames != null and anim.sprite_frames.has_animation(&"closed"):
		anim.play(&"closed")


func _on_animation_finished() -> void:
	# Held on the last frame of "open" while the window is up, as the bank's is.
	if anim.animation == &"open" and is_open:
		anim.frame = anim.sprite_frames.get_frame_count(&"open") - 1


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_nearby = body


func _on_body_exited(body: Node) -> void:
	if body != player_nearby:
		return
	player_nearby = null
	if is_open:
		player_left_range.emit()
		var panel: Node = _panel()
		if panel == null or not panel.has_method("showing") or not bool(panel.call("showing", self)):
			_shut_lid()
