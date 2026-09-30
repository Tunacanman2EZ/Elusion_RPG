# hotbarslot.gd — one hotbar key. A real inventory cell, drawn on the bar.
#
# EACH KEY HOLDS THE ITEM ITSELF. Dragging a stack from the bag onto a key
# moves it there, the way equipping moves a piece onto the character - it is
# no longer in the bag. The keys are the player's backpack cells 20-29 (see
# InventoryContainer's "CELLS PAST THE GRID" and CARRY_CAPACITY in app.py), so
# the server stores, reconciles and clears them exactly like the bag.
#
# IT USED TO HOLD AN item_id POINTING INTO THE BAG, and that is the whole
# history of this file. The potion was drawn twice - in its bag cell and on its
# key - so the bag cell grew a gold "linked" tint to explain the second copy,
# the tooltip grew "Linked from inventory", a drag off the key had to clear a
# reference rather than move anything, and the trash had to refuse a key
# because deleting "it" would have deleted nothing. Every one of those existed
# to explain one item being in two places. Now it is in one, and they are gone.
#
# What is left is what makes a key look like a key: its size, and the type the
# drag rules and the trash read.
extends InventorySlot
class_name HotbarSlot


# HOW BIG A SLOT IS ON SCREEN. The art is 32x32 with a 7px frame, which leaves
# an 18px hole - too small for a 32px item icon, which is why a filled slot
# used to overflow its own frame and cover it completely. At 42 the tile is
# nine-patched (the frame stays pixel-exact, only the middle stretches) and the
# hole comes out at 28, which an item icon fits inside.
const SLOT_SIZE := Vector2(42, 42)

# The slot_type every key carries. Not a bank and not a loot bag, so a drag
# between a key and the bag is an ordinary move, and a drag from a key into the
# bank is a deposit like any other carried cell.
const HOTBAR_SLOT_TYPE := "hotbar"


func _ready() -> void:
	slot_type = HOTBAR_SLOT_TYPE
	custom_minimum_size = SLOT_SIZE
	super._ready()
