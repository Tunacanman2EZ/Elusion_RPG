# equipmentslot.gd — one square of the equipment panel: the helm, the chest,
# the weapon hand. Eight of them, laid out as a paper doll in equipmentpanel.tscn.
#
# =============================================================================
# IT EXTENDS InventorySlot, AND OVERRIDES EVERY PART THAT MOVES AN ITEM
# =============================================================================
# The inheritance is for the LOOK and the HOVER: the 48x48 panel, the styles
# built off the theme, the icon and its tint, the tooltip on mouse-over. Those
# are already right, already tested by being the same square the player has
# been looking at all game, and duplicating them would mean two definitions of
# what a slot looks like that drift the first time one is restyled.
#
# Everything about MOVING an item is replaced outright, because an equipment
# slot does not hold one:
#
#     _get_drag_data   -> null           nothing can be dragged out
#     _can_drop_data   -> own rules      only gear that fits THIS square
#     _drop_data       -> a signal       the panel decides, nothing moves here
#
# The overrides are total — none of them calls super() — so the parent's
# stack-moving logic cannot leak through a branch nobody thought about.
#
# WHY NOTHING MOVES. player.equipped maps a slot name to an item_id; the item
# itself never leaves the backpack. See the long note on `equipped` in
# player.gd for why that shape was chosen over an equipment container. The
# visible consequence here is that equipping a sword does not empty the bag
# cell it came from, which is deliberate and is the same thing the hotbar
# already does — hotbarslot.gd calls itself "just a reference layer".
extends InventorySlot
class_name EquipmentSlot


# =============================================================================
# SIGNALS
# =============================================================================
# REPORTED, NOT PERFORMED. A slot knows which square it is and what was
# dropped on it; it does not know whether the character may wear the thing,
# where that is saved, or what else on screen has to redraw afterwards. The
# panel owns all of that, so the slot's whole job is to say what happened.

signal equip_requested(slot_name: String, item_id: String)


# =============================================================================
# CONFIGURATION
# =============================================================================

# Which square this is: "weapon", "helm", "chest", "legs", "boots", "shield",
# "ring", "amulet". Set per-instance in equipmentpanel.tscn.
#
# THE SAME STRING THE SAVE USES, and the server's saves.equipment column, and
# ItemData.slot_name(). One vocabulary, derived from ItemData.EquipSlot — see
# the note beside that function for what a second copy of it cost last time.
@export var equip_slot_name: String = ""

# Shown in the empty square so the panel reads as a body rather than a grid of
# holes. "Helm", "Off hand", and so on.
@export var empty_hint: String = ""


# =============================================================================
# STATE
# =============================================================================

# The character whose gear this shows. Used only to grey a square out when the
# dragged item is one this class or level cannot wear — the refusal itself is
# the server's, and the panel checks again before it saves.
var _player: Node = null


func set_player(p: Node) -> void:
	_player = p


# =============================================================================
# DRAG AND DROP
# =============================================================================

func _get_drag_data(_at_position: Vector2) -> Variant:
	# NOTHING COMES OUT BY DRAGGING. There is no second container for it to go
	# to — the item never left the backpack — so a drag out would have to mean
	# "unequip", which is a different gesture wearing a familiar one's clothes.
	# Right-click does that, and says so in the panel's own comment.
	return null


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("stack"):
		return false

	var incoming: ItemStack = data["stack"]
	if incoming == null or not incoming.is_valid():
		return false

	# THIS SQUARE, not any square. A helm dropped on the chest is refused here
	# rather than silently redirected: the cursor going dead over the wrong
	# slot is how a player learns where a piece goes, and moving it for them
	# teaches nothing and looks like a bug the first time it guesses wrong.
	if ItemData.slot_name(int(incoming.data.equip_slot)) != equip_slot_name:
		return false

	# THE COURTESY CHECK, not the rule. player.equip_check() is the same three
	# questions gamedata.equip_check() asks on the server; this one just makes
	# the cursor honest before the click. A player with no character attached
	# — the panel open before set_player() has run — gets the permissive
	# answer, and the panel checks again before anything is saved.
	if _player == null or not _player.has_method("equip_check"):
		return true

	var verdict: Dictionary = _player.equip_check(incoming.data.item_id)
	return bool(verdict.get("ok", false))


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY or not data.has("stack"):
		return

	var incoming: ItemStack = data["stack"]
	if incoming == null or not incoming.is_valid():
		return

	# NOTHING IS MOVED, CLEARED OR SET HERE. The panel writes player.equipped,
	# saves, and repaints every square including this one. Writing the icon
	# here as well would be a second source of truth that is right until the
	# save is refused.
	equip_requested.emit(equip_slot_name, incoming.data.item_id)


# =============================================================================
# DISPLAY
# =============================================================================

func refresh_display() -> void:
	super.refresh_display()

	# LOOKED UP RATHER THAN @onready, and that is not fussiness. The parent's
	# _ready() is what calls this, and a subclass's @onready assignments are
	# injected into the subclass's own _ready — which does not exist here. The
	# reference would be null on the one call that happens at startup.
	if not is_node_ready():
		return
	var hint: Label = get_node_or_null("hintlabel") as Label
	if hint == null:
		return

	# THE HINT IS THE EMPTY STATE. Eight identical empty squares are a grid;
	# eight squares that say "Helm", "Chest", "Off hand" are a body, and a
	# player who has never seen this panel knows what goes where without
	# picking anything up.
	hint.visible = is_empty()
	hint.text = empty_hint if empty_hint != "" else equip_slot_name.capitalize()
