# inventoryslot.gd — a single inventory slot. displays one ItemStack (icon +
# quantity), handles hover highlighting, tooltips, right-click use, double-click
# quick-transfer, and drag-and-drop between slots.
#
# slot_type distinguishes contexts ("inventory", "hotbar", "bank", "lootbag")
# so behavior and drag rules can vary. drag-and-drop is container-agnostic:
# any slot can drop onto any other slot, which is what lets items move freely
# between inventory, bank, hotbar, and loot bags.
#
# visual state: two styleboxes, normal and hover.
#
# drop cases:
# - CASE T: the drag crosses between the bank and the carry → a request
# - CASE B1: target empty → move stack from source to here
# - CASE B2: target matches → merge stacks with overflow to source
# - CASE B3: target differs → swap stacks
#
# A HOTBAR KEY IS ONE OF THESE, with no special case. It holds a real stack,
# so a drag between the bag and a key moves, merges or swaps exactly like a
# drag between two bag cells. There used to be a CASE A here for a key that
# only pointed at a bag item, and a gold "linked" face for the bag cell it
# pointed at; both went when the keys started holding items.
extends PanelContainer
class_name InventorySlot


# =============================================================================
# SIGNALS
# =============================================================================

signal slot_clicked(slot: InventorySlot)
signal slot_right_clicked(slot: InventorySlot)
signal slot_changed(slot: InventorySlot)
signal slot_double_clicked(slot: InventorySlot)

# A DROP THIS SLOT REFUSES TO PERFORM ITSELF.
#
# Emitted instead of moving anything when a drag crosses between the bank and
# the backpack. Relayed by InventoryContainer and answered by bankinventory.gd,
# which turns it into one POST /api/bank/items. See _drop_data().
signal transfer_requested(source_slot: InventorySlot, target_slot: InventorySlot)


# =============================================================================
# CONSTANTS
# =============================================================================

# on-screen size of the icon that follows the pointer during a drag.
# see make_drag_preview() — it is centred on the pointer, so this is also
# what decides how far the icon is offset from it.
const DRAG_PREVIEW_SIZE := Vector2(40, 40)


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

@export var slot_type: String = "inventory"

# The one slot_type the drag handlers actually branch on. Loot slots render a
# bag the SERVER owns, so nothing may be dragged out of one or into one — see
# _get_drag_data() and _can_drop_data() below. Set at runtime by
# lootbaginventory.gd via InventoryContainer.set_slot_type(), not in the scene,
# because the slots are instantiated by the container.
const LOOT_SLOT_TYPE := "lootbag"

# The other slot_type the drag handlers branch on. A bank grid is server-owned
# the same way a loot bag is, but the rule is softer: rearranging WITHIN the
# bank is layout and stays local, while anything crossing between the bank and
# the backpack is a transfer and has to be a request. Set at runtime by
# bankinventory.gd via InventoryContainer.set_slot_type().
const BANK_SLOT_TYPE := "bank"


# =============================================================================
# STATE
# =============================================================================

var stack: ItemStack = null
var slot_index: int = -1

# THE CONTAINER THIS CELL BELONGS TO, which is not always its parent. A bag
# cell's parent is its grid; a hotbar key's parent is the hotbar's row, while
# the cell it IS belongs to the player's backpack (see InventoryContainer's
# "CELLS PAST THE GRID"). Anything that needs "the container that saves this
# cell" - the trash, above all - asks this rather than get_parent().
var home_container: Node = null

var is_hovered: bool = false

# StyleBox, NOT StyleBoxFlat. A slot's face is whatever the theme hands over,
# and since the hotbar's is a piece of the artist's tile art it is a
# StyleBoxTexture - which is not a StyleBoxFlat and never will be. Typed
# narrowly, `style is StyleBoxTexture` is not a check that fails at runtime,
# it is one Godot refuses to compile: "Expression is of type StyleBoxFlat so
# it can't be of type StyleBoxTexture."
var style_normal: StyleBox = null
var style_hover:  StyleBox = null


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var icon_rect: TextureRect = $centercontainer/icon
@onready var quantity_label: Label = $quantitylabel

