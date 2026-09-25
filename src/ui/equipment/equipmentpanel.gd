# equipmentpanel.gd — the paper doll: eight squares showing what this
# character is wearing, and a summary of what that is worth.
# attached to res://scene/ui/equipment/equipmentpanel.tscn.
#
# Opens and closes with the backpack, immediately to its left, so gear can be
# dragged straight across. Same arrangement the bank already uses, for the same
# reason: a drag needs both ends visible.
#
# =============================================================================
# THIS PANEL IS A VIEW, NOT A STORE
# =============================================================================
# The truth is player.equipped — {slot_name: item_id} — and the rule is that a
# slot points at a bag item rather than holding one. Nothing here caches that.
# Every square is repainted from player.equipped after every change, so there
# is no second copy to fall out of step with the save, the server, or with
# CharacterData's pruning when you sell the sword you were holding.
#
# WHAT HAPPENS ON A DROP, in order, because the order is the whole design:
#
#   1. the slot asks the player whether it fits            (courtesy)
#   2. this panel asks again and writes player.equipped    (the local truth)
#   3. CharacterData saves, prunes against the real bag    (reconciliation)
#   4. ServerStorage pushes saves.equipment                (the rule)
#   5. every square repaints from player.equipped          (the view)
#
# Step 3 is why the panel repaints from the player AFTER saving rather than
# from what it just wrote: the prune can legitimately refuse a piece — you
# dropped it, or it was sold from the bank in another window — and the squares
# should show what survived, not what was attempted.
extends Control
class_name EquipmentPanel


# =============================================================================
# SIGNALS
# =============================================================================

signal closed


# =============================================================================
# CONSTANTS
# =============================================================================

# HOW TALL THE CHARACTER IS DRAWN IN THE WELL, in pixels, whatever the source
# art measures. The classes are not one size - warrior, mage and healer are
# 64x64 frames and the tank is 128x128 - so a fixed scale would draw the tank
# at twice everyone else and burst out of the box. The scale is worked out from
# the frame instead, which also means new art of any size just fits.
const PREVIEW_HEIGHT := 150.0

# Matches the in-world speed_scale on every class's animatedsprite2d, so the
# walk in the panel has the same cadence as the walk on the map.
const PREVIEW_SPEED_SCALE := 1.5

# WALKING, NOT STANDING, and this is the whole point of the well: an idle
# frame is a picture, and what a player wants to see when they put new boots on
# is their character moving in them. idledown is the fallback for art that has
# no walk cycle rather than the preference.
const PREVIEW_ANIMATIONS := ["walkdown", "idledown"]

const COLOUR_NEUTRAL := Color(0.8, 0.75, 0.65)
const COLOUR_GOOD    := Color(0.55, 0.85, 0.5)


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var close_button:  Button  = get_node_or_null("%equipclosebutton")
@onready var damage_label:  Label   = get_node_or_null("%equipdamagevalue")
@onready var speed_label:   Label   = get_node_or_null("%equipspeedvalue")
@onready var armour_label:  Label   = get_node_or_null("%equiparmourvalue")
@onready var soak_label:    Label   = get_node_or_null("%equipsoakvalue")

# THE LIVING DOLL. An AnimatedSprite2D in the middle of the squares, walking on
# the spot, so the panel shows who is wearing all this rather than a grid of
# icons belonging to nobody.
@onready var preview:      AnimatedSprite2D = get_node_or_null("%equippreview")
@onready var preview_box:  Control = get_node_or_null("%equippreviewbox")
@onready var preview_hint: Label   = get_node_or_null("%equippreviewhint")


# =============================================================================
# STATE
# =============================================================================

var player: Node = null

# slot_name -> EquipmentSlot, built once in _ready() by walking the tree rather
# than by eight @onready lines. A slot added to the doll is then one node in
# the scene and nothing here.
var _slots: Dictionary = {}


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Found by group, the same way the tooltip is, so the backpack can ask the
	# doll to repaint after a right-click without either knowing where the
	# other is parented.
	add_to_group("equipmentpanel")

	_collect_slots()
	_verify_slots()

	if close_button != null and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)

	if preview != null:
		preview.speed_scale = PREVIEW_SPEED_SCALE
	if preview_box != null and not preview_box.resized.is_connected(_centre_preview):
		# THE BOX HAS NO SIZE YET. Containers lay out after _ready(), so
		# centring the sprite now would centre it in a zero-sized rectangle and
		# leave it in the corner. This fires when the real size arrives, and
		# again if the panel is ever resized.
		preview_box.resized.connect(_centre_preview)

	visible = false


