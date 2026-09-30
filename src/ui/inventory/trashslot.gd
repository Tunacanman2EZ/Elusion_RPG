# trashslot.gd — drag-and-drop delete target for the inventory screen.
# drag any InventorySlot's stack here to discard it permanently.
#
# requires confirmation before the delete actually commits — no silent,
# one-drop destroy. this project has a 1/216 pet drop rate; a fat-fingered
# drag shouldn't be able to erase something irreplaceable.
#
# uses the SAME drag-data contract as inventoryslot.gd's _get_drag_data():
#   { "stack": ItemStack, "source_slot": InventorySlot, "source_type": String }
# so any existing draggable slot can drop here without needing to know
# TrashSlot exists — no changes needed to inventoryslot.gd itself.
#
# persistence: deletion goes through the owning InventoryContainer's
# remove_stack_at(index) — the same method any other removal path uses, and
# the one actually tied to inventory_changed (the signal that triggers
# saves). the container is the slot's home_container, NOT its parent: a bag
# cell's parent is its grid, but a hotbar key's parent is the hotbar's row,
# while the cell it is belongs to the player's backpack. get_parent() is kept
# as a fallback for a slot nothing ever stamped. this works for ANY
# InventoryContainer-based UI (main inventory, bank, a hotbar key), not just
# one specific context.
#
# SCENE SETUP — how inventory.tscn and bankinventory.tscn both build it:
# 1. a PanelContainer with theme_type_variation = &"PanelSocket", so the trash
#    wears the same socket art as every inventory slot and reads as a place
#    you can put an item rather than as a decoration beside the grid.
# 2. this script on it.
# 3. a ConfirmationDialog as its CHILD, named exactly "confirmationdialog".
# 4. an icon inside, on a CenterContainer - and BOTH with mouse_filter IGNORE.
#    That last part is not cosmetic. A drop is delivered to the control under
#    the cursor, and an icon left on its default filter sits on top of this
#    node and swallows the drag, so the trash stops accepting anything and
#    nothing says why. The suite checks both filters.
# Godot calls _can_drop_data/_drop_data automatically during a drag gesture,
# no signal wiring needed for that part.
#
# IT GLOWS RED WHILE SOMETHING DROPPABLE IS OVER IT, and only then. A drag it
# would refuse - a second one while a confirmation is already open - does not
# light it up; a target that glows and then refuses is worse than one that
# never glowed. The glow is a tinted copy
# of the socket, the same way inventoryslot.gd tints its own socket for hover.
extends Control
class_name TrashSlot


# =============================================================================
# STATE
# =============================================================================

# holds the pending drop's data while the confirmation dialog is open, so
# _on_delete_confirmed can act on it after the player actually confirms.
var _pending_source_slot: InventorySlot = null
var _pending_stack: ItemStack = null

# The socket at rest and the socket glowing. StyleBox, not StyleBoxTexture: the
# theme decides which kind a panel wears, and this must not fail to compile the
# day that changes - see the same note in inventoryslot.gd.
var _style_idle: StyleBox = null
var _style_hot: StyleBox = null
var _hot: bool = false

# Red, but not alarm-red: it is a warning that you are about to be ASKED, not a
# deletion. The confirmation dialog is still the only thing that destroys.
const HOT_TINT := Color(1.55, 0.55, 0.45, 1.0)


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var confirm_dialog: ConfirmationDialog = get_node_or_null("confirmationdialog")


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_build_styles()
	if confirm_dialog != null:
		if not confirm_dialog.confirmed.is_connected(_on_delete_confirmed):
			confirm_dialog.confirmed.connect(_on_delete_confirmed)
		if not confirm_dialog.canceled.is_connected(_on_delete_canceled):
			confirm_dialog.canceled.connect(_on_delete_canceled)


# =============================================================================
# DRAG AND DROP — TARGET
# =============================================================================

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	# Asked every frame the cursor is over this during a drag, which makes it
	# exactly the right place to decide the glow: lit when the answer is yes.
	var accepted: bool = _accepts(data)
	_set_hot(accepted)
	return accepted


func _notification(what: int) -> void:
	# OFF WHEN THE CURSOR LEAVES AND WHEN THE DRAG ENDS, and both are needed.
	# Leaving covers "dragged over it and away"; drag-end covers a drop anywhere
	# else, or a cancelled drag, while still over it - otherwise the trash would
	# stay lit after the item had gone back where it came from.
	if what == NOTIFICATION_MOUSE_EXIT or what == NOTIFICATION_DRAG_END:
		_set_hot(false)