# The coloured border a rare item draws round its slot. Built in code rather
# than in inventoryslot.tscn so every slot that inherits this script - bank,
# loot bag, shop, hotbar - gets it without a scene edit each.
var _rarity_frame: Panel = null
var _rarity_box: StyleBoxFlat = null


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_build_styles()
	_build_rarity_frame()
	_update_style()
	refresh_display()

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


# =============================================================================
# STYLE
# =============================================================================

# A SLOT'S TWO FACES - resting and hovered - are both DERIVED from whatever
# stylebox the theme hands over, never written out here.
# That is what lets one slot be a flat panel drawn by the theme and another be
# a piece of the artist's own tile art, with no code between them knowing
# which.
#
# HOW A STATE IS SHOWN DEPENDS ON WHAT THE STYLE IS. A flat box has a bg and a
# border to change; a texture has neither - it has art that must not be
# repainted, so it is TINTED instead. Same two states, same meaning, two ways
# of saying it.
func _build_rarity_frame() -> void:
	# A BORDER, NOT A FILL. The slot's face is the artist's socket art, and the
	# icon sits in it; a tinted background would repaint the one and fight the
	# other. Drawn under the stack count, so the number stays readable.
	if _rarity_frame != null:
		return
	_rarity_box = StyleBoxFlat.new()
	_rarity_box.draw_center = false
	_rarity_box.set_border_width_all(2)
	_rarity_box.set_corner_radius_all(3)
	_rarity_frame = Panel.new()
	_rarity_frame.name = "rarityframe"
	_rarity_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rarity_frame.visible = false
	_rarity_frame.add_theme_stylebox_override("panel", _rarity_box)
	add_child(_rarity_frame)
	if quantity_label != null:
		move_child(_rarity_frame, quantity_label.get_index())


func _paint_rarity() -> void:
	if _rarity_frame == null:
		return
	var tier: int = 0 if is_empty() else int(stack.data.tier)
	var framed: bool = tier >= GameConstants.RARITY_FRAME_MIN_TIER
	_rarity_frame.visible = framed
	if framed:
		_rarity_box.border_color = GameConstants.rarity_colour(tier)


func _build_styles() -> void:
	var base: StyleBox = get_theme_stylebox("panel")

	# THE COPIES ARE HELD IN LOCALS OF THE EXACT TYPE, not written straight
	# onto the members. bg_color exists on a StyleBoxFlat and modulate_color on
	# a StyleBoxTexture, and reaching for either through a variable typed as
	# the base StyleBox is a compile error, not a runtime one.
	if base is StyleBoxFlat:
		var flat: StyleBoxFlat = base as StyleBoxFlat
		var flat_hover: StyleBoxFlat = flat.duplicate() as StyleBoxFlat
		flat_hover.bg_color = flat.bg_color.lightened(0.15)

		style_normal = flat.duplicate() as StyleBoxFlat
		style_hover = flat_hover
	elif base is StyleBoxTexture:
		# THE ART IS THE SLOT. Lightening it for a hover keeps the artist's
		# outline, highlight and corners exactly as drawn - a border colour
		# would have nothing to colour.
		var art: StyleBoxTexture = base as StyleBoxTexture
		var art_hover: StyleBoxTexture = art.duplicate() as StyleBoxTexture
		art_hover.modulate_color = Color(1.22, 1.20, 1.10, 1.0)

		style_normal = art.duplicate() as StyleBoxTexture
		style_hover = art_hover
	else:
		style_normal = StyleBoxFlat.new()
		style_hover = StyleBoxFlat.new()


func _update_style() -> void:
	if style_normal == null or style_hover == null:
		return

	# THERE WAS AN `is_selected` HALF TO THIS and nothing ever set it true, in
	# this class or in HotbarSlot which inherits it - so the slot had a designed
	# "selected" look that no input could reach. Removed rather than documented,
	# because a state that renders is a state a reader assumes works.
	if is_hovered:
		add_theme_stylebox_override("panel", style_hover)
	else:
		add_theme_stylebox_override("panel", style_normal)


# =============================================================================
# STACK MANAGEMENT
# =============================================================================

func set_stack(new_stack: ItemStack) -> void:
	stack = new_stack
	refresh_display()


func clear_stack() -> void:
	stack = null
	refresh_display()