func _collect_slots() -> void:
	_slots.clear()
	for node in _descendants(self):
		if not (node is EquipmentSlot):
			continue
		var slot: EquipmentSlot = node
		if slot.equip_slot_name == "":
			push_error("EquipmentPanel: a slot in the scene has no equip_slot_name")
			continue
		_slots[slot.equip_slot_name] = slot

		if not slot.equip_requested.is_connected(_on_equip_requested):
			slot.equip_requested.connect(_on_equip_requested)
		# RIGHT-CLICK TAKES IT OFF. Not a drag out, which would imply the
		# piece is being moved somewhere — it never left the backpack, so
		# there is nowhere for it to land. The inherited signal is enough;
		# InventorySlot._gui_input() already sets the flag that stops the
		# click also swinging the character's weapon.
		if not slot.slot_right_clicked.is_connected(_on_slot_right_clicked):
			slot.slot_right_clicked.connect(_on_slot_right_clicked)


func _descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in node.get_children():
		out.append(child)
		out.append_array(_descendants(child))
	return out


func _verify_slots() -> void:
	# THE DOLL AND THE ENUM HAVE TO NAME THE SAME EIGHT THINGS, and this is the
	# check that says so out loud rather than leaving a square that silently
	# accepts nothing.
	#
	# It is the third time this project has needed a check of exactly this
	# shape. app.py held a hand-typed slot list with a "robe" the enum never
	# had and no "boots", which it does — nothing errored, and every pair of
	# boots in the game would have been refused. A panel with a square named
	# "gloves" would fail the same silent way: the square would be there, it
	# would just never light up.
	var real: Array = ItemData.slot_names()

	for slot_name in _slots:
		if not real.has(slot_name):
			push_error("EquipmentPanel: the doll has a '%s' square, which ItemData.EquipSlot does not define. Nothing can ever go in it." % slot_name)

	for slot_name in real:
		if not _slots.has(slot_name):
			push_warning("EquipmentPanel: ItemData.EquipSlot defines '%s' and the doll has no square for it — that gear can never be worn." % slot_name)


# =============================================================================
# PUBLIC API
# =============================================================================

func set_player(p: Node) -> void:
	player = p
	for slot_name in _slots:
		(_slots[slot_name] as EquipmentSlot).set_player(p)
	refresh()


func show_panel() -> void:
	visible = true
	refresh()


func hide_panel() -> void:
	visible = false


func refresh() -> void:
	# REPAINTED WHOLE, EVERY TIME. Eight squares and a four-line summary is
	# nothing to rebuild, and a partial update is how a panel ends up showing a
	# piece that the save refused or the prune took back off.
	for slot_name in _slots:
		var slot: EquipmentSlot = _slots[slot_name]
		slot.set_stack(_stack_for(slot_name))

	_refresh_summary()
	_refresh_preview()


# =============================================================================
# THE CHARACTER IN THE MIDDLE
# =============================================================================

func _refresh_preview() -> void:
	# THE ART COMES OFF THE LIVE PLAYER, not from a class-id lookup. The panel
	# already holds the character node, and that node IS its class with its own
	# SpriteFrames hanging off it - so there is no fifth copy of the slot ->
	# scene table to keep in step, and switching character repaints this for
	# free because characterhud.gd calls set_player() again.
	if preview == null:
		return

	var body: AnimatedSprite2D = null
	if player != null:
		body = player.get_node_or_null("animatedsprite2d") as AnimatedSprite2D

	if body == null or body.sprite_frames == null:
		_show_preview(false)
		return

	var frames: SpriteFrames = body.sprite_frames
	var wanted: String = ""
	for candidate in PREVIEW_ANIMATIONS:
		if frames.has_animation(candidate):
			wanted = candidate
			break
	if wanted == "":
		# Art with neither a walk nor an idle facing the camera. Nothing to
		# draw, and an empty well says so rather than showing a stuck frame.
		_show_preview(false)
		return

	# SHARED, NOT COPIED. SpriteFrames is a Resource and assigning it points
	# this sprite at the same one the character is using; duplicating it would
	# hold a second copy of every frame of every animation in memory for a
	# panel that is shut most of the time.
	if preview.sprite_frames != frames:
		preview.sprite_frames = frames

	_show_preview(true)
	_fit_preview(frames, wanted)

	# PLAYED EXPLICITLY EVERY TIME. The panel is built once and then shown and
	# hidden, so autoplay would only ever start it on the first open.
	if preview.animation != StringName(wanted) or not preview.is_playing():
		preview.play(wanted)


func _show_preview(on: bool) -> void:
	if preview != null:
		preview.visible = on
	if preview_hint != null:
		preview_hint.visible = not on


func _fit_preview(frames: SpriteFrames, anim: String) -> void:
	var frame_height: float = 64.0
	if frames.get_frame_count(anim) > 0:
		var texture: Texture2D = frames.get_frame_texture(anim, 0)
		if texture != null and texture.get_height() > 0:
			frame_height = float(texture.get_height())

	var factor: float = PREVIEW_HEIGHT / frame_height
	preview.scale = Vector2(factor, factor)
	_centre_preview()


