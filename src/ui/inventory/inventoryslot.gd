# inventoryslot.gd — a single inventory slot. displays one ItemStack (icon +
# quantity), handles hover highlighting, tooltips, right-click use, double-click
# quick-transfer, and drag-and-drop between slots.
#
# slot_type distinguishes contexts ("inventory", "hotbar", "bank", "lootbag")
# so behavior and drag rules can vary. drag-and-drop is container-agnostic:
# any slot can drop onto any other slot, which is what lets items move freely
# between inventory, bank, hotbar, and loot bags.
#
# visual state:
# three styleboxes — normal, hover, and linked (gold border for items with
# a hotbar assignment). the linked style is queried per-frame from the parent
# container so hotbar changes are reflected immediately across all slots.
#
# drop cases:
# - CASE A: source is HotbarSlot → reference-clear only (no item transfer)
# - CASE B1: target empty → move stack from source to here
# - CASE B2: target matches → merge stacks with overflow to source
# - CASE B3: target differs → swap stacks
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

var is_hovered: bool = false
var is_selected: bool = false

# StyleBox, NOT StyleBoxFlat. A slot's face is whatever the theme hands over,
# and since the hotbar's is a piece of the artist's tile art it is a
# StyleBoxTexture - which is not a StyleBoxFlat and never will be. Typed
# narrowly, `style is StyleBoxTexture` is not a check that fails at runtime,
# it is one Godot refuses to compile: "Expression is of type StyleBoxFlat so
# it can't be of type StyleBoxTexture."
var style_normal: StyleBox = null
var style_hover:  StyleBox = null
var style_linked: StyleBox = null


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var icon_rect: TextureRect = $centercontainer/icon
@onready var quantity_label: Label = $quantitylabel


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_build_styles()
	_update_style()
	refresh_display()

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


# =============================================================================
# STYLE
# =============================================================================

# A SLOT'S THREE FACES - resting, hovered, and linked to the hotbar - are all
# DERIVED from whatever stylebox the theme hands over, never written out here.
# That is what lets one slot be a flat panel drawn by the theme and another be
# a piece of the artist's own tile art, with no code between them knowing
# which.
#
# HOW A STATE IS SHOWN DEPENDS ON WHAT THE STYLE IS. A flat box has a bg and a
# border to change; a texture has neither - it has art that must not be
# repainted, so it is TINTED instead. Same three states, same meaning, two
# ways of saying it.
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
		var flat_linked: StyleBoxFlat = flat.duplicate() as StyleBoxFlat
		flat_linked.border_color = Color(0.95, 0.80, 0.30, 1.0)

		style_normal = flat.duplicate() as StyleBoxFlat
		style_hover = flat_hover
		style_linked = flat_linked
	elif base is StyleBoxTexture:
		# THE ART IS THE SLOT. Lightening it for a hover and warming it for a
		# link keeps the artist's outline, highlight and corners exactly as
		# drawn - a border colour would have nothing to colour.
		var art: StyleBoxTexture = base as StyleBoxTexture
		var art_hover: StyleBoxTexture = art.duplicate() as StyleBoxTexture
		art_hover.modulate_color = Color(1.22, 1.20, 1.10, 1.0)
		var art_linked: StyleBoxTexture = art.duplicate() as StyleBoxTexture
		art_linked.modulate_color = Color(1.25, 1.05, 0.55, 1.0)

		style_normal = art.duplicate() as StyleBoxTexture
		style_hover = art_hover
		style_linked = art_linked
	else:
		style_normal = StyleBoxFlat.new()
		style_hover = StyleBoxFlat.new()
		style_linked = StyleBoxFlat.new()


func _update_style() -> void:
	if style_normal == null or style_hover == null:
		return

	if is_hovered or is_selected:
		add_theme_stylebox_override("panel", style_hover)
	elif _is_linked_to_hotbar() and style_linked != null:
		add_theme_stylebox_override("panel", style_linked)
	else:
		add_theme_stylebox_override("panel", style_normal)


func _is_linked_to_hotbar() -> bool:
	if is_empty():
		return false

	var parent_container: Node = get_parent()
	if parent_container == null:
		return false
	if not parent_container.has_method("is_item_linked"):
		return false

	return parent_container.is_item_linked(stack.data.item_id)


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
		_update_style()
		return

	icon_rect.texture = stack.data.icon
	icon_rect.modulate = stack.data.icon_tint
	if stack.quantity > 1:
		quantity_label.text = str(stack.quantity)
	else:
		quantity_label.text = ""

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
	# Builds the icon that follows the pointer during a drag. Shared with
	# HotbarSlot so both kinds of slot drag identically — they used to keep
	# separate copies of this and could drift apart.
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
	# Defaulted so HotbarSlot's call site keeps working unchanged; it passes its
	# own icon_rect.modulate, which is the same value by construction.
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

	# CASE A — drag from HotbarSlot. hotbar is just a reference layer; the
	# actual stack already lives in inventory. clearing the hotbar removes
	# the link without touching real inventory contents.
	if source_slot is HotbarSlot:
		source_slot.clear()
		source_slot.slot_changed.emit(source_slot)
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