func is_empty() -> bool:
	return stack == null or not stack.is_valid()


func refresh_display() -> void:
	if not is_node_ready():
		return

	if is_empty():
		icon_rect.texture = null
		# Reset with the texture. modulate belongs to the NODE, not the texture,
		# so a tinted item leaving a slot would otherwise leave its colour
		# behind on whatever lands there next.
		icon_rect.modulate = Color.WHITE
		quantity_label.text = ""
		_paint_rarity()
		_update_style()
		return

	icon_rect.texture = stack.data.icon
	icon_rect.modulate = stack.data.icon_tint
	if stack.quantity > 1:
		quantity_label.text = str(stack.quantity)
	else:
		quantity_label.text = ""

	_paint_rarity()
	_update_style()


# =============================================================================
# INPUT — LEFT CLICK (select) + RIGHT CLICK (use) + DOUBLE CLICK (quick transfer)
# =============================================================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.double_click and not is_empty():
				slot_double_clicked.emit(self)
			else:
				slot_clicked.emit(self)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Tell the player this click belongs to the UI.
			#
			# accept_event() below stops the event propagating through the
			# scene tree, but the character classes read the mouse with
			# Input.is_mouse_button_pressed(), which asks the HARDWARE and
			# knows nothing about what a Control consumed. So right-clicking
			# a potion to drink it also swung your weapon. This marks the
			# click as spoken for; player.gd clears it when the button is
			# released. See GameState for why the flag lives on the autoload.
			GameState.ui_absorbed_right_click = true
			slot_right_clicked.emit(self)
			accept_event()


# =============================================================================
# HOVER + TOOLTIP
# =============================================================================

func _on_mouse_entered() -> void:
	is_hovered = true
	_update_style()
	_show_tooltip()


func _on_mouse_exited() -> void:
	is_hovered = false
	_update_style()
	_hide_tooltip()


func _show_tooltip() -> void:
	if is_empty():
		return
	var tooltip: Node = get_tree().get_first_node_in_group("itemtooltip")
	if tooltip == null:
		return
	if tooltip.has_method("show_for_stack"):
		tooltip.show_for_stack(stack, self)


func _hide_tooltip() -> void:
	var tooltip: Node = get_tree().get_first_node_in_group("itemtooltip")
	if tooltip == null:
		return
	if tooltip.has_method("hide_tooltip"):
		tooltip.hide_tooltip()


# =============================================================================
# DRAG AND DROP — SOURCE
# =============================================================================

func make_drag_preview(texture: Texture2D, tint: Color = Color.WHITE) -> Control:
	# Builds the icon that follows the pointer during a drag. Every kind of
	# slot drags through this one - HotbarSlot used to keep a separate copy,
	# and the two drifted apart.
	#
	# CENTRED ON THE POINTER, WHICH IT PREVIOUSLY WAS NOT.
	#
	# set_drag_preview() puts the preview's TOP-LEFT CORNER at the mouse, so
	# the icon hung down and to the right of the real drop point by its full
	# size. You were aiming with the middle of the icon while the drop was
	# being tested ~20px up and left of that — which reads as "the item won't
	# go in the slot" when the slot is only 32px across. It went unnoticed
	# while the system cursor was drawn, because the arrow showed the true
	# point; hiding the cursor during drags removed that reference and left
	# only the icon, which was lying about where the pointer was.
	#
	# A zero-sized wrapper sits exactly on the pointer, and the icon inside is
	# offset by half its size, so what you see centred under your hand IS the
	# point being tested.
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# DRAW ABOVE EVERY PANEL. set_drag_preview() parents the preview to the
	# control it is called on, so the icon lives inside whichever panel you
	# picked it up from and any panel drawn after that one covers it — that's
	# what sent the icon behind the bank window on the way over.
	#
	# Every panel is in the same CanvasLayer (characterhud, layer 0), so
	# z_index settles it, and it has to be ABSOLUTE: z_index is added to the
	# parent's by default, which would only offset it from whatever the source
	# panel is at. 4096 is the engine maximum. The child inherits this
	# ordering, so setting it on the wrapper covers both.
	root.z_as_relative = false
	root.z_index = 4096

	var icon := TextureRect.new()
	icon.texture = texture
	# The item's own tint (ItemData.icon_tint), so a recoloured item does not
	# turn back into its base colour the moment it is picked up.
	icon.modulate = tint
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size = DRAG_PREVIEW_SIZE
	icon.position = -DRAG_PREVIEW_SIZE * 0.5
	root.add_child(icon)

	return root