func _centre_preview() -> void:
	if preview == null or preview_box == null:
		return
	# The sprite is centred on its own origin, so putting that origin in the
	# middle of the box is the whole of the centring.
	preview.position = preview_box.size * 0.5


# =============================================================================
# THE SQUARES
# =============================================================================

func _stack_for(slot_name: String) -> ItemStack:
	# A DISPLAY STACK OF ONE, built fresh, never the player's own. The real
	# stack is in the backpack with whatever quantity it has; this is a picture
	# of the item, and handing the square a reference to the bag's stack would
	# make the equipment panel able to edit the bag by accident.
	if player == null or not ("equipped" in player):
		return null

	var item_id: String = str(player.equipped.get(slot_name, ""))
	if item_id == "":
		return null

	var data: ItemData = ItemRegistry.get_item(item_id)
	if data == null:
		# Not an error worth shouting about, but it no longer clears itself.
		# prune_equipment() used to drop an id the registry had never heard of
		# on the next save; it is gone, because equipment is a location now
		# rather than a pointer into the bag. An unknown id here means the
		# catalogue and the save disagree - the square draws empty and the
		# server still believes the slot is filled.
		#
		# Reachable only by removing an item from the catalogue that someone is
		# wearing, which is a migration problem rather than a runtime one.
		return null

	return ItemStack.new(data, 1)


# =============================================================================
# THE SUMMARY
# =============================================================================

func _refresh_summary() -> void:
	if player == null:
		return

	# WHAT YOU ACTUALLY HIT FOR, asked of the character rather than assembled
	# here. attack_damage_range() does the same arithmetic the class does at
	# the moment it swings, so these two numbers are the two a player will see
	# pop off an enemy — not an estimate that drifts when a class is tuned.
	if damage_label != null and player.has_method("attack_damage_range"):
		var band: Vector2i = player.attack_damage_range()
		damage_label.text = "%d - %d" % [band.x, band.y]

	if speed_label != null and player.has_method("attack_damage_range") \
			and player.has_method("attack_period"):
		var band2: Vector2i = player.attack_damage_range()
		var period: float = float(player.attack_period())
		if period > 0.0:
			var middle: float = float(band2.x + band2.y) * 0.5
			speed_label.text = "%d" % roundi(middle / period)
		else:
			speed_label.text = "-"

	if armour_label != null and player.has_method("equipped_armor_value"):
		armour_label.text = str(player.equipped_armor_value())

	if soak_label != null and player.has_method("equipped_armor_value"):
		# THE NUMBER THAT MEANS SOMETHING. "Armour 28" answers nothing on its
		# own — it is only a position on a ladder nobody has seen. The
		# percentage is what the player feels, and it is the one armour
		# actually applies in take_damage().
		var reduction: float = PlayerStats.armour_reduction(player.equipped_armor_value())
		soak_label.text = "%d%% less" % roundi(reduction * 100.0)
		soak_label.add_theme_color_override("font_color",
			COLOUR_GOOD if reduction > 0.0 else COLOUR_NEUTRAL)


# =============================================================================
# EQUIP AND UNEQUIP
# =============================================================================

func _on_equip_requested(_slot_name: String, item_id: String) -> void:
	# The square's name is ignored on purpose: player.equip() derives the slot
	# from the item, so there is nothing for the two to disagree about. The
	# square already refused anything that does not belong in it.
	await equip(item_id)


func equip(item_id: String) -> bool:
	# THE RULE IS NOT HERE. CharacterData.equip_item() asks the player whether
	# the piece may be worn and saves if it may — because the backpack's
	# right-click does the same thing, and a UI panel owning the only copy of
	# "equip, then save" would mean the other gesture had to duplicate it.
	#
	# What is left here is the view: repaint, from the player, afterwards.
	# await: equip_item() is a server round trip now. Repainting before the
	# answer lands would draw a character wearing something the server may be
	# about to refuse.
	if not await CharacterData.equip_item(player, item_id):
		return false
	refresh()
	return true


func _on_slot_right_clicked(slot: InventorySlot) -> void:
	var square: EquipmentSlot = slot as EquipmentSlot
	if square == null or player == null or not player.has_method("unequip"):
		return
	if square.is_empty():
		return

	# REPAINTED FROM THE PLAYER AFTER THE SERVER ANSWERS, not from what was
	# requested. The square should show what the server did: an unequip into a
	# full bag is refused with a 409 and the piece stays on, which is a
	# different picture from the one the click asked for.
	await CharacterData.unequip_slot(player, square.equip_slot_name)
	refresh()


# =============================================================================
# CLOSING
# =============================================================================

func _on_close_pressed() -> void:
	hide_panel()
	closed.emit()
