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
# saves). the container is found via source_slot.get_parent(), since
# InventoryContainer._create_slots() parents every slot directly to itself
# — this works for ANY InventoryContainer-based UI (main inventory, bank,
# loot bag), not just one specific context.
#
# SCENE SETUP (required, not done here — can't edit .tscn from chat):
# 1. add a Control-derived node (TextureButton works well for a trash-icon
#    look) somewhere on the inventory screen.
# 2. attach this script to it.
# 3. add a ConfirmationDialog as its CHILD, named exactly "confirmationdialog"
#    (unique within this node, does not need the % unique-name flag since
#    we look it up via $ as a direct child).
# that's the whole setup — Godot calls _can_drop_data/_drop_data
# automatically during a drag gesture, no signal wiring needed for that part.
extends Control
class_name TrashSlot


# =============================================================================
# STATE
# =============================================================================

# holds the pending drop's data while the confirmation dialog is open, so
# _on_delete_confirmed can act on it after the player actually confirms.
var _pending_source_slot: InventorySlot = null
var _pending_stack: ItemStack = null


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var confirm_dialog: ConfirmationDialog = get_node_or_null("confirmationdialog")


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	if confirm_dialog != null:
		if not confirm_dialog.confirmed.is_connected(_on_delete_confirmed):
			confirm_dialog.confirmed.connect(_on_delete_confirmed)
		if not confirm_dialog.canceled.is_connected(_on_delete_canceled):
			confirm_dialog.canceled.connect(_on_delete_canceled)


# =============================================================================
# DRAG AND DROP — TARGET
# =============================================================================

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	# same shape check inventoryslot.gd uses for its own drop targets, plus
	# refusing hotbar-origin drags — a hotbar slot is just a REFERENCE to a
	# real inventory stack (see inventoryslot.gd's CASE A comment), not the
	# item itself. deleting should happen from the real inventory slot,
	# which naturally clears the hotbar reference too as a side effect.
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if not data.has("stack") or not data.has("source_slot"):
		return false
	if data.get("source_type", "") == "hotbar":
		return false
	# don't accept a second drop while a confirmation is already pending
	if confirm_dialog != null and confirm_dialog.visible:
		return false
	return true


func _drop_data(_at_position: Vector2, data: Variant) -> void:
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
	confirm_dialog.dialog_text = "Delete %s%s? This cannot be undone." % [display_name, qty_text]
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
	var container: Node = _pending_source_slot.get_parent()
	if container != null and container.has_method("remove_stack_at"):
		container.remove_stack_at(_pending_source_slot.slot_index)
	else:
		push_warning("TrashSlot: parent of source_slot has no remove_stack_at() — clearing slot directly as a fallback, but this will NOT persist to save")
		_pending_source_slot.clear_stack()

	_pending_source_slot = null
	_pending_stack = null


func _on_delete_canceled() -> void:
	_pending_source_slot = null
	_pending_stack = null