func _get_drag_data(_at_position: Vector2) -> Variant:
	if is_empty():
		return null

	# A LOOT BAG BELONGS TO THE SERVER, AND A DRAG IS NOT A REQUEST.
	#
	# Dragging moves a stack between containers synchronously, here, with
	# nothing told to anyone. That was fine while the client owned the bag. Now
	# that /api/loot/take decides what leaves one, a drag out would be a
	# duplication bug in two clicks: drag the potion into the backpack, then
	# double-click the cell it came from and be handed it a second time, because
	# the server still has the row.
	#
	# lootbaginventory.gd marks its slots "lootbag" in open_for_bag(). Double-
	# click is how items leave a bag.
	if slot_type == LOOT_SLOT_TYPE:
		return null

	_hide_tooltip()

	set_drag_preview(make_drag_preview(icon_rect.texture, icon_rect.modulate))

	return {
		"stack":       stack.duplicate_stack(),
		"source_slot": self,
		"source_type": slot_type,
	}


# =============================================================================
# DRAG AND DROP — TARGET
# =============================================================================

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	# And nothing goes INTO a loot bag either. There is no endpoint for it, so
	# anything dropped in would sit in a grid the server does not know about and
	# be gone the moment the panel closed — which looks exactly like the game
	# eating an item.
	if slot_type == LOOT_SLOT_TYPE:
		return false

	return typeof(data) == TYPE_DICTIONARY \
		and data.has("stack") \
		and data.has("source_slot")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var incoming:    ItemStack     = data["stack"]
	var source_slot: InventorySlot = data["source_slot"]

	if source_slot == self:
		return

	# CASE T — THE DRAG CROSSES BETWEEN THE BANK AND THE BACKPACK.
	#
	# Same principle as the loot bag rule in _get_drag_data(): a drag is not a
	# request, and the server owns both of these grids. Moving the stack here
	# and letting each container save its own array afterwards is two
	# independent whole-array writes that the server cannot tell are two halves
	# of one transfer - two arrays that do not add up look exactly like two that
	# do. So nothing moves locally; bankinventory.gd turns this into one
	# POST /api/bank/items and repaints BOTH grids from the response.
	#
	# XOR, not "either is a bank slot": bank-to-bank is a rearrange and falls
	# through to the normal cases below, because layout inside one container
	# moves no items and is nobody's business but the client's.
	#
	# The cell the player aimed at is deliberately ignored. The endpoint takes
	# an item and a quantity, not a position - the server merges onto an
	# existing stack and then takes the first free cell, the same placement rule
	# _add_to_backpack() already uses for loot. Honouring the drop position
	# would mean a second placement rule that disagrees with the first the
	# moment a stack is part-used.
	var source_type: String = str(data.get("source_type", ""))
	if (source_type == BANK_SLOT_TYPE) != (slot_type == BANK_SLOT_TYPE):
		transfer_requested.emit(source_slot, self)
		return

	# B1: empty target — move incoming here, clear source
	if is_empty():
		set_stack(incoming)
		source_slot.clear_stack()
		_emit_both_changed(source_slot)
		return

	# B2: target has matching stackable item — merge with overflow handling
	if stack.can_stack_with(incoming):
		var leftover: int = stack.add_to_stack(incoming.quantity)
		if leftover > 0:
			incoming.quantity = leftover
			source_slot.set_stack(incoming)
		else:
			source_slot.clear_stack()
		refresh_display()
		_emit_both_changed(source_slot)
		return

	# B3: different items — swap the two slots' stacks
	var our_old_stack: ItemStack = stack
	set_stack(incoming)
	source_slot.set_stack(our_old_stack)
	_emit_both_changed(source_slot)


func _emit_both_changed(source_slot: InventorySlot) -> void:
	slot_changed.emit(self)
	source_slot.slot_changed.emit(source_slot)