func _accepts(data: Variant) -> bool:
	# same shape check inventoryslot.gd uses for its own drop targets.
	#
	# A HOTBAR KEY IS ACCEPTED. It used to be refused, because a key held only
	# a reference to a bag item and "deleting" it would have destroyed nothing.
	# It holds the item itself now, so dropping a key's stack here deletes that
	# stack, exactly like a bag cell's.
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if not data.has("stack") or not data.has("source_slot"):
		return false
	# don't accept a second drop while a confirmation is already pending
	if confirm_dialog != null and confirm_dialog.visible:
		return false
	return true


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_set_hot(false)
	var source_slot: InventorySlot = data["source_slot"]
	if source_slot == null or source_slot.is_empty():
		return

	_pending_source_slot = source_slot
	_pending_stack = data["stack"]  # already a duplicate, made by _get_drag_data

	_show_confirmation()


func _show_confirmation() -> void:
	if confirm_dialog == null or _pending_stack == null or _pending_stack.data == null:
		# no dialog wired up in the scene yet — fail loud rather than
		# silently deleting without confirmation, which would defeat the
		# whole point of requiring one.
		push_warning("TrashSlot: no confirmationdialog child found (or invalid stack) — refusing to delete without a confirmation step. Add a ConfirmationDialog child named 'confirmationdialog'.")
		_pending_source_slot = null
		_pending_stack = null
		return

	var display_name: String = _pending_stack.data.display_name
	var qty_text: String = (" x%d" % _pending_stack.quantity) if _pending_stack.quantity > 1 else ""
	# ITS OWN WORDS, NOT GODOT'S. Neither scene titles the dialog, so it opened
	# as "Please Confirm..." over an OK button, beside a row that says "Drag
	# here to destroy". One verb, from the row to the button.
	confirm_dialog.title = "Destroy item"
	confirm_dialog.ok_button_text = "Destroy"
	confirm_dialog.dialog_text = "Destroy %s%s? This cannot be undone." % [display_name, qty_text]
	confirm_dialog.popup_centered()


# =============================================================================
# CONFIRMATION RESULT
# =============================================================================

func _on_delete_confirmed() -> void:
	if _pending_source_slot == null:
		return

	# route through the owning container's remove_stack_at() rather than
	# clearing the slot directly — this is what actually emits
	# inventory_changed and triggers a save. see class comment for why
	# slot_changed alone (the original approach here) doesn't persist.
	var container: Node = _pending_source_slot.home_container \
		if _pending_source_slot.home_container != null else _pending_source_slot.get_parent()
	if container != null and container.has_method("remove_stack_at"):
		container.remove_stack_at(_pending_source_slot.slot_index)
	else:
		push_warning("TrashSlot: source_slot's container has no remove_stack_at() — clearing slot directly as a fallback, but this will NOT persist to save")
		_pending_source_slot.clear_stack()

	_pending_source_slot = null
	_pending_stack = null


func _on_delete_canceled() -> void:
	_pending_source_slot = null
	_pending_stack = null


# =============================================================================
# THE GLOW
# =============================================================================

func _build_styles() -> void:
	var base: StyleBox = get_theme_stylebox("panel")
	if base == null:
		return
	_style_idle = base.duplicate()
	var hot: StyleBox = base.duplicate()
	if hot is StyleBoxTexture:
		(hot as StyleBoxTexture).modulate_color = HOT_TINT
	elif hot is StyleBoxFlat:
		var flat: StyleBoxFlat = hot as StyleBoxFlat
		flat.bg_color = flat.bg_color.lerp(Color(0.55, 0.12, 0.08, flat.bg_color.a), 0.6)
		flat.border_color = Color(0.95, 0.3, 0.22, 1.0)
	_style_hot = hot
	add_theme_stylebox_override("panel", _style_idle)


func _set_hot(on: bool) -> void:
	if on == _hot:
		return
	_hot = on
	if _style_idle == null or _style_hot == null:
		# No panel style to tint - a plain Control carrying this script. Tint
		# the node instead, which is cruder but still says the same thing.
		self_modulate = HOT_TINT if on else Color.WHITE
		return
	add_theme_stylebox_override("panel", _style_hot if on else _style_idle)


func is_hot() -> bool:
	return _hot
